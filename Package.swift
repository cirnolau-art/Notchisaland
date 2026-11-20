// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland"
        ),
        .testTarget(name: "NotchIslandTests", dependencies: ["NotchIsland"])
    ]
)
