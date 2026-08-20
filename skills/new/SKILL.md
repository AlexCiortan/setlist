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
  before any question or observation. Session zero is architecture work and
  should run on the escalation tier of the model ladder (Part 2; `/model opus`
  under the current bindings), not `opusplan`. Say so; do not assume the user
  read the README, and do not let environment friction displace the line (a
  cold run has skipped it exactly that way). Continue either way.
- Greenfield guard: if the current directory is not empty and not a git
  repository, stop and ask before touching anything. An existing codebase
  belongs to /setlist:retrofit instead.
- Load the protocol you are bound to. Run:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8`
  and follow that text (the Bootstrap Protocol) for everything below.

## 2. Gather conversationally (before the interview)

Ask for, in plain conversation:

- The project paragraph: what it is, the core user job, the one-sentence pitch.
- Constraints: budget, solo vs team, time, legal/privacy, anything mandated.
- The working mode: the user writes code too, or reviews only.

## 3. The Part 8 interview and decisions, exactly as written

- Run Part 8 Step 1 as one structured round: only genuine forks become
  questions, recommendations stated inline, and the stopping rule holds (one
  round is right, two is fine, three is procrastination). The round OPENS with
  "what has changed since this framework edition was written" (tooling,
  models, workflow), Part 8's mandated first question, never its last. Include
  the environment facts Step 1 demands: the opusplan check below, the QA
  tooling for this project type, the design surface question for UI projects,
  and the riskiest assumption worth a spike.
- Verify `opusplan` by LIVE PROBE before parking, the same probe the prompt
  path runs: attempt the selection once from this environment (a one-shot
  `claude -p --model opusplan` invocation that returns any clean reply
  verifies it resolves; in an interactive session, `/model opusplan` and read
  the response). Only if the probe cannot run or fails: leave the model line
  out of settings.json and park verification in STATUS.md with a named owner.
  Never park without attempting the probe.
- Verify `jq` in the same environment check (`command -v jq`). The three
  stamped GIT hooks fail closed without it (the three session gates are advisory and permit), so an instance stamped on a machine
  that lacks it will deny its own first writes; a clean container is the
  common case, since jq is not in most default installs. Report the install
  command and let the user run it; install nothing yourself.
- Run Step 2 foundational decisions WITH the user at full depth. This is the
  product of the whole session; do not compress it. The core data model gets
  the most effort.

## 4. Phase 1: the mechanical stamp

Write the answers file to `.claude/stamp-answers.txt` in the project directory,
KEY=VALUE lines:

```
project_name=<name>
stack=<short stack id>
working_mode=<review-only | developer-writes>
ui=<yes|no>
opusplan_verified=<yes|no>
design_surface=<yes|no>
src_role=<src, or the agreed path>
tests_role=<tests, or the agreed path>
mode=new
```

Then run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh" .claude/stamp-answers.txt .`

The stamp emits every framework-fixed file, including the gate hooks (enabled;
each documents its one-line disable in its header), `specs/TEMPLATE.md`
extracted from the edition, and the committed edition copy. Do not regenerate
any stamped file by hand.

## 5. Phase 2: tailored generation (the 20 percent that is the product)

Write only what encodes the decisions just made with the user: the steering
docs' content, the founding ADRs (entry plus index row, typically five), the
first specs per Part 8 Step 4 (spike 0000 if warranted, 0001 to 0003, later
ones as DRAFT or parking-lot rows), `RUNBOOK.md` as Part 7 instantiated with
this stack's exact commands, and every `[PHASE 2 SLOT: ...]` marker the stamp
left behind. No slot marker survives this phase.

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
  the run stalls on an approval that never comes. Part 7c names the
  non-interactive stance; expect the operator to relaunch with it.
