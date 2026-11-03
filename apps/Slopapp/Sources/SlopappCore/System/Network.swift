import Foundation

/// URLSession without cookies, caches or identifying headers. The only request the
/// launcher makes on its own is a plain GET of the feed: no IDs, no telemetry.
public final class Network: FeedFetching, Downloading, Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 15 * 60
        config.httpAdditionalHeaders = ["User-Agent": "Slopapp"]
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func data(from url: URL) async throws -> Data {
        if url.isFileURL {
            do { return try Data(contentsOf: url) } catch { throw NetworkError.notFound }
        }
        do {
            let (data, response) = try await session.data(from: url)
            try Self.check(response)
            return data
        } catch let error as NetworkError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    public func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { throw NetworkError.notFound }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            progress(1)
            return
        }
        let delegate = ProgressDelegate(onProgress: progress)
        do {
            let (file, response) = try await session.download(from: url, delegate: delegate)
            defer { try? FileManager.default.removeItem(at: file) }
            try Self.check(response)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            progress(1)
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 404, 410: throw NetworkError.notFound
        default: throw NetworkError.server(http.statusCode)
        }
    }

    private static func map(_ error: any Error) -> any Error {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return NetworkError.other(nsError.localizedDescription) }
        switch nsError.code {
        case NSURLErrorCancelled: return CancellationError()
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorDNSLookupFailed,
             NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
            return NetworkError.offline
        case NSURLErrorFileDoesNotExist, NSURLErrorResourceUnavailable:
            return NetworkError.notFound
        default:
            return NetworkError.other(nsError.localizedDescription)
        }
    }
}

/// Reports download progress in whole percent steps (KVO fires far more often than that).
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private let lock = NSLock()
    private var lastPercent = -1

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
    }

    private func report(_ fraction: Double) {
        let percent = Int(fraction * 100)
        let changed = lock.withLock { () -> Bool in
            guard percent != lastPercent else { return false }
            lastPercent = percent
            return true
        }
        if changed { onProgress(fraction) }
    }
}
