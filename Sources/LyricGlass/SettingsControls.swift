import AppKit

// Shared app-local palette and AppKit controls for settings.
enum SettingsPalette {
    private static func color(_ light: String, _ dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)!
        }
    }
    static let canvas = color("FFFCFD", "211B20")
    static let sidebar = color("FBF6F8", "271F25")
    static let surface = color("FFFFFF", "2B232A")
    static let control = color("FFFFFF", "332831")
    static let soft = color("FFF8FB", "352730")
    static let highlight = color("FFF2F6", "4B2C3B")
    static let outline = color("EEDDE5", "59414F")
    static let separator = color("F1E7EC", "42333D")
    static let accent = color("9A4967", "F1B5CC")
    static let text = color("3B2B34", "F5E8EF")
    static let secondary = color("826A78", "C2A9B6")
    static let muted = color("B29CA7", "967C8B")

    static func panel(_ rect: NSRect, fill: NSColor, stroke: NSColor? = nil, radius: CGFloat = 10, lineWidth: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let stroke { stroke.setStroke(); path.lineWidth = lineWidth; path.stroke() }
    }
    static func text(_ value: String, in rect: NSRect, color: NSColor, size: CGFloat = 13,
                     weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
        let height = ceil(string.size().height)
        string.draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
    }
}

final class SettingsSurfaceView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { SettingsPalette.canvas.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
final class SettingsSidebarSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { SettingsPalette.sidebar.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
final class SettingsGroupView: NSView {
    override func draw(_ dirtyRect: NSRect) { SettingsPalette.panel(bounds, fill: SettingsPalette.surface, stroke: SettingsPalette.separator, radius: 12) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
final class SettingsDivider: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) {
        SettingsPalette.separator.setFill()
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        NSRect(x: 0, y: 0, width: bounds.width > bounds.height ? bounds.width : pixel,
               height: bounds.width > bounds.height ? pixel : bounds.height).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

enum SettingsNativeControls {
    static func button(_ button: NSButton) {
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13)
        button.bezelColor = nil
        button.contentTintColor = nil
        button.bezelStyle = .rounded
        // Older Xcode SDKs lack these declarations even inside a runtime check.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if button is NSPopUpButton { button.bezelStyle = .glass }
            button.borderShape = .capsule
        }
        #endif
    }
    static func segments(_ control: NSSegmentedControl) {
        control.controlSize = .regular
        control.font = .systemFont(ofSize: 13)
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { control.borderShape = .capsule }
        #endif
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) { control.role = .valueSelection }
        #endif
    }
}

final class SettingsSidebarButton: NSButton {
    private var selected = false
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    func setSelected(_ value: Bool) { selected = value; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if selected || hovered || isHighlighted {
            SettingsPalette.panel(bounds, fill: selected || isHighlighted ? SettingsPalette.highlight : SettingsPalette.soft,
                                  stroke: selected ? SettingsPalette.outline : nil, radius: 10)
        }
        if window?.firstResponder === self {
            SettingsPalette.panel(bounds, fill: .clear, stroke: SettingsPalette.accent, radius: 10, lineWidth: 1.5)
        }
        let color = selected ? SettingsPalette.accent : SettingsPalette.secondary
        let iconRect = NSRect(x: 13, y: bounds.midY - 9, width: 18, height: 18)
        if let icon = image?.withSymbolConfiguration(.init(paletteColors: [color])) {
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        SettingsPalette.text(title, in: NSRect(x: 42, y: 0, width: max(0, bounds.width - 52), height: bounds.height),
                             color: selected ? SettingsPalette.text : SettingsPalette.secondary, size: 13, weight: selected ? .medium : .regular)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

