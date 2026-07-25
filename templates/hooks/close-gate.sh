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

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
TRUNK="$(jq -r '.trunk // "main"' "$SDD_JSON")"

# Derive the merge target. Default: the current branch (the split form runs
# the merge while already on the trunk). Compound form: if the same command
# also checks out or switches to the trunk before merging, the target is the
# trunk even though the current branch is not yet (F4-2a).
TARGET="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
if printf '%s' "$CMD_NORM" | grep -qE "(^|[;&|(]| )([^ ]*/)?git${GIT_OPTS} +(checkout|switch) +${TRUNK}( |$|[;&|)])"; then
  TARGET="$TRUNK"
fi

# Only gate merges INTO the trunk.
# fail-open-ok: merging the trunk into a feature branch (or any non-trunk
# target) is not a close; the trunk is what this gate guards. (Detached HEAD
# reads as an empty target and passes: named in Known limitations.)
[[ "$TARGET" == "$TRUNK" ]] || exit 0

# Extract the merged ref: the first git-merge argument that names a spec/ or
# chore/ branch. Other merges (e.g. the trunk into a feature branch, already
# excluded above) pass through.
# CMD_NORM is used, not CMD: quoting the branch name (`git merge --no-ff
# "spec/0001-x"`, either quote style) used to leave no word matching spec/*,
# so MERGED_REF came back empty and the gate exited silently, waving through
# exactly the merge it exists to check. Fully-qualified and remote-tracking
# spellings of the same branch did the same.
# Only the arguments AFTER the merge subcommand are the merge's arguments
# (1.0.4). Scanning the whole command line let a compound form donate tokens
# it does not own: `git checkout spec/0001-x && git merge main` had the spec
# branch read off the CHECKOUT and gated as though it were being merged, and
# the same donation would have handed the named-ref test below the trunk name
# out of `git checkout main && git merge $B`, re-opening the hole this block
# exists to close. Taking the text after the LAST " merge " survives a commit
# message that happens to contain the word.
MERGE_ARGS="$CMD_NORM"
case "$CMD_NORM" in
  *" merge "*) MERGE_ARGS="${CMD_NORM##* merge }" ;;
  *" merge")   MERGE_ARGS="" ;;
esac

MERGED_REF=""
for word in $MERGE_ARGS; do
  word="${word#refs/heads/}"
  word="${word#refs/remotes/}"
  word="${word#origin/}"
  case "$word" in
    spec/*|chore/*) MERGED_REF="$word"; break ;;
  esac
done

# No extractable ref DENIES (1.0.3, IN-1). The 1.0.1 fix widened the parser
# for quoted branch names but kept the fail-open disposition, so every
# indirect naming (`git merge $BRANCH`, `-`, `@{-1}`, FETCH_HEAD, a raw SHA)
# still merged into the trunk unchecked. A gate that cannot establish WHAT is
# being merged cannot verify anything about it, and by the same doctrine as
# the jq check above, it denies rather than guessing. The one exception:
# --continue/--abort/--quit finish or cancel a merge whose initiating command
# was already gated on its own way in.
if [[ -z "$MERGED_REF" ]]; then
  if printf '%s' "$CMD_NORM" | grep -qE "merge${GIT_OPTS} +--(continue|abort|quit)( |$)"; then
    # fail-open-ok: the in-progress merge was gated when it was initiated;
    # blocking --continue/--abort here would strand a conflicted close with
    # no permitted way to finish or back out.
    exit 0
  fi

  # A ref that is NAMED but is not a spec or chore branch is not a close, and
  # this gate has never governed it. 1.0.3 denied it anyway, which broke
  # `git merge origin/main` (syncing your own trunk) and any release or
  # upstream branch, while `git pull` achieved the identical result and passed
  # untouched: friction with no safety, and the deny message pointed at the
  # bypass. The 1.0.4 rule separates the two cases 1.0.3 conflated. A ref is
  # NAMED when a post-merge argument resolves to a commit in this repository
  # and is not one of the forms whose target cannot be read off the command:
  # a shell variable, -, @{...}, a bare SHA, or a pseudo-ref like FETCH_HEAD.
  # Requiring it to RESOLVE is what keeps the message words of
  # `git merge -m "closing spec" $B` from posing as a branch name.
  NAMED_REF=""
  for word in $MERGE_ARGS; do
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
  if [[ -n "$NAMED_REF" ]]; then
    # fail-open-ok: $NAMED_REF resolves and is not a spec or chore branch, so
    # this is a sync or integration merge, not a close; the close conditions
    # are about a spec branch's own artifacts and have nothing to say here.
    exit 0
  fi

  deny "close gate: this merges into the trunk, but no post-merge argument names a branch this gate can resolve. Indirect forms (a shell variable, -, @{-1}, FETCH_HEAD, a raw commit SHA) cannot be verified, so the close conditions cannot be checked at all. Name the branch literally: git merge --no-ff spec/NNNN-slug."
fi

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
