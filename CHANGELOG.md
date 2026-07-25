# Changelog

Plugin releases. The framework edition (`setlist.md`) carries its own version
and its own changelog inside the file; where a plugin release does not move the
edition, it says so.

The plugin version counter restarted at 1.0.0 when the plugin was renamed to
`setlist`. Releases numbered 1.6.0 through 1.8.0 named in the edition's
changelog belong to the pre-rename plugin, so a Setlist version below those
numbers is not a downgrade.

## 1.0.4

Edition unchanged (v1.6). Fixes two defects introduced by 1.0.3 itself, both
found by review of the shipped tree.

**A trunk merge that names a real, non-spec branch is allowed again.** 1.0.3
denied every merge into your trunk that did not literally name a `spec/` or
`chore/` branch. That caught the case it was aimed at, but it also denied
`git merge origin/main`, release branches, and upstream syncs, none of which
are spec closes. Worse, `git pull` achieved the identical result and was never
gated, so the denial added friction without adding safety. The gate now
separates the two cases: a merge argument that resolves to a real ref is a
sync or an integration merge and passes, while forms whose target cannot be
read from the command at all (a shell variable, `-`, `@{-1}`, `FETCH_HEAD`, a
bare commit SHA) are still denied, because the close conditions cannot be
checked against a branch the gate cannot identify.

Related: the gate now reads only the arguments that follow `merge`. A compound
like `git checkout spec/0001-x && git merge main` previously had the spec
branch read off the `checkout` and gated as though it were being merged.

**The upgrade's settings check no longer misjudges your settings file.** 1.0.3
introduced a check that your `.claude/settings.json` carries the current hook
wiring, and it inspected the file as text. Two consequences, both reported from
real use: a project's own hook with no timeout (a formatter, say) produced an
INCOMPLETE that no edit to Setlist's wiring could clear, since the fix it
demanded was editing an unrelated hook; and because the count was per line
rather than per entry, a minified settings file could pass with hooks that had
no timeout at all. The check now reads the file as JSON, considers only the
four entries whose commands point into `.claude/hooks/`, ignores every hook you
added yourself, and names the exact entries that need attention. A settings
file that does not parse is reported as unreadable rather than assumed clean.

Also: the hook timeout unit is now verified live rather than assumed. It is
seconds, and a hook that exceeds it is cancelled while the tool call proceeds.
Both directions are recorded in the close gate's header.

## 1.0.3

Edition unchanged (v1.6). A hardening release: every fix is a change to what a
gate does when it cannot evaluate its own question.

- The close gate denies a merge into the trunk whose branch it cannot
  identify, instead of allowing it. Previously `git merge $BRANCH`,
  `git merge -`, `git merge @{-1}`, `git merge FETCH_HEAD`, and merging a raw
  commit SHA all reached the trunk with no close condition checked.
- The trunk rule covers every tool that writes a file. `NotebookEdit` was
  outside the matcher, so notebook changes landed on the trunk untouched. The
  hook also reads `notebook_path` as well as `file_path`, and denies a write
  event carrying neither.
- Every stamped hook entry carries an explicit timeout. A hook the harness
  cancels is a gate that did not run, and the close gate re-runs your full
  suite.
- `git rm` and `git mv` join `git add` as denied stage-and-commit compounds:
  all three write the index while the command runs, after the gate has already
  read it.
- Every silent pass inside a hook now carries a written justification, and the
  test suite fails if one appears without it.

Documentation: a minimum Claude Code version (2.1.193), and three additions to
Known limitations covering timeout cancellation, hooks running without your
interactive PATH, the sideways routes to the trunk that the close gate does not
parse, and the staged-content scans reading vendored code and fixtures.

## 1.0.2

Edition unchanged (v1.6). The upgrade path learns direction.

- `.claude/sdd.json` records the plugin version that stamped the project,
  written at stamp and at every refresh.
- The refresh refuses to move a project backwards, and refuses when it cannot
  determine either version rather than guessing. It reports by default and
  writes only with `--apply`, so a file you customised is surfaced before
  anything overwrites it.
- `/setlist:upgrade` and `/setlist:validate` state which plugin version they
  are operating from and compare it against the newest version in the plugin
  cache, because a session binds its plugin tree when it starts. If a newer one
  has arrived, they say so and refuse to refresh until the session restarts.
- The close gate stopped denying compliant merges: it found the end of the QA
  Pass 1 block by looking for the text "QA Pass 2" anywhere in a line, so a
  report whose QA-1 notes mentioned QA Pass 2 in passing had its verdict cut
  out of the block.

## 1.0.1

Edition unchanged (v1.6). Three fail-open fixes and the test suite.

- The gates deny rather than allow when `jq` is missing, and the session says
  so at startup.
- The scope hook canonicalises paths, so `./src/x.js` no longer reached the
  trunk by spelling.
- Both Bash gates tolerate the ways a git command can be written; a quoted
  branch name previously disabled the close gate outright.
- A hook test suite runs on Linux and macOS on every push.

## 1.0.0

The first Setlist release, carrying framework edition v1.6.
