import AppKit
import SlopKit
import TidyCore

/// Test mode only: steps the real UI from a script and renders the app's windows to PNGs
/// (`cacheDisplay`, so it works while the screen is locked, when Accessibility can't see
/// windows). For design review on fixtures; the scripted walkthrough with `scripts/drive`
/// is still the real test. Ignored unless a `TIDY_*` test-mode variable is set.
///
///     TIDY_SNAPSHOT_SCRIPT=/tmp/tidy-test/script.txt  TIDY_SNAPSHOT_DIR=/tmp/tidy-test/shots
///
/// One command per line: `appearance light|dark`, `size W H`, `section spaceLens`,
/// `scope home|startup|disk NAME|folder PATH`, `scan`, `wait`, `stop`, `go ID`, `smaller ID`,
/// `back`, `forward`, `up`, `select ID`, `hover ID`, `check ID`, `uncheck ID`, `tray`, `untray`,
/// `inspect ID`, `uninspect`, `confirm`, `move`, `undo`, `startover`, `fda on|off`, `sleep MS`,
/// `shot NAME`, `state`, `quit`. The state log has counts and sizes only, never paths.
@MainActor
enum SnapshotScript {
    static func runIfRequested(_ model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard model.environment.isTestMode, let script = env["TIDY_SNAPSHOT_SCRIPT"],
              let text = try? String(contentsOfFile: script, encoding: .utf8) else { return }
        let dir = URL(fileURLWithPath: env["TIDY_SNAPSHOT_DIR"] ?? "/tmp/tidy-test/shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            for line in lines {
                await run(line, model: model, dir: dir)
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private static func log(_ dir: URL, _ text: String) {
        let file = dir.appendingPathComponent("state.log")
        let line = text + "\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }

    private static func run(_ line: String, model: AppModel, dir: URL) async {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        let space = model.space
        func find(_ id: String) -> MapItem? {
            if let item = space.item(id) { return item }
            guard let store = space.store, let node = store.find(id: id) else { return nil }
            let parent = (id as NSString).deletingLastPathComponent
            return store.snapshot(of: store.find(id: parent) ?? MapStore.root, id: parent).items.first { $0.node == node }
        }
        switch command {
        case "appearance": NSApp.appearance = NSAppearance(named: argument == "dark" ? .darkAqua : .aqua)
        case "size":
            let numbers = argument.split(separator: " ").compactMap { Double($0) }
            if numbers.count == 2, let window = mainWindow { window.setContentSize(NSSize(width: numbers[0], height: numbers[1])) }
        case "section": if let section = SidebarSection(rawValue: argument) { model.section = section }
        case "scope":
            if argument == "home" { space.scope = .home }
            else if argument == "startup", let disk = space.startupVolume { space.scope = .volume(disk) }
            else if argument.hasPrefix("disk "), let disk = space.volumes.first(where: { $0.name == String(argument.dropFirst(5)) }) {
                space.scope = .volume(disk)
            } else if argument.hasPrefix("folder ") { space.scope = .folder(URL(fileURLWithPath: String(argument.dropFirst(7)))) }
        case "scan": model.startSpaceScan()
        case "wait":
            for _ in 0..<300 where space.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
        case "stop": space.stop()
        case "scanstop":
            model.startSpaceScan()
            try? await Task.sleep(for: .milliseconds(Int(argument) ?? 50))
            space.stop()
        case "go": space.navigate(to: .folder(argument))
        case "smaller": space.navigate(to: .smaller(argument))
        case "back": space.back()
        case "forward": space.forward()
        case "up": space.goUp()
        case "select": space.selection = [argument]
        case "hover": space.hovered = argument
        case "check": if let item = find(argument) { space.setChecked(item, true) }
        case "uncheck": if let item = find(argument) { space.setChecked(item, false) }
        case "tray": space.showingTray = true
        case "untray": space.showingTray = false
        case "inspect": if let item = find(argument) { space.selection = [item.id]; space.inspect(item) }
        case "uninspect": space.inspected = nil
        case "confirm": model.confirmSpaceMove()
        case "move":
            if let plan = model.pendingSpaceMove {
                model.pendingSpaceMove = nil
                model.performSpaceMove(plan)
                for _ in 0..<50 where model.isMoving { try? await Task.sleep(for: .milliseconds(100)) }
            }
        case "undo": model.undo()
        case "startover": model.setStage(.intro, for: .spaceLens)
        case "fda": model.hasFullDiskAccess = argument == "on"
        case "sleep": try? await Task.sleep(for: .milliseconds(Int(argument) ?? 500))
        case "shot": shot(argument, dir: dir)
        case "state":
            let tray = space.tray
            log(dir, "\(argument) status=\(space.status) place=\(space.place == .folder("") ? "root" : "depth \(space.place.folderID.split(separator: "/").count)") items=\(space.items.count) total=\(space.total) tray=\(tray.count) up_to=\(tray.freeable) note=\(space.note == nil ? "none" : "yes") result=\(model.results[.spaceLens].map { "\($0.moved.count) moved, \($0.failures.count) failed, putback=\($0.isPutBack)" } ?? "none") pending=\(model.pendingSpaceMove != nil)")
        case "quit": NSApp.terminate(nil)
        default: log(dir, "unknown command \(command)")
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" } ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    /// Renders every visible window (the main window, then popovers, sheets and alerts).
    private static func shot(_ name: String, dir: URL) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 40 }
            .sorted { ($0 == mainWindow ? 0 : 1) < ($1 == mainWindow ? 0 : 1) }
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let file = dir.appendingPathComponent(index == 0 ? "\(name).png" : "\(name)-\(index + 1).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
