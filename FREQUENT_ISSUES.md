# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Ice removed an item](#ice-removed-an-item)
- [Ice does not remember the order of items](#ice-does-not-remember-the-order-of-items)
- [A visible app is missing from the Menu Bar Layout view](#a-visible-app-is-missing-from-the-menu-bar-layout-view)
- [A visible app remains onscreen when the menu bar auto-hides](#a-visible-app-remains-onscreen-when-the-menu-bar-auto-hides)
- [How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-ice-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)
- [Why do local installs keep asking for Accessibility or Screen Recording permission?](#why-do-local-installs-keep-asking-for-accessibility-or-screen-recording-permission)

## Items are moved to the always-hidden section

By default, macOS adds new items to the far left of the menu bar, which is also the location of Ice's always-hidden section. Most apps are configured
to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This results in
these items appearing in the always-hidden section, even if they have been previously been moved.

Ice does not currently manage individual items, and in fact cannot, as of the current release. Once issues
[#6](https://github.com/jordanbaird/Ice/issues/6) and [#26](https://github.com/jordanbaird/Ice/issues/26) are implemented, Ice will be able to
monitor the items in the menu bar, and move the ones it recognizes to their previous locations, even if macOS rearranges them.

## Ice removed an item

Ice does not have the ability to move or remove items. It likely got placed in the always-hidden section by macOS. Option + click the Ice icon to show
the always-hidden section, then Command + drag the item into a different section.

## Ice does not remember the order of items

This is not a bug, but a missing feature. It is being tracked in [#26](https://github.com/jordanbaird/Ice/issues/26).

## A visible app is missing from the Menu Bar Layout view

Some menu bar apps use a status-level overlay window when their native status item exists but is not visibly placed by macOS. Portworth is one example: it can show a portfolio title and sparkline in a Portworth-owned status-level window titled `com.portworth.app.statusItem`.

What failed:

1. Looking only at macOS's private menu bar item list missed these overlay-backed items.
2. Classifying sections only by Ice's divider item positions could place a real on-screen overlay into the wrong section when the overlay appeared left of the usual status cluster.
3. Letting the overlay app detect its own window as a native item caused brief hide/show flicker after wake or unlock.

What works:

Ice now merges the private menu bar item list with auxiliary on-screen status-level windows whose titles start with their owning app's bundle identifier, or the dashed form of that bundle identifier. If macOS reports a scripted/helper app's status-level window without a bundle identifier or CoreGraphics title, Ice can still treat the top-pinned app-owned window as auxiliary by using its owner name while excluding known system owners. These auxiliary windows are cached as visible when they are on screen, because that matches what the user actually sees in the menu bar.

Ice treats auxiliary item frame changes as cache changes too. This is important for apps whose status-level windows move, resize, or change visibility without getting a new window identifier.

When the hidden section is shown in the native menu bar, Ice also keeps enough invisible divider width reserved for these auxiliary status windows. The reservation uses the auxiliary window frames captured while the hidden section is hidden, so newly shown native items are added to the left without pushing the auxiliary window around. This prevents hidden native menu bar items from sliding under an auxiliary overlay window that macOS does not manage as a normal status item.

Some auxiliary status windows are shorter than the system menu bar and are pinned by macOS to the menu bar's top edge. Ice cannot move those third-party windows directly, so it places a pass-through visual cover over the item while the menu bar is visible, redraws the menu bar background, and paints the captured auxiliary item centered within the full menu bar height. The cover ignores mouse events, so clicks still reach the owning app's real status window.

When Ice renders auxiliary windows inside Ice Bar or the Menu Bar Layout view, it trims transparent horizontal padding from the captured image. Some apps expose a much wider status-level window than the content they actually draw, and trimming keeps those items from appearing offset inside Ice's own UI.

Implementation note: Ice's hide/show control is driven by both the control item's published hiding state and the spacer length applied to the status item. When updating this flow, make length and auxiliary reservation calculations use the state value currently being applied, because reading the stored state during a publisher callback can be stale and can leave hidden items visible after the user clicks Hide.

This is intentionally generic. It does not hardcode Portworth, but Portworth's stable `com.portworth.app.statusItem` window title, or its app owner name on systems where CoreGraphics reports an empty title, gives Ice enough identity to show it in the Visible Section.

## A visible app remains onscreen when the menu bar auto-hides

Some apps draw their own status-level window in the menu bar. Portworth is one example. These windows are owned by the app, not by Ice or the macOS menu bar, so Ice cannot move or hide them the same way it moves native status items.

When the macOS menu bar is configured to automatically hide and show, Ice handles these auxiliary status-level windows by placing a cover window over each auxiliary item. The cover tracks the auxiliary item's current position and becomes visible as soon as the pointer leaves the menu bar. Ice refreshes the cover image when the cover appears, when the auxiliary item moves, and periodically while hidden, instead of recapturing it on every pointer movement.

The same cover mechanism may also be visible while the menu bar is shown for auxiliary windows that macOS pins to the top edge of the menu bar. In that case, Ice redraws the captured item centered in the menu bar instead of hiding it.

This cover is visual only. The app that owns the auxiliary window still owns its window and may update or animate it independently.

## How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?

Showing and rehiding hidden items is supported when the macOS menu bar is set to automatically hide and show. Arranging menu bar items still requires the menu bar to be permanently visible while you make layout changes:

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Ice`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)

## Why do local installs keep asking for Accessibility or Screen Recording permission?

macOS stores Accessibility and Screen Recording grants against the installed app's identity. Local development builds are ad-hoc signed, so macOS can still occasionally treat a rebuilt app as a new app, especially after changing signing, bundle contents, or the installed app path.

The `build-and-install.sh` helper preserves existing TCC permissions. It no longer calls `tccutil reset` for Accessibility or Screen Recording during install, and it signs the embedded Sparkle framework and Ice app separately before launching the new build.

If macOS still does not apply an existing grant to a local ad-hoc build, remove Ice from `System Settings` > `Privacy & Security` > `Accessibility`, add `/Applications/Ice.app` again, and relaunch Ice. Stable Developer ID signing is the long-term way to avoid most rebuild identity churn.
