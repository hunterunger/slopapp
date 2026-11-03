import Foundation
import UniformTypeIdentifiers

/// Everything the user can choose. Codable so the app can keep it in UserDefaults.
public struct SquishSettings: Codable, Equatable, Sendable {
    public var preset: QualityPreset = .balanced
    /// Used when `preset == .custom`. 0.1...1.
    public var customQuality: Double = 0.7
    /// Used when `preset == .custom`. Image resolution inside PDFs, in dots per inch.
    public var customPDFResolution: Int = 144
    /// Longest edge in pixels. Only ever shrinks; `nil` keeps the size.
    public var maxDimension: Int?
    public var format: OutputFormat = .original
    /// Removes camera, location and editing metadata. Keeps orientation and color profile.
    public var stripMetadata = true
    public var destination: Destination = .alongside
    /// Added to the name of files saved next to the original: "photo-small.jpg".
    public var suffix = SquishSettings.defaultSuffix

    public static let defaultSuffix = "-small"

    public init() {}

    /// The suffix actually used: never empty when saving alongside, so we can't clobber
    /// the original by accident.
    public var effectiveSuffix: String {
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return trimmed.isEmpty ? Self.defaultSuffix : trimmed
    }

    public var imageQuality: Double {
        switch preset {
        case .high: 0.80
        case .balanced: 0.70
        case .small: 0.55
        case .custom: min(1, max(0.1, customQuality))
        }
    }

    /// PNG: palette reduction unless the user asked for (near) lossless.
    public var pngMode: PNGMode {
        switch preset {
        case .high: .lossless
        case .balanced: .palette(colors: 256)
        case .small: .palette(colors: 128)
        case .custom: customQuality >= 0.9 ? .lossless : .palette(colors: customQuality >= 0.5 ? 256 : 128)
        }
    }

    public var pdf: PDFSettings {
        switch preset {
        case .high: PDFSettings(resolution: 220, quality: 0.80)
        case .balanced: PDFSettings(resolution: 144, quality: 0.70)
        case .small: PDFSettings(resolution: 96, quality: 0.50)
        case .custom: PDFSettings(resolution: min(600, max(50, customPDFResolution)), quality: imageQuality)
        }
    }

    // Decoding is lenient: a stored value from an older version, with missing keys,
    // still loads with defaults instead of resetting everything.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SquishSettings()
        preset = (try? c.decode(QualityPreset.self, forKey: .preset)) ?? d.preset
        customQuality = (try? c.decode(Double.self, forKey: .customQuality)) ?? d.customQuality
        customPDFResolution = (try? c.decode(Int.self, forKey: .customPDFResolution)) ?? d.customPDFResolution
        maxDimension = try? c.decodeIfPresent(Int.self, forKey: .maxDimension)
        format = (try? c.decode(OutputFormat.self, forKey: .format)) ?? d.format
        stripMetadata = (try? c.decode(Bool.self, forKey: .stripMetadata)) ?? d.stripMetadata
        destination = (try? c.decode(Destination.self, forKey: .destination)) ?? d.destination
        suffix = (try? c.decode(String.self, forKey: .suffix)) ?? d.suffix
    }
}

public enum QualityPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case high, balanced, small, custom
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .high: "High Quality"
        case .balanced: "Balanced"
        case .small: "Smallest File"
        case .custom: "Custom"
        }
    }

    /// Short form for the options bar.
    public var shortTitle: String {
        switch self {
        case .high: "High"
        case .balanced: "Balanced"
        case .small: "Smallest"
        case .custom: "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .high: "Hard to tell apart from the original"
        case .balanced: "Much smaller, looks the same on screen"
        case .small: "Smallest files, some visible loss"
        case .custom: "Pick the quality yourself"
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

public enum Destination: Codable, Equatable, Sendable {
    /// Next to the original, with the suffix.
    case alongside
    /// Into this folder, keeping the name.
    case folder(URL)
    /// Replace the original; the original goes to the Trash.
    case replaceOriginal
}
