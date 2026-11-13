import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// One clip in the panel's strip: a header (kind, age, source app icon) over a big preview
/// of the content, with a small line at the foot. AppKit with manual layout, so the strip
/// can reuse a dozen of these for any number of clips.
///
/// The look: a white (content-background) card with a soft shadow; a header band in the
/// source app's colour with white type (`HeaderColor` keeps it readable) and the app's icon,
/// large and cropped by the card's corner; an accent ring with a small gap when selected.
final class ClipCardView: NSView, NSDraggingSource {
    static let size = PanelMetrics.cardSize
    static let headerHeight: CGFloat = 44
    /// The app icon in the header: large, reaching past the card's top and right edges so the
    /// card's corner crops it.
    static let appIconSize: CGFloat = 44
    static let appIconOverhang = CGSize(width: 4, height: 2)
    nonisolated static let ringWidth: CGFloat = 3
    nonisolated static let ringGap: CGFloat = 2
    /// How far the selection ring reaches outside the card.
    nonisolated static var ringOutset: CGFloat { ringGap + ringWidth }
    /// Text and icons inside the card sit this far from its edges.
    static let padding = Spacing.m
    /// The foot row (character count, size chip, ⌘-number badge): its height and its gap to
    /// the card's bottom edge. Everything in it shares one centre line.
    static let footRowHeight: CGFloat = 18
    static let footRowInset: CGFloat = 6
    static var footerHeight: CGFloat { footRowHeight + footRowInset }

    /// Set by the strip, concentric with the panel's corner. The selection ring and the
    /// ⌘-number badge in the corner follow it.
    var cornerRadius: CGFloat = Radius.m {
        didSet {
            guard cornerRadius != oldValue else { return }
            applyCornerRadius()
            needsLayout = true
        }
    }

    weak var strip: ClipStripView?
    private(set) var index = 0
    private(set) var clip: Clip?

    // Structure: the ring sits outside the clipped content.
    private let ring = CALayer()
    private let content = FlippedView()
    private let header = FlippedView()
    private let kindLabel = NSTextField(labelWithString: "")
    private let ageLabel = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private let appIcon = NSImageView()
    // Body variants (only the ones a clip kind needs are shown).
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let picture = FlippedView()
    private let tile = FlippedView()
    private let monogram = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let fileIcon = NSImageView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let chip = FlippedView()
    private let chipLabel = NSTextField(labelWithString: "")
    private let numberBadge = FlippedView()
    private let numberLabel = NSTextField(labelWithString: "")

    private var isSelected = false
    /// The pointer is over the card: a neutral ring where the selection ring goes.
    private var isHovered = false
    private var query = ""
    private var tint: NSColor?
    /// The header's ink (white, or dark on light colours), set with the header colour.
    private var headerInk: HeaderColor.Ink = .light
    private var siteColor: NSColor = .systemBlue
    private var swatch: NSColor?
    private var imageTask: Task<Void, Never>?
    private var mouseDownPoint: NSPoint?

    /// SlopKit's readable orange (darkened in light mode) as an NSColor.
    private static let warningText = NSColor(Color.textOrange)
    private static let textFont = NSFont.systemFont(ofSize: 13)
    private static let headingFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let boldTextFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let wrapping: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1
        return style
    }()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        _ = Self.paletteObserver
        wantsLayer = true
        layer?.masksToBounds = false
        // A soft shadow instead of an outline (the path keeps it cheap to draw).
        layer?.shadowColor = .black
        ring.cornerCurve = .continuous
        ring.borderWidth = Self.ringWidth
        ring.isHidden = true
        layer?.addSublayer(ring)

        content.wantsLayer = true
        // AppKit owns a view layer's masksToBounds (it follows clipsToBounds, off by default
        // since macOS 14), so clip through the view or the corners come out square.
        content.clipsToBounds = true
        content.layer?.cornerCurve = .continuous
        // Labels draw into the card's own layer instead of one backing store each.
        content.canDrawSubviewsIntoLayer = true
        addSubview(content)

        header.wantsLayer = true
        content.addSubview(header)
        kindLabel.font = .systemFont(ofSize: 14, weight: .bold)
        ageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        pin.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        for view in [kindLabel, ageLabel, pin, appIcon] as [NSView] { header.addSubview(view) }

        textLabel.font = Self.textFont
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.lineBreakMode = .byWordWrapping
        picture.wantsLayer = true
        picture.clipsToBounds = true
        picture.layer?.contentsGravity = .resizeAspectFill
        tile.wantsLayer = true
        monogram.font = .systemFont(ofSize: 34, weight: .bold)
        monogram.alignment = .center
        tile.addSubview(monogram)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.alignment = .center
        chip.wantsLayer = true
        chip.layer?.cornerCurve = .continuous
        chipLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        chipLabel.alignment = .center
        chipLabel.lineBreakMode = .byTruncatingTail
        chip.addSubview(chipLabel)
        numberBadge.wantsLayer = true
        numberBadge.layer?.cornerCurve = .continuous
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        numberLabel.alignment = .center
        numberBadge.addSubview(numberLabel)
        for view in [picture, textLabel, tile, titleLabel, subtitleLabel, fileIcon, footerLabel, chip, numberBadge] as [NSView] {
            content.addSubview(view)
        }
        for view in [content, header, kindLabel, ageLabel, pin, appIcon, textLabel, picture, tile, monogram, titleLabel,
                     subtitleLabel, fileIcon, footerLabel, chip, chipLabel, numberBadge, numberLabel] as [NSView] {
            view.setAccessibilityElement(false)
        }
        applyCornerRadius()
    }

    private func applyCornerRadius() {
        content.layer?.cornerRadius = cornerRadius
        ring.cornerRadius = cornerRadius + Self.ringOutset
        // The badge sits in the card's bottom-right corner: concentric with it.
        numberBadge.layer?.cornerRadius = Radius.nested(in: cornerRadius, padding: Self.footRowInset)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // A hairline: one device pixel.
        content.layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Content

    func configure(clip: Clip, index: Int, number: Int?, now: Date, query: String, selected: Bool, showsNumber: Bool,
                   board: Board? = nil) {
        let sameClip = self.clip?.id == clip.id
        self.clip = clip
        self.index = index
        self.query = query
        isSelected = selected
        highlighted.removeAll()
        // A title the user gave the clip takes the kind's place.
        kindLabel.stringValue = ClipText.headerTitle(of: clip)
        let age = ClipText.ageSentence(of: clip.lastUsed, now: now)
        ageLabel.stringValue = age
        pin.isHidden = !clip.isPinned
        if let id = clip.sourceBundleID, let icon = AppIcons.icon(for: id) {
            appIcon.image = icon
            appIcon.isHidden = false
        } else {
            appIcon.isHidden = true
        }
        tint = AppTint.color(for: clip.sourceBundleID)
        numberLabel.stringValue = number.map { "⌘\($0)" } ?? ""
        numberBadge.isHidden = !(showsNumber && number != nil)

        // Hide every body variant, then show what this kind uses.
        for view in [textLabel, picture, tile, titleLabel, subtitleLabel, fileIcon, footerLabel, chip] as [NSView] {
            view.isHidden = true
        }
        swatch = nil
        if !sameClip {
            imageTask?.cancel()
            picture.layer?.contents = nil
        }
        footerLabel.stringValue = ClipText.cardFooter(of: clip) ?? ""
        footerLabel.isHidden = footerLabel.stringValue.isEmpty

        switch clip.kind {
        case .text:
            textLabel.isHidden = false
            textLabel.attributedStringValue = bodyText(for: clip, query: query)
        case .link:
            let host = ClipText.host(ofLink: clip.text)
            siteColor = AppTint.color(forHost: host)
            monogram.stringValue = ClipText.monogram(ofHost: host)
            tile.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            setHighlighted(titleLabel, clip.title ?? host, font: Self.titleFont)
            setHighlighted(subtitleLabel, ClipText.shortURL(clip.text), font: Self.subtitleFont)
        case .color:
            let hex = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = ColorValue(hex: hex) {
                swatch = NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
            }
            picture.isHidden = false
            chip.isHidden = false
            chipLabel.stringValue = hex
        case .image:
            picture.isHidden = false
            // A search that matched text in the image shows the words it matched.
            if let found = ClipText.imageTextSnippet(of: clip, query: query) {
                chip.isHidden = false
                chipLabel.stringValue = found
            } else if let footer = ClipText.cardFooter(of: clip) {
                chip.isHidden = false
                chipLabel.stringValue = footer
            }
            footerLabel.isHidden = true
            loadImage(for: clip)
        case .file:
            let paths = clip.filePaths
            fileIcon.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false
            fileIcon.image = paths.first.map(AppIcons.icon(forFile:)) ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            setHighlighted(titleLabel, ClipText.title(of: clip), font: Self.titleFont)
            if let first = paths.first, paths.count == 1, !FileManager.default.fileExists(atPath: first) {
                subtitleLabel.stringValue = "Not found"
            } else {
                subtitleLabel.stringValue = paths.first.map { (($0 as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath } ?? ""
            }
        }

        var spoken = [ClipText.kindName(of: clip)]
        if let label = clip.label { spoken.append(label) }
        switch clip.kind {
        case .link: spoken.append(clip.title.map { "\($0), \(ClipText.host(ofLink: clip.text))" } ?? clip.text)
        case .image:
            if clip.imageWidth > 0 { spoken.append("\(clip.imageWidth) by \(clip.imageHeight)") }
            if let found = ClipText.imageTextSnippet(of: clip, query: query) { spoken.append("text: \(found)") }
        default: spoken.append(ClipText.contentTitle(of: clip, limit: 120))
        }
        if clip.isPinned { spoken.append(board.map { "pinned to \($0.name)" } ?? "pinned") }
        if let source = clip.sourceName { spoken.append("from \(source)") }
        spoken.append(age)
        if let number { spoken.append("Command \(number)") }
        setAccessibilityLabel(spoken.joined(separator: ", "))
        needsLayout = true
        applyColors()
    }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        applyColors()
    }

    func setShowsNumber(_ shows: Bool) {
        numberBadge.isHidden = !(shows && !numberLabel.stringValue.isEmpty)
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11)

    /// A one-line label with the search's matches marked, as the text cards do. Its colour is
    /// set later (applyColors), so plain text keeps the label's own colour.
    private func setHighlighted(_ label: NSTextField, _ text: String, font: NSFont) {
        let ranges = SearchText.highlights(in: text, query: query)
        highlighted[ObjectIdentifier(label)] = ranges.isEmpty ? nil : (text, font, ranges)
        if ranges.isEmpty { label.stringValue = text }
    }

    /// Labels showing search matches: their text, font and the matched ranges.
    private var highlighted: [ObjectIdentifier: (String, NSFont, [NSRange])] = [:]

    /// Sets a label's colour, keeping its matches dark on the find highlight.
    private func setColor(_ color: NSColor, of label: NSTextField) {
        guard let (text, font, ranges) = highlighted[ObjectIdentifier(label)] else {
            label.textColor = color
            return
        }
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        for range in ranges where NSMaxRange(range) <= attributed.length {
            attributed.addAttributes([.backgroundColor: NSColor.findHighlightColor, .foregroundColor: NSColor.black], range: range)
        }
        label.attributedStringValue = attributed
    }

    /// The text body: the start of the clip, or the words around a match that's further in,
    /// with matches highlighted.
    private func bodyText(for clip: Clip, query: String) -> NSAttributedString {
        var text = String(clip.text.prefix(700))
        var isSnippet = false
        if !query.isEmpty, let snippet = ClipText.snippet(in: clip.searchableText, query: query, visibleLength: 220,
                                                           before: 40, length: 400) {
            text = snippet
            isSnippet = true
        }
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: Self.textFont, .foregroundColor: plain(.primary), .paragraphStyle: Self.wrapping,
        ])
        // A first line that reads like a heading ("Address:") is set in semibold.
        if !isSnippet, let heading = ClipText.headingLength(of: text), heading <= attributed.length {
            attributed.addAttribute(.font, value: Self.headingFont, range: NSRange(location: 0, length: heading))
        }
        for range in SearchText.highlights(in: text, query: query) where NSMaxRange(range) <= attributed.length {
            attributed.addAttributes([.font: Self.boldTextFont, .backgroundColor: NSColor.findHighlightColor,
                                      .foregroundColor: NSColor.black], range: range)
        }
        return attributed
    }

    private func loadImage(for clip: Clip) {
        let id = clip.id
        if let image = ImageCache.shared.cachedCardImage(for: id) {
            picture.layer?.contents = image
            return
        }
        // The small stored thumbnail first (instant), then a sharp one.
        if picture.layer?.contents == nil, let thumb = ImageCache.shared.cachedThumbnail(for: id) {
            picture.layer?.contents = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            if self?.picture.layer?.contents == nil, let thumb = await ImageCache.shared.thumbnail(for: clip),
               self?.clip?.id == id, self?.picture.layer?.contents == nil {
                self?.picture.layer?.contents = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            guard !Task.isCancelled, let image = await ImageCache.shared.cardImage(for: clip),
                  !Task.isCancelled, self?.clip?.id == id else { return }
            self?.picture.layer?.contents = image
        }
    }

    // MARK: - Layout and colours

    override func layout() {
        super.layout()
        let size = Self.size
        content.frame = CGRect(origin: .zero, size: size)
        layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: cornerRadius,
                                   cornerHeight: cornerRadius, transform: nil)
        let outset = Self.ringGap + Self.ringWidth
        ring.frame = CGRect(x: -outset, y: -outset, width: size.width + outset * 2, height: size.height + outset * 2)

        let pad = Self.padding
        let headerHeight = Self.headerHeight
        header.frame = CGRect(x: 0, y: 0, width: size.width, height: headerHeight)
        let iconSize = Self.appIconSize
        appIcon.frame = CGRect(x: size.width - iconSize + Self.appIconOverhang.width, y: -Self.appIconOverhang.height,
                               width: iconSize, height: iconSize)
        let textRight = appIcon.isHidden ? size.width - pad : appIcon.frame.minX
        kindLabel.sizeToFit()
        ageLabel.sizeToFit()
        // Kind over age, centred as a pair in the header.
        let pairHeight = kindLabel.frame.height + ageLabel.frame.height
        let pairTop = ((headerHeight - pairHeight) / 2).rounded()
        let pinRoom: CGFloat = clip?.isPinned == true ? 16 : 0
        kindLabel.frame = CGRect(x: pad, y: pairTop, width: min(kindLabel.frame.width, textRight - pad - pinRoom),
                                 height: kindLabel.frame.height)
        pin.frame = CGRect(x: kindLabel.frame.maxX + Spacing.xs, y: (kindLabel.frame.midY - 6).rounded(), width: 12, height: 12)
        ageLabel.frame = CGRect(x: pad, y: kindLabel.frame.maxY, width: textRight - pad, height: ageLabel.frame.height)

        let bodyTop = headerHeight
        // The foot row: one centre line for the count, the size chip and the badge.
        let footMidY = size.height - Self.footRowInset - Self.footRowHeight / 2
        let footerTop = size.height - Self.footerHeight
        footerLabel.sizeToFit()
        let footerLabelHeight = footerLabel.frame.height
        footerLabel.frame = CGRect(x: pad, y: (footMidY - footerLabelHeight / 2).rounded(), width: size.width - pad * 2,
                                   height: footerLabelHeight)
        // Body text: `pad` below the header on the first line's cap height, as on the sides.
        let textTop = bodyTop + pad - (Self.textFont.ascender - Self.textFont.capHeight).rounded()
        textLabel.frame = CGRect(x: pad, y: textTop, width: size.width - pad * 2, height: footerTop - textTop)
        let lineHeight = ceil(Self.textFont.ascender - Self.textFont.descender + Self.textFont.leading) + 1
        textLabel.maximumNumberOfLines = max(1, Int(textLabel.frame.height / lineHeight))

        // Pictures (images, colour swatches) run to the bottom edge.
        picture.frame = CGRect(x: 0, y: bodyTop, width: size.width, height: size.height - bodyTop)
        chipLabel.sizeToFit()
        let chipHeight = Self.footRowHeight
        let chipWidth = min(chipLabel.frame.width + chipHeight, size.width - Self.padding * 2)
        chipLabel.frame.size.width = chipWidth - chipHeight
        chip.frame = CGRect(x: ((size.width - chipWidth) / 2).rounded(), y: footMidY - chipHeight / 2, width: chipWidth, height: chipHeight)
        chip.layer?.cornerRadius = chipHeight / 2
        chipLabel.frame = CGRect(x: chipHeight / 2, y: ((chipHeight - chipLabel.frame.height) / 2).rounded(),
                                 width: chipLabel.frame.width, height: chipLabel.frame.height)

        // Links: a site tile, then the title and address.
        let tileHeight: CGFloat = 82
        tile.frame = CGRect(x: 0, y: bodyTop, width: size.width, height: tileHeight)
        monogram.sizeToFit()
        monogram.frame = CGRect(x: 0, y: ((tileHeight - monogram.frame.height) / 2).rounded(), width: size.width,
                                height: monogram.frame.height)
        // Files: the icon, then name and folder.
        let fileIconSize: CGFloat = 64
        fileIcon.frame = CGRect(x: (size.width - fileIconSize) / 2, y: bodyTop + pad, width: fileIconSize, height: fileIconSize)
        let titleFont = titleLabel.font ?? Self.textFont
        let titleTop = clip?.kind == .file ? fileIcon.frame.maxY + Spacing.s
            : tile.frame.maxY + pad - (titleFont.ascender - titleFont.capHeight).rounded()
        let titleSize = titleLabel.sizeThatFits(CGSize(width: size.width - pad * 2, height: 40))
        titleLabel.frame = CGRect(x: pad, y: titleTop, width: size.width - pad * 2, height: min(titleSize.height, 32))
        titleLabel.alignment = clip?.kind == .file ? .center : .left
        subtitleLabel.alignment = clip?.kind == .file ? .center : .left
        subtitleLabel.lineBreakMode = clip?.kind == .file ? .byTruncatingHead : .byTruncatingMiddle
        subtitleLabel.sizeToFit()
        subtitleLabel.frame = CGRect(x: pad, y: titleLabel.frame.maxY + 2, width: size.width - pad * 2,
                                     height: subtitleLabel.frame.height)

        numberLabel.sizeToFit()
        let badgeHeight = Self.footRowHeight
        let badgeWidth = max(badgeHeight, numberLabel.frame.width + Spacing.s + 2)
        numberBadge.frame = CGRect(x: size.width - badgeWidth - Self.footRowInset, y: footMidY - badgeHeight / 2,
                                   width: badgeWidth, height: badgeHeight)
        numberLabel.frame = CGRect(x: ((badgeWidth - numberLabel.frame.width) / 2).rounded(),
                                   y: ((badgeHeight - numberLabel.frame.height) / 2).rounded(),
                                   width: numberLabel.frame.width, height: numberLabel.frame.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let clip, clip.kind == .text { textLabel.attributedStringValue = bodyText(for: clip, query: query) }
        applyColors()
    }

    /// An NSColor as sRGB components (nil for no colour).
    private static func rgb(_ color: NSColor?) -> RGB? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        return RGB(srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    /// `color` as it looks in plain light or dark mode, fixed.
    ///
    /// Inside the glass strip every view's appearance becomes the vibrant variant, whose label
    /// colours are meant to be blended onto glass. Drawn flat on an opaque card they came out
    /// a shade too light (secondary text #999999 on white, 2.9:1, instead of #808080, ~3.9:1;
    /// body text #4D4D4D instead of #262626). Cards are opaque, so they use the plain colours.
    private func plain(_ role: TextRole) -> NSColor {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = PlainColorKey(role: role, dark: dark)
        if let cached = Self.plainColors[key] { return cached }
        let color = role.color
        var resolved = color
        (dark ? Self.darkAppearance : Self.lightAppearance)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        Self.plainColors[key] = resolved
        return resolved
    }

    private enum TextRole: Hashable {
        case primary, secondary, warning

        var color: NSColor {
            switch self {
            case .primary: .labelColor
            case .secondary: .secondaryLabelColor
            case .warning: ClipCardView.warningText
            }
        }
    }

    private struct PlainColorKey: Hashable {
        let role: TextRole
        let dark: Bool
    }

    // Reset when the system palette changes (Increase Contrast, accent colour).
    private static var plainColors: [PlainColorKey: NSColor] = [:]
    private static let lightAppearance = NSAppearance(named: .aqua)
    private static let darkAppearance = NSAppearance(named: .darkAqua)
    private static let paletteObserver: Void = {
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { ClipCardView.plainColors.removeAll() }
        }
    }()

    /// Selection follows the keyboard, so it changes at once; hover fades in briefly.
    private func applyColors(fade: Bool = false) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(!fade)
        CATransaction.setAnimationDuration(0.12)
        defer { CATransaction.commit() }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            content.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            // Light: a soft shadow lifts the white card off the glass. Dark: shadows barely
            // read, so a deeper, tighter one plus a faint edge.
            content.layer?.borderColor = dark ? NSColor.separatorColor.cgColor : NSColor.clear.cgColor
            layer?.shadowOpacity = dark ? 0.45 : 0.14
            layer?.shadowRadius = dark ? 2 : 4
            layer?.shadowOffset = CGSize(width: 0, height: dark ? -1 : -2)
            let header = HeaderColor.resolve(base: Self.rgb(tint) ?? .neutral, darkMode: dark)
            headerInk = header.ink
            self.header.layer?.backgroundColor = CGColor(srgbRed: header.fill.red, green: header.fill.green,
                                                         blue: header.fill.blue, alpha: 1)
            ring.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
            ring.isHidden = !(isSelected || isHovered)
            tile.layer?.backgroundColor = siteColor.withAlphaComponent(dark ? 0.28 : 0.16).cgColor
            // Bright system colours (yellow, mint) need darkening to read on their light wash.
            monogram.textColor = dark ? siteColor : (siteColor.blended(withFraction: 0.4, of: .black) ?? siteColor)
            if let swatch {
                picture.layer?.contents = nil
                picture.layer?.backgroundColor = swatch.cgColor
            } else {
                picture.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            }
            // Dark enough behind white text over any picture (4.5:1 even over white).
            chip.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            numberBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        // White on the app's colour, or dark type on light colours (see HeaderColor).
        let ink: NSColor = headerInk == .light ? .white : .black
        kindLabel.textColor = headerInk == .light ? ink : ink.withAlphaComponent(0.85)
        ageLabel.textColor = headerInk == .light ? ink : ink.withAlphaComponent(HeaderColor.darkSecondaryOpacity)
        pin.contentTintColor = kindLabel.textColor
        setColor(plain(.primary), of: titleLabel)
        setColor(plain(subtitleLabel.stringValue == "Not found" ? .warning : .secondary), of: subtitleLabel)
        footerLabel.textColor = plain(.secondary)
        chipLabel.textColor = .white
        numberLabel.textColor = .white
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // The strip never activates Clips, so track while inactive too.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        applyColors(fade: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    override var isHidden: Bool {
        didSet { if isHidden, isHovered { isHovered = false } }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        strip?.cardClicked(self, clickCount: event.clickCount, modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        strip?.cardMouseUp(self)
    }

    /// The clips being dragged (several when the card is one of a selection).
    private var draggedClips: [Clip] = []

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, clip != nil, let strip else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        strip.dragStarted()
        draggedClips = strip.targets(for: self)
        let image = snapshot()
        var items: [NSDraggingItem] = []
        for (offset, clip) in draggedClips.enumerated() {
            for writer in strip.dragWriters(for: clip) {
                let item = NSDraggingItem(pasteboardWriter: writer)
                // Several cards: a small fan of this one, so the drag shows it's more than one.
                let shift = CGFloat(min(offset, 3)) * 6
                item.setDraggingFrame(bounds.offsetBy(dx: shift, dy: shift), contents: offset < 4 ? image : nil)
                items.append(item)
            }
        }
        guard !items.isEmpty else { return }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .none
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        strip?.menu(for: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    /// Over a board tab, the card drops there instead of sliding back.
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let overBoard = strip?.dragMoved(to: screenPoint) ?? false
        session.animatesToStartingPositionsOnCancelOrFail = !overBoard
    }

    /// A card dropped into an app counts as using the clip: the paste sound. Dropped on a
    /// board tab, it's pinned there.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let clips = draggedClips
        draggedClips = []
        if operation != [] {
            AppModel.shared.clipDelivered()
        } else {
            _ = strip?.dragEnded(at: screenPoint, clips: clips)
        }
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    /// The label says it all; the card's inner labels would only repeat it.
    override func accessibilityChildren() -> [Any]? { [] }
    override func isAccessibilitySelected() -> Bool { isSelected }
    override func accessibilityPerformPress() -> Bool {
        strip?.cardClicked(self, clickCount: 1)
        return true
    }
}

/// A plain view with a top-left origin, for manual layout.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

