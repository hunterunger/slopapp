import Foundation

/// Finds the text in an image. The app uses Vision (on device); tests use a fake.
public protocol TextRecognizer: Sendable {
    /// The lines of text in the image, top to bottom.
    func recognizeText(in imageData: Data) async throws -> [String]
}

public enum RecognizedText {
    /// Lines as one searchable string: trimmed, blank ones dropped, one per line, capped.
    public static func join(_ lines: [String], limit: Int = Clip.recognizedTextLimit) -> String {
        let text = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.count > limit ? String(text.prefix(limit)) : text
    }
}

/// Looks for text in image clips one at a time, in the background, so capture stays fast and
/// only one image is ever decoded for it at once. New copies go first; older images (from
/// before this feature, or left when Clips quit) are worked through after them, with a pause
/// between each so it never hogs the Mac.
public actor TextRecognitionQueue {
    public typealias Loader = @Sendable (UUID) async -> Data?
    /// Gets the result: the found text, or "" when there was none (or the image couldn't be read).
    public typealias Sink = @Sendable (UUID, String) async -> Void
    public typealias Gate = @Sendable () -> Bool

    private let recognizer: any TextRecognizer
    private let load: Loader
    private let deliver: Sink
    private let pause: Duration
    /// While this says false (Low Power Mode), the queue waits.
    private let canRun: Gate
    private var pending: [UUID] = []
    private var queued = Set<UUID>()
    private var worker: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(recognizer: any TextRecognizer, pause: Duration = .milliseconds(400), canRun: @escaping Gate = { true },
                load: @escaping Loader, deliver: @escaping Sink) {
        self.recognizer = recognizer
        self.pause = pause
        self.canRun = canRun
        self.load = load
        self.deliver = deliver
    }

    /// Adds images to look at. `first`: ahead of what's waiting (a new copy).
    public func enqueue(_ ids: [UUID], first: Bool = false) {
        let new = ids.filter { queued.insert($0).inserted }
        guard !new.isEmpty else { return }
        if first { pending.insert(contentsOf: new, at: 0) } else { pending.append(contentsOf: new) }
        startIfNeeded()
    }

    /// Images that were deleted: don't look at them.
    public func cancel(_ ids: Set<UUID>) {
        pending.removeAll { ids.contains($0) }
        queued.subtract(ids)
    }

    public var pendingCount: Int { pending.count }

    /// Returns once nothing is waiting (tests).
    public func waitUntilIdle() async {
        if worker == nil && pending.isEmpty { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task(priority: .utility) { await self.drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            while !canRun() {
                try? await Task.sleep(for: .seconds(30))
            }
            let id = pending.removeFirst()
            guard let data = await load(id) else {
                queued.remove(id)
                continue
            }
            // Deleted while loading?
            guard queued.contains(id) else { continue }
            let text: String
            do {
                text = RecognizedText.join(try await recognizer.recognizeText(in: data))
            } catch {
                text = ""
            }
            if queued.remove(id) != nil { await deliver(id, text) }
            if !pending.isEmpty { try? await Task.sleep(for: pause) }
        }
        worker = nil
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
