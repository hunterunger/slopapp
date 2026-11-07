import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The Library window, AppKit-owned so the panel, menus and a global shortcut can open it
/// from anywhere. Three columns like the original's main window: palettes (history on
/// top), the colors of the selected one, and the editor for the selected color.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = LibraryView(controller: controller, model: controller.model, selection: controller.library)
        let hosting = NSHostingController(rootView: root)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        // SwiftUI bridges the selected list's name ("Brand – 6 colors") only when the
        // selection changes, so start with the same name rather than a fixed title.
        window.title = controller.library.list.map { controller.model.title(of: $0) } ?? "Library"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 820, height: 480)
        window.setContentSize(CGSize(width: 980, height: 600))
        window.identifier = NSUserInterfaceItemIdentifier("library")
        window.delegate = self
        if !window.setFrameUsingName("DropperLibrary") { window.center() }
        window.setFrameAutosaveName("DropperLibrary")
        return window
    }
}

struct LibraryView: View {
    let controller: AppController
    @Bindable var model: DropperModel
    @Bindable var selection: LibrarySelection

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(controller: controller, selection: selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } content: {
            LibraryColorList(controller: controller, selection: selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            LibraryDetail(controller: controller, selection: selection)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Pick Color") { controller.pickAndCopy() }
                    Button("Pick Multiple Colors") { controller.pickMultiple() }
                    Button("Pick Contrast Pair") { controller.pickContrastPair() }
                } label: {
                    Label("Pick Color", systemImage: "eyedropper")
                } primaryAction: {
                    controller.pickAndCopy()
                }
                .help("Pick a color from the screen")
                Button {
                    controller.showContrastChecker()
                } label: {
                    Label("Contrast Checker", systemImage: "circle.lefthalf.filled")
                }
                .help("Contrast Checker (⌘K)")
                FormatSelector(model: model)
                    .frame(width: 190)
            }
        }
        .onChange(of: selection.list) { _, new in
            // Keep a selection that belongs to the new list (Edit in Library sets both).
            let ids = Set(new.map { model.items(in: $0).map(\.id) } ?? [])
            selection.colors = selection.colors.filter { ids.contains($0) }
        }
    }
}

struct LibrarySidebar: View {
    let controller: AppController
    @Bindable var selection: LibrarySelection
    private var model: DropperModel { controller.model }

    var body: some View {
        List(selection: $selection.list) {
            SidebarRow(controller: controller, list: .history, title: "Color History",
                       colors: model.history.items.map(\.color), locked: false, active: false)
                .tag(ColorListID.history)
                .contextMenu { ListActions(controller: controller, list: .history, rename: {}) }
            Section("Palettes") {
                ForEach(model.palettes) { palette in
                    SidebarRow(controller: controller, list: .palette(palette.id), title: palette.name,
                               colors: palette.colors.map(\.color), locked: palette.isLocked,
                               active: model.activePaletteID == palette.id)
                        .tag(ColorListID.palette(palette.id))
                        .contextMenu {
                            ListActions(controller: controller, list: .palette(palette.id)) {
                                selection.list = .palette(palette.id)
                                selection.renaming = palette.id
                            }
                        }
                        .dropDestination(for: String.self) { strings, _ in
                            let colors = strings.flatMap { PaletteCodec.colors(inText: $0) }
                            for color in colors { model.add(color, to: palette.id) }
                            return !colors.isEmpty
                        }
                }
                .onMove { model.movePalettes(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    let palette = controller.newPalette()
                    selection.list = .palette(palette.id)
                    selection.renaming = palette.id
                } label: {
                    Label("New Palette", systemImage: "plus")
                }
                .help("New palette (⌘N)")
                Button {
                    controller.importPalettes()
                } label: {
                    Label("Import Palette…", systemImage: "square.and.arrow.down")
                }
                .help("Import a palette: ASE, CLR, GPL, JSON, or any text with color values (⌘O)")
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            // The + lines up with the rows' text (18 pt in: the list's 10 pt row inset,
            // the selection's 6 pt and the row's 2 pt); borderless buttons add 2 pt.
            .padding(.leading, Spacing.l)
            .padding(.trailing, Spacing.s)
            .padding(.vertical, Spacing.s)
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.controlActiveState) private var activeState
    /// The sidebar's selection (8 pt radius on macOS 26) sits 6 pt outside the row's content
    /// at the sides and 8 pt below it; 2 pt of side padding makes that an even 8 pt, as
    /// large as the selection's radius, so the strip takes the swatch token.
    static let stripRadius = Radius.xs
    static let sidePadding: CGFloat = 2

    let controller: AppController
    let list: ColorListID
    let title: String
    let colors: [ColorValue]
    let locked: Bool
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if list == .history {
                    Text(title).font(.headline)
                } else {
                    Text(title).lineLimit(1)
                }
                if locked {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Locked")
                }
                Spacer()
                if active {
                    Image(systemName: "eyedropper.halffull")
                        .font(.caption)
                        // Grey in a background window, like the system's own accents.
                        .foregroundStyle(Color.windowAccent(activeState))
                        .help("New picks are added to this palette")
                        .accessibilityLabel("New picks go here")
                }
            }
            ColorStrip(colors: colors, vision: controller.settings.colorVision, height: 22, maxCount: 20,
                       cornerRadius: Self.stripRadius)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Self.sidePadding)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(colors.count) colors")
    }
}

struct LibraryColorList: View {
    let controller: AppController
    @Bindable var selection: LibrarySelection
    private var model: DropperModel { controller.model }

    var body: some View {
        if let list = selection.list {
            let items = model.items(in: list)
            let locked = model.isLocked(list)
            List(selection: $selection.colors) {
                ForEach(items) { item in
                    ColorRow(controller: controller, item: item, list: list, compact: true, contextMenuEnabled: false)
                        .tag(item.id)
                }
                .onMove(perform: moveHandler(list, locked: locked))
                .onDelete(perform: locked ? nil : { offsets in
                    model.remove(Set(offsets.map { items[$0].id }), from: list)
                })
            }
            .contextMenu(forSelectionType: PickedColor.ID.self) { ids in
                selectionMenu(ids, items: items, list: list)
            } primaryAction: { ids in
                if let id = ids.first, let item = items.first(where: { $0.id == id }) { controller.copy(item) }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label(list == .history ? "No Colors Yet" : "This Palette Is Empty", systemImage: "eyedropper")
                    } description: {
                        Text(list == .history ? "Pick a color and it shows up here."
                             : "Drag colors here from another list, use Add to Palette, or turn on “Add New Picks Here” and pick.")
                    }
                }
            }
            .navigationTitle(title(list))
            .navigationSubtitle(items.count == 1 ? "1 color" : "\(items.count) colors")
            .dropDestination(for: String.self) { strings, _ in
                guard case .palette(let id) = list else { return false }
                let colors = strings.flatMap { PaletteCodec.colors(inText: $0) }
                for color in colors { model.add(color, to: id) }
                return !colors.isEmpty
            }
        } else {
            ContentUnavailableView("No Palette Selected", systemImage: "swatchpalette")
        }
    }

    private func moveHandler(_ list: ColorListID, locked: Bool) -> ((IndexSet, Int) -> Void)? {
        guard case .palette(let id) = list, !locked else { return nil }
        return { model.moveColors(in: id, fromOffsets: $0, toOffset: $1) }
    }

    @ViewBuilder
    private func selectionMenu(_ ids: Set<PickedColor.ID>, items: [PickedColor], list: ColorListID) -> some View {
        let chosen = items.filter { ids.contains($0.id) }
        if chosen.count == 1, let item = chosen.first {
            ColorActions(controller: controller, item: item, list: list)
        } else if !chosen.isEmpty {
            Button("Copy \(chosen.count) Colors") {
                model.copyText(chosen.map { model.text(for: $0.color, name: $0.name) }.joined(separator: "\n"))
            }
            Menu("Add to Palette") {
                ForEach(model.palettes.filter { list != .palette($0.id) }) { palette in
                    Button(palette.name) { model.add(chosen, to: palette.id) }.disabled(palette.isLocked)
                }
                if !model.palettes.isEmpty { Divider() }
                Button("New Palette with These Colors") { controller.newPalette(colors: chosen) }
            }
            Divider()
            Button("Remove \(chosen.count) Colors", role: .destructive) { model.remove(ids, from: list) }
                .disabled(model.isLocked(list))
        }
    }

    private func title(_ list: ColorListID) -> String { model.title(of: list) }
}

struct LibraryDetail: View {
    let controller: AppController
    @Bindable var selection: LibrarySelection
    private var model: DropperModel { controller.model }

    var body: some View {
        if let list = selection.list {
            let items = model.items(in: list)
            if selection.colors.count == 1, let id = selection.colors.first, let item = items.first(where: { $0.id == id }) {
                ColorEditorView(controller: controller, item: item, list: list)
                    .id(item.id)
            } else if selection.colors.count > 1 {
                ContentUnavailableView("\(selection.colors.count) Colors Selected", systemImage: "square.stack",
                                       description: Text("Right-click for actions on all of them."))
            } else if case .palette(let id) = list, let palette = model.palette(id) {
                PaletteInfoView(controller: controller, palette: palette, selection: selection)
                    .id(palette.id)
            } else {
                HistoryInfoView(controller: controller)
            }
        } else {
            ContentUnavailableView("Nothing Selected", systemImage: "paintpalette")
        }
    }
}

/// Name, note, info and switches for one palette.
struct PaletteInfoView: View {
    let controller: AppController
    let palette: Palette
    @Bindable var selection: LibrarySelection
    @State private var name = ""
    @State private var note = ""
    @FocusState private var nameFocused: Bool
    private var model: DropperModel { controller.model }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit { model.renamePalette(palette.id, to: name) }
                TextField("Notes", text: $note, prompt: Text("What it’s for, where it’s used"), axis: .vertical)
                    .lineLimit(2...6)
                    .onSubmit { model.setNote(note, forPalette: palette.id) }
            }
            .disabled(palette.isLocked)
            Section {
                ColorStrip(colors: palette.colors.map(\.color), vision: controller.settings.colorVision, height: 40, maxCount: 60,
                           cornerRadius: Radius.s)
                    .accessibilityHidden(true)
                LabeledContent("Colors") { Text("\(palette.colors.count)").monospacedDigit() }
                LabeledContent("Created", value: palette.created.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: palette.modified.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                Toggle("Add new picks to this palette", isOn: Binding(
                    get: { model.activePaletteID == palette.id },
                    set: { model.activePaletteID = $0 ? palette.id : nil }))
                Toggle("Show in Color Dock", isOn: Binding(get: { palette.inDock }, set: {
                    model.setInDock($0, palette: palette.id)
                    if $0 { controller.settings.showDock = true }
                }))
                Toggle(isOn: Binding(get: { palette.isLocked }, set: { model.setLocked($0, palette: palette.id) })) {
                    Text("Lock")
                    Text("A locked palette can’t be changed, renamed or deleted.")
                }
            }
            Section {
                HStack {
                    ExportMenuButton { controller.exportPalette(palette.id, as: $0) }
                    .disabled(palette.colors.isEmpty)
                    Button("Duplicate") { model.duplicatePalette(palette.id) }
                    Spacer()
                    Button("Delete Palette…", role: .destructive) { controller.deletePalette(palette.id) }
                        .disabled(palette.isLocked)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(palette.name)
        .onAppear {
            name = palette.name
            note = palette.note
            if selection.renaming == palette.id {
                selection.renaming = nil
                DispatchQueue.main.async { nameFocused = true }
            }
        }
        .onChange(of: nameFocused) { _, focused in if !focused { model.renamePalette(palette.id, to: name) } }
        .onDisappear {
            model.renamePalette(palette.id, to: name)
            if note != palette.note { model.setNote(note, forPalette: palette.id) }
        }
    }
}

struct HistoryInfoView: View {
    let controller: AppController
    private var model: DropperModel { controller.model }

    var body: some View {
        Form {
            Section {
                ColorStrip(colors: model.history.items.map(\.color), vision: controller.settings.colorVision, height: 40, maxCount: 100,
                           cornerRadius: Radius.s)
                    .accessibilityHidden(true)
                LabeledContent {
                    Text("\(model.history.items.count) of \(ColorHistory.defaultLimit)")
                        .monospacedDigit()
                } label: {
                    Text("Colors")
                    Text("Every pick lands here, newest first. Picking a color again moves it to the top.")
                }
            }
            Section {
                HStack {
                    Button("Save as New Palette") { controller.newPalette(colors: model.history.items) }
                    ExportMenuButton { PaletteFiles.export(controller.historyAsPalette, as: $0, controller: controller) }
                    Spacer()
                    Button("Clear History…", role: .destructive) { controller.clearHistory() }
                }
                .disabled(model.history.items.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Color History")
    }
}

extension DropperModel {
    /// A list's name as windows and headers show it.
    func title(of list: ColorListID) -> String {
        switch list {
        case .history: "Color History"
        case .palette(let id): palette(id)?.name ?? "Palette"
        }
    }
}
