import AppKit
import CoreText

// Keep NSTextField's text/accessibility API, but trim unused font ascender/descender
// space using the glyphs actually present in each wrapped line.
final class LyricsTextField: NSTextField {
    private struct Line {
        let text: CTLine
        let x: CGFloat
        let top: CGFloat
        let ink: CGRect
    }
    private var cachedWidth: CGFloat = -1
    private var cachedText: NSAttributedString?
    private var lines: [Line] = []
    private var measuredHeight: CGFloat = 1
    private(set) var laidOutUTF16Count = 0
    override var isFlipped: Bool { true }

    init(_ text: String) {
        super.init(frame: .zero)
        isEditable = false; isSelectable = false; isBordered = false; drawsBackground = false
        stringValue = text
        LyricsTypography.configureWrapping(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func height(fittingWidth width: CGFloat) -> CGFloat {
        prepare(width: width)
        return measuredHeight
    }
    private func prepare(width: CGFloat) {
        let width = max(1, width)
        let value = attributedStringValue
        if width == cachedWidth, cachedText?.isEqual(to: value) == true { return }
        cachedWidth = width; cachedText = NSAttributedString(attributedString: value)
        lines = []; laidOutUTF16Count = 0
        guard value.length > 0 else { measuredHeight = 1; return }
        let rendering = NSMutableAttributedString(attributedString: value)
        rendering.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rendering.length)) { color, range, _ in
            if let color = color as? NSColor { rendering.addAttribute(.foregroundColor, value: color.cgColor, range: range) }
        }
        let setter = CTFramesetterCreateWithAttributedString(rendering)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: max(1, ceil(suggested.height) + 100)), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let shaped = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: shaped.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        laidOutUTF16Count = CTFrameGetVisibleStringRange(frame).length
        // Hinting/antialiasing can extend beyond vector bounds, especially accents.
        var top: CGFloat = 2
        for (index, line) in shaped.enumerated() {
            var ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            if ink.isNull || ink.isEmpty { ink = CGRect(x: 0, y: 0, width: 0, height: max(1, (font?.pointSize ?? 16) * 0.5)) }
            lines.append(Line(text: line, x: origins[index].x, top: top, ink: ink))
            top += ceil(ink.height) + 2
        }
        measuredHeight = max(1, ceil(top - 1))
    }
    override func draw(_ dirtyRect: NSRect) {
        prepare(width: bounds.width)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for line in lines {
            context.textPosition = CGPoint(x: line.x, y: bounds.height - line.top - line.ink.maxY)
            CTLineDraw(line.text, context)
        }
        context.restoreGState()
    }
}
