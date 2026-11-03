import AppKit
import SwiftUI

// A two-pane split that keeps its proportion when the window or content changes (SwiftUI's
// HSplitView/VSplitView don't). Drag the divider to resize; double-click it to reset to
// half and half. The fraction can be persisted. Candidate for SlopKit.

struct SplitStack<First: View, Second: View>: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    @Binding var fraction: Double
    var minimum: CGFloat = 160
    var accessibilityLabel = "Pane divider"
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    @State private var dragStart: Double?
    private let handle: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let usable = max(0, total - handle)
            let firstLength = clampedLength(usable: usable)
            let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                first()
                    .frame(width: axis == .horizontal ? firstLength : nil, height: axis == .vertical ? firstLength : nil)
                divider(usable: usable)
                second()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func clampedLength(usable: CGFloat) -> CGFloat {
        guard usable > minimum * 2 else { return usable / 2 }
        return min(max(usable * fraction, minimum), usable - minimum)
    }

    private func divider(usable: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .horizontal ? handle : nil, height: axis == .vertical ? handle : nil)
            .overlay {
                // A wider invisible grab area than the 1 pt line.
                Color.clear
                    .frame(width: axis == .horizontal ? 9 : nil, height: axis == .vertical ? 9 : nil)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                guard usable > 0 else { return }
                                let start = dragStart ?? fraction
                                if dragStart == nil { dragStart = start }
                                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                                fraction = min(max(start + Double(delta / usable), 0.1), 0.9)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .onTapGesture(count: 2) { fraction = 0.5 }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = min(fraction + 0.05, 0.9)
                case .decrement: fraction = max(fraction - 0.05, 0.1)
                @unknown default: break
                }
            }
    }
}
