import SlopKit
import SwiftUI
import TidyCore

/// The one-click scan across modules. Scanning changes nothing; Clean moves the checked
/// junk to the Trash (and empties the Trash only if its tile is checked, after asking).
@MainActor
@Observable
final class SmartScanState {
    var includeJunk = Keys.defaults.object(forKey: "smartIncludeJunk") as? Bool ?? true {
        didSet { Keys.defaults.set(includeJunk, forKey: "smartIncludeJunk") }
    }
    /// Emptying the Trash is permanent, so it's off unless the user turns it on.
    var includeTrash = Keys.defaults.bool(forKey: "smartIncludeTrash") {
        didSet { Keys.defaults.set(includeTrash, forKey: "smartIncludeTrash") }
    }
    var step = ""
    var doneLines: [DoneLine] = []
    var didMove = false
    @ObservationIgnored var task: Task<Void, Never>?
}

extension AppModel {
    func startSmartScan() {
        smart.task?.cancel()
        setStage(.scanning, for: .smartScan)
        smart.step = "Looking for junk…"
        smart.task = Task {
            scanJunk()
            async let trash: Void = refreshTrashBins()
            async let background: Void = refreshBackgroundItems()
            await junkTask?.value
            guard !Task.isCancelled else { return }
            smart.step = "Looking for leftovers of deleted apps…"
            for _ in 0..<100 where !appsLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            findOrphans()
            for _ in 0..<600 where orphanPhase != .done {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            requestOrphanSizes()
            smart.step = "Checking the Trash and background items…"
            await trash
            await background
            guard !Task.isCancelled else { return }
            // The modules show these results too.
            setStage(.results, for: .smartScan)
            setStage(.results, for: .junk)
            setStage(.results, for: .maintenance)
        }
    }

    func stopSmartScan() {
        smart.task?.cancel()
        stopJunk()
        setStage(.intro, for: .smartScan)
    }

    var smartScanDetail: String {
        if case .scanning(let text) = junkPhase { return "\(smart.step) \(text)" }
        return smart.step
    }

    var smartJunk: [JunkItem] { checkedJunk(in: .systemJunk) }

    var smartCanClean: Bool {
        (smart.includeJunk && !smartJunk.isEmpty) || (smart.includeTrash && !cleanup.trashItems.isEmpty && !cleanup.trashUnreadable)
    }

    /// The big Clean button.
    func cleanSmartScan() {
        guard smartCanClean, !isMoving else { return }
        if smart.includeTrash && !cleanup.trashItems.isEmpty && !cleanup.trashUnreadable {
            confirmErase(context: .smartScan)   // runSmartScan(erasing:) after the user confirms
            return
        }
        runSmartScan(erasing: nil)
    }

    /// Empties the Trash first (if confirmed), then moves the junk, so the junk can still be
    /// put back afterwards.
    func runSmartScan(erasing plan: ErasePlan?) {
        setStage(.running, for: .smartScan)
        Task {
            var lines: [DoneLine] = []
            if let plan {
                smart.step = "Emptying the Trash…"
                lines.append(Self.eraseLine(await performErase(plan)))
            }
            var moved = false
            if smart.includeJunk && !smartJunk.isEmpty {
                smart.step = "Moving junk to the Trash…"
                let result = await performMove(smartJunk.map(\.url), section: .junk)
                lines += Self.doneLines(moved: result, label: "junk")
                moved = !(result?.moved.isEmpty ?? true)
            }
            smart.doneLines = lines
            smart.didMove = moved
            setStage(.done, for: .smartScan)
        }
    }

    func openFromSmartScan(_ section: SidebarSection, review: () -> Void) {
        self.section = section
        review()
    }
}

struct SmartScanView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.stage(.smartScan) {
        case .intro:
            ModuleIntro(systemImage: SidebarSection.smartScan.systemImage, title: "Smart Scan",
                        subtitle: "One scan for junk, the Trash, leftovers of deleted apps and broken background items. Nothing is removed until you click Clean.",
                        features: [ModuleFeature(systemImage: CleanupPane.systemJunk.systemImage, title: "System junk"),
                                   ModuleFeature(systemImage: CleanupPane.trash.systemImage, title: "Trash"),
                                   ModuleFeature(systemImage: SidebarSection.leftovers.systemImage, title: "Leftovers of deleted apps"),
                                   ModuleFeature(systemImage: MaintenancePane.backgroundItems.systemImage, title: "Background items")],
                        buttonHelp: "Scan (⌘R)", action: model.startSmartScan) { EmptyView() }
        case .scanning:
            ModuleScanning(systemImage: SidebarSection.smartScan.systemImage, title: "Scanning your Mac…",
                           detail: model.smartScanDetail, onStop: model.stopSmartScan)
        case .results, .review:
            ModuleResults(headline: headline, subheadline: "Check what to include, then click Clean. Everything else is yours to review.",
                          tiles: tiles) {
                RoundActionButton(title: "Clean", help: cleanHelp) { model.cleanSmartScan() }
                    .disabled(!model.smartCanClean || model.isMoving)
                    .keyboardShortcut(.defaultAction)
                    .padding(.bottom, Spacing.xl)
            }
        case .running:
            ModuleScanning(systemImage: SidebarSection.smartScan.systemImage, title: "Cleaning…", detail: model.smart.step)
        case .done:
            ModuleDone(systemImage: "checkmark", title: model.smart.doneLines.isEmpty ? "Nothing to Do" : "All Done",
                       lines: model.smart.doneLines) {
                if model.smart.didMove {
                    Button("Recently Moved to Trash…") { model.showingHistory = true }
                }
                Spacer()
                Button("Start Over") { model.setStage(.intro, for: .smartScan) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var cleanHelp: String {
        model.smart.includeTrash
            ? "Move the checked junk to the Trash, and empty the Trash (asks first)"
            : "Move the checked junk to the Trash. You can put it back (⌘Z)."
    }

    private var headline: String {
        let junk = model.smart.includeJunk ? model.sizes.total(model.smartJunk.map(\.url)).bytes : 0
        let trash = model.smart.includeTrash ? model.trashTotal.bytes : 0
        let total = junk + trash
        return total > 0 ? "\(ByteFormat.string(total)) is ready to clean." : "Your Mac is in good shape. Here's what Tidy found."
    }

    private var tiles: [TileModel] {
        let junkAll = model.sizes.total(model.junkItems(in: .systemJunk).map(\.url)).bytes
        let junkChecked = model.sizes.total(model.smartJunk.map(\.url)).bytes
        let orphans = model.orphanGroups
        let orphanBytes = model.sizes.total(orphans.flatMap(\.items).map(\.url)).bytes
        let broken = model.maintenance.launchItems.filter(\.isBroken)
        var tiles = [
            TileModel(id: "junk", systemImage: SidebarSection.junk.systemImage, label: "Cleanup",
                      value: "\(ByteFormat.string(junkChecked)) of junk",
                      caption: junkAll > junkChecked ? "to clean (\(ByteFormat.string(junkAll)) found)" : "to clean",
                      detail: "Caches, logs and developer files. Apps make them again when they need them.",
                      isIncluded: Binding(get: { model.smart.includeJunk }, set: { model.smart.includeJunk = $0 }),
                      actions: [TileAction(title: "Review") { model.section = .junk; model.reviewCleanup(.systemJunk) }],
                      isQuiet: junkChecked == 0),
        ]
        if model.cleanup.trashUnreadable {
            tiles.append(TileModel(id: "trash", systemImage: CleanupPane.trash.systemImage, label: "Trash", value: "Needs access",
                                   caption: "macOS protects the Trash.",
                                   actions: [TileAction(title: "Allow…") { model.showingAccessSheet = true }], isQuiet: true))
        } else {
            tiles.append(TileModel(id: "trash", systemImage: CleanupPane.trash.systemImage, label: "Trash",
                                   value: "\(ByteFormat.string(model.trashTotal.bytes)) in the Trash",
                                   caption: model.cleanup.trashItems.isEmpty ? "already empty" : "to empty",
                                   isIncluded: Binding(get: { model.smart.includeTrash }, set: { model.smart.includeTrash = $0 }),
                                   actions: [TileAction(title: "Review") { model.section = .junk; model.reviewCleanup(.trash) }],
                                   isQuiet: model.cleanup.trashItems.isEmpty))
        }
        tiles.append(TileModel(id: "leftovers", systemImage: SidebarSection.leftovers.systemImage, label: "Leftovers",
                               value: orphans.count == 1 ? "1 deleted app" : "\(orphans.count) deleted apps",
                               caption: orphans.isEmpty ? "left nothing behind" : "left \(ByteFormat.string(orphanBytes)) to review",
                               actions: [TileAction(title: "Review", isEnabled: !orphans.isEmpty) { model.section = .leftovers }],
                               isQuiet: orphans.isEmpty))
        tiles.append(TileModel(id: "background", systemImage: MaintenancePane.backgroundItems.systemImage, label: "Background Items",
                               value: broken.isEmpty ? "No problems" : (broken.count == 1 ? "1 broken item" : "\(broken.count) broken items"),
                               caption: broken.isEmpty ? "\(model.maintenance.launchItems.count) items checked" : "their program is gone",
                               actions: [TileAction(title: "Review") { model.section = .maintenance; model.reviewMaintenance(.backgroundItems) }],
                               isQuiet: broken.isEmpty))
        return tiles
    }
}
