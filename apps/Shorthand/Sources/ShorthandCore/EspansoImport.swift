import AppKit

/// espanso match files (YAML): `matches:` with `trigger`/`triggers`, `replace`, `label`,
/// `propagate_case`, `vars` (date, clipboard, echo, choice/list, form, match), `form` with
/// `[[field]]` and `form_fields`, `$|$` (cursor), `markdown`, `html` and `image_path`.
/// Shell and script variables and regex triggers can't be carried over and are reported.
public enum EspansoImport {
    @MainActor
    public static func entries(fromYAML text: String, fileURL: URL) throws -> (entries: [ImportEntry], notes: [String]) {
        let root = try MiniYAML.parse(text)
        let group = fileURL.deletingPathExtension().lastPathComponent
        var fileNotes: [String] = []
        if root["imports"] != nil { fileNotes.append("This file imports other files; import those separately.") }
        let globals = root["global_vars"]?.list ?? []
        var entries: [ImportEntry] = []
        for match in root["matches"]?.list ?? [] {
            entries.append(contentsOf: self.entries(from: match, globals: globals, group: group, fileURL: fileURL))
        }
        return (entries, fileNotes)
    }

    @MainActor
    static func entries(from match: YAMLValue, globals: [YAMLValue], group: String, fileURL: URL) -> [ImportEntry] {
        let label = match["label"]?.string ?? ""
        let caseMode: CaseMode = match["propagate_case"]?.bool == true ? .adapt : .exact
        var triggers = match["triggers"]?.list?.compactMap(\.string) ?? []
        if let trigger = match["trigger"]?.string { triggers.insert(trigger, at: 0) }
        if triggers.isEmpty {
            if let regex = match["regex"]?.string {
                return [ImportEntry(abbreviation: regex, content: "", name: label, groupName: group,
                                    unsupported: "A regex trigger: Shorthand matches exact abbreviations")]
            }
            return []
        }
        var notes: [String] = []
        func note(_ message: String) { if !notes.contains(message) { notes.append(message) } }

        // Variables: name → Shorthand placeholder text.
        var tokens: [String: String] = [:]
        var forms: [String: [String: String]] = [:]
        for variable in globals + (match["vars"]?.list ?? []) {
            guard let name = variable["name"]?.string else { continue }
            let params = variable["params"]
            switch variable["type"]?.string ?? "" {
            case "date":
                let format = params?["format"]?.string ?? "%x"
                var spec: DateSpec
                if format == "%x" || format == "%c" {
                    spec = DateSpec(kind: format == "%x" ? .date : .datetime)
                } else {
                    let converted = DateFormatConversion.pattern(fromStrftime: format)
                    if !converted.unknown.isEmpty { note("Date codes \(converted.unknown.joined(separator: " ")) have no equivalent and were left out.") }
                    spec = DateSpec(kind: .date, format: converted.pattern.isEmpty ? nil : converted.pattern)
                }
                if let seconds = params?["offset"]?.string.flatMap(Int.init), seconds != 0 {
                    if seconds % 86_400 == 0 { spec.offset = DateOffset(amount: seconds / 86_400, unit: .day) }
                    else if seconds % 3_600 == 0 { spec.offset = DateOffset(amount: seconds / 3_600, unit: .hour) }
                    else if seconds % 60 == 0 { spec.offset = DateOffset(amount: seconds / 60, unit: .minute) }
                    else { note("A date offset in seconds was left out.") }
                }
                tokens[name] = PlaceholderParser.token(for: .date(spec))
            case "clipboard":
                tokens[name] = "{clipboard}"
            case "echo":
                tokens[name] = PlaceholderParser.escape(params?["echo"]?.string ?? "")
            case "choice", "list":
                let options = (params?["values"]?.list ?? []).compactMap { $0.string ?? $0["label"]?.string ?? $0["id"]?.string }
                    .map(cleanName)
                tokens[name] = options.isEmpty ? "" : PlaceholderParser.token(for: .choice(name: cleanName(name), options: options))
            case "form":
                let layout = params?["layout"]?.string ?? ""
                let fields = params?["fields"]
                var formTokens: [String: String] = [:]
                for field in formFieldNames(layout) {
                    formTokens[field] = fieldToken(field, definition: fields?[field], note: note)
                }
                forms[name] = formTokens
            case "match":
                if let trigger = params?["trigger"]?.string { tokens[name] = "{snippet:\(trigger)}" }
            case "shell", "script":
                tokens[name] = ""
                note("A \(variable["type"]?.string ?? "") variable was left out: Shorthand doesn't run commands.")
            default:
                tokens[name] = ""
                note("A “\(variable["type"]?.string ?? "unknown")” variable was left out.")
            }
        }

        // The text, with {{var}}, {{form.field}}, [[field]] (form:) and $|$ converted.
        var body: String
        var kind = "replace"
        if let replace = match["replace"]?.string {
            body = replace
        } else if let form = match["form"]?.string {
            body = form
            kind = "form"
        } else if let markdown = match["markdown"]?.string {
            body = markdown
            kind = "markdown"
        } else if let html = match["html"]?.string {
            body = html
            kind = "html"
        } else if let path = match["image_path"]?.string {
            body = path
            kind = "image"
        } else {
            return triggers.map { ImportEntry(abbreviation: $0, content: "", name: label, groupName: group, notes: notes) }
        }

        var content = ""
        var richText: Data?
        switch kind {
        case "image":
            let url = resolve(path: body, relativeTo: fileURL)
            if let image = RichText.image(at: url) {
                content = image.string
                richText = RichText.encode(image)
            } else {
                note("The image “\(url.lastPathComponent)” couldn't be read, so this one is empty.")
            }
        case "markdown", "html":
            let template = convert(body, tokens: tokens, forms: forms, formFields: nil, note: note, escape: kind == "markdown")
            let rich = kind == "markdown" ? RichText.fromMarkdown(template) : RichText.fromHTML(template)
            if let rich {
                content = rich.string
                richText = RichText.encode(rich)
            } else {
                content = template
                note("Its formatting couldn't be read, so it comes in as plain text.")
            }
        default:
            content = convert(body, tokens: tokens, forms: forms, formFields: kind == "form" ? (match["form_fields"] ?? .map([])) : nil,
                              note: note, escape: true)
        }
        let first = triggers[0]
        var result = [ImportEntry(abbreviation: first, content: content, richText: richText, name: label, groupName: group,
                                  caseMode: caseMode, notes: notes)]
        // More triggers for the same text: each becomes a snippet that includes the first.
        for other in triggers.dropFirst() {
            result.append(ImportEntry(abbreviation: other, content: "{snippet:\(first)}", name: label, groupName: group, caseMode: caseMode,
                                      preview: "Same as \(first)", notes: []))
        }
        return result
    }

    static func cleanName(_ name: String) -> String {
        name.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "").replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func formFieldNames(_ layout: String) -> [String] {
        var names: [String] = []
        var rest = Substring(layout)
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            let name = String(rest[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !names.contains(name) { names.append(name) }
            rest = rest[close.upperBound...]
        }
        return names
    }

    static func fieldToken(_ field: String, definition: YAMLValue?, note: (String) -> Void) -> String {
        let name = cleanName(field)
        switch definition?["type"]?.string ?? "text" {
        case "choice", "list":
            let options = (definition?["values"]?.list ?? []).compactMap { $0.string ?? $0["label"]?.string }.map(cleanName)
            var ordered = options
            if let chosen = definition?["default"]?.string.map(cleanName), let index = ordered.firstIndex(of: chosen), index > 0 {
                ordered.insert(ordered.remove(at: index), at: 0)
            }
            return ordered.isEmpty ? "" : PlaceholderParser.token(for: .choice(name: name, options: ordered))
        default:
            if definition?["multiline"]?.bool == true { note("A multi-line fill-in became a one-line field.") }
            let value = cleanName(definition?["default"]?.string ?? "")
            return PlaceholderParser.token(for: .field(name: name, defaultValue: value))
        }
    }

    /// espanso's text → Shorthand's: braces escaped (for plain text), `{{var}}` and
    /// `{{form.field}}` to placeholders, `[[field]]` for `form:` matches, `$|$` to the cursor.
    static func convert(_ text: String, tokens: [String: String], forms: [String: [String: String]], formFields: YAMLValue?,
                        note: (String) -> Void, escape: Bool) -> String {
        var result = ""
        var rest = Substring(text)
        while !rest.isEmpty {
            if rest.hasPrefix("{{"), let close = rest.range(of: "}}") {
                let name = rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound].trimmingCharacters(in: .whitespaces)
                if let token = tokens[name] {
                    result += token
                } else if let dot = name.firstIndex(of: "."), let form = forms[String(name[..<dot])],
                          let token = form[String(name[name.index(after: dot)...])] {
                    result += token
                } else {
                    note("“{{\(name)}}” isn't defined in this file, so it was left out.")
                }
                rest = rest[close.upperBound...]
                continue
            }
            if let formFields, rest.hasPrefix("[["), let close = rest.range(of: "]]") {
                let name = rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound].trimmingCharacters(in: .whitespaces)
                result += fieldToken(name, definition: formFields[name], note: note)
                rest = rest[close.upperBound...]
                continue
            }
            if rest.hasPrefix("$|$") {
                result += "{cursor}"
                rest = rest.dropFirst(3)
                continue
            }
            let character = rest.removeFirst()
            if escape && (character == "{" || character == "}") {
                result += String(character) + String(character)
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// `$CONFIG/…` is espanso's config folder (the parent of `match/`); other relative paths
    /// are next to the file.
    static func resolve(path: String, relativeTo fileURL: URL) -> URL {
        let folder = fileURL.deletingLastPathComponent()
        let config = folder.lastPathComponent == "match" ? folder.deletingLastPathComponent() : folder
        var expanded = path.replacingOccurrences(of: "$CONFIG", with: config.path).replacingOccurrences(of: "%CONFIG%", with: config.path)
        expanded = (expanded as NSString).expandingTildeInPath
        return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
    }
}
