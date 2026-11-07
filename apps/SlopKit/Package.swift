// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlopKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlopKit", targets: ["SlopKit"]),
    ],
    dependencies: [
        // Global hotkeys + recorder. Approved in docs/design-system.md; pin exact versions.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0"),
    ],
    targets: [
        .target(
            name: "SlopKit",
            dependencies: ["SlopKitLaunch", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")]
        ),
        // Launch-time hooks that must work whatever an app's delegate is (SLOP_APPEARANCE).
        .target(name: "SlopKitLaunch"),
        // Every component on one screen: swift run --package-path apps/SlopKit SlopKitGallery
        .executableTarget(name: "SlopKitGallery", dependencies: ["SlopKit"]),
        .testTarget(name: "SlopKitTests", dependencies: ["SlopKit"]),
    ],
    swiftLanguageModes: [.v6]
)
