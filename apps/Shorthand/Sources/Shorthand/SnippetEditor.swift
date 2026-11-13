import AppKit
import ShorthandCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// The detail pane: abbreviation (with conflict notes), name, case, group, format, the text
/// with an Insert Placeholder menu (and a formatting bar for formatted snippets), a live
/// preview and a "Try it" field. Saves as you type.
struct SnippetEditor: View {
    @Bindable var model: AppModel
    let snippetID: UUID
    let focusAbbreviation: Int
    @State private var textHandle = TextViewHandle()
    @State private var tryText = ""
    @State private var tryNote: String?
    @State private var tryForm: FillInState?
    @State private var confirmPlain = false
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
            .focusedSceneValue(\.placeholderInserter, { textHandle.insert($0) })
            .onAppear { if snippet.abbreviation.isEmpty { abbreviationFocused = true } }
            .onChange(of: focusAbbreviation) { _, _ in abbreviationFocused = true }
            .confirmationDialog("Make this snippet plain text?", isPresented: $confirmPlain) {
                Button("Make Plain Text", role: .destructive) { setFormatted(false, confirmed: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its formatting and images are removed. The text and placeholders stay.")
            }
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
            GridRow {
                Text("Format")
                Picker("Format", selection: Binding(get: { snippet.isFormatted }, set: { setFormatted($0) })) {
                    Text("Plain text").tag(false)
                    Text("Formatted text").tag(true)
                }
                .labelsHidden()
                .fixedSize()
                .help("Formatted text keeps fonts, styles, links and images, and is pasted. Apps that only take plain text get the text alone.")
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

    /// Plain ↔ formatted. Going plain asks first when there's formatting or an image to lose.
    private func setFormatted(_ formatted: Bool, confirmed: Bool = false) {
        guard var snippet = model.library.snippet(snippetID), snippet.isFormatted != formatted else { return }
        if formatted {
            snippet.richText = RichText.encode(RichText.make(fromPlain: snippet.content))
        } else {
            let rich = snippet.richText.flatMap(RichText.decode)
            if !confirmed, let rich, RichText.hasFormatting(rich) || snippet.content.contains(attachmentCharacter) {
                confirmPlain = true
                return
            }
            snippet.content = snippet.plainContent
            snippet.richText = nil
        }
        model.update(snippet)
    }

    // MARK: Content

    private func content(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text")
                    .font(.headline)
                Spacer()
                PlaceholderMenu(snippets: model.library.snippets.filter { $0.id != snippetID }) { textHandle.insert($0) }
                    .fixedSize()
            }
            if snippet.isFormatted {
                FormatBar(handle: textHandle)
            }
            ContentTextView(text: binding(\.content), formatted: snippet.isFormatted ? model.formattedText(snippetID) : nil,
                            onFormattedChange: { text in updateFormatted(text) }, handle: textHandle)
                .id(snippet.isFormatted)
                .frame(minHeight: 140, idealHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
            ContentNotes(model: model, snippet: snippet)
        }
    }

    private func updateFormatted(_ text: NSAttributedString) {
        guard var snippet = model.library.snippet(snippetID) else { return }
        snippet.content = RichText.plain(text)
        snippet.richText = RichText.encode(text)
        model.update(snippet)
    }

    // MARK: Preview

    /// Fill-ins at their defaults; an empty field shows its name.
    private func previewValues(_ snippet: Snippet) -> FillValues {
        var values = FillValues()
        for field in FillIn.fields(for: snippet, lookup: model.library.lookup) {
            if case .text(let value) = field.kind, value.isEmpty { values[field.name] = .text("‹\(field.name)›") }
        }
        return values
    }

    private func resolved(_ snippet: Snippet) -> Resolved {
        PlaceholderResolver(now: Date()).resolve(snippet, values: previewValues(snippet), lookup: model.library.lookup) {
            .text(Self.sampleClipboard)
        }
    }

    private func preview(_ snippet: Snippet) -> some View {
        let result = resolved(snippet)
        let before = String(result.text.dropLast(result.charactersAfterCursor))
        let after = String(result.text.suffix(result.charactersAfterCursor))
        let hasCursor = result.pieces.count > 0 && PlaceholderParser.parse(snippet.content).contains { if case .placeholder(.cursor, _) = $0 { true } else { false } }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Preview")
                .font(.headline)
            Group {
                if result.pieces.isEmpty {
                    Text("Nothing yet")
                        .foregroundStyle(.secondary)
                } else if result.isFormatted {
                    FormattedPreview(text: RichText.assemble(result) { model.formattedText($0) })
                } else {
                    (Text(before) + (hasCursor ? Text("|").foregroundColor(.accentColor).bold() : Text("")) + Text(after))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.s))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview")
            .accessibilityValue(result.text)
            if PlaceholderResolver.needsClipboard(snippet, lookup: model.library.lookup) {
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
                .sheet(isPresented: Binding(get: { tryForm != nil }, set: { if !$0 { tryForm = nil } })) {
                    if let tryForm { FillInForm(state: tryForm, showsKeyHints: false) }
                }
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
        let kept = String(String.UnicodeScalarView(scalars.dropLast(hit.length)))
        let note = snippet.id == snippetID ? "Expanded." : "Expanded “\(snippet.abbreviation)” from another snippet."
        let lookup = model.library.lookup
        let fields = FillIn.fields(for: snippet, lookup: lookup)
        func finish(_ values: FillValues) {
            let resolved = PlaceholderResolver(now: Date()).resolve(snippet, typedCase: hit.typedCase, values: values, lookup: lookup) {
                .text(Self.sampleClipboard)
            }
            tryText = kept + resolved.text.replacingOccurrences(of: "\n", with: " ")
            tryNote = note
        }
        guard !fields.isEmpty else { return finish(FillValues()) }
        // The same form as in other apps, right here.
        let state = FillInState(title: snippet.title, fields: fields) { values in
            PlaceholderResolver(now: Date()).resolve(snippet, values: values, lookup: lookup) { .text(Self.sampleClipboard) }.text
        }
        state.onInsert = { values in
            tryForm = nil
            finish(values)
        }
        state.onCancel = {
            tryForm = nil
            tryNote = "Cancelled: the abbreviation stays as typed."
        }
        tryForm = state
    }
}

/// Bold, italic, underline, fonts, colours and an image, for formatted snippets. The Format
/// menu has the same commands with their shortcuts.
struct FormatBar: View {
    let handle: TextViewHandle

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ControlGroup {
                Button { handle.toggle(.boldFontMask) } label: { Label("Bold", systemImage: "bold") }
                    .help("Bold (⌘B)")
                Button { handle.toggle(.italicFontMask) } label: { Label("Italic", systemImage: "italic") }
                    .help("Italic (⌘I)")
                Button { handle.underline() } label: { Label("Underline", systemImage: "underline") }
                    .help("Underline (⌘U)")
            }
            .fixedSize()
            Button { handle.showFonts() } label: { Label("Fonts", systemImage: "textformat") }
                .help("Show Fonts (⌘T)")
            Button { handle.showColors() } label: { Label("Colours", systemImage: "paintpalette") }
                .help("Show Colours (⇧⌘C)")
            Button { handle.insertImage() } label: { Label("Insert Image…", systemImage: "photo") }
                .help("Insert an image (or paste or drop one into the text)")
            Spacer()
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }
}

/// A formatted preview with images, sized to its content (up to a limit).
struct FormattedPreview: NSViewRepresentable {
    let text: NSAttributedString
    static let maxHeight: CGFloat = 240

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.usesAdaptiveColorMappingForDarkAppearance = true
        view.setAccessibilityLabel("Preview")
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        if view.attributedString() != text { view.textStorage?.setAttributedString(text) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height
        return CGSize(width: width, height: min(Self.maxHeight, max(height, 17)))
    }
}

/// Under the abbreviation field: what's wrong, or a hint.
struct AbbreviationNotes: View {
    let snippet: Snippet
    let library: Library

    var body: some View {
        if snippet.abbreviation.isEmpty {
            Text("Starting it with ; or another symbol keeps it from expanding inside words. Without one, it's only in the search panel.")
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
        let lookup = model.library.lookup
        let segments = PlaceholderParser.parse(snippet.content)
        let unknown = segments.compactMap { if case .unknown(let raw) = $0 { raw } else { nil } }
        let cursors = segments.filter { if case .placeholder(.cursor, _) = $0 { true } else { false } }.count
        let sample = PlaceholderResolver(now: Date()).resolve(snippet, lookup: lookup) { .text(SnippetEditor.sampleClipboard) }
        let pastes = !snippet.content.isEmpty && (sample.isFormatted || InsertionPlanner.method(for: sample.text, mode: model.insertMode) == .paste)
        let privacyBlocked = model.pasteboardPrivacy != .allowed
        let fields = FillIn.fields(for: snippet, lookup: lookup)
        let notes = TemplateCheck.notes(for: snippet, lookup: lookup)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if snippet.content.isEmpty {
                caption("Snippets with no text don't expand.")
            }
            ForEach(unknown, id: \.self) { raw in
                warning("“\(raw)” isn't a placeholder Shorthand knows, so it's typed as written. For a brace, write {{ or }}.")
            }
            ForEach(notes, id: \.self) { note in warning(note.message) }
            if cursors > 1 {
                caption("Only the first cursor position is used.")
            }
            if !fields.isEmpty {
                caption(fields.count == 1 ? "Asks for 1 fill-in when it expands." : "Asks for \(fields.count) fill-ins when it expands.")
            }
            if pastes {
                if privacyBlocked && model.restoreClipboard {
                    PrivacyNote(text: "This snippet is pasted. To put your clipboard back afterwards, allow Shorthand in Paste from Other Apps. Until then, the snippet stays on your clipboard.")
                } else if sample.isFormatted {
                    let why = snippet.isFormatted ? "Formatted snippets are pasted" : "It includes formatted text, so it's pasted"
                    caption(model.restoreClipboard
                            ? "\(why), then your clipboard is put back. Apps that only take plain text get the text alone."
                            : "\(why) and stays on your clipboard. Apps that only take plain text get the text alone.")
                } else {
                    caption(model.restoreClipboard
                            ? "This one is pasted (it's long or has several lines), then your clipboard is put back."
                            : "This one is pasted (it's long or has several lines) and stays on your clipboard.")
                }
            }
            if PlaceholderResolver.needsClipboard(snippet, lookup: lookup) && privacyBlocked {
                PrivacyNote(text: "The clipboard placeholder stays empty until Shorthand is allowed in Paste from Other Apps.")
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.textOrange)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        .font(.caption)
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

/// Lets the editor insert placeholders at the caret and format the selection.
@MainActor
final class TextViewHandle {
    weak var textView: NSTextView? { didSet { if textView != nil { Self.current = self } } }
    /// The editor showing now (test hooks).
    static weak var current: TextViewHandle?

    func insert(_ token: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.insertText(token, replacementRange: textView.selectedRange())
    }

    /// Inserts a placeholder; fill-ins come with their name selected, ready to type over, and
    /// an optional section wraps the selected text.
    func insert(_ placeholder: Placeholder) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let selection = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: selection)
        let token: String
        var select: NSRange?
        switch placeholder {
        case .field(let name, _):
            token = "{field:\(name)}"
            select = NSRange(location: 7, length: (name as NSString).length)
        case .choice(let name, _):
            token = PlaceholderParser.token(for: placeholder)
            select = NSRange(location: 8, length: (name as NSString).length)
        case .optionalStart(let name, _):
            let body = selected.isEmpty ? "Text" : selected
            token = PlaceholderParser.token(for: placeholder) + body + "{/optional}"
            select = NSRange(location: ("{optional:" as NSString).length, length: (name as NSString).length)
        default:
            token = PlaceholderParser.token(for: placeholder)
        }
        textView.insertText(token, replacementRange: selection)
        if let select { textView.setSelectedRange(NSRange(location: selection.location + select.location, length: select.length)) }
    }

    /// Bold or italic on the selection (or what's typed next).
    func toggle(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        textView.window?.makeFirstResponder(textView)
        let manager = NSFontManager.shared
        let range = textView.selectedRange()
        let current = (range.length > 0 ? storage.attribute(.font, at: range.location, effectiveRange: nil)
                       : textView.typingAttributes[.font]) as? NSFont ?? RichText.baseFont
        let adding = !manager.traits(of: current).contains(trait)
        func convert(_ font: NSFont) -> NSFont {
            adding ? manager.convert(font, toHaveTrait: trait) : manager.convert(font, toNotHaveTrait: trait)
        }
        guard range.length > 0 else {
            textView.typingAttributes[.font] = convert(current)
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            storage.addAttribute(.font, value: convert(value as? NSFont ?? RichText.baseFont), range: run)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func underline() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.underline(nil)
    }

    func showFonts() {
        textView.map { $0.window?.makeFirstResponder($0) }
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    func showColors() {
        textView.map { $0.window?.makeFirstResponder($0) }
        NSApp.orderFrontColorPanel(nil)
    }

    func insertImage() {
        guard let textView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to put in this snippet."
        guard panel.runModal() == .OK, let url = panel.url, let image = RichText.image(at: url) else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: image.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: image)
        textView.didChangeText()
    }
}

/// An `NSTextView` for snippet text: system body font, no smart quotes, dashes or macOS text
/// replacements (snippets often hold code), undo, caret-aware inserts. Plain text, or
/// formatted text with images (pasted, dropped or inserted) when `formatted` is set.
struct ContentTextView: NSViewRepresentable {
    @Binding var text: String
    /// The formatted text to edit (nil: a plain-text snippet).
    var formatted: NSAttributedString?
    var onFormattedChange: (NSAttributedString) -> Void = { _ in }
    let handle: TextViewHandle

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onFormattedChange: onFormattedChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: Spacing.xs, height: Spacing.s)
        if let formatted {
            context.coordinator.formatted = true
            textView.isRichText = true
            textView.importsGraphics = true
            textView.allowsImageEditing = true
            textView.usesFontPanel = true
            textView.usesAdaptiveColorMappingForDarkAppearance = true
            textView.textStorage?.setAttributedString(formatted)
            textView.typingAttributes = formatted.length > 0 ? formatted.attributes(at: formatted.length - 1, effectiveRange: nil).filter { $0.key != .attachment }
                : RichText.baseAttributes
            textView.setAccessibilityLabel("Snippet text, formatted")
        } else {
            textView.isRichText = false
            textView.importsGraphics = false
            textView.font = .preferredFont(forTextStyle: .body)
            textView.textColor = .labelColor
            textView.string = text
            textView.setAccessibilityLabel("Snippet text")
        }
        handle.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onFormattedChange = onFormattedChange
        // Formatted text is only ever changed here, by typing; plain text can change from
        // outside (placeholders from the menu bar's Snippet menu go through the view anyway).
        if formatted == nil, textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        handle.textView = textView
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onFormattedChange: (NSAttributedString) -> Void
        var formatted = false

        init(text: Binding<String>, onFormattedChange: @escaping (NSAttributedString) -> Void) {
            self.text = text
            self.onFormattedChange = onFormattedChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if formatted, let storage = textView.textStorage {
                RichText.compactImages(in: storage)
                onFormattedChange(NSAttributedString(attributedString: storage))
            } else {
                text.wrappedValue = textView.string
            }
        }
    }
}
