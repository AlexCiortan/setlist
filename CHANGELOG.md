# Changelog

Plugin releases. The framework edition (`setlist.md`) carries its own version
and its own changelog inside the file; where a plugin release does not move the
edition, it says so.

The plugin version counter restarted at 1.0.0 when the plugin was renamed to
`setlist`. Releases numbered 1.6.0 through 1.8.0 named in the edition's
changelog belong to the pre-rename plugin, so a Setlist version below those
numbers is not a downgrade.

## 2.1.0

**Edition v1.9 (the reckoning edition).** A corrections-and-doctrine release: the
framework document is edited for accuracy and gains one new principle. No command,
hook, or gate behaviour changes.

- The Part 8c upgrade description now names the git-hook boundary explicitly (which
  files a pre-v1.8 upgrade delivers, and the two git settings it turns on) instead of
  a generic description.
- The Known limitations "pathspec hole" is restored to its narrow, original meaning
  (`git commit <file>` only); the nested-repository index hole and the
  `GIT_INDEX_FILE` hole are named as their own, separate limitations instead of being
  folded into it.
- Two references to a private design document that was never published are removed
  from the edition text; the affected passages now name the mechanism directly.
- A stale README bullet claiming the shipped gate messages still promise a denial is
  corrected to match the shipped, advisory wording.
- This changelog's own 1.1.0 entry below gains a one-line note that it was an
  internal milestone, never tagged in this repository.
- **New doctrine (Part 6):** a comparison should assert the size of what it is
  comparing and refuse on zero rather than pass an empty comparison silently, and
  every green result should be labelled with what it is evidence of rather than
  assumed to mean more than it tested.

## 2.0.0

**Edition v1.8 (the boundary edition).** A MAJOR release because the guarantee's
semantics change, not because the mechanism was rewritten: the same hooks refuse the
same things, and what moves is which layer the project calls its guarantee.

- **The guarantee is the push-time trunk audit.** `pre-commit` and `pre-merge-commit`
  keep refusing at commit and merge time, with the same reasons, as early warning inside
  the boundary. The audit at `pre-push` is what stands between unreviewed work and a
  shared trunk. A route past a per-merge hook is a MAJOR in this project's severity
  model rather than a release blocker: the work is refused later than intended, at push,
  rather than not at all. This is the same reclassification v1.7 made for the session
  gates, one layer in, and for the same measured reason.
- **The audit decides by identity and ancestry, never by shape.** Its last shape-decided
  outcome is gone: a merge's parent count no longer decides whether the pre-rule
  exemption applies. Nothing was relaxed, and pre-adoption history keeps the exemption
  every pre-rule merge keeps.
- **`/setlist:retrofit` no longer switches off a hook layer it does not own.** The stamp
  wrote `core.hooksPath` unconditionally, so retrofitting into a project already using
  husky, lefthook or pre-commit disabled that project's own hooks, secret scanning
  included, with no warning. It now refuses before its first write, decides ownership by
  the CONTENT of the hooks directory rather than by its name, and keeps
  `SETLIST_ADOPT_HOOKSPATH=1` as the deliberate override. **If you retrofit into a
  project with an existing hook layer, this release will stop and tell you, where the
  previous one silently continued.**
- **The model bindings in Part 2 are re-verified against the live harness**, with the
  verification date and method recorded in the table.
- **First push to a brand-new EMPTY remote now audits every pushed branch as a trunk
  candidate.** An empty remote has no default branch yet and forges adopt the first pushed
  branch as the default, so the push-time audit cannot tell which pushed ref is about to
  become the trunk and audits them all. The clean trunk pushed on its own passes; a spec
  branch pushed first, or alongside the trunk, is refused, because unclosed feature code
  must not become a remote's default by a raw push. Push the trunk first, or use
  `SETLIST_SKIP_TRUNK_AUDIT=1` for a deliberate exception. This closes a case where such a
  branch was previously allowed while the audit read the local trunk instead.
- **The mandatory Architecture-diagram close field is read from live text only.** A line
  that appears only inside a fenced code block no longer answers it, at any layer including
  the push-time audit, matching how the inventory row and QA verdict are already read.

## 1.1.0

*An internal milestone: this version was never tagged in this repository and shipped as part of 2.0.0.*

**Edition v1.7 (the convergence edition).** The enforcement boundary moves from
the Claude Code hooks to GIT hooks, and one setting changes behaviour you will
notice on day one.

**Read this first: `merge.ff = false`.** The stamp now sets it, alongside
`core.hooksPath`. Merges that used to fast-forward will create merge commits.
This is not cosmetic and it is not optional: a fast-forward merge fires no git
hook at all, so without it a plain `git merge spec/0001-x` walks unreviewed work
onto your trunk past everything else. If you have tooling that assumes
fast-forward merges, this is the change to plan for.

**What moved and why.** The three PreToolUse gates decided what a command would
do by reading the command's text. Across five releases every hardening pass
closed one spelling and the next release found another, because a shell command
can compute its own arguments. Then 1.0.8 died on macOS for a reason that had
nothing to do with command text and allowed everything in silence, while a git
hook on the same machine in the same run was untouched.

So the guarantee moved. `pre-commit`, `pre-merge-commit` and `pre-push` are
stamped into a tracked `.githooks/` directory and git runs them from its own
state, after argument parsing and after `$(...)` is expanded. The PreToolUse
gates remain, are still useful, and are now described as ADVISORY: they warn
before the command runs, which no git hook can do. A new bypass spelling of that
layer is now a MAJOR rather than a release blocker, because the work still
cannot reach the trunk.

**The release rail.** Projects declare how they record a version in a `release`
block in `.claude/sdd.json`: `none` (the default, and the right answer if you
ship nothing yet), `tags`, or `version-file`. `/setlist:checkpoint` grows the cut
ceremony, with approval bound to OUTWARDNESS rather than to versioning.

**Also**: BUILT and PARKED join the spec lifecycle; a Closing report can now
record a criterion that is structurally blocked rather than merely unrun; the
QA-verdict rule was widened after it was measured rejecting 15 of 18 real specs
in a live project; and the edition gained a Known limitations section that says
plainly where the mechanical layer ends, including `--no-verify` and the fact
that the config pointing at your hooks is per-clone.

`/setlist:upgrade` performs all of it and will tell you about `merge.ff`.

## 1.0.9

Edition unchanged (v1.6). **If you are on macOS and running 1.0.8, update now.**
On a Mac, 1.0.8's commit gate and close gate did not deny anything. They did not
crash and they printed no error: they allowed, silently, every commit and every
merge they exist to check. Linux and WSL were never affected. 1.0.7 and earlier
were never affected on any platform.

**The cause was one stray character, and the platform decided whether it
mattered.** Both gates normalise the command they are given through a small awk
program, and in 1.0.8 that program ended with `}\'` instead of `}'`. GNU awk and
mawk, which is what Linux ships, accept the trailing backslash without comment.
The BWK "one true awk" that macOS ships as `/usr/bin/awk` rejects it: syntax
error, exit status 2, nothing written to standard output. The normalised command
therefore came back EMPTY, the test for "is this a command I govern" matched
nothing, and each gate concluded it had nothing to do. An empty read was
indistinguishable from an absent one, and absence read as permission.

That is the same failure this project fixed one layer down in 1.0.8 itself, when
a `jq` that existed but could not run made the gates allow in silence. There the
dependency was broken; here it was merely STRICTER. Both gates now carry the
rule in the file: the lexer's awk program must not end in a backslash, and a
gate whose lexer can fail must not treat lexer failure as a clean parse.

**Nothing else changed.** This is a two-file, two-byte repair plus the comments
explaining it. No new command spellings are recognised, no gate semantics moved,
no checks were added or removed. Everything 1.0.8 closed stays closed.

**How it escaped, stated plainly.** 1.0.8's evidence was real and it was
platform-scoped. Every mechanical leg ran under Linux and GNU awk, where the
defect is invisible by construction, and the release shipped with the macOS leg
listed as an outstanding debt to be watched after the push rather than a gate to
be passed before it. It went red on the first run: 169 of 451 assertions failed
on `macos-latest` while the Linux leg was green. For 1.0.9 that debt is a
blocking pre-publish gate instead of a note, and the suite is now also run
locally under bash 3.2 with BWK awk, the same implementations macOS ships.

## 1.0.8

Edition unchanged (v1.6). An adversarial review of the exact 1.0.7 tree found
nine ways past the gates; all nine are closed here, together with two older ones
that had been deferred. Every one of them was present in v1.0.6 as well, so this
is the release to take from any earlier version.

They turned out to be three defects rather than eleven, which is why they could
be fixed together.

**A ref is identified by the commit it names, not by how it is spelled.** The
gate used to recognise a spec branch by stripping three literal prefixes from
the merge argument. Every other spelling of the same commit read as an ordinary
sync merge and skipped every close check: `heads/spec/0001-x`,
`remotes/origin/spec/0001-x`, another remote's name, a TAG pointing at the
branch, an alias branch, a raw commit id. Worse, for `origin/spec/0001-x` the
strip produced the LOCAL branch name, so a compliant local branch could
green-light a non-compliant remote one: the thing checked was not the thing
merged. The gate now resolves the argument to a commit and asks git which refs
point at it. A spelling nobody has thought of resolves like one everybody knows.

This also closed a documented limitation without anyone aiming at it: merging a
spec branch under a second name was on the known-holes list because an alias is
a different string. An alias points at the same commit, so it is simply governed
now.

**Shell grammar no longer hides the command.** Wrapping a merge in `{ ...; }`,
`if ... then`, `for ... do`, or prefixing it with `!` moved the git verb out of
the position the gate inspects, and all four really did land a merge on the
trunk. Reserved words are stripped at the head of a segment now, in both gates.

**Quoted text is opaque.** The close gate deleted quote characters and kept
their contents, so a commit message that merely mentioned a checkout could
retarget the branch the gate believed it was standing on. The commit gate did
the opposite, deleting whole quoted spans, so quoting the word `git` or `commit`
deleted the word it matches on, and an odd number of quote characters in
ordinary prose swallowed the real command. Neither treatment could serve both
gates. A quoted span of one shell-safe word (a branch name, a binary, a
subcommand) is now kept as that word, and anything longer becomes a single inert
token that cannot supply a command or split a line. Escaped quotes are
understood, so the ordinary way of writing a contraction no longer confuses the
scan.

**Two smaller ones.** A `.claude/sdd.json` that is valid JSON but not a single
object (a top-level array, or two documents in one file, which a half-merged
config produces) silently disabled the trunk rule in both the close gate and the
scope hook; both now require one object. And the 1.0.7 upgrade check for
"are the gates wired" matched the hook filename anywhere in your settings, so
gates moved to the wrong hook event, or given a matcher that never names the
tool they govern, certified as a complete refresh. It checks the event and the
matcher now.

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
