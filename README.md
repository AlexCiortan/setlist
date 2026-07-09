# Setlist

[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757)](https://code.claude.com/docs/en/discover-plugins)
[![Plugin version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FAlexCiortan%2Fsetlist%2Fmain%2F.claude-plugin%2Fplugin.json&query=%24.version&label=plugin&color=blue)](https://github.com/AlexCiortan/setlist/blob/main/.claude-plugin/plugin.json)
[![License: CC BY 4.0](https://img.shields.io/badge/license-CC%20BY%204.0-lightgrey)](LICENSE)

**Setlist** is spec-driven development for Claude Code: build real software by **directing rather than typing**. You act as architect and reviewer, the agent writes the code, and a spec (not the keyboard) is your control surface.

![A real /setlist:new session zero, recorded live at 2.5x: the interview's decision forks, the two-phase stamp, the framework's own health check, and /scaffold making the first commit with gates green](demo.gif)

Setlist ships as an installable Claude Code plugin (`setlist`): seven slash commands (`new`, `retrofit`, `upgrade`, `checkpoint`, `validate`, `gate`, `journal`), four reference skills, and four mechanical hooks (three enforcement gates plus session re-grounding) stamped into every project it generates. The current edition of the framework document is **[setlist.md](setlist.md)** (edition v1.6; the version lives inside the file); you do not need to read it to start. The plugin version and the edition version are separate counters: the plugin counts releases of the tooling, the edition counts revisions of the document.

## Why Setlist

AI coding agents are powerful but drift: across a long project they lose context, wander from past decisions, and quietly expand scope. When you review instead of type, every ambiguity the agent resolves on its own ships unless you catch it later. Setlist's answer:

- **Specs are the contract.** Work proceeds one small spec at a time, each with exhaustive acceptance criteria.
- **Scope discipline is sacred.** An explicit, enforced out-of-scope list is the primary defense against ballooning.
- **Review is the gate, tests are the aid.** Your review is the quality bar; tests are written to be read as a specification of behavior.
- **Enforcement is mechanical, not aspirational.** Most agent methodologies are prompts that hold until the model forgets them. Setlist stamps four hooks into every project it generates: feature code cannot land on the trunk, commits are scanned for secrets and style violations before they exist, no spec merges without a complete closing report and a green test suite, and every session starts re-grounded from the repo. The rules survive long sessions, context compaction, and model swaps, because they do not live in the context window.
- **The repository is the memory.** Every durable decision lands in a version-controlled file: an ADR (architecture decision record) log with an index, a bounded status file, per-session journals, a living architecture diagram that is gate-checked at every merge. Any session, on any model, re-grounds by reading the repo. Chats are disposable; the repo persists.
- **Role separation is a native mechanism.** A *Planner* (thinks, decides, writes specs) and a *Builder* (writes code, runs tests, does Git), never blurred: the two map directly onto Claude Code's `opusplan` model setting, and the boundary is held by the same stamped hooks, not by hoping the agent remembers which hat it wears.
- **Every release is dogfooded cold.** No edition publishes without passing a real end-to-end gate ("Does it actually work?", below). The run artifacts drive the next edition; the framework is maintained under its own discipline.
- **Claude Code-native depth over multi-tool breadth.** Setlist binds the harness's real capabilities (plan mode, hooks, skills, session-start injection, plugin distribution) instead of targeting a lowest common denominator. When the harness grows a mechanism that replaces discipline, the framework absorbs it; that is how the hooks and the re-grounding injection came to exist.

## Quickstart

Install the plugin once, from inside Claude Code:

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
5. **Hand-off.** Nothing is committed yet by design: run `/scaffold` next. It is not a plugin command, which is why the table below does not list it: it is a project-local skill the bootstrap just generated into your repo. It wires the test harness, records your full-suite gate command, makes the first commit, and arms the enforcement hooks.

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

## Does it actually work?

Every release passes a **dogfood gate**: a fresh agent with zero prior context is given only this repository and its README, and must take a small real application from empty directory to a merged, twice-QA-passed feature with the discipline holding at every step. Recent gate runs built a Go CLI, a Python CLI, and a Node.js CLI end to end, each cold from the installed plugin. The enforcement hooks are additionally **hostile-tested**: real subprocess sessions actively try to commit em-dashes and secret-shaped strings, merge specs with incomplete closing reports, and write feature code on the trunk, and the run only passes when every attack is denied by mechanism with the specific failure named.

The QA discipline you can expect, from those runs' closing report format:

```
QA Pass 1 (automated, per acceptance criterion): PASS / PARTIAL / FAIL, one line each,
pasted verbatim into the spec. Anything the automated run cannot exercise is an honest
PARTIAL with the reason, never a claimed PASS.
QA Pass 2 (you): use the feature yourself; spot-check at least one criterion marked PASS.
```

## Repository contents

| File | What it is |
|------|------------|
| [`setlist.md`](setlist.md) | **The current framework edition** (the version is stated inside the file). The single source of truth; read this to operate or adapt the method. |
| `.claude-plugin/`, `skills/`, `templates/`, `scripts/` | The plugin (`setlist`): the marketplace and plugin manifests, the seven `/setlist` command skills and four reference skills, the instance templates including the stamped hooks, and the stamp and Part-extraction scripts. All of it is a binding of the edition document. |
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
