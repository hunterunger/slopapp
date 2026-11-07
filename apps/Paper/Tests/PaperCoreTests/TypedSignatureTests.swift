import CoreGraphics
import PaperCore
import Testing

@Suite("Typed signatures")
struct TypedSignatureTests {
    @Test func aTypedNameBecomesAnInkSignature() throws {
        let font = TypedSignature.availableFonts.first?.name ?? "Helvetica"
        let signature = try #require(TypedSignature.signature("Sample Name", fontName: font))
        #expect(signature.isImage)
        #expect(!signature.strokes.isEmpty)
        // A name is much wider than it is tall.
        #expect(signature.aspect > 2)
    }

    @Test func emptyTextAndMissingFontsMakeNothing() {
        #expect(TypedSignature.signature("   ", fontName: "Helvetica") == nil)
        #expect(TypedSignature.image("Name", fontName: "No Such Font") == nil)
    }

    @Test func initialsKeepTheirKind() throws {
        let signature = try #require(TypedSignature.signature("SN", fontName: "Helvetica", kind: .initials))
        #expect(signature.kind == .initials)
    }

    @Test func availableFontsAreInstalledAndCapped() {
        #expect(TypedSignature.availableFonts.count <= 3)
    }
}
