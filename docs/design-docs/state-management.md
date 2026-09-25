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
fetches the full item and resolves a playback provider. Its watched toggle updates
optimistically, rolls back on error, and publishes the server response through
[`Notifications`](../../Shared/Services/Notifications.swift).
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
coalesces Home refreshes and honors focus coordinator deferral. Acknowledged progress/
stop notifications drive refresh; [focus readiness](focus-system.md) is a separate gate.

Queries are bounded by page limits; this is not an exhaustive local watch-history
index. Missing IDs/dates can affect deduplication and ordering. Inspect actual payloads
before diagnosing a report. The [product contract](../product-specs/continue-watching.md)
describes the intended result; these query details describe the current mechanism.

## TV Shows session loading

Only the retained tvOS TV Shows tab opts into `PagingLibraryViewModel` automatic
refresh. Its first active-scene appearance starts the existing model's initial
load, without requiring tab selection. A successful response, including an empty
one, marks initial loading complete. Subsequent refreshes replace the collection
in the background; existing content stays visible during requests and failures.

A 60-second timer checks a five-minute freshness window while the scene is active.
Scene activation and tab entry also check freshness. Item user-data, metadata,
delete, accepted playback-stop, global-refresh, and connection-change signals
invalidate the collection. A single worker batches signals for 350 ms and drains
one pending refresh at a time; signals during a request require a follow-up.
Filter/sort changes use that same worker. Query and collection generations reject
obsolete responses before publication, including snapshots predating user-data
changes/deletions. Existing matching-ID updates remain immediate. Search keeps its
own paging state and rejects results from an obsolete filter/sort environment.

This adds no item database/cache or separate preloader. The tradeoff is retaining
one full TV series collection and grid, plus moving its initial item/filter requests
into signed-in startup. In-flight work may finish when the scene becomes inactive;
new automatic requests wait until activation. Initial failures remain retryable by
the freshness checks. Movies, Home, and iOS do not enable this policy.
