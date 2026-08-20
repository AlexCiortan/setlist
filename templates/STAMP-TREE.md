# templates/: the phase-1 stamp tree

This directory is the input to `scripts/stamp.sh`, the mechanical half of the
two-phase bootstrap: files whose content is fixed by the framework are stamped
with zero model tokens; files that encode project decisions are written by the
model in phase 2. This file is the contract `stamp.sh` implements; it is
documentation, never copied into instances.

## Conventions

- **`.tmpl` suffix = placeholder substitution.** Only files named `*.tmpl` are
  templated; the suffix is stripped at stamp time. Every other file is copied
  byte-verbatim. In particular `hooks/` contains no `.tmpl` files and is never
  templated (the commit gate builds its em-dash pattern from an escape sequence
  that must survive untouched).
- **Placeholders**, filled from the answers file the command writes:
  `{{PROJECT_NAME}}`, `{{STACK}}`, `{{WORKING_MODE}}`, `{{SRC_ROLE}}`,
  `{{TESTS_ROLE}}`, `{{STAMP_DATE}}`, `{{EDITION_FILE}}`. Two exceptions are
  never asked and always detected: `{{TRUNK}}`, the trunk branch name resolved
  from the target repo at stamp time (origin/HEAD, else the current branch,
  else main), which the scope and close hooks read from `.claude/sdd.json`;
  and `{{PLUGIN_VERSION}}`, the stamping plugin's version read live from this
  tree's own manifest by `scripts/plugin-version.sh`. An undeterminable plugin
  version aborts the stamp rather than producing an instance that records
  none, because `scripts/refresh-instance.sh` trusts the recorded value when
  it decides whether a refresh moves forward or backward.
- **Conditional lines**: a line starting with `{{IF:OPUSPLAN}}` is kept (marker
  stripped) when the interview verified `opusplan` resolves, dropped otherwise.
- **Phase-2 slots** are marked `[PHASE 2 SLOT: ...]` in stamped files; tailored
  generation replaces every one of them, and `/setlist:validate`
  reports any that remain.
- **`sdd.json` shape.** Facts about the repo itself stay flat (`trunk`,
  `gate_command`, `scaffolded`, and the `roles` map the scope hook reads);
  facts the framework records about its own machinery are nested blocks that
  sit after them, `plugin` being the first. New framework blocks append rather
  than reorder, so an instance's file grows by addition and every reader can
  keep treating an absent block as "stamped before that block existed". The
  `release` block (edition v1.7) is the second such block and follows the rule:
  it appends after `plugin`, it carries only the model plus its marker fact, and
  every reader treats an absent block as `{"model": "none"}` and says so rather
  than inferring a model for an instance that never declared one.

## The mapping

| Template | Stamps to | Condition |
|---|---|---|
| `root/CLAUDE.md.tmpl` | `CLAUDE.md` | always |
| `root/README.md.tmpl` | `README.md` | always |
| `root/ROADMAP.md.tmpl` | `ROADMAP.md` | always |
| `root/DECISIONS.md.tmpl` | `DECISIONS.md` | always |
| `root/gitignore` | `.gitignore` | always |
| `root/env.example` | `.env.example` | always |
| `specs/STATUS.md.tmpl` | `specs/STATUS.md` | always |
| `claude/settings.json.tmpl` | `.claude/settings.json` | always (model line only when opusplan verified) |
| `claude/sdd.json.tmpl` | `.claude/sdd.json` | always |
| `claude/agents/qa-verifier.md` | `.claude/agents/qa-verifier.md` | always |
| `claude/skills/scaffold/SKILL.md.tmpl` | `.claude/skills/scaffold/SKILL.md` | new projects (retrofits get no generated skill; the health check ships as `/setlist:validate`) |
| `claude/skills/browser-qa/SKILL.md` | `.claude/skills/browser-qa/SKILL.md` | ui = yes |
| `hooks/scope-hook.sh` | `.claude/hooks/scope-hook.sh` | always, byte-verbatim |
| `hooks/commit-gate.sh` | `.claude/hooks/commit-gate.sh` | always, byte-verbatim |
| `hooks/close-gate.sh` | `.claude/hooks/close-gate.sh` | always, byte-verbatim |
| `hooks/regrounding-hook.sh` | `.claude/hooks/regrounding-hook.sh` | always, byte-verbatim |
| `git-hooks/pre-commit` | `.githooks/pre-commit` | always, byte-verbatim |
| `git-hooks/pre-merge-commit` | `.githooks/pre-merge-commit` | always, byte-verbatim |
| `git-hooks/pre-push` | `.githooks/pre-push` | always, byte-verbatim |
| `git-hooks/setlist-hook-lib.sh` | `.githooks/setlist-hook-lib.sh` | always, byte-verbatim |
| `docs-design/INDEX.md` | `docs/design/INDEX.md` | design_surface = yes |

## Git config stamp.sh sets (edition v1.7, the enforcement boundary)

Two settings, written to the target's `.git/config`, both required for the git
hooks to be a boundary rather than a suggestion:

- `core.hooksPath = .githooks`, so git runs the TRACKED hooks above rather than
  `.git/hooks`, which is not cloned.
- `merge.ff = false`, because a fast-forward merge fires **no git hook at all**.
  Measured 2026-08-01: without it, 11 of 60 oracle cases walked unreviewed work
  onto the trunk on the fast-forward path alone, past an otherwise airtight
  boundary. The framework already merges spec branches with `--no-ff`, so this
  makes the config agree with the protocol. The cost, named because git's own
  error does not name it: the setting implies `--no-ff`, which git refuses in
  combination with `--squash`, so `git merge --squash` is fatal in every stamped
  instance. Use `git merge --ff --squash`, which `pre-commit` still gates.

Both are per-clone, because `.git/config` is not cloned. `core.hooksPath` into a
tracked directory NARROWS the per-clone gap (the hooks themselves are versioned
and reviewable) rather than closing it, and the edition's Known limitations says
exactly that rather than implying the hole is gone.

`stamp.sh` also verifies the three git hooks are executable and DIES if any is
not, because git skips a non-executable hook silently, which is a boundary that
stops nothing and reports nothing.

## Created by stamp.sh without a template

- `specs/TEMPLATE.md`: Appendix C extracted from the bundled edition at stamp
  time via `scripts/part.sh appendix-c` (the fenced template body, unfenced).
  Never a maintained second copy.
- The edition file itself, copied from the plugin root into the instance root
  (the audit-trail rule, Part 8 Step 3).
- The empty role directories: `steering/`, `journal/`, plus the src and tests
  role paths from the answers file, each holding a `.gitkeep`.

## Not stamped (phase 2, the model with the human)

Steering doc content, the founding ADRs, the first specs, `RUNBOOK.md`, and the
tailored slots above. Phase 1 never writes a file that encodes a Step 2
decision.
