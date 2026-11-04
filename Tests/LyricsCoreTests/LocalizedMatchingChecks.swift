import Foundation
import LyricsCore

func checkLocalizedArtistIdentitiesKeepRecordingGuards() {
    let examples: [(String, String, String, String, Double)] = [
        ("夜晚的牠知道", "Shallow Levée", "淺堤", "婚禮之途", 310.68),
        ("小孩", "I'mdifficult", "我是機車少女", "小孩", 252.755),
        ("快一點，慢一點", "puppiebelly", "漢堡黃", "BURGER POP", 219.782),
        ("一起", "puppiebelly", "汉堡黄", "BURGER POP", 199.271),
        ("night night", "Andr & Whys Young", "Andr & 尹志英", "SKIN", 239.099)
    ]
    for (title, expected, actual, album, duration) in examples {
        let song = Song(id: "localized", title: title, artist: expected, album: album, duration: duration)
        checkTrue(LyricsProvider.matches(LyricsRecord(trackName: title, artistName: actual, albumName: album, duration: duration), song: song))
        checkFalse(LyricsProvider.matches(LyricsRecord(trackName: title + " (Live)", artistName: actual, albumName: album, duration: duration), song: song))
        checkFalse(LyricsProvider.matches(LyricsRecord(trackName: title, artistName: actual, albumName: album, duration: duration + 3), song: song))
        checkFalse(LyricsProvider.matches(LyricsRecord(trackName: title, artistName: "Other Artist", albumName: album, duration: duration), song: song))
    }
    let duet = Song(id: "duet", title: "night night", artist: "Andr & Whys Young", album: "SKIN", duration: 239)
    checkFalse(LyricsProvider.matches(.init(trackName: duet.title, artistName: "Andr & Other Guest", albumName: duet.album, duration: duet.duration), song: duet))
    checkFalse(LyricsProvider.matches(.init(trackName: duet.title, artistName: "Andr", albumName: "Different Album", duration: duet.duration), song: duet))
}

actor LocalizedSearchFixture {
    var searchedLocalizedArtist = false
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let json: [String: Any]
        if url.path.contains("client_search_cp") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "w" }?.value ?? ""
            searchedLocalizedArtist = searchedLocalizedArtist || query.contains("汉堡黄")
            json = ["code": 0, "data": ["song": ["list": [["songmid": "localized-recording", "songname": "快一点，慢一点",
                    "albumname": "BURGER POP", "interval": 219, "singer": [["name": "汉堡黄"]]]]]]]
        } else {
            json = ["code": 0, "lyric": "[00:05]fixture one\n[00:10]fixture two"]
        }
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkLocalizedQueriesReachTimedLyrics() async {
    let fixture = LocalizedSearchFixture()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory, sources: [.qq])
    let song = Song(id: "puppiebelly", title: "快一點，慢一點", artist: "puppiebelly", album: "BURGER POP", duration: 219.782)
    do {
        let record = try await provider.fetch(song: song)
        checkTrue(record.hasSyncedLyrics)
        checkEqual(record.sourceKind, .qq)
        checkTrue(await fixture.searchedLocalizedArtist)
        let otherPlayer = Song(id: "other-player", title: song.title, artist: "漢堡黃", album: song.album, duration: 219.8)
        checkTrue(LyricsDiskCache(directory: directory).load(song: otherPlayer)?.cached ?? false)
    } catch { failures += 1; print("FAIL localized query: \(error)") }
}
