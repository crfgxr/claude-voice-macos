// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeVoice",
            path: "Sources/ClaudeVoice"
        )
    ]
)
