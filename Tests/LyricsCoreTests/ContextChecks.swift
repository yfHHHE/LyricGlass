import LyricsCore

func checkReadingContextFollowsTimeline() {
    let timeline = LyricsTimeline(lrc: "[00:05]one\n[00:10]two\n[00:15]three\n[00:20]four\n[00:25]five\n[00:30]six\n[00:35]seven")
    for position in [0.0, 5, 14.99, 15, 23, 35, 100, 10] {
        let context = timeline.context(at: position)
        checkEqual(context.lines.count, 5)
        checkEqual(context.lines[context.currentIndex], timeline.pair(at: position).current)
    }
    checkEqual(timeline.context(at: 23).lines, ["two", "three", "four", "five", "six"])
    checkEqual(timeline.context(at: 23).currentIndex, 2)
    checkEqual(timeline.context(at: 100).lines, ["three", "four", "five", "six", "seven"])
    checkEqual(timeline.context(at: 100).currentIndex, 4)
    checkEqual(timeline.context(at: 0).lines, ["前奏 · 等待人声", "one", "two", "three", "four"])
    let interlude = LyricsTimeline(lrc: "[00:05]one\n[00:10]\n[00:12]\n[00:15]two\n[00:20]three")
    checkEqual(interlude.context(at: 11).lines, ["one", "间奏 ♪", "two", "three"])
    checkEqual(interlude.context(at: 11).currentIndex, 1)
    checkEqual(interlude.context(at: 16).lines, ["one", "two", "three"])
    let repeated = LyricsTimeline(lrc: "[00:00]same\n[00:05]same\n[00:10]last")
    checkEqual(repeated.context(at: 5).currentIndex, 1)
    checkEqual(repeated.context(at: 5).lines, ["same", "same", "last"])
    checkEqual(timeline.context(at: 23, count: 0).lines, ["four"])
    checkEqual(timeline.context(at: 0, count: 1).lines, ["前奏 · 等待人声"])
    checkEqual(LyricsTimeline(lrc: "").context(at: 0).lines, ["暂无同步歌词"])
    var clock = PlaybackClock()
    clock.sample(position: 14.8, duration: 40, playing: true, now: 100)
    checkEqual(timeline.context(at: clock.position(at: 100.3)).lines[2], "three")
    clock.sample(position: 15.1, duration: 40, playing: false, now: 101)
    checkEqual(timeline.context(at: clock.position(at: 110)).lines[2], "three")
    clock.sample(position: 5, duration: 40, playing: true, now: 111)
    checkEqual(timeline.context(at: clock.position(at: 111)).currentIndex, 0)
    checkEqual(timeline.context(at: 14.8 + 0.5).lines[2], "three")
}
