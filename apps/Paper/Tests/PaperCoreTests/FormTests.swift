import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite("PDF syntax")
struct PDFSyntaxTests {
    @Test func parsesAndWritesObjects() throws {
        let source = "<< /Type /Annot /Rect [72 700.5 -3 4] /T (a \\(b\\) \\\\ c) /Hex <48656C6C6F> /Ref 12 0 R /On true /N null /Name#20x 1 /Kids [1 0 R 2 0 R] >>"
        var parser = PDFParser(Data(source.utf8))
        let object = try parser.parseObject()
        let dict = try #require(object.dictValue)
        #expect(dict["Type"] == .name("Annot"))
        #expect(dict["Rect"] == .array([.int(72), .real(700.5), .int(-3), .int(4)]))
        #expect(dict["T"]?.textValue == "a (b) \\ c")
        #expect(dict["Hex"]?.textValue == "Hello")
        #expect(dict["Ref"]?.refValue?.0 == 12)
        #expect(dict["On"] == .bool(true))
        #expect(dict["N"] == .null)
        #expect(dict["Name x"] == .int(1))
        #expect(dict["Kids"]?.arrayValue?.count == 2)
        // Round trip.
        var again = PDFParser(PDFWriter.serialize(object))
        #expect(try again.parseObject() == object)
    }

    @Test func textStringsRoundTripUnicode() {
        for text in ["plain", "Café déjà vu", "口座番号", "Zoë – “quotes”"] {
            #expect(PDFText.decode(PDFText.encode(text)) == text)
        }
    }

    @Test func numbersHaveNoExponent() {
        #expect(PDFWriter.number(0.000012) == "0")
        #expect(PDFWriter.number(12.5) == "12.5")
        #expect(PDFWriter.number(-3) == "-3")
        #expect(PDFWriter.number(1.23456) == "1.2346")
    }

    @Test func readsPDFKitFilesAndAppendsUpdates() throws {
        let data = try #require(PDFDocument(data: Fixtures.textDocument())?.dataRepresentation())
        let file = try PDFFile(data: data)
        #expect(file.pageRefs().count == 3)
        let root = try #require(file.rootRef)
        var catalog = try #require(try file.object(root.0).dictValue)
        #expect(catalog["Type"] == .name("Catalog"))
        var update = IncrementalUpdate(file)
        catalog["PaperTest"] = .text("hello")
        update.replace(root.0, with: .dict(catalog))
        let written = update.write()
        #expect(written.prefix(data.count) == data)
        let reread = try PDFFile(data: written)
        #expect(try reread.object(root.0).dictValue?["PaperTest"]?.textValue == "hello")
        // PDFKit and Poppler-compatible: it still opens with every page.
        #expect(PDFDocument(data: written)?.pageCount == 3)
    }

    @Test func readsCrossReferenceStreams() throws {
        // A file whose only cross-reference section is a stream (as Acrobat writes them).
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
        ]
        var out = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xrefOffset = out.utf8.count
        var rows = Data([0, 0, 0, 0, 0xFF, 0xFF])
        for offset in offsets + [xrefOffset] {
            rows.append(1); rows.append(contentsOf: [UInt8(offset >> 24 & 0xFF), UInt8(offset >> 16 & 0xFF), UInt8(offset >> 8 & 0xFF), UInt8(offset & 0xFF)]); rows.append(0)
        }
        var data = Data(out.utf8)
        data.append(Data("4 0 obj\n<< /Type /XRef /Size 5 /W [1 4 1] /Root 1 0 R /Length \(rows.count) >>\nstream\n".utf8))
        data.append(rows)
        data.append(Data("\nendstream\nendobj\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        let file = try PDFFile(data: data)
        #expect(file.usesXrefStream)
        #expect(file.pageRefs().count == 1)
        var update = IncrementalUpdate(file)
        _ = update.add(.dict(PDFDict([("Type", .name("Test"))])))
        let written = update.write()
        let reread = try PDFFile(data: written)
        #expect(try reread.object(5).dictValue?["Type"] == .name("Test"))
        #expect(PDFDocument(data: written)?.pageCount == 1)
    }

    @Test func inflatesWhatItDeflates() throws {
        let text = Data(String(repeating: "Paper form ", count: 200).utf8)
        let packed = try #require(StreamFilters.deflate(text))
        #expect(packed.count < text.count)
        #expect(try StreamFilters.inflate(packed) == text)
    }
}

@Suite("Form fields")
struct FormFieldTests {
    /// A one-page document with fields made the way the Forms tool makes them.
    static func makeForm(_ build: (PDFPage) -> Void) -> PDFDocument {
        let document = doc(Fixtures.textDocument(pages: 1))
        build(document.page(at: 0)!)
        return document
    }

    static func save(_ document: PDFDocument, _ scripts: FormScripts = FormScripts()) -> Data {
        AcroFormWriter.finalize(document.dataRepresentation()!, scripts: scripts, widgets: FormFields.states(in: document))
    }

    @Test func everyKindPersists() throws {
        let document = Self.makeForm { page in
            var y: CGFloat = 300
            for kind in FormFieldKind.allCases {
                page.addAnnotation(FormFieldFactory.make(kind, in: CGRect(origin: CGPoint(x: 72, y: y), size: kind.defaultSize), name: kind.baseName + " 1"))
                y -= 60
            }
        }
        let reopened = doc(Self.save(document))
        let kinds = FormFields.widgets(in: reopened).compactMap { FormFieldKind.of($0.annotation) }
        #expect(kinds == FormFieldKind.allCases)
        let names = FormFields.widgets(in: reopened).compactMap(\.annotation.fieldName)
        #expect(names == ["Text 1", "Checkbox 1", "Choice 1", "Dropdown 1", "Signature 1"])
    }

    @Test func fieldsAreListedInTheAcroForm() throws {
        let document = Self.makeForm { page in
            page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 300, width: 100, height: 22), name: "first"))
            page.addAnnotation(FormFieldFactory.make(.checkbox, in: CGRect(x: 72, y: 260, width: 14, height: 14), name: "agree"))
        }
        let plain = document.dataRepresentation()!
        let plainFile = try PDFFile(data: plain)
        let plainCatalog = try plainFile.object(plainFile.rootRef!.0).dictValue!
        // Research P24: PDFKit leaves the catalog without an AcroForm.
        #expect(plainCatalog["AcroForm"] == nil)

        let fixed = AcroFormWriter.finalize(plain, widgets: FormFields.states(in: document))
        let file = try PDFFile(data: fixed)
        let catalog = try file.object(file.rootRef!.0).dictValue!
        let form = try #require(file.dict(catalog["AcroForm"]))
        let fields = try #require(form["Fields"]?.arrayValue)
        #expect(fields.count == 2)
        let names = fields.compactMap { file.dict($0)?["T"]?.textValue }
        #expect(names == ["first", "agree"])
        #expect(form["DA"] != nil && form["DR"] != nil)
        // Idempotent: a second pass adds nothing.
        #expect(AcroFormWriter.finalize(fixed, widgets: FormFields.states(in: doc(fixed))) == fixed)
        // PDFKit still reads the fields.
        #expect(FormFields.widgets(in: doc(fixed)).count == 2)
    }

    @Test func radioButtonsBecomeOneGroup() throws {
        let document = Self.makeForm { page in
            for (index, option) in ["Basic", "Plus", "Pro"].enumerated() {
                page.addAnnotation(FormFieldFactory.make(.radio, in: CGRect(x: 72 + CGFloat(index) * 40, y: 300, width: 14, height: 14),
                                                         name: "plan", exportValue: option))
            }
        }
        let radios = document.page(at: 0)!.annotations.filter { $0.widgetControlType == .radioButtonControl }
        radios[1].buttonWidgetState = .onState
        let fixed = Self.save(document)
        let file = try PDFFile(data: fixed)
        let form = try #require(file.dict(try file.object(file.rootRef!.0).dictValue!["AcroForm"]))
        let fields = try #require(form["Fields"]?.arrayValue)
        #expect(fields.count == 1)
        let parent = try #require(file.dict(fields[0]))
        #expect(parent["T"]?.textValue == "plan")
        #expect(parent["Kids"]?.arrayValue?.count == 3)
        #expect(parent["V"] == .name("Plus"))
        #expect((parent["Ff"]?.intValue ?? 0) & AcroFormWriter.radioFlag != 0)
        // Reopened, PDFKit sees three radio widgets named "plan", the second one on.
        let reopened = doc(fixed)
        let widgets = FormFields.widgets(in: reopened).map(\.annotation)
        #expect(widgets.count == 3)
        #expect(widgets.allSatisfy { $0.fieldName == "plan" })
        #expect(FormFields.values(in: reopened)["plan"] == "Plus")

        // Choosing another button and saving again keeps one well-formed group.
        widgets[1].buttonWidgetState = .offState
        widgets[2].buttonWidgetState = .onState
        let second = Self.save(reopened)
        let file2 = try PDFFile(data: second)
        let form2 = try #require(file2.dict(try file2.object(file2.rootRef!.0).dictValue!["AcroForm"]))
        let fields2 = try #require(form2["Fields"]?.arrayValue)
        #expect(fields2.count == 1)
        let names = fields2.compactMap { file2.dict($0)?["T"]?.textValue }
        #expect(names == ["plan"])
        #expect(FormFields.values(in: doc(second))["plan"] == "Pro")
    }

    @Test func tabOrderFollowsTheAnnotationOrder() throws {
        let document = Self.makeForm { page in
            page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 300, y: 300, width: 100, height: 22), name: "right"))
            page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 300, width: 100, height: 22), name: "left"))
            page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 200, width: 100, height: 22), name: "below"))
        }
        let page = document.page(at: 0)!
        let widgets = page.annotations.filter { $0.type == "Widget" }
        let sorted = FormFields.positionOrder(widgets)
        #expect(sorted.compactMap(\.fieldName) == ["left", "right", "below"])
        FormFields.reorder(page, widgets: sorted)
        let reopened = doc(Self.save(document))
        #expect(FormFields.widgets(in: reopened).compactMap(\.annotation.fieldName) == ["left", "right", "below"])
        // The fixture's other annotations (none) and the fields' values survive the reorder.
        #expect(reopened.page(at: 0)!.annotations.count == 3)
    }

    @Test func uniqueNames() {
        #expect(FormNames.unique("Text", existing: []) == "Text 1")
        #expect(FormNames.unique("Text", existing: ["Text 1", "Text 2"]) == "Text 3")
        #expect(FormNames.clean(" a.b ") == "a b")
    }
}

@Suite("Calculated fields")
struct CalculationTests {
    @Test func formulas() throws {
        let values = ["qty": "3", "price": "$4.50", "unit price": "2", "empty": ""]
        func run(_ text: String) -> Double? { FormMath.compute(.formula(text), values: values) }
        #expect(run("qty * price") == 13.5)
        #expect(run("qty * price + 1") == 14.5)
        #expect(run("(qty + 1) * 2") == 8)
        #expect(run("-qty + 10") == 7)
        #expect(run("unit\\ price * 3") == 6)
        #expect(run("empty + 2") == 2)
        #expect(run("qty / 0") == nil)
        #expect(throws: FormulaError.unbalanced) { try FormulaParser.parse("(qty + 2") }
        #expect(throws: FormulaError.empty) { try FormulaParser.parse("  ") }
        #expect(try FormulaParser.parse("a * (b + c)").fieldNames == ["a", "b", "c"])
    }

    @Test func aggregates() {
        let values = ["a": "2", "b": "1,000", "c": "x"]
        #expect(FormMath.compute(.aggregate(.sum, fields: ["a", "b", "c"]), values: values) == 1002)
        #expect(FormMath.compute(.aggregate(.product, fields: ["a", "b"]), values: values) == 2000)
        #expect(FormMath.compute(.aggregate(.average, fields: ["a", "b"]), values: values) == 501)
        #expect(FormMath.compute(.aggregate(.minimum, fields: ["a", "b"]), values: values) == 2)
        #expect(FormMath.compute(.aggregate(.maximum, fields: ["a", "b"]), values: values) == 1000)
    }

    @Test func chainedCalculationsRunInOrder() {
        var scripts = FormScripts()
        // Defined out of order: total reads subtotal, which is itself calculated.
        scripts.set(FieldCalculation(.formula("subtotal * 1.1"), decimals: 2), for: "total")
        scripts.set(FieldCalculation(.formula("qty * price"), decimals: 2), for: "subtotal")
        #expect(scripts.runOrder() == ["subtotal", "total"])
        let changed = scripts.evaluate(["qty": "2", "price": "5", "subtotal": "", "total": ""])
        #expect(changed == ["subtotal": "10.00", "total": "11.00"])
        // Nothing changes when the values are current.
        #expect(scripts.evaluate(["qty": "2", "price": "5", "subtotal": "10.00", "total": "11.00"]).isEmpty)
    }

    @Test func javaScriptRoundTrips() {
        let rules: [Calculation] = [
            .aggregate(.sum, fields: ["a", "line \"2\""]),
            .aggregate(.average, fields: ["x"]),
            .formula("qty * price + shipping"),
        ]
        for rule in rules {
            let js = FormJavaScript.calculate(rule)!
            #expect(FormJavaScript.parseCalculation(js) == rule)
        }
        #expect(FormJavaScript.calculate(.formula("qty * price"))!.contains("AFMakeNumber(getField(\"qty\").value)"))
        #expect(FormJavaScript.parseCalculation("event.value = 42;") == .script("event.value = 42;"))
        #expect(FormJavaScript.parseDecimals(FormJavaScript.format(decimals: 3)) == 3)
    }

    @Test func renameUpdatesRules() {
        var scripts = FormScripts()
        scripts.set(FieldCalculation(.aggregate(.sum, fields: ["a", "b"])), for: "sum")
        scripts.set(FieldCalculation(.formula("a * 2")), for: "double")
        scripts.rename("a", to: "first item")
        #expect(scripts.calculations["sum"]?.rule == .aggregate(.sum, fields: ["first item", "b"]))
        #expect(scripts.calculations["double"]?.rule.inputs == ["first item"])
        scripts.rename("double", to: "twice")
        #expect(scripts.calculations["twice"] != nil && scripts.order.contains("twice"))
    }

    @Test func calculationsAreWrittenForOtherViewers() throws {
        let document = FormFieldTests.makeForm { page in
            for (index, name) in ["qty", "price", "total"].enumerated() {
                page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 300 - CGFloat(index) * 40, width: 100, height: 22), name: name))
            }
        }
        var scripts = FormScripts()
        scripts.set(FieldCalculation(.formula("qty * price"), decimals: 2), for: "total")
        let data = FormFieldTests.save(document, scripts)
        let file = try PDFFile(data: data)
        let form = try #require(file.dict(try file.object(file.rootRef!.0).dictValue!["AcroForm"]))
        #expect(form["CO"]?.arrayValue?.count == 1)
        let total = try #require(form["Fields"]?.arrayValue?.compactMap { file.dict($0) }.first { $0["T"]?.textValue == "total" })
        let actions = try #require(file.dict(total["AA"]))
        let calculate = try #require(file.dict(actions["C"]))
        #expect(calculate["S"] == .name("JavaScript"))
        #expect(AcroFormWriter.javaScript(of: calculate, file)?.contains("BVCALC qty * price EVCALC") == true)
        #expect(file.dict(actions["F"]) != nil)
        // Read back as the same rule.
        #expect(FormScripts.read(from: data) == scripts)
        // PDFKit keeps the script through another save (it rewrites untouched fields as is),
        // and the writer restores it either way.
        let resaved = FormFieldTests.save(doc(data), FormScripts.read(from: data))
        #expect(FormScripts.read(from: resaved) == scripts)
        // Removing the calculation removes the script and the order.
        let cleared = FormFieldTests.save(doc(resaved), FormScripts())
        #expect(FormScripts.read(from: cleared).isEmpty)
    }
}

@Suite("Form field appearances")
struct FieldAppearanceTests {
    @Test func savedTextFieldsHaveABorder() throws {
        let document = FormFieldTests.makeForm { page in
            page.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 300, width: 120, height: 22), name: "name"))
        }
        document.page(at: 0)!.annotations.first { $0.type == "Widget" }!.widgetStringValue = "Ada"
        let data = FormFieldTests.save(document)
        // Reopened, PDFKit draws the saved appearance: the border is there.
        let page = doc(data).page(at: 0)!
        let image = try #require(PageRenderer.render(page, region: CGRect(x: 72, y: 300, width: 120, height: 22), scale: 2))
        let pixels = try #require(PageRenderer.rgba(image))
        // The left edge column is grey (border), the middle of an empty part is white.
        let left = Int(pixels[(image.width * (image.height / 2)) * 4])
        let middle = Int(pixels[(image.width * (image.height / 2) + image.width - 20) * 4])
        #expect(left < 200)
        #expect(middle > 240)
        #expect(page.annotations.first?.widgetStringValue == "Ada")
        // Idempotent.
        #expect(AcroFormWriter.finalize(data, widgets: FormFields.states(in: doc(data))) == data)
    }
}

@Suite("Form field accessibility")
struct FieldAccessibilityTests {
    @Test func newFieldsAreNamedForScreenReaders() {
        let field = FormFieldFactory.make(.checkbox, in: CGRect(x: 0, y: 0, width: 14, height: 14), name: "Agree to terms")
        #expect(FormFieldFactory.tooltip(of: field) == "Agree to terms")
        let reopened = doc(FormFieldTests.save(FormFieldTests.makeForm { $0.addAnnotation(field) }))
        #expect(FormFields.widgets(in: reopened).first.map { FormFieldFactory.tooltip(of: $0.annotation) } == "Agree to terms")
    }
}
