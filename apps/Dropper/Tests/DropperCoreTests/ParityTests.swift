import Foundation
import Testing
@testable import DropperCore

@Suite struct MoreFormatTests {
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)

    @Test(arguments: [
        (ColorFormat.cssRGBA, "rgba(51, 102, 204, 1)"),
        (.cssHSLA, "hsla(220, 60%, 50%, 1)"),
        (.cssHWB, "hwb(220 20% 20%)"),
        (.cssCMYK, "device-cmyk(75% 50% 0% 20%)"),
        (.swiftUIHSB, "Color(hue: 0.611, saturation: 0.75, brightness: 0.8)"),
        (.nsColorHSB, "NSColor(hue: 0.611, saturation: 0.75, brightness: 0.8, alpha: 1)"),
        (.uiColorHSB, "UIColor(hue: 0.611, saturation: 0.75, brightness: 0.8, alpha: 1)"),
        (.cgColor, "CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)"),
        (.objcNSColor, "[NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.8 alpha:1]"),
        (.objcUIColor, "[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1]"),
        (.androidARGB, "#FF3366CC"),
        (.compose, "Color(0xFF3366CC)"),
        (.flutter, "Color.fromARGB(255, 51, 102, 204)"),
        (.dotNetRGB, "Color.FromArgb(51, 102, 204)"),
        (.dotNetARGB, "Color.FromArgb(255, 51, 102, 204)"),
        (.javaRGB, "new Color(51, 102, 204)"),
        (.javaRGBA, "new Color(51, 102, 204, 255)"),
        (.unitRGB, "0.2, 0.4, 0.8"),
        (.unitRGBA, "0.2, 0.4, 0.8, 1"),
    ])
    func formats(format: ColorFormat, expected: String) {
        #expect(ColorFormatter.string(blue, as: format) == expected)
    }

    @Test func androidXMLUsesTheName() {
        #expect(ColorFormatter.string(blue, as: .androidXML, name: "Brand Blue 2") == "<color name=\"brand_blue_2\">#FF3366CC</color>")
        #expect(ColorFormatter.resourceName("2 Blue") == "color_2_blue")
    }

    @Test func oklchMatchesCSSReference() {
        // CSS Color 4: red is oklch(62.8% 0.2577 29.23).
        #expect(ColorFormatter.string(ColorValue(red: 1, green: 0, blue: 0), as: .cssOKLCH) == "oklch(62.8% 0.258 29.2)")
        #expect(ColorFormatter.string(ColorValue(red: 1, green: 1, blue: 1), as: .cssOKLCH) == "oklch(100% 0 0)")
        #expect(ColorFormatter.string(ColorValue(red: 0, green: 0, blue: 0), as: .cssOKLCH) == "oklch(0% 0 0)")
    }

    @Test func labMatchesCSSReference() {
        // CSS Color 4: sRGB red is lab(54.29 80.8 69.89) (D50).
        let lab = ColorMath.lab(fromSRGB: RGB(red: 1, green: 0, blue: 0))
        #expect(abs(lab.l - 54.29) < 0.05 && abs(lab.a - 80.8) < 0.1 && abs(lab.b - 69.89) < 0.1)
        let white = ColorMath.lab(fromSRGB: RGB(red: 1, green: 1, blue: 1))
        #expect(abs(white.l - 100) < 0.01 && abs(white.a) < 0.01 && abs(white.b) < 0.01)
        #expect(ColorFormatter.string(ColorValue(red: 0.5, green: 0.5, blue: 0.5), as: .cssLCH).hasSuffix(" 0 0)"))
    }

    @Test func labAndOKLabRoundTrip() {
        for c in [RGB(red: 0.2, green: 0.4, blue: 0.8), RGB(red: 0.9, green: 0.1, blue: 0.3), RGB(red: 0.07, green: 0.67, blue: 0.5)] {
            let a = ColorMath.sRGB(fromLab: ColorMath.lab(fromSRGB: c))
            let b = ColorMath.sRGB(fromOKLab: ColorMath.oklab(fromSRGB: c))
            #expect(zip(a.components, c.components).allSatisfy { abs($0 - $1) < 1e-6 })
            #expect(zip(b.components, c.components).allSatisfy { abs($0 - $1) < 1e-6 })
        }
    }

    @Test func platformFormatsStaySRGBInP3Mode() {
        let p3 = FormatOptions(space: .displayP3)
        #expect(ColorFormatter.string(blue, as: .androidARGB, options: p3) == "#FF3366CC")
        #expect(ColorFormatter.string(blue, as: .flutter, options: p3) == "Color.fromARGB(255, 51, 102, 204)")
        #expect(ColorFormatter.string(blue, as: .cgColor, options: p3).hasPrefix("CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!"))
    }

    @Test func everyFormatIsInExactlyOneGroup() {
        let grouped = ColorFormat.groups.flatMap(\.formats)
        #expect(Set(grouped) == Set(ColorFormat.allCases))
        #expect(grouped.count == ColorFormat.allCases.count)
    }

    @Test func everyFormatIsLocaleSafe() {
        let color = ColorValue(red: 0.123, green: 0.456, blue: 0.789)
        for format in ColorFormat.allCases {
            let text = ColorFormatter.string(color, as: format)
            #expect(!text.contains(",5") && !text.contains("0,1") && !text.isEmpty, "\(format)")
        }
    }

    @Test func hiddenFormatsKeepTheCurrentOne() {
        let prefs = Preferences(format: .cssLab, hiddenFormats: [.cssLab, .javaRGB])
        #expect(prefs.visibleFormats.contains(.cssLab))
        #expect(!prefs.visibleFormats.contains(.javaRGB))
    }

    @Test func parsesOKLCH() {
        let red = ColorParser.color("oklch(62.8% 0.2577 29.23)", in: .sRGB)
        #expect(red.map { ColorFormatter.string($0, as: .hex) } == "#FF0000")
        #expect(ColorParser.color("oklch(0.5 0.1 200)", in: .sRGB) != nil)
        #expect(ColorParser.color("oklch(150% 0.1 200)", in: .sRGB) == nil)
    }
}

@Suite struct NameTests {
    @Test(arguments: [
        ("#000000", "Black"), ("#FFFFFF", "White"), ("#808080", "Gray"), ("#FF0000", "Vivid Red"),
        ("#3366CC", "Blue"), ("#000080", "Very Dark Blue"), ("#8B4513", "Dark Brown"), ("#FFC0CB", "Pale Pink"),
        ("#008000", "Green"), ("#00FFFF", "Pale Cyan"), ("#808000", "Olive"),
    ])
    func names(hex: String, expected: String) throws {
        let color = try #require(HexParser.color(hex, in: .sRGB))
        #expect(ColorNamer.name(for: color) == expected)
    }

    @Test func savedNameWins() {
        var item = PickedColor(color: ColorValue(red: 0, green: 0, blue: 0), date: .now)
        #expect(item.displayName == "Black")
        item.name = "Ink"
        #expect(item.displayName == "Ink")
        item.name = "  "
        #expect(item.displayName == "Black")
    }
}

@Suite struct ContrastFixTests {
    let white = ColorValue(red: 1, green: 1, blue: 1)

    @Test func targets() {
        #expect(ContrastFixer.target(for: 2.9) == 4.5)
        #expect(ContrastFixer.target(for: 4.5) == 7)
        #expect(ContrastFixer.target(for: 7.2) == nil)
    }

    @Test func fixDarkensLightTextOnWhite() throws {
        let text = try #require(HexParser.color("#7FA7E0", in: .sRGB))
        let fixed = try #require(ContrastFixer.fix(text, against: white, target: 4.5))
        #expect(Contrast.ratio(fixed, white) >= 4.5)
        #expect(Contrast.ratio(fixed, white) < 5.2) // the nearest pass, not black
        // Same hue family.
        let before = ColorMath.oklch(fromSRGB: text.sRGB), after = ColorMath.oklch(fromSRGB: fixed.sRGB)
        #expect(abs(before.h - after.h) < 8)
    }

    @Test func fixLightensWhenThatsCloser() throws {
        let navy = try #require(HexParser.color("#1A1A40", in: .sRGB))
        let text = try #require(HexParser.color("#555577", in: .sRGB))
        let fixed = try #require(ContrastFixer.fix(text, against: navy, target: 4.5))
        #expect(Contrast.ratio(fixed, navy) >= 4.5)
        #expect(Contrast.luminance(fixed) > Contrast.luminance(text))
    }

    @Test func impossibleTargetIsNil() throws {
        let gray = try #require(HexParser.color("#777777", in: .sRGB))
        #expect(ContrastFixer.fix(gray, against: gray, target: 7) == nil)
    }

    @Test func alreadyPassingIsUnchanged() {
        let black = ColorValue(red: 0, green: 0, blue: 0)
        #expect(ContrastFixer.fix(black, against: white, target: 7) == black)
    }
}

@Suite struct ColorVisionTests {
    @Test func normalIsIdentityAndOthersStayInRange() {
        let c = ColorValue(red: 0.9, green: 0.2, blue: 0.3)
        #expect(ColorVision.normal.simulate(c) == c)
        for mode in ColorVision.allCases {
            let s = mode.simulate(c).sRGB
            #expect(s.components.allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 })
        }
        let gray = ColorVision.achromatopsia.simulate(c).sRGB
        #expect(abs(gray.red - gray.green) < 1e-9 && abs(gray.green - gray.blue) < 1e-9)
    }

    @Test func protanopiaConfusesRedAndGreen() {
        let red = ColorValue(red: 0.8, green: 0.2, blue: 0.1), green = ColorValue(red: 0.4, green: 0.5, blue: 0.1)
        let a = ColorVision.protanopia.simulate(red).sRGB, b = ColorVision.protanopia.simulate(green).sRGB
        let before = abs(red.sRGB.red - green.sRGB.red), after = abs(a.red - b.red)
        #expect(after < before)
    }
}

@Suite struct PaletteTests {
    let date = Date(timeIntervalSince1970: 1000)
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    let red = ColorValue(red: 1, green: 0, blue: 0)
    let green = ColorValue(red: 0, green: 0.6, blue: 0)

    @Test func noDuplicatesAndLockRefusesChanges() {
        var p = Palette(name: "P", created: date)
        let first = p.add(blue, at: date)
        let again = p.add(blue, at: date)
        #expect(first && !again)
        p.isLocked = true
        let lockedAdd = p.add(red, at: date)
        let lockedRemove = p.remove([p.colors[0].id], at: date)
        #expect(!lockedAdd && !lockedRemove)
        #expect(p.colors.count == 1)
    }

    @Test func moveLikeOnMove() {
        var p = Palette(name: "P", colors: [blue, red, green].map { PickedColor(color: $0, date: date) }, created: date)
        p.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, at: date)
        #expect(p.colors.map(\.color) == [red, green, blue])
        p.move(fromOffsets: IndexSet(integer: 2), toOffset: 0, at: date)
        #expect(p.colors.map(\.color) == [blue, red, green])
    }

    @Test func sortByHueAndLightness() {
        var p = Palette(name: "P", colors: [blue, ColorValue(red: 0.5, green: 0.5, blue: 0.5), red, green].map { PickedColor(color: $0, date: date) },
                        created: date)
        p.sort(by: .hue, at: date)
        #expect(p.colors.map(\.color) == [red, green, blue, ColorValue(red: 0.5, green: 0.5, blue: 0.5)])
        p.sort(by: .lightness, at: date)
        #expect(p.colors.first?.color == green || p.colors.first?.color == red)
    }

    @Test func duplicateAndMerge() {
        let a = Palette(name: "A", colors: [PickedColor(color: blue, date: date, name: "Brand")], created: date)
        let copy = a.duplicate(at: date)
        #expect(copy.name == "A copy" && copy.id != a.id && copy.colors[0].id != a.colors[0].id && copy.colors[0].name == "Brand")
        var b = Palette(name: "B", colors: [PickedColor(color: red, date: date)], created: date)
        let once = b.merge(a, at: date)
        let twice = b.merge(a, at: date)
        #expect(once == 1 && twice == 0)
    }
}

@MainActor
@Suite struct LibraryModelTests {
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    let red = ColorValue(red: 1, green: 0, blue: 0)

    func makeModel(_ picks: [ColorValue?], store: LibraryStore = MemoryLibraryStore()) -> (DropperModel, FakeClipboard) {
        let clipboard = FakeClipboard()
        let model = DropperModel(sampler: FakeSampler(picks), clipboard: clipboard, historyStore: store,
                                 preferencesStore: FakePreferences(), now: { Date(timeIntervalSince1970: 1000) })
        return (model, clipboard)
    }

    @Test func picksJoinTheActivePalette() async throws {
        let store = MemoryLibraryStore()
        let (model, _) = makeModel([blue, red], store: store)
        let palette = model.newPalette()
        #expect(palette.name == "New Palette")
        #expect(model.newPalette().name == "New Palette 2")
        model.activePaletteID = palette.id
        _ = await model.pickAndCopy()
        model.activePaletteID = nil
        _ = await model.pickAndCopy()
        #expect(model.palette(palette.id)?.colors.map(\.color) == [blue])
        #expect(model.history.items.count == 2)
        let saved = try store.load()
        #expect(saved.palettes.count == 2 && saved.palettes[0].colors.count == 1)
        #expect(saved.activePaletteID == nil)
    }

    @Test func activePaletteSurvivesReloadAndDeletionClearsIt() throws {
        let store = MemoryLibraryStore()
        let (model, _) = makeModel([], store: store)
        let p = model.newPalette(name: "Brand")
        model.activePaletteID = p.id
        let (reloaded, _) = makeModel([], store: store)
        #expect(reloaded.activePaletteID == p.id)
        reloaded.deletePalette(p.id)
        #expect(reloaded.activePaletteID == nil && reloaded.palettes.isEmpty)
    }

    @Test func lockedPaletteCantBeEditedOrDeleted() {
        let (model, _) = makeModel([])
        let p = model.newPalette(name: "Brand")
        model.setLocked(true, palette: p.id)
        model.renamePalette(p.id, to: "Other")
        #expect(!model.add(blue, to: p.id))
        model.deletePalette(p.id)
        #expect(model.palette(p.id)?.name == "Brand")
        model.setLocked(false, palette: p.id)
        model.renamePalette(p.id, to: "Other")
        #expect(model.palette(p.id)?.name == "Other")
    }

    @Test func pickMultipleCopiesAllUntilCancel() async {
        let (model, clipboard) = makeModel([blue, red, nil])
        let result = await model.pickMultiple()
        #expect(result?.count == 2)
        #expect(clipboard.writes == ["#3366CC\n#FF0000"])
        #expect(model.history.items.map(\.color) == [red, blue])
    }

    @Test func pickContrastPair() async {
        let (model, clipboard) = makeModel([blue, red])
        let pair = await model.pickContrastPair()
        #expect(pair?.text == blue && pair?.background == red)
        #expect(clipboard.writes.isEmpty)
        let (cancelled, _) = makeModel([blue, nil])
        #expect(await cancelled.pickContrastPair() == nil)
    }

    @Test func editNameInHistoryAndPalette() async throws {
        let (model, clipboard) = makeModel([blue])
        _ = await model.pickAndCopy()
        var item = try #require(model.history.latest)
        item.name = "Brand Blue"
        model.update(item, in: .history)
        #expect(model.history.latest?.displayName == "Brand Blue")
        let p = model.newPalette(colors: [item])
        #expect(model.palette(p.id)?.colors.first?.name == "Brand Blue")
        model.preferences.format = .androidXML
        model.copy(try #require(model.palette(p.id)?.colors.first))
        #expect(clipboard.writes.last == "<color name=\"brand_blue\">#FF3366CC</color>")
    }

    @Test func mergeAndImportMakeNamesUnique() {
        let (model, _) = makeModel([])
        let a = model.newPalette(name: "A", colors: [PickedColor(color: blue, date: .now)])
        let b = model.newPalette(name: "B", colors: [PickedColor(color: red, date: .now), PickedColor(color: blue, date: .now)])
        #expect(model.merge([b.id], into: a.id) == 1)
        #expect(model.palettes.map(\.name) == ["A"])
        let imported = model.importPalettes([Palette(name: "A", created: .now)])
        #expect(imported.first?.name == "A 2")
    }

    @Test func dockFlagPersistsAndOldPalettesDecode() throws {
        let store = MemoryLibraryStore()
        let (model, _) = makeModel([], store: store)
        let p = model.newPalette(name: "Dock me")
        model.setLocked(true, palette: p.id)
        model.setInDock(true, palette: p.id)
        #expect(model.dockPalettes.map(\.id) == [p.id])
        #expect(try store.load().palettes.first?.inDock == true)
        let old = #"{"id":"6F1C2D1E-0000-4000-8000-000000000002","name":"Old","colors":[],"isLocked":false,"created":"2026-11-03T10:00:00Z","modified":"2026-11-03T10:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Palette.self, from: Data(old.utf8))
        #expect(decoded.inDock == false && decoded.note.isEmpty)
    }

    @Test func appFormatsApplyOnlyWhenOnAndMatching() async {
        let (model, clipboard) = makeModel([blue, blue, blue])
        model.preferences.appFormats = ["com.apple.dt.Xcode": .swiftUI]
        model.frontmostApp = { "com.apple.dt.Xcode" }
        _ = await model.pickAndCopy()
        model.preferences.usesAppFormats = true
        let result = await model.pickAndCopy()
        model.frontmostApp = { "com.apple.Safari" }
        _ = await model.pickAndCopy()
        #expect(clipboard.writes == ["#3366CC", "Color(red: 0.2, green: 0.4, blue: 0.8)", "#3366CC"])
        #expect(result?.appFormat == .swiftUI)
    }

    @Test func version1FileStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dropper-v1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = """
        {"history":[{"color":{"sRGB":{"blue":0.8,"green":0.4,"red":0.2}},"date":"2026-11-03T10:00:00Z","id":"6F1C2D1E-0000-4000-8000-000000000001"}],"version":1}
        """
        try Data(v1.utf8).write(to: dir.appendingPathComponent("colors.json"))
        let contents = try FileLibraryStore(directory: dir).load()
        #expect(contents.history.count == 1 && contents.palettes.isEmpty)
        #expect(contents.history[0].name == nil)
    }
}

@Suite struct CodecTests {
    let date = Date(timeIntervalSince1970: 1000)

    var palette: Palette {
        Palette(name: "Brand Ünïcode", note: "Main colors", colors: [
            PickedColor(color: ColorValue(red: 0.2, green: 0.4, blue: 0.8), date: date, name: "Ocean"),
            PickedColor(color: ColorValue(red: 1, green: 0, blue: 0), date: date),
            PickedColor(color: ColorValue(displayP3: RGB(red: 0, green: 1, blue: 0)), date: date, name: "P3 Green"),
        ], created: date)
    }

    @Test func aseRoundTrip() throws {
        let data = PaletteCodec.ase(palette)
        #expect(data.prefix(4) == Data("ASEF".utf8))
        let back = try PaletteCodec.importPalettes(data, format: .ase, fallbackName: "file", date: date)
        #expect(back.count == 1)
        #expect(back[0].name == "Brand Ünïcode")
        #expect(back[0].colors.map(\.displayName) == ["Ocean", "Vivid Red", "P3 Green"])
        #expect(ColorFormatter.string(back[0].colors[0].color, as: .hex) == "#3366CC")
    }

    @Test func jsonRoundTripKeepsWideGamut() throws {
        let data = try #require(PaletteCodec.json(palette))
        let back = try PaletteCodec.importPalettes(data, format: .json, fallbackName: "file", date: date)
        #expect(back[0].name == "Brand Ünïcode" && back[0].note == "Main colors")
        #expect(back[0].colors[2].color.isOutsideSRGB)
        #expect(back[0].colors[0].name == "Ocean")
    }

    @Test func gplRoundTrip() throws {
        let text = PaletteCodec.gpl(palette)
        #expect(text.hasPrefix("GIMP Palette\nName: Brand Ünïcode\n"))
        #expect(text.contains(" 51 102 204\tOcean"))
        let back = try PaletteCodec.importPalettes(Data(text.utf8), format: .gpl, fallbackName: "file", date: date)
        #expect(back[0].colors.count == 3 && back[0].name == "Brand Ünïcode")
    }

    @Test func cssVariables() {
        let css = PaletteCodec.css(palette)
        #expect(css.contains("  --ocean: #3366CC;"))
        #expect(css.contains("  --vivid-red: #FF0000;"))
    }

    @Test func importScansTextForColors() throws {
        let text = ":root { --a: #3366cc; --b: rgb(255 0 0); --c: #36c; color: hsl(120, 100%, 25%); } /* #12345 isn't */"
        let back = try PaletteCodec.importPalettes(Data(text.utf8), format: .css, fallbackName: "tokens", date: date)
        #expect(back[0].name == "tokens")
        #expect(back[0].colors.map { ColorFormatter.string($0.color, as: .hex) } == ["#3366CC", "#FF0000", "#008000"])
    }

    @Test func garbageIsRejected() {
        #expect(throws: PaletteCodecError.noColors) {
            try PaletteCodec.importPalettes(Data("hello".utf8), format: nil, fallbackName: "x", date: date)
        }
        #expect(throws: PaletteCodecError.self) {
            try PaletteCodec.importPalettes(Data("ASEF\u{0}".utf8), format: .ase, fallbackName: "x", date: date)
        }
    }
}

@Suite struct LoupeTests {
    @Test func stepsClampAndCellsAreOdd() {
        var g = LoupeGeometry(sizeStep: 99, zoomStep: -3)
        #expect(g.sizeStep == LoupeGeometry.diameters.count - 1 && g.zoomStep == 0)
        g.grow(); g.zoomOut()
        #expect(g.sizeStep == LoupeGeometry.diameters.count - 1 && g.zoomStep == 0)
        for s in 0..<LoupeGeometry.diameters.count {
            for z in 0..<LoupeGeometry.cellSizes.count {
                #expect(LoupeGeometry(sizeStep: s, zoomStep: z).cells % 2 == 1)
            }
        }
        let sample = LoupeGeometry().sampleRect(around: PixelPoint(x: 100, y: 50))
        #expect(sample.x == 100 - LoupeGeometry().cells / 2 && sample.side == LoupeGeometry().cells)
    }

    @Test func pixelMappingRoundTripsOnRetina() {
        let p = PixelPoint.under(local: CGPoint(x: 10.3, y: 890.2), height: 900, scale: 2)
        #expect(p == PixelPoint(x: 20, y: 19))
        let back = p.localCenter(height: 900, scale: 2)
        #expect(PixelPoint.under(local: back, height: 900, scale: 2) == p)
    }

    @Test func nudgeIsOnePixelAndClamped() {
        let p = PixelPoint(x: 0, y: 5)
        let right = PickerNudge.delta(keyCode: 124, shift: false)
        let up = PickerNudge.delta(keyCode: 126, shift: true)
        #expect(right?.dx == 1 && right?.dy == 0)
        #expect(up?.dx == 0 && up?.dy == -10)
        #expect(PickerNudge.delta(keyCode: 0, shift: false) == nil)
        #expect(p.nudged(dx: -1, dy: -10, width: 100, height: 100) == PixelPoint(x: 0, y: 0))
        #expect(p.nudged(dx: 200, dy: 1, width: 100, height: 100) == PixelPoint(x: 99, y: 6))
    }
}

@Suite struct DockTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func snapsToNearestEdge() {
        #expect(DockPlacement.snapped(center: CGPoint(x: 30, y: 400), in: screen) == DockPlacement(edge: .left, position: 0.5))
        #expect(DockPlacement.snapped(center: CGPoint(x: 990, y: 200), in: screen).edge == .right)
        #expect(DockPlacement.snapped(center: CGPoint(x: 250, y: 790), in: screen) == DockPlacement(edge: .top, position: 0.25))
        #expect(DockPlacement.snapped(center: CGPoint(x: 500, y: 5), in: screen).edge == .bottom)
    }

    @Test func frameStaysOnScreen() {
        let left = DockPlacement(edge: .left, position: 0).frame(length: 200, thickness: 24, in: screen)
        #expect(left == CGRect(x: 4, y: 4, width: 24, height: 200))
        let right = DockPlacement(edge: .right, position: 1).frame(length: 2000, thickness: 24, in: screen)
        #expect(right.maxX == 996 && right.minY == 4 && right.maxY == 796)
        let bottom = DockPlacement(edge: .bottom, position: 0.5).frame(length: 300, thickness: 24, in: screen)
        #expect(bottom == CGRect(x: 350, y: 4, width: 300, height: 24))
    }
}
