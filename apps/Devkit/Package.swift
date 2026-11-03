// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Devkit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "DevkitCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Devkit",
            dependencies: ["DevkitCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "DevkitCoreTests", dependencies: ["DevkitCore"]),
    ],
    swiftLanguageModes: [.v6]
)
