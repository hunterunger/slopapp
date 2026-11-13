import AppKit
import Observation
import ShorthandCore
import SlopKit
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Unset by default (⌘/ and ⌥Space, the usual picks, are taken by apps and by macOS).
    /// Test copies use their own names, so they never pick up the person's shortcuts.
    static let searchSnippets = Self(Diagnostics.isTestMode ? "test.searchSnippets" : "searchSnippets")
}

@MainActor
@Observable
final class SearchState {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            selection = 0
            refresh()
        }
    }
    private(set) var results: [Snippet] = []
    var selection = 0
    @ObservationIgnored var library: () -> Library = { Library() }
    @ObservationIgnored var hasFields: (Snippet) -> Bool = { _ in false }
    @ObservationIgnored var preview: (Snippet) -> String = { $0.plainContent }

    func refresh() {
        results = QuickSearch.results(library().snippets, query: query)
        selection = results.isEmpty ? 0 : min(selection, results.count - 1)
    }

    var selected: Snippet? { results.indices.contains(selection) ? results[selection] : nil }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + step, 0), results.count - 1)
    }
}

/// Type to filter every snippet (name, abbreviation, text); ↑↓ choose; Return inserts it
/// where you were typing; ⌘1–9 insert one of the first nine; ⌘C copies; Esc clears, then closes.
struct SearchPanelView: View {
    @Bindable var state: SearchState
    let pick: (Snippet) -> Void
    let openLibrary: () -> Void
    @FocusState private var searchFocused: Bool
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    static let width: CGFloat = 560
    static let listHeight: CGFloat = 352

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search snippets", text: $state.query, prompt: Text("Insert a snippet…"))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .accessibilityLabel("Search snippets")
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            Hairline()
            list
                .frame(height: Self.listHeight)
            Hairline()
            HStack(spacing: Spacing.m) {
                Text("Return inserts · ⌘C copies · Esc closes")
                Spacer()
                Button("Open Snippets") { openLibrary() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
        .frame(width: Self.width)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder private var list: some View {
        if state.results.isEmpty {
            if state.query.isEmpty {
                ContentUnavailableView("No Snippets Yet", systemImage: "character.cursor.ibeam",
                                       description: Text("Snippets you make in the library show up here."))
            } else {
                ContentUnavailableView.search(text: state.query)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.results.enumerated()), id: \.element.id) { index, snippet in
                            SearchRow(snippet: snippet, preview: state.preview(snippet), number: index < 9 ? index + 1 : nil, selected: index == state.selection,
                                      hasFields: state.hasFields(snippet), radius: Radius.nested(in: panelRadius, padding: Spacing.s))
                                .id(snippet.id)
                                .contentShape(Rectangle())
                                .onTapGesture { pick(snippet) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { pick(snippet) }
                        }
                    }
                    .padding(Spacing.s)
                }
                .onChange(of: state.selection) { _, new in
                    if state.results.indices.contains(new) { proxy.scrollTo(state.results[new].id) }
                }
            }
        }
    }
}

struct SearchRow: View {
    /// The system's colours for a selected row (white on the accent, as in Finder's lists).
    static let selectedText = Color(nsColor: .alternateSelectedControlTextColor)
    static let selectedBackground = Color(nsColor: .selectedContentBackgroundColor)

    let snippet: Snippet
    let preview: String
    let number: Int?

    private var title: String {
        let name = snippet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let line = preview.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line ?? snippet.title
    }
    let selected: Bool
    let hasFields: Bool
    let radius: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(title)
                        .lineLimit(1)
                    if !snippet.abbreviation.isEmpty {
                        Text(snippet.abbreviation)
                            .font(.callout.monospaced())
                            .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                Text(preview.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hasFields {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .help("Asks for fill-ins")
                    .accessibilityLabel("Asks for fill-ins")
            }
            if let number {
                Text("⌘\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(Self.selectedText) : AnyShapeStyle(.primary))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs + 2)
        .background(selected ? Self.selectedBackground : .clear, in: RoundedRectangle(cornerRadius: radius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The search panel in the centre of the active screen. The app you were in keeps focus.
@MainActor
final class SearchController {
    let state = SearchState()
    private var panel: FloatingPanel?
    private var escapeMonitor: Any?
    private(set) var isShowing = false
    var onShowingChange: (Bool) -> Void = { _ in }
    var onPick: (Snippet) -> Void = { _ in }
    var onCopy: (Snippet) -> Void = { _ in }
    var onOpenLibrary: () -> Void = {}

    func toggle() {
        if isShowing { panel?.dismiss() } else { show() }
    }

    func show() {
        state.query = ""
        state.selection = 0
        state.refresh()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        isShowing = true
        onShowingChange(true)
        panel.show(at: .center)
        startEscapeMonitor()
        Diagnostics.record("search panel shown results=\(state.results.count)")
    }

    func dismiss() { panel?.dismiss() }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(cornerRadius: Radius.xl) { [state] in
            SearchPanelView(state: state, pick: { [weak self] in self?.choose($0) }, openLibrary: { [weak self] in
                self?.dismiss()
                self?.onOpenLibrary()
            })
        }
        panel.setAccessibilityLabel("Insert a snippet")
        panel.animationBehavior = .none
        panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
        panel.onDismiss = { [weak self] in
            guard let self else { return }
            self.isShowing = false
            self.stopEscapeMonitor()
            self.onShowingChange(false)
        }
        return panel
    }

    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection([.command, .control, .option]) == .command
        switch event.keyCode {
        case 125: state.move(1); return true          // ↓
        case 126: state.move(-1); return true         // ↑
        case 36, 76:                                  // Return
            if let snippet = state.selected { choose(snippet) }
            return true
        default: break
        }
        if command, let number = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(number) {
            if state.results.indices.contains(number - 1) { choose(state.results[number - 1]) }
            return true
        }
        if command, event.charactersIgnoringModifiers == "c" {
            let editor = panel?.firstResponder as? NSTextView
            guard editor?.selectedRange().length ?? 0 == 0, let snippet = state.selected else { return false }
            dismiss()
            onCopy(snippet)
            return true
        }
        return false
    }

    private func choose(_ snippet: Snippet) {
        dismiss()
        onPick(snippet)
    }

    /// Esc clears the search first (FloatingPanel would close straight away).
    private func startEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isShowing, self.panel?.isKeyWindow == true, !self.state.query.isEmpty else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.state.query = ""
            return nil
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
