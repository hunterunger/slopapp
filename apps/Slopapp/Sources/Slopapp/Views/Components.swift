import AppKit
import SlopappCore
import SlopKit
import SwiftUI

/// An app's icon, or a quiet placeholder tile with its initial (planned apps have no icon yet).
struct AppIconView: View {
    let item: CatalogItem
    let icons: Icons
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image = icons.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Text(item.app.name.prefix(1))
                            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(size * 0.09)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The one button that is the state: Install → progress → Open, or Update.
struct ActionButton: View {
    let item: CatalogItem
    @Bindable var store: Store
    var large = false

    var body: some View {
        Group {
            if let operation = store.operations[item.id] {
                progress(operation)
            } else {
                switch item.state {
                case .comingSoon:
                    Text("Coming Soon")
                        .font(large ? .callout : .caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xs)
                        .background(.quaternary, in: Capsule())
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
        .frame(minWidth: large ? 96 : 76, alignment: large ? .leading : .trailing)
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minWidth: large ? 64 : 44)
        }
        .buttonBorderShape(.capsule)
        .controlSize(large ? .large : .small)
        .modifier(ProminentIf(prominent))
    }

    private func progress(_ operation: Operation) -> some View {
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
enum StatusColor {
    static func style(_ color: Color, on prominence: BackgroundProminence) -> AnyShapeStyle {
        prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(color)
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

/// The "Move to Trash" sheet, with the option to remove settings and data too.
struct UninstallSheet: View {
    let item: CatalogItem
    let store: Store
    @State private var removeData = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let running = item.primary.map { RunningApps.isRunning(at: $0.url) } ?? false
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.l) {
                AppIconView(item: item, icons: store.icons, size: 56)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Move \(item.app.name) to the Trash?")
                        .font(.headline)
                    Text(running
                         ? "\(item.app.name) is open. It will quit first. You can put it back from the Trash."
                         : "You can put it back from the Trash.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Also remove its settings and data", isOn: $removeData)
                        .padding(.top, Spacing.xs)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { store.uninstallRequest = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    Task { await store.uninstall(item, removeData: removeData) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}

/// Header row for a page: big title, optional trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
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
