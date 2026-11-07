// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Crate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SlopKit"),
    ],
    targets: [
        // The system libarchive, through a small header of our own (see crate_archive.h).
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        // The system liblzma, for 7z headers (see crate_lzma.h).
        .systemLibrary(name: "CLZMA", path: "Sources/CLZMA"),
        // Pure logic: reading, extracting and creating archives. No SwiftUI.
        .target(name: "CrateCore", dependencies: ["CArchive", "CLZMA"]),
        // The app: SwiftUI views and wiring.
        .executableTarget(
            name: "Crate",
            dependencies: ["CrateCore", .product(name: "SlopKit", package: "SlopKit")]
        ),
        .testTarget(
            name: "CrateCoreTests",
            dependencies: ["CrateCore", "CArchive"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
