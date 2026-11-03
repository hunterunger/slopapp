import AppKit
import ClipsCore

/// The clipboard as Clips uses it. The system implementation wraps an `NSPasteboard`
/// (the general one, or a private named one for tests).
@MainActor
protocol Pasteboard: AnyObject {
    var name: NSPasteboard.Name { get }
    var changeCount: Int { get }
    /// Every type on every item, without reading any data.
    func allTypes() -> Set<String>
    /// The value of `org.nspasteboard.source`, if the writing app set it.
    func declaredSource() -> String?
    /// Replaces the contents. Returns the new change count.
    @discardableResult func write(_ payload: ClipPayload) -> Int
}

@MainActor
final class SystemPasteboard: Pasteboard {
    let board: NSPasteboard

    init(name: String?) {
        board = name.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }

    var name: NSPasteboard.Name { board.name }
    var changeCount: Int { board.changeCount }

    func allTypes() -> Set<String> {
        var types = Set<String>()
        for item in board.pasteboardItems ?? [] {
            types.formUnion(item.types.map(\.rawValue))
        }
        return types
    }

    func declaredSource() -> String? {
        board.string(forType: NSPasteboard.PasteboardType(PasteboardType.source))
    }

    @discardableResult
    func write(_ payload: ClipPayload) -> Int {
        board.clearContents()
        let items = payload.items.map { reps -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for rep in reps {
                item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
            }
            return item
        }
        board.writeObjects(items)
        return board.changeCount
    }

    /// Reads the stored types of every item. Safe to call off the main thread (NSPasteboard
    /// is thread-safe); used there so big images never block the UI.
    nonisolated static func snapshot(named name: NSPasteboard.Name) -> (snapshot: PasteboardSnapshot, changeCount: Int) {
        let board = NSPasteboard(name: name)
        let changeCount = board.changeCount
        var items: [[Representation]] = []
        for item in board.pasteboardItems ?? [] {
            let available = Set(item.types.map(\.rawValue))
            var reps: [Representation] = []
            let hasFile = available.contains(PasteboardType.fileURL)
            let hasText = available.contains(PasteboardType.string)
            for type in PasteboardType.stored where available.contains(type) {
                // Skip big image renderings when the item is really text or a file.
                if PasteboardType.imageTypes.contains(type), hasFile || hasText { continue }
                // One image format is enough.
                if PasteboardType.imageTypes.contains(type), reps.contains(where: { PasteboardType.imageTypes.contains($0.type) }) { continue }
                if let data = item.data(forType: NSPasteboard.PasteboardType(type)) {
                    reps.append(Representation(type: type, data: data))
                }
            }
            if !reps.isEmpty { items.append(reps) }
        }
        return (PasteboardSnapshot(items: items), changeCount)
    }
}
