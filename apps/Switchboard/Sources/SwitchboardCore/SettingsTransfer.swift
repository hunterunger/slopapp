import Foundation

/// An exported settings file: readable JSON, with a marker so a random JSON file isn't taken
/// for settings. Import also accepts a plain config.json copied from another Mac.
public struct SettingsFile: Codable, Equatable, Sendable {
    public static let formatName = "Switchboard settings"
    public static let currentFormatVersion = 1

    public var format: String
    public var formatVersion: Int
    public var exportedAt: Date?
    public var settings: Config

    public init(settings: Config, exportedAt: Date?) {
        format = Self.formatName
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

public enum SettingsTransfer {
    public enum ReadError: Error, Equatable {
        /// Not JSON, or JSON that isn't Switchboard settings.
        case notSettings
        /// Made by a newer Switchboard in a format this one can't read.
        case newerFormat(Int)
    }

    public enum Mode: Equatable, Sendable {
        /// Add what's new, keep everything already here.
        case merge
        /// Use the file's settings instead (undoable in the app).
        case replace
    }

    /// Pretty-printed, keys sorted, dates in ISO 8601, so the file reads well and diffs well.
    public static func export(_ config: Config, at date: Date? = Date()) throws -> Data {
        var copy = config
        copy.didSeedTargets = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(SettingsFile(settings: copy, exportedAt: date))
    }

    public static func read(_ data: Data) throws -> Config {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Marker: Decodable { var format: String?; var formatVersion: Int? }
        if let marker = try? decoder.decode(Marker.self, from: data), marker.format == SettingsFile.formatName {
            if let version = marker.formatVersion, version > SettingsFile.currentFormatVersion {
                throw ReadError.newerFormat(version)
            }
            guard let file = try? decoder.decode(SettingsFile.self, from: data) else { throw ReadError.notSettings }
            return file.settings
        }
        guard let config = try? decoder.decode(Config.self, from: data) else { throw ReadError.notSettings }
        return config
    }

    /// What an import would do, in numbers, for the preview.
    public struct Summary: Equatable, Sendable {
        public var browsers = 0
        public var emailApps = 0
        public var rules = 0
        public var rewrites = 0
        public var appHandoffs = 0
        public var fileTypes = 0
        /// Already here (merge): not added again.
        public var duplicateRules = 0
        public var duplicateTargets = 0

        public init() {}

        public var isEmpty: Bool {
            browsers + emailApps + rules + rewrites + appHandoffs + fileTypes == 0
        }

        /// "3 browsers, 12 rules and 1 rewrite".
        public var itemsText: String {
            var parts: [String] = []
            func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") } }
            add(browsers, "browser", "browsers")
            add(emailApps, "email app", "email apps")
            add(rules, "rule", "rules")
            add(rewrites, "rewrite", "rewrites")
            add(appHandoffs, "app to open links in", "apps to open links in")
            add(fileTypes, "file type", "file types")
            return parts.isEmpty ? "nothing new" : ListFormatter.localizedString(byJoining: parts)
        }
    }

    public struct Plan: Equatable, Sendable {
        public var result: Config
        public var summary: Summary
    }

    /// The settings after importing `incoming` into `current`.
    ///
    /// Merge keeps every current setting and order, and appends what the file has that isn't
    /// here: browsers and email apps (matched by app, profile and options), rules (matched
    /// by conditions and destination), rewrites, app handoffs and file types. Rules from the
    /// file that point at a browser already here are reconnected to it.
    public static func plan(importing incoming: Config, into current: Config, mode: Mode) -> Plan {
        switch mode {
        case .replace:
            var result = incoming
            result.didSeedTargets = true
            var summary = Summary()
            summary.browsers = incoming.targets.count
            summary.emailApps = incoming.emailTargets.count
            summary.rules = incoming.rules.count
            summary.rewrites = incoming.rewrites.count
            summary.appHandoffs = incoming.handoffs.filter { Handoffs.handoff(id: $0) != nil }.count
            summary.fileTypes = incoming.fileTypes.count
            return Plan(result: result, summary: summary)
        case .merge:
            return merge(incoming, into: current)
        }
    }

    private static func merge(_ incoming: Config, into current: Config) -> Plan {
        var result = current
        var summary = Summary()
        var idMap: [UUID: UUID] = [:]
        var usedIDs = Set(current.targets.map(\.id) + current.emailTargets.map(\.id) + current.removedTargets.map(\.id)
                          + current.fileTypes.compactMap(\.app?.id))

        func fresh(_ id: UUID) -> UUID {
            if usedIDs.contains(id) {
                let new = UUID()
                usedIDs.insert(new)
                return new
            }
            usedIDs.insert(id)
            return id
        }

        func mergeTargets(_ list: [Target], into keyPath: WritableKeyPath<Config, [Target]>, count: WritableKeyPath<Summary, Int>) {
            for target in list {
                if let existing = result[keyPath: keyPath].first(where: { $0.isSameDestination(as: target) }) {
                    idMap[target.id] = existing.id
                    summary.duplicateTargets += 1
                } else {
                    var copy = target
                    copy.id = fresh(target.id)
                    idMap[target.id] = copy.id
                    result[keyPath: keyPath].append(copy)
                    summary[keyPath: count] += 1
                }
            }
        }
        mergeTargets(incoming.targets, into: \.targets, count: \.browsers)
        mergeTargets(incoming.emailTargets, into: \.emailTargets, count: \.emailApps)

        // Removed browsers the file's rules still point at come along as removed, so those
        // rules reconnect if the browser is added later.
        for tombstone in incoming.removedTargets where idMap[tombstone.id] == nil {
            if let existing = (result.targets + result.emailTargets + result.removedTargets)
                .first(where: { $0.destinationKey == tombstone.destinationKey }) {
                idMap[tombstone.id] = existing.id
            } else {
                var copy = tombstone
                copy.id = fresh(tombstone.id)
                idMap[tombstone.id] = copy.id
                result.removedTargets.append(copy)
            }
        }

        // File types: the file's app comes along with its type.
        for type in incoming.fileTypes {
            if let index = result.fileTypes.firstIndex(where: { $0.id == type.id }) {
                if let app = type.app, let mine = result.fileTypes[index].app, mine.bundleID == app.bundleID {
                    idMap[app.id] = mine.id
                }
                continue
            }
            var copy = type
            if let app = type.app {
                var newApp = app
                newApp.id = fresh(app.id)
                idMap[app.id] = newApp.id
                copy.app = newApp
            }
            result.fileTypes.append(copy)
            summary.fileTypes += 1
        }
        // Fallbacks of the newly added file types point into the merged ids.
        for index in result.fileTypes.indices where !current.fileTypes.contains(where: { $0.id == result.fileTypes[index].id }) {
            result.fileTypes[index].fallback = remap(result.fileTypes[index].fallback, idMap)
        }

        for rule in incoming.rules {
            var copy = rule
            if case .open(let id) = rule.action { copy.action = .open(targetID: idMap[id] ?? id) }
            if result.rules.contains(where: { sameRule($0, copy) }) {
                summary.duplicateRules += 1
                continue
            }
            if result.rules.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
            result.rules.append(copy)
            summary.rules += 1
        }

        for rewrite in incoming.rewrites where !result.rewrites.contains(where: { sameRewrite($0, rewrite) }) {
            var copy = rewrite
            if result.rewrites.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
            result.rewrites.append(copy)
            summary.rewrites += 1
        }

        for id in incoming.handoffs where Handoffs.handoff(id: id) != nil && !result.handoffs.contains(id) {
            result.handoffs.append(id)
            summary.appHandoffs += 1
        }
        return Plan(result: result, summary: summary)
    }

    private static func remap(_ fallback: Fallback, _ map: [UUID: UUID]) -> Fallback {
        if case .open(let id) = fallback { return .open(targetID: map[id] ?? id) }
        return fallback
    }

    static func sameRule(_ a: Rule, _ b: Rule) -> Bool {
        a.kind == b.kind && a.host.caseInsensitiveCompare(b.host) == .orderedSame && a.path == b.path
            && Set(a.fileExtensions) == Set(b.fileExtensions) && a.sourceApp?.bundleID.lowercased() == b.sourceApp?.bundleID.lowercased()
            && a.modifiers == b.modifiers && a.action == b.action
    }

    static func sameRewrite(_ a: Rewrite, _ b: Rewrite) -> Bool {
        a.host.caseInsensitiveCompare(b.host) == .orderedSame && a.find == b.find
            && a.replacement == b.replacement && a.usesRegex == b.usesRegex
    }
}
