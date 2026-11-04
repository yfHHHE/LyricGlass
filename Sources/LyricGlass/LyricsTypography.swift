import AppKit

enum LyricsTypography {
    static func attributedText(_ text: String, style: LyricsAppearance, size: CGFloat, bold: Bool, color: NSColor) -> NSAttributedString {
        let english = style.englishFont.font(size: size, bold: bold)
        let chinese = style.chineseFont.font(size: size, bold: bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
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
}
