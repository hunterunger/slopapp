import Foundation

/// One-click suggestions for the empty editor. Nothing is on until the person adds one.
public struct Starter: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let systemImage: String
    public let bindings: [TriggerBinding]
    /// Apps the bindings need in the sidebar.
    public let apps: [AppEntry]

    public static let all: [Starter] = [
        Starter(
            id: "tap-middle-click",
            title: "Three-finger tap to middle-click",
            detail: "Open links in a new tab, close tabs, paste in Terminal.",
            systemImage: "hand.tap",
            bindings: [TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps)],
            apps: []
        ),
        Starter(
            id: "swipe-back-forward",
            title: "Four-finger swipe to go back and forward",
            detail: "In browsers: swipe right for Back, left for Forward.",
            systemImage: "arrow.left.arrow.right",
            bindings: [
                TriggerBinding(trigger: .gesture(.swipe(4, .right), modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)), scope: .browsers),
                TriggerBinding(trigger: .gesture(.swipe(4, .left), modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.rightBracket, modifiers: .command)), scope: .browsers),
            ],
            apps: []
        ),
        Starter(
            id: "mouse-back-forward",
            title: "Mouse buttons 4 and 5 for Back and Forward",
            detail: "In browsers and Finder, which ignore these buttons on their own.",
            systemImage: "computermouse",
            bindings: [
                TriggerBinding(trigger: .mouseButton(3, modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)), scope: .browsers),
                TriggerBinding(trigger: .mouseButton(4, modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.rightBracket, modifiers: .command)), scope: .browsers),
                TriggerBinding(trigger: .mouseButton(3, modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)), scope: .app(bundleID: "com.apple.finder")),
                TriggerBinding(trigger: .mouseButton(4, modifiers: []),
                        action: .pressKeys(KeyCombo(keyCode: KeyNames.rightBracket, modifiers: .command)), scope: .app(bundleID: "com.apple.finder")),
            ],
            apps: [AppEntry(bundleID: "com.apple.finder", name: "Finder")]
        ),
    ]

    /// Adds the starter to `config` with fresh ids, skipping bindings that already exist.
    public func apply(to config: inout Config) -> [TriggerBinding] {
        for app in apps { config.addApp(bundleID: app.bundleID, name: app.name) }
        var added: [TriggerBinding] = []
        for binding in bindings {
            let exists = config.bindings.contains { $0.trigger == binding.trigger && $0.scope == binding.scope }
            guard !exists else { continue }
            var copy = binding
            copy.id = UUID()
            config.bindings.append(copy)
            added.append(copy)
        }
        return added
    }

    /// Whether everything this starter adds is already there.
    public func isApplied(in config: Config) -> Bool {
        bindings.allSatisfy { binding in
            config.bindings.contains { $0.trigger == binding.trigger && $0.scope == binding.scope }
        }
    }
}

/// The last few fires, newest first, in memory only. Names what fired, never content.
public struct RecentLog: Sendable, Equatable {
    public struct Entry: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let bindingID: UUID
        public let trigger: Trigger
        public let action: Action
        public let appName: String?
        public let date: Date
        public let outcome: String?
    }

    public private(set) var entries: [Entry] = []
    public let capacity: Int

    public init(capacity: Int = 20) { self.capacity = capacity }

    public mutating func record(_ binding: TriggerBinding, appName: String?, date: Date, outcome: String? = nil) {
        entries.insert(Entry(id: UUID(), bindingID: binding.id, trigger: binding.trigger, action: binding.action,
                             appName: appName, date: date, outcome: outcome), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    public mutating func clear() { entries.removeAll() }
}

/// "2 s ago", "5 min ago", for the Recent menu.
public enum RelativeAge {
    public static func describe(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds) s ago" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }
}
