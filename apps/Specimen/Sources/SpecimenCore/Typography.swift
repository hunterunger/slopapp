import Foundation

// MARK: Variable fonts

/// Positions on a variable font's axes (the Variables tab's sliders).
public struct VariationSettings: Hashable, Sendable {
    public let axes: [VariationAxis]
    /// Axis tag → value. Missing tags are at their default.
    public private(set) var values: [String: Double]

    public init(axes: [VariationAxis], values: [String: Double] = [:]) {
        self.axes = axes
        self.values = [:]
        for (tag, value) in values { set(tag, to: value) }
    }

    public func value(_ tag: String) -> Double {
        values[tag] ?? axes.first { $0.tag == tag }?.defaultValue ?? 0
    }

    /// Sets an axis, clamped to its range. Unknown tags are ignored.
    public mutating func set(_ tag: String, to value: Double) {
        guard let axis = axes.first(where: { $0.tag == tag }) else { return }
        values[tag] = min(max(value, axis.minimum), axis.maximum)
    }

    public mutating func reset() { values = [:] }

    /// Every axis at its default.
    public var isDefault: Bool {
        axes.allSatisfy { abs(value($0.tag) - $0.defaultValue) < 0.0001 }
    }

    /// CoreText's variation dictionary: axis identifier → value, for axes off their default.
    public var coreTextVariation: [Int: Double] {
        var result: [Int: Double] = [:]
        for axis in axes {
            let current = value(axis.tag)
            if abs(current - axis.defaultValue) > 0.0001, let id = VariationAxis.identifier(fromTag: axis.tag) {
                result[id] = current
            }
        }
        return result
    }

    /// Every axis's value (identifier → value), for drawing a named instance moved off its
    /// own position: the default of one axis may differ from the instance's value.
    public var coreTextValues: [Int: Double] {
        var result: [Int: Double] = [:]
        for axis in axes {
            if let id = VariationAxis.identifier(fromTag: axis.tag) { result[id] = value(axis.tag) }
        }
        return result
    }

    /// `font-variation-settings: "wght" 628, "wdth" 87.5;` for every axis.
    public var css: String {
        let parts = axes.map { "\"\($0.tag)\" \(VariationAxis.format(value($0.tag)))" }
        return "font-variation-settings: \(parts.joined(separator: ", "));"
    }

    /// Settings from a CoreText variation dictionary (a named instance's values).
    public static func from(axes: [VariationAxis], coreText: [Int: Double]) -> VariationSettings {
        var settings = VariationSettings(axes: axes)
        for (id, value) in coreText { settings.set(VariationAxis.tag(from: id), to: value) }
        return settings
    }

    /// `count` evenly spaced values across an axis (the sample glyphs above each slider).
    public static func stops(for axis: VariationAxis, count: Int = 5) -> [Double] {
        guard count > 1, axis.maximum > axis.minimum else { return [axis.defaultValue] }
        return (0..<count).map { axis.minimum + (axis.maximum - axis.minimum) * Double($0) / Double(count - 1) }
    }
}

extension VariationAxis {
    /// 'wght' → 0x77676874, the integer CoreText uses.
    public static func identifier(fromTag tag: String) -> Int? {
        let bytes = Array(tag.utf8)
        if bytes.count == 4 {
            return bytes.reduce(0) { $0 << 8 | Int($1) }
        }
        return Int(tag)
    }
}

// MARK: Characters

/// The groups in the Characters tab.
public enum CharacterGroup: String, CaseIterable, Sendable, Identifiable {
    case all, letters, numbers, punctuation, symbols, currency, marks, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .letters: "Letters"
        case .numbers: "Numbers"
        case .punctuation: "Punctuation"
        case .symbols: "Symbols"
        case .currency: "Currency"
        case .marks: "Marks"
        case .other: "Other"
        }
    }

    public static func of(_ scalar: Unicode.Scalar) -> CharacterGroup {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: .letters
        case .decimalNumber, .letterNumber, .otherNumber: .numbers
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: .punctuation
        case .currencySymbol: .currency
        case .mathSymbol, .modifierSymbol, .otherSymbol: .symbols
        case .nonspacingMark, .spacingMark, .enclosingMark: .marks
        default: .other
        }
    }
}

/// The characters a font maps, for the Characters tab. Pure: give it the font's membership test.
public enum CharacterCatalog {
    /// Every mapped, visible code point, in Unicode order. `planes` are the Unicode planes
    /// the font has anything in (skips 64k lookups per empty plane); `limit` caps huge CJK fonts.
    public static func characters(planes: [Int] = Array(0...16), limit: Int = 70_000, contains: (UInt32) -> Bool) -> [UInt32] {
        var result: [UInt32] = []
        for plane in planes where (0...16).contains(plane) {
            let start = UInt32(plane) << 16
            for value in start..<(start + 0x10000) {
                guard contains(value), let scalar = Unicode.Scalar(value), isVisible(scalar) else { continue }
                result.append(value)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Not controls, formats, spaces, private use or surrogates.
    public static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .spaceSeparator, .lineSeparator, .paragraphSeparator: false
        default: true
        }
    }

    /// Characters in `group` matching `search`: the character itself, part of its Unicode
    /// name ("alpha", "euro sign"), or a code point ("U+20AC", "20ac").
    public static func filter(_ characters: [UInt32], group: CharacterGroup, search: String) -> [UInt32] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let byGroup = group == .all ? characters : characters.filter { Unicode.Scalar($0).map(CharacterGroup.of) == group }
        guard !query.isEmpty else { return byGroup }
        let codePoint = parseCodePoint(query)
        // One character: that character (any case), not every name containing the letter.
        if query.count == 1 {
            let wanted = Set((query.lowercased() + query.uppercased()).unicodeScalars.map(\.value))
            return byGroup.filter(wanted.contains)
        }
        let words = query.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return byGroup.filter { value in
            if value == codePoint { return true }
            guard let name = Unicode.Scalar(value)?.properties.name else { return false }
            return words.allSatisfy(name.contains)
        }
    }

    /// "U+20AC", "u+20ac", "0x20AC" or a bare hex number of 4–6 digits.
    public static func parseCodePoint(_ text: String) -> UInt32? {
        var hex = text.uppercased()
        if hex.hasPrefix("U+") { hex.removeFirst(2) } else if hex.hasPrefix("0X") { hex.removeFirst(2) } else if hex.count < 4 { return nil }
        guard (1...6).contains(hex.count), hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16), value <= 0x10FFFF else { return nil }
        return value
    }

    public static func codePoint(_ value: UInt32) -> String {
        "U+" + String(value, radix: 16, uppercase: true).leftPadded(to: 4)
    }

    public static func name(_ value: UInt32) -> String {
        guard let scalar = Unicode.Scalar(value) else { return "" }
        return (scalar.properties.name ?? scalar.properties.nameAlias ?? "").capitalized
    }

    public static func htmlEntity(_ value: UInt32) -> String {
        "&#x" + String(value, radix: 16, uppercase: true) + ";"
    }

    public static func string(_ value: UInt32) -> String {
        Unicode.Scalar(value).map { String(Character($0)) } ?? ""
    }
}

extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

// MARK: Coverage ("hide fonts that can't show this text")

extension PreviewText {
    /// Whether a font can show every visible character of `text`. Blank text: yes.
    public static func covers(_ text: String, covers: ([UInt16]) -> Bool) -> Bool {
        for character in text {
            let units = relevantUnits(character)
            if !units.isEmpty, !covers(units) { return false }
        }
        return true
    }

    /// The text the coverage filter checks: the first line, as the grid shows it.
    public static func coverageText(_ text: String) -> String? {
        let first = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? nil : first
    }
}

// MARK: Adding fonts

/// What happens to each file in "Add Fonts…".
public struct InstallPlan: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Copy into the fonts folder.
        case copy(destination: URL)
        /// The same file is already there.
        case alreadyInstalled
        /// A face with the same PostScript name is installed from another file.
        case nameInUse(postScriptName: String)
        /// Not a font CoreText can read.
        case unreadable
    }

    public struct Item: Sendable, Equatable {
        public var source: URL
        public var outcome: Outcome
        /// PostScript names in the file (empty when unreadable).
        public var postScriptNames: [String]
    }

    public var items: [Item]

    public var copies: [Item] { items.filter { if case .copy = $0.outcome { true } else { false } } }
    public var problems: [Item] { items.filter { if case .copy = $0.outcome { false } else { true } } }

    /// Plans an install. `names(url)` returns the file's PostScript names (nil: unreadable);
    /// `installed` are the names already in the library; `sameFile(a, b)` compares contents.
    public static func make(files: [URL], into folder: URL, installed: Set<String>,
                            names: (URL) -> [String]?, exists: (URL) -> Bool, sameFile: (URL, URL) -> Bool) -> InstallPlan {
        var claimed = Set<String>()
        var items: [Item] = []
        for file in files {
            guard let faces = names(file), !faces.isEmpty else {
                items.append(Item(source: file, outcome: .unreadable, postScriptNames: []))
                continue
            }
            let destination = folder.appendingPathComponent(file.lastPathComponent)
            if exists(destination), sameFile(file, destination) {
                items.append(Item(source: file, outcome: .alreadyInstalled, postScriptNames: faces))
            } else if let clash = faces.first(where: { installed.contains($0) || claimed.contains($0) }) {
                items.append(Item(source: file, outcome: .nameInUse(postScriptName: clash), postScriptNames: faces))
            } else {
                claimed.formUnion(faces)
                items.append(Item(source: file, outcome: .copy(destination: uniqueDestination(destination, exists: exists)), postScriptNames: faces))
            }
        }
        return InstallPlan(items: items)
    }

    /// "Font.otf" → "Font 2.otf" when the name is taken by a different file.
    static func uniqueDestination(_ url: URL, exists: (URL) -> Bool) -> URL {
        guard exists(url) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var number = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    public static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]

    /// Font files in a drop: files with a font extension, and font files directly inside folders.
    public static func fontFiles(in urls: [URL], isDirectory: (URL) -> Bool, contents: (URL) -> [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            if isDirectory(url) { return contents(url).filter { fontExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path } }
            return fontExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
    }
}
