---
name: model-ladder
description: The capability-tier escalation rules for Planner and Builder sessions (Part 2)
---

Condensed binding of Part 2 of the edition committed in this repo. On any
conflict, the edition text wins; load it with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 2`, or read Part 2 in the
edition file committed at the repo root.

The ladder is stated as capability tiers; model names are bindings that churn,
held in one table the edition's Changelog updates per edition.

- **Planning tier** does the deciding: architecture, spec design, steering
  changes. **Execution tier** does the typing: code, edits, tests, Git.
  **Escalation tier** is the strongest model the harness offers, reserved for
  the moments that earn it.
- Default binding: `opusplan`. The planning tier runs in plan mode (deep
  reasoning, read-only), the execution tier in execution mode. Plan mode is
  read-only, so the planner decides and the executor types; that is fine,
  because the quality that matters in planning is the deciding.
- Escalate the Builder when it loops: a bug that survives two fix attempts, or
  a fix that spawns new failures, moves the build session one tier up. Do not
  keep feeding the loop; escalation is cheaper than the churn, and far cheaper
  than a wrong fix that ships.
- Heavyweight planning (session zero, a major spec revision, a steering change)
  runs a dedicated session on the escalation tier, so the whole session
  reasons at full strength.
- De-escalate after the escalated session closes its spec or fix: the next
  ordinary session returns to `opusplan`.
- Roles bind to artifacts, never to model names. What must hold is the
  boundary between planning artifacts and implementation. Record which model
  did what in the journal so escalation patterns stay visible.
- Degradation is not escalation. The settings' `fallbackModel` chain (Part 3)
  absorbs provider overload by routing a turn to the next model down, with a
  notice. Do not treat a degraded turn as evidence about the tier, and give a
  degraded planning turn a journal line so the record stays honest about
  which model actually decided.

Current bindings (v1.6, from the edition's Part 2 table): planning tier Opus
via `opusplan` plan mode; execution tier Sonnet via `opusplan` execution mode;
escalation tier the strongest model available in the environment (a model
family above Opus where offered, otherwise Opus, reached with `/model`).

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and
instance journals; nothing lands here without a real observed occurrence.
