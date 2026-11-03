import Foundation
import Testing
@testable import TallyCore

/// Single lines beyond the corpus: each is evaluated alone.
let singleLines: [(String, String)] = [
    // Numbers and operators
    ("12", "12"), (".5 + .25", "0.75"), ("1,234,567", "1,234,567"), ("2.50", "2.5"),
    ("1.5E3", "1,500"), ("2e-3", "0.002"), ("0b1010", "10"), ("0o17", "15"), ("0xFF", "255"),
    ("10 − 3", "7"), ("6 × 7", "42"), ("84 ÷ 2", "42"), ("2 ** 8", "256"), ("3 x 4", "12"), ("3x4", "12"),
    ("5 plus 3 minus 1", "7"), ("6 multiplied by 7", "42"), ("-7 mod 3", "2"), ("(1 + 2", "3"),
    ("2 ^ -1", "0.5"), ("10 ^ 400", "err(number too large)"), ("2 ^ 0.5", "1.414213562"),
    ("5!", "120"), ("3.5!", "err(factorial needs a whole number)"), ("12 * 4 =", "48"),
    ("1000000 * 1000000", "1,000,000,000,000"), ("10 ^ 20", "1e20"), ("1 / 10 ^ 12", "1e-12"),
    ("123456789012.345", "123,456,789,012"), ("0.1 * 3", "0.3"), ("1 / 3 * 3", "1"),
    ("2 pi", "6.283185307"), ("2(3)(4)", "24"), ("-(2 + 3)", "-5"), ("--5", "5"), ("+5", "5"),
    ("1.5 million", "1,500,000"), ("3 thousand + 1", "3,001"), ("2.5k * 2", "5,000"),
    ("e", "2.718281828"), ("π", "3.141592654"),
    // Percent
    ("20% + 5%", "25%"), ("50% * 50%", "25%"), ("200 * 5%", "10"), ("5% * 200", "10"),
    ("20 percent of 150", "30"), ("0.25 in %", "25%"), ("1 as % of 8", "12.5%"),
    ("$100 + 8%", "$108.00"), ("10% off $40", "$36.00"), ("5 km + 10%", "5.5 km"),
    ("20% of 3 kg", "0.6 kg"), ("50 as % of 200", "25%"), ("20% + 150", "err(incompatible units)"),
    // Units
    ("5 km + 2", "7 km"), ("3 + 2 m", "5 m"), ("2 m * 3", "6 m"), ("1 mile in km", "1.609344 km"),
    ("1 nmi in km", "1.852 km"), ("12 inches in cm", "30.48 cm"), ("5 feet in m", "1.524 m"),
    ("1 kg in lb", "2.204622622 lb"), ("16 oz in lb", "1 lb"), ("1 stone in kg", "6.35029318 kg"),
    ("1 tonne in kg", "1,000 kg"), ("8 bits in bytes", "1 B"), ("1 B in bits", "8 bits"),
    ("1 MiB in KiB", "1,024 KiB"), ("1 GB in GiB", "0.9313225746 GiB"), ("1 Gb in MB", "125 MB"),
    ("750 MB in GiB", "0.698491931 GiB"), ("1 day in hours", "24 h"), ("1 week in days", "7 days"),
    ("1 year in days", "365 days"), ("1 month in days", "30.41666667 days"), ("1 day", "1 day"),
    ("3600 s in h", "1 h"), ("500 ms in s", "0.5 s"), ("1.5 h in min", "90 min"),
    ("2 m * 3 m", "6 m²"), ("2 m * 3 ft", "1.8288 m²"), ("(3 m)^2", "9 m²"), ("2 m ^ 3", "8 m³"),
    ("10 m² / 2 m", "5 m"), ("1 sq km in ha", "100 ha"), ("1 acre in sq m", "4,046.856422 m²"),
    ("2 square feet in square inches", "288 in²"), ("1 cu m in L", "1,000 L"), ("1 gallon in L", "3.785411784 L"),
    ("2 cups in mL", "473.176473 mL"), ("3 tsp in tbsp", "1 tbsp"), ("100 °C in F", "212 °F"),
    ("98.6 F in C", "37 °C"), ("-40 °C in °F", "-40 °F"), ("20°C + 5", "25 °C"), ("300 K in °C", "26.85 °C"),
    ("180° in rad", "3.141592654 rad"), ("cos(60 deg)", "0.5"), ("sin(pi / 2)", "1"), ("cos(90°)", "0"),
    ("tan 45°", "1"), ("5 ft 11 inches in cm", "180.34 cm"), ("5 ft 11 in in cm", "—"), ("1 m 20 cm", "1.2 m"), ("2 h 15 min", "2.25 h"),
    ("1 m 5 kg", "—"), ("5 kg * 3 m", "err(incompatible units)"), ("1 / 5 km", "err(incompatible units)"),
    ("10 km / 2 km", "5"), ("5 km in kg", "err(incompatible units)"), ("6 km mod 4 km", "2 km"),
    ("5km", "5 km"), ("3m", "3 m"), ("2 Kilometers in Meters", "2,000 m"), ("1 hr in mins", "60 min"),
    // Functions
    ("sqrt(16)", "4"), ("sqrt 2", "1.414213562"), ("sqrt(-1)", "err(not a real number)"), ("cbrt 27", "3"),
    ("abs(-5)", "5"), ("abs(-3 kg)", "3 kg"), ("round(2.4)", "2"), ("round(-2.5)", "-3"), ("round(3.14159, 2)", "3.14"),
    ("ceil(2.1)", "3"), ("floor(2.9)", "2"), ("ceil(-2.5)", "-2"), ("floor(-2.5)", "-3"), ("ln(e)", "1"),
    ("log 1000", "3"), ("log(8, 2)", "3"), ("ln 0", "err(not a real number)"), ("exp(0)", "1"), ("fact(5)", "120"),
    ("round(12.345%)", "12%"), ("sqrt(25 m²)", "5 m"), ("asin(1) in deg", "90°"), ("asin(1)", "1.570796327 rad"), ("90°", "90°"), ("sin(asin(0.5))", "0.5"),
    // Number styles
    ("255 in hex", "0xFF"), ("10 in binary", "0b1010"), ("8 in oct", "0o10"), ("1500 in sci", "1.5e3"),
    ("0xff in dec", "255"), ("2.5 in hex", "err(hex needs a whole number)"),
    // Text and notes
    ("Tip: 18% of 40", "7.2"), ("\"Dinner\" 40 + 2", "42"), ("40 + 2 // tip", "42"), ("12:30", "—"),
    ("3 apples + 2", "—"), ("apples", "—"), ("apples + 2", "err(unknown name “apples”)"),
    ("Groceries 3 + 4", "—"), ("the total is 5", "—"), ("5 +", "—"), ("* 5", "—"), ("()", "—"),
    ("in", "—"), ("km", "—"), ("5 in", "—"), ("what?", "—"), ("Total 1200 + 85", "—"),
    ("Café: 4.50 * 2", "9"), ("数字: 2 + 2", "4"),
    // Currency without rates
    ("$5", "$5.00"), ("5$", "$5.00"), ("€10 + €5", "€15.00"), ("£3 * 2", "£6.00"), ("¥1000 + 500", "¥1,500"),
    ("10 usd + 5", "$15.00"), ("20 EUR / 4", "€5.00"), ("100 CAD", "100.00 CAD"), ("USD 100", "$100.00"),
    ("5 dollars", "$5.00"), ("3 euros + 1 euro", "€4.00"), ("-$5", "-$5.00"), ("$10 / $4", "2.5"),
    ("$1.5k", "$1,500.00"), ("₹100", "₹100.00"), ("$5 + 3 kg", "err(incompatible units)"),
    ("100 USD in EUR", "err(rates off)"), ("$1 in GBP", "err(rates off)"), ("1000 JPY", "¥1,000"),
    ("5 pounds in kg", "2.26796185 kg"),
]

@Test(arguments: Array(singleLines.indices))
func singleLine(_ index: Int) {
    let (input, expected) = singleLines[index]
    #expect(calc(input) == expected, "\(input)")
}
