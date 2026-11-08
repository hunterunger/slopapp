import AppKit
import ShorthandCore
import SlopKit
import SwiftUI

/// `SHORTHAND_SNAPSHOT_DIR=/path` (with `SHORTHAND_DATA_DIR`, `SHORTHAND_FAKE_APPS=1`): renders
/// the library (empty and full), the editor, the import preview and Settings offscreen in light
/// and dark, then quits. For layout review while the screen can't be driven. Materials and
/// the toolbar don't render offscreen; check those on screen with `scripts/drive shot`.
@MainActor
enum Snapshots {
    static func runIfAsked(model: AppModel) -> Bool {
        guard let directory = Diagnostics.snapshotDirectory, Diagnostics.isTestMode else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            let full = sampleLibrary
            let info = AppInfo.current(fallbackName: "Shorthand")
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                model.replaceForSnapshot(Library())
                render(LibraryWindow(model: model).frame(width: 920, height: 560), "library-empty-\(name)", directory)
                model.replaceForSnapshot(full)
                let selected = full.snippets[1]
                render(LibraryWindow(model: model, selection: [selected.id]).frame(width: 1040, height: 760), "library-\(name)", directory)
                render(SnippetEditor(model: model, snippetID: full.snippets[0].id, focusAbbreviation: 0).frame(width: 600, height: 760),
                       "editor-cursor-\(name)", directory)
                render(SnippetEditor(model: model, snippetID: full.snippets[3].id, focusAbbreviation: 0).frame(width: 600, height: 760),
                       "editor-conflict-\(name)", directory)
                render(SnippetEditor(model: model, snippetID: full.snippets[5].id, focusAbbreviation: 0).frame(width: 600, height: 760),
                       "editor-unknown-\(name)", directory)
                render(ImportSheet(model: model, rows: importRows(full)), "import-\(name)", directory)
                render(ImportSheet(model: model), "import-start-\(name)", directory)
                render(NoticeStack(model: model).frame(width: 320), "notices-\(name)", directory)
                render(GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                    Toggle("Expand abbreviations", isOn: .constant(true))
                    Toggle(isOn: .constant(true)) {
                        Text("Only expand at the start of a word")
                        Text("After a space, punctuation or a new line, so “sig” doesn't fire inside “design”.")
                    }
                }.frame(width: Metrics.settingsWidth), "settings-general-\(name)", directory)
                render(AppsTab(model: model).frame(width: Metrics.settingsWidth), "settings-apps-\(name)", directory)
                render(AdvancedTab(model: model).frame(width: Metrics.settingsWidth), "settings-advanced-\(name)", directory)
            }
            for status in [ExpansionStatus.expanding, .paused, .secureInput(app: "Safari"), .needsPermission, .inputMethod,
                           .excluded(app: "1Password"), .noSnippets] {
                Diagnostics.record("status line: \(status.line) | icon \(status.symbol) | label \(status.accessibilityLabel)")
            }
            NSApp.terminate(nil)
        }
        return true
    }

    static var sampleLibrary: Library {
        var library = Library()
        let work = library.addGroup(named: "Work")
        let off = library.addGroup(named: "Old Replies")
        library.setGroup(off.id, enabled: false)
        let g = library.defaultGroupID
        library.addSnippet(Snippet(groupID: g, name: "Letter opening", abbreviation: ";dear", content: "Dear {cursor},\n\nThanks for writing. slopapp-test"))
        library.addSnippet(Snippet(groupID: g, name: "Address", abbreviation: ";addr", content: "slopapp-test 1 Example Street\nSpringfield 12345"))
        library.addSnippet(Snippet(groupID: g, abbreviation: ";dt", content: "{date:iso}", useCount: 12))
        library.addSnippet(Snippet(groupID: g, name: "Short date", abbreviation: ";d", content: "{date:short}"))
        library.addSnippet(Snippet(groupID: work.id, name: "Meeting notes", abbreviation: ";meet", content: "Meeting notes for {date:long}\n\nAttendees: {clipboard}\n{cursor}"))
        library.addSnippet(Snippet(groupID: work.id, abbreviation: "sig", content: "slopapp-test Best regards, {name}"))
        library.addSnippet(Snippet(groupID: off.id, name: "Old sign-off", abbreviation: ";old", content: "slopapp-test Cheers"))
        library.addSnippet(Snippet(groupID: g, name: "", abbreviation: "", content: ""))
        return library
    }

    static func importRows(_ library: Library) -> [ImportCandidate] {
        TextReplacementsImport.candidates([
            (";omw", "slopapp-test On my way"), (";addr", "slopapp-test elsewhere"), ("has space", "slopapp-test"),
            (";br", "slopapp-test Best regards"), (";tm", "™"), (";shrug", "¯\\_(ツ)_/¯"),
        ], library: library)
    }

    private static func render<V: View>(_ view: V, _ name: String, _ directory: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        hosting.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        hosting.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}
