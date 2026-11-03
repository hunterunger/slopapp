// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Specimen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic: the font index, classification, filtering, favourites and activation
        // planning. No SwiftUI. CoreText calls go through `FontSystem` so tests can fake them.
        .target(name: "SpecimenCore"),
        // The app: SwiftUI + an AppKit collection view for the font grid.
        .executableTarget(
            name: "Specimen",
            dependencies: ["SpecimenCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        // Test-font helper for walkthroughs and blind tests (registers the OFL fixture at
        // session scope from /tmp/specimen-test, and cleans it up again):
        //   swift run --package-path apps/Specimen specimen-fixture install
        .executableTarget(name: "specimen-fixture", dependencies: ["SpecimenCore"], path: "Sources/SpecimenFixture"),
        .testTarget(name: "SpecimenCoreTests", dependencies: ["SpecimenCore"], exclude: []),
    ],
    swiftLanguageModes: [.v6]
)
