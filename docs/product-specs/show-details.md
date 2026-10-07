# TV Show Details

TV Show Details keeps the selected show's metadata and existing route context. The
tvOS page omits the Trailer action and the Genres and Studios sections. Season
selection and episode browsing remain available.

Top-level tvOS TV Show Details includes one labeled **Mark as unwatched** action in
the existing action row. Selecting it performs a full viewing-state reset for the
series: every episode in every season becomes unwatched and every episode's saved
playback position is cleared, including partially watched episodes. No episode
retains resume progress from before the reset. Jellyfin derives season and series
watched state from their child episodes, so their aggregate state updates with the
episode states. Episodes in Home's Continue Watching row only because of saved
progress from this series leave that row after the successful reset. Show Details,
season and episode markers, and affected library/Home rows refresh promptly in
place while keeping focus on a valid target and without adding a navigation layer.

This reset uses Jellyfin's established unplayed semantics: marking a folder
unplayed recursively updates its leaf episodes, and resetting an episode clears its
played flag, play count, last-played date, and resume position.

These omissions apply to top-level tvOS TV Show Details only. Movie Details keeps its
existing content, and the shared iOS Details experience keeps its existing content.
Other show metadata, actions, and configured content groups remain governed by their
current behavior.

The page uses the shared Details route hierarchy. Nested content and playback return
through that hierarchy; see the [navigation contract](navigation.md) and the
[app-wide focus contract](../design-docs/focus-navigation-contract.md#details-screens-and-nested-shelves).
