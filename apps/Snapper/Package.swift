// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snapper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        // Uses SlopKit's capture geometry (SelectionGeometry, ScreenCoordinates).
        .target(name: "SnapperCore", dependencies: [.product(name: "SlopKit", package: "SlopKit")]),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Snapper",
            dependencies: ["SnapperCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "SnapperCoreTests", dependencies: ["SnapperCore"]),
    ],
    swiftLanguageModes: [.v6]
)
