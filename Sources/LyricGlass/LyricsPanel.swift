import AppKit

final class LyricsPanel: NSPanel {
    let lyricsView = LyricsView(frame: NSRect(x: 0, y: 0, width: 940, height: 170))

    init() {
        super.init(contentRect: lyricsView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "LyricGlass · 桌面歌词"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = lyricsView
        lyricsView.onPreferredHeightChange = { [weak self] in self?.resizeForLyrics() }
        apply(LyricsAppearance())
        centerAtBottom()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ style: LyricsAppearance) {
        lyricsView.apply(style)
        var frame = self.frame
        let center = frame.midX
        let visible = (screen ?? NSScreen.screens.first)?.visibleFrame
        frame.size.width = min(style.presentation.desktopWidth, max(1, (visible?.width ?? 980) - 40))
        frame.origin.x = center - frame.width / 2
        frame.size.height = min(lyricsView.height(fittingWidth: frame.width), max(1, (visible?.height ?? 900) - 16))
        if let visible {
            frame.origin.x = min(visible.maxX - frame.width, max(visible.minX, frame.minX))
            frame.origin.y = min(visible.maxY - frame.height, max(visible.minY, frame.minY))
        }
        setFrame(frame, display: true)
        level = style.alwaysOnTop ? .floating : .normal
        ignoresMouseEvents = style.clickThrough
        if style.clickThrough { lyricsView.setHovered(false) }
    }

    private func resizeForLyrics() {
        var frame = self.frame
        let visible = (screen ?? NSScreen.screens.first)?.visibleFrame
        frame.size.height = min(lyricsView.height(fittingWidth: frame.width), max(1, (visible?.height ?? 900) - 16))
        if let visible { frame.origin.y = min(visible.maxY - frame.height, max(visible.minY, frame.minY)) }
        if self.frame != frame { setFrame(frame, display: true) }
    }

    func centerAtBottom() {
        // Keep reopened lyrics discoverable on multi-monitor Macs.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(lyricsView.preferredWidth, visible.width - 40)
        let height = min(lyricsView.height(fittingWidth: width), max(1, visible.height - 16))
        setFrame(NSRect(x: visible.midX - width / 2, y: min(visible.minY + 44, visible.maxY - height),
                        width: width, height: height), display: true)
    }
}

// The settings preview and the real lyrics window use this same renderer.
final class LyricsView: NSView {
    let current = NSTextField(labelWithString: "正在连接播放器…")
    let next = NSTextField(labelWithString: "桌面透明双行歌词")
    let effect = NSVisualEffectView()
    let pet = RaindropPetView(frame: .zero)
    let controls = PlaybackControls()
    let textViewport = LyricsTextViewport()
    private let tint = NSView()
    private let hoverTint = NSView()
    private let detail = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var style = LyricsAppearance()
    private var measuredWidth: CGFloat = -1
    private var measuredHeights: (CGFloat, CGFloat) = (0, 0)
    var onPreferredHeightChange: (() -> Void)?
    var onContextMenu: ((NSEvent, NSView) -> Void)?
    var onPlaybackAction: ((SettingsAction) -> Void)? {
        didSet { controls.onAction = onPlaybackAction }
    }

    init(frame: NSRect, desktop: Bool = true) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        effect.blendingMode = desktop ? .behindWindow : .withinWindow
        effect.material = .hudWindow
        effect.state = .active
        for view in [tint, hoverTint] { view.wantsLayer = true }
        for view in [effect, tint, hoverTint, pet, textViewport, detail, controls] { addSubview(view) }
        for label in [current, next] { textViewport.textDocument.addSubview(label) }
        for label in [current, next, detail] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isSelectable = false
        }
        for label in [current, next] { LyricsTypography.configureWrapping(label) }
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(desktop ? "LyricGlass 桌面双行歌词" : "实时双行歌词外观预览")
        apply(style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func textHeights(width: CGFloat) -> (CGFloat, CGFloat) {
        if measuredWidth != width {
            let available = max(1, width - style.padding * 2 - (style.petEnabled ? 110 : 0))
            measuredHeights = (
                LyricsTypography.wrappedHeight(current, width: available, minimum: LyricsTypography.lineHeight(style: style, size: style.primarySize, bold: style.bold)),
                style.presentation.showNextLine ? LyricsTypography.wrappedHeight(next, width: available, minimum: LyricsTypography.lineHeight(style: style, size: style.secondarySize, bold: false)) : 0)
            measuredWidth = width
        }
        return measuredHeights
    }
    private var controlsHeight: CGFloat { style.presentation.showControls ? 34 : 0 }
    var preferredWidth: CGFloat { style.presentation.desktopWidth }
    func height(fittingWidth width: CGFloat) -> CGFloat {
        let (first, second) = textHeights(width: width)
        return max(style.petEnabled ? 150 : 100, first + second + (style.presentation.showNextLine ? style.lineGap : 0) + 58 + controlsHeight)
    }
    var preferredHeight: CGFloat { height(fittingWidth: bounds.width > 0 ? bounds.width : preferredWidth) }
    var preferredPreviewHeight: CGFloat { preferredHeight + 24 }

    func updatePlayback(playing: Bool, enabled: Bool) {
        controls.update(playing: playing, enabled: enabled, color: NSColor(hex: style.primaryColor))
    }

    private func updateText(_ label: NSTextField, text: String) {
        let primary = label === current
        let size = primary ? style.primarySize : style.secondarySize
        let color = NSColor(hex: primary ? style.primaryColor : style.secondaryColor) ?? .white
        label.font = style.englishFont.font(size: size, bold: primary && style.bold)
        label.textColor = color
        label.attributedStringValue = LyricsTypography.attributedText(text, style: style, size: size, bold: primary && style.bold, color: color)
        measuredWidth = -1
        textViewport.resetPosition()
    }
    func show(current text: String, next upcoming: String, detail info: String) {
        let changed = current.stringValue != text || next.stringValue != upcoming
        if current.stringValue != text { updateText(current, text: text) }
        if next.stringValue != upcoming { updateText(next, text: upcoming) }
        if detail.stringValue != info { detail.stringValue = info }
        if changed { needsLayout = true; onPreferredHeightChange?() }
    }

    func apply(_ value: LyricsAppearance) {
        style = value.normalized()
        pet.setEnabled(style.petEnabled)
        next.isHidden = !style.presentation.showNextLine
        layer?.cornerRadius = style.cornerRadius
        effect.isHidden = style.background != .frosted
        effect.alphaValue = style.opacity
        effect.appearance = style.glassTheme == 0 ? nil : NSAppearance(named: style.glassTheme == 1 ? .darkAqua : .aqua)
        let color = NSColor(hex: style.backgroundColor) ?? .black
        tint.layer?.backgroundColor = color.withAlphaComponent(style.background == .transparent ? 0 : style.opacity * (style.background == .frosted ? 0.28 : 1)).cgColor
        for label in [current, next] {
            updateText(label, text: label.stringValue)
            label.wantsLayer = true
            label.layer?.shadowColor = NSColor.black.cgColor
            label.layer?.shadowOpacity = style.shadow ? 0.8 : 0
            label.layer?.shadowRadius = 4
            label.layer?.shadowOffset = CGSize(width: 0, height: -1)
            label.layer?.masksToBounds = false
        }
        detail.textColor = NSColor(hex: style.primaryColor)?.withAlphaComponent(0.75)
        setHovered(hovered)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        effect.frame = bounds
        tint.frame = bounds
        hoverTint.frame = bounds
        let (firstHeight, nextHeight) = textHeights(width: bounds.width)
        let gap = style.presentation.showNextLine ? style.lineGap : 0
        let total = firstHeight + nextHeight + gap
        textViewport.frame = NSRect(x: 0, y: controlsHeight + 12, width: bounds.width, height: max(0, bounds.height - controlsHeight - 48))
        textViewport.fitDocument(height: total)
        let bottom = max(0, (textViewport.textDocument.bounds.height - total) / 2)
        let petSize: CGFloat = 100
        let reserved = style.petEnabled ? petSize + 10 : 0
        pet.frame = NSRect(x: style.padding - 4, y: (bounds.height - petSize) / 2 - 2, width: petSize, height: petSize)
        let width = max(0, bounds.width - style.padding * 2 - reserved)
        current.frame = NSRect(x: style.padding + reserved, y: bottom + nextHeight + gap, width: width, height: firstHeight)
        next.frame = NSRect(x: style.padding + reserved, y: bottom, width: width, height: nextHeight)
        detail.frame = NSRect(x: 18, y: bounds.height - 26, width: max(0, bounds.width - 36), height: 18)
        controls.frame = NSRect(x: (bounds.width - 144) / 2, y: 6, width: 144, height: 32)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func setHovered(_ value: Bool) {
        hovered = value
        detail.isHidden = !value || detail.stringValue.isEmpty
        controls.isHidden = !value || !style.presentation.showControls
        hoverTint.layer?.backgroundColor = NSColor.black.withAlphaComponent(value && style.background == .transparent ? 0.25 : 0).cgColor
    }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event, self) }
}
