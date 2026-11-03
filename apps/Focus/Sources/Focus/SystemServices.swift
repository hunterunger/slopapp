import AppKit
import FocusCore
import os
import UserNotifications

/// End-of-phase notifications through Notification Center, with action buttons.
/// The sound is played separately (`SystemSound`) so the "Play sound" setting and the
/// sound picker apply whether or not notifications are allowed.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    var onAction: ((AlertAction) -> Void)?
    private let center = UNUserNotificationCenter.current()
    /// Every combination of buttons `AlertContent` uses.
    private static let actionSets: [[AlertAction]] = [[], [.skipBreak], [.startBreak, .startFocus], [.startFocus]]

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(Self.actionSets.map { actions in
            let content = AlertContent(title: "", body: "", actions: actions)
            return UNNotificationCategory(
                identifier: content.category,
                actions: actions.map { UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: []) },
                intentIdentifiers: []
            )
        }))
    }

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestPermission() async -> NotificationPermission {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            Self.logger.info("notification permission granted=\(granted, privacy: .public)")
        } catch {
            Self.logger.error("notification permission request failed: \(String(describing: error), privacy: .public)")
        }
        return await permission()
    }

    private static let logger = Logger(subsystem: "app.slopapp.focus", category: "notifications")

    func post(_ content: AlertContent) {
        let note = UNMutableNotificationContent()
        note.title = content.title
        note.body = content.body
        note.categoryIdentifier = content.category
        note.sound = nil
        note.interruptionLevel = .active
        // One identifier: each new notification replaces the last instead of piling up.
        center.add(UNNotificationRequest(identifier: "focus.phase", content: note, trigger: nil)) { error in
            if let error {
                Self.logger.error("couldn't post notification: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = AlertAction(rawValue: response.actionIdentifier)
        completionHandler()
        guard let action else { return }
        Task { @MainActor in self.onAction?(action) }
    }

    /// Show banners even while Settings is open (the app is "active" then).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "app.slopapp.focus")")!
}

/// System alert sounds (Glass, Ping, ...).
@MainActor
final class SystemSound: SoundPlayer {
    private var playing: NSSound?

    static var systemSoundNames: [String] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let names = files.map { $0.deletingPathExtension().lastPathComponent }
        return names.isEmpty ? ["Glass"] : names.sorted()
    }

    var availableSounds: [String] { Self.systemSoundNames }

    func play(_ name: String) {
        playing?.stop()
        playing = NSSound(named: NSSound.Name(name)) ?? NSSound(named: NSSound.Name("Glass"))
        playing?.play()
    }
}
