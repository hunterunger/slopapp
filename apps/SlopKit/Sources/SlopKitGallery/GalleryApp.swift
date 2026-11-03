import AppKit
import SlopKit
import SwiftUI

// Every SlopKit component on one screen, for design review and screenshots.
//
//   swift run --package-path apps/SlopKit SlopKitGallery
//   GALLERY_DEMO=panel|hud|settings ... opens that demo at launch (for screenshots).

extension KeyboardShortcuts.Name {
    static let galleryPanel = Self("galleryPanel")
}

@main
struct GalleryApp: App {
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    private let info = AppInfo(name: "SlopKit Gallery", version: "dev", build: "0",
                               tagline: "Every Slopapp component in one place.")

    init() {
        // `swift run` binaries start as background processes; make it a normal app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("SlopKit Gallery", id: "gallery") {
            GalleryView()
        }
        .defaultSize(width: 640, height: 760)

        MenuBarExtra("Gallery", systemImage: "square.grid.2x2", isInserted: $showMenuBarIcon) {
            Text("Status line goes here")
            Button("Main action") {}
            MenuFooter(info: info)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SlopSettings(info: info, isMenuBarApp: true) {
                Toggle("An app-specific option", isOn: .constant(true))
            } shortcuts: {
                ShortcutRow("Show the picker", name: .galleryPanel)
            }
        }
    }
}

struct GalleryView: View {
    @State private var dropped: [URL] = []
    @State private var queue = FileQueue(processor: DemoProcessor(), acceptedTypes: [.item], maxConcurrent: 2)
    @State private var queueSelection = Set<FileQueueItem.ID>()
    @State private var picked: String?
    @Environment(\.openSettings) private var openSettings
    private let demo = ProcessInfo.processInfo.environment["GALLERY_DEMO"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                section("DropZone") {
                    DropZone("Drop images here", systemImage: "photo.on.rectangle.angled", types: [.image]) {
                        dropped = $0
                    }
                    .frame(height: 200)
                    if !dropped.isEmpty {
                        Text(dropped.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                section("FileQueue") {
                    // The drop-in window body: drop files, watch rows progress. This demo's
                    // processor writes nothing; it just pretends for a moment.
                    FileQueueView(queue: queue, selection: $queueSelection, dropTitle: "Drop any files here")
                        .frame(height: 240)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }

                section("FloatingPanel and HUD") {
                    HStack(spacing: Spacing.s) {
                        Button("Picker near mouse") { PickerDemo.show(at: .nearMouse) { picked = $0 } }
                        Button("Centered") { PickerDemo.show(at: .center) { picked = $0 } }
                        Button("Corner") { PickerDemo.show(at: .corner(.bottomTrailing)) { picked = $0 } }
                        Button("Show HUD") { HUD.show("Copied", systemImage: "doc.on.doc") }
                    }
                    if let picked {
                        Text("Picked \(picked)").font(.callout).foregroundStyle(.secondary)
                    }
                }

                section("PermissionPrompt") {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        ForEach(Permission.allCases) { permission in
                            VStack(spacing: Spacing.xs) {
                                Label(permission.title, systemImage: permission.isGranted ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(permission.isGranted ? .green : .secondary)
                                    .font(.callout)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    GroupBox {
                        PermissionPrompt(permission: .accessibility,
                                         reason: "Tiles moves and resizes windows for you. It can't read what's in them.")
                            .frame(maxWidth: .infinity)
                    }
                }

                section("Settings pieces") {
                    Button("Open Settings…") { openSettings() }
                    Form {
                        ShortcutRow("Show the picker", name: .galleryPanel)
                        LaunchAtLoginToggle()
                    }
                    .formStyle(.grouped)
                    .frame(height: 140)
                }

                section("Type and spacing") {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Title 2").font(.title2.bold())
                        Text("Headline").font(.headline)
                        Text("Body text in sentence case. Buttons are verbs.")
                        Text("Callout, secondary").font(.callout).foregroundStyle(.secondary)
                        Text("4.2 MB → 1.1 MB  −74%").font(.body.monospacedDigit())
                    }
                }
            }
            .padding(Spacing.windowMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 600)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            switch demo {
            case "panel": PickerDemo.show(at: .center) { picked = $0 }
            case "hud": HUD.show("Copied", systemImage: "doc.on.doc", duration: .seconds(30))
            case "settings": openSettings()
            default: break
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// A Switchboard-style chooser: number keys pick, arrows move, Return confirms, Esc closes.
@MainActor
enum PickerDemo {
    static let options = ["Safari", "Firefox", "Chrome", "Arc"]
    private static var panel: FloatingPanel?

    static func show(at placement: PanelPlacement, onPick: @escaping (String) -> Void) {
        let model = PickerModel(options: options)
        let panel = FloatingPanel { PickerList(model: model) }
        func pick(_ index: Int) {
            guard options.indices.contains(index) else { return }
            onPick(options[index])
            panel.dismiss()
        }
        model.onPick = pick
        panel.keyHandler = { event in
            if let digit = event.digit { pick(digit - 1); return true }
            switch event.keyCode {
            case 125: model.move(1); return true      // down
            case 126: model.move(-1); return true     // up
            case 36, 76: pick(model.selection); return true // return, enter
            default: return false
            }
        }
        self.panel = panel
        panel.show(at: placement)
    }
}

@MainActor
@Observable
final class PickerModel {
    let options: [String]
    var selection = 0
    var onPick: (Int) -> Void = { _ in }

    init(options: [String]) { self.options = options }

    func move(_ delta: Int) {
        selection = (selection + delta + options.count) % options.count
    }
}

struct PickerList: View {
    let model: PickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Open link with")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.s)
                .padding(.bottom, Spacing.xs)
            ForEach(Array(model.options.enumerated()), id: \.offset) { index, name in
                Button { model.onPick(index) } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "globe")
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 20)
                        Text(name)
                        Spacer(minLength: Spacing.xl)
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == model.selection ? Color.accentColor.opacity(0.2) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.s)
        .frame(width: 240)
    }
}

/// A FileQueue processor that writes nothing: it reports progress for a second, then says
/// what it would have done. Real apps return `.produced(output:bytes:)` for new files.
struct DemoProcessor: FileProcessor {
    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(100))
            progress(Double(step) / 10)
        }
        return .unchanged(reason: "Demo only. Nothing was written.")
    }
}
