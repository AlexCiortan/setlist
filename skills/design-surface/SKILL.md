---
name: design-surface
description: The design surface for UI projects (Part 5c): the design-heavy routing test, locked redlines as spec contracts, the bundle rule, design QA on the branch, /insights at gates
---

Condensed binding of Part 5c of the edition committed in this repo. On any
conflict, the edition text wins; load it with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 5c`, or read Part 5c in the
edition file committed at the repo root. Applies to UI projects that declared
a design surface at bootstrap (design_surface=yes) or adopted one later.

- **The routing test.** An entry is design-heavy when its risk is visual or
  interactional (a layout pass, a new user-facing surface, a redesign, a
  first-run flow); functional when its risk is plumbing (a service worker, a
  migration, a parser). Design-heavy entries route through a design intake
  BEFORE they are specced; functional entries skip straight to the spec.
- **A mock is a decision, not a picture.** The design surface returns locked
  deliverables: redlines and mocks carrying exact values (hex, px,
  breakpoints, copy), numbered as decisions. The spec is written against the
  locked redline and cites it in its header (`Design contract:`); the
  redline's values become acceptance criteria. Pixel fidelity stays a QA
  concern checked against the mock, never an acceptance criterion.
- **Design in batches, build in order.** Coherent groups of screens are
  designed as ONE system in a single intake, frozen, then built in
  engineering order. **No design happens mid-build**: a spec that starts
  redesigning something mid-build means an intake was skipped; stop and run
  it, do not improvise pixels in the build session.
- **The bundle rule.** The intake is not done until the deliverables are IN
  the repo: the downloadable bundle (redline documents, mock exports, an
  updated INDEX.md) committed under `docs/design/`. A design decision that
  is not committed does not exist.
- **Design QA on the branch.** Screenshots of the running build go back to
  the design surface during the build; findings return as a concrete punch
  list (values, not vibes) and are fixed in place. The spec does not close
  until the final punch list is empty or each remaining item is explicitly
  accepted or deferred by name. Expect the first build to be structurally
  right and rhythmically wrong; the loop converges in two or three rounds,
  and the last micro-alignment nits belong to an app-wide polish pass.
- **/insights at major gates.** At stage transitions and before large design
  arcs, run /insights over the accumulated design record and feed the result
  into backlog reconciliation (Part 7b Step 3).
- **Handoff hygiene.** House style rules (no em-dashes, naming, token names)
  ride the intake prompt so deliverables arrive compliant. Substantive design
  arcs land as companion journal entries, numbered in the repo's journal
  sequence.

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and
instance journals; nothing lands here without a real observed occurrence.
