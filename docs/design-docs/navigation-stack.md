# Navigation implementation

Contract: [navigation](../product-specs/navigation.md).

[`TabCoordinator`](../../Shared/Coordinators/Tabs/TabCoordinator.swift) keeps selection
and a `NavigationCoordinator` for each tab. [`Router`](../../Shared/Coordinators/Navigation/Router.swift)
exposes route operations and the environment dismissal action.

[`NavigationCoordinator`](../../Shared/Coordinators/Navigation/NavigationCoordinator.swift)
owns `path`, `presentedSheet`, and `presentedFullScreen`. On tvOS, `.push` and `.sheet`
create a presented child coordinator; `.fullscreen` creates a full-screen child.
If a child is already presented, pushes are forwarded into it.
[`NavigationInjectionView`](../../Shared/Coordinators/Navigation/NavigationInjectionView.swift)
wraps each coordinator in a NavigationStack and renders both TV presentation slots
using full-screen covers. iOS `.push` instead appends to the path.

Consequently, `path.isEmpty`/`isRootOfPath` alone cannot prove that Home is visible.
A details presentation may have its own player presentation above it.

Home Continue Watching routes `.item` via
[`CinematicSelectionContentGroup`](<../../Swiftfin tvOS/Objects/CinematicSelectionContentGroup.swift>).
[`NavigationRoute+Item`](../../Shared/Coordinators/Navigation/NavigationRoute/NavigationRoute+Item.swift)
creates an `ItemContentGroupProvider`/`ItemView`. `PlayButton` routes a full-screen
player from that details environment. Dismiss the player at its own level.

Other launch paths must be traced separately. [EpisodeCard](../../Shared/Objects/ContentGroup/SeriesEpisodeContentGroup/SeriesEpisodeContentGroup+EpisodeCard.swift)
has distinct artwork-play and content-details actions. [Socket playback commands](../../Shared/Services/UserSession/UserSessionManager+SocketCommands.swift)
can route a player through the selected tab; with Home selected and no presented
child, this can launch directly over Home. It is not a Home tile Play action, and
restoring an originating tile cannot be assumed when no tile was selected.

[`MainTabView`](../../Shared/Coordinators/Tabs/MainTabView.swift) observes Home's item
sheet coordinator and direct/details player presentation slots. It reports those
changes to the Home focus coordinator; it does not need to flatten navigation.
These observations target the Home → item details → player shape. Deeper nested
item presentations need explicit tracing if a future task changes that flow.

See [focus system](focus-system.md) for restoration gating and
[playback lifecycle](playback-lifecycle.md) for player teardown.
