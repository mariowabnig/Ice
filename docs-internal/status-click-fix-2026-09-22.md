# Usage-tracker click moves menu-bar items

## Diagnosis and scope

On macOS 27, Ice's empty-space detection used the layout editor's cached item
frames. Multiple status groups from one application can share an editor identity
and collapse into one tile. Clicking a different icon could therefore toggle
Hidden items after the short click delay. Cached geometry also lagged reflow.
The installed Claude Usage tracker exposes several independent status controls,
matching this failure mode. Its own variable-width indicators can also resize
when usage values refresh; that rendering is outside this Ice repair.

The exact physical-click symptom has not been conclusively reproduced through
computer automation. MenuBarAgent inspection works, but the current native UI
driver rejects coordinate clicks on the composited menu bar. A semantic click
showing no change does not establish a physical-click pass.

## Implementation

- Keep raw occupancy separate from editor identity resolution and deduplication.
- Require complete, current MenuBarAgent window/group geometry for empty-space
  click, context-menu and hover actions. Include unknown groups, Ice and overflow.
- Use a separate actor, a 0.4-second total deadline and at most 50 milliseconds
  per Accessibility message. Reject incomplete, invalid and late responses.
- Cancel pending actions after mouse movement or newer input. Recheck visibility
  generation across the asynchronous read and section state before toggling.
- Short-circuit ordinary desktop movement before querying application menus.
- Retain the existing macOS 14–26 handlers and persisted assignments.

The patch was first validated on f860519, then ported additively after fetching
origin/main at 76578af. That fast-forward brought in the upstream beta and the
fork's newer visibility lifecycle; its discovery, retry and assertion replacement
logic was preserved. The final version is 0.11.13-dev.2-macos27.2, build2026092202.

## Adversarial review and simplification

Resolved findings:

1. A busy guard dropped new clicks while canceled hover reads unwound. Separate
   actor serialization plus each request's own deadline replaces that guard.
2. An early application-menu AX query ran on ordinary desktop pointer movement.
   Cheap menu/notch checks now run first.
3. The newer visibility lifecycle can change geometry without mouse input.
   Its generation must remain unchanged across an occupancy read.
4. The beta port must retain the Option-click fallback when Always-Hidden is
   disabled. Target selection matches the existing handler.

The simplification pass retained one scheduling helper for click/context/hover
and kept temporal rechecks explicit because state can change across awaits.
No broad refactoring was needed. No remaining code-level ship blocker was found.
Residual limits are live physical-click and additional-display verification,
private macOS API compatibility, and independent resizing by the tracker itself.

## Validation

- Universal Release build and recursive code-signature verification: passed.
- Full native Debug XCTest: 44 passed, including nine occupancy/input cases.
- Standalone production visibility/layout/geometry harness: 15 passed.
- Repository-wide SwiftLint0.65.1 strict check: passed.
- Shell syntax and whitespace checks: passed.

An initial build after moving the development directory rejected old compiler
caches with their former absolute path. Rebuilding those generated caches fixed
it; the subsequent full test run passed. Xcode's existing CoreDevice/Simulator
warnings did not prevent the macOS suite.

## Installation and duplicate cleanup

Ice was removed from Accessibility and re-added using the exact
/Applications/Ice.app path. Its toggle was verified on. Nine obsolete app bundles
were archived, extraction-verified (including hashes, symlinks and execute bits),
and removed. Their archive manifest is local and ignored by Git. Stale Ice and
bundled updater registrations were removed. Spotlight now exposes only the
normal /Applications installation.

Current development products live under build.noindex/. The installer now uses
that directory and preserves replaced installations inside Ice-backups.noindex/
beside its destination, preventing the same search clutter on later installs.

The final beta is installed and About reports 0.11.13-dev.2-macos27.2. After
replacing the app, its stale Accessibility entry was removed and the exact
/Applications/Ice.app path added again; Ice reported Permission Granted and
completed setup. Opening Menu Bar Layout visibly restored BetterTouchTool,
Wi-Fi and other assigned apps in MenuBarAgent's tree. Returning to General
removed them again. General still reports active-but-unverified hiding because
the beta's broader discovery snapshot is incomplete. This is not reported as
fully verified runtime behavior.

Installed executable SHA-256:
8918da41eee5d3398457a72b0eee68aa32f25d4530e7f470115da66ba02ff36b.
The immediate previous installation is preserved in the extraction-verified
2026-09-22-before-beta-click-update.zip archive. Physical tracker-click,
empty-space/context/hover, and additional-display checks remain unverified.
