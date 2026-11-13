import CoreText
import Foundation
import Testing
@testable import SpecimenCore

@Suite struct ActivationRoutingTests {
    let inPlace: (FontFace) -> Bool = { $0.path?.hasPrefix("/L/") == true }

    @Test func installedFontsUseTheSwitchLibraryFontsRegister() {
        let installed = face("Inst", family: "Inst", enabled: false)
        let library = face("Lib-Regular", family: "Lib", path: "/L/Lib.otf", enabled: false)
        let libraryTemp = face("Tmp-Regular", family: "Tmp", path: "/L/Tmp.otf", enabled: false)
        let steps = ActivationRouter.steps(on: [installed, library, libraryTemp], off: [], temporaryIDs: [libraryTemp.id],
                                           inPlace: inPlace, registered: [])
        #expect(steps.enable == [installed])
        #expect(steps.registerPersistent == ["/L/Lib.otf"])
        #expect(steps.registerTemporary == ["/L/Tmp.otf"])
        #expect(steps.unregister.isEmpty && steps.disable.isEmpty)
    }

    @Test func turningOffUnregistersOncePerFile() {
        let regular = face("Pair-Regular", family: "Pair", path: "/L/Pair.ttc")
        let bold = face("Pair-Bold", family: "Pair", style: "Bold", path: "/L/Pair.ttc")
        let installed = face("Inst", family: "Inst")
        let steps = ActivationRouter.steps(on: [], off: [regular, bold, installed], temporaryIDs: [], inPlace: inPlace, registered: ["/L/Pair.ttc"])
        #expect(steps.unregister == ["/L/Pair.ttc"])
        #expect(steps.disable == [installed])
    }

    @Test func keepingATemporaryFontOnReRegistersItForGood() {
        var temporary = face("Tmp-Regular", family: "Tmp", path: "/L/Tmp.otf")
        temporary.isTemporary = true
        let steps = ActivationRouter.steps(on: [temporary], off: [], temporaryIDs: [], inPlace: inPlace, registered: ["/L/Tmp.otf"])
        #expect(steps.unregister == ["/L/Tmp.otf"])
        #expect(steps.registerPersistent == ["/L/Tmp.otf"])
    }

    @Test func undoingKeepActiveMakesItTemporaryAgain() {
        let kept = face("Tmp-Regular", family: "Tmp", path: "/L/Tmp.otf")
        let steps = ActivationRouter.steps(on: [kept], off: [], temporaryIDs: [kept.id], inPlace: inPlace, registered: ["/L/Tmp.otf"])
        #expect(steps.unregister == ["/L/Tmp.otf"])
        #expect(steps.registerTemporary == ["/L/Tmp.otf"])
        #expect(steps.registerPersistent.isEmpty)
    }

    @Test func undoPutsEveryFaceBackAsItWas() {
        let off = face("Off-Regular", family: "Off", path: "/L/Off.otf", enabled: false)
        var temporary = face("Tmp-Regular", family: "Tmp", path: "/L/Tmp.otf")
        temporary.isTemporary = true
        let persistent = face("On-Regular", family: "On", path: "/L/On.otf")
        // Turning on `off` and keeping `temporary` (both "on" targets), turning off `persistent`.
        let step = ActivationUndo.reverse(on: [off, temporary], off: [persistent])
        #expect(step.on == [persistent, temporary])
        #expect(step.off == [off])
        #expect(step.temporaryIDs == [temporary.id])
        // Undoing a temporary activation turns it off; its undo (redo) turns it back on temporarily.
        let undo = ActivationUndo.reverse(on: [off], off: [])
        #expect(undo.on.isEmpty && undo.off == [off])
        let redo = ActivationUndo.reverse(on: [], off: [temporary])
        #expect(redo.on == [temporary] && redo.temporaryIDs == [temporary.id])
        // And the router turns that into the right registrations.
        let steps = ActivationRouter.steps(on: redo.on.map { var f = $0; f.isEnabled = false; f.isTemporary = false; return f },
                                           off: [], temporaryIDs: redo.temporaryIDs, inPlace: inPlace, registered: [])
        #expect(steps.registerTemporary == ["/L/Tmp.otf"])
    }

    @Test func registeredButSwitchedOffIsSwitchedOn() {
        let off = face("Lib-Regular", family: "Lib", path: "/L/Lib.otf", enabled: false)
        let steps = ActivationRouter.steps(on: [off], off: [], temporaryIDs: [], inPlace: inPlace, registered: ["/L/Lib.otf"])
        #expect(steps.enable == [off])
        #expect(steps.registerPersistent.isEmpty)
    }

    @Test func plannerTemporaryRules() {
        let installed = face("Inst", family: "Inst", enabled: false)
        let library = face("Lib-Regular", family: "Lib", path: "/L/Lib.otf", enabled: false)
        var temporary = face("Tmp-Regular", family: "Tmp", path: "/L/Tmp.otf")
        temporary.isTemporary = true
        let all = [installed, library, temporary]
        let exists: (String) -> Bool = { _ in true }

        // Temporary only applies to library-folder fonts.
        let plan = ActivationPlanner.plan(targets: all, enable: true, library: all, testRoot: nil, temporary: true, inPlace: inPlace, fileExists: exists)
        #expect(plan.temporary)
        #expect(plan.changes == [library])
        #expect(plan.lockReasons == [.notTemporary])
        #expect(plan.alreadyDone == [temporary])

        // Activate (for good) on a temporary font keeps it on.
        let keep = ActivationPlanner.plan(targets: [temporary], enable: true, library: all, testRoot: nil, inPlace: inPlace, fileExists: exists)
        #expect(keep.changes == [temporary])
        #expect(!keep.temporary)
    }

    @Test func plannerWontSwapAcrossMechanisms() {
        let exists: (String) -> Bool = { _ in true }
        let installedOn = face("Same", family: "Same")
        let libraryCopy = face("Same", family: "Same", path: "/L/Same.otf", enabled: false)
        let plan = ActivationPlanner.plan(targets: [libraryCopy], enable: true, library: [installedOn, libraryCopy], testRoot: nil, inPlace: inPlace, fileExists: exists)
        #expect(plan.conflicts.first?.activeCopyLock == .otherCopyActive)
        #expect(plan.swapOns.isEmpty)
        // Two library copies (one project's v1, another's v2) can swap.
        let libraryOn = face("Same", family: "Same", path: "/L/v1/Same.otf")
        let swap = ActivationPlanner.plan(targets: [libraryCopy], enable: true, library: [libraryOn, libraryCopy], testRoot: nil, inPlace: inPlace, fileExists: exists)
        #expect(swap.swapOns == [libraryCopy])
        #expect(swap.swapOffs == [libraryOn])
    }

    @Test func renamedRegisteredFilesStayActive() {
        var change = LibraryChange()
        change.removed = ["/L/A/Inter.otf": ["Inter-Regular"], "/L/A/Gone.otf": ["Gone"], "/L/A/Off.otf": ["Off"]]
        change.added = ["/L/B/Inter.otf": ["Inter-Regular"], "/L/A/Inter copy.otf": ["Inter-Regular"], "/L/A/Off2.otf": ["Off"]]
        let moves = RegistrationCarryOver.moves(in: change, registered: ["/L/A/Inter.otf", "/L/A/Gone.otf"])
        // Same file name wins over same folder; unregistered files aren't carried.
        #expect(moves == [RegistrationCarryOver.Move(from: "/L/A/Inter.otf", to: "/L/B/Inter.otf")])
    }

    @Test func sessionOnlyRegistrarNeverRegistersForGood() {
        let base = FakeRegistrar()
        let registrar = SessionOnlyRegistrar(base: base)
        _ = registrar.register(["/t/a.otf"], scope: .persistent)
        _ = registrar.register(["/t/b.otf"], scope: .session)
        #expect(base.scopes == ["/t/a.otf": .session, "/t/b.otf": .session])
        #expect(registrar.scope(of: "/t/a.otf") == .persistent)
        #expect(registrar.scope(of: "/t/b.otf") == .session)
        #expect(registrar.registeredByThisRun == ["/t/a.otf"])
        _ = registrar.unregister(["/t/a.otf"])
        #expect(registrar.scope(of: "/t/a.otf") == nil)
        #expect(registrar.registeredByThisRun.isEmpty)
    }

    @Test func temporaryStoreRoundTrips() {
        let store = TemporaryStore(directory: temporaryDirectory())
        #expect(store.load().isEmpty)
        store.save(["/a", "/b"])
        #expect(store.load() == ["/a", "/b"])
        store.save([])
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

/// Real files and CoreText, in a temporary folder. Registrations are process-scoped (this
/// test process only), never session or persistent.
@Suite(.serialized) struct LibraryCoreTextTests {
    @Test func renamedFixturesAreDistinctFonts() throws {
        let folder = temporaryDirectory()
        let files = try FixtureFonts.makeLibrary(from: Fixtures.regular, into: folder, prefix: "Specimen Probe", count: 3)
        let faces = files.flatMap { CoreTextFontSystem.faces(inFile: $0.path) }
        #expect(faces.map(\.familyName) == ["Specimen Probe 1", "Specimen Probe 2", "Specimen Probe 3"])
        #expect(faces.map(\.postScriptName) == ["SpecimenProbe1-Regular", "SpecimenProbe2-Regular", "SpecimenProbe3-Regular"])
        #expect(faces.allSatisfy { $0.path?.hasPrefix(folder.path) == true && !$0.isEnabled })
        // The copy still renders.
        #expect(FontLoader.makeFont(postScriptName: "SpecimenProbe1-Regular", path: files[0].path, isEnabled: false, size: 12) != nil)
    }

    @Test func scansRealFoldersQuickly() throws {
        let root = temporaryDirectory().appendingPathComponent("Library")
        try FixtureFonts.makeLibrary(from: Fixtures.regular, into: root.appendingPathComponent("Client A"), prefix: "Scan A", count: 150)
        try FixtureFonts.makeLibrary(from: Fixtures.bold, into: root.appendingPathComponent("Client B/Fonts"), prefix: "Scan B", count: 150, style: "Bold")
        try Data("not a font".utf8).write(to: root.appendingPathComponent("Client A/Broken.otf"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Client A/notes.txt"))
        let fileSystem = LocalLibraryFileSystem()
        var scan = LibraryScan()
        let clock = ContinuousClock()
        var change = LibraryChange()
        let cold = clock.measure { change = scan.rescan(root.path, fileSystem: fileSystem) }
        #expect(change.added.count == 301)
        #expect(scan.faces(in: [root.path]).count == 300)
        #expect(scan.unreadableCount(in: root.path) == 1)
        // Paths keep the form the folder was given in (not /private/var/...).
        #expect(scan.files.keys.allSatisfy { $0.hasPrefix(root.path + "/") })
        let warm = clock.measure { change = scan.rescan(root.path, fileSystem: fileSystem) }
        #expect(change.isEmpty)
        print("scan of 301 files: cold \(cold), warm \(warm)")
        #expect(warm < cold)
    }

    @Test func fsEventsReportAddedAndRemovedFonts() async throws {
        let root = temporaryDirectory().appendingPathComponent("Watched")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let watcher = FSEventsWatcher(latency: 0.05)
        let received = EventBox()
        watcher.watch([root.path]) { received.append($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        let file = try FixtureFonts.makeLibrary(from: Fixtures.regular, into: root.appendingPathComponent("New"), prefix: "Watch", count: 1)[0]
        var waited = 0
        while !received.events.contains(where: { $0.path == file.path }), waited < 50 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        #expect(received.events.contains { $0.path == file.path && $0.flags.contains(.isFile) })
        // Applying what FSEvents said brings the scan up to date.
        var scan = LibraryScan()
        let change = scan.apply(received.events, roots: [root.path], fileSystem: LocalLibraryFileSystem())
        #expect(change.added.keys.contains(file.path))
    }

    @Test func registersInPlaceAndUnregisters() throws {
        let folder = temporaryDirectory()
        let file = try FixtureFonts.makeLibrary(from: Fixtures.regular, into: folder, prefix: "Specimen Reg", count: 1)[0]
        let registrar = CoreTextRegistrar()
        #expect(registrar.scope(of: file.path) == nil)
        #expect(registrar.register([file.path], scope: .process).isEmpty)
        #expect(registrar.scope(of: file.path) == .process)
        // Registering twice reports an error for that file.
        let again = registrar.register([file.path], scope: .process)
        #expect(again.first?.path == file.path)
        let listed = CoreTextFontSystem().listFaces().filter { $0.familyName == "Specimen Reg 1" }
        #expect(listed.count == 1)
        #expect(listed.first?.path == file.path)
        #expect(listed.first?.isEnabled == true)
        #expect(registrar.unregister([file.path]).isEmpty)
        #expect(registrar.scope(of: file.path) == nil)
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [FolderEvent] = []
    func append(_ events: [FolderEvent]) { lock.withLock { stored += events } }
    var events: [FolderEvent] { lock.withLock { stored } }
}
