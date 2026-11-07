import AppKit
import ApplicationServices
import os
import TriggersCore

/// Runs actions for real. The only production type that posts events (`CGEvent.post`), and
/// in test mode (`TRIGGERS_ACT_ONLY_IN`) it acts only on the test target: keys and clicks go
/// to that process with `postToPid`, menus and windows resolve only that app, and Open / Run
/// Shortcut just log what they'd do.
@MainActor
final class SystemPerformer: ActionPerformer {
    private let testTarget = Diagnostics.actOnlyIn
    private(set) var windowLatency = LatencyStats()
    private(set) var postLatency = LatencyStats()
    private static let signposter = OSSignposter(subsystem: "app.slopapp.triggers", category: "actions")

    func perform(_ action: Action, context: ActionContext) -> ActionResult {
        if let testTarget {
            guard context.frontApp?.bundleID == testTarget, let pid = context.frontApp?.pid else {
                Diagnostics.record("skipped \(action.fallbackTitle): \(context.frontApp?.bundleID ?? "no app") isn't the test target")
                return .skipped("Test mode acts only in the test target.")
            }
            return run(action, context: context, testPID: pid)
        }
        return run(action, context: context, testPID: nil)
    }

    private func run(_ action: Action, context: ActionContext, testPID: pid_t?) -> ActionResult {
        if action.needsAccessibility, !AccessibilityTrust.isTrusted {
            return .failed("Triggers needs Accessibility access to do this. Turn it on in System Settings › Privacy & Security › Accessibility.")
        }
        let start = Diagnostics.now()
        let result: ActionResult
        switch action {
        case .pressKeys(let combo):
            result = KeyPoster.press(combo, held: context.trigger.modifiers, pid: testPID)
            postLatency.record(seconds: Diagnostics.now() - start)
        case .click(let kind):
            result = Clicker.click(kind, pid: testPID)
            postLatency.record(seconds: Diagnostics.now() - start)
        case .menuItem(let path):
            guard let pid = context.frontApp?.pid else { return .skipped("No app is in front.") }
            result = MenuInvoker.choose(path, pid: pid, appName: context.frontApp?.name ?? "the app")
        case .window(let move):
            guard let pid = context.frontApp?.pid else { return .skipped("No app is in front.") }
            let signpost = Self.signposter.beginInterval("window")
            result = WindowMover.move(move, pid: pid)
            Self.signposter.endInterval("window", signpost)
            windowLatency.record(seconds: Diagnostics.now() - start)
        case .open(let target):
            result = Diagnostics.fakesOutsideEffects ? fake("open \(target)") : Opener.open(target)
        case .runShortcut(let name):
            result = Diagnostics.fakesOutsideEffects ? fake("run shortcut \(name)") : ShortcutRunner.run(name)
        case .passThrough:
            result = .done
        }
        Diagnostics.record("performed \(action.fallbackTitle) in \(context.frontApp?.bundleID ?? "-") -> \(result) in \(String(format: "%.2f", (Diagnostics.now() - start) * 1000)) ms")
        return result
    }

    private func fake(_ what: String) -> ActionResult {
        Diagnostics.record("test mode: would \(what)")
        return .done
    }
}

enum AccessibilityTrust {
    @MainActor static var isTrusted: Bool { Diagnostics.assumeTrusted ?? AXIsProcessTrusted() }
}

/// Posts key combos (`KeyPostPlan`): modifiers pressed and released around the key, so the
/// system's modifier state ends where it started; what the person holds is put back.
@MainActor
enum KeyPoster {
    /// Made once; `warmUp()` at launch.
    private static let source = CGEventSource(stateID: .privateState)

    /// The first event created in a process costs ~40 ms and the first post ~8 ms (measured on
    /// macOS 27.2); later ones take microseconds. Pay that once at launch, not on the first
    /// trigger: create an event and post a no-op flags change to Triggers itself.
    static func warmUp() {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        event.type = .flagsChanged
        event.flags = []
        event.postToPid(getpid())
    }

    static func press(_ combo: KeyCombo, held: Modifiers, pid: pid_t?) -> ActionResult {
        for planned in KeyPostPlan.events(for: combo, held: held) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(planned.keyCode),
                                      keyDown: planned.kind != .keyUp) else {
                return .failed("Couldn't press \(KeyDisplay.name(combo)).")
            }
            if planned.kind == .flagsChanged { event.type = .flagsChanged }
            event.flags = CGEventFlags(rawValue: planned.flags)
            event.setIntegerValueField(.eventSourceUserData, value: MouseTapDecider.ownEventMarker)
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
        return .done
    }
}

/// Clicks at the pointer.
@MainActor
enum Clicker {
    private static let source = CGEventSource(stateID: .privateState)

    static func click(_ kind: ClickKind, pid: pid_t?) -> ActionResult {
        let location = CGEvent(source: nil)?.location ?? .zero
        let (down, up, button, flags): (CGEventType, CGEventType, CGMouseButton, CGEventFlags) = switch kind {
        case .middle: (.otherMouseDown, .otherMouseUp, .center, [])
        case .right: (.rightMouseDown, .rightMouseUp, .right, [])
        case .commandClick: (.leftMouseDown, .leftMouseUp, .left, .maskCommand)
        }
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
                return .failed("Couldn't click.")
            }
            event.flags = flags
            if kind == .middle { event.setIntegerValueField(.mouseEventButtonNumber, value: 2) }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            // Marked, so our own tap lets it through even if the middle button is bound.
            event.setIntegerValueField(.eventSourceUserData, value: MouseTapDecider.ownEventMarker)
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
        return .done
    }
}

/// A menu in an app's menu bar, read through Accessibility (for the menu item picker).
struct MenuNode: Identifiable, Hashable, Sendable {
    var title: String
    var children: [MenuNode]
    var id: String { title + "/" + children.map(\.title).joined(separator: "|") }
}

/// Chooses menu items by title path, and reads menus for the picker.
enum MenuInvoker {
    static func choose(_ path: [String], pid: pid_t, appName: String) -> ActionResult {
        let readable = path.joined(separator: " › ")
        guard !path.isEmpty, let menuBar = element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else {
            return .failed("Couldn't read \(appName)'s menus.")
        }
        var current = menuBar
        for (index, title) in path.enumerated() {
            let items = index == 0 ? children(current) : children(children(current).first ?? current)
            guard let item = items.first(where: { matches(string($0, kAXTitleAttribute), title) }) else {
                return .failed("Couldn't find \(readable) in \(appName).")
            }
            current = item
        }
        if let enabled = bool(current, kAXEnabledAttribute), !enabled {
            return .failed("\(readable) is turned off in \(appName) right now.")
        }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
            ? .done : .failed("Couldn't choose \(readable) in \(appName).")
    }

    /// The app's menus, two levels below the menu bar (Apple menu left out).
    nonisolated static func read(pid: pid_t, depth: Int = 3) -> [MenuNode] {
        guard let menuBar = element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return [] }
        return children(menuBar).dropFirst().compactMap { node($0, depth: depth) }
    }

    private nonisolated static func node(_ item: AXUIElement, depth: Int) -> MenuNode? {
        guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { return nil }
        guard depth > 1, let menu = children(item).first else { return MenuNode(title: title, children: []) }
        return MenuNode(title: title, children: children(menu).compactMap { node($0, depth: depth - 1) })
    }

    /// Titles match ignoring case and "…" versus "...".
    static func matches(_ actual: String?, _ wanted: String) -> Bool {
        guard let actual else { return false }
        func normal(_ text: String) -> String {
            text.replacingOccurrences(of: "...", with: "…").trimmingCharacters(in: .whitespaces).lowercased()
        }
        return normal(actual) == normal(wanted)
    }

    nonisolated static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}

/// Moves the front app's focused window with Accessibility, using `WindowLayout`'s math.
enum WindowMover {
    @MainActor
    static func move(_ move: WindowMove, pid: pid_t) -> ActionResult {
        let app = AXUIElementCreateApplication(pid)
        guard let window = MenuInvoker.element(app, kAXFocusedWindowAttribute),
              MenuInvoker.string(window, kAXRoleAttribute) == kAXWindowRole as String else {
            return .skipped("No window to move.")
        }
        if MenuInvoker.bool(window, "AXFullScreen") == true { return .skipped("The window is full screen.") }
        if move == .minimize {
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
                ? .done : .failed("Couldn't minimize the window.")
        }
        guard let frame = frame(of: window) else { return .failed("Couldn't read the window's position.") }
        let screens = NSScreen.screens
        guard let primary = screens.first else { return .skipped("No display.") }
        let height = primary.frame.height
        let visibles = screens.map { WindowLayout.flip($0.visibleFrame, primaryHeight: height) }
        let frames = screens.map { WindowLayout.flip($0.frame, primaryHeight: height) }
        guard let index = WindowLayout.screenIndex(for: frame, in: frames) else { return .skipped("No display.") }
        var nextVisible: CGRect?
        var targetVisible = visibles[index]
        if move == .nextDisplay {
            let order = WindowLayout.ordered(frames)
            guard let position = order.firstIndex(of: index), let next = WindowLayout.nextIndex(after: position, count: order.count) else {
                return .skipped("There's only one display.")
            }
            nextVisible = visibles[order[next]]
            targetVisible = visibles[order[next]]
        }
        guard let target = WindowLayout.target(for: move, window: frame, visible: visibles[index], nextVisible: nextVisible) else {
            return .skipped("Nothing to do.")
        }
        // Position, size, position again: moving to another display can clip the size first.
        set(window, position: target.origin)
        set(window, size: target.size)
        set(window, position: target.origin)
        if let actual = self.frame(of: window), actual.size != target.size {
            let settled = WindowLayout.settle(actual: actual.size, target: target, move: move, visible: targetVisible)
            if settled.origin != actual.origin { set(window, position: settled.origin) }
        }
        return .done
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func set(_ window: AXUIElement, position: CGPoint) {
        var point = position
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    private static func set(_ window: AXUIElement, size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    }
}

/// Opens apps, links and files.
enum Opener {
    @MainActor
    static func open(_ target: OpenTarget) -> ActionResult {
        switch target {
        case .app(let bundleID, let name):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return .failed("Couldn't find \(name). It may have been moved or deleted.")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .done
        case .url(let text):
            guard OpenURLCheck.isOpenable(text), let url = URL(string: text.trimmingCharacters(in: .whitespaces)) else {
                return .failed("“\(text)” isn't a link Triggers can open.")
            }
            return NSWorkspace.shared.open(url) ? .done : .failed("No app could open \(text).")
        case .file(let path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                return .failed("Couldn't find \(url.lastPathComponent). It may have been moved or deleted.")
            }
            return NSWorkspace.shared.open(url) ? .done : .failed("Couldn't open \(url.lastPathComponent).")
        }
    }
}

/// Runs Shortcuts with the `shortcuts` command-line tool, off the main thread.
enum ShortcutRunner {
    @MainActor
    static func run(_ name: String) -> ActionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Diagnostics.record("shortcut exited \(status)")
                    NotificationCenter.default.post(name: .actionFailed, object: "Couldn't run the Shortcut “\(name)”. Check it still exists in the Shortcuts app.")
                }
            }
        }
        do {
            try process.run()
            return .done
        } catch {
            return .failed("Couldn't start Shortcuts.")
        }
    }

    /// Every Shortcut's name (`shortcuts list`), or the made-up list in test mode.
    static func list() async -> [String] {
        if Diagnostics.fakeApps { return FakeCatalog.shortcuts }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["list"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                    continuation.resume(returning: names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

extension Notification.Name {
    static let actionFailed = Notification.Name("app.slopapp.triggers.actionFailed")
}
