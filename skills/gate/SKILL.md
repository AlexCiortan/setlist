---
name: gate
description: Run a stage-gate transition session per Part 7b (verify the gate leg by leg, reconcile the next stage's backlog, spec its first entry)
disable-model-invocation: true
argument-hint: "[which transition, e.g. gate 1 to 2]"
---

You are running a stage-gate transition session (Part 7b of the committed
edition). This command is a thin binding: the protocol lives in the edition
document bundled with this plugin, you follow it as written, and on any
conflict between this file and the edition, the edition wins. Load the full
Part first:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 7b`

This is a planning-only session: no src or tests edits. Gates are
evidence-gated, never time-gated.

## The five steps, in order

1. **Re-ground and scan.** Read STATUS.md, ROADMAP.md (the gate and the next
   stage's table), and the DECISIONS.md index. Run /setlist:validate and
   report findings. Confirm the tree is clean and the trunk is green; skim the
   Closing reports of specs closed since the last transition (deviations and
   follow-ups only). Where a design surface exists, run /insights over its
   record (Part 5c). The repo as it exists is the ground truth, not the
   roadmap's assumptions.
2. **Verify the gate, leg by leg.** Quote each leg and state PASS or FAIL
   with evidence, verified live this session (gates re-run, not taken on
   faith). Usage and desire legs are answered by the human and taken as the
   evidence; never self-certify them. If ANY leg fails: stop. A failed gate
   is a finding, not an obstacle to argue with. Name the smallest work that
   addresses the failing leg as the next action and end the session.
3. **Reconcile the next stage's backlog.** For each row: keep, amend the
   one-line scope (citing what closed specs taught), reorder, demote to the
   parking lot, or add a row (only if it traces to a Closing-report follow-up
   or an open question; nothing speculative). Constitution-touching changes
   need an ADR; reordering and scope-line edits do not. ADR consolidation
   (Part 4) happens here. One structured round for genuine forks only.
4. **Spec the first entry** of the new stage from specs/TEMPLATE.md, next
   sequential number. Design-heavy first entries route through the design
   intake (Part 5c) BEFORE this step.
5. **Close on one commit:** the reconciled ROADMAP, the new spec, STATUS.md
   (phase line, inventory row, named next action), and a journal entry
   carrying the gate evidence and reconciliation decisions. Then
   /setlist:checkpoint opens the spec branch.

A gate that reverses a standing constraint (for example "no backend") gets a
dedicated heavyweight planning session on the escalation tier of the model
ladder (Part 2), not this standard flow.

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and
instance journals; nothing lands here without a real observed occurrence.
