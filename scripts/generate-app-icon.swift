import AppKit

// Reproducible vector drawing; no external artwork or runtime rendering is needed.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = project.appendingPathComponent("Resources", isDirectory: true)
let output = project.appendingPathComponent("artifacts/app-icon", isDirectory: true)
let iconset = output.appendingPathComponent("NotchIsland.iconset", isDirectory: true)
let files = FileManager.default
try files.createDirectory(at: resources, withIntermediateDirectories: true)
try files.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawIcon(pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0.10, 0.11, 0.13).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [color(0.10, 0.11, 0.14), color(0.23, 0.25, 0.29)])!
        .draw(in: NSRect(x: 100, y: 100, width: 824, height: 824), angle: 90)

    func glow(center: CGPoint, radius: CGFloat, tint: NSColor) {
        let colors = [tint.cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
    }
    glow(center: CGPoint(x: 355, y: 452), radius: 320, tint: color(0.10, 0.80, 0.93, 0.30))
    glow(center: CGPoint(x: 680, y: 465), radius: 300, tint: color(0.42, 0.34, 0.96, 0.32))
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(roundedRect: NSRect(x: 102, y: 102, width: 820, height: 820), xRadius: 182, yRadius: 182)
    rim.lineWidth = 2
    NSColor.white.withAlphaComponent(0.12).setStroke()
    rim.stroke()

    // The floating pill is the single central mark, with a connection light and a quiet waveform.
    let pillRect = NSRect(x: 203, y: 440, width: 618, height: 174)
    let pill = NSBezierPath(roundedRect: pillRect, xRadius: 87, yRadius: 87)
    NSGraphicsContext.saveGraphicsState()
    let pillShadow = NSShadow()
    pillShadow.shadowColor = NSColor.black.withAlphaComponent(0.68)
    pillShadow.shadowBlurRadius = 36
    pillShadow.shadowOffset = NSSize(width: 0, height: -20)
    pillShadow.set()
    NSColor.black.setFill()
    pill.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0.015, 0.018, 0.025), color(0.065, 0.075, 0.09)])!
        .draw(in: pill, angle: 90)
    pill.lineWidth = 2
    NSColor.white.withAlphaComponent(0.18).setStroke()
    pill.stroke()

    NSGraphicsContext.saveGraphicsState()
    let dotShadow = NSShadow()
    dotShadow.shadowColor = color(0.25, 0.93, 0.88, 0.45)
    dotShadow.shadowBlurRadius = 18
    dotShadow.shadowOffset = .zero
    dotShadow.set()
    color(0.47, 0.97, 0.90).setFill()
    NSBezierPath(ovalIn: NSRect(x: 266, y: 501, width: 52, height: 52)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let heights: [CGFloat] = [26, 58, 88, 50, 26]
    for (index, height) in heights.enumerated() {
        NSColor.white.withAlphaComponent(index == 2 ? 1 : 0.91).setFill()
        let bar = NSRect(x: 558 + CGFloat(index) * 35, y: 527 - height / 2, width: 17, height: height)
        NSBezierPath(roundedRect: bar, xRadius: 8.5, yRadius: 8.5).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let representations: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, pixels) in representations {
    try drawIcon(pixels: pixels).write(to: iconset.appendingPathComponent(name + ".png"))
}
try drawIcon(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
try drawIcon(pixels: 256).write(to: output.appendingPathComponent("preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated Resources/AppIcon.icns and AppIcon.png")
