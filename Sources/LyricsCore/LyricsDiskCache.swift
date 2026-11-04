import Foundation
import CryptoKit

public struct LyricsDiskCache: Sendable {
    private let directory: URL
    private let lifetime: TimeInterval = 30 * 24 * 60 * 60
    private struct Entry: Codable {
        let schema: Int
        let song: Song
        let record: LyricsRecord
        let savedAt: Date
    }
    private struct RecordingKey: Codable, Equatable {
        let title: String
        let artists: [String]
        let album: String
        let seconds: Int
    }

    public init(directory: URL) { self.directory = directory }

    public func load(song: Song, now: Date = Date()) -> LyricsRecord? {
        guard song.duration.isFinite, song.duration > 0, song.duration < Double(Int.max - 4) else { return nil }
        // Adjacent second buckets tolerate small metadata precision changes without
        // including a player's transient ID in the recording identity.
        let candidates = [0, -1, 1, -2, 2].compactMap { try? file(for: song, secondsOffset: $0) }
        for url in candidates {
            if let record = read(url, song: song, now: now, legacyOnly: false) { return record }
        }
        // v0.4 hashes the entire Song including the player ID. Read those entries
        // without deleting them or extending their original 30-day expiry.
        for url in ((try? managedFiles()) ?? []).prefix(200) where !candidates.contains(url) {
            if let record = read(url, song: song, now: now, legacyOnly: true) { return record }
        }
        return nil
    }

    private func read(_ url: URL, song: Song, now: Date, legacyOnly: Bool) -> LyricsRecord? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512_000,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= 512_000,
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.schema == 1 || (!legacyOnly && entry.schema == 2),
              entry.song.duration.isFinite, abs(entry.song.duration - song.duration) <= 2,
              SongMatcher.titleKey(entry.song.title) == SongMatcher.titleKey(song.title),
              ArtistNames.parts(entry.song.artist).sorted() == ArtistNames.parts(song.artist).sorted(),
              LyricsProvider.normalized(entry.song.album) == LyricsProvider.normalized(song.album),
              entry.savedAt <= now.addingTimeInterval(60), now.timeIntervalSince(entry.savedAt) < lifetime,
              LyricsProvider.matches(entry.record, song: entry.song), LyricsProvider.matches(entry.record, song: song),
              entry.record.hasSyncedLyrics else { return nil }
        var record = entry.record
        record.cached = true
        return record
    }

    public func store(_ record: LyricsRecord, song: Song, now: Date = Date()) throws {
        guard song.duration < Double(Int.max - 4), record.hasSyncedLyrics, LyricsProvider.matches(record, song: song) else { return }
        let encoder = JSONEncoder()
        let data = try encoder.encode(Entry(schema: 2, song: song, record: record, savedAt: now))
        guard data.count <= 512_000 else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = try file(for: song)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let files = try managedFiles().sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for old in files.dropFirst(200) { try? FileManager.default.removeItem(at: old) }
    }

    public func clear() throws {
        for file in try managedFiles() { try FileManager.default.removeItem(at: file) }
    }

    private func file(for song: Song, secondsOffset: Int = 0) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let recording = RecordingKey(title: SongMatcher.titleKey(song.title), artists: ArtistNames.parts(song.artist).sorted(),
                                     album: LyricsProvider.normalized(song.album), seconds: Int(song.duration.rounded()) + secondsOffset)
        let key = SHA256.hash(data: try encoder.encode(recording)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }

    private func managedFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { url in
                let key = url.deletingPathExtension().lastPathComponent
                return url.pathExtension == "json" && key.count == 64 && key.allSatisfy { "0123456789abcdef".contains($0) }
            }
    }
}
