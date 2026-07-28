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
CMD_NORM="$(printf '%s' "$CMD" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | tr '\n\r' ';;' | tr -s '[:space:]' ' ')"
# Quoted spans are removed by a LEFT-TO-RIGHT scan, not by two sed passes.
#
# The two passes paired quote characters across the whole line, and across
# segments: `echo "it@s fine" && git commit -m "don@t ship"` (with @ an
# apostrophe) has the apostrophe of the first message pair with the apostrophe
# of the second, deleting everything between them including the `git commit`
# this gate exists to see. Reordering the passes does not fix it, it mirrors it:
# singles-first loses the case above, doubles-first loses `echo @a"b@ && git
# commit -m @c"d@`. Both spellings are asserted in the suite for exactly that
# reason.
#
# A scan has no such failure mode. Whichever quote opens first owns the span
# until its own closing character, which is what a shell does.
CMD_BARE="$(printf '%s' "$CMD_NORM" | awk '{
  out = ""; q = ""
  n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (q == "") {
      if (c == "\"" || c == "\047") { q = c } else { out = out c }
    } else if (c == q) { q = "" }
  }
  print out
}')"
GIT_OPTS='( +-{1,2}[A-Za-z][^ ]*( +[^- ][^ ]*)?)*'

# The verbs that WRITE THE INDEX, which is the whole population Check 0 has to
# recognise. Until 1.0.7 this enumeration was `add|rm|mv`, so every other verb
# that writes the index could be compounded with a commit and all three
# staged-content checks below would read an index nobody had judged:
#
#     git stash pop && git commit -m x        <- allowed, index changed after the scan
#     git restore --staged . && git commit -m x
#
# `stage` is here because it is a plain synonym for `add` and was simply never
# written down. The rest are the verbs whose documented effect includes writing
# the index, whether or not that is their headline purpose: a branch switch, a
# merge with --no-commit, a half-applied cherry-pick and a plumbing read-tree
# all leave an index the scan above did not see.
#
# THIS LIST IS A CORPUS DIMENSION, not a constant. test/run-tests.sh carries its
# own copy, asserts every verb in it is denied when compounded with a commit,
# and asserts the two lists are IDENTICAL, so a verb added here without a
# corpus entry (or the reverse) fails the suite. That lockstep is the point: the
# defect this list replaces was not a wrong pattern, it was a dimension nobody
# had enumerated, and the repo has now shipped that same shape three times (the
# wrapper axis, the dash-valued flag axis, this). An enumeration a reviewer must
# remember to extend is the same defect waiting.
INDEX_VERBS='add|stage|rm|mv|restore|reset|stash|checkout|switch|merge|pull|rebase|cherry-pick|revert|am|apply|update-index|read-tree|sparse-checkout'

# Segment-wise, for the same reason the close gate is (1.0.5). A command line
# is not one command, and a whole-line grep cannot tell an operation from a
# mention of one: `echo git add . && git commit -m x` was denied though the
# only staging in it is a word being printed. The generated commit-gate corpus
# found that on its first run. Each segment is judged at COMMAND POSITION.
# Strip the ways a shell legitimately STARTS a git command before judging
# whether a segment is one (1.0.6). The command-position test that removed the
# `echo git merge ...` false positive introduced this false negative: a segment
# is only judged when it starts with `git`, so `command git merge ...`,
# `env git merge ...` and `nice git merge ...` were never judged at all.
#
# The allowlist is deliberately NOT a claim of completeness: `timeout`,
# `setsid`, `ionice`, `sudo`, `xargs` and whatever comes next are not covered,
# and no allowlist can be, because this is the shell-escape-hatch family. It
# closes the forms a person or an agent actually types. The designed catch for
# the whole family is the trunk audit, which reads the outcome in history and
# does not care how the command was spelled.
strip_wrappers() { # strip_wrappers <segment> -> echoes the segment, unwrapped
  local seg="$1" prev=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    # leading VAR=val assignments (FOO=bar git ...)
    seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^ ]* *//')"
    # a wrapper word, plus env/stdbuf style flags and assignments after it
    seg="$(printf '%s' "$seg" | sed -E 's/^(command|exec|nice|nohup|time|stdbuf|env) +//')"
    # A wrapper flag may take its value as a SEPARATE word (`nice -n 5 git
    # commit -am x`), and consuming the flag alone strands the value at the
    # head of the segment, where it defeats the command-position test. The
    # command word is never eaten as a value: `env -i git commit ...` has git
    # sitting exactly where a value would be. Same defect and same fix as
    # close-gate.sh, repeated because the two hooks each carry their own copy
    # and a repair in one is not a repair in the other.
    # The bare `--` option terminator is not a flag, not a value and not a
    # command: it is punctuation that every branch below ignored, so it sat at
    # the head of the segment and defeated the command-position test on its own.
    # v1.0.6 DENIED `env -- git merge ...`; 1.0.7 allowed it until this line.
    seg="$(printf '%s' "$seg" | sed -E 's/^-- +//')"
    if printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +([^ ]*/)?git( |$)'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +-[^ ]* +'; then
      # A flag value may itself begin with a dash: `nice -n -5 git ...` is an
      # ordinary negative niceness. The value branch below requires a NON-dash
      # value, so `-n` was consumed one word at a time and `-5` was stranded at
      # the head, which is the same stranding the value branch was written to
      # stop. v1.0.6 DENIED this; 1.0.7 allowed it until this branch.
      #
      # It sits AFTER the git branch on purpose. That branch has already taken
      # any case where the command word follows the flag directly, so nothing
      # here can eat git: a dash-leading word is never the command.
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +-[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +[^- ][^ ]* +'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +[^- ][^ ]* +//')"
    else
      seg="$(printf '%s' "$seg" | sed -E 's/^(-{1,2}[^ ]* +)+//')"
    fi
  done
  printf '%s' "$seg"
}

# The separator set. `&` is here as of 1.0.7: a SINGLE ampersand backgrounds the
# preceding command and starts a new one, exactly as `;` does, and its absence
# meant `git stash pop & git commit -m x` collapsed to one unrecognised segment.
# Both gates carry their own copy of this line, so this is fixed in both; a
# repair in one has already failed to be a repair in the other more than once.
#
# `&&` must not become two separators. It does not: POSIX ERE alternation is
# leftmost-LONGEST, the two-character alternative is listed first, and the
# behaviour is asserted in the suite rather than trusted, because "the awk on
# the reviewer's machine" is precisely the assumption the macOS leg exists to
# doubt. Even if it did split, the empty middle segment is skipped below, so
# this is belt and braces on a case that must not regress silently.
SEGMENTS="$(printf '%s\n' "$CMD_BARE" | awk '{ gsub(/&&|\|\||[;|()&]/, "\n"); print }')"
HAS_COMMIT=""
HAS_STAGE=""
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue
  seg="$(strip_wrappers "$seg")"
  [[ -n "$seg" ]] || continue
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +commit( |$)"; then
    HAS_COMMIT="$seg"
  elif printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +($INDEX_VERBS)( |$)"; then
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
  deny "commit gate: this command writes the index and commits in one step (git add, stage, rm, mv, restore, reset, stash, checkout, switch, merge, pull, rebase, cherry-pick, revert, am, apply, update-index, read-tree and sparse-checkout can all write the index during command execution, after this gate scanned it), so the gate would scan a stale index and check nothing. Run the index-writing command on its own first, then git commit separately; the gate scans the staged content and names any finding."
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
