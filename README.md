# Setlist

[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757)](https://code.claude.com/docs/en/discover-plugins)
[![Plugin version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FAlexCiortan%2Fsetlist%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=plugin&color=blue)](https://github.com/AlexCiortan/setlist/blob/main/.claude-plugin/plugin.json)
[![License: CC BY 4.0](https://img.shields.io/badge/license-CC%20BY%204.0-lightgrey)](LICENSE)
[![tests](https://github.com/AlexCiortan/setlist/actions/workflows/test.yml/badge.svg)](https://github.com/AlexCiortan/setlist/actions/workflows/test.yml)

**Setlist** is spec-driven development for Claude Code, for one developer or a team: build real software by **directing rather than typing**. You act as architect and reviewer, the agent writes the code, and a spec (not the keyboard) is your control surface. Alone, the discipline lives in your clone's git hooks; on a team, the same checks run at the forge on every pull request (the Teams section below).

![A real /setlist:new session zero, recorded live at 2.5x: the interview's decision forks, the two-phase stamp, the framework's own health check, and /scaffold making the first commit with gates green](demo.gif)

Setlist ships as an installable Claude Code plugin (`setlist`): seven slash commands (`new`, `retrofit`, `upgrade`, `checkpoint`, `validate`, `gate`, `journal`), four reference skills, and eight mechanical hooks stamped into every project it generates: three git hooks (a push-time trunk audit that carries the enforcement guarantee, plus two per-merge hooks that refuse early), three advisory session gates, session re-grounding, and a Stop hook (2.6.0); beside them, a forge check that runs the same verification on every pull request where a team requires it. The current edition of the framework document is **[setlist.md](setlist.md)** (edition v1.14, the team edition; the version lives inside the file); you do not need to read it to start. The plugin version and the edition version are separate counters: the plugin counts releases of the tooling, the edition counts revisions of the document.

**Three numbers, and what each counts.** The edition version counts the protocol (`setlist.md`, v1.14 at this release; it moves when the document changes what a gate asks or what a close writes). The plugin version counts the binding (`.claude-plugin/plugin.json`, 2.6.1; it moves on every release of the tooling, edition turn or not). The plugin counter restarted at 1.0.0 when the plugin was renamed to `setlist`, so the releases numbered 1.6.0 through 1.8.0 that the edition's changelog names belong to the pre-rename plugin and a Setlist version below them is not a downgrade.

## Why Setlist

AI coding agents are powerful but drift: across a long project they lose context, wander from past decisions, and quietly expand scope. When you review instead of type, every ambiguity the agent resolves on its own ships unless you catch it later. Setlist's answer:

- **Specs are the contract.** Work proceeds one small spec at a time, each with exhaustive acceptance criteria.
- **Scope discipline is sacred.** An explicit, enforced out-of-scope list is the primary defense against ballooning.
- **Review is the gate, tests are the aid.** Your review is the quality bar; tests are written to be read as a specification of behavior.
- **Enforcement is a DISCIPLINE control for cooperating use, not a security boundary.** This is the sentence six rounds of adversarial review narrowed it to, and it is worth reading precisely. Setlist stamps git hooks into every project it generates, and git runs them from its own state after the shell is done. **For a developer or agent following the process**, that enforces closed-spec discipline: a merge bringing role-path code to the trunk is refused unless it closes a spec or records a chore, a spec whose row flips to CLOSED must carry a complete Closing report with a QA verdict and an answered diagram field, the project's gate command must pass, and the push-time trunk audit reads history for work that arrived by the ordinary routes no local hook witnessed. **It is not a control against someone who wants around it.** A committer who crafts merges specifically to evade the audit can: the routes found so far are named in Known limitations, that list is maintained rather than complete, and every attempt to enumerate them has so far produced a further route, including one introduced by the fix for the one before it. If you need a boundary that holds against deliberate evasion, it belongs on the forge, in branch protection and required checks, where it can be enforced somewhere the committer does not control, which Setlist now stamps as `setlist forge check`. **When the hooks do not run, none of this applies**: they are inert unless `core.hooksPath` points at the tracked `.githooks/`, and every hook exits silently when the CHECKED-OUT branch has no `.claude/sdd.json`. Secret and style scanning is separate and weaker still: best-effort early warning, never a control. The rules that DO hold survive long sessions, context compaction and model swaps, because they do not live in the context window.
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

Wider shipped in 2.6.0, and it is worth saying exactly what it consists of. A spec is a self-contained unit of scope with its own branch, acceptance criteria and gate, and since 2.6.0 the declarations carry the rest: two specs that declare disjoint `Owns:` sets cannot collide at the audit, the stamped CODEOWNERS makes ownership a reviewed fact rather than a claim, and the forge check judges every pull request's merge with the same predicates the local hooks use, so two people can each run a spec at once on separate branches and the trunk stays governed. What did NOT ship, and is not planned, is a coordination plane inside one checkout: within one developer's session the sequential bet stands, one spec active at a time, because that is the unit a person can actually review.

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

## Teams

Everything above works for one developer with one clone. Since 2.6.0 the same discipline holds across a team, and every piece of it is a stamped file you can read. Each item below names the boundary bullet that says where it stops, so this section and the Known-limitations list never disagree.

- **The forge check, required on your trunk.** `/setlist:new` and `/setlist:upgrade` stamp `.github/workflows/setlist-forge-check.yml`, which runs the instance's own `.claude/hooks/forge-check.sh` on every pull request as the status check named `setlist forge check`. It builds the merge the button would make and asks it what the git hooks ask: the close verification, the attestation walk, the content scan, the `push` gate tier and the trunk audit, one token on stdout, never a pass on absence, no escape variable. It cannot require itself: on the trunk's protection (GitHub: Settings, Branches or Rules) require a pull request, one approving review, and the status check by exactly that name. Branch protection and rulesets are free for public repositories and need a paid plan (Pro, Team or Enterprise) for private ones. Two settings belong beside the check rather than inside it: **require branches to be up to date before merging** (the check judges the merge against the base its checkout carries and does not read that setting), and **disable rebase merging** on the governed trunk (a rebase lands every branch commit as direct feature code, before the fact, where no run of the check sees it). Boundary: *The forge check governs the merge button only where the trunk requires it.*
- **`forge` custody: approval without a key.** Declare `"custody": "forge"` and the approval of a spec is the ACTIVE flip landing on the protected trunk through the required review, verified at the check from the trunk's protection as it stands and from the flip's ancestry; every pass says what that establishes, and the local hooks defer to the check by name. Boundary: *The forge check reads the trunk's protection as it stands, not as it stood* (and the custody bullet, *The headless integrity chain is only as strong as where your signing key lives*).
- **The CODEOWNERS bridge.** The stamped `.github/CODEOWNERS` carries an `@OWNER` slot you fill and makes `.githooks/`, `.claude/`, `specs/attest/` and `.github/` reviewed changes; the audit and the check judge every spec's `Owns:` declarations against it, refusing a close that declares a file another owner's pattern claims. Boundary: *The CODEOWNERS bridge reads a subset of the file's grammar, and a pattern is a claim about paths.*
- **Three gate tiers.** `gates.commit`, `gates.close` and `gates.push` in `.claude/sdd.json` name what runs at each layer (a lint at commit, the suite at the close, the full check at push); an absent block reads as today's single `gate_command`, and `/setlist:upgrade` writes exactly that. Boundary: *`git merge --ff-only` and `git merge --ff` skip the merge hooks*, so the close tier runs only on a real merge.
- **The lite spec tier.** `Tier: lite` in a spec's header keeps the parts the gates read and drops the rest; a lite spec owns at most five files and is refused past that at every close as `SLH-LITE-OVERSIZED`; `/setlist:checkpoint` drafts its Closing report from the record and leaves the verdicts to you. Boundary: *The close audit's single-parent arm is as strong as your declarations.*
- **The Stop hook.** The fifth session hook refuses to end a turn that leaves a spec or `specs/STATUS.md` change unstaged, once per turn, so a session cannot end with a record and a page that disagree. Boundary: *A session killed from outside fires no Stop, and the Stop hook is a nudge, never a lock.*

## Known limitations

**The guarantee lives in the git hooks, not in your Claude Code session:** the session gates are advisory in mechanism since 2026-08-04, and the push-time trunk audit is what stands between unreviewed work and a shared trunk. The list below is three kinds of thing: **design boundaries** are decisions with a date and a reason, **open limitations** are defects with a status, and **upstream conditions** are things this project does not control. Each bullet is a title and one sentence here, and its full text, with what to do and the history behind it, is in [LIMITATIONS.md](LIMITATIONS.md); **the counts live on the group headings below and nowhere else.**

### Design boundaries (33)

- **Git hooks are per-clone, and the tracked directory narrows that without closing it.** A fresh clone has the hooks but not the config that points at them, so it is unprotected until `refresh-instance.sh --apply` runs; the forge check is the layer that does not live in a clone. [Full text.](LIMITATIONS.md#per-clone-hooks)
- **`--no-verify` skips git hooks**: A deliberate flag with an obvious name skips every git hook, the push-time audit included; the forge check has no such flag. [Full text.](LIMITATIONS.md#no-verify)
- **git allows one `core.hooksPath`, so Setlist cannot coexist with husky, lefthook or pre-commit, and `refresh-instance.sh --apply` now REFUSES rather than displace one silently.** Only one hook layer can run; the refresh refuses to displace another one and names it, and nothing in git makes both run. [Full text.](LIMITATIONS.md#hookspath-conflict)
- **`git merge --squash` needs one flag to work in a Setlist instance, and the error does not say so.** git refuses `--squash` under the stamped `merge.ff=false` with a message that names neither Setlist nor the setting; a compliant squash close is accepted at push. [Full text.](LIMITATIONS.md#squash-flag)
- **`git merge --ff-only` and `git merge --ff` skip the merge hooks.** A fast-forward creates no merge commit, so no merge hook runs; the push-time audit still reads a one-commit close correctly and refuses a multi-commit fast-forward on its intermediate commits. [Full text.](LIMITATIONS.md#fast-forward)
- **The trunk is recognised by the NAME recorded in `.claude/sdd.json`, so an instance that merges onto a differently-named branch is ungoverned.** Every hook compares branch names against the recorded trunk; merge onto a branch with another name and the whole layer stays silent. [Full text.](LIMITATIONS.md#trunk-name)
- **A first push to a brand-new EMPTY remote audits every pushed branch as a trunk candidate.** With no default branch yet, `pre-push` cannot know which ref becomes the trunk and audits them all, refusing a spec branch pushed first; this fails closed. [Full text.](LIMITATIONS.md#empty-remote)
- **The `SETLIST_SKIP_HOOKS=1` escape skips EVERY git hook, `pre-push`'s trunk audit and content scan included.** Setlist's own escape is read first by every git hook, `pre-push` included; `SETLIST_SKIP_TRUNK_AUDIT=1` is the narrow one, and since 2.6.0 no refusal names either. [Full text.](LIMITATIONS.md#skip-hooks-escape)
- **The staged-content scans read every staged line unless you scope them.** The em-dash and secret scans read every added line of the index, vendored code and fixtures included, unless `scan_exclusions` in `.claude/sdd.json` names the paths; the in-session commit gate does not read exclusions and says so. [Full text.](LIMITATIONS.md#scan-scoping)
- **The scans read this project's own index.** A commit aimed at another repository (`git -C nested commit`, `GIT_INDEX_FILE=...`) is not scanned; your own staged content always is. [Full text.](LIMITATIONS.md#own-index)
- **Secret and style scanning is best-effort early warning, not a guarantee.** The scan reads a rendering the repository controls (a `.gitattributes` `-diff` entry emits no added lines) with a first-cut pattern set, so it catches accidents on the ordinary path and nothing more. [Full text.](LIMITATIONS.md#scan-best-effort)
- **The pathspec hole.** `git commit <file>` commits the working-tree copy without staging it, so the staged-content scan has nothing to read; the suite asserts this deliberately. [Full text.](LIMITATIONS.md#pathspec-hole)
- **A checkout is an enforcement switch: every git hook is inert on a branch without `.claude/sdd.json`.** Each hook exits silently on a checked-out branch that lacks the file, so a push refused from the trunk succeeds from an orphan branch; the forge check refuses such a pull request instead. [Full text.](LIMITATIONS.md#checkout-switch)
- **The set of tested platforms is a list, not a proof.** The suite runs on Linux under two awks and on macOS under bash 3.2 with the BWK awk; Windows has never been run, and the list is extended, never restated as a proof. [Full text.](LIMITATIONS.md#platform-list)
- **The session gates are text parsers, and a growing list of spellings read a command wrongly.** The three advisory gates read command text and a closed list of spellings misleads them; the parsers are frozen since 2026-08-04, and for all but one item the git hooks judge the same operation correctly afterwards. [Full text.](LIMITATIONS.md#parser-spellings)
- **A `<<\EOF` heredoc body is read as code by the session gates.** Only the backslash heredoc spelling is misread, drawing a close-gate verdict on a commit that merges nothing; since 2.6.0 that is a misleading advisory and never a hang. [Full text.](LIMITATIONS.md#heredoc-backslash)
- **A role directory spelled in a different case is not seen by the session scope gate on macOS or Windows.** On a case-insensitive filesystem a write to `SRC/` is the same file as `src/` and draws no advisory; the trunk audit refuses the commit at push, and the same holds for a symlinked leaf. [Full text.](LIMITATIONS.md#case-spelling)
- **Identity-by-commit governs an alias only while a spec or chore ref still points at that exact commit.** An alias of a spec branch stops drawing the session-layer warning once the spec branch advances or is deleted; both guarantee layers still refuse the merge. [Full text.](LIMITATIONS.md#alias-identity)
- **The wiring check recognises only the command spellings `settings.json.tmpl` ships.** A hand-rewritten hook entry that genuinely runs the stamped file is reported `NOT WIRED`; the check over-reports rather than certifying a disarmed instance. [Full text.](LIMITATIONS.md#wiring-spellings)
- **The forge check governs the merge button only where the trunk requires it.** The stamped check is a report until the trunk lists `setlist forge check` as required beside a review; it cannot require itself, and a rebase-merge trunk defeats it before the fact. [Full text.](LIMITATIONS.md#forge-check-required)
- **The forge check reads the trunk's protection as it stands, not as it stood.** Under `forge` custody the check verifies the protection NOW, so a trunk protected after an unreviewed flip landed verifies that flip. [Full text.](LIMITATIONS.md#forge-protection-now)
- **The CODEOWNERS bridge reads a subset of the file's grammar, and a pattern is a claim about paths.** `Owns:` declarations are judged against the core CODEOWNERS grammar; sections, negations and character classes are refused by name, and only email owners resolve locally. [Full text.](LIMITATIONS.md#codeowners-bridge)
- **The headless integrity chain is only as strong as where your signing key lives, and a key your build can reach is not custody.** A signature proves a key was used, not that a person decided; `forge` custody (2.6.0) has no key and rests on the forge's required review instead. [Full text.](LIMITATIONS.md#custody-key)
- **The close audit's single-parent arm is as strong as your declarations, and a declaration is a claim, not a verified fact.** A close is audited file by file against its own `Owns:` lines, which travel in the commit they justify; the hooks verify coverage, not truth, and a spec that declares nothing closes under the older whole-commit exemption. [Full text.](LIMITATIONS.md#declarations-claim)
- **The hashed range ends at the FIRST line reading `## Closing report`, fences included, and the ownership reader agrees with that cut.** A quoted copy of the template above your `Owns:` lines ends the signed range early and the declaration below it is refused as out of range; the refusal names the one-edit fix. [Full text.](LIMITATIONS.md#hashed-range-cut)
- **A session killed from outside fires no Stop, and the Stop hook is a nudge, never a lock.** The Stop hook refuses to end a turn with an unstaged spec or `specs/STATUS.md` change, once; a session killed from outside fires nothing, and the git hooks are what refuse the work. [Full text.](LIMITATIONS.md#stop-hook)
- **Merges crafted to evade the trunk audit can succeed, and the list of known routes is maintained rather than complete.** A chained merge and its octopus spelling hide unspecced work behind a compliant close; the checks that refused them broke `git pull` on a shared trunk and were removed, so the routes are documented, not defended. [Full text.](LIMITATIONS.md#crafted-merges)
- **Sideways routes to the trunk.** `git cherry-pick`, `git pull <remote> spec/...` and a detached-HEAD merge are not parsed by the close gate; for cooperating use the trunk audit catches each at push. [Full text.](LIMITATIONS.md#sideways-routes)
- **`git rebase` onto a spec branch brings that branch's commits to the trunk with no closing merge.** No merge, so no session verdict; the push is refused with a `VIOLATION` and the remote is untouched, unless composed with a compliant single-parent close that declares no ownership. [Full text.](LIMITATIONS.md#rebase-route)
- **`git reset --hard <spec-branch>` moves the trunk onto unclosed work outright.** Same silence at the session layer, same refusal at push, same qualification for a declaring close. [Full text.](LIMITATIONS.md#reset-route)
- **`git checkout <spec-branch> -- <path>` copies role-path files onto the trunk without any merge to read.** The pathspec checkout writes files straight into the working tree and the commit that follows is ordinary; refused at push, remote untouched, same qualification. [Full text.](LIMITATIONS.md#pathspec-checkout-route)
- **The trunk audit cannot tell a merge that EDITS a file from ordinary conflict resolution.** The audit reports files a merge introduced that no parent carries; a merge that edits a file a parent already had reads as conflict resolution and is not flagged. [Full text.](LIMITATIONS.md#evil-merge-edit)
- **The Bash escape hatch.** The scope hook watches the file-writing tools, so a write through Bash (`cat >`, `sed -i`) draws nothing, and a git command run through another interpreter is not one the gates can read; the trunk audit is the designed catch. [Full text.](LIMITATIONS.md#bash-escape)

### Open limitations (2)

- **Completing a refused merge on the trunk side, as the hook's own message prescribes, is accepted at commit and refused at push.** Following the refusal text's own remedy writes the record on the trunk side, which `pre-commit` accepts and the push-time audit refuses; nothing unsafe reaches the remote. [Full text.](LIMITATIONS.md#merge-completion)
- **The close gate refuses `@{u}` and other revision-suffix spellings of a merge operand.** `git merge @{u}` is refused as unresolvable by the session gate although its value is fixed configuration; the git hooks are unaffected. [Full text.](LIMITATIONS.md#revision-suffix)

### Upstream conditions (2)

- **The session gates' warnings do not reach the agent on current harnesses.** Claude Code drops a hook's reason when the decision is `allow`, and an advisory verdict always is, so the session gates are a machine-readable surface today and the git hooks' refusals are the feedback you see. [Full text.](LIMITATIONS.md#advisory-not-rendered)
- **A timed-out hook is a skipped gate.** Claude Code cancels a hook past its timeout and lets the tool call proceed; the stamped timeouts are 300 seconds since 2.6.0, and a gate command that fails only under the hook's non-interactive PATH is a false deny. [Full text.](LIMITATIONS.md#hook-timeout)

## Repository contents

| File | What it is |
|------|------------|
| [`setlist.md`](setlist.md) | **The current framework edition** (the version is stated inside the file). The single source of truth; read this to operate or adapt the method. |
| `.claude-plugin/`, `skills/`, `templates/`, `scripts/` | The plugin (`setlist`): the marketplace and plugin manifests, the seven `/setlist` command skills and four reference skills, the instance templates including the stamped hooks, and the scripts that stamp an instance, extract a Part, and refresh an existing instance's enforcement files. All of it is a binding of the edition document. |
| `test/`, `.github/` | The hook test suite and the workflow that runs it on Linux and macOS on every push, plus a second Linux run under GNU awk. Fixture repositories are built from scratch at run time; the suite depends on nothing beyond bash, git, `jq`, and coreutils. It runs sharded, as several processes with separate temporary directories, and the wrapper refuses rather than reports if any shard failed to claim its share of the work. |
| [`LIMITATIONS.md`](LIMITATIONS.md) | The Known-limitations list in full: every bullet the section above lists by title, with its claim, what to do, and the history and measurements behind it, folded. |
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

Field reports are the framework's fuel: every edition so far was distilled from real projects run end to end. If you adopt it, [open an issue](https://github.com/AlexCiortan/setlist/issues) with what held and what fought you; both are findings. A refusal you did not expect has its own form there ("A refusal I did not expect"): it asks for the platform, the git version, the exact message with its bracketed code, and the one command that drew it, which is what a reproduction needs.

## About the author

Built by [Mihai Alexandru (Alex) Ciortan](https://www.linkedin.com/in/alexciortan), Principal Architect with 15+ years of enterprise platform engineering at one of the world's largest game publishers, part-time CTO at DEIO, and previously part-time CIO at MyBenefits from proof-of-concept through its acquisition. The framework is distilled from running real software projects with Claude Code end to end, and this repository is itself maintained under the discipline it describes.

## License

© 2026 Alex Ciortan. Released under the [Creative Commons Attribution 4.0 International License](LICENSE) (CC BY 4.0): use, adapt, and share it, including commercially, as long as you give appropriate credit. Suggested attribution: "Setlist, a spec-driven development framework by Alex Ciortan, licensed under CC BY 4.0."
