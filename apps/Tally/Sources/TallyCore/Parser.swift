import Foundation

/// A Pratt parser over one line's tokens. Binding powers, low to high:
/// conversion (in/to/as) → + - → * / mod of on off → implicit multiplication → unary minus
/// and bare function arguments → ^ (right-assoc) → units, currencies, scales → postfix % !
struct Parser {
    private enum BP {
        static let convert = 5
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

    private func isOperatorish(_ token: Token?) -> Bool {
        switch token {
        case .symbol: return true
        case .word(let w):
            let l = w.lowercased()
            return Words.operators.contains(l) || Words.conversions.contains(l) || Words.functions[l] != nil || w == "x"
        default: return false
        }
    }

    /// Does the token at `offset` start an operand (for `x` meaning "times")?
    private func startsOperand(_ offset: Int) -> Bool {
        switch peek(offset) {
        case .number, .currencySymbol: return true
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
            case "*", "/":
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                return .binary(s == "*" ? .multiply : .divide, lhs, try parse(BP.multiplicative))
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

        case .word(let w):
            let l = w.lowercased()
            if Words.conversions.contains(l) {
                guard BP.convert > minBP else { return nil }
                pos += 1
                // "as % of" / "as a percentage of"
                if peek() == .symbol("%") || lowerWord() == "percent" {
                    if lowerWord(1) == "of" {
                        pos += 2
                        return .asPercentOf(lhs, try parse(BP.convert))
                    }
                }
                return .convert(lhs, try parseTarget())
            }
            switch l {
            case "plus", "minus":
                guard BP.additive > minBP else { return nil }
                pos += 1
                return .binary(l == "plus" ? .add : .subtract, lhs, try parse(BP.additive))
            case "times", "mod":
                guard BP.multiplicative > minBP else { return nil }
                pos += 1
                return .binary(l == "times" ? .multiply : .modulo, lhs, try parse(BP.multiplicative))
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

    private static func currency(symbol: String) -> CurrencyRef {
        symbol == "$" ? .dollar : .code(Currencies.symbols[symbol] ?? "USD")
    }

    // MARK: - Prefix

    private mutating func nud() throws -> (Expr, Kind) {
        let index = pos
        guard let token = advance() else { throw NotACalculation() }
        switch token {
        case .number(let n):
            return (.number(n), .numberLike)
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
            if let c = Words.constant(w) { return (.constant(c), .numberLike) }
            if let fn = Words.functions[l] { return (try call(fn), .other) }
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
            return .currency(Self.currency(symbol: s))
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
            if let (unit, length) = unitAt(0) {
                pos += length
                return .unit(unit)
            }
            if let c = Currencies.lookup(w) {
                pos += 1
                return .currency(c)
            }
            throw NotACalculation()
        default:
            throw NotACalculation()
        }
    }
}
