import Foundation
import Testing
@testable import TallyCore

/// A realistic big sheet: the corpus repeated, with unique variable names per block.
func bigSheet(lines count: Int) -> [String] {
    var lines: [String] = []
    var block = 0
    while lines.count < count {
        for (input, _) in corpus {
            lines.append(input.replacingOccurrences(of: "price", with: "price\(block)"))
            if lines.count == count { break }
        }
        block += 1
    }
    return lines
}

/// Median wall time of `runs` executions, in milliseconds.
func medianMillis(runs: Int = 21, _ body: () -> Void) -> Double {
    var times: [Double] = []
    let clock = ContinuousClock()
    for _ in 0..<runs {
        let d = clock.measure(body)
        times.append(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
    }
    return times.sorted()[runs / 2]
}

@Suite(.serialized) struct Performance {
    /// One keystroke in a 1,000-line sheet: split, re-evaluate every line (cache hits for
    /// unchanged lines) and format every result. Budget: one 120 Hz frame (8 ms) in release;
    /// debug builds are several times slower, so they get a looser bound.
    @Test func keystrokeInAThousandLineSheet() {
        var lines = bigSheet(lines: 1000)
        let engine = SheetEngine()
        let formatter = ResultFormatter(locale: usLocale)
        let context = SheetContext(rates: .loaded(fixtureRates, stale: false))
        _ = engine.evaluate(lines: lines, context: context) // warm the parse cache
        var keystroke = 0
        let ms = medianMillis {
            keystroke += 1
            lines[500] = "price3 * \(keystroke)"
            let text = lines.joined(separator: "\n")
            let outputs = engine.evaluate(text, context: context)
            var chars = 0
            for o in outputs { if let q = o.result.quantity { chars += formatter.format(q).count } }
            #expect(chars > 0)
        }
        print("TALLY_PERF keystroke_1000_lines_ms=\(String(format: "%.2f", ms))")
        #expect(ms < Self.budget(release: 8, debug: 80))
    }

    /// Pasting 5,000 new lines (nothing cached): the research doc's "huge sheet" edge case.
    @Test func coldFiveThousandLineSheet() {
        let lines = bigSheet(lines: 5000)
        let context = SheetContext(rates: .loaded(fixtureRates, stale: false))
        let ms = medianMillis(runs: 5) {
            _ = SheetEngine().evaluate(lines: lines, context: context)
        }
        print("TALLY_PERF cold_5000_lines_ms=\(String(format: "%.2f", ms))")
        #expect(ms < Self.budget(release: 100, debug: 1000))
    }

    static func budget(release: Double, debug: Double) -> Double {
        // Shared CI runners are much slower than a real Mac; give them 4x headroom.
        let slack: Double = ProcessInfo.processInfo.environment["CI"] == nil ? 1 : 4
        #if DEBUG
        return debug * slack
        #else
        return release * slack
        #endif
    }
}
