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
  keep treating an absent block as "stamped before that block existed".

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
| `docs-design/INDEX.md` | `docs/design/INDEX.md` | design_surface = yes |

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
