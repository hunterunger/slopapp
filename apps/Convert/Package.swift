// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Convert",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic: planning, AVFoundation/ImageIO conversion, output naming. No SwiftUI.
        .target(name: "ConvertCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Convert",
            dependencies: ["ConvertCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        // Synthetic test media (moving test pattern + tones, images), used by the tests and by
        //   swift run --package-path apps/Convert ConvertFixturesTool /tmp/convert-test/fixtures
        .target(name: "ConvertFixtures"),
        .executableTarget(name: "ConvertFixturesTool", dependencies: ["ConvertFixtures"]),
        .testTarget(name: "ConvertCoreTests", dependencies: ["ConvertCore", "ConvertFixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
