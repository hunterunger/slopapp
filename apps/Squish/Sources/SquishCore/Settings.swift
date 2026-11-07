import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Everything the user can choose. Codable so the app can keep it in UserDefaults.
///
/// The compression values (quality, size, format, metadata, PDF) are what a preset holds
/// (`options`); where files go (destination, suffix, subfolder, dates) belongs to the app,
/// not to presets, so picking a preset can never switch on Replace Originals.
public struct SquishSettings: Codable, Equatable, Sendable {
    // MARK: Compression (what presets hold)

    /// JPEG / HEIC / AVIF quality, 0.1...1.
    public var quality: Double = CompressionOptions.balanced.quality
    /// PNGs are reduced to at most this many colors; `nil` keeps them lossless.
    public var pngColors: Int? = CompressionOptions.balanced.pngColors
    /// Writes JPEGs that load blurry-first on slow connections.
    public var progressiveJPEG = false
    /// How images are scaled down. Never enlarges.
    public var resize: ResizeMode = .none
    public var format: OutputFormat = .original
    public var metadata: MetadataPolicy = .removeAll
    /// Images inside PDFs: downsampled to this many dots per inch.
    public var pdfResolution: Int = CompressionOptions.balanced.pdfResolution
    /// Images inside PDFs: JPEG quality, 0.1...1.
    public var pdfQuality: Double = CompressionOptions.balanced.pdfQuality
    /// Turns PDF pages gray.
    public var pdfGrayscale = false

    /// The preset these options came from (they may have been edited since).
    public var presetID: String = CompressionPreset.balanced.id

    // MARK: Where files go

    public var destination: Destination = .alongside
    /// Added to the name of files saved next to the original: "photo-small.jpg".
    public var suffix = SquishSettings.defaultSuffix
    /// Gives compressed files the original's creation and modification dates.
    public var keepFileDates = false

    public static let defaultSuffix = "-small"
    public static let defaultSubfolder = "Compressed"

    public init() {}

    /// The compression part, as a preset stores it.
    public var options: CompressionOptions {
        get {
            CompressionOptions(quality: quality, pngColors: pngColors, progressiveJPEG: progressiveJPEG, resize: resize,
                               format: format, metadata: metadata, pdfResolution: pdfResolution,
                               pdfQuality: pdfQuality, pdfGrayscale: pdfGrayscale)
        }
        set {
            quality = newValue.quality
            pngColors = newValue.pngColors
            progressiveJPEG = newValue.progressiveJPEG
            resize = newValue.resize
            format = newValue.format
            metadata = newValue.metadata
            pdfResolution = newValue.pdfResolution
            pdfQuality = newValue.pdfQuality
            pdfGrayscale = newValue.pdfGrayscale
        }
    }

    /// Picks a preset: its options, and remembers which one it was.
    public mutating func apply(_ preset: CompressionPreset) {
        options = preset.options
        presetID = preset.id
    }

    /// The suffix actually used: never empty when saving alongside, so we can't clobber
    /// the original by accident.
    public var effectiveSuffix: String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return trimmed.isEmpty ? Self.defaultSuffix : trimmed
    }

    public var imageQuality: Double { min(1, max(0.1, quality)) }

    public var pngMode: PNGMode {
        guard let pngColors else { return .lossless }
        return .palette(colors: min(256, max(2, pngColors)))
    }

    public var pdf: PDFSettings {
        PDFSettings(resolution: min(600, max(50, pdfResolution)), quality: min(1, max(0.1, pdfQuality)),
                    grayscale: pdfGrayscale)
    }

    /// Shorthand used by older code and tests: "longest edge" resizing.
    public var maxDimension: Int? {
        get { if case .longestEdge(let px) = resize { px } else { nil } }
        set { resize = newValue.map(ResizeMode.longestEdge) ?? .none }
    }

    /// Shorthand: remove all metadata (true) or keep it all (false).
    public var stripMetadata: Bool {
        get { metadata == .removeAll }
        set { metadata = newValue ? .removeAll : .keepAll }
    }

    private enum CodingKeys: String, CodingKey {
        case quality, pngColors, progressiveJPEG, resize, format, metadata, pdfResolution, pdfQuality, pdfGrayscale
        case presetID, destination, suffix, keepFileDates
        // Before presets (0.1): a fixed preset plus custom values.
        case preset, customQuality, customPDFResolution, maxDimension, stripMetadata
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(quality, forKey: .quality)
        try c.encode(pngColors ?? 0, forKey: .pngColors)
        try c.encode(progressiveJPEG, forKey: .progressiveJPEG)
        try c.encode(resize, forKey: .resize)
        try c.encode(format, forKey: .format)
        try c.encode(metadata, forKey: .metadata)
        try c.encode(pdfResolution, forKey: .pdfResolution)
        try c.encode(pdfQuality, forKey: .pdfQuality)
        try c.encode(pdfGrayscale, forKey: .pdfGrayscale)
        try c.encode(presetID, forKey: .presetID)
        try c.encode(destination, forKey: .destination)
        try c.encode(suffix, forKey: .suffix)
        try c.encode(keepFileDates, forKey: .keepFileDates)
    }

    // Decoding is lenient: a stored value from an older version, with missing keys,
    // still loads with defaults instead of resetting everything.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SquishSettings()
        if let legacy = try? c.decode(LegacyPreset.self, forKey: .preset) {
            // 0.1 settings: map the old preset (and custom values) onto the new options.
            switch legacy {
            case .high: apply(.high)
            case .balanced: apply(.balanced)
            case .small: apply(.small)
            case .custom:
                let q = (try? c.decode(Double.self, forKey: .customQuality)) ?? 0.7
                quality = q
                pdfQuality = q
                pdfResolution = (try? c.decode(Int.self, forKey: .customPDFResolution)) ?? 144
                pngColors = q >= 0.9 ? nil : (q >= 0.5 ? 256 : 128)
                presetID = ""
            }
            if let max = try? c.decodeIfPresent(Int.self, forKey: .maxDimension) { resize = .longestEdge(max) }
            if let strip = try? c.decode(Bool.self, forKey: .stripMetadata) { metadata = strip ? .removeAll : .keepAll }
        } else {
            quality = (try? c.decode(Double.self, forKey: .quality)) ?? d.quality
            if let colors = try? c.decode(Int.self, forKey: .pngColors) { pngColors = colors > 0 ? colors : nil }
            progressiveJPEG = (try? c.decode(Bool.self, forKey: .progressiveJPEG)) ?? d.progressiveJPEG
            resize = (try? c.decode(ResizeMode.self, forKey: .resize)) ?? d.resize
            metadata = (try? c.decode(MetadataPolicy.self, forKey: .metadata)) ?? d.metadata
            pdfResolution = (try? c.decode(Int.self, forKey: .pdfResolution)) ?? d.pdfResolution
            pdfQuality = (try? c.decode(Double.self, forKey: .pdfQuality)) ?? d.pdfQuality
            pdfGrayscale = (try? c.decode(Bool.self, forKey: .pdfGrayscale)) ?? d.pdfGrayscale
            presetID = (try? c.decode(String.self, forKey: .presetID)) ?? d.presetID
        }
        format = (try? c.decode(OutputFormat.self, forKey: .format)) ?? d.format
        destination = (try? c.decode(Destination.self, forKey: .destination)) ?? d.destination
        suffix = (try? c.decode(String.self, forKey: .suffix)) ?? d.suffix
        keepFileDates = (try? c.decode(Bool.self, forKey: .keepFileDates)) ?? d.keepFileDates
    }

    private enum LegacyPreset: String, Codable { case high, balanced, small, custom }
}

/// The compression values a preset holds.
public struct CompressionOptions: Codable, Equatable, Hashable, Sendable {
    public var quality: Double
    public var pngColors: Int?
    public var progressiveJPEG = false
    public var resize: ResizeMode = .none
    public var format: OutputFormat = .original
    public var metadata: MetadataPolicy = .removeAll
    public var pdfResolution: Int
    public var pdfQuality: Double
    public var pdfGrayscale = false

    public init(quality: Double, pngColors: Int?, progressiveJPEG: Bool = false, resize: ResizeMode = .none,
                format: OutputFormat = .original, metadata: MetadataPolicy = .removeAll,
                pdfResolution: Int, pdfQuality: Double, pdfGrayscale: Bool = false) {
        self.quality = quality
        self.pngColors = pngColors
        self.progressiveJPEG = progressiveJPEG
        self.resize = resize
        self.format = format
        self.metadata = metadata
        self.pdfResolution = pdfResolution
        self.pdfQuality = pdfQuality
        self.pdfGrayscale = pdfGrayscale
    }

    // JPEG qualities sit just under the steps of Apple's encoder (0.70 → 1.87 MB,
    // 0.75 → 2.59 MB on the test photo). PDFs: 72 dpi made scanned text unreadable; 96 is
    // the floor.
    public static let high = CompressionOptions(quality: 0.80, pngColors: nil, pdfResolution: 220, pdfQuality: 0.80)
    public static let balanced = CompressionOptions(quality: 0.70, pngColors: 256, pdfResolution: 144, pdfQuality: 0.70)
    public static let small = CompressionOptions(quality: 0.55, pngColors: 128, pdfResolution: 96, pdfQuality: 0.50)
}

/// A named set of compression options. Three are built in; the user can save more.
public struct CompressionPreset: Codable, Equatable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var options: CompressionOptions

    public init(id: String = UUID().uuidString, name: String, options: CompressionOptions) {
        self.id = id
        self.name = name
        self.options = options
    }

    public static let high = CompressionPreset(id: "high", name: "High Quality", options: .high)
    public static let balanced = CompressionPreset(id: "balanced", name: "Balanced", options: .balanced)
    public static let small = CompressionPreset(id: "small", name: "Smallest File", options: .small)
    public static let builtIns = [high, balanced, small]

    public var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }

    /// One line about what it does, for menus.
    public var detail: String {
        switch id {
        case Self.high.id: "Hard to tell apart from the original"
        case Self.balanced.id: "Much smaller, looks the same on screen"
        case Self.small.id: "Smallest files, some visible loss"
        default: options.summary
        }
    }

}

extension CompressionOptions {
    /// "70% · Up to 1920 px · JPEG", for menus and help.
    public var summary: String {
        var parts = ["\(Int((quality * 100).rounded()))%"]
        if resize != .none { parts.append(resize.title) }
        if format != .original { parts.append(format.title) }
        parts.append("PDF \(pdfResolution) dpi")
        if pdfGrayscale { parts.append("Gray") }
        return parts.joined(separator: " · ")
    }
}

/// The built-in presets plus the user's own, in order. Pure; the app saves it.
public struct PresetLibrary: Codable, Equatable, Sendable {
    public private(set) var custom: [CompressionPreset] = []

    public init(custom: [CompressionPreset] = []) {
        self.custom = custom
    }

    public var all: [CompressionPreset] { CompressionPreset.builtIns + custom }

    public func preset(id: String) -> CompressionPreset? {
        all.first { $0.id == id }
    }

    /// A name no preset uses yet: "Web", then "Web 2", "Web 3"…
    public func uniqueName(_ wanted: String) -> String {
        let base = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "My Preset" : base
        let taken = Set(all.map { $0.name.lowercased() })
        if !taken.contains(name.lowercased()) { return name }
        var n = 2
        while taken.contains("\(name) \(n)".lowercased()) { n += 1 }
        return "\(name) \(n)"
    }

    @discardableResult
    public mutating func add(name: String, options: CompressionOptions) -> CompressionPreset {
        let preset = CompressionPreset(name: uniqueName(name), options: options)
        custom.append(preset)
        return preset
    }

    /// Saves new options into one of the user's presets. Built-ins can't change.
    public mutating func update(id: String, options: CompressionOptions) {
        guard let i = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[i].options = options
    }

    public mutating func rename(id: String, to name: String) {
        guard let i = custom.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != custom[i].name else { return }
        var others = self
        others.custom.remove(at: i)
        custom[i].name = others.uniqueName(trimmed)
    }

    public mutating func delete(id: String) {
        custom.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { custom[$0] }
        var rest = custom.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(rest.count, destination - before))
        custom = rest
    }
}

/// How images are made smaller. Every mode keeps the aspect ratio and never enlarges.
public enum ResizeMode: Codable, Equatable, Sendable, Hashable {
    case none
    /// The longer side becomes at most this many pixels (portrait and landscape alike).
    case longestEdge(Int)
    case width(Int)
    case height(Int)
    /// Fits inside a box.
    case fit(width: Int, height: Int)
    /// Scales to this percent of the original.
    case percent(Int)

    public static let validPixels = 16...20_000
    public static let validPercent = 1...99

    /// The size to scale an image of `size` (as displayed, upright) to, or nil to keep it.
    public func targetSize(for size: CGSize) -> CGSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale: Double
        switch self {
        case .none: return nil
        case .longestEdge(let px): scale = Double(px) / max(size.width, size.height)
        case .width(let px): scale = Double(px) / size.width
        case .height(let px): scale = Double(px) / size.height
        case .fit(let w, let h): scale = min(Double(w) / size.width, Double(h) / size.height)
        case .percent(let p): scale = Double(p) / 100
        }
        guard scale < 1, scale > 0 else { return nil }
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// Short label: "Up to 1920 px", "1280 px wide", "50%".
    public var title: String {
        switch self {
        case .none: "Full Size"
        case .longestEdge(let px): "Up to \(px) px"
        case .width(let px): "\(px) px wide"
        case .height(let px): "\(px) px high"
        case .fit(let w, let h): "Within \(w) × \(h)"
        case .percent(let p): "\(p)%"
        }
    }

    public var kind: Kind {
        switch self {
        case .none: .none
        case .longestEdge: .longestEdge
        case .width: .width
        case .height: .height
        case .fit: .fit
        case .percent: .percent
        }
    }

    /// The modes, for a picker.
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case none, longestEdge, width, height, fit, percent
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: "Don't Resize"
            case .longestEdge: "Longest Edge"
            case .width: "Width"
            case .height: "Height"
            case .fit: "Fit Within"
            case .percent: "Percentage"
            }
        }
    }

    /// Switching modes keeps the number where it makes sense.
    public func switching(to kind: Kind) -> ResizeMode {
        let px: Int = switch self {
        case .longestEdge(let v), .width(let v), .height(let v): v
        case .fit(let w, _): w
        default: 1920
        }
        switch kind {
        case .none: return .none
        case .longestEdge: return .longestEdge(px)
        case .width: return .width(px)
        case .height: return .height(px)
        case .fit:
            if case .fit = self { return self }
            return .fit(width: px, height: px)
        case .percent:
            if case .percent = self { return self }
            return .percent(50)
        }
    }
}

/// What happens to camera, location and author details.
public enum MetadataPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Location, camera, dates, author: all gone. Orientation, color profile and DPI stay.
    case removeAll
    /// Only location (GPS and place names) goes.
    case removeLocation
    case keepAll

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .removeAll: "Remove All"
        case .removeLocation: "Remove Location Only"
        case .keepAll: "Keep All"
        }
    }
}

public enum PNGMode: Equatable, Sendable {
    case lossless
    /// Reduce to at most this many colors (with dithering), like screenshot optimizers do.
    case palette(colors: Int)
}

public struct PDFSettings: Equatable, Sendable {
    /// Images inside the PDF are downsampled to this many dots per inch.
    public var resolution: Int
    /// JPEG quality for those images, 0...1.
    public var quality: Double
    /// Pages turn gray.
    public var grayscale = false

    public init(resolution: Int, quality: Double, grayscale: Bool = false) {
        self.resolution = resolution
        self.quality = quality
        self.grayscale = grayscale
    }
}

public enum OutputFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case original, jpeg, heic, png, webp, avif
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "Same as Original"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .webp: "WebP"
        case .avif: "AVIF"
        }
    }

    public var type: UTType? {
        switch self {
        case .original: nil
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        case .webp: .webP
        case .avif: UTType("public.avif")
        }
    }
}

public enum Destination: Codable, Equatable, Sendable, Hashable {
    /// Next to the original, with the suffix.
    case alongside
    /// Into a folder of this name inside the original's folder, keeping the name.
    case subfolder(String)
    /// Into this folder, keeping the name.
    case folder(URL)
    /// Replace the original; the original goes to the Trash.
    case replaceOriginal

    /// A folder name that's safe to create: no slashes, not empty, not hidden.
    public static func cleanSubfolderName(_ name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let trimmed = cleaned.drop { $0 == "." }
        return trimmed.isEmpty ? SquishSettings.defaultSubfolder : String(trimmed)
    }
}
