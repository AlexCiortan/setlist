# Dated additions and edition deltas, v1.7 to v1.23 (Part 8c)

Read on demand from `/setlist:upgrade` (its SKILL.md names when). The edition wins on any conflict: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8c`.

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
  hand copy is what this bullet used to ask for and it is the worse path. Git
  skips a non-executable hook SILENTLY, so a manual install that loses the mode
  bit leaves a boundary that stops nothing and says nothing.
  **Both settings, and the second is not optional**: a fast-forward merge fires
  no git hook at all, so without it `git merge spec/0001-x` walks unreviewed
  work onto the trunk past the boundary.
  What is left for a person here is the VERIFICATION and the warning, not the
  install: confirm `git config core.hooksPath` reads `.githooks` and
  `git config merge.ff` reads `false` after the refresh (`/setlist:validate`
  check 18 asserts exactly this), and warn the human that this is a BEHAVIOURAL
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
- **Tell an instance with pre-boundary history that the per-push escape ends here**
  (edition v1.18). When `.claude/sdd.json` was committed before `.githooks/`
  arrived, the trunk audit used to judge every merge in between and refuse every
  push; the refresh now records `audit.baseline` in the migration commit, so the
  audit judges this history from the commit the instance was first governed at,
  and `SETLIST_SKIP_TRUNK_AUDIT=1` stops being the price of pushing. The
  migration commit is the one that carries the key: say which commit was
  recorded, and that it is a declaration in a reviewed file rather than a
  setting.
- **Tell the human what the boundary move means.** The PreToolUse gates are now
  ADVISORY, and within the git hooks the GUARANTEE is the push-time trunk audit:
  the two per-merge hooks keep refusing at commit and merge time as early
  warning, and the audit at `pre-push` is what stands between unreviewed work
  and a shared trunk. Nothing is removed and no workflow breaks, but a bypass
  spelling of a session gate, and a route past a per-merge hook, are MAJORs
  rather than release blockers now, and the real holes (`--no-verify`, the
  forge merge button, the per-clone config) are listed in the edition's Known
  limitations. An upgrade that silently changes what a guarantee means is worse
  than one that says so.
- **Optionally declare a git identity** (BL-007, plugin 1.1.0). If this machine
  holds more than one git identity, add `"identity": {"user_email": "..."}` to
  `.claude/sdd.json` and `/setlist:validate` reports a mismatch with the machine's
  `git config user.email` at each health check (since 2.8.0 nothing warns at
  commit time, and nothing refuses). Do NOT add it silently: no key means no check, which is the correct
  default, and writing whatever `git config user.email` currently returns would
  ratify a possibly-wrong value rather than declare an intended one. Ask.
- **Mention the new `Spec-hash:` field, and migrate NOTHING** (BL-005, edition
  v1.7). Existing specs simply lack it and acquire one at their next transition
  to ACTIVE. Do not back-fill hashes across historical specs: a hash computed
  today over a spec approved months ago attests to nothing, and writing one
  would turn a truthful "not yet covered" into a false "verified". Tell the human
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
  that works without a forge, and that `"custody": "forge"` (built in edition
  v1.14) means no key at all: the approval is the flip landing on the protected
  trunk through a required review, verified by the stamped forge check, which
  the team must REQUIRE on the trunk for it to be a boundary.
- **Mention the diagram half, and migrate NOTHING** (BL-005's precedent applied
  a fourth time). DETECT the old shape: a `steering/structure.md` carrying a
  Mermaid section and no `docs/diagrams/` directory. REPORT it in one line:
  this instance carries one diagram at one altitude; the diagram half's checks
  are off until `docs/diagrams/` exists; opting in is a chore of its own. Then
  stop. Do NOT create the directory, do not split the diagram across altitudes,
  and do not redraw anything. An upgrade is a planning-and-documentation act,
  and a redrawn architecture is neither: it is a scan of the code producing
  claims nobody reviewed, landed on a docs-only chore branch where nobody would
  look for them. Creating the directory is also not a neutral act, which is the
  second reason: its presence ARMS the close's diagram checks, so an upgrade
  that created it would turn on refusals for a project whose diagrams nobody has
  read yet. Tell the human the half exists, that opting in is a chore with its
  own branch and close where the old section is retired to
  `docs/diagrams/retired/` and the altitudes are seeded under their review, and
  that until then the instance loses nothing and behaves exactly as it did.
- **Mention the status record, and migrate NOTHING** (RP1, edition v1.12;
  BL-005's precedent applied a third time). An upgrade NEVER creates
  `.claude/status.json`: stamp parity explicitly excludes it, because the only
  path that may create the record unattended is a birth, where there is
  nothing to transcribe and therefore nothing to launder. Until the file
  exists the instance is a legacy instance and loses nothing: the page readers
  keep deciding, byte-identically. Tell the human the record exists, that new
  instances are structured from birth, and that opting in is
  `/setlist:checkpoint`'s one-time transcription. It reads STATUS.md, prints
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
  human BEFORE arming: the legitimate exits are relocating the foreign file or
  declining the record path, never overwriting their file.
- **The v1.14 delta (plugin 2.6.0): the forge side, the Stop hook and the
  `gates` block.** The refresh delivers all of it (above); what is left for a
  person is three things. Wire the Stop hook: the refresh exits 3 until
  `.claude/settings.json` carries the `Stop` entry the template shows (no
  matcher, timeout 60), because that file is never machine-rewritten. Fill the
  `@OWNER` slot in `.github/CODEOWNERS` with the team that owns the enforcement
  layer (a standing slot is `/setlist:validate`'s finding), and require the
  check named `setlist forge check` on the trunk at the forge, in a ruleset,
  with one approving review and review from Code Owners (edition v1.18: the
  check reads that setting, and under `forge` custody refuses without it,
  `FC-NO-CODE-OWNER-REVIEW`): until then the check reports rather than
  governs, and it says so on every pull request. The `gates` migration is the ONE migration
  this edition makes, because it changes no verdict: `close` and `push` from
  the single `gate_command`, `commit` empty; tell the human the tiers exist
  and let them declare a cheaper `commit` tier if they want one. Under
  `forge` custody an instance that refused every commit since v1.11 stops
  refusing the day the check is in the tree (the hooks defer to it by name).
- **The v1.18 delta (plugin 2.10.0): two things the refresh leaves to a
  person** (Part 8c). Under `forge` custody, turn on "Require review from Code
  Owners" in the trunk's ruleset BEFORE the upgrade lands, or the refreshed
  check refuses the next closing pull request (`FC-NO-CODE-OWNER-REVIEW`). And
  the stamped `.env` deny narrowed to the conventional secret-bearing names
  (Part 3), which the refresh does not carry into an existing
  `.claude/settings.json`: offer the one edit that replaces `Read(.env.*)`
  with those names (and, from v1.22, the earlier Bash entry for reading
  environment files with the template's Bash entries), so the session can read
  the `.env.example` it keeps current; the instance loses nothing by declining.
- **The v1.19 delta (plugin 2.11.0): new rules dated, nothing judged
  backwards** (Part 8c). The refresh records `plugin.version` 2.11.0 in the
  migration commit, and that record is what puts the close review, the
  overlap refusal and the merge-edit report in force: each reads the plugin
  version a close's own `.claude/sdd.json` records, so a close made before the
  upgrade is never asked for them. Quote the verdict delta (above) before
  `--apply`. Where another hook manager holds `core.hooksPath`, the refresh
  chains it: commit `hooks_chain` in `.claude/sdd.json` and the pass-throughs
  under `.githooks/` with the migration.
  And offer the three golden rules v1.19 adds (Part 4: carry a spec through
  and build nothing beyond it, a real check or no claim, ideas first when
  ideas are asked for) as one edit to the instance's `CLAUDE.md`, in the words
  of `${CLAUDE_PLUGIN_ROOT}/templates/root/CLAUDE.md.tmpl`, numbered after the
  instance's own rules; the file is the project's, so the human takes the edit
  or declines it, and a decline is recorded in the umbrella ADR.
- **The v1.20 delta (plugin 2.12.0): the audit's codes, a `verify` skill,
  nothing by hand** (Part 8c). The refresh delivers the `verify` skill and the
  changed `close-reviewer` agent through its report of changed bytes, keeping a
  differing copy as `.setlist-backup` (never over an earlier backup), and records `plugin.version` 2.12.0,
  which dates no new rule. Quote the verdict delta before `--apply`: refusals
  the old audit printed as a sentence alone now carry their codes, and the
  delta keys each old sentence by its new code. Tell the human that `models`
  is recorded only by a bootstrap probe and is never migrated, and that the
  stamped deny and ask rules need Claude Code 2.1.289 or later.
- **The v1.21 delta (plugin 2.13.0): the delegated tier, the spec reader, the
  bypass deny blocking on failure, one offered edit** (Part 8c). The refresh
  delivers `qa-verifier` (now on `model: haiku`), the changed `close-reviewer`
  (an `effort:` default and the effort line) and the new `spec-reader` through
  its report of changed bytes, each differing copy kept as `.setlist-backup`;
  a qa-verifier the instance had adapted is in that backup, so fold its
  adaptations back in where they matter and record the deviation. When the
  report prints the `jq` edit that adds `"onFailure": "block"` to the bypass
  deny's entry in `.claude/settings.json`, offer it as one edit the human takes
  or declines (it needs Claude Code 2.1.295; an older one ignores it). When the
  report calls `.github/workflows/setlist-forge-check.yml` STALE (a workflow from
  before v1.21 hands the refreshed check no answers file, so the check asks the
  forge nothing), offer the printed `cp` from the template the same way, and say
  that any local edit to the workflow (a runner label) is re-applied after it. Offer
  golden rule 13 (Part 4, "delegate the mechanical, never the deciding") in the
  words of `${CLAUDE_PLUGIN_ROOT}/templates/root/CLAUDE.md.tmpl`, numbered after
  the instance's own rules. The refresh records `plugin.version` 2.13.0, which
  dates no new rule; quote the verdict delta before `--apply`.
- **The v1.22 delta (plugin 2.14.0): hooks and two agents through the refresh,
  two additive keys, one offered settings edit, the design surface on `/design`**
  (Part 8c). The refresh delivers the hook library and the three git hooks, the
  trunk audit, the re-grounding hook and the `close-reviewer` and `spec-reader`
  agents through its report of changed bytes, each differing agent copy kept as
  `.setlist-backup`; quote the verdict delta before `--apply` (an empty remote
  now audits its declared trunk alone). Migrate nothing: the `Driver:` line is
  written at the next ACTIVE flip, `Cites:` and `Contracts touched:` are
  optional, `system_spec` and `stale_days` are additive keys absent-as-before
  (the refresh keeps and names a recorded `system_spec`), and the Assumptions
  sections arrive with the next default written down. Refresh
  `specs/TEMPLATE.md` from Appendix C as above, which brings the new header
  lines. Offer one edit to `.claude/settings.json`: the earlier Bash entry for
  reading environment files replaced by the `Bash(cat <name>)` entries for the seven names in
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/settings.json.tmpl`, so the session
  reads `.env.example` from the shell; the human takes it or declines. In a UI instance, offer
  `${CLAUDE_PLUGIN_ROOT}/templates/docs-design/INDEX.md` as
  `docs/design/INDEX.md` where absent, and say that a design locked on the
  standalone design site is committed under `docs/design/` before 2026-12-14.
  The plugin's own skills load from the plugin and reach no instance file. The
  refresh records `plugin.version` 2.14.0, which dates no new rule.
- **The v1.23 delta (plugin 2.15.0): the hooks through the refresh, two push
  refusals dated by the stamp, one optional record key** (Part 8c). The refresh
  delivers the hook library, `pre-commit`, `pre-push`, the trunk audit and the
  re-grounding hook through its report of changed bytes; quote the verdict delta
  before `--apply`. Migrate nothing: a record without `driver` reads as before,
  and the checkpoint writes the key at the next ACTIVE flip. Say that the
  refresh's record of `plugin.version` 2.15.0 is what puts the two refusals in
  force (`SLH-CLAIM-NOT-ON-TRUNK`, `SLH-CLAIM-NUMBER-TAKEN`): each is asked of a
  pushed commit stamping 2.15 or later, so an unmerged branch cut before the
  upgrade is not asked, and refuses a record carrying `driver` as
  `SLH-RECORD-MALFORMED` until it merges the trunk.
- Record all of this inside the umbrella ADR.
