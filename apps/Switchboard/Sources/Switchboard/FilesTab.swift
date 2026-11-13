import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// File types Switchboard can open, so rules choose where those files go. Each one is the
/// user's choice: "Open with Switchboard…" asks macOS, and "Give Back To" undoes it.
struct FilesTab: View {
    @Bindable var model: AppModel

    /// Presets first, then types the user added.
    private var types: [FileType] {
        let added = model.config.fileTypes.filter { type in !FileType.presets.contains { $0.id == type.id } }
        return FileType.presets.map { preset in model.config.fileTypes.first { $0.id == preset.id } ?? preset } + added
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    status(isOurs: model.isDefaultBrowser)
                } label: {
                    Text("Web pages")
                    Text("HTML files open in your browsers, through your rules. Part of being the default browser.")
                }
            } header: {
                Text("When Switchboard opens a type of file, your rules for files choose where each one goes (by type, the app it came from, or the keys you hold). Otherwise it opens where it used to.")
                    .font(.callout)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityRemoveTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(types) { type in
                FileTypeSection(type: type, model: model)
            }

            Section {
                Button("Add File Type…", action: addType)
                    .help("Choose a file of the type Switchboard should open")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
    }

    private func status(isOurs: Bool) -> some View {
        Group {
            if isOurs {
                Label {
                    Text("Switchboard")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Not Switchboard").foregroundStyle(.secondary)
            }
        }
    }

    private func addType() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a file of the type Switchboard should open."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
              !uti.conforms(to: .html), !uti.conforms(to: .directory), !uti.conforms(to: .application) else {
            HUD.show("Switchboard can't open that kind of file.", systemImage: "exclamationmark.triangle")
            return
        }
        if FileType.presets.contains(where: { $0.typeIdentifiers.contains(uti.identifier) })
            || model.config.fileTypes.contains(where: { $0.typeIdentifiers.contains(uti.identifier) }) {
            HUD.show("That type is already listed.", systemImage: "info.circle")
            return
        }
        var extensions = uti.tags[.filenameExtension] ?? []
        if extensions.isEmpty, !url.pathExtension.isEmpty { extensions = [url.pathExtension.lowercased()] }
        let name = uti.localizedDescription.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ".\(extensions.first ?? "") files"
        let type = FileType(id: uti.identifier, name: name, typeIdentifiers: [uti.identifier], extensions: extensions)
        model.config.fileTypes.append(type)
        model.takeOver(type)
    }
}

private struct FileTypeSection: View {
    let type: FileType
    @Bindable var model: AppModel

    private var holder: AppRef? { model.fileTypeHolders[type.id] }
    private var isOurs: Bool { model.roles.isOurs(holder) }
    private var index: Int? { model.config.fileTypes.firstIndex { $0.id == type.id } }
    private var isAdded: Bool { !FileType.presets.contains { $0.id == type.id } }

    var body: some View {
        Section {
            LabeledContent {
                if isOurs {
                    Menu("Give Back To") {
                        let candidates = model.candidates(for: type)
                        if let app = type.app, let original = candidates.first(where: { $0.bundleID == app.bundleID }) {
                            Button("\(original.name)…") { model.handBack(type, to: AppRef(path: original.path, bundleID: original.bundleID)) }
                            Divider()
                        }
                        ForEach(candidates.filter { $0.bundleID != type.app?.bundleID }, id: \.bundleID) { app in
                            Button("\(app.name)…") { model.handBack(type, to: AppRef(path: app.path, bundleID: app.bundleID)) }
                        }
                    }
                    .fixedSize()
                } else {
                    Button("Open with Switchboard") { model.takeOver(type) }
                }
            } label: {
                Text(type.name)
                Text(subtitle)
            }
            .contextMenu {
                if isAdded, !isOurs {
                    Button("Remove from List", role: .destructive) {
                        model.config.fileTypes.removeAll { $0.id == type.id }
                    }
                }
            }
            if isOurs, !type.opensLinkInside, let index {
                Picker("When no rule matches", selection: $model.config.fileTypes[index].fallback) {
                    if let app = type.app {
                        Text("Open in \(app.appName)").tag(Fallback.open(targetID: app.id))
                    }
                    Text("Show the picker").tag(Fallback.ask)
                    Divider()
                    ForEach(model.config.targets) { target in
                        Text("Open in \(target.displayName)").tag(Fallback.open(targetID: target.id))
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let extensions = type.extensions.map { "." + $0 }.joined(separator: ", ")
        if type.opensLinkInside {
            return isOurs
                ? "\(extensions): the link inside opens like any other link, through your rules."
                : "\(extensions) files open in \(holderName). With Switchboard, the link inside goes through your rules."
        }
        if isOurs { return "\(extensions) files go through your rules for files." }
        return "\(extensions) files open in \(holderName)."
    }

    private var holderName: String {
        holder.map { AppModel.displayName(of: URL(fileURLWithPath: $0.path)) } ?? "no app"
    }
}
