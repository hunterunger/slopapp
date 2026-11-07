import Foundation

/// A Pratt parser over one line's tokens. Binding powers, low to high:
/// conversion (in/to/as) → | → xor → & → << >> → + - → * / mod of on off → implicit
/// multiplication → unary minus and bare function arguments → ^ (right-assoc) → per-unit
/// (`km/h`) → units, currencies, scales → postfix % !
struct Parser {
    private enum BP {
        static let convert = 5
        static let bitOr = 6
        static let bitXor = 7
        static let bitAnd = 8
        static let shift = 9
        static let additive = 10
        static let multiplicative = 20
        static let implicit = 25
        static let unary = 30
        static let power = 40
        static let tag = 45
        static let postfix = 50
    }

    /// What the left-hand side is, for deciding whether juxtaposition means multiplication.
    private enum Kind { case numberLike, name, other }

    private let tokens: [Token]
    private var pos = 0

    static func parseLine(_ line: String) -> ParsedLine {
        let syntax = LineSyntax.parse(line)
        switch syntax.kind {
        case .blank: return .blank
        case .header: return .header
        case .comment: return .comment
        case .content: break
        }
        guard var tokens = try? Lexer.tokenize(Substring(syntax.expression)), !tokens.isEmpty else { return .text }
        // A trailing "=" ("12 * 4 =") asks for the answer; ignore it.
        while tokens.last == .symbol("=") { tokens.removeLast() }
        if tokens.isEmpty { return .text }

        // em = 20px, ppi = 326
        if tokens.count >= 3, case .word(let name) = tokens[0], tokens[1] == .symbol("="),
           let setting = Self.cssSetting(name) {
            guard let expr = try? Parser.expression(Array(tokens[2...])) else { return .text }
            return .cssSetting(setting, expr)
        }
        // 5% of what is 6 / 6 is 5% of what
        if let solved = Self.percentBase(tokens) { return .expression(solved) }
        // name = expr
        if tokens.count >= 2, case .word(let name) = tokens[0], tokens[1] == .symbol("=") {
            if let kind = Words.reservedKind(name) {
                // "1 USD = ..." starts with a number, so a reserved word here is a mistake...
                // unless it's a currency rate written code-first ("USD = 1.37 CAD" isn't valid anyway).
                return .reservedName(name, kind: kind)
            }
            guard tokens.count > 2, let expr = try? Parser.expression(Array(tokens[2...])) else { return .text }
            return .assignment(name, expr)
        }
        // lhs = rhs: a currency rate.
        if let eq = tokens.firstIndex(of: .symbol("=")) {
            guard let lhs = try? Parser.expression(Array(tokens[..<eq])),
                  let rhs = try? Parser.expression(Array(tokens[(eq + 1)...])) else { return .text }
            return .rate(lhs, rhs)
        }
        guard let expr = try? Parser.expression(tokens) else { return .text }
        return .expression(expr)
    }

    private static func cssSetting(_ name: String) -> CSSSetting? {
        switch name {
        case "em", "rem": .em
        case "ppi", "PPI": .ppi
        default: nil
        }
    }

    /// `P% of what is Y` or `Y is P% of what` (also `on`/`off`).
    private static func percentBase(_ tokens: [Token]) -> Expr? {
        func lower(_ i: Int) -> String? {
            if case .word(let w) = tokens[safe: i] { return w.lowercased() }
            return nil
        }
        guard let what = tokens.indices.first(where: { lower($0) == "what" }), what >= 2,
              let opWord = lower(what - 1) else { return nil }
        let op: PercentOp
        switch opWord {
        case "of": op = .of
        case "on": op = .on
        case "off": op = .off
        default: return nil
        }
        if lower(what + 1) == "is" {
            guard let p = try? expression(Array(tokens[..<(what - 1)])),
                  let y = try? expression(Array(tokens[(what + 2)...])) else { return nil }
            return .percentBase(op, p, y)
        }
        if what == tokens.count - 1, let isIndex = tokens.indices.first(where: { lower($0) == "is" }), isIndex < what - 1 {
            guard let y = try? expression(Array(tokens[..<isIndex])),
                  let p = try? expression(Array(tokens[(isIndex + 1)..<(what - 1)])) else { return nil }
            return .percentBase(op, p, y)
        }
        return nil
    }

    static func expression(_ tokens: [Token]) throws -> Expr {
        var parser = Parser(tokens)
        return try parser.parseAll()
    }

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func parseAll() throws -> Expr {
        let e = try parse(0)
        guard pos == tokens.count else { throw NotACalculation() }
        return e
    }

    // MARK: - Helpers

    private func peek(_ offset: Int = 0) -> Token? { tokens[safe: pos + offset] }

    private func word(_ offset: Int = 0) -> String? {
        if case .word(let w) = peek(offset) { return w }
        return nil
    }

    private func lowerWord(_ offset: Int = 0) -> String? { word(offset)?.lowercased() }

    private mutating func advance() -> Token? {
        defer { pos += 1 }
        return peek()
    }

    /// Is `token` an operator that makes a neighbouring unknown word an error ("unknown
    /// name") instead of plain text? Bitwise symbols and conversational words (`and`, `with`,
    /// `is`) don't count, so "R&D" or "rent and utilities" stay text.
    private func isOperatorish(_ token: Token?) -> Bool {
        switch token {
        case .symbol(let s): return s != "&" && s != "|"
        case .word(let w):
            let l = w.lowercased()
            if Words.softOperators.contains(l) { return false }
            return Words.operators.contains(l) || Words.conversions.contains(l) || Words.functions[l] != nil || w == "x"
        default: return false
        }
    }

    /// Does the token at `offset` start an operand (for `x` meaning "times")?
    private func startsOperand(_ offset: Int) -> Bool {
        switch peek(offset) {
        case .number, .currencySymbol, .clock, .isoDate: return true
        case .symbol(let s): return s == "(" || s == "-"
        case .word(let w): return Words.constant(w) != nil || Words.functions[w.lowercased()] != nil
        case nil: return false
        }
    }

    // MARK: - Pratt loop

    private mutating func parse(_ minBP: Int) throws -> Expr {
        var (lhs, kind) = try nud()
        while let token = peek() {
            guard let step = try led(token, lhs: lhs, kind: kind, minBP: minBP) else { break }
            lhs = step
            kind = .other
        }
        return lhs
    }

    /// Applies one infix/postfix step if its binding power beats `minBP`; nil to stop.
    private mutating func led(_ token: Token, lhs: Expr, kind: Kind, minBP: Int) throws -> Expr? {
        switch token {
        case .symbol(let s):
            switch s {
            case "+", "-":
                guard BP.additive > minBP else { return nil }
                pos += 1
                return .binary(s == "+" ? .add : .subtract, lhs, try parse(BP.additive))
            case "/" where perUnit(at: 0) != nil:
                // km/h, $25/h: divide by one of a unit, binding tighter than * and /.
                guard BP.tag - 1 > minBP, let (unit, length) = perUnit(at: 0) else { return nil }
                pos += length
                return .per(lhs, unit)
            case "*", "/":
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                return .binary(s == "*" ? .multiply : .divide, lhs, try parse(BP.multiplicative))
            case "&":
                guard BP.bitAnd > minBP else { return nil }
                pos += 1
                return .binary(.bitAnd, lhs, try parse(BP.bitAnd))
            case "|":
                guard BP.bitOr > minBP else { return nil }
                pos += 1
                return .binary(.bitOr, lhs, try parse(BP.bitOr))
            case "<", ">":
                guard BP.shift > minBP else { return nil }
                pos += 1
                return .binary(s == "<" ? .shiftLeft : .shiftRight, lhs, try parse(BP.shift))
            case "^":
                guard BP.power > minBP else { return nil }
                pos += 1
                return .binary(.power, lhs, try parse(BP.power - 1))
            case "%":
                guard BP.postfix > minBP else { return nil }
                pos += 1
                return .percent(lhs)
            case "!":
                guard BP.postfix > minBP else { return nil }
                pos += 1
                return .factorial(lhs)
            case "(":
                guard BP.implicit > minBP else { return nil }
                return .binary(.multiply, lhs, try parse(BP.implicit))
            default:
                return nil
            }

        case .currencySymbol(let sym):
            // 20$ / 20€
            guard BP.tag > minBP else { return nil }
            pos += 1
            return .tagged(lhs, .currency(Self.currency(symbol: sym)))

        case .number:
            // Mixed units: "1 h 30 min", "5 ft 11 in".
            guard BP.tag > minBP, case .tagged(_, .unit(let u)) = lastTagged(lhs) else { return nil }
            guard let (next, length) = unitAt(1), next.dimension == u.dimension else { return nil }
            guard case .number(let n) = advance() else { return nil }
            pos += length
            let part = Expr.tagged(.number(n), .unit(next))
            if case .mixed(let parts) = lhs { return .mixed(parts + [part]) }
            return .mixed([lhs, part])

        case .clock, .isoDate:
            return nil

        case .word(let w):
            let l = w.lowercased()
            if Words.conversions.contains(l) {
                guard BP.convert > minBP else { return nil }
                pos += 1
                // "as % of", "as a % on", "as a percentage off"
                let article = lowerWord() == "a" || lowerWord() == "an" ? 1 : 0
                if peek(article) == .symbol("%") || lowerWord(article) == "percent" || lowerWord(article) == "percentage" {
                    let op: PercentOp? = switch lowerWord(article + 1) {
                    case "of": .of
                    case "on": .on
                    case "off": .off
                    default: nil
                    }
                    if let op {
                        pos += article + 2
                        return .asPercent(op, lhs, try parse(BP.convert))
                    }
                }
                return .convert(lhs, try parseTarget())
            }
            switch l {
            case "plus", "minus", "and", "with", "without":
                guard BP.additive > minBP else { return nil }
                pos += 1
                return .binary(l == "minus" || l == "without" ? .subtract : .add, lhs, try parse(BP.additive))
            case "times", "mod", "mul":
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                return .binary(l == "mod" ? .modulo : .multiply, lhs, try parse(BP.multiplicative))
            case "divide":
                guard BP.multiplicative > minBP else { return nil }
                pos += lowerWord(1) == "by" ? 2 : 1
                return .binary(.divide, lhs, try parse(BP.multiplicative))
            case "xor":
                guard BP.bitXor > minBP else { return nil }
                pos += 1
                return .binary(.bitXor, lhs, try parse(BP.bitXor))
            case "per":
                guard let (unit, length) = perUnit(at: 0) else {
                    // "100 km per 2 hours": a plain division.
                    guard BP.multiplicative > minBP, startsOperand(1) else { return nil }
                    pos += 1
                    return .binary(.divide, lhs, try parse(BP.multiplicative))
                }
                guard BP.tag - 1 > minBP else { return nil }
                pos += length
                return .per(lhs, unit)
            case "divided", "multiplied":
                guard BP.multiplicative > minBP else { return nil }
                guard lowerWord(1) == "by" else { throw NotACalculation() }
                pos += 2
                return .binary(l == "divided" ? .divide : .multiply, lhs, try parse(BP.multiplicative))
            case "of", "on", "off":
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                let op: PercentOp = l == "of" ? .of : (l == "on" ? .on : .off)
                return .percentOp(op, lhs, try parse(BP.multiplicative))
            case "percent":
                guard BP.postfix > minBP else { return nil }
                pos += 1
                return .percent(lhs)
            default: break
            }
            if w == "x", startsOperand(1) {
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                return .binary(.multiply, lhs, try parse(BP.multiplicative))
            }
            if let scale = Words.scales[l] {
                guard BP.tag > minBP else { return nil }
                pos += 1
                return .binary(.multiply, lhs, .number(scale))
            }
            if let (unit, length) = unitAt(0) {
                guard BP.tag > minBP else { return nil }
                pos += length
                return .tagged(lhs, .unit(unit))
            }
            if let rate = Units.rateAlias(w) {
                guard BP.tag > minBP else { return nil }
                pos += 1
                return .tagged(lhs, .rate(rate))
            }
            if let currency = Currencies.lookup(w) {
                guard BP.tag > minBP else { return nil }
                pos += 1
                return .tagged(lhs, .currency(currency))
            }
            // Juxtaposition: "2 pi", "3 x", "2 sqrt 9".
            guard kind == .numberLike, BP.implicit > minBP else { return nil }
            if Words.constant(w) != nil || Words.functions[l] != nil || Words.aggregates[l] == .prev {
                return .binary(.multiply, lhs, try parse(BP.implicit))
            }
            if Words.reservedKind(w) == nil {
                // A word right after a number is in "unit position": if it isn't a defined
                // variable, the line is just text ("3 apples").
                pos += 1
                return .binary(.multiply, lhs, .name(w, strict: false))
            }
            return nil
        }
    }

    /// The innermost expression a unit was attached to, looking through mixed sums.
    private func lastTagged(_ e: Expr) -> Expr {
        if case .mixed(let parts) = e, let last = parts.last { return last }
        return e
    }

    /// A unit starting at `offset`, possibly two words ("sq ft", "square meters").
    private func unitAt(_ offset: Int) -> (PhysicalUnit, Int)? {
        guard let w = word(offset) else { return nil }
        if Units.isCompoundPrefix(w), let next = word(offset + 1), let u = Units.compound(prefix: w, length: next) {
            return (u, 2)
        }
        if w.lowercased() == "nautical", let next = word(offset + 1)?.lowercased(), next.hasPrefix("mile") {
            return (Units.unit(id: "nmi")!, 2)
        }
        if let u = Units.lookup(w) { return (u, 1) }
        return nil
    }

    /// `/ h` or `per hour`, with the operator at `offset`: the unit, when it isn't followed by
    /// a number (so `1 GB / 1 MB` stays a division). Returns the unit and the tokens used,
    /// counting the operator.
    private func perUnit(at offset: Int) -> (PhysicalUnit, Int)? {
        guard peek(offset) == .symbol("/") || lowerWord(offset) == "per",
              let (unit, length) = unitAt(offset + 1) else { return nil }
        switch peek(offset + 1 + length) {
        case .number, .symbol("("), .currencySymbol: return nil
        default: return (unit, length + 1)
        }
    }

    /// A time zone named by the words starting at `offset`.
    private func zoneAt(_ offset: Int) -> (ZoneRef, Int)? {
        var words: [String] = []
        var k = offset
        while words.count < Zones.maxWords, let w = word(k) {
            words.append(w)
            k += 1
        }
        return Zones.lookup(words)
    }

    private static func currency(symbol: String) -> CurrencyRef {
        symbol == "$" ? .dollar : .code(Currencies.symbols[symbol] ?? "USD")
    }

    // MARK: - Prefix

    private mutating func nud() throws -> (Expr, Kind) {
        let index = pos
        guard let token = advance() else { throw NotACalculation() }
        switch token {
        case .number(let n):
            if let time = try timeAfterNumber(n) { return (time, .other) }
            if let date = dayMonth(n) { return (date, .other) }
            return (.number(n), .numberLike)
        case .clock(let h, let m, let sec):
            var hour = h
            if let meridiem = lowerWord(), meridiem == "am" || meridiem == "pm" {
                guard (1...12).contains(h) else { throw NotACalculation() }
                pos += 1
                hour = h % 12 + (meridiem == "pm" ? 12 : 0)
            }
            return (.timeOfDay(hour: hour, minute: m, second: sec, zone: takeZone()), .other)
        case .isoDate(let y, let m, let d):
            return (.calendarDay(year: y, month: m, day: d), .other)
        case .currencySymbol(let sym):
            let operand = try parse(BP.tag - 1)
            return (.tagged(operand, .currency(Self.currency(symbol: sym))), .other)
        case .symbol(let s):
            switch s {
            case "-": return (.negate(try parse(BP.unary)), .other)
            case "+": return (try parse(BP.unary), .other)
            case "(":
                let inner = try parse(0)
                if peek() == .symbol(")") {
                    pos += 1
                } else if peek() != nil {
                    throw NotACalculation()
                } // An unclosed "(" at the end of the line closes itself.
                return (inner, .numberLike)
            default: throw NotACalculation()
            }
        case .word(let w):
            let l = w.lowercased()
            if let agg = Words.aggregates[l] { return (.aggregate(agg), .other) }
            if let special = try dateOrTimeWord(w, at: index) { return (special, .other) }
            if let c = Words.constant(w) { return (.constant(c), .numberLike) }
            if let fn = Words.functions[l] { return (try call(fn), .other) }
            if l == "square" || l == "cube", lowerWord() == "root" {
                // "square root of 9", "cube root 27"
                pos += lowerWord(1) == "of" ? 2 : 1
                return (.call(l == "square" ? .sqrt : .cbrt, [try parse(BP.unary)]), .other)
            }
            if let currency = Currencies.lookup(w), startsNumber() {
                // "USD 100", "EUR 50"
                let operand = try parse(BP.tag - 1)
                return (.tagged(operand, .currency(currency)), .other)
            }
            if w != "x", Words.reservedKind(w) != nil { throw NotACalculation() }
            let strict = isOperatorish(tokens[safe: index - 1]) || isOperatorish(tokens[safe: index + 1])
            return (.name(w, strict: strict), .name)
        }
    }

    /// `3pm`, `11 am PST`: a number followed by am/pm (the number is already consumed).
    private mutating func timeAfterNumber(_ n: Decimal) throws -> Expr? {
        guard let meridiem = lowerWord(), meridiem == "am" || meridiem == "pm" else { return nil }
        guard DecimalMath.isInteger(n), n >= 1, n <= 12 else { throw NotACalculation() }
        pos += 1
        let h = NSDecimalNumber(decimal: n).intValue
        return .timeOfDay(hour: h % 12 + (meridiem == "pm" ? 12 : 0), minute: 0, second: 0, zone: takeZone())
    }

    /// `25 Dec`, `25 December 2026` (the day is already consumed).
    private mutating func dayMonth(_ n: Decimal) -> Expr? {
        guard let w = lowerWord(), let month = DateMath.months[w], DecimalMath.isInteger(n), n >= 1, n <= 31 else { return nil }
        pos += 1
        return .calendarDay(year: takeYear(comma: false), month: month, day: NSDecimalNumber(decimal: n).intValue)
    }

    /// A four-digit year after a day and month ("Dec 25, 2026", "25 Dec 2026").
    private mutating func takeYear(comma: Bool) -> Int? {
        let skip = comma && peek() == .symbol(",") ? 1 : 0
        guard case .number(let y) = peek(skip), DecimalMath.isInteger(y), y >= 1000, y <= 9999 else { return nil }
        // "Dec 25, 2026" but not "Dec 25 2026 - 5": a year is never followed by a unit.
        pos += skip + 1
        return NSDecimalNumber(decimal: y).intValue
    }

    /// An optional zone after a time: `3pm PST`, `9:30 New York`.
    private mutating func takeZone() -> ZoneRef? {
        guard let (zone, length) = zoneAt(0) else { return nil }
        pos += length
        return zone
    }

    /// now, today, `Dec 25`, noon, `time in Tokyo`, `PST time`. `index` is the word's position;
    /// `pos` is already past it.
    private mutating func dateOrTimeWord(_ w: String, at index: Int) throws -> Expr? {
        let l = w.lowercased()
        if let word = Words.dateWords[l] {
            return .dateWord(word)
        }
        if l == "noon" || l == "midnight" {
            return .timeOfDay(hour: l == "noon" ? 12 : 0, minute: 0, second: 0, zone: takeZone())
        }
        if l == "time", let c = lowerWord(), Words.conversions.contains(c), let (zone, length) = zoneAt(1) {
            pos += 1 + length
            return .zoneNow(zone)
        }
        if let month = DateMath.months[l], case .number(let d) = peek(), DecimalMath.isInteger(d), d >= 1, d <= 31 {
            pos += 1
            return .calendarDay(year: takeYear(comma: true), month: month, day: NSDecimalNumber(decimal: d).intValue)
        }
        // "PST time", "New York time": only looked up when "time" follows within a few words.
        if let k = (0..<Zones.maxWords).first(where: { lowerWord($0) == "time" }),
           let (zone, length) = zoneAt(-1), length == k + 1 {
            pos += length
            return .zoneNow(zone)
        }
        return nil
    }

    private func startsNumber() -> Bool {
        if case .number = peek() { return true }
        return peek() == .symbol("(")
    }

    private mutating func call(_ fn: MathFunction) throws -> Expr {
        if peek() == .symbol("(") {
            pos += 1
            var args: [Expr] = []
            if peek() != .symbol(")") {
                args.append(try parse(0))
                while peek() == .symbol(",") {
                    pos += 1
                    args.append(try parse(0))
                }
            }
            if peek() == .symbol(")") {
                pos += 1
            } else if peek() != nil {
                throw NotACalculation()
            }
            // "sqrt(16) + 2" is done; but "round(2.5)^2" should still apply ^ and postfix.
            return .call(fn, args)
        }
        // "log 2 (10)": log base 2 of 10; "root 3 (8)": the cube root of 8.
        if fn == .log || fn == .root, case .number(let n) = peek(), peek(1) == .symbol("(") {
            pos += 2
            let x = try parse(0)
            if peek() == .symbol(")") { pos += 1 } else if peek() != nil { throw NotACalculation() }
            return .call(fn, [x, .number(n)])
        }
        if lowerWord() == "of", fn == .sqrt || fn == .cbrt || fn == .root { pos += 1 }
        return .call(fn, [try parse(BP.unary)])
    }

    // MARK: - Conversion targets

    private mutating func parseTarget() throws -> Target {
        guard let token = peek() else { throw NotACalculation() }
        switch token {
        case .symbol("%"):
            pos += 1
            return .percent
        case .currencySymbol(let s):
            pos += 1
            let ref = Self.currency(symbol: s)
            if let (per, length) = perUnit(at: 0) {
                pos += length
                return .rate(.currency(ref, per: per))
            }
            return .currency(ref)
        case .word(let w):
            let l = w.lowercased()
            if l == "percent" || l == "percentage" {
                pos += 1
                return .percent
            }
            if let style = Words.styles[l] {
                pos += 1
                return .style(style)
            }
            if l == "unix" || l == "timestamp" {
                pos += 1
                if lowerWord() == "time" || lowerWord() == "timestamp" { pos += 1 }
                return .unix
            }
            if let (unit, length) = unitAt(0) {
                pos += length
                if let (per, perLength) = perUnit(at: 0) {
                    pos += perLength
                    return .rate(.unit(RateUnit(.unit(unit), per: per)))
                }
                return .unit(unit)
            }
            if let rate = Units.rateAlias(w) {
                pos += 1
                return .rate(.unit(rate))
            }
            if let c = Currencies.lookup(w) {
                pos += 1
                if let (per, length) = perUnit(at: 0) {
                    pos += length
                    return .rate(.currency(c, per: per))
                }
                return .currency(c)
            }
            if let (zone, length) = zoneAt(0) {
                pos += length
                if lowerWord() == "time" { pos += 1 }
                return .zone(zone)
            }
            throw NotACalculation()
        default:
            throw NotACalculation()
        }
    }
}
