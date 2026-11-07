// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dictate",
    // On-device AI cleanup (FoundationModels) and the speech engines need macOS 26.4.
    platforms: [.macOS("26.4")],
    dependencies: [
        .package(path: "../SlopKit"),
        // Speech engines. Pinned exactly and listed in docs/design-system.md §9.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "0.18.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.14.8"),
    ],
    targets: [
        // Pure logic: settings, cleanup rules, the dictation pipeline, hotkey state, history,
        // migration, audio features. No SwiftUI. System calls go through protocols so tests
        // can fake them.
        .target(name: "DictateCore"),
        // The app: SwiftUI views, AppKit glue and the real engines/recorder/inserter.
        .executableTarget(
            name: "Dictate",
            dependencies: [
                "DictateCore",
                .product(name: "SlopKit", package: "SlopKit"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"]),
    ],
    swiftLanguageModes: [.v6]
)
