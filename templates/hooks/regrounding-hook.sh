#!/usr/bin/env bash
# SDD re-grounding hook: SessionStart (no matcher: startup, resume, and
# post-compaction restarts alike), stamped into the instance. Delivers the
# read-budget pointer (edition Part 2) by mechanism: read specs/STATUS.md,
# then the active spec. Pointer, never content: inlining STATUS.md would
# bloat every session start and hand the session a copy that rots.
# Injection mechanic verified live 2026-07-07 on Claude Code 2.1.203:
# additionalContext JSON on stdout reaches the model verbatim, including
# under claude -p, with observed sources startup, resume, and compact.
# Requires jq. Without it this hook still delivers the pointer, and adds the
# warning that the three PreToolUse gates are now failing closed; it is the one
# hook that can report the condition before a deny surfaces it.
# Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

INPUT=$(cat)
PROJ="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)"

# Not an SDD instance, or pre-stamp: stay silent.
# fail-open-ok: not a gate; outside an instance there is nothing to point at.
[[ -f "$PROJ/.claude/sdd.json" ]] || exit 0
# Bootstrap phase 1 may run before STATUS.md exists; nothing to point at yet.
# fail-open-ok: not a gate; the pointer's target does not exist yet.
[[ -f "$PROJ/specs/STATUS.md" ]] || exit 0

# No jq: the pointer still ships, carrying the warning that the enforcement
# layer is down. Fixed literal, so no escaping (and no jq) is needed.
#
# JQ PRESENT IS NOT JQ USABLE (leg 4, F1), and here the consequence is worse
# than a missing warning. `command -v jq` passed for a jq that exists and exits
# nonzero, so the final `jq -Rs .` produced NOTHING and this hook emitted
#
#     {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":}}
#
# which is not JSON. So on the one machine where the three gates have silently
# stopped enforcing, the session start emitted a malformed object carrying no
# warning at all, and the notice the README promises never arrived. The warning
# is most needed in exactly the state that suppressed it.
#
# jq is RUN rather than located, and both failures take the literal path.
if ! command -v jq >/dev/null 2>&1 || ! printf '{}' | jq -e . >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"SDD re-grounding (the read budget, framework Part 2): before anything else, read specs/STATUS.md, then the active spec it names. WARNING: jq is not usable on this machine (it is missing, or it is installed but exits nonzero), so the three PreToolUse gates (scope, commit, close) are degraded and will report their verdict while PERMITTING the writes, commits and merges they govern, because they are advisory since v1.7; the git hooks are the layer that refuses, and they will refuse the commits and merges they govern until this is fixed. Run jq --version to see which it is, then install or repair jq (apt-get install jq, brew install jq, or the package manager for this system) before continuing."}}'
  # fail-open-ok: not a pass; the pointer plus the jq warning was delivered.
  exit 0
fi

SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || printf 'startup')"

case "$SOURCE" in
  compact)
    MSG="SDD re-grounding (post-compaction, framework Part 2): the context was just summarized, and a summary of the spec is not the spec. Re-read specs/STATUS.md and the ACTIVE spec it names before continuing."
    ;;
  resume)
    MSG="SDD re-grounding (resumed session, framework Part 2): re-read specs/STATUS.md and the active spec it names before continuing; the repo may have moved since this conversation last ran."
    ;;
  *)
    MSG="SDD re-grounding (the read budget, framework Part 2): before anything else, read specs/STATUS.md, then the active spec it names. Load owner docs only as the spec's header directs; everything else is reference material."
    ;;
esac

# SPEC DRIFT (BL-005). A spec edited after approval, mid-build, means the Builder
# is executing against text the Planner never approved. This warns; it cannot
# deny, because SessionStart has no deny mechanic, and pretending otherwise would
# be the kind of claim this framework spends its time removing.
#
# The recipe is documented in scripts/spec-hash.sh and implemented here INLINE,
# because a stamped hook runs inside an instance where the plugin tree may not be
# reachable. The suite drives both implementations over a corpus and asserts they
# agree on output.
#
# ABSENT FIELD IS SILENT, deliberately: every spec authored before v1.7 lacks it,
# and warning about those would train people to ignore this message before it had
# said anything true.
SPEC_NUM="$(awk -F'|' '
  function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
  NF >= 4 && toupper(trim($4)) == "ACTIVE" { print trim($2); exit }
' "$PROJ/specs/STATUS.md" 2>/dev/null || true)"

if [[ -n "$SPEC_NUM" ]]; then
  SPEC_FILE="$(ls "$PROJ/specs/${SPEC_NUM}"-*.md 2>/dev/null | head -n1 || true)"
  if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
    RECORDED="$(grep -m1 -E '^[-*+[:space:]]*Spec-hash:' "$SPEC_FILE" 2>/dev/null \
      | sed -E 's/^[-*+[:space:]]*Spec-hash:[[:space:]]*//' | tr -d '[:space:]' || true)"
    if [[ -n "$RECORDED" ]]; then
      # The tool probe carries its own outcome. A missing hasher must not read as
      # "no drift": that is the silent-stop this project keeps writing down.
      SPEC_HASHER=""
      if command -v sha256sum >/dev/null 2>&1; then SPEC_HASHER=sha256sum
      elif command -v shasum >/dev/null 2>&1; then SPEC_HASHER=shasum
      fi
      if [[ -z "$SPEC_HASHER" ]]; then
        MSG="$MSG

SPEC INTEGRITY: UNVERIFIED. Neither sha256sum nor shasum is available on this machine, so the active spec's Spec-hash could not be checked and this session cannot tell you whether ${SPEC_FILE##*/} changed after approval. That is not the same as no drift. Install coreutils or perl, then restart the session."
      else
        if [[ "$SPEC_HASHER" == "sha256sum" ]]; then
          ACTUAL="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' "$SPEC_FILE" | grep -v '^[-*+[:space:]]*Spec-hash:' | sha256sum | cut -d' ' -f1)"
        else
          ACTUAL="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' "$SPEC_FILE" | grep -v '^[-*+[:space:]]*Spec-hash:' | shasum -a 256 | cut -d' ' -f1)"
        fi
        # PRESENT IS NOT WORKING (redesign section 10, and the suite caught this
        # exact gap here). A hasher that exists and exits nonzero yields an empty
        # digest, and an empty digest compared against a recorded one is not
        # "no drift", it is no answer. Both no-tool and broken-tool report
        # UNVERIFIED; only a real digest is allowed to say anything else.
        if [[ -z "$ACTUAL" ]]; then
          MSG="$MSG

SPEC INTEGRITY: UNVERIFIED. A sha256 tool is installed but produced no digest on this machine, so the active spec's Spec-hash could not be checked and this session cannot tell you whether ${SPEC_FILE##*/} changed after approval. That is not the same as no drift. Run sha256sum --version (or shasum -a 256 </dev/null) to see the failure."
        elif [[ "$ACTUAL" != "$RECORDED" ]]; then
          MSG="$MSG

SPEC DRIFT: the active spec ${SPEC_FILE##*/} has CHANGED since it was approved. Its recorded Spec-hash does not match its current content above the Closing report. Stop and resolve this before building: either revert the edit, or route the change through Status REVISED with Planner sign-off and let /setlist:checkpoint rewrite the hash when it returns to ACTIVE. Building against text nobody approved is the failure this field exists to catch. (Edits to the Closing report itself are excluded from the hash and never trigger this.)"
        fi
      fi
    fi
  fi
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$MSG" | jq -Rs .)"
# fail-open-ok: not a gate; the re-grounding pointer above is the output.
exit 0
