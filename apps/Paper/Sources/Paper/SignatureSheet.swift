import AppKit
import PaperCore
import SlopKit
import SwiftUI

@MainActor
enum SignatureSheet {
    static func present(on window: NSWindow, source: SignatureSource = .draw, completion: @escaping (Signature?) -> Void) {
        Sheet.present(on: window) { dismiss in
            SignaturePad(source: source) { signature in
                if let signature { SignatureLibraryStore.shared.add(signature) }
                dismiss()
                completion(signature)
            }
        }
    }
}

enum SignatureSource: String, CaseIterable, Identifiable {
    case draw, type, image
    var id: String { rawValue }
}

/// Draw a signature with the trackpad or mouse, or import a photo or scan of one. Saved
/// locally; never uploaded.
struct SignaturePad: View {
    let finish: (Signature?) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var kind: Signature.Kind = .signature
    @State private var source: SignatureSource
    @State private var imported: ImportedSignature
    @State private var typedName = ""
    @State private var typedFont = TypedSignature.availableFonts.first?.name ?? "Helvetica"
    static let size = CGSize(width: 480, height: 200)
    /// Both tabs take the same space, so switching between them doesn't resize the sheet.
    static let areaHeight: CGFloat = 200

    init(source: SignatureSource = .draw, imported: ImportedSignature? = nil, typedName: String = "",
         finish: @escaping (Signature?) -> Void) {
        self.finish = finish
        _source = State(initialValue: source)
        _typedName = State(initialValue: typedName)
        _imported = State(initialValue: imported ?? ImportedSignature())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("New Signature").font(.headline)
                Spacer()
                Picker("Kind", selection: $kind) {
                    Text("Signature").tag(Signature.Kind.signature)
                    Text("Initials").tag(Signature.Kind.initials)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Picker("Source", selection: $source) {
                Text("Draw").tag(SignatureSource.draw)
                Text("Type").tag(SignatureSource.type)
                Text("Image").tag(SignatureSource.image)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch source {
            case .draw:
                drawingArea
            case .type:
                TypedSignatureArea(name: $typedName, font: $typedFont, signature: typedSignature)
                    .frame(width: Self.size.width, height: Self.areaHeight)
            case .image:
                SignatureImageImport(imported: imported)
                    .frame(width: Self.size.width, height: Self.areaHeight)
            }
            HStack {
                switch source {
                case .draw:
                    Button("Clear") { strokes = []; current = [] }
                        .disabled(strokes.isEmpty)
                case .type:
                    EmptyView()
                case .image:
                    Button("Choose Image…", action: imported.choose)
                }
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save Signature", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            Text("Signatures are kept on this Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
    }

    private var typedSignature: Signature? {
        TypedSignature.signature(typedName, fontName: typedFont, kind: kind)
    }

    private var canSave: Bool {
        switch source {
        case .draw: Signature.from(strokes: strokes) != nil
        case .type: typedSignature != nil
        case .image: imported.signature != nil
        }
    }

    private func save() {
        switch source {
        case .type:
            finish(typedSignature)
        case .draw:
            // SwiftUI's y grows downward; PDF space grows upward.
            let flipped = strokes.map { $0.map { CGPoint(x: $0.x, y: Self.size.height - $0.y) } }
            finish(Signature.from(strokes: flipped, kind: kind))
        case .image:
            guard var signature = imported.signature else { return }
            signature.kind = kind
            finish(signature)
        }
    }

    private var drawingArea: some View {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Radius.m).fill(.background)
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
                Path { path in
                    path.move(to: CGPoint(x: 24, y: Self.size.height - 44))
                    path.addLine(to: CGPoint(x: Self.size.width - 24, y: Self.size.height - 44))
                }
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if strokes.isEmpty && current.isEmpty {
                    Text(kind == .signature ? "Sign here with the trackpad or mouse" : "Draw your initials here")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { context, _ in
                    for stroke in strokes + [current] where stroke.count > 1 {
                        var path = Path()
                        path.move(to: stroke[0])
                        for point in stroke.dropFirst() { path.addLine(to: point) }
                        context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in current.append(value.location) }
                    .onEnded { _ in
                        if current.count > 1 { strokes.append(current) }
                        current = []
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Signature drawing area")
            .accessibilityValue(strokes.isEmpty ? "Empty" : "\(strokes.count) strokes")
    }
}

/// The picked image and the signature traced from it.
@Observable
@MainActor
final class ImportedSignature {
    var image: CGImage?
    var name = ""
    /// 0...1; pixels darker than this are ink.
    var threshold: Double = 0.5
    var automatic: Double = 0.5
    private(set) var signature: Signature?

    func load(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary)
        else {
            self.image = nil
            signature = nil
            name = "Couldn't read “\(url.lastPathComponent)”"
            return
        }
        load(image, name: url.lastPathComponent)
    }

    func load(_ image: CGImage, name: String) {
        self.image = image
        self.name = name
        if let gray = SignatureImport.luminance(of: image) {
            automatic = Double(SignatureImport.suggestedThreshold(gray.values))
            threshold = automatic
        }
        retrace()
    }

    func retrace() {
        signature = image.flatMap { SignatureImport.signature(from: $0, threshold: Float(threshold)) }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo or scan of your signature on light paper."
        panel.begin { response in
            MainActor.assumeIsolated {
                if response == .OK, let url = panel.url { self.load(url) }
            }
        }
    }
}

/// Drop or choose a picture of a signature; the paper is removed and the ink traced.
struct SignatureImageImport: View {
    @Bindable var imported: ImportedSignature

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let signature = imported.signature {
                ZStack {
                    // The same surface and ink as the Draw tab, in light and dark.
                    RoundedRectangle(cornerRadius: Radius.m).fill(.background)
                        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
                    let height = min(120, (SignaturePad.size.width - 2 * Spacing.xxl) / max(signature.aspect, 0.5))
                    Image(nsImage: SignatureImage.image(signature, height: height))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Traced signature preview")
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Text("Thinner").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $imported.threshold, in: 0.15...0.9) { Text("Ink thickness") }
                        .labelsHidden()
                        .accessibilityLabel("Ink thickness")
                        .onChange(of: imported.threshold) { imported.retrace() }
                    Text("Bolder").font(.caption).foregroundStyle(.secondary)
                    Button("Auto") {
                        imported.threshold = imported.automatic
                        imported.retrace()
                    }
                    .controlSize(.small)
                }
            } else {
                DropZone(imported.image == nil && !imported.name.isEmpty ? imported.name : "Drop a photo of your signature",
                         systemImage: "signature", types: [.image], allowsMultiple: false) { urls in
                    if let url = urls.first { imported.load(url) }
                }
            }
        }
    }
}

/// Type a name and pick a handwriting style; the preview is the traced result, so what you see
/// is what goes on the page.
struct TypedSignatureArea: View {
    @Binding var name: String
    @Binding var font: String
    let signature: Signature?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.m).fill(.background)
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
                if let signature {
                    // Inset from the box like the Draw tab's baseline, never edge to edge.
                    let height = min(80, (SignaturePad.size.width - 2 * Spacing.xxl) / max(signature.aspect, 0.5))
                    Image(nsImage: SignatureImage.image(signature, height: height))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Typed signature preview")
                } else {
                    Text("Type your name below").foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: Spacing.s) {
                TextField("Name", text: $name, prompt: Text("Your name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
                Picker("Style", selection: $font) {
                    ForEach(TypedSignature.availableFonts, id: \.name) { Text($0.title).tag($0.name) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(TypedSignature.availableFonts.count < 2)
            }
        }
        .onAppear { focused = true }
    }
}
