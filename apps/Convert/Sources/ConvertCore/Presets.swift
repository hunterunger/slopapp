import Foundation

/// A named set of choices (a format for each kind, quality and size) applied in one go.
/// Some come built in, for devices and common jobs; people save their own from the window's
/// current settings.
public struct Preset: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// SF Symbol shown in menus.
    public var symbol: String
    public var video: VideoTarget
    public var audio: AudioTarget
    public var image: ImageTarget
    public var quality: Quality
    public var size: SizeLimit
    /// Fit each file in this size instead of using Quality (saved presets only; optional so
    /// presets saved by older versions still load).
    public var fileSize: FileSizeLimit?
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, name: String, symbol: String = "slider.horizontal.3",
                video: VideoTarget, audio: AudioTarget, image: ImageTarget, quality: Quality,
                size: SizeLimit, fileSize: FileSizeLimit? = nil, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.video = video
        self.audio = audio
        self.image = image
        self.quality = quality
        self.size = size
        self.fileSize = fileSize
        self.isBuiltIn = isBuiltIn
    }

    /// The window's current choices as a preset to save.
    public init(name: String, from settings: ConvertSettings) {
        self.init(name: name, video: settings.video, audio: settings.audio, image: settings.image,
                  quality: settings.quality, size: settings.size, fileSize: settings.fileSize)
    }

    /// "MP4 (HEVC), M4A (AAC), HEIC · Balanced · Up to 4K".
    public var detail: String {
        "\(video.title), \(audio.title), \(image.title) · \(fileSize?.title ?? quality.title) · \(size.shortTitle)"
    }

    /// Whether `settings` already match this preset.
    public func matches(_ settings: ConvertSettings) -> Bool {
        settings.video == video && settings.audio == audio && settings.image == image
            && settings.quality == quality && settings.size == size && settings.fileSize == fileSize
    }

    /// Presets for devices and common jobs. Every Apple device since 2017 plays HEVC; the
    /// "older devices" one is for everything else.
    public static let builtIn: [Preset] = [
        Preset(id: "builtin.apple", name: "iPhone & iPad", symbol: "iphone", video: .mp4HEVC, audio: .m4a,
               image: .heic, quality: .balanced, size: .p2160, isBuiltIn: true),
        Preset(id: "builtin.appletv", name: "Apple TV 4K", symbol: "appletv", video: .mp4HEVC, audio: .m4a,
               image: .jpeg, quality: .best, size: .p2160, isBuiltIn: true),
        Preset(id: "builtin.compatible", name: "Older Devices & Windows", symbol: "pc", video: .mp4H264,
               audio: .m4a, image: .jpeg, quality: .balanced, size: .p1080, isBuiltIn: true),
        Preset(id: "builtin.web", name: "Web & Email", symbol: "envelope", video: .mp4H264, audio: .m4a,
               image: .jpeg, quality: .smaller, size: .p720, isBuiltIn: true),
        Preset(id: "builtin.chat", name: "Chat GIF", symbol: "bubble.left", video: .gif, audio: .m4a,
               image: .png, quality: .smaller, size: .original, isBuiltIn: true),
        Preset(id: "builtin.editing", name: "Video Editing", symbol: "film.stack", video: .movProRes,
               audio: .wav, image: .tiff, quality: .best, size: .original, isBuiltIn: true),
    ]

    /// The built-in presets this Mac can do (ProRes, HEVC and HEIC depend on the Mac).
    public static func available(_ capabilities: Capabilities) -> [Preset] {
        builtIn.filter { capabilities.canWrite($0.video) && capabilities.canWrite($0.image) && capabilities.canWrite($0.audio) }
    }
}

extension ConvertSettings {
    /// Takes a preset's formats, quality and size. Destination and dates stay as they are.
    public mutating func apply(_ preset: Preset) {
        video = preset.video
        audio = preset.audio
        image = preset.image
        quality = preset.quality
        size = preset.size
        fileSize = preset.fileSize
    }
}

/// The user's saved presets, newest last. Pure list operations, so they're tested.
public struct PresetLibrary: Codable, Equatable, Sendable {
    public private(set) var saved: [Preset] = []

    public init(saved: [Preset] = []) {
        self.saved = saved
    }

    /// Saves the settings under `name`. A preset with the same name (any case) is replaced.
    @discardableResult
    public mutating func save(_ name: String, from settings: ConvertSettings) -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var preset = Preset(name: trimmed.isEmpty ? "My Preset" : trimmed, from: settings)
        if let index = saved.firstIndex(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
            preset.id = saved[index].id
            saved[index] = preset
        } else {
            saved.append(preset)
        }
        return preset
    }

    public mutating func rename(_ id: Preset.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].name = trimmed
    }

    public mutating func delete(_ id: Preset.ID) {
        saved.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        let moving = fromOffsets.sorted().map { saved[$0] }
        for index in fromOffsets.sorted(by: >) { saved.remove(at: index) }
        let before = fromOffsets.filter { $0 < toOffset }.count
        saved.insert(contentsOf: moving, at: min(saved.count, max(0, toOffset - before)))
    }
}
