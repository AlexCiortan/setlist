---
name: new
description: Bootstrap a new project with the Spec-Driven Development Framework (Part 8)
disable-model-invocation: true
---

You are bootstrapping a new framework instance. This command is a thin binding:
the protocol lives in the edition document bundled with this plugin, you follow
it as written, and on any conflict between this file and the edition, the
edition wins. Never fork the protocol.

## 1. Guards and grounding

- Output contract for your FIRST message: it opens with the model expectation,
  before any question or observation. Session zero is architecture work: it
  runs on `opus`, the planning tier's model, and a complex project on the escalation tier
  of the model ladder (Part 2; `/model fable` under the current bindings, or
  `/model best` where the organization has no Fable access). It is not the day-to-day
  `opusplan` default. Say so; do not assume the user read the README, and do
  not let environment friction displace the line (a cold run has skipped it
  exactly that way). Continue either way.
- Right after the model line, the same first message states the contract
  (Part 8 Step 1), before any question. Say that this is an architecture
  session the user drives. Then three sentences: "I decide the stack, the
  core data model, the scope and every default I write down only with your
  approval." "I never decide boundaries, data ownership, the repository split
  or anything with a cost for you." "Ask me anything at the level you work
  at; I keep going until you stop me."
- Greenfield guard: if the current directory is not empty and not a git
  repository, stop and ask before touching anything. An existing codebase
  belongs to /setlist:retrofit instead.
- Observe mode (`/setlist:retrofit --observe`, the verdict delta of
  `/setlist:upgrade`) does not apply here: a new project has no history to
  read, and this interview's proposal of every decision before a file is
  written is its equivalent.
- Load the protocol you are bound to. Run:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8`
  and follow that text (the Bootstrap Protocol) for everything below.

## 2. Gather conversationally (before the interview)

Ask for, in plain conversation:

- The project paragraph: what it is, the core user job, the one-sentence pitch.
- Constraints: budget, solo vs team, time, legal/privacy, anything mandated.
  A team answer opens the team round in section 3.
- The working mode: the user writes code too, or reviews only.

## 3. The Part 8 interview and decisions, exactly as written

- Derive first when the idea is high-level (Part 8 Step 1). If you cannot
  name the deployables, the users and the core data from what the user told
  you, derive the decisions the idea leaves open before proposing anything.
  Ask them in order of consequence, three at a time. The stopping rule does
  not apply until the derivation is done. Each decision you derive is a
  question or a register line.
- Run Part 8 Step 1's rule: every decision the idea leaves open is a
  question or a stated default. Ask the questions in structured rounds with
  recommendations inline. The sizing picks the mode (Part 8 Step 1, the depth
  modes): ordinary for one deployable, deep for several, estate for a system
  that already runs as several repositories; say which, and what it will ask.
  In the ordinary mode the stopping rule bounds the rounds (one is right, two
  is fine, three is procrastination). In deep and estate it is per round: a
  round ends when its decisions are written or the user says enough, never
  when you run out of defaults. One round per topic is right, two on a hard
  one are fine, and a third on the same topic is procrastination. Never force
  deep on one deployable. Write every default as a register
  line, `A-07 | decision | default taken | why | the question that would
  change it`, and show the lines as you go, all five fields in the chat
  exactly as they will stand on disk. Use one id series: `A-nn` for every
  register line, and the same id when a line is carried into Open
  questions; keep question and round labels out of the written register. The user answers each inline:
  keep, change, or ask me later. A line left for later reads "ask me later"
  as its default and "not set" as its why, in the chat as on disk. Never
  assume a default without its line.
  The first round OPENS with
  "what has changed since this framework edition was written" (tooling,
  models, workflow), Part 8's mandated first question, never its last. The
  sizing comes second (Part 8 Step 1): one deployable, several with their own
  pipelines, or an existing estate; who else builds here; what already
  exists. Write the answers as the sizing line in `steering/product.md`. Include
  the environment facts Step 1 demands: the opusplan check below, the QA
  tooling for this project type, the design surface question for UI projects,
  and the riskiest assumption worth a spike. The design surface question
  names Claude Code's `/design` (Part 5c) and what yes commits the instance
  to. Each design intake is an interactive `/design` session. Each locked
  redline and its artboard exports are committed under `docs/design/` before
  the spec that builds to it goes ACTIVE. Design QA reads the committed
  redline. `/design` needs a claude.ai sign-in with the Design template on;
  without it, yes still holds and mocks made another way are committed.
- Verify `opusplan` by LIVE PROBE before parking: run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/model-probe.sh"` (say first that it
  spends two short headless sessions of the user's quota) and keep its two
  `served planning <id>` and `served execution <id>` lines for the answers
  file. They record the model each phase served, which `/setlist:validate`
  compares with a later run. Only if the probe cannot run or names no model:
  leave both answers empty, which leaves the model line out of settings.json,
  and park verification in STATUS.md with a named owner. Never park without
  attempting the probe.
- Verify `jq` in the same environment check (`command -v jq`). The stamp
  refuses before it writes anything when `jq` is missing or not working (it
  builds `.claude/sdd.json` with `jq`, and the three stamped GIT hooks fail
  closed without it; the session hooks report, or stay silent, and do not block), so
  check first rather than meet the refusal; a clean container is the common
  case, since jq is not in most default installs. Report the install command
  and let the user run it; install nothing yourself.
- Ask the `diagram_command` question in the same round, DEFAULT NONE. "Is there
  a command that prints this project's structure as one Mermaid block (an import
  graph, a schema dump)?" A yes records it in `.claude/sdd.json` beside
  `gate_command`, and its committed output under `docs/diagrams/generated/` is
  then required to equal what it prints at every close. A no records nothing,
  which is the right default: the framework ships no extractor, and a declared
  command that does not run refuses the close rather than degrading.
- Ask the pipelines question in the round: which deployables, and for each
  its pipeline, its release cadence and its team. Then propose the
  repository split as a Step 2 decision: one repository per deployable that
  needs its own pipeline, cadence or team, one repository where they share
  all three. Name the trade (each repository is its own instance, and a
  change across them is a spec in each) and record the choice with its
  reason in `steering/product.md`. This instance is one of those
  repositories.
- For a team, ask the team round (Part 8 Step 1): who else builds here and
  how many at once; whether the trunk is protected and by what; who approves
  a spec; who may flip it ACTIVE; what happens to a claim nobody touches for
  N days. The answers write a Team section in `steering/product.md`. Who may
  flip ACTIVE feeds the attestation question, which stays OFF by default and
  is never turned on by this round alone. The CODEOWNERS owner question and
  the headless-build question stay where they are.
- In estate mode, first read the repositories this one joins, read-only, as
  Part 8b Step 1 says: ask for each one's path or URL, read its layout,
  languages, pipeline files and visible crossings, and show what you found.
- In deep and estate mode, run the six deep rounds after the round above, in
  Part 8 Step 1's order and words. Each takes one topic and ends with what was
  decided and what stays open. Boundaries and ownership asks, where the system
  has end users, how they sign in and which component owns their identity, and writes
  `structure.md`. Contracts between components gives every crossing a
  contract or an open question and proposes a `contracts/` location, never
  creating it (`structure.md`). A crossing between two other repositories is
  an open question by id, owned by the session of the repository that
  publishes its contract. Data asks consistency per user flow
  (`state.md`). Pipelines and deployment writes `RUNBOOK.md` and `tech.md` and
  names each repository's full-suite command for `/scaffold`. Failure modes
  per crossing and the riskiest integration scope spike 0000
  (`structure.md`). Observability and operations comes last (`tech.md`'s
  Operations section).
- Run Step 2 foundational decisions WITH the user at full depth. This is the
  product of the whole session; do not compress it. The core data model gets
  the most effort.

## 4. Phase 1: the mechanical stamp

Write the answers file to `.claude/stamp-answers.txt` in the project directory,
one NAME=VALUE pair per line:

```
project_name=<name>
stack=<short stack id>
working_mode=<review-only | developer-writes>
ui=<yes|no>
planning_model=<the id on the probe's "served planning" line, or empty>
execution_model=<the id on the probe's "served execution" line, or empty>
design_surface=<yes|no>
src_role=<src, or the agreed path>
tests_role=<tests, or the agreed path>
sizing=<ordinary | deep | estate, the mode the sizing selected>
system_spec=<a system of repositories only: the system spec's path from this repository, or its URL>
mode=new
```

The stamp does not read `sizing`; it records the session's depth beside the
other answers. It records `system_spec` in `.claude/sdd.json` and reads it
back; leave the line out for a system of one repository.

Then run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh" .claude/stamp-answers.txt .`

When the team round set a stale-claim rule, add `"stale_days": <N>` to
`.claude/sdd.json` after the stamp. Absent, the instance behaves as before.

The stamp emits every framework-fixed file, including the four session hooks
(enabled; each documents its one-line disable in its header), the git hooks,
the trunk audit and the forge check beside it, `.github/workflows/
setlist-forge-check.yml` (the check as a required status check, `setlist forge
check`) and `.github/CODEOWNERS` (the four protected paths under an `@OWNER`
slot that phase 2 fills with the owner the human names for the enforcement
layer, a team or a handle, asked in the interview and never inferred from the
plugin's own metadata or its author; with no answer the slot stands, and a
standing slot is a validate finding), the `gates` block in `sdd.json` (three
empty tiers `/scaffold` records beside `gate_command`), `specs/TEMPLATE.md`
extracted from the edition, the committed edition copy, the `verify` skill
(Claude Code asks for it before a commit; it runs `gate_command` and reports,
and refuses nothing), and `AGENTS.md` beside
`CLAUDE.md` (a pointer to it and to the edition for agents that read
`AGENTS.md`, never a second copy of the golden rules). Do not regenerate
any stamped file by hand. Requiring the check on the trunk is the user's act at
their forge; name it in the hand-off rather than assuming it.

### A system of repositories: walk the bootstrap plan

Part 8 Step 3 defines the plan. Write
`system.md` first, with its `## Bootstrap plan`: one numbered step per
repository, each with its directory, role paths, gate command and
`system_spec`. The system repository is not stamped as an instance unless the
user asks for it; say so where its role paths would otherwise be proposed. A
default you take while writing is still a register line: show it with its id
and its question, and get the answer, before you write it. Check each contract
file you wrote against its own format (an OpenAPI linter, a JSON Schema
validator, at the least a parse) and fix what fails before the first stamp.
Then, step by step:
write that repository's answers file, run the stamp with that directory as the
target and print its exit code on a line of its own (`bash ... stamp.sh
<answers> <dir>; echo "stamp exit $?"`), write its phase 2 (section 5)
and its spec 0001 with the `Cites:` line, and report one progress line
(`plan step 2 of 3, api: stamped (exit 0), phase 2 written, spec 0001 cites
../shop-system/system.md`). A stamp exit other than 0, or a step you cannot
write, stops the plan there: name the step and the stamp's message, list the
steps left, and wait for the user. Mark each step done in `system.md` as it
lands, the system repository's own commit included.

## 5. Phase 2: tailored generation (the 20 percent that is the product)

Write only what encodes the decisions just made with the user: the steering
docs' content, the founding ADRs (entry plus index row, typically five), the
first specs per Part 8 Step 4 (spike 0000 if warranted, 0001 to 0003, later
ones as DRAFT or parking-lot rows; where the target already has a trunk or a
remote, number from `bash "${CLAUDE_PLUGIN_ROOT}/scripts/board.sh" --next`,
Part 3's numbering, edition v1.22), `RUNBOOK.md` as Part 7 instantiated with
this stack's exact commands, and every `[PHASE 2 SLOT: ...]` marker the stamp
left behind. No slot marker survives this phase. The register lands here too:
an **Assumptions** section in `steering/product.md` and in `steering/tech.md`,
each line with the user's answer, and every "ask me later" line by id under an
`## Open questions` heading in spec 0001 and in STATUS.md's open questions.
In deep and estate mode the deep rounds' answers land in the documents each
round names, and every crossing left open is one of those open questions.
Where the repository split named two or more repositories, write the system
spec first (Part 4): `system.md` in the system repository, with the bootstrap
plan (section 4), `contracts/` and the system's founding ADRs. Then each
repository's phase 2 follows in the plan's order, and its spec 0001 carries a
`Cites:` line naming `system.md`.

Seed `docs/diagrams/` here, in phase 2, and never in the stamp. Create the
directory and write two files from the decisions just made: `context.md` at L1
(the system, its users and the outside services it talks to) and the L2
container block at the bottom of `steering/structure.md` beside the core model.
Both under the `diagrams` skill's rules, each opening with the four-line header
from `${CLAUDE_PLUGIN_ROOT}/templates/root/DIAGRAM-HEADER.md` and
`Synced by: bootstrap`. Node names are the role paths the answers file recorded,
so they resolve against the tree from the first close.

Say plainly what creating the directory does, because it is a decision and not a
formality: its presence ARMS the close's diagram checks, so from the first spec
onward a close that says `updated` names its files and one that says
`no impact` while a diagram moved is refused. That is the intended state for a
project born under this edition. A user who wants to start without it deletes
the directory, and every reader behaves as it did before the diagram half
existed.

## 6. Hand off

Per Part 8 Step 5: point the user at RUNBOOK.md, name the next action in
specs/STATUS.md (normally `/scaffold`, then the spike or spec 0001), and note
that day-to-day Git runs through /setlist:checkpoint.

Warn explicitly in the handoff text: nothing is committed yet. Session zero
leaves the instance as uncommitted files by design (the first commit belongs
to /scaffold, which also runs git init when no repo exists), so until
/scaffold runs, one stray deletion loses the whole session. Run /scaffold
next, before anything else.

## Gotchas (field-observed)

- Do not improvise vocabularies the templates already fix. A generated
  DECISIONS.md index once carried the status "Accepted" where Part 4's legend
  is ACTIVE / SUPERSEDED-by-NNN / INFERRED; the template header states the
  legend, use exactly those words.
- Non-interactive bootstraps (`claude -p`) under default permissions cannot
  read the plugin root (`part.sh` lives outside the project directory), and
  the run stalls on an approval that never comes. The permission stance is
  the operator's, set outside the plugin (Part 7c): say what stalled and
  stop, never choose or suggest a mode that turns prompts off.
