import AppKit

private let longLyric = String(repeating: "让旋律穿过漫长街道 stay with me 直到每一个字都被看见，", count: 3) + "终章 END"

private func requireCompleteGlyphLayout(_ label: NSTextField) throws {
    let storage = NSTextStorage(attributedString: label.attributedStringValue)
    let manager = NSLayoutManager()
    let drawing = label.cell?.drawingRect(forBounds: label.bounds) ?? label.bounds
    let container = NSTextContainer(containerSize: drawing.size)
    container.lineFragmentPadding = 0
    manager.addTextContainer(container); storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let range = manager.glyphRange(for: container)
    try require(range.length == manager.numberOfGlyphs, "Every glyph, including the ending, must fit its wrapped field")
    try require(manager.usedRect(for: container).maxY <= drawing.height + 0.5, "Mixed-font wrapped glyphs must fit vertically")
    try require(manager.usedRect(for: container).maxX <= drawing.width + 0.5, "Unbroken words must wrap within the field width")
    try require(label.maximumNumberOfLines == 0 && !label.allowsDefaultTighteningForTruncation, "Long lyrics must neither truncate nor tighten their letter spacing")
}

func verifyWrapping() throws {
    var style = LyricsAppearance()
    style.primarySize = 32; style.secondarySize = 24; style.lineGap = 18
    style.chineseFont = .notoSerif; style.englishFont = .openDyslexic
    style.presentation.desktopWidth = 480; style.presentation.islandWidth = 320
    let panel = LyricsPanel(); panel.apply(style)
    panel.lyricsView.show(current: "短句 Short", next: "下一句 Next", detail: "Check")
    panel.lyricsView.layoutSubtreeIfNeeded()
    let shortHeight = panel.frame.height, bottom = panel.frame.minY
    panel.lyricsView.show(current: longLyric, next: longLyric, detail: "Check")
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(panel.frame.height > shortHeight, "New long lyrics must immediately grow the real desktop window")
    try require(panel.lyricsView.current.font?.pointSize == 32 && panel.lyricsView.next.font?.pointSize == 24, "Wrapping must retain both selected font sizes")
    try require(panel.lyricsView.current.stringValue == longLyric, "Wrapping must retain the exact original lyric")
    try require(abs(panel.lyricsView.current.frame.minY - panel.lyricsView.next.frame.maxY - 18) < 0.1, "Sentence spacing must remain separate from wrapped line spacing")
    try requireCompleteGlyphLayout(panel.lyricsView.current)
    try requireCompleteGlyphLayout(panel.lyricsView.next)
    let narrowHeight = panel.frame.height
    style.presentation.desktopWidth = 1000; panel.apply(style)
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(panel.frame.height < narrowHeight, "Increasing width must reflow and reduce window height")
    try require(abs(panel.frame.minY - bottom) < 0.1, "Normal resizing must preserve the desktop window's bottom anchor")
    let text = String(repeating: "Supercalifragilistic", count: 12) + " 👩🏽‍💻 𠀀 日本語の歌詞 END"
    panel.lyricsView.show(current: text, next: "下一句", detail: "")
    panel.lyricsView.layoutSubtreeIfNeeded()
    try requireCompleteGlyphLayout(panel.lyricsView.current)
    let enormous = String(repeating: longLyric + "\n", count: 40)
    panel.lyricsView.show(current: enormous, next: "尾声", detail: "")
    panel.lyricsView.layoutSubtreeIfNeeded()
    if let visible = NSScreen.screens.first?.visibleFrame {
        try require(visible.contains(panel.frame), "An unusually long paragraph must keep its window on screen")
    }
    let viewport = panel.lyricsView.textViewport
    try require(viewport.textDocument.bounds.height > viewport.contentSize.height, "Screen-sized text must remain available through a scroll viewport")
    try require(abs(viewport.documentVisibleRect.maxY - viewport.textDocument.bounds.maxY) < 1, "A new paragraph must initially show its beginning")
    viewport.contentView.scroll(to: .zero); viewport.reflectScrolledClipView(viewport.contentView)
    try require(viewport.documentVisibleRect.minY == 0, "The end of an unusually long paragraph must be reachable")
    panel.lyricsView.show(current: "短句", next: "下一句", detail: "")
    panel.lyricsView.layoutSubtreeIfNeeded()
    try require(panel.frame.height < narrowHeight, "Switching back to short lyrics must reclaim height")

    let island = IslandPanel(); island.apply(style); island.setExpanded(true, animated: false)
    let top = island.frame.maxY, initialHeight = island.frame.height
    island.islandView.show(current: longLyric, next: longLyric, title: "测试", artist: "LyricGlass", playing: true, canControl: true, position: 10, duration: 100, error: "")
    island.islandView.layoutSubtreeIfNeeded()
    try require(island.frame.height > initialHeight && island.frame.maxY == top, "New long lyrics must grow an expanded island downwards from its top anchor")
    try requireCompleteGlyphLayout(island.islandView.current)
    try requireCompleteGlyphLayout(island.islandView.next)
    try require(island.islandView.textViewport.frame.minY > island.islandView.controls.frame.maxY, "Wrapped text must not cover transport controls")
    let notched = IslandGeometry(screenFrame: NSRect(x: -900, y: 100, width: 900, height: 700), topInset: 32, notchWidth: 200)
    island.islandView.geometry = notched
    island.setFrame(notched.frame(expanded: true, width: 320, height: island.islandView.expandedHeight), display: true)
    island.islandView.layoutSubtreeIfNeeded()
    try require(island.islandView.textViewport.frame.maxY <= island.islandView.bounds.height - 32, "Wrapped island content must stay below the camera cutout")
    try require(notched.screenFrame.contains(island.frame), "Expanded island must remain in an offset screen's bounds")
    print("PASS wrapping: full mixed-script glyphs, unbroken words, automatic sizing, anchors, scrolling, spacing and notch safety")
}

func exportWrappingPreviews(to directory: URL) throws {
    try registerAppearanceFonts()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func save(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError(description: "Cannot render wrapping preview") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckError(description: "Cannot encode wrapping preview") }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        print("PASS wrapping snapshot \(name): \(view.bounds.size)")
    }
    var style = LyricsAppearance.preset(2)
    style.primarySize = 30; style.secondarySize = 22
    style.chineseFont = .notoSerif; style.englishFont = .openDyslexic
    style.presentation.desktopWidth = 600; style.presentation.islandWidth = 480
    style.presentation.islandPinned = true
    let panel = LyricsPanel(); panel.apply(style)
    panel.lyricsView.show(current: longLyric, next: "下一句也完整显示，让文字跟着时间走到句尾。The words follow time to the end.", detail: "")
    try save(panel.lyricsView, name: "desktop-wrap")
    let island = IslandPanel(); island.apply(style)
    island.islandView.show(current: longLyric, next: "让时间慢一点 · Stay awhile", title: "长歌词换行预览", artist: "LyricGlass", playing: true, canControl: true, position: 20, duration: 100, error: "")
    try save(island.islandView, name: "island-wrap")
    let geometry = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900), topInset: 32, notchWidth: 200)
    island.islandView.geometry = geometry
    island.setFrame(geometry.frame(expanded: true, width: 480, height: island.islandView.expandedHeight), display: true)
    try save(island.islandView, name: "island-wrap-notch")
}
