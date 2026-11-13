import AppKit
import AVKit
import SlopKit
import SnapperCore

/// Trims a recording: the video in a window with the system's own trimming bar (drag the
/// yellow handles, play, Trim or Cancel; Return and Esc work). Trim keeps the part between
/// the handles without re-encoding, and the thumbnail (and history) get the shorter video.
/// The untrimmed recording is kept, so "Restore Untrimmed Recording" can undo it.
@MainActor
final class TrimWindowController: NSObject, NSWindowDelegate {
    private static var open: [UUID: TrimWindowController] = [:]

    private let item: CaptureItem
    private unowned let model: AppModel
    private let window: NSWindow
    private let playerView = AVPlayerView()
    private var finished = false

    static func show(_ item: CaptureItem, model: AppModel) {
        guard let media = item.media, !media.isGIF else { return }
        if let existing = open[item.id] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = TrimWindowController(item: item, model: model, url: media.url)
        open[item.id] = controller
        controller.present()
    }

    static func isTrimming(_ item: CaptureItem) -> Bool { open[item.id] != nil }

    /// The front trim window's controller (test hooks).
    static var front: TrimWindowController? { open.values.first { $0.window.isKeyWindow } ?? open.values.first }

    private init(item: CaptureItem, model: AppModel, url: URL) {
        self.item = item
        self.model = model
        let size = Self.windowSize(for: item.size)
        // A plain titled window: the video sits under the title bar, never behind it (a
        // recording of a window has its own title bar, which mustn't read as ours).
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Trim \(item.fileBaseName)"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 480, height: 300)
        window.delegate = self
        playerView.controlsStyle = .inline
        playerView.showsFrameSteppingButtons = true
        playerView.showsSharingServiceButton = false
        playerView.allowsPictureInPicturePlayback = false
        // No Live Text over the frames: it adds unlabeled text areas and nothing to trim.
        playerView.allowsVideoFrameAnalysis = false
        let player = AVPlayer(url: url)
        playerView.player = player
        playerView.setAccessibilityLabel("Recording")
        // The picture on its own above, the system's trimming bar in a strip below it, so the
        // bar never covers the video. (The player view's own small picture behind the bar is
        // hidden by its overlay.)
        let picture = PlayerLayerView(player: player)
        let shade = WindowBackgroundView()
        playerView.contentOverlayView?.addSubview(shade)
        shade.frame = playerView.contentOverlayView?.bounds ?? .zero
        shade.autoresizingMask = [.width, .height]
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        picture.frame = CGRect(x: 0, y: Self.barHeight, width: size.width, height: size.height - Self.barHeight)
        picture.autoresizingMask = [.width, .height]
        playerView.frame = CGRect(x: 0, y: 0, width: size.width, height: Self.barHeight)
        playerView.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(picture)
        content.addSubview(playerView)
        window.contentView = content
        window.center()
    }

    /// The strip under the picture for the trimming bar.
    static let barHeight: CGFloat = 76

    /// The video at up to 960 × 600 points plus the trimming bar's strip, never smaller than
    /// the bar needs.
    static func windowSize(for video: CGSize) -> CGSize {
        let limit = CGSize(width: 960, height: 600)
        let scale = min(1, limit.width / max(video.width, 1), limit.height / max(video.height, 1))
        return CGSize(width: max(560, (video.width * scale).rounded()), height: max(240, (video.height * scale).rounded()) + barHeight)
    }

    private func present() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await beginTrimming() }
    }

    private func beginTrimming() async {
        // The bar can start once the player has the asset ready.
        for _ in 0..<50 where !playerView.canBeginTrimming {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard playerView.canBeginTrimming else {
            Diagnostics.record("trim unavailable")
            return
        }
        Diagnostics.record("trim window shown")
        let result = await playerView.beginTrimming()
        trimmingEnded(result)
    }

    private func trimmingEnded(_ result: AVPlayerViewTrimResult) {
        guard result == .okButton, let playerItem = playerView.player?.currentItem else {
            close()
            return
        }
        let duration = item.media?.duration ?? playerItem.duration.seconds
        let start = playerItem.reversePlaybackEndTime.isNumeric ? playerItem.reversePlaybackEndTime.seconds : 0
        let end = playerItem.forwardPlaybackEndTime.isNumeric ? playerItem.forwardPlaybackEndTime.seconds : duration
        close()
        guard let range = TrimRange(start: start, end: end, duration: duration) else {
            HUD.show("That's too short to keep", systemImage: "scissors")
            return
        }
        model.trim(item, to: range)
    }

    /// Trims to `range` directly (scripted tests: the trimming bar has no scriptable handles).
    func trim(to range: TrimRange) {
        close()
        model.trim(item, to: range)
    }

    private func close() {
        guard !finished else { return }
        finished = true
        playerView.player?.pause()
        window.delegate = nil
        window.close()
        Self.open[item.id] = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        playerView.player?.pause()
        Self.open[item.id] = nil
    }
}

/// The window's background colour as a layer, following appearance changes.
private final class WindowBackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

/// The video, aspect-fit on the window's background (the trim window's picture).
private final class PlayerLayerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Video")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}
