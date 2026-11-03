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

    public init(directory: URL) { self.directory = directory }

    public func load(song: Song, now: Date = Date()) -> LyricsRecord? {
        guard let url = try? file(for: song), let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= 512_000,
              let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.schema == 1, entry.song == song,
              entry.savedAt <= now.addingTimeInterval(60), now.timeIntervalSince(entry.savedAt) < lifetime,
              LyricsProvider.matches(entry.record, song: song), entry.record.hasSyncedLyrics else { return nil }
        var record = entry.record
        record.cached = true
        return record
    }

    public func store(_ record: LyricsRecord, song: Song, now: Date = Date()) throws {
        guard record.hasSyncedLyrics, LyricsProvider.matches(record, song: song) else { return }
        let encoder = JSONEncoder()
        let data = try encoder.encode(Entry(schema: 1, song: song, record: record, savedAt: now))
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

    private func file(for song: Song) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = SHA256.hash(data: try encoder.encode(song)).map { String(format: "%02x", $0) }.joined()
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
