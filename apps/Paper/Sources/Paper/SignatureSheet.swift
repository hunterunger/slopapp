import AppKit
import PaperCore
import SlopKit
import SwiftUI

@MainActor
enum SignatureSheet {
    static func present(on window: NSWindow, completion: @escaping (Signature?) -> Void) {
        Sheet.present(on: window) { dismiss in
            SignaturePad { signature in
                if let signature { SignatureLibraryStore.shared.add(signature) }
                dismiss()
                completion(signature)
            }
        }
    }
}

/// Draw a signature with the trackpad or mouse. Saved locally; never uploaded.
struct SignaturePad: View {
    let finish: (Signature?) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var kind: Signature.Kind = .signature
    static let size = CGSize(width: 480, height: 180)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("New Signature").font(.headline)
            Picker("Kind", selection: $kind) {
                Text("Signature").tag(Signature.Kind.signature)
                Text("Initials").tag(Signature.Kind.initials)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.background)
                RoundedRectangle(cornerRadius: 8).strokeBorder(.separator)
                Path { path in
                    path.move(to: CGPoint(x: 24, y: Self.size.height - 44))
                    path.addLine(to: CGPoint(x: Self.size.width - 24, y: Self.size.height - 44))
                }
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if strokes.isEmpty && current.isEmpty {
                    Text(kind == .signature ? "Sign here with the trackpad or mouse" : "Draw your initials here")
                        .foregroundStyle(.tertiary)
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
            HStack {
                Button("Clear") { strokes = []; current = [] }
                    .disabled(strokes.isEmpty)
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save Signature") {
                    // SwiftUI's y grows downward; PDF space grows upward.
                    let flipped = strokes.map { $0.map { CGPoint(x: $0.x, y: Self.size.height - $0.y) } }
                    finish(Signature.from(strokes: flipped, kind: kind))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Signature.from(strokes: strokes) == nil)
            }
            Text("Signatures are kept on this Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
    }
}
