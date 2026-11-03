import AppKit
import ClipsCore
import SlopKit
import SwiftUI

struct PanelActions {
    let choose: (Clip, _ plain: Bool) -> Void
    let copy: (Clip) -> Void
    let togglePin: (Clip) -> Void
    let delete: (Clip) -> Void
    let dismiss: () -> Void
}

enum PanelMetrics {
    static let size = CGSize(width: 760, height: 480)
    static let listWidth: CGFloat = 330
    static let rowHeight: CGFloat = 32
}

/// Search on top; the list on the left, a preview of the selected clip on the right; key
/// hints at the bottom.
struct PanelView: View {
    @Bindable var state: PanelState
    let model: AppModel
    let actions: PanelActions

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            FilterBar(filter: $state.filter)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.s)
            Divider()
            PanelNotices(model: model)
            if let pending = state.pendingPinnedDelete, let clip = state.results.first(where: { $0.id == pending }) {
                NoticeRow(systemImage: "pin", text: "“\(ClipText.title(of: clip, limit: 40))” is pinned. Press ⌘⌫ again to delete it.")
            }
            if model.isLoaded, state.results.isEmpty {
                // Nothing to preview: the explanation gets the whole panel.
                ClipList(state: state, actions: actions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ClipList(state: state, actions: actions)
                        .frame(width: PanelMetrics.listWidth)
                    Divider()
                    Group {
                        if let clip = state.selected {
                            ClipPreview(clip: clip, now: state.now, pasteLabel: pasteLabel, actions: actions)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            PanelFooter(model: model, target: state.target, targetName: state.targetName,
                        selectionIsPinned: state.selected?.isPinned == true)
        }
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .onAppear { searchFocused = true }
        .onChange(of: state.focusRequest) { searchFocused = true }
    }

    private var pasteLabel: String {
        model.willPasteDirectly(into: state.target) ? "Paste" : "Copy"
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search clips", text: $state.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel("Search clips")
            if model.isLoaded {
                Text(countText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(countText)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.m)
    }

    private var countText: String {
        let count = state.results.count
        return count == 1 ? "1 clip" : "\(count.formatted()) clips"
    }
}

// MARK: - Filters

struct FilterBar: View {
    @Binding var filter: ClipFilter

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ClipFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(item == filter ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                        }
                        .foregroundStyle(item == filter ? Color.primary : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == filter ? .isSelected : [])
                .help("Show \(item.title.lowercased()) (Tab switches)")
            }
            Spacer()
        }
        .symbolRenderingMode(.hierarchical)
    }
}

extension ClipFilter {
    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .files: "doc"
        }
    }
}

extension ClipKind {
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }

    var spokenName: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }
}

// MARK: - List

struct ClipList: View {
    @Bindable var state: PanelState
    let actions: PanelActions

    var body: some View {
        if !AppModel.shared.isLoaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.results.isEmpty {
            emptyState
        } else {
            ClipTable(state: state, actions: actions)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !state.query.isEmpty {
            ContentUnavailableView.search(text: state.query)
        } else if state.filter == .pinned {
            ContentUnavailableView("No Pinned Clips", systemImage: "pin",
                                   description: Text("Press ⌘P to pin the selected clip. Pinned clips are never removed automatically."))
        } else if state.filter != .all {
            ContentUnavailableView("No \(state.filter.title)", systemImage: state.filter.systemImage,
                                   description: Text("Nothing of this kind has been copied yet."))
        } else {
            ContentUnavailableView("No Clips Yet", systemImage: "doc.on.clipboard",
                                   description: Text("Copy text, links, images or files in any app and they show up here."))
        }
    }
}

// MARK: - Notices and footer

/// One-line notices above the list: storage problems, clipboard access, paused recording.
struct PanelNotices: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.storageError {
                NoticeRow(systemImage: "exclamationmark.triangle", text: error)
            }
            switch model.clipboardAccess {
            case .denied:
                NoticeRow(systemImage: "hand.raised", text: "macOS is blocking Clips from reading the clipboard, so new copies aren't recorded.",
                          button: "Open Settings…") { ClipboardAccess.openSettings() }
            case .asks:
                NoticeRow(systemImage: "hand.raised", text: "macOS asks before Clips reads each copy. Allow Clips under Paste from Other Apps to stop the alerts.",
                          button: "Open Settings…") { ClipboardAccess.openSettings() }
            case .allowed:
                EmptyView()
            }
            if model.pasteDirectly, !model.hasAccessibility, !model.usesPrivatePasteboard {
                NoticeRow(systemImage: "accessibility", text: "Return copies the clip. To paste straight into apps, allow Clips in Accessibility.",
                          button: "Open Settings…") { Permission.accessibility.request() }
            }
            if let paused = model.pauseDescription {
                NoticeRow(systemImage: "pause.circle", text: "\(paused). New copies aren't recorded.", button: "Resume") {
                    model.resume()
                }
            }
        }
    }
}

struct NoticeRow: View {
    let systemImage: String
    let text: String
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.s)
                if let button, let action {
                    Button(button, action: action)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            Divider()
        }
    }
}

struct PanelFooter: View {
    let model: AppModel
    let target: NSRunningApplication?
    let targetName: String?
    let selectionIsPinned: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            hint("↩", returnText)
            hint("⇧↩", "Plain text")
            if model.willPasteDirectly(into: target) { hint("⌘C", "Copy") }
            hint("⌘P", selectionIsPinned ? "Unpin" : "Pin")
            hint("⌘⌫", "Delete")
            hint("⇥", "Filter")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .frame(height: 34)
    }

    private var returnText: String {
        if model.willPasteDirectly(into: target) {
            return targetName.map { "Paste in \($0)" } ?? "Paste"
        }
        return "Copy"
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
