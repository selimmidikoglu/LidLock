// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LidLock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LidLock",
            path: "Sources/LidLock",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
