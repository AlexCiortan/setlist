#!/usr/bin/env bash
# Setlist Stop hook: refuses to END A TURN that leaves a spec or specs/STATUS.md
# changed and unstaged in the working tree (2.6.0, spec 0132 cluster H; the
# owner's ruling 5 on the 2.6.0 strategy; external review minor 2). Stamped
# into the instance beside the three PreToolUse gates and the SessionStart
# re-grounding hook; wired on the Stop event, which takes no matcher.
#
# WHY A STOP HOOK, AND WHY THIS RULE. The record (a spec's Status line, its
# Closing report, the inventory row in specs/STATUS.md) and the page that reads
# it are kept in agreement by ONE writer at a time (Part 3, RP1). A turn that
# ends with that record edited and not staged is the state in which the two
# disagree and nobody is holding the pen: the next session re-grounds on a
# STATUS.md the working tree contradicts. The Bash gates cannot see this (they
# read commands, not the tree between them), and the git hooks cannot either
# (nothing was committed). The end of a turn is the one moment the harness
# asks, and the reason it renders here is READ by the model. Measured live on
# 2026-09-07, Claude Code 2.1.259, in a scratch instance with specs/STATUS.md
# edited and unstaged: the first Stop payload (stop_hook_active false) drew
# this hook's block, the session read the reason, ran `git add
# specs/STATUS.md` and answered; the second Stop payload (stop_hook_active
# true) drew this hook's allow and the turn ended, three turns in all. That
# is more than the PreToolUse gates can say for an allow with a reason (RP5).
#
# WHAT IT DOES NOT DO. It does not commit, stage or restore anything. It does
# not read the spec's content. It refuses ONCE per end of turn: the harness
# marks the continuation it grants on this hook's word (`stop_hook_active`),
# and on that continuation this hook allows, so a change the session cannot
# stage (a permission it lacks, a file it did not write) is a nudge that is
# seen, never a lock. A session killed from outside fires no Stop at all, which
# the public list names as this hook's boundary.
#
# FAIL-CLOSED WHERE IT CAN ASK, OPEN WHERE IT CANNOT. A tree git cannot read
# is refused by name (SP-NO-GIT): a check that could not run has not passed,
# and the reason says so. jq is NOT load-bearing here: the payload's one field
# is read by a substring test and the verdict is written by a literal printf,
# so a broken jq changes nothing about the decision; it is REPORTED beside a
# refusal (SP-JQ-BROKEN) so the operator learns it from the layer that can
# still speak. A repository with no .claude/sdd.json is not an instance and
# is none of this hook's business.
#
# THE CONTRACT (the Stop event's, measured):
#   stdout  {"decision":"block","reason":<text>,"setlistAdvisory":{...}}  to refuse
#           nothing                                                        to allow
#   exit    0 either way (a nonzero exit is an error the harness reports, not a verdict)
#   setlistAdvisory  {gate: "stop", verdict: "block", code, reason}, the same
#                    field the three gates emit, so one reader reads all four
set -u

# THE CODE IS EXTRACTED BY THE SHELL (KL11's rule, from birth): the last
# well-formed bracketed token of the reason.
adv_code_of() { # adv_code_of <reason> -> sets ADV_CODE
  local rest="$1" cand
  ADV_CODE=""
  while [[ "$rest" == *"["* ]]; do
    rest="${rest#*\[}"
    [[ "$rest" == *"]"* ]] || break
    cand="${rest%%\]*}"
    case "$cand" in
      [A-Z]*) case "$cand" in *[!A-Z0-9-]*) ;; *) ADV_CODE="$cand" ;; esac ;;
    esac
  done
}

# json_str <text> -> a JSON string literal, by the shell (no jq on this path).
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

refuse() { # refuse <reason>  -> the block, on stdout, exit 0
  # The toolchain report rides AHEAD of the refusal so the refusal's own code
  # is the last bracket, which is the one the reader extracts.
  local reason="${JQ_NOTE}$1"
  adv_code_of "$reason"
  printf '{"decision":"block","reason":%s,"setlistAdvisory":{"gate":"stop","verdict":"block","code":%s,"reason":%s}}\n' \
    "$(json_str "setlist stop hook: $reason")" "$(json_str "$ADV_CODE")" "$(json_str "$reason")"
  # fail-open-ok: this exit 0 delivers a BLOCK, not an allow: the harness reads
  # the JSON's decision, and a nonzero exit would be an error it reports rather
  # than a verdict it renders.
  exit 0
}

IFS= read -r -d '' INPUT || true

# THE CONTINUATION THIS HOOK ASKED FOR IS ALLOWED. The harness sets
# stop_hook_active when the turn is continuing because a Stop hook blocked; a
# second block on the same grounds would loop until the harness's own cap.
# Read by substring on the raw payload, so jq is not on this path.
case "$INPUT" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

PROJ="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJ" ]]; then
  # The payload's cwd, read by jq when jq works and by a substring when it does
  # not; an unreadable cwd falls back to the working directory this hook runs in.
  PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [[ -n "$PROJ" ]] || PROJ="$PWD"
fi
# Not an instance: nothing here is this hook's business.
[[ -f "$PROJ/.claude/sdd.json" ]] || exit 0

JQ_NOTE=""
if [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  JQ_NOTE="[SP-JQ-BROKEN]: jq is missing or does not work on this machine, so the three PreToolUse gates are reporting their verdicts while permitting and the git hooks refuse; run jq --version to see which, then install or repair it. Reported here because this hook decides without jq and can still speak. "
fi

# THE READ. git is asked directly for the working tree's state under specs/;
# a git that cannot answer is a refusal by name, never a pass on silence.
if ! git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  refuse "[SP-NO-GIT]: git could not read $PROJ as a work tree, so whether this turn leaves the spec record unstaged cannot be checked, and a check that could not run has not passed. Run git status there to see the failure (git missing from PATH, a corrupt .git, or a directory that is not the instance root all look like this), repair it, then end the turn."
fi
if ! STATUS="$(git -C "$PROJ" status --porcelain=v1 --untracked-files=all -- specs/ 2>/dev/null)"; then
  refuse "[SP-NO-GIT]: git status failed under $PROJ/specs, so whether this turn leaves the spec record unstaged cannot be checked, and a check that could not run has not passed. Run git status there to see the failure, repair it, then end the turn."
fi

# UNSTAGED means the working tree differs from the index: porcelain's second
# column is not a space (modified, deleted, type-changed), or the entry is
# untracked (??). A change that is STAGED is the session's deliberate act and
# is allowed to stand at the end of a turn; the record it will become is in the
# index, and the commit is the next thing the protocol asks for.
UNSTAGED_STATUS=""; UNSTAGED_SPECS=""
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  x="${line:0:1}"; y="${line:1:1}"; path="${line:3}"
  case "$path" in *' -> '*) path="${path##* -> }" ;; esac
  case "$path" in \"*\") path="${path#\"}"; path="${path%\"}" ;; esac
  if [[ "$x$y" == "??" || "$y" != " " ]]; then
    case "$path" in
      specs/STATUS.md) UNSTAGED_STATUS="$path" ;;
      *) UNSTAGED_SPECS="${UNSTAGED_SPECS:+$UNSTAGED_SPECS, }$path" ;;
    esac
  fi
done <<< "$STATUS"

if [[ -n "$UNSTAGED_STATUS" && -n "$UNSTAGED_SPECS" ]]; then
  refuse "[SP-UNSTAGED-STATUS]: specs/STATUS.md is changed and not staged, and so is the spec record ($UNSTAGED_SPECS). A turn that ends here leaves the inventory and the record disagreeing with what is committed, and the next session re-grounds on the committed page. Stage them (git add specs/) and commit them with the work they describe, or restore them (git checkout -- specs/STATUS.md, git restore <file>) if the edit was not meant, then end the turn. This hook refuses once; the continuation it grants passes."
elif [[ -n "$UNSTAGED_STATUS" ]]; then
  refuse "[SP-UNSTAGED-STATUS]: specs/STATUS.md is changed and not staged. A turn that ends here leaves the inventory page disagreeing with what is committed, and the next session re-grounds on the committed page. Stage it (git add specs/STATUS.md) and commit it with the work it describes, or restore it (git checkout -- specs/STATUS.md) if the edit was not meant, then end the turn. This hook refuses once; the continuation it grants passes."
elif [[ -n "$UNSTAGED_SPECS" ]]; then
  refuse "[SP-UNSTAGED-SPEC]: the spec record is changed and not staged ($UNSTAGED_SPECS). A turn that ends here leaves the record disagreeing with what is committed, and the next session re-grounds on the committed page. Stage it (git add specs/) and commit it with the work it describes, or restore it (git restore <file>) if the edit was not meant, then end the turn. This hook refuses once; the continuation it grants passes."
fi

# fail-open-ok: every file under specs/ is committed or staged, which is the
# state this hook exists to reach; silence is the allow.
exit 0
