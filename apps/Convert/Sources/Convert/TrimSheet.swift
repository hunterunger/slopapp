import AVKit
import ConvertCore
import SlopKit
import SwiftUI

/// Trim one video or sound file: a player on top, a range bar with start and end handles,
/// and nudge buttons on each side (−1 s, −0.1 s, set to the playhead, +0.1 s, +1 s).
/// I and O set the start and end at the playhead; Return is Done, Esc is Cancel.
struct TrimSheet: View {
    @Bindable var model: AppModel
    let entry: CardEntry

    @State private var player: AVPlayer
    @State private var duration: Double
    @State private var start: Double
    @State private var end: Double
    @State private var time: Double = 0
    @State private var observer: Any?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, entry: CardEntry) {
        self.model = model
        self.entry = entry
        let duration = model.facts(for: entry.input).info?.duration ?? 0
        let trim = model.options(for: entry.input).trim
        _player = State(initialValue: AVPlayer(url: entry.input))
        _duration = State(initialValue: duration)
        _start = State(initialValue: trim?.start ?? 0)
        _end = State(initialValue: min(trim?.end ?? duration, duration))
    }

    private var isSound: Bool { model.kind(of: entry.input) == .audio }

    var body: some View {
        VStack(spacing: 0) {
            Text("Trim “\(entry.input.lastPathComponent)”")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
            // AVKit draws its own letterbox for video; sound files get just the inline bar on
            // the sheet's own background (no black band in light mode).
            PlayerView(player: player, inline: isSound)
                .frame(minWidth: 640, minHeight: isSound ? 80 : 360)
            VStack(spacing: Spacing.m) {
                HStack {
                    Text(Durations.precise(0)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    RangeSlider(start: $start, end: $end, duration: duration, playhead: time) { seek(to: $0) }
                    Text(Durations.precise(duration)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: Spacing.s) {
                    nudges(for: "Start", isStart: true, setKey: "i")
                    Spacer(minLength: Spacing.s)
                    VStack(spacing: 2) {
                        Text("\(Durations.precise(start)) – \(Durations.precise(end))")
                            .font(.callout.monospacedDigit())
                        Text("Keeps \(Durations.precise(end - start))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: Spacing.s)
                    nudges(for: "End", isStart: false, setKey: "o")
                }
                HStack {
                    Button("Keep Everything") {
                        start = 0
                        end = duration
                    }
                    .help("Remove the trim")
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(end - start < 0.1)
                }
            }
            .padding(Spacing.xl)
        }
        .frame(minWidth: 680)
        .navigationTitle("Trim \(entry.input.lastPathComponent)")
        .onAppear {
            seek(to: start)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { t in
                MainActor.assumeIsolated {
                    time = t.seconds
                    // Playing stops at the end of the kept part.
                    if player.rate > 0, t.seconds >= end { player.pause() }
                }
            }
        }
        .onDisappear {
            player.pause()
            if let observer { player.removeTimeObserver(observer) }
        }
        .onChange(of: start) { _, new in seek(to: new) }
        .onChange(of: end) { _, new in seek(to: new) }
    }

    private func nudges(for name: String, isStart: Bool, setKey: Character) -> some View {
        HStack(spacing: Spacing.xs / 2) {
            nudge("\(name) back 1 second", text: "−1s", isStart: isStart, by: -1)
            nudge("\(name) back a tenth of a second", symbol: "chevron.left", isStart: isStart, by: -0.1)
            Button("Set \(name)") { set(isStart: isStart, to: time) }
                .keyboardShortcut(KeyEquivalent(setKey), modifiers: [])
                .help("Set the \(name.lowercased()) to the playhead (\(String(setKey).uppercased()))")
            nudge("\(name) forward a tenth of a second", symbol: "chevron.right", isStart: isStart, by: 0.1)
            nudge("\(name) forward 1 second", text: "+1s", isStart: isStart, by: 1)
        }
        .controlSize(.small)
    }

    private func nudge(_ label: String, symbol: String? = nil, text: String? = nil, isStart: Bool, by step: Double) -> some View {
        Button { set(isStart: isStart, to: (isStart ? start : end) + step) } label: {
            // Symbols inside Text, so these get the same height as the text buttons beside them
            // (an image-only bordered button comes out 3 pt shorter).
            Group {
                if let symbol { Text(Image(systemName: symbol)) } else { Text(text ?? "").monospacedDigit() }
            }
            .frame(minWidth: Spacing.xxl)
        }
        .help(label)
        .accessibilityLabel(label)
    }

    /// Keeps the start before the end (at least 0.1 s apart), both inside the file.
    private func set(isStart: Bool, to new: Double) {
        let clamped = min(max(0, new), duration)
        if isStart {
            start = max(0, min(clamped, end - 0.1))
        } else {
            end = min(duration, max(clamped, start + 0.1))
        }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func save() {
        let trim = TrimRange(start: start, end: end)
        model.updateOptions(for: [entry]) { $0.trim = trim.isWhole(of: duration) ? nil : trim }
        dismiss()
    }
}

/// AVKit's player, with its own controls (floating for videos, a bar for sound).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    var inline = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = inline ? .inline : .floating
        view.showsFullScreenToggleButton = false
        view.setAccessibilityLabel("Preview")
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}

/// A bar with two handles (start and end) over a file's length, the kept part in the
/// accent colour and a line at the playhead. Clicking the bar moves the playhead. Each handle
/// is adjustable with VoiceOver (a tenth of a second per step) and the arrow keys.
/// Named so it could move to SlopKit.
struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let duration: Double
    let playhead: Double
    let onScrub: (Double) -> Void

    private let thumb: CGFloat = 16
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - thumb)
            let x = { (value: Double) -> CGFloat in thumb / 2 + CGFloat(duration > 0 ? value / duration : 0) * width }
            let value = { (x: CGFloat) -> Double in min(max(0, Double((x - thumb / 2) / width) * duration), duration) }
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.secondary).frame(height: 6)
                    .padding(.horizontal, thumb / 2)
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { onScrub(value($0.location.x)) })
                    .accessibilityHidden(true)
                Capsule().fill(Color.windowAccent(activeState))
                    .frame(width: max(0, x(end) - x(start)), height: 6)
                    .offset(x: x(start))
                    .allowsHitTesting(false)
                Rectangle().fill(.primary)
                    .frame(width: 2, height: 20)
                    .offset(x: x(playhead) - 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                handle("Start", value: $start, at: x(start)) { new in start = min(value(new), end - 0.1) }
                handle("End", value: $end, at: x(end)) { new in end = max(value(new), start + 0.1) }
            }
            .frame(height: proxy.size.height)
            .coordinateSpace(name: "track")
        }
        .frame(height: 24)
    }

    private func handle(_ name: String, value: Binding<Double>, at position: CGFloat, drag: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            // Control background: white in light mode, dark in dark mode (a ring handle), with
            // a tight shadow that reads in both.
            .fill(Color(nsColor: .controlBackgroundColor))
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.35), radius: 1, y: 0.5)
            .overlay(Circle().strokeBorder(Color.windowAccent(activeState), lineWidth: 2))
            .frame(width: thumb, height: thumb)
            .offset(x: position - thumb / 2)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track")).onChanged { g in
                drag(g.location.x)
            })
            // A real slider for VoiceOver (role, value, increment/decrement by 0.1 s), kept
            // inside the file and at least 0.1 s from the other handle.
            .accessibilityRepresentation {
                Slider(value: Binding(get: { value.wrappedValue }, set: { new in
                    if name == "Start" { start = min(max(0, new), end - 0.1) } else { end = max(min(duration, new), start + 0.1) }
                }), in: 0...max(duration, 0.1), step: 0.1) { Text(name) }
                    .accessibilityValue(Durations.precise(value.wrappedValue))
            }
            .accessibilityLabel(name)
    }
}
