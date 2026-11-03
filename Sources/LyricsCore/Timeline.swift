import Foundation

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
}

public struct LyricsTimeline: Sendable {
    public let lines: [LyricLine]

    public init(lrc: String) {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let entire = NSRange(lrc.startIndex..., in: lrc)
        let offset: Double
        if let match = offsetPattern.firstMatch(in: lrc, range: entire),
           let range = Range(match.range(at: 1), in: lrc), let ms = Double(lrc[range]) {
            offset = ms / 1000
        } else { offset = 0 }
        var parsed: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = stamp.matches(in: raw, range: range)
            guard let last = matches.last, let end = Range(last.range, in: raw)?.upperBound else { continue }
            let text = raw[end...].trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: raw),
                      let secondRange = Range(match.range(at: 2), in: raw),
                      let minutes = Double(raw[minuteRange]), let seconds = Double(raw[secondRange]),
                      seconds < 60 else { continue }
                var fraction = 0.0
                if let r = Range(match.range(at: 3), in: raw) {
                    fraction = (Double(raw[r]) ?? 0) / pow(10, Double(raw[r].count))
                }
                // Positive LRC offset means the lyrics run earlier relative to the audio.
                parsed.append(.init(time: max(0, minutes * 60 + seconds + fraction - offset), text: text))
            }
        }
        // Stable ordering; combine different simultaneous lines instead of silently losing one.
        var merged: [LyricLine] = []
        var seen: Set<String> = []
        for line in parsed.enumerated().sorted(by: {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }).map(\.element) {
            if let previous = merged.last, previous.time == line.time {
                if seen.contains(line.text) || line.text.isEmpty { continue }
                seen.insert(line.text)
                merged[merged.count - 1] = .init(time: line.time, text: previous.text.isEmpty ? line.text : previous.text + " · " + line.text)
            } else { merged.append(line); seen = [line.text] }
        }
        lines = merged
    }

    public func index(at position: Double) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }

    public func pair(at position: Double) -> (current: String, next: String) {
        guard !lines.isEmpty else { return ("暂无同步歌词", "") }
        guard let i = index(at: position) else { return ("前奏 · 等待人声", lines.first(where: { !$0.text.isEmpty })?.text ?? "") }
        let current = lines[i].text.isEmpty ? "间奏 ♪" : lines[i].text
        let next = lines.dropFirst(i + 1).first(where: { !$0.text.isEmpty })?.text ?? ""
        return (current, next)
    }
}

public struct PlaybackClock: Sendable {
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false
    private var sampledAt: Double = 0

    public init() {}

    public mutating func sample(position: Double, duration: Double, playing: Bool, now: Double) {
        self.position = max(0, position)
        self.duration = max(0, duration)
        self.isPlaying = playing
        self.sampledAt = now
    }

    public func position(at now: Double) -> Double {
        // Stop extrapolating if the selected player stops answering.
        let elapsed = isPlaying ? min(2, max(0, now - sampledAt)) : 0
        return min(duration, position + elapsed)
    }
}
