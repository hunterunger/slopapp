import Foundation
import ImageIO
import Testing
@testable import IconsmithCore

@Suite struct ExportTests {
    let exporter = IconExporter(renderer: IconRenderer(source: rasterSource(transparentEdges: true)))

    @Test func iconsetHasTenCorrectlySizedPNGs() throws {
        let plan = try exporter.plan(.iconset, style: IconStyle(), options: ExportOptions())
        #expect(plan.files.count == 10)
        let byName = Dictionary(uniqueKeysWithValues: plan.files.map { ($0.path, $0.data) })
        #expect(imageSize(byName["icon_16x16.png"]!)! == (16, 16))
        #expect(imageSize(byName["icon_16x16@2x.png"]!)! == (32, 32))
        #expect(imageSize(byName["icon_512x512@2x.png"]!)! == (1024, 1024))
    }

    @Test func icnsIsWrittenAndReadable() throws {
        let dir = try makeTestFolder()
        let plan = try exporter.plan(.icns, style: IconStyle(), options: ExportOptions())
        let url = try ExportWriter(trash: FolderTrash(folder: dir.appending(path: "trash")))
            .write(plan, format: .icns, to: dir.appending(path: "logo.icns"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) >= 10)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers == ["logo.icns"]) // staging cleaned up
    }

    @Test func xcodeAppIconUsesCurrentLayout() throws {
        let plan = try exporter.plan(.xcode, style: IconStyle(background: .none), options: ExportOptions(xcodePlatforms: [.macOS, .iOS, .watchOS]))
        let contentsData = try #require(plan.files.first { $0.path == "Contents.json" }?.data)
        let json = try #require(try JSONSerialization.jsonObject(with: contentsData) as? [String: Any])
        let images = try #require(json["images"] as? [[String: String]])
        #expect(images.count == 12)
        let ios = try #require(images.first { $0["platform"] == "ios" })
        #expect(ios["idiom"] == "universal" && ios["size"] == "1024x1024")
        #expect(images.contains { $0["platform"] == "watchos" })
        #expect(images.filter { $0["idiom"] == "mac" }.count == 10)
        // Every referenced file is in the plan.
        let paths = Set(plan.files.map(\.path))
        for image in images { #expect(paths.contains(image["filename"]!)) }
        // iOS is opaque with no alpha channel, and the user is told why.
        let iosPNG = try #require(plan.files.first { $0.path == ios["filename"] }?.data)
        #expect(!hasAlphaChannel(iosPNG))
        #expect(plan.notes.count == 1)
        let info = try #require(json["info"] as? [String: Any])
        #expect(info["author"] as? String == "xcode")
    }

    @Test func xcodeMacOnlyHasNoNotes() throws {
        let plan = try exporter.plan(.xcode, style: IconStyle(), options: ExportOptions(xcodePlatforms: [.macOS]))
        #expect(plan.notes.isEmpty)
        #expect(plan.files.count == 11)
        #expect(throws: ExportError.noPlatforms) { try exporter.plan(.xcode, style: IconStyle(), options: ExportOptions(xcodePlatforms: [])) }
    }

    @Test func faviconSet() throws {
        let plan = try exporter.plan(.favicons, style: IconStyle(), options: ExportOptions())
        let names = Set(plan.files.map(\.path))
        #expect(names == ["favicon.ico", "icon-192.png", "icon-512.png", "apple-touch-icon.png", "icon-maskable-512.png", "manifest.webmanifest", "head.html"])
        let touch = try #require(plan.files.first { $0.path == "apple-touch-icon.png" }?.data)
        #expect(imageSize(touch)! == (180, 180))
        #expect(!hasAlphaChannel(touch))
        let ico = try #require(plan.files.first { $0.path == "favicon.ico" }?.data)
        #expect(ico[4] == 3) // three images
        let manifest = try #require(plan.files.first { $0.path == "manifest.webmanifest" }?.data)
        let text = String(decoding: manifest, as: UTF8.self)
        #expect(text.contains("maskable"))
        #expect(!text.contains("\\/"))   // no escaped slashes
        let json = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        #expect(json["name"] as? String == "test")
        #expect(json["short_name"] as? String == "test")
        #expect(json["display"] as? String == "standalone")
        #expect(json["theme_color"] as? String == "#FFFFFF")
        #expect(json["background_color"] as? String == "#FFFFFF")
    }

    @Test func pngExportUsesChosenSize() throws {
        let plan = try exporter.plan(.png, style: IconStyle(), options: ExportOptions(pngSize: 512))
        #expect(imageSize(plan.files[0].data)! == (512, 512))
    }

    @Test func icoEncoderHeaderAndDirectory() throws {
        let png16 = Data(repeating: 1, count: 10), png256 = Data(repeating: 2, count: 20)
        let data = try ICOEncoder.encode([(16, png16), (256, png256)])
        #expect(Array(data[0..<6]) == [0, 0, 1, 0, 2, 0])
        #expect(data[6] == 16 && data[22] == 0) // 256 is stored as 0
        // First image's offset is right after the 6 + 2*16 byte header.
        #expect(Int(data[18]) == 38)
        #expect(data.count == 38 + 30)
        #expect(data[38] == 1 && data[48] == 2)
    }

    @Test func windowsIconHasSevenSizesAndImageIOReadsIt() throws {
        let plan = try exporter.plan(.ico, style: IconStyle(), options: ExportOptions())
        let source = try #require(CGImageSourceCreateWithData(plan.files[0].data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 7)
    }

    @Test func replacingAnExportTrashesTheOldOne() throws {
        let dir = try makeTestFolder()
        let trash = dir.appending(path: "trash")
        let writer = ExportWriter(trash: FolderTrash(folder: trash))
        let target = dir.appending(path: "logo.iconset")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appending(path: "old.txt"))
        let plan = try exporter.plan(.iconset, style: IconStyle(), options: ExportOptions())
        try writer.write(plan, format: .iconset, to: target)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "old.txt").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "icon_16x16.png").path))
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: "logo.iconset/old.txt").path))
    }

    @Test func requiredExtensionIsKept() {
        let url = URL(fileURLWithPath: "/tmp/iconsmith-test/My Icon")
        #expect(ExportWriter.withExtension(url, format: .icns).lastPathComponent == "My Icon.icns")
        #expect(ExportWriter.withExtension(url.appendingPathExtension("ICNS"), format: .icns).lastPathComponent == "My Icon.ICNS")
        #expect(ExportWriter.withExtension(url, format: .favicons).lastPathComponent == "My Icon")
    }

    @Test func suggestedNames() {
        #expect(ExportFormat.icns.suggestedName(base: "logo") == "logo.icns")
        #expect(ExportFormat.xcode.suggestedName(base: "logo") == "AppIcon.appiconset")
        #expect(ExportFormat.favicons.suggestedName(base: "logo") == "logo Favicons")
        #expect(ExportFormat.png.suggestedName(base: "logo", source: "logo.png") == "logo Icon.png")
        #expect(ExportFormat.icns.suggestedName(base: "logo", source: "logo.png") == "logo.icns")
        #expect(ExportFormat.icns.suggestedName(base: "app", source: "app.icns") == "app Icon.icns")
    }

    @Test func unwritableDestinationGivesClearError() throws {
        let dir = try makeTestFolder()
        let locked = dir.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let plan = try exporter.plan(.png, style: IconStyle(), options: ExportOptions(pngSize: 256))
        #expect(throws: ExportError.self) { try ExportWriter().write(plan, format: .png, to: locked.appending(path: "x.png")) }
    }
}
