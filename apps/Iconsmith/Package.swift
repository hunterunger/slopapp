// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Iconsmith",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "IconsmithCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Iconsmith",
            dependencies: ["IconsmithCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "IconsmithCoreTests", dependencies: ["IconsmithCore"]),
    ],
    swiftLanguageModes: [.v6]
)
