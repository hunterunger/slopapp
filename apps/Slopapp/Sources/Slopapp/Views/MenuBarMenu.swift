import AppKit
import SlopappCore
import SlopKit
import SwiftUI

struct MenuBarLabel: View {
    let store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = store.updates.count
        // MenuBarExtra labels must be a single image or text. With no updates it's a plain
        // symbol; with updates, a pre-rendered bitmap of symbol + count (the menu bar redraws
        // its items often, so nothing is drawn on demand).
        Group {
            if count == 0 {
                Image(systemName: "square.grid.2x2")
            } else {
                Image(nsImage: StatusIcon.image(count: count))
            }
        }
            .accessibilityLabel(count == 0 ? "Slopapp" : (count == 1 ? "Slopapp: 1 update" : "Slopapp: \(count) updates"))
            .onAppear {
                // The label is always alive, so it's where the window can be reopened from.
                Navigation.shared.openWindow = { [openWindow] in openWindow(id: WindowID.main) }
            }
    }
}

/// The menu bar icon: a grid of apps, filled with the update count beside it when updates wait.
@MainActor
enum StatusIcon {
    private static var cache: [Int: NSImage] = [:]

    static func image(count: Int) -> NSImage {
        if let cached = cache[count] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: count > 0 ? "square.grid.2x2.fill" : "square.grid.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let text = count > 0 ? NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.black,
        ]) : nil
        let gap: CGFloat = text == nil ? 0 : 3
        let textSize = text?.size() ?? .zero
        let height = max(symbol.size.height, 16)
        let size = NSSize(width: ceil(symbol.size.width + gap + textSize.width), height: height)
        // Rasterize once at 2x: a drawing-handler image would re-run on every menu bar redraw.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return symbol }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(x: 0, y: (height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
        text?.draw(at: NSPoint(x: symbol.size.width + gap, y: (height - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        cache[count] = image
        return image
    }
}

/// Status line → main actions → installed apps → options → footer (design system 2a).
struct MenuBarMenu: View {
    let store: Store
    let navigation: Navigation
    let info: AppInfo

    var body: some View {
        let updates = store.updates
        if store.isChecking {
            Text("Checking for updates…")
        } else if updates.isEmpty {
            Text(store.feed == nil ? "The catalog hasn't loaded yet" : "All apps are up to date")
        } else {
            Text(updates.count == 1 ? "1 update available" : "\(updates.count) updates available")
        }
        if !updates.isEmpty {
            Button(updates.count == 1 ? "Update \(updates[0].app.name)" : "Update All") { store.updateAll() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
        }
        if let hub = store.hubUpdate, let version = hub.version {
            Button("Slopapp \(version) Is Available…") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("releases"))
            }
        }

        let installed = store.installed
        if !installed.isEmpty {
            // A Section draws its own separators above and below.
            Section("Installed") {
                ForEach(installed) { item in
                    Button {
                        store.open(item)
                    } label: {
                        if let image = store.icons.menuImage(for: item) {
                            Label { Text(title(item)) } icon: { Image(nsImage: image) }
                        } else {
                            Text(title(item))
                        }
                    }
                }
            }
        } else {
            Divider()
        }

        // No shortcut: ⌘O means Install/Open the selected app in the main menu.
        Button("Open Slopapp") { navigation.bringWindowForward() }
        Button("Check for Updates") { Task { await store.refresh() } }
            .keyboardShortcut("r")
            .disabled(store.isChecking)
        HubMenuFooter(info: info)
    }

    private func title(_ item: CatalogItem) -> String {
        if let op = store.operations[item.id] { return "\(item.app.name) — \(op.label)" }
        return item.state == .updateAvailable ? "\(item.app.name) — Update Available" : item.app.name
    }
}
