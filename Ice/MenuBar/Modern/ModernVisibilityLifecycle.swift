import CoreGraphics
import Foundation

enum ModernVisibilityVerification: Equatable {
    case confirmedHidden
    case stillVisible([ModernItemID])
    case unreadable
}

enum ModernVisibilityVerifier {
    static func verify(_ plan: ModernVisibilityPlan, in snapshot: ModernMenuBarSnapshot) -> ModernVisibilityVerification {
        guard snapshot.canVerifyVisibility else { return .unreadable }
        let stillVisible = snapshot.items.map(\.id).filter { plan.conceals($0) }
        return stillVisible.isEmpty ? .confirmedHidden : .stillVisible(stillVisible)
    }
}

struct ModernVisibilityRetryPolicy: Equatable {
    var maxAutomaticRetries = 3
    var initialDelay: TimeInterval = 0.75

    func delay(afterFailureCount failureCount: Int) -> TimeInterval? {
        guard failureCount > 0, failureCount <= maxAutomaticRetries else { return nil }
        return initialDelay * pow(2, Double(failureCount - 1))
    }
}

struct ModernVisibilityFailure: Equatable {
    var plan: ModernVisibilityPlan
    var failureCount: Int
    var message: String

    var canRetryAutomatically: Bool {
        ModernVisibilityRetryPolicy().delay(afterFailureCount: failureCount) != nil
    }

    static func record(
        previous: ModernVisibilityFailure?,
        plan: ModernVisibilityPlan,
        message: String
    ) -> ModernVisibilityFailure {
        let previousCount = previous?.plan == plan ? previous?.failureCount ?? 0 : 0
        return ModernVisibilityFailure(plan: plan, failureCount: previousCount + 1, message: message)
    }
}

struct ModernVisibilityLifecycle: Equatable {
    enum State: Equatable {
        case idle
        case pending(generation: Int, unreadableRetriesRemaining: Int)
        case active
        case activeUnverified
        case failed(failureCount: Int, message: String)
    }

    enum VerificationOutcome: Equatable {
        case confirmed
        case keepWaiting
        case activeButUnverified
        case failed(message: String)
        case ignoredStale
    }

    private(set) var generation = 0
    private(set) var state: State = .idle
    var unreadableRetryLimit = 3

    init(unreadableRetryLimit: Int = 3) {
        self.unreadableRetryLimit = unreadableRetryLimit
    }

    var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    var isActiveUnverified: Bool {
        state == .activeUnverified
    }

    mutating func beginActivation() -> Int {
        generation += 1
        state = .pending(generation: generation, unreadableRetriesRemaining: unreadableRetryLimit)
        return generation
    }

    mutating func markActiveWithoutVerification() {
        state = .activeUnverified
    }

    mutating func markIdle() {
        generation += 1
        state = .idle
    }

    mutating func markFailed(message: String) {
        generation += 1
        state = .failed(failureCount: 1, message: message)
    }

    mutating func handleCallback(generation callbackGeneration: Int) -> Bool {
        guard case let .pending(activeGeneration, _) = state else { return false }
        return callbackGeneration == activeGeneration && callbackGeneration == generation
    }

    mutating func verify(
        generation verificationGeneration: Int,
        result: ModernVisibilityVerification,
        allowFailure: Bool
    ) -> VerificationOutcome {
        guard case let .pending(activeGeneration, retriesRemaining) = state,
              activeGeneration == verificationGeneration,
              activeGeneration == generation
        else {
            return .ignoredStale
        }

        switch result {
        case .confirmedHidden:
            state = .active
            return .confirmed
        case .unreadable:
            guard retriesRemaining > 0 else {
                state = .activeUnverified
                return .activeButUnverified
            }
            state = .pending(generation: activeGeneration, unreadableRetriesRemaining: retriesRemaining - 1)
            return .keepWaiting
        case .stillVisible:
            guard allowFailure else { return .keepWaiting }
            generation += 1
            state = .failed(failureCount: 1, message: "macOS did not apply menu bar hiding.")
            return .failed(message: "macOS did not apply menu bar hiding.")
        }
    }

    mutating func observeActive(
        _ result: ModernVisibilityVerification
    ) -> VerificationOutcome {
        guard state == .active || state == .activeUnverified else { return .ignoredStale }
        switch result {
        case .confirmedHidden:
            state = .active
            return .confirmed
        case .unreadable:
            return .keepWaiting
        case .stillVisible:
            generation += 1
            state = .failed(failureCount: 1, message: "macOS did not apply menu bar hiding.")
            return .failed(message: "macOS did not apply menu bar hiding.")
        }
    }
}

enum ModernItemDiscovery {
    static func mergedItems(
        previous: [ModernMenuBarItem],
        observed: [ModernMenuBarItem],
        appliedVisibility: ModernVisibilityPlan,
        retainAllUnobserved: Bool,
        ownBundle: String,
        isAlive: (pid_t) -> Bool
    ) -> [ModernMenuBarItem] {
        let observedIDs = Set(observed.map(\.id))
        let retained = previous.filter { item in
            guard !observedIDs.contains(item.id), isAlive(item.pid) else { return false }
            return retainAllUnobserved || appliedVisibility.conceals(item.id)
        }
        return (observed + retained)
            .filter { $0.id.bundleID != ownBundle }
            .sorted { $0.frame.minX < $1.frame.minX }
    }
}

struct ModernMoveVerificationItem: Equatable {
    var id: ModernItemID
    var midX: CGFloat
}

enum ModernMoveVerification {
    static func acceptedMoveBefore(
        _ id: ModernItemID,
        targetID: ModernItemID,
        before: [ModernMoveVerificationItem],
        after: [ModernMoveVerificationItem]
    ) -> Bool {
        guard let beforeSource = before.firstIndex(where: { $0.id == id }),
              let beforeTarget = before.firstIndex(where: { $0.id == targetID }),
              let afterSource = after.firstIndex(where: { $0.id == id }),
              let afterTarget = after.firstIndex(where: { $0.id == targetID }),
              afterSource < afterTarget
        else { return false }

        if beforeSource > beforeTarget {
            return true
        }

        if beforeSource + 1 == beforeTarget {
            return true
        }

        return afterSource + 1 == afterTarget
    }
}
