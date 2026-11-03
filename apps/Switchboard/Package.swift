// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "SwitchboardCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Switchboard",
            dependencies: ["SwitchboardCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"]),
    ],
    swiftLanguageModes: [.v6]
)
