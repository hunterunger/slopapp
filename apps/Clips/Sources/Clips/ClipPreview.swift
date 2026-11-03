import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The selected clip, big enough to recognise, with where it came from and what you can do.
struct ClipPreview: View {
    let clip: Clip
    let now: Date
    /// "Paste" or "Copy", for the main button.
    let pasteLabel: String
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            ClipContentView(clip: clip)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack(spacing: Spacing.s) {
                ClipSourceLine(clip: clip, now: now)
                Spacer(minLength: Spacing.s)
                Button {
                    actions.togglePin(clip)
                } label: {
                    Image(systemName: clip.isPinned ? "pin.slash" : "pin")
                }
                .help(clip.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")
                .accessibilityLabel(clip.isPinned ? "Unpin" : "Pin")
                Button {
                    actions.delete(clip)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete (⌘⌫)")
                .accessibilityLabel("Delete")
                if pasteLabel != "Copy" {
                    Button("Copy") { actions.copy(clip) }
                        .help("Copy to the clipboard (⌘C)")
                }
                Button(pasteLabel) { actions.choose(clip, false) }
                    .buttonStyle(.borderedProminent)
                    .help(pasteLabel == "Paste" ? "Paste into the app you were using (Return)" : "Copy to the clipboard (Return)")
            }
            .controlSize(.small)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
    }
}

/// "From Safari · 5 min ago · 2 lines · 84 characters"
struct ClipSourceLine: View {
    let clip: Clip
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let id = clip.sourceBundleID, let icon = AppIcons.icon(for: id) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        var parts: [String] = []
        if let source = clip.sourceName { parts.append(source) }
        parts.append(ClipText.ageSentence(of: clip.lastUsed, now: now))
        parts.append(ClipText.details(of: clip))
        if clip.hasRichText { parts.append("Formatted") }
        return parts.joined(separator: " · ")
    }
}

/// The clip's content: text, link, color swatch, image or files.
struct ClipContentView: View {
    let clip: Clip

    var body: some View {
        switch clip.kind {
        case .text:
            TextPreview(clip: clip)
        case .link:
            LinkPreview(text: clip.text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .color:
            ColorPreview(text: clip.text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .image:
            ImagePreview(clip: clip)
        case .file:
            FilesPreview(paths: clip.filePaths)
        }
    }
}

private struct LinkPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(host).font(.title3.weight(.semibold)).lineLimit(1)
            } icon: {
                Image(systemName: "link").symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var host: String {
        if let url = URL(string: text), let host = url.host(percentEncoded: false) {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if text.lowercased().hasPrefix("mailto:") { return String(text.dropFirst(7)) }
        return text
    }
}

private struct ColorPreview: View {
    let text: String

    var body: some View {
        VStack(spacing: Spacing.m) {
            if let color = ColorValue(hex: text) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                    .frame(width: 140, height: 140)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.title3.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ImagePreview: View {
    let clip: Clip
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? ImageCache.shared.cachedPreview(for: clip.id) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("Image, \(clip.imageWidth) by \(clip.imageHeight) pixels")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: clip.id) {
            image = nil
            image = await ImageCache.shared.preview(for: clip)
        }
    }
}

private struct FilesPreview: View {
    let paths: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(paths.prefix(200), id: \.self) { path in
                    HStack(spacing: Spacing.s) {
                        Image(nsImage: AppIcons.icon(forFile: path))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text((path as NSString).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text((path as NSString).deletingLastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if !FileManager.default.fileExists(atPath: path) {
                            Text("Missing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Plain text, or the formatted version when the clip carries RTF (TextEdit, Notes, Pages,
/// Mail…). HTML isn't rendered: AppKit's HTML import can fetch remote images, and Clips
/// never touches the network.
private struct TextPreview: View {
    let clip: Clip
    @State private var rich: NSAttributedString?
    @State private var richID: UUID?

    /// Larger RTF is shown as plain text (parsing it would stall the panel).
    static let richLimit = 1_000_000

    var body: some View {
        Group {
            if let rich, richID == clip.id {
                RichTextView(text: rich)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(clip.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if clip.isTruncated {
                            Text("Showing the first \(Clip.textLimit.formatted()) of \(clip.textLength.formatted()) characters. The whole text is pasted."
                                 + (clip.isSearchTruncated ? " Search covers the first \(Clip.searchLimit.formatted()) characters." : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(Spacing.l)
                }
            }
        }
        .task(id: clip.id) {
            guard clip.hasRichText else { rich = nil; return }
            let id = clip.id
            guard let payload = await AppModel.shared.payload(for: id), id == clip.id else { return }
            let reps = payload.items.first ?? []
            var text: NSAttributedString?
            if let rtf = reps.first(where: { $0.type == PasteboardType.rtf }), rtf.data.count <= Self.richLimit {
                text = NSAttributedString(rtf: rtf.data, documentAttributes: nil)
            } else if let rtfd = reps.first(where: { $0.type == PasteboardType.rtfd }), rtfd.data.count <= Self.richLimit {
                text = NSAttributedString(rtfd: rtfd.data, documentAttributes: nil)
            }
            rich = text
            richID = text == nil ? nil : id
        }
    }
}

/// A read-only, selectable text view for formatted text. Colors adapt to Dark Mode.
private struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.usesAdaptiveColorMappingForDarkAppearance = true
            view.textContainerInset = NSSize(width: Spacing.m, height: Spacing.l)
            view.setAccessibilityLabel("Clip text")
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.attributedString() != text else { return }
        view.textStorage?.setAttributedString(text)
    }
}
