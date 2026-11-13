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
            HelpCommands(info: info)
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

        Window("Clone Repository", id: "clone") {
            CloneWindow(app: app)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        WindowGroup("File History", id: "file-history", for: FileHistoryTarget.self) { $target in
            if let target {
                FileHistoryWindow(target: target)
            } else {
                ContentUnavailableView("No File", systemImage: "clock",
                                       description: Text("Choose Show File History on a file in a repository window."))
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .defaultSize(width: 1000, height: 680)
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
    @FocusedValue(\.fileHistoryModel) private var fileHistory

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Commit") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…") { app.chooseRepository() }
                .keyboardShortcut("o")
            Button("Clone Repository…") { app.showClone() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
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
            Divider()
            Button("Show File History") { model?.showHistoryOfSelectedFile(blame: false) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model?.fileForHistory == nil)
            Button("Show Blame") { model?.showHistoryOfSelectedFile(blame: true) }
                .keyboardShortcut("h", modifiers: [.command, .shift, .option])
                .disabled(model?.fileForHistory == nil)
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
            // File History windows.
            Button("Changes in Version") { fileHistory?.mode = .changes }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(fileHistory == nil)
            Button("Blame of Version") { fileHistory?.mode = .blame }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(fileHistory == nil)
            Button("Newer Version") { fileHistory?.goNewer() }
                .keyboardShortcut("]")
                .disabled(fileHistory?.canGoNewer != true)
            Button("Older Version") { fileHistory?.goOlder() }
                .keyboardShortcut("[")
                .disabled(fileHistory?.canGoOlder != true)
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
            Button("Mark Resolved") {
                if model?.conflict != nil { model?.markConflictResolved() } else { model?.markSelectedResolved() }
            }
                .disabled(model?.selectedConflicts.isEmpty != false)
            Button("Use Our Whole File") { model?.takeWholeFile(ours: true) }
                .disabled(model?.selectedConflicts.isEmpty != false)
            Button("Use Their Whole File") { model?.takeWholeFile(ours: false) }
                .disabled(model?.selectedConflicts.isEmpty != false)
            Button("Open in \(model?.mergeTool.name ?? "Merge Tool")") {
                if let entry = model?.selectedConflicts.first { model?.openInMergeTool(entry) }
            }
            .disabled(model?.selectedConflicts.count != 1 || model?.canUseMergeTool != true)
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
            Divider()
            Button("Merge into \(model?.currentBranchName ?? "Current Branch")…") { model?.showIntegrate(.merge) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model?.canIntegrateOnBranch != true)
            Button("Rebase \(model?.currentBranchName ?? "Current Branch")…") { model?.showIntegrate(.rebase) }
                .keyboardShortcut("m", modifiers: [.command, .shift, .option])
                .disabled(model?.canIntegrateOnBranch != true)
            Button(model?.cherryPickTitle ?? "Cherry-pick onto Current Branch") { model?.cherryPickSelection() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.canCherryPickSelection != true)
            Button("Revert Commit") { if let id = model?.historySelection { model?.revert(id) } }
                .disabled(model?.canIntegrate != true || model?.isShowingHistory != true || model?.selectedCommits.count != 1)
            Button("Edit History from Selected Commit…") { if let id = model?.historySelection { model?.editHistory(from: id) } }
                .disabled(model?.canIntegrateOnBranch != true || model?.isShowingHistory != true || model?.selectedCommits.count != 1)
            Button("Edit Unpushed Commits…") { model?.editUnpushedCommits() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model?.canEditUnpushed != true)
            Divider()
            Button("New Tag…") {
                model?.showNewTag(at: model?.isShowingHistory == true && model?.selectedCommits.count == 1 ? model?.historySelection : nil)
            }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model?.status.branch.isUnborn != false)
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
            Button("Force Push…") { model?.confirmForcePush() }
                .keyboardShortcut("u", modifiers: [.command, .option, .shift])
                .disabled(model?.canForcePush != true)
            Button("Push Tags") { model?.pushAllTags() }
                .disabled(model?.canPushTags != true)
            if model?.activity?.isCancellable == true {
                Button("Cancel \(model?.activity?.title ?? "")") { model?.cancelActivity() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            Divider()
            Button("Stash Changes…") { model?.showStashSheet() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model?.status.isClean != false)
            Button("Remotes…") { model?.showRemotes() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model?.repository == nil)
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
