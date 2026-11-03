import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SlopKit

@Suite struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 240, height: 160)

    @Test func nearMouseCentersBelowTheCursor() {
        let frame = PanelPlacement.nearMouse.frame(size: size, mouse: CGPoint(x: 700, y: 500), visibleFrame: screen)
        #expect(frame.midX == 700)
        #expect(frame.maxY == 500 - PanelPlacement.cursorGap)
    }

    @Test func nearMouseFlipsAboveWhenNoRoomBelow() {
        let frame = PanelPlacement.nearMouse.frame(size: size, mouse: CGPoint(x: 700, y: 60), visibleFrame: screen)
        #expect(frame.minY == 60 + PanelPlacement.cursorGap)
    }

    @Test func nearMouseStaysOnScreenAtTheEdge() {
        let frame = PanelPlacement.nearMouse.frame(size: size, mouse: CGPoint(x: 5, y: 500), visibleFrame: screen)
        #expect(frame.minX == 16)
        let right = PanelPlacement.nearMouse.frame(size: size, mouse: CGPoint(x: 1439, y: 500), visibleFrame: screen)
        #expect(abs(right.maxX - 1424) < 0.001)
    }

    @Test func centerSitsInTheUpperThird() {
        let frame = PanelPlacement.center.frame(size: size, mouse: .zero, visibleFrame: screen)
        #expect(frame.midX == 720)
        #expect(frame.midY == 600)
    }

    @Test(arguments: [
        (PanelPlacement.Corner.topLeading, CGPoint(x: 16, y: 900 - 16 - 160)),
        (.topTrailing, CGPoint(x: 1440 - 16 - 240, y: 900 - 16 - 160)),
        (.bottomLeading, CGPoint(x: 16, y: 16)),
        (.bottomTrailing, CGPoint(x: 1440 - 16 - 240, y: 16)),
    ])
    func corners(corner: PanelPlacement.Corner, origin: CGPoint) {
        let frame = PanelPlacement.corner(corner).frame(size: size, mouse: .zero, visibleFrame: screen)
        #expect(frame.origin == origin)
    }

    @Test func respectsAScreenThatIsNotAtTheOrigin() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let frame = PanelPlacement.corner(.bottomTrailing).frame(size: size, mouse: .zero, visibleFrame: second)
        #expect(frame.maxX == second.maxX - 16)
        #expect(frame.minY == second.minY + 16)
    }
}

@Suite struct DropFilterTests {
    @Test func keepsOnlyMatchingTypes() {
        let urls = ["a.png", "b.jpg", "notes.txt", "doc.pdf"].map { URL(fileURLWithPath: "/tmp/slopkit-test/\($0)") }
        let images = DropFilter.accepted(urls, types: [.image])
        #expect(images.map(\.lastPathComponent) == ["a.png", "b.jpg"])
        let pdfs = DropFilter.accepted(urls, types: [.pdf, .image])
        #expect(pdfs.count == 3)
    }

    @Test func itemAcceptsAnything() {
        let urls = [URL(fileURLWithPath: "/tmp/slopkit-test/whatever.zzz"), URL(fileURLWithPath: "/tmp/slopkit-test/noext")]
        #expect(DropFilter.accepted(urls, types: [.item]).count == 2)
    }
}

@Suite struct AppPathsTests {
    let base = URL(fileURLWithPath: "/Users/me/Library/Application Support")

    @Test func usesTheBundleIdentifier() {
        let url = AppPaths.applicationSupport(in: base, bundleIdentifier: "app.slopapp.awake", executableName: "Awake")
        #expect(url.path == "/Users/me/Library/Application Support/app.slopapp.awake")
    }

    @Test func fallsBackOutsideABundle() {
        let url = AppPaths.applicationSupport(in: base, bundleIdentifier: nil, executableName: "Awake")
        #expect(url.lastPathComponent == "app.slopapp.awake")
    }
}

@MainActor
@Suite struct DigitKeyTests {
    func key(_ chars: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }

    @Test func bareDigitsPick() {
        #expect(key("1").digit == 1)
        #expect(key("9").digit == 9)
    }

    @Test func otherKeysDont() {
        #expect(key("0").digit == nil)
        #expect(key("a").digit == nil)
        #expect(key("1", modifiers: .command).digit == nil)
        #expect(key("2", modifiers: .shift).digit == 2)
    }
}

@Suite @MainActor struct SettingsWindowTests {
    /// MenuFooter's Settings… finds SwiftUI's window by the identifier SwiftUI gives it
    /// (`com_apple_SwiftUI_Settings_window`) to make it key after activating the app.
    @Test func findsSwiftUIsSettingsWindowByIdentifier() {
        _ = NSApplication.shared
        let other = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        other.identifier = NSUserInterfaceItemIdentifier("main")
        other.isReleasedWhenClosed = false
        #expect(SettingsWindow.window?.identifier?.rawValue != "main")

        let settings = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        settings.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        settings.isReleasedWhenClosed = false
        #expect(SettingsWindow.window === settings)
        settings.close()
        other.close()
    }
}
