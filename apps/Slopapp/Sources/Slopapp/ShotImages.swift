import AppKit
import ImageIO
import Observation
import SlopappCore

/// Store screenshots for app pages: fetched from the feed only when a page shows them,
/// cached on disk in `~/Library/Caches/app.slopapp.slopapp/shots/<slug>/<set version>/`
/// (older sets are removed), decoded off the main thread at the size they're drawn, and
/// kept in memory for the last few only.
@MainActor
@Observable
final class ShotImages {
    enum Phase: Equatable {
        case loading
        case loaded(NSImage)
        case failed
    }

    private(set) var phases: [String: Phase] = [:]
    @ObservationIgnored private var recent: [String] = []
    @ObservationIgnored private var prunedSlugs: Set<String> = []
    @ObservationIgnored private let fetcher: any FeedFetching
    @ObservationIgnored private let urlPolicy: URLPolicy
    @ObservationIgnored private let cacheDirectory: URL?
    @ObservationIgnored private let allowsNetwork: Bool

    /// Decoded images kept in memory (about 9 MB each at gallery size).
    static let memoryLimit = 8
    /// Feed images larger than this aren't decoded (a 2880 × 1800 WebP is well under 1 MB).
    nonisolated static let maxBytes = 8_000_000

    init(fetcher: any FeedFetching, urlPolicy: URLPolicy, cacheDirectory: URL?, allowsNetwork: Bool) {
        self.fetcher = fetcher
        self.urlPolicy = urlPolicy
        self.cacheDirectory = cacheDirectory
        self.allowsNetwork = allowsNetwork
    }

    /// Key for one image at one decoded size (widths are bucketed so live resizing doesn't
    /// decode again on every frame).
    static func key(_ url: URL, maxPixel: Int) -> String {
        "\(url.absoluteString)#\(bucket(maxPixel))"
    }

    static func bucket(_ pixels: Int) -> Int {
        min(2880, max(512, Int((Double(pixels) / 256).rounded(.up)) * 256))
    }

    func phase(_ url: URL, maxPixel: Int) -> Phase? {
        phases[Self.key(url, maxPixel: maxPixel)]
    }

    /// Starts loading `url` for `app`'s current set, unless it's loaded or loading.
    func load(_ url: URL, app: FeedApp, maxPixel: Int) {
        let key = Self.key(url, maxPixel: maxPixel)
        touch(key)
        guard phases[key] == nil else { return }
        guard urlPolicy.allows(url) else {
            phases[key] = .failed
            return
        }
        phases[key] = .loading
        let cacheFile = cacheDirectory.map { ShotCache.file(in: $0, slug: app.slug, version: app.shotsVersion, url: url) }
        pruneOlderSets(of: app)
        let fetcher = fetcher, allowsNetwork = allowsNetwork, pixels = Self.bucket(maxPixel)
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                var data = cacheFile.flatMap { try? Data(contentsOf: $0) }
                if data == nil, allowsNetwork, let fetched = try? await fetcher.data(from: url), fetched.count < Self.maxBytes {
                    data = fetched
                    if let cacheFile {
                        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fetched.write(to: cacheFile, options: .atomic)
                    }
                }
                return data.flatMap { Self.decode($0, maxPixel: pixels) }
            }.value
            if let image {
                // Pixels are 2 per point at the masters' scale; the view sizes it anyway.
                phases[key] = .loaded(NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)))
            } else {
                phases[key] = .failed
            }
            evictIfNeeded()
        }
    }

    /// A fully decoded bitmap no wider than `maxPixel`, so drawing never decodes on the main thread.
    nonisolated static func decode(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func touch(_ key: String) {
        recent.removeAll { $0 == key }
        recent.append(key)
    }

    private func evictIfNeeded() {
        // Oldest first; images still loading stay.
        while recent.count > Self.memoryLimit, let index = recent.firstIndex(where: { phases[$0] != .loading }) {
            phases[recent.remove(at: index)] = nil
        }
    }

    /// Once per app per launch: delete cached sets other than the current one.
    private func pruneOlderSets(of app: FeedApp) {
        guard let cacheDirectory, prunedSlugs.insert(app.slug).inserted else { return }
        let folder = ShotCache.folder(in: cacheDirectory, slug: app.slug, version: app.shotsVersion).deletingLastPathComponent()
        let slug = app.slug, version = app.shotsVersion
        Task.detached(priority: .utility) {
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for stale in ShotCache.stale(in: cacheDirectory, slug: slug, version: version, existing: existing) {
                try? FileManager.default.removeItem(at: stale)
            }
        }
    }
}
