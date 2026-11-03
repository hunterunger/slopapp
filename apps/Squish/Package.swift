// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Squish",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic: image and PDF compression, output naming, settings. No SwiftUI.
        .target(name: "SquishCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Squish",
            dependencies: ["SquishCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        // Headless benchmark: runs the real queue + compressor over a folder.
        //   swift run -c release --package-path apps/Squish SquishBench /tmp/squish-test/batch
        .executableTarget(
            name: "SquishBench",
            dependencies: ["SquishCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "SquishCoreTests", dependencies: ["SquishCore"]),
    ],
    swiftLanguageModes: [.v6]
)
