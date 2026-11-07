import AppKit
import CommitCore
import SlopKit
import SwiftUI

// Archetype: library window (one per repository) with document-style plumbing: a welcome
// window, Open Recent, folders as an Alternate document type, windows restored on relaunch.
// See docs/design-system.md 2c/2e and docs/research/commit.md.

struct CommitApp: App {
    @NSApplicationDelegateAdaptor(CommitAppDelegate.self) private var appDelegate
    @State private var app = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Commit")

    var body: some Scene {
        Window("Welcome to Commit", id: "welcome") {
            WelcomeView(app: app)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommitCommands(app: app, info: info)
        }

        WindowGroup("Repository", id: "repository", for: URL.self) { $url in
            if let url {
                RepoWindow(url: url, app: app)
            } else {
                RepoPlaceholder(app: app)
            }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(app: app, info: info)
        }
    }
}

/// Window app plumbing without quitting on last window close (a library window app keeps
/// running with no windows, like Finder or Mail). Dock-icon clicks bring back the welcome
/// window; folders dropped on the Dock icon or sent with `open -a` open as repositories.
@MainActor
final class CommitAppDelegate: NSObject, NSApplicationDelegate {
    private let slop = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        slop.applicationWillFinishLaunching(notification)
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.prepare()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showWelcome() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppModel.shared.open(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.quit()
    }
}

/// ⌘⌫ and ⌘↑/⌘↓ are also text-editing keys. When a text field or editor has focus, the menu
/// item hands the key back to it, so typing in the composer never discards lines.
@MainActor
enum TextEditingKeys {
    static func forward(_ selector: Selector) -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable else { return false }
        editor.doCommand(by: selector)
        return true
    }
}

/// The focused repository window, for menu commands.
struct RepoModelKey: FocusedValueKey {
    typealias Value = RepoModel
}

extension FocusedValues {
    var repoModel: RepoModel? {
        get { self[RepoModelKey.self] }
        set { self[RepoModelKey.self] = newValue }
    }
}

/// Every action, in a menu, with its shortcut (design system §6). Menu items are text only.
struct CommitCommands: Commands {
    let app: AppModel
    let info: AppInfo
    @FocusedValue(\.repoModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Commit") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…") { app.chooseRepository() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recents.paths, id: \.self) { path in
                    Button(RecentRow.display(path)) { app.open(URL(fileURLWithPath: path)) }
                }
                if !app.recents.paths.isEmpty { Divider() }
                Button("Clear Menu") { app.clearRecents() }
                    .disabled(app.recents.paths.isEmpty)
            }
            Divider()
            Button("Show in Finder") { model?.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model?.repository == nil)
            Button("Open in Terminal") { model?.openInTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(model?.repository == nil)
        }
        CommandGroup(after: .undoRedo) {}

        CommandGroup(before: .sidebar) {
            Button("Changes") { model?.sidebarSelection = .changes }
                .keyboardShortcut("1")
                .disabled(model?.repository == nil)
            Button("History") { model?.sidebarSelection = .history }
                .keyboardShortcut("2")
                .disabled(model?.repository == nil)
            Button("Stashes") { model?.sidebarSelection = .stashes }
                .keyboardShortcut("3")
                .disabled(model?.repository == nil)
            Divider()
            Button(model?.showAllBranches == true ? "Show Current Branch in History" : "Show All Branches in History") {
                model?.toggleAllBranches()
            }
                .disabled(model?.repository == nil)
            Button("More Context") { model?.changeContext(by: 1) }
                .keyboardShortcut("=")
                .disabled(model?.repository == nil)
            Button("Less Context") { model?.changeContext(by: -1) }
                .keyboardShortcut("-")
                .disabled(model?.repository == nil)
            Button(model?.ignoreWhitespace == true ? "Show Whitespace Changes" : "Ignore Whitespace Changes") {
                model?.toggleIgnoreWhitespace()
            }
            .disabled(model?.repository == nil)
            Divider()
        }

        CommandMenu("Changes") {
            Button(model?.commitButtonTitle ?? "Commit") { model?.commit(thenPush: false) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.canCommit != true)
            Button("Commit and Push") { model?.commit(thenPush: true) }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(model?.canCommit != true)
            Button(model?.amend == true ? "Stop Amending" : "Amend Last Commit") { model?.toggleAmend() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model?.status.branch.isUnborn != false)
            Button("Focus Commit Message") { model?.focusComposer() }
                .keyboardShortcut("l")
                .disabled(model?.repository == nil)
            Divider()
            Button(model?.stageToggleTitle ?? "Stage or Unstage Selection") { model?.toggleSelection() }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
                .disabled(model?.canToggleSelection != true)
            Button("Stage All") { model?.stageAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(model?.status.unstaged.isEmpty != false)
            Button("Unstage All") { model?.unstageAll() }
                .keyboardShortcut("a", modifiers: [.command, .option, .shift])
                .disabled(model?.status.staged.isEmpty != false)
            Button("Mark Resolved") { model?.markSelectedResolved() }
                .disabled(model?.selectedConflicts.isEmpty != false)
            Divider()
            Button(model?.discardTitle ?? "Discard…") {
                if TextEditingKeys.forward(#selector(NSResponder.deleteToBeginningOfLine(_:))) { return }
                model?.discardSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model?.canDiscardSelection != true && model?.isEditingText != true)
            Button("Discard All Changes…") { model?.confirmDiscardAll() }
                .keyboardShortcut(.delete, modifiers: [.command, .option, .shift])
                .disabled(model?.status.isClean != false)
            Divider()
            Button("Next Change") {
                if TextEditingKeys.forward(#selector(NSResponder.moveToEndOfDocument(_:))) { return }
                model?.moveToHunk(forward: true)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(model?.canMoveBetweenHunks != true && model?.isEditingText != true)
            Button("Previous Change") {
                if TextEditingKeys.forward(#selector(NSResponder.moveToBeginningOfDocument(_:))) { return }
                model?.moveToHunk(forward: false)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(model?.canMoveBetweenHunks != true && model?.isEditingText != true)
        }

        CommandMenu("Branch") {
            Button("New Branch…") { model?.showNewBranch(from: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model?.status.branch.isUnborn != false)
            Button("Switch Branch…") { model?.showBranchSwitcher = true }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(model?.repository == nil)
        }

        CommandMenu("Repository") {
            Button("Fetch") { model?.fetch() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model?.canSync != true)
            Button("Pull") { model?.pull() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model?.canPull != true)
            Button("Push") { model?.push() }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(model?.canPush != true)
            if model?.activity?.isCancellable == true {
                Button("Cancel \(model?.activity?.title ?? "")") { model?.cancelActivity() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            Divider()
            Button("Stash Changes…") { model?.showStashSheet() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model?.status.isClean != false)
            if let op = model?.inProgress {
                Divider()
                Button("Continue \(op.noun)") { model?.continueOperation() }
                    .disabled(model?.status.conflicted.isEmpty == false)
                Button("Abort \(op.noun)…") { model?.confirmAbort() }
            }
            Divider()
            Button("Refresh") { model?.refreshNow(full: true) }
                .keyboardShortcut("r")
                .disabled(model?.repository == nil)
        }
    }
}
