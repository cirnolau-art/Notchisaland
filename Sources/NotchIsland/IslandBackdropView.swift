import AppKit
import QuartzCore

struct IslandBackdropConfiguration: Equatable {
    static let defaultFrost = 0.30
    static let defaultDarkening = 0.22
    static let defaultRim = 0.35

    var style: IslandBackgroundStyle
    var blur: Double
    var opacity: Double
    var rimStrength = Self.defaultRim

    static var current: Self {
        let preferences = IslandPreferences.shared
        return .init(style: preferences.effectiveBackgroundStyle, blur: preferences.glassBlur,
                     opacity: preferences.glassOpacity, rimStrength: preferences.glassRimStrength)
    }

    var frostAlpha: Double { blur * blur * 0.92 }
    var tintAlphas: [Double] { [1, 1, opacity * 0.9, opacity * 0.72] }
}

/// Native Apple materials; no private blur filters, wallpaper capture, or render timer.
final class IslandBackdropView: NSView {
    private let clipped = NSView()
    private let materials = NSView()
    private let tintView = NSView()
    private let clipMask = CAShapeLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let tint = CAGradientLayer()
    private var glass: NSView?
    private var blur: NSVisualEffectView?
    private var lastConfiguration: IslandBackdropConfiguration?
    private var lastRect = CGRect.zero
    private var releaseWork: DispatchWorkItem?
    var onActivityChanged: ((Bool) -> Void)?
    var nativeEffectActive: Bool { glass != nil }
    var debugClipBounds: CGRect? { clipMask.path?.boundingBoxOfPath }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for view in [clipped, materials, tintView] { view.wantsLayer = true; view.frame = bounds; view.autoresizingMask = [.width, .height] }
        addSubview(clipped); clipped.addSubview(materials); clipped.addSubview(tintView)
        clipped.layer?.mask = clipMask
        tintView.layer?.addSublayer(tint)
        clipped.layer?.addSublayer(rim); rim.mask = rimMask
        rimMask.fillColor = nil; rimMask.strokeColor = NSColor.white.cgColor; rimMask.lineWidth = 1.5
        rim.startPoint = CGPoint(x: 0, y: 1); rim.endPoint = CGPoint(x: 1, y: 0)
        rim.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.25).cgColor,
                      NSColor.white.withAlphaComponent(0.09).cgColor, NSColor.white.withAlphaComponent(0.65).cgColor]
        rim.locations = [0, 0.27, 0.55, 1]
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { releaseWork?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(configuration: IslandBackdropConfiguration, rect: CGRect, path: CGPath, previous: CGPath?, notchHeight: CGFloat, spring: CASpringAnimation?) {
        let available: Bool
        if #available(macOS 26.0, *) { available = true } else { available = false }
        let visible = configuration.style == .glass && available && rect.height > notchHeight + 1 && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        releaseWork?.cancel(); releaseWork = nil
        guard visible else {
            if configuration.style == .glass, glass != nil, let spring, let previous, rect.height <= notchHeight + 1 {
                CATransaction.begin(); CATransaction.setDisableActions(true); clipMask.path = path; rimMask.path = path; CATransaction.commit()
                // Reopening to the previous size must still update a mask that is midway through collapse.
                lastRect = rect
                let animation = spring.copy() as! CASpringAnimation; animation.fromValue = previous; animation.toValue = path
                clipMask.add(animation, forKey: "morph"); rimMask.add(animation, forKey: "morph")
                let work = DispatchWorkItem { [weak self] in self?.releaseEffects() }
                releaseWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + spring.duration, execute: work)
            } else { releaseEffects() }
            return
        }
        isHidden = false
        if #available(macOS 26.0, *), glass == nil {
            let effect = NSGlassEffectView(frame: rect)
            effect.style = .clear; effect.cornerRadius = 24
            if #available(macOS 27.0, *) { effect.effectIsInteractive = false }
            materials.addSubview(effect)
            glass = effect
            onActivityChanged?(true)
        }
        guard configuration != lastConfiguration || rect != lastRect else { return }
        lastConfiguration = configuration; lastRect = rect
        glass?.frame = rect
        updateFrost(alpha: configuration.frostAlpha, frame: rect)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clipMask.path = path; rimMask.path = path; rim.frame = bounds; rimMask.frame = bounds
        rim.opacity = Float(configuration.rimStrength)
        let stops = Self.tintStops(height: rect.height, notchHeight: notchHeight)
        tint.frame = rect; tint.startPoint = CGPoint(x: 0.5, y: 1); tint.endPoint = CGPoint(x: 0.5, y: 0)
        // An opaque plateau covers the complete camera area; opacity only affects the lower material.
        tint.colors = configuration.tintAlphas.map { NSColor.black.withAlphaComponent($0).cgColor }
        tint.locations = stops.map { NSNumber(value: $0) }
        CATransaction.commit()
        clipMask.removeAnimation(forKey: "morph"); rimMask.removeAnimation(forKey: "morph")
        if let spring, let previous {
            let animation = spring.copy() as! CASpringAnimation
            animation.fromValue = previous; animation.toValue = path
            clipMask.add(animation, forKey: "morph"); rimMask.add(animation, forKey: "morph")
        }
    }
    /// Public for geometry tests: the black plateau must cover the entire physical notch.
    static func tintStops(height: CGFloat, notchHeight: CGFloat) -> [Double] {
        let plateau = min(0.97, (notchHeight + 3) / max(1, height))
        let feather = min(0.99, max(plateau + 0.01, (notchHeight + 32) / max(1, height)))
        return [0, Double(plateau), Double(feather), 1]
    }

    private func updateFrost(alpha: Double, frame: CGRect) {
        guard alpha > 0 else {
            blur?.removeFromSuperview()
            blur = nil
            return
        }
        if blur == nil {
            let effect = NSVisualEffectView(frame: frame)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            materials.addSubview(effect, positioned: .below, relativeTo: glass)
            blur = effect
        }
        blur?.frame = frame
        blur?.alphaValue = alpha
    }
    private func releaseEffects() {
        clipMask.removeAllAnimations(); rimMask.removeAllAnimations()
        let active = glass != nil
        isHidden = true; glass?.removeFromSuperview(); glass = nil; blur?.removeFromSuperview(); blur = nil
        lastRect = .zero; lastConfiguration = nil
        if active { onActivityChanged?(false) }
    }
}
