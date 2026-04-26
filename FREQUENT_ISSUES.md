# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Ice removed an item](#ice-removed-an-item)
- [Ice does not remember the order of items](#ice-does-not-remember-the-order-of-items)
- [A visible app is missing from the Menu Bar Layout view](#a-visible-app-is-missing-from-the-menu-bar-layout-view)
- [How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-ice-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)

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

Ice now merges the private menu bar item list with auxiliary on-screen status-level windows whose titles start with their owning app's bundle identifier, or the dashed form of that bundle identifier. These auxiliary windows are cached as visible when they are on screen, because that matches what the user actually sees in the menu bar.

When the hidden section is shown in the native menu bar, Ice also keeps enough invisible divider width reserved for these auxiliary status windows. This prevents hidden native menu bar items from sliding under an auxiliary overlay window that macOS does not manage as a normal status item.

This is intentionally generic. It does not hardcode Portworth, but Portworth's stable `com.portworth.app.statusItem` window title gives Ice enough identity to show it in the Visible Section.

## How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?

Showing and rehiding hidden items is supported when the macOS menu bar is set to automatically hide and show. Arranging menu bar items still requires the menu bar to be permanently visible while you make layout changes:

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Ice`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)
