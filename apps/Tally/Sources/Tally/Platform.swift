import AppKit
import SlopKit
import TallyCore

/// Real implementations of TallyCore's system protocols.
enum Platform {
    /// `TALLY_DATA_DIR` overrides the data folder (tests and walkthroughs use /tmp).
    static var dataDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["TALLY_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // The pipeline's launch test shouldn't write into the real data folder.
        if env["SLOPAPP_SMOKE_TEST"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("tally-smoke-\(ProcessInfo.processInfo.processIdentifier)")
        }
        return (try? AppPaths.applicationSupport)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("app.slopapp.tally")
    }

    /// With `TALLY_DATA_DIR` set (tests), open and save panels start in its parent folder.
    static var testFolder: URL? {
        guard let override = ProcessInfo.processInfo.environment["TALLY_DATA_DIR"], !override.isEmpty else { return nil }
        return URL(fileURLWithPath: override, isDirectory: true).deletingLastPathComponent()
    }

    /// The ECB's daily reference rates. `TALLY_RATES_URL` points tests at a fixture
    /// (a `file://` URL works).
    static var ratesURL: URL {
        if let override = ProcessInfo.processInfo.environment["TALLY_RATES_URL"], let url = URL(string: override) {
            return url
        }
        return URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    }
}

/// One GET, no cookies, no cache, nothing sent but the request itself.
struct ECBFetcher: RatesFetching {
    let url: URL

    func fetch() async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

@MainActor
struct SystemClipboard: Clipboard {
    /// `TALLY_CLIPBOARD_FILE` sends copies to a file instead, so tests never touch the
    /// real clipboard.
    static var testFile: URL? {
        ProcessInfo.processInfo.environment["TALLY_CLIPBOARD_FILE"].map { URL(fileURLWithPath: $0) }
    }

    func setString(_ string: String) {
        if let file = Self.testFile {
            try? Data(string.utf8).write(to: file, options: .atomic)
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(string, forType: .string)
    }
}

/// With `TALLY_PERF_LOG=1`, appends per-keystroke timings to `perf.log` in the data folder:
/// evaluation (parse + evaluate + format) and the whole change handler (plus results layout).
@MainActor
enum PerfLog {
    private static let enabled = ProcessInfo.processInfo.environment["TALLY_PERF_LOG"] == "1"
    private static var handle: FileHandle? = {
        guard enabled else { return nil }
        let url = Platform.dataDirectory.appendingPathComponent("perf.log")
        try? FileManager.default.createDirectory(at: Platform.dataDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    static func keystroke(total: Duration, evaluation: Double, lines: Int) {
        guard let handle else { return }
        let ms = Double(total.components.attoseconds) / 1e15 + Double(total.components.seconds) * 1000
        let line = String(format: "lines=%d evaluate_ms=%.3f change_ms=%.3f\n", lines, evaluation, ms)
        handle.write(Data(line.utf8))
    }
}
