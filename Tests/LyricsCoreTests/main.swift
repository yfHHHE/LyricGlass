import Foundation
import LyricsCore

final class TimelineTests {
    func testTimestampsFractionsRepeatedTagsAndMetadata() {
        let timeline = LyricsTimeline(lrc: """
        [ar:Example]
        [00:15.123]C
        [00:05.5][00:10.50]A
        [00:12:25]B
        [00:99.00]invalid
        """)
        checkEqual(timeline.lines.map(\.time), [5.5, 10.5, 12.25, 15.123])
        checkEqual(timeline.lines.map(\.text), ["A", "A", "B", "C"])
        checkNil(timeline.index(at: 5.49))
        checkEqual(timeline.index(at: 5.5), 0)
        checkEqual(timeline.index(at: 10.5), 1)
    }

    func testOffsetAndBilingualSimultaneousLines() {
        let timeline = LyricsTimeline(lrc: "[offset:+500]\n[00:02.00]Hello\n[00:02.00]你好\n[00:02.00]你好")
        checkEqual(timeline.lines.first?.time, 1.5)
        checkEqual(timeline.pair(at: 1.5).current, "Hello · 你好")
        checkEqual(LyricsTimeline(lrc: "[offset:-250]\n[00:01]A").lines.first?.time, 1.25)
    }

    func testPreludeInterludeSeekBackwardAndFinalLine() {
        let timeline = LyricsTimeline(lrc: "[00:05]A\n[00:10]\n[00:15]B\n[00:20]C")
        checkEqual(timeline.pair(at: 0).current, "前奏 · 等待人声")
        checkEqual(timeline.pair(at: 0).next, "A")
        checkEqual(timeline.pair(at: 6).current, "A")
        checkEqual(timeline.pair(at: 6).next, "B")
        checkEqual(timeline.pair(at: 12).current, "间奏 ♪")
        checkEqual(timeline.pair(at: 16).current, "B")
        checkEqual(timeline.pair(at: 5).current, "A")
        checkEqual(timeline.pair(at: 25).current, "C")
        checkEqual(timeline.pair(at: 25).next, "")
        checkTrue(LyricsTimeline(lrc: "plain text").lines.isEmpty)
    }

    func testClockPauseSeekResumeAndStaleRead() {
        var clock = PlaybackClock()
        clock.sample(position: 6, duration: 30, playing: true, now: 100)
        checkEqual(clock.position(at: 100.5), 6.5)
        checkEqual(clock.position(at: 110), 8, "Stale Spotify data must freeze after two seconds")
        clock.sample(position: 7, duration: 30, playing: false, now: 101)
        checkEqual(clock.position(at: 110), 7)
        clock.sample(position: 18, duration: 30, playing: true, now: 111)
        checkEqual(clock.position(at: 111.25), 18.25)
        clock.sample(position: 2, duration: 30, playing: true, now: 112)
        checkEqual(clock.position(at: 112.25), 2.25)
        clock.sample(position: 29.8, duration: 30, playing: true, now: 113)
        checkEqual(clock.position(at: 114), 30)
    }

    func testMatchingRejectsDifferentRecordingAndDuration() {
        let song = Song(id: "a", title: "Yellow", artist: "Coldplay", album: "Parachutes", duration: 266)
        checkTrue(LyricsProvider.matches(.init(trackName: "YELLOW", artistName: "Coldplay", duration: 267), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Yellow (Live)", artistName: "Coldplay", duration: 266), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Yellow", artistName: "Another artist", duration: 266), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Yellow", artistName: "Coldplay", duration: 275), song: song))
        let chinese = Song(id: "b", title: "出現又離開（Live）", artist: "梁博", album: "", duration: 372)
        checkTrue(LyricsProvider.matches(.init(trackName: "出现又离开 (Live)", artistName: "梁博", duration: 372), song: chinese))
    }

    func testPlaybackToLyricsIntegration() {
        let timeline = LyricsTimeline(lrc: "[00:05]first\n[00:10]second\n[00:15]third")
        var clock = PlaybackClock()
        clock.sample(position: 9.8, duration: 30, playing: true, now: 100)
        checkEqual(timeline.pair(at: clock.position(at: 100.3)).current, "second")
        clock.sample(position: 10.1, duration: 30, playing: false, now: 100.3)
        checkEqual(timeline.pair(at: clock.position(at: 110)).current, "second")
        clock.sample(position: 5, duration: 30, playing: true, now: 110)
        checkEqual(timeline.pair(at: clock.position(at: 110.1)).current, "first")
        clock.sample(position: 16, duration: 30, playing: true, now: 111)
        checkEqual(timeline.pair(at: clock.position(at: 111.1)).current, "third")
    }

    func testEnglishArtistAliasMatchesChineseCatalog() {
        let song = Song(id: "alias", title: "一夜一夜一夜", artist: "Crowd Lu", album: "幾分之幾", duration: 247)
        let record = LyricsRecord(trackName: "一夜一夜一夜", artistName: "卢广仲", albumName: "几分之几", duration: 247)
        checkTrue(LyricsProvider.matches(record, song: song))
    }

    func testAmazingShowAliasKeepsRecordingChecks() {
        let song = Song(id: "amazing-show", title: "愛情的大壞蛋", artist: "Amazing Show", album: "美秀集團同名專輯", duration: 187)
        checkTrue(LyricsProvider.matches(.init(trackName: "爱情的大坏蛋", artistName: "美秀集团", albumName: "美秀集团同名专辑", duration: 187), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "爱情的大坏蛋 (DJ Remix)", artistName: "美秀集团", duration: 187), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "爱情的大坏蛋", artistName: "美秀集团", duration: 99), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "爱情的大坏蛋", artistName: "Another Show", duration: 187), song: song))
    }

    func testCollaboratorsAndVersionsStayDistinct() {
        let song = Song(id: "collab", title: "Afterglow (feat. Guest)", artist: "Lead, Guest", album: "Shared Album", duration: 200)
        checkTrue(LyricsProvider.matches(.init(trackName: "Afterglow", artistName: "Guest & Lead", albumName: "Shared Album", duration: 200), song: song))
        checkTrue(LyricsProvider.matches(.init(trackName: "Afterglow", artistName: "Lead", albumName: "Shared Album", duration: 201), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow", artistName: "Lead", albumName: "Another Album", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow", artistName: "Lead & Stranger", albumName: "Shared Album", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow", artistName: "LeadGuest", albumName: "Shared Album", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow (Live)", artistName: "Lead, Guest", albumName: "Shared Album", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow (DJ Remix)", artistName: "Lead, Guest", albumName: "Shared Album", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Afterglow - Live", artistName: "Lead", albumName: "Shared Album", duration: 200), song: song))
    }

    func testCatalogAliasesAndRealTimestamps() {
        let song = Song(id: "provider-alias", title: "Example", artist: "Catalog English Name", album: "Album", duration: 100)
        checkTrue(LyricsProvider.matches(.init(trackName: "Example", artistName: "艺名", duration: 100, artistAliases: ["Catalog English Name"]), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Example", artistName: "艺名", duration: 100), song: song))
        checkFalse(LyricsRecord(trackName: "Example", artistName: "Artist", duration: 100, syncedLyrics: "[00:00]title\n[00:00]artist").hasSyncedLyrics)
        checkTrue(LyricsRecord(trackName: "Example", artistName: "Artist", duration: 100, syncedLyrics: "[00:05]one\n[00:10]two").hasSyncedLyrics)
    }

    func testBilingualDisplayNamesNeedAlbumEvidence() {
        let song = Song(id: "bilingual", title: "Example", artist: "海風 Sea Breeze", album: "Room", duration: 200)
        checkTrue(LyricsProvider.matches(.init(trackName: "Example", artistName: "海风", albumName: "Room", duration: 200), song: song))
        checkTrue(LyricsProvider.matches(.init(trackName: "Example", artistName: "Sea Breeze", albumName: "Room", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Example", artistName: "海风", albumName: "Elsewhere", duration: 200), song: song))
        checkFalse(LyricsProvider.matches(.init(trackName: "Example", artistName: "Breeze", albumName: "Room", duration: 200), song: song))
    }

    func testCacheExpiryAndRecordingIdentity() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LyricsDiskCache(directory: directory)
        let date = Date(timeIntervalSince1970: 1_000_000)
        let song = Song(id: "same-id", title: "Example", artist: "Artist", album: "Album", duration: 100)
        let record = LyricsRecord(trackName: "Example", artistName: "Artist", albumName: "Album", duration: 100, syncedLyrics: "[00:05]one\n[00:10]two", source: .qq)
        do {
            try cache.store(record, song: song, now: date)
            checkTrue(cache.load(song: song, now: date)?.cached ?? false)
            checkNil(cache.load(song: song, now: date.addingTimeInterval(31 * 24 * 60 * 60)))
            checkNil(cache.load(song: Song(id: "same-id", title: "Example (Live)", artist: "Artist", album: "Album", duration: 100), now: date))
            checkNil(cache.load(song: Song(id: "same-id", title: "Example", artist: "Artist", album: "Album", duration: 120), now: date))
        } catch { failures += 1; print("FAIL cache identity: \(error)") }
    }
}


// A standalone runner keeps the prototype verifiable with Command Line Tools alone.
var failures = 0
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL line \(line): \(actual) != \(expected) \(message)") }
}
func checkNil<T>(_ value: T?, line: UInt = #line) { if value != nil { failures += 1; print("FAIL line \(line): expected nil") } }
func checkTrue(_ value: Bool, line: UInt = #line) { if !value { failures += 1; print("FAIL line \(line): expected true") } }
func checkFalse(_ value: Bool, line: UInt = #line) { checkTrue(!value, line: line) }

let suite = TimelineTests()
let cases: [(String, () -> Void)] = [
    ("Localized artist aliases retain version, guest and duration guards", checkLocalizedArtistIdentitiesKeepRecordingGuards),
    ("LRC timestamps and repeated tags", suite.testTimestampsFractionsRepeatedTagsAndMetadata),
    ("LRC offset and simultaneous translations", suite.testOffsetAndBilingualSimultaneousLines),
    ("Prelude, interlude and backwards seek", suite.testPreludeInterludeSeekBackwardAndFinalLine),
    ("Clock pause, resume, seek and stale samples", suite.testClockPauseSeekResumeAndStaleRead),
    ("Recording identity, duration and Chinese matching", suite.testMatchingRejectsDifferentRecordingAndDuration),
    ("Playback-to-lyrics integration", suite.testPlaybackToLyricsIntegration),
    ("English artist alias matches Chinese catalog", suite.testEnglishArtistAliasMatchesChineseCatalog),
    ("Amazing Show alias preserves recording checks", suite.testAmazingShowAliasKeepsRecordingChecks),
    ("Collaborators match without mixing recording versions", suite.testCollaboratorsAndVersionsStayDistinct),
    ("Provider aliases and usable timestamps", suite.testCatalogAliasesAndRealTimestamps),
    ("Bilingual display names require album evidence", suite.testBilingualDisplayNamesNeedAlbumEvidence),
    ("Cache expiry and recording identity", suite.testCacheExpiryAndRecordingIdentity),
    ("Apple Music seconds, pause and seek reach the lyric timeline", checkAppleMusicReadAndSeek),
    ("Apple Music streams use notifications without stale tracks", checkAppleMusicStreamingNotifications),
    ("Players keep distinct identities and report permission errors", checkPlayersStayIsolatedAndPermissionErrors),
    ("Music without an ID rejects mixed recordings and invalid notifications", checkMusicMissingIDAndInvalidNotification),
    ("Music pause metadata keeps a stable recording identity", checkMusicNotificationIdentitySurvivesPrecisionChanges),
    ("Music zero IDs do not reuse another song's lyrics", checkMusicZeroIDDoesNotReuseAnotherSong),
    ("Automatic mode follows Music while Spotify is paused", checkAutomaticPlayerFollowsPlayback),
    ("Automatic handoffs follow new playback and keep stable ties", checkAutomaticPlayerTransitionsStayStable),
    ("Automatic mode isolates denied and unresponsive players", checkAutomaticPermissionsAndRecovery),
    ("Manual mode pins a player and can return to automatic", checkManualModeOverridesAutomaticChoice),
    ("Automatic mode handles closed apps and missing stream metadata", checkAutomaticEmptyAndStreamingGap),
    ("Playback commands use each player's shipped scripting dictionary", checkPlaybackCommandDictionaries),
    ("Playback commands target only the selected player", checkPlaybackCommandsTargetOnlySelectedPlayer),
    ("Playback controls never launch a closed player", checkPlaybackControlsDoNotLaunchClosedPlayer),
    ("Control errors never retry or switch players", checkPlaybackControlErrorsDoNotRetryOrSwitchPlayers)
]
for (name, run) in cases {
    let before = failures
    run()
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
let asyncCases: [(String, () async -> Void)] = [
    ("Localized search names fetch timed lyrics and reuse recording cache", checkLocalizedQueriesReachTimedLyrics),
    ("lrcmux preserves milliseconds, attribution and offline cache", checkLrcmuxTimelineAttributionAndOfflineCache),
    ("lrcmux rejects covers, versions, duration mismatches and invalid timing", checkLrcmuxRejectsWrongRecordingsAndUntimedText),
    ("Fast valid sources win and cancel slow lookups", checkFastSourceWinsAndCancelsSlowSource),
    ("At most two lyric sources run concurrently", checkSourceConcurrencyIsBounded),
    ("Recording cache survives player and precision changes", checkRecordingCacheReuseAndIsolation),
    ("Legacy cache keeps identity checks and original expiry", checkLegacyCacheReusesRecordingWithoutRenewingExpiry),
    ("Source deadlines and track cancellation stop pending work", checkSourceDeadlineAndParentCancellation),
    ("Business failures cool down and failed refresh keeps cache", checkBusinessFailuresCoolDownAndRefreshKeepsCache),
    ("Different recording lengths retain separate cache entries", checkDifferentDurationsKeepSeparateCacheEntries),
    ("HTTP retries respect Retry-After", checkHTTPRetry),
    ("Plain lyrics do not block timed fallback", checkTimedFallback),
    ("Restarted app reads timed lyrics offline", checkCacheSurvivesRestartOffline),
    ("Service failures fall through to QQ with correct version", checkQQFallback),
    ("Missing catalogs fall through to Kugou with valid LRC", checkKugouFallback),
    ("Long throttles skip the host without blocking other sources", checkLongThrottle),
    ("Cancellation stops fallback requests", checkCancellation),
    ("Corrupt cache recovers and clear preserves unrelated files", checkCorruptCache)
]
Task {
    for (name, run) in asyncCases {
        let before = failures
        await run()
        print("\(failures == before ? "PASS" : "FAIL") \(name)")
    }
    print("\(cases.count + asyncCases.count) scenarios, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
