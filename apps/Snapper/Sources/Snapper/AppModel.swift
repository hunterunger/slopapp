import AppKit
import Observation
import SlopKit
import SnapperCore

/// App state and the actions every surface (menu, hotkeys, cards, editor, pins) shares.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Settings (UserDefaults)

    var afterCapture: AfterCapture {
        didSet { defaults.set(afterCapture.rawValue, forKey: Keys.afterCapture) }
    }
    var cardCorner: CardCorner {
        didSet { defaults.set(cardCorner.rawValue, forKey: Keys.cardCorner); cards.relayout() }
    }
    var autoClose: AutoClose {
        didSet { defaults.set(autoClose.rawValue, forKey: Keys.autoClose); cards.autoCloseChanged() }
    }
    var autoCloseAction: AutoCloseAction {
        didSet { defaults.set(autoCloseAction.rawValue, forKey: Keys.autoCloseAction) }
    }
    var closeAfterDragging: Bool {
        didSet { defaults.set(closeAfterDragging, forKey: Keys.closeAfterDragging) }
    }
    /// Copy and Save from a thumbnail close it (like macOS's own). Off: it stays.
    var closeAfterCopyOrSave: Bool {
        didSet { defaults.set(closeAfterCopyOrSave, forKey: Keys.closeAfterCopyOrSave) }
    }
    /// The folder chosen in Settings (nil = default).
    var chosenFolder: String? {
        didSet { defaults.set(chosenFolder, forKey: Keys.chosenFolder) }
    }
    var format: ImageFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: Keys.includeWindowShadow) }
    }
    var hideDesktopIcons: Bool {
        didSet { defaults.set(hideDesktopIcons, forKey: Keys.hideDesktopIcons) }
    }
    var showMagnifier: Bool {
        didSet { defaults.set(showMagnifier, forKey: Keys.showMagnifier) }
    }
    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }

    // MARK: State

    /// Last area captured (for Capture Previous Area).
    private(set) var lastArea: RememberedArea? {
        didSet {
            if let lastArea, let data = try? JSONEncoder().encode(lastArea) { defaults.set(data, forKey: Keys.lastArea) }
        }
    }
    /// The most recently closed capture, kept as a temporary PNG (not in memory) so
    /// "Reopen Last Capture" can bring it back.
    private(set) var lastClosed: ClosedCapture?
    @ObservationIgnored private var rememberTask: Task<Void, Never>?
    private(set) var hasPermission = false
    /// How many cards and pins are open (for enabling menu items).
    var openCards = 0
    var openPins = 0
    private(set) var isCapturing = false

    // MARK: Wiring

    @ObservationIgnored let capturer: ScreenCapturing
    @ObservationIgnored let pasteboard: PasteboardWriting
    @ObservationIgnored private(set) var cards: CardController!
    @ObservationIgnored private(set) var pins: PinController!
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let afterCapture = "afterCapture"
        static let cardCorner = "cardCorner"
        static let autoClose = "autoClose"
        static let autoCloseAction = "autoCloseAction"
        static let closeAfterDragging = "closeAfterDragging"
        static let closeAfterCopyOrSave = "closeAfterCopyOrSave"
        static let chosenFolder = "saveFolder"
        static let format = "format"
        static let includeWindowShadow = "includeWindowShadow"
        static let hideDesktopIcons = "hideDesktopIcons"
        static let showMagnifier = "showMagnifier"
        static let playSound = "playSound"
        static let lastArea = "lastArea"
    }

    private init(capturer: ScreenCapturing = ScreenCaptureKitCapturer(), pasteboard: PasteboardWriting = SystemPasteboardWriter()) {
        self.capturer = capturer
        self.pasteboard = pasteboard
        let d = UserDefaults.standard
        afterCapture = (d.object(forKey: Keys.afterCapture) as? Int).map(AfterCapture.init(rawValue:)) ?? .default
        cardCorner = d.string(forKey: Keys.cardCorner).flatMap(CardCorner.init) ?? .left
        autoClose = (d.object(forKey: Keys.autoClose) as? Int).flatMap(AutoClose.init) ?? .never
        autoCloseAction = d.string(forKey: Keys.autoCloseAction).flatMap(AutoCloseAction.init) ?? .close
        closeAfterDragging = d.object(forKey: Keys.closeAfterDragging) as? Bool ?? true
        closeAfterCopyOrSave = d.object(forKey: Keys.closeAfterCopyOrSave) as? Bool ?? true
        chosenFolder = d.string(forKey: Keys.chosenFolder)
        format = d.string(forKey: Keys.format).flatMap { ImageFormat(rawValue: $0) } ?? .png
        includeWindowShadow = d.object(forKey: Keys.includeWindowShadow) as? Bool ?? true
        hideDesktopIcons = d.object(forKey: Keys.hideDesktopIcons) as? Bool ?? true
        showMagnifier = d.object(forKey: Keys.showMagnifier) as? Bool ?? true
        playSound = d.object(forKey: Keys.playSound) as? Bool ?? true
        lastArea = d.data(forKey: Keys.lastArea).flatMap { try? JSONDecoder().decode(RememberedArea.self, from: $0) }
        cards = CardController(model: self)
        pins = PinController(model: self)
        refreshPermission()
    }

    func refreshPermission() {
        let granted = capturer.hasPermission
        if granted != hasPermission { hasPermission = granted }
    }

    // MARK: Save folder

    /// macOS's own screenshot folder, if the user set one (Screenshot app → Options).
    var systemScreenshotFolder: String? {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    }

    var saveFolder: URL {
        SaveLocation.resolve(override: Diagnostics.saveDirectory, chosen: chosenFolder,
                             systemScreenshotFolder: systemScreenshotFolder,
                             home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var saveFolderIsOverridden: Bool { Diagnostics.saveDirectory != nil }

    // MARK: Capturing

    func capture(_ mode: CaptureMode, started: TimeInterval = Diagnostics.now()) {
        refreshPermission()
        guard hasPermission else {
            Diagnostics.record("capture blocked reason=noPermission mode=\(mode.rawValue)")
            PermissionWindow.show()
            return
        }
        if let overlay = RegionOverlay.current {
            // The same shortcut again while selecting switches mode, like pressing Space.
            if mode == .window { overlay.setMode(.window) } else if mode == .area { overlay.setMode(.area) }
            return
        }
        guard !isCapturing else {
            // The previous capture is still wrapping up (e.g. Esc a moment ago): try again
            // shortly instead of dropping the request.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, Diagnostics.now() - started < 1.5 else { return }
                self.capture(mode, started: started)
            }
            return
        }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            switch mode {
            case .area, .window:
                await captureWithOverlay(mode == .window ? .window : .area, started: started)
            case .fullScreen:
                await captureFullScreen(started: started)
            case .previousArea:
                await capturePreviousArea(started: started)
            }
        }
    }

    private var exclusions: CaptureExclusions {
        CaptureExclusions(keepOwnWindows: pins.windowNumbers.union(TestScene.windowNumbers), hideDesktopIcons: hideDesktopIcons,
                          onlyWindows: TestScene.isActive ? pins.windowNumbers.union(TestScene.windowNumbers) : nil)
    }

    private func captureWithOverlay(_ mode: RegionOverlay.Mode, started: TimeInterval) async {
        let overlay = RegionOverlay(capturer: capturer, mode: mode, options: .init(
            showsMagnifier: showMagnifier, exclusions: exclusions, log: Diagnostics.record))
        let result = await overlay.run(started: started)
        let finished = overlay.finishedAt ?? Diagnostics.now()
        switch result {
        case .area(let displayID, let rect, let image):
            lastArea = RememberedArea(displayID: displayID, rect: rect)
            deliver(image, scale: scaleOf(displayID), displayID: displayID, started: finished, kind: "area")
        case .window(let window):
            if let only = exclusions.onlyWindows, !only.contains(window.id) {
                Diagnostics.record("window capture refused: test mode allows only the test scene")
                return
            }
            do {
                let screen = screenContaining(quartzRect: window.frame)
                let bare = try await capturer.captureWindow(window.id, includeShadow: false)
                let scale = CGFloat(bare.width) / max(window.frame.width, 1)
                let image = includeWindowShadow ? (WindowShadow.apply(to: bare, scale: scale) ?? bare) : bare
                deliver(image, scale: scale > 0.5 ? scale.rounded() : (screen?.backingScaleFactor ?? 2), displayID: screen?.displayID, started: finished, kind: "window")
            } catch {
                report(error)
            }
        case .cancelled:
            Diagnostics.record("capture cancelled")
            Memory.relieveSoon()
        case .failed(let error):
            report(error)
        }
    }

    private func captureFullScreen(started: TimeInterval) async {
        guard let screen = NSScreen.underPointer else { return }
        do {
            let images = try await capturer.snapshot(displays: [screen.displayID], excluding: exclusions)
            guard let image = images[screen.displayID] else { throw CaptureError.displayNotFound }
            deliver(image, scale: screen.backingScaleFactor, displayID: screen.displayID, started: started, kind: "fullScreen")
        } catch {
            report(error)
        }
    }

    private func capturePreviousArea(started: TimeInterval) async {
        guard let area = lastArea, let screen = NSScreen.screens.first(where: { $0.displayID == area.displayID }),
              let rect = area.rect(within: CGRect(origin: .zero, size: screen.frame.size)) else {
            Diagnostics.record("previous area missing; starting area capture")
            await captureWithOverlay(.area, started: started)
            return
        }
        do {
            let images = try await capturer.snapshot(displays: [screen.displayID], excluding: exclusions)
            guard let full = images[screen.displayID] else { throw CaptureError.displayNotFound }
            let scale = CGFloat(full.width) / screen.frame.width
            let pixels = ScreenCoordinates.pixelRect(local: rect, screenSize: screen.frame.size, scale: scale)
            guard let image = full.cropping(to: pixels) else { throw CaptureError.displayNotFound }
            deliver(image, scale: scale, displayID: screen.displayID, started: started, kind: "previousArea")
        } catch {
            report(error)
        }
    }

    private func scaleOf(_ displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
    }

    private func screenContaining(quartzRect: CGRect) -> NSScreen? {
        let appKit = ScreenCoordinates.flip(quartzRect, primaryHeight: NSScreen.primaryHeight)
        let center = CGPoint(x: appKit.midX, y: appKit.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main
    }

    private func report(_ error: Error) {
        Diagnostics.record("capture failed error=\(error)")
        if case CaptureError.noPermission = error {
            PermissionWindow.show()
            return
        }
        refreshPermission()
        if !hasPermission {
            PermissionWindow.show()
        } else {
            HUD.show("Couldn't capture the screen. Try again.", systemImage: "exclamationmark.triangle")
        }
    }

    /// Hands a fresh capture to the after-capture actions.
    private func deliver(_ image: CGImage, scale: CGFloat, displayID: CGDirectDisplayID?, started: TimeInterval, kind: String) {
        if playSound { Output.playShutter() }
        let item = CaptureItem(image: image, scale: scale, displayID: displayID)
        item.sourceName = item.fileBaseName
        if afterCapture.contains(.showCard) {
            cards.add(item)
            Diagnostics.record("card shown kind=\(kind) ms=\(Diagnostics.milliseconds(since: started)) pixels=\(item.pixelSizeDescription)")
        } else {
            Diagnostics.record("captured kind=\(kind) ms=\(Diagnostics.milliseconds(since: started)) pixels=\(item.pixelSizeDescription)")
        }
        item.prepareTemporaryFile(format: format)
        Memory.relieveSoon()
        if afterCapture.contains(.copy) {
            copy(item, closeCard: false)
        }
        if afterCapture.contains(.save) {
            save(item, closeCard: false)
        }
        if !afterCapture.contains(.showCard) {
            remember(item)
        }
    }

    // MARK: Actions on a capture

    func copy(_ item: CaptureItem, closeCard: Bool = true) {
        pasteboard.write(item.image, size: item.size)
        HUD.show("Copied", systemImage: "doc.on.doc")
        Diagnostics.record("copied pixels=\(item.pixelSizeDescription)")
        if closeCard, closeAfterCopyOrSave { cards.close(item) }
    }

    func save(_ item: CaptureItem, closeCard: Bool = true) {
        let folder = saveFolder
        Task {
            do {
                let previous = item.savedURL ?? item.lastSavedURL
                let url = try await Output.save(item.image, format: format, to: folder, date: item.createdAt, replacing: previous)
                let again = url == previous
                item.savedURL = url
                item.lastSavedURL = url
                HUD.show(again ? "Updated “\(url.lastPathComponent)” in \(folder.lastPathComponent)"
                                 : "Saved “\(url.lastPathComponent)” to \(folder.lastPathComponent)",
                         systemImage: "square.and.arrow.down", duration: .seconds(2.5))
                Diagnostics.record("saved file=\(url.lastPathComponent)")
                if closeCard, closeAfterCopyOrSave { cards.close(item) }
            } catch {
                HUD.show(error.localizedDescription, systemImage: "exclamationmark.triangle", duration: .seconds(4))
            }
        }
    }

    func saveAs(_ item: CaptureItem) {
        Task {
            if let url = await Output.saveAs(item.image, suggestedName: item.fileBaseName, format: format, folder: saveFolder) {
                item.savedURL = url
                HUD.show("Saved \(url.lastPathComponent)", systemImage: "square.and.arrow.down")
                cards.close(item)
            }
        }
    }

    func annotate(_ item: CaptureItem) {
        cards.close(item, remember: false)
        EditorWindowController.open(item, model: self)
    }

    func pin(_ item: CaptureItem) {
        cards.close(item, remember: false)
        pins.pin(item)
    }

    func showInFinder(_ item: CaptureItem) {
        guard let url = item.savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Keeps a closed capture so "Reopen Last Capture" can bring it back. The pixels go to a
    /// temporary file in the background so idle memory drops back to baseline.
    func remember(_ item: CaptureItem) {
        let image = item.image, scale = item.scale, displayID = item.displayID, date = item.createdAt
        if !cards.contains(item), !pins.contains(item), !EditorWindowController.isEditing(item) {
            item.discardTemporaryFile()
        }
        rememberTask?.cancel()
        rememberTask = Task {
            let url = await Task.detached(priority: .utility) { ClosedCapture.write(image) }.value
            guard !Task.isCancelled, let url else { return }
            if let old = lastClosed { try? FileManager.default.removeItem(at: old.url) }
            lastClosed = ClosedCapture(url: url, scale: scale, displayID: displayID, createdAt: date)
            Memory.relieveSoon()
        }
    }

    func reopenLastCapture() {
        guard let closed = lastClosed, let image = closed.load() else { return }
        lastClosed = nil
        try? FileManager.default.removeItem(at: closed.url)
        cards.add(CaptureItem(image: image, scale: closed.scale, displayID: closed.displayID, createdAt: closed.createdAt))
    }

    // MARK: Images from elsewhere

    /// The image on the clipboard, if any (read only when the user asks for it).
    func clipboardImage() -> CaptureItem? {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else { return nil }
        let item = Self.item(from: image)
        item?.sourceName = "Clipboard Image"
        return item
    }

    static func item(from image: NSImage) -> CaptureItem? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = image.size.width > 0 ? CGFloat(cg.width) / image.size.width : 1
        return CaptureItem(image: cg, scale: max(1, scale.rounded()), displayID: nil)
    }

    func annotateClipboard() {
        guard let item = clipboardImage() else {
            HUD.show("There's no image on the clipboard", systemImage: "photo")
            return
        }
        EditorWindowController.open(item, model: self)
    }

    func pinClipboard() {
        guard let item = clipboardImage() else {
            HUD.show("There's no image on the clipboard", systemImage: "photo")
            return
        }
        pins.pin(item)
    }

    /// "Open Image…": choose a picture file to annotate or pin.
    func chooseImage(then action: @escaping (CaptureItem) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url), let item = Self.item(from: image) else { return }
        item.sourceName = url.deletingPathExtension().lastPathComponent
        action(item)
    }
}
