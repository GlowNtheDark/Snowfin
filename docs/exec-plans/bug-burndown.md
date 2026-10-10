# Screen bug-burn-down register

Audit date: 2026-10-10
Scope: A01/A02 shared playback Back-path fix, B01 sidebar-return fix, and focused simulator acceptance; other register entries retain their prior evidence.
Original audit baseline: `8da2e06b1935bb7fa86b2b08a0705acf6d1dea2f` on `codex/phase1-shared-item-state`. B01 follow-up started from `aba7494196f8be6dba4a32542d3b00b4fc609776` on the same branch; the B01 remediation changes in this working tree are uncommitted.
Runtime target: Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator. No physical Apple TV was used.

## Executive summary

The 26 initial register items were reviewed: **1 confirmed open bug**, **11 runtime passes**, **8 source-verified cases with runtime coverage still incomplete**, **1 previously reported issue not reproduced**, **5 unverified cases**, and **0 blocked cases**. No P0 was found. The remaining confirmed bug is P1: Up Episodes can reopen with the season selector focused after a cross-season change. A01, A02, and B01 pass their focused simulator acceptance paths; B01's pre-fix reproduction and corrected return paths are recorded below.

**A01/A02 remediation:** both failures shared the outer Menu/Back delivery path, while the coordinator's Intro and credits transitions remain distinct. The corrected simulator runs confirm a single Back press is consumed by the active segment layer; details are recorded below.

HUD metadata root cause and current behavior: `HUDMetadata` receives the current `MediaPlayerManager.item`. Jellyfin's episode `name` is already available there. Before the fix, the HUD bottom line selected `BaseItemDto.episodeLocator` instead of the DTO's `displayTitle`/`name`; `episodeLocator` locally formats `indexNumber` as `Episode N`. `seasonEpisodeLabel` separately supplies `Sx:Ey`. No additional metadata request was needed. The current HUD title selection trims `item.name`, rejects blank text and the locally synthesized locator, then uses the localized locator as fallback; the top series line and `Sx:Ey` are retained. Both metadata lines are single-line. See [HUDMetadata](<../../Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+HUD.swift:19>) and [episode labels](<../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift:34>).

Current evidence does **not** establish a known-bug-free baseline. Membership/focus behavior, a controlled Search request failure, EPG geometry, and several boundaries still need the checks below. The A01/A02 remediation was signed-built and installed on the specified simulator; the temporary credits setting was restored to Show Next Episode with its original 10-second duration.

### Classification counts

| Status | Count | IDs |
| --- | ---: | --- |
| CONFIRMED BUG | 1 | A03 |
| PASS | 11 | A01, A02, A04, A05, B01, C02, D01, D03, E03, F01, F03 |
| SOURCE VERIFIED | 8 | B02-B07, E02, F02 |
| NOT REPRODUCED | 1 | C01 |
| UNVERIFIED | 5 | B08, D02, E01, F04, F05 |
| BLOCKED | 0 | — |

Severity describes the impact if a behavior regresses, not its current status. Across the 26 items: **15 P1, 10 P2, 1 P3, 0 P0**. Confirmed open bugs: **2 P1**.

## Confirmed open bugs

### A03 — Up Episodes can reopen focused on the season selector

- **Subsystem / severity / status:** Playback Episodes focus restoration; P1; **CONFIRMED BUG**.
- **Reproduction:** On the 2026-09-28 simulator run, select S2:E1 from Season 2, close Episodes, then reopen it and press Right once.
- **Expected:** Reopening selects the current playing season and focuses the current episode card (S2:E1); Right then advances within that episode shelf.
- **Observed / evidence:** Right changed the selected shelf to Season 3, proving focus had returned to the Season 2 selector rather than the S2:E1 card. The initial S3:E10 open before cross-season selection did focus the current episode correctly, so the failure is path-dependent. Two narrow focus passes did not make the return reliable. During this audit, a no-season-change reopen correctly focused the current S3:E10 card; that does not cover the failing path.
- **References:** [tech-debt evidence](tech-debt.md#deferred-findings-and-review-needs), [Episodes contract](../design-docs/focus-navigation-contract.md#up-episodes-surface), lines 466-480, and [playback focus notes](../design-docs/focus-system.md).
- **Dependencies / blocker:** Focus candidate timing during cross-season player-item replacement; current candidate registration must precede the focus request.
- **Next action:** Trace `focusedTarget`, shelf candidate registration, and focus-update ordering immediately after cross-season selection. Retest with S2:E1 and an episode in a second season; do not add a delay-based correction.

### B01 — Sidebar return restores the remembered Home tile

- **Subsystem / severity / status:** Home/sidebar focus acquisition; P1; **PASS**.
- **Original reproduction / pre-fix evidence:** Focus the first tile in Home's Recently Added TV Shows row (The Secret Lives of Mormon Wives), press Left to enter the Home sidebar, then press Right once. The pre-fix simulator returned to Continue Watching S3:E10 instead of the remembered tile, reproducing the earlier sidebar-entry timing report.
- **Expected:** Sidebar return restores the last valid Home tile, reveals it if its shelf is horizontally scrolled, preserves initial Home launch focus, and performs one transition without a delayed corrective jump.
- **Corrected runtime evidence:** On the Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, the original Left/Right path restored The Secret Lives of Mormon Wives. Repeating the return with Select also restored it. Returning from Circle in Recently Added Movies restored Circle; returning from Coyote vs. Acme with the Movies shelf horizontally scrolled restored that exact tile and kept the scroll offset. After sidebar return, Up to Circle then Down restored the exact Secret Lives tile. Opening the series Details from that tile and pressing Back returned to it. Initial Home entry focused Futurama, the first Continue Watching candidate. Each sampled press produced one visible transition, and no later first-tile jump was observed.
- **Root cause / fix:** `FocusCoordinator` kept only the currently focused Home tile, which was cleared as focus moved to the sidebar. The root-tab repeat path then requested the first Home group, while each row's high-priority `defaultFocus` could reacquire its first poster after restoration. Home now retains the last semantic tile, resolves exact item then nearest same-row then first available fallback, reveals the target row/cell, and waits for the sidebar to relinquish focus before requesting it. The exact-target path skips the competing generic root request, invalidates stale focus requests, and keeps row default focus suppressed after the remembered tile is acquired. Initial Home entry still uses its original first-candidate request.
- **References:** [Home focus ownership](<../../Shared/Objects/FocusCoordinator.swift:32>), [sidebar activation](<../../Shared/Coordinators/Tabs/MainTabView.swift:135>), [Home initial/root focus](<../../Shared/Views/ContentGroupView.swift:61>), [row default focus](<../../Shared/Components/PosterHStackLibrarySection.swift:87>), [focus contract](../design-docs/focus-navigation-contract.md#root-and-launch), lines 145-156 and 547.
- **Dependencies / blocker:** No blocker for the verified simulator paths. Physical Apple TV behavior was not tested, as requested.
- **Next action:** Keep B01 in the sidebar/Home regression checklist; include Right and Select, an offscreen shelf target, Home vertical reverse, and Details return after future focus changes.

## Previously reported bugs not reproduced

### C01 — Video Player Type menu loses its row focus after Back

- **Subsystem / severity / status:** Settings/native menu focus; P1; **NOT REPRODUCED**.
- **Reproduction:** In Settings, focus Video Player Type, Select to open its Native/Screen menu, press Back, inspect the invoking row, then Select once.
- **Expected:** Back dismisses only the menu, the original row is visibly focused, and one Select immediately reopens the menu.
- **Observed / evidence:** In this audit, Back closed the native menu with Video Player Type visibly highlighted. One Select immediately reopened it with Native focused and Screen still selected. No delayed corrective jump was observed.
- **References:** [ListRowMenu](<../../Swiftfin tvOS/Components/ListRowMenu.swift:86>), [focus contract Settings row](../design-docs/focus-navigation-contract.md#settings-root-and-nested-settings), lines 271-281.
- **Dependencies / blocker:** tvOS 27.0 simulator only; native form behavior may vary by OS/device.
- **Next action:** Retain as not reproduced, not fixed. Repeat on physical Apple TV when testing a Settings/menu change.

## Runtime passes

### A01 — Intro overlay Back dismisses only the prompt

- **Subsystem / severity / status:** Playback Back ownership; P1; **PASS**.
- **Reproduction:** On the corrected build, play Futurama S10:E4, “The Numberland Gap”, wait for its active Skip Intro prompt, confirm the action is available, then press Back once.
- **Expected:** Dismiss only the Intro prompt, keep the same playback active, and do not seek.
- **Observed / evidence:** The prompt disappeared and the same player returned to its HUD over the continuing episode at about 0:23. The player did not exit or jump to the intro boundary. A later Skip Intro Select check still sought forward and left playback running.
- **Root cause / fix:** The segment overlay was a SwiftUI sibling outside the UIKit player container, so the focused overlay's Menu/Back could bypass the container's Menu owner and dismiss the player presentation. The presentation publisher also emits its new value before storage; the old subscriber discarded that value and reread stale `presentation`, leaving the full-screen presentation dismissible. The overlay is now hosted inside the UIKit container, Menu is consumed once there, and dismissibility uses the emitted presentation value.
- **References:** [player press ownership](<../../Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift:1003>), [segment Back transitions](<../../Shared/Snowfin/PlaybackSegments/SnowfinPlaybackSegmentCoordinator.swift:163>), [presentation dismissibility](<../../Shared/Views/VideoPlayer/VideoPlayer.swift:94>), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next).
- **Next action:** Keep A01 in the playback Back regression checklist; no additional fix remains for this register item.

### A02 — Credits countdown Back cancels before dismissing

- **Subsystem / severity / status:** Playback Back ownership; P1; **PASS**.
- **Reproduction:** Temporarily set Credits / Outro to Countdown + Autoplay, reach Futurama S10:E4's Up Next countdown, then press Back once and again.
- **Expected:** The first Back cancels only the countdown and retains both choices; a later Back dismisses the choice to the HUD without exiting playback.
- **Observed / evidence:** First Back replaced the countdown with `AUTOPLAY CANCELLED` while keeping Keep Watching and Play Next visible. Second Back dismissed that presentation and returned to the same S10:E4 HUD/video near 24:14. Neither press exited the player. The temporary setting was restored afterward.
- **Root cause / fix:** A02 shared A01's outer event-delivery and stale-presentation-dismissibility defect. The coordinator's transitions remain separate: countdown Back cancels and retains the next-episode choice; a later Back dismisses that choice. The UIKit container consumes each press before player dismissal and suppresses the paired Menu-ended phase after handling at press-began.
- **References:** [player press ownership](<../../Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift:1003>), [countdown and choice transitions](<../../Shared/Snowfin/PlaybackSegments/SnowfinPlaybackSegmentCoordinator.swift:166>), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next).
- **Next action:** Keep A02 in the playback Back regression checklist; no additional fix remains for this register item.

### A04 — Player → Details → Home exact tile restoration

- **Subsystem / severity / status:** Playback route and Home restoration; P1; **PASS**.
- **Reproduction:** From the existing Home Continue item, resume its episode, then Back through the visible HUD/player to Episode Details and Back to Home.
- **Expected:** Each Back dismisses one layer; the player returns to its Details route, then Home restores the exact originating tile.
- **Observed / evidence:** HUD/player dismissal and Details return were separate; the next Back returned Home with the same S3:E10 Continue tile visibly focused. No premature Home restoration occurred.
- **References:** [navigation contract](../product-specs/navigation.md), [player return contract](../design-docs/focus-navigation-contract.md#player-dismissal-and-return-focus), lines 525-537.
- **Dependencies / blocker:** One direct Continue-origin episode route tested; this does not cover every deeper Details/shelf route.
- **Next action:** Keep the exact Details and Home return in the navigation regression checklist.

### A05 — Movie Details Play / Replay action restoration

- **Subsystem / severity / status:** Movie Details action focus; P1; **PASS**.
- **Reproduction:** From Movie Details for the already-watched “Wuthering Heights”, start Play, Back through the player HUD to Details, then focus Replay, start it, and return the same way.
- **Expected:** Play returns with Play focused; Replay/Play From Beginning returns with that action focused. If Replay is unavailable, fall back to Play.
- **Observed / evidence:** The first Details return highlighted Play. Replay was selectable, started at 0:00, and after return the Replay action had the focus outline. Movie Details continued to show Watched. The no-Replay fallback was source-reviewed only.
- **References:** [focus contract Details actions](../design-docs/focus-navigation-contract.md#details-screens-and-nested-shelves), lines 297-313; [navigation implementation](../design-docs/navigation-stack.md).
- **Dependencies / blocker:** Fallback when Replay is unavailable was not encountered in this Movie's metadata.
- **Next action:** Preserve the return target and retain a separate regression case for the unavailable-Replay fallback.

### C02 — App Font dismissal and selection return focus

- **Subsystem / severity / status:** Settings custom menu focus; P2; **PASS**.
- **Reproduction:** Open App Font, Back; reopen and select another option; Select once to reopen.
- **Expected:** Back and selection return focus to App Font; the next Select reopens with no delayed focus jump.
- **Observed / evidence:** Both dismissal paths visibly restored App Font. One Select reopened the menu. Serif was selected temporarily and then Rounded was restored, its original value.
- **References:** [App Font row/menu](<../../Shared/Views/SettingsView/SettingsView.swift:256>), [focus contract Settings](../design-docs/focus-navigation-contract.md#settings-root-and-nested-settings), lines 273-275.
- **Dependencies / blocker:** None in this simulator scenario.
- **Next action:** Keep the immediate reopen and no-delayed-jump case in the Settings regression checklist.

### D01 — Search no-results focus stays in the input region

- **Subsystem / severity / status:** Search focus; P2; **PASS**.
- **Reproduction:** Enter a query with no matching results, focus the first on-screen key, then press Down; also test Down from the search field.
- **Expected:** With no results, focus alternates between input field and keyboard rather than entering empty result content.
- **Observed / evidence:** “No Results” was shown; Down from the first key focused the field, and Down from the field focused the first key. Left from the first key entered the sidebar once. The Device Hub keyboard capture produced `aaaaa` instead of the intended synthetic query; this was a harness input issue, not a product defect.
- **References:** [Search focus routing](<../../Shared/Views/SearchView.swift:86>), [contract Search](../design-docs/focus-navigation-contract.md#search), lines 232-249.
- **Dependencies / blocker:** No matching results were available for this query; controlled request failure is tracked separately as D02.
- **Next action:** Retain no-results input/keyboard alternation in the Search regression checklist.

### D03 — Search result Details return and favorite update

- **Subsystem / severity / status:** Search result focus/state; P1; **PASS**.
- **Reproduction:** Use the existing 2026-10-08 simulator evidence: open an Arcane Search result's Details, change Favorite, return with Back.
- **Expected:** One Back returns to the same Search result, and accepted watched/favorite presentation updates are visible without reopening Search.
- **Observed / evidence:** The same Arcane result returned focused with its updated favorite badge. The audit did not repeat this mutation. Search retains local query/results while result cards observe shared item state.
- **References:** [state-management runtime evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 318-326; [Search focus contract](../design-docs/focus-navigation-contract.md#search), lines 237-249.
- **Dependencies / blocker:** Recent simulator evidence covers Favorite; a Search-specific watched mutation was not separately captured.
- **Next action:** Keep exact result and favorite update in the Search regression checklist; add watched-state coverage when a safe test item is available.

### E03 — Episode title, locator, series, fallback, and Movie HUD

- **Subsystem / severity / status:** Playback HUD metadata; P2; **PASS**.
- **Reproduction:** Resume The Secret Lives of Mormon Wives S3:E10 and show the HUD; separately start the Movie “Wuthering Heights”.
- **Expected:** Episode HUD shows S3:E10, series title, and Jellyfin episode title. `Episode N` is fallback only. Movie metadata remains unchanged.
- **Observed / evidence:** The episode HUD showed `S3:E10`, `The Secret Lives of Mormon Wives`, and `The Book of Enlightenment`; no generic `Episode 10` appeared. That title fit on one line at 1080p without colliding with controls/progress/timestamps. Movie playback showed only `"Wuthering Heights"` with its time/progress display and no episode locator. The missing/blank-title fallback is source-reviewed, not runtime-fed.
- **References:** [HUD title selection](<../../Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+HUD.swift:19>), [localized fallback and Sx:Ey](<../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift:134>), [metadata state ownership](../design-docs/state-management.md).
- **Dependencies / blocker:** Simulator had no blank-title episode. Only the observed title length was visually measured; no additional long-title sample was needed for the audit matrix.
- **Next action:** Retain this episode and Movie pair as a regression check. If a blank-title episode becomes available, verify localized fallback runtime.

### F01 — Representative exact restoration through Home, libraries, and Search

- **Subsystem / severity / status:** Route/focus restoration; P1; **PASS**.
- **Reproduction:** Use the 2026-10-08 signed simulator checks for Movies poster → Details → Back, TV Shows poster → Details → Back, and Search result → Details → Back; Home direct-to-Details route was also exercised in this audit.
- **Expected:** One Back dismisses the child and returns focus to the exact originating item in its still-visible parent.
- **Observed / evidence:** Movies, TV Shows, Search, and the current Home Continue route returned to their exact originating item in one route-level Back. The current episode player first hid its HUD, then returned to Details, then Home and its original Continue item.
- **References:** [state-management runtime evidence](../design-docs/state-management.md), lines 418-425; [navigation contract](../product-specs/navigation.md).
- **Dependencies / blocker:** Prior evidence is from the installed simulator app; not every nested shelf/action route was included.
- **Next action:** Keep representative exact-return flows in navigation regression checks; treat B01's sidebar entry separately.

### F03 — Representative remote presses produce one transition

- **Subsystem / severity / status:** tvOS remote navigation; P1; **PASS**.
- **Reproduction:** During this audit, test Home row Down/Up and Left/Right, Search no-results Down, Settings menu Select/Back, Episodes open/Back, and player/Details/Home Back one press at a time.
- **Expected:** One remote press produces at most one region/route transition and no delayed corrective jump.
- **Observed / evidence:** The sampled presses produced one visible transition each. Immediate App Font reopen worked. The pre-fix Home Right result was one transition to the wrong tile (B01); the B01 follow-up restored exact targets through Right and Select without a delayed jump. This sample is not a claim that every app boundary was tested.
- **References:** [one-press contract](../design-docs/focus-navigation-contract.md#root-and-launch), lines 145-156 and 558-568; [Home vertical focus](../design-docs/focus-navigation-contract.md#home-and-shelves).
- **Dependencies / blocker:** Covers representative simulator paths only; hardware input remains untested.
- **Next action:** Recheck one-press ownership alongside each confirmed fix; do not infer full navigation coverage from this sample.

## Source-verified; runtime verification remains incomplete

### B02 — Focused Home tile updates live

- **Subsystem / severity / status:** Home shared item state; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; required runtime path is to keep a Home tile focused while accepted watched, favorite, or playback progress changes.
- **Expected:** Presentation updates in place, preserving tile identity and focus without a corrective jump.
- **Observed / evidence:** Source sends accepted item updates through session-scoped `ItemState`; poster/tile presentation observes that state while collection identity stays local. Recent runtime showed other Details/episode card updates, not this exact focused Home tile case.
- **References:** [state-management ownership and migration](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 138-165 and 260-288.
- **Dependencies / blocker:** Requires a safe item with known starting state and a server-accepted watched/favorite/progress update.
- **Next action:** Runtime-test one reversible Favorite update and one progress update while the same Home tile remains focused; restore Favorite afterward.

### B03 — Focused Continue item disappears and receives fallback focus

- **Subsystem / severity / status:** Home focus fallback; P1; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; remove a currently focused Continue item through completion or a membership change.
- **Expected:** Focus resolves deterministically to the nearest valid tile in the original row, then the row's first tile, then the first valid Home tile.
- **Observed / evidence:** `FocusCoordinator.resolveHomeReturn` implements exact item → same-series replacement → nearest original-row tile → first available Home tile. Runtime membership disappearance/fallback was not tested.
- **References:** [focus fallback](<../../Shared/Objects/FocusCoordinator.swift:326>), [state-management Home invalidation](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 179-186.
- **Dependencies / blocker:** Requires a safe Continue item and a removable membership change; no blocker prevents a controlled future test.
- **Next action:** Verify the fallback chain with test content, including when the exact item and then its row are absent.

### B04 — New Continue item appears after resume threshold

- **Subsystem / severity / status:** Continue membership refresh; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; start an item absent from Continue Watching and report progress past Jellyfin's resume threshold.
- **Expected:** Home re-queries affected Continue membership without manual refresh and adds the item in the right order.
- **Observed / evidence:** `ResumeItemsLibrary` requests membership refresh when positive playback ticks arrive for an item not already present; acknowledged updates carry item identity/revision and Home refresh is targeted. No absent-item threshold transition was tested.
- **References:** [ResumeItemsLibrary membership decision](<../../Shared/Objects/Libraries/ResumeItemsLibrary.swift:51>), [state-management Continue rules](../design-docs/state-management.md#continue-watching-and-refresh), lines 39-61 and 149-155.
- **Dependencies / blocker:** Requires a safe item absent from Home Continue and a server resume threshold; restore/clear the resulting progress where practical.
- **Next action:** Record the item's pre-test membership and position, cross the server threshold, verify Home ordering, then restore the starting position/state.

### B05 — Existing Continue progress updates while its tile stays onscreen

- **Subsystem / severity / status:** Continue presentation state; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; leave an existing Continue tile onscreen and focused while acknowledged progress changes.
- **Expected:** Its label/bar update without hover, click, navigation, or manual refresh; focus identity remains stable.
- **Observed / evidence:** Typed progress ticks patch the same session item state and tvOS poster/card reads that state. Home progress presentation without an actual playback update is not proof of live refresh.
- **References:** [ItemState update](<../../Shared/Objects/ItemState.swift:34>), [PagingLibraryViewModel update](<../../Shared/Objects/PagingLibrary/PagingLibraryViewModel.swift:176>), [state-management](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 149-155.
- **Dependencies / blocker:** Safe Continue item, known starting ticks, and one acknowledged progress update.
- **Next action:** Validate the visible focused tile with one small progress change, then restore or document the resulting resume position.

### B06 — Episode completion replaces Continue with Next Up

- **Subsystem / severity / status:** Playback completion/Home membership; P2; **SOURCE VERIFIED**.
- **Reproduction:** This audit did not complete an episode. Existing 2026-10-08 simulator evidence exercised a near-end Play Next transition, not the whole Home focus acceptance path.
- **Expected:** Finished item leaves or is replaced in Continue, correct Next Up item/order appears, and focus falls back deterministically.
- **Observed / evidence:** Existing runtime evidence says the finished episode became watched and Continue advanced to the next episode; it does not establish focused-Home-card disappearance and replacement behavior. Source uses targeted membership invalidation and revision guards.
- **References:** [state-management episode completion evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 298-313; [Continue membership rules](../design-docs/state-management.md#continue-watching-and-refresh), lines 41-61.
- **Dependencies / blocker:** Requires a safe episode near completion, known Continue/Next Up ordering, and server state restoration plan. No full-episode playback was done in this audit.
- **Next action:** Use an explicit near-end test item, capture before/after server and Home memberships, and verify focus on the replacement or deterministic fallback.

### B07 — Series Mark Unwatched propagates through loaded rows and Home

- **Subsystem / severity / status:** Episode watched state and Continue membership; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not repeated in this audit. Existing 2026-10-08 runtime tested loaded Arcane episode/season rows and series Mark Unwatched.
- **Expected:** Loaded episode states and Continue membership update; unrelated shelves remain stable and Home needs no manual reload.
- **Observed / evidence:** Prior simulator evidence reports watched/progress indicators changed in loaded rows and Arcane was removed from Continue after reset. Source reconciles exact loaded descendant IDs and targets only affected Home collections. Stability of unrelated shelves was not explicitly captured.
- **References:** [state-management reconciliation/runtime evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 290-313; [notification reconciliation](<../../Shared/Services/Notifications.swift:152>).
- **Dependencies / blocker:** A safe series with known episode states; changing server watched state requires restoration.
- **Next action:** Repeat only with recorded before-state; assert all loaded children, Continue, unrelated rows, and focus, then restore the initial state.

### E02 — App Font is independent from subtitle font settings

- **Subsystem / severity / status:** Typography/subtitle configuration; P2; **SOURCE VERIFIED**.
- **Reproduction:** This audit changed App Font from Rounded to Serif and restored Rounded; subtitle appearance was not runtime-tested.
- **Expected:** App-wide SwiftUI type design does not replace the separately configured rendered subtitle font.
- **Observed / evidence:** `AppFontEnvironment` applies SwiftUI `.fontDesign`; subtitle font name/size/color remain in `subtitleConfiguration` and the VLC proxy configures subtitle rendering from that setting. Native AVPlayer remains AVKit-owned. No subtitle visual comparison was performed.
- **References:** [App Font environment](<../../Swiftfin tvOS/App/SwiftfinApp.swift:34>), [subtitle setting](<../../Shared/Views/SettingsView/VideoPlayerSettingsView.swift:348>), [VLC subtitle font](<../../Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy+VLC.swift:99>).
- **Dependencies / blocker:** Requires a subtitle-bearing sample with known configured font; none was selected in this audit.
- **Next action:** Compare actual subtitle rendering before/after App Font change while leaving subtitle configuration unchanged, then restore Rounded.

### F02 — Hidden/inactive controls cannot acquire focus

- **Subsystem / severity / status:** Focus eligibility of inactive content; P1; **SOURCE VERIFIED**.
- **Reproduction:** No dedicated hidden-control focus sweep was run in this audit.
- **Expected:** Inactive tab content and hidden HUD controls cannot acquire focus; visible active controls retain their documented default.
- **Observed / evidence:** MainTabView makes inactive tab content transparent, disabled, non-hit-testable and accessibility-hidden. The custom playback hierarchy structurally includes HUD only while visible; focus APIs retain a progress-first default. Runtime did not probe every hidden/inactive control.
- **References:** [MainTabView inactive content](<../../Shared/Coordinators/Tabs/MainTabView.swift:210>), [HUD focus presentation](<../../Swiftfin tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls.swift:140>), [focus contract](../design-docs/focus-navigation-contract.md#hidden-player-controls-and-visible-hud), lines 359-384.
- **Dependencies / blocker:** Runtime focus debugger exposes hosting responders rather than all SwiftUI candidates; physical hardware was excluded.
- **Next action:** On simulator, exercise hidden HUD, dropdown, Episodes, and inactive retained tabs for accidental focus acquisition; use hardware for final focus proof.

## Unverified cases

### B08 — Home vertical shelf focus regression matrix

- **Subsystem / severity / status:** Home vertical focus; P1; **UNVERIFIED**.
- **Reproduction:** Current audit checked Continue → Recently Added Movies → Recently Added TV Shows, then one Up back to the exact Promising Young Woman tile.
- **Expected:** Never skip an adjacent shelf; choose nearest visible horizontal position; choose deterministic fallback for short shelves; immediate reverse restores exact origin; scrolled offsets and Details return remain correct; one press means one transition.
- **Observed / evidence:** In the tested pair, Down selected the nearest visible column and Up restored the exact origin. Short-shelf fallback, horizontally scrolled row offset, Details return, and all boundary combinations were not exercised here. Prior implementation work passed the focused vertical scenario, but does not cover this full matrix.
- **References:** [FocusCoordinator Home routing](<../../Shared/Objects/FocusCoordinator.swift:63>), [focus contract Home](../design-docs/focus-navigation-contract.md#home-and-shelves), [2026-10-08 runtime evidence](../design-docs/state-management.md).
- **Dependencies / blocker:** Requires deliberately short and horizontally scrolled shelves; no blocker to future simulator coverage.
- **Next action:** Run the missing shelf/boundary matrix and keep Left/Right, membership, sidebar, and exact Details return as regressions.

### D02 — Search request-error focus and recovery

- **Subsystem / severity / status:** Search loading/error focus; P2; **UNVERIFIED**.
- **Reproduction:** No controlled failed request was injected; the audit did not disrupt session authentication or shared server connectivity.
- **Expected:** A query failure does not steal focus; field and keyboard remain usable, no delayed jump occurs, and recovery returns to results correctly.
- **Observed / evidence:** SearchView keeps app-owned field/key focus and the SearchViewModel refreshes nested content groups. Nested content-group request/error presentation is separate from SearchViewModel's own state; the error-focus/recovery path has not been runtime-proven. This is a risk to test, not a confirmed bug.
- **References:** [SearchViewModel request path](<../../Shared/ViewModels/SearchViewModel.swift:81>), [Search focus and content](<../../Shared/Views/SearchView.swift:86>), [state-management Search scope](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 318-326.
- **Dependencies / blocker:** A safe deterministic single-request failure injection/test endpoint is not configured. No broad connectivity or authentication disruption was attempted.
- **Next action:** Use a controlled one-request failure, preserve the active session, assert focus/input/recovery, and restore connectivity without changing user data.

### E01 — EPG font geometry across System, Rounded, and Serif

- **Subsystem / severity / status:** EPG typography/layout; P3; **UNVERIFIED**.
- **Reproduction:** EPG was not opened for a visual geometry check in this audit.
- **Expected:** Program text, row height, ruler alignment, and clipping remain correct for System, Rounded, and Serif.
- **Observed / evidence:** Source computes EPG row/ruler dimensions from preferred UIKit text metrics with minimum heights; program and ruler text use fixed semantic styles and one-line truncation. Source does not prove rendered measurements or clipping in all app font designs.
- **References:** [App Font environment](<../../Swiftfin tvOS/App/SwiftfinApp.swift:34>), [EPGLayout](<../../Shared/Objects/EPG/EPGLayout.swift:18>), [program cell](<../../Shared/Components/EPG/Body/Components/EPGProgramCell.swift:73>), [time ruler](<../../Shared/Components/EPG/Body/EPGTimeRuler.swift:43>).
- **Dependencies / blocker:** Requires loaded guide data and visual checks under all three font designs; Rounded was restored after the Settings test.
- **Next action:** On simulator, capture the same EPG rows/ruler in System, Rounded, Serif; inspect baseline alignment, clipping, and row stability, then restore the user's original font.

### F04 — Playback overlay layering matrix

- **Subsystem / severity / status:** Player-local overlay stack; P1; **UNVERIFIED** as a full matrix.
- **Reproduction:** Current audit opened Up Episodes and Back returned to the HUD. Existing 2026-09-28 simulator evidence covered nested Audio, Subtitles, and Quality picker Back, then dropdown, HUD, and Details. Intro/Credits are separately reproduced as A01/A02.
- **Expected:** One Back dismisses only the top active surface in order: nested picker, dropdown, Episodes/segment surface, transient HUD, player. Focus returns to the correct underlying target.
- **Observed / evidence:** Episodes and nested playback pickers followed the expected layered dismissal in their available scenarios. The 2026-09-28 run also did not reproduce the reported Restart Episode focus failure (Select restarted at 0:00) or nested picker Back closing the dropdown (Back dismissed only the picker). Intro and Credits violate the contract as A01/A02. This aggregate is not counted as a separate confirmed defect; those two repros are the actionable tracked bugs. No post-fix segment runtime matrix exists.
- **References:** [focus contract player stack](../design-docs/focus-navigation-contract.md#player-dismissal-and-return-focus), lines 525-539; [tech-debt segment cases](tech-debt.md#deferred-findings-and-review-needs); [dropdown evidence](../design-docs/focus-navigation-contract.md#down-playback-dropdown).
- **Dependencies / blocker:** Suitable Intro and Credits sample/segment is needed. The existing simulator has not been retested on the affected content since those reports.
- **Next action:** Fix A01/A02 using one responder-path trace; then validate every visible layer and its focus return in sequence.

### F05 — First/last focus boundaries and deterministic fallback

- **Subsystem / severity / status:** Cross-screen focus boundaries; P1; **UNVERIFIED**.
- **Reproduction:** Current audit checked Home first TV Shows tile Left to sidebar, Home shelves Down/Up, Search first key Left, and Search no-results Down. Existing Episodes checks exercised several selector/shelf edges, but no single full boundary matrix was run.
- **Expected:** Representative first/last targets, section transitions, empty regions, and missing-target fallbacks retain focus or choose the documented deterministic destination with one press.
- **Observed / evidence:** Individual tested boundaries moved once. B01's sidebar return now restored the saved Home target in the focused follow-up. Search fallback to field/key is explicit in source. Libraries, Settings, Details shelves, Episodes edge retention, and disappearing-item fallback were not all exercised.
- **References:** [focus contract known deviations](../design-docs/focus-navigation-contract.md#known-deviations-and-required-confirmation), lines 543-554; [Home fallback](<../../Shared/Objects/FocusCoordinator.swift:326>); [Search fallback](<../../Shared/Views/SearchView.swift:99>).
- **Dependencies / blocker:** Some focus regions use native tvOS spatial movement; device confirmation remains outstanding.
- **Next action:** Maintain a compact per-region first/last/empty-target checklist and rerun only affected paths with navigation changes.

## Blocked verification

None. D02 remains **UNVERIFIED**, not BLOCKED: a safe deterministic failure injection is absent, but a controlled test setup can be provided later without disrupting global connectivity.

## Newly discovered issues

No additional reproducible app bug outside the initial register was found. B01 reproduced on the pre-fix baseline and passed after the focused correction; it was not a new issue. The Search keyboard capture mismatch (`aaaaa` rather than the typed synthetic query) came from Device Hub input handling and was not counted as an app bug.

### X01 — Play Next product acceptance and native-player coverage

- **Subsystem / severity / status:** Playback product acceptance/backend scope; provisional P2; **UNVERIFIED**, not a confirmed bug.
- **Reproduction / inspection:** Source inspection of custom `SnowfinPlaybackSegmentOverlay` and `NativeVideoPlayer`; no native-player Play Next runtime sample was run.
- **Expected:** Product acceptance and native-player parity have not been decided by this audit; treat the existing product direction separately from custom-player behavior.
- **Observed / evidence:** The custom player attaches the four-part segment overlay; the native AVPlayer path does not. Existing tech debt calls for review of the custom transition and clarification of native-player coverage. This is an implementation-scope decision, not a runtime defect without a confirmed parity requirement.
- **References:** [existing tech-debt entry](tech-debt.md#deferred-findings-and-review-needs), [Play Next product spec](../product-specs/play-next.md), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next), lines 497-514.
- **Dependencies / blocker:** Product decision on native-player parity and acceptance of the custom overlay.
- **Next action:** Jamie reviews product acceptance separately; do not mix a parity decision into A01/A02 Back ownership fixes.

## Recommended repair order

1. **A03 — Up Episodes cross-season reopening**, a separate playback focus-target readiness issue.
2. Close the high-impact verification gaps with reversible test data: B03-B07 membership/progress/watched propagation, then D02 Search failure/recovery and D03 watched-specific assertion if desired.
3. Complete B08 and F05 focus boundaries, F02 hidden controls, E01 EPG geometry, and any remaining F04 overlay matrix.
4. Resolve X01 as a product/acceptance decision. Do not treat it as a confirmed bug or broaden playback architecture before that decision.

There are two useful shared investigations: (a) A01/A02 exposed the same outer player Back-delivery failure and now pass after one UIKit container owner was restored; their Intro-dismissal and countdown-then-choice transitions remain distinct, as does F04's separate segment surface; (b) B02-B07 share typed ItemState publication and targeted collection invalidation, but presentation-only updates must stay distinct from membership/order refresh. B01 and A03 both involve focus timing, yet they have different owners (Home sidebar candidate acquisition vs episode-card candidate readiness) and should not be patched by a shared delay.

## Regression checklist

- [x] A01: Intro Back dismisses only prompt; same player continues without a seek; HUD returns.
- [x] A02: first Back cancels countdown, second dismisses choice to the HUD; neither press exits the player.
- [ ] A03: first and cross-season Up Episodes reopens focus current episode; Left/Right and selector/shelf boundaries retain their owner.
- [ ] A04: Details-origin playback returns to same Details, then Home exact origin only after Home is visible.
- [ ] A05: Play returns to Play, Replay/Play From Beginning returns to its exact action, unavailable Replay falls back to Play.
- [x] B01: sidebar Right and Select restored the remembered tile from the TV Shows row, Movies row, and a horizontally scrolled Movies shelf; Home Up/Down reverse and Details return preserved the exact target. Initial launch still focused the first Home candidate. (Apple TV 4K 3rd gen, 1080p, tvOS 27.0 simulator.)
- [ ] B02-B07: focused tile updates, Continue membership add/remove, completion/Next Up ordering, descendant unwatch reconciliation, unrelated shelves, and deterministic focus.
- [ ] B08: adjacent shelf, nearest visible tile, short-row fallback, immediate reverse, scrolled offset, Details return, one press.
- [ ] C01-C02: native menu and App Font Back/selection return to invoking row; immediate reopen; no delayed jump.
- [ ] D01-D03: no-results input focus, controlled request failure/recovery, exact result return and accepted user-state presentation.
- [ ] E01-E03: System/Rounded/Serif EPG geometry; subtitle font independence; episode title/locator/series/fallback and Movie HUD.
- [ ] F01-F05: exact route restoration, hidden/inactive focus eligibility, one-press transitions, full overlay stack, and first/last/empty target fallback.

## Known-bug-free exit criteria

The bug-burn-down phase is complete only when every confirmed bug is fixed and its original reproduction passes on the Apple TV 4K (3rd generation) 1080p simulator, with affected contract regressions passing; no source-only claim closes a confirmed bug. All currently unverified items are either runtime-verified or explicitly accepted as non-defects/product decisions with evidence. No unexpected focus target, duplicate transition, delayed jump, playback exit, watched/progress mutation, or unrelated Home membership change remains in the affected paths. Physical Apple TV behavior remains a separate evidence tier where hardware-specific focus/playback proof is required.

## Original audit changes and side effects

In the initial register audit, only this register was created. The pre-existing modified files `docs/design-docs/focus-navigation-contract.md`, `docs/design-docs/navigation-stack.md`, and `docs/product-specs/navigation.md` were not edited, staged, reverted, or overwritten. No source code, existing normative document, commit, or push was changed in that audit.

Runtime used the already installed signed simulator app (version 1.4.1). The existing Mormon Wives S3:E10 session was resumed/paused and returned normally; no watched/favorite/completion control was changed. “Wuthering Heights” was already marked Watched; two brief playback samples reached about 0:03 and returned to its Details screen with Watched still shown. Start/stop reports may have updated its resume position; server-side ticks were not queried and that possible small progress update was not restored. The temporary App Font change was restored from Serif to Rounded. Search query input was local and the simulator session was left without any auth/connectivity changes. No build/install was run because only a documentation artifact changed.

## A01/A02 implementation follow-up (2026-10-10)

The remediation changes are limited to `Shared/Views/VideoPlayer/VideoPlayer.swift` and `Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift`. The overlay is hosted as a child of the UIKit player container; its controller receives Menu at `pressesBegan`, calls the shared handler once, and consumes the paired `pressesEnded` phase. `handleMenuEnded()` gives segment state first ownership and returns after coordinator consumption. Intro Back clears only the prompt; countdown Back cancels and retains the choice; a later Back clears the Play Next presentation. No relevant SwiftUI `onExitCommand` handler exists in this path. The presentation subscriber now derives dismissal eligibility from the emitted `presentation` value instead of rereading the `@Published` property during `willSet`.

Focused runtime checks on the requested Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator passed: Intro Back; countdown cancellation followed by separate overlay dismissal; HUD Back; Down dropdown Back; nested quality-picker Back; Up Episodes Back; regular player exit and return to the same Details route; Skip Intro activation; Play Next advancing one episode; and Keep Watching retaining the current episode. `The World Is Hot Enough` rendered on the episode HUD with `S10:E2` and `Futurama`, fitting on one line without overlap with the progress bar or timestamps. Movie playback still showed only `10 Cloverfield Lane` with the ordinary progress controls. One initial dropdown observation after Down was not reproducible on the immediate retrial and is not classified as a new bug.

The signed simulator build/install completed successfully before these documentation-only updates; lint reported 17 existing violations and 0 serious findings. The temporary Credits / Outro test preference was restored to Show Next Episode; its saved countdown duration was restored to 10 seconds. Test seeking and Play Next exercised the existing progress/completion paths and may have changed Futurama episode resume/watched state on Jellyfin; server-side state was not queried or restored. No commit or push was made. The three pre-existing dirty navigation documents remain untouched.
