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
        let compare = ClosureMenuItem("Compare", key: "k") { model.openCompare() }
        compare.isEnabled = model.canCompare
        menu.addItem(compare)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(model.allActionFamiliesAreFavorites ? "Remove from Favorites" : "Add to Favorites", key: "d") { model.toggleFavorite() })
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

    func makeNSView(context: Context) -> PreviewLineView { PreviewLineView() }

    func updateNSView(_ view: PreviewLineView, context: Context) {
        view.configure(face: face, text: text, size: size, allowSample: allowSample)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewLineView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: FontCardView.previewHeight(for: size))
    }
}

final class PreviewLineView: NSView {
    private var face: FontFace?
    private var text = ""
    private var size: CGFloat = 36
    private var allowSample = true

    override var isFlipped: Bool { true }

    func configure(face: FontFace, text: String, size: CGFloat, allowSample: Bool) {
        guard face != self.face || text != self.text || size != self.size || allowSample != self.allowSample else { return }
        self.face = face
        self.text = text
        self.size = size
        self.allowSample = allowSample
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(PreviewText.line(for: text, familyName: face.displayFamilyName)), in \(face.fullName)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let face, let context = NSGraphicsContext.current?.cgContext else { return }
        let lineText = PreviewText.line(for: text, familyName: face.displayFamilyName)
        let line = PreviewRenderer.shared.line(for: face, text: lineText, size: size, width: bounds.width, allowSample: allowSample)
        context.saveGState()
        context.clip(to: bounds)
        if line.unavailable {
            ("Can't preview this font" as NSString).draw(at: NSPoint(x: 0, y: 4), withAttributes: [
                .font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        } else {
            line.draw(in: context, x: 0, baseline: 4 + min(line.ascent, size * 1.05), color: .labelColor)
        }
        context.restoreGState()
    }
}
