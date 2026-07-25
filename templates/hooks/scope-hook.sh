#!/usr/bin/env bash
# SDD scope hook: PreToolUse on matcher "Write|Edit|MultiEdit|NotebookEdit",
# stamped into the instance. (MultiEdit is absent from current Claude Code,
# folded into Edit; it stays in the matcher defensively for older harnesses,
# where matching a tool that never fires costs nothing and missing one that
# does costs the trunk. NotebookEdit is live and sends notebook_path, not
# file_path; both are read below.)
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
  # fail-open-ok: not a pass at all; exit 0 is how the hook protocol delivers
  # the deny JSON emitted above.
  exit 0
}

# Deny with a fixed literal reason, for the paths where jq is unavailable to
# escape one. The text must contain no double quotes, backslashes, or newlines.
deny_literal() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  # fail-open-ok: not a pass at all; exit 0 delivers the deny JSON above.
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
# fail-open-ok: no sdd.json means no framework contract to enforce; gating a
# repo that never opted in would make the plugin unusable outside instances.
[[ -f "$SDD_JSON" ]] || exit 0

# Fail closed when jq is absent: sdd.json is unreadable, so the branch rule
# cannot be evaluated at all. Scoped to stamped instances by the check above.
if ! command -v jq >/dev/null 2>&1; then
  deny_literal "scope hook: jq is not installed, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk; it would otherwise allow feature code straight onto the trunk unchallenged. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# The config must PARSE. jq being installed is not the same as sdd.json being
# readable: a truncated or half-merged file makes every extraction below
# return empty, so the scaffolded flag reads false, the trunk name reads
# empty, and the hook exits 0 having checked nothing. That is total silent
# disablement of the trunk rule from an ordinary accident (a bad merge, an
# interrupted write, a hand edit), and it is exactly the failure this hook's
# no-jq path was written to prevent, reached by a different road.
# `refresh-instance.sh` has refused on this since 1.0.2; the hooks had not.
# Found by the degraded-environment generator on its first run.
if ! jq -e . "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal "scope hook: .claude/sdd.json does not parse as JSON, so this gate cannot read the trunk name or the role paths and cannot tell whether this write lands on the trunk. It would otherwise allow feature code straight onto the trunk unchallenged. Fix the file (jq . .claude/sdd.json will show the error), then retry. Gates fail closed by design."
fi

# Active only after /scaffold flips the flag, so the one-time bootstrap
# scaffold on main is not blocked.
# fail-open-ok: pre-scaffold, the trunk rule is deliberately not yet in force.
[[ "$(jq -r '.scaffolded // false' "$SDD_JSON")" == "true" ]] || exit 0

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
TRUNK="$(jq -r '.trunk // "main"' "$SDD_JSON")"
BRANCH="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
# fail-open-ok: off the trunk, writes are the point of a spec branch; this
# gate only guards the trunk. (Detached HEAD reads as empty, never equals the
# trunk, and passes: named in Known limitations.)
[[ "$BRANCH" == "$TRUNK" ]] || exit 0

# file_path for Write/Edit/MultiEdit; notebook_path for NotebookEdit. An
# event carrying NEITHER denies (1.0.3, IN-3): every tool this hook matches
# sends one of the two today, so an empty extraction means the harness
# changed shape under the hook, and a gate that cannot see the path cannot
# tell whether the write lands on the trunk. This used to exit 0, which is
# exactly how NotebookEdit's notebook_path slipped past the trunk rule.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
if [[ -z "$FILE_PATH" ]]; then
  deny "scope hook: this tool call carries neither file_path nor notebook_path, so the gate cannot tell whether the write lands on $TRUNK and will not guess. If the harness has changed its tool-input shape, update .claude/hooks/scope-hook.sh (and report it); removing this hook entry from .claude/settings.json is the deliberate way to work without the gate."
fi

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
# fail-open-ok: the write matched no role path; docs-only trunk writes are
# the allowed case the whole loop exists to distinguish.
exit 0
