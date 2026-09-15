# Playback

Status: explicit dismissal direction and existing playback capabilities.

Start the selected item with the chosen source and available resume position, or
from zero when explicitly requested. Preserve existing pause, seek, stream settings,
queue, and error handling unless the task changes them.

Dismissal returns to the launching screen under the [navigation contract](navigation.md).
Stopping playback does not itself authorize a Home navigation reset. Preserve genuine
direct-play origins as well as details-origin playback.

Report progress/stop state to Jellyfin and use returned user data for watched state;
a high local percentage is not the definition of watched. The
[Play Next contract](play-next.md) governs the near-end experience. Natural-end
queue autoplay and credits-driven transitions are distinct paths today.

The app has custom VLC and native AVPlayer presentation paths. Do not assume feature
parity or identical dismissal mechanics; see [lifecycle and limits](../design-docs/playback-lifecycle.md).
