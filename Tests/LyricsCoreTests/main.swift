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
    ("LRC timestamps and repeated tags", suite.testTimestampsFractionsRepeatedTagsAndMetadata),
    ("LRC offset and simultaneous translations", suite.testOffsetAndBilingualSimultaneousLines),
    ("Prelude, interlude and backwards seek", suite.testPreludeInterludeSeekBackwardAndFinalLine),
    ("Clock pause, resume, seek and stale samples", suite.testClockPauseSeekResumeAndStaleRead),
    ("Recording identity, duration and Chinese matching", suite.testMatchingRejectsDifferentRecordingAndDuration),
    ("Playback-to-lyrics integration", suite.testPlaybackToLyricsIntegration)
]
for (name, run) in cases {
    let before = failures
    run()
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
print("\(cases.count) scenarios, \(failures) failures")
exit(failures == 0 ? 0 : 1)
