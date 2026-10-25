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
  the moments that earn it. **Delegated tier** (edition v1.21) runs bounded
  mechanical work a subagent can finish and a check can judge.
- Default binding: `opusplan`. The planning tier runs in plan mode (deep
  reasoning, read-only), the execution tier in execution mode. Plan mode is
  read-only, so the planner decides and the executor types; that is fine,
  because the quality that matters in planning is the deciding. The reasoning
  does not make the trip: thinking is tied to the model that produced it, and
  the execution model reads none of the planning model's, so the executor
  receives the written plan and nothing else, and a session escalated from
  execution starts its reasoning over. A decision that is not on the page, in
  the spec or the plan, has not been handed over.
- Escalate the Builder when it loops: a bug that survives two fix attempts, or
  a fix that spawns new failures, moves the build session one tier up. Do not
  keep feeding the loop; escalation is cheaper than the churn, and far cheaper
  than a wrong fix that ships.
- Heavyweight planning (a complex project's session zero, a major spec
  revision, a steering change) runs a dedicated session on the escalation tier,
  so the whole session reasons at full strength; an ordinary session zero runs
  on the planning tier's model (`opus`).
- De-escalate after the escalated session closes its spec or fix: the next
  ordinary session returns to `opusplan`.
- Roles bind to artifacts, never to model names. What must hold is the
  boundary between planning artifacts and implementation. Record which model
  did what in the journal so escalation patterns stay visible.
- Delegate the mechanical, never the deciding. To a subagent on the delegated
  tier (`haiku`): the mechanical half of `/setlist:checkpoint` (the survey, the
  sanity check, the gates' runs), `/setlist:gate`'s leg verification runs,
  `/setlist:validate`'s read-only check, QA Pass 1 (`qa-verifier`, `model:
  haiku`) with its browser-QA runs, and the `verify` skill's gate run. Never
  delegated: planning, the close review (`close-reviewer` stays on `model:
  opus`), and any decision that closes a spec. A delegated phase runs through
  the Agent tool with `model: haiku`, never as a fork, which runs on the parent
  session's model; the journal line's model field shows which ran. The rung is safe inside Setlist
  because two guardrails answer the tier's named failure modes (stopping early
  to hand the task back; claiming a change done without a check): the golden
  rules "carry a spec through" and "a real check, or no claim", delivered by
  the Stop hook and the `verify` skill, and the git hooks, which refuse
  whichever model typed the work. Each delegated phase gets a journal line:
  the phase, the model it resolved to, its tokens, and its cost where the
  harness reports one.
- Degradation is not escalation. A turn can be served by a model other than
  the one the session chose, in two ways. The settings' `fallbackModel` chain
  (Part 3) routes a turn to the next model down when the provider is overloaded,
  with a notice. Since Claude Code 2.1.286 the harness also retries once on the
  previous model of the same tier when the API refuses the model an alias
  resolves to; its changelog does not say whether that retry is announced, and
  a refusal provoked at 2.1.292 reached no retry. Do not read either kind of
  turn as evidence about the tier. Give each one a journal line, a single-turn
  change inside a tier included, so the record names the model that decided.

Current bindings, from the edition's Part 2 table (which carries the dated
reading of what each alias served and the verification method): planning tier
Opus via `opusplan` plan mode, which plans on `opus`; execution tier Sonnet via
`opusplan` execution mode, which builds on `sonnet`; escalation tier Claude
Fable, alias `fable`, or the availability-aware alias `best` (Fable where the
organization has access, latest Opus otherwise), reached with `/model`;
delegated tier Haiku, alias `haiku`, for the subagents named above. The
binding is the ALIAS and the tier, never a version: what an alias served on a
date, and on which provider, is a reading kept in the table's verification
column and the edition's Changelog. On other providers the same aliases can
resolve a version or a generation older. A family named anywhere in the
protocol means the latest version of it the provider serves: "Opus 5",
"Sonnet 5" and "Haiku 5" name the latest version of that tier the harness
serves. `opusplan[1m]` forces the 1M window in both phases where a phase's
model does not run it natively; the table's verification column records which
models run it natively. Effort is per model and recalibrated per release:
`medium` is Claude Code's default on both tiers as the table reads them, and a
setting carried over from an earlier version of a tier is re-read before it is
kept. The bootstrap probe records the model each phase served (`models` in
`.claude/sdd.json`, plugin 2.12.0). A managed allowlist changed after the stamp
makes the harness substitute a model, and it does not refuse. So
`/setlist:validate` re-runs the probe in each phase, names a phase served off
its tier, and names a phase whose model differs from the recorded one.

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and
instance journals; nothing lands here without a real observed occurrence.
