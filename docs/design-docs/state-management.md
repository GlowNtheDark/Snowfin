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
coalesces broad Home refreshes and honors focus coordinator deferral. Typed item updates
now requery only Home collections whose membership or ordering can change; accepted
stop reports no longer refresh every shelf. [Focus readiness](focus-system.md) remains
a separate gate.

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
  route/focus state remain locally owned. Home and tvOS Search result posters observe
  the same session's ItemState. Search query/results and its title-only suggestion array
  remain local. Episode-card metadata and routing use the local DTO, with user-data
  presentation overlaid from that session's ItemState.
- Show Details episode rows remain nested paging models. A series-level unplayed response
  contains one `UserItemDataDto` for the requested series, not descendant episode DTOs;
  current upstream Jellyfin `MarkUnplayedItem` returns that single item result
  ([controller source](https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/PlaystateController.cs#L1515-L1566)).
  The simulator server version and raw response body were not captured. A typed
  reconciliation request therefore queries the IDs already present in selected or
  previously loaded season rows. Only returned child user data is published as typed
  item updates; the season collections are not refetched or recreated. The separate
  itemShouldRefreshMetadata notification and row-revision repair have been removed. The
  season selector itself displays titles only. The separate Seasons poster group displays
  the season DTO's server userData through the existing poster indicators; it does not
  recompute season aggregates from episodes. Loaded season IDs are included in the same
  authoritative reconciliation query.
- `ContentGroupViewModel` listens for Home and Search collection-impacting item updates
  and metadata refresh signals. It targets only affected collection groups for watched
  state, Continue membership, and Search filter/sort results; Home deletion remains
  targeted too. Focus coordination defers Home's targeted queries while Details owns
  the Home return. Home global refresh remains broad. The Continue row and Play Next
  overlay keep separate list models and re-run their own derivation/query paths.
- Retained tvOS Movies and TV Shows libraries use `PagingLibraryViewModel` automatic
  refresh for metadata, stop, delete, user-data, global-refresh, and connection-change
  signals. They coalesce collection queries and keep matching user-data changes
  immediate. The shared poster path now covers those grids, and Movie/top-level Show
  Details also observe the same item state. Home and Search posters and episode cards
  overlay same-session shared user data.
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
the acknowledged ticks. The old `itemShouldRefreshMetadata` user-data repair signal was
removed after episode cards adopted the shared store and series descendants gained an
authoritative ID query. `didSendStopReport`, metadata, and library membership hooks remain
for their other consumers. Home and Search consume same-session typed updates through
shared poster presentation and collection-specific invalidation. Episode-card user data
is session-shared; metadata remains in each episode DTO.

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

### Incremental migration and remaining scope

1. **Completed: shared poster/tile path in Movies and TV Shows.** The library snapshots
   seed the session-scoped state, and the retained Movies and TV Shows grids observe it.
   Collection ownership and filter-driven invalidation remain local. Home and Search
   result posters use the same shared state.
2. **Completed: Movie and top-level TV Show Details.** The provider keeps full-item
   metadata locally and overlays same-session shared user data for the Details item and
   selected play target. Server-accepted watched/favorite changes publish typed updates;
   the Details view and retained Movies/TV Shows cards observe the same item state. The
   playback-stop full-item fetch remains for authoritative metadata and playback-provider
   refresh. Details action callbacks no longer
   mutate a private user-data copy; successful server responses publish the shared update.
   Full snapshots seed user data only while an item's typed-update revision is still zero;
   later snapshots refresh metadata without overwriting accepted watched/favorite/progress
   state. Superseded fetch generations are discarded. Details routes, groups, and focus
   ownership remain local.
3. **Completed: Show Details episode rows (Phase 3).** On tvOS, loaded episode cards
   observe the session's ItemState while retaining their full server metadata DTO for
   labels, images, routing, and actions. Episode pages seed state from the server only
   before a newer typed update exists; later user-data snapshots are overlaid from the
   canonical state. After a server-accepted series-level unplayed mutation, the Show
   Details owner queries exact IDs in loaded season rows and publishes only the returned
   child user data. Loaded season IDs are queried as well, so the season poster group
   receives server-backed user data without a client-side aggregate. This avoids season
   collection refetches and episode-row identity changes. Session IDs gate both the
   reconciliation trigger and response; request-start revisions let a later progress
   or mutation update win. Runtime checks on the Apple TV 4K (3rd generation) 1080p
   simulator loaded two Arcane seasons. An individual episode Played action appeared on
   the loaded card after returning from Episode Details; a later series Mark Unwatched
   cleared that marker in place while the action stayed focused. Playback stop showed
   acknowledged progress on the same loaded episode card without reopening Show Details;
   after starting playback from the episode artwork, Back restored focus to that exact
   episode's metadata while its progress indicator remained visible.
   An explicit near-end Play Next transition marked the finished episode watched in
   place, advanced Continue to the next episode, and a subsequent series Mark Unwatched
   cleared the completed marker. After that reset, Arcane was absent from the Home
   Continue row through its rightmost focused card. The exact before/after response DTOs
   were not captured, and no clear season-level aggregate indicator was visible at
   runtime; source inspection confirms season indicators use server-provided Season DTO
   user data and do not locally aggregate episode state. No physical Apple TV was tested.
4. **Implemented: Home and Continue (Phase 4; runtime verification incomplete).** The tvOS
   Home poster path observes session-scoped ItemState while retaining each library DTO
   and row identity. Continue, Recently Played, and deleted-item membership changes
   requery only affected Home collections. Focus deferral remains in ContentGroupViewModel.
5. **Completed: Search result cards (Phase 5; simulator validation partial).** Search
   cards observe session-scoped `ItemState`; query text, suggestions, result-group
   membership/order, paging, loading/error state, and focus remain Search-owned. Search
   targets result groups whose active played/favorite traits or user-data sorts can
   change membership/order. Presentation-only updates do not reload Search. Simulator
   checks passed for focus movement and the Details return path; the same Arcane result
   returned focused with its updated favorite badge. Playback progress has no clean
   before/after card result yet, and request-error behavior remains source-reviewed but
   runtime-unverified. Suggestions remain a title-only local DTO array.

The planned shared presentation migration is complete for tvOS Home, Movies, TV Shows,
Search result cards, Details, and loaded episode cards. This is not a process-wide DTO
cache. Generic tvOS Media library and nested `ItemLibrary` routes whose
`PagingLibraryView` has not opted into `ItemState` still render user-data indicators from
page DTOs. The file-backed Top Shelf snapshot remains a separate Home-derived
projection. Search suggestions remain local but show titles only. iOS presentation
paths remain unchanged and outside this migration.

### Home and Search presentation adoption and collection invalidation

`ContentGroupView` supplies the current session's store to the tvOS Home tree, and
`SearchView` supplies it to Search result groups. `PosterHStack` uses the item-state
poster wrapper whenever that store is present, including Search cards. The wrapper
applies canonical user data to the same `BaseItemDto` metadata snapshot; card IDs,
actions, row order, and focus registrations stay owned by their existing views and
models.

| Surface | Disposition | Collection responsibility |
| --- | --- | --- |
| Continue / Cinematic Selection | Migrated | `ResumeItemsLibrary` still fetches Resume, Next Up, and recent completion data, deduplicates by series, and sorts by activity. A new positive progress value can add an unloaded item; clearing progress can remove a loaded item; watched state, accepted stop, and server-derived ordering changes target this row. Repeated positive progress refreshes are limited to one query per 30 seconds. |
| Recently Added Movies and Shows | Migrated | `dateCreated` query and ordering stay local; user-data changes patch presentation without a collection query. |
| Recently Played | Migrated | Existing `ItemLibrary` played filter and `datePlayed` ordering decide when watched/stop updates require a targeted query. |
| On Now / Recommended Programs | Migrated | Server airing membership remains local; item user-data updates do not requery the row. |
| Latest in each library | Migrated | Premiere/date-created server ordering remains local; user-data updates do not requery the row. |
| Search result groups | Migrated | Search owns query membership, order, paging, and group identity. Active user-data traits/sorts trigger targeted group refreshes; presentation-only updates use `ItemState` without a query. |
| Search suggestions | Local title DTOs | Suggestions are separate from result cards and display only titles; no user-data-derived presentation is shown. |

`ItemUpdate.CollectionImpact` marks watched/membership mutations separately from
presentation-only favorite and progress patches. Progress updates still pass through
Continue's local membership check: a positive tick value targets the Resume query only
when the item is not loaded, and zero targets it only when the item is loaded. An
accepted stop always targets Continue, allowing the server to remove a completed item
or supply its next episode. Other Home `ItemLibrary` rows retain their own filter/sort
rules. Home deletion targets only rows that still contain the item ID.

Search has a targeted invalidation hook because an item that begins matching an active
Search trait may not already be in a loaded result page. `ItemLibrary` evaluates only the
active played/favorite filters and user-data sorts; each affected result group advances
its collection generation and refreshes independently. The Search check also re-evaluates
a favorite change marked presentation-only when a favorite filter/sort is active.
Playback-position-only updates do not query Search. Query text changes still rebuild
Search groups through the existing Search flow.

| Search refresh/update path | Phase 5 disposition | Reason |
| --- | --- | --- |
| Query or filter change | Required; retained | Search owns query semantics, membership, result order, and paging. |
| User-data update with an active matching trait/sort | Required; targeted to result groups whose active criteria can change | Membership/order may change, including a result not currently loaded. |
| User-data update with no affected trait/sort | No Search query | Visible poster appearance comes from `ItemState`. |
| Matching-ID DTO patch in `PagingLibraryViewModel` | Retained | It keeps the paging snapshot current for iOS Search and other DTO consumers; tvOS Search poster appearance reads `ItemState`. |
| Deleted result ID | Required; retained | The paging model removes the matching element directly. |
| Search suggestions | Retained | First-appearance lookup shows titles only and is separate from result presentation. |

The old Home refresh-all path for every `.userData` update and every accepted playback
stop was removed. The focus coordinator still observes stop reporting, and targeted
collection queries queue while Home refresh deferral is active. Metadata and explicit
global refresh signals remain broad because they can affect metadata or collection
results across multiple rows. A targeted result resolves row visibility through the
existing candidate-group order; no provider rebuild or row reorder is added.

The Home `PagingLibraryViewModel` advances its collection generation on a relevant
membership/order update and again before a targeted query, rejecting snapshots started
before that change. Each poster observes the session's weakly retained `ItemState`,
whose per-item revisions, partial-field merge, session ID, and 512-entry replay bound
are unchanged. Thus an older query can update metadata and membership only when its
generation is current; the poster overlays newer canonical user data either way.

The signed tvOS simulator build/install passed and retained the app-group container. A
post-launch screenshot showed the Continue row with its first card focused, followed by
Recently Added Movies. This confirms visible Home startup and initial focus only. Remote
interaction was unavailable in the current simulator host, so progress entry/change,
completion/Next Up, series-wide Mark Unwatched, presentation-only update, shelf movement,
Details/player return, active membership refresh focus, one-layer Back, and absence of a
corrective focus jump remain runtime `UNVERIFIED`. No physical Apple TV was used.

After each owner is migrated, the following local repairs can be retired where the
store/event path provides equivalent behavior:

- series `itemShouldRefreshMetadata` notification and loaded-season collection refresh
  after a series-level unplayed mutation (removed in Phase 3; replaced by exact-ID child
  user-data reconciliation);
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
