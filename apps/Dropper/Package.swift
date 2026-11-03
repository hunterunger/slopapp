// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dropper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "DropperCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Dropper",
            dependencies: ["DropperCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "DropperCoreTests", dependencies: ["DropperCore"]),
    ],
    swiftLanguageModes: [.v6]
)
