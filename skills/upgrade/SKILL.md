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
refresh below will say the same thing again rather than let it pass quietly.

## 1. Establish old and new

- The OLD edition is the framework markdown committed in this repo:
  `setlist.md` (a pre-cutover instance carries it under the edition's
  original filename instead; still exactly one framework markdown at the
  root). Read its version from inside the file (the Edition header line, or the
  Version line in older editions); do not ask the user for it.
- The NEW edition is the one bundled at the plugin root:
  `"${CLAUDE_PLUGIN_ROOT}"/setlist.md`, its version on its Edition header
  line. Its Changelog section is the authoritative delta list.
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
genuine forks only; execute on a single chore branch (`chore/vNN-migration`);
relocate verbatim under provenance banners, never rewrite; style rules
forward-only; one umbrella ADR with its index row; replace the committed
framework markdown with the new edition in the same commit (as of the setlist
cutover the committed copy is always named `setlist.md`, so an edition file
carrying an older name is git-renamed to `setlist.md` in that commit);
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
  move an instance backwards; a byte comparison alone cannot tell newer from
  older, which is how a session once installed the older hooks over the newer
  ones and reported success. It also refuses when it cannot determine either
  version, rather than falling through to the copy. Read its report before
  applying: any file listed as differing may be a deliberate instance edit, and
  Part 8c is explicit that a customized stamped copy is a fork to surface in
  the umbrella ADR, never a file to silently overwrite. On --apply the four
  hooks (scope-hook, commit-gate, close-gate, regrounding-hook) are copied byte
  for byte, the git-hook boundary is delivered (`.githooks/` plus
  `core.hooksPath` and `merge.ff`, see the boundary bullet below), and the plugin
  version is recorded in `.claude/sdd.json`.
  **Exit code 3 means the refresh applied INCOMPLETELY**: the hook bytes and the
  version record are current, but `.claude/settings.json` still needs an edit the
  script named and deliberately did not make (that file carries the instance's own
  permissions and model settings, so it is never machine-rewritten). Make the named
  edits by hand and re-run until it exits 0. Do not report the upgrade as done on a
  3: part of what the version promises is not in force, and the whole point of the
  exit code is that it cannot be read past. Wire the hooks in
  `.claude/settings.json` exactly as
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/settings.json.tmpl` shows (scope
  hook on Write|Edit|MultiEdit|NotebookEdit and commit gate and close gate on
  Bash, both PreToolUse; regrounding hook on SessionStart, no matcher; every
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
- Refresh `specs/TEMPLATE.md` from the new edition:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" appendix-c` (the template body
  inside the fences). Existing specs are historical text and are not
  retrofitted. **Refresh applies to unmodified stamped copies only** (Part
  8c): a template the instance deliberately domain-adapted is a fork to
  surface, kept as is and recorded under the umbrella ADR's accepted
  deviations, with the new edition's delta folded in by hand where it matters.
- Stamp the qa-verifier agent if missing: copy
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/agents/qa-verifier.md` to
  `.claude/agents/qa-verifier.md` (the stamp gives every new instance this
  agent; an upgraded instance gets the same). If a hand-edited copy exists,
  surface the diff instead of overwriting.
- **Add the `release` block to `.claude/sdd.json`** (edition v1.7). Write
  `"release": {"model": "none"}` unless the project already has a release
  practice to declare, appended AFTER the `plugin` block rather than reordering
  the file. `none` is the WRITTEN DEFAULT and not a placeholder: it means users
  run the trunk, which is the true answer for most instances. Do not infer
  `tags` from the presence of tags, or `version-file` from the presence of a
  VERSION file; a model is declared by a person, and `/setlist:validate`
  check 13 will hold whatever is declared to its marker.
- **The GIT HOOKS and their config** (edition v1.7, the enforcement boundary).
  **The refresh script above delivers this; do not install it by hand.**
  `refresh-instance.sh --apply` copies `pre-commit`, `pre-merge-commit`,
  `pre-push` and `setlist-hook-lib.sh` from
  `${CLAUDE_PLUGIN_ROOT}/templates/git-hooks/` into a TRACKED `.githooks/`,
  makes the three hooks executable and DIES if any is not, and sets both
  `git config core.hooksPath .githooks` and `git config merge.ff false`. A
  hand copy is what this bullet used to ask for and it is the worse path: git
  skips a non-executable hook SILENTLY, so a manual install that loses the mode
  bit leaves a boundary that stops nothing and says nothing.
  **Both settings, and the second is not optional**: a fast-forward merge fires
  no git hook at all, so without it `git merge spec/0001-x` walks unreviewed
  work onto the trunk past the boundary.
  What is left for a person here is the VERIFICATION and the warning, not the
  install: confirm `git config core.hooksPath` reads `.githooks` and
  `git config merge.ff` reads `false` after the refresh (`/setlist:validate`
  check 17 asserts exactly this), and warn the human that this is a BEHAVIOURAL
  change they will feel immediately, since merges that used to fast-forward now
  create merge commits. **Tell them about the squash too**: `merge.ff = false`
  implies `--no-ff`, and git refuses that with `--squash`, so
  `git merge --squash <branch>` stops working with
  `fatal: options '--squash' and '--no-ff.' cannot be used together`. The error
  names neither Setlist nor the setting, so an operator who is not told has
  nothing to search for. The workaround is `git merge --ff --squash <branch>`,
  which `pre-commit` still gates because the commit completing a squash reaches
  it. If the instance is not a git work tree the script warns
  and sets neither, which is the one case where a person has to act.
- **Tell the human what the boundary move means.** The PreToolUse gates are now
  ADVISORY, and within the git hooks the GUARANTEE is the push-time trunk audit:
  the two per-merge hooks keep refusing at commit and merge time as early
  warning, and the audit at `pre-push` is what stands between unreviewed work
  and a shared trunk. Nothing is removed and no workflow breaks, but a bypass
  spelling of a session gate, and a route past a per-merge hook, are MAJORs
  rather than release blockers now, and the honest holes (`--no-verify`, the
  forge merge button, the per-clone config) are listed in the edition's Known
  limitations. An upgrade that silently changes what a guarantee means is worse
  than one that says so.
- **Optionally declare a git identity** (BL-007, plugin 1.1.0). If this machine
  holds more than one git identity, add `"identity": {"user_email": "..."}` to
  `.claude/sdd.json` and the commit gate will WARN about a commit made under the
  wrong one. Do NOT add it silently: no key means no check, which is the correct
  default, and writing whatever `git config user.email` currently returns would
  ratify a possibly-wrong value rather than declare an intended one. Ask.
- **Mention the new `Spec-hash:` field, and migrate NOTHING** (BL-005, edition
  v1.7). Existing specs simply lack it and acquire one at their next transition
  to ACTIVE. Do not back-fill hashes across historical specs: a hash computed
  today over a spec approved months ago attests to nothing, and writing one
  would turn an honest "not yet covered" into a false "verified". Tell the human
  the field exists and that the drift warning starts working from the next spec
  that goes ACTIVE.
- **Mention the new `attestation` block, and migrate NOTHING** (KL3, edition
  v1.11). It is `"attestation": {"required": false}` and OFF is the shipped
  default, so an upgraded instance behaves exactly as it did. **Do NOT turn it
  on during an upgrade.** Turning it on requires deciding where the signing key
  lives, and that is a decision about the project's threat model rather than a
  migration step: a key the build process can reach lets a headless run sign its
  own approval, so switching this on without that conversation would hand
  somebody an integrity chain whose strength nobody established. Tell the human
  the block exists, that `"custody": "signer"` with a key they hold is the model
  that works today, and that `"custody": "forge"` is designed and not yet built.
- **Mention the status record, and migrate NOTHING** (RP1, edition v1.12;
  BL-005's precedent applied a third time). An upgrade NEVER creates
  `.claude/status.json`: stamp parity explicitly excludes it, because the only
  path that may create the record unattended is a birth, where there is
  nothing to transcribe and therefore nothing to launder. Until the file
  exists the instance is a legacy instance and loses nothing: the page readers
  keep deciding, byte-identically. Tell the human the record exists, that new
  instances are structured from birth, and that opting in is
  `/setlist:checkpoint`'s one-time transcription: it reads STATUS.md, prints
  exactly what it would record, and writes the file only after the human
  confirms the list. Never run that transcription yourself during the upgrade,
  and never unattended: an unconfirmed transcription launders the frozen
  readers' possible misreadings into the authoritative record.
  **Check for a name collision first**: presence is the switch, so a project
  that already tracks its OWN `.claude/status.json` (some deploy tools write
  one) reads as present-and-malformed the moment the 2.4.0 hooks arm, and
  role-path trunk writes and closes refuse with `SLH-RECORD-MALFORMED` whose
  message assumes a corrupted record rather than a foreign owner (measured,
  2.4.0 review). If the file exists and is not Setlist's, surface it to the
  human BEFORE arming: the honest exits are relocating the foreign file or
  declining the record path, never overwriting their file.
- Record all of this inside the umbrella ADR.

## 4. Instance skill flags (any instance stamped before plugin 1.6)

The generated skills (`.claude/skills/scaffold`, and `browser-qa` where
present) are instance-owned; the upgrade never rewrites their bodies.
Their frontmatter must still carry the manual-invocation flag Part 6 demands
("Mark them manual-invocation"): ensure each SKILL.md has
`disable-model-invocation: true`, adding the line when missing, and record the
touch-up in the umbrella ADR with the rest.

## Gotchas (field-observed)

- "Already byte-identical" and "already current" are claims, not facts: verify
  them with a checksum or a diff against the plugin's template before leaving
  a file alone. Sessions have misreported enforcement events elsewhere; the
  upgrades whose claims held were the ones that checked.
