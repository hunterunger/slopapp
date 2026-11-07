import SlopappCore
import Testing

@Suite("Sidebar order")
struct SidebarOrderTests {
    let categories = ["Utilities", "Media"]

    @Test("Main pages, then All Apps and its categories, then Updates last")
    func order() {
        #expect(SidebarItem.order(categories: categories) == [
            .discover, .installed, .favorites, .allApps, .category("Utilities"), .category("Media"), .updates,
        ])
        #expect(SidebarItem.order(categories: []).last == .updates)
    }

    @Test("Arrow keys move one row and stop at the ends")
    func moves() {
        #expect(SidebarItem.moved(from: .discover, by: 1, categories: categories) == .installed)
        #expect(SidebarItem.moved(from: .allApps, by: 1, categories: categories) == .category("Utilities"))
        #expect(SidebarItem.moved(from: .category("Media"), by: 1, categories: categories) == .updates)
        #expect(SidebarItem.moved(from: .updates, by: 1, categories: categories) == .updates)
        #expect(SidebarItem.moved(from: .discover, by: -1, categories: categories) == .discover)
        #expect(SidebarItem.moved(from: .updates, by: -1, categories: categories) == .category("Media"))
    }

    @Test("Nothing selected, or a category that's gone: down starts at the top, up at the bottom")
    func fromNothing() {
        #expect(SidebarItem.moved(from: nil, by: 1, categories: categories) == .discover)
        #expect(SidebarItem.moved(from: nil, by: -1, categories: categories) == .updates)
        #expect(SidebarItem.moved(from: .category("Gone"), by: 1, categories: categories) == .discover)
    }

    @Test("Categories have no icon and are indented; pages have filled glyphs")
    func glyphs() {
        #expect(SidebarItem.category("Media").symbol == nil)
        #expect(SidebarItem.category("Media").isCategory)
        #expect(!SidebarItem.allApps.isCategory)
        for item in SidebarItem.top + [.allApps, .updates] {
            #expect(item.symbol?.hasSuffix(".fill") == true)
        }
        #expect(SidebarItem.category("Media").id != SidebarItem.allApps.id)
    }
}

@Suite("Header status")
struct HeaderStatusTests {
    @Test("Checking wins, then updates, then errors, then up to date")
    func priority() {
        #expect(HeaderStatus(updates: 2, isChecking: true, hasError: true, hasCatalog: true).kind == .checking)
        #expect(HeaderStatus(updates: 2, isChecking: false, hasError: true, hasCatalog: true).kind == .updates)
        #expect(HeaderStatus(updates: 0, isChecking: false, hasError: true, hasCatalog: true).kind == .offline)
        #expect(HeaderStatus(updates: 0, isChecking: false, hasError: false, hasCatalog: true).kind == .upToDate)
        #expect(HeaderStatus(updates: 0, isChecking: false, hasError: false, hasCatalog: false).kind == .unknown)
    }

    @Test("Counts read naturally")
    func titles() {
        #expect(HeaderStatus(updates: 1, isChecking: false, hasError: false, hasCatalog: true).title == "1 Update")
        #expect(HeaderStatus(updates: 3, isChecking: false, hasError: false, hasCatalog: true).title == "3 Updates")
        #expect(HeaderStatus(updates: 0, isChecking: false, hasError: false, hasCatalog: true).title == "Up to Date")
        #expect(HeaderStatus(updates: 0, isChecking: true, hasError: false, hasCatalog: true).symbol == nil)
    }
}
