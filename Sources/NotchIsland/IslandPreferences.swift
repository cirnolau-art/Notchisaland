import AppKit

extension Notification.Name { static let islandPreferencesChanged = Notification.Name("NotchIsland.preferencesChanged") }

final class IslandPreferences {
    static let shared = IslandPreferences()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    static var supportsGlass: Bool { if #available(macOS 26.0, *) { return true }; return false }
    static func resolvedBackground(_ style: IslandBackgroundStyle, glassAvailable: Bool) -> IslandBackgroundStyle { glassAvailable ? style : .black }
    var effectiveBackgroundStyle: IslandBackgroundStyle { Self.resolvedBackground(backgroundStyle, glassAvailable: Self.supportsGlass) }
    func isEnabled(_ tab: IslandTab) -> Bool {
        defaults.object(forKey: "notchisland.module.\(tab.rawValue)") as? Bool ?? (tab != .clipboard)
    }
    func setEnabled(_ tab: IslandTab, _ enabled: Bool) {
        guard isEnabled(tab) != enabled else { return }
        defaults.set(enabled, forKey: "notchisland.module.\(tab.rawValue)"); changed()
    }
    var visibleTabs: [IslandTab] { IslandTab.allCases.filter { isEnabled($0) } }
    func resolvedTab(_ preferred: IslandTab) -> IslandTab? { isEnabled(preferred) ? preferred : visibleTabs.first }
    var systemHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.systemHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.systemHUDEnabled"); changed() } }
    var inputHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.inputHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.inputHUDEnabled"); changed() } }
    var powerHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.powerHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.powerHUDEnabled"); changed() } }
    var calendarEnabled: Bool { get { defaults.bool(forKey: "notchisland.calendarEnabled") } set { defaults.set(newValue, forKey: "notchisland.calendarEnabled"); changed() } }
    var backgroundStyle: IslandBackgroundStyle { get { IslandBackgroundStyle(rawValue: defaults.integer(forKey: "notchisland.backgroundStyle")) ?? .black } set { defaults.set(newValue.rawValue, forKey: "notchisland.backgroundStyle"); changed() } }
    var glassBlur: Double { get { defaults.object(forKey: "notchisland.glassBlur") as? Double ?? 0.75 } set { defaults.set(min(1, max(0, newValue)), forKey: "notchisland.glassBlur"); changed() } }
    var glassOpacity: Double { get { defaults.object(forKey: "notchisland.glassOpacity") as? Double ?? 0.58 } set { defaults.set(min(1, max(0, newValue)), forKey: "notchisland.glassOpacity"); changed() } }
    var airPodsEnabled: Bool { get { defaults.object(forKey: "notchisland.airPodsEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.airPodsEnabled"); changed() } }
    var notificationsEnabled: Bool { get { defaults.object(forKey: "notchisland.notificationsEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.notificationsEnabled"); changed() } }
    var notificationPreview: Bool { get { defaults.object(forKey: "notchisland.notificationPreview") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.notificationPreview"); changed() } }
    var notificationPlacement: NotificationPlacement { get { NotificationPlacement(rawValue: defaults.integer(forKey: "notchisland.notificationPlacement")) ?? .island } set { defaults.set(newValue.rawValue, forKey: "notchisland.notificationPlacement"); changed() } }
    var lyricsPlacement: LyricsPlacement { get { LyricsPlacement(rawValue: defaults.object(forKey: "notchisland.lyricsPlacement") as? Int ?? LyricsPlacement.below.rawValue) ?? .below } set { defaults.set(newValue.rawValue, forKey: "notchisland.lyricsPlacement"); changed() } }
    var lyricsAnimation: LyricsAnimationStyle { get { LyricsAnimationStyle(rawValue: defaults.object(forKey: "notchisland.lyricsAnimation") as? Int ?? LyricsAnimationStyle.appleMusic.rawValue) ?? .appleMusic } set { defaults.set(newValue.rawValue, forKey: "notchisland.lyricsAnimation"); changed() } }
    var lyricsDirectory: String { get { defaults.string(forKey: "notchisland.lyricsDirectory") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchIsland Lyrics").path } set { defaults.set(newValue, forKey: "notchisland.lyricsDirectory"); changed() } }
    var focusDisplayEnabled: Bool { get { defaults.object(forKey: "notchisland.focusDisplayEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.focusDisplayEnabled"); changed() } }
    var displayID: UInt32 { get { UInt32(defaults.integer(forKey: "notchisland.displayID")) } set { defaults.set(Int(newValue), forKey: "notchisland.displayID"); changed() } }
    var hoverPreview: Bool { get { defaults.object(forKey: "notchisland.hoverPreview") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.hoverPreview"); changed() } }
    var gentleMotion: Bool { get { defaults.bool(forKey: "notchisland.gentleMotion") } set { defaults.set(newValue, forKey: "notchisland.gentleMotion"); changed() } }
    var fullscreenMode: Int { get { defaults.integer(forKey: "notchisland.fullscreenMode") } set { defaults.set(newValue, forKey: "notchisland.fullscreenMode"); changed() } }
    var excludedApps: [String] { get { defaults.stringArray(forKey: "notchisland.excludedApps") ?? [] } set { defaults.set(newValue, forKey: "notchisland.excludedApps"); changed() } }
    var takeover: Bool { get { defaults.bool(forKey: "notchisland.takeover") } set { defaults.set(newValue, forKey: "notchisland.takeover"); changed() } }
    var autoHide: TimeInterval { get { defaults.object(forKey: "notchisland.autoHideSeconds") as? Double ?? 10 } set { defaults.set(newValue, forKey: "notchisland.autoHideSeconds"); changed() } }
    var reduceMotion: Bool { gentleMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func changed() { NotificationCenter.default.post(name: .islandPreferencesChanged, object: nil) }
    var screen: NSScreen? {
        if displayID != 0, let match = NSScreen.screens.first(where: { $0.displayID == displayID }) { return match }
        return NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? NSScreen.screens.first
    }
}

enum NotificationPlacement: Int, CaseIterable { case island, sides
    var title: String { self == .island ? "刘海展开" : "两侧小窗口" }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID() }
    var islandGeometry: (width: CGFloat, height: CGFloat, hasNotch: Bool) {
        if let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea, r.minX - l.maxX > 40 {
            return (r.minX - l.maxX, max(l.height, safeAreaInsets.top), true)
        }
        return (180, 30, false)
    }
}
