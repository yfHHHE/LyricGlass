import AppKit

struct CheckError: Error, CustomStringConvertible { let description: String }
func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw CheckError(description: message) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func send(_ control: NSControl) throws {
    guard let action = control.action else { throw CheckError(description: "Missing native action") }
    try require(control.sendAction(action, to: control.target), "Native action was not delivered")
}

func verify() throws {
    let suite = "ai.yufan.lyricglass.appearance-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); defaults.synchronize() }
    let store = AppearanceStore(defaults: defaults)
    _ = AppearanceStore().load() // Real startup path: never construct a suite from the app's own bundle ID.
    try registerAppearanceFonts()
    try verifyWrapping()
    try verifyCompactLayouts()
    let panel = LyricsPanel()
    panel.lyricsView.show(current: "Let the melody stay", next: "让文字跟着时间", detail: "Check")
    var changed = 0
    var actions: [SettingsAction] = []
    var playerSelections: [Int] = []
    let settings = AppearanceSettings(style: store.load(), onChange: {
        changed += 1; store.save($0); panel.apply($0)
    }, onRecenter: { panel.centerAtBottom() }, onPlayer: { playerSelections.append($0) }, onAction: { actions.append($0) })
    settings.showWindow()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    try require(settings.root.bounds.width >= 780 && settings.root.bounds.height >= 620, "Settings window must stay usable after AppKit lays out scroll pages")
    settings.window.orderOut(nil)
    let disclosure = descendants(settings.root).compactMap { $0 as? NSButton }.first { $0.title == "更多外观选项" }!
    disclosure.state = .on; try send(disclosure)
    let views = descendants(settings.root)
    let display = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "歌词显示方式" }!
    try require(store.load().presentation.mode == .both, "Default must retain desktop lyrics alongside the island")
    display.selectItem(at: 2); try send(display)
    try require(store.load().presentation.mode == .island, "Display mode must save independently of typography")
    display.selectItem(at: 0); try send(display)
    let gap = views.compactMap { $0 as? NSSlider }.first { $0.tag == 5 }!
    gap.doubleValue = 48; try send(gap)
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(abs(panel.lyricsView.current.frame.minY - panel.lyricsView.next.frame.maxY - 48) < 0.1, "Line gap must reach the real renderer without clipping")
    let width = views.compactMap { $0 as? NSSlider }.first { $0.tag == 6 }!
    width.doubleValue = 680; try send(width)
    try require(abs(panel.frame.width - min(680, (NSScreen.screens.first?.visibleFrame.width ?? 720) - 40)) < 0.1, "Desktop width must resize the actual window")
    let showNext = views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "显示下一句歌词" }!
    let twoLineHeight = panel.frame.height
    showNext.state = .off; try send(showNext)
    try require(panel.lyricsView.next.isHidden && panel.frame.height < twoLineHeight, "Single-line mode must hide the next line and reclaim its space")
    showNext.state = .on; try send(showNext)
    gap.doubleValue = 8; try send(gap)
    let island = IslandPanel()
    island.apply(store.load())
    var pinned = store.load(); pinned.presentation.islandPinned = true
    island.apply(pinned)
    try require(island.expanded, "Pinning must immediately expand the island")
    pinned.presentation.islandPinned = false; island.apply(pinned)
    try require(!island.expanded, "Unpinning from settings must immediately restore compact mode")
    island.setExpanded(true, animated: false)
    island.islandView.layoutSubtreeIfNeeded()
    try require(island.frame.maxY == NSScreen.screens.first?.frame.maxY, "Island expansion must keep the top screen edge anchored")
    let notched = IslandGeometry(screenFrame: NSRect(x: -1440, y: 200, width: 1440, height: 900), topInset: 32, notchWidth: 200)
    let compactFrame = notched.frame(expanded: false, width: 480, height: 180)
    let expandedFrame = notched.frame(expanded: true, width: 480, height: 180)
    try require(compactFrame.midX == expandedFrame.midX && compactFrame.maxY == expandedFrame.maxY && expandedFrame.maxY == 1100, "Notched and offset monitors must share a stable expansion anchor")
    island.islandView.geometry = notched
    island.setFrame(NSRect(x: 0, y: 0, width: 480, height: island.islandView.expandedHeight), display: true)
    island.islandView.layoutSubtreeIfNeeded()
    try require(island.islandView.current.frame.maxY <= island.islandView.bounds.height - 32, "Expanded lyrics must stay below the camera cutout")
    let small = IslandGeometry(screenFrame: NSRect(x: 100, y: -600, width: 360, height: 600))
    try require(small.screenFrame.contains(small.frame(expanded: true, width: 720, height: 200)), "Island must clamp to small and secondary screen coordinates")
    var invalidLayout = LyricsAppearance(); invalidLayout.lineGap = .infinity
    invalidLayout.presentation.desktopWidth = .nan; invalidLayout.presentation.islandWidth = .infinity
    let valid = invalidLayout.normalized()
    try require(valid.lineGap == 8 && valid.presentation.desktopWidth == 940 && valid.presentation.islandWidth == 480, "Invalid stored dimensions must normalize before any window layout")
    var playbackActions: [SettingsAction] = []
    panel.lyricsView.onPlaybackAction = { playbackActions.append($0) }
    island.onPlaybackAction = { playbackActions.append($0) }
    panel.lyricsView.updatePlayback(playing: true, enabled: true)
    island.islandView.controls.update(playing: true, enabled: true)
    try require(panel.lyricsView.controls.playPause.toolTip == "暂停", "Playback state must set the current transport action")
    for controls in [panel.lyricsView.controls, island.islandView.controls] {
        for button in [controls.previous, controls.playPause, controls.next] { try send(button) }
    }
    try require(playbackActions == [.previousTrack, .togglePlayback, .nextTrack, .previousTrack, .togglePlayback, .nextTrack], "Both windows must route all three real native buttons")
    panel.lyricsView.updatePlayback(playing: false, enabled: false)
    try require(!panel.lyricsView.controls.next.isEnabled && panel.lyricsView.controls.playPause.toolTip == "播放", "Unavailable playback must disable controls")
    let petToggle = views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "在歌词旁显示雨滴" }!
    let petMotion = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "雨滴动作" }!
    try require(!store.load().petEnabled && panel.lyricsView.pet.avatar == nil, "Companion must default off without loading graphics")
    petToggle.state = .on; try send(petToggle)
    try require(store.load().petEnabled && panel.lyricsView.pet.avatar?.character.childNodes.count == 5, "Companion toggle must save and load the original 5-mesh avatar")
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(panel.lyricsView.current.frame.minX > panel.lyricsView.pet.frame.maxX, "Companion must reserve its own space rather than cover the lyrics")
    petMotion.selectItem(at: 0); try send(petMotion)
    try require(store.load().petMotion == .still, "Motion selection must auto-save")
    let avatar = panel.lyricsView.pet.avatar!
    avatar.pose(time: 0.2, playing: true, motion: .gentle, reducedMotion: false)
    try require(avatar.character.position.y > 0, "Playback loop must move while playing")
    avatar.pose(time: 0.2, playing: false, motion: .gentle, reducedMotion: false)
    try require(avatar.character.position.y == 0, "Pausing must stop the dance")
    avatar.pose(time: 0.2, playing: true, motion: .audio, pulse: 0, reducedMotion: false)
    try require(avatar.character.position.y == 0, "Audio mode must not invent a beat during silence")
    avatar.pose(time: 0.2, playing: true, motion: .audio, pulse: 1, reducedMotion: true)
    try require(avatar.character.position.y == 0, "Reduce Motion must override audio movement")
    petToggle.state = .off; try send(petToggle)
    try require(panel.lyricsView.pet.avatar == nil && panel.lyricsView.pet.scene == nil, "Switching off must release the scene")
    let sliders = views.compactMap { $0 as? NSSlider }
    let wells = views.compactMap { $0 as? NSColorWell }
    let fields = views.compactMap { $0 as? NSTextField }
    guard let size = sliders.first(where: { $0.tag == 0 }),
          let color = wells.first(where: { $0.tag == 0 }),
          let font = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.accessibilityLabel() == "英文字体" }),
          let chineseFont = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.accessibilityLabel() == "中文字体" }),
          let background = views.compactMap({ $0 as? NSSegmentedControl }).first(where: { $0.label(forSegment: 0) == "透明" }),
          let presets = views.compactMap({ $0 as? NSSegmentedControl }).first(where: { $0.label(forSegment: 0) == "透明极简" }) else {
        throw CheckError(description: "Native appearance controls missing")
    }
    try require(font.selectedTag() == FontChoice.allCases.firstIndex(of: .system) && font.selectedItem?.isEnabled == true, "Grouped menu must select the font rather than a category heading")
    for category in FontCategory.allCases {
        try require(font.itemTitles.contains(category.rawValue), "Missing font group \(category)")
    }
    for choice in FontChoice.allCases {
        let index = FontChoice.allCases.firstIndex(of: choice)!
        let item = font.menu!.items.first { $0.tag == index }!
        try require(item.isEnabled == choice.available, "Unavailable fonts must be visible and disabled")
        if choice.bundled { try require(choice.available, "Bundled font \(choice.label) must load") }
        if choice.available {
            let regular = choice.font(size: 32, bold: false)
            let emphasized = choice.font(size: 32, bold: true)
            print("FONT \(choice.label): \(regular.fontName) / \(emphasized.fontName)")
            try require(NSFontManager.shared.weight(of: emphasized) > NSFontManager.shared.weight(of: regular), "Emphasis must select a heavier actual font: \(choice.label)")
        }
    }
    for choice in [FontChoice.notoSans, .notoSerif, .wenkai, .genryu] {
        let font = choice.font(size: 32, bold: false)
        try require("愛情的大壞蛋".unicodeScalars.allSatisfy { font.coveredCharacterSet.contains($0) }, "Chinese fonts must include full Chinese lyric glyphs")
    }
    func runFont(_ label: NSTextField, _ substring: String) throws -> NSFont {
        let index = (label.stringValue as NSString).range(of: substring).location
        guard index != NSNotFound,
              let font = label.attributedStringValue.attribute(.font, at: index, effectiveRange: nil) as? NSFont else {
            throw CheckError(description: "Missing font run for \(substring)")
        }
        return font
    }
    try require(chineseFont.selectedTag() == FontChoice.allCases.firstIndex(of: .pingfang), "Chinese default must stay independent from English")
    try require(font.bounds.width < 170 && chineseFont.bounds.width < 170, "Font selectors must fit their selected names")
    try require(!chineseFont.itemTitles.contains("OpenDyslexic"), "Chinese font choices must cover Chinese glyphs")
    chineseFont.selectItem(withTag: FontChoice.allCases.firstIndex(of: .wenkai)!); try send(chineseFont)
    font.selectItem(withTitle: "OpenDyslexic"); try send(font)
    panel.lyricsView.show(current: "中文 Hello 123，World 👩🏽‍💻 𠀀", next: "下一句 Next", detail: "Mixed-script fixture")
    let chineseRun = try runFont(panel.lyricsView.current, "中")
    let englishRun = try runFont(panel.lyricsView.current, "Hello")
    let numberRun = try runFont(panel.lyricsView.current, "123")
    let punctuationRun = try runFont(panel.lyricsView.current, "，")
    try require(chineseRun.fontName == "LXGWWenKai-Medium" && punctuationRun.fontName == chineseRun.fontName, "Chinese text and punctuation must use the selected Chinese font")
    try require(englishRun.fontName == "OpenDyslexic-Bold" && numberRun.fontName == englishRun.fontName, "English and digits in the same line must use the selected English font")
    try require(panel.lyricsView.current.stringValue == "中文 Hello 123，World 👩🏽‍💻 𠀀", "Emoji and supplementary Chinese characters must stay intact")
    font.selectItem(withTitle: "Inter"); try send(font)
    let unchangedChinese = try runFont(panel.lyricsView.current, "中")
    try require(unchangedChinese.fontName == chineseRun.fontName, "Changing English font must leave Chinese unchanged")
    chineseFont.selectItem(withTag: FontChoice.allCases.firstIndex(of: .notoSerif)!); try send(chineseFont)
    let interRun = try runFont(panel.lyricsView.current, "Hello")
    try require(interRun.familyName == "Inter", "Changing Chinese font must leave English unchanged")
    // Font updates must also reach subsequent playback lines, not only the existing preview.
    panel.lyricsView.show(current: "新的中文 New line", next: "下一句 Next", detail: "Next lyric")
    let newChinese = try runFont(panel.lyricsView.current, "新"), newEnglish = try runFont(panel.lyricsView.current, "New")
    try require(newChinese.familyName == "Noto Serif SC" && newEnglish.familyName == "Inter", "New lyric text must retain both font selections")
    chineseFont.selectItem(withTag: FontChoice.allCases.firstIndex(of: .pingfang)!); try send(chineseFont)
    panel.lyricsView.show(current: "Let the melody stay", next: "让文字跟着时间", detail: "Check")
    size.doubleValue = 46; try send(size)
    try require(panel.lyricsView.current.font?.pointSize == 46 && settings.scene.lyrics.current.font?.pointSize == 46, "Size must update real lyrics and preview")
    color.color = NSColor(hex: "F7CC74")!; try send(color)
    try require(panel.lyricsView.current.textColor?.rgbHex == "F7CC74", "Color must update real lyrics")
    font.selectItem(withTitle: "OpenDyslexic"); try send(font)
    let currentEnglish = try runFont(panel.lyricsView.current, "Let")
    let nextChinese = try runFont(panel.lyricsView.next, "让")
    try require(currentEnglish.fontName == "OpenDyslexic-Bold" && nextChinese.fontName == "PingFangSC-Regular", "English selection must not replace Chinese glyphs")
    background.selectedSegment = 2; try send(background)
    try require(!panel.lyricsView.effect.isHidden && panel.lyricsView.effect.blendingMode == .behindWindow, "Real glass must blur behind the desktop window")
    let opacity = sliders.first { $0.tag == 2 }!
    opacity.doubleValue = 42; try send(opacity)
    try require(abs(panel.lyricsView.effect.alphaValue - 0.42) < 0.001, "Glass opacity must update live")
    let primaryHEX = fields.first { $0.accessibilityLabel() == "当前句颜色十六进制色值" }!
    primaryHEX.stringValue = "#2ABCDD"
    settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: primaryHEX))
    try require(panel.lyricsView.current.textColor?.rgbHex == "2ABCDD", "HEX typing must update live")
    let primarySize = fields.first { $0.accessibilityLabel() == "当前句字号数值" }!
    primarySize.stringValue = "64"
    settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: primarySize))
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(panel.lyricsView.current.frame.maxY <= panel.lyricsView.bounds.maxY && panel.lyricsView.next.frame.minY >= 0, "Largest OpenDyslexic font must fit the desktop panel")
    let lock = views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "鼠标穿透" }!
    lock.state = .on; try send(lock)
    try require(panel.ignoresMouseEvents, "Lock must reach actual panel")
    lock.performClick(nil)
    try require(!panel.ignoresMouseEvents, "Native switch activation must toggle the actual window")
    settings.window.orderOut(nil)
    let top = views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "歌词置顶" }!
    top.state = .off; try send(top)
    try require(panel.level == .normal, "Always-on-top toggle must reach actual panel")
    chineseFont.selectItem(withTag: FontChoice.allCases.firstIndex(of: .wenkai)!); try send(chineseFont)
    defaults.synchronize()
    let data = try JSONEncoder().encode(settings.style)
    let child = Process()
    child.executableURL = Bundle.main.executableURL!
    child.arguments = ["--verify-store", suite, data.base64EncodedString()]
    try child.run(); child.waitUntilExit()
    try require(child.terminationStatus == 0, "Saved appearance must restore in a new process")
    presets.selectedSegment = 1; try send(presets)
    try require(!panel.lyricsView.effect.isHidden, "Dark glass preset must enable frosted glass")
    presets.selectedSegment = 2; try send(presets)
    try require(panel.lyricsView.effect.isHidden && panel.lyricsView.current.textColor?.rgbHex == "242A33", "Light preset must apply background and text together: selected=\(presets.selectedSegment), style=\(settings.style.background), color=\(settings.style.primaryColor)")
    try require(settings.style.backgroundColor == "FFF2F6", "Light card must use the requested brand color")
    for choice in FontChoice.allCases {
        var style = LyricsAppearance(); style.englishFont = choice
        panel.apply(style)
        try require(panel.lyricsView.current.font?.pointSize == 32, "Font choice \(choice) must render at requested size")
    }
    var invalid = LyricsAppearance(); invalid.primarySize = 900; invalid.primaryColor = "invalid"; invalid.opacity = -1
    store.save(invalid)
    try require(store.load().primarySize == 64 && store.load().primaryColor == "FFFFFF" && store.load().opacity == 0, "Persisted values must stay within supported ranges")
    var legacy = LyricsAppearance()
    legacy.englishFont = .wenkai; legacy.primarySize = 41; legacy.backgroundColor = "AABBCC"
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
    legacyJSON.removeValue(forKey: "chineseFont")
    legacyJSON.removeValue(forKey: "companionVisible")
    legacyJSON.removeValue(forKey: "companionMotion")
    defaults.set(try JSONSerialization.data(withJSONObject: legacyJSON), forKey: "appearance-v1")
    var migrated = store.load()
    try require(!migrated.petEnabled && migrated.petMotion == .gentle, "Legacy settings must migrate with companion off")
    try require(migrated.chineseFont == .wenkai && migrated.englishFont == .wenkai && migrated.primarySize == 41 && migrated.backgroundColor == "AABBCC", "Legacy font settings must migrate without losing appearance")
    migrated.englishFont = .openDyslexic
    try require(migrated.chineseFont == .wenkai, "Migrated Chinese selection must stay fixed when English is edited")
    legacyJSON["font"] = "rounded"
    defaults.set(try JSONSerialization.data(withJSONObject: legacyJSON), forKey: "appearance-v1")
    let migratedEnglish = store.load()
    try require(migratedEnglish.englishFont == .rounded && migratedEnglish.chineseFont == .pingfang && migratedEnglish.primarySize == 41, "Legacy English choices must retain their font with an independent Chinese default")
    let playbackNavigation = views.compactMap { $0 as? SettingsSidebarButton }.first { $0.title == "播放与歌词" }!
    playbackNavigation.performClick(nil)
    try require(settings.selectedPage == .playback, "Sidebar must switch to playback")
    let mode = views.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles == ["自动识别", "Spotify", "Apple Music"] }!
    mode.selectItem(at: 2); try send(mode)
    try require(playerSelections == [2], "Player selection must reach the app")
    for button in views.compactMap({ $0 as? NSControl }) where button.action.map(NSStringFromSelector) == "performAction:" { try send(button) }
    try require(Set(actions.map(\.rawValue)) == Set(SettingsAction.allCases.map(\.rawValue)), "Every moved setting action must remain reachable")
    settings.updatePlayback(SettingsPlaybackState(modeIndex: 2, player: "Apple Music", title: "Test song", artist: "Test artist", status: "已暂停", source: "本地 LRC", hasTrack: true))
    try require(fields.contains { $0.stringValue == "Test song" }, "Now playing state must update settings")
    settings.showPage(.about)
    try require(settings.selectedPage == .about, "About page must be reachable")
    var quickActions: [QuickMenuAction] = []
    let quick = QuickMenu { quickActions.append($0) }
    quick.update(visible: true, locked: true)
    let quickItems = quick.menu.items.filter { !$0.isSeparatorItem }
    try require(quickItems.map(\.title) == ["隐藏歌词", "锁定位置", "设置…", "退出 LyricGlass"], "Quick menu must contain only four common actions")
    try require(quickItems[1].state == .on, "Menu must reflect lock state")
    for item in quickItems { try require(NSApp.sendAction(item.action!, to: item.target, from: item), "Quick menu action must be connected") }
    try require(quickActions.count == 4, "All quick menu actions must reach the app")
    try require(changed >= 10, "Controls must notify the app")
    print("PASS native settings → real lyrics: fonts, sizes, colors, glass, opacity, presets, window controls and fresh-process persistence")
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--verify-store" {
    let suite = CommandLine.arguments[2]
    guard suite.hasPrefix("ai.yufan.lyricglass.appearance-checks."),
          let data = Data(base64Encoded: CommandLine.arguments[3]),
          let expected = try? JSONDecoder().decode(LyricsAppearance.self, from: data),
          AppearanceStore(defaults: UserDefaults(suiteName: suite)!).load() == expected else { exit(1) }
    print("PASS appearance restored in a new process")
} else {
    _ = NSApplication.shared
    do {
        if let index = CommandLine.arguments.firstIndex(of: "--compact-snapshots"), index + 1 < CommandLine.arguments.count {
            try exportCompactPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        } else if let index = CommandLine.arguments.firstIndex(of: "--wrapping-snapshots"), index + 1 < CommandLine.arguments.count {
            try exportWrappingPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        } else if let index = CommandLine.arguments.firstIndex(of: "--island-snapshot"), index + 1 < CommandLine.arguments.count {
            try registerAppearanceFonts()
            let island = IslandPanel()
            var style = LyricsAppearance(); style.chineseFont = .wenkai; style.englishFont = .inter
            style.presentation.islandPinned = true
            island.apply(style)
            if CommandLine.arguments.contains("--notch") {
                island.islandView.geometry = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900), topInset: 32, notchWidth: 200)
                island.setFrame(NSRect(x: 0, y: 0, width: 480, height: island.islandView.expandedHeight), display: true)
            }
            island.islandView.show(current: "让旋律 stay with me", next: "让时间慢一点 · Stay awhile", title: "窗边的旋律", artist: "LyricGlass 原创演示", playing: true, canControl: true, position: 15, duration: 40, error: "")
            let view = island.islandView
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot render island") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckError(description: "Cannot encode island") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("PASS island preview exported: \(view.bounds)")
        } else if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            try registerAppearanceFonts()
            let lightCard = CommandLine.arguments.contains("--light-card")
            var style = LyricsAppearance.preset(lightCard ? 2 : 1)
            let petPage = CommandLine.arguments.contains("--pet")
            if petPage { style.petEnabled = true }
            if !lightCard { style.englishFont = .notoSans }
            if CommandLine.arguments.contains("--font-pair") { style.chineseFont = .wenkai; style.englishFont = .openDyslexic }
            let settings = AppearanceSettings(style: style, onChange: { _ in }, onRecenter: {})
            if CommandLine.arguments.contains("--dark") { settings.window.appearance = NSAppearance(named: .darkAqua) }
            settings.showWindow(page: petPage ? .pet : CommandLine.arguments.contains("--playback") ? .playback : .appearance)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            settings.window.contentView?.layoutSubtreeIfNeeded()
            settings.window.displayIfNeeded()
            print("Window frame: \(settings.window.frame); min=\(settings.window.minSize); root=\(settings.root.frame)")
            try require(settings.root.bounds.height >= 620, "Rendered settings window is too small")
            let view = settings.root, bounds = settings.root.bounds
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw CheckError(description: "Cannot render native settings") }
            view.cacheDisplay(in: bounds, to: bitmap)
            // SceneKit is a GPU surface; explicitly snapshot our own rendered view.
            if petPage {
                let pet = settings.petPreview
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                pet.snapshot().draw(in: pet.convert(pet.bounds, to: view))
                NSGraphicsContext.restoreGraphicsState()
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckError(description: "Cannot encode native settings preview") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("Native settings preview exported: \(Int(bounds.width)) x \(Int(bounds.height))")
        } else { try verify() }
    }
    catch { fputs("Appearance check failed: \(error)\n", stderr); exit(1) }
}
