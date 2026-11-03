import Foundation
import IOKit.pwr_mgt

/// Holds or releases a "don't idle-sleep" request. Behind a protocol so tests never touch
/// the real system.
@MainActor
public protocol SleepBlocker: AnyObject {
    var isHeld: Bool { get }
    func hold(reason: String) -> Bool
    func release()
}

/// The real thing: an IOPMAssertion that stops idle sleep (the display may still sleep).
/// Shows up in `pmset -g assertions` as "Convert is converting files".
@MainActor
public final class IOKitSleepBlocker: SleepBlocker {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isHeld: Bool { assertionID != nil }

    public func hold(reason: String) -> Bool {
        guard assertionID == nil else { return true }
        var id = IOPMAssertionID(0)
        // The string value of kIOPMAssertionTypePreventUserIdleSystemSleep.
        let result = IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        return true
    }

    public func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}

/// Keeps the Mac awake exactly while the queue is busy.
@MainActor
public final class KeepAwake {
    private let blocker: any SleepBlocker
    private let reason: String

    public init(blocker: any SleepBlocker = IOKitSleepBlocker(), reason: String = "Converting files") {
        self.blocker = blocker
        self.reason = reason
    }

    public var isHolding: Bool { blocker.isHeld }

    public func update(busy: Bool) {
        if busy {
            _ = blocker.hold(reason: reason)
        } else {
            blocker.release()
        }
    }
}
