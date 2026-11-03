import Foundation

public enum HexParser {
    /// Parses "#3366CC", "3366cc", "#36C" or "36c" (surrounding spaces allowed) into
    /// components 0...1. Returns nil for anything else, including 8-digit hex with alpha.
    public static func parse(_ text: String) -> RGB? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 3 || s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(s, radix: 16) else { return nil }
        return RGB(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Parses hex given in `space` ("#FF0000" in Display P3 is a more vivid red than in sRGB).
    public static func color(_ text: String, in space: OutputSpace) -> ColorValue? {
        parse(text).map { ColorValue($0, in: space) }
    }
}
