import Foundation

public actor LyricsProvider {
    private let http: LyricsHTTPClient
    private let cache: LyricsDiskCache?
    private let sources: [LyricsSource]
    private var netEasePrepared = false
    public init(http: LyricsHTTPClient = LyricsHTTPClient(), cacheDirectory: URL? = nil,
                sources: [LyricsSource] = LyricsSource.allCases) {
        self.http = http; self.sources = sources
        let directory = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LyricGlass/Lyrics", isDirectory: true)
        self.cache = directory.map(LyricsDiskCache.init)
    }

    public static func normalized(_ text: String) -> String {
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    public static func matches(_ record: LyricsRecord, song: Song) -> Bool {
        SongMatcher.score(record, song: song) != nil
    }

    public func fetch(song: Song, forceReload: Bool = false) async throws -> LyricsRecord {
        guard song.duration.isFinite, song.duration > 0 else { throw LyricsLookupError.notFound }
        try Task.checkCancellation()
        let stored = cache?.load(song: song)
        let cached = stored.flatMap { sources.contains($0.sourceKind) ? $0 : nil }
        if !forceReload, let cached { return cached }
        let remote = RemoteLyrics(http: http)
        var plain: LyricsRecord?
        var failure: Error?
        for source in sources {
            try Task.checkCancellation()
            do {
                let records: [LyricsRecord]
                switch source {
                case .lrclib: records = try await remote.lrclib(song)
                case .netease:
                    if !netEasePrepared { try await remote.prepareNetEase(); netEasePrepared = true }
                    records = try await remote.netease(song)
                case .qq: records = try await remote.qq(song)
                }
                let valid = records.filter { Self.matches($0, song: song) }.sorted {
                    (SongMatcher.score($0, song: song) ?? 0) > (SongMatcher.score($1, song: song) ?? 0)
                }
                if let record = valid.first(where: \.hasSyncedLyrics) {
                    try Task.checkCancellation()
                    try? cache?.store(record, song: song)
                    return record
                }
                if plain == nil { plain = valid.first { $0.plainLyrics?.isEmpty == false || $0.instrumental } }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                try Task.checkCancellation()
                if case LyricsLookupError.http(404) = error { continue }
                failure = error
            }
        }
        if let cached { return cached }
        if let plain { return plain }
        if let failure { throw failure }
        throw LyricsLookupError.notFound
    }

    public func clearCache() throws { try cache?.clear() }
}
