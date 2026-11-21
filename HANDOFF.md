# NotchIsland 交接

## 项目现状

- 仓库为 `/Users/kachunlau/Documents/GitHub/Dinamic-island-but-DIYed-by-Cirnolau`。当前工作树版本是 **1.7.8（构建 19）**，来源为 `Version.env`。本地安装包为 `dist/NotchIsland-1.7.8-arm64.dmg`，最低 macOS 15.0，Apple 芯片。已有 `RELEASE.md` 写到 1.7.3。
- 分支 `main` 跟踪 `origin/main`。本地记录中两者均指向 `9a5fc8dfd560d9b18f078826a10862907a25bd8f`（说明书更新）。没有暂存改动。1.7.4–1.7.8 是相对该 HEAD 的本地改动和构建产物。
  下列路径相对于仓库根目录，`M` 表示已跟踪但未暂存，`??` 表示未跟踪。清单计入这份交接文档，`dist/` 和 `artifacts/` 已被 Git 忽略。

| 状态 | 文件 | 改动 |
|---|---|---|
| M | `Sources/NotchIsland/IslandBackdropView.swift` | 原生玻璃、顶部渐变、全透明分支和过渡清理 |
| M | `Sources/NotchIsland/IslandController.swift` | 显示器与辅助功能刷新、计时器更新和播放诊断入口 |
| M | `Sources/NotchIsland/IslandPreferences.swift` | 独立保存玻璃材质、渐变和色调，外观变化走轻量刷新 |
| M | `Sources/NotchIsland/IslandView.swift` | 刘海形变、歌词显隐、歌词层级与媒体控件更新 |
| M | `Sources/NotchIsland/IslandWindow.swift` | 透明窗口使用扩展 sRGB 色彩空间 |
| M | `Sources/NotchIsland/LyricRollView.swift` | 缓存歌词行、滚动与淡出，移除行容器的渐变遮罩 |
| M | `Sources/NotchIsland/Lyrics.swift` | 按已知时间处理长间奏和歌曲结束 |
| M | `Sources/NotchIsland/LyricsAppearance.swift` | HDR 开关、强度和旧设置解码 |
| M | `Sources/NotchIsland/MusicAppMonitor.swift` | Music/Spotify 播放事件、AppleScript 补充查询与旧结果隔离 |
| M | `Sources/NotchIsland/SettingsWindowController.swift` | 展开材质、顶部渐变、HDR 设置及可用性 |
| M | `Sources/NotchIsland/Snapshot.swift` | 运行时播放、歌词、玻璃与形变检查 |
| M | `Tests/NotchIslandTests/ConnectedActivityTests.swift` | 玻璃设置保存和模式独立性 |
| M | `Tests/NotchIslandTests/ModuleClipboardTests.swift` | 移除旧玻璃渐变实现的断言，现由玻璃专项覆盖 |
| M | `Tests/NotchIslandTests/SecondBatchTests.swift` | 原生玻璃色调及兼容降级断言 |
| M | `Version.env` | 版本 1.7.8、构建 19 |
| ?? | `Sources/NotchIsland/LyricHighlight.swift` | 真实字词时间和 EDR 增益计算 |
| ?? | `Sources/NotchIsland/LyricTextView.swift` | Core Text 字形缓存、逐字动画和 EDR 图像合成 |
| ?? | `Sources/NotchIsland/PolishPreview.swift` | 明暗背景及手动展开和收起的隔离预览 |
| ?? | `Tests/NotchIslandTests/GlassBackdropTests.swift` | 收起无玻璃、渐变像素、清透保留原生玻璃及反向切换检查 |
| ?? | `Tests/NotchIslandTests/IslandAnimationTests.swift` | 异步歌词、控件复用和动画连续性检查 |
| ?? | `Tests/NotchIslandTests/LyricCompositingTests.swift` | 歌词层级与浮点渲染输出检查 |
| ?? | `Tests/NotchIslandTests/MusicPlaybackTests.swift` | 播放事件、旧轮询结果和暂停状态检查 |
| ?? | `Tests/NotchIslandTests/PolishTests.swift` | 前奏、暂停和隐藏时的渲染资源、旧设置与 HDR 负载检查 |
| ?? | `docs/superpowers/plans/2026-11-20-island-polish.md` | 1.7.4 实施计划，其中的捏合方案已被 1.7.6 撤销 |
| ?? | `docs/verification/1.7.4.md` | 1.7.4 的历史验证记录和实机验证边界 |
| ?? | `HANDOFF.md` | 本交接文档 |

## 已完成

- **1.7.0**：加入在线歌词、系统专注模式和通知显示位置。
- **1.7.1**：加入歌词滚动、逐字时间轴和逐字高亮。
- **1.7.2**：加入歌词外观自定义和对称渐隐底色，补充输入法监听、专注诊断及 AirPods 电量匹配。
- **1.7.3**：加入贴合刘海的通知布局、长歌词自动换行和逐字渐亮，并调整玻璃参数、AirPods 补读和专注状态读取。
- **1.7.4**：修前奏空歌词底色闪烁和过期隐藏任务，重做歌词布局与动画、简化玻璃阴影，加入可选 HDR 和双指捏合完全收起。
- **1.7.5**：把原生玻璃移出父级遮罩，修正 EDR 请求条件，稳定异步歌词到达时的展开面板，并取消切模块时的同步截图。
- **1.7.6**：移除捏合及持续隐藏状态，接入 Music/Spotify 播放事件，修正压回 SDR 的色调映射并把展开歌词移出遮罩，同时曾让紧凑播放两翼显示玻璃。
- **1.7.7**：恢复紧凑态整条纯黑，展开可选标准玻璃、轻模糊或全透明，新增顶部渐变开关，并同步轮廓、背景与内容退场。
- **用户实测**：用户跑过 1.7.5 阶段的 115 项测试且全过，随后在 1.7.6 报告紧凑两翼发灰及分段收起。1.7.7 实测反馈为材质观感未达到原生液态玻璃、展开和收起有色块分离、「完全透明」丢失液态玻璃；设置界面也需对齐 macOS 原生风格并使用液态玻璃按钮。
- **仅程序验证通过**：1.7.7 的 120 项测试、打包后交互检查、arm64 DMG 校验、签名与启动检查通过。窗口中采到收起高度 `280 → 203.7 → 95.5 → 38 pt`，黑底 alpha 随过渡增加，快速反向检查通过。HDR 的浮点合成输出超过 SDR 白色，播放通过模拟事件走到界面。真实播放事件、窗口上实际折射和肉眼 HDR 亮度均未验证。对 macOS 15/26 未做这一版的真机测试。
- **2026-11-21 · 1.7.7 界面诊断**：在本机 macOS 27.3 启动构建 18 的浅色隔离预览，录到收起时底部玻璃先脱离轮廓、歌词留在轮廓外，展开时歌词先于面板出现。标准档截图可见灰色模糊与上方深色渐变。代码确认「完全透明」直接移除原生玻璃，主体在快速反向时将呈现位移截断到 3–16 pt，展开歌词单独移动且没有同步进场，紧凑歌词也独立定位和淡入淡出。另在屏幕上复现预览按 `5` 或 `6` 时，如果保持展开，原材质不变，需先收起才生效。录屏为 `/private/tmp/notchisland-177-preview.UYLFHg/motion-slow.mp4`。本阶段为诊断，应用源码和打包产物未改动。
- **2026-11-21 · 原生材质专项**：清透档沿用原设置编号，改为原生 `.clear`，停用额外色调、黑色渐变和边缘高光。更新玻璃尺寸测试，验证 AppKit 内容视图跟随实际玻璃尺寸；清透回归先失败后通过，玻璃专项 5 项全过。隔离预览加入三种玻璃与渐变切换并走现有外观刷新入口，待与动画一并跑屏幕验证。
- **2026-11-21 · 动画与屏幕对照**：轮廓动画驱动 AppKit 玻璃的真实视图尺寸。移除主体和展开歌词的独立垂直位移，反向时复用同一布局。展开歌词在自身离开轮廓前淡出，保留无遮罩的 HDR 图层；紧凑歌词随过渡显隐。动画回归先失败后通过。在明暗测试背景录屏复核纯黑收起、连续反向、三种原生玻璃和渐变开关，确认同尺寸切换生效。画面检查另外发现浅色玻璃上的前景对比不足，已加入控件与歌词的局部对比，待随最终构建复核。
- **1.7.8 · 设置与最终验证**：设置改用跟随系统明暗的 SwiftUI 原生分组表单，六个分类沿用原入口。macOS 26 起动作按钮使用 `.glass`，旧系统保留标准按钮。通过明暗窗口截图和隔离设置交互，切换六个分类，并从清透档恢复默认、重新打开核对渐变、色调与高光。玻璃默认附加色调降为 0，已保存的色调仍保留。在本机 macOS 27.3 最终验证 121 项测试、打包交互、明暗背景慢放、清透前景、DMG 校验和 SHA-256、挂载后的签名、应用拖拽入口与启动检查。详细记录为 `/private/tmp/notchisland-178-qa.d6mVni/app.log`，浅色慢放为 `/private/tmp/notchisland-178-screen.7bKgyh/light-slow.mp4`，设置明暗截图同目录。用户验收、macOS 15/26 真机、实际播放及实屏 HDR 对比仍待复核。
- **2026-11-21 · README**：已更新 1.7.8 的功能、玻璃外观入口、系统要求与本地 DMG 构建步骤。

## 待办（按优先级）

1. **P0 · 1.7.8 用户复核** — 检查用户桌面背景上的标准、轻模糊、清透玻璃和设置明暗外观，播放状态下快速展开、收起及反向。从用户发现的问题和本机的同帧检查继续定位。
2. **P1 · 真实播放有无漏报** — 1.7.5 有播放后刘海不响应的反馈 → `MusicAppMonitor.swift:44`、`:80`、`:104`，`IslandController.swift:259`、`:294`，`Snapshot.swift` 的 `runPlaybackCheck` → 本机 macOS 27 日志显示 MediaRemote 读取曲目被拒绝，旧版等脚本查询且曾被持续隐藏状态阻挡 → 用户允许后，用正常安装的 app 分别实测 Music 和 Spotify 的播放、暂停、换歌与退出，再看「音乐与权限」及 `/tmp/notchisland.log`。合成事件已通过，脚本权限是否为用户当时的故障原因未确认。若还漏报，先查分发事件是否收到和选源结果，再检查自动化权限。未授权时首个事件可先显示歌名，精确进度、封面和控制仍依赖相应权限。
3. **P1 · HDR 和系统兼容** — 之前开启 HDR 仍看不出亮度差 → `LyricTextView.swift:106`、`:157`、`:265`，`IslandView.swift` 的 `buildMusic`，`Tests/NotchIslandTests/LyricCompositingTests.swift:33` → 旧 `.ifSupported` 会把测试渲染压到 1.0，父级遮罩不一定压低亮度，已用带/不带遮罩的离屏对照排除“遮罩必然夹回 SDR” → 在 HDR 内屏与普通外接屏上用同一段白色歌词切换 HDR 和强度，记录显示器余量，同时在 macOS 15/26 运行 DMG 内程序的 `--startup-check` 并启动正常界面。当前浮点测试没有测量屏幕亮度。若只在真机失效，查显示器余量和透明窗口合成，不要调高像素来掩盖问题。
4. **P2 · 系统功能的旧反馈复核** — 通知未接管、AirPods 不弹电量、专注或输入法未识别都曾有反馈 → `NotificationBridge.swift:50`、`:118`，`IslandController.swift:315`、`:326`，`AirPodsMonitor.swift:256`、`:349`，`SystemFocusMonitor.swift:154`、`:183`，`InputSourceMonitor.swift:32` → 可能分别卡在辅助功能授权或通知结构、音频路由或电量补读、控制中心状态/输入法事件，当前版未有用户验收 → 若重新收到报告，先跑已授权应用的 `--diagnose-notifications`，AirPods 单独验证“仅开盒、实际切到耳机输出、静置”三种情况，其余分别切一次「减少打扰」和输入法。先记录系统事件是否到达，再改对应 monitor，避免把后台刷新当作连接事件。

## 关键约束（踩过的坑）

- 用户明确要求：收起时连播放两翼都纯黑，刘海贴住屏幕顶边。展开默认从上黑渐变到底部透明，材质观感对齐 Apple 原生液态玻璃，清透档也要保留原生玻璃。动画连续、快速反向从当前状态继续。闲置开销低，设置按模块独立，可关的模块不占展开面板。
- 用户明确拒绝：双指捏合和因此触发的持续隐藏、灰色紧凑玻璃、手选播放器、要求手工下载歌词、AirPods 静置时反复弹电量。保留普通滚动手势、自动识别播放来源与在线歌词。AirPods 自动提示以实际音频输出为现有触发依据，不能宣称检测到佩戴。
- 歌词必须自动换行并保留原时间；真逐字数据做逐字渐亮，普通 LRC 整句亮，省资源模式只滚动、关闭 HDR 增强。HDR 开关和光晕独立，尊重减少透明度、减少动态效果与多屏能力。测试过的离屏浮点值与实屏亮度分开记录。
- **macOS 15**：最低部署目标。HDR 图像的 `CGImage(headroom:…)` 从 15 可用，图层用 `wantsExtendedDynamicRangeContent`（14 起可用，26 弃用）。无原生玻璃入口，使用纯黑外观。**macOS 26**：`NSGlassEffectView` 的 `.regular`、`.clear` 和 `CALayer.preferredDynamicRange` 可用，玻璃类必须弱链接。清透档需保留系统 `.clear`，避免自绘不透明层盖住材质。**macOS 27**：`effectIsInteractive` 从 27 可用，当前没有调用；旧 MediaRemote 是私有兼容路径，27 上可能因权限拿不到数据，优先排查 Music/Spotify 事件与 AppleScript 路径。
- 从仓库根目录执行 `swift test --disable-sandbox`，最新记录是 **121 项、0 失败**（本机 macOS 27.3 / Xcode 27.2，日志 `/private/tmp/notchisland-178-tests.log`）。没有已确认会在当前版随机失败的用例。剪贴板测试需要登录桌面会话和粘贴板服务，先区分环境失败。旧快照曾在主队列嵌套等待淡出，阻塞实际清理，已改成异步续跑。
- 构建执行 `./build-app.sh`，用 `open -n -W dist/NotchIsland.app --args --snapshot --snapshot-output /private/tmp/notchisland-qa` 检查 `verification.txt`。安装包执行 `./build-dmg.sh --skip-build`，复核版本、签名、SHA-256 和 /Applications 拖拽入口。安装包为本地临时签名，未公证。未经用户要求，不提交或推送 GitHub、不发布 Release、不替换已安装应用。项目按 GPL-3.0 分发，保留 Lau Kachun 版权。

## 下一步第一件事

用本地 1.7.8 安装包或隔离预览复核用户环境下的玻璃、动画和设置外观。`PolishPreview.swift` 的 `1`、`2` 展开和收起，`6–8` 切换三种原生玻璃，`9` 切换渐变，`0` 打开隔离设置。每阶段完成后更新本文件的「已完成」和「待办」。
