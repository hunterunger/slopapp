import AppKit
import SlopappCore
import SlopKit
import SwiftUI

// Archetype: library window plus a menu bar extra (docs/design-system.md 2c and 2a), laid
// out like the original's store window: sidebar (Discover, Installed, Updates, Favorites,
// All Apps + categories), Back/Forward, card grids, app pages. See docs/research/slopapp.md.

@main
struct SlopappApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var store = Store.shared
    @State private var navigation = Navigation.shared
    private let info = AppInfo.current(fallbackName: "Slopapp")

    var body: some Scene {
        Window("Slopapp", id: WindowID.main) {
            MainWindow(store: store, navigation: navigation)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 720)
        // The content runs to the top of the window (see storeWindowChrome()).
        .windowStyle(.hiddenTitleBar)
        .commands {
            SlopappCommands(store: store, navigation: navigation, info: info)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarMenu(store: store, navigation: navigation, info: info)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: store, info: info)
        }
    }
}

enum WindowID {
    static let main = "main"
}

/// The sidebar section, the open app pages and the search text, shared by the window, the
/// menus and the menu bar extra.
@MainActor
@Observable
final class Navigation {
    static let shared = Navigation()

    /// Sidebar rows (`SlopappCore.SidebarItem`): the main pages, All Apps with its
    /// categories, Updates last.
    typealias Section = SidebarItem

    /// Every page visited, with Back/Forward (sidebar pages and app pages alike).
    private(set) var history = PageHistory()
    /// The sidebar page showing.
    var section: Section { history.current.section }
    /// The open app page, if any (it sits on top of the sidebar page).
    var detail: String? { history.current.app }
    var search = "" {
        // Typing shows the results, even from an app page (Back returns to it).
        didSet {
            guard oldValue != search else { return }
            selection = nil
            if detail != nil, !search.trimmingCharacters(in: .whitespaces).isEmpty {
                history.go(to: Page(section))
            }
        }
    }
    /// The highlighted app in a grid (keyboard selection). Menu commands act on the open
    /// app page first, then on this.
    var selection: String?
    /// Chips and sort on All Apps and category pages (kept while you move between them).
    var filter: CatalogFilter = .all
    var sort: CatalogSort = .featured

    /// The app that Apps-menu commands act on.
    var current: String? { detail ?? selection }

    func show(_ section: Section) {
        search = ""
        visit(Page(section))
    }

    func goBack() { move { $0.back() } }
    func goForward() { move { $0.forward() } }

    func showDetail(_ slug: String) {
        visit(Page(section, app: slug))
    }

    private func visit(_ page: Page) {
        move { $0.go(to: page) }
    }

    /// A grid's highlight belongs to its page: moving to another sidebar page drops it.
    private func move(_ change: (inout PageHistory) -> Void) {
        let before = history.current.section
        change(&history)
        if history.current.section != before { selection = nil }
    }

    /// Bumped by ⌘F; the content header's search field takes focus when it changes.
    private(set) var searchFocusRequest = 0

    /// ⌘F: put the cursor in the search field at the top of the content.
    func focusSearch() {
        bringWindowForward()
        DispatchQueue.main.async { self.searchFocusRequest += 1 }
    }

    /// The window title (Window menu, VoiceOver): the open app page, else the page.
    func windowTitle(appName: (String) -> String?) -> String {
        if let slug = detail, let name = appName(slug) { return name }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { return "Search" }
        return section.title
    }

    /// Opens the library window (it may be closed while the menu bar item lives on).
    var openWindow: (() -> Void)?

    func bringWindowForward() {
        NSApp.setActivationPolicy(.regular)
        openWindow?()
        NSApp.activate()
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }?.makeKeyAndOrderFront(nil)
        }
    }
}

extension SidebarItem {
    /// View menu order: by shortcut (⌘1–⌘5), which keeps Updates on ⌘3 even though its
    /// sidebar row is last.
    static let menuOrder: [SidebarItem] = [.discover, .installed, .updates, .favorites, .allApps]

    var shortcut: KeyEquivalent? {
        switch self {
        case .discover: "1"
        case .installed: "2"
        case .updates: "3"
        case .favorites: "4"
        case .allApps: "5"
        case .category: nil
        }
    }
}

struct SlopappCommands: Commands {
    let store: Store
    let navigation: Navigation
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Slopapp") { HubAboutWindow.show(info: info) }
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates") { Task { await store.refresh() } }
                .keyboardShortcut("r")
                .disabled(store.isChecking)
        }
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .textEditing) {
            Button("Find…") { navigation.focusSearch() }
                .keyboardShortcut("f")
        }
        CommandGroup(before: .sidebar) {
            ForEach(Navigation.Section.menuOrder) { section in
                Button(section.title) { navigation.show(section) }
                    .keyboardShortcut(section.shortcut.map { KeyboardShortcut($0) })
            }
            Menu("Categories") {
                ForEach(store.categories, id: \.self) { name in
                    Button(name) { navigation.show(.category(name)) }
                }
            }
            .disabled(store.categories.isEmpty)
            Divider()
            Button("Back") { navigation.goBack() }
                .keyboardShortcut("[")
                .disabled(!navigation.history.canGoBack)
            Button("Forward") { navigation.goForward() }
                .keyboardShortcut("]")
                .disabled(!navigation.history.canGoForward)
            Divider()
        }
        CommandMenu("Apps") {
            let current = navigation.current.flatMap(store.item)
            Button(current.map { primaryTitle(for: $0) } ?? "Install") {
                if let current { primaryAction(for: current) }
            }
            .keyboardShortcut("o")
            .disabled(current == nil || current?.state == .comingSoon || current.map { store.operations[$0.id] != nil } ?? true)
            Button("Show Details") { if let current { navigation.showDetail(current.id) } }
                .keyboardShortcut(.downArrow)
                .disabled(current == nil || navigation.detail == current?.id)
            Button("Reveal in Finder") { if let current { store.reveal(current) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(current?.primary == nil)
            Button("Reinstall") { if let current { store.reinstall(current) } }
                .disabled(current.map { !canReinstall($0) } ?? true)
            Button("Move to Trash…") { if let current { store.requestUninstall(current) } }
                .keyboardShortcut(.delete)
                .disabled(current?.primary?.location.canModify != true)
            Divider()
            Button(current.map { store.isFavorite($0) } == true ? "Remove from Favorites" : "Add to Favorites") {
                if let current { store.toggleFavorite(current) }
            }
            .keyboardShortcut("d")
            .disabled(current == nil)
            Divider()
            Button(store.updates.isEmpty ? "Update All" : "Update All (\(store.updates.count))") { store.updateAll() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(store.updates.isEmpty)
        }
        CommandGroup(replacing: .help) {
            Link("Slopapp on GitHub", destination: Brand.repoURL)
            Link("Report an Issue", destination: Brand.repoURL.appendingPathComponent("issues"))
        }
    }

    private func canReinstall(_ item: CatalogItem) -> Bool {
        item.state == .installed && item.app.isInstallable && item.primary?.location.canModify == true
            && store.operations[item.id] == nil
    }

    private func primaryTitle(for item: CatalogItem) -> String {
        switch item.state {
        case .notInstalled: "Install \(item.app.name)"
        case .updateAvailable: "Update \(item.app.name)"
        case .installed: "Open \(item.app.name)"
        case .comingSoon: "Coming Soon"
        }
    }

    private func primaryAction(for item: CatalogItem) {
        switch item.state {
        case .notInstalled, .updateAvailable: store.installOrUpdate(item)
        case .installed: store.open(item)
        case .comingSoon: break
        }
    }
}
