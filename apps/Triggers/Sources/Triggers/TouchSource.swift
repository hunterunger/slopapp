import AppKit
import IOKit
import os
import TriggersCore
import TriggersTouchShim

/// Trackpad touches from MultitouchSupport.framework (private; no public API reads global
/// multi-finger touches). Loaded at runtime with `dlopen`, never linked, so a missing or
/// changed framework means "gestures unavailable" instead of a crash. The only file that
/// knows the framework exists. See docs/research/triggers.md, "Trackpad gestures".
@MainActor
final class MultitouchSource: TouchFrameSource {
    private(set) var unavailableReason: String?
    var onGesture: ((Gesture) -> Void)?
    var onFingers: ((Int) -> Void)?
    var reportsFingers = false { didSet { TouchProcessor.shared.setReportsFingers(reportsFingers) } }
    var tuning = GestureTuning() { didSet { TouchProcessor.shared.setTuning(tuning) } }
    var interests = GestureInterests.immediate { didSet { if interests != oldValue { TouchProcessor.shared.setInterests(interests) } } }
    private(set) var isRunning = false

    private let api: MultitouchAPI?
    private var devices: CFArray?
    private var running: [UnsafeMutableRawPointer] = []
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var rescanPending = false
    private var wakeObservers: [NSObjectProtocol] = []
    /// Device descriptions for diagnostics (family, built-in, size). No touch data.
    private(set) var deviceSummary: [String] = []

    init() {
        if Diagnostics.gesturesUnavailable {
            api = nil
            unavailableReason = "Trackpad gestures aren't available on this Mac. Mouse buttons and key combinations still work."
        } else {
            api = MultitouchAPI.load()
            if api == nil {
                unavailableReason = "Trackpad gestures aren't available on this version of macOS. Mouse buttons and key combinations still work."
            }
        }
        TouchProcessor.shared.deliver = { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    private func handle(_ event: TouchProcessor.Event) {
        switch event {
        case .gesture(let gesture):
            // Without real input (test mode), the only frames are replays.
            guard isRunning || Diagnostics.noInput else { return }
            if let modifiers = TouchReplayer.stepModifiers {
                Diagnostics.record("replay recognized \(gesture.title)")
                AppModel.shared.engine.receive(.gesture(gesture, modifiers: modifiers))
            } else {
                onGesture?(gesture)
            }
        case .fingers(let count): if reportsFingers { onFingers?(count) }
        case .garbage:
            stop()
            unavailableReason = "Triggers turned trackpad gestures off because this version of macOS reports touches in a way it doesn't understand. Mouse buttons and key combinations still work."
            Diagnostics.record("touch frames failed validation; gestures off")
            NotificationCenter.default.post(name: .touchSourceChanged, object: nil)
        }
    }

    func start() {
        guard !isRunning, !Diagnostics.noInput, let api, unavailableReason == nil else { return }
        isRunning = true
        startDevices(api)
        watchDevices()
        if wakeObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
                wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { self.scheduleRescan() }
                })
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let api { stopDevices(api) }
        unwatchDevices()
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers.removeAll()
        TouchProcessor.shared.reset()
    }

    /// Re-enumerate after wake or a trackpad coming or going (a known "stops working after
    /// sleep" failure mode of every tool in this space).
    func scheduleRescan() {
        guard isRunning, !rescanPending else { return }
        rescanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                self.rescanPending = false
                guard self.isRunning, let api = self.api else { return }
                self.stopDevices(api)
                self.startDevices(api)
                Diagnostics.record("touch devices re-enumerated: \(self.running.count)")
            }
        }
    }

    private func startDevices(_ api: MultitouchAPI) {
        TouchProcessor.shared.reset()
        guard let list = api.createList()?.takeRetainedValue() else { return }
        devices = list
        deviceSummary = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var family: Int32 = 0
            _ = api.familyID(device, &family)
            // Magic Mouse surfaces aren't trackpads. Magic Mouse gestures would start here: let
            // these families through, tag their frames as a mouse surface and give them their
            // own recognizer rules (docs/research/triggers.md, "Magic Mouse"). Not done: the
            // only way to read a Magic Mouse's touches is this private framework.
            if MultitouchAPI.mouseFamilies.contains(family) { continue }
            var width: Int32 = 0
            var height: Int32 = 0
            _ = api.surface(device, &width, &height)
            let builtIn = api.isBuiltIn?(device) ?? false
            TouchProcessor.shared.setSurface(device: Int(bitPattern: device), width: Float(width) / 100, height: Float(height) / 100)
            api.register(device, touchFrameCallback)
            if api.start(device, 0) == 0 {
                running.append(device)
                deviceSummary.append("family=\(family) builtIn=\(builtIn) surface_mm=\(width / 100)x\(height / 100)")
            }
        }
    }

    private func stopDevices(_ api: MultitouchAPI) {
        for device in running {
            api.unregister(device, touchFrameCallback)
            _ = api.stop(device)
        }
        running.removeAll()
        // The list (and the device objects it retains) stays alive until the next scan: some
        // macOS versions call back once more after stopping.
    }

    // MARK: Device add/remove

    private func watchDevices() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let callback: IOServiceMatchingCallback = { context, iterator in
                // Drain the iterator to re-arm the notification.
                while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
                guard let context else { return }
                let source = Unmanaged<MultitouchSource>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { source.scheduleRescan() }
            }
            if IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, context, &iterator) == KERN_SUCCESS {
                while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
                iterators.append(iterator)
            }
        }
    }

    private func unwatchDevices() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port = notifyPort { IONotificationPortDestroy(port) }
        notifyPort = nil
    }

    var frameStats: (intervals: LatencyStats, cost: LatencyStats, frames: Int, bad: Int) {
        TouchProcessor.shared.stats()
    }
}

/// The C callback. MultitouchSupport calls it on its own thread for every frame while
/// fingers touch.
private let touchFrameCallback: TRTouchFrameCallback = { device, touches, count, timestamp, _ in
    TouchProcessor.shared.handle(device: device, touches: touches, count: Int(count), timestamp: timestamp)
}

/// Runs the recognizer on the framework's thread under an uncontended lock (the main thread
/// only takes it to change settings). Converts frames into a reused buffer: no allocation per
/// frame. Hands gestures to the main thread.
final class TouchProcessor: @unchecked Sendable {
    static let shared = TouchProcessor()

    enum Event: Sendable { case gesture(Gesture), fingers(Int), garbage }

    private struct State {
        var recognizer = GestureRecognizer()
        var validator = TouchFrameValidator()
        /// A held-back single tap's deadline (frame clock), with a flush scheduled for it.
        var flushScheduledFor: Double?
        var buffer: [TouchContact] = []
        var reportsFingers = false
        var lastFingers = -1
        var failed = false
        var lastTimestamp = 0.0
        var intervals = LatencyStats()
        var cost = LatencyStats()
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    /// Lets held-back single taps go when their double-tap window ends (no frames arrive then).
    private let flushQueue = DispatchQueue(label: "app.slopapp.triggers.touch-flush", qos: .userInteractive)
    /// Set once by the source at launch, before any frames.
    nonisolated(unsafe) var deliver: (@Sendable (Event) -> Void)?

    private init() {
        lock.withLock { $0.buffer.reserveCapacity(32) }
    }

    func handle(device: UnsafeMutableRawPointer?, touches: UnsafePointer<TRTouch>?, count: Int, timestamp: Double) {
        let start = mach_absolute_time()
        var event: Event?
        var earlier: Event?
        var fingersEvent: Event?
        var flushAfter: (delay: Double, deadline: Double)?
        lock.withLockUnchecked { state in
            guard !state.failed else { return }
            state.buffer.removeAll(keepingCapacity: true)
            var allValid = true
            if let touches, count > 0, count <= 20 {
                for index in 0..<count {
                    let touch = touches[index]
                    let contact = TouchContact(id: touch.identifier, x: touch.normalized.position.x, y: touch.normalized.position.y,
                                               size: touch.total, state: touch.state)
                    if !TouchFrameValidator.isValid(contact) { allValid = false }
                    if state.buffer.count < 32 { state.buffer.append(contact) }
                }
            }
            if !state.validator.check(count: count, allValid: allValid) {
                state.failed = true
                event = .garbage
                return
            }
            guard allValid else { return }
            if state.lastTimestamp > 0 {
                let interval = timestamp - state.lastTimestamp
                if interval > 0 && interval < 0.1 { state.intervals.record(seconds: interval) }
            }
            state.lastTimestamp = timestamp
            let output = state.buffer.withUnsafeBufferPointer {
                state.recognizer.process(device: Int(bitPattern: device), timestamp: timestamp, contacts: $0)
            }
            if let gesture = output.gesture { event = .gesture(gesture) }
            if let gesture = output.earlier { earlier = .gesture(gesture) }
            if let deadline = output.pendingUntil, state.flushScheduledFor != deadline {
                state.flushScheduledFor = deadline
                flushAfter = (max(0, deadline - timestamp), deadline)
            }
            if state.reportsFingers, output.fingers != state.lastFingers {
                state.lastFingers = output.fingers
                fingersEvent = .fingers(output.fingers)
            }
            state.cost.record(seconds: Self.seconds(since: start))
        }
        if let fingersEvent { deliver?(fingersEvent) }
        if let earlier { deliver?(earlier) }
        if let event { deliver?(event) }
        if let flushAfter { scheduleFlush(after: flushAfter.delay, deadline: flushAfter.deadline) }
    }

    /// At the deadline, in the frames' own clock (so the two clocks never mix).
    private func scheduleFlush(after delay: Double, deadline: Double) {
        flushQueue.asyncAfter(deadline: .now() + delay + 0.001) { [self] in
            let gestures = lock.withLock { state -> [Gesture] in
                guard state.flushScheduledFor == deadline else { return [] }
                state.flushScheduledFor = nil
                return state.recognizer.flush(now: deadline)
            }
            for gesture in gestures { deliver?(.gesture(gesture)) }
        }
    }

    func setInterests(_ interests: GestureInterests) { lock.withLock { $0.recognizer.interests = interests } }

    func setSurface(device: Int, width: Float, height: Float) {
        lock.withLock { $0.recognizer.setSurface(device: device, width: width, height: height) }
    }

    func setTuning(_ tuning: GestureTuning) { lock.withLock { $0.recognizer.tuning = tuning } }

    func setReportsFingers(_ value: Bool) {
        lock.withLock { state in
            state.reportsFingers = value
            state.lastFingers = -1
        }
    }

    func reset() { lock.withLock { $0.recognizer.reset() } }

    func stats() -> (intervals: LatencyStats, cost: LatencyStats, frames: Int, bad: Int) {
        lock.withLock { ($0.intervals, $0.cost, $0.validator.goodFrames, $0.validator.badFrames) }
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func seconds(since start: UInt64) -> Double {
        let elapsed = mach_absolute_time() &- start
        return Double(elapsed) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

/// The handful of MultitouchSupport functions Triggers uses, resolved with `dlsym`.
struct MultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias Register = @convention(c) (UnsafeMutableRawPointer?, TRTouchFrameCallback?) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias FamilyID = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>) -> Int32
    typealias Surface = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer?) -> Bool

    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let familyID: FamilyID
    let surface: Surface
    let isBuiltIn: IsBuiltIn?

    /// Magic Mouse and Magic Mouse 2.
    static let mouseFamilies: Set<Int32> = [112, 113]

    static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    static func load() -> MultitouchAPI? {
        guard let handle = dlopen(path, RTLD_LAZY) else {
            Diagnostics.record("MultitouchSupport didn't load")
            return nil
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else {
                Diagnostics.record("MultitouchSupport is missing \(name)")
                return nil
            }
            return unsafeBitCast(pointer, to: type)
        }
        guard let createList = symbol("MTDeviceCreateList", as: CreateList.self),
              let register = symbol("MTRegisterContactFrameCallback", as: Register.self),
              let unregister = symbol("MTUnregisterContactFrameCallback", as: Register.self),
              let start = symbol("MTDeviceStart", as: Start.self),
              let stop = symbol("MTDeviceStop", as: Stop.self),
              let familyID = symbol("MTDeviceGetFamilyID", as: FamilyID.self),
              let surface = symbol("MTDeviceGetSensorSurfaceDimensions", as: Surface.self)
        else { return nil }
        return MultitouchAPI(createList: createList, register: register, unregister: unregister, start: start, stop: stop,
                             familyID: familyID, surface: surface, isBuiltIn: symbol("MTDeviceIsBuiltIn", as: IsBuiltIn.self))
    }
}

extension Notification.Name {
    static let touchSourceChanged = Notification.Name("app.slopapp.triggers.touchSourceChanged")
}
