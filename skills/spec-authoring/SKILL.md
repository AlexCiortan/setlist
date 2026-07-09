---
name: spec-authoring
description: The spec template and the Closing report contract (Appendix C and Part 5)
---

Condensed binding of Appendix C and Part 5 of the edition committed in this
repo. On any conflict, the edition text wins; load the template with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" appendix-c`, or copy
specs/TEMPLATE.md, which is the same text, stamped at bootstrap.

## Authoring

- Every spec starts as a copy of specs/TEMPLATE.md, numbered sequentially
  (spikes are 0000). Statuses: QUEUED, ACTIVE, REVISED, CLOSED, DRAFT.
- A spike's output is a decision, and it lands as a citable artifact, never as
  prose: an ADR (the usual case), or a Decision section in the spike file's
  Closing report. Dependent specs cite it by path, so the dependency is a file
  reference, not a remembered sentence.
- The header fields are contracts, not decoration: `Depends on:` names specs
  that must be CLOSED first; `Owner docs:` is the Builder's read budget for
  this spec; `QA binding:` declares how Pass 1 verifies it, decided at
  authoring time, never improvised at close; `Design contract:` cites the
  locked redline for design-heavy work, or "none (functional)".
- Acceptance criteria are dual-purpose: a human checklist AND the verbatim
  prompt that drives automated QA Pass 1. Write each as a concrete, checkable
  statement naming observable behavior, never implementation; if two readers
  could disagree on whether it passed, rewrite it before the spec goes ACTIVE.
  Experience-critical work carries the mandatory human acceptance criterion.
- The out-of-scope list is enforced, not advisory. If you are tempted to write
  scope-bounding rules for a maintenance item, it is a spec; if "done" fits in
  one observable sentence with no behavior shift, it is a chore.
- Ground-truth the premise before writing criteria: probe the running code; do
  not trust the framing. Capabilities that already work become regression-lock
  criteria, not build work.

## The Closing report contract

A spec closes only with the Closing report complete, and the close gate
verifies it mechanically:

- What was built; deviations and whether each was ratified; test counts
  (before -> after).
- The QA Pass 1 PASS/PARTIAL/FAIL report, pasted verbatim. A QA pass that is
  not in the repo did not happen. Honest PARTIALs, never claimed PASSes.
- QA Pass 2: confirmed by the developer, with the spot-checked criterion named.
- Design QA: punch list state, or "n/a (functional)".
- The mandatory diagram field, exactly: `Architecture diagram: updated in this
  commit` or `no impact`. Any diagram edit rides the closing commit.
- Follow-ups filed as chores or parking-lot rows.
- The spec's one-line inventory row in specs/STATUS.md flips to CLOSED in the
  same commit.

## Gotchas (field-observed)

- A failing QA probe can be a wrong probe. One field run's promotion "bug"
  was the prober passing the wrong argument shape to the API under test;
  the code was correct. Ground-truth the surface a criterion drives (the real
  signature, the real flag, the real endpoint) before filing the failure.
