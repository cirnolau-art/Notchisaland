import AppKit
import EventKit

struct IslandMeeting: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendar: String
    let location: String
    let link: URL?
    var timeLabel: String { "\(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)) – \(DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short))" }
    func countdown(at now: Date = Date()) -> String {
        let seconds = start.timeIntervalSince(now)
        if end <= now { return "已结束" }
        if seconds <= 0 { return "正在进行" }
        if seconds < 60 { return "不到 1 分钟后" }
        let minutes = Int(ceil(seconds / 60))
        return minutes < 60 ? "\(minutes) 分钟后" : "\(minutes / 60) 小时\(minutes % 60 == 0 ? "" : " \(minutes % 60) 分")后"
    }
    static func meetingURL(_ strings: [String]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let candidates = strings.flatMap { string in detector.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap(\.url) }
        return candidates.first { url in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return false }
            return ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "meeting.tencent.com", "voovmeeting.com", "feishu.cn", "larksuite.com"].contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
    static let demo = IslandMeeting(id: "demo", title: "产品设计评审", start: Date().addingTimeInterval(480), end: Date().addingTimeInterval(4080), calendar: "工作", location: "线上会议", link: URL(string: "https://meet.google.com/preview"))
}

/// EventKit updates and one deadline timer; no calendar polling while disabled.
final class CalendarMonitor {
    var onChange: (() -> Void)?
    var onReminder: ((IslandMeeting) -> Void)?
    private(set) var meeting: IslandMeeting?
    private(set) var status = "开启后显示下一场日程"
    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "notchisland.calendar", qos: .utility)
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var enabled = false
    private var generation = 0
    private var reminderKeys: [String: Date] = [:]
    private var requesting = false
    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }; enabled = value; generation += 1
        if value {
            for (center, name) in [(NotificationCenter.default, Notification.Name.EKEventStoreChanged), (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification), (NotificationCenter.default, NSNotification.Name.NSSystemTimeZoneDidChange), (NotificationCenter.default, NSNotification.Name.NSSystemClockDidChange)] {
                observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }))
            }
            refresh()
        } else {
            timer?.invalidate(); timer = nil; meeting = nil; status = "日程功能未启用"
            observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll(); onChange?()
        }
    }
    func requestAccess() {
        guard !requesting else { return }; requesting = true
        store.requestFullAccessToEvents { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }; self.requesting = false
                if let error { self.status = error.localizedDescription; self.onChange?() }
                self.refresh()
            }
        }
    }
    func refresh() {
        guard enabled else { return }
        timer?.invalidate(); timer = nil
        guard hasAccess else { meeting = nil; status = "需要日历完整访问权限"; onChange?(); return }
        generation += 1; let expected = generation
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date(), end = Date().addingTimeInterval(7 * 86400)
            let predicate = self.store.predicateForEvents(withStart: now.addingTimeInterval(-86400), end: end, calendars: nil)
            let events = self.store.events(matching: predicate).filter { event in
                !event.isAllDay && event.endDate > now && event.status != .canceled && !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
            }.sorted { $0.startDate < $1.startDate }
            let next = events.first.map { event in
                IslandMeeting(id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)", title: event.title ?? "未命名日程", start: event.startDate, end: event.endDate, calendar: event.calendar.title, location: event.location ?? "", link: IslandMeeting.meetingURL([event.url?.absoluteString ?? "", event.location ?? "", event.notes ?? ""]))
            }
            DispatchQueue.main.async {
                guard self.enabled, expected == self.generation else { return }
                self.meeting = next; self.status = next == nil ? "未来 7 天暂无定时日程" : "已连接系统日历"; self.onChange?(); self.schedule()
            }
        }
    }
    private func schedule() {
        let now = Date()
        reminderKeys = reminderKeys.filter { $0.value > now.addingTimeInterval(-86400) }
        var next = now.addingTimeInterval(900)
        if let meeting {
            let lead = meeting.start.addingTimeInterval(-300)
            if now >= lead, now < meeting.start, reminderKeys[meeting.id] == nil {
                reminderKeys[meeting.id] = now; onReminder?(meeting)
            }
            for date in [lead, meeting.start, meeting.end] where date > now { next = min(next, date) }
        }
        let timer = Timer(fire: next.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in self?.refresh() }
        timer.tolerance = 1; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func open(_ meeting: IslandMeeting) {
        if let link = meeting.link { NSWorkspace.shared.open(link) }
        else if let url = URL(string: "calshow:\(meeting.start.timeIntervalSinceReferenceDate)") { NSWorkspace.shared.open(url) }
    }
    deinit { timer?.invalidate(); observers.forEach { $0.0.removeObserver($0.1) } }
}
