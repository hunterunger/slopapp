import AppKit
import Foundation
import ImageIO
import Testing
@testable import IconsmithCore

/// A stand-in for the system folder icon: a light blue folder shape (tab on top) with
/// transparent margins, so tests don't depend on the running macOS's artwork.
func fakeFolderArt() -> FolderArt {
    let n = 256
    let context = Bitmap.context(pixels: n)!
    context.setFillColor(CGColor(srgbRed: 0.45, green: 0.72, blue: 0.93, alpha: 1))
    context.fill(CGRect(x: 10, y: 30, width: 236, height: 180))  // front
    context.fill(CGRect(x: 10, y: 200, width: 90, height: 26))   // tab
    let image = NSImage(size: NSSize(width: 256, height: 256))
    image.addRepresentation(NSBitmapImageRep(cgImage: context.makeImage()!))
    let doc = Bitmap.context(pixels: n)!
    doc.setFillColor(CGColor(gray: 0.98, alpha: 1))
    doc.fill(CGRect(x: 48, y: 16, width: 160, height: 224))
    let document = NSImage(size: NSSize(width: 256, height: 256))
    document.addRepresentation(NSBitmapImageRep(cgImage: doc.makeImage()!))
    let measured = FolderArt.measure(image)!
    return FolderArt(image: image, layout: measured.layout, tone: measured.tone, document: document,
                     documentLayout: DocumentLayout(bounds: FolderArt.measureBounds(document)!))
}

/// A wide horizontal bar on transparency (to see rotation).
func barSource() -> IconSource {
    let context = Bitmap.context(width: 400, height: 100)!
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 30, width: 400, height: 40))
    return IconSource(content: .raster(context.makeImage()!), name: "bar", url: nil, size: CGSize(width: 400, height: 100))
}

@Suite struct TemplateTests {
    @Test func everyTemplateRendersAndIsGrouped() throws {
        let renderer = IconRenderer(source: rasterSource(), folder: fakeFolderArt())
        for shape in IconShape.allCases {
            let image = try #require(renderer.render(IconStyle(shape: shape), pixels: 64))
            #expect(pixel(image, 32, 36).a > 0.9, "\(shape) draws something in the middle")
        }
        #expect(IconShape.allCases.filter { $0.group == .finder } == [.folder, .folderCover, .folderSymbol, .document])
        #expect(IconShape.folder.usesBackground && IconShape.folder.colorTitle == "Folder Color")
        #expect(!IconShape.document.usesBackground && !IconShape.asIs.usesBackground)
    }

    @Test func roundedCutsCornersButIsFullCanvas() throws {
        let image = try #require(IconRenderer(source: rasterSource()).render(IconStyle(shape: .rounded), pixels: 128))
        #expect(pixel(image, 1, 1).a < 0.05)
        #expect(pixel(image, 64, 1).a > 0.95)   // edge middle: full canvas
        #expect(pixel(image, 1, 64).a > 0.95)
    }

    @Test func folderColorRecoloursTheFolder() throws {
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true), folder: fakeFolderArt())
        let standard = try #require(renderer.render(IconStyle(shape: .folder), pixels: 256))
        let plain = pixel(standard, 30, 128)  // folder front, outside the picture
        #expect(plain.b > plain.r + 0.3)
        let red = try #require(renderer.render(IconStyle(shape: .folder, background: .color, color: RGBA(0.9, 0.2, 0.2)), pixels: 256))
        let tinted = pixel(red, 30, 128)
        #expect(tinted.r > tinted.b + 0.4)
        #expect(abs(tinted.r - 0.9) < 0.12)     // close to the chosen colour
        #expect(pixel(red, 2, 2).a < 0.01)      // corners stay transparent
        #expect(pixel(red, 200, 40).a < 0.01)   // beside the tab too
    }

    @Test func folderSymbolPressesThePictureIntoTheFolder() throws {
        let folder = fakeFolderArt()
        let renderer = IconRenderer(source: rasterSource(transparentEdges: true), folder: folder)
        let image = try #require(renderer.render(IconStyle(shape: .folderSymbol), pixels: 256))
        let centre = pixel(image, 128, 136)
        let tone = (folder.tone ?? .white).symbolTone
        #expect(abs(centre.r - tone.red) < 0.08 && abs(centre.b - tone.blue) < 0.08)
        // Not the picture's own red.
        #expect(centre.r < 0.5)
        // A black logo on white (opaque) uses its dark parts as the symbol.
        let opaqueLogo = IconRenderer(source: rasterSource(), folder: folder)
        let mask = try #require(opaqueLogo.render(IconStyle(shape: .folderSymbol), pixels: 128))
        #expect(pixel(mask, 64, 68).b < pixel(mask, 20, 64).b) // ink darker than the folder
    }

    @Test func documentPutsThePictureOnThePage() throws {
        let renderer = IconRenderer(source: rasterSource(), folder: fakeFolderArt())
        let image = try #require(renderer.render(IconStyle(shape: .document), pixels: 256))
        #expect(pixel(image, 20, 128).a < 0.01)                 // left of the page
        let page = pixel(image, 128, 30)
        #expect(page.r > 0.9 && page.g > 0.9)                    // page, below the picture
        #expect(pixel(image, 128, 128).a > 0.99)
    }

    @Test func rotationTurnsThePicture() throws {
        let renderer = IconRenderer(source: barSource())
        let flat = try #require(renderer.render(IconStyle(shape: .asIs, fill: false), pixels: 128))
        #expect(pixel(flat, 10, 64).a > 0.9)
        #expect(pixel(flat, 64, 20).a < 0.1)
        let turned = try #require(renderer.render(IconStyle(shape: .asIs, fill: false, rotation: 90), pixels: 128))
        #expect(pixel(turned, 10, 64).a < 0.1)
        #expect(pixel(turned, 64, 20).a > 0.9)
        #expect(IconStyle(rotation: 400).clamped().rotation == 180)
    }
}

@Suite struct TextTests {
    let blank = IconSource.blank()!

    @Test func blankPictureIsEmptyUntilTextIsAdded() throws {
        let renderer = IconRenderer(source: blank)
        let empty = try #require(renderer.render(IconStyle(shape: .asIs), pixels: 128))
        #expect(pixel(empty, 64, 64).a < 0.01)
        var style = IconStyle(shape: .asIs)
        style.text = IconText(string: "HI", color: .black)
        let text = try #require(renderer.render(style, pixels: 128))
        var inked = 0
        for y in stride(from: 40, to: 88, by: 2) { for x in stride(from: 20, to: 108, by: 2) where pixel(text, x, y).a > 0.5 { inked += 1 } }
        #expect(inked > 40)
        #expect(blank.isBlank && !blank.isSmall)
    }

    @Test func autoSizeFitsTheWidthAndManualSizeScales() {
        let renderer = IconRenderer(source: blank)
        var style = IconStyle(shape: .square)
        style.text = IconText(string: "A very long folder label")
        let long = renderer.textLayout(style, pixels: 1024)
        let width = CTLineGetTypographicBounds(IconRenderer.line(style.text.string, font: IconRenderer.font(style.text, size: long.size), color: .black), nil, nil, nil)
        #expect(width <= long.area.width * 0.95)
        style.text = IconText(string: "A")
        let short = renderer.textLayout(style, pixels: 1024)
        #expect(short.size > long.size)
        style.text = IconText(string: "A", autoSize: false, size: 0.2)
        let small = renderer.textLayout(style, pixels: 1024).size
        style.text.size = 0.4
        #expect(renderer.textLayout(style, pixels: 1024).size > small * 1.9)
    }

    @Test func badgeSitsInTheBottomRightCorner() throws {
        var style = IconStyle(shape: .square, background: .color, color: .white)
        style.text = IconText(string: "3", position: .badge, badgeColor: RGBA(0, 0.6, 0))
        let image = try #require(IconRenderer(source: blank).render(style, pixels: 256))
        let layout = IconRenderer(source: blank).textLayout(style, pixels: 256)
        let badge = try #require(layout.badge)
        #expect(badge.midX > 160 && badge.midY < 96)            // bottom right (y up)
        // The circle's colour near its rim (the digit sits in the middle).
        let rim = pixel(image, Int(badge.midX), 256 - Int(badge.minY) - 6)
        #expect(rim.g > 0.5 && rim.r < 0.2)
        #expect(IconRenderer(source: blank).textColor(for: style) == .white) // contrasts with the badge
    }

    @Test func automaticTextColours() {
        let renderer = IconRenderer(source: blank, folder: fakeFolderArt())
        var folder = IconStyle(shape: .folder)
        folder.text.string = "x"
        #expect(renderer.textColor(for: folder) == renderer.folderTone(for: folder).symbolTone)
        let dark = IconStyle(shape: .square, background: .color, color: .black)
        #expect(renderer.textColor(for: dark) == .white)
        let light = IconStyle(shape: .square, background: .color, color: .white)
        #expect(renderer.textColor(for: light).luminance < 0.2)
    }
}

struct FakeRemover: BackgroundRemoving {
    var keepCentre = true
    func subjectMask(for image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var mask = [UInt8](repeating: 0, count: w * h)
        guard keepCentre else { return mask }
        for y in h / 4..<(3 * h / 4) { for x in w / 4..<(3 * w / 4) { mask[y * w + x] = 255 } }
        return mask
    }
}

@Suite struct CutoutTests {
    @Test func maskMakesTheBackgroundTransparent() throws {
        let cut = try Cutout.make(from: rasterSource(width: 200, height: 200), remover: FakeRemover())
        #expect(cut.isCutout)
        guard case .raster(let image) = cut.content else { Issue.record("expected raster"); return }
        #expect(pixel(image, 5, 5).a < 0.01)
        #expect(pixel(image, 100, 100).a > 0.99)
        #expect(cut.edges.isTransparent) // now placed like a logo
    }

    @Test func emptyMaskMeansNoSubject() {
        #expect(throws: CutoutError.noSubject) {
            try Cutout.make(from: rasterSource(width: 64, height: 64), remover: FakeRemover(keepCentre: false))
        }
    }

    @Test func vectorSourcesAreDrawnFirst() throws {
        let vector = IconSource(content: .vector(FakeIconProvider().icon(forFile: URL(fileURLWithPath: "/"))!), name: "v", url: nil,
                                size: CGSize(width: 64, height: 32))
        let cut = try Cutout.make(from: vector, remover: FakeRemover())
        #expect(cut.size == CGSize(width: 1024, height: 512))
    }
}

@Suite struct ParityExportTests {
    let logo = IconExporter(renderer: IconRenderer(source: rasterSource(transparentEdges: true)))
    let photo = IconExporter(renderer: IconRenderer(source: rasterSource()))

    @Test func androidHasEveryDensityRoundAdaptiveAndPlayStore() throws {
        let plan = try logo.plan(.android, style: IconStyle(), options: ExportOptions())
        #expect(plan.files.count == 5 * 4 + 3)
        let byPath = Dictionary(uniqueKeysWithValues: plan.files.map { ($0.path, $0.data) })
        #expect(imageSize(byPath["res/mipmap-mdpi/ic_launcher.png"]!)! == (48, 48))
        #expect(imageSize(byPath["res/mipmap-xxxhdpi/ic_launcher_round.png"]!)! == (192, 192))
        #expect(imageSize(byPath["res/mipmap-xxhdpi/ic_launcher_foreground.png"]!)! == (324, 324))
        #expect(imageSize(byPath["playstore-icon.png"]!)! == (512, 512))
        #expect(!hasAlphaChannel(byPath["playstore-icon.png"]!))
        #expect(!hasAlphaChannel(byPath["res/mipmap-hdpi/ic_launcher_background.png"]!))
        let xml = String(decoding: byPath["res/mipmap-anydpi-v26/ic_launcher.xml"]!, as: UTF8.self)
        #expect(xml.contains("@mipmap/ic_launcher_foreground") && xml.contains("<monochrome"))
        // Foreground keeps the logo inside the safe zone: its corners are clear.
        let fg = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(byPath["res/mipmap-xxxhdpi/ic_launcher_foreground.png"]! as CFData, nil)!, 0, nil)!
        #expect(pixel(fg, 40, 40).a < 0.01)
        #expect(pixel(fg, 216, 216).a > 0.9)
        // A photo goes into the background layer and has no monochrome layer.
        let photoPlan = try photo.plan(.android, style: IconStyle(), options: ExportOptions())
        let photoXML = String(decoding: photoPlan.files.first { $0.path.hasSuffix("ic_launcher.xml") }!.data, as: UTF8.self)
        #expect(!photoXML.contains("<monochrome"))
    }

    @Test func androidWritesNestedFolders() throws {
        let dir = try makeTestFolder()
        let plan = try logo.plan(.android, style: IconStyle(), options: ExportOptions())
        let url = try ExportWriter(trash: FolderTrash(folder: dir.appending(path: "trash")))
            .write(plan, format: .android, to: dir.appending(path: "logo Android"))
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "res/mipmap-xhdpi/ic_launcher.png").path))
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "playstore-icon.png").path))
    }

    @Test func iOSDarkAndTintedVariants() throws {
        let plan = try logo.plan(.xcode, style: IconStyle(), options: ExportOptions(xcodePlatforms: [.iOS], xcodeAppearances: true))
        let json = try #require(try JSONSerialization.jsonObject(with: plan.files.first { $0.path == "Contents.json" }!.data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: Any]])
        #expect(images.count == 3)
        let values = images.compactMap { ($0["appearances"] as? [[String: String]])?.first?["value"] }
        #expect(Set(values) == ["dark", "tinted"])
        let dark = try #require(plan.files.first { $0.path == "AppIcon-iOS-Dark-1024.png" }?.data)
        #expect(hasAlphaChannel(dark)) // transparent: the system draws the dark background
        let tintedData = try #require(plan.files.first { $0.path == "AppIcon-iOS-Tinted-1024.png" }?.data)
        #expect(!hasAlphaChannel(tintedData))
        let tinted = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(tintedData as CFData, nil)!, 0, nil)!
        let centre = pixel(tinted, 512, 512)
        #expect(abs(centre.r - centre.g) < 0.02 && abs(centre.g - centre.b) < 0.02) // grey
        #expect(pixel(tinted, 4, 4).r < 0.02)                                         // on black
        // Off by default.
        let plain = try logo.plan(.xcode, style: IconStyle(), options: ExportOptions(xcodePlatforms: [.iOS]))
        #expect(plain.files.count == 2)
    }

    @Test func jpegIsOpaqueAtTheChosenSize() throws {
        let plan = try logo.plan(.jpg, style: IconStyle(), options: ExportOptions(pngSize: 512))
        let data = try #require(plan.files.first?.data)
        #expect(imageSize(data)! == (512, 512))
        #expect(!hasAlphaChannel(data))
        #expect(plan.notes.count == 1) // the macOS tile's corners became white
        let square = try photo.plan(.jpg, style: IconStyle(shape: .square), options: ExportOptions())
        #expect(square.notes.isEmpty)
    }

    @Test func folderExportIsAnEmptyFolder() throws {
        let dir = try makeTestFolder()
        let plan = try logo.plan(.folder, style: IconStyle(), options: ExportOptions())
        let url = try ExportWriter().write(plan, format: .folder, to: dir.appending(path: "Projects"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
    }

    @Test func batchNamesNeverCollide() {
        let names = BatchNaming.names(for: ["logo", "logo", "photo"], format: .icns, existing: ["photo.icns"])
        #expect(names == ["logo.icns", "logo 2.icns", "photo 2.icns"])
        #expect(BatchNaming.names(for: ["a", "b"], format: .xcode, existing: []) == ["a.appiconset", "b.appiconset"])
    }

    @Test func olderOptionsKeepTheirPlatforms() throws {
        let old = Data(#"{"xcodePlatforms":["watchOS"],"pngSize":512}"#.utf8)
        let options = try JSONDecoder().decode(ExportOptions.self, from: old)
        #expect(options.xcodePlatforms == [.watchOS] && options.pngSize == 512 && !options.xcodeAppearances)
    }
}

@Suite struct ColorTests {
    @Test func hsbRoundTripAndSymbolTone() {
        let colour = RGBA(0.45, 0.72, 0.93)
        let (h, s, b) = colour.hsb
        let back = RGBA(hue: h, saturation: s, brightness: b)
        #expect(abs(back.red - colour.red) < 0.001 && abs(back.green - colour.green) < 0.001 && abs(back.blue - colour.blue) < 0.001)
        #expect(colour.symbolTone.hsb.brightness < b)                 // darker on a light folder
        #expect(RGBA(0.1, 0.1, 0.1).symbolTone.luminance > 0.1)        // lighter on a dark one
        #expect(RGBA.white.contrasting.luminance < 0.2 && RGBA.black.contrasting == .white)
    }
}
