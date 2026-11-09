// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicroPad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MicroPad", path: "Sources/MicroPad")
    ]
)
