# Deferred findings and review needs

Observed during documentation bootstrap, 2026-09-14. No runtime bugs are asserted
by this list, and no production fixes were attempted. Add only evidence-backed
findings; plan conventions are in [CODEX_WORKFLOW.md](../CODEX_WORKFLOW.md).

| Finding | Evidence and impact | Next useful check |
| --- | --- | --- |
| Play Next product acceptance/backend scope | [Custom overlay](../../Shared/Snowfin/PlaybackSegments/SnowfinPlaybackSegmentOverlay.swift) contains the requested four areas inside the player; [native player](../../Shared/Components/NativeVideoPlayer.swift) does not attach it. The [product direction](../product-specs/play-next.md) asks for an intermediary screen experience. | Review the custom transition on Apple TV and decide whether it meets that direction; clarify native-player coverage before a future implementation task. |
| Existing docs differ from local Screen state | [Contribution guide](../../Documentation/contributing.md) says there are no UI guidelines and requires both platform builds upstream; [roadmap](../../Documentation/Snowfin-UI-Roadmap.md) establishes local design rules; [CI](../../.github/workflows/ci.yml) runs TV only. The roadmap still lists dynamic Top Shelf work although writer/extension code exists. | Retain upstream context; use the new Screen map for local guidance. Refresh historical phase status only with runtime/product evidence. |
| Current navigation/focus changes lack bootstrap runtime evidence | Pre-existing uncommitted changes in `MainTabView`, `FocusCoordinator`, and player/content files were included in the source trace. The [design docs](../design-docs/navigation-stack.md) describe those current mechanisms, not a validated release. | Exercise Home → Episode Details → Play → Back → same Details → Back → Home, with refreshed/replaced tiles and any affected direct-play flow, when validating that work. |
