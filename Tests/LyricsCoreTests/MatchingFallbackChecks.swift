import Foundation
import LyricsCore

func checkReleaseMetadataAndCrossPlayerCache() {
    let spotify = Song(id: "spotify:track", title: "Pale Blue Eyes", artist: "The Velvet Underground", album: "The Velvet Underground", duration: 337)
    let music = Song(id: "music:track", title: "Pale Blue Eyes - 2014 Remaster", artist: spotify.artist, album: "45th Anniversary Super Deluxe", duration: 340)
    let record = LyricsRecord(trackName: spotify.title, artistName: spotify.artist, albumName: spotify.album, duration: 337,
                              syncedLyrics: "[00:05]one\n[00:10]two")
    checkTrue(LyricsProvider.matches(record, song: music))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let cache = LyricsDiskCache(directory: directory)
        try cache.store(record, song: spotify)
        checkTrue(cache.load(song: music)?.cached ?? false)
        checkNil(cache.load(song: .init(id: "cover", title: music.title, artist: "Other Artist", album: music.album, duration: music.duration)))
        checkNil(cache.load(song: .init(id: "live", title: "Pale Blue Eyes (Live)", artist: music.artist, album: music.album, duration: music.duration)))
        let duet = Song(id: "duet-a", title: "Example", artist: "Lead & Guest A", album: "First Album", duration: 200)
        try cache.store(.init(trackName: "Example", artistName: "Lead", albumName: "First Album", duration: 200,
                             syncedLyrics: "[00:05]one\n[00:10]two"), song: duet)
        checkNil(cache.load(song: .init(id: "duet-b", title: "Example", artist: "Lead & Guest B", album: "Second Album", duration: 200)))
    } catch { failures += 1; print("FAIL release cache: \(error)") }
    for title in ["Pale Blue Eyes (2014 Remastered)", "Pale Blue Eyes - Remastered", "Pale Blue Eyes (Album Version)"] {
        checkTrue(LyricsProvider.matches(record, song: .init(id: "edition", title: title, artist: spotify.artist, album: "Compilation", duration: 339)))
    }
    for title in ["Pale Blue Eyes (Live)", "Pale Blue Eyes (Acoustic)", "Pale Blue Eyes (Remix)", "Pale Blue Eyes (Radio Edit)"] {
        checkFalse(LyricsProvider.matches(record, song: .init(id: "version", title: title, artist: spotify.artist, album: spotify.album, duration: 337)))
    }
}

actor LRCLIBPlainFixture {
    var searches = 0
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let broad = !items.contains { $0.name == "artist_name" }
        var record: [String: Any] = ["trackName": "Example", "artistName": "Artist", "albumName": "Album", "duration": 200,
                                     "plainLyrics": "plain fixture", "instrumental": false]
        if url.path == "/api/search" { searches += 1 }
        if url.path == "/api/search" && broad { record["syncedLyrics"] = "[00:05]one\n[00:10]two" }
        let json: Any = url.path == "/api/get" ? record : [record]
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkLRCLIBPlainDoesNotStopSearch() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = LRCLIBPlainFixture()
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory, sources: [.lrclib])
    do {
        let record = try await provider.fetch(song: .init(id: "plain", title: "Example", artist: "Artist", album: "Album", duration: 200))
        checkTrue(record.hasSyncedLyrics)
        checkTrue(await fixture.searches >= 2)
    } catch { failures += 1; print("FAIL LRCLIB plain continuation: \(error)") }
}

actor CatalogPlainFixture {
    let source: LyricsSource
    let fourthCandidate: Bool
    var downloads: [String] = []
    init(_ source: LyricsSource, fourthCandidate: Bool = false) { self.source = source; self.fourthCandidate = fourthCandidate }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!, path = url.path
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
        let isSearch = path.contains("client_search_cp") || path == "/api/search/pc" || path == "/search"
        let json: [String: Any]
        if isSearch {
            let query = value(source == .qq ? "w" : (source == .netease ? "s" : "keyword"))
            let ids = fourthCandidate ? ["1", "2", "3", "4"] : (query == "Example" ? ["4"] : ["1"])
            let tracks: [[String: Any]] = ids.map { id in
                switch source {
                case .qq: return ["songmid": id, "songname": "Example", "albumname": "Album", "interval": 200 + Double(id)! / 10, "singer": [["name": "Artist"]]]
                case .netease: return ["id": Int(id)!, "name": "Example", "duration": 200000 + Double(id)! * 100, "artists": [["name": "Artist"]], "album": ["name": "Album"]]
                default: return ["id": id, "song": "Example", "singer": "Artist", "duration": 200000 + Double(id)! * 100, "accesskey": "fixture"]
                }
            }
            switch source {
            case .qq: json = ["code": 0, "data": ["song": ["list": tracks]]]
            case .netease: json = ["code": 200, "result": ["songs": tracks]]
            default: json = ["status": 200, "candidates": tracks]
            }
        } else if path == "/" { json = [:] }
        else {
            let id = value(source == .qq ? "songmid" : "id")
            downloads.append(id)
            let lyric = id == "4" ? "[00:05]one\n[00:10]two" : "plain fixture"
            switch source {
            case .qq: json = ["code": 0, "lyric": lyric]
            case .netease: json = ["code": 200, "lrc": ["lyric": lyric]]
            default: json = ["status": 200, "content": Data(lyric.utf8).base64EncodedString()]
            }
        }
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkCatalogsContinueAfterPlainCandidates() async {
    for source in [LyricsSource.qq, .netease, .kugou] {
        for fourth in [false, true] {
            let fixture = CatalogPlainFixture(source, fourthCandidate: fourth)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory, sources: [source])
            do {
                let record = try await provider.fetch(song: .init(id: "catalog", title: "Example", artist: "Artist", album: "Album", duration: 200))
                checkTrue(record.hasSyncedLyrics)
                checkTrue(await fixture.downloads.contains("4"))
            } catch { failures += 1; print("FAIL \(source) plain continuation: \(error)") }
        }
    }
}
