import AppKit
import DevkitCore
import Observation

/// What every tool offers the app: an input, a primary output for Copy Output (⇧⌘C) and
/// Use Output as Input (⌘↩), and a way to receive detected clipboard content.
@MainActor
protocol ToolModel: AnyObject {
    var tool: Tool { get }
    var input: String { get set }
    var editor: EditorHandle { get }
    var primaryOutput: String? { get }
    /// Shown in the HUD after Copy Output, e.g. "Copied SHA-256".
    var primaryOutputName: String { get }
    func receive(_ detection: Detector.Detection)
}

extension ToolModel {
    var primaryOutputName: String { "Output" }
    func receive(_ detection: Detector.Detection) {}
}

/// A labeled value in a results list, with its own copy button.
struct ResultRow: Identifiable, Equatable {
    var label: String
    var value: String
    var note: String? = nil
    var id: String { label }
}

enum SettingsKey {
    static let readClipboardOnOpen = "readClipboardOnOpen"
    static let jsonIndent = "jsonIndent"
    static let jsonSortKeys = "jsonSortKeys"
    static let stackVertically = "stackVertically"
    static let selectedTool = "selectedTool"
}

/// Output shown in a text view is capped so a 50 MB result doesn't stall the UI; Copy
/// Output still copies everything.
enum DisplayLimit {
    static let bytes = 2 * 1024 * 1024

    static func clip(_ text: String) -> (shown: String, clipped: Bool) {
        guard text.utf8.count > bytes else { return (text, false) }
        let utf8 = text.utf8
        var end = utf8.index(utf8.startIndex, offsetBy: bytes)
        // Don't cut a character in half: back up past UTF-8 continuation bytes.
        while end > utf8.startIndex, utf8[end] & 0xC0 == 0x80 {
            end = utf8.index(before: end)
        }
        return (String(decoding: utf8[..<end], as: UTF8.self), true)
    }
}

func formatBytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}

// MARK: - JSON

@MainActor
@Observable
final class JSONToolModel: ToolModel {
    let tool = Tool.json
    let editor = EditorHandle()
    let job = LiveJob()

    var input = "" { didSet { if input != oldValue { update() } } }
    var style = JSONFormatter.Style.pretty { didSet { if style != oldValue { update() } } }
    var indent: JSONFormatter.Indent {
        didSet {
            Diagnostics.defaults.set(indent.rawValue, forKey: SettingsKey.jsonIndent)
            if indent != oldValue { update() }
        }
    }
    var sortKeys: Bool {
        didSet {
            Diagnostics.defaults.set(sortKeys, forKey: SettingsKey.jsonSortKeys)
            if sortKeys != oldValue { update() }
        }
    }

    private(set) var output = ""
    private(set) var shownOutput = ""
    private(set) var isClipped = false
    private(set) var error: JSONError?
    private(set) var warnings: [String] = []
    private(set) var lineCount = 0
    private(set) var styles: [TextStyleRun] = []
    private(set) var stylesVersion = 0

    init() {
        indent = JSONFormatter.Indent(rawValue: Diagnostics.defaults.string(forKey: SettingsKey.jsonIndent) ?? "") ?? .two
        sortKeys = Diagnostics.defaults.bool(forKey: SettingsKey.jsonSortKeys)
    }

    var primaryOutput: String? { output.isEmpty ? nil : output }

    func receive(_ detection: Detector.Detection) {}

    /// Re-reads the default indent (it can change in Settings while the tool is open).
    func reloadSettings() {
        let stored = JSONFormatter.Indent(rawValue: Diagnostics.defaults.string(forKey: SettingsKey.jsonIndent) ?? "") ?? .two
        if stored != indent { indent = stored }
    }

    private struct Computed: Sendable {
        var result: Result<JSONFormatter.Result, JSONError>?
        var spans: [JSONHighlighter.Span]
    }

    private func update() {
        let text = input
        let options = JSONFormatter.Options(style: style, indent: indent, sortKeys: sortKeys)
        guard !isBlank(text) else {
            job.cancel()
            apply(Computed(result: nil, spans: []))
            return
        }
        job.run(background: approximateSize(text) > LiveJob.syncLimit) { isCancelled in
            do {
                let result = try JSONFormatter.format(text, options: options, isCancelled: isCancelled)
                let spans = result.text.utf8.count <= JSONHighlighter.limit ? JSONHighlighter.spans(in: result.text) : []
                return Computed(result: .success(result), spans: spans)
            } catch let error as JSONError {
                return Computed(result: .failure(error), spans: [])
            } catch {
                return Computed(result: nil, spans: [])
            }
        } apply: { [weak self] computed in
            self?.apply(computed)
        }
    }

    private func apply(_ computed: Computed) {
        switch computed.result {
        case let .success(result)?:
            output = result.text
            (shownOutput, isClipped) = DisplayLimit.clip(result.text)
            error = nil
            warnings = result.warnings
            lineCount = result.lineCount
            styles = isClipped ? [] : computed.spans.map { TextStyleRun(range: $0.range, style: Self.style(for: $0.kind)) }
        case let .failure(error)?:
            output = ""
            shownOutput = ""
            isClipped = false
            self.error = error
            warnings = []
            styles = []
        case nil:
            output = ""
            shownOutput = ""
            isClipped = false
            error = nil
            warnings = []
            styles = []
        }
        stylesVersion += 1
    }

    static func style(for kind: JSONHighlighter.Kind) -> TextStyleRun.Style {
        switch kind {
        case .key: .key
        case .string: .string
        case .number: .number
        case .keyword: .keyword
        }
    }
}

// MARK: - Base64

enum CodingMode: String, CaseIterable, Identifiable {
    case encode, decode
    var id: String { rawValue }
    var title: String { self == .encode ? "Encode" : "Decode" }
}

@MainActor
@Observable
final class Base64ToolModel: ToolModel {
    let tool = Tool.base64
    let editor = EditorHandle()
    let job = LiveJob()

    var input = "" { didSet { if input != oldValue { update() } } }
    var mode = CodingMode.encode { didSet { if mode != oldValue { update() } } }
    var urlSafe = false { didSet { update() } }
    var padding = true { didSet { update() } }

    private(set) var output = ""
    private(set) var shownOutput = ""
    private(set) var error: String?
    private(set) var summary = ""
    private(set) var isHexDump = false

    var primaryOutput: String? { output.isEmpty ? nil : output }

    func receive(_ detection: Detector.Detection) {
        if detection.hint == .decode { mode = .decode }
    }

    private struct Computed: Sendable {
        var output = ""
        var error: String?
        var summary = ""
        var isHexDump = false
    }

    private func update() {
        let text = input, mode = mode
        let options = Base64.EncodeOptions(urlSafe: urlSafe, padding: padding)
        guard !text.isEmpty else {
            job.cancel()
            apply(Computed())
            return
        }
        job.run(background: approximateSize(text) > LiveJob.syncLimit) { _ in
            switch mode {
            case .encode:
                let bytes = text.utf8.count
                let encoded = Base64.encode(text, options: options)
                return Computed(output: encoded, summary: "\(formatBytes(bytes)) of UTF-8 text → \(encoded.count.formatted()) characters")
            case .decode:
                do {
                    let decoded = try Base64.decodeText(text)
                    if decoded.text != nil {
                        return Computed(output: decoded.display, summary: "Decoded \(formatBytes(decoded.data.count)) of UTF-8 text")
                    }
                    return Computed(output: decoded.display, summary: "Decoded \(formatBytes(decoded.data.count)). It isn't text, so it's shown as hex.", isHexDump: true)
                } catch {
                    return Computed(error: "\(error)")
                }
            }
        } apply: { [weak self] computed in
            guard let self else { return }
            output = computed.output
            shownOutput = DisplayLimit.clip(computed.output).shown
            error = computed.error
            summary = computed.summary
            isHexDump = computed.isHexDump
        }
    }

    private func apply(_ computed: Computed) {
        output = computed.output
        shownOutput = computed.output
        error = computed.error
        summary = computed.summary
        isHexDump = computed.isHexDump
    }
}

// MARK: - URL

@MainActor
@Observable
final class URLToolModel: ToolModel {
    let tool = Tool.url
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    var mode = CodingMode.encode { didSet { update() } }
    var scope = URLCoding.Scope.component { didSet { update() } }
    var spaceAsPlus = false { didSet { update() } }
    var plusAsSpace = true { didSet { update() } }

    private(set) var output = ""
    private(set) var error: String?

    var primaryOutput: String? { output.isEmpty ? nil : output }

    func receive(_ detection: Detector.Detection) {
        if detection.hint == .decode { mode = .decode }
    }

    private func update() {
        error = nil
        guard !input.isEmpty else { output = ""; return }
        switch mode {
        case .encode:
            output = URLCoding.encode(input, scope: scope, spaceAsPlus: spaceAsPlus)
        case .decode:
            do {
                output = try URLCoding.decode(input, plusAsSpace: plusAsSpace)
            } catch {
                output = ""
                self.error = "\(error)"
            }
        }
    }
}

// MARK: - JWT

@MainActor
@Observable
final class JWTToolModel: ToolModel {
    let tool = Tool.jwt
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    var secret = "" { didSet { verify() } }
    var secretIsBase64 = false { didSet { verify() } }

    private(set) var decoded: JWT.Decoded?
    private(set) var error: String?
    private(set) var verification: JWT.Verification?
    private(set) var secretError: String?
    private(set) var headerStyles: [TextStyleRun] = []
    private(set) var payloadStyles: [TextStyleRun] = []
    private(set) var version = 0

    var primaryOutput: String? { decoded?.payload }
    var primaryOutputName: String { "Payload" }

    var validity: JWT.Validity? {
        decoded.map { JWT.validity(of: $0, now: Diagnostics.now()) }
    }

    private func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { version += 1 }
        guard !trimmed.isEmpty else {
            decoded = nil
            error = nil
            verification = nil
            return
        }
        do {
            let token = try JWT.decode(trimmed)
            decoded = token
            error = nil
            headerStyles = JSONHighlighter.spans(in: token.header).map { TextStyleRun(range: $0.range, style: JSONToolModel.style(for: $0.kind)) }
            payloadStyles = JSONHighlighter.spans(in: token.payload).map { TextStyleRun(range: $0.range, style: JSONToolModel.style(for: $0.kind)) }
        } catch {
            decoded = nil
            self.error = "\(error)"
        }
        verify()
    }

    private func verify() {
        secretError = nil
        guard let decoded else { verification = nil; return }
        let key: Data
        if secretIsBase64 {
            guard secret.isEmpty || (try? Base64.decode(secret)) != nil else {
                secretError = "The secret isn't valid Base64."
                verification = nil
                return
            }
            key = (try? Base64.decode(secret)) ?? Data()
        } else {
            key = Data(secret.utf8)
        }
        verification = JWT.verify(decoded, secret: key)
    }
}

// MARK: - UUID / ULID

enum UUIDMode: String, CaseIterable, Identifiable {
    case generate, inspect
    var id: String { rawValue }
    var title: String { self == .generate ? "Generate" : "Inspect" }
}

@MainActor
@Observable
final class UUIDToolModel: ToolModel {
    let tool = Tool.uuid
    let editor = EditorHandle()

    var mode = UUIDMode.generate
    var kind = IdentifierKind.uuidV4 { didSet { generate() } }
    var count = 1 { didSet { if count != oldValue { generate() } } }
    var uppercase = false { didSet { reformat() } }
    var hyphens = true { didSet { reformat() } }

    var input = "" { didSet { if input != oldValue { inspect() } } }

    private(set) var generated: [String] = []
    private var raw: [[UInt8]] = []
    private(set) var rows: [ResultRow] = []
    private(set) var error: String?
    var selectedRow: String?

    @ObservationIgnored private var generator = IdentifierGenerator(random: SystemRandomNumberGenerator(), now: Diagnostics.now)

    init() {
        generate()
    }

    var generatedText: String { generated.joined(separator: "\n") }

    var primaryOutput: String? {
        switch mode {
        case .generate: generated.isEmpty ? nil : generatedText
        case .inspect: rows.first { $0.id == selectedRow }?.value ?? rows.first { $0.label == "Canonical" }?.value
        }
    }

    var primaryOutputName: String {
        switch mode {
        case .generate: generated.count == 1 ? (kind == .ulid ? "ULID" : "UUID") : "\(generated.count) IDs"
        case .inspect: selectedRow ?? "Canonical"
        }
    }

    func receive(_ detection: Detector.Detection) {
        mode = .inspect
    }

    func generate() {
        let clamped = min(max(count, 1), 1000)
        raw = (0..<clamped).map { _ in
            switch kind {
            case .uuidV4: generator.nextV4()
            case .uuidV7: generator.nextV7()
            case .ulid: generator.nextULID()
            }
        }
        reformat()
    }

    private func reformat() {
        let format = IdentifierFormat(uppercase: uppercase, hyphens: hyphens)
        generated = raw.map { kind == .ulid ? Identifiers.encodeULID($0) : Identifiers.formatUUID($0, format: format) }
    }

    private func inspect() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { rows = []; error = nil; return }
        do {
            rows = try Identifiers.inspect(trimmed).map { ResultRow(label: $0.label, value: $0.value) }
            error = nil
        } catch {
            rows = []
            self.error = "\(error)"
        }
    }
}

// MARK: - Hash

@MainActor
@Observable
final class HashToolModel: ToolModel {
    let tool = Tool.hash
    let editor = EditorHandle()
    let job = LiveJob()

    var input = "" {
        didSet {
            guard input != oldValue else { return }
            if !input.isEmpty { file = nil }
            update()
        }
    }
    var encoding = DigestEncoding.hex { didSet { reformat() } }
    var useHMAC = false { didSet { update() } }
    var hmacKey = "" { didSet { if useHMAC { update() } } }
    var expected = "" { didSet { reformat() } }

    struct HashedFile: Equatable {
        var url: URL
        var size: Int64
        var progress: Double
        var isHashing: Bool
        var error: String?
    }

    private(set) var file: HashedFile?
    private var digests: [HashAlgorithm: [UInt8]] = [:]
    private(set) var rows: [ResultRow] = []
    private(set) var matched: HashAlgorithm?
    var selectedRow: String? = HashAlgorithm.sha256.title
    @ObservationIgnored private var fileTask: Task<Void, Never>?

    var primaryOutput: String? {
        rows.first { $0.id == (selectedRow ?? HashAlgorithm.sha256.title) }?.value
    }

    var primaryOutputName: String { selectedRow ?? HashAlgorithm.sha256.title }

    private var key: Data? { useHMAC && !hmacKey.isEmpty ? Data(hmacKey.utf8) : nil }

    private func update() {
        if let file, input.isEmpty {
            hashFile(file.url)
            return
        }
        let text = input, key = key
        guard !text.isEmpty else {
            job.cancel()
            digests = [:]
            reformat()
            return
        }
        job.run(background: approximateSize(text) > LiveJob.syncLimit) { _ in
            Hashing.digests(of: Data(text.utf8), hmacKey: key)
        } apply: { [weak self] digests in
            self?.digests = digests
            self?.reformat()
        }
    }

    private func reformat() {
        let encoding = encoding
        matched = expected.isEmpty ? nil : Hashing.match(expected, in: digests)
        rows = digests.isEmpty ? [] : HashAlgorithm.allCases.compactMap { algorithm in
            guard let digest = digests[algorithm] else { return nil }
            return ResultRow(label: algorithm.title, value: encoding.encode(digest),
                             note: algorithm.isInsecure ? "Not for security" : nil)
        }
    }

    /// Hashes a file on disk, streamed, with progress. Replaces any text input.
    func hashFile(_ url: URL) {
        fileTask?.cancel()
        job.cancel()
        if !input.isEmpty { input = "" }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        file = HashedFile(url: url, size: size, progress: 0, isHashing: true)
        digests = [:]
        reformat()
        let key = key
        let progress = ProgressBox()
        fileTask = Task { [weak self] in
            let job = Task.detached(priority: .userInitiated) { () -> Result<[HashAlgorithm: [UInt8]], Error> in
                do {
                    var source = try FileChunkSource(url: url)
                    defer { source.close() }
                    return .success(try Hashing.digests(of: &source, hmacKey: key, progress: { progress.value = $0 }, isCancelled: { Task.isCancelled }))
                } catch {
                    return .failure(error)
                }
            }
            // Poll progress a few times a second while hashing (only during the job).
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.file?.progress = progress.value
                }
            }
            let result = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            ticker.cancel()
            guard let self, !Task.isCancelled, file?.url == url else { return }
            switch result {
            case let .success(digests):
                self.digests = digests
                file?.isHashing = false
                file?.progress = 1
            case let .failure(error):
                file?.isHashing = false
                file?.error = error is CancellationError ? nil : "Couldn't read \(url.lastPathComponent). Check that it still exists and you can open it. (\(error.localizedDescription))"
            }
            reformat()
        }
    }

    func cancelFile() {
        fileTask?.cancel()
        fileTask = nil
        file = nil
        digests = [:]
        reformat()
    }
}

/// A progress value shared between the hashing thread and the UI ticker.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0.0
    var value: Double {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

struct FileChunkSource: ChunkSource {
    let handle: FileHandle
    let totalBytes: Int64?

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    mutating func next(maxLength: Int) throws -> Data? {
        guard let data = try handle.read(upToCount: maxLength), !data.isEmpty else { return nil }
        return data
    }

    func close() { try? handle.close() }
}

// MARK: - Unix time

@MainActor
@Observable
final class TimestampToolModel: ToolModel {
    let tool = Tool.timestamp
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    var unit = Timestamps.Unit.automatic { didSet { update() } }

    private(set) var parsed: Timestamps.Parsed?
    private(set) var rows: [ResultRow] = []
    private(set) var error: String?
    var selectedRow: String?

    var primaryOutput: String? {
        if let selectedRow, let row = rows.first(where: { $0.id == selectedRow }) { return row.value }
        return rows.first { $0.label == defaultRow }?.value
    }

    var primaryOutputName: String { selectedRow ?? defaultRow }

    /// Numbers convert to a date, dates convert to a number.
    private var defaultRow: String {
        if case .text? = parsed?.input { return "Unix seconds" }
        return "ISO 8601"
    }

    var detectedUnitDescription: String? {
        guard let parsed else { return nil }
        switch parsed.input {
        case let .number(unit): return "Read as \(unit.title.lowercased())"
        case let .text(format): return "Read as \(format)"
        }
    }

    func setNow() {
        input = String(Int(Diagnostics.now().timeIntervalSince1970))
    }

    func refresh() { update() }

    private func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { parsed = nil; rows = []; error = nil; return }
        do {
            let parsed = try Timestamps.parse(trimmed, unit: unit, now: Diagnostics.now())
            self.parsed = parsed
            rows = Timestamps.rows(for: parsed.date, now: Diagnostics.now()).map { ResultRow(label: $0.label, value: $0.value) }
            error = nil
        } catch {
            parsed = nil
            rows = []
            self.error = "\(error)"
        }
    }
}

// MARK: - Regex

@MainActor
@Observable
final class RegexToolModel: ToolModel {
    let tool = Tool.regex
    let editor = EditorHandle()
    let job = LiveJob()

    var pattern = "" { didSet { if pattern != oldValue { update() } } }
    var flags: RegexTester.Flags = [] { didSet { update() } }
    var input = "" { didSet { if input != oldValue { update() } } }
    var template = "" { didSet { if template != oldValue { update() } } }

    private(set) var matches: [RegexTester.Match] = []
    private(set) var status: Status = .idle
    private(set) var replaced: String?
    private(set) var styles: [TextStyleRun] = []
    private(set) var stylesVersion = 0

    enum Status: Equatable {
        case idle
        case matched(count: Int, truncated: Bool)
        case invalid(String)
        case timedOut
    }

    var primaryOutput: String? {
        if let replaced, !template.isEmpty { return replaced }
        return matches.isEmpty ? nil : matches.map(\.text).joined(separator: "\n")
    }

    var primaryOutputName: String { replaced != nil && !template.isEmpty ? "Replacement" : "Matches" }

    func flag(_ flag: RegexTester.Flags) -> Bool { flags.contains(flag) }

    func setFlag(_ flag: RegexTester.Flags, _ on: Bool) {
        if on { flags.insert(flag) } else { flags.remove(flag) }
    }

    private struct Computed: Sendable {
        var outcome: RegexTester.Outcome
        var replacement: RegexTester.ReplaceOutcome?
    }

    private func update() {
        let pattern = pattern, flags = flags, text = input, template = template
        guard !pattern.isEmpty else {
            job.cancel()
            apply(Computed(outcome: .emptyPattern, replacement: nil))
            return
        }
        // Always off the main thread: even small inputs can backtrack for the full timeout.
        job.run(background: true, debounce: .milliseconds(60)) { isCancelled in
            let outcome = RegexTester.evaluate(pattern: pattern, flags: flags, in: text, isCancelled: isCancelled)
            var replacement: RegexTester.ReplaceOutcome?
            if !template.isEmpty, case .matches = outcome {
                replacement = RegexTester.replace(pattern: pattern, flags: flags, in: text, template: template, isCancelled: isCancelled)
            }
            return Computed(outcome: outcome, replacement: replacement)
        } apply: { [weak self] computed in
            self?.apply(computed)
        }
    }

    private func apply(_ computed: Computed) {
        switch computed.outcome {
        case .emptyPattern:
            matches = []
            status = .idle
        case let .invalidPattern(message):
            matches = []
            status = .invalid(message)
        case let .timedOut(partial):
            matches = partial
            status = .timedOut
        case let .matches(found, truncated):
            matches = found
            status = .matched(count: found.count, truncated: truncated)
        }
        if case let .replaced(text, _)? = computed.replacement {
            replaced = text
        } else {
            replaced = nil
        }
        styles = matches.prefix(5000).map { TextStyleRun(range: $0.range, style: .match($0.index)) }
        stylesVersion += 1
    }
}

// MARK: - Diff

enum DiffLayout: String, CaseIterable, Identifiable {
    case sideBySide, unified
    var id: String { rawValue }
    var title: String { self == .sideBySide ? "Side by Side" : "Unified" }
}

@MainActor
@Observable
final class DiffToolModel: ToolModel {
    let tool = Tool.diff
    let editor = EditorHandle()
    let changedEditor = EditorHandle()
    let job = LiveJob()

    /// The original text.
    var input = "" { didSet { if input != oldValue { update() } } }
    var changed = "" { didSet { if changed != oldValue { update() } } }
    var ignoreWhitespace = false { didSet { update() } }
    var ignoreCase = false { didSet { update() } }
    var layout = DiffLayout.sideBySide

    private(set) var result: TextDiff.Result?
    private(set) var unified = ""
    private(set) var unifiedStyles: [TextStyleRun] = []
    private(set) var version = 0

    var primaryOutput: String? { unified.isEmpty ? nil : unified }
    var primaryOutputName: String { "Unified Diff" }

    func swapSides() {
        let original = input
        input = changed
        changed = original
    }

    private struct Computed: Sendable {
        var result: TextDiff.Result?
        var unified: String
        var styles: [TextStyleRun]
    }

    private func update() {
        let old = input, new = changed
        let options = TextDiff.Options(ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase)
        guard !old.isEmpty || !new.isEmpty else {
            job.cancel()
            apply(Computed(result: nil, unified: "", styles: []))
            return
        }
        job.run(background: approximateSize(old) + approximateSize(new) > 16 * 1024) { _ in
            let result = TextDiff.compare(old, new, options: options)
            let unified = TextDiff.unified(result)
            return Computed(result: result, unified: unified, styles: Self.unifiedStyles(unified))
        } apply: { [weak self] computed in
            self?.apply(computed)
        }
    }

    private func apply(_ computed: Computed) {
        result = computed.result
        unified = computed.unified
        unifiedStyles = computed.styles
        version += 1
    }

    nonisolated static func unifiedStyles(_ text: String) -> [TextStyleRun] {
        var styles: [TextStyleRun] = []
        var location = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.utf16.count
            if line.hasPrefix("@@") {
                styles.append(TextStyleRun(range: NSRange(location: location, length: length), style: .hunkHeader))
            } else if line.hasPrefix("+"), !line.hasPrefix("+++") {
                styles.append(TextStyleRun(range: NSRange(location: location, length: length), style: .added))
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                styles.append(TextStyleRun(range: NSRange(location: location, length: length), style: .removed))
            }
            location += length + 1
        }
        return styles
    }
}

extension TextStyleRun: @unchecked Sendable {}

// MARK: - Color

@MainActor
@Observable
final class ColorToolModel: ToolModel {
    let tool = Tool.color
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    private(set) var color: RGBAColor?
    private(set) var rows: [ResultRow] = []
    private(set) var error: String?
    var selectedRow: String?

    var primaryOutput: String? {
        rows.first { $0.id == (selectedRow ?? "Hex") }?.value
    }

    var primaryOutputName: String { selectedRow ?? "Hex" }

    func setFromPicker(_ nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return }
        let picked = RGBAColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
        let hex = ColorConverter.rows(for: picked)[0].value
        if hex != rows.first?.value { input = hex }
    }

    private func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { color = nil; rows = []; error = nil; return }
        do {
            let color = try ColorConverter.parse(trimmed)
            self.color = color
            rows = ColorConverter.rows(for: color).map { ResultRow(label: $0.label, value: $0.value) }
            error = nil
        } catch {
            color = nil
            rows = []
            self.error = "\(error)"
        }
    }
}

// MARK: - Number base

@MainActor
@Observable
final class NumberBaseToolModel: ToolModel {
    let tool = Tool.numberBase
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    /// 0 means detect from the prefix.
    var inputRadix = 0 { didSet { update() } }
    var customRadix = 36 { didSet { update() } }
    var uppercase = true { didSet { update() } }

    private(set) var value: NumberBase.Value?
    private(set) var rows: [ResultRow] = []
    private(set) var error: String?
    var selectedRow: String?

    var primaryOutput: String? {
        rows.first { $0.id == (selectedRow ?? defaultRow) }?.value
    }

    var primaryOutputName: String { selectedRow ?? defaultRow }

    /// Decimal input copies hex; anything else copies decimal.
    private var defaultRow: String { value?.detectedRadix == 10 ? "Hexadecimal" : "Decimal" }

    private func update() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { value = nil; rows = []; error = nil; return }
        do {
            let value = try NumberBase.parse(trimmed, radix: inputRadix == 0 ? nil : inputRadix)
            self.value = value
            let custom = min(max(customRadix, 2), 36)
            rows = [
                ResultRow(label: "Binary", value: value.string(radix: 2)),
                ResultRow(label: "Octal", value: value.string(radix: 8)),
                ResultRow(label: "Decimal", value: value.string(radix: 10)),
                ResultRow(label: "Hexadecimal", value: value.string(radix: 16, uppercase: uppercase)),
                ResultRow(label: "Base \(custom)", value: value.string(radix: custom, uppercase: uppercase)),
                ResultRow(label: "Bits", value: "\(value.magnitude.bitWidth)"),
            ]
            error = nil
        } catch {
            value = nil
            rows = []
            self.error = "\(error)"
        }
    }
}

// MARK: - Text case

@MainActor
@Observable
final class CaseToolModel: ToolModel {
    let tool = Tool.textCase
    let editor = EditorHandle()

    var input = "" { didSet { if input != oldValue { update() } } }
    private(set) var rows: [ResultRow] = []
    var selectedRow: String?

    var primaryOutput: String? {
        rows.first { $0.id == (selectedRow ?? CaseConverter.Style.camel.title) }?.value
    }

    var primaryOutputName: String { selectedRow ?? CaseConverter.Style.camel.title }

    private func update() {
        guard !input.isEmpty else { rows = []; return }
        let text = approximateSize(input) > 256 * 1024 ? String(input.prefix(256 * 1024)) : input
        rows = CaseConverter.Style.allCases.map { ResultRow(label: $0.title, value: CaseConverter.convert(text, to: $0)) }
    }
}
