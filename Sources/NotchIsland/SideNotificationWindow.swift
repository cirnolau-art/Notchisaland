import AppKit
import QuartzCore

private final class SideNotificationContentView: FlippedView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A compact notification surface for users who do not want the top island to
/// cover content. It intentionally owns its window so the main island geometry
/// and hit testing stay unchanged.
final class SideNotificationWindow: NSPanel {
    private var closeWork: DispatchWorkItem?
    private var openAction: (() -> Void)?
    private var dismissAction: (() -> Void)?
    private let sourceLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView(frame: .zero)
    private let close = NSButton(frame: .zero)
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 92), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false; isFloatingPanel = true; ignoresMouseEvents = false
        let view = SideNotificationContentView(frame: NSRect(origin: .zero, size: frame.size)); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor; view.layer?.cornerRadius = 18; view.layer?.borderWidth = 0.7; view.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor; contentView = view
        view.onClick = { [weak self] in self?.openAction?(); self?.hide() }
        icon.frame = NSRect(x: 16, y: 18, width: 28, height: 28); icon.contentTintColor = .white; view.addSubview(icon)
        sourceLabel.frame = NSRect(x: 56, y: 14, width: 220, height: 16); sourceLabel.font = .systemFont(ofSize: 10, weight: .medium); sourceLabel.textColor = .white.withAlphaComponent(0.55); view.addSubview(sourceLabel)
        titleLabel.frame = NSRect(x: 56, y: 31, width: 235, height: 21); titleLabel.font = .systemFont(ofSize: 14, weight: .semibold); titleLabel.textColor = .white; titleLabel.lineBreakMode = .byTruncatingTail; view.addSubview(titleLabel)
        bodyLabel.frame = NSRect(x: 56, y: 55, width: 245, height: 18); bodyLabel.font = .systemFont(ofSize: 11); bodyLabel.textColor = .white.withAlphaComponent(0.65); bodyLabel.lineBreakMode = .byTruncatingTail; view.addSubview(bodyLabel)
        close.bezelStyle = .regularSquare; close.isBordered = false; close.title = "×"; close.font = .systemFont(ofSize: 17, weight: .light); close.contentTintColor = .white.withAlphaComponent(0.65); close.frame = NSRect(x: 285, y: 10, width: 25, height: 25); close.target = self; close.action = #selector(closeClicked); view.addSubview(close)
    }
    func show(_ item: IslandNotification, seconds: TimeInterval = 6, onDismiss: @escaping () -> Void) {
        closeWork?.cancel(); openAction = item.openApplication; dismissAction = onDismiss
        sourceLabel.stringValue = item.source; titleLabel.stringValue = item.title; bodyLabel.stringValue = item.body
        icon.image = item.icon ?? NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
        guard let screen = IslandPreferences.shared.screen else { return }
        let width = frame.width; let margin: CGFloat = 18
        let right = UserDefaults.standard.integer(forKey: "notchisland.notificationSide") != 1
        let x = right ? screen.visibleFrame.maxX - width - margin : screen.visibleFrame.minX + margin
        let y = screen.visibleFrame.maxY - frame.height - margin
        setFrameOrigin(NSPoint(x: x, y: y)); alphaValue = 0; orderFrontRegardless()
        if !IslandPreferences.shared.reduceMotion { NSAnimationContext.runAnimationGroup { $0.duration = 0.24; animator().alphaValue = 1 } } else { alphaValue = 1 }
        let work = DispatchWorkItem { [weak self] in self?.hide() }; closeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    private func hide() {
        closeWork?.cancel(); closeWork = nil
        let completion = dismissAction; dismissAction = nil; openAction = nil
        if !IslandPreferences.shared.reduceMotion { NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; animator().alphaValue = 0 }, completionHandler: { [weak self] in self?.orderOut(nil); completion?() }) } else { orderOut(nil); completion?() }
    }
    @objc private func closeClicked() { hide() }
}
