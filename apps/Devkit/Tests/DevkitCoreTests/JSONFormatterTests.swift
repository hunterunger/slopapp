import Foundation
import Testing
@testable import DevkitCore

@Suite struct JSONFormatterTests {
    @Test func prettyPrintsKeepingKeyOrderAndNumberText() throws {
        let input = #"{"z":1,"a":[12345678901234567890,1.10,-0.5e-3],"m":{"x":true,"y":null},"e":{},"f":[]}"#
        let result = try JSONFormatter.format(input)
        #expect(result.text == """
        {
          "z": 1,
          "a": [
            12345678901234567890,
            1.10,
            -0.5e-3
          ],
          "m": {
            "x": true,
            "y": null
          },
          "e": {},
          "f": []
        }
        """)
        #expect(result.lineCount == 14)
    }

    @Test func minifies() throws {
        let input = "{\n  \"a\" : [ 1 , 2 ],\n  \"b\" : \"x y\"\n}\n"
        #expect(try JSONFormatter.format(input, options: .init(style: .minified)).text == #"{"a":[1,2],"b":"x y"}"#)
    }

    @Test func sortsKeysRecursivelyByCodeUnit() throws {
        let input = #"{"b":{"d":1,"c":[{"z":0,"y":1}]},"a":2,"B":3}"#
        let result = try JSONFormatter.format(input, options: .init(style: .minified, sortKeys: true))
        #expect(result.text == #"{"B":3,"a":2,"b":{"c":[{"y":1,"z":0}],"d":1}}"#)
        let pretty = try JSONFormatter.format(#"{"b":[],"a":{}}"#, options: .init(sortKeys: true))
        #expect(pretty.text == "{\n  \"a\": {},\n  \"b\": []\n}")
    }

    @Test func sortUsesDecodedKeys() throws {
        let result = try JSONFormatter.format(#"{"b":1,"a":2}"#, options: .init(style: .minified, sortKeys: true))
        #expect(result.text == #"{"a":2,"b":1}"#)
    }

    @Test(arguments: [JSONFormatter.Indent.two, .four, .tab])
    func indentOptions(indent: JSONFormatter.Indent) throws {
        let result = try JSONFormatter.format("[1]", options: .init(indent: indent))
        let unit = indent == .tab ? "\t" : String(repeating: " ", count: indent == .two ? 2 : 4)
        #expect(result.text == "[\n\(unit)1\n]")
    }

    @Test func scalarsAtTopLevel() throws {
        #expect(try JSONFormatter.format(" \"hi\" ").text == "\"hi\"")
        #expect(try JSONFormatter.format("42").text == "42")
        #expect(try JSONFormatter.format("\u{FEFF}{}").text == "{}")
    }

    @Test func keepsEscapesAndUnicodeAsWritten() throws {
        let input = #"{"emoji":"😀 😀","tab":"a\tb","q":"\"\\\/"}"#
        #expect(try JSONFormatter.format(input, options: .init(style: .minified)).text == input)
    }

    @Test func warnsAboutDuplicateKeys() throws {
        let result = try JSONFormatter.format("{\"a\":1,\n\"a\":2}")
        #expect(result.warnings == ["Duplicate key “a” at line 2, column 1."])
    }

    struct Bad: Sendable, CustomTestStringConvertible {
        let input: String
        let line: Int
        let column: Int
        let message: String
        var testDescription: String { input }
    }

    @Test(arguments: [
        Bad(input: "{\"a\":1,}", line: 1, column: 7, message: "Trailing comma before }. Remove the comma."),
        Bad(input: "[1,2,]", line: 1, column: 5, message: "Trailing comma before ]. Remove the comma."),
        Bad(input: "{\n  \"a\": 1\n  \"b\": 2\n}", line: 3, column: 3, message: "Expected , or } after the value."),
        Bad(input: "{'a':1}", line: 1, column: 2, message: "Keys need double quotes, not single quotes."),
        Bad(input: "[NaN]", line: 1, column: 2, message: "NaN isn't valid JSON. Use null or a string."),
        Bad(input: "[-Infinity]", line: 1, column: 2, message: "Infinity isn't valid JSON. Use null or a string."),
        Bad(input: "{// hi\n}", line: 1, column: 2, message: "Comments aren't allowed in JSON."),
        Bad(input: "[01]", line: 1, column: 2, message: "Numbers can't have leading zeros."),
        Bad(input: "[1.]", line: 1, column: 4, message: "Expected a digit after the decimal point."),
        Bad(input: "{\"a\" 1}", line: 1, column: 6, message: "Expected : after the key."),
        Bad(input: "[\"abc", line: 1, column: 2, message: "The string isn't closed. Add a \"."),
        Bad(input: "{\"a\":[1,2]", line: 1, column: 11, message: "The object isn't closed. Add a }."),
        Bad(input: "{} {}", line: 1, column: 4, message: "Unexpected text after the JSON value."),
        Bad(input: "[\"a\\x\"]", line: 1, column: 4, message: "Unknown escape \\x. Use \\\\ for a backslash."),
        Bad(input: "[tru]", line: 1, column: 2, message: "Expected true or false."),
        Bad(input: "   ", line: 1, column: 4, message: "The input is empty. Paste some JSON."),
        Bad(input: "[\"é\", x]", line: 1, column: 7, message: "Expected a value."),
    ])
    func reportsErrorsWithLocation(bad: Bad) {
        do {
            _ = try JSONFormatter.format(bad.input)
            Issue.record("expected an error")
        } catch let error as JSONError {
            #expect(error.message == bad.message)
            #expect(error.line == bad.line)
            #expect(error.column == bad.column)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func deepNestingDoesNotOverflow() throws {
        let depth = 100_000
        let input = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let result = try JSONFormatter.format(input, options: .init(style: .minified))
        #expect(result.text == input)
        _ = try JSONFormatter.format(String(repeating: "{\"a\":", count: 500) + "1" + String(repeating: "}", count: 500),
                                     options: .init(sortKeys: true))
    }

    @Test func roundTripsThroughFoundation() throws {
        let input = #"{"name":"Ada","tags":["x","y"],"n":{"k":[1,2,{"deep":false}]}}"#
        let pretty = try JSONFormatter.format(input).text
        let a = try JSONSerialization.jsonObject(with: Data(input.utf8)) as? NSDictionary
        let b = try JSONSerialization.jsonObject(with: Data(pretty.utf8)) as? NSDictionary
        #expect(a == b)
    }

    @Test func cancels() {
        let big = "[" + Array(repeating: "1", count: 200_000).joined(separator: ",") + "]"
        #expect(throws: CancellationError.self) {
            _ = try JSONFormatter.format(big, isCancelled: { true })
        }
    }

    @Test func largeInputIsFast() throws {
        let item = #"{"id":12345,"name":"Item name here","tags":["alpha","beta"],"price":12.5,"ok":true},"#
        // Debug builds (scripts/test.sh) are ~20x slower than release; release does 50 MB in < 1 s.
        let count = 5_000_000 / item.utf8.count
        var input = "["
        input.reserveCapacity(5_000_100)
        for _ in 0..<count { input += item }
        input.removeLast()
        input += "]"
        let clock = ContinuousClock()
        var result: JSONFormatter.Result?
        let elapsed = try clock.measure { result = try JSONFormatter.format(input) }
        #expect(result != nil)
        #expect(elapsed < .seconds(10), "5 MB took \(elapsed)")
    }
}
