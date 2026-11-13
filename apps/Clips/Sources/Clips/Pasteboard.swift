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
    /// The data behind the last promised write (kept alive until the next write).
    private var promised: [PromisedPasteboardData] = []

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
        promised.removeAll()
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

    /// Writes `payload` as a promise: the data is handed over when an app asks for it, and
    /// `onRead` hears each ask (the paste stack's way of telling a paste happened). Marked
    /// transient, so clipboard managers don't read it. Returns the new change count.
    @discardableResult
    func writePromised(_ payload: ClipPayload, onRead: @escaping @MainActor () -> Void) -> Int {
        board.clearContents()
        promised = payload.items.map { PromisedPasteboardData(reps: $0, onRead: onRead) }
        let items = promised.map { provider -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: provider.types)
            item.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardType.transient))
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
