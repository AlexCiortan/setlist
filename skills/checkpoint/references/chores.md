# Chores: the branch, the archive line and the record

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

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
- **Chores:** record the chore under `chores.<id>` with its `files` (the
  declared set the audit checks per file) as the chore is worked, and flip
  `status` to `"done"` beside the archive line.
