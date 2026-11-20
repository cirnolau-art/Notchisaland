import Foundation

struct NotchNotificationLayout {
    static let widthRange = 320.0...600.0
    static let depthRange = 46.0...106.0
    static let defaultWidth = 410.0
    static let defaultDepth = 60.0

    let width: CGFloat
    let depth: CGFloat

    init(notch: CGFloat, available: CGFloat, width: Double, depth: Double) {
        let width = width.isFinite ? min(Self.widthRange.upperBound, max(Self.widthRange.lowerBound, width)) : Self.defaultWidth
        let depth = depth.isFinite ? min(Self.depthRange.upperBound, max(Self.depthRange.lowerBound, depth)) : Self.defaultDepth
        self.width = min(available, max(notch + 100, width))
        self.depth = depth
    }
}
