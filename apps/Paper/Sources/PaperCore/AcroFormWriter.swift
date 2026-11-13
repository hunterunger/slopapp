import AppKit
import PDFKit

/// Fixes up the form structure in a file PDFKit wrote, as an incremental update:
///
/// - PDFKit writes new fields as widgets but never adds them to the catalog's `/AcroForm`
///   (it doesn't even create one), so Acrobat and most viewers don't treat them as fields
///   (research P24). Every widget is listed in `/Fields`.
/// - Radio buttons that share a name are written as separate fields; they're grouped under
///   one parent field (with `/Kids`), which is how PDF expresses a radio group.
/// - Calculated fields get their calculate action (`/AA /C`) and number format, and the
///   AcroForm gets the calculation order (`/CO`). PDFKit can't write JavaScript actions.
///
/// It's idempotent: run on a file it already fixed, it changes nothing.
public enum AcroFormWriter {
    static let radioFlag = 1 << 15
    static let noToggleToOff = 1 << 14

    public static func finalize(_ data: Data, scripts: FormScripts = FormScripts(), widgets states: [WidgetState] = []) -> Data {
        guard let file = try? PDFFile(data: data), !file.isEncrypted, let root = file.rootRef,
              let catalog = (try? file.object(root.0))?.dictValue else { return data }
        var update = IncrementalUpdate(file)

        // 1. Widgets in page order, repaired from what Paper knows about each field.
        struct Widget { var number: Int; var dict: PDFDict; var kind: FormFieldKind? }
        var widgets: [Widget] = []
        var available = Dictionary(grouping: states, by: \.pageIndex)
        for (pageIndex, page) in file.pageRefs().enumerated() {
            guard let pageDict = file.dict(.ref(page.0, page.1)),
                  let annots = pageDict["Annots"].flatMap({ try? file.resolve($0).arrayValue }) else { continue }
            for annot in annots {
                guard let ref = annot.refValue, var dict = file.dict(annot), dict["Subtype"]?.nameValue == "Widget" else { continue }
                var kind: FormFieldKind?
                if let rect = rect(dict["Rect"]), var candidates = available[pageIndex],
                   let match = candidates.firstIndex(where: { $0.rect.isClose(to: rect) }) {
                    let state = candidates.remove(at: match)
                    available[pageIndex] = candidates
                    kind = state.kind
                    let repaired = repair(dict, state: state, file: file, update: &update)
                    if repaired != dict {
                        dict = repaired
                        update.replace(ref.0, with: .dict(dict))
                    }
                }
                widgets.append(Widget(number: ref.0, dict: dict, kind: kind))
            }
        }
        let existingForm = file.dict(catalog["AcroForm"])
        guard !widgets.isEmpty || existingForm != nil else { return data }

        // 2. Top-level field for each widget; group same-named parentless widgets.
        var topLevel: [Int] = []
        var fieldByName: [String: Int] = [:]
        func addTop(_ number: Int) { if !topLevel.contains(number) { topLevel.append(number) } }
        func parentDict(_ number: Int) -> PDFDict? { update.current(number)?.dictValue }

        func topAncestor(_ number: Int, _ dict: PDFDict) -> (Int, PDFDict) {
            var current = (number, dict)
            var hops = 0
            while let parent = current.1["Parent"]?.refValue, let dict = parentDict(parent.0), hops < 16 {
                current = (parent.0, dict)
                hops += 1
            }
            return current
        }

        var parentless: [String: [Widget]] = [:]
        var parentlessOrder: [String] = []
        for widget in widgets {
            if let parent = widget.dict["Parent"]?.refValue {
                // A kid PDFKit rewrote may carry the field's own entries again; move them to
                // the parent so the name isn't doubled ("plan.plan").
                var kid = widget.dict
                if var field = parentDict(parent.0) {
                    let before = field
                    if let name = kid["T"]?.textValue, name == field["T"]?.textValue { kid["T"] = nil }
                    for key in ["FT", "Ff", "DV", "TU"] where kid[key] != nil && field[key] != nil { kid[key] = nil }
                    if kid["V"] != nil { kid["V"] = nil }
                    // A group another writer made (macOS 26's PDFKit does, once a button is on)
                    // may lack the radio flags, so viewers would treat it as checkboxes.
                    if widget.kind == .radio, (field["Ff"]?.intValue ?? 0) & radioFlag == 0 {
                        field["FT"] = .name("Btn")
                        field["Ff"] = .int((field["Ff"]?.intValue ?? 0) | radioFlag | noToggleToOff)
                    }
                    if field["FT"]?.nameValue == "Btn" {
                        // The group's value is the state of whichever button is on.
                        let kids = (field["Kids"].flatMap { try? file.resolve($0).arrayValue } ?? []).compactMap(\.refValue)
                        let on = kids.lazy.compactMap { parentDict($0.0)?["AS"]?.nameValue }.first { $0 != "Off" }
                        let current = kid["AS"]?.nameValue
                        field["V"] = .name((current != nil && current != "Off" ? current : on) ?? "Off")
                    }
                    if kid != widget.dict { update.replace(widget.number, with: .dict(kid)) }
                    if field != before { update.replace(parent.0, with: .dict(field)) }
                }
                let (number, dict) = topAncestor(widget.number, kid)
                addTop(number)
                if let name = dict["T"]?.textValue { fieldByName[name] = number }
                continue
            }
            guard let name = widget.dict["T"]?.textValue else { addTop(widget.number); continue }
            if parentless[name] == nil { parentlessOrder.append(name) }
            parentless[name, default: []].append(widget)
        }
        var groupParents: [String: Int] = [:]
        for name in parentlessOrder {
            guard let group = parentless[name] else { continue }
            if group.count == 1 {
                fieldByName[name] = group[0].number
                continue
            }
            // Several widgets with one name: one field with kids.
            let first = group[0].dict
            var parent = PDFDict()
            parent["FT"] = first["FT"] ?? .name("Btn")
            parent["T"] = first["T"]
            if let tooltip = group.lazy.compactMap({ $0.dict["TU"] }).first { parent["TU"] = tooltip }
            // macOS 26's PDFKit doesn't always put /FT and /Ff on each widget: go by what Paper
            // knows the widgets are, then by any widget that says.
            var flags = group.lazy.compactMap { $0.dict["Ff"]?.intValue }.first ?? 0
            let isButton = group.contains { $0.kind == .radio || $0.kind == .checkbox || $0.dict["FT"]?.nameValue == "Btn" }
            if isButton {
                parent["FT"] = .name("Btn")
                flags |= radioFlag | noToggleToOff
            }
            parent["Ff"] = .int(flags)
            if isButton {
                let on = group.lazy.compactMap { $0.dict["AS"]?.nameValue }.first { $0 != "Off" }
                parent["V"] = .name(on ?? "Off")
            } else if let value = group.lazy.compactMap({ $0.dict["V"] }).first {
                parent["V"] = value
            }
            if let da = first["DA"] { parent["DA"] = da }
            parent["Kids"] = .array(group.map { .ref($0.number, 0) })
            guard case .ref(let parentNumber, _) = update.add(.dict(parent)) else { continue }
            for widget in group {
                var kid = widget.dict
                for key in ["T", "FT", "Ff", "V", "DV", "TU"] { kid[key] = nil }
                kid["Parent"] = .ref(parentNumber, 0)
                update.replace(widget.number, with: .dict(kid))
            }
            fieldByName[name] = parentNumber
            groupParents[name] = parentNumber
        }
        for widget in widgets where widget.dict["Parent"] == nil {
            if let name = widget.dict["T"]?.textValue, let parent = groupParents[name] { addTop(parent) } else { addTop(widget.number) }
        }

        // 3. Calculations.
        var calculationOrder: [PDFObject] = []
        for (name, number) in fieldByName {
            guard var dict = update.current(number)?.dictValue else { continue }
            var actions = file.dict(dict["AA"]) ?? PDFDict()
            let before = actions
            if let calculation = scripts.calculations[name], let js = FormJavaScript.calculate(calculation.rule) {
                actions["C"] = javaScriptAction(js)
                if let decimals = calculation.decimals {
                    actions["F"] = javaScriptAction(FormJavaScript.format(decimals: decimals))
                    actions["K"] = javaScriptAction(FormJavaScript.keystroke(decimals: decimals))
                } else {
                    for key in ["F", "K"] where isNumberFormat(file.dict(actions[key]), file) { actions[key] = nil }
                }
            } else if actions["C"] != nil {
                actions["C"] = nil
                // Formatting Paper added with the calculation goes with it.
                for key in ["F", "K"] where isNumberFormat(file.dict(actions[key]), file) { actions[key] = nil }
            }
            if actions != before {
                dict["AA"] = actions.entries.isEmpty ? nil : .dict(actions)
                update.replace(number, with: .dict(dict))
            }
        }
        for name in scripts.runOrder() {
            if let number = fieldByName[name] { calculationOrder.append(.ref(number, 0)) }
        }

        // 4. The AcroForm itself.
        var form = existingForm ?? PDFDict()
        let oldFields = (form["Fields"].flatMap { try? file.resolve($0).arrayValue } ?? []).compactMap(\.refValue).map(\.0)
        let oldOrder = (form["CO"].flatMap { try? file.resolve($0).arrayValue } ?? []).compactMap(\.refValue).map(\.0)
        let newOrder = calculationOrder.compactMap(\.refValue).map(\.0)
        var formChanged = existingForm == nil || oldFields != topLevel || oldOrder != newOrder
        form["Fields"] = .array(topLevel.map { .ref($0, 0) })
        form["CO"] = calculationOrder.isEmpty ? nil : .array(calculationOrder)
        if form["DA"] == nil { form["DA"] = .string(Data("/Helv 0 Tf 0 g".utf8)); formChanged = true }
        var resources = file.dict(form["DR"]) ?? PDFDict()
        var fonts = file.dict(resources["Font"]) ?? PDFDict()
        for (key, base) in [("Helv", "Helvetica"), ("ZaDb", "ZapfDingbats")] where fonts[key] == nil {
            var font = PDFDict([("Type", .name("Font")), ("Subtype", .name("Type1")), ("BaseFont", .name(base))])
            if key == "Helv" { font["Encoding"] = .name("WinAnsiEncoding") }
            fonts[key] = .dict(font)
            formChanged = true
        }
        resources["Font"] = .dict(fonts)
        form["DR"] = .dict(resources)
        guard formChanged || !update.isEmpty else { return data }
        if case .ref(let number, _) = catalog["AcroForm"] {
            update.replace(number, with: .dict(form))
        } else {
            var newCatalog = catalog
            newCatalog["AcroForm"] = update.add(.dict(form))
            update.replace(root.0, with: .dict(newCatalog))
        }
        return update.write()
    }

    /// Puts back what PDFKit drops when it rewrites a widget of a loaded document
    /// (research P26): `/DA` as a string naming a font in `/DR`, the border and background
    /// in `/MK`, and for checkboxes and radio buttons both appearance states, `/AS` and `/V`.
    static func repair(_ widget: PDFDict, state: WidgetState, file: PDFFile, update: inout IncrementalUpdate) -> PDFDict {
        var dict = widget
        let isButton = state.kind == .checkbox || state.kind == .radio
        let wantedDA = isButton ? "/ZaDb 0 Tf 0 g" : "/Helv \(PDFWriter.number(Double(state.fontSize ?? 0))) Tf 0 g"
        if let da = dict["DA"]?.stringValue.map(PDFText.decode) {
            if !(da.hasPrefix("/Helv ") || da.hasPrefix("/ZaDb ") || da.contains("/Helv ")) && !isKnownFont(da) {
                dict["DA"] = .string(Data(wantedDA.utf8))
            }
        } else if state.kind != .signature {
            dict["DA"] = .string(Data(wantedDA.utf8))
        }
        // /MK and /AP may be written inline (macOS 27) or as references (macOS 26).
        var mk = file.dict(dict["MK"]) ?? PDFDict()
        if mk["BC"] == nil, let border = state.borderColor { mk["BC"] = .array(border.map { .real(Double($0)) }) }
        if mk["BG"] == nil, let background = state.backgroundColor { mk["BG"] = .array(background.map { .real(Double($0)) }) }
        if isButton, mk["CA"] == nil { mk["CA"] = .string(Data((state.kind == .radio ? "l" : "4").utf8)) }
        if !mk.entries.isEmpty || dict["MK"] != nil { dict["MK"] = .dict(mk) }
        if let bs = dict["BS"]?.dictValue, bs.entries.isEmpty, state.borderColor != nil {
            dict["BS"] = .dict(PDFDict([("W", .int(1)), ("S", .name("S"))]))
        }
        if isButton, let rect = rect(dict["Rect"]) {
            let on = sanitizedState(state.onState)
            let states = file.dict(file.dict(dict["AP"])?["N"])
            if states?[on] == nil || states?["Off"] == nil {
                let size = CGSize(width: rect.width, height: rect.height)
                let onRef = update.add(appearanceDict(size), stream: ButtonAppearance.stream(state.kind == .radio, on: true, size: size, state: state))
                let offRef = update.add(appearanceDict(size), stream: ButtonAppearance.stream(state.kind == .radio, on: false, size: size, state: state))
                dict["AP"] = .dict(PDFDict([("N", .dict(PDFDict([(on, onRef), ("Off", offRef)])))]))
            }
            dict["AS"] = .name(state.isOn ? on : "Off")
            if dict["Parent"] == nil, state.kind == .checkbox { dict["V"] = .name(state.isOn ? on : "Off") }
            if state.kind == .radio, dict["Parent"] == nil { dict["V"] = .name(state.isOn ? on : "Off") }
        }
        // PDFKit's text field appearance has the background and the text but no border
        // (research P29): wrap it in one that adds the border, keeping PDFKit's drawing.
        if state.kind == .text, let border = state.borderColor, let rect = rect(dict["Rect"]),
           let ap = file.dict(dict["AP"]), case .ref(let normal, let generation)? = ap["N"],
           update.current(normal)?.dictValue?["PaperBorder"] == nil {
            let w = Double(rect.width), h = Double(rect.height)
            let color = border.map { PDFWriter.number(Double($0)) }.joined(separator: " ")
            let content = "/PaperField Do q \(color) RG 1 w 0.5 0.5 \(PDFWriter.number(w - 1)) \(PDFWriter.number(h - 1)) re S Q"
            let wrapper = PDFDict([
                ("Type", .name("XObject")), ("Subtype", .name("Form")),
                ("BBox", .array([.int(0), .int(0), .real(w), .real(h)])),
                ("Resources", .dict(PDFDict([("XObject", .dict(PDFDict([("PaperField", .ref(normal, generation))])))]))),
                ("PaperBorder", .bool(true)),
            ])
            var appearance = ap
            appearance["N"] = update.add(.dict(wrapper), stream: Data(content.utf8))
            dict["AP"] = .dict(appearance)
        }
        if state.kind == .dropdown, dict["Opt"] == nil, let options = state.options, !options.isEmpty {
            dict["Opt"] = .array(options.map(PDFObject.text))
        }
        return dict
    }

    /// A `/DA` that names a font the AcroForm's `/DR` might not have, from another app.
    static func isKnownFont(_ da: String) -> Bool {
        !da.contains("AppleSystemUIFont") && !da.contains("/Helvetica ") && da.hasPrefix("/")
    }

    static func sanitizedState(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Off" ? "Yes" : trimmed
    }

    static func appearanceDict(_ size: CGSize) -> PDFObject {
        .dict(PDFDict([("Type", .name("XObject")), ("Subtype", .name("Form")),
                       ("BBox", .array([.int(0), .int(0), .real(Double(size.width)), .real(Double(size.height))])),
                       ("Resources", .dict(PDFDict()))]))
    }

    static func rect(_ object: PDFObject?) -> CGRect? {
        guard let numbers = object?.arrayValue?.compactMap(\.numberValue), numbers.count == 4 else { return nil }
        return CGRect(x: min(numbers[0], numbers[2]), y: min(numbers[1], numbers[3]),
                      width: abs(numbers[2] - numbers[0]), height: abs(numbers[3] - numbers[1]))
    }

    static func javaScriptAction(_ js: String) -> PDFObject {
        var action = PDFDict()
        action["S"] = .name("JavaScript")
        action["JS"] = .string(Data(js.utf8))
        return .dict(action)
    }

    static func isNumberFormat(_ action: PDFDict?, _ file: PDFFile) -> Bool {
        guard let action, let js = javaScript(of: action, file) else { return false }
        return js.contains("AFNumber_Format") || js.contains("AFNumber_Keystroke")
    }

    /// The script of a JavaScript action (a string, or a stream).
    static func javaScript(of action: PDFDict, _ file: PDFFile) -> String? {
        guard action["S"]?.nameValue == "JavaScript", let js = action["JS"] else { return nil }
        if let text = js.stringValue { return PDFText.decode(text) }
        if let ref = js.refValue, let (object, raw) = try? file.objectWithStream(ref.0), let dict = object.dictValue, let raw,
           let decoded = try? StreamFilters.decode(raw, dict: dict) {
            return String(decoding: decoded, as: UTF8.self)
        }
        return nil
    }
}

extension FormScripts {
    /// The calculated fields of a file: each field's calculate script and number format,
    /// and the order from `/CO`.
    public static func read(from data: Data) -> FormScripts {
        guard let file = try? PDFFile(data: data), !file.isEncrypted, let root = file.rootRef,
              let catalog = (try? file.object(root.0))?.dictValue, let form = file.dict(catalog["AcroForm"]) else { return FormScripts() }
        var scripts = FormScripts()
        var visited = Set<Int>()
        var nameByNumber: [Int: String] = [:]
        func visit(_ object: PDFObject, prefix: String) {
            guard let ref = object.refValue, !visited.contains(ref.0), let dict = file.dict(object) else { return }
            visited.insert(ref.0)
            let partial = dict["T"]?.textValue
            let name = [prefix, partial ?? ""].filter { !$0.isEmpty }.joined(separator: ".")
            if partial != nil { nameByNumber[ref.0] = name }
            if let actions = file.dict(dict["AA"]), let calculate = file.dict(actions["C"]),
               let js = AcroFormWriter.javaScript(of: calculate, file), !name.isEmpty {
                let decimals = file.dict(actions["F"]).flatMap { AcroFormWriter.javaScript(of: $0, file) }.flatMap(FormJavaScript.parseDecimals)
                scripts.calculations[name] = FieldCalculation(FormJavaScript.parseCalculation(js), decimals: decimals)
            }
            for kid in file.dict(object)?["Kids"].flatMap({ try? file.resolve($0).arrayValue }) ?? [] {
                visit(kid, prefix: name)
            }
        }
        for field in form["Fields"].flatMap({ try? file.resolve($0).arrayValue }) ?? [] { visit(field, prefix: "") }
        let order = (form["CO"].flatMap { try? file.resolve($0).arrayValue } ?? []).compactMap { $0.refValue.flatMap { nameByNumber[$0.0] } }
        scripts.order = order.filter { scripts.calculations[$0] != nil }
        for name in scripts.calculations.keys.sorted() where !scripts.order.contains(name) { scripts.order.append(name) }
        return scripts
    }
}

/// What Paper knows about a widget in memory, which PDFKit's writer can lose.
public struct WidgetState: Equatable, Sendable {
    public var pageIndex: Int
    public var rect: CGRect
    public var kind: FormFieldKind?
    public var onState: String?
    public var isOn: Bool
    public var options: [String]?
    public var fontSize: CGFloat?
    public var borderColor: [CGFloat]?
    public var backgroundColor: [CGFloat]?

    public init(pageIndex: Int, rect: CGRect, kind: FormFieldKind?, onState: String? = nil, isOn: Bool = false,
                options: [String]? = nil, fontSize: CGFloat? = nil, borderColor: [CGFloat]? = nil, backgroundColor: [CGFloat]? = nil) {
        self.pageIndex = pageIndex
        self.rect = rect
        self.kind = kind
        self.onState = onState
        self.isOn = isOn
        self.options = options
        self.fontSize = fontSize
        self.borderColor = borderColor
        self.backgroundColor = backgroundColor
    }
}

extension FormFields {
    /// The state of every widget, taken just before a save (see `AcroFormWriter.repair`).
    public static func states(in document: PDFDocument) -> [WidgetState] {
        widgets(in: document).map { item in
            let field = item.annotation
            let kind = FormFieldKind.of(field)
            func rgb(_ color: NSColor?) -> [CGFloat]? {
                guard let color = color?.usingColorSpace(.sRGB), color.alphaComponent > 0.01 else { return nil }
                return [color.redComponent, color.greenComponent, color.blueComponent]
            }
            return WidgetState(
                pageIndex: item.pageIndex, rect: field.bounds, kind: kind,
                onState: kind == .checkbox || kind == .radio ? field.buttonWidgetStateString : nil,
                isOn: field.buttonWidgetState == .onState,
                options: kind == .dropdown ? field.choices : nil,
                fontSize: field.font?.pointSize,
                borderColor: rgb(field.color), backgroundColor: rgb(field.backgroundColor)
            )
        }
    }
}

/// Appearance streams for checkboxes and radio buttons, drawn as paths (no fonts needed).
enum ButtonAppearance {
    static func stream(_ radio: Bool, on: Bool, size: CGSize, state: WidgetState) -> Data {
        let w = Double(size.width), h = Double(size.height)
        func n(_ value: Double) -> String { PDFWriter.number(value) }
        func color(_ components: [CGFloat]?, fallback: String, stroke: Bool) -> String {
            guard let components, components.count == 3 else { return fallback }
            return components.map { n(Double($0)) }.joined(separator: " ") + (stroke ? " RG" : " rg")
        }
        var ops: [String] = []
        if radio {
            let r = min(w, h) / 2, cx = w / 2, cy = h / 2
            func circle(_ radius: Double) -> String {
                let k = 0.5523 * radius
                return "\(n(cx + radius)) \(n(cy)) m "
                    + "\(n(cx + radius)) \(n(cy + k)) \(n(cx + k)) \(n(cy + radius)) \(n(cx)) \(n(cy + radius)) c "
                    + "\(n(cx - k)) \(n(cy + radius)) \(n(cx - radius)) \(n(cy + k)) \(n(cx - radius)) \(n(cy)) c "
                    + "\(n(cx - radius)) \(n(cy - k)) \(n(cx - k)) \(n(cy - radius)) \(n(cx)) \(n(cy - radius)) c "
                    + "\(n(cx + k)) \(n(cy - radius)) \(n(cx + radius)) \(n(cy - k)) \(n(cx + radius)) \(n(cy)) c h"
            }
            ops.append("q \(color(state.backgroundColor, fallback: "1 g", stroke: false)) \(circle(r - 0.5)) f Q")
            ops.append("q \(color(state.borderColor, fallback: "0.5 G", stroke: true)) 1 w \(circle(r - 0.5)) S Q")
            if on { ops.append("q 0 g \(circle(r * 0.45)) f Q") }
        } else {
            ops.append("q \(color(state.backgroundColor, fallback: "1 g", stroke: false)) 0 0 \(n(w)) \(n(h)) re f Q")
            ops.append("q \(color(state.borderColor, fallback: "0.5 G", stroke: true)) 1 w 0.5 0.5 \(n(w - 1)) \(n(h - 1)) re S Q")
            if on {
                let line = max(1, min(w, h) / 9)
                ops.append("q 0 G \(n(line)) w 1 J 1 j \(n(w * 0.22)) \(n(h * 0.52)) m \(n(w * 0.42)) \(n(h * 0.28)) l \(n(w * 0.8)) \(n(h * 0.74)) l S Q")
            }
        }
        return Data(ops.joined(separator: "\n").utf8)
    }
}
