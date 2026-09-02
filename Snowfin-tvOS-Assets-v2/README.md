# Snowfin tvOS Artwork v2

This revision specifically fixes the simulator issues seen in the first pack:

- The tvOS foreground mark now has generous transparent safe-area padding so parallax/cropping does not cut it off.
- The icon background is atmosphere-only and no longer places a mountain outline through the foreground mark.
- Top Shelf branding is fully inset from the left/top/bottom crop zones.
- Mountain artwork is pushed to the right side, leaving a clean dark region behind the Snowfin wordmark.
- No tvOS/Apple logos are baked into the Top Shelf art.

Replace the same existing asset slots used for v1, preserving Contents.json and asset names.

Recommended Codex prompt:

> Replace the currently installed Snowfin tvOS icon and Top Shelf artwork with the files in `Snowfin-tvOS-Assets-v2/`. Preserve the existing asset catalog names and Contents.json metadata. Replace only the matching tvOS artwork files; do not change code, iOS assets, schemes, targets, bundle IDs, or Snowfin playback functionality. Build the `Swiftfin tvOS` target afterward and report asset-catalog errors/warnings. Do not regenerate or modify the supplied artwork.

Test the home-screen icon and Top Shelf in the tvOS simulator before committing.
