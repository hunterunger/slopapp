import SlopKit
import SwiftUI
import TidyCore
import UniformTypeIdentifiers

// Space Map: what's taking the space, as a nested treemap beside a sized list. Scan a
// folder or a whole disk; the map draws while it scans. Check items anywhere (the tray
// gathers them), then Move to Trash. See docs/research/tidy-diskmap.md.

extension AppModel {
    /// Asks before moving the checked items (after a last check that each is still the
    /// item that was scanned).
    func confirmSpaceMove() {
        guard !space.tray.isEmpty else { return }
        pendingSpaceMove = SpaceMovePlan(items: space.tray.items, otherVolume: space.isOtherVolume)
    }

    func performSpaceMove(_ plan: SpaceMovePlan) {
        let (items, refused) = space.verifiedForMove()
        let urls = items.filter { item in plan.items.contains { $0.path == item.path } }.map { URL(fileURLWithPath: $0.path) }
        if urls.isEmpty {
            if !refused.isEmpty { failureReport = FailureReport(title: "Nothing was moved", failures: refused) }
            return
        }
        move(urls, section: .spaceLens, service: space.trash, refused: refused)
    }

    func chooseSpaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = environment.home
        panel.prompt = "Map"
        panel.message = "Choose a folder or a disk to map."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mapFolder(url)
    }

    /// Maps a folder (chosen, dropped or from Recent). A disk's root maps the disk.
    func mapFolder(_ url: URL) {
        let url = url.standardizedFileURL
        section = .spaceLens
        if let disk = space.volumes.first(where: { $0.root.path == url.path || $0.walkRoot.path == url.path }) {
            space.scope = .volume(disk)
        } else if url.path == environment.home.path {
            space.scope = .home
        } else {
            space.scope = .folder(url)
            space.remember(url)
        }
        startSpaceScan()
    }

    func startSpaceScan() {
        // A new map starts with a clean bar (the last move stays in Edit ▸ Undo and History).
        results[.spaceLens] = nil
        space.scan(environment: environment, hasFullDiskAccess: hasFullDiskAccess)
    }

    /// Apps found in the map go to the Uninstaller, so their leftovers go too.
    func uninstallFromMap(_ item: MapItem) {
        guard let url = space.url(of: item) else { return }
        open(appAt: url)
    }

    /// The map's results are showing (menu commands that act on it are on).
    var mapIsBrowsable: Bool { section == .spaceLens && stage(.spaceLens) != .intro && space.hasMap && !isModalUp }

    var mapHasSingleSelection: Bool {
        mapIsBrowsable && space.selection.count == 1 && space.selection.first.flatMap(space.item).map { !$0.isVirtual } == true
    }

    var mapCanOpenSelection: Bool {
        mapIsBrowsable && space.selection.count == 1 && space.selection.first.flatMap(space.item)?.canOpen == true
    }

    var mapSelectedPackage: MapItem? {
        guard mapIsBrowsable, space.selection.count == 1, let item = space.selection.first.flatMap(space.item),
              item.kind == .package, !item.isApp, item.childCount == 0 else { return nil }
        return item
    }

    func mapOpenSelection() {
        guard let id = space.selection.first, let item = space.item(id) else { return }
        space.open(item)
    }

    func mapShowPackageContents() {
        guard let item = mapSelectedPackage else { return }
        space.rescanCurrentFolder(showPackageContents: item)
    }

    func mapGetInfo() {
        guard mapHasSingleSelection, let id = space.selection.first, let item = space.item(id) else { return }
        space.inspect(item)
    }

    func copyMapPaths(_ ids: Set<String>) {
        let paths = ids.sorted().compactMap { space.url(forID: $0)?.path }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
}

// MARK: Module

struct SpaceMapModuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.stage(.spaceLens) {
            case .intro: SpaceIntro(model: model)
            default:
                if case .failed(let message) = model.space.status {
                    ContentUnavailableView {
                        Label("Nothing to Map", systemImage: "square.grid.3x3.square")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Start Over") { model.setStage(.intro, for: .spaceLens) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SpaceMapView(model: model)
                }
            }
        }
        .onAppear { model.space.loadVolumes(model.environment) }
    }
}

/// The first page: what to map, notes about access, and the round Scan button. Drop a
/// folder or disk anywhere on it to map it.
struct SpaceIntro: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        ModuleIntro(systemImage: SidebarSection.spaceLens.systemImage, title: "Space Map",
                    subtitle: "See what's taking up space on your Mac, open it up, and move what you don't need to the Trash.",
                    features: [ModuleFeature(systemImage: "square.grid.3x3.square", title: "A map that draws as it scans"),
                               ModuleFeature(systemImage: "internaldrive", title: "Your home folder, a folder or a whole disk"),
                               ModuleFeature(systemImage: "tray.full", title: "Collect items, then move them at once")],
                    buttonHelp: "Map it (⌘R). You can also drop a folder here.",
                    action: model.startSpaceScan) {
            VStack(spacing: Spacing.s) {
                ScopeMenu(model: model)
                ScopeSummary(model: model)
                notices
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, Spacing.xl)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(Spacing.xs)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }) else {
                return false
            }
            model.mapFolder(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder private var notices: some View {
        let space = model.space
        if !model.hasFullDiskAccess {
            if case .volume(let volume) = space.scope, volume.kind == .startup {
                Notice(systemImage: "lock.shield",
                       text: "Without Full Disk Access, most of the disk shows as “Not mapped”: macOS protects it. You can still scan.") {
                    Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                }
            } else if !space.scope.isDisk {
                Notice(systemImage: "lock.shield",
                       text: "Desktop, Documents, Downloads and other apps' data will be skipped: macOS protects them.") {
                    Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                }
            }
        }
        if case .volume(let volume) = space.scope, volume.kind == .network {
            Notice(systemImage: "network", text: "Network disks can take minutes to map.") { EmptyView() }
        }
    }
}

/// "Home Folder ▾": the home folder, the disks, recent folders and Choose Folder…
struct ScopeMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        Menu {
            Button("Home Folder") { space.scope = .home }
            if let startup = space.startupVolume {
                Button("\(startup.name) (startup disk)") { space.scope = .volume(startup) }
            }
            let others = space.otherVolumes
            if !others.isEmpty {
                Section("Disks") {
                    ForEach(others) { volume in
                        Button("\(volume.name) (\(volume.kindDescription.lowercased()))") { space.scope = .volume(volume) }
                    }
                }
            }
            if !space.recents.isEmpty {
                Section("Recent") {
                    ForEach(space.recents, id: \.self) { url in
                        Button(url.lastPathComponent) { space.scope = .folder(url) }
                    }
                    Button("Clear Recent") { space.clearRecents() }
                }
            }
            Divider()
            Button("Choose Folder…", action: model.chooseSpaceFolder)
        } label: {
            Label(space.scopeTitle(model.environment.home), systemImage: scopeSymbol)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .help("What to map")
    }

    private var scopeSymbol: String {
        switch model.space.scope {
        case .home: "house"
        case .folder: "folder"
        case .volume(let volume): volume.kind == .network ? "externaldrive.connected.to.line.below"
            : volume.kind == .external ? "externaldrive" : "internaldrive"
        }
    }
}

/// Under the scope menu: the disk's kind and a small used/free bar, or the folder's path.
struct ScopeSummary: View {
    var model: AppModel

    var body: some View {
        switch model.space.scope {
        case .home:
            Text(PathDisplay.short(model.environment.home, home: model.environment.home) == "~"
                 ? "Your home folder" : model.environment.home.path)
                .font(.callout).foregroundStyle(.secondary)
        case .folder(let url):
            Text(PathDisplay.short(url, home: model.environment.home))
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        case .volume(let volume):
            HStack(spacing: Spacing.s) {
                Text(volume.kindDescription + (volume.isReadOnly ? ", read-only" : ""))
                UsageBar(fraction: volume.total > 0 ? Double(volume.used) / Double(volume.total) : 0)
                    .frame(width: 80, height: 6)
                Text("\(ByteFormat.string(volume.free)) free of \(ByteFormat.string(volume.total))")
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A plain used/free capsule.
struct UsageBar: View {
    @Environment(\.controlActiveState) private var activeState
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.windowAccent(activeState))
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: The map page

struct SpaceMapView: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        VStack(spacing: 0) {
            MapHeaderBar(model: model)
            Hairline()
            if space.mapped?.isDisk == true, let figures = space.figures {
                VolumeBar(figures: figures, isStartup: space.volume?.kind == .startup)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                Hairline()
            }
            if space.skippedProtected {
                Group {
                    if model.hasFullDiskAccess {
                        Notice(systemImage: "lock.open", text: "Full Disk Access is on. Rescan to include the protected folders.") {
                            Button("Rescan") { model.startSpaceScan() }
                        }
                    } else {
                        Notice(systemImage: "lock.shield",
                               text: "Desktop, Documents, Downloads and other apps' data weren't mapped: macOS protects them.") {
                            Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                Hairline()
            }
            if space.status == .disconnected {
                Notice(systemImage: "externaldrive.badge.xmark", text: "The disk was disconnected. The map is read-only.") {
                    Button("Start Over") { model.space.reset(); model.setStage(.intro, for: .spaceLens) }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                Hairline()
            }
            HSplitView {
                SpaceList(model: model)
                    .frame(minWidth: 330, idealWidth: 360, maxWidth: 460)
                VStack(spacing: 0) {
                    TreemapView(model: model)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    Hairline()
                    DetailsStrip(model: model)
                }
            }
            MapBottomBar(model: model)
        }
        // Drop a folder or disk on the map to map it instead.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }) else {
                return false
            }
            model.mapFolder(url)
            return true
        }
    }
}

/// Up, breadcrumbs, the scan's progress (or Stopped), and the total.
struct MapHeaderBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        HStack(spacing: Spacing.xs) {
            Button { space.back() } label: { Label("Back", systemImage: "chevron.backward") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: SpaceRow.chevronWidth)
                .disabled(space.backStack.isEmpty)
                .help("Back (⌘[)")
            Button { space.forward() } label: { Label("Forward", systemImage: "chevron.forward") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: SpaceRow.chevronWidth)
                .disabled(space.forwardStack.isEmpty)
                .help("Forward (⌘])")
            Button { space.goUp() } label: { Label("Enclosing Folder", systemImage: "chevron.up") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: SpaceRow.chevronWidth)
                .disabled(!space.canGoUp)
                .help("Enclosing folder (⌘↑)")
            let crumbs = space.breadcrumbs(home: model.environment.home)
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Button(crumb.title) { space.navigate(to: crumb.place) }
                    .buttonStyle(.plain)
                    .fontWeight(index == crumbs.count - 1 ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(index == crumbs.count - 1 ? "You're here" : "Go to \(crumb.title)")
            }
            Spacer(minLength: Spacing.m)
            status
            Text(ByteFormat.string(space.total) + (space.folder?.isLowerBound == true ? "+" : ""))
                .font(.headline.monospacedDigit())
                .help(space.folder?.isLowerBound == true
                      ? "Some of it couldn't be read or is still being counted, so it may be bigger." : "Space on disk")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder private var status: some View {
        let space = model.space
        switch space.status {
        case .scanning:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small).accessibilityLabel("Mapping")
                Text("\(space.progressItems.formatted()) items · \(ByteFormat.string(space.progressBytes))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Stop", action: space.stop)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .help("Stop and keep what was counted (Esc)")
            }
        case .stopped:
            HStack(spacing: Spacing.s) {
                Text("Stopped: partial map").font(.callout).foregroundStyle(.secondary)
                Button("Rescan", action: model.startSpaceScan).controlSize(.small).help("Map it again from the start (⌘R)")
            }
        default:
            EmptyView()
        }
    }
}

/// The disk's used space in four parts: mapped, other used, purgeable, free.
struct VolumeBar: View {
    @Environment(\.controlActiveState) private var activeState
    let figures: VolumeFigures
    let isStartup: Bool

    private struct Segment: Identifiable {
        var id: String { title }
        let title: String
        let bytes: Int64
        let help: String
    }

    private var segments: [Segment] {
        [Segment(title: "Mapped", bytes: figures.mapped, help: "What the map shows."),
         Segment(title: "Other used space", bytes: figures.other,
                 help: isStartup ? "macOS itself, other volumes on this disk, local snapshots, other users and folders Tidy couldn't read."
                    : "Folders Tidy couldn't read and the disk's own bookkeeping."),
         Segment(title: "Purgeable", bytes: figures.purgeable,
                 help: "macOS frees this on its own when it needs room (caches, snapshots it can drop)."),
         Segment(title: "Free", bytes: figures.free, help: "Free space.")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        let width = figures.total > 0 ? proxy.size.width * CGFloat(Double(segment.bytes) / Double(figures.total)) : 0
                        fill(index)
                            .frame(width: max(0, width - 1))
                            .help("\(segment.title): \(ByteFormat.string(segment.bytes)). \(segment.help)")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: Spacing.l) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    HStack(spacing: Spacing.xs) {
                        fill(index).frame(width: 10, height: 10).clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)) // lint:allow 10 pt legend swatch
                            .accessibilityHidden(true)
                        Text(segment.title)
                        Text(ByteFormat.string(segment.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .help(segment.help)
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func fill(_ index: Int) -> some View {
        let accent = Color.windowAccent(activeState)
        switch index {
        case 0: Rectangle().fill(accent)
        case 1: Rectangle().fill(Color.secondary.opacity(0.55))
        case 2:
            // Dashed: it's used, but macOS gives it back on its own.
            Rectangle().fill(accent.opacity(0.18))
                .overlay { Rectangle().strokeBorder(accent.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
        default: Rectangle().fill(.quaternary)
        }
    }
}

// MARK: List

/// The folder's contents, biggest first, with checkboxes. The list is the full equivalent of
/// the map (VoiceOver and the keyboard go here).
struct SpaceList: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        let items = filtered(space.items)
        let parentSize = max(1, space.total)
        Group {
            if case .smaller = space.place, space.smallItems == nil {
                ProgressView("Reading the smaller items…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && space.status != .scanning {
                ContentUnavailableView {
                    Label(model.query.isEmpty ? "This Folder Is Empty" : "No Matches", systemImage: "folder")
                } description: {
                    Text(model.query.isEmpty ? "Nothing in it takes up space." : "Nothing here matches “\(model.query)”.")
                }
            } else {
                List(selection: Binding(get: { space.selection }, set: { space.selection = $0 })) {
                    ForEach(items) { item in
                        SpaceRow(model: model, item: item, parentSize: parentSize)
                            .tag(item.id)
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    MapContextMenu(model: model, ids: ids)
                } primaryAction: { ids in
                    guard let id = ids.first, let item = space.item(id) else { return }
                    MapActions.primary(model, item)
                }
                .onKeyPress(.space) {
                    guard !space.selection.isEmpty else { return .ignored }
                    space.toggle(space.selection)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard space.selection.count == 1, let id = space.selection.first, let item = space.item(id) else { return .ignored }
                    MapActions.primary(model, item)
                    return .handled
                }
            }
        }
    }

    private func filtered(_ items: [MapItem]) -> [MapItem] {
        guard !model.query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(model.query) }
    }
}

/// What double-click and Return do.
@MainActor
enum MapActions {
    static func primary(_ model: AppModel, _ item: MapItem) {
        let space = model.space
        if item.canOpen {
            space.open(item)
        } else if item.isApp {
            model.uninstallFromMap(item)
        } else if let url = space.url(of: item) {
            Finder.reveal([url])
        }
    }
}

struct MapContextMenu: View {
    var model: AppModel
    let ids: Set<String>

    var body: some View {
        let space = model.space
        let items = ids.sorted().compactMap(space.item)
        let real = items.filter { !$0.isVirtual }
        let urls = real.compactMap(space.url)
        if items.count == 1, let item = items.first, item.canOpen {
            Button("Open") { space.open(item) }
        }
        if !urls.isEmpty {
            Button("Show in Finder") { Finder.reveal(urls) }
            Button("Quick Look") { model.previewURL = urls.first }
        }
        if items.count == 1, let item = items.first {
            Button("Get Info") { space.selection = [item.id]; space.inspect(item) }
        }
        if !urls.isEmpty {
            Button("Copy Path") { model.copyMapPaths(Set(real.map(\.id))) }
        }
        if items.count == 1, let item = items.first, item.kind == .package, !item.isApp, item.childCount == 0, space.status != .scanning {
            Button("Show Package Contents") { space.rescanCurrentFolder(showPackageContents: item) }
        }
        if items.count == 1, let item = items.first, item.isApp {
            Button("Uninstall…") { model.uninstallFromMap(item) }
        }
        let checkable = real.filter(space.checkable)
        if !checkable.isEmpty || real.contains(where: space.isChecked) {
            Divider()
            if checkable.contains(where: { !space.isChecked($0) }) {
                Button("Check") { for item in checkable { space.setChecked(item, true) } }
            }
            if real.contains(where: space.isChecked) {
                Button("Uncheck") { for item in real { space.setChecked(item, false) } }
            }
        }
    }
}

struct SpaceRow: View {
    /// The open-folder button's slot (also kept empty for files), so sizes line up.
    static let chevronWidth: CGFloat = 16

    var model: AppModel
    let item: MapItem
    let parentSize: Int64

    var body: some View {
        let space = model.space
        let lock = space.lock(item)
        let covering = space.coveringCheck(item)
        let checked = space.isChecked(item) || covering != nil
        HStack(spacing: Spacing.s) {
            Toggle(isOn: Binding(get: { checked }, set: { space.setChecked(item, $0) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(lock != nil || covering != nil)
                .opacity(item.isVirtual ? 0 : 1)
                .accessibilityLabel(item.name)
                .accessibilityHidden(item.isVirtual)
                .help(lock?.reason ?? covering.map { "Inside “\($0.name)”, which is checked." } ?? "Check to move it to the Trash")
            icon
                .frame(width: ReviewRow.iconSide, height: ReviewRow.iconSide)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(item.isVirtual ? .secondary : .primary)
                        .layoutPriority(1)
                    badges(lock)
                }
                ProgressView(value: Double(min(item.size, parentSize)), total: Double(parentSize))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            // The name column takes the room; the size slot after it is fixed.
            .frame(maxWidth: .infinity, alignment: .leading)
            // A fixed slot: the bars above stay the same length whatever the size's width.
            Text(sizeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ReviewRow.sizeWidth, alignment: .trailing)
                .help(sizeHelp)
            if item.canOpen {
                Button { MapActions.primary(model, item) } label: { Label("Open \(item.name)", systemImage: "chevron.right") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: Self.chevronWidth)
                    .help(item.kind == .smaller ? "List the smaller items" : "Open this folder in the map")
            } else {
                Color.clear.frame(width: Self.chevronWidth, height: 1)
            }
        }
        .padding(.vertical, 1)
        .background {
            if space.hovered == item.id || (space.hovered.map { item.id.hasPrefix($0 + "/") } ?? false) {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(.quaternary.opacity(0.5))
                    .padding(.horizontal, -Spacing.xs)
            }
        }
        .onHover { inside in
            if inside { space.hovered = item.id } else if space.hovered == item.id { space.hovered = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(lock: lock, checked: checked))
    }

    private var sizeText: String {
        let shown = item.flags.contains(.countedElsewhere) ? item.reported : item.size
        return ByteFormat.string(shown) + (item.isLowerBound ? "+" : "")
    }

    private var sizeHelp: String {
        if item.flags.contains(.countedElsewhere) { return "Counted once, at its other copy. Moving this one may free nothing." }
        if item.isCounting { return "Still counting" }
        if item.flags.contains(.partial) { return "Some of it couldn't be read, so it may be bigger." }
        return "Space on disk"
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .smaller: Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
        case .system: Image(systemName: "apple.logo").foregroundStyle(.secondary)
        case .notMapped: Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
        default:
            if let url = model.space.url(of: item) {
                Image(nsImage: Icons.icon(for: url)).resizable()
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func badges(_ lock: MapLock?) -> some View {
        if item.flags.contains(.hardLinked) {
            Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
                .help("Hard-linked: the same file has other names.").accessibilityHidden(true)
        }
        if item.flags.contains(.clone) {
            Image(systemName: "square.on.square").font(.caption).foregroundStyle(.secondary)
                .help("A clone: shares its space with other files.").accessibilityHidden(true)
        }
        if item.flags.contains(.dataless) {
            Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary)
                .help("In iCloud, not downloaded.").accessibilityHidden(true)
        }
        if let lock, lock != .virtualItem {
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                .help(lock.reason).accessibilityHidden(true)
        }
    }

    private func accessibilityLabel(lock: MapLock?, checked: Bool) -> String {
        var parts = [item.name, kindName(item), ByteFormat.string(item.size) + (item.isLowerBound ? " or more" : "")]
        if parentSize > 0 { parts.append("\(Int((Double(item.size) / Double(parentSize) * 100).rounded())) percent") }
        if item.isCounting { parts.append("counting") }
        if checked { parts.append("checked") }
        if let lock, lock != .virtualItem { parts.append("locked: " + lock.reason) }
        return parts.joined(separator: ", ")
    }
}

func kindName(_ item: MapItem) -> String {
    switch item.kind {
    case .folder: "folder"
    case .package: item.isApp ? "app" : "package"
    case .file: "file"
    case .symlink: "alias"
    case .smaller: "group of smaller items"
    case .system: "macOS system volume"
    case .notMapped: "space the map couldn't see"
    }
}

// MARK: Details

/// Under the map, a fixed height so nothing jumps: the item under the pointer, or the
/// selection when the pointer is elsewhere.
struct DetailsStrip: View {
    var model: AppModel

    var body: some View {
        let space = model.space
        let id = space.hovered ?? (space.selection.count == 1 ? space.selection.first : nil)
        let item = id.flatMap(space.item)
        HStack(spacing: Spacing.m) {
            if let item {
                icon(item)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.s) {
                        Text(item.name).font(.headline).lineLimit(1).truncationMode(.middle)
                        Text(summary(item)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(detail(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if !item.isVirtual {
                    Button("Get Info") { space.selection = [item.id]; space.inspect(item) }
                        .controlSize(.small)
                        .help("Sizes, dates and why it's locked (⌘I)")
                        .popover(item: Binding(get: { space.inspected }, set: { space.inspected = $0 }), arrowEdge: .top) { inspected in
                            MapInspector(model: model, item: inspected)
                        }
                }
            } else {
                Text(space.status == .scanning ? "Point at a block to see what it is." : "Point at a block or select a row to see what it is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Spacing.l)
        .frame(height: 52)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }

    @ViewBuilder private func icon(_ item: MapItem) -> some View {
        if let url = model.space.url(of: item) {
            Image(nsImage: Icons.icon(for: url)).resizable()
        } else {
            Image(systemName: item.kind == .system ? "apple.logo" : item.kind == .smaller ? "ellipsis.circle" : "questionmark.square.dashed")
                .font(.title2).foregroundStyle(.secondary)
        }
    }

    private func summary(_ item: MapItem) -> String {
        var text = kindName(item).capitalizedFirst + " · " + ByteFormat.string(item.size) + (item.isLowerBound ? "+" : "")
        if item.isFolderLike, item.itemCount > 0 { text += " · \(item.itemCount.formatted()) files" }
        if item.kind == .smaller { text += " · \(item.otherCount.formatted()) files" }
        return text
    }

    private func detail(_ item: MapItem) -> String {
        let space = model.space
        var notes: [String] = []
        switch item.kind {
        case .system: return "The sealed macOS system volume. It's never mapped or moved."
        case .notMapped:
            return "Used space the map couldn't see: other volumes on this disk, local snapshots, other users and folders Tidy couldn't read."
        case .smaller: return "Files too small to show on their own. Open to list them."
        default: break
        }
        if let lock = space.lock(item) { notes.append(lock.reason) }
        if item.flags.contains(.countedElsewhere) { notes.append("Counted once, at its other copy") }
        if item.flags.contains(.sparse) || item.flags.contains(.compressed), item.logical > item.reported {
            notes.append("File size \(ByteFormat.string(item.logical)) (\(item.flags.contains(.sparse) ? "sparse" : "compressed"))")
        }
        if item.flags.contains(.purgeable) { notes.append("macOS may remove this on its own") }
        if let cloud = space.cloudTally(item), cloud.count > 0 {
            notes.append("\(cloud.count.formatted()) in iCloud, not downloaded (\(ByteFormat.string(cloud.bytes)))")
        }
        let unreadable = space.unreadableCount(item)
        if unreadable > 0 { notes.append(unreadable == 1 ? "Tidy couldn't read 1 folder here" : "Tidy couldn't read \(unreadable) folders here") }
        let path = space.url(of: item).map { PathDisplay.short($0, home: model.environment.home) } ?? ""
        return ([path] + notes).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Get Info: both sizes, dates, and what's special about it.
struct MapInspector: View {
    var model: AppModel
    let item: MapItem

    var body: some View {
        let space = model.space
        let facts = space.inspectedFacts
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                if let url = space.url(of: item) {
                    Image(nsImage: Icons.icon(for: url)).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).lineLimit(2).truncationMode(.middle)
                    Text(kindName(item).capitalizedFirst).font(.callout).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
                row("Size on disk", ByteFormat.string(item.flags.contains(.countedElsewhere) ? item.reported : item.size)
                    + (item.isLowerBound ? "+" : ""))
                row("File size", ByteFormat.string(item.logical))
                if item.isFolderLike { row("Files", item.itemCount.formatted()) }
                if let modified = facts?.modified { row("Modified", modified.formatted(date: .abbreviated, time: .shortened)) }
                if let created = facts?.created { row("Created", created.formatted(date: .abbreviated, time: .shortened)) }
                if let privateSize = facts?.privateSize { row("Frees at least", ByteFormat.string(privateSize)) }
            }
            .font(.callout)
            let notes = self.notes
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(notes, id: \.self) { note in
                        Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let url = space.url(of: item) {
                Text(PathDisplay.short(url, home: model.environment.home))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.l)
        .frame(width: 320, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private var notes: [String] {
        let space = model.space
        var notes: [String] = []
        if let links = space.linkCount(item), links > 1 {
            notes.append("Hard-linked: also at \(links - 1) other \(links == 2 ? "place" : "places"). Moving this one to the Trash frees nothing while the others exist.")
        } else if item.flags.contains(.hardLinked) {
            notes.append("Hard-linked: the same file has other names. Moving this one frees nothing while the others exist.")
        }
        if item.flags.contains(.clone) { notes.append("A clone: shares its space with other files, so moving it may free nothing.") }
        if item.flags.contains(.partialClone) { notes.append("Shares some of its space with other files.") }
        if item.flags.contains(.dataless) { notes.append("In iCloud, not downloaded.") }
        if let cloud = space.cloudTally(item), cloud.count > 0, !item.flags.contains(.dataless) {
            notes.append("\(cloud.count.formatted()) items (\(ByteFormat.string(cloud.bytes))) are in iCloud and not downloaded.")
        }
        if item.flags.contains(.purgeable) { notes.append("macOS may remove this on its own when it needs room.") }
        if item.flags.contains(.sparse) { notes.append("Sparse: it uses less space on disk than its file size.") }
        if item.flags.contains(.compressed) { notes.append("Compressed by the file system.") }
        let unreadable = space.unreadableCount(item)
        if unreadable > 0 { notes.append("Tidy couldn't read \(unreadable == 1 ? "1 folder" : "\(unreadable) folders") inside.") }
        if let lock = space.lock(item) { notes.append(lock.reason) }
        return notes
    }
}

// MARK: Tray

/// The bottom bar: the checked-items tray, the last move with Put Back, Move to Trash…
struct MapBottomBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        BottomBar {
            Button {
                space.showingTray.toggle()
            } label: {
                Label(trayTitle, systemImage: "tray.full")
                    .monospacedDigit()
            }
            .disabled(space.tray.isEmpty)
            .help("Show the checked items (⇧⌘K)")
            .popover(isPresented: Binding(get: { space.showingTray }, set: { space.showingTray = $0 }), arrowEdge: .top) {
                TrayPopover(model: model)
            }
            if let result = model.results[.spaceLens] {
                Hairline(axis: .vertical).frame(height: 20)
                Image(systemName: result.isPutBack ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(result.isPutBack ? Color.secondary : Color.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.summary).lineLimit(1)
                    if !result.isPutBack, result.bytes > 0 {
                        Text(space.isOtherVolume ? "Empty the Trash while the disk is connected to free up to \(ByteFormat.string(result.bytes))."
                             : "Empty the Trash to free up to \(ByteFormat.string(result.bytes)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !result.isPutBack {
                    Button("Put Back") { model.putBack(.spaceLens) }
                        .help("Move these items back to where they were (⌘Z)")
                    Button("Open Trash") { NSWorkspace.shared.open(model.environment.trashBins[0]) }
                        .help("Show the Trash in Finder")
                }
            } else if let note = space.note {
                Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.isMoving {
                ProgressView().controlSize(.small).accessibilityLabel("Moving to Trash")
            }
            Button("Move to Trash…") { model.moveCheckedToTrash(.reviewButton) }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canMoveToTrash || model.section != .spaceLens)
                .help("Move the checked items to the Trash, after you confirm. You can put them back (⌘Z).")
        }
    }

    private var trayTitle: String {
        let tray = model.space.tray
        guard !tray.isEmpty else { return "Nothing checked" }
        return "\(tray.count == 1 ? "1 checked" : "\(tray.count.formatted()) checked") · up to \(ByteFormat.string(tray.freeable))"
    }
}

/// Every checked item, wherever it is in the map.
struct TrayPopover: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        VStack(alignment: .leading, spacing: 0) {
            Text(space.tray.count == 1 ? "1 Checked Item" : "\(space.tray.count) Checked Items")
                .font(.headline)
                .padding(Spacing.l)
            Hairline()
            List {
                ForEach(space.tray.items) { item in
                    HStack(spacing: Spacing.s) {
                        Image(nsImage: Icons.icon(for: URL(fileURLWithPath: item.path))).resizable()
                            .frame(width: ReviewRow.iconSide, height: ReviewRow.iconSide)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text("in \(item.folderName)" + (item.mayFreeNothing ? " · may free nothing" : ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: Spacing.s)
                        Text(ByteFormat.string(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Menu {
                            Button("Show in Finder") { Finder.reveal([URL(fileURLWithPath: item.path)]) }
                            Button("Quick Look") { model.previewURL = URL(fileURLWithPath: item.path) }
                            Divider()
                            Button("Uncheck") { space.uncheck(path: item.path) }
                        } label: {
                            Label("Actions for \(item.name)", systemImage: "ellipsis.circle")
                        }
                        .labelStyle(.iconOnly)
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Show in Finder, Quick Look or Uncheck")
                        Button { space.uncheck(path: item.path) } label: { Label("Uncheck \(item.name)", systemImage: "xmark.circle.fill") }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Uncheck")
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 120, maxHeight: 320)
            Hairline()
            HStack {
                Text("Up to \(ByteFormat.string(space.tray.freeable)) once you empty the Trash.")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move to Trash…") {
                    space.showingTray = false
                    model.moveCheckedToTrash(.reviewButton)
                }
                .disabled(!model.canMoveToTrash)
            }
            .padding(Spacing.l)
        }
        .frame(width: 420)
    }
}

/// "Home Folder ▾" with Choose Folder… (Large & Old).
struct FolderMenu: View {
    let title: String
    let home: () -> Void
    let choose: () -> Void

    var body: some View {
        Menu {
            Button("Home Folder", action: home)
            Button("Choose Folder…", action: choose)
        } label: {
            Label(title, systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .help("Folder to look in")
    }
}
