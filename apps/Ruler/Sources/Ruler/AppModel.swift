import AppKit
import Observation
import RulerCore
import SlopKit

/// Writes to the clipboard. Behind a protocol so it can be faked.
@MainActor
protocol PasteboardWriting {
    func write(_ text: String)
    func write(image: CGImage, pointSize: CGSize)
}

/// The general pasteboard, or a private named one in tests (`RULER_PASTEBOARD`), so scripted
/// runs never touch the user's clipboard.
struct SystemPasteboardWriter: PasteboardWriting {
    private var pasteboard: NSPasteboard {
        Diagnostics.pasteboardName.map { NSPasteboard(name: .init($0)) } ?? .general
    }

    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func write(image: CGImage, pointSize: CGSize) {
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: pointSize)])
    }
}

/// The color of lines and outlines on the overlay.
enum LineColor: String, CaseIterable, Identifiable {
    case accent, red, pink, orange, yellow, green, teal, blue, purple

    var id: String { rawValue }
    var title: String { self == .accent ? "Accent Color" : rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .red: .systemRed
        case .pink: .systemPink
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .purple: .systemPurple
        }
    }
}

/// App state and the actions the menu, the hotkey and the overlay share.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum State { case idle, measuring, background }

    // MARK: Settings (UserDefaults)

    var unit: MeasureUnit { didSet { save(unit.rawValue, Keys.unit) } }
    var copyFormat: CopyFormat { didSet { defaults.set(copyFormat.rawValue, forKey: Keys.copyFormat) } }
    /// Remembered between sessions; changed in the overlay with = − and T.
    var tolerance: Tolerance { didSet { save(tolerance.rawValue, Keys.tolerance) } }
    var showMagnifier: Bool { didSet { save(showMagnifier, Keys.showMagnifier) } }
    /// Divides readouts, for @2x/@3x designs or zoomed design tools.
    var designScale: Double { didSet { save(designScale, Keys.designScale) } }
    var lineColor: LineColor { didSet { save(lineColor.rawValue, Keys.lineColor) } }
    var showUnits: Bool { didSet { save(showUnits, Keys.showUnits) } }
    var ratioOnAreas: Bool { didSet { save(ratioOnAreas, Keys.ratioOnAreas) } }
    var ratioOnDistances: Bool { didSet { save(ratioOnDistances, Keys.ratioOnDistances) } }
    var ratioStyle: AspectRatioStyle { didSet { save(ratioStyle.rawValue, Keys.ratioStyle) } }
    var showHints: Bool { didSet { save(showHints, Keys.showHints) } }
    var screenshotFormat: ScreenshotFormat { didSet { defaults.set(screenshotFormat.rawValue, forKey: Keys.screenshotFormat) } }
    /// Space around the measured area in screenshots, in points.
    var screenshotPadding: Double { didSet { defaults.set(screenshotPadding, forKey: Keys.screenshotPadding) } }
    var screenshotAt1x: Bool { didSet { defaults.set(screenshotAt1x, forKey: Keys.screenshotAt1x) } }
    /// Nil: the Desktop.
    var screenshotFolderPath: String? { didSet { defaults.set(screenshotFolderPath, forKey: Keys.screenshotFolder) } }

    // MARK: State

    private(set) var hasPermission = false
    private(set) var state: State = .idle
    var isMeasuring: Bool { state != .idle }
    private(set) var hasSavedSession = false

    @ObservationIgnored let capturer: ScreenCapturing
    @ObservationIgnored let pasteboard: PasteboardWriting
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let unit = "unit"
        static let copyFormat = "copyFormat"
        static let tolerance = "tolerance"
        static let showMagnifier = "showMagnifier"
        static let designScale = "designScale"
        static let lineColor = "lineColor"
        static let showUnits = "showUnits"
        static let ratioOnAreas = "ratioOnAreas"
        static let ratioOnDistances = "ratioOnDistances"
        static let ratioStyle = "ratioStyle"
        static let showHints = "showHints"
        static let screenshotFormat = "screenshotFormat"
        static let screenshotPadding = "screenshotPadding"
        static let screenshotAt1x = "screenshotAt1x"
        static let screenshotFolder = "screenshotFolder"
        static let lastSession = "lastSession"
    }

    private init(capturer: ScreenCapturing = Diagnostics.fakeCapture ? SceneRenderCapturer() : ScreenCaptureKitCapturer(),
                 pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.capturer = capturer
        self.pasteboard = pasteboard
        let d = UserDefaults.standard
        unit = d.string(forKey: Keys.unit).flatMap(MeasureUnit.init(rawValue:)) ?? .points
        copyFormat = d.string(forKey: Keys.copyFormat).flatMap(CopyFormat.init(rawValue:)) ?? .plain
        tolerance = (d.object(forKey: Keys.tolerance) as? Int).flatMap(Tolerance.init(rawValue:)) ?? .default
        showMagnifier = d.object(forKey: Keys.showMagnifier) as? Bool ?? false
        designScale = DesignScale.clamped(d.object(forKey: Keys.designScale) as? Double ?? 1)
        lineColor = d.string(forKey: Keys.lineColor).flatMap(LineColor.init(rawValue:)) ?? .accent
        showUnits = d.object(forKey: Keys.showUnits) as? Bool ?? true
        ratioOnAreas = d.object(forKey: Keys.ratioOnAreas) as? Bool ?? false
        ratioOnDistances = d.object(forKey: Keys.ratioOnDistances) as? Bool ?? false
        ratioStyle = d.string(forKey: Keys.ratioStyle).flatMap(AspectRatioStyle.init(rawValue:)) ?? .automatic
        showHints = d.object(forKey: Keys.showHints) as? Bool ?? true
        screenshotFormat = d.string(forKey: Keys.screenshotFormat).flatMap(ScreenshotFormat.init(rawValue:)) ?? .png
        screenshotPadding = d.object(forKey: Keys.screenshotPadding) as? Double ?? 24
        screenshotAt1x = d.object(forKey: Keys.screenshotAt1x) as? Bool ?? false
        screenshotFolderPath = d.string(forKey: Keys.screenshotFolder)
        hasSavedSession = SavedSession.decode(d.data(forKey: Keys.lastSession)) != nil
        refreshPermission()
    }

    /// Saves a setting and redraws the overlay, if one is up.
    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        MeasureOverlay.current?.settingsChanged()
    }

    func refreshPermission() {
        let granted = capturer.hasPermission
        if granted != hasPermission { hasPermission = granted }
    }

    // MARK: Measuring

    /// The shortcut and the Measure item. Starts measuring; while measuring, keeps the
    /// measurements on screen and steps back (or closes, if there's nothing to keep);
    /// in the background, picks the session back up.
    func toggleMeasuring(started: TimeInterval = Diagnostics.now()) {
        if let overlay = MeasureOverlay.current {
            switch overlay.phase {
            case .active: overlay.hasMeasurements ? overlay.enterBackground(returnFocus: true) : overlay.close()
            case .background: overlay.resume(started: started)
            }
            return
        }
        startMeasuring(started: started, boards: nil)
    }

    /// Opens the overlay, optionally with saved boards per display.
    private func startMeasuring(started: TimeInterval, boards: SavedSession?) {
        refreshPermission()
        guard hasPermission else {
            Diagnostics.record("measure blocked reason=noPermission")
            PermissionWindow.show()
            return
        }
        let overlay = MeasureOverlay(model: self, capturer: capturer, exclusions: exclusions)
        state = .measuring
        overlay.onClose = { [weak self] error in
            self?.state = .idle
            if let error { self?.report(error) }
        }
        overlay.show(started: started, restoring: boards)
    }

    func overlayPhaseChanged(_ phase: MeasureOverlay.Phase) {
        state = phase == .active ? .measuring : .background
    }

    /// Ends the session (menu bar "Clear Measurements" while they're kept on screen).
    func stopMeasuring() {
        MeasureOverlay.current?.close()
    }

    /// In test mode the freeze contains only the test scene; otherwise everything except
    /// Ruler's own windows.
    var exclusions: CaptureExclusions {
        TestScene.isActive ? CaptureExclusions(onlyWindows: TestScene.windowNumbers) : CaptureExclusions()
    }

    private func report(_ error: Error) {
        Diagnostics.record("measure failed error=\(error)")
        refreshPermission()
        if !hasPermission {
            PermissionWindow.show()
        } else {
            HUD.show("Couldn't read the screen. Try again.", systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: Last session

    func saveSession(_ session: SavedSession) {
        guard !session.isEmpty, let data = session.encoded() else { return }
        defaults.set(data, forKey: Keys.lastSession)
        hasSavedSession = true
    }

    var savedSession: SavedSession? { SavedSession.decode(defaults.data(forKey: Keys.lastSession)) }

    /// Brings back the last closed session's measurements (into the open session, or a new one).
    func restoreLastSession() {
        guard let session = savedSession else {
            NSSound.beep()
            return
        }
        if let overlay = MeasureOverlay.current {
            if overlay.phase == .background { overlay.resume(started: Diagnostics.now()) }
            overlay.restore(session)
        } else {
            startMeasuring(started: Diagnostics.now(), boards: session)
        }
    }

    // MARK: Output

    func copy(_ text: String) {
        pasteboard.write(text)
    }

    var screenshotFolder: URL {
        if let dir = Diagnostics.screenshotDirectory { return URL(fileURLWithPath: dir, isDirectory: true) }
        if let path = screenshotFolderPath { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    var readoutRatioStyle: (areas: AspectRatioStyle?, distances: AspectRatioStyle?) {
        (ratioOnAreas ? ratioStyle : nil, ratioOnDistances ? ratioStyle : nil)
    }
}
