import XCTest
@testable import NotchIsland

private actor LyricsHTTPFixture {
    struct Reply {
        let status: Int
        let json: String
        let headers: [String: String]?
        init(_ status: Int, _ json: String = "", headers: [String: String]? = nil) {
            self.status = status; self.json = json; self.headers = headers
        }
    }
    var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { XCTFail("Unexpected request"); throw URLError(.badURL) }
        let reply = replies.removeFirst()
        return (Data(reply.json.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
    }
}

final class OnlineLyricsTests: XCTestCase {
    private func track(_ title: String = "歌+曲") -> LyricsQuery {
        LyricsQuery(MediaInfo(title: title, artist: "歌手", album: "专辑", duration: 201), directory: "", online: true)!
    }

    func testLookupEscapesMetadataAndPrefersTimedExactVersion() async {
        let exact = #"{"trackName":"歌+曲","artistName":"歌手","albumName":"专辑","duration":201,"syncedLyrics":"[00:01.5]行"}"#
        let fixture = LyricsHTTPFixture([.init(200, exact)])
        let result = await OnlineLyricsProvider(request: { try await fixture.send($0) }).fetch(track())
        XCTAssertEqual(result.lines, [LyricLine(time: 1.5, text: "行")])
        let requests = await fixture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].url!.absoluteString.contains("%2B"))
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "User-Agent")!.contains("NotchIsland"))
    }

    func testMissingExactSearchRejectsDifferentPerformanceAndArtist() async {
        let search = #"[{"trackName":"歌+曲","artistName":"歌手","duration":260,"syncedLyrics":"[00:01]现场版"},{"trackName":"歌+曲","artistName":"其他歌手","duration":201,"syncedLyrics":"[00:01]翻唱"},{"trackName":"歌+曲","artistName":"歌手","duration":200,"syncedLyrics":"[00:02]匹配"}]"#
        let fixture = LyricsHTTPFixture([.init(404), .init(200, search)])
        let result = await OnlineLyricsProvider(request: { try await fixture.send($0) }).fetch(track())
        XCTAssertEqual(result.lines.map(\.text), ["匹配"])
        let paths = await fixture.requests.map { $0.url!.path }
        XCTAssertEqual(paths, ["/api/get", "/api/search"])
    }

    func testNetEaseFallbackVerifiesVersionBeforeFetchingLyrics() async {
        let search = #"{"code":200,"result":{"songs":[{"id":11,"name":"歌+曲","artists":[{"name":"歌手"}],"album":{"name":"现场录音"},"duration":305000},{"id":22,"name":"歌+曲","artists":[{"name":"歌手"}],"album":{"name":"专辑"},"duration":201305}]}}"#
        let fixture = LyricsHTTPFixture([.init(404), .init(200, "[]"), .init(200, search), .init(200, #"{"code":200,"lrc":{"lyric":"[00:10.250]备用来源"}}"#)])
        let result = await OnlineLyricsProvider(request: { try await fixture.send($0) }).fetch(track())
        XCTAssertEqual(result.lines, [LyricLine(time: 10.25, text: "备用来源")])
        let urls = await fixture.requests.compactMap(\.url)
        XCTAssertEqual(urls.map(\.host), ["lrclib.net", "lrclib.net", "music.163.com", "music.163.com"])
        XCTAssertTrue(urls.last!.query!.contains("id=22"))
    }

    func testPlainLyricsNeverFabricateTimingAndInstrumentalsStayEmpty() async {
        let fixture = LyricsHTTPFixture([.init(200, #"{"trackName":"歌+曲","artistName":"歌手","duration":201,"instrumental":true}"#)])
        let result = await OnlineLyricsProvider(request: { try await fixture.send($0) }).fetch(track())
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertTrue(LyricsParser.parse("任意普通文本").isEmpty)
    }

    func testRateLimitRespectedAcrossTrackChanges() async {
        let fixture = LyricsHTTPFixture([.init(429, headers: ["Retry-After": "300"])])
        let provider = OnlineLyricsProvider(request: { try await fixture.send($0) })
        let first = await provider.fetch(track())
        let second = await provider.fetch(track("下一首"))
        XCTAssertEqual(first.validUntil, second.validUntil)
        XCTAssertGreaterThan(first.validUntil.timeIntervalSinceNow, 290)
        let count = await fixture.requests.count
        XCTAssertEqual(count, 1)
    }

    func testLocalFileTakesPrecedenceAndOfflineMissStaysEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var info = MediaInfo(title: "歌曲", artist: "歌手", duration: 201)
        try "[00:01.50]本地歌词".write(to: root.appendingPathComponent("歌手 - 歌曲.lrc"), atomically: true, encoding: .utf8)
        let local = await LyricsLookup.resolveLyrics(LyricsQuery(info, directory: root.path, online: true)!)
        XCTAssertEqual(local.lines, [LyricLine(time: 1.5, text: "本地歌词")])
        info.title = UUID().uuidString
        let offline = await LyricsLookup.resolveLyrics(LyricsQuery(info, directory: root.path, online: false)!)
        XCTAssertTrue(offline.lines.isEmpty)
    }

    @MainActor
    func testLookupCoalescesPollsCachesResultsAndDropsLateCompletions() async {
        let started = expectation(description: "first song started")
        let updated = expectation(description: "second song delivered")
        let completed = expectation(description: "first returned after song change")
        let first = track("A"), second = track("B")
        var releaseFirst: CheckedContinuation<Void, Never>?
        var requested: [String] = []
        let lookup = LyricsLookup { @MainActor query in
            requested.append(query.title)
            if query == first {
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                    started.fulfill()
                }
                completed.fulfill()
            }
            return LyricsResult([LyricLine(time: 0, text: query.title)])
        }
        var deliveries: [[LyricLine]] = []
        lookup.onChange = { lines in deliveries.append(lines); updated.fulfill() }
        _ = lookup.select(first)
        _ = lookup.select(first)
        await fulfillment(of: [started], timeout: 2)
        _ = lookup.select(second)
        await fulfillment(of: [updated], timeout: 2)
        releaseFirst?.resume()
        await fulfillment(of: [completed], timeout: 2)
        _ = lookup.select(nil)
        XCTAssertEqual(lookup.select(second), [LyricLine(time: 0, text: "B")])
        XCTAssertEqual(requested, ["A", "B"])
        XCTAssertEqual(deliveries, [[LyricLine(time: 0, text: "B")]])
    }
}
