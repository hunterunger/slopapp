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
                Toggle("Show macOS fonts", isOn: Binding(get: { model.showSystemFonts }, set: { model.showSystemFonts = $0 }))
                Toggle("Group styles into families", isOn: Binding(get: { model.groupByFamily }, set: { model.groupByFamily = $0 }))
                Text("Fonts that come with macOS can be hidden to see only the ones you added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SpecimenCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Specimen") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {}
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
            Divider()
            Menu("Go To") {
                ForEach(SidebarItem.libraryItems + SidebarItem.categoryItems, id: \.self) { item in
                    Button(item.title) {
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
            Button("Compare") { model.openCompare() }
                .keyboardShortcut("k")
                .disabled(!model.canCompare)
            Divider()
            Button(model.allActionFamiliesAreFavorites ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite() }
                .keyboardShortcut("d")
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
            Button("Deactivate") { model.activate(false) }
                .keyboardShortcut(";", modifiers: [.command, .shift])
                .disabled(!model.canDeactivate || model.isChangingFonts)
        }
        CommandGroup(replacing: .help) {
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
        if let kind = AppModel.shared.environment.benchmark {
            Benchmark.run(kind, model: AppModel.shared)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.cleanUpTestFonts()
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
