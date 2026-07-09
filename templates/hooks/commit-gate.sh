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
# Requires jq. Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

INPUT=$(cat)
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# Check 0: compound stage-and-commit forms are denied outright (F4-1). This
# hook runs BEFORE the command, so a command that both stages and commits
# would have its staged-content checks below scan an index that does not yet
# hold the content: every check would pass vacuously. Quoted strings are
# stripped first so commit messages mentioning "git add" or "-a" do not
# false-trip the scan.
CMD_BARE="$(printf '%s' "$CMD" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"
if printf '%s' "$CMD_BARE" | grep -qE 'git[[:space:]]+add([[:space:]]|$)'; then
  deny "commit gate: this command stages and commits in one step, so the gate would scan an empty index and check nothing. Run git add as its own command first, then git commit separately; the gate scans the staged content and names any finding."
fi
if printf '%s' "$CMD_BARE" | grep -qE 'git[[:space:]]+commit[[:space:]]' \
  && printf '%s' "$CMD_BARE" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[ai][a-zA-Z]*([[:space:]]|$)|--all([[:space:]]|$)|--include([[:space:]]|$)|--interactive([[:space:]]|$)'; then
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

exit 0
