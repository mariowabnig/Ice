# Ice review fixes — 2026-09-26

Scope: Part C of `../.prd/code-review-fixes-portworth-cockpit-ice.md`. Local Conventional Commits group related fixes; nothing was pushed.

## Implementation

- C1: every AX attribute read sets a maximum 0.2-second messaging timeout; snapshot reads share a 1.5-second deadline and report partial/read-error snapshots. Debug logs include read count and duration.
- C2: macOS 27 does not install the legacy auxiliary-cover pointer monitor or 1/5-second timers. `_HIHideMenuBar` is cached and refreshed every 30 seconds.
- C3: refresh captures visibility generation, applied plan, and suspension epoch before awaiting; stale replies cannot update discovery or invalidate assertions. Verification cannot fail inside the three-second settle window.
- C4: move completion uses merged discovery and preserves the previous list on empty/unreadable snapshots.
- C5: pointer movement cancels hover intents only; clicks allow up to four points of jitter and retain the menu-bar geometry checks.
- C6: MenuBarAgent AX notifications request debounced refreshes, with a 20-second backstop. Sleep and inactive-session suspension are tracked independently. Wake during an in-flight refresh coalesces an immediate follow-up instead of losing it. Stop/suspend cancels verification and removes the AX run-loop source. Stale occupancy replies after suspension are rejected.
- C7: application launch/termination triggers refresh; assertion reapplication compares allowed bundles owning observed status items, avoiding reactivation for unrelated applications. New-app visibility still needs live verification; observer support and discovery of newly hidden items depend on macOS behavior.
- C8: hover show/rehide delays share one stored cancellable task.
- C9: the three-second verification task is owned/cancelled; hide-application-menus is explained as unavailable in the macOS 27 UI and its legacy callback is gated.

## Automated verification

Host: macOS 27.0 (26A428), scheme `Ice` verified with `xcodebuild -list`.

Command:

```sh
xcodebuild -project Ice.xcodeproj -scheme Ice -destination 'platform=macOS' \
  -derivedDataPath /tmp/ice-review-derived CODE_SIGNING_ALLOWED=NO test
```

Result: **53 tests passed** (`/tmp/ice-review-final-tests.log`). Xcode printed CoreDevice/CoreSimulator version warnings, but the macOS build and test action succeeded. The build phase reported that SwiftLint is unavailable; strict lint has not been verified. `git diff --check` passed.

Added lifecycle regression tests were run before their fixes and both failed (`/tmp/ice-review-lifecycle-repro.log`):

- `testWakeDuringSnapshotQueuesImmediateRefresh`
- `testSessionActivationDoesNotResumeSleepingScreens`

Both pass after the fixes. Existing/expanded tests cover stopped-manager stale replies, stale visibility generations, settle-window behavior, occupancy geometry/jitter, and merged item discovery. Tests synthesize notifications inside the test process; they do not put the Mac to sleep.

## Install and runtime verification

The initial attempt to install Xcode's test-built Debug app was rejected by strict signing because it contained `IceTests.xctest`. No signing checks were weakened. A clean **Release build succeeded** in the same fresh DerivedData (`/tmp/ice-review-release-build.log`; final formatting rebuild: `/tmp/ice-review-final-release-build.log`), followed by successful installation and launch through the unchanged script:

```sh
ICE_INSTALL_SOURCE=/tmp/ice-review-derived/Build/Products/Release/Ice.app ./build-and-install.sh
codesign --verify --deep --strict /Applications/Ice.app
```

Both commands succeeded. Install logs: `/tmp/ice-review-release-install.log` and final `/tmp/ice-review-final-install.log`. The final installed process is PID 81801; strict signature verification passed again. The previous working app is preserved at `/Applications/Ice-backups.noindex/Ice-20260926-160955.app`; the second backup ending `161141` contains the rejected test-bearing Debug install, not the previous working app.

The script could not establish a trusted local signing identity and used its existing **ad-hoc signing fallback**. Read-only UI inspection of the launched app (initial PID 76731, final PID 81801) showed the **Permissions** window, Accessibility and Screen Recording grant buttons, and disabled Continue. Existing grants were not revoked or reset. The user needs to reapprove Accessibility before the modern backend can run; Screen Recording is shown as optional for limited mode.

A 12-sample `top` capture showed 0.0–2.5% CPU (mean 0.82% across all samples), but this measures the permission window, **not** the modern backend and does not establish either CPU acceptance threshold. A ten-second `/usr/bin/sample` capture completed with no `persistentDomain` or `ModernItemEnumerator` matches. With setup blocked on permission, that absence is not evidence about pointer-move or idle backend performance. Artifacts: `/tmp/ice-review-runtime-top.txt`, `/tmp/ice-review-runtime.sample.txt`. No user pointer movement, real sleep, permission changes, or deliberate app hangs were triggered.

## Remaining manual acceptance

- Deliberately hung status-item helper: verify wall-clock snapshot duration under two seconds and visibility convergence. Deadline/timeout code is present, but this real AX failure scenario has not been exercised.
- Sustained pointer movement: measure CPU below 1% and absence of per-move persistent-domain copies. Static samples alone cannot prove this threshold.
- Real screen sleep/session lock/wake: verify no new AX reads while suspended and prompt resume from logs. Notification regressions cover logic without interrupting the user's Mac.
- Confirm AX created/destroyed/moved notification support on this OS build and measure actual reads/minute against the previous build; the backstop frequency alone drops from 20 to 3 polls/minute (85%).
- Launch a newly installed status-item app while hiding is active; verify it stays visible and unrelated applications do not cycle assertions.
- Missing-permission startup, granted-permission hide/show and layout drag, fullscreen/auto-hide, multiple displays, click jitter, and live task-count checks remain manual.
- C9 ad-hoc helper/team behavior is **unverified on macOS 26**. Host is macOS 27; service security checks were not weakened.

## Commit grouping

C1 (AX deadlines) is independent. C2 and the C9 platform setting gate share the legacy manager/UI boundary. C3/C4/C6/C7 and C9 task ownership share the modern manager's refresh and assertion lifecycle, so they are committed together rather than creating partially working intermediate lifecycle states. C5/C8 share event intent/task ownership and are committed together. The final documentation commit records validation, installation, and manual gaps.

Local code commits:

- `2c061f6` — C1: bound modern Accessibility snapshot reads.
- `dd7447a` — C2/C9: gate legacy menu bar work on macOS 27.
- `6196cc1` — C3/C4/C6/C7/C9: synchronize modern refresh lifecycle.
- `f61c7f4` — C5/C8: preserve click intents and coalesce hover delays.

## Follow-up: Accessibility entry recovery

The user reported an empty Menu Bar Layout after installation. The Accessibility switch in System Settings was on, but Ice's actual access check still failed. With the user's approval, the coordinating agent removed and re-added the current `/Applications/Ice.app` Accessibility entry; the layout populated again. This verifies the observed empty layout was recoverable through permission repair, rather than proving an AX timeout failure. Permission entry changes require user authorization; Ice does not automate them.

The follow-up code now:

- Rechecks the running process using the existing AX trust check, including when returning to the layout and when retrying after periodic permission checks have stopped.
- Distinguishes denied process access, a refresh in progress, and a permitted-but-empty snapshot with a pure diagnostic selector.
- Shows conditional remove/re-add guidance and the running app's actual bundle path, without claiming Ice can identify whether permission is missing or an older entry is involved.
- Offers Open Accessibility Settings and Retry Access in the permission window, plus Retry Access and Refresh in the layout. Retry awaits the existing one-time app setup before requesting another snapshot.
- Makes Continue recheck actual permissions instead of trusting a cached state.

Six focused tests cover diagnostic precedence, allowed-but-empty snapshots, current path guidance, and explicit grant/revocation checks after periodic checks stop. The full suite passed: **59 tests, zero failures/skips**, confirmed with `xcresulttool get test-results summary` (`/tmp/ice-permission-diagnostics-tests.log`). The earlier 52-test report undercounted an interleaved output line; that preceding run had 53 passing tests. The Release build also succeeded (`/tmp/ice-permission-diagnostics-release.log`); install source: `/tmp/ice-review-derived/Build/Products/Release/Ice.app`. The coordinating agent will install and verify the UI with reauthorization arranged; this worker has not installed or restarted the app.


Final follow-up UI verification: installed the tested Release via `build-and-install.sh` with strict signature verification. The installed Permissions window displayed the new actual-access denial guidance and current application path; Open Accessibility Settings reached the correct pane. After the user-authorized remove/re-add, the window reported Permission Granted and Continue in Limited Mode completed setup. Menu Bar Layout visibly populated all three saved sections, and Retry Access and Refresh retained the items. Screen Recording was not reauthorized; it remains optional and the app is in limited mode. This check verifies permission recovery and layout discovery, not hiding/CPU acceptance. Backup: `/Applications/Ice-backups.noindex/Ice-20260926-163232.app`. The local build remains ad-hoc signed, so future rebuilds can require reauthorization; the new UI explains that recovery instead of silently leaving empty sections. No TCC database edits or automatic permission resets were added.
