# Play Next

Status: explicit product direction; implementation partially establishes the experience.

Near episode end, Screen should transition visually into a Plex-like intermediary
next-episode experience containing:

- the current episode;
- the next episode;
- the countdown;
- Continue Watching content.

The direction is richer than a single overlaid button. Preserve user choice to start
the next episode or keep watching, and respect configured credits/autoplay behavior.
Do not replace this direction with the older single-button experience.

## Current implementation vs intent

The custom TV player currently renders all four content areas in a large overlay
inside the existing player. It is not a separately routed screen. The coordinator
supports credits modes (off, show next, countdown, immediate autoplay), so the
countdown is conditional. This is progress toward the intended intermediary
experience, not evidence of final product acceptance.

Whether its visual transition fully meets the intended screen experience needs
human/runtime review. The native AVPlayer view does not attach this custom overlay.
This bootstrap changes neither implementation nor watched/completion semantics.
See [playback lifecycle](../design-docs/playback-lifecycle.md) and
[review findings](../exec-plans/tech-debt.md).
