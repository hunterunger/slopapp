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
        .frame(minWidth: 540, minHeight: 380)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .sheet(item: queuePasswordRequest) { request in
            PasswordEntrySheet(
                fileName: request.url.lastPathComponent, wrong: request.wrong, checking: false,
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(2)
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

/// Unlock an encrypted archive. Used by the open archive and by queue rows.
struct PasswordEntrySheet: View {
    let fileName: String
    let wrong: Bool
    let checking: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("“\(fileName)” is protected with a password")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Enter its password to extract its files. Crate doesn't save passwords.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
            Toggle("Show password", isOn: $showPassword)
            if wrong {
                Label("That password didn't work. Check it and try again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
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
