import Foundation

public struct Song: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public init(id: String, title: String, artist: String, album: String, duration: Double) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public struct LyricsRecord: Decodable, Sendable {
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(trackName: String, artistName: String, albumName: String? = nil, duration: Double,
                instrumental: Bool = false, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.trackName = trackName; self.artistName = artistName; self.albumName = albumName
        self.duration = duration; self.instrumental = instrumental
        self.plainLyrics = plainLyrics; self.syncedLyrics = syncedLyrics
    }
}

public enum LyricsLookupError: LocalizedError {
    case notFound, http(Int)
    public var errorDescription: String? {
        switch self {
        case .notFound: return "没有找到匹配歌词，可从菜单导入 LRC"
        case .http(503): return "歌词服务正忙，可从菜单重试或导入本地 LRC"
        case .http(429): return "歌词请求过于频繁，请稍后从菜单重试"
        case .http(let status): return "歌词服务返回 HTTP \(status)，可从菜单重试"
        }
    }
}

public struct LyricsProvider: Sendable {
    public init() {}

    public static func normalized(_ text: String) -> String {
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    public static func matches(_ record: LyricsRecord, song: Song) -> Bool {
        // Keep version names (live/remix/etc.); a studio lyric must not win for a live recording.
        normalized(record.trackName) == normalized(song.title)
            && normalized(record.artistName) == normalized(song.artist)
            && abs(record.duration - song.duration) <= 2
    }

    public func fetch(song: Song) async throws -> LyricsRecord {
        let query = [URLQueryItem(name: "track_name", value: song.title),
                     URLQueryItem(name: "artist_name", value: song.artist),
                     URLQueryItem(name: "album_name", value: song.album),
                     URLQueryItem(name: "duration", value: String(Int(song.duration.rounded())))]
        do {
            let data = try await request(path: "get", query: query)
            let record = try JSONDecoder().decode(LyricsRecord.self, from: data)
            if Self.matches(record, song: song) { return record }
        } catch LyricsLookupError.http(404) {
            // Search only after an exact miss; network errors must remain distinguishable from no lyrics.
        }
        try Task.checkCancellation()
        let data = try await request(path: "search", query: Array(query.prefix(2)))
        let candidates = try JSONDecoder().decode([LyricsRecord].self, from: data)
            .filter { Self.matches($0, song: song) }
        guard let best = candidates.sorted(by: { lhs, rhs in
            let l = lhs.syncedLyrics?.isEmpty == false, r = rhs.syncedLyrics?.isEmpty == false
            if l != r { return l }
            let la = Self.normalized(lhs.albumName ?? "") == Self.normalized(song.album)
            let ra = Self.normalized(rhs.albumName ?? "") == Self.normalized(song.album)
            if la != ra { return la }
            return abs(lhs.duration - song.duration) < abs(rhs.duration - song.duration)
        }).first else { throw LyricsLookupError.notFound }
        return best
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://lrclib.net/api/\(path)")!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("LyricGlass/0.1 (local macOS prototype)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else { throw LyricsLookupError.http(response.statusCode) }
        return data
    }
}
