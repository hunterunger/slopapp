import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// Email links: whether Switchboard gets them, the mail apps and webmail they can go to
/// (order = number keys in their picker), and where they go when no rule matches. Rules for
/// email live with the other rules.
struct EmailTab: View {
    @Bindable var model: AppModel
    @State private var selection: UUID?
    @State private var webmailSheet: WebmailDraft?
    @State private var showUndo = false
    @Environment(\.undoManager) private var undoManager

    private var selectedIndex: Int? {
        selection.flatMap { id in model.config.emailTargets.firstIndex { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            EmailRoleRow(model: model)

            if model.config.emailTargets.isEmpty {
                ContentUnavailableView {
                    Label("No Email Apps", systemImage: "envelope")
                } description: {
                    Text("Add a mail app or webmail so email links have somewhere to go.")
                } actions: {
                    addMenu(title: true)
                    UndoRemovalButton(label: "Undo Remove", isVisible: $showUndo)
                }
                .frame(height: 200)
            } else {
                List(selection: $selection) {
                    ForEach(model.config.emailTargets) { target in
                        TargetListRow(target: target, number: pickerNumber(of: target), isInstalled: model.isInstalled(target))
                            .tag(target.id)
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                if target.webmail != nil { Button("Edit…") { edit(target) } }
                                Button(target.isHidden ? "Show in Picker" : "Hide from Picker") {
                                    update(target.id) { $0.isHidden.toggle() }
                                }
                                Button("Remove", role: .destructive) { remove(target) }
                            }
                    }
                    .onMove { model.config.emailTargets.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                .frame(height: min(max(CGFloat(model.config.emailTargets.count) * 34 + 14, 110), 200))
                .accessibilityLabel("Email apps")
                .onDeleteCommand { if let index = selectedIndex { remove(model.config.emailTargets[index]) } }

                ListButtonBar(
                    canRemove: selectedIndex != nil,
                    canMoveUp: (selectedIndex ?? 0) > 0,
                    canMoveDown: selectedIndex.map { $0 < model.config.emailTargets.count - 1 } ?? false,
                    remove: { if let index = selectedIndex { remove(model.config.emailTargets[index]) } },
                    moveUp: { move(by: -1) },
                    moveDown: { move(by: 1) }
                ) { addMenu(title: false) } trailing: {
                    UndoRemovalButton(label: "Undo Remove", isVisible: $showUndo)
                }

                options
            }

            Form {
                Picker("When no rule matches an email link", selection: $model.config.emailFallback) {
                    Text("Show the picker").tag(Fallback.ask)
                    Divider()
                    ForEach(model.config.emailTargets) { target in
                        Text("Write in \(target.displayName)").tag(Fallback.open(targetID: target.id))
                    }
                    if case .open(let id) = model.config.emailFallback, model.target(id: id) == nil {
                        Text("Write in \(model.destinationName(.open(targetID: id)).name) (removed, shows the picker)")
                            .tag(model.config.emailFallback)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -Spacing.xl)
            .padding(.vertical, -Spacing.xl)
            .scrollContentBackground(.hidden)
        }
        .padding(Spacing.xl)
        .onReceive(NotificationCenter.default.publisher(for: .switchboardOpenSheet)) { note in
            switch note.object as? String {
            case "webmail": webmailSheet = WebmailDraft(provider: .gmail, account: "1")
            case "webmail-custom": webmailSheet = WebmailDraft(provider: .custom, template: "https://mail.example.org/new")
            default: break
            }
        }
        .sheet(item: $webmailSheet) { draft in
            WebmailSheet(draft: draft, browsers: model.config.targets) { target in
                if let target { save(target, replacing: draft.editing) }
            }
        }
    }

    /// The selected entry's options, or a hint. Fixed height so the window doesn't jump.
    private var options: some View {
        Group {
            if let index = selectedIndex {
                let target = model.config.emailTargets[index]
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(target.displayName).font(.headline)
                        if target.webmail != nil {
                            Button("Edit…") { edit(target) }
                                .controlSize(.small)
                        }
                    }
                    Toggle("Show in picker", isOn: Binding(
                        get: { !model.config.emailTargets[index].isHidden },
                        set: { model.config.emailTargets[index].isHidden = !$0 }))
                    Toggle("Open in the background", isOn: $model.config.emailTargets[index].opensInBackground)
                    if target.webmail != nil, BrowserCatalog.family(for: target.bundleID).windowsNeedAccessibility,
                       target.privateWindow || target.profile != nil {
                        AccessibilityNote()
                    }
                }
                .toggleStyle(.checkbox)
            } else {
                Text("Email links show these in this order, with number keys. Rules can send some email links straight to one, like work addresses to webmail in your work profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
    }

    private func addMenu(title: Bool) -> some View {
        Menu {
            Section("Mail Apps") {
                ForEach(model.installedMailApps, id: \.bundleID) { app in
                    Button(isListed(app) ? "\(app.name) (Added)" : app.name) { addApp(app) }
                        .disabled(isListed(app))
                }
            }
            Section("Webmail") {
                ForEach(WebmailProvider.allCases.filter { $0 != .custom }, id: \.self) { provider in
                    Button("\(provider.title)…") { webmailSheet = WebmailDraft(provider: provider) }
                }
                Button("Other Webmail…") { webmailSheet = WebmailDraft(provider: .custom) }
            }
            .disabled(model.config.targets.isEmpty)
            Section("Other Apps") {
                ForEach(model.otherMailApps, id: \.bundleID) { app in
                    Button(isListed(app) ? "\(app.name) (Added)" : app.name) { addApp(app) }
                        .disabled(isListed(app))
                }
                Button("Choose App…") { chooseApp() }
            }
        } label: {
            if title {
                Text("Add Email App")
            } else {
                Label("Add", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
            }
        }
        .menuIndicator(title ? .visible : .hidden)
        .fixedSize()
        .help("Add a mail app or webmail")
        .accessibilityLabel("Add")
    }

    private func isListed(_ app: InstalledApp) -> Bool {
        model.config.emailTargets.contains { $0.bundleID == app.bundleID && $0.webmail == nil && !$0.isHidden }
    }

    private func pickerNumber(of target: Target) -> Int? {
        let visible = model.config.emailTargets.filter { !$0.isHidden }
        guard !target.isHidden, let index = visible.firstIndex(where: { $0.id == target.id }), index < 9 else { return nil }
        return index + 1
    }

    private func addApp(_ app: InstalledApp) {
        selection = model.addEmailTarget(Target(bundleID: app.bundleID, appPath: app.path, appName: app.name))
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an app to write emails in."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        selection = model.addEmailTarget(Target(bundleID: id, appPath: url.path, appName: AppModel.displayName(of: url)))
    }

    private func edit(_ target: Target) {
        guard let webmail = target.webmail else { return }
        let browser = model.config.targets.first {
            $0.bundleID == target.bundleID && $0.profile == target.profile && $0.privateWindow == target.privateWindow
        }
        webmailSheet = WebmailDraft(provider: webmail.provider, account: webmail.account, template: webmail.template,
                                    browserID: browser?.id, editing: target)
    }

    private func save(_ target: Target, replacing old: Target?) {
        if let old, let index = model.config.emailTargets.firstIndex(where: { $0.id == old.id }) {
            var updated = target
            updated.id = old.id
            updated.isHidden = old.isHidden
            updated.opensInBackground = old.opensInBackground
            model.config.emailTargets[index] = updated
            selection = old.id
        } else {
            selection = model.addEmailTarget(target)
        }
    }

    private func update(_ id: UUID, _ change: (inout Target) -> Void) {
        guard let index = model.config.emailTargets.firstIndex(where: { $0.id == id }) else { return }
        change(&model.config.emailTargets[index])
    }

    private func remove(_ target: Target) {
        guard let index = model.config.emailTargets.firstIndex(where: { $0.id == target.id }) else { return }
        model.removeTarget(id: target.id, undoManager: undoManager)
        showUndo = true
        let remaining = model.config.emailTargets
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    private func move(by offset: Int) {
        guard let index = selectedIndex else { return }
        model.config.emailTargets.moveElement(at: index, by: offset)
    }
}

/// "Email links: Switchboard / Mail", with the button to take them over or give them back.
struct EmailRoleRow: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Email links")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.m)
            if model.isDefaultEmailApp {
                Menu("Give Back To") {
                    ForEach(model.installedMailApps + model.otherMailApps, id: \.bundleID) { app in
                        Button("\(app.name)…") { model.handBackEmail(to: app) }
                    }
                }
                .fixedSize()
                .help("Let another app open email links again")
            } else {
                Button("Make Default Email App…") { model.makeDefaultEmailApp() }
            }
        }
    }

    private var subtitle: String {
        if model.isDefaultEmailApp {
            return "Switchboard opens email links and sends each to the app or webmail below."
        }
        let holder = model.emailHolder.map { AppModel.displayName(of: URL(fileURLWithPath: $0.path)) } ?? "No app"
        return "\(holder) opens email links now. Make Switchboard the default email app to choose per link. macOS will ask you to confirm."
    }
}

// MARK: - Webmail

struct WebmailDraft: Identifiable {
    let id = UUID()
    var provider: WebmailProvider
    var account = ""
    var template = ""
    var browserID: UUID?
    /// The target being edited, if not new.
    var editing: Target?
}

/// Chooses a webmail service and the browser (and profile) to write in.
struct WebmailSheet: View {
    @State var draft: WebmailDraft
    let browsers: [Target]
    let onDone: (Target?) -> Void
    @Environment(\.dismiss) private var dismiss

    private var browser: Target? {
        browsers.first { $0.id == draft.browserID } ?? browsers.first
    }

    private var webmail: Webmail {
        Webmail(provider: draft.provider, account: draft.account, template: draft.template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Service", selection: $draft.provider) {
                    ForEach(WebmailProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                Picker("Write in", selection: Binding(get: { browser?.id }, set: { draft.browserID = $0 })) {
                    ForEach(browsers) { target in
                        Text(target.displayName).tag(Optional(target.id))
                    }
                }
                if draft.provider.supportsAccount {
                    TextField("Account", text: $draft.account, prompt: Text("Optional, like you@gmail.com"))
                        .autocorrectionDisabled()
                }
                if draft.provider == .custom {
                    TextField("Compose address", text: Binding(get: { draft.template }, set: { draft.template = LinkParser.plainText($0) }),
                              prompt: Text("https://mail.example.com/compose?to={to}"))
                        .autocorrectionDisabled()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top) {
                Label(feedback.text, systemImage: feedback.isProblem ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(feedback.isProblem ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.secondary))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250, alignment: .leading)
                Spacer()
                Button("Cancel", role: .cancel) { close(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(draft.editing == nil ? "Add" : "Save") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(browser == nil || webmail.templateProblem != nil)
            }
            .padding([.horizontal, .bottom], Spacing.xl)
        }
        .frame(width: 460)
    }

    private var feedback: (text: String, isProblem: Bool) {
        if browser == nil { return ("Add a browser in the Browsers tab first.", true) }
        if let problem = webmail.templateProblem { return (problem, true) }
        if draft.provider == .custom {
            return ("Use {to}, {cc}, {bcc}, {subject}, {body}, or {mailto} for the whole link.", false)
        }
        return ("Email links open a new message in \(draft.provider.shortTitle), with the address, subject and text filled in. Sign in there once.", false)
    }

    private func add() {
        guard let browser else { return }
        close(Target(bundleID: browser.bundleID, appPath: browser.appPath, appName: browser.appName,
                     profile: browser.profile, privateWindow: browser.privateWindow, webmail: webmail))
    }

    private func close(_ target: Target?) {
        onDone(target)
        dismiss()
    }
}
