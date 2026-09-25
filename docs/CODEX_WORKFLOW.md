# Codex workflow

Keep Codex prompts short and task-specific: state the outcome, scope, and special
constraints. Stable repo guidance belongs in [AGENTS.md](../AGENTS.md) and relevant
docs rather than being repeated in each prompt.

## Task lifecycle

1. Inspect the current diff and identify the task's relevant product contract.
2. Trace the relevant code; use [ARCHITECTURE.md](../ARCHITECTURE.md) if ownership is unfamiliar.
3. Make the smallest coherent change. Keep a plan only if it helps manage the work.
4. Run [focused verification](QUALITY.md) and review the resulting diff.
5. Pass: finish with a concise evidence-based report. Failure: investigate the result;
   for non-crashing UI/behavior bugs, apply the two-pass limit and exceptions in
   [AGENTS.md](../AGENTS.md). Report unresolved work without claiming it passed.

Use [AGENTS.md](../AGENTS.md) for repo scope, model roles, delegation, investigation,
and the two-pass limit. This document covers planning, deferred findings, and doc upkeep.

## Plans and deferred findings

Use [active/](exec-plans/active/) for substantial work spanning multiple steps or
sessions, not routine edits. A useful plan contains: outcome/non-goals, source paths,
known facts and uncertainties, small steps/status, decisions, and verification results.
Keep it current as scope changes. Move useful finished plans to
[completed/](exec-plans/completed/); do not retain noise solely to fill the directory.

[Tech debt](exec-plans/tech-debt.md) records observed deferred problems or unresolved
findings with evidence, impact, and the next useful check. Label uncertainty; do not
invent problems or present untested hypotheses as confirmed bugs.

## Documentation maintenance and discovery

Put user-facing contracts in `product-specs/`, ownership/mechanics in `design-docs/`,
and temporary work in plans. Link to the owning document instead of duplicating rules.
Preserve useful legacy documentation; explicitly identify disagreements with newer
Screen direction or current code. Update only documents affected by the task.

Official OpenAI guidance recommends short, practical `AGENTS.md` files with links
for deeper task-specific material and durable instructions instead of repeated prompts.
This repository follows that approach. [OpenAI best practices](https://learn.chatgpt.com/guides/best-practices)
(reviewed 2026-09-14).

Codex discovers instruction files along the project-root-to-working-directory path,
with `AGENTS.override.md` taking precedence over `AGENTS.md` in the same directory.
Linked docs are read on demand; links do not automatically load every specification.
[OpenAI instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
(reviewed 2026-09-14).
