import AppKit
import Observation
import SlopKit
import SnapperCore

/// App state and the actions every surface (menu, hotkeys, cards, editor, pins) shares.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Settings (UserDefaults)

    var afterCapture: AfterCapture {
        didSet { defaults.set(afterCapture.rawValue, forKey: Keys.afterCapture) }
    }
    var cardCorner: CardCorner {
        didSet { defaults.set(cardCorner.rawValue, forKey: Keys.cardCorner); cards.relayout() }
    }
    var autoClose: AutoClose {
        didSet { defaults.set(autoClose.rawValue, forKey: Keys.autoClose); cards.autoCloseChanged() }
    }
    var autoCloseAction: AutoCloseAction {
        didSet { defaults.set(autoCloseAction.rawValue, forKey: Keys.autoCloseAction) }
    }
    var closeAfterDragging: Bool {
        didSet { defaults.set(closeAfterDragging, forKey: Keys.closeAfterDragging) }
    }
    /// Copy and Save from a thumbnail close it (like macOS's own). Off: it stays.
    var closeAfterCopyOrSave: Bool {
        didSet { defaults.set(closeAfterCopyOrSave, forKey: Keys.closeAfterCopyOrSave) }
    }
    /// The folder chosen in Settings (nil = default).
    var chosenFolder: String? {
        didSet { defaults.set(chosenFolder, forKey: Keys.chosenFolder) }
    }
    var format: ImageFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: Keys.includeWindowShadow) }
    }
    var hideDesktopIcons: Bool {
        didSet { defaults.set(hideDesktopIcons, forKey: Keys.hideDesktopIcons) }
    }
    var showMagnifier: Bool {
        didSet { defaults.set(showMagnifier, forKey: Keys.showMagnifier) }
    }
    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }
    var selfTimerInterval: Int {
        didSet { defaults.set(selfTimerInterval, forKey: Keys.selfTimerInterval) }
    }
    var ocrKeepLineBreaks: Bool {
        didSet { defaults.set(ocrKeepLineBreaks, forKey: Keys.ocrKeepLineBreaks) }
    }
    /// Thumbnails show the text of any QR code in the capture, read on this Mac.
    var showsCodes: Bool {
        didSet { defaults.set(showsCodes, forKey: Keys.showsCodes); cards.showsCodesChanged() }
    }
    var fileNameTemplate: String {
        didSet { defaults.set(fileNameTemplate, forKey: Keys.fileNameTemplate) }
    }
    /// Backdrop for window captures; nil = transparent with a shadow.
    var windowBackground: GradientPreset? {
        didSet { defaults.set(windowBackground?.rawValue ?? "none", forKey: Keys.windowBackground) }
    }
    var windowPadding: Double {
        didSet { defaults.set(windowPadding, forKey: Keys.windowPadding) }
    }
    /// Thumbnail width in points (Settings → Quick Access → size).
    var cardWidth: Double {
        didSet { defaults.set(cardWidth, forKey: Keys.cardWidth); cards.relayout() }
    }
    /// Thumbnails appear on the screen under the pointer rather than the capture's screen.
    var cardFollowsPointer: Bool {
        didSet { defaults.set(cardFollowsPointer, forKey: Keys.cardFollowsPointer) }
    }
    var annotateShadows: Bool {
        didSet { defaults.set(annotateShadows, forKey: Keys.annotateShadows) }
    }
    var annotateAlwaysOnTop: Bool {
        didSet { defaults.set(annotateAlwaysOnTop, forKey: Keys.annotateAlwaysOnTop); EditorWindowController.applyLevel() }
    }
    var pinRoundedCorners: Bool {
        didSet { defaults.set(pinRoundedCorners, forKey: Keys.pinRoundedCorners); pins.restyle() }
    }
    var pinShadow: Bool {
        didSet { defaults.set(pinShadow, forKey: Keys.pinShadow); pins.restyle() }
    }
    var pinBorder: Bool {
        didSet { defaults.set(pinBorder, forKey: Keys.pinBorder); pins.restyle() }
    }
    var recordFrameRate: Int {
        didSet { defaults.set(recordFrameRate, forKey: Keys.recordFrameRate) }
    }
    var recordShowsCursor: Bool {
        didSet { defaults.set(recordShowsCursor, forKey: Keys.recordShowsCursor) }
    }
    var recordScaleToOneX: Bool {
        didSet { defaults.set(recordScaleToOneX, forKey: Keys.recordScaleToOneX) }
    }
    var recordDimScreen: Bool {
        didSet { defaults.set(recordDimScreen, forKey: Keys.recordDimScreen) }
    }
    var recordCountdown: Bool {
        didSet { defaults.set(recordCountdown, forKey: Keys.recordCountdown) }
    }
    /// Recordings keep the Mac's own sound.
    var recordComputerAudio: Bool {
        didSet { defaults.set(recordComputerAudio, forKey: Keys.recordComputerAudio) }
    }
    /// Recordings keep the microphone (`microphoneID`, nil = the system's default).
    var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: Keys.recordMicrophone) }
    }
    var microphoneID: String? {
        didSet { defaults.set(microphoneID, forKey: Keys.microphoneID) }
    }
    /// Recordings show the camera in a bubble (`cameraID`, nil = the system's default).
    var recordCamera: Bool {
        didSet { defaults.set(recordCamera, forKey: Keys.recordCamera) }
    }
    var cameraID: String? {
        didSet { defaults.set(cameraID, forKey: Keys.cameraID) }
    }
    var cameraShape: BubbleShape {
        didSet { defaults.set(cameraShape.rawValue, forKey: Keys.cameraShape) }
    }
    var cameraWidth: Double {
        didSet { defaults.set(cameraWidth, forKey: Keys.cameraWidth) }
    }
    var cameraCorner: BubbleCorner {
        didSet { defaults.set(cameraCorner.rawValue, forKey: Keys.cameraCorner) }
    }
    /// A ring where you click, in recordings.
    var recordShowClicks: Bool {
        didSet { defaults.set(recordShowClicks, forKey: Keys.recordShowClicks) }
    }
    /// A caption of the keys you press, in recordings (needs Accessibility).
    var recordShowKeys: Bool {
        didSet { defaults.set(recordShowKeys, forKey: Keys.recordShowKeys) }
    }
    var keystrokeMode: KeystrokeMode {
        didSet { defaults.set(keystrokeMode.rawValue, forKey: Keys.keystrokeMode) }
    }
    var gifFrameRate: Int {
        didSet { defaults.set(gifFrameRate, forKey: Keys.gifFrameRate) }
    }
    var gifWidth: Int {
        didSet { defaults.set(gifWidth, forKey: Keys.gifWidth) }
    }

    var recordingOptions: RecordingOptions {
        RecordingOptions(frameRate: recordFrameRate, showsCursor: recordShowsCursor, scaleToOneX: recordScaleToOneX,
                         audio: RecordingAudio(computer: recordComputerAudio, microphone: recordMicrophone))
    }

    var gifOptions: GIFEncoder.Options {
        GIFEncoder.Options(frameRate: gifFrameRate, maxWidth: gifWidth)
    }

    // MARK: State

    /// Last area captured (for Capture Previous Area).
    private(set) var lastArea: RememberedArea? {
        didSet {
            if let lastArea, let data = try? JSONEncoder().encode(lastArea) { defaults.set(data, forKey: Keys.lastArea) }
        }
    }
    /// The most recently closed capture, kept as a temporary PNG (not in memory) so
    /// "Reopen Last Capture" can bring it back.
    private(set) var lastClosed: ClosedCapture?
    @ObservationIgnored private var rememberTask: Task<Void, Never>?
    private(set) var hasPermission = false
    /// How many cards and pins are open (for enabling menu items).
    var openCards = 0
    var openPins = 0
    private(set) var isCapturing = false
    /// The screen recording's state (menu bar icon and menu follow it).
    var recordingPhase: RecordingPhase = .idle
    var isRecording: Bool { recordingPhase != .idle }

    // MARK: Wiring

    @ObservationIgnored let capturer: ScreenCapturing
    @ObservationIgnored let pasteboard: PasteboardWriting
    @ObservationIgnored private(set) var cards: CardController!
    @ObservationIgnored private(set) var pins: PinController!
    @ObservationIgnored private(set) var recording: RecordingController!
    @ObservationIgnored private(set) var history: HistoryController!
    /// The app a capture in progress comes from (set when it starts; window picks refine it).
    @ObservationIgnored var pendingSource: SourceApp?
    @ObservationIgnored let textRecognizer: TextRecognizing = VisionTextRecognizer()
    @ObservationIgnored let codeReader: CodeReading = VisionCodeReader()
    @ObservationIgnored private let defaults = Preferences.store

    private enum Keys {
        static let afterCapture = "afterCapture"
        static let cardCorner = "cardCorner"
        static let autoClose = "autoClose"
        static let autoCloseAction = "autoCloseAction"
        static let closeAfterDragging = "closeAfterDragging"
        static let closeAfterCopyOrSave = "closeAfterCopyOrSave"
        static let chosenFolder = "saveFolder"
        static let format = "format"
        static let includeWindowShadow = "includeWindowShadow"
        static let hideDesktopIcons = "hideDesktopIcons"
        static let showMagnifier = "showMagnifier"
        static let playSound = "playSound"
        static let lastArea = "lastArea"
        static let selfTimerInterval = "selfTimerInterval"
        static let ocrKeepLineBreaks = "ocrKeepLineBreaks"
        static let showsCodes = "showsCodes"
        static let fileNameTemplate = "fileNameTemplate"
        static let windowBackground = "windowBackground"
        static let windowPadding = "windowPadding"
        static let cardWidth = "cardWidth"
        static let cardFollowsPointer = "cardFollowsPointer"
        static let annotateShadows = "annotateShadows"
        static let annotateAlwaysOnTop = "annotateAlwaysOnTop"
        static let pinRoundedCorners = "pinRoundedCorners"
        static let pinShadow = "pinShadow"
        static let pinBorder = "pinBorder"
        static let recordFrameRate = "recordFrameRate"
        static let recordShowsCursor = "recordShowsCursor"
        static let recordScaleToOneX = "recordScaleToOneX"
        static let recordDimScreen = "recordDimScreen"
        static let recordCountdown = "recordCountdown"
        static let recordComputerAudio = "recordComputerAudio"
        static let recordMicrophone = "recordMicrophone"
        static let microphoneID = "microphoneID"
        static let recordCamera = "recordCamera"
        static let cameraID = "cameraID"
        static let cameraShape = "cameraShape"
        static let cameraWidth = "cameraWidth"
        static let cameraCorner = "cameraCorner"
        static let recordShowClicks = "recordShowClicks"
        static let recordShowKeys = "recordShowKeys"
        static let keystrokeMode = "keystrokeMode"
        static let gifFrameRate = "gifFrameRate"
        static let gifWidth = "gifWidth"
    }

    private init(capturer: ScreenCapturing = ScreenCaptureKitCapturer(), pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.capturer = capturer
        self.pasteboard = pasteboard
        let d = Preferences.store
        afterCapture = (d.object(forKey: Keys.afterCapture) as? Int).map(AfterCapture.init(rawValue:)) ?? .default
        cardCorner = d.string(forKey: Keys.cardCorner).flatMap(CardCorner.init) ?? .left
        autoClose = (d.object(forKey: Keys.autoClose) as? Int).flatMap(AutoClose.init) ?? .never
        autoCloseAction = d.string(forKey: Keys.autoCloseAction).flatMap(AutoCloseAction.init) ?? .close
        closeAfterDragging = d.object(forKey: Keys.closeAfterDragging) as? Bool ?? true
        closeAfterCopyOrSave = d.object(forKey: Keys.closeAfterCopyOrSave) as? Bool ?? true
        chosenFolder = d.string(forKey: Keys.chosenFolder)
        format = d.string(forKey: Keys.format).flatMap { ImageFormat(rawValue: $0) } ?? .png
        includeWindowShadow = d.object(forKey: Keys.includeWindowShadow) as? Bool ?? true
        hideDesktopIcons = d.object(forKey: Keys.hideDesktopIcons) as? Bool ?? true
        showMagnifier = d.object(forKey: Keys.showMagnifier) as? Bool ?? true
        playSound = d.object(forKey: Keys.playSound) as? Bool ?? true
        lastArea = d.data(forKey: Keys.lastArea).flatMap { try? JSONDecoder().decode(RememberedArea.self, from: $0) }
        selfTimerInterval = (d.object(forKey: Keys.selfTimerInterval) as? Int) ?? SelfTimer.defaultInterval
        ocrKeepLineBreaks = d.object(forKey: Keys.ocrKeepLineBreaks) as? Bool ?? true
        showsCodes = d.object(forKey: Keys.showsCodes) as? Bool ?? true
        fileNameTemplate = d.string(forKey: Keys.fileNameTemplate) ?? FileNaming.defaultTemplate
        windowBackground = d.string(forKey: Keys.windowBackground).flatMap(GradientPreset.init)
        windowPadding = d.object(forKey: Keys.windowPadding) as? Double ?? 56
        cardWidth = d.object(forKey: Keys.cardWidth) as? Double ?? 220
        cardFollowsPointer = d.object(forKey: Keys.cardFollowsPointer) as? Bool ?? true
        annotateShadows = d.object(forKey: Keys.annotateShadows) as? Bool ?? true
        annotateAlwaysOnTop = d.object(forKey: Keys.annotateAlwaysOnTop) as? Bool ?? false
        pinRoundedCorners = d.object(forKey: Keys.pinRoundedCorners) as? Bool ?? true
        pinShadow = d.object(forKey: Keys.pinShadow) as? Bool ?? true
        pinBorder = d.object(forKey: Keys.pinBorder) as? Bool ?? true
        recordFrameRate = (d.object(forKey: Keys.recordFrameRate) as? Int) ?? 30
        recordShowsCursor = d.object(forKey: Keys.recordShowsCursor) as? Bool ?? true
        recordScaleToOneX = d.object(forKey: Keys.recordScaleToOneX) as? Bool ?? false
        recordDimScreen = d.object(forKey: Keys.recordDimScreen) as? Bool ?? true
        recordCountdown = d.object(forKey: Keys.recordCountdown) as? Bool ?? false
        recordComputerAudio = d.object(forKey: Keys.recordComputerAudio) as? Bool ?? false
        recordMicrophone = d.object(forKey: Keys.recordMicrophone) as? Bool ?? false
        microphoneID = d.string(forKey: Keys.microphoneID)
        recordCamera = d.object(forKey: Keys.recordCamera) as? Bool ?? false
        cameraID = d.string(forKey: Keys.cameraID)
        cameraShape = d.string(forKey: Keys.cameraShape).flatMap(BubbleShape.init) ?? .circle
        cameraWidth = d.object(forKey: Keys.cameraWidth) as? Double ?? BubbleGeometry.defaultWidth
        cameraCorner = d.string(forKey: Keys.cameraCorner).flatMap(BubbleCorner.init) ?? .bottomLeft
        recordShowClicks = d.object(forKey: Keys.recordShowClicks) as? Bool ?? false
        recordShowKeys = d.object(forKey: Keys.recordShowKeys) as? Bool ?? false
        keystrokeMode = d.string(forKey: Keys.keystrokeMode).flatMap(KeystrokeMode.init) ?? .shortcuts
        gifFrameRate = (d.object(forKey: Keys.gifFrameRate) as? Int) ?? 15
        gifWidth = (d.object(forKey: Keys.gifWidth) as? Int) ?? 800
        cards = CardController(model: self)
        pins = PinController(model: self)
        recording = RecordingController(model: self, recorder: StreamRecorder())
        history = HistoryController(model: self)
        refreshPermission()
    }

    func refreshPermission() {
        let granted = capturer.hasPermission
        if granted != hasPermission { hasPermission = granted }
    }

    // MARK: Save folder

    /// macOS's own screenshot folder, if the user set one (Screenshot app → Options).
    var systemScreenshotFolder: String? {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    }

    var saveFolder: URL {
        SaveLocation.resolve(override: Diagnostics.saveDirectory, chosen: chosenFolder,
                             systemScreenshotFolder: systemScreenshotFolder,
                             home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var saveFolderIsOverridden: Bool { Diagnostics.saveDirectory != nil }

    // MARK: Capturing

    func capture(_ mode: CaptureMode, started: TimeInterval = Diagnostics.now()) {
        refreshPermission()
        guard hasPermission else {
            Diagnostics.record("capture blocked reason=noPermission mode=\(mode.rawValue)")
            PermissionWindow.show()
            return
        }
        if mode == .recording, isRecording {
            // The record shortcut (or menu item) again stops the recording.
            recording.stop()
            return
        }
        if mode == .allInOne {
            AllInOneBar.toggle(model: self)
            return
        }
        AllInOneBar.close()
        if ScrollingCapture.current != nil {
            if mode == .scrolling { ScrollingCapture.current?.finish() }
            return
        }
        if let overlay = RegionOverlay.current {
            // The same shortcut again while selecting switches mode, like pressing Space.
            if mode == .window { overlay.setMode(.window) } else if mode == .area { overlay.setMode(.area) }
            return
        }
        guard !isCapturing else {
            // The previous capture is still wrapping up (e.g. Esc a moment ago): try again
            // shortly instead of dropping the request.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, Diagnostics.now() - started < 1.5 else { return }
                self.capture(mode, started: started)
            }
            return
        }
        isCapturing = true
        pendingSource = CaptureSource.current()
        Task {
            defer { isCapturing = false }
            switch mode {
            case .area, .window:
                await captureWithOverlay(mode == .window ? .window : .area, started: started)
            case .fullScreen:
                await captureFullScreen(started: started)
            case .previousArea:
                await capturePreviousArea(started: started)
            case .text:
                await captureText(started: started)
            case .selfTimer:
                await captureWithTimer(started: started)
            case .scrolling:
                await captureScrolling(started: started)
            case .recording:
                await recording.begin(started: started)
            case .allInOne:
                break
            }
        }
    }

    var overlayOptions: RegionOverlay.Options {
        .init(showsMagnifier: showMagnifier, exclusions: exclusions, log: Diagnostics.record)
    }

    var exclusions: CaptureExclusions {
        CaptureExclusions(keepOwnWindows: pins.windowNumbers.union(TestScene.windowNumbers), hideDesktopIcons: hideDesktopIcons,
                          onlyWindows: TestScene.isActive ? pins.windowNumbers.union(TestScene.windowNumbers) : nil)
    }

    private func captureWithOverlay(_ mode: RegionOverlay.Mode, started: TimeInterval) async {
        let overlay = RegionOverlay(capturer: capturer, mode: mode, options: .init(
            showsMagnifier: showMagnifier, exclusions: exclusions, log: Diagnostics.record))
        let result = await overlay.run(started: started)
        let finished = overlay.finishedAt ?? Diagnostics.now()
        switch result {
        case .area(let displayID, let rect, let image):
            lastArea = RememberedArea(displayID: displayID, rect: rect)
            deliver(image, scale: scaleOf(displayID), displayID: displayID, started: finished, kind: "area")
        case .window(let window):
            await captureWindow(window, started: finished)
        case .cancelled:
            Diagnostics.record("capture cancelled")
            Memory.relieveSoon()
        case .failed(let error):
            report(error)
        }
    }

    /// One window on its own: shadow on transparency, or the window background preset.
    func captureWindow(_ window: WindowInfo, started finished: TimeInterval) async {
        pendingSource = CaptureSource.window(window)
        if let only = exclusions.onlyWindows, !only.contains(window.id) {
            Diagnostics.record("window capture refused: test mode allows only the test scene")
            return
        }
        do {
            let screen = screenContaining(quartzRect: window.frame)
            let bare = try await capturer.captureWindow(window.id, includeShadow: false)
            let scale = CGFloat(bare.width) / max(window.frame.width, 1)
            let itemScale = scale > 0.5 ? scale.rounded() : (screen?.backingScaleFactor ?? 2)
            if let preset = windowBackground {
                // A backdrop instead of transparency: editable later with the Background tool.
                let background = CaptureBackground(fill: .gradient(preset), padding: windowPadding, cornerRadius: 0,
                                                   shadow: includeWindowShadow ? 0.6 : 0)
                deliver(bare, scale: itemScale, displayID: screen?.displayID, started: finished, kind: "window", background: background)
            } else {
                let image = includeWindowShadow ? (WindowShadow.apply(to: bare, scale: scale) ?? bare) : bare
                deliver(image, scale: itemScale, displayID: screen?.displayID, started: finished, kind: "window")
            }
        } catch {
            report(error)
        }
    }

    private func captureFullScreen(started: TimeInterval) async {
        guard let screen = NSScreen.underPointer else { return }
        do {
            let images = try await capturer.snapshot(displays: [screen.displayID], excluding: exclusions)
            guard let image = images[screen.displayID] else { throw CaptureError.displayNotFound }
            deliver(image, scale: screen.backingScaleFactor, displayID: screen.displayID, started: started, kind: "fullScreen")
        } catch {
            report(error)
        }
    }

    private func capturePreviousArea(started: TimeInterval) async {
        guard let area = lastArea, let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID }),
              let rect = area.rect(within: CGRect(origin: .zero, size: screen.frame.size)) else {
            Diagnostics.record("previous area missing; starting area capture")
            await captureWithOverlay(.area, started: started)
            return
        }
        do {
            let images = try await capturer.snapshot(displays: [screen.displayID], excluding: exclusions)
            guard let full = images[screen.displayID] else { throw CaptureError.displayNotFound }
            let scale = CGFloat(full.width) / screen.frame.width
            let pixels = ScreenCoordinates.pixelRect(local: rect, screenSize: screen.frame.size, scale: scale)
            guard let image = full.cropping(to: pixels) else { throw CaptureError.displayNotFound }
            deliver(image, scale: scale, displayID: screen.displayID, started: started, kind: "previousArea")
        } catch {
            report(error)
        }
    }

    private func scaleOf(_ displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
    }

    private func screenContaining(quartzRect: CGRect) -> NSScreen? {
        let appKit = ScreenCoordinates.flip(quartzRect, primaryHeight: NSScreen.primaryHeight)
        let center = CGPoint(x: appKit.midX, y: appKit.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main
    }

    func report(_ error: Error) {
        Diagnostics.record("capture failed error=\(error)")
        if case CaptureError.noPermission = error {
            PermissionWindow.show()
            return
        }
        refreshPermission()
        if !hasPermission {
            PermissionWindow.show()
        } else {
            HUD.show("Couldn't capture the screen. Try again.", systemImage: "exclamationmark.triangle")
        }
    }

    /// Hands a fresh capture to the after-capture actions.
    func deliver(_ image: CGImage, scale: CGFloat, displayID: CGDirectDisplayID?, started: TimeInterval, kind: String,
                 background: CaptureBackground? = nil, media: MediaFile? = nil) {
        if playSound, media == nil { Output.playShutter() }
        let item = CaptureItem(image: image, scale: scale, displayID: displayID)
        item.media = media
        if let background {
            let renderer = AnnotationRenderer(base: image, scale: scale)
            let document = AnnotationDocument(imageSize: renderer.imageSize, background: background)
            if let rendered = renderer.render(document) { item.apply(document, rendered: rendered) }
        }
        item.sourceName = item.fileBaseName
        if afterCapture.contains(.showCard) {
            cards.add(item)
            Diagnostics.record("card shown kind=\(kind) ms=\(Diagnostics.milliseconds(since: started)) pixels=\(item.pixelSizeDescription)")
        } else {
            Diagnostics.record("captured kind=\(kind) ms=\(Diagnostics.milliseconds(since: started)) pixels=\(item.pixelSizeDescription)")
        }
        // History keeps a persistent file for drags; without it, a temporary one.
        if history.isOn {
            history.record(item, kind: HistoryKind(captureKind: kind), source: pendingSource ?? CaptureSource.current())
        } else {
            item.prepareTemporaryFile(format: format)
        }
        pendingSource = nil
        Memory.relieveSoon()
        if afterCapture.contains(.copy) {
            copy(item, closeCard: false)
        }
        if afterCapture.contains(.save) {
            save(item, closeCard: false)
        }
        if !afterCapture.contains(.showCard) {
            remember(item)
        }
    }

    // MARK: Actions on a capture

    func copy(_ item: CaptureItem, closeCard: Bool = true) {
        if let media = item.media {
            pasteboard.write(file: media.url)
        } else {
            pasteboard.write(item.image, size: item.size)
        }
        HUD.show("Copied", systemImage: "doc.on.doc")
        Diagnostics.record("copied pixels=\(item.pixelSizeDescription)")
        if closeCard, closeAfterCopyOrSave { cards.close(item) }
    }

    func save(_ item: CaptureItem, closeCard: Bool = true) {
        let folder = saveFolder
        Task {
            do {
                let previous = item.savedURL ?? item.lastSavedURL
                let url: URL
                if let media = item.media {
                    if let previous, FileManager.default.fileExists(atPath: previous.path) {
                        url = previous
                    } else {
                        url = try await Output.saveFile(media.url, to: folder, baseName: item.fileBaseName)
                    }
                } else {
                    url = try await Output.save(item.image, format: format, to: folder, date: item.createdAt,
                                                baseName: item.fileBaseName, replacing: previous)
                }
                let again = url == previous
                item.savedURL = url
                item.lastSavedURL = url
                history.saved(item, to: url)
                HUD.show(again ? "Updated “\(url.lastPathComponent)” in \(folder.lastPathComponent)"
                                 : "Saved “\(url.lastPathComponent)” to \(folder.lastPathComponent)",
                         systemImage: "square.and.arrow.down", duration: .seconds(2.5))
                Diagnostics.record("saved file=\(url.lastPathComponent)")
                if closeCard, closeAfterCopyOrSave { cards.close(item) }
            } catch {
                HUD.show(error.localizedDescription, systemImage: "exclamationmark.triangle", duration: .seconds(4))
            }
        }
    }

    func saveAs(_ item: CaptureItem) {
        Task {
            let url: URL?
            if let media = item.media {
                url = await Output.saveFileAs(media.url, suggestedName: item.fileBaseName, folder: saveFolder)
            } else {
                url = await Output.saveAs(item.image, suggestedName: item.fileBaseName, format: format, folder: saveFolder)
            }
            if let url {
                item.savedURL = url
                history.saved(item, to: url)
                HUD.show("Saved \(url.lastPathComponent)", systemImage: "square.and.arrow.down")
                cards.close(item)
            }
        }
    }

    func annotate(_ item: CaptureItem) {
        guard !item.isMedia else { openTrimmer(item); return }
        cards.close(item, remember: false)
        EditorWindowController.open(item, model: self)
    }

    func pin(_ item: CaptureItem) {
        guard !item.isMedia else { return }
        cards.close(item, remember: false)
        pins.pin(item)
    }

    /// Opens a recording in the default player.
    func openMedia(_ item: CaptureItem) {
        guard let media = item.media else { return }
        NSWorkspace.shared.open(media.url)
    }

    /// Makes an animated GIF from a video recording; it gets its own thumbnail.
    func exportGIF(_ item: CaptureItem) {
        guard let media = item.media, !media.isGIF else { return }
        HUD.show("Making GIF…", systemImage: "hourglass")
        Task {
            do {
                let gif = try await VideoFrames.makeGIF(from: media.url, options: gifOptions)
                let copy = CaptureItem(image: item.image, scale: item.scale, displayID: item.displayID, createdAt: item.createdAt)
                copy.media = MediaFile(url: gif, duration: media.duration)
                copy.sourceName = copy.fileBaseName
                cards.add(copy)
                history.record(copy, kind: .gif, source: history.entry(item.historyID)?.source)
                Diagnostics.record("exported gif")
            } catch {
                HUD.show("Couldn't make a GIF", systemImage: "exclamationmark.triangle")
            }
        }
    }

    /// Opens a video in the trim window.
    func openTrimmer(_ item: CaptureItem) {
        guard let media = item.media, !media.isGIF else { return }
        TrimWindowController.show(item, model: self)
    }

    /// Keeps only `range` of a video (no re-encoding). The thumbnail stays where it is and
    /// shows the shorter video; history gets it too. The untrimmed recording is kept so
    /// `restoreUntrimmed` can undo it.
    func trim(_ item: CaptureItem, to range: TrimRange) {
        guard let media = item.media, !media.isGIF, !range.isWhole(of: media.duration) else { return }
        let started = Diagnostics.now()
        Task {
            let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let output = folder.appendingPathComponent(media.url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await MediaEditor.trim(media.url, to: range, output: output)
                let duration = await MediaEditor.duration(of: output)
                guard let poster = await VideoFrames.poster(of: output) else { throw RecordingError.noFrames }
                if item.untrimmed == nil, item.historyID == nil { item.untrimmed = media }
                try await replaceMedia(of: item, with: MediaFile(url: output, duration: duration), poster: poster)
                Diagnostics.record("trimmed seconds=\(String(format: "%.1f", duration)) from=\(String(format: "%.1f", media.duration)) ms=\(Diagnostics.milliseconds(since: started))")
                HUD.show("Trimmed to \(Elapsed.string(duration))", systemImage: "scissors")
            } catch {
                try? FileManager.default.removeItem(at: folder)
                Diagnostics.record("trim failed error=\(error)")
                HUD.show("Couldn't trim the recording", systemImage: "exclamationmark.triangle")
            }
        }
    }

    /// Whether a video was trimmed and can go back to the whole recording.
    func canRestoreUntrimmed(_ item: CaptureItem) -> Bool {
        if item.untrimmed != nil { return true }
        guard let entry = history.entry(item.historyID) else { return false }
        return history.store.untrimmedURL(for: entry) != nil
    }

    /// Undoes trims: the whole recording again.
    func restoreUntrimmed(_ item: CaptureItem) {
        Task {
            do {
                if let entry = history.entry(item.historyID), let url = history.store.untrimmedURL(for: entry) {
                    let duration = await MediaEditor.duration(of: url)
                    guard let poster = await VideoFrames.poster(of: url) else { throw RecordingError.noFrames }
                    guard let updated = try await history.restoreUntrimmed(item, duration: duration, poster: poster) else { return }
                    item.replaceMedia(MediaFile(url: history.store.fileURL(for: updated), duration: duration), poster: poster)
                } else if let original = item.untrimmed {
                    guard let poster = await VideoFrames.poster(of: original.url) else { throw RecordingError.noFrames }
                    item.untrimmed = nil
                    item.replaceMedia(original, poster: poster)
                } else {
                    return
                }
                cards.refresh(item)
                Diagnostics.record("trim restored")
                HUD.show("Restored the whole recording", systemImage: "arrow.uturn.backward")
            } catch {
                HUD.show("Couldn't restore the recording", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func replaceMedia(of item: CaptureItem, with media: MediaFile, poster: CGImage) async throws {
        if item.historyID != nil, let updated = try await history.replaceMedia(item, with: media, poster: poster) {
            try? FileManager.default.removeItem(at: media.url.deletingLastPathComponent())
            item.replaceMedia(MediaFile(url: history.store.fileURL(for: updated), duration: media.duration), poster: poster)
        } else {
            item.replaceMedia(media, poster: poster)
        }
        cards.refresh(item)
    }

    func showInFinder(_ item: CaptureItem) {
        guard let url = item.savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Keeps a closed capture so "Reopen Last Capture" can bring it back. The pixels go to a
    /// temporary file in the background so idle memory drops back to baseline.
    func remember(_ item: CaptureItem) {
        if item.historyID != nil {
            // History has it on disk already: nothing to park.
            history.closed(item)
            return
        }
        if let media = item.media {
            rememberTask?.cancel()
            if let old = lastClosed, old.url != item.temporaryFile(format: format) { try? FileManager.default.removeItem(at: old.url) }
            // A recording's poster is parked in memory-light form: just the file.
            lastClosed = ClosedCapture(url: media.url, scale: item.scale, displayID: item.displayID, createdAt: item.createdAt, media: media)
            return
        }
        let image = item.image, scale = item.scale, displayID = item.displayID, date = item.createdAt
        if !cards.contains(item), !pins.contains(item), !EditorWindowController.isEditing(item) {
            item.discardTemporaryFile()
        }
        rememberTask?.cancel()
        rememberTask = Task {
            let url = await Task.detached(priority: .utility) { ClosedCapture.write(image) }.value
            guard !Task.isCancelled, let url else { return }
            if let old = lastClosed { try? FileManager.default.removeItem(at: old.url) }
            lastClosed = ClosedCapture(url: url, scale: scale, displayID: displayID, createdAt: date)
            Memory.relieveSoon()
        }
    }

    /// Whether "Reopen Last Capture" has something to bring back. (Reads the open card and
    /// pin counts so menus showing it update when those change.)
    var canReopen: Bool {
        _ = (openCards, openPins)
        return history.isOn ? history.reopenCandidate != nil : lastClosed != nil
    }

    /// Edited images on screen that exist nowhere else: not in History, never saved or
    /// copied out (an opened file's edits, or any edits with History off).
    var unsavedEdits: [CaptureItem] {
        var seen = Set<UUID>()
        return (cards.items + pins.items + EditorWindowController.openItems).filter { item in
            guard seen.insert(item.id).inserted else { return false }
            return !item.isMedia && item.document != nil && item.historyID == nil && item.savedURL == nil
        }
    }

    /// History ids of every capture on screen (cards, editors, pins): never pruned or deleted.
    var openHistoryIDs: Set<UUID> {
        Set((cards.items + pins.items + EditorWindowController.openItems).compactMap(\.historyID))
    }

    func openItem(historyID: UUID) -> CaptureItem? {
        (cards.items + pins.items + EditorWindowController.openItems).first { $0.historyID == historyID }
    }

    func reopenLastCapture() {
        if history.isOn {
            guard let entry = history.reopenCandidate else { return }
            restore(entry)
            return
        }
        guard let closed = lastClosed else { return }
        if let media = closed.media {
            lastClosed = nil
            Task {
                guard let poster = await VideoFrames.poster(of: media.url) else { return }
                let item = CaptureItem(image: poster, scale: closed.scale, displayID: closed.displayID, createdAt: closed.createdAt)
                item.media = media
                cards.add(item)
            }
            return
        }
        guard let image = closed.load() else { return }
        lastClosed = nil
        try? FileManager.default.removeItem(at: closed.url)
        cards.add(CaptureItem(image: image, scale: closed.scale, displayID: closed.displayID, createdAt: closed.createdAt))
    }

    // MARK: History

    /// Brings a history entry back as a thumbnail card (or to the front, if it's open).
    func restore(_ entry: HistoryEntry) {
        Task {
            if let open = openItem(historyID: entry.id) {
                if !cards.contains(open), !pins.contains(open), !EditorWindowController.isEditing(open) { cards.add(open) }
                return
            }
            guard let item = await history.capture(for: entry) else {
                HUD.show("Couldn't open that capture", systemImage: "exclamationmark.triangle")
                return
            }
            cards.add(item)
            Diagnostics.record("history restored kind=\(entry.kind.rawValue) edited=\(item.document != nil)")
        }
    }

    /// Runs `action` on a history entry as a capture (Annotate, Pin, Copy…).
    func withCapture(_ entry: HistoryEntry, _ action: @escaping (CaptureItem) -> Void) {
        Task {
            guard let item = await history.capture(for: entry) else {
                HUD.show("Couldn't open that capture", systemImage: "exclamationmark.triangle")
                return
            }
            action(item)
        }
    }

    // MARK: Text (OCR)

    /// Picks an area (or window) and copies the text in it.
    private func captureText(started: TimeInterval) async {
        guard let region = await PickedRegion.pick(.area, capturer: capturer, options: overlayOptions, started: started, report: report) else { return }
        let image: CGImage
        if let frozen = region.frozen {
            image = frozen
        } else if let window = region.window {
            if let only = exclusions.onlyWindows, !only.contains(window.id) {
                Diagnostics.record("window capture refused: test mode allows only the test scene")
                return
            }
            guard let captured = try? await capturer.captureWindow(window.id, includeShadow: false) else { return }
            image = captured
        } else {
            return
        }
        await recognizeAndCopy(image)
    }

    /// Reads the text in `image` and copies it.
    func recognizeAndCopy(_ image: CGImage) async {
        let started = Diagnostics.now()
        do {
            let text = try await textRecognizer.recognize(image, keepLineBreaks: ocrKeepLineBreaks)
            Diagnostics.record("text recognized characters=\(text.count) ms=\(Diagnostics.milliseconds(since: started))")
            guard !text.isEmpty else {
                HUD.show("No text found", systemImage: "text.viewfinder")
                return
            }
            pasteboard.write(text: text)
            HUD.show("Copied text: \(TextLayout.preview(text))", systemImage: "text.viewfinder", duration: .seconds(2.5))
        } catch {
            HUD.show("Couldn't read text from the capture", systemImage: "exclamationmark.triangle")
        }
    }

    func copyText(_ item: CaptureItem) {
        let image = item.image
        Task { await recognizeAndCopy(image) }
    }

    // MARK: QR codes

    func copyCode(_ code: ScannedCode) {
        pasteboard.write(text: code.payload)
        HUD.show("Copied: \(TextLayout.preview(code.displayText))", systemImage: "qrcode", duration: .seconds(2.5))
        Diagnostics.record("code copied characters=\(code.payload.count)")
    }

    /// Opens a code's web link in the default browser. Only http(s) links get here
    /// (`ScannedCode.link`); anything else is copy-only.
    func openCode(_ code: ScannedCode) {
        guard let url = code.link else { return }
        if Diagnostics.testScene != nil {
            // Test runs never open a browser.
            Diagnostics.record("code open refused in test mode host=\(url.host ?? "")")
            return
        }
        NSWorkspace.shared.open(url)
        Diagnostics.record("code opened")
    }

    // MARK: Self-timer

    /// Picks an area (Return: whole screen), counts down, then captures it fresh.
    private func captureWithTimer(started: TimeInterval) async {
        guard let region = await PickedRegion.pick(.area, capturer: capturer, options: overlayOptions, started: started, report: report) else { return }
        let frame = RegionFrame(rect: region.global, dimOutside: false)
        let go = await Countdown.run(selfTimerInterval, centeredIn: region.global, label: "Capturing")
        frame.close()
        guard go else { Diagnostics.record("self-timer cancelled"); return }
        let fired = Diagnostics.now()
        if let window = region.window {
            if let only = exclusions.onlyWindows, !only.contains(window.id) { return }
            do {
                let bare = try await capturer.captureWindow(window.id, includeShadow: false)
                let scale = CGFloat(bare.width) / max(window.frame.width, 1)
                let image = includeWindowShadow ? (WindowShadow.apply(to: bare, scale: scale) ?? bare) : bare
                deliver(image, scale: scale.rounded(), displayID: region.displayID, started: fired, kind: "selfTimerWindow")
            } catch {
                report(error)
            }
            return
        }
        do {
            let images = try await capturer.snapshot(displays: [region.displayID], excluding: exclusions)
            guard let full = images[region.displayID] else { throw CaptureError.displayNotFound }
            let scale = CGFloat(full.width) / region.screen.frame.width
            let pixels = ScreenCoordinates.pixelRect(local: region.local, screenSize: region.screen.frame.size, scale: scale)
            guard let image = full.cropping(to: pixels) else { throw CaptureError.displayNotFound }
            lastArea = RememberedArea(displayID: region.displayID, rect: region.local)
            deliver(image, scale: scale, displayID: region.displayID, started: fired, kind: "selfTimer")
        } catch {
            report(error)
        }
    }

    // MARK: Scrolling capture

    private func captureScrolling(started: TimeInterval) async {
        guard let region = await PickedRegion.pick(.area, capturer: capturer, options: overlayOptions, started: started, report: report) else { return }
        await captureScrolling(region)
    }

    func captureScrolling(_ region: PickedRegion) async {
        let session = ScrollingCapture(model: self, region: region)
        guard let image = await session.run() else { return }
        deliver(image, scale: CGFloat(image.width) / max(region.local.width, 1), displayID: region.displayID,
                started: Diagnostics.now(), kind: "scrolling")
    }

    // MARK: Images from elsewhere

    /// The image on the clipboard, if any (read only when the user asks for it).
    func clipboardImage() -> CaptureItem? {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else { return nil }
        let item = Self.item(from: image)
        item?.sourceName = "Clipboard Image"
        return item
    }

    static func item(from image: NSImage) -> CaptureItem? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = image.size.width > 0 ? CGFloat(cg.width) / image.size.width : 1
        return CaptureItem(image: cg, scale: max(1, scale.rounded()), displayID: nil)
    }

    func annotateClipboard() {
        guard let item = clipboardImage() else {
            HUD.show("There's no image on the clipboard", systemImage: "photo")
            return
        }
        EditorWindowController.open(item, model: self)
    }

    func pinClipboard() {
        guard let item = clipboardImage() else {
            HUD.show("There's no image on the clipboard", systemImage: "photo")
            return
        }
        pins.pin(item)
    }

    /// "Open Image…": choose a picture file to annotate or pin.
    func chooseImage(then action: @escaping (CaptureItem) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url), let item = Self.item(from: image) else {
            // A damaged file, or one only named like an image: say so instead of doing nothing.
            HUD.show("Not a readable image: \(url.lastPathComponent)", systemImage: "exclamationmark.triangle", duration: .seconds(2.5))
            Diagnostics.record("image file unreadable")
            return
        }
        item.sourceName = url.deletingPathExtension().lastPathComponent
        action(item)
    }
}
