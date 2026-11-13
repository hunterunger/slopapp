import AppKit
import SlopKit
import SwiftUI

/// Help › Clips Help: how Clips works and every key, in a window of its own (no browser).
struct HelpWindow: View {
    static let id = "help"

    private struct Topic: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    private static let topics: [Topic] = [
        Topic(title: "Paste from your history",
              text: "Press ⇧⌥V in any app (or choose Show Clips from the menu bar icon). Type a few letters to search, then press Return to paste the clip into the app you were using. Space previews the selected clip; Esc closes."),
        Topic(title: "Boards",
              text: "Boards keep the clips you reuse. Clips on a board are never removed automatically. ⌘P pins to the first board, ⌥⌘1 to ⌥⌘9 to that board, or drag cards onto a board's tab (or onto + for a new board). Double-click a tab to rename it; right-click it to change its colour, move it or delete it."),
        Topic(title: "Titles and edits",
              text: "⌘R gives a clip a title, shown on its card and found by search. ⌘E edits a text clip; the edited text is what pastes. ⌘S saves, Esc throws the changes away."),
        Topic(title: "Several clips at once",
              text: "⌘-click, ⇧-click, ⇧-arrows or ⌘A select several cards. Return pastes them together in the order you copied them; ⌘C copies them; ⌘P pins them; ⌘⌫ deletes them (⌘Z brings them back)."),
        Topic(title: "Paste stack",
              text: "For filling in forms: press ⇧⌘C in the strip, copy things in order, then paste. Each paste takes the next one until the last. With several cards selected, ⇧⌘C stacks those. A list in the top-right corner shows what's next; ✕ stops it."),
        Topic(title: "Text in images",
              text: "Clips reads the text in images you copy, on this Mac, so searching finds screenshots by their words. Right-click an image card and choose Copy Text in Image to get the text."),
        Topic(title: "Privacy",
              text: "Your history never leaves this Mac. Passwords and anything an app marks as private are never recorded, and Settings › Privacy lists apps whose copies are ignored."),
    ]

    private static let keys: [(String, String)] = [
        ("⇧⌥V", "Open or close the strip"),
        ("Return", "Paste (⇧Return as plain text)"),
        ("⌘1 – ⌘9", "Paste that card"),
        ("← →", "Move (⇧ to select several, ⌘A selects all)"),
        ("⌘← ⌘→", "Previous or next tab"),
        ("Tab", "Search or cards"),
        ("Space", "Preview"),
        ("⌘C", "Copy only"),
        ("⌘E", "Edit"),
        ("⌘R", "Title"),
        ("⌘P", "Pin or unpin"),
        ("⌥⌘1 – ⌥⌘9", "Pin to that board"),
        ("⇧⌘N", "New board"),
        ("⇧⌘C", "Paste stack"),
        ("⌘⌫", "Delete (⌘Z undoes)"),
        ("⌘O", "Open a link or file"),
        ("⌘T", "Pause or resume recording"),
        ("⌘Y", "History window"),
        ("Esc", "Back out one step, then close"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ForEach(Self.topics) { topic in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(topic.title).font(.headline)
                        Text(topic.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Keys in the strip").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xs) {
                        ForEach(Self.keys, id: \.0) { key, action in
                            GridRow {
                                Text(key).monospacedDigit().fontWeight(.medium)
                                Text(action).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("More Help on the Web") {
                    NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Clips"))
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 360, idealHeight: 620)
    }
}

/// Opens the help window from code that isn't a view (the strip's ⋯ menu).
@MainActor
enum HelpOpener {
    static var action: (() -> Void)?

    static func open() {
        NSApp.activate()
        if let action {
            action()
            return
        }
        // The menu bar icon (where the action is captured) may be hidden: use the Help menu.
        for item in NSApp.mainMenu?.items ?? [] {
            guard let menu = item.submenu, let index = menu.items.firstIndex(where: { $0.title == "Clips Help" }) else { continue }
            menu.performActionForItem(at: index)
            return
        }
    }
}
