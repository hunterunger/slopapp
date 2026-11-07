// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slopapp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "SlopappCore"),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Slopapp",
            dependencies: ["SlopappCore", .product(name: "SlopKit", package: "SlopKit")],
            // The featured banners' botanical prints (the website's, web/public/prints/).
            resources: [.copy("Resources/Prints")]
        ),
        .testTarget(name: "SlopappCoreTests", dependencies: ["SlopappCore"]),
    ],
    swiftLanguageModes: [.v6]
)
