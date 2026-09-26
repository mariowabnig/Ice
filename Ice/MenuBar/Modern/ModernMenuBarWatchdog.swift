//
//  ModernMenuBarWatchdog.swift
//  Ice
//

import AppKit
import ApplicationServices
import Combine
import Darwin
import OSLog

/// A narrow watchdog for the macOS 27 MenuBarAgent hang. Never restarts Ice,
/// Control Center, or a process merely because visibility cannot be verified.
@MainActor
final class ModernMenuBarWatchdog {
    private let logger = Logger(subsystem: "com.jordanbaird.Ice", category: "MenuBarRecovery")
    private let probe = ModernMenuBarHealthProbe()
    private var health = ModernMenuBarHealth()
    private var timer: AnyCancellable?
    private var observers = Set<AnyCancellable>()
    private var isChecking = false
    private var generation = 0
    private var suspended = false
    private var resumeAfter = Date.distantPast
    private var lastRecoveryUptime: TimeInterval?
    private let canRecover: () -> Bool

    init(canRecover: @escaping () -> Bool) {
        self.canRecover = canRecover
    }

    func start() {
        guard timer == nil else { return }
        suspended = false
        resumeAfter = Date().addingTimeInterval(30)
        logger.notice("MenuBarAgent watchdog enabled; sustained timeout/resource checks, 30-minute cooldown")
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            center.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.suspend()
            }.store(in: &observers)
        }
        for name in [
            NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            center.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.resume()
            }.store(in: &observers)
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.suspend() }
            .store(in: &observers)
        distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.resume() }
            .store(in: &observers)
        timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in Task { await self?.check() } }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        observers.removeAll()
        generation += 1
        health.reset()
    }

    private func suspend() {
        suspended = true
        generation += 1
        health.reset()
    }

    private func resume() {
        suspended = false
        generation += 1
        resumeAfter = Date().addingTimeInterval(30)
        health.reset()
    }

    private var sessionIsReady: Bool {
        guard !suspended, Date() >= resumeAfter, AXIsProcessTrusted(), canRecover(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }

    private func check() async {
        guard !isChecking else { return }
        guard sessionIsReady, let agent = Self.currentAgent() else {
            health.reset()
            return
        }
        isChecking = true
        defer { isChecking = false }
        let currentGeneration = generation
        let pid = agent.pid
        guard let sample = await probe.sample(pid: pid), generation == currentGeneration,
              timer != nil, sessionIsReady, Self.currentAgent() == agent else {
            health.reset()
            return
        }
        let lastRecovery = Defaults.object(forKey: .modernMenuBarLastRecovery) as? Date ?? .distantPast
        let elapsed = ModernMenuBarHealth.secondsSinceRecovery(
            wallElapsed: Date().timeIntervalSince(lastRecovery),
            uptimeElapsed: lastRecoveryUptime.map { sample.uptime - $0 }
        )
        logger.debug("MenuBarAgent probe pid=\(pid, privacy: .public) timedOut=\(sample.timedOut, privacy: .public) residentBytes=\(sample.residentBytes, privacy: .public)")
        guard health.shouldRecover(sample, secondsSinceRecovery: elapsed) else { return }
        // Persist BEFORE attempting recovery, so a failure or Ice relaunch cannot loop.
        Defaults.set(Date(), forKey: .modernMenuBarLastRecovery)
        lastRecoveryUptime = sample.uptime
        health.reset()
        logger.warning("Restarting unresponsive MenuBarAgent pid=\(pid, privacy: .public) residentBytes=\(sample.residentBytes, privacy: .public)")
        let result = kill(pid, SIGTERM)
        let signalError = result == 0 ? 0 : errno
        logger.notice("MenuBarAgent recovery signal result=\(result, privacy: .public) errno=\(signalError, privacy: .public)")
        // launchd replaces the service; the existing manager rediscovers and verifies it.
    }

    static func currentAgent() -> ModernMenuBarHealth.ProcessIdentity? {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: ModernItemEnumerator.agentBundleID) {
            guard app.executableURL?.path == "/System/Library/CoreServices/MenuBarAgent.app/Contents/MacOS/MenuBarAgent",
                  !app.isTerminated else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout.size(ofValue: info))
            guard proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  info.pbi_uid == getuid(), info.pbi_start_tvsec > 0 else { continue }
            // NSRunningApplication.launchDate is nil for this system agent.
            // Kernel start time still distinguishes replacement processes/PID reuse.
            return .init(pid: app.processIdentifier, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
        }
        return nil
    }
}

private actor ModernMenuBarHealthProbe {
    func sample(pid: pid_t) -> ModernMenuBarHealth.Sample? {
        let element = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(element, 0.25) == .success else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return ModernMenuBarHealth.Sample(
            pid: pid,
            uptime: ProcessInfo.processInfo.systemUptime,
            cpuNanoseconds: info.pti_total_user + info.pti_total_system,
            residentBytes: info.pti_resident_size,
            timedOut: error == .cannotComplete
        )
    }
}
