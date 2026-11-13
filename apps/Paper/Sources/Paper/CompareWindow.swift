import AppKit
import Observation
import PDFKit
import PaperCore
import SlopKit
import SwiftUI

@Observable
@MainActor
final class CompareModel {
    var changes: [DocumentCompare.Change] = []
    var selected: Int?
    var isComparing = true
    let originalName: String
    let revisedName: String

    init(originalName: String, revisedName: String) {
        self.originalName = originalName
        self.revisedName = revisedName
    }
}

/// Compare With…: the two versions side by side. Removed text is tinted in the original,
/// added text in the revision; the list on the left steps through every difference and
/// scrolls both to it. Paper compares the text, not pictures or layout.
@MainActor
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [CompareWindowController] = []
    let model: CompareModel
    let original: PDFDocument
    let revised: PDFDocument
    let left = PDFView()
    let right = PDFView()

    static func show(original: PDFDocument, originalName: String, revised: PDFDocument, revisedName: String) {
        // Snapshots, so edits in the document window don't shift the highlighted ranges.
        guard let originalCopy = original.dataRepresentation().flatMap(PDFDocument.init(data:)),
              let revisedCopy = revised.dataRepresentation().flatMap(PDFDocument.init(data:)) else { return }
        let controller = CompareWindowController(original: originalCopy, originalName: originalName, revised: revisedCopy, revisedName: revisedName)
        open.append(controller)
        controller.showWindow(nil)
        controller.run()
    }

    init(original: PDFDocument, originalName: String, revised: PDFDocument, revisedName: String) {
        self.original = original
        self.revised = revised
        model = CompareModel(originalName: originalName, revisedName: revisedName)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "Compare “\(originalName)” with “\(revisedName)”"
        window.minSize = NSSize(width: 720, height: 420)
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "PaperCompare")
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        let split = NSSplitViewController()
        let list = NSHostingController(rootView: CompareList(model: model) { [weak self] index in self?.select(index) })
        let sidebar = NSSplitViewItem(sidebarWithViewController: list)
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 380
        split.addSplitViewItem(sidebar)
        let panes = NSSplitViewController()
        panes.splitView.isVertical = true
        for (view, document, title) in [(left, original, "Original: \(model.originalName)"), (right, revised, "Revised: \(model.revisedName)")] {
            view.document = document
            view.displayMode = .singlePageContinuous
            view.autoScales = true
            view.backgroundColor = .underPageBackgroundColor
            view.setAccessibilityLabel(title)
            PDFViewTuning.disableAutomaticAnalysis(view)
            let controller = NSViewController()
            let header = NSHostingView(rootView: ComparePaneHeader(title: title))
            header.translatesAutoresizingMaskIntoConstraints = false
            view.translatesAutoresizingMaskIntoConstraints = false
            let root = NSView()
            root.addSubview(view)
            root.addSubview(header)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
                header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.topAnchor.constraint(equalTo: header.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
            controller.view = root
            let item = NSSplitViewItem(viewController: controller)
            item.minimumThickness = 240
            panes.addSplitViewItem(item)
        }
        split.addSplitViewItem(NSSplitViewItem(viewController: panes))
        contentViewController = split
    }

    private func run() {
        guard let oldData = original.dataRepresentation(), let newData = revised.dataRepresentation() else { return }
        Task {
            let changes = await Task.detached(priority: .userInitiated) { () -> [DocumentCompare.Change] in
                guard let old = PDFDocument(data: oldData), let new = PDFDocument(data: newData) else { return [] }
                return DocumentCompare.compare(old, new)
            }.value
            model.changes = changes
            model.isComparing = false
            highlight()
            if !changes.isEmpty { select(0) }
        }
    }

    private func selections(_ tokens: [DocumentCompare.Token], in document: PDFDocument, color: NSColor) -> [PDFSelection] {
        DocumentCompare.ranges(tokens).compactMap { item in
            guard let selection = document.page(at: item.page)?.selection(for: item.range) else { return nil }
            selection.color = color
            return selection
        }
    }

    private func highlight() {
        let removed = NSColor.systemRed.withAlphaComponent(0.3), added = NSColor.systemGreen.withAlphaComponent(0.3)
        left.highlightedSelections = model.changes.flatMap { selections($0.old, in: original, color: removed) }
        right.highlightedSelections = model.changes.flatMap { selections($0.new, in: revised, color: added) }
    }

    func select(_ index: Int) {
        guard model.changes.indices.contains(index) else { return }
        model.selected = index
        let change = model.changes[index]
        show(change.old, in: left, document: original, near: change.new.first, other: revised)
        show(change.new, in: right, document: revised, near: change.old.first, other: original)
    }

    /// Scrolls to the change; where one side has nothing (an insertion), it goes to the same
    /// place in the text on that side.
    private func show(_ tokens: [DocumentCompare.Token], in view: PDFView, document: PDFDocument, near: DocumentCompare.Token?, other: PDFDocument) {
        if let first = tokens.first, let selection = document.page(at: first.page)?.selection(for: DocumentCompare.ranges(tokens)[0].range) {
            view.setCurrentSelection(selection, animate: true)
            view.go(to: selection)
        } else if let near, let page = document.page(at: min(near.page, document.pageCount - 1)) {
            view.setCurrentSelection(nil, animate: false)
            view.go(to: page)
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

struct ComparePaneHeader: View {
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: PaperMetrics.barHeight)
            Hairline()
        }
        .background(.bar)
    }
}

struct CompareList: View {
    @Bindable var model: CompareModel
    let select: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Text(model.isComparing ? "Comparing…" : model.changes.count == 1 ? "1 difference" : "\(model.changes.count) differences")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.up") }
                    .help("Previous Difference (⌘↑)")
                    .accessibilityLabel("Previous difference")
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.changes.isEmpty)
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                    .help("Next Difference (⌘↓)")
                    .accessibilityLabel("Next difference")
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(model.changes.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Spacing.m)
            .frame(height: PaperMetrics.barHeight)
            Hairline()
            if model.isComparing {
                ProgressView().controlSize(.small).frame(maxHeight: .infinity)
            } else if model.changes.isEmpty {
                ContentUnavailableView("No Text Differences", systemImage: "equal.circle",
                                       description: Text("Both documents have the same text. Paper compares text, not pictures or layout."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(get: { model.selected }, set: { if let index = $0 { select(index) } })) {
                        ForEach(model.changes) { change in
                            CompareRow(change: change).tag(change.id).id(change.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .accessibilityLabel("Differences")
                    .onChange(of: model.selected) { _, index in if let index { proxy.scrollTo(index) } }
                }
                Hairline()
                HStack(spacing: Spacing.m) {
                    legend(.systemRed, "Removed")
                    legend(.systemGreen, "Added")
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, Spacing.m)
                .frame(height: PaperMetrics.barHeight)
            }
        }
    }

    private func step(_ delta: Int) {
        guard !model.changes.isEmpty else { return }
        let next = ((model.selected ?? (delta > 0 ? -1 : 0)) + delta + model.changes.count) % model.changes.count
        select(next)
    }

    private func legend(_ color: NSColor, _ title: String) -> some View {
        HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: Radius.xs).fill(Color(nsColor: color).opacity(0.35)).frame(width: 14, height: 10)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

struct CompareRow: View {
    let change: DocumentCompare.Change

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pageLabel).font(.caption).foregroundStyle(.secondary)
            Text(change.summary).lineLimit(3)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var pageLabel: String {
        let page = (change.newPage ?? change.oldPage ?? 0) + 1
        switch change.kind {
        case .inserted: return "Page \(page) · Added"
        case .deleted: return "Page \((change.oldPage ?? 0) + 1) · Removed"
        case .changed: return "Page \(page) · Changed"
        }
    }
}
