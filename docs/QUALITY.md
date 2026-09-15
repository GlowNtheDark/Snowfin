# Quality and completion

Done means the requested result is implemented within scope, the relevant checks
pass, and material unverified behavior is reported. Preserve unrelated work and iOS
behavior. See [AGENTS.md](../AGENTS.md) for scope and the two-pass limit.

## Choose checks by impact

Select checks for the behavior actually affected, not every check in a matching row.
For example, an indicator-only edit does not require auditing shelf ordering.
Honor explicit task limits on validation; report any resulting verification gap.

| Change | Relevant verification |
| --- | --- |
| Documentation only | Review links/source paths, instruction consistency, intent vs implementation, and diff scope. No app build needed. |
| Small TV UI edit | Focused static/diff check and affected TV build; inspect changed layout/focus on simulator or device. |
| Navigation/focus | Exercise the [navigation contract](product-specs/navigation.md), including nested details and any affected direct-play path; verify initial focus, directional moves, Back, and restored tile after refresh. |
| Playback | Start/resume, pause/seek, Back/dismissal, stop reporting, and affected queue/Play Next behavior; test each affected backend. |
| Watched/Continue Watching | Correlate the same item ID in server responses and local mappings; check partial episodes, next episodes, movies, deduplication, and recency ordering. |
| Shared behavior | Add relevant iOS validation when shared paths are affected. Use existing focused tests where useful; add tests for behavior, not implementation duplication. |

A successful build is separate from simulator/physical Apple TV verification.
State which ran. Hardware-dependent player behavior needs device evidence.
At the 2026-09-14 inspection, the `Snowfin tvOS` shared scheme had no Testables;
check the current scheme before choosing tests. `xcodebuild test` is
not evidence of app coverage without an actual test target.

## Build entry points

Run from the repository root. Inspect [CI](../.github/workflows/ci.yml),
[Brewfile](../Brewfile), [Cartfile](../Cartfile), and the
[contribution setup](../Documentation/contributing.md) only when setup is relevant.
At bootstrap, CI specifies Xcode 26.6 and the `Snowfin tvOS` scheme. Verify local
Xcode selection, available destinations, and existing Carthage/package artifacts
before treating an environment failure as a source defect.

```sh
xcode-select -p
xcodebuild -project Swiftfin.xcodeproj -scheme 'Snowfin tvOS' -showdestinations
xcodebuild -project Swiftfin.xcodeproj -scheme 'Snowfin tvOS' \
  -configuration Debug -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The generic simulator command checks compilation; select an installed simulator
for interaction testing. For requested device compilation, use
`-destination 'generic/platform=tvOS'`; device installation requires appropriate signing.
Build commands are entry points, not a claim that this bootstrap ran them.
Do not default to clean builds, dependency upgrades, or cache deletion.
Use targeted SwiftFormat/SwiftLint checks for changed Swift files according to the
checked-in configuration; do not format the entire dirty tree.

The upstream guide calls for both platform builds before upstream merge; current
local CI runs tvOS only. This distinction does not waive validation for affected iOS code.

## Final review

Run `git diff --check` and inspect the task's diff (including new files).
After builds inspect `Swiftfin.xcodeproj/project.pbxproj` for incidental rewrites.
Report changes, checks and their results, and material limitations concisely.
Do not rerun passed checks without a new change, failure, or concrete concern.
