# Shard 19: the probe seed (spec 0151). Sourced by test/run-tests.sh.
#
# =============================================================================
# THE PROBE LIBRARY'S FIVE CONTRACTS, ONE CASE GROUP PER TECHNIQUE, NO QUOTA
# (spec 0151; specs/0149-v2.9.0-intake.md section 3).
#
# A probe that drives a real session answers a question about the HARNESS, and
# every way it can be wrong looks like an answer: an auxiliary model read as the
# served one (E13), a turn budget spent on denied tools read as a refusal (E12,
# E14), a fixture write that returned success and left half a file (E15), a
# classifier block on an identical command read as the thing measured (E11), and
# a BLOCKED run collapsed into NOT-SEEN. Each case below seeds exactly one of
# those and asserts the library keeps it apart. Nothing here runs claude.
#
# THE FIXTURES ARE RECORDED, NOT WRITTEN BY HAND (test/fixtures/probes/). The
# auxiliary-model and turn-exhausted results and the stream transcript were
# recorded from `claude -p` at CLI 2.1.274 on 2026-09-17 and trimmed to the
# result-shape keys (session ids and paths dropped); the single-model result is
# 2.8.0's cold round 4 raw output with its long result text replaced by "[]".
#
# THE LIBRARY IS PRIVATE TOOLING. The export does not carry it, so this region
# reports one SKIPPED line there, the precedent shards 09 and 14 set.
# =============================================================================
# >>> SHARD-BEGIN probe-seed-0151 cost=3
if shard_region probe-seed-0151; then

PSL_LIB="$ROOT/dogfood/probes/lib.sh"
PSL_FIX="$ROOT/test/fixtures/probes"

if [[ ! -f "$PSL_LIB" ]]; then
  ok "probe seed: SKIPPED, the probe library is not present in this tree (export copy)"
else
# The library is sourced in a subshell per group, so a function it defines, or a
# variable it sets, cannot reach any other region.
PSL_W="$(mktemp -d "${TMPDIR:-/tmp}/probe-seed.XXXXXX")"

# --- 1. served-model detection (E13) ------------------------------------------
# The hazard first, so the matcher case measures something: in the recorded
# auxiliary result the FIRST modelUsage key is the auxiliary Haiku entry, so any
# reader that takes a key by position names the wrong model.
psl_first_key="$(jq -r '.modelUsage | keys[0]' "$PSL_FIX/result-served-sonnet-aux-haiku.json" 2>/dev/null)"
if [[ "$psl_first_key" == claude-haiku-* ]]; then
  ok "probe seed E13 control: the recorded result lists the auxiliary Haiku entry first, so position is not the served model"
else
  bad "probe seed E13 control: the recorded result lists the auxiliary Haiku entry first" "first key read '$psl_first_key'; the matcher cases below would not be discriminating"
fi
psl_served="$( (source "$PSL_LIB" && probe_served_model "$PSL_FIX/result-served-sonnet-aux-haiku.json") 2>&1)"
[[ "$psl_served" == "claude-sonnet-5" ]] \
  && ok "probe seed E13: the served model is the modelUsage entry whose tokens equal usage, not the auxiliary Haiku" \
  || bad "probe seed E13: the served model is the entry matching usage" "read '$psl_served', wanted claude-sonnet-5"
psl_served="$( (source "$PSL_LIB" && probe_served_model "$PSL_FIX/result-error-max-turns.json") 2>&1)"
[[ "$psl_served" == "claude-sonnet-5" ]] \
  && ok "probe seed E13: a turn-exhausted result still names its served model" \
  || bad "probe seed E13: a turn-exhausted result still names its served model" "read '$psl_served'"
psl_served="$( (source "$PSL_LIB" && probe_served_model "$PSL_FIX/result-served-haiku-only.json") 2>&1)"
[[ "$psl_served" == "claude-haiku-4-5-20251001" ]] \
  && ok "probe seed E13: a session served by Haiku is read as Haiku" \
  || bad "probe seed E13: a session served by Haiku is read as Haiku" "read '$psl_served'"
psl_served="$( (source "$PSL_LIB" && probe_served_model "$PSL_FIX/stream-served-sonnet.jsonl") 2>&1)"
[[ "$psl_served" == "claude-sonnet-5" ]] \
  && ok "probe seed E13: a stream-json transcript is read at its result line" \
  || bad "probe seed E13: a stream-json transcript is read at its result line" "read '$psl_served'"
jq '.usage.output_tokens = 1' "$PSL_FIX/result-served-sonnet-aux-haiku.json" > "$PSL_W/nomatch.json"
psl_served="$( (source "$PSL_LIB" && probe_served_model "$PSL_W/nomatch.json"); printf ' rc=%s' "$?")"
[[ "$psl_served" == " rc=1" ]] \
  && ok "probe seed E13: no entry matching usage is rc 1 and no name, never a guess" \
  || bad "probe seed E13: no entry matching usage is rc 1 and no name" "read '$psl_served'"

# --- 2. allowlist, never denylist (E14) ---------------------------------------
psl_argv="$( (source "$PSL_LIB" && probe_claude_argv "" -p hi && printf '%s|' "${PROBE_ARGV[@]}") 2>&1)"
[[ "$psl_argv" == "--tools|SetlistProbeNoSuchTool|-p|hi|" ]] \
  && ok "probe seed E14: a pure-text probe is given one tool that does not exist" \
  || bad "probe seed E14: a pure-text probe is given one tool that does not exist" "argv '$psl_argv'"
psl_argv="$( (source "$PSL_LIB" && probe_claude_argv "Write" -p hi && printf '%s|' "${PROBE_ARGV[@]}") 2>&1)"
[[ "$psl_argv" == "--tools|Write|-p|hi|" ]] \
  && ok "probe seed E14: a probe is given exactly the tools it names" \
  || bad "probe seed E14: a probe is given exactly the tools it names" "argv '$psl_argv'"
for psl_flag in --disallowedTools --disallowed-tools --tools; do
  psl_argv="$( (source "$PSL_LIB" && probe_claude_argv "Write" -p hi "$psl_flag" Bash; printf 'rc=%s' "$?") 2>/dev/null)"
  [[ "$psl_argv" == "rc=2" ]] \
    && ok "probe seed E14: $psl_flag in a probe's own arguments is refused, rc 2" \
    || bad "probe seed E14: $psl_flag in a probe's own arguments is refused" "read '$psl_argv'"
done

# --- 3. verify-after-write (E15) ----------------------------------------------
psl_content="$(printf 'line one\nline two, the instruction\n\n')"$'\n'
psl_r="$( (source "$PSL_LIB" && probe_write_verified "$PSL_W/ok.txt" "$psl_content"; printf 'rc=%s' "$?") 2>&1)"
if [[ "$psl_r" == "rc=0" ]] && cmp -s "$PSL_W/ok.txt" <(printf '%s' "$psl_content"); then
  ok "probe seed E15: a write is read back byte for byte, trailing newlines included"
else
  bad "probe seed E15: a write is read back byte for byte" "read '$psl_r'"
fi
# A writer that truncates on its first call only: rewritten once, then verified.
psl_r="$( (source "$PSL_LIB"
  psl_calls=0
  psl_trunc_once() { psl_calls=$((psl_calls + 1)); if [[ "$psl_calls" -eq 1 ]]; then printf '%s' "${2:0:5}" > "$1"; else printf '%s' "$2" > "$1"; fi; }
  PROBE_WRITER=psl_trunc_once probe_write_verified "$PSL_W/once.txt" "$psl_content"; printf 'rc=%s calls=%s' "$?" "$psl_calls") 2>/dev/null)"
[[ "$psl_r" == "rc=0 calls=2" ]] \
  && ok "probe seed E15: a truncated write is rewritten once and then verifies" \
  || bad "probe seed E15: a truncated write is rewritten once and then verifies" "read '$psl_r'"
psl_r="$( (source "$PSL_LIB"
  psl_calls=0
  psl_trunc_always() { psl_calls=$((psl_calls + 1)); printf '%s' "${2:0:5}" > "$1"; }
  PROBE_WRITER=psl_trunc_always probe_write_verified "$PSL_W/always.txt" "$psl_content"; printf 'rc=%s calls=%s' "$?" "$psl_calls") 2>/dev/null)"
[[ "$psl_r" == "rc=3 calls=2" ]] \
  && ok "probe seed E15: a second mismatch is BLOCKED (rc 3) after exactly one rewrite" \
  || bad "probe seed E15: a second mismatch is BLOCKED after exactly one rewrite" "read '$psl_r'"

# --- 4. retry-once (E11, E12) -------------------------------------------------
psl_c="$( (source "$PSL_LIB" && probe_classify "$PSL_FIX/result-error-max-turns.json") 2>&1)"
[[ "$psl_c" == "BLOCKED error_max_turns" ]] \
  && ok "probe seed E12: a recorded turn-exhausted run classifies BLOCKED, never as the thing measured" \
  || bad "probe seed E12: a recorded turn-exhausted run classifies BLOCKED" "read '$psl_c'"
psl_c="$( (source "$PSL_LIB" && probe_classify "$PSL_FIX/stream-served-sonnet.jsonl") 2>&1)"
[[ "$psl_c" == "OK" ]] \
  && ok "probe seed E11: a recorded completed transcript classifies OK" \
  || bad "probe seed E11: a recorded completed transcript classifies OK" "read '$psl_c'"
: > "$PSL_W/empty.json"
jq '.result = ""' "$PSL_FIX/result-served-sonnet-aux-haiku.json" > "$PSL_W/emptyresult.json"
jq '.is_error = true | .result = "API Error: 529 overloaded"' "$PSL_FIX/result-served-sonnet-aux-haiku.json" > "$PSL_W/apierror.json"
printf 'not json\n' > "$PSL_W/garbage.json"
psl_c="$( (source "$PSL_LIB"; for f in empty emptyresult apierror garbage; do probe_classify "$PSL_W/$f.json" | awk '{printf "%s;", $1}'; done) 2>&1)"
[[ "$psl_c" == "BLOCKED;BLOCKED;BLOCKED;BLOCKED;" ]] \
  && ok "probe seed E11: an empty output, an empty result, an API error and unparseable output each classify BLOCKED" \
  || bad "probe seed E11: empty output, empty result, API error and garbage each classify BLOCKED" "read '$psl_c'"
psl_r="$( (source "$PSL_LIB"
  psl_n=0
  psl_blocked_then_ok() { psl_n=$((psl_n + 1)); if [[ "$psl_n" -eq 1 ]]; then cp "$PSL_FIX/result-error-max-turns.json" "$1"; else cp "$PSL_FIX/result-served-sonnet-aux-haiku.json" "$1"; fi; }
  probe_run psl_blocked_then_ok "$PSL_W/run1.json"; printf 'rc=%s attempts=%s state=%s calls=%s' "$?" "$PROBE_ATTEMPTS" "$PROBE_RUN_STATE" "$psl_n") 2>&1)"
[[ "$psl_r" == "rc=0 attempts=2 state=OK calls=2" ]] \
  && ok "probe seed E11: a BLOCKED run is retried once with identical inputs and the retry's answer stands" \
  || bad "probe seed E11: a BLOCKED run is retried once and the retry stands" "read '$psl_r'"
psl_r="$( (source "$PSL_LIB"
  psl_n=0
  psl_always_blocked() { psl_n=$((psl_n + 1)); cp "$PSL_FIX/result-error-max-turns.json" "$1"; }
  probe_run psl_always_blocked "$PSL_W/run2.json"; printf 'rc=%s attempts=%s state=%s calls=%s reason=%s' "$?" "$PROBE_ATTEMPTS" "$PROBE_RUN_STATE" "$psl_n" "$PROBE_BLOCKED_REASON") 2>&1)"
[[ "$psl_r" == "rc=3 attempts=2 state=BLOCKED calls=2 reason=error_max_turns" ]] \
  && ok "probe seed E11: a second BLOCKED is the outcome, after two attempts and never a third" \
  || bad "probe seed E11: a second BLOCKED is the outcome after two attempts" "read '$psl_r'"
psl_r="$( (source "$PSL_LIB"
  psl_n=0
  psl_ok() { psl_n=$((psl_n + 1)); cp "$PSL_FIX/stream-served-sonnet.jsonl" "$1"; }
  probe_run psl_ok "$PSL_W/run3.json"; printf 'rc=%s attempts=%s calls=%s' "$?" "$PROBE_ATTEMPTS" "$psl_n") 2>&1)"
[[ "$psl_r" == "rc=0 attempts=1 calls=1" ]] \
  && ok "probe seed E11: a run that completes is not retried" \
  || bad "probe seed E11: a run that completes is not retried" "read '$psl_r'"

# --- 5. four outcomes, never collapsed ----------------------------------------
psl_o="$( (source "$PSL_LIB"
  probe_arm_outcome BLOCKED yes yes yes; probe_arm_outcome BLOCKED no no no
  probe_arm_outcome OK no yes yes; probe_arm_outcome OK yes yes no
  probe_arm_outcome OK yes no yes; probe_arm_outcome OK yes yes yes
  probe_arm_outcome maybe yes yes yes) 2>&1 | tr '\n' ';')"
[[ "$psl_o" == "BLOCKED;BLOCKED;CONTROL-FAILED;NOT-SEEN;NOT-SEEN;SEEN;CONTROL-FAILED;" ]] \
  && ok "probe seed outcomes: BLOCKED never reads as NOT-SEEN, an unfired hook is CONTROL-FAILED, SEEN needs all three marks" \
  || bad "probe seed outcomes: the arm table" "read '$psl_o'"
psl_o="$( (source "$PSL_LIB"
  probe_pair_outcome SEEN NOT-SEEN PASS; probe_pair_outcome NOT-SEEN NOT-SEEN PASS
  probe_pair_outcome SEEN SEEN PASS; probe_pair_outcome SEEN NOT-SEEN FAIL
  probe_pair_outcome SEEN NOT-SEEN BLOCKED; probe_pair_outcome SEEN BLOCKED PASS
  probe_pair_outcome SEEN CONTROL-FAILED PASS; probe_pair_outcome SEEN NOT-SEEN pass) 2>&1 | tr '\n' ';')"
[[ "$psl_o" == "SEEN;NOT-SEEN;CONTROL-FAILED;CONTROL-FAILED;BLOCKED;BLOCKED;CONTROL-FAILED;CONTROL-FAILED;" ]] \
  && ok "probe seed outcomes: a SEEN twin or a failed deny control is CONTROL-FAILED, a BLOCKED anywhere is BLOCKED" \
  || bad "probe seed outcomes: the pair table" "read '$psl_o'"
psl_o="$( (source "$PSL_LIB"
  probe_result_line PRE SEEN 2.1.274 claude-sonnet-5 abc123; printf 'rc=%s;' "$?"
  probe_result_line PRE MAYBE 2.1.274 claude-sonnet-5 abc123; printf 'rc=%s;' "$?"
  probe_result_line PRE SEEN "" claude-sonnet-5 abc123; printf 'rc=%s;' "$?"
  probe_result_line PRE SEEN 2.1.274 "" abc123; printf 'rc=%s;' "$?"
  probe_result_line PRE SEEN 2.1.274 claude-sonnet-5 ""; printf 'rc=%s;' "$?") 2>/dev/null)"
[[ "$psl_o" == "PROBE-RESULT: PRE SEEN harness=2.1.274 served=claude-sonnet-5 tree=abc123"$'\n'"rc=0;rc=2;rc=2;rc=2;rc=2;" ]] \
  && ok "probe seed outcomes: a result line carries harness, served model and tree digest, and refuses without them or with an unknown outcome" \
  || bad "probe seed outcomes: the result line" "read '$psl_o'"
# The marks are read from what the MODEL said, never from what the hook injected:
# a nonce that appears only inside a tool result is not an echo.
{ printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"hook context NONCE-zz91","is_error":false}]}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I wrote the file."}]}}'
  tail -n 1 "$PSL_FIX/stream-served-sonnet.jsonl"; } > "$PSL_W/injected.jsonl"
psl_o="$( (source "$PSL_LIB" && probe_model_text "$PSL_W/injected.jsonl") 2>&1)"
if [[ "$psl_o" == *"I wrote the file."* && "$psl_o" == *"probe-stream"* && "$psl_o" != *NONCE-zz91* ]]; then
  ok "probe seed outcomes: the model's text excludes text that arrived only in a tool result"
else
  bad "probe seed outcomes: the model's text excludes tool-result text" "read '$psl_o'"
fi

rm -rf "$PSL_W"
fi
fi; shard_region_end
