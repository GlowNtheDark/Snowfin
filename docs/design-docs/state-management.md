# State and data boundaries

## Session and persistence

[`UserSessionManager`](../../Shared/Services/UserSession/UserSessionManager.swift)
owns authentication/current session through FactoryKit registration.
[`UserSession`](../../Shared/Services/UserSession/UserSession.swift) owns the Jellyfin
client and starts/stops connection/socket services. The shared
[`ViewModel`](../../Shared/ViewModels/ViewModel.swift) supplies authenticated requests,
logging, and Combine subscriptions. Action/state models use StatefulMacros; views
use ObservableObject, StateObject, and local SwiftUI state for presentation.

[`SwiftfinStore`](../../Shared/SwiftfinStore/SwiftfinStore.swift) manages versioned
CoreStore/SQLite persistence and local ServerState/UserState models.
StoredValue/Defaults hold preferences; Keychain owns credential storage. UI state
is not an alternative source of server media truth.

## Items and propagation

Jellyfin `BaseItemDto.userData` carries `isPlayed`, `playbackPositionTicks`, and
`lastPlayedDate`. [`ItemContentGroupProvider`](../../Shared/Views/ItemContentGroupView/ItemContentGroupProvider.swift)
fetches the full item and resolves a playback provider. On tvOS, Movie and top-level
series Details overlay session-scoped `ItemState` on their local metadata snapshot;
accepted watched/favorite responses update that state through
[`Notifications`](../../Shared/Services/Notifications.swift). The iOS Details path keeps
its existing snapshot and optimistic action behavior.
[`PagingLibraryViewModel`](../../Shared/Objects/PagingLibrary/PagingLibraryViewModel.swift)
updates matching item IDs and calls each library's user-data hook.

[`BaseItemDto` extensions](../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift)
derive progress labels/percentages. [`PosterIndicatorsOverlay`](../../Shared/Components/PosterIndicators/PosterIndicatorsOverlay.swift)
uses `isPlayed` for completed styling. Never promote high progress into watched state.
[EpisodeCard](../../Shared/Objects/ContentGroup/SeriesEpisodeContentGroup/SeriesEpisodeContentGroup+EpisodeCard.swift)
has a separate indicator path; check it too when a change affects episode-card styling.
For disagreements, correlate the same ID in fresh server data and local mappings;
UI appearance alone cannot identify the cause. If Jellyfin itself returns contradictory
state, report that evidence rather than changing local semantics to hide it.

## Continue Watching and refresh

[`ResumeItemsLibrary`](../../Shared/Objects/Libraries/ResumeItemsLibrary.swift) starts
from Jellyfin resume items. TV video requests also fetch Next Up and recently played
episodes. It chooses partial episodes ahead of Next Up for each series, uses a 14-day
completed-series activity window, deduplicates by series ID (name fallback), preserves
non-episode resume entries, then sorts the combined result by last-played activity.
The iOS branch returns the resume response directly.

[`CinematicSelectionContentGroup`](<../../Swiftfin tvOS/Objects/CinematicSelectionContentGroup.swift>)
performs display deduplication and passes updates to the Top Shelf snapshot writer.
The custom Play Next overlay has its own resume-library view model, so those surfaces
share derivation logic rather than a single in-memory list.
[`ContentGroupViewModel`](../../Shared/ViewModels/ContentGroupViewModel/ContentGroupViewModel.swift)
coalesces Home refreshes and honors focus coordinator deferral. Accepted stop reports
still refresh Home; typed progress/stop updates also reach each library's existing
membership hook. [Focus readiness](focus-system.md) is a separate gate.

Queries are bounded by page limits; this is not an exhaustive local watch-history
index. Missing IDs/dates can affect deduplication and ordering. Inspect actual payloads
before diagnosing a report. The [product contract](../product-specs/continue-watching.md)
describes the intended result; these query details describe the current mechanism.

## TV Shows and Movies session loading

The retained tvOS TV Shows and Movies tabs opt into `PagingLibraryViewModel`
automatic refresh. Their first active-scene appearance starts the existing model's
initial load, without requiring tab selection. A successful response, including an
empty one, marks initial loading complete. Subsequent refreshes replace the collection
in the background; existing content stays visible during requests and failures.

A 60-second timer checks a five-minute freshness window while the scene is active.
Scene activation and tab entry also check freshness. Typed item updates patch matching
DTOs immediately and advance the collection generation so an older in-flight snapshot
cannot overwrite them. `ItemLibrary` requests a replacement only when its active
user-data filter or sort can change membership/order; playback-position-only updates
do not trigger a Movies/TV Shows query. Metadata, delete, global-refresh, and
connection-change signals still invalidate the collection. A single worker batches
requested refreshes for 350 ms and drains one pending refresh at a time; signals during
a request require a follow-up. Filter/sort changes use that same worker. Search keeps
its own paging state and rejects results from an obsolete filter/sort environment.

This adds no item database/cache or separate preloader. The tradeoff is retaining
one full TV series collection and one full Movies collection with their grids, plus
moving both initial item/filter requests into signed-in startup. In-flight work may
finish when the scene becomes inactive; new automatic requests wait until activation.
Initial failures remain retryable by the freshness checks. Home and iOS do not enable
this policy.

## App-wide live item state audit

Audited on 2026-10-08 before the Phase 1 implementation below. The ownership findings
and migration direction remain useful; the implementation section records the current
source behavior. The focus contract remains unchanged.

### Current ownership and identity

Screen already uses MVVM and Combine/SwiftUI observation. Shared `ViewModel` subclasses are
`ObservableObject`; view models publish state with `@Published`; views own models with
`@StateObject` and observe child models with `@ObservedObject`. StatefulMacros provide action/state
machinery. This is enough infrastructure for live updates; the gap is that media state
is usually a DTO snapshot owned by each screen or collection, not one observable entity
shared by those owners.

`BaseItemDto` values are copied into independent owners: each
`PagingLibraryViewModel` holds its own `elements` and `searchElements`; each Home `PosterGroup` has its
own paging model; the tvOS Continue row and Play Next overlay each have a resume-library
model; Search suggestions are a separate array; Details keeps metadata and derived
playback/group selection in `ItemContentGroupProvider`, while Movie and top-level series
user data comes from `ItemState`; Show Details creates a season model whose elements are
further episode paging models. The observable arrays notify SwiftUI when their own
copies change, but changing one copy does not change another unless that owner observes
the shared state or handles the update event.

Jellyfin item `id` is the useful canonical identity within a signed-in
`UserSession`. `BaseItemDto.id`, `UserItemDataDto.itemID`, search/library rows, Details, and
episode rows all use that server item ID. The shared store is scoped to the current
session and keyed by item ID; a process-wide store would need a composite
server/user/item key because user data is user-specific and IDs are server-local.
Continue's `continue-watching` paging-library ID and the visual Home group ID
`cinematic-selection` identify collections/focus contexts, not Jellyfin items.
Series/episode membership and collection positions are separate identities too.

Keep four kinds of state separate:

- **Item metadata:** server-backed title, overview, image tags, people, genres, and
  other `BaseItemDto` fields.
- **User data:** `UserItemDataDto` fields including Played, PlaybackPositionTicks,
  Favorite, PlayCount, and LastPlayedDate.
- **Collection state:** server/query-derived membership and ordering for Continue,
  Recently Added, Latest, Next Up, filters, and search results.
- **Navigation and focus:** route/coordinator state and semantic group/item focus IDs.

An item update should not recreate a route or change a tile's identity. Membership or
ordering changes may remove or move a tile and need the existing focus restoration rules.

### Existing propagation and current stale-state paths

- `Notifications` is a typed wrapper over `NotificationCenter` with Combine publishers.
  `itemUserDataDidChange` now carries an `ItemUpdate` with user-session ID, item ID,
  request-start revision, and user-data or playback-position change. A matching
  `PagingLibraryViewModel` patches both published arrays, field-merges user data, then
  calls the library's `onItemUserDataChanged` hook. This does not update arbitrary DTO
  copies held by surfaces that have not migrated.
- `itemMetadataDidChange` carries a `BaseItemDto`. Home records the signal and refreshes
  its provider groups. Automatically refreshing Movies/TV Shows libraries invalidate
  and re-query. Ordinary paging models do not merge the metadata payload into their
  matching elements, so a metadata notification alone is not an app-wide item update.
- `didSendStopReport` still carries an item ID after Jellyfin accepts a stop report.
  Home refreshes its dynamic groups, and `ItemView` fetches its item only when the
  stopped ID is exactly the Details provider ID. In addition, accepted tvOS progress
  and stop reports publish typed item updates; retained Movies/TV Shows libraries use
  those to update cards and consult the active filter/sort before querying. The older
  `didSendResumeProgressReport` signal remains for its existing subscribers.
- `ItemContentGroupProvider` retains a full-item metadata snapshot and resolves a playback
  provider locally. Movie and top-level series Details observe the session's `ItemState`
  for their own item; Show Details also observes the currently selected play target's
  state for Play/Resume presentation. Accepted watched/favorite changes publish typed
  updates, and the Details provider relays shared-state changes without rebuilding the
  route. Playback target metadata/source selection, groups, trailers, backdrop, and
  route/focus state remain locally owned. Home, Search, and episode-card DTOs still use
  their existing owners.
- Show Details episode rows are nested paging models. A series-wide Mark Unwatched
  returns user data for the series, not each loaded episode. The separate
  `itemShouldRefreshMetadata` string notification is matched to the series parent by
  `SeriesEpisodeContentGroup`; it explicitly refetches the selected and already-loaded
  season episode collections and bumps a row revision. Without that targeted refresh,
  episode indicators keep their old DTOs. This is a local repair for a missing shared
  item update path.
- `ContentGroupViewModel` listens for item user-data/metadata changes. For tvOS Home,
  the Default provider refreshes all candidate groups; focus coordination can defer
  that refresh. Continue also applies its library-specific membership logic: played
  items are removed immediately, while a newly resumable item or a server-derived
  ordering change can schedule a background query. `NextUpLibrary` similarly schedules
  a query when user data can affect membership. `ResumeItemsLibrary` and the Play Next
  overlay keep separate list models and re-run their own derivation/query paths.
- Retained tvOS Movies and TV Shows libraries use `PagingLibraryViewModel` automatic
  refresh for metadata, stop, delete, user-data, global-refresh, and connection-change
  signals. They coalesce collection queries and keep matching user-data changes
  immediate. The shared poster path now covers those grids, and Movie/top-level Show
  Details also observe the same item state. Home, Search, and episode representations
  still use their existing owners.
- `ServerSocketManager` already exposes a Combine event stream and command/subscription
  publishers. The app consumes playback commands and session information; activity and
  task publisher helpers also exist. No consumed Jellyfin socket event currently
  updates item metadata, user data, or collection membership. There is no shared media
  DTO cache/invalidation layer; image caches are separate.

The result is not a lack of MVVM. It is a split between reactive owners that each hold
their own snapshot, plus events whose payloads and subscribers differ by surface. The
specific regressions above are expected when a change reaches one owner or triggers a
collection query, but another visible owner has no matching update subscription.

### Architecture options

| Approach | Churn and migration | Main benefit | Main cost/risk |
| --- | --- | --- | --- |
| **A. Improve local invalidation** | Lowest initial churn; extend typed notifications and add handlers to each DTO-owning view model. | Fits current code and keeps collection ownership unchanged. | Coverage remains distributed across Home, Details, Search, and nested episode models; each new owner can miss an event, and local copies remain a continuing stale-state risk. |
| **B. Shared store for all item and collection state** | Highest churn; collections and views would need to stop owning DTO snapshots and instead use canonical records. | One obvious source for item state and simple cross-surface propagation after migration. | Collection query/order and item facts become coupled; broad call-site changes, migration risk, and a strong store can retain every visited item. Refetch/diff changes could also disturb focus. |
| **C. Shared item state plus local collection models** | Moderate, incremental churn; keep paging, search, and Home list models, while migrating visible item views to shared observable state. | Centralizes live metadata/user-data while preserving current collection and SwiftUI/MVVM boundaries. Stable collection IDs keep focus independent. | Requires a defined merge/update event and collection-specific invalidation; during migration, unmigrated DTO owners still need the event adapter. |

**Choose C.** Add a session-scoped observable item-state service, not a new app-wide
architecture. Keep each library responsible for its query, membership, order, paging,
and filter environment. Keep `PagingLibraryViewModel` and existing
`ContentGroupViewModel` refresh/coalescing behavior as the collection layer while individual
surfaces migrate. This gives visible item views one live state without replacing the
app's MVVM model or rewriting routes and collections.

### Implemented Phase 1 shape and update flow

Use the existing Combine/`ObservableObject` conventions in `Shared`; a new Observation
framework or persistence schema is not required.

Phase 1 adds three concrete types in `Shared`: `ItemState` and `ItemStateStore` in
`Shared/Objects/ItemState.swift`, plus `ItemUpdate` in
`Shared/Services/Notifications.swift`. `ItemState` is a main-actor observable keyed by
Jellyfin item ID. It owns only canonical `UserItemDataDto`; each card keeps using its
library `BaseItemDto` for metadata and routing.

`UserSession` gets a unique UUID and lazily owns its store. `UserSession.willStop()`
resets an already-created store and cancels its notification subscription. Views strongly
hold state only while the poster is alive; the store uses weak state references and
prunes dead entries. It keeps at most 512 latest item updates as bounded replay/revision
history, applying a cached update after a library snapshot seeds a newly materialized
state. The session UUID on each update prevents same-item IDs from another session or
server reaching this store.

Mutation and playback report producers capture a monotonic request-start revision and
the originating session before starting the request. Only an accepted response/report
posts an `ItemUpdate`. When state fields merge, non-nil fields overwrite their matching
user-data fields, including explicit `false` and `0`; nil fields preserve the canonical
value. Item metadata is never merged from a user-data response. Updates with an older
revision are ignored by both `ItemState` and each paging model, whose revision history
is also capped at 512 entries. This prevents late replies from an earlier request from
overwriting newer watched/favorite/progress values.

The `itemUserDataDidChange` payload now supports `.userData`,
`.playbackPositionTicks`, and `.playbackStopped(positionTicks:)`. Existing server-backed
poster and Details toggles, series-unwatch flow, and playback-completion path publish
the returned `UserItemDataDto`. Accepted tvOS playback progress/stop reports publish
the acknowledged ticks. Existing `didSendStopReport`, metadata-refresh, and library
membership hooks remain available. Home consumes same-session `.userData` updates
through its existing group refresh path; Home and Search have not migrated their visible
DTOs to `ItemState`. Details migration is recorded below. Episode-card DTOs have not
migrated.

The retained Movies and TV Shows tabs explicitly opt into the shared store. Their grid
poster wrapper observes the item state and feeds a user-data-updated copy of the same
page DTO into the existing `PosterButton`. `CollectionVGrid` still identifies and
focuses cards by the original element ID; no new focus state, route, or focus request is
introduced. The store changes presentation in place while collection/page view models
continue to own membership, order, paging, filters, search, and queries.

`PagingLibraryViewModel` retains its matching-ID DTO patch for loaded main/search arrays
and calls each library's existing membership hook. `ItemLibrary` refreshes only when
an active played/unplayed/favorite/liked trait or status/date/count sort can be affected;
playback-position presentation updates do not query Movie/TV collections. Every accepted
update still advances the collection generation to reject an older in-flight snapshot.
An initial automatic load is rescheduled if an update invalidates it before completion.
Other libraries retain their previous refresh policy by default.

### Incremental migration and eventual cleanup

1. **Completed: shared poster/tile path in Movies and TV Shows.** The library snapshots
   seed the session-scoped state, and the retained Movies and TV Shows grids observe it.
   Collection ownership and filter-driven invalidation remain local. Home poster shelves
   and Search result groups still need their own migration.
2. **Completed: Movie and top-level TV Show Details.** The provider keeps full-item
   metadata locally and overlays same-session shared user data for the Details item and
   selected play target. Server-accepted watched/favorite changes publish typed updates;
   the Details view and retained Movies/TV Shows cards observe the same item state. The
   playback-stop full-item fetch and series `itemShouldRefreshMetadata` loaded-season
   refresh remain in place for this migration phase. The exact-ID playback-stop fetch is
   temporarily redundant for shared progress presentation, but remains for authoritative
   metadata and playback-provider refresh. The series notification and loaded-season
   refetch remain required for unmigrated episode rows. Details action callbacks no longer
   mutate a private user-data copy; successful server responses publish the shared update.
   Full snapshots seed user data only while an item's typed-update revision is still zero;
   later snapshots refresh metadata without overwriting accepted watched/favorite/progress
   state. Superseded fetch generations are discarded. Details routes, groups, and focus
   ownership remain local.
3. **Phase 3: season and episode rows.** Adopt shared item state in loaded episode cards and
   route series-wide changes to affected children. Remove the explicit loaded-season
   refresh/revision repair only after the same series-unwatch flow updates every loaded
   episode row and membership remains correct.
4. **Home and Continue.** Migrate the custom Cinematic Selection row and its separate
   resume model. Replace Home's refresh-all-groups response to item changes with
   targeted list invalidation only after each Home library reports whether the event
   affects its membership/order. Keep accepted-stop refresh and focus deferral until
   targeted behavior is verified.
5. **Search suggestions and remaining libraries.** Search result groups use the shared
   poster path; its independent suggestion array and less common DTO views need their
   own small adapters. Search query membership/order remains Search's responsibility.

After each owner is migrated, the following local repairs can be retired where the
store/event path provides equivalent behavior:

- per-surface `itemShouldRefreshMetadata` plus loaded-season refresh for series-wide
  user-data changes (retain through Phase 3 episode-row migration);
- full Details item fetches after an exact-ID playback stop (shared acknowledged ticks
  now update presentation; retain the fetch until authoritative metadata/playback-provider
  refresh coverage is proven);
- Home's refresh of every candidate group for a presentation-only item change;
- full Movies/TV Shows collection refreshes caused only by an item presentation update;
- library-specific debounce/refetch used only to make already loaded item fields fresh.

Keep collection invalidation where a query-derived membership or order can change;
these refreshes are not obsolete merely because visible item fields are shared.

Guard against stale partial DTOs overwriting richer metadata, duplicate events from a
mutation and subsequent socket message, updates crossing session/user boundaries,
memory growth from retained state objects, unnecessary full-collection queries, and
SwiftUI identity changes that drop tvOS focus. The shared code can serve iOS too, but
migration should be surface-by-surface and must preserve iOS query and presentation
behavior. Focus, route, playback-session, and progress ownership stay outside the item
store. Phase 1 changed source and passed the signed Apple TV 4K (3rd generation) 1080p
simulator build/install. Runtime checks confirmed Movies watched-state presentation
updated on the retained grid and focus returned to the originating card after Details;
TV Shows also returned to its originating card, but its action did not expose a clear
visual state change. Playback progress/stop reporting was exercised through a short
playback session, but the progress delta was too small to verify the card value. Other
sort order was changed to descending and restored to ascending successfully. A
tvOS filter mutation was not exercised; the filter drawer is only attached to the iOS
library body. Other focus boundaries and hidden-control behavior remain unverified, and
no physical Apple TV was tested.

Phase 2 changed source and passed the signed Apple TV 4K (3rd generation) 1080p
simulator build/install. Runtime checks on the retained app session confirmed Movie and
Show Details initially focus Play; Movie watched state updates immediately and can be
reversed while its action retains focus; Show favorite state updates immediately and
reverses while its action retains focus; and Back returns to the exact originating
poster with its updated watched/favorite treatment. The Show action-to-season-selector-
to-episode path and one-layer Back behavior passed. A series-wide Mark Unwatched
invocation did not produce a visible state change during this run, so that mutation is
unverified. A brief movie playback produced an acknowledged resume value: after stop,
Details displayed `2h 15m` without reopening the route. The retained Movies poster
remained present, but the progress fraction from this short run was too small to confirm
visually on its compact indicator; retained-poster progress is therefore unverified.
No manual refresh was used, and no physical Apple TV was tested. Build/install does not
establish behavior on physical hardware.
