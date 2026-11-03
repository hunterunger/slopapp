import Darwin
import Foundation
import Observation
import ZonesCore

/// UI state of the panel that isn't the model's business: which mode it's in, the search
/// query and results, inline edits.
@MainActor
@Observable
final class PanelState {
    enum Mode: Equatable {
        case list
        case search
        /// Typing a time on a row ("3pm").
        case editingTime(UUID)
        case renaming(UUID)
    }

    var mode: Mode = .list
    /// Text being typed into a row's time or name.
    var editText = ""
    /// "Type a time like 3pm or 15:30", shown under the list after a bad entry.
    var editError: String?

    // Search
    var query = "" {
        didSet { if query != oldValue { updateResults() } }
    }
    private(set) var results: [SearchResult] = []
    var resultSelection = 0
    private(set) var isLoading = false
    private(set) var loadError: String?
    private var search: PlaceSearch?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    // Mouse tracking (AppController), in the panel's top-left coordinates
    /// Where the vertical marker is drawn while dragging sideways.
    var markerX: CGFloat?
    @ObservationIgnored var rowFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var timeFrames: [UUID: CGRect] = [:]
    var listFrame: CGRect = .zero
    @ObservationIgnored var moreButtonFrame: CGRect = .zero
    /// macOS is hiding the menu bar item (full menu bar / notch). Shown in Settings.
    var statusItemHiddenBySystem = false
    /// When the result list last changed: a pointer resting over the list mustn't steal
    /// the highlight from the first result.
    @ObservationIgnored var resultsChangedAt = Date.distantPast

    // MARK: Modes

    func beginSearch() {
        cancelRelease()
        mode = .search
        query = ""
        resultSelection = 0
        loadIfNeeded()
        updateResults()
    }

    func beginEditingTime(_ id: UUID, initialText: String = "") {
        editText = initialText
        editError = nil
        mode = .editingTime(id)
    }

    func beginRenaming(_ id: UUID, current: String) {
        editText = current
        editError = nil
        mode = .renaming(id)
    }

    func cancel() {
        mode = .list
        editError = nil
        query = ""
    }

    func reset() {
        cancel()
        markerX = nil
    }

    /// Drops the city list (about 15 MB in memory) once the panel has been closed for a
    /// while, and hands the memory back to the system. It reloads in a fraction of a second.
    func releaseSearchSoon() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.mode != .search, !self.isLoading else { return }
            self.search = nil
            self.results = []
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    func cancelRelease() {
        releaseTask?.cancel()
    }

    // MARK: Search

    var selectedResult: SearchResult? {
        results.indices.contains(resultSelection) ? results[resultSelection] : nil
    }

    func moveResultSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        resultSelection = max(0, min(results.count - 1, resultSelection + delta))
    }

    /// Loads the bundled city list off the main thread the first time search opens.
    private func loadIfNeeded() {
        guard search == nil, !isLoading else { return }
        guard let url = CityDatabase.bundledURL else {
            loadError = "The city list is missing from the app. Reinstall Zones to get it back."
            return
        }
        isLoading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> PlaceSearch? in
                guard let database = try? CityDatabase.load(from: url) else { return nil }
                return PlaceSearch(database: database)
            }.value
            isLoading = false
            if let loaded {
                search = loaded
            } else {
                loadError = "Couldn't read the city list. Reinstall Zones to repair it."
            }
            updateResults()
        }
    }

    private func updateResults() {
        guard mode == .search, let search else {
            results = []
            return
        }
        results = search.results(for: query)
        resultSelection = 0
        resultsChangedAt = Date()
    }
}
