import AppKit
import Foundation
import SnapperCore

/// Keeps Capture Text instant.
///
/// The first text recognition after macOS drops its compiled copy of the recognizer takes 30 s
/// or more while the Neural Engine compiles the networks again. macOS keeps that compiled
/// copy per executable, and drops it when it likes (restarts, updates, cache clean-up).
///
/// So Snapper runs its own executable as a short-lived helper (`--warm-text-recognition`)
/// soon after launch, after the Mac wakes, and every few hours. The helper reads a built-in
/// sample and quits: the compile happens there, in the background, and Snapper itself never
/// holds the recognizer's memory until it reads text. When the cache is already warm the
/// helper is done in well under a second.
enum TextWarmUp {
    static let argument = "--warm-text-recognition"

    /// How long after launch the first warm-up starts (launch work comes first).
    private static let launchDelay: Duration = .seconds(8)
    /// macOS can drop the compiled copy while Snapper runs; check again this often.
    private static let interval: Duration = .seconds(3 * 60 * 60)
    /// A helper still going after this is stopped (a normal cold compile takes under a minute).
    private static let helperTimeout: TimeInterval = 180

    @MainActor private static var helper: Process?
    @MainActor private static var schedule: Task<Void, Never>?
    @MainActor private static var wakeObserver: NSObjectProtocol?

    /// In the helper process: warm up, print what was read and how long it took, exit.
    /// Called before anything else starts (no app, no windows, no settings).
    static func runIfRequested() {
        guard CommandLine.arguments.contains(argument) else { return }
        let started = Date()
        let text = VisionTextRecognizer.warmUp()
        print(String(format: "%.2f", Date().timeIntervalSince(started)), text)
        exit(text.isEmpty ? 1 : 0)
    }

    /// In the app: warm up soon after launch, after every wake, and every few hours.
    /// Test runs skip it, so they never start the compiler for a throwaway build.
    @MainActor static func start() {
        guard Diagnostics.testScene == nil, !Diagnostics.testHooks,
              ProcessInfo.processInfo.environment["SLOPAPP_SMOKE_TEST"] != "1" else { return }
        schedule = Task {
            try? await Task.sleep(for: launchDelay)
            while !Task.isCancelled {
                runHelper(reason: "scheduled")
                try? await Task.sleep(for: interval)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { runHelper(reason: "wake") }
        }
    }

    /// Starts warming in this process too, when text is about to be read (Capture Text was
    /// chosen and an area is being picked): a cold compile then overlaps with the picking.
    static func warmInProcess() {
        Task.detached(priority: .userInitiated) { VisionTextRecognizer.warmUp() }
    }

    @MainActor private static func runHelper(reason: String) {
        guard helper == nil, let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = [argument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        let started = Diagnostics.now()
        process.terminationHandler = { finished in
            let line = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let seconds = line.split(separator: " ").first.map(String.init) ?? "?"
            let status = finished.terminationStatus
            Task { @MainActor in
                helper = nil
                Diagnostics.record("text warm-up \(reason) status=\(status) seconds=\(seconds) ms=\(Diagnostics.milliseconds(since: started))")
            }
        }
        do {
            try process.run()
        } catch {
            Diagnostics.record("text warm-up \(reason) couldn't start: \(error.localizedDescription)")
            return
        }
        helper = process
        Task {
            try? await Task.sleep(for: .seconds(helperTimeout))
            if helper === process, process.isRunning { process.terminate() }
        }
    }
}

/// Snapper's entry point: the warm-up helper exits here, before the app or its model exist.
@main
enum SnapperMain {
    static func main() {
        TextWarmUp.runIfRequested()
        SnapperApp.main()
    }
}
