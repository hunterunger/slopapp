import AppKit
import DevkitCore
import SlopKit
import SwiftUI

/// Fixed sizes shared by every tool, so switching tools never moves the panes.
enum ToolMetrics {
    /// The options row above a tool's panes.
    static let optionsBarHeight: CGFloat = 40
    /// A pane's title row.
    static let paneHeaderHeight: CGFloat = 30
    /// The status row under the panes (room for two lines of callout text).
    static let statusLineHeight: CGFloat = 32
    /// Text fields that sit in a row of regular controls (pop-ups, segmented pickers).
    static let rowControlHeight: CGFloat = 24
    /// Extra horizontal padding inside a plain list row: plain rows start their content
    /// 8.5 pt in (measured), and 4 more puts row text on the pane title's 12.5 pt line and
    /// row Copy buttons under the header's Copy button.
    static let listRowPadding: CGFloat = Spacing.xs
}

extension View {
    /// Result lists are flush with their pane, like the panes themselves (full-width rows,
    /// as in Xcode's and Console's tables). Pair with `paneListRow()` on each row.
    func paneList() -> some View {
        listStyle(.plain)
    }

    /// Lines a plain list row's text up with the pane title above it.
    func paneListRow() -> some View {
        padding(.horizontal, ToolMetrics.listRowPadding)
    }
}

/// A pane's title row: the title on the leading edge, its controls on the trailing edge.
struct PaneHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.s)
            accessory()
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: ToolMetrics.paneHeaderHeight)
        .background(.bar)
    }
}

/// A titled region (Input, Output…) with optional trailing controls, flush to its neighbors
/// like the panes of Xcode or Console.
struct Pane<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: title, accessory: accessory)
            Hairline()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Pane where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// The slim row of options above a tool's panes. Controls keep their one-line labels; when
/// the window is too narrow for all of them the row scrolls sideways instead of wrapping
/// labels mid-word.
struct OptionsBar<Content: View>: View {
    var isBusy = false
    /// False for a row that only holds a `ToolNote`, which truncates instead.
    var scrolls = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                if scrolls {
                    ScrollView(.horizontal) {
                        row.fixedSize()
                            .padding(.horizontal, Spacing.m)
                            .frame(maxHeight: .infinity)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                } else {
                    row.padding(.horizontal, Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Working")
                        .padding(.trailing, Spacing.m)
                }
            }
            .frame(height: ToolMetrics.optionsBarHeight)
            Hairline()
        }
    }

    private var row: some View {
        HStack(spacing: Spacing.m) {
            content()
        }
        .lineLimit(1)
    }
}

/// An options row that only explains the tool.
struct NoteBar: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        OptionsBar(scrolls: false) { ToolNote(text) }
    }
}

/// What a tool with no options does, in the options row, so every tool's panes start at the
/// same height.
struct ToolNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(text)
    }
}

/// Input and output side by side, or stacked (View ▸ Stack Panes Vertically).
struct SplitPanes<First: View, Second: View>: View {
    @AppStorage(SettingsKey.stackVertically) private var stackVertically = false
    @AppStorage("paneFraction") private var fraction = 0.5
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    var body: some View {
        SplitStack(axis: stackVertically ? .vertical : .horizontal, fraction: $fraction,
                   minimum: stackVertically ? 120 : 220, accessibilityLabel: "Input and output divider",
                   first: first, second: second)
    }
}

/// One line under the panes: what happened, or what went wrong and what to do.
struct StatusLine: View {
    enum Kind { case info, success, warning, error }

    var kind: Kind
    var text: String
    var action: (title: String, run: () -> Void)?
    var hint: String?

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Spacing.s) {
                if !text.isEmpty {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(kind == .error ? .primary : .secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                if let action {
                    Button(action.title, action: action.run)
                        .controlSize(.small)
                }
                Spacer(minLength: Spacing.s)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(hint)
                }
            }
            .padding(.horizontal, Spacing.m)
            // Fixed: a two-line message must not squeeze the panes above it.
            .frame(height: ToolMetrics.statusLineHeight)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

/// A small "Copy" button for pane headers and rows.
struct CopyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Copy", systemImage: "doc.on.doc")
                .labelStyle(.iconOnly)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Copy \(label)")
        .accessibilityLabel("Copy \(label)")
    }
}

/// Label/value rows, each copyable. The selected row is what Copy Output copies.
struct ResultsList: View {
    let rows: [ResultRow]
    @Binding var selection: String?
    var defaultSelection: String?
    var highlighted: String?
    let copy: (ResultRow) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let note = row.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 140, alignment: .leading)
                    // Long tokens (hashes, IDs) would be hyphenated when wrapped, which reads as
                    // part of the value; keep them on one line, truncated in the middle.
                    let isToken = !row.value.contains(where: \.isWhitespace)
                    Text(row.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(isToken ? 1 : 4)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(row.value)
                    if highlighted == row.id {
                        Label("Matches", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .help("Matches the checksum you pasted")
                    }
                    CopyButton(label: row.label) { copy(row) }
                }
                .padding(.vertical, Spacing.xs)
                .paneListRow()
                .tag(row.id)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.label): \(row.value)")
                .accessibilityAction(named: "Copy") { copy(row) }
            }
        }
        .paneList()
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                Button("Copy \(row.label)") { copy(row) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) { copy(row) }
        }
        .onAppear {
            if selection == nil { selection = defaultSelection }
        }
        .onChange(of: rows.map(\.id)) {
            if let current = selection, !rows.contains(where: { $0.id == current }) { selection = defaultSelection }
        }
    }
}

/// A large single-line field for one value (a timestamp, a color, a number).
struct ValueField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        CodeField(text: $text, placeholder: prompt, accessibilityLabel: title, size: .large, focusOnAppear: true)
            .frame(height: 30)
    }
}

/// The empty state for a results area.
struct EmptyResults: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An input pane's editor, or a summary when the input is too large to edit comfortably.
struct InputEditor: View {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var handle: EditorHandle?
    var styles: [TextStyleRun] = []
    var stylesVersion = 0
    var onFileDrop: ((URL) -> Void)?
    let clear: () -> Void

    var body: some View {
        if approximateSize(text) > LargeText.limit {
            VStack(spacing: Spacing.m) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("\(formatBytes(approximateSize(text))) of text")
                    .font(.headline)
                Text("Too large to show for editing. The result is ready, and Copy Output copies all of it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("Clear Input", action: clear)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
        } else {
            CodeTextView(text: $text, placeholder: placeholder, accessibilityLabel: accessibilityLabel,
                         handle: handle, styles: styles, stylesVersion: stylesVersion,
                         onFileDrop: onFileDrop, onLargeText: { text = $0 })
        }
    }
}

/// The buttons on every input pane's header: paste the clipboard here, try an example,
/// clear. The same three in the same place in every tool.
struct InputActions: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Button("Clipboard") { app.pasteClipboardIntoCurrentTool() }
                .help("Paste the clipboard into this tool (⇧⌘V also picks the tool for you)")
            Button("Sample") { app.loadSample() }
                .help("Fill in an example")
                .disabled(!app.canLoadSample)
            Button("Clear") { app.clearInput() }
                .help("Clear the input (⌘K)")
                .disabled(!app.canClearInput)
        }
        .controlSize(.small)
    }
}
