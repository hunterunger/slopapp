// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tally",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "TallyCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Tally",
            dependencies: ["TallyCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "TallyCoreTests", dependencies: ["TallyCore"]),
        // Editor and model behavior that needs AppKit (undo, wrapping, autosave).
        .testTarget(name: "TallyAppTests", dependencies: ["Tally", "TallyCore"]),
    ],
    swiftLanguageModes: [.v6]
)
