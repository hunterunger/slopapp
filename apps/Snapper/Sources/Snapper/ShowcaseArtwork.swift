import AppKit
import Charts
import SlopKit
import SwiftUI

/// Made-up screens for the store screenshots (docs/screenshots.md): what a capture of a
/// sales dashboard, a checklist, a chat or a calendar looks like. Every name, number and
/// address is invented; nothing is read from the Mac. Rendered with `ImageRenderer` at 2x in
/// the app's appearance, so the dark set shows dark-mode "screenshots".
@MainActor
enum ShowcaseArtwork {
    enum Kind: CaseIterable {
        case dashboard, checklist, chat, palette, calendar, landscape
    }

    static func image(_ kind: Kind, size: CGSize, variant: Int = 0) -> CGImage? {
        let view = Group {
            switch kind {
            case .dashboard: SalesDashboard()
            case .checklist: LaunchChecklist()
            case .chat: ChatThread()
            case .palette: PaletteBoard(variant: variant)
            case .calendar: WeekCalendar()
            case .landscape: Landscape(variant: variant)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }
}

// MARK: - Pieces

private struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(.separator, lineWidth: 1))
    }
}

// MARK: - Dashboard (the hero)

struct SalesDashboard: View {
    struct Day: Identifiable {
        let name: String
        let sales: Double
        var id: String { name }
    }

    static let days = [
        Day(name: "Mon", sales: 1420), Day(name: "Tue", sales: 1510), Day(name: "Wed", sales: 1630),
        Day(name: "Thu", sales: 1580), Day(name: "Fri", sales: 2040), Day(name: "Sat", sales: 2610),
        Day(name: "Sun", sales: 1690),
    ]

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Weekly sales").font(.system(size: 30, weight: .bold))
                        Text("Larkspur Coffee · 3–9 November").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(["Day", "Week", "Month"], id: \.self) { period in
                            Text(period)
                                .font(.headline)
                                .padding(.horizontal, Spacing.l)
                                .padding(.vertical, Spacing.s)
                                .background(period == "Week" ? AnyShapeStyle(.orange.opacity(0.2)) : AnyShapeStyle(.clear),
                                            in: Capsule())
                        }
                    }
                    .padding(Spacing.xs)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                }
                HStack(spacing: Spacing.l) {
                    kpi("Revenue", "$12,480", "+8.2%")
                    kpi("Orders", "1,204", "+3.1%")
                    kpi("Average order", "$10.36", "+4.9%")
                    kpi("New customers", "86", "+12")
                }
                HStack(alignment: .top, spacing: Spacing.l) {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Text("Sales by day").font(.headline)
                            Chart(Self.days) { day in
                                BarMark(x: .value("Day", day.name), y: .value("Sales", day.sales))
                                    .foregroundStyle(day.name == "Sat" ? AnyShapeStyle(.orange) : AnyShapeStyle(.orange.opacity(0.45)))
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                            }
                            .chartYAxis { AxisMarks(position: .leading, values: [0, 1000, 2000, 3000]) }
                            .frame(height: 250)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Text("Top items").font(.headline)
                            ForEach([("Oat flat white", "312"), ("Cold brew", "248"), ("Cardamom bun", "191"),
                                     ("Matcha latte", "142"), ("Almond croissant", "117")], id: \.0) { item in
                                HStack {
                                    Text(item.0)
                                    Spacer()
                                    Text(item.1).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.body)
                            }
                        }
                    }
                    .frame(width: 300)
                }
                HStack(spacing: Spacing.s) {
                    Image(systemName: "envelope")
                    Text("Report sent every Monday to dana.reyes@larkspur.example")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func kpi(_ title: String, _ value: String, _ change: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text(change).font(.callout.weight(.medium)).foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Checklist (the background shot)

struct LaunchChecklist: View {
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Friday release").font(.system(size: 28, weight: .bold))
                    Text("Version 2.4 · 4 of 6 done").font(.title3).foregroundStyle(.secondary)
                }
                ForEach(Array([
                    ("Freeze the release branch", true), ("Update the screenshots", true),
                    ("Write the release notes", true), ("Translate the new strings", true),
                    ("Send the newsletter", false), ("Tag and publish", false),
                ].enumerated()), id: \.offset) { _, task in
                    HStack(spacing: Spacing.m) {
                        Image(systemName: task.1 ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(task.1 ? AnyShapeStyle(.indigo) : AnyShapeStyle(.tertiary))
                        Text(task.0)
                            .font(.title3)
                            .strikethrough(task.1, color: .secondary)
                            .foregroundStyle(task.1 ? .secondary : .primary)
                    }
                }
            }
        }
    }
}

// MARK: - History thumbnails

struct ChatThread: View {
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Spacing.m) {
                bubble("Are the new screenshots ready?", mine: false)
                bubble("Almost. Fixing one arrow.", mine: true)
                bubble("No rush, launch is at 4.", mine: false)
                bubble("Sent. Check your inbox.", mine: true)
            }
            .font(.title3)
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            Text(text)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .foregroundStyle(mine ? .white : .primary)
                .background(mine ? AnyShapeStyle(.blue) : AnyShapeStyle(.quaternary), in: Capsule())
            if !mine { Spacer() }
        }
    }
}

struct PaletteBoard: View {
    let variant: Int
    var body: some View {
        let colours: [Color] = variant == 0
            ? [.orange, .pink, .purple, .indigo, .teal, .mint]
            : [.red, .yellow, .green, .cyan, .blue, .brown]
        Surface {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(variant == 0 ? "Spring palette" : "Poster colours").font(.system(size: 28, weight: .bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.l), count: 3), spacing: Spacing.l) {
                    ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                        RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(colour.gradient).frame(height: 120)
                    }
                }
            }
        }
    }
}

struct WeekCalendar: View {
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("This week").font(.system(size: 28, weight: .bold))
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri"].enumerated()), id: \.offset) { index, day in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text(day).font(.headline).foregroundStyle(.secondary)
                            ForEach(0..<(2 + index % 3), id: \.self) { slot in
                                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                    .fill([Color.blue, .green, .orange, .purple][(index + slot) % 4].opacity(0.3))
                                    .frame(height: CGFloat(48 + (index * 17 + slot * 29) % 60))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

struct Landscape: View {
    let variant: Int
    var body: some View {
        ZStack {
            LinearGradient(colors: variant == 0 ? [.orange, .pink] : [.teal, .blue], startPoint: .top, endPoint: .bottom)
            Circle().fill(.yellow.opacity(0.85)).frame(width: 140).offset(x: 160, y: -90)
            Ellipse().fill(.green.opacity(0.75)).frame(width: 900, height: 360).offset(x: -180, y: 260)
            Ellipse().fill(.green).frame(width: 900, height: 320).offset(x: 260, y: 300)
        }
        .clipped()
    }
}
