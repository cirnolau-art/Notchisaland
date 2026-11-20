import AppKit
import Quartz

struct ShelfItem: Codable, Identifiable {
    let id: UUID
    var bookmark: Data?
    var path: String
    var url: URL { URL(fileURLWithPath: path) }
}

/// Stores references, never moves or deletes the user's originals.
final class FileShelf: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSSharingServicePickerDelegate {
    var onChange: (() -> Void)?
    var onInteraction: ((Bool) -> Void)?
    private var sharePicker: NSSharingServicePicker?
    private(set) var items: [ShelfItem] = []
    private let defaults: UserDefaults
    private let key = "notchisland.fileShelf"
    private var previewURLs: [URL] = []
    private var previewIndex = 0
    var readableItems: [ShelfItem] { items.filter { FileManager.default.fileExists(atPath: $0.path) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        if !SnapshotMode.enabled, let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.map { item in
                var updated = item
                if let bookmark = item.bookmark {
                    var stale = false
                    if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
                        updated.path = url.path
                        if stale { updated.bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
                    }
                }
                return updated
            }
        }
    }
    @discardableResult func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalized.path), !items.contains(where: { $0.url.resolvingSymlinksInPath().path == normalized.resolvingSymlinksInPath().path }) else { continue }
            guard items.count < 30 else { break }
            items.insert(ShelfItem(id: UUID(), bookmark: try? normalized.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), path: normalized.path), at: 0)
            added += 1
        }
        if added > 0 { save() }
        return added
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    func clear() { items.removeAll(); save() }
    func removeMissing() { items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }; save() }
    private func save() { if !SnapshotMode.enabled, let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }; onChange?() }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func share(_ urls: [URL], from view: NSView) {
        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !valid.isEmpty else { return }
        let picker = NSSharingServicePicker(items: valid)
        picker.delegate = self; sharePicker = picker; onInteraction?(true)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) { sharePicker = nil; onInteraction?(false) }
    func preview(_ url: URL) {
        previewURLs = readableItems.map(\.url)
        previewIndex = previewURLs.firstIndex(of: url) ?? 0
        guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self; panel.delegate = self; panel.reloadData(); panel.currentPreviewItemIndex = previewIndex
        panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
}

final class ShelfRowView: NSView, NSDraggingSource {
    let item: ShelfItem
    var onPreview: (() -> Void)?
    var onInteraction: ((Bool) -> Void)?
    private var downPoint = NSPoint.zero
    private var dragging = false
    private let name: NSTextField
    private let icon: NSImageView
    init(item: ShelfItem, index: Int, shelf: FileShelf) {
        self.item = item
        name = NSTextField(labelWithString: item.url.lastPathComponent)
        icon = NSImageView(image: NSWorkspace.shared.icon(forFile: item.path))
        super.init(frame: NSRect(x: 0, y: 0, width: 388, height: 48))
        wantsLayer = true; layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor; layer?.cornerRadius = 12
        icon.frame = NSRect(x: 10, y: 10, width: 28, height: 28); addSubview(icon)
        name.frame = NSRect(x: 48, y: 23, width: 190, height: 17); name.font = .systemFont(ofSize: 12, weight: .medium); name.textColor = .white; name.lineBreakMode = .byTruncatingMiddle; addSubview(name)
        let missing = !FileManager.default.fileExists(atPath: item.path)
        let hint = NSTextField(labelWithString: missing ? "文件已移动或不可访问" : "拖出使用 · 空格预览")
        hint.frame = NSRect(x: 48, y: 7, width: 190, height: 14); hint.font = .systemFont(ofSize: 10); hint.textColor = missing ? .systemOrange : .white.withAlphaComponent(0.4); addSubview(hint)
        for (offset, symbol, description) in [(0, "eye", "预览文件"), (1, "folder", "在 Finder 中显示"), (2, "square.and.arrow.up", "分享文件"), (3, "xmark", "移出暂存区")] {
            let b = ActionButton(symbol: symbol, help: description) { [weak shelf] sender in
                guard let shelf else { return }
                switch offset { case 0: shelf.preview(item.url); case 1: shelf.reveal(item.url); case 2: shelf.share([item.url], from: sender); default: shelf.remove(item.id) }
            }
            b.frame = NSRect(x: 242 + CGFloat(offset) * 34, y: 9, width: 30, height: 30)
            b.isEnabled = offset == 3 || !missing; addSubview(b)
        }
        onInteraction = { [weak shelf] active in shelf?.onInteraction?(active) }
        onPreview = { [weak shelf] in shelf?.preview(item.url) }
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel(item.url.lastPathComponent)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target = super.hitTest(point) else { return nil }
        return target is NSButton ? target : self
    }
    override func mouseDown(with event: NSEvent) { downPoint = convert(event.locationInWindow, from: nil); dragging = false; window?.makeKey(); window?.makeFirstResponder(self) }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard !dragging, hypot(p.x - downPoint.x, p.y - downPoint.y) > 5, FileManager.default.fileExists(atPath: item.path) else { return }
        dragging = true; onInteraction?(true)
        let drag = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        drag.setDraggingFrame(NSRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36), contents: icon.image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) { if !dragging && event.clickCount == 2 { onPreview?() } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 { onPreview?() } else { super.keyDown(with: event) } }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false; onInteraction?(false) }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
