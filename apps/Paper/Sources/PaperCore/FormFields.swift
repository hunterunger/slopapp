import AppKit
import PDFKit

/// The kinds of form field Paper can add to a page.
public enum FormFieldKind: String, CaseIterable, Codable, Sendable {
    case text, checkbox, radio, dropdown, signature

    public var title: String {
        switch self {
        case .text: "Text Field"
        case .checkbox: "Checkbox"
        case .radio: "Radio Button"
        case .dropdown: "Dropdown"
        case .signature: "Signature Field"
        }
    }

    /// The base for new field names ("Text 1", "Checkbox 2").
    public var baseName: String {
        switch self {
        case .text: "Text"
        case .checkbox: "Checkbox"
        case .radio: "Choice"
        case .dropdown: "Dropdown"
        case .signature: "Signature"
        }
    }

    /// The size a field gets from a single click, in points.
    public var defaultSize: CGSize {
        switch self {
        case .text: CGSize(width: 180, height: 22)
        case .checkbox, .radio: CGSize(width: 14, height: 14)
        case .dropdown: CGSize(width: 140, height: 22)
        case .signature: CGSize(width: 200, height: 50)
        }
    }

    /// Checkboxes and radio buttons stay square.
    public var keepsSquare: Bool { self == .checkbox || self == .radio }

    public static func of(_ annotation: PDFAnnotation) -> FormFieldKind? {
        guard annotation.type == "Widget" else { return nil }
        switch annotation.widgetFieldType {
        case .text: return .text
        case .choice: return .dropdown
        case .signature: return .signature
        case .button:
            switch annotation.widgetControlType {
            case .checkBoxControl: return .checkbox
            case .radioButtonControl: return .radio
            default: return nil
            }
        default: return nil
        }
    }
}

/// Makes form fields that look the same in every viewer: a thin grey border, a white
/// background, Helvetica (a standard PDF font, so nothing needs embedding).
public enum FormFieldFactory {
    static let borderColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)

    public static func make(_ kind: FormFieldKind, in rect: CGRect, name: String, exportValue: String? = nil) -> PDFAnnotation {
        var bounds = rect.standardized
        if kind.keepsSquare {
            let side = max(10, min(bounds.width, bounds.height))
            bounds = CGRect(x: bounds.minX, y: bounds.maxY - side, width: side, height: side)
        }
        let field = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
        // The field type has to come first: setting it later resets the name and the
        // appearance PDFKit writes (research P26).
        switch kind {
        case .text:
            field.widgetFieldType = .text
        case .checkbox:
            field.widgetFieldType = .button
            field.widgetControlType = .checkBoxControl
        case .radio:
            field.widgetFieldType = .button
            field.widgetControlType = .radioButtonControl
        case .dropdown:
            field.widgetFieldType = .choice
            field.isListChoice = false
        case .signature:
            field.widgetFieldType = .signature
        }
        field.fieldName = name
        // The tooltip is also what screen readers announce (here and in other viewers).
        setTooltip(name, on: field)
        let border = PDFBorder()
        border.lineWidth = 1
        field.border = border
        field.color = borderColor
        field.backgroundColor = kind == .signature ? NSColor(srgbRed: 0.97, green: 0.97, blue: 1, alpha: 1) : .white
        if kind == .text || kind == .dropdown {
            field.font = NSFont(name: "Helvetica", size: min(12, max(8, (bounds.height * 0.55).rounded())))
            field.fontColor = .black
        }
        switch kind {
        case .text:
            field.widgetStringValue = ""
        case .checkbox:
            field.buttonWidgetStateString = exportValue ?? "Yes"
            field.buttonWidgetState = .offState
        case .radio:
            field.buttonWidgetStateString = exportValue ?? "Choice 1"
            field.buttonWidgetState = .offState
        case .dropdown:
            field.choices = ["Option 1", "Option 2", "Option 3"]
            field.widgetStringValue = ""
        case .signature:
            break
        }
        return field
    }

    /// The tooltip other viewers and screen readers show for a field (`/TU`).
    public static func tooltip(of field: PDFAnnotation) -> String {
        (field.value(forAnnotationKey: tooltipKey) as? String) ?? ""
    }

    public static func setTooltip(_ text: String, on field: PDFAnnotation) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { field.removeValue(forAnnotationKey: tooltipKey) } else { field.setValue(trimmed, forAnnotationKey: tooltipKey) }
    }

    static let tooltipKey = PDFAnnotationKey(rawValue: "/TU")
    static let flagsKey = PDFAnnotationKey(rawValue: "/Ff")

    /// Field flags (`/Ff`): read-only is bit 1, required bit 2, multiline (text) bit 13.
    public enum Flag: Int, Sendable {
        case readOnly = 1, required = 2, multiline = 4096
    }

    public static func flags(of field: PDFAnnotation) -> Int {
        (field.value(forAnnotationKey: flagsKey) as? NSNumber)?.intValue ?? 0
    }

    public static func has(_ flag: Flag, _ field: PDFAnnotation) -> Bool {
        if flag == .readOnly, field.isReadOnly { return true }
        if flag == .multiline, field.widgetFieldType == .text, field.isMultiline { return true }
        return flags(of: field) & flag.rawValue != 0
    }

    public static func set(_ flag: Flag, _ on: Bool, on field: PDFAnnotation) {
        switch flag {
        case .readOnly: field.isReadOnly = on
        case .multiline where field.widgetFieldType == .text: field.isMultiline = on
        default: break
        }
        var value = flags(of: field)
        value = on ? value | flag.rawValue : value & ~flag.rawValue
        field.setValue(NSNumber(value: value), forAnnotationKey: flagsKey)
    }
}

/// Field names: unique, and without dots (a dot makes a name hierarchical in PDF).
public enum FormNames {
    public static func clean(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func unique(_ base: String, existing: Set<String>) -> String {
        var number = 1
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Every field name in the document.
    public static func all(in document: PDFDocument) -> Set<String> {
        var names = Set<String>()
        for field in FormFields.widgets(in: document) {
            if let name = field.annotation.fieldName, !name.isEmpty { names.insert(name) }
        }
        return names
    }
}

public enum FormFields {
    public struct Item {
        public let annotation: PDFAnnotation
        public let pageIndex: Int
    }

    /// Every form widget, page by page in the order PDF viewers tab through them.
    public static func widgets(in document: PDFDocument) -> [Item] {
        var items: [Item] = []
        for index in 0..<document.pageCount {
            for annotation in document.page(at: index)?.annotations ?? [] where annotation.type == "Widget" {
                items.append(Item(annotation: annotation, pageIndex: index))
            }
        }
        return items
    }

    /// The current value of a field by name, as text (a checked box is its export value).
    public static func values(in document: PDFDocument) -> [String: String] {
        var values: [String: String] = [:]
        for item in widgets(in: document) {
            guard let name = item.annotation.fieldName else { continue }
            let field = item.annotation
            if field.widgetFieldType == .button {
                if field.buttonWidgetState == .onState { values[name] = field.buttonWidgetStateString }
                else if values[name] == nil { values[name] = "" }
            } else {
                values[name] = field.widgetStringValue ?? ""
            }
        }
        return values
    }

    /// The page's widgets sorted into reading order: rows top to bottom, then left to right.
    /// Two fields are on the same row when their vertical centres are within half the
    /// smaller one's height.
    public static func positionOrder(_ fields: [PDFAnnotation]) -> [PDFAnnotation] {
        fields.sorted { a, b in
            let tolerance = min(a.bounds.height, b.bounds.height) / 2
            if abs(a.bounds.midY - b.bounds.midY) > tolerance { return a.bounds.midY > b.bounds.midY }
            return a.bounds.minX < b.bounds.minX
        }
    }

    /// Puts a page's widgets in `order` (tab order is the order of the page's annotations).
    /// Other annotations keep their order, in front of the fields.
    public static func reorder(_ page: PDFPage, widgets order: [PDFAnnotation]) {
        let all = page.annotations
        let widgets = Set(order.map(ObjectIdentifier.init))
        let others = all.filter { !widgets.contains(ObjectIdentifier($0)) }
        let remaining = all.filter { widgets.contains(ObjectIdentifier($0)) }
        guard remaining.count == order.count else { return }
        for annotation in all { page.removeAnnotation(annotation) }
        for annotation in others + order { page.addAnnotation(annotation) }
    }
}

// MARK: Calculations

/// A calculated field's rule. Written as the standard Acrobat form JavaScript, so Acrobat,
/// Reader and other viewers that run form scripts calculate too (research P25).
public enum Calculation: Equatable, Sendable {
    public enum Operation: String, CaseIterable, Sendable {
        case sum = "SUM", product = "PRD", average = "AVG", minimum = "MIN", maximum = "MAX"

        public var title: String {
            switch self {
            case .sum: "Sum"
            case .product: "Product"
            case .average: "Average"
            case .minimum: "Minimum"
            case .maximum: "Maximum"
            }
        }
    }

    /// An operation over a list of fields.
    case aggregate(Operation, fields: [String])
    /// Simplified field notation: `qty * price + shipping`. Names with spaces or operators
    /// are written with a backslash before those characters (`unit\ price`), as Acrobat does.
    case formula(String)
    /// A script from another app that Paper doesn't run. It's kept as it is.
    case script(String)

    public var isScript: Bool { if case .script = self { true } else { false } }

    /// Field names this rule reads.
    public var inputs: [String] {
        switch self {
        case .aggregate(_, let fields): fields
        case .formula(let text): (try? FormulaParser.parse(text).fieldNames) ?? []
        case .script: []
        }
    }
}

public struct FieldCalculation: Equatable, Sendable {
    public var rule: Calculation
    /// Decimal places shown (`AFNumber_Format`), or nil to leave formatting alone.
    public var decimals: Int?

    public init(_ rule: Calculation, decimals: Int? = 2) {
        self.rule = rule
        self.decimals = decimals
    }
}

/// All calculated fields of a document, by field name, plus the order they run in (the
/// AcroForm `/CO` array).
public struct FormScripts: Equatable, Sendable {
    public var calculations: [String: FieldCalculation] = [:]
    public var order: [String] = []

    public init(calculations: [String: FieldCalculation] = [:], order: [String] = []) {
        self.calculations = calculations
        self.order = order
    }

    public var isEmpty: Bool { calculations.isEmpty }

    public mutating func set(_ calculation: FieldCalculation?, for name: String) {
        calculations[name] = calculation
        order.removeAll { $0 == name }
        if calculation != nil { order.append(name) }
        order = runOrder()
    }

    /// Calculation order: a field runs after the calculated fields it reads. Fields in a
    /// cycle keep their place and simply read the previous value.
    public func runOrder() -> [String] {
        var result: [String] = []
        var state: [String: Int] = [:] // 1 visiting, 2 done
        func visit(_ name: String) {
            guard state[name] == nil, let calculation = calculations[name] else { return }
            state[name] = 1
            for input in calculation.rule.inputs where calculations[input] != nil && state[input] == nil { visit(input) }
            state[name] = 2
            result.append(name)
        }
        for name in order + calculations.keys.sorted() where calculations[name] != nil { visit(name) }
        return result
    }

    /// New values for calculated fields, given the current values of every field.
    /// Fields whose value doesn't change aren't returned.
    public func evaluate(_ values: [String: String]) -> [String: String] {
        var current = values
        var changed: [String: String] = [:]
        for name in runOrder() {
            guard let calculation = calculations[name],
                  let number = FormMath.compute(calculation.rule, values: current) else { continue }
            let text = FormMath.format(number, decimals: calculation.decimals)
            if current[name] != text {
                changed[name] = text
                current[name] = text
            }
        }
        return changed
    }

    /// Rename a field everywhere it's read.
    public mutating func rename(_ old: String, to new: String) {
        var renamed: [String: FieldCalculation] = [:]
        for (name, var calculation) in calculations {
            switch calculation.rule {
            case .aggregate(let op, let fields):
                calculation.rule = .aggregate(op, fields: fields.map { $0 == old ? new : $0 })
            case .formula(let text):
                calculation.rule = .formula(FormulaParser.rename(old, to: new, in: text))
            case .script:
                break
            }
            renamed[name == old ? new : name] = calculation
        }
        calculations = renamed
        order = order.map { $0 == old ? new : $0 }
    }
}

public enum FormMath {
    /// Reads a field value as a number the way Acrobat's `AFMakeNumber` does for the usual
    /// cases: currency signs, spaces and thousands separators are ignored; empty is 0.
    public static func number(_ text: String?) -> Double {
        guard let text else { return 0 }
        let kept = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(kept) ?? 0
    }

    public static func compute(_ rule: Calculation, values: [String: String]) -> Double? {
        switch rule {
        case .aggregate(let op, let fields):
            let numbers = fields.map { number(values[$0]) }
            guard !numbers.isEmpty else { return op == .sum ? 0 : nil }
            switch op {
            case .sum: return numbers.reduce(0, +)
            case .product: return numbers.reduce(1, *)
            case .average: return numbers.reduce(0, +) / Double(numbers.count)
            case .minimum: return numbers.min()
            case .maximum: return numbers.max()
            }
        case .formula(let text):
            guard let expression = try? FormulaParser.parse(text) else { return nil }
            let result = expression.evaluate { number(values[$0]) }
            return result.isFinite ? result : nil
        case .script:
            return nil
        }
    }

    public static func format(_ value: Double, decimals: Int?) -> String {
        guard let decimals else {
            if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
            return String(value)
        }
        return String(format: "%.\(max(0, min(decimals, 6)))f", value)
    }
}

// MARK: Formulas

public indirect enum FormulaExpression: Equatable, Sendable {
    case number(Double)
    case field(String)
    case negate(FormulaExpression)
    case binary(Character, FormulaExpression, FormulaExpression)

    public func evaluate(_ lookup: (String) -> Double) -> Double {
        switch self {
        case .number(let value): return value
        case .field(let name): return lookup(name)
        case .negate(let inner): return -inner.evaluate(lookup)
        case .binary(let op, let a, let b):
            let x = a.evaluate(lookup), y = b.evaluate(lookup)
            switch op {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            default: return x / y
            }
        }
    }

    public var fieldNames: [String] {
        switch self {
        case .number: []
        case .field(let name): [name]
        case .negate(let inner): inner.fieldNames
        case .binary(_, let a, let b): a.fieldNames + b.fieldNames.filter { !a.fieldNames.contains($0) }
        }
    }

    /// The JavaScript Acrobat runs for this expression.
    public var javaScript: String {
        switch self {
        case .number(let value): return FormMath.format(value, decimals: nil)
        case .field(let name): return "AFMakeNumber(getField(\(JSString.quote(name))).value)"
        case .negate(let inner): return "-(\(inner.javaScript))"
        case .binary(let op, let a, let b): return "(\(a.javaScript) \(op) \(b.javaScript))"
        }
    }
}

public enum FormulaError: Error, Equatable, LocalizedError {
    case empty
    case unexpected(String)
    case unbalanced

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a formula, like qty * price."
        case .unexpected(let token): "The formula has something Paper doesn't understand near “\(token)”."
        case .unbalanced: "The formula's parentheses don't match."
        }
    }
}

/// Parses simplified field notation: numbers, field names, + − × ÷ and parentheses.
public enum FormulaParser {
    enum Token: Equatable { case number(Double), name(String), op(Character), open, close }

    public static func parse(_ text: String) throws -> FormulaExpression {
        var tokens = try tokenize(text)
        guard !tokens.isEmpty else { throw FormulaError.empty }
        let expression = try parseSum(&tokens)
        guard tokens.isEmpty else { throw FormulaError.unexpected(describe(tokens[0])) }
        return expression
    }

    static func describe(_ token: Token) -> String {
        switch token {
        case .number(let n): FormMath.format(n, decimals: nil)
        case .name(let n): n
        case .op(let c): String(c)
        case .open: "("
        case .close: ")"
        }
    }

    static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-"))
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if c.isWhitespace { index += 1; continue }
            if "+-*/".contains(c) { tokens.append(.op(c)); index += 1; continue }
            if c == "(" { tokens.append(.open); index += 1; continue }
            if c == ")" { tokens.append(.close); index += 1; continue }
            if c.isNumber || c == "." {
                var end = index
                while end < chars.count, chars[end].isNumber || chars[end] == "." { end += 1 }
                guard let value = Double(String(chars[index..<end])) else { throw FormulaError.unexpected(String(chars[index..<end])) }
                tokens.append(.number(value))
                index = end
                continue
            }
            // A field name: anything up to an unescaped operator, parenthesis or space.
            var name = ""
            while index < chars.count {
                let ch = chars[index]
                if ch == "\\", index + 1 < chars.count {
                    name.append(chars[index + 1])
                    index += 2
                    continue
                }
                if ch.isWhitespace || "+-*/()".contains(ch) { break }
                name.append(ch)
                index += 1
            }
            guard !name.isEmpty else { throw FormulaError.unexpected(String(c)) }
            tokens.append(.name(name))
        }
        return tokens
    }

    static func parseSum(_ tokens: inout [Token]) throws -> FormulaExpression {
        var left = try parseProduct(&tokens)
        while case .op(let op) = tokens.first, op == "+" || op == "-" {
            tokens.removeFirst()
            left = .binary(op, left, try parseProduct(&tokens))
        }
        return left
    }

    static func parseProduct(_ tokens: inout [Token]) throws -> FormulaExpression {
        var left = try parseUnary(&tokens)
        while case .op(let op) = tokens.first, op == "*" || op == "/" {
            tokens.removeFirst()
            left = .binary(op, left, try parseUnary(&tokens))
        }
        return left
    }

    static func parseUnary(_ tokens: inout [Token]) throws -> FormulaExpression {
        guard let first = tokens.first else { throw FormulaError.unexpected("end") }
        switch first {
        case .op("-"):
            tokens.removeFirst()
            return .negate(try parseUnary(&tokens))
        case .op("+"):
            tokens.removeFirst()
            return try parseUnary(&tokens)
        case .number(let value):
            tokens.removeFirst()
            return .number(value)
        case .name(let name):
            tokens.removeFirst()
            return .field(name)
        case .open:
            tokens.removeFirst()
            let inner = try parseSum(&tokens)
            guard tokens.first == .close else { throw FormulaError.unbalanced }
            tokens.removeFirst()
            return inner
        default:
            throw FormulaError.unexpected(describe(first))
        }
    }

    /// A field name as it's written in a formula (spaces and operators escaped).
    public static func escape(_ name: String) -> String {
        var out = ""
        for c in name {
            if c.isWhitespace || "+-*/()\\".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// Renames a field inside formula text.
    public static func rename(_ old: String, to new: String, in text: String) -> String {
        guard let tokens = try? tokenize(text) else { return text }
        return tokens.map { token -> String in
            switch token {
            case .name(let name): escape(name == old ? new : name)
            case .number(let n): FormMath.format(n, decimals: nil)
            case .op(let c): String(c)
            case .open: "("
            case .close: ")"
            }
        }.joined(separator: " ").replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")")
    }
}

// MARK: JavaScript in the file

public enum JSString {
    public static func quote(_ text: String) -> String {
        var out = "\""
        for c in text {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default: out.append(c)
            }
        }
        return out + "\""
    }
}

/// The form JavaScript Paper writes for a calculation and number format, and reads back.
public enum FormJavaScript {
    public static func calculate(_ rule: Calculation) -> String? {
        switch rule {
        case .aggregate(let op, let fields):
            return "AFSimple_Calculate(\"\(op.rawValue)\", new Array(\(fields.map(JSString.quote).joined(separator: ", "))));"
        case .formula(let text):
            guard let expression = try? FormulaParser.parse(text) else { return nil }
            // The comment is how Acrobat stores simplified field notation, so it can show the
            // formula again; Paper reads it back the same way.
            return "/** BVCALC \(text) EVCALC **/ event.value = \(expression.javaScript);"
        case .script(let js):
            return js
        }
    }

    public static func format(decimals: Int) -> String { "AFNumber_Format(\(decimals), 0, 0, 0, \"\", true);" }
    public static func keystroke(decimals: Int) -> String { "AFNumber_Keystroke(\(decimals), 0, 0, 0, \"\", true);" }

    /// What a field's calculate script means.
    public static func parseCalculation(_ js: String) -> Calculation {
        let trimmed = js.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "BVCALC"), let end = trimmed.range(of: "EVCALC", range: range.upperBound..<trimmed.endIndex) {
            let formula = trimmed[range.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if (try? FormulaParser.parse(formula)) != nil { return .formula(formula) }
        }
        let pattern = #"^AFSimple_Calculate\(\s*"(SUM|PRD|AVG|MIN|MAX)"\s*,\s*new\s+Array\s*\((.*)\)\s*\)\s*;?$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let opRange = Range(match.range(at: 1), in: trimmed), let listRange = Range(match.range(at: 2), in: trimmed),
           let op = Calculation.Operation(rawValue: String(trimmed[opRange])) {
            return .aggregate(op, fields: quotedStrings(in: String(trimmed[listRange])))
        }
        return .script(js)
    }

    /// Decimal places from an `AFNumber_Format(…)` format script.
    public static func parseDecimals(_ js: String?) -> Int? {
        guard let js, let range = js.range(of: "AFNumber_Format(") else { return nil }
        let digits = js[range.upperBound...].prefix { $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        return Int(digits)
    }

    static func quotedStrings(in text: String) -> [String] {
        var result: [String] = []
        var current: String?
        var escaped = false
        var quote: Character = "\""
        for c in text {
            if var value = current {
                if escaped { value.append(c); escaped = false; current = value; continue }
                if c == "\\" { escaped = true; continue }
                if c == quote { result.append(value); current = nil; continue }
                value.append(c)
                current = value
            } else if c == "\"" || c == "'" {
                quote = c
                current = ""
            }
        }
        return result
    }
}
