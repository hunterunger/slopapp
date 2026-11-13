import SwiftUI

/// The standard Settings window: General, Shortcuts (if any), Advanced (if any), About.
///
///     Settings {
///         SlopSettings(info: info, isMenuBarApp: true) {
///             Toggle("Keep display on", isOn: $keepDisplayOn)      // extra General rows
///         } shortcuts: {
///             ShortcutRow("Open picker", name: .openPicker)
///         }
///     }
///
/// Tabs whose builder is left empty are hidden.
public struct SlopSettings<General: View, Shortcuts: View, Advanced: View>: View {
    let info: AppInfo
    let isMenuBarApp: Bool
    let general: General
    let shortcuts: Shortcuts
    let advanced: Advanced

    public init(
        info: AppInfo,
        isMenuBarApp: Bool,
        @ViewBuilder general: () -> General = { EmptyView() },
        @ViewBuilder shortcuts: () -> Shortcuts = { EmptyView() },
        @ViewBuilder advanced: () -> Advanced = { EmptyView() }
    ) {
        self.info = info
        self.isMenuBarApp = isMenuBarApp
        self.general = general()
        self.shortcuts = shortcuts()
        self.advanced = advanced()
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: isMenuBarApp, appName: info.name) { general }
                .tabItem { Label("General", systemImage: "gearshape") }
            if Shortcuts.self != EmptyView.self {
                SettingsForm { shortcuts }
                    .tabItem { Label("Shortcuts", systemImage: "command") }
            }
            if Advanced.self != EmptyView.self {
                SettingsForm { advanced }
                    .tabItem { Label("Advanced", systemImage: "gearshape.2") }
            }
            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}

/// A grouped form at the standard Settings width. Use for custom tabs.
public struct SettingsForm<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// General tab: Launch at login, menu bar icon visibility (menu bar apps), then app rows.
public struct GeneralSettingsTab<Content: View>: View {
    let isMenuBarApp: Bool
    let appName: String
    let content: Content
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true

    public init(isMenuBarApp: Bool, appName: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.isMenuBarApp = isMenuBarApp
        self.appName = appName
        self.content = content()
    }

    private static var isMenuBarOnly: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
    }

    public var body: some View {
        SettingsForm {
            Section {
                LaunchAtLoginToggle()
                if isMenuBarApp {
                    Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                    // Only a menu-bar-only app needs the way back spelled out; an app with a
                    // window (the launcher) reaches Settings from that window.
                    if !showMenuBarIcon, Self.isMenuBarOnly {
                        Text("To bring the icon back, open \(appName) again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if Content.self != EmptyView.self {
                Section { content }
            }
        }
    }
}

/// About tab: the standard About view, centered.
public struct AboutSettingsTab: View {
    let info: AppInfo

    public init(info: AppInfo) {
        self.info = info
    }

    public var body: some View {
        AboutView(info: info)
            .frame(maxWidth: .infinity)
            // The icon artwork has about 9 pt of transparent margin at 96 pt, so a little
            // less padding on top makes the visible gaps above and below equal.
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
    }
}
