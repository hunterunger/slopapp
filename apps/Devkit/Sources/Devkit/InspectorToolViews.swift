import DevkitCore
import SlopKit
import SwiftUI

// Richer tools: JWT, Regex and Text Diff.

struct JWTToolView: View {
    @Bindable var model: JWTToolModel
    let app: AppModel
    @AppStorage("jwtPayloadFraction") private var payloadFraction = 0.45

    var body: some View {
        VStack(spacing: 0) {
            NoteBar("Decoding doesn't check the signature: add the secret or public key under the claims to verify it.")
            SplitPanes {
                Pane("Token", accessory: { InputActions(app: app) }) {
                    CodeTextView(text: $model.input,
                                 placeholder: "Paste a JWT (header.payload.signature), or press ⇧⌘V to paste and detect. Nothing leaves your Mac.",
                                 accessibilityLabel: "JWT", handle: model.editor)
                }
            } second: {
                decoded
            }
            status
        }
    }

    @ViewBuilder private var decoded: some View {
        if let token = model.decoded {
            VStack(spacing: 0) {
                Pane("Header", accessory: {
                    CopyButton(label: "Header") { app.copy(token.header, name: "Header") }
                }) {
                    CodeTextView(text: .constant(token.header), isEditable: false, accessibilityLabel: "Header",
                                 styles: model.headerStyles, stylesVersion: model.version)
                }
                .frame(minHeight: 100, idealHeight: headerHeight(token), maxHeight: headerHeight(token))
                SplitStack(axis: .vertical, fraction: $payloadFraction, minimum: 110, accessibilityLabel: "Payload and claims divider") {
                    Pane("Payload", accessory: {
                        CopyButton(label: "Payload") { app.copy(token.payload, name: "Payload") }
                    }) {
                        CodeTextView(text: .constant(token.payload), isEditable: false, accessibilityLabel: "Payload",
                                     styles: model.payloadStyles, stylesVersion: model.version)
                    }
                } second: {
                    Pane("Claims and Signature") {
                        ClaimsView(model: model, token: token)
                    }
                }
            }
        } else {
            Pane("Decoded") {
                EmptyResults(symbol: "key", title: "No Token",
                             message: "The header, payload, dates and signature check appear here.",
                             actionTitle: "Paste and Detect") { app.pasteAndDetect() }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let error = model.error {
            StatusLine(kind: .error, text: error)
        } else if let validity = model.validity {
            switch validity {
            case let .expired(date):
                StatusLine(kind: .warning, text: "Expired \(Timestamps.relative(date, now: Diagnostics.now()))", hint: "⇧⌘C copies the payload")
            case let .notYetValid(date):
                StatusLine(kind: .warning, text: "Not valid until \(date.formatted(date: .abbreviated, time: .standard)) (\(Timestamps.relative(date, now: Diagnostics.now())))", hint: "⇧⌘C copies the payload")
            case let .valid(until):
                StatusLine(kind: .success, text: "Not expired. Expires \(Timestamps.relative(until, now: Diagnostics.now()))", hint: "⇧⌘C copies the payload")
            case .noExpiry:
                StatusLine(kind: .info, text: "This token has no expiry (exp) claim.", hint: "⇧⌘C copies the payload")
            }
        } else {
            StatusLine(kind: .info, text: "")
        }
    }
}

/// Header JSON is short: size its pane to the lines it has (within limits).
private func headerHeight(_ token: JWT.Decoded) -> CGFloat {
    let lines = token.header.split(separator: "\n", omittingEmptySubsequences: false).count
    return min(200, 30 + 18 + CGFloat(lines) * 17)
}

struct ClaimsView: View {
    @Bindable var model: JWTToolModel
    let token: JWT.Decoded

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                    ForEach(token.claims) { claim in
                        GridRow {
                            Text(claim.meaning)
                                .foregroundStyle(.secondary)
                                .help(claim.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(claim.value)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                if let date = claim.date {
                                    Text("\(date.formatted(date: .abbreviated, time: .standard)), \(Timestamps.relative(date, now: Diagnostics.now()))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    GridRow {
                        Text("Algorithm").foregroundStyle(.secondary)
                        Text(token.algorithm ?? "Not set").font(.body.monospaced())
                    }
                }
                if token.claims.isEmpty {
                    Text("No registered claims (iss, sub, aud, exp, nbf, iat, jti).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Hairline()
                if token.algorithm?.hasPrefix("HS") == true {
                    HStack(spacing: Spacing.s) {
                        CodeField(text: $model.secret, placeholder: "Secret, to check the signature", accessibilityLabel: "Secret")
                        Toggle("Base64", isOn: $model.secretIsBase64)
                            .help("The secret is Base64 or base64url encoded")
                            .accessibilityLabel("Secret is Base64")
                    }
                } else if JWT.isAsymmetric(token.algorithm) {
                    verification
                        .font(.callout)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Public key")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        CodeTextView(text: $model.publicKey,
                                     placeholder: "PEM (-----BEGIN PUBLIC KEY-----), a certificate, a JWK or a JWK Set",
                                     accessibilityLabel: "Public key", handle: model.publicKeyEditor)
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    }
                }
                if !JWT.isAsymmetric(token.algorithm) {
                    verification
                        .font(.callout)
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var verification: some View {
        if let error = model.secretError {
            Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.textRed)
        } else {
            switch model.verification {
            case .verified?:
                Label("Signature verified", systemImage: "checkmark.seal.fill").foregroundStyle(.textGreen)
            case .mismatch?:
                Label(JWT.isAsymmetric(token.algorithm) ? "The signature doesn't match this key" : "The signature doesn't match this secret",
                      systemImage: "xmark.seal.fill").foregroundStyle(.textRed)
            case let .badKey(reason)?:
                Label(reason, systemImage: "key.slash").foregroundStyle(.textOrange)
            case .unsigned?:
                Label("Unsigned token (alg: none). Anyone could have written it.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.textOrange)
            case let .unsupported(algorithm)?:
                Text("\(algorithm) signatures can't be checked here. Supported: HS, RS, PS and ES (256/384/512).")
                    .foregroundStyle(.secondary)
            case .needsSecret?, nil:
                Text(JWT.isAsymmetric(token.algorithm)
                     ? "Paste the public key to check the signature. It stays on this Mac."
                     : "Type the secret to check the signature. It stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RegexToolView: View {
    @Bindable var model: RegexToolModel
    let app: AppModel
    @AppStorage("regexMatchesFraction") private var matchesFraction = 0.55

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Text("/").foregroundStyle(.secondary).font(.title3.monospaced()).accessibilityHidden(true)
                    CodeField(text: $model.pattern, placeholder: "Regular expression, e.g. (\\w+)@(\\w+)\\.com",
                              accessibilityLabel: "Pattern", size: .large, focusOnAppear: model.pattern.isEmpty)
                        .frame(height: 30)
                    Text("/").foregroundStyle(.secondary).font(.title3.monospaced()).accessibilityHidden(true)
                }
                // One line per flag; a narrow window scrolls the row rather than wrapping labels.
                ScrollView(.horizontal) {
                HStack(spacing: Spacing.l) {
                    Toggle("Ignore case", isOn: flag(.caseInsensitive))
                        .help("i: letters match either case")
                    Toggle("^ and $ match lines", isOn: flag(.multiline))
                        .help("m: anchors match at every line break")
                    Toggle(". matches newlines", isOn: flag(.dotAll))
                        .help("s: the dot also matches line breaks")
                    Toggle("Allow comments", isOn: flag(.extended))
                        .help("x: whitespace in the pattern is ignored and # starts a comment")
                    if model.job.isBusy {
                        ProgressView().controlSize(.small).accessibilityLabel("Working")
                    }
                }
                .lineLimit(1)
                .fixedSize()
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.m)
            Hairline()
            SplitPanes {
                Pane("Test Text", accessory: { InputActions(app: app) }) {
                    InputEditor(text: $model.input, placeholder: "Type or paste text to test the pattern against. Matches are highlighted.",
                                accessibilityLabel: "Test text", handle: model.editor,
                                styles: model.styles, stylesVersion: model.stylesVersion) { app.clearInput() }
                }
            } second: {
                SplitStack(axis: .vertical, fraction: $matchesFraction, minimum: 120, accessibilityLabel: "Matches and replace divider") {
                    Pane(matchesTitle) {
                        MatchesList(matches: model.matches) { app.copy($0, name: "Match") }
                    }
                } second: {
                    Pane("Replace", accessory: {
                        CopyButton(label: "Result") { if let text = model.replaced { app.copy(text, name: "Result") } }
                            .disabled(model.replaced == nil)
                    }) {
                        VStack(spacing: 0) {
                            CodeField(text: $model.template, placeholder: "Replacement, e.g. $2:$1 or ${name}",
                                      accessibilityLabel: "Replacement template")
                                .padding(Spacing.s)
                            Hairline()
                            CodeTextView(text: .constant(model.template.isEmpty ? "" : (model.replaced ?? "")), isEditable: false,
                                         placeholder: model.template.isEmpty ? "Type a replacement to preview the result." : "",
                                         accessibilityLabel: "Replacement result")
                        }
                    }
                }
            }
            status
        }
    }

    private var matchesTitle: String {
        if case let .matched(count, truncated) = model.status {
            return truncated ? "Matches (first \(count.formatted()))" : "Matches (\(count.formatted()))"
        }
        return "Matches"
    }

    private func flag(_ flag: RegexTester.Flags) -> Binding<Bool> {
        Binding(get: { model.flag(flag) }, set: { model.setFlag(flag, $0) })
    }

    @ViewBuilder private var status: some View {
        let engine = "ICU syntax, as in Swift and Objective-C (close to PCRE; a few differences from JavaScript)"
        switch model.status {
        case .idle:
            StatusLine(kind: .info, text: "", hint: engine)
        case let .invalid(message):
            StatusLine(kind: .error, text: message, hint: engine)
        case .timedOut:
            StatusLine(kind: .warning, text: "Stopped after half a second: this pattern backtracks too much. Nested quantifiers like (a+)+ are the usual cause; try possessive (a++) or atomic (?>a+) groups.")
        case let .matched(count, truncated):
            if count == 0 {
                StatusLine(kind: .info, text: "No matches", hint: engine)
            } else {
                StatusLine(kind: .success, text: truncated ? "Showing the first \(count.formatted()) matches" : "\(count.formatted()) \(count == 1 ? "match" : "matches")", hint: "⇧⌘C copies \(model.primaryOutputName.lowercased())")
            }
        }
    }
}

struct MatchesList: View {
    let matches: [RegexTester.Match]
    let copy: (String) -> Void

    var body: some View {
        if matches.isEmpty {
            EmptyResults(symbol: "text.magnifyingglass", title: "No Matches", message: "Matches and their groups appear here.")
        } else {
            List {
                ForEach(matches.prefix(1000)) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(match.index)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, alignment: .trailing)
                            Text(match.text.isEmpty ? "(empty)" : match.text)
                                .font(.body.monospaced())
                                .foregroundStyle(match.text.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                            Spacer(minLength: Spacing.s)
                            Text("\(match.range.location)–\(match.range.location + match.range.length)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help("Position in UTF-16 code units")
                            CopyButton(label: "Match \(match.index)") { copy(match.text) }
                        }
                        ForEach(match.groups, id: \.index) { group in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                Text(group.name.map { "\(group.index) \($0)" } ?? "\(group.index)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 60, alignment: .trailing)
                                Text(group.text ?? "no match")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(group.text == nil ? .secondary : .primary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .paneListRow()
                    .accessibilityElement(children: .combine)
                }
            }
            .paneList()
        }
    }
}

struct DiffToolView: View {
    @Bindable var model: DiffToolModel
    let app: AppModel
    @AppStorage("diffInputsFraction") private var inputsFraction = 0.4
    @AppStorage("diffSidesFraction") private var sidesFraction = 0.5

    var body: some View {
        VStack(spacing: 0) {
            OptionsBar(isBusy: model.job.isBusy) {
                Picker("Layout", selection: $model.layout) {
                    ForEach(DiffLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Layout")
                Toggle("Ignore whitespace", isOn: $model.ignoreWhitespace)
                Toggle("Ignore case", isOn: $model.ignoreCase)
                Button("Swap") { model.swapSides() }
                    .help("Swap the original and changed text")
            }
            SplitStack(axis: .vertical, fraction: $inputsFraction, minimum: 120, accessibilityLabel: "Texts and differences divider") {
                SplitStack(axis: .horizontal, fraction: $sidesFraction, minimum: 200, accessibilityLabel: "Original and changed divider") {
                    Pane("Original", accessory: { InputActions(app: app) }) {
                        InputEditor(text: $model.input, placeholder: "Paste the original text.",
                                    accessibilityLabel: "Original text", handle: model.editor) { model.input = "" }
                    }
                } second: {
                    Pane("Changed") {
                        InputEditor(text: $model.changed, placeholder: "Paste the changed text.",
                                    accessibilityLabel: "Changed text", handle: model.changedEditor) { model.changed = "" }
                    }
                }
            } second: {
                Pane("Differences", accessory: {
                    CopyButton(label: "Unified Diff") { app.copyOutput() }.disabled(model.unified.isEmpty)
                }) {
                    result
                }
            }
            status
        }
    }

    @ViewBuilder private var result: some View {
        if let result = model.result, !result.isIdentical {
            switch model.layout {
            case .sideBySide:
                SideBySideDiff(result: result)
            case .unified:
                CodeTextView(text: .constant(model.unified), isEditable: false, accessibilityLabel: "Unified diff",
                             styles: model.unifiedStyles, stylesVersion: model.version, wraps: false)
            }
        } else if model.result != nil {
            EmptyResults(symbol: "equal.circle", title: "No Differences", message: "The two texts are the same.")
        } else {
            EmptyResults(symbol: "plus.forwardslash.minus", title: "Nothing to Compare",
                         message: "Paste text into both sides to see what changed.")
        }
    }

    @ViewBuilder private var status: some View {
        if let result = model.result {
            if result.isIdentical {
                StatusLine(kind: .success, text: "No differences" + (model.ignoreWhitespace || model.ignoreCase ? " (with the ignore options)" : ""))
            } else {
                StatusLine(kind: .info, text: "\(result.added.formatted()) added, \(result.removed.formatted()) removed",
                           hint: "⇧⌘C copies a unified diff")
            }
        } else {
            StatusLine(kind: .info, text: "")
        }
    }
}

struct SideBySideDiff: View {
    let result: TextDiff.Result

    var body: some View {
        GeometryReader { proxy in
            let half = max(320, (proxy.size.width - 1) / 2)
            let oldWidth = max(half, columnWidth(\.oldText))
            let newWidth = max(half, columnWidth(\.newText))
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.rows) { row in
                        HStack(spacing: 0) {
                            side(number: row.oldLine, text: row.oldText, highlights: row.oldHighlights,
                                 tint: row.kind == .removed || row.kind == .changed ? .red : nil, width: oldWidth)
                            Hairline(axis: .vertical)
                            side(number: row.newLine, text: row.newText, highlights: row.newHighlights,
                                 tint: row.kind == .added || row.kind == .changed ? .green : nil, width: newWidth)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityText(row))
                    }
                }
                .padding(.vertical, Spacing.xs)
                .frame(minWidth: proxy.size.width, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Wide enough for the longest line on that side (monospaced, so characters × advance).
    private func columnWidth(_ text: KeyPath<TextDiff.Row, String?>) -> CGFloat {
        let longest = result.rows.reduce(0) { max($0, $1[keyPath: text]?.count ?? 0) }
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        return 40 + Spacing.s + CGFloat(longest) * advance + Spacing.l
    }

    private func side(number: Int?, text: String?, highlights: [NSRange], tint: Color?, width: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(number.map(String.init) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(attributed(text ?? "", highlights: highlights, tint: tint))
                .font(.body.monospaced())
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .frame(width: width, alignment: .leading)
        .background(text == nil ? Color.secondary.opacity(0.06) : (tint?.opacity(0.14) ?? .clear))
    }

    private func attributed(_ text: String, highlights: [NSRange], tint: Color?) -> AttributedString {
        var string = AttributedString(text)
        guard let tint else { return string }
        let ns = text as NSString
        for range in highlights where range.location + range.length <= ns.length {
            guard let swiftRange = Range(range, in: text),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: string),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: string) else { continue }
            string[lower..<upper].backgroundColor = tint.opacity(0.35)
        }
        return string
    }

    private func accessibilityText(_ row: TextDiff.Row) -> String {
        switch row.kind {
        case .same: "Unchanged line \(row.oldLine ?? 0): \(row.oldText ?? "")"
        case .removed: "Removed line \(row.oldLine ?? 0): \(row.oldText ?? "")"
        case .added: "Added line \(row.newLine ?? 0): \(row.newText ?? "")"
        case .changed: "Changed line \(row.oldLine ?? 0) from \(row.oldText ?? "") to \(row.newText ?? "")"
        }
    }
}
