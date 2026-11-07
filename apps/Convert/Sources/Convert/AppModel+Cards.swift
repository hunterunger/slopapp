import AppKit
import ConvertCore
import SlopKit

/// What the cards, group headers and status bar need: grouping, per-file options, starting,
/// removing, presets and merging.
extension AppModel {
    // MARK: Cards and groups

    /// Every card in order: files in the queue, then files waiting for Start.
    var entries: [CardEntry] {
        queue.items.map(CardEntry.item) + staged.map(CardEntry.staged)
    }

    /// What a file is: what it turned out to be once read, else its type.
    func kind(of url: URL) -> MediaKind? {
        facts(for: url).info?.kind ?? MediaTypes.kind(of: url)
    }

    /// Cards by kind, in a fixed order: Video, Audio, Images, Other.
    var groups: [CardGroup] {
        var byKind: [String: [CardEntry]] = [:]
        for entry in entries {
            byKind[kind(of: entry.input)?.rawValue ?? "other", default: []].append(entry)
        }
        let order: [MediaKind?] = [.video, .audio, .image, nil]
        return order.compactMap { kind in
            guard let entries = byKind[kind?.rawValue ?? "other"], !entries.isEmpty else { return nil }
            return CardGroup(kind: kind, entries: entries)
        }
    }

    var isEmpty: Bool { queue.items.isEmpty && staged.isEmpty }

    func entry(_ id: UUID) -> CardEntry? {
        entries.first { $0.id == id }
    }

    var selectedEntries: [CardEntry] {
        entries.filter { selection.contains($0.id) }
    }

    /// The selection, or this card when it isn't part of the selection (right-click rules).
    func targets(for entry: CardEntry) -> [CardEntry] {
        selection.contains(entry.id) ? selectedEntries : [entry]
    }

    // MARK: Per-file options

    func options(for url: URL) -> FileOptions {
        facts(for: url).options
    }

    /// Changes options for some files. A file that already finished (or is converting) is
    /// converted again when "Start converting as soon as files are added" is on; otherwise
    /// it waits for Start like a new file.
    func updateOptions(for entries: [CardEntry], _ change: (inout FileOptions) -> Void) {
        for entry in entries {
            let row = facts(for: entry.input)
            var options = row.options
            change(&options)
            guard options != row.options else { continue }
            row.options = options
            optionsBook.set(options, for: entry.input)
            guard autoStart, let item = entry.item else { continue }
            switch item.state {
            case .working:
                queue.cancel(item)
                queue.retry(item)
            case .finished, .failed, .cancelled:
                if item.canRetry { queue.retry(item) }
            case .waiting:
                break
            }
        }
    }

    /// The format a file becomes: its own, or its group's.
    func targetTitle(for url: URL, kind: MediaKind) -> String {
        settings.applying(options(for: url)).targetTitle(for: kind)
    }

    /// The format choices for a file's card menu.
    func formatEntries(for targets: [CardEntry], kind: MediaKind) -> [BarMenuEntry] {
        let options = targets.map { self.options(for: $0.input) }
        let own = options.contains { $0.hasOwnFormat(for: kind) }
        var entries: [BarMenuEntry] = [
            .choice("Same as Group (\(settings.targetTitle(for: kind)))", detail: nil, isOn: !own) { [self] in
                updateOptions(for: targets) {
                    switch kind {
                    case .video: $0.video = nil
                    case .audio: $0.audio = nil
                    case .image: $0.image = nil
                    }
                }
            },
            .separator,
        ]
        func isOn(_ check: (FileOptions) -> Bool) -> Bool { own && options.allSatisfy(check) }
        switch kind {
        case .video:
            for target in capabilities.videoTargets {
                entries.append(.choice(target.title, detail: target.detail, isOn: isOn { $0.video == target }) { [self] in
                    updateOptions(for: targets) { $0.video = target }
                })
                if target == .gif { entries.append(.separator) }
            }
        case .audio:
            for target in AudioTarget.allCases {
                entries.append(.choice(target.title, detail: target.detail, isOn: isOn { $0.audio == target }) { [self] in
                    updateOptions(for: targets) { $0.audio = target }
                })
            }
        case .image:
            for target in capabilities.imageTargets {
                entries.append(.choice(target.title, detail: target.detail, isOn: isOn { $0.image == target }) { [self] in
                    updateOptions(for: targets) { $0.image = target }
                })
            }
        }
        return entries
    }

    /// Turn and flip choices for a card (and the File menu).
    func turnEntries(for targets: [CardEntry]) -> [BarMenuEntry] {
        let current = targets.first.map { options(for: $0.input).transform } ?? .identity
        return [
            .action("Rotate Right") { [self] in updateOptions(for: targets) { $0.transform = $0.transform.rotatedRight() } },
            .action("Rotate Left") { [self] in updateOptions(for: targets) { $0.transform = $0.transform.rotatedLeft() } },
            .action("Flip Horizontal") { [self] in updateOptions(for: targets) { $0.transform = $0.transform.flippedHorizontally() } },
            .action("Flip Vertical") { [self] in updateOptions(for: targets) { $0.transform = $0.transform.flippedVertically() } },
            .separator,
            .choice("Original Orientation", detail: nil, isOn: current.isIdentity) { [self] in
                updateOptions(for: targets) { $0.transform = .identity }
            },
            .note(current.title),
        ]
    }

    /// Which sound a video keeps.
    func soundEntries(for entry: CardEntry) -> [BarMenuEntry] {
        let info = facts(for: entry.input).info
        let current = options(for: entry.input).sound
        let tracks = info?.audioTracks ?? []
        var entries: [BarMenuEntry] = [
            .choice(tracks.count > 1 ? "All Tracks, Mixed" : "Keep Sound", detail: nil, isOn: current == .all) { [self] in
                updateOptions(for: [entry]) { $0.sound = .all }
            },
        ]
        if tracks.count > 1 {
            entries.append(.separator)
            for track in tracks {
                entries.append(.choice(track.title, detail: nil, isOn: current == .track(track.index)) { [self] in
                    updateOptions(for: [entry]) { $0.sound = .track(track.index) }
                })
            }
        }
        entries.append(.separator)
        entries.append(.choice("No Sound", detail: "Removes the sound", isOn: current == .none) { [self] in
            updateOptions(for: [entry]) { $0.sound = .none }
        })
        return entries
    }

    func resetOptions(for entries: [CardEntry]) {
        updateOptions(for: entries) { $0 = FileOptions() }
    }

    /// Whether the trim tool applies (videos and sound files, not animated images or photos).
    func canTrim(_ entry: CardEntry) -> Bool {
        guard let info = facts(for: entry.input).info else { return false }
        return info.kind != .image && !info.isAnimatedImage && info.duration > 0.2
    }

    func canTurn(_ entry: CardEntry) -> Bool {
        guard let info = facts(for: entry.input).info else { return false }
        return info.kind == .image || (info.kind == .video && !info.isAnimatedImage)
    }

    // MARK: Removing

    /// Removes cards. Queue rows get Undo (see `removeFromList`); waiting cards just go.
    func remove(_ entries: [CardEntry], actionName: String = "Remove from List") {
        let ids = Set(entries.map(\.id))
        staged.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        let items = entries.compactMap(\.item)
        if !items.isEmpty { removeFromList(items, actionName: actionName) }
    }

    func removeStagedForClear() {
        staged.removeAll()
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        settings.apply(preset)
        HUD.show("Using “\(preset.name)”", systemImage: preset.symbol)
    }

    /// Asks for a name and saves the current formats, quality and size.
    func saveCurrentAsPreset() {
        let alert = NSAlert()
        alert.messageText = "Save Current Settings as a Preset"
        alert.informativeText = "\(settings.video.title), \(settings.audio.title), \(settings.image.title) · \(settings.quality.title) · \(settings.size.shortTitle)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name"
        field.setAccessibilityLabel("Preset name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let preset = presets.save(field.stringValue, from: settings)
        HUD.show("Saved “\(preset.name)”", systemImage: "checkmark.circle")
    }

    func presetEntries() -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = Preset.available(capabilities).map { preset in
            .choice(preset.name, detail: preset.detail, isOn: preset.matches(settings)) { [self] in apply(preset) }
        }
        if !presets.saved.isEmpty {
            entries.append(.separator)
            for preset in presets.saved {
                entries.append(.choice(preset.name, detail: preset.detail, isOn: preset.matches(settings)) { [self] in apply(preset) })
            }
        }
        entries.append(.separator)
        entries.append(.action("Save Current Settings as Preset…") { [self] in saveCurrentAsPreset() })
        return entries
    }

    // MARK: Merging

    /// Files that can be merged from these cards: videos or sound files, in list order.
    func mergeable(_ entries: [CardEntry]) -> [URL] {
        // Only files that were read (not damaged, not MKV) and play over time.
        let urls = entries.map(\.input).filter { url in
            guard let info = facts(for: url).info, facts(for: url).readError == nil else { return false }
            return info.kind != .image && !info.isAnimatedImage
        }
        return urls.count >= 2 ? urls : []
    }

    func merge(_ entries: [CardEntry]) {
        let urls = mergeable(entries)
        guard !urls.isEmpty else {
            HUD.show("Select two or more videos or sound files", systemImage: "rectangle.stack.badge.plus")
            return
        }
        merging = urls
    }

    // MARK: Grid keyboard

    /// Moves the selection by `offset` cards (arrow keys); with `extend`, grows it.
    func moveSelection(by offset: Int, extend: Bool) {
        let ordered = groups.filter { !collapsedGroups.contains($0.id) }.flatMap(\.entries).map(\.id)
        guard !ordered.isEmpty else { return }
        let current = ordered.lastIndex { selection.contains($0) }
        let next = current.map { min(max(0, $0 + offset), ordered.count - 1) } ?? 0
        if extend { selection.insert(ordered[next]) } else { selection = [ordered[next]] }
        selectionLead = ordered[next]
    }
}
