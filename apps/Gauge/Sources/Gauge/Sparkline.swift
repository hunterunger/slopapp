import GaugeCore
import SlopKit
import SwiftUI

/// A history graph over a fixed, labelled span. Time runs left to right with "now" at the
/// right edge, so a spike's position says how long ago it happened. Gaps (sleep) break the
/// line instead of joining across them. Nothing animates.
/// A history graph over a fixed, labelled span. Time runs left to right with "now" at the
/// right edge, so a spike's position says how long ago it happened. Gaps (sleep) break the
/// line instead of joining across them. Nothing animates.
///
/// Drawn with shapes, not a `Canvas`: on macOS 27 a Canvas filled with a saturated colour (the
/// accent) made the panel allocate about 220 MB of graphics memory.
struct Sparkline: View {
    struct Series {
        var points: [TimeSeries.Point]
        var color: Color
        var filled: Bool
    }

    let series: [Series]
    let span: HistorySpan
    let now: Double
    /// The value at the top edge.
    let ceiling: Double
    var lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                let runs = Self.runs(line.points, span: span, now: now, ceiling: ceiling)
                if line.filled {
                    RunsShape(runs: runs, area: true, inset: lineWidth / 2).fill(line.color.opacity(0.18))
                }
                RunsShape(runs: runs, area: false, inset: lineWidth / 2)
                    .stroke(line.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// Points as fractions of the graph (x: 0 = start of the span, 1 = now; y: 0 = bottom),
    /// split into runs at gaps.
    static func runs(_ points: [TimeSeries.Point], span: HistorySpan, now: Double, ceiling: Double) -> [[CGPoint]] {
        let start = now - span.seconds
        let scale = ceiling > 0 ? ceiling : 1
        var runs: [[CGPoint]] = [[]]
        for p in points where p.time >= start - 60 {
            if p.isGap {
                if !(runs.last?.isEmpty ?? true) { runs.append([]) }
            } else {
                runs[runs.count - 1].append(CGPoint(x: (p.time - start) / span.seconds,
                                                    y: min(1, max(0, Double(p.value) / scale))))
            }
        }
        return runs.filter { !$0.isEmpty }
    }

    /// A ceiling for rates: the peak in view, with headroom, never under 10 KB/s so a quiet
    /// line stays near the bottom instead of filling the graph with noise.
    static func rateCeiling(_ series: [[TimeSeries.Point]]) -> Double {
        let peak = series.flatMap { $0 }.lazy.filter { !$0.isGap }.map { Double($0.value) }.max() ?? 0
        return max(10_000, peak * 1.15)
    }
}

/// The line through each run, or the area under it.
private struct RunsShape: Shape {
    let runs: [[CGPoint]]
    let area: Bool
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let height = rect.height - inset * 2
        for run in runs {
            let points = run.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.maxY - inset - $0.y * height) }
            let line = points.count == 1 ? [points[0], CGPoint(x: points[0].x + 1, y: points[0].y)] : points
            if area, let first = line.first, let last = line.last {
                path.move(to: CGPoint(x: first.x, y: rect.maxY))
                path.addLines(line)
                path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                path.closeSubpath()
            } else {
                path.addLines(line)
            }
        }
        return path
    }
}

/// The graph with its frame and caption: "Last 10 min" on the left, a span switch on the
/// right, and a spoken summary for VoiceOver.
struct HistoryGraph: View {
    let title: String
    let series: [Sparkline.Series]
    let span: HistorySpan
    let now: Double
    let ceiling: Double
    let summary: String
    let height: CGFloat
    @Binding var spanSelection: HistorySpan

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Sparkline(series: series, span: span, now: now, ceiling: ceiling)
                .padding(.vertical, Spacing.xs)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(.quaternary.opacity(0.35)))
                .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel("\(title), \(span.spokenTitle)")
                .accessibilityValue(summary)
            HStack(spacing: Spacing.s) {
                Text(summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Picker("History", selection: $spanSelection) {
                    ForEach(HistorySpan.allCases, id: \.self) { span in
                        Text(span.title).tag(span)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .accessibilityLabel("History span")
            }
        }
    }
}
