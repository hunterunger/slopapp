// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "FocusCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Focus",
            dependencies: ["FocusCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"]),
    ],
    swiftLanguageModes: [.v6]
)
