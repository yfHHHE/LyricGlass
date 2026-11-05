import Foundation
import CryptoKit
import LyricsCore

actor RacingCatalogFixture {
    var active = 0
    var peak = 0
    var cancelledSlowSource = false

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        let url = request.url!
        let json: [String: Any]
        if url.host == "lrclib.net" {
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { cancelledSlowSource = true; throw error }
            json = ["trackName": "Example", "artistName": "Artist", "duration": 100,
                    "instrumental": false, "syncedLyrics": "[00:05]slow one\n[00:10]slow two"]
        } else if url.path.contains("client_search_cp") {
            try await Task.sleep(nanoseconds: 20_000_000)
            json = ["code": 0, "data": ["song": ["list": [["songmid": "right", "songname": "Example",
                    "albumname": "Album", "interval": 100, "singer": [["name": "Artist"]]]]]]]
        } else {
            json = ["code": 0, "lyric": "[00:05]fast one\n[00:10]fast two"]
        }
        return (try JSONSerialization.data(withJSONObject: json),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkFastSourceWinsAndCancelsSlowSource() async {
    let fixture = RacingCatalogFixture()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }),
                                  cacheDirectory: directory, sources: [.lrclib, .qq])
    let started = ProcessInfo.processInfo.systemUptime
    do {
        let record = try await provider.fetch(song: Song(id: "race", title: "Example", artist: "Artist", album: "Album", duration: 100))
        checkEqual(record.sourceKind, .qq)
        checkTrue(ProcessInfo.processInfo.systemUptime - started < 0.7)
        checkEqual(await fixture.peak, 2)
        checkTrue(await fixture.cancelledSlowSource)
    } catch { failures += 1; print("FAIL source race: \(error)") }
}

actor MissingCatalogFixture {
    var active = 0
    var peak = 0
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
    }
}

func checkSourceConcurrencyIsBounded() async {
    let fixture = MissingCatalogFixture()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { try await fixture.send($0) }), cacheDirectory: directory)
    do {
        _ = try await provider.fetch(song: Song(id: "missing", title: "Missing", artist: "Artist", album: "", duration: 100))
        checkTrue(false)
    } catch LyricsLookupError.notFound { }
    catch { failures += 1; print("FAIL bounded sources: \(error)") }
    checkEqual(await fixture.peak, 2)
}

func checkRecordingCacheReuseAndIsolation() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LyricsDiskCache(directory: directory)
    let song = Song(id: "spotify:original", title: "愛情的大壞蛋", artist: "Amazing Show", album: "美秀集團同名專輯", duration: 187.49)
    let record = LyricsRecord(trackName: "爱情的大坏蛋", artistName: "美秀集团", albumName: "美秀集团同名专辑", duration: 187,
                              syncedLyrics: "[00:05]one\n[00:10]two", source: .qq)
    do {
        try cache.store(record, song: song)
        let music = Song(id: "music:other", title: "爱情的大坏蛋", artist: "美秀集团", album: "美秀集团同名专辑", duration: 187.59)
        checkTrue(cache.load(song: music)?.cached ?? false)
        checkNil(cache.load(song: Song(id: song.id, title: song.title + " (Live)", artist: song.artist, album: song.album, duration: song.duration)))
        checkNil(cache.load(song: Song(id: song.id, title: song.title, artist: "Other Artist", album: song.album, duration: song.duration)))
        checkTrue(cache.load(song: Song(id: song.id, title: song.title, artist: song.artist, album: "Other Album", duration: song.duration))?.cached ?? false)
        checkNil(cache.load(song: Song(id: song.id, title: song.title, artist: song.artist, album: song.album, duration: 200)))
        let offline = LyricsHTTPClient(sender: { _ in throw URLError(.notConnectedToInternet) })
        let result = try await LyricsProvider(http: offline, cacheDirectory: directory).fetch(song: music)
        checkTrue(result.cached)
    } catch { failures += 1; print("FAIL recording cache reuse: \(error)") }
}

func checkLegacyCacheReusesRecordingWithoutRenewingExpiry() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let song = Song(id: "spotify:legacy", title: "Example", artist: "Artist", album: "Album", duration: 100)
    let record = LyricsRecord(trackName: "Example", artistName: "Artist", albumName: "Album", duration: 100,
                              syncedLyrics: "[00:05]one\n[00:10]two", source: .qq)
    let date = Date(timeIntervalSince1970: 1_000_000)
    struct LegacyEntry: Encodable { let schema = 1; let song: Song; let record: LyricsRecord; let savedAt: Date }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let key = SHA256.hash(data: try encoder.encode(song)).map { String(format: "%02x", $0) }.joined()
        try encoder.encode(LegacyEntry(song: song, record: record, savedAt: date)).write(to: directory.appendingPathComponent(key + ".json"))
        let cache = LyricsDiskCache(directory: directory)
        let other = Song(id: "music:new", title: song.title, artist: song.artist, album: song.album, duration: 100.1)
        checkTrue(cache.load(song: other, now: date)?.cached ?? false)
        checkNil(cache.load(song: other, now: date.addingTimeInterval(31 * 24 * 60 * 60)))
    } catch { failures += 1; print("FAIL legacy cache: \(error)") }
}

func checkSourceDeadlineAndParentCancellation() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let http = LyricsHTTPClient(sender: { _ in
        try await Task.sleep(nanoseconds: 2_000_000_000)
        throw URLError(.badServerResponse)
    })
    let provider = LyricsProvider(http: http, cacheDirectory: directory, sources: [.lrclib, .qq], sourceTimeout: 0.06)
    let song = Song(id: "deadline", title: "Example", artist: "Artist", album: "Album", duration: 100)
    let start = ProcessInfo.processInfo.systemUptime
    do { _ = try await provider.fetch(song: song); checkTrue(false) }
    catch let error as URLError { checkEqual(error.code, .timedOut) }
    catch { failures += 1; print("FAIL deadline: \(error)") }
    checkTrue(ProcessInfo.processInfo.systemUptime - start < 0.5)

    let task = Task { try await provider.fetch(song: song, forceReload: true) }
    try? await Task.sleep(nanoseconds: 20_000_000)
    task.cancel()
    do { _ = try await task.value; checkTrue(false) }
    catch is CancellationError { }
    catch { failures += 1; print("FAIL parent cancellation: \(error)") }
    checkNil(LyricsDiskCache(directory: directory).load(song: song))
}

actor UnavailableCatalogFixture {
    var calls = 0
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        calls += 1
        return (Data("{\"code\":-462}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

func checkBusinessFailuresCoolDownAndRefreshKeepsCache() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = UnavailableCatalogFixture()
    let provider = LyricsProvider(http: LyricsHTTPClient(sender: { await fixture.send($0) }), cacheDirectory: directory, sources: [.netease])
    let song = Song(id: "cooldown", title: "Example", artist: "Artist", album: "Album", duration: 100)
    for _ in 0..<2 {
        do { _ = try await provider.fetch(song: song); checkTrue(false) }
        catch LyricsLookupError.unavailable { }
        catch { failures += 1; print("FAIL business cooldown: \(error)") }
    }
    checkEqual(await fixture.calls, 2) // One guest setup + one failed search, across both lookups.
    let record = LyricsRecord(trackName: song.title, artistName: song.artist, albumName: song.album, duration: song.duration,
                              syncedLyrics: "[00:05]one\n[00:10]two", source: .netease)
    do {
        try LyricsDiskCache(directory: directory).store(record, song: song)
        let refreshed = try await provider.fetch(song: song, forceReload: true)
        checkTrue(refreshed.cached)
        checkEqual(await fixture.calls, 3) // Explicit refresh retries the source, retaining verified lyrics on failure.
    } catch { failures += 1; print("FAIL refresh cache fallback: \(error)") }
}

func checkDifferentDurationsKeepSeparateCacheEntries() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LyricsDiskCache(directory: directory)
    do {
        for duration in [100.0, 110.0] {
            let song = Song(id: "version:\(duration)", title: "Example", artist: "Artist", album: "Album", duration: duration)
            try cache.store(LyricsRecord(trackName: song.title, artistName: song.artist, albumName: song.album, duration: duration,
                                         syncedLyrics: "[00:05]one\n[00:10]two"), song: song)
        }
        for duration in [100.1, 110.1] {
            let song = Song(id: "another-player", title: "Example", artist: "Artist", album: "Album", duration: duration)
            checkTrue(cache.load(song: song)?.cached ?? false)
        }
    } catch { failures += 1; print("FAIL duration variants: \(error)") }
}
