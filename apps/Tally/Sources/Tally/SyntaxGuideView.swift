import SlopKit
import SwiftUI
import TallyCore

/// Help ▸ Syntax Guide: every example with its live result.
struct SyntaxGuideView: View {
    private struct Row: Identifiable {
        let id: String
        let example: String
        let result: String
        let isDimmed: Bool
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let note: String?
        let rows: [Row]
    }

    /// Each section is evaluated as its own little sheet, so `price * qty` sees `price`.
    private let groups: [Group] = {
        let formatter = ResultFormatter(locale: .current, dollarCode: Pref.dollar)
        return SyntaxGuide.sections.map { section in
            let outputs = SheetEngine().evaluate(lines: section.examples)
            let rows = zip(section.examples, outputs).enumerated().map { i, pair in
                let (example, out) = pair
                switch out.result {
                case .value(let q):
                    return Row(id: "\(section.id)-\(i)", example: example, result: formatter.format(q), isDimmed: false)
                case .error(let e):
                    return Row(id: "\(section.id)-\(i)", example: example, result: e.message, isDimmed: true)
                case .none:
                    return Row(id: "\(section.id)-\(i)", example: example, result: "", isDimmed: true)
                }
            }
            return Group(id: section.id, title: section.title, note: section.note, rows: rows)
        }
    }()

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    if let note = group.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.example)
                                .font(.body.monospacedDigit())
                                .textSelection(.enabled)
                            Spacer(minLength: Spacing.l)
                            Text(row.result)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(row.isDimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .frame(minWidth: 420, minHeight: 360)
    }
}
