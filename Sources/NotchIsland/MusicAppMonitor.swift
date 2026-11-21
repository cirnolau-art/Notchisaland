import AppKit

/// Display player events immediately, with scripting used for precise position, art and controls.
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
    private var playback = MusicPlaybackState()
    private var issues: [String] = []
    var hasActiveApp: Bool { !activeAppName.isEmpty }
    private var expanded = false
    private var playing = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshQueued = false
    private var observers: [NSObjectProtocol] = []

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
            playback = MusicPlaybackState()
            issues.removeAll()
            activeAppName = ""
            playing = false
            onInfo?(nil)
        }
    }
    func start() {
        guard observers.isEmpty else { return }; enabled = true
        for (name, app) in [("com.apple.Music.playerInfo", "Music"), ("com.apple.iTunes.playerInfo", "Music"),
                            ("com.spotify.client.PlaybackStateChanged", "Spotify")] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                guard let self, self.enabled,
                      !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID(app)).isEmpty else { return }
                if let event = MusicPlaybackEvent(userInfo: note.userInfo), self.playback.apply(event, from: app) {
                    self.publish()
                }
                self.query()
            })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let app = MusicPlaybackState.apps.first(where: { Self.bundleID($0) == application.bundleIdentifier }) else { return }
                if name == NSWorkspace.didTerminateApplicationNotification {
                    self.playback.apply(.stopped, from: app)
                    self.publish()
                }
                self.query()
            })
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
        let revision = playback.revision
        inFlight = true
        let running = Set(MusicPlaybackState.apps.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID($0)).isEmpty })
        queue.async { [weak self] in
            guard let self else { return }
            var readings: [String: MediaInfo?] = [:]
            var issues = [String]()
            for app in MusicPlaybackState.apps {
                guard running.contains(app) else {
                    readings.updateValue(nil, forKey: app)
                    continue
                }
                if self.deniedApps.contains(app) { issues.append("\(app)：需要自动化权限"); continue }
                let issueCount = issues.count
                let info = self.fetch(app: app, issues: &issues)
                if issues.count == issueCount { readings.updateValue(info, forKey: app) }
            }
            DispatchQueue.main.async {
                self.inFlight = false
                guard self.enabled, generation == self.generation else { if self.enabled { self.query() }; return }
                for app in MusicPlaybackState.apps {
                    if let reading = readings[app] { self.playback.applyReading(reading, from: app, startedAt: revision) }
                }
                self.issues = issues
                self.publish()
                if self.refreshQueued { self.refreshQueued = false; self.query() }
            }
        }
    }
    private func publish() {
        let selected = playback.selected
        activeAppName = selected?.source ?? ""
        let isPlaying = selected?.isPlaying == true
        if playing != isPlaying {
            playing = isPlaying
            schedule()
        }
        let summary = selected.map { "\($0.source) · \($0.isPlaying ? "播放中" : "已暂停")" }
        let status = ([summary].compactMap { $0 } + issues).joined(separator: "；")
        let message = status.isEmpty ? "等待 Music 或 Spotify 播放" : status
        if lastStatus != message { lastStatus = message; onStatus?(message) }
        onInfo?(selected)
    }
    private func fetch(app: String, issues: inout [String]) -> MediaInfo? {
        let source = """
        with timeout of 2 seconds
        tell application "\(app)"
            if player state is stopped then return {}
            set trackName to name of current track
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to 0
            set trackPosition to 0
            try
                set trackArtist to artist of current track
            end try
            try
                set trackAlbum to album of current track
            end try
            try
                set trackDuration to duration of current track
            end try
            try
                set trackPosition to player position
            end try
            return {trackName, trackArtist, trackAlbum, trackDuration, trackPosition, (player state is playing)}
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
        if result.numberOfItems == 0 { return nil }
        guard result.numberOfItems >= 6, let title = result.atIndex(1)?.stringValue, !title.isEmpty else {
            issues.append("\(app)：暂时无法读取")
            return nil
        }
        let duration = result.atIndex(4)?.doubleValue ?? 0
        var info = MediaInfo(title: title, artist: result.atIndex(2)?.stringValue ?? "", isPlaying: result.atIndex(6)?.booleanValue == true,
                             album: result.atIndex(3)?.stringValue ?? "", duration: app == "Spotify" ? duration / 1000 : duration,
                             elapsed: result.atIndex(5)?.doubleValue ?? 0, source: app)
        let key = "\(app)|\(info.title)|\(info.artist)|\(info.album)"
        info.trackID = key
        if let cached = artworkCache[key] { info.artwork = cached }
        else if Date().timeIntervalSince(artworkAttempts[key] ?? .distantPast) >= 20 {
            artworkAttempts[key] = Date()
            if app == "Music" {
                var artError: NSDictionary?
                let descriptor = NSAppleScript(source: "with timeout of 2 seconds\ntell application \"Music\" to get data of artwork 1 of current track\nend timeout")?.executeAndReturnError(&artError)
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
        let text = NSAppleScript(source: "with timeout of 2 seconds\ntell application \"Spotify\" to get artwork url of current track\nend timeout")?.executeAndReturnError(&error).stringValue
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

enum MusicPlaybackEvent {
    case stopped
    case track(playing: Bool, title: String?, artist: String?, album: String?, duration: Double?, elapsed: Double?)

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo, let state = (userInfo["Player State"] as? String)?.lowercased() else { return nil }
        if state == "stopped" { self = .stopped; return }
        guard state == "playing" || state == "paused" else { return nil }
        func string(_ key: String) -> String? {
            guard let value = (userInfo[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        func time(_ key: String) -> Double? {
            let value = (userInfo[key] as? NSNumber)?.doubleValue ?? string(key).flatMap(Double.init)
            return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        self = .track(playing: state == "playing", title: string("Name"), artist: string("Artist"), album: string("Album"),
                      duration: (time("Total Time") ?? time("Duration")).map { $0 / 1_000 }, elapsed: time("Playback Position"))
    }
}

/// Keeps a poll that took longer to return from undoing a newer playback notification.
struct MusicPlaybackState {
    static let apps = ["Music", "Spotify"]
    private(set) var revision = 0
    private var eventRevisions: [String: Int] = [:]
    private var byApp: [String: MediaInfo] = [:]
    private var lastActive = ""

    var selected: MediaInfo? {
        MediaSourcePolicy.select(Self.apps.compactMap { byApp[$0] }, lastActive: lastActive)
    }

    @discardableResult
    mutating func apply(_ event: MusicPlaybackEvent, from app: String, at now: Date = Date()) -> Bool {
        revision += 1
        eventRevisions[app] = revision
        switch event {
        case .stopped:
            return byApp.removeValue(forKey: app) != nil
        case .track(let playing, let title, let artist, let album, let duration, let elapsed):
            let previous = byApp[app]
            guard let title = title ?? previous?.title else { return false }
            let sameTrack = previous.map { Self.matches($0, title: title, artist: artist, album: album) } ?? false
            var song = sameTrack ? previous?.interpolated(at: now) ?? MediaInfo() : MediaInfo()
            song.title = title
            song.artist = artist ?? song.artist
            song.album = album ?? song.album
            song.source = app
            song.duration = duration ?? song.duration
            song.elapsed = elapsed ?? song.elapsed
            song.isPlaying = playing
            song.sampledAt = now
            if song.trackID.isEmpty { song.trackID = Self.trackID(for: song) }
            update(song, from: app)
            return true
        }
    }

    mutating func applyReading(_ reading: MediaInfo?, from app: String, startedAt revision: Int) {
        guard (eventRevisions[app] ?? 0) <= revision else { return }
        guard var song = reading else { byApp[app] = nil; return }
        if let previous = byApp[app], Self.matches(previous, title: song.title, artist: song.artist, album: song.album) {
            song.trackID = previous.trackID
            if song.artwork == nil {
                song.artwork = previous.artwork
                song.dominantColor = previous.dominantColor
            }
            if song.artist.isEmpty { song.artist = previous.artist }
            if song.album.isEmpty { song.album = previous.album }
            if song.duration == 0 { song.duration = previous.duration }
        }
        update(song, from: app)
    }

    private mutating func update(_ song: MediaInfo, from app: String) {
        if song.isPlaying && byApp[app]?.isPlaying != true { lastActive = app }
        byApp[app] = song
    }

    private static func trackID(for song: MediaInfo) -> String {
        "\(song.source)|\(song.title)|\(song.artist)|\(song.album)"
    }

    private static func matches(_ song: MediaInfo, title: String, artist: String?, album: String?) -> Bool {
        song.title == title
            && (artist?.isEmpty != false || song.artist.isEmpty || song.artist == artist)
            && (album?.isEmpty != false || song.album.isEmpty || song.album == album)
    }
}
