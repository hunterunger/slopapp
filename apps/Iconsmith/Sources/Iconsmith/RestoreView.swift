import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

/// Restore mode: one big target that gives dropped items their standard icons back.
struct RestoreView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            // Same square and corners as Create's drop zone, so switching tabs feels like one place.
            DropZone("Drop files, folders or disks here", systemImage: "arrow.uturn.backward.circle", types: [.item, .folder],
                     allowsMultiple: true) { model.removeIcons(from: $0) }
                .dropZoneCornerRadius(BigPreview.radius)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: BigPreview.maxSide, maxHeight: BigPreview.maxSide)
            Text("They get their standard icons back. ⌘Z puts the custom ones back.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Per-item results of the last apply or restore.
struct ResultsList: View {
    let model: AppModel
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(summary)
                    .font(.callout.weight(.medium))
                if model.resultsCanUndo {
                    Text(model.resultsAreUndo ? "⇧⌘Z to redo" : "⌘Z to undo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.clearResults() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: ResultRow.buttonSide, height: ResultRow.buttonSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Hide these results")
                .accessibilityLabel("Hide Results")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.results) { result in
                        ResultRow(model: model, result: result)
                    }
                }
            }
            .frame(maxHeight: model.results.count > 3 ? 84 : CGFloat(model.results.count) * 26)
        }
    }
}

struct ResultRow: View {
    let model: AppModel
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
            if result.needsAppManagement {
                Button("Open Settings") { model.openAppManagementSettings() }
                    .controlSize(.small)
                    .help("Privacy & Security ▸ App Management, where you can allow Iconsmith to change apps")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([result.url]) } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: Self.buttonSide, height: Self.buttonSide)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(result.name) in Finder")
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
    }

    /// Icon-only buttons get a full row-height target, not just their glyph.
    static let buttonSide: CGFloat = 20

    private var symbol: String {
        switch result.outcome {
        case .applied, .removed, .restored: "checkmark.circle.fill"
        case .unchanged: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch result.outcome {
        case .applied, .removed, .restored: .textGreen
        // The only copy of this outcome, so it must read at 4.5:1 (.secondary is ~3.1:1 in light on 27.2).
        case .unchanged: .primary
        case .failed: .textOrange
        }
    }
}
