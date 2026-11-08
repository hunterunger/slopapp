import Foundation

/// How snippets get into the app.
public enum InsertMode: String, Codable, Sendable, CaseIterable {
    /// Type short single lines; paste anything longer, multi-line or with a Tab.
    case automatic
    case alwaysPaste
    case alwaysType
}

public enum InsertMethod: String, Sendable, Equatable {
    case type
    case paste
}

/// Everything the inserter does for one expansion, in order: Backspaces, the text (typed or
/// pasted), ← presses to the cursor marker, then the keys typed meanwhile.
public struct InsertionPlan: Sendable, Equatable {
    public var backspaces: Int
    public var method: InsertMethod
    public var text: String
    public var leftArrows: Int
    public var retype: String
}

public enum InsertionPlanner {
    /// Longest text typed in automatic mode.
    public static let typeLimit = 200

    public static func method(for text: String, mode: InsertMode) -> InsertMethod {
        switch mode {
        case .alwaysPaste: return .paste
        case .alwaysType: return .type
        case .automatic:
            // A typed Return sends the message in Messages, Slack and friends; a typed Tab
            // moves focus. Both paste.
            if text.contains(where: { $0.isNewline || $0 == "\t" }) || text.count > typeLimit { return .paste }
            return .type
        }
    }

    /// `typedLength`: characters typed for the abbreviation; `pending`: keys typed after it
    /// (already in the app, after the abbreviation: they're deleted and retyped after the snippet).
    public static func plan(resolved: Resolved, typedLength: Int, pending: String, mode: InsertMode) -> InsertionPlan {
        InsertionPlan(backspaces: typedLength + pending.count, method: method(for: resolved.text, mode: mode),
                      text: resolved.text, leftArrows: resolved.charactersAfterCursor, retype: pending)
    }
}
