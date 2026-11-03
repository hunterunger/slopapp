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
                Divider()
                ZStack {
                    gridArea
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
    }

    private var navigationTitle: String {
        switch model.screen {
        case .grid: model.sidebar.title
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

    @ViewBuilder private var gridArea: some View {
        if !model.hasLoaded {
            ProgressView("Loading fonts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            emptyState
        } else {
            FontGrid(model: model)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.search.isEmpty {
            ContentUnavailableView {
                Label("No fonts match “\(model.search)”", systemImage: "magnifyingglass")
            } description: {
                Text(model.sidebar == .all ? "Try another name or style." : "Searching in \(model.sidebar.title). Try All Fonts.")
            } actions: {
                Button("Clear Search") { model.search = "" }
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
                Text(model.showSystemFonts ? "Nothing in \(model.sidebar.title) right now." : "Nothing in \(model.sidebar.title). macOS fonts are hidden.")
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
            Divider().frame(height: 16).padding(.horizontal, Spacing.xs)
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
            .disabled(model.screen == .grid)
            .opacity(model.screen == .grid ? 0 : 1)
            .accessibilityHidden(model.screen == .grid)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.openCompare()
            } label: {
                Label("Compare", systemImage: "rectangle.split.1x2")
            }
            .help(model.compareIsCapped ? "Compare the first 8 selected fonts (⌘K)" : "Compare the selected fonts (⌘K)")
            .disabled(!model.canCompare)
        }
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.sidebar }, set: { if let value = $0 { model.sidebar = value } })) {
            Section("Library") {
                ForEach(SidebarItem.libraryItems, id: \.self, content: row)
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

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(model.counts[item] ?? 0)
            .tag(item)
            .accessibilityLabel("\(item.title), \(model.counts[item] ?? 0)")
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
