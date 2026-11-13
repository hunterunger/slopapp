import AppKit
import ApplicationServices
import SlopKit
import SwiftUI
import SwitchboardCore

/// Safari profiles and private windows open through Safari's File menu, which needs
/// Accessibility. Says so where those targets are set up, with the way to turn it on, and
/// updates by itself once it's on.
struct AccessibilityNote: View {
    @State private var isTrusted = AXIsProcessTrusted()

    var body: some View {
        Group {
            if isTrusted {
                Label("Opens from Safari's File menu, using Accessibility.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Spacing.s) {
                    Label("Needs Accessibility to open Safari profiles and private windows.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Allow…") { Permission.accessibility.request() }
                        .controlSize(.small)
                }
            }
        }
        .font(.caption)
        .task {
            // Re-check while the note is on screen, until it's granted.
            while !isTrusted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                isTrusted = AXIsProcessTrusted()
            }
        }
    }
}

/// Adds Safari profiles by name. Safari has no profile list other apps can read, except its
/// own File ▸ New Window menu: "Find Profiles" reads the names there (Safari must be open,
/// and Accessibility on).
struct SafariProfileSheet: View {
    let app: InstalledApp
    @Bindable var model: AppModel
    let onDone: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var found: [String]?
    @State private var chosen: Set<String> = []
    @State private var findNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("\(app.name) Profiles")
                .font(.headline)
            if let found, !found.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(found, id: \.self) { profile in
                        Toggle(profile, isOn: Binding(
                            get: { chosen.contains(profile) },
                            set: { on in if on { chosen.insert(profile) } else { chosen.remove(profile) } }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                    GridRow {
                        Text("Profile").gridColumnAlignment(.trailing)
                        TextField("Profile", text: $name, prompt: Text("Work"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Profile")
                    }
                }
                Text("Use the name Safari shows in File › New Window. Switchboard opens the profile's window from there, then the link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s) {
                    Button("Find Profiles") { findProfiles() }
                    if let findNote {
                        Text(findNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            AccessibilityNote()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }

    private var canAdd: Bool {
        if let found, !found.isEmpty { return !chosen.isEmpty }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func findProfiles() {
        guard AXIsProcessTrusted() else {
            findNote = "Allow Accessibility first."
            return
        }
        guard let names = Opener.safari.profileNames(safariURL: URL(fileURLWithPath: app.path)) else {
            findNote = "Open Safari, then try again."
            return
        }
        if names.isEmpty {
            findNote = "Safari has no profiles yet. Add them in Safari › Settings › Profiles."
        } else {
            let existing = Set(model.config.targets.filter { $0.bundleID == app.bundleID }.compactMap { $0.profile?.directory })
            found = names
            chosen = Set(names).subtracting(existing)
        }
    }

    private func add() {
        let names = found.map { list in list.filter(chosen.contains) } ?? [name.trimmingCharacters(in: .whitespaces)]
        var last: UUID?
        for profile in names where !profile.isEmpty {
            last = model.addTarget(app: app, profile: BrowserProfile(directory: profile, name: profile))
        }
        close(last)
    }

    private func close(_ added: UUID?) {
        onDone(added)
        dismiss()
    }
}
