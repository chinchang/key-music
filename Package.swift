// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibeType",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibeType",
            path: "Sources/VibeType"
        )
    ]
)
