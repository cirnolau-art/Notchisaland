import AppKit

enum IslandBackgroundStyle: Int, CaseIterable { case black, glass }

struct AirPodsSnapshot: Equatable {
    var name: String
    var address: String
    var connected: Bool
    var left: Int?
    var right: Int?
    var caseBattery: Int?
    var sampledAt: Date = Date()
    var cachedFields: Set<String> = []
    var hasBattery: Bool { left != nil || right != nil || caseBattery != nil }
    func preservingKnownBattery(from previous: Self?) -> Self {
        guard let previous, previous.address == address else { return self }
        var result = self
        result.left = left ?? previous.left; result.right = right ?? previous.right; result.caseBattery = caseBattery ?? previous.caseBattery
        if left == nil, previous.left != nil { result.cachedFields.insert("left") }
        if right == nil, previous.right != nil { result.cachedFields.insert("right") }
        if caseBattery == nil, previous.caseBattery != nil { result.cachedFields.insert("case") }
        return result
    }
    static let demo = AirPodsSnapshot(name: "AirPods Pro · 动画预览", address: "preview", connected: true, left: 86, right: 84, caseBattery: 72)
}

enum AirPodsProfileParser {
    static func normalizedAddress(_ value: String) -> String { value.lowercased().replacingOccurrences(of: "-", with: ":") }
    static func applyingConnections(_ reports: [AirPodsSnapshot], connectedAddresses: Set<String>, disconnectedAddress: String?) -> [AirPodsSnapshot] {
        let connected = Set(connectedAddresses.map(normalizedAddress))
        return reports.map { report in
            var result = report
            let address = normalizedAddress(report.address)
            if disconnectedAddress.map(normalizedAddress) == address { result.connected = false }
            else if connected.contains(address) { result.connected = true }
            return result
        }
    }
    static func percent(_ value: Any?) -> Int? {
        let number: Int?
        if let text = value as? String { number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) }
        else if let value = value as? NSNumber { number = value.intValue }
        else { number = nil }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }
    static func parse(_ data: Data, at date: Date = Date()) -> [AirPodsSnapshot] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let adapters = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var results: [AirPodsSnapshot] = []
        for adapter in adapters {
            for section in ["device_connected", "device_not_connected"] {
                for row in adapter[section] as? [[String: Any]] ?? [] {
                    for (name, raw) in row {
                        guard let device = raw as? [String: Any] else { continue }
                        let lower = name.lowercased()
                        let batteryKeys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelCase"]
                        guard lower.contains("airpods") || lower.contains("pods pro") || batteryKeys.contains(where: { device[$0] != nil }) else { continue }
                        results.append(AirPodsSnapshot(name: name, address: device["device_address"] as? String ?? name,
                            connected: section == "device_connected", left: percent(device["device_batteryLevelLeft"]),
                            right: percent(device["device_batteryLevelRight"]), caseBattery: percent(device["device_batteryLevelCase"]), sampledAt: date))
                    }
                }
            }
        }
        return results
    }
    static func select(_ snapshots: [AirPodsSnapshot], previousAddress: String?) -> AirPodsSnapshot? {
        let previous = previousAddress.map(normalizedAddress)
        let connected = snapshots.filter(\.connected)
        return connected.first(where: { normalizedAddress($0.address) == previous }) ?? connected.first
            ?? snapshots.first(where: { normalizedAddress($0.address) == previous }) ?? snapshots.first(where: \.hasBattery) ?? snapshots.first
    }
}

struct IslandNotification {
    var source: String
    var title: String
    var body: String
    var identity: String
    var icon: NSImage?
    var openApplication: (() -> Void)?
    var dismissNativeBanner: (() -> Void)?
    var actionTitle = "打开应用"
    static var demo: IslandNotification {
        IslandNotification(source: "日历 · 效果预览", title: "设计评审即将开始", body: "10 分钟后 · 与团队一起看看今天的新想法。", identity: "preview", icon: NSImage(systemSymbolName: "calendar", accessibilityDescription: nil))
    }
}

/// The accessibility bridge only accepts complete visible banners, never a notification history dump.
enum BannerTextParser {
    static func parse(_ strings: [String]) -> (source: String, title: String, body: String)? {
        let controls: Set<String> = ["关闭", "清除", "选项", "回复", "显示更多", "Close", "Clear", "Options", "Reply", "Show more", "Notification Center", "通知中心"]
        var seen = Set<String>()
        let values = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && !controls.contains($0) && $0.count < 2000 && seen.insert($0).inserted
                && $0.range(of: "^(现在|刚刚|now|[0-9]+ (seconds?|minutes?) ago|[0-9]+[秒分钟小时]+前|[0-9]{1,2}:[0-9]{2})$", options: [.regularExpression, .caseInsensitive]) == nil
        }
        guard values.count >= 2 else { return nil }
        return (String(values[0].prefix(80)), String(values[1].prefix(200)), String(values.dropFirst(2).joined(separator: "\n").prefix(1000)))
    }
}

struct NotificationDeduplicator {
    private var seen: [String: Date] = [:]
    mutating func accept(_ identity: String, at now: Date = Date()) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) < 30 }
        guard seen[identity] == nil else { return false }
        if seen.count >= 64, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen.removeValue(forKey: oldest) }
        seen[identity] = now
        return true
    }
}
