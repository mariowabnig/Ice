import AppKit
import XCTest
@testable import Ice

final class ModernMenuBarHealthTests: XCTestCase {
    @MainActor
    func testRunningSystemAgentHasUsableKernelIdentity() throws {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
            throw XCTSkip("MenuBarAgent is unavailable on this macOS version")
        }
        let identity = try XCTUnwrap(ModernMenuBarWatchdog.currentAgent())
        XCTAssertEqual(identity.pid, agent.processIdentifier)
        XCTAssertGreaterThan(identity.startSeconds, 0)
        XCTAssertEqual(identity, ModernMenuBarWatchdog.currentAgent())
    }

    private func sample(_ seconds: Double, pid: Int32 = 700, timedOut: Bool = true,
                        cpu: Double = 1, memory: UInt64 = 40_000_000) -> ModernMenuBarHealth.Sample {
        .init(pid: pid, uptime: seconds, cpuNanoseconds: UInt64(seconds * cpu * 1_000_000_000),
              residentBytes: memory, timedOut: timedOut)
    }

    func testSustainedBusyTimeoutsRecoverOnlyAfterObservationWindow() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            XCTAssertFalse(health.shouldRecover(sample(time), secondsSinceRecovery: 1800))
        }
        XCTAssertTrue(health.shouldRecover(sample(40), secondsSinceRecovery: 1800))
    }

    func testHighMemoryHangCanRecoverWithoutHighCPU() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            XCTAssertFalse(health.shouldRecover(sample(time, cpu: 0, memory: 2_000_000_000), secondsSinceRecovery: 1800))
        }
        XCTAssertTrue(health.shouldRecover(sample(40, cpu: 0, memory: 2_000_000_000), secondsSinceRecovery: 1800))
    }

    func testResourceUseAloneNeverRestartsResponsiveAgent() {
        var health = ModernMenuBarHealth()
        for time in stride(from: 0.0, through: 100, by: 10) {
            XCTAssertFalse(health.shouldRecover(sample(time, timedOut: false, memory: 5_000_000_000), secondsSinceRecovery: 1800))
        }
    }

    func testTimeoutAloneNeverRestartsAgent() {
        var health = ModernMenuBarHealth()
        for time in stride(from: 0.0, through: 100, by: 10) {
            XCTAssertFalse(health.shouldRecover(sample(time, cpu: 0.1), secondsSinceRecovery: 1800))
        }
    }

    func testCooldownIncludingClockRollbackPreventsRecovery() {
        for interval in [-100.0, 0, 1799] {
            var health = ModernMenuBarHealth()
            for time in stride(from: 0.0, through: 100, by: 10) {
                XCTAssertFalse(health.shouldRecover(sample(time), secondsSinceRecovery: interval))
            }
        }
    }

    func testClockJumpCannotShortenLiveCooldown() {
        XCTAssertEqual(ModernMenuBarHealth.secondsSinceRecovery(wallElapsed: 3600, uptimeElapsed: 60), 60)
        XCTAssertEqual(ModernMenuBarHealth.secondsSinceRecovery(wallElapsed: -60, uptimeElapsed: 1800), -60)
        XCTAssertEqual(ModernMenuBarHealth.secondsSinceRecovery(wallElapsed: 1800, uptimeElapsed: nil), 1800)
    }

    func testResourcePressureEndingResetsObservationWindow() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            _ = health.shouldRecover(sample(time, cpu: 0, memory: 2_000_000_000), secondsSinceRecovery: 1800)
        }
        XCTAssertFalse(health.shouldRecover(sample(40, cpu: 0), secondsSinceRecovery: 1800))
        XCTAssertFalse(health.shouldRecover(sample(50, cpu: 0, memory: 2_000_000_000), secondsSinceRecovery: 1800))
    }

    func testCounterRollbackAndNonAdvancingTimeDiscardEvidence() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            _ = health.shouldRecover(sample(time), secondsSinceRecovery: 1800)
        }
        var rollback = health
        XCTAssertFalse(rollback.shouldRecover(sample(40, cpu: 0), secondsSinceRecovery: 1800))
        XCTAssertFalse(health.shouldRecover(sample(30), secondsSinceRecovery: 1800))
    }

    func testSuccessfulReadResetsHangEvidence() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            _ = health.shouldRecover(sample(time), secondsSinceRecovery: 1800)
        }
        XCTAssertFalse(health.shouldRecover(sample(40, timedOut: false), secondsSinceRecovery: 1800))
        XCTAssertFalse(health.shouldRecover(sample(50), secondsSinceRecovery: 1800))
        XCTAssertFalse(health.shouldRecover(sample(60), secondsSinceRecovery: 1800))
    }

    func testProcessReplacementSleepGapAndResetDiscardOldEvidence() {
        var health = ModernMenuBarHealth()
        for time in [0.0, 10, 20, 30] {
            _ = health.shouldRecover(sample(time), secondsSinceRecovery: 1800)
        }
        var replacement = health
        XCTAssertFalse(replacement.shouldRecover(sample(40, pid: 701), secondsSinceRecovery: 1800))
        var afterSleep = health
        XCTAssertFalse(afterSleep.shouldRecover(sample(300), secondsSinceRecovery: 1800))
        health.reset()
        XCTAssertFalse(health.shouldRecover(sample(40), secondsSinceRecovery: 1800))
    }
}
