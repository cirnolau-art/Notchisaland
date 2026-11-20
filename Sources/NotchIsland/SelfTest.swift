import AppKit

/// 运行时自检：验证各系统能力可用性
enum SelfTest {
    private static func wait(_ semaphore: DispatchSemaphore, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if semaphore.wait(timeout: .now()) == .success { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }
    static func run() {
        print("== NotchIsland 自检 ==")

        // 音量
        let vol = VolumeMonitor()
        vol.start()
        _ = wait(DispatchSemaphore(value: 0), seconds: 0.5)
        if let value = vol.currentVolume() { print("[音量] ✅ 当前 \(Int(value * 100))%，可调整=\(vol.canAdjust)") }
        else { print("[音量] ❌ 无法读取输出设备") }

        // 亮度
        let bri = BrightnessMonitor()
        let briSem = DispatchSemaphore(value: 0)
        var briResult = "未触发"
        bri.onBrightnessChange = { v in
            briResult = "亮度 \(Int(v * 100))%"
            briSem.signal()
        }
        bri.start()
        _ = wait(briSem, seconds: 1)
        if let v = bri.read() {
            print("[亮度] ✅ 当前 \(Int(v * 100))%（变化会触发显示: \(briResult == "未触发" ? "未变化" : briResult)）")
        } else {
            print("[亮度] ❌ 读取失败")
        }

        // 输入法
        if let (name, id) = InputSourceMonitor.currentKeyboardSource() {
            print("[输入法] ✅ \(name) (\(id))")
        } else {
            print("[输入法] ❌ 无法读取当前输入源")
        }

        // 电池
        let bat = BatteryMonitor()
        let batSem = DispatchSemaphore(value: 0)
        var batResult = "未触发"
        bat.onPowerChange = { charging, pct in
            batResult = "充电=\(charging), 电量 \(pct)%"
            batSem.signal()
        }
        bat.start()
        _ = wait(batSem, seconds: 1)
        print("[电池] \(batResult)")

        // 音乐（异步，等 2 秒）
        let music = NowPlayingMonitor()
        let musicSem = DispatchSemaphore(value: 0)
        var musicResult = "当前无播放"
        music.onStateChange = { info in
            if let info {
                musicResult = "✅ 正在播放: \(info.title) - \(info.artist) [\(info.isPlaying)] artwork=\(info.artwork != nil)"
            } else {
                musicResult = "无播放（正常，若无媒体在播）"
            }
            musicSem.signal()
        }
        music.start()
        _ = wait(musicSem, seconds: 3)
        print("[音乐] \(musicResult)")

        // 媒体键接管
        let trusted = MediaKeyInterceptor.isTrusted
        print("[媒体键] 辅助功能授权=\(trusted ? "✅ 已授权" : "❌ 未授权（系统原生 HUD 仍会弹出）")")


        print("== 自检完成 ==")
    }
}
