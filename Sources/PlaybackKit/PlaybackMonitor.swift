import Foundation

public enum PlaybackMode: String, CaseIterable {
    case automatic = "auto", spotify, appleMusic = "apple-music"
    public var selectedPlayer: DesktopPlayer? { DesktopPlayer(rawValue: rawValue) }
    public var label: String { selectedPlayer?.label ?? "自动识别" }
}

public struct PlaybackUpdate {
    public let player: DesktopPlayer?
    public let result: Result<PlaybackSample, Error>
}

public enum PlaybackMonitorError: LocalizedError {
    case noPlayer
    public var errorDescription: String? { "打开 Spotify 或 Apple Music 桌面端并播放一首歌" }
}

// Call poll on one serial queue. Each player keeps its own metadata and permissions.
public final class PlaybackMonitor {
    private let readers: [DesktopPlayer: PlayerReader]
    private let preferred: DesktopPlayer
    private var current: DesktopPlayer?
    private var previouslyPlaying: Set<DesktopPlayer> = []
    private var previousMode: PlaybackMode?
    private var statusFailures: [DesktopPlayer: (error: Error, retryAt: Double)] = [:]

    public init(preferredPlayer: DesktopPlayer = .spotify, readers: [DesktopPlayer: PlayerReader]? = nil) {
        preferred = preferredPlayer
        self.readers = readers ?? Dictionary(uniqueKeysWithValues: DesktopPlayer.allCases.map { ($0, PlayerReader(player: $0)) })
    }

    public func retry() { statusFailures.removeAll() }

    public func poll(mode: PlaybackMode = .automatic, now: Double = ProcessInfo.processInfo.systemUptime) -> PlaybackUpdate {
        if previousMode != mode { previouslyPlaying = []; previousMode = mode }
        let candidates = mode.selectedPlayer.map { [$0] } ?? DesktopPlayer.allCases
        var states: [DesktopPlayer: PlayerPlaybackState] = [:]
        var failures: [DesktopPlayer: Error] = [:]
        for player in candidates {
            if let blocked = statusFailures[player], blocked.retryAt > now { failures[player] = blocked.error; continue }
            do {
                states[player] = try readers[player]?.playbackState() ?? .notRunning
                statusFailures.removeValue(forKey: player)
            } catch {
                failures[player] = error
                let denied: Bool
                if case PlayerReadError.denied = error { denied = true } else { denied = false }
                statusFailures[player] = (error, denied ? .infinity : now + 5)
            }
        }
        let ordered = [preferred] + DesktopPlayer.allCases.filter { $0 != preferred }
        let selected = mode.selectedPlayer ?? choose(states: states, ordered: ordered)
        current = selected
        guard let selected, let reader = readers[selected] else {
            return .init(player: nil, result: .failure(ordered.compactMap { failures[$0] }.first ?? PlaybackMonitorError.noPlayer))
        }
        if let failure = failures[selected] { return .init(player: selected, result: .failure(failure)) }
        let result = Result { try reader.read() }
        if case .failure(let error) = result, case PlayerReadError.denied = error {
            statusFailures[selected] = (error, .infinity)
        }
        return .init(player: selected, result: result)
    }

    private func choose(states: [DesktopPlayer: PlayerPlaybackState], ordered: [DesktopPlayer]) -> DesktopPlayer? {
        let playing = Set(states.filter { $0.value == .playing }.map(\.key))
        let started = playing.subtracting(previouslyPlaying)
        // A failed probe is unknown, not a pause. Recovery must not look like a new play action.
        for (player, state) in states {
            if state == .playing { previouslyPlaying.insert(player) }
            else { previouslyPlaying.remove(player) }
        }
        if started.count == 1 { return started.first }
        if let current, playing.contains(current) { return current }
        if let player = ordered.first(where: { playing.contains($0) }) { return player }
        if let current, states[current] != .notRunning { return current }
        return ordered.first { states[$0] != nil && states[$0] != .notRunning }
    }
}
