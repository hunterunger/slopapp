import Foundation
import Testing
@testable import SpecimenCore

@Suite struct LibraryTests {
    let faces: [FontFace] = [
        face("Avenir-Bold", family: "Avenir", style: "Bold", weight: 0.4),
        face("Avenir-Book", family: "Avenir", style: "Book", weight: -0.1),
        face("Avenir-Oblique", family: "Avenir", style: "Oblique", italic: true),
        face("Avenir-Roman", family: "Avenir", style: "Roman"),
        face("Didot", family: "Didot", path: "/System/Library/Fonts/Supplemental/Didot.ttc", category: .serif),
        face("Didot-Bold", family: "Didot", style: "Bold", path: "/System/Library/Fonts/Supplemental/Didot.ttc", weight: 0.4, category: .serif),
        face("FiraCode-Regular", family: "Fira Code", enabled: false, category: .monospaced, variable: true),
        face("Cafe-Regular", family: "Café Script", category: .script),
    ]

    var families: [FontFamily] { FontFamily.group(faces) }

    @Test func groupsSortsAndPicksRegular() throws {
        #expect(families.map(\.name) == ["Avenir", "Café Script", "Didot", "Fira Code"])
        let avenir = try #require(families.first)
        #expect(avenir.faces.map(\.styleName) == ["Book", "Roman", "Oblique", "Bold"])
        #expect(avenir.representative?.styleName == "Roman")
        #expect(avenir.category == .sansSerif)
    }

    @Test func representativeFollowsFilters() throws {
        let items = LibraryFilter.items(in: families, query: LibraryQuery(search: "bold"))
        let avenir = try #require(items.first { $0.family.name == "Avenir" })
        #expect(avenir.representative.styleName == "Bold")
        #expect(avenir.faces.count == 1)
    }

    @Test func familyNameMatchKeepsAllStyles() throws {
        let items = LibraryFilter.items(in: families, query: LibraryQuery(search: "AVENIR"))
        #expect(items.count == 1)
        #expect(items[0].faces.count == 4)
        #expect(items[0].representative.styleName == "Roman")
    }

    @Test func searchIgnoresCaseAndDiacriticsAndMatchesAllWords() {
        #expect(LibraryFilter.items(in: families, query: LibraryQuery(search: "cafe")).map(\.family.name) == ["Café Script"])
        #expect(LibraryFilter.items(in: families, query: LibraryQuery(search: "didot bold")).first?.faces.map(\.styleName) == ["Bold"])
        #expect(LibraryFilter.items(in: families, query: LibraryQuery(search: "FiraCode-Regular")).count == 1)
        #expect(LibraryFilter.items(in: families, query: LibraryQuery(search: "nothing like this")).isEmpty)
    }

    @Test func sidebarFilters() {
        func names(_ item: SidebarItem, favorites: Set<String> = []) -> [String] {
            LibraryFilter.items(in: families, query: LibraryQuery(sidebar: item, favorites: favorites)).map(\.family.name)
        }
        #expect(names(.all).count == 4)
        #expect(names(.favorites, favorites: ["Didot"]) == ["Didot"])
        #expect(names(.favorites).isEmpty)
        #expect(names(.active) == ["Avenir", "Café Script", "Didot"])
        #expect(names(.inactive) == ["Fira Code"])
        #expect(names(.variable) == ["Fira Code"])
        #expect(names(.category(.serif)) == ["Didot"])
        #expect(names(.category(.symbol)).isEmpty)
    }

    @Test func hidesSystemFonts() {
        let items = LibraryFilter.items(in: families, query: LibraryQuery(showSystemFonts: false))
        #expect(!items.contains { $0.family.name == "Didot" })
        #expect(families.first { $0.name == "Didot" }?.isSystem == true)
    }

    @Test func ungroupedShowsEveryFace() {
        let items = LibraryFilter.items(in: families, query: LibraryQuery(groupByFamily: false))
        #expect(items.count == faces.count)
        #expect(Set(items.map(\.id)).count == faces.count)
        #expect(items.first { $0.representative.styleName == "Bold" && $0.family.name == "Avenir" }?.title == "Avenir Bold")
    }

    @Test func countsIgnoreSearch() {
        let counts = LibraryFilter.counts(in: families, query: LibraryQuery(search: "zzz", favorites: ["Avenir"]))
        #expect(counts[.all] == 4)
        #expect(counts[.favorites] == 1)
        #expect(counts[.inactive] == 1)
        #expect(counts[.category(.monospaced)] == 1)
    }

    @Test func mixedFamilyState() {
        let family = FontFamily(name: "X", faces: [face("X-A", family: "X"), face("X-B", family: "X", enabled: false)])
        #expect(family.state == .mixed)
        #expect(FontFamily(name: "Y", faces: [face("Y", family: "Y", enabled: false)]).state == .inactive)
    }

    @Test func categoryOverrideWins() {
        let grouped = FontFamily.group(faces, overrides: ["Avenir": .display])
        #expect(grouped.first { $0.name == "Avenir" }?.category == .display)
    }

    @Test func typeAhead() {
        let titles = ["Arial", "Avenir", "Baskerville", "Courier", "Zapfino"]
        #expect(LibraryFilter.typeAheadIndex("av", in: titles) == 1)
        #expect(LibraryFilter.typeAheadIndex("b", in: titles) == 2)
        #expect(LibraryFilter.typeAheadIndex("bz", in: titles) == 3)   // nearest after
        #expect(LibraryFilter.typeAheadIndex("zz", in: titles) == 4)
        #expect(LibraryFilter.typeAheadIndex("", in: titles) == nil)
    }

    @Test func sidebarStorageKeysRoundTrip() {
        for item in SidebarItem.libraryItems + SidebarItem.categoryItems {
            #expect(SidebarItem(storageKey: item.storageKey) == item)
        }
        #expect(SidebarItem(storageKey: "bogus") == nil)
    }

    @Test func locations() {
        #expect(FontLocation(path: "/System/Library/Fonts/Helvetica.ttc") == .system)
        #expect(FontLocation(path: "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/x.ttc") == .system)
        #expect(FontLocation(path: "/Library/Fonts/Arial Unicode.ttf") == .computer)
        #expect(FontLocation(path: "/Users/me/Library/Fonts/A.otf", home: "/Users/me") == .user)
        #expect(FontLocation(path: "/tmp/specimen-test/A.ttf") == .other)
        #expect(FontLocation(path: nil) == .system)
    }
}
