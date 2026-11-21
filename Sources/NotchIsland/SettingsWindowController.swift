import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 610), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "灵动岛设置"; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: IslandSettingsView())
        super.init(window: window); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func snapshotPage(_ page: Int, glass: Bool = false, legacy: Bool = false) {
        guard SnapshotMode.enabled else { return }
        window?.contentViewController = NSHostingController(rootView: IslandSettingsView(initialPage: page, previewGlass: glass, previewLegacy: legacy))
    }
    func show(page: Int? = nil) {
        if let page { window?.contentViewController = NSHostingController(rootView: IslandSettingsView(initialPage: page)) }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private struct IslandSettingsView: View {
    private let supportsGlass: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var page = 0
    @State private var modules = Set(IslandPreferences.shared.visibleTabs)
    @State private var systemHUD = IslandPreferences.shared.systemHUDEnabled
    @State private var inputHUD = IslandPreferences.shared.inputHUDEnabled
    @State private var powerHUD = IslandPreferences.shared.powerHUDEnabled
    @State private var background = IslandPreferences.shared.effectiveBackgroundStyle
    @State private var calendarEnabled = IslandPreferences.shared.calendarEnabled
    @State private var calendarStatus = ""
    @State private var actions = IslandController.shared.quickActions.actions
    @State private var shortcutNames: [String] = []
    @State private var shortcutSelection = ""
    @State private var shortcutStatus = ""
    @State private var loadingShortcuts = false
    @State private var glassMaterial = IslandPreferences.shared.glassMaterial
    @State private var glassGradient = IslandPreferences.shared.glassGradientEnabled
    @State private var glassOpacity = IslandPreferences.shared.glassOpacity
    @State private var glassRimStrength = IslandPreferences.shared.glassRimStrength
    @State private var lyricsAppearance = IslandPreferences.shared.lyricsAppearance
    @State private var volumeTrack = IslandPreferences.shared.hudTrackAppearance(for: .volume)
    @State private var brightnessTrack = IslandPreferences.shared.hudTrackAppearance(for: .brightness)
    @State private var accentRGB = IslandPreferences.shared.accentRGB
    @State private var airPodsEnabled = IslandPreferences.shared.airPodsEnabled
    @State private var notificationsEnabled = IslandPreferences.shared.notificationsEnabled
    @State private var notificationPreview = IslandPreferences.shared.notificationPreview
    @State private var notificationPlacement = IslandPreferences.shared.notificationPlacement
    @State private var notificationWidth = IslandPreferences.shared.notificationWidth
    @State private var notificationDepth = IslandPreferences.shared.notificationDepth
    @State private var lyricsRightBackground = IslandPreferences.shared.lyricsRightBackground
    @State private var lyricsPlacement = IslandPreferences.shared.lyricsPlacement
    @State private var expandedLyricsPlacement = IslandPreferences.shared.expandedLyricsPlacement
    @State private var lyricsAnimation = IslandPreferences.shared.lyricsAnimation
    @State private var lyricsDirectory = IslandPreferences.shared.lyricsDirectory
    @State private var onlineLyrics = IslandPreferences.shared.onlineLyrics
    @State private var focusDisplay = IslandPreferences.shared.focusDisplayEnabled
    @State private var airPodsStatus = ""
    @State private var notificationStatus = ""
    @State private var hover = IslandPreferences.shared.hoverPreview
    @State private var gentle = IslandPreferences.shared.gentleMotion
    @State private var autoHide = IslandPreferences.shared.autoHide
    @State private var display = IslandPreferences.shared.displayID
    @State private var fullscreen = IslandPreferences.shared.fullscreenMode
    @State private var takeover = IslandPreferences.shared.takeover
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var naturalScrolling = IslandPreferences.shared.naturalScrolling
    @State private var systemNaturalScrolling = IslandPreferences.systemNaturalScrolling
    @State private var exclusions = IslandPreferences.shared.excludedApps.joined(separator: ", ")
    @State private var screens = NSScreen.screens
    @State private var status = ""
    @State private var musicStatus = ""
    @State private var error: String?
    private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(initialPage: Int = 0, previewGlass: Bool = false, previewLegacy: Bool = false) {
        supportsGlass = IslandPreferences.supportsGlass && !(SnapshotMode.enabled && previewLegacy)
        _page = State(initialValue: initialPage)
        if previewGlass && supportsGlass { _background = State(initialValue: .glass) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $page) {
                Text("交互").tag(0)
                Text("外观").tag(1)
                Text("设备与通知").tag(2)
                Text("音乐与权限").tag(3)
                Text("日程与快捷").tag(4)
                Text("模块").tag(5)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            settingsForm.id(page)

            Divider()
            HStack {
                Text("© 2026 Lau Kachun · 文件暂存只保留引用，不移动原文件")
                Spacer()
                Text(AppVersion.display)
                    .help("版本 \(AppVersion.release) · 构建 \(AppVersion.build)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .frame(width: 580, height: 610)
        .onReceive(clock) { _ in
            guard SettingsWindowController.shared.window?.isVisible == true else { return }
            status = IslandController.shared.mediaKeyTakeoverEnabled ? "已接管系统提示" : (MediaKeyInterceptor.isTrusted ? "权限已开启，可重新启用接管" : "需要辅助功能权限")
            musicStatus = IslandController.shared.musicAppStatus
            screens = NSScreen.screens
            airPodsStatus = IslandController.shared.airPodsStatus
            notificationStatus = IslandController.shared.notificationStatus
            refreshDaily()
        }
        .onAppear { refreshDaily() }
        .onReceive(NotificationCenter.default.publisher(for: .islandPreferencesChanged)) { _ in modules = Set(IslandPreferences.shared.visibleTabs) }
        .alert("设置未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) { error = nil } } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private var settingsForm: some View {
        if #available(macOS 26.0, *), supportsGlass {
            form.buttonStyle(.glass)
        } else {
            form.buttonStyle(.bordered)
        }
    }

    private var form: some View {
        Form {
            switch page {
            case 0: interactionPage
            case 1:
                appearancePage
                hudTrackSection("音量提示条", appearance: $volumeTrack, kind: .volume)
                hudTrackSection("亮度提示条", appearance: $brightnessTrack, kind: .brightness)
                lyricsAppearancePage
                displayPage
            case 2: connectedPage
            case 3: permissionsPage
            case 4: dailyPage
            default: modulesPage
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    private var modulesPage: some View {
        Group {
            Section("展开面板 · 按需开启") {
                ForEach(IslandTab.allCases, id: \.rawValue) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.symbol).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tab.title)
                            Text(tab.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle(tab.title, isOn: Binding(get: { modules.contains(tab) }, set: { value in
                            if value { modules.insert(tab) } else { modules.remove(tab) }
                            IslandPreferences.shared.setEnabled(tab, value)
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("关闭后从面板和滑动导航中隐藏。文件暂存保留引用；已有计时仍按时提醒。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("剪贴板隐私") {
                Text("默认关闭；开启后从下一次复制开始记录。跳过带保密标记的内容和常见密码管理器。退出或关闭模块会清空历史，不会清空系统剪贴板。").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("单张图片最多 4 MB，文字最多 1 MB。普通文字中的敏感内容无法自动判断；复制敏感资料前请关闭此模块。").font(.system(size: 11)).foregroundStyle(.tertiary)
                Button("清空本次历史") { IslandController.shared.clipboardHistory.clear() }.disabled(!modules.contains(.clipboard))
            }
            Section("即时提示") {
                Toggle("音量与亮度", isOn: $systemHUD).onChange(of: systemHUD) { _, value in IslandPreferences.shared.systemHUDEnabled = value }
                Toggle("输入法切换", isOn: $inputHUD).onChange(of: inputHUD) { _, value in IslandPreferences.shared.inputHUDEnabled = value }
                Button("预览输入法提示") { IslandController.shared.previewInputSource() }.disabled(!inputHUD)
                Toggle("电源连接", isOn: $powerHUD).onChange(of: powerHUD) { _, value in IslandPreferences.shared.powerHUDEnabled = value }
                Text("耳机与通知可在“设备与通知”中分别开关。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private var interactionPage: some View {
        Group {
            Section("交互") {
                Toggle("悬停预览", isOn: $hover).onChange(of: hover) { _, value in IslandPreferences.shared.hoverPreview = value }
                Text("停留片刻显示摘要，点击展开；横向滑动切换模块。").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("离开后自动收起", selection: $autoHide) { Text("5 秒").tag(5.0); Text("10 秒").tag(10.0); Text("15 秒").tag(15.0); Text("30 秒").tag(30.0); Text("手动收起").tag(0.0) }.onChange(of: autoHide) { _, value in IslandPreferences.shared.autoHide = value }
                Text("指针停留、拖动和输入时保持展开。Esc 或点击外部收起。").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("自然滚动", isOn: Binding(
                    get: { naturalScrolling ?? systemNaturalScrolling },
                    set: { naturalScrolling = $0 }
                ))
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    systemNaturalScrolling = IslandPreferences.systemNaturalScrolling
                }
                .onChange(of: naturalScrolling) { _, value in IslandPreferences.shared.naturalScrolling = value }
                .help("默认跟随 macOS 的自然滚动设置。")
                if naturalScrolling != nil {
                    Button("恢复跟随系统滚动方向") {
                        systemNaturalScrolling = IslandPreferences.systemNaturalScrolling
                        naturalScrolling = nil
                    }
                }
            }
            Section("动画与启动") {
                Toggle("柔和动效", isOn: $gentle).onChange(of: gentle) { _, value in IslandPreferences.shared.gentleMotion = value }
                Text("默认使用连续弹簧动画；自动遵循系统“减少动态效果”。").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("登录时启动", isOn: $login).onChange(of: login) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { self.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                }
            }
        }
    }
    private var appearancePage: some View {
        Section("刘海外观") {
            ColorPicker("控件强调色", selection: Binding(
                get: { Color(nsColor: LyricsAppearance.color(for: accentRGB)) },
                set: { if let rgb = LyricsAppearance.rgb(for: NSColor($0)) { accentRGB = rgb; IslandPreferences.shared.accentRGB = rgb } }
            ), supportsOpacity: false)
            if supportsGlass {
                Picker("展开背景", selection: $background) {
                    Text("纯黑").tag(IslandBackgroundStyle.black)
                    Text("液态玻璃").tag(IslandBackgroundStyle.glass)
                }
                .pickerStyle(.segmented)
                .onChange(of: background) { _, value in IslandPreferences.shared.backgroundStyle = value }
                if background == .glass {
                    Picker("玻璃材质", selection: $glassMaterial) {
                        Text("标准").tag(IslandGlassMaterial.regular)
                        Text("轻模糊").tag(IslandGlassMaterial.clear)
                        Text("清透玻璃").tag(IslandGlassMaterial.transparent)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: glassMaterial) { _, value in IslandPreferences.shared.glassMaterial = value }
                    if glassMaterial != .transparent {
                        Toggle("顶部黑色渐变", isOn: $glassGradient)
                        glassSlider("玻璃色调", value: $glassOpacity)
                        glassSlider("额外边缘高光", value: $glassRimStrength)
                    }
                    Button("恢复默认外观") {
                        glassMaterial = .regular
                        glassGradient = true
                        glassOpacity = IslandBackdropConfiguration.defaultDarkening
                        glassRimStrength = IslandBackdropConfiguration.defaultRim
                    }
                    if reduceTransparency {
                        Text("系统已开启“减少透明度”，当前显示纯黑背景。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("玻璃参数会独立保存，切换不会覆盖。")
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("展开背景", value: "纯黑")
            }
        }
        .onChange(of: glassGradient) { _, value in IslandPreferences.shared.glassGradientEnabled = value }
        .onChange(of: glassOpacity) { _, value in IslandPreferences.shared.glassOpacity = value }
        .onChange(of: glassRimStrength) { _, value in IslandPreferences.shared.glassRimStrength = value }
    }
    private func hudTrackSection(_ title: String, appearance: Binding<HUDTrackAppearance>, kind: HUDTrackKind) -> some View {
        Section(title) {
            let volume = kind == .volume
            hudColorPicker(volume ? "低音量颜色" : "低亮度颜色", rgb: appearance.lowColorRGB)
            hudColorPicker(volume ? "高音量颜色" : "高亮度颜色", rgb: appearance.highColorRGB)
            Toggle("HDR 高亮", isOn: appearance.hdrEnabled)
        }
        .onChange(of: appearance.wrappedValue) { _, value in
            IslandPreferences.shared.setHUDTrackAppearance(value, for: kind)
        }
    }

    private func hudColorPicker(_ title: String, rgb: Binding<UInt32>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: LyricsAppearance.color(for: rgb.wrappedValue)) },
            set: { if let value = LyricsAppearance.rgb(for: NSColor($0)) { rgb.wrappedValue = value } }
        ), supportsOpacity: false)
    }

    private var lyricsAppearancePage: some View {
        Section("歌词外观") {
            LyricAppearancePreview(appearance: lyricsAppearance, rightBackground: lyricsRightBackground).frame(height: 54).accessibilityHidden(true)
            Toggle("显示右侧歌词底色", isOn: $lyricsRightBackground)
                .onChange(of: lyricsRightBackground) { _, value in IslandPreferences.shared.lyricsRightBackground = value }
            lyricSlider("显示宽度", value: $lyricsAppearance.width, range: LyricsAppearance.widthRange,
                        formatted: "\(Int(lyricsAppearance.width.rounded())) pt")
            lyricSlider("底色不透明度", value: $lyricsAppearance.opacity, range: 0...1,
                        formatted: "\(Int((lyricsAppearance.opacity * 100).rounded()))%")
            lyricSlider("字号", value: $lyricsAppearance.size, range: LyricsAppearance.fontSizeRange,
                        formatted: "\(Int(lyricsAppearance.size.rounded())) pt")
            Picker("字重", selection: $lyricsAppearance.weight) {
                ForEach(LyricsAppearance.Weight.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            ColorPicker("字体颜色", selection: Binding(
                get: { Color(nsColor: lyricsAppearance.color) },
                set: { if let rgb = LyricsAppearance.rgb(for: NSColor($0)) { lyricsAppearance.colorRGB = rgb } }
            ), supportsOpacity: false)
            lyricSlider("文字光晕", value: $lyricsAppearance.glow, range: 0...1,
                        formatted: "\(Int((lyricsAppearance.glow * 100).rounded()))%")
            if lyricsAnimation == .appleMusic {
                Picker("歌词流光", selection: $lyricsAppearance.flowStyle) {
                    ForEach(LyricFlowStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("HDR 歌词高亮", isOn: $lyricsAppearance.hdrEnabled)
            }
            if lyricsAppearance.hdrEnabled && lyricsAnimation == .appleMusic {
                lyricSlider("HDR 强度", value: $lyricsAppearance.hdrStrength, range: 0...1,
                            formatted: "\(Int((lyricsAppearance.hdrStrength * 100).rounded()))%")
                if (IslandPreferences.shared.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) <= 1 {
                    Text("当前刘海所在的显示器使用普通高亮。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Button("恢复歌词默认样式", systemImage: "arrow.counterclockwise") { lyricsAppearance = LyricsAppearance() }
                .disabled(lyricsAppearance == LyricsAppearance())
        }.onChange(of: lyricsAppearance) { _, value in IslandPreferences.shared.lyricsAppearance = value }
    }

    private func lyricSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                             formatted: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 96, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
        }
    }
    private var connectedPage: some View {
        Group {
            Section("AirPods") {
                Toggle("开始使用时显示耳机动画与电量", isOn: $airPodsEnabled).onChange(of: airPodsEnabled) { _, value in IslandPreferences.shared.airPodsEnabled = value }
                Text(airPodsStatus.isEmpty ? IslandController.shared.airPodsStatus : airPodsStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(IslandController.shared.airPods.capabilityDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("查看实际电量") { IslandController.shared.showAirPods() }; Button("预览连接动画") { IslandController.shared.previewAirPods() } }
                Text("切为 Mac 声音输出并稳定后显示一次，后台电量刷新不弹窗。分别显示左右耳和耳机盒；盒盖关闭时，系统可能暂不更新盒内电量。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("刘海通知") {
                Toggle("接收系统通知横幅", isOn: $notificationsEnabled).onChange(of: notificationsEnabled) { _, value in IslandPreferences.shared.notificationsEnabled = value }
                Toggle("显示通知标题与正文", isOn: $notificationPreview).onChange(of: notificationPreview) { _, value in IslandPreferences.shared.notificationPreview = value }
                Picker("通知样式", selection: $notificationPlacement) { ForEach(NotificationPlacement.allCases, id: \.rawValue) { Text($0.title).tag($0) } }.pickerStyle(.segmented).onChange(of: notificationPlacement) { _, value in IslandPreferences.shared.notificationPlacement = value }
                if notificationPlacement == .sides {
                    lyricSlider("通知宽度", value: $notificationWidth, range: NotchNotificationLayout.widthRange,
                                formatted: "\(Int(notificationWidth.rounded())) pt")
                        .onChange(of: notificationWidth) { _, value in IslandPreferences.shared.notificationWidth = value }
                    lyricSlider("通知下展高度", value: $notificationDepth, range: NotchNotificationLayout.depthRange,
                                formatted: "\(Int(notificationDepth.rounded())) pt")
                        .onChange(of: notificationDepth) { _, value in IslandPreferences.shared.notificationDepth = value }
                }
                Text(notificationStatus.isEmpty ? IslandController.shared.notificationStatus : notificationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("预览通知") { IslandController.shared.previewNotification() }; Button("重新连接") { IslandController.shared.notificationBridge.reconnect() }; Button("辅助功能设置") { openPrivacy("Accessibility") } }
            }
        }
    }
    private func refreshDaily() {
        let controller = IslandController.shared
        actions = controller.quickActions.actions; shortcutNames = controller.quickActions.shortcutNames
        shortcutStatus = controller.quickActions.status; loadingShortcuts = controller.quickActions.loading
        calendarStatus = controller.calendar.status
        if !shortcutNames.contains(shortcutSelection) { shortcutSelection = shortcutNames.first ?? "" }
    }
    private var dailyPage: some View {
        Group {
            Section("日历与会议") {
                Toggle("连接系统日历", isOn: $calendarEnabled).onChange(of: calendarEnabled) { _, enabled in
                    if enabled { IslandController.shared.enableCalendar() }
                    else { IslandPreferences.shared.calendarEnabled = false }
                    refreshDaily()
                }
                Text(calendarStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("开始前 5 分钟提醒，支持会议链接。跳过全天、已取消和你已拒绝的日程；只读取，不更改日历。").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("查看日程") { IslandController.shared.showPanel(.calendar) }.disabled(!modules.contains(.calendar)); Button("日历权限设置") { openPrivacy("Calendars") } }
            }
            Section("快捷操作 · \(actions.count) / 6") {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) { Text(item.title).font(.system(size: 12)); Text(item.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        Button { IslandController.shared.quickActions.move(item.id, by: -1); refreshDaily() } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("向前移动")
                        Button { IslandController.shared.quickActions.move(item.id, by: 1); refreshDaily() } label: { Image(systemName: "chevron.down") }.disabled(index == actions.count - 1).help("向后移动")
                        Button { IslandController.shared.quickActions.remove(item.id); refreshDaily() } label: { Image(systemName: "minus.circle") }.help("移除操作")
                    }.controlSize(.small)
                }
                Divider()
                HStack {
                    Button("添加应用…") { IslandController.shared.quickActions.choose(.application) }
                    Button("添加文件夹…") { IslandController.shared.quickActions.choose(.folder) }
                    Button(loadingShortcuts ? "读取中…" : "读取快捷指令") { IslandController.shared.quickActions.loadShortcuts(); refreshDaily() }.disabled(loadingShortcuts)
                }.disabled(actions.count >= 6)
                if !shortcutNames.isEmpty {
                    HStack {
                        Picker("快捷指令", selection: $shortcutSelection) { ForEach(shortcutNames, id: \.self) { Text($0).tag($0) } }
                        Button("添加") {
                            _ = IslandController.shared.quickActions.add(.init(title: shortcutSelection, kind: .shortcut, target: shortcutSelection)); refreshDaily()
                        }.disabled(actions.count >= 6 || shortcutSelection.isEmpty || actions.contains { $0.kind == .shortcut && $0.target == shortcutSelection })
                    }
                }
                if !shortcutStatus.isEmpty { Text(shortcutStatus).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text("由系统快捷指令 App 执行，沿用该指令的权限和确认设置。").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
    private var displayPage: some View {
        Group {
            Section("显示位置") {
                Picker("显示器", selection: $display) {
                    Text("自动 · 优先内置屏幕").tag(UInt32(0))
                    ForEach(screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                    if display != 0 && !screens.contains(where: { $0.displayID == display }) { Text("已断开的显示器 · 暂用自动").tag(display) }
                }.onChange(of: display) { _, value in IslandPreferences.shared.displayID = value }
                Text("自动适配刘海尺寸；无刘海显示器使用顶部胶囊。").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("全屏应用中", selection: $fullscreen) { Text("正常显示").tag(0); Text("仅保留胶囊").tag(1); Text("隐藏").tag(2) }.onChange(of: fullscreen) { _, value in IslandPreferences.shared.fullscreenMode = value }
                Text("闹钟到点仍会显示停止按钮。全屏判断依据前台窗口尺寸。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("按应用隐藏") {
                Text("填写应用的 Bundle ID，用英文逗号分隔。").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("例如 com.apple.Keynote, com.apple.QuickTimePlayerX", text: $exclusions).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("保存应用规则") { IslandPreferences.shared.excludedApps = exclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } } }
            }
        }
    }
    private var permissionsPage: some View {
        Group {
            Section("音乐") {
                Text("自动跟随正在播放的应用").font(.system(size: 13))
                Text(musicStatus.isEmpty ? "播放音乐后显示歌曲、封面和进度" : musicStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("重新读取 / 请求授权") { IslandController.shared.promptMusicAuth() }; Button("自动化设置") { openPrivacy("Automation") } }
                Divider()
                Picker("收起时的歌词", selection: $lyricsPlacement) {
                    Text("隐藏").tag(LyricsPlacement.hidden)
                    Text("刘海下方").tag(LyricsPlacement.below)
                    Text("刘海左侧").tag(LyricsPlacement.side)
                }.pickerStyle(.segmented).onChange(of: lyricsPlacement) { _, value in IslandPreferences.shared.lyricsPlacement = value }
                Picker("展开时的歌词", selection: $expandedLyricsPlacement) {
                    Text("隐藏").tag(LyricsPlacement.hidden)
                    Text("控制键下方").tag(LyricsPlacement.below)
                    Text("播放器右侧").tag(LyricsPlacement.side)
                }.pickerStyle(.segmented).onChange(of: expandedLyricsPlacement) { _, value in IslandPreferences.shared.expandedLyricsPlacement = value }
                Picker("歌词动画", selection: $lyricsAnimation) { ForEach(LyricsAnimationStyle.allCases, id: \.rawValue) { Text($0.title).tag($0) } }.onChange(of: lyricsAnimation) { _, value in IslandPreferences.shared.lyricsAnimation = value }
                HStack { Text(lyricsDirectory).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1); Spacer(); Button("选择歌词目录…") { chooseLyricsDirectory() } }
                Toggle("自动查找在线歌词", isOn: $onlineLyrics).onChange(of: onlineLyrics) { _, value in IslandPreferences.shared.onlineLyrics = value }
                Text("优先使用本地 LRC。在线查找会将曲名、歌手、专辑和时长提交给 LRCLIB；未匹配时，通过网易云音乐检索曲名和歌手。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("计时") {
                Toggle("收起时显示倒计时", isOn: $focusDisplay).onChange(of: focusDisplay) { _, value in IslandPreferences.shared.focusDisplayEnabled = value }
            }
            Section("系统提示") {
                Toggle("接管音量与亮度按键", isOn: $takeover).onChange(of: takeover) { _, enabled in
                    if enabled { IslandController.shared.requestMediaKeyTakeover() } else { IslandPreferences.shared.takeover = false }
                }
                Text(status.isEmpty ? "开启后需允许辅助功能权限；不支持的按键会交给系统。" : status).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("重新启用") { IslandController.shared.requestMediaKeyTakeover(); takeover = true }; Button("辅助功能设置") { openPrivacy("Accessibility") } }
            }
        }
    }
    private func glassSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent {
            HStack(spacing: 12) {
                Slider(value: value, in: 0...1).accessibilityLabel(title)
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        } label: {
            Text(title).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func chooseLyricsDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { lyricsDirectory = url.path; IslandPreferences.shared.lyricsDirectory = url.path }
    }
    private func openPrivacy(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)") { NSWorkspace.shared.open(url) } }
}
