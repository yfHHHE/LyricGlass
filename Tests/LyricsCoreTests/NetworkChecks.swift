import Foundation
import LyricsCore

actor RetryFixture {
    var calls = 0
    var delays: [Double] = []
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        calls += 1
        return (Data("{\"ok\":true}".utf8), HTTPURLResponse(url: request.url!, statusCode: calls == 1 ? 503 : 200,
                    httpVersion: nil, headerFields: ["Retry-After": "1"])!)
    }
    func sleep(_ seconds: Double) { delays.append(seconds) }
}

actor FallbackFixture {
    var calls: [String] = []
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url!
        calls.append(url.host! + url.path)
        let json: [String: Any]
        if url.host == "lrclib.net" {
            json = ["trackName": "Galaxies", "artistName": "Laura Veirs", "albumName": "Year of Meteors", "duration": 216,
                    "instrumental": false, "plainLyrics": "example plain words"]
        } else if url.path == "/api/search/pc" {
            json = ["code": 200, "result": ["songs": [["id": 21034540, "name": "Galaxies", "duration": 215600,
                        "artists": [["name": "Laura Veirs"]], "album": ["name": "Year of Meteors"]]]]]
        } else if url.path == "/api/song/lyric" {
            json = ["code": 200, "lrc": ["lyric": "[00:05]example one\n[00:10]example two"]]
        } else { json = [:] }
        return (try! JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkTimedFallback() async {
    let fixture = FallbackFixture()
    let http = LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in })
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = LyricsProvider(http: http, cacheDirectory: directory)
    do {
        let song = Song(id: "test-fallback", title: "Galaxies", artist: "Laura Veirs", album: "Year of Meteors", duration: 216)
        let record = try await provider.fetch(song: song)
        checkEqual(record.sourceKind, .netease)
        checkTrue(record.hasSyncedLyrics)
    } catch { failures += 1; print("FAIL timed fallback: \(error)") }
}

func checkCacheSurvivesRestartOffline() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = FallbackFixture()
    let online = LyricsProvider(http: LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in }), cacheDirectory: directory)
    let song = Song(id: "persisted", title: "Galaxies", artist: "Laura Veirs", album: "Year of Meteors", duration: 216)
    do {
        let first = try await online.fetch(song: song)
        checkFalse(first.cached)
        let offline = LyricsHTTPClient(sender: { _ in throw URLError(.notConnectedToInternet) }, sleep: { _ in })
        let restarted = LyricsProvider(http: offline, cacheDirectory: directory)
        let second = try await restarted.fetch(song: song)
        checkTrue(second.cached)
        checkTrue(second.hasSyncedLyrics)
        checkEqual(second.sourceKind, .netease)
        do {
            _ = try await LyricsProvider(http: offline, cacheDirectory: directory, sources: [.qq]).fetch(song: song)
            checkTrue(false)
        } catch let error as URLError { checkEqual(error.code, .notConnectedToInternet) }
    } catch { failures += 1; print("FAIL persistent cache: \(error)") }
}

func checkHTTPRetry() async {
    let fixture = RetryFixture()
    let client = LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { await fixture.sleep($0) })
    do {
        let result = try await client.data(for: URLRequest(url: URL(string: "https://lrclib.net/test")!))
        checkEqual(String(data: result, encoding: .utf8), "{\"ok\":true}")
        checkEqual(await fixture.calls, 2)
        let delays = await fixture.delays
        checkEqual(delays.count, 1)
        checkTrue(delays.first.map { $0 >= 1 } ?? false)
    } catch { failures += 1; print("FAIL retry: \(error)") }
}

actor QQFixture {
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url!
        var status = 200
        let json: [String: Any]
        if url.host == "lrclib.net" { status = 503; json = [:] }
        else if url.path == "/api/search/pc" { json = ["code": -462] }
        else if url.path.contains("client_search_cp") {
            json = ["code": 0, "data": ["song": ["list": [
                ["songmid": "remix", "songname": "一夜一夜一夜 (DJ Remix)", "albumname": "幾分之幾", "interval": 247, "singer": [["name": "卢广仲"]]],
                ["songmid": "short", "songname": "一夜一夜一夜", "albumname": "幾分之幾", "interval": 241, "singer": [["name": "卢广仲"]]],
                ["songmid": "right", "songname": "一夜一夜一夜", "albumname": "幾分之幾", "interval": 247, "singer": [["name": "卢广仲"]]]
            ]]]]
        } else if url.path.contains("fcg_query_lyric") {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "songmid" }?.value
            json = ["code": 0, "lyric": Data("[00:05]\(id ?? "wrong") one\n[00:10]example two".utf8).base64EncodedString()]
        } else { json = [:] }
        return (try! JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "0"])!)
    }
}

func checkQQFallback() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = QQFixture()
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in }), cacheDirectory: directory)
    do {
        let song = Song(id: "qq-fallback", title: "一夜一夜一夜", artist: "Crowd Lu", album: "幾分之幾", duration: 247)
        let record = try await provider.fetch(song: song)
        checkEqual(record.sourceKind, .qq)
        checkEqual(record.duration, 247)
        checkTrue(record.hasSyncedLyrics)
        checkEqual(LyricsTimeline(lrc: record.syncedLyrics ?? "").pair(at: 6).current, "right one")
    } catch { failures += 1; print("FAIL QQ fallback: \(error)") }
}

actor KugouFixture {
    var downloads: [String] = []
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url!
        var status = 200
        let json: [String: Any]
        if url.host == "lrclib.net" { status = 404; json = [:] }
        else if url.path == "/api/search/pc" { json = ["code": 200, "result": ["songs": []]] }
        else if url.path.contains("client_search_cp") { json = ["code": 0, "data": ["song": ["list": []]]] }
        else if url.host == "lyrics.kugou.com", url.path == "/search" {
            // This endpoint returns empty results for reordered or URL-style space encoding.
            checkTrue(url.absoluteString.contains("?keyword="))
            checkTrue(url.absoluteString.contains("+"))
            checkFalse(url.absoluteString.contains("%20"))
            checkTrue(url.absoluteString.contains("&duration=247000&client=pc&ver=1&man=yes"))
            json = ["status": 200, "candidates": [
                ["id": "remix", "song": "一夜一夜一夜 (DJ Remix)", "singer": "卢广仲", "duration": 247000, "accesskey": "fixture"],
                ["id": "short", "song": "一夜一夜一夜", "singer": "卢广仲", "duration": 241000, "accesskey": "fixture"],
                ["id": "cover", "song": "一夜一夜一夜", "singer": "Someone Else", "duration": 247000, "accesskey": "fixture"],
                ["id": "right", "song": "一夜一夜一夜", "singer": "卢广仲", "duration": 247000, "accesskey": "fixture+token"]
            ]]
        } else if url.host == "lyrics.kugou.com", url.path == "/download" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = items.first { $0.name == "id" }?.value ?? "wrong"
            downloads.append(id)
            checkEqual(items.first { $0.name == "fmt" }?.value, "lrc")
            checkTrue(url.absoluteString.contains("&accesskey=fixture%2Btoken&fmt=lrc"))
            json = ["status": 200, "content": Data("[00:05]\(id) one\n[00:10]example two".utf8).base64EncodedString()]
        } else { json = [:] }
        return (try! JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

func checkKugouFallback() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = KugouFixture()
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in }), cacheDirectory: directory)
    do {
        let song = Song(id: "kugou-fallback", title: "一夜一夜一夜", artist: "Crowd Lu", album: "", duration: 247)
        let record = try await provider.fetch(song: song)
        checkEqual(record.sourceKind.rawValue, "kugou")
        checkTrue(record.hasSyncedLyrics)
        checkEqual(LyricsTimeline(lrc: record.syncedLyrics ?? "").pair(at: 6).current, "right one")
        checkEqual(await fixture.downloads, ["right"])
        let offline = LyricsHTTPClient(sender: { _ in throw URLError(.notConnectedToInternet) }, sleep: { _ in })
        let restarted = try await LyricsProvider(http: offline, cacheDirectory: directory).fetch(song: song)
        checkTrue(restarted.cached)
        checkEqual(restarted.sourceKind.rawValue, "kugou")
    } catch { failures += 1; print("FAIL Kugou fallback: \(error)") }
}

actor ThrottleFixture {
    var calls = 0
    var waits = 0
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        calls += 1
        let status = request.url!.host == "lrclib.net" ? 429 : 200
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "60"])!)
    }
    func sleep() { waits += 1 }
}

func checkLongThrottle() async {
    let fixture = ThrottleFixture()
    let client = LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in await fixture.sleep() })
    for _ in 0..<2 {
        do { _ = try await client.data(for: URLRequest(url: URL(string: "https://lrclib.net/test")!)); checkTrue(false) }
        catch LyricsLookupError.http(429) { }
        catch { failures += 1; print("FAIL throttle: \(error)") }
    }
    do { _ = try await client.data(for: URLRequest(url: URL(string: "https://music.163.com/test")!)) }
    catch { failures += 1; print("FAIL alternate host: \(error)") }
    checkEqual(await fixture.calls, 2)
    checkEqual(await fixture.waits, 0)
}

actor CancellationFixture {
    var calls = 0
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) { calls += 1; throw CancellationError() }
}

func checkCancellation() async {
    let fixture = CancellationFixture()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }, sleep: { _ in }), cacheDirectory: directory)
    do {
        _ = try await provider.fetch(song: Song(id: "cancel", title: "Example", artist: "Example", album: "", duration: 100))
        checkTrue(false)
    } catch is CancellationError { }
    catch { failures += 1; print("FAIL cancellation propagation: \(error)") }
    checkEqual(await fixture.calls, 1)
}

func checkCorruptCache() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = FallbackFixture()
    let http = LyricsHTTPClient(sender: { await fixture.send($0) }, sleep: { _ in })
    let song = Song(id: "corrupt", title: "Galaxies", artist: "Laura Veirs", album: "Year of Meteors", duration: 216)
    do {
        _ = try await LyricsProvider(http: http, cacheDirectory: directory).fetch(song: song)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        checkEqual(files.count, 1)
        guard let file = files.first else { return }
        try Data("broken JSON".utf8).write(to: file)
        let provider = LyricsProvider(http: http, cacheDirectory: directory)
        let recovered = try await provider.fetch(song: song)
        checkFalse(recovered.cached)
        checkTrue(recovered.hasSyncedLyrics)
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        try await provider.clearCache()
        checkEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["notes.txt"])
    } catch { failures += 1; print("FAIL cache recovery: \(error)") }
}
