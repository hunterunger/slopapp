import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// Ordered rules (first match wins), what happens otherwise, and a link tester.
struct RulesTab: View {
    @Bindable var model: AppModel
    @State private var selection: UUID?
    @State private var showUndo = false
    @Environment(\.undoManager) private var undoManager
    @State private var editing: Rule?
    @State private var testText = ""

    private var selectedIndex: Int? {
        selection.flatMap { id in model.config.rules.firstIndex { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            tester

            if model.config.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("Every link shows the picker. Add a rule, or hold ⌘ as you pick a browser to make one.")
                        .frame(maxWidth: 360)
                } actions: {
                    Button("Add Rule…") { startNewRule() }
                }
                .frame(minHeight: 240)
            } else {
                let unused = RuleAnalysis.unused(in: model.config.rules, askModifiers: model.config.askModifiers)
                List(selection: $selection) {
                    ForEach(Array(model.config.rules.enumerated()), id: \.element.id) { index, rule in
                        let destination = model.destinationName(rule.action)
                        RuleRow(
                            rule: rule, number: index + 1,
                            destination: destination.name, isMissing: destination.isMissing,
                            unused: unused[index],
                            isEnabled: enabledBinding(rule.id)
                        )
                            .tag(rule.id)
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                Button("Edit…") { edit(rule) }
                                Button(rule.isEnabled ? "Turn Off" : "Turn On") { enabledBinding(rule.id).wrappedValue.toggle() }
                                Button("Delete", role: .destructive) { delete(rule.id) }
                            }
                    }
                    .onMove { model.config.rules.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                .frame(height: 180)
                .accessibilityLabel("Rules")
                .onDeleteCommand { if let id = selection { delete(id) } }
                .onKeyPress(.return) {
                    guard let index = selectedIndex else { return .ignored }
                    edit(model.config.rules[index])
                    return .handled
                }

                ListButtonBar(
                    canRemove: selectedIndex != nil,
                    canMoveUp: (selectedIndex ?? 0) > 0,
                    canMoveDown: selectedIndex.map { $0 < model.config.rules.count - 1 } ?? false,
                    remove: { if let id = selection { delete(id) } },
                    moveUp: { move(by: -1) },
                    moveDown: { move(by: 1) }
                ) {
                    Button(action: startNewRule) {
                        Label("New Rule", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .help("Add a rule")
                    .accessibilityLabel("New Rule")
                } trailing: {
                    Button("Edit…") { if let index = selectedIndex { edit(model.config.rules[index]) } }
                        .disabled(selectedIndex == nil)
                    UndoRemovalButton(label: "Undo Delete", isVisible: $showUndo)
                }
                if let (number, reason) = unused.enumerated().compactMap({ i, u in u.map { (i + 1, $0) } }).first {
                    Label(Self.explain(rule: number, reason, ask: model.config.askModifiers), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Rules are checked from the top. The first one that matches wins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Form {
                Picker("When no rule matches a web link", selection: fallbackBinding) {
                    Text("Show the picker").tag(Fallback.ask)
                    Divider()
                    ForEach(model.config.targets) { target in
                        Text("Open in \(target.displayName)").tag(Fallback.open(targetID: target.id))
                    }
                    if case .open(let id) = model.config.fallback, model.target(id: id) == nil {
                        Text("Open in \(model.destinationName(.open(targetID: id)).name) (removed, shows the picker)")
                            .tag(model.config.fallback)
                    }
                }
                Picker("Always show the picker while holding", selection: $model.config.askModifiers) {
                    Text("Nothing").tag(Modifiers())
                    Text("⌥ Option").tag(Modifiers.option)
                    Text("⌃ Control").tag(Modifiers.control)
                    Text("⌃⌥ Control-Option").tag(Modifiers([.control, .option]))
                    Text("fn").tag(Modifiers.function)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            // A grouped form brings its own 20 pt margins. Sideways they line its sections up
            // with the list; vertically they'd double the tab's own, so take them back.
            .padding(.horizontal, -Spacing.xl)
            .padding(.vertical, -Spacing.xl)
            // Its (now overlapping) margins mustn't paint over the caption above.
            .scrollContentBackground(.hidden)
        }
        .padding(Spacing.xl)
        .onReceive(NotificationCenter.default.publisher(for: .switchboardOpenSheet)) { note in
            switch note.object as? String {
            case "rule-email": editing = Rule(kind: .email, host: "example.com", action: model.config.emailTargets.first.map { .open(targetID: $0.id) } ?? .ask)
            case "rule-file": editing = Rule(kind: .file, fileExtensions: ["pdf"], action: .ask)
            default: break
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: !model.config.rules.contains { $0.id == rule.id }, model: model) { saved in
                if let saved { save(saved) }
                editing = nil
            }
        }
    }

    static func explain(rule number: Int, _ reason: RuleAnalysis.Unused, ask: Modifiers) -> String {
        switch reason {
        case .shadowed(let by):
            "Rule \(number) is never used: rule \(by + 1) above it catches the same links first. Move it up, or make rule \(by + 1) narrower."
        case .askModifiers:
            "Rule \(number) is never used: holding \(ask.symbol) always shows the picker (setting below). Choose other keys for the rule, or change that setting."
        }
    }

    // MARK: Tester

    private var tester: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("Test a link", text: Binding(get: { testText }, set: { testText = LinkParser.plainText($0) }),
                      prompt: Text("Paste a link or email address to see where it goes"))
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Test a link")
            // Always one line tall, so the window doesn't jump as you type.
            Label(testResult?.text ?? "Shows which rule a link matches.", systemImage: testResult?.symbol ?? "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var testResult: (text: String, symbol: String)? {
        let trimmed = testText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = Self.testLink(trimmed) else {
            return ("That doesn't look like a web link or email address.", "questionmark.circle")
        }
        let prepared = LinkPreparation.prepare(url, config: model.config)
        let link = IncomingLink(url: prepared.url)
        let decision = Router.route(link, config: model.config, isInstalled: model.isInstalled, installedApp: HandoffApps.installed)
        var text = Router.describe(decision, kind: link.kind)
        let rewrites = prepared.steps.compactMap { step -> Int? in
            if case .rewritten(let index, _) = step { return index + 1 }
            return nil
        }
        if !rewrites.isEmpty {
            let numbers = ListFormatter.localizedString(byJoining: rewrites.map(String.init))
            text = "Rewritten (rewrite \(numbers)) to \(prepared.url.absoluteString). " + text
        } else if prepared.steps.contains(.removedTracking) {
            text = "Tracking removed. " + text
        }
        switch decision {
        case .open, .openInApp: return (text, "arrow.up.forward.app")
        case .pick: return (text, "list.bullet")
        case .noTargets: return (text, "exclamationmark.triangle")
        }
    }

    /// A web link, a mailto link, or a bare address ("a@b.com" → mailto:a@b.com).
    static func testLink(_ text: String) -> URL? {
        if text.lowercased().hasPrefix("mailto:") { return URL(string: text) }
        if !text.contains("/"), !text.contains(" "), text.contains("@"), AddressPattern(text) != nil {
            return URL(string: "mailto:" + text)
        }
        return LinkParser.webLink(in: text)
    }

    // MARK: Helpers

    private var fallbackBinding: Binding<Fallback> {
        Binding(
            get: { model.config.fallback },
            set: { model.config.fallback = $0 }
        )
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.config.rules.first { $0.id == id }?.isEnabled ?? false },
            set: { value in
                if let index = model.config.rules.firstIndex(where: { $0.id == id }) {
                    model.config.rules[index].isEnabled = value
                }
            }
        )
    }

    private func startNewRule() {
        let firstTarget = model.config.pickerTargets.first?.id ?? model.config.targets.first?.id
        editing = Rule(action: firstTarget.map { .open(targetID: $0) } ?? .ask)
    }

    private func edit(_ rule: Rule) {
        editing = rule
    }

    private func save(_ rule: Rule) {
        if let index = model.config.rules.firstIndex(where: { $0.id == rule.id }) {
            model.config.rules[index] = rule
        } else {
            model.config.rules.append(rule)
        }
        selection = rule.id
    }

    private func delete(_ id: UUID) {
        guard let index = model.config.rules.firstIndex(where: { $0.id == id }) else { return }
        model.removeRule(id: id, undoManager: undoManager)
        showUndo = true
        let rules = model.config.rules
        selection = rules.isEmpty ? nil : rules[min(index, rules.count - 1)].id
    }

    private func move(by offset: Int) {
        guard let index = selectedIndex else { return }
        model.config.rules.moveElement(at: index, by: offset)
    }
}

private struct RuleRow: View {
    let rule: Rule
    let number: Int
    let destination: String
    let isMissing: Bool
    let unused: RuleAnalysis.Unused?
    @Binding var isEnabled: Bool

    private var unusedNote: String? {
        switch unused {
        case .shadowed(let by): "never used because rule \(by + 1) catches these links first"
        case .askModifiers: "never used because holding these keys always shows the picker"
        case nil: nil
        }
    }

    /// Width of the "→ destination" column, so the arrows line up down the list.
    static let destinationWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle("Rule \(number) on", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            // The warning follows the condition, so conditions keep one leading edge.
            HStack(spacing: Spacing.xs) {
                Text(rule.conditionSummary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(rule.isEnabled && unused == nil ? .primary : .secondary)
                if let unusedNote {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
                        .help("Rule \(number) is \(unusedNote).")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text(destination)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isMissing ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.secondary))
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
                }
            }
            .frame(width: Self.destinationWidth, alignment: .leading)
            .help(isMissing ? "\(destination) was removed or uninstalled. These links show the picker until it's back." : destination)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "Rule \(number): \(rule.conditionSummary), "
        switch rule.action {
        case .ask: text += "shows the picker"
        case .open: text += isMissing ? "opens in \(destination), which is missing, so it shows the picker" : "opens in \(destination)"
        }
        if !rule.isEnabled { text += ", off" }
        if let unusedNote { text += ", \(unusedNote)" }
        return text
    }
}

// MARK: - Editor

struct RuleEditor: View {
    @State var rule: Rule
    let isNew: Bool
    @Bindable var model: AppModel
    let onDone: (Rule?) -> Void

    @State private var sourceApps: [SourceAppMatch] = []
    @State private var extensionsText = ""

    /// Where rules of this kind can send links.
    private var destinations: [Target] {
        switch rule.kind {
        case .web: model.config.targets
        case .email: model.config.emailTargets
        case .file: model.config.fileTypes.compactMap(\.app) + model.config.targets
        }
    }

    private var footerText: String {
        switch rule.kind {
        case .web: "example.com also matches www.example.com. *.example.com matches every subdomain."
        case .email: "example.com matches addresses at example.com; *.example.com adds its subdomains. Any recipient (To, Cc or Bcc) counts."
        case .file: "For file types Switchboard opens (Files tab). Separate several with commas."
        }
    }

    /// Changing the kind keeps the app and keys, and picks a destination of the new kind.
    private var kindBinding: Binding<LinkKind> {
        Binding(get: { rule.kind }, set: { kind in
            guard kind != rule.kind else { return }
            rule.kind = kind
            if case .open(let id) = rule.action, !destinations.contains(where: { $0.id == id }) {
                rule.action = destinations.first.map { .open(targetID: $0.id) } ?? .ask
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker("For", selection: kindBinding) {
                        ForEach(LinkKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    switch rule.kind {
                    case .web:
                        TextField("Website", text: Binding(get: { rule.host }, set: { rule.host = LinkParser.plainText($0) }),
                                  prompt: Text("example.com or *.example.com"))
                            .autocorrectionDisabled()
                        TextField("Path starts with", text: Binding(get: { rule.path }, set: { rule.path = LinkParser.plainText($0) }),
                                  prompt: Text("Optional, like /docs"))
                            .autocorrectionDisabled()
                    case .email:
                        TextField("To", text: Binding(get: { rule.host }, set: { rule.host = LinkParser.plainText($0) }),
                                  prompt: Text("example.com or name@example.com"))
                            .autocorrectionDisabled()
                    case .file:
                        TextField("File types", text: Binding(get: { extensionsText }, set: { extensionsText = $0; rule.fileExtensions = FileType.parseExtensions($0) }),
                                  prompt: Text("pdf, docx"))
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Picker("Link comes from", selection: $rule.sourceApp) {
                            Text("Any app").tag(SourceAppMatch?.none)
                            Divider()
                            ForEach(sourceApps, id: \.bundleID) { app in
                                Text(app.name).tag(Optional(app))
                            }
                        }
                        Button("Choose…") { chooseSourceApp() }
                            .help("Choose an app that isn't running")
                    }
                    HStack {
                        Text("Only while holding")
                        Spacer()
                        ForEach([Modifiers.control, .option, .shift, .command], id: \.rawValue) { key in
                            // Same width for every key, whatever its symbol's width.
                            Toggle(isOn: modifierBinding(key)) {
                                Text(key.symbol).frame(width: PickerMetrics.keySlot)
                            }
                            .toggleStyle(.button)
                                .accessibilityLabel(key.name)
                        }
                    }
                } header: {
                    Text("Match links")
                } footer: {
                    Text(verbatim: footerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("Then") {
                    Picker("Open in", selection: $rule.action) {
                        Text("Show the picker").tag(RuleAction.ask)
                        Divider()
                        ForEach(destinations) { target in
                            Text(target.displayName).tag(RuleAction.open(targetID: target.id))
                        }
                        if case .open(let id) = rule.action, model.target(id: id) == nil {
                            Text("\(model.destinationName(rule.action).name) (missing)").tag(rule.action)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                // What will actually be saved, or why it can't be.
                Label(feedback.text, systemImage: feedback.symbol)
                    .font(.caption)
                    .foregroundStyle(feedback.isProblem ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.secondary))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .leading)
                Spacer()
                Button("Cancel", role: .cancel) { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.normalized().validationProblem != nil)
            }
            .padding([.horizontal, .bottom], Spacing.xl)
        }
        .frame(width: 460)
        .onAppear {
            sourceApps = Self.candidateSourceApps(including: rule.sourceApp)
            extensionsText = rule.fileExtensions.joined(separator: ", ")
        }
    }

    private func modifierBinding(_ key: Modifiers) -> Binding<Bool> {
        Binding(
            get: { rule.modifiers.contains(key) },
            set: { on in if on { rule.modifiers.insert(key) } else { rule.modifiers.remove(key) } }
        )
    }

    private var feedback: (text: String, symbol: String, isProblem: Bool) {
        let normalized = rule.normalized()
        if let problem = normalized.validationProblem {
            // Before anything is typed, a gentle hint rather than an error.
            let untouched = rule.host.isEmpty && rule.path.isEmpty && rule.fileExtensions.isEmpty && rule.sourceApp == nil && rule.modifiers.isEmpty
            return (problem, untouched ? "info.circle" : "exclamationmark.triangle.fill", !untouched)
        }
        if normalized.isBlocked(byAskModifiers: model.config.askModifiers) {
            let keys = model.config.askModifiers.symbol
            return ("Holding \(keys) always shows the picker (Rules › “Always show the picker while holding”), so this rule won't run. Choose other keys, or change that setting.",
                    "exclamationmark.triangle.fill", true)
        }
        return ("Matches: \(normalized.conditionSummary)", "checkmark.circle", false)
    }

    private func save() {
        let normalized = rule.normalized()
        guard normalized.validationProblem == nil else { return }
        onDone(normalized)
    }

    private func chooseSourceApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose the app links come from."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        let match = SourceAppMatch(bundleID: id, name: AppModel.displayName(of: url))
        if !sourceApps.contains(match) { sourceApps.insert(match, at: 0) }
        rule.sourceApp = match
    }

    /// Running apps with a Dock icon, plus the rule's current app.
    static func candidateSourceApps(including current: SourceAppMatch?) -> [SourceAppMatch] {
        var apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> SourceAppMatch? in
                guard let id = app.bundleIdentifier else { return nil }
                return SourceAppMatch(bundleID: id, name: app.localizedName ?? id)
            }
        if let current, !apps.contains(where: { $0.bundleID == current.bundleID }) {
            apps.append(current)
        }
        var seen = Set<String>()
        return apps.filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

