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
        frame.size.height = lyricsView.preferredHeight
        if let visible {
            frame.origin.x = min(visible.maxX - frame.width, max(visible.minX, frame.minX))
            frame.origin.y = min(visible.maxY - frame.height, max(visible.minY, frame.minY))
        }
        setFrame(frame, display: true)
        level = style.alwaysOnTop ? .floating : .normal
        ignoresMouseEvents = style.clickThrough
        if style.clickThrough { lyricsView.setHovered(false) }
    }

    func centerAtBottom() {
        // Keep reopened lyrics discoverable on multi-monitor Macs.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(lyricsView.preferredWidth, visible.width - 40)
        setFrame(NSRect(x: visible.midX - width / 2, y: visible.minY + 44,
                        width: width, height: lyricsView.preferredHeight), display: true)
    }
}

// The settings preview and the real lyrics window use this same renderer.
final class LyricsView: NSView {
    let current = NSTextField(labelWithString: "正在连接播放器…")
    let next = NSTextField(labelWithString: "桌面透明双行歌词")
    let effect = NSVisualEffectView()
    let pet = RaindropPetView(frame: .zero)
    let controls = PlaybackControls()
    private let tint = NSView()
    private let hoverTint = NSView()
    private let detail = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var style = LyricsAppearance()
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
        for view in [effect, tint, hoverTint, pet, current, next, detail, controls] { addSubview(view) }
        for label in [current, next, detail] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isSelectable = false
        }
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(desktop ? "LyricGlass 桌面双行歌词" : "实时双行歌词外观预览")
        apply(style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var currentHeight: CGFloat { LyricsTypography.lineHeight(style: style, size: style.primarySize, bold: style.bold) }
    private var nextHeight: CGFloat { LyricsTypography.lineHeight(style: style, size: style.secondarySize, bold: false) }
    private var textHeight: CGFloat { currentHeight + (style.presentation.showNextLine ? nextHeight + style.lineGap : 0) }
    private var controlsHeight: CGFloat { style.presentation.showControls ? 34 : 0 }
    var preferredWidth: CGFloat { style.presentation.desktopWidth }
    var preferredHeight: CGFloat { max(style.petEnabled ? 150 : 100, textHeight + 58 + controlsHeight) }
    var preferredPreviewHeight: CGFloat { textHeight + 40 + controlsHeight }

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
    }
    func show(current text: String, next upcoming: String, detail info: String) {
        if current.stringValue != text { updateText(current, text: text) }
        if next.stringValue != upcoming { updateText(next, text: upcoming) }
        if detail.stringValue != info { detail.stringValue = info }
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
        effect.frame = bounds
        tint.frame = bounds
        hoverTint.frame = bounds
        let firstHeight = currentHeight, nextHeight = style.presentation.showNextLine ? self.nextHeight : 0
        let gap = style.presentation.showNextLine ? style.lineGap : 0
        let total = firstHeight + nextHeight + gap
        let bottom = max(8, (bounds.height - controlsHeight - total - 20) / 2) + controlsHeight
        let petSize = min(100, max(64, bounds.height - 36))
        let reserved = style.petEnabled ? petSize + 10 : 0
        pet.frame = NSRect(x: style.padding - 4, y: (bounds.height - petSize) / 2 - 2, width: petSize, height: petSize)
        let width = max(0, bounds.width - style.padding * 2 - reserved)
        current.frame = NSRect(x: style.padding + reserved, y: bottom + nextHeight + gap, width: width, height: firstHeight)
        next.frame = NSRect(x: style.padding + reserved, y: bottom, width: width, height: nextHeight)
        detail.frame = NSRect(x: 18, y: current.frame.maxY + 8, width: max(0, bounds.width - 36), height: 18)
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
