# Navigation contract

Status: explicit product direction.

```text
Home → Show Details (tvOS Home episode entry) / Episode Details (iOS) → Play
Back/Escape from player → same Details route
Back/Escape from Details → Home → originating tile focus restored
```

Keep the existing hierarchy and details context. Player dismissal and Home focus
restoration are separate events. Never collapse intermediate screens just to obtain
Home focus. Home restoration starts only when navigation actually returns to Home.

On tvOS, selecting an episode from Home opens its owning Show Details. The route selects
the episode's season and gives initial focus to that episode's artwork; Select on the
artwork starts playback. Opening Show Details does not start playback. If the requested
season is unavailable, use a verified alternate season when possible and otherwise the
first available season. If the episode is absent from the loaded season, focus its first
eligible episode; if the show has no playable episodes, use Show Details' stable entry
target. Other tvOS episode entry points outside this migration keep their existing
routes, and selections whose owner cannot be resolved retain their existing fallback
routing. A resolvable episode selected from Search or a library opens the owning Show
Details with its season selected and its artwork focused; Select on that artwork starts
playback. Search retains its query, result-group identity, result membership, and scroll
position while Details is presented. Dismissing Details restores the exact Search result
when it remains available, or the Search field when the query, group, or item is no
longer valid. Libraries retain tab, library, item, and collection position; dismissal
restores the exact item when available, otherwise the nearest item in the same library
by its original index (lower index wins a tie), then that library's first item. Keep the
current scroll position when the target is already visible and reveal it only when it is
offscreen.

Preserve genuine direct-play-from-Home flows: those return directly to Home.
Determine the actual playback origin rather than assuming every player came from Home.
“Direct” means Home is the player's immediate presenting context, with no details
screen between them; originally selecting a Home tile does not make later playback direct.
This exception preserves existing flows and does not authorize adding a details bypass.
Other navigation should likewise return through the screen that launched it.

See [Episode Details](episode-details.md), [focus restoration](focus-restoration.md),
and [navigation implementation](../design-docs/navigation-stack.md).

## Search, TV Shows, and Movies tab lifetime

Within a signed-in tvOS session, Search, TV Shows, and Movies preload and retain their
content across tab changes. Search keeps its query, result groups, and scroll position,
and re-entry targets its Search field. TV Shows and Movies retain their browsing state.
Refreshes preserve the last loaded collection until its replacement is available,
including a genuinely empty replacement. Inactive retained tabs must not take focus, accept input, appear in
accessibility, or present routes. Right/Select enters Search at its field or a library
at its first item. See the
[tab lifetime implementation](../design-docs/navigation-stack.md#retained-search-tv-shows-and-movies-tabs).
