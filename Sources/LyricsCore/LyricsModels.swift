import Foundation

public enum LyricsSource: String, Codable, Sendable, CaseIterable {
    case lrclib, qq, lrcmux, kugou, netease
    public var label: String {
        switch self { case .lrclib: return "LRCLIB"; case .netease: return "网易"; case .qq: return "QQ Music"; case .kugou: return "酷狗"; case .lrcmux: return "lrcmux" }
    }
    public var website: URL {
        let address: String
        switch self {
        case .lrclib: address = "https://lrclib.net"
        case .netease: address = "https://music.163.com"
        case .qq: address = "https://y.qq.com"
        case .kugou: address = "https://www.kugou.com"
        case .lrcmux: address = "https://lrcmux.dev"
        }
        return URL(string: address)!
    }
}

public struct Song: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public init(id: String, title: String, artist: String, album: String, duration: Double) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public struct LyricsRecord: Codable, Sendable {
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?
    public let source: LyricsSource?
    public let artistAliases: [String]?
    public let upstreamSource: String?
    public var cached = false
    private enum CodingKeys: String, CodingKey {
        case trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics, source, artistAliases, upstreamSource
    }
    public var sourceKind: LyricsSource { source ?? .lrclib }
    public var sourceLabel: String {
        sourceKind.label + (upstreamSource.map { " · " + $0 } ?? "") + (cached ? " · 本地缓存" : "")
    }
    public var hasSyncedLyrics: Bool {
        let lines = LyricsTimeline(lrc: syncedLyrics ?? "").lines.filter { !$0.text.isEmpty }
        return Set(lines.map(\.time)).count >= 2 && lines.contains { $0.time > 0 }
    }

    public init(trackName: String, artistName: String, albumName: String? = nil, duration: Double,
                instrumental: Bool = false, plainLyrics: String? = nil, syncedLyrics: String? = nil,
                source: LyricsSource = .lrclib, artistAliases: [String]? = nil, upstreamSource: String? = nil) {
        self.trackName = trackName; self.artistName = artistName; self.albumName = albumName
        self.duration = duration; self.instrumental = instrumental
        self.plainLyrics = plainLyrics; self.syncedLyrics = syncedLyrics
        self.source = source; self.artistAliases = artistAliases
        self.upstreamSource = upstreamSource
    }
}

public enum LyricsLookupError: LocalizedError {
    case notFound, http(Int), unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let source): return "\(source)暂时不可用，可稍后重试或使用其他歌词源"
        case .notFound: return "没有找到匹配歌词，可从菜单导入 LRC"
        case .http(503): return "歌词服务正忙，可从菜单重试或导入本地 LRC"
        case .http(429): return "歌词请求过于频繁，请稍后从菜单重试"
        case .http(let status): return "歌词服务返回 HTTP \(status)，可从菜单重试"
        }
    }
}
