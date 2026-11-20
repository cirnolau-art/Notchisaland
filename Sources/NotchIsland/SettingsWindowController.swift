import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 610), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "灵动岛设置"; window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
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
    @State private var glassBlur = IslandPreferences.shared.glassBlur
    @State private var glassOpacity = IslandPreferences.shared.glassOpacity
    @State private var airPodsEnabled = IslandPreferences.shared.airPodsEnabled
    @State private var notificationsEnabled = IslandPreferences.shared.notificationsEnabled
    @State private var notificationPreview = IslandPreferences.shared.notificationPreview
    @State private var notificationPlacement = IslandPreferences.shared.notificationPlacement
    @State private var notificationSide = IslandPreferences.shared.notificationSide
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
    @State private var invert = UserDefaults.standard.bool(forKey: "notchisland.invertScrollV2")
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "capsule.inset.filled").font(.system(size: 28)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) { Text("灵动岛").font(.system(size: 23, weight: .semibold)); Text("让常用操作，近在手边").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Text(AppVersion.display).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .help("版本 \(AppVersion.release) · 构建 \(AppVersion.build)")
            }
            Picker("设置分类", selection: $page) { Text("交互").tag(0); Text("外观").tag(1); Text("设备与通知").tag(2); Text("音乐与权限").tag(3); Text("日程与快捷").tag(4); Text("模块").tag(5) }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if page == 0 { interactionPage }
                    else if page == 1 { appearancePage; displayPage }
                    else if page == 2 { connectedPage }
                    else if page == 3 { permissionsPage }
                    else if page == 4 { dailyPage }
                    else { modulesPage }
                }.padding(.vertical, 4)
            }
            Divider()
            Text("© 2026 Lau Kachun · 文件暂存只保留引用，不移动原文件")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(26).frame(width: 580, height: 610).background(Color(nsColor: NSColor(calibratedWhite: 0.075, alpha: 1)))
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
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    private var modulesPage: some View {
        VStack(spacing: 18) {
            card("展开面板 · 按需开启") {
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
            card("剪贴板隐私") {
                Text("默认关闭；开启后从下一次复制开始记录。跳过带保密标记的内容和常见密码管理器。退出或关闭模块会清空历史，不会清空系统剪贴板。").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("单张图片最多 4 MB，文字最多 1 MB。普通文字中的敏感内容无法自动判断；复制敏感资料前请关闭此模块。").font(.system(size: 11)).foregroundStyle(.tertiary)
                Button("清空本次历史") { IslandController.shared.clipboardHistory.clear() }.disabled(!modules.contains(.clipboard))
            }
            card("即时提示") {
                Toggle("音量与亮度", isOn: $systemHUD).onChange(of: systemHUD) { _, value in IslandPreferences.shared.systemHUDEnabled = value }
                Toggle("输入法切换", isOn: $inputHUD).onChange(of: inputHUD) { _, value in IslandPreferences.shared.inputHUDEnabled = value }
                Toggle("电源连接", isOn: $powerHUD).onChange(of: powerHUD) { _, value in IslandPreferences.shared.powerHUDEnabled = value }
                Text("耳机与通知可在“设备与通知”中分别开关。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private var interactionPage: some View {
        VStack(spacing: 18) {
            card("顺手的交互") {
                Toggle("悬停预览", isOn: $hover).onChange(of: hover) { _, value in IslandPreferences.shared.hoverPreview = value }
                Text("停留片刻显示摘要，点击展开；横向滑动切换模块。").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("离开后自动收起", selection: $autoHide) { Text("5 秒").tag(5.0); Text("10 秒").tag(10.0); Text("15 秒").tag(15.0); Text("30 秒").tag(30.0); Text("手动收起").tag(0.0) }.onChange(of: autoHide) { _, value in IslandPreferences.shared.autoHide = value }
                Text("指针停留、拖动和输入时保持展开。Esc 或点击外部收起。").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("反转展开手势方向", isOn: $invert).onChange(of: invert) { _, value in UserDefaults.standard.set(value, forKey: "notchisland.invertScrollV2") }
            }
            card("动画与启动") {
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
        card("刘海外观") {
          if supportsGlass {
            Picker("背景模式", selection: $background) { Text("纯黑").tag(IslandBackgroundStyle.black); Text("液态玻璃").tag(IslandBackgroundStyle.glass) }
                .pickerStyle(.segmented).onChange(of: background) { _, value in IslandPreferences.shared.backgroundStyle = value }
            if background == .glass {
                    HStack { Text("背景模糊"); Slider(value: $glassBlur, in: 0...1).onChange(of: glassBlur) { _, value in IslandPreferences.shared.glassBlur = value }; Text("\(Int(glassBlur * 100))%").monospacedDigit().frame(width: 38) }
                    HStack { Text("不透明度"); Slider(value: $glassOpacity, in: 0...1).onChange(of: glassOpacity) { _, value in IslandPreferences.shared.glassOpacity = value }; Text("\(Int(glassOpacity * 100))%").monospacedDigit().frame(width: 38) }
                    Text("顶部保持纯黑遮住刘海，下方过渡到 Apple 原生液态玻璃，保留通透边缘。模糊控制原生材质强度；系统未提供自定义折射或模糊半径。").font(.system(size: 11)).foregroundStyle(.secondary)
            } else { Text("保持纯黑、清晰的刘海轮廓。玻璃参数会独立保存，切换不会覆盖。").font(.system(size: 11)).foregroundStyle(.secondary) }
            Text("空闲时不保留玻璃合成效果；遵循系统“减少透明度”设置。").font(.system(size: 11)).foregroundStyle(.tertiary)
          } else {
              Text("纯黑背景").font(.system(size: 13))
              Text("轮廓贴合屏幕刘海，收起后保持原有厚度。").font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }
    }
    private var connectedPage: some View {
        VStack(spacing: 18) {
            card("AirPods") {
                Toggle("开始使用时显示耳机动画与电量", isOn: $airPodsEnabled).onChange(of: airPodsEnabled) { _, value in IslandPreferences.shared.airPodsEnabled = value }
                Text(airPodsStatus.isEmpty ? IslandController.shared.airPodsStatus : airPodsStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(IslandController.shared.airPods.capabilityDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("查看实际电量") { IslandController.shared.showAirPods() }; Button("预览连接动画") { IslandController.shared.previewAirPods() } }
                Text("切为 Mac 声音输出并稳定后显示一次，后台电量刷新不弹窗。分别显示左右耳和耳机盒；盒盖关闭时，系统可能暂不更新盒内电量。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            card("刘海通知") {
                Toggle("接收系统通知横幅", isOn: $notificationsEnabled).onChange(of: notificationsEnabled) { _, value in IslandPreferences.shared.notificationsEnabled = value }
                Toggle("显示通知标题与正文", isOn: $notificationPreview).onChange(of: notificationPreview) { _, value in IslandPreferences.shared.notificationPreview = value }
                Picker("通知位置", selection: $notificationPlacement) { ForEach(NotificationPlacement.allCases, id: \.rawValue) { Text($0.title).tag($0) } }.pickerStyle(.segmented).onChange(of: notificationPlacement) { _, value in IslandPreferences.shared.notificationPlacement = value }
                if notificationPlacement == .sides {
                    Picker("小窗口位置", selection: $notificationSide) {
                        Text("刘海左侧").tag(NotificationSide.left)
                        Text("刘海右侧").tag(NotificationSide.right)
                    }.pickerStyle(.segmented).onChange(of: notificationSide) { _, value in
                        IslandPreferences.shared.notificationSide = value
                    }
                }
                Text(notificationStatus.isEmpty ? IslandController.shared.notificationStatus : notificationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("预览通知") { IslandController.shared.previewNotification() }; Button("重新连接") { IslandController.shared.notificationBridge.reconnect() }; Button("辅助功能设置") { openPrivacy("Accessibility") } }
                Text("需要辅助功能权限，并保留来源应用的系统横幅。两侧小窗口不改变刘海尺寸；专注／勿扰模式延后投递的通知不会显示。").font(.system(size: 11)).foregroundStyle(.secondary)
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
        VStack(spacing: 18) {
            card("日历与会议") {
                Toggle("连接系统日历", isOn: $calendarEnabled).onChange(of: calendarEnabled) { _, enabled in
                    if enabled { IslandController.shared.enableCalendar() }
                    else { IslandPreferences.shared.calendarEnabled = false }
                    refreshDaily()
                }
                Text(calendarStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("开始前 5 分钟提醒，支持会议链接。跳过全天、已取消和你已拒绝的日程；只读取，不更改日历。").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("查看日程") { IslandController.shared.showPanel(.calendar) }.disabled(!modules.contains(.calendar)); Button("日历权限设置") { openPrivacy("Calendars") } }
            }
            card("快捷操作 · \(actions.count) / 6") {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) { Text(item.title).font(.system(size: 12)); Text(item.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        Button { IslandController.shared.quickActions.move(item.id, by: -1); refreshDaily() } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("向前移动")
                        Button { IslandController.shared.quickActions.move(item.id, by: 1); refreshDaily() } label: { Image(systemName: "chevron.down") }.disabled(index == actions.count - 1).help("向后移动")
                        Button { IslandController.shared.quickActions.remove(item.id); refreshDaily() } label: { Image(systemName: "minus.circle") }.help("移除操作")
                    }.buttonStyle(.borderless)
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
        VStack(spacing: 18) {
            card("显示位置") {
                Picker("显示器", selection: $display) {
                    Text("自动 · 优先内置屏幕").tag(UInt32(0))
                    ForEach(screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                    if display != 0 && !screens.contains(where: { $0.displayID == display }) { Text("已断开的显示器 · 暂用自动").tag(display) }
                }.onChange(of: display) { _, value in IslandPreferences.shared.displayID = value }
                Text("自动适配刘海尺寸；无刘海显示器使用顶部胶囊。").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("全屏应用中", selection: $fullscreen) { Text("正常显示").tag(0); Text("仅保留胶囊").tag(1); Text("隐藏").tag(2) }.onChange(of: fullscreen) { _, value in IslandPreferences.shared.fullscreenMode = value }
                Text("闹钟到点仍会显示停止按钮。全屏判断依据前台窗口尺寸。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            card("按应用隐藏") {
                Text("填写应用的 Bundle ID，用英文逗号分隔。").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("例如 com.apple.Keynote, com.apple.QuickTimePlayerX", text: $exclusions).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("保存应用规则") { IslandPreferences.shared.excludedApps = exclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } } }
            }
        }
    }
    private var permissionsPage: some View {
        VStack(spacing: 18) {
            card("音乐") {
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
            card("计时") {
                Toggle("收起时显示倒计时", isOn: $focusDisplay).onChange(of: focusDisplay) { _, value in IslandPreferences.shared.focusDisplayEnabled = value }
            }
            card("系统提示") {
                Toggle("接管音量与亮度按键", isOn: $takeover).onChange(of: takeover) { _, enabled in
                    if enabled { IslandController.shared.requestMediaKeyTakeover() } else { IslandPreferences.shared.takeover = false }
                }
                Text(status.isEmpty ? "开启后需允许辅助功能权限；不支持的按键会交给系统。" : status).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { Button("重新启用") { IslandController.shared.requestMediaKeyTakeover(); takeover = true }; Button("辅助功能设置") { openPrivacy("Accessibility") } }
            }
        }
    }
    private func chooseLyricsDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url { lyricsDirectory = url.path; IslandPreferences.shared.lyricsDirectory = url.path }
    }
    private func openPrivacy(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)") { NSWorkspace.shared.open(url) } }
}
