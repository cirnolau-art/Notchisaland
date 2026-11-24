import AppKit
import CoreText

/// A display timeline only. The source lyrics and the onsets of their timed words stay unchanged.
struct LyricsWrapping {
    private var input: [LyricLine] = []
    private var output: [LyricLine] = []
    private var measuredWidth: CGFloat = 0
    private var font: NSFont?
    private var duration: TimeInterval = 0

    mutating func lines(for lyrics: [LyricLine], width: CGFloat, font: NSFont, duration: TimeInterval) -> [LyricLine] {
        let width = floor(width)
        guard width > 6 else { return lyrics }
        if width == measuredWidth, font == self.font, duration == self.duration, lyrics == input { return output }
        measuredWidth = width
        self.font = font
        self.duration = duration
        input = lyrics
        output = lyrics.enumerated().flatMap { index, line in
            let end = index + 1 < lyrics.count ? lyrics[index + 1].time : duration
            return Self.split(line, width: width, font: font, nextTime: end)
        }
        return output
    }

    private static func split(_ line: LyricLine, width: CGFloat, font: NSFont, nextTime: TimeInterval) -> [LyricLine] {
        let attributed = NSAttributedString(string: line.text, attributes: [.font: font])
        let source = line.text as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var ranges: [NSRange] = []
        var offset = 0
        while offset < source.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, offset, width)
            let cluster = source.rangeOfComposedCharacterSequence(at: offset)
            let proposed = NSRange(location: offset, length: max(cluster.length, count))
            let range = source.rangeOfComposedCharacterSequences(for: proposed)
            ranges.append(range)
            offset = NSMaxRange(range)
        }
        guard ranges.count > 1 else { return [line] }
        var position = 0
        let timed = line.hasReliableWordTiming
        let sourceCues = timed ? LyricHighlight.cues(for: line, next: nextTime > line.time ? nextTime : nil,
                                                   style: .appleMusic) : []
        let timedRanges = (timed ? line.segments : []).map { segment in
            let range = NSRange(location: position, length: segment.text.utf16.count)
            position = NSMaxRange(range)
            return (range, segment)
        }
        let window = nextTime > line.time ? nextTime - line.time : 4
        let minimumGap = min(0.12, window / Double(ranges.count * 2))
        var previous = line.time
        return ranges.enumerated().map { index, range in
            let segments = timedRanges.compactMap { span, segment -> LyricSegment? in
                let intersection = NSIntersectionRange(range, span)
                guard intersection.length > 0 else { return nil }
                return LyricSegment(time: segment.time, text: source.substring(with: intersection), endTime: segment.endTime)
            }
            let cues = sourceCues.compactMap { cue -> LyricHighlight? in
                let intersection = NSIntersectionRange(range, cue.range)
                guard intersection.length > 0 else { return nil }
                return LyricHighlight(range: NSRange(location: intersection.location - range.location,
                                                     length: intersection.length),
                                      start: cue.start, duration: cue.duration)
            }
            let distributed = line.time + window * Double(index) / Double(ranges.count)
            let limit = line.time + window - minimumGap * Double(ranges.count - index)
            let proposed = cues.first?.start ?? distributed
            let start = index == 0 ? line.time : min(limit, max(previous + minimumGap, proposed))
            previous = start
            return LyricLine(time: start, text: source.substring(with: range), segments: segments, wrappedCues: cues)
        }
    }
}
