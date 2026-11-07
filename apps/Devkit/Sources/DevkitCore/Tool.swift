import Foundation

/// The tools, in default sidebar order (most used first). ⌘1…⌘9 follow this order.
public enum Tool: String, CaseIterable, Identifiable, Sendable, Codable {
    case json, jwt, base64, timestamp, regex, url, urlParser, htmlEntities, backslash, uuid, diff
    case yamlToJSON, jsonToYAML, numberBase, htmlFormat, cssFormat, xmlFormat, sqlFormat
    case lorem, qrCode, stringInspector, jsonToCSV, csvToJSON, hash, textCase, cron, color
    case randomString, svgToCSS, certificate, hexText, lineSort, gzip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .json: "JSON"
        case .jwt: "JWT"
        case .base64: "Base64"
        case .timestamp: "Unix Time"
        case .regex: "Regex"
        case .url: "URL Encode"
        case .urlParser: "URL Parser"
        case .htmlEntities: "HTML Entities"
        case .backslash: "Backslash Escape"
        case .uuid: "UUID and ULID"
        case .diff: "Text Diff"
        case .yamlToJSON: "YAML to JSON"
        case .jsonToYAML: "JSON to YAML"
        case .numberBase: "Number Base"
        case .htmlFormat: "HTML Format"
        case .cssFormat: "CSS Format"
        case .xmlFormat: "XML Format"
        case .sqlFormat: "SQL Format"
        case .lorem: "Lorem Ipsum"
        case .qrCode: "QR Code"
        case .stringInspector: "String Inspector"
        case .jsonToCSV: "JSON to CSV"
        case .csvToJSON: "CSV to JSON"
        case .hash: "Hash"
        case .textCase: "Text Case"
        case .cron: "Cron"
        case .color: "Color"
        case .randomString: "Random String"
        case .svgToCSS: "SVG to CSS"
        case .certificate: "Certificate"
        case .hexText: "Hex and Text"
        case .lineSort: "Sort Lines"
        case .gzip: "GZip"
        }
    }

    /// One line under the title in the window's toolbar.
    public var subtitle: String {
        switch self {
        case .json: "Format, validate and minify"
        case .jwt: "Decode tokens and check signatures"
        case .base64: "Encode and decode"
        case .timestamp: "Timestamps to dates and back"
        case .regex: "Test patterns and replacements"
        case .url: "Percent-encode and decode"
        case .urlParser: "Split a URL and its query string"
        case .htmlEntities: "Escape and unescape HTML"
        case .backslash: "Escape and unescape string literals"
        case .uuid: "Generate and inspect"
        case .diff: "Compare two texts line by line"
        case .yamlToJSON: "Convert YAML documents to JSON"
        case .jsonToYAML: "Convert JSON to YAML"
        case .numberBase: "Binary, octal, decimal, hex"
        case .htmlFormat: "Beautify and minify HTML"
        case .cssFormat: "Beautify and minify CSS, SCSS and LESS"
        case .xmlFormat: "Validate, beautify and minify XML"
        case .sqlFormat: "Format and minify SQL"
        case .lorem: "Placeholder text"
        case .qrCode: "Make and read QR codes"
        case .stringInspector: "Count and inspect characters"
        case .jsonToCSV: "Arrays of objects to a table"
        case .csvToJSON: "Tables to JSON"
        case .hash: "MD5, SHA-1 and SHA-2 for text or files"
        case .textCase: "camelCase, snake_case and more"
        case .cron: "Explain schedules and list next runs"
        case .color: "Hex, RGB, HSL and code"
        case .randomString: "Passwords, keys and tokens"
        case .svgToCSS: "SVG to a CSS data URI"
        case .certificate: "Decode X.509 certificates"
        case .hexText: "Bytes as hex and back"
        case .lineSort: "Sort, dedupe and tidy lines"
        case .gzip: "Compress and decompress"
        }
    }

    /// SF Symbol for the sidebar (app UI only; never in the app icon).
    public var symbol: String {
        switch self {
        case .json: "curlybraces"
        case .jwt: "key"
        case .base64: "character.textbox"
        case .timestamp: "clock"
        case .regex: "text.magnifyingglass"
        case .url: "percent"
        case .urlParser: "link"
        case .htmlEntities: "number"
        case .backslash: "arrow.left.and.right.text.vertical"
        case .uuid: "barcode"
        case .diff: "plus.forwardslash.minus"
        case .yamlToJSON, .jsonToYAML, .jsonToCSV, .csvToJSON: "arrow.left.arrow.right"
        case .numberBase: "01.square"
        case .htmlFormat: "chevron.left.forwardslash.chevron.right"
        case .cssFormat: "paintbrush"
        case .xmlFormat: "chevron.left.slash.chevron.right"
        case .sqlFormat: "cylinder.split.1x2"
        case .lorem: "text.alignleft"
        case .qrCode: "qrcode"
        case .stringInspector: "character.magnify"
        case .hash: "number.square"
        case .textCase: "textformat"
        case .cron: "calendar.badge.clock"
        case .color: "paintpalette"
        case .randomString: "dice"
        case .svgToCSS: "photo.artframe"
        case .certificate: "checkmark.seal"
        case .hexText: "h.square"
        case .lineSort: "arrow.up.arrow.down"
        case .gzip: "doc.zipper"
        }
    }

    /// Extra words the sidebar filter matches.
    public var keywords: [String] {
        switch self {
        case .json: ["format", "pretty", "minify", "validate", "beautify", "lint"]
        case .jwt: ["token", "jws", "bearer", "claims", "hmac", "rsa", "ecdsa", "debugger", "verify"]
        case .base64: ["b64", "decode", "encode", "base64url"]
        case .timestamp: ["epoch", "unix", "date", "time", "iso", "8601", "rfc 2822"]
        case .regex: ["regular expression", "regexp", "pattern", "match", "replace"]
        case .url: ["percent", "encode", "decode", "uri", "escape"]
        case .urlParser: ["query", "query string", "parameters", "host", "path", "uri"]
        case .htmlEntities: ["entity", "escape", "unescape", "amp", "encode", "decode"]
        case .backslash: ["escape", "unescape", "string", "literal", "quote", "newline"]
        case .uuid: ["guid", "ulid", "random", "id", "generate", "decode"]
        case .diff: ["compare", "difference", "changes"]
        case .yamlToJSON, .jsonToYAML: ["yaml", "yml", "convert", "json"]
        case .numberBase: ["binary", "hex", "octal", "decimal", "radix", "base"]
        case .htmlFormat: ["html", "beautify", "minify", "pretty", "indent"]
        case .cssFormat: ["css", "scss", "less", "sass", "beautify", "minify", "stylesheet"]
        case .xmlFormat: ["xml", "plist", "svg", "beautify", "minify", "validate"]
        case .sqlFormat: ["sql", "query", "beautify", "minify", "postgres", "mysql"]
        case .lorem: ["lorem", "ipsum", "placeholder", "dummy", "text", "generate"]
        case .qrCode: ["qr", "barcode", "scan", "read", "generate", "wifi"]
        case .stringInspector: ["count", "characters", "words", "length", "unicode", "bytes", "inspect"]
        case .jsonToCSV, .csvToJSON: ["csv", "tsv", "spreadsheet", "table", "convert", "json"]
        case .hash: ["md5", "sha", "sha1", "sha256", "sha512", "checksum", "digest", "hmac"]
        case .textCase: ["camel", "snake", "kebab", "pascal", "upper", "lower", "title", "case"]
        case .cron: ["crontab", "schedule", "job", "parser"]
        case .color: ["hex", "rgb", "hsl", "hsb", "colour", "css", "contrast"]
        case .randomString: ["password", "random", "token", "key", "generate", "secret"]
        case .svgToCSS: ["svg", "css", "data uri", "background"]
        case .certificate: ["x509", "x.509", "pem", "ssl", "tls", "cert", "decoder"]
        case .hexText: ["hex", "ascii", "bytes", "text", "convert"]
        case .lineSort: ["sort", "dedupe", "duplicates", "unique", "lines", "shuffle", "reverse"]
        case .gzip: ["gzip", "zlib", "deflate", "compress", "decompress", "inflate"]
        }
    }

    public func matches(filter: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
            || subtitle.lowercased().contains(query)
    }
}
