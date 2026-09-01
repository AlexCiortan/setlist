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
    stamped hooks need it; since plugin 1.0.1 the three gates report their verdict and PERMIT (advisory since v1.7; the GIT hooks are what refuse, and they fail closed without jq)
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
13. The `release` block is COHERENT (Part 6, the release rail). An absent block
    is NOT a finding: it reads as `model: none`, which is the default and the
    right answer for an instance that ships nothing yet. What is checked is that
    a DECLARED model has the marker it claims:
    - `model` is one of `none`, `tags`, `version-file`. Any other value is a
      finding: the skills cannot act on a model they do not know, and guessing
      one would govern a release nobody described.
    - `tags` with no tag matching the declared pattern: report as INFORMATION
      before the first release, a finding after one. A project that declared the
      model and has not yet cut anything is in a normal state, and a check that
      cannot tell those apart trains people to ignore it.
    - `version-file` with no file at the declared path: a finding, always. That
      model's whole claim is that the file at that path identifies what users
      run, so an absent file makes invariant (b) unsatisfiable rather than
      merely unexercised. The asymmetry with `tags` is deliberate.
    - A marker fact that is present but EMPTY (an empty tag pattern, an empty
      path) is a finding rather than an absent marker: it is a declaration
      somebody started and did not finish.
14. Every PARKED row in the STATUS inventory states BOTH a reason and a revisit
    trigger in its note (Part 5). A PARKED row missing either is a finding: the
    state exists to record a decision, and a row with no trigger is an abandoned
    branch with a label on it, which is exactly what the state was introduced to
    stop being invisible. Report the row and what it is missing; do not invent
    the trigger.
15. If `.claude/sdd.json` declares `identity.user_email`, report it beside the
    machine's current `git config user.email` as INFORMATION when they match.
    When they DIFFER, say so plainly: the commit gate will WARN on the next
    commit, and NOTHING refuses it: the identity comparison exists only in the advisory
    commit gate, and no git hook or the trunk audit reads `user.email` at all. Say that
    plainly, because this declaration has no enforcing layer; learning
    that during a health check is cheaper than learning it mid-close. An absent key is not a finding; the check is opt-in and most
    projects will not want it.
16. The ACTIVE spec carries a `Spec-hash:` field (Part 6). Its ABSENCE is
    INFORMATION, not a finding: specs authored before edition v1.7 do not have
    one and acquire it on their next REVISED cycle. Do not recompute or write
    the value here; that is checkpoint's job at a lifecycle transition, and a
    health check that silently re-stamps a hash would erase the very drift the
    field exists to surface.
17. If `.claude/sdd.json` declares `"attestation": {"required": true}`, the
    ACTIVE spec has an approval attestation at `specs/attest/NNNN.json` with its
    `.sig` beside it (Part 6). **Presence is INFORMATION and absence is not a
    finding**, on the same rule item 16 states and for the same reason: a
    project that has not turned the feature on has nothing missing, and a spec
    approved before the project turned it on acquires one on its next lifecycle
    transition. **Never write or re-sign one here.** That is checkpoint's job at
    an approval, in a session where a human is present, and a health check that
    quietly produced an approval would be manufacturing the exact thing the
    mechanism exists to make somebody do deliberately.

17. **The git-hook boundary is LIVE** (Part 6). The guarantee is the push-time
    trunk audit, the per-merge hooks are its early warning, and all three parts
    below have to hold for either to run at all:
    - `.githooks/` exists and carries `pre-commit`, `pre-merge-commit`,
      `pre-push` and `setlist-hook-lib.sh`, and the three hooks are
      EXECUTABLE. Git skips a non-executable hook silently, so a mode bit is
      the difference between a boundary and a decoration.
    - `git config core.hooksPath` is `.githooks`. Without it git runs
      `.git/hooks` and every file above is inert.
    - `git config merge.ff` is `false`. Without it a fast-forward merge fires
      NO hook at all and walks unreviewed work onto the trunk.
    Any of the three missing is a FINDING, not information: unlike the release
    block or the identity key, this is not opt-in, and an instance that has lost
    it is running with the advisory layer only while the edition says otherwise.
    Both config settings live in `.git/config`, which is not cloned, so a fresh
    clone legitimately lacks them and the fix is to re-run the refresh.
    Report what is missing and the exact command that restores it.

18. **The status record versus the page** (Part 3, edition v1.12). In a
    structured instance (`.claude/status.json` present), cross-check the
    record against specs/STATUS.md: a spec whose record token and inventory
    row disagree, a chore done in one and open in the other. **Divergence is
    INFORMATION, never a finding that blocks**, matching item 16's posture and
    for the load-bearing reason: the machine acts on the record, the page is
    for people, and a blocking sync check would make the human page
    load-bearing again, which is the disease the record cures. Report each
    divergence with both values so the human can fix the page (or discover the
    hand edit). The record's ABSENCE is not information and not a finding:
    a legacy instance is a supported state. A record that is present and
    MALFORMED is a FINDING: every gate that reads it refuses, so the instance
    cannot close anything until it is fixed, and this check is the friendly
    version of the message the hooks will deliver anyway.
19. **Double declaration** (Part 6, edition v1.12): one file in two specs'
    `Owns:` sets, or in a spec's set and a chore's `files`. INFORMATION, never
    a finding: the audit checks coverage per closing spec, so a double
    declaration is legal and sometimes honest (a file that genuinely changed
    hands), and refusing it would need a cross-spec read at declaration time
    whose cost nobody has measured. Report the file and both owners; the human
    decides whether it is a handoff or a lie.

## Gotchas (field-observed)

- A finding is not always a framework defect. A missing SessionStart wiring
  turned out to be an uncommitted local edit, correctly identified by diffing
  settings.json against git history before reporting. Classify each finding
  as committed drift or local edit first; the recommended fix differs, and
  restoring still requires approval either way.
