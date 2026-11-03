// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tidy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic: finding apps, leftovers, junk and large files; the trash policy.
        // No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "TidyCore"),
        // A realistic fake Mac (apps, leftovers, decoys, junk, large files) for tests and walkthroughs.
        .target(name: "TidyFixtures", dependencies: ["TidyCore"]),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Tidy",
            dependencies: ["TidyCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        // Command line helper: build fixtures, and a read-only benchmark that prints only counts and timings.
        //   swift run --package-path apps/Tidy tidy-tool fixtures /tmp/tidy-test
        .executableTarget(name: "tidy-tool", dependencies: ["TidyCore", "TidyFixtures"], path: "Sources/TidyTool"),
        .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore", "TidyFixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
