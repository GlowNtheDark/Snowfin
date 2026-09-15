# Screen Agent Guide

Screen is a native tvOS Jellyfin client derived from Swiftfin/Snowfin.
This file is the entry point and map; deeper documents are loaded only as needed.

## Instruction priority

1. The current explicit user task.
2. This `AGENTS.md`.
3. Relevant repository documentation.
4. Existing implementation where documentation is silent.

Current-task requirements win over stale guidance. Describe disagreements between
implementation and product intent; do not silently turn a bug into a specification.
Within repository docs, current Screen contracts in `docs/` take precedence over
legacy `Documentation/` guidance. Implementation descriptions are observations,
not new product requirements or authorization to fix unrelated discrepancies.

## Read the relevant map

Start with [ARCHITECTURE.md](ARCHITECTURE.md) when ownership is unfamiliar.
Select only the documents needed for the task:

| Task | Read |
| --- | --- |
| Product scope | [Product principles](docs/PRODUCT.md) |
| UI or remote interaction | [Design conventions](docs/DESIGN.md) |
| Validation or build failure | [Quality and build commands](docs/QUALITY.md) |
| Workflow or substantial planning | [Codex workflow](docs/CODEX_WORKFLOW.md) |
| Navigation or dismissal | [Navigation contract](docs/product-specs/navigation.md), [implementation](docs/design-docs/navigation-stack.md) |
| Home content | [Home](docs/product-specs/home.md), [Continue Watching](docs/product-specs/continue-watching.md) |
| Episode details | [Episode Details](docs/product-specs/episode-details.md) |
| Playback | [Playback contract](docs/product-specs/playback.md), [lifecycle](docs/design-docs/playback-lifecycle.md) |
| Play Next | [Play Next](docs/product-specs/play-next.md) |
| Focus | [Restoration contract](docs/product-specs/focus-restoration.md), [focus system](docs/design-docs/focus-system.md) |
| Models, services, watched state | [State management](docs/design-docs/state-management.md) |
| Ongoing or deferred work | [Active plans](docs/exec-plans/active/), [tech debt](docs/exec-plans/tech-debt.md) |

Do not load this entire table's destinations for every task.
Follow further links only when needed to answer the task; links are not a reading checklist.

## Scope discipline

Make the smallest coherent change that solves the task.

- Do not refactor unrelated code or rename unrelated types/files.
- Do not rewrite working systems or add speculative abstractions.
- Do not change unrelated product behavior.
- Preserve existing uncommitted work; inspect the diff before and after edits.
- Keep tvOS product changes platform-scoped and preserve iOS behavior unless asked otherwise.

## Investigation

Trace the relevant call path and state ownership before editing.
Identify the smallest responsible set of files; stop broad exploration once known.
Prefer the existing mechanism over adding a parallel one.
Use source paths in the docs as starting points, then verify the current code.

## Two-pass rule

For a non-crashing UI or behavioral bug, allow at most two focused implementation passes.
After two unsuccessful passes, stop expanding the fix. Record useful evidence in
[tech debt](docs/exec-plans/tech-debt.md) when appropriate and move to other requested work.
Report the unresolved behavior; do not claim completion of a failed fix.
Crashes, data corruption, introduced build failures, and severe regressions may
exceed this limit when necessary to restore a working state.

## Verification

Use [QUALITY.md](docs/QUALITY.md) to select proportional verification.
Prefer focused checks; do not repeatedly run broad suites without new changes,
a failure, or a concrete unresolved concern. Avoid tests that duplicate implementation
or exist solely to inflate coverage. A build does not prove tvOS focus behavior.

## Delegation

Default to one lead agent. Use at most one subagent unless unusually strong,
independent work justifies more. Delegate only to materially save time or context.
Use higher-capability reasoning for architecture, integration, cross-file root causes,
difficult crashes, and complex state/navigation. Use lower-cost reasoning for narrow
tracing, mechanical edits, and straightforward visual tweaks when available.
Do not spawn agents just because delegation is available.

## Token efficiency

Favor targeted `rg` searches, narrow reads, small diffs, concise planning, and focused validation.
Avoid rereading understood files, rediscovering mapped architecture, speculative edit
loops, unrelated documentation, and oversized status summaries.
Use a short plan only when the task benefits from one; substantial work belongs in
[active plans](docs/exec-plans/active/), using the [workflow](docs/CODEX_WORKFLOW.md).

## Completion

Confirm the requested behavior was addressed and inspect the affected flow for regressions.
Report what changed, verification performed, and material unresolved limits concisely.
Update the owning document when a task changes a stable contract or ownership boundary.
Keep product intent in product specs and implementation mechanics in design docs.
