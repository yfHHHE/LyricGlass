import AppKit
import LyricsCore
import PlaybackKit

func argument(_ flag: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

if CommandLine.arguments.contains("--check-lyrics") {
    // Metadata-only diagnostics: never print or upload lyric contents.
    let title = argument("--title") ?? "Yellow"
    let artist = argument("--artist") ?? "Coldplay"
    let album = argument("--album") ?? "Parachutes"
    guard let duration = Double(argument("--duration") ?? "266"), duration.isFinite, duration > 0 else {
        fputs("--duration must be a positive number of seconds\n", stderr); exit(2)
    }
    let selected = argument("--source")
    guard selected == nil || selected == "all" || LyricsSource(rawValue: selected!) != nil else {
        fputs("--source must be all, lrclib, netease, qq or kugou\n", stderr); exit(2)
    }
    Task {
        do {
            let started = ProcessInfo.processInfo.systemUptime
            let cache = argument("--cache-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            let sources = selected.flatMap(LyricsSource.init(rawValue:)).map { [$0] } ?? LyricsSource.allCases
            let song = Song(id: "probe:\(title):\(artist)", title: title, artist: artist, album: album, duration: duration)
            let provider = LyricsProvider(cacheDirectory: cache, sources: sources)
            let record = try await provider.fetch(song: song, forceReload: CommandLine.arguments.contains("--fresh"))
            let count = LyricsTimeline(lrc: record.syncedLyrics ?? "").lines.count
            let output: [String: Any] = ["title": record.trackName, "artist": record.artistName, "album": record.albumName ?? "",
                "duration": record.duration, "source": record.sourceKind.rawValue, "cached": record.cached,
                "synced": record.hasSyncedLyrics, "timed_lines": count,
                "elapsed_ms": Int((ProcessInfo.processInfo.systemUptime - started) * 1000)]
            let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            exit(record.hasSyncedLyrics ? 0 : 2)
        } catch { fputs("Lyrics check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--diagnose-spotify") || CommandLine.arguments.contains("--diagnose-player") {
    let selected = CommandLine.arguments.contains("--diagnose-spotify") ? "spotify" : argument("--player") ?? "spotify"
    guard let player = DesktopPlayer(rawValue: selected),
          let watch = Double(argument("--watch") ?? "0"), watch.isFinite, (0...120).contains(watch) else {
        fputs("Use --player spotify|apple-music and --watch 0...120 seconds\n", stderr); exit(2)
    }
    let reader = PlayerReader(player: player)
    let outputFlag = CommandLine.arguments.firstIndex(of: "--output")
    let output = outputFlag.flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
    func diagnose() {
      let result: [String: Any]
      do {
        let sample = try reader.read()
        result = ["ok": true, "player": player.rawValue, "title": sample.song?.title ?? "", "artist": sample.song?.artist ?? "",
                  "album": sample.song?.album ?? "", "duration": sample.song?.duration ?? 0,
                  "position": sample.position, "playing": sample.playing]
      } catch { result = ["ok": false, "player": player.rawValue, "error": error.localizedDescription] }
      let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
      if let output { try? data.write(to: URL(fileURLWithPath: output)) }
      print(String(data: data, encoding: .utf8)!)
      fflush(stdout)
    }
    diagnose()
    if watch > 0 {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in diagnose() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(watch))
        timer.invalidate()
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
