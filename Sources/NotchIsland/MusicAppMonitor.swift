import AppKit

/// Query both players before selecting one; keep all scripting and caches on one serial queue.
final class MusicAppMonitor {
    var onInfo: ((MediaInfo?) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "notchisland.music", qos: .utility)
    private var timer: Timer?
    private var inFlight = false
    private var activeAppName = ""
    private var lastStatus = ""
    private var artworkCache = [String: CGImage]()
    private var pendingArtwork = Set<String>()
    private var artworkAttempts = [String: Date]()
    private var deniedApps = Set<String>()
    private var lastActive = ""
    var hasActiveApp: Bool { !activeAppName.isEmpty }
    private var expanded = false
    private var playing = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshQueued = false
    private var observers: [NSObjectProtocol] = []
    private var previousPlaying = [String: Bool]()

    private var enabled = false
    private var generation = 0
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; generation += 1
        if value { start() }
        else {
            timer?.invalidate(); timer = nil; expanded = false; refreshQueued = false
            workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers.removeAll()
            observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }; observers.removeAll()
            onInfo?(nil)
        }
    }
    func start() {
        guard observers.isEmpty else { return }; enabled = true
        for name in ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.query() })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.query() })
        }
        schedule(); query()
    }
    deinit { workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; timer?.invalidate(); observers.forEach { DistributedNotificationCenter.default().removeObserver($0) } }
    func setExpanded(_ value: Bool) { guard value != expanded else { return }; expanded = value; schedule(); if value { query() } }
    private func schedule() {
        timer?.invalidate(); timer = nil
        guard enabled else { return }
        let value = Timer(timeInterval: expanded ? 0.8 : (playing ? 3 : 8), repeats: true) { [weak self] _ in self?.query() }
        value.tolerance = expanded ? 0.1 : 1
        timer = value; RunLoop.main.add(value, forMode: .common)
    }
    func refresh() { query() }
    func requestAuthorization() { queue.async { [weak self] in self?.deniedApps.removeAll() }; query() }
    private func query() {
        guard enabled else { return }
        guard !inFlight else { refreshQueued = true; return }
        let generation = self.generation
        inFlight = true
        let running = ["Music", "Spotify"].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID($0)).isEmpty }
        queue.async { [weak self] in
            guard let self else { return }
            var candidates = [MediaInfo]()
            var issues = [String]()
            for app in running {
                if self.deniedApps.contains(app) { issues.append("\(app)：需要自动化权限"); continue }
                if let info = self.fetch(app: app, issues: &issues) { candidates.append(info) }
            }
            if let justStarted = candidates.first(where: { $0.isPlaying && self.previousPlaying[$0.source] != true }) { self.lastActive = justStarted.source }
            self.previousPlaying = Dictionary(uniqueKeysWithValues: candidates.map { ($0.source, $0.isPlaying) })
            let selected = MediaSourcePolicy.select(candidates, lastActive: self.lastActive)
            if let selected { self.lastActive = selected.source }
            let status = issues.isEmpty ? (selected.map { "\($0.source) · \($0.isPlaying ? "播放中" : "已暂停")" } ?? "等待 Music 或 Spotify 播放") : issues.joined(separator: "；")
            DispatchQueue.main.async {
                self.inFlight = false
                guard self.enabled, generation == self.generation else { if self.enabled { self.query() }; return }
                self.activeAppName = selected?.source ?? ""
                if self.playing != (selected?.isPlaying == true) { self.playing = selected?.isPlaying == true; self.schedule() }
                if self.lastStatus != status { self.lastStatus = status; self.onStatus?(status) }
                self.onInfo?(selected)
                if self.refreshQueued { self.refreshQueued = false; self.query() }
            }
        }
    }
    private func fetch(app: String, issues: inout [String]) -> MediaInfo? {
        let source = """
        with timeout of 2 seconds
        tell application "\(app)"
            if player state is stopped then return {}
            return {name of current track, artist of current track, album of current track, duration of current track, player position, player state as text}
        end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { deniedApps.insert(app); issues.append("\(app)：需要自动化权限") }
            else { issues.append("\(app)：暂时无法读取") }
            return nil
        }
        guard result.numberOfItems >= 6, let title = result.atIndex(1)?.stringValue, !title.isEmpty else { return nil }
        let duration = result.atIndex(4)?.doubleValue ?? 0
        var info = MediaInfo(title: title, artist: result.atIndex(2)?.stringValue ?? "", isPlaying: result.atIndex(6)?.stringValue?.lowercased() == "playing",
                             album: result.atIndex(3)?.stringValue ?? "", duration: app == "Spotify" ? duration / 1000 : duration,
                             elapsed: result.atIndex(5)?.doubleValue ?? 0, source: app)
        let key = "\(app)|\(info.title)|\(info.artist)|\(info.album)"
        info.trackID = key
        if let cached = artworkCache[key] { info.artwork = cached }
        else if Date().timeIntervalSince(artworkAttempts[key] ?? .distantPast) >= 20 {
            artworkAttempts[key] = Date()
            if app == "Music" {
                var artError: NSDictionary?
                let descriptor = NSAppleScript(source: "tell application \"Music\" to get data of artwork 1 of current track")?.executeAndReturnError(&artError)
                if artError == nil, let data = descriptor?.data, let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    info.artwork = cg; artworkCache[key] = cg
                }
            } else { fetchSpotifyArtwork(key: key) }
        }
        if let image = info.artwork { info.dominantColor = Self.dominantColor(of: image) }
        if artworkCache.count > 24 { artworkCache = info.artwork.map { [key: $0] } ?? [:] }
        if artworkAttempts.count > 100 { artworkAttempts = [key: Date()] }
        return info
    }
    private func fetchSpotifyArtwork(key: String) {
        guard !pendingArtwork.contains(key) else { return }
        var error: NSDictionary?
        let text = NSAppleScript(source: "tell application \"Spotify\" to get artwork url of current track")?.executeAndReturnError(&error).stringValue
        guard error == nil, let text, let url = URL(string: text), url.scheme == "https" else { return }
        pendingArtwork.insert(key)
        var request = URLRequest(url: url); request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            self?.queue.async {
                guard let self else { return }
                self.pendingArtwork.remove(key)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, data.count < 8_000_000, let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) else { return }
                self.artworkCache[key] = image
                DispatchQueue.main.async { self.query() }
            }
        }.resume()
    }
    private func control(_ command: String) {
        let app = activeAppName
        guard !app.isEmpty else { return }
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "with timeout of 2 seconds\ntell application \"\(app)\" to \(command)\nend timeout")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.query() }
        }
    }
    func playPause() { control("playpause") }
    func next() { control("next track") }
    func prev() { control("previous track") }
    func seek(to seconds: Double) { guard seconds.isFinite else { return }; control("set player position to \(max(0, seconds))") }
    func openPlayer() {
        let id = Self.bundleID(activeAppName.isEmpty ? "Music" : activeAppName)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    }
    static func bundleID(_ app: String) -> String { app == "Spotify" ? "com.spotify.client" : "com.apple.Music" }
    static func dominantColor(of image: CGImage) -> CGColor {
        guard let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSColor.systemMint.cgColor }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let data = ctx.data else { return NSColor.systemMint.cgColor }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var rgb = [Double](repeating: 0, count: 3); var count = 0.0
        for i in 0..<256 {
            let pixel = (0..<3).map { Double(bytes[i * 4 + $0]) / 255 }
            let light = pixel.reduce(0, +) / 3
            guard bytes[i * 4 + 3] > 128, light > 0.12, light < 0.9 else { continue }
            for c in 0..<3 { rgb[c] += pixel[c] }; count += 1
        }
        guard count > 0 else { return NSColor.systemMint.cgColor }
        let color = NSColor(srgbRed: rgb[0] / count, green: rgb[1] / count, blue: rgb[2] / count, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(0.7, max(0.35, s)), brightness: max(0.82, b), alpha: 1).cgColor
    }
}

/// Follow a playing app automatically, remembering the most recently active source.
enum MediaSourcePolicy {
    static func select(_ candidates: [MediaInfo], lastActive: String) -> MediaInfo? {
        let playing = candidates.filter(\.isPlaying)
        return playing.first(where: { $0.source == lastActive }) ?? playing.first
            ?? candidates.first(where: { $0.source == lastActive }) ?? candidates.first
    }
}
