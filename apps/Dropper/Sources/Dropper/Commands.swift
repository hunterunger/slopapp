import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The main menu while Dropper is frontmost (Library, Settings or the Contrast Checker).
/// Also the way in when a crowded menu bar hides the status item.
struct DropperCommands: Commands {
    let controller: AppController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Palette") {
                let palette = controller.newPalette()
                controller.showLibrary(list: .palette(palette.id))
            }
            .keyboardShortcut("n")
            Button("Import Palette…") { controller.importPalettes() }
                .keyboardShortcut("o")
        }
        CommandMenu("Color") {
            ColorCommandItems(controller: controller, model: controller.model)
        }
        CommandGroup(before: .windowList) {
            Button("Dropper Library") { controller.showLibrary() }
                .keyboardShortcut("0")
            Button("Dropper Panel") { controller.togglePanel() }
            Button(controller.settings.showDock ? "Hide Color Dock" : "Show Color Dock") { controller.dock.toggle() }
            Divider()
        }
        HelpCommands(info: controller.info) {
            Button("Dropper Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Dropper"))
            }
        }
    }
}

private struct ColorCommandItems: View {
    let controller: AppController
    let model: DropperModel

    var body: some View {
        Button("Pick Color") { controller.pickAndCopy() }
            .globalShortcut(.pickColor)
        Button("Pick Multiple Colors") { controller.pickMultiple() }
            .globalShortcut(.pickMultiple)
        Button("Pick Contrast Pair") { controller.pickContrastPair() }
        Button("Contrast Checker…") { controller.showContrastChecker() }
            .keyboardShortcut("k")
        Divider()
        Menu("Copy Last Color As") {
            if let last = model.history.latest {
                ForEach(ColorFormat.groups) { group in
                    Section(group.title) {
                        ForEach(model.preferences.visible(in: group)) { format in
                            Button("\(format.title): \(model.text(for: last.color, as: format, name: last.name))") {
                                controller.copy(last, as: format)
                            }
                        }
                    }
                }
            }
        }
        .disabled(model.history.latest == nil)
        Menu("Recent Colors") {
            ForEach(model.history.items.prefix(10)) { item in
                Button {
                    controller.copy(item)
                } label: {
                    Label {
                        Text(model.menuTitle(for: item.color))
                    } icon: {
                        Image(nsImage: SwatchImage.image(for: item.color))
                    }
                }
            }
            Divider()
            Button("Clear History…") { controller.clearHistory() }
        }
        .disabled(model.history.items.isEmpty)
    }
}

extension DropperModel {
    /// The color in the copy format, marked when the chosen space can't show it, so a vivid
    /// P3 red and a plain sRGB red don't look like the same "#FF0000".
    func menuTitle(for color: ColorValue) -> String {
        let text = text(for: color)
        guard isClamped(color) else { return text }
        return "\(text) · outside \(preferences.options.space.title)"
    }
}
