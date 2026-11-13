import Foundation

/// Editing a saved clip's text. The edited version replaces the clip (same id, board, label,
/// source and dates), so it's what pastes from then on.
///
/// Formatting: a clip with RTF or RTFD is edited as formatted text and saved as RTF (RTFD when
/// it holds pictures). Copied HTML can't be edited safely (rendering it could load remote
/// content), so editing a clip whose only formatting is HTML keeps the text and drops the
/// HTML; the editor says so first.
public enum ClipEdit {
    /// Kinds whose text can be edited. Images and files can only be renamed.
    public static func canEditText(_ clip: Clip) -> Bool {
        clip.kind == .text || clip.kind == .link || clip.kind == .color
    }

    /// The full plain text to edit (the clip itself keeps only the first `Clip.textLimit` characters).
    public static func plainText(in payload: ClipPayload?, fallback: String) -> String {
        guard let data = payload?.items.first?.first(where: { $0.type == PasteboardType.string })?.data else { return fallback }
        return String(decoding: data, as: UTF8.self)
    }

    /// The representation to edit as formatted text: RTF, else RTFD. Nil means plain editing.
    public static func richSource(in payload: ClipPayload?, limit: Int = 1_000_000) -> Representation? {
        guard let item = payload?.items.first else { return nil }
        return item.first { $0.type == PasteboardType.rtf && $0.data.count <= limit }
            ?? item.first { $0.type == PasteboardType.rtfd && $0.data.count <= limit }
    }

    /// True when saving an edit loses formatting the clip has (HTML only, or rich text too
    /// large to edit), so the editor can say so.
    public static func dropsFormatting(_ clip: Clip, payload: ClipPayload?) -> Bool {
        clip.hasRichText && richSource(in: payload) == nil
    }

    /// The clip and payload after editing its text to `text`, with `rich` (RTF or RTFD, made
    /// by the editor) when it was edited as formatted text. Nil when the text is empty (an
    /// empty clip pastes nothing) or the clip isn't text.
    public static func apply(text: String, rich: Representation?, to clip: Clip) -> (Clip, ClipPayload)? {
        guard canEditText(clip), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var reps = [Representation(type: PasteboardType.string, data: Data(text.utf8))]
        if let rich { reps.append(rich) }
        let payload = ClipPayload(items: [reps])
        let kind: ClipKind = LinkDetector.isLink(trimmed) ? .link : (ColorValue(hex: trimmed) != nil ? .color : .text)
        // A link's page title only still fits if the link didn't change.
        let title = kind == .link && clip.kind == .link && text == clip.text ? clip.title : nil
        let edited = Clip(id: clip.id, kind: kind, text: text, byteCount: payload.byteCount, hasRichText: rich != nil,
                          sourceBundleID: clip.sourceBundleID, sourceName: clip.sourceName, title: title,
                          created: clip.created, lastUsed: clip.lastUsed, useCount: clip.useCount,
                          boardID: clip.boardID, label: clip.label,
                          fingerprint: "text:" + ClipBuilder.digest(Data(text.utf8)))
        return (edited, payload)
    }
}
