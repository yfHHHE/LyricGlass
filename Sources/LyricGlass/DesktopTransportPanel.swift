import AppKit

private final class TransportSurface: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class DesktopTransportPanel: NSPanel {
    private let surface = TransportSurface()
    var onHover: ((Bool) -> Void)? { didSet { surface.onHover = onHover } }
    init(controls: PlaybackControls) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 168, height: 36),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "LyricGlass · 播放控制"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        surface.frame = NSRect(origin: .zero, size: frame.size)
        surface.wantsLayer = true; surface.layer?.cornerRadius = 10; surface.layer?.masksToBounds = true
        let effect = NSVisualEffectView(frame: surface.bounds)
        effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.autoresizingMask = [.width, .height]
        surface.addSubview(effect)
        controls.frame = NSRect(x: 12, y: 2, width: 144, height: 32)
        surface.addSubview(controls); contentView = surface
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func position(near parent: NSWindow) {
        guard let visible = (parent.screen ?? NSScreen.screens.first)?.visibleFrame else { return }
        let below = parent.frame.minY - frame.height - 3
        let y = below >= visible.minY ? below : min(visible.maxY - frame.height, parent.frame.maxY + 3)
        let x = min(visible.maxX - frame.width, max(visible.minX, parent.frame.midX - frame.width / 2))
        setFrameOrigin(NSPoint(x: x, y: y)); level = parent.level
    }
}
