import AppKit
import QuartzCore

private final class EarbudIllustration: FlippedView {
    private let check = NSImageView(frame: NSRect(x: 63, y: 50, width: 18, height: 18))
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        for (index, symbol) in ["airpodpro.left", "airpodpro.right"].enumerated() {
            let icon = NSImageView(frame: NSRect(x: 10 + index * 33, y: 3, width: 34, height: 55))
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "airpodspro", accessibilityDescription: nil)
            icon.contentTintColor = .white; icon.imageScaling = .scaleProportionallyUpOrDown; icon.wantsLayer = true
            addSubview(icon)
            if !IslandPreferences.shared.reduceMotion {
                let rise = CASpringAnimation(keyPath: "transform.translation.y")
                rise.fromValue = 17; rise.toValue = 0; rise.mass = 0.8; rise.stiffness = 180; rise.damping = 18; rise.duration = 0.85
                rise.beginTime = CACurrentMediaTime() + Double(index) * 0.055
                icon.layer?.add(rise, forKey: "connect-rise")
                let spread = CASpringAnimation(keyPath: "transform.translation.x")
                spread.fromValue = index == 0 ? 10 : -10; spread.toValue = 0; spread.stiffness = 180; spread.damping = 18; spread.duration = 0.85
                icon.layer?.add(spread, forKey: "connect-spread")
                let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.3
                icon.layer?.add(fade, forKey: "connect-fade")
            }
        }
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil); check.contentTintColor = .systemGreen; addSubview(check)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setConnected(_ connected: Bool) {
        check.isHidden = !connected
        for icon in subviews where icon !== check {
            icon.alphaValue = connected ? 1 : 0.5
            if !connected { icon.layer?.removeAllAnimations() }
        }
    }
}

final class AirPodsConnectionView: FlippedView {
    private let illustration = EarbudIllustration(frame: NSRect(x: 23, y: 16, width: 88, height: 78))
    private let name = NSTextField(labelWithString: "")
    private let connection = NSTextField(labelWithString: "")
    private let footnote = NSTextField(labelWithString: "系统最近报告 · 盒盖关闭时电量可能暂不更新")
    private var values: [NSTextField] = []
    private var fills: [CALayer] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(illustration)
        name.frame = NSRect(x: 125, y: 24, width: frame.width - 157, height: 25); name.font = .systemFont(ofSize: 17, weight: .semibold); name.textColor = .white; name.lineBreakMode = .byTruncatingTail
        connection.frame = NSRect(x: 125, y: 56, width: frame.width - 157, height: 20); connection.font = .systemFont(ofSize: 12); connection.textColor = .white.withAlphaComponent(0.55)
        addSubview(name); addSubview(connection)
        let cellWidth = (frame.width - 48) / 3
        for (index, title) in ["左耳", "右耳", "充电盒"].enumerated() {
            let x = 24 + CGFloat(index) * cellWidth
            let caption = NSTextField(labelWithString: title); caption.frame = NSRect(x: x, y: 107, width: cellWidth - 12, height: 18); caption.font = .systemFont(ofSize: 11); caption.textColor = .white.withAlphaComponent(0.55); addSubview(caption)
            let value = NSTextField(labelWithString: "—"); value.frame = NSRect(x: x, y: 130, width: cellWidth - 12, height: 29); value.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium); value.textColor = .white; addSubview(value); values.append(value)
            let track = NSView(frame: NSRect(x: x + 2, y: 169, width: cellWidth - 20, height: 3)); track.wantsLayer = true
            track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor; track.layer?.cornerRadius = 1.5
            let fill = CALayer(); fill.cornerRadius = 1.5; track.layer?.addSublayer(fill); fills.append(fill); addSubview(track)
        }
        footnote.frame = NSRect(x: 24, y: 193, width: frame.width - 48, height: 16); footnote.font = .systemFont(ofSize: 10); footnote.textColor = .white.withAlphaComponent(0.35); addSubview(footnote)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ snapshot: AirPodsSnapshot) {
        name.stringValue = snapshot.name
        illustration.setConnected(snapshot.connected)
        connection.stringValue = snapshot.connected ? "已连接，可开始聆听" : "未连接 · 上次报告的电量"
        footnote.stringValue = snapshot.connected && !snapshot.cachedFields.isEmpty ? "浅色电量为上次报告 · 盒盖关闭时可能暂不更新" : "系统最近报告 · 盒盖关闭时电量可能暂不更新"
        for (index, percentage) in [snapshot.left, snapshot.right, snapshot.caseBattery].enumerated() {
            let cached = !snapshot.connected || snapshot.cachedFields.contains(["left", "right", "case"][index])
            values[index].textColor = .white.withAlphaComponent(cached ? 0.48 : 1)
            values[index].stringValue = percentage.map { "\($0)%" } ?? "—"
            values[index].setAccessibilityLabel(["左耳", "右耳", "充电盒"][index] + (percentage.map { "\(cached ? "缓存" : "")电量 \($0)%" } ?? "电量暂不可用"))
            let width = (bounds.width - 48) / 3 - 20
            CATransaction.begin(); CATransaction.setDisableActions(true)
            fills[index].frame = CGRect(x: 0, y: 0, width: width * CGFloat(percentage ?? 0) / 100, height: 3)
            fills[index].backgroundColor = (percentage.map { $0 <= 20 ? NSColor.systemOrange : NSColor.white } ?? NSColor.clear).cgColor
            CATransaction.commit()
        }
    }
}
