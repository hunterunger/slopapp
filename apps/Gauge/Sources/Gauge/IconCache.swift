import AppKit

/// App icons for process rows, loaded once per app and kept small.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]
    private static let size = NSSize(width: 16, height: 16)

    static func icon(forApp path: String?) -> NSImage {
        let key = path ?? ""
        if let icon = icons[key] { return icon }
        let source = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .unixExecutable)
        // A small bitmap at 1x and 2x: Finder's icons carry representations up to 1024 px,
        // and scaling those down for every row, every second, adds up.
        let icon = NSImage(size: size)
        for scale in [1, 2] as [CGFloat] {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                             pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            icon.addRepresentation(rep)
        }
        if icons.count > 200 { icons.removeAll() }
        icons[key] = icon
        return icon
    }

    /// The app's name as Finder shows it (localised), falling back to the bundle name.
    private static var names: [String: String] = [:]

    static func displayName(forApp path: String, fallback: String) -> String {
        if let name = names[path] { return name }
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        if name.isEmpty { name = fallback }
        names[path] = name
        return name
    }
}
