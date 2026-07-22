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

Verify the environment in this round too: the `opusplan` live probe, and
`command -v jq`. The three stamped gates fail closed without jq, so a retrofit
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
merge the framework content into those by hand in phase 2. The stamp emits no
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
graph; the queue per Step 4 (spec 0001 is characterization tests around the
de-facto core abstraction unless its Goal justifies otherwise); the whole
retrofit landing as ONE commit on the default branch with message prefix
`framework:`; and the Step 5 hand-off lines in RUNBOOK.md.

## Gotchas (field-observed)

- The stamp can collide with an existing file by case. A stamped `README.md`
  once landed next to a repo's real lowercase `readme.md` as a duplicate.
  Prefer the repo's real file, remove the stamped duplicate, and record the
  call in the retrofit commit.
