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
    @FocusState private var isFocused: Bool
    @Environment(\.dropZoneCornerRadius) private var cornerRadius

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
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(.title3)
                    Text(allowsMultiple ? "or click to choose files" : "or click to choose a file")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.xxl)
        }
        .buttonStyle(DropZoneStyle(isTargeted: isTargeted, isFocused: isFocused, cornerRadius: cornerRadius))
        .focused($isFocused)
        .focusEffectDisabled() // DropZoneStyle draws a rounded focus ring instead
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

/// The drop zone's look in every state: idle (dashed outline), hover (a touch more fill),
/// pressed, drop-targeted (solid accent outline and tint) and keyboard focus (the system
/// focus ring, following the rounded shape instead of a square).
struct DropZoneStyle: ButtonStyle {
    let isTargeted: Bool
    let isFocused: Bool
    let cornerRadius: CGFloat
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.colorScheme) private var colorScheme

    /// Fill opacity of `.primary` by state. Subtle on purpose: the outline carries the shape.
    static func fillOpacity(pressed: Bool, hovered: Bool) -> Double {
        pressed ? 0.08 : hovered ? 0.05 : 0.03
    }

    /// The dashed outline: `.secondary`, toned down in dark mode where it's brighter. Both
    /// measure 3:1 or better against the fill (design system §4, meaningful UI).
    static func outlineColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.secondary.opacity(0.7) : Color.secondary
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background {
                shape.fill(isTargeted
                           ? Color.accentColor.opacity(0.1)
                           : Color.primary.opacity(Self.fillOpacity(pressed: configuration.isPressed, hovered: isHovered)))
                GeometryReader { proxy in
                    shape.strokeBorder(isTargeted ? Color.accentColor : Self.outlineColor(colorScheme),
                                       style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5,
                                                          dash: isTargeted ? [] : DashPattern.fitted(dash: 6, gap: 5, size: proxy.size,
                                                                                                     cornerRadius: cornerRadius, lineWidth: 1.5)))
                }
            }
            .overlay {
                if isFocused && !isTargeted {
                    shape.inset(by: -Spacing.xs / 2)
                        .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .scaleEffect(isTargeted && !reduceMotion ? 1.01 : 1)
            .animation(.snappy(duration: 0.15), value: isTargeted)
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Dash patterns that fit a rounded rectangle's outline a whole number of times, so the
/// dashes meet evenly where the path starts and ends instead of leaving a stub.
enum DashPattern {
    static func fitted(dash: CGFloat, gap: CGFloat, size: CGSize, cornerRadius: CGFloat, lineWidth: CGFloat) -> [CGFloat] {
        let perimeter = self.perimeter(size: size, cornerRadius: cornerRadius, inset: lineWidth / 2)
        let period = dash + gap
        guard perimeter > period else { return [dash, gap] }
        let scale = perimeter / (perimeter / period).rounded() / period
        return [dash * scale, gap * scale]
    }

    /// The length of a rounded rectangle's outline, inset by `inset` (where a stroke border
    /// of twice that width runs).
    static func perimeter(size: CGSize, cornerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        let width = max(size.width - inset * 2, 0), height = max(size.height - inset * 2, 0)
        let radius = min(max(cornerRadius - inset, 0), min(width, height) / 2)
        return 2 * (width + height) - (8 - 2 * .pi) * radius
    }
}

extension EnvironmentValues {
    @Entry var dropZoneCornerRadius: CGFloat = Radius.l
}

public extension View {
    /// The corner radius of `DropZone`s (and `FileQueueView`'s empty state) inside this view.
    /// Default `Radius.l`. Set it when the drop zone sits inside another rounded shape, to
    /// keep the corners concentric: `.dropZoneCornerRadius(Radius.nested(in: Radius.xl, padding: Spacing.s))`.
    func dropZoneCornerRadius(_ radius: CGFloat) -> some View {
        environment(\.dropZoneCornerRadius, radius)
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
