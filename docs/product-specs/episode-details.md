# Episode Details

Status: explicit navigation direction, with actions supported by the existing details UI.

Episode Details preserves the selected episode's identity, metadata, watched state,
and playback actions. Play resumes from available progress; Play From Beginning
starts at zero. Keep selected media-source context where supported.

Launching playback leaves this details instance underneath the player. Returning
from playback must show that same context; a subsequent Back returns through the
existing hierarchy. Follow the [navigation contract](navigation.md), including
Home focus only after Home is reached.

Watched state is server-backed and separate from playback position. Refreshing data
must not require reconstructing the navigation stack. Episode Details uses the shared
item-details implementation rather than a dedicated episode screen type; mechanics
are in [state management](../design-docs/state-management.md) and
[playback lifecycle](../design-docs/playback-lifecycle.md).

On tvOS, when the parent button is used for a verified episode with a resolvable owning
series, it opens that Show Details route with the originating episode artwork focused.
This does not start playback. If the owner cannot be verified, retain the existing
error fallback. Episode-card metadata actions remain a deliberate way to open Episode
Details and are not converted to Show Details routing. Deep links without a parent route
do not invent a focus-restoration origin; see the [navigation contract](navigation.md).
