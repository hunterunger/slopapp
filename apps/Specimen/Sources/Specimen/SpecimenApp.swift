import SlopKit
import SpecimenCore
import SwiftUI

// Archetype: library window (docs/design-system.md, 2c). Sidebar of filters and categories,
// a grid of every font in your own preview text, a detail page per family, and compare.

@main
struct SpecimenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Specimen")

    var body: some Scene {
        Window("Specimen", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
        .commands { SpecimenCommands(model: model, info: info) }

        Settings {
            SlopSettings(info: info, isMenuBarApp: false) {
                Toggle(isOn: Binding(get: { model.showSystemFonts }, set: { model.showSystemFonts = $0 })) {
                    Text("Show macOS fonts")
                    Text("Turn off to see only the fonts you added.")
                }
                Toggle(isOn: Binding(get: { model.groupByFamily }, set: { model.groupByFamily = $0 })) {
                    Text("Group styles into families")
                    Text("One card per family. Turn off for a card per style.")
                }
            }
        }
    }
}

struct SpecimenCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo

    private var detailFamily: String? {
        if case .detail(let name) = model.screen { return name }
        return nil
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Specimen") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tag…") { model.sheet = .newTag }
                .keyboardShortcut("n")
            Button("New Smart Collection…") { model.newSmartCollection() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Open…") { model.chooseDocumentToOpen() }
                .keyboardShortcut("o")
                .help("See the fonts a PDF, Illustrator, EPS, SVG, HTML, CSS or RTF file uses")
            Button("Add Folder to Library…") { model.chooseFolderToAdd() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Browse and activate a folder of fonts where it is, without copying it")
            Button("Install Fonts…") { model.chooseFontsToAdd() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(model.environment.stressCopies > 1)
                .help("Copy font files into your Fonts folder")
        }
        CommandGroup(after: .newItem) {
            Button("Show in Finder") { model.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.revealableURLs.isEmpty)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy PostScript Name") { model.copyNames(postScript: true) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.actionFaces.isEmpty)
            Divider()
            Button("Find") { WindowFocus.focusSearchField() }
                .keyboardShortcut("f")
            Button("Edit Preview Text") { model.focusPreviewRequest += 1 }
                .keyboardShortcut("l")
        }
        CommandGroup(before: .toolbar) {
            if case .detail = model.screen {
                ForEach(Array(DetailTab.allCases.enumerated()), id: \.element) { index, tab in
                    Toggle(tab.title, isOn: Binding(get: { model.detailTab == tab }, set: { _ in model.detailTab = tab }))
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                        .disabled(tab == .variables && !(model.family(named: detailFamily ?? "")?.isVariable ?? false))
                }
            } else {
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                    Toggle("as \(mode.title)", isOn: Binding(get: { model.viewMode == mode }, set: { _ in model.viewMode = mode }))
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            Menu("Sort By") {
                ForEach(LibrarySort.Key.allCases) { key in
                    Toggle(key.title, isOn: Binding(get: { model.sort.key == key }, set: { _ in model.sort = LibrarySort(key: key, ascending: model.sort.key == key ? model.sort.ascending : nil) }))
                }
                Divider()
                Toggle("Ascending", isOn: Binding(get: { model.sort.ascending }, set: { model.sort = LibrarySort(key: model.sort.key, ascending: $0) }))
                Toggle("Descending", isOn: Binding(get: { !model.sort.ascending }, set: { model.sort = LibrarySort(key: model.sort.key, ascending: !$0) }))
            }
            Divider()
            Button("Bigger") { model.biggerPreview() }
                .keyboardShortcut("+")
                .disabled(model.previewSize >= PreviewSize.range.upperBound)
            Button("Smaller") { model.smallerPreview() }
                .keyboardShortcut("-")
                .disabled(model.previewSize <= PreviewSize.range.lowerBound)
            Button("Actual Size") { model.actualSizePreview() }
                .keyboardShortcut("0")
            Divider()
            Toggle("Show macOS Fonts", isOn: $model.showSystemFonts)
            Toggle("Group Styles into Families", isOn: $model.groupByFamily)
            Toggle("Hide Fonts That Can’t Show This Text", isOn: $model.hideUncovered)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Menu("Go To") {
                ForEach(LibraryFilter.countedItems(tags: model.tags, smartCollections: model.smartCollections), id: \.self) { item in
                    Button(model.title(for: item)) {
                        model.sidebar = item
                        model.screen = .grid
                    }
                }
            }
            Divider()
        }
        CommandMenu("Font") {
            Button("Show Details") { model.openDetail() }
                .keyboardShortcut(.downArrow)
                .disabled(model.screen != .grid || model.selection.isEmpty)
            Button("Back to All Fonts") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(model.screen == .grid)
            Button(model.selectionIsInTray ? "Remove from Compare" : "Add to Compare") { model.toggleTraySelection() }
                .disabled(model.screen != .grid || model.selection.isEmpty)
            Button("Compare") { model.openCompare() }
                .keyboardShortcut("k")
                .disabled(!model.canCompare)
            Button("Clear Compare") { model.clearTray() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(model.tray.isEmpty)
            Divider()
            Button(model.allActionFamiliesAreFavorites ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite() }
                .keyboardShortcut("d")
                .disabled(model.actionFamilies.isEmpty)
            Button("Tags…") { model.sheet = .tags }
                .keyboardShortcut("t")
                .disabled(model.actionFamilies.isEmpty)
            Menu("Tags") {
                let names = model.actionFamilies
                ForEach(model.tags.names, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(get: { model.tags.membership(tag, families: names) == .all },
                                              set: { _ in model.toggleTag(tag, families: names) }))
                }
                if !model.tags.isEmpty { Divider() }
                Button("New Tag…") { model.sheet = .newTag }
            }
            .disabled(model.actionFamilies.isEmpty)
            Menu("Category") {
                let names = model.actionFamilies
                let current = Set(names.compactMap(model.category(ofFamily:)))
                ForEach(FontCategory.allCases) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { current == [category] },
                        set: { _ in model.setCategory(category, families: names) }
                    ))
                }
                Divider()
                Button("Automatic") { model.setCategory(nil, families: names) }
                    .disabled(!names.contains(where: model.hasCategoryOverride))
            }
            .disabled(model.actionFamilies.isEmpty)
            Divider()
            Button("Activate") { model.activate(true) }
                .keyboardShortcut(";")
                .disabled(!model.canActivate || model.isChangingFonts)
            Button("Activate Temporarily") { model.activate(true, temporary: true) }
                .keyboardShortcut(";", modifiers: [.command, .option])
                .disabled(!model.canActivateTemporarily || model.isChangingFonts)
            Button("Deactivate") { model.activate(false) }
                .keyboardShortcut(";", modifiers: [.command, .shift])
                .disabled(!model.canDeactivate || model.isChangingFonts)
            Divider()
            Button("Deactivate Temporary Fonts") { model.deactivateTemporaryFonts() }
                .disabled(model.temporaryFaces.isEmpty || model.isChangingFonts)
        }
        HelpCommands(info: info) {
            Button("Specimen Help") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Specimen"))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["SPECIMEN_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        Snapshots.startIfAsked(model: AppModel.shared)
        if let kind = AppModel.shared.environment.benchmark {
            Benchmark.run(kind, model: AppModel.shared)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Temporary activations end when Specimen quits.
        AppModel.shared.endTemporaryActivations()
        AppModel.shared.cleanUpTestFonts()
    }

    /// Documents (and folders) opened from Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        if model.hasLoaded {
            _ = model.handleDrop(urls)
        } else {
            Task {
                while !model.hasLoaded { try? await Task.sleep(for: .milliseconds(50)) }
                _ = model.handleDrop(urls)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }
}

/// Puts the cursor in the toolbar's search field (Edit ▸ Find).
@MainActor
enum WindowFocus {
    static func focusSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
              let root = window.contentView?.superview, let field = searchField(in: root) else { return }
        window.makeFirstResponder(field)
    }

    private static func searchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }
}
