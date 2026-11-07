import AppKit
import CrateCore
import SlopKit
import SwiftUI

/// The finished screen after extracting, creating, converting, splitting or joining: what
/// was made, as rows that can be dragged anywhere (they're real files now), with Back,
/// Show in Finder and Done in the toolbar.
struct ResultPage: View {
    let title: String
    let detail: String
    let items: [URL]
    var warning: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.xs) {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    Image(systemName: warning == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(warning == nil ? .green : .orange)
                }
                .lineLimit(2)
                .truncationMode(.middle)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let warning {
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.textOrange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Drag items to copy them anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .accessibilityElement(children: .combine)
            Hairline()
            List(items, id: \.self) { url in
                ResultRow(url: url)
                    .onDrag { NSItemProvider(object: url as NSURL) }
                    .contextMenu {
                        Button("Open") { NSWorkspace.shared.open(url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
            }
            .listStyle(.inset)
        }
    }
}

/// One finished item: icon, name, size or item count. Double-click opens it.
struct ResultRow: View {
    let url: URL
    @State private var detail = ""

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent), \(detail.lowercased())")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { NSWorkspace.shared.open(url) }
        .accessibilityAction(named: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        .task(id: url) {
            let url = self.url
            detail = await Task.detached { ItemRow.describe(url) }.value
        }
    }
}

/// Toolbar for a finished screen: Back, Show in Finder, Done (Return).
struct ResultToolbar: ToolbarContent {
    let back: (() -> Void)?
    let reveal: () -> Void
    let done: () -> Void

    @ToolbarContentBuilder var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let back {
                Button(action: back) { Label("Back", systemImage: "chevron.left") }
                    .keyboardShortcut(.cancelAction)
                    .help("Go back (Esc)")
            }
            Button(action: reveal) { Label("Show in Finder", systemImage: "folder") }
                .help("Show the results in Finder (⇧⌘R)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: done) {
                Label("Done", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help("Finish and go back to the start (Return)")
        }
    }
}

/// One format to choose on the format page: a card with a symbol, the name, and a short
/// line. Our own look (system symbols and the accent colour).
struct FormatCard: View {
    let format: CreateFormat
    let selected: Bool
    let action: () -> Void
    @Environment(\.controlActiveState) private var activeState

    static let size = CGSize(width: 92, height: 82)

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: format.symbol)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    // Accent in the key window, grey in a background one (Golden Gate).
                    .foregroundStyle(selected ? Color.windowAccent(activeState) : .secondary)
                    .frame(height: 38)
                Text(format.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .buttonStyle(FormatCardStyle(selected: selected))
        .accessibilityLabel(format.title)
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityHint(format.summary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The card's states: a soft fill that deepens on hover and while pressed, a hairline edge,
/// and an accent fill and 2 pt accent edge when selected (grey when the window isn't key).
struct FormatCardStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, selected: selected)
    }

    private struct CardBody: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlActiveState) private var activeState

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.l, style: .continuous) }

        private var fill: Color {
            if selected { return Color.selectionTint(activeState, opacity: configuration.isPressed ? 0.22 : 0.14) }
            return Color.primary.opacity(configuration.isPressed ? 0.12 : hovering && isEnabled ? 0.08 : 0.04)
        }

        var body: some View {
            configuration.label
                .background(fill, in: shape)
                .hairlineBorder(shape)
                .overlay {
                    if selected { shape.strokeBorder(Color.selectionRing(activeState), lineWidth: 2) }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: selected)
        }
    }
}

extension CreateFormat {
    var symbol: String {
        switch self {
        case .zip: "doc.zipper"
        case .sevenZip: "archivebox"
        case .tarGz: "shippingbox"
        case .tarXz: "shippingbox.fill"
        }
    }
}

/// Split into parts: a size and a unit (KB, MB, GB).
struct SplitSheet: View {
    let fileName: String
    let fileSize: Int64?
    @Binding var size: Int
    @Binding var unit: FileSplitter.Unit
    let onSplit: (Int64) -> Void
    let onCancel: () -> Void
    @FocusState private var sizeFocused: Bool

    private var partSize: Int64 { Int64(max(size, 0)) * unit.bytes }

    private var problem: String? {
        if partSize < FileSplitter.minimumPartSize {
            return "Parts must be at least \(ByteCountFormatter.string(fromByteCount: FileSplitter.minimumPartSize, countStyle: .file))."
        }
        if let fileSize, fileSize <= partSize { return "“\(fileName)” is already smaller than one part." }
        return nil
    }

    private var partCount: Int? {
        guard let fileSize, partSize > 0, problem == nil else { return nil }
        return Int((fileSize + partSize - 1) / partSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Split “\(fileName)” into Parts")
                .font(.headline)
            HStack(spacing: Spacing.s) {
                Text("Part size:")
                TextField("Part size", value: $size, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .accessibilityLabel("Part size")
                    .focused($sizeFocused)
                    .onSubmit { if problem == nil { onSplit(partSize) } }
                Stepper("Part size", value: $size, in: 1...100_000)
                    .labelsHidden()
                    .accessibilityLabel("Change part size")
                Picker("Unit", selection: $unit) {
                    ForEach(FileSplitter.Unit.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Unit")
            }
            Group {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.textOrange)
                } else if let partCount {
                    Text("Makes \(partCount) parts named “\(fileName).001”, “.002”… next to it. The original stays.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Text("Crate, 7‑Zip, Keka and The Unarchiver open split archives. Join Parts puts any split file back together.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Split") { onSplit(partSize) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear { sizeFocused = true }
    }
}

/// The bottom bar every page shares: a hairline on top, then a fixed 40 pt row, so the
/// list above never moves when progress, a Stop button or a message replaces the summary.
struct FooterBar<Content: View>: View {
    static var height: CGFloat { 40 }
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Spacing.s, content: content)
                .padding(.horizontal, Spacing.l)
                .frame(height: Self.height)
        }
    }
}

/// The bottom of a page: an optional control on the left, and a centered summary (or
/// progress with Stop) like the original's footer. A `warning` summary reads as a problem
/// to fix (orange, with a symbol).
struct PageFooter<Leading: View>: View {
    let summary: String
    var warning = false
    /// The summary is the only place that says what to do next (why the main button is
    /// off): `.primary`, since `.secondary` is only ~3.1:1 in light mode on macOS 27.
    var isNextStep = false
    let progress: (title: String, fraction: Double?)?
    let stop: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        FooterBar {
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 1).accessibilityHidden(true)
                leading()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let progress {
                    HStack(spacing: Spacing.s) {
                        Text(progress.title).font(.callout).lineLimit(1).truncationMode(.middle)
                        ProgressView(value: progress.fraction ?? 0)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                            .accessibilityLabel("Progress")
                        Button("Stop", action: stop)
                            .controlSize(.small)
                            .keyboardShortcut(.cancelAction)
                    }
                } else if warning {
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.textOrange)
                        .lineLimit(1)
                } else {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(isNextStep ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                }
            }
            .layoutPriority(1)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
                .accessibilityHidden(true)
        }
    }
}
