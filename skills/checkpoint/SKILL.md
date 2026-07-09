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
  directly on the trunk (the scope hook blocks it once the project is
  scaffolded).
- Chores: small ones commit directly on the trunk like docs-only changes;
  larger ones get `chore/<slug>` and merge `--no-ff`.
- This command is a mandate, not a required wrapper: a session may run a
  checkpoint duty inline (a Builder opening its spec branch, a close merging
  once the checklist below passes) provided it executes the same checklist.
  The hooks enforce the same conditions either way.

## Closing a spec (the gatekeeper role)

Refuse to merge until every check passes; name the missing item when refusing:

1. The spec file's Closing report is complete: the QA Pass 1 PASS/PARTIAL/FAIL
   report pasted verbatim, QA Pass 2 confirmed by the developer, and the
   mandatory field answered: `Architecture diagram: updated in this commit` or
   `no impact` (and the diagram edit, if any, rides THIS closing commit).
2. specs/STATUS.md marks the spec's inventory row CLOSED, one line, in the same
   commit as the Closing report.
3. The gate_command from `.claude/sdd.json` (the FULL suite) exits 0, run
   fresh, now.
4. Then merge `--no-ff`, delete the branch, and confirm specs/STATUS.md names
   the next action.

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
- Sessions misreport hook denials. One session narrated a compound
  checkout-and-merge as "checkout succeeded, then the merge was denied" when
  the repo showed the whole command was denied and the checkout never ran.
  After any deny, re-read `git status` and the current branch before acting
  on your own account of what happened.
