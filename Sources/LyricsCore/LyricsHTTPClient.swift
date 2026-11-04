import Foundation

public actor LyricsHTTPClient {
    public typealias Sender = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public typealias Sleeper = @Sendable (Double) async throws -> Void
    private let sender: Sender
    private let sleeper: Sleeper
    private var cooldowns: [String: (until: Date, status: Int)] = [:]

    public init(sender: Sender? = nil, sleep: @escaping Sleeper = { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }) {
        if let sender { self.sender = sender }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 7
            config.timeoutIntervalForResource = 10
            config.httpMaximumConnectionsPerHost = 1
            // This isolated session only retains the providers' anonymous guest cookies in memory.
            config.httpShouldSetCookies = true
            config.httpCookieAcceptPolicy = .always
            let session = URLSession(configuration: config)
            self.sender = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                return (data, response)
            }
        }
        self.sleeper = sleep
    }

    public func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        var request = request
        guard let host = request.url?.host, request.url?.scheme == "https" else { throw URLError(.badURL) }
        if let cooldown = cooldowns[host], cooldown.until > Date() { throw LyricsLookupError.http(cooldown.status) }
        request.timeoutInterval = 7
        request.setValue("LyricGlass/0.5.1 (https://github.com/yfHHHE/LyricGlass)", forHTTPHeaderField: "User-Agent")
        for attempt in 0...1 {
            try Task.checkCancellation()
            let data: Data, response: HTTPURLResponse
            do { (data, response) = try await sender(request) }
            catch {
                try Task.checkCancellation()
                if let error = error as? URLError,
                   [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code), attempt == 0 {
                    try await sleeper(0.6 + Double.random(in: 0...0.15))
                    continue
                }
                throw error
            }
            try Task.checkCancellation()
            if response.statusCode == 200 {
                cooldowns.removeValue(forKey: host)
                guard data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
                return data
            }
            guard [429, 500, 503].contains(response.statusCode) else { throw LyricsLookupError.http(response.statusCode) }
            let delay = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After")) ?? 0.6
            cooldowns[host] = (Date().addingTimeInterval(max(delay, 1)), response.statusCode)
            // Respect long server cooldowns by trying another provider rather than retrying too soon.
            guard attempt == 0, delay <= 2 else { throw LyricsLookupError.http(response.statusCode) }
            try await sleeper(delay + Double.random(in: 0...0.15))
        }
        throw URLError(.badServerResponse)
    }

    private static func retryDelay(_ header: String?) -> Double? {
        guard let header else { return nil }
        if let seconds = Double(header), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: header).map { max(0, $0.timeIntervalSinceNow) }
    }
}
