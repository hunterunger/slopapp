import FocusCore
import SlopKit
import SwiftUI

/// The big round timer: a clock face of 60 minute ticks with a ring showing the minutes left
/// (one turn is an hour, like a kitchen timer). When nothing runs, dragging around the ring
/// sets the session length in 5-minute steps; arrow keys and VoiceOver adjust it too.
struct FocusDial: View {
    /// Minutes the ring covers (fractional while running).
    let minutes: Double
    let tint: Color
    /// The text in the middle ("24:26").
    let time: String
    /// The line under it ("Focus", "Paused").
    let caption: String
    var size: CGFloat = 220
    /// Set when the length can be changed by dragging (idle).
    var onSetMinutes: ((Int) -> Void)?

    private var fraction: Double { min(max(minutes / 60, 0), 1) }
    private var ringWidth: CGFloat { max(6, size * 0.075) }
    private var tickInset: CGFloat { size * 0.02 }
    private var ringInset: CGFloat { size * 0.13 }

    var body: some View {
        ZStack {
            // Resolved label colours rather than hierarchical styles: inside the menu bar
            // panel's glass, `.tertiary` went vibrant and the Canvas ticks vanished.
            Ticks(size: size)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            Circle()
                .inset(by: ringInset)
                .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: ringWidth)
            Circle()
                .inset(by: ringInset)
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if onSetMinutes != nil {
                knob
            }
            // The digits sit on the dial's centre; the caption hangs below them (an invisible
            // copy above keeps the stack symmetric), so the time doesn't ride up when there's
            // a caption and is centred the same in every state.
            VStack(spacing: size * 0.01) {
                captionText.hidden()
                Text(time)
                    .font(.system(size: size * 0.17, weight: .light).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                captionText
            }
            .frame(width: size * 0.62)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(dragToSet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue("\(time), \(caption)")
        .modifier(Adjustable(minutes: Int(minutes.rounded()), onSetMinutes: onSetMinutes))
    }

    private var captionText: some View {
        Text(caption)
            .font(size > 160 ? .callout : .caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// A handle at the end of the ring, showing it can be dragged.
    private var knob: some View {
        let radius = size / 2 - ringInset
        let angle = Angle.degrees(fraction * 360 - 90)
        return Circle()
            .fill(.background)
            .overlay(Circle().stroke(tint, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .frame(width: ringWidth * 1.6, height: ringWidth * 1.6)
            .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
    }

    private var dragToSet: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onSetMinutes else { return }
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                guard hypot(dx, dy) > size * 0.15 else { return }
                // Angle clockwise from 12 o'clock, 0..<360.
                var degrees = atan2(dx, -dy) * 180 / .pi
                if degrees < 0 { degrees += 360 }
                let snapped = Int((degrees / 6 / 5).rounded()) * 5
                onSetMinutes(min(60, max(5, snapped)))
            }
    }

    private struct Ticks: View {
        let size: CGFloat

        var body: some View {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = canvasSize.width / 2 - 1
                for tick in 0..<60 {
                    let major = tick % 5 == 0
                    let length = major ? size * 0.06 : size * 0.03
                    let angle = Double(tick) / 60 * 2 * .pi - .pi / 2
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                    path.addLine(to: CGPoint(x: center.x + (outer - length) * cos(angle), y: center.y + (outer - length) * sin(angle)))
                    context.stroke(path, with: .foreground, lineWidth: major ? max(1.5, size * 0.009) : 1)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Increment/decrement by 5 minutes for VoiceOver.
    private struct Adjustable: ViewModifier {
        let minutes: Int
        let onSetMinutes: ((Int) -> Void)?

        func body(content: Content) -> some View {
            if let onSetMinutes {
                content.accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onSetMinutes(min(TimerSettings.focusRange.upperBound, minutes + 5))
                    case .decrement: onSetMinutes(max(5, minutes - 5))
                    @unknown default: break
                    }
                }
            } else {
                content
            }
        }
    }
}
