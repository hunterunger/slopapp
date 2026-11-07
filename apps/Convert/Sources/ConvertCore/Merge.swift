import AVFoundation
import CoreMedia
import Foundation

/// Joins videos (or sound files) end to end into one new file, in the given order. Clips of
/// other sizes are scaled to fit the first one's frame, with black bars. The picture is
/// always re-encoded (one consistent size and codec); sound uses the target's format.
extension Converter {
    /// Kinds of merge, decided from the files and the target.
    enum MergeKind {
        case video(VideoTarget)
        case audio(AudioTarget, title: String)
    }

    /// The name the merged file gets, before any " 2": "Holiday Merged.mp4" for a merge
    /// that starts with "Holiday.mov".
    public static func mergedName(first: URL) -> String {
        first.deletingPathExtension().lastPathComponent + " Merged"
    }

    public func merge(_ inputs: [URL], progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ConversionReport {
        guard inputs.count >= 2 else { throw ConvertError.cantMerge(reason: "Choose two or more files to merge.") }
        var infos: [MediaInfo] = []
        for url in inputs {
            infos.append(try await MediaProbe.probe(url))
            try Task.checkCancellation()
        }
        if infos.contains(where: { $0.kind == .image || $0.isAnimatedImage }) {
            throw ConvertError.cantMerge(reason: "Only videos and sound files can be merged.")
        }
        let allVideo = infos.allSatisfy(\.hasVideo)
        let anyVideo = infos.contains(where: \.hasVideo)
        let kind: MergeKind
        var notes: [String] = ["Merged from \(inputs.count) files."]
        if allVideo, settings.video.audioTarget == nil {
            var target = settings.video
            if target == .gif {
                target = .mp4H264
                notes.append("Merged as MP4 (H.264): GIFs are made from one clip at a time.")
            }
            guard capabilities.canWrite(target) else { throw ConvertError.cantWriteFormat(format: target.title, kind: .video) }
            kind = .video(target)
        } else if allVideo, let audioTarget = settings.video.audioTarget {
            kind = .audio(audioTarget, title: settings.video.title)
        } else if !anyVideo {
            kind = .audio(settings.audio, title: settings.audio.title)
        } else {
            throw ConvertError.cantMerge(reason: "Videos and sound files can't be merged together. Merge videos with videos, or sound with sound.")
        }
        if case .audio = kind, !infos.contains(where: \.hasAudio) {
            throw ConvertError.cantMerge(reason: "None of these files has any sound.")
        }

        // The timeline: each file's picture and first sound track, one after another.
        let composition = AVMutableComposition()
        let wantsVideo: Bool = if case .video = kind { true } else { false }
        let videoTrack = wantsVideo ? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        let audioTrack = infos.contains(where: \.hasAudio)
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        let first = infos[0]
        var render = CGSize(width: first.displayWidth, height: first.displayHeight)
        var segments: [(start: CMTime, transform: CGAffineTransform)] = []
        var cursor = CMTime.zero
        var frameRate = 0.0
        var anyHDR = false
        var resized = false
        if case .video(let target) = kind {
            var (w, h) = Planner.fit(first.displayWidth, first.displayHeight, in: settings.size.box, even: true)
            if target == .mp4H264 { (w, h) = Planner.fit(w, h, in: Planner.h264Box, even: true) }
            render = CGSize(width: Planner.even(w), height: Planner.even(h))
        }
        for (url, info) in zip(inputs, infos) {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, duration.seconds > 0 else { throw ConvertError.damaged(name: url.lastPathComponent) }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let videoTrack, let source = try await MediaProbe.firstEnabled(try await asset.loadTracks(withMediaType: .video)) {
                let (natural, preferred, rate, sourceRange) = try await source.load(.naturalSize, .preferredTransform, .nominalFrameRate, .timeRange)
                do {
                    try videoTrack.insertTimeRange(CMTimeRangeGetIntersection(range, otherRange: sourceRange), of: source, at: cursor)
                } catch {
                    throw ConvertError.damaged(name: url.lastPathComponent)
                }
                frameRate = max(frameRate, Double(rate))
                anyHDR = anyHDR || info.isHDR
                // Upright, then scaled to fit the frame, centred.
                let shown = CGRect(origin: .zero, size: natural).applying(preferred)
                let (sw, sh) = (abs(shown.width), abs(shown.height))
                let scale = min(render.width / max(1, sw), render.height / max(1, sh))
                if abs(sw * scale - render.width) > 2 || abs(sh * scale - render.height) > 2 { resized = true }
                let t = preferred
                    .concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: (render.width - sw * scale) / 2,
                                                     y: (render.height - sh * scale) / 2))
                segments.append((cursor, t))
            }
            if let audioTrack {
                let sources = try await asset.loadTracks(withMediaType: .audio)
                if let source = try await MediaProbe.firstEnabled(sources) {
                    let sourceRange = try await source.load(.timeRange)
                    do {
                        try audioTrack.insertTimeRange(CMTimeRangeGetIntersection(range, otherRange: sourceRange), of: source, at: cursor)
                    } catch {
                        throw ConvertError.damaged(name: url.lastPathComponent)
                    }
                }
            }
            cursor = cursor + duration
            try Task.checkCancellation()
        }
        if resized { notes.append("Clips of another shape were fitted with black bars.") }

        var merged = first
        merged.duration = cursor.seconds
        merged.audioTrackCount = audioTrack == nil ? 0 : 1
        if merged.audioCodec == nil, let other = infos.first(where: \.hasAudio) {
            merged.audioCodec = other.audioCodec
            merged.channels = other.channels
            merged.sampleRate = other.sampleRate
            merged.bitsPerSample = other.bitsPerSample
        }
        // Sound is always decoded and re-encoded: the pieces may differ.
        merged.audioCodec = merged.audioCodec.map { _ in "lpcm" }
        merged.audioBitRate = 0

        var plan: TranscodePlan
        var videoComposition: AVVideoComposition?
        switch kind {
        case .video(let target):
            plan = Planner.videoPlan(merged, target: target, settings: settings)
            let codec: VideoCodecChoice = target == .mp4HEVC ? .hevc : target == .movProRes ? .proRes422 : .h264
            plan.video = .encode(VideoEncoding(
                codec: codec, width: Int(render.width), height: Int(render.height),
                quality: codec == .proRes422 ? nil : QualityTable.videoQuality(settings.quality),
                keepHDR: false, toSDR: anyHDR, frameRate: min(60, frameRate), upright: true))
            plan.notes = []
            if anyHDR { notes.append("HDR was converted to standard range.") }
            if let videoTrack {
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                for segment in segments { layer.setTransform(segment.transform, at: segment.start) }
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
                instruction.layerInstructions = [layer]
                let vc = AVMutableVideoComposition()
                vc.renderSize = render
                vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? min(60, frameRate.rounded()) : 30))
                vc.instructions = [instruction]
                vc.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
                vc.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
                vc.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
                videoComposition = vc
            }
        case .audio(let target, let title):
            merged.kind = .audio
            merged.videoCodec = nil
            plan = try Planner.audioPlan(merged, target: target, quality: settings.quality, name: inputs[0].lastPathComponent,
                                         title: title)
            plan.notes = []
        }

        let name = Self.mergedName(first: inputs[0])
        let stand = inputs[0].deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension("merge")
        let finalPlan = plan
        let vc = videoComposition
        let length = cursor.seconds
        var me = self
        me.previous = nil
        me.settings.keepDates = false
        let result = try await me.writeAsync(stand, ext: plan.fileExtension) { scratch in
            let extra = try await Transcoder(asset: composition, plan: finalPlan, output: scratch, name: name,
                                             videoComposition: vc).run(progress: progress)
            var parts = [finalPlan.targetTitle]
            if case .encode(let e)? = finalPlan.video { parts.append("\(e.width)×\(e.height)") }
            if case .encode(let a) = finalPlan.audio, case .aac(let bitRate) = a.format, finalPlan.video == nil {
                parts.append("\(bitRate / 1000) kbps")
            }
            parts.append(Durations.string(length))
            return (parts, false, notes + extra)
        }
        guard case .converted(let report) = result else { throw ConvertError.encodeFailed(name: name) }
        return report
    }
}
