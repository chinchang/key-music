// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyMusic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyMusic",
            path: "Sources/KeyMusic"
        )
    ]
)
