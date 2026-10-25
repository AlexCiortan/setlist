---
name: board
description: The board (Part 6), every spec by state with its driver, Owns set, remote branch and age, and the collisions a read of the trunk and the remote can see. Read-only; refuses nothing.
argument-hint: "[--offline]"
---

You are the board: a read of the instance's trunk and its remote that shows who
holds which spec (Part 6 of the committed edition, edition v1.22). This command
is a thin binding over one script; on any conflict the edition wins. Load the
Part when in doubt: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 6`

Run it:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh"            # live: git ls-remote, then a fetch of tips not here
bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh" --offline  # the last fetch alone, with its age
```

Then tell the engineer what it printed, in this order: where it read from (live,
the last fetch and its age, or no remote), every collision it named, the stale
claims, and the next number. Quote each collision line as the script wrote it;
do not soften or merge them.

What it reads: the trunk's `.claude/status.json` and every `specs/NNNN-<slug>.md`
header on the trunk (Status, `Driver:`, `Owns:`), and on each `spec/` branch of
the remote that branch's own spec file, because `Owns:` lines are appended on the
branch. The remote is the trunk's upstream, else `origin`, else none. The live
read fetches remote-tracking refs and changes no working tree and no local
branch, so it needs no ask.

What it names, one line each: a number claimed twice under two slugs; two ACTIVE
specs whose `Owns:` sets overlap; a `spec/` branch whose spec is not on the trunk;
an ACTIVE spec with no branch on the remote; a BUILT spec waiting to merge; and a
stale claim, an ACTIVE spec whose branch has had no commit for `stale_days`
(`.claude/sdd.json`, default 7). It prints a count of ACTIVE specs per driver,
which is a count and never a limit.

It decides nothing and fixes nothing. It REFUSES NOTHING: no hook reads it, and
the guarantee on two specs that declare one file is still the close-time refusal
(`SLH-OWNS-OVERLAP`). What it cannot see is a claim nobody pushed, so a clean
board means nothing pushed collides, not that nothing collides. If the engineer
wants a collision resolved, that is the checkpoint's work (renumber the later cut
before it merges, merge the trunk into a branch, park a stale claim with a reason
and a trigger) and it is done only on their word.

Exit 2 means the script could not read and says why (no repository, no
`.claude/sdd.json`, no usable `jq`, a git read that failed); report that line
as it stands.
