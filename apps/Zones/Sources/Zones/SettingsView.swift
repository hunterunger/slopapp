import SlopKit
import SwiftUI
import ZonesCore

/// General, Places, Shortcuts, About. Mirrors `SlopSettings`, plus a Places tab and data
/// credits in About (which `SlopSettings` has no slot for).
struct ZonesSettingsView: View {
    @Bindable var model: ZonesModel
    let panel: PanelState
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                GeneralRows(model: model, panel: panel)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            PlacesSettingsTab(model: model)
                .tabItem { Label("Places", systemImage: "globe") }

            SettingsForm {
                ShortcutRow("Open Zones", name: .togglePanel)
                Text("Opens the panel from any app, even when the menu bar icon is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }

            CreditedAboutView(info: info)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
        .onAppear { AppController.shared.refreshStatusItemVisibility() }
        .onChange(of: model.preferences.menuBarDisplay) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { AppController.shared.refreshStatusItemVisibility() }
        }
    }
}

struct GeneralRows: View {
    @Bindable var model: ZonesModel
    let panel: PanelState

    var body: some View {
        Toggle("Show local time", isOn: $model.preferences.showLocalTime)
        Picker("Time format", selection: $model.preferences.hourCycle) {
            ForEach(HourCycle.allCases) { Text($0.title).tag($0) }
        }
        Picker("Copy format", selection: $model.preferences.copyFormat) {
            ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
        }
        Picker("Menu bar shows", selection: $model.preferences.menuBarDisplay) {
            ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
        }
        if model.preferences.menuBarDisplay.showsTime {
            Picker("Menu bar clock", selection: menuBarPlace) {
                Text("Local time (\(model.localPlace.label))").tag(ClockRow.localID)
                ForEach(model.places) { place in
                    Text(place.label).tag(place.id)
                }
            }
        }
        if panel.statusItemHiddenBySystem {
            Label {
                Text(model.preferences.menuBarDisplay.showsTime
                     ? "macOS is hiding the menu bar item because the menu bar is full. Icon only takes the least space. Settings → Shortcuts can open Zones from the keyboard."
                     : "macOS is hiding the menu bar item because the menu bar is full. Settings → Shortcuts can open Zones from the keyboard.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var menuBarPlace: Binding<UUID> {
        Binding(
            get: { model.menuBarPlace?.id ?? ClockRow.localID },
            set: { model.preferences.menuBarPlaceID = $0 }
        )
    }
}

/// Reorder by dragging, rename in place, remove with Undo.
struct PlacesSettingsTab: View {
    @Bindable var model: ZonesModel
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            List(selection: $selection) {
                ForEach(model.places) { place in
                    PlaceSettingsRow(place: place, model: model)
                        .tag(place.id)
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) { model.remove(model.places[index].id) }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 240)
            .onDeleteCommand {
                if let selection { model.remove(selection) }
            }
            .overlay {
                if model.places.isEmpty {
                    Text("No places yet. Add some from the menu bar panel.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Add Place…") { AppController.shared.showPanel(search: true) }
                Button("Sort by Time Difference") { model.sortByTimeDifference() }
                    .disabled(model.places.count < 2)
                Spacer()
                if let undo = model.pendingUndo {
                    Text(undo.message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Undo") { model.undo() }
                        .keyboardShortcut("z")
                }
            }
            Text("Drag to reorder. Click a name to rename it; leave it empty to go back to the original.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.windowMargin)
    }
}

struct PlaceSettingsRow: View {
    let place: Place
    @Bindable var model: ZonesModel
    @State private var name = ""

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 1) {
                TextField("Name", text: $name, prompt: Text(place.name))
                    .textFieldStyle(.plain)
                    .onSubmit { model.rename(place.id, to: name) }
                    .onChange(of: name) { _, value in model.rename(place.id, to: value) }
                    .accessibilityLabel("Name for \(place.name)")
                Text(place.customName == nil ? place.detail : "\(place.name) · \(place.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.formatter.time(model.now, in: place.timeZone))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button { model.remove(place.id) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove \(place.label)")
            .accessibilityLabel("Remove \(place.label)")
        }
        .onAppear { name = place.label }
    }
}

/// The standard About view plus where the city data comes from (its license asks for credit).
/// Candidate for SlopKit: an `AboutView` with a credits slot.
struct CreditedAboutView: View {
    let info: AppInfo

    var body: some View {
        VStack(spacing: 0) {
            AboutView(info: info)
            VStack(spacing: Spacing.xs) {
                Text("City names from GeoNames, licensed under CC BY 4.0.")
                HStack(spacing: Spacing.m) {
                    Link("geonames.org", destination: URL(string: "https://www.geonames.org")!)
                    Link("License", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
                Text("Time zone rules come from macOS.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xl)
        }
    }
}

/// About window for the panel's "About Zones" (SlopKit's `AboutWindow` has no credits slot).
@MainActor
enum CreditedAboutWindow {
    private static var window: NSWindow?

    static func show(info: AppInfo) {
        if window == nil {
            let hosting = NSHostingController(rootView: CreditedAboutView(info: info))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "About \(info.name)"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
