# Continue Watching

Status: behavior supported by current TV derivation and established Home direction.

- Resume partially watched episodes before suggesting another episode of the same series.
- Present at most one entry per identifiable series.
- Offer an eligible next episode after recent completed-series activity.
- Keep movie resume behavior and interleave movie/TV entries in one recency order;
  do not group all TV series first.
- Watched means Jellyfin `userData.isPlayed`, not a threshold on local progress.

“Partial first” is a per-series selection rule, not a separate TV-first shelf order.
The current recent-completion window is 14 days; that is an implementation parameter,
not a new permanent product promise. Entries may change following acknowledged
playback reports or user-data updates.

Home and the custom Play Next experience derive content through `ResumeItemsLibrary`;
Top Shelf receives a saved Home snapshot. Selection/refresh details and server-data
boundaries are in [state management](../design-docs/state-management.md). Returning
focus after an entry is replaced follows [focus restoration](focus-restoration.md).
