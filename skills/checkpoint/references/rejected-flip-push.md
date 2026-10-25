# A rejected flip push is the lock working (edition v1.22)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

- **A rejected flip push is the lock working** (edition v1.22). The trunk
  moved: git rejects the push as not a fast-forward, or the stamped `pre-push`
  refuses it first as `SLH-SCAN-UNREADABLE-RANGE`, because this clone never
  fetched the remote end of the range. Either way: fetch, read the trunk's
  record and the spec's header again (or run the board), and report who holds
  the spec, its `Driver:` line and the trunk's sha, or that the trunk moved for
  another reason. Never retry, rebase or reset on your own. Ask the engineer:
  take the next number for this cut (`board.sh --next`), or stand down.
  Dropping the local flip commit is a destructive operation, and it asks.
  Under `forge` custody the race is two pull requests: once the first lands,
  the second's diff shows the first's `Driver:` line on the trunk, and you say
  so by name.
