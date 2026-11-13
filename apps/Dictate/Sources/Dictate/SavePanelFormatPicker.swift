import AppKit
import SlopKit
import UniformTypeIdentifiers

/// A "Format:" pop-up under a save panel's file name, like TextEdit and Preview have. Picking
/// a format changes the file type and the name's extension. Could move to SlopKit.
final class SavePanelFormatPicker: NSObject {
    struct Format {
        var name: String
        var type: UTType
        var tag: String
    }

    private let formats: [Format]
    private(set) var selectedTag: String
    private weak var panel: NSSavePanel?
    /// The file name without an extension, as the caller set it.
    private var baseName = ""
    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)

    init(formats: [Format], selected: String) {
        self.formats = formats
        selectedTag = formats.contains { $0.tag == selected } ? selected : formats.first?.tag ?? ""
        super.init()
    }

    /// Set the panel's `nameFieldStringValue` (without an extension) first.
    func attach(to panel: NSSavePanel) {
        self.panel = panel
        baseName = panel.nameFieldStringValue
        popUp.addItems(withTitles: formats.map(\.name))
        popUp.selectItem(at: formats.firstIndex { $0.tag == selectedTag } ?? 0)
        popUp.target = self
        popUp.action = #selector(changed)
        popUp.setAccessibilityLabel("Format")

        let label = NSTextField(labelWithString: "Format:")
        let row = NSStackView(views: [label, popUp])
        row.orientation = .horizontal
        row.spacing = Spacing.s
        row.translatesAutoresizingMaskIntoConstraints = false
        // Centred under the panel's fields, as in TextEdit and Preview.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: Spacing.l),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: Spacing.m),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Spacing.m),
        ])
        panel.accessoryView = container
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        apply()
    }

    @objc private func changed() {
        selectedTag = formats[max(0, popUp.indexOfSelectedItem)].tag
        apply()
    }

    private func apply() {
        guard let panel, let format = formats.first(where: { $0.tag == selectedTag }) else { return }
        panel.allowedContentTypes = [format.type]
        // Keep what the person typed, swapping only the extension.
        let typed = panel.nameFieldStringValue
        let known = formats.compactMap(\.type.preferredFilenameExtension)
        let ext = (typed as NSString).pathExtension
        let base = known.contains(ext.lowercased()) ? (typed as NSString).deletingPathExtension : (typed.isEmpty ? baseName : typed)
        if let newExt = format.type.preferredFilenameExtension, !base.isEmpty {
            panel.nameFieldStringValue = "\(base).\(newExt)"
        }
    }
}
