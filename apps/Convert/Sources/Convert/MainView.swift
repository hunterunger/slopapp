import AppKit
import ConvertCore
import QuickLook
import SlopKit
import SwiftUI

/// The window, laid out like the original: files in groups by kind (Video, Audio, Images),
/// each under a header with the group's format; each file a wide card with its own tools;
/// a status bar along the bottom with the count, presets, quality, size and destination.
struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            if model.isEmpty {
                DropZone("Drop videos, audio or images", systemImage: "arrow.triangle.2.circlepath",
                         types: MediaTypes.accepted + [.folder, .item]) { model.add($0) }
                    .padding(Spacing.windowMargin)
            } else {
                CardQueueView(model: model)
            }
            OutdatedNotice(model: model)
            Hairline()
            StatusBar(model: model)
        }
        .frame(minWidth: 760, minHeight: 400)
        .background { WindowCloseGuard() }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.queue.items.map(\.id)) { model.rowsChanged() }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        // Kept in its own small view so the window body doesn't redraw for every
        // progress tick of every file. (No window subtitle: the status bar has the count.)
        .background { QuickLookHost(model: model) }
        .sheet(item: $model.trimming) { entry in
            TrimSheet(model: model, entry: entry)
        }
        .sheet(item: $model.cropping) { entry in
            CropSheet(model: model, entry: entry)
        }
        .sheet(isPresented: Binding(get: { model.merging != nil }, set: { if !$0 { model.merging = nil } })) {
            if let urls = model.merging { MergeSheet(model: model, files: urls) }
        }
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.queue.isBusy {
                Button { model.queue.cancelAll() } label: {
                    Label("Stop All", systemImage: "stop.circle")
                }
                .help("Stop converting (⌘.)")
            } else if !model.isEmpty {
                Button { model.clearList() } label: {
                    Label("Clear List", systemImage: "xmark.circle")
                }
                .help("Clear the list. Files aren't touched (⇧⌘⌫)")
            }
            Button { model.chooseFiles() } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Choose files or folders to convert (⌘O)")
        }
    }
}

extension CardEntry: Hashable {
    nonisolated static func == (lhs: CardEntry, rhs: CardEntry) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The groups of cards: a scrolling grid with pinned group headers. Click selects (⌘ adds,
/// ⇧ extends), double-click shows the result in Finder, arrows move, Space previews, Delete
/// removes. Drop more files anywhere on it.
struct CardQueueView: View {
    @Bindable var model: AppModel
    @State private var targeted = false
    @State private var highlighted = Set<UUID>()
    @State private var width: CGFloat = 800
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    static let minCardWidth: CGFloat = 330

    private var columns: Int {
        max(1, Int((width - 2 * Spacing.l + Spacing.m) / (Self.minCardWidth + Spacing.m)))
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.groups) { group in
                        Section {
                            // Rows are direct children of the lazy stack (not a nested grid), so
                            // `scrollTo` can reach a card that hasn't been drawn yet.
                            if !model.collapsedGroups.contains(group.id) {
                                ForEach(rows(of: group)) { row in
                                    HStack(alignment: .top, spacing: Spacing.m) {
                                        ForEach(row.entries) { entry in
                                            card(entry, kind: group.kind)
                                                .frame(maxWidth: .infinity)
                                        }
                                        ForEach(row.entries.count..<columns, id: \.self) { _ in
                                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                        }
                                    }
                                    .padding(.horizontal, Spacing.l)
                                    .padding(.bottom, row.entries.last?.id == group.entries.last?.id ? Spacing.s : 0)
                                }
                            }
                        } header: {
                            // Same edges as the cards below it.
                            // No gap above it: pinned, it sits right under the toolbar, so no
                            // card can show through above it. Groups are spaced by the stack's
                            // top padding and the bottom padding of each group's last row.
                            GroupHeader(group: group, model: model)
                                .padding(.horizontal, Spacing.l)
                                .padding(.bottom, model.collapsedGroups.contains(group.id) ? Spacing.s : 0)
                        }
                    }
                }
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.s)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { width = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in width = new }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space, .return, .delete, .deleteForward]) { press in
                let result = handle(press)
                // Arrows keep the moved-to card in view.
                if result == .handled, [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(press.key),
                   let id = model.selectionLead {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { scroller.scrollTo(rowID(containing: id)) }
                }
                return result
            }
            .onChange(of: model.addedBatch) {
                let ids = model.lastAddedIDs
                guard let first = ids.first else { return }
                focused = true
                highlighted = Set(ids)
                Task {
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        scroller.scrollTo(rowID(containing: ids.count > 1 ? first : ids[ids.count - 1]),
                                          anchor: ids.count > 1 ? .top : .bottom)
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeOut(duration: 0.25)) { highlighted.subtract(ids) }
                }
            }
        }
        .overlay {
            if targeted {
                // Stays the accent while dragging from another app (the window isn't key then),
                // as Finder's drop targets do.
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(Spacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = DropFilter.accepted(urls, types: MediaTypes.accepted + [.folder, .item])
            guard !accepted.isEmpty else { return false }
            model.add(accepted)
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files")
    }

    /// One row of cards. Its id (also the scroll target) is its group's and its first card's:
    /// a file that turns out to be another kind once read (an MKV whose picture can't be
    /// read is sound) moves group, and two rows in different groups must never share an id
    /// (the lazy stack reused the old row's view and showed a stale card).
    struct CardRow: Identifiable {
        let group: String
        let entries: [CardEntry]
        var id: String { "row-\(group)-" + (entries.first?.id.uuidString ?? "") }
    }

    private func rows(of group: CardGroup) -> [CardRow] {
        stride(from: 0, to: group.entries.count, by: columns).map {
            CardRow(group: group.id, entries: Array(group.entries[$0..<min($0 + columns, group.entries.count)]))
        }
    }

    /// The row a card sits in now (it changes with the column count and as files move groups).
    private func rowID(containing id: UUID) -> String {
        for group in model.groups where !model.collapsedGroups.contains(group.id) {
            if let row = rows(of: group).first(where: { $0.entries.contains { $0.id == id } }) { return row.id }
        }
        return ""
    }

    private func card(_ entry: CardEntry, kind: MediaKind?) -> some View {
        CardView(entry: entry, kind: kind, model: model, isSelected: model.selection.contains(entry.id))
            .overlay {
                if highlighted.contains(entry.id) {
                    RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous)
                        .fill(Color.selectionTint(activeState, opacity: 0.18))
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture { select(entry) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { open(entry) })
            .contextMenu { CardContextMenu(model: model, entry: entry) }
            .accessibilityAddTraits(model.selection.contains(entry.id) ? [.isSelected] : [])
            .accessibilityAction(named: "Select") { select(entry) }
            .accessibilityAction(named: "Show in Finder") { open(entry) }
    }

    private func select(_ entry: CardEntry) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(entry.id) { model.selection.remove(entry.id) } else { model.selection.insert(entry.id) }
        } else if flags.contains(.shift), let anchor = model.selection.first {
            let ordered = model.groups.flatMap(\.entries).map(\.id)
            if let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: entry.id) {
                model.selection.formUnion(ordered[min(a, b)...max(a, b)])
            }
        } else {
            model.selection = [entry.id]
        }
    }

    private func open(_ entry: CardEntry) {
        if let item = entry.item { FileQueueActions.reveal([item]) } else {
            NSWorkspace.shared.activateFileViewerSelecting([entry.input])
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow: model.moveSelection(by: -1, extend: extend)
        case .rightArrow: model.moveSelection(by: 1, extend: extend)
        case .upArrow: model.moveSelection(by: -columns, extend: extend)
        case .downArrow: model.moveSelection(by: columns, extend: extend)
        case .space: model.toggleQuickLook()
        case .return:
            guard let entry = model.selectedEntries.first else { return .ignored }
            open(entry)
        case .delete, .deleteForward:
            guard !model.selectedEntries.isEmpty else { return .ignored }
            model.remove(model.selectedEntries)
        default: return .ignored
        }
        return .handled
    }
}

/// A group's header: Start, its format, name and count, then add, more, clear and fold.
struct GroupHeader: View {
    let group: CardGroup
    @Bindable var model: AppModel
    @Environment(\.controlActiveState) private var activeState

    private var collapsed: Bool { model.collapsedGroups.contains(group.id) }

    private var startable: [CardEntry] {
        group.entries.filter { entry in
            switch entry {
            case .staged: true
            case .item(let item): model.isOutdated(item)
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            // Its slot stays when there's nothing to start, so the format pop-up doesn't jump.
            Button { model.start(startable) } label: {
                Image(systemName: "play.fill")
                    .frame(width: CardMetrics.control, height: CardMetrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Convert the \(group.title.lowercased()) files that are ready")
            .accessibilityLabel("Start \(group.title)")
            .opacity(startable.isEmpty ? 0 : 1)
            .disabled(startable.isEmpty)
            .accessibilityHidden(startable.isEmpty)
            if let kind = group.kind {
                BarMenuButton(name: "\(kind.title) format", value: model.settings.targetTitle(for: kind), symbol: "",
                              help: "What \(group.title.lowercased()) files become, unless a file has its own format",
                              size: CGSize(width: 0, height: CardMetrics.control)) {
                    switch kind {
                    case .video: MenuEntries.video(model)
                    case .audio: MenuEntries.audio(model)
                    case .image: MenuEntries.image(model)
                    }
                }
                .padding(.horizontal, Spacing.s)
                // As tall as the row, so it's inset exactly `headerPadding` from the header's
                // top and bottom, with corners concentric with the header's.
                .frame(maxHeight: .infinity)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: Self.pillRadius, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(group.title).font(.headline)
                Text(group.entries.count == 1 ? "1 file" : "\(group.entries.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.s)
            headerButton("Add Files", symbol: "plus", help: "Add more files (⌘O)") { model.chooseFiles() }
            BarMenuButton(name: "\(group.title) actions", value: "", symbol: "ellipsis.circle",
                          help: "More for this group",
                          size: CGSize(width: CardMetrics.control, height: CardMetrics.control)) { actions }
            headerButton("Clear \(group.title)", symbol: "xmark.circle", help: "Remove these files from the list. Files aren't touched.") {
                model.remove(group.entries, actionName: "Clear \(group.title)")
            }
            headerButton(collapsed ? "Expand \(group.title)" : "Collapse \(group.title)",
                         symbol: collapsed ? "chevron.right" : "chevron.down",
                         help: collapsed ? "Show these files" : "Hide these files") {
                if collapsed { model.collapsedGroups.remove(group.id) } else { model.collapsedGroups.insert(group.id) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Optical: puts the ▷ on the cards' ▷ column and the chevron on their ⊗ column.
        .padding(.leading, Spacing.s + 2)
        .padding(.trailing, Spacing.s + 1)
        .padding(.vertical, Self.headerPadding)
        .background {
            let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            // Opaque underneath: pinned, cards scroll behind it.
            shape.fill(.windowBackground)
            shape.fill(.bar)
            shape.fill(Color.windowAccent(activeState).opacity(0.10))
            Color.clear.hairlineBorder(shape)
        }
    }

    static let radius = CardMetrics.radius
    static let headerPadding: CGFloat = Spacing.xs + 2 // lint:allow 6 pt: header's top/bottom inset
    static let pillRadius = Radius.nested(in: radius, padding: headerPadding)

    private var actions: [BarMenuEntry] {
        var entries: [BarMenuEntry] = []
        if group.kind == .video || group.kind == .audio {
            let urls = model.mergeable(group.entries)
            entries.append(urls.isEmpty
                ? .note("Merge needs two or more files")
                : .action("Merge \(urls.count) Files into One…") { model.merge(group.entries) })
            entries.append(.separator)
        }
        entries.append(.action("Select All \(group.title)") { model.selection = Set(group.entries.map(\.id)) })
        if group.entries.contains(where: { !model.options(for: $0.input).isEmpty }) {
            entries.append(.action("Reset Each File's Own Settings") { model.resetOptions(for: group.entries) })
        }
        let finished = group.entries.filter { if case .finished? = $0.item?.state { true } else { false } }
        if !finished.isEmpty {
            entries.append(.action("Remove Finished Files") { model.remove(finished, actionName: "Remove Finished") })
        }
        return entries
    }

    private func headerButton(_ title: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// Right-click on a card (applies to the selection when the card is part of it).
struct CardContextMenu: View {
    @Bindable var model: AppModel
    let entry: CardEntry

    var body: some View {
        let targets = model.targets(for: entry)
        let items = targets.compactMap(\.item)
        if targets.contains(where: { if case .staged = $0 { true } else { false } }) {
            Button("Start") { model.start(targets) }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map { $0.item?.revealURL ?? $0.input })
        }
        Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.input)) }
        Button("Quick Look") {
            model.selection = Set(targets.map(\.id))
            model.toggleQuickLook()
        }
        Divider()
        if model.canTrim(entry), targets.count == 1 {
            Button("Trim…") { model.trimming = entry }
        }
        if targets.count == 1, model.canCrop(entry) {
            Button(model.options(for: entry.input).crop == nil ? "Crop…" : "Change Crop…") { model.cropping = entry }
        }
        if targets.count == 1, model.hasSubtitles(entry) {
            Menu("Subtitles") {
                let current = model.options(for: entry.input).subtitles
                Toggle("Keep Subtitles", isOn: Binding(get: { current == .keep }, set: { if $0 { model.updateOptions(for: [entry]) { $0.subtitles = .keep } } }))
                ForEach(model.facts(for: entry.input).info?.subtitleTracks.filter(\.canBurn) ?? [], id: \.index) { track in
                    Toggle("Burn In: \(track.title)", isOn: Binding(get: { current == .burn(track.index) },
                                                                    set: { if $0 { model.updateOptions(for: [entry]) { $0.subtitles = .burn(track.index) } } }))
                }
                Toggle("No Subtitles", isOn: Binding(get: { current == .none }, set: { if $0 { model.updateOptions(for: [entry]) { $0.subtitles = .none } } }))
            }
        }
        if targets.allSatisfy(model.canTurn) {
            Menu("Rotate and Flip") {
                Button("Rotate Right") { model.updateOptions(for: targets) { $0.transform = $0.transform.rotatedRight() } }
                Button("Rotate Left") { model.updateOptions(for: targets) { $0.transform = $0.transform.rotatedLeft() } }
                Button("Flip Horizontal") { model.updateOptions(for: targets) { $0.transform = $0.transform.flippedHorizontally() } }
                Button("Flip Vertical") { model.updateOptions(for: targets) { $0.transform = $0.transform.flippedVertically() } }
                Divider()
                Button("Original Orientation") { model.updateOptions(for: targets) { $0.transform = .identity } }
            }
        }
        if !model.mergeable(targets).isEmpty {
            Button("Merge \(model.mergeable(targets).count) Files into One…") { model.merge(targets) }
        }
        if targets.contains(where: { !model.options(for: $0.input).isEmpty }) {
            Button("Reset File Settings") { model.resetOptions(for: targets) }
        }
        Divider()
        if items.contains(where: \.isActive) {
            Button("Stop") { items.forEach(model.queue.cancel) }
        }
        if items.contains(where: \.canRetry) {
            Button("Convert Again") { items.filter(\.canRetry).forEach(model.queue.retry) }
        }
        Button("Remove from List") { model.remove(targets) }
    }
}

/// Along the window's bottom: add and start on the left, the count in the middle, then
/// presets, quality, size and destination.
struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button { model.chooseFiles() } label: {
                Image(systemName: "plus")
                    .frame(width: CardMetrics.control, height: CardMetrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Add files or folders (⌘O)")
            .accessibilityLabel("Add Files")
            StartButton(model: model)
            StatusCount(model: model)
            Spacer(minLength: Spacing.s)
            FormatMenus(model: model)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}

/// Start everything that's ready. Its own view: it reads every file's state.
/// With "start as soon as files are added" off it's always there (dimmed when nothing is
/// ready), so the count beside it doesn't jump each time it would come and go.
struct StartButton: View {
    let model: AppModel
    @AppStorage(AppModel.autoStartKey) private var autoStart = true

    var body: some View {
        if model.canStart || !autoStart {
            Button { model.start() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!model.canStart)
            .help("Convert every file that's ready (⌘↩)")
        }
    }
}

/// "13 files · 6 converting · 7 finished". Its own view so progress ticks redraw only it.
struct StatusCount: View {
    let model: AppModel

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var text: String {
        let s = model.queue.summary
        let total = s.total + model.staged.count
        guard total > 0 else { return "No files" }
        var parts = [total == 1 ? "1 file" : "\(total) files"]
        if !model.staged.isEmpty { parts.append("\(model.staged.count) ready") }
        if s.remaining > 0 { parts.append("\(s.remaining) converting") }
        if s.produced + s.unchanged > 0 { parts.append("\(s.produced + s.unchanged) finished") }
        if s.failed > 0 { parts.append("\(s.failed) failed") }
        if s.cancelled > 0 { parts.append("\(s.cancelled) stopped") }
        return parts.joined(separator: " · ")
    }
}

struct QuickLookHost: View {
    @Bindable var model: AppModel

    var body: some View {
        Color.clear.quickLookPreview($model.previewURL, in: model.previewURL == nil ? [] : model.previewURLs)
    }
}

/// "Settings changed for 3 files. [Convert Again]", under the list, when finished files
/// were made with other settings than the current ones.
struct OutdatedNotice: View {
    let model: AppModel

    var body: some View {
        let count = model.queue.isBusy ? 0 : model.outdatedItems.count
        if count > 0 {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(count == 1 ? "1 file was converted with other settings." : "\(count) files were converted with other settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.s)
                Button("Convert Again") { model.convertAgain() }
                    .help("Convert those files again with the current settings, replacing what they made before (⌘R)")
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }
}

/// Presets, quality, size and destination: compact menus showing their value. The formats
/// per kind live in the group headers; every choice is also in the Format menu.
struct FormatMenus: View {
    @Bindable var model: AppModel

    private var settings: ConvertSettings { model.settings }

    var body: some View {
        HStack(spacing: Spacing.m) {
            BarMenuButton(name: "Presets", value: currentPreset ?? "Presets", symbol: "square.stack.3d.up",
                          help: "Set every format, quality and size in one go, for a device or a job") {
                model.presetEntries()
            }
            BarMenuButton(name: "Quality", value: model.qualityTitle, symbol: settings.fileSize == nil ? "dial.medium" : "scalemass",
                          help: settings.fileSize.map { "Each file is made to fit \($0.title.lowercased()). Convert picks the bit rate." }
                              ?? "Quality: \(settings.quality.detail).") {
                MenuEntries.quality(model)
            }
            BarMenuButton(name: "Size", value: settings.size.shortTitle, symbol: "arrow.up.left.and.arrow.down.right",
                          help: "Make videos and images no bigger than this. Smaller ones are never enlarged. GIFs are also capped by Quality (\(QualityTable.gif(settings.quality).longEdge) px now).") {
                MenuEntries.size(model)
            }
            BarMenuButton(name: "Save To", value: DestinationText.short(settings.destination),
                          symbol: settings.destination == .alongside ? "doc.on.doc" : "folder",
                          help: DestinationText.help(settings.destination)) {
                MenuEntries.destination(model)
            }
        }
        .fixedSize()
    }

    private var currentPreset: String? {
        (Preset.available(model.capabilities) + model.presets.saved).first { $0.matches(settings) }?.name
    }
}

/// The bar menus' contents (the Format menu shows the same choices).
@MainActor
enum MenuEntries {
    static func video(_ model: AppModel) -> [BarMenuEntry] {
        model.capabilities.videoTargets.flatMap { target -> [BarMenuEntry] in
            let item = BarMenuEntry.choice(target.title, detail: target.detail, isOn: model.settings.video == target) {
                model.settings.video = target
            }
            return target == .gif ? [item, .separator] : [item]
        }
    }

    static func audio(_ model: AppModel) -> [BarMenuEntry] {
        model.capabilities.audioTargets.map { target in
            .choice(target.title, detail: target.detail, isOn: model.settings.audio == target) { model.settings.audio = target }
        }
    }

    static func image(_ model: AppModel) -> [BarMenuEntry] {
        model.capabilities.imageTargets.map { target in
            .choice(target.title, detail: target.detail, isOn: model.settings.image == target) { model.settings.image = target }
        }
    }

    static func quality(_ model: AppModel) -> [BarMenuEntry] {
        Quality.allCases.map { quality in
            .choice(quality.title, detail: quality.detail, isOn: model.settings.fileSize == nil && model.settings.quality == quality) {
                model.useQuality(quality)
            }
        } + [.separator] + model.fileSizeEntries()
    }

    static func size(_ model: AppModel) -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = []
        for size in SizeLimit.allCases {
            entries.append(.choice(size.title, detail: nil, isOn: model.settings.size == size) { model.settings.size = size })
            if size == .original { entries.append(.separator) }
        }
        entries.append(.separator)
        entries.append(.note(GIFText.menuNote(model.settings.quality)))
        return entries
    }

    static func destination(_ model: AppModel) -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = [
            .choice("Next to Originals", detail: nil, isOn: model.settings.destination == .alongside) {
                model.settings.destination = .alongside
            },
        ]
        for folder in model.recentFolders {
            entries.append(.choice(folder.lastPathComponent, detail: folder.deletingLastPathComponent().path,
                                   isOn: model.settings.destination == .folder(folder)) { model.useFolder(folder) })
        }
        entries.append(.separator)
        entries.append(.action("Choose Folder…") { model.chooseFolder() })
        return entries
    }
}

// MARK: Menu contents (shared by the format bar and the Format menu)

/// A checkmarked menu item with a one-line subtitle.
struct ChoiceItem: View {
    let title: String
    let detail: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { if $0 { action() } })) {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}

struct VideoMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        let targets = model.capabilities.videoTargets
        ForEach(targets) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.video == target) {
                model.settings.video = target
            }
            if target == .gif { Divider() }
        }
    }
}

struct AudioMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(model.capabilities.audioTargets) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.audio == target) {
                model.settings.audio = target
            }
        }
    }
}

struct ImageMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(model.capabilities.imageTargets) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.image == target) {
                model.settings.image = target
            }
        }
    }
}

struct QualityMenuItems: View {
    @Bindable var model: AppModel
    /// Adds ⌘1–⌘3 (for the Format menu).
    var withShortcuts = false

    var body: some View {
        ForEach(Array(Quality.allCases.enumerated()), id: \.element) { index, quality in
            let item = ChoiceItem(title: quality.title, detail: withShortcuts ? nil : quality.detail,
                                  isOn: model.settings.fileSize == nil && model.settings.quality == quality) {
                model.useQuality(quality)
            }
            if withShortcuts {
                item.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            } else {
                item
            }
        }
    }
}

struct SizeMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(SizeLimit.allCases) { size in
            ChoiceItem(title: size.title, detail: nil, isOn: model.settings.size == size) {
                model.settings.size = size
            }
            if size == .original { Divider() }
        }
        Divider()
        Text(GIFText.menuNote(model.settings.quality))
    }
}

/// The Format menu's File Size submenu: any size, or Quality decides.
struct FileSizeMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ChoiceItem(title: "No Size Limit", detail: nil, isOn: model.settings.fileSize == nil) { model.settings.fileSize = nil }
        Divider()
        ForEach(FileSizeLimit.choices, id: \.self) { limit in
            ChoiceItem(title: limit.title, detail: nil, isOn: model.settings.fileSize == limit) { model.settings.fileSize = limit }
        }
        Button("Other Size…") { model.askForFileSize() }
    }
}

struct DestinationMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ChoiceItem(title: "Next to Originals", detail: nil, isOn: model.settings.destination == .alongside) {
            model.settings.destination = .alongside
        }
        ForEach(model.recentFolders, id: \.self) { folder in
            ChoiceItem(title: folder.lastPathComponent, detail: nil, isOn: model.settings.destination == .folder(folder)) {
                model.useFolder(folder)
            }
        }
        Divider()
        Button("Choose Folder…") { model.chooseFolder() }
    }
}

enum DestinationText {
    static func short(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "Next to Originals"
        case .folder(let url): url.lastPathComponent
        }
    }

    static func help(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "New files are saved next to the originals. Originals aren't touched, and nothing is overwritten."
        case .folder(let url): "New files are saved into \(url.path). Originals aren't touched, and nothing is overwritten."
        }
    }
}
