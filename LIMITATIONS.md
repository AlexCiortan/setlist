# Known limitations, in full

This is the full text of every limitation the README lists in short form: the same
titles, the same three classes with the same counts, ordered here by who hits each one
first. Each entry states its claim, then what to do, then folds the history and the
measurements behind it. Nothing was cut when the README's section became short; it was
folded. The titles are the keys the test suite's hole ledger and the maintainer's release
gates read, so a title here is a hole the suite asserts or names as unassertable.

**The guarantee does not live in your Claude Code session.** It used to be four hooks running inside your Claude Code session, deciding what a command would do by reading the command's text. That layer is still there and still useful, and as of 2026-08-04 it is advisory **in mechanism as well as in name**: it warns and permits, and it no longer holds a veto over your session. Each session gate reports what it would have decided, why, and the code, and then lets the command run (under a sed that is broken the JSON `code` field arrives empty because sed extracts it, while the reason text still carries the bracketed code; recorded by the 2.5.0 review and filed, a machine reader's loss only). The git hooks below are what refuse the work. This wording used to describe a warning while the gates actually denied, and the gap cost a release cycle: successive rounds of adversarial review found that most new defects sat in parser code written that same day to fix the previous round's findings, and while the parsers could deny, every one of those defects was release-blocking. **The trade is explicit, and one half of it did not survive contact with the harness.** A false positive is now noise instead of a blocked command. But **on current Claude Code versions the advisory reason is not shown to the model when the decision is `allow`**, and an advisory verdict is always `allow`, so in practice the session gates do not warn the agent today: the in-session feedback you actually get is the **git hooks' refusal messages**, arriving as ordinary command output at the moment of the attempt, which is where the guarantee lives anyway. That one is under Upstream conditions below, with its measurement, the control that makes it a harness finding rather than a wiring one, and the probe that lifts it. The guarantee moved to **git hooks**, stamped into a tracked `.githooks/` directory, which git runs itself after it has already parsed the arguments and resolved the refs. For cooperating use there is nothing left to spell around at that point: a merge is a merge however it was written. That is a claim about the SHELL, which it survives, and not about a committer crafting merge topology to evade the audit, which it does not. **Within the git-hook layer, the guarantee is the push-time trunk audit specifically.** The two per-merge hooks keep refusing at commit and merge time, and that early refusal is the feedback you feel day to day; the audit at `pre-push` is what stands between unreviewed work and a shared trunk, and it decides by identity and ancestry (does this history descend from the commit that adopted the rules; did this content arrive through a closed spec's lineage) rather than by recognising the shape of any operation. A route past a per-merge hook is therefore a MAJOR in this project's severity model, not a release blocker: the work is refused later than intended, at push, rather than not at all.

Why the change: across five releases, every hardening pass closed one spelling and the next release found another, because a shell command can compute its own arguments and the set of spellings has no end. Then the parser layer died on macOS for a reason that had nothing to do with command text, silently allowing everything, while a git hook on the same machine in the same run was untouched. A parser has failure modes its subject matter does not.

Both halves of the boundary are worth stating plainly, because an enforcement layer whose edges you cannot see is one you cannot reason about.

The list below is not one kind of thing, which is why it arrives in three groups rather than as one wall. **Design boundaries** are decisions with a date and a reason, where the layer deliberately stops. **Open limitations** are real defects or gaps with a fix scheduled, a candidate, or a named gate, each carrying its status. **Upstream conditions** are things this project does not control, with what would lift them and how that is re-checked every release. A design boundary read as a defect overstates the problem; a defect read as a decision understates it. **The counts live on the group headings below and nowhere else**, so there is exactly one place for them to be wrong and it is the place that moves when a bullet does.

### Design boundaries (38)

These are boundaries, not bugs. Setlist governs the session; it is not a server-side policy engine and does not try to be one. Each one is a decision, and each says when it was taken and why.

#### Week one, one developer

<a id="per-clone-hooks"></a>
- **Git hooks are per-clone, and the tracked directory narrows that without closing it.** `.git/hooks` is not cloned, which is exactly why the hooks are stamped into a tracked `.githooks/` instead: they are versioned, reviewed in diffs, and present in every clone.
  **What to do:** Run `/setlist:upgrade` (or `scripts/refresh-instance.sh --apply .`) in every clone; for a team, require the forge check on the trunk.

<details><summary>The history and the measurements</summary>

What is still per-clone is the CONFIG pointing at them, since `.git/config` is not cloned either, so a fresh clone is unprotected until it is set up. The same applies to `merge.ff=false`, which Setlist sets because a fast-forward merge fires no git hook at all. Expect merges that used to fast-forward to create merge commits; that is the setting doing its job. For a team, the stamped forge check (2.6.0) is the layer that does not live in a clone: required on the trunk, it verifies every pull request against the same predicates whether or not the committer's clone had its hooks armed. It is a boundary only where it is required, and the check says so when it is not.

</details>

<a id="no-verify"></a>
- **`--no-verify` skips git hooks**, and `git push --no-verify` skips the pre-push audit.
  **What to do:** Treat `--no-verify` as the escape it is, and put the forge check on the trunk if the trunk must hold against it.

<details><summary>The history and the measurements</summary>

This is a real hole and a different kind of hole from the others: a deliberate act with an obvious name, not an apostrophe in a commit message. Setlist's own escape hatch, `SETLIST_SKIP_HOOKS=1`, is the same thing said out loud. Since 2.6.0 the refusal text no longer names the escape; the escape is documented here and in the hooks' own headers, and the forge check has no escape variable at all: a workflow edit is a reviewed change under the stamped CODEOWNERS.

</details>

<a id="hookspath-conflict"></a>
- **git allows one `core.hooksPath`, so Setlist cannot coexist with husky, lefthook or pre-commit, and `refresh-instance.sh --apply` now REFUSES rather than displace one silently.** Until 2026-08-08 it overwrote the setting unconditionally with no warning and no backup, and report mode said "git config still to set: core.hooksPath" while it was already set to something else that was about to be switched off.
  **What to do:** Move the other layer's checks into `.githooks/`, or re-run with `SETLIST_ADOPT_HOOKSPATH=1` to displace it on purpose. When the other layer ALREADY lives in `.githooks/` the first remedy has nothing to move, and the answer is the second one or merging the two layers' scripts by hand.

<details><summary>The history and the measurements</summary>

Measured: the identical `git commit` was refused by `.husky/pre-commit` before the refresh and committed cleanly after it. What gets displaced is often itself a control, since gitleaks, detect-secrets and commit-msg validation are commonly wired exactly this way. Report mode now names the value it would displace and what stops running; `--apply` refuses and tells you the two ways forward, which are to move those checks into `.githooks/` or to re-run with `SETLIST_ADOPT_HOOKSPATH=1` and displace the other layer on purpose. This is a limitation of git rather than of Setlist: the two layers genuinely cannot both run, and the only thing that was ever fixable is whether you find out.

</details>

<a id="squash-flag"></a>
- **`git merge --squash` needs one flag to work in a Setlist instance, and the error does not say so.** `merge.ff=false` implies `--no-ff`, and git refuses `--squash` in combination with it: `fatal: options '--squash' and '--no-ff.' cannot be used together`, on every squash merge, whether or not the branch could have fast-forwarded.
  **What to do:** Use `git -c merge.ff=true merge --squash <branch>` for a one-off; `--no-ff` stays the recommended close.

<details><summary>The history and the measurements</summary>

The message names neither Setlist nor the setting, so there is nothing to search for. Use `git -c merge.ff=true merge --squash <branch>` for a one-off, or drop the setting for that command. A squash has no second parent, so the trunk audit can never see the branch the work came from; it reads the close conditions off the commit instead, so a COMPLIANT squash close is accepted at push. As with a fast-forward, what you lose is the merge-time close verification, and `--no-ff` stays the recommended close because it runs every layer. The setting stays because a plain fast-forward merge fires no git hook at all, and that hole is worth more than the convenience. **Fixed as of 2.4.0, jointly with the `--ff` bullet below, for a close that arrives as ONE commit, and a decided boundary for what remains (ruled 2026-09-02, when this bullet moved here from Open limitations): git's own error message names neither Setlist nor the setting, and the setting stays.** A compliant `--squash` close is accepted at push; the two layers agree there, and the one-off flag above remains the way to run a squash. (This bullet's Status read "fix scheduled for the next release cycle" for one release after the fix shipped, and was corrected 2026-09-02 by the release's own claims-vs-bytes review rather than by a reader.)

</details>

<a id="fast-forward"></a>
- **`git merge --ff-only` and `git merge --ff` skip the merge hooks.** A fast-forward creates no merge commit, so there is no `pre-merge-commit` for git to run, and an explicit `--ff-only` beats the `merge.ff=false` Setlist sets.
  **What to do:** Close with `--no-ff` (what `/setlist:checkpoint` does); if a GUI passes `--ff` for you, expect the audit at push to be the layer that speaks.

<details><summary>The history and the measurements</summary>

So does a bare `--ff`. Unlike `--no-verify` neither looks like a bypass, which is why they are called out here: they are normal preference flags and some GUI clients pass them for you. What this costs you is the merge-time close verification, which does not run: the commit-time checks and the push-time trunk audit both still do, and the audit reads the close conditions off the commit itself, so a COMPLIANT fast-forward close is accepted at push WHEN THE CLOSE ARRIVES AS ONE COMMIT: a fast-forward of a single-commit branch, or a `--squash`. A fast-forward of a MULTI-commit branch lands the branch's earlier commits on the trunk as ordinary single-parent commits the audit reads one by one, so the intermediate work commits are refused as feature code with no close (measured by the 2.4.0 review; the close exemption covers the closing commit, not a range). `--no-ff` remains the recommended way to close, and is what `/setlist:checkpoint` does, because it is the only route that runs every layer. The suite is separately not re-run by the audit. **Fixed as of 2.4.0 for a close that arrives as ONE commit, and a decided boundary for what remains (ruled 2026-09-02, when this bullet moved here from Open limitations): git fires no hook for a fast-forward, `merge.ff=false` is the stamped answer and `--no-ff` the recommended close, and a multi-commit fast-forward refusing at push on its intermediate commits is the audit doing its job.** A compliant `--squash` close, or a fast-forward of a single-commit branch, is no longer refused at push; the two layers agree there, and the audit decides on the parent COUNT so one rule covers both flag names. A multi-commit fast-forward still refuses on the branch's intermediate commits, as the bullet now states (recorded by the 2.4.0 review, which is also what corrected this bullet's Status from claiming the fix whole).

</details>

<a id="trunk-name"></a>
- **The trunk is recognised by the NAME recorded in `.claude/sdd.json`, so an instance that merges onto a differently-named branch is ungoverned.** Every git hook asks "is the checked-out branch the recorded trunk" by comparing names.
  **What to do:** Record in `.claude/sdd.json` the branch you actually merge onto; the upgrade skill prescribes exactly that.

<details><summary>The history and the measurements</summary>

On a git-flow shaped repository, where the team works on `trunk` or `develop` which tracks `origin/main` while a local `main` also exists as the release branch, a recorded trunk of `main` means every hook takes its fail-open exit while merges really do advance the branch the project treats as its trunk. Measured on the shipped bytes: unspecced role-path code lands on that branch with the whole guarantee layer silent. Between 2026-08-05 and 2026-08-07 the hooks also consulted what the branch TRACKS, which closed this shape and broke a much commoner one: `git checkout -b <name> origin/main` is git's own documented way to branch from a remote trunk, git announces it with "set up to track", and every such branch became the trunk to the hooks, so merging role-path code into an ordinary spec or feature branch was hard-refused with a message naming `main` as the target of a merge that never touched it. The two shapes are indistinguishable from inside a hook, so the tracking test was removed and this limitation is the honest statement of what is left. **The remedy is one line**: record in `.claude/sdd.json` the branch you actually merge onto. The upgrade skill prescribes exactly that.

</details>

#### Ordinary use

<a id="empty-remote"></a>
- **A first push to a brand-new EMPTY remote audits every pushed branch as a trunk candidate.** An empty remote has no default branch yet, and git hosts adopt the first pushed branch as the default, so `pre-push` cannot know which pushed ref is about to become the trunk and audits them all.
  **What to do:** Push the trunk first, alone; use `SETLIST_SKIP_TRUNK_AUDIT=1` only for a deliberate exception.

<details><summary>The history and the measurements</summary>

The clean trunk pushed on its own passes; a spec branch pushed first, or alongside the trunk, is audited as if it were the trunk and refused, because unclosed feature code must not become a remote's default by a raw push. Push the trunk first, or use `SETLIST_SKIP_TRUNK_AUDIT=1` for a deliberate exception. This is FAIL-CLOSED: it refuses more than you might expect, and it closed a fail-open that adversarial review found, where a differently-named branch pushed first to an empty remote was ALLOWED while the hook audited a local ref the push never touched.

</details>

<a id="review-ref-namespace"></a>
- **The push-time hooks read only the branch and tag namespaces, so a push to a review-ref namespace is ungoverned by them.** `pre-push` runs the content scan and the trunk audit over `refs/heads/*` and `refs/tags/*`; a push to any other namespace, of which Gerrit's `refs/for/<branch>` is the common one, matches neither and both checks are skipped.
  **What to do:** Push the trunk directly so the audit reads it, or require the stamped forge check on the trunk; since 2.7.0 the hook REPORTS the skip by name rather than passing in silence.

<details><summary>The history and the measurements</summary>

Found by the 2.7.0 adversarial review, which measured a live-shaped secret reaching the remote at exit 0 by this route. **What changed in 2.7.0 is the silence, not the scope:** `pre-push` now emits `SLH-REF-NOT-AUDITED` naming the ref and both ways through, and it refuses nothing, so no ordinary push is denied by it. **The scope was deliberately NOT widened**, and the reason is this project's own history rather than indifference: teaching the hook another forge's ref grammar means shipping a spelling nobody here can exercise end to end, and an unexercised spelling is the class that produced the two defences removed on 2026-08-07 for refusing ordinary work. Native support for review-ref workflows waits on a field report from someone who runs one, which is the same trigger the forge-check work carried. On such a workflow the forge check is the layer that holds, because it judges the merge a change request would make rather than the ref that carried it.

</details>

<a id="skip-hooks-escape"></a>
- **The `SETLIST_SKIP_HOOKS=1` escape skips EVERY git hook, `pre-push`'s trunk audit and content scan included.** Setlist's own escape hatch is read FIRST by every stamped git hook, `pre-push` included since 2.2.0, and at push it skips the trunk audit and the content scan both, saying so on stderr; `SETLIST_SKIP_TRUNK_AUDIT=1` is the narrow escape, skipping the audit alone while the content scan still runs.
  **What to do:** Reach for the narrow variable when you mean to skip the audit alone, and never carry the wide one in a shell profile.

<details><summary>The history and the measurements</summary>

**This bullet said the opposite from 2.1.0 through 2.4.1** ("not read by `pre-push`", so a refused push would not get through), which was true when it was written and false from the 2.2.0 hook onward, in the unsafe direction: a reader carrying the variable for a noisy commit hook was told it was inert at push and it was not. Corrected in 2.5.0 by that release's adversarial review, with the suite case behind it rewritten to pin the escape in its real direction (it had reported a pass either way). A deliberate act with an obvious name, like `--no-verify` above. Since 2.6.0 the refusal text no longer names the escape; the escape is documented here and in the hooks' own headers.

</details>

<a id="scan-scoping"></a>
- **The staged-content scans read every staged line unless you scope them.** By default the em-dash and secret scans do not know vendored third-party code, quoted external text, or test fixtures with dummy credentials from your own new writing, and **splitting the commit does not help, which this list said it did until 2026-08-04**: the scans read every added line of the index, so isolating the foreign content isolates it WITH the scanner rather than away from it.
  **What to do:** Declare repo-relative globs in `scan_exclusions`; every skip is printed with the glob that matched it.

<details><summary>The history and the measurements</summary>

Since 2.2.0 you scope them by declaring the paths, repo-relative globs, in `.claude/sdd.json`: `"scan_exclusions": ["vendor/**", "test/fixtures/**"]`, honoured by both scans at the commit layer and the push layer alike. **Every skip is printed, naming the file and the glob that matched it**, because an exclusion nobody is told about is a hole one directory over. The deliberate limits, which are the reason this is scoping and not an off switch: the set reaches the two content scans and nothing else, so it cannot quiet the trunk audit, the close checks or role-path judgment; a pattern made only of wildcards is refused, which stops the obvious off switch but is NOT the same as "no spelling reaches everything": the guard strips `*`, `?` and `/` and asks whether anything is left, so `*.*` leaves a dot, passes, and excludes every path with an extension. That was measured in 2.7.0 and the sentence here claimed the stronger property until then. Read the guard as refusing the bare catch-all, and read the exclusion set as a declaration you are responsible for; an unreadable set is refused with a named code rather than resolved in either direction; matching is case-exact and a path git had to quote is scanned and says so, because failing to exclude costs a refusal you can see while failing to scan costs a published secret. Declaring nothing leaves the scans exactly as they were. **One residue is deliberate:** the in-session advisory commit gate does not read exclusions, and since 2.3.0 its message says so, naming the git-hook layer as where they are evaluated, so a commit of excluded content still draws the advisory verdict inside a Claude Code session and commits cleanly through the hooks, and you can tell from the message which will happen. Do not edit third-party content to satisfy a style gate. **Built in 2.2.0 for the layer that carries the guarantee, and a decided boundary for the advisory half (ruled 2026-08-28; moved here from Open limitations 2026-09-02): the session gate is not path-scoped, the divergence is closed by honesty rather than by coupling, and the message that says so shipped in 2.3.0.** (This bullet's Status called the advisory half "the remaining piece" for two releases after that ruling; corrected 2026-09-02.)

</details>

<a id="own-index"></a>
- **The scans read this project's own index.** The commit gate looks at what is staged in the project it governs.
  **What to do:** Give a nested repository its own instance if it should be governed.

<details><summary>The history and the measurements</summary>

A commit aimed somewhere else is therefore not scanned: `git -C some/nested/repo commit ...` commits that repository's index, and `GIT_INDEX_FILE=...` names a different index outright. Your own staged content is still checked, every time. Following the target index instead would mean re-deriving which repository each command line means, in every spelling, which is the kind of parser-chasing that has produced more holes here than it has closed. A nested repository is a different project, and if it should be governed it should have its own instance.

</details>

<a id="scan-best-effort"></a>
- **Secret and style scanning is best-effort early warning, not a guarantee.** Treat any secret that reached a commit as COMPROMISED and rotate it, whatever these hooks reported.
  **What to do:** Treat any secret that reached a commit as COMPROMISED and rotate it, whatever the hooks reported; send pattern misses as field reports.

<details><summary>The history and the measurements</summary>

This limitation is written at this strength because the claim above it was narrowed three times and falsified three times under the 1.1.0 adversarial review (2026-08-06), and the mechanism is what decides which sentence is true. **Two structural holes remain, and they are structural rather than a matter of pattern coverage.** The scanner reads the output of `git diff`, which is a RENDERING the repository controls: a `.gitattributes` entry marking a path `-diff` or `binary` makes git emit no added lines at all, and a live-shaped secret then reaches a remote at exit 0 by the ORDINARY commit-and-push path (measured under adversarial review); and the repository's own diff CONFIGURATION shapes the same rendering, which is the structural class the `.gitattributes` case belongs to: colour forced into a pipe, an external or textconv driver, a driver whose hunk-header regex does not compile, the setting that renders a root commit as nothing, each found by measurement and each closed as of 2.4.1 by flags that ignore configuration and by reading git's own exit status, while the class itself stays open because a rendering has no last setting. And the pattern set is a first cut rather than a complete secret detector: it matches token-shaped and connection-string-shaped values, so it will miss exotic formats and can flag something innocent; tuning comes from field reports, so send them, and there is no scheduled cycle for it because the tuning that would help is the tuning real misses tell us about (that sentence was a bullet of its own until 2026-09-02, merged here because the list said it twice). Separately and not a hole in the scan: git fires no hook for `cherry-pick`, for `rebase`'s intermediate commits, or for the apply step of `git am`, so those are read at push rather than at commit. What the scan is good for is catching an accident early on the ordinary path. It is not a control you can put between a secret and a remote. **The four holes once scheduled here were FIXED in 2.2.0** (the endpoint diff became a per-commit walk of the pushed range, the first-push range derives against the remote's own refs instead of coming out empty, a tag push is scanned for what it publishes, and the `+++` header strip is anchored to the header), **and what remains is structural and stays by decision (2.2.0, restated 2026-09-02 when this bullet moved here from Open limitations)**: the rendering, which a `.gitattributes` entry can suppress and configuration can reshape, and the pattern set; the hookless routes named above are git's and not the scan's. The sentence at the head of this bullet is the one to trust either way.

</details>

<a id="pathspec-hole"></a>
- **The pathspec hole.** `git commit <file>` commits the working-tree copy of that file without staging it, so the staged-content scan has nothing to look at.
  **What to do:** Stage first (`git add`), then commit.

<details><summary>The history and the measurements</summary>

The test suite asserts this hole deliberately rather than hiding it, so the day it closes, we find out.

</details>

<a id="checkout-switch"></a>
- **A checkout is an enforcement switch: every git hook is inert on a branch without `.claude/sdd.json`.** Each hook opens by checking that the CHECKED-OUT branch carries that file and exits silently when it does not.
  **What to do:** Keep `.claude/sdd.json` on every branch that carries governed work, and require the forge check where that matters.

<details><summary>The history and the measurements</summary>

That guard is deliberate and load-bearing, because a `core.hooksPath` set in one repository must not govern unrelated work. The consequence is that the guard is also a switch: measured on the shipped bytes, a push of an unclosed merge is refused from the trunk and the IDENTICAL push of the IDENTICAL commits succeeds after checking out an orphan or legacy branch that has no `sdd.json`, and the work reaches the remote trunk (measured under adversarial review). If your repository carries branches without the file, the enforcement boundary is conditional on which branch happens to be checked out. This is documented rather than closed: narrowing the claim was the recorded decision once repeated repair rounds kept introducing new defects, and a fix here would have to distinguish "not a Setlist project" from "a Setlist project standing on an unstamped branch", which the file alone cannot do. The forge check closes this at the one layer where a branch is read rather than checked out: a pull request whose head carries no `.claude/sdd.json` is refused, not waved through.

</details>

<a id="platform-list"></a>
- **The set of tested platforms is a list, not a proof.** The suite runs on Linux under two different awks (the distribution's own, and GNU awk), and on macOS under bash 3.2 with the BWK awk, which is where the platform fault that prompted all of this would have been caught.
  **What to do:** Read the release notes' platform list as the claim; send a field report from anything not on it.

<details><summary>The history and the measurements</summary>

The awk axis is on the list because it is the axis that has actually broken this project, and the third awk was added by extending the list rather than by reasoning about it. A platform not on that list is untested, Windows has never been run at all, and the release notes say which list rather than implying the proof. **A decided boundary rather than an open defect (ratified 2026-08-26; moved here 2026-09-02): the list is extended and never restated as a proof, because no number of platforms makes it one.** The first extension landed 2026-09-02, in the shape the list describes: the Linux leg runs the suite a second time under GNU awk, so the list is Linux under two awks and macOS under the BWK awk, and the release's own CI is what backs it. The next extension is Windows, on a field-report trigger. Read the list as the claim: it is a list, not a proof about platforms.

</details>

#### Diagrams as claims (2.7.0)

<a id="diagram-checks"></a>
- **A diagram check compares a claim to a diff and a lockfile to a command's output; it does not judge whether a drawing is true of the code.** The field checks establish that the files the closer named are the files the commit touched, the node check that every drawn path exists in the tree, and the lockfile that the generated view equals what the declared command prints.
  **What to do:** Review a diagram the way you review a Closing report, and run the baseline chore under your own eyes.

<details><summary>The history and the measurements</summary>

That a box, an arrow or a label is TRUE of the mechanism is what review establishes, and `chore/diagram-baseline`'s file-by-file human review is the first instance of it: the one legitimate scan in the framework is the one a person signs. Three verdicts, by whose node it is: a stale node the CLOSING spec drew refuses (`SLH-DIAGRAM-STALE-NODE`), an earlier spec's stale node is REPORTED with two honest exits and refuses nothing, and a name that is not path-shaped is printed rather than checked (the bullet below). The twelve-node bound is reported at validate and refuses nothing, as are validate's other three diagram reports. The whole half is OPT-IN, and **there are TWO ways to opt in, which is a correction this bullet owes you**: a file under `docs/diagrams/` carrying the four-line header, or a `diagram_command` declared in `.claude/sdd.json`. A project with neither behaves exactly as it did before 2.7.0, which a differential fixture proves rather than assumes. A project that declares `diagram_command` is armed by that declaration ALONE, with no `docs/diagrams/` in the tree at all, because the lockfile arm is the half it opted into. **What arms the checks is what the diagram half itself writes, not the directory**, and that is a correction this release made to itself: until the second 2.7.0 leg the switch was the mere existence of any file under `docs/diagrams/`, a `.png` included, so an upgrade armed the checks for any project that already kept diagrams at that conventional path and started refusing closes it had passed the week before. The switch is now a file under `docs/diagrams/` carrying a `Synced by:` header line, which `chore/diagram-baseline` writes on an upgrade and `/setlist:new` writes on a new project, OR a declared `diagram_command`, because a project whose only diagram surface is a generated view carries no header anywhere and the generated file is the command output rather than a drawing anyone signed. **The residue is worth knowing and is not reported anywhere:** a `docs/diagrams/` tree whose files carry no header does not arm the checks and nothing tells you so, which is the quiet direction rather than the refusing one. If you have drawn diagrams there by hand and want them gate-checked, add the header (cut `chore/diagram-baseline`, or write the four lines) and the checks come on. One consequence of arming them is worth knowing before you do: on an armed instance the OLD field form (`updated in this commit`, naming no files) is refused as a claim that names nothing, because a claim nobody can check is the thing this release exists to remove.

</details>

<a id="path-shaped-names"></a>
- **A drawn name is verified only when it is path-shaped, and everything else is reported rather than checked.** A name counts as a path when it contains a slash and no whitespace, so `api["src/api"]` is resolved against the tree and `api["The API"]` is not.
  **What to do:** Write the path in the node's own label, not only in the node id; read the printed skip list, because a label you meant as a path and spelled as prose is on it.

<details><summary>The history and the measurements</summary>

Every unverified name is PRINTED with what it is, a node, a subgraph id or a subgraph title (`SLH-DIAGRAM-NODE-SKIPPED`, up to ten listed with a count beyond that), so the boundary is visible at every close rather than discovered later. What the print cannot do is turn a prose label into a claim: a module identifier with dots and no slash, and a subgraph that draws a process or a trust boundary rather than a directory, have no path to resolve and are checked by nobody. Three Mermaid spellings are not read at all, and they are named here and in the `diagrams` skill so a drawer is told rather than believed: the rhombus and hexagon (`{...}`), the asymmetric (`>...]`), and a label separated from its id by a space (`a ["src/a"]`). The last of those is the price of a strict adjacency test, which was measured and kept because the alternative re-opens the false-refusal direction in the open limitation below.

</details>

<a id="render-check"></a>
- **The render check runs where a renderer runs, and the stamped workflow fails its job rather than passing without one.** Inside `setlist-forge-check.yml` the parser step succeeds or fails the job; the stamped script run anywhere else reports that it could not parse and refuses nothing on that ground; local git hooks never render.
  **What to do:** Require the check on the trunk; on a forge that is not GitHub, put a Mermaid parser on the runner's PATH.

<details><summary>The history and the measurements</summary>

A Mermaid block that does not parse is caught at the forge or on the rendered page, never at the commit, because a git hook that needs a toolchain fails for reasons unrelated to the work on a machine whose node nobody chose. The price is a network fetch inside a required check, and it is smaller than this bullet first said it would be: the pinned tool exposes a parse-only entry point, so the step installs `mermaid@11.14.0` and `jsdom` and nothing else. Measured on one host, both paths: parse-only 1.8s and 143MB, a full render 30s and 484MB of packages plus a 493MB browser download, with the two verdicts agreeing on every case of a twelve-case corpus in both directions. So the browser download is not paid. The claim the check makes is that the block PARSES under the pinned version, not that a picture was produced. `FC-DIAGRAM-NO-RENDERER` is a report and is reachable only OUTSIDE the stamped workflow, which is what keeps "never a pass on absence" true where the check is required; the step also verifies its own parser in both directions before the check runs, because a parser that accepts a broken block would turn every diagram into a claim nobody checked while reporting that it did.

</details>

#### The session layer: advisory, and its parsers frozen

<a id="hard-deny-expansion"></a>
- **The session layer's one hard deny is defeated by ordinary variable expansion, so read it as a nudge and never as a boundary.** The commit gate carries a single hard refusal, `CM-BYPASS-SPELLED`, which exists to stop a command that would disarm the git hooks; `git commit -m ${MSG} --no-verify` is allowed in silence, because an unquoted expansion before the flag defeats the lexer that looks for it.
  **What to do:** Treat the deny as a nudge that catches the obvious spelling, and put the boundary where it holds: the git hooks, and the forge check on a trunk that requires it.

<details><summary>The history and the measurements</summary>

This bullet is written at this strength because the alternative is worse than the hole. The gate's other verdicts have been advisory in mechanism since 2026-08-04; this one deny is the exception, and it is the one a reader is most likely to mistake for a boundary. **What defeats it is not exotic.** `-m ${MSG}` is how a shell script writes a commit message, so a developer meets this while doing nothing unusual, which is why the sentence above does not say "crafted spellings evade it". Crafted spellings evade it too, and they are the same hole rather than a second one: ANSI-C quoting (`git commit $'--no-verify'`), a global option that takes a separate value and shifts where the subcommand is found (`git --attr-source HEAD commit -n`), and `--config-env=core.hooksPath=VAR`, which moves the hooks path without tripping `CM-HOOKSPATH-MOVED`. All four were measured against the shipped bytes by the 2.7.0 adversarial review, each with a replay. **They are not repaired, and the reason is the parser freeze of 2026-08-04**, recorded in the bullet above: the guarantee moved to the git hooks, each parser repair here has historically introduced its own defect, and widening a lexer to chase four spellings is the coverage chase this project has twice removed checks over. The git hooks are unaffected by every one of them: what is lost is an early refusal in the session, not the boundary at the trunk.

</details>

<a id="parser-spellings"></a>
- **The session gates are text parsers, and a growing list of spellings read a command wrongly.** They are advisory, so MOST of these are a warning that is absent or misleading rather than a command wrongly blocked, and for most of them the git hooks judge the same operation correctly afterwards.
  **What to do:** Read the session gates as warnings and the git hooks' refusals as the answer; the spellings are listed in the folded block, with the two that are more than a missing warning named first.

<details><summary>The history and the measurements, and the two spellings with bullets of their own</summary>

**Two of them are not merely absent warnings**, and the sentence used to claim all of them were: the diagram-field item below is shared by both layers so no later layer corrects it, and the `<<\EOF` heredoc item runs your gate command before an ordinary commit, which is neither a warning nor absent. A `git checkout` run in a DIFFERENT repository (`cd vendor/lib && git checkout x && cd - && git merge ...`) is credited to this project, so the close warning does not appear. The architecture-diagram field is read from the whole spec rather than from the Closing report section, so a mention of the label ELSEWHERE in the spec can decide it in either direction (the readers take the FIRST matching line, ruled first-line-wins in 2.3.0). And the commit gate assumes textual order is execution order, so a loop body that commits before it stages gets no warning. These are FROZEN by decision: the parsers and their corpus are closed to new spellings as of 2026-08-04, because the guarantee moved to the git hooks, chasing spellings is what the measurement above priced, and each parser repair has historically introduced its own defect. Adversarial review also recorded, and this release does not fix: a trailing shell COMMENT read as commit flags, text inside a comment judged as live commands when the comment contains a separator, ANSI-C quoting of the subcommand (`$'merge'`) read as nothing to govern, an attached `-m` message (`git commit -mfix`) read as option letters, a git ALIAS as an unhandled spelling, a fenced quotation of the spec template refused by the commit gate, a `&` immediately followed by punctuation (`git commit -m x & (git add -A)`) losing its concurrency marker so the stage-and-commit warning is absent for that spelling (2.4.0 review), and a QUOTED merge operand whose branch name carries any byte outside the ASCII keep-class collapsing to an inert token, so the same compliant close allows unquoted and is refused quoted (2.4.0 review), and a checkout believed on `&&` staying believed across a later `;` or `||`, so `git checkout X && cmd ; git merge Y` draws no unresolved-switch warning although the merge is not under the `&&` (2.4.1 review; the git hooks refuse the merge). The 2.7.0 leg added one in the refusing direction: bash's `&>`, `&>>` and `|&` are split as command separators, so a healthy `git checkout X &>/dev/null && git merge Y` draws a spurious `CG-UNRESOLVED-SWITCH` that the `>/dev/null 2>&1` spelling of the identical command does not. The 2.5.0 review recorded six more, and this release does not fix them either: the `function NAME { git commit ...; }` spelling silencing the commit gate, whose wrapper-stripping is three passes short of the close gate's (the git hooks refused the secret staged behind it); an EMPTY quoted message, `git commit -m "" -a`, making `-m` swallow the next flag so the auto-staging warning is absent (the git-hook scans read the index and refused); a backgrounded commit's `&` carried one segment and not beyond, so `git commit -m x & cmd ; git add -A` is judged as if the commit had finished (the separated sibling of the adjacent-punctuation member above); a multi-operand merge in which an operand the close gate cannot resolve is dropped unless its name looks spec-shaped, so a resolvable sibling vouches for it (the git hooks judge the merge that runs); and two in the refusing direction, git's own unambiguous abbreviations `git merge --abo` and `--cont` missing the merge-resumption exemption and being refused with a remedy that names no branch, and a sync merge whose branch name carries a byte outside `[A-Za-z0-9._/-]` (an accented letter, a `+`) refused before git is asked. Each is a warning arriving late, not at all, or wrongly. With the exception of the diagram-field item, none of them lets work reach the trunk, which is what the git hooks decide; that one does, because the same first-match reading is in the hooks and the audit alike, as described earlier in this bullet.

<a id="heredoc-backslash"></a>
- **A `<<\EOF` heredoc body is read as code by the session gates.** The four other heredoc spellings (`<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`) are read correctly; only the backslash form is missed, because the delimiter reader requires a letter or underscore at that position and gives up on the backslash.
  **What to do:** Use any other heredoc spelling, or `git commit -m`.

<details><summary>The history and the measurements</summary>

Measured on the shipped bytes, with controls: `git commit -F - <<\EOF` whose message body mentions a merge is judged as a real trunk merge and draws the close gate's verdict for that spec on a commit that merges nothing. The quoted spelling and a plain `git commit -m` do not; a real merge does, which is the control. Through plugin 2.5.0 the misreading also EXECUTED the project's gate command synchronously inside the PreToolUse hook under the template's `timeout 1800`, so an ordinary commit could hang for the length of a test run; 2.6.0 removed that run from the close gate (the git hook runs the gate command once, at the merge, where its verdict is acted on) and the entry's timeout fell to 300, so what remains of this hole is a misleading advisory, never a hang. The parsers are FROZEN, and the owner's decision on 2026-08-08 was to hold that freeze and document this rather than widen the character class, because parser repairs have historically introduced their own defects. Workaround: use any other heredoc spelling, or `git commit -m`. The git hooks are unaffected, and nothing here lets work reach the trunk.

</details>

<a id="case-spelling"></a>
- **A role directory spelled in a different case is not seen by the session scope gate on macOS or Windows.** With `roles.src` recorded as `src`, a write to `SRC/a.txt` is the same file on a case-insensitive filesystem but does not match the role path, so the gate stays silent where `src/a.txt` is refused.
  **What to do:** Spell role paths as recorded; the audit at push is the layer that holds.

<details><summary>The history and the measurements</summary>

The trunk audit catches it: git stores the path under its on-disk spelling, so the commit is reported as feature code on the trunk and `pre-push` refuses it. Advisory layer misses, guarantee layer holds, which is the layering this release claims. **The same layering holds for a symlinked LEAF (2.4.1 review):** the scope gate resolves the directory of a written path and re-attaches the final name literally, so a write through a symlink whose target is a role-path file draws no advisory, while a symlinked role DIRECTORY is refused; the trunk audit refuses the resulting commit at push, measured.

</details>

</details>

<a id="alias-identity"></a>
- **Identity-by-commit governs an alias only while a spec or chore ref still points at that exact commit.** The 1.0.8 delisting of the rename smuggle holds for the case it was built for, and the 2.4.0 review measured its boundary: an alias cut at a spec branch's tip stops being governed by the session gate once the spec branch advances past that commit, or once the spec branch is deleted, because `for-each-ref --points-at` then finds no governed ref and the merge classifies as an ungoverned sync, silently.
  **What to do:** Merge the spec branch by its own name; nothing reaches the trunk by the alias route.

<details><summary>The history and the measurements</summary>

Both guarantee layers were verified by execution to refuse the same merge (the pre-merge hook with `SLH-CLOSES-NO-SPEC`, the trunk audit with a violation at exit 1), so no work reaches the trunk by this route; what is lost is the session-layer warning, and what was wrong was this README claiming the alias case whole. The suite pins both spellings so the delisting cannot silently return. **A decided boundary rather than an open defect, moved to this group 2026-09-02**: the residue is the session-layer warning, accepted under the 2026-08-04 parser freeze, and the guarantee layers carry it.

</details>

<a id="wiring-spellings"></a>
- **The wiring check recognises only the command spellings `settings.json.tmpl` ships.** `refresh-instance.sh` certifies a stamped gate as wired by matching the hook entry's command against an enumerated set, because a shape test cannot express "the file I stamped".
  **What to do:** Restore the template's spelling, which the message prints; file the spelling you need if it is a real one.

<details><summary>The history and the measurements</summary>

The 2.4.0 review measured the consequence: an entry rewritten to `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/close-gate.sh`, which genuinely runs the stamped file, is reported `NOT WIRED` and `--apply` exits 3 telling you to restore a wiring already in force. It over-reports on hand-edited spellings, and the message names the exact template spelling that clears it. **It does not only fail in the safe direction, and this bullet said it did until 2.7.0:** the predicate matches the command's FIRST WORD, so a spelling that begins with the template's command and then redirects or wraps it, `... close-gate.sh >/dev/null` being the measured case, is certified as wired while the hook's verdict is thrown away. The check is a wiring inventory, not a proof that the wired thing still speaks. It is one predicate with five residuals and it is deliberately not repaired piecemeal, because separate repairs to one predicate are how the second reintroduces the first. The suite pins the restriction so widening the set is a visible decision. **A decided restriction rather than an open defect, moved to this group 2026-09-02**: it is the fifth residual of one predicate and is deliberately not repaired alone, because separate repairs to one predicate are how the second reintroduces the first. Add the template spelling back, or file the spelling you need. The matcher has the same restriction as the command (2.4.1 review): a comma-joined matcher such as `Write,Edit,MultiEdit,NotebookEdit`, which the harness accepts, is reported `NOT WIRED` by the wiring predicate while the sibling coverage predicate accepts it; it fails in the same safe direction and the printed remedy, the pipe spelling the template ships, clears it in one edit.

</details>

#### Teams: the forge, ownership and custody

<a id="forge-check-required"></a>
- **The forge check governs the merge button only where the trunk requires it.** The stamped check (2.6.0) runs the close verification, the attestation walk, the content scan, the third gate tier and the trunk audit against the merge a pull request would make, and refuses on any of them; the forge's merge button then enforces what the local gate would have.
  **What to do:** Require the check and one approving review on the trunk, disable rebase merging there, and require branches to be up to date before merging.

<details><summary>The history and the measurements</summary>

What it cannot do is require itself: a trunk that does not list it as a required check has a report, not a boundary, and under `forge` custody the check refuses for exactly that reason. It does not review merge diffs (the bullet below stands). A repository that merges by REBASE lands every branch commit on the trunk as direct feature code: the check reports the setting before the fact, no later run of the check sees the commit (each run audits only its own range), and an armed clone's `pre-push` refuses every push of that trunk from then on, so disable rebase merging on a trunk the check governs. And the check judges the merge against the base its checkout carries: the forge's own setting that requires a branch to be up to date before merging is what keeps that base current, and the check does not read it, so require it beside the check.

</details>

<a id="forge-protection-now"></a>
- **The forge check reads the trunk's protection as it stands, not as it stood.** Under `forge` custody the check verifies that the trunk requires a review and this check NOW and that the flip is on the trunk; a trunk protected after an unreviewed flip landed verifies that flip.
  **What to do:** Protect the trunk before the first custody flip lands; the forge's audit log holds the rest of that history.

<details><summary>The history and the measurements</summary>

The stamped CODEOWNERS makes the paths that matter reviewed changes; the forge's audit log is where the rest of that history lives, and the check does not read it.

</details>

<a id="codeowners-bridge"></a>
- **The CODEOWNERS bridge reads a subset of the file's grammar, and a pattern is a claim about paths.** The audit and the forge check evaluate `Owns:` declarations against the repository's CODEOWNERS file (the core grammar the forges share: patterns, `@login`, `@org/team`, emails, last match wins) and refuse a close that declares a file another owner's pattern claims.
  **What to do:** Write CODEOWNERS in the core grammar (patterns, `@login`, `@org/team`, emails) and let the forge resolve handles.

<details><summary>The history and the measurements</summary>

Sections, negations and character classes are refused by name rather than guessed at. Locally, only email owners can be matched; a handle or a team is resolved at the forge, and the audit reports rather than refuses when it cannot resolve one. Ownership here is what the file says, not what an organisation chart says.

</details>

<a id="custody-key"></a>
- **The headless integrity chain is only as strong as where your signing key lives, and a key your build can reach is not custody.** An attestation binds an approval to a spec's exact bytes and the git hooks refuse a build commit whose spec has drifted since that approval.
  **What to do:** Declare the custody you actually have; if a boundary against deliberate evasion is the need, it is the forge check required on your trunk.

<details><summary>The history and the measurements</summary>

It does not stop the unapproved build from HAPPENING: the only layer present when code is written is the session layer, and that layer has been advisory in mechanism since 2026-08-04. It stops the result becoming a commit, and at push, being shared. **A signature proves a key was used, not that a person decided.** If the signing key sits where the build process can read it, a headless run can sign its own approval and the chain will verify: what it then proves is that the run had the key, which is not the question. Setlist therefore makes you DECLARE your custody, and prints that declaration in every verification it emits, including the ones that pass, so the strength of the claim travels with the claim. Two things it does not close under `signer` custody, named rather than implied: **the allowed-signers file is read from the tree under review**, so a committer who can push a key enrolment and a signed attestation in one range verifies under that key (a forge that protects `.claude/` through the stamped CODEOWNERS makes the enrolment a reviewed change, which is the mitigation and not a fix); and **`--no-verify` and an unset `core.hooksPath` bypass this exactly as they bypass every other git hook.** Under `forge` custody (built in 2.6.0) there is no key: the approval is the ACTIVE flip landing on the protected trunk through a required review, verified by the stamped forge check, and what that establishes is that the forge's review happened, with the forge's account security as the custody. If you need a boundary that holds against deliberate evasion, it is that check, required on your trunk.

</details>

<a id="declarations-claim"></a>
- **The close audit's single-parent arm is as strong as your declarations, and a declaration is a claim, not a verified fact.** A spec declares the files it owns (`Owns:` lines in its header); a single-parent close is audited file by file against that declaration, so a close can no longer exempt a whole commit by flipping one status row.
  **What to do:** Declare ownership in every spec, put a custody behind the declaration, and read `/setlist:validate` when the page and the record disagree.

<details><summary>The history and the measurements</summary>

But the declaration travels in the same commit it justifies: whoever writes the close can write the declaration, and the hooks verify coverage, not truth. With a declared attestation custody the declaration sits inside the approved, signed spec bytes, so changing it costs a human re-approval; without one, it is an explicit line in your history that review and `/setlist:validate` can catch, and nothing more. **A spec that declares nothing closes under the pre-2.4.0 rules**, the whole-commit exemption included, so the audit is only as complete as your adoption; chores declare their files in the machine record (`chores.<id>.files`), which no attestation covers, so the chore route is the weaker one by exactly that much. And the machine record in `.claude/status.json` is what the hooks read: the human STATUS.md page is for people, and a hand-edit can make the page disagree with the record until `/setlist:validate` reports it.

</details>

<a id="hashed-range-cut"></a>
- **The hashed range ends at the FIRST line reading `## Closing report`, fences included, and the ownership reader agrees with that cut.** The range a spec's hash signs is cut by the first line matching the Closing-report heading read RAW, so a fenced or quoted copy of the spec template ABOVE your `Owns:` declarations ends the range early, and a declaration below that quote is refused as out-of-range even though it sits above your real Closing report.
  **What to do:** Keep declarations above any quoted `## Closing report` line, or drop the quoted heading.

<details><summary>The history and the measurements</summary>

This is a decided boundary, not an accident (2.4.0 review, ruled 2026-09-01): the ownership reader and the hash cut are kept byte-agreed, because a declaration the reader accepts but the signature does not cover would put the ownership set outside what a human approved, silently, exactly where this layout occurs. The refusal names the cause and the one-edit fix: move the declarations above the quote, or drop the quoted heading line. The suite pins the agreement, so a future fence-aware reader has to move the hash cut, the custody question and this bullet in one commit.

</details>

<a id="stop-hook"></a>
- **A session killed from outside fires no Stop, and the Stop hook is a nudge, never a lock.** The stamped Stop hook (2.6.0) refuses to end a turn that leaves a spec or `specs/STATUS.md` change unstaged, once per turn, and allows the continuation the harness marks, so a change the session cannot stage costs one refusal and never a hang.
  **What to do:** Stage the spec and the page before ending a turn; do not read the Stop hook as enforcement.

<details><summary>The history and the measurements</summary>

A session killed from outside, or one that never reaches its Stop event, fires nothing, and a change staged and never committed is not its question; the git hooks are what refuse the work. It is the one session hook whose reason the harness renders (the three gates' reasons are dropped on `allow`, Upstream conditions below).

</details>

#### Deliberate evasion

<a id="crafted-merges"></a>
- **Merges crafted to evade the trunk audit can succeed, and the list of known routes is maintained rather than complete.** The audit reads history and judges each merged parent; it does not attribute individual files to the spec that authorised a merge, because that is not decidable from history.
  **What to do:** Put branch protection and required checks on your forge if evasion by a committer is in your threat model.

<details><summary>The history and the measurements</summary>

Two routes are known and OPEN: a chained merge (unspecced code merged INTO a spec branch, then that branch merged with a compliant close), and the OCTOPUS spelling of the same trick, where parent order hides the unspecced parent behind a catch-up parent. Both were found by adversarial review rather than by use. Both were refused for a while, and the checks that refused them were removed on 2026-08-07, because neither could tell the crafted shape apart from ordinary work: the chained-merge check reported `git pull` on a shared trunk as a violation, naming as the offender the compliant close merge it had passed clean minutes before. That is the second developer on any team, on the commonest git command there is. A false denial on ordinary work costs more here than the bypass it prevents, so the route is documented instead of defended. The history is the point of this bullet: the second route was introduced by the fix for the first, and the fix for both broke everyday use. A cooperating developer does not construct these; someone determined to bypass the audit will find the next one before we do. Put branch protection and required checks on your forge if that matters to you.

</details>

<a id="sideways-routes"></a>
- **Sideways routes to the trunk.** The close gate reads the merge command; content can still reach the trunk through commands it does not parse: `git cherry-pick` of spec-branch commits, `git pull <remote> spec/...` (a fetch-and-merge the gate does not intercept), merges performed on a detached HEAD (no current branch, so the gate never sees a trunk target).
  **What to do:** Close specs through `/setlist:checkpoint`; read these routes as the audit's job, not the gate's.

<details><summary>The history and the measurements</summary>

Merging a spec branch under a second NAME used to be on this list and no longer is FOR THE COMMON CASE: as of 1.0.8 the gate resolves a merge argument to a COMMIT and asks git which refs point at it, so an alias, a tag, `heads/spec/...`, a remote-tracking ref and a raw object name all identify the same branch and are all governed WHILE a spec or chore ref still points at that exact commit; the boundary of that identity is its own bullet in Design boundaries above (2.4.0 review). These remaining routes are named rather than parsed because each is a deliberate spelling of "go around the gate", and a visible edge is more honest than a half-parser that would miss the next spelling. Each of them is caught by the trunk audit below FOR COOPERATING USE, which is why the two layers exist: the gates stop things as they happen and can be spelled around, and the audit reads history afterwards so it does not care how work arrived. It is not immune to being spelled around either: merge TOPOLOGY crafted to evade it (a chained merge, an octopus parent order) is a separate class, named in its own bullet above, and closing those routes has not been convergent.

</details>

The three routes below are the same family as the bullet above, split out because each is a command a person runs for ordinary reasons rather than a deliberate spelling of "go around the gate". All three were measured on the shipped bytes for this release, with controls in both directions: a compliant close pushes clean, and an unclosed merge on the trunk is refused. In each case the trunk audit at `pre-push` refuses and the remote is untouched, so what these cost you is the EARLY refusal, not the trunk. That is the two-layer design working as intended, and it is still worth knowing which commands take the slow path.

<a id="rebase-route"></a>
- **`git rebase` onto a spec branch brings that branch's commits to the trunk with no closing merge.** The close gate reads `git merge`; a rebase is not a merge, so the gate emits no verdict at all and nothing warns you at the moment you run it.
  **What to do:** Close with `--no-ff`; declare ownership so the audit reads file by file.

<details><summary>The history and the measurements</summary>

Measured: run on the trunk, it leaves the spec's role-path file on the trunk, and the next `git push` is refused with `VIOLATION ... feature code committed directly to main`, remote unchanged. The suite pins this as a documented hole, so the day it stops being one, the suite says so instead of the docs quietly going stale. Close a spec with `--no-ff` instead, which is what `/setlist:checkpoint` does. **One qualification, measured by adversarial review and corrected here:** that refusal holds for the bare form. Composed with a compliant single-parent spec close that declares no ownership, the audit's close exemption applies and the push SUCCEEDS; a close that DOES declare is audited file by file instead. See the single-parent declarations bullet above for the exemption and its limits.

</details>

<a id="reset-route"></a>
- **`git reset --hard <spec-branch>` moves the trunk onto unclosed work outright.** Same silence at the session layer, for the same reason: there is no merge for the close gate to read.
  **What to do:** Use `git reset --hard` on a trunk only to discard local commits, never to take a branch's work.

<details><summary>The history and the measurements</summary>

Measured: the trunk ends up at the spec branch's tip carrying its role-path file, and the push is refused with the same `VIOLATION`, remote unchanged. Reach for `git reset --hard` on a trunk only when you mean to discard local commits, never as a way to take a branch's work. **One qualification, measured by adversarial review and corrected here:** that refusal holds for the bare form. Composed with a compliant single-parent spec close that declares no ownership, the audit's close exemption applies and the push SUCCEEDS; a close that DOES declare is audited file by file instead. See the single-parent declarations bullet above for the exemption and its limits.

</details>

<a id="pathspec-checkout-route"></a>
- **`git checkout <spec-branch> -- <path>` copies role-path files onto the trunk without any merge to read.** The pathspec form of checkout writes files from another branch straight into your working tree, and the commit that follows is an ordinary commit: the close gate has no merge to judge, and the commit gate scans content rather than provenance, so it commits clean.
  **What to do:** Take a file from a spec branch through the spec that owns it.

<details><summary>The history and the measurements</summary>

Measured: the file lands on the trunk at exit 0 and the push is then refused with the same `VIOLATION`, remote unchanged. If you want one file from a spec branch, take it through the spec that owns it. **One qualification, measured by adversarial review and corrected here:** that refusal holds for the bare form. Composed with a compliant single-parent spec close that declares no ownership, the audit's close exemption applies and the push SUCCEEDS; a close that DOES declare is audited file by file instead. See the single-parent declarations bullet above for the exemption and its limits.

</details>

<a id="evil-merge-edit"></a>
- **The trunk audit cannot tell a merge that EDITS a file from ordinary conflict resolution.** It reports role-path files a merge commit introduced that no parent carries, which covers `git commit --amend` on a completed merge and evil merges that ADD content.
  **What to do:** Review merge diffs at the forge; the audit reads provenance, not content.

<details><summary>The history and the measurements</summary>

A merge that edits a file a parent already had is indistinguishable by content from a legitimate conflict resolution, so it is not flagged: doing so would refuse every real merge.

</details>

<a id="bash-escape"></a>
- **The Bash escape hatch.** The scope hook watches the file-writing tools (Write, Edit, MultiEdit, NotebookEdit), so a session that writes files through Bash instead (`cat >`, `sed -i`, a heredoc) does not trip it, and the commit gate checks what a commit contains rather than where the file lives.
  **What to do:** Read the deny list as a spelling list (`Read(.env)`, `Read(.env.*)`, `Bash(cat .env*)`) and the audit as the backstop.

<details><summary>The history and the measurements</summary>

The same boundary applies to git itself: the gates read the command they are given, so a git command run through another interpreter (`sh -c '...'`, a backtick, a script file) is not a command they can read. Wrapper prefixes that a person actually types (`command`, `env`, `nice`, `nohup`, `exec`, and leading `VAR=value` assignments) ARE handled, but that list is not a claim of completeness and cannot be one. The trunk audit below is the designed catch for this whole family: it reads what ended up in your history and does not care how the command was spelled. The stamped deny list is the same kind of thing and its template says so in a `_comment` key: `Read(.env)`, `Read(.env.*)` and, since 2.6.0, `Bash(cat .env*)` stop three spellings of reading a secret and nothing else.

</details>

### Open limitations (3)

These are defects and gaps rather than decisions. Each carries its status: the spec that closes it, the cycle it is scheduled to, or the gate it waits on. **This list shrinks by fixing, never by editing**: a bullet leaves it in the commit that closes its hole.

<a id="merge-completion"></a>
- **Completing a refused merge on the trunk side, as the hook's own message prescribes, is accepted at commit and refused at push.** When `pre-merge-commit` refuses a merge for a missing close record or chore archive line, its message says to add the line "in this same commit", and git says to complete the merge with `git commit`.
  **What to do:** Put the record on the branch being merged and merge again.

  **Status: fix scheduled for the next cycle that touches the audit's merge arm**, where both layers ask the same question of the merge commit itself; deferred under a dated bound because the fix is a mechanism change owing its own review, and the measurement that it is not a regression is published.

<details><summary>The history and the measurements</summary>

Doing exactly that writes the record on the trunk side of the merge: `pre-commit`'s merge-completion verification reads the merge INDEX and accepts, and the push-time trunk audit reads the merged PARENTS and refuses the same commit as a chore-shaped or close-shaped merge with no recorded completion. Nothing unsafe reaches the remote; the cost is a false denial at push on the route the refusal text itself names. Found by the 2.4.1 adversarial review, measured identical on 2.4.0. The way through today is to put the record on the branch being merged and merge again.

</details>

<a id="inline-edge-text"></a>
- **Mermaid's inline edge-text form can refuse a close for a path nobody drew.** A drawn name is read from a declaration's own label, the bracket or parenthesis attached directly to a node id; Mermaid's other edge-label spelling puts its text in exactly that position, so `a -- reads(src/gone.json) --> b` is read as a node called `src/gone.json` and, when that path does not exist, can refuse the close.
  **What to do:** Label edges with the pipe form, `-->|"reads src/gone.json"|`, which every type reference teaches and which has no such hazard. It is a one-edit fix on the line the refusal names.

  **Status: filed with its workaround, not fixed, because no regex separates the two forms.** `-- text --` and `-->` are the same dash run to a lexer that does not know whether the link closed, so a real parse of the line is what a fix would take. Its trigger is the next change of the node reader of any kind, or a field report.

<details><summary>The history and the measurements</summary>

This is the narrow remainder of a wider defect the same release found and fixed before shipping: the node extractor used to read ANY bracketed or parenthesised span, so an edge label between pipes could produce a phantom node too. That was a refusal firing on ordinary Mermaid at the layer that carries the guarantee, and it was fixed by anchoring the read to a declaration rather than to a span, in its own spec, before the edition turn. The pipe form, which every type reference here teaches and every diagram in this project uses, is clean. What survives is the one spelling that is textually indistinguishable from a declaration, and it is disclosed rather than half-covered with a pattern that would look like coverage. The same strictness that closed the wide case is why the space-separated label in the boundary above is unread: allowing whitespace between an id and its bracket re-opens this exact form, and the false-refusal direction is the one this project has twice removed checks over.

</details>

<a id="revision-suffix"></a>
- **The close gate refuses `@{u}` and other revision-suffix spellings of a merge operand.** `git merge origin/main` is allowed, because syncing the trunk from its own remote is not a close; `git merge @{u}`, `git merge @{upstream}` and `git merge main@{u}` name the same ref and are refused with `CG-UNNAMEABLE-REF`.
  **What to do:** Spell the ref out (`git merge origin/main`).

  **Status: gated on the parser freeze** recorded in the design boundaries above (2026-08-04). It is a session-layer inconvenience with a one-word workaround, and it lifts when that freeze lifts.

<details><summary>The history and the measurements</summary>

The gate refuses operands it cannot resolve to a literal branch name, and that rule is right for `@{-1}` and `FETCH_HEAD`, whose meaning changes between the moment the hook reads them and the moment git acts; it is merely conservative for `@{u}`, whose value is fixed configuration. Spell the ref out. This is a session-layer refusal only: the git hooks and the trunk audit are unaffected.

</details>

### Upstream conditions (2)

Neither decisions nor defects in this project: conditions in software it depends on. Each names what would lift it and the check that re-measures it per release, so it stops being true by measurement rather than by anyone remembering to look.

<a id="advisory-not-rendered"></a>
- **The session gates' warnings do not reach the agent on current harnesses.** The three PreToolUse gates compute their verdict and emit the reason on `permissionDecisionReason`, `systemMessage` and a machine-readable `setlistAdvisory` field, and Claude Code delivers none of them to the model when the decision is `allow`.
  **What to do:** Read the git hooks' refusal messages as the in-session feedback; the maintainer's per-release probe re-checks the harness and the bullet lifts by itself.

<details><summary>The history and the measurements</summary>

Measured on 2.1.221 with the discriminating control that makes it a harness finding rather than a wiring one: a hook returning `deny` has its reason delivered verbatim, so the hooks are dispatched and the reason is dropped. Consequence: the advisory layer is a machine-readable surface for tooling and CI, not an in-session teaching surface, and the feedback you actually see is the git hooks' refusal at commit or merge time. Filed upstream as a Claude Code bug (PreToolUse allow-path reasons dropped); the maintainer's per-release probe, run in the source repository at every release gate, re-checks it, and the limitation lifts by itself when the harness renders them.

</details>

<a id="hook-timeout"></a>
- **A timed-out hook is a skipped gate.** Claude Code cancels a hook that exceeds its timeout and lets the tool call proceed; that behavior belongs to the harness, not to the hook.
  **What to do:** Raise `timeout` in `.claude/settings.json` before the ceiling finds you, and fix PATH inside the gate command rather than in a profile.

<details><summary>The history and the measurements</summary>

The stamped settings therefore set explicit timeouts (300 seconds for each Bash gate since 2.6.0; through 2.5.0 the close gate carried 30 minutes because it re-ran your full suite inside the hook, a run 2.6.0 removed: the git hook runs the suite once, at the merge). If a hook outgrows its timeout, raise the `timeout` in `.claude/settings.json` rather than letting the ceiling find you. Relatedly, hooks run in a non-interactive shell: version managers wired into your interactive profile (nvm, pyenv, asdf) may be off PATH there, which shows up as a gate command that fails in the hook while passing in your terminal. That is a false deny, not a false pass; fix the PATH in the gate command itself.

</details>
