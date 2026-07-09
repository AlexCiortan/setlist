#!/usr/bin/env bash
# SDD scope hook: PreToolUse on matcher "Write|Edit", stamped into the instance.
# Enforces Part 6: feature code never lands directly on the trunk branch
# (read from .claude/sdd.json, never assumed to be main).
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Requires jq. Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

INPUT=$(cat)
# Normalize to an absolute path so the prefix strip below works whether
# file_path arrives absolute or relative (hooks run with cwd = project dir).
PROJ="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)"
SDD_JSON="$PROJ/.claude/sdd.json"

# Not an SDD instance, or pre-stamp: stay silent.
[[ -f "$SDD_JSON" ]] || exit 0

# Active only after /scaffold flips the flag, so the one-time bootstrap
# scaffold on main is not blocked.
[[ "$(jq -r '.scaffolded // false' "$SDD_JSON")" == "true" ]] || exit 0

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
TRUNK="$(jq -r '.trunk // "main"' "$SDD_JSON")"
BRANCH="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
[[ "$BRANCH" == "$TRUNK" ]] || exit 0

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
[[ -n "$FILE_PATH" ]] || exit 0

# Role paths: a string or a list of strings (multi-prefix repos, and flat-root
# repos that enumerate their shippable files). A directory entry covers its
# subtree; a file entry covers exactly that file. "." is deliberately inert:
# covering the whole root would deny the docs-only trunk commits the loop
# depends on; a flat-root repo lists its real code paths instead.
ROLE_PATHS="$(jq -r '[.roles.src // "src", .roles.tests // "tests"] | flatten | .[]' "$SDD_JSON")"

# Strip the project prefix if present, then test against the role paths.
REL="${FILE_PATH#"$PROJ"/}"
while IFS= read -r ROLE; do
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  ROLE="${ROLE%/}"
  if [[ "$REL" == "$ROLE"/* || "$REL" == "$ROLE" ]]; then
    deny "feature code never lands directly on $TRUNK; open a spec or chore branch via /setlist:checkpoint."
  fi
done <<< "$ROLE_PATHS"
exit 0
