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
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Trim \(item.fileBaseName)"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 480, height: 300)
        window.delegate = self
        playerView.controlsStyle = .inline
        playerView.showsFrameSteppingButtons = true
        playerView.showsSharingServiceButton = false
        playerView.allowsPictureInPicturePlayback = false
        playerView.player = AVPlayer(url: url)
        playerView.setAccessibilityLabel("Recording")
        window.contentView = playerView
        window.center()
    }

    /// The video at up to 960 × 640 points, never smaller than the trimming bar needs.
    static func windowSize(for video: CGSize) -> CGSize {
        let limit = CGSize(width: 960, height: 640)
        let scale = min(1, limit.width / max(video.width, 1), limit.height / max(video.height, 1))
        return CGSize(width: max(480, (video.width * scale).rounded()), height: max(300, (video.height * scale).rounded()))
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
