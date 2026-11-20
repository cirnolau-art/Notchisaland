import AppKit
import QuartzCore

struct IslandBackdropConfiguration: Equatable {
    var style: IslandBackgroundStyle
    var blur: Double
    var opacity: Double
    static var current: Self { .init(style: IslandPreferences.shared.effectiveBackgroundStyle, blur: IslandPreferences.shared.glassBlur, opacity: IslandPreferences.shared.glassOpacity) }
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
        rimMask.fillColor = nil; rimMask.strokeColor = NSColor.white.cgColor; rimMask.lineWidth = 2
        rim.startPoint = CGPoint(x: 0, y: 1); rim.endPoint = CGPoint(x: 1, y: 0)
        rim.colors = [NSColor.white.withAlphaComponent(0.36).cgColor, NSColor.white.withAlphaComponent(0.04).cgColor, NSColor.white.withAlphaComponent(0.19).cgColor]
        rim.locations = [0, 0.48, 1]
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
            let nativeBlur = NSVisualEffectView(frame: rect)
            nativeBlur.material = .hudWindow; nativeBlur.blendingMode = .behindWindow; nativeBlur.state = .active
            nativeBlur.isEmphasized = false
            materials.addSubview(nativeBlur); materials.addSubview(effect)
            glass = effect; blur = nativeBlur
            onActivityChanged?(true)
        }
        guard configuration != lastConfiguration || rect != lastRect else { return }
        lastConfiguration = configuration; lastRect = rect
        glass?.frame = rect; blur?.frame = rect
        // Apple owns the blur radius. Blend native materials to expose a continuous strength control.
        blur?.alphaValue = configuration.blur
        glass?.alphaValue = 1 // Preserve the native refracting rim, even at minimum supplemental blur.
        if #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView {
            glass.style = .clear
            glass.tintColor = NSColor.black.withAlphaComponent(configuration.opacity * 0.25)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clipMask.path = path; rimMask.path = path; rim.frame = bounds; rimMask.frame = bounds
        let stops = Self.tintStops(height: rect.height, notchHeight: notchHeight)
        tint.frame = rect; tint.startPoint = CGPoint(x: 0.5, y: 1); tint.endPoint = CGPoint(x: 0.5, y: 0)
        // An opaque plateau covers the complete camera area; opacity only affects the lower material.
        tint.colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                       NSColor.black.withAlphaComponent(configuration.opacity * 0.7).cgColor,
                       NSColor.black.withAlphaComponent(configuration.opacity * 0.18).cgColor]
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
        let feather = min(0.99, max(plateau + 0.01, (notchHeight + 65) / max(1, height)))
        return [0, Double(plateau), Double(feather), 1]
    }
    private func releaseEffects() {
        clipMask.removeAllAnimations(); rimMask.removeAllAnimations()
        let active = glass != nil
        isHidden = true; glass?.removeFromSuperview(); glass = nil; blur?.removeFromSuperview(); blur = nil
        lastRect = .zero; lastConfiguration = nil
        if active { onActivityChanged?(false) }
    }
}
