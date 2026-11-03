// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zones",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        // The city list is GeoNames data (CC BY 4.0), built by Tools/build-cities.py.
        .target(
            name: "ZonesCore",
            resources: [.copy("Resources/cities.tsv.deflate")]
        ),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Zones",
            dependencies: ["ZonesCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"]),
    ],
    swiftLanguageModes: [.v6]
)
