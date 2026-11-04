import AppKit

private func paintedBands(_ view: NSView) throws -> ([(Int, Int)], CGFloat) {
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot measure visual spacing") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    var bands: [(Int, Int)] = []
    var start: Int?
    for y in 0..<bitmap.pixelsHigh {
        let painted = (0..<bitmap.pixelsWide).contains { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.5 }
        if painted && start == nil { start = y }
        if !painted, let first = start { bands.append((first, y - 1)); start = nil }
    }
    if let start { bands.append((start, bitmap.pixelsHigh - 1)) }
    return (bands, CGFloat(bitmap.pixelsHigh) / view.bounds.height)
}

func verifyCompactLayouts() throws {
    var style = LyricsAppearance()
    style.primarySize = 26; style.secondarySize = 18; style.lineGap = 0; style.shadow = false
    style.chineseFont = .notoSerif; style.englishFont = .openDyslexic
    let panel = LyricsPanel(); panel.apply(style)
    panel.lyricsView.show(current: "國", next: "國", detail: "Spacing fixture")
    panel.lyricsView.layoutSubtreeIfNeeded()
    let compactHeight = panel.frame.height
    let (bands, scale) = try paintedBands(panel.lyricsView)
    try require(bands.count == 2, "Zero spacing must retain two separate visible glyph bands")
    let gap = CGFloat(bands[1].0 - bands[0].1 - 1) / scale
    try require(gap <= 4, "Zero gap must remove unused font leading, including an unused English typeface")
    style.lineGap = 12; panel.apply(style)
    let (spaced, secondScale) = try paintedBands(panel.lyricsView)
    try require(spaced.count == 2 && CGFloat(spaced[1].0 - spaced[0].1 - 1) / secondScale >= 12, "Sentence gap must control the visual distance between glyphs")
    try require(panel.frame.height == compactHeight + 12, "Gap changes must not add hidden layout padding")
    style.lineGap = 0; style.presentation.showControls = false; panel.apply(style)
    try require(panel.frame.height == compactHeight, "Playback controls must not reserve permanent desktop height")
    style.presentation.showControls = true; style.petEnabled = true; panel.apply(style)
    try require(panel.frame.height < 100, "The companion must adapt to the compact text rather than force a 150pt window")
    for sample in ["Ág jøy", "👩🏽‍💻", "中文 Ág 👩🏽‍💻 𠀀"] {
        let field = LyricsTextField(sample)
        field.font = style.englishFont.font(size: 26, bold: false)
        field.attributedStringValue = LyricsTypography.attributedText(sample, style: style, size: 26, bold: false, color: .white)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: field.height(fittingWidth: 300))
        let (ink, pixelScale) = try paintedBands(field)
        try require(!ink.isEmpty && ink.first!.0 > 0 && CGFloat(ink.last!.1) < field.bounds.height * pixelScale - 1, "Drawing safety for \(sample): ink=\(ink), height=\(field.bounds.height), scale=\(pixelScale), opaque=\(field.isOpaque)")
    }
    panel.orderFrontRegardless(); panel.lyricsView.setHovered(true)
    try require(panel.transportPanel.isVisible && !panel.frame.intersects(panel.transportPanel.frame), "Hover controls must be outside the lyric window")
    panel.lyricsView.setHovered(false); panel.transportPanel.onHover?(true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    try require(panel.transportPanel.isVisible, "Controls must remain clickable when the pointer moves from lyrics to the toolbar")
    panel.transportPanel.onHover?(false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    try require(!panel.transportPanel.isVisible && panel.transportPanel.parent == nil, "Leaving both windows must hide and detach controls")
    panel.lyricsView.setHovered(true); panel.orderOut(nil)
    try require(!panel.transportPanel.isVisible, "Hiding desktop lyrics must never leave orphaned controls")

    let island = IslandPanel()
    let suite = "ai.yufan.lyricglass.appearance-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppearanceStore(defaults: defaults)
    let settings = AppearanceSettings(style: style, onChange: { store.save($0); island.apply($0) }, onRecenter: {})
    settings.showWindow(); settings.window.orderOut(nil)
    let views = descendants(settings.root)
    let sliders = views.compactMap { $0 as? NSSlider }
    for (tag, value) in [(8, 640.0), (9, 20.0), (10, 180.0), (11, 24.0)] {
        let slider = sliders.first { $0.tag == tag }!; slider.doubleValue = value; try send(slider)
    }
    let shape = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "顶部窗口形状" }!
    shape.selectItem(at: 2); try send(shape)
    let saved = store.load().presentation.islandAppearance
    try require(saved.compactWidth == 640 && saved.compactHeight == 20 && saved.expandedMaxHeight == 180 && saved.topOffset == 24 && saved.shape == .rectangle, "Every new native control must save its own value")
    try require(store.load().presentation.islandWidth >= saved.compactWidth, "Expanded island must not shrink away from a pointer on the wider compact window")
    island.islandView.layoutSubtreeIfNeeded()
    try require(island.islandView.layer?.cornerRadius == 0, "Rectangle must have square corners in the actual view")
    let screen = IslandGeometry(screenFrame: NSRect(x: -1000, y: 100, width: 1000, height: 700))
    var shifted = screen; shifted.topOffset = 24
    let compact = shifted.frame(expanded: false, width: 480, height: 300, compactWidth: 640, compactHeight: 20)
    try require(compact.size == NSSize(width: 640, height: 20) && compact.maxY == 776, "Collapsed size and vertical position must follow their controls")
    var changed = store.load(); changed.presentation.islandPinned = true; island.apply(changed)
    island.islandView.show(current: String(repeating: "让每一个字都被看见 ", count: 50), next: "下一句", title: "Test", artist: "Test", playing: false, canControl: true, position: 0, duration: 100, error: "")
    try require(island.frame.height <= 180, "Expanded height must respect the configured maximum while preserving scrollable lyrics")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style.normalized())) as! [String: Any]
    var presentation = legacy["presentationOptions"] as! [String: Any]
    presentation.removeValue(forKey: "islandOptions"); presentation["desktopWidth"] = 731
    legacy["presentationOptions"] = presentation
    let migrated = try JSONDecoder().decode(LyricsAppearance.self, from: JSONSerialization.data(withJSONObject: legacy)).normalized()
    try require(migrated.presentation.desktopWidth == 731 && migrated.chineseFont == .notoSerif && migrated.englishFont == .openDyslexic && migrated.lineGap == 0, "Existing v0.6.1 settings must survive the new nested options")
    try require(migrated.presentation.islandAppearance.compactWidth == 420 && migrated.presentation.islandAppearance.compactHeight == 24, "Existing users receive wider, lower compact defaults")
    print("PASS compact layouts: visual zero-gap \(gap)pt, desktop \(compactHeight)pt, independent dimensions, shapes, toolbar lifecycle and settings migration")
}

func exportCompactPreviews(to directory: URL) throws {
    try registerAppearanceFonts()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func save(_ view: NSView, _ name: String) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot snapshot compact layout") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        print("PASS compact preview \(name): \(view.bounds.size)")
    }
    var style = LyricsAppearance.preset(2)
    style.primarySize = 26; style.secondarySize = 18; style.lineGap = 0
    style.chineseFont = .notoSerif; style.englishFont = .openDyslexic
    style.presentation.desktopWidth = 600
    let panel = LyricsPanel(); panel.apply(style)
    panel.lyricsView.show(current: "让旋律停在窗边", next: "让文字跟着时间", detail: "")
    try save(panel.lyricsView, "desktop-zero-gap")
    let island = IslandPanel()
    style.presentation.islandAppearance.compactWidth = 540
    style.presentation.islandAppearance.compactHeight = 22
    for shape in IslandShape.allCases {
        style.presentation.islandAppearance.shape = shape; island.apply(style)
        island.islandView.show(current: "让旋律 stay with me · 每一句都看得见", next: "下一句", title: "LyricGlass", artist: "Demo", playing: true, canControl: true, position: 10, duration: 100, error: "")
        try save(island.islandView, "top-" + shape.rawValue)
    }
}
