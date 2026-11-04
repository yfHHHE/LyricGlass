import AppKit
import PlaybackKit

func checkPlaybackCommandDictionaries() {
    checkEqual(PlaybackCommand.allCases.map(\.eventID), ["Prev", "PlPs", "Next"])
    for command in PlaybackCommand.allCases {
        checkEqual(command.eventClass(for: .spotify), "spfy")
        checkEqual(command.eventClass(for: .appleMusic), "hook")
    }
}

func checkPlaybackCommandsTargetOnlySelectedPlayer() {
    var calls: [(DesktopPlayer, PlaybackCommand)] = []
    let controller = PlayerController(sender: { calls.append(($0, $1)) }, isRunning: { _ in true })
    do {
        for player in DesktopPlayer.allCases {
            for command in PlaybackCommand.allCases { try controller.perform(command, on: player) }
        }
        checkEqual(calls.count, 6)
        checkTrue(calls.prefix(3).allSatisfy { $0.0 == .spotify })
        checkTrue(calls.suffix(3).allSatisfy { $0.0 == .appleMusic })
        checkEqual(calls.map { $0.1.eventID }, ["Prev", "PlPs", "Next", "Prev", "PlPs", "Next"])
    } catch { failures += 1; print("FAIL selected playback target: \(error)") }
}

func checkPlaybackControlsDoNotLaunchClosedPlayer() {
    var sends = 0
    let controller = PlayerController(sender: { _, _ in sends += 1 }, isRunning: { _ in false })
    do { try controller.perform(.next, on: .spotify); checkTrue(false) }
    catch PlayerReadError.notRunning(.spotify) { }
    catch { checkTrue(false) }
    checkEqual(sends, 0)
}

func checkPlaybackControlErrorsDoNotRetryOrSwitchPlayers() {
    for code in [-1743, -1712] {
        var targets: [DesktopPlayer] = []
        let controller = PlayerController(sender: { player, _ in
            targets.append(player); throw NSError(domain: NSOSStatusErrorDomain, code: code)
        }, isRunning: { _ in true })
        do { try controller.perform(.next, on: .appleMusic); checkTrue(false) }
        catch PlayerReadError.denied(.appleMusic) { checkEqual(code, -1743) }
        catch PlayerReadError.unavailable(.appleMusic, let actual) { checkEqual(actual, code) }
        catch { checkTrue(false) }
        checkEqual(targets, [.appleMusic], "Never replay or redirect a playback-changing event")
    }
}
