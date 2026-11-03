import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite struct DocumentFactsTests {
    @Test func forms() {
        let data = Fixtures.formDocument()
        let facts = DocumentFacts.inspect(doc(data), raw: data)
        #expect(facts.formFieldCount == 4)
        #expect(facts.hasTextLayer)
        #expect(!facts.isPDFA)
    }

    @Test func scans() {
        #expect(!DocumentFacts.inspect(doc(Fixtures.scanDocument()), raw: nil).hasTextLayer)
        #expect(DocumentFacts.inspect(doc(Fixtures.scanDocument(withHiddenText: true)), raw: nil).hasTextLayer)
    }

    @Test func foreignRedactionsAndMarks() {
        let data = Fixtures.foreignRedactDocument()
        let facts = DocumentFacts.inspect(doc(data), raw: data)
        #expect(facts.redactAnnotationCount == 1)
        let marked = doc(Fixtures.textDocument(pages: 1))
        mark("\(Fixtures.secret)-1", in: marked)
        #expect(DocumentFacts.inspect(marked, raw: nil).pendingMarkCount == 1)
    }

    @Test func restrictions() {
        let facts = DocumentFacts.inspect(doc(Fixtures.restrictedDocument()), raw: nil)
        #expect(facts.isEncrypted)
        #expect(!facts.allowsPrinting)
        #expect(!facts.allowsCopying)
        #expect(facts.isRestricted)
        #expect(facts.isReadOnly)
        let open = DocumentFacts.inspect(doc(Fixtures.textDocument()), raw: nil)
        #expect(!open.isReadOnly)
    }

    @Test func rawScanLooksAtHeadAndTail() {
        var data = Data("pdfaid:part".utf8)
        data.append(Data(count: 100))
        #expect(RawScan.contains("pdfaid:part", in: data, window: 16))
        var middle = Data(count: 100)
        middle.append(Data("/XFA".utf8))
        middle.append(Data(count: 100))
        #expect(!RawScan.contains("/XFA", in: middle, window: 16))
        #expect(RawScan.contains("/XFA", in: middle, window: 1000))
    }
}

@Suite struct SearchTests {
    @Test func findsHitsWithContext() {
        let hits = PDFSearch.hits(in: doc(Fixtures.textDocument()), query: "public sentence", options: .init())
        #expect(hits.count == 3)
        #expect(hits.map(\.pageIndex) == [0, 1, 2])
        #expect(hits[0].context.contains("This public sentence should"))
    }

    @Test func lineRectsForAHit() {
        let document = doc(Fixtures.textDocument(pages: 1))
        let hit = PDFSearch.hits(in: document, query: "nobody", options: .init()).first!
        let rects = PDFSearch.lineRects(for: hit.range, on: document.page(at: 0)!)
        #expect(rects.count == 1)
        #expect(rects[0].width > 20)
    }

    @Test func cjkSearch() {
        let hits = PDFSearch.hits(in: doc(Fixtures.cjkDocument()), query: "東京", options: .init(wholeWord: true))
        #expect(hits.count == 1)
    }

    @Test func textLayerDetection() {
        #expect(PDFSearch.hasTextLayer(doc(Fixtures.textDocument())))
        #expect(!PDFSearch.hasTextLayer(doc(Fixtures.scanDocument())))
    }
}

@Suite struct LastPageMemoryTests {
    @Test func remembersAndCaps() {
        let memory = LastPageMemory(store: InMemoryStore(), capacity: 3)
        for index in 0..<5 { memory.remember(page: index, for: URL(fileURLWithPath: "/tmp/\(index).pdf")) }
        #expect(memory.page(for: URL(fileURLWithPath: "/tmp/4.pdf")) == 4)
        #expect(memory.page(for: URL(fileURLWithPath: "/tmp/0.pdf")) == nil)
        memory.remember(page: 9, for: URL(fileURLWithPath: "/tmp/2.pdf"))
        #expect(memory.page(for: URL(fileURLWithPath: "/tmp/2.pdf")) == 9)
        #expect(memory.entries.count == 3)
        #expect(memory.entries.first?.path == "/tmp/2.pdf")
    }
}

@Suite struct NotesExportTests {
    @Test func markdownInPageOrder() {
        let document = doc(Fixtures.textDocument(pages: 2))
        let factory = AnnotationFactory(author: nil)
        let rect = bounds(of: "public sentence", in: document, page: 1)
        let highlight = factory.markup(.highlight, color: .yellow, lineRects: [rect])!
        highlight.contents = "Why public?"
        document.page(at: 1)!.addAnnotation(highlight)
        document.page(at: 0)!.addAnnotation(factory.note("First page note", at: CGPoint(x: 300, y: 300)))
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let items = NotesExport.items(in: document)
        #expect(items.count == 2)
        let markdown = NotesExport.markdown(title: "Test", items: items)
        #expect(markdown == """
        # Test

        ## Page 1

        Note: First page note

        ## Page 2

        > public sentence

        Why public?

        """)
    }
}
