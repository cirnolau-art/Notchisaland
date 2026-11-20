import AppKit
import CoreGraphics

/// MediaRemote（私有框架）正在播放监听与控制。
/// macOS 27.2 实测：老的无参命令（MRMediaRemotePlay 等）已移除，控制走 MRMediaRemoteSendCommand；
/// block 参数必须显式声明为 @convention(block) 类型的变量传入，否则触发 noescape 逃逸检查崩溃。
final class NowPlayingMonitor {
    var onStateChange: ((MediaInfo?) -> Void)?

    private var mediaState = MediaInfo()

    // MARK: - 函数类型（typealias 拆分保证 escaping 语义）

    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias InfoHandler = @convention(block) (CFDictionary?) -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, InfoHandler) -> Void
    private typealias PlayingHandler = @convention(block) (Any?) -> Void
    private typealias GetPlayingFn = @convention(c) (DispatchQueue, PlayingHandler) -> Void
    private typealias SendCmdFn = @convention(c) (UInt, CFDictionary?) -> Void

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var pollTimer: Timer?
    private var didDumpKeys = false

    private var registerFn: RegisterFn?
    private var getInfoFn: GetInfoFn?
    private var getPlayingFn: GetPlayingFn?
    private var sendCmdFn: SendCmdFn?

    /// MRCommand 枚举（MediaRemote.h 头文件）：
    /// unknown=0, play=1, pause=2, togglePlayPause=3, stop=4, nextTrack=5, previousTrack=6
    private enum MRCommand: UInt {
        case play = 1
        case pause = 2
        case togglePlayPause = 3
        case stop = 4
        case nextTrack = 5
        case previousTrack = 6
    }

    private var enabled = false
    private var initialized = false
    private var generation = 0
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; generation += 1
        if value { if !initialized { start(); initialized = true } else { setPollingEnabled(true); fetch(); fetchPlaying() } }
        else { setPollingEnabled(false); onStateChange?(nil) }
    }
    func start() {
        guard !initialized else { return }; enabled = true; initialized = true
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            print("[Music] MediaRemote not loaded, music module disabled")
            return
        }
        frameworkHandle = handle
        if let p = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") { registerFn = unsafeBitCast(p, to: RegisterFn.self) }
        if let p = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") { getInfoFn = unsafeBitCast(p, to: GetInfoFn.self) }
        if let p = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") { getPlayingFn = unsafeBitCast(p, to: GetPlayingFn.self) }
        if let p = dlsym(handle, "MRMediaRemoteSendCommand") { sendCmdFn = unsafeBitCast(p, to: SendCmdFn.self) }
        print("[Music] MediaRemote loaded: register=\(registerFn != nil) info=\(getInfoFn != nil) playing=\(getPlayingFn != nil) sendCmd=\(sendCmdFn != nil)")

        registerFn?(.main)

        // macOS 27 上通知名常量是符号本身（旧教程的 com.apple.MediaRemote.* 已失效）
        let infoName = Self.symbolString(handle, "kMRMediaRemoteNowPlayingInfoDidChangeNotification")
            ?? "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
        let playingName = Self.symbolString(handle, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
            ?? "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        let appName = Self.symbolString(handle, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
            ?? "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        print("[Music] 通知名: \(infoName) / \(playingName)")

        let nc = NotificationCenter.default
        for name in [infoName, appName] {
            nc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.fetch()
            }
        }
        nc.addObserver(forName: NSNotification.Name(playingName), object: nil, queue: .main) { [weak self] _ in
            self?.fetchPlaying()
        }

        // 轮询兜底：即使通知没到，也能在 1.5s 内拿到播放状态与进度
        pollTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.fetch()
            self?.fetchPlaying()
        }
        fetch()
        fetchPlaying()
    }

    /// dlsym 数据常量是「指向 CFStringRef 的指针」，需要解引用
    private static func symbolString(_ handle: UnsafeMutableRawPointer, _ name: String) -> String? {
        guard let p = dlsym(handle, name) else { return nil }
        return p.assumingMemoryBound(to: CFString.self).pointee as String
    }

    /// AppleScript 数据源接管后停掉轮询（MediaRemote 在 macOS 27 上恒返回 nil）
    func setPollingEnabled(_ enabled: Bool) {
        if enabled {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
                self?.fetch()
                self?.fetchPlaying()
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func fetch() {
        guard enabled else { return }
        let generation = self.generation
        guard let getInfoFn else { return }
        let handler: InfoHandler = { [weak self] dict in
            guard let self, self.enabled, generation == self.generation else { return }
            guard let d = dict as? [String: Any] else {
                DispatchQueue.main.async { guard self.enabled, generation == self.generation else { return }; self.mediaState = MediaInfo(); self.onStateChange?(nil) }
                return
            }
            if d.isEmpty || Self.string(d, "title", "kMRMediaRemoteNowPlayingInfoTitle") == nil {
                DispatchQueue.main.async {
                    guard self.enabled, generation == self.generation else { return }
                    self.mediaState = MediaInfo()
                    self.onStateChange?(nil)
                }
                return
            }
            if !self.didDumpKeys {
                self.didDumpKeys = true
                print("[Music] nowPlayingInfo keys: \(d.keys.sorted().joined(separator: ", "))")
            }
            DispatchQueue.main.async {
                guard self.enabled, generation == self.generation else { return }
                var m = self.mediaState
                m.title = Self.string(d, "title", "kMRMediaRemoteNowPlayingInfoTitle") ?? m.title
                m.artist = Self.string(d, "artist", "kMRMediaRemoteNowPlayingInfoArtist") ?? m.artist
                m.duration = Self.number(d, "duration", "kMRMediaRemoteNowPlayingInfoDuration") ?? m.duration
                m.elapsed = Self.number(d, "elapsed", "elapsedTime", "kMRMediaRemoteNowPlayingInfoElapsedTime") ?? m.elapsed
                m.sampledAt = Date()
                let artData = d["artwork"] as? Data ?? d["artworkData"] as? Data
                if let data = artData {
                    if let src = CGImageSourceCreateWithData(data as CFData, nil),
                       let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        m.artwork = img
                    }
                } else {
                    m.artwork = nil
                }
                self.mediaState = m
                self.emit()
            }
        }
        getInfoFn(.main, handler)
    }

    private static func string(_ d: [String: Any], _ keys: String...) -> String? {
        for k in keys { if let v = d[k] as? String, !v.isEmpty { return v } }
        return nil
    }

    private static func number(_ d: [String: Any], _ keys: String...) -> Double? {
        for k in keys {
            if let v = d[k] as? Double { return v }
            if let v = d[k] as? NSNumber { return v.doubleValue }
        }
        return nil
    }

    private func fetchPlaying() {
        guard enabled else { return }
        let generation = self.generation
        guard let getPlayingFn else { return }
        let handler: PlayingHandler = { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.enabled, generation == self.generation else { return }
                let playing: Bool
                if let b = value as? Bool { playing = b }
                else if let n = value as? NSNumber { playing = n.boolValue }
                else { playing = false }
                self.mediaState.isPlaying = playing
                self.emit()
            }
        }
        getPlayingFn(.main, handler)
    }

    private func emit() {
        // isPlaying 回调在部分 App 上不触发，只要拿到曲目就认为有正在播放内容
        let hasContent = !mediaState.title.isEmpty
        onStateChange?(hasContent ? mediaState : nil)
    }

    // MARK: - 控制

    func playPause() {
        sendCmdFn?(MRCommand.togglePlayPause.rawValue, nil)
    }

    func next() {
        sendCmdFn?(MRCommand.nextTrack.rawValue, nil)
    }

    func prev() {
        sendCmdFn?(MRCommand.previousTrack.rawValue, nil)
    }
}
