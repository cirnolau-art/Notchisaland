import AppKit
import Darwin

let diagnosticArguments: Set<String> = ["--startup-check", "--version", "--selftest", "--selftest2",
                                       "--diagnose-notifications", "--diagnose-audio", "--snapshot"]
let isDiagnostic = !diagnosticArguments.isDisjoint(with: CommandLine.arguments)

// Keep terminal diagnostics visible. Duplicate one descriptor so stdout and stderr
// share a file offset instead of truncating and overwriting each other's output.
if Bundle.main.bundleIdentifier != nil && !isDiagnostic && isatty(STDOUT_FILENO) == 0 {
    let descriptor = open("/tmp/notchisland.log", O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW,
                          S_IRUSR | S_IWUSR)
    if descriptor >= 0 {
        _ = dup2(descriptor, STDOUT_FILENO)
        _ = dup2(descriptor, STDERR_FILENO)
        close(descriptor)
    }
}

// Use libc's original streams, avoiding an unnecessary Swift stdio overlay import.
setvbuf(__stdoutp, nil, _IONBF, 0)
setvbuf(__stderrp, nil, _IONBF, 0)

if CommandLine.arguments.contains("--version") {
    print("NotchIsland \(AppVersion.display)")
    exit(0)
}

if CommandLine.arguments.contains("--startup-check") {
    print("NotchIsland \(AppVersion.display)")
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("最低系统版本：\(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "15.0")")
    print("原生液态玻璃：\(IslandPreferences.supportsGlass ? "可用" : "隐藏入口，使用纯黑外观")")
    print("PASS: executable and required libraries loaded; system monitors were not started.")
    exit(0)
}

if CommandLine.arguments.contains("--diagnose-notifications") { IslandDiagnostics.notifications() }
if CommandLine.arguments.contains("--diagnose-audio") { IslandDiagnostics.audio() }

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

if SnapshotMode.enabled {
    // 快照模式：由 AppDelegate 调度（需要 AppKit runloop）
}

if CommandLine.arguments.contains("--selftest2") {
    SelfTest.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
