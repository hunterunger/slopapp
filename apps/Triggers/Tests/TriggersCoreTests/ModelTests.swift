import CoreGraphics
import Foundation
import Testing
@testable import TriggersCore

@Suite struct ConflictTests {
    private func settings(_ values: [String: Int], dock: [String: Int] = [:]) -> SystemGestureSettings {
        SystemGestureSettings { key, domain in
            domain == SystemGestureSettings.dockDomain ? dock[key] : values[key]
        }
    }

    @Test func readsTheOwnersKindOfSetup() {
        // The macOS 27 defaults as found on the test Mac (read-only).
        let system = settings([
            "TrackpadThreeFingerDrag": 0, "TrackpadThreeFingerTapGesture": 0,
            "TrackpadThreeFingerHorizSwipeGesture": 2, "TrackpadFourFingerHorizSwipeGesture": 2,
            "TrackpadThreeFingerVertSwipeGesture": 2, "TrackpadFourFingerVertSwipeGesture": 2,
        ], dock: ["showMissionControlGestureEnabled": 1, "showAppExposeGestureEnabled": 0])
        #expect(system.systemUse(of: .tap(3)) == nil)
        #expect(system.systemUse(of: .tap(4)) == nil)
        #expect(system.systemUse(of: .swipe(3, .left)) == .fullScreenApps)
        #expect(system.systemUse(of: .swipe(4, .right)) == .fullScreenApps)
        #expect(system.systemUse(of: .swipe(3, .up)) == .missionControl)
        #expect(system.systemUse(of: .swipe(4, .down)) == nil, "App Exposé is off")
    }

    @Test func lookUpAndThreeFingerDrag() {
        #expect(settings(["TrackpadThreeFingerTapGesture": 2]).systemUse(of: .tap(3)) == .lookUp)
        let drag = settings(["TrackpadThreeFingerDrag": 1])
        #expect(drag.systemUse(of: .swipe(3, .down)) == .threeFingerDrag)
        #expect(drag.systemUse(of: .tap(3)) == .threeFingerDrag)
        #expect(drag.systemUse(of: .tap(4)) == nil)
        #expect(SystemGestureUse.threeFingerDrag.settingsPane == .pointerControl)
    }

    @Test func pagesSwipe() {
        #expect(settings(["TrackpadThreeFingerHorizSwipeGesture": 1]).systemUse(of: .swipe(3, .right)) == .pages)
        #expect(settings(["TrackpadThreeFingerHorizSwipeGesture": 0, "TrackpadFourFingerHorizSwipeGesture": 0]).systemUse(of: .swipe(4, .left)) == nil)
    }

    @Test func eitherTrackpadDomainCounts() {
        let system = SystemGestureSettings { key, domain in
            if key == "TrackpadThreeFingerTapGesture" { return domain.contains("Bluetooth") ? 2 : 0 }
            return nil
        }
        #expect(system.systemUse(of: .tap(3)) == .lookUp)
    }

    @Test func duplicatesAndOverrides() {
        let tap = Trigger.gesture(.tap(3), modifiers: [])
        let all = TriggerBinding(trigger: tap, action: .click(.middle), scope: .allApps)
        let dup = TriggerBinding(trigger: tap, action: .click(.right), scope: .allApps)
        let safariOwn = TriggerBinding(trigger: tap, action: .window(.center), scope: .app(bundleID: "com.apple.Safari"))
        let config = Config(bindings: [all, dup, safariOwn])
        let checker = ConflictChecker()
        #expect(checker.conflicts(for: dup, in: config) == [.duplicate(all)])
        #expect(checker.conflicts(for: safariOwn, in: config) == [.overrides(all)])
        #expect(!Conflict.overrides(all).isWarning)
        // A disabled twin isn't a duplicate.
        var off = dup
        off.isEnabled = false
        #expect(checker.conflicts(for: all, in: Config(bindings: [all, off])).isEmpty)
    }

    @Test func browserAppPrefersTheBrowsersGroupAsWhatItOverrides() {
        let tap = Trigger.gesture(.tap(4), modifiers: [])
        let group = TriggerBinding(trigger: tap, action: .click(.middle), scope: .browsers)
        let all = TriggerBinding(trigger: tap, action: .click(.right), scope: .allApps)
        let own = TriggerBinding(trigger: tap, action: .window(.center), scope: .app(bundleID: "com.apple.Safari"))
        #expect(ConflictChecker().conflicts(for: own, in: Config(bindings: [all, group, own])) == [.overrides(group)])
    }

    @Test func keyComboConflicts() {
        let space = KeyCombo(keyCode: 49, modifiers: .command)
        let checker = ConflictChecker(systemShortcuts: [space], unavailableShortcuts: [ctrlOptK])
        let spotlight = TriggerBinding(trigger: .keyCombo(space), action: .window(.center), scope: .allApps)
        let taken = TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .pressKeys(ctrlOptK), scope: .allApps)
        #expect(checker.conflicts(for: spotlight, in: Config()) == [.systemShortcut])
        #expect(checker.conflicts(for: taken, in: Config()) == [.shortcutTaken, .pressesItself])
    }
}

@Suite struct StoreTests {
    @Test func roundTrip() throws {
        var config = Config(bindings: [
            TriggerBinding(trigger: .gesture(.swipe(4, .up), modifiers: [.command]), action: .window(.maximize), scope: .allApps),
            TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .pressKeys(cmdLeftBracket), scope: .browsers),
            TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .open(.app(bundleID: "com.apple.Notes", name: "Notes")),
                    scope: .app(bundleID: "com.apple.Safari"), isEnabled: false),
            TriggerBinding(trigger: .keyCombo(KeyCombo(keyCode: 122, modifiers: [])), action: .menuItem(["File", "Export…"]), scope: .allApps),
            TriggerBinding(trigger: .gesture(.tap(4), modifiers: []), action: .runShortcut("Log Water"), scope: .allApps),
            TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .passThrough, scope: .app(bundleID: "com.apple.Notes")),
        ])
        config.addApp(bundleID: "com.apple.Safari", name: "Safari")
        config.setUsesAllAppsTriggers(false, in: "com.example.game", name: "Game")
        let decoded = try ConfigCodec.decode(ConfigCodec.encode(config))
        #expect(decoded == config)
    }

    @Test func newerFileIsRefusedNotOverwritten() {
        let data = Data(#"{"schemaVersion": 9, "bindings": [], "apps": []}"#.utf8)
        #expect(throws: ConfigCodec.Failure.newerVersion(9)) { try ConfigCodec.decode(data) }
    }

    @Test func damagedFile() {
        #expect(throws: ConfigCodec.Failure.self) { try ConfigCodec.decode(Data("nope".utf8)) }
        #expect(throws: ConfigCodec.Failure.self) { try ConfigCodec.decode(Data(#"{"schemaVersion": 1, "bindings": 3}"#.utf8)) }
    }

    @Test func fileStorage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("triggers-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileConfigStorage(url: dir.appendingPathComponent("nested/triggers.json"))
        #expect(try storage.load() == nil)
        try storage.save(Data("x".utf8))
        #expect(try storage.load() == Data("x".utf8))
    }

    @Test func importMergesWithoutDuplicates() {
        let existing = TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps)
        let newOne = TriggerBinding(trigger: .mouseButton(2, modifiers: []), action: .window(.center), scope: .app(bundleID: "com.apple.Notes"))
        let imported = Config(bindings: [existing, newOne], apps: [AppEntry(bundleID: "com.apple.Notes", name: "Notes")])
        let (merged, added) = ConfigCodec.merge(imported, into: Config(bindings: [existing]))
        #expect(added == 1)
        #expect(merged.bindings.count == 2)
        #expect(merged.bindings[1].id != newOne.id, "imported bindings get new ids")
        #expect(merged.app("com.apple.Notes") != nil)
    }
}

@Suite struct ModelTests {
    @Test func startersAddOnceAndNeedNothingOnByDefault() {
        var config = Config()
        #expect(config.bindings.isEmpty, "starts empty")
        let mouse = Starter.all.first { $0.id == "mouse-back-forward" }!
        #expect(!mouse.isApplied(in: config))
        let added = mouse.apply(to: &config)
        #expect(added.count == 4)
        #expect(config.app("com.apple.finder") != nil)
        #expect(mouse.isApplied(in: config))
        #expect(mouse.apply(to: &config).isEmpty, "a second click adds nothing")
        let table = RoutingTable(config: config)
        #expect(table.resolve(.mouseButton(3, modifiers: []), frontApp: "com.apple.Safari").binding?.action == .pressKeys(cmdLeftBracket))
        #expect(table.resolve(.mouseButton(3, modifiers: []), frontApp: "com.apple.finder").binding != nil)
        #expect(table.resolve(.mouseButton(3, modifiers: []), frontApp: "com.apple.Notes") == .none)
    }

    @Test func swipeStarterGoesBackWithFingersMovingRight() {
        var config = Config()
        _ = Starter.all.first { $0.id == "swipe-back-forward" }!.apply(to: &config)
        let table = RoutingTable(config: config)
        #expect(table.resolve(.gesture(.swipe(4, .right), modifiers: []), frontApp: "com.apple.Safari").binding?.action == .pressKeys(cmdLeftBracket))
    }

    @Test func recentKeepsTheLastTwenty() {
        var log = RecentLog()
        let binding = TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps)
        for index in 0..<25 { log.record(binding, appName: "App \(index)", date: Date(timeIntervalSince1970: Double(index))) }
        #expect(log.entries.count == 20)
        #expect(log.entries.first?.appName == "App 24")
        #expect(RelativeAge.describe(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 2)) == "2 s ago")
        #expect(RelativeAge.describe(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 300)) == "5 min ago")
    }

    @Test func modifiers() {
        let flags: UInt64 = CGEventFlags([.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn]).rawValue
        #expect(Modifiers(cgFlags: flags) == [.command, .shift])
        #expect(Modifiers([.control, .option, .shift, .command]).symbols == "⌃⌥⇧⌘")
        #expect(Modifiers(cgFlags: Modifiers.all.cgFlags) == .all)
        #expect(Modifiers([.command, .option]).carbonFlags == (1 << 8 | 1 << 11))
        #expect(Modifiers([.control, .shift]).spokenNames == "Control-Shift")
    }

    @Test func comboUsability() {
        #expect(KeyCombo(keyCode: 40, modifiers: .command).isUsableAsTrigger)
        #expect(!KeyCombo(keyCode: 40, modifiers: .shift).isUsableAsTrigger, "Shift-K is typing")
        #expect(!KeyCombo(keyCode: 40, modifiers: []).isUsableAsTrigger)
        #expect(KeyCombo(keyCode: 122, modifiers: []).isUsableAsTrigger, "F1 alone is fine")
        #expect(ctrlOptK.fallbackDisplay == "⌃⌥K")
    }

    @Test func titles() {
        #expect(Trigger.gesture(.tap(3), modifiers: []).fallbackTitle == "Three-finger tap")
        #expect(Trigger.gesture(.swipe(4, .left), modifiers: .option).fallbackTitle == "⌥ Four-finger swipe left")
        #expect(Trigger.mouseButton(3, modifiers: []).fallbackTitle == "Button 4 (back)")
        #expect(Trigger.mouseButton(7, modifiers: []).fallbackTitle == "Button 8")
        #expect(Action.pressKeys(cmdLeftBracket).fallbackTitle == "Press ⌘[")
        #expect(Action.menuItem(["File", "Export…"]).fallbackTitle == "File › Export…")
        #expect(Gesture.supported.count == 10)
    }

    @Test func actionsNeedingAccessibility() {
        #expect(Action.pressKeys(cmdLeftBracket).needsAccessibility)
        #expect(Action.window(.leftHalf).needsAccessibility)
        #expect(!Action.open(.url("https://example.com")).needsAccessibility)
        #expect(!Action.runShortcut("X").needsAccessibility)
    }

    @Test func completeness() {
        #expect(!Action.menuItem([]).isComplete)
        #expect(!Action.menuItem(["File", " "]).isComplete)
        #expect(Action.open(.url("https://example.com")).isComplete)
        #expect(!Action.open(.url("example")).isComplete)
        #expect(!Action.open(.url("javascript:alert(1)")).isComplete)
        #expect(!Action.open(.url("file:///etc/hosts")).isComplete)
        #expect(Action.open(.url("things:///add")).isComplete)
        #expect(!Action.runShortcut("").isComplete)
    }

    @Test func actionKindDefaultsKeepCurrent() {
        let current = Action.pressKeys(ctrlOptK)
        #expect(ActionKind.pressKeys.defaultAction(from: current) == current)
        #expect(ActionKind.middleClick.defaultAction(from: current) == .click(.middle))
        #expect(current.kind == .pressKeys)
        #expect(Action.window(.nextDisplay).kind == .window(.nextDisplay))
    }

    @Test func keyPostPlanUsesExactlyTheCombosModifiers() {
        let events = KeyPostPlan.events(for: cmdLeftBracket)
        let keys = events.filter { $0.kind != .flagsChanged }
        #expect(keys.map(\.kind) == [.keyDown, .keyUp])
        #expect(keys.allSatisfy { Modifiers(cgFlags: $0.flags) == .command })
        // ⌘ goes down before the key and up after it: nothing is left held.
        #expect(events.first == .init(kind: .flagsChanged, keyCode: 55, flags: Modifiers.command.cgFlags))
        #expect(events.last == .init(kind: .flagsChanged, keyCode: 55, flags: 0))
        #expect(KeyPostPlan.finalModifiers(events) == [])
    }

    @Test func keyPostPlanReleasesAndRestoresHeldModifiers() {
        // The trigger was ⌥ + a mouse button; the person still holds ⌥ while ⌃⇧K is pressed.
        let combo = KeyCombo(keyCode: 40, modifiers: [.control, .shift])
        let events = KeyPostPlan.events(for: combo, held: .option)
        let key = events.first { $0.kind == .keyDown }!
        #expect(Modifiers(cgFlags: key.flags) == [.control, .shift], "⌥ doesn't leak into the combo")
        #expect(events.first == .init(kind: .flagsChanged, keyCode: 58, flags: 0), "⌥ let go first")
        #expect(KeyPostPlan.finalModifiers(events) == .option, "and put back at the end")
        // Modifier events go control, option, shift, command down; reverse up.
        let downs = events.drop { $0.kind == .flagsChanged && $0.flags == 0 }.prefix { $0.kind == .flagsChanged }.map(\.keyCode)
        #expect(downs == [59, 56])
    }

    @Test func keyPostPlanWithoutModifiers() {
        let escape = KeyCombo(keyCode: KeyNames.escape, modifiers: [])
        #expect(KeyPostPlan.events(for: escape).map(\.kind) == [.keyDown, .keyUp])
    }

    @Test func replayDecodes() throws {
        let json = #"""
        {"steps": [{"tap": 3}, {"after": 0.2, "swipe": {"fingers": 4, "direction": "left"}},
                   {"after": 0.1, "mouseButton": 3}, {"keyCode": 40, "modifiers": 3}, {"scrollSeconds": 1}]}
        """#
        let timeline = try ReplayTimeline.decode(Data(json.utf8))
        #expect(timeline.steps.count == 5)
        #expect(ReplayTimeline.frames(for: timeline.steps[0], at: 5).first?.timestamp == 5)
        #expect(!ReplayTimeline.frames(for: timeline.steps[1], at: 0).isEmpty)
        #expect(ReplayTimeline.frames(for: timeline.steps[2], at: 0).isEmpty)
    }

    @Test func urlCheck() {
        #expect(OpenURLCheck.isOpenable("https://example.com/a?b"))
        #expect(!OpenURLCheck.isOpenable("https://"))
        #expect(!OpenURLCheck.isOpenable(""))
        #expect(!OpenURLCheck.isOpenable("data:text/html,hi"))
    }

    @Test func latencyStats() {
        var stats = LatencyStats()
        for _ in 0..<99 { stats.record(microseconds: 3) }
        stats.record(microseconds: 700)
        #expect(stats.count == 100)
        #expect(stats.percentile(0.5) == 5)
        #expect(stats.percentile(0.99) == 5)
        #expect(stats.percentile(1) == 1_000)
        #expect(stats.maxMicroseconds == 700)
    }
}

@Suite struct WindowLayoutTests {
    // A 1512×982 laptop screen with a 33 pt menu bar, AX coordinates (top-left origin).
    let visible = CGRect(x: 0, y: 33, width: 1512, height: 949)
    let window = CGRect(x: 100, y: 120, width: 800, height: 600)

    @Test func halves() {
        #expect(WindowLayout.target(for: .leftHalf, window: window, visible: visible) == CGRect(x: 0, y: 33, width: 756, height: 949))
        #expect(WindowLayout.target(for: .rightHalf, window: window, visible: visible) == CGRect(x: 756, y: 33, width: 756, height: 949))
        #expect(WindowLayout.target(for: .topHalf, window: window, visible: visible) == CGRect(x: 0, y: 33, width: 1512, height: 474))
        #expect(WindowLayout.target(for: .bottomHalf, window: window, visible: visible) == CGRect(x: 0, y: 507, width: 1512, height: 475))
    }

    @Test func oddWidthsLeaveNoGap() {
        let odd = CGRect(x: 0, y: 25, width: 1441, height: 875)
        let left = WindowLayout.target(for: .leftHalf, window: window, visible: odd)!
        let right = WindowLayout.target(for: .rightHalf, window: window, visible: odd)!
        #expect(left.maxX == right.minX)
        #expect(right.maxX == odd.maxX)
    }

    @Test func maximizeCenterMinimize() {
        #expect(WindowLayout.target(for: .maximize, window: window, visible: visible) == visible)
        let centered = WindowLayout.target(for: .center, window: window, visible: visible)!
        #expect(centered.size == window.size)
        #expect(abs(centered.midX - visible.midX) <= 1 && abs(centered.midY - visible.midY) <= 1)
        #expect(WindowLayout.target(for: .minimize, window: window, visible: visible) == nil)
        // A window bigger than the screen is shrunk to fit when centred.
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(WindowLayout.target(for: .center, window: huge, visible: visible)?.size == visible.size)
    }

    @Test func nextDisplay() {
        let external = CGRect(x: 1512, y: -300, width: 2560, height: 1415)
        let moved = WindowLayout.target(for: .nextDisplay, window: window, visible: visible, nextVisible: external)!
        #expect(external.contains(moved))
        #expect(moved.width > window.width, "scaled with the bigger screen")
        // A maximized window stays maximized.
        #expect(WindowLayout.target(for: .nextDisplay, window: visible, visible: visible, nextVisible: external) == external)
        // One screen: nothing to do.
        #expect(WindowLayout.target(for: .nextDisplay, window: window, visible: visible, nextVisible: nil) == nil)
    }

    @Test func flipAndScreenPicking() {
        // A second display above the primary (AppKit y = 982).
        let above = WindowLayout.flip(CGRect(x: 0, y: 982, width: 1920, height: 1080), primaryHeight: 982)
        #expect(above == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), above]
        #expect(WindowLayout.screenIndex(for: CGRect(x: 100, y: -500, width: 400, height: 300), in: screens) == 1)
        #expect(WindowLayout.screenIndex(for: CGRect(x: 100, y: 100, width: 400, height: 300), in: screens) == 0)
        #expect(WindowLayout.screenIndex(for: CGRect(x: -500, y: 500, width: 10, height: 10), in: screens) == 0, "off-screen: nearest")
        #expect(WindowLayout.nextIndex(after: 1, count: 2) == 0)
        #expect(WindowLayout.nextIndex(after: 0, count: 1) == nil)
        #expect(WindowLayout.ordered([CGRect(x: 1512, y: 0, width: 10, height: 10), CGRect(x: 0, y: 0, width: 10, height: 10)]) == [1, 0])
    }

    @Test func minimumSizeKeepsTheRightEdge() {
        let target = WindowLayout.target(for: .rightHalf, window: window, visible: visible)!
        let settled = WindowLayout.settle(actual: CGSize(width: 900, height: 949), target: target, move: .rightHalf, visible: visible)
        #expect(settled.maxX == visible.maxX)
        let left = WindowLayout.settle(actual: CGSize(width: 900, height: 949), target: WindowLayout.target(for: .leftHalf, window: window, visible: visible)!,
                                       move: .leftHalf, visible: visible)
        #expect(left.minX == visible.minX)
    }
}

@Suite struct BenchmarkTests {
    /// Budget: p99 ≤ 20 µs per frame on Apple silicon, no allocation. The assertion is loose
    /// (×10, debug builds on a busy machine); the tight number is printed.
    @Test func recognizerFrameCost() {
        var frames: [TouchFrame] = []
        var time = 0.0
        while frames.count < 100_000 {
            let chunk = SyntheticTouches.scroll(seconds: 0.5, at: time) + SyntheticTouches.tap(fingers: 3, at: time + 0.6)
                + SyntheticTouches.swipe(fingers: 4, direction: .left, at: time + 1)
            frames += chunk
            time += 1.5
        }
        let contacts = frames.map(\.touches)
        var recognizer = GestureRecognizer()
        var stats = LatencyStats()
        var gestures = 0
        let clock = ContinuousClock()
        for (frame, touches) in zip(frames, contacts) {
            let start = clock.now
            if recognizer.process(device: 1, timestamp: frame.timestamp, contacts: touches).gesture != nil { gestures += 1 }
            let elapsed = clock.now - start
            stats.record(seconds: Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds))
        }
        print("recognizer \(frames.count) frames: \(stats.summary) gestures=\(gestures)")
        #expect(gestures > 0)
        #expect(stats.percentile(0.99) <= 200)
    }
}
