# Ice Architecture

## Purpose

Ice is a macOS menu bar utility. It manages visible, hidden, and always-hidden menu bar sections; provides an optional Ice Bar; supports search, hotkeys, appearance customization, and update checks; and coordinates permissions needed to inspect and manipulate menu bar items.

The app is system-facing. Changes should be conservative around private APIs, Accessibility access, Screen Recording access, global event monitoring, and menu bar auto-hide behavior.

## Runtime Overview

```text
IceApp
  -> AppDelegate
  -> AppState
  -> managers
     -> MenuBarManager / MenuBarItemManager / MenuBarAppearanceManager
     -> EventManager / HotkeyRegistry
     -> SettingsManager / PermissionsManager / UpdatesManager
     -> UserNotificationManager / MenuBarItemImageCache
  -> SwiftUI settings, permissions, Ice Bar, layout, and search UI
```

`AppState` is the center of the application. It is `@MainActor`, owns the long-lived managers, forwards manager change notifications to SwiftUI, and performs setup only after permissions and windows are in a usable state.

## Startup Flow

1. `IceApp` creates `AppState`, runs migrations, applies the split-view swizzle, and assigns the state to `AppDelegate`.
2. `AppDelegate.applicationWillFinishLaunching` connects the delegate back into `AppState` and enables background cursor control through `Bridging`.
3. `AppDelegate.applicationDidFinishLaunching` hides default app menus, dismisses initial windows, then checks permissions.
4. If required permissions exist, `AppState.performSetup()` initializes managers. If not, the app opens the permissions window.

Keep setup idempotent. Several managers assume `performSetup()` happens once after windows and permissions are ready.

## Main Areas

- `Ice/Main`: app entrypoint, delegate, shared app state, and navigation state.
- `Ice/MenuBar`: menu bar sections, control items, menu item discovery, image cache, appearance overlays, spacing, search, and Ice Bar integration.
- `Ice/Settings`: settings window, panes, and manager objects that bridge `UserDefaults` to UI.
- `Ice/UI`: reusable SwiftUI views, layout bar, Ice Bar UI, hotkey recorder, shapes, and view modifiers.
- `Ice/Hotkeys`: hotkey model, registry, modifiers, key codes, and actions.
- `Ice/Events`: global/local event monitoring and event taps.
- `Ice/Permissions`: Accessibility and Screen Recording permission checks and prompts.
- `Ice/Updates`: update-check coordination.
- `Ice/UserNotifications`: notification identifiers and notification delivery.
- `Ice/Utilities`: defaults, logging, migrations, screen capture, status-item defaults, window inspection, and shared helpers.
- `Ice/Bridging`: wrappers around system/private APIs.
- `Ice/Swizzling`: targeted AppKit behavior overrides.

## Menu Bar Model

`MenuBarManager` owns the high-level menu bar state:

- visible, hidden, and always-hidden sections
- the Ice Bar panel
- the search panel
- system auto-hide detection
- application-menu hiding behavior
- auxiliary status item cover panels for apps that draw status-level windows

`MenuBarItemManager` and related item types discover and track menu bar items. `MenuBarItemImageCache` stores images used by layout/search surfaces. `MenuBarAppearanceManager` applies tint, border, shadow, and shape overlays.

Menu bar behavior depends on window position, active space, fullscreen status, global user defaults, and CoreGraphics window information. Treat timing-sensitive changes as high risk.

## Settings and Persistence

Settings are persisted through `Ice/Utilities/Defaults.swift`, which centralizes `UserDefaults` keys. Settings managers own domain-specific state:

- general menu bar behavior
- hotkeys
- advanced behavior
- menu bar appearance

Migrations live in `MigrationManager`. When changing persisted values, add a migration if existing users need their stored settings transformed.

## Permissions

`PermissionsManager` tracks all permission objects and exposes one permission state:

- `missingPermissions`
- `hasRequiredPermissions`
- `hasAllPermissions`

The app gates setup on required permissions. Permission-related changes need manual QA with permissions both granted and revoked.

## System Boundaries

The following areas require extra care:

- `Bridging`: private or lower-level system APIs.
- `WindowInfo` and CoreGraphics window inspection.
- `UniversalEventMonitor` and event taps.
- Screen capture and menu bar item image caching.
- Swizzled AppKit behavior.
- Accessibility-driven menu bar discovery/manipulation.

Keep these boundaries narrow and documented. Prefer changing callers over expanding private API usage.

## Build and Verification

Use a full Xcode installation, not only Command Line Tools.

Inspect available schemes:

```bash
xcodebuild -list -project Ice.xcodeproj
```

Build after confirming the scheme:

```bash
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug build
```

Manual QA should cover:

- first launch with missing permissions
- launch with permissions already granted
- hiding and showing menu bar sections
- always-hidden section behavior
- auto-hidden menu bar behavior
- fullscreen spaces
- external displays when available
- settings persistence after relaunch
- hotkey registration and release
- update/settings/permissions windows opening from the menu bar

## Development Notes

- Keep `AppState` and manager mutations on the main actor unless a file already establishes a safe background boundary.
- Do not bypass `Defaults.Key` for persisted settings.
- Do not add broad global event monitors for narrow UI behavior.
- Treat auto-hidden menu bars and auxiliary status-level windows as regression-prone.
- When `xcodebuild` fails because the active developer directory points at Command Line Tools, document the blocker instead of treating it as a code failure.
