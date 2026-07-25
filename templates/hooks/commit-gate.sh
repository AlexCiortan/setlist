#!/usr/bin/env bash
# SDD commit gate: PreToolUse on matcher "Bash", fires only on `git commit`.
# Stamped into the instance. Check 0 denies compound stage-and-commit commands
# (the gate can only scan content that is already staged when the hook runs);
# then three staged-content checks (Part 6): em-dash scan, secret scan,
# STATUS-in-same-commit. Each deny names the specific failure so the agent can
# fix and retry. Known residual hole: `git commit <pathspec>` commits the
# working-tree copy of the named path without staging; distinguishing a
# pathspec from a message word needs real shell parsing, so it is out of
# scope here and the split-form doctrine plus prompted discipline cover it.
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make every
# extraction below return empty, every check fall through, and the gate allow
# everything silently. Disable with a one-line edit: remove this hook's entry
# from .claude/settings.json.

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

# Fail closed when jq is absent. The raw payload is scanned instead of the
# parsed command so that a missing jq gates the commands this hook governs
# rather than every Bash call in the session: the agent can still run the
# install command that fixes it. The match is the bare word here, not "git
# commit": without jq there is no reliable parse, so this path errs toward
# denying anything that mentions committing at all.
if ! command -v jq >/dev/null 2>&1; then
  case "$INPUT" in
    *commit*)
      deny_literal "commit gate: jq is not installed, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: without jq the raw payload does not mention committing, so
    # this is not a command the gate governs; gating every Bash call would
    # block the very install command that fixes the missing jq.
    *) exit 0 ;;
  esac
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Whether this gate applies must not depend on how the command is SPELLED.
# A literal "git commit" substring test let `git  commit` (two spaces),
# `git -C . commit`, `git --no-pager commit`, and `git -c k=v commit` past the
# gate untouched: it did not error, it stopped checking, in silence. Whitespace
# is squeezed once, quoted strings are dropped so a message mentioning the word
# cannot trip it, and git's own global options are tolerated between the binary
# and the subcommand.
CMD_NORM="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')"
CMD_BARE="$(printf '%s' "$CMD_NORM" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"
GIT_OPTS='( +-{1,2}[A-Za-z][^ ]*( +[^- ][^ ]*)?)*'
# Segment-wise, for the same reason the close gate is (1.0.5). A command line
# is not one command, and a whole-line grep cannot tell an operation from a
# mention of one: `echo git add . && git commit -m x` was denied though the
# only staging in it is a word being printed. The generated commit-gate corpus
# found that on its first run. Each segment is judged at COMMAND POSITION.
SEGMENTS="$(printf '%s\n' "$CMD_BARE" | awk '{ gsub(/&&|\|\||[;|()]/, "\n"); print }')"
HAS_COMMIT=""
HAS_STAGE=""
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +commit( |$)"; then
    HAS_COMMIT="$seg"
  elif printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +(add|rm|mv)( |$)"; then
    HAS_STAGE="$seg"
  fi
done <<SEGEOF
$SEGMENTS
SEGEOF

if [[ -z "$HAS_COMMIT" ]]; then
  # fail-open-ok: no segment is a commit at command position; this gate
  # governs commits only.
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# Check 0: compound stage-and-commit forms are denied outright (F4-1). This
# hook runs BEFORE the command, so a command that both stages and commits
# would have its staged-content checks below scan an index that does not yet
# hold the content: every check would pass vacuously.
if [[ -n "$HAS_STAGE" ]]; then
  deny "commit gate: this command stages and commits in one step (git add, rm, and mv all write the index during command execution, after this gate scanned it), so the gate would scan a stale index and check nothing. Run the staging command on its own first, then git commit separately; the gate scans the staged content and names any finding."
fi
# Read the COMMIT segment's own flags, not the whole line: another command's
# -a on the same line is not this commit's auto-staging flag.
if printf '%s' "$HAS_COMMIT" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[ai][a-zA-Z]*([[:space:]]|$)|--all([[:space:]]|$)|--include([[:space:]]|$)|--interactive([[:space:]]|$)'; then
  deny "commit gate: git commit with -a, -i, --all, or --include stages at commit time, so the gate would scan an empty index and check nothing. Stage the exact files with git add first, then run git commit without auto-staging flags."
fi

# Staged additions only: lines the commit would introduce.
ADDED="$(git -C "$PROJ" diff --cached --unified=0 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"

# Check 1: em-dash scan on staged new content. The character is built from an
# escape so this script never contains it literally (repo rule 1 applies to the
# instances too).
EMDASH="$(printf '\342\200\224')"
if printf '%s\n' "$ADDED" | grep -q "$EMDASH"; then
  deny "commit gate: staged new content contains an em-dash; replace it with a comma, colon, parentheses, or separate sentences, then retry."
fi

# Check 2: secret scan. Token-shaped, connection-string-shaped, password-shaped.
# STUB NOTE: the pattern set is a first cut; tune it as dogfood and field runs
# surface false positives or misses.
if printf '%s\n' "$ADDED" | grep -qiE '(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'; then
  deny "commit gate: staged content contains a secret-shaped string; move the value to the environment, reference it, and stage .env.example instead."
fi

# Check 3: STATUS-in-same-commit. A staged spec lifecycle transition (Status
# line change or a Closing report section added) requires specs/STATUS.md in
# the same commit. Ordinary mid-build spec edits do not trip it. The formats
# bound here are Appendix C exactly: the header line "Status: QUEUED" (bare
# label, one lifecycle state) and the "## Closing report" heading.
SPEC_ADDED="$(git -C "$PROJ" diff --cached --unified=0 -- 'specs/*.md' ':(exclude)specs/STATUS.md' ':(exclude)specs/TEMPLATE.md' 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
if printf '%s\n' "$SPEC_ADDED" | grep -qE '^\+Status:[[:space:]]*(QUEUED|ACTIVE|REVISED|CLOSED|DRAFT)|^\+#+[[:space:]]*Closing report'; then
  if ! git -C "$PROJ" diff --cached --name-only | grep -qx 'specs/STATUS.md'; then
    deny "commit gate: this commit changes a spec lifecycle state but does not stage specs/STATUS.md; update the STATUS.md inventory line in the same commit."
  fi
fi

# fail-open-ok: every check above ran against the staged content and found
# nothing to deny; this is the gate's green path.
exit 0
