import CrateCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// The window: a drop zone, an open archive, a new archive, or the extraction queue.
struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            switch model.screen {
            case .empty:
                DropZone("Drop an archive to open it, or files to compress", systemImage: "archivebox",
                         types: [.item, .folder]) { model.open($0) }
                    .padding(Spacing.windowMargin)
                    .navigationTitle("Crate")
            case .browse(let browse):
                BrowseView(model: browse)
            case .create(let create):
                CreateView(model: create)
            case .queue:
                QueueView(model: model)
            }
        }
        // 540: the narrowest width where the browse toolbar (title, Close, Split, Convert,
        // Extract, Filter) fits without sending Extract to the overflow menu.
        .frame(minWidth: 540, minHeight: 340)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .sheet(item: queuePasswordRequest) { request in
            PasswordEntrySheet(
                fileName: request.url.lastPathComponent, wrong: request.wrong, checking: false,
                remember: $model.settings.rememberPasswords,
                onSubmit: { model.answerPassword($0, for: request) },
                onCancel: { model.answerPassword(nil, for: request) }
            )
        }
    }

    private var queuePasswordRequest: Binding<PasswordRequest?> {
        Binding(
            get: {
                if case .queue = model.screen { return model.passwordRequests.first }
                return nil
            },
            set: { value in
                if value == nil, let first = model.passwordRequests.first { model.answerPassword(nil, for: first) }
            }
        )
    }
}

/// Accepts drops anywhere on a view and hands them to the app's router.
struct WindowDrop: ViewModifier {
    let model: AppModel
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    DropHighlight()
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                model.open(urls)
                return true
            } isTargeted: { targeted = $0 }
    }
}

extension View {
    func acceptsDrops(_ model: AppModel) -> some View { modifier(WindowDrop(model: model)) }
}

/// A 2 pt accent ring just inside the window while files are dragged over it, its
/// corners following the window's.
struct DropHighlight: View {
    private static let inset: CGFloat = 2
    private static let lineWidth: CGFloat = 2

    var body: some View {
        if #available(macOS 26, *) {
            // A stroke twice the width centred on the edge, clipped to the inside.
            let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(Radius.xs)), isUniform: true)
            shape.stroke(Color.accentColor, lineWidth: Self.lineWidth * 2)
                .clipShape(shape)
                .padding(Self.inset)
        } else {
            RoundedRectangle(cornerRadius: Radius.nested(in: Radius.legacyWindow, padding: Self.inset), style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: Self.lineWidth)
                .padding(Self.inset)
        }
    }
}

/// Unlock an encrypted archive. Used by the open archive and by queue rows. The layout of
/// an authentication dialog: the lock on the left, everything else in one column, and a
/// wrong password replaces the subtitle in place, so the sheet never changes size.
struct PasswordEntrySheet: View {
    let fileName: String
    let wrong: Bool
    let checking: Bool
    /// Settings ▸ Remember passwords, offered here too.
    @Binding var remember: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("“\(fileName)” is protected with a password")
                            .font(.headline)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                        Group {
                            if wrong {
                                Label("That password didn't work. Try again.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.textOrange)
                            } else {
                                Text("Enter its password to open it.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Toggle("Show password", isOn: $showPassword)
                        Toggle("Remember in Keychain", isOn: $remember)
                            .help("Save passwords that work in your Keychain, and try them on new archives")
                    }
                }
            }
            HStack(spacing: Spacing.s) {
                if checking {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking password")
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Unlock", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || checking)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 400)
        .onAppear { focused = true }
        .onChange(of: wrong) { _, isWrong in
            if isWrong { password = ""; focused = true }
        }
        .onChange(of: checking) { _, isChecking in
            if !isChecking, wrong { password = ""; focused = true }
        }
    }

    private func submit() {
        guard !password.isEmpty, !checking else { return }
        onSubmit(password)
    }
}
