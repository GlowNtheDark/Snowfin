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
