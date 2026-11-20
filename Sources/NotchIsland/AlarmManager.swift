import AppKit

struct Alarm: Codable, Equatable {
    var hour: Int
    var minute: Int
    var enabled: Bool = true
    var label: String { String(format: "%02d:%02d", hour, minute) }
}

final class AlarmManager {
    var onAlarmFired: ((String) -> Void)?
    var onTimerFired: ((String) -> Void)?
    var onTimerTick: ((Int?) -> Void)?
    var onRingingStopped: (() -> Void)?
    static let storageKey = "notchisland.alarms"
    private static let sessionKey = "notchisland.timerSession"
    private(set) var alarms: [Alarm] = [] { didSet { persistAlarms(); schedule() } }
    private(set) var session: TimerSession?
    private var tickTimer: Timer?
    private var ringingSound: NSSound?
    private(set) var isRinging = false
    private var lastCheck = Date()
    private var firedKeys = Set<String>()
    private var wakeObserver: NSObjectProtocol?
    var timerRemaining: Int? { session.map { Int($0.remaining().rounded(.up)) } }

    init() {
        if SnapshotMode.enabled { return }
        firedKeys = Set(UserDefaults.standard.stringArray(forKey: "notchisland.firedAlarms") ?? [])
        if let data = UserDefaults.standard.data(forKey: Self.storageKey), let list = try? JSONDecoder().decode([Alarm].self, from: data) { alarms = list }
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey) { session = try? JSONDecoder().decode(TimerSession.self, from: data) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }
        // Allow the controller to install callbacks before recovering an expired session.
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }
    deinit { tickTimer?.invalidate(); if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) } }
    func add(_ alarm: Alarm) {
        alarms.removeAll { $0.hour == alarm.hour && $0.minute == alarm.minute }
        alarms.append(alarm)
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
    func remove(at index: Int) { guard alarms.indices.contains(index) else { return }; alarms.remove(at: index) }
    func toggle(at index: Int) { guard alarms.indices.contains(index) else { return }; alarms[index].enabled.toggle() }
    private func persistAlarms() {
        if let data = try? JSONEncoder().encode(alarms) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }
    private func persistSession() {
        if let session, let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: Self.sessionKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.sessionKey) }
    }
    func startTimer(seconds: Int, label: String = "倒计时") {
        session = TimerSession(seconds: TimeInterval(max(1, min(seconds, 86400))), label: label)
        persistSession(); tick()
    }
    func pauseOrResume() {
        guard var value = session else { return }
        if value.isPaused { value.resume() } else { value.pause() }
        session = value; persistSession(); tick()
    }
    func addMinute() { guard session != nil else { return }; session?.add(seconds: 60); persistSession(); tick() }
    func cancelTimer() { session = nil; persistSession(); onTimerTick?(nil); schedule() }
    private func schedule() {
        tickTimer?.invalidate()
        let running = session != nil && session?.isPaused == false
        guard running || alarms.contains(where: \.enabled) else { return }
        let interval = running ? 1.0 : max(0.2, 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.tick() }
        timer.tolerance = running ? 0.1 : 0.5
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        let now = Date()
        if let value = session {
            let remaining = Int(value.remaining(at: now).rounded(.up))
            if remaining <= 0 && !value.isPaused {
                session = nil; persistSession(); onTimerTick?(nil)
                startRinging(); onTimerFired?(value.label)
            } else { onTimerTick?(remaining) }
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for alarm in alarms where alarm.enabled {
            guard let due = cal.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: now) else { continue }
            let key = "\(today.timeIntervalSince1970)-\(alarm.label)"
            // Recover a recently missed alarm on wake; do not ring hours-old alarms.
            let caughtUp = due > lastCheck && now.timeIntervalSince(due) >= 0 && now.timeIntervalSince(due) < 300
            let sameMinute = cal.component(.hour, from: now) == alarm.hour && cal.component(.minute, from: now) == alarm.minute
            if (sameMinute || caughtUp), !firedKeys.contains(key) {
                firedKeys.insert(key)
                UserDefaults.standard.set(Array(firedKeys), forKey: "notchisland.firedAlarms")
                if !isRinging { startRinging(); onAlarmFired?(alarm.label) }
            }
        }
        if firedKeys.count > 128 { firedKeys = Set(firedKeys.filter { $0.hasPrefix("\(today.timeIntervalSince1970)-") }) }
        lastCheck = now
        schedule()
    }
    func startRinging() {
        guard !isRinging else { return }
        isRinging = true
        ringingSound = NSSound(named: "Glass") ?? NSSound(named: "Ping")
        ringingSound?.loops = true; ringingSound?.play()
    }
    func stopRinging() { ringingSound?.stop(); ringingSound = nil; isRinging = false; onRingingStopped?() }
}
