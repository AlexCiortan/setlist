---
name: upgrade
description: Upgrade a framework instance to the edition bundled in this plugin (Part 8c)
disable-model-invocation: true
---

You are upgrading a repo that already runs an earlier edition of the framework.
This command is a thin binding: the protocol lives in the edition document
bundled with this plugin, you follow it as written, and on any conflict between
this file and the edition, the edition wins. Never fork the protocol.

Load the protocol first. Run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8c`
and follow that text (the Upgrade Protocol) for everything below. An upgrade is
a planning-and-documentation act: reading src is permitted, editing it is not.

## 0. State the plugin you are operating from, before anything else

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-skew.sh"` and report its output
verbatim to the user before touching a file. A session binds its plugin tree at
session start, so a session opened before a marketplace update keeps running the
old tree, including these very instructions. If the check reports SKEW, stop:
restart the session and run the upgrade there. If it reports that the state is
unverified, say that too, in those words; unverified is not clean, and the
refresh below will say the same thing again rather than let it pass unnoticed.

## 1. Establish old and new

- The OLD edition is the framework markdown committed in this repo:
  `setlist.md` (a pre-cutover instance carries it under the edition's
  original filename instead, one framework markdown at the root; an instance
  stamped or upgraded since plugin 2.13.0 carries the three files named
  below). Read its version from inside the file (the Edition header line, or the
  Version line in older editions); do not ask the user for it.
- The NEW edition is the one bundled at the plugin root, three files since
  plugin 2.13.0: `"${CLAUDE_PLUGIN_ROOT}"/setlist.md` (the core, Parts 1 to
  6), `setlist-operations.md` (Parts 7 to 10 and Appendices A to C) and
  `setlist-changelog.md`, each carrying the version on its Edition header line.
  Read the delta from `"${CLAUDE_PLUGIN_ROOT}"/setlist-changelog.md`: its
  Changelog section is the authoritative delta list. An instance upgrading
  from an edition before the split carries one `setlist.md` holding its own
  Changelog; one already on three files carries it in its own
  `setlist-changelog.md`.
- Ask conversationally: how was the old edition adopted (a chore number, or
  the original bootstrap/retrofit), and which ADR records it, if any.
- **When the editions match but the plugin has moved** (a plugin patch that
  changed stamped files, the first being 1.0.1's fail-closed hooks), this is
  not a full migration. Run the enforcement-file refresh in section 3 and
  nothing else: hooks are byte-copied into the instance at stamp time, so a
  plugin release fixes new instances only and an existing one keeps its old
  hook bytes until this refresh runs. Close it as an ordinary docs-only chore
  with a one-line ADR naming the plugin version, not an umbrella migration
  ADR. As of plugin 1.0.2 the instance records which plugin stamped it
  (`.plugin.version` in `.claude/sdd.json`), and the refresh script reads that
  record to establish direction; an instance stamped earlier records nothing,
  which the script treats as a move forward and repairs.

## 2. Run Part 8c as written

All mechanics come from the loaded Part: prefer the window between specs, or
pause the ACTIVE spec cleanly with a resume prompt; diff the repo's framework
files against the new edition and list every gap; one structured round for
real forks only; execute on a single chore branch (`chore/vNN-migration`);
relocate verbatim under provenance banners, never rewrite; style rules
forward-only; one umbrella ADR with its index row; replace the committed
framework markdown with the new edition in the same commit (as of the setlist
cutover the committed copy is always named `setlist.md`, so an edition file
carrying an older name is git-renamed to `setlist.md` in that commit). Since
plugin 2.13.0 the edition is three files: the instance's `setlist.md` is
replaced in place by the plugin root's, and `setlist-operations.md` and
`setlist-changelog.md` are copied beside it, all three in that one commit;
record accepted
deviations; close like any chore with docs-only gates.

## 3. Plugin-era migration (part of the same chore)

When the instance predates the setlist cutover (it carries `/sdd-framework:` or
`/sdd:` command references), rewrite every one of them to `/setlist:` in
RUNBOOK.md, CLAUDE.md, .gitignore comments, and instance-owned skills, and
record the rewrite in the umbrella ADR.

When the instance predates this plugin, also:

- Remove the generated per-project checkpoint skill
  (`.claude/skills/checkpoint/`) and rewrite every RUNBOOK.md and CLAUDE.md
  reference from `/checkpoint` to `/setlist:checkpoint`.
- Remove the generated per-project validate skill (`.claude/skills/validate/`),
  the same promotion one edition later: the health check ships as
  `/setlist:validate`. Domain adaptations the instance added to its copy
  (extra checks, stack-specific notes) are relocated FIRST into an
  instance-owned skill under the instance's own name, then the directory is
  removed; rewrite `/validate` references to `/setlist:validate`
  (RUNBOOK.md, CLAUDE.md, .gitignore comments).
- Stamp or refresh the enforcement files with the script, never by hand:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-instance.sh" .` reports what
  would change, and `--apply` before the path performs it. The script
  establishes DIRECTION from the version the instance records, and refuses to
  move an instance backwards. A byte comparison alone cannot tell newer from
  older, which is how a session once installed the older hooks over the newer
  ones and reported success. It also refuses when it cannot determine either
  version, rather than falling through to the copy. Read its report before
  applying. Any file listed as differing may be a deliberate instance edit, and
  Part 8c is explicit that a customized stamped copy is a fork to surface in
  the umbrella ADR, never a file to silently overwrite. On --apply the four
  session hooks (scope-hook, regrounding-hook, since 2.6.0 stop-hook, and since
  2.8.0 bypass-deny) are copied byte for byte, the trunk audit and the forge check
  beside them, the git-hook boundary is delivered (`.githooks/` plus
  `core.hooksPath` and `merge.ff`, see the boundary bullet below), the two
  wiring files (`.github/workflows/setlist-forge-check.yml`,
  `.github/CODEOWNERS`) are delivered when ABSENT and otherwise reported by
  file and LEFT AS IS (they are the team's; an ownership file that does not
  name `/.github/` is told so by path), the `gates` block is written on an
  instance that lacks it (see the v1.14 bullet below), and the plugin
  version is recorded in `.claude/sdd.json`.
  **Since 2.8.0 the refresh also REPORTS the two retired hooks**
  (`.claude/hooks/commit-gate.sh`, `.claude/hooks/close-gate.sh`) and the
  `settings.json` entries that still run them, and prints the exact edit that
  removes exactly those; it never removes them itself, and the report changes no
  exit status. Show the human the report and let them run the printed edit, then
  re-run the refresh; a fork of a retired hook is reported and left alone.
  **Exit code 3 means the refresh applied INCOMPLETELY**: the hook bytes and the
  version record are current, but `.claude/settings.json` still needs an edit the
  script named and deliberately did not make (that file carries the instance's own
  permissions and model settings, so it is never machine-rewritten). Make the named
  edits by hand and re-run until it exits 0. Do not report the upgrade as done on a
  3: part of what the version promises is not in force, and the whole point of the
  exit code is that it cannot be read past. Wire the hooks in
  `.claude/settings.json` exactly as
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/settings.json.tmpl` shows (scope
  hook on Write|Edit|MultiEdit|NotebookEdit and bypass deny on Bash, both
  PreToolUse; regrounding hook on SessionStart, no matcher; stop hook on Stop,
  no matcher; every
  hook entry carries an explicit `timeout`, since a timed-out hook is a
  skipped gate). An instance whose settings still carry the pre-1.0.3 matcher
  `Write|Edit` or hook entries with no timeout takes both updates as part of
  the refresh. The same template also shows
  the `fallbackModel` chain (`["default"]`, v1.6); add the line when the
  instance's settings.json lacks it. Create
  `.claude/sdd.json` from its template if missing, BEFORE running the refresh
  (the script refuses without it, since that file is where the version record
  lives), with this repo's real src
  and tests role paths, the full-suite gate_command, and scaffolded=true (the
  project exists; the gates should bind now). Whether created or already
  present, sdd.json must carry the `trunk` field: detect the trunk branch
  NAME and record the plain name, never a ref path. ASK THE BRANCH THE PROJECT
  MERGES ONTO, NOT THE REMOTE'S DEFAULT. These are different questions and this
  skill used to lead with the wrong one: `git symbolic-ref --short
  refs/remotes/origin/HEAD | sed 's#^[^/]*/##'` returns the REMOTE's default
  branch name, which on a git-flow shaped repository is `main` while the branch
  actually worked on and merged onto is `trunk` or `develop`. Recording `main`
  there names a real-but-wrong local branch, and until 2026-08-05 every layer
  then concluded "not on the trunk" and no-opped in silence on every close
  (v1.7 re-leg, F3). Prefer, in order:

  1. the branch you are on now, if it is the one this project merges onto:
     `git symbolic-ref --short HEAD`
  2. the local branch whose upstream is the remote's default, which is the
     git-flow answer: `git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads`
     and take the one whose upstream matches `origin/HEAD`
  3. the remote default, `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^[^/]*/##'`
  4. main

  Record the plain name, never a ref path: recording the full ref path used to
  disable BOTH hooks in silence, because they compare it against the branch
  name you are standing on and the two can never be equal. The hooks now reduce
  a ref spelling and refuse a trunk that names no local branch, but they do NOT
  recognise the trunk under a different local name: a version that did so, by
  what the branch TRACKS, refused ordinary merges on every branch cut with
  `git checkout -b <name> origin/main` and was removed on 2026-08-07. So
  writing the right value here is not a convenience, it is the whole of the
  trunk detection, and the git-flow case is a documented limitation when it is
  wrong. The scope
  and close hooks read this field instead of assuming main. Note that hooks load at session start, so the
  gates bind from the NEXT session onward.
- **Read the refresh's edition and binding drift report, and quote it.** The same
  run prints, under the heading `edition and binding drift`, every line in this
  instance's `CLAUDE.md`, `RUNBOOK.md`, `specs/TEMPLATE.md` and instance-owned
  skills that names an edition other than the one you are moving to
  (`SLH-EDITION-DRIFT`), or that names a model-ladder tier beside a model alias
  the new edition's Part 2 binds to a different tier (`SLH-BINDING-DRIFT`), each
  with its file, its line, the string found and the value the edition holds.
  Quote the block to the human verbatim, the way section 0 quotes the skew check.
  Then take the lines one at a time: a CURRENT-STATE sentence is rewritten to the
  value named beside it, in this chore's own commits; a PROVENANCE citation (the
  edition a field arrived in) is left as written and recorded as reconciled under
  the umbrella ADR. The report changes no exit status and the script never edits
  your prose, so nothing downstream catches what you skip here: **the migration
  chore does not close while a listed line stands.** Re-run the report after the
  rewrites and quote the clean run. This is the check that would have caught an
  instance whose own `CLAUDE.md` header still named v1.6 after it had been
  upgraded to v1.14, which is in no changelog delta and so in no rewrite list.
  Since plugin 2.11.0 the report reads `AGENTS.md` too, and below it names, under
  `outside this instance`, the skills and plugins this machine loads into every
  session from the user's own directories and the account: no Setlist check
  compares them, so say so when quoting it. Its last line (plugin 2.11.0)
  names Claude Code's `/doctor prompt-audit`, which reads the same files for
  prompts written for older models and for stale paths: that is the other half
  of the question, and running it is the human's choice, not this chore's.
- **Read the verdict delta beside the drift report, BEFORE `--apply`** (plugin
  2.11.0, Part 8c). Run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-instance.sh" --delta .` (`--merges N`
  for another count than 50) and quote its output verbatim. It runs the
  instance's stamped trunk audit and this plugin's over the last 50 merges, each
  under the configuration it would read at the next push (the new side with the
  baseline the refresh would record), in a private clone, and prints both frames,
  what the new edition would refuse that the old allowed, and the reverse. It
  refuses nothing and writes nothing. Walk the human through each listed commit:
  a line in the first list is a push the upgrade will refuse, so it is settled
  (a close record completed, a chore recorded) or accepted as a known refusal in
  the umbrella ADR before the upgrade lands; a line in the second list is history
  the new frame stops judging, which is the purpose of the baseline and worth
  saying. The same auto-mode fact the retrofit skill's observe step records holds
  here: the stamped ask rules still prompt when a session starts in auto mode.
- Refresh `specs/TEMPLATE.md` from the new edition:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" appendix-c` (the template body
  inside the fences). Existing specs are historical text and are not
  retrofitted. **Refresh applies to unmodified stamped copies only** (Part
  8c): a template the instance deliberately domain-adapted is a fork to
  surface, kept as is and recorded under the umbrella ADR's accepted
  deviations, with the new edition's delta folded in by hand where it matters.
- The qa-verifier and spec-reader agents are delivered by the refresh since
  plugin 2.13.0: it copies
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/agents/qa-verifier.md` to
  `.claude/agents/qa-verifier.md` (QA Pass 1, on the delegated tier) and
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/agents/spec-reader.md` to
  `.claude/agents/spec-reader.md` (the pre-build reading at spec approval,
  advisory). Before 2.13.0 the qa-verifier was stamped here by hand where
  missing and a hand-edited copy was kept; a domain-adapted copy is now kept
  as `.setlist-backup` beside the new one, so fold its adaptations back in by
  hand where they matter, and record it as a deviation as above.
- The close-reviewer agent and the `verify` skill are delivered by the
  refresh, not by hand: it copies
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/agents/close-reviewer.md` to
  `.claude/agents/close-reviewer.md` (plugin 2.11.0: `/setlist:checkpoint`
  runs it at every close, and the gates require its block once
  `.claude/sdd.json` records 2.11.0 or later) and
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/skills/verify/SKILL.md` to
  `.claude/skills/verify/SKILL.md` (plugin 2.12.0: Claude Code asks for a
  skill of that name before a commit; it runs the gate command and reports).
  Since 2.12.0 a copy that differs is REPLACED, the previous one kept as
  `.setlist-backup` beside it (a backup an earlier refresh made is kept and
  never overwritten), because the reviewer's tool list moved in that
  release. Quote the refresh's lines for both, and surface a backup it wrote
  as a hand edit to carry forward or drop.
- Stamp `AGENTS.md` if missing, as the qa-verifier above: copy
  `${CLAUDE_PLUGIN_ROOT}/templates/root/AGENTS.md` to `AGENTS.md` at the root
  (plugin 2.11.0: a pointer to `CLAUDE.md` and `setlist.md` for agents that read
  `AGENTS.md`, never a second copy of the golden rules). If a different
  `AGENTS.md` exists, it is the project's: surface the diff instead of
  overwriting, and tell the human that Claude Code reads `CLAUDE.md` where both
  exist.
- **Every dated addition and every edition's delta, v1.7 to v1.22**: read
  `${CLAUDE_PLUGIN_ROOT}/skills/upgrade/references/deltas.md` and walk each entry whose edition or plugin
  version lies after the instance's recorded one, in order. It holds the
  `release` block, the git hooks and their config, the per-push escape, the git
  identity, the `Spec-hash:` field, the attestation block, the diagram half, the
  status record, and the v1.14 to v1.22 deltas, each with the edits it offers and
  what it migrates (most migrate nothing). An entry you skip is an edit the
  instance never receives.

## 4. Instance skill flags (any instance stamped before plugin 1.6)

Read `${CLAUDE_PLUGIN_ROOT}/skills/upgrade/references/instance-skill-flags.md` when the instance's own skills predate
plugin 1.6.

## Gotchas (field-observed)

Read `${CLAUDE_PLUGIN_ROOT}/skills/upgrade/references/gotchas.md` before closing the migration chore.
