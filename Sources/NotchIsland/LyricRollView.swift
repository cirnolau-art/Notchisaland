import AppKit
import QuartzCore

final class LyricRollView: FlippedView {
    enum Layout { case compact, below, side }
    private let placement: Layout
    private let incoming = LyricTextView(frame: .zero)
    private let upcoming = LyricTextView(frame: .zero)
    private let outgoing = LyricTextView(frame: .zero)
    private let farUpcoming = LyricTextView(frame: .zero)
    private var previousRow: LyricTextView
    private var currentRow: LyricTextView
    private var nextRow: LyricTextView
    private var nextNextRow: LyricTextView
    private var beforePreviousLine: LyricLine?
    private var previousLine: LyricLine?
    private var currentLine: LyricLine?
    private var nextLine: LyricLine?
    private var nextNextLine: LyricLine?
    private var lyricAppearance = LyricsAppearance()
    private var style: LyricsAnimationStyle?
    private var scrollGeneration = 0
    private var laidOutSize = CGSize.zero
    private var rowHeight: CGFloat {
        Self.rowHeight(for: lyricFont(for: lyricAppearance))
    }
    private var step: CGFloat { rowHeight + Self.rowSpacing(placement) }
    var hasScrollAnimation: Bool {
        [incoming, upcoming, outgoing, farUpcoming].contains { $0.layer?.animation(forKey: "lyricScroll") != nil }
    }
    var isCompact: Bool { placement == .compact }
    var fittingWidth: CGFloat { max(0, bounds.width - 8) }
    var linesPerRow: Int { 1 }
    func lyricFont(for appearance: LyricsAppearance) -> NSFont {
        Self.lyricFont(for: appearance, placement: placement)
    }
    static func expandedHeight(for appearance: LyricsAppearance, placement: Layout) -> CGFloat {
        4 * rowHeight(for: lyricFont(for: appearance, placement: placement)) + 3 * rowSpacing(placement) + 8
    }
    private static func lyricFont(for appearance: LyricsAppearance, placement: Layout) -> NSFont {
        let increase: CGFloat = placement == .side ? 6 : (placement == .below ? 4 : 0)
        return .systemFont(ofSize: appearance.size + increase, weight: appearance.weight.fontWeight)
    }
    private static func rowHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading) + 8
    }
    private static func rowSpacing(_ placement: Layout) -> CGFloat { placement == .side ? 8 : 3 }
    init(frame: CGRect, placement: Layout) {
        self.placement = placement
        previousRow = outgoing
        currentRow = incoming
        nextRow = upcoming
        nextNextRow = farUpcoming
        super.init(frame: frame)
        wantsLayer = true
        // Keep EDR glyphs in the window's compositing path during fades.
        layer?.allowsGroupOpacity = false
        layer?.masksToBounds = true
        for row in [outgoing, upcoming, incoming, farUpcoming] { addSubview(row) }
        outgoing.isHidden = true; outgoing.setAccessibilityElement(false)
        upcoming.isHidden = placement == .compact
        farUpcoming.isHidden = placement == .compact
        incoming.setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setGlassContrast(_ enabled: Bool) {
        for row in [incoming, upcoming, outgoing, farUpcoming] { row.setGlassContrast(enabled) }
    }
    override func layout() {
        super.layout()
        laidOutSize = bounds.size
        place(currentRow, slot: 0)
        place(previousRow, slot: placement == .compact ? 0 : -1)
        place(nextRow, slot: placement == .compact ? 0 : 1)
        place(nextNextRow, slot: placement == .compact ? 0 : 2)
    }
    func update(current: LyricLine?, next: LyricLine?, elapsed: TimeInterval, style: LyricsAnimationStyle,
                appearance: LyricsAppearance, animated: Bool, running: Bool = true, flowPalette: LyricFlowPalette = .rgb) {
        update(previous: previousLine ?? currentLine, current: current, next: next, nextNext: nextNextLine,
               elapsed: elapsed, style: style, appearance: appearance, animated: animated,
               running: running, flowPalette: flowPalette)
    }

    func update(previous: LyricLine?, current: LyricLine?, next: LyricLine?, nextNext: LyricLine?,
                elapsed: TimeInterval, style: LyricsAnimationStyle,
                appearance: LyricsAppearance, animated: Bool, running: Bool = true,
                flowPalette: LyricFlowPalette = .rgb) {
        let oldCurrent = currentLine
        let oldNext = nextLine
        let oldPrevious = previousLine
        let changed = oldCurrent != current
        let layoutChanged = laidOutSize != bounds.size || self.lyricAppearance.size != appearance.size
            || self.lyricAppearance.weight != appearance.weight
        self.lyricAppearance = appearance
        if layoutChanged { needsLayout = true; layoutSubtreeIfNeeded() }
        let styleChanged = self.style != style
        let canAnimate = animated && !layoutChanged && !styleChanged && changed && oldCurrent != nil && current != nil
        let direction: LyricRollDirection?
        if canAnimate, current == oldNext {
            direction = .forward
        } else if canAnimate, current == oldPrevious {
            direction = .backward
        } else {
            direction = nil
        }

        if let direction {
            transition(previous: previous, current: current, next: next, nextNext: nextNext,
                       elapsed: elapsed, style: style, appearance: lyricAppearance,
                       running: running, flowPalette: flowPalette, direction: direction)
            previousLine = previous
            currentLine = current
            nextLine = next
            nextNextLine = nextNext
        } else {
            previousLine = previous
            currentLine = current
            nextLine = next
            nextNextLine = nextNext
            if changed || layoutChanged || styleChanged { resetScroll() }
            updateRows(previous: previous, current: current, next: next, nextNext: nextNext,
                       elapsed: elapsed, style: style,
                       appearance: lyricAppearance, running: running, flowPalette: flowPalette)
            arrangeRowsImmediately()
        }
        self.style = style
    }
    func suspend(release: Bool = false) {
        if release { resetScroll() }
        for row in [incoming, upcoming, outgoing, farUpcoming] { row.suspend(release: release) }
    }
    func reset() {
        guard style != nil else { return }
        suspend(release: true)
        currentLine = nil; nextLine = nil; nextNextLine = nil; beforePreviousLine = nil; previousLine = nil; style = nil
        for row in [incoming, upcoming, outgoing, farUpcoming] {
            row.update(line: nil, next: nil, elapsed: 0, style: .efficient, appearance: lyricAppearance,
                       font: lyricFont(for: lyricAppearance), active: false, centered: true, running: false)
            row.setRollPresentation(alpha: 0, blurRadius: 0)
            row.isHidden = true
        }
        currentRow = incoming; nextRow = upcoming; previousRow = outgoing; nextNextRow = farUpcoming
        currentRow.isHidden = false
        nextRow.isHidden = placement == .compact
        nextNextRow.isHidden = placement == .compact
    }
    private func resetScroll() {
        scrollGeneration += 1
        for row in [incoming, upcoming, outgoing, farUpcoming] {
            row.layer?.removeAnimation(forKey: "lyricScroll")
            row.layer?.removeAnimation(forKey: "lyricScrollOpacity")
            row.setRollPresentation(alpha: 1, blurRadius: 0)
        }
        previousRow.isHidden = true
        nextRow.isHidden = placement == .compact
        nextNextRow.isHidden = placement == .compact
    }

    private func updateRows(previous: LyricLine?, current: LyricLine?, next: LyricLine?, nextNext: LyricLine?,
                            elapsed: TimeInterval, style: LyricsAnimationStyle, appearance: LyricsAppearance,
                            running: Bool, flowPalette: LyricFlowPalette) {
        currentRow.update(line: current, next: next?.time, elapsed: elapsed, style: style, appearance: appearance,
                          font: lyricFont(for: appearance), active: current != nil, centered: placement != .side,
                          running: running, flowPalette: flowPalette, compact: placement == .compact)
        if placement != .compact {
            nextRow.update(line: next, next: nil, elapsed: elapsed, style: style, appearance: appearance,
                           font: lyricFont(for: appearance), active: false, centered: placement != .side,
                          running: false, flowPalette: flowPalette)
            previousRow.update(line: previous, next: nil, elapsed: elapsed, style: style, appearance: appearance,
                              font: lyricFont(for: appearance), active: false, centered: placement != .side,
                              running: false, flowPalette: flowPalette)
            nextNextRow.update(line: nextNext, next: nil, elapsed: elapsed, style: style, appearance: appearance,
                               font: lyricFont(for: appearance), active: false, centered: placement != .side,
                               running: false, flowPalette: flowPalette)
        }
    }

    private func transition(previous: LyricLine?, current: LyricLine?, next: LyricLine?, nextNext: LyricLine?,
                            elapsed: TimeInterval, style: LyricsAnimationStyle, appearance: LyricsAppearance,
                            running: Bool, flowPalette: LyricFlowPalette, direction: LyricRollDirection) {
        if placement == .compact {
            transitionCompact(to: current, next: next, elapsed: elapsed, style: style,
                              appearance: appearance, running: running, flowPalette: flowPalette,
                              direction: direction)
            return
        }
        guard placement != .compact, let current else {
            updateRows(previous: previous, current: current, next: next, nextNext: nextNext,
                       elapsed: elapsed, style: style, appearance: appearance,
                       running: running, flowPalette: flowPalette)
            arrangeRowsImmediately()
            return
        }

        let snapshot = [incoming, upcoming, outgoing, farUpcoming].reduce(into: [ObjectIdentifier: (CGFloat, Float)]()) { result, row in
            result[ObjectIdentifier(row)] = presentation(for: row)
            row.layer?.removeAnimation(forKey: "lyricScroll")
            row.layer?.removeAnimation(forKey: "lyricScrollOpacity")
        }
        let oldCurrentRow = currentRow
        let oldPreviousRow = previousRow
        let oldNextRow = nextRow
        let oldNextNextRow = nextNextRow

        if direction == .forward {
            previousRow = oldCurrentRow
            currentRow = oldNextRow
            nextRow = oldNextNextRow
            nextNextRow = oldPreviousRow
        } else {
            previousRow = oldNextNextRow
            currentRow = oldPreviousRow
            nextRow = oldCurrentRow
            nextNextRow = oldNextRow
        }

        updateRows(previous: previous, current: current, next: next, nextNext: nextNext,
                   elapsed: elapsed, style: style, appearance: appearance,
                   running: running, flowPalette: flowPalette)

        let duration = LyricRollPolicy.transitionDuration(style: style)
        let previousTarget = LyricRollPolicy.state(distance: 1, direction: .backward, step: step)
        let nextTarget = LyricRollPolicy.state(distance: 1, direction: .forward, step: step)
        let farTarget = LyricRollPolicy.state(distance: 2, direction: .forward, step: step)
        let currentTarget = LyricRollPolicy.state(distance: 0, direction: direction, step: step)
        animate(previousRow, from: snapshot[ObjectIdentifier(previousRow)] ?? presentation(for: previousRow),
                toSlot: -1, target: previous == nil ? .init(alpha: 0, blurRadius: 0, offset: 0) : previousTarget,
                duration: duration)
        animate(currentRow, from: snapshot[ObjectIdentifier(currentRow)] ?? presentation(for: currentRow),
                toSlot: 0, target: currentTarget, duration: duration)
        animate(nextRow, from: snapshot[ObjectIdentifier(nextRow)] ?? presentation(for: nextRow),
                toSlot: 1, target: next == nil ? .init(alpha: 0, blurRadius: 0, offset: 0) : nextTarget,
                duration: duration)
        animate(nextNextRow, from: snapshot[ObjectIdentifier(nextNextRow)] ?? presentation(for: nextNextRow),
                toSlot: 2, target: nextNext == nil ? .init(alpha: 0, blurRadius: 0, offset: 0) : farTarget,
                duration: duration)
        previousRow.isHidden = previous == nil
        currentRow.isHidden = false
        nextRow.isHidden = next == nil
        nextNextRow.isHidden = nextNext == nil
    }

    private func transitionCompact(to current: LyricLine?, next: LyricLine?, elapsed: TimeInterval,
                                   style: LyricsAnimationStyle, appearance: LyricsAppearance,
                                   running: Bool, flowPalette: LyricFlowPalette, direction: LyricRollDirection) {
        guard let current else {
            updateRows(previous: nil, current: nil, next: nil, nextNext: nil,
                       elapsed: elapsed, style: style, appearance: appearance,
                       running: false, flowPalette: flowPalette)
            arrangeRowsImmediately()
            return
        }

        let oldCurrentRow = currentRow
        let oldPreviousRow = previousRow
        let oldNextRow = nextRow
        let oldCurrentLine = currentLine
        let snapshot = [incoming, upcoming, outgoing, farUpcoming].reduce(into: [ObjectIdentifier: (position: CGFloat, animated: Bool)]()) { result, row in
            let position = row.layer?.presentation()?.position.y ?? row.layer?.position.y ?? row.frame.midY
            let animated = row.layer?.animation(forKey: "lyricScroll") != nil
            result[ObjectIdentifier(row)] = (position, animated)
            row.layer?.removeAnimation(forKey: "lyricScroll")
            row.layer?.removeAnimation(forKey: "lyricScrollOpacity")
        }

        if direction == .forward {
            previousRow = oldCurrentRow
            currentRow = oldNextRow
            nextRow = oldPreviousRow
            previousLine = oldCurrentLine
            beforePreviousLine = nil

            previousRow.update(line: oldCurrentLine, next: nil, elapsed: elapsed, style: style,
                               appearance: appearance, font: lyricFont(for: appearance), active: false,
                               centered: true, running: false, flowPalette: flowPalette, compact: true)
            currentRow.update(line: current, next: next?.time, elapsed: elapsed, style: style,
                              appearance: appearance, font: lyricFont(for: appearance), active: true,
                              centered: true, running: running, flowPalette: flowPalette, compact: true)
            nextRow.update(line: nil, next: nil, elapsed: elapsed, style: style,
                           appearance: appearance, font: lyricFont(for: appearance), active: false,
                           centered: true, running: false, flowPalette: flowPalette, compact: true)
            previousRow.isHidden = oldCurrentLine == nil
            currentRow.isHidden = false
            nextRow.isHidden = true

            let target = currentRow.layer?.position.y ?? currentRow.frame.midY
            let outgoingStart = snapshot[ObjectIdentifier(previousRow)].map { $0.animated ? $0.position : target } ?? target
            let incomingStart = snapshot[ObjectIdentifier(currentRow)].map { $0.animated ? $0.position : target + step } ?? target + step
            animateCompact(previousRow, from: outgoingStart,
                           to: target - step, alpha: 0, duration: LyricRollPolicy.transitionDuration(style: style))
            animateCompact(currentRow, from: incomingStart,
                           to: target, alpha: 1, duration: LyricRollPolicy.transitionDuration(style: style))
        } else {
            nextRow = oldCurrentRow
            currentRow = oldPreviousRow
            previousRow = oldNextRow
            previousLine = beforePreviousLine
            beforePreviousLine = nil

            nextRow.update(line: oldCurrentLine, next: nil, elapsed: elapsed, style: style,
                           appearance: appearance, font: lyricFont(for: appearance), active: false,
                           centered: true, running: false, flowPalette: flowPalette, compact: true)
            currentRow.update(line: current, next: next?.time, elapsed: elapsed, style: style,
                              appearance: appearance, font: lyricFont(for: appearance), active: true,
                              centered: true, running: running, flowPalette: flowPalette, compact: true)
            previousRow.update(line: nil, next: nil, elapsed: elapsed, style: style,
                              appearance: appearance, font: lyricFont(for: appearance), active: false,
                              centered: true, running: false, flowPalette: flowPalette, compact: true)
            nextRow.isHidden = oldCurrentLine == nil
            currentRow.isHidden = false
            previousRow.isHidden = true

            let target = currentRow.layer?.position.y ?? currentRow.frame.midY
            let outgoingStart = snapshot[ObjectIdentifier(nextRow)].map { $0.animated ? $0.position : target } ?? target
            let incomingStart = snapshot[ObjectIdentifier(currentRow)].map { $0.animated ? $0.position : target - step } ?? target - step
            animateCompact(nextRow, from: outgoingStart,
                           to: target + step, alpha: 0, duration: LyricRollPolicy.transitionDuration(style: style))
            animateCompact(currentRow, from: incomingStart,
                           to: target, alpha: 1, duration: LyricRollPolicy.transitionDuration(style: style))
        }
    }

    private func arrangeRowsImmediately() {
        let current = LyricRollPolicy.state(distance: 0, direction: .forward, step: step)
        let next = LyricRollPolicy.state(distance: 1, direction: .forward, step: step)
        let farNext = LyricRollPolicy.state(distance: 2, direction: .forward, step: step)
        setFrame(currentRow, slot: 0); currentRow.setRollPresentation(alpha: current.alpha, blurRadius: current.blurRadius)
        if placement != .compact {
            setFrame(nextRow, slot: 1); nextRow.setRollPresentation(alpha: nextLine == nil ? 0 : next.alpha, blurRadius: nextLine == nil ? 0 : next.blurRadius)
            setFrame(nextNextRow, slot: 2); nextNextRow.setRollPresentation(alpha: nextNextLine == nil ? 0 : farNext.alpha, blurRadius: nextNextLine == nil ? 0 : farNext.blurRadius)
            setFrame(previousRow, slot: -1); previousRow.setRollPresentation(alpha: previousLine == nil ? 0 : next.alpha, blurRadius: previousLine == nil ? 0 : next.blurRadius)
            previousRow.isHidden = previousLine == nil
            nextRow.isHidden = nextLine == nil
            nextNextRow.isHidden = nextNextLine == nil
        }
        currentRow.isHidden = false
    }

    private func setFrame(_ row: LyricTextView, slot: Int) {
        let height = placement == .compact ? bounds.height : rowHeight
        // Keep all four expanded rows inside the lyric viewport. The current
        // row occupies slot 1, leaving slot 0 for the previous lyric instead
        // of clipping it above the container.
        let y = placement == .compact ? 0 : 4 + CGFloat(slot + 1) * step
        let frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        row.frame = frame
        CATransaction.commit()
    }

    private func place(_ row: LyricTextView, slot: Int) {
        guard row.frame.width != bounds.width || row.frame.height != (placement == .compact ? bounds.height : rowHeight)
                       || row.frame.minY != (placement == .compact ? 0 : 4 + CGFloat(slot + 1) * step) else { return }
        setFrame(row, slot: slot)
    }

    private func presentation(for row: LyricTextView) -> (CGFloat, Float) {
        let modelY = row.layer?.position.y ?? row.frame.midY
        let y = row.layer?.presentation()?.position.y ?? modelY
        let opacity = row.layer?.presentation()?.opacity ?? row.layer?.opacity ?? 1
        return (y, opacity)
    }

    private func animate(_ row: LyricTextView, from start: (CGFloat, Float), toSlot slot: Int,
                         target: LyricRollState, duration: TimeInterval) {
        setFrame(row, slot: slot)
        row.setRollPresentation(alpha: target.alpha, blurRadius: target.blurRadius)
        let targetY = row.layer?.position.y ?? row.frame.midY
        guard duration > 0.01 else { return }
        let motion = CABasicAnimation(keyPath: "position.y")
        motion.fromValue = start.0
        motion.toValue = targetY
        motion.duration = duration
        motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.20, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start.1
        fade.toValue = Float(target.alpha)
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        row.layer?.add(motion, forKey: "lyricScroll")
        row.layer?.add(fade, forKey: "lyricScrollOpacity")
    }

    private func animateCompact(_ row: LyricTextView, from start: CGFloat, to targetY: CGFloat,
                                alpha: CGFloat, duration: TimeInterval) {
        setFrame(row, slot: 0)
        row.setRollPresentation(alpha: alpha, blurRadius: 0)
        guard duration > 0.01 else { return }
        let motion = CABasicAnimation(keyPath: "position.y")
        motion.fromValue = start
        motion.toValue = targetY
        motion.duration = duration
        motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.20, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = alpha == 0 ? 1 : 0
        fade.toValue = Float(alpha)
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        row.layer?.add(motion, forKey: "lyricScroll")
        row.layer?.add(fade, forKey: "lyricScrollOpacity")
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
