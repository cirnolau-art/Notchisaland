import AppKit
import QuartzCore

enum IslandGlassMaterial: Int, CaseIterable { case regular, clear, transparent }

struct IslandBackdropConfiguration: Equatable {
    static let defaultDarkening = 0.0
    static let defaultRim = 0.0

    var style: IslandBackgroundStyle
    var material: IslandGlassMaterial = .regular
    var opacity: Double
    var rimStrength = Self.defaultRim
    var showsGradient = true

    static var current: Self {
        let preferences = IslandPreferences.shared
        return .init(style: preferences.effectiveBackgroundStyle, material: preferences.glassMaterial,
                     opacity: preferences.glassOpacity, rimStrength: preferences.glassRimStrength,
                     showsGradient: preferences.glassGradientEnabled)
    }

    var nativeTint: NSColor? {
        material != .transparent && opacity > 0 ? NSColor.black.withAlphaComponent(opacity * 0.55) : nil
    }
    var drawsGradient: Bool { material != .transparent && showsGradient }
    var rimOpacity: Float { material == .transparent ? 0 : Float(rimStrength * 0.18) }
}

/// Native Apple materials; no private blur filters, wallpaper capture, or render timer.
final class IslandBackdropView: NSView {
    private let overlays = NSView()
    private let gradient = CAGradientLayer()
    private let gradientMask = CAShapeLayer()
    private let rim = CAShapeLayer()
    private static let glassRadius: CGFloat = 24
    private var glass: NSView?
    private var lastConfiguration: IslandBackdropConfiguration?
    private var lastRect = CGRect.zero
    private var releaseWork: DispatchWorkItem?
    private var releaseGeneration = 0
    private(set) var usesTranslucentBackground = false
    var nativeEffectActive: Bool { glass != nil }
    var debugClipBounds: CGRect? { rim.path?.boundingBoxOfPath }
    var debugGradientActive: Bool { !isHidden && gradient.opacity > 0 }
    var debugPresentedGlass: (frame: CGRect, opacity: Float)? {
        guard let glass, let layer = glass.layer else { return nil }
        let presented = layer.presentation() ?? layer
        return (presented.frame.intersection(bounds), presented.opacity)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        overlays.frame = bounds
        overlays.autoresizingMask = [.width, .height]
        overlays.wantsLayer = true
        addSubview(overlays)
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.opacity = 0
        gradient.mask = gradientMask
        overlays.layer?.addSublayer(gradient)
        overlays.layer?.addSublayer(rim)
        rim.fillColor = nil
        rim.strokeColor = NSColor.white.cgColor
        rim.lineWidth = 0.75
        rim.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { releaseWork?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(configuration: IslandBackdropConfiguration, rect: CGRect, path: CGPath, previous: CGPath?, notchRect: CGRect,
                spring: CASpringAnimation?, drivesMaterialFrame: Bool = false) {
        guard #available(macOS 26.0, *), configuration.style == .glass,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            cancelRelease()
            releaseEffects()
            return
        }
        let active = rect.height > notchRect.height + 1
        // Appearance updates during an existing collapse must not finish it early.
        if !active, rect == lastRect, spring == nil, releaseWork != nil { return }
        cancelRelease()
        if !active {
            guard glass != nil, let spring, let previous else { releaseEffects(); return }
            lastRect = rect
            usesTranslucentBackground = false
            syncMaterial(to: drivesMaterialFrame ? previous.boundingBoxOfPath : rect)
            setOpacity(0, on: glass?.layer, spring: spring)
            updateOverlays(configuration: lastConfiguration ?? configuration, rect: rect, path: path, previous: previous,
                           notchRect: notchRect, spring: spring, showing: false)
            let generation = releaseGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.releaseGeneration == generation else { return }
                self.releaseWork = nil
                self.releaseEffects()
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + spring.duration, execute: work)
            return
        }
        isHidden = false
        let addedGlass = glass == nil
        if glass == nil {
            let initialFrame = Self.materialFrame(for: drivesMaterialFrame && spring != nil ? (previous?.boundingBoxOfPath ?? rect) : rect)
            let effect = NSGlassEffectView(frame: initialFrame)
            effect.cornerRadius = Self.glassRadius
            effect.contentView = NSView(frame: effect.bounds)
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.glassRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            addSubview(effect, positioned: .below, relativeTo: overlays)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            effect.layer?.opacity = spring == nil ? 1 : 0
            CATransaction.commit()
            glass = effect
        }
        let geometryChanged = rect != lastRect || rim.frame != overlays.bounds
        let appearanceChanged = addedGlass || configuration != lastConfiguration
        guard appearanceChanged || geometryChanged || !usesTranslucentBackground else { return }
        lastConfiguration = configuration
        lastRect = rect
        if appearanceChanged {
            let effect = glass as? NSGlassEffectView
            effect?.style = configuration.material == .regular ? .regular : .clear
            effect?.tintColor = configuration.nativeTint
        }
        if geometryChanged {
            syncMaterial(to: drivesMaterialFrame && spring != nil ? (previous?.boundingBoxOfPath ?? rect) : rect)
        }
        setOpacity(1, on: glass?.layer, spring: spring)
        updateOverlays(configuration: configuration, rect: rect, path: path, previous: previous,
                       notchRect: notchRect, spring: spring, showing: true, updatePath: geometryChanged)
        usesTranslucentBackground = true
    }

    private func cancelRelease() {
        releaseGeneration += 1
        releaseWork?.cancel(); releaseWork = nil
    }

    private static func materialFrame(for rect: CGRect) -> CGRect {
        // Let the window cut off the upper corners while the bottom corners stay native.
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + glassRadius)
    }

    // AppKit lays out the glass internals at the NSView frame. Animating only
    // the outer CALayer leaves those internals at the final size mid-transition.
    func syncMaterial(to outline: CGRect) {
        let frame = Self.materialFrame(for: outline)
        guard let glass, glass.frame != frame else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glass.frame = frame
        glass.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func setOpacity(_ opacity: Float, on layer: CALayer?, spring: CASpringAnimation?) {
        guard let layer, layer.opacity != opacity else { return }
        let start = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        layer.removeAnimation(forKey: "backdropOpacity")
        guard let spring else { return }
        let animation = spring.copy() as! CASpringAnimation
        animation.keyPath = "opacity"
        animation.fromValue = start
        animation.toValue = opacity
        layer.add(animation, forKey: "backdropOpacity")
    }

    private func updateOverlays(configuration: IslandBackdropConfiguration, rect: CGRect, path: CGPath, previous: CGPath?,
                                notchRect: CGRect, spring: CASpringAnimation?, showing: Bool, updatePath: Bool = true) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if updatePath {
            rim.frame = overlays.bounds
            rim.path = path
            gradient.frame = overlays.bounds
            gradientMask.frame = gradient.bounds
            gradientMask.path = path
        }
        if showing && configuration.drawsGradient {
            let height = max(1, gradient.bounds.height)
            let top = max(0, gradient.frame.maxY - notchRect.maxY)
            let fade = max(1, min(134, rect.height - notchRect.height))
            let points = [0, top + notchRect.height, top + notchRect.height + fade * 0.22,
                          top + notchRect.height + fade * 0.5, top + notchRect.height + fade * 0.78,
                          top + notchRect.height + fade]
            gradient.locations = points.map { NSNumber(value: min(1, Double($0 / height))) }
            gradient.colors = [1, 1, 0.82, 0.42, 0.10, 0].map { NSColor.black.withAlphaComponent($0).cgColor }
        }
        CATransaction.commit()
        setOpacity(showing && configuration.drawsGradient ? 1 : 0, on: gradient, spring: spring)
        setOpacity(showing ? configuration.rimOpacity : 0, on: rim, spring: spring)
        guard updatePath else { return }
        for layer in [rim, gradientMask] { layer.removeAnimation(forKey: "morph") }
        guard let spring, let previous else { return }
        let animation = spring.copy() as! CASpringAnimation
        animation.fromValue = previous
        animation.toValue = path
        rim.add(animation, forKey: "morph")
        gradientMask.add(animation, forKey: "morph")
    }

    private func releaseEffects() {
        clearMaterial()
        usesTranslucentBackground = false
    }

    private func clearMaterial() {
        rim.removeAllAnimations()
        gradient.removeAllAnimations()
        gradientMask.removeAllAnimations()
        setOpacity(0, on: gradient, spring: nil)
        setOpacity(0, on: rim, spring: nil)
        isHidden = true
        glass?.removeFromSuperview()
        glass = nil
        lastRect = .zero; lastConfiguration = nil
    }
}
