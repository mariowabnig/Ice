# Menu bar recovery review — 2026-09-26

Scope: the macOS 27 watchdog, recovery policy, manager setup/stop integration,
saved cooldown, and version 0.11.13-dev.2-macos27.4. Reviewed locally using the
adversarial-review and simplify-code workflows before shipping.

## Integration

Fetched the fork and inspected remote branch heads/open PRs. Local main and
origin/main both started at 42bf809; no newer fork commit needed merging.
Existing Input Menu, Itsycal, automatic menu bar hiding and beta integration
fixes remain included. Upstream main has no commits missing from this main;
the older upstream macos-26 development branch was not substituted for the fork.

## Findings and resolution

- High, resolved during live verification: NSRunningApplication.launchDate is
  nil for MenuBarAgent, so requiring it prevented all monitoring. Identity now
  uses the kernel's process start seconds/microseconds; a read-only integration
  test checks that the real running system agent has a usable, stable identity.
- Medium, resolved: a forward wall-clock adjustment could shorten the cooldown
  of a running watchdog. ModernMenuBarHealth.secondsSinceRecovery now uses the
  smaller wall-clock and monotonic elapsed intervals. The persisted date retains
  cooldown across normal relaunches. Regression tests cover forward/backward
  clock movement. Changing the clock and relaunching together is not protected
  by a persisted boot identity; this is a reliability limit, not a security claim.
- Low, resolved: startup logging alone did not show whether health probes ran.
  ModernMenuBarWatchdog.check now records bounded debug probe results and the
  signal errno. No menu item titles or application content are logged.
- Examined false positives, missing permissions, lock/sleep, process replacement,
  stale async work and restart loops. Recovery requires root AX transport
  timeouts plus sustained resource pressure, active unlocked session, no layout
  edit/move, matching PID/kernel start time, exact system executable and current UID.
  Generation checks discard probes spanning suspension/stop. Failed signals
  consume cooldown too; no SIGKILL escalation occurs.

## Simplification

Replaced the optional timestamp initialization/fallback with one resolved local
timestamp. Kept the pure policy separate from OS effects so the dangerous-action
criteria remain directly testable; kept actor isolation and identity checks.

## Validation and recommendation

Ship: no remaining blocking findings. All 63 native XCTest cases (including ten
watchdog-policy tests and the live identity check), 19 standalone checks, strict SwiftLint 0.65.1 and the
universal Release build passed. Installed with the existing local signing
identity; strict recursive verification passed. Live General reports active
hiding, the watchdog startup is logged and the layout hash is unchanged.
The final installed build also logged a real health probe with `timedOut=false`
and approximately 25 MB resident memory; the existing MenuBarAgent PID remained
unchanged. This verified the kernel-identity correction in the running app.

The original hang's trigger remains unknown. This is bounded recovery, not proof
that Ice or macOS cannot hang again. No artificial resource-heavy system hang
or physical sleep/lock cycle was induced; actual automatic restart during a
future hang remains a live-validation limitation. Evidence of recovery while
locked, restarts without sustained root timeouts, or repeated restart attempts
inside the cooldown would change the ship recommendation.

The pre-existing diagnostic log docs-internal/input-menu-hiding-2026-09-24.log
is intentionally excluded from the commit and stays local.
