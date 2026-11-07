import CoreGraphics
import Foundation

/// Where things go on the icon canvas. All rects are in unit coordinates (0...1, origin at
/// the bottom left, like Core Graphics), so the same layout renders at any pixel size.
public enum IconGeometry {
    /// Apple's macOS icon grid: an 824 pt tile with 100 pt margins on a 1024 pt canvas.
    public static let tileRect = CGRect(x: 100.0 / 1024, y: 100.0 / 1024, width: 824.0 / 1024, height: 824.0 / 1024)
    public static let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// The area the picture fits into at 100% size. Logos (transparent edges, trimmed to
    /// their visible part) get a margin so they don't touch the shape's outline; photos
    /// fill it.
    public static func contentRect(for shape: IconShape, logo: Bool = false, folder: FolderLayout = .standard,
                                   document: DocumentLayout = .standard) -> CGRect {
        switch shape {
        case .macOSApp: logo ? tileRect.insetBy(dx: tileRect.width * 0.14, dy: tileRect.height * 0.14) : tileRect
        case .rounded: logo ? canvas.insetBy(dx: 0.14, dy: 0.14) : canvas
        case .square: logo ? canvas.insetBy(dx: 0.12, dy: 0.12) : canvas
        // The largest square inside the circle, plus a little air.
        case .circle: logo ? canvas.insetBy(dx: 0.18, dy: 0.18) : canvas
        case .asIs: canvas
        case .folder: folder.art
        case .folderCover: logo ? folder.panel.insetBy(dx: folder.panel.width * 0.16, dy: folder.panel.height * 0.16) : folder.panel
        case .folderSymbol: folder.symbol
        case .document: document.art
        }
    }

    /// The area the picture is clipped to (nil: not clipped).
    public static func clipRect(for shape: IconShape, folder: FolderLayout = .standard, document: DocumentLayout = .standard) -> CGRect? {
        switch shape {
        case .macOSApp: tileRect
        case .rounded, .square, .circle: canvas
        case .asIs: nil
        case .folder, .folderCover, .folderSymbol: folder.panel
        case .document: document.page
        }
    }

    /// Where text goes (its line is centred in here, or put at the top or bottom).
    public static func textRect(for shape: IconShape, folder: FolderLayout = .standard, document: DocumentLayout = .standard) -> CGRect {
        switch shape {
        case .macOSApp: tileRect.insetBy(dx: tileRect.width * 0.1, dy: tileRect.height * 0.1)
        case .rounded, .square: canvas.insetBy(dx: 0.1, dy: 0.1)
        case .circle: canvas.insetBy(dx: 0.17, dy: 0.17)
        case .asIs: canvas.insetBy(dx: 0.05, dy: 0.05)
        case .folder, .folderCover, .folderSymbol:
            folder.panel.insetBy(dx: folder.panel.width * 0.08, dy: folder.panel.height * 0.12)
        case .document: document.page.insetBy(dx: document.page.width * 0.12, dy: document.page.height * 0.12)
        }
    }

    /// The picture's rect: fitted (or filled) into `content`, scaled about its centre, then offset.
    public static func artRect(aspect: CGFloat, style: IconStyle, content: CGRect) -> CGRect {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1
        let contentAspect = content.width / content.height
        var size: CGSize
        let widthLimited = aspect > contentAspect
        if widthLimited != style.fill {
            size = CGSize(width: content.width, height: content.width / aspect)
        } else {
            size = CGSize(width: content.height * aspect, height: content.height)
        }
        size.width *= style.scale
        size.height *= style.scale
        return CGRect(x: content.midX - size.width / 2 + style.offset.x,
                      y: content.midY - size.height / 2 + style.offset.y,
                      width: size.width, height: size.height)
    }

    /// Continuous-corner tile (a superellipse, close to the macOS icon shape).
    public static func superellipse(in rect: CGRect, steps: Int = 360) -> CGPath {
        let path = CGMutablePath()
        let n = 5.0, a = rect.width / 2, b = rect.height / 2
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
            let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
            step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    /// The clip outline of a shape in pixel space.
    public static func clipPath(for shape: IconShape, pixels: CGFloat, folder: FolderLayout = .standard,
                                document: DocumentLayout = .standard) -> CGPath? {
        guard let unit = clipRect(for: shape, folder: folder, document: document) else { return nil }
        let rect = unit.scaled(by: pixels)
        switch shape {
        case .macOSApp, .rounded: return superellipse(in: rect, steps: pixels <= 64 ? 120 : 360)
        case .circle: return CGPath(ellipseIn: rect, transform: nil)
        case .folder, .folderCover, .folderSymbol:
            let radius = rect.height * 0.08
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .document:
            let radius = rect.width * 0.03
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .square, .asIs: return CGPath(rect: rect, transform: nil)
        }
    }
}

/// Where the picture sits on the system folder icon, measured from the icon itself so it
/// follows whatever folder art the running macOS draws.
public struct FolderLayout: Equatable, Sendable {
    /// The folder's front panel (the picture is clipped to it).
    public var panel: CGRect
    /// The picture's area at 100% size.
    public var art: CGRect

    public init(panel: CGRect, art: CGRect) {
        self.panel = panel
        self.art = art
    }

    /// A symbol pressed into the folder: a little smaller than a picture, so it reads as a mark.
    public var symbol: CGRect { art.insetBy(dx: art.width * 0.08, dy: art.height * 0.08) }

    /// Measured from the macOS 26 folder icon. Used when measuring fails.
    public static let standard = FolderLayout(bounds: CGRect(x: 0.039, y: 0.129, width: 0.922, height: 0.742))

    /// Derives the layout from the folder's opaque bounds (unit coordinates): the back tab
    /// takes the top ~17%, the front panel the rest; the picture is a square in the panel.
    public init(bounds: CGRect) {
        let panelTop = bounds.maxY - bounds.height * 0.175
        let panel = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: panelTop - bounds.minY)
        let side = min(panel.height * 0.62, panel.width * 0.8)
        self.panel = panel
        self.art = CGRect(x: panel.midX - side / 2, y: panel.midY - side / 2, width: side, height: side)
    }

    /// Opaque bounds of an RGBA8 bitmap (premultiplied, rows top to bottom) in unit
    /// coordinates, or nil when the bitmap is empty.
    public static func opaqueBounds(alpha: (Int, Int) -> UInt8, width: Int, height: Int, threshold: UInt8 = 128) -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) >= threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let w = Double(width), h = Double(height)
        // Flip rows (top-down) to Core Graphics' bottom-up unit space.
        return CGRect(x: Double(minX) / w, y: 1 - Double(maxY + 1) / h,
                      width: Double(maxX - minX + 1) / w, height: Double(maxY - minY + 1) / h)
    }
}

/// Where the picture sits on the system's blank document icon.
public struct DocumentLayout: Equatable, Sendable {
    /// The page (the picture is clipped to it, a little inside its edge).
    public var page: CGRect
    /// The picture's area at 100% size.
    public var art: CGRect

    public init(page: CGRect, art: CGRect) {
        self.page = page
        self.art = art
    }

    /// Typical blank document proportions. Used when measuring fails.
    public static let standard = DocumentLayout(bounds: CGRect(x: 0.19, y: 0.06, width: 0.62, height: 0.88))

    /// Derives the layout from the document icon's opaque bounds: the page inset from its
    /// edge, and a square picture area a little below the middle (clear of the folded corner).
    public init(bounds: CGRect) {
        let page = bounds.insetBy(dx: bounds.width * 0.07, dy: bounds.height * 0.05)
        let side = min(page.width * 0.84, page.height * 0.62)
        self.page = page
        self.art = CGRect(x: page.midX - side / 2, y: page.minY + page.height * 0.44 - side / 2, width: side, height: side)
    }
}

extension CGRect {
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(x: minX * factor, y: minY * factor, width: width * factor, height: height * factor)
    }
}

/// The selection ring around a template's thumbnail: a band `gap` points outside the
/// template's own outline (tile, circle, square…) and `width` points wide, so it stays
/// concentric with the shape. Templates without an outline (As Is, folders, documents) get
/// a ring around an icon-tile square (corner radius 0.2237 × side, like `Radius.iconTile`).
public enum TemplateRingGeometry {
    /// `frame`: the thumbnail's square, in the same coordinates as the result.
    public static func ring(for shape: IconShape, in frame: CGRect, gap: CGFloat, width: CGFloat) -> CGPath {
        let side = min(frame.width, frame.height)
        let base: CGPath
        if shape.hasOutline, let clip = IconGeometry.clipPath(for: shape, pixels: side) {
            // The outlines are symmetric top to bottom, so y-up and y-down agree.
            var move = CGAffineTransform(translationX: frame.midX - side / 2, y: frame.midY - side / 2)
            base = clip.copy(using: &move) ?? clip
        } else {
            let tile = side * 0.2237
            base = CGPath(roundedRect: CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side),
                          cornerWidth: tile, cornerHeight: tile, transform: nil)
        }
        // The outline grown by `gap` and by `gap + width`; the ring is what lies between.
        // Round joins keep the offset of a sharp corner (Square) a true arc.
        let outer = base.union(base.copy(strokingWithWidth: 2 * (gap + width), lineCap: .round, lineJoin: .round, miterLimit: 1))
        let inner = base.union(base.copy(strokingWithWidth: 2 * gap, lineCap: .round, lineJoin: .round, miterLimit: 1))
        return outer.subtracting(inner)
    }
}
