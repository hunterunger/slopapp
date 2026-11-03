import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite struct FlattenerTests {
    func filledForm() -> PDFDocument {
        let document = doc(Fixtures.formDocument())
        let page = document.page(at: 0)!
        for annotation in page.annotations {
            switch annotation.fieldName {
            case "fullName": annotation.widgetStringValue = "Jane Example"
            case "agree": annotation.buttonWidgetState = .onState
            case "color": annotation.widgetStringValue = "Green"
            default: break
            }
        }
        return document
    }

    @Test func formValuesSurviveSaveAndReopen() {
        let saved = doc(filledForm().dataRepresentation()!)
        let widgets = saved.page(at: 0)!.annotations
        #expect(widgets.first { $0.fieldName == "fullName" }?.widgetStringValue == "Jane Example")
        #expect(widgets.first { $0.fieldName == "agree" }?.buttonWidgetState == .onState)
        #expect(widgets.first { $0.fieldName == "color" }?.widgetStringValue == "Green")
    }

    @Test func bakesEverythingIn() throws {
        let document = filledForm()
        let page = document.page(at: 0)!
        let factory = AnnotationFactory(author: "Tester")
        page.addAnnotation(factory.textBox("Typed on the page", topLeft: CGPoint(x: 300, y: 300), fontSize: 14, color: .black))
        page.addAnnotation(factory.ink([[CGPoint(x: 300, y: 200), CGPoint(x: 340, y: 230), CGPoint(x: 380, y: 200)]], color: .blue, lineWidth: 2)!)
        page.addAnnotation(RedactionMarks.makeMark(bounds: CGRect(x: 72, y: 700, width: 50, height: 20)))
        let flat = doc(try Flattener.flatten(document.dataRepresentation()!))
        #expect(annotationCount(flat) == 0)
        let text = allText(flat)
        #expect(text.contains("Jane Example"))
        #expect(text.contains("Typed on the page"))
    }

    @Test func checkedBoxStaysChecked() throws {
        let flat = doc(try Flattener.flatten(filledForm().dataRepresentation()!))
        let box = CGRect(x: 72, y: 600, width: 18, height: 18).insetBy(dx: 3, dy: 3)
        let image = PageRenderer.render(flat.page(at: 0)!, region: box, scale: 4)!
        #expect(PageRenderer.meanLuminance(image) < 0.9)
    }

    @Test func pendingMarksAreLeftOut() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let area = bounds(of: "\(Fixtures.secret)-1", in: document)
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: area))
        let flat = doc(try Flattener.flatten(document.dataRepresentation()!))
        // Not redacted (that's Apply Redactions' job), and no red box baked in either.
        #expect(allText(flat).contains("\(Fixtures.secret)-1"))
        let image = PageRenderer.render(flat.page(at: 0)!, region: area, scale: 2)!
        #expect(PageRenderer.meanLuminance(image) > 0.7)
    }

    @Test func unreadableInput() {
        #expect(throws: FlattenError.unreadable) { try Flattener.flatten(Data("x".utf8)) }
    }
}

@Suite struct SaveSafetyTests {
    @Test func savingKeepsAnOCRLayer() {
        let original = Fixtures.scanDocument(withHiddenText: true)
        let document = doc(original)
        let factory = AnnotationFactory(author: nil)
        let rect = bounds(of: "55821", in: document)
        document.page(at: 0)!.addAnnotation(factory.markup(.highlight, color: InkColor.yellow.nsColor, lineRects: [rect])!)
        let saved = document.dataRepresentation()!
        #expect(allText(doc(saved)).contains(Fixtures.hidden))
        #expect(Double(saved.count) <= Double(original.count) * 1.2 + 4096)
    }

    @Test func unlockedEncryptedDocumentCanBeRead() {
        let document = doc(Fixtures.encryptedDocument(password: "paper"))
        #expect(document.isLocked)
        #expect(!document.unlock(withPassword: "wrong"))
        #expect(document.unlock(withPassword: "paper"))
        #expect(allText(document).contains("Paper test page 1"))
    }

    @Test func damagedAndNonPDFFilesDontOpen() {
        #expect(PDFDocument(data: Data("This is plain text, not a PDF.\n".utf8)) == nil)
        let damaged = PDFDocument(data: Fixtures.textDocument().prefix(900))
        #expect(damaged == nil || damaged!.pageCount == 0)
    }
}
