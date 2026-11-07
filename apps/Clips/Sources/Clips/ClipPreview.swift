import AppKit
import ClipsCore
import SlopKit
import SwiftUI

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
            LinkPreview(text: clip.text.trimmingCharacters(in: .whitespacesAndNewlines), title: clip.title)
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
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(host).font(.title3.weight(.semibold)).lineLimit(1)
            } icon: {
                Image(systemName: "link").symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            }
            if let title {
                Text(title).font(.body.weight(.medium)).lineLimit(3)
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

    private var host: String { ClipText.host(ofLink: text) }
}

private struct ColorPreview: View {
    let text: String

    var body: some View {
        VStack(spacing: Spacing.m) {
            if let color = ColorValue(hex: text) {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
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
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    var body: some View {
        Group {
            if let image = image ?? ImageCache.shared.cachedPreview(for: clip.id) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Concentric with the surface it sits on, `Spacing.l` in.
                    .clipShape(RoundedRectangle(cornerRadius: Radius.nested(in: panelRadius, padding: Spacing.l, minimum: Radius.s),
                                                style: .continuous))
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
                            // "Not found" sits on the name's baseline, as on the card.
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                Text((path as NSString).lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !FileManager.default.fileExists(atPath: path) {
                                    Text("Not found")
                                        .font(.caption)
                                        .foregroundStyle(.textOrange)
                                        .fixedSize()
                                }
                            }
                            Text((path as NSString).deletingLastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
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
            // Text starts Spacing.l in, like the plain-text preview (no extra line padding).
            view.textContainer?.lineFragmentPadding = 0
            view.textContainerInset = NSSize(width: Spacing.l, height: Spacing.l)
            view.setAccessibilityLabel("Clip text")
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.attributedString() != text else { return }
        view.textStorage?.setAttributedString(text)
    }
}
