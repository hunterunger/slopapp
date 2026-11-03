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
    public static func displayHost(_ host: String) -> String {
        host.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            let lower = label.lowercased()
            guard lower.hasPrefix("xn--"), let decoded = decode(String(lower.dropFirst(4))) else {
                return String(label)
            }
            return decoded
        }.joined(separator: ".")
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
