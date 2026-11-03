import AppKit
import SlopKit
import SnapperCore
import UniformTypeIdentifiers

/// Writing a capture somewhere: clipboard, a folder, a save panel, the share sheet.
/// System calls sit behind `PasteboardWriting` / `FolderSaving` so the model can be tested
/// with fakes.
@MainActor
protocol PasteboardWriting {
    func write(_ image: CGImage, size: CGSize)
}

@MainActor
struct SystemPasteboardWriter: PasteboardWriting {
    /// PNG (lossless, keeps transparency) plus the TIFF NSImage writes, so every app can paste it.
    func write(_ image: CGImage, size: CGSize) {
        let board = NSPasteboard.general
        board.clearContents()
        let nsImage = NSImage(cgImage: image, size: size)
        board.writeObjects([nsImage])
        if let png = try? ImageEncoder.data(for: image, format: .png) {
            board.setData(png, forType: .png)
        }
    }
}

enum SaveError: LocalizedError {
    case failed(folder: URL)

    var errorDescription: String? {
        switch self {
        case .failed(let folder):
            "Couldn't save to \(folder.lastPathComponent). Check that the folder exists and you can write to it, or choose another folder in Settings."
        }
    }
}

enum Output {
    /// Saves off the main thread; returns the new file's URL.
    static func save(_ image: CGImage, format: ImageFormat, to folder: URL, date: Date, replacing previous: URL? = nil) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            do {
                return try ImageEncoder.save(image, format: format, to: folder, date: date, replacing: previous)
            } catch {
                throw SaveError.failed(folder: folder)
            }
        }.value
    }

    /// Asks where to save (with a format menu), starting in `folder`. Returns the URL
    /// written, or nil if cancelled.
    @MainActor
    static func saveAs(_ image: CGImage, suggestedName: String, format: ImageFormat, folder: URL) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.directoryURL = folder
        panel.canCreateDirectories = true
        let picker = FormatPicker(panel: panel, format: format)
        panel.accessoryView = picker.view
        NSApp.activate()
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        let chosen = ImageFormat(fileExtension: url.pathExtension) ?? picker.format
        do {
            let data = try await Task.detached { try ImageEncoder.data(for: image, format: chosen) }.value
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            HUD.show("Couldn't save \(url.lastPathComponent). Try another folder.", systemImage: "exclamationmark.triangle")
            return nil
        }
    }

    /// Shows the share menu for a file next to `view`.
    @MainActor
    static func share(_ url: URL, from view: NSView, edge: NSRectEdge = .minY) {
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }

    /// macOS's own screen capture sound.
    @MainActor
    static func playShutter() {
        guard !Diagnostics.silent else { return }
        shutter?.stop()
        shutter?.play()
    }

    @MainActor private static let shutter: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()
}

/// The "Format" menu under a save panel; switching it updates the file type and extension.
@MainActor
final class FormatPicker: NSObject {
    private weak var panel: NSSavePanel?
    private(set) var format: ImageFormat
    let view: NSView
    private let popup: NSPopUpButton

    init(panel: NSSavePanel, format: ImageFormat) {
        self.panel = panel
        self.format = format
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ImageFormat.allCases.map(\.title))
        popup.selectItem(at: ImageFormat.allCases.firstIndex(of: format) ?? 0)
        popup.setAccessibilityLabel("Format")
        let label = NSTextField(labelWithString: "Format:")
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view = stack
        super.init()
        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        format = ImageFormat.allCases[popup.indexOfSelectedItem]
        guard let panel else { return }
        panel.allowedContentTypes = [format.utType]
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
    }
}
