import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

// Archetype: drop-in utility window. See docs/design-system.md, 2b.

@main
struct IconsmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Iconsmith")

    var body: some Scene {
        // One window. Closing it quits the app.
        Window("Iconsmith", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 820, height: 700)
        .commands { IconsmithCommands(model: model, info: info) }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

struct IconsmithCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Iconsmith") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { model.chooseImage() }
                .keyboardShortcut("o")
                .disabled(model.isPresentingPanel)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Export \(model.prefs.format.title)…") { model.export() }
                .keyboardShortcut("e")
                .disabled(!model.hasSource || model.isPresentingPanel)
            Menu("Export As") {
                ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element) { index, format in
                    Button("\(format.title)…") { model.export(format) }
                        // ⌥⌘: ⇧⌘3/4/5/6 belong to macOS screenshots.
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
            }
            .disabled(!model.hasSource || model.isPresentingPanel)
            Divider()
            Button("Close Image") { model.closeImage() }
                .disabled(!model.hasSource)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { WindowCloser.closeFrontmost() }
                .keyboardShortcut("w")
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoState.undoTitle) {
                if EditTarget.isMainWindow { model.undo() } else { EditTarget.forward(Selector(("undo:"))) }
            }
            .keyboardShortcut("z")
            .disabled(!model.undoState.canUndo)
            Button(model.undoState.redoTitle) {
                if EditTarget.isMainWindow { model.redo() } else { EditTarget.forward(Selector(("redo:"))) }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.undoState.canRedo)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Icon") {
                if EditTarget.isMainWindow { model.copyIcon() } else { EditTarget.forward(#selector(NSText.copy(_:))) }
            }
            .keyboardShortcut("c")
            Button("Paste") {
                if EditTarget.isMainWindow { model.paste() } else { EditTarget.forward(#selector(NSText.paste(_:))) }
            }
            .keyboardShortcut("v")
            Divider()
            Button("Apply Icon to…") { model.chooseTargets(remove: false) }
                .keyboardShortcut("j")
                .disabled(!model.hasSource || model.isPresentingPanel)
            Button("Remove Custom Icons…") { model.chooseTargets(remove: true) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(model.isPresentingPanel)
        }
        CommandMenu("Icon") {
            ForEach(Array(IconShape.allCases.enumerated()), id: \.element) { index, shape in
                Toggle(shape.title, isOn: Binding(get: { model.style.shape == shape }, set: { _ in model.setShape(shape) }))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Menu("Background") {
                ForEach(BackgroundMode.allCases) { mode in
                    Toggle(mode.title, isOn: Binding(get: { model.style.background == mode },
                                                     set: { _ in model.edit("Change Background") { $0.background = mode } }))
                }
            }
            .disabled(!model.style.shape.usesBackground)
            Divider()
            Menu("Framing") {
                Toggle("Fit", isOn: Binding(get: { !model.style.fill }, set: { _ in model.setFill(false) }))
                Toggle("Fill", isOn: Binding(get: { model.style.fill }, set: { _ in model.setFill(true) }))
            }
            .disabled(!model.hasSource)
            Button("Bigger") { model.zoom(by: 1.1) }
                .keyboardShortcut("=")
                .disabled(!model.hasSource)
            Button("Smaller") { model.zoom(by: 1 / 1.1) }
                .keyboardShortcut("-")
                .disabled(!model.hasSource)
            Button("Reset Size") { model.resetSize() }
                .disabled(!model.hasSource)
            Menu("Move Picture") {
                Button("Up") { model.nudge(dx: 0, dy: AppModel.nudgeStep) }
                    .keyboardShortcut(.upArrow, modifiers: [.option])
                Button("Down") { model.nudge(dx: 0, dy: -AppModel.nudgeStep) }
                    .keyboardShortcut(.downArrow, modifiers: [.option])
                Button("Left") { model.nudge(dx: -AppModel.nudgeStep, dy: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [.option])
                Button("Right") { model.nudge(dx: AppModel.nudgeStep, dy: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: [.option])
            }
            .disabled(!model.hasSource)
            Button("Re-center") { model.resetPosition() }
                .keyboardShortcut("0")
                .disabled(!model.hasSource || model.style.isCentered)
        }
        CommandGroup(replacing: .help) {
            Button("Iconsmith Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Iconsmith"))
            }
        }
    }
}

/// Copy and Paste mean "the icon" in the main window and the usual text editing elsewhere
/// (the colour panel's hex field, Settings).
@MainActor
enum EditTarget {
    static var isMainWindow: Bool {
        guard let key = NSApp.keyWindow else { return true }
        return key === MainWindow.current
    }

    static func forward(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

@MainActor
enum WindowCloser {
    static func closeFrontmost() {
        let window = NSApp.keyWindow
            ?? NSApp.orderedWindows.first { $0.isVisible && $0.styleMask.contains(.closable) && !($0 is NSPanel) }
        window?.performClose(nil)
    }
}
