import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

/// Two drop targets along the bottom of the window: give items this icon, or give them
/// their standard icon back. Each shows per-item results; ⌘Z undoes.
struct FinderWell: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                TargetWell(title: "Apply to Files & Folders",
                           subtitle: model.hasSource ? "Drop items here to give them this icon" : "Open a picture first",
                           systemImage: "folder.badge.plus",
                           isEnabled: model.hasSource,
                           help: "Drop files, folders or disks here, or click to choose them (⌘J)",
                           onClick: { model.chooseTargets(remove: false) },
                           onDrop: { model.applyIcon(to: $0) })
                TargetWell(title: "Remove Custom Icons",
                           subtitle: "Drop items here to restore their standard icons",
                           systemImage: "arrow.uturn.backward.circle",
                           isEnabled: true,
                           help: "Drop files, folders or disks here, or click to choose them (⇧⌘J)",
                           onClick: { model.chooseTargets(remove: true) },
                           onDrop: { model.removeIcons(from: $0) })
            }
            if let summary = model.resultSummary {
                ResultsList(model: model, summary: summary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

struct TargetWell: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let help: String
    let onClick: () -> Void
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s + 2)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [5, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .dropDestination(for: URL.self) { urls, _ in
            guard isEnabled, !urls.isEmpty else { return false }
            onDrop(urls)
            return true
        } isTargeted: { isTargeted = isEnabled && $0 }
    }
}

struct ResultsList: View {
    let model: AppModel
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(summary)
                    .font(.callout.weight(.medium))
                Text(model.resultsAreUndo ? "⇧⌘Z to redo" : "⌘Z to undo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button { model.clearResults() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Hide these results")
                .accessibilityLabel("Hide Results")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.results) { result in
                        ResultRow(result: result)
                    }
                }
            }
            .frame(maxHeight: model.results.count > 3 ? 84 : CGFloat(model.results.count) * 26)
        }
    }
}

struct ResultRow: View {
    let result: TargetResult

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(result.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.s)
            Label(result.outcome.message, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([result.url]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(result.name) in Finder")
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch result.outcome {
        case .applied, .removed, .restored: "checkmark.circle.fill"
        case .unchanged: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch result.outcome {
        case .applied, .removed, .restored: .green
        case .unchanged: .secondary
        case .failed: .orange
        }
    }
}
