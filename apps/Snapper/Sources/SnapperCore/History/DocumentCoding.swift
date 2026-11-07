import CoreGraphics
import Foundation

// The annotation document as JSON, so a capture in history reopens with its edits as objects.
// Decoding is forgiving: a mark of a kind this version doesn't know is dropped, missing fields
// get defaults.

extension RGBA: Codable {
    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decodeIfPresent(Double.self, forKey: .red) ?? 0,
                  try c.decodeIfPresent(Double.self, forKey: .green) ?? 0,
                  try c.decodeIfPresent(Double.self, forKey: .blue) ?? 0,
                  try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(red, forKey: .red)
        try c.encode(green, forKey: .green)
        try c.encode(blue, forKey: .blue)
        try c.encode(alpha, forKey: .alpha)
    }
}

extension AnnotationKind: Codable {}

extension Annotation: Codable {
    private enum CodingKeys: String, CodingKey { case id, kind, start, end, points, color, width, text, number }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try c.decode(AnnotationKind.self, forKey: .kind),
                  start: try c.decodeIfPresent(CGPoint.self, forKey: .start) ?? .zero,
                  end: try c.decodeIfPresent(CGPoint.self, forKey: .end),
                  points: try c.decodeIfPresent([CGPoint].self, forKey: .points) ?? [],
                  color: try c.decodeIfPresent(RGBA.self, forKey: .color) ?? PaletteColor.default.color,
                  width: try c.decodeIfPresent(CGFloat.self, forKey: .width) ?? StrokeWidth.medium.points,
                  text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                  number: try c.decodeIfPresent(Int.self, forKey: .number) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        if !points.isEmpty { try c.encode(points, forKey: .points) }
        try c.encode(color, forKey: .color)
        try c.encode(width, forKey: .width)
        if !text.isEmpty { try c.encode(text, forKey: .text) }
        if number != 0 { try c.encode(number, forKey: .number) }
    }
}

extension AnnotationDocument: Codable {
    private enum CodingKeys: String, CodingKey { case version, imageSize, annotations, crop, background }

    /// A mark that fails to decode (an unknown kind) is skipped.
    private struct LenientAnnotation: Decodable {
        let value: Annotation?
        init(from decoder: Decoder) throws { value = try? Annotation(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(imageSize: try c.decodeIfPresent(CGSize.self, forKey: .imageSize) ?? .zero,
                  annotations: (try c.decodeIfPresent([LenientAnnotation].self, forKey: .annotations) ?? []).compactMap(\.value),
                  crop: try c.decodeIfPresent(CGRect.self, forKey: .crop),
                  background: try? c.decodeIfPresent(CaptureBackground.self, forKey: .background))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(imageSize, forKey: .imageSize)
        try c.encode(annotations, forKey: .annotations)
        try c.encodeIfPresent(crop, forKey: .crop)
        try c.encodeIfPresent(background, forKey: .background)
    }
}
