import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// Shared layout for the small sheets: title, content, buttons on the right.
struct SheetLayout<Content: View, Buttons: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(title).font(.headline)
            content
            HStack(spacing: Spacing.s) {
                Spacer()
                buttons
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}

struct NewBranchSheet: View {
    let model: RepoModel
    let from: ObjectID?
    let fromLabel: String
    @State private var name = ""
    @State private var checkout = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: "New Branch") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField("Name", text: $name, prompt: Text("feature/my-change"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Branch name")
                    .onSubmit(create)
                Text(problem ?? "Starts from \(fromLabel).")
                    .font(.caption)
                    .foregroundStyle(problem == nil ? Color.secondary : Color.textOrange)
                    .lineLimit(2)
                Toggle("Switch to it", isOn: $checkout)
                    .toggleStyle(.checkbox)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create Branch", action: create)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
        }
    }

    private var trimmed: String { BranchName.suggest(from: name) }

    /// Why the typed name won't do (nil while empty: the button is just disabled).
    private var problem: String? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let p = BranchName.problem(with: trimmed) { return p }
        if model.refs.local.contains(where: { $0.name == trimmed }) { return "A branch called \(trimmed) already exists." }
        return nil
    }

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && problem == nil }

    private func create() {
        guard canCreate else { return }
        model.createBranch(trimmed, from: from, checkout: checkout)
        dismiss()
    }
}

struct StashSheet: View {
    let model: RepoModel
    @State private var message = ""
    @State private var includeUntracked = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: "Stash Changes") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField("Message", text: $message, prompt: Text("What you were working on (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Stash message")
                    .onSubmit(stash)
                Toggle("Include untracked files", isOn: $includeUntracked)
                    .toggleStyle(.checkbox)
                Text("Your working copy goes back to the last commit. Apply the stash later from Stashes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Stash", action: stash)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func stash() {
        model.stash(message: message, includeUntracked: includeUntracked)
        dismiss()
    }
}

/// git's output (a hook that failed, an error's details) with Copy Output.
struct OutputSheet: View {
    let title: String
    let output: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(.headline)
            ScrollView {
                Text(output.isEmpty ? "Git didn't print anything." : output)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
            .frame(minHeight: 160, maxHeight: 360)
            HStack {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                    HUD.show("Copied", systemImage: "doc.on.doc")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 560)
    }
}

/// A pull hit "divergent branches": merge or rebase, once or always for this repository.
struct DivergentPullSheet: View {
    let model: RepoModel
    @State private var remember = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: "Merge or Rebase?") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Your branch and \(model.status.branch.upstream ?? "the remote") both have new commits. Merge combines them with a merge commit. Rebase puts your commits on top of theirs.")
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Remember for this repository", isOn: $remember)
                    .toggleStyle(.checkbox)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Rebase") {
                dismiss()
                model.pull(strategy: .rebase, remember: remember)
            }
            Button("Merge") {
                dismiss()
                model.pull(strategy: .merge, remember: remember)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// Missing user.name / user.email, asked at the first commit.
struct IdentitySheet: View {
    let model: RepoModel
    @State private var name = ""
    @State private var email = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: "Who's Committing?") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Git records a name and email with every commit.")
                    .fixedSize(horizontal: false, vertical: true)
                Form {
                    TextField("Name", text: $name, prompt: Text("Ada Lovelace"))
                    TextField("Email", text: $email, prompt: Text("ada@example.com"))
                }
                .formStyle(.columns)
                Text("Saved in your global Git config, so every repository uses them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { model.saveIdentity(name: name, email: email) }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !email.contains("@"))
        }
        .onAppear {
            name = model.identity.name ?? ""
            email = model.identity.email ?? ""
        }
    }
}

/// git or ssh needs something typed: a username, a password or token, a key passphrase, or
/// a yes/no for an unknown server. Nothing typed is kept by Commit.
struct AskpassSheet: View {
    let pending: PendingPrompt
    /// nil: cancelled.
    let respond: (String?) -> Void
    @State private var answer = ""

    var body: some View {
        SheetLayout(title: pending.prompt.title) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(pending.prompt.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(pending.prompt.kind == .confirmation ? .callout.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                switch pending.prompt.kind {
                case .username:
                    TextField("Username", text: $answer)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { respond(answer) }
                case .secret:
                    SecureField(pending.prompt.title, text: $answer)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { respond(answer) }
                case .confirmation:
                    EmptyView()
                }
                Text(pending.prompt.kind == .confirmation
                     ? "Only trust a server you expect. Its fingerprint is shown above."
                     : "Commit passes this to Git and doesn't keep it. Your credential helper or ssh-agent may.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } buttons: {
            Button("Cancel", role: .cancel) { respond(nil) }
                .keyboardShortcut(.cancelAction)
            if pending.prompt.kind == .confirmation {
                Button("Trust") { respond(AskpassPrompt.confirmationAnswer(true)) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { respond(answer) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .interactiveDismissDisabled()
    }
}

/// The toolbar branch popover: filter and switch.
struct BranchSwitcher: View {
    @Bindable var model: RepoModel
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        let local = RefList.filter(model.refs.local, query)
        let remote = RefList.filter(model.refs.remote, query).filter { r in !model.refs.local.contains { $0.name == r.nameOnRemote } }
        VStack(spacing: 0) {
            TextField("Switch to branch", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .padding(Spacing.s)
                .accessibilityLabel("Filter branches")
                .onSubmit { switchTo(local.first ?? remote.first) }
            Hairline()
            List(selection: $selection) {
                Section("Branches") {
                    ForEach(local.prefix(100)) { ref in
                        RefRow(ref: ref, status: model.status.branch).tag(ref.fullName)
                    }
                }
                if !remote.isEmpty {
                    Section("Remote Branches") {
                        ForEach(remote.prefix(100)) { ref in
                            RefRow(ref: ref, status: model.status.branch).tag(ref.fullName)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { names in
                guard let name = names.first else { return }
                switchTo((model.refs.local + model.refs.remote).first { $0.fullName == name })
            }
            Hairline()
            HStack {
                Button("New Branch…") {
                    model.showBranchSwitcher = false
                    model.showNewBranch(from: nil)
                }
                .disabled(model.status.branch.isUnborn)
                Spacer()
                Button("Switch") {
                    switchTo((model.refs.local + model.refs.remote).first { $0.fullName == selection })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .controlSize(.small)
            .padding(Spacing.s)
        }
        .frame(width: 320, height: 380)
        .onAppear { focused = true }
    }

    private func switchTo(_ ref: GitRef?) {
        guard let ref else { return }
        model.showBranchSwitcher = false
        model.switchTo(ref)
    }
}
