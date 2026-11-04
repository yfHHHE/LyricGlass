import AppKit
import QuartzCore

struct IslandGeometry {
    var screenFrame: NSRect
    var topInset: CGFloat
    var notchWidth: CGFloat

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
    var hasNotch: Bool { topInset > 0 }
    var contentTopInset: CGFloat { hasNotch ? topInset + 10 : 12 }
    func frame(expanded: Bool, width: CGFloat, height: CGFloat) -> NSRect {
        let desiredWidth = expanded ? max(width, notchWidth + 100) : max(280, notchWidth + 100)
        let actualWidth = min(desiredWidth, max(1, screenFrame.width - 24))
        let actualHeight = min(expanded ? height : max(32, topInset + 6), screenFrame.height)
        return NSRect(x: screenFrame.midX - actualWidth / 2, y: screenFrame.maxY - actualHeight,
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
        islandView.geometry = IslandGeometry(screen: screen)
        islandView.expanded = expanded
        setFrame(islandView.geometry.frame(expanded: expanded, width: style.presentation.islandWidth,
                  height: islandView.expandedHeight), display: true)
    }
    func setExpanded(_ value: Bool, animated: Bool = true) {
        guard expanded != value else { return }
        expanded = value
        islandView.expanded = value
        let frame = islandView.geometry.frame(expanded: value, width: style.presentation.islandWidth,
                                              height: islandView.expandedHeight)
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
    let current = NSTextField(labelWithString: "")
    let next = NSTextField(labelWithString: "")
    let compact = NSButton()
    private let track = NSTextField(labelWithString: "LyricGlass")
    private let status = NSImageView()
    private let settings = NSButton()
    private let progress = NSView()
    private let progressTrack = NSView()
    private var style = LyricsAppearance()
    private var tracking: NSTrackingArea?
    private var fraction: CGFloat = 0
    var onHover: ((Bool) -> Void)?
    var onExpand: (() -> Void)?
    var onSettings: (() -> Void)?
    var geometry = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)) {
        didSet { needsLayout = true }
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
        track.font = .systemFont(ofSize: 11, weight: .medium); track.textColor = .lightGray
        for view in [progressTrack, progress] { view.wantsLayer = true }
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progress.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        status.contentTintColor = .lightGray
        for view in [compact, status, track, current, next, settings, controls, progressTrack, progress] { addSubview(view) }
        updateVisibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var primarySize: CGFloat { min(24, max(16, style.primarySize * 0.65)) }
    private var secondarySize: CGFloat { min(20, max(12, style.secondarySize * 0.65)) }
    private var firstHeight: CGFloat { LyricsTypography.lineHeight(style: style, size: primarySize, bold: style.bold) }
    private var secondHeight: CGFloat { LyricsTypography.lineHeight(style: style, size: secondarySize, bold: false) }
    var expandedHeight: CGFloat {
        geometry.contentTopInset + 22 + firstHeight + (style.presentation.showNextLine ? style.lineGap + secondHeight : 0)
            + (style.presentation.showControls ? 38 : 0) + 14
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
    }
    func show(current text: String, next upcoming: String, title: String, artist: String,
              playing: Bool, canControl: Bool, position: Double, duration: Double, error: String) {
        if current.stringValue != text { updateText(current, text: text, primary: true) }
        if next.stringValue != upcoming { updateText(next, text: upcoming, primary: false) }
        let metadata = error.isEmpty ? [title, artist].filter { !$0.isEmpty }.joined(separator: " · ") : error
        if track.stringValue != metadata { track.stringValue = metadata }
        let compactText = geometry.hasNotch ? "" : "  " + text
        if compact.attributedTitle.string != compactText {
            compact.attributedTitle = NSAttributedString(string: compactText, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
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
        needsLayout = true
    }
    private func updateVisibility() {
        compact.isHidden = expanded; status.isHidden = expanded
        for view in [track, current, settings, progressTrack, progress] { view.isHidden = !expanded }
        next.isHidden = !expanded || !style.presentation.showNextLine
        controls.isHidden = !expanded || !style.presentation.showControls
        layer?.cornerRadius = expanded ? 22 : 16
    }
    override func layout() {
        super.layout()
        compact.frame = NSRect(x: 14, y: 2, width: max(0, bounds.width - 52), height: bounds.height - 4)
        status.frame = NSRect(x: bounds.width - 32, y: (bounds.height - 16) / 2, width: 16, height: 16)
        var top = bounds.height - geometry.contentTopInset
        track.frame = NSRect(x: 40, y: top - 16, width: max(0, bounds.width - 80), height: 16)
        settings.frame = NSRect(x: bounds.width - 32, y: top - 19, width: 24, height: 24)
        top -= 22
        current.frame = NSRect(x: 20, y: top - firstHeight, width: max(0, bounds.width - 40), height: firstHeight)
        top -= firstHeight + style.lineGap
        next.frame = NSRect(x: 20, y: top - secondHeight, width: max(0, bounds.width - 40), height: secondHeight)
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
