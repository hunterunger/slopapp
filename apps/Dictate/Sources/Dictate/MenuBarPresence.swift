import AppKit
import DictateCore
import Observation
import SlopKit

/// Notices when the menu bar icon is out of sight (a full menu bar hides icons that don't
/// fit, next to the camera notch above all), so Settings can say so and how to get around it.
/// Best effort: macOS doesn't tell apps, so this reads where the icon's window ended up
/// (`StatusItemPlacement`). Could move to SlopKit for every menu bar app.
@Observable
final class MenuBarPresence {
    /// The icon should be showing but seems not to be.
    private(set) var isHidden = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var observingScreens = false
    /// Called once when the icon is first found hidden.
    @ObservationIgnored var onFirstHidden: () -> Void = {}
    @ObservationIgnored private var reported = false
    @ObservationIgnored private var reinserted = false

    /// Looks again after `delay` (the menu bar settles its layout a moment after launch).
    func check(after delay: Duration = .zero) {
        observeScreens()
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard MenuBarPresence.wantsIcon else {
            isHidden = false
            return
        }
        let window = Self.statusItemWindow
        let screens = NSScreen.screens.map {
            StatusItemPlacement.Screen(frame: $0.frame, topLeftArea: $0.auxiliaryTopLeftArea,
                                       topRightArea: $0.auxiliaryTopRightArea)
        }
        let hidden = StatusItemPlacement.isHidden(itemFrame: window?.frame, isOnScreen: window?.isVisible ?? false,
                                                  screens: screens)
        Diagnostics.record("status item frame=\(window.map { NSStringFromRect($0.frame) } ?? "none") visible=\(window?.isVisible ?? false) hidden=\(hidden)")
        if hidden, !reinserted {
            // A new copy's icon sometimes never gets a place until it's put in again (seen on
            // macOS 27 with a fresh bundle id): take it out and back in once, then look again.
            reinserted = true
            Diagnostics.defaults.set(false, forKey: MenuBarIcon.storageKey)
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                Diagnostics.defaults.set(true, forKey: MenuBarIcon.storageKey)
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.evaluate()
            }
            return
        }
        isHidden = hidden
        if hidden, !reported {
            reported = true
            onFirstHidden()
        }
    }

    static var wantsIcon: Bool {
        Diagnostics.defaults.object(forKey: MenuBarIcon.storageKey) as? Bool ?? true
    }

    /// SwiftUI's status item lives in a window of AppKit's private status bar window class.
    private static var statusItemWindow: NSWindow? {
        NSApp.windows.first { NSStringFromClass(type(of: $0)).contains("StatusBarWindow") }
    }

    private func observeScreens() {
        guard !observingScreens else { return }
        observingScreens = true
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(after: .seconds(2)) }
        }
    }
}
