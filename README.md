# Setlist

[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757)](https://code.claude.com/docs/en/discover-plugins)
[![Plugin version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FAlexCiortan%2Fsetlist%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=plugin&color=blue)](https://github.com/AlexCiortan/setlist/blob/main/.claude-plugin/plugin.json)
[![License: CC BY 4.0](https://img.shields.io/badge/license-CC%20BY%204.0-lightgrey)](LICENSE)
[![tests](https://github.com/AlexCiortan/setlist/actions/workflows/test.yml/badge.svg)](https://github.com/AlexCiortan/setlist/actions/workflows/test.yml)

**Setlist** is spec-driven development for Claude Code: build real software by **directing rather than typing**. You act as architect and reviewer, the agent writes the code, and a spec (not the keyboard) is your control surface.

![A real /setlist:new session zero, recorded live at 2.5x: the interview's decision forks, the two-phase stamp, the framework's own health check, and /scaffold making the first commit with gates green](demo.gif)

Setlist ships as an installable Claude Code plugin (`setlist`): seven slash commands (`new`, `retrofit`, `upgrade`, `checkpoint`, `validate`, `gate`, `journal`), four reference skills, and seven mechanical hooks stamped into every project it generates: three git hooks (a push-time trunk audit that carries the enforcement guarantee, plus two per-merge hooks that refuse early), three advisory session gates, and session re-grounding. The current edition of the framework document is **[setlist.md](setlist.md)** (edition v1.10, the scoping edition; the version lives inside the file); you do not need to read it to start. The plugin version and the edition version are separate counters: the plugin counts releases of the tooling, the edition counts revisions of the document.

## Why Setlist

AI coding agents are powerful but drift: across a long project they lose context, wander from past decisions, and quietly expand scope. When you review instead of type, every ambiguity the agent resolves on its own ships unless you catch it later. Setlist's answer:

- **Specs are the contract.** Work proceeds one small spec at a time, each with exhaustive acceptance criteria.
- **Scope discipline is sacred.** An explicit, enforced out-of-scope list is the primary defense against ballooning.
- **Review is the gate, tests are the aid.** Your review is the quality bar; tests are written to be read as a specification of behavior.
- **Enforcement is a DISCIPLINE control for cooperating use, not a security boundary.** This is the sentence six rounds of adversarial review narrowed it to, and it is worth reading precisely. Setlist stamps git hooks into every project it generates, and git runs them from its own state after the shell is done. **For a developer or agent following the process**, that enforces closed-spec discipline: a merge bringing role-path code to the trunk is refused unless it closes a spec or records a chore, a spec whose row flips to CLOSED must carry a complete Closing report with a QA verdict and an answered diagram field, the project's gate command must pass, and the push-time trunk audit reads history for work that arrived by the ordinary routes no local hook witnessed. **It is not a control against someone who wants around it.** A committer who crafts merges specifically to evade the audit can: the routes found so far are named in Known limitations, that list is maintained rather than complete, and every attempt to enumerate them has so far produced a further route, including one introduced by the fix for the one before it. If you need a boundary that holds against deliberate evasion, it belongs on the forge, in branch protection and required checks, where it can be enforced somewhere the committer does not control. **When the hooks do not run, none of this applies**: they are inert unless `core.hooksPath` points at the tracked `.githooks/`, and every hook exits silently when the CHECKED-OUT branch has no `.claude/sdd.json`. Secret and style scanning is separate and weaker still: best-effort early warning, never a control. The rules that DO hold survive long sessions, context compaction and model swaps, because they do not live in the context window.
- **The repository is the memory.** Every durable decision lands in a version-controlled file: an ADR (architecture decision record) log with an index, a bounded status file, per-session journals, a living architecture diagram, whose field is gate-checked on the merges that CLOSE a spec (the checks iterate over the specs a change closes, so a chore merge carrying role-path code does not reach them; verified by adversarial review). Any session, on any model, re-grounds by reading the repo. Chats are disposable; the repo persists.
- **Role separation is a native mechanism.** A *Planner* (thinks, decides, writes specs) and a *Builder* (writes code, runs tests, does Git), never blurred: the two map directly onto Claude Code's `opusplan` model setting, and the boundary is held by the same stamped hooks, not by hoping the agent remembers which hat it wears.
- **Every release is dogfooded cold.** No edition publishes without passing a real end-to-end gate ("Does it actually work?", below). The run artifacts drive the next edition; the framework is maintained under its own discipline.
- **Claude Code-native depth over multi-tool breadth.** Setlist binds the harness's real capabilities (plan mode, hooks, skills, session-start injection, plugin distribution) instead of targeting a lowest common denominator. When the harness grows a mechanism that replaces discipline, the framework absorbs it; that is how the hooks and the re-grounding injection came to exist. That is a deliberate bet against the way this field is currently moving, so it is worth being precise about what it costs you: **the enforcement guarantee itself is harness-agnostic.** It lives in git hooks that git runs from its own state, so it holds under any agent, another vendor's, or none at all, and it travels with the repository rather than with the tool. What is Claude Code-specific is the ceremony that installs and tailors it, and the advisory session layer above it. Changing harness later costs you the ceremony and the advisories, not the part that refuses work.

## Quickstart

Requires Claude Code 2.1.193 or later (the marketplace rename migration and the `fallbackModel` chain both need it; the deny mechanic is verified on 2.1.200+). Install the plugin once, from inside Claude Code:

```
/plugin marketplace add AlexCiortan/setlist
/plugin install setlist@setlist
```

Then open Claude Code in your project directory, set the session to Opus, and run the entry command that fits:

```
/model opus
/setlist:new
```

Session zero runs on **Opus**, not `opusplan`: it is pure architecture work, and you want full reasoning strength for the whole conversation. Day-to-day building afterward is where `/model opusplan` takes over, and day-to-day Git runs through the shipped `/setlist:checkpoint` command.

## Get started, by situation

### Starting a new project: `/setlist:new`

Run it in an empty directory. What happens, in order:

1. **You describe the project** in plain conversation: what it is, your constraints (budget, solo or team, legal/privacy), and your working mode (*I write code too* or *I review only*; the second makes generated specs strict and exhaustive, because anything unspecified becomes an unreviewed guess).
2. **One structured interview round.** Only genuine forks become questions, recommendations come inline, and it opens with "what has changed since this edition was written" to catch tooling drift. It also live-verifies that the `opusplan` model binding actually resolves in your environment before committing it to settings.
3. **The foundational decisions, proposed for your approval before any file is written**: the stack (with explicit rejections), the core data model (the single highest-leverage decision), scope with an enforced out-of-scope list, and the riskiest assumption worth a throwaway spike. Each lands as an ADR, not as chat.
4. **Two-phase generation.** A mechanical stamp emits every framework-fixed file (the hooks, the config, the templates, the committed edition) with zero model tokens; the model then writes only what encodes your decisions: steering docs, founding ADRs, your first specs, and a `RUNBOOK.md` with your stack's concrete commands.
5. **Hand-off.** Nothing is committed yet by design: run `/scaffold` next. It is not a plugin command, which is why the table below does not list it: it is a project-local skill the bootstrap just generated into your repo. It wires the test harness, records your full-suite gate command, makes the first commit, and arms the enforcement hooks by setting `core.hooksPath` and `merge.ff` right after it creates the repository, which is what makes the git hooks run at all (the stamp cannot set them: `/setlist:new` starts in an empty directory, and it says so).

You end up with a tailored, enforced instance and a queue of real specs. From there, each feature follows the operating loop below.

### Adopting it on an existing codebase: `/setlist:retrofit`

Run it at the repo root. The whole session is planning plus documentation: it reads your code, it never edits it.

1. **Read-only inventory first.** It explores before asking anything: the actual stack, the de-facto core data model, state ownership, error handling as practiced, honest test-coverage reality, secrets exposure, and the riskiest areas. You see the report before a single question.
2. **The interview** adds one retrofit-specific fork: which existing constraints are **sacred** (not redesignable in the coming months) versus disposable, so no future spec proposes redesigning something you consider settled.
3. **Generation describes what IS, not what you wish.** Steering docs record every divergence between reality and intent with explicit callouts; the decision log is seeded with INFERRED entries read off the code, and confirming or superseding each one (the flip ceremony) is your first planning action afterward.
4. **The first spec is characterization tests** around the de-facto core: black-box assertions that pass against the unmodified codebase, so every later change has a regression net before it lands.
5. The whole retrofit lands as **one commit** on your default branch; the gates bind immediately using your repo's real test command.

### Already running an earlier edition: `/setlist:upgrade`

Run it at the root of a repo that carries an earlier `setlist.md` edition.

1. It confirms no spec is mid-build (or pauses one cleanly with a resume prompt), then **diffs your instance against the bundled edition**, using the edition's changelog as the authoritative delta list.
2. **One round of genuine forks** (accepted deviations to keep or retire); everything else gets a recommended default.
3. Execution happens on a **single migration branch**: relocations move verbatim under provenance banners (history is never rewritten), one umbrella ADR records the edition change, the committed edition file is replaced, and hook fixes arrive byte-for-byte.
4. It is a docs-only change by contract: **your gates must pass identically before and after**, and any difference is a finding, not noise.

### No plugin?

The plugin is the supported path, but the framework document is self-contained: copy [`setlist.md`](setlist.md) into your project, open a session on Opus, and ask it to run the protocol that fits: bootstrap, retrofit, or upgrade (the document carries all three). The protocols are identical; the plugin is a binding of the document, never the other way around.

### Try it in three prompts

The first two build on each other: prompt 2 assumes the project prompt 1 bootstrapped. Prompt 3 works on any repo, independently.

1. In an empty directory: `/setlist:new`, then answer its opening with *"A CLI reading tracker: log books and pages read, see streaks and a yearly pace. Solo project, I review only."* Watch it interview you and propose decisions before writing a single file. (The demo at the top of this page is this exact prompt.)
2. In a bootstrapped project with uncommitted changes: `/setlist:checkpoint` with *"survey and commit what is pending, spec-scoped."* It surveys the diff, checks for secrets and style violations, and commits with a spec-scoped message.
3. At the root of any existing repo: `/setlist:retrofit`. It shows you a read-only inventory report (stack, de-facto data model, test coverage reality) before asking a single question.

### Invocation discipline, built in

The stamping ceremonies (`/setlist:new`, `/setlist:retrofit`, `/setlist:upgrade`) are **user-only**: the model cannot decide on its own to bootstrap or migrate your repo. `/setlist:checkpoint` stays available to the model deliberately, so a session about to commit pulls the checkpoint checklist into context by itself. That split is the framework's philosophy in miniature: ceremonies with side effects wait for you; discipline loads itself.

## The full command and skill surface

The seven commands:

| Command | What it does | Invoked by |
|---------|--------------|------------|
| `/setlist:new` | Bootstraps a new project from an empty directory: interview, foundational decisions for your approval, then the tailored two-phase stamp. | You only |
| `/setlist:retrofit` | Audits an existing codebase read-only, interviews you, and retrofits the framework around what actually exists. | You only |
| `/setlist:upgrade` | Migrates an instance from an earlier edition to the bundled one, on a single docs-only chore branch, gates unchanged. | You only |
| `/setlist:gate` | Runs a stage-gate transition when your project moves between roadmap stages: verifies the stage's exit criteria leg by leg, reconciles the next stage's backlog, and specs its first entry. A failed gate is a finding, not a formality. (Distinct from the mechanical close gate that `/setlist:checkpoint` runs.) | You only |
| `/setlist:checkpoint` | Spec-scoped Git: opens the spec branch, surveys and commits with secret and style checks, runs the close gate, merges `--no-ff`. | You, or the model when about to commit |
| `/setlist:validate` | Idempotent health check of the instance: required files, bounded STATUS sections, hook wiring, config coherence. Reports findings, fixes nothing without approval. | You, or the model at a transition gate |
| `/setlist:journal` | Writes the numbered journal entry for a substantive session: raw notes, what surprised you, no narrative smoothing. | You, or the model after a substantive session |

One more lives outside the plugin: `/scaffold`, the project-local skill the bootstrap generates into your repo (it wires the test harness and makes the first commit; see step 5 above).

The plugin also carries four **reference skills**: context the model loads by itself at the moment it applies, never commands you type.

| Skill | Loads by itself when | What it carries |
|-------|----------------------|-----------------|
| `model-ladder` | A session weighs escalating models | The escalation rules between planning and execution tiers |
| `planner-discipline` | Planning work starts | The operating loop, the read budget, and the park-do-not-improvise rule |
| `spec-authoring` | A spec is being written | The spec template and the closing-report contract |
| `design-surface` | UI work routes through a design intake | Locked redlines as spec contracts, design QA on the branch |

Each skill also carries a **Gotchas** section grown from real field failures, never speculation. This table is the complete surface: the publish tooling mechanically refuses a release whose README and shipped skills disagree, in either direction.

## Why one spec at a time

The first question anyone arriving from a multi-agent harness asks is what Setlist does about parallelism. The honest answer is that the sequential model is a deliberate position, not a missing feature.

One spec is active at a time, and no two agents write coupled code at once. The bet is that for a person directing rather than typing, correctness of decisions beats throughput of execution: the bottleneck in agent-assisted work is not how fast code appears, it is how much of it you can actually review before it becomes the foundation for the next thing. Ten features arriving in parallel is not ten times the progress if you can only genuinely review two of them. Read-only parallelism is unrestricted, because that constraint protects the shared model from concurrent edits, not research from speed: inventory sweeps, ground-truth probes, and verification runs fan out freely.

Nothing in the architecture precludes going wider later. A spec is already a self-contained unit of scope with its own branch, acceptance criteria, and gate, which is exactly the interface a parallel execution plane would need. If that arrives it will be because independently-scoped specs proved they could run without stepping on each other, not because throughput sounded appealing.

## Does it actually work?

Every release passes a **dogfood gate**: a fresh agent with zero prior context is given only this repository and its README, and must take a small real application from empty directory to a merged, twice-QA-passed feature with the discipline holding at every step. Recent gate runs built a Go CLI, a Python CLI, and a Node.js CLI end to end, each cold from the installed plugin. The enforcement hooks are additionally **hostile-tested**: real subprocess sessions actively try to commit em-dashes and secret-shaped strings, merge specs with incomplete closing reports, and write feature code on the trunk, and the run only passes when every attack is refused by the layer that owns it, with the specific failure named. Read that precisely, because this release moved which layer owns what: the GIT hooks refuse and the session gates warn. Writing feature code onto the trunk is PERMITTED by the scope gate, which is advisory now, and by `git commit`, which does not run the close verification for an ordinary commit; the trunk audit at `pre-push` is what refuses it. That is why the guarantee is about the remote trunk rather than your local one (found by adversarial review).

The QA discipline you can expect, from those runs' closing report format:

```
QA Pass 1 (automated, per acceptance criterion): PASS / PARTIAL / FAIL, one line each,
pasted verbatim into the spec. Anything the automated run cannot exercise is an honest
PARTIAL with the reason, never a claimed PASS.
QA Pass 2 (you): use the feature yourself; spot-check at least one criterion marked PASS.
```

The mechanical layer additionally runs as an **automated suite** on every push, on Linux and macOS: fixture repositories built from scratch, every gate driven through the same payloads Claude Code sends it, and both contracts asserted on each denial (the machine-readable decision, and whether the message names the specific failure a person has to fix). That suite is a regression net for the hooks; it is not a substitute for the dogfood gate, which tests whether a stranger can actually use the thing.

## The trunk audit (opt-in)

The Claude Code hooks above decide by reading a command before it runs, which is why they are advisory. `scripts/trunk-audit.sh` asks a different question, of your repository rather than of a command: does the trunk's history show every piece of feature code arriving through a closed spec? Because it reads history rather than guessing intent, it sees what a command-reading gate structurally cannot, including work that arrived through a renamed branch, a cherry-pick, or your forge's merge button. It does not see through merge topology built to hide the work: see Known limitations.

Run it whenever you want a second opinion:

```
bash "$CLAUDE_PLUGIN_ROOT/scripts/trunk-audit.sh" .
```

It reports three kinds of commit: clean, unverifiable (a chore branch carries no spec, and history cannot tell one from an unspecced feature), and violations.

It runs automatically at push, because the git hooks are now part of the protocol rather than a sample you were invited to copy. `/setlist:new` and `/setlist:upgrade` stamp them for you.

## Known limitations

**The guarantee does not live in your Claude Code session.** It used to be four hooks running inside your Claude Code session, deciding what a command would do by reading the command's text. That layer is still there and still useful, and as of 2026-08-04 it is advisory **in mechanism as well as in name**: it warns and permits, and it no longer holds a veto over your session. Each session gate reports what it would have decided, why, and the code, and then lets the command run. The git hooks below are what refuse the work. This wording used to describe a warning while the gates actually denied, and the gap cost a release cycle: successive rounds of adversarial review found that most new defects sat in parser code written that same day to fix the previous round's findings, and while the parsers could deny, every one of those defects was release-blocking. **The trade is explicit, and one half of it did not survive contact with the harness.** A false positive is now noise instead of a blocked command. But **on current Claude Code versions the advisory reason is not shown to the model when the decision is `allow`**, and an advisory verdict is always `allow`, so in practice the session gates do not warn the agent today: the in-session feedback you actually get is the **git hooks' refusal messages**, arriving as ordinary command output at the moment of the attempt, which is where the guarantee lives anyway. That one is under Upstream conditions below, with its measurement, the control that makes it a harness finding rather than a wiring one, and the probe that lifts it. The guarantee moved to **git hooks**, stamped into a tracked `.githooks/` directory, which git runs itself after it has already parsed the arguments and resolved the refs. For cooperating use there is nothing left to spell around at that point: a merge is a merge however it was written. That is a claim about the SHELL, which it survives, and not about a committer crafting merge topology to evade the audit, which it does not. **Within the git-hook layer, the guarantee is the push-time trunk audit specifically.** The two per-merge hooks keep refusing at commit and merge time, and that early refusal is the feedback you feel day to day; the audit at `pre-push` is what stands between unreviewed work and a shared trunk, and it decides by identity and ancestry (does this history descend from the commit that adopted the rules; did this content arrive through a closed spec's lineage) rather than by recognising the shape of any operation. A route past a per-merge hook is therefore a MAJOR in this project's severity model, not a release blocker: the work is refused later than intended, at push, rather than not at all.

Why the change: across five releases, every hardening pass closed one spelling and the next release found another, because a shell command can compute its own arguments and the set of spellings has no end. Then the parser layer died on macOS for a reason that had nothing to do with command text, silently allowing everything, while a git hook on the same machine in the same run was untouched. A parser has failure modes its subject matter does not.

Both halves of the boundary are worth stating plainly, because an enforcement layer whose edges you cannot see is one you cannot reason about.

The list below is 33 entries, and they are not the same kind of thing, which is why they now arrive in three groups rather than as one wall. **18 are design boundaries**: decisions with a date and a reason, where the layer deliberately stops. **13 are open limitations**: real defects or gaps with a fix scheduled, a candidate, or a named gate, each carrying its status. **2 are upstream conditions**: things this project does not control, with what would lift them and how that is re-checked every release. A design boundary read as a defect overstates the problem; a defect read as a decision understates it.

### Design boundaries (18)

These are boundaries, not bugs. Setlist governs the session; it is not a server-side policy engine and does not try to be one. Each one is a decision, and each says when it was taken and why.

- **Merges crafted to evade the trunk audit can succeed, and the list of known routes is maintained rather than complete.** The audit reads history and judges each merged parent; it does not attribute individual files to the spec that authorised a merge, because that is not decidable from history. Two routes are known and OPEN: a chained merge (unspecced code merged INTO a spec branch, then that branch merged with a compliant close), and the OCTOPUS spelling of the same trick, where parent order hides the unspecced parent behind a catch-up parent. Both were found by adversarial review rather than by use. Both were refused for a while, and the checks that refused them were removed on 2026-08-07, because neither could tell the crafted shape apart from ordinary work: the chained-merge check reported `git pull` on a shared trunk as a violation, naming as the offender the compliant close merge it had passed clean minutes before. That is the second developer on any team, on the commonest git command there is. A false denial on ordinary work costs more here than the bypass it prevents, so the route is documented instead of defended. The history is the point of this bullet: the second route was introduced by the fix for the first, and the fix for both broke everyday use. A cooperating developer does not construct these; someone determined to bypass the audit will find the next one before we do. Put branch protection and required checks on your forge if that matters to you.

- **The trunk is recognised by the NAME recorded in `.claude/sdd.json`, so an instance that merges onto a differently-named branch is ungoverned.** Every git hook asks "is the checked-out branch the recorded trunk" by comparing names. On a git-flow shaped repository, where the team works on `trunk` or `develop` which tracks `origin/main` while a local `main` also exists as the release branch, a recorded trunk of `main` means every hook takes its fail-open exit while merges really do advance the branch the project treats as its trunk. Measured on the shipped bytes: unspecced role-path code lands on that branch with the whole guarantee layer silent. Between 2026-08-05 and 2026-08-07 the hooks also consulted what the branch TRACKS, which closed this shape and broke a much commoner one: `git checkout -b <name> origin/main` is git's own documented way to branch from a remote trunk, git announces it with "set up to track", and every such branch became the trunk to the hooks, so merging role-path code into an ordinary spec or feature branch was hard-refused with a message naming `main` as the target of a merge that never touched it. The two shapes are indistinguishable from inside a hook, so the tracking test was removed and this limitation is the honest statement of what is left. **The remedy is one line**: record in `.claude/sdd.json` the branch you actually merge onto. The upgrade skill prescribes exactly that.

- **git allows one `core.hooksPath`, so Setlist cannot coexist with husky, lefthook or pre-commit, and `refresh-instance.sh --apply` now REFUSES rather than displace one silently.** Until 2026-08-08 it overwrote the setting unconditionally with no warning and no backup, and report mode said "git config still to set: core.hooksPath" while it was already set to something else that was about to be switched off. Measured: the identical `git commit` was refused by `.husky/pre-commit` before the refresh and committed cleanly after it. What gets displaced is often itself a control, since gitleaks, detect-secrets and commit-msg validation are commonly wired exactly this way. Report mode now names the value it would displace and what stops running; `--apply` refuses and tells you the two ways forward, which are to move those checks into `.githooks/` or to re-run with `SETLIST_ADOPT_HOOKSPATH=1` and displace the other layer on purpose. This is a limitation of git rather than of Setlist: the two layers genuinely cannot both run, and the only thing that was ever fixable is whether you find out.

- **A checkout is an enforcement switch: every git hook is inert on a branch without `.claude/sdd.json`.** Each hook opens by checking that the CHECKED-OUT branch carries that file and exits silently when it does not. That guard is deliberate and load-bearing, because a `core.hooksPath` set in one repository must not govern unrelated work. The consequence is that the guard is also a switch: measured on the shipped bytes, a push of an unclosed merge is refused from the trunk and the IDENTICAL push of the IDENTICAL commits succeeds after checking out an orphan or legacy branch that has no `sdd.json`, and the work reaches the remote trunk (measured under adversarial review). If your repository carries branches without the file, the enforcement boundary is conditional on which branch happens to be checked out. This is documented rather than closed: narrowing the claim was the recorded decision once repeated repair rounds kept introducing new defects, and a fix here would have to distinguish "not a Setlist project" from "a Setlist project standing on an unstamped branch", which the file alone cannot do.

- **The `SETLIST_SKIP_HOOKS=1` escape is not read by `pre-push`.** The other hooks honour it and `pre-push`'s own refusal text names it, but the variable is not consulted there, so it will not get a refused push through (measured under adversarial review). Use `--no-verify` for that, or fix the content the scan objected to.

- **`--no-verify` skips git hooks**, and `git push --no-verify` skips the pre-push audit. This is a real hole and a different kind of hole from the others: a deliberate act with an obvious name, not an apostrophe in a commit message. Setlist's own escape hatch, `SETLIST_SKIP_HOOKS=1`, is the same thing said out loud.

- **Git hooks are per-clone, and the tracked directory narrows that without closing it.** `.git/hooks` is not cloned, which is exactly why the hooks are stamped into a tracked `.githooks/` instead: they are versioned, reviewed in diffs, and present in every clone. What is still per-clone is the CONFIG pointing at them, since `.git/config` is not cloned either, so a fresh clone is unprotected until it is set up. The same applies to `merge.ff=false`, which Setlist sets because a fast-forward merge fires no git hook at all. Expect merges that used to fast-forward to create merge commits; that is the setting doing its job.

- **A role directory spelled in a different case is not seen by the session scope gate on macOS or Windows.** With `roles.src` recorded as `src`, a write to `SRC/a.txt` is the same file on a case-insensitive filesystem but does not match the role path, so the gate stays silent where `src/a.txt` is refused. The trunk audit catches it: git stores the path under its on-disk spelling, so the commit is reported as feature code on the trunk and `pre-push` refuses it. Advisory layer misses, guarantee layer holds, which is the layering this release claims.

- **A `<<\EOF` heredoc body is read as code by the session gates, and can run your whole gate command before an ordinary `git commit`.** The four other heredoc spellings (`<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`) are read correctly; only the backslash form is missed, because the delimiter reader requires a letter or underscore at that position and gives up on the backslash. Measured on the shipped bytes, with controls: `git commit -F - <<\EOF` whose message body mentions a merge was judged as a real trunk merge, ran the close checks for that spec, and EXECUTED the project's gate command synchronously inside the PreToolUse hook, which the template ships with `timeout 1800`. The quoted spelling and a plain `git commit -m` did not; a real merge did, which is the control. So on a large suite an ordinary commit can hang for the length of your test run. The parsers are FROZEN, and the owner's decision on 2026-08-08 was to hold that freeze and document this rather than widen the character class, because parser repairs have historically introduced their own defects. Workaround: use any other heredoc spelling, or `git commit -m`. The git hooks are unaffected, and nothing here lets work reach the trunk.

- **The session gates are text parsers, and a growing list of spellings read a command wrongly.** They are advisory, so MOST of these are a warning that is absent or misleading rather than a command wrongly blocked, and for most of them the git hooks judge the same operation correctly afterwards. **Two of them are not merely absent warnings**, and the sentence used to claim all of them were: the diagram-field item below is shared by both layers so no later layer corrects it, and the `<<\EOF` heredoc item runs your gate command before an ordinary commit, which is neither a warning nor absent. The diagram-field item below is the exception, and it is the reason this sentence says most rather than all: that one is shared by BOTH layers, so no later layer corrects it. A `git checkout` run in a DIFFERENT repository (`cd vendor/lib && git checkout x && cd - && git merge ...`) is credited to this project, so the close warning does not appear. The architecture-diagram field is read from the whole spec rather than from the Closing report section, so a later bulleted mention of the label can decide it in either direction. And the commit gate assumes textual order is execution order, so a loop body that commits before it stages gets no warning. These are frozen: the parsers and their corpus are closed to new spellings as of 2026-08-04, because chasing them is what the measurement above priced. These are FROZEN by decision: the parsers are not repaired for new spellings, because the guarantee moved to the git hooks and each parser repair has historically introduced its own defect. Adversarial review also recorded, and this release does not fix: a trailing shell COMMENT read as commit flags, text inside a comment judged as live commands when the comment contains a separator, ANSI-C quoting of the subcommand (`$'merge'`) read as nothing to govern, an attached `-m` message (`git commit -mfix`) read as option letters, a git ALIAS as an unhandled spelling, and a fenced quotation of the spec template refused by the commit gate. Each is a warning arriving late or not at all. With the exception of the diagram-field item, none of them lets work reach the trunk, which is what the git hooks decide; that one does, because the same last-match reading is in the hooks and the audit alike, and it has its own bullet above.

- **The trunk audit cannot tell a merge that EDITS a file from ordinary conflict resolution.** It reports role-path files a merge commit introduced that no parent carries, which covers `git commit --amend` on a completed merge and evil merges that ADD content. A merge that edits a file a parent already had is indistinguishable by content from a legitimate conflict resolution, so it is not flagged: doing so would refuse every real merge.

- **The Bash escape hatch.** The scope hook watches the file-writing tools (Write, Edit, MultiEdit, NotebookEdit), so a session that writes files through Bash instead (`cat >`, `sed -i`, a heredoc) does not trip it, and the commit gate checks what a commit contains rather than where the file lives. The same boundary applies to git itself: the gates read the command they are given, so a git command run through another interpreter (`sh -c '...'`, a backtick, a script file) is not a command they can read. Wrapper prefixes that a person actually types (`command`, `env`, `nice`, `nohup`, `exec`, and leading `VAR=value` assignments) ARE handled, but that list is not a claim of completeness and cannot be one. The trunk audit below is the designed catch for this whole family: it reads what ended up in your history and does not care how the command was spelled.

- **Sideways routes to the trunk.** The close gate reads the merge command; content can still reach the trunk through commands it does not parse: `git cherry-pick` of spec-branch commits, `git pull <remote> spec/...` (a fetch-and-merge the gate does not intercept), merges performed on a detached HEAD (no current branch, so the gate never sees a trunk target). Merging a spec branch under a second NAME used to be on this list and no longer is: as of 1.0.8 the gate resolves a merge argument to a COMMIT and asks git which refs point at it, so an alias, a tag, `heads/spec/...`, a remote-tracking ref and a raw object name all identify the same branch and are all governed. These remaining routes are named rather than parsed because each is a deliberate spelling of "go around the gate", and a visible edge is more honest than a half-parser that would miss the next spelling. Each of them is caught by the trunk audit below FOR COOPERATING USE, which is why the two layers exist: the gates stop things as they happen and can be spelled around, and the audit reads history afterwards so it does not care how work arrived. It is not immune to being spelled around either: merge TOPOLOGY crafted to evade it (a chained merge, an octopus parent order) is a separate class, named in its own bullet above, and closing those routes has not been convergent.

The three routes below are the same family as the bullet above, split out because each is a command a person runs for ordinary reasons rather than a deliberate spelling of "go around the gate". All three were measured on the shipped bytes for this release, with controls in both directions: a compliant close pushes clean, and an unclosed merge on the trunk is refused. In each case the trunk audit at `pre-push` refuses and the remote is untouched, so what these cost you is the EARLY refusal, not the trunk. That is the two-layer design working as intended, and it is still worth knowing which commands take the slow path.

- **`git rebase` onto a spec branch brings that branch's commits to the trunk with no closing merge.** The close gate reads `git merge`; a rebase is not a merge, so the gate emits no verdict at all and nothing warns you at the moment you run it. Measured: run on the trunk, it leaves the spec's role-path file on the trunk, and the next `git push` is refused with `VIOLATION ... feature code committed directly to main`, remote unchanged. The suite pins this as a documented hole, so the day it stops being one, the suite says so instead of the docs quietly going stale. Close a spec with `--no-ff` instead, which is what `/setlist:checkpoint` does.

- **`git reset --hard <spec-branch>` moves the trunk onto unclosed work outright.** Same silence at the session layer, for the same reason: there is no merge for the close gate to read. Measured: the trunk ends up at the spec branch's tip carrying its role-path file, and the push is refused with the same `VIOLATION`, remote unchanged. Reach for `git reset --hard` on a trunk only when you mean to discard local commits, never as a way to take a branch's work.

- **`git checkout <spec-branch> -- <path>` copies role-path files onto the trunk without any merge to read.** The pathspec form of checkout writes files from another branch straight into your working tree, and the commit that follows is an ordinary commit: the close gate has no merge to judge, and the commit gate scans content rather than provenance, so it commits clean. Measured: the file lands on the trunk at exit 0 and the push is then refused with the same `VIOLATION`, remote unchanged. If you want one file from a spec branch, take it through the spec that owns it.

- **The pathspec hole.** `git commit <file>` commits the working-tree copy of that file without staging it, so the staged-content scan has nothing to look at. The test suite asserts this hole deliberately rather than hiding it, so the day it closes, we find out.

- **The scans read this project's own index.** The commit gate looks at what is staged in the project it governs. A commit aimed somewhere else is therefore not scanned: `git -C some/nested/repo commit ...` commits that repository's index, and `GIT_INDEX_FILE=...` names a different index outright. Your own staged content is still checked, every time. Following the target index instead would mean re-deriving which repository each command line means, in every spelling, which is the kind of parser-chasing that has produced more holes here than it has closed. A nested repository is a different project, and if it should be governed it should have its own instance.

### Open limitations (11)

These are defects and gaps rather than decisions. Each carries its status: the spec that closes it, the cycle it is scheduled to, or the gate it waits on. **This list shrinks by fixing, never by editing**: a bullet leaves it in the commit that closes its hole.

- **The Architecture-diagram check is decided by the LAST matching line, so a later note can answer or unanswer it.** The close gate and the git-hook layer both read the Closing report's `Architecture diagram:` field by taking the last line that matches, anchored past a list bullet. A follow-up note written as a list item is such a line, so it wins over the real field in BOTH directions: a spec whose field is answered can be REFUSED because a later bullet repeats the label with the template placeholder, and a spec whose field is unanswered can MERGE because a later bullet happens to read as answered (found by adversarial review and reproduced at both layers). Keep the `Architecture diagram:` label on exactly one line of a Closing report and do not repeat it in follow-ups. This release has corrected field-versus-substring reading three times on three surfaces; it is documented here rather than corrected a fourth time, per the scope-reduction decision recorded in the gate report.

  **Status: fix scheduled.** It is the highest-severity item on this list because both layers share the defect, so no later layer corrects it. The durable fix is a structured field the readers cannot mistake for prose, rather than a fourth prefix rule of the kind that produced the last three corrections.

- **Secret and style scanning is best-effort early warning, not a guarantee.** Treat any secret that reached a commit as COMPROMISED and rotate it, whatever these hooks reported. This limitation is written at this strength because the claim above it was narrowed three times and falsified three times under this release's own adversarial review, and the mechanism is what decides which sentence is true. **Two structural holes remain, and they are structural rather than a matter of pattern coverage.** The scanner reads the output of `git diff`, which is a RENDERING the repository controls: a `.gitattributes` entry marking a path `-diff` or `binary` makes git emit no added lines at all, and a live-shaped secret then reaches a remote at exit 0 by the ORDINARY commit-and-push path (measured under adversarial review). And the pattern set is a first cut rather than a complete secret detector: it matches token-shaped and connection-string-shaped values, so it will miss exotic formats and can flag something innocent. Separately and not a hole in the scan: git fires no hook for `cherry-pick`, for `rebase`'s intermediate commits, or for the apply step of `git am`, so those are read at push rather than at commit. What the scan is good for is catching an accident early on the ordinary path. It is not a control you can put between a secret and a remote.

  **Status: the four scheduled holes are FIXED as of this release**, and the bullet above shrank with them: the endpoint diff is now a per-commit walk of the pushed range, the first-push range derives against the remote's own refs instead of coming out empty, a tag push is scanned for what it publishes, and the `+++` header strip is anchored to the header. The two that remain are structural and stay: a `.gitattributes` entry that suppresses the diff, and the pattern set. The sentence above the list is the one to trust either way.

- **`git merge --ff-only` and `git merge --ff` skip the merge hooks.** A fast-forward creates no merge commit, so there is no `pre-merge-commit` for git to run, and an explicit `--ff-only` beats the `merge.ff=false` Setlist sets. So does a bare `--ff`. Unlike `--no-verify` neither looks like a bypass, which is why they are called out here: they are normal preference flags and some GUI clients pass them for you. What this costs you is the merge-time close verification, which does not run: the commit-time checks and the push-time trunk audit both still do, and the audit reads the close conditions off the commit itself, so a COMPLIANT fast-forward close is accepted at push. `--no-ff` remains the recommended way to close, and is what `/setlist:checkpoint` does, because it is the only route that runs every layer. The suite is separately not re-run by the audit.

  **Status: fixed as of this release.** A compliant fast-forward or `--squash` close is no longer refused at push; the two layers now agree, and the audit decides on the parent COUNT so one rule covers both flag names.

- **`git merge --squash` needs one flag to work in a Setlist instance, and the error does not say so.** `merge.ff=false` implies `--no-ff`, and git refuses `--squash` in combination with it: `fatal: options '--squash' and '--no-ff.' cannot be used together`, on every squash merge, whether or not the branch could have fast-forwarded. The message names neither Setlist nor the setting, so there is nothing to search for. Use `git -c merge.ff=true merge --squash <branch>` for a one-off, or drop the setting for that command. A squash has no second parent, so the trunk audit can never see the branch the work came from; it reads the close conditions off the commit instead, so a COMPLIANT squash close is accepted at push. As with a fast-forward, what you lose is the merge-time close verification, and `--no-ff` stays the recommended close because it runs every layer. The setting stays because a plain fast-forward merge fires no git hook at all, and that hole is worth more than the convenience.

  **Status: fix scheduled for the next release cycle**, jointly with the `--ff` bullet above.

- **The close gate refuses `@{u}` and other revision-suffix spellings of a merge operand.** `git merge origin/main` is allowed, because syncing the trunk from its own remote is not a close; `git merge @{u}`, `git merge @{upstream}` and `git merge main@{u}` name the same ref and are refused with `CG-UNNAMEABLE-REF`. The gate refuses operands it cannot resolve to a literal branch name, and that rule is right for `@{-1}` and `FETCH_HEAD`, whose meaning changes between the moment the hook reads them and the moment git acts; it is merely conservative for `@{u}`, whose value is fixed configuration. Spell the ref out. This is a session-layer refusal only: the git hooks and the trunk audit are unaffected.

  **Status: gated on the parser freeze** recorded in the design boundaries above (2026-08-04). It is a session-layer inconvenience with a one-word workaround, and it lifts when that freeze lifts.

- **A headless build has no integrity chain.** Nothing mechanically stops a `claude -p` session from building against a spec that was edited after approval. Setlist records a `Spec-hash` when a spec goes ACTIVE and WARNS at session start when the spec has changed since, but a SessionStart hook can only warn: it has no ability to deny. The designed fix (an attestation binding the verdict to the hash as signed data) is drafted in Part 7c of the edition and is deliberately not built in this cycle.

  **Status: design scheduled, implementation later.** The attestation design is being ratified now; building it is its own cycle. Until then the SessionStart warning is the whole of it, and a warning is not a denial.

- **The set of tested platforms is a list, not a proof.** The suite runs on Linux and on macOS under bash 3.2 with the BWK awk, which is where the platform fault that prompted all of this would have been caught. A platform not on that list is untested, and the release notes say which list rather than implying the proof.

  **Status: scheduled.** Widening the matrix is queued for a CI batch. Until it lands, read the list as the claim: it is two platforms, not a proof about platforms.

- **The remote-merge bypass.** The close gate intercepts a `git merge` run in the session. Merging through `gh pr merge`, a button in a forge's web UI, or a push of an already-merged trunk goes around it entirely, which matters the moment a project moves to a pull-request flow: the strongest gate is then out of band. Your forge is the right place to close that half. Protect the trunk and require status checks, so the merge button enforces what the local gate would have. Running the close checks themselves as a CI job is the obvious way to finish the loop, and is a candidate rather than a promise.

  **Status: candidate, not a promise.** It moves when a real pull-request-flow instance drives the requirement. Today your forge is the right place to close it, and branch protection with required checks is the closing move.

- **The secret scan is a first cut.** It matches token-shaped and connection-string-shaped values, which catches the common accidents. It will miss exotic formats and it can flag something innocent. Tuning comes from field reports, so send them.

  **Status: candidate, fed by field reports.** There is no scheduled cycle for it, because the tuning that would help is the tuning real misses tell us about.

- **A broken or missing `jq` is handled by the GIT hooks, not by the session gates.** The session gates are advisory and that applies to their failure paths too: with `jq` absent or exiting non-zero they emit `permissionDecision: allow` carrying a code (`SH-JQ-BROKEN`, `CM-NO-JQ`, `CG-NO-JQ`, `*-NO-TOOLCHAIN`), and the operation proceeds. Measured on the shipped bytes: a trunk write under a `jq` that exits 3 returns `allow` with `SH-JQ-BROKEN`. The layer that actually refuses is the git-hook layer, which stops the commit. The gates' own message text and the SessionStart notice say exactly this: they report their verdict and PERMIT, name themselves advisory, and point at the git hooks as the layer that refuses. One consequence is worth stating plainly rather than leaving to be discovered: the git hook's refusal reads `SLH-UNREADABLE-CONFIG: .claude/sdd.json could not be parsed`, which points at a config file that is usually fine when the real cause is the toolchain: if you see it, check `jq` first.

  **Status: fix scheduled for the next release cycle**, where the refusal names the toolchain instead of pointing at a config file that is usually fine.

- **The staged-content scans read every staged line unless you scope them.** By default the em-dash and secret scans do not know vendored third-party code, quoted external text, or test fixtures with dummy credentials from your own new writing, and **splitting the commit does not help, which this list said it did until 2026-08-04**: the scans read every added line of the index, so isolating the foreign content isolates it WITH the scanner rather than away from it. Since 2.2.0 you scope them by declaring the paths, repo-relative globs, in `.claude/sdd.json`: `"scan_exclusions": ["vendor/**", "test/fixtures/**"]`, honoured by both scans at the commit layer and the push layer alike. **Every skip is printed, naming the file and the glob that matched it**, because an exclusion nobody is told about is a hole one directory over. The deliberate limits, which are the reason this is scoping and not an off switch: the set reaches the two content scans and nothing else, so it cannot quiet the trunk audit, the close checks or role-path judgment; a pattern made only of wildcards is refused, so there is no spelling that means "all"; an unreadable set is refused with a named code rather than resolved in either direction; matching is case-exact and a path git had to quote is scanned and says so, because failing to exclude costs a refusal you can see while failing to scan costs a published secret. Declaring nothing leaves the scans exactly as they were. **One piece is not done:** the in-session advisory commit gate is not path-scoped, so inside a Claude Code session a commit of excluded content is still denied there even though the git hooks accept it; running the commit outside a session, or past the advisory verdict, works today. Do not edit third-party content to satisfy a style gate.

  **Status: built in 2.2.0 for the layer that carries the guarantee; the advisory session gate is not yet scoped and is the remaining piece.**
### Upstream conditions (2)

Neither decisions nor defects in this project: conditions in software it depends on. Each names what would lift it and the check that re-measures it per release, so it stops being true by measurement rather than by anyone remembering to look.

- **The session gates' warnings do not reach the agent on current harnesses.** The three PreToolUse gates compute their verdict and emit the reason on `permissionDecisionReason`, `systemMessage` and a machine-readable `setlistAdvisory` field, and Claude Code delivers none of them to the model when the decision is `allow`. Measured on 2.1.221 with the discriminating control that makes it a harness finding rather than a wiring one: a hook returning `deny` has its reason delivered verbatim, so the hooks are dispatched and the reason is dropped. Consequence: the advisory layer is a machine-readable surface for tooling and CI, not an in-session teaching surface, and the feedback you actually see is the git hooks' refusal at commit or merge time. Filed upstream as a Claude Code bug (PreToolUse allow-path reasons dropped); `dogfood/advisory-visibility-probe.sh` re-checks it per release and the limitation lifts by itself when the harness renders them.

- **A timed-out hook is a skipped gate.** Claude Code cancels a hook that exceeds its timeout and lets the tool call proceed; that behavior belongs to the harness, not to the hook. The stamped settings therefore set explicit, generous timeouts (30 minutes for the close gate, which re-runs your full suite). If your suite outgrows that, raise the `timeout` in `.claude/settings.json` rather than letting the ceiling find you. Relatedly, hooks run in a non-interactive shell: version managers wired into your interactive profile (nvm, pyenv, asdf) may be off PATH there, which shows up as a gate command that fails in the hook while passing in your terminal. That is a false deny, not a false pass; fix the PATH in the gate command itself.

## Repository contents

| File | What it is |
|------|------------|
| [`setlist.md`](setlist.md) | **The current framework edition** (the version is stated inside the file). The single source of truth; read this to operate or adapt the method. |
| `.claude-plugin/`, `skills/`, `templates/`, `scripts/` | The plugin (`setlist`): the marketplace and plugin manifests, the seven `/setlist` command skills and four reference skills, the instance templates including the stamped hooks, and the scripts that stamp an instance, extract a Part, and refresh an existing instance's enforcement files. All of it is a binding of the edition document. |
| `test/`, `.github/` | The hook test suite and the workflow that runs it on Linux and macOS on every push. Fixture repositories are built from scratch at run time; the suite depends on nothing beyond bash, git, `jq`, and coreutils. |
| `demo.gif` | The demo at the top of this page: a real `/setlist:new` session zero and the `/scaffold` first commit, recorded live and trimmed for pacing. |

## After bootstrap: the operating loop

The two roles run on a single tool. Under Claude Code's `opusplan` model setting, **the planning model runs in plan mode** (the Planner) and Claude Code **automatically switches to the execution model in execution mode** (the Builder). Plan mode is read-only, so the planner decides and the executor types. When the Builder loops on a bug (two failed fix attempts, or fixes that spawn new failures), escalate the session up the model ladder (the `model-ladder` reference skill carries the rules). Roles bind to artifacts, not to model names.

Once the framework instance exists, each feature follows the per-feature loop (your generated `RUNBOOK.md` has the concrete commands for your stack):

1. **Plan.** In Claude Code under `opusplan`, Shift+Tab into plan mode. The Planner re-grounds from `STATUS.md`, asks any genuine forks, and proposes the next spec. You approve; the Builder writes it.
2. **Branch.** `/setlist:checkpoint` opens `spec/NNNN-<slug>`.
3. **Build.** The Builder implements in small commits and runs the gates. Ambiguities get parked in `STATUS.md`, never improvised.
4. **QA Pass 1.** With gates green, run the automated criterion check; paste the report into the spec's Closing report.
5. **QA Pass 2.** Use the feature yourself; spot-check at least one passed criterion.
6. **Close.** Complete the Closing report. `/setlist:checkpoint` runs the close gate and merges `--no-ff`. `STATUS.md` names the next action.
7. **Next.** Shift+Tab, repeat.

Your inputs as the human: plan-mode conversations and approvals, answers to parked questions, QA Pass 2, and reading Closing reports. You never type code and never type Git.

The gates are the product, not ceremony: each one is a decision that stays yours instead of being improvised by the agent. The framework's bet is that a human hour spent on forks, approvals, and QA Pass 2 buys more correctness than the same hour spent typing.

## Where to start reading

- **Just want to use it?** Run the Quickstart above; read nothing first. When curious, skim Part 1 (the core idea) and Part 10 (quick-start summary) of `setlist.md`.
- **Want to understand the why?** Read the core (Parts 1-10), then Appendix A (principles) and Appendix B (anti-patterns).

A note on style: everything this framework produces avoids em-dashes by rule. New content uses commas, colons, parentheses, or separate sentences.

## Feedback and contributions

Field reports are the framework's fuel: every edition so far was distilled from real projects run end to end. If you adopt it, [open an issue](https://github.com/AlexCiortan/setlist/issues) with what held and what fought you; both are findings.

## About the author

Built by [Mihai Alexandru (Alex) Ciortan](https://www.linkedin.com/in/alexciortan), Principal Architect with 15+ years of enterprise platform engineering at one of the world's largest game publishers, part-time CTO at DEIO, and previously part-time CIO at MyBenefits from proof-of-concept through its acquisition. The framework is distilled from running real software projects with Claude Code end to end, and this repository is itself maintained under the discipline it describes.

## License

© 2026 Alex Ciortan. Released under the [Creative Commons Attribution 4.0 International License](LICENSE) (CC BY 4.0): use, adapt, and share it, including commercially, as long as you give appropriate credit. Suggested attribution: "Setlist, a spec-driven development framework by Alex Ciortan, licensed under CC BY 4.0."
