import Foundation

/// Several clips as one paste. They go in the order they were copied (oldest first), which is
/// the order you'd read them in:
///
/// - all files: every file, so Finder pastes them all;
/// - all images: every image, as separate items (apps that take several images get them all);
/// - anything else: plain text, one clip per line. Images have no text and are left out;
///   files paste as their paths.
public enum ClipJoin {
    /// `clips` in any order; returns them oldest first (by last use, as the strip shows them).
    public static func chronological(_ clips: [Clip]) -> [Clip] {
        clips.sorted { $0.lastUsed != $1.lastUsed ? $0.lastUsed < $1.lastUsed : $0.created < $1.created }
    }

    /// The plain text of several clips, oldest first, one per line. Nil if none has text.
    public static func text(of clips: [Clip], payloads: [UUID: ClipPayload] = [:]) -> String? {
        let parts = chronological(clips).compactMap { clip -> String? in
            guard clip.kind != .image else { return nil }
            // The stored clip text is capped; the payload has all of it.
            if let payload = payloads[clip.id], clip.kind != .file,
               let data = payload.items.first?.first(where: { $0.type == PasteboardType.string })?.data {
                return String(decoding: data, as: UTF8.self)
            }
            return clip.text
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// What pasting `clips` together puts on the pasteboard. `payloads` holds each clip's
    /// stored content (needed for images and for the full text of long clips).
    public static func payload(for clips: [Clip], payloads: [UUID: ClipPayload]) -> ClipPayload? {
        let ordered = chronological(clips)
        guard !ordered.isEmpty else { return nil }
        if ordered.allSatisfy({ $0.kind == .file }) {
            var seen = Set<String>()
            var items: [[Representation]] = []
            for clip in ordered {
                for item in payloads[clip.id]?.items ?? [] {
                    guard let rep = item.first(where: { $0.type == PasteboardType.fileURL }),
                          seen.insert(String(decoding: rep.data, as: UTF8.self)).inserted else { continue }
                    items.append([rep])
                }
            }
            return items.isEmpty ? nil : ClipPayload(items: items)
        }
        if ordered.allSatisfy({ $0.kind == .image }) {
            let items = ordered.compactMap { payloads[$0.id]?.items.first }
            return items.isEmpty ? nil : ClipPayload(items: items)
        }
        guard let text = text(of: ordered, payloads: payloads) else { return nil }
        return ClipPayload(items: [[Representation(type: PasteboardType.string, data: Data(text.utf8))]])
    }

    /// A short description for menus and HUDs: "3 clips", "2 images", "4 files".
    public static func describe(_ clips: [Clip]) -> String {
        let count = clips.count
        if count > 0, clips.allSatisfy({ $0.kind == .image }) { return count == 1 ? "1 image" : "\(count) images" }
        if count > 0, clips.allSatisfy({ $0.kind == .file }) {
            let files = clips.reduce(0) { $0 + max(1, $1.filePaths.count) }
            return files == 1 ? "1 file" : "\(files) files"
        }
        return count == 1 ? "1 clip" : "\(count) clips"
    }
}
