/// Punycode decoding (RFC 3492), so `xn--` hosts can be shown the way people typed them.
/// Encoding isn't needed: Foundation's `URL.host` already returns the ASCII (punycode) form.
public enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
    private static let initialBias = 72, initialN = 128

    /// Decodes one label without its `xn--` prefix. Returns nil if it isn't valid punycode.
    public static func decode(_ input: String) -> String? {
        let scalars = Array(input.unicodeScalars)
        var output: [UnicodeScalar] = []
        var basicEnd = 0
        if let lastDelimiter = scalars.lastIndex(of: "-") {
            for scalar in scalars[..<lastDelimiter] {
                guard scalar.isASCII else { return nil }
                output.append(scalar)
            }
            basicEnd = lastDelimiter + 1
        }

        var n = initialN, i = 0, bias = initialBias
        var index = basicEnd
        while index < scalars.count {
            let oldI = i
            var w = 1
            var k = base
            while true {
                guard index < scalars.count, let digit = digitValue(scalars[index]) else { return nil }
                index += 1
                let (product, overflow1) = digit.multipliedReportingOverflow(by: w)
                guard !overflow1 else { return nil }
                let (sum, overflow2) = i.addingReportingOverflow(product)
                guard !overflow2 else { return nil }
                i = sum
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                let (newW, overflow3) = w.multipliedReportingOverflow(by: base - t)
                guard !overflow3 else { return nil }
                w = newW
                k += base
            }
            let count = output.count + 1
            bias = adapt(delta: i - oldI, count: count, first: oldI == 0)
            n += i / count
            i %= count
            guard let scalar = UnicodeScalar(n) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }
        var result = ""
        result.unicodeScalars.append(contentsOf: output)
        return result
    }

    /// Converts each `xn--` label of a host to Unicode; leaves other labels alone.
    /// The host as people should read it: Unicode, unless that could pass for another site.
    /// Like browsers, a name that mixes scripts ("аpple.com" with a Cyrillic а), or is made
    /// only of Cyrillic or Greek letters under a Latin top-level domain, stays in its
    /// `xn--` form, so a look-alike can't pose as the real site in the picker.
    public static func displayHost(_ host: String) -> String {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let decoded = labels.map { label -> String in
            let lower = label.lowercased()
            guard lower.hasPrefix("xn--"), let unicode = decode(String(lower.dropFirst(4))) else { return label }
            return unicode
        }
        guard decoded != labels else { return host }
        let topLevel = scripts(of: decoded.last ?? "")
        for label in decoded {
            let found = scripts(of: label)
            if found.count > 1 {
                // Latin with Chinese, Japanese or Korean is normal ("東京tokyo"); any other mix isn't.
                guard found.isSubset(of: [.latin, .cjk]) else { return host }
            } else if let only = found.first, only == .cyrillic || only == .greek, !topLevel.contains(only) {
                return host
            }
        }
        return decoded.joined(separator: ".")
    }

    enum Script: Hashable {
        case latin, greek, cyrillic, cjk
        /// Any other script, by its 128-character block (enough to tell scripts apart).
        case other(UInt32)
    }

    /// The scripts of a label's letters (digits and hyphens don't count).
    static func scripts(of label: String) -> Set<Script> {
        var result = Set<Script>()
        for scalar in label.unicodeScalars where scalar.properties.isAlphabetic {
            let v = scalar.value
            switch v {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: result.insert(.latin)
            case 0x370...0x3FF, 0x1F00...0x1FFF: result.insert(.greek)
            case 0x400...0x52F, 0x2DE0...0x2DFF, 0xA640...0xA69F: result.insert(.cyrillic)
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0x1100...0x11FF, 0xF900...0xFAFF:
                result.insert(.cjk)
            default: result.insert(.other(v >> 7))
            }
        }
        return result
    }

    private static func digitValue(_ scalar: UnicodeScalar) -> Int? {
        switch scalar.value {
        case 48...57: Int(scalar.value) - 22 // 0-9 -> 26-35
        case 65...90: Int(scalar.value) - 65 // A-Z
        case 97...122: Int(scalar.value) - 97 // a-z
        default: nil
        }
    }

    private static func adapt(delta: Int, count: Int, first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}
