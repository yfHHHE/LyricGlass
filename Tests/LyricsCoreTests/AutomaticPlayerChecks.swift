import LyricsCore
import PlaybackKit

func playerMonitor(_ spotify: PlayerFixture, _ music: PlayerFixture, preferred: DesktopPlayer = .spotify) -> PlaybackMonitor {
    PlaybackMonitor(preferredPlayer: preferred, readers: [
        .spotify: PlayerReader(player: .spotify, property: spotify.property, isRunning: { spotify.running }, observeNotifications: false),
        .appleMusic: PlayerReader(player: .appleMusic, property: music.property, isRunning: { music.running }, observeNotifications: false)
    ])
}

func checkAutomaticPlayerFollowsPlayback() {
    let spotify = PlayerFixture(), music = PlayerFixture()
    spotify.duration = 187000; spotify.state = "kPSp"
    let monitor = playerMonitor(spotify, music)
    let update = monitor.poll()
    checkEqual(update.player, .appleMusic)
    do {
        let sample = try update.result.get()
        checkTrue(sample.playing)
        checkEqual(sample.song?.duration, 187)
    } catch { failures += 1; print("FAIL automatic player: \(error)") }
}

func checkAutomaticPlayerTransitionsStayStable() {
    let spotify = PlayerFixture(), music = PlayerFixture()
    spotify.duration = 187000; music.state = "kPSp"
    let monitor = playerMonitor(spotify, music)
    checkEqual(monitor.poll().player, .spotify)
    music.state = "kPSP"
    checkEqual(monitor.poll().player, .appleMusic)
    checkEqual(monitor.poll().player, .appleMusic)
    music.state = "kPSp"; spotify.state = "kPSp"
    checkEqual(monitor.poll().player, .appleMusic)
    spotify.state = "kPSP"
    checkEqual(monitor.poll().player, .spotify)
    music.state = "kPSP"
    checkEqual(monitor.poll().player, .appleMusic)
    music.running = false
    checkEqual(monitor.poll().player, .spotify)
    music.running = true
    checkEqual(monitor.poll().player, .appleMusic)
    let bothPlaying = playerMonitor(spotify, music, preferred: .appleMusic)
    checkEqual(bothPlaying.poll().player, .appleMusic)
    checkEqual(bothPlaying.poll().player, .appleMusic)
}

func checkAutomaticPermissionsAndRecovery() {
    let spotify = PlayerFixture(), music = PlayerFixture()
    spotify.duration = 187000; spotify.errors["pPlS"] = -1743
    let monitor = playerMonitor(spotify, music)
    checkEqual(monitor.poll(now: 10).player, .appleMusic)
    checkEqual(monitor.poll(now: 11).player, .appleMusic)
    checkEqual(spotify.calls["pPlS"], 1)
    checkNil(spotify.calls["pnam"])
    spotify.errors = [:]; spotify.state = "kPSp"
    monitor.retry()
    checkEqual(monitor.poll(now: 12).player, .appleMusic)
    checkEqual(spotify.calls["pPlS"], 2)
    music.state = "kPSp"; spotify.state = "kPSP"
    checkEqual(monitor.poll(now: 13).player, .spotify)
    music.state = "kPSP"
    checkEqual(monitor.poll(now: 14).player, .appleMusic)
    music.errors["pPlS"] = -1712
    checkEqual(monitor.poll(now: 15).player, .spotify)
    let callsAfterTimeout = music.calls["pPlS"]
    checkEqual(monitor.poll(now: 16).player, .spotify)
    checkEqual(music.calls["pPlS"], callsAfterTimeout)
    music.errors = [:]
    checkEqual(monitor.poll(now: 21).player, .spotify)
}

func checkManualModeOverridesAutomaticChoice() {
    let spotify = PlayerFixture(), music = PlayerFixture()
    spotify.duration = 187000; spotify.state = "kPSp"
    let monitor = playerMonitor(spotify, music)
    let pinned = monitor.poll(mode: .spotify)
    checkEqual(pinned.player, .spotify)
    checkTrue(music.calls.isEmpty)
    do { checkFalse(try pinned.result.get().playing) }
    catch { failures += 1; print("FAIL pinned player: \(error)") }
    checkEqual(monitor.poll().player, .appleMusic)
    checkEqual(monitor.poll(mode: .appleMusic).player, .appleMusic)
    spotify.state = "kPSP"
    checkEqual(monitor.poll(mode: .appleMusic).player, .appleMusic)
    checkEqual(monitor.poll().player, .appleMusic)
}

func checkAutomaticEmptyAndStreamingGap() {
    let spotify = PlayerFixture(), music = PlayerFixture()
    spotify.duration = 187000; spotify.running = false; music.running = false
    let monitor = playerMonitor(spotify, music)
    let empty = monitor.poll()
    checkNil(empty.player)
    checkTrue(spotify.calls.isEmpty && music.calls.isEmpty)
    do { _ = try empty.result.get(); checkTrue(false) }
    catch PlaybackMonitorError.noPlayer { }
    catch { failures += 1; print("FAIL no player: \(error)") }
    spotify.running = true; spotify.state = "kPSp"; music.running = true; music.libraryAvailable = false
    let streaming = monitor.poll()
    checkEqual(streaming.player, .appleMusic)
    do { _ = try streaming.result.get(); checkTrue(false) }
    catch PlayerReadError.musicMetadataUnavailable { }
    catch { failures += 1; print("FAIL streaming gap: \(error)") }
    music.libraryAvailable = true
    do { checkTrue(try monitor.poll().result.get().playing) }
    catch { failures += 1; print("FAIL streaming recovery: \(error)") }
    music.errors["pPlS"] = -1712
    let failed = monitor.poll()
    checkEqual(failed.player, .appleMusic)
    do { _ = try failed.result.get(); checkTrue(false) }
    catch PlayerReadError.unavailable(.appleMusic, -1712) { }
    catch { failures += 1; print("FAIL active source outage: \(error)") }
}
