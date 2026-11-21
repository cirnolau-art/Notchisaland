import AppKit

extension Notification.Name {
    static let islandPreferencesChanged = Notification.Name("NotchIsland.preferencesChanged")
    static let islandAppearanceChanged = Notification.Name("NotchIsland.appearanceChanged")
}

enum HUDTrackKind: String {
    case volume, brightness
}

final class IslandPreferences {
    static let shared = IslandPreferences(defaults: SnapshotMode.enabled ? SnapshotMode.defaults : .standard)
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
    static var systemNaturalScrolling: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }
    var naturalScrolling: Bool? {
        get {
            if let override = defaults.object(forKey: "notchisland.naturalScrolling") as? Bool { return override }
            // Legacy inversion was relative to the device's physical direction for vertical gestures.
            return defaults.bool(forKey: "notchisland.invertScrollV2") ? false : nil
        }
        set {
            defaults.set(newValue, forKey: "notchisland.naturalScrolling")
            defaults.removeObject(forKey: "notchisland.invertScrollV2")
        }
    }
    static func scrollDirectionMultiplier(naturalScrolling: Bool?, eventIsInverted: Bool) -> CGFloat {
        guard let naturalScrolling else { return 1 }
        return naturalScrolling == eventIsInverted ? 1 : -1
    }
    var systemHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.systemHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.systemHUDEnabled"); changed() } }
    var inputHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.inputHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.inputHUDEnabled"); changed() } }
    var powerHUDEnabled: Bool { get { defaults.object(forKey: "notchisland.powerHUDEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.powerHUDEnabled"); changed() } }
    var calendarEnabled: Bool { get { defaults.bool(forKey: "notchisland.calendarEnabled") } set { defaults.set(newValue, forKey: "notchisland.calendarEnabled"); changed() } }
    var backgroundStyle: IslandBackgroundStyle {
        get { IslandBackgroundStyle(rawValue: defaults.integer(forKey: "notchisland.backgroundStyle")) ?? .black }
        set {
            guard backgroundStyle != newValue else { return }
            defaults.set(newValue.rawValue, forKey: "notchisland.backgroundStyle")
            appearanceChanged()
        }
    }
    var glassMaterial: IslandGlassMaterial {
        get { IslandGlassMaterial(rawValue: defaults.integer(forKey: "notchisland.glassMaterial")) ?? .regular }
        set {
            guard newValue != glassMaterial else { return }
            defaults.set(newValue.rawValue, forKey: "notchisland.glassMaterial")
            appearanceChanged()
        }
    }
    var glassGradientEnabled: Bool {
        get { defaults.object(forKey: "notchisland.glassGradientEnabled") as? Bool ?? true }
        set {
            guard glassGradientEnabled != newValue else { return }
            defaults.set(newValue, forKey: "notchisland.glassGradientEnabled")
            appearanceChanged()
        }
    }
    var glassOpacity: Double {
        get { defaults.object(forKey: "notchisland.glassOpacity") as? Double ?? IslandBackdropConfiguration.defaultDarkening }
        set { setGlassValue(newValue, current: glassOpacity, key: "notchisland.glassOpacity") }
    }
    var glassRimStrength: Double {
        get { defaults.object(forKey: "notchisland.glassRimStrength") as? Double ?? IslandBackdropConfiguration.defaultRim }
        set { setGlassValue(newValue, current: glassRimStrength, key: "notchisland.glassRimStrength") }
    }
    private func setGlassValue(_ value: Double, current: Double, key: String) {
        guard value.isFinite else { return }
        let clamped = min(1, max(0, value))
        guard clamped != current else { return }
        defaults.set(clamped, forKey: key)
        appearanceChanged()
    }
    var airPodsEnabled: Bool { get { defaults.object(forKey: "notchisland.airPodsEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.airPodsEnabled"); changed() } }
    var notificationsEnabled: Bool { get { defaults.object(forKey: "notchisland.notificationsEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.notificationsEnabled"); changed() } }
    var notificationPreview: Bool { get { defaults.object(forKey: "notchisland.notificationPreview") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.notificationPreview"); changed() } }
    var notificationPlacement: NotificationPlacement { get { NotificationPlacement(rawValue: defaults.integer(forKey: "notchisland.notificationPlacement")) ?? .island } set { defaults.set(newValue.rawValue, forKey: "notchisland.notificationPlacement"); changed() } }
    var notificationWidth: Double {
        get { defaults.object(forKey: "notchisland.notificationWidth") as? Double ?? NotchNotificationLayout.defaultWidth }
        set { defaults.set(newValue, forKey: "notchisland.notificationWidth"); appearanceChanged() }
    }
    var notificationDepth: Double {
        get { defaults.object(forKey: "notchisland.notificationDepth") as? Double ?? NotchNotificationLayout.defaultDepth }
        set { defaults.set(newValue, forKey: "notchisland.notificationDepth"); appearanceChanged() }
    }
    var lyricsRightBackground: Bool {
        get { defaults.object(forKey: "notchisland.lyricsRightBackground") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchisland.lyricsRightBackground"); appearanceChanged() }
    }
    var lyricsPlacement: LyricsPlacement {
        get { LyricsPlacement(rawValue: defaults.object(forKey: "notchisland.lyricsPlacement") as? Int ?? LyricsPlacement.below.rawValue) ?? .below }
        set {
            // Preserve the old expanded preference the first time a 1.6 user edits the compact position.
            if defaults.object(forKey: "notchisland.expandedLyricsPlacement") == nil {
                defaults.set(expandedLyricsPlacement.rawValue, forKey: "notchisland.expandedLyricsPlacement")
            }
            defaults.set(newValue.rawValue, forKey: "notchisland.lyricsPlacement")
            changed()
        }
    }
    var expandedLyricsPlacement: LyricsPlacement {
        get {
            if let value = defaults.object(forKey: "notchisland.expandedLyricsPlacement") as? Int,
               let placement = LyricsPlacement(rawValue: value) { return placement }
            return lyricsPlacement == .hidden ? .hidden : .below
        }
        set { defaults.set(newValue.rawValue, forKey: "notchisland.expandedLyricsPlacement"); changed() }
    }
    var showsAnyLyrics: Bool { lyricsPlacement != .hidden || expandedLyricsPlacement != .hidden }
    var lyricsAppearance: LyricsAppearance {
        get {
            guard let data = defaults.data(forKey: "notchisland.lyricsAppearance"),
                  let value = try? PropertyListDecoder().decode(LyricsAppearance.self, from: data) else { return LyricsAppearance() }
            return value.normalized()
        }
        set {
            let value = newValue.normalized()
            guard lyricsAppearance != value, let data = try? PropertyListEncoder().encode(value) else { return }
            defaults.set(data, forKey: "notchisland.lyricsAppearance")
            NotificationCenter.default.post(name: .islandAppearanceChanged, object: nil)
        }
    }
    func hudTrackAppearance(for kind: HUDTrackKind) -> HUDTrackAppearance {
        let key = "notchisland.hudTrack.\(kind.rawValue)"
        guard let data = defaults.data(forKey: key),
              let appearance = try? PropertyListDecoder().decode(HUDTrackAppearance.self, from: data) else {
            return HUDTrackAppearance()
        }
        return appearance
    }
    func setHUDTrackAppearance(_ appearance: HUDTrackAppearance, for kind: HUDTrackKind) {
        guard appearance != hudTrackAppearance(for: kind),
              let data = try? PropertyListEncoder().encode(appearance) else { return }
        defaults.set(data, forKey: "notchisland.hudTrack.\(kind.rawValue)")
        appearanceChanged()
    }
    var accentRGB: UInt32 {
        get { UInt32(clamping: defaults.object(forKey: "notchisland.accentRGB") as? Int ?? 0xFFFFFF) & 0xFFFFFF }
        set {
            let value = newValue & 0xFFFFFF
            guard value != accentRGB else { return }
            defaults.set(Int(value), forKey: "notchisland.accentRGB")
            NotificationCenter.default.post(name: .islandAppearanceChanged, object: nil)
        }
    }
    var lyricsAnimation: LyricsAnimationStyle { get { LyricsAnimationStyle(rawValue: defaults.object(forKey: "notchisland.lyricsAnimation") as? Int ?? LyricsAnimationStyle.appleMusic.rawValue) ?? .appleMusic } set { defaults.set(newValue.rawValue, forKey: "notchisland.lyricsAnimation"); changed() } }
    var lyricsDirectory: String { get { defaults.string(forKey: "notchisland.lyricsDirectory") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchIsland Lyrics").path } set { defaults.set(newValue, forKey: "notchisland.lyricsDirectory"); changed() } }
    var onlineLyrics: Bool { get { defaults.object(forKey: "notchisland.onlineLyrics") as? Bool ?? true } set { defaults.set(newValue, forKey: "notchisland.onlineLyrics"); changed() } }
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
    func appearanceChanged() { NotificationCenter.default.post(name: .islandAppearanceChanged, object: nil) }
    var screen: NSScreen? {
        if displayID != 0, let match = NSScreen.screens.first(where: { $0.displayID == displayID }) { return match }
        return NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) ?? NSScreen.screens.first
    }
}

enum NotificationPlacement: Int, CaseIterable { case island, sides
    var title: String { self == .island ? "完整卡片" : "贴合刘海" }
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
