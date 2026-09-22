//
//  MenuBarSection.swift
//  Ice
//

import SwiftUI

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            LocalizedStringKey(displayString)
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// A token used to invalidate pending rehide work when the section is
    /// shown or hidden again.
    private var rehideGeneration = 0

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: EventMonitor?

    /// A Boolean value that indicates whether the Ice Bar should be used.
    private var useIceBar: Bool {
        appState?.settings.general.useIceBar ?? false
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// The best screen to show the Ice Bar on.
    private weak var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.activeSpace.isFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if #available(macOS 27.0, *), let appState {
            switch name {
            case .visible:
                return false
            case .hidden:
                return !appState.modernMenuBarManager.revealed.contains(.hidden)
            case .alwaysHidden:
                return !appState.modernMenuBarManager.revealed.contains(.alwaysHidden)
            }
        }
        if useIceBar {
            if controlItem.state == .showSection {
                return false
            }
            switch name {
            case .visible, .hidden:
                return menuBarManager?.iceBarPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.iceBarPanel.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if menuBarManager?.iceBarPanel.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideSection
        case .alwaysHidden:
            if menuBarManager?.iceBarPanel.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideSection
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        if #available(macOS 27.0, *) {
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// The hotkey to toggle the section.
    var hotkey: Hotkey? {
        guard let hotkeys = appState?.settings.hotkeys else {
            return nil
        }
        return switch name {
        case .visible: nil
        case .hidden: hotkeys.hotkey(withAction: .toggleHiddenSection)
        case .alwaysHidden: hotkeys.hotkey(withAction: .toggleAlwaysHiddenSection)
        }
    }

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .visible)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
    }

    /// Shows the section.
    func show() {
        guard let menuBarManager, isHidden else {
            return
        }

        guard isEnabled else {
            // The section is disabled.
            return
        }

        if #available(macOS 27.0, *), let appState {
            appState.modernMenuBarManager.reveal(name == .alwaysHidden ? .alwaysHidden : .hidden)
            startRehideChecks()
            return
        }

        if useIceBar {
            // Make sure hidden and always-hidden control items are collapsed.
            // Still update the visible control item (Ice icon) state to show
            // its alternate icon.
            for section in menuBarManager.sections {
                switch section.name {
                case .visible:
                    section.controlItem.state = .showSection
                case .hidden, .alwaysHidden:
                    section.controlItem.state = .hideSection
                }
            }

            if let screen = screenForIceBar {
                Task {
                    switch name {
                    case .visible, .hidden:
                        await menuBarManager.iceBarPanel.show(section: .hidden, on: screen)
                    case .alwaysHidden:
                        await menuBarManager.iceBarPanel.show(section: .alwaysHidden, on: screen)
                    }
                    startRehideChecks()
                }
            }

            return // We're done.
        }

        // If we made it here, we're not using the Ice Bar.
        // Make sure it's closed.
        menuBarManager.iceBarPanel.close()

        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections where section.name != .alwaysHidden {
                section.controlItem.state = .showSection
            }
        case .alwaysHidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }

        startRehideChecks()
    }

    /// Hides the section.
    func hide() {
        guard let menuBarManager, !isHidden else {
            return
        }

        menuBarManager.iceBarPanel.close() // Make sure Ice Bar is always closed.
        menuBarManager.showOnHoverAllowed = true

        if #available(macOS 27.0, *), let appState {
            appState.modernMenuBarManager.conceal(name == .alwaysHidden ? .alwaysHidden : .hidden)
            stopRehideChecks()
            return
        }

        switch name {
        case _ where useIceBar, .visible, .hidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .hideSection
            }
        case .alwaysHidden:
            controlItem.state = .hideSection
        }

        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    func toggle() {
        if isHidden { show() } else { hide() }
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideGeneration += 1
        let generation = rehideGeneration
        rehideTimer?.invalidate()
        rehideTimer = nil
        rehideMonitor?.stop()
        rehideMonitor = nil

        guard
            let appState,
            appState.settings.general.autoRehide,
            case .timed = appState.settings.general.rehideStrategy
        else {
            return
        }

        func scheduleRehideIfNeeded() {
            guard
                rehideGeneration == generation,
                !isHidden,
                rehideTimer == nil,
                isPointerAwayFromMenuBar()
            else {
                return
            }
            rehideTimer = .scheduledTimer(
                withTimeInterval: appState.settings.general.rehideInterval,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    guard
                        let self,
                        self.rehideGeneration == generation
                    else {
                        return
                    }
                    self.rehideTimer = nil
                    guard
                        let appState = self.appState,
                        appState.settings.general.autoRehide,
                        case .timed = appState.settings.general.rehideStrategy,
                        !self.isHidden
                    else {
                        self.stopRehideChecks()
                        return
                    }
                    if self.isPointerAwayFromMenuBar() {
                        self.hide()
                    } else {
                        self.startRehideChecks()
                    }
                }
            }
        }

        // A hotkey can reveal the section while the pointer is already away
        // from the menu bar. Start the timer immediately instead of waiting
        // for the next mouse-moved event.
        scheduleRehideIfNeeded()

        rehideMonitor = EventMonitor.universal(for: .mouseMoved) { [weak self] event in
            guard let self else {
                return event
            }
            if self.isPointerAwayFromMenuBar() {
                scheduleRehideIfNeeded()
            } else {
                self.rehideTimer?.invalidate()
                self.rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// Returns whether the pointer is outside the menu bar reveal area.
    private func isPointerAwayFromMenuBar() -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main else {
            return false
        }
        return !screen.containsAppKitMenuBarPoint(NSEvent.mouseLocation)
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideGeneration += 1
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}
