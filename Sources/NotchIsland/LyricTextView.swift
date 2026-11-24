import AppKit
import CoreText
import QuartzCore

/// Cached CoreText pixels; no display link, per-frame layout, or full-window HDR surface.
/// Only highlighted glyph tiles opt in to EDR; the backdrop and unspoken text remain SDR.
final class LyricTextView: NSView {
    private let base = CALayer()
    private var highlights: [CALayer] = []
    private var cues: [LyricHighlight] = []
    private var line: LyricLine?
    private var nextTime: TimeInterval?
    private var lyricAppearance = LyricsAppearance()
    private var font = NSFont.systemFont(ofSize: 12)
    private var style = LyricsAnimationStyle.efficient
    private var active = false
    private var centered = true
    private var lastSize = CGSize.zero
    private var lastScale: CGFloat = 0
    private var raster: LyricRaster?
    private var normal: CGImage?
    private var flowPalette = LyricFlowPalette.rgb
    private var flowGradient: LyricFlowGradient?
    private var compact = false
    private var suspended = false
    private var usesWordTiming: Bool {
        active && (line.map { LyricHighlight.usesWordTiming(for: $0, style: style) } ?? false)
    }
    private var usesFlow: Bool {
        active && style == .appleMusic && line != nil && lyricAppearance.flowStyle != .off
    }
    private var reduceMotion = false
    private var clock: (elapsed: TimeInterval, host: TimeInterval, playing: Bool)?
    private(set) var stringValue = ""
    private(set) var hdrGain: CGFloat = 1
    var debugHasGlyphAnimations: Bool { highlights.contains { $0.animation(forKey: "highlight") != nil } }
    var debugHasGlyphLiftAnimations: Bool { highlights.contains { $0.animation(forKey: "highlightLift") != nil } }
    var debugHasFeatherMasks: Bool { highlights.contains { $0.mask is CAGradientLayer } }
    var debugGlowActive: Bool { highlights.contains { $0.shadowOpacity > 0 } }
    var debugFlowActive: Bool { flowGradient != nil }
    var debugFlowAnimating: Bool {
        highlights.contains { $0.sublayers?.first?.sublayers?.first?.animation(forKey: "flowPosition") != nil }
    }
    var debugRollBlurRadius: CGFloat {
        guard let filter = layer?.filters?.first as? CIFilter,
              let value = filter.value(forKey: kCIInputRadiusKey) as? NSNumber else { return 0 }
        return CGFloat(value.doubleValue)
    }
    var debugGlyphAlphas: [CGFloat] {
        let baseAlpha = CGFloat(base.opacity)
        var result = [CGFloat](repeating: baseAlpha, count: stringValue.utf16.count)
        for (cue, tile) in zip(cues, highlights) {
            let opacity = CGFloat(tile.presentation()?.opacity ?? tile.opacity)
            for index in cue.range.location..<min(NSMaxRange(cue.range), result.count) {
                result[index] = baseAlpha + (1 - baseAlpha) * opacity
            }
        }
        return result
    }
    var debugProgress: [Double] { cues.map { $0.progress(at: elapsedNow) } }
    private var elapsedNow: TimeInterval {
        guard let clock else { return 0 }
        return clock.elapsed + (clock.playing ? CACurrentMediaTime() - clock.host : 0)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.allowsGroupOpacity = false
        layer?.addSublayer(base)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setGlassContrast(_ enabled: Bool) {
        // Apply the shadow to the SDR glyphs so the HDR layers keep their original compositing.
        base.shadowColor = NSColor.black.cgColor
        base.shadowRadius = 1
        base.shadowOffset = CGSize(width: 0, height: -1)
        base.shadowOpacity = enabled ? 1 : 0
    }
    override func layout() { super.layout(); refreshRenderingLayout() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshRenderingLayout() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refreshRenderingLayout() }

    func update(line: LyricLine?, next: TimeInterval?, elapsed: TimeInterval, style: LyricsAnimationStyle,
                appearance: LyricsAppearance, font: NSFont, active: Bool, centered: Bool, running: Bool,
                flowPalette: LyricFlowPalette = .rgb, compact: Bool = false) {
        let flowChanged = self.lyricAppearance.flowStyle != appearance.flowStyle || self.flowPalette != flowPalette || self.compact != compact
        let rebuild = self.line != line || self.style != style || self.lyricAppearance.colorRGB != appearance.colorRGB ||
            self.font != font || self.active != active || self.centered != centered || nextTime != next || flowChanged
        let glowChanged = self.lyricAppearance.glow != appearance.glow
        let reduceMotion = IslandPreferences.shared.reduceMotion
        let resync = clock == nil || clock?.playing != running || self.reduceMotion != reduceMotion
            || abs(elapsedNow - elapsed) > 0.065
        suspended = false
        self.reduceMotion = reduceMotion
        self.line = line; self.style = style; self.lyricAppearance = appearance; self.font = font
        self.active = active; self.centered = centered; nextTime = next
        self.flowPalette = flowPalette
        self.compact = compact
        let text = line?.text ?? ""
        if stringValue != text { stringValue = text; setAccessibilityValue(text) }
        if rebuild { lastSize = .zero }
        let rebuilt = rebuildIfNeeded()
        if glowChanged && !rebuilt {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            highlights.forEach(configureGlow)
            CATransaction.commit()
        }
        if rebuilt || resync || (reduceMotion && usesWordTiming) {
            clock = (elapsed, CACurrentMediaTime(), running)
            schedule(elapsed: elapsed, running: running)
        } else if glowChanged, flowGradient != nil {
            schedule(elapsed: elapsedNow, running: running)
        }
    }

    func copyPresentation(from other: LyricTextView) {
        update(line: other.line, next: other.nextTime, elapsed: other.elapsedNow, style: other.style,
               appearance: other.lyricAppearance, font: other.font, active: other.active, centered: other.centered,
               running: false, flowPalette: other.flowPalette, compact: other.compact)
    }

    func setRollPresentation(alpha: CGFloat, blurRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = Float(min(1, max(0, alpha)))
        if blurRadius > 0 {
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(blurRadius, forKey: kCIInputRadiusKey)
            layer?.filters = filter.map { [$0] }
        } else {
            layer?.filters = nil
        }
        CATransaction.commit()
    }

    func suspend(release: Bool = false) {
        let elapsed = elapsedNow
        clock = (elapsed, CACurrentMediaTime(), false)
        suspended = true
        schedule(elapsed: elapsed, running: false)
        if release {
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            base.contents = nil
            highlights.forEach { $0.removeFromSuperlayer() }; highlights.removeAll()
            raster = nil; normal = nil; flowGradient = nil; hdrGain = 1
            lastSize = .zero
        }
    }

    private func refreshRenderingLayout() {
        if rebuildIfNeeded(), let clock { schedule(elapsed: elapsedNow, running: clock.playing) }
    }

    private func rebuildIfNeeded() -> Bool {
        guard !suspended else { return false }
        let scale = window?.backingScaleFactor ?? 2
        let gain = LyricHDR.requestedGain(enabled: usesWordTiming && lyricAppearance.hdrEnabled && !isHiddenOrHasHiddenAncestor,
                                          strength: lyricAppearance.hdrStrength,
                                          potential: window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1,
                                          usesDisplayPeak: usesFlow)
        let geometryChanged = lastSize != bounds.size || lastScale != scale
        guard geometryChanged || hdrGain != gain else { return false }
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        if !geometryChanged {
            updateHighlightImage(gain: gain)
            return true
        }
        lastSize = bounds.size; lastScale = scale
        highlights.forEach { $0.removeFromSuperlayer() }; highlights.removeAll()
        cues.removeAll(keepingCapacity: true)
        raster = nil; normal = nil; flowGradient = nil; hdrGain = 1
        base.frame = bounds
        guard let line, bounds.width > 0, bounds.height > 0,
              let raster = LyricRaster(line: line.text, font: font, size: bounds.size, scale: scale, centered: centered),
              let normal = raster.image(color: lyricAppearance.color, gain: 1) else { base.contents = nil; return true }
        base.contents = normal; base.contentsScale = scale
        base.opacity = active ? (usesWordTiming ? 0.44 : 1) : (compact ? 0.34 : 0.83)
        guard usesWordTiming || usesFlow else { return true }
        self.raster = raster; self.normal = normal
        let renderCues = usesWordTiming
            ? LyricHighlight.cues(for: line, next: nextTime, style: style)
            : [.init(range: NSRange(location: 0, length: line.text.utf16.count), start: line.time, duration: 0)]
        for cue in renderCues {
            let region = raster.rect(for: cue.range)
            let minX = max(0, (region.minX * scale).rounded())
            let maxX = min(CGFloat(raster.width), (region.maxX * scale).rounded())
            guard maxX > minX else { continue }
            if usesWordTiming {
                cues.append(cue)
            }
            let tile = CALayer()
            tile.allowsGroupOpacity = false
            tile.frame = CGRect(x: minX / scale, y: 0, width: (maxX - minX) / scale, height: bounds.height)
            tile.contentsRect = CGRect(x: minX / CGFloat(raster.width), y: 0,
                                       width: (maxX - minX) / CGFloat(raster.width), height: 1)
            tile.contentsScale = scale
            if usesWordTiming {
                tile.mask = makeFeatherMask(frame: tile.bounds)
            }
            configureGlow(tile)
            tile.opacity = usesWordTiming ? 0 : 1
            layer?.addSublayer(tile); highlights.append(tile)
        }
        updateHighlightImage(gain: gain)
        return true
    }

    private func configureGlow(_ tile: CALayer) {
        tile.shadowColor = lyricAppearance.color.cgColor
        if usesFlow {
            let strength = lyricAppearance.glow
            tile.shadowOpacity = Float(compact ? 0.52 + 0.32 * strength : 0.46 + 0.34 * strength)
            tile.shadowRadius = compact ? 2 + 1.6 * strength : 3 + 2.5 * strength
        } else {
            tile.shadowOpacity = Float(lyricAppearance.glow * 0.65)
            tile.shadowRadius = 1 + 4 * lyricAppearance.glow
        }
        tile.shadowOffset = .zero
    }

    private func makeFeatherMask(frame: CGRect) -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = frame
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, 0, 0.18]
        return mask
    }

    private func updateFeatherMask(_ tile: CALayer, progress: Double) {
        guard let mask = tile.mask as? CAGradientLayer else { return }
        mask.locations = featherLocations(progress)
    }

    private func featherLocations(_ progress: Double) -> [NSNumber] {
        let value = max(0, min(1, progress))
        let feather = 0.18
        return [0, NSNumber(value: value), NSNumber(value: min(1.05, value + feather))]
    }

    private func updateHighlightImage(gain: CGFloat) {
        guard !highlights.isEmpty, let raster, let normal else { return }
        flowGradient = usesFlow ? LyricFlowGradient(palette: flowPalette, gain: 1) : nil
        let extendedFlow = gain > 1 && flowGradient != nil ? LyricFlowGradient(palette: flowPalette, gain: gain) : nil
        let extended = gain > 1 && flowGradient == nil ? raster.image(color: lyricAppearance.color, gain: gain) : nil
        hdrGain = extendedFlow == nil && extended == nil ? 1 : gain
        let rowWidth = CGFloat(raster.width) / raster.scale
        for tile in highlights {
            tile.sublayers?.forEach { $0.removeFromSuperlayer() }
            tile.contents = flowGradient == nil ? normal : nil
            if let flowGradient {
                tile.addSublayer(flowGradient.makeLayer(stencil: normal, rect: tile.contentsRect,
                                                        rowWidth: rowWidth, height: tile.bounds.height))
            }
            if extended != nil || extendedFlow != nil {
                // Mix the cached peak image over the SDR glyph using cue progress.
                let hdr = CALayer()
                hdr.name = "lyricHDR"
                hdr.frame = tile.bounds
                hdr.contentsRect = tile.contentsRect
                hdr.contentsScale = tile.contentsScale
                if let extendedFlow {
                    hdr.addSublayer(extendedFlow.makeLayer(stencil: normal, rect: tile.contentsRect,
                                                           rowWidth: rowWidth, height: tile.bounds.height))
                } else {
                    hdr.contents = extended
                    if #available(macOS 26.0, *) { hdr.preferredDynamicRange = .constrainedHigh }
                    else { hdr.wantsExtendedDynamicRangeContent = true }
                }
                tile.addSublayer(hdr)
            }
        }
    }

    private func hdrLayer(for tile: CALayer) -> CALayer? {
        guard let layer = tile.sublayers?.last, layer.name == "lyricHDR" else { return nil }
        return layer
    }

    private func schedule(elapsed: TimeInterval, running: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        let host = CACurrentMediaTime()
        let animate = running && style == .appleMusic && !reduceMotion
        scheduleFlow(elapsed: elapsed, running: animate, host: host)
        for (cue, tile) in zip(cues, highlights) {
            let progress = reduceMotion ? (elapsed >= cue.start ? 1.0 : 0.0) : cue.progress(at: elapsed)
            tile.removeAnimation(forKey: "highlight")
            tile.removeAnimation(forKey: "highlightLift")
            tile.mask?.removeAnimation(forKey: "highlightFeather")
            let hdr = hdrLayer(for: tile)
            hdr?.removeAnimation(forKey: "highlightGain")
            updateFeatherMask(tile, progress: progress)
            tile.opacity = Float(progress)
            hdr?.opacity = Float(progress)
            let lift = reduceMotion ? 0 : -1.6 * progress
            tile.transform = CATransform3DMakeTranslation(0, lift, 0)
            guard animate, progress < 1 else { continue }
            let duration = cue.duration * (1 - progress)
            guard duration > 0 else { continue }
            let begin = host + max(0, cue.start - elapsed)
            func animateProgress(_ layer: CALayer, key: String, path: String, from: Any, to: Any) {
                let animation = CABasicAnimation(keyPath: path)
                animation.fromValue = from
                animation.toValue = to
                animation.beginTime = layer.convertTime(begin, from: nil)
                animation.duration = duration
                animation.fillMode = .backwards
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                layer.add(animation, forKey: key)
            }
            tile.opacity = 1
            animateProgress(tile, key: "highlight", path: "opacity", from: progress, to: 1)

            if let mask = tile.mask as? CAGradientLayer {
                mask.locations = featherLocations(1)
                animateProgress(mask, key: "highlightFeather", path: "locations",
                                from: featherLocations(progress), to: featherLocations(1))
            }
            tile.transform = CATransform3DMakeTranslation(0, -1.6, 0)
            animateProgress(tile, key: "highlightLift", path: "transform.translation.y", from: lift, to: -1.6)
            if let hdr {
                hdr.opacity = 1
                animateProgress(hdr, key: "highlightGain", path: "opacity", from: progress, to: 1)
            }
        }
    }

    private func scheduleFlow(elapsed: TimeInterval, running: Bool, host: TimeInterval) {
        guard let flowGradient, let raster else { return }
        let width = CGFloat(raster.width) / raster.scale
        let flowElapsed = reduceMotion ? (line?.time ?? 0) : elapsed
        let playing = running && !isHiddenOrHasHiddenAncestor
        for tile in highlights {
            flowGradient.animate(tile, tileFrame: tile.frame, rowWidth: width, elapsed: flowElapsed,
                                 running: playing, host: host)
            if let hdr = hdrLayer(for: tile) {
                flowGradient.animate(hdr, tileFrame: tile.frame, rowWidth: width, elapsed: flowElapsed,
                                     running: playing, host: host)
            }
        }
    }
}

/// One row's glyph atlas and character geometry, shared by normal and EDR tiles.
struct LyricRaster {
    private(set) var pixels = [UInt8]()
    let width: Int
    let height: Int
    let scale: CGFloat
    private let text: CTLine
    private let origin: CGFloat
    init?(line: String, font: NSFont, size: CGSize, scale: CGFloat, centered: Bool) {
        width = max(1, Int(ceil(size.width * scale))); height = max(1, Int(ceil(size.height * scale)))
        self.scale = scale
        let value = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.white])
        text = CTLineCreateWithAttributedString(value)
        var asc: CGFloat = 0, desc: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(text, &asc, &desc, nil))
        origin = centered ? max(3, (size.width - textWidth) / 2) : 3
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.scaleBy(x: scale, y: scale)
            context.textPosition = CGPoint(x: origin, y: (size.height - asc - desc) / 2 + desc)
            CTLineDraw(text, context)
            return true
        }
        guard drawn else { return nil }
        pixels = buffer
    }
    func rect(for range: NSRange) -> CGRect {
        let a = CTLineGetOffsetForStringIndex(text, range.location, nil)
        let b = CTLineGetOffsetForStringIndex(text, NSMaxRange(range), nil)
        return CGRect(x: origin + min(a, b), y: 0, width: abs(b - a), height: CGFloat(height) / scale)
    }
    func image(color: NSColor, gain: CGFloat) -> CGImage? {
        let alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        if gain <= 1 {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let rgb = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            let red = min(1, max(0, rgb.redComponent))
            let green = min(1, max(0, rgb.greenComponent))
            let blue = min(1, max(0, rgb.blueComponent))
            var bytes = pixels
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = CGFloat(bytes[i + 3])
                guard alpha > 0 else { continue }
                bytes[i] = UInt8((red * alpha).rounded())
                bytes[i + 1] = UInt8((green * alpha).rounded())
                bytes[i + 2] = UInt8((blue * alpha).rounded())
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: space, bitmapInfo: [alphaInfo, .byteOrder32Big], provider: provider,
                           decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }

        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let linearSpace = NSColorSpace(cgColorSpace: space),
              let linear = color.usingColorSpace(linearSpace) else { return nil }
        let red = Float(linear.redComponent * gain)
        let green = Float(linear.greenComponent * gain)
        let blue = Float(linear.blueComponent * gain)
        var values = [Float16](repeating: 0, count: pixels.count)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Float(pixels[i + 3]) / 255
            values[i] = Float16(red * alpha)
            values[i + 1] = Float16(green * alpha)
            values[i + 2] = Float16(blue * alpha)
            values[i + 3] = Float16(alpha)
        }
        let data = values.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(headroom: Float(gain), width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                       bytesPerRow: width * 8, space: space, bitmapInfo: [alphaInfo, .floatComponents, .byteOrder16Little],
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
