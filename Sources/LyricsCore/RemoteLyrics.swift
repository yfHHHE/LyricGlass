import Foundation

// Independent adapters for direct, anonymous lyric catalogs. No browser cookies or proxy servers.
struct RemoteLyrics {
    let http: LyricsHTTPClient

    func lrclib(_ song: Song) async throws -> [LyricsRecord] {
        var query = ["track_name": song.title, "artist_name": song.artist, "album_name": song.album]
        if song.duration <= 3600 { query["duration"] = String(Int(song.duration.rounded())) }
        do {
            let record: LyricsRecord = try await json("https://lrclib.net/api/get", query)
            if LyricsProvider.matches(record, song: song) { return [record] }
        } catch LyricsLookupError.http(404) { }
        let title = Self.simplified(SongMatcher.queryTitle(song.title))
        let queries = [
            ["track_name": song.title, "artist_name": song.artist],
            ["track_name": title, "artist_name": ArtistNames.queryName(song.artist)],
            ["track_name": title]
        ]
        var seen: Set<String> = []
        for query in queries {
            let key = query.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "&")
            guard seen.insert(key).inserted else { continue }
            let records: [LyricsRecord] = try await json("https://lrclib.net/api/search", query)
            let valid = records.filter { LyricsProvider.matches($0, song: song) }
            if !valid.isEmpty { return valid }
        }
        return []
    }

    func prepareNetEase() async throws {
        var request = URLRequest(url: URL(string: "https://music.163.com/")!)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        // Establish only this app's anonymous in-memory guest cookies, never the user's login session.
        _ = try await http.data(for: request)
    }

    func netease(_ song: Song) async throws -> [LyricsRecord] {
        let title = Self.simplified(SongMatcher.queryTitle(song.title))
        let queries = [title + " " + ArtistNames.queryName(song.artist), title]
        for query in queries {
            let reply: NetEaseSearch = try await json("https://music.163.com/api/search/pc",
                ["s": query, "offset": "0", "limit": "10", "type": "1"], post: true, referer: "https://music.163.com/")
            guard reply.code == 200 else { throw LyricsLookupError.unavailable("网易") }
            let candidates = (reply.result?.songs ?? []).compactMap { track -> (NetEaseTrack, LyricsRecord)? in
                let record = LyricsRecord(trackName: track.name, artistName: track.artists.map(\.name).joined(separator: " & "),
                    albumName: track.album.name, duration: track.duration / 1000, source: .netease,
                    artistAliases: track.artists.flatMap { ($0.alias ?? []) + ($0.transNames ?? []) + ($0.tns ?? []) })
                return LyricsProvider.matches(record, song: song) ? (track, record) : nil
            }.sorted { (SongMatcher.score($0.1, song: song) ?? 0) > (SongMatcher.score($1.1, song: song) ?? 0) }
            var results: [LyricsRecord] = []
            for (track, metadata) in candidates.prefix(2) {
                try Task.checkCancellation()
                let lyric: NetEaseLyrics = try await json("https://music.163.com/api/song/lyric",
                    ["id": String(track.id), "lv": "1", "kv": "-1", "tv": "-1"])
                guard lyric.code == 200 else { throw LyricsLookupError.unavailable("网易") }
                guard let lrc = lyric.lrc?.lyric, !lrc.isEmpty else { continue }
                let record = Self.withLyrics(lrc, metadata: metadata)
                results.append(record)
                if record.hasSyncedLyrics { return results }
            }
            if !results.isEmpty { return results }
        }
        return []
    }

    func qq(_ song: Song) async throws -> [LyricsRecord] {
        let title = Self.simplified(SongMatcher.queryTitle(song.title))
        let queries = [title + " " + ArtistNames.queryName(song.artist), title]
        for query in queries {
            let reply: QQSearch = try await json("https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                ["w": query, "format": "json", "n": "10", "p": "1"])
            guard reply.code == 0 else { throw LyricsLookupError.unavailable("QQ Music") }
            let candidates = (reply.data?.song?.list ?? []).compactMap { track -> (QQTrack, LyricsRecord)? in
                let record = LyricsRecord(trackName: track.songname, artistName: track.singer.map(\.name).joined(separator: " & "),
                    albumName: track.albumname, duration: track.interval, source: .qq,
                    artistAliases: track.singer.flatMap { ($0.alias ?? []) + ($0.transNames ?? []) + ($0.tns ?? []) })
                return LyricsProvider.matches(record, song: song) ? (track, record) : nil
            }.sorted { (SongMatcher.score($0.1, song: song) ?? 0) > (SongMatcher.score($1.1, song: song) ?? 0) }
            var results: [LyricsRecord] = []
            for (track, metadata) in candidates.prefix(2) {
                try Task.checkCancellation()
                let lyric: QQLyrics = try await json("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
                    ["songmid": track.songmid, "g_tk": "5381", "format": "json", "nobase64": "1"],
                    referer: "https://y.qq.com/portal/player.html")
                guard lyric.code == 0 else { throw LyricsLookupError.unavailable("QQ Music") }
                guard var lrc = lyric.lyric, !lrc.isEmpty else { continue }
                if !lrc.contains("["), let data = Data(base64Encoded: lrc), let text = String(data: data, encoding: .utf8) { lrc = text }
                let record = Self.withLyrics(lrc, metadata: metadata)
                results.append(record)
                if record.hasSyncedLyrics { return results }
            }
            if !results.isEmpty { return results }
        }
        return []
    }

    private func json<T: Decodable>(_ base: String, _ parameters: [String: String], post: Bool = false, referer: String? = nil) async throws -> T {
        var url = URLComponents(string: base)!
        url.queryItems = parameters.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!)
        if post { request.httpMethod = "POST" }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let data = try await http.data(for: request)
        // Some catalog responses use a JSONP envelope. Parse only JSON; never execute returned code.
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.hasPrefix("{"), !text.hasPrefix("["), let begin = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return try JSONDecoder().decode(T.self, from: Data(text[begin...end].utf8))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }

    private static func withLyrics(_ text: String, metadata: LyricsRecord) -> LyricsRecord {
        var lrc = text
        for (entity, replacement) in [("&#10;", "\n"), ("&#13;", "\r"), ("&#39;", "'"), ("&apos;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            lrc = lrc.replacingOccurrences(of: entity, with: replacement)
        }
        let plain = lrc.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LyricsRecord(trackName: metadata.trackName, artistName: metadata.artistName, albumName: metadata.albumName,
            duration: metadata.duration, plainLyrics: plain, syncedLyrics: lrc,
            source: metadata.sourceKind, artistAliases: metadata.artistAliases)
    }
}

private struct CatalogArtist: Decodable { let name: String; let alias: [String]?; let transNames: [String]?; let tns: [String]? }
private struct CatalogAlbum: Decodable { let name: String }
private struct NetEaseTrack: Decodable { let id: Int64; let name: String; let duration: Double; let artists: [CatalogArtist]; let album: CatalogAlbum }
private struct NetEaseSearch: Decodable {
    let code: Int
    let result: Results?
    struct Results: Decodable { let songs: [NetEaseTrack]? }
}
private struct NetEaseLyrics: Decodable {
    let code: Int
    let lrc: LRC?
    struct LRC: Decodable { let lyric: String? }
}
private struct QQTrack: Decodable { let songmid: String; let songname: String; let albumname: String; let interval: Double; let singer: [CatalogArtist] }
private struct QQSearch: Decodable {
    let code: Int
    let data: Results?
    struct Results: Decodable { let song: Songs? }
    struct Songs: Decodable { let list: [QQTrack]? }
}
private struct QQLyrics: Decodable { let code: Int; let lyric: String? }
