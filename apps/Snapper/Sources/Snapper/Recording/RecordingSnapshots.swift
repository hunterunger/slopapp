import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// The `snapshotRecordingUI` test hook: the recording bar (ready and recording, extras off
/// and on), the permission windows, the keystroke caption and Settings → Recording, drawn
/// into PNGs without any window on screen (works while the display sleeps or is locked).
/// Offscreen drawing leaves out the panels' glass; this checks layout, symbols and text.
@MainActor
enum RecordingSnapshots {
    static func write(model: AppModel) async {
        let folder = URL(fileURLWithPath: Diagnostics.snapshotDirectory ?? "/tmp/snapper-test/snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controller: RecordingController = model.recording
        let clock = RecordingClock()
        let saved = (model.recordMicrophone, model.recordComputerAudio, model.recordCamera, model.recordShowClicks, model.recordShowKeys)
        func render<V: View>(_ name: String, width: CGFloat? = nil, height: CGFloat? = nil, _ view: V) {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
                host.appearance = NSAppearance(named: appearance)
                let fitting = host.fittingSize
                host.frame = CGRect(origin: .zero, size: CGSize(width: width ?? fitting.width, height: height ?? fitting.height))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name)-\(mode).png"))
            }
        }
        // Extras off.
        model.recordMicrophone = false; model.recordComputerAudio = false; model.recordCamera = false
        model.recordShowClicks = false; model.recordShowKeys = false
        render("bar-ready-off", RecordingBar(controller: controller, model: model, clock: clock, microphone: controller.microphone, ready: true))
        // Everything on, with the test microphone running so the meter shows a level.
        model.recordMicrophone = true; model.recordComputerAudio = true; model.recordCamera = true
        model.recordShowClicks = true; model.recordShowKeys = true
        try? controller.microphone.start(deviceID: FakeMediaDevices.microphone.id)
        try? await Task.sleep(for: .milliseconds(600))
        render("bar-ready-on", RecordingBar(controller: controller, model: model, clock: clock, microphone: controller.microphone, ready: true))
        render("bar-recording", RecordingBar(controller: controller, model: model, clock: clock, microphone: controller.microphone, ready: false))
        controller.microphone.stop()
        for (name, permission) in [("microphone", RecordingPermission.media(.microphone)), ("camera", .media(.camera)), ("accessibility", .accessibility)] {
            render("permission-\(name)", MediaPermissionView(permission: permission) {})
        }
        render("caption", CaptionView(text: "⇧⌘4"))
        render("settings-recording", width: 560, height: 1180, RecordingPane(model: model))
        (model.recordMicrophone, model.recordComputerAudio, model.recordCamera, model.recordShowClicks, model.recordShowKeys) = saved
        Diagnostics.record("offscreen recording ui written")
    }
}
