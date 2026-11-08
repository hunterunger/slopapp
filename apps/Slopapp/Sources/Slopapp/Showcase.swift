import AppKit
import SlopappCore
import SlopKit

/// Store screenshot scenes (`SLOP_SHOWCASE`, docs/screenshots.md), all in the library window:
///
/// - `discover`: the Discover page (featured banner, category rows).
/// - `app`: an app's page with its screenshot gallery (`SLOPAPP_SHOWCASE_APP`, default Snapper).
/// - `updates`: the Updates page with updates waiting, and two apps updated earlier this week.
///
/// The content is synthetic: `scripts/shots.sh` runs `apps/Slopapp/showcase-fixtures.sh`
/// first (a local feed built from this repo's apps, and older copies of a few of them "installed"
/// in the scene's own folder), and `ShowcaseSandbox` keeps every path the launcher uses inside
/// the scene's data folder, so a scene never sees or changes the apps on this Mac. Each scene
/// waits for the catalog, the icons and (on an app page) the screenshots before it's ready.
@MainActor
enum ShowcaseScenes {
    static let scenes = ["discover", "app", "updates"]

    static func run(_ scene: String, store: Store, navigation: Navigation) {
        guard scenes.contains(scene) else {
            Showcase.fail("Slopapp has no scene \"\(scene)\" (\(scenes.joined(separator: ", ")))")
            return
        }
        Task {
            do {
                try await show(scene, store: store, navigation: navigation)
            } catch let error as SceneError {
                Showcase.fail("scene \(scene): \(error.message)")
            } catch {
                Showcase.fail("scene \(scene): \(error.localizedDescription)")
            }
        }
    }

    private static func show(_ scene: String, store: Store, navigation: Navigation) async throws {
        try await wait("the catalog to load (\(store.config.feedURL.path))", timeout: .seconds(10)) {
            store.feed != nil && !store.items.isEmpty && !store.isChecking
        }
        if let error = store.feedError { throw SceneError(message: "the catalog didn't load: \(error)") }
        switch scene {
        case "app":
            let slug = ProcessInfo.processInfo.environment["SLOPAPP_SHOWCASE_APP"] ?? "snapper"
            guard let item = store.item(slug), !item.app.shots.isEmpty else {
                throw SceneError(message: "the feed has no screenshots for \(slug)")
            }
            navigation.show(.discover)
            navigation.showDetail(slug)
        case "updates":
            guard !store.updates.isEmpty else {
                throw SceneError(message: "nothing to update (are older copies in \(store.config.roots.installDirectory.path)?)")
            }
            store.showcaseRecentUpdates(recentUpdates(store))
            navigation.show(.updates)
        default:
            navigation.show(.discover)
        }

        var found: NSWindow?
        try await wait("the library window", timeout: .seconds(5)) {
            found = mainWindow
            return found != nil
        }
        guard let window = found else { return }
        // Sized now, so the images load at the size they're captured at.
        Showcase.place(window)
        Showcase.bringToFront(window)
        // No focus ring or caret in the search field.
        window.makeFirstResponder(nil)

        try await wait("the app icons", timeout: .seconds(10)) { missingIcons(store).isEmpty }
        if scene == "app" {
            try await wait("the screenshots", timeout: .seconds(10)) { try shotsLoaded(store.shotImages) }
        }
        // Layout can still ask for another size of an image: ready once nothing changed for a moment.
        try await waitUntilSettled {
            guard missingIcons(store).isEmpty else { return false }
            return scene == "app" ? try shotsLoaded(store.shotImages) : true
        }
        window.makeFirstResponder(nil)
        Showcase.ready { [mainWindow] }
    }

    /// Two apps updated earlier this week (from 0.1.0 to the feed's version), for the
    /// Updates page's "Recently Updated" list.
    private static func recentUpdates(_ store: Store) -> [RecentUpdate] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let picks: [(slug: String, daysAgo: Int, hour: Int, minute: Int)] = [("snapper", 1, 16, 40), ("switchboard", 3, 9, 15)]
        return picks.compactMap { pick in
            guard let item = store.item(pick.slug), let version = item.app.version,
                  let day = calendar.date(byAdding: .day, value: -pick.daysAgo, to: today),
                  let date = calendar.date(bySettingHour: pick.hour, minute: pick.minute, second: 0, of: day) else { return nil }
            return RecentUpdate(slug: item.id, name: item.app.name, from: "0.1.0", to: version, date: date)
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true && $0.isVisible }
    }

    private static func missingIcons(_ store: Store) -> [String] {
        ShowcaseSandbox.missingIcons(store.items, allows: store.config.urlPolicy.allows) { store.icons.image(for: $0) != nil }
    }

    /// Every screenshot the gallery asked for has loaded (and at least one did).
    private static func shotsLoaded(_ images: ShotImages) throws -> Bool {
        let phases = Array(images.phases.values)
        if phases.contains(.failed) { throw SceneError(message: "a screenshot didn't load") }
        return !phases.isEmpty && !phases.contains(.loading)
    }

    private struct SceneError: Error {
        var message: String
    }

    /// Polls `condition` every 50 ms until it holds, or fails with what it was waiting for.
    private static func wait(_ what: String, timeout: Duration, _ condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while try !condition() {
            guard clock.now < deadline else { throw SceneError(message: "gave up waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// `condition` held on three checks in a row, 150 ms apart.
    private static func waitUntilSettled(_ condition: () throws -> Bool) async throws {
        var streak = 0
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while streak < 3 {
            guard clock.now < deadline else { throw SceneError(message: "the page kept changing") }
            streak = try condition() ? streak + 1 : 0
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}
