// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "brew-swift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "brew-swift",
            path: "Sources"
        ),
    ]
)
