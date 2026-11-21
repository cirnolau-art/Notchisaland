import AppKit

final class IslandController: NSObject {
    static let shared = IslandController()
    let window = IslandWindow()
    private var islandView: IslandView { window.contentView as! IslandView }
    let volumeMonitor = VolumeMonitor()
    let brightnessMonitor = BrightnessMonitor()
    let inputMonitor = InputSourceMonitor()
    let nowPlaying = NowPlayingMonitor()
    let batteryMonitor = BatteryMonitor()
    let mediaKeys = MediaKeyInterceptor()
    let musicApp = MusicAppMonitor()
    private let lyricsLookup = LyricsLookup()
    let alarmManager = AlarmManager()
    let focusMonitor = SystemFocusMonitor()
    let fileShelf = FileShelf()
    let clipboardHistory = ClipboardHistory()
    let airPods = AirPodsMonitor()
    let notificationBridge = NotificationBridge()
    let audioOutputs = AudioOutputMonitor()
    let calendar = CalendarMonitor()
    let quickActions = QuickActions()
    private var meetingTimer: Timer?
    private var pendingActivities: [(state: IslandState, date: Date)] = []
    private var dragWasActive = false
    private var presentationRules = ""
    private var policy = PresentationPolicy()
    private var currentState: IslandState = .idle(.time(""))
    private var transient: IslandState?
    private var transientEnd = Date.distantPast
    private var panelDeadline = Date.distantFuture
    private var pointerEntered: Date?
    private var pointerInside = false
    private var hoveringPreview = false
    private var hoverDismissed = false
    private var interacting = false
    private var dropActive = false
    private var hidden = false
    private var suppressed = false
    private var compactOnly = false
    private var pointerTimer: Timer?
    private var progressTimer: Timer?
    private var environmentTimer: Timer?
    private var eventMonitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var nowPlayingInfo: MediaInfo?
    private var musicAppInfo: MediaInfo?
    private var fallbackInfo: MediaInfo?
    private var compactActivity = CompactMediaActivity()
    private var playbackIntent: (playing: Bool, source: String, trackID: String, expires: Date)?
    private var selectedTab = IslandTab(rawValue: UserDefaults.standard.integer(forKey: "notchisland.selectedTab")) ?? .music
    private(set) var musicAppStatus = ""
    private var isDebug = false
    private var wasVisible = true
    private var manualAirPodsPresentation = false
    private var dragBoardBaseline = NSPasteboard(name: .drag).changeCount
    var isHidden: Bool { hidden }
    var mediaKeyTakeoverEnabled: Bool { mediaKeys.isActive }
    var airPodsStatus: String { airPods.status }
    var notificationStatus: String { notificationBridge.status }
    var autoHideSeconds: TimeInterval { IslandPreferences.shared.autoHide }
    var debugView: IslandView? { islandView }

    private override init() { super.init(); setupCallbacks() }
    func start() {
        selectedTab = IslandPreferences.shared.resolvedTab(selectedTab) ?? selectedTab
        window.reposition(); renderUnderlying(); window.orderFrontRegardless()
        volumeMonitor.start()
        focusMonitor.setEnabled(IslandPreferences.shared.isEnabled(.focus))
        brightnessMonitor.setEnabled(IslandPreferences.shared.systemHUDEnabled)
        inputMonitor.setEnabled(IslandPreferences.shared.inputHUDEnabled)
        batteryMonitor.setEnabled(IslandPreferences.shared.powerHUDEnabled)
        audioOutputs.setEnabled(IslandPreferences.shared.isEnabled(.audio))
        calendar.setEnabled(IslandPreferences.shared.calendarEnabled && IslandPreferences.shared.isEnabled(.calendar))
        updateConnectedPanels()
        nowPlaying.setEnabled(IslandPreferences.shared.isEnabled(.music)); musicApp.setEnabled(IslandPreferences.shared.isEnabled(.music))
        clipboardHistory.setEnabled(IslandPreferences.shared.isEnabled(.clipboard))
        airPods.setEnabled(IslandPreferences.shared.airPodsEnabled)
        notificationBridge.setEnabled(IslandPreferences.shared.notificationsEnabled)
        if IslandPreferences.shared.takeover && IslandPreferences.shared.systemHUDEnabled {
            setupMediaKeyTakeover()
        }
        if ((IslandPreferences.shared.takeover && IslandPreferences.shared.systemHUDEnabled) || IslandPreferences.shared.notificationsEnabled) && !MediaKeyInterceptor.isTrusted { _ = MediaKeyInterceptor.requestTrust() }
        print("[Island] screen=\(String(describing: IslandPreferences.shared.screen?.frame)) window=\(window.frame) \(islandView.debugGeometry())")
        observe(.islandPreferencesChanged, center: .default) { [weak self] in self?.applyPreferences() }
        observe(.islandAppearanceChanged, center: .default) { [weak self] in self?.islandView.applyAppearance() }
        observe(NSApplication.didBecomeActiveNotification, center: .default) { [weak self] in self?.window.reposition(); self?.focusMonitor.refresh() }
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in self?.updateEnvironment() }
        observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.islandView.refreshCompact()
            self?.islandView.applyAppearance()
        }
        observe(NSWorkspace.didActivateApplicationNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.updateEnvironment() }
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.updateEnvironment() }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.window.reposition(); self?.musicApp.refresh(); self?.airPods.didWake(); self?.focusMonitor.didWake(); self?.updateEnvironment() }
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { [weak self] in self?.suspendAirPodsForSleep(); self?.window.orderOut(nil); self?.islandView.setActivityVisible(false) }
        let environment = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.updateEnvironment() }; environment.tolerance = 1; RunLoop.main.add(environment, forMode: .common); environmentTimer = environment
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            guard let self else { return }
            if event.type == .scrollWheel {
                if self.islandView.containsVisiblePoint(NSEvent.mouseLocation), !self.hidden, !self.suppressed { self.islandView.handleScroll(event) }
            } else if event.type == .mouseMoved || event.type == .leftMouseDragged || event.type == .leftMouseUp { self.updatePointer() }
            else { self.outsideClick() }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            guard let self else { return event }
            if [.mouseMoved, .leftMouseDragged, .leftMouseUp].contains(event.type) { self.updatePointer(); return event }
            if event.type == .keyDown, event.keyCode == 53, event.window === self.window { self.dismissToIdle(); return nil }
            if event.type != .keyDown, event.window !== self.window { self.outsideClick() }
            return event
        }) { eventMonitors.append(monitor) }
        updateEnvironment(); updatePointer()
    }
    private func observe(_ name: Notification.Name, center: NotificationCenter, block: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in block() }))
    }
    deinit {
        meetingTimer?.invalidate()
        pointerTimer?.invalidate(); progressTimer?.invalidate(); environmentTimer?.invalidate()
        eventMonitors.forEach(NSEvent.removeMonitor)
        observers.forEach { $0.0.removeObserver($0.1) }
    }
    func startDebug() { isDebug = true; window.reposition(); islandView.shelf = fileShelf; window.orderFrontRegardless(); renderUnderlying() }
    func debugPresent(_ state: IslandState) { currentState = state; islandView.timerSession = alarmManager.session; islandView.render(state) }
    func debugAcceptPlaybackSample(_ info: MediaInfo?) {
        guard isDebug else { return }
        musicApp.onInfo?(info)
    }
    private func setupCallbacks() {
        lyricsLookup.onChange = { [weak self] lines in
            guard let self, self.nowPlayingInfo?.lyrics != lines else { return }
            self.nowPlayingInfo?.lyrics = lines
            self.updateMediaPresentation()
        }
        islandView.shelf = fileShelf
        focusMonitor.onChange = { [weak self] state in self?.islandView.updateFocus(state) }
        islandView.clipboard = clipboardHistory
        clipboardHistory.onChange = { [weak self] in self?.islandView.refreshClipboard() }
        audioOutputs.onChange = { [weak self] in self?.updateConnectedPanels() }
        calendar.onChange = { [weak self] in self?.updateConnectedPanels() }
        calendar.onReminder = { [weak self] meeting in
            guard let self else { return }
            var item = IslandNotification(source: "日历", title: meeting.title, body: "\(meeting.countdown()) · \(meeting.timeLabel)", identity: "meeting-\(meeting.id)", icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: nil))
            item.actionTitle = meeting.link == nil ? "打开日程" : "加入会议"
            item.openApplication = { [weak self] in self?.calendar.open(meeting) }
            self.enqueueActivity(.notification(item))
        }
        quickActions.onChange = { [weak self] in self?.updateConnectedPanels() }
        islandView.onSelectOutput = { [weak self] in self?.audioOutputs.select($0); self?.keepAlive() }
        islandView.onOutputVolume = { [weak self] in self?.volumeMonitor.setVolume($0); self?.keepAlive() }
        islandView.onEnableCalendar = { [weak self] in self?.enableCalendar() }
        islandView.onOpenMeeting = { [weak self] in self?.calendar.open($0); self?.keepAlive() }
        islandView.onConfigureQuickActions = { SettingsWindowController.shared.show(page: 4) }
        islandView.onQuickAction = { [weak self] action in
            self?.quickActions.execute(action) { [weak self] error in
                guard let self else { return }
                guard IslandPreferences.shared.isEnabled(.shortcuts) else { return }
                self.islandView.quickActionStatus = error
                self.updateConnectedPanels(); self.keepAlive()
                if error == nil { self.dismissToIdle() }
            }
        }
        volumeMonitor.onAvailabilityChange = { [weak self] in
            self?.updateConnectedPanels(); self?.airPods.audioOutputDidChange()
        }
        airPods.onChange = { [weak self] snapshot, _ in
            guard let self else { return }
            if case .airPods(let shown) = self.transient, let snapshot,
               (shown.address == "waiting" || (self.manualAirPodsPresentation && shown.address != "preview") ||
                AirPodsProfileParser.normalizedAddress(shown.address) == AirPodsProfileParser.normalizedAddress(snapshot.address)) {
                if shown.connected && !snapshot.connected && !self.manualAirPodsPresentation { self.dismissActivity() }
                else {
                    if shown.address == "waiting" { self.transientEnd = Date().addingTimeInterval(7) }
                    self.transient = .airPods(snapshot); self.islandView.render(.airPods(snapshot))
                }
            }
        }
        airPods.onPresentation = { [weak self] snapshot in
            guard let self, !self.policy.transientVisible, !self.interacting, !self.dropActive else { return false }
            // Preserve the current music/workspace panel underneath the card. The
            // monitor consumes this event only after the window accepts it.
            guard self.presentTransient(.airPods(snapshot), seconds: 5) else { return false }
            self.manualAirPodsPresentation = false; self.window.orderFrontRegardless()
            return true
        }
        notificationBridge.onNotification = { [weak self] item in self?.enqueueActivity(.notification(item)) }
        islandView.onDismissActivity = { [weak self] in self?.dismissActivity() }
        mediaKeys.canHandleVolume = { [weak self] in
            guard let monitor = self?.volumeMonitor else { return false }
            return monitor.canAdjust && monitor.currentVolume() != nil
        }
        mediaKeys.canHandleBrightness = { [weak self] in
            guard let monitor = self?.brightnessMonitor else { return false }
            return monitor.canAdjust && monitor.read() != nil
        }
        mediaKeys.onVolumeNudge = { [weak self] value in self?.handleVolumeKey { $0.nudge(value) } ?? false }
        mediaKeys.onBrightnessNudge = { [weak self] value in
            guard let self, self.brightnessMonitor.nudge(value) else { return false }
            if let brightness = self.brightnessMonitor.read() { self.presentSystemHUD(.brightness(brightness)) }
            return true
        }
        mediaKeys.onMuteToggle = { [weak self] in self?.handleVolumeKey { $0.toggleMute() } ?? false }
        volumeMonitor.onVolumeChange = { [weak self] _, _ in self?.updateConnectedPanels() }
        inputMonitor.onInputSourceChange = { [weak self] name in guard IslandPreferences.shared.inputHUDEnabled else { return }; self?.presentTransient(.inputSource(name), seconds: 1.7) }
        batteryMonitor.onPowerChange = { [weak self] plugged, percent in guard IslandPreferences.shared.powerHUDEnabled else { return }; self?.presentTransient(.charging(plugged, percent), seconds: 2.5) }
        musicApp.onInfo = { [weak self] info in
            guard let self else { return }
            self.musicAppInfo = info
            self.selectMedia()
        }
        musicApp.onStatus = { [weak self] status in self?.musicAppStatus = status }
        nowPlaying.onStateChange = { [weak self] info in self?.fallbackInfo = info; self?.selectMedia() }
        alarmManager.onTimerTick = { [weak self] _ in
            guard let self else { return }
            let session = IslandPreferences.shared.isEnabled(.timer) ? self.alarmManager.session : nil
            let changedPresence = (self.islandView.timerSession == nil) != (session == nil)
            self.islandView.timerSession = session
            if changedPresence, self.policy.surface == .idle, !self.policy.transientVisible {
                self.renderUnderlying()
                return
            }
            self.islandView.refreshTimer()
        }
        alarmManager.onAlarmFired = { [weak self] title in self?.showAlert(.alarm(title)) }
        alarmManager.onTimerFired = { [weak self] title in self?.showAlert(.timerDone(title)) }
        alarmManager.onRingingStopped = { [weak self] in self?.policy.stopAlert(); self?.renderUnderlying(); (NSApp.delegate as? AppDelegate)?.rebuildMenu() }
        fileShelf.onInteraction = { [weak self] value in self?.interacting = value; self?.keepAlive() }
        fileShelf.onChange = { [weak self] in self?.islandView.refreshFiles(); self?.renderIfIdle() }
        islandView.onDismiss = { [weak self] in self?.dismissToIdle() }
        islandView.onExpand = { [weak self] in self?.showPanel() }
        islandView.onSelectTab = { [weak self] tab in self?.showPanel(tab) }
        islandView.onSettings = { SettingsWindowController.shared.show() }
        islandView.onPlayPause = { [weak self] in self?.togglePlayback() }
        islandView.onPrevious = { [weak self] in guard let self else { return }; self.nowPlayingInfo?.source.isEmpty == false ? self.musicApp.prev() : self.nowPlaying.prev(); self.keepAlive() }
        islandView.onNext = { [weak self] in guard let self else { return }; self.nowPlayingInfo?.source.isEmpty == false ? self.musicApp.next() : self.nowPlaying.next(); self.keepAlive() }
        islandView.onSeek = { [weak self] value in
            guard let self, var info = self.nowPlayingInfo else { return }
            info.elapsed = min(info.duration, max(0, value)); info.sampledAt = Date(); self.nowPlayingInfo = info; self.islandView.mediaInfo = info
            self.islandView.playbackPositionDidChange()
            self.musicApp.seek(to: info.elapsed); self.keepAlive()
        }
        islandView.onOpenPlayer = { [weak self] in self?.musicApp.openPlayer() }
        islandView.onTimerStart = { [weak self] seconds, label in self?.alarmManager.startTimer(seconds: seconds, label: label); self?.showPanel(.timer); (NSApp.delegate as? AppDelegate)?.rebuildMenu() }
        islandView.onTimerPause = { [weak self] in self?.alarmManager.pauseOrResume(); self?.keepAlive() }
        islandView.onTimerAdd = { [weak self] in self?.alarmManager.addMinute(); self?.keepAlive() }
        islandView.onTimerCancel = { [weak self] in self?.alarmManager.cancelTimer(); self?.keepAlive(); (NSApp.delegate as? AppDelegate)?.rebuildMenu() }
        islandView.onStopAlert = { [weak self] in self?.alarmManager.stopRinging() }
        islandView.onVolume = { [weak self] value in
            guard let self, case .volume = self.transient, self.volumeMonitor.setVolume(value) else { return }
            self.updateSystemHUD(.volume(value, self.volumeMonitor.isMuted))
            self.transientEnd = Date().addingTimeInterval(1.6)
        }
        islandView.onBrightness = { [weak self] value in
            guard let self, case .brightness = self.transient, self.brightnessMonitor.setBrightness(value) else { return }
            self.updateSystemHUD(.brightness(value))
            self.transientEnd = Date().addingTimeInterval(1.6)
        }
        islandView.onInteraction = { [weak self] value in self?.interacting = value; self?.keepAlive() }
        islandView.onDropHover = { [weak self] value in
            guard let self, IslandPreferences.shared.isEnabled(.files) else { return }; self.dropActive = value
            if value { self.showPanel(.files) } else { self.keepAlive() }
        }
        islandView.onFilesDropped = { [weak self] urls in
            guard let self else { return }
            guard IslandPreferences.shared.isEnabled(.files) else { return }
            let added = self.fileShelf.add(urls)
            self.showPanel(.files); self.keepAlive()
            if added == 0, self.fileShelf.items.count >= 30 { NSSound.beep() }
        }
    }
    private func selectMedia() {
        if let app = musicAppInfo {
            if !app.isPlaying, let fallback = fallbackInfo, fallback.isPlaying, fallback.title != app.title,
               Date().timeIntervalSince(fallback.sampledAt) < 3 { nowPlayingInfo = fallback }
            else { nowPlayingInfo = app }
        } else { nowPlayingInfo = fallbackInfo }
        if let intent = playbackIntent, var info = nowPlayingInfo,
           info.source == intent.source, info.trackID == intent.trackID, Date() < intent.expires {
            if info.isPlaying == intent.playing { playbackIntent = nil }
            else {
                info = info.interpolated(); info.isPlaying = intent.playing; info.sampledAt = Date()
                nowPlayingInfo = info
            }
        } else { playbackIntent = nil }
        applySelectedLyrics()
        updateMediaPresentation()
    }
    private func applySelectedLyrics() {
        let prefs = IslandPreferences.shared
        let query = prefs.isEnabled(.music) && prefs.showsAnyLyrics
            ? LyricsQuery(nowPlayingInfo, directory: prefs.lyricsDirectory, online: prefs.onlineLyrics,
                          preferWordTiming: prefs.lyricsAnimation == .appleMusic)
            : nil
        let lines = lyricsLookup.select(query)
        nowPlayingInfo?.lyrics = lines
    }
    private func togglePlayback() {
        guard var info = nowPlayingInfo else { return }
        info = info.interpolated(); info.isPlaying.toggle(); info.sampledAt = Date()
        playbackIntent = (info.isPlaying, info.source, info.trackID, Date().addingTimeInterval(1.2))
        nowPlayingInfo = info
        updateMediaPresentation()
        info.source.isEmpty ? nowPlaying.playPause() : musicApp.playPause()
        keepAlive()
    }
    private func updateMediaPresentation() {
        compactActivity.update(hasMedia: nowPlayingInfo?.title.isEmpty == false, playing: nowPlayingInfo?.isPlaying == true)
        islandView.mediaInfo = nowPlayingInfo
        islandView.compactMediaVisible = IslandPreferences.shared.isEnabled(.music) && compactActivity.isVisible()
        if policy.surface == .idle, !policy.transientVisible { renderUnderlying() }
        else { islandView.refreshCompact() }
        updateWorkTimers()
    }
    private func renderIfIdle() { if case .idle = policy.surface, !policy.transientVisible { renderUnderlying() } }
    private func handleVolumeKey(_ adjust: (VolumeMonitor) -> Bool) -> Bool {
        guard adjust(volumeMonitor) else { return false }
        if policy.surface != .panel(.audio), let volume = volumeMonitor.currentVolume() {
            presentSystemHUD(.volume(volume, volumeMonitor.isMuted))
        }
        return true
    }
    private func presentSystemHUD(_ state: IslandState) {
        guard IslandPreferences.shared.systemHUDEnabled else { return }
        presentTransient(state, seconds: 1.6)
    }
    private func updateSystemHUD(_ state: IslandState) {
        transient = state
        currentState = state
        islandView.render(state)
    }
    @discardableResult private func presentTransient(_ state: IslandState, seconds: TimeInterval) -> Bool {
        if case .notification = transient { return false }
        guard !hidden, !suppressed, !compactOnly, !interacting, !dropActive, policy.showTransient() else { return false }
        transient = state; transientEnd = Date().addingTimeInterval(seconds); currentState = state
        islandView.render(state); updatePointer(); return true
    }
    private func enqueueActivity(_ state: IslandState) {
        guard !hidden, !suppressed, !compactOnly else { return }
        pendingActivities.append((state, Date()))
        if pendingActivities.count > 4 { pendingActivities.removeFirst() }
        drainActivities(); updateWorkTimers()
    }
    private func drainActivities() {
        pendingActivities.removeAll { Date().timeIntervalSince($0.date) > 30 }
        guard !hidden, !suppressed, !compactOnly, policy.surface != .alert else { return }
        guard !policy.transientVisible, !pointerInside, !interacting, !dropActive, !pendingActivities.isEmpty else { return }
        // Remove before presenting: presentTransient synchronously re-enters updatePointer.
        let entry = pendingActivities.removeFirst()
        let shown: Bool
        if case .notification(let item) = entry.state { shown = showNotification(item, seconds: 6) }
        else { shown = presentTransient(entry.state, seconds: 6) }
        if !shown { pendingActivities.insert(entry, at: 0) }
    }
    @discardableResult private func showNotification(_ item: IslandNotification, seconds: TimeInterval) -> Bool {
        guard presentTransient(.notification(item), seconds: seconds) else { return false }
        window.orderFrontRegardless()
        guard window.isVisible else { dismissActivity(); return false }
        item.dismissNativeBanner?()
        return true
    }
    private func dismissActivity() {
        hoverDismissed = true
        manualAirPodsPresentation = false
        policy.expireTransient(); transient = nil; renderUnderlying(); drainActivities()
    }
    private func suspendAirPodsForSleep() {
        manualAirPodsPresentation = false
        if case .notification = transient { policy.expireTransient(); transient = nil }
        pendingActivities.removeAll { if case .notification = $0.state { return true }; return false }
        airPods.suspendAutomaticPresentation()
        pendingActivities.removeAll { if case .airPods = $0.state { return true }; return false }
        if case .airPods = transient { policy.expireTransient(); transient = nil; renderUnderlying() }
    }
    func showAirPods() {
        manualAirPodsPresentation = true
        if let snapshot = airPods.snapshot {
            _ = presentTransient(.airPods(snapshot), seconds: 7)
            airPods.refresh()
        } else {
            airPods.refresh()
            _ = presentTransient(.airPods(AirPodsSnapshot(name: "AirPods", address: "waiting", connected: false)), seconds: 7)
        }
    }
    func previewAirPods() { manualAirPodsPresentation = true; _ = presentTransient(.airPods(.demo), seconds: 7) }
    func previewInputSource() {
        guard IslandPreferences.shared.inputHUDEnabled else { return }
        let name = InputSourceMonitor.currentKeyboardSource()?.0 ?? "简体拼音"
        _ = presentTransient(.inputSource(name), seconds: 2.5)
    }
    func previewNotification() {
        if !showNotification(.demo, seconds: 7) { enqueueActivity(.notification(.demo)) }
    }
    func enableCalendar() {
        IslandPreferences.shared.calendarEnabled = true
        calendar.setEnabled(IslandPreferences.shared.isEnabled(.calendar)); calendar.requestAccess(); updateConnectedPanels()
    }
    private func updateConnectedPanels() {
        islandView.audioOutputs = audioOutputs.outputs; islandView.selectedOutput = audioOutputs.selected
        islandView.switchingOutput = audioOutputs.switching; islandView.outputVolume = volumeMonitor.currentVolume()
        islandView.outputVolumeAvailable = volumeMonitor.canAdjust; islandView.outputError = audioOutputs.error
        islandView.nextMeeting = calendar.meeting; islandView.calendarEnabled = IslandPreferences.shared.calendarEnabled
        islandView.calendarAuthorized = calendar.hasAccess; islandView.calendarStatus = calendar.status
        islandView.quickActions = quickActions.actions
        islandView.refreshConnectedPanels()
    }
    private func updateWorkTimers() {
        guard !isDebug else { return }
        let visible = (!hidden && !suppressed) || policy.surface == .alert
        let panelOpen: Bool = { if case .panel = policy.surface { return true }; return false }()
        let needsPointer = visible && (pointerInside || panelOpen || policy.transientVisible || dragWasActive || !pendingActivities.isEmpty || (compactActivity.pausedAt != nil && compactActivity.isVisible()))
        if needsPointer && pointerTimer == nil {
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.updatePointer() }
            timer.tolerance = 0.025; pointerTimer = timer; RunLoop.main.add(timer, forMode: .common)
        } else if !needsPointer { pointerTimer?.invalidate(); pointerTimer = nil }
        let needsProgress = visible && policy.surface == .panel(.music) && !hoveringPreview && nowPlayingInfo?.isPlaying == true
        if needsProgress && progressTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.islandView.refreshContent() }
            timer.tolerance = 0.1; progressTimer = timer; RunLoop.main.add(timer, forMode: .common)
        } else if !needsProgress { progressTimer?.invalidate(); progressTimer = nil }
        let needsMeeting = visible && policy.surface == .panel(.calendar) && !hoveringPreview && calendar.meeting != nil
        if needsMeeting && meetingTimer == nil {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.islandView.refreshMeetingCountdown() }
            timer.tolerance = 3; meetingTimer = timer; RunLoop.main.add(timer, forMode: .common)
        } else if !needsMeeting { meetingTimer?.invalidate(); meetingTimer = nil }
    }
    private func showAlert(_ state: IslandState) {
        policy.ring(); transient = nil; hoveringPreview = false; currentState = state
        islandView.render(state); window.orderFrontRegardless(); (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }
    private func renderUnderlying() {
        guard !policy.transientVisible else { return }
        islandView.mediaInfo = IslandPreferences.shared.isEnabled(.music) ? nowPlayingInfo : nil; islandView.timerSession = IslandPreferences.shared.isEnabled(.timer) ? alarmManager.session : nil
        islandView.compactMediaVisible = IslandPreferences.shared.isEnabled(.music) && compactActivity.isVisible()
        switch policy.surface {
        case .alert: return
        case .panel(let tab): currentState = .workspace(tab, hoveringPreview)
        case .idle:
            if IslandPreferences.shared.isEnabled(.timer), IslandPreferences.shared.focusDisplayEnabled, let remaining = alarmManager.timerRemaining { currentState = .idle(.timer(formatRemaining(remaining))) }
            else if IslandPreferences.shared.isEnabled(.music), let info = nowPlayingInfo, info.isPlaying { currentState = .idle(.music(info.title, info.artwork, info.dominantColor, true)) }
            else { currentState = .idle(.time(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))) }
        }
        islandView.render(currentState)
        musicApp.setExpanded(policy.surface == .panel(.music) && !hoveringPreview)
        updateVisibility(); updateWorkTimers()
    }
    func showPanel(_ tab: IslandTab? = nil) {
        guard policy.surface != .alert, !compactOnly else { return }
        if hidden { hidden = false }
        guard let resolved = IslandPreferences.shared.resolvedTab(tab ?? selectedTab) else {
            SettingsWindowController.shared.show(page: 5); return
        }
        selectedTab = resolved; UserDefaults.standard.set(selectedTab.rawValue, forKey: "notchisland.selectedTab")
        hoveringPreview = false; hoverDismissed = true; policy.open(selectedTab); transient = nil; keepAlive(); renderUnderlying(); window.orderFrontRegardless()
        if selectedTab == .music { musicApp.refresh() }
        if selectedTab == .audio { audioOutputs.refresh() }
        if selectedTab == .calendar { calendar.refresh() }
        if selectedTab == .focus { focusMonitor.refresh() }
        updateConnectedPanels()
    }
    private func dismissToIdle() {
        guard policy.surface != .alert else { return }
        hoveringPreview = false; hoverDismissed = true; policy.close(); transient = nil
        window.makeFirstResponder(nil); renderUnderlying()
    }
    private func keepAlive() { panelDeadline = autoHideSeconds > 0 ? Date().addingTimeInterval(autoHideSeconds) : .distantFuture }
    private func outsideClick() {
        guard !islandView.containsVisiblePoint(NSEvent.mouseLocation), !dropActive, !interacting else { return }
        if case .panel = policy.surface { dismissToIdle() }
    }
    private func updatePointer() {
        guard !isDebug else { return }
        let visible = (!hidden && !suppressed) || policy.surface == .alert
        guard visible else { window.ignoresMouseEvents = true; updateWorkTimers(); return }
        let now = Date()
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        if dragging || dragWasActive {
            let dragBoard = NSPasteboard(name: .drag)
            if !dragging { dragBoardBaseline = dragBoard.changeCount }
            else if IslandPreferences.shared.isEnabled(.files), dragBoard.changeCount != dragBoardBaseline, dragBoard.types?.contains(.fileURL) == true,
                    islandView.isNearDropTarget(NSEvent.mouseLocation), !compactOnly, policy.surface != .alert {
                if policy.surface != .panel(.files) || hoveringPreview { showPanel(.files) }
            }
        }
        dragWasActive = dragging
        let inside = islandView.containsVisiblePoint(NSEvent.mouseLocation)
        window.ignoresMouseEvents = !inside && !interacting && !dropActive
        islandView.setHover(inside)
        if inside && !pointerInside { pointerEntered = now }
        if !inside && pointerInside { pointerEntered = nil; hoverDismissed = false; keepAlive() }
        pointerInside = inside
        let mediaVisible = IslandPreferences.shared.isEnabled(.music) && compactActivity.isVisible(at: now)
        if mediaVisible != islandView.compactMediaVisible {
            islandView.compactMediaVisible = mediaVisible
            islandView.refreshCompact()
        }
        if case .panel(.music) = policy.surface, compactActivity.pausedAt != nil,
           !mediaVisible, !inside, !interacting, !dropActive { dismissToIdle() }
        if policy.transientVisible, now >= transientEnd, !interacting, !dropActive {
            policy.expireTransient(); transient = nil; renderUnderlying()
        }
        if inside, !hoverDismissed, IslandPreferences.shared.hoverPreview, !compactOnly, !IslandPreferences.shared.visibleTabs.isEmpty,
           let entered = pointerEntered, now.timeIntervalSince(entered) >= 0.3,
           case .idle = policy.surface, !policy.transientVisible {
            hoveringPreview = true; policy.open(selectedTab); renderUnderlying()
        }
        if !policy.transientVisible, hoveringPreview, !inside, !dropActive, !interacting {
            dismissToIdle()
        } else if !policy.transientVisible, case .panel = policy.surface, !inside, !interacting, !dropActive, now >= panelDeadline {
            let editing = window.firstResponder is NSTextView
            if !editing { dismissToIdle() }
        }
        drainActivities(); updateWorkTimers()
    }
    private func updateEnvironment() {
        guard let screen = IslandPreferences.shared.screen else { return }
        window.reposition()
        let front = NSWorkspace.shared.frontmostApplication
        suppressed = front?.bundleIdentifier.map { IslandPreferences.shared.excludedApps.contains($0) } ?? false
        let mode = IslandPreferences.shared.fullscreenMode
        var fullscreen = false
        if mode != 0, !suppressed, let pid = front?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
                guard let raw = window[kCGWindowBounds as String] as? [String: Any], let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else { continue }
                // CG windows use a top-left origin relative to the primary screen.
                let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
                let converted = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
                if converted.intersection(screen.frame).width >= screen.frame.width - 2 && converted.intersection(screen.frame).height >= screen.frame.height - 2 { fullscreen = true; break }
            }
        }
        let previousCompact = compactOnly
        compactOnly = fullscreen && mode == 1
        if fullscreen && mode == 2 { suppressed = true }
        if (compactOnly && !previousCompact) || suppressed {
            if case .panel = policy.surface { dismissToIdle() }
        }
        updateVisibility()
    }
    private func updateVisibility() {
        let visible = (!hidden && !suppressed) || policy.surface == .alert
        if visible { if !wasVisible || !window.isVisible { window.reposition(); window.orderFrontRegardless() } }
        else { window.orderOut(nil) }
        wasVisible = visible
        islandView.setActivityVisible(visible); updateWorkTimers()
    }
    private func applyPreferences() {
        let preferences = IslandPreferences.shared
        focusMonitor.setEnabled(preferences.isEnabled(.focus))
        let rules = "\(preferences.displayID)|\(preferences.fullscreenMode)|\(preferences.excludedApps)"
        if presentationRules != rules { presentationRules = rules; window.reposition(); keepAlive(); updateEnvironment() }
        if preferences.takeover && preferences.systemHUDEnabled { setupMediaKeyTakeover() } else { mediaKeys.stop() }
        airPods.setEnabled(IslandPreferences.shared.airPodsEnabled)
        notificationBridge.setEnabled(IslandPreferences.shared.notificationsEnabled)
        islandView.applyAppearance()
        calendar.setEnabled(IslandPreferences.shared.calendarEnabled && IslandPreferences.shared.isEnabled(.calendar))
        nowPlaying.setEnabled(preferences.isEnabled(.music)); musicApp.setEnabled(preferences.isEnabled(.music))
        clipboardHistory.setEnabled(preferences.isEnabled(.clipboard))
        brightnessMonitor.setEnabled(preferences.systemHUDEnabled)
        inputMonitor.setEnabled(preferences.inputHUDEnabled)
        batteryMonitor.setEnabled(preferences.powerHUDEnabled)
        audioOutputs.setEnabled(preferences.isEnabled(.audio))
        if !preferences.isEnabled(.files) { dropActive = false }
        if !preferences.isEnabled(.music) { nowPlayingInfo = nil; musicAppInfo = nil; fallbackInfo = nil; compactActivity.update(hasMedia: false, playing: false) }
        applySelectedLyrics()
        islandView.mediaInfo = nowPlayingInfo
        if let resolved = preferences.resolvedTab(selectedTab) {
            if selectedTab != resolved { window.makeFirstResponder(nil); interacting = false }
            selectedTab = resolved
            UserDefaults.standard.set(resolved.rawValue, forKey: "notchisland.selectedTab")
            policy.reconcileTabs(preferences.visibleTabs)
        } else if case .panel = policy.surface { policy.reconcileTabs([]); hoveringPreview = false; interacting = false; window.makeFirstResponder(nil) }
        pendingActivities.removeAll { entry in
            switch entry.state { case .airPods: return !preferences.airPodsEnabled; case .notification(let item): return item.identity.hasPrefix("meeting-") ? !preferences.isEnabled(.calendar) : !preferences.notificationsEnabled; default: return false }
        }
        if let transient {
            let disabled: Bool
            switch transient {
            case .airPods: disabled = !preferences.airPodsEnabled
            case .notification(let item): disabled = item.identity.hasPrefix("meeting-") ? !preferences.isEnabled(.calendar) : !preferences.notificationsEnabled
            case .volume, .brightness: disabled = !preferences.systemHUDEnabled
            case .inputSource: disabled = !preferences.inputHUDEnabled
            case .charging: disabled = !preferences.powerHUDEnabled
            default: disabled = false
            }
            if disabled { self.transient = nil; policy.expireTransient() }
        }
        reconcileNotificationPresentation()
        updateConnectedPanels(); renderUnderlying(); drainActivities()
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }
    func reconcileNotificationPresentation() {
        if case .notification(let item) = transient { islandView.render(.notification(item)) }
    }
    func setHidden(_ value: Bool) { hidden = value; if value { dismissToIdle() }; updateVisibility() }
    func showMusic() { showPanel(.music) }
    func showMusicPanel() { showPanel(.music) }
    func setAutoHideSeconds(_ seconds: TimeInterval) { IslandPreferences.shared.autoHide = seconds }
    func setupMediaKeyTakeover() { guard IslandPreferences.shared.systemHUDEnabled else { return }; _ = mediaKeys.start() }
    func requestMediaKeyTakeover() {
        IslandPreferences.shared.takeover = true
        guard IslandPreferences.shared.systemHUDEnabled else { return }
        if !mediaKeys.start() {
            _ = MediaKeyInterceptor.requestTrust()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard IslandPreferences.shared.takeover, IslandPreferences.shared.systemHUDEnabled else { return }
                _ = self?.mediaKeys.start()
            }
        }
    }
    func promptMusicAuth() { musicApp.requestAuthorization() }
    private func formatRemaining(_ seconds: Int) -> String { seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
