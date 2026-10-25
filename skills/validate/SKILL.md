---
name: validate
description: Idempotent framework health check of the instance (Part 6). Reports findings, fixes nothing without approval. With --board, adds the board.
---

You are the framework health check (Part 6 of the committed edition). This
command is a thin binding: the check list lives here, project facts come from
`.claude/sdd.json` (role paths, trunk, gate command), and on any conflict the
edition wins. Load the full Part when in doubt:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 6`

Run any time; idempotent. Report findings as a list ordered by severity, and
fix nothing without approval.

The check list below is read-only and mechanical, so it runs on the delegated
tier (Part 2, edition v1.21): hand it to a subagent through the Agent tool with
`model: haiku`, with this file's path, and report what it returns; check 24's
probe stays in the session, since it measures the session's own models and
spends quota the user is told about first. What a finding means, and anything to fix, stays with you. A journal
line names the delegated run, the model it resolved to, its tokens, and its
cost where the harness reports one. Checks 18, 21, 22 and 24 keep their full text in
`${CLAUDE_PLUGIN_ROOT}/skills/validate/references/checks.md`: hand the subagent that path too. Never hand the check list to a fork: a fork
runs on this session's model, not `haiku`, and the journal line's model field
is the check.

Open the report by stating the plugin version you are operating from and
whether it is the newest one available: run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-skew.sh"` and quote its verdict. A
session binds its plugin tree at session start, so a health check run from a
stale session is reporting on the wrong tree, and every check below inherits
that. SKEW is a finding in its own right, above all the others, and its fix is
to restart the session rather than to change anything in the repo.

Structural by design. This check verifies shape: files in place, sections
present, wiring intact, config coherent. It does not judge semantic consistency
(a plan that contradicts its spec, criteria that miss the goal); that is
Planner work at spec time. Domain checks an instance accumulates (a shellcheck
sweep, a stack-specific hygiene rule) live in an instance-owned skill under the
instance's own name, never in a copy of this command.

With `--board` (edition v1.22), after the checks below, run the board and print
its report under its own heading: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh"`
(the same script `/setlist:board` runs; `--offline` passes through). It reads
the trunk and the remote, names every collision it can see, and refuses
nothing; its lines are information, never findings, and it exits 2 only when it
could not read, which is reported as the one line it prints.

Checks:

1. `.claude/settings.json` parses as JSON and still carries the permission
   rules (deny on .env reads, and since 2.6.0 the one Bash spelling, the
   deny entry for reading environment files, beside them; ask on push, hard reset, force push, rm -rf).
   The `_comment` key in the permissions block is the deny list's own note
   (a deny list is a spelling list) and is not a finding; a `//` comment
   anywhere in the file IS one, because the harness then drops every rule.
2. The four stamped session hooks are present in `.claude/hooks/` and wired in
   settings.json: scope-hook on Write|Edit|MultiEdit|NotebookEdit
   (PreToolUse), bypass-deny on Bash (PreToolUse, 2.8.0),
   regrounding-hook on SessionStart, stop-hook on Stop (2.6.0; no matcher).
   An instance stamped before 2.6.0 lacks stop-hook, and one stamped before
   2.8.0 lacks bypass-deny, until `/setlist:upgrade` delivers it and its
   settings entry is restored from the template. A
   disabled or missing hook is a finding,
   not an error: report it with the settings line that would re-enable it.
   The pre-1.0.3 matcher `Write|Edit` is a finding (NotebookEdit writes files
   past the trunk rule), as is any hook entry with no explicit `timeout` (a
   timed-out hook is a skipped gate); both are fixed by re-wiring from the
   current template.
3. `.claude/sdd.json` parses, names the src and tests role paths (`roles.src`,
   `roles.tests`, each a string or a list of strings) and the `trunk`, and
   carries a non-empty `gate_command` once `scaffolded` is true, and, when it
   carries a `gates` block (2.6.0, the three tiers), that block is an object
   of three strings `commit`, `close`, `push` with `close` and `push` non-empty
   once `scaffolded` is true (an empty tier there is the stamped default, not a
   declaration, and the git hook refuses every close on it; a block of any
   other shape is refused `SLH-GATES-SHAPE` by the hooks). An absent block is
   not a finding: it reads as the single `gate_command` at `close` and `push`,
   and `/setlist:upgrade`'s refresh writes it. A role path
   of `"."` is a finding: the scope hook ignores it by design (Part 6);
   recommend enumerating the real code paths as a list.
   A role path that does not exist, or that holds no tracked file (`git ls-files
   -- <path>` prints nothing), is a finding too: it governs no code while the
   instance reads armed (a retrofit stamped with the default `src` and `tests` on
   a project laid out otherwise). Name it with the retrofit skill's inventory
   scan beside it (the tracked source files by top-level directory, most first),
   which `refresh-instance.sh` prints in its report, and recommend the real paths.
4. Required files exist: CLAUDE.md, README.md, ROADMAP.md, RUNBOOK.md,
   DECISIONS.md, .gitignore, .env.example, specs/STATUS.md, specs/TEMPLATE.md,
   the steering docs, and the committed edition at the repo root:
   `setlist.md`, `setlist-operations.md` and `setlist-changelog.md` (the
   edition is three files since plugin 2.13.0). A `setlist.md` alone is an
   edition from before that split, and an instance not yet upgraded to the
   setlist cutover carries one edition file under its original pre-cutover
   name instead; either is a finding recommending /setlist:upgrade.
5. specs/STATUS.md has its five bounded sections (Current state, Spec
   inventory, Open chores, Open questions for the Planner, Pointers) AND
   passes row discipline: inventory notes and chore archive lines are single
   lines, and no resolved item lingers under Open questions.
6. The L2 container view exists as a Mermaid block in the document that holds it:
   `steering/structure.md` for an ordinary application, or, where the instance
   records that its L2 lives in its own README (the project draws itself for
   readers who are not its maintainers), that file. Report the absence against
   the home the instance actually uses; do not report `structure.md` missing a
   diagram it was never meant to carry.
7. .gitignore does not exclude `.claude/`.
8. No [PHASE 2 SLOT: ...] markers remain anywhere in the instance (a leftover
   slot means tailored generation skipped a file).
9. DECISIONS.md has its index table, and no INFERRED row lingers past the flip
   ceremony (retrofits only).
10. The `verify` skill is stamped (plugin 2.12.0): `.claude/skills/verify/SKILL.md`
    exists. Compare it with `cmp -s` against
    `${CLAUDE_PLUGIN_ROOT}/templates/claude/skills/verify/SKILL.md`. Absent is a
    finding recommending `/setlist:upgrade`, whose refresh delivers it; a copy
    that differs is information naming the file (a hand edit, or an older copy
    the refresh replaces with a backup). Say what it is when you report it:
    Claude Code asks for a skill of this name before a commit, and the skill runs
    the gate command and reports. It persuades; the git hooks refuse.
    No stale generated skills linger: `.claude/skills/checkpoint/` and
    `.claude/skills/validate/` were removed by the plugin-era migrations
    (their duties ship as /setlist:checkpoint and /setlist:validate);
    report any survivor with the removal step from the upgrade protocol.
11. Binding dependencies are installed: `jq` resolves on PATH (all four
    stamped hooks need it), and, when `.claude/skills/browser-qa/` exists,
    Playwright resolves (`npx --no-install playwright --version`, never a download) with its Chromium
    installed. Without jq the session hooks report their verdict and PERMIT
    (the scope hook says so in its own text, the bypass deny is silent; both
    are advisory since v1.7), and the re-grounding pointer says so at session
    start. The git hooks fail closed, so commits, merges and pushes are
    refused until it is installed. Report the exact install command for
    anything missing; install nothing yourself. Read `claude --version` too,
    and report it beside the floor the plugin's README names: read the floor
    from the "Requires Claude Code" sentence of `${CLAUDE_PLUGIN_ROOT}/README.md`
    rather than from memory, since that sentence is the one copy. Below the
    floor, name the update. Below 2.1.277, report that the re-grounding pointer
    may be partly dropped on a resumed, continued or cleared session (the
    harness fixed that in 2.1.277), and name the update. Below 2.1.289, report
    that a deny or ask rule in `.claude/settings.json` can be skipped under
    sandbox auto-allow when the command carries a variable-assignment prefix
    (`X=1 rm -rf ...`), so the stamped ask rules in front of `git reset --hard`
    and `rm -rf` are advisory there, and name the update. Below 2.1.295, report
    that the bypass deny's `"onFailure": "block"` is ignored there, so a bypass
    deny that times out or cannot start lets the command through, and name the
    update. Where `.claude/settings.json`'s bypass-deny entry carries no
    `onFailure` key, report the one edit the refresh prints for it. All four are
    reports, not findings.
12. The instance records which plugin stamped it: `.claude/sdd.json` carries
    `plugin.version`. An instance stamped before 1.0.2 records none, which is a
    finding recommending `/setlist:upgrade` (the refresh records it), not an
    error. When a version IS recorded and it is OLDER than the plugin this
    session runs, the instance is carrying stale enforcement files and the same
    recommendation applies. When it is NEWER, say so plainly and recommend
    nothing yet. The instance was refreshed by a newer plugin than this session
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
    trigger in its note (Part 5). A PARKED row missing either is a finding. The
    state exists to record a decision, and a row with no trigger is an abandoned
    branch with a label on it, which is exactly what the state was introduced to
    stop being invisible. Report the row and what it is missing; do not invent
    the trigger.
15. If `.claude/sdd.json` declares `identity.user_email`, report it beside the
    machine's current `git config user.email` as INFORMATION when they match.
    When they DIFFER, say so plainly: this item is the only place the declared
    identity is compared at all (since 2.8.0 nothing warns at commit time), and
    NOTHING refuses a commit made under the wrong one: no git hook and not the trunk
    audit reads `user.email`. Say that plainly, because this declaration has no
    enforcing layer; learning that during a health check is cheaper than learning
    it mid-close. An absent key is not a finding; the check is opt-in and most
    projects will not want it. Where the ACTIVE spec's `Driver:` line (edition
    v1.22) names a handle other than the declared one, report both as
    INFORMATION: a teammate may hold the spec.
16. The ACTIVE spec carries a `Spec-hash:` field (Part 6). Its ABSENCE is
    INFORMATION, not a finding: specs authored before edition v1.7 do not have
    one and acquire it on their next REVISED cycle. Do not recompute or write
    the value here; that is checkpoint's job at a lifecycle transition, and a
    health check that silently re-stamps a hash would erase the very drift the
    field exists to surface. Report its `Driver:` line (edition v1.22) beside it,
    as INFORMATION; an absent line is information too, for a spec flipped before
    the line existed, and nothing here writes one.
17. If `.claude/sdd.json` declares `"attestation": {"required": true}`, the
    ACTIVE spec has an approval attestation at `specs/attest/NNNN.json` with its
    `.sig` beside it (Part 6). **Presence is INFORMATION and absence is not a
    finding**, on the same rule item 16 states and for the same reason: a
    project that has not turned the feature on has nothing missing, and a spec
    approved before the project turned it on acquires one on its next lifecycle
    transition. **Never write or re-sign one here.** That is checkpoint's job at
    an approval, in a session where a human is present, and a health check that
    produced an approval unseen would be manufacturing the exact thing the
    mechanism exists to make somebody do deliberately.

18. **The git-hook boundary is LIVE** (Part 6): `.githooks/` carries the three
    hooks, `core.hooksPath` and `merge.ff` are set, and the audit's declared
    baseline is reported. Run it from `${CLAUDE_PLUGIN_ROOT}/skills/validate/references/checks.md`, check 18.
19. **The status record versus the page** (Part 3, edition v1.12). In a
    structured instance (`.claude/status.json` present), cross-check the
    record against specs/STATUS.md: a spec whose record token and inventory
    row disagree, a chore done in one and open in the other. **Divergence is
    INFORMATION, never a finding that blocks**, matching item 16's posture and
    for the reason that decides it: the machine acts on the record, the page is
    for people, and a blocking sync check would make the human page
    essential again, which is the disease the record cures. Report each
    divergence with both values so the human can fix the page (or discover the
    hand edit). The record's ABSENCE is not information and not a finding:
    a legacy instance is a supported state. A record that is present and
    MALFORMED is a FINDING. Every gate that reads it refuses, so the instance
    cannot close anything until it is fixed, and this check is the friendly
    version of the message the hooks will deliver anyway.
20. **Double declaration** (Part 6, edition v1.12): one file in two specs'
    `Owns:` sets, or in a spec's set and a chore's `files`. INFORMATION, never
    a finding. The audit checks coverage per closing spec, so a double
    declaration is legal and sometimes legitimate (a file that really changed
    hands), and refusing it at declaration time would need a cross-spec read
    whose cost nobody has measured. The one overlap the audit DOES refuse is
    at close time, two specs in flight at once (`SLH-OWNS-OVERLAP`, plugin
    2.11.0): a second close whose branch never took the first's change. Report
    the file and both owners; the human decides whether it is a handoff or a
    lie. Since edition v1.22 the item reaches the remote's spec branches too:
    run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh"` and report each
    `overlap:` line it prints beside the local ones, still as INFORMATION.
21. **The two wiring files the refresh never replaces** (2.6.0): the forge
    check's workflow and `.github/CODEOWNERS`, compared with the plugin's
    templates and reported. Run it from `${CLAUDE_PLUGIN_ROOT}/skills/validate/references/checks.md`, check 21.
22. **The diagram reports** (projects with `docs/diagrams/`): reports only,
    never blocking findings; where the directory does not exist, report
    nothing. Run it from `${CLAUDE_PLUGIN_ROOT}/skills/validate/references/checks.md`, check 22.
23. **What loads from outside the instance** (plugin 2.11.0). Name the skills and
    plugins this machine loads into every session beside the instance's own:
    the directories under `~/.claude/skills/` (the user's) and
    `~/.claude/skills/synced/<bucket>/` (synced from the account), the plugin
    keys in `~/.claude/plugins/installed_plugins.json`, and the directories
    under `~/.claude/plugins/synced/<bucket>/` (`$CLAUDE_CONFIG_DIR` in place of
    `~/.claude` where it is configured). The refresh's report prints the same list
    (`refresh-instance.sh .`, under "outside this instance"). Names only: read
    no content, and say that no Setlist check compares these files, so a stale
    edition claim or a model binding living there is in no report. This is a
    report, not a finding.
24. **The model binding answers now** (Part 2; plugin 2.11.0): where the
    settings set `"model": "opusplan"`, say first that it spends two short
    headless sessions, then probe both phases and name any phase off its tier,
    and the Haiku generation of this check's own run. Run it from
    `${CLAUDE_PLUGIN_ROOT}/skills/validate/references/checks.md`, check 24.
25. **The system spec** (edition v1.22). Where `.claude/sdd.json` records
    `system_spec`, read it. A path is resolved against the instance root: one
    that does not exist or cannot be read is a finding, naming the path and the
    fix (record the path `system.md` has from here, or restore the file). A URL
    is reported as recorded and not fetched; tell the user to open it. Then read
    spec 0001's `Cites:` header lines: none naming the recorded system spec is a
    finding. Where the key is absent, report nothing. No hook reads the key or
    the citation; this check is the one reader.

## Gotchas (field-observed)

- A finding is not always a framework defect. A missing SessionStart wiring
  turned out to be an uncommitted local edit, correctly identified by diffing
  settings.json against git history before reporting. Classify each finding
  as committed drift or local edit first; the recommended fix differs, and
  restoring still requires approval either way.
