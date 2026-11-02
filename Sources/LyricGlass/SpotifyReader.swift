import AppKit
import Carbon
import LyricsCore

struct SpotifySample {
    let song: Song?
    let position: Double
    let playing: Bool
    let sampledAt: Double
}

enum SpotifyReadError: LocalizedError {
    case notRunning, denied, unavailable(Int), changedTrack
    var errorDescription: String? {
        switch self {
        case .notRunning: return "打开 Spotify 桌面端并播放一首歌"
        case .denied: return "请在系统设置 → 隐私与安全性 → 自动化中允许 LyricGlass 读取 Spotify"
        case .unavailable(let code): return "Spotify 暂时没有响应（\(code)），请稍后重试"
        case .changedTrack: return "正在切歌…"
        }
    }
}

// Uses the same public Apple-event properties as Spotify's installed scripting dictionary.
// No polling subprocess, developer account, token, accessibility or screen recording permission.
final class SpotifyReader {
    private var cached: Song?
    private let target = NSAppleEventDescriptor(bundleIdentifier: "com.spotify.client")

    func read() throws -> SpotifySample {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            cached = nil
            throw SpotifyReadError.notRunning
        }
        let state = try get("pPlS").enumCodeValue
        if state == fourCC("kPSS") {
            cached = nil
            return .init(song: nil, position: 0, playing: false, sampledAt: ProcessInfo.processInfo.systemUptime)
        }
        let track = property("pTrk")
        let id = try get("ID  ", from: track).stringValue ?? ""
        guard !id.isEmpty else { throw SpotifyReadError.changedTrack }
        if cached?.id != id {
            let title = try get("pnam", from: track).stringValue ?? ""
            let artist = try get("pArt", from: track).stringValue ?? ""
            let album = try get("pAlb", from: track).stringValue ?? ""
            // Spotify's dictionary says seconds, but the actual pDur value is milliseconds.
            let duration = try get("pDur", from: track).doubleValue / 1000
            cached = Song(id: id, title: title, artist: artist, album: album, duration: duration)
        }
        let position = try get("pPos").doubleValue
        let sampledAt = ProcessInfo.processInfo.systemUptime
        // A transition during the metadata reads must not attach the previous lyrics to a new track.
        guard try get("ID  ", from: track).stringValue == id else {
            cached = nil
            throw SpotifyReadError.changedTrack
        }
        return .init(song: cached, position: position, playing: state == fourCC("kPSP"), sampledAt: sampledAt)
    }

    private func property(_ name: String, from container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("prop")), forKeyword: fourCC("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC("prop")), forKeyword: fourCC("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC(name)), forKeyword: fourCC("seld"))
        record.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: fourCC("from"))
        return record.coerce(toDescriptorType: fourCC("obj "))!
    }

    private func get(_ name: String, from container: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: fourCC("core"), eventID: fourCC("getd"),
                                          targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(property(name, from: container), forKeyword: keyDirectObject)
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 2)
        } catch {
            let code = (error as NSError).code
            if code == -1743 { throw SpotifyReadError.denied }
            throw SpotifyReadError.unavailable(code)
        }
        let code = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        if code == -1743 { throw SpotifyReadError.denied }
        guard code == 0 else { throw SpotifyReadError.unavailable(Int(code)) }
        guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw SpotifyReadError.unavailable(-1700) }
        return result
    }

    private func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
