import XCTest
@testable import Ice

final class ModernMenuBarLayoutTests: XCTestCase {
    func testNewAppsRemainVisible() {
        let layout = ModernMenuBarLayout()
        XCTAssertEqual(layout.section(for: "example.new"), .visible)
        XCTAssertTrue(layout.concealedBundles(revealing: []).isEmpty)
    }

    func testRevealingHiddenDoesNotRevealAlwaysHidden() {
        var layout = ModernMenuBarLayout()
        layout.assignments = ["example.visible": .visible, "example.hidden": .hidden, "example.private": .alwaysHidden]
        XCTAssertEqual(layout.concealedBundles(revealing: [.hidden]), ["example.private"])
        XCTAssertEqual(layout.concealedBundles(revealing: []), ["example.hidden", "example.private"])
        XCTAssertTrue(layout.concealedBundles(revealing: Set(ModernMenuBarLayout.Section.allCases)).isEmpty)
    }

    func testChangingAppTitleDoesNotLoseItsSection() {
        var layout = ModernMenuBarLayout()
        let old = ModernItemID.status(bundle: "example.app", title: "20%")
        let updated = ModernItemID.status(bundle: "example.app", title: "21%")
        layout.assignments[old.bundleID] = .hidden
        XCTAssertEqual(layout.section(for: updated.bundleID), .hidden)
        XCTAssertNotEqual(old, updated)
    }

    func testLayoutRoundTripsWithoutLegacyDefaults() throws {
        var layout = ModernMenuBarLayout()
        layout.assignments["example.app"] = .alwaysHidden
        let encoded = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(ModernMenuBarLayout.self, from: encoded), layout)
    }

    func testUnknownSectionCannotSilentlyHideAnApp() {
        let data = Data(#"{"assignments":{"example.app":"unknown"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ModernMenuBarLayout.self, from: data))
    }

    private func system(_ name: String) -> ModernItemID {
        .status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.\(name)")
    }

    func testWiFiCanHideWithoutHidingBatteryOrItsHost() {
        var layout = ModernMenuBarLayout()
        layout.assignments[system("wifi").assignmentKey] = .hidden
        let plan = layout.visibilityPlan(revealing: [], runningBundles: ["com.apple.MenuBarAgent"], ownBundle: "ice")
        XCTAssertTrue(plan.requiresAssertion)
        XCTAssertEqual(plan.systemItems, [.wifi])
        XCTAssertFalse(plan.allowedSystemItems.contains(.wifi))
        XCTAssertTrue(plan.allowedSystemItems.contains(.battery))
        XCTAssertTrue(plan.allowedSystemItems.contains(.controlCenter))
        XCTAssertTrue(plan.bundles.isEmpty)
        XCTAssertEqual(layout.section(for: system("battery")), .visible)
        XCTAssertTrue(system("wifi").supportsHiding)
        XCTAssertFalse(system("controlcenter").supportsHiding)
    }

    func testSystemSectionsRevealIndependentlyAndSurviveRelaunch() throws {
        var layout = ModernMenuBarLayout()
        layout.assignments[system("wifi").assignmentKey] = .hidden
        layout.assignments[system("battery").assignmentKey] = .alwaysHidden
        layout = try JSONDecoder().decode(ModernMenuBarLayout.self, from: JSONEncoder().encode(layout))
        let plan = layout.visibilityPlan(revealing: [.hidden], runningBundles: [], ownBundle: "ice")
        XCTAssertEqual(plan.systemItems, [.battery])
        XCTAssertFalse(plan.conceals(system("wifi")))
        XCTAssertTrue(plan.conceals(system("battery")))
        let editing = layout.visibilityPlan(revealing: Set(ModernMenuBarLayout.Section.allCases), runningBundles: [], ownBundle: "ice")
        XCTAssertFalse(editing.requiresAssertion)
    }

    func testUserAloneActivatesGroupedHidingAndRestoresOnReveal() {
        var layout = ModernMenuBarLayout()
        layout.assignments[system("user").assignmentKey] = .hidden
        let hidden = layout.visibilityPlan(revealing: [], runningBundles: [], ownBundle: "ice")
        XCTAssertTrue(hidden.requiresAssertion)
        XCTAssertTrue(hidden.conceals(system("user")))
        XCTAssertFalse(hidden.conceals(system("wifi")))
        XCTAssertTrue(hidden.bundles.isEmpty)
        let visible = layout.visibilityPlan(revealing: [.hidden], runningBundles: [], ownBundle: "ice")
        XCTAssertFalse(visible.requiresAssertion)
        XCTAssertFalse(visible.conceals(system("user")))
    }

    func testUserIsAlsoConcealedByAnyOtherHidingRequest() {
        var layout = ModernMenuBarLayout()
        layout.assignments["example.app"] = .hidden
        let plan = layout.visibilityPlan(revealing: [], runningBundles: ["example.app"], ownBundle: "ice")
        XCTAssertTrue(plan.conceals(system("user")))
        XCTAssertFalse(plan.conceals(system("controlcenter")))
    }

    func testOldAppAssignmentsDecodeAndUnsupportedAppleHostsStayVisible() throws {
        let data = Data(#"{"assignments":{"example.app":"hidden","com.apple.MenuBarAgent":"hidden","ice":"hidden"}}"#.utf8)
        let layout = try JSONDecoder().decode(ModernMenuBarLayout.self, from: data)
        let plan = layout.visibilityPlan(revealing: [], runningBundles: ["example.app", "com.apple.MenuBarAgent", "ice"], ownBundle: "ice")
        XCTAssertEqual(plan.bundles, ["example.app"])
        XCTAssertTrue(plan.systemItems.isEmpty)
        XCTAssertFalse(system("unknown").supportsHiding)
        XCTAssertEqual(layout.section(for: system("wifi")), .visible)
    }
}
