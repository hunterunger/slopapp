import Foundation
import Testing
@testable import AwakeCore

@Suite struct URLCommandTests {
    func parse(_ text: String) -> URLCommand? { URLCommand(url: URL(string: text)!) }

    @Test func activateForms() {
        #expect(parse("slopawake://activate") == .activate(.defaultDuration))
        #expect(parse("slopawake:activate") == .activate(.defaultDuration))
        #expect(parse("slopawake://activate?minutes=45") == .activate(.duration(.minutes(45))))
        #expect(parse("slopawake://activate?hours=1&minutes=30") == .activate(.duration(.minutes(90))))
        #expect(parse("slopawake://activate?indefinitely") == .activate(.duration(.indefinitely)))
        #expect(parse("slopawake://activate?until=17:30") == .activate(.until(hour: 17, minute: 30)))
        #expect(parse("SLOPAWAKE://Activate?Hours=2") == .activate(.duration(.hours(2))))
    }

    @Test func otherVerbs() {
        #expect(parse("slopawake://deactivate") == .deactivate)
        #expect(parse("slopawake://toggle") == .toggle(.defaultDuration))
        #expect(parse("slopawake://toggle?hours=1") == .toggle(.duration(.hours(1))))
    }

    @Test(arguments: [
        "slopawake://explode", "https://activate", "slopawake://activate?until=25:00",
        "slopawake://activate?until=noon", "slopawake://activate?minutes=0", "slopawake://activate?hours=-1",
        "slopawake://activate?minutes=abc",
    ])
    func rejects(text: String) {
        #expect(parse(text) == nil)
    }

    @MainActor @Test func performRunsCommands() {
        let scheduler = ManualScheduler()
        let store = TestDefaults()
        let controller = AwakeController(
            assertion: FakeAssertion(), scheduler: scheduler,
            preferences: AwakePreferences(defaults: store.defaults),
            monitors: FakeSystem().monitors, clock: { scheduler.now }
        )
        controller.perform(.activate(.duration(.minutes(45))))
        #expect(controller.session?.duration == .minutes(45))
        controller.perform(.toggle(.defaultDuration))
        #expect(!controller.isActive)
        controller.perform(.toggle(.defaultDuration))
        #expect(controller.session?.duration == .indefinitely)
        controller.perform(.activate(.until(hour: 3, minute: 0)))
        if case .until = controller.session?.kind {} else { Issue.record("expected an until session") }
        controller.perform(.deactivate)
        #expect(!controller.isActive)
    }
}
