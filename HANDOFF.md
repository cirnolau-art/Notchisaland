# NotchIsland 交接

## 项目现状

- 仓库为 `/Users/kachunlau/Documents/GitHub/Dinamic-island-but-DIYed-by-Cirnolau`。当前工作树版本是 **1.8.3（构建 25）**，来源为 `Version.env`。最低 macOS 15.0，Apple 芯片。`RELEASE.md` 已补充 1.8.3 更新说明并保留历史版本。
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
| M | `RELEASE.md` | 新增 1.8.0 更新说明和验证记录 |
| M | `Version.env` | 版本 1.8.2、构建 24 |
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
- **1.7.9 · 音量、亮度与滚动**：只由接管的媒体键弹出音量和亮度 HUD。后台读数继续维护硬件状态，音频面板保持刷新，已打开的 HUD 只响应按键和岛内滑块。自然滚动默认跟随系统，可在交互设置覆盖或恢复；迁移旧反转设置。音量及亮度提示条分别保存低值色、高值色和 HDR 开关；颜色在线性 sRGB 插值，HDR 随百分比升高。38 项定向测试通过，覆盖后台误弹回归、滚动迁移、端点颜色、峰值增益和两条提示的独立配置。
- **1.7.9 · 构建验证**：本机登录桌面会话中完整测试 128 项全部通过，日志为 `/private/tmp/notchisland-179-desktop-tests.log`。生产构建、临时签名、DMG 校验及打包后隔离快照检查通过。自动化验证覆盖真实 HUD 层的浮点图像与峰值余量标记，物理媒体键、鼠标/触控板方向和实屏 HDR 亮度待复核。
- **1.7.10 · 歌词流光**：歌词外观新增默认关闭的 RGB 和封面流光，支持收起与展开。已唱部分仍按原歌词时间高亮，收起时字边泛光更集中，字芯偏白。封面取色在后台运行，单色封面保留自身色调，灰阶或缺封面时使用白光。暂停冻结，省资源模式停用流光。完整测试 133 项通过，浮点合成确认字形遮罩后的流光仍有超 SDR 输出。
- **1.7.10 · 打包验证**：签名、启动检查和安装包校验通过。在本机 macOS 27.3 用打包版预览两档流光的收起与展开画面，暂停前后取样区域哈希一致。截图为 `/private/tmp/notchisland-1710-screen.BGkDzY/flow-review.jpg`。当前 HDR 浮点合成和本机屏幕余量已核对，尚未测量面板实际亮度。
- **2026-11-22 · 歌词滚动策略第一阶段**：参考 AM++ 与 AMLyricBlur 的稳定行身份和连续目标重定向，新增 `LyricRollPolicy`，当前行保持清晰，前后行按距离降低透明度并增加方向性模糊。`LyricRollView` 改为前一行、当前行、下一行角色轮换，滚动使用绝对位置动画并读取 presentation 状态，保留现有 RGB、封面取色、逐字高亮和 HDR 图层。新增策略测试 4 项和行轮换反向测试 1 项通过，歌词、动画、流光与界面相关定向测试 50 项通过。完整测试和打包版实机画面仍待复核。
- **2026-11-22 · 歌词滚动验证边界**：定向测试 50 项通过，其中 2 项需要 EDR/Metal 而跳过。完整 `swift test --disable-sandbox` 仍被登录桌面服务环境中的 `InputSourceTests.testDistributedChangeIsDeliveredOnceAndStopsWithTheModule`、`ModuleClipboardTests.testCountAndByteCapsAndOversizedInputs` 及其后续 xctest signal 5 阻断，未观察到歌词相关失败。生产脚本受仓库 `.build` 目录权限阻断，隔离 scratch 的 debug 构建通过，打包版滚动实机画面尚未复核。
- **1.7.10 · GitHub Release 配图**：通过本地 API 的 Gemini 3.1 Flash Image 生成并检查了版本封面、RGB 流光和封面取色流光三张静态宣传图，存于 `/Users/kachunlau/Documents/ChatGPT/ceshi/notchisland-1.7.10-release-images/`。
- **1.7.10 · 实机演示图**：已在本机用 Apple Music 播放 IVE 的《XOXZ》，确认收起和展开均显示歌词，分别截取 RGB 流光和封面流光的四张窗口截图。成品位于 `/Users/kachunlau/Documents/ChatGPT/ceshi/notchisland-1.7.10-release-images/XOXZ/`。
- **1.8.0 · 歌词逐行滚动**：参考 AM++ 与 AMLyricBlur 的稳定行身份、前后行模糊和连续目标重定向，采用逐行卡片式滚动。当前行保持清晰居中，前后行按距离降低透明度并增加方向性模糊，快速正向和反向切换从 presentation 状态继续，保留 RGB、封面取色、逐字高亮和 HDR。定向歌词、动画、流光与界面测试共 50 项通过，其中 2 项 EDR/Metal 测试因环境条件跳过。
- **1.8.0 · 版本元数据**：`Version.env` 已升级为版本 1.8.0、构建 22，README 的本地构建和 DMG 文件名已同步，arm64 DMG 已生成并完成验证。
- **1.8.0 · 发布打包**：`./build-app.sh` 和 `./build-dmg.sh --skip-build` 已完成。`dist/NotchIsland-1.8.0-arm64.dmg` 通过 `verify-release.py`、arm64、最低 macOS 15、签名、DMG CRC 校验、SHA-256 和挂载结构检查。SHA-256 为 `47031eefad1e6f7c634c5c386618debee45bc411214d35eba817205a30af7009`。完整 Swift 测试 138 项通过，日志为 `/private/tmp/notchisland-180-tests.log`。
- **1.8.1 · 歌词回归修复**：修复初始布局在保存 `nextLine` 前就隐藏下一行，及滚动切换后新当前行继承 `isHidden` 的问题。新增“展开下一行可见”和“滚动当前行可见”回归测试，完整 Swift 测试 140 项通过，日志为 `/private/tmp/notchisland-181-tests.log`。模糊度策略保持不变。
- **1.8.1 · 版本元数据**：`Version.env` 已升级为版本 1.8.1、构建 23，README 和 RELEASE 已同步，arm64 DMG 已生成并完成验证。
- **1.8.1 · 发布打包**：`./build-app.sh` 和 `./build-dmg.sh --skip-build` 已完成。`dist/NotchIsland-1.8.1-arm64.dmg` 通过 `verify-release.py`、arm64、最低 macOS 15、签名、DMG CRC 校验、SHA-256 和挂载结构检查。SHA-256 为 `e55f6a788861fe960e1fa018d4bb540ed3d2e2d5ae2c98ae3f7bdb4d9716d791`。完整 Swift 测试 140 项通过，日志为 `/private/tmp/notchisland-181-tests.log`。
- **1.8.2 · 歌词显示重做（代码与定向验证完成）**：展开歌词改为上一句、正在唱、下一句、再下一句四行稳定角色，远行按距离降低透明度并增加模糊。收起态恢复真实上下滚动，正向和反向切换都从当前展示位置继续。逐字时间轴按字符拆分，当前字的高亮、横向羽化和上浮绑定同一个 cue，保留 RGB/封面流光、HDR 和暂停冻结。新增四行窗口、收起位移、逐字 cue、羽化和上浮回归测试，歌词、滚动、流光和渲染定向测试 45 项通过，其中 2 项 EDR/Metal 测试因当前环境跳过。完整测试已完成构建，但登录桌面服务环境中的 `InputSourceTests`、`ModuleClipboardTests` 失败并导致 xctest signal 5，未观察到歌词相关失败。隔离预览、1.8.2 DMG 和测试图待完成。
- **1.8.2 · 外框圆角修复（代码与定向验证完成）**：原生 `NSGlassEffectView` 在设置 `contentView` 后重新同步 `CALayer` 的 24 pt 连续圆角并启用裁剪，避免扩展玻璃 frame 盖住主体外框的圆角。新增玻璃圆角回归断言，修复前测试稳定失败，修复后目标测试通过。完整歌词、玻璃和动画回归及 1.8.2 DMG 仍待本阶段完成。
- **2026-11-23 · 新一轮歌词问题记录（仅更新交接，不改代码）**：当前 1.8.2 仍有歌词逐字显示兼容性问题。若当前歌词数据不提供可靠的逐字时间轴，必须自动回退到整句显示，禁止继续播放逐字高亮、逐字羽化和逐字上浮动画，避免动画与歌词数据不匹配。只有在歌词确实提供逐字时间轴时，才启用逐字动画；逐字高亮、羽化、上浮和 HDR 亮度层必须使用同一个逐字进度，HDR 增益要随着当前字的进度同步变化。用户明确要求本对话禁止操作代码，后续优化在新对话中继续。

- **2026-11-23 · 歌词逐字与 HDR 定向根因分析（仅分析，未改源码）**：定向审查 `Lyrics.swift`、`OnlineLyrics.swift`、`LyricsWrapping.swift`、`LyricHighlight.swift`、`LyricTextView.swift`、`LyricRollView.swift` 与 `IslandView.swift`，确认普通 LRC 没有 `segments` 时，`LyricHighlight.cues` 虽只返回一个整句 cue，但 `LyricTextView.rebuildIfNeeded` 仍为它创建高亮 tile 和 feather mask，`schedule` 仍附加 `highlight`、`highlightFeather`、`highlightLift`，所以当前只是时间粒度回退，未关闭逐字视觉动画；`OnlineLyrics.hasWordTiming` 只要任一行有 segments 就判定整份歌词支持逐字时间轴，混合或部分逐字数据没有按渲染行可靠降级。带 segments 的路径中，透明度、羽化位置和上浮都使用同一个 `cue.progress`，但 HDR 图像/流光梯度在重建时用固定 gain 生成，流光位置另用独立 `flowPosition` 时钟，尚未证明 HDR 增益随同一逐字进度同步变化。`LyricsWrapping` 还可能把一个 timed segment 切到多个显示行并复用同一时间范围，后续实现需按最终渲染行重新确认时间轴可靠性。
  - 现有定向验证：`swift test --disable-sandbox --filter 'LyricRenderingPolicyTests|LyricsTests|LyricCompositingTests/testActiveWordHighlightUsesFeatherMaskAndLiftAnimation'` 通过 26 项；`swift test --disable-sandbox --filter 'IslandAnimationTests|GlassBackdropTests'` 通过 15 项。当前测试未覆盖“无逐字数据不得创建 feather/lift/HDR tile”及“HDR 增益与 cue progress 同步”的负向断言。
  - 下一代码阶段应引入明确的逐字时间轴能力判定：无可靠时间轴时仅渲染整句并关闭逐字 tile、羽化、上浮和逐字 HDR；有可靠时间轴时由同一个 progress 驱动高亮、羽化、上浮和 HDR 增益，并补齐混合数据、换行切分、暂停/恢复和 HDR 进度同步回归测试。本阶段遵守“禁止改代码”，因此尚未实施这些改动。

- **2026-11-23 · 1.8.2 现有版本打包复核**：在未改源码的前提下重新执行 `./build-app.sh` 与 `./build-dmg.sh --skip-build`。`dist/NotchIsland.app` 通过版本 1.8.2、构建 24、arm64、最低 macOS 15.0、系统库与开发者 rpath 检查，临时签名验证通过；`dist/NotchIsland-1.8.2-arm64.dmg` 的 hdiutil CRC、签名与发布检查通过。SHA-256：`9f6437dadccec45ccc4b13bf7b3bb5b2b5f60923a3806d790fc948f03a957783`。该 DMG 反映当前源码的既有行为，未包含本阶段尚未实施的逐字兼容与 HDR 同步修复。

- **1.8.3 · 整句回退与展开歌词可读性**：逐行校验时间片的文本覆盖、先后顺序与时长。缺少可靠时间轴时走静态整句渲染，关闭逐字高亮、羽化、上浮、流光和逐字 HDR。可靠时间轴在布局换行后保留原有 cue，末尾只有起点的 LRC 片段整体呈现。逐字高亮、羽化、上浮和 HDR 叠加层使用相同进度，暂停时按同一个时间点更新。展开的非当前行去掉高斯模糊并提高不透明度，下方和侧边均按字号容纳四行。两项回归先复现后通过。隔离工作目录的定向测试执行 63 项，61 项通过，2 项依赖 EDR/Metal 的测试跳过。

- **1.8.3 · 窗口与安装包复核**：打包版快照复现了 1.8.2 的音乐面板越界。主窗口从 370 pt 增至 448 pt，顶部定位保持贴住屏幕边缘。最大字号下的侧边和下方布局测试确认四行以及整个面板均在窗口内。完整测试 148 项，147 项通过，1 项因缺少 EDR 设备而跳过，日志为 `/private/tmp/notchisland-183-final-tests.log`。最终安装包通过签名、挂载、Applications 拖拽入口、CRC、版本和启动检查，快照不再报告面板越界，仍复现 1.8.2 的省资源模式滚动诊断。安装包为 `dist/NotchIsland-1.8.3-arm64.dmg`，SHA-256 为 `63d61da8cd04b8f0731b5444568ac3c81686cbd547781d200676270be500e5e8`。

- **1.8.4 · 普通歌词 RGB 流光回归**：上一阶段把 usesFlow 绑定到可靠逐字时间轴，导致普通整句歌词只剩白色基础文字。现改为流光独立于逐字时间轴启用。普通歌词创建一个整句流光 tile，不创建 feather mask、逐字上浮或逐字 cue。新增回归测试。完整测试 149 项，148 项通过，1 项因缺少 EDR 设备而跳过。dist/NotchIsland-1.8.4-arm64.dmg 已通过签名、CRC、挂载入口和启动检查，SHA-256 为 f62d63aa814e8310361a1052a277688ca914a484cc018efe53110307701eb32a。快照保留旧版省资源模式滚动诊断。

## 待办（按优先级）

- **发布素材**：用户从宣传图和《XOXZ》实机截图中选图，自行上传到 GitHub Release。


- **P0 · 歌词流光用户复核**：用真实播放和不同封面检查收起歌词泛光、连贯切色及 HDR 观感。隔离预览可用 `r`、`a`、`s` 切换流光，`p` 暂停。
- **P0 · 歌词滚动与 HDR 用户复核**：用 Apple Music 的普通 LRC 和有效逐字歌词确认展开四行的可读性、换歌和跳转时的行切换，以及同一字上各效果的同步；实屏检查 HDR 亮度变化。

0. **P0 · 1.7.9 真机复核** — 在已授予辅助功能权限且启用媒体键接管的环境测试音量加减、静音和亮度键。确认自动调整不会弹出或移动提示，用鼠标和触控板分别测试自然滚动开关。用支持 HDR 的屏幕比较同一颜色在 SDR、50% 和 100% 的实屏亮度，记录系统提供的实际 HDR 余量。
1. **P0 · 1.7.8 用户复核** — 检查用户桌面背景上的标准、轻模糊、清透玻璃和设置明暗外观，播放状态下快速展开、收起及反向。从用户发现的问题和本机的同帧检查继续定位。
2. **P1 · 真实播放有无漏报** — 1.7.5 有播放后刘海不响应的反馈 → `MusicAppMonitor.swift:44`、`:80`、`:104`，`IslandController.swift:259`、`:294`，`Snapshot.swift` 的 `runPlaybackCheck` → 本机 macOS 27 日志显示 MediaRemote 读取曲目被拒绝，旧版等脚本查询且曾被持续隐藏状态阻挡 → 用户允许后，用正常安装的 app 分别实测 Music 和 Spotify 的播放、暂停、换歌与退出，再看「音乐与权限」及 `/tmp/notchisland.log`。合成事件已通过，脚本权限是否为用户当时的故障原因未确认。若还漏报，先查分发事件是否收到和选源结果，再检查自动化权限。未授权时首个事件可先显示歌名，精确进度、封面和控制仍依赖相应权限。
3. **P1 · HDR 和系统兼容** — 之前开启 HDR 仍看不出亮度差 → `LyricTextView.swift:106`、`:157`、`:265`，`IslandView.swift` 的 `buildMusic`，`Tests/NotchIslandTests/LyricCompositingTests.swift:33` → 旧 `.ifSupported` 会把测试渲染压到 1.0，父级遮罩不一定压低亮度，已用带/不带遮罩的离屏对照排除“遮罩必然夹回 SDR” → 在 HDR 内屏与普通外接屏上用同一段白色歌词切换 HDR 和强度，记录显示器余量，同时在 macOS 15/26 运行 DMG 内程序的 `--startup-check` 并启动正常界面。当前浮点测试没有测量屏幕亮度。若只在真机失效，查显示器余量和透明窗口合成，不要调高像素来掩盖问题。
4. **P2 · 系统功能的旧反馈复核** — 通知未接管、AirPods 不弹电量、专注或输入法未识别都曾有反馈 → `NotificationBridge.swift:50`、`:118`，`IslandController.swift:315`、`:326`，`AirPodsMonitor.swift:256`、`:349`，`SystemFocusMonitor.swift:154`、`:183`，`InputSourceMonitor.swift:32` → 可能分别卡在辅助功能授权或通知结构、音频路由或电量补读、控制中心状态/输入法事件，当前版未有用户验收 → 若重新收到报告，先跑已授权应用的 `--diagnose-notifications`，AirPods 单独验证“仅开盒、实际切到耳机输出、静置”三种情况，其余分别切一次「减少打扰」和输入法。先记录系统事件是否到达，再改对应 monitor，避免把后台刷新当作连接事件。

## 关键约束（踩过的坑）

- 用户明确要求：收起时连播放两翼都纯黑，刘海贴住屏幕顶边。展开默认从上黑渐变到底部透明，材质观感对齐 Apple 原生液态玻璃，清透档也要保留原生玻璃。动画连续、快速反向从当前状态继续。闲置开销低，设置按模块独立，可关的模块不占展开面板。
- 用户明确拒绝：双指捏合和因此触发的持续隐藏、灰色紧凑玻璃、手选播放器、要求手工下载歌词、AirPods 静置时反复弹电量。保留普通滚动手势、自动识别播放来源与在线歌词。AirPods 自动提示以实际音频输出为现有触发依据，不能宣称检测到佩戴。
- 歌词必须自动换行并保留原时间；真逐字数据做逐字渐亮，普通 LRC 整句亮，省资源模式只滚动、关闭 HDR 增强。HDR 开关和光晕独立，尊重减少透明度、减少动态效果与多屏能力。测试过的离屏浮点值与实屏亮度分开记录。
- **macOS 15**：最低部署目标。HDR 图像的 `CGImage(headroom:…)` 从 15 可用，图层用 `wantsExtendedDynamicRangeContent`（14 起可用，26 弃用）。无原生玻璃入口，使用纯黑外观。**macOS 26**：`NSGlassEffectView` 的 `.regular`、`.clear` 和 `CALayer.preferredDynamicRange` 可用，玻璃类必须弱链接。清透档需保留系统 `.clear`，避免自绘不透明层盖住材质。**macOS 27**：`effectIsInteractive` 从 27 可用，当前没有调用；旧 MediaRemote 是私有兼容路径，27 上可能因权限拿不到数据，优先排查 Music/Spotify 事件与 AppleScript 路径。
- 从仓库根目录执行 `swift test --disable-sandbox`，最新记录是 **140 项、0 失败**（本机 macOS 27.3 / Xcode 27.2，日志 `/private/tmp/notchisland-181-tests.log`）。剪贴板和输入法测试需要登录桌面会话与对应系统服务，先区分环境失败。旧快照曾在主队列嵌套等待淡出，阻塞实际清理，已改成异步续跑。
- 构建执行 `./build-app.sh`，用 `open -n -W dist/NotchIsland.app --args --snapshot --snapshot-output /private/tmp/notchisland-qa` 检查 `verification.txt`。安装包执行 `./build-dmg.sh --skip-build`，复核版本、签名、SHA-256 和 /Applications 拖拽入口。安装包为本地临时签名，未公证。未经用户要求，不提交或推送 GitHub、不发布 Release、不替换已安装应用。项目按 GPL-3.0 分发，保留 Lau Kachun 版权。

## 下一步第一件事

用同一台机器播放一首普通 LRC 歌曲和一首带逐字时间轴的歌曲，展开时核对四行能否读清，再暂停、恢复和反向跳转，确认逐字效果和 HDR 同步。
