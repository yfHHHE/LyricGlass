import AppKit
import LyricsCore

if CommandLine.arguments.contains("--check-lyrics") {
    // Network-only smoke check. Reports metadata and timestamp count, never the lyric text.
    Task {
        do {
            let song = Song(id: "probe", title: "Yellow", artist: "Coldplay", album: "Parachutes", duration: 266)
            let record = try await LyricsProvider().fetch(song: song)
            let count = LyricsTimeline(lrc: record.syncedLyrics ?? "").lines.count
            print("LRCLIB OK: \(record.trackName), \(record.artistName), \(record.duration)s, timed lines=\(count)")
            exit(count > 0 ? 0 : 2)
        } catch { fputs("Lyrics check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--diagnose-spotify") {
    let outputFlag = CommandLine.arguments.firstIndex(of: "--output")
    let output = outputFlag.flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
    let result: [String: Any]
    do {
        let sample = try SpotifyReader().read()
        result = ["ok": true, "title": sample.song?.title ?? "", "artist": sample.song?.artist ?? "",
                  "album": sample.song?.album ?? "", "duration": sample.song?.duration ?? 0,
                  "position": sample.position, "playing": sample.playing]
    } catch { result = ["ok": false, "error": error.localizedDescription] }
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    if let output { try? data.write(to: URL(fileURLWithPath: output)) }
    print(String(data: data, encoding: .utf8)!)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
