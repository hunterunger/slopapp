import SlopKit
import SwiftUI
import ZonesCore

/// General, Places, Shortcuts, About. Mirrors `SlopSettings`, plus a Places tab and data
/// credits in About (which `SlopSettings` has no slot for).
struct ZonesSettingsView: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let info: AppInfo

    var body: some View {
        TabView(selection: $panel.settingsTab) {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                GeneralRows(model: model, panel: panel)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(PanelState.SettingsTab.general)

            PlacesSettingsTab(model: model, panel: panel)
                .tabItem { Label("Places", systemImage: "globe") }
                .tag(PanelState.SettingsTab.places)

            SettingsForm {
                // ShortcutRow, with its explanation as a subtitle under the title.
                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                } label: {
                    Text("Open Zones")
                    Text("Opens the panel from any app, even when the menu bar icon is hidden.")
                }
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }
            .tag(PanelState.SettingsTab.shortcuts)

            // Padded like SlopKit's AboutSettingsTab (the icon has ~9 pt of clear margin on top).
            CreditedAboutView(info: info)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.l)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(PanelState.SettingsTab.about)
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
        Picker("Row style", selection: $model.preferences.rowStyle) {
            ForEach(RowStyle.allCases) { Text($0.title).tag($0) }
        }
        Picker("Copy format", selection: $model.preferences.copyFormat) {
            ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
        }
        Picker("Menu bar shows", selection: $model.preferences.menuBarDisplay) {
            ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
        }
        if model.preferences.menuBarDisplay.showsTime {
            LabeledContent {
                Text(model.menuBarPlaces.map(\.label).joined(separator: ", "))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Menu bar clocks")
                Text("Choose places with the \(Image(systemName: "menubar.rectangle")) buttons in Places, or right-click a place in the panel. Each clock takes menu bar space.")
                    .accessibilityLabel("Choose places with the menu bar buttons in Places, or right-click a place in the panel. Each clock takes menu bar space.")
            }
            Toggle("Show local time in the menu bar", isOn: Binding(
                get: { model.isInMenuBar(ClockRow.localID) },
                set: { $0 ? model.showInMenuBar(ClockRow.localID) : model.removeFromMenuBar(ClockRow.localID) }
            ))
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
}

/// Default working hours; the list: reorder by dragging, rename in place, each place's
/// own hours and menu bar clock, remove with Undo.
struct PlacesSettingsTab: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsForm {
                Section {
                    WorkingHoursEditor(hours: $model.preferences.defaultWorkingHours,
                                       subtitle: "For local time and every place without its own. Times in working hours show in your accent colour.")
                        .utcTimePickers()
                } header: {
                    Text("Working hours")
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Places")
                    .font(.headline)
                    // On the same line as the form's section header above.
                    .padding(.leading, SettingsMetrics.sectionHeaderInset)
                List(selection: $selection) {
                    ForEach(model.places) { place in
                        PlaceSettingsRow(place: place, model: model, panel: panel)
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
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: "globe")
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No places yet")
                                .font(.headline)
                            Text("Add the cities you work with.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: Spacing.s) {
                    Button("Add Place…") { AppController.shared.showPanel(search: true) }
                    Button("Sort by Time Difference") { model.sortByTimeDifference() }
                        .disabled(model.places.count < 2)
                    Spacer(minLength: Spacing.s)
                    if let undo = model.pendingUndo {
                        Text(undo.message)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Undo") { model.undo() }
                            .keyboardShortcut("z")
                    }
                }
                Text("Drag to reorder. Click a name to rename it; leave it empty to go back to the original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SettingsMetrics.formInset)
            .padding(.bottom, Spacing.windowMargin)
        }
    }
}

/// A grouped `Form`'s geometry, so content below a form lines up with it. Measured on
/// macOS 26 (`scripts/measure line` on Settings → Places).
enum SettingsMetrics {
    /// Sections' edges from the window's sides.
    static let formInset: CGFloat = Spacing.xl
    /// Section headers' and rows' text from a section's edge.
    static let sectionHeaderInset: CGFloat = 10 // lint:allow measured system inset
    /// A bordered list's rows start this much further in than a form's; padding them by it
    /// puts their names on the form's text column.
    static let listRowNudge: CGFloat = 3 // lint:allow measured system inset
}

struct PlaceSettingsRow: View {
    @Environment(\.controlActiveState) private var activeState
    let place: Place
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
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
            HoursButton(place: place, model: model, panel: panel)
            Button {
                if model.isInMenuBar(place.id) { model.removeFromMenuBar(place.id) } else { model.showInMenuBar(place.id) }
            } label: {
                Image(systemName: "menubar.rectangle")
                    .symbolVariant(model.isInMenuBar(place.id) ? .fill : .none)
                    .foregroundStyle(model.isInMenuBar(place.id) ? Color.windowAccent(activeState) : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(model.isInMenuBar(place.id) ? "Remove \(place.label) from the menu bar" : "Show \(place.label) in the menu bar")
            .accessibilityLabel("Show \(place.label) in Menu Bar")
            .accessibilityValue(model.isInMenuBar(place.id) ? "On" : "Off")
            Text(model.formatter.time(model.now, in: place.timeZone))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
            Button { model.remove(place.id) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove \(place.label)")
            .accessibilityLabel("Remove \(place.label)")
        }
        .padding(.leading, SettingsMetrics.listRowNudge)
        .onAppear { name = place.label }
    }
}

/// "Default" or "8:00 AM – 4:00 PM, Sun–Thu"; opens an editor for this place's own hours.
struct HoursButton: View {
    let place: Place
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    @State private var editing = false

    var body: some View {
        Button {
            editing = true
        } label: {
            Text(place.workingHours.map { $0.spanText(formatter: model.formatter) } ?? "Default hours")
                .monospacedDigit()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(place.workingHours.map { "Working hours: \($0.summary(formatter: model.formatter))" } ?? "Uses the default working hours")
        .accessibilityLabel("Working Hours for \(place.label)")
        .accessibilityValue(place.workingHours.map { $0.summary(formatter: model.formatter) } ?? "Default")
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            PlaceHoursEditor(place: place, model: model)
        }
        .onAppear { openIfAsked() }
        .onChange(of: panel.hoursEditingID) { openIfAsked() }
    }

    /// "Working Hours…" in the panel lands here with this place's editor open.
    private func openIfAsked() {
        guard panel.hoursEditingID == place.id else { return }
        panel.hoursEditingID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editing = true }
    }
}

struct PlaceHoursEditor: View {
    let place: Place
    @Bindable var model: ZonesModel

    var body: some View {
        Form {
            Toggle("Use the default hours", isOn: Binding(
                get: { model.places.first { $0.id == place.id }?.workingHours == nil },
                set: { useDefault in
                    model.setWorkingHours(useDefault ? nil : custom(model.preferences.defaultWorkingHours), for: place.id)
                }
            ))
            WorkingHoursEditor(hours: Binding(
                get: { model.workingHours(for: place.id) },
                set: { model.setWorkingHours($0, for: place.id) }
            ))
            .utcTimePickers()
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Turning "default" off starts from the default, one hour later, so it differs (a
    /// place equal to the default stays on the default).
    private func custom(_ hours: WorkingHours) -> WorkingHours {
        WorkingHours(start: (hours.start + 60) % 1440, end: min(1440, hours.end + 60), days: hours.days)
    }
}

/// The standard About view plus where the city data comes from (its license asks for credit).
/// Candidate for SlopKit: an `AboutView` with a credits slot.
struct CreditedAboutView: View {
    let info: AppInfo
    /// In the About window, like SlopKit's `AboutWindow`: the transparent title bar above
    /// already gives the icon room, so drop `AboutView`'s top padding.
    var fillsWindow = false

    var body: some View {
        VStack(spacing: 0) {
            AboutView(info: info)
                .padding(.top, fillsWindow ? -Spacing.xxl : 0)
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
            // The same 24 pt as AboutView's sides and the gap above.
            .padding(.bottom, Spacing.xxl)
        }
    }
}

/// About window for the panel's "About Zones" (SlopKit's `AboutWindow` has no credits slot).
@MainActor
enum CreditedAboutWindow {
    private static var window: NSWindow?

    static func show(info: AppInfo) {
        if window == nil {
            let hosting = NSHostingController(rootView: CreditedAboutView(info: info, fillsWindow: true))
            let newWindow = NSWindow(contentViewController: hosting)
            // Like SlopKit's AboutWindow (and the system About panels): the title is kept for
            // the Window menu and VoiceOver but not drawn; just the close button over the content.
            newWindow.title = "About \(info.name)"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.titlebarSeparatorStyle = .none
            newWindow.isMovableByWindowBackground = true
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
