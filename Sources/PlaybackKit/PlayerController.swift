import AppKit

public enum PlaybackCommand: CaseIterable, Sendable {
    case previous, togglePlayPause, next
    public var eventID: String {
        switch self {
        case .previous: return "Prev"
        case .togglePlayPause: return "PlPs"
        case .next: return "Next"
        }
    }
    public func eventClass(for player: DesktopPlayer) -> String { player == .spotify ? "spfy" : "hook" }
}

// Commands always target the player selected at the time of the user's click.
// Never launch a player, retry a non-idempotent command, or fall through to another player.
public final class PlayerController {
    public typealias Sender = (DesktopPlayer, PlaybackCommand) throws -> Void
    private let sender: Sender
    private let isRunning: (DesktopPlayer) -> Bool

    public init(sender: Sender? = nil, isRunning: ((DesktopPlayer) -> Bool)? = nil) {
        self.sender = sender ?? { try PlayerAppleEvents(bundleIdentifier: $0.bundleIdentifier).perform($1, on: $0) }
        self.isRunning = isRunning ?? { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).isEmpty }
    }

    public func perform(_ command: PlaybackCommand, on player: DesktopPlayer) throws {
        guard isRunning(player) else { throw PlayerReadError.notRunning(player) }
        do { try sender(player, command) }
        catch {
            let code = (error as NSError).code
            if code == -1743 { throw PlayerReadError.denied(player) }
            throw PlayerReadError.unavailable(player, code)
        }
    }
}
