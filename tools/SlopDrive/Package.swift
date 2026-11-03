// swift-tools-version: 6.0
// SlopDrive: drive any running Mac app through Accessibility, for agents.
// Use it through scripts/drive, which builds this once and forwards arguments.
import PackageDescription

let package = Package(
    name: "SlopDrive",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SlopDrive", path: "Sources/SlopDrive")
    ]
)
