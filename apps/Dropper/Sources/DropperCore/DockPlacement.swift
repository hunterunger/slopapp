import CoreGraphics
import Foundation

/// Where the Color Dock sits: an edge of the screen and how far along it (0 = start,
/// 1 = end; bottom/left first). Dragging it anywhere snaps to the nearest edge.
public struct DockPlacement: Equatable, Codable, Sendable {
    public enum Edge: String, Codable, Sendable, CaseIterable {
        case left, right, top, bottom
        public var isVertical: Bool { self == .left || self == .right }
    }

    public var edge: Edge
    public var position: Double

    public init(edge: Edge = .left, position: Double = 0.5) {
        self.edge = edge
        self.position = min(max(position, 0), 1)
    }

    /// The edge nearest a point (AppKit coordinates) and the matching position.
    public static func snapped(center: CGPoint, in visible: CGRect) -> DockPlacement {
        let distances: [(Edge, CGFloat)] = [
            (.left, abs(center.x - visible.minX)), (.right, abs(visible.maxX - center.x)),
            (.bottom, abs(center.y - visible.minY)), (.top, abs(visible.maxY - center.y)),
        ]
        let edge = distances.min { $0.1 < $1.1 }!.0
        let position = edge.isVertical
            ? Double((center.y - visible.minY) / max(visible.height, 1))
            : Double((center.x - visible.minX) / max(visible.width, 1))
        return DockPlacement(edge: edge, position: position)
    }

    /// The dock's frame: `length` along the edge, `thickness` across, kept on screen.
    public func frame(length: CGFloat, thickness: CGFloat, in visible: CGRect, inset: CGFloat = 4) -> CGRect {
        if edge.isVertical {
            let height = min(length, visible.height - 2 * inset)
            let y = min(max(visible.minY + CGFloat(position) * visible.height - height / 2, visible.minY + inset), visible.maxY - inset - height)
            let x = edge == .left ? visible.minX + inset : visible.maxX - inset - thickness
            return CGRect(x: x, y: y, width: thickness, height: height)
        }
        let width = min(length, visible.width - 2 * inset)
        let x = min(max(visible.minX + CGFloat(position) * visible.width - width / 2, visible.minX + inset), visible.maxX - inset - width)
        let y = edge == .bottom ? visible.minY + inset : visible.maxY - inset - thickness
        return CGRect(x: x, y: y, width: width, height: thickness)
    }
}
