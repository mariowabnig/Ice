# Input Menu hiding review — 2026-09-24

Scope: the macOS 27 Input Menu host allowlist repair and its diagnostics.

Adversarial review found a privacy issue: public verification results could include dynamic menu-item titles. Corrected the result interpolation to private logging and replaced the per-item raw identifier with a private bundle identifier. The captured machine log is excluded from the commit.

No remaining blocking findings. The repair keeps the app and system allowlists consistent when keyboard is concealed, without excluding its host when keyboard is revealed or only another system item is hidden. The existing fail-open lifecycle is unchanged.

Simplification review retained the small visibility-plan helper: it centralizes the required relationship and enables regression coverage without adding a new abstraction.

Validation: all 52 native Debug XCTest cases passed with the signed test host; all 19 standalone checks passed; strict SwiftLint 0.65.1 and shell syntax validation passed. The final universal Release build passed, was installed with the existing local signing identity, and passed strict recursive signature verification. A final editor reveal/conceal cycle returned to active hiding after the bounded unreadable-snapshot retry. Live reveal/conceal cycles, sustained hiding and restart were verified during the repair. Portworth returned to its settled position after reveal/conceal. Physical pointer-driven auto-hide, fullscreen and second-display behavior remain unverified.

Recommendation: ship the bounded repair. See docs/MACOS_27.md for installation and live-test evidence.
