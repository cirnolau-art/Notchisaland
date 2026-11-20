import Foundation

/// A timestamped lyric line. Files stay local; no network or account access is required.
struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
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
    static func parse(_ text: String) -> [LyricLine] {
        let pattern = "\\[(\\d{1,3}):([0-5]?\\d)(?:\\.(\\d{1,3}))?\\]"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let matches = expression.matches(in: raw, range: range)
            let lyric = expression.stringByReplacingMatches(in: raw, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { continue }
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let minutesRange = Range(match.range(at: 1), in: raw),
                      let secondsRange = Range(match.range(at: 2), in: raw),
                      let minutes = Double(raw[minutesRange]), let seconds = Double(raw[secondsRange]) else { continue }
                var fraction = 0.0
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound, let fractionRange = Range(match.range(at: 3), in: raw) {
                    let fractionText = String(raw[fractionRange])
                    if let value = Double(fractionText) { fraction = value / (fractionText.count <= 2 ? 100 : 1000) }
                }
                result.append(LyricLine(time: minutes * 60 + seconds + fraction, text: lyric))
            }
        }
        return result.sorted { $0.time == $1.time ? $0.text < $1.text : $0.time < $1.time }
    }
}

enum LyricsStore {
    static func load(title: String, artist: String) -> [LyricLine] {
        let directory = IslandPreferences.shared.lyricsDirectory
        var roots = [URL(fileURLWithPath: directory, isDirectory: true)]
        let music = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchIsland Lyrics", isDirectory: true)
        if music.path != directory { roots.append(music) }
        let names = [title, "\(title) - \(artist)", "\(artist) - \(title)"]
        for root in roots {
            for name in names {
                let url = root.appendingPathComponent(name).appendingPathExtension("lrc")
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return LyricsParser.parse(text) }
            }
        }
        return []
    }
}

extension MediaInfo {
    func lyricLine(at date: Date = Date()) -> (current: LyricLine?, next: LyricLine?) {
        guard !lyrics.isEmpty else { return (nil, nil) }
        let elapsed = interpolated(at: date).elapsed
        let index = lyrics.lastIndex(where: { $0.time <= elapsed })
        guard let index else { return (nil, lyrics.first) }
        return (lyrics[index], lyrics.indices.contains(index + 1) ? lyrics[index + 1] : nil)
    }
}
