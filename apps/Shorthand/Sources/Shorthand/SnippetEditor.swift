import AppKit
import ShorthandCore
import SlopKit
import SwiftUI

/// The detail pane: abbreviation (with conflict notes), name, case, group, the text with an
/// Insert Placeholder menu, a live preview and a "Try it" field. Saves as you type.
struct SnippetEditor: View {
    @Bindable var model: AppModel
    let snippetID: UUID
    let focusAbbreviation: Int
    @State private var textHandle = TextViewHandle()
    @State private var tryText = ""
    @State private var tryNote: String?
    @FocusState private var abbreviationFocused: Bool

    /// Shown in the preview and Try it instead of the real clipboard (which is never read here).
    static let sampleClipboard = "clipboard text"

    private var snippet: Snippet? { model.library.snippet(snippetID) }

    private func binding<T>(_ keyPath: WritableKeyPath<Snippet, T>) -> Binding<T> {
        Binding(
            get: { model.library.snippet(snippetID)?[keyPath: keyPath] ?? Snippet(groupID: UUID(), abbreviation: "", content: "")[keyPath: keyPath] },
            set: { value in
                guard var snippet = model.library.snippet(snippetID) else { return }
                snippet[keyPath: keyPath] = value
                model.update(snippet)
            }
        )
    }

    var body: some View {
        if let snippet {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    fields(snippet)
                    content(snippet)
                    preview(snippet)
                    tryIt
                }
                .padding(Spacing.xl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusedSceneValue(\.placeholderInserter, { textHandle.insert(PlaceholderParser.token(for: $0)) })
            .onAppear { if snippet.abbreviation.isEmpty { abbreviationFocused = true } }
            .onChange(of: focusAbbreviation) { _, _ in abbreviationFocused = true }
        }
    }

    // MARK: Fields

    private func fields(_ snippet: Snippet) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.m) {
            GridRow {
                Text("Abbreviation")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    TextField("Abbreviation", text: binding(\.abbreviation), prompt: Text(";example"))
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .focused($abbreviationFocused)
                        .accessibilityLabel("Abbreviation")
                    AbbreviationNotes(snippet: snippet, library: model.library)
                }
            }
            GridRow {
                Text("Name")
                TextField("Name", text: binding(\.name), prompt: Text("Optional"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Name")
            }
            GridRow {
                Text("Case")
                Picker("Case", selection: binding(\.caseMode)) {
                    Text("Match exactly").tag(CaseMode.exact)
                    Text("Adapt to how it's typed").tag(CaseMode.adapt)
                }
                .labelsHidden()
                .fixedSize()
                .help("Adapt: typing it with a capital capitalises the text; in capitals, the text is in capitals.")
            }
            if model.library.groups.count > 1 {
                GridRow {
                    Text("Group")
                    Picker("Group", selection: binding(\.groupID)) {
                        ForEach(model.library.groups) { group in Text(group.name).tag(group.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Content

    private func content(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text")
                    .font(.headline)
                Spacer()
                PlaceholderMenu { textHandle.insert(PlaceholderParser.token(for: $0)) }
                    .fixedSize()
            }
            ContentTextView(text: binding(\.content), handle: textHandle)
                .frame(minHeight: 140, idealHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
            ContentNotes(model: model, snippet: snippet)
        }
    }

    // MARK: Preview

    private func resolved(_ snippet: Snippet) -> Resolved {
        PlaceholderResolver(now: Date()).resolve(snippet.content) { .text(Self.sampleClipboard) }
    }

    private func preview(_ snippet: Snippet) -> some View {
        let result = resolved(snippet)
        let before = String(result.text.dropLast(result.charactersAfterCursor))
        let after = String(result.text.suffix(result.charactersAfterCursor))
        let hasCursor = PlaceholderParser.parse(snippet.content).contains { if case .placeholder(.cursor, _) = $0 { true } else { false } }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Preview")
                .font(.headline)
            Group {
                if result.text.isEmpty {
                    Text("Nothing yet")
                        .foregroundStyle(.secondary)
                } else {
                    (Text(before) + (hasCursor ? Text("|").foregroundColor(.accentColor).bold() : Text("")) + Text(after))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.s))
            .accessibilityLabel("Preview")
            .accessibilityValue(result.text)
            if PlaceholderResolver.needsClipboard(snippet.content) {
                Text("The preview shows “\(Self.sampleClipboard)” where your clipboard goes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Try it

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Try It")
                .font(.headline)
            TextField("Try it", text: $tryText, prompt: Text("Type the abbreviation here"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Try it")
                .onChange(of: tryText) { old, new in tryExpansion(old: old, new: new) }
            Text(tryNote ?? "Works like typing in any app, without needing permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Runs the real matcher over what was just typed in the field.
    private func tryExpansion(old: String, new: String) {
        guard new.count == old.count + 1, new.hasPrefix(old) else { return }
        let scalars = Array(new.unicodeScalars)
        var buffer = RollingBuffer()
        let start = max(0, scalars.count - RollingBuffer.capacity)
        buffer.reset(beforeIsWord: start > 0 && CharacterClass.isWord(scalars[start - 1].value))
        for scalar in scalars[start...] { buffer.append(scalar.value) }
        let index = model.index
        guard let hit = index.match(buffer, wordStartOnly: model.wordStartOnly),
              let snippet = model.library.snippet(index.entries[hit.entry].snippetID) else {
            tryNote = nil
            return
        }
        let resolved = PlaceholderResolver(now: Date()).resolve(snippet.content, typedCase: hit.typedCase) { .text(Self.sampleClipboard) }
        var kept = String.UnicodeScalarView(scalars.dropLast(hit.length))
        kept.append(contentsOf: resolved.text.replacingOccurrences(of: "\n", with: " ").unicodeScalars)
        tryText = String(kept)
        tryNote = snippet.id == snippetID ? "Expanded." : "Expanded “\(snippet.abbreviation)” from another snippet."
    }
}

/// Under the abbreviation field: what's wrong, or a hint.
struct AbbreviationNotes: View {
    let snippet: Snippet
    let library: Library

    var body: some View {
        if snippet.abbreviation.isEmpty {
            Text("Starting it with ; or another symbol keeps it from expanding inside words.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let problem = AbbreviationRules.validate(snippet.abbreviation) {
            note(AbbreviationRules.message(for: problem), systemImage: "xmark.octagon.fill", color: .red, text: .textRed)
        } else {
            ForEach(ConflictChecker.warnings(for: snippet, in: library), id: \.message) { warning in
                if warning.blocksExpansion {
                    note(warning.message + " Neither expands until then.", systemImage: "exclamationmark.triangle.fill", color: .red, text: .textRed)
                } else {
                    note(warning.message, systemImage: "exclamationmark.triangle", color: .orange, text: .textOrange)
                }
            }
        }
    }

    private func note(_ text: String, systemImage: String, color: Color, text style: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(style)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .font(.caption)
    }
}

/// Under the text: how it will be inserted, and anything that won't work as written.
struct ContentNotes: View {
    @Bindable var model: AppModel
    let snippet: Snippet

    var body: some View {
        let segments = PlaceholderParser.parse(snippet.content)
        let unknown = segments.compactMap { if case .unknown(let raw) = $0 { raw } else { nil } }
        let cursors = segments.filter { if case .placeholder(.cursor, _) = $0 { true } else { false } }.count
        let sample = PlaceholderResolver(now: Date()).resolve(snippet.content) { .text(SnippetEditor.sampleClipboard) }
        let pastes = !snippet.content.isEmpty && InsertionPlanner.method(for: sample.text, mode: model.insertMode) == .paste
        let privacyBlocked = model.pasteboardPrivacy != .allowed
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if snippet.content.isEmpty {
                caption("Snippets with no text don't expand.")
            }
            ForEach(unknown, id: \.self) { raw in
                Label {
                    Text("“\(raw)” isn't a placeholder Shorthand knows, so it's typed as written. For a brace, write {{ or }}.")
                        .foregroundStyle(.textOrange)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .font(.caption)
            }
            if cursors > 1 {
                caption("Only the first cursor position is used.")
            }
            if pastes {
                if privacyBlocked && model.restoreClipboard {
                    PrivacyNote(text: "This snippet is pasted. To put your clipboard back afterwards, allow Shorthand in Paste from Other Apps. Until then, the snippet stays on your clipboard.")
                } else {
                    caption(model.restoreClipboard
                            ? "This one is pasted (it's long or has several lines), then your clipboard is put back."
                            : "This one is pasted (it's long or has several lines) and stays on your clipboard.")
                }
            }
            if PlaceholderResolver.needsClipboard(snippet.content) && privacyBlocked {
                PrivacyNote(text: "The clipboard placeholder stays empty until Shorthand is allowed in Paste from Other Apps.")
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PrivacyNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") { PasteboardPrivacy.openSettings() }
                .controlSize(.small)
        }
    }
}

// MARK: - Text view

/// Lets the editor insert placeholders at the caret.
@MainActor
final class TextViewHandle {
    weak var textView: NSTextView?

    func insert(_ token: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(token, replacementRange: textView.selectedRange())
    }
}

/// An `NSTextView` for snippet text: plain text, system body font, no smart quotes, dashes
/// or macOS text replacements (snippets often hold code), undo, caret-aware inserts.
struct ContentTextView: NSViewRepresentable {
    @Binding var text: String
    let handle: TextViewHandle

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: Spacing.xs, height: Spacing.s)
        textView.string = text
        textView.setAccessibilityLabel("Snippet text")
        handle.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        handle.textView = textView
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
