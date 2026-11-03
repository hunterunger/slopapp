import Foundation

// Pure logic for __NAME__ lives in this target.
//
// Rules of thumb:
// - No SwiftUI or AppKit views here.
// - Put system access (files, pasteboard, IOKit, clocks, timers) behind a protocol
//   and inject it, so tests can pass a fake. See apps/Awake/Sources/AwakeCore.
// - Keep it deterministic: pass in `Date`s and locales instead of reading globals.

public enum __NAME__Core {
    public static let appName = "__NAME__"
}
