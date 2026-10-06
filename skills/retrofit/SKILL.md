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

## 0. Observe, on request, before anything is written (plugin 2.11.0)

When the command was invoked with `--observe`, or when the user answers yes to
this, your FIRST question: "Before anything is written: do you want to see what
Setlist would have refused over this repository's last 50 merges? It installs
nothing and writes nothing." A no, or no answer, goes straight to section 1.

1. Find what the read needs, read-only: the trunk (the branch this project
   merges onto, in the order the upgrade skill gives) and the de-facto role
   paths (where the feature code lives; the tests role too). This is the part
   of section 2's inventory the audit needs, nothing more yet.
2. Run, from the repository root:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-instance.sh" --observe --trunk <trunk> --role <path> [--role <path> ...] .`
   (`--merges N` reads another count). It clones the repository privately,
   runs the plugin's trunk audit, which carries the close checks, and deletes
   the clone; nothing in the repository changes. On a long history it takes
   minutes (measured: 160 commits in about 100 seconds).
3. Quote its output to the user verbatim: the range it read, then every commit
   the audit WOULD have refused, by its code where the audit gives one and by
   the audit's own sentence where it does not. Say what it is: a reading of
   their history as if they had adopted Setlist at the range's start, not a
   verdict on them, and exit 0 means the read completed.
4. If the user asks what adopting changes inside a session, one measured fact
   belongs here: Claude Code starts an interactive session in auto mode on a
   third-party provider or with telemetry off when no `permissions.defaultMode`
   is set, and the stamp sets none; the stamped ask rules still prompt under it
   (measured on Claude Code 2.1.284: `git push` in auto mode was answered with
   "Ask rule Bash(git push*) overrides auto mode for this command."), and the
   git hooks refuse whatever the session allows.
5. Invoked with `--observe`: stop here, and say that `/setlist:retrofit` without
   it adopts. Otherwise continue at section 1.

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

**The role paths come from one mechanical scan, never from the defaults.** Run
the inventory scan from the repository root and show its output in the report:

```sh
git ls-files | awk -F/ '{ top = (NF > 1) ? $1 : "."; k = split($NF, part, "."); ext = (k > 1) ? tolower(part[k]) : "" } ext ~ /^(c|cc|cpp|cs|go|java|js|jsx|kt|m|mjs|php|py|rb|rs|scala|sh|swift|ts|tsx|vue|dart|ex|exs|clj|lua|r|sql|hs|ml|fs|elm|erl|zig)$/ { n[top]++ } END { for (d in n) printf "%d %s%s\n", n[d], d, (tolower(d) ~ /^(test|tests|spec|__tests__|e2e|testing)$/ ? " (tests)" : "") }' | sort -rn
```

It counts the tracked source files under each top-level directory, most first,
and marks the test-named ones. Write `src_role` from the first candidate not
marked `(tests)` and `tests_role` from the first one marked, as the scan read
them; never write `src` or `tests` unless the scan lists them. Where the code
lives in several directories, stamp with the first and list the rest in
`.claude/sdd.json`'s `roles` after the stamp (a role is a string or a list of
strings). The stamp refuses a role path the repository does not have, by name.

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
`command -v jq`. The stamp refuses before it writes anything when `jq` is
missing or not working (it builds `.claude/sdd.json` with `jq`, and
the GIT hooks fail closed without it; the session hooks report, or stay
silent, and do not block), so check first rather than meet the refusal. Report the
install command and let the user run it; install nothing yourself.

## 4. Phase 1: the mechanical stamp

Write `.claude/stamp-answers.txt` (KEY=VALUE) with `mode=retrofit` and the
src_role and tests_role paths the inventory scan found (section 2):

```
project_name=<name>
stack=<short stack id>
working_mode=<review-only | developer-writes>
ui=<yes|no>
opusplan_verified=<yes|no>
design_surface=<yes|no>
src_role=<the scan's first candidate>
tests_role=<the scan's first (tests) candidate>
mode=retrofit
```

Then run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh" .claude/stamp-answers.txt .`

In retrofit mode the stamp skips files the repo already has (it reports them);
merge the framework content into those by hand in phase 2. **A repository that
carries `AGENTS.md` and no `CLAUDE.md`** governs its agents through that file,
and Claude Code reads `CLAUDE.md` where both exist: tell the user BEFORE running
the stamp that the new `CLAUDE.md` will shadow their `AGENTS.md` (the stamp
prints the same notice before its first write and leaves the file as it is),
and merge what it says into `CLAUDE.md` in phase 2. Where the repository has no
`AGENTS.md`, the stamp writes the pointer one, as for a new instance. An existing
`.github/CODEOWNERS` is one of those: the stamp leaves it, and phase 2 adds the
four protected paths (`/.githooks/`, `/.claude/`, `/specs/attest/`,
`/.github/`) under the team's own owner rather than replacing the file. The
forge check, its workflow and the `gates` block are stamped as for a new
instance (edition v1.14); requiring the check on the trunk is the team's act at
the forge, named in the hand-off. The stamp emits no
/scaffold skill: the project is already scaffolded, and the health check ships
as /setlist:validate. Fill gate_command in `.claude/sdd.json` with the
repo's real full-suite command and set `scaffolded` to true once it runs, so
the gates bind. Verify that it runs the way the hooks will run it (it checks for
jq first, because without jq the command reads as empty and an empty command
"passes"):

    command -v jq >/dev/null 2>&1 || { echo "jq is not installed, so the gate command was not read: install jq first"; false; } && { ( eval "$(jq -r .gate_command .claude/sdd.json)" ) >/dev/null 2>&1; echo $?; }

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
