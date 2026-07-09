#!/usr/bin/env bash
# SDD re-grounding hook: SessionStart (no matcher: startup, resume, and
# post-compaction restarts alike), stamped into the instance. Delivers the
# read-budget pointer (edition Part 2) by mechanism: read specs/STATUS.md,
# then the active spec. Pointer, never content: inlining STATUS.md would
# bloat every session start and hand the session a copy that rots.
# Injection mechanic verified live 2026-07-07 on Claude Code 2.1.203:
# additionalContext JSON on stdout reaches the model verbatim, including
# under claude -p, with observed sources startup, resume, and compact.
# Requires jq. Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

INPUT=$(cat)
PROJ="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)"

# Not an SDD instance, or pre-stamp: stay silent.
[[ -f "$PROJ/.claude/sdd.json" ]] || exit 0
# Bootstrap phase 1 may run before STATUS.md exists; nothing to point at yet.
[[ -f "$PROJ/specs/STATUS.md" ]] || exit 0

SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || printf 'startup')"

case "$SOURCE" in
  compact)
    MSG="SDD re-grounding (post-compaction, framework Part 2): the context was just summarized, and a summary of the spec is not the spec. Re-read specs/STATUS.md and the ACTIVE spec it names before continuing."
    ;;
  resume)
    MSG="SDD re-grounding (resumed session, framework Part 2): re-read specs/STATUS.md and the active spec it names before continuing; the repo may have moved since this conversation last ran."
    ;;
  *)
    MSG="SDD re-grounding (the read budget, framework Part 2): before anything else, read specs/STATUS.md, then the active spec it names. Load owner docs only as the spec's header directs; everything else is reference material."
    ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$MSG" | jq -Rs .)"
exit 0
