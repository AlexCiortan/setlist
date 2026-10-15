# How Setlist thinks

This is the short account of Setlist for someone deciding whether a team should use it. It covers
why the discipline lives in git, what a spec and a close are, the four levels you can adopt, and
where the whole thing stops. It takes about ten minutes. The [README](README.md) says how to start,
and [`setlist.md`](setlist.md) is the protocol itself, which nobody needs to read in order to decide.

## The problem it answers

An agent that writes code is fast, and the bottleneck moves to the person directing it. What limits
you is no longer how quickly code appears. It is how much of it you can review before the next
thing is built on top of it. A process helps only if it survives the moments when nobody is
watching: a long session, a compacted context, a model swapped mid-feature, a teammate's clone, a
Friday afternoon. Instructions an agent is asked to follow do not survive those moments reliably.
They are text in a context window, and a context window forgets, summarises and reinterprets.

Setlist moves the part of the process that must hold out of the conversation and into the
repository. There git enforces it, whether or not anyone remembers it.

## Why the discipline lives in git

The first versions of Setlist enforced the process inside the Claude Code session. Hooks read each
shell command and denied the ones that would skip a step. Every release closed one spelling of a
bypass and the next release found another. A shell command can compute its own arguments, so
the set of spellings has no end. Then the command parser failed on one platform for a reason that had
nothing to do with commands. It failed open and allowed everything, while a git hook on the same
machine in the same run was untouched.

That was the lesson the design is built on. A git hook runs after the shell is done: git has already
parsed the arguments, resolved the refs and decided what the operation is. A merge is a merge
however it was typed. So the guarantee lives in hooks that git runs from its own state. They are
stamped into a tracked `.githooks/` directory, so they are versioned, reviewed in diffs and present
in every clone. They hold under Claude Code, under another agent, or under no agent at all.

The session layer did not disappear. It became advisory, which is what it could truthfully be. A
scope hook tells the agent when a write lands somewhere the active spec does not cover. A
re-grounding hook points a new or resumed session at the current state. A Stop hook nudges a
session not to end with a spec change unstaged. And one deny stops an obvious spelling of switching
the git hooks off. Advice persuades; hooks refuse. The rest of this document is about the part that
refuses.

## What a spec is

A spec is a short file under `specs/` that says what one piece of work will do and what it will not
do. It also says how anyone will know the work is done: acceptance criteria a person can check. You
approve it before code is written. It declares the files it owns (`Owns:` lines), which is how the
hooks tell work that belongs to it from work that wandered in.

One spec is active at a time in a checkout. That is the point of the design, and the tooling could
do otherwise. Ten features built in parallel are not ten times the progress if you can review two.
Across a team, two people can each run a spec on their own branch, and the audit keeps them apart.
Disjoint `Owns:` sets close in any order. Overlapping ones are refused at the second close until its
branch carries the first close's change.

The spec is also the memory. A decision that is not in the spec or its plan has not been handed
over. A model's reasoning does not travel from one session to the next, and the file does.

## What a close is

A close is the merge that brings a spec's branch to the trunk. It is made with `--no-ff`, so that it
is a merge commit git can judge. Before git merges it, `/setlist:checkpoint` runs the close
checklist. The checklist covers the gates the project declared (its tests, its type-checker, its
build) and a Closing report in the spec with the first QA pass written down. It also covers a review
by a second model in a fresh context. That model reads the branch's diff against the spec's criteria
and reports every finding with a file and a line. You fix what it finds, and it reads again. After
two rounds the call is yours, recorded as yours. The second QA pass is always yours: you use the
feature and check at least one criterion by hand.

Then git decides. The merge hook refuses a close that brings feature code without closing a spec. At
push the trunk audit walks the history again, from the commit the instance adopted the rules. It
refuses anything that reached the trunk without a closed spec's lineage. The audit reads history,
whatever command produced it. So it sees work that arrived by a renamed branch, a cherry-pick or the
forge's merge button, and it does not care how the command was spelled.

## The four levels

You adopt Setlist in levels, and each level refuses something the one before cannot.

- **The git hooks**, in every clone. `pre-commit`, `pre-merge-commit` and `pre-push` refuse a commit,
  a merge or a push whose history skipped the process. This is the level that matters, and it works
  for one developer with one clone.
- **The forge check**, for a team. CI asks the same questions on every pull request, about the merge
  the button would make, in a place no committer's clone controls. It governs the merge button only
  where the trunk requires it, beside a review and code-owner review.
- **The session layer**, optional. Advice inside Claude Code: the scope warning, the re-grounding
  pointer, the Stop nudge, the one deny. It refuses nothing the git hooks do not also refuse.
- **Custody**, the question of who may approve a spec. One answer is a signing key, which is only as
  strong as where it lives. The other is the forge's required review, which needs no key and rests on
  the forge's account security.

## The threat model, in short

Setlist is a discipline control for cooperating use. It is no security boundary, and it says so
before you install it. The line between the two is exact: a git hook can refuse what git hands it,
and it cannot refuse what never reaches it.

What never reaches it, in the groups the full list uses:

- **The escapes.** `--no-verify` and Setlist's own `SETLIST_SKIP_HOOKS=1` skip the git hooks. They are
  deliberate acts with obvious names. The forge check has neither, and it is the answer.
- **The clone.** Hooks are per-clone configuration. A fresh clone is unprotected until it is armed.
  Another hook manager can point git elsewhere on install. A branch that never carried Setlist runs
  no hook when it is checked out. The session start reports a disarmed clone, and the forge check
  does not live in a clone at all.
- **The forge.** The forge check judges what the forge exposes when it runs: the protection as it
  stands now, and the pull request's own copy of the check. It is as strong as the trunk's rules.
- **Declarations.** An `Owns:` line and a signed approval are claims. The hooks verify that they are
  present, consistent and signed, and never that they are true.
- **Deliberate evasion.** A committer who crafts history to pass the audit can. Some routes are
  closed and the rest are named: a chained merge, five sideways commands, and a merge that edits a
  file outside its conflicts, which the audit reports.
- **The harness.** A hook that times out is a skipped gate, and a session killed from outside fires
  no Stop.

Each item is stated in [LIMITATIONS.md](LIMITATIONS.md) as a fact about git, the forge or the
harness. Each comes with the date it was decided, the reason, and what to do. The list is tested and
not only asserted. Every release's own adversarial review drives the shipped bytes with these routes
as its brief. A route it finds is fixed before the release ships, or it is named as the boundary of
a new capability. A release never grows the list for any other reason.

## What it costs

Setlist is invasive by design. It stamps hooks, a workflow and a few documents into your repository,
and it changes how merges are made (`--no-ff`, always). It asks for approvals, for answers to parked
questions and for the second QA pass. It will not ship ten things in parallel for you to review
later. If you want the agent to run ahead of you, it is the wrong tool.

You can see what it would do before paying any of that. `/setlist:retrofit --observe` reads an
existing repository's last fifty merges and prints every one the trunk audit would have refused,
installing and writing nothing. On a repository you already run it on, `/setlist:upgrade` prints the
same reading, as a delta between the audit you have and the new one, before anything is replaced.

## Where to go next

- The [README](README.md): install, the operating loop, the commands.
- [LIMITATIONS.md](LIMITATIONS.md): every boundary in full.
- [`setlist.md`](setlist.md): the protocol, which the plugin's commands, skills and templates bind.
