import AppKit

final class LyricsPanel: NSPanel {
    let lyricsView = LyricsView(frame: NSRect(x: 0, y: 0, width: 940, height: 150))

    init() {
        super.init(contentRect: lyricsView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "LyricGlass · 桌面歌词"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = lyricsView
        centerAtBottom()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func centerAtBottom() {
        // Use the primary display so a reopened overlay is easy to find on multi-monitor Macs.
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let width = min(940, visible.width - 40)
        setFrame(NSRect(x: visible.midX - width / 2, y: visible.minY + 44, width: width, height: 150), display: true)
    }
}

final class LyricsView: NSView {
    private let current = NSTextField(labelWithString: "正在连接 Spotify…")
    private let next = NSTextField(labelWithString: "桌面透明双行歌词")
    private let detail = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var hovered = false
    var fontSize: CGFloat = 30 { didSet { refreshText() } }
    private var currentText = "正在连接 Spotify…"
    private var nextText = "桌面透明双行歌词"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 22
        for label in [current, next, detail] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.textColor = .white.withAlphaComponent(0.75)
        detail.isHidden = true
        NSLayoutConstraint.activate([
            current.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            current.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            current.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            next.leadingAnchor.constraint(equalTo: current.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: current.trailingAnchor),
            next.topAnchor.constraint(equalTo: current.bottomAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            detail.bottomAnchor.constraint(equalTo: current.topAnchor, constant: -12)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("LyricGlass 桌面双行歌词")
        refreshText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(current text: String, next upcoming: String, detail info: String) {
        if text != currentText || upcoming != nextText {
            currentText = text; nextText = upcoming
            refreshText()
        }
        if detail.stringValue != info { detail.stringValue = info }
    }

    private func refreshText() {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        for (label, text, size, weight, alpha) in [
            (current, currentText, fontSize, NSFont.Weight.semibold, 1.0),
            (next, nextText, max(18, fontSize * 0.73), NSFont.Weight.medium, 0.66)
        ] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            label.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                .shadow: shadow, .paragraphStyle: paragraph
            ])
        }
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
        detail.isHidden = !value
        layer?.backgroundColor = value ? NSColor.black.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = (NSApplication.shared.delegate as? AppDelegate)?.menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
