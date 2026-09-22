# Automatically hidden menu bars

Status: implementation and local review complete, 2026-09-22.

Build 0.11.13-dev.2-macos27.3 keeps interaction within the presented menu bar
or its one-pixel reveal edge. Stationary hover waits through slide-down using
fresh bounded AX reads; pointer/input generations still cancel stale actions.
Occupancy reads only the window under the pointer. Visibility verification uses
presented-display observations while retaining editor discovery from other
displays, and preserves concealment assertions during normal retraction.

Adversarial review found that missing/invalid window geometry or failed display
enumeration could be mislabeled as retraction, pausing verification indefinitely.
Only positively established retraction now pauses verification. Unknown geometry
keeps the bounded unreadable-snapshot path. No remaining code-level ship blocker
was found. The simplification pass retained the shared geometry and scheduling
helpers without removing the necessary post-await checks.

Validation after review: 50 native XCTest cases, 17 standalone production-code
checks, SwiftLint 0.65.1 strict (zero violations), shell syntax, Debug test build,
and universal Release installation passed. Both installed apps pass strict
recursive signature verification. Ice was restarted and General reported active
hiding. Its Accessibility entry had been removed and the exact installed app
re-added; the stable-signature rebuild preserved that approval.

Physical hover/retract, fullscreen and secondary-display behavior still need
hands-on verification. The native UI driver cannot reliably exercise the
composited menu bar, so model tests and the active-hiding status do not establish
those end-to-end checks. Saved assignments and auto-hide preferences were kept.
The pre-update local changes remain separately preserved in the existing stash.
