import AVFoundation
import ConvertCore
import ImageIO
import SlopKit
import SwiftUI

/// Shapes the crop box can keep.
enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, wide, tall, standard, portrait
    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Any Shape"
        case .original: "Original Shape"
        case .square: "Square"
        case .wide: "16:9"
        case .tall: "9:16"
        case .standard: "4:3"
        case .portrait: "3:4"
        }
    }

    /// Width ÷ height in pixels (nil: any).
    func ratio(original: Double) -> Double? {
        switch self {
        case .free: nil
        case .original: original
        case .square: 1
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        case .standard: 4.0 / 3
        case .portrait: 3.0 / 4
        }
    }
}

/// Crop one video or photo: the picture as it will come out (turned, if it's turned), a box
/// to drag, a shape to keep, and for videos a frame to look at and black-bar detection.
/// Return is Done, Esc is Cancel.
struct CropSheet: View {
    @Bindable var model: AppModel
    let entry: CardEntry

    @State private var picture: CGImage?
    @State private var rect: CropRect
    @State private var aspect = CropAspect.free
    @State private var time: Double = 0
    @State private var playable: URL?
    @State private var detecting = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    private let turn: PictureTransform
    private let info: MediaInfo?

    init(model: AppModel, entry: CardEntry) {
        self.model = model
        self.entry = entry
        let options = model.options(for: entry.input)
        turn = options.transform
        info = model.facts(for: entry.input).info
        _rect = State(initialValue: (options.crop ?? .whole).turned(by: options.transform))
        _time = State(initialValue: min(1, (model.facts(for: entry.input).info?.duration ?? 0) * 0.1))
    }

    private var isVideo: Bool { info?.kind == .video }

    /// The picture's size as it will come out (after the turn), in pixels.
    private var pixelSize: CGSize {
        let (w, h) = (info?.displayWidth ?? 0, info?.displayHeight ?? 0)
        return turn.swapsSides ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Crop “\(entry.input.lastPathComponent)”")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
            CropCanvas(image: picture, rect: $rect, ratio: normalizedRatio, pixelSize: pixelSize)
                .frame(minWidth: 640, minHeight: 380)
                .padding(.horizontal, Spacing.xl)
            VStack(spacing: Spacing.m) {
                if isVideo, let duration = info?.duration, duration > 0.2 {
                    HStack(spacing: Spacing.s) {
                        Text("Frame").foregroundStyle(.secondary)
                        Slider(value: $time, in: 0...duration) { Text("Frame to show") }
                            .labelsHidden()
                            .accessibilityValue(Durations.precise(time))
                        Text(Durations.precise(time)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: Spacing.m) {
                    Picker("Shape", selection: $aspect) {
                        ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    if isVideo {
                        Button(detecting ? "Looking…" : "Remove Black Bars") { detectBars() }
                            .disabled(detecting || playable == nil)
                            .help("Find black bars at the edges of the picture and crop them off")
                    }
                    Spacer()
                    Text(sizeText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cropped size")
                        .accessibilityValue(sizeText)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Keep Whole Picture") {
                        aspect = .free
                        rect = .whole
                    }
                    .help("Remove the crop")
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xl)
        }
        .frame(minWidth: 680)
        .task { await load() }
        .onChange(of: time) { _, _ in Task { await loadFrame() } }
        .onChange(of: aspect) { _, _ in
            if let ratio = normalizedRatio { rect = CropCanvas.fit(rect, ratio: ratio) }
        }
    }

    /// The shape as fractions (width fraction ÷ height fraction).
    private var normalizedRatio: Double? {
        guard pixelSize.width > 0, pixelSize.height > 0,
              let ratio = aspect.ratio(original: pixelSize.width / pixelSize.height) else { return nil }
        return ratio * pixelSize.height / pixelSize.width
    }

    private var sizeText: String {
        let pixels = rect.pixels(width: Int(pixelSize.width), height: Int(pixelSize.height), even: isVideo)
        return "\(Int(pixels.width)) × \(Int(pixels.height))"
    }

    // MARK: Pictures

    private func load() async {
        if isVideo {
            playable = await PlayablePreviews.shared.playable(entry.input)
            await loadFrame()
        } else {
            let url = entry.input
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
            }.value
            picture = image.flatMap { PictureDrawing.turned($0, by: turn) }
        }
    }

    private func frame(at seconds: Double) async -> CGImage? {
        guard let playable else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: playable))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func loadFrame() async {
        guard let image = await frame(at: time) else { return }
        picture = PictureDrawing.turned(image, by: turn)
    }

    private func detectBars() {
        detecting = true
        message = nil
        Task {
            let duration = info?.duration ?? 0
            var frames: [CGImage] = []
            for fraction in [0.2, 0.4, 0.6, 0.8] {
                if let image = await frame(at: duration * fraction) { frames.append(image) }
            }
            detecting = false
            if let found = BlackBars.detect(frames) {
                aspect = .free
                rect = found.turned(by: turn)
            } else {
                message = "No black bars found."
            }
        }
    }

    private func save() {
        let crop = rect.unturned(by: turn)
        model.updateOptions(for: [entry]) { $0.crop = crop.isWhole ? nil : crop }
        dismiss()
    }
}

/// The picture with a crop box over it: drag inside to move it, drag a handle to resize it.
/// Outside the box is dimmed. With a shape (`ratio`, in fractions), only the corners resize
/// and keep it. VoiceOver moves and resizes it with actions. Named so it could move to SlopKit.
struct CropCanvas: View {
    let image: CGImage?
    @Binding var rect: CropRect
    /// Width ÷ height of the box in fractions of the picture, when the shape is fixed.
    let ratio: Double?
    let pixelSize: CGSize

    @State private var dragStart: CropRect?
    private let handle: CGFloat = 12
    private static let minimum = 0.03

    enum Edge { case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight, move }

    var body: some View {
        GeometryReader { proxy in
            let frame = fitted(in: proxy.size)
            ZStack(alignment: .topLeading) {
                CardInk.ink.opacity(0.06)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                let box = CGRect(x: frame.minX + rect.x * frame.width, y: frame.minY + rect.y * frame.height,
                                 width: rect.width * frame.width, height: rect.height * frame.height)
                // Dim everything outside the box.
                Path { path in
                    path.addRect(frame)
                    path.addRect(box)
                }
                .fill(CardInk.ink.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                // Thirds, then the box's edge.
                Path { path in
                    for i in 1...2 {
                        let x = box.minX + box.width * Double(i) / 3, y = box.minY + box.height * Double(i) / 3
                        path.move(to: CGPoint(x: x, y: box.minY)); path.addLine(to: CGPoint(x: x, y: box.maxY))
                        path.move(to: CGPoint(x: box.minX, y: y)); path.addLine(to: CGPoint(x: box.maxX, y: y))
                    }
                }
                .stroke(CardInk.paper.opacity(0.35), lineWidth: 0.5)
                .allowsHitTesting(false)
                Rectangle()
                    .strokeBorder(CardInk.paper, lineWidth: 1.5)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .contentShape(Rectangle())
                    .gesture(drag(.move, frame: frame))
                ForEach(handles(box), id: \.0) { _, point, edge in
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CardInk.paper)
                        .shadow(color: CardInk.ink.opacity(0.5), radius: 1)
                        .frame(width: handle, height: handle)
                        .offset(x: point.x - handle / 2, y: point.y - handle / 2)
                        .gesture(drag(edge, frame: frame))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Crop box")
        .accessibilityValue(accessibilityValue)
        .accessibilityAction(named: "Move Left") { nudge(dx: -0.02) }
        .accessibilityAction(named: "Move Right") { nudge(dx: 0.02) }
        .accessibilityAction(named: "Move Up") { nudge(dy: -0.02) }
        .accessibilityAction(named: "Move Down") { nudge(dy: 0.02) }
        .accessibilityAction(named: "Make Smaller") { scale(0.95) }
        .accessibilityAction(named: "Make Bigger") { scale(1.05) }
    }

    private var accessibilityValue: String {
        let pixels = rect.pixels(width: Int(pixelSize.width), height: Int(pixelSize.height))
        return "\(Int(pixels.width)) by \(Int(pixels.height)) pixels, \(Int(pixels.minX)) from the left, \(Int(pixels.minY)) from the top"
    }

    /// The picture's place in the view: as big as fits, centred.
    private func fitted(in size: CGSize) -> CGRect {
        let aspect = pixelSize.width > 0 && pixelSize.height > 0 ? pixelSize.width / pixelSize.height
            : image.map { Double($0.width) / Double($0.height) } ?? 16.0 / 9
        // Inset by half a handle, so handles on the picture's edge are whole.
        let inset = CGSize(width: max(1, size.width - handle), height: max(1, size.height - handle))
        var w = inset.width, h = w / aspect
        if h > inset.height { h = inset.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func handles(_ box: CGRect) -> [(Int, CGPoint, Edge)] {
        var list: [(Int, CGPoint, Edge)] = [
            (0, CGPoint(x: box.minX, y: box.minY), .topLeft), (1, CGPoint(x: box.maxX, y: box.minY), .topRight),
            (2, CGPoint(x: box.minX, y: box.maxY), .bottomLeft), (3, CGPoint(x: box.maxX, y: box.maxY), .bottomRight),
        ]
        if ratio == nil {
            list += [(4, CGPoint(x: box.midX, y: box.minY), .top), (5, CGPoint(x: box.midX, y: box.maxY), .bottom),
                     (6, CGPoint(x: box.minX, y: box.midY), .left), (7, CGPoint(x: box.maxX, y: box.midY), .right)]
        }
        return list
    }

    private func drag(_ edge: Edge, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? rect
                if dragStart == nil { dragStart = rect }
                let dx = value.translation.width / max(1, frame.width)
                let dy = value.translation.height / max(1, frame.height)
                rect = Self.adjust(start, edge: edge, dx: dx, dy: dy, ratio: ratio)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// The box after dragging `edge` by (dx, dy) fractions of the picture.
    static func adjust(_ r: CropRect, edge: Edge, dx: Double, dy: Double, ratio: Double?) -> CropRect {
        var left = r.x, top = r.y, right = r.x + r.width, bottom = r.y + r.height
        switch edge {
        case .move:
            let x = min(max(0, left + dx), 1 - r.width), y = min(max(0, top + dy), 1 - r.height)
            return CropRect(x: x, y: y, width: r.width, height: r.height)
        case .top: top = min(max(0, top + dy), bottom - minimum)
        case .bottom: bottom = max(min(1, bottom + dy), top + minimum)
        case .left: left = min(max(0, left + dx), right - minimum)
        case .right: right = max(min(1, right + dx), left + minimum)
        case .topLeft: left = min(max(0, left + dx), right - minimum); top = min(max(0, top + dy), bottom - minimum)
        case .topRight: right = max(min(1, right + dx), left + minimum); top = min(max(0, top + dy), bottom - minimum)
        case .bottomLeft: left = min(max(0, left + dx), right - minimum); bottom = max(min(1, bottom + dy), top + minimum)
        case .bottomRight: right = max(min(1, right + dx), left + minimum); bottom = max(min(1, bottom + dy), top + minimum)
        }
        if let ratio {
            // Keep the shape: the height follows the width, from the corner opposite the one dragged.
            var width = right - left, height = width / ratio
            let anchorsBottom = edge == .topLeft || edge == .topRight
            let room = anchorsBottom ? bottom : 1 - top
            if height > room { height = room; width = height * ratio }
            if edge == .topLeft || edge == .bottomLeft { left = right - width } else { right = left + width }
            if anchorsBottom { top = bottom - height } else { bottom = top + height }
        }
        return CropRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The largest box of this shape inside the current one, centred on it.
    static func fit(_ r: CropRect, ratio: Double) -> CropRect {
        var width = r.width, height = width / ratio
        if height > r.height { height = r.height; width = height * ratio }
        if width > 1 { width = 1; height = width / ratio }
        if height > 1 { height = 1; width = height * ratio }
        let x = min(max(0, r.x + (r.width - width) / 2), 1 - width)
        let y = min(max(0, r.y + (r.height - height) / 2), 1 - height)
        return CropRect(x: x, y: y, width: width, height: height)
    }

    private func nudge(dx: Double = 0, dy: Double = 0) {
        rect = Self.adjust(rect, edge: .move, dx: dx, dy: dy, ratio: nil)
    }

    private func scale(_ factor: Double) {
        let width = min(1, max(Self.minimum, rect.width * factor)), height = min(1, max(Self.minimum, rect.height * factor))
        let x = min(max(0, rect.x + (rect.width - width) / 2), 1 - width)
        let y = min(max(0, rect.y + (rect.height - height) / 2), 1 - height)
        rect = CropRect(x: x, y: y, width: width, height: height)
    }
}
