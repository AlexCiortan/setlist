---
name: upgrade
description: Upgrade a framework instance to the edition bundled in this plugin (Part 8c)
disable-model-invocation: true
---

You are upgrading a repo that already runs an earlier edition of the framework.
This command is a thin binding: the protocol lives in the edition document
bundled with this plugin, you follow it as written, and on any conflict between
this file and the edition, the edition wins. Never fork the protocol.

Load the protocol first. Run:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8c`
and follow that text (the Upgrade Protocol) for everything below. An upgrade is
a planning-and-documentation act: reading src is permitted, editing it is not.

## 1. Establish old and new

- The OLD edition is the framework markdown committed in this repo:
  `setlist.md` (a pre-cutover instance carries it under the edition's
  original filename instead; still exactly one framework markdown at the
  root). Read its version from inside the file (the Edition header line, or the
  Version line in older editions); do not ask the user for it.
- The NEW edition is the one bundled at the plugin root:
  `"${CLAUDE_PLUGIN_ROOT}"/setlist.md`, its version on its Edition header
  line. Its Changelog section is the authoritative delta list.
- Ask conversationally: how was the old edition adopted (a chore number, or
  the original bootstrap/retrofit), and which ADR records it, if any.
- **When the editions match but the plugin has moved** (a plugin patch that
  changed stamped files, the first being 1.0.1's fail-closed hooks), this is
  not a full migration. Run the enforcement-file refresh in section 3 and
  nothing else: hooks are byte-copied into the instance at stamp time, so a
  plugin release fixes new instances only and an existing one keeps its old
  hook bytes until this refresh runs. Close it as an ordinary docs-only chore
  with a one-line ADR naming the plugin version, not an umbrella migration
  ADR. Compare the hook bytes rather than the version numbers: the plugin
  version is not recorded in the instance, so the diff is the evidence.

## 2. Run Part 8c as written

All mechanics come from the loaded Part: prefer the window between specs, or
pause the ACTIVE spec cleanly with a resume prompt; diff the repo's framework
files against the new edition and list every gap; one structured round for
genuine forks only; execute on a single chore branch (`chore/vNN-migration`);
relocate verbatim under provenance banners, never rewrite; style rules
forward-only; one umbrella ADR with its index row; replace the committed
framework markdown with the new edition in the same commit (as of the setlist
cutover the committed copy is always named `setlist.md`, so an edition file
carrying an older name is git-renamed to `setlist.md` in that commit);
record accepted
deviations; close like any chore with docs-only gates.

## 3. Plugin-era migration (part of the same chore)

When the instance predates the setlist cutover (it carries `/sdd-framework:` or
`/sdd:` command references), rewrite every one of them to `/setlist:` in
RUNBOOK.md, CLAUDE.md, .gitignore comments, and instance-owned skills, and
record the rewrite in the umbrella ADR.

When the instance predates this plugin, also:

- Remove the generated per-project checkpoint skill
  (`.claude/skills/checkpoint/`) and rewrite every RUNBOOK.md and CLAUDE.md
  reference from `/checkpoint` to `/setlist:checkpoint`.
- Remove the generated per-project validate skill (`.claude/skills/validate/`),
  the same promotion one edition later: the health check ships as
  `/setlist:validate`. Domain adaptations the instance added to its copy
  (extra checks, stack-specific notes) are relocated FIRST into an
  instance-owned skill under the instance's own name, then the directory is
  removed; rewrite `/validate` references to `/setlist:validate`
  (RUNBOOK.md, CLAUDE.md, .gitignore comments).
- Stamp or refresh the enforcement files: copy the four stamped hooks from
  `${CLAUDE_PLUGIN_ROOT}/templates/hooks/` (scope-hook, commit-gate,
  close-gate, regrounding-hook) into `.claude/hooks/` byte for byte,
  REPLACING any older copies whose bytes differ (the hooks are plugin-owned
  and never hand-edited; an upgrade is exactly how an instance receives hook
  fixes). If a copy shows hand edits, show the diff and name the fork in the
  umbrella ADR before replacing (Part 8c: a customized stamped copy is a fork
  to surface, never a file to silently overwrite). Wire them in
  `.claude/settings.json` exactly as
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/settings.json.tmpl` shows (scope
  hook on Write|Edit and commit gate and close gate on Bash, both PreToolUse;
  regrounding hook on SessionStart, no matcher). The same template also shows
  the `fallbackModel` chain (`["default"]`, v1.6); add the line when the
  instance's settings.json lacks it. Create
  `.claude/sdd.json` from its template if missing, with this repo's real src
  and tests role paths, the full-suite gate_command, and scaffolded=true (the
  project exists; the gates should bind now). Whether created or already
  present, sdd.json must carry the `trunk` field: detect the trunk branch
  name (`git symbolic-ref refs/remotes/origin/HEAD`, else the current trunk
  branch in use, else main) and record it; the scope and close hooks read it
  instead of assuming main. Note that hooks load at session start, so the
  gates bind from the NEXT session onward.
- Refresh `specs/TEMPLATE.md` from the new edition:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" appendix-c` (the template body
  inside the fences). Existing specs are historical text and are not
  retrofitted. **Refresh applies to unmodified stamped copies only** (Part
  8c): a template the instance deliberately domain-adapted is a fork to
  surface, kept as is and recorded under the umbrella ADR's accepted
  deviations, with the new edition's delta folded in by hand where it matters.
- Stamp the qa-verifier agent if missing: copy
  `${CLAUDE_PLUGIN_ROOT}/templates/claude/agents/qa-verifier.md` to
  `.claude/agents/qa-verifier.md` (the stamp gives every new instance this
  agent; an upgraded instance gets the same). If a hand-edited copy exists,
  surface the diff instead of overwriting.
- Record all of this inside the umbrella ADR.

## 4. Instance skill flags (any instance stamped before plugin 1.6)

The generated skills (`.claude/skills/scaffold`, and `browser-qa` where
present) are instance-owned; the upgrade never rewrites their bodies.
Their frontmatter must still carry the manual-invocation flag Part 6 demands
("Mark them manual-invocation"): ensure each SKILL.md has
`disable-model-invocation: true`, adding the line when missing, and record the
touch-up in the umbrella ADR with the rest.

## Gotchas (field-observed)

- "Already byte-identical" and "already current" are claims, not facts: verify
  them with a checksum or a diff against the plugin's template before leaving
  a file alone. Sessions have misreported enforcement events elsewhere; the
  upgrades whose claims held were the ones that checked.
