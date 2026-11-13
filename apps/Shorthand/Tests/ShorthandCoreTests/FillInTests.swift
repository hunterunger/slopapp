import Foundation
import Testing
@testable import ShorthandCore

@Suite("Fill-ins, sections and nested snippets")
struct FillInTests {
    let now = Date(timeIntervalSince1970: 1_794_060_300)
    var resolver: PlaceholderResolver {
        PlaceholderResolver(now: now, locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian),
                            timeZone: TimeZone(identifier: "UTC")!)
    }

    func library(_ snippets: [Snippet]) -> Library {
        var library = Library()
        for var s in snippets { s.groupID = library.defaultGroupID; library.addSnippet(s) }
        return library
    }

    func resolve(_ snippet: Snippet, in library: Library? = nil, values: FillValues = FillValues(), typedCase: TypedCase = .asWritten) -> Resolved {
        let library = library ?? self.library([snippet])
        return resolver.resolve(snippet, typedCase: typedCase, values: values, lookup: library.lookup) { .text("slopapp-test clip") }
    }

    @Test func parsesFillIns() {
        #expect(PlaceholderParser.parse("{field:Name}") == [.placeholder(.field(name: "Name", defaultValue: ""), raw: "{field:Name}")])
        #expect(PlaceholderParser.parse("{field: First name =Ann}") == [.placeholder(.field(name: "First name", defaultValue: "Ann"), raw: "{field: First name =Ann}")])
        #expect(PlaceholderParser.parse("{choice:Tone|warm| brief }") == [.placeholder(.choice(name: "Tone", options: ["warm", "brief"]), raw: "{choice:Tone|warm| brief }")])
        #expect(PlaceholderParser.parse("{optional:PS}") == [.placeholder(.optionalStart(name: "PS", defaultOn: true), raw: "{optional:PS}")])
        #expect(PlaceholderParser.parse("{optional:PS=off}") == [.placeholder(.optionalStart(name: "PS", defaultOn: false), raw: "{optional:PS=off}")])
        #expect(PlaceholderParser.parse("{/optional}") == [.placeholder(.optionalEnd, raw: "{/optional}")])
        #expect(PlaceholderParser.parse("{snippet:;addr}") == [.placeholder(.snippet(abbreviation: ";addr"), raw: "{snippet:;addr}")])
        // Not quite placeholders: typed as written.
        #expect(PlaceholderParser.parse("{field:}") == [.unknown("{field:}")])
        #expect(PlaceholderParser.parse("{choice:Tone}") == [.unknown("{choice:Tone}")])
        #expect(PlaceholderParser.parse("{optional:PS=maybe}") == [.unknown("{optional:PS=maybe}")])
        #expect(PlaceholderParser.parse("{snippet:}") == [.unknown("{snippet:}")])
    }

    @Test func newTokensRoundTrip() {
        for placeholder: Placeholder in [.field(name: "Name", defaultValue: ""), .field(name: "City", defaultValue: "Oslo"),
                                         .choice(name: "Tone", options: ["warm", "brief"]), .optionalStart(name: "PS", defaultOn: false),
                                         .optionalStart(name: "PS", defaultOn: true), .optionalEnd, .snippet(abbreviation: ";sig")] {
            let token = PlaceholderParser.token(for: placeholder)
            #expect(PlaceholderParser.parse(token) == [.placeholder(placeholder, raw: token)])
        }
    }

    @Test func tokenRangesAreUTF16AndEscapesStandAlone() {
        let tokens = PlaceholderParser.tokens("é{{x{cursor}👍🏽")
        #expect(tokens.map(\.range) == [0..<1, 1..<3, 3..<4, 4..<12, 12..<16])
        #expect(tokens[1].segment == .text("{"))
        // Literal tokens are exactly their source.
        let content = "Hi {field:Name}, bye"
        let utf16 = Array(content.utf16)
        for token in PlaceholderParser.tokens(content) {
            if case .text(let text) = token.segment {
                #expect(String(decoding: utf16[token.range], as: UTF16.self) == text)
            }
        }
    }

    @Test func fieldsInOrderAndNamesFillOnce() {
        let s = snippet(";reply", "Hi {field:Name}, {choice:Tone|warm|brief}. {optional:PS}P.S. {field:name} {field:Extra}{/optional}")
        let fields = FillIn.fields(for: s, lookup: { _ in nil })
        #expect(fields.map(\.name) == ["Name", "Tone", "PS", "Extra"])
        #expect(fields[0].kind == .text(defaultValue: ""))
        #expect(fields[1].kind == .choice(options: ["warm", "brief"]))
        #expect(fields[2].kind == .section(defaultOn: true))
        // Name also appears outside the section; Extra only inside it.
        #expect(fields[0].onlyInSection == nil)
        #expect(fields[3].onlyInSection == "ps")
        #expect(FillIn.fields(for: snippet(";p", "plain {date}"), lookup: { _ in nil }).isEmpty)
    }

    @Test func resolvesWithValuesAndDefaults() {
        let s = snippet(";reply", "Hi {field:Name=there}, {choice:Tone|warm|brief}.{optional:PS} P.S. {field:name}{/optional}")
        #expect(resolve(s).text == "Hi there, warm. P.S. there")
        var values = FillValues()
        values["NAME"] = .text("slopapp-test Ann")
        values["tone"] = .text("brief")
        values["PS"] = .flag(false)
        #expect(resolve(s, values: values).text == "Hi slopapp-test Ann, brief.")
        values["ps"] = .flag(true)
        #expect(resolve(s, values: values).text == "Hi slopapp-test Ann, brief. P.S. slopapp-test Ann")
    }

    @Test func sectionsNestAndOffByDefault() {
        let s = snippet(";s", "a{optional:One=off}b{optional:Two}c{/optional}d{/optional}e")
        #expect(resolve(s).text == "ae")
        #expect(resolve(s, values: FillValues(["One": .flag(true)])).text == "abcde")
        #expect(resolve(s, values: FillValues(["One": .flag(true), "Two": .flag(false)])).text == "abde")
        // A cursor inside an excluded section doesn't count.
        let c = snippet(";c", "x{optional:S=off}{cursor}{/optional}yz")
        #expect(resolve(c).charactersAfterCursor == 0)
    }

    @Test func nestedSnippets() {
        let sig = snippet(";sig", "slopapp-test Best, {field:Name}")
        let reply = snippet(";reply", "Thanks {field:Name}!\n{snippet:;sig}")
        let lib = library([sig, reply])
        let r = resolve(lib.snippets[1], in: lib, values: FillValues(["name": .text("Bo")]))
        #expect(r.text == "Thanks Bo!\nslopapp-test Best, Bo")
        #expect(r.includedSnippets == [lib.snippets[0].id])
        // The included snippet's fields join the form, once.
        #expect(FillIn.fields(for: lib.snippets[1], lookup: lib.lookup).map(\.name) == ["Name"])
        // Included snippets keep their own cursor (the first in the result wins).
        let a = snippet(";a", "[{snippet:;b}]")
        let b = snippet(";b", "b{cursor}b")
        let lib2 = library([a, b])
        #expect(resolve(lib2.snippets[0], in: lib2).charactersAfterCursor == 2)
    }

    @Test func nestedSnippetsInGroupsThatAreOff() {
        var lib = library([snippet(";part", "slopapp-test part"), snippet(";whole", "<{snippet:;part}>")])
        let off = lib.addGroup(named: "Parts")
        lib.setGroup(off.id, enabled: false)
        lib.move([lib.snippets[0].id], to: off.id)
        #expect(resolve(lib.snippets[1], in: lib).text == "<slopapp-test part>")
    }

    @Test func cyclesAndMissingReferences() {
        let a = snippet(";a", "a{snippet:;b}")
        let b = snippet(";b", "b{snippet:;a}")
        let selfRef = snippet(";self", "x{snippet:;self}y")
        let missing = snippet(";m", "x{snippet:;nope}y")
        let lib = library([a, b, selfRef, missing])
        let r = resolve(lib.snippets[0], in: lib)
        #expect(r.text == "ab")
        #expect(r.cyclicSnippets == [";a"])
        #expect(resolve(lib.snippets[2], in: lib).text == "xy")
        let m = resolve(lib.snippets[3], in: lib)
        #expect(m.text == "xy")
        #expect(m.missingSnippets == [";nope"])
        #expect(TemplateCheck.notes(for: lib.snippets[0], lookup: lib.lookup) == [.cycle(";b")])
        #expect(TemplateCheck.notes(for: lib.snippets[2], lookup: lib.lookup) == [.cycle(";self")])
        #expect(TemplateCheck.notes(for: lib.snippets[3], lookup: lib.lookup) == [.missingSnippet(";nope")])
        // Fields walk stops at cycles too.
        #expect(FillIn.fields(for: lib.snippets[0], lookup: lib.lookup).isEmpty)
    }

    @Test func deepNestingStops() {
        var snippets: [Snippet] = []
        for i in 0..<12 { snippets.append(snippet(";n\(i)", "\(i){snippet:;n\(i + 1)}")) }
        let lib = library(snippets)
        let r = resolve(lib.snippets[0], in: lib)
        #expect(r.text == "01234567")
        #expect(r.cyclicSnippets == [";n8"])
    }

    @Test func templateNotes() {
        let lookup: (String) -> Snippet? = { _ in nil }
        #expect(TemplateCheck.notes(for: snippet(";x", "a{/optional}"), lookup: lookup) == [.strayEnd])
        #expect(TemplateCheck.notes(for: snippet(";x", "{optional:PS}a"), lookup: lookup) == [.unclosed("PS")])
        #expect(TemplateCheck.notes(for: snippet(";x", "{field:Tone} {choice:tone|a|b}"), lookup: lookup) == [.nameClash("Tone")])
        #expect(TemplateCheck.notes(for: snippet(";x", "{field:Tone} {optional:X}{/optional}"), lookup: lookup).isEmpty)
    }

    @Test func adaptCaseStillAppliesToTheStart() {
        let s = snippet(";hi", "{{hello}} {field:Name}")
        #expect(resolve(s, typedCase: .capitalized).text == "{Hello} ")
        #expect(resolve(snippet(";x", "{field:N=a} hello"), typedCase: .capitalized).text == "a hello")
    }

    @Test func clipboardNeededThroughNesting() {
        let lib = library([snippet(";c", "{clipboard}"), snippet(";outer", "x {snippet:;c}")])
        #expect(PlaceholderResolver.needsClipboard(lib.snippets[1], lookup: lib.lookup))
        #expect(!PlaceholderResolver.needsClipboard("x {{clipboard}}"))
    }

    @Test func piecesPointBackAtTheirSource() {
        let s = snippet(";p", "Dear {field:Name}, {{ok}}")
        let r = resolve(s, values: FillValues(["Name": .text("Ann")]))
        #expect(r.pieces.map(\.text) == ["Dear ", "Ann", ", ", "{", "ok", "}"])
        #expect(r.pieces[1].generated)
        #expect(r.pieces[1].source == 5..<17)
        #expect(r.pieces.allSatisfy { $0.snippetID == s.id })
        #expect(!r.isFormatted)
    }

    @Test func imagesArentInThePlainText() {
        var s = snippet(";img", "Logo: \u{FFFC}{cursor}\u{FFFC} end")
        s.richText = Data([1])
        let r = resolve(s)
        #expect(r.text == "Logo:  end")
        #expect(r.isFormatted)
        #expect(r.charactersAfterCursor == 4)
        #expect(r.formattedCharactersAfterCursor == 5)
        let plan = InsertionPlanner.plan(resolved: r, typedLength: 4, pending: "", mode: .alwaysType)
        #expect(plan.method == .paste && plan.formatted && plan.leftArrows == 5)
        #expect(s.plainContent == "Logo: {cursor} end")
        var only = snippet(";o", "\u{FFFC}")
        only.richText = Data([1])
        #expect(only.title == "Image")
    }
}

@Suite("Quick search")
struct QuickSearchTests {
    @Test func emptyQueryShowsMostUsedFirst() {
        var a = snippet(";a", "slopapp-test alpha"); a.useCount = 1
        var b = snippet(";b", "slopapp-test beta"); b.useCount = 5
        var c = snippet(";c", "slopapp-test gamma"); c.useCount = 1; c.lastUsed = Date(timeIntervalSince1970: 100)
        let empty = snippet(";e", "")
        #expect(QuickSearch.results([a, b, c, empty], query: "").map(\.abbreviation) == [";b", ";c", ";a"])
    }

    @Test func abbreviationThenTitleThenText() {
        let text = snippet(";zz", "slopapp-test mentions addr in passing")
        var title = snippet(";q", "slopapp-test x"); title.name = "Addr book"
        let prefix = snippet(";address", "slopapp-test y")
        let exact = snippet("addr", "slopapp-test z")
        #expect(QuickSearch.results([text, title, prefix, exact], query: "ADDR").map(\.abbreviation) == ["addr", ";address", ";zz", ";q"])
        #expect(QuickSearch.results([text, title, prefix, exact], query: ";add").map(\.abbreviation) == [";address"])
        // The abbreviation's leading symbol doesn't count; title words match by prefix.
        var sig = snippet(";sigf", "slopapp-test s"); sig.name = "Formatted signature"
        var mention = snippet(";reply", "slopapp-test {snippet:;sigf}"); mention.useCount = 9
        #expect(QuickSearch.results([mention, sig], query: "sig").map(\.abbreviation) == [";sigf", ";reply"])
        var sign = snippet(";x", "slopapp-test"); sign.name = "Old signature"
        #expect(QuickSearch.results([mention, sign], query: "sign").map(\.abbreviation) == [";x"])
        #expect(QuickSearch.results((0..<200).map { snippet(";s\($0)", "slopapp-test") }, query: "").count == QuickSearch.limit)
    }
}
