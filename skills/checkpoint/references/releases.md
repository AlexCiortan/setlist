# The release model and cutting a release (Part 6)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

## The release model this project declares

Read `release.model` from `.claude/sdd.json` before answering any question about
what users are running or about cutting a release (Part 6, the release rail).

An ABSENT `release` block reads as `model: none`, and you say so rather than
inferring anything. An instance stamped before v1.7 has no block, and "no
block" is a real answer (nothing is released; users run the trunk), not missing
information to be filled in by guessing. If a session needs a model that is not
declared, the fix is for someone to declare one; this skill never picks.

- `none`: there is no release ceremony. Say that plainly when asked, and stop.
- `tags`: an annotated tag on the trunk is the release. See the cut-release
  section for the ceremony.
- `version-file`: the bump rides the close commit as ordinary checkpoint work.


## Cutting a release (Part 6)

Only when `release.model` is `tags`. Under `version-file` the bump rides the
close commit as ordinary checkpoint work; under `none` there is no ceremony and you
say so.

1. **The trunk is green.** Verify it now, against the files. A cut is not the
   place to discover a red trunk.
2. **State what the release CONTAINS and what it EXCLUDES.** The exclusion half
   is the one that gets skipped and the one that matters. Read the STATUS
   inventory and name every PARKED row: that work is on a branch, not on the
   trunk, so it is not in this release however finished it looked.
3. **Write the short release notes.**
4. **Create the annotated tag.**
5. **Push only with human approval.** Ask, and wait.

Approval binds to OUTWARDNESS, not to versioning. Creating a tag or bumping
a file is bookkeeping and needs no ceremony. A push that triggers a deploy or a
publish is outward-facing and effectively irreversible, so it asks first. That
is why `version-file` bumps need no approval and a `tags` push does: one
instance shipped three patches in a day, and a confirmation on each would be
theater that teaches people to click through.

Do not report a release as cut until the tag exists AND the push has happened.
"Tagged locally" is not released.
