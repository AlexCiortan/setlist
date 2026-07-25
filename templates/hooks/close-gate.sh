#!/usr/bin/env bash
# SDD close gate: PreToolUse on matcher "Bash", fires only on `git merge` into
# the trunk branch (read from .claude/sdd.json, never assumed to be main) from
# a spec/ or chore/ branch. Stamped into the instance. Independently verifies
# the Part 6 close conditions before the merge; /setlist:checkpoint runs the same
# checks first and will normally be the thing that satisfies them.
# Two facts shape this script (dogfood F4-2/F5-1): PreToolUse runs BEFORE the
# command, so the merge target is derived from the command text plus repo
# state (a compound "git checkout <trunk> && git merge ..." is gated even
# though the current branch is not yet the trunk); and the Closing report
# exists on the branch being merged, so every content check reads the merged
# ref via `git show <ref>:<path>`, never the working tree.
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Hook TIMEOUT verified live 2026-07-25 on Claude Code 2.1.x, both directions,
# because this gate re-runs the project's whole suite and is the entry most
# likely to run long. The unit is SECONDS, and the key is honoured: a hook
# sleeping 3s under "timeout": 10 delivered its deny, and the same hook under
# "timeout": 1 was CANCELLED and the tool call PROCEEDED. That second result is
# the fail-open this gate's timeout exists to prevent, so it is measured here
# rather than assumed. The template ships 1800 (30 minutes) for this entry.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make every
# extraction below return empty, every check fall through, and the gate allow
# every merge unchecked. Disable with a one-line edit: remove this hook's entry
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
# parsed command so that a missing jq gates the merges this hook governs
# rather than every Bash call in the session.
if ! command -v jq >/dev/null 2>&1; then
  case "$INPUT" in
    *merge*)
      deny_literal "close gate: jq is not installed, so this gate cannot verify the Closing report, the QA verdict, or the inventory row, and would otherwise allow every merge unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: without jq the raw payload does not mention merging, so
    # this is not a command the gate governs; gating every Bash call would
    # block the very install command that fixes the missing jq.
    *) exit 0 ;;
  esac
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Whether this gate applies must not depend on how the command is SPELLED.
# A literal "git merge" substring test let `git  merge`, `git -C . merge`, and
# `git --no-pager merge` past untouched. Whitespace is squeezed, quotes are
# removed (not their contents: the branch name is an argument this gate needs),
# and git's global options are tolerated before the subcommand.
CMD_NORM="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ' | tr -d "\"'")"
GIT_OPTS='( +-{1,2}[A-Za-z][^ ]*( +[^- ][^ ]*)?)*'
if ! printf '%s' "$CMD_NORM" | grep -qE "(^|[;&|(]| )([^ ]*/)?git${GIT_OPTS} +merge( |$)"; then
  # fail-open-ok: not a merge; this gate governs merges only.
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# Not an SDD instance: stay silent.
# fail-open-ok: no sdd.json means no framework contract to enforce.
SDD_JSON="$PROJ/.claude/sdd.json"
[[ -f "$SDD_JSON" ]] || exit 0

# The config must PARSE, for the same reason the scope hook now requires it: a
# truncated sdd.json makes TRUNK read empty, so the trunk comparison below can
# never match and every merge passes unchecked. jq present is not jq usable.
if ! jq -e . "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal "close gate: .claude/sdd.json does not parse as JSON, so this gate cannot read the trunk name and cannot tell whether this merge lands on the trunk. It would otherwise allow every merge unchecked. Fix the file (jq . .claude/sdd.json will show the error), then retry. Gates fail closed by design."
fi

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
TRUNK="$(jq -r '.trunk // "main"' "$SDD_JSON")"

# --- segment-wise evaluation (1.0.5) -----------------------------------------
#
# A command line is not one command, and every parser this gate has shipped
# did string surgery on the whole line. Each was defeated by that assumption:
#
#   1.0.3 scanned every word, so `git checkout spec/0001-x && git merge main`
#         read the spec branch off the CHECKOUT and gated the wrong operation.
#   1.0.4 took the text after the LAST " merge ". That discarded the first
#         merge's arguments outright (`git merge spec/X && git merge main`
#         passed with nothing checked) and handed the parser a commit MESSAGE
#         whenever one contained the word (`-m "improve merge of main"`
#         passed). A generated corpus found 144 spellings of that class, and
#         the 1.0.4 comment claiming last-occurrence "survives a commit
#         message that happens to contain the word" had it exactly backwards.
#
# So the line is split on its connectors and each segment is judged on its
# own, with the branch each segment RUNS ON tracked across the split. A merge
# counts only at COMMAND POSITION within its segment, which is what stops
# `echo git merge spec/0001-x` from being read as a merge. Any segment that
# denies denies the whole command.
SEGMENTS="$(printf '%s\n' "$CMD_NORM" | awk '{ gsub(/&&|\|\||[;|()]/, "\n"); print }')"

CUR_BRANCH="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
MERGED_REFS=""
UNNAMEABLE=""

while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue

  # A checkout or switch changes the branch every LATER segment runs on. This
  # is how the compound close (`git checkout main && git merge --no-ff
  # spec/X`) is still recognised, without letting the checkout donate its
  # argument to the merge.
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +(checkout|switch) +"; then
    NEWB="$(printf '%s' "$seg" | awk '{ f=0; for (i=1;i<=NF;i++) { if (f && $i !~ /^-/) { print $i; exit } if ($i=="checkout" || $i=="switch") f=1 } }')"
    [[ -n "$NEWB" ]] && CUR_BRANCH="$NEWB"
    continue
  fi

  printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +merge( |$)" || continue

  # This gate guards the trunk. A merge running on any other branch is not a
  # close and never was.
  [[ "$CUR_BRANCH" == "$TRUNK" ]] || continue

  # The merge's own arguments: everything after the FIRST merge token in THIS
  # segment. First, not last, so prose in -m cannot displace the real ones.
  MARGS="$(printf '%s' "$seg" | awk '{ f=0; for (i=1;i<=NF;i++) { if (f) printf "%s ", $i; if (!f && $i=="merge") f=1 } }')"

  if printf '%s' "$MARGS" | grep -qE '(^| )--(continue|abort|quit)( |$)'; then
    # fail-open-ok: the in-progress merge was gated when it was initiated;
    # blocking --continue/--abort would strand a conflicted close with no
    # permitted way to finish it or back out.
    continue
  fi

  SEG_REF=""
  for word in $MARGS; do
    word="${word#refs/heads/}"
    word="${word#refs/remotes/}"
    word="${word#origin/}"
    case "$word" in
      spec/*|chore/*) SEG_REF="$word"; break ;;
    esac
  done

  if [[ -n "$SEG_REF" ]]; then
    MERGED_REFS="$MERGED_REFS $SEG_REF"
    continue
  fi

  # A ref that is NAMED but is not a spec or chore branch is a sync or an
  # integration merge, which this gate has never governed. 1.0.3 denied those
  # too, breaking `git merge origin/main` while `git pull` did the same thing
  # ungated: friction with no safety. A ref counts as named when it RESOLVES
  # here and is not a form whose target cannot be read off the command line.
  # Requiring resolution is what stops the words of
  # `git merge -m "closing spec" $B` from posing as a branch name.
  NAMED_REF=""
  for word in $MARGS; do
    case "$word" in
      -*|*'$'*|*'`'*|@*|'') continue ;;
      HEAD|FETCH_HEAD|ORIG_HEAD|MERGE_HEAD|CHERRY_PICK_HEAD|REVERT_HEAD) continue ;;
    esac
    printf '%s' "$word" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._/-]*$' || continue
    printf '%s' "$word" | grep -qE '^[0-9a-f]{7,40}$' && continue
    if git -C "$PROJ" rev-parse --verify --quiet "${word}^{commit}" >/dev/null 2>&1; then
      NAMED_REF="$word"; break
    fi
  done
  [[ -n "$NAMED_REF" ]] || UNNAMEABLE="$seg"
done <<SEGEOF
$SEGMENTS
SEGEOF

# A trunk-targeting merge whose branch cannot be established at all: the close
# conditions are about a specific branch's artifacts, so with no branch there
# is nothing to check and the gate refuses rather than guessing.
if [[ -n "$UNNAMEABLE" ]]; then
  deny "close gate: this merges into the trunk, but no argument of [$UNNAMEABLE] names a branch this gate can resolve. Indirect forms (a shell variable, -, @{-1}, FETCH_HEAD, a raw commit SHA) cannot be verified, so the close conditions cannot be checked at all. Name the branch literally: git merge --no-ff spec/NNNN-slug."
fi

if [[ -z "$MERGED_REFS" ]]; then
  # fail-open-ok: no segment merges a spec or chore branch into the trunk, so
  # no close is being attempted here.
  exit 0
fi

# Every collected ref is checked; the first failure denies the whole command.
for MERGED_REF in $MERGED_REFS; do
  # The ref must resolve; every check below reads the merged ref's committed
  # tree, so working-tree edits that were never committed to the branch do not
  # count.
  if ! git -C "$PROJ" rev-parse --verify --quiet "${MERGED_REF}^{commit}" >/dev/null 2>&1; then
    deny "close gate: branch $MERGED_REF does not resolve to a commit; the close gate cannot verify the Closing report. Check the branch name."
  fi

  # Chore branches (chore/<slug>, unnumbered per Part 5b) have no spec file or
  # inventory row to verify; for them only the gate command below applies.
  if [[ "$MERGED_REF" == spec/* ]]; then
    # Derive the spec file from the branch NUMBER (Part 6: spec/NNNN-<slug>
    # builds specs/NNNN-*.md), looked up in the merged ref's tree. The slug may
    # legitimately differ between branch and file; the number may not. Fail
    # closed on zero or multiple matches.
    SPEC_NUM="${MERGED_REF#spec/}"
    SPEC_NUM="${SPEC_NUM%%-*}"
    SPEC_PATHS="$(git -C "$PROJ" ls-tree -r --name-only "$MERGED_REF" -- specs/ 2>/dev/null | grep -E "^specs/${SPEC_NUM}-[^/]*\.md$" || true)"
    MATCHES=0
    [[ -n "$SPEC_PATHS" ]] && MATCHES="$(printf '%s\n' "$SPEC_PATHS" | grep -c .)"
    if [[ "$MATCHES" -eq 0 ]]; then
      deny "close gate: no spec file matches specs/$SPEC_NUM-*.md on branch $MERGED_REF; the close gate cannot verify the Closing report. Commit the spec file to the branch before merging."
    fi
    if [[ "$MATCHES" -ne 1 ]]; then
      deny "close gate: $MATCHES spec files match specs/$SPEC_NUM-*.md on branch $MERGED_REF; spec numbers must be unique. Resolve the duplicate before merging."
    fi
    SPEC_PATH="$(printf '%s\n' "$SPEC_PATHS" | head -n1)"
    SPEC_TEXT="$(git -C "$PROJ" show "${MERGED_REF}:${SPEC_PATH}" 2>/dev/null || true)"

    # The Closing report section exists (Appendix C: "## Closing report ...").
    if ! printf '%s\n' "$SPEC_TEXT" | grep -qE '^#+[[:space:]]*Closing report'; then
      deny "close gate: the spec file for $MERGED_REF has no Closing report section on the branch; complete it, commit it to the branch, then merge."
    fi

    # The pasted QA Pass 1 block: between the "QA Pass 1 report" field and the
    # "QA Pass 2" field there must be at least one PASS / PARTIAL / FAIL verdict.
    # Both boundaries anchor on the Appendix C FIELD MARKER (start of line, past
    # any list bullet or bold markers), never on a bare substring anywhere in the
    # line. The bare "QA Pass 2" test ended the block at the first sentence of
    # QA-1 prose that merely cross-referenced QA Pass 2, truncating the verdict
    # out of the block and denying a compliant merge in the field.
    QA_BLOCK="$(printf '%s\n' "$SPEC_TEXT" | awk '
      /^[-*+[:space:]]*QA Pass 1 report/ { inqa = 1 }
      /^[-*+[:space:]]*QA Pass 2/        { inqa = 0 }
      inqa')"
    if ! printf '%s\n' "$QA_BLOCK" | grep -qE '(^|[^A-Z])(PASS|PARTIAL|FAIL)([^A-Z]|$)'; then
      deny "close gate: the Closing report for $MERGED_REF carries no pasted QA Pass 1 PASS/PARTIAL/FAIL block; run QA Pass 1, paste the report, commit it to the branch, then merge."
    fi

    # The architecture-diagram field (Appendix C, exact label "Architecture
    # diagram:") is answered: "updated in this commit" or "no impact", never the
    # template placeholder (which still carries angle brackets).
    DIAG_LINE="$(printf '%s\n' "$SPEC_TEXT" | grep -E 'Architecture diagram:' | tail -n1)"
    if [[ -z "$DIAG_LINE" ]]; then
      deny "close gate: the Closing report for $MERGED_REF is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    fi
    DIAG_ANSWER="${DIAG_LINE#*Architecture diagram:}"
    if [[ "$DIAG_ANSWER" == *"<"* ]] || ! printf '%s' "$DIAG_ANSWER" | grep -qE 'updated in this commit|no impact'; then
      deny "close gate: the architecture-diagram field for $MERGED_REF is unanswered; answer it 'updated in this commit' or 'no impact', commit to the branch, then merge."
    fi

    # STATUS.md carries the spec's inventory row, updated to CLOSED, on the
    # branch (Part 6: the row rides the same commit as the Closing report; the
    # merge is what brings it to the trunk). Row format from the stamped
    # STATUS.md: | NNNN | Title | Status | note |.
    STATUS_TEXT="$(git -C "$PROJ" show "${MERGED_REF}:specs/STATUS.md" 2>/dev/null || true)"
    if ! printf '%s\n' "$STATUS_TEXT" | grep -E "^\|[[:space:]]*${SPEC_NUM}[[:space:]]*\|" | grep -q 'CLOSED'; then
      deny "close gate: specs/STATUS.md on branch $MERGED_REF has no inventory row marking spec $SPEC_NUM CLOSED; update the row in the same commit as the Closing report, then merge."
    fi
  fi
done

# The gate command (the full test suite) must exit 0, run fresh. /scaffold
# records it in sdd.json when it flips the scaffolded flag; before that flip
# (bootstrap-era, docs-only merges) there is nothing to run yet.
SCAFFOLDED="$(jq -r '.scaffolded // false' "$SDD_JSON" 2>/dev/null)"
GATE_CMD="$(jq -r '.gate_command // empty' "$SDD_JSON" 2>/dev/null)"
if [[ "$SCAFFOLDED" == "true" && -z "$GATE_CMD" ]]; then
  deny "close gate: .claude/sdd.json is scaffolded but carries no gate_command; record the full-suite command there before merging."
fi
if [[ -n "$GATE_CMD" ]]; then
  if ! (cd "$PROJ" && bash -c "$GATE_CMD" >/dev/null 2>&1); then
    deny "close gate: the gate command ($GATE_CMD) failed on a fresh run; gates must be green before merging."
  fi
fi

# fail-open-ok: every close condition above was checked against the merged
# ref's committed tree and held; this is the gate's green path.
exit 0
