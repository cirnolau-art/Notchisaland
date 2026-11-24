import Foundation

enum LyricRollDirection {
    case forward
    case backward
}

struct LyricRollState: Equatable {
    let alpha: CGFloat
    let blurRadius: CGFloat
    let offset: CGFloat
}

enum LyricRollPolicy {
    static func state(distance: Int, direction: LyricRollDirection, step: CGFloat) -> LyricRollState {
        let distance = max(0, distance)
        guard distance > 0 else { return LyricRollState(alpha: 1, blurRadius: 0, offset: 0) }

        let alpha: CGFloat = distance == 1 ? 0.87 : 0.75
        let signedStep = direction == .forward ? 1 : -1
        return LyricRollState(alpha: alpha, blurRadius: 0,
                              offset: CGFloat(distance) * step * CGFloat(signedStep))
    }

    static func transitionDuration(style: LyricsAnimationStyle) -> TimeInterval {
        style == .appleMusic ? 0.29 : 0
    }
}
