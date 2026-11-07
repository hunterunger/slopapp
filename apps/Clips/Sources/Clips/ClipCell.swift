import AppKit
import ClipsCore
import SlopKit

/// One clip in a table. `.compact` (panel): icon, title, pin, age, ⌘-number on one line.
/// `.detailed` (History window): icon, title over "app · age", pin.
/// Words matching the search are bold in the title.
final class ClipCellView: NSTableCellView {
    enum Style { case compact, detailed }

    private let style: Style
    private let icon = NSImageView()
    private let swatch = NSView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private let age = NSTextField(labelWithString: "")
    private let number = NSTextField(labelWithString: "")
    private var clipID: UUID?
    private var showsSymbol = false
    private var titleText = ""
    private var highlights: [NSRange] = []
    private var subtitleText = ""
    private var subtitleHighlights: [NSRange] = []

    private static let bodyFont = NSFont.preferredFont(forTextStyle: .body)
    private static let boldFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
    private static let captionFont = NSFont.preferredFont(forTextStyle: .caption1)
    private static let boldCaptionFont = NSFontManager.shared.convert(captionFont, toHaveTrait: .boldFontMask)
    private static let oneLine: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        let iconSize: CGFloat = style == .compact ? 20 : 24
        icon.imageScaling = .scaleProportionallyUpOrDown
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = Radius.xs
        swatch.layer?.borderWidth = 0.5
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.usesSingleLineMode = true
        title.cell?.truncatesLastVisibleLine = true
        title.font = Self.bodyFont
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.usesSingleLineMode = true
        subtitle.font = Self.captionFont
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        pin.symbolConfiguration = .init(textStyle: .caption1)
        age.font = Self.captionFont
        age.alignment = .right
        number.font = .monospacedDigitSystemFont(ofSize: Self.captionFont.pointSize, weight: .regular)
        number.alignment = .right
        let views: [NSView] = style == .compact ? [icon, swatch, title, pin, age, number] : [icon, swatch, title, subtitle, pin]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        var constraints = [
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xs),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            swatch.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            swatch.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: iconSize - 4),
            swatch.heightAnchor.constraint(equalToConstant: iconSize - 4),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Spacing.s),
            pin.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: Spacing.xs),
            pin.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        switch style {
        case .compact:
            constraints += [
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
                age.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: Spacing.xs),
                age.centerYAnchor.constraint(equalTo: centerYAnchor),
                number.leadingAnchor.constraint(equalTo: age.trailingAnchor, constant: Spacing.xs),
                number.widthAnchor.constraint(equalToConstant: 26),
                number.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xs),
                number.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            age.setContentHuggingPriority(.required, for: .horizontal)
            age.setContentCompressionResistancePriority(.required, for: .horizontal)
        case .detailed:
            constraints += [
                title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
                subtitle.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
                subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                subtitle.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -Spacing.xs),
                pin.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xs),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        pin.setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    func configure(clip: Clip, number: Int?, now: Date, query: String) {
        clipID = clip.id
        titleText = ClipText.title(of: clip, limit: 120)
        subtitleText = [clip.sourceName, ClipText.ageSentence(of: clip.lastUsed, now: now)]
            .compactMap { $0 }.joined(separator: " · ")
        // A match deep in the text: show the words around it (instead of the title in the
        // one-line panel row, under the title in History).
        if !query.isEmpty, clip.kind != .image,
           let snippet = ClipText.snippet(in: clip.searchableText, query: query, visibleLength: style == .compact ? 34 : 44,
                                             before: style == .compact ? 10 : 24) {
            if style == .compact { titleText = snippet } else { subtitleText = snippet }
        }
        highlights = SearchText.highlights(in: titleText, query: query)
        subtitleHighlights = style == .detailed ? SearchText.highlights(in: subtitleText, query: query) : []
        let ageText = ClipText.age(of: clip.lastUsed, now: now)
        age.stringValue = ageText
        self.number.stringValue = number.map { "⌘\($0)" } ?? ""
        pin.isHidden = !clip.isPinned
        swatch.isHidden = true
        icon.isHidden = false
        icon.contentTintColor = nil
        showsSymbol = false

        switch clip.kind {
        case .image:
            if let cached = ImageCache.shared.cachedThumbnail(for: clip.id) {
                icon.image = cached
            } else {
                setSymbol(clip.kind.systemImage)
                Task { [weak self] in
                    guard let image = await ImageCache.shared.thumbnail(for: clip), self?.clipID == clip.id else { return }
                    self?.icon.image = image
                    self?.showsSymbol = false
                    self?.applyColors()
                }
            }
        case .color:
            if let color = ColorValue(hex: clip.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                icon.isHidden = true
                swatch.isHidden = false
                swatch.layer?.backgroundColor = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            } else {
                setSymbol(clip.kind.systemImage)
            }
        case .file:
            if let path = clip.filePaths.first { icon.image = AppIcons.icon(forFile: path) } else { setSymbol("doc") }
        case .text, .link:
            if let id = clip.sourceBundleID, let appIcon = AppIcons.icon(for: id) {
                icon.image = appIcon
            } else {
                setSymbol(clip.kind.systemImage)
            }
        }

        var spoken = [clip.kind.spokenName, titleText]
        if clip.isPinned { spoken.append("pinned") }
        if let source = clip.sourceName { spoken.append("from \(source)") }
        spoken.append(ageText)
        if let number { spoken.append("Command \(number)") }
        setAccessibilityLabel(spoken.joined(separator: ", "))
        applyColors()
    }

    private func setSymbol(_ name: String) {
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        showsSymbol = true
    }

    private func applyColors() {
        let selected = backgroundStyle == .emphasized
        let primary: NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
        if highlights.isEmpty {
            title.stringValue = titleText
            title.textColor = primary
        } else {
            let attributed = NSMutableAttributedString(string: titleText, attributes: [.font: Self.bodyFont, .foregroundColor: primary, .paragraphStyle: Self.oneLine])
            for range in highlights where NSMaxRange(range) <= attributed.length {
                attributed.addAttribute(.font, value: Self.boldFont, range: range)
            }
            title.attributedStringValue = attributed
        }
        let secondary: NSColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        age.textColor = secondary
        let sub = NSMutableAttributedString(string: subtitleText, attributes: [.font: Self.captionFont, .foregroundColor: secondary, .paragraphStyle: Self.oneLine])
        for range in subtitleHighlights where NSMaxRange(range) <= sub.length {
            sub.addAttributes([.font: Self.boldCaptionFont, .foregroundColor: primary], range: range)
        }
        subtitle.attributedStringValue = sub
        number.textColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.7) : .tertiaryLabelColor
        pin.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        if showsSymbol { icon.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor }
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
