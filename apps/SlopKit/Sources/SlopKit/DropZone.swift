import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The empty state of a drop-in utility: a big target that takes dropped files or opens a
/// file chooser when clicked (or Space/Return when focused).
///
///     DropZone("Drop images here", types: [.image]) { urls in queue.add(urls) }
///
/// Include `.folder` in `types` to accept folders, both dropped and in the chooser.
public struct DropZone: View {
    let title: String
    let systemImage: String
    let types: [UTType]
    let allowsMultiple: Bool
    let onFiles: ([URL]) -> Void

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String = "Drop files here",
        systemImage: String = "arrow.down.doc",
        types: [UTType] = [.item],
        allowsMultiple: Bool = true,
        onFiles: @escaping ([URL]) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.types = types
        self.allowsMultiple = allowsMultiple
        self.onFiles = onFiles
    }

    public var body: some View {
        Button(action: chooseFiles) {
            VStack(spacing: Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(title)
                    .font(.title3)
                Text(allowsMultiple ? "or click to choose files" : "or click to choose a file")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.xxl)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [6, 5]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isTargeted && !reduceMotion ? 1.01 : 1)
            .animation(.snappy(duration: 0.15), value: isTargeted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Opens a file chooser")
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = DropFilter.accepted(urls, types: types)
            guard !accepted.isEmpty else { return false }
            onFiles(allowsMultiple ? accepted : [accepted[0]])
            return true
        } isTargeted: { isTargeted = $0 }
    }

    /// Whether these types let the chooser pick folders.
    static func acceptsFolders(_ types: [UTType]) -> Bool {
        types.contains { $0 == .folder || $0 == .directory }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = Self.acceptsFolders(types)
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK, !panel.urls.isEmpty { onFiles(panel.urls) }
        }
    }
}

/// Which dropped files a drop zone accepts. Pure, so it's tested.
public enum DropFilter {
    public static func accepted(_ urls: [URL], types: [UTType]) -> [URL] {
        urls.filter { url in
            guard let type = contentType(of: url) else { return types.contains(.item) }
            return types.contains { type.conforms(to: $0) }
        }
    }

    static func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return url.pathExtension.isEmpty ? nil : UTType(filenameExtension: url.pathExtension)
    }
}
