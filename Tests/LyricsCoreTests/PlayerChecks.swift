import AppKit
import LyricsCore
import PlaybackKit

final class PlayerFixture {
    var position = 12.5
    var state = "kPSP"
    var libraryAvailable = true
    var running = true
    var id = "music-track"
    var title = "Example"
    var artist = "Artist"
    var duration = 187.0
    var errors: [String: Int] = [:]
    var calls: [String: Int] = [:]
    var afterPosition: (() -> Void)?

    func property(_ code: String, track: Bool) throws -> NSAppleEventDescriptor {
        calls[code, default: 0] += 1
        if let error = errors[code] { throw NSError(domain: NSOSStatusErrorDomain, code: error) }
        if track && !libraryAvailable { throw NSError(domain: NSOSStatusErrorDomain, code: -1728) }
        switch code {
        case "pPlS": return NSAppleEventDescriptor(enumCode: state.utf8.reduce(0) { ($0 << 8) | UInt32($1) })
        case "pPos": afterPosition?(); return NSAppleEventDescriptor(double: position)
        case "pPID", "ID  ": return NSAppleEventDescriptor(string: id)
        case "pnam": return NSAppleEventDescriptor(string: title)
        case "pArt": return NSAppleEventDescriptor(string: artist)
        case "pAlb": return NSAppleEventDescriptor(string: "Album")
        case "pDur": return NSAppleEventDescriptor(double: duration)
        default: throw NSError(domain: NSOSStatusErrorDomain, code: -1700)
        }
    }
}

func checkPlayersStayIsolatedAndPermissionErrors() {
    let music = PlayerFixture(), spotify = PlayerFixture()
    spotify.duration = 187000
    let musicReader = PlayerReader(player: .appleMusic, property: music.property, isRunning: { music.running }, observeNotifications: false)
    let spotifyReader = PlayerReader(player: .spotify, property: spotify.property, isRunning: { spotify.running }, observeNotifications: false)
    do {
        let first = try musicReader.read(), second = try spotifyReader.read()
        checkEqual(first.song?.duration, 187)
        checkEqual(second.song?.duration, 187)
        checkFalse(first.song?.id == second.song?.id)
        music.errors["pPID"] = -1743
        do { _ = try musicReader.read(); checkTrue(false) }
        catch PlayerReadError.denied(.appleMusic) { }
        spotify.errors["ID  "] = -1743
        do { _ = try spotifyReader.read(); checkTrue(false) }
        catch PlayerReadError.denied(.spotify) { }
        spotify.errors = [:]
        spotify.afterPosition = { spotify.id = "next-track" }
        do { _ = try spotifyReader.read(); checkTrue(false) }
        catch PlayerReadError.changedTrack { }
    } catch { failures += 1; print("FAIL player isolation: \(error)") }
}

func checkMusicMissingIDAndInvalidNotification() {
    let fixture = PlayerFixture()
    fixture.errors["pPID"] = -1728
    let reader = PlayerReader(player: .appleMusic, property: fixture.property, isRunning: { fixture.running }, observeNotifications: false)
    do {
        checkEqual(try reader.read().song?.artist, "Artist")
        fixture.afterPosition = { fixture.artist = "Different Artist" }
        do { _ = try reader.read(); checkTrue(false) }
        catch PlayerReadError.changedTrack { }
        fixture.afterPosition = nil
        reader.receiveAppleMusicNotification(["Name": "Stream", "Artist": "Artist", "Total Time": 187000, "Player State": "Playing"])
        checkEqual(try reader.read().song?.title, "Stream")
        reader.receiveAppleMusicNotification(["Player State": "Playing", "Total Time": "invalid"])
        do { _ = try reader.read(); checkTrue(false) }
        catch PlayerReadError.musicMetadataUnavailable { }
        fixture.state = "kPSS"
        checkNil(try reader.read().song)
    } catch { failures += 1; print("FAIL Music missing metadata: \(error)") }
}

func checkMusicNotificationIdentitySurvivesPrecisionChanges() {
    let fixture = PlayerFixture()
    fixture.libraryAvailable = false
    let reader = PlayerReader(player: .appleMusic, property: fixture.property, isRunning: { true }, observeNotifications: false)
    var info: [AnyHashable: Any] = ["Name": "Galaxies", "Artist": "Laura Veirs", "Album": "Year of Meteors", "Total Time": 215000, "PersistentID": 12345, "Player State": "Playing"]
    reader.receiveAppleMusicNotification(info)
    do {
        let playing = try reader.read()
        info["Total Time"] = 215647
        info["Player State"] = "Paused"
        fixture.state = "kPSp"
        reader.receiveAppleMusicNotification(info)
        let paused = try reader.read()
        checkEqual(playing.song?.id, paused.song?.id)
        checkEqual(paused.song?.duration, 215.647)
        checkFalse(paused.playing)
    } catch { failures += 1; print("FAIL Music precision change: \(error)") }
}

func checkMusicZeroIDDoesNotReuseAnotherSong() {
    let fixture = PlayerFixture()
    fixture.id = "0000000000000000"
    let reader = PlayerReader(player: .appleMusic, property: fixture.property, isRunning: { true }, observeNotifications: false)
    do {
        let first = try reader.read()
        fixture.duration = 187.647
        checkEqual(try reader.read().song?.id, first.song?.id)
        fixture.title = "Different Song"
        let next = try reader.read()
        checkFalse(next.song?.id == first.song?.id)
        checkEqual(next.song?.title, "Different Song")
    } catch { failures += 1; print("FAIL Music zero ID: \(error)") }
}

func checkAppleMusicReadAndSeek() {
    let fixture = PlayerFixture()
    let reader = PlayerReader(player: .appleMusic, property: fixture.property, isRunning: { fixture.running }, observeNotifications: false)
    do {
        let sample = try reader.read()
        checkEqual(sample.song?.duration, 187)
        checkEqual(sample.position, 12.5)
        checkTrue(sample.playing)
        checkTrue(sample.song?.id.hasPrefix("apple-music:") ?? false)
        fixture.state = "kPSp"; fixture.position = 5
        let paused = try reader.read()
        checkFalse(paused.playing)
        var clock = PlaybackClock()
        clock.sample(position: paused.position, duration: paused.song!.duration, playing: paused.playing, now: 100)
        let timeline = LyricsTimeline(lrc: "[00:02]first\n[00:05]second\n[00:20]third")
        checkEqual(timeline.pair(at: clock.position(at: 101)).current, "second")
        fixture.position = 21; fixture.state = "kPSP"
        let seeked = try reader.read()
        clock.sample(position: seeked.position, duration: seeked.song!.duration, playing: seeked.playing, now: 102)
        checkEqual(timeline.pair(at: clock.position(at: 102.5)).current, "third")
    } catch { failures += 1; print("FAIL Music playback: \(error)") }
}

func checkAppleMusicStreamingNotifications() {
    let fixture = PlayerFixture()
    fixture.libraryAvailable = false
    let reader = PlayerReader(player: .appleMusic, property: fixture.property, isRunning: { fixture.running }, observeNotifications: false)
    reader.receiveAppleMusicNotification(["Name": "Streaming Song", "Artist": "Artist", "Album": "Album", "Total Time": 187000, "Player State": "Playing", "PersistentID": 12345])
    do {
        let sample = try reader.read()
        checkEqual(sample.song?.title, "Streaming Song")
        checkEqual(sample.song?.duration, 187)
        checkEqual(sample.position, 12.5)
        checkTrue(sample.playing)
        fixture.position = 40; fixture.state = "kPSp"
        checkFalse(try reader.read().playing)
        checkEqual(try reader.read().position, 40)
        fixture.afterPosition = {
            reader.receiveAppleMusicNotification(["Name": "Next Stream", "Artist": "Artist", "Album": "Album", "Total Time": 200000, "Player State": "Playing"])
        }
        do { _ = try reader.read(); checkTrue(false) }
        catch PlayerReadError.changedTrack { }
        fixture.afterPosition = nil
        checkEqual(try reader.read().song?.title, "Next Stream")
        fixture.running = false
        do { _ = try reader.read(); checkTrue(false) }
        catch PlayerReadError.notRunning(.appleMusic) { }
        fixture.running = true
        do { _ = try reader.read(); checkTrue(false) }
        catch PlayerReadError.musicMetadataUnavailable { }
    } catch { failures += 1; print("FAIL Music streaming: \(error)") }
}
