import AppKit
import Quartz

final class IslandWindow: NSPanel {
    static let windowSize = CGSize(width: 780, height: 370)
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.windowSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; ignoresMouseEvents = true; hidesOnDeactivate = false
        isFloatingPanel = true; becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        // isFloatingPanel resets the level to .floating; set our menu-bar level last.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        contentView = IslandView(frame: NSRect(origin: .zero, size: Self.windowSize))
    }
    // AppKit otherwise constrains accessory panels below the menu bar when the
    // app activates or Spaces changes, leaving a second notch under the real one.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    func reposition() {
        guard let screen = IslandPreferences.shared.screen else { return }
        let target = NSRect(x: screen.frame.midX - frame.width / 2, y: screen.frame.maxY - frame.height, width: frame.width, height: frame.height)
        if !frame.equalTo(target) { setFrame(target, display: false) }
        (contentView as? IslandView)?.relayoutIfNeeded()
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let shelf = (contentView as? IslandView)?.shelf
        panel.dataSource = shelf; panel.delegate = shelf
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    override func cancelOperation(_ sender: Any?) { (contentView as? IslandView)?.onDismiss?() }
}
