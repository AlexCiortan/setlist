#!/usr/bin/env bash
# SDD scope hook: PreToolUse on matcher "Write|Edit", stamped into the instance.
# Enforces Part 6: feature code never lands directly on the trunk branch
# (read from .claude/sdd.json, never assumed to be main).
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make the
# scaffolded flag, the trunk name, and the role paths all read empty, so every
# check fell through and feature code could land on the trunk unchallenged.
# Because none of those facts are readable without jq, the fail-closed path
# denies every Write and Edit inside a stamped instance rather than guessing;
# Bash is untouched, so the session can install jq and continue.
# Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

# Deny with a fixed literal reason, for the paths where jq is unavailable to
# escape one. The text must contain no double quotes, backslashes, or newlines.
deny_literal() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

INPUT=$(cat)
# Normalize to an absolute path so the prefix strip below works whether
# file_path arrives absolute or relative (hooks run with cwd = project dir).
# Both the given and the resolved forms are kept: they differ whenever the
# project root is reached through a symlink or a path with a trailing slash,
# and the strip below has to survive either.
PROJ_GIVEN="${CLAUDE_PROJECT_DIR:-.}"
PROJ_GIVEN="${PROJ_GIVEN%/}"
PROJ="$(cd "$PROJ_GIVEN" && pwd)"
SDD_JSON="$PROJ/.claude/sdd.json"

# Not an SDD instance, or pre-stamp: stay silent.
[[ -f "$SDD_JSON" ]] || exit 0

# Fail closed when jq is absent: sdd.json is unreadable, so the branch rule
# cannot be evaluated at all. Scoped to stamped instances by the check above.
if ! command -v jq >/dev/null 2>&1; then
  deny_literal "scope hook: jq is not installed, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk; it would otherwise allow feature code straight onto the trunk unchallenged. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

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

# Canonicalize before comparing. A path that is merely SPELLED differently
# (`./src/app.js`, `src//app.js`, a project root reached with a trailing slash)
# used to survive the prefix strip as an absolute or dot-prefixed string,
# match no role path, and be allowed onto the trunk in silence. That is the
# same fail-open class as a gate running without jq: the check does not error,
# it just stops checking. Found by the suite on macOS, where TMPDIR carries a
# trailing slash, and reproduced on Linux with `./src/...`.
# Slash squeezing goes through tr rather than bash pattern substitution: the
# escaped-delimiter form (${v//\/\//\/}) squeezed correctly under bash 5 and
# did not under the bash 3.2 that ships with macOS, which the suite caught on
# the macOS CI leg. tr -s is POSIX and behaves the same everywhere.
REL="$(printf '%s' "$FILE_PATH" | tr -s '/')"
REL="${REL#"$PROJ"/}"
REL="${REL#"$PROJ_GIVEN"/}"
while [[ "$REL" == ./* ]]; do REL="${REL#./}"; done
while IFS= read -r ROLE; do
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  ROLE="${ROLE%/}"
  if [[ "$REL" == "$ROLE"/* || "$REL" == "$ROLE" ]]; then
    deny "feature code never lands directly on $TRUNK; open a spec or chore branch via /setlist:checkpoint."
  fi
done <<< "$ROLE_PATHS"
exit 0
