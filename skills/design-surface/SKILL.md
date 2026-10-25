---
name: design-surface
description: "The design surface for UI projects (Part 5c), bound to Claude Code's /design: the design-heavy routing test, the intake on the canvas, locked redlines committed under docs/design/ before ACTIVE, design QA against the committed redline, the design record at gates"
---

Condensed binding of Part 5c of the edition committed in this repo. On any
conflict, the edition text wins; load it with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 5c`, or read Part 5c in the
edition file committed at the repo root. Applies to UI projects that declared
a design surface at bootstrap (design_surface=yes) or adopted one later.

- **The binding.** The design surface is Claude Code's `/design` skill: it
  drafts mockups and screen flows as artboards on one canvas, published as a
  Claude Design artifact on claude.ai, private until shared, versioned on
  every publish. It needs Claude Code 2.1.265 or later, the Anthropic API,
  the Design template on, and an interactive session signed in with a
  claude.ai account (`/login`). Artifacts are off under `claude -p`, so an
  intake is never headless. Some instances have no `/design`: those on a
  cloud provider's platform or an API gateway, under customer-managed keys,
  HIPAA or zero data retention, or with the template or artifacts off. For
  them the Part still holds: commit a redline and a mock made another way.
- **Where a design lives.** The canvas is where it is drawn; `docs/design/`
  is where it is locked. A retention period can delete an artifact nobody
  opens, and no Builder session reads the canvas, so a decision only on the
  canvas does not exist.
- **The routing test.** An entry is design-heavy when its risk is visual or
  interactional (a layout pass, a new user-facing surface, a redesign, a
  first-run flow); functional when its risk is plumbing (a service worker, a
  migration, a parser). Design-heavy entries route through a design intake
  BEFORE they are specced; functional entries skip straight to the spec.
- **The intake.** One `/design` session per batch of screens, the human
  present. The brief names the screens, the house style and
  `steering/design-tokens.md` as the design system. The human picks one
  artboard per screen and may adjust it; the pick is the lock. The
  implementation is a spec written against the locked redline, never a build
  from the canvas session. The session writes the redline from the pick and
  the human confirms each value. The session reads the canvas back at the
  version it locks, so an adjustment on the canvas is read, not remembered.
- **A mock records a decision.** Redlines carry exact values (hex, px,
  breakpoints, copy), numbered as decisions. The spec cites the redline in
  its header (`Design contract:`) and its values become acceptance criteria.
  Pixel fidelity stays a QA concern checked against the mock, never an
  acceptance criterion.
- **Design in batches, build in order.** Coherent groups of screens are
  designed as ONE system on one canvas, frozen, then built in engineering
  order. **No design happens mid-build**: a spec that starts redesigning
  something mid-build means an intake was skipped; stop and run it, do not
  improvise pixels in the build session.
- **The bundle rule.** The spec that builds to a design does not go ACTIVE
  until `docs/design/` holds five things. The redline, its header naming the
  artifact's title, its address, the version locked and the date. Each
  picked artboard's export, PNG or PDF, made from the canvas page in a
  desktop browser. The picked boards' source as a read of the artifact saves
  it, which is evidence and no substitute for the export. Every decision a
  comment thread records, copied into the redline or an ADR. And
  `INDEX.md`'s row. A design decision that is not
  committed does not exist.
- **Design QA on the branch.** Screenshots of the running build are read
  beside the committed redline and its artboard export, and findings return as a punch
  list by the redline's decision ids and exact values, fixed in place. The
  spec does not close until the final punch list is empty or each remaining
  item is accepted or deferred by name. Expect the first build to be
  structurally right and rhythmically wrong; the loop converges in two or
  three rounds, and the last micro-alignment nits belong to an app-wide
  polish pass.
- **The design record at gates.** At stage transitions and before large
  design arcs, read `docs/design/INDEX.md` and the redlines locked since the
  last transition for drift, and feed the result into backlog reconciliation
  (Part 7b Step 3).
- **Handoff hygiene.** House style rules (no em-dashes, naming, token names)
  ride the `/design` brief so deliverables arrive compliant. Substantive
  design arcs land as companion journal entries, numbered in the repo's
  journal sequence. Token changes land through the Planner with an ADR.
- **The standalone site closes on 2026-12-14.** A design still on
  claude.ai/design is committed under `docs/design/` before then, and every
  decision in its chats or comments, which do not move, is copied into a
  redline or an ADR. `/design-sync` and `/design-login` serve that site and
  are not part of this binding.

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and
instance journals; nothing lands here without a real observed occurrence.
