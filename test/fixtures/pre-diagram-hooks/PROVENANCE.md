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

**The one edit, 2026-10-13 (spec 0193, decision 4).** One line of `setlist-hook-lib.sh`, the one
that runs the project's gate command, changed in this directory and in the two sibling copies
(`test/fixtures/pre-attest-hooks/`, `test/fixtures/pre-record-hooks/`) exactly as it changed in the
shipped library: the command string is handed to `bash -c` as its argument instead of being run
with the shell's string-running builtin, because these copies ship in the package and a reader of
the package flags that builtin over a variable. The verdict does not depend on how the string
reaches the shell, and every differential that runs a copy runs both generations over the same
corpus, so the baseline still answers the question it was kept for. The shipped blobs the two
pinned copies stood for (`155ba1ae`, `58c265ee`) stay in `KNOWN_SETLIST_HOOK_BLOBS` for the
instances that carry them; the edited copies are not pinned, as the pre-record copy is not.

**The second edit, 2026-10-13 (spec 0193, item 6's fix).** The content scan's pattern variable,
`SLH_SECRET_RE`, is named `SLH_SHAPED_VALUE_RE` in all three copies as in the shipped library (two
lines each, its definition and its one read), because the package's reader counts a variable named
like a credential that a shipped file reads. The pattern's bytes and every verdict are unchanged.

**The third edit, 2026-10-13 (spec 0193, item 6's round-2 fix).** The trunk audit's refusal "pass --since
<ref>" reads "give --since <ref>" in the two copies that carry it (`pre-diagram-hooks/trunk-audit.sh`,
`pre-record-hooks/trunk-audit.sh`) as in the shipped audit, because the package's reader read "pass" at
that position as the password-store command. The verdict and the code are unchanged.

**The fourth edit, 2026-10-14 (spec 0193, item 6's round-5 sweep).** A comment of the two `pre-commit` copies
(`pre-attest-hooks/pre-commit`, `pre-record-hooks/pre-commit`) is re-flowed as in the shipped hook, its words
unchanged, so that no line begins with "pass" (the package's reader takes a line's first word, given an
argument, as the password-store command). No code moves.

**The fifth edit, 2026-10-14 (spec 0193, item 6's round-7 sweep).** Two variable names change in every copy
that carries them, as in the shipped library and audit: `pat` (a CODEOWNERS or Owns: pattern, in shell and
in the awk readers) is `glob_rule`, and `tok` (a verdict word, or a word of a command line) is `vword`,
because the package's reader read a variable named `pat` as a personal access token. Every awk reader that is
compared byte for byte across the carriers moves the same way in each, so the comparisons still hold; no
logic moves.

**The sixth edit, 2026-10-14 (spec 0193, item 6's round-10 sweep).** Three copies change in words only, as in
the shipped audit and gates, because the package's reader takes a word that prints the environment,
standing before a separator, as a read of it: a comment of `pre-diagram-hooks/trunk-audit.sh` reads
"the declared files" where it read "the set", and the wrapper-stripping pattern of
`pre-record-hooks/close-gate.sh` and `pre-record-hooks/commit-gate.sh` spells its last alternative `en[v]`,
which matches the same word. No verdict moves.
