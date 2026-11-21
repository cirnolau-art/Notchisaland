import Foundation

/// A real source cue. Fades are composited by Core Animation, not a polling loop.
struct LyricHighlight {
    let range: NSRange
    let start: TimeInterval
    let duration: TimeInterval
    func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= start else { return 0 }
        return duration > 0 ? min(1, max(0, (elapsed - start) / duration)) : 1
    }
    static func cues(for line: LyricLine, next: TimeInterval?, style: LyricsAnimationStyle) -> [Self] {
        if style == .efficient || line.segments.isEmpty {
            return [.init(range: NSRange(location: 0, length: line.text.utf16.count), start: line.time,
                          duration: style == .efficient ? 0 : 0.20)]
        }
        var offset = 0
        return line.segments.enumerated().map { index, segment in
            defer { offset += segment.text.utf16.count }
            let following = line.segments.dropFirst(index + 1).first?.time ?? next
            let end = [segment.endTime, following].compactMap { $0 }.min() ?? segment.time + 0.4
            return .init(range: NSRange(location: offset, length: segment.text.utf16.count), start: segment.time,
                         duration: min(0.20, max(0.025, (end - segment.time) * 0.75)))
        }
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
