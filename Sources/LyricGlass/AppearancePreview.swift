import AppKit

final class WallpaperView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(hex: "59414F")!, NSColor(hex: "30232D")!])!.draw(in: bounds, angle: 24)
        NSColor(hex: "FFF2F6")!.withAlphaComponent(0.04).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width * 0.6, y: -bounds.height * 0.5, width: bounds.width * 0.7, height: bounds.height * 1.5)).fill()
        NSColor(hex: "B46F8A")!.withAlphaComponent(0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: -60, y: -bounds.height * 0.8, width: bounds.width * 0.75, height: bounds.height * 1.4)).fill()
    }
}

final class PreviewScene: NSView {
    let lyrics = LyricsView(frame: .zero, desktop: false)
    private let wallpaper = WallpaperView()
    var onPreferredHeightChange: (() -> Void)?
    var preferredHeight: CGFloat { min(400, lyrics.height(fittingWidth: max(1, bounds.width - 36)) + 24) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        addSubview(wallpaper)
        addSubview(lyrics)
        lyrics.onPreferredHeightChange = { [weak self] in self?.onPreferredHeightChange?() }
        setLanguage(0)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setLanguage(_ index: Int) {
        lyrics.show(current: index == 0 ? "让旋律 stay with me" : index == 1 ? "让旋律停在窗边" : "Let the melody stay",
                    next: index == 0 ? "让时间慢一点 · Stay awhile" : index == 1 ? "让文字跟着时间" : "The words follow time", detail: "")
    }
    override func layout() {
        super.layout()
        wallpaper.frame = bounds
        lyrics.frame = bounds.insetBy(dx: 18, dy: 12)
        onPreferredHeightChange?()
    }
}

