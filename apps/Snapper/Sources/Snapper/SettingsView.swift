import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// Settings, laid out like the screenshot tool people switch from: a sidebar of panes
/// (General, Shortcuts, Quick Access, Screenshots, Recording, Annotate, Advanced, About) and
/// a grouped form on the right. Built from SlopKit's pieces (launch-at-login toggle, menu
/// bar icon key, About view); `SlopSettings` is a tab view with three fixed tabs, and
/// Snapper has eight panes. (Worth a sidebar variant in SlopKit.)
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @Bindable private var navigation = SettingsNavigation.shared

    var body: some View {
        // A real split view, so the sidebar gets the system's own inset, rounded sidebar and
        // the pane's title sits over the detail column, like System Settings.
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { navigation.pane }, set: { if let pane = $0 { navigation.pane = pane } })) { pane in
                // The system sidebar tints these with the accent (grey in a background window),
                // like Finder and Mail on Golden Gate.
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
            .frame(width: 200)
            .toolbar(removing: .sidebarToggle)
            .accessibilityLabel("Settings sections")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigation.pane.title)
        }
        .frame(width: 760, height: 560)
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane {
        case .general: GeneralPane(model: model, info: info)
        case .shortcuts: ShortcutsPane()
        case .quickAccess: QuickAccessPane(model: model)
        case .screenshots: ScreenshotsPane(model: model)
        case .recording: RecordingPane(model: model)
        case .annotate: AnnotatePane(model: model)
        case .history: HistoryPane(history: model.history)
        case .advanced: AdvancedPane(model: model)
        case .about: AboutView(info: info).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Which pane Settings shows (shared, so test hooks can switch panes).
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var pane: SettingsPane = .general
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, quickAccess, screenshots, recording, annotate, history, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .quickAccess: "Quick Access"
        case .screenshots: "Screenshots"
        case .recording: "Recording"
        case .annotate: "Annotate"
        case .history: "History"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .quickAccess: "rectangle.bottomhalf.inset.filled"
        case .screenshots: "camera"
        case .recording: "record.circle"
        case .annotate: "pencil.tip.crop.circle"
        case .history: "clock.arrow.circlepath"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

/// A scrolling grouped form for one pane.
struct Pane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

// MARK: Panes

struct GeneralPane: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @AppStorage(MenuBarIcon.storageKey, store: Preferences.store) private var showMenuBarIcon = true

    var body: some View {
        Pane {
            Section("App") {
                LaunchAtLoginToggle()
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("To bring the icon back, open \(info.name) again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Capture") {
                Toggle("Hide desktop icons while capturing", isOn: $model.hideDesktopIcons)
            }
            Section("Sounds") {
                Toggle("Play sounds", isOn: $model.playSound)
            }
            Section {
                LabeledContent("Export location") {
                    HStack(spacing: Spacing.s) {
                        Label(model.saveFolder.lastPathComponent, systemImage: "folder")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .help(model.saveFolder.path(percentEncoded: false))
                        Button("Choose…") { chooseFolder() }
                            .disabled(model.saveFolderIsOverridden)
                    }
                }
                if model.saveFolderIsOverridden {
                    Text("Set by SNAPPER_SAVE_DIR for testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.chosenFolder != nil {
                    Button("Use Default Folder") { model.chosenFolder = nil }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Where Save puts captures and recordings, from the thumbnail, the editor and after capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Show thumbnail", isOn: afterCapture(.showCard))
                Toggle("Copy to clipboard", isOn: afterCapture(.copy))
                Toggle("Save to the export location", isOn: afterCapture(.save))
            } header: {
                Text("After Capture")
            } footer: {
                Text("What happens right after a screenshot or recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func afterCapture(_ option: AfterCapture) -> Binding<Bool> {
        Binding(
            get: { model.afterCapture.contains(option) },
            set: { on in
                if on { model.afterCapture.insert(option) } else { model.afterCapture.remove(option) }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.chosenFolder = url.path(percentEncoded: false)
        }
    }
}

struct ShortcutsPane: View {
    var body: some View {
        Pane {
            Section("General") {
                LabeledShortcutRow("All-in-One", name: .allInOne)
                LabeledShortcutRow("Toggle desktop icons", name: .toggleDesktopIcons)
                LabeledShortcutRow("Pin image file", name: .pinFile)
                LabeledShortcutRow("Reopen last capture", name: .reopenLast)
                LabeledShortcutRow("Close all thumbnails", name: .closeAllCards)
                LabeledShortcutRow("Open capture history", name: .openHistory)
            }
            Section("Screenshots") {
                LabeledShortcutRow("Capture area", name: .captureArea)
                LabeledShortcutRow("Capture previous area", name: .capturePreviousArea)
                LabeledShortcutRow("Capture full screen", name: .captureFullScreen)
                LabeledShortcutRow("Capture window", name: .captureWindow)
                LabeledShortcutRow("Self-timer", name: .selfTimer)
                LabeledShortcutRow("Scrolling capture", name: .scrolling)
            }
            Section("Text and Recording") {
                LabeledShortcutRow("Capture text", name: .captureText)
                LabeledShortcutRow("Record screen / stop", name: .recordScreen)
            }
            Section {
                Text("While selecting: Space switches between area and window, Shift makes a square, Option grows from the center, arrow keys move the pointer, Return takes the whole screen, Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct QuickAccessPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Pane {
            Section("Appearance") {
                Picker("Position on screen", selection: $model.cardCorner) {
                    ForEach(CardCorner.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $model.cardFollowsPointer) {
                    Text("Move to active screen")
                    Text("The screen the pointer is on.")
                }
                LabeledContent("Thumbnail size") {
                    Slider(value: $model.cardWidth, in: 160...320, step: 20) {
                        Text("Thumbnail size")
                    } minimumValueLabel: {
                        Image(systemName: "photo").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "photo").imageScale(.large)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Toggle(isOn: $model.showsCodes) {
                    Text("Show QR code contents")
                    Text("Reads any QR code in a capture, on this Mac, and shows it under the thumbnail.")
                }
            }
            Section("Behavior") {
                Picker("Auto-close", selection: $model.autoClose) {
                    ForEach(AutoClose.allCases) { Text($0.title).tag($0) }
                }
                Picker("Then", selection: $model.autoCloseAction) {
                    ForEach(AutoCloseAction.allCases) { Text($0.title).tag($0) }
                }
                .disabled(model.autoClose == .never)
                Toggle(isOn: $model.closeAfterDragging) {
                    Text("Close after dragging")
                    Text("Hold Option while dragging to keep the thumbnail.")
                }
                Toggle("Close after copying or saving", isOn: $model.closeAfterCopyOrSave)
                LabeledContent("Save button") {
                    Text("Saves to the export location; Option-click to choose")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ScreenshotsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Pane {
            Section("Output") {
                Picker("File format", selection: $model.format) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Capture") {
                Picker("Self-timer interval", selection: $model.selfTimerInterval) {
                    ForEach(SelfTimer.intervals, id: \.self) { Text("\($0) Seconds").tag($0) }
                }
                Toggle("Show magnifier while selecting", isOn: $model.showMagnifier)
            }
            Section {
                Picker("Background", selection: Binding(get: { model.windowBackground?.rawValue ?? "none" },
                                                        set: { model.windowBackground = GradientPreset(rawValue: $0) })) {
                    Text("Transparent").tag("none")
                    Divider()
                    ForEach(GradientPreset.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Padding") {
                    HStack(spacing: Spacing.s) {
                        Slider(value: $model.windowPadding, in: 16...160, step: 8) { Text("Padding") }
                            .labelsHidden()
                            .frame(width: 220)
                        // A fixed slot so the slider doesn't shift as the number changes width.
                        FixedWidthText(text: "\(Int(model.windowPadding)) pt", variants: ["160 pt"], alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .disabled(model.windowBackground == nil)
                }
                Toggle("Capture window shadow", isOn: $model.includeWindowShadow)
            } header: {
                Text("Window Screenshots")
            } footer: {
                Text("With a background, window captures open with the Background tool's backdrop, which you can change or remove in the editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RecordingPane: View {
    @Bindable var model: AppModel
    /// Re-read when the pane appears (devices come and go; permissions change in System Settings).
    @State private var microphones: [MediaDevice] = []
    @State private var cameras: [MediaDevice] = []
    @State private var keysAllowed = true

    var body: some View {
        Pane {
            Section("General") {
                Toggle("Dim screen while recording", isOn: $model.recordDimScreen)
                Toggle("Show countdown", isOn: $model.recordCountdown)
            }
            Section {
                Picker("Microphone", selection: deviceBinding(.microphone)) {
                    Text("None").tag(String?.none)
                    ForEach(microphones) { Text($0.name).tag(String?.some($0.id)) }
                }
                Toggle(isOn: $model.recordComputerAudio) {
                    Text("Record computer sound")
                    Text("Apps and alerts. Snapper's own sounds are left out.")
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("With both, they're mixed into one track when the recording stops. GIFs have no sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Camera") {
                Picker("Camera", selection: deviceBinding(.camera)) {
                    Text("None").tag(String?.none)
                    ForEach(cameras) { Text($0.name).tag(String?.some($0.id)) }
                }
                Picker("Shape", selection: $model.cameraShape) {
                    ForEach(BubbleShape.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle(isOn: $model.recordShowClicks) {
                    Text("Show clicks")
                    Text("A ring where you click.")
                }
                Toggle(isOn: Binding(get: { model.recordShowKeys }, set: { on in
                    if on, !KeyAccess.isGranted {
                        MediaPermissionWindow.show(.accessibility) { model.recordShowKeys = true; keysAllowed = true }
                    } else {
                        model.recordShowKeys = on
                    }
                })) {
                    Text("Show keystrokes")
                    Text("The keys you press, as a caption at the bottom. Never kept.")
                }
                if model.recordShowKeys {
                    Picker("Keystrokes", selection: $model.keystrokeMode) {
                        ForEach(KeystrokeMode.allCases) { Text($0.title).tag($0) }
                    }
                    if !keysAllowed {
                        LabeledContent {
                            Button("Open System Settings") { Permission.accessibility.request() }
                        } label: {
                            Text("Needs Accessibility")
                            Text("Turn on Snapper under Privacy & Security → Accessibility.")
                        }
                    }
                }
            } header: {
                Text("Clicks and Keys")
            } footer: {
                Text("Shortcuts Only never shows what you type, like passwords or messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Video") {
                Picker("Frame rate", selection: $model.recordFrameRate) {
                    ForEach(RecordingOptions.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Toggle("Show cursor", isOn: $model.recordShowsCursor)
                Toggle("Scale Retina videos to 1x", isOn: $model.recordScaleToOneX)
            }
            Section("GIF") {
                Picker("Frame rate", selection: $model.gifFrameRate) {
                    ForEach(GIFEncoder.Options.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Width", selection: $model.gifWidth) {
                    ForEach(GIFEncoder.Options.widths, id: \.self) { Text("\($0) px").tag($0) }
                }
            }
            Section {
                Text("Videos are MP4 (H.264 with AAC sound); GIFs are silent. Trim a video from its thumbnail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            microphones = MediaEnvironment.devices.devices(.microphone)
            cameras = MediaEnvironment.devices.devices(.camera)
            keysAllowed = KeyAccess.isGranted
        }
    }

    /// None, or the chosen device (the default one when the choice is gone). Picking one asks
    /// for permission if macOS hasn't yet.
    private func deviceBinding(_ kind: MediaKind) -> Binding<String?> {
        Binding {
            let on = kind == .camera ? model.recordCamera : model.recordMicrophone
            guard on else { return nil }
            return kind == .camera ? model.recording.currentCameraID : model.recording.currentMicrophoneID
        } set: { id in
            if kind == .camera { model.recording.chooseCamera(id) } else { model.recording.chooseMicrophone(id) }
        }
    }
}

struct AnnotatePane: View {
    @Bindable var model: AppModel

    var body: some View {
        Pane {
            Section("Tools") {
                Toggle("Draw shadow on objects", isOn: $model.annotateShadows)
            }
            Section("Window") {
                Toggle("Always on top", isOn: $model.annotateAlwaysOnTop)
            }
            Section {
                Text("Tools: V select, R rectangle, F filled rectangle, E ellipse, L line, A arrow, T text, D pencil, M highlighter, P blur and pixelate, H spotlight, C counter, K crop, B background. ] and [ change the line width.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HistoryPane: View {
    @Bindable var history: HistoryController
    @State private var confirmingClear = false
    @State private var confirmingOff = false

    private var usage: String {
        let count = history.entries.count
        let captures = count == 1 ? "1 capture" : "\(count.formatted()) captures"
        return "\(ByteCountFormatter.string(fromByteCount: history.totalBytes, countStyle: .file)) · \(captures)"
    }

    var body: some View {
        Pane {
            Section {
                Picker("Keep captures", selection: Binding(get: { history.retention }, set: { newValue in
                    if newValue == .off, !history.entries.isEmpty { confirmingOff = true } else { history.retention = newValue }
                })) {
                    ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Disk used") {
                    Text(history.isLoaded ? usage : "…")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Capture History") { HistoryWindowController.show() }
                    Spacer()
                    Button("Show in Finder") {
                        let root = HistoryController.rootURL
                        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([root])
                    }
                    Button("Clear History…") { confirmingClear = true }
                        .disabled(history.entries.isEmpty)
                }
            } header: {
                Text("Capture History")
            } footer: {
                Text("Every capture is kept on this Mac with its edits and the app it came from (never window titles), then deleted after the time you pick. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("Clear Capture History?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("All \(history.entries.count.formatted()) captures in history are deleted. This can't be undone. Thumbnails, editors and pins that are open keep theirs.")
        }
        .confirmationDialog("Turn Off Capture History?", isPresented: $confirmingOff) {
            Button("Turn Off", role: .destructive) { history.retention = .off }
        } message: {
            Text("The \(history.entries.count.formatted()) captures in history are deleted, and new ones aren't kept.")
        }
    }
}

struct AdvancedPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Pane {
            Section {
                TextField("File name", text: $model.fileNameTemplate, prompt: Text(FileNaming.defaultTemplate))
                LabeledContent("Example") {
                    Text(FileNaming.baseName(template: model.fileNameTemplate, date: Date()) + "." + model.format.fileExtension)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if model.fileNameTemplate != FileNaming.defaultTemplate {
                    Button("Restore Default") { model.fileNameTemplate = FileNaming.defaultTemplate }
                }
            } header: {
                Text("File Name")
            } footer: {
                Text("Tokens: " + FileNaming.tokens.joined(separator: " ") + ". {type} is Screenshot or Recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Text Recognition") {
                Toggle("Keep line breaks", isOn: $model.ocrKeepLineBreaks)
            }
            Section("Pinned Screenshots") {
                Toggle("Rounded corners", isOn: $model.pinRoundedCorners)
                Toggle("Shadow", isOn: $model.pinShadow)
                Toggle("Border", isOn: $model.pinBorder)
            }
        }
    }
}

/// SlopKit's `ShortcutRow`, but the recorder is named after its row for VoiceOver ("Capture
/// area" rather than an unnamed search field). Worth folding into SlopKit's row. The
/// recorder's ✕ is drawn by KeyboardShortcuts and isn't an accessibility element.
struct LabeledShortcutRow: View {
    let title: String
    let name: KeyboardShortcuts.Name

    init(_ title: String, name: KeyboardShortcuts.Name) {
        self.title = title
        self.name = name
    }

    var body: some View {
        LabeledContent(title) {
            NamedRecorder(title: title, name: name)
                .fixedSize()
        }
    }
}

private struct NamedRecorder: NSViewRepresentable {
    let title: String
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.setAccessibilityLabel(title)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {}
}
