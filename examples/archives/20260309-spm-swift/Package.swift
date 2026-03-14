// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spm-swift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "spm-swift",
            path: "Sources"
        ),
    ]
)
