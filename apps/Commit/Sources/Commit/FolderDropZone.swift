import AppKit
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// A drop target for one folder, with "or click to choose a folder" (SlopKit's `DropZone`
/// always says "file"). Same look: dashed outline, accent outline and tint while a drop hovers,
/// system focus ring; click, Space or Return opens a folder chooser.
/// Candidate for SlopKit (a `DropZone` option for folder-only targets).
struct FolderDropZone: View {
    let title: String
    let onFolder: (URL) -> Void
    @State private var isTargeted = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        Button(action: choose) {
            VStack(spacing: Spacing.s) {
                Image(systemName: "folder")
                    .font(.largeTitle.weight(.light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.xs) {
                    Text(title).font(.headline)
                    Text("or click to choose a folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.l)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            shape.fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(isHovered ? 0.05 : 0.03))
            shape.strokeBorder(isTargeted ? Color.accentColor : (colorScheme == .dark ? Color.secondary.opacity(0.7) : Color.secondary),
                               style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [6, 5]))
        }
        .overlay {
            if isFocused {
                shape.inset(by: -Spacing.xs / 2)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) { choose(); return .handled }
        .onHover { isHovered = $0 }
        .scaleEffect(isTargeted && !reduceMotion ? 1.01 : 1)
        .animation(.snappy(duration: 0.15), value: isTargeted)
        .accessibilityLabel(title)
        .accessibilityHint("Opens a folder chooser")
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { return false }
            onFolder(folder)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.begin { response in
            if response == .OK, let url = panel.url { onFolder(url) }
        }
    }
}
