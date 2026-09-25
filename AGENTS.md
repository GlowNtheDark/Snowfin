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
- Keep work scoped to Screen, the tvOS Jellyfin application; preserve iOS behavior unless asked otherwise.

## Investigation

Trace the relevant call path and state ownership before editing. Use relevant docs as
entry points, then identify the smallest responsible set of files. Stop broad
exploration once that set is known; prefer the existing mechanism over a parallel one.

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
For runtime work, physical Apple TV behavior is authoritative. See
[QUALITY.md](docs/QUALITY.md) for focus, scrolling, playback, and performance validation.

## Model roles and delegation

Use GPT-6 Sol as the default lead and orchestrator for normal implementation, everyday
debugging, and work that needs judgment. Use GPT-6 Luna for repo exploration, file
tracing, triage, small localized edits, and scoped subtasks. Use GPT-6 Astra for
difficult root causes, architecture or cross-cutting changes, and stubborn regressions.
Use it as lead or as an independent second opinion when that can change the decision.

Keep one lead and at most one subagent. Delegate only independent, bounded work that
materially improves the result or saves time; the lead integrates and reviews the work.
Do not add model or reasoning recommendations to normal task prompts; use project
defaults and this guide unless the user explicitly asks otherwise.

## Completion

Confirm the requested behavior was addressed and inspect the affected flow for regressions.
Report what changed, verification performed, and material unresolved limits concisely.
Update the owning document when a task changes a stable contract or ownership boundary.
Keep product intent in product specs and implementation mechanics in design docs.
