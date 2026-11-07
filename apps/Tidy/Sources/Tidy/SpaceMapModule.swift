import SlopKit
import SwiftUI
import TidyCore

/// Asks before Space Map moves whole folders to the Trash (they can be big and personal).
struct SpaceMovePlan: Identifiable {
    let id = UUID()
    var urls: [URL]
    var bytes: Int64

    var title: String {
        urls.count == 1 ? "Move “\(urls[0].lastPathComponent)” to the Trash?" : "Move \(urls.count) items to the Trash?"
    }

    var message: String {
        let names = urls.prefix(5).map(\.lastPathComponent).joined(separator: ", ") + (urls.count > 5 ? ", and \(urls.count - 5) more" : "")
        return "\(urls.count == 1 ? "" : names + ". ")\(ByteFormat.string(bytes)) will be moved to the Trash. You can put it back (⌘Z)."
    }
}

@MainActor
@Observable
final class SpaceState {
    /// The folder mapped (nil until the first scan: the home folder).
    var root: URL?
    var tree: SpaceNode?
    /// The folder shown in the map.
    var current: URL?
    var phase: ScanPhase = .idle
    var progress = ""
    var checked: Set<String> = []
    var selection: Set<String> = []
    /// Protected folders were left out (no Full Disk Access).
    var skippedProtected = false
    /// Moved to the Trash since the scan (path → size), so sizes stay right without rescanning.
    var removed: [String: Int64] = [:]
    @ObservationIgnored var task: Task<Void, Never>?

    func scan(environment: TidyEnvironment, hasFullDiskAccess: Bool) {
        task?.cancel()
        let root = self.root ?? environment.home
        self.root = root
        let excluded = hasFullDiskAccess ? [] : SpaceScanner.protectedFolders(in: environment.home)
        skippedProtected = excluded.contains { $0.path.hasPrefix(root.path + "/") || $0.path == root.path }
        let scanner = SpaceScanner(root: root, excluded: excluded + [environment.trashDirectory].compactMap { $0 })
        phase = .scanning("Mapping…")
        progress = root.path
        AppModel.shared.setStage(.scanning, for: .spaceLens)
        let counter = ProgressBox()
        task = Task {
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    let (count, path) = counter.value
                    if count > 0 { self.progress = "\(count.formatted()) items · \(path)" }
                }
            }
            let work = Task.detached(priority: .userInitiated) { scanner.scan { counter.set($0, $1) } }
            let tree = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            poll.cancel()
            guard !Task.isCancelled else { return }
            self.tree = tree
            self.current = tree?.url
            checked = []
            selection = []
            removed = [:]
            phase = tree == nil ? .stopped : .done
            AppModel.shared.setStage(tree == nil ? .intro : .results, for: .spaceLens)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        phase = .stopped
        AppModel.shared.setStage(tree == nil ? .intro : .results, for: .spaceLens)
    }

    var currentNode: SpaceNode? {
        guard let tree else { return nil }
        return current.flatMap { tree.find($0) } ?? tree
    }

    /// Ancestors from the mapped folder down to the one shown.
    var breadcrumbs: [SpaceNode] {
        guard let tree, let current else { return [] }
        var path: [SpaceNode] = [tree]
        var node = tree
        while node.url.path != current.path,
              let next = node.children.first(where: { current.path.hasPrefix($0.url.path + "/") || current.path == $0.url.path }) {
            path.append(next)
            node = next
        }
        return path
    }

    func open(_ node: SpaceNode) {
        guard node.canOpen, !isRemoved(node) else { return }
        current = node.url
        selection = []
    }

    func goUp() {
        let crumbs = breadcrumbs
        guard crumbs.count > 1 else { return }
        current = crumbs[crumbs.count - 2].url
        selection = []
    }

    func isRemoved(_ node: SpaceNode) -> Bool {
        removed.keys.contains { node.url.path == $0 || node.url.path.hasPrefix($0 + "/") }
    }

    /// The node's size minus what's been moved out of it since the scan.
    func displaySize(_ node: SpaceNode) -> Int64 {
        let inside = removed.filter { $0.key == node.url.path || $0.key.hasPrefix(node.url.path + "/") }.values.reduce(0, +)
        return max(0, node.size - inside)
    }

    func visibleChildren(of node: SpaceNode) -> [SpaceNode] {
        node.children.filter { !isRemoved($0) }
    }

    var checkedNodes: [SpaceNode] {
        guard let tree else { return [] }
        return checked.sorted().compactMap { tree.find(URL(fileURLWithPath: $0)) }.filter { !isRemoved($0) }
    }

    func size(of url: URL) -> Int64? { tree?.find(url).map(displaySize) }

    /// After a move or Put Back.
    func noteChanged(_ paths: Set<String>, restored: Bool) {
        guard let tree else { return }
        if restored {
            for path in paths { removed[path] = nil }
            return
        }
        for path in paths {
            if let node = tree.find(URL(fileURLWithPath: path)) { removed[path] = node.size }
        }
        checked.subtract(paths)
        selection.subtract(paths)
    }
}

/// The scan's progress, shared between the walker and the UI.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var path = ""
    var value: (Int, String) { lock.withLock { (count, path) } }
    func set(_ count: Int, _ path: String) { lock.withLock { self.count = count; self.path = path } }
}

extension AppModel {
    func confirmSpaceMove() {
        let nodes = space.checkedNodes.filter { policy.allows($0.url) }
        guard !nodes.isEmpty else { return }
        pendingSpaceMove = SpaceMovePlan(urls: nodes.map(\.url), bytes: nodes.reduce(0) { $0 + space.displaySize($1) })
    }

    func chooseSpaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = space.root ?? environment.home
        panel.prompt = "Map"
        panel.message = "Choose a folder in your home folder to map."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = environment.home.standardizedFileURL.resolvingSymlinksInPath().path
        guard path == home || path.hasPrefix(home + "/") else {
            failureReport = FailureReport(title: "Choose a folder in your home folder", failures: [
                TrashFailure(url: url, message: "Space Map looks at \(environment.home.path) and the folders inside it."),
            ], offersReveal: false)
            return
        }
        section = .spaceLens
        space.root = url.standardizedFileURL
        space.scan(environment: environment, hasFullDiskAccess: hasFullDiskAccess)
    }
}

// MARK: Views

struct SpaceMapModuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.stage(.spaceLens) {
        case .intro:
            ModuleIntro(systemImage: SidebarSection.spaceLens.systemImage, title: "Space Map",
                        subtitle: "See which folders take up the most space, open them up, and move what you don't need to the Trash.",
                        features: [ModuleFeature(systemImage: "square.grid.3x3.square", title: "A map of folder sizes"),
                                   ModuleFeature(systemImage: "list.number", title: "Biggest folders first"),
                                   ModuleFeature(systemImage: "eye", title: "Hidden files included")],
                        buttonHelp: "Map this folder (⌘R)",
                        action: { model.space.scan(environment: model.environment, hasFullDiskAccess: model.hasFullDiskAccess) }) {
                FolderMenu(title: rootTitle, home: { model.space.root = model.environment.home }, choose: model.chooseSpaceFolder)
            }
        case .scanning:
            ModuleScanning(systemImage: SidebarSection.spaceLens.systemImage, title: "Mapping your storage…",
                           detail: model.space.progress, onStop: model.space.stop)
        default:
            SpaceMapView(model: model)
        }
    }

    private var rootTitle: String {
        guard let root = model.space.root, root != model.environment.home else { return "Home Folder" }
        return root.lastPathComponent
    }
}

/// "Home Folder ▾" with Choose Folder…
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

struct SpaceMapView: View {
    @Bindable var model: AppModel

    var body: some View {
        let space = model.space
        VStack(spacing: 0) {
            if let node = space.currentNode {
                breadcrumbBar
                Hairline()
                if space.skippedProtected {
                    Notice(systemImage: "lock.shield",
                           text: "Desktop, Documents, Downloads and other apps' data weren't mapped: macOS protects them.") {
                        Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                    Hairline()
                }
                HSplitView {
                    SpaceList(model: model, node: node)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                    TreemapView(model: model, node: node)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
                let checked = space.checkedNodes
                ActionBar(model: model, section: .spaceLens, checkedURLs: checked.map(\.url),
                          knownBytes: checked.reduce(0) { $0 + space.displaySize($1) }, buttonTitle: "Move to Trash…")
            } else {
                ContentUnavailableView {
                    Label("Nothing to Map", systemImage: "square.grid.3x3.square")
                } description: {
                    Text("Tidy couldn't read that folder.")
                } actions: {
                    Button("Start Over") { model.setStage(.intro, for: .spaceLens) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: Spacing.xs) {
            Button { model.space.goUp() } label: { Label("Enclosing Folder", systemImage: "chevron.up") }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: SpaceRow.chevronWidth)
                .disabled(model.space.breadcrumbs.count < 2)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Enclosing folder (⌘↑)")
            ForEach(Array(model.space.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                Button(index == 0 ? (crumb.url == model.environment.home ? "Home Folder"
                                     : PathDisplay.short(crumb.url, home: model.environment.home)) : crumb.name) {
                    model.space.current = crumb.url
                    model.space.selection = []
                }
                .buttonStyle(.plain)
                .fontWeight(index == model.space.breadcrumbs.count - 1 ? .semibold : .regular)
                .lineLimit(1)
            }
            Spacer()
            if let node = model.space.currentNode {
                Text("\(ByteFormat.string(model.space.displaySize(node)))\(node.isPartial ? "+" : "")")
                    .font(.headline.monospacedDigit())
                    .help(node.isPartial ? "Some folders inside couldn't be read, so it may be bigger." : "Space on disk")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}

/// The folder's contents, biggest first, with checkboxes. Double-click or Return opens a folder.
struct SpaceList: View {
    @Bindable var model: AppModel
    let node: SpaceNode

    var body: some View {
        let space = model.space
        let children = filtered(space.visibleChildren(of: node))
        List(selection: Binding(get: { space.selection }, set: { space.selection = $0 })) {
            ForEach(children) { child in
                SpaceRow(model: model, node: child, parentSize: max(1, space.displaySize(node)))
                    .tag(child.id)
            }
            if node.otherSize > 0 && model.query.isEmpty {
                // The same columns as SpaceRow (an invisible checkbox keeps the space), so the
                // icon, name and size line up with the rows above.
                HStack(spacing: Spacing.s) {
                    Toggle(isOn: .constant(false)) { EmptyView() }
                        .toggleStyle(.checkbox).labelsHidden().hidden().accessibilityHidden(true)
                    Image(systemName: "ellipsis.circle")
                        .frame(width: ReviewRow.iconSide)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("\(node.otherCount.formatted()) smaller items").foregroundStyle(.secondary)
                    Spacer(minLength: Spacing.s)
                    Text(ByteFormat.string(node.otherSize))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: ReviewRow.sizeWidth, alignment: .trailing)
                    Color.clear.frame(width: SpaceRow.chevronWidth, height: 1)
                }
                .selectionDisabled()
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            let urls = ids.sorted().map { URL(fileURLWithPath: $0) }
            Button("Show in Finder") { Finder.reveal(urls) }
            Button("Quick Look") { model.previewURL = urls.first }
            Divider()
            Button("Check") { model.space.checked.formUnion(ids.filter { model.policy.allows(URL(fileURLWithPath: $0)) }) }
            Button("Uncheck") { model.space.checked.subtract(ids) }
        } primaryAction: { ids in
            guard let id = ids.first, let child = node.children.first(where: { $0.id == id }) else { return }
            if child.canOpen { model.space.open(child) } else { Finder.reveal([child.url]) }
        }
        .onKeyPress(.space) {
            let ids = model.space.selection.filter { model.policy.allows(URL(fileURLWithPath: $0)) }
            guard !ids.isEmpty else { return .ignored }
            if ids.isSubset(of: model.space.checked) { model.space.checked.subtract(ids) } else { model.space.checked.formUnion(ids) }
            return .handled
        }
    }

    private func filtered(_ nodes: [SpaceNode]) -> [SpaceNode] {
        guard !model.query.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(model.query) }
    }
}

struct SpaceRow: View {
    /// The open-folder button's slot (also kept empty for files), so sizes line up.
    static let chevronWidth: CGFloat = 16

    var model: AppModel
    let node: SpaceNode
    let parentSize: Int64

    var body: some View {
        let space = model.space
        let allowed = model.policy.allows(node.url)
        let size = space.displaySize(node)
        HStack(spacing: Spacing.s) {
            Toggle(isOn: Binding(get: { space.checked.contains(node.id) },
                                 set: { if $0 { space.checked.insert(node.id) } else { space.checked.remove(node.id) } })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!allowed)
            .accessibilityLabel(node.name)
            .help(allowed ? "Check to move it to the Trash" : "Tidy doesn't move this folder.")
            Image(nsImage: Icons.icon(for: node.url)).resizable()
                .frame(width: ReviewRow.iconSide, height: ReviewRow.iconSide).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                ProgressView(value: Double(size), total: Double(parentSize))
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: Spacing.s)
            // A fixed slot: the bars above stay the same length whatever the size's width.
            Text(ByteFormat.string(size) + (node.isPartial ? "+" : ""))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ReviewRow.sizeWidth, alignment: .trailing)
            if node.canOpen {
                Button { space.open(node) } label: { Label("Open \(node.name)", systemImage: "chevron.right") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: Self.chevronWidth)
                    .help("Open this folder in the map")
            } else {
                Color.clear.frame(width: Self.chevronWidth, height: 1)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Rectangles sized by space on disk. Click selects, double-click opens a folder.
struct TreemapView: View {
    var model: AppModel
    let node: SpaceNode

    var body: some View {
        let space = model.space
        let children = space.visibleChildren(of: node)
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: Spacing.m, dy: Spacing.m)
            let values = children.map { Double(space.displaySize($0)) } + [Double(node.otherSize)]
            let rects = Treemap.layout(values, in: bounds)
            let largest = Double(children.first.map { space.displaySize($0) } ?? 1)
            ZStack(alignment: .topLeading) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    let rect = rects[index]
                    if rect.width > 1 && rect.height > 1 {
                        TreemapTile(name: child.name, size: space.displaySize(child), isPartial: child.isPartial,
                                    isFolder: child.isDirectory && !child.isPackage,
                                    weight: Double(space.displaySize(child)) / max(largest, 1),
                                    isSelected: space.selection.contains(child.id), isChecked: space.checked.contains(child.id))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .onTapGesture(count: 2) { if child.canOpen { space.open(child) } else { Finder.reveal([child.url]) } }
                            .onTapGesture { space.selection = [child.id] }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(child.name), \(ByteFormat.string(space.displaySize(child)))")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { space.selection = [child.id] }
                            .accessibilityAction(named: "Open") { space.open(child) }
                    }
                }
                if let rect = rects.last, node.otherSize > 0, rect.width > 1, rect.height > 1 {
                    TreemapTile(name: "\(node.otherCount.formatted()) smaller items", size: node.otherSize, isFolder: false, weight: 0,
                                isSelected: false, isChecked: false, isOther: true)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(node.otherCount) smaller items, \(ByteFormat.string(node.otherSize))")
                }
            }
        }
        .background(.background)
    }
}

struct TreemapTile: View {
    @Environment(\.controlActiveState) private var activeState
    let name: String
    let size: Int64
    var isPartial = false
    let isFolder: Bool
    let weight: Double
    let isSelected: Bool
    let isChecked: Bool
    var isOther = false

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(isSelected ? Color.selectionRing(activeState) : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2.5 : 0.5)
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    if proxy.size.width > 64 && proxy.size.height > 34 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.callout.weight(.medium)).lineLimit(proxy.size.height > 60 ? 2 : 1)
                            Text(ByteFormat.string(size) + (isPartial ? "+" : "")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(Spacing.s)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isChecked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OnAccent.color, Color.windowAccent(activeState))
                        .padding(Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .padding(1.5)
            .contentShape(Rectangle())
    }

    private var fill: AnyShapeStyle {
        if isOther { return AnyShapeStyle(.quaternary) }
        if isFolder { return AnyShapeStyle(Color.windowAccent(activeState).opacity(0.18 + 0.45 * weight)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12 + 0.25 * weight))
    }
}
