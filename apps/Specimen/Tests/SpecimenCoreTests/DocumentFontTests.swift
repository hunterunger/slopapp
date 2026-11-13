import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import SpecimenCore

@Suite struct DocumentFontTests {
    @Test func cssFamiliesSkipGenericsAndKnowWebFonts() {
        let css = """
        /* font-family: Commented Out; */
        @font-face { font-family: "Brand Sans"; src: url(brand.woff2), local("Brand Sans Regular"); }
        body { font-family: "Brand Sans", 'Inter', system-ui, -apple-system, sans-serif; }
        h1 { font: italic bold 2rem/1.2 "Playfair Display", Georgia, serif; }
        code { font-family: var(--mono), "JetBrains Mono" !important }
        .caption { font: caption; }
        p { font-size: 12px; -webkit-font-family: Ignored; }
        """
        let references = DocumentFontReader.references(css: css)
        #expect(references.map(\.name) == ["Brand Sans", "Inter", "JetBrains Mono", "Playfair Display", "Georgia", "Brand Sans Regular"])
        #expect(references[0].isProvidedByDocument)
        #expect(!references[1].isProvidedByDocument)
        #expect(references.last?.kind == .either)
        #expect(references.dropLast().allSatisfy { $0.kind == .family })
    }

    @Test func familyListQuotesAndSpaces() {
        #expect(DocumentFontReader.familyList(#""Font, With Comma", Times   New  Roman , monospace"#) == ["Font, With Comma", "Times New Roman"])
        #expect(DocumentFontReader.shorthandFamilies("bold 12px Helvetica, Arial") == "Helvetica, Arial")
        #expect(DocumentFontReader.shorthandFamilies("small-caps 1em/1.5 Futura") == "Futura")
    }

    @Test func htmlStylesAttributesFontTagsAndLinkedSheets() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="site.css?v=2"><link rel="stylesheet" href="https://example.com/remote.css">
        <style>h1 { font-family: Didot; }</style></head>
        <body><p style="font-family: &quot;Gill Sans&quot;, sans-serif">x</p><font face="Optima">y</font></body></html>
        """
        var asked: [String] = []
        let references = DocumentFontReader.references(html: html) { href in
            asked.append(href)
            return href == "site.css" ? "body { font-family: Avenir Next; }" : nil
        }
        #expect(asked == ["site.css"])
        #expect(Set(references.map(\.name)) == ["Didot", "Gill Sans", "Optima", "Avenir Next"])
    }

    @Test func svgAttributesAndStyles() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg"><style>.t { font-family: 'Futura'; }</style>
        <text font-family="Helvetica Neue, Arial">a</text><text style="font: 700 18px Menlo">b</text></svg>
        """
        #expect(Set(DocumentFontReader.references(svg: svg).map(\.name)) == ["Futura", "Helvetica Neue", "Arial", "Menlo"])
    }

    @Test func postScriptComments() {
        let eps = """
        %!PS-Adobe-3.0 EPSF-3.0
        %%DocumentNeededResources: font Helvetica-Bold
        %%+ font Minion-Regular
        %%+ procset Adobe_AGM_Image 1.0 0
        %%DocumentSuppliedResources: font MyLogo-Regular
        %%DocumentFonts: (atend)
        %%EndComments
        /Helvetica-Bold findfont
        %%Trailer
        %%DocumentFonts: Helvetica-Bold Futura-Book
        """
        let references = DocumentFontReader.references(postScript: eps)
        #expect(references.map(\.name) == ["Helvetica-Bold", "Minion-Regular", "Futura-Book", "MyLogo-Regular"])
        #expect(references.last?.isEmbedded == true)
        #expect(references.allSatisfy { $0.kind == .postScript })
    }

    @Test func rtfFontTable() {
        let rtf = #"{\rtf1\ansi{\fonttbl\f0\fswiss\fcharset0 Helvetica;\f1\fnil\fcharset0 HelveticaNeue-Bold;{\f2\froman{\*\panose 02020603050405020304}Times New Roman;}}\f0 Hi}"#
        #expect(DocumentFontReader.references(rtf: rtf).map(\.name) == ["Helvetica", "HelveticaNeue-Bold", "Times New Roman"])
    }

    @Test func subsetPrefixes() {
        #expect(DocumentFontReader.stripSubsetPrefix("ABCDEF+Inter-Bold") == "Inter-Bold")
        #expect(DocumentFontReader.stripSubsetPrefix("Inter-Bold") == "Inter-Bold")
        #expect(DocumentFontReader.stripSubsetPrefix("abcdef+Inter") == "abcdef+Inter")
    }

    @Test func pdfFontsFromARealPDF() throws {
        // A one-page PDF set in the OFL fixture (loaded from its file, not registered).
        let font = try #require(FontLoader.makeFont(postScriptName: "Silkscreen-Regular", path: Fixtures.regular.path, isEnabled: false, size: 24))
        let url = temporaryDirectory().appendingPathComponent("poster.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello", attributes: [.init(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, context)
        let helvetica = CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil)
        context.textPosition = CGPoint(x: 20, y: 50)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "World", attributes: [.init(kCTFontAttributeName as String): helvetica])), context)
        context.endPDFPage()
        context.closePDF()
        let references = try DocumentFontReader.references(in: url)
        #expect(references.map(\.name).contains("Silkscreen-Regular"))
        #expect(references.map(\.name).contains("Helvetica-Bold"))
        #expect(references.allSatisfy { $0.kind == .postScript && $0.isEmbedded })
        #expect(throws: DocumentFontReader.Failure.unsupported) { try DocumentFontReader.references(in: URL(fileURLWithPath: "/tmp/x.docx")) }
    }

    @Test func matchingByNameFamilyAndLooseForms() {
        let interRegular = face("Inter-Regular", family: "Inter", path: "/L/Inter-Regular.otf", enabled: false)
        let interBold = face("Inter-Bold", family: "Inter", style: "Bold", path: "/L/Inter-Bold.otf", enabled: false, weight: 0.4)
        let arialBold = face("Arial-BoldMT", family: "Arial", style: "Bold", path: "/Library/Fonts/Arial Bold.ttf")
        let source = face("SourceSansPro-Regular", family: "Source Sans Pro", path: "/L/SSP.otf")
        let library = [interRegular, interBold, arialBold, source]
        let references = [
            FontReference(name: "Inter-Bold", kind: .postScript),
            FontReference(name: "Arial,Bold", kind: .postScript),
            FontReference(name: "inter", kind: .family),
            FontReference(name: "SourceSansPro", kind: .family),
            FontReference(name: "Missing Grotesk", kind: .family),
            FontReference(name: "HelveticaNeue-Light", kind: .either),
        ]
        let matches = DocumentFontMatcher.match(references, in: library, documentPath: nil)
        #expect(matches[0].faces == [interBold] && matches[0].status == .inactive)
        #expect(matches[1].faces == [arialBold] && matches[1].status == .active)
        #expect(matches[2].faces == [interRegular, interBold])
        #expect(matches[3].status == .active)
        #expect(matches[4].status == .missing)
        #expect(matches[5].status == .missing)
    }

    @Test func picksTheCopyNearestTheDocumentUnlessOneIsOn() {
        let near = face("Brand-Regular", family: "Brand", path: "/Work/Acme/Fonts/Brand.otf", enabled: false)
        let far = face("Brand-Regular", family: "Brand", path: "/Archive/Old/Brand.otf", enabled: false)
        let reference = [FontReference(name: "Brand-Regular", kind: .postScript)]
        #expect(DocumentFontMatcher.match(reference, in: [far, near], documentPath: "/Work/Acme/Poster.pdf")[0].faces == [near])
        var farOn = far
        farOn.isEnabled = true
        let match = DocumentFontMatcher.match(reference, in: [farOn, near], documentPath: "/Work/Acme/Poster.pdf")[0]
        #expect(match.faces == [farOn] && match.status == .active)
    }

    @Test func documentsListMovesReopenedToTop() {
        var (list, first) = DocumentsStore.adding("/a.pdf", to: [])
        (list, _) = DocumentsStore.adding("/b.svg", to: list)
        let (reopened, id) = DocumentsStore.adding("/a.pdf", to: list)
        #expect(id == first)
        #expect(reopened.map(\.path) == ["/a.pdf", "/b.svg"])
        #expect(reopened[0].kind == .pdf)
    }
}
