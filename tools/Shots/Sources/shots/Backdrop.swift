import AppKit
import ShotsCore

/// A full-screen window of our own behind the app being captured, so translucent materials
/// sample our backdrop instead of the owner's desktop and windows. It never takes clicks or
/// focus, sits at the normal window level (the app's windows come in front of it), and goes
/// away when the script kills it (or after `lifetime`, as a safety net).
@MainActor
enum Backdrop {
    static let lifetime: TimeInterval = 15 * 60

    static func run(palette: BackdropPalette, ready: URL?) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.screens.first else { throw Failure("no screen") }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.animationBehavior = .none
        window.title = "Slopapp Shots Backdrop"
        window.contentView = BackdropView(palette: palette)
        window.orderFrontRegardless()

        for signal in [SIGTERM, SIGINT, SIGHUP] {
            Foundation.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { exit(0) }
            source.resume()
            sources.append(source)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { exit(0) }
        if let ready {
            // Once it's drawn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                try? Data("\(window.windowNumber)\n".utf8).write(to: ready)
            }
        }
        app.run()
    }

    private static var sources: [any DispatchSourceSignal] = []
}

final class BackdropView: NSView {
    let palette: BackdropPalette

    init(palette: BackdropPalette) {
        self.palette = palette
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        Render.backdrop(palette, in: context, size: bounds.size)
    }
}
