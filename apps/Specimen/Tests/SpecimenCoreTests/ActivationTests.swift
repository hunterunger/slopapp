import Foundation
import Testing
@testable import SpecimenCore

@Suite struct ActivationTests {
    let exists: (String) -> Bool = { _ in true }

    @Test func turnsOffUserFonts() {
        let a = face("A", family: "A")
        let plan = ActivationPlanner.plan(targets: [a], enable: false, library: [a], testRoot: nil, fileExists: exists)
        #expect(plan.changes == [a])
        #expect(plan.locked.isEmpty)
    }

    @Test func locksSystemAndComputerFonts() {
        let system = face("Helvetica", family: "Helvetica", path: "/System/Library/Fonts/Helvetica.ttc")
        let computer = face("Arial", family: "Arial", path: "/Library/Fonts/Arial.ttf")
        let plan = ActivationPlanner.plan(targets: [system, computer], enable: false, library: [system, computer], testRoot: nil, fileExists: exists)
        #expect(plan.changes.isEmpty)
        #expect(plan.locked.count == 2)
        #expect(plan.lockReasons == [.system, .computer])
        #expect(plan.isEmpty)
    }

    @Test func missingFileIsLocked() {
        let gone = face("Gone", family: "Gone")
        let plan = ActivationPlanner.plan(targets: [gone], enable: false, library: [gone], testRoot: nil, fileExists: { _ in false })
        #expect(plan.lockReasons == [.missingFile])
    }

    @Test func testModeOnlyAllowsTheTestFolder() {
        let test = face("T", family: "T", path: "/tmp/specimen-test/T.ttf")
        let privateTest = face("P", family: "P", path: "/private/tmp/specimen-test/P.ttf")
        let user = face("U", family: "U")
        let root = URL(fileURLWithPath: "/tmp/specimen-test")
        let plan = ActivationPlanner.plan(targets: [test, privateTest, user], enable: false, library: [test, privateTest, user], testRoot: root, fileExists: exists)
        #expect(plan.changes.map(\.postScriptName) == ["T", "P"])
        #expect(plan.lockReasons == [.testMode])
        // A sibling folder with the same prefix doesn't count.
        let sibling = face("S", family: "S", path: "/tmp/specimen-test2/S.ttf")
        #expect(ActivationPlanner.lockReason(for: sibling, testRoot: root, fileExists: exists) == .testMode)
    }

    @Test func alreadyInStateIsNoOp() {
        let off = face("Off", family: "Off", enabled: false)
        let plan = ActivationPlanner.plan(targets: [off, off], enable: false, library: [off], testRoot: nil, fileExists: exists)
        #expect(plan.alreadyDone == [off])
        #expect(plan.isEmpty)
    }

    @Test func clashingPostScriptNameOffersSwap() {
        let active = face("Dup", family: "Dup", path: "/Users/test/Library/Fonts/Dup-old.otf")
        let wanted = face("Dup", family: "Dup", path: "/Users/test/Fonts/Dup-new.otf", enabled: false)
        let plan = ActivationPlanner.plan(targets: [wanted], enable: true, library: [active, wanted], testRoot: nil, fileExists: exists)
        #expect(plan.changes.isEmpty)
        #expect(plan.conflicts.count == 1)
        #expect(plan.swapOffs == [active])
        #expect(plan.swapOns == [wanted])
    }

    @Test func clashWithSystemCopyCantSwap() {
        let system = face("Dup", family: "Dup", path: "/System/Library/Fonts/Dup.ttc")
        let wanted = face("Dup", family: "Dup", enabled: false)
        let plan = ActivationPlanner.plan(targets: [wanted], enable: true, library: [system, wanted], testRoot: nil, fileExists: exists)
        #expect(plan.conflicts.first?.activeCopyLock == .system)
        #expect(plan.swapOffs.isEmpty)
    }

    @Test func wontTurnOffACopyThatSharesANameWithAProtectedFont() {
        // macOS turns fonts off by PostScript name, so this would also turn off Apple's copy.
        let system = face("Helvetica", family: "Helvetica", path: "/System/Library/Fonts/Helvetica.ttc")
        let mine = face("Helvetica", family: "Helvetica", path: "/Users/test/Library/Fonts/Helvetica.ttf")
        let plan = ActivationPlanner.plan(targets: [mine], enable: false, library: [system, mine], testRoot: nil, fileExists: exists)
        #expect(plan.changes.isEmpty)
        #expect(plan.lockReasons == [.sharedName])
        // Two unprotected copies are fine.
        let other = face("Helvetica", family: "Helvetica", path: "/Users/test/Fonts/Helvetica.ttf")
        let ok = ActivationPlanner.plan(targets: [mine], enable: false, library: [other, mine], testRoot: nil, fileExists: exists)
        #expect(ok.changes == [mine])
    }

    @Test func twoCopiesSelectedOnlyOneTurnsOn() {
        let a = face("Dup", family: "Dup", path: "/Users/test/a.otf", enabled: false)
        let b = face("Dup", family: "Dup", path: "/Users/test/b.otf", enabled: false)
        let plan = ActivationPlanner.plan(targets: [a, b], enable: true, library: [a, b], testRoot: nil, fileExists: exists)
        #expect(plan.changes == [a])
        #expect(plan.conflicts.map(\.face) == [b])
    }

    @Test func bulkConfirmation() {
        let many = (0..<101).map { face("F\($0)", family: "F\($0)", enabled: false) }
        #expect(ActivationPlanner.plan(targets: many, enable: true, library: many, testRoot: nil, fileExists: exists).needsConfirmation)
        #expect(!ActivationPlanner.plan(targets: Array(many.prefix(100)), enable: true, library: many, testRoot: nil, fileExists: exists).needsConfirmation)
        #expect(!ActivationPlanner.plan(targets: many.map { var f = $0; f.isEnabled = true; return f }, enable: false, library: many, testRoot: nil, fileExists: exists).needsConfirmation)
    }

    @Test func reportsFacesThatDidNotChange() {
        let a = face("A", family: "A"), b = face("B", family: "B")
        var after = [a, b]
        after[0].isEnabled = false
        #expect(ActivationPlanner.failures(requested: [a, b], enable: false, after: after) == [b])
    }

    @Test func fakeSystemRoundTrip() {
        let system = FakeFontSystem([SystemFace(postScriptName: "A", familyName: "A", styleName: "Regular", path: "/u/A.otf")])
        let index = FontIndexer(system: system).build(cache: IndexCache())
        system.setEnabled(index.faces, enabled: false)
        #expect(system.listFaces().first?.isEnabled == false)
        let updated = FontIndexer.applyStates(system.listFaces(), to: index.faces)
        #expect(updated?.first?.isEnabled == false)
    }
}
