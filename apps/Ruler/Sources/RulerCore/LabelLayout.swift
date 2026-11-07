import CoreGraphics
import Foundation

/// Where labels and the magnifier go on the overlay, so readouts never sit on top of each
/// other. Pure geometry in view points with a y-up origin (AppKit's), so it's testable.
public enum LabelLayout {
    /// The live hover readout: one "W × H" pill down-right of the pointer, flipped left or
    /// up near the display edges.
    public static func cursorPill(size: CGSize, pointer: CGPoint, bounds: CGRect, offset: CGFloat = 14) -> CGRect {
        var x = pointer.x + offset
        var y = pointer.y - offset - size.height
        if x + size.width > bounds.maxX { x = pointer.x - offset - size.width }
        if y < bounds.minY { y = pointer.y + offset }
        return clamp(CGRect(origin: CGPoint(x: x, y: y), size: size), to: bounds)
    }

    /// An area's size label: centered inside it when it fits with room to spare, else just
    /// below it (or above, at the bottom of the display).
    public static func areaLabel(size: CGSize, box: CGRect, bounds: CGRect, gap: CGFloat = 6) -> CGRect {
        let inside = box.width >= size.width + 2 * gap && box.height >= size.height + 2 * gap
        var frame: CGRect
        if inside {
            frame = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        } else {
            frame = CGRect(x: box.midX - size.width / 2, y: box.minY - gap - size.height, width: size.width, height: size.height)
            if frame.minY < bounds.minY { frame.origin.y = box.maxY + gap }
        }
        return clamp(frame, to: bounds)
    }

    /// A held distance's (or a guide gap's) label: centered on its line, like a pill threaded
    /// on it, when the line shows at least `gap` past both of its ends. A shorter line would be
    /// hidden under its own number, ends included, so the label goes beside it instead: above
    /// a horizontal line, right of a vertical one (flipped at the display edge), clear of the
    /// T ends by `clearance`.
    public static func lineLabel(size: CGSize, from a: CGPoint, to b: CGPoint, bounds: CGRect,
                                 gap: CGFloat = 6, clearance: CGFloat = 4) -> CGRect {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var frame = CGRect(x: mid.x - size.width / 2, y: mid.y - size.height / 2, width: size.width, height: size.height)
        let horizontal = abs(b.x - a.x) >= abs(b.y - a.y)
        let length = horizontal ? abs(b.x - a.x) : abs(b.y - a.y)
        if (horizontal ? size.width : size.height) + 2 * gap > length {
            if horizontal {
                frame.origin.y = mid.y + clearance + gap
                if frame.maxY > bounds.maxY { frame.origin.y = mid.y - clearance - gap - size.height }
            } else {
                frame.origin.x = mid.x + clearance + gap
                if frame.maxX > bounds.maxX { frame.origin.x = mid.x - clearance - gap - size.width }
            }
        }
        return clamp(frame, to: bounds)
    }

    /// The magnifier: the first corner around the pointer (up-left, up-right, down-left,
    /// down-right) that's on screen and clear of `avoiding` (the readout pill and other
    /// labels). If none is clear, the one overlapping least.
    public static func magnifier(size: CGSize, pointer: CGPoint, bounds: CGRect, avoiding: [CGRect], offset: CGFloat = 28) -> CGRect {
        // Each corner at a growing distance, so a corner squeezed by the readout still works.
        var candidates: [CGRect] = []
        for extra: CGFloat in [0, 40, 80] {
            let d = offset + extra
            candidates += [
                CGPoint(x: pointer.x - d - size.width, y: pointer.y + d),
                CGPoint(x: pointer.x + d, y: pointer.y + d),
                CGPoint(x: pointer.x - d - size.width, y: pointer.y - d - size.height),
                CGPoint(x: pointer.x + d, y: pointer.y - d - size.height),
            ].map { CGRect(origin: $0, size: size) }
        }
        let onScreen = candidates.filter { bounds.contains($0) }
        if let clear = onScreen.first(where: { overlap($0, avoiding) == 0 }) { return clear }
        let pool = onScreen.isEmpty ? candidates.map { clamp($0, to: bounds) } : onScreen
        return pool.min { overlap($0, avoiding) < overlap($1, avoiding) } ?? pool[0]
    }

    /// Moves labels off the ones placed before them (earlier labels win), trying small
    /// steps down, up, right and left. Labels that can't be freed stay where they were.
    public static func separate(_ frames: [CGRect], bounds: CGRect, spacing: CGFloat = 4) -> [CGRect] {
        var placed: [CGRect] = []
        for frame in frames {
            guard placed.contains(where: { $0.insetBy(dx: -spacing / 2, dy: -spacing / 2).intersects(frame) }) else {
                placed.append(frame)
                continue
            }
            var best = frame
            search: for step in 1...12 {
                let d = CGFloat(step) * (frame.height + spacing) / 2
                for offset in [CGVector(dx: 0, dy: -d), CGVector(dx: 0, dy: d), CGVector(dx: d, dy: 0), CGVector(dx: -d, dy: 0)] {
                    let moved = frame.offsetBy(dx: offset.dx, dy: offset.dy)
                    guard bounds.contains(moved) else { continue }
                    if !placed.contains(where: { $0.insetBy(dx: -spacing / 2, dy: -spacing / 2).intersects(moved) }) {
                        best = moved
                        break search
                    }
                }
            }
            placed.append(best)
        }
        return placed
    }

    public static func clamp(_ rect: CGRect, to area: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, area.minX), area.maxX - r.width)
        r.origin.y = min(max(r.minY, area.minY), area.maxY - r.height)
        return r
    }

    static func overlap(_ rect: CGRect, _ others: [CGRect]) -> CGFloat {
        others.reduce(0) { total, other in
            let i = rect.intersection(other)
            return total + (i.isNull ? 0 : i.width * i.height)
        }
    }
}

/// Which part of the frozen display a measurement screenshot shows.
public enum ScreenshotPlan {
    /// The crop: `subject` (a hovered area, or everything measured, in image pixels) grown
    /// by `padding`, kept inside the image, and — in test mode — inside `allowed`, so a
    /// screenshot can never contain anything but the test scene. Nil subject: the whole
    /// image (or all of `allowed`). Nil result: nothing allowed to capture.
    public static func crop(subject: PixelRect?, padding: Int, image: PixelRect, allowed: PixelRect?) -> PixelRect? {
        let limit = allowed.flatMap { $0.intersection(image) } ?? (allowed == nil ? image : nil)
        guard let limit else { return nil }
        guard let subject else { return limit }
        return subject.outsetBy(max(padding, 0)).intersection(limit)
    }

    /// "Ruler 2026-11-03 at 17.42.10.png", like macOS names screenshots.
    public static func fileName(date: DateComponents, ext: String) -> String {
        func two(_ n: Int?) -> String { n.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        return "Ruler \(date.year ?? 2000)-\(two(date.month))-\(two(date.day)) at \(two(date.hour)).\(two(date.minute)).\(two(date.second)).\(ext)"
    }
}

/// The image file a measurement screenshot is saved as.
public enum ScreenshotFormat: String, CaseIterable, Sendable, Identifiable {
    case png, jpeg

    public var id: String { rawValue }
    public var title: String { self == .png ? "PNG" : "JPEG" }
    public var fileExtension: String { self == .png ? "png" : "jpg" }
}
