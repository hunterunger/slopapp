import Foundation
import GaugeCore
import Observation

/// Settings, observable for SwiftUI. Saved to UserDefaults (or the `GAUGE_DEFAULTS_SUITE`
/// test suite) on every change and handed to the sampler.
@MainActor
@Observable
final class PreferencesStore {
    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            if !isVolatile { PreferencesCodec.save(preferences, to: defaults) }
            onChange?(preferences)
        }
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var onChange: ((Preferences) -> Void)?
    /// Started with test overrides (`GAUGE_READOUTS`…): changes aren't saved.
    @ObservationIgnored var isVolatile = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        preferences = PreferencesCodec.load(from: defaults)
    }
}
