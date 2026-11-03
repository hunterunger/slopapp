import AppKit
import QuartzCore
import SpecimenCore

/// `SPECIMEN_BENCH=scroll,typing` (optionally `SPECIMEN_STRESS=10`, `SPECIMEN_BENCH_OUT=file.json`):
/// waits for the library, then measures on the real window, writes JSON, and quits. No input
/// devices are used. Each "frame" is the main-thread time to lay out and draw one step.
@MainActor
enum Benchmark {
    static func run(_ kind: String, model: AppModel) {
        Task {
            while !model.hasLoaded || model.isIndexing { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(800))
            var report: [String: Any] = [
                "faces": model.faces.count * model.environment.stressCopies,
                "families": model.families.count,
                "cards": model.items.count,
            ]
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && find(in: $0.contentView!) != nil }),
                  let grid = find(in: window.contentView!) else {
                report["error"] = "no grid"
                finish(report, model: model)
                return
            }
            report["window"] = "\(Int(window.frame.width))x\(Int(window.frame.height))"
            if kind.contains("scroll") {
                var scroll: [String: Any] = [:]
                for size in [12.0, 36, 72, 200] {
                    model.previewSize = size
                    try? await Task.sleep(for: .milliseconds(400))
                    PreviewRenderer.shared.clearAll()
                    scroll["\(Int(size))pt"] = scrollPass(grid, window: window)
                }
                report["scroll"] = scroll
                report["footprintAfterScrollMB"] = footprintMB()
            }
            if kind.contains("typing") {
                var typing: [String: Any] = [:]
                for size in [36.0, 72] {
                    model.previewSize = size
                    grid.enclosingScrollView?.contentView.scroll(to: .zero)
                    try? await Task.sleep(for: .milliseconds(400))
                    typing["\(Int(size))pt"] = await typingPass(grid, window: window, model: model)
                }
                report["typing"] = typing
                model.previewText = ""
            }
            report["footprintMB"] = footprintMB()
            finish(report, model: model)
        }
    }

    private static func find(in view: NSView) -> FontCollectionView? {
        if let grid = view as? FontCollectionView { return grid }
        for child in view.subviews { if let grid = find(in: child) { return grid } }
        return nil
    }

    /// Scrolls top to bottom 60 pt per step (a brisk flick at 60 fps), cold caches.
    private static func scrollPass(_ grid: FontCollectionView, window: NSWindow) -> [String: Any] {
        guard let scrollView = grid.enclosingScrollView else { return [:] }
        let clip = scrollView.contentView
        let maxY = max(0, grid.frame.height - clip.bounds.height)
        var times: [Double] = []
        var y: CGFloat = 0
        while y <= maxY, times.count < 4000 {
            // One pool per step, as one scroll event would have.
            autoreleasepool {
                clip.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(clip)
                let start = CACurrentMediaTime()
                grid.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                times.append((CACurrentMediaTime() - start) * 1000)
            }
            y += 60
        }
        clip.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clip)
        return stats(times, extra: ["contentHeight": Int(grid.frame.height), "columns": grid.controller?.columns ?? 0])
    }

    /// Types a sentence one character at a time; each sample is keystroke → every visible card redrawn.
    private static func typingPass(_ grid: FontCollectionView, window: NSWindow, model: AppModel) async -> [String: Any] {
        let sentence = "The quick brown fox jumps over the lazy dog"
        var times: [Double] = []
        var propagation: [Double] = []
        var redraw: [Double] = []
        var drawCPU: [Double] = []
        model.previewText = ""
        try? await Task.sleep(for: .milliseconds(200))
        for count in 1...sentence.count {
            let text = String(sentence.prefix(count))
            let start = CACurrentMediaTime()
            let drawBefore = FontCardView.totalDrawTime
            model.previewText = text
            // Wait until the change reached the grid and every visible card has redrawn.
            while CACurrentMediaTime() - start < 1 {
                try? await Task.sleep(for: .milliseconds(2))
                if grid.controller?.appliedPreviewText == text, !grid.visibleItems().contains(where: { $0.view.needsDisplay }),
                   FontCardView.lastDrawEnd > start { break }
            }
            grid.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let applied = grid.controller?.previewAppliedAt ?? start
            times.append((FontCardView.lastDrawEnd - start) * 1000)
            propagation.append((applied - start) * 1000)
            redraw.append((FontCardView.lastDrawEnd - applied) * 1000)
            drawCPU.append((FontCardView.totalDrawTime - drawBefore) * 1000)
            try? await Task.sleep(for: .milliseconds(30))
        }
        func median(_ values: [Double]) -> Double { (values.sorted()[values.count / 2] * 100).rounded() / 100 }
        return stats(times, extra: ["visibleCards": grid.visibleItems().count,
                                    "swiftUIPropagationP50ms": median(propagation), "untilDrawnP50ms": median(redraw),
                                    "cardDrawCPUP50ms": median(drawCPU), "cardDrawCPUMaxms": ((drawCPU.max() ?? 0) * 100).rounded() / 100])
    }

    private static func stats(_ times: [Double], extra: [String: Any]) -> [String: Any] {
        guard !times.isEmpty else { return extra }
        let sorted = times.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        func round(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        var result = extra
        result["samples"] = times.count
        result["p50ms"] = round(percentile(0.5))
        result["p95ms"] = round(percentile(0.95))
        result["p99ms"] = round(percentile(0.99))
        result["maxms"] = round(sorted.last ?? 0)
        result["over16ms"] = times.filter { $0 > 16.7 }.count
        return result
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? (Double(info.phys_footprint) / 1_048_576 * 10).rounded() / 10 : -1
    }

    private static func finish(_ report: [String: Any], model: AppModel) {
        let url = model.environment.benchmarkOutput ?? URL(fileURLWithPath: "/tmp/specimen-bench.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
        if ProcessInfo.processInfo.environment["SPECIMEN_BENCH_HOLD"] == nil { NSApp.terminate(nil) }
    }
}
