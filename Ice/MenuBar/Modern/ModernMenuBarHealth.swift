//
//  ModernMenuBarHealth.swift
//  Ice
//

import Foundation

/// Recovery requires both a transport timeout and sustained resource pressure.
/// Missing items, a retracted bar, or a slow single read are not a hang.
struct ModernMenuBarHealth {
    struct ProcessIdentity: Equatable {
        var pid: Int32
        var startSeconds: UInt64
        var startMicroseconds: UInt64
    }

    struct Sample: Sendable {
        var pid: Int32
        var uptime: TimeInterval
        var cpuNanoseconds: UInt64
        var residentBytes: UInt64
        var timedOut: Bool
    }

    static let cooldown: TimeInterval = 30 * 60
    private var previous: Sample?
    private var unhealthySince: TimeInterval?

    /// Wall-clock persistence survives relaunch; uptime also protects a running
    /// watchdog from a clock jump shortening its cooldown.
    static func secondsSinceRecovery(wallElapsed: TimeInterval, uptimeElapsed: TimeInterval?) -> TimeInterval {
        min(wallElapsed, uptimeElapsed ?? .infinity)
    }

    mutating func reset() {
        previous = nil
        unhealthySince = nil
    }

    mutating func shouldRecover(_ sample: Sample, secondsSinceRecovery: TimeInterval) -> Bool {
        defer { previous = sample }
        guard sample.timedOut, secondsSinceRecovery >= Self.cooldown,
              let previous, previous.pid == sample.pid, previous.timedOut,
              sample.uptime > previous.uptime, sample.uptime - previous.uptime <= 20,
              sample.cpuNanoseconds >= previous.cpuNanoseconds else {
            unhealthySince = nil
            return false
        }
        let elapsed = sample.uptime - previous.uptime
        let cpu = Double(sample.cpuNanoseconds - previous.cpuNanoseconds) / (elapsed * 1_000_000_000)
        guard cpu >= 0.8 || sample.residentBytes >= 1_073_741_824 else {
            unhealthySince = nil
            return false
        }
        let since = unhealthySince ?? sample.uptime
        unhealthySince = since
        return sample.uptime - since >= 30
    }
}
