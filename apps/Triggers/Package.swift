// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Triggers",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // The private MultitouchSupport contact struct, declared in C so the compiler checks its
        // layout. Nothing is linked: the framework is loaded at runtime (TouchSource.swift).
        .target(name: "TriggersTouchShim"),
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "TriggersCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Triggers",
            dependencies: ["TriggersCore", "TriggersTouchShim", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "TriggersCoreTests", dependencies: ["TriggersCore"]),
    ],
    swiftLanguageModes: [.v6]
)
