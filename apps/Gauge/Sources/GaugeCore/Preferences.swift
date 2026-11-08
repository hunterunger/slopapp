import Foundation

/// Something Gauge can show in the menu bar.
public enum Readout: String, Sendable, Codable, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, battery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory pressure"
        case .network: "Network"
        case .disk: "Disk free"
        case .battery: "Battery"
        }
    }

    /// The SF Symbol beside the value (battery picks its own by level).
    public var symbol: String? {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .network: nil
        case .disk: "internaldrive"
        case .battery: "battery.100percent"
        }
    }
}

/// How often the counters are read while the panel is closed.
public enum UpdateInterval: Int, Sendable, Codable, CaseIterable, Identifiable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var title: String {
        switch self {
        case .oneSecond: "1 second"
        case .twoSeconds: "2 seconds"
        case .fiveSeconds: "5 seconds"
        }
    }
}

/// Everything in Settings. Stored as one JSON value; unknown or missing keys fall back to
/// the defaults so an older or newer copy of Gauge never loses the rest.
public struct Preferences: Sendable, Equatable, Codable {
    public static let maxReadouts = 3
    public static let defaultReadouts: [Readout] = [.cpu, .network]

    /// In menu bar order. At most `maxReadouts`, no duplicates.
    public var readouts: [Readout] {
        didSet { readouts = Self.normalized(readouts) }
    }
    public var interval: UpdateInterval
    public var slowDownInLowPowerMode: Bool
    public var rateUnit: RateUnit
    public var groupProcessesByApp: Bool
    public var historySpan: HistorySpan

    public init(readouts: [Readout] = Preferences.defaultReadouts, interval: UpdateInterval = .twoSeconds,
                slowDownInLowPowerMode: Bool = true, rateUnit: RateUnit = .bytes,
                groupProcessesByApp: Bool = true, historySpan: HistorySpan = .tenMinutes) {
        self.readouts = Self.normalized(readouts)
        self.interval = interval
        self.slowDownInLowPowerMode = slowDownInLowPowerMode
        self.rateUnit = rateUnit
        self.groupProcessesByApp = groupProcessesByApp
        self.historySpan = historySpan
    }

    static func normalized(_ readouts: [Readout]) -> [Readout] {
        var seen = Set<Readout>()
        return Array(readouts.filter { seen.insert($0).inserted }.prefix(maxReadouts))
    }

    public func shows(_ readout: Readout) -> Bool { readouts.contains(readout) }

    /// Whether `readout` can be switched on: there's room, or it's already on.
    public func canAdd(_ readout: Readout) -> Bool {
        readouts.contains(readout) || readouts.count < Self.maxReadouts
    }

    /// Turns a readout on (appended at the end) or off. Turning the last one off is allowed:
    /// the item then shows just its symbol.
    public mutating func set(_ readout: Readout, shown: Bool) {
        if shown {
            guard !readouts.contains(readout), readouts.count < Self.maxReadouts else { return }
            readouts.append(readout)
        } else {
            readouts.removeAll { $0 == readout }
        }
    }

    /// Moves a shown readout left (-1) or right (+1) in the menu bar.
    public mutating func move(_ readout: Readout, by offset: Int) {
        guard let index = readouts.firstIndex(of: readout) else { return }
        let target = index + offset
        guard readouts.indices.contains(target) else { return }
        readouts.swapAt(index, target)
    }

    // MARK: Codable, tolerant

    enum CodingKeys: String, CodingKey {
        case readouts, interval, slowDownInLowPowerMode, rateUnit, groupProcessesByApp, historySpan
    }

    public init(from decoder: any Decoder) throws {
        let defaults = Preferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Readouts by raw value, skipping any this version doesn't know.
        let raw = try? container.decodeIfPresent([String].self, forKey: .readouts)
        self.readouts = raw.map { Self.normalized($0.compactMap(Readout.init(rawValue:))) } ?? defaults.readouts
        interval = (try? container.decodeIfPresent(UpdateInterval.self, forKey: .interval)) ?? defaults.interval
        slowDownInLowPowerMode = (try? container.decodeIfPresent(Bool.self, forKey: .slowDownInLowPowerMode))
            ?? defaults.slowDownInLowPowerMode
        rateUnit = (try? container.decodeIfPresent(RateUnit.self, forKey: .rateUnit)) ?? defaults.rateUnit
        groupProcessesByApp = (try? container.decodeIfPresent(Bool.self, forKey: .groupProcessesByApp))
            ?? defaults.groupProcessesByApp
        historySpan = (try? container.decodeIfPresent(HistorySpan.self, forKey: .historySpan)) ?? defaults.historySpan
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readouts.map(\.rawValue), forKey: .readouts)
        try container.encode(interval, forKey: .interval)
        try container.encode(slowDownInLowPowerMode, forKey: .slowDownInLowPowerMode)
        try container.encode(rateUnit, forKey: .rateUnit)
        try container.encode(groupProcessesByApp, forKey: .groupProcessesByApp)
        try container.encode(historySpan, forKey: .historySpan)
    }
}

/// Where preferences are kept. `UserDefaults` in the app, a dictionary in tests.
public protocol PreferenceStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

extension UserDefaults: PreferenceStorage {
    public func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}

public enum PreferencesCodec {
    public static let key = "preferences"

    public static func load(from storage: any PreferenceStorage) -> Preferences {
        guard let data = storage.data(forKey: key),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return preferences
    }

    public static func save(_ preferences: Preferences, to storage: any PreferenceStorage) {
        storage.set(try? JSONEncoder().encode(preferences), forKey: key)
    }
}

/// How often to sample, given the settings and the situation.
public enum Cadence {
    /// The panel open samples every second; Low Power Mode slows to 5 s (when allowed).
    public static func interval(for preferences: Preferences, panelOpen: Bool, lowPowerMode: Bool) -> TimeInterval {
        if panelOpen { return 1 }
        if lowPowerMode && preferences.slowDownInLowPowerMode {
            return max(preferences.interval.seconds, UpdateInterval.fiveSeconds.seconds)
        }
        return preferences.interval.seconds
    }

    /// Timer leeway: generous, so macOS can batch Gauge's wakeups with others'.
    public static func leeway(for interval: TimeInterval) -> TimeInterval {
        min(1, interval * 0.2)
    }
}
