import AppKit

enum LyricsTypography {
    static func attributedText(_ text: String, style: LyricsAppearance, size: CGFloat, bold: Bool, color: NSColor) -> NSAttributedString {
        let english = style.englishFont.font(size: size, bold: bold)
        let chinese = style.chineseFont.font(size: size, bold: bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString(string: text, attributes: [.font: english, .foregroundColor: color, .paragraphStyle: paragraph])
        var offset = 0
        var chineseStart: Int?
        // Iterate grapheme clusters so emoji, surrogate pairs and variation selectors stay intact.
        for character in text {
            let length = String(character).utf16.count
            let isChinese = character.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x2E80...0x2FFF, 0x3000...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                     0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE10...0xFE1F, 0xFE30...0xFE4F,
                     0xFF00...0xFFEF, 0x20000...0x323AF: return true
                default: return false
                }
            }
            if isChinese {
                if chineseStart == nil { chineseStart = offset }
            } else if let start = chineseStart {
                result.addAttribute(.font, value: chinese, range: NSRange(location: start, length: offset - start))
                chineseStart = nil
            }
            offset += length
        }
        if let start = chineseStart {
            result.addAttribute(.font, value: chinese, range: NSRange(location: start, length: offset - start))
        }
        return result
    }

    static func lineHeight(style: LyricsAppearance, size: CGFloat, bold: Bool) -> CGFloat {
        let fonts = [style.chineseFont.font(size: size, bold: bold), style.englishFont.font(size: size, bold: bold)]
        let ascender = fonts.map(\.ascender).max() ?? size
        let descender = fonts.map { -$0.descender }.max() ?? 0
        let leading = fonts.map(\.leading).max() ?? 0
        return ceil(max(size * 1.45, ascender + descender + leading + 6))
    }

    static func configureWrapping(_ label: NSTextField) {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.allowsDefaultTighteningForTruncation = false
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        (label.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = false
    }

    static func wrappedHeight(_ label: NSTextField, width: CGFloat, minimum: CGFloat) -> CGFloat {
        if let label = label as? LyricsTextField { return label.height(fittingWidth: width) }
        let bounds = NSRect(x: 0, y: 0, width: max(1, width), height: .greatestFiniteMagnitude)
        // Measure the actual field cell, including its insets and mixed-font glyphs.
        return max(minimum, ceil(label.cell?.cellSize(forBounds: bounds).height ?? minimum) + 4)
    }
}

// Keep unusually long lyric paragraphs on screen without shrinking or discarding text.
final class LyricsTextViewport: NSScrollView {
    let textDocument = NSView()
    private var resetToTop = true

    init() {
        super.init(frame: .zero)
        drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; hasHorizontalScroller = false
        autohidesScrollers = true; scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        contentView.drawsBackground = false
        documentView = textDocument
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resetPosition() { resetToTop = true }
    func fitDocument(height: CGFloat) {
        let size = NSSize(width: contentSize.width, height: max(contentSize.height, height))
        if textDocument.frame.size != size { textDocument.setFrameSize(size) }
        if resetToTop {
            contentView.scroll(to: NSPoint(x: 0, y: max(0, size.height - contentSize.height)))
            reflectScrolledClipView(contentView)
            resetToTop = false
        }
    }
}
