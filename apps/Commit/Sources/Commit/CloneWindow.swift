import AppKit
import CommitCore
import Observation
import SlopKit
import SwiftUI

/// Something git's askpass prompts can be shown on: a repository window or the clone window.
@MainActor
protocol PromptPresenting: AnyObject {
    func ask(_ prompt: AskpassPrompt) async -> String?
}

extension RepoModel: PromptPresenting {}

/// Clone: an address, a folder, progress and Cancel. Uses the person's own git credentials and
/// SSH setup; prompts (a token, a key passphrase, a new host key) appear in this window.
@MainActor
@Observable
final class CloneModel: PromptPresenting {
    let id = UUID()
    var address = "" {
        didSet {
            guard address != oldValue, !nameEdited else { return }
            name = CloneAddress.problem(with: address) == nil ? CloneAddress.suggestedName(for: address) : ""
        }
    }
    var name = ""
    var nameEdited = false
    var parent: URL
    var submodules = true
    private(set) var isCloning = false
    private(set) var progress: GitProgress?
    var problem: Explanation?
    var prompt: PendingPrompt?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let parentKey = "cloneParentFolder"

    init() {
        let fm = FileManager.default
        if let override = Diagnostics.cloneParent {
            parent = override
        } else if let saved = UserDefaults.standard.string(forKey: Self.parentKey), fm.fileExists(atPath: saved) {
            parent = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            let home = fm.homeDirectoryForCurrentUser
            let developer = home.appendingPathComponent("Developer", isDirectory: true)
            parent = fm.fileExists(atPath: developer.path) ? developer : home
        }
    }

    var destination: CloneDestination { CloneDestination(parent: parent, name: name.trimmingCharacters(in: .whitespaces)) }

    var addressProblem: String? {
        address.trimmingCharacters(in: .whitespaces).isEmpty ? nil : CloneAddress.problem(with: address)
    }

    var destinationProblem: String? { name.isEmpty ? nil : destination.problem() }

    var canClone: Bool {
        !isCloning && CloneAddress.problem(with: address) == nil && destination.problem() == nil
    }

    func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = parent
        panel.prompt = "Choose"
        panel.message = "Choose where the repository's folder goes."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.parent = url
                if Diagnostics.cloneParent == nil { UserDefaults.standard.set(url.path, forKey: Self.parentKey) }
            }
        }
    }

    func clone(onDone: @escaping @MainActor (URL) -> Void) {
        let app = AppModel.shared
        guard canClone else { return }
        problem = nil
        isCloning = true
        progress = nil
        let address = address, destination = destination, submodules = submodules
        app.registerPrompts(self, id: id)
        task = Task {
            await app.waitUntilReady()
            guard let runner = app.runner(for: id) else {
                isCloning = false
                problem = Explanation.explain("Git isn't available.", operation: .clone)
                return
            }
            do {
                let url = try await Repository.clone(address, into: destination, submodules: submodules, runner: runner) { value in
                    Task { @MainActor [weak self] in self?.progress = value }
                }
                isCloning = false
                app.unregisterPrompts(id: id)
                HUD.show("Cloned \(destination.name)", systemImage: "checkmark.circle")
                onDone(url)
            } catch is CancellationError {
                isCloning = false
                progress = nil
                app.unregisterPrompts(id: id)
            } catch {
                isCloning = false
                progress = nil
                app.unregisterPrompts(id: id)
                let output = (error as? GitFailure)?.output ?? String(describing: error)
                problem = Explanation.explain(output, operation: .clone, remote: Self.host(of: address))
            }
        }
    }

    func cancel() {
        task?.cancel()
        answerPrompt(nil)
    }

    /// "github.com" for a readable error ("Git couldn't sign in to github.com").
    static func host(of address: String) -> String? {
        let s = CloneAddress.normalize(address)
        if let host = URLComponents(string: s)?.host, !host.isEmpty { return host }
        if let at = s.firstIndex(of: "@"), let colon = s[at...].firstIndex(of: ":") { return String(s[s.index(after: at)..<colon]) }
        return nil
    }

    func ask(_ prompt: AskpassPrompt) async -> String? {
        await withCheckedContinuation { continuation in
            if let existing = self.prompt { existing.continuation.resume(returning: nil) }
            self.prompt = PendingPrompt(prompt: prompt, continuation: continuation)
        }
    }

    func answerPrompt(_ answer: String?) {
        prompt?.continuation.resume(returning: answer)
        prompt = nil
    }
}

struct CloneWindow: View {
    let app: AppModel
    @State private var model = CloneModel()
    @FocusState private var addressFocused: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Form {
                TextField("Address", text: $model.address, prompt: Text("https://example.com/owner/project.git"))
                    .focused($addressFocused)
                    .disabled(model.isCloning)
                    .onSubmit(start)
                LabeledContent("Where") {
                    HStack(spacing: Spacing.s) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.parent.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(RecentRow.display(model.parent.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.parent.path)
                        Spacer(minLength: Spacing.s)
                        Button("Choose…") { model.chooseParent() }
                            .disabled(model.isCloning)
                    }
                }
                TextField("Folder name", text: Binding(get: { model.name }, set: { model.name = $0; model.nameEdited = !$0.isEmpty }),
                          prompt: Text("project"))
                    .disabled(model.isCloning)
                    .onSubmit(start)
                Toggle("Include submodules", isOn: $model.submodules)
                    .toggleStyle(.checkbox)
                    .disabled(model.isCloning)
            }
            .formStyle(.columns)

            status
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

            HStack(spacing: Spacing.s) {
                Spacer()
                if model.isCloning {
                    Button("Cancel", role: .cancel) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel", role: .cancel) { dismissWindow(id: "clone") }
                        .keyboardShortcut(.cancelAction)
                    Button("Clone", action: start)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canClone)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            addressFocused = true
            app.windowsAreAvailable(open: openWindow, dismiss: dismissWindow)
        }
        .onDisappear { if model.isCloning { model.cancel() } }
        .sheet(item: Binding(get: { model.prompt }, set: { if $0 == nil, model.prompt != nil { model.answerPrompt(nil) } })) { pending in
            AskpassSheet(pending: pending) { model.answerPrompt($0) }
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.isCloning {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let fraction = model.progress?.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(model.progress.map { "\($0.phase)…" } ?? "Connecting…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cloning, \(model.progress?.phase ?? "connecting")")
        } else if let problem = model.problem {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(problem.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.textOrange)
                Text(problem.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if !problem.output.isEmpty {
                    DisclosureGroup("Git's Output") {
                        Text(problem.output)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
        } else if let issue = model.addressProblem ?? model.destinationProblem {
            Text(issue)
                .font(.callout)
                .foregroundStyle(.textOrange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(model.name.isEmpty
                 ? "Commit runs git clone with your own credentials and SSH keys. Nothing is stored by Commit."
                 : "Clones into \(RecentRow.display(model.destination.url.path)) and opens it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func start() {
        model.clone { url in
            app.open(url)
            dismissWindow(id: "clone")
        }
    }
}
