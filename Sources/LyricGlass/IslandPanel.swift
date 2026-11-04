import AppKit
import QuartzCore

struct IslandGeometry {
    var screenFrame: NSRect
    var topInset: CGFloat
    var notchWidth: CGFloat
    var topOffset: CGFloat = 0

    init(screenFrame: NSRect, topInset: CGFloat = 0, notchWidth: CGFloat = 0) {
        self.screenFrame = screenFrame; self.topInset = topInset; self.notchWidth = notchWidth
    }
    init(screen: NSScreen) {
        screenFrame = screen.frame
        topInset = screen.safeAreaInsets.top
        if topInset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
    }
    var hasNotch: Bool { topInset > topOffset }
    var contentTopInset: CGFloat { hasNotch ? topInset - topOffset + 10 : 12 }
    func frame(expanded: Bool, width: CGFloat, height: CGFloat, compactWidth: CGFloat = 420, compactHeight: CGFloat = 24) -> NSRect {
        let desiredWidth = max(expanded ? max(width, compactWidth) : compactWidth, hasNotch ? notchWidth + 100 : 0)
        let actualWidth = min(desiredWidth, max(1, screenFrame.width - 24))
        let actualHeight = min(expanded ? height : max(compactHeight, hasNotch ? topInset - topOffset + 4 : 0), max(1, screenFrame.height - topOffset - 12))
        return NSRect(x: screenFrame.midX - actualWidth / 2, y: screenFrame.maxY - topOffset - actualHeight,
                      width: actualWidth, height: actualHeight)
    }
}

final class IslandPanel: NSPanel {
    let islandView = IslandView()
    private(set) var expanded = false
    private var style = LyricsAppearance()
    private var collapse: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    var onSettings: (() -> Void)? {
        didSet { islandView.onSettings = onSettings }
    }
    var onPlaybackAction: ((SettingsAction) -> Void)? {
        didSet { islandView.controls.onAction = onPlaybackAction }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 32),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "LyricGlass · 灵动岛"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        contentView = islandView
        islandView.onPreferredHeightChange = { [weak self] in
            guard let self, self.expanded else { return }
            self.resizeToFitContent()
        }
        islandView.onHover = { [weak self] hovered in
            guard let self else { return }
            self.collapse?.cancel()
            if hovered { self.setExpanded(true) }
            else if !self.style.presentation.islandPinned {
                let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
                self.collapse = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        }
        islandView.onExpand = { [weak self] in self?.setExpanded(true) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        apply(style)
    }
    deinit {
        collapse?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ value: LyricsAppearance) {
        let wasPinned = style.presentation.islandPinned
        style = value.normalized()
        islandView.apply(style)
        if style.presentation.islandPinned { collapse?.cancel(); expanded = true }
        else if wasPinned { expanded = false }
        reposition()
    }
    func reposition() {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        var geometry = IslandGeometry(screen: screen)
        geometry.topOffset = style.presentation.islandAppearance.topOffset
        islandView.geometry = geometry
        islandView.expanded = expanded
        resizeToFitContent()
    }
    private func resizeToFitContent() {
        let target = targetFrame
        if target != frame { setFrame(target, display: true) }
    }
    private var targetFrame: NSRect {
        let options = style.presentation.islandAppearance
        return islandView.geometry.frame(expanded: expanded, width: style.presentation.islandWidth,
            height: islandView.expandedHeight, compactWidth: options.compactWidth, compactHeight: options.compactHeight)
    }
    func setExpanded(_ value: Bool, animated: Bool = true) {
        guard expanded != value else { return }
        expanded = value
        islandView.expanded = value
        let frame = targetFrame
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else { setFrame(frame, display: true) }
    }
}

final class IslandView: NSView {
    let controls = PlaybackControls(dark: true)
    let current = LyricsTextField("")
    let next = LyricsTextField("")
    let compact = NSButton()
    let textViewport = LyricsTextViewport()
    private let track = NSTextField(labelWithString: "LyricGlass")
    private let status = NSImageView()
    private let settings = NSButton()
    private let progress = NSView()
    private let progressTrack = NSView()
    private var style = LyricsAppearance()
    private var tracking: NSTrackingArea?
    private var fraction: CGFloat = 0
    private var measuredWidth: CGFloat = -1
    private var measuredHeights: (CGFloat, CGFloat) = (0, 0)
    private var compactFontSize: CGFloat = -1
    var onPreferredHeightChange: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onExpand: (() -> Void)?
    var onSettings: (() -> Void)?
    var geometry = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)) {
        didSet { measuredWidth = -1; textViewport.resetPosition(); needsLayout = true }
    }
    var expanded = false { didSet { updateVisibility(); needsLayout = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 16; layer?.masksToBounds = true
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        setAccessibilityElement(false)
        setAccessibilityLabel("LyricGlass 顶部灵动岛")
        compact.target = self; compact.action = #selector(expandIsland)
        compact.isBordered = false; compact.contentTintColor = .white
        compact.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        compact.imagePosition = .imageLeading; compact.alignment = .left
        compact.font = .systemFont(ofSize: 12, weight: .medium)
        compact.cell?.lineBreakMode = .byTruncatingTail
        compact.setAccessibilityLabel("展开灵动岛")
        compact.toolTip = "悬停或点击展开歌词与播放控制"
        settings.isBordered = false; settings.contentTintColor = .lightGray
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        settings.setAccessibilityLabel("灵动岛设置")
        settings.target = self; settings.action = #selector(openSettings)
        for label in [track, current, next] {
            label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
            label.alignment = .center; label.isSelectable = false
        }
        for label in [current, next] { LyricsTypography.configureWrapping(label); textViewport.textDocument.addSubview(label) }
        track.font = .systemFont(ofSize: 11, weight: .medium); track.textColor = .lightGray
        for view in [progressTrack, progress] { view.wantsLayer = true }
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progress.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        status.contentTintColor = .lightGray
        for view in [compact, status, track, textViewport, settings, controls, progressTrack, progress] { addSubview(view) }
        updateVisibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var primarySize: CGFloat { min(24, max(16, style.primarySize * 0.65)) }
    private var secondarySize: CGFloat { min(20, max(12, style.secondarySize * 0.65)) }
    private func textHeights(width: CGFloat) -> (CGFloat, CGFloat) {
        if measuredWidth != width {
            measuredHeights = (
                LyricsTypography.wrappedHeight(current, width: max(1, width), minimum: LyricsTypography.lineHeight(style: style, size: primarySize, bold: style.bold)),
                style.presentation.showNextLine ? LyricsTypography.wrappedHeight(next, width: max(1, width), minimum: LyricsTypography.lineHeight(style: style, size: secondarySize, bold: false)) : 0)
            measuredWidth = width
        }
        return measuredHeights
    }
    var expandedHeight: CGFloat {
        let width = geometry.frame(expanded: true, width: style.presentation.islandWidth, height: 1,
            compactWidth: style.presentation.islandAppearance.compactWidth).width - 40
        let (first, second) = textHeights(width: width)
        let preferred = geometry.contentTopInset + 22 + first + (style.presentation.showNextLine ? style.lineGap + second : 0)
            + (style.presentation.showControls ? 38 : 0) + 14
        let minimum = geometry.contentTopInset + 22 + LyricsTypography.lineHeight(style: style, size: primarySize, bold: style.bold)
            + (style.presentation.showControls ? 38 : 0) + 14
        return min(preferred, max(minimum, style.presentation.islandAppearance.expandedMaxHeight))
    }
    func apply(_ value: LyricsAppearance) {
        style = value.normalized()
        updateText(current, text: current.stringValue, primary: true)
        updateText(next, text: next.stringValue, primary: false)
        updateVisibility(); needsLayout = true
    }
    private func updateText(_ label: NSTextField, text: String, primary: Bool) {
        label.attributedStringValue = LyricsTypography.attributedText(text, style: style,
            size: primary ? primarySize : secondarySize, bold: primary && style.bold,
            color: primary ? .white : NSColor.white.withAlphaComponent(0.65))
        measuredWidth = -1; textViewport.resetPosition()
    }
    func show(current text: String, next upcoming: String, title: String, artist: String,
              playing: Bool, canControl: Bool, position: Double, duration: Double, error: String) {
        let changed = current.stringValue != text || next.stringValue != upcoming
        if current.stringValue != text { updateText(current, text: text, primary: true) }
        if next.stringValue != upcoming { updateText(next, text: upcoming, primary: false) }
        let metadata = error.isEmpty ? [title, artist].filter { !$0.isEmpty }.joined(separator: " · ") : error
        if track.stringValue != metadata { track.stringValue = metadata }
        let compactText = geometry.hasNotch ? "" : "  " + text
        let fontSize = min(12, max(10, style.presentation.islandAppearance.compactHeight - 6))
        if compact.attributedTitle.string != compactText || compactFontSize != fontSize {
            compactFontSize = fontSize
            compact.attributedTitle = NSAttributedString(string: compactText, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: NSColor.white])
        }
        compact.setAccessibilityValue(text)
        compact.toolTip = [title, text, error].filter { !$0.isEmpty }.joined(separator: "\n")
        let symbol = playing ? "waveform" : "pause.fill"
        if status.toolTip != symbol {
            status.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playing ? "播放中" : "已暂停")
            status.toolTip = symbol
        }
        controls.update(playing: playing, enabled: canControl)
        fraction = duration > 0 && position.isFinite ? CGFloat(min(1, max(0, position / duration))) : 0
        if changed { onPreferredHeightChange?() }
        needsLayout = true
    }
    private func updateVisibility() {
        compact.isHidden = expanded; status.isHidden = expanded
        for view in [track, textViewport, settings, progressTrack, progress] { view.isHidden = !expanded }
        next.isHidden = !expanded || !style.presentation.showNextLine
        controls.isHidden = !expanded || !style.presentation.showControls
        layer?.cornerRadius = style.presentation.islandAppearance.shape.radius(height: bounds.height, expanded: expanded)
    }
    override func layout() {
        super.layout()
        layer?.cornerRadius = style.presentation.islandAppearance.shape.radius(height: bounds.height, expanded: expanded)
        compact.frame = NSRect(x: 10, y: 2, width: max(0, bounds.width - 44), height: bounds.height - 4)
        let iconSize = min(14, bounds.height - 6)
        status.frame = NSRect(x: bounds.width - 28, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        var top = bounds.height - geometry.contentTopInset
        track.frame = NSRect(x: 40, y: top - 16, width: max(0, bounds.width - 80), height: 16)
        settings.frame = NSRect(x: bounds.width - 32, y: top - 19, width: 24, height: 24)
        top -= 22
        let width = max(1, bounds.width - 40)
        let (first, second) = textHeights(width: width)
        let gap = style.presentation.showNextLine ? style.lineGap : 0
        let total = first + second + gap
        let bottom: CGFloat = (style.presentation.showControls ? 38 : 0) + 14
        textViewport.frame = NSRect(x: 20, y: bottom, width: width, height: max(0, top - bottom))
        textViewport.fitDocument(height: total)
        let documentHeight = textViewport.textDocument.bounds.height
        current.frame = NSRect(x: 0, y: documentHeight - first, width: width, height: first)
        next.frame = NSRect(x: 0, y: documentHeight - total, width: width, height: second)
        controls.frame = NSRect(x: (bounds.width - 144) / 2, y: 10, width: 144, height: 32)
        progressTrack.frame = NSRect(x: 24, y: 3, width: max(0, bounds.width - 48), height: 2)
        progress.frame = NSRect(x: 24, y: 3, width: max(0, bounds.width - 48) * fraction, height: 2)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    @objc private func expandIsland() { onExpand?() }
    @objc private func openSettings() { onSettings?() }
}
