import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore

/// What happens to a web link before rules see it: tracking removal, apps that open their own
/// links, and the user's rewrites. Order on the page = the order they run in.
struct RewriteTab: View {
    @Bindable var model: AppModel
    @State private var editing: Rewrite?
    @State private var showUndo = false
    @Environment(\.undoManager) private var undoManager

    private var installed: [AppHandoff] {
        _ = model.handoffRefresh
        return Handoffs.all.filter { HandoffApps.installed($0) != nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.config.stripsTrackingParameters) {
                    Text("Remove tracking from links")
                    Text("Drops ad and newsletter tags like utm_source and fbclid before a link opens. The page is the same.")
                }
            }

            Section {
                if model.config.rewrites.isEmpty {
                    Text("No rewrites. Add one to switch a website to a mirror, drop part of its links, or send them to an app.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(model.config.rewrites.enumerated()), id: \.element.id) { index, rewrite in
                    RewriteRow(rewrite: rewrite, number: index + 1, isEnabled: enabledBinding(rewrite.id)) { editing = rewrite }
                        .contextMenu {
                            Button("Edit…") { editing = rewrite }
                            Button("Move Up") { model.config.rewrites.moveElement(at: index, by: -1) }
                                .disabled(index == 0)
                            Button("Move Down") { model.config.rewrites.moveElement(at: index, by: 1) }
                                .disabled(index == model.config.rewrites.count - 1)
                            Divider()
                            Button("Delete", role: .destructive) { delete(rewrite.id) }
                        }
                }
                HStack {
                    Button("Add Rewrite…") { editing = Rewrite() }
                    UndoRemovalButton(label: "Undo Delete", isVisible: $showUndo)
                }
            } header: {
                Text("Rewrite links")
            } footer: {
                Text("Rewrites run from the top, each on the result of the one before, then the apps below, then your rules. A rewrite that makes another app's link (like zoommtg://) opens it in that app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                // Catalog order, installed or not, so meeting apps come first either way.
                ForEach(Handoffs.all) { handoff in
                    let isInstalled = installed.contains { $0.id == handoff.id }
                    Toggle(isOn: handoffBinding(handoff.id)) {
                        Text(handoff.title)
                        Text(isInstalled
                             ? "\(handoff.example) links open in \(handoff.appName)"
                             : "\(handoff.appName) isn't installed, so these links open in your browser. Turn this on to use \(handoff.appName) once it's there.")
                    }
                }
            } header: {
                Text("Open in apps")
            } footer: {
                Text(appsFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .formStyle(.grouped)
        .frame(minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .switchboardOpenSheet)) { note in
            switch note.object as? String {
            case "rewrite": editing = model.config.rewrites.first ?? Rewrite()
            default: break
            }
        }
        .sheet(item: $editing) { rewrite in
            RewriteEditor(rewrite: rewrite, isNew: !model.config.rewrites.contains { $0.id == rewrite.id }) { saved in
                if let saved { save(saved) }
                editing = nil
            }
        }
    }

    private var appsFooter: String {
        var text = "After rewrites, before your rules. A link an app sends out is never sent back to it."
        let keys = model.config.askModifiers
        if !keys.isEmpty { text += " Hold \(keys.symbol) while clicking to choose a browser instead." }
        text += " An app that isn't installed is skipped, so its links still open in your browser."
        return text
    }

    private func handoffBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.config.handoffs.contains(id) },
            set: { on in
                model.config.handoffs.removeAll { $0 == id }
                if on {
                    // Keep the catalog's order, so the first match is predictable.
                    let order = Handoffs.all.map(\.id)
                    model.config.handoffs.append(id)
                    model.config.handoffs.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
                }
            }
        )
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.config.rewrites.first { $0.id == id }?.isEnabled ?? false },
            set: { value in
                if let index = model.config.rewrites.firstIndex(where: { $0.id == id }) { model.config.rewrites[index].isEnabled = value }
            }
        )
    }

    private func save(_ rewrite: Rewrite) {
        if let index = model.config.rewrites.firstIndex(where: { $0.id == rewrite.id }) {
            model.config.rewrites[index] = rewrite
        } else {
            model.config.rewrites.append(rewrite)
        }
    }

    private func delete(_ id: UUID) {
        model.changeUndoably("Delete Rewrite", undoManager: undoManager) { $0.rewrites.removeAll { $0.id == id } }
        showUndo = true
    }
}

private struct RewriteRow: View {
    let rewrite: Rewrite
    let number: Int
    @Binding var isEnabled: Bool
    let edit: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle("Rewrite \(number) on", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 1) {
                Text(rewrite.summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(rewrite.isEnabled ? .primary : .secondary)
                if rewrite.usesRegex {
                    Text("Regular expression")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Edit…", action: edit)
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rewrite \(number): \(rewrite.summary)\(rewrite.isEnabled ? "" : ", off")")
    }
}

/// Find and replace, with a link to try it on.
struct RewriteEditor: View {
    @State var rewrite: Rewrite
    let isNew: Bool
    let onDone: (Rewrite?) -> Void
    @State private var sample = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Website", text: plain(\.host), prompt: Text(verbatim: "Optional, like example.com"))
                        .autocorrectionDisabled()
                    TextField("Find", text: plain(\.find), prompt: Text(verbatim: rewrite.usesRegex ? "^https://example\\.com/(.*)$" : "twitter.com"))
                        .autocorrectionDisabled()
                    TextField("Replace with", text: plain(\.replacement), prompt: Text(verbatim: rewrite.usesRegex ? "https://mirror.example/$1" : "Empty removes it"))
                        .autocorrectionDisabled()
                    Toggle(isOn: $rewrite.usesRegex) {
                        Text("Regular expression")
                        Text("Matches anywhere in the link, ignoring case. Use $1, $2… for its groups.")
                    }
                } header: {
                    Text("Rewrite links")
                } footer: {
                    Text(verbatim: "example.com also matches www.example.com. *.example.com matches every subdomain, like us02web.example.com.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section("Try it") {
                    TextField("Test link", text: Binding(get: { sample }, set: { sample = LinkParser.plainText($0) }),
                              prompt: Text(verbatim: "Paste a link"))
                        .autocorrectionDisabled()
                    Label(result.text, systemImage: result.symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let problem = rewrite.validationProblem, !rewrite.find.isEmpty || !rewrite.host.isEmpty {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260, alignment: .leading)
                }
                Spacer()
                Button("Cancel", role: .cancel) { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rewrite" : "Save") {
                    var saved = rewrite
                    saved.host = saved.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDone(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rewrite.validationProblem != nil)
            }
            .padding([.horizontal, .bottom], Spacing.xl)
        }
        .frame(width: 480)
    }

    private func plain(_ keyPath: WritableKeyPath<Rewrite, String>) -> Binding<String> {
        Binding(get: { rewrite[keyPath: keyPath] }, set: { rewrite[keyPath: keyPath] = LinkParser.plainText($0) })
    }

    private var result: (text: String, symbol: String) {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("Shows what a link becomes.", "info.circle") }
        guard let url = LinkParser.webLink(in: trimmed) else { return ("That doesn't look like a web link.", "questionmark.circle") }
        var probe = rewrite
        probe.isEnabled = true
        let site = rewrite.host.trimmingCharacters(in: .whitespaces)
        if let pattern = HostPattern(site), !pattern.matches(url) {
            let hint = site.hasPrefix("*.") ? "" : " For its subdomains too, use *.\(site)."
            return ("Doesn't apply: this link isn't on \(site).\(hint)", "equal.circle")
        }
        guard let out = probe.apply(to: url) else { return ("Doesn't change this link: nothing matches what to find.", "equal.circle") }
        if LinkKind.of(out) == nil, !Opener.canOpen(out) {
            return ("Becomes \(out.absoluteString), but no app on this Mac opens \(out.scheme ?? ""): links, so these links will open in a browser as they are.",
                    "exclamationmark.triangle")
        }
        return ("Becomes \(out.absoluteString)", "arrow.right.circle")
    }
}
