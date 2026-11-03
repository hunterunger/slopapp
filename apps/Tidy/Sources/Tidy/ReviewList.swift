import SlopKit
import SwiftUI
import TidyCore

/// One row in a review list: something Tidy proposes to move to the Trash.
struct ReviewItem: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var title: String
    /// Shown under the title (usually the shortened path).
    var subtitle: String
    /// A short caption explaining the match or why it starts unchecked.
    var note: String?
    /// nil when it can be checked; otherwise why not ("Needs Full Disk Access").
    var lockReason: String?
    /// The size to show when it isn't measured from disk (large files).
    var knownSize: Int64?
    /// Tooltip: why it's listed.
    var help: String?
}

struct ReviewSection: Identifiable {
    var id: String
    var title: String
    var systemImage: String
    var detail: String?
    var items: [ReviewItem]
}

/// A grouped list with a checkbox per item and per group, sizes filling in as they're
/// measured, Space to check or uncheck the selected rows, and Quick Look / Show in Finder in
/// the context menu. Used by Uninstall, Leftovers and Junk.
struct ReviewList: View {
    let sections: [ReviewSection]
    @Binding var checked: Set<String>
    @Binding var selection: Set<String>
    var sizes: SizeStore
    var home: URL
    @State private var collapsed: Set<String> = []

    var body: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section(isExpanded: expandedBinding(section.id)) {
                    ForEach(section.items) { item in
                        ReviewRow(item: item, isChecked: binding(for: item), sizes: sizes)
                            .tag(item.id)
                            .contextMenu { contextMenu(for: item) }
                    }
                } header: {
                    header(section)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .onKeyPress(.space) {
            toggleSelected()
            return .handled
        }
    }

    private func header(_ section: ReviewSection) -> some View {
        let checkable = section.items.filter { $0.lockReason == nil }
        let total = sizes.total(section.items.map(\.url))
        let knownTotal = section.items.compactMap(\.knownSize).reduce(0, +)
        return HStack(spacing: Spacing.s) {
            let checkedCount = checkable.filter { checked.contains($0.id) }.count
            TriStateCheckbox(
                label: "Check all in \(section.title)",
                state: checkable.isEmpty || checkedCount == 0 ? .off : (checkedCount == checkable.count ? .on : .mixed),
                isEnabled: !checkable.isEmpty
            ) {
                let ids = checkable.map(\.id)
                if ids.allSatisfy(checked.contains) { checked.subtract(ids) } else { checked.formUnion(ids) }
            }
            .fixedSize()
            .accessibilityRemoveTraits(.isHeader)
            Label(section.title, systemImage: section.systemImage)
                .font(.headline)
                .foregroundStyle(checkable.isEmpty ? .secondary : .primary)
            if let detail = section.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }
            Spacer(minLength: Spacing.s)
            Text(countText(section, checkable: checkable.count, checked: checkedCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(total.bytes + knownTotal == 0 && !total.isComplete ? "—" : ByteFormat.string(total.bytes + knownTotal))
                .font(.callout.monospacedDigit())
                .foregroundStyle(total.isComplete ? .primary : .secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .background(.background)
    }

    /// One rule everywhere: every row counts (locked and possible matches too).
    private func countText(_ section: ReviewSection, checkable: Int, checked: Int) -> String {
        ItemCount.text(total: section.items.count, checked: checked)
    }

    @ViewBuilder
    private func contextMenu(for item: ReviewItem) -> some View {
        Button("Show in Finder") { Finder.reveal(targets(for: item)) }
        Button("Quick Look") { AppModel.shared.previewURL = item.url }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(targets(for: item).map(\.path).joined(separator: "\n"), forType: .string)
        }
        if item.lockReason == nil {
            Divider()
            Button(checked.contains(item.id) ? "Uncheck" : "Check") { toggle(targets(for: item)) }
        }
    }

    /// The right-clicked row, or the whole selection if the row is part of it.
    private func targets(for item: ReviewItem) -> [URL] {
        selection.contains(item.id) ? selection.sorted().map { URL(fileURLWithPath: $0) } : [item.url]
    }

    private func toggle(_ urls: [URL]) {
        let ids = urls.map(\.path).filter { id in sections.contains { $0.items.contains { $0.id == id && $0.lockReason == nil } } }
        guard !ids.isEmpty else { return }
        if ids.allSatisfy(checked.contains) { checked.subtract(ids) } else { checked.formUnion(ids) }
    }

    private func toggleSelected() {
        toggle(selection.map { URL(fileURLWithPath: $0) })
    }

    private func binding(for item: ReviewItem) -> Binding<Bool> {
        Binding(
            get: { checked.contains(item.id) },
            set: { isOn in
                guard item.lockReason == nil else { return }
                if isOn { checked.insert(item.id) } else { checked.remove(item.id) }
            }
        )
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(id) },
                set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } })
    }
}

struct ReviewRow: View {
    let item: ReviewItem
    @Binding var isChecked: Bool
    var sizes: SizeStore

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle(isOn: $isChecked) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.lockReason != nil)
                .accessibilityLabel(item.title)
            Image(nsImage: Icons.icon(for: item.url))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(item.help.map { "\($0)\n\(item.url.path)" } ?? item.url.path)
            .opacity(item.lockReason == nil ? 1 : 0.6)
            Spacer(minLength: Spacing.s)
            if let lock = item.lockReason {
                Label(lock, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            } else if let note = item.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            SizeText(url: item.url, knownSize: item.knownSize, sizes: sizes, isLocked: item.lockReason != nil)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

struct SizeText: View {
    let url: URL
    var knownSize: Int64?
    var sizes: SizeStore
    var isLocked = false

    var body: some View {
        Group {
            if let knownSize {
                Text(ByteFormat.string(knownSize))
            } else if let usage = sizes.size(url) {
                Text(ByteFormat.string(usage.bytes) + (usage.isPartial ? "+" : ""))
                    .help(usage.isPartial ? "Some files inside couldn't be read, so it may be bigger." : "")
            } else if sizes.isMeasuring(url) {
                ProgressView().controlSize(.mini).accessibilityLabel("Measuring")
            } else {
                Text("—").foregroundStyle(.tertiary)
                    .help(isLocked ? "Tidy can't measure it without access." : "Couldn't be measured.")
            }
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// The bar under a review list: what's checked, the total, and Move to Trash. After a move it
/// shows the result with Put Back.
struct ActionBar: View {
    var model: AppModel
    let section: SidebarSection
    let checkedURLs: [URL]
    /// Sizes already known (large files); otherwise they come from the size store.
    var knownBytes: Int64?
    var buttonTitle = "Move to Trash"

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let result = model.results[section] {
                Image(systemName: result.isPutBack ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(result.isPutBack ? Color.secondary : Color.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.summary)
                    if !result.isPutBack, result.bytes > 0 {
                        Text("Empty the Trash to free \(ByteFormat.string(result.bytes)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = result.leftInPlaceNote {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !result.isPutBack {
                    Button("Put Back") { model.putBack(section) }
                        .help("Move these items back to where they were (⌘Z)")
                }
            } else {
                let total = knownBytes.map { (bytes: $0, isComplete: true) } ?? model.sizes.total(checkedURLs)
                Text(selectionSummary(bytes: total.bytes, complete: total.isComplete))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if model.isMoving {
                ProgressView().controlSize(.small).accessibilityLabel("Moving to Trash")
            }
            if !model.history.isEmpty {
                Button("History…") { model.showingHistory = true }
                    .help("Everything moved to the Trash this session, with Put Back")
            }
            Button(buttonTitle) { model.moveCheckedToTrash(.reviewButton) }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canMoveToTrash || model.section != section)
                // The button never asks: it acts on the list right above it, and everything can be put back.
                .help("Move the checked items to the Trash. You can put them back (⌘Z).")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s + 2)
        .background(.bar)
    }

    private func selectionSummary(bytes: Int64, complete: Bool) -> String {
        let count = checkedURLs.count
        guard count > 0 else { return "Nothing checked" }
        let items = count == 1 ? "1 item" : "\(count.formatted()) items"
        return "\(items) checked, \(complete ? "" : "at least ")\(ByteFormat.string(bytes))"
    }
}

/// A checkbox with a real mixed state (AppKit), for "check all" in a group header.
/// Accessibility reports 0, 1 or 2 (mixed) like any Mac checkbox.
struct TriStateCheckbox: NSViewRepresentable {
    enum State { case off, mixed, on }
    let label: String
    let state: State
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.allowsMixedState = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.state = state
        button.state = state == .on ? .on : (state == .mixed ? .mixed : .off)
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        var state: State = .off

        @objc func clicked(_ sender: NSButton) {
            action()
            // AppKit cycles the state itself; show the model's answer instead.
            sender.state = state == .on ? .on : (state == .mixed ? .mixed : .off)
        }
    }
}

/// "7 items · 3 checked": the count rule for group headers and the app header.
enum ItemCount {
    static func text(total: Int, checked: Int) -> String {
        "\(total == 1 ? "1 item" : "\(total) items") · \(checked) checked"
    }
}
