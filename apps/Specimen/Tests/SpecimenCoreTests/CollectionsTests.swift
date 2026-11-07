import Foundation
import Testing
@testable import SpecimenCore

@Suite struct TagTests {
    @Test func createRenameDeleteIgnoringCase() {
        var tags = TagLibrary()
        let first = tags.create("  Client   work ")
        let again = tags.create("client WORK")
        let blank = tags.create("   ")
        #expect(first == "Client work")
        #expect(again == "Client work")
        #expect(blank == nil)
        #expect(tags.unusedName() == "New Tag")
        tags.create("New Tag")
        #expect(tags.unusedName() == "New Tag 2")
        let renamed = tags.rename("New Tag", to: "Headlines")
        let clash = tags.rename("Headlines", to: "client work")
        let recased = tags.rename("Headlines", to: "headlines")
        #expect(renamed && !clash && recased)
        #expect(tags.names == ["Client work", "headlines"])
        tags.delete("headlines")
        #expect(tags.names == ["Client work"])
    }

    @Test func attachDetachAndMembership() {
        var tags = TagLibrary()
        tags.attach("Logo", to: ["Avenir", "Didot"])
        tags.attach("Body", to: ["Didot"])
        #expect(tags.tags(of: "Didot") == ["Body", "Logo"])
        #expect(tags.membership("Logo", families: ["Avenir", "Didot"]) == .all)
        #expect(tags.membership("Body", families: ["Avenir", "Didot"]) == .some)
        #expect(tags.membership("Body", families: ["Avenir"]) == .none)
        tags.detach("Logo", from: ["Avenir"])
        #expect(tags.families(in: "Logo") == ["Didot"])
        // Renaming keeps members.
        tags.rename("Logo", to: "Logos")
        #expect(tags.families(in: "Logos") == ["Didot"])
    }

    @Test func storeRoundTripAndDamagedFile() throws {
        let dir = temporaryDirectory()
        let store = CollectionsStore(directory: dir)
        #expect(store.load() == CollectionsStore.Contents())
        var tags = TagLibrary()
        tags.attach("Logo", to: ["Avenir"])
        let smart = SmartCollection(name: "Mono I own", rules: SmartRules(category: .monospaced, source: .yours))
        try store.save(CollectionsStore.Contents(tags: tags, smartCollections: [smart]))
        let loaded = store.load()
        #expect(loaded.tagLibrary == tags)
        #expect(loaded.smartCollections == [smart])
        try Data("{broken".utf8).write(to: store.url)
        #expect(store.load() == CollectionsStore.Contents())
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("collections.damaged.json").path))
    }

    @Test func sidebarStorageKeys() {
        let id = UUID()
        for item: SidebarItem in [.all, .userFonts, .systemFonts, .variable, .category(.script), .tag("Client work"), .smart(id)] {
            #expect(SidebarItem(storageKey: item.storageKey) == item)
        }
    }
}

@Suite struct CollectionFilterTests {
    let families = FontFamily.group([
        face("Avenir-Roman", family: "Avenir"),
        face("Avenir-Bold", family: "Avenir", style: "Bold", weight: 0.4),
        face("Didot", family: "Didot", path: "/System/Library/Fonts/Supplemental/Didot.ttc", category: .serif),
        face("FiraCode-Regular", family: "Fira Code", enabled: false, category: .monospaced, variable: true),
        face("Menlo-Regular", family: "Menlo", path: "/System/Library/Fonts/Menlo.ttc", category: .monospaced),
    ])

    func names(_ query: LibraryQuery) -> [String] {
        LibraryFilter.items(in: families, query: query).map(\.family.name)
    }

    @Test func tagSidebarItem() {
        var tags = TagLibrary()
        tags.attach("Logo", to: ["Didot", "Fira Code"])
        #expect(names(LibraryQuery(sidebar: .tag("Logo"), tags: tags)) == ["Didot", "Fira Code"])
        #expect(names(LibraryQuery(sidebar: .tag("Missing"), tags: tags)).isEmpty)
        #expect(LibraryFilter.counts(in: families, query: LibraryQuery(tags: tags))[.tag("Logo")] == 2)
    }

    @Test func locationSidebarItems() {
        #expect(names(LibraryQuery(sidebar: .userFonts)) == ["Avenir", "Fira Code"])
        #expect(names(LibraryQuery(sidebar: .systemFonts)) == ["Didot", "Menlo"])
    }

    @Test func smartCollections() {
        var tags = TagLibrary()
        tags.attach("Code", to: ["Menlo"])
        let mono = SmartCollection(name: "My mono", rules: SmartRules(category: .monospaced, source: .yours))
        let active = SmartCollection(name: "Active mono", rules: SmartRules(category: .monospaced, state: .active))
        let tagged = SmartCollection(name: "Tagged", rules: SmartRules(tag: "Code"))
        let named = SmartCollection(name: "Named", rules: SmartRules(nameContains: "bold"))
        let big = SmartCollection(name: "Big", rules: SmartRules(minimumStyles: 2))
        let all = [mono, active, tagged, named, big]
        func smart(_ c: SmartCollection, search: String = "") -> [String] {
            names(LibraryQuery(sidebar: .smart(c.id), search: search, tags: tags, smartCollections: all))
        }
        #expect(smart(mono) == ["Fira Code"])
        #expect(smart(active) == ["Menlo"])
        #expect(smart(tagged) == ["Menlo"])
        #expect(smart(named) == ["Avenir"])
        #expect(LibraryFilter.items(in: families, query: LibraryQuery(sidebar: .smart(named.id), smartCollections: all)).first?.faces.count == 1)
        #expect(smart(big) == ["Avenir"])
        #expect(smart(mono, search: "menlo").isEmpty)
        #expect(names(LibraryQuery(sidebar: .smart(UUID()), smartCollections: all)).isEmpty)
        let counts = LibraryFilter.counts(in: families, query: LibraryQuery(tags: tags, smartCollections: all))
        #expect(counts[.smart(mono.id)] == 1)
    }

    @Test func rulesFromCurrentFilters() {
        let rules = SmartRules(sidebar: .category(.serif), search: " didot ")
        #expect(rules.category == .serif)
        #expect(rules.nameContains == "didot")
        #expect(SmartRules(sidebar: .inactive, search: "").state == .inactive)
        #expect(SmartRules(sidebar: .systemFonts, search: "").source == .macOS)
        #expect(rules.summary == "Serif · name contains “didot”")
        #expect(SmartRules().summary == "Every font")
    }

    @Test func hiddenFacesDropFromCardsAndPickNewRepresentative() throws {
        let roman = try #require(families.first?.faces.first { $0.styleName == "Regular" })
        let didot = try #require(families.first { $0.name == "Didot" }?.faces.first)
        let items = LibraryFilter.items(in: families, query: LibraryQuery(hiddenFaceIDs: [roman.id, didot.id]))
        #expect(items.first { $0.family.name == "Avenir" }?.representative.styleName == "Bold")
        #expect(!items.contains { $0.family.name == "Didot" })
        // Counts ignore coverage, like search.
        #expect(LibraryFilter.counts(in: families, query: LibraryQuery(hiddenFaceIDs: [didot.id]))[.all] == 4)
    }

    @Test func sortOrders() {
        var dated = families
        dated[0].faces[0].fileModified = Date(timeIntervalSince1970: 300)   // Avenir
        #expect(dated[2].name == "Fira Code")
        dated[2].faces[0].fileModified = Date(timeIntervalSince1970: 500)
        dated[2].faces[0].foundry = "Zed Type"
        dated[0].faces[0].foundry = "Linotype"
        func order(_ sort: LibrarySort) -> [String] {
            LibraryFilter.items(in: dated, query: LibraryQuery(sort: sort)).map(\.family.name)
        }
        #expect(order(LibrarySort()) == ["Avenir", "Didot", "Fira Code", "Menlo"])
        #expect(order(LibrarySort(key: .name, ascending: false)) == ["Menlo", "Fira Code", "Didot", "Avenir"])
        #expect(order(LibrarySort(key: .recentlyAdded)) == ["Fira Code", "Avenir", "Didot", "Menlo"])
        #expect(order(LibrarySort(key: .styles)).first == "Avenir")
        #expect(order(LibrarySort(key: .category)) == ["Didot", "Avenir", "Fira Code", "Menlo"])
        #expect(order(LibrarySort(key: .foundry)) == ["Avenir", "Fira Code", "Didot", "Menlo"])
        #expect(order(LibrarySort(key: .foundry, ascending: false)) == ["Fira Code", "Avenir", "Didot", "Menlo"])
    }

    @Test func sortChoosingFlipsAndPersists() {
        let sort = LibrarySort()
        #expect(sort.choosing(.name) == LibrarySort(key: .name, ascending: false))
        #expect(sort.choosing(.recentlyAdded) == LibrarySort(key: .recentlyAdded, ascending: false))
        #expect(LibrarySort(storageKey: LibrarySort(key: .styles).storageKey) == LibrarySort(key: .styles))
        #expect(LibrarySort(storageKey: "nonsense") == nil)
    }

    @Test func familyFacts() throws {
        let avenir = try #require(families.first)
        #expect(avenir.weightRange == 400...700)
        #expect(FontFace.cssWeight(fromTrait: -0.4) == 300)
        #expect(FontFace.cssWeight(fromTrait: 0.62) == 900)
        #expect(FontFormat.shortVersion("Version 1.000;PS 001.000;hotconv 1.0.38") == "1.000")
        #expect(FontFormat.shortVersion("13.0d1e3") == "13.0d1e3")
    }
}

@Suite struct CompareTrayTests {
    @Test func toggleCardsAndKeepOrder() {
        var tray = CompareTray()
        tray.toggle(cardFaceIDs: ["a1", "a2"], representative: "a1")
        tray.toggle(cardFaceIDs: ["b1"], representative: "b1")
        #expect(tray.faceIDs == ["a1", "b1"])
        // A card whose family is in (any style) toggles out.
        tray.replace("a1", with: "a2")
        #expect(tray.containsAny(["a1", "a2"]))
        tray.toggle(cardFaceIDs: ["a1", "a2"], representative: "a1")
        #expect(tray.faceIDs == ["b1"])
    }

    @Test func toggleSeveral() {
        var tray = CompareTray(faceIDs: ["a", "a", "b"])
        #expect(tray.faceIDs == ["a", "b"])
        tray.toggle(cards: [(["a"], "a"), (["c"], "c")])
        #expect(tray.faceIDs == ["a", "b", "c"])
        tray.toggle(cards: [(["a"], "a"), (["c"], "c")])
        #expect(tray.faceIDs == ["b"])
    }

    @Test func replaceMovePrune() {
        var tray = CompareTray(faceIDs: ["a", "b", "c"])
        tray.replace("b", with: "c")
        #expect(tray.faceIDs == ["a", "c"])
        tray = CompareTray(faceIDs: ["a", "b", "c"])
        tray.move(from: [2], to: 0)
        #expect(tray.faceIDs == ["c", "a", "b"])
        tray.move(from: [0], to: 3)
        #expect(tray.faceIDs == ["a", "b", "c"])
        tray.prune(existing: ["a", "c"])
        #expect(tray.faceIDs == ["a", "c"])
        tray.removeAll()
        #expect(tray.isEmpty)
    }
}
