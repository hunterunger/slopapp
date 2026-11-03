import Foundation

/// How a Move to Trash was asked for. The review pane's own button is an explicit, visible
/// choice; a menu item or shortcut can fire from anywhere (even while typing in search).
public enum MoveTrigger: Sendable, Equatable {
    case reviewButton
    case menuCommand
}

/// Rules that keep destructive actions tied to what the user can see.
public enum ReviewRules {
    /// What a destructive action may touch: checked items that are visible right now, in
    /// the order they're shown. Checked items hidden by search or filters are left alone.
    public static func actionable(checked: Set<String>, visible: [String]) -> [String] {
        visible.filter(checked.contains)
    }

    /// The selection after the visible list changed: kept if still visible, otherwise none.
    public static func reconcile(selection: String?, visible: [String]) -> String? {
        guard let selection, visible.contains(selection) else { return nil }
        return selection
    }

    public static func reconcile(selection: Set<String>, visible: [String]) -> Set<String> {
        selection.intersection(visible)
    }

    /// A menu key equivalent that's also a text-editing key (⌘⌫, ⌘Z) goes to the text field
    /// being edited instead of the app's command.
    public static func routesToTextField(isEditingText: Bool) -> Bool { isEditingText }
}

/// What uninstalling will do, for the confirmation shown when it's started from a menu or
/// shortcut instead of the review pane's button.
public struct UninstallPlan: Sendable, Equatable, Identifiable {
    public var id: String { appName + "\(itemCount)" }
    public var appName: String
    public var includesApp: Bool
    /// Items besides the app itself.
    public var itemCount: Int
    public var bytes: Int64

    public init(appName: String, includesApp: Bool, itemCount: Int, bytes: Int64) {
        self.appName = appName
        self.includesApp = includesApp
        self.itemCount = itemCount
        self.bytes = bytes
    }

    public func needsConfirmation(_ trigger: MoveTrigger) -> Bool { trigger == .menuCommand }

    public var title: String {
        includesApp ? "Move \(appName) to the Trash?" : "Move \(appName)’s files to the Trash?"
    }

    public var message: String {
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        let what = includesApp ? (itemCount > 0 ? "\(appName) and \(items)" : appName) : items
        return "\(what), \(ByteFormat.string(bytes)), will be moved to the Trash. You can put them back."
    }
}
