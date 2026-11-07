import AppKit
import SlopKit
import SwitchboardCore

/// Store screenshot scenes (`SLOP_SHOWCASE`, docs/screenshots.md), with the synthetic
/// settings from `ShowcaseFixtures` (AppModel loads them instead of the real ones):
///
/// - `picker`: the picker choosing a browser for a link, under the menu bar icon.
/// - `browsers`, `rules`: those Settings tabs.
///
/// `scripts/shots.sh Switchboard` runs a private copy with its own bundle id, so the scenes
/// never touch the installed Switchboard, its settings, or which app opens links.
@MainActor
enum ShowcaseScenes {
    static func run(_ scene: String, model: AppModel) {
        switch scene {
        case "picker":
            // After the launch prewarm, which builds the panel off-screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let picker = LinkRouter.shared.picker
                picker.show(IncomingLink(url: ShowcaseFixtures.link, forcePicker: true),
                            targets: model.config.pickerTargets, size: model.config.pickerSize,
                            receivedAt: Diagnostics.now(), waitingCount: 0)
                Showcase.ready(statusItem: "signpost.right.fill") { [picker.window] }
            }
        case SettingsTab.browsers.rawValue, SettingsTab.rules.rawValue:
            // SettingsView opens on this tab (Diagnostics.initialSettingsTab).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                SettingsWindow.open()
                // No focus ring on the link tester: the window as you'd find it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SettingsWindow.window?.makeFirstResponder(nil) }
                Showcase.ready(statusItem: "signpost.right.fill") { [SettingsWindow.window] }
            }
        default:
            Showcase.fail("Switchboard has no scene \"\(scene)\" (picker, browsers, rules)")
        }
    }
}
