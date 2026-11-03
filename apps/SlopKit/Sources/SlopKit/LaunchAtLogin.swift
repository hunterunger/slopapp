import Observation
import ServiceManagement
import SwiftUI

/// Observable wrapper around `SMAppService.mainApp`.
/// Only works from a real .app bundle; under `swift run` it reports an error instead.
@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var isEnabled: Bool
    public private(set) var lastError: String?

    public init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Couldn't change this. Try again, or add the app in System Settings > General > Login Items."
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// "Launch at login" toggle, with the error shown under it when registration fails.
public struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = LaunchAtLogin()

    public init() {}

    public var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.set($0) }
        ))
        if let error = launchAtLogin.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
