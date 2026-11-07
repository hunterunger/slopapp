import Foundation
import SlopKit
import SquishCore

// Headless benchmark of the real pipeline (FileQueue + Squisher), no UI.
//
//   SquishBench <folder> [--concurrency N] [--preset high|balanced|small] [--format jpeg|heic|png]
//                        [--max 2000] [--out <folder under /tmp>]
//
// Writes outputs into --out (default: <folder>-out next to it). Only use on test fixtures.

struct Processor: FileProcessor {
    let squisher: Squisher
    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        switch try await squisher.run(job.input, previousOutput: job.previousOutput, progress: { progress($0) }) {
        case .saved(let url, let bytes): .produced(output: url, bytes: bytes)
        case .keptOriginal(let reason): .unchanged(reason: reason)
        case .skipped(let reason): .skipped(reason: reason)
        }
    }
}

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let concurrency = option("--concurrency").flatMap(Int.init) ?? FileQueue.defaultConcurrency
var settings = SquishSettings()
settings.apply(option("--preset").flatMap { id in CompressionPreset.builtIns.first { $0.id == id } } ?? .balanced)
settings.format = option("--format").flatMap(OutputFormat.init(rawValue:)) ?? .original
settings.maxDimension = option("--max").flatMap(Int.init)
let outOption = option("--out")
guard let folder = args.first.map({ URL(fileURLWithPath: $0) }), folder.path.hasPrefix("/tmp/") || folder.path.hasPrefix("/private/tmp/") else {
    print("usage: SquishBench /tmp/<folder> [--concurrency N] [--preset P] [--format F] [--max PX] [--out /tmp/<folder>]")
    exit(2)
}
let out = URL(fileURLWithPath: outOption ?? folder.path + "-out")
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
settings.destination = .folder(out)

let start = Date()
let (summary, items) = await MainActor.run { () -> Task<(FileQueueSummary, [(String, String)]), Never> in
    let queue = FileQueue(processor: Processor(squisher: Squisher(settings: settings)),
                          acceptedTypes: SquishTypes.accepted, maxConcurrent: concurrency)
    return Task { @MainActor in
        await queue.add([folder])
        await queue.waitUntilIdle()
        let rows = queue.items.map { item -> (String, String) in
            switch item.state {
            case .finished(.produced(_, let bytes)):
                return (item.name, "\(item.originalBytes ?? 0) -> \(bytes) (\(FileQueueText.percent(saved: item.savedFraction ?? 0)))")
            case .finished(.unchanged(let r)), .finished(.skipped(let r)): return (item.name, r)
            case .failed(let m): return (item.name, "FAILED: \(m)")
            default: return (item.name, "\(item.state)")
            }
        }
        return (queue.summary, rows)
    }
}.value
let elapsed = Date().timeIntervalSince(start)
if items.count <= 30 { for (name, line) in items { print("  \(name): \(line)") } }
print(String(format: "%d files in %.2f s (%.1f files/s) with concurrency %d; produced %d, unchanged %d, failed %d; %@ -> %@ (saved %@)",
             summary.total, elapsed, Double(summary.total) / elapsed, concurrency, summary.produced, summary.unchanged, summary.failed,
             FileQueueText.bytes(summary.bytesBefore), FileQueueText.bytes(summary.bytesAfter),
             FileQueueText.percent(saved: summary.savedFraction ?? 0)))
