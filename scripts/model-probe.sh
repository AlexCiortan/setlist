#!/usr/bin/env bash
# The model binding, re-probed: which model does each phase of `opusplan` serve
# on this machine, now? (spec 0177, C-65 of the weekly scan of 2026-09-28)
#
# Usage: model-probe.sh [--claude <bin>]     (default: `claude` on PATH)
#
# Why this exists. `/setlist:new` and `/setlist:retrofit` verify `opusplan` by a
# live probe at bootstrap and record `opusplan_verified` as a yes or a no. That
# answer names no version, and it is never asked again. Since Claude Code
# 2.1.283 a managed allowlist can pin exact versions (`availableModelsMatch:
# "exact"`) or deny one (`deniedModels`), and the harness does not REFUSE a
# blocked planning model: it substitutes, the plan phase falling to the newest
# permitted Opus or staying on Sonnet when every Opus is excluded (the
# model-configuration page, read 2026-09-29). An instance stamped months earlier
# then plans on a model its bindings never named, and nothing says so. So the
# refusal is this script's: it runs both phases and names a phase served off its
# tier.
#
# What it runs: two short headless sessions, `claude -p --model opusplan` with
# and without `--permission-mode plan` (plan mode is what makes `opusplan` serve
# its planning model), each asked for one word, from a fresh scratch directory
# so no instance hook or project setting enters the probe. Managed and user
# settings still apply, and those are where an allowlist lives (both keys are
# read from managed settings only). The sessions spend a little of the user's
# quota; the first line of output says so before either runs.
#
# THE SERVED MODEL is the one `modelUsage` entry whose output tokens equal the
# result's `usage.output_tokens`, never the first key: the harness lists an
# auxiliary Haiku it uses for its own housekeeping, and it sorts first. A
# reading that cannot be taken (no usage block, no unique match) is no name,
# never a guess. This restates the private probe library's E13 predicate
# (dogfood/probes/lib.sh), which does not ship.
#
# THE TIER is judged by family and the version is printed, not judged: Part 2
# of the edition names the alias, not the version, so an exact allowlist that
# keeps the planning phase on an older Opus holds the tier and is a line, not a
# finding.
#
# Exit codes:
#   0  both phases served a model of their tier's family (each printed).
#   1  a phase was served off its tier: [MP-PLAN-OFF-TIER] or [MP-EXEC-OFF-TIER].
#   2  no reading: [MP-PROBE-UNAVAILABLE] (the probe did not run, errored, or
#      named no unique served model) or [MP-FAMILY-UNREADABLE] (the served id
#      names no model family, as a gateway's own deployment name can). Never a
#      pass: a check that could not look has not seen the tier hold.

set -u

CLAUDE_BIN="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude) CLAUDE_BIN="${2:-}"; shift 2 ;;
    *) printf 'model-probe.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf '[MP-PROBE-UNAVAILABLE] jq is not on PATH, so no result can be read; install jq and re-run.\n'
  exit 2
fi
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  printf '[MP-PROBE-UNAVAILABLE] the claude binary %s is not on PATH, so neither phase could be probed.\n' "$CLAUDE_BIN"
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/setlist-model-probe.XXXXXX")" || {
  printf '[MP-PROBE-UNAVAILABLE] could not create a scratch directory to probe from.\n'; exit 2; }
trap 'rm -rf "$WORKDIR"' EXIT

printf 'model-probe: running two short headless sessions (the plan and execution phases of opusplan); they spend a little of your quota.\n'

served_model() { # <result file> -> model id, or nothing when no unique entry matches
  jq -r '
    if (type != "object") then empty
    elif ((.usage | type) != "object") or ((.usage.output_tokens | type) != "number") then empty
    elif ((.modelUsage | type) != "object") then empty
    else .usage as $u
      | [ .modelUsage | to_entries[]
          | select((.value | type) == "object"
                   and (.value.outputTokens | type) == "number"
                   and .value.outputTokens == $u.output_tokens)
          | .key ]
      | if length == 1 then .[0] else empty end
    end' "$1" 2>/dev/null
}

family_of() { # <model id> -> opus | sonnet | haiku | fable, or nothing
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *opus*) printf 'opus' ;;
    *sonnet*) printf 'sonnet' ;;
    *haiku*) printf 'haiku' ;;
    *fable*) printf 'fable' ;;
  esac
}

UNAVAILABLE=0
OFF=0
probe_phase() { # <label> <expected family> <code> [claude args...]
  local label="$1" want="$2" code="$3" out rc id fam cost
  shift 3
  out="$WORKDIR/$label.json"
  ( cd "$WORKDIR" && "$CLAUDE_BIN" -p "$@" --model opusplan --output-format json \
      'Reply with the single word ok.' ) > "$out" 2> "$WORKDIR/$label.err"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '[MP-PROBE-UNAVAILABLE] %s: the probe exited %s: %s\n' "$label" "$rc" \
      "$(head -c 300 "$WORKDIR/$label.err" | tr '\n' ' ')"
    UNAVAILABLE=1; return
  fi
  if [[ "$(jq -r 'if type == "object" then (.is_error // false) else "unreadable" end' "$out" 2>/dev/null)" != "false" ]]; then
    printf '[MP-PROBE-UNAVAILABLE] %s: the result is an error or unreadable: %s\n' "$label" \
      "$(jq -r '.result // empty' "$out" 2>/dev/null | head -c 300)"
    UNAVAILABLE=1; return
  fi
  id="$(served_model "$out")"
  if [[ -z "$id" ]]; then
    printf '[MP-PROBE-UNAVAILABLE] %s: the result names no unique served model (modelUsage against usage).\n' "$label"
    UNAVAILABLE=1; return
  fi
  cost="$(jq -r '.total_cost_usd // empty' "$out" 2>/dev/null)"
  printf '%s: %s%s\n' "$label" "$id" "${cost:+ (cost $cost USD)}"
  fam="$(family_of "$id")"
  if [[ -z "$fam" ]]; then
    printf '[MP-FAMILY-UNREADABLE] %s: %s names no model family, so this probe cannot say whether the %s tier holds; read it against your provider'"'"'s model list.\n' \
      "$label" "$id" "$want"
    UNAVAILABLE=1; return
  fi
  if [[ "$fam" != "$want" ]]; then
    printf '[%s] the %s phase of opusplan was served %s, not a %s model. The harness substitutes a blocked model rather than refusing it: a managed availableModels list with availableModelsMatch "exact", a deniedModels entry, or a provider that does not serve the family. Ask whoever manages this machine'"'"'s settings to permit the model Part 2 binds, or bind the tier to a model you can reach.\n' \
      "$code" "$label" "$id" "$want"
    OFF=1
  fi
}

probe_phase plan opus MP-PLAN-OFF-TIER --permission-mode plan
probe_phase execution sonnet MP-EXEC-OFF-TIER

if [[ "$OFF" -eq 1 ]]; then exit 1; fi
if [[ "$UNAVAILABLE" -eq 1 ]]; then exit 2; fi
printf 'model-probe: both phases of opusplan served a model of their tier.\n'
exit 0
