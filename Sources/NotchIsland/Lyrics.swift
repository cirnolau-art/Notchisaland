import Foundation

struct LyricSegment: Equatable {
    let time: TimeInterval
    let text: String
    let endTime: TimeInterval?

    init(time: TimeInterval, text: String, endTime: TimeInterval? = nil) {
        self.time = time
        self.text = text
        self.endTime = endTime
    }
}

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
    let segments: [LyricSegment]
    let wrappedCues: [LyricHighlight]?

    init(time: TimeInterval, text: String, segments: [LyricSegment] = [], wrappedCues: [LyricHighlight]? = nil) {
        self.time = time
        self.text = text
        self.segments = segments
        self.wrappedCues = wrappedCues
    }

    var hasReliableWordTiming: Bool {
        if let wrappedCues { return !wrappedCues.isEmpty }
        guard time.isFinite, !segments.isEmpty, segments.map(\.text).joined() == text else { return false }
        if segments.count == 1, segments[0].endTime == nil { return false }
        var previousStart = -Double.infinity
        var previousEnd: TimeInterval?
        for segment in segments {
            guard !segment.text.isEmpty, segment.time.isFinite, segment.time >= time - 0.001,
                  segment.time > previousStart,
                  previousEnd.map({ $0 <= segment.time + 0.001 }) ?? true,
                  segment.endTime.map({ $0.isFinite && $0 > segment.time }) ?? true else { return false }
            previousStart = segment.time
            previousEnd = segment.endTime
        }
        return true
    }
}

enum LyricsAnimationStyle: Int, CaseIterable {
    case appleMusic, efficient
    var title: String { self == .appleMusic ? "Apple Music 风格" : "省资源" }
}

enum LyricsPlacement: Int, CaseIterable {
    case hidden, below, side
    var title: String {
        switch self { case .hidden: return "不显示"; case .below: return "刘海下方"; case .side: return "刘海侧边" }
    }
}

enum LyricsParser {
    private static let timestamp = #"([0-9]{1,3}):([0-5]?[0-9])(?:[.:]([0-9]{1,3}))?"#
    private static let lineTag = try! NSRegularExpression(pattern: #"\["# + timestamp + #"\]"#)
    private static let segmentTag = try! NSRegularExpression(pattern: "<" + timestamp + ">")
    private static let yrcLineTag = try! NSRegularExpression(pattern: #"^\[([0-9]{1,9}),([0-9]{1,9})\]"#)
    private static let yrcSegmentTag = try! NSRegularExpression(pattern: #"\(([0-9]{1,9}),([0-9]{1,9}),[0-9]{1,9}\)"#)

    static func parse(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let source = raw as NSString
            let range = NSRange(location: 0, length: source.length)
            let times = lineTag.matches(in: raw, range: range).compactMap { lrcTime($0, in: source) }
            guard let firstTime = times.first else { continue }
            let body = lineTag.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
            let bodySource = body as NSString
            let bodyRange = NSRange(location: 0, length: bodySource.length)
            let tags = segmentTag.matches(in: body, range: bodyRange)
            let lyric = segmentTag.stringByReplacingMatches(in: body, range: bodyRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { continue }

            let starts = tags.compactMap { lrcTime($0, in: bodySource) }
            var segments: [LyricSegment] = []
            if let firstTag = tags.first, starts.count == tags.count,
               starts.first.map({ $0 >= firstTime }) == true, isOrdered(starts) {
                let prefix = bodySource.substring(to: firstTag.range.location)
                for (index, tag) in tags.enumerated() {
                    let start = NSMaxRange(tag.range)
                    let next = index + 1
                    let end = next < tags.count ? tags[next].range.location : bodySource.length
                    if end > start {
                        let text = bodySource.substring(with: NSRange(location: start, length: end - start))
                        segments.append(LyricSegment(time: starts[index], text: text, endTime: next < starts.count ? starts[next] : nil))
                    }
                }
                segments = prefix.trimmingCharacters(in: .whitespaces).isEmpty ? trimmed(segments) : []
            }

            for time in times {
                let offset = time - firstTime
                let relocated = segments.map {
                    LyricSegment(time: $0.time + offset, text: $0.text, endTime: $0.endTime.map { $0 + offset })
                }
                result.append(LyricLine(time: time, text: lyric, segments: relocated))
            }
        }
        return sorted(result)
    }

    static func parseYRC(_ text: String) -> [LyricLine] {
        let result: [LyricLine] = text.components(separatedBy: .newlines).compactMap { row in
            let raw = row.trimmingCharacters(in: .whitespaces)
            let source = raw as NSString
            let range = NSRange(location: 0, length: source.length)
            guard let header = yrcLineTag.firstMatch(in: raw, range: range),
                  let start = milliseconds(header, 1, in: source),
                  let duration = milliseconds(header, 2, in: source) else { return nil }
            let body = source.substring(from: NSMaxRange(header.range))
            let bodySource = body as NSString
            let bodyRange = NSRange(location: 0, length: bodySource.length)
            let tags = yrcSegmentTag.matches(in: body, range: bodyRange)
            let lyric = yrcSegmentTag.stringByReplacingMatches(in: body, range: bodyRange, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { return nil }
            let line = LyricLine(time: start, text: lyric)
            guard let first = tags.first,
                  bodySource.substring(to: first.range.location).trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            var segments: [LyricSegment] = []
            for (index, tag) in tags.enumerated() {
                let from = NSMaxRange(tag.range)
                let until = index + 1 < tags.count ? tags[index + 1].range.location : bodySource.length
                guard let time = milliseconds(tag, 1, in: bodySource),
                      let length = milliseconds(tag, 2, in: bodySource),
                      time >= start, time + length <= start + duration + 0.001 else { return line }
                if until > from {
                    let word = bodySource.substring(with: NSRange(location: from, length: until - from))
                    segments.append(LyricSegment(time: time, text: word, endTime: time + length))
                }
            }
            return LyricLine(time: start, text: lyric, segments: isOrdered(segments.map(\.time)) ? trimmed(segments) : [])
        }
        return sorted(result)
    }

    private static func lrcTime(_ match: NSTextCheckingResult, in source: NSString) -> TimeInterval? {
        guard let minutes = Double(source.substring(with: match.range(at: 1))),
              let seconds = Double(source.substring(with: match.range(at: 2))) else { return nil }
        let fraction = match.range(at: 3)
        let subsecond = fraction.location == NSNotFound ? 0 : Double("0." + source.substring(with: fraction)) ?? 0
        return minutes * 60 + seconds + subsecond
    }

    private static func milliseconds(_ match: NSTextCheckingResult, _ index: Int, in source: NSString) -> TimeInterval? {
        Double(source.substring(with: match.range(at: index))).map { $0 / 1000 }
    }

    private static func isOrdered(_ times: [TimeInterval]) -> Bool {
        zip(times, times.dropFirst()).allSatisfy { $0.0 <= $0.1 }
    }

    private static func trimmed(_ segments: [LyricSegment]) -> [LyricSegment] {
        guard let first = segments.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
              let last = segments.lastIndex(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
              first < last, segments[first].time < segments[last].time else { return [] }
        var result = Array(segments[first...last])
        let leading = result[0]
        result[0] = LyricSegment(time: leading.time, text: String(leading.text.drop(while: \.isWhitespace)), endTime: leading.endTime)
        let trailing = result[result.count - 1]
        let lastText = String(trailing.text.reversed().drop(while: \.isWhitespace).reversed())
        result[result.count - 1] = LyricSegment(time: trailing.time, text: lastText, endTime: trailing.endTime)
        return result
    }

    private static func sorted(_ result: [LyricLine]) -> [LyricLine] {
        result.sorted { $0.time == $1.time ? $0.text < $1.text : $0.time < $1.time }
    }
}

enum LyricsStore {
    static func load(title: String, artist: String, directory: String) -> [LyricLine] {
        var roots = [URL(fileURLWithPath: directory, isDirectory: true)]
        let music = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchIsland Lyrics", isDirectory: true)
        if music.path != directory { roots.append(music) }
        let names = ["\(artist) - \(title)", "\(title) - \(artist)", title]
        let byteLimit = 512 * 1024
        for root in roots {
            for name in names {
                let filename = name.replacingOccurrences(of: "/", with: "-")
                let url = root.appendingPathComponent(filename).appendingPathExtension("lrc").resolvingSymlinksInPath()
                guard url.deletingLastPathComponent().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let file = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? file.close() }
                guard let data = try? file.read(upToCount: byteLimit + 1), data.count <= byteLimit,
                      let text = String(data: data, encoding: .utf8) else { continue }
                let lines = LyricsParser.parse(text)
                if !lines.isEmpty { return lines }
            }
        }
        return []
    }
}

extension MediaInfo {
    typealias LyricWindow = (previous: LyricLine?, current: LyricLine?, next: LyricLine?, nextNext: LyricLine?)

    func lyricWindow(at date: Date = Date()) -> LyricWindow {
        guard !lyrics.isEmpty else { return (nil, nil, nil, nil) }
        let elapsed = interpolated(at: date).elapsed
        let index = lyrics.lastIndex(where: { $0.time <= elapsed })
        guard let index else {
            return (nil, nil, lyrics.first, lyrics.indices.contains(1) ? lyrics[1] : nil)
        }

        let previous = index > lyrics.startIndex ? lyrics[index - 1] : nil
        let current = lyrics[index]
        let next = lyrics.indices.contains(index + 1) ? lyrics[index + 1] : nil
        let nextNext = lyrics.indices.contains(index + 2) ? lyrics[index + 2] : nil
        if let end = current.hideTime(next: next?.time, duration: duration), elapsed >= end {
            return (previous, nil, next, nextNext)
        }
        return (previous, current, next, nextNext)
    }

    func lyricWindow() -> LyricWindow {
        lyricWindow(at: Date())
    }

    func lyricLine(at date: Date = Date()) -> (current: LyricLine?, next: LyricLine?) {
        let window = lyricWindow(at: date)
        return (window.current, window.next)
    }

    func lyricLine() -> (current: LyricLine?, next: LyricLine?) {
        lyricLine(at: Date())
    }
}

extension LyricLine {
    /// Only explicit source timing can identify an instrumental gap in an LRC line.
    func hideTime(next: TimeInterval?, duration: TimeInterval) -> TimeInterval? {
        var result: TimeInterval? = duration > 0 ? duration : nil
        if hasReliableWordTiming, let end = segments.last?.endTime, next == nil || next! > end + 2 {
            result = min(result ?? .infinity, end + 1)
        }
        return result
    }
}
