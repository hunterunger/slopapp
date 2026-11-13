import AppKit
import SpecimenCore
import SwiftUI

/// The grid's right-click menu. Same actions (and shortcuts) as the Font menu.
@MainActor
struct ContextMenuBuilder {
    let model: AppModel

    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Show Details", key: "") { model.openDetail() })
        menu.addItem(ClosureMenuItem(model.selectionIsInTray ? "Remove from Compare" : "Add to Compare", key: "") { model.toggleTraySelection() })
        let compare = ClosureMenuItem("Compare", key: "k") { model.openCompare() }
        compare.isEnabled = model.canCompare
        menu.addItem(compare)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(model.allActionFamiliesAreFavorites ? "Remove from Favorites" : "Add to Favorites", key: "d") { model.toggleFavorite() })
        let tagsItem = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        let tagsMenu = NSMenu()
        let families = model.actionFamilies
        for tag in model.tags.names {
            let item = ClosureMenuItem(tag, key: "") { model.toggleTag(tag, families: families) }
            switch model.tags.membership(tag, families: families) {
            case .all: item.state = .on
            case .some: item.state = .mixed
            case .none: item.state = .off
            }
            tagsMenu.addItem(item)
        }
        if !model.tags.isEmpty { tagsMenu.addItem(.separator()) }
        tagsMenu.addItem(ClosureMenuItem("New Tag…", key: "") { model.sheet = .newTag })
        tagsMenu.addItem(ClosureMenuItem("Edit Tags…", key: "t") { model.sheet = .tags })
        tagsMenu.autoenablesItems = false
        tagsItem.submenu = tagsMenu
        menu.addItem(tagsItem)
        let category = NSMenuItem(title: "Category", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let names = model.actionFamilies
        let current = Set(names.compactMap(model.category(ofFamily:)))
        for option in FontCategory.allCases {
            let item = ClosureMenuItem(option.title, key: "") { model.setCategory(option, families: names) }
            item.state = current == [option] ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let automatic = ClosureMenuItem("Automatic", key: "") { model.setCategory(nil, families: names) }
        automatic.isEnabled = names.contains(where: model.hasCategoryOverride)
        submenu.addItem(automatic)
        category.submenu = submenu
        menu.addItem(category)
        menu.addItem(.separator())
        let activate = ClosureMenuItem("Activate", key: ";") { model.activate(true) }
        activate.isEnabled = model.canActivate
        menu.addItem(activate)
        let temporary = ClosureMenuItem("Activate Temporarily", key: ";", modifiers: [.command, .option]) { model.activate(true, temporary: true) }
        temporary.isEnabled = model.canActivateTemporarily
        temporary.toolTip = "Until you quit Specimen"
        menu.addItem(temporary)
        let deactivate = ClosureMenuItem("Deactivate", key: ";", modifiers: [.command, .shift]) { model.activate(false) }
        deactivate.isEnabled = model.canDeactivate
        menu.addItem(deactivate)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy Name", key: "c") { model.copyNames(postScript: false) })
        menu.addItem(ClosureMenuItem("Copy PostScript Name", key: "c", modifiers: [.command, .option]) { model.copyNames(postScript: true) })
        let reveal = ClosureMenuItem("Show in Finder", key: "r", modifiers: [.command, .shift]) { model.revealInFinder() }
        reveal.isEnabled = !model.revealableURLs.isEmpty
        menu.addItem(reveal)
        menu.autoenablesItems = false
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String, modifiers: NSEvent.ModifierFlags = .command, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

/// One preview line for SwiftUI (detail, waterfall, compare), drawn like the grid's cards.
struct PreviewLine: NSViewRepresentable {
    var face: FontFace
    var text: String
    var size: CGFloat
    var allowSample = true
    var variation: [Int: Double] = [:]
    var centered = false
    var features: [FeatureValue] = []

    func makeNSView(context: Context) -> PreviewLineView { PreviewLineView() }

    func updateNSView(_ view: PreviewLineView, context: Context) {
        view.configure(face: face, text: text, size: size, allowSample: allowSample, variation: variation, centered: centered, features: features)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewLineView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: PreviewMetrics.height(for: size))
    }
}

final class PreviewLineView: NSView {
    private var face: FontFace?
    private var text = ""
    private var size: CGFloat = 36
    private var allowSample = true
    private var variation: [Int: Double] = [:]
    private var centered = false
    private var features: [FeatureValue] = []

    override var isFlipped: Bool { true }

    /// The cached line is per appearance; repaint when it changes so colours re-resolve.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func configure(face: FontFace, text: String, size: CGFloat, allowSample: Bool, variation: [Int: Double] = [:], centered: Bool = false,
                   features: [FeatureValue] = []) {
        guard face != self.face || text != self.text || size != self.size || allowSample != self.allowSample
            || variation != self.variation || centered != self.centered || features != self.features else { return }
        self.features = features
        self.face = face
        self.text = text
        self.size = size
        self.allowSample = allowSample
        self.variation = variation
        self.centered = centered
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(PreviewText.line(for: text, familyName: face.displayFamilyName)), in \(face.fullName)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let face, let context = NSGraphicsContext.current?.cgContext else { return }
        let lineText = PreviewText.line(for: text, familyName: face.displayFamilyName)
        let line = PreviewRenderer.shared.line(for: face, text: lineText, size: size, width: bounds.width, allowSample: allowSample,
                                               variation: variation, features: features)
        context.saveGState()
        context.clip(to: bounds)
        if line.unavailable {
            ("Can't preview this font" as NSString).draw(at: NSPoint(x: 0, y: PreviewMetrics.topPadding), withAttributes: [
                .font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.secondaryLabelColor,
            ])
        } else {
            let x = centered && line.width < bounds.width ? (bounds.width - line.width) / 2 : 0
            line.draw(in: context, x: x, baseline: PreviewMetrics.baseline(for: size), color: .labelColor)
        }
        context.restoreGState()
    }
}
