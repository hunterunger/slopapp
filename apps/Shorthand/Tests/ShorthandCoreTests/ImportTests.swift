import AppKit
import Testing
@testable import ShorthandCore

@Suite("YAML subset")
struct MiniYAMLTests {
    @Test func mappingsSequencesAndScalars() throws {
        let yaml = """
        # comment
        matches:
          - trigger: ":hi"   # trailing comment
            replace: 'it''s "fine"'
            word: true
          - triggers: [":a", ':b', c]
            replace: "tab\\there \\u00e9"
          - trigger: :plain
            replace: plain text
              continued here
        empty:
        flow: {name: x, values: [1, 2]}
        """
        let root = try MiniYAML.parse(yaml)
        let matches = try #require(root["matches"]?.list)
        #expect(matches.count == 3)
        #expect(matches[0]["trigger"]?.string == ":hi")
        #expect(matches[0]["replace"]?.string == "it's \"fine\"")
        #expect(matches[0]["word"]?.bool == true)
        #expect(matches[1]["triggers"]?.list?.compactMap(\.string) == [":a", ":b", "c"])
        #expect(matches[1]["replace"]?.string == "tab\there é")
        #expect(matches[2]["trigger"]?.string == ":plain")
        #expect(matches[2]["replace"]?.string == "plain text continued here")
        #expect(root["empty"] == .null)
        #expect(root["flow"]?["values"]?.list?.compactMap(\.string) == ["1", "2"])
    }

    @Test func sequenceAtTheKeysIndent() throws {
        let root = try MiniYAML.parse("matches:\n- trigger: a\n  replace: b\n- trigger: c\n  replace: d\nafter: 1\n")
        #expect(root["matches"]?.list?.count == 2)
        #expect(root["matches"]?.list?[1]["replace"]?.string == "d")
        #expect(root["after"]?.string == "1")
    }

    @Test func blockScalars() throws {
        let yaml = """
        literal: |
          line one
            indented
          line three
        stripped: |-
          no trailing break
        kept: |+
          keep

        folded: >
          folded
          into one

          new paragraph
        next: x
        """
        let root = try MiniYAML.parse(yaml)
        #expect(root["literal"]?.string == "line one\n  indented\nline three\n")
        #expect(root["stripped"]?.string == "no trailing break")
        #expect(root["kept"]?.string == "keep\n\n")
        #expect(root["folded"]?.string == "folded into one\nnew paragraph\n")
        #expect(root["next"]?.string == "x")
    }

    @Test func multiLineQuotesAnchorsAndNesting() throws {
        let yaml = """
        a: "first
          second"
        b: &shared
          type: date
        c: *shared
        list:
          -
            - nested
          - key: value
            other: 2
        """
        let root = try MiniYAML.parse(yaml)
        #expect(root["a"]?.string == "first second")
        #expect(root["c"]?["type"]?.string == "date")
        #expect(root["list"]?.list?[0].list?[0].string == "nested")
        #expect(root["list"]?.list?[1]["other"]?.string == "2")
    }

    @Test func errorsSayWhere() {
        #expect(throws: MiniYAML.ParseError.self) { try MiniYAML.parse("a: \"never closed\nb: 1") }
        #expect(throws: MiniYAML.ParseError.self) { try MiniYAML.parse("a: 1\n   b: 2") }
        #expect((try? MiniYAML.parse("")) == .null)
    }
}

@Suite("Date codes")
struct DateCodeTests {
    @Test func strftimeToUnicode() {
        #expect(DateFormatConversion.pattern(fromStrftime: "%Y-%m-%d").pattern == "yyyy-MM-dd")
        #expect(DateFormatConversion.pattern(fromStrftime: "%A, %-d %B").pattern == "EEEE, d MMMM")
        #expect(DateFormatConversion.pattern(fromStrftime: "%d of %b at %H:%M %p").pattern == "dd' of 'MMM' at 'HH:mm a")
        #expect(DateFormatConversion.pattern(fromStrftime: "100%% o'clock").pattern == "'100% o''clock'")
        let unknown = DateFormatConversion.pattern(fromStrftime: "%Q %Y {x}")
        #expect(unknown.unknown == ["%Q", "{", "}"])
        #expect(unknown.pattern == " yyyy' x'")
    }
}

@Suite("TextExpander import")
struct TextExpanderImportTests {
    func convert(_ text: String) -> (String, [String]) {
        let result = TextExpanderMacros.convert(text)
        return (TextEdit.apply(result.edits, to: text), result.notes)
    }

    @Test func datesAndMath() {
        #expect(convert("Today is %B %e, %Y.").0 == "Today is {date:format=MMMM d, yyyy}.")
        #expect(convert("%@+7D%A").0 == "{date:+7d format=EEEE}")
        #expect(convert("%H:%M then %1m/%d").0 == "{date:format=HH:mm} then {date:format=M/dd}")
        #expect(convert("50% off, 100%% sure").0 == "50% off, 100% sure")
    }

    @Test func clipboardCursorSnippetsAndBraces() {
        #expect(convert("[%clipboard] %| {x} %snippet:;sig%").0 == "[{clipboard}] {cursor} {{x}} {snippet:;sig}")
        let keys = convert("Name%key:tab%Email")
        #expect(keys.0 == "NameEmail")
        #expect(keys.1 == ["A key press (tab) was left out: Shorthand only inserts text."])
    }

    @Test func fillIns() {
        #expect(convert("Hi %filltext:name=Name:default=there:width=10%!").0 == "Hi {field:Name=there}!")
        #expect(convert("%fillpopup:name=Closing:Cheers:default=Thanks:All the best%").0 == "{choice:Closing|Thanks|Cheers|All the best}")
        #expect(convert("%fillpart:name=PS:default=yes%P.S.%fillpartend%").0 == "{optional:PS}P.S.{/optional}")
        #expect(convert("%fillpart:name=PS%x%fillpartend%").0 == "{optional:PS=off}x{/optional}")
        let area = convert("%fillarea:name=Note:height=4%")
        #expect(area.0 == "{field:Note}")
        #expect(area.1 == ["A multi-line fill-in became a one-line field."])
        #expect(convert("%filltext% and %filltext:default=a%").0 == "{field:Field 1} and {field:Field 2=a}")
    }

    @MainActor @Test func groupFile() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>groupInfo</key><dict><key>groupName</key><string>slopapp-test Replies</string></dict>
          <key>snippetsTE2</key><array>
            <dict><key>abbreviation</key><string>;ty</string><key>label</key><string>Thanks</string>
                  <key>plainText</key><string>slopapp-test Thanks %filltext:name=Name%</string><key>snippetType</key><integer>0</integer></dict>
            <dict><key>abbreviation</key><string>;sh</string><key>plainText</key><string>#!/bin/sh
        echo hi</string><key>snippetType</key><integer>3</integer></dict>
          </array>
        </dict></plist>
        """
        let url = testDirectory().appendingPathComponent("slopapp-test.textexpander")
        let result = try SnippetImport.read(Data(plist.utf8), fileURL: url)
        #expect(result.format == .textExpander)
        #expect(result.entries.count == 2)
        #expect(result.entries[0].groupName == "slopapp-test Replies")
        #expect(result.entries[0].name == "Thanks")
        #expect(result.entries[0].content == "slopapp-test Thanks {field:Name}")
        let rows = SnippetImport.candidates(result.entries, library: Library())
        #expect(rows[0].isSelected)
        #expect(!rows[1].canSelect)
        #expect(rows[1].reason == "A script snippet: Shorthand doesn't run scripts")
        var library = Library()
        #expect(SnippetImport.apply(rows, to: &library) == 1)
        #expect(library.groups.map(\.name) == ["Snippets", "slopapp-test Replies"])
    }

    @Test func formattedSnippetsKeepTheirFormatting() throws {
        let bold = NSFontManager.shared.convert(RichText.baseFont, toHaveTrait: .boldFontMask)
        let text = NSMutableAttributedString(string: "slopapp-test ", attributes: RichText.baseAttributes)
        text.append(NSAttributedString(string: "Best %Y", attributes: [.font: bold]))
        let rtf = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
        let entry = TextExpanderImport.entry(from: ["abbreviation": ";b", "plainText": "slopapp-test Best %Y", "snippetType": 1, "richText": rtf],
                                             group: "G")
        #expect(entry.content == "slopapp-test Best {date:format=yyyy}")
        let decoded = try #require(entry.richText.flatMap(RichText.decode))
        #expect(decoded.string == entry.content)
        #expect((decoded.attribute(.font, at: 13, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        // Rich type without data: plain, with a note.
        let plain = TextExpanderImport.entry(from: ["abbreviation": ";p", "plainText": "x", "snippetType": 1], group: "G")
        #expect(plain.richText == nil && plain.notes.count == 1)
    }
}

@Suite("espanso import")
struct EspansoImportTests {
    @MainActor
    func read(_ yaml: String, folder: URL = testDirectory()) throws -> SnippetImport.Result {
        let url = folder.appendingPathComponent("base.yml")
        return try SnippetImport.read(Data(yaml.utf8), fileURL: url)
    }

    @MainActor @Test func replacementsAndVariables() throws {
        let yaml = """
        global_vars:
          - name: today
            type: date
            params:
              format: "%d/%m/%Y"
        matches:
          - trigger: ":hi"
            replace: "slopapp-test Hello {{today}} {x} $|$"
            label: Greeting
            propagate_case: true
          - trigger: ":tom"
            replace: "{{tomorrow}}"
            vars:
              - name: tomorrow
                type: date
                params:
                  format: "%A"
                  offset: 86400
          - triggers: [":c1", ":c2"]
            replace: "[{{clip}}] {{tone}} {{other}}"
            vars:
              - name: clip
                type: clipboard
              - name: tone
                type: choice
                params:
                  values: [warm, brief]
              - name: other
                type: match
                params:
                  trigger: ":hi"
          - trigger: ":sh"
            replace: "{{out}}"
            vars:
              - name: out
                type: shell
                params:
                  cmd: "echo slopapp-test"
          - regex: ":d(\\\\d+)"
            replace: "x"
        """
        let result = try read(yaml)
        #expect(result.format == .espanso)
        let e = result.entries
        #expect(e.map(\.abbreviation) == [":hi", ":tom", ":c1", ":c2", ":sh", ":d(\\d+)"])
        #expect(e[0].content == "slopapp-test Hello {date:format=dd/MM/yyyy} {{x}} {cursor}")
        #expect(e[0].name == "Greeting" && e[0].caseMode == .adapt)
        #expect(e[0].groupName == "base")
        #expect(e[1].content == "{date:+1d format=EEEE}")
        #expect(e[2].content == "[{clipboard}] {choice:tone|warm|brief} {snippet::hi}")
        #expect(e[3].content == "{snippet::c1}")
        #expect(e[4].content == "")
        #expect(e[4].notes == ["A shell variable was left out: Shorthand doesn't run commands."])
        #expect(e[5].unsupported != nil)
    }

    @MainActor @Test func forms() throws {
        let yaml = """
        matches:
          - trigger: ":form"
            form: |
              Hey [[name]], [[mood]]!
            form_fields:
              mood:
                type: choice
                values:
                  - great
                  - fine
                default: fine
          - trigger: ":f2"
            replace: "Hi {{f.who}}"
            vars:
              - name: f
                type: form
                params:
                  layout: "Who? [[who]]"
        """
        let e = try read(yaml).entries
        #expect(e[0].content == "Hey {field:name}, {choice:mood|fine|great}!\n")
        #expect(e[1].content == "Hi {field:who}")
    }

    @MainActor @Test func markdownHTMLAndImages() throws {
        let folder = testDirectory()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
        try testPNG().write(to: folder.appendingPathComponent("images/slopapp-test.png"))
        let yaml = """
        matches:
          - trigger: ":md"
            markdown: "slopapp-test **bold** {{d}}"
            vars:
              - name: d
                type: date
                params: {format: "%Y"}
          - trigger: ":html"
            html: "<b>slopapp-test</b>"
          - trigger: ":img"
            image_path: "$CONFIG/images/slopapp-test.png"
          - trigger: ":gone"
            image_path: "/tmp/shorthand-test/does-not-exist.png"
        """
        let e = try read(yaml, folder: folder).entries
        #expect(e[0].content == "slopapp-test bold {date:format=yyyy}")
        #expect(e[0].richText != nil)
        #expect(e[1].content == "slopapp-test" && e[1].richText != nil)
        #expect(e[2].content == "\u{FFFC}")
        #expect(e[2].richText.flatMap(RichText.decode).map(RichText.attachments)?.count == 1)
        #expect(e[3].content.isEmpty && e[3].notes.count == 1)
    }
}

@Suite("Other imports")
struct OtherImportTests {
    @Test func csv() {
        let rows = CSVImport.parse("abbreviation,text,name\n;a,\"slopapp-test, with comma\",A\n;b,\"two\nlines \"\"quoted\"\"\",\r\n\n")
        #expect(rows == [["abbreviation", "text", "name"], [";a", "slopapp-test, with comma", "A"], [";b", "two\nlines \"quoted\"", ""]])
        let entries = CSVImport.entries("abbreviation,text\n;a,slopapp-test {x}\n", groupName: "G")
        #expect(entries.count == 1)
        #expect(entries[0].content == "slopapp-test {{x}}")
        #expect(entries[0].preview == "slopapp-test {x}")
    }

    @MainActor @Test func detectsEachFormat() throws {
        let folder = testDirectory()
        let replacements = Data("""
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><array>
        <dict><key>phrase</key><string>slopapp-test</string><key>shortcut</key><string>;t</string></dict></array></plist>
        """.utf8)
        #expect(try SnippetImport.read(replacements, fileURL: folder.appendingPathComponent("Text Substitutions.plist")).format == .textReplacements)
        var library = Library()
        var s = Snippet(groupID: library.defaultGroupID, abbreviation: ";j", content: "slopapp-test", caseMode: .adapt)
        s.richText = RichText.encode(RichText.make(fromPlain: "slopapp-test"))
        library.addSnippet(s)
        let json = try SnippetStore.encode(library)
        let shorthand = try SnippetImport.read(json, fileURL: folder.appendingPathComponent("export.json"))
        #expect(shorthand.format == .shorthand)
        #expect(shorthand.entries[0].richText != nil && shorthand.entries[0].caseMode == .adapt)
        #expect(try SnippetImport.read(Data(";c,slopapp-test".utf8), fileURL: folder.appendingPathComponent("x.csv")).format == .csv)
        #expect(throws: SnippetImport.ReadError.unrecognised) {
            try SnippetImport.read(Data("just some words".utf8), fileURL: folder.appendingPathComponent("notes.txt"))
        }
        #expect(throws: SnippetImport.ReadError.self) {
            try SnippetImport.read(Data("matches:\n  - trigger: \"x\n".utf8), fileURL: folder.appendingPathComponent("bad.yml"))
        }
    }

    @Test func importedGroupsAndDuplicates() {
        var library = Library()
        library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";have", content: "slopapp-test"))
        let entries = [ImportEntry(abbreviation: ";a", content: "slopapp-test a", groupName: "One"),
                       ImportEntry(abbreviation: ";have", content: "slopapp-test b", groupName: "One"),
                       ImportEntry(abbreviation: ";a", content: "slopapp-test c", groupName: "Two"),
                       ImportEntry(abbreviation: ";d", content: "slopapp-test d", groupName: "Two")]
        let rows = SnippetImport.candidates(entries, library: library)
        #expect(rows.map(\.issue) == [nil, .alreadyInLibrary, .repeated, nil])
        #expect(SnippetImport.apply(rows, to: &library) == 2)
        #expect(library.groups.map(\.name) == ["Snippets", "One", "Two"])
    }
}
