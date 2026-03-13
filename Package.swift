// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeHandsFree",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeHandsFree",
            path: "Sources/ClaudeHandsFree"
        )
    ]
)
