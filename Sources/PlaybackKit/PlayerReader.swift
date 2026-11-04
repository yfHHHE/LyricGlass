import AppKit
import Carbon
import CryptoKit
import LyricsCore

public enum DesktopPlayer: String, CaseIterable, Sendable {
    case spotify
    case appleMusic = "apple-music"
    public var label: String { self == .spotify ? "Spotify" : "Apple Music" }
    public var bundleIdentifier: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

public struct PlaybackSample {
    public let song: Song?
    public let position: Double
    public let playing: Bool
    public let sampledAt: Double
}

public enum PlayerPlaybackState { case notRunning, stopped, paused, playing }

public enum PlayerReadError: LocalizedError {
    case notRunning(DesktopPlayer), denied(DesktopPlayer), unavailable(DesktopPlayer, Int), changedTrack, musicMetadataUnavailable
    public var errorDescription: String? {
        switch self {
        case .notRunning(let player): return "打开 \(player.label) 桌面端并播放一首歌"
        case .denied(let player): return "请在系统设置 → 隐私与安全性 → 自动化中允许 LyricGlass 访问 \(player.label)"
        case .unavailable(let player, let code): return "\(player.label) 暂时没有响应（\(code)），请稍后重试"
        case .changedTrack: return "正在切歌…"
        case .musicMetadataUnavailable: return "请在 Apple Music 暂停后继续一次，或切换歌曲，以接收流媒体曲目信息"
        }
    }
}

// Playback observation uses public scripting properties only.
public final class PlayerReader {
    public typealias Property = (_ code: String, _ currentTrack: Bool) throws -> NSAppleEventDescriptor
    public let player: DesktopPlayer
    private let property: Property
    private let isRunning: () -> Bool
    private var cached: Song?
    private let notificationLock = NSLock()
    private var notifiedSong: Song?
    private var notificationReceived = false
    private var notificationRevision = 0
    private var observer: NSObjectProtocol?

    public init(player: DesktopPlayer, property: Property? = nil, isRunning: (() -> Bool)? = nil,
                observeNotifications: Bool = true) {
        self.player = player
        let events = PlayerAppleEvents(bundleIdentifier: player.bundleIdentifier)
        self.property = property ?? { try events.get($0, currentTrack: $1) }
        self.isRunning = isRunning ?? { !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty }
        if player == .appleMusic && observeNotifications {
            observer = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"),
                object: nil, queue: .main) { [weak self] note in
                self?.receiveAppleMusicNotification(note.userInfo ?? [:])
            }
        }
    }

    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) } }

    public func receiveAppleMusicNotification(_ info: [AnyHashable: Any]) {
        guard player == .appleMusic else { return }
        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let duration = (info["Total Time"] as? NSNumber)?.doubleValue ?? Double(info["Total Time"] as? String ?? "") ?? 0
        let valid = info["Player State"] as? String != "Stopped" && !title.isEmpty && duration.isFinite && duration > 0
        // Music may change duration precision on pause. Keep the same track identity.
        let resource = info["PersistentID"].map { String(describing: $0) } ?? ""
        let identity = (try? JSONEncoder().encode([title, artist, album, resource])) ?? Data()
        let id = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        notificationLock.withLock {
            notificationReceived = true
            notificationRevision += 1
            notifiedSong = valid ? Song(id: "apple-music:" + id, title: title, artist: artist, album: album, duration: duration / 1000) : nil
        }
    }

    private func clearNotification() {
        notificationLock.withLock { notificationReceived = false; notifiedSong = nil; notificationRevision += 1 }
    }

    // Probe only application-level state, without reading an idle player's track metadata.
    public func playbackState() throws -> PlayerPlaybackState {
        guard isRunning() else { cached = nil; clearNotification(); return .notRunning }
        do {
            let state = try property("pPlS", false).enumCodeValue
            if state == fourCC("kPSS") { cached = nil; clearNotification(); return .stopped }
            return state == fourCC("kPSP") ? .playing : .paused
        } catch {
            let code = (error as NSError).code
            if code == -1743 { throw PlayerReadError.denied(player) }
            throw PlayerReadError.unavailable(player, code)
        }
    }

    public func read() throws -> PlaybackSample {
        do {
            let notification = notificationLock.withLock { (received: notificationReceived, song: notifiedSong, revision: notificationRevision) }
            let state = try playbackState()
            if state == .notRunning { throw PlayerReadError.notRunning(player) }
            if state == .stopped {
                cached = nil; clearNotification()
                return .init(song: nil, position: 0, playing: false, sampledAt: ProcessInfo.processInfo.systemUptime)
            }
            if player == .appleMusic && notification.received {
                guard let song = notification.song else { throw PlayerReadError.musicMetadataUnavailable }
                let position = try property("pPos", false).doubleValue
                let sampledAt = ProcessInfo.processInfo.systemUptime
                guard position.isFinite else { throw PlayerReadError.unavailable(player, -1700) }
                guard notificationLock.withLock({ notificationRevision == notification.revision }) else { throw PlayerReadError.changedTrack }
                return .init(song: song, position: max(0, position), playing: state == .playing, sampledAt: sampledAt)
            }
            let idCode = player == .spotify ? "ID  " : "pPID"
            var rawID: String?
            do { rawID = try property(idCode, true).stringValue }
            catch {
                guard player == .appleMusic, [-1728, -1700].contains((error as NSError).code) else { throw error }
            }
            if rawID?.isEmpty == true || (player == .appleMusic && rawID?.allSatisfy({ $0 == "0" }) == true) { rawID = nil }
            if player == .spotify && (rawID ?? "").isEmpty { throw PlayerReadError.changedTrack }
            let id = rawID.map { player == .spotify ? $0 : "apple-music:" + $0 }
            if cached?.id != id || player == .appleMusic {
                cached = try readSong(id: id)
            }
            let position = try property("pPos", false).doubleValue
            let sampledAt = ProcessInfo.processInfo.systemUptime
            guard position.isFinite else { throw PlayerReadError.unavailable(player, -1700) }
            guard notificationLock.withLock({ notificationRevision == notification.revision }) else { throw PlayerReadError.changedTrack }
            if let rawID {
                guard try property(idCode, true).stringValue == rawID else { cached = nil; throw PlayerReadError.changedTrack }
            } else {
                guard try readSong(id: cached?.id) == cached else { cached = nil; throw PlayerReadError.changedTrack }
            }
            return .init(song: cached, position: max(0, position), playing: state == .playing, sampledAt: sampledAt)
        } catch let error as PlayerReadError { throw error }
        catch {
            let code = (error as NSError).code
            if code == -1743 { throw PlayerReadError.denied(player) }
            if player == .appleMusic && code == -1728 { throw PlayerReadError.musicMetadataUnavailable }
            throw PlayerReadError.unavailable(player, code)
        }
    }

    private func readSong(id: String?) throws -> Song {
        let title = try property("pnam", true).stringValue ?? ""
        let artist = try property("pArt", true).stringValue ?? ""
        let album = try property("pAlb", true).stringValue ?? ""
        // Spotify returns milliseconds despite its dictionary; Music returns seconds.
        let duration = try property("pDur", true).doubleValue / (player == .spotify ? 1000 : 1)
        guard !title.isEmpty, duration.isFinite, duration > 0 else { throw PlayerReadError.changedTrack }
        let fallback = SHA256.hash(data: try JSONEncoder().encode([title, artist, album, ""]))
            .map { String(format: "%02x", $0) }.joined()
        return Song(id: id ?? "apple-music:" + fallback, title: title, artist: artist, album: album, duration: duration)
    }
}

final class PlayerAppleEvents {
    private let target: NSAppleEventDescriptor
    init(bundleIdentifier: String) { target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier) }

    private func object(_ code: String, from container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("prop")), forKeyword: fourCC("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC("prop")), forKeyword: fourCC("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC(code)), forKeyword: fourCC("seld"))
        record.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: fourCC("from"))
        return record.coerce(toDescriptorType: fourCC("obj "))!
    }

    func get(_ code: String, currentTrack: Bool) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: fourCC("core"), eventID: fourCC("getd"),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object(code, from: currentTrack ? object("pTrk") : nil), forKeyword: keyDirectObject)
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 2)
        let code = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        guard code == 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
        guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw NSError(domain: NSOSStatusErrorDomain, code: -1700) }
        return result
    }

    func perform(_ command: PlaybackCommand, on player: DesktopPlayer) throws {
        let event = NSAppleEventDescriptor(eventClass: fourCC(command.eventClass(for: player)), eventID: fourCC(command.eventID),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 2)
        let code = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        guard code == 0 else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
    }
}

private func fourCC(_ string: String) -> UInt32 { string.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
