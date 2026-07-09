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
  *"git merge"*) ;;
  *) exit 0 ;;
esac

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# Not an SDD instance: stay silent.
SDD_JSON="$PROJ/.claude/sdd.json"
[[ -f "$SDD_JSON" ]] || exit 0

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
TRUNK="$(jq -r '.trunk // "main"' "$SDD_JSON")"

# Derive the merge target. Default: the current branch (the split form runs
# the merge while already on the trunk). Compound form: if the same command
# also checks out or switches to the trunk before merging, the target is the
# trunk even though the current branch is not yet (F4-2a).
TARGET="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
if printf '%s' "$CMD" | grep -qE "git[[:space:]]+(checkout|switch)[[:space:]]+${TRUNK}([[:space:]]|$|[;&|)])"; then
  TARGET="$TRUNK"
fi

# Only gate merges INTO the trunk.
[[ "$TARGET" == "$TRUNK" ]] || exit 0

# Extract the merged ref: the first git-merge argument that names a spec/ or
# chore/ branch. Other merges (e.g. the trunk into a feature branch, already
# excluded above) pass through.
MERGED_REF=""
for word in $CMD; do
  case "$word" in
    spec/*|chore/*) MERGED_REF="$word"; break ;;
  esac
done
[[ -n "$MERGED_REF" ]] || exit 0

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
  QA_BLOCK="$(printf '%s\n' "$SPEC_TEXT" | awk '/QA Pass 1 report/ { inqa=1 } /QA Pass 2/ { inqa=0 } inqa')"
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

exit 0
