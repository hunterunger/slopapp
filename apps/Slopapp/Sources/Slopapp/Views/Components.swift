import AppKit
import SlopappCore
import SlopKit
import SwiftUI

/// An app's icon, or a quiet placeholder tile with its initial (planned apps have no icon yet).
struct AppIconView: View {
    let item: CatalogItem
    let icons: Icons
    var size: CGFloat = 64
    /// Lay out by the tile's art instead of the full icon canvas, so the art (not the
    /// transparent margin around it) sits on the alignment line. The margin still draws.
    var alignsArt = false

    /// macOS icons draw their tile in the middle 824 of a 1024 canvas.
    static func artInset(_ size: CGFloat) -> CGFloat { size * 100 / 1024 }
    static func artSide(_ size: CGFloat) -> CGFloat { size - 2 * artInset(size) }

    var body: some View {
        Group {
            if let image = icons.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                // The same tile as a real icon: its size and corner on the icon grid.
                let side = Self.artSide(size)
                RoundedRectangle(cornerRadius: Radius.iconTile(side: side), style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Text(item.app.name.prefix(1))
                            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Self.artInset(size))
            }
        }
        .frame(width: size, height: size)
        .padding(alignsArt ? -Self.artInset(size) : 0)
        .accessibilityHidden(true)
    }
}

/// Holds a slot exactly as tall as a bordered button of this control size, so whatever
/// takes the button's place (progress, "Coming Soon") doesn't change the row's height.
struct ButtonHeightSlot<Content: View>: View {
    let controlSize: ControlSize
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .leading) {
            Button(" ") {}
                .buttonStyle(.bordered)
                .controlSize(controlSize)
                .frame(width: 0)
                .hidden()
                .accessibilityHidden(true)
            content.frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The one button that is the state: Install → progress → Open, or Update.
struct ActionButton: View {
    enum Size { case card, large }

    let item: CatalogItem
    @Bindable var store: Store
    var size: Size = .card

    private var large: Bool { size == .large }

    var body: some View {
        Group {
            if let operation = store.operations[item.id] {
                ButtonHeightSlot(controlSize: large ? .large : .small) {
                    OperationProgress(item: item, operation: operation, store: store)
                }
            } else {
                switch item.state {
                case .comingSoon:
                    ComingSoonPill(large: large)
                case .notInstalled:
                    let retry = store.errors[item.id]?.isInstallFailure == true
                    button(retry ? "Retry" : "Install", prominent: true) { store.installOrUpdate(item) }
                        .accessibilityLabel(retry ? "Retry installing \(item.app.name)" : "Install \(item.app.name)")
                case .updateAvailable:
                    let retry = store.errors[item.id]?.isInstallFailure == true
                    button(retry ? "Retry" : "Update", prominent: true) { store.installOrUpdate(item) }
                        .accessibilityLabel(retry ? "Retry updating \(item.app.name)" : "Update \(item.app.name)")
                case .installed:
                    button("Open", prominent: false) { store.open(item) }
                        .accessibilityLabel("Open \(item.app.name)")
                }
            }
        }
        .fixedSize()
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minWidth: large ? 72 : 48)
        }
        .buttonBorderShape(.capsule)
        .controlSize(large ? .large : .small)
        .modifier(ProminentIf(prominent))
    }
}

/// "Downloading 42%" with a ring and a Cancel button, in place of the state button.
struct OperationProgress: View {
    let item: CatalogItem
    let operation: Operation
    let store: Store

    var body: some View {
        HStack(spacing: Spacing.s) {
            if case .downloading(let p) = operation, p > 0 {
                ProgressView(value: p)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(operation.label)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            if operation.canCancel {
                Button {
                    store.cancel(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Cancel installing \(item.app.name)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.app.name): \(operation.label)")
    }
}

/// Where a planned app's button would be: a quiet capsule exactly the button's height.
struct ComingSoonPill: View {
    var large = false

    var body: some View {
        ButtonHeightSlot(controlSize: large ? .large : .small) {
            Text("Coming Soon")
                .font(large ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, large ? Spacing.l : Spacing.m)
                .frame(maxHeight: .infinity)
                // Lighter than a button's fill: it isn't one, and secondary text keeps its
                // contrast on it (3.8:1 on the button grey in light mode).
                .background(.quinary, in: Capsule())
        }
    }
}

private struct ProminentIf: ViewModifier {
    let prominent: Bool
    init(_ prominent: Bool) { self.prominent = prominent }

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// The last failure for an app, under its button.
struct ErrorLine: View {
    let message: String?
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(StatusColor.style(.red, on: prominence))
                .symbolRenderingMode(prominence == .increased ? .monochrome : .multicolor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// "Reinstalled version 1.1.0." under an app's button for a few seconds after it changed.
struct NoticeLine: View {
    let message: String?
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(StatusColor.style(.green, on: prominence))
                .transition(.opacity)
        }
    }
}

/// Status colors stay readable on a selected (accent-filled) row: there they turn primary.
/// Elsewhere they're SlopKit's readable variants (darkened in light mode so they pass contrast).
enum StatusColor {
    enum Tone { case red, orange, green }

    static func style(_ tone: Tone, on prominence: BackgroundProminence) -> AnyShapeStyle {
        guard prominence != .increased else { return AnyShapeStyle(.primary) }
        switch tone {
        case .red: return AnyShapeStyle(Color.textRed)
        case .orange: return AnyShapeStyle(Color.textOrange)
        case .green: return AnyShapeStyle(Color.textGreen)
        }
    }
}

/// "Unsigned development build" and friends, for a copy on disk.
struct SignatureBadge: View {
    let copy: InstalledCopy?
    let policy: SignaturePolicy
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if let label = policy.label(for: copy?.signature) {
            Label(label, systemImage: label.hasPrefix("Damaged") ? "xmark.seal" : "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(StatusColor.style(label.hasPrefix("Damaged") ? .red : .orange, on: prominence))
                .help(label.hasPrefix("Damaged")
                      ? "This copy's code signature doesn't match its contents. Reinstall it."
                      : "This build isn't signed with an Apple Developer ID. Slopapp checked its download against the catalog's checksum.")
        }
    }
}

/// "~/Applications/Slopapp/Awake.app" instead of the full home path.
func displayPath(_ url: URL) -> String {
    let home = NSHomeDirectory()
    let path = url.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

func relativeDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter.string(from: date)
}
