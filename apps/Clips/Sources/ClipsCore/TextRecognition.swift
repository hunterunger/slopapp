import Foundation

/// Finds the text in an image clip. The app uses Vision (on device, in a helper process that
/// reads the image from the history file itself); tests use a fake.
public protocol TextRecognizer: Sendable {
    /// The lines of text in the clip's image, top to bottom, or nil if the clip is gone.
    func recognizeText(inClip id: UUID) async throws -> [String]?
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
    /// Gets the result: the found text, or "" when there was none (or the image couldn't be read).
    public typealias Sink = @Sendable (UUID, String) async -> Void
    public typealias Gate = @Sendable () -> Bool

    private let recognizer: any TextRecognizer
    private let deliver: Sink
    private let pause: Duration
    /// While this says false (Low Power Mode), the queue waits.
    private let canRun: Gate
    private var pending: [UUID] = []
    private var queued = Set<UUID>()
    private var worker: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(recognizer: any TextRecognizer, pause: Duration = .milliseconds(400), canRun: @escaping Gate = { true },
                deliver: @escaping Sink) {
        self.recognizer = recognizer
        self.pause = pause
        self.canRun = canRun
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
            let text: String
            do {
                guard let lines = try await recognizer.recognizeText(inClip: id) else {
                    // The clip is gone.
                    queued.remove(id)
                    continue
                }
                text = RecognizedText.join(lines)
            } catch {
                text = ""
            }
            // Deleted while it was being read?
            if queued.remove(id) != nil { await deliver(id, text) }
            if !pending.isEmpty { try? await Task.sleep(for: pause) }
        }
        worker = nil
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
