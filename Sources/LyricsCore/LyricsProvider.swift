import Foundation

public actor LyricsProvider {
    private let http: LyricsHTTPClient
    private let cache: LyricsDiskCache?
    private let sources: [LyricsSource]
    private let sourceTimeout: TimeInterval
    private var netEasePrepared = false
    private var cooldowns: [LyricsSource: (until: Date, error: Error)] = [:]
    public init(http: LyricsHTTPClient = LyricsHTTPClient(), cacheDirectory: URL? = nil,
                sources: [LyricsSource] = LyricsSource.allCases, sourceTimeout: TimeInterval = 4) {
        precondition(sourceTimeout.isFinite && sourceTimeout > 0 && sourceTimeout <= 60)
        self.http = http; self.sources = sources; self.sourceTimeout = sourceTimeout
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
        guard song.duration.isFinite, song.duration > 0, song.duration < Double(Int.max - 4) else { throw LyricsLookupError.notFound }
        try Task.checkCancellation()
        let stored = cache?.load(song: song)
        let cached = stored.flatMap { sources.contains($0.sourceKind) ? $0 : nil }
        if !forceReload, let cached { return cached }
        // On an explicit refresh, try the previously verified source first as well.
        let ordered = cached.map { previous in
            [previous.sourceKind] + sources.filter { $0 != previous.sourceKind }
        } ?? sources
        var plain: LyricsRecord?
        var failure: Error?
        let available = ordered.filter { source in
            if !forceReload, let cooldown = cooldowns[source], cooldown.until > Date() {
                failure = cooldown.error
                return false
            }
            return true
        }
        let result = try await withThrowingTaskGroup(of: SourceResult.self, returning: LyricsRecord.self) { group in
            var pending = available.makeIterator()
            // Parallelize independent hosts, while keeping traffic bounded to two sources.
            for _ in 0..<2 {
                if let source = pending.next() {
                    group.addTask { try await self.lookup(source: source, song: song) }
                }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                switch result.result {
                case .success(let records):
                    cooldowns.removeValue(forKey: result.source)
                    let valid = records.filter { Self.matches($0, song: song) }.sorted {
                        (SongMatcher.score($0, song: song) ?? 0) > (SongMatcher.score($1, song: song) ?? 0)
                    }
                    if let record = valid.first(where: \.hasSyncedLyrics) {
                        group.cancelAll()
                        return record
                    }
                    if plain == nil { plain = valid.first { $0.plainLyrics?.isEmpty == false || $0.instrumental } }
                case .failure(let error):
                    if case LyricsLookupError.http(404) = error { break }
                    failure = error
                    // Business errors such as NetEase -462 otherwise repeat on every track.
                    // Host-level Retry-After remains enforced independently by the HTTP client.
                    cooldowns[result.source] = (Date().addingTimeInterval(20), error)
                }
                if let source = pending.next() {
                    group.addTask { try await self.lookup(source: source, song: song) }
                }
            }
            if let cached { return cached }
            if let plain { return plain }
            if let failure { throw failure }
            throw LyricsLookupError.notFound
        }
        try Task.checkCancellation()
        if !result.cached { try? cache?.store(result, song: song) }
        return result
    }

    private struct SourceResult: Sendable {
        let source: LyricsSource
        let result: Result<[LyricsRecord], Error>
    }

    private func lookup(source: LyricsSource, song: Song) async throws -> SourceResult {
        do {
            let records = try await withThrowingTaskGroup(of: [LyricsRecord].self) { group in
                group.addTask { try await self.records(source: source, song: song) }
                let timeout = sourceTimeout
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            return SourceResult(source: source, result: .success(records))
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            try Task.checkCancellation()
            return SourceResult(source: source, result: .failure(error))
        }
    }

    private func records(source: LyricsSource, song: Song) async throws -> [LyricsRecord] {
        let remote = RemoteLyrics(http: http)
        switch source {
        case .lrclib: return try await remote.lrclib(song)
        case .netease:
            if !netEasePrepared { try await remote.prepareNetEase(); netEasePrepared = true }
            return try await remote.netease(song)
        case .qq: return try await remote.qq(song)
        case .kugou: return try await remote.kugou(song)
        case .lrcmux: return try await remote.lrcmux(song)
        }
    }

    public func clearCache() throws { try cache?.clear() }
}
