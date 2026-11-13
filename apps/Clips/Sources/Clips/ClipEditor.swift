import AppKit
import ClipsCore
import Observation
import SlopKit
import SwiftUI

/// One edit of a clip: its title, and (for text) its text. Formatted text (RTF/RTFD) is edited
/// with its formatting and saved as RTF; anything else as plain text. Nothing changes until
/// Save, and only what was changed is saved.
@MainActor
@Observable
final class ClipEditSession {
    let clipID: UUID
    var label: String
    let originalLabel: String
    /// Text clips: the text is editable too. Images and files only get a title.
    let editsText: Bool
    /// Put the keyboard in the title field first (⌘R) instead of the text (⌘E).
    let startsInTitle: Bool
    private(set) var isLoading: Bool
    /// The text as loaded (plain, or formatted when the clip has RTF).
    private(set) var plainText = ""
    private(set) var richText: NSAttributedString?
    /// Saving will lose formatting the clip has (HTML only), so the editor says so.
    private(set) var dropsFormatting = false
    /// The editor's text view, to read the edited text from.
    @ObservationIgnored weak var textView: NSTextView?

    init(clip: Clip, startsInTitle: Bool) {
        clipID = clip.id
        label = clip.label ?? ""
        originalLabel = clip.label ?? ""
        editsText = ClipEdit.canEditText(clip)
        self.startsInTitle = startsInTitle || !ClipEdit.canEditText(clip)
        isLoading = ClipEdit.canEditText(clip)
    }

    /// Reads the clip's full text (and formatting) from the history file.
    func load(model: AppModel, clip: Clip) async {
        guard editsText else { return }
        let payload = await model.payload(for: clip.id)
        plainText = ClipEdit.plainText(in: payload, fallback: clip.text)
        // Capped at 1 MB by richSource, like the preview, so parsing here stays quick.
        if let rich = ClipEdit.richSource(in: payload) {
            richText = rich.type == PasteboardType.rtfd ? NSAttributedString(rtfd: rich.data, documentAttributes: nil)
                : NSAttributedString(rtf: rich.data, documentAttributes: nil)
        }
        dropsFormatting = richText == nil && ClipEdit.dropsFormatting(clip, payload: payload)
        isLoading = false
    }

    /// Saves what changed. Returns false when the text is empty (nothing would paste).
    func save(model: AppModel) -> Bool {
        guard let clip = model.history.clip(id: clipID) else { return true }
        if editsText, !isLoading, let textView {
            let edited = textView.attributedString()
            let textChanged: Bool
            if let richText {
                textChanged = !edited.isEqual(to: richText)
            } else {
                textChanged = edited.string != plainText
            }
            if textChanged {
                guard !edited.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                var rich: Representation?
                if richText != nil {
                    let range = NSRange(location: 0, length: edited.length)
                    if edited.containsAttachments, let data = edited.rtfd(from: range, documentAttributes: [:]) {
                        rich = Representation(type: PasteboardType.rtfd, data: data)
                    } else if let data = edited.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                        rich = Representation(type: PasteboardType.rtf, data: data)
                    }
                }
                guard model.saveEdit(of: clip, text: edited.string, rich: rich) else { return false }
            }
        }
        if label != originalLabel { model.setLabel(label, for: clipID) }
        return true
    }
}

/// The editor: a title field and Cancel / Save over the text (or, for images and files, the
/// clip as it is). ⌘S or ⌘Return saves, Esc cancels; Return in the title saves too.
struct ClipEditorView: View {
    @Bindable var session: ClipEditSession
    let clip: Clip
    let onDone: (_ save: Bool) -> Void
    /// Inside the strip's preview the content sits on its own surface; in History it's plain.
    var surfaceRadius: CGFloat?

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                TextField("Title", text: $session.label, prompt: Text("Add a title (\(ClipText.kindName(of: clip)))"))
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit { onDone(true) }
                    .accessibilityLabel("Clip title")
                Button("Cancel") { onDone(false) }
                    .help("Discard changes (Esc)")
                Button("Save") { onDone(true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isLoading)
                    .help("Save changes (⌘S)")
            }
            .controlSize(.small)
            .padding(.horizontal, Spacing.l)
            .frame(height: QuickLookMetrics.headerHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(Surface(radius: surfaceRadius))
            if session.dropsFormatting || session.editsText {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
            }
        }
        .onAppear {
            if session.startsInTitle { titleFocused = true }
        }
    }

    private var footnote: String {
        if session.dropsFormatting { return "This clip's formatting came from a web page. Saving keeps the text but not the formatting." }
        return session.richText != nil ? "The edited text is what pastes. Formatting is kept." : "The edited text is what pastes."
    }

    @ViewBuilder private var content: some View {
        if !session.editsText {
            ClipContentView(clip: clip)
        } else if session.isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EditableTextView(session: session, focus: !session.startsInTitle)
        }
    }

    private struct Surface: ViewModifier {
        let radius: CGFloat?

        func body(content: Content) -> some View {
            if let radius {
                content
                    .environment(\.floatingPanelCornerRadius, radius)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .padding(.horizontal, Spacing.s)
            } else {
                content
            }
        }
    }
}

/// An editable NSTextView: formatted when the clip has RTF, plain otherwise.
private struct EditableTextView: NSViewRepresentable {
    let session: ClipEditSession
    let focus: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: Spacing.l, height: Spacing.l)
        view.setAccessibilityLabel("Clip text")
        if let rich = session.richText {
            view.isRichText = true
            view.importsGraphics = rich.containsAttachments
            view.usesAdaptiveColorMappingForDarkAppearance = true
            view.textStorage?.setAttributedString(rich)
        } else {
            view.isRichText = false
            view.font = .preferredFont(forTextStyle: .body)
            view.textColor = .textColor
            view.string = session.plainText
        }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        session.textView = view
        if focus {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}
}
