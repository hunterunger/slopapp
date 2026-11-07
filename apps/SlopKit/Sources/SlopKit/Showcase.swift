import AppKit

/// Store screenshots (docs/screenshots.md). `scripts/shots.sh` launches an app with
/// `SLOP_SHOWCASE=<scene>`; the app loads synthetic fixtures, opens the scene's windows, then
/// calls `Showcase.ready(_:)`. SlopKit does the shared part:
///
/// - **Environment**: `SLOP_SHOWCASE` (scene id), `SLOP_SHOWCASE_SIZE` (`1280x800`, the main
///   window's content size from `showcase.json`), `SLOP_SHOWCASE_READY` (where to write the ready
///   file), `SLOP_SHOWCASE_DATA` (a scratch folder with the app's fixtures), and
///   `SLOP_SHOWCASE_SETTLE` (milliseconds to wait for layout and materials, default 700).
/// - **Placement**: `place(_:size:)` sizes a window and centres it on the primary screen,
///   where the capture backdrop is.
/// - **Ready file**: JSON with each window's id, frame and kind, so the script captures exactly
///   those windows (`screencapture -l<id>`) and nothing else.
///
/// An app's scene code is usually one `switch` in `applicationDidFinishLaunching`:
///
///     if let scene = Showcase.scene {
///         switch scene {
///         case "hero": openEditor(fixture); Showcase.ready { EditorWindowController.front?.window }
///         default: Showcase.fail("unknown scene \(scene)")
///         }
///     }
public struct ShowcaseRequest: Equatable, Sendable {
    public var scene: String
    /// The main window's content size, in points.
    public var size: CGSize?
    public var readyFile: URL?
    public var dataDirectory: URL?
    /// How long to let layout, images and glass settle before signalling ready.
    public var settle: Duration

    public static let defaultSettle: Duration = .milliseconds(700)

    public init(scene: String, size: CGSize? = nil, readyFile: URL? = nil, dataDirectory: URL? = nil,
                settle: Duration = ShowcaseRequest.defaultSettle) {
        self.scene = scene
        self.size = size
        self.readyFile = readyFile
        self.dataDirectory = dataDirectory
        self.settle = settle
    }

    /// Nil unless `SLOP_SHOWCASE` names a scene.
    public static func parse(_ environment: [String: String]) -> ShowcaseRequest? {
        guard let scene = environment["SLOP_SHOWCASE"]?.trimmingCharacters(in: .whitespaces), !scene.isEmpty,
              scene != "0" else { return nil }
        let path: (String) -> URL? = { key in
            environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        }
        let settle = environment["SLOP_SHOWCASE_SETTLE"].flatMap(Int.init).map { Duration.milliseconds(max(0, $0)) }
        return ShowcaseRequest(
            scene: scene,
            size: environment["SLOP_SHOWCASE_SIZE"].flatMap(parseSize),
            readyFile: path("SLOP_SHOWCASE_READY"),
            dataDirectory: path("SLOP_SHOWCASE_DATA"),
            settle: settle ?? defaultSettle
        )
    }

    /// "1280x800" (or "1280×800", "1280,800") → 1280 × 800. Nil for anything else.
    public static func parseSize(_ text: String) -> CGSize? {
        let parts = text.split(whereSeparator: { "x×X,".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width >= 1, height >= 1, width <= 10_000, height <= 10_000 else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// What the ready file says: the windows to capture, back to front, in Quartz global
/// coordinates (origin top-left of the primary screen, points).
public struct ShowcaseReady: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// A titled window.
            case window
            /// A borderless panel, card or HUD (glass draws its own edge).
            case panel
            /// The app's menu bar icon, as `image` (the composer puts it in a synthetic menu bar).
            case statusItem
        }

        public var id: UInt32
        public var kind: Kind
        public var title: String
        public var frame: Rect
        /// A PNG drawn by the app instead of a window to capture (the menu bar icon: macOS
        /// draws status items itself, outside the app's windows).
        public var image: String?

        public init(id: UInt32, kind: Kind, title: String, frame: Rect, image: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.frame = frame
            self.image = image
        }
    }

    /// A rect that encodes as `{"x":…, "y":…, "width":…, "height":…}`.
    public struct Rect: Codable, Equatable, Sendable {
        public var x, y, width, height: Double

        public init(_ rect: CGRect) {
            x = rect.minX
            y = rect.minY
            width = rect.width
            height = rect.height
        }

        public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    public var scene: String
    /// "light" or "dark": what the app actually drew in.
    public var appearance: String
    /// Backing scale of the screen the windows are on (captures are this many pixels per point).
    public var scale: Double
    public var screen: Rect
    public var windows: [Window]
    /// Set when the scene couldn't be shown; the script stops with this message.
    public var error: String?

    public init(scene: String, appearance: String, scale: Double, screen: Rect, windows: [Window], error: String? = nil) {
        self.scene = scene
        self.appearance = appearance
        self.scale = scale
        self.screen = screen
        self.windows = windows
        self.error = error
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Window geometry for showcase scenes. Pure, so it's tested.
public enum ShowcaseLayout {
    /// A window frame of `size` centred in `visibleFrame` (AppKit coordinates), on whole points,
    /// shrunk to fit with a margin when the screen is too small.
    public static func centered(_ size: CGSize, in visibleFrame: CGRect, margin: CGFloat = 24) -> CGRect {
        let width = min(size.width, visibleFrame.width - 2 * margin)
        let height = min(size.height, visibleFrame.height - 2 * margin)
        return CGRect(
            x: (visibleFrame.midX - width / 2).rounded(),
            y: (visibleFrame.midY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// `frame` moved sideways, if it must, so the pointer isn't over it: wherever the owner's
    /// pointer rests mustn't leave a hover state in the shot. (The composer re-centres windows,
    /// so where it ends up on screen doesn't show.)
    public static func avoiding(_ pointer: CGPoint, _ frame: CGRect, in visibleFrame: CGRect, gap: CGFloat = 24) -> CGRect {
        guard frame.insetBy(dx: -gap, dy: -gap).contains(pointer) else { return frame }
        let left = frame.offsetBy(dx: (pointer.x - gap - frame.maxX).rounded(.down), dy: 0)
        let right = frame.offsetBy(dx: (pointer.x + gap - frame.minX).rounded(.up), dy: 0)
        if left.minX >= visibleFrame.minX { return left }
        if right.maxX <= visibleFrame.maxX { return right }
        // No room sideways (a window as wide as the screen): above or below instead.
        let below = frame.offsetBy(dx: 0, dy: (pointer.y - gap - frame.maxY).rounded(.down))
        return below.minY >= visibleFrame.minY ? below : frame.offsetBy(dx: 0, dy: (pointer.y + gap - frame.minY).rounded(.up))
    }

    /// The frame of a window whose content is `contentSize`, given the window's frame and
    /// content rects now (the title bar and toolbar stay as they are).
    public static func frameSize(forContent contentSize: CGSize, frame: CGRect, contentRect: CGRect) -> CGSize {
        CGSize(width: contentSize.width + (frame.width - contentRect.width),
               height: contentSize.height + (frame.height - contentRect.height))
    }
}

@MainActor
public enum Showcase {
    /// The scene requested in the environment, if any.
    public static let request: ShowcaseRequest? = ShowcaseRequest.parse(ProcessInfo.processInfo.environment)

    /// The scene id, or nil in normal use.
    public static var scene: String? { request?.scene }
    public static var isActive: Bool { request != nil }

    /// The scene's scratch folder (fixtures copied by the script), created on demand.
    public static var dataDirectory: URL {
        let url = request?.dataDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("slopapp-showcase", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The screen the capture backdrop covers: the primary one (with the menu bar).
    public static var screen: NSScreen? { NSScreen.screens.first }

    /// Sizes `window` (content size `size`, else the request's size, else as it is) and centres
    /// it on the primary screen. Panels and windows alike.
    public static func place(_ window: NSWindow, size: CGSize? = nil) {
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var frameSize = window.frame.size
        if let content = size ?? request?.size {
            frameSize = ShowcaseLayout.frameSize(forContent: content, frame: window.frame,
                                                 contentRect: window.contentRect(forFrameRect: window.frame))
        }
        let frame = ShowcaseLayout.avoiding(NSEvent.mouseLocation, ShowcaseLayout.centered(frameSize, in: visible), in: visible)
        window.setFrame(frame, display: true)
    }

    /// Activates the app and brings `window` to the front as the key window, so it's drawn in
    /// its active state.
    public static func bringToFront(_ window: NSWindow) {
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Waits until `windows` returns at least one visible window (up to `timeout`), lets the
    /// scene settle, and writes the ready file. Windows are listed back to front. Menu bar apps
    /// pass their menu bar icon's symbol as `statusItem`; it's drawn for the composer's
    /// synthetic menu bar. With `arrange` (the default) the front
    /// window is sized (`SLOP_SHOWCASE_SIZE`), centred and made key first; scenes that lay out
    /// several windows themselves pass false.
    public static func ready(statusItem: String? = nil, arrange: Bool = true, timeout: Duration = .seconds(10),
                             _ windows: @escaping @MainActor () -> [NSWindow?]) {
        guard let request else { return }
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            var found: [NSWindow] = []
            while clock.now < deadline {
                found = windows().compactMap { $0 }.filter(\.isVisible)
                if !found.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let front = found.last else {
                fail("scene \(request.scene): no window appeared within \(timeout)")
                return
            }
            if arrange {
                place(front)
                bringToFront(front)
            }
            // The pointer rests outside the window (see `place`); keep it from mattering at all.
            for window in found { window.ignoresMouseEvents = true }
            try? await Task.sleep(for: request.settle)
            // Windows may have been replaced while settling: ask again.
            let final = windows().compactMap { $0 }.filter(\.isVisible)
            write(ready(for: final.isEmpty ? found : final, statusItem: statusItem, scene: request.scene))
        }
    }

    /// Reports that the scene can't be shown (the script stops with `message`).
    public static func fail(_ message: String) {
        guard let request else { return }
        let ready = ShowcaseReady(scene: request.scene, appearance: appearanceName, scale: 2,
                                  screen: .init(.zero), windows: [], error: message)
        write(ready)
    }

    /// "light" or "dark", as the app draws now.
    public static var appearanceName: String {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
    }

    /// Menu bar icon size: the menu bar's height, the symbol at the menu bar's size.
    public static let statusItemHeight: CGFloat = 24
    static let statusItemPadding: CGFloat = 6

    /// Draws `symbol` the way a status item shows it (template, 15 pt) into a 4x PNG at `url`
    /// (4x, so it stays crisp in a zoomed-in shot).
    /// Returns its size in points.
    @discardableResult
    public static func drawStatusItem(_ symbol: String, to url: URL) -> CGSize? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let size = CGSize(width: (image.size.width + 2 * statusItemPadding).rounded(.up), height: statusItemHeight)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 4), pixelsHigh: Int(size.height * 4),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = CGRect(x: ((size.width - image.size.width) / 2).rounded(), y: ((size.height - image.size.height) / 2).rounded(),
                          width: image.size.width, height: image.size.height)
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return size
    }

    private static func ready(for windows: [NSWindow], statusItem: String?, scene: String) -> ShowcaseReady {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // Windows that aren't on screen have no window server number (≤ 0): nothing to capture.
        func info(_ window: NSWindow, kind: ShowcaseReady.Window.Kind) -> ShowcaseReady.Window? {
            guard window.windowNumber > 0, let id = UInt32(exactly: window.windowNumber) else { return nil }
            return ShowcaseReady.Window(
                id: id, kind: kind, title: window.title,
                frame: .init(ScreenCoordinates.flip(window.frame, primaryHeight: primaryHeight))
            )
        }
        var list = windows.compactMap { info($0, kind: $0.styleMask.contains(.titled) ? .window : .panel) }
        if let statusItem, let file = request?.readyFile?.appendingPathExtension("status.png"),
           let size = drawStatusItem(statusItem, to: file) {
            // Where macOS would put it doesn't matter: the composer places it in its menu bar.
            list.append(ShowcaseReady.Window(id: 0, kind: .statusItem, title: "",
                                             frame: .init(CGRect(origin: .zero, size: size)), image: file.path))
        }
        let screenFrame = screen.map { ScreenCoordinates.flip($0.frame, primaryHeight: primaryHeight) } ?? .zero
        return ShowcaseReady(scene: scene, appearance: appearanceName,
                             scale: Double(screen?.backingScaleFactor ?? 2),
                             screen: .init(screenFrame), windows: list)
    }

    private static func write(_ ready: ShowcaseReady) {
        guard let file = request?.readyFile, let data = try? ready.encoded() else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Write then rename, so the script never reads half a file.
        let temporary = file.appendingPathExtension("partial")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temporary, to: file)
        } catch {
            NSLog("Showcase: couldn't write the ready file: \(error.localizedDescription)")
        }
    }
}
