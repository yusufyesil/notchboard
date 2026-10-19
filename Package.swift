// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Notchboard",
            path: "Sources/Notchboard",
            resources: [.process("Resources")]
        )
    ]
)
