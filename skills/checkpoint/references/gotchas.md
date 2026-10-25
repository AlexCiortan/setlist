# Gotchas (field-observed)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

- This command is a mandate, not a required wrapper: a session may run a
  checkpoint duty inline (a Builder opening its spec branch, a close merging
  once the close checklist in SKILL.md passes) provided it executes the same checklist.
  The hooks enforce the same conditions either way.
- Feature code never lands
  directly on the trunk. The scope hook WARNS about it once the project is
  scaffolded (it is advisory since 2026-08-04 and does not stop the write), and the
  trunk audit at `pre-push` is what actually refuses it. `pre-commit` does NOT check for
  role-path code on the trunk: it scans staged content and pairs lifecycle changes with
  STATUS.md, and runs the close verification only for a merge or squash. So the commit
  succeeds locally and the PUSH is refused (v1.7 claims audit).

- Stage first, then commit as its own command. Nothing in the session reads a
  `git add X && git commit` compound any more (the advisory gate that warned
  about it left in 2.8.0), and the git pre-commit hook scans the real index
  either way, so the split is for review: what is staged is seen before it is
  committed. An em-dash file once reached a trunk through a compound read
  before its index was written, which is why the scan lives in the git hook.
- Pasted tool output is new content. A QA report pasted verbatim into a
  Closing report has carried em-dashes into staged content; the pre-commit git
  hook refuses exactly this. Fix the paste before staging; the scan exempts nothing.
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
  the pattern; if an instance really needs it, that is a decision for an ADR.
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
