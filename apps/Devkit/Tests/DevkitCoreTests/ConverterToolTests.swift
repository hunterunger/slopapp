import Foundation
import Testing
@testable import DevkitCore

@Suite struct YAMLTests {
    // YAML 1.2 spec, Example 2.1 "Sequence of Scalars".
    @Test func specExample2_1() throws {
        let json = try YAMLConverter.toJSON("- Mark McGwire\n- Sammy Sosa\n- Ken Griffey\n")
        #expect(json == "[\n  \"Mark McGwire\",\n  \"Sammy Sosa\",\n  \"Ken Griffey\"\n]")
    }

    // Example 2.2 "Mapping Scalars to Scalars", with comments; order is kept.
    @Test func specExample2_2() throws {
        let value = try YAMLConverter.parse("hr:  65    # Home runs\navg: 0.278 # Batting average\nrbi: 147   # Runs Batted In\n")
        #expect(value == .object([("hr", .number("65")), ("avg", .number("0.278")), ("rbi", .number("147"))]))
    }

    // Example 2.10: anchors and aliases.
    @Test func specExample2_10Aliases() throws {
        let yaml = """
        ---
        hr:
          - Mark McGwire
          # Following node labeled SS
          - &SS Sammy Sosa
        rbi:
          - *SS # Subsequent occurrence
          - Ken Griffey
        """
        let value = try YAMLConverter.parse(yaml)
        #expect(value["rbi"] == .array([.string("Sammy Sosa"), .string("Ken Griffey")]))
    }

    @Test func coreSchemaKeepsNorwayAString() throws {
        let value = try YAMLConverter.parse("country: no\nenabled: true\nnothing: ~\nempty:\nhex: 0x1F\nbig: 12345678901234567890\nversion: '1.0'\nfloat: .5\n")
        #expect(value == .object([
            ("country", .string("no")), ("enabled", .bool(true)), ("nothing", .null), ("empty", .null),
            ("hex", .number("31")), ("big", .number("12345678901234567890")), ("version", .string("1.0")), ("float", .number("0.5")),
        ]))
    }

    @Test func mergeKeys() throws {
        let yaml = "base: &base\n  a: 1\n  b: 2\nchild:\n  <<: *base\n  b: 3\n"
        let value = try YAMLConverter.parse(yaml)
        #expect(value["child"] == .object([("b", .number("3")), ("a", .number("1"))]))
    }

    @Test func multipleDocumentsBecomeAnArray() throws {
        #expect(try YAMLConverter.parse("a: 1\n---\nb: 2\n") == .array([.object([("a", .number("1"))]), .object([("b", .number("2"))])]))
    }

    @Test func blockScalars() throws {
        let value = try YAMLConverter.parse("literal: |\n  line 1\n  line 2\nfolded: >\n  one\n  two\n")
        #expect(value == .object([("literal", .string("line 1\nline 2\n")), ("folded", .string("one two\n"))]))
    }

    @Test func errorsHaveALocation() {
        do {
            _ = try YAMLConverter.parse("a: 1\n b: 2\n  - c\n")
            Issue.record("expected an error")
        } catch let error as YAMLConverter.ConversionError {
            #expect(error.line != nil)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test(arguments: [
        #"{"name":"Devkit","tags":["a","b"],"nested":{"x":1,"y":[{"k":true},{"k":null}]},"empty":{},"list":[]}"#,
        ##"{"tricky":["yes","no","on","null","~","1.0","0x10","2024-01-01","- dash",": colon","a: b","#hash","  spaced  ","","multi\nline\n","tab\there","quote\"d","emoji 😀"]}"##,
        #"[[1,2],[3,[4,5]],{"a":[[]]}]"#,
        #"{"text":"ends with blank lines\n\n\n","crlf":"a\r\nb","lead":"\nleading"}"#,
        #"[{"a":1,"b":{"c":2}},{"d":[1,{"e":3}]}]"#,
    ])
    func jsonRoundTripsThroughYAML(json: String) throws {
        for indent in [2, 4] {
            let yaml = try YAMLConverter.fromJSON(json, indent: indent)
            #expect(try YAMLConverter.parse(yaml) == (try JSONTree.parse(json)), "indent \(indent):\n\(yaml)")
        }
    }

    @Test func emitsReadableYAML() throws {
        let yaml = try YAMLConverter.fromJSON(#"{"server":{"port":8080,"hosts":["a.example","b.example"]},"users":[{"name":"ann","admin":true}]}"#)
        #expect(yaml == """
        server:
          port: 8080
          hosts:
          - a.example
          - b.example
        users:
        - name: ann
          admin: true

        """)
    }

    @Test func detection() {
        #expect(YAMLConverter.looksLikeYAML("name: devkit\nversion: 1\ntags:\n  - a\n"))
        #expect(!YAMLConverter.looksLikeYAML("Just a sentence: with a colon.\nAnd another line of prose here."))
        #expect(!YAMLConverter.looksLikeYAML("single: line"))
    }
}

@Suite struct CSVTests {
    // RFC 4180 §2: quoted fields with commas, doubled quotes and line breaks.
    @Test func rfc4180Fields() throws {
        let rows = try CSVConverter.parse("a,\"b,c\",\"say \"\"hi\"\"\"\r\n1,\"line\nbreak\",3\r\n")
        #expect(rows == [["a", "b,c", "say \"hi\""], ["1", "line\nbreak", "3"]])
    }

    @Test func toJSONWithHeaderAndTypes() throws {
        let json = try CSVConverter.toJSON("id,name,zip,active\n1,Ann,02134,true\n2,\"Lee, Jr.\",,false\n")
        #expect(json == """
        [
          {
            "id": 1,
            "name": "Ann",
            "zip": "02134",
            "active": true
          },
          {
            "id": 2,
            "name": "Lee, Jr.",
            "zip": "",
            "active": false
          }
        ]
        """)
    }

    @Test func detectsSemicolonsAndTabs() throws {
        #expect(try CSVConverter.parse("a;b;c\n1;2;3") == [["a", "b", "c"], ["1", "2", "3"]])
        #expect(try CSVConverter.parse("a\tb\n1\t2") == [["a", "b"], ["1", "2"]])
    }

    @Test func unclosedQuoteIsAnError() {
        #expect(throws: CSVConverter.ParseError.self) { try CSVConverter.parse("a,\"b\n1,2") }
    }

    @Test func fromJSONFlattensAndQuotes() throws {
        let csv = try CSVConverter.fromJSON(#"[{"id":1,"user":{"name":"Ann, B","tags":["x"]}},{"id":2,"note":"say \"hi\""}]"#)
        #expect(csv == "id,user.name,user.tags,note\n1,\"Ann, B\",\"[\"\"x\"\"]\",\n2,,,\"say \"\"hi\"\"\"\n")
    }

    @Test func roundTrip() throws {
        let json = #"[{"a":"1","b":"x,y"},{"a":"2","b":"line\nbreak"}]"#
        let csv = try CSVConverter.fromJSON(json)
        #expect(try CSVConverter.toJSONValue(csv, options: .init(inferTypes: false)) == (try JSONTree.parse(json)))
    }

    @Test func detection() {
        #expect(CSVConverter.looksLikeCSV("name,age\nann,3\nlee,4"))
        #expect(!CSVConverter.looksLikeCSV("Hello, world.\nThis is prose, mostly, with commas here and there, see."))
    }
}

@Suite struct EscapeTests {
    @Test func htmlEntitiesDecode() {
        #expect(HTMLEntities.decode("&lt;p&gt; &#60;&#x3C; caf&eacute; &copy; &notanentity; AT&T &amp;amp;") == "<p> << café © &notanentity; AT&T &amp;")
        // Two-code-point reference from the WHATWG table.
        #expect(HTMLEntities.decode("&NotEqualTilde;") == "\u{2242}\u{338}")
        #expect(HTMLEntities.decode("&#0;") == "\u{FFFD}")
    }

    @Test func htmlEntitiesEncode() {
        #expect(HTMLEntities.encode("<a href=\"x\">Tom & Jerry's</a>") == "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;")
        #expect(HTMLEntities.encode("café ©", scope: .named) == "caf&eacute; &copy;")
        #expect(HTMLEntities.encode("café 😀", scope: .numeric) == "caf&#233; &#128512;")
        for text in ["héllo <wörld> & ∑ 😀 \u{2329}", "plain"] {
            for scope in HTMLEntities.EncodeScope.allCases {
                #expect(HTMLEntities.decode(HTMLEntities.encode(text, scope: scope)) == text)
            }
        }
    }

    @Test func backslashRoundTrip() throws {
        let text = "Line 1\nTab\there \"quoted\" 'single' back\\slash \u{07} é 😀"
        let escaped = BackslashEscapes.escape(text)
        #expect(escaped == "Line 1\\nTab\\there \\\"quoted\\\" \\'single\\' back\\\\slash \\u0007 é 😀")
        #expect(try BackslashEscapes.unescape(escaped) == text)
        #expect(try BackslashEscapes.unescape(BackslashEscapes.escape(text, escapeUnicode: true)) == text)
        #expect(BackslashEscapes.escape("😀", escapeUnicode: true) == "\\uD83D\\uDE00")
    }

    @Test func unescapeForms() throws {
        #expect(try BackslashEscapes.unescape(#"\x41\u0042\u{1F600}\101\0\/"#) == "AB😀A\0/")
        #expect(throws: BackslashEscapes.UnescapeError.self) { try BackslashEscapes.unescape("bad \\q") }
        #expect(throws: BackslashEscapes.UnescapeError.self) { try BackslashEscapes.unescape("trailing \\") }
        #expect(throws: BackslashEscapes.UnescapeError.self) { try BackslashEscapes.unescape("\\uD83D alone") }
    }

    @Test func hexText() throws {
        #expect(HexText.encode("Hello") == "48 65 6c 6c 6f")
        #expect(HexText.encode("é", separator: .none, uppercase: true) == "C3A9")
        #expect(HexText.encode("Hi", separator: .prefixed) == "0x48 0x69")
        #expect(try HexText.decode("48:65:6C 0x6c\\x6f").text == "Hello")
        #expect(throws: HexText.DecodeError.self) { try HexText.bytes(from: "abc") }
        #expect(throws: HexText.DecodeError.self) { try HexText.bytes(from: "zz") }
    }

    @Test func svgToCSS() throws {
        let css = try SVGToCSS.convert("<svg xmlns=\"http://www.w3.org/2000/svg\">\n  <circle fill=\"#f00\" r=\"1\"/>\n</svg>")
        #expect(css == "background-image: url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle fill='%23f00' r='1'/%3E%3C/svg%3E\");")
        #expect(throws: SVGToCSS.SVGError.self) { try SVGToCSS.convert("not svg") }
        #expect(try SVGToCSS.convert("<svg/>", encoding: .base64) == "background-image: url(\"data:image/svg+xml;base64,PHN2Zy8+\");")
    }
}

@Suite struct TextToolTests {
    @Test func urlParser() throws {
        let parsed = try URLParser.parse("https://user:pw@example.com:8443/a/b%20c?q=hello+world&tag=1&tag=2&x#frag")
        let parts = Dictionary(parsed.parts.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(parts["Scheme"] == "https")
        #expect(parts["Host"] == "example.com")
        #expect(parts["Port"] == "8443")
        #expect(parts["User"] == "user")
        #expect(parts["Path segment 2"] == "b c")
        #expect(parts["Fragment"] == "frag")
        #expect(parsed.query.map { [$0.0, $0.1] } == [["q", "hello world"], ["tag", "1"], ["tag", "2"], ["x", ""]])
        #expect(parsed.queryJSON == "{\n  \"q\": \"hello world\",\n  \"tag\": [\n    \"1\",\n    \"2\"\n  ],\n  \"x\": \"\"\n}")
        #expect(try URLParser.parse("https://example.com").parts.contains { $0.0 == "Port" && $0.1 == "443 (default)" })
        #expect(try URLParser.parse("a=1&b=%26").query.map { $0.1 } == ["1", "&"])
        #expect(throws: URLParser.ParseError.self) { try URLParser.parse("just words") }
    }

    @Test func stringInspector() {
        let stats = StringInspector.stats("Hello, world. Café e\u{301}!\n👨‍👩‍👧 2 lines")
        #expect(stats.lines == 2)
        // "é" is e + U+0301 (one character, two scalars); the family emoji is five scalars.
        #expect(stats.words == 6)
        #expect(stats.sentences == 3)
        #expect(stats.characters == 31)
        #expect(stats.unicodeScalars == 36)
        #expect(stats.utf8Bytes == "Hello, world. Café e\u{301}!\n👨‍👩‍👧 2 lines".utf8.count)
        #expect(stats.digits == 1)
        let rows = StringInspector.scalars("é\n")
        #expect(rows.map(\.codePoint) == ["U+00E9", "U+000A"])
        #expect(rows[0].name == "LATIN SMALL LETTER E WITH ACUTE")
        #expect(rows[0].utf8 == "C3 A9")
        #expect(rows[1].character == "↵")
    }

    @Test func lineTools() {
        var random = SeededRandom(state: 1)
        let text = "banana\nApple\napple\n10\n2\nbanana\n\n"
        let sorted = LineTools.process(text, options: .init(sort: .natural, removeDuplicates: true, caseSensitive: false, removeEmpty: true), random: &random)
        #expect(sorted.text == "2\n10\nApple\nbanana")
        #expect(sorted.duplicatesRemoved == 2)
        #expect(sorted.inputLines == 7)
        let descending = LineTools.process("a\nc\nb", options: .init(sort: .descending), random: &random)
        #expect(descending.text == "c\nb\na")
        let byLength = LineTools.process("ccc\na\nbb\nd", options: .init(sort: .length), random: &random)
        #expect(byLength.text == "a\nd\nbb\nccc")
        let shuffled = LineTools.process("1\n2\n3\n4\n5", options: .init(sort: .shuffle), random: &random)
        #expect(Set(shuffled.text.split(separator: "\n")) == ["1", "2", "3", "4", "5"])
    }

    @Test func loremIpsum() {
        var random = SeededRandom(state: 7)
        let words = LoremIpsum.generate(count: 12, unit: .words, random: &random)
        #expect(words.split(separator: " ").count == 12)
        #expect(words.hasPrefix("lorem ipsum dolor sit amet"))
        let paragraphs = LoremIpsum.generate(count: 3, unit: .paragraphs, random: &random)
        #expect(paragraphs.components(separatedBy: "\n\n").count == 3)
        #expect(paragraphs.hasPrefix(LoremIpsum.classicOpening + "."))
        let sentences = LoremIpsum.generate(count: 4, unit: .sentences, startWithLorem: false, random: &random)
        #expect(sentences.filter { $0 == "." }.count == 4)
        #expect(!sentences.hasPrefix("Lorem ipsum dolor"))
    }

    @Test func randomStrings() {
        var random = SeededRandom(state: 3)
        let options = RandomStrings.Options(length: 32, count: 50, symbols: true, avoidAmbiguous: true)
        let strings = RandomStrings.generate(options, random: &random)
        #expect(strings.count == 50)
        #expect(strings.allSatisfy { $0.count == 32 && !$0.contains(where: { "0Oo1lI".contains($0) }) })
        #expect(Set(strings).count == 50)
        let keys = RandomStrings.generate(.init(length: 16, lowercase: false, groupSize: 4), random: &random)
        #expect(keys[0].split(separator: "-").map(\.count) == [4, 4, 4, 4])
        #expect(RandomStrings.generate(.init(lowercase: false, uppercase: false, digits: false), random: &random).isEmpty)
        #expect(abs(RandomStrings.entropyBits(.init(length: 10, lowercase: false, uppercase: false)) - 33.22) < 0.01)
    }
}
