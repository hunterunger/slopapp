import Foundation
import Testing
@testable import FocusCore

@Suite("Storage")
struct StorageTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("focus-tests-\(UUID().uuidString)")
    }

    @Test func stateAndSettingsRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStorage(directory: dir)
        #expect(store.loadState() == nil)
        let state = TimerState(run: Run(phase: .focus, length: 1500, startedAt: t0, label: "Draft"), cycleCount: 2)
        try store.saveState(state)
        try store.saveSettings(TimerSettings(focusMinutes: 50))
        let again = FileStorage(directory: dir)
        #expect(again.loadState() == state)
        #expect(again.loadSettings()?.focusMinutes == 50)
    }

    @Test func historyAppendsAndReadsRecentOnes() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStorage(directory: dir)
        for day in 0..<10 {
            let end = t0.addingTimeInterval(Double(day - 9) * 86_400)
            try store.append(SessionRecord(startedAt: end.addingTimeInterval(-1500), endedAt: end, planned: 1500, focused: 1500, completed: true, label: "d\(day)"))
        }
        let recent = store.records(since: utc.startOfDay(for: t0).addingTimeInterval(-86_400))
        #expect(recent.map(\.label) == ["d8", "d9"])
    }

    @Test func aDamagedLineIsSkipped() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStorage(directory: dir)
        try store.append(SessionRecord(startedAt: t0, endedAt: t0, planned: 60, focused: 60, completed: true, label: "a"))
        let handle = try FileHandle(forWritingTo: store.historyURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json\n".utf8))
        try handle.close()
        try store.append(SessionRecord(startedAt: t0.addingTimeInterval(1), endedAt: t0.addingTimeInterval(1), planned: 60, focused: 60, completed: true, label: "b"))
        #expect(store.records(since: t0.addingTimeInterval(-10)).map(\.label) == ["a", "b"])
    }

    @Test func aDamagedStateFileIsIgnored() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("state.json"))
        #expect(FileStorage(directory: dir).loadState() == nil)
    }
}

@Suite("Shortcuts command")
struct ShortcutsCommandTests {
    @Test func successAndFailure() async throws {
        try await CommandShortcutRunner(executable: URL(fileURLWithPath: "/usr/bin/true")).run("Anything")
        await #expect(throws: ShortcutError.couldntRun("Work On")) {
            try await CommandShortcutRunner(executable: URL(fileURLWithPath: "/usr/bin/false")).run("Work On")
        }
        await #expect(throws: ShortcutError.couldntRun("X")) {
            try await CommandShortcutRunner(executable: URL(fileURLWithPath: "/nonexistent/shortcuts")).run("X")
        }
    }

    @Test func listsOutputLines() async throws {
        // `echo list` prints "list": stands in for `shortcuts list`.
        let names = try await CommandShortcutRunner(executable: URL(fileURLWithPath: "/bin/echo")).list()
        #expect(names == ["list"])
    }

    @Test func slowCommandsAreStopped() async throws {
        let start = Date()
        let result = try await CommandShortcutRunner.execute(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.3)
        #expect(result.timedOut)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
