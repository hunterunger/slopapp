// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // Pure logic. No SwiftUI. System calls go through protocols so tests can fake them.
        .target(name: "PaperCore"),
        // Generated test PDFs, shared by the tests and the paper-fixtures tool. Not in the app.
        .target(name: "PaperFixtures", dependencies: ["PaperCore"]),
        .executableTarget(name: "paper-fixtures", dependencies: ["PaperFixtures"]),
        // The app: AppKit document architecture (NSDocument + PDFView) with SwiftUI panels.
        .executableTarget(
            name: "Paper",
            dependencies: ["PaperCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore", "PaperFixtures"]),
    ],
    swiftLanguageModes: [.v6]
)
