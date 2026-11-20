import AppKit

// Use Finder's custom-icon API for an existing signed installation.
// The next full build embeds the same artwork using CFBundleIconFile.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, let image = NSImage(contentsOfFile: arguments[0]) else {
    fputs("Usage: swift scripts/apply-installed-icon.swift <icon.icns> <application.app> [...]\n", stderr)
    exit(1)
}
for application in arguments.dropFirst() {
    guard FileManager.default.fileExists(atPath: application), application.hasSuffix(".app") else {
        fputs("Application not found: \(application)\n", stderr)
        exit(1)
    }
    guard NSWorkspace.shared.setIcon(image, forFile: application, options: []) else {
        fputs("Unable to update icon: \(application)\n", stderr)
        exit(1)
    }
    print("Updated icon: \(application)")
}
