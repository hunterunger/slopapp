import AppKit
import SlopappCore
import SlopKit
import SwiftUI

// Archetype: library window (sidebar Discover / Installed / Updates / Also Great) plus a
// menu bar extra. See docs/design-system.md, section 2c and 2a.

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
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            SidebarCommands()
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

/// The sidebar section, the open detail page and the search text, shared by the window,
/// the menus and the menu bar extra.
@MainActor
@Observable
final class Navigation {
    static let shared = Navigation()

    enum Section: String, CaseIterable, Identifiable {
        case discover, installed, updates, alsoGreat
        var id: String { rawValue }

        var title: String {
            switch self {
            case .discover: "Discover"
            case .installed: "Installed"
            case .updates: "Updates"
            case .alsoGreat: "Also Great"
            }
        }

        var symbol: String {
            switch self {
            case .discover: "square.grid.2x2"
            case .installed: "checkmark.circle"
            case .updates: "arrow.down.circle"
            case .alsoGreat: "heart"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .discover: "1"
            case .installed: "2"
            case .updates: "3"
            case .alsoGreat: "4"
            }
        }
    }

    var section: Section? = .discover {
        didSet { if oldValue != section { path = []; selection = nil } }
    }
    /// Slugs of pushed detail pages.
    var path: [String] = []
    var search = "" {
        didSet { if oldValue != search { selection = nil } }
    }
    /// The highlighted app in a list or grid (keyboard selection). Menu commands act on the
    /// open detail page first, then on this.
    var selection: String?

    /// The app that Apps-menu commands act on.
    var current: String? { path.last ?? selection }

    func show(_ section: Section) {
        self.section = section
        path = []
        search = ""
        selection = nil
    }

    func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    func showDetail(_ slug: String) {
        if path.last != slug { path.append(slug) }
    }

    /// ⌘F: put the cursor in the toolbar search field.
    func focusSearch() {
        bringWindowForward()
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }
            let search = window?.toolbar?.items.lazy.compactMap { $0 as? NSSearchToolbarItem }.first
            search?.beginSearchInteraction()
        }
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
            ForEach(Navigation.Section.allCases) { section in
                Button(section.title) { navigation.show(section) }
                    .keyboardShortcut(section.shortcut)
            }
            Divider()
            Button("Back") { navigation.goBack() }
                .keyboardShortcut("[")
                .disabled(navigation.path.isEmpty)
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
                .disabled(current == nil || navigation.path.last == current?.id)
            Button("Reveal in Finder") { if let current { store.reveal(current) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(current?.primary == nil)
            Button("Reinstall") { if let current { store.reinstall(current) } }
                .disabled(current.map { !canReinstall($0) } ?? true)
            Button("Move to Trash…") { if let current { store.requestUninstall(current) } }
                .keyboardShortcut(.delete)
                .disabled(current?.primary?.location.canModify != true)
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
