import AppKit
import QuartzCore

struct MediaInfo {
    var title = ""
    var artist = ""
    var artwork: CGImage?
    var isPlaying = false
    var album = ""
    var dominantColor: CGColor?
    var duration: Double = 0
    var elapsed: Double = 0
    var source = ""
    var trackID = ""
    var sampledAt = Date()
    var lyrics: [LyricLine] = []
    var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
    func interpolated(at date: Date = Date()) -> MediaInfo {
        var result = self
        if isPlaying {
            let position = elapsed + max(0, date.timeIntervalSince(sampledAt))
            result.elapsed = duration > 0 ? min(duration, position) : position
            result.sampledAt = max(date, sampledAt)
        }
        return result
    }
}

enum IslandState {
    enum IdleContent {
        case time(String)
        case music(String, CGImage?, CGColor?, Bool)
        case timer(String)
    }
    case idle(IdleContent), volume(Double, Bool), brightness(Double), inputSource(String), charging(Bool, Int)
    case alarm(String), timerDone(String), music(MediaInfo), workspace(IslandTab, Bool)
    case airPods(AirPodsSnapshot), notification(IslandNotification)
}

enum IslandMetrics {
    static let white = NSColor.white.cgColor
    static let white55 = NSColor.white.withAlphaComponent(0.55).cgColor
}

private final class PassiveLabel: NSTextField { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
private final class PassiveImage: NSImageView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

private final class FocusBadgeView: NSView {
    private let light = CAGradientLayer()
    private let ring = CAShapeLayer()
    private let icon = PassiveImage()
    private var mode: SystemFocusMode?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        light.type = .conic
        light.startPoint = CGPoint(x: 0.5, y: 0.5); light.endPoint = CGPoint(x: 0.5, y: 1)
        light.colors = [NSColor.systemCyan, .systemBlue, .systemPurple, .systemPink, .systemOrange, .systemCyan].map(\.cgColor)
        ring.fillColor = nil; ring.strokeColor = NSColor.white.cgColor
        light.mask = ring; layer?.addSublayer(light)
        icon.imageScaling = .scaleProportionallyDown; addSubview(icon)
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        light.frame = bounds; ring.frame = bounds
        ring.lineWidth = max(1.5, bounds.width * 0.075)
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: ring.lineWidth / 2, dy: ring.lineWidth / 2), transform: nil)
        CATransaction.commit()
        let inset = bounds.width * (mode?.reducesInterruptions == true ? 0.20 : 0.08)
        icon.frame = bounds.insetBy(dx: inset, dy: inset)
    }
    func update(_ next: SystemFocusMode?, animated: Bool) {
        if mode != next {
            mode = next; isHidden = next == nil
            toolTip = next?.name; setAccessibilityLabel(next?.name)
            let symbol = next.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) } ?? NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)
            icon.image = symbol?.withSymbolConfiguration(.init(pointSize: bounds.width, weight: .medium))
            icon.contentTintColor = next?.reducesInterruptions == true ? .white : .systemIndigo.blended(withFraction: 0.42, of: .white)
            light.isHidden = next?.reducesInterruptions != true
            needsLayout = true
        }
        if animated, next?.reducesInterruptions == true, !IslandPreferences.shared.reduceMotion {
            if light.animation(forKey: "orbit") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = Double.pi * 2; spin.duration = 6; spin.repeatCount = .infinity
                light.add(spin, forKey: "orbit")
            }
        } else { light.removeAnimation(forKey: "orbit") }
    }
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ActionButton: NSButton {
    private var actionBlock: ((NSView) -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    var selected = false { didSet { needsDisplay = true } }
    var symbolSize: CGFloat = 14
    init(title: String = "", symbol: String? = nil, help: String, action: @escaping (NSView) -> Void) {
        super.init(frame: .zero)
        self.title = title; self.toolTip = help; actionBlock = action
        target = self; self.action = #selector(invoke)
        isBordered = false; bezelStyle = .regularSquare
        wantsLayer = true
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .white.withAlphaComponent(0.75)
        focusRingType = .none
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        setAccessibilityLabel(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { actionBlock?(self) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseDown(with event: NSEvent) {
        if !IslandPreferences.shared.reduceMotion {
            let press = CABasicAnimation(keyPath: "opacity"); press.fromValue = 1; press.toValue = 0.65; press.duration = 0.08; press.fillMode = .forwards; press.isRemovedOnCompletion = false
            layer?.add(press, forKey: "press")
        }
        super.mouseDown(with: event)
        layer?.removeAnimation(forKey: "press")
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let accent = LyricsAppearance.color(for: IslandPreferences.shared.accentRGB)
        let alpha: CGFloat = isHighlighted ? 0.17 : (selected ? 0.12 : (hovered ? 0.08 : 0))
        (selected ? accent.withAlphaComponent(alpha) : NSColor.white.withAlphaComponent(alpha)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: min(10, bounds.height / 2), yRadius: min(10, bounds.height / 2)).fill()
        let tint: NSColor = !isEnabled ? .white.withAlphaComponent(0.2) : (selected ? accent : .white.withAlphaComponent(hovered ? 1 : 0.9))
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: tint]
        let text = NSAttributedString(string: title, attributes: attributes)
        let textSize = text.size()
        let iconWidth: CGFloat = image == nil ? 0 : symbolSize
        let gap: CGFloat = image == nil || title.isEmpty ? 0 : 7
        let start = bounds.midX - (iconWidth + gap + textSize.width) / 2
        if let image {
            let tinted = image.withSymbolConfiguration(.init(paletteColors: [tint])) ?? image
            let ratio = min(iconWidth / max(1, tinted.size.width), iconWidth / max(1, tinted.size.height))
            let fitted = NSSize(width: tinted.size.width * ratio, height: tinted.size.height * ratio)
            tinted.draw(in: NSRect(x: start + (iconWidth - fitted.width) / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if !title.isEmpty { text.draw(at: NSPoint(x: start + iconWidth + gap, y: bounds.midY - textSize.height / 2)) }

    }
}

private final class IslandSliderCell: NSSliderCell {
    var showThumb = false
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
    override func drawKnob(_ knobRect: NSRect) {
        guard showThumb || isHighlighted else { return }
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 3, y: knobRect.midY - 3, width: 6, height: 6)).fill()
    }
}

final class InteractionSlider: NSSlider {
    private let trackLayer = CALayer()
    private let progressLayer = CALayer()
    private var animatesProgress = false
    private var trackingValue = false
    override var doubleValue: Double { didSet { updateProgress(animated: animatesProgress && !trackingValue) } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); cell = IslandSliderCell(); wantsLayer = true
        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        progressLayer.backgroundColor = NSColor.white.withAlphaComponent(0.82).cgColor
        trackLayer.cornerRadius = 1.5; progressLayer.cornerRadius = 1.5
        progressLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(trackLayer); layer?.addSublayer(progressLayer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func layout() { super.layout(); updateProgress(animated: false) }
    func setDisplayedValue(_ value: Double, animated: Bool) {
        animatesProgress = animated; doubleValue = value; animatesProgress = false
    }
    private func updateProgress(animated: Bool) {
        guard bounds.width > 0 else { return }
        let fraction = min(1, max(0, (doubleValue - minValue) / max(0.001, maxValue - minValue)))
        let previous = progressLayer.presentation()?.transform.m11 ?? progressLayer.transform.m11
        let rect = (cell as? NSSliderCell)?.barRect(flipped: isFlipped) ?? bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        trackLayer.frame = CGRect(x: rect.minX, y: bounds.midY - 1.5, width: rect.width, height: 3)
        progressLayer.bounds = CGRect(x: 0, y: 0, width: rect.width, height: 3)
        progressLayer.position = CGPoint(x: rect.minX, y: bounds.midY)
        progressLayer.transform = CATransform3DMakeScale(fraction, 1, 1)
        CATransaction.commit()
        progressLayer.removeAnimation(forKey: "progress")
        if animated && !IslandPreferences.shared.reduceMotion {
            let motion = CABasicAnimation(keyPath: "transform.scale.x")
            motion.fromValue = previous; motion.toValue = fraction; motion.duration = 0.12
            motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressLayer.add(motion, forKey: "progress")
        }
    }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { (cell as? IslandSliderCell)?.showThumb = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { (cell as? IslandSliderCell)?.showThumb = false; needsDisplay = true }
    var onInteraction: ((Bool) -> Void)?
    var onFinish: ((Double) -> Void)?
    override func mouseDown(with event: NSEvent) {
        trackingValue = true; progressLayer.removeAllAnimations()
        (cell as? IslandSliderCell)?.showThumb = true
        onInteraction?(true)
        super.mouseDown(with: event)
        onFinish?(doubleValue)
        trackingValue = false
        onInteraction?(false)
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        updateProgress(animated: false)
        return super.sendAction(action, to: target)
    }
}

/// One shape morphs between compact, preview, HUD and expanded states. All content stays below the physical notch.
final class IslandView: NSView {
    private let shape = CAShapeLayer()
    private let backdrop = IslandBackdropView(frame: .zero)
    var notificationPreviewOverride: Bool?
    private var showsNotificationPreview: Bool { notificationPreviewOverride ?? IslandPreferences.shared.notificationPreview }
    var backdropOverride: IslandBackdropConfiguration?
    private var backdropConfiguration: IslandBackdropConfiguration { backdropOverride ?? .current }
    private var airPodsCard: AirPodsConnectionView?
    var clipboard: ClipboardHistory?
    var enabledTabsOverride: [IslandTab]?
    private var visibleTabs: [IslandTab] { enabledTabsOverride ?? IslandPreferences.shared.visibleTabs }
    private var clipboardPanel: ClipboardPanelView?
    private var audioPanel: AudioPanelView?
    private var calendarPanel: CalendarPanelView?
    private var quickPanel: QuickActionsPanelView?
    var audioOutputs: [AudioOutput] = []
    var selectedOutput: UInt32 = 0
    var switchingOutput: UInt32?
    var outputVolume: Double?
    var outputVolumeAvailable = false
    var outputError: String?
    var nextMeeting: IslandMeeting?
    var calendarEnabled = false
    var calendarAuthorized = false
    var calendarStatus = "开启后显示下一场日程"
    var quickActions: [IslandQuickAction] = []
    var quickActionStatus: String?
    private var activityVisible = true
    private var notificationPreview = IslandPreferences.shared.notificationPreview
    private let content = NSView()
    private let contentMask = CAShapeLayer()
    private let body = FlippedView()
    private let leftAccessory = FlippedView()
    private let rightAccessory = FlippedView()
    private let centerLabel = PassiveLabel(labelWithString: "")
    private var state: IslandState = .idle(.time(""))
    private var tab: IslandTab = .music
    private var preview = false
    private var expanded = false
    private var visualRect = CGRect.zero
    private var notchWidth: CGFloat = 200
    private var notchHeight: CGFloat = 32
    private var hasNotch = false
    private let panelWidth: CGFloat = 440
    private let bodyHeight: CGFloat = 284
    private var hover = false
    private var contentKey = ""
    private var titleLabel: NSTextField?
    private var artistLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var remainingLabel: NSTextField?
    private var timerLabel: NSTextField?
    private var timerStatus: NSTextField?
    private var playButton: ActionButton?
    private var pauseButton: ActionButton?
    private var seekSlider: InteractionSlider?
    private var artworkView: NSImageView?
    private var hudLabel: NSTextField?
    private var hudSlider: InteractionSlider?
    private var minutesField: NSTextField?
    private var draggingFiles = false
    private var scrollHandled = false
    private var scrollCooldown: TimeInterval = 0
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var seekInProgress = false
    private var accessoryKey = ""
    private var hudInteracting = false
    private var equalizer: EqualizerView?
    private var compactArtwork: NSImageView?
    private var compactFocusBadge: FocusBadgeView?
    private weak var panelFocusBadge: FocusBadgeView?
    private(set) var focusState = SystemFocusState.unavailable
    private var compactTimer: TimerSession? { IslandPreferences.shared.focusDisplayEnabled ? timerSession : nil }
    private var compactFocus: SystemFocusMode? {
        guard case .idle = state else { return nil }
        return focusState.mode
    }
    private var bodyFadeWork: DispatchWorkItem?
    private var transitionWork: DispatchWorkItem?
    private var outgoingBody: NSImageView?
    var compactMediaVisible = false
    private var accessoryStyle = ""
    private var accessoryVisible: Bool?
    private var compactLyrics: CompactLyricsView?
    private var compactLyricsVisible = false
    private var compactLyricsHide: DispatchWorkItem?
    private var lyricsAppearance = IslandPreferences.shared.lyricsAppearance
    private var accentRGB = IslandPreferences.shared.accentRGB
    private var lyricTimer: Timer?
    private var playerLyrics: LyricRollView?
    private var lyricWrapper = LyricsWrapping()
    private struct LyricTrack: Equatable {
        let source: String
        let id: String
        let title: String
        let artist: String
    }
    private var lyricTrack: LyricTrack?

    private var musicPanelWidth: CGFloat { max(360, notchWidth + 100) }
    private var sideLyricsPanelWidth: CGFloat { lyricsAppearance.width + 36 }
    private var expandedLyricPosition: LyricsPlacement {
        guard let mediaInfo, !mediaInfo.lyrics.isEmpty else { return .hidden }
        let placement = IslandPreferences.shared.expandedLyricsPlacement
        if placement == .side, let screen = IslandPreferences.shared.screen,
           screen.frame.width < musicPanelWidth + sideLyricsPanelWidth + 16 {
            return .below
        }
        return placement
    }

    var mediaInfo: MediaInfo?
    var timerSession: TimerSession?
    var shelf: FileShelf?
    var compactOnly = false
    var interactive: Bool { true }
    var onDismiss: (() -> Void)?
    var onExpand: (() -> Void)?
    var onPreview: (() -> Void)?
    var onSelectTab: ((IslandTab) -> Void)?
    var onPlayPause: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onOpenPlayer: (() -> Void)?
    var onTimerStart: ((Int, String) -> Void)?
    var onTimerPause: (() -> Void)?
    var onTimerAdd: (() -> Void)?
    var onTimerCancel: (() -> Void)?
    var onStopAlert: (() -> Void)?
    var onVolume: ((Double) -> Void)?
    var onBrightness: ((Double) -> Void)?
    var onInteraction: ((Bool) -> Void)?
    var onDropHover: ((Bool) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onSettings: (() -> Void)?
    var onDismissActivity: (() -> Void)?
    var onSelectOutput: ((UInt32) -> Void)?
    var onOutputVolume: ((Double) -> Void)?
    var onEnableCalendar: (() -> Void)?
    var onOpenMeeting: ((IslandMeeting) -> Void)?
    var onQuickAction: ((IslandQuickAction) -> Void)?
    var onConfigureQuickActions: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        shape.fillColor = NSColor.black.cgColor
        shape.strokeColor = NSColor.white.withAlphaComponent(0.045).cgColor
        shape.lineWidth = 0.7
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowRadius = 22; shape.shadowOffset = CGSize(width: 0, height: -8)
        layer?.addSublayer(shape)
        content.frame = bounds; content.autoresizingMask = [.width, .height]; content.wantsLayer = true
        backdrop.frame = bounds; backdrop.autoresizingMask = [.width, .height]; addSubview(backdrop)
        backdrop.onActivityChanged = { [weak self] active in
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self?.shape.fillColor = (active ? NSColor.clear : NSColor.black).cgColor
            CATransaction.commit()
        }
        content.layer?.mask = contentMask; addSubview(content)
        for v in [body, leftAccessory, rightAccessory] { v.wantsLayer = true; content.addSubview(v) }
        centerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); centerLabel.textColor = .white; centerLabel.alignment = .center
        content.addSubview(centerLabel)
        registerForDraggedTypes([.fileURL])
        relayout()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    private var top: CGFloat { bounds.maxY }
    var debugVisibleRect: CGRect { visualRect }
    private var attachedNoticeLayout: NotchNotificationLayout {
        let prefs = IslandPreferences.shared
        let availableWidth = min(bounds.width, prefs.screen?.frame.width ?? bounds.width)
        return NotchNotificationLayout(notch: notchWidth, available: availableWidth - 16,
                                       width: prefs.notificationWidth, depth: prefs.notificationDepth)
    }
    var debugNotchRect: CGRect { notchRect }
    var debugWaveAnimating: Bool { equalizer?.isAnimating ?? false }
    var debugWaveIsFlat: Bool { equalizer?.isFlat ?? false }
    var debugGlassActive: Bool { backdrop.nativeEffectActive }
    var debugGlassClipBounds: CGRect? { backdrop.debugClipBounds }
    func applyAppearance() {
        updateBackdrop(rect: visualRect, previous: nil, spring: nil)
        let lyrics = IslandPreferences.shared.lyricsAppearance
        let accent = IslandPreferences.shared.accentRGB
        if accent != accentRGB {
            accentRGB = accent
            func redrawButtons(_ parent: NSView) {
                for child in parent.subviews {
                    if child is ActionButton { child.needsDisplay = true }
                    redrawButtons(child)
                }
            }
            redrawButtons(body)
        }
        if lyrics != lyricsAppearance {
            let widthChanged = lyrics.width != lyricsAppearance.width
            lyricsAppearance = lyrics
            if widthChanged, expanded, tab == .music { contentKey = ""; render(state, animated: false) }
            else { refreshLyrics() }
        }
        compactLyrics?.rightBackground = IslandPreferences.shared.lyricsRightBackground
        if case .notification = state { render(state) }
        let preview = IslandPreferences.shared.notificationPreview
        if notificationPreview != preview {
            notificationPreview = preview
            if case .notification = state { contentKey = ""; render(state, animated: false) }
        }
    }
    func setActivityVisible(_ visible: Bool) {
        guard visible != activityVisible else { return }; activityVisible = visible
        refreshCompact(); applyAppearance()
    }
    private func updateBackdrop(rect: CGRect, previous: CGPath?, spring: CASpringAnimation?) {
        var configuration = backdropConfiguration
        if !activityVisible { configuration.style = .black }
        backdrop.update(configuration: configuration, rect: rect, path: path(for: rect), previous: previous, notchHeight: notchHeight, spring: spring)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shape.fillColor = backdrop.nativeEffectActive ? NSColor.clear.cgColor : NSColor.black.cgColor
        CATransaction.commit()
    }
    private var notchRect: CGRect { CGRect(x: bounds.midX - notchWidth / 2, y: top - notchHeight, width: notchWidth, height: notchHeight) }
    static func notchGeometry() -> (width: CGFloat, height: CGFloat) {
        let geometry = IslandPreferences.shared.screen?.islandGeometry
        return (geometry?.width ?? 200, geometry?.height ?? 32)
    }
    func relayout() {
        let geometry = IslandPreferences.shared.screen?.islandGeometry
        notchWidth = geometry?.width ?? 200; notchHeight = geometry?.height ?? 32; hasNotch = geometry?.hasNotch ?? false
        let scale = IslandPreferences.shared.screen?.backingScaleFactor ?? 2
        shape.contentsScale = scale
        contentKey = ""; accessoryKey = ""
        render(state, animated: false)
    }
    func relayoutIfNeeded() {
        let geometry = IslandPreferences.shared.screen?.islandGeometry
        guard notchWidth != geometry?.width || notchHeight != geometry?.height || hasNotch != geometry?.hasNotch else { return }
        relayout()
    }
    private func path(for rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let r = rect.height <= notchHeight + 1 ? min(10, rect.height / 2) : 24
        // The same command sequence is used for every state, making path interpolation stable.
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath(); return p
    }
    private func morph(to rect: CGRect, animated: Bool) {
        let target = path(for: rect)
        let previous = shape.presentation()?.path ?? shape.path ?? target
        let moving = animated && !IslandPreferences.shared.reduceMotion
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shape.path = target; shape.shadowPath = target; shape.shadowOpacity = rect.height > notchHeight + 8 ? 0.45 : 0
        shape.strokeColor = NSColor.white.withAlphaComponent(rect.height > notchHeight ? 0.045 : 0).cgColor
        contentMask.path = target
        CATransaction.commit()
        shape.removeAnimation(forKey: "morph")
        shape.removeAnimation(forKey: "shadowMorph")
        contentMask.removeAnimation(forKey: "morph")
        var motion: CASpringAnimation?
        if moving {
            let spring = CASpringAnimation(keyPath: "path")
            spring.fromValue = previous; spring.toValue = target
            spring.mass = 1; spring.stiffness = 520; spring.damping = 40; spring.initialVelocity = 0
            spring.duration = min(0.65, spring.settlingDuration)
            motion = spring
            shape.add(spring, forKey: "morph")
            contentMask.add(spring.copy() as! CAAnimation, forKey: "morph")
            let shadow = spring.copy() as! CASpringAnimation; shadow.keyPath = "shadowPath"
            shape.add(shadow, forKey: "shadowMorph")
        }
        visualRect = rect
        updateBackdrop(rect: rect, previous: previous, spring: motion)
    }
    func render(_ newState: IslandState, animated: Bool = true) {
        let previousTab = tab
        let previousExpanded = expanded
        state = newState
        var height = notchHeight
        var width = notchWidth + ((compactMediaVisible || compactTimer != nil || compactFocus != nil) ? 112 : 0)
        var key = "idle"
        expanded = false; preview = false
        switch newState {
        case .workspace(let selected, let isPreview):
            tab = selected; preview = isPreview; expanded = true
            let secondary = selected == .audio || selected == .calendar || selected == .shortcuts || selected == .clipboard
            let position: LyricsPlacement = selected == .music && !isPreview ? expandedLyricPosition : .hidden
            height += isPreview ? 86 : (selected == .music ? 242 + (position == .below ? 62 : 0) : (secondary ? 326 : bodyHeight))
            width = isPreview ? max(notchWidth + 90, 324) : (selected == .music ? musicPanelWidth + (position == .side ? sideLyricsPanelWidth : 0) : panelWidth)
            key = "panel-\(tab.rawValue)-\(isPreview)-\(visibleTabs.map(\.rawValue))-lyrics\(position.rawValue)"
        case .music(let info):
            mediaInfo = info; tab = .music; expanded = true
            let position = expandedLyricPosition
            height += 242 + (position == .below ? 62 : 0)
            width = musicPanelWidth + (position == .side ? sideLyricsPanelWidth : 0)
            key = "panel-0-false-\(visibleTabs.map(\.rawValue))-lyrics\(position.rawValue)"
        case .volume: width = notchWidth + 236; key = "volume"
        case .brightness: width = notchWidth + 236; key = "brightness"
        case .airPods(let info): height += 226; width = max(notchWidth + 140, 390); key = "airpods-\(info.address)-\(info.connected)"
        case .notification(let info):
            let attached = IslandPreferences.shared.notificationPlacement == .sides
            let layout = attachedNoticeLayout
            height += attached ? layout.depth : 154
            width = attached ? layout.width : max(notchWidth + 140, 400)
            key = "notification-\(info.identity)-\(showsNotificationPreview)-\(attached)-\(width)-\(height)"
        case .inputSource(let name): height += 78; width = max(notchWidth + 100, 340); key = "input-\(name)"
        case .charging(let connected, let percent): height += 78; width = max(notchWidth + 100, 340); key = "power-\(connected)-\(percent)"
        case .alarm(let text), .timerDone(let text): height += 148; width = max(notchWidth + 140, 368); key = "alert-\(text)"
        default: break
        }
        let rect = CGRect(x: bounds.midX - width / 2, y: top - height, width: width, height: height)
        let changed = key != contentKey
        if !visualRect.equalTo(rect) || !animated { morph(to: rect, animated: animated) }
        let h = height - notchHeight
        if !changed {
            renderAccessories(newState)
            refreshContent()
            return
        }
        transitionWork?.cancel(); outgoingBody?.removeFromSuperview(); outgoingBody = nil
        let lateral = previousExpanded && expanded && previousTab != tab
        let direction: CGFloat = tab.rawValue > previousTab.rawValue ? 1 : -1
        if lateral, animated, !IslandPreferences.shared.reduceMotion, !body.isHidden, !body.subviews.isEmpty,
           let bitmap = body.bitmapImageRepForCachingDisplay(in: body.bounds) {
            body.cacheDisplay(in: body.bounds, to: bitmap)
            let image = NSImage(size: body.bounds.size); image.addRepresentation(bitmap)
            let snapshot = PassiveImage(frame: body.frame); snapshot.image = image; snapshot.imageScaling = .scaleAxesIndependently; snapshot.wantsLayer = true
            content.addSubview(snapshot, positioned: .above, relativeTo: body); outgoingBody = snapshot
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.14
            snapshot.layer?.opacity = 0; snapshot.layer?.add(fade, forKey: "depart")
            let slide = CABasicAnimation(keyPath: "transform.translation.x"); slide.fromValue = 0; slide.toValue = -direction * 10; slide.duration = 0.16; slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            snapshot.layer?.add(slide, forKey: "departMove")
            let work = DispatchWorkItem { [weak self, weak snapshot] in snapshot?.removeFromSuperview(); self?.outgoingBody = nil }
            transitionWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.17, execute: work)
        }
        bodyFadeWork?.cancel()
        body.layer?.removeAnimation(forKey: "contentFade")
        body.layer?.removeAnimation(forKey: "contentMove")
        if h > 0 {
            body.isHidden = false
            body.frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: h)
            body.layer?.opacity = 1
        } else if !animated {
            body.isHidden = true; body.layer?.opacity = 0
            body.subviews.forEach { $0.removeFromSuperview() }
        } else if !body.isHidden {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = body.layer?.presentation()?.opacity ?? 1; fade.toValue = 0; fade.duration = animated ? 0.12 : 0
            body.layer?.opacity = 0; body.layer?.add(fade, forKey: "contentFade")
            let work = DispatchWorkItem { [weak self] in self?.body.isHidden = true; self?.body.subviews.forEach { $0.removeFromSuperview() } }
            bodyFadeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.13 : 0), execute: work)
        }
        if changed {
            contentKey = key
            if h > 0 { body.subviews.forEach { $0.removeFromSuperview() } }
            airPodsCard = nil
            audioPanel = nil; calendarPanel = nil; quickPanel = nil; clipboardPanel = nil
            titleLabel = nil; artistLabel = nil; elapsedLabel = nil; remainingLabel = nil; timerLabel = nil; timerStatus = nil; playButton = nil; seekSlider = nil; artworkView = nil; pauseButton = nil; minutesField = nil; playerLyrics = nil
            if expanded { preview ? buildPreview() : buildPanel() }
            else { buildTransient(newState) }
            if h > 0 && animated && !body.isHidden && !IslandPreferences.shared.reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = lateral ? 0.22 : 0.18
                body.layer?.add(fade, forKey: "contentFade")
                let move = CASpringAnimation(keyPath: lateral ? "transform.translation.x" : "transform.translation.y"); move.fromValue = lateral ? direction * 10 : 3; move.toValue = 0; move.stiffness = 420; move.damping = 36; move.duration = 0.42
                body.layer?.add(move, forKey: "contentMove")
            }
        }
        renderAccessories(newState)
        refreshContent()
    }
    @discardableResult private func label(_ text: String, frame: NSRect, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .white, parent: NSView? = nil) -> NSTextField {
        let field = PassiveLabel(labelWithString: text); field.frame = frame
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color; field.lineBreakMode = .byTruncatingTail
        (parent ?? body).addSubview(field); return field
    }
    @discardableResult private func button(_ title: String = "", symbol: String? = nil, help: String, frame: NSRect, action: @escaping (NSView) -> Void) -> ActionButton {
        let b = ActionButton(title: title, symbol: symbol, help: help, action: action); b.frame = frame; body.addSubview(b); return b
    }
    private func buildPanel() {
        let w = body.bounds.width
        let step = min(56, (w - 104) / CGFloat(max(1, visibleTabs.count)))
        for (index, selected) in visibleTabs.enumerated() {
            let b = button(symbol: selected.symbol, help: selected.title, frame: NSRect(x: 14 + CGFloat(index) * step, y: 7, width: step - 3, height: 28)) { [weak self] _ in self?.onSelectTab?(selected) }
            b.font = .systemFont(ofSize: 11, weight: selected == tab ? .semibold : .regular)
            b.selected = selected == tab
        }
        button(symbol: "gearshape", help: "打开设置", frame: NSRect(x: w - 74, y: 7, width: 28, height: 28)) { [weak self] _ in self?.onSettings?() }.symbolSize = 12
        button(symbol: "chevron.up", help: "收起 · Esc", frame: NSRect(x: w - 42, y: 7, width: 28, height: 28)) { [weak self] _ in self?.onDismiss?() }.symbolSize = 12
        guard !visibleTabs.isEmpty else {
            let title = label("只留一片安静", frame: NSRect(x: 24, y: 114, width: w - 48, height: 28), size: 18, weight: .medium); title.alignment = .center
            let hint = label("在设置中开启需要的模块", frame: NSRect(x: 24, y: 154, width: w - 48, height: 20), size: 12, color: .white.withAlphaComponent(0.5)); hint.alignment = .center
            return
        }
        switch tab {
        case .music: buildMusic(); case .files: buildFiles(); case .timer: buildTimer()
        case .focus: buildFocus()
        case .audio:
            let panel = AudioPanelView(frame: NSRect(x: 0, y: 42, width: w, height: 284))
            panel.onSelect = { [weak self] in self?.onSelectOutput?($0) }
            panel.onVolume = { [weak self] in self?.onOutputVolume?($0) }
            panel.onInteraction = { [weak self] in self?.onInteraction?($0) }
            body.addSubview(panel); audioPanel = panel
        case .calendar:
            let panel = CalendarPanelView(frame: NSRect(x: 0, y: 42, width: w, height: 284))
            panel.onOpen = { [weak self] in self?.onOpenMeeting?($0) }
            panel.onEnable = { [weak self] in self?.onEnableCalendar?() }
            body.addSubview(panel); calendarPanel = panel
        case .clipboard:
            let panel = ClipboardPanelView(frame: NSRect(x: 0, y: 42, width: w, height: 284))
            panel.history = clipboard; panel.onInteraction = { [weak self] in self?.onInteraction?(false) }
            body.addSubview(panel); clipboardPanel = panel; panel.update()
        case .shortcuts:
            let panel = QuickActionsPanelView(frame: NSRect(x: 0, y: 42, width: w, height: 284))
            body.addSubview(panel); quickPanel = panel
        }
        refreshConnectedPanels()
    }
    func refreshConnectedPanels() {
        audioPanel?.update(outputs: audioOutputs, selected: selectedOutput, switching: switchingOutput, volume: outputVolume, available: outputVolumeAvailable, error: outputError)
        calendarPanel?.update(meeting: nextMeeting, enabled: calendarEnabled, authorized: calendarAuthorized, status: calendarStatus)
        quickPanel?.update(actions: quickActions, run: { [weak self] in self?.onQuickAction?($0) }, configure: { [weak self] in self?.onConfigureQuickActions?() }, status: quickActionStatus)
    }
    func refreshClipboard() { clipboardPanel?.update() }
    func refreshMeetingCountdown() { calendarPanel?.refreshTime() }
    private func buildMusic() {
        let position = expandedLyricPosition
        let w = position == .side ? musicPanelWidth : body.bounds.width
        let art = PassiveImage(frame: NSRect(x: 24, y: 54, width: 60, height: 60))
        art.wantsLayer = true; art.layer?.cornerRadius = 9; art.layer?.masksToBounds = true
        art.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor; art.imageScaling = .scaleProportionallyUpOrDown
        body.addSubview(art); artworkView = art
        titleLabel = label("暂无播放", frame: NSRect(x: 100, y: 62, width: w - 124, height: 22), size: 16, weight: .semibold)
        artistLabel = label("播放音乐后自动显示", frame: NSRect(x: 100, y: 91, width: w - 124, height: 19), size: 12, color: .white.withAlphaComponent(0.5))
        let slider = InteractionSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(seekChanged))
        slider.frame = NSRect(x: 22, y: 135, width: w - 44, height: 16); slider.isContinuous = true; slider.controlSize = .small; slider.setAccessibilityLabel("播放进度")
        slider.onInteraction = { [weak self] value in self?.seekInProgress = value; self?.onInteraction?(value) }
        slider.onFinish = { [weak self] fraction in guard let self else { return }; self.onSeek?(fraction * (self.mediaInfo?.duration ?? 0)) }
        body.addSubview(slider); seekSlider = slider
        elapsedLabel = label("0:00", frame: NSRect(x: 25, y: 158, width: 100, height: 14), size: 10, color: .white.withAlphaComponent(0.38))
        remainingLabel = label("−0:00", frame: NSRect(x: w - 125, y: 158, width: 100, height: 14), size: 10, color: .white.withAlphaComponent(0.38)); remainingLabel?.alignment = .right
        elapsedLabel?.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); remainingLabel?.font = elapsedLabel?.font
        button(symbol: "backward.fill", help: "上一首", frame: NSRect(x: w / 2 - 88, y: 185, width: 44, height: 42)) { [weak self] _ in self?.onPrevious?() }.symbolSize = 22
        playButton = button(symbol: "play.fill", help: "播放或暂停", frame: NSRect(x: w / 2 - 26, y: 180, width: 52, height: 52)) { [weak self] _ in self?.onPlayPause?() }
        playButton?.symbolSize = 28
        button(symbol: "forward.fill", help: "下一首", frame: NSRect(x: w / 2 + 44, y: 185, width: 44, height: 42)) { [weak self] _ in self?.onNext?() }.symbolSize = 22
        if position != .hidden {
            let side = position == .side
            let lineWidth = min(lyricsAppearance.width, side ? sideLyricsPanelWidth - 32 : w - 48)
            let x = side ? w + 8 : (w - lineWidth) / 2
            let lyrics = LyricRollView(frame: CGRect(x: x, y: side ? 88 : 239, width: lineWidth, height: side ? 100 : 49),
                                       placement: side ? .side : .below)
            body.addSubview(lyrics)
            playerLyrics = lyrics
        }
    }
    @objc private func seekChanged(_ sender: NSSlider) {
        elapsedLabel?.stringValue = formatTrackTime(sender.doubleValue * (mediaInfo?.duration ?? 0))
        remainingLabel?.stringValue = "−" + formatTrackTime((1 - sender.doubleValue) * (mediaInfo?.duration ?? 0))
    }
    private func buildFiles() {
        guard let shelf else { return }
        let count = shelf.items.count
        label(count == 0 ? "随手放在这里，稍后接着用" : "\(count) / 30 个文件", frame: NSRect(x: 26, y: 62, width: 248, height: 18), size: 12, color: .white.withAlphaComponent(0.5))
        button(symbol: "square.and.arrow.up", help: "分享全部文件", frame: NSRect(x: 336, y: 56, width: 34, height: 30)) { [weak shelf] sender in shelf?.share(shelf?.readableItems.map(\.url) ?? [], from: sender) }
        button(symbol: "tray", help: "清空暂存记录，保留原文件", frame: NSRect(x: 376, y: 56, width: 34, height: 30)) { [weak shelf] _ in shelf?.clear() }
        if count == 0 {
            let icon = PassiveImage(frame: NSRect(x: 196, y: 112, width: 48, height: 48)); icon.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil); icon.contentTintColor = .white.withAlphaComponent(0.7); body.addSubview(icon)
            let t = label("拖放文件到灵动岛", frame: NSRect(x: 30, y: 177, width: 380, height: 24), size: 16, weight: .medium); t.alignment = .center
            let hint = label("支持拖出、空格预览和分享 · 原文件保留原位", frame: NSRect(x: 20, y: 212, width: 400, height: 18), size: 11, color: .white.withAlphaComponent(0.42)); hint.alignment = .center
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 24, y: 92, width: 392, height: 174)); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay
            let list = FlippedView(frame: NSRect(x: 0, y: 0, width: 388, height: max(174, count * 54)))
            for (i, item) in shelf.items.enumerated() { let row = ShelfRowView(item: item, index: i, shelf: shelf); row.frame.origin = NSPoint(x: 0, y: i * 54); list.addSubview(row) }
            scroll.documentView = list; body.addSubview(scroll)
        }
    }
    private func buildFocus() {
        let mid = body.bounds.midX
        let badge = FocusBadgeView(frame: NSRect(x: mid - 23, y: 66, width: 46, height: 46))
        body.addSubview(badge); panelFocusBadge = badge
        badge.update(focusState.mode ?? .resolve(identifier: "", name: "专注模式", symbol: "moon"), animated: activityVisible)
        let title = label(focusState.title, frame: NSRect(x: 24, y: 127, width: body.bounds.width - 48, height: 28), size: 20, weight: .semibold)
        title.alignment = .center
        let detail: String
        let command: String
        let settings: String
        switch focusState {
        case .needsAccessibility:
            detail = "在系统设置中允许灵动岛读取菜单栏"
            command = "打开辅助功能设置"
            settings = "com.apple.preference.security?Privacy_Accessibility"
        case .menuItemUnavailable:
            detail = "菜单栏暂未提供专注状态"
            command = "打开菜单栏设置"
            settings = "com.apple.ControlCenter-Settings.extension"
        case .unavailable, .inactive, .active:
            if focusState.mode == .resolve(identifier: "") { detail = "系统专注已开启 · 暂无模式名称" }
            else if focusState == .unavailable { detail = "正在检查系统状态" }
            else { detail = focusState.mode == nil ? "系统当前未开启专注模式" : "系统专注模式已开启" }
            command = "专注模式设置"
            settings = "com.apple.Focus-Settings.extension"
        }
        label(detail, frame: NSRect(x: 16, y: 169, width: body.bounds.width - 32, height: 20), size: 12, color: .white.withAlphaComponent(0.58)).alignment = .center
        button(command, symbol: "arrow.up.forward", help: command, frame: NSRect(x: mid - 96, y: 211, width: 192, height: 34)) { [weak self] _ in
            if self?.focusState == .needsAccessibility { _ = MediaKeyInterceptor.requestTrust() }
            if let url = URL(string: "x-apple.systempreferences:\(settings)") { NSWorkspace.shared.open(url) }
        }
    }
    func updateFocus(_ next: SystemFocusState) {
        guard next != focusState else { return }
        focusState = next
        if expanded && tab == .focus { contentKey = "" }
        render(state)
    }
    private func buildTimer() {
        if let session = timerSession {
            timerLabel = label(formatTime(session.remaining()), frame: NSRect(x: 24, y: 72, width: 392, height: 68), size: 52, weight: .light)
            timerLabel?.font = .monospacedDigitSystemFont(ofSize: 52, weight: .light); timerLabel?.alignment = .center
            timerStatus = label(session.label, frame: NSRect(x: 24, y: 145, width: 392, height: 20), size: 12, color: .white.withAlphaComponent(0.5)); timerStatus?.alignment = .center
            pauseButton = button(session.isPaused ? "继续" : "暂停", symbol: session.isPaused ? "play.fill" : "pause.fill", help: "暂停或继续计时", frame: NSRect(x: 72, y: 200, width: 96, height: 40)) { [weak self] _ in self?.onTimerPause?() }; pauseButton?.selected = true
            button("+1 分钟", help: "增加一分钟", frame: NSRect(x: 176, y: 200, width: 96, height: 40)) { [weak self] _ in self?.onTimerAdd?() }
            button("结束", help: "结束当前计时", frame: NSRect(x: 280, y: 200, width: 88, height: 40)) { [weak self] _ in self?.onTimerCancel?() }
        } else {
            label("留一点时间，专注眼前", frame: NSRect(x: 28, y: 68, width: 382, height: 26), size: 18, weight: .semibold)
            for (i, value) in [5, 15, 25, 45].enumerated() {
                let b = button("\(value) 分钟", help: "开始 \(value) 分钟计时", frame: NSRect(x: 24 + i * 100, y: 114, width: 92, height: 46)) { [weak self] _ in self?.onTimerStart?(value * 60, value == 25 ? "专注时间" : "倒计时") }; b.selected = value == 25
            }
            let field = NSTextField(string: "10"); field.frame = NSRect(x: 28, y: 188, width: 76, height: 28); field.isBezeled = false; field.drawsBackground = false; field.textColor = .white; field.wantsLayer = true; field.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor; field.layer?.cornerRadius = 8; field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium); field.alignment = .center; field.placeholderString = "分钟"; field.setAccessibilityLabel("自定义分钟数，1 到 1440"); body.addSubview(field); minutesField = field
            label("分钟", frame: NSRect(x: 116, y: 193, width: 54, height: 20), color: .white.withAlphaComponent(0.5))
            button("开始计时", symbol: "play.fill", help: "开始自定义倒计时", frame: NSRect(x: 292, y: 182, width: 120, height: 40)) { [weak self] _ in
                guard let self, let text = self.minutesField?.stringValue.trimmingCharacters(in: .whitespaces), let minutes = Int(text), (1...1440).contains(minutes) else { NSSound.beep(); return }
                self.onTimerStart?(minutes * 60, "倒计时")
            }
            label("睡眠后继续计时 · 暂停状态自动保存", frame: NSRect(x: 28, y: 244, width: 380, height: 18), size: 11, color: .white.withAlphaComponent(0.35))
        }
    }
    private func buildPreview() {
        let title: String
        if tab == .timer, let session = timerSession { title = "\(session.label) · \(formatTime(session.remaining()))" }
        else if tab == .focus { title = focusState.title }
        else if tab == .music, let info = mediaInfo, !info.title.isEmpty { title = info.title }
        else { title = visibleTabs.isEmpty ? "只留一片安静" : tab.title }
        label(title, frame: NSRect(x: 22, y: 18, width: body.bounds.width - 72, height: 24), size: 15, weight: .semibold)
        label(tab == .music && mediaInfo?.artist.isEmpty == false ? mediaInfo!.artist : "点击展开 · 在设置中管理模块", frame: NSRect(x: 22, y: 52, width: body.bounds.width - 44, height: 18), size: 11, color: .white.withAlphaComponent(0.45))
        button(symbol: "chevron.down", help: "展开灵动岛", frame: NSRect(x: body.bounds.width - 52, y: 18, width: 30, height: 30)) { [weak self] _ in self?.onExpand?() }
    }
    private func buildTransient(_ state: IslandState) {
        switch state {
        case .airPods(let info):
            let card = AirPodsConnectionView(frame: body.bounds); card.update(info); body.addSubview(card); airPodsCard = card
            button(symbol: "xmark", help: "关闭耳机电量", frame: NSRect(x: body.bounds.width - 30, y: 3, width: 24, height: 24)) { [weak self] _ in self?.onDismissActivity?() }.symbolSize = 10
        case .notification(let info): buildNotification(info)
        case .volume, .brightness: break
        case .inputSource(let name): buildNotice(symbol: "keyboard", title: name, subtitle: "输入源已切换")
        case .charging(let connected, let percent): buildNotice(symbol: connected ? "bolt.fill" : "battery.50", title: connected ? "已连接电源" : "使用电池", subtitle: "电量 \(percent)%")
        case .alarm(let title), .timerDone(let title):
            buildNotice(symbol: "bell.badge.fill", title: title, subtitle: "时间到了，休息一下")
            button("停止响铃", symbol: "stop.fill", help: "停止响铃", frame: NSRect(x: body.bounds.midX - 68, y: 88, width: 136, height: 40)) { [weak self] _ in self?.onStopAlert?() }.selected = true
        default: break
        }
    }
    private func buildNotification(_ info: IslandNotification) {
        if IslandPreferences.shared.notificationPlacement == .sides {
            buildAttachedNotification(info)
            return
        }
        let width = body.bounds.width
        let icon = PassiveImage(frame: NSRect(x: 24, y: 20, width: 30, height: 30))
        icon.image = info.icon ?? NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white; icon.wantsLayer = true; icon.layer?.cornerRadius = 7; icon.layer?.masksToBounds = true; body.addSubview(icon)
        label(info.source, frame: NSRect(x: 68, y: 17, width: width - 126, height: 17), size: 11, weight: .medium, color: .white.withAlphaComponent(0.55))
        label(showsNotificationPreview ? info.title : "收到一条新通知", frame: NSRect(x: 68, y: 39, width: width - 94, height: 23), size: 15, weight: .semibold)
        let message = label(showsNotificationPreview ? info.body : "通知内容已隐藏", frame: NSRect(x: 24, y: 77, width: width - 48, height: 38), size: 12, color: .white.withAlphaComponent(0.66))
        message.maximumNumberOfLines = 2; message.lineBreakMode = .byTruncatingTail
        button(symbol: "xmark", help: "关闭通知", frame: NSRect(x: width - 40, y: 11, width: 28, height: 28)) { [weak self] _ in self?.onDismissActivity?() }.symbolSize = 10
        if let open = info.openApplication {
            button(info.actionTitle, symbol: "arrow.up.forward", help: info.actionTitle, frame: NSRect(x: width - 111, y: 118, width: 92, height: 27)) { [weak self] _ in open(); self?.onDismissActivity?() }.symbolSize = 10
        }
    }
    private func buildAttachedNotification(_ info: IslandNotification) {
        let width = body.bounds.width
        let height = body.bounds.height
        let trailing: CGFloat = info.openApplication == nil ? 20 : 45
        let textWidth = max(0, width - 46 - trailing)
        let title = showsNotificationPreview ? info.title : "收到一条新通知"
        _ = label(title, frame: CGRect(x: 24, y: 1, width: textWidth, height: 20), size: 14, weight: .semibold)
        let message = showsNotificationPreview ? info.body : "通知内容已隐藏"
        let text = label(message, frame: CGRect(x: 24, y: 23, width: textWidth, height: max(17, height - 32)),
                         size: 12, color: .white.withAlphaComponent(0.75))
        text.maximumNumberOfLines = max(1, min(4, Int((height - 30) / 15)))
        if let open = info.openApplication {
            button(symbol: "arrow.up.forward", help: info.actionTitle,
                   frame: CGRect(x: width - 47, y: max(4, (height - 26) / 2), width: 25, height: 26)) { [weak self] _ in
                open(); self?.onDismissActivity?()
            }.symbolSize = 11
        }
    }
    private func buildNotice(symbol: String, title: String, subtitle: String) {
        let icon = PassiveImage(frame: NSRect(x: 22, y: 20, width: 28, height: 28)); icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); icon.contentTintColor = .white.withAlphaComponent(0.8); body.addSubview(icon)
        label(title, frame: NSRect(x: 66, y: 12, width: body.bounds.width - 88, height: 24), size: 16, weight: .semibold)
        label(subtitle, frame: NSRect(x: 66, y: 42, width: body.bounds.width - 88, height: 18), size: 11, color: .white.withAlphaComponent(0.5))
    }
    private func renderAccessories(_ state: IslandState) {
        refreshLyrics()
        let style: String
        switch state {
        case .volume: style = "volume"
        case .brightness: style = "brightness"
        case .notification where IslandPreferences.shared.notificationPlacement == .sides: style = "attachedNotification"
        default: style = "compact"
        }
        if accessoryStyle != style {
            accessoryStyle = style
            accessoryVisible = nil; accessoryKey = ""
            leftAccessory.subviews.forEach { $0.removeFromSuperview() }; rightAccessory.subviews.forEach { $0.removeFromSuperview() }
            hudLabel = nil; hudSlider = nil; equalizer = nil; compactArtwork = nil; compactFocusBadge = nil
            if style == "compact" {
                let side: CGFloat = min(22, notchHeight - 10)
                let art = PassiveImage(frame: NSRect(x: (56 - side) / 2, y: (notchHeight - side) / 2, width: side, height: side))
                art.wantsLayer = true; art.layer?.cornerRadius = 5; art.layer?.masksToBounds = true; compactArtwork = art; leftAccessory.addSubview(art)
                let badge = FocusBadgeView(frame: art.frame)
                badge.isHidden = true; compactFocusBadge = badge; leftAccessory.addSubview(badge)
                let wave = EqualizerView(frame: NSRect(x: 16, y: (notchHeight - 14) / 2, width: 24, height: 14))
                equalizer = wave; rightAccessory.addSubview(wave)
            } else if style != "attachedNotification" {
                buildHUD(volume: style == "volume")
            }
        }
        centerLabel.isHidden = hasNotch; centerLabel.frame = notchRect.insetBy(dx: 6, dy: 7)
        if style == "attachedNotification", case .notification(let info) = state {
            renderAttachedNotificationHeader(info)
            return
        }
        if style != "compact" {
            leftAccessory.frame = CGRect(x: notchRect.minX - 118, y: notchRect.minY, width: 118, height: notchHeight)
            rightAccessory.frame = CGRect(x: notchRect.maxX, y: notchRect.minY, width: 118, height: notchHeight)
            setAccessoryVisibility(true)
            let value: Double
            if case .volume(let v, let muted) = state {
                value = v
                (leftAccessory.subviews.first as? NSImageView)?.image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : (v > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"), accessibilityDescription: "音量")
            } else if case .brightness(let v) = state { value = v } else { value = 0 }
            hudLabel?.stringValue = "\(Int((value * 100).rounded()))%"
            if !hudInteracting { hudSlider?.setDisplayedValue(value, animated: true) }
            return
        }
        let show = compactMediaVisible || compactTimer != nil || compactFocus != nil
        setAccessoryVisibility(show)
        leftAccessory.frame = CGRect(x: notchRect.minX - 56, y: notchRect.minY, width: 56, height: notchHeight)
        rightAccessory.frame = CGRect(x: notchRect.maxX, y: notchRect.minY, width: 56, height: notchHeight)
        let pairedIcons = compactFocus != nil && compactMediaVisible
        let side = min(22, notchHeight - 10)
        compactArtwork?.isHidden = compactFocus != nil && !compactMediaVisible
        compactArtwork?.frame.origin.x = pairedIcons ? 4 : (56 - side) / 2
        compactFocusBadge?.frame.origin.x = pairedIcons ? 30 : (56 - side) / 2
        compactFocusBadge?.update(compactFocus, animated: activityVisible)
        if expanded && tab == .focus, let mode = focusState.mode { panelFocusBadge?.update(mode, animated: activityVisible) }
        if compactMediaVisible, let art = mediaInfo?.artwork { compactArtwork?.image = NSImage(cgImage: art, size: .zero) }
        else { compactArtwork?.image = NSImage(systemSymbolName: compactTimer != nil ? "timer" : "music.note", accessibilityDescription: nil); compactArtwork?.contentTintColor = .white.withAlphaComponent(0.7) }
        equalizer?.isHidden = compactTimer != nil || !compactMediaVisible
        equalizer?.setPlaying(activityVisible && compactTimer == nil && compactMediaVisible && mediaInfo?.isPlaying == true, color: mediaInfo?.dominantColor.map { NSColor(cgColor: $0) ?? .white } ?? .white)
        if let session = compactTimer {
            let key = "timer-\(Int(session.remaining().rounded(.up)))"
            if key != accessoryKey {
                rightAccessory.subviews.filter { $0 !== equalizer }.forEach { $0.removeFromSuperview() }
                let field = label(formatTime(session.remaining()), frame: NSRect(x: 0, y: (notchHeight - 16) / 2, width: 56, height: 17), size: 11, parent: rightAccessory)
                field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium); field.alignment = .center; accessoryKey = key
            }
        } else if let focus = compactFocus, !compactMediaVisible {
            let key = "focus-" + focus.name
            if accessoryKey != key {
                rightAccessory.subviews.filter { $0 !== equalizer }.forEach { $0.removeFromSuperview() }
                let field = label(focus.name, frame: NSRect(x: 0, y: (notchHeight - 15) / 2, width: 50, height: 16), size: 10, weight: .medium, parent: rightAccessory)
                field.alignment = .center; field.toolTip = focus.name; accessoryKey = key
            }
        } else if !accessoryKey.isEmpty { rightAccessory.subviews.filter { $0 !== equalizer }.forEach { $0.removeFromSuperview() }; accessoryKey = "" }
        if !hasNotch { centerLabel.stringValue = "" }
    }
    private func renderAttachedNotificationHeader(_ info: IslandNotification) {
        setAccessoryVisibility(true)
        let shelfWidth = max(0, (visualRect.width - notchWidth) / 2)
        leftAccessory.frame = CGRect(x: visualRect.minX, y: notchRect.minY, width: shelfWidth, height: notchHeight)
        rightAccessory.frame = CGRect(x: notchRect.maxX, y: notchRect.minY, width: shelfWidth, height: notchHeight)
        let key = "\(info.identity)-\(shelfWidth)"
        guard accessoryKey != key else { return }
        accessoryKey = key
        leftAccessory.subviews.forEach { $0.removeFromSuperview() }; rightAccessory.subviews.forEach { $0.removeFromSuperview() }
        let size = min(22, notchHeight - 8)
        let icon = PassiveImage(frame: CGRect(x: max(8, (shelfWidth - size) / 2), y: (notchHeight - size) / 2,
                                              width: size, height: size))
        icon.image = info.icon ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 5
        icon.layer?.masksToBounds = true
        leftAccessory.addSubview(icon)
        let close = ActionButton(symbol: "xmark", help: "关闭通知") { [weak self] _ in self?.onDismissActivity?() }
        close.symbolSize = 9
        close.frame = CGRect(x: max(0, shelfWidth - 28), y: (notchHeight - 24) / 2, width: 23, height: 24)
        rightAccessory.addSubview(close)
        _ = label(info.source, frame: CGRect(x: 5, y: (notchHeight - 17) / 2, width: max(0, shelfWidth - 33), height: 17),
                  size: 11, weight: .semibold, color: .white.withAlphaComponent(0.82), parent: rightAccessory)
    }
    private func setAccessoryVisibility(_ visible: Bool) {
        guard accessoryVisible != visible else { return }; accessoryVisible = visible
        for accessory in [leftAccessory, rightAccessory] {
            let opacity = accessory.layer?.presentation()?.opacity ?? accessory.layer?.opacity ?? 0
            CATransaction.begin(); CATransaction.setDisableActions(true)
            accessory.layer?.opacity = visible ? 1 : 0
            CATransaction.commit()
            if !IslandPreferences.shared.reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = opacity; fade.toValue = visible ? 1 : 0; fade.duration = 0.16
                accessory.layer?.add(fade, forKey: "reveal")
            }
        }
    }
    private func buildHUD(volume: Bool) {
        let icon = PassiveImage(frame: NSRect(x: 15, y: (notchHeight - 18) / 2, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: volume ? "speaker.wave.2.fill" : "sun.max.fill", accessibilityDescription: nil); icon.contentTintColor = .white
        leftAccessory.addSubview(icon)
        hudLabel = label("", frame: NSRect(x: 46, y: (notchHeight - 16) / 2, width: 58, height: 17), size: 11, parent: leftAccessory)
        hudLabel?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let slider = InteractionSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: volume ? #selector(volumeChanged) : #selector(brightnessChanged))
        slider.frame = NSRect(x: 10, y: (notchHeight - 18) / 2, width: 92, height: 18); slider.isContinuous = true; slider.controlSize = .small
        slider.onInteraction = { [weak self] value in self?.hudInteracting = value; self?.onInteraction?(value) }
        slider.setAccessibilityLabel(volume ? "调整音量" : "调整亮度"); rightAccessory.addSubview(slider); hudSlider = slider
    }
    @objc private func volumeChanged(_ sender: NSSlider) { hudLabel?.stringValue = "\(Int(sender.doubleValue * 100))%"; onVolume?(sender.doubleValue) }
    @objc private func brightnessChanged(_ sender: NSSlider) { hudLabel?.stringValue = "\(Int(sender.doubleValue * 100))%"; onBrightness?(sender.doubleValue) }
    func refreshContent() {
        if case .airPods(let info) = state { airPodsCard?.update(info) }
        if tab == .music, expanded, !preview {
            let info = mediaInfo?.interpolated()
            titleLabel?.stringValue = info?.title.isEmpty == false ? info!.title : "暂无播放"
            artistLabel?.stringValue = info?.artist.isEmpty == false ? info!.artist : "播放音乐后自动显示"
            artworkView?.image = info?.artwork.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            artworkView?.contentTintColor = .white.withAlphaComponent(0.6)
            playButton?.image = NSImage(systemSymbolName: info?.isPlaying == true ? "pause.fill" : "play.fill", accessibilityDescription: "播放或暂停")
            playButton?.isEnabled = info != nil
            seekSlider?.isEnabled = (info?.duration ?? 0) > 0 && info?.source.isEmpty == false
            if !seekInProgress { seekSlider?.doubleValue = info?.progress ?? 0; elapsedLabel?.stringValue = formatTrackTime(info?.elapsed ?? 0); remainingLabel?.stringValue = "−" + formatTrackTime(max(0, (info?.duration ?? 0) - (info?.elapsed ?? 0))) }
        }
        if let session = timerSession {
            timerLabel?.stringValue = formatTime(session.remaining())
            timerStatus?.stringValue = session.isPaused ? "\(session.label) · 已暂停" : session.label
            pauseButton?.title = session.isPaused ? "继续" : "暂停"
            pauseButton?.image = NSImage(systemSymbolName: session.isPaused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        }
    }
    func playbackPositionDidChange(animated: Bool = false) {
        refreshContent()
        refreshLyrics(allowScroll: animated)
    }
    private func refreshLyrics(allowScroll: Bool = true) {
        let compact: Bool
        if case .idle = state {
            compact = compactMediaVisible && IslandPreferences.shared.lyricsPlacement != .hidden
        } else { compact = false }
        if !compact { hideCompactLyrics() }
        guard activityVisible, compact || playerLyrics != nil, let info = mediaInfo, !info.lyrics.isEmpty else {
            hideCompactLyrics()
            playerLyrics?.reset()
            lyricTimer?.invalidate(); lyricTimer = nil
            return
        }
        let now = Date()
        let elapsed = info.interpolated(at: now).elapsed
        let style = IslandPreferences.shared.lyricsAnimation
        let track = LyricTrack(source: info.source, id: info.trackID, title: info.title, artist: info.artist)
        let animated = allowScroll && lyricTrack == track && info.isPlaying && !IslandPreferences.shared.reduceMotion
        lyricTrack = track
        let lyrics: LyricRollView?
        if compact {
            lyrics = prepareCompactLyrics(hasLine: true).roll
        } else {
            lyrics = playerLyrics
        }
        let width: CGFloat = lyrics?.fittingWidth ?? CGFloat(lyricsAppearance.width)
        let font = lyrics?.lyricFont(for: lyricsAppearance) ?? .systemFont(ofSize: lyricsAppearance.size, weight: lyricsAppearance.weight.fontWeight)
        let wrapped = lyricWrapper.lines(for: info.lyrics, width: width, font: font, duration: info.duration)
        let wrappedInfo = MediaInfo(isPlaying: info.isPlaying, duration: info.duration, elapsed: elapsed, sampledAt: now, lyrics: wrapped)
        let pair = wrappedInfo.lyricLine(at: now)
        if compact, pair.current == nil { hideCompactLyrics() }
        lyrics?.update(current: pair.current, next: pair.next, elapsed: elapsed, style: style,
                       appearance: lyricsAppearance, animated: animated)

        let nextSegment: TimeInterval?
        if style == .appleMusic {
            nextSegment = pair.current?.segments.first(where: { $0.time > elapsed })?.time
        } else {
            nextSegment = nil
        }
        let nextLineTime = pair.next?.time ?? .infinity
        let nextWordTime = nextSegment ?? .infinity
        let nextChange = min(nextLineTime, nextWordTime)
        guard info.isPlaying, nextChange.isFinite, info.duration <= 0 || nextChange <= info.duration else {
            lyricTimer?.invalidate(); lyricTimer = nil
            return
        }
        let deadline = info.sampledAt.addingTimeInterval(nextChange - info.elapsed)
        if let timer = lyricTimer, timer.isValid, abs(timer.fireDate.timeIntervalSince(deadline)) < 0.008 { return }
        lyricTimer?.invalidate()
        let timer = Timer(fire: max(deadline, now.addingTimeInterval(0.003)), interval: 0, repeats: false) { [weak self] _ in
            self?.lyricTimer = nil
            self?.refreshLyrics()
        }
        timer.tolerance = style == .appleMusic ? 0.008 : 0.02
        lyricTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func hideCompactLyrics() {
        setCompactLyricsVisible(false)
    }
    private func setCompactLyricsVisible(_ visible: Bool) {
        guard let lyrics = compactLyrics, let layer = lyrics.layer else { return }
        let moving = activityVisible && !IslandPreferences.shared.reduceMotion
        if visible == compactLyricsVisible {
            if !visible && !moving { lyrics.isHidden = true; layer.removeAnimation(forKey: "lyricVisibility") }
            return
        }
        compactLyricsVisible = visible
        compactLyricsHide?.cancel()
        if !visible { lyrics.roll.reset() }
        let prior = lyrics.isHidden ? 0 : (layer.presentation()?.opacity ?? layer.opacity)
        let target: Float = visible ? 1 : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = target
        CATransaction.commit()
        layer.removeAnimation(forKey: "lyricVisibility")
        if visible { lyrics.isHidden = false }
        if moving {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = prior; fade.toValue = target
            fade.duration = visible ? 0.25 : 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "lyricVisibility")
        }
        if !visible {
            let hide = DispatchWorkItem { [weak lyrics] in lyrics?.isHidden = true }
            compactLyricsHide = hide
            if moving { DispatchQueue.main.asyncAfter(deadline: .now() + 0.19, execute: hide) }
            else { hide.perform() }
        }
    }
    private func prepareCompactLyrics(hasLine: Bool) -> CompactLyricsView {
        let lyrics: CompactLyricsView
        if let existing = compactLyrics { lyrics = existing }
        else {
            lyrics = CompactLyricsView(frame: .zero)
            lyrics.isHidden = true
            addSubview(lyrics, positioned: .below, relativeTo: content)
            compactLyrics = lyrics
        }
        let position = IslandPreferences.shared.lyricsPlacement
        lyrics.placement = position
        lyrics.lyricAppearance = lyricsAppearance
        lyrics.rightBackground = IslandPreferences.shared.lyricsRightBackground
        let frame: CGRect
        if position == .below {
            frame = CGRect(x: visualRect.minX, y: notchRect.minY - 20,
                           width: visualRect.width, height: notchHeight + 20)
        } else {
            let availableWidth = min(bounds.width, IslandPreferences.shared.screen?.frame.width ?? bounds.width)
            let extensionWidth = min(lyricsAppearance.width + 24, max(0, (availableWidth - visualRect.width) / 2 - 4))
            lyrics.sideExtension = extensionWidth
            frame = visualRect.insetBy(dx: -extensionWidth, dy: 0)
        }
        if lyrics.frame != frame { lyrics.frame = frame }
        setCompactLyricsVisible(hasLine)
        return lyrics
    }
    func refreshCompact() { render(state) }
    func refreshFiles() { guard expanded && tab == .files && !preview else { return }; contentKey = ""; render(state, animated: false) }
    func refreshTimer() {
        if expanded && tab == .timer && !preview {
            let hasTimerUI = timerLabel != nil
            if hasTimerUI != (timerSession != nil) { contentKey = ""; render(state, animated: false) }
            else { refreshContent() }
        }
        if !expanded { renderAccessories(state) }
    }
    func setHover(_ value: Bool) {
        guard hover != value else { return }; hover = value
        CATransaction.begin(); CATransaction.setAnimationDuration(0.18)
        shape.strokeColor = NSColor.white.withAlphaComponent(value && visualRect.height > notchHeight ? 0.08 : 0.0).cgColor
        CATransaction.commit()
    }
    func isMouseInNotch(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return CGRect(x: notchRect.minX - 70, y: notchRect.minY, width: notchWidth + 140, height: notchHeight).contains(local)
    }
    func isNearDropTarget(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        return notchRect.insetBy(dx: -105, dy: -20).contains(convert(window.convertPoint(fromScreen: point), from: nil))
    }
    func containsVisiblePoint(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        let currentPath = shape.presentation()?.path ?? shape.path
        return currentPath?.contains(local) ?? false
    }
    override func mouseDown(with event: NSEvent) {
        if case .notification = state { return }
        if case .airPods = state { return }
        if preview || !expanded { onExpand?() }
        else if convert(event.locationInWindow, from: nil).y >= top - notchHeight { onDismiss?() }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) } }
    override func scrollWheel(with event: NSEvent) {
        // File list scrolling belongs to the scroll view; use horizontal swipes for tabs.
        handleScroll(event)
    }
    func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) { scrollHandled = false; scrollX = 0; scrollY = 0 }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollHandled = false; scrollX = 0; scrollY = 0; return }
        if event.phase.isEmpty {
            guard Date.timeIntervalSinceReferenceDate - scrollCooldown > 0.45 else { return }
            scrollX = event.scrollingDeltaX; scrollY = event.scrollingDeltaY
        } else { scrollX += event.scrollingDeltaX; scrollY += event.scrollingDeltaY }
        guard !scrollHandled else { return }
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 16 : 2
        guard max(abs(scrollX), abs(scrollY)) >= threshold else { return }
        let invert = UserDefaults.standard.bool(forKey: "notchisland.invertScrollV2") ? -1.0 : 1.0
        if expanded && abs(scrollX) > abs(scrollY) * 1.3 { onSelectTab?(tab.moved(by: scrollX * invert < 0 ? 1 : -1, among: visibleTabs)) }
        else if abs(scrollY) > abs(scrollX) * 1.3 {
            if expanded && (tab == .files || tab == .audio || tab == .clipboard) { return }
            let direction = scrollY * invert * (event.isDirectionInvertedFromDevice ? 1 : -1)
            if direction > 0 { onExpand?() } else { onDismiss?() }
        } else { return }
        scrollHandled = true; scrollCooldown = Date.timeIntervalSinceReferenceDate
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard visibleTabs.contains(.files), sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        draggingFiles = true; onDropHover?(true); setHover(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingFiles && visibleTabs.contains(.files) ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { draggingFiles = false; onDropHover?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { draggingFiles && visibleTabs.contains(.files) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard visibleTabs.contains(.files) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }; onFilesDropped?(urls); draggingFiles = false; onDropHover?(false); return true
    }
    func debugGeometry() -> String { "notch=\(notchRect) visible=\(visualRect) tab=\(tab) preview=\(preview)" }
    private func formatTrackTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }; let s = max(0, Int(value.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

final class EqualizerView: NSView {
    private let bars = (0..<5).map { _ in CALayer() }
    private let baseline = CALayer()
    private var mode = ""
    var isAnimating: Bool { bars.contains { $0.animation(forKey: "wave") != nil } }
    var isFlat: Bool { !isAnimating && baseline.opacity == 1 }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        baseline.frame = CGRect(x: 0, y: bounds.midY - 1, width: 24, height: 2)
        baseline.cornerRadius = 1; layer?.addSublayer(baseline)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: 2)
            bar.position = CGPoint(x: 2 + CGFloat(i) * 5, y: bounds.midY)
            bar.cornerRadius = 1.5; layer?.addSublayer(bar)
        }
        setPlaying(false, color: .white)
    }
    func setPlaying(_ active: Bool, color: NSColor) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseline.backgroundColor = color.cgColor
        for bar in bars { bar.backgroundColor = color.cgColor }
        CATransaction.commit()
        let reduceMotion = IslandPreferences.shared.reduceMotion
        let nextMode = active ? (reduceMotion ? "static" : "playing") : "paused"
        guard mode != nextMode else { return }; mode = nextMode
        let oldOpacity = baseline.presentation()?.opacity ?? baseline.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        baseline.opacity = active ? 0 : 1
        CATransaction.commit()
        if !reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = oldOpacity; fade.toValue = active ? 0 : 1; fade.duration = 0.16
            baseline.add(fade, forKey: "settle")
        }
        for (i, bar) in bars.enumerated() {
            let current = bar.presentation()?.bounds ?? bar.bounds
            let opacity = bar.presentation()?.opacity ?? bar.opacity
            bar.removeAllAnimations()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: active ? CGFloat([5, 10, 7, 12, 4][i]) : 2)
            bar.opacity = active ? 1 : 0
            CATransaction.commit()
            if active && !reduceMotion {
                let wave = CAKeyframeAnimation(keyPath: "bounds.size.height")
                wave.values = [3, 8, 5, 12, 3]; wave.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                wave.duration = 0.85 + Double(i) * 0.13; wave.repeatCount = .infinity
                wave.beginTime = CACurrentMediaTime() - Double(i) * 0.18; wave.calculationMode = .cubic
                bar.add(wave, forKey: "wave")
            } else if !reduceMotion {
                let settle = CABasicAnimation(keyPath: "bounds.size.height")
                settle.fromValue = current.height; settle.toValue = bar.bounds.height; settle.duration = 0.16
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut); bar.add(settle, forKey: "settle")
            }
            if !reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = opacity; fade.toValue = active ? 1 : 0; fade.duration = 0.16
                bar.add(fade, forKey: "visibility")
            }
        }
        setAccessibilityLabel(active ? "音乐播放中" : "音乐已暂停")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
