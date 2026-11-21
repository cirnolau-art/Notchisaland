import AppKit
import QuartzCore

final class LyricRollView: FlippedView {
    enum Layout { case compact, below, side }
    private let placement: Layout
    private let incoming = LyricTextView(frame: .zero)
    private let upcoming = LyricTextView(frame: .zero)
    private let outgoing = LyricTextView(frame: .zero)
    private var currentLine: LyricLine?
    private var nextLine: LyricLine?
    private var lyricAppearance = LyricsAppearance()
    private var style: LyricsAnimationStyle?
    private var scrollGeneration = 0
    private var laidOutSize = CGSize.zero
    private var rowHeight: CGFloat {
        let font = lyricFont(for: lyricAppearance)
        return ceil(font.ascender - font.descender + font.leading) + 8
    }
    private var step: CGFloat { rowHeight + (placement == .side ? 8 : 3) }
    var hasScrollAnimation: Bool { incoming.layer?.animation(forKey: "lyricScroll") != nil }
    var isCompact: Bool { placement == .compact }
    var fittingWidth: CGFloat { max(0, bounds.width - 8) }
    var linesPerRow: Int { 1 }
    func lyricFont(for appearance: LyricsAppearance) -> NSFont {
        let increase: CGFloat = placement == .side ? 6 : (placement == .below ? 4 : 0)
        return .systemFont(ofSize: appearance.size + increase, weight: appearance.weight.fontWeight)
    }
    init(frame: CGRect, placement: Layout) {
        self.placement = placement
        super.init(frame: frame)
        wantsLayer = true
        // Keep EDR glyphs in the window's compositing path during fades.
        layer?.allowsGroupOpacity = false
        layer?.masksToBounds = true
        for row in [outgoing, upcoming, incoming] { addSubview(row) }
        outgoing.isHidden = true; outgoing.setAccessibilityElement(false)
        upcoming.isHidden = placement == .compact
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setGlassContrast(_ enabled: Bool) {
        for row in [incoming, upcoming, outgoing] { row.setGlassContrast(enabled) }
    }
    override func layout() {
        super.layout()
        laidOutSize = bounds.size
        let height = placement == .compact ? bounds.height : rowHeight
        let row = CGRect(x: 0, y: placement == .compact ? 0 : 4, width: bounds.width, height: height)
        let nextRow = row.offsetBy(dx: 0, dy: step)
        if incoming.frame != row { incoming.frame = row }
        if upcoming.frame != nextRow { upcoming.frame = nextRow }
        if outgoing.frame != row { outgoing.frame = row }
    }
    func update(current: LyricLine?, next: LyricLine?, elapsed: TimeInterval, style: LyricsAnimationStyle,
                appearance: LyricsAppearance, animated: Bool, running: Bool = true, flowPalette: LyricFlowPalette = .rgb) {
        let changed = currentLine != current
        let layoutChanged = laidOutSize != bounds.size || self.lyricAppearance.size != appearance.size
            || self.lyricAppearance.weight != appearance.weight
        self.lyricAppearance = appearance
        if layoutChanged { needsLayout = true; layoutSubtreeIfNeeded() }
        let roll = animated && !layoutChanged && self.style == style && changed && current != nil && current == nextLine
        var carry: CGFloat = 0
        if roll, let layer = incoming.layer, let visible = layer.presentation() { carry = visible.position.y - layer.position.y }
        if changed || layoutChanged || self.style != style { resetScroll() }
        if roll && currentLine != nil {
            outgoing.isHidden = false; outgoing.copyPresentation(from: incoming)
        }
        incoming.update(line: current, next: next?.time, elapsed: elapsed, style: style, appearance: lyricAppearance,
                        font: lyricFont(for: lyricAppearance), active: true, centered: placement != .side,
                        running: running, flowPalette: flowPalette, compact: placement == .compact)
        if placement != .compact {
            upcoming.update(line: next, next: nil, elapsed: elapsed, style: style, appearance: appearance,
                            font: lyricFont(for: appearance), active: false, centered: placement != .side, running: false)
        }
        currentLine = current; nextLine = next; self.style = style
        if roll {
            let preferred = style == .appleMusic ? 0.36 : 0.22
            let duration = next.map { min(preferred, max(0, ($0.time - elapsed) * 0.75)) } ?? preferred
            if duration >= 1.0 / 60 { scroll(duration: duration, carry: carry) }
            else { outgoing.isHidden = true }
        }
    }
    func suspend(release: Bool = false) {
        if release { resetScroll() }
        for row in [incoming, upcoming, outgoing] { row.suspend(release: release) }
    }
    func reset() {
        guard style != nil else { return }
        suspend(release: true); currentLine = nil; nextLine = nil; style = nil
        incoming.update(line: nil, next: nil, elapsed: 0, style: .efficient, appearance: lyricAppearance,
                        font: lyricFont(for: lyricAppearance), active: false, centered: true, running: false)
        upcoming.update(line: nil, next: nil, elapsed: 0, style: .efficient, appearance: lyricAppearance,
                        font: lyricFont(for: lyricAppearance), active: false, centered: true, running: false)
    }
    private func resetScroll() {
        scrollGeneration += 1
        for row in [incoming, upcoming, outgoing] {
            row.layer?.removeAnimation(forKey: "lyricScroll")
            row.layer?.removeAnimation(forKey: "lyricScrollOpacity")
        }
        outgoing.isHidden = true
    }
    private func scroll(duration: TimeInterval, carry: CGFloat) {
        let offset = convertToLayer(CGPoint(x: 0, y: step)).y - convertToLayer(CGPoint.zero).y
        func move(_ row: LyricTextView, from: CGFloat, to: CGFloat, hold: Bool = false) {
            let motion = CABasicAnimation(keyPath: "position.y")
            motion.isAdditive = true; motion.fromValue = from; motion.toValue = to; motion.duration = duration
            motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.20, 1)
            if hold { motion.fillMode = .forwards; motion.isRemovedOnCompletion = false }
            row.layer?.add(motion, forKey: "lyricScroll")
        }
        func fade(_ row: LyricTextView, from: Float, to: Float, hold: Bool = false) {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from; animation.toValue = to; animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: hold ? .easeOut : .easeIn)
            if hold { animation.fillMode = .forwards; animation.isRemovedOnCompletion = false }
            row.layer?.add(animation, forKey: "lyricScrollOpacity")
        }
        move(incoming, from: offset + carry, to: 0)
        if placement != .compact {
            move(upcoming, from: offset + carry, to: 0)
            fade(upcoming, from: 0, to: 1)
        }
        if !outgoing.isHidden {
            let generation = scrollGeneration
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.scrollGeneration == generation else { return }
                self.outgoing.isHidden = true; self.outgoing.suspend(release: true)
            }
            move(outgoing, from: carry, to: -offset, hold: true)
            fade(outgoing, from: 1, to: 0, hold: true)
            CATransaction.commit()
        }
    }
}

final class CompactLyricsView: NSView {
    let roll = LyricRollView(frame: .zero, placement: .compact)
    var rightBackground = true {
        didSet { if oldValue != rightBackground { needsDisplay = true } }
    }
    var lyricAppearance = LyricsAppearance() {
        didSet {
            guard oldValue != lyricAppearance else { return }
            needsDisplay = true
            needsLayout = true
        }
    }
    var sideExtension: CGFloat = 0 {
        didSet {
            guard oldValue != sideExtension else { return }
            needsDisplay = true
            needsLayout = true
        }
    }
    var placement: LyricsPlacement = .below {
        didSet {
            guard oldValue != placement else { return }
            needsDisplay = true
            needsLayout = true
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.allowsGroupOpacity = false
        addSubview(roll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func stripHeight(for appearance: LyricsAppearance) -> CGFloat {
        let font = NSFont.systemFont(ofSize: appearance.size, weight: appearance.weight.fontWeight)
        return ceil(font.ascender - font.descender + font.leading) + 8
    }
    override func layout() {
        super.layout()
        if placement == .side {
            roll.frame = CGRect(x: 16, y: 0, width: max(0, sideExtension - 24), height: bounds.height)
        } else {
            let width = min(lyricAppearance.width, max(0, bounds.width - 48))
            roll.frame = CGRect(x: bounds.midX - width / 2, y: 0, width: width, height: Self.stripHeight(for: lyricAppearance))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        guard w > 24, h > 0, lyricAppearance.opacity > 0 else { return }
        if placement == .side {
            guard sideExtension > 0, let context = NSGraphicsContext.current?.cgContext,
                  let gradient = NSGradient(colors: [
                      .clear, NSColor.black.withAlphaComponent(lyricAppearance.opacity * 0.64),
                      NSColor.black.withAlphaComponent(lyricAppearance.opacity), .black
                  ], atLocations: [0, 0.32, 0.84, 1], colorSpace: .deviceRGB) else { return }
            let reach = sideExtension + 16
            let wing = NSBezierPath()
            wing.move(to: CGPoint(x: 0, y: h))
            wing.line(to: CGPoint(x: reach, y: h))
            wing.line(to: CGPoint(x: reach, y: 0))
            wing.line(to: CGPoint(x: min(15, reach), y: 0))
            wing.curve(to: CGPoint(x: 0, y: h), controlPoint1: CGPoint(x: min(4, reach), y: 0),
                       controlPoint2: CGPoint(x: 0, y: h * 0.45))
            wing.close()
            for mirrored in [false, true] where !mirrored || rightBackground {
                context.saveGState()
                if mirrored { context.translateBy(x: w, y: 0); context.scaleBy(x: -1, y: 1) }
                wing.addClip()
                gradient.draw(from: .zero, to: CGPoint(x: reach, y: 0), options: [])
                context.restoreGState()
            }
            return
        }
        let path = NSBezierPath()
        let shoulder = min(h, 32)
        path.move(to: NSPoint(x: 0, y: shoulder))
        path.line(to: NSPoint(x: 0, y: h))
        path.line(to: NSPoint(x: w, y: h))
        path.line(to: NSPoint(x: w, y: shoulder))
        path.curve(to: NSPoint(x: w - 25, y: 0), controlPoint1: NSPoint(x: w, y: 12),
                   controlPoint2: NSPoint(x: w - 7, y: 0))
        path.line(to: NSPoint(x: 25, y: 0))
        path.curve(to: NSPoint(x: 0, y: shoulder), controlPoint1: NSPoint(x: 7, y: 0),
                   controlPoint2: NSPoint(x: 0, y: 12))
        path.close()
        NSColor.black.withAlphaComponent(lyricAppearance.opacity).setFill()
        path.fill()
    }
}
