import Foundation

/// The Help ▸ Syntax Guide content. Examples are evaluated live by the same engine, so the
/// guide can't drift from what Tally really does (a test checks every example).
public enum SyntaxGuide {
    public struct Section: Identifiable, Sendable {
        public let title: String
        public let note: String?
        public let examples: [String]
        public var id: String { title }
    }

    public static let sections: [Section] = [
        Section(title: "Math", note: "Results appear as you type. No need for =.", examples: [
            "2 + 3 * 4", "(2 + 3) * 4", "2 ^ 10", "7 mod 3", "8 times 9", "100 divided by 8", "5!",
            "2(3 + 1)", "1,250 + 750", "3k + 2.5M", "1.2 billion / 1000",
        ]),
        Section(title: "Percentages", note: nil, examples: [
            "20% of 150", "150 + 20%", "150 - 20%", "5% on 200", "6% off 50", "30 as % of 120",
        ]),
        Section(title: "Variables and earlier lines", note: "prev is the line above. sum and avg add up the lines above, back to a blank line or header.", examples: [
            "price = 40", "qty = 3", "price * qty", "prev + 10%", "sum", "avg",
        ]),
        Section(title: "Notes", note: "Text that isn't math is left alone. Lines with unknown words show nothing.", examples: [
            "# A header", "// A comment", "Rent: 1200 + 85", "\"May\" 1200 / 3",
        ]),
        Section(title: "Units", note: "Length, mass, data, time, temperature, area, volume and angles. Convert with in, to or as.", examples: [
            "5 km in miles", "6 ft to cm", "3 lb in kg", "1 m + 20 cm", "1 GB in MB", "1 GiB in MiB",
            "100 Mb in MB", "90 min in hours", "1 h 30 min in min", "20 °C in °F", "2 m * 3 m", "1 cup in mL",
        ]),
        Section(title: "Functions and constants", note: "Trigonometry uses radians unless you add °.", examples: [
            "sqrt 16 + 2", "round(2.5)", "round(3.14159, 2)", "abs(-4)", "log 1000", "ln(e)", "sin(30°)", "pi * 2",
        ]),
        Section(title: "Number formats", note: nil, examples: [
            "0xff + 1", "255 in hex", "10 in binary", "1500 in sci", "1.5e3",
        ]),
        Section(title: "Money", note: "Same-currency math always works. Converting needs exchange rates: turn them on in Settings, or write your own rate on a line.", examples: [
            "$20 + $5", "€12.50 * 4", "1 USD = 1.37 CAD", "50 USD in CAD",
        ]),
    ]

    /// Every example as one sheet, so `price * qty` sees `price`.
    public static var allExamples: [String] { sections.flatMap(\.examples) }
}
