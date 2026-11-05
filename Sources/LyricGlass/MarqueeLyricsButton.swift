import AppKit
import QuartzCore

/// A native button whose full accessible title scrolls inside a clipped lyric window.
final class MarqueeLyricsButton: NSButton {
    private let movingText = CALayer()
    private let textLayers = [CATextLayer(), CATextLayer()]
    private let edgeFade = CAGradientLayer()
    private var signature = ""
    private var motionObserver: NSObjectProtocol?
    private(set) var isScrolling = false
    var animationEnabled = true {
        didSet {
            if oldValue != animationEnabled {
                if !animationEnabled { movingText.removeAllAnimations(); isScrolling = false }
                signature = ""; needsLayout = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(movingText)
        for text in textLayers { movingText.addSublayer(text) }
        edgeFade.startPoint = CGPoint(x: 0, y: 0.5); edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.signature = ""; self?.needsLayout = true }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }

    // Text is rendered by Core Animation; the native button keeps hit testing and AX actions.
    override func draw(_ dirtyRect: NSRect) {}

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let next = "\(attributedTitle.hash)-\(bounds.size)-\(scale)-\(animationEnabled)-\(reducedMotion)"
        guard signature != next else { return }
        signature = next
        let textSize = attributedTitle.size()
        let width = ceil(textSize.width), height = ceil(textSize.height + 2)
        let textInset: CGFloat = 6
        let distance = width + 30
        isScrolling = width > bounds.width - textInset * 2 && bounds.width > textInset * 2 && animationEnabled && !reducedMotion
        CATransaction.begin(); CATransaction.setDisableActions(true)
        movingText.removeAllAnimations()
        movingText.frame = bounds
        edgeFade.frame = bounds
        // A complete lyric must remain fully opaque. Padding keeps the first glyph
        // outside the fading edge when a longer line begins its scrolling cycle.
        layer?.mask = isScrolling ? edgeFade : nil
        let fade = min(0.12, 5 / max(1, bounds.width))
        edgeFade.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        for (index, text) in textLayers.enumerated() {
            text.contentsScale = scale
            text.string = attributedTitle
            text.alignmentMode = .left; text.isWrapped = false; text.truncationMode = .none
            text.frame = CGRect(x: textInset + CGFloat(index) * distance, y: floor((bounds.height - height) / 2), width: max(1, width), height: height)
            text.isHidden = index == 1 && !isScrolling
        }
        CATransaction.commit()
        if isScrolling {
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = 0; animation.toValue = -distance
            animation.duration = Double(distance / 28)
            animation.beginTime = CACurrentMediaTime() + 0.6
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.repeatCount = .infinity
            movingText.add(animation, forKey: "lyric-scroll")
        }
    }
}
