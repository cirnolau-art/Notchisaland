import Foundation

struct LyricsQuery: Hashable {
    let title: String
    let artist: String
    let album: String
    let duration: Int?
    let directory: String
    let online: Bool

    init?(_ info: MediaInfo?, directory: String, online: Bool) {
        guard let info else { return nil }
        title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        artist = info.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        album = info.album.trimmingCharacters(in: .whitespacesAndNewlines)
        duration = (1...3600).contains(info.duration.rounded()) ? Int(info.duration.rounded()) : nil
        self.directory = directory
        self.online = online
    }
}

struct LyricsResult {
    let lines: [LyricLine]
    let validUntil: Date

    init(_ lines: [LyricLine], validUntil: Date? = nil) {
        self.lines = lines
        self.validUntil = validUntil ?? Date().addingTimeInterval(lines.isEmpty ? 600 : 3600)
    }
}

/// Called on the main thread by the controller. Polling the same player must not
/// start another request or replace the player's latest elapsed-time sample.
final class LyricsLookup {
    typealias Resolver = (LyricsQuery) async -> LyricsResult
    private let resolve: Resolver
    private var selected: LyricsQuery?
    private var work: Task<Void, Never>?
    private var cache: [LyricsQuery: LyricsResult] = [:]
    var onChange: (([LyricLine]) -> Void)?

    init(resolve: @escaping Resolver = LyricsLookup.resolveLyrics) { self.resolve = resolve }
    deinit { work?.cancel() }

    func select(_ query: LyricsQuery?) -> [LyricLine] {
        if query != selected {
            work?.cancel()
            work = nil
            selected = query
        }
        guard let query else { return [] }
        if let hit = cache[query], hit.validUntil > Date() { return hit.lines }
        guard work == nil else { return [] }
        work = Task { @MainActor [weak self, resolve] in
            let result = await resolve(query)
            guard !Task.isCancelled, let self, selected == query else { return }
            work = nil
            if cache.count >= 32, cache[query] == nil, let oldest = cache.min(by: { $0.value.validUntil < $1.value.validUntil }) {
                cache.removeValue(forKey: oldest.key)
            }
            cache[query] = result
            onChange?(result.lines)
        }
        return []
    }

    static func resolveLyrics(_ query: LyricsQuery) async -> LyricsResult {
        guard !Task.isCancelled else { return LyricsResult([]) }
        let local = LyricsStore.load(title: query.title, artist: query.artist, directory: query.directory)
        guard local.isEmpty, query.online, !query.artist.isEmpty, !Task.isCancelled else { return LyricsResult(local) }
        return await OnlineLyricsProvider.shared.fetch(query)
    }
}

actor OnlineLyricsProvider {
    static let shared = OnlineLyricsProvider()
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let request: Transport
    private var limitedUntil: [String: Date] = [:]
    private struct RetryLater: Error { let date: Date }

    init(request: Transport? = nil) {
        // Playback metadata should not be persisted in the system URL cache.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        self.request = request ?? { try await session.data(for: $0) }
    }

    private struct Record: Decodable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    func fetch(_ query: LyricsQuery) async -> LyricsResult {
        let identity = [URLQueryItem(name: "track_name", value: query.title), URLQueryItem(name: "artist_name", value: query.artist)]
        do {
            var exact = identity
            if !query.album.isEmpty { exact.append(URLQueryItem(name: "album_name", value: query.album)) }
            if let duration = query.duration { exact.append(URLQueryItem(name: "duration", value: String(duration))) }
            if let record: Record = try await read(host: "lrclib.net", path: "/api/get", items: exact), matches(record, query) {
                if record.instrumental == true { return LyricsResult([]) }
                let lines = LyricsParser.parse(record.syncedLyrics ?? "")
                if !lines.isEmpty { return LyricsResult(lines) }
            }
            // Album naming varies between players. Keep song, artist and known
            // duration checks, and prefer the requested album amongst matches.
            let found: [Record] = try await read(host: "lrclib.net", path: "/api/search", items: identity) ?? []
            let candidates = found.filter { matches($0, query) }.sorted { lhs, rhs in
                let lhsAlbum = folded(lhs.albumName ?? "") == folded(query.album)
                let rhsAlbum = folded(rhs.albumName ?? "") == folded(query.album)
                if lhsAlbum != rhsAlbum { return lhsAlbum }
                guard let duration = query.duration else { return false }
                return abs((lhs.duration ?? 0) - Double(duration)) < abs((rhs.duration ?? 0) - Double(duration))
            }
            for record in candidates where record.instrumental != true {
                let lines = LyricsParser.parse(record.syncedLyrics ?? "")
                if !lines.isEmpty { return LyricsResult(lines) }
            }
            return try await netEaseLyrics(query)
        } catch let retry as RetryLater {
            return LyricsResult([], validUntil: retry.date)
        } catch {
            return LyricsResult([], validUntil: Date().addingTimeInterval(60))
        }
    }

    private func folded(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func matches(_ record: Record, _ query: LyricsQuery) -> Bool {
        guard folded(query.title) == folded(record.trackName), folded(query.artist) == folded(record.artistName) else { return false }
        guard let expected = query.duration else { return true }
        guard let actual = record.duration, actual > 0 else { return false }
        return abs(Double(expected) - actual) <= 2
    }

    private struct NetEaseSearch: Decodable {
        struct Name: Decodable { let name: String }
        struct Song: Decodable {
            let id: Int
            let name: String
            let artists: [Name]
            let album: Name
            let duration: Double
        }
        struct Result: Decodable { let songs: [Song]? }
        let code: Int
        let result: Result?
    }
    private struct NetEaseLyric: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let code: Int
        let lrc: LRC?
    }

    private func netEaseLyrics(_ query: LyricsQuery) async throws -> LyricsResult {
        let keywords = "\(query.artist) \(query.title)"
        let items = [URLQueryItem(name: "s", value: keywords), URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "type", value: "1")]
        let response: NetEaseSearch? = try await read(host: "music.163.com", path: "/api/search/get/web", items: items)
        guard let response, response.code == 200 else { throw URLError(.badServerResponse) }
        let candidates = (response.result?.songs ?? []).filter { song in
            let name = song.artists.map(\.name).joined(separator: ", ")
            let record = Record(trackName: song.name, artistName: name, albumName: song.album.name, duration: song.duration / 1000, instrumental: nil, syncedLyrics: nil)
            return matches(record, query)
        }
        let song = candidates.first { folded($0.album.name) == folded(query.album) } ?? candidates.first
        guard let song else { return LyricsResult([]) }
        let queryItems = [URLQueryItem(name: "id", value: String(song.id)), URLQueryItem(name: "lv", value: "-1")]
        let result: NetEaseLyric? = try await read(host: "music.163.com", path: "/api/song/lyric", items: queryItems)
        guard let result, result.code == 200 else { throw URLError(.badServerResponse) }
        return LyricsResult(LyricsParser.parse(result.lrc?.lyric ?? ""))
    }

    private func read<T: Decodable>(host: String, path: String, items: [URLQueryItem]) async throws -> T? {
        try Task.checkCancellation()
        if let until = limitedUntil[host], Date() < until { throw RetryLater(date: until) }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        // Some query decoders interpret literal plus signs as spaces.
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw URLError(.badURL) }
        var lookup = URLRequest(url: url, timeoutInterval: 12)
        lookup.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        lookup.setValue("NotchIsland/\(version) (https://github.com/cirnolau-art/Dinamic-island-but-DIYed-by-Cirnolau)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await request(lookup)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            let value = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(secondsFromGMT: 0)
            format.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            let retry = Double(value).map { Date().addingTimeInterval($0) } ?? format.date(from: value)
            let until = max(retry ?? .distantPast, Date().addingTimeInterval(60))
            limitedUntil[host] = until
            throw RetryLater(date: until)
        }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
