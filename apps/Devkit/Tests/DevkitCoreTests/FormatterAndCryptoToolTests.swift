import Foundation
import Testing
@testable import DevkitCore

@Suite struct MarkupTests {
    @Test func beautifiesHTML() throws {
        let html = "<!DOCTYPE html><html><head><title>Hi</title><style>body{margin:0}</style></head><body><div class=\"a\"\n  id=\"b\"><p>Hello <b>bold</b> world!</p><ul><li>One<li>Two</ul><br><img src=\"x.png\"><pre>  keep\n   this</pre></div></body></html>"
        let pretty = try MarkupFormatter.beautify(html, dialect: .html)
        #expect(pretty == """
        <!DOCTYPE html>
        <html>
          <head>
            <title>Hi</title>
            <style>
              body{margin:0}
            </style>
          </head>
          <body>
            <div class="a" id="b">
              <p>Hello <b>bold</b> world!</p>
              <ul>
                <li>One</li>
                <li>Two</li>
              </ul>
              <br><img src="x.png">
              <pre>  keep
           this</pre>
            </div>
          </body>
        </html>

        """)
    }

    @Test func minifiesHTMLKeepingInlineSpaces() throws {
        let html = "<div>\n  <p>\n    Hello   <b>a</b> <i>b</i>\n  </p>\n  <!-- note -->\n</div>"
        #expect(try MarkupFormatter.minify(html, dialect: .html) == "<div><p>Hello <b>a</b> <i>b</i></p></div>")
    }

    @Test func beautifiesAndMinifiesXML() throws {
        let xml = "<?xml version=\"1.0\"?><catalog><book id=\"1\"><title>Swift</title><tags><tag>a</tag><tag/></tags></book><!-- c --></catalog>"
        #expect(try MarkupFormatter.beautify(xml, dialect: .xml) == """
        <?xml version="1.0"?>
        <catalog>
          <book id="1">
            <title>Swift</title>
            <tags>
              <tag>a</tag>
              <tag/>
            </tags>
          </book>
          <!-- c -->
        </catalog>

        """)
        let pretty = try MarkupFormatter.beautify(xml, dialect: .xml)
        #expect(try MarkupFormatter.minify(pretty, dialect: .xml) == xml.replacingOccurrences(of: "<!-- c -->", with: ""))
    }

    @Test func invalidXMLIsAnError() {
        #expect(throws: MarkupFormatter.FormatError.self) { try MarkupFormatter.beautify("<a><b></a>", dialect: .xml) }
    }

    @Test func detection() {
        #expect(MarkupFormatter.looksLikeHTML("<!doctype html><html></html>"))
        #expect(MarkupFormatter.looksLikeHTML("<div class=\"x\"><p>Hi</p></div>"))
        #expect(MarkupFormatter.looksLikeXML("<?xml version=\"1.0\"?><a/>"))
        #expect(MarkupFormatter.looksLikeXML("<note><to>Tove</to></note>"))
        #expect(!MarkupFormatter.looksLikeXML("<not closed"))
    }
}

@Suite struct CSSTests {
    @Test func beautifies() {
        let css = "/* top */ a,b>c{color:red;margin:0 auto}@media (max-width:600px){.x{font:12px/1.5 \"Helvetica Neue\",sans-serif;background:url(a;b.png)}}"
        #expect(CSSFormatter.beautify(css) == """
        /* top */
        a, b>c {
          color: red;
          margin: 0 auto;
        }

        @media (max-width:600px) {
          .x {
            font: 12px/1.5 "Helvetica Neue", sans-serif;
            background: url(a;b.png);
          }
        }

        """)
    }

    @Test func minifies() {
        let css = "/*! keep */\n/* drop */\na , b {\n  color : red ;\n  margin: 0  auto !important;\n}\n"
        #expect(CSSFormatter.minify(css) == "/*! keep */a,b{color:red;margin:0 auto!important}")
    }

    @Test func scssNesting() {
        let scss = "$c: #333;\n.a { color: $c; &:hover { color: #000; } // note\n}"
        #expect(CSSFormatter.beautify(scss) == "$c: #333;\n\n.a {\n  color: $c;\n  &:hover {\n    color: #000;\n  }\n  // note\n}\n")
    }

    @Test func detection() {
        #expect(CSSFormatter.looksLikeCSS("body { margin: 0; }"))
        #expect(!CSSFormatter.looksLikeCSS("function f() { return 1; }"))
        #expect(!CSSFormatter.looksLikeCSS("{\"a\": 1}"))
    }
}

@Suite struct SQLTests {
    @Test func formatsASelect() {
        let sql = "select u.id, u.name, count(o.id) as orders from users u left join orders o on o.user_id = u.id where u.active = true and u.created_at > '2024-01-01' group by u.id, u.name order by orders desc limit 10;"
        #expect(SQLFormatter.format(sql) == """
        SELECT
          u.id,
          u.name,
          COUNT(o.id) AS orders
        FROM users u
        LEFT JOIN orders o
          ON o.user_id = u.id
        WHERE u.active = TRUE
          AND u.created_at > '2024-01-01'
        GROUP BY
          u.id,
          u.name
        ORDER BY
          orders DESC
        LIMIT 10;

        """)
    }

    @Test func subqueriesIndent() {
        let sql = "SELECT * FROM t WHERE id IN (SELECT id FROM u WHERE x BETWEEN 1 AND 2)"
        #expect(SQLFormatter.format(sql, keywordCase: .lower) == """
        select
          *
        from t
        where id in (
          select
            id
          from u
          where x between 1 and 2
        )

        """)
    }

    @Test func minifies() {
        #expect(SQLFormatter.minify("SELECT a ,\n b -- note\nFROM t WHERE x = 'a  b' ;") == "SELECT a,b FROM t WHERE x = 'a  b';")
    }

    @Test func detection() {
        #expect(SQLFormatter.looksLikeSQL("SELECT * FROM users"))
        #expect(SQLFormatter.looksLikeSQL("update t set a = 1"))
        #expect(!SQLFormatter.looksLikeSQL("select the best option from the menu"))
        #expect(!SQLFormatter.looksLikeSQL("Update: the build is green"))
    }
}

@Suite struct CronTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2024-02-28 10:07:30 UTC (a Wednesday, the day before a leap day).
    let start = Date(timeIntervalSince1970: 1_709_114_850)

    func iso(_ dates: [Date]) -> [String] {
        let formatter = ISO8601DateFormatter()
        return dates.map { formatter.string(from: $0) }
    }

    @Test func everyFifteenMinutes() throws {
        let schedule = try Cron.parse("*/15 * * * *")
        #expect(Cron.describe(schedule) == "Every 15 minutes")
        #expect(iso(Cron.nextRuns(of: schedule, after: start, count: 3, calendar: utc)) == ["2024-02-28T10:15:00Z", "2024-02-28T10:30:00Z", "2024-02-28T10:45:00Z"])
    }

    @Test func weekdayMornings() throws {
        let schedule = try Cron.parse("30 9 * * 1-5")
        #expect(Cron.describe(schedule) == "At 09:30, Monday through Friday")
        // Wed 28 Feb → Thu 29 Feb (leap day) → Fri 1 Mar → Mon 4 Mar.
        #expect(iso(Cron.nextRuns(of: schedule, after: start, count: 3, calendar: utc)) == ["2024-02-29T09:30:00Z", "2024-03-01T09:30:00Z", "2024-03-04T09:30:00Z"])
    }

    @Test func leapDayOnly() throws {
        let schedule = try Cron.parse("0 0 29 2 *")
        #expect(iso(Cron.nextRuns(of: schedule, after: start, count: 2, calendar: utc)) == ["2024-02-29T00:00:00Z", "2028-02-29T00:00:00Z"])
    }

    @Test func dayOfMonthOrWeekday() throws {
        // Both restricted: either matches (Vixie cron).
        let schedule = try Cron.parse("0 12 1 * SUN")
        #expect(Cron.describe(schedule) == "At 12:00, on day 1 of the month or on Sunday")
        #expect(iso(Cron.nextRuns(of: schedule, after: start, count: 3, calendar: utc)) == ["2024-03-01T12:00:00Z", "2024-03-03T12:00:00Z", "2024-03-10T12:00:00Z"])
    }

    @Test func macrosNamesAndSeconds() throws {
        #expect(Cron.describe(try Cron.parse("@daily")) == "At 00:00")
        #expect(Cron.describe(try Cron.parse("0 0 1 JAN,JUL *")) == "At 00:00, on day 1 of the month, in January and July")
        #expect(try Cron.parse("0 0 * * 7").weekdays.values == [0])
        let seconds = try Cron.parse("*/10 * * * * *")
        #expect(iso(Cron.nextRuns(of: seconds, after: start, count: 2, calendar: utc)) == ["2024-02-28T10:07:40Z", "2024-02-28T10:07:50Z"])
        #expect(Cron.describe(try Cron.parse("5 0-6 * * *")) == "At minute 5, between 00:00 and 06:59")
    }

    @Test(arguments: ["* * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "5-1 * * * *", "*/0 * * * *", "a * * * *"])
    func invalid(expression: String) {
        #expect(throws: Cron.ParseError.self) { try Cron.parse(expression) }
    }

    @Test func detection() {
        #expect(Cron.looksLikeCron("*/5 * * * *"))
        #expect(Cron.looksLikeCron("@hourly"))
        #expect(!Cron.looksLikeCron("1 2 3 4 5"))
        #expect(!Cron.looksLikeCron("a b c d e"))
    }
}

@Suite struct QRTests {
    @Test(arguments: [QRCode.Correction.low, .high])
    func generatedCodesReadBack(correction: QRCode.Correction) throws {
        let text = "https://example.com/?q=devkit&n=42 ✓"
        let image = try QRCode.generate(text, correction: correction, scale: 8)
        #expect(image.width == image.height)
        #expect(try QRCode.read(image) == [text])
        let png = try #require(QRCode.pngData(image))
        #expect(try QRCode.read(imageData: png) == [text])
    }

    @Test func wifiPayloadEscapes() {
        #expect(QRCode.wifiPayload(ssid: "My;Net", password: "p:a\"ss", security: .wpa, hidden: true) == "WIFI:T:WPA;S:My\\;Net;P:p\\:a\\\"ss;H:true;;")
        #expect(QRCode.wifiPayload(ssid: "Open", password: "x", security: .none, hidden: false) == "WIFI:T:nopass;S:Open;;")
    }

    @Test func notAnImage() {
        #expect(throws: QRCode.QRError.self) { try QRCode.read(imageData: Data("nope".utf8)) }
    }
}

@Suite struct CertificateTests {
    @Test func decodesISRGRootX1() throws {
        let certificate = try #require(try CertificateDecoder.decodeAll(Fixtures.isrgRootX1).first)
        #expect(certificate.sha256Fingerprint == "96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6")
        #expect(certificate.subject == "C=US, O=Internet Security Research Group, CN=ISRG Root X1")
        #expect(certificate.isSelfSigned)
        #expect(certificate.commonName == "ISRG Root X1")
        #expect(certificate.serialNumber == "82:10:CF:B0:D2:40:E3:59:44:63:E0:BB:63:82:8B:00")
        #expect(certificate.version == 3)
        #expect(certificate.signatureAlgorithm == "SHA-256 with RSA")
        #expect(certificate.publicKey == "RSA 4096 bits")
        #expect(certificate.notBefore == Date(timeIntervalSince1970: 1_433_415_878)) // 2015-06-04 11:04:38 UTC
        #expect(certificate.notAfter == Date(timeIntervalSince1970: 2_064_567_878))  // 2035-06-04 11:04:38 UTC
        #expect(certificate.isCA == true)
        #expect(certificate.keyUsage == ["Certificate Sign", "CRL Sign"])
    }

    @Test func decodesECRootAndChains() throws {
        let both = try CertificateDecoder.decodeAll(Fixtures.isrgRootX1 + "\n" + Fixtures.isrgRootX2)
        #expect(both.count == 2)
        #expect(both[1].publicKey == "EC P-384")
        #expect(both[1].signatureAlgorithm == "ECDSA with SHA-384")
        #expect(both[1].sha256Fingerprint == "69:72:9B:8E:15:A8:6E:FC:17:7A:57:AF:B7:17:1D:FC:64:AD:D2:8C:2F:CA:8C:F1:50:7E:34:45:3C:CB:14:70")
    }

    @Test func rejectsGarbage() {
        #expect(throws: CertificateDecoder.DecodeError.self) { try CertificateDecoder.decodeAll("hello") }
        #expect(throws: CertificateDecoder.DecodeError.self) { try CertificateDecoder.decodeAll("-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----") }
    }
}

@Suite struct GZipTests {
    // Check values from the CRC-32 (ISO-HDLC) catalogue and Adler-32's Wikipedia example.
    @Test func checksums() {
        #expect(GZip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(GZip.adler32(Data("Wikipedia".utf8)) == 0x11E6_0398)
    }

    @Test func decodesCLIOutput() throws {
        // `printf hello | gzip -n | base64` and Python's zlib.compress(b"hello").
        let gzip = try GZip.decompress(try Base64.decode("H4sIAAAAAAAAA8tIzcnJBwCGphA2BQAAAA=="))
        #expect(gzip.format == .gzip)
        #expect(String(decoding: gzip.data, as: UTF8.self) == "hello")
        let zlib = try GZip.decompress(try Base64.decode("eJzLSM3JyQcABiwCFQ=="))
        #expect(zlib.format == .zlib)
        #expect(String(decoding: zlib.data, as: UTF8.self) == "hello")
    }

    @Test(arguments: GZip.Format.allCases)
    func roundTrips(format: GZip.Format) throws {
        let text = Data(String(repeating: "Devkit compresses this. ", count: 200).utf8)
        let compressed = try GZip.compress(text, format: format)
        #expect(compressed.count < text.count / 10)
        let result = try GZip.decompress(compressed)
        #expect(result.data == text)
        #expect(result.format == format)
    }

    @Test func damagedDataIsAnError() throws {
        var data = try GZip.compress(Data("hello world".utf8))
        data[data.count - 6] ^= 0xFF // CRC
        #expect(throws: GZip.GZipError.self) { try GZip.decompress(data) }
        #expect(GZip.looksLikeCompressedBase64(Base64.encode(try GZip.compress(Data("some text here".utf8)))))
        #expect(!GZip.looksLikeCompressedBase64("H4sIAAAAAAAAA8tIzcnJBwCGphA2"))
    }
}

@Suite struct JWTPublicKeyTests {
    // RFC 7515 Appendix A.2 (RS256) and A.3 (ES256).
    static let payload = "eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ"
    static let rs256 = "eyJhbGciOiJSUzI1NiJ9." + payload + ".cC4hiUPoj9Eetdgtv3hF80EGrhuB__dzERat0XF9g2VtQgr9PJbu3XOiZj5RZmh7AAuHIm4Bh-0Qc_lF5YKt_O8W2Fp5jujGbds9uJdbF9CUAr7t1dnZcAcQjbKBYNX4BAynRFdiuB--f_nZLgrnbyTyWzO75vRK5h6xBArLIARNPvkSjtQBMHlb1L07Qe7K0GarZRmB_eSN9383LcOLn6_dO--xi12jzDwusC-eOkHWEsqtFZESc6BfI7noOPqvhJ1phCnvWh6IeYI2w9QOYEUipUTI8np6LbgGY9Fs98rqVt5AXLIhWkWywlVmtVrBp0igcN_IoypGlUPQGe77Rw"
    static let rsaJWK = #"{"kty":"RSA","n":"ofgWCuLjybRlzo0tZWJjNiuSfb4p4fAkd_wWJcyQoTbji9k0l8W26mPddxHmfHQp-Vaw-4qPCJrcS2mJPMEzP1Pt0Bm4d4QlL-yRT-SFd2lZS-pCgNMsD1W_YpRPEwOWvG6b32690r2jZ47soMZo9wGzjb_7OMg0LOL-bSf63kpaSHSXndS5z5rexMdbBYUsLA9e-KXBdQOS-UTo7WTBEMa2R2CapHg665xsmtdVMTBQY4uDZlxvb3qCo5ZwKh9kG4LT6_I5IhlJH7aGhyxXFvUK-DWNmoudF8NAco9_h9iaGNj8q2ethFkMLs91kzk2PAcDTW9gb54h4FRWyuXpoQ","e":"AQAB"}"#
    static let es256 = "eyJhbGciOiJFUzI1NiJ9." + payload + ".DtEhU3ljbEg8L38VWAfUAqOyKAM6-Xx-F4GawxaepmXFCgfTjDxw5djxLa8ISlSApmWQxfKTUJqPP3-Kg6NU1Q"
    static let ecJWK = #"{"kty":"EC","crv":"P-256","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0"}"#

    @Test func rs256WithJWK() throws {
        let token = try JWT.decode(Self.rs256)
        #expect(JWT.verify(token, publicKey: Self.rsaJWK) == .verified)
        #expect(JWT.verify(token, publicKey: #"{"keys":[\#(Self.rsaJWK)]}"#) == .verified)
        let key = try JWT.publicKey(from: Self.rsaJWK)
        #expect(key.summary == "RSA 2048 bits")
    }

    @Test func rs256WithPEM() throws {
        // The same key as SPKI PEM, built from the JWK.
        guard case let .rsa(pkcs1) = try JWT.publicKey(from: Self.rsaJWK) else { Issue.record("not RSA"); return }
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let bitString = DERNode.encode(tag: 0x03, [0x00] + [UInt8](pkcs1))
        let spki = Data(DERNode.encode(tag: 0x30, algorithm + bitString))
        let pem = "-----BEGIN PUBLIC KEY-----\n" + spki.base64EncodedString(options: .lineLength64Characters) + "\n-----END PUBLIC KEY-----"
        #expect(JWT.verify(try JWT.decode(Self.rs256), publicKey: pem) == .verified)
        let pkcs1PEM = "-----BEGIN RSA PUBLIC KEY-----\n" + pkcs1.base64EncodedString() + "\n-----END RSA PUBLIC KEY-----"
        #expect(JWT.verify(try JWT.decode(Self.rs256), publicKey: pkcs1PEM) == .verified)
    }

    @Test func es256WithJWK() throws {
        #expect(JWT.verify(try JWT.decode(Self.es256), publicKey: Self.ecJWK) == .verified)
    }

    @Test func tamperedAndWrongKeys() throws {
        var parts = Self.rs256.split(separator: ".").map(String.init)
        parts[1] = Base64.encode(#"{"iss":"mallory"}"#, options: .init(urlSafe: true, padding: false))
        #expect(JWT.verify(try JWT.decode(parts.joined(separator: ".")), publicKey: Self.rsaJWK) == .mismatch)
        if case .badKey = JWT.verify(try JWT.decode(Self.rs256), publicKey: Self.ecJWK) {} else { Issue.record("expected badKey") }
        if case .badKey = JWT.verify(try JWT.decode(Self.es256), publicKey: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----") {} else { Issue.record("expected badKey") }
        #expect(JWT.verify(try JWT.decode(Self.es256), publicKey: "") == .needsSecret)
    }

    @Test func certificateKeys() throws {
        let key = try JWT.publicKey(from: Fixtures.isrgRootX2)
        #expect(key.summary == "EC P-384")
    }
}
