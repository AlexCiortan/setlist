---
name: retrofit
description: Retrofit the Spec-Driven Development Framework onto an existing codebase (Part 8b)
disable-model-invocation: true
---

You are retrofitting the framework onto an existing codebase. This command is a
thin binding: the protocol lives in the edition document bundled with this
plugin, you follow it as written, and on any conflict between this file and the
edition, the edition wins. Never fork the protocol.

Load the protocol first. Run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8b`
and follow that text (the Retrofit Protocol) for everything below. The whole
retrofit is planning plus documentation: reading the de-facto src and tests is
required; editing them is forbidden.

## 1. Gather conversationally

- What the software does and its history, in a paragraph.
- The working mode (the user writes code too, or reviews only) and known
  constraints.
- Hold the retrofit-specific question for the interview: which existing
  constraints are sacred (not redesignable in the coming months) versus
  disposable.

## 2. Inventory first (Part 8b Step 1, read-only)

Explore before asking, exactly as Step 1 lists: stack and versions, the
de-facto core data model, state ownership, error handling as practiced, test
coverage reality, secrets handling, the riskiest areas, and the de-facto src
and tests locations (paths are roles; they may not exist by those names). Show
the inventory report to the user BEFORE any interview question.

## 3. Interview (Part 8b Step 2)

Same structured-round rules as Part 8 Step 1, plus the sacred-vs-disposable
question. One round, genuine forks only, recommendations inline, and the same
opener: "what has changed since this framework edition was written" comes
first.

Ask the `diagram_command` question in this round too, DEFAULT NONE: is there a
command that prints this project's structure as one Mermaid block (an import
graph, a schema dump)? A yes is recorded in `.claude/sdd.json` beside
`gate_command` and its committed output under `docs/diagrams/generated/` must
then equal what it prints at every close; a no records nothing, which is the
right default.

Verify the environment in this round too: the `opusplan` live probe, and
`command -v jq`. The three stamped gates are advisory and PERMIT without jq; the GIT hooks fail closed without it, so a retrofit
onto a machine that lacks it will deny its own first commits. Report the
install command and let the user run it; install nothing yourself.

## 4. Phase 1: the mechanical stamp

Write `.claude/stamp-answers.txt` (KEY=VALUE) with `mode=retrofit` and the
src_role and tests_role paths the inventory found:

```
project_name=<name>
stack=<short stack id>
working_mode=<review-only | developer-writes>
ui=<yes|no>
opusplan_verified=<yes|no>
design_surface=<yes|no>
src_role=<de-facto src path>
tests_role=<de-facto tests path>
mode=retrofit
```

Then run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh" .claude/stamp-answers.txt .`

In retrofit mode the stamp skips files the repo already has (it reports them);
merge the framework content into those by hand in phase 2. An existing
`.github/CODEOWNERS` is one of those: the stamp leaves it, and phase 2 adds the
four protected paths (`/.githooks/`, `/.claude/`, `/specs/attest/`,
`/.github/`) under the team's own owner rather than replacing the file. The
forge check, its workflow and the `gates` block are stamped as for a new
instance (edition v1.14); requiring the check on the trunk is the team's act at
the forge, named in the hand-off. The stamp emits no
/scaffold skill: the project is already scaffolded, and the health check ships
as /setlist:validate. Fill gate_command in `.claude/sdd.json` with the
repo's real full-suite command and set `scaffolded` to true once it runs, so
the gates bind.

The stamp takes one path per role; after it runs, edit `.claude/sdd.json` when
the inventory found more. Role paths accept a list (Part 6): spread layouts
name every code location, and a flat-root repo enumerates its real code files
(for example `["index.js", "lib"]`). Never record `"."`: the scope hook
ignores it by design, and a root-wide deny would block the docs-only trunk
commits the loop depends on.

## 5. Phase 2: generation with the retrofit differences (Part 8b Steps 3 to 5)

All from the loaded Part: steering docs DESCRIBE what is, with Current vs
target callouts wherever reality and intent diverge; DECISIONS.md seeded with
INFERRED ADRs for the flip ceremony; the diagram drawn from the real dependency
graph, which for this edition means SEEDING `docs/diagrams/` from the inventory
you already read (see below); the queue per Step 4 (spec 0001 is characterization tests around the
de-facto core abstraction unless its Goal justifies otherwise); the whole
retrofit landing as ONE commit on the default branch with message prefix
`framework:`; and the Step 5 hand-off lines in RUNBOOK.md.

### Seeding `docs/diagrams/` in phase 2

Create the directory and write `docs/diagrams/context.md` at L1 and the L2
container block at the bottom of `steering/structure.md`, both from the Step 1
inventory you have already read, under the `diagrams` skill's rules, each
opening with the four-line header from
`${CLAUDE_PLUGIN_ROOT}/templates/root/DIAGRAM-HEADER.md` and
`Synced by: retrofit`. Node names are the de-facto role paths the inventory
found, so they resolve against the tree from the first close. This is the ONE
scan-and-draw-fresh a retrofit gets, and it is bounded by the same read you
already showed the user: it draws what exists, not what should exist, and a box
you cannot point at a path for does not go in.

Say plainly what creating the directory does: its presence ARMS the close's
diagram checks, so from the first spec onward a close that says `updated` names
its files and one that says `no impact` while a diagram moved is refused. Show
the seeded files to the user before the retrofit commit, the way you showed the
inventory; a diagram they cannot read as true of their own code is redrawn now,
not accepted and fixed later. A project that would rather not opt in yet deletes
the directory, and every reader behaves as it did before the diagram half
existed.

## Gotchas (field-observed)

- The stamp can collide with an existing file by case. A stamped `README.md`
  once landed next to a repo's real lowercase `readme.md` as a duplicate.
  Prefer the repo's real file, remove the stamped duplicate, and record the
  call in the retrofit commit.
