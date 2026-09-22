import XCTest
@testable import Ice

final class ModernVisibilityLifecycleTests: XCTestCase {
    private func item(_ bundle: String, title: String = "Item", x: CGFloat = 0, pid: pid_t = 100) -> ModernMenuBarItem {
        ModernMenuBarItem(
            id: .status(bundle: bundle, title: title),
            frame: CGRect(x: x, y: 0, width: 22, height: 22),
            appName: bundle,
            hostIsBundleless: false,
            pid: pid
        )
    }

    private func systemAnchor() -> ModernMenuBarItem {
        ModernMenuBarItem(
            id: .status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.controlcenter"),
            frame: CGRect(x: 40, y: 0, width: 22, height: 22),
            appName: nil,
            hostIsBundleless: false,
            pid: 200
        )
    }

    func testReadableSnapshotConfirmsHiddenWhenTargetsAreGone() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let snapshot = ModernMenuBarSnapshot(items: [item("example.visible"), systemAnchor()], isReadable: true)
        XCTAssertEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .confirmedHidden)
    }

    func testEmptyReadableSnapshotDoesNotConfirmHidden() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let snapshot = ModernMenuBarSnapshot(items: [], isReadable: true)
        XCTAssertEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .unreadable)
    }

    func testStillVisibleTargetFailsVerification() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let snapshot = ModernMenuBarSnapshot(items: [item("example.hidden"), systemAnchor()], isReadable: true)
        XCTAssertEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .stillVisible([item("example.hidden").id]))
    }

    func testPartialSnapshotWithoutSystemAnchorDoesNotConfirmHidden() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let snapshot = ModernMenuBarSnapshot(items: [item("example.visible")], isReadable: true)
        XCTAssertEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .unreadable)
    }

    func testSnapshotWithReadErrorsDoesNotConfirmHiddenEvenWithAnchor() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let snapshot = ModernMenuBarSnapshot(
            items: [item("example.visible"), systemAnchor()],
            isReadable: true,
            hasReadErrors: true
        )
        XCTAssertEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .unreadable)
    }

    func testPartialDiscoveryRetainsAliveUnobservedItemsAndAcceptsNewObservedItems() {
        let retainedVisible = item("example.visible", x: 30, pid: 101)
        let retainedHidden = item("example.hidden", x: 20, pid: 102)
        let droppedDead = item("example.dead", x: 10, pid: 103)
        let observedNew = item("example.new", x: 40, pid: 104)
        let ownItem = item(Constants.bundleIdentifier, x: 50, pid: 105)
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]

        let merged = ModernItemDiscovery.mergedItems(
            previous: [retainedVisible, retainedHidden, droppedDead],
            observed: [observedNew, ownItem],
            appliedVisibility: plan,
            retainAllUnobserved: true,
            ownBundle: Constants.bundleIdentifier,
            isAlive: { $0 != droppedDead.pid }
        )

        XCTAssertEqual(merged.map(\.id), [retainedHidden.id, retainedVisible.id, observedNew.id])
    }

    func testCompleteDiscoveryOnlyRetainsConcealedAliveItems() {
        let visible = item("example.visible", x: 10, pid: 101)
        let hidden = item("example.hidden", x: 20, pid: 102)
        let observed = item("example.observed", x: 30, pid: 103)
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]

        let merged = ModernItemDiscovery.mergedItems(
            previous: [visible, hidden],
            observed: [observed],
            appliedVisibility: plan,
            retainAllUnobserved: false,
            ownBundle: Constants.bundleIdentifier,
            isAlive: { _ in true }
        )

        XCTAssertEqual(merged.map(\.id), [hidden.id, observed.id])
    }

    func testMissingCallbackCanStillConfirmFromSnapshot() {
        var lifecycle = ModernVisibilityLifecycle()
        let generation = lifecycle.beginActivation()
        let outcome = lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true)
        XCTAssertEqual(outcome, .confirmed)
        XCTAssertEqual(lifecycle.state, .active)
    }

    func testLateCallbackAfterSnapshotConfirmationIsIgnored() {
        var lifecycle = ModernVisibilityLifecycle()
        let generation = lifecycle.beginActivation()
        XCTAssertEqual(lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true), .confirmed)
        XCTAssertFalse(lifecycle.handleCallback(generation: generation))
    }

    func testStaleGenerationVerificationIsIgnored() {
        var lifecycle = ModernVisibilityLifecycle()
        let staleGeneration = lifecycle.beginActivation()
        _ = lifecycle.beginActivation()
        XCTAssertEqual(
            lifecycle.verify(generation: staleGeneration, result: .confirmedHidden, allowFailure: true),
            .ignoredStale
        )
        XCTAssertTrue(lifecycle.isPending)
    }

    func testPendingObservationCannotFailBeforeDeadline() {
        var lifecycle = ModernVisibilityLifecycle()
        let generation = lifecycle.beginActivation()
        let hidden = ModernItemID.status(bundle: "example.hidden", title: "Item")
        XCTAssertEqual(
            lifecycle.verify(generation: generation, result: .stillVisible([hidden]), allowFailure: false),
            .keepWaiting
        )
        XCTAssertEqual(lifecycle.generation, generation)
        XCTAssertTrue(lifecycle.isPending)
    }

    func testUnreadableVerificationRetriesAreBoundedWithoutDroppingAssertion() {
        var lifecycle = ModernVisibilityLifecycle(unreadableRetryLimit: 2)
        let generation = lifecycle.beginActivation()
        XCTAssertEqual(lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true), .keepWaiting)
        XCTAssertEqual(lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true), .keepWaiting)
        XCTAssertEqual(
            lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true),
            .activeButUnverified
        )
        XCTAssertEqual(lifecycle.state, .activeUnverified)
    }

    func testConfirmedAssertionFailsIfConcealedTargetLaterReappears() {
        var lifecycle = ModernVisibilityLifecycle()
        let generation = lifecycle.beginActivation()
        XCTAssertEqual(lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true), .confirmed)
        let hidden = ModernItemID.status(bundle: "example.hidden", title: "Item")
        XCTAssertEqual(
            lifecycle.observeActive(.stillVisible([hidden])),
            .failed(message: "macOS did not apply menu bar hiding.")
        )
        XCTAssertEqual(lifecycle.generation, generation + 1)
    }

    func testConsecutiveFailuresForSamePlanIncrementAttemptHistory() {
        var plan = ModernVisibilityPlan()
        plan.bundles = ["example.hidden"]
        let first = ModernVisibilityFailure.record(previous: nil, plan: plan, message: "failed")
        let second = ModernVisibilityFailure.record(previous: first, plan: plan, message: "failed")
        let third = ModernVisibilityFailure.record(previous: second, plan: plan, message: "failed")
        let fourth = ModernVisibilityFailure.record(previous: third, plan: plan, message: "failed")
        let policy = ModernVisibilityRetryPolicy(maxAutomaticRetries: 3, initialDelay: 0.5)
        XCTAssertEqual(first.failureCount, 1)
        XCTAssertEqual(second.failureCount, 2)
        XCTAssertEqual(third.failureCount, 3)
        XCTAssertEqual(fourth.failureCount, 4)
        XCTAssertNotNil(policy.delay(afterFailureCount: third.failureCount))
        XCTAssertNil(policy.delay(afterFailureCount: fourth.failureCount))
    }

    func testDifferentPlanResetsAttemptHistory() {
        var firstPlan = ModernVisibilityPlan()
        firstPlan.bundles = ["example.hidden"]
        var secondPlan = ModernVisibilityPlan()
        secondPlan.bundles = ["example.other"]
        let first = ModernVisibilityFailure.record(previous: nil, plan: firstPlan, message: "failed")
        let reset = ModernVisibilityFailure.record(previous: first, plan: secondPlan, message: "failed")
        XCTAssertEqual(reset.failureCount, 1)
    }

    func testAutomaticRetryBackoffIsBounded() {
        let policy = ModernVisibilityRetryPolicy(maxAutomaticRetries: 3, initialDelay: 0.5)
        XCTAssertEqual(policy.delay(afterFailureCount: 1), 0.5)
        XCTAssertEqual(policy.delay(afterFailureCount: 2), 1.0)
        XCTAssertEqual(policy.delay(afterFailureCount: 3), 2.0)
        XCTAssertNil(policy.delay(afterFailureCount: 4))
    }

    func testMoveVerificationRejectsUnchangedAlreadyBeforeOrder() {
        let source = ModernItemID.status(bundle: "example.source", title: "Item")
        let middle = ModernItemID.status(bundle: "example.middle", title: "Item")
        let target = ModernItemID.status(bundle: "example.target", title: "Item")
        let before = [
            ModernMoveVerificationItem(id: source, midX: 10),
            ModernMoveVerificationItem(id: middle, midX: 20),
            ModernMoveVerificationItem(id: target, midX: 30),
        ]
        XCTAssertFalse(
            ModernMoveVerification.acceptedMoveBefore(source, targetID: target, before: before, after: before)
        )
    }

    func testMoveVerificationAcceptsNewBeforeTargetOrder() {
        let source = ModernItemID.status(bundle: "example.source", title: "Item")
        let target = ModernItemID.status(bundle: "example.target", title: "Item")
        let before = [
            ModernMoveVerificationItem(id: target, midX: 10),
            ModernMoveVerificationItem(id: source, midX: 20),
        ]
        let after = [
            ModernMoveVerificationItem(id: source, midX: 10),
            ModernMoveVerificationItem(id: target, midX: 20),
        ]
        XCTAssertTrue(
            ModernMoveVerification.acceptedMoveBefore(source, targetID: target, before: before, after: after)
        )
    }
}
