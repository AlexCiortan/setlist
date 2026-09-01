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
  (spikes are 0000). Statuses: DRAFT, QUEUED, ACTIVE, REVISED, BUILT, PARKED,
  CLOSED (Part 5 carries the canonical list; BUILT and PARKED are v1.7, and
  both mean the work is NOT on the trunk).
- A spike's output is a decision, and it lands as a citable artifact, never as
  prose: an ADR (the usual case), or a Decision section in the spike file's
  Closing report. Dependent specs cite it by path, so the dependency is a file
  reference, not a remembered sentence.
- The header fields are contracts, not decoration: `Depends on:` names specs
  that must be CLOSED first; `Owner docs:` is the Builder's read budget for
  this spec; `QA binding:` declares how Pass 1 verifies it, decided at
  authoring time, never improvised at close; `Design contract:` cites the
  locked redline for design-heavy work, or "none (functional)". Two are
  MACHINE-written and never authored by hand: `Spec-hash:` (checkpoint, at the
  ACTIVE flip) and `Owns:` lines (checkpoint, as the build acquires role-path
  files; edition v1.12, one verbatim file per line, no placeholder in the
  template on purpose). Do not add, edit or imitate either while authoring:
  the audit reads their exact grammar, and a hand-written declaration is a
  claim checkpoint never made.
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
- The QA Pass 1 verdict block (a fenced `qa-pass-1` block, one
  `<criterion>: PASS|PARTIAL|FAIL` line each), which is what the gates read, and
  below it the full report pasted verbatim, which is what people read. A QA pass that is
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
- Pre-agree the SPLIT at approval, not mid-build. If a spec might run big, name
  the boundary and the sibling number now ("the WSL2 half parks as 0002b if the
  session overruns"). Otherwise the Builder invents a scope boundary under
  pressure, at the moment its judgment is worst. The sibling's STATUS row uses
  the SUFFIXED number; the close gate greps the number literally, so a `0002b`
  spec with a `0002` row does not close.
- A spec approved with no friction, in a session that raised a concern, is a
  concern that got dropped. Approval is not agreement. If you raised something
  and it is not in the spec, in an ADR, or in an open question, it was lost, not
  resolved. Say so once, with a recommendation; the human decides and the
  decision gets recorded.
- Name the confirmation affordance for any DESTRUCTIVE action at authoring time,
  even if the answer is "none, and here is why". A delete shipped
  confirmation-free because the design contract specified a sheet for the
  harmless action and said nothing about the destructive one, and an
  unremembered click wiped a server.
- A fact about mounting, ordering, or lifecycle established for one surface says
  something about every OTHER surface in the spec. Ask what, in the spec, before
  the build. Three QA Pass 2 defects and two live production bugs in one arc
  shared exactly that signature.
