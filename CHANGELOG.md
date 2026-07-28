# Changelog

Plugin releases. The framework edition (`setlist.md`) carries its own version
and its own changelog inside the file; where a plugin release does not move the
edition, it says so.

The plugin version counter restarted at 1.0.0 when the plugin was renamed to
`setlist`. Releases numbered 1.6.0 through 1.8.0 named in the edition's
changelog belong to the pre-rename plugin, so a Setlist version below those
numbers is not a downgrade.

## 1.0.7

Edition unchanged (v1.6). Two more bypasses closed, both in code 1.0.6 added,
both found by an independent review of the shipped release, and both reachable
by typing something ordinary. If you are on 1.0.6, this is the upgrade to take.

**Wrapper flags that take a separate value no longer strand it.** 1.0.6 taught
both gates to look past a wrapper like `nice` or `env`. It stripped the wrapper
word and then stripped flags one word at a time, which is fine for a flag that
carries its own value (`stdbuf -o0`) and wrong for one that does not: in
`nice -n 5 git merge --no-ff spec/0001-x`, the `5` was left sitting at the
front of the command, the gate no longer recognised the line as starting with
git, and it was never judged at all. `env -u VAR git merge ...` went the same
way. A flag is now consumed together with the value that follows it, with one
exception that matters: the command word itself is never swallowed, so
`env -i git merge ...` keeps its git.

**Discarding working-tree changes no longer looks like switching branches.**
`git checkout` is two commands sharing a name. With a branch it switches; with
a path it throws away local edits and switches nothing. The gate recorded the
argument as a branch either way, so `git checkout -- . && git merge --no-ff
spec/0001-x` concluded the merge would run on a branch named `.`, decided that
was not your trunk, and skipped every check. Discarding changes before a merge
is something people and agents do constantly, so nobody had to be trying. The
gate now tells the two apart: a real branch is tracked, an existing path leaves
the branch alone, anything after `--` is a path by definition, and an argument
that is neither refuses rather than guessing. `git restore` was never affected
and `git switch` needs none of this, because switch only ever takes a branch.

Both classes are now generated corpus axes in the test suite rather than
example cases, so they stay closed. The suite also checks that every shipped
skill's frontmatter parses, after `design-surface` shipped from 1.0.0 through
1.0.6 with an unquoted colon in its description: at runtime that skill loaded
with all of its metadata silently dropped, and the release gate that was
supposed to catch it had been pointed at the wrong manifest.

**Staging is more than `git add`.** The commit gate refuses a command that
writes the index and commits in one step, because it decides before the command
runs and would otherwise scan an index that does not hold your content yet. It
recognised `add`, `rm` and `mv`. Everything else that writes the index went
through, so `git stash pop && git commit -m x` and
`git restore --staged . && git commit -m x` committed content nothing had
scanned. `git stage`, a plain synonym for `add`, was missing too. The full set
is now recognised, and it is a generated corpus dimension checked against the
gate's own list, so the next verb cannot go missing quietly.

**A single `&` separates commands.** The gates split a command line on `&&`,
`||`, `;`, `|` and newlines, but not on a lone `&`, which backgrounds what came
before it and starts something new. So `echo hi & git merge --no-ff spec/0001-x`
was read as one command beginning with `echo`, and the merge was never judged.
`&&` is still one separator, not two, and an `&` inside a redirection such as
`2>&1` still is not one.

**A pathspec checkout is not a branch switch, even with a branch in front of
it.** 1.0.7 already handled `git checkout -- .`. It did not handle
`git checkout other-branch -- src/file`, which also restores files and switches
nothing: the gate recorded a switch that never happens and judged the next merge
against the wrong branch. The test is now the `--` separator itself, which is
what git uses to tell its own two commands apart.

**A closed spec's number cannot be reused to carry unreviewed work.** Every
close check reads the spec file as it stands on the branch being merged, which
settles what the artifacts say but not who wrote them. A branch cut from the
trunk after spec 0001 closed inherits that spec, Closing report and all, so a
branch named `spec/0001-anything` could merge arbitrary changes with no
artifacts of its own and pass every check. The gate now requires the branch to
have modified its own spec file. Writing the Closing report into the spec is
what closing a spec is, so an honest close is unaffected, including the common
case of planning a spec on the trunk and closing it on the branch.

**Upgrades check that the gates are actually wired.** `refresh-instance.sh`
verified your hook FILES were current and, separately, that the entries present
in `.claude/settings.json` were well formed. It never checked the gates were
there at all, so an instance with both gate entries deleted was reported as a
complete refresh, exit 0, with a note that the refreshed gates would bind from
the next session. They would never bind. It also claimed hooks it does not own:
a hook of yours living in `.claude/hooks/` with no timeout was reported as a
Setlist entry and produced an upgrade that could never be completed, because
the fix it demanded was editing your own file. Ownership is now by name.

## 1.0.6

Edition unchanged (v1.6). Two bypasses closed, both found by review of 1.0.5,
one of which fired on an everyday command.

**`git checkout -` no longer walks past the close gate.** The gate tracks
which branch each part of a command line runs on, so that a compound like
`git checkout main && git merge --no-ff spec/0001-x` is recognised as a close.
It read the branch name as the first argument that was not a flag, and `-` is
a flag as far as that reading goes, so it was skipped: the gate believed the
merge was still running on the spec branch, which is a case it deliberately
allows. `git checkout -` right after `git checkout spec/0001-x` is how a
person and an agent both return to the trunk, so this was reachable without
anyone trying. The gate now resolves `-` and `@{-1}` (it runs before your
command, so the previous branch is still there to resolve), and if it cannot,
it refuses rather than assuming the merge is harmless.

**Wrapper prefixes no longer escape either gate.** `command git merge ...`,
`env git merge ...`, `nice`, `nohup`, `exec`, and a leading `VAR=value`
assignment all reached the trunk unchecked, and `command git commit -am x`
walked past the commit gate the same way. Both gates now strip those prefixes
before deciding whether a command is one they govern. That list is not a claim
of completeness and cannot be one; the trunk audit is the designed catch for
the wider family, because it reads what ended up in your history and does not
care how the command was spelled.

**The two layers are now documented as one story.** Known limitations
previously described the Bash escape hatch as a file-writing route, without
saying that running git through another interpreter (`sh -c '...'`, a
backtick) is the same boundary, and the sideways-routes list did not mention
merging a spec branch under a second name. Both are named now, each is
cross-referenced to the trunk audit as the thing that catches it, and the test
suite pins the pairing: the interpreter forms pass the gate AND their outcome
is caught by the audit. The audit's opt-in status is stated plainly in the
same place, because until you install it the hooks are the only enforcement
running, and the hooks are the layer that can be spelled around.

## 1.0.5

Edition unchanged (v1.6). A release about how releases are checked, and one
substantial fix that its own new checking found at a scale no review had.

**A merge into your trunk can no longer hide behind the shape of the command
line.** 1.0.4 read the merge's arguments from the text after the LAST
occurrence of the word `merge`. Two consequences, both live: a compound like
`git merge --no-ff spec/0001-x && git merge main` discarded the first merge's
arguments entirely and passed with no close condition checked, and any commit
message containing the word, `-m "improve merge of main"`, displaced the real
arguments and did the same. The second is the serious one, because it fires on
ordinary usage with no intent at all.

The gate now splits the command line on its connectors and judges each segment
on its own, tracking which branch each segment runs on, and reads a merge's
arguments from the FIRST merge token in its own segment. A generated corpus
found 144 spellings of this class; all 144 now deny. The same change removed
an over-denial nobody had reported: `echo git merge spec/0001-x` was denied
though nothing merges. The commit gate received the same treatment, which
fixed the same shape of over-denial there.

**A trunk audit, advisory.** `scripts/trunk-audit.sh` reads your trunk's
history and reports any commit that put code into it outside a closed spec.
It answers a question no command parser can answer correctly, because a shell
command can compute its own arguments while history simply is what it is. It
catches by construction what a parser misses: chained merges, a branch renamed
to hide it, cherry-picks, tags, the merge button on your forge. Nothing calls
it automatically in this release, it gates nothing, and a finding blocks
nothing; run it yourself when you want to know. It was validated against 148
commits of real project history before shipping.

**The trunk audit can run at push time, if you want it to.** A sample git
`pre-push` hook ships alongside the audit. Copying it into `.git/hooks/` makes
the audit run at the last moment your history is still private, which is also
the only place a local hook can notice work that arrived through your forge's
merge button. It refuses the push rather than passing if it cannot find its
own tool, because a check that could not run has not passed. Nothing installs
it for you, and it is not part of the protocol.

**Generated tests, not just written ones.** The suite now generates its
adversarial inputs rather than enumerating them, for both the close gate and
the commit gate, and asserts the inverse in each case so a gate that denies
ordinary work fails too. Every deliberate limitation in Known limitations is
now either pinned by a test or recorded as unassertable with the manual
procedure that would check it, and the release tooling refuses to publish when
those two lists disagree.

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
