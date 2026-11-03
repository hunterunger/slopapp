import Foundation
import Testing
@testable import TidyCore

/// Round 1 regression: ⌘⌫ in the search field trashed an app that wasn't visible.
@Suite("Review rules")
struct ReviewRuleTests {
    @Test func onlyVisibleCheckedItemsAreActionable() {
        let visible = ["/a", "/c"]
        #expect(ReviewRules.actionable(checked: ["/a", "/b", "/c"], visible: visible) == ["/a", "/c"])
        #expect(ReviewRules.actionable(checked: ["/b"], visible: visible).isEmpty)
        #expect(ReviewRules.actionable(checked: [], visible: visible).isEmpty)
    }

    @Test func selectionFollowsVisibleResults() {
        // Searching "Note" hides Tasker: the selected Tasker must not stay the target.
        let visible = ["/Applications/Notely.app", "/Applications/Notely Mini.app"]
        #expect(ReviewRules.reconcile(selection: "/Applications/Tasker.app", visible: visible) == nil)
        #expect(ReviewRules.reconcile(selection: "/Applications/Notely.app", visible: visible) == "/Applications/Notely.app")
        #expect(ReviewRules.reconcile(selection: nil, visible: visible) == nil)
        #expect(ReviewRules.reconcile(selection: Set(["/x", "/Applications/Notely.app"]), visible: visible) == ["/Applications/Notely.app"])
    }

    @Test func textEditingKeysGoToTheFocusedField() {
        #expect(ReviewRules.routesToTextField(isEditingText: true))
        #expect(!ReviewRules.routesToTextField(isEditingText: false))
    }

    @Test func uninstallFromAMenuAsksFirst() {
        let plan = UninstallPlan(appName: "Tasker", includesApp: true, itemCount: 3, bytes: 2_100_000)
        #expect(plan.needsConfirmation(.menuCommand))
        #expect(!plan.needsConfirmation(.reviewButton))
        #expect(plan.title == "Move Tasker to the Trash?")
        #expect(plan.message == "Tasker and 3 items, 2.1 MB, will be moved to the Trash. You can put them back.")
        let files = UninstallPlan(appName: "Tasker", includesApp: false, itemCount: 1, bytes: 4_000)
        #expect(files.title == "Move Tasker’s files to the Trash?")
        #expect(files.message.hasPrefix("1 item, "))
    }
}
