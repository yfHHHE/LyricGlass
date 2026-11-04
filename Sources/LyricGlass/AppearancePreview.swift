import AppKit

enum PreviewLyrics {
    static let english = [
        "Every time I lost my mind",
        "Every time 我告訴我自己",
        "I will be okay"
    ]
    static let chinese = [
        "人群的溫暖輕撫我讓寂寞更熱烈",
        "無知的黑洞撐開虛空快把我撕裂"
    ]
    static func pair(language: Int) -> (current: String, next: String) {
        switch language {
        case 1: return (chinese[0], chinese[1])
        case 2: return (english[0], english[2])
        default: return (english[0], english[1])
        }
    }
    static var lrc: String {
        zip(["00:00.00", "00:08.00", "00:16.00", "00:24.00", "00:32.00"], english + chinese)
            .map { "[\($0.0)]\($0.1)" }.joined(separator: "\n") + "\n[00:39.00]"
    }
}

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
        let pair = PreviewLyrics.pair(language: index)
        lyrics.show(current: pair.current, next: pair.next, detail: "")
    }
    override func layout() {
        super.layout()
        wallpaper.frame = bounds
        lyrics.frame = bounds.insetBy(dx: 18, dy: 12)
        onPreferredHeightChange?()
    }
}

