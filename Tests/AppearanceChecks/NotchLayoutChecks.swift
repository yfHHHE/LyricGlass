import AppKit

func verifyIslandControlBindings() throws {
    var style = LyricsAppearance()
    style.presentation.islandAppearance.compactWidth = 500
    style.presentation.islandAppearance.compactLyricWidth = 100
    let panel = IslandPanel(); panel.apply(style); panel.islandView.layoutSubtreeIfNeeded()
    try require(panel.frame.width == 500 && panel.islandView.compact.frame.width == 100, "Capsule total width and lyric viewport width must control separate bounds")
    style.presentation.islandAppearance.compactLyricWidth = 160
    panel.apply(style); panel.islandView.layoutSubtreeIfNeeded()
    try require(panel.frame.width == 500 && panel.islandView.compact.frame.width == 160, "Changing lyric width must leave the outer capsule width unchanged")
    style.presentation.islandAppearance.compactWidth = 650
    panel.apply(style); panel.islandView.layoutSubtreeIfNeeded()
    try require(panel.frame.width == 650 && panel.islandView.compact.frame.width == 160, "Changing total width must leave the lyric viewport width unchanged")
    style.presentation.islandAppearance.compactWidth = 800
    style.presentation.islandWidth = 400
    try require(style.normalized().presentation.islandWidth == 400, "Stored compact and expanded widths must remain independent")
    for shape in IslandShape.allCases {
        style.presentation.islandAppearance.shape = shape
        panel.apply(style); panel.islandView.layoutSubtreeIfNeeded()
        let expected: CGFloat = shape == .rectangle ? 0 : (shape == .roundedRectangle ? 8 : panel.frame.height / 2)
        try require(panel.islandView.layer?.cornerRadius == expected, "Shape selection must control the collapsed capsule")
    }
    panel.setExpanded(true, animated: false); panel.islandView.layoutSubtreeIfNeeded()
    try require(panel.islandView.layer?.cornerRadius == 18, "Changing capsule shape must leave expanded reading geometry stable")
    print("PASS island control bindings: independent container and lyric viewport widths, capsule shapes and separately stored expansion")
}

func verifyNotchLayouts() throws {
    // Actual 14-inch MacBook screen reported during this fix: camera x=663.5...848.5.
    let mac = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, notchWidth: 185)
    let folded = mac.frame(expanded: false, width: 550, height: 200, compactHeight: 29)
    try require(folded == NSRect(x: 472.5, y: 950, width: 420, height: 32), "Compact mode must use the configured outer width and match the camera height")
    try require(folded.contains(mac.notchFrame), "The black background must enclose the camera housing")
    let left = mac.compactContentBounds(windowFrame: folded).offsetBy(dx: folded.minX, dy: folded.minY)
    try require(left.width == 160 && left.maxX <= mac.notchFrame.minX - 12, "The160pt lyric viewport must remain separate from the container and camera")
    for width in [320.0, 550, 800, 1000] {
        let expanded = mac.frame(expanded: true, width: width, height: 220)
        try require(expanded.midX == mac.notchCenterX && expanded.contains(folded) && mac.screenFrame.contains(expanded), "Centered expansion must contain every compact hover point and remain on screen")
    }
    let offset = IslandGeometry(screenFrame: NSRect(x: -1440, y: 200, width: 1440, height: 900), topInset: 32, notchWidth: 200, notchCenterX: -620)
    let shifted = offset.frame(expanded: false, width: 560, height: 100)
    try require(shifted.minX == -896 && shifted.maxX == -476 && shifted.maxY == 1100, "Use the system camera coordinates even on offset screens and off-center cutouts")
    for geometry in [mac, offset, IslandGeometry(screenFrame: NSRect(x: 200, y: -700, width: 1024, height: 640), topInset: 32, notchWidth: 180)] {
        for width in [360.0, 500, 1000] {
            let compact = geometry.frame(expanded: false, width: 550, height: 200, compactWidth: width)
            let expanded = geometry.frame(expanded: true, width: 550, height: 240, compactWidth: width)
            try require(geometry.screenFrame.contains(compact) && geometry.screenFrame.contains(expanded) && expanded.contains(compact), "Narrow and secondary screens must clamp both states without a hover gap")
            try require(expanded.midX == geometry.notchCenterX, "Independent left widths must never move the expanded center away from the camera")
        }
    }
    let external = IslandGeometry(screenFrame: NSRect(x: 1512, y: -98, width: 1920, height: 1080))
    let ordinary = external.frame(expanded: false, width: 550, height: 100, compactHeight: 29)
    try require(ordinary.size == NSSize(width: 420, height: 29) && ordinary.midX == external.screenFrame.midX, "Unnotched displays must use the outer width setting and keep the capsule centered")
    var lowered = mac; lowered.topOffset = 40
    try require(!lowered.hasNotch && lowered.frame(expanded: false, width: 550, height: 100, compactHeight: 29).midX == 756, "A capsule moved below the camera may use the normal centered layout")

    let panel = IslandPanel()
    var style = LyricsAppearance()
    style.presentation.islandAppearance.compactWidth = 486; style.presentation.islandAppearance.compactHeight = 29
    panel.apply(style)
    let view = panel.islandView
    for geometry in [mac, offset, external, lowered] {
        view.geometry = geometry
        panel.setFrame(geometry.frame(expanded: false, width: 550, height: 100, compactHeight: 29), display: true)
        view.show(current: PreviewLyrics.english[1], next: PreviewLyrics.english[2], title: "歌词示例", artist: "LyricGlass",
            playing: true, canControl: true, position: 25, duration: 100, error: "")
        view.layoutSubtreeIfNeeded()
        try require(view.compact.attributedTitle.string == PreviewLyrics.english[1], "The scrolling title must retain the complete lyric without an extra music icon")
        if geometry.hasNotch {
            try require(panel.frame.minX + view.compact.frame.maxX < geometry.notchFrame.minX, "The entire native lyric button must remain left of the cutout")
            try require(panel.frame.minX + view.compactPlayPause.frame.minX > geometry.notchFrame.maxX, "The actual play/pause button must stay entirely right of the camera")
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot inspect camera region") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let start = Int(ceil((geometry.notchFrame.minX - panel.frame.minX) * scale))
            let end = Int(floor((geometry.notchFrame.maxX - panel.frame.minX) * scale))
            for x in max(0, start)..<min(end, bitmap.pixelsWide) {
                for y in Int(6 * scale)..<(bitmap.pixelsHigh - Int(6 * scale)) {
                    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    if let color, color.alphaComponent > 0.5 {
                        try require(max(color.redComponent, color.greenComponent, color.blueComponent) < 0.08, "The physical camera region must stay black; controls and lyrics belong in separate wings")
                    }
                }
            }
        }
    }
    view.geometry = mac
    panel.setFrame(folded, display: true)
    let long = "Every time 我告訴我自己 — 人群的溫暖輕撫我讓寂寞更熱烈"
    view.show(current: long, next: "I will be okay", title: "Demo", artist: "LyricGlass", playing: true, canControl: true, position: 10, duration: 100, error: "")
    view.layoutSubtreeIfNeeded()
    try require(view.compact.accessibilityValue() as? String == long && view.compact.attributedTitle.string == long, "The full mixed-script line must remain accessible while clipped visually")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        try require(view.compact.isScrolling, "Long lyrics must use the smooth marquee")
        let moving = view.compact.layer!.sublayers!.first!
        let started = moving.animation(forKey: "lyric-scroll")!.beginTime
        view.show(current: long, next: "I will be okay", title: "Demo", artist: "LyricGlass", playing: false, canControl: true, position: 11, duration: 100, error: "")
        view.layoutSubtreeIfNeeded()
        try require(moving.animation(forKey: "lyric-scroll")?.beginTime == started, "Playhead and pause updates must not restart the scrolling lyric")
        panel.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        let first = moving.presentation()?.transform.m41 ?? 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let second = moving.presentation()?.transform.m41 ?? 0
        try require(second < first, "The rendered text must move left over actual elapsed time")
        panel.orderOut(nil)
    }
    var actions: [SettingsAction] = []
    panel.onPlaybackAction = { actions.append($0) }
    try send(view.compactPlayPause)
    try require(actions == [.togglePlayback], "The compact button must route to the same current-player toggle as expanded controls")
    panel.setExpanded(true, animated: false); view.layoutSubtreeIfNeeded()
    try require(!view.compact.isScrolling, "Hidden compact lyrics must stop animating while expanded")
    panel.setExpanded(false, animated: false)
    view.show(current: "Okay", next: "", title: "Demo", artist: "LyricGlass", playing: true, canControl: false, position: 0, duration: 100, error: "")
    view.layoutSubtreeIfNeeded()
    try require(!view.compact.isScrolling && !view.compactPlayPause.isEnabled, "Short lyrics must remain readable, and missing player control must disable the button")
    try require(view.compact.layer?.mask == nil, "A fully visible lyric must not fade or blur its first word")
    let firstText = view.compact.layer?.sublayers?.first?.sublayers?.first
    try require((firstText?.frame.minX ?? 0) >= 6, "The first glyph must begin clear of the scrolling edge")
    let suite = "ai.yufan.lyricglass.notch-settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AppearanceStore(defaults: defaults)
    let settings = AppearanceSettings(style: style, onChange: { store.save($0); panel.apply($0) }, onRecenter: {})
    settings.showWindow(); settings.window.orderOut(nil)
    let slider = descendants(settings.root).compactMap { $0 as? NSSlider }.first { $0.tag == 12 }!
    let requestedWidth = min(240, slider.maxValue)
    slider.doubleValue = requestedWidth; try send(slider)
    panel.islandView.layoutSubtreeIfNeeded()
    try require(store.load().presentation.islandAppearance.compactLyricWidth == requestedWidth && store.load().presentation.islandAppearance.compactWidth == 486, "Native lyric width must save independently of container width")
    if let screen = NSScreen.screens.first {
        let expected = IslandGeometry(screen: screen).frame(expanded: false, width: style.presentation.islandWidth,
            height: 1, compactWidth: style.presentation.islandAppearance.compactWidth, compactHeight: style.presentation.islandAppearance.compactHeight)
        try require(panel.frame.width == expected.width && panel.islandView.compact.frame.width == requestedWidth, "The native lyric slider must change the text viewport without changing the outer panel")
    }
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as! [String: Any]
    var presentation = legacy["presentationOptions"] as! [String: Any]
    var options = presentation["islandOptions"] as! [String: Any]
    options.removeValue(forKey: "leftLyricWidth"); presentation["islandOptions"] = options; legacy["presentationOptions"] = presentation
    let migrated = try JSONDecoder().decode(LyricsAppearance.self, from: JSONSerialization.data(withJSONObject: legacy))
    try require(migrated.presentation.islandAppearance.compactLyricWidth == 160 && migrated.presentation.islandAppearance.compactWidth == 486, "Existing preferences must adopt a short lyric wing without resetting the old capsule width")
    print("PASS notch marquee: real camera boundaries, right-side playback, centered expansion, independent persisted width, mixed-script scrolling, stable progress updates and external capsule")
}

func exportNotchPreviews(to directory: URL) throws {
    try registerAppearanceFonts()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let panel = IslandPanel()
    var style = LyricsAppearance(); style.presentation.islandAppearance.compactWidth = 486; style.presentation.islandAppearance.compactHeight = 29
    let geometries: [(String, IslandGeometry)] = [
        ("macbook-left-bar", IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, notchWidth: 185)),
        ("external-capsule", IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080)))
    ]
    for (name, geometry) in geometries {
        panel.apply(style); panel.islandView.geometry = geometry
        panel.setFrame(geometry.frame(expanded: false, width: 550, height: 100, compactHeight: 29), display: true)
        let view = panel.islandView
        view.show(current: PreviewLyrics.english[1], next: PreviewLyrics.english[2], title: "歌词示例", artist: "LyricGlass", playing: true, canControl: true, position: 25, duration: 100, error: "")
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot snapshot notch layout") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        print("PASS \(name) native preview: \(panel.frame)")
    }
}
