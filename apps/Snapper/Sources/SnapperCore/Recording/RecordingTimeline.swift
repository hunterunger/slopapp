import CoreMedia

/// Maps the host-clock times of captured samples (screen frames, computer audio, the
/// microphone) to times in the recording file, so every track lines up and a pause leaves no
/// gap. All three sources stamp their samples on the host clock.
///
/// The file starts at the first kept screen frame. Samples from before it, or from inside a
/// pause, are dropped; later ones move back by the paused time.
public struct RecordingTimeline: Sendable {
    /// Host time of the file's first frame.
    public private(set) var start: CMTime?
    private var pauses: [(start: CMTime, end: CMTime?)] = []

    public init() {}

    public var hasStarted: Bool { start != nil }
    public var isPaused: Bool { pauses.last.map { $0.end == nil } ?? false }

    /// The first screen frame arrived at host time `time`.
    public mutating func begin(at time: CMTime) {
        guard start == nil else { return }
        start = time
    }

    public mutating func pause(at time: CMTime) {
        guard !isPaused else { return }
        pauses.append((time, nil))
    }

    public mutating func resume(at time: CMTime) {
        guard isPaused, let last = pauses.last else { return }
        pauses[pauses.count - 1].end = CMTimeMaximum(time, last.start)
    }

    /// Paused time that ended at or before `time`.
    private func pausedBefore(_ time: CMTime) -> CMTime {
        pauses.reduce(CMTime.zero) { total, pause in
            guard let end = pause.end, end <= time else { return total }
            return CMTimeAdd(total, CMTimeSubtract(end, pause.start))
        }
    }

    /// Where a sample stamped `time` goes in the file, or nil to drop it (before the start,
    /// or during a pause).
    public func fileTime(for time: CMTime) -> CMTime? {
        guard let start, time >= start else { return nil }
        for pause in pauses where time >= pause.start && (pause.end.map { time < $0 } ?? true) {
            return nil
        }
        return CMTimeSubtract(CMTimeSubtract(time, start), pausedBefore(time))
    }

    /// How long the file is at host time `now`: up to the pause if paused.
    public func duration(at now: CMTime) -> CMTime {
        guard let start else { return .zero }
        if isPaused, let pause = pauses.last {
            return CMTimeMaximum(.zero, CMTimeSubtract(CMTimeSubtract(pause.start, start), pausedBefore(pause.start)))
        }
        return CMTimeMaximum(.zero, CMTimeSubtract(CMTimeSubtract(now, start), pausedBefore(now)))
    }
}
