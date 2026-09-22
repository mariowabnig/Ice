//
//  ModernMenuBarLayout.swift
//  Ice
//

import Foundation

/// macOS 27 has stable app identities but no individual CGWindowIDs for status items.
public struct ModernItemID: Hashable, Codable, Sendable {
    let bundleID: String
    let title: String

    static func status(bundle: String, title: String) -> Self {
        Self(bundleID: bundle, title: title)
    }

    var rawValue: String { "\(bundleID)::\(title)" }
}

struct ModernMenuBarLayout: Codable, Equatable {
    enum Section: String, CaseIterable, Codable {
        case visible, hidden, alwaysHidden

        var title: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }
    }

    // App assignments retain bundle keys. System controls use reserved keys,
    // so Wi-Fi does not inherit Battery's section from their shared host.
    var assignments: [String: Section] = [:]

    func section(for bundleID: String) -> Section {
        assignments[bundleID] ?? .visible
    }

    func section(for item: ModernItemID) -> Section {
        section(for: item.assignmentKey)
    }

    func concealedBundles(revealing sections: Set<Section>) -> Set<String> {
        Set(assignments.compactMap { bundle, section in
            !bundle.hasPrefix("system:") && section != .visible && !sections.contains(section) ? bundle : nil
        })
    }

    func visibilityPlan(revealing sections: Set<Section>, runningBundles: Set<String>, ownBundle: String) -> ModernVisibilityPlan {
        let bundles = concealedBundles(revealing: sections).intersection(runningBundles).filter {
            $0 != ownBundle && ModernItemID.supportsBundleHiding($0)
        }
        let systemItems = ModernSystemItem.allCases.filter {
            $0 != .controlCenter && isHidden(key: $0.assignmentKey, revealing: sections)
        }
        return ModernVisibilityPlan(
            bundles: Set(bundles),
            systemItems: Set(systemItems),
            hideOtherSystemExtras: isHidden(key: ModernVisibilityPlan.otherSystemExtrasKey, revealing: sections)
        )
    }

    private func isHidden(key: String, revealing sections: Set<Section>) -> Bool {
        let section = section(for: key)
        return section != .visible && !sections.contains(section)
    }
}
