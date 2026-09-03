# Changelog

Plugin releases. The framework edition (`setlist.md`) carries its own version
and its own changelog inside the file; where a plugin release does not move the
edition, it says so.

The plugin version counter restarted at 1.0.0 when the plugin was renamed to
`setlist`. Releases numbered 1.6.0 through 1.8.0 named in the edition's
changelog belong to the pre-rename plugin, so a Setlist version below those
numbers is not a downgrade.

## 2.4.1

**Edition v1.12 (the record edition), unchanged.** A maintenance release, the first
since the limitations campaign closed at 2.4.0: documentation and hook hygiene, no
protocol change, no new command, and no new gate question.

- **A repository's own diff configuration could blind every content scan, and it is
  fixed.** The scans read the output of `git diff` and `git show`, which is a
  rendering the repository controls. With `color.ui=always` (or `color.diff=always`)
  git colours its output even into a pipe, the added-line filter matched nothing, and
  a live-shaped secret committed and pushed clean at exit 0 with nothing printed,
  at every layer. Found by the project's own records sweep at the 2.4.0 close (an
  unverified claim from that release's review, confirmed by control), fixed here at
  every site that renders a diff for a scan or a detector:
  `templates/git-hooks/pre-commit`, `templates/git-hooks/pre-merge-commit`,
  `templates/git-hooks/pre-push`, `templates/git-hooks/setlist-hook-lib.sh` (the
  lifecycle detector, which read the same rendering) and the advisory
  `templates/hooks/commit-gate.sh` at both of its sites. The fix is flags that ignore
  configuration (`--no-color`, `--no-ext-diff`, `--no-textconv`), each member measured
  before it was pinned: colour blinds every site; an external diff driver blinds the
  three sites that lacked `--no-ext-diff`; a textconv driver hides the content it
  converts; prefix settings blind nothing, so no prefix flag is pinned. Two more
  members came out of the same measurement. `log.showRoot=false` renders a ROOT commit
  as nothing, so a first push's first commit was scanned as empty, while the trunk
  audit in `scripts/trunk-audit.sh` could not find the commit that adopted the rules
  under the same setting and refused every push by accident, a false denial that hid
  the scan's blindness; both readers take `--root` now. And every site took its diff
  through a command substitution that lost git's own exit status, so a git that ran
  and died rendered nothing and nothing read as clean; every site now reads the
  status and refuses under the codes that already exist for a scan that could not
  run. The shipped suite pins all of it, each case watched red on the previous
  release's bytes first. No new refusal code: the scan asks the same question it
  always asked, of the bytes rather than of a rendering.
- **Two bullets move from Open limitations to Design boundaries.** The
  identity-by-commit alias bullet and the wiring-check bullet had carried Status
  lines reading "documented boundary" and "documented restriction" since 2.4.0's own
  review, while sitting under a heading that says "defects and gaps rather than
  decisions". Each now sits with the decisions, with the move and its date stated in
  the bullet's own text and nothing else in it changed.
- **Five more bullets are RULED design boundaries rather than open defects, and one
  duplicate is merged.** Each ruling is dated 2026-09-02 in the bullet's own text and
  argued against the standing policy (the list shrinks by fixing, never by editing; a
  bullet crosses only when its residue is a dated decision). The fast-forward and
  `--squash` bullets: their fixes shipped in 2.2.0 and 2.4.0 for a one-commit close,
  and what remains is that git fires no hook for a fast-forward and git's own error
  message names neither Setlist nor the setting. The tested-platforms bullet: a list
  is never a proof, however long it gets. The path-scoping bullet: its advisory half
  was ruled closed by honesty on 2026-08-28. The scanning bullet: its four scheduled
  holes were fixed in 2.2.0 and the rest is structural. And "The secret scan is a
  first cut" said, word for word, what the scanning bullet already says, so it is
  merged into that bullet's pattern-set sentence with its field-report line intact:
  the list goes from 35 to 34 by de-duplication, stated here so the count change is
  never read as a fix. **The counts as they leave: 29 design boundaries, 4 open
  limitations, 2 upstream conditions, 35 in all**, the fourth open limitation being
  the one this release's own review found, below.
- **This release's own adversarial review, and what it found.** Twenty-two candidates,
  fourteen refuted (two filed as blockers among them: the `.gitattributes` half of the
  scanning class, which the bullet deliberately leaves open, and a first-block QA reader
  the replay showed refusing). Eight survived. One is a false denial disclosed in the list
  rather than fixed: a merge completed on the trunk side as the hook's message prescribes
  lands at commit and is refused at push, present unchanged in 2.4.0 and scheduled. Three
  are recorded in the bullets whose class they are: a symlinked leaf the scope gate does
  not follow, a `&&`-then-`;` checkout spelling under the parser freeze, and a
  comma-joined matcher the wiring check reports in the safe direction. Four are defects in
  this project's own checking tools and its suite, which never block a release and are
  fixed after it.
- **The Known-limitations list is now checked by an instrument, not by a habit.**
  Before this release can be attested, and on every push to the source repository, a
  comparator reads the list as one structure (each group heading's count against the
  bullets under it, every Status paragraph against the bullet it belongs to, the three
  surfaces that count the same things against each other, this changelog's counts line
  against the headings) and reads every "landed", "shipped" or "fixed" sentence in the
  newest entry of this changelog against the diff behind it, refusing a claim with no
  diff and counting a claim that names no file rather than passing it. It found two
  defects on its first runs, the orphaned Status paragraph above and, inside itself, a
  counts-line reader that took the first line mentioning the phrase rather than the
  first line counting; both are fixed here. Its threshold is deliberately low: it
  catches a claim with nothing behind it, and does not pretend to judge whether a diff
  implements a sentence.
- **The suite runs sharded, and the Linux leg runs it a second time under GNU awk.**
  `test/run-tests.sh` gained `--shard K/N` over marked regions, `test/run-shards.sh` runs
  the shards and refuses a run that covered less than a serial one (a missing shard, a
  region claimed by nobody or by two), and `.github/workflows/test.yml` runs both, plus
  the alternate-awk leg that is the extension the tested-platforms bullet now names.
  These landed in the source repository after 2.4.0 shipped and reach the public tree
  with this release.
- **Four Status lines that had gone stale are put right in place.** The `--squash`
  bullet said its fix was scheduled for one release after the fix shipped in 2.4.0.
  The tested-platforms bullet said the matrix widening was queued after the first
  extension (the suite run a second time under GNU awk on the Linux leg) had
  landed. The path-scoping bullet called its advisory half "the remaining piece" for
  two releases after the 2026-08-28 ruling that closed it by honesty. And one Status
  paragraph had drifted two bullets away from the `@{u}` bullet it describes, so a
  reader attributed it to the wrong limitation. The frozen-parsers bullet also said
  two of its sentences twice.

## 2.4.0

**Edition v1.12 (the record edition).** Close and chore state become a record the
machine owns. The gates stop deriving facts from rendered markdown, which is the
architecture that produced the reader-class defects this changelog has been reporting
for four releases, and read `.claude/status.json` instead: a small JSON inventory with
one-token facts, written only by `/setlist:checkpoint`.

**What it does.** New and retrofitted instances are stamped with the record from birth.
Checkpoint records each spec at its cut, updates its lifecycle token at each flip,
writes the close facts (`qa_pass_1`, `diagram`) at the close, and records chores with
the files they touch. The git hooks and the push-time audit read those facts; the
STATUS.md page and the spec's Closing report stay exactly what they were, FOR PEOPLE,
and `/setlist:validate` reports record-versus-page divergence as information.

**A close now declares what it owns.** As a build acquires role-path files, checkpoint
appends `Owns:` lines to the spec's header. A single-parent close (`--squash` or
fast-forward) of a declaring spec is audited FILE BY FILE against that declared set,
so a close can no longer exempt a whole commit by flipping one status row: the
smuggled file is refused by name, with the two honest exits named in the message.
Chore closes take the same per-file question against the chore's declared files, which
is what finally lets a compliant `--squash` or fast-forward CHORE close through both
layers (the 2.2.0 release notes' item 4 debt, `F5-2026`, closed without widening
anything). The residual is disclosed in Known limitations rather than papered over:
the hooks verify coverage, not truth, and a spec that declares nothing closes under
the previous rules exactly.

**Nothing changes unless the record exists.** An instance without `.claude/status.json`
behaves byte-for-byte as it did on 2.3.0, proven by a pinned differential in the
shipped test suite rather than asserted; the two frozen page readers are retained
byte-identical as that path, permanently. A record that is present and malformed
REFUSES with a named code and never falls back. `/setlist:upgrade` mentions the record
and migrates nothing; opting an existing instance in is a one-time, human-confirmed
transcription by checkpoint.

**Known limitations moves by fixing, for the first time in this campaign.** The
Architecture-diagram last-match bullet leaves the list: its mechanical halves
(first-line-wins, the anchored answer) shipped in 2.3.0, the bullet had been stale
since, and the class itself cannot exist on the structured path, where the diagram
answer is a one-token record field. The single-parent content-exemption bullet is
REPLACED by a design boundary stating the declarations model and its limits, because
the exemption persists for closes that declare nothing and saying otherwise would be
an over-claim. The counts move with the bullets: 22 design boundaries, 11 open
limitations, 2 upstream conditions, 35 in all.

## 2.3.0

**Edition v1.11 (the attestation edition).** The headless build integrity chain. If
anything builds your project without a human watching (CI, a `claude -p` run, a
scripted batch), this release is the one that stops an unapproved build's output from
becoming a commit and, at push, from being shared.

**What it does.** Declare an `attestation` block in `.claude/sdd.json` and
`/setlist:checkpoint` writes and signs an approval when a spec goes ACTIVE, binding it
to that spec's exact bytes. The git hooks then refuse a build commit, a push, or a
close whose spec has drifted since that approval. The existing `Spec-hash` record and
its session-start warning stay exactly as they were and sit underneath it; the two
answer different questions, and a spec whose hash was quietly recomputed by hand passes
the first and fails the second.

**What it is worth, which the mechanism prints rather than leaves you to work out.** A
signature proves a key was used, not that a person decided. If your signing key sits
where the build process can read it, a headless run can sign its own approval and the
chain will verify, establishing that the run had the key, which is not the question. So
Setlist makes you DECLARE where your key lives and names that declaration in every
verification it emits, including the ones that pass. `signer` custody (a key you hold,
which the build cannot read) is the model that addresses the problem.

**Nothing changes unless you turn it on.** No `attestation` block means the feature is
off, and off is byte-for-byte the behaviour you have today; an upgrade delivers the key
set to `false` and migrates nothing. Turning it on is a decision about where your key
lives, not a migration step, and `/setlist:upgrade` will say so rather than doing it for
you. **`forge` custody is designed and not built:** declaring it refuses and tells you
why, and its verification arrives with the forge-side required check.

**A correction to an earlier draft of these notes, stated plainly rather than quietly
fixed.** A draft of this entry claimed four repairs as shipped that were not written.
The claim was false when it was made. It was caught before release by this project's own
adversarial review, which reads the changelog as ground truth and reported the code as
contradicting it; the repairs below are the ones that then actually landed, and the one
that did not is named as deferred rather than promised again. A release note is a claim
about bytes, and this one was audited against the bytes before it shipped.

**Also in this release.** A no-git probe in the commit gate, so a broken or missing git
can no longer make every staged-content check report clean having read nothing. A
correctly-wired hook is no longer certified NOT WIRED when its matcher is `*` or absent,
so `/setlist:upgrade` on a working instance no longer exits INCOMPLETE forever. The
Architecture-diagram field is read as an answer rather than as a sentence containing one,
and it is decided by the FIRST such field rather than the last, so a later note can
neither answer nor unanswer it. The QA verdict block is likewise decided by the FIRST
block, so an illustrative example placed after a real verdict no longer replaces it. A
secret on an added line whose text begins `++ ` is no longer deleted from the scanners'
own input at either layer. A `scaffolded` value that is present and not a boolean now
reports itself instead of silently standing the trunk-write gate down. The advisory
session gates carry a machine-readable code on every refusal, not only on some. The
advisory commit gate now says that path exclusions are evaluated at the git-hook layer
and that it does not read them, so you can tell from the message whether a commit will
actually be blocked. The Known-limitations list gains the empty-remote trunk-audit
boundary, which the framework document described and this list did not.

**What is NOT in this release, named rather than promised.** This release's own adversarial
review found more than it fixed, and the remainder is listed here rather than left for you
to discover.

A compliant chore close spelled `--ff` or `--squash` is still accepted at commit and
refused at push. Its scoped fix was measured during the review to widen a more serious
exemption in the same code, so it is deferred with that measurement published rather than
taken in a way that would trade a disclosed gap for an undisclosed one. That more serious
exemption is now a Known limitation in its own right, stated at its real width: a
single-parent trunk commit that closes a spec is content-exempt at the push-time audit.
Both are the same underlying gap and they are scheduled together.

A `scaffolded` value that is present and not a boolean still stands the session scope gate
down silently instead of reporting itself. The one-line fix was written during this cycle
and cut: it needs a new refusal code, a new code is a new question, and a new question
under this project's own release rules means a full adversarial review that a repair round
does not get. It is scheduled for a cycle that owes one anyway. The layer affected is the
advisory session gate; the git hooks, which are what refuse, are unaffected.

Two defects in this project's own private checking tools were also found and are deferred
under the rule that a defect in a checker never blocks a release. They do not affect
anything you install.

## 2.2.0

**Edition v1.10 (the scoping edition).** The enforcement release. Unlike the two
before it, this one changes the bytes that do the enforcing: the git hooks, the
push-time trunk audit, the advisory session gates, and the upgrade certification all
move. It is the first release since the hooks were pinned by content that REPLACES
hook bytes in an existing instance, so `/setlist:upgrade` does more here than move a
document.

- **The false denial disclosed in 2.1.0 is FIXED.** A spec that QUOTED the
  closing-report template inside a fenced code block, changed no lifecycle state, and
  did not stage `specs/STATUS.md`, was refused an ordinary commit with
  `[SLH-STATUS-MISSING]`. The detector read the raw staged diff and did not strip
  fences, so quoted text was read as if it were live. The same regex meant an indented
  `## Closing report` heading was not matched at all, while three other readers in the
  same release accepted it. Both halves are one fix, made in the SHARED reader rather
  than a fourth private copy, so all four readers now agree. The 2.1.0 notes promised
  this to this release; the reproduction from that disclosure is now a fixture, and it
  commits clean.
- **The staged-content scans can be PATH-SCOPED, and this is the release's one new
  feature.** Vendored trees, fixtures carrying dummy credentials and quoted external
  text are not your writing, and splitting the commit never separated them from the
  scanner. Declare the paths as repo-relative globs in `.claude/sdd.json`:
  `"scan_exclusions": ["vendor/**", "test/fixtures/**"]`, honoured by the em-dash and
  secret scans at the commit layer and the push layer alike. Four properties are part
  of the mechanism rather than incidental to it. **Every skip is printed, naming the
  file and the glob that matched it**, because an exclusion nobody is told about is a
  hole one directory over. The set reaches those two scans and nothing else, so it
  cannot quiet the trunk audit, the close checks or role-path judgment. A set that
  cannot be read, or one made only of wildcards, is refused with a named code rather
  than resolved in either direction, because a config error that quietly scans
  everything ignores a declaration while one that quietly scans nothing is an exemption
  nobody wrote. And declaring nothing leaves the scans exactly as they were. Where a
  match cannot be decided the scan RUNS: a case-variant spelling and a path git had to
  quote are scanned, and say so. This is scoping, not an off switch, and there is
  deliberately no pattern that means "all". **One piece is not done**: the in-session
  advisory commit gate is not path-scoped, so inside a Claude Code session a commit of
  excluded content is still denied there while the git hooks accept it.
- **A compliant SPEC close is no longer permanently unpushable.** A fast-forward or
  `--squash` close of a spec branch that is otherwise compliant was refused by the
  push-time trunk audit and could never be pushed at all. The audit now decides on parent
  COUNT, so one fix covers both spellings. **A compliant CHORE close spelled that way is
  still refused at push**, which is unchanged from previous releases and is disclosed in
  the release notes as a known open issue. Preferring `--no-ff` avoids both.
- **The skip variable stops being all-or-nothing.** `SETLIST_SKIP_TRUNK_AUDIT=1` now
  narrows to the audit arm alone: the secret and em-dash scans keep running, so a push
  that skips the history check is not also a push with the content checks off.
- **The push-time scan reads every commit in the pushed range**, rather than diffing the
  two endpoints, which missed content added and then removed across a range. A first
  push of the trunk derives a range that cannot be empty, and a tag push whose target
  introduces commits is either scanned or refused by name: a scan of nothing must never
  read as a scan that found nothing.
- **The advisory gates say so when they cannot run.** With `git` unusable, the close gate
  and the scope hook produced zero bytes, which reads as approval. They now probe for a
  usable repository and emit an explicit refusal code instead. Two pieces of advice that
  pointed at a variable with no effect at the refusal in question are corrected, and no
  gate message promises a denial it does not deliver.
- **The upgrade certification stops reporting the wrong answer in both directions.** It
  read one tool's matchers where a project may configure four, so a correctly protected
  instance could be reported unprotected and an under-protected one clean. It now reads
  every entry that runs the scope hook and takes the union.

## 2.1.1

**Edition v1.9 (the reckoning edition), unchanged.** A documentation release. No
command, hook, or gate behaviour changes, and the framework document is not edited:
the only executable change is five new test assertions that pin an existing defect
so the release that fixes it cannot ship with stale documentation.

- **Known limitations is now three lists instead of one.** The section carried 29
  bullets as a single undifferentiated wall, so sixteen deliberate design decisions
  read as defects while the genuinely open holes were buried among them. It now
  splits into **design boundaries** (decisions, each with its date and reason),
  **open limitations** (real defects and gaps, each carrying a status line naming
  what closes it), and **upstream conditions** (things this project does not
  control, each naming what would lift it and the check that re-measures it). An
  orientation paragraph carries the count per class. Every pre-existing bullet was
  MOVED, not rewritten: no claim, measurement or workaround changed.
- **Four limitations that were true but undocumented are now listed.** Three are
  routes the session gates do not read and the push-time trunk audit refuses:
  `git rebase` onto a spec branch, `git reset --hard` onto one, and the pathspec
  form of `git checkout`. Each was re-measured for this release with controls in
  both directions: all three put role-path code on the local trunk and all three
  are refused at push, remote untouched. The fourth discloses a false denial that
  is still present: a spec that QUOTES the closing-report template inside a fence
  is refused an ordinary commit, because the detector reads the raw staged diff and
  does not strip fenced blocks. That bullet names the workaround that actually
  works and, explicitly, the plausible one that does not.
- **The list shrinks by fixing, never by editing.** No bullet was deleted or
  softened in this release, and that is now the stated policy for the section. The
  fenced-template bullet above is scheduled to be deleted by the commit that fixes
  the defect, which is the intended shape.
- **An honest positioning note** in the Claude Code-native bullet: the enforcement
  guarantee itself is harness-agnostic, because it lives in git hooks that git runs
  from its own state and travels with the repository. What is Claude Code-specific
  is the ceremony that installs and tailors it, plus the advisory session layer.
- Housekeeping: the opening paragraph of Known limitations no longer restates a
  finding it now links to, and no longer ends by pointing at the section it is
  already inside.

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
