import AppKit
import CommitCore
import SlopKit

/// The conflicted file on screen in the resolver: its conflicts, the choices made so far and
/// the hand-edited result. Nothing is written to disk until Mark Resolved.
struct ConflictSession: Equatable {
    var entry: StatusEntry
    var file: ConflictFile?
    /// The bytes the session was loaded from, to notice edits made in another app.
    var loadedData: Data?
    var choices: [Int: ConflictChoice] = [:]
    var isEditing = false
    var editedText = ""
    var isLoading = true

    var path: String { entry.path }
    var kind: ConflictKind { entry.conflictKind ?? .bothModified }
    var hasWork: Bool { !choices.isEmpty || isEditing }
    var conflictCount: Int { file?.conflicts.count ?? 0 }
    var isFullyResolved: Bool { isEditing ? !ConflictMarkers.present(in: Data(editedText.utf8)) : (file?.isFullyResolved(choices) ?? false) }

    /// What Mark Resolved writes.
    var result: Data? {
        if isEditing { return Data(editedText.utf8) }
        return file?.resolved(choices)
    }

    var progressText: String {
        if isEditing { return isFullyResolved ? "Edited by hand. No conflict markers left." : "Edited by hand. Conflict markers remain." }
        let total = conflictCount
        guard total > 0 else { return kind.explanation }
        if choices.count == total { return total == 1 ? "The conflict is resolved." : "All \(total) conflicts are resolved." }
        return "\(choices.count) of \(total) \(total == 1 ? "conflict" : "conflicts") resolved."
    }
}

extension ConflictChoice {
    var title: String {
        switch self {
        case .ours: "Ours"
        case .theirs: "Theirs"
        case .both: "Both"
        case .bothTheirsFirst: "Both, Theirs First"
        case .base: "Base"
        case .neither: "Neither"
        }
    }

    var undoName: String { "Use \(title)" }
}

extension RepoModel {
    /// Loads (or keeps) the resolver for a conflicted file. Choices survive refreshes unless
    /// the file changed on disk underneath them.
    func loadConflict(_ entry: StatusEntry) {
        guard let repository else { return }
        if var current = conflict, current.path == entry.path {
            current.entry = entry
            if current.hasWork { conflict = current; return }
        }
        if conflict?.path != entry.path { conflict = ConflictSession(entry: entry) }
        Task {
            let data = FileManager.default.contents(atPath: repository.root.appendingPathComponent(entry.path).path)
            let file = await repository.conflictFile(entry.path)
            guard var session = conflict, session.path == entry.path else { return }
            if session.hasWork || (session.loadedData == data && !session.isLoading) { return }
            session.file = file
            session.loadedData = data
            session.choices = [:]
            session.isLoading = false
            conflict = session
        }
    }

    func choose(_ choice: ConflictChoice?, for index: Int) {
        guard var session = conflict else { return }
        let previous = session.choices[index]
        guard previous != choice else { return }
        session.choices[index] = choice
        conflict = session
        let path = session.path
        registerUndo(choice?.undoName ?? "Change Choice") { [weak self] in
            guard let self, self.conflict?.path == path else { return }
            self.choose(previous, for: index)
        }
    }

    /// Every conflict in the file the same way.
    func chooseAll(_ choice: ConflictChoice) {
        guard var session = conflict, let file = session.file else { return }
        let previous = session.choices
        for index in file.conflicts.indices { session.choices[index] = choice }
        conflict = session
        let path = session.path
        registerUndo(choice.undoName) { [weak self] in
            guard let self, self.conflict?.path == path else { return }
            self.conflict?.choices = previous
        }
    }

    func startEditingConflict() {
        guard var session = conflict, let data = session.result else { return }
        session.editedText = String(decoding: data, as: UTF8.self)
        session.isEditing = true
        conflict = session
    }

    func stopEditingConflict() {
        conflict?.isEditing = false
        conflict?.editedText = ""
    }

    var canEditConflictAsText: Bool { conflict?.file?.isUTF8 ?? false }

    /// Writes the resolved file, stages it, and moves on to the next conflicted file.
    func markConflictResolved() {
        guard let repository, let session = conflict, let data = session.result else { return }
        let entry = session.entry
        let write: @MainActor () -> Void = { [weak self] in
            self?.mutate(.resolve, undoName: "Mark Resolved") { [weak self] in
                let snapshot = try await repository.snapshotConflict(entry.path)
                try await repository.resolveConflict(entry.path, with: data)
                await MainActor.run { if self?.conflict?.path == entry.path { self?.conflict = nil } }
                HUD.show("Resolved \(entry.nameAndFolder.name)", systemImage: "checkmark.circle")
                return { [weak self] in self?.restoreConflicts([snapshot]) }
            }
        }
        if ConflictMarkers.present(in: data) {
            confirmation = Confirmation(
                title: "“\(entry.nameAndFolder.name)” still has conflict markers",
                message: "Some conflicts have no choice yet, so their <<<<<<< and >>>>>>> lines would be committed. Mark it resolved anyway?",
                confirmTitle: "Mark Resolved", isDestructive: false, action: write)
        } else {
            write()
        }
    }

    /// Resolves the selected conflicted files with one side's whole file.
    func takeWholeFile(ours: Bool, entries: [StatusEntry]? = nil) {
        guard let repository else { return }
        let targets = entries ?? (conflict.map { [$0.entry] } ?? selectedConflicts)
        guard !targets.isEmpty else { return }
        mutate(.resolve, undoName: ours ? "Use Ours" : "Use Theirs") { [weak self] in
            var snapshots: [ConflictSnapshot] = []
            for entry in targets {
                snapshots.append(try await repository.snapshotConflict(entry.path))
                try await repository.resolveConflict(entry, takingOurs: ours)
            }
            await MainActor.run { self?.conflict = nil }
            return { [weak self] in self?.restoreConflicts(snapshots) }
        }
    }

    func restoreConflicts(_ snapshots: [ConflictSnapshot]) {
        guard let repository else { return }
        mutate(.resolve, undoName: "Mark Resolved", isUndo: true) {
            for snapshot in snapshots.reversed() { try await repository.restoreConflict(snapshot) }
            return nil
        }
    }

    var canUseMergeTool: Bool { mergeTool.isUsable && activity == nil }

    /// Opens the person's own merge tool and waits for it; git stages the file if the tool says so.
    func openInMergeTool(_ entry: StatusEntry) {
        guard let repository, let name = mergeTool.name, mergeTool.isUsable else { return }
        if conflict?.hasWork == true { conflict?.choices = [:]; conflict?.isEditing = false }
        perform(.mergeTool, title: "Waiting for \(name)", cancellable: true) { _ in
            try await repository.runMergeTool(entry.path)
        } success: { [weak self] in
            self?.conflict = nil
            HUD.show("\(name) closed", systemImage: "checkmark.circle")
        }
    }

    var mergeToolHelp: String {
        guard let name = mergeTool.name else { return "Set merge.tool in your Git config to use your own merge tool." }
        if mergeTool.needsTerminal { return "\(name) runs in a terminal. Use Open in Terminal, then git mergetool." }
        return "Resolve in \(name), your merge.tool. Commit waits until you close it."
    }
}
