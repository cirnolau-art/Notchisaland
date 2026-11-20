import AppKit
import QuartzCore

final class LyricRollView: FlippedView {
    enum Layout {
        case compact, below, side

        var rowHeight: CGFloat {
            switch self {
            case .compact: return 20
            case .below: return 24
            case .side: return 48
            }
        }

        var step: CGFloat {
            switch self {
            case .compact: return 20
            case .below: return 25
            case .side: return 51
            }
        }
    }

    private let placement: Layout
    private let incoming = NSTextField(labelWithString: "")
    private let upcoming = NSTextField(labelWithString: "")
    private let outgoing = NSTextField(labelWithString: "")
    private var currentLine: LyricLine?
    private var nextLine: LyricLine?
    private var highlighted = 0
    private var animationStyle: LyricsAnimationStyle?
    private var lyricAppearance = LyricsAppearance()
    private var scrollGeneration = 0
    var hasScrollAnimation: Bool { incoming.layer?.animation(forKey: "lyricScroll") != nil }
    var isCompact: Bool { placement == .compact }
    var fittingWidth: CGFloat { max(0, bounds.width - 6) }
    var linesPerRow: Int { placement == .side ? 2 : 1 }
    func lyricFont(for appearance: LyricsAppearance) -> NSFont {
        let increase: CGFloat = placement == .side ? 6 : (placement == .below ? 4 : 0)
        return .systemFont(ofSize: appearance.size + increase, weight: appearance.weight.fontWeight)
    }

    init(frame: CGRect, placement: Layout) {
        self.placement = placement
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for field in [outgoing, upcoming, incoming] {
            field.wantsLayer = true
            field.alignment = placement == .side ? .natural : .center
            field.maximumNumberOfLines = placement == .side ? 2 : 1
            field.cell?.wraps = placement == .side
            field.lineBreakMode = .byTruncatingTail
            if placement == .compact { field.allowsDefaultTighteningForTruncation = true }
            addSubview(field)
        }
        outgoing.isHidden = true
        outgoing.setAccessibilityElement(false)
        upcoming.isHidden = placement == .compact
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let y = placement == .compact ? (bounds.height - placement.rowHeight) / 2 : 0
        let row = CGRect(x: 0, y: y, width: bounds.width, height: placement.rowHeight)
        incoming.frame = row
        upcoming.frame = row.offsetBy(dx: 0, dy: placement.step)
        outgoing.frame = row
    }

    func update(current: LyricLine?, next: LyricLine?, elapsed: TimeInterval, style: LyricsAnimationStyle,
                appearance: LyricsAppearance, animated: Bool) {
        let count = style == .appleMusic ? current?.segments.prefix(while: { $0.time <= elapsed }).count ?? 0 : 0
        let lineChanged = currentLine != current
        let nextChanged = nextLine != next
        let styleChanged = animationStyle != style || lyricAppearance != appearance
        lyricAppearance = appearance
        let roll = animated && !styleChanged && lineChanged && current != nil && current == nextLine
        // Preserve the visible row positions when another cue arrives mid-scroll.
        var carry: CGFloat = 0
        if roll, hasScrollAnimation, let layer = incoming.layer, let visible = layer.presentation() {
            carry = visible.position.y - layer.position.y
        }
        if styleChanged || lineChanged || (hasScrollAnimation && !animated) { resetScroll() }
        if roll && currentLine != nil {
            outgoing.attributedStringValue = incoming.attributedStringValue
            outgoing.isHidden = false
        }
        if lineChanged || count != highlighted || styleChanged {
            incoming.layer?.removeAnimation(forKey: "wordHighlight")
            let previousCount = lineChanged ? 0 : highlighted
            if animated, style == .appleMusic, !styleChanged, !lineChanged || roll,
               count == previousCount + 1, let current {
                let segment = current.segments[count - 1]
                let following = current.segments.dropFirst(count).first?.time ?? next?.time
                let end = [segment.endTime, following].compactMap { $0 }.min() ?? segment.time + 0.34
                let duration = min(0.24, max(0, end - segment.time) * 0.78) - max(0, elapsed - segment.time)
                if duration > 1.0 / 60 {
                    // The previous frame of a promoted row belongs to another line.
                    if lineChanged {
                        incoming.attributedStringValue = text(current, highlighted: 0, active: true, style: style)
                        incoming.displayIfNeeded()
                    }
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = duration
                    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    incoming.layer?.add(fade, forKey: "wordHighlight")
                }
            }
            incoming.attributedStringValue = text(current, highlighted: count, active: true, style: style)
        } else if !animated {
            incoming.layer?.removeAnimation(forKey: "wordHighlight")
        }
        if placement != .compact, nextChanged || styleChanged {
            upcoming.attributedStringValue = text(next, highlighted: 0, active: false, style: style)
        }
        currentLine = current
        nextLine = next
        highlighted = count
        animationStyle = style
        if roll {
            let preferred = style == .appleMusic ? 0.31 : 0.19
            let duration = next.map { min(preferred, max(0, ($0.time - elapsed) * 0.8)) } ?? preferred
            if duration >= 1.0 / 60 { scroll(duration: duration, carry: carry) }
            else { outgoing.isHidden = true }
        }
    }

    func reset() {
        resetScroll()
        incoming.layer?.removeAnimation(forKey: "wordHighlight")
        currentLine = nil
        nextLine = nil
        animationStyle = nil
        incoming.stringValue = ""
        upcoming.stringValue = ""
    }

    private func text(_ line: LyricLine?, highlighted: Int, active: Bool, style: LyricsAnimationStyle) -> NSAttributedString {
        guard let line else { return NSAttributedString() }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = placement == .side ? .natural : .center
        paragraph.lineBreakMode = .byTruncatingTail
        let timed = active && style == .appleMusic && !line.segments.isEmpty
        let color = lyricAppearance.color
        let foreground = color.withAlphaComponent(active && !timed ? 0.97 : 0.44)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: lyricFont(for: lyricAppearance),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let rendered = NSMutableAttributedString(string: line.text, attributes: attributes)
        if active {
            let length = timed ? line.segments.prefix(highlighted).reduce(0) { $0 + $1.text.utf16.count } : rendered.length
            let range = NSRange(location: 0, length: min(length, rendered.length))
            if range.length > 0 {
                rendered.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.98), range: range)
                if lyricAppearance.glow > 0 {
                    let shadow = NSShadow()
                    shadow.shadowColor = color.withAlphaComponent(lyricAppearance.glow * 0.9)
                    shadow.shadowBlurRadius = 2 + 6 * lyricAppearance.glow
                    shadow.shadowOffset = .zero
                    rendered.addAttribute(.shadow, value: shadow, range: range)
                }
            }
        }
        return rendered
    }

    private func resetScroll() {
        scrollGeneration += 1
        for field in [incoming, upcoming, outgoing] { field.layer?.removeAnimation(forKey: "lyricScroll") }
        outgoing.isHidden = true
    }

    private func scroll(duration: TimeInterval, carry: CGFloat) {
        layoutSubtreeIfNeeded()
        // Sublayer positions are in the parent layer's local coordinates.
        let offset = convertToLayer(CGPoint(x: 0, y: placement.step)).y - convertToLayer(CGPoint.zero).y
        func move(_ field: NSTextField, from: CGFloat, to: CGFloat) {
            let motion = CABasicAnimation(keyPath: "position.y")
            motion.isAdditive = true
            motion.fromValue = from
            motion.toValue = to
            motion.duration = duration
            motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
            field.layer?.add(motion, forKey: "lyricScroll")
        }
        move(incoming, from: offset + carry, to: 0)
        if placement != .compact { move(upcoming, from: offset + carry, to: 0) }
        if !outgoing.isHidden {
            let generation = scrollGeneration
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.scrollGeneration == generation else { return }
                self.outgoing.isHidden = true
            }
            // Keep the outgoing row outside the viewport until the completion hides it.
            let motion = CABasicAnimation(keyPath: "position.y")
            motion.isAdditive = true
            motion.fromValue = carry
            motion.toValue = -offset
            motion.duration = duration
            motion.fillMode = .forwards
            motion.isRemovedOnCompletion = false
            motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
            outgoing.layer?.add(motion, forKey: "lyricScroll")
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
        addSubview(roll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if placement == .side {
            roll.frame = CGRect(x: 16, y: bounds.midY - 10, width: max(0, sideExtension - 24), height: 20)
        } else {
            let width = min(lyricAppearance.width, max(0, bounds.width - 48))
            roll.frame = CGRect(x: bounds.midX - width / 2, y: 2, width: width, height: 20)
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
            wing.line(to: CGPoint(x: 15, y: 0))
            wing.curve(to: CGPoint(x: 0, y: h), controlPoint1: CGPoint(x: 4, y: 0),
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
        path.move(to: NSPoint(x: 0, y: min(h, 32)))
        path.line(to: NSPoint(x: 0, y: h))
        path.line(to: NSPoint(x: w, y: h))
        path.line(to: NSPoint(x: w, y: 32))
        path.curve(to: NSPoint(x: w - 25, y: 0), controlPoint1: NSPoint(x: w, y: 12),
                   controlPoint2: NSPoint(x: w - 7, y: 0))
        path.line(to: NSPoint(x: 25, y: 0))
        path.curve(to: NSPoint(x: 0, y: 32), controlPoint1: NSPoint(x: 7, y: 0),
                   controlPoint2: NSPoint(x: 0, y: 12))
        path.close()
        NSColor.black.withAlphaComponent(lyricAppearance.opacity).setFill()
        path.fill()
    }
}
