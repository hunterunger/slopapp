// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ruler",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "RulerCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Ruler",
            dependencies: ["RulerCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "RulerCoreTests", dependencies: ["RulerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
