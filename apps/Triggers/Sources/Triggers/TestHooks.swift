import AppKit
import CoreGraphics
import TriggersCore
import TriggersTouchShim

/// Scripted-test entry points (`TRIGGERS_TEST_HOOKS=1`, `TRIGGERS_REPLAY`). See Diagnostics.
@MainActor
enum TestHooks {
    private static let prefix = "app.slopapp.triggers.test."

    /// Hooks: editor, settings <tab>, newTrigger, replay <path>, stats <path>, pause 1|0,
    /// allApps on|off (for the front app), record start|stop, tapSelfTest <count>.
    static func install(model: AppModel) {
        let center = DistributedNotificationCenter.default()
        func on(_ name: String, _ action: @escaping @MainActor (String?) -> Void) {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { note in
                let object = note.object as? String
                MainActor.assumeIsolated { action(object) }
            }
        }
        on("editor") { _ in EditorWindow.show() }
        on("settings") { tab in SettingsNavigation.open(tab ?? "general") }
        on("newTrigger") { _ in
            EditorWindow.show()
            model.beginNew()
        }
        on("replay") { path in
            guard let path else { return }
            replay(file: URL(fileURLWithPath: path), model: model)
        }
        on("stats") { path in
            let report = model.diagnosticsReport()
            Diagnostics.record("stats\n" + report)
            if let path { try? report.write(toFile: path, atomically: true, encoding: .utf8) }
        }
        on("pause") { value in model.isPaused = value != "0" }
        on("allApps") { value in
            guard let app = model.menuTargetApp, let id = app.bundleID else { return }
            model.setUsesAllAppsTriggers(value != "off", in: id, name: app.name, undo: nil)
            Diagnostics.record("all-apps triggers \(value ?? "on") in \(id)")
        }
        on("record") { value in
            if value == "stop" { model.stopRecording() } else { model.startRecording() }
            Diagnostics.record("recording \(value == "stop" ? "stopped" : "started")")
        }
        on("tapSelfTest") { count in tapSelfTest(count: Int(count ?? "") ?? 200, model: model) }
        Diagnostics.record("test hooks installed")
    }

    /// Feeds a timeline into the real recognizer and router, in-process. Touch frames go through
    /// a recognizer like the live source's; mouse presses through the tap's own decision with
    /// the live routes; key combos as if their hotkey fired. Nothing is posted anywhere.
    static func replay(file: URL, model: AppModel) {
        guard let data = try? Data(contentsOf: file), let timeline = try? ReplayTimeline.decode(data) else {
            Diagnostics.record("replay: couldn't read \(file.path)")
            return
        }
        Task { @MainActor in
            var decider = MouseTapDecider()
            let started = ProcessInfo.processInfo.systemUptime
            Diagnostics.record("replay start: \(timeline.steps.count) steps")
            for step in timeline.steps {
                if let after = step.after { try? await Task.sleep(for: .seconds(after)) }
                let frames = ReplayTimeline.frames(for: step, at: Diagnostics.now() + 0.005)
                if !frames.isEmpty {
                    // Through the same processor the MultitouchSupport callback feeds, on a
                    // background thread at the frames' own times, so CPU numbers mean something.
                    await TouchReplayer.play(frames, modifiers: Modifiers(rawValue: step.modifiers ?? 0))
                }
                let modifiers = Modifiers(rawValue: step.modifiers ?? 0)
                if let button = step.mouseButton {
                    if model.isRecording {
                        model.recorded(.mouseButton(button, modifiers: modifiers))
                    } else {
                        let routes = model.engine.table.mouseRoutes(frontApp: model.engine.frontApp?.bundleID)
                        let effective = model.isPaused ? MouseRoutes.empty : routes
                        let decision = decider.decide(phase: .down, button: button, modifiers: modifiers, routes: effective, isOwnEvent: false)
                        _ = decider.decide(phase: .up, button: button, modifiers: modifiers, routes: effective, isOwnEvent: false)
                        Diagnostics.record("replay button \(button) -> \(decision)")
                        if case .swallowAndFire(let id) = decision {
                            model.engine.receive(mouseBinding: id, trigger: .mouseButton(button, modifiers: modifiers))
                        }
                    }
                }
                if let keyCode = step.keyCode {
                    let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
                    // Only combos registered for the front app fire, as with real hotkeys.
                    if model.isRecording || model.engine.table.hotkeys(frontApp: model.engine.frontApp?.bundleID).contains(combo) {
                        model.engine.receive(.keyCombo(combo))
                    } else {
                        Diagnostics.record("replay key \(combo.fallbackDisplay) not registered here")
                    }
                }
            }
            let seconds = ProcessInfo.processInfo.systemUptime - started
            let stats = TouchProcessor.shared.stats()
            Diagnostics.record("replay done in \(String(format: "%.1f", seconds)) s")
            Diagnostics.perf("replay recognizer \(stats.cost.summary)")
            Diagnostics.perf("replay frame_interval \(stats.intervals.summary)")
            Diagnostics.perf("replay dispatch \(model.engine.dispatchLatency.summary)")
        }
    }

    /// Measures the real tap: posts presses of an unused button (21) at the pointer while a
    /// binding for it, scoped to the test target, swallows every one, so no app ever sees them.
    /// Refuses unless the test target is in front, the pointer is over its window and the owner
    /// has been idle a minute. Then reads `CGGetEventTapList` for our tap's latency.
    static func tapSelfTest(count: Int, model: AppModel) {
        guard let target = Diagnostics.actOnlyIn, model.frontApp?.bundleID == target, let pid = model.frontApp?.pid else {
            Diagnostics.record("tapSelfTest refused: test target isn't in front")
            return
        }
        guard idleSeconds() >= 60 else {
            Diagnostics.record("tapSelfTest refused: owner active")
            return
        }
        let pointer = CGEvent(source: nil)?.location ?? .zero
        guard windowOwner(at: pointer) == pid else {
            Diagnostics.record("tapSelfTest refused: pointer isn't over the test target's window")
            return
        }
        guard model.tap.isInstalled,
              model.engine.table.mouseRoutes(frontApp: target).binding(button: 21, modifiers: []) != nil else {
            Diagnostics.record("tapSelfTest refused: no installed tap with a button-22 binding in the test target")
            return
        }
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<count {
            for type in [CGEventType.otherMouseDown, .otherMouseUp] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: pointer, mouseButton: .center) else { continue }
                event.setIntegerValueField(.mouseEventButtonNumber, value: 21)
                event.post(tap: .cghidEventTap)
            }
            usleep(2000)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                Diagnostics.perf("tapSelfTest posted=\(count) callback \(model.tap.callbackLatency.summary)")
                Diagnostics.perf("tapSelfTest window_server \(EventTapStats.summary())")
            }
        }
    }

    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    private static func windowOwner(at point: CGPoint) -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(point) { return pid }
        }
        return nil
    }
}

/// Plays touch frames into `TouchProcessor` from a background thread, timed like real frames.
/// Gestures come out through the live source exactly as with fingers on a trackpad.
enum TouchReplayer {
    /// Modifiers for gestures from the current replay step (deterministic, not the live keyboard).
    nonisolated(unsafe) static var stepModifiers: Modifiers?

    static func play(_ frames: [TouchFrame], modifiers: Modifiers) async {
        stepModifiers = modifiers
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                let buffer = UnsafeMutablePointer<TRTouch>.allocate(capacity: 20)
                defer { buffer.deallocate() }
                for frame in frames {
                    let wait = frame.timestamp - Diagnostics.now()
                    if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
                    let count = min(frame.contacts.count, 20)
                    for index in 0..<count {
                        let contact = frame.contacts[index]
                        var touch = TRTouch()
                        touch.identifier = contact.id
                        touch.state = contact.state ?? 4
                        touch.normalized.position = TRTouchPoint(x: contact.x, y: contact.y)
                        touch.total = contact.size ?? 1
                        buffer[index] = touch
                    }
                    TouchProcessor.shared.handle(device: UnsafeMutableRawPointer(bitPattern: 0x7E57), touches: buffer,
                                                 count: count, timestamp: frame.timestamp)
                }
                continuation.resume()
            }
            thread.qualityOfService = .userInteractive
            thread.start()
        }
        // Let the last gesture reach the main thread before the next step.
        try? await Task.sleep(for: .milliseconds(20))
        stepModifiers = nil
    }
}
