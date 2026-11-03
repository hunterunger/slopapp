import Foundation
import IOKit.pwr_mgt

/// Holds or releases the "don't sleep" request. Injected so tests never touch the real system.
@MainActor
public protocol PowerAssertion: AnyObject {
    var isHeld: Bool { get }
    /// Takes (or replaces) the assertion. `keepDisplayOn` also stops the screen dimming.
    func hold(keepDisplayOn: Bool, reason: String) throws
    func release()
}

public struct PowerAssertionError: Error, CustomStringConvertible {
    public let code: Int32
    public var description: String { "Couldn't keep the Mac awake (IOKit error \(code))." }
}

/// The real thing: an IOPMAssertion. Shows up in `pmset -g assertions`.
@MainActor
public final class IOKitPowerAssertion: PowerAssertion {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isHeld: Bool { assertionID != nil }

    public func hold(keepDisplayOn: Bool, reason: String) throws {
        release()
        // String values of kIOPMAssertionTypePreventUserIdle{Display,System}Sleep,
        // which aren't imported into Swift as constants.
        let type = keepDisplayOn ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { throw PowerAssertionError(code: result) }
        assertionID = id
    }

    public func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}
