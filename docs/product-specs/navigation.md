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
target. Other tvOS episode entry points and unresolved ownership retain their existing
Episode Details routes until migrated.

Preserve genuine direct-play-from-Home flows: those return directly to Home.
Determine the actual playback origin rather than assuming every player came from Home.
“Direct” means Home is the player's immediate presenting context, with no details
screen between them; originally selecting a Home tile does not make later playback direct.
This exception preserves existing flows and does not authorize adding a details bypass.
Other navigation should likewise return through the screen that launched it.

See [Episode Details](episode-details.md), [focus restoration](focus-restoration.md),
and [navigation implementation](../design-docs/navigation-stack.md).

## TV Shows tab lifetime

Within a signed-in tvOS session, TV Shows preloads and retains its content and
browsing state across tab changes. Refreshes preserve the last loaded collection
until its replacement is available, including a genuinely empty replacement.
Inactive TV Shows must not take focus, accept input, appear in accessibility, or
present routes. Right/Select retains the existing explicit entry-to-first-item
behavior. See the [tab lifetime implementation](../design-docs/navigation-stack.md#retained-tv-shows-tab).
