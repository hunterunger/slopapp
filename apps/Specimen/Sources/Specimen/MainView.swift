import SlopKit
import SpecimenCore
import SwiftUI

/// The library window: sidebar of filters, the font grid, and the detail and compare pages.
struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var previewFocused: Bool

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            VStack(spacing: 0) {
                previewBar
                Hairline()
                ZStack {
                    libraryArea
                        .opacity(model.screen == .grid ? 1 : 0)
                        .allowsHitTesting(model.screen == .grid)
                        .accessibilityHidden(model.screen != .grid)
                    switch model.screen {
                    case .grid: EmptyView()
                    case .detail(let family):
                        FamilyDetailView(model: model, familyName: family)
                            .background(.background)
                            .transition(.opacity)
                    case .compare:
                        CompareView(model: model)
                            .background(.background)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.screen)
            }
            .frame(minWidth: 560, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity, alignment: .top)
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search Fonts")
        .navigationTitle(navigationTitle)
        .navigationSubtitle(model.environment.testModeSummary ?? subtitle)
        .toolbar { toolbarContent }
        .onAppear {
            model.fallbackUndoManager = undoManager
            previewFocused = true
        }
        .onChange(of: undoManager) { model.fallbackUndoManager = undoManager }
        .onChange(of: model.focusPreviewRequest) { previewFocused = true }
        .alert(model.notice?.title ?? "", isPresented: Binding(
            get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }
        ), presenting: model.notice) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.message)
        }
        .sheet(item: $model.pending) { pending in
            ActivationPrompt(model: model, pending: pending)
        }
        .sheet(item: $model.sheet) { sheet in
            LibrarySheetView(model: model, sheet: sheet)
        }
        // Font files dropped anywhere on the window are added (File ▸ Add Fonts…).
        .dropDestination(for: URL.self) { urls, _ in
            let fonts = urls.filter { $0.isFileURL }
            guard !fonts.isEmpty else { return false }
            model.addFonts(fonts)
            return true
        }
    }

    private var navigationTitle: String {
        switch model.screen {
        case .grid: model.title(for: model.sidebar)
        case .detail(let family): model.family(named: family)?.displayName ?? family
        case .compare: "Compare"
        }
    }

    private var subtitle: String {
        guard model.hasLoaded else { return "" }
        let count = model.items.count
        let noun = model.groupByFamily ? (count == 1 ? "family" : "families") : (count == 1 ? "style" : "styles")
        return "\(count.formatted()) \(noun)"
    }

    @ViewBuilder private var libraryArea: some View {
        if !model.hasLoaded {
            ProgressView("Loading fonts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            emptyState
        } else if model.viewMode == .list {
            FontListView(model: model)
        } else {
            FontGrid(model: model)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.search.isEmpty {
            ContentUnavailableView {
                Label("No fonts match “\(model.search)”", systemImage: "magnifyingglass")
            } description: {
                Text(model.sidebar == .all ? "Try another name or style." : "Searching in \(model.title(for: model.sidebar)). Try All Fonts.")
            } actions: {
                Button("Clear Search") { model.search = "" }
            }
        } else if model.hideUncovered, model.isCheckingCoverage || PreviewText.coverageText(model.previewText) != nil {
            ContentUnavailableView {
                Label("No fonts can show this text", systemImage: "character.cursor.ibeam")
            } description: {
                Text("Every font here is missing at least one of its characters.")
            } actions: {
                Button("Show All Fonts Anyway") { model.hideUncovered = false }
            }
        } else if case .tag(let name) = model.sidebar {
            ContentUnavailableView {
                Label("Nothing tagged “\(name)”", systemImage: "tag")
            } description: {
                Text("Select fonts and press ⌘T, or drag them onto the tag in the sidebar.")
            } actions: {
                Button("Show All Fonts") { model.sidebar = .all }
            }
        } else if model.sidebar == .favorites {
            ContentUnavailableView {
                Label("No favorites yet", systemImage: "star")
            } description: {
                Text("Select a font and press ⌘D, or click the star on its card.")
            } actions: {
                Button("Show All Fonts") { model.sidebar = .all }
            }
        } else {
            ContentUnavailableView {
                Label("No fonts here", systemImage: model.sidebar.systemImage)
            } description: {
                Text(model.showSystemFonts ? "Nothing in \(model.title(for: model.sidebar)) right now." : "Nothing in \(model.title(for: model.sidebar)). macOS fonts are hidden.")
            } actions: {
                if model.showSystemFonts {
                    Button("Show All Fonts") { model.sidebar = .all }
                } else {
                    Button("Show macOS Fonts") { model.showSystemFonts = true }
                }
            }
        }
    }

    /// The preview text and size: always visible, the main control of the app.
    private var previewBar: some View {
        HStack(spacing: Spacing.s) {
            TextField("Preview text", text: $model.previewText, prompt: Text("Type something to preview in every font"))
                .textFieldStyle(.roundedBorder)
                .focused($previewFocused)
                .accessibilityLabel("Preview text")
                .help("Text shown in every font (⌘L). Leave empty to show each font’s name.")
                .onSubmit { model.focusGridRequest += 1 }
                .onKeyPress(.downArrow) {
                    model.focusGridRequest += 1
                    return .handled
                }
            Menu {
                ForEach(PreviewPreset.all) { preset in
                    Button(preset.title) { model.previewText = preset.text }
                }
            } label: {
                Label("Presets", systemImage: "text.badge.plus")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Preview Text Presets")
            .help("Preview text presets")
            Toggle(isOn: $model.hideUncovered) {
                Label("Hide Fonts That Can’t Show This Text", systemImage: "eye.slash")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help(model.hideUncovered ? "Showing only fonts that have every character of your text. Click to show all." : "Hide fonts that can’t show every character of your text")
            .accessibilityLabel("Hide Fonts That Can’t Show This Text")
            if model.isCheckingCoverage {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Checking which fonts can show the text")
            }
            Hairline(axis: .vertical).frame(height: 16).padding(.horizontal, Spacing.xs)
            Image(systemName: "textformat.size.smaller")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $model.previewSize, in: PreviewSize.range)
                .frame(minWidth: 100, idealWidth: 160, maxWidth: 200)
                .accessibilityLabel("Preview size")
                .accessibilityValue("\(Int(model.previewSize)) points")
                .help("Preview size (⌘+ / ⌘−, ⌘0 for 36 pt)")
            Image(systemName: "textformat.size.larger")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(Int(model.previewSize)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .help("Back to all fonts (Esc)")
            .keyboardShortcut(model.screen == .grid ? nil : KeyboardShortcut.cancelAction)
            // Always there (disabled on the grid, like Finder's): on macOS 26 a toolbar item
            // faded to 0 still draws its empty glass bubble, and adding it on demand would
            // shift the title when a page opens.
            .disabled(model.screen == .grid)
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $model.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Show fonts as a grid (⌘1) or a list (⌘2)")
            .accessibilityLabel("View")
        }
        ToolbarItem(placement: .primaryAction) {
            // Text and checkmarks only (Golden Gate menus), the same items as View ▸ Sort By.
            Menu {
                ForEach(LibrarySort.Key.allCases) { key in
                    Toggle(key.title, isOn: Binding(get: { model.sort.key == key }, set: { _ in model.sort = model.sort.choosing(key) }))
                }
                Divider()
                Toggle("Ascending", isOn: Binding(get: { model.sort.ascending }, set: { model.sort = LibrarySort(key: model.sort.key, ascending: $0) }))
                Toggle("Descending", isOn: Binding(get: { !model.sort.ascending }, set: { model.sort = LibrarySort(key: model.sort.key, ascending: !$0) }))
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("Sort by \(model.sort.key.title.lowercased())")
            .accessibilityLabel("Sort By")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleTrayScreen()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: model.screen == .compare ? "rectangle.stack.fill" : "rectangle.stack")
                    Text("\(model.tray.count)").monospacedDigit()
                }
                .accessibilityHidden(true)
            }
            .help(model.tray.isEmpty ? "Compare: collect fonts with Return or the ⊕ on a card" : "Compare \(model.tray.count) fonts side by side (⌘K)")
            .accessibilityLabel("Compare, \(model.tray.count) fonts")
            .disabled(model.tray.isEmpty && model.screen != .compare)
            .contextMenu {
                Button("Clear Compare") { model.clearTray() }
                    .disabled(model.tray.isEmpty)
            }
        }
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.sidebar }, set: { if let value = $0 { model.sidebar = value; model.screen = .grid } })) {
            Section("Library") {
                ForEach(SidebarItem.libraryItems, id: \.self, content: row)
            }
            Section {
                ForEach(model.tags.names, id: \.self) { name in
                    tagRow(name)
                }
            } header: {
                sectionHeader("Tags", add: "New Tag (⌘N)") { model.sheet = .newTag }
            }
            Section {
                ForEach(model.smartCollections) { collection in
                    row(.smart(collection.id))
                        .help(collection.rules.summary)
                        .contextMenu {
                            Button("Edit Smart Collection…") { model.sheet = .smartCollection(collection, isNew: false) }
                            Button("Delete Smart Collection") { model.deleteSmartCollection(collection.id) }
                        }
                }
            } header: {
                sectionHeader("Smart Collections", add: "New Smart Collection from the current filters (⌥⌘N)") { model.newSmartCollection() }
            }
            Section("Categories") {
                ForEach(SidebarItem.categoryItems, id: \.self, content: row)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isIndexing || model.isChangingFonts {
                HStack(spacing: Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text(model.isChangingFonts ? "Updating fonts…" : "Reading fonts…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func sectionHeader(_ title: String, add help: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(title == "Tags" ? "New Tag" : "New Smart Collection")
            // Section headers run 16 pt further right than the rows' count badges: pull the
            // + in so its right edge lines up with the counts below it.
            .padding(.trailing, Spacing.l)
        }
    }

    private func tagRow(_ name: String) -> some View {
        row(.tag(name))
            .contextMenu {
                let families = model.actionFamilies
                if !families.isEmpty {
                    let membership = model.tags.membership(name, families: families)
                    Button(membership == .all ? "Remove from Selected Fonts" : "Add to Selected Fonts") {
                        model.toggleTag(name, families: families)
                    }
                    Divider()
                }
                Button("Rename Tag…") { model.sheet = .renameTag(name) }
                Button("New Smart Collection with This Tag") {
                    model.sheet = .smartCollection(SmartCollection(name: name, rules: SmartRules(tag: name)), isNew: true)
                }
                Divider()
                Button("Delete Tag") { model.deleteTag(name) }
            }
            // Drag cards from the grid onto a tag to tag them.
            .dropDestination(for: String.self) { names, _ in
                let families = names.flatMap { $0.split(separator: "\n").map(String.init) }.filter { model.family(named: $0) != nil }
                guard !families.isEmpty else { return false }
                model.attachTag(name, families: families)
                return true
            }
    }

    private func row(_ item: SidebarItem) -> some View {
        let title = model.title(for: item)
        return Label(title, systemImage: item.systemImage)
            .badge(model.counts[item] ?? 0)
            .tag(item)
            .accessibilityLabel("\(title), \(model.counts[item] ?? 0)")
    }
}

/// Swap (clashing PostScript name) and bulk-activation confirmations.
struct ActivationPrompt: View {
    var model: AppModel
    var pending: PendingActivation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            switch pending {
            case .swap(let plan):
                swapContent(plan)
            case .bulk(let plan):
                Text("Activate \(plan.changes.count.formatted()) fonts?")
                    .font(.headline)
                Text("Every active font appears in every app’s font menu, and lots of them can make apps slower to open.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { model.pending = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Activate") { model.confirm(plan, swap: false) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440)
    }

    @ViewBuilder private func swapContent(_ plan: ActivationPlan) -> some View {
        let swappable = plan.conflicts.filter { $0.activeCopyLock == nil }
        let blocked = plan.conflicts.filter { $0.activeCopyLock != nil }
        Text(plan.conflicts.count == 1 ? "Another copy of this font is active" : "Other copies of these fonts are active")
            .font(.headline)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(plan.conflicts.prefix(6), id: \.face.id) { conflict in
                Text("\(conflict.face.fullName): the active copy is \(conflict.activeCopy.path ?? "built in").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        if !blocked.isEmpty {
            Text("\(blocked.count == 1 ? "One copy" : "\(blocked.count) copies") can’t be swapped because the active copy belongs to macOS or all users.")
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(swappable.isEmpty ? "Only one copy of a font can be active at a time." : "Only one copy can be active at a time. Turn off the active copy and use this one?")
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { model.pending = nil }
                .keyboardShortcut(.cancelAction)
            if !plan.changes.isEmpty {
                Button("Skip These") { model.confirm(plan, swap: false) }
            }
            if !swappable.isEmpty {
                Button("Use This Copy") { model.confirm(plan, swap: true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
