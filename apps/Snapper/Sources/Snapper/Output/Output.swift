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
    func write(text: String)
    /// A file (recordings): as a file URL, so Finder, Mail and chats paste the file itself.
    func write(file: URL)
}

@MainActor
struct SystemPasteboardWriter: PasteboardWriting {
    /// The general pasteboard, or a private named one when `SNAPPER_PASTEBOARD` is set
    /// (tests read it back without touching the real clipboard).
    var board: NSPasteboard {
        Diagnostics.pasteboardName.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }

    func write(text: String) {
        let board = self.board
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func write(file: URL) {
        let board = self.board
        board.clearContents()
        board.writeObjects([file as NSURL])
        if file.pathExtension.lowercased() == "gif", let data = try? Data(contentsOf: file) {
            board.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
    }

    /// PNG (lossless, keeps transparency) plus the TIFF NSImage writes, so every app can paste it.
    func write(_ image: CGImage, size: CGSize) {
        let board = self.board
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
    static func save(_ image: CGImage, format: ImageFormat, to folder: URL, date: Date, baseName: String? = nil, replacing previous: URL? = nil) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            do {
                return try ImageEncoder.save(image, format: format, to: folder, date: date, baseName: baseName, replacing: previous)
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

    /// Copies a recording into `folder` under a unique name; returns the new file.
    static func saveFile(_ source: URL, to folder: URL, baseName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = FileNaming.uniqueName(base: baseName, fileExtension: source.pathExtension) {
                    fm.fileExists(atPath: folder.appendingPathComponent($0).path)
                }
                let url = folder.appendingPathComponent(name)
                try fm.copyItem(at: source, to: url)
                return url
            } catch {
                throw SaveError.failed(folder: folder)
            }
        }.value
    }

    /// Asks where to save a recording. Returns the URL written, or nil if cancelled.
    @MainActor
    static func saveFileAs(_ source: URL, suggestedName: String, folder: URL) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(source.pathExtension)"
        panel.directoryURL = folder
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: source.pathExtension) { panel.allowedContentTypes = [type] }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: source, to: url)
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
