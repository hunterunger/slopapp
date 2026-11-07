// swift-tools-version: 6.0
// Shots: the store screenshot pipeline's Swift half (docs/screenshots.md). scripts/shots.sh
// builds it and calls it to read showcase.json, show the capture backdrop, and compose the
// final images. Not shipped in any app.
import PackageDescription

let package = Package(
    name: "Shots",
    platforms: [.macOS(.v14)],
    targets: [
        // Showcase files, palette, layout and drawing. No AppKit windows; tested.
        .target(name: "ShotsCore"),
        .executableTarget(name: "shots", dependencies: ["ShotsCore"]),
        .testTarget(name: "ShotsCoreTests", dependencies: ["ShotsCore"]),
    ],
    swiftLanguageModes: [.v6]
)
