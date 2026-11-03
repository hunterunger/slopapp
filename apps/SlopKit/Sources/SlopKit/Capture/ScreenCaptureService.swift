import AppKit
import ScreenCaptureKit

// Screen capture for Slopapp apps (Snapper, Ruler, Dropper, Snip): a ScreenCaptureKit
// service behind a protocol, frozen display images, the on-screen window list, and the
// region overlay (RegionOverlay.swift). Needs Screen Recording permission (`Permission`).

/// What to leave out of a screen capture.
public struct CaptureExclusions: Sendable {
    /// Our own windows to keep in the capture anyway (e.g. pinned images).
    public var keepOwnWindows: Set<CGWindowID>
    /// Leave out Finder's desktop icons.
    public var hideDesktopIcons: Bool
    /// If set, capture only these windows (ours or not) and nothing else. Test mode uses it
    /// so captures can only ever contain the generated test scene.
    public var onlyWindows: Set<CGWindowID>?

    public init(keepOwnWindows: Set<CGWindowID> = [], hideDesktopIcons: Bool = false, onlyWindows: Set<CGWindowID>? = nil) {
        self.keepOwnWindows = keepOwnWindows
        self.hideDesktopIcons = hideDesktopIcons
        self.onlyWindows = onlyWindows
    }
}

/// Takes screenshots. The real one uses ScreenCaptureKit; tests and previews can fake it.
@MainActor
public protocol ScreenCapturing: AnyObject {
    /// Whether macOS lets this process record the screen.
    var hasPermission: Bool { get }
    /// Full-resolution images of whole displays, keyed by display ID. Our own windows
    /// (except `keepOwnWindows`) never appear in them.
    func snapshot(displays: [CGDirectDisplayID], excluding: CaptureExclusions) async throws -> [CGDirectDisplayID: CGImage]
    /// One window on its own (even if covered), optionally with its shadow on transparency.
    func captureWindow(_ id: CGWindowID, includeShadow: Bool) async throws -> CGImage
}

public enum CaptureError: LocalizedError {
    case noPermission
    case displayNotFound
    case windowNotFound

    public var errorDescription: String? {
        switch self {
        case .noPermission: "Screen Recording permission is off."
        case .displayNotFound: "That display isn't available anymore."
        case .windowNotFound: "That window closed before it could be captured."
        }
    }
}

/// ScreenCaptureKit-backed capturer (macOS 14+: `SCScreenshotManager`).
@MainActor
public final class ScreenCaptureKitCapturer: ScreenCapturing {
    public init() {}

    public var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    public func snapshot(displays: [CGDirectDisplayID], excluding: CaptureExclusions) async throws -> [CGDirectDisplayID: CGImage] {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filterParts = Self.filterParts(content: content, excluding: excluding)
        var images: [CGDirectDisplayID: CGImage] = [:]
        for id in displays {
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter: SCContentFilter
            if let only = excluding.onlyWindows {
                // Every app out, then just these windows back in. (A display filter that
                // *includes* windows crops to their bounds instead of keeping the display's
                // coordinates.)
                filter = SCContentFilter(display: display, excludingApplications: content.applications,
                                         exceptingWindows: content.windows.filter { only.contains($0.windowID) })
            } else {
                filter = SCContentFilter(display: display, excludingApplications: filterParts.apps, exceptingWindows: filterParts.keep)
            }
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int((CGFloat(display.width) * scale).rounded())
            config.height = Int((CGFloat(display.height) * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            if let only = excluding.onlyWindows {
                // The filter can't remove surfaces no app owns (menu bar, clock), so mask
                // everything outside the allowed windows. Fails closed: no mask, no image.
                let pixelScale = CGFloat(image.width) / max(CGFloat(display.width), 1)
                // Never keep the menu bar strip, even where an allowed window lies under it.
                let menuBar = Self.menuBarHeight(displayID: id) * pixelScale
                let allowed = CGRect(x: 0, y: menuBar, width: CGFloat(image.width), height: CGFloat(image.height) - menuBar)
                let keep = content.windows.filter { only.contains($0.windowID) }.map { window in
                    CGRect(x: (window.frame.minX - display.frame.minX) * pixelScale,
                           y: (window.frame.minY - display.frame.minY) * pixelScale,
                           width: window.frame.width * pixelScale, height: window.frame.height * pixelScale)
                        .intersection(allowed)
                }.filter { !$0.isNull && !$0.isEmpty }
                guard let masked = PrivacyMask.apply(to: image, keeping: keep) else { throw CaptureError.displayNotFound }
                image = masked
            }
            images[id] = image
        }
        guard !images.isEmpty else { throw CaptureError.displayNotFound }
        return images
    }

    /// The menu bar's height on a display, in points (at least the standard bar, even when
    /// it's set to hide).
    private static func menuBarHeight(displayID: CGDirectDisplayID) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return 40 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness, screen.safeAreaInsets.top, 24)
    }

    public func captureWindow(_ id: CGWindowID, includeShadow: Bool) async throws -> CGImage {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = !includeShadow
        config.showsCursor = false
        config.captureResolution = .best
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Apps to leave out (us, and Finder when hiding desktop icons) and the windows of those
    /// apps to keep anyway (our pins, Finder's real windows). Excluding whole apps also
    /// leaves out windows that appear after this list was made, like the overlay itself.
    private static func filterParts(content: SCShareableContent, excluding: CaptureExclusions) -> (apps: [SCRunningApplication], keep: [SCWindow]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [SCRunningApplication] = []
        var keep: [SCWindow] = []
        if let own = content.applications.first(where: { $0.processID == ownPID }) {
            apps.append(own)
            keep += content.windows.filter { $0.owningApplication?.processID == ownPID && excluding.keepOwnWindows.contains($0.windowID) }
        }
        if excluding.hideDesktopIcons, let finder = content.applications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            apps.append(finder)
            keep += content.windows.filter {
                $0.owningApplication?.processID == finder.processID
                    && !DesktopIcons.isDesktopIconWindow(bundleID: finder.bundleIdentifier, layer: $0.windowLayer)
            }
        }
        return (apps, keep)
    }
}

/// The on-screen window list, front to back, from the window server. Frames and owners
/// don't need Screen Recording permission.
public enum WindowList {
    public static func onScreen() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(
                id: id,
                ownerPID: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
                frame: bounds
            )
        }
    }
}

extension NSScreen {
    /// The display ID (`CGDirectDisplayID`) ScreenCaptureKit and Quartz use for this screen.
    public var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// The screen under the pointer.
    public static var underPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// The primary display's height, for flipping between AppKit and Quartz coordinates.
    public static var primaryHeight: CGFloat {
        screens.first?.frame.height ?? 0
    }
}

/// One display frozen at a moment: its image plus everything needed to map points to pixels.
/// Ruler-style tools read `pixels` for edge detection; capture tools crop `image`.
public struct FrozenDisplay: @unchecked Sendable {
    public let displayID: CGDirectDisplayID
    /// The screen's frame in AppKit global coordinates (points).
    public let frame: CGRect
    /// The full-resolution image of the display (top-left origin).
    public let image: CGImage

    public init(displayID: CGDirectDisplayID, frame: CGRect, image: CGImage) {
        self.displayID = displayID
        self.frame = frame
        self.image = image
    }

    /// Pixels per point (2 on Retina). Measured from the image, so it's always right.
    public var scale: CGFloat { CGFloat(image.width) / max(frame.width, 1) }

    /// A screen-local rect (AppKit points) as image pixels.
    public func pixelRect(local rect: CGRect) -> CGRect {
        ScreenCoordinates.pixelRect(local: rect, screenSize: frame.size, scale: scale)
    }

    /// A screen-local point (AppKit points) as an image pixel position.
    public func pixelPoint(local point: CGPoint) -> CGPoint {
        ScreenCoordinates.pixelPoint(local: point, screenSize: frame.size, scale: scale)
    }

    /// The pixels inside a screen-local rect, or nil if it's off the display.
    public func crop(local rect: CGRect) -> CGImage? {
        image.cropping(to: pixelRect(local: rect))
    }

    /// Decoded RGBA pixels (made on demand; tens of MB for a 5K display).
    public func pixels() -> PixelBuffer? { PixelBuffer(image) }
}

extension ScreenCapturing {
    /// Freezes the given screens (default: all). Same exclusions as `snapshot`.
    public func freeze(_ screens: [NSScreen] = NSScreen.screens, excluding: CaptureExclusions = .init()) async throws -> [FrozenDisplay] {
        let images = try await snapshot(displays: screens.map(\.displayID), excluding: excluding)
        return screens.compactMap { screen in
            images[screen.displayID].map { FrozenDisplay(displayID: screen.displayID, frame: screen.frame, image: $0) }
        }
    }
}
