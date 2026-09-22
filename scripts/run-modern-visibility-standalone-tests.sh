#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ice-modern-visibility-tests.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

MAIN="$TMP_ROOT/main.swift"
BIN="$TMP_ROOT/modern-visibility-tests"

cat > "$MAIN" <<'SWIFT'
import CoreGraphics
import ApplicationServices
import Foundation

@discardableResult
func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
    if !condition() {
        fputs("FAIL: \(message) (\(file):\(line))\n", stderr)
        exit(1)
    }
    return true
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        fputs("FAIL: \(message) expected \(expected), got \(actual) (\(file):\(line))\n", stderr)
        exit(1)
    }
}

func checkNil<T>(_ value: T?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if let value {
        fputs("FAIL: \(message) expected nil, got \(value) (\(file):\(line))\n", stderr)
        exit(1)
    }
}

func checkNotNil<T>(_ value: T?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    if value == nil {
        fputs("FAIL: \(message) expected non-nil (\(file):\(line))\n", stderr)
        exit(1)
    }
}

var executed = 0
func test(_ name: String, _ body: () throws -> Void) rethrows {
    try body()
    executed += 1
    print("✓ \(name)")
}

func item(_ bundle: String, title: String = "Item", x: CGFloat = 0, pid: pid_t = 100) -> ModernMenuBarItem {
    ModernMenuBarItem(
        id: .status(bundle: bundle, title: title),
        frame: CGRect(x: x, y: 0, width: 22, height: 22),
        appName: bundle,
        hostIsBundleless: false,
        pid: pid
    )
}

func systemAnchor() -> ModernMenuBarItem {
    ModernMenuBarItem(
        id: .status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.controlcenter"),
        frame: CGRect(x: 40, y: 0, width: 22, height: 22),
        appName: nil,
        hostIsBundleless: false,
        pid: 200
    )
}

func system(_ name: String) -> ModernItemID {
    .status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.\(name)")
}

test("Accessibility transport failures cannot verify hiding") {
    for error: AXError in [.cannotComplete, .invalidUIElement, .apiDisabled, .failure] {
        check(ModernItemEnumerator.isIncompleteRead(error), "transport error must mark snapshot incomplete")
    }
    for error: AXError in [.success, .attributeUnsupported, .noValue] {
        check(!ModernItemEnumerator.isIncompleteRead(error), "absent optional attribute is not a transport error")
    }
}

test("readable anchored snapshot confirms hidden targets are gone") {
    var plan = ModernVisibilityPlan()
    plan.bundles = ["example.hidden"]
    let snapshot = ModernMenuBarSnapshot(items: [item("example.visible"), systemAnchor()], isReadable: true)
    checkEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .confirmedHidden, "readable anchored snapshot should confirm hidden")
}

test("empty or partial snapshots do not create false success") {
    var plan = ModernVisibilityPlan()
    plan.bundles = ["example.hidden"]
    checkEqual(
        ModernVisibilityVerifier.verify(plan, in: ModernMenuBarSnapshot(items: [], isReadable: true)),
        .unreadable,
        "empty readable snapshot cannot verify hiding"
    )
    checkEqual(
        ModernVisibilityVerifier.verify(plan, in: ModernMenuBarSnapshot(items: [item("example.visible")], isReadable: true)),
        .unreadable,
        "snapshot without a system anchor cannot verify hiding"
    )
    checkEqual(
        ModernVisibilityVerifier.verify(
            plan,
            in: ModernMenuBarSnapshot(items: [item("example.visible"), systemAnchor()], isReadable: true, hasReadErrors: true)
        ),
        .unreadable,
        "snapshot with read errors cannot verify hiding"
    )
}

test("visible concealed target is reported") {
    var plan = ModernVisibilityPlan()
    plan.bundles = ["example.hidden"]
    let hidden = item("example.hidden")
    let snapshot = ModernMenuBarSnapshot(items: [hidden, systemAnchor()], isReadable: true)
    checkEqual(ModernVisibilityVerifier.verify(plan, in: snapshot), .stillVisible([hidden.id]), "visible concealed target should fail verification")
}

test("partial discovery accepts new observed items and retains alive previous items") {
    let retainedVisible = item("example.visible", x: 30, pid: 101)
    let retainedHidden = item("example.hidden", x: 20, pid: 102)
    let droppedDead = item("example.dead", x: 10, pid: 103)
    let observedNew = item("example.new", x: 40, pid: 104)
    let ownItem = item("ice", x: 50, pid: 105)
    var plan = ModernVisibilityPlan()
    plan.bundles = ["example.hidden"]
    let merged = ModernItemDiscovery.mergedItems(
        previous: [retainedVisible, retainedHidden, droppedDead],
        observed: [observedNew, ownItem],
        appliedVisibility: plan,
        retainAllUnobserved: true,
        ownBundle: "ice",
        isAlive: { $0 != droppedDead.pid }
    )
    checkEqual(merged.map(\.id), [retainedHidden.id, retainedVisible.id, observedNew.id], "partial discovery should retain alive previous items and accept new observed items")
}

test("complete discovery only retains concealed alive items") {
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
        ownBundle: "ice",
        isAlive: { _ in true }
    )
    checkEqual(merged.map(\.id), [hidden.id, observed.id], "complete discovery should prune ordinary missing visible items")
}

test("missing callback can still confirm from snapshot") {
    var lifecycle = ModernVisibilityLifecycle()
    let generation = lifecycle.beginActivation()
    checkEqual(lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true), .confirmed, "snapshot confirmation should activate lifecycle")
    checkEqual(lifecycle.state, .active, "lifecycle should become active")
}

test("late callbacks and stale generations are ignored") {
    var lifecycle = ModernVisibilityLifecycle()
    let generation = lifecycle.beginActivation()
    checkEqual(lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true), .confirmed, "first generation should confirm")
    check(!lifecycle.handleCallback(generation: generation), "late callback after confirmation should be ignored")

    let staleGeneration = lifecycle.beginActivation()
    _ = lifecycle.beginActivation()
    checkEqual(
        lifecycle.verify(generation: staleGeneration, result: .confirmedHidden, allowFailure: true),
        .ignoredStale,
        "stale verification should be ignored"
    )
    check(lifecycle.isPending, "new generation should remain pending")
}

test("pending visible target keeps waiting before deadline") {
    var lifecycle = ModernVisibilityLifecycle()
    let generation = lifecycle.beginActivation()
    let hidden = ModernItemID.status(bundle: "example.hidden", title: "Item")
    checkEqual(
        lifecycle.verify(generation: generation, result: .stillVisible([hidden]), allowFailure: false),
        .keepWaiting,
        "pending observation should not fail before timeout"
    )
    checkEqual(lifecycle.generation, generation, "generation should not change while still waiting")
    check(lifecycle.isPending, "lifecycle should stay pending")
}

test("unreadable verification retries are bounded without dropping assertion") {
    var lifecycle = ModernVisibilityLifecycle(unreadableRetryLimit: 2)
    let generation = lifecycle.beginActivation()
    checkEqual(lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true), .keepWaiting, "first unreadable retry should wait")
    checkEqual(lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true), .keepWaiting, "second unreadable retry should wait")
    checkEqual(lifecycle.verify(generation: generation, result: .unreadable, allowFailure: true), .activeButUnverified, "third unreadable result should become active unverified")
    checkEqual(lifecycle.state, .activeUnverified, "assertion should remain active but unverified")
}

test("confirmed or unverified assertion fails if concealed target reappears") {
    var lifecycle = ModernVisibilityLifecycle()
    let generation = lifecycle.beginActivation()
    checkEqual(lifecycle.verify(generation: generation, result: .confirmedHidden, allowFailure: true), .confirmed, "assertion should confirm")
    let hidden = ModernItemID.status(bundle: "example.hidden", title: "Item")
    checkEqual(
        lifecycle.observeActive(.stillVisible([hidden])),
        .failed(message: "macOS did not apply menu bar hiding."),
        "concealed target reappearing should fail"
    )
    checkEqual(lifecycle.generation, generation + 1, "failure should advance generation")

    var unverified = ModernVisibilityLifecycle(unreadableRetryLimit: 0)
    let unverifiedGeneration = unverified.beginActivation()
    checkEqual(unverified.verify(generation: unverifiedGeneration, result: .unreadable, allowFailure: true), .activeButUnverified, "unreadable should become active unverified")
    checkEqual(unverified.observeActive(.confirmedHidden), .confirmed, "later readable success should clear unverified state")
    checkEqual(unverified.state, .active, "unverified assertion should become confirmed active")
}

test("same-plan failures increment and retry budget exhausts") {
    var plan = ModernVisibilityPlan()
    plan.bundles = ["example.hidden"]
    let first = ModernVisibilityFailure.record(previous: nil, plan: plan, message: "failed")
    let second = ModernVisibilityFailure.record(previous: first, plan: plan, message: "failed")
    let third = ModernVisibilityFailure.record(previous: second, plan: plan, message: "failed")
    let fourth = ModernVisibilityFailure.record(previous: third, plan: plan, message: "failed")
    let policy = ModernVisibilityRetryPolicy(maxAutomaticRetries: 3, initialDelay: 0.5)
    checkEqual(first.failureCount, 1, "first failure count")
    checkEqual(second.failureCount, 2, "second failure count")
    checkEqual(third.failureCount, 3, "third failure count")
    checkEqual(fourth.failureCount, 4, "fourth failure count")
    checkNotNil(policy.delay(afterFailureCount: third.failureCount), "third failure should still be retryable")
    checkNil(policy.delay(afterFailureCount: fourth.failureCount), "fourth failure should exhaust automatic retry")

    var otherPlan = ModernVisibilityPlan()
    otherPlan.bundles = ["example.other"]
    let reset = ModernVisibilityFailure.record(previous: fourth, plan: otherPlan, message: "failed")
    checkEqual(reset.failureCount, 1, "different plan should reset attempt history")
}

test("modern layout preserves bundle and system assignments") {
    var layout = ModernMenuBarLayout()
    layout.assignments["example.visible"] = .visible
    layout.assignments["example.hidden"] = .hidden
    layout.assignments["example.private"] = .alwaysHidden
    checkEqual(layout.concealedBundles(revealing: [.hidden]), ["example.private"], "revealing hidden should not reveal always-hidden")
    checkEqual(layout.section(for: ModernItemID.status(bundle: "example.hidden", title: "Renamed")), .hidden, "title changes should keep bundle assignment")

    layout.assignments[system("wifi").assignmentKey] = .hidden
    let plan = layout.visibilityPlan(revealing: [], runningBundles: ["example.hidden", "com.apple.MenuBarAgent"], ownBundle: "ice")
    check(plan.requiresAssertion, "plan should require assertion")
    check(plan.systemItems.contains(.wifi), "Wi-Fi should hide as its own system item")
    check(!plan.allowedSystemItems.contains(.wifi), "Wi-Fi should be excluded from allowed system items")
    check(plan.allowedSystemItems.contains(.battery), "Battery should remain allowed")
    checkEqual(layout.section(for: system("battery")), .visible, "other system controls should remain visible")

    let encoded = try! JSONEncoder().encode(layout)
    let decoded = try! JSONDecoder().decode(ModernMenuBarLayout.self, from: encoded)
    checkEqual(decoded, layout, "layout should round-trip")
}

test("move verification rejects unchanged already-before order") {
    let source = ModernItemID.status(bundle: "example.source", title: "Item")
    let middle = ModernItemID.status(bundle: "example.middle", title: "Item")
    let target = ModernItemID.status(bundle: "example.target", title: "Item")
    let before = [
        ModernMoveVerificationItem(id: source, midX: 10),
        ModernMoveVerificationItem(id: middle, midX: 20),
        ModernMoveVerificationItem(id: target, midX: 30),
    ]
    check(!ModernMoveVerification.acceptedMoveBefore(source, targetID: target, before: before, after: before), "unchanged already-before order should not count as a successful reorder")

    let after = [
        ModernMoveVerificationItem(id: source, midX: 10),
        ModernMoveVerificationItem(id: target, midX: 20),
        ModernMoveVerificationItem(id: middle, midX: 30),
    ]
    check(ModernMoveVerification.acceptedMoveBefore(source, targetID: target, before: before, after: after), "new adjacency before target should count")
}

test("auxiliary reservation geometry stays on divider display") {
    let leftDisplay = CGRect(x: -1512, y: 0, width: 1512, height: 982)
    let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let divider = CGRect(x: 900, y: 0, width: 30, height: 33)
    let leftDisplayOverlay = CGRect(x: -500, y: 0, width: 180, height: 33)
    let mainDisplayOverlay = CGRect(x: 700, y: 0, width: 180, height: 33)
    let frames = AuxiliaryStatusItemReservationGeometry.rowFrames(
        from: [leftDisplayOverlay, mainDisplayOverlay],
        dividerFrame: divider,
        displayBounds: [leftDisplay, mainDisplay]
    )
    checkEqual(frames, [mainDisplayOverlay], "row frames should keep only overlays on divider display")

    var cache = AuxiliaryStatusItemReservationCache()
    checkEqual(cache.reserve(66, displayID: 1, hasAnchors: true), 66, "cache should capture first positive reservation")
    checkEqual(cache.reserve(312, displayID: 1, hasAnchors: true), 66, "cache should not grow during same-display layout")
    checkEqual(cache.reserve(0, displayID: 1, hasAnchors: true), 66, "cache should keep space while anchors exist")
    checkEqual(cache.reserve(0, displayID: 2, hasAnchors: true), 0, "cache should not carry reservation to another display")
}

print("modern visibility/layout/geometry standalone tests passed (\(executed) tests)")
SWIFT

cd "$REPO_ROOT"
xcrun swiftc \
    -O \
    -o "$BIN" \
    "$MAIN" \
    Ice/MenuBar/Modern/ModernMenuBarLayout.swift \
    Ice/MenuBar/Modern/ModernSystemItem.swift \
    Ice/MenuBar/Modern/ModernItemEnumerator.swift \
    Ice/MenuBar/Modern/ModernVisibilityLifecycle.swift \
    Ice/MenuBar/ControlItem/AuxiliaryStatusItemReservationGeometry.swift
"$BIN"
