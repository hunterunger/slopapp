import AppKit
import SwiftUI
import Testing
@testable import SlopKit

/// A window that sizes itself to its SwiftUI content (`sizingOptions = .preferredContentSize`),
/// the way `MenuBarExtra(.window)` panels are hosted. Hairlines inside it used to make AppKit
/// throw from its constraint pass at launch (the line's layout size followed the display scale).
/// The throw itself needs a running app's display cycle: the gallery reproduces it
/// (`GALLERY_DEMO=selfsizing`); these tests pin the layout rule that prevents it.
@MainActor @Suite struct SelfSizingWindowTests {
    struct Panel: View {
        var rows: Int
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(0..<rows, id: \.self) { row in
                    Text("Row \(row)")
                    Hairline()
                }
                HStack {
                    Text("Left")
                    Hairline(axis: .vertical).frame(height: 16)
                    Text("Right")
                }
                Text("Bordered").padding(Spacing.s)
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                Text("Panel").padding(Spacing.s)
                    .windowConcentric(fill: .quaternary, inset: Spacing.s, hairline: Color(nsColor: .separatorColor))
            }
            .padding(Spacing.m)
            .frame(width: Metrics.menuBarWindowWidth)
        }
    }

    @Test func hairlinesInASelfSizingWindowLayOutWithoutThrowing() {
        let hosting = NSHostingController(rootView: Panel(rows: 2))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        for rows in [3, 1, 5, 2] {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.rootView = Panel(rows: rows)
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        // Whole points: nothing fractional fed back into the window's size.
        let size = window.contentLayoutRect.size
        #expect(size.height == size.height.rounded())
        window.close()
    }

    /// The crash came from the line's layout size following the display scale (0.5 pt once
    /// a Retina window had it, 1 pt before). The layout is now a fixed whole point.
    @Test(arguments: [1.0, 2.0, 3.0])
    func hairlineLaysOutOnePointWhateverTheScale(scale: CGFloat) {
        let horizontal = NSHostingController(rootView: Hairline().frame(width: 100).environment(\.displayScale, scale))
        #expect(horizontal.sizeThatFits(in: CGSize(width: 100, height: 1000)).height == Hairline.layoutThickness)
        let vertical = NSHostingController(rootView: Hairline(axis: .vertical).frame(height: 100).environment(\.displayScale, scale))
        #expect(vertical.sizeThatFits(in: CGSize(width: 1000, height: 100)).width == Hairline.layoutThickness)
    }
}
