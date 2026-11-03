import Foundation

enum ArtistNames {
    // Small, explicit alias seed; providers can also supply their own artist aliases.
    // Unknown names are never guessed or translated by a language model.
    static let groups = [
        ["Crowd Lu", "卢广仲"], ["New Pants", "新裤子"],
        ["Eason Chan", "陈奕迅"], ["Jay Chou", "周杰伦"],
        ["Faye Wong", "王菲"], ["Sodagreen", "苏打绿"],
        ["Accusefive", "告五人"], ["No Party For Cao Dong", "草东没有派对"]
    ]

    static func canonical(_ name: String) -> String {
        let normalized = LyricsProvider.normalized(name)
        for group in groups where group.contains(where: { LyricsProvider.normalized($0) == normalized }) {
            return LyricsProvider.normalized(group[0])
        }
        return normalized
    }

    static func queryName(_ name: String) -> String {
        let key = canonical(name)
        if let known = groups.first(where: { canonical($0[0]) == key })?.last { return known }
        let variants = displayVariants(name)
        return variants.count > 1 ? variants[1] : name
    }

    static func displayVariants(_ name: String) -> [String] {
        guard name.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
              name.range(of: "[A-Za-z]", options: .regularExpression) != nil,
              name.range(of: #"[\p{Hiragana}\p{Katakana}]"#, options: .regularExpression) == nil else { return [name] }
        let chinese = name.replacingOccurrences(of: #"[^\p{Han}]+"#, with: "", options: .regularExpression)
        let latin = name.replacingOccurrences(of: #"\p{Han}+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, chinese, latin].filter { !$0.isEmpty }
    }

    static func parts(_ name: String) -> [String] {
        let separated = name.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring|x)\s+|\s*[,;&/、，；]\s*"#,
                                                  with: "\n", options: .regularExpression)
        return separated.components(separatedBy: .newlines).map(canonical).filter { !$0.isEmpty }
    }
}

public enum SongMatcher {
    public static func queryTitle(_ title: String) -> String {
        let folded = title.folding(options: .widthInsensitive, locale: nil)
        let parentheses = folded.replacingOccurrences(of: #"(?i)[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]+[\)\]]"#,
                                                       with: "", options: .regularExpression)
        // Stop at edition brackets/dashes so a trailing Live or Remix label survives.
        let features = parentheses.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring)\s+[^\(\[\-–—]+"#,
                                                        with: "", options: .regularExpression)
        return features.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func titleKey(_ title: String) -> String { LyricsProvider.normalized(queryTitle(title)) }

    public static func score(_ record: LyricsRecord, song: Song) -> Double? {
        guard song.duration.isFinite, record.duration.isFinite, song.duration > 0, record.duration > 0,
              abs(record.duration - song.duration) <= 2,
              !titleKey(song.title).isEmpty, titleKey(record.trackName) == titleKey(song.title) else { return nil }
        let album = LyricsProvider.normalized(song.album)
        let sameAlbum = !album.isEmpty && album == LyricsProvider.normalized(record.albumName ?? "")
        let expected = ArtistNames.parts(song.artist), actual = ArtistNames.parts(record.artistName)
        let wholeMatch = expected.count == actual.count && !ArtistNames.canonical(song.artist).isEmpty
            && ArtistNames.canonical(song.artist) == ArtistNames.canonical(record.artistName)
        let fullMatch = !expected.isEmpty && Set(expected) == Set(actual)
        let providerAlias = expected.count == 1 && actual.count == 1
            && (record.artistAliases ?? []).map(ArtistNames.canonical).contains(expected[0])
        let expectedNames = Set(ArtistNames.displayVariants(song.artist).map(ArtistNames.canonical))
        let actualNames = Set(ArtistNames.displayVariants(record.artistName).map(ArtistNames.canonical))
        let bilingual = expected.count == 1 && actual.count == 1 && sameAlbum
            && !expectedNames.isDisjoint(with: actualNames)
        // A catalog may omit guests, but must retain the lead, album and matching recording length.
        let leadOnly = expected.count > 1 && actual.count == 1 && expected.first == actual.first && sameAlbum
        guard wholeMatch || fullMatch || providerAlias || bilingual || leadOnly else { return nil }
        return 100 - abs(record.duration - song.duration) * 5 + (sameAlbum ? 20 : 0) + (leadOnly ? 0 : 10)
    }
}
