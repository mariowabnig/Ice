//
//  MenuBarItem.swift
//  Ice
//

import Cocoa

/// A structural representation of a menu bar item.
struct MenuBarItem: CustomStringConvertible {
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// A Boolean value that indicates whether this item can be moved.
    var isMovable: Bool {
        tag.isMovable && !isAuxiliaryStatusItem
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden
    }

    /// A Boolean value that indicates whether this item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether the item is a visible status-level
    /// window that is not returned by the private menu bar item list. These are
    /// treated as read-only overlays so app-owned popovers such as Portworth's
    /// portfolio menu stay clickable but are not moved by Ice.
    var isAuxiliaryStatusItem: Bool {
        guard
            isOnScreen,
            !isCurrentlyInMenuBar,
            bounds.height <= Self.auxiliaryStatusItemMaxHeight(for: WindowInfo(windowID: windowID))
        else {
            return false
        }
        return Self.hasAuxiliaryStatusItemIdentity(window: WindowInfo(windowID: windowID))
    }

    /// A Boolean value that indicates whether the auxiliary item follows Ice's
    /// read-only overlay contract: the window title starts with the owning app's
    /// bundle identifier, or its dashed form.
    var isBundleIdentifiedAuxiliaryStatusItem: Bool {
        Self.hasBundleIdentifiedAuxiliaryStatusItemIdentity(window: WindowInfo(windowID: windowID))
    }

    /// A Boolean value that indicates whether the item is currently represented
    /// in the private menu bar item list.
    private var isCurrentlyInMenuBar: Bool {
        let list = Set(Bridging.getMenuBarWindowList(option: .itemsOnly))
        return list.contains(windowID)
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    // TODO: Generate this once, during initialization.
    /// A name associated with the item, suited for display.
    var displayName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase<S: StringProtocol>(_ s: S) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return Constants.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        guard let sourceApplication else {
            return fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        guard !isBentoBox else {
            if tag == .controlCenter {
                return bestName
            }
            return title
        }

        // Most items use their computed "best name", but we handle
        // a few special cases for system items.
        let displayName = switch tag.namespace {
        case .passwords, .weather, .textInputMenuAgent:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            // "TextInputMenuAgent" -> "Text Input"
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .controlCenter:
            if let match = title.prefixMatch(of: /Hearing/) {
                // Changed from "Hearing" to "Hearing_GlowE" in macOS 15.4
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        case .systemUIServer:
            if let match = title.firstMatch(of: /TimeMachine/) {
                // Sonoma:  "TimeMachine.TMMenuExtraHost"
                // Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
                // Tahoe:   "com.apple.menuextra.TimeMachine"
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        default:
            bestName
        }

        // Provide some extra context if the name is just a UUID.
        if UUID(uuidString: displayName) != nil, let sourceName {
            return "\(sourceName) (\(displayName))"
        }

        return displayName
    }

    /// A textual representation of the item.
    var description: String {
        "\(displayName) (\(tag))"
    }

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.isOnScreen = itemWindow.isOnScreen
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
    static func getMenuBarItemWindows(on display: CGDirectDisplayID? = nil, option: ListOption) -> [WindowInfo] {
        var bridgingOption: Bridging.MenuBarWindowListOption = .itemsOnly
        var displayBoundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if let display {
            bridgingOption.insert(.onScreen)
            let displayBounds = CGDisplayBounds(display)
            displayBoundsPredicate = { windowID in
                Bridging.windowIntersectsDisplayBounds(windowID, displayBounds)
            }
        } else if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
        }

        return Bridging.getMenuBarWindowList(option: bridgingOption)
            .reversed().compactMap { windowID in
                guard
                    displayBoundsPredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return window
            }
    }

    /// Creates and returns a list of menu bar items using experimental
    /// source pid retrieval for macOS 26.
    @available(macOS 26.0, *)
    private static func getMenuBarItemsExperimental(on display: CGDirectDisplayID?, option: ListOption) async -> [MenuBarItem] {
        let windows = getMenuBarItemWindows(on: display, option: option)
        var items = [MenuBarItem]()
        for window in windows {
            let sourcePID = await MenuBarItemService.Connection.shared.sourcePID(for: window)
            let item = MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePID)
            items.append(item)
        }
        let auxiliaryItems = getAuxiliaryStatusItems(
            on: display,
            activeSpaceOnly: option.contains(.activeSpace),
            excluding: Set(windows.map(\.windowID))
        )
        return (items + auxiliaryItems).sortedMenuBarItemsByPosition()
    }

    /// Creates and returns a list of menu bar items, defaulting to the
    /// legacy source pid behavior, prior to macOS 26.
    private static func getMenuBarItemsLegacyMethod(on display: CGDirectDisplayID?, option: ListOption) -> [MenuBarItem] {
        let windows = getMenuBarItemWindows(on: display, option: option)
        let bridgedItems = windows.map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
        let auxiliaryItems = getAuxiliaryStatusItems(
            on: display,
            activeSpaceOnly: option.contains(.activeSpace),
            excluding: Set(windows.map(\.windowID))
        )
        return (bridgedItems + auxiliaryItems).sortedMenuBarItemsByPosition()
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, option: ListOption) async -> [MenuBarItem] {
        if #available(macOS 26.0, *) {
            await getMenuBarItemsExperimental(on: display, option: option)
        } else {
            getMenuBarItemsLegacyMethod(on: display, option: option)
        }
    }

    private static func auxiliaryStatusItemMaxHeight(for window: WindowInfo?) -> CGFloat {
        let screen = window.flatMap { window in
            NSScreen.screens.first { CGDisplayBounds($0.displayID).intersects(window.bounds) }
        }
        let menuBarHeight = screen.flatMap { screen in
            WindowInfo.menuBarWindow(for: screen.displayID)?.bounds.height ?? screen.getMenuBarHeight()
        } ?? NSStatusBar.system.thickness
        return max(menuBarHeight, NSStatusBar.system.thickness) + 10
    }

    private static func hasAuxiliaryStatusItemIdentity(window: WindowInfo?) -> Bool {
        guard let window else {
            return false
        }

        if hasBundleIdentifiedAuxiliaryStatusItemIdentity(window: window) {
            return true
        }

        guard let ownerName = window.ownerName, !ownerName.isEmpty else {
            return false
        }

        let excludedOwnerNames = Set([
            "Control Center",
            "Kontrollzentrum",
            "Dock",
            "SystemUIServer",
            "Window Server",
        ])
        return !excludedOwnerNames.contains(ownerName)
    }

    private static func hasBundleIdentifiedAuxiliaryStatusItemIdentity(window: WindowInfo?) -> Bool {
        guard
            let window,
            let title = window.title,
            !title.isEmpty,
            let bundleIdentifier = window.owningApplication?.bundleIdentifier
        else {
            return false
        }

        let dashedBundleIdentifier = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        return title.hasPrefix(bundleIdentifier) || title.hasPrefix(dashedBundleIdentifier)
    }

    private static func isAuxiliaryStatusItemWindow(
        _ window: WindowInfo,
        on display: CGDirectDisplayID?,
        activeSpaceOnly: Bool,
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> Bool {
        guard
            !excludedWindowIDs.contains(window.windowID),
            window.layer == kCGStatusWindowLevel,
            window.isOnScreen,
            hasAuxiliaryStatusItemIdentity(window: window)
        else {
            return false
        }

        if activeSpaceOnly, !Bridging.getSpaceList(for: window.windowID).contains(Bridging.getActiveSpaceID()) {
            return false
        }

        let displayBounds = display.map { [CGDisplayBounds($0)] } ?? NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        guard displayBounds.contains(where: { bounds in
            abs(window.bounds.minY - bounds.minY) <= 2 &&
            bounds.intersects(window.bounds)
        }) else {
            return false
        }

        return window.bounds.height <= auxiliaryStatusItemMaxHeight(for: window)
    }

    private static func getAuxiliaryStatusItems(
        on display: CGDirectDisplayID?,
        activeSpaceOnly: Bool,
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> [MenuBarItem] {
        let option: Bridging.WindowListOption = activeSpaceOnly ? [.onScreen, .activeSpace] : .onScreen
        return WindowInfo.createWindows(option: option)
            .filter {
                isAuxiliaryStatusItemWindow(
                    $0,
                    on: display,
                    activeSpaceOnly: activeSpaceOnly,
                    excluding: excludedWindowIDs
                )
            }
            .map { MenuBarItem(uncheckedItemWindow: $0) }
    }
}

private extension [MenuBarItem] {
    func sortedMenuBarItemsByPosition() -> [MenuBarItem] {
        sorted { lhs, rhs in
            if abs(lhs.bounds.minY - rhs.bounds.minY) > 2 {
                return lhs.bounds.minY < rhs.bounds.minY
            }
            return lhs.bounds.minX > rhs.bounds.minX
        }
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.sourcePID == rhs.sourcePID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.title == rhs.title &&
        lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(title)
        hasher.combine(isOnScreen)
    }
}

// MARK: - MenuBarItemTag Helper

private extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.title = itemWindow.title ?? ""
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

private extension MenuBarItemTag.Namespace {
    private static var uuidCache = [CGWindowID: UUID]()

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self = .optional(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(app.bundleIdentifier ?? app.localizedName)
        } else if let uuid = Self.uuidCache[itemWindow.windowID] {
            self = .uuid(uuid)
        } else {
            let uuid = UUID()
            Self.uuidCache[itemWindow.windowID] = uuid
            self = .uuid(uuid)
        }
    }
}
