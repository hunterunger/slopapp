import Foundation

/// File formats a palette can be saved as or read from. Apple Color List (.clr) and PDF need
/// AppKit, so the app writes those itself. PDF is export-only.
public enum PaletteFileFormat: String, CaseIterable, Sendable, Identifiable {
    case json
    case ase
    case clr
    case gpl
    case css
    case pdf

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .json: "Dropper Palette (JSON)"
        case .ase: "Adobe Swatch Exchange (ASE)"
        case .clr: "Apple Color List (CLR)"
        case .gpl: "GIMP Palette (GPL)"
        case .css: "CSS Variables"
        case .pdf: "PDF Swatch Sheet"
        }
    }

    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .ase: "ase"
        case .clr: "clr"
        case .gpl: "gpl"
        case .css: "css"
        case .pdf: "pdf"
        }
    }

    public static func forExtension(_ ext: String) -> PaletteFileFormat? {
        allCases.first { $0.fileExtension == ext.lowercased() }
    }
}

public enum PaletteCodecError: LocalizedError, Equatable {
    case notAPalette
    case noColors

    public var errorDescription: String? {
        switch self {
        case .notAPalette: "This file isn’t a palette Dropper can read."
        case .noColors: "No colors were found in this file."
        }
    }
}

public enum PaletteCodec {
    // MARK: Export

    public static func export(_ palette: Palette, as format: PaletteFileFormat, options: FormatOptions = .standard) -> Data? {
        switch format {
        case .json: json(palette)
        case .ase: ase(palette)
        case .gpl: Data(gpl(palette).utf8)
        case .css: Data(css(palette, options: options).utf8)
        case .clr, .pdf: nil
        }
    }

    struct JSONPalette: Codable {
        struct Entry: Codable {
            var name: String
            var hex: String
            /// Extended sRGB, so wide-gamut colors survive a round trip.
            var sRGB: [Double]?
            var note: String?
        }
        var format: String
        var version: Int
        var name: String
        var note: String?
        var colors: [Entry]
    }

    static let jsonFormatID = "app.slopapp.dropper.palette"

    public static func json(_ palette: Palette) -> Data? {
        let file = JSONPalette(format: jsonFormatID, version: 1, name: palette.name, note: palette.note.isEmpty ? nil : palette.note,
                               colors: palette.colors.map {
                                   JSONPalette.Entry(name: $0.displayName, hex: ColorFormatter.string($0.color, as: .hex),
                                                     sRGB: $0.color.isOutsideSRGB ? $0.color.sRGB.components : nil,
                                                     note: $0.note)
                               })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(file)
    }

    public static func gpl(_ palette: Palette) -> String {
        var lines = ["GIMP Palette", "Name: \(palette.name)", "Columns: 0", "#"]
        for item in palette.colors {
            let b = item.color.sRGB.quantized.bytes
            lines.append(String(format: "%3d %3d %3d\t%@", b.red, b.green, b.blue, item.displayName))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `:root { --dark-blue: #3366CC; }`, in the copy format when it's a CSS one.
    public static func css(_ palette: Palette, format: ColorFormat = .hex, options: FormatOptions = .standard) -> String {
        var used: [String: Int] = [:]
        var lines = ["/* \(palette.name) */", ":root {"]
        for item in palette.colors {
            var base = ColorFormatter.resourceName(item.displayName).replacingOccurrences(of: "_", with: "-")
            used[base, default: 0] += 1
            if let n = used[base], n > 1 { base += "-\(n)" }
            lines.append("  --\(base): \(ColorFormatter.string(item.color, as: format, options: options));")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Adobe Swatch Exchange 1.0: one group named after the palette, RGB float entries.
    public static func ase(_ palette: Palette) -> Data {
        var out = Data("ASEF".utf8)
        out.appendBE(UInt16(1))
        out.appendBE(UInt16(0))
        out.appendBE(UInt32(palette.colors.count + 2))

        var group = Data()
        group.appendASEString(palette.name)
        out.appendBE(UInt16(0xC001))
        out.appendBE(UInt32(group.count))
        out.append(group)

        for item in palette.colors {
            var block = Data()
            block.appendASEString(item.displayName)
            block.append(Data("RGB ".utf8))
            let c = item.color.sRGB.quantized
            for v in c.components { block.appendBE(Float32(v).bitPattern) }
            block.appendBE(UInt16(2)) // normal (process) color
            out.appendBE(UInt16(0x0001))
            out.appendBE(UInt32(block.count))
            out.append(block)
        }
        out.appendBE(UInt16(0xC002))
        out.appendBE(UInt32(0))
        return out
    }

    // MARK: Import

    /// Reads palettes from a file's contents. `fallbackName` names palettes the file
    /// doesn't name (usually the file name). Unknown text files are scanned for color values.
    public static func importPalettes(_ data: Data, format: PaletteFileFormat?, fallbackName: String, date: Date) throws -> [Palette] {
        if data.starts(with: Data("ASEF".utf8)) { return try readASE(data, fallbackName: fallbackName, date: date) }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw PaletteCodecError.notAPalette
        }
        if format == .json || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
           let palette = readJSON(data, date: date) {
            return [palette]
        }
        if text.hasPrefix("GIMP Palette") { return [try readGPL(text, fallbackName: fallbackName, date: date)] }
        let found = colors(inText: text)
        guard !found.isEmpty else { throw PaletteCodecError.noColors }
        return [Palette(name: fallbackName, colors: found.map { PickedColor(color: $0, date: date) }, created: date)]
    }

    static func readJSON(_ data: Data, date: Date) -> Palette? {
        guard let file = try? JSONDecoder().decode(JSONPalette.self, from: data) else { return nil }
        let entries = file.colors.compactMap { entry -> PickedColor? in
            let color = entry.sRGB.flatMap { $0.count == 3 ? ColorValue(red: $0[0], green: $0[1], blue: $0[2]) : nil }
                ?? HexParser.color(entry.hex, in: .sRGB)
            return color.map { PickedColor(color: $0, date: date, name: entry.name, note: entry.note) }
        }
        return Palette(name: file.name, note: file.note ?? "", colors: entries, created: date)
    }

    static func readGPL(_ text: String, fallbackName: String, date: Date) throws -> Palette {
        var name = fallbackName
        var items: [PickedColor] = []
        for raw in text.split(whereSeparator: \.isNewline).dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Name:") {
                name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("Columns:") { continue }
            let parts = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3, let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]),
                  [r, g, b].allSatisfy({ (0...255).contains($0) }) else { continue }
            let label = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : ""
            items.append(PickedColor(color: ColorValue(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255),
                                     date: date, name: label.isEmpty || label == "Untitled" ? nil : label))
        }
        guard !items.isEmpty else { throw PaletteCodecError.noColors }
        return Palette(name: name, colors: items, created: date)
    }

    /// Every color value written in some text: hex (#rgb, #rrggbb), rgb()/rgba(), hsl()/hsla(),
    /// color(display-p3 …) and oklch(), in order, without repeats. Imports CSS files,
    /// design tokens and notes.
    public static func colors(inText text: String) -> [ColorValue] {
        let pattern = #"#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-fA-F])|(?:rgba?|hsla?|color|oklch)\([^()]*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var seen = Set<[Int]>()
        var result: [ColorValue] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            guard let color = ColorParser.color(token, in: .sRGB), seen.insert(color.identityKey).inserted else { continue }
            result.append(color)
        }
        return result
    }

    static func readASE(_ data: Data, fallbackName: String, date: Date) throws -> [Palette] {
        var reader = BigEndianReader(data: data)
        guard reader.bytes(4) == Data("ASEF".utf8), reader.u16() != nil, reader.u16() != nil, let count = reader.u32() else {
            throw PaletteCodecError.notAPalette
        }
        var palettes: [Palette] = []
        var loose: [PickedColor] = []
        var current: (name: String, items: [PickedColor])?
        for _ in 0..<count {
            guard let type = reader.u16(), let length = reader.u32(), let block = reader.bytes(Int(length)) else { break }
            var b = BigEndianReader(data: block)
            switch type {
            case 0xC001:
                current = (b.aseString() ?? fallbackName, [])
            case 0xC002:
                if let group = current {
                    palettes.append(Palette(name: group.name, colors: group.items, created: date))
                }
                current = nil
            case 0x0001:
                let name = b.aseString()
                guard let model = b.bytes(4).flatMap({ String(data: $0, encoding: .ascii) }),
                      let color = aseColor(model: model, reader: &b) else { continue }
                let item = PickedColor(color: color, date: date, name: name?.isEmpty == false ? name : nil)
                if current != nil { current?.items.append(item) } else { loose.append(item) }
            default:
                continue
            }
        }
        if let group = current { palettes.append(Palette(name: group.name, colors: group.items, created: date)) }
        if !loose.isEmpty { palettes.insert(Palette(name: fallbackName, colors: loose, created: date), at: 0) }
        palettes.removeAll { $0.colors.isEmpty }
        guard !palettes.isEmpty else { throw PaletteCodecError.noColors }
        return palettes
    }

    private static func aseColor(model: String, reader: inout BigEndianReader) -> ColorValue? {
        func floats(_ n: Int) -> [Double]? {
            var values: [Double] = []
            for _ in 0..<n {
                guard let bits = reader.u32() else { return nil }
                values.append(Double(Float32(bitPattern: bits)))
            }
            return values
        }
        switch model {
        case "RGB ":
            guard let v = floats(3) else { return nil }
            return ColorValue(red: v[0], green: v[1], blue: v[2])
        case "Gray":
            guard let v = floats(1) else { return nil }
            return ColorValue(red: v[0], green: v[0], blue: v[0])
        case "CMYK":
            guard let v = floats(4) else { return nil }
            return ColorValue(red: (1 - v[0]) * (1 - v[3]), green: (1 - v[1]) * (1 - v[3]), blue: (1 - v[2]) * (1 - v[3]))
        case "LAB ":
            guard let v = floats(3) else { return nil }
            return ColorValue(sRGB: ColorMath.sRGB(fromLab: CIELab(l: v[0] * 100, a: v[1], b: v[2])))
        default:
            return nil
        }
    }
}

// MARK: Binary helpers

struct BigEndianReader {
    let data: Data
    var offset = 0

    init(data: Data) {
        self.data = Data(data)
    }

    mutating func bytes(_ n: Int) -> Data? {
        guard n >= 0, offset + n <= data.count else { return nil }
        defer { offset += n }
        return data.subdata(in: offset..<offset + n)
    }

    mutating func u16() -> UInt16? {
        bytes(2).map { $0.reduce(0) { $0 << 8 | UInt16($1) } }
    }

    mutating func u32() -> UInt32? {
        bytes(4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
    }

    /// UTF-16BE with a length in code units (including the terminating zero).
    mutating func aseString() -> String? {
        guard let units = u16(), let raw = bytes(Int(units) * 2) else { return nil }
        var codeUnits: [UInt16] = []
        var r = BigEndianReader(data: raw)
        while let u = r.u16(), u != 0 { codeUnits.append(u) }
        return String(decoding: codeUnits, as: UTF16.self)
    }
}

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    mutating func appendASEString(_ string: String) {
        let units = Array(string.utf16) + [0]
        appendBE(UInt16(units.count))
        for u in units { appendBE(u) }
    }
}
