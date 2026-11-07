import AppKit
import DropperCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Palette files: import (ASE, CLR, GPL, our JSON, or any text with color values) and
/// export (the same plus CSS variables). Apple Color Lists go through `NSColorList`.
@MainActor
enum PaletteFiles {
    static let importTypes: [UTType] = ["ase", "clr", "gpl", "json", "css", "txt", "scss", "svg"]
        .compactMap { UTType(filenameExtension: $0) } + [.plainText, .json]

    static func chooseAndImport(into controller: AppController) {
        AppActivation.activate()
        let panel = NSOpenPanel()
        panel.title = "Import Palette"
        panel.prompt = "Import"
        panel.message = "Choose ASE, CLR, GPL or Dropper palette files, or any text file with color values."
        panel.allowedContentTypes = importTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, into: controller)
    }

    /// Imports files and selects the first new palette in the Library.
    static func importFiles(_ urls: [URL], into controller: AppController) {
        var added: [Palette] = []
        var failures: [String] = []
        for url in urls {
            do {
                let palettes = try read(url)
                added += controller.model.importPalettes(palettes)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Diagnostics.record("imported \(added.count) palettes, \(failures.count) failures")
        if let first = added.first {
            controller.showLibrary(list: .palette(first.id))
            let count = added.reduce(0) { $0 + $1.colors.count }
            HUD.show("Imported \(added.count == 1 ? "“\(first.name)”" : "\(added.count) palettes"), \(count) colors",
                     systemImage: "square.and.arrow.down")
        }
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = failures.count == 1 ? "Couldn’t import this file" : "Couldn’t import \(failures.count) files"
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
    }

    static func read(_ url: URL) throws -> [Palette] {
        let name = url.deletingPathExtension().lastPathComponent
        let format = PaletteFileFormat.forExtension(url.pathExtension)
        if format == .clr {
            guard let list = NSColorList(name: name, fromFile: url.path) else { throw PaletteCodecError.notAPalette }
            let items = list.allKeys.compactMap { key -> PickedColor? in
                guard let color = list.color(withKey: key).flatMap(SystemColorSampler.convert) else { return nil }
                return PickedColor(color: color, date: .now, name: key)
            }
            guard !items.isEmpty else { throw PaletteCodecError.noColors }
            return [Palette(name: name, colors: items, created: .now)]
        }
        let data = try Data(contentsOf: url)
        return try PaletteCodec.importPalettes(data, format: format, fallbackName: name, date: .now)
    }

    static func export(_ palette: Palette, as format: PaletteFileFormat, controller: AppController) {
        let fileName = sanitized(palette.name) + "." + format.fileExtension
        if let dir = Diagnostics.exportDirectory {
            write(palette, as: format, to: dir.appendingPathComponent(fileName), controller: controller)
            return
        }
        AppActivation.activate()
        let panel = NSSavePanel()
        panel.title = "Export Palette"
        panel.nameFieldStringValue = fileName
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(palette, as: format, to: url, controller: controller)
    }

    static func write(_ palette: Palette, as format: PaletteFileFormat, to url: URL, controller: AppController) {
        do {
            if format == .clr {
                let list = NSColorList(name: palette.name)
                var used: [String: Int] = [:]
                for item in palette.colors {
                    var key = item.displayName
                    used[key, default: 0] += 1
                    if let n = used[key], n > 1 { key += " \(n)" }
                    list.setColor(item.color.nsColor, forKey: key)
                }
                try list.write(to: url)
            } else if format == .pdf {
                try PaletteSheet.pdf(palette, model: controller.model).write(to: url, options: .atomic)
            } else if format == .css {
                let model = controller.model
                let cssFormat = model.preferences.format.groupTitle == "Web" && model.preferences.format != .hsb
                    ? model.preferences.format : .hex
                try Data(PaletteCodec.css(palette, format: cssFormat, options: model.preferences.options).utf8).write(to: url, options: .atomic)
            } else if let data = PaletteCodec.export(palette, as: format, options: controller.model.preferences.options) {
                try data.write(to: url, options: .atomic)
            }
            Diagnostics.record("exported \(palette.colors.count) colors to \(url.lastPathComponent)")
            HUD.show("Exported “\(palette.name)”", systemImage: "square.and.arrow.up")
        } catch {
            // Cocoa's own message names the file as if it were a folder ("The folder
            // “Brand.json” doesn’t exist"); say what failed and what to do instead.
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t export “\(palette.name)”"
            alert.informativeText = exportFailureReason(error, folder: url.deletingLastPathComponent())
            alert.runModal()
        }
    }

    static func exportFailureReason(_ error: Error, folder: URL) -> String {
        let code = (error as? CocoaError)?.code
        if code == .fileNoSuchFile || code == .fileWriteNoPermission || code == .fileWriteVolumeReadOnly
            || code == .fileWriteInvalidFileName {
            return "The folder “\(folder.lastPathComponent)” is missing or can’t be written to. Export again and choose another folder."
        }
        if code == .fileWriteOutOfSpace {
            return "The disk is full. Free some space, then export again."
        }
        return "\(error.localizedDescription) Try exporting again, or choose another format."
    }

    private static func sanitized(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Palette" : cleaned
    }
}

/// A printable sheet: the palette's name and note, then each color with its name and its
/// value in a few common formats.
struct PaletteSheet: View {
    let palette: Palette
    let model: DropperModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(palette.name).font(.system(size: 28, weight: .bold))
            if !palette.note.isEmpty { Text(palette.note).font(.system(size: 13)).foregroundStyle(.secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: Spacing.l, alignment: .topLeading), count: 3),
                      alignment: .leading, spacing: Spacing.xl) {
                ForEach(palette.colors) { item in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(item.color.swiftUIColor).frame(height: 90)
                            .overlay { RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(.black.opacity(0.12)) }
                        Text(item.displayName).font(.system(size: 12, weight: .semibold))
                        ForEach([ColorFormat.hex, .cssRGB, .cssOKLCH], id: \.self) { format in
                            Text(model.text(for: item.color, as: format)).font(.system(size: 10, design: .monospaced))
                        }
                    }
                }
            }
            Text("Exported from Dropper").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(40) // lint:allow page margin of a printed letter-size sheet
        .frame(width: 612, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    /// One letter-width page, as tall as the sheet needs (at least letter height).
    @MainActor
    static func pdf(_ palette: Palette, model: DropperModel) throws -> Data {
        let renderer = ImageRenderer(content: PaletteSheet(palette: palette, model: model))
        let data = NSMutableData()
        var failed = true
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 612, height: max(size.height, 792)))
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: box.height - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            failed = false
        }
        if failed { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
