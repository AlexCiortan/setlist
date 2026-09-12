# The PRE-DIAGRAM generation of the two carriers the diagram half touches

These are `templates/git-hooks/setlist-hook-lib.sh` and `scripts/trunk-audit.sh` exactly
as they stood at commit `79549f2` (2026-09-10, spec 0135's cut), which is plugin 2.6.1 /
edition v1.14: the last bytes before spec 0136 added the diagram half.

**Why they are vendored rather than read out of git.** The absence differential is the
edition's central claim to an instance that has not opted in: with no `docs/diagrams/`
directory, every reader behaves exactly as v1.14. The suite proves it by RUNNING both
generations over the same corpus and requiring byte-identical output, which means it
needs the old bytes at run time. Reading them from history looked simpler and failed on
CI at the first attempt: the mutation check copies the tree somewhere without the
repository's history, so `git show 79549f2:...` returned nothing and the differential
went red on a Linux runner while passing on the developer's machine. A fixture that
travels with the suite runs everywhere the suite runs.

This is the same method and the same reason as `test/fixtures/pre-record-hooks/`, which
vendors the pre-record generation of all six carriers for the record edition's own
absence path.

**These files are frozen.** Nothing edits them; they are what shipped. When a later
edition needs a differential against a newer baseline, it adds a directory of its own
rather than moving these, because a baseline that moves is not a baseline.
