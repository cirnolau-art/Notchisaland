import AppKit

enum NotificationSide: Int, CaseIterable {
    case right, left

    func cardFrame(in visibleFrame: CGRect, avoiding island: CGRect) -> CGRect? {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(320, available.width)
        let height: CGFloat = 86
        guard width >= 180, available.height >= height else { return nil }
        let gap: CGFloat = 12
        let preferredX = self == .right ? island.maxX + gap : island.minX - gap - width
        let x = min(max(preferredX, available.minX), available.maxX - width)
        var card = CGRect(x: x, y: available.maxY - height, width: width, height: height)
        if card.intersects(island.insetBy(dx: -gap / 2, dy: -gap / 2)) {
            card.origin.y = island.minY - gap - height
        }
        return available.contains(card) ? card : nil
    }
}

private final class SideNotificationContentView: FlippedView {
    let source = NSTextField(labelWithString: "")
    let titleField = NSTextField(labelWithString: "")
    let message = NSTextField(labelWithString: "")
    let icon = NSImageView(frame: .zero)
    let closeButton = NSButton(frame: .zero)
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.97).cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        source.font = .systemFont(ofSize: 10, weight: .medium)
        source.textColor = .white.withAlphaComponent(0.55)
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .white
        message.font = .systemFont(ofSize: 11)
        message.textColor = .white.withAlphaComponent(0.68)
        for field in [source, titleField, message] {
            field.lineBreakMode = .byTruncatingTail
            addSubview(field)
        }
        icon.contentTintColor = .white
        addSubview(icon)
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭通知")
        closeButton.contentTintColor = .white.withAlphaComponent(0.65)
        closeButton.toolTip = "关闭通知"
        addSubview(closeButton)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let w = bounds.width
        icon.frame = NSRect(x: 16, y: 18, width: 28, height: 28)
        source.frame = NSRect(x: 56, y: 11, width: w - 94, height: 16)
        titleField.frame = NSRect(x: 56, y: 31, width: w - 73, height: 20)
        message.frame = NSRect(x: 56, y: 54, width: w - 73, height: 18)
        closeButton.frame = NSRect(x: w - 35, y: 7, width: 26, height: 23)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === closeButton || hit.isDescendant(of: closeButton) ? hit : self
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class SideNotificationWindow: NSPanel {
    private let card = SideNotificationContentView(frame: .zero)
    private var closeWork: DispatchWorkItem?
    private(set) var item: IslandNotification?
    private(set) var expiresAt = Date.distantPast
    private var onDismiss: (() -> Void)?
    private var generation = 0
    private var fading = false
    var isPresenting: Bool { item != nil }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 86), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        contentView = card
        card.onClick = { [weak self] in
            guard let self else { return }
            self.item?.openApplication?()
            self.finish(animated: false)
        }
        card.closeButton.target = self
        card.closeButton.action = #selector(closeClicked)
    }
    @discardableResult
    func show(_ item: IslandNotification, frame: CGRect, previews: Bool, seconds: TimeInterval, onDismiss: @escaping () -> Void) -> Bool {
        guard !isPresenting else { return false }
        generation += 1
        self.item = item
        self.onDismiss = onDismiss
        expiresAt = Date().addingTimeInterval(seconds)
        card.icon.image = item.icon ?? NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
        setPreviews(previews)
        setFrame(frame, display: true)
        alphaValue = 1
        orderFrontRegardless()
        guard isVisible else { cancel(); return false }
        if !IslandPreferences.shared.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.18
            card.layer?.add(fade, forKey: "reveal")
        }
        let work = DispatchWorkItem { [weak self] in self?.finish(animated: true) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return true
    }
    func setPreviews(_ enabled: Bool) {
        guard let item else { return }
        card.source.stringValue = item.source
        card.titleField.stringValue = enabled ? item.title : "收到一条新通知"
        card.message.stringValue = enabled ? item.body : "通知内容已隐藏"
    }
    // A cancelled presentation must not let its timer or fade completion dismiss a successor.
    func cancel() {
        generation += 1
        closeWork?.cancel()
        closeWork = nil
        item = nil
        onDismiss = nil
        fading = false
        card.layer?.removeAllAnimations()
        orderOut(nil)
    }
    private func finish(animated: Bool) {
        guard isPresenting, !fading else { return }
        fading = true
        let expected = generation
        let done = { [weak self] in
            guard let self, self.generation == expected else { return }
            let completion = self.onDismiss
            self.cancel()
            completion?()
        }
        if animated && !IslandPreferences.shared.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.16
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock(done)
            card.layer?.add(fade, forKey: "dismiss")
            CATransaction.commit()
        } else { done() }
    }
    @objc private func closeClicked() { finish(animated: false) }
}
