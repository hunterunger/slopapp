import AppKit
import Observation
import RulerCore
import SlopKit

/// Writes text to the clipboard. Behind a protocol so it can be faked.
@MainActor
protocol PasteboardWriting {
    func write(_ text: String)
}

struct SystemPasteboardWriter: PasteboardWriting {
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// App state and the actions the menu, the hotkey and the overlay share.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Settings (UserDefaults)

    var unit: MeasureUnit {
        didSet { defaults.set(unit.rawValue, forKey: Keys.unit); MeasureOverlay.current?.settingsChanged() }
    }
    var copyFormat: CopyFormat {
        didSet { defaults.set(copyFormat.rawValue, forKey: Keys.copyFormat) }
    }
    /// Remembered between sessions; changed in the overlay with = and −.
    var tolerance: Tolerance {
        didSet { defaults.set(tolerance.rawValue, forKey: Keys.tolerance); MeasureOverlay.current?.settingsChanged() }
    }
    var showMagnifier: Bool {
        didSet { defaults.set(showMagnifier, forKey: Keys.showMagnifier); MeasureOverlay.current?.settingsChanged() }
    }

    // MARK: State

    private(set) var hasPermission = false
    private(set) var isMeasuring = false

    @ObservationIgnored let capturer: ScreenCapturing
    @ObservationIgnored let pasteboard: PasteboardWriting
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let unit = "unit"
        static let copyFormat = "copyFormat"
        static let tolerance = "tolerance"
        static let showMagnifier = "showMagnifier"
    }

    private init(capturer: ScreenCapturing = ScreenCaptureKitCapturer(), pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.capturer = capturer
        self.pasteboard = pasteboard
        let d = UserDefaults.standard
        unit = d.string(forKey: Keys.unit).flatMap(MeasureUnit.init(rawValue:)) ?? .points
        copyFormat = d.string(forKey: Keys.copyFormat).flatMap(CopyFormat.init(rawValue:)) ?? .plain
        tolerance = (d.object(forKey: Keys.tolerance) as? Int).flatMap(Tolerance.init(rawValue:)) ?? .default
        showMagnifier = d.object(forKey: Keys.showMagnifier) as? Bool ?? false
        refreshPermission()
    }

    func refreshPermission() {
        let granted = capturer.hasPermission
        if granted != hasPermission { hasPermission = granted }
    }

    /// The shortcut and the Measure item: open the overlay, or close it if it's up.
    func toggleMeasuring(started: TimeInterval = Diagnostics.now()) {
        if let overlay = MeasureOverlay.current {
            overlay.close()
            return
        }
        refreshPermission()
        guard hasPermission else {
            Diagnostics.record("measure blocked reason=noPermission")
            PermissionWindow.show()
            return
        }
        let overlay = MeasureOverlay(model: self, capturer: capturer, exclusions: exclusions)
        isMeasuring = true
        overlay.onClose = { [weak self] error in
            self?.isMeasuring = false
            if let error { self?.report(error) }
        }
        overlay.show(started: started)
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

    func copy(_ text: String) {
        pasteboard.write(text)
    }
}
