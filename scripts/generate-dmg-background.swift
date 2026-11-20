import AppKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift generate-dmg-background.swift OUTPUT VERSION")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let version = CommandLine.arguments[2]
let size = NSSize(width: 660, height: 430)
let scale = 2
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                              pixelsHigh: Int(size.height) * scale, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let bounds = NSRect(origin: .zero, size: size)
NSGradient(starting: NSColor(calibratedRed: 0.98, green: 0.985, blue: 1, alpha: 1),
           ending: NSColor(calibratedRed: 0.93, green: 0.945, blue: 0.965, alpha: 1))!
    .draw(in: bounds, angle: -90)

func text(_ string: String, top: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color,
                                                    .paragraphStyle: paragraph])
        .draw(in: NSRect(x: 35, y: size.height - top - height, width: size.width - 70, height: height))
}

text("灵动岛", top: 42, height: 42, font: .systemFont(ofSize: 30, weight: .semibold),
     color: NSColor(calibratedWhite: 0.13, alpha: 1))
text("NotchIsland  ·  \(version)", top: 89, height: 24, font: .systemFont(ofSize: 13),
     color: NSColor(calibratedWhite: 0.46, alpha: 1))

// Finder draws the actual app and Applications folder at the two ends of this arrow.
let arrow = NSBezierPath()
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
let arrowY = size.height - 207
arrow.move(to: NSPoint(x: 307, y: arrowY))
arrow.line(to: NSPoint(x: 353, y: arrowY))
arrow.move(to: NSPoint(x: 343, y: arrowY + 10))
arrow.line(to: NSPoint(x: 353, y: arrowY))
arrow.line(to: NSPoint(x: 343, y: arrowY - 10))
NSColor(calibratedWhite: 0.57, alpha: 1).setStroke()
arrow.stroke()

text("拖入「应用程序」，即可安装", top: 337, height: 24,
     font: .systemFont(ofSize: 14, weight: .medium), color: NSColor(calibratedWhite: 0.28, alpha: 1))
text("macOS 15 或更新版本", top: 371, height: 20,
     font: .systemFont(ofSize: 11), color: NSColor(calibratedWhite: 0.52, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
