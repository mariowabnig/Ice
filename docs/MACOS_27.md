# macOS 27 compatibility

## Why the old layout pane was empty

On macOS 27.0 (26A428), Ice logged `Missing control item for hidden section` and cleared its entire item cache. MenuBarAgent now composites status items: the old `CGSGetProcessMenuBarWindowList` path does not supply the individual item windows Ice needs. The running app had Accessibility and Screen Recording permission, so resetting those permissions would not repair this discovery path.

## New backend

`AppState.modernMenuBarManager` owns the macOS 27 path. macOS 14–26 retain the existing window-based implementation.

- `ModernItemEnumerator` walks MenuBarAgent's Accessibility tree off the main actor, with bounded messaging timeouts, resolves app identities, and deduplicates display instances.
- The new layout editor displays application icons and names without requiring Screen Recording. Search filters the editor. It never fabricates CGWindowIDs for scene-based items.
- Dragging onto another item resolves fresh, on-screen frames, performs a native Command-drag, and checks the resulting relative order. macOS persists the physical order. A rejected or off-screen move is reported instead of silently treated as success.
- Dropping into a section changes the app's assignment. Third-party hiding is per application, so all of an app's status items share one section. Supported core system controls use separate `system:<raw identifier>` assignment keys; existing app assignments still decode unchanged. Assignments are stored separately under `Defaults.Key.modernMenuBarLayout`; existing settings are not overwritten.
- Opening the editor temporarily reveals items; leaving it restores concealment. Ice's section actions and rehide timers use the new backend.
- Section assignments save immediately, but the menu bar continues showing all items while Menu Bar Layout is open. Switch to General or Menu Bar Appearance, or close Settings, to see the saved hiding behavior. Returning to Menu Bar Layout reveals items again without changing any assignments.
- Concealment uses a process-bound MenuBarClientCore assertion. Errors/timeouts release the assertion. Quitting Ice releases it too. The allowlist includes other running applications, and refresh updates it when applications launch or quit.
- Scene dividers no longer expand to enormous widths. Search opens the new searchable editor. On macOS 27 the old separate Ice Bar falls back to the system menu bar, and the ineffective legacy spacing/relaunch control is not offered.

## Current limits

- Tiles show application icons, not live captures of each status-item glyph.
- Move endpoints must be visible in the same menu bar. Expand macOS's overflow area before moving an off-screen item. Additional displays have not been manually verified.
- Wi-Fi, Battery, Sound, Bluetooth, Display, Input Menu, Clock and Screen Mirroring use individual system allowlist entries. SystemUIServer extras hide together by bundle. Control Center itself and helper overlays without a bundle identity cannot be hidden.
- User can be assigned to a hidden section, but it hides together with optional Control Center extras (including AirDrop and Focus). macOS also removes this group whenever any other hiding assertion is active, even if User is assigned Visible. Reveal all sections to restore the group. The User-only assignment activates an assertion with all supported core controls allowed.
- The assessment mechanism can also prevent clicking the clock from opening Notification Center while concealment is active. Reveal all sections first if affected; this backend does not yet provide a clock-click workaround.
- The original divider-based section assignments cannot be inferred reliably once macOS stops exposing those windows. Choose sections in the new editor; the old preferences remain intact for older macOS versions.
- The private concealment API can change between macOS releases. Availability and selector checks must remain in the Objective-C shim.

## Other fixes in this change

- Replace CompactSlider 1.x with native SwiftUI sliders; the dependency's `opacity` call is ambiguous in the macOS 27 SDK. Preserve continuous and stepped values and their labels.
- Avoid explicitly deactivating Ice when its last window closes on macOS 27.
- Capture window actions from live SwiftUI scenes. Settings commands reuse and raise the existing window, restore it when minimized, and request the active Space; reopening Ice from Finder opens Settings. macOS 27 activation no longer uses the legacy Dock hop.
- Make AppState setup idempotent.
- Validate NSWindow IDs against actual CoreGraphics windows, since a scene identifier can fit in UInt32 without being a CGWindowID. Use the primary display origin for AppKit-to-CoreGraphics conversion.
- Release the temporary capture-window buffer, reject empty captures, and publish legacy image scale metadata before publishing images.
- Use the actual Screen Recording preflight check on macOS 27; individual window titles no longer indicate that permission.

## Verification

Build and the 17-test macOS suite passed locally with Xcode's macOS 27 SDK on 2026-09-15. Five tests cover new-app defaults, independent hidden/always-hidden reveal behavior, app identity across changing status titles, saved-layout round trips, and invalid saved sections. Five additional tests cover independent system assignments, persistence/reveal, User-only assertions, collateral User visibility, and backward compatibility. The seven existing auxiliary reservation tests also pass.

Commands (full Xcode required):

```sh
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Ice.xcodeproj -scheme Ice -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
```

The developer installation on this Mac has pending setup/license and CoreDevice/CoreSimulator warnings. Calling Xcode's own `Contents/Developer/usr/bin/xcodebuild` directly completed these macOS builds/tests; no license was accepted or system developer configuration changed.

Live verification on this Mac confirmed that the new editor discovers and displays the installed menu bar applications. After the window fix, reopening Ice from Finder brought Settings to the front after both closing and minimizing it. The missing-permission launch also displayed the Permissions window. The window fix builds successfully; switching Spaces and the menu command itself have not been independently exercised.

The system-item update passed all 17 tests and was installed on 2026-09-15. After removing the stale Accessibility entry and adding `/Applications/Ice.app` again, Ice reported permission granted. Its granted-Accessibility / absent-Screen-Recording launch populated the editor. Both Wi-Fi and User were assigned Hidden through their context menus; MenuBarAgent AX confirmed that both disappeared after leaving the editor, while Battery, Clock and Control Center remained. Reopening the editor restored Wi-Fi and User. Both assignments are left in Hidden.

The previous installed app is preserved at `build/backups/2026-09-15-macos27/Ice.app`, and the build before the window fix at `build/backups/2026-09-15-before-window-fix/Ice.app`. Local ad-hoc rebuilds can require macOS to reapprove Accessibility; the latest installation has Accessibility restored. Screen Recording restoration requires a macOS Touch ID prompt. Remaining runtime verification includes a physical move and reverse move, search, and additional displays. Do not infer runtime success from compilation or unit tests.

## Follow-up verification — 2026-09-16

BetterTouchTool's Hidden assignment was confirmed in the running editor and saved preferences. Switching from Menu Bar Layout to General activated the visibility assertion successfully; after the menu bar settled, BetterTouchTool disappeared from MenuBarAgent's Accessibility tree. Returning to Menu Bar Layout revealed it again while its assignment remained Hidden. No code or assignments were changed during this investigation.

Before shipping, the Debug build and all 17 macOS tests passed again using Xcode's own `xcodebuild` with `-destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build test`. The existing CoreDevice/CoreSimulator environment warnings did not prevent the macOS build or test run. SwiftLint was not installed locally, so local lint verification was unavailable.

## Source attribution

The bounded AX enumerator, system identifier mappings and Objective-C MenuBarClientCore shim are adapted from [fif7y/Pelmet](https://github.com/fif7y/pelmet), revision `76db5715991a82e4583f93c360fba9807750d040`, licensed under GNU GPL v3. Ice is also GPL v3. The copied portions retain their original descriptive comments, with type/function names and logging adapted to Ice. The original GPL license is retained in `docs/licenses/Pelmet-GPL-3.0.txt`. The manager, editor, persistence model, and integration are specific to this fork.

Thaw's macOS 27 release notes were useful context, but the inspected public Thaw tag did not contain the advertised new backend; it was not used as the basis for this implementation.
