# Focus system

Contract: [focus restoration](../product-specs/focus-restoration.md).

[`FocusCoordinator`](../../Shared/Objects/FocusCoordinator.swift) publishes focused IDs
and requests. TV `HomeTile` carries group/item/series/index; its target combines group
and item identity. `selectHomeTile` records the origin. `homePlayerPresented(fromDetails:)`
records the actual player origin. `homePlayerDismissed` releases refresh deferral
but keeps a details-origin Home focus request dormant until `homeDetailsDismissed`.

[`ContentGroupView`](../../Shared/Views/ContentGroupView.swift) owns the Home coordinator,
observes refresh completion, and supplies row manifests/revisions. Content groups and
[`PosterHStack`](../../Shared/Components/PosterHStack.swift) expose rows;
[`PosterButton`](../../Shared/Components/PosterButton.swift) registers selection,
layout readiness, and acquired focus. The coordinator resolves the current fallback
order against refreshed rows, scrolls the underlying virtualized collection to the
target, and requests focus only once that tile is ready. Acquisition clears protection.

[`MainTabView`](../../Shared/Coordinators/Tabs/MainTabView.swift) observes presentation
changes and protects the Home return from sidebar focus. Navigation ownership remains
with the navigation coordinators; focus events must not dismiss intermediate screens.

`ItemView` owns a separate coordinator initially targeting its Play action.
TV Search uses `@FocusState` in [SearchView](../../Shared/Views/SearchView.swift) plus
[`TVSearchFocusCoordinator`](<../../Swiftfin tvOS/Extensions/View/View-tvOS.swift>) to
hand sidebar Right/Select entry to the app-owned field. iOS retains `.searchable`.
Do not assume keyboard/responder readiness proves remote focus has moved.

These are current mechanisms, including uncommitted work present at inspection.
Validate refresh, removed/replaced tiles, offscreen rows, and Back behavior at runtime;
see [QUALITY.md](../QUALITY.md).
