import Foundation
import Testing
@testable import DevkitCore

@Suite struct Base64Tests {
    // RFC 4648 §10 test vectors.
    static let vectors: [(String, String)] = [
        ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"),
        ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
    ]

    @Test func rfc4648Encode() {
        for (plain, encoded) in Self.vectors {
            #expect(Base64.encode(plain) == encoded)
        }
    }

    @Test func rfc4648Decode() throws {
        for (plain, encoded) in Self.vectors where !encoded.isEmpty {
            #expect(try Base64.decodeText(encoded).text == plain)
        }
    }

    @Test func urlSafeAndUnpadded() throws {
        let data = Data([0xFB, 0xFF, 0xBF])
        #expect(Base64.encode(data) == "+/+/")
        #expect(Base64.encode(data, options: .init(urlSafe: true)) == "-_-_")
        #expect(Base64.encode("f", options: .init(padding: false)) == "Zg")
        #expect(try Base64.decode("-_-_") == data)
        #expect(try Base64.decode("Zg") == Data("f".utf8))
        #expect(try Base64.decode("Zm9v\nYmFy \r\n") == Data("foobar".utf8))
    }

    @Test func decodeErrors() {
        #expect(throws: Base64.DecodeError.invalidCharacter("$", position: 2)) { try Base64.decode("Zm$v") }
        #expect(throws: Base64.DecodeError.misplacedPadding(position: 2)) { try Base64.decode("Zg==Zg==") }
        #expect(throws: Base64.DecodeError.invalidLength) { try Base64.decode("Zm9vY") }
        #expect(throws: Base64.DecodeError.empty) { try Base64.decode("  ") }
    }

    @Test func binaryShowsHexDump() throws {
        let decoded = try Base64.decodeText(Base64.encode(Data([0x00, 0x01, 0xFF, 0x41])))
        #expect(decoded.text == nil)
        #expect(decoded.display == "00000000  00 01 ff 41                                       |...A|")
    }

    @Test func emojiRoundTrip() throws {
        let text = "Grüße 👋🏽"
        #expect(try Base64.decodeText(Base64.encode(text)).text == text)
    }
}

@Suite struct URLCodingTests {
    @Test func componentEncodesReserved() {
        #expect(URLCoding.encode("a b&c=d/é") == "a%20b%26c%3Dd%2F%C3%A9")
        #expect(URLCoding.encode("a b", spaceAsPlus: true) == "a+b")
        #expect(URLCoding.encode("-._~") == "-._~")
    }

    @Test func wholeURLKeepsStructure() {
        #expect(URLCoding.encode("https://example.com/a b?q=1&r=é#top", scope: .wholeURL)
                == "https://example.com/a%20b?q=1&r=%C3%A9#top")
    }

    @Test func decodes() throws {
        #expect(try URLCoding.decode("a%20b%26c+d") == "a b&c d")
        #expect(try URLCoding.decode("a+b", plusAsSpace: false) == "a+b")
        #expect(try URLCoding.decode("%F0%9F%91%8B") == "👋")
    }

    @Test func decodeErrors() {
        #expect(throws: URLCoding.DecodeError.invalidEscape("%G1", position: 2)) { try URLCoding.decode("ab%G1") }
        #expect(throws: URLCoding.DecodeError.invalidEscape("%2", position: 1)) { try URLCoding.decode("a%2") }
        #expect(throws: URLCoding.DecodeError.notUTF8) { try URLCoding.decode("%FF%FE") }
    }

    @Test func roundTrip() throws {
        let text = "name=Ada Lovelace & co/100% 🎉"
        #expect(try URLCoding.decode(URLCoding.encode(text)) == text)
    }
}

@Suite struct NumberBaseTests {
    @Test func convertsWithPrefixes() throws {
        let hex = try NumberBase.parse("0xFF")
        #expect(hex.detectedRadix == 16)
        #expect(hex.string(radix: 10) == "255")
        #expect(hex.string(radix: 2) == "11111111")
        #expect(try NumberBase.parse("0b1010").string(radix: 10) == "10")
        #expect(try NumberBase.parse("0o17").string(radix: 10) == "15")
        #expect(try NumberBase.parse("1_000_000").string(radix: 16) == "f4240")
        #expect(try NumberBase.parse("-42").string(radix: 16, uppercase: true) == "-2A")
        #expect(try NumberBase.parse("0").string(radix: 2) == "0")
    }

    @Test func forcedRadix() throws {
        #expect(try NumberBase.parse("0b", radix: 16).string(radix: 10) == "11")
        #expect(try NumberBase.parse("zz", radix: 36).string(radix: 10) == "1295")
        #expect(throws: NumberBase.ParseError.invalidDigit("2", radix: 2)) { try NumberBase.parse("102", radix: 2) }
    }

    @Test func bigNumbers() throws {
        let value = try NumberBase.parse("340282366920938463463374607431768211455") // 2^128 − 1
        #expect(value.string(radix: 16) == String(repeating: "f", count: 32))
        #expect(value.magnitude.bitWidth == 128)
        let huge = String(repeating: "9", count: 300)
        #expect(try NumberBase.parse(NumberBase.parse(huge).string(radix: 7), radix: 7).string(radix: 10) == huge)
    }

    @Test func errors() {
        #expect(throws: NumberBase.ParseError.empty) { try NumberBase.parse(" ") }
        #expect(throws: NumberBase.ParseError.invalidDigit("g", radix: 16)) { try NumberBase.parse("0xfg") }
    }

    @Test func grouping() {
        #expect(NumberBase.grouped("11111111", size: 4) == "1111 1111")
        #expect(NumberBase.grouped("1000000", size: 3, separator: ",") == "1,000,000")
        #expect(NumberBase.grouped("-12345", size: 3) == "-12 345")
    }
}

@Suite struct CaseConverterTests {
    @Test func splitsWords() {
        #expect(CaseConverter.words("parseHTTPResponse") == ["parse", "HTTP", "Response"])
        #expect(CaseConverter.words("user_id-value.name") == ["user", "id", "value", "name"])
        #expect(CaseConverter.words("utf8String") == ["utf8", "String"])
        #expect(CaseConverter.words("  Hello  World ") == ["Hello", "World"])
    }

    @Test func converts() {
        let input = "parse HTTP response"
        #expect(CaseConverter.convert(input, to: .camel) == "parseHttpResponse")
        #expect(CaseConverter.convert(input, to: .pascal) == "ParseHttpResponse")
        #expect(CaseConverter.convert(input, to: .snake) == "parse_http_response")
        #expect(CaseConverter.convert(input, to: .kebab) == "parse-http-response")
        #expect(CaseConverter.convert(input, to: .constant) == "PARSE_HTTP_RESPONSE")
        #expect(CaseConverter.convert(input, to: .dot) == "parse.http.response")
        #expect(CaseConverter.convert(input, to: .title) == "Parse Http Response")
        #expect(CaseConverter.convert(input, to: .sentence) == "Parse http response")
        #expect(CaseConverter.convert(input, to: .upper) == "PARSE HTTP RESPONSE")
    }

    @Test func perLineAndUnicode() {
        #expect(CaseConverter.convert("fooBar\nbaz_qux", to: .kebab) == "foo-bar\nbaz-qux")
        #expect(CaseConverter.convert("élan vital", to: .pascal) == "ÉlanVital")
        #expect(CaseConverter.convert("", to: .camel) == "")
    }
}
