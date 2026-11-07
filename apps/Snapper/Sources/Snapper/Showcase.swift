import AppKit
import SlopKit
import SnapperCore

/// Store screenshot scenes (`SLOP_SHOWCASE`, docs/screenshots.md). Every capture in them is
/// made-up artwork (`ShowcaseArtwork`); nothing on screen is captured.
///
/// - `annotate`: the editor on a sales dashboard with arrows, a box, numbered steps, a label
///   and a blurred address.
/// - `card`: two fresh captures waiting in the corner, the newest with its quick actions.
/// - `background`: the editor's Background sidebar framing a checklist for sharing.
/// - `history`: Capture History with two days of captures.
///
/// `scripts/shots.sh Snapper` runs a private copy (its own bundle id) with
/// `SNAPPER_HISTORY_DIR` and `SNAPPER_SAVE_DIR` in the scene's scratch folder, so the scenes
/// never touch the installed Snapper's history, settings or save folder.
@MainActor
enum ShowcaseScenes {
    /// The card scene's newest capture shows its quick actions, as if the pointer were on it.
    static let hoveredCardName = "Showcase: hovered card"

    static func run(_ scene: String, model: AppModel) {
        // Captures belong on the primary screen, where the backdrop is.
        model.cardFollowsPointer = false
        let display = CGMainDisplayID()
        switch scene {
        case "annotate":
            guard let image = ShowcaseArtwork.image(.dashboard, size: CGSize(width: 1100, height: 610)) else {
                return Showcase.fail("couldn't draw the dashboard")
            }
            let item = CaptureItem(image: image, scale: 2, displayID: display)
            item.sourceName = "Weekly sales"
            EditorWindowController.open(item, model: model)
            if let editor = EditorWindowController.front { annotate(editor) }
            Showcase.ready { [editorWindow] }

        case "background":
            guard let image = ShowcaseArtwork.image(.checklist, size: CGSize(width: 440, height: 330)) else {
                return Showcase.fail("couldn't draw the checklist")
            }
            let item = CaptureItem(image: image, scale: 2, displayID: display)
            item.sourceName = "Friday release"
            EditorWindowController.open(item, model: model)
            if let editor = EditorWindowController.front {
                editor.toggleBackground()
                editor.setBackground(CaptureBackground(fill: .gradient(.sunrise), padding: 72, cornerRadius: 16, shadow: 0.6)) // lint:allow the capture's frame (image content), not a UI corner
                editor.tool = .select
            }
            Showcase.ready { [editorWindow] }

        case "card":
            let older = ShowcaseArtwork.image(.landscape, size: CGSize(width: 640, height: 400))
            let newer = ShowcaseArtwork.image(.dashboard, size: CGSize(width: 1100, height: 610))
            // Big enough to read at gallery size (the Settings slider goes to 320).
            model.cardWidth = 300
            for (image, hovered) in [(older, false), (newer, true)] {
                guard let image else { continue }
                let item = CaptureItem(image: image, scale: 2, displayID: display)
                item.sourceName = hovered ? hoveredCardName : item.fileBaseName
                model.cards.add(item)
            }
            Showcase.ready(statusItem: "camera", arrange: false) {
                // Back to front: the older card above, the newest nearest the corner.
                model.cards.windowNumbers.compactMap { NSApp.window(withWindowNumber: $0) }
                    .sorted { $0.frame.minY > $1.frame.minY }
            }

        case "history":
            fillHistory(model)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                HistoryWindowController.show()
                Showcase.ready { [NSApp.windows.first { $0.title == "Capture History" && $0.isVisible }] }
            }

        default:
            Showcase.fail("Snapper has no scene \"\(scene)\" (annotate, card, background, history)")
        }
    }

    private static var editorWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && EditorWindowController.owns($0) }
    }

    /// Marks on the dashboard: a box around the best day, an arrow and a label pointing at
    /// revenue, numbered steps on the top items, and the email address blurred. The box stays
    /// selected, so its handles show it can still be changed.
    private static func annotate(_ editor: EditorModel) {
        let red = PaletteColor.default.color
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 557, y: 286), end: CGPoint(x: 643, y: 522), color: red)
        editor.editor.add(Annotation(kind: .blur, start: CGPoint(x: 211, y: 548), end: CGPoint(x: 389, y: 572)))
        editor.editor.add(Annotation(kind: .arrow, start: CGPoint(x: 796, y: 452), end: CGPoint(x: 652, y: 418), color: red))
        editor.editor.add(Annotation(kind: .text, start: CGPoint(x: 806, y: 436), color: red, text: "Best day since June"))
        editor.editor.add(Annotation(kind: .counter, start: CGPoint(x: 896, y: 274), color: red, number: 1))
        editor.editor.add(Annotation(kind: .counter, start: CGPoint(x: 877, y: 302), color: red, number: 2))
        editor.editor.add(box)
        editor.editor.selection = box.id
        editor.tool = .select
        editor.changed()
    }

    /// Nine made-up captures over today and yesterday, from the apps people capture most.
    private static func fillHistory(_ model: AppModel) {
        let now = Date()
        let shots: [(ShowcaseArtwork.Kind, Int, CGSize, HistoryKind, String, String, TimeInterval)] = [
            (.dashboard, 0, CGSize(width: 1100, height: 610), .screenshot, "com.apple.Safari", "Safari", 600),
            (.chat, 0, CGSize(width: 640, height: 420), .window, "com.apple.MobileSMS", "Messages", 1_900),
            (.palette, 0, CGSize(width: 720, height: 460), .screenshot, "com.apple.Preview", "Preview", 3_600),
            (.calendar, 0, CGSize(width: 800, height: 500), .window, "com.apple.iCal", "Calendar", 5_400),
            (.landscape, 0, CGSize(width: 640, height: 400), .screenshot, "com.apple.Photos", "Photos", 7_800),
            (.checklist, 0, CGSize(width: 440, height: 330), .window, "com.apple.Notes", "Notes", 86_400 + 1_200),
            (.palette, 1, CGSize(width: 720, height: 460), .screenshot, "com.apple.Safari", "Safari", 86_400 + 4_000),
            (.landscape, 1, CGSize(width: 640, height: 400), .screenshot, "com.apple.Photos", "Photos", 86_400 + 9_000),
            (.chat, 0, CGSize(width: 640, height: 420), .window, "com.apple.MobileSMS", "Messages", 86_400 + 12_000),
        ]
        // Oldest first, so the index ends up newest first.
        for shot in shots.reversed() {
            guard let image = ShowcaseArtwork.image(shot.0, size: shot.2, variant: shot.1) else { continue }
            let item = CaptureItem(image: image, scale: 2, displayID: CGMainDisplayID(), createdAt: now.addingTimeInterval(-shot.6))
            model.history.record(item, kind: shot.3, source: SourceApp(bundleID: shot.4, name: shot.5))
        }
    }
}
