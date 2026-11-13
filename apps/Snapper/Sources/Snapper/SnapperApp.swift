import AppKit
import SlopKit
import SnapperCore
import SwiftUI

// Archetype: menu bar utility + overlays (the capture overlay, capture cards, pins) + a
// document-style window (the annotation editor). See docs/design-system.md, section 2.

extension KeyboardShortcuts.Name {
    // ⌥⇧⌘ + the digits people know from the popular screenshot tool's ⇧⌘2–5 (2 text, 3 full
    // screen, 4 area, 5 All-in-One) plus 6 for recording. The extra ⌥ keeps them clear of
    // macOS's own (⇧⌘3/4/5, ⌃⇧⌘3/4), of that tool, and of typing (⌘ prevents symbols).
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.option, .shift, .command]))
    static let allInOne = Self("allInOne", default: .init(.five, modifiers: [.option, .shift, .command]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.three, modifiers: [.option, .shift, .command]))
    static let captureText = Self("captureText", default: .init(.two, modifiers: [.option, .shift, .command]))
    static let recordScreen = Self("recordScreen", default: .init(.six, modifiers: [.option, .shift, .command]))
    static let captureWindow = Self("captureWindow")
    static let capturePreviousArea = Self("capturePreviousArea")
    static let scrolling = Self("scrollingCapture")
    static let selfTimer = Self("selfTimer")
    static let toggleDesktopIcons = Self("toggleDesktopIcons")
    static let pinFile = Self("pinFile")
    static let reopenLast = Self("reopenLastCapture")
    static let closeAllCards = Self("closeAllCards")
    static let openHistory = Self("openHistory")

    /// The shortcut for each capture mode.
    static func forMode(_ mode: CaptureMode) -> Self {
        switch mode {
        case .allInOne: .allInOne
        case .area: .captureArea
        case .previousArea: .capturePreviousArea
        case .fullScreen: .captureFullScreen
        case .window: .captureWindow
        case .scrolling: .scrolling
        case .selfTimer: .selfTimer
        case .text: .captureText
        case .recording: .recordScreen
        }
    }
}

@main
struct SnapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey, store: Preferences.store) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Snapper")

    init() {
        // Before any menu reads a shortcut.
        AppDelegate.isolateShortcuts()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            SnapperMenu(model: model, info: info)
        } label: {
            Image(systemName: model.isRecording ? "stop.circle.fill" : model.isCapturing ? "camera.fill" : "camera")
                .accessibilityLabel(model.isRecording ? "Snapper, recording" : "Snapper")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CaptureCommands(model: model, info: info)
            EditorCommands()
        }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// File-menu captures and Help, for when Snapper is the active app (status item hidden
/// by the notch, or simply quicker from the menu bar).
struct CaptureCommands: Commands {
    let model: AppModel
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                captureButton(mode, .forMode(mode))
            }
            Divider()
            Button("Annotate Clipboard Image") { model.annotateClipboard() }
            Button("Pin Clipboard Image") { model.pinClipboard() }
            Button("Annotate Image File…") { model.chooseImage { EditorWindowController.open($0, model: model) } }
                .keyboardShortcut("o")
            Button("Pin Image File…") { model.chooseImage { model.pins.pin($0) } }
            Divider()
            Button("Reopen Last Capture") { model.reopenLastCapture() }
            historyButton
        }
        HelpCommands(info: info) {
            Button("Snapper Help") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Snapper"))
            }
        }
    }

    @MainActor
    private var historyButton: some View {
        let shortcut = KeyboardShortcuts.getShortcut(for: .openHistory)
        return Button("Capture History…") { HistoryWindowController.show() }
            .keyboardShortcut(shortcut?.menuKey.map { KeyboardShortcut($0, modifiers: shortcut!.eventModifiers) })
    }

    @MainActor
    private func captureButton(_ mode: CaptureMode, _ name: KeyboardShortcuts.Name) -> some View {
        let button = Button(mode.title) {
            // Let the menu close (and our windows step aside) before the screen freezes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.capture(mode) }
        }
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        return button.keyboardShortcut(shortcut?.menuKey.map { KeyboardShortcut($0, modifiers: shortcut!.eventModifiers) })
    }
}

/// Status line → captures (in the order people know) → desktop icons → images → open
/// captures → footer.
struct SnapperMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        if !model.hasPermission {
            Text("Screen Recording is off")
            Button("Allow Screen Recording…") { PermissionWindow.show() }
            Divider()
        }
        if model.isRecording {
            Button(model.recordingPhase == .ready ? "Cancel Recording" : "Stop Recording") { model.recording.stop() }
            if model.recordingPhase == .recording || model.recordingPhase == .paused {
                Button(model.recordingPhase == .paused ? "Resume Recording" : "Pause Recording") { model.recording.togglePause() }
                Button("Discard Recording") { model.recording.discard() }
            }
            Divider()
        }

        ForEach(CaptureMode.allCases, id: \.self) { mode in
            if !(mode == .recording && model.isRecording) {
                captureButton(mode, shortcut: .forMode(mode))
            }
        }
        Divider()

        // "in Captures": the icons are only left out of captures; the desktop doesn't change.
        Toggle("Hide Desktop Icons in Captures", isOn: $model.hideDesktopIcons)
        Divider()

        Button("Annotate Image File…") { model.chooseImage { EditorWindowController.open($0, model: model) } }
        Button("Pin Image File…") { model.chooseImage { model.pins.pin($0) } }
        Button("Annotate Clipboard Image") { model.annotateClipboard() }
        Button("Pin Clipboard Image") { model.pinClipboard() }
        Divider()

        Button("Reopen Last Capture") { model.reopenLastCapture() }
            .disabled(!model.canReopen)
        Button("Close All Thumbnails") { model.cards.closeAll() }
            .disabled(model.openCards == 0)
        Button("Close All Pins") { model.pins.closeAll() }
            .disabled(model.openPins == 0)
        Divider()

        historyButton

        MenuFooter(info: info)
            .onAppear { model.refreshPermission() }
    }

    @ViewBuilder
    private var historyButton: some View {
        let button = Button("Capture History…") { HistoryWindowController.show() }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .openHistory), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }

    @ViewBuilder
    private func captureButton(_ mode: CaptureMode, shortcut name: KeyboardShortcuts.Name) -> some View {
        let button = Button(mode.title) {
            // Let the menu close before the overlay freezes the screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.capture(mode) }
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: name), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }
}

extension KeyboardShortcuts.Shortcut {
    /// The shortcut as a SwiftUI key equivalent, so the menu shows it. Letters and digits only.
    var menuKey: KeyEquivalent? {
        guard let last = description.last, last.isLetter || last.isNumber else { return nil }
        return KeyEquivalent(Character(last.lowercased()))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    /// Every global shortcut name (Settings → Shortcuts lists the same).
    static var shortcutNames: [KeyboardShortcuts.Name] {
        CaptureMode.allCases.map(KeyboardShortcuts.Name.forMode) + [.toggleDesktopIcons, .pinFile, .reopenLast, .closeAllCards, .openHistory]
    }

    /// A test copy (`SNAPPER_DEFAULTS_SUITE`) shows Snapper's default shortcuts, not the
    /// installed copy's own choices: the shortcuts library reads the app's standard defaults,
    /// so the defaults go in this process's argument domain, which is read first and never
    /// written to disk.
    static func isolateShortcuts() {
        guard Diagnostics.defaultsSuite != nil else { return }
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for name in shortcutNames {
            let key = "KeyboardShortcuts_\(name.rawValue)"
            if let shortcut = name.defaultShortcut, let data = try? JSONEncoder().encode(shortcut) {
                values[key] = String(decoding: data, as: UTF8.self)
            } else {
                values[key] = false // "no shortcut"
            }
        }
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        Diagnostics.record("test shortcuts isolated area=\(KeyboardShortcuts.getShortcut(for: .captureArea)?.description ?? "none")")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TemporaryFiles.clear()
        AppPresence.start()
        AppModel.shared.history.start()
        let model = AppModel.shared
        // Shortcuts live in the app's own defaults: a test copy with its own suite leaves them be.
        if Diagnostics.defaultsSuite == nil { Self.migrateShortcuts() }
        if !Diagnostics.noShortcuts { installShortcuts(model) }
        if Diagnostics.testHooks { installTestHooks(model) }
        TestScene.showIfRequested()
        if let scene = Showcase.scene { ShowcaseScenes.run(scene, model: model) }
        HiddenIconHint.checkSoon()
        Diagnostics.record("launched permission=\(model.hasPermission) shortcuts=\(!Diagnostics.noShortcuts)")
    }

    /// The global shortcuts (not in test copies with `SNAPPER_NO_SHORTCUTS`).
    private func installShortcuts(_ model: AppModel) {
        for mode in CaptureMode.allCases {
            KeyboardShortcuts.onKeyDown(for: .forMode(mode)) { model.capture(mode, started: Diagnostics.now()) }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleDesktopIcons) {
            model.hideDesktopIcons.toggle()
            HUD.show(model.hideDesktopIcons ? "Desktop icons hidden in captures" : "Desktop icons shown in captures", systemImage: "menubar.dock.rectangle")
        }
        KeyboardShortcuts.onKeyDown(for: .pinFile) { model.chooseImage { model.pins.pin($0) } }
        KeyboardShortcuts.onKeyDown(for: .reopenLast) { model.reopenLastCapture() }
        KeyboardShortcuts.onKeyDown(for: .closeAllCards) { model.cards.closeAll() }
        KeyboardShortcuts.onKeyDown(for: .openHistory) { HistoryWindowController.show() }
    }

    /// Finder ▸ Open With, `open -a Snapper image.png`, or a drop on the Dock icon: each
    /// image opens in the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        var opened = 0
        for url in urls where url.scheme?.lowercased() == "snapper" {
            URLCommand.run(url, model: model)
        }
        let urls = urls.filter { $0.scheme?.lowercased() != "snapper" }
        guard !urls.isEmpty else { return }
        for url in urls {
            guard let image = NSImage(contentsOf: url), let item = AppModel.item(from: image) else { continue }
            item.sourceName = url.deletingPathExtension().lastPathComponent
            EditorWindowController.open(item, model: model)
            opened += 1
        }
        Diagnostics.record("opened files=\(urls.count) images=\(opened)")
        if opened < urls.count {
            // The fixed part first: a long file name is what gets cut off.
            let message = urls.count == 1 ? "Not a readable image: \(urls[0].lastPathComponent)" : "\(urls.count - opened) files aren't readable images"
            HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(2.5))
        }
    }

    /// 0.2 had ⌥⇧⌘5 on Capture Window; it's All-in-One's now (Space switches to window
    /// picking). Once, free the old default so the two don't collide.
    private static func migrateShortcuts() {
        let key = "migratedShortcuts.v3"
        guard !Preferences.store.bool(forKey: key) else { return }
        Preferences.store.set(true, forKey: key)
        let old = KeyboardShortcuts.Shortcut(.five, modifiers: [.option, .shift, .command])
        if KeyboardShortcuts.getShortcut(for: .captureWindow) == old {
            KeyboardShortcuts.setShortcut(nil, for: .captureWindow)
            if KeyboardShortcuts.getShortcut(for: .allInOne) == nil { KeyboardShortcuts.setShortcut(old, for: .allInOne) }
        }
    }

    /// Edited images that would be lost (opened files aren't in History, and with History
    /// off nothing is): with History on they're kept there, like every capture; with it off,
    /// Snapper asks first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        EditorWindowController.commitAll()
        let unsaved = model.unsavedEdits
        guard !unsaved.isEmpty else { return .terminateNow }
        if model.history.isOn {
            Task {
                for item in unsaved { await model.history.recordNow(item, kind: .screenshot, source: nil) }
                Diagnostics.record("quit kept edited images in history count=\(unsaved.count)")
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        let alert = NSAlert()
        alert.messageText = unsaved.count == 1 ? "Quit and lose your edits to an image?" : "Quit and lose your edits to \(unsaved.count) images?"
        alert.informativeText = "History is off, so edits that aren't saved, copied or dragged out are gone when Snapper quits."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        alert.buttons.last?.hasDestructiveAction = true
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        TemporaryFiles.clear()
        // Deleted history captures can't be undone after quitting: erase them now.
        try? FileManager.default.removeItem(at: HistoryController.rootURL.appendingPathComponent(".deleted"))
    }

    private func installTestHooks(_ model: AppModel) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.snapper.test."
        for mode in CaptureMode.allCases {
            center.addObserver(forName: .init(prefix + mode.rawValue), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { model.capture(mode, started: Diagnostics.now()) }
            }
        }
        let actions: [String: @MainActor () -> Void] = [
            "cancel": { RegionOverlay.current?.cancel() },
            "closeCards": { model.cards.closeAll() },
            "closePins": { model.pins.closeAll() },
            "scrollingScene": {
                guard let region = TestScene.region(inset: 40), ScrollingCapture.current == nil else { return }
                Task { await model.captureScrolling(region) }
            },
            "windowScene": {
                guard let id = TestScene.recordingTarget?.id, let window = WindowList.onScreen().first(where: { $0.id == id }) else { return }
                Task { await model.captureWindow(window, started: Diagnostics.now()) }
            },
            "windowOther": {
                // Any window that isn't the scene: test mode must refuse it.
                guard let window = WindowList.onScreen().first(where: { $0.ownerPID != ProcessInfo.processInfo.processIdentifier && $0.layer == 0 }) else { return }
                Task { await model.captureWindow(window, started: Diagnostics.now()) }
            },
            "recordScene": { if let region = TestScene.region(inset: 20) { model.recording.ready(region) } },
            "recordOutside": {
                // A region that misses the scene: test mode must refuse to record it.
                guard let screen = NSScreen.main else { return }
                let region = PickedRegion(screen: screen, local: CGRect(x: 0, y: 0, width: 200, height: 120), frozen: nil, window: nil)
                model.recording.ready(region)
            },
            "scrollingStart": { ScrollingCapture.current?.start() },
            "scrollingDone": { ScrollingCapture.current?.finish() },
            "scrollingCancel": { ScrollingCapture.current?.cancel() },
            "scrollScene": { TestScene.scroll(by: 180) },
            "recordVideo": { model.recording.record(gif: false) },
            "recordGIF": { model.recording.record(gif: true) },
            "recordStop": { model.recording.stop() },
            "recordPause": { model.recording.togglePause() },
            "recordDiscard": { model.recording.discard() },
            // Recording extras (test mode uses the test microphone and camera; nothing real).
            "recordMicOn": { model.recording.chooseMicrophone(FakeMediaDevices.microphone.id) },
            "recordMicOff": { model.recording.chooseMicrophone(nil) },
            "recordComputerAudioOn": { model.recordComputerAudio = true },
            "recordComputerAudioOff": { model.recordComputerAudio = false },
            "recordCameraOn": { model.recording.chooseCamera(FakeMediaDevices.camera.id) },
            "recordCameraOff": { model.recording.chooseCamera(nil) },
            "recordCameraLarger": { if let width = model.recording.camera.frame?.width { model.recording.camera.resize(to: width * 1.3) } },
            "recordCameraRounded": { model.recording.camera.setShape(.roundedRectangle) },
            "recordCameraCircle": { model.recording.camera.setShape(.circle) },
            "recordClicksOn": { model.recordShowClicks = true },
            "recordClicksOff": { model.recordShowClicks = false },
            "recordKeysOn": { model.recording.toggleKeys(on: true) },
            "recordKeysOff": { model.recordShowKeys = false },
            "recordKeysAll": { model.keystrokeMode = .allKeys },
            "recordKeysShortcuts": { model.keystrokeMode = .shortcuts },
            "recordClick": {
                // A synthetic click in the middle of the scene (no real mouse).
                guard let region = TestScene.region() else { return }
                InputOverlay.current?.showClick(at: CGPoint(x: region.global.midX, y: region.global.midY))
            },
            "recordKeyShortcut": { InputOverlay.current?.show(KeyStroke(keyCode: 21, key: "4", typed: "$", modifiers: [.command, .shift])) },
            "recordKeyTyping": {
                for (index, key) in "hello".enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                        InputOverlay.current?.show(KeyStroke(keyCode: 0, key: String(key)))
                    }
                }
            },
            "snapshotRecordingUI": { Task { await RecordingSnapshots.write(model: model) } },
            "cardFromTestVideo": {
                // `SNAPPER_TEST_VIDEO`: a generated video becomes a recording's thumbnail, as if
                // just recorded (trim tests while the display can't be recorded).
                guard let path = ProcessInfo.processInfo.environment["SNAPPER_TEST_VIDEO"] else { return }
                Task {
                    let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent("Test Recording.mp4")
                    guard (try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)) != nil,
                          let poster = await VideoFrames.poster(of: url) else { return }
                    let duration = await MediaEditor.duration(of: url)
                    model.deliver(poster, scale: 2, displayID: nil, started: Diagnostics.now(), kind: "video", media: MediaFile(url: url, duration: duration))
                }
            },
            "openTestImage": {
                // `SNAPPER_TEST_IMAGE`: opened as Finder's Open With would (never through
                // LaunchServices, which could hand it to an installed copy).
                guard let path = ProcessInfo.processInfo.environment["SNAPPER_TEST_IMAGE"] else { return }
                NSApp.delegate?.application?(NSApp, open: [URL(fileURLWithPath: path)])
            },
            "sceneTone": { TestScene.playTone(seconds: 2.5) },
            "trimWindowLast": { if let item = model.cards.newest { model.openTrimmer(item) } },
            "trimMiddleLast": {
                // The middle half of the newest video, the way the trim window's Trim does it.
                guard let item = model.cards.newest, let media = item.media,
                      let range = TrimRange(start: media.duration / 4, end: media.duration * 3 / 4, duration: media.duration) else { return }
                if let window = TrimWindowController.front { window.trim(to: range) } else { model.trim(item, to: range) }
            },
            "restoreUntrimmedLast": { if let item = model.cards.newest { model.restoreUntrimmed(item) } },
            "countdownCancel": { Countdown.cancel() },
            "allInOneClose": { AllInOneBar.close() },
            "copyTextLast": { if let item = model.cards.newest { model.copyText(item) } },
            "annotateLast": { if let item = model.cards.newest { model.annotate(item) } },
            "editorSample": {
                // A few marks with the rectangle selected, so handles and toolbar states can
                // be screenshotted without the real mouse.
                guard let editor = EditorWindowController.front else { return }
                let size = editor.editor.document.imageSize
                func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
                let box = Annotation(kind: .rectangle, start: at(0.12, 0.18), end: at(0.42, 0.52), color: editor.color.color)
                editor.editor.add(Annotation(kind: .arrow, start: at(0.75, 0.75), end: at(0.46, 0.5), color: editor.color.color))
                editor.editor.add(Annotation(kind: .counter, start: at(0.6, 0.3), color: editor.color.color, number: 1))
                editor.editor.add(Annotation(kind: .text, start: at(0.55, 0.7), color: editor.color.color, text: "Test label"))
                editor.editor.add(box)
                editor.editor.selection = box.id
                editor.tool = .select
                editor.changed()
            },
            "editorCrop": { EditorWindowController.front?.tool = .crop },
            "history": { HistoryWindowController.show() },
            "historyClose": { HistoryWindowController.close() },
            "historySelectFirst": { HistoryWindowController.openState?.move(.home, extending: false) },
            "historySelectAll": { HistoryWindowController.openState?.selectAll() },
            "historyRestore": { HistoryWindowController.openState?.restore() },
            "historyDelete": { HistoryWindowController.openState?.delete(undoManager: HistoryWindowController.undoManager) },
            "historyUndo": { HistoryWindowController.undoManager?.undo() },
            "historyFilterWindows": { HistoryWindowController.openState?.kind = .window },
            "historyFilterAll": { HistoryWindowController.openState?.kind = nil; HistoryWindowController.openState?.search = "" },
            "historySearchNothing": { HistoryWindowController.openState?.search = "Nonexistent App" },
            "historySearchNotes": { HistoryWindowController.openState?.search = "notes" },
            "historySelectSecond": { HistoryWindowController.openState?.move(.home, extending: false); HistoryWindowController.openState?.move(.right, extending: true) },
            "reopenLast": { model.reopenLastCapture() },
            "snapshotWindows": {
                // Draws each of our titled windows into a PNG without the window server (for
                // checks while the display sleeps). Our own windows only.
                let folder = URL(fileURLWithPath: Diagnostics.snapshotDirectory ?? "/tmp/snapper-test/snapshots", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let name = window.title.replacingOccurrences(of: "/", with: "-")
                    try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
                }
            },
            "snapshotCardCodes": {
                // The card's QR row drawn into PNGs without any window (no window server): the
                // test pattern goes through the real code reader, then one and two codes at
                // two widths, light and dark. Offscreen drawing leaves out the panel's glass
                // and the thumbnail's layer, so this checks the row's layout and text only.
                Task { @MainActor in
                    let folder = URL(fileURLWithPath: Diagnostics.snapshotDirectory ?? "/tmp/snapper-test/snapshots", isDirectory: true)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let pattern = TestPatternView(frame: CGRect(x: 0, y: 0, width: 1000, height: 680))
                    guard let rep = pattern.bitmapImageRepForCachingDisplay(in: pattern.bounds) else { return }
                    pattern.cacheDisplay(in: pattern.bounds, to: rep)
                    guard let image = rep.cgImage else { return }
                    let item = CaptureItem(image: image, scale: CGFloat(image.width) / 1000, displayID: nil)
                    let found = (try? await model.codeReader.codes(in: image)) ?? []
                    Diagnostics.record("offscreen codes found=\(found.map(\.payload))")
                    let two = found + [ScannedCode(payload: "WIFI:T:WPA;S:Slopapp Test Network;P:not-a-real-password;;")]
                    for (label, codes) in [("one", found), ("two", two)] {
                        for width in [CGFloat(160), 240] {
                            for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                                let card = CardView(item: item, thumbnailSize: CardController.thumbnailSize(for: item.size, width: width),
                                                    codes: codes, model: model, controller: model.cards)
                                let host = NSHostingView(rootView: card.background(Color(nsColor: .windowBackgroundColor)))
                                host.appearance = NSAppearance(named: name)
                                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                                host.layoutSubtreeIfNeeded()
                                guard let shot = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                                host.cacheDisplay(in: host.bounds, to: shot)
                                try? shot.representation(using: .png, properties: [:])?
                                    .write(to: folder.appendingPathComponent("card-\(label)-\(Int(width))-\(mode).png"))
                            }
                        }
                    }
                    Diagnostics.record("offscreen cards written")
                }
            },
            "historyOff": { model.history.retention = .off },
            "historyMonth": { model.history.retention = .month },
            "editorSelect": { EditorWindowController.front?.tool = .select },
            "editorBackground": { EditorWindowController.front?.toggleBackground() },
            "editorDone": { if let editor = EditorWindowController.front { EditorWindowController.close(model: editor) } },
            "pinLast": { if let item = model.cards.newest { model.pin(item) } },
            "permissionWindow": { PermissionWindow.show() },
            // A live appearance change while windows are open (layers must follow it).
            "appearanceLight": { NSApp.appearance = NSAppearance(named: .aqua) },
            "appearanceDark": { NSApp.appearance = NSAppearance(named: .darkAqua) },
            "openSettings": { AppDelegate.openSettings() },
            "reopen": { _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false) },
            "statusItemInfo": {
                // Where the menu bar icon's window is (diagnostics: a full menu bar hides it).
                for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
                    let screen = window.screen.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none"
                    Diagnostics.record("status item frame=\(window.frame) visible=\(window.isVisible) occluded=\(!window.occlusionState.contains(.visible)) screen=\(screen)")
                }
            },
        ]
        for pane in SettingsPane.allCases {
            center.addObserver(forName: .init(prefix + "settings." + pane.rawValue), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SettingsNavigation.shared.pane = pane }
            }
        }
        for (name, action) in actions {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            }
        }
    }

    /// Opening Snapper again (Finder, Spotlight, the Dock) brings the menu bar icon back and
    /// opens Settings: the way in when a full menu bar hides the icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Diagnostics.record("reopened visibleWindows=\(flag)")
        guard Diagnostics.defaultsSuite != nil else {
            return standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
        }
        // A test copy: SlopKit's handler writes the icon setting to the app's own defaults
        // (the installed copy's); write ours instead and open Settings the same way.
        Preferences.store.set(true, forKey: MenuBarIcon.storageKey)
        if !flag { Self.openSettings() }
        return true
    }

    /// The app menu's own Settings… item (the SwiftUI Settings scene has no API).
    static func openSettings() {
        NSApp.activate()
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: index)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// `snapper://` commands, for launchers and scripts:
/// `snapper://open-history`, `snapper://restore-recently-closed`, and each capture mode
/// (`snapper://capture-area`, `…/capture-window`, `…/capture-full-screen`, `…/all-in-one`, …).
@MainActor
enum URLCommand {
    static func run(_ url: URL, model: AppModel) {
        let command = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        Diagnostics.record("url command=\(command)")
        switch command {
        case "open-history", "history": HistoryWindowController.show()
        case "restore-recently-closed", "reopen-last-capture": model.reopenLastCapture()
        case "capture-area": model.capture(.area)
        case "capture-previous-area": model.capture(.previousArea)
        case "capture-full-screen", "capture-fullscreen": model.capture(.fullScreen)
        case "capture-window": model.capture(.window)
        case "scrolling-capture": model.capture(.scrolling)
        case "self-timer": model.capture(.selfTimer)
        case "capture-text": model.capture(.text)
        case "record-screen": model.capture(.recording)
        case "all-in-one": model.capture(.allInOne)
        default: HUD.show("Snapper doesn't know “\(command)”", systemImage: "questionmark.circle")
        }
    }
}
