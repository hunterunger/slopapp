// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gauge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "GaugeCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Gauge",
            dependencies: ["GaugeCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "GaugeCoreTests", dependencies: ["GaugeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
