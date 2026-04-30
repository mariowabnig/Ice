# Changelog

All notable changes to Ice are tracked here retroactively from the available git history. Older entries summarize release themes rather than every small refactor.

## Unreleased

### Added
- Added a manual GitHub Actions workflow for building app artifacts.
- Added shared Codex and Claude agent guidance through `AGENTS.md`, `CLAUDE.md`, and `docs/AGENT_GUIDE.md`.
- Added discovery for visible auxiliary status-level windows that are not returned by macOS's private menu bar item list. This covers apps such as Portworth that draw their own menu bar presentation window.
- Added support for showing and rehiding hidden items when macOS is configured to automatically hide and show the menu bar.
- Added visual cover panels for auxiliary status-level windows while the system menu bar is retracted, so app-owned status windows do not linger on the desktop.

### Changed
- Auxiliary status item covers now cache and refresh their images only when needed, reducing flicker and avoiding unnecessary screen captures during pointer movement.
- Auxiliary status item covers now redraw shorter top-pinned auxiliary windows centered in the visible menu bar while still passing mouse events through to the owning app.
- Hidden-section reveal now reserves space from auxiliary status item frames captured while the hidden section is hidden, preventing native hidden items from sliding underneath app-owned overlays.
- Auxiliary status item reservation now preserves every auxiliary frame instead of collapsing windows with the same simplified identity.
- Ice Bar and Menu Bar Layout render auxiliary status item captures with transparent horizontal padding trimmed, so wide transparent app-owned windows do not appear oddly offset inside Ice's UI.
- Hidden-section hide/show updates now use the hiding state currently being applied when computing divider visibility and auxiliary reservation length.
- Control items now reapply their current status item state after the menu bar section graph is initialized, so startup length and icon updates run with a valid owning section.

### Fixed
- Fixed a recursive status item frame/length update loop that could crash Ice with a main-thread stack overflow.
- Fixed startup behavior where items assigned to the Hidden Section could still appear in the native menu bar because the hidden spacer length was not reapplied.
- Fixed hidden section hide transitions that could leave items visible after clicking Hide.
- Fixed auxiliary status item reveal anchoring when hidden native items appear next to app-owned overlay windows.
- Fixed auxiliary status item cover flicker after wake, unlock, or menu bar reconstruction.
- Fixed auxiliary status item layout detection so visible app-owned status windows are classified in the Visible Section instead of being missed or placed in a hidden section.
- Fixed menu bar item movement, move timeouts, and display names on macOS 26 Tahoe.
- Fixed macOS 26 compatibility where status item ownership and menu bar window behavior changed.

### Documentation
- Documented the control-item startup ordering and status item length requirements that keep hidden items offscreen.
- Documented auxiliary status item behavior, Portworth centering integration notes, auto-hidden menu bar limitations, and local install permission behavior in `FREQUENT_ISSUES.md`.
- Documented automatically hidden menu bar support and auxiliary status-level item behavior in `README.md`.

## 0.11.13-dev.2 - 2025-09-16

### Changed
- Updated issue templates.

## 0.11.13-dev.1 - 2025-06-20

### Added
- Added Homebrew cask installation instructions.
- Added a configurable behavior for right-clicking in the menu bar.

### Changed
- Updated project files for newer Xcode versions.
- Reworked menus, pickers, and related settings UI.
- Moved the updates interface into the About page.
- Made minor UI refinements.

## 0.11.12 - 2024-10-29

### Added
- Added optional screen-recording-permission behavior so Ice can work without Screen Recording in supported flows.
- Added a more complete screen recording permissions implementation.

### Changed
- Improved modifier flag handling.
- Updated group box and related interface details.

### Fixed
- Fixed missing items from hidden sections.

## 0.11.11 - 2024-10-19

### Changed
- Updated the menu bar search panel and full-screen behavior.
- Adjusted isolation and search panel window style handling.

### Fixed
- Reverted an accessibility-title change that caused regressions in the search panel.

## 0.11.10 - 2024-10-14

### Added
- Added dynamic menu bar appearance support.
- Added live preview for dynamic menu bar appearance changes.

### Changed
- Reworked appearance editor UI and menu bar shape edge insets.
- Reworked object association storage into `ObjectStorage`.
- Refactored menu bar item info and related internals.
- Improved movement timing by waiting for mouse motion to settle.

## 0.11.9 - 2024-10-08

### Added
- Added a small delay before moving menu bar items.

### Changed
- Reworked item caching and temporarily shown item handling.
- Updated menu bar item cache when running applications change.
- Opened the settings window when checking for updates.

## 0.11.8.1 - 2024-10-05

### Added
- Added a setting to show all sections while dragging menu bar items.

### Changed
- Reworked cursor location handling.

### Fixed
- Fixed smart rehide behavior on macOS Sequoia.
- Removed a legacy inset option that should not have shipped.

## 0.11.8 - 2024-10-04

### Changed
- Reworked item clicking and application menu overlap handling.
- Improved behavior for long application menus while temporarily showing items.
- Removed 1px padding around menu bar shapes.
- Updated advanced settings and sidebar sizing.

## 0.11.7 - 2024-10-02

### Added
- Added update notifications.

### Changed
- Updated Ice Bar corner rounding.

## 0.11.6 - 2024-09-30

### Changed
- Maintenance release with version/build updates from the 0.11 line.

## 0.11.0 - 2024-09-15

### Changed
- Major 0.11 release line with menu bar management, appearance, search, and settings improvements accumulated through the beta cycle.

## 0.10.x - 2024-06-13 to 2024-08-16

### Changed
- 0.10 release line covering the previous generation of menu bar item management, appearance, and reliability improvements before the 0.11 beta series.
