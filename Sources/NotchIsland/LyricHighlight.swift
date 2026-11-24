import Foundation

/// A real source cue. Fades are composited by Core Animation, not a polling loop.
struct LyricHighlight: Equatable {
    let range: NSRange
    let start: TimeInterval
    let duration: TimeInterval
    func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= start else { return 0 }
        return duration > 0 ? min(1, max(0, (elapsed - start) / duration)) : 1
    }
    static func cues(for line: LyricLine, next: TimeInterval?, style: LyricsAnimationStyle) -> [Self] {
        if !usesWordTiming(for: line, style: style) {
            return [.init(range: NSRange(location: 0, length: line.text.utf16.count), start: line.time,
                          duration: 0)]
        }
        return line.wrappedCues ?? characterCues(for: line, next: next)
    }

    static func usesWordTiming(for line: LyricLine, style: LyricsAnimationStyle) -> Bool {
        style == .appleMusic && line.hasReliableWordTiming
    }

    private static func characterCues(for line: LyricLine, next: TimeInterval?) -> [Self] {
        var offset = 0
        var result: [Self] = []
        for (index, segment) in line.segments.enumerated() {
            let following = line.segments.indices.contains(index + 1) ? line.segments[index + 1].time : nil
            guard let segmentEnd = segment.endTime ?? following else {
                // The final LRC tag can have an onset without an end. Reveal its
                // whole segment together instead of guessing when each letter starts.
                let length = segment.text.utf16.count
                let available = next.map { max(0, $0 - segment.time) } ?? 0.20
                result.append(.init(range: NSRange(location: offset, length: length), start: segment.time,
                                    duration: min(0.20, available)))
                offset += length
                continue
            }
            let characters = Array(segment.text)
            let span = (segmentEnd - segment.time) / Double(characters.count)
            for (characterIndex, character) in characters.enumerated() {
                let length = String(character).utf16.count
                let start = segment.time + span * Double(characterIndex)
                result.append(.init(range: NSRange(location: offset, length: length), start: start,
                                    duration: min(0.20, span * 0.75)))
                offset += length
            }
        }
        return result
    }
}

enum LyricHDR {
    static func requestedGain(enabled: Bool, strength: Double, potential: CGFloat, usesDisplayPeak: Bool = false) -> CGFloat {
        guard enabled, strength.isFinite, potential.isFinite, potential > 1 else { return 1 }
        // Current headroom can be 1 until a layer requests EDR. The compositor
        // maps this tagged content to the headroom available at presentation.
        let peak = min(usesDisplayPeak ? CGFloat(Float16.greatestFiniteMagnitude) : 2, potential)
        return 1 + min(1, max(0, strength)) * (peak - 1)
    }
}
