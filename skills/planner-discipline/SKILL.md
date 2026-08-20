---
name: planner-discipline
description: The Planner role's operating loop, read budget, and park-do-not-improvise rule (Parts 7 and 2)
---

Condensed binding of Parts 7 and 2 of the edition committed in this repo. On
any conflict, the edition text wins; load the full Part with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 7` (or `2`), or read Part 7 in
the edition file committed at the repo root.

## The role boundary

The Planner thinks, decides, writes and refines specs, and records rationale.
It touches planning artifacts only: specs/, steering/, journal/, specs/STATUS.md,
DECISIONS.md, ROADMAP.md, CLAUDE.md. Never the src or tests role paths. The
Builder is governed by the one active spec; STATUS.md is the baton between the
two roles.

## The read budget (load this much and no more)

- Every session: CLAUDE.md (auto-loaded), specs/STATUS.md, the active spec.
- Planner, additionally: the DECISIONS.md index table; full ADR entries only on
  demand; steering docs only when the planning question touches them.
- Builder, additionally: only the steering docs the spec's `Owner docs:` header
  names. That field is load-bearing, not decoration.
- After a compaction event, and in any multi-hour build, re-read STATUS.md and
  the active spec before continuing.

## The per-feature loop (Part 7)

Plan (re-ground from STATUS.md, ground-truth the premise against the running
code, one structured round for genuine forks, propose the spec), branch via
/setlist:checkpoint, build in small spec-scoped commits, QA Pass 1 automated
against the criteria, QA Pass 2 human acceptance, close through the gate,
repeat. Chores run between specs, never during a build.

**Every planning precondition reads the STATUS STATE, never the spec number.**
Close order does not follow spec order. A spec can sit BUILT or PARKED on its
branch while later specs merge past it, so "0044 is done, therefore 0045 can
build on it" is false whenever 0044 is parked, and that exact sentence has been
written in the field and acted on. Before asserting that a dependency exists,
read its inventory row: only CLOSED means the work is on the trunk. BUILT and
PARKED both mean it is not.

## Park, do not improvise

A genuine ambiguity found mid-build goes to specs/STATUS.md under "Open
questions for the Planner" and is surfaced to the human. Never resolved by
guessing, never widened into scope. A gate failure that cannot be resolved
within the spec's scope is parked the same way; never widen scope to fix a
gate.

## Interview discipline

When 2 to 4 decisions need locking, ask them as ONE structured multi-question
round with recommendations inline; only genuine forks become questions. The
stopping rule: one round is right, two is fine, three is procrastination.

## Gotchas (field-observed)

- A spec queued at session zero goes stale the moment the spike ships. One
  field run's spike lifted the core into src before spec 0001 opened; the
  re-ground flipped those criteria to regression locks and re-aligned the
  spec to the shipped shapes. Re-ground a QUEUED spec against post-spike
  reality before its branch opens; never build from the session-zero text.
- Baked-in judgment calls beat manufactured forks. The same re-ground offered
  its three judgment calls as veto points with recommendations instead of
  opening a new interview round; reserve questions for genuine forks.
