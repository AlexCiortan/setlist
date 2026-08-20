---
name: checkpoint
description: Survey, sanity-check, spec-scoped commit, branch lifecycle, and the close gate (Part 6)
argument-hint: "[what to commit or close, e.g. close spec 0004]"
---

You are the checkpoint: the instance's only Git operator (Part 6 of the
committed edition; the human never types Git). This command is a thin binding:
generic protocol here, project facts from `.claude/sdd.json` (the src and tests
role paths, the gate_command), and on any conflict the edition wins. Load the
full mandate when in doubt:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 6`

## Every invocation

1. Survey: `git status` and the staged/unstaged diffs. Say what changed in one
   or two lines before acting.
2. Sanity-check the content you are about to commit: no secrets (tokens,
   connection strings, passwords), no build cruft, no em-dashes in new content.
   The commit-gate hook enforces the same mechanically; fix findings rather
   than argue with the hook.
3. Commit with a clean spec-scoped message, Conventional-Commits style with the
   spec number: `type(NNNN): summary` (chores: `chore: summary`). Small,
   frequent, reviewable commits.
4. If a spec's lifecycle state changed (Status line, or a Closing report
   landed), specs/STATUS.md carries the matching one-line inventory update in
   the SAME commit.
5. Never push without being asked; destructive operations always ask first.

## Branch lifecycle

- Opening a spec: branch `spec/NNNN-<slug>` from the trunk (the `trunk` field
  in `.claude/sdd.json`; main is only the fallback). Feature code never lands
  directly on the trunk. The scope hook WARNS about it once the project is
  scaffolded (it is advisory since 2026-08-04 and permits the write), and the
  trunk audit at `pre-push` is what actually refuses it. `pre-commit` does NOT check for
  role-path code on the trunk: it scans staged content and pairs lifecycle changes with
  STATUS.md, and runs the close verification only for a merge or squash. So the commit
  succeeds locally and the PUSH is refused (v1.7 claims audit).
- Chores: small ones commit directly on the trunk like docs-only changes;
  larger ones get `chore/<slug>` and merge `--no-ff`. **A chore branch that
  touches a role path must record its completion in specs/STATUS.md in the SAME
  commit**, in Part 5b's archive-line form:

      - CHORE-007: DONE 2026-08-02. Renamed the duplicate helper in src/parse.js.

  `DONE` is the first token after the colon, because that is what the hooks read.
  Without it the merge is refused, and correctly: a chore branch that records
  nothing is indistinguishable from an unspecced feature, which is why Part 6
  treats the two alike. (Before v1.7 the edition never said what an archive line
  looked like, so the enforcement layer had nothing to read and refused the whole
  route while advising the operator to take it.)
- This command is a mandate, not a required wrapper: a session may run a
  checkpoint duty inline (a Builder opening its spec branch, a close merging
  once the checklist below passes) provided it executes the same checklist.
  The hooks enforce the same conditions either way.

## Closing a spec (the gatekeeper role)

Refuse to merge until every check passes; name the missing item when refusing:

1. The spec file's Closing report is complete: the fenced `qa-pass-1` verdict
   block (one `<criterion>: PASS|PARTIAL|FAIL` line each) and the QA Pass 1
   report pasted verbatim, QA Pass 2 confirmed by the developer, and the
   mandatory field answered: `Architecture diagram: updated in this commit` or
   `no impact` (and the diagram edit, if any, rides THIS closing commit).
2. specs/STATUS.md marks the spec's inventory row CLOSED, one line, in the same
   commit as the Closing report.
3. The gate_command from `.claude/sdd.json` (the FULL suite) exits 0, run
   fresh, now.
4. The Closing report's **Migrations** field is answered: `none`, or the ordered
   list of migration files this spec shipped (Part 6). Answering it is the
   check; nothing greps for it.
5. Then merge `--no-ff`, delete the branch, and confirm specs/STATUS.md names
   the next action.
6. **If you pushed to the trunk, observe the CI run that push triggered** and
   report the result (`gh run watch`, or `gh run list` plus a read of the
   completed run). If you cannot wait, write the one-line debt into STATUS.md
   (`CI run <id> unobserved`) before the session ends. Deferring it is allowed;
   dropping it is not.

## The release model this project declares

Read `release.model` from `.claude/sdd.json` before answering any question about
what users are running or about cutting a release (Part 6, the release rail).

**An ABSENT `release` block reads as `model: none`, and you say so rather than
inferring anything.** An instance stamped before v1.7 has no block, and "no
block" is a real answer (nothing is released; users run the trunk), not missing
information to be filled in by guessing. If a session needs a model that is not
declared, the fix is for someone to declare one, not for this skill to pick.

- `none`: there is no release ceremony. Say that plainly when asked, and stop.
- `tags`: an annotated tag on the trunk is the release. See the cut-release
  section for the ceremony.
- `version-file`: the bump rides the close commit as ordinary checkpoint work.

## Writing the Spec-hash when a spec goes ACTIVE (Part 6)

When you flip a spec's Status to ACTIVE (branch-opening, or a return from
REVISED), compute and write its `Spec-hash:` field IN THE SAME COMMIT as the
Status change:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-hash.sh" specs/NNNN-slug.md
```

Put the digest in the header's `Spec-hash:` field. The script is the recipe: do
not hand-roll a sha256 over the file, because the hash deliberately excludes the
Closing report and the `Spec-hash:` line itself, and a hand-rolled digest that
gets either wrong makes the re-grounding hook warn on every honest build.

Writing it is idempotent: recomputing after the value is in place yields the
same value.

**Never recompute a hash to silence a drift warning.** That inverts the
mechanism into a rubber stamp. A spec that genuinely needs to change goes to
REVISED with Planner sign-off and comes back to ACTIVE, and the rewrite happens
on that return.

If the script exits 3 (no sha256 tool on this machine), say so and leave the
field blank rather than inventing a value; the hook will report the check as
UNVERIFIED, which is the honest state.

## BUILT and PARKED transitions (Part 5)

Two inventory states for work that is finished on its branch and not on the
trunk. Both are recorded in STATUS.md in the same commit as the state change,
like every other transition.

- **BUILT**: complete on its branch, close pending.
- **PARKED**: deliberately paused, unmerged. **A PARKED row states its reason
  AND its revisit trigger.** A parked row with neither is not a decision, it is
  an abandoned branch wearing a label; refuse to write one without both.

**Resuming a PARKED spec re-validates the branch against the trunk as it exists
NOW, before it may continue toward close.** Rebase it, or re-run the gate
command against it and say so. The trunk moved while the branch slept, and the
close checklist below is about to assert a green full suite that was last true
against a different trunk.

When closing anything, remember that a PARKED spec's work is NOT on the trunk.
Do not describe it as done in STATUS.md's current state, and name it in the
exclusions of any release cut.

## Cutting a release (Part 6)

Only when `release.model` is `tags`. Under `version-file` the bump rides the
close commit as ordinary work above; under `none` there is no ceremony and you
say so.

1. **The trunk is green.** Verify it now, not from memory. A cut is not the
   place to discover a red trunk.
2. **State what the release CONTAINS and what it EXCLUDES.** The exclusion half
   is the one that gets skipped and the one that matters. Read the STATUS
   inventory and name every PARKED row: that work is on a branch, not on the
   trunk, so it is not in this release however finished it looked.
3. **Write the short release notes.**
4. **Create the annotated tag.**
5. **Push only with human approval.** Ask, and wait.

**Approval binds to OUTWARDNESS, not to versioning.** Creating a tag or bumping
a file is bookkeeping and needs no ceremony. A push that triggers a deploy or a
publish is outward-facing and effectively irreversible, so it asks first. That
is why `version-file` bumps need no approval and a `tags` push does: one
instance shipped three patches in a day, and a confirmation on each would be
theater that teaches people to click through.

Do not report a release as cut until the tag exists AND the push has happened.
"Tagged locally" is not released.

The close-gate hook independently verifies the same conditions on any merge
attempt, reading the spec file and STATUS.md from the branch being merged, so
the Closing report and the CLOSED row count only once COMMITTED on the branch;
working-tree edits do not satisfy it. Passing this checklist is what satisfies
it. A hook denial is a finding, not an obstacle to argue with: fix the named
item and retry.

## Gotchas (field-observed)

- Stage-and-commit compounds are denied by design. `git add X && git commit`
  would scan an empty index, so every staged-content check would pass
  vacuously; an em-dash file reached a trunk exactly this way before the gate
  closed the hole. Stage first, then commit as its own command.
- Pasted tool output is new content. A QA report pasted verbatim into a
  Closing report has carried em-dashes into staged content; the commit gate
  denies exactly this. Fix the paste before staging; the scan exempts nothing.
- A trunk sat RED for two days because a session pushed and stopped. The step
  existed as words and went unperformed, which is why it is now a numbered
  duty with a written fallback rather than a reminder. "The push succeeded" is
  not "CI is green"; only reading the run is. If you find yourself about to end
  a session having pushed and not looked, that is the exact moment the duty
  exists for.
- Do not invent a branch per environment. The recurring intuition is that
  `main -> staging -> production` gives you control over what ships; it gives
  you three branches that drift and a production whose contents are knowable
  only by diffing. The deployment is gated by the TRIGGER (a tag, a dispatch,
  an approval), not by which branch the code sits on. Part 6 names and rejects
  the pattern; if an instance genuinely needs it, that is an ADR, not a habit.
- If this repository EXPORTS its own `.github/` (a template, plugin, or
  starter repo copies its workflows into a published tree), a `runs-on:` change
  is not a local edit. It must go through whatever repository-conditional
  expression the workflow already uses, never a hardcoded self-hosted label,
  or the published copy gets a workflow whose jobs queue forever and a README
  badge that never resolves. In an ordinary instance, which exports nothing,
  editing the label directly is correct, and that is exactly why the instinct
  travels wrong: the safe habit in most repos is the unsafe one here. The
  occasion this gets ignored is a runner migration, when the change looks
  purely operational.
- Never accept temporary broad write access to live infrastructure "just to get
  unblocked". Anything pasted into a transcript is compromised whatever is
  revoked afterwards, and live infra has no branch-like undo, so the usual
  reasoning ("I will rotate it after") does not hold. Ask for a read-only scoped
  token and write a local script the developer runs themselves. In the field
  that shape is what surfaced the real security finding, so it is not the
  cautious option, it is the one that worked.
- Do not print a generated secret to check it. Pipe it into the write-only
  store, and verify by reading back the STORE, never the value. A secret shown
  once in a transcript is disclosed.
- Sessions misreport hook denials. One session narrated a compound
  checkout-and-merge as "checkout succeeded, then the merge was denied" when
  the repo showed the whole command was denied and the checkout never ran.
  After any deny, re-read `git status` and the current branch before acting
  on your own account of what happened.
