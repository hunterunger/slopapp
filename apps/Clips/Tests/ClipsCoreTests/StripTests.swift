import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

// MARK: - Strip geometry

@Suite struct StripLayoutTests {
    let layout = StripLayout(itemWidth: 200, spacing: 10, inset: 20)

    @Test func contentWidth() {
        #expect(layout.contentWidth(count: 0) == 0)
        #expect(layout.contentWidth(count: 1) == 240)
        #expect(layout.contentWidth(count: 3) == 20 + 600 + 20 + 20)
    }

    @Test func positions() {
        #expect(layout.x(of: 0) == 20)
        #expect(layout.x(of: 2) == 440)
    }

    @Test func visibleRange() {
        #expect(layout.visibleRange(offset: 0, viewportWidth: 500, count: 100) == 0..<3)
        // Scrolled so card 0 is just off-screen to the left.
        #expect(layout.visibleRange(offset: 221, viewportWidth: 200, count: 100) == 1..<2)
        #expect(layout.visibleRange(offset: 221, viewportWidth: 230, count: 100) == 1..<3)
        #expect(layout.visibleRange(offset: 0, viewportWidth: 5_000, count: 4) == 0..<4)
        #expect(layout.visibleRange(offset: 0, viewportWidth: 500, count: 0) == 0..<0)
    }

    @Test func hitTesting() {
        #expect(layout.index(atX: 10, count: 5) == nil) // inset
        #expect(layout.index(atX: 25, count: 5) == 0)
        #expect(layout.index(atX: 225, count: 5) == nil) // gap
        #expect(layout.index(atX: 235, count: 5) == 1)
        #expect(layout.index(atX: 5_000, count: 5) == nil)
    }

    @Test func revealScrollsTheLeastNeeded() {
        // Already visible: no scroll.
        #expect(layout.offset(revealing: 1, from: 0, viewportWidth: 500, count: 100) == 0)
        // Card 3 (x 650…850) needs the right edge plus inset in view.
        #expect(layout.offset(revealing: 3, from: 0, viewportWidth: 500, count: 100) == 870 - 500)
        // Back to the first card from far away.
        #expect(layout.offset(revealing: 0, from: 3_000, viewportWidth: 500, count: 100) == 0)
        // Never past the end.
        let end = layout.offset(revealing: 99, from: 0, viewportWidth: 500, count: 100)
        #expect(end == layout.contentWidth(count: 100) - 500)
    }

    @Test func pageSize() {
        #expect(layout.pageSize(viewportWidth: 500) == 2)
        #expect(layout.pageSize(viewportWidth: 100) == 1)
        #expect(layout.pageSize(viewportWidth: 2_000) == 9)
    }
}

// MARK: - Keyboard

@Suite struct PanelKeysTests {
    func command(_ code: UInt16, _ chars: String? = nil, _ mods: PanelKeys.Modifiers = [],
                 _ context: PanelKeys.Context = .init()) -> PanelCommand? {
        PanelKeys.command(keyCode: code, characters: chars, modifiers: mods, context: context)
    }

    @Test func returnPastesShiftReturnPastesPlain() {
        #expect(command(36) == .choose(plain: false))
        #expect(command(36, nil, .shift) == .choose(plain: true))
        #expect(command(76) == .choose(plain: false))
    }

    @Test func arrowsMoveThroughTheStrip() {
        #expect(command(123) == .move(-1))
        #expect(command(124) == .move(1))
        #expect(command(126) == .move(-1))
        #expect(command(125) == .move(1))
        #expect(command(126, nil, .command) == .first)
        #expect(command(125, nil, .command) == .last)
        #expect(command(115) == .first)
        #expect(command(119) == .last)
    }

    @Test func commandArrowsSwitchTabs() {
        #expect(command(123, nil, .command) == .previousTab)
        #expect(command(124, nil, .command) == .nextTab)
    }

    @Test func numbersQuickPaste() {
        #expect(command(18, "1", .command) == .quickPaste(index: 0, plain: false))
        #expect(command(25, "9", [.command, .shift]) == .quickPaste(index: 8, plain: true))
        #expect(command(83, "1", .command) == .quickPaste(index: 0, plain: false))
        // Bare digits type into the search.
        #expect(command(18, "1") == nil)
    }

    @Test func spaceIsQuickLookUnlessTypingASearch() {
        #expect(command(49, " ") == .quickLook)
        let searching = PanelKeys.Context(queryIsEmpty: false)
        #expect(command(49, " ", [], searching) == nil)
        let onCards = PanelKeys.Context(queryIsEmpty: false, cardsFocused: true)
        #expect(command(49, " ", [], onCards) == .quickLook)
        let open = PanelKeys.Context(queryIsEmpty: false, quickLookOpen: true)
        #expect(command(49, " ", [], open) == .quickLook)
    }

    @Test func commandLetters() {
        #expect(command(8, "c", .command) == .copy)
        #expect(command(8, "c", .command, .init(searchHasSelection: true)) == nil)
        #expect(command(35, "p", .command) == .togglePin)
        #expect(command(31, "o", .command) == .open)
        #expect(command(17, "t", .command) == .togglePause)
        #expect(command(3, "f", .command) == .focusSearch)
        #expect(command(51, nil, .command) == .delete)
        #expect(command(6, "z", .command) == .undo)
        #expect(command(6, "z", [.command, .shift]) == nil)
        #expect(command(13, "w", .command) == .close)
        #expect(command(16, "y", .command) == .openHistory)
        #expect(command(43, ",", .command) == .openSettings)
        #expect(command(48) == .toggleFocus)
        // Plain letters and ⌫ go to the search field.
        #expect(command(0, "a") == nil)
        #expect(command(51) == nil)
    }
}

// MARK: - Link titles and card text

@Suite struct CardTextTests {
    private func build(_ reps: [Representation]) throws -> Clip {
        try ClipBuilder.build(PasteboardSnapshot(items: [reps]), sourceBundleID: nil, sourceName: nil, now: now).get().0
    }

    private func rep(_ type: String, _ text: String) -> Representation {
        Representation(type: type, data: Data(text.utf8))
    }

    @Test func linkTitleFromURLName() throws {
        let clip = try build([rep(PasteboardType.string, "https://example.com/a"),
                              rep(PasteboardType.urlName, "  Example   Page ")])
        #expect(clip.kind == .link)
        #expect(clip.title == "Example Page")
        // The title is searchable.
        #expect(ClipSearch.run([clip], query: "example page").count == 1)
    }

    @Test func linkTitleFromASingleAnchor() throws {
        let clip = try build([rep(PasteboardType.string, "https://example.com/a"),
                              rep(PasteboardType.html, "<meta charset='utf-8'><a href=\"https://example.com/a\">Fish &amp; <b>Chips</b></a>")])
        #expect(clip.title == "Fish & Chips")
    }

    @Test func noTitleWhenItsJustTheURL() throws {
        let clip = try build([rep(PasteboardType.string, "https://example.com/a"),
                              rep(PasteboardType.html, "<a href=\"https://example.com/a\">https://example.com/a</a>")])
        #expect(clip.title == nil)
        let two = try build([rep(PasteboardType.string, "https://example.com/a"),
                             rep(PasteboardType.html, "<a href=x>One</a> <a href=y>Two</a>")])
        #expect(two.title == nil)
    }

    @Test func textNeverGetsATitle() throws {
        let clip = try build([rep(PasteboardType.string, "hello"), rep(PasteboardType.urlName, "Title")])
        #expect(clip.title == nil)
    }

    @Test func recopyKeepsTheTitle() throws {
        var history = History()
        history.record(try build([rep(PasteboardType.string, "https://example.com/a"), rep(PasteboardType.urlName, "Page")]))
        history.record(try build([rep(PasteboardType.string, "https://example.com/a")]))
        #expect(history.clips.count == 1)
        #expect(history.clips[0].title == "Page")
    }

    @Test func titleSurvivesTheDatabase() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clips-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        let clip = try build([rep(PasteboardType.string, "https://example.com/a"), rep(PasteboardType.urlName, "Page")])
        try await db.save(clip, payload: nil)
        #expect(try await db.loadAll() == [clip])
    }

    @Test func kindNamesAndFooters() throws {
        let text = try build([rep(PasteboardType.string, "hello world")])
        #expect(ClipText.kindName(of: text) == "Text")
        #expect(ClipText.cardFooter(of: text) == "11 characters")
        let one = try build([rep(PasteboardType.string, "x")])
        #expect(ClipText.cardFooter(of: one) == "1 character")
        let link = try build([rep(PasteboardType.string, "https://example.com")])
        #expect(ClipText.kindName(of: link) == "Link")
        #expect(ClipText.cardFooter(of: link) == nil)
        let image = Clip(kind: .image, text: "", imageWidth: 2_400, imageHeight: 1_600, created: now, fingerprint: "i")
        #expect(ClipText.cardFooter(of: image) == "\(2_400.formatted()) × \(1_600.formatted())")
        let files = Clip(kind: .file, text: "/tmp/a\n/tmp/b", created: now, fingerprint: "f")
        #expect(ClipText.kindName(of: files) == "2 Files")
    }

    @Test(arguments: [
        ("https://www.example.com/a/b", "example.com"),
        ("http://docs.example.org", "docs.example.org"),
        ("www.apple.com", "apple.com"),
        ("mailto:me@example.com", "me@example.com"),
    ])
    func hosts(input: String, host: String) {
        #expect(ClipText.host(ofLink: input) == host)
    }

    @Test func shortURLsAndMonograms() {
        #expect(ClipText.shortURL("https://www.example.com/a/") == "example.com/a")
        #expect(ClipText.monogram(ofHost: "example.com") == "E")
        #expect(ClipText.monogram(ofHost: "docs.swift.org") == "S")
        #expect(ClipText.stableHash("a") == ClipText.stableHash("a"))
        #expect(ClipText.stableHash("a") != ClipText.stableHash("b"))
    }
}

@Suite("Strip geometry")
struct StripGeometryTests {
    let geometry = StripGeometry(panelRadius: 24, inset: 12, controlHeight: 28, cardHeight: 216, ringOutset: 5, overflow: 8)

    @Test func insetsAreEvenAroundTheCards() {
        #expect(geometry.cardBottomGap == geometry.inset)
        // Top bar's controls end `inset` above the cards.
        #expect(geometry.cardTop - (geometry.inset + geometry.controlHeight) == geometry.inset)
        #expect(geometry.panelHeight == 280)
    }

    @Test func cardAndRingAreConcentricWithThePanel() {
        #expect(geometry.cardRadius == 12)
        // The ring is `ringOutset` outside the card, so its radius grows by the same amount.
        #expect(geometry.ringRadius == geometry.cardRadius + geometry.ringOutset)
    }

    @Test func overflowStaysBetweenTheRingAndTheInset() {
        #expect(StripGeometry(panelRadius: 24, inset: 12, controlHeight: 28, cardHeight: 216, ringOutset: 5).overflow == 5)
        #expect(StripGeometry(panelRadius: 24, inset: 12, controlHeight: 28, cardHeight: 216, ringOutset: 5, overflow: 30).overflow == 12)
    }

    @Test func nestedRadiusNeverVanishes() {
        var tight = geometry
        tight.panelRadius = 8
        #expect(tight.cardRadius == 2)
    }
}

@Suite("Card header colour")
struct HeaderColorTests {
    let green = RGB(52 / 255, 199 / 255, 89 / 255)     // a Messages-like green
    let blue = RGB(0, 122 / 255, 1)                     // a Safari/Mail-like blue
    let yellow = RGB(1, 204 / 255, 0)                   // a Notes-like yellow
    let red = RGB(1, 59 / 255, 48 / 255)

    @Test func whiteTypeAlwaysPasses() {
        let paleGreen = RGB(0.36, 0.83, 0.36)  // what a light app icon can average to
        for base in [green, blue, red, RGB.neutral, paleGreen] {
            for dark in [false, true] {
                let header = HeaderColor.resolve(base: base, darkMode: dark)
                #expect(header.ink == .light)
                #expect(HeaderColor.contrast(of: .light, on: header.fill) >= 4.5)
            }
        }
    }

    @Test func darkensOnlyAsMuchAsNeeded() {
        let header = HeaderColor.resolve(base: blue, darkMode: false)
        // One step lighter would fail.
        let lighter = header.fill.mixed(with: .white, 0.03)
        #expect(HeaderColor.contrast(of: .light, on: lighter) < 4.5 || header.fill == blue)
        #expect(header.fill.luminance > 0.1)
    }

    @Test func lightColoursKeepTheirColourWithDarkType() {
        let header = HeaderColor.resolve(base: yellow, darkMode: false)
        #expect(header.ink == .dark)
        #expect(header.fill == yellow)
        #expect(HeaderColor.contrast(of: .dark, on: header.fill) >= 4.5)
    }

    @Test func orangesAreNotDarkenedToBrown() {
        let orange = RGB(1, 149 / 255, 0)
        for dark in [false, true] {
            let header = HeaderColor.resolve(base: orange, darkMode: dark)
            #expect(header.ink == .dark)
            #expect(header.fill == orange)
        }
        // An orange a shade lighter than Photos' averages too (~0.48 luminance).
        let photosLike = RGB(0.94, 0.68, 0.24)
        for dark in [false, true] {
            #expect(HeaderColor.resolve(base: photosLike, darkMode: dark).ink == .dark)
        }
        let header = HeaderColor.resolve(base: orange, darkMode: false)
        #expect(HeaderColor.contrast(of: .dark, on: header.fill) >= 4.5)
        #expect(abs(orange.hue - 35.0 / 360) < 0.01)
    }

    @Test func darkModeIsDeeper() {
        let light = HeaderColor.resolve(base: green, darkMode: false)
        let dark = HeaderColor.resolve(base: green, darkMode: true)
        #expect(dark.fill.luminance <= light.fill.luminance)
    }

    @Test func contrastMaths() {
        #expect(abs(RGB.white.contrast(with: .black) - 21) < 0.01)
        #expect(abs(RGB.white.contrast(with: .white) - 1) < 0.0001)
    }
}

@Suite("Card text heading")
struct HeadingTests {
    @Test func colonOrShortTitleLine() {
        #expect(ClipText.headingLength(of: "Address:\n1 Infinite Loop") == 8)
        #expect(ClipText.headingLength(of: "Shopping list\nmilk\neggs") == 13)
    }

    @Test func notHeadings() {
        #expect(ClipText.headingLength(of: "One line only") == nil)
        #expect(ClipText.headingLength(of: "This is a sentence.\nAnother one.") == nil)
        #expect(ClipText.headingLength(of: "func greet(_ name: String) -> String {\n}") == nil)
        #expect(ClipText.headingLength(of: "Heading\n   \n") == nil)
        #expect(ClipText.headingLength(of: String(repeating: "long ", count: 12) + "\nbody") == nil)
    }
}
