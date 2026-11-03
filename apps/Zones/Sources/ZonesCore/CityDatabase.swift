import Compression
import Foundation

/// A city from the bundled GeoNames list.
public struct City: Hashable, Sendable {
    public var name: String
    /// Where this city's folded search keys ("name|ascii name|alternate names...") sit in
    /// `CityDatabase.keyBytes`, and where the first key (the name) ends.
    var keyStart: Int32
    var keyEnd: Int32
    var nameEnd: Int32
    public var countryCode: String
    public var region: String
    public var population: Int
    public var timeZoneID: String
}

/// The bundled city list (GeoNames cities15000, CC BY 4.0), loaded on demand.
public final class CityDatabase: Sendable {
    public let cities: [City]
    /// Every city's search keys, UTF-8, back to back (searched with memmem: fast).
    let keyBytes: [UInt8]

    init(cities: [City], keyBytes: [UInt8]) {
        self.cities = cities
        self.keyBytes = keyBytes
    }

    public enum LoadError: Error, Equatable {
        case missingFile, unreadable
    }

    /// Parses the TSV (see Tools/build-cities.py).
    public convenience init(tsv: String) {
        self.init(utf8: Data(tsv.utf8))
    }

    /// Parses UTF-8 TSV bytes in one pass without intermediate arrays of lines or fields,
    /// so loading doesn't balloon memory. Region and zone strings are shared between cities.
    convenience init(utf8 data: Data) {
        var cities: [City] = []
        cities.reserveCapacity(35_000)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count * 6 / 10)
        // Interned by a hash of the raw bytes, so repeated regions and zones don't create a
        // temporary String per line.
        var interned: [Int: [String]] = [:]
        func intern(_ buffer: UnsafeRawBufferPointer.SubSequence) -> String {
            var hasher = Hasher()
            hasher.combine(bytes: UnsafeRawBufferPointer(rebasing: buffer))
            let key = hasher.finalize()
            if let existing = interned[key]?.first(where: { $0.utf8.elementsEqual(buffer) }) { return existing }
            let value = String(decoding: buffer, as: UTF8.self)
            interned[key, default: []].append(value)
            return value
        }
        func integer(_ buffer: UnsafeRawBufferPointer.SubSequence) -> Int {
            buffer.reduce(0) { value, byte in
                (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ? value * 10 + Int(byte - UInt8(ascii: "0")) : value
            }
        }
        var fields: [Range<Int>] = []
        fields.reserveCapacity(8)
        let tab = UInt8(ascii: "\t"), newline = UInt8(ascii: "\n"), bar = UInt8(ascii: "|")
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var lineStart = 0
            while lineStart < raw.count {
                var lineEnd = lineStart
                while lineEnd < raw.count && raw[lineEnd] != newline { lineEnd += 1 }
                defer { lineStart = lineEnd + 1 }
                guard lineEnd > lineStart, raw[lineStart] != UInt8(ascii: "#") else { continue }
                fields.removeAll(keepingCapacity: true)
                var fieldStart = lineStart
                for index in lineStart...lineEnd where index == lineEnd || raw[index] == tab {
                    fields.append(fieldStart..<index)
                    fieldStart = index + 1
                }
                guard fields.count >= 6 else { continue }
                let start = bytes.count
                let keys = raw[fields[1]]
                bytes.append(contentsOf: keys)
                let nameLength = (keys.firstIndex(of: bar) ?? keys.endIndex) - keys.startIndex
                let population = integer(raw[fields[4]])
                cities.append(City(
                    name: String(decoding: raw[fields[0]], as: UTF8.self),
                    keyStart: Int32(start),
                    keyEnd: Int32(bytes.count),
                    nameEnd: Int32(start + nameLength),
                    countryCode: intern(raw[fields[2]]),
                    region: intern(raw[fields[3]]),
                    population: population,
                    timeZoneID: intern(raw[fields[5]])
                ))
            }
        }
        self.init(cities: cities, keyBytes: bytes)
    }

    /// Reads the raw-DEFLATE file Tools/build-cities.py writes. The compressed file is
    /// memory-mapped and decompressed into one scratch buffer that's freed right after
    /// parsing, so loading leaves only the parsed list behind (NSData's decompression keeps
    /// several MB of buffers around).
    public static func load(from url: URL) throws -> CityDatabase {
        guard let compressed = try? Data(contentsOf: url, options: .alwaysMapped), !compressed.isEmpty else {
            throw LoadError.missingFile
        }
        // The text is about 2.4× the compressed size; leave generous room (untouched
        // pages of the scratch buffer cost nothing).
        let capacity = compressed.count * 6
        // mmap rather than malloc so the pages go straight back to the system when unmapped.
        guard let mapped = mmap(nil, capacity, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
              mapped != MAP_FAILED else { throw LoadError.unreadable }
        defer { munmap(mapped, capacity) }
        let scratch = mapped.assumingMemoryBound(to: UInt8.self)
        let length = compressed.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(scratch, capacity, base, source.count, nil, COMPRESSION_ZLIB)
        }
        guard length > 0, length < capacity else { throw LoadError.unreadable }
        let text = Data(bytesNoCopy: scratch, count: length, deallocator: .none)
        return CityDatabase(utf8: text)
    }

    /// Where the bundled file is: in the .app's Resources (release builds), next to the
    /// executable (`swift run`), or in the SwiftPM build folder (tests).
    public static var bundledURL: URL? {
        let bundleName = "Zones_ZonesCore.bundle"
        let file = "cities.tsv.deflate"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(bundleName))
        }
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executable.appendingPathComponent(bundleName))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        for directory in candidates {
            for url in [directory.appendingPathComponent(file),
                        directory.appendingPathComponent("Contents/Resources/\(file)")]
            where FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return Bundle.module.url(forResource: "cities.tsv", withExtension: "deflate")
    }
}
