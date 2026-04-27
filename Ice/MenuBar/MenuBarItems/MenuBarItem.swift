//
//  MenuBarItem.swift
//  Ice
//

import Cocoa

// MARK: - MenuBarItem

/// A representation of an item in the menu bar.
struct MenuBarItem {
    /// The item's window.
    let window: WindowInfo

    /// The menu bar item info associated with this item.
    let info: MenuBarItemInfo

    /// The identifier of the item's window.
    var windowID: CGWindowID {
        window.windowID
    }

    /// The frame of the item's window.
    var frame: CGRect {
        window.frame
    }

    /// The title of the item's window.
    var title: String? {
        window.title
    }

    /// A Boolean value that indicates whether the item is on screen.
    var isOnScreen: Bool {
        window.isOnScreen
    }

    /// A Boolean value that indicates whether the item can be moved.
    var isMovable: Bool {
        let immovableItems = Set(MenuBarItemInfo.immovableItems)
        return !immovableItems.contains(info)
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        let nonHideableItems = Set(MenuBarItemInfo.nonHideableItems)
        return !nonHideableItems.contains(info)
    }

    /// The process identifier of the application that owns the item.
    var ownerPID: pid_t {
        window.ownerPID
    }

    /// The name of the application that owns the item.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    var ownerName: String? {
        window.ownerName
    }

    /// The application that owns the item.
    var owningApplication: NSRunningApplication? {
        window.owningApplication
    }

    /// A name associated with the item that is suited for display to
    /// the user.
    var displayName: String {
        var fallback: String { "Unknown" }
        guard let owningApplication else {
            return ownerName ?? title ?? fallback
        }
        var bestName: String {
            owningApplication.localizedName ??
            ownerName ??
            owningApplication.bundleIdentifier ??
            fallback
        }
        guard let title else {
            return bestName
        }
        // by default, use the application name, but handle a few special cases
        return switch MenuBarItemInfo.Namespace(owningApplication.bundleIdentifier) {
        case .controlCenter:
            switch title {
            case "AccessibilityShortcuts": "Accessibility Shortcuts"
            case "BentoBox": bestName // Control Center
            case "FocusModes": "Focus"
            case "KeyboardBrightness": "Keyboard Brightness"
            case "MusicRecognition": "Music Recognition"
            case "NowPlaying": "Now Playing"
            case "ScreenMirroring": "Screen Mirroring"
            case "StageManager": "Stage Manager"
            case "UserSwitcher": "Fast User Switching"
            case "WiFi": "Wi-Fi"
            default: Self.resolveDisplayName(from: title) ?? title
            }
        case .systemUIServer:
            switch title {
            case "TimeMachine.TMMenuExtraHost"/*Sonoma*/, "TimeMachineMenuExtra.TMMenuExtraHost"/*Sequoia*/: "Time Machine"
            default: title
            }
        case MenuBarItemInfo.Namespace("com.apple.Passwords.MenuBarExtra"): "Passwords"
        default:
            bestName
        }
    }

    /// On macOS 26+, all status items are owned by Control Center. Try to find the
    /// actual owning app by matching the window title against running apps' bundle IDs.
    private static func resolveDisplayName(from title: String) -> String? {
        let iceControlItemTitles = Set(ControlItem.Identifier.allCases.map(\.rawValue))
        if iceControlItemTitles.contains(title) {
            return "Ice"
        }
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if title.hasPrefix(bid) || title.hasPrefix(bid.replacingOccurrences(of: ".", with: "-")) {
                return app.localizedName
            }
        }
        return nil
    }

    /// A Boolean value that indicates whether the item is currently
    /// in the menu bar.
    var isCurrentlyInMenuBar: Bool {
        let list = Set(Bridging.getWindowList(option: .menuBarItems))
        return list.contains(windowID)
    }

    /// A Boolean value that indicates whether the item is a visible status-level
    /// window that is not returned by the private menu bar item list.
    var isAuxiliaryStatusItem: Bool {
        guard
            isOnScreen,
            !isCurrentlyInMenuBar,
            let title,
            !title.isEmpty,
            let bundleIdentifier = owningApplication?.bundleIdentifier
        else {
            return false
        }

        let dashedBundleIdentifier = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        return title.hasPrefix(bundleIdentifier) || title.hasPrefix(dashedBundleIdentifier)
    }

    /// A string to use for logging purposes.
    var logString: String {
        String(describing: info)
    }

    /// Returns an image suitable for displaying this item in Ice's UI.
    ///
    /// App-owned auxiliary status windows can include transparent padding around
    /// their visible content. Trimming that padding lets Ice center the visible
    /// item the same way it centers ordinary menu bar item captures.
    func displayImage(from image: CGImage) -> CGImage {
        guard isAuxiliaryStatusItem else {
            return image
        }
        return image.trimmingTransparentPixels() ?? image
    }

    /// Creates a menu bar item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.window = itemWindow
        self.info = MenuBarItemInfo(uncheckedItemWindow: itemWindow)
    }

    /// Creates a menu bar item.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `itemWindow` does not represent a menu bar item,
    /// the initializer will fail.
    ///
    /// - Parameter itemWindow: A window that contains information about the item.
    init?(itemWindow: WindowInfo) {
        guard itemWindow.isMenuBarItem else {
            return nil
        }
        self.init(uncheckedItemWindow: itemWindow)
    }

    /// Creates a menu bar item with the given window identifier.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `windowID` does not represent a menu bar item,
    /// the initializer will fail.
    ///
    /// - Parameter windowID: An identifier for a window that contains information
    ///   about the item.
    init?(windowID: CGWindowID) {
        guard let window = WindowInfo(windowID: windowID) else {
            return nil
        }
        self.init(itemWindow: window)
    }
}

// MARK: MenuBarItem Getters
extension MenuBarItem {
    private static func isAuxiliaryStatusItemWindow(
        _ window: WindowInfo,
        on display: CGDirectDisplayID?,
        activeSpaceOnly: Bool,
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> Bool {
        guard
            !excludedWindowIDs.contains(window.windowID),
            window.isMenuBarItem,
            window.isOnScreen,
            window.alpha > 0,
            let title = window.title,
            !title.isEmpty,
            let bundleIdentifier = window.owningApplication?.bundleIdentifier
        else {
            return false
        }

        let dashedBundleIdentifier = bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        guard title.hasPrefix(bundleIdentifier) || title.hasPrefix(dashedBundleIdentifier) else {
            return false
        }

        if activeSpaceOnly, !window.isOnActiveSpace {
            return false
        }

        let displayBounds = display.map { [CGDisplayBounds($0)] } ?? NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        guard displayBounds.contains(where: { bounds in
            abs(window.frame.minY - bounds.minY) <= 2 &&
            bounds.intersects(window.frame)
        }) else {
            return false
        }

        return window.frame.height <= NSStatusBar.system.thickness + 10
    }

    private static func getAuxiliaryStatusItems(
        on display: CGDirectDisplayID?,
        activeSpaceOnly: Bool,
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> [MenuBarItem] {
        WindowInfo.getOnScreenWindows(excludeDesktopWindows: true)
            .filter {
                isAuxiliaryStatusItemWindow(
                    $0,
                    on: display,
                    activeSpaceOnly: activeSpaceOnly,
                    excluding: excludedWindowIDs
                )
            }
            .compactMap(MenuBarItem.init(itemWindow:))
    }

    /// Returns an array of the current menu bar items in the menu bar on the given display.
    ///
    /// - Parameters:
    ///   - display: The display to retrieve the menu bar items on. Pass `nil` to return the
    ///     menu bar items across all displays.
    ///   - onScreenOnly: A Boolean value that indicates whether only the menu bar items that
    ///     are on screen should be returned.
    ///   - activeSpaceOnly: A Boolean value that indicates whether only the menu bar items
    ///     that are on the active space should be returned.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, onScreenOnly: Bool, activeSpaceOnly: Bool) -> [MenuBarItem] {
        var option: Bridging.WindowListOption = [.menuBarItems]

        var titlePredicate: (MenuBarItem) -> Bool = { _ in true }
        var boundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if onScreenOnly {
            option.insert(.onScreen)
        }
        if activeSpaceOnly {
            option.insert(.activeSpace)
            titlePredicate = { $0.title != "" }
        }
        if let display {
            let displayBounds = CGDisplayBounds(display)
            boundsPredicate = { windowID in
                guard let windowFrame = Bridging.getWindowFrame(for: windowID) else {
                    return false
                }
                return displayBounds.intersects(windowFrame)
            }
        }

        let bridgedWindowIDs = Bridging.getWindowList(option: option)
        let bridgedItems = bridgedWindowIDs.lazy
            .filter(boundsPredicate)
            .compactMap { windowID in
                MenuBarItem(windowID: windowID)
            }
        let auxiliaryItems = getAuxiliaryStatusItems(
            on: display,
            activeSpaceOnly: activeSpaceOnly,
            excluding: Set(bridgedWindowIDs)
        )

        return (Array(bridgedItems) + auxiliaryItems)
            .filter(titlePredicate)
            .sortedByOrderInMenuBar()
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.window == rhs.window
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(window)
    }
}

// MARK: MenuBarItemInfo Unchecked Item Window Initializer
private extension MenuBarItemInfo {
    /// Creates a simplified item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        let title = itemWindow.title ?? ""
        self.title = title

        // On macOS 26+, all status items are owned by Control Center.
        // Identify Ice's own control items by their unique titles.
        let iceControlItemTitles = Set(ControlItem.Identifier.allCases.map(\.rawValue))
        if iceControlItemTitles.contains(title) {
            self.namespace = .ice
        } else if let bundleIdentifier = itemWindow.owningApplication?.bundleIdentifier {
            self.namespace = Namespace(bundleIdentifier)
        } else {
            self.namespace = .null
        }
    }
}
