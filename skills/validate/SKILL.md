---
name: validate
description: Idempotent framework health check of the instance (Part 6). Reports findings, fixes nothing without approval.
---

You are the framework health check (Part 6 of the committed edition). This
command is a thin binding: the check list lives here, project facts come from
`.claude/sdd.json` (role paths, trunk, gate command), and on any conflict the
edition wins. Load the full Part when in doubt:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 6`

Run any time; idempotent. Report findings as a list ordered by severity, and
fix nothing without approval.

Open the report by stating the plugin version you are operating from and
whether it is the newest one available: run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-skew.sh"` and quote its verdict. A
session binds its plugin tree at session start, so a health check run from a
stale session is reporting on the wrong tree, and every check below inherits
that. SKEW is a finding in its own right, above all the others, and its fix is
to restart the session rather than to change anything in the repo.

**Structural by design.** This check verifies shape: files in place, sections
present, wiring intact, config coherent. It does not judge semantic consistency
(a plan that contradicts its spec, criteria that miss the goal); that is
Planner work at spec time. Domain checks an instance accumulates (a shellcheck
sweep, a stack-specific hygiene rule) live in an instance-owned skill under the
instance's own name, never in a copy of this command.

Checks:

1. `.claude/settings.json` parses as JSON and still carries the permission
   rules (deny on .env reads; ask on push, hard reset, force push, rm -rf).
2. The four stamped hooks are present in `.claude/hooks/` and wired in
   settings.json: scope-hook on Write|Edit|MultiEdit|NotebookEdit
   (PreToolUse), commit-gate and close-gate on Bash (PreToolUse),
   regrounding-hook on SessionStart. A disabled or missing hook is a finding,
   not an error: report it with the settings line that would re-enable it.
   The pre-1.0.3 matcher `Write|Edit` is a finding (NotebookEdit writes files
   past the trunk rule), as is any hook entry with no explicit `timeout` (a
   timed-out hook is a skipped gate); both are fixed by re-wiring from the
   current template.
3. `.claude/sdd.json` parses, names the src and tests role paths (`roles.src`,
   `roles.tests`, each a string or a list of strings) and the `trunk`, and
   carries a non-empty `gate_command` once `scaffolded` is true. A role path
   of `"."` is a finding: the scope hook ignores it by design (Part 6);
   recommend enumerating the real code paths as a list.
4. Required files exist: CLAUDE.md, README.md, ROADMAP.md, RUNBOOK.md,
   DECISIONS.md, .gitignore, .env.example, specs/STATUS.md, specs/TEMPLATE.md,
   the steering docs, and exactly ONE committed edition file at the repo root:
   `setlist.md` (an instance not yet upgraded to the setlist cutover carries
   the edition file under its original pre-cutover name instead; still
   exactly one, and any name other than setlist.md is a finding recommending
   /setlist:upgrade).
5. specs/STATUS.md has its five bounded sections (Current state, Spec
   inventory, Open chores, Open questions for the Planner, Pointers) AND
   passes row discipline: inventory notes and chore archive lines are single
   lines, and no resolved item lingers under Open questions.
6. steering/structure.md contains an architecture diagram (a mermaid block).
7. .gitignore does not exclude `.claude/`.
8. No [PHASE 2 SLOT: ...] markers remain anywhere in the instance (a leftover
   slot means tailored generation skipped a file).
9. DECISIONS.md has its index table, and no INFERRED row lingers past the flip
   ceremony (retrofits only).
10. No stale generated skills linger: `.claude/skills/checkpoint/` and
    `.claude/skills/validate/` were removed by the plugin-era migrations
    (their duties ship as /setlist:checkpoint and /setlist:validate);
    report any survivor with the removal step from the upgrade protocol.
11. Binding dependencies are installed: `jq` resolves on PATH (all four
    stamped hooks need it; since plugin 1.0.1 the three gates FAIL CLOSED
    without it, denying the writes, commits, and merges they govern rather
    than allowing them unchecked, and the re-grounding pointer says so at
    session start, so a missing jq presents as a blocked session rather than
    silent damage), and, when `.claude/skills/browser-qa/` exists,
    Playwright resolves (`npx playwright --version`) with its Chromium
    installed. Report the exact install command for anything missing; install
    nothing yourself.
12. The instance records which plugin stamped it: `.claude/sdd.json` carries
    `plugin.version`. An instance stamped before 1.0.2 records none, which is a
    finding recommending `/setlist:upgrade` (the refresh records it), not an
    error. When a version IS recorded and it is OLDER than the plugin this
    session runs, the instance is carrying stale enforcement files and the same
    recommendation applies. When it is NEWER, say so plainly and recommend
    nothing yet: the instance was refreshed by a newer plugin than this session
    holds, so this session is the stale party, and any refresh it ran would
    reinstall older hooks over newer ones.

## Gotchas (field-observed)

- A finding is not always a framework defect. A missing SessionStart wiring
  turned out to be an uncommitted local edit, correctly identified by diffing
  settings.json against git history before reporting. Classify each finding
  as committed drift or local edit first; the recommended fix differs, and
  restoring still requires approval either way.
