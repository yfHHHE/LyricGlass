import Foundation
import LyricsCore

actor LrcmuxFixture {
    enum Mode { case valid, cover, live, wrongDuration, untimed, invalidTimes }
    let mode: Mode
    init(_ mode: Mode) { self.mode = mode }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        checkEqual(url.host, "api.lrcmux.dev")
        checkEqual(url.path, "/get")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        checkEqual(query.first { $0.name == "level" }?.value, "line")
        checkEqual(query.first { $0.name == "strict" }?.value, "true")
        checkEqual(query.first { $0.name == "duration" }?.value, "100")
        var lines: [[String: Any]] = [["text": "one", "start": 5000, "end": 9000],
                                      ["text": "two", "start": 10000, "end": 12000],
                                      ["text": "", "start": 12000, "end": 13000]]
        if mode == .untimed { lines = [["text": "one"], ["text": "two"]] }
        if mode == .invalidTimes { lines = [["text": "negative", "start": -5000], ["text": "outside track", "start": 900000]] }
        let json: [String: Any] = [
            "track": ["title": mode == .live ? "Example (Live)" : "Example", "artist": mode == .cover ? "Other Artist" : "Artist",
                      "album": "Album", "duration": mode == .wrongDuration ? 120 : 100],
            "meta": ["level": mode == .untimed ? "none" : "line", "source": ["id": "fixture", "name": "Fixture catalog"]],
            "lines": lines
        ]
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkLrcmuxTimelineAttributionAndOfflineCache() async {
    guard let source = LyricsSource(rawValue: "lrcmux") else { checkTrue(false); return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = LrcmuxFixture(.valid)
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory, sources: [source])
    let song = Song(id: "lrcmux", title: "Example", artist: "Artist", album: "Album", duration: 100)
    do {
        let record = try await provider.fetch(song: song)
        checkEqual(record.sourceKind, source)
        checkTrue(record.sourceLabel.contains("Fixture catalog"))
        checkEqual(LyricsTimeline(lrc: record.syncedLyrics ?? "").pair(at: 6).current, "one")
        checkEqual(LyricsTimeline(lrc: record.syncedLyrics ?? "").pair(at: 12).current, "间奏 ♪")
        let offline = LyricsHTTPClient(sender: { _ in throw URLError(.notConnectedToInternet) })
        let cached = try await LyricsProvider(http: offline, cacheDirectory: directory, sources: [source]).fetch(song: song)
        checkTrue(cached.cached)
        checkEqual(cached.sourceKind, source)
        checkTrue(cached.sourceLabel.contains("Fixture catalog"))
    } catch { failures += 1; print("FAIL lrcmux timeline: \(error)") }
}

func checkLrcmuxRejectsWrongRecordingsAndUntimedText() async {
    guard let source = LyricsSource(rawValue: "lrcmux") else { checkTrue(false); return }
    let song = Song(id: "lrcmux-negative", title: "Example", artist: "Artist", album: "Album", duration: 100)
    for mode in [LrcmuxFixture.Mode.cover, .live, .wrongDuration, .untimed, .invalidTimes] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = LrcmuxFixture(mode)
        let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory, sources: [source])
        do {
            let record = try await provider.fetch(song: song)
            checkTrue(mode == .invalidTimes)
            checkFalse(record.hasSyncedLyrics)
        } catch LyricsLookupError.notFound { }
        catch { failures += 1; print("FAIL lrcmux recording validation: \(error)") }
        checkNil(LyricsDiskCache(directory: directory).load(song: song))
    }
}
