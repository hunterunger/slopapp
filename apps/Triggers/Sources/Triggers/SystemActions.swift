import AppKit
import SlopKit
import TriggersCore

/// Media and hardware keys, posted as the keyboard's special keys (system-defined events,
/// subtype 8), so macOS handles them exactly like the keys on the keyboard: the Now Playing app
/// plays or pauses, and the volume and brightness overlays show. Needs Accessibility.
@MainActor
enum MediaKeys {
    static func press(_ key: MediaKey) -> ActionResult {
        for down in [true, false] {
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                                 timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                                 data1: key.data1(down: down), data2: -1),
                  let cgEvent = event.cgEvent else { return .failed("Couldn't press \(key.title).") }
            cgEvent.setIntegerValueField(.eventSourceUserData, value: MouseTapDecider.ownEventMarker)
            cgEvent.post(tap: .cghidEventTap)
        }
        return .done
    }
}

/// Things the Mac does with no app involved, through the same public routes as the Dock and
/// the keyboard: the Mission Control app (its argument picks Show Desktop or App Exposé),
/// `pmset`, the lock-screen shortcut, the screen saver app, and System Events for dark mode.
@MainActor
enum SystemActions {
    static let missionControl = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"

    static func run(_ action: SystemAction) -> ActionResult {
        switch action {
        case .missionControl: return launch(missionControl, [])
        case .showDesktop: return launch(missionControl, ["1"])
        case .appExpose: return launch(missionControl, ["2"])
        case .launchpad:
            let candidates = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                return .failed("Couldn't find \(action.title) on this Mac.")
            }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            return .done
        case .sleepDisplay: return launch("/usr/bin/pmset", ["displaysleepnow"])
        case .lockScreen:
            // The Apple menu's Lock Screen (⌃⌘Q), which macOS reserves for it.
            return KeyPoster.press(KeyCombo(keyCode: 12, modifiers: [.control, .command]), held: [], pid: nil)
        case .screenSaver:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
            return .done
        case .toggleDarkMode:
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            return ScriptRunner.run(.appleScript, script) { result in
                if case .failed = result {
                    HUD.show("Couldn't switch dark mode. Allow Triggers to control System Events in System Settings › Privacy & Security › Automation.",
                             systemImage: "exclamationmark.triangle", duration: .seconds(4))
                }
            } ?? .done
        }
    }

    private static func launch(_ path: String, _ arguments: [String]) -> ActionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return .done
        } catch {
            return .failed("Couldn't start \((path as NSString).lastPathComponent).")
        }
    }
}

/// Runs shell scripts (`zsh -l`, so the person's PATH applies) and AppleScripts (`osascript`)
/// in their own process, never on the main thread. Output is discarded; a failure names the
/// script's first error line.
@MainActor
enum ScriptRunner {
    static func run(_ language: ScriptLanguage, _ source: String, finished: @escaping @MainActor (ActionResult) -> Void) -> ActionResult? {
        let process = Process()
        switch language {
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", source]
        case .appleScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
        }
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { done in
            let status = done.terminationStatus
            let text = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
            let line = text.split(separator: "\n").first.map { String($0.prefix(120)) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Diagnostics.record("\(language.rawValue) script exited \(status)")
                    if status == 0 {
                        finished(.done)
                    } else {
                        let detail = line.map { " (\($0))" } ?? ""
                        finished(.failed("The \(language == .shell ? "shell script" : "AppleScript") stopped with an error\(detail)."))
                    }
                }
            }
        }
        do {
            try process.run()
            return nil
        } catch {
            return .failed("Couldn't start the \(language == .shell ? "shell script" : "AppleScript").")
        }
    }
}

/// Types text into the front app as keystrokes (SlopKit's `SyntheticKeyboard`; the clipboard is
/// never touched). Marked as Triggers' own, so key sequences and the hyper key ignore it.
@MainActor
enum Typer {
    static func type(_ text: String, pid: pid_t?, finished: @escaping @MainActor (ActionResult) -> Void) -> ActionResult? {
        let keyboard = SyntheticKeyboard(destination: pid.map { .process($0) } ?? .hidEventTap, marker: MouseTapDecider.ownEventMarker)
        Task { @MainActor in
            await keyboard.type(text, interval: .milliseconds(2))
            Diagnostics.record("typed \(text.count) characters")
            finished(.done)
        }
        return nil
    }
}
