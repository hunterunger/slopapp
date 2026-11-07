import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SlopKit

/// Records how many jobs run at once; each job waits a little so they overlap.
actor QueueTracker {
    var running = 0
    var peak = 0
    var jobs: [FileJob] = []
    func start(_ job: FileJob) { running += 1; peak = max(peak, running); jobs.append(job) }
    func end() { running -= 1 }
}

struct QueueFailure: LocalizedError {
    var errorDescription: String? { "Couldn't read it." }
    var recoverySuggestion: String? { "Try again." }
}

struct FakeFileProcessor: FileProcessor {
    let tracker: QueueTracker
    var delay: Duration = .milliseconds(20)

    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        await tracker.start(job)
        defer { Task { await tracker.end() } }
        progress(0.5)
        try await Task.sleep(for: delay)
        let name = job.input.lastPathComponent
        if name.hasPrefix("fail") { throw QueueFailure() }
        if name.hasPrefix("same") { return .unchanged(reason: "Already small") }
        return .produced(output: job.input.deletingPathExtension().appendingPathExtension("out"), bytes: 40)
    }
}

func queueFiles(_ names: [String]) throws -> [URL] {
    let folder = URL(fileURLWithPath: "/tmp/squish-test/unit/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try names.map { name in
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: url)
        return url
    }
}

@MainActor
@Suite struct FileQueueTests {
    @Test func processesEverythingWithBoundedConcurrency() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker), acceptedTypes: [.item], maxConcurrent: 3)
        let urls = try queueFiles((1...12).map { "f\($0).jpg" })
        await queue.add(urls)
        await queue.waitUntilIdle()
        #expect(queue.items.count == 12)
        #expect(await tracker.peak == 3)
        #expect(queue.summary.produced == 12)
        #expect(queue.summary.bytesBefore == 1200)
        #expect(queue.summary.bytesAfter == 480)
        #expect(queue.summary.savedFraction == 0.6)
        #expect(queue.items.allSatisfy { $0.savedFraction == 0.6 && $0.output != nil })
    }

    @Test func ignoresDuplicatesAndOwnOutputs() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker, delay: .milliseconds(80)), acceptedTypes: [.item], maxConcurrent: 1)
        let urls = try queueFiles(["a.jpg", "b.jpg"])
        await queue.add(urls)
        await queue.add(urls + urls)
        #expect(queue.items.count == 2)
        await queue.waitUntilIdle()
        // Outputs this queue made aren't taken back in.
        let outputs = queue.items.compactMap(\.output)
        try outputs.forEach { try Data([1]).write(to: $0) }
        let added = await queue.add(outputs)
        #expect(added.isEmpty)
        // A finished file added again runs again in its own row, with its old output.
        let firstOutput = queue.items[0].output
        let again = await queue.add([urls[0]])
        #expect(again.map(\.id) == [queue.items[0].id])
        #expect(queue.items.count == 2)
        await queue.waitUntilIdle()
        #expect(queue.items[0].runs == 2)
        #expect(await tracker.jobs.last?.previousOutput == firstOutput)
        #expect(queue.summary.bytesBefore == 200)
    }

    @Test func setOutcomeReplacesAFinishedResult() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item])
        await queue.add(try queueFiles(["a.jpg"]))
        await queue.waitUntilIdle()
        queue.setOutcome(.unchanged(reason: "Put back"), for: queue.items[0])
        #expect(queue.items[0].state == .finished(.unchanged(reason: "Put back")))
        #expect(queue.summary.produced == 0)
    }

    @Test func foldersExpandInFinderOrderAndFilterTypes() async throws {
        let urls = try queueFiles(["dir/img10.png", "dir/img2.png", "dir/notes.txt", "dir/sub/deep.jpg", "dir/.hidden.png"])
        let folder = urls[0].deletingLastPathComponent()
        let found = FileIntake.expand([folder], types: [.image])
        #expect(found.map(\.url.lastPathComponent) == ["img2.png", "img10.png", "deep.jpg"])
        #expect(found.allSatisfy { $0.bytes == 100 })
        #expect(FileIntake.expand([folder, urls[1]], types: [.image]).count == 3)
        #expect(FileIntake.expand([folder], types: [.image], limit: 2).count == 2)
    }

    @Test func failuresUseTheErrorsWords() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item])
        await queue.add(try queueFiles(["fail.jpg", "same.jpg"]))
        await queue.waitUntilIdle()
        #expect(queue.items[0].state == .failed("Couldn't read it. Try again."))
        #expect(queue.items[1].state == .finished(.unchanged(reason: "Already small")))
        #expect(queue.summary.failed == 1 && queue.summary.unchanged == 1)
        #expect(queue.summary.savedFraction == nil)
    }

    @Test func cancelStopsWaitingAndWorkingFiles() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker, delay: .seconds(5)), acceptedTypes: [.item], maxConcurrent: 1)
        await queue.add(try queueFiles(["a.jpg", "b.jpg", "c.jpg"]))
        #expect(queue.items[0].state == .working(nil) || queue.items[0].isActive)
        queue.cancel(queue.items[2])
        #expect(queue.items[2].state == .cancelled)
        queue.cancelAll()
        await queue.waitUntilIdle()
        #expect(queue.items.allSatisfy { $0.state == .cancelled })
        #expect(await tracker.jobs.count <= 1) // only the first ever started
        #expect(!queue.isBusy)
    }

    @Test func retryHandsBackThePreviousOutput() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker), acceptedTypes: [.item])
        await queue.add(try queueFiles(["a.jpg"]))
        await queue.waitUntilIdle()
        let item = queue.items[0]
        let firstOutput = item.output
        queue.retry(item)
        await queue.waitUntilIdle()
        #expect(item.runs == 2)
        let jobs = await tracker.jobs
        #expect(jobs.map(\.previousOutput) == [nil, firstOutput])
    }

    @Test func removeAndClearFinished() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker(), delay: .seconds(5)), acceptedTypes: [.item], maxConcurrent: 1)
        await queue.add(try queueFiles(["a.jpg", "b.jpg"]))
        queue.remove([queue.items[0]])
        #expect(queue.items.map(\.name) == ["b.jpg"])
        queue.cancelAll()
        await queue.waitUntilIdle()
        queue.clearFinished()
        #expect(queue.items.isEmpty)
    }

    @Test func onIdleFiresOncePerBatch() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item], maxConcurrent: 2)
        var fired = 0
        queue.onIdle = { fired += 1 }
        await queue.add(try queueFiles(["a.jpg", "b.jpg", "c.jpg"]))
        await queue.waitUntilIdle()
        #expect(fired == 1)
        await queue.add(try queueFiles(["d.jpg"]))
        await queue.waitUntilIdle()
        #expect(fired == 2)
    }

    @Test func raisingConcurrencyStartsMoreWork() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker, delay: .milliseconds(100)), acceptedTypes: [.item], maxConcurrent: 1)
        await queue.add(try queueFiles(["a.jpg", "b.jpg", "c.jpg", "d.jpg"]))
        queue.maxConcurrent = 4
        await queue.waitUntilIdle()
        #expect(await tracker.peak == 4)
    }
}

@Suite struct FileQueueTextTests {
    @Test func percentRoundsDownWithARealMinus() {
        #expect(FileQueueText.percent(saved: 0.674) == "\u{2212}67%")
        #expect(FileQueueText.percent(saved: 0.999) == "\u{2212}99%")
        #expect(FileQueueText.percent(saved: 0.004) == "0%")
    }

    @Test func progressIsThrottled() {
        let box = ProgressBox()
        let progress = FileProgress { box.append($0) }
        for i in 0...1000 { progress(Double(i) / 1000) }
        #expect(box.values.count <= 52)
        #expect(box.values.last == 1)
    }

    @Test @MainActor func dropZoneChoosesFoldersOnlyWhenAsked() {
        #expect(DropZone.acceptsFolders([.image, .folder]))
        #expect(!DropZone.acceptsFolders([.image, .pdf]))
    }

    @Test func defaultConcurrencyIsSane() {
        #expect((2...8).contains(FileQueue.defaultConcurrency))
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    var values: [Double] { lock.withLock { _values } }
    func append(_ v: Double) { lock.withLock { _values.append(v) } }
}

@MainActor
@Suite struct FileQueueRetryTests {
    @Test func retryRightAfterCancelRunsAgain() async throws {
        let tracker = QueueTracker()
        let queue = FileQueue(processor: FakeFileProcessor(tracker: tracker, delay: .milliseconds(50)), acceptedTypes: [.item], maxConcurrent: 1)
        await queue.add(try queueFiles(["a.jpg"]))
        let item = queue.items[0]
        try await Task.sleep(for: .milliseconds(10))
        queue.cancel(item)
        queue.retry(item)
        // Queued again: waiting for the slot, or already in it on a fast cancel.
        let requeued: Bool
        switch item.state {
        case .waiting, .working: requeued = true
        default: requeued = false
        }
        #expect(requeued)
        await queue.waitUntilIdle()
        #expect(item.output != nil)
    }
}

/// Tracks how many jobs of each extension run at once.
actor LaneTracker {
    var running: [String: Int] = [:]
    var peak: [String: Int] = [:]
    var order: [String] = []
    func start(_ ext: String, _ name: String) {
        running[ext, default: 0] += 1
        peak[ext] = max(peak[ext] ?? 0, running[ext]!)
        order.append(name)
    }
    func end(_ ext: String) { running[ext, default: 1] -= 1 }
}

struct LaneProcessor: FileProcessor {
    let tracker: LaneTracker
    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        let ext = job.input.pathExtension
        await tracker.start(ext, job.input.lastPathComponent)
        try await Task.sleep(for: ext == "mov" ? .milliseconds(80) : .milliseconds(10))
        await tracker.end(ext)
        return .produced(output: job.input.appendingPathExtension("out"), bytes: 200)
    }
}

@MainActor
@Suite struct FileQueueOptionsTests {
    @Test func lanesCapOneKindWhileOthersRun() async throws {
        let tracker = LaneTracker()
        let queue = FileQueue(processor: LaneProcessor(tracker: tracker), acceptedTypes: [.item], maxConcurrent: 4)
        queue.lane = { $0.pathExtension == "mov" ? "video" : nil }
        queue.laneLimits = ["video": 1]
        let urls = try queueFiles(["a.mov", "b.mov", "c.mov", "1.jpg", "2.jpg", "3.jpg", "4.jpg"])
        await queue.add(urls)
        await queue.waitUntilIdle()
        #expect(await tracker.peak["mov"] == 1)
        #expect(await tracker.peak["jpg"] ?? 0 >= 2)
        // Photos queued behind the videos didn't wait for them.
        let order = await tracker.order
        #expect(order.firstIndex(of: "4.jpg")! < order.firstIndex(of: "c.mov")!)
        #expect(queue.summary.produced == 7)
    }

    @Test func unsupportedFilesBecomeFailedRowsWithTheReason() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.image])
        queue.unsupportedReason = { $0.pathExtension == "skip" ? nil : "\($0.lastPathComponent) isn't an image." }
        let urls = try queueFiles(["a.jpg", "notes.txt", "x.skip", "dir/inside.txt"])
        let folder = urls[3].deletingLastPathComponent()
        await queue.add([urls[0], urls[1], urls[2], folder])
        await queue.waitUntilIdle()
        #expect(queue.items.map(\.name) == ["a.jpg", "notes.txt"])
        #expect(queue.items[1].state == .failed("notes.txt isn't an image."))
        #expect(queue.items[1].originalBytes == 100)
        // Dropping it again doesn't add a second row.
        await queue.add([urls[1]])
        #expect(queue.items.count == 2)
    }

    @Test func withoutAReasonUnsupportedFilesAreSkipped() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.image])
        await queue.add(try queueFiles(["a.jpg", "notes.txt"]))
        await queue.waitUntilIdle()
        #expect(queue.items.map(\.name) == ["a.jpg"])
    }

    @Test func onBusyAndOnIdlePair() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item], maxConcurrent: 2)
        var events: [String] = []
        queue.onBusy = { events.append("busy") }
        queue.onIdle = { events.append("idle") }
        await queue.add(try queueFiles(["a.jpg", "b.jpg", "c.jpg"]))
        await queue.waitUntilIdle()
        queue.retry(queue.items[0])
        await queue.waitUntilIdle()
        #expect(events == ["busy", "idle", "busy", "idle"])
    }

    @Test func neutralLabelsSkipTheSavedPercent() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item])
        await queue.add(try queueFiles(["a.jpg"]))
        await queue.waitUntilIdle()
        let item = queue.items[0]
        #expect(FileQueueText.accessibilityLabel(for: item).contains("saved 60 percent"))
        let neutral = FileQueueText.accessibilityLabel(for: item, sizeStyle: .neutral, detail: "MP4 · 1920×1080")
        #expect(!neutral.contains("saved"))
        #expect(neutral.hasSuffix(", MP4 · 1920×1080"))
    }
}

struct FinalFailure: LocalizedError, FileQueueRetryHint {
    var errorDescription: String? { "Can't read this kind of file." }
    var isWorthRetrying: Bool { false }
}

struct FinalFailingProcessor: FileProcessor {
    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        if job.input.lastPathComponent.hasPrefix("final") { throw FinalFailure() }
        throw QueueFailure()
    }
}

@MainActor
@Suite struct FileQueueRetryHintTests {
    @Test func finalFailuresCantBeRetried() async throws {
        let queue = FileQueue(processor: FinalFailingProcessor(), acceptedTypes: [.image])
        queue.unsupportedReason = { _ in "Nope." }
        await queue.add(try queueFiles(["final.jpg", "again.jpg", "notes.txt"]))
        await queue.waitUntilIdle()
        #expect(queue.items.map(\.canRetry) == [false, true, false])
        #expect(queue.lastAdded == queue.items.map(\.id))
        #expect(queue.addedBatches == 1)
    }
}

@MainActor
@Suite struct FileQueueUndoTests {
    @Test func removedRowsCanBeRestoredInPlace() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item])
        await queue.add(try queueFiles(["a.jpg", "b.jpg", "c.jpg"]))
        await queue.waitUntilIdle()
        let removed = [queue.items[0], queue.items[2]]
        queue.remove(removed)
        #expect(queue.items.map(\.name) == ["b.jpg"])
        queue.restore(removed, at: [0, 2])
        #expect(queue.items.map(\.name) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(queue.items[0].output != nil)
        queue.restore(removed, at: [0, 2]) // already there: no duplicates
        #expect(queue.items.count == 3)
    }

    @Test func outputNameShowsOnlyWhenItDiffers() async throws {
        let queue = FileQueue(processor: FakeFileProcessor(tracker: QueueTracker()), acceptedTypes: [.item])
        await queue.add(try queueFiles(["a.jpg"]))
        await queue.waitUntilIdle()
        #expect(queue.items[0].outputName == "a.out")
        #expect(FileQueueText.accessibilityLabel(for: queue.items[0]).hasSuffix("written as a.out"))
        queue.setOutcome(.unchanged(reason: "x"), for: queue.items[0])
        #expect(queue.items[0].outputName == nil)
    }
}
