import AppKit

func verifyReadingLayouts() throws {
    let panel = IslandPanel()
    let suite = "ai.yufan.lyricglass.appearance-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppearanceStore(defaults: defaults)
    panel.onAppearanceChange = { store.save($0); panel.apply($0) }
    let lines = PreviewLyrics.english + PreviewLyrics.chinese
    func show(_ lines: [String], active: Int) {
        panel.islandView.show(current: lines[active], next: active + 1 < lines.count ? lines[active + 1] : "",
            title: "歌词示例", artist: "LyricGlass", playing: true, canControl: true,
            position: Double(active) * 8, duration: 40, error: "", context: lines, currentIndex: active)
        panel.islandView.layoutSubtreeIfNeeded()
    }
    let view = panel.islandView
    show(lines, active: 1)
    try require(!panel.expanded && !view.compact.isHidden && view.textViewport.isHidden && view.controls.isHidden, "Default must be the original single-line capsule, with expanded lyrics and controls hidden")
    try require(panel.frame.height == 24 && view.layer?.cornerRadius == 12, "Default capsule must remain small and fully rounded")
    try require(view.compact.attributedTitle.string.contains(lines[1]), "The original capsule must preview the current lyric")
    let compact = panel.frame
    panel.setExpanded(true, animated: false); view.layoutSubtreeIfNeeded()
    try require(view.visibleRows.map(\.stringValue) == Array(lines[1...2]) && view.current.alignment == .center, "Default expanded A must show the centered current and next lyrics")
    try require(view.controls.orientation == .horizontal && view.textViewport.frame.maxY < view.controls.frame.minY, "Two-line playback controls must share the title row above the lyrics")
    view.lineCount.selectedSegment = 1; try send(view.lineCount); view.layoutSubtreeIfNeeded()
    try require(store.load().presentation.islandAppearance.expandedLineCount == 5, "The inline five-line option must save independently of the lock")
    try require(view.visibleRows.map(\.stringValue) == lines && view.currentRowIndex == 1, "Expanded D must display five correctly ordered context rows")
    try require(view.visibleRows.allSatisfy { $0.alignment == .left } && view.controls.orientation == .vertical, "Expanded lyrics must align left beside vertical playback controls")
    let accessible = view.textViewport.textDocument.accessibilityChildren() as? [LyricsTextField]
    try require(accessible?.map(\.stringValue) == lines && view.current.accessibilityLabel() == "当前歌词", "VoiceOver must read the five rows in visual order and identify the active lyric")
    try require(view.textViewport.frame.maxX < view.controls.frame.minX, "The right-side buttons must not cover the lyrics")
    try require(view.controls.previous.frame.minY > view.controls.playPause.frame.minY && view.controls.playPause.frame.minY > view.controls.next.frame.minY, "Vertical controls must keep previous, play, next ordering")
    try require(panel.frame.height > compact.height && panel.frame.maxY == compact.maxY, "Five-line expansion must grow down from the same screen anchor")
    var actions: [SettingsAction] = []
    panel.onPlaybackAction = { actions.append($0) }
    for button in [view.controls.previous, view.controls.playPause, view.controls.next] { try send(button) }
    try require(actions == [.previousTrack, .togglePlayback, .nextTrack], "All three vertical buttons must reach the actual player action route")
    show(lines, active: 4)
    try require(view.current === view.visibleRows.last && view.currentRowIndex == 4, "At the last lyric, preceding context must remain visible without duplicating the current line")
    let long = String(repeating: "Every time 我告訴我自己 ", count: 120)
    show([long, lines[0], lines[1], lines[2], lines[3]], active: 2)
    let viewport = view.textViewport
    try require(viewport.textDocument.bounds.height > viewport.contentSize.height, "Height-limited long context must remain scrollable")
    try require(viewport.documentVisibleRect.intersects(view.current.frame), "New current lyrics must stay visible even after a very long preceding row")
    let selected = view.current.stringValue
    viewport.contentView.scroll(to: .zero)
    view.show(current: selected, next: lines[2], title: "歌词示例", artist: "LyricGlass", playing: false, canControl: true,
        position: 16, duration: 40, error: "", context: [long, lines[0], lines[1], lines[2], lines[3]], currentIndex: 2)
    view.layoutSubtreeIfNeeded()
    try require(viewport.documentVisibleRect.minY == 0, "Progress ticks and pause state must preserve manual scroll position")
    show(["另一首歌", "另一首下一句"], active: 0)
    try require(view.visibleRows.map(\.stringValue) == ["另一首歌", "另一首下一句"], "Track changes must remove all preceding-song rows")
    try send(view.pin); view.onHover?(false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    try require(panel.expanded && store.load().presentation.islandPinned, "Only the explicit pin must keep expansion open outside hover and save the lock")
    try send(view.pin); view.layoutSubtreeIfNeeded()
    try require(!panel.expanded && !store.load().presentation.islandPinned && !view.compact.isHidden && panel.frame.height == compact.height, "Unlocking must immediately restore the original small capsule")
    if !panel.frame.contains(NSEvent.mouseLocation) {
        try send(view.compact)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        try require(!panel.expanded, "An accessibility click from outside the window must auto-collapse without needing a new mouse-exit event")
    }
    try send(view.compact); view.onHover?(false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    try require(!panel.expanded && !store.load().presentation.islandPinned, "Clicking to expand must never implicitly lock the window")
    view.onHover?(true); view.onHover?(false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    try require(!panel.expanded, "A hover-only expansion must collapse after the pointer leaves")
    var legacy = LyricsAppearance()
    legacy.presentation.islandAppearance.compactWidth = 486
    legacy.presentation.islandAppearance.compactHeight = 29
    legacy.chineseFont = .wenkai; legacy.englishFont = .openDyslexic
    let migrated = legacy.normalized()
    try require(migrated.presentation.islandAppearance.compactHeight == 29 && migrated.presentation.islandAppearance.compactWidth == 486 && migrated.chineseFont == .wenkai && migrated.englishFont == .openDyslexic, "Original capsule dimensions and language fonts must survive")
    legacy.presentation.islandAppearance.compactHeight = 96
    try require(legacy.normalized().presentation.islandAppearance.compactHeight == 24, "Accidental v0.6.3 card heights must migrate back to a small capsule")
    let settings = AppearanceSettings(style: store.load(), onChange: { store.save($0); panel.apply($0) }, onRecenter: {})
    settings.showWindow(); settings.window.orderOut(nil)
    let picker = descendants(settings.root).compactMap { $0 as? NSSegmentedControl }.first { $0.accessibilityLabel() == "顶部展开行数" }!
    picker.selectedSegment = 0; try send(picker)
    try require(store.load().presentation.islandAppearance.expandedLineCount == 2 && !store.load().presentation.islandPinned, "Settings must save two-line mode without changing lock state")
    panel.setExpanded(true, animated: false); show(lines, active: 1)
    try require(view.visibleRows.map(\.stringValue) == Array(lines[1...2]) && view.controls.orientation == .horizontal, "Saved two-line mode must reach the actual renderer")
    try send(view.pin); view.onHover?(false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    try require(panel.expanded && store.load().presentation.islandPinned, "Two-line expansion must also be lockable")
    try send(view.expansion)
    try require(!panel.expanded && !store.load().presentation.islandPinned, "The collapse arrow must explicitly unlock and return to the capsule")
    print("PASS capsule → 2/5-line expansion: independent persisted lock, hover/click auto-collapse, native buttons, context order, scrolling and legacy settings")
}

func exportReadingPreviews(to directory: URL) throws {
    try registerAppearanceFonts()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let panel = IslandPanel()
    let lines = PreviewLyrics.english + PreviewLyrics.chinese
    for (name, expanded, rows) in [("capsule", false, 2), ("A-two-lines", true, 2), ("D-five-lines", true, 5)] {
        var style = LyricsAppearance()
        style.presentation.islandAppearance.expandedLineCount = rows
        panel.apply(style); panel.setExpanded(expanded, animated: false)
        panel.islandView.show(current: lines[1], next: lines[2], title: "歌词示例", artist: "LyricGlass",
            playing: true, canControl: true, position: 10, duration: 40, error: "", context: lines, currentIndex: 1)
        let view = panel.islandView
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot snapshot reading layout") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        print("PASS production \(name) snapshot: \(panel.frame.size)")
    }
}
