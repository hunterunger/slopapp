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
            "5% of what is 6", "5% off what is 47.5", "$70 as a % on $20", "$20 as a % off $70",
        ]),
        Section(title: "Variables and earlier lines", note: "Names match in any case. prev is the line above. sum and avg add up the lines above, back to a blank line or header.", examples: [
            "price = 40", "qty = 3", "price * qty", "prev + 10%", "sum", "avg",
        ]),
        Section(title: "Notes", note: "Text that isn’t math is left alone. Lines with unknown words show nothing.", examples: [
            "# A header", "// A comment", "Rent: 1200 + 85", "\"May\" 1200 / 3",
        ]),
        Section(title: "Units", note: "Length, mass, data, time, temperature, area, volume and angles. Convert with in, to or as.", examples: [
            "5 km in miles", "6 ft to cm", "3 lb in kg", "1 m + 20 cm", "1 GB in MB", "1 GiB in MiB",
            "100 Mb in MB", "90 min in hours", "1 h 30 min in min", "20 °C in °F", "2 m * 3 m", "1 cup in mL",
        ]),
        Section(title: "Speeds and other rates", note: "Divide units, or write per. Multiply a rate by its unit to get back the amount.", examples: [
            "60 km/h in m/s", "30 mph in km/h", "100 km / 2 h", "60 km/h * 90 min", "$25 per hour * 38 h",
            "$4/kg * 750 g", "1 GB / 100 Mbps",
        ]),
        Section(title: "Times, dates and time zones", note: "Cities, countries and zone abbreviations like PST or CET. Answers that use the clock update every minute.", examples: [
            "now", "now in Tokyo", "time in Madrid", "PST time", "3pm PST in CET", "2:30 pm HKT in Berlin",
            "9am + 3 hours 30 min", "5:30pm - 9am", "today + 3 weeks", "Dec 25 - today", "2026-12-25 + 1 month",
            "fromunix(1446587186)", "now in unix",
        ]),
        Section(title: "Screen units", note: "1 em is 16 px and a pixel is 1/96 inch unless Settings or a line like em = 20px or ppi = 326 says otherwise.", examples: [
            "12 pt in px", "2 em in px", "24 px in em", "1 inch in px", "em = 20px", "1.5 em in px",
        ]),
        Section(title: "Functions and constants", note: "Trigonometry uses radians unless you add °.", examples: [
            "sqrt 16 + 2", "square root of 81", "round(2.5)", "round(3.14159, 2)", "abs(-4)", "log 1000",
            "log 2 (8)", "root 3 (27)", "ln(e)", "sin(30°)", "cosh 0", "pi * 2",
        ]),
        Section(title: "Number formats and bits", note: "& | xor << >> work on whole numbers.", examples: [
            "0xff + 1", "255 in hex", "10 in binary", "1500 in sci", "1.5e3", "12 & 10", "12 | 3", "12 xor 10",
            "1 << 8", "(0xF0 | 0x0F) in hex",
        ]),
        Section(title: "Money", note: "Same-currency math always works. Converting needs exchange rates: turn them on in Settings, or write your own rate on a line.", examples: [
            "$20 + $5", "€12.50 * 4", "1 USD = 1.37 CAD", "50 USD in CAD",
        ]),
    ]

    /// Every example as one sheet, so `price * qty` sees `price`.
    public static var allExamples: [String] { sections.flatMap(\.examples) }
}
