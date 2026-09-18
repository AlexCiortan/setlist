#!/usr/bin/env bash
# test/suite/03-trunk-rules-and-hook-audits.sh: shard 3 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# 1.0.3, IN-3: NotebookEdit reaches the trunk rule (notebook_path), and a
# pathless write-tool event denies instead of slipping through.
# =============================================================================

NB="$WORK/scope-notebook"
git_init "$NB"
sdd_json "$NB"

notebook_payload() { # notebook_payload <notebook_path>
  jq -nc --arg p "$1" '{tool_name:"NotebookEdit", tool_input:{notebook_path:$p}}'
}

run_hook "$HOOKS/scope-hook.sh" "$NB" "$(notebook_payload "$NB/src/model.ipynb")"
expect_deny "scope nb-a: NotebookEdit into src/ on the trunk is denied" "never lands"

git -C "$NB" checkout -q -b spec/0002-notebooks
run_hook "$HOOKS/scope-hook.sh" "$NB" "$(notebook_payload "$NB/src/model.ipynb")"
expect_allow "scope nb-b: NotebookEdit into src/ on a spec branch is allowed"
git -C "$NB" checkout -q main

# A matched write tool that carries NEITHER path field is a harness-shape
# change the gate cannot evaluate; it denies rather than guessing (this was
# the exact silent path NotebookEdit used to take).
run_hook "$HOOKS/scope-hook.sh" "$NB" "$(jq -nc '{tool_name:"Edit", tool_input:{}}')"
expect_deny "scope nb-c: a pathless write-tool event on the trunk is denied" "neither file_path nor notebook_path"

# Off the trunk the pathless event stays silent: the gate only guards the trunk.
git -C "$NB" checkout -q spec/0002-notebooks
run_hook "$HOOKS/scope-hook.sh" "$NB" "$(jq -nc '{tool_name:"Edit", tool_input:{}}')"
expect_allow "scope nb-d: a pathless write-tool event off the trunk is allowed"
git -C "$NB" checkout -q main

# The template wires the full write-tool matcher set.
if grep -q '"matcher": "Write|Edit|MultiEdit|NotebookEdit"' "$ROOT/templates/claude/settings.json.tmpl"; then
  ok "scope nb-e: settings.json.tmpl wires the full write-tool matcher set"
else
  bad "scope nb-e: settings.json.tmpl wires the full write-tool matcher set" \
      "the Write|Edit|MultiEdit|NotebookEdit matcher is missing from the template"
fi

# =============================================================================
# 1.0.3, IN-2: every command hook in the template carries an explicit timeout.
# A timed-out hook is cancelled by the harness and the tool call proceeds, so
# a hook with no timeout key is a gate wearing the harness default as a
# silent ceiling.
# =============================================================================

# ENTRIES, NOT LINES (CHK-SUITE's timeout arm, 0148's E-4, taken in spec 0150).
# The count was two greps, so a newline-stripped template was ONE line and
# passed having evaluated one entry. It now reads the template as JSON: every
# command hook under every event, and those whose timeout is a number. The
# {{IF:...}} markers are resolved by deleting the marker, not the line, because
# the suite's `grep -v '^{{IF:'` would erase a one-line template whole.
timeout_entries() { # timeout_entries <template> -> "<commands> <with a numeric timeout>", or nothing when unparseable
  sed -e 's/{{IF:[A-Z_]*}}//' -e 's/{{[A-Z_]*}}/x/g' "$1" \
    | jq -r '[.hooks[][] | .hooks[] | select(.type == "command")] | "\(length) \([.[] | select(.timeout | type == "number")] | length)"' 2>/dev/null
}
TO_MUT="$WORK/settings-oneline.tmpl"
awk '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) if (!d && l[i] ~ /"timeout":/) { sub(/,[[:space:]]*$/, "", l[i-1]); skip[i] = 1; d = 1 }
                         for (i = 1; i <= NR; i++) if (!skip[i]) print l[i] }' "$ROOT/templates/claude/settings.json.tmpl" > "$TO_MUT.a"
tr -d '\n' < "$TO_MUT.a" > "$TO_MUT"
TO_MUT_READ="$(timeout_entries "$TO_MUT")"
if [[ -n "$TO_MUT_READ" && "${TO_MUT_READ% *}" -ne "${TO_MUT_READ#* }" ]]; then
  ok "timeout b: a newline-stripped template with one entry's timeout removed is caught ($TO_MUT_READ)"
else
  bad "timeout b: a newline-stripped template with one entry's timeout removed is caught" \
      "read '${TO_MUT_READ:-<unparseable>}'; the count cannot see the entry it lost"
fi
TO_READ="$(timeout_entries "$ROOT/templates/claude/settings.json.tmpl")"
TYPE_COUNT="${TO_READ% *}"; TIMEOUT_COUNT="${TO_READ#* }"
if [[ -z "$TO_READ" ]]; then
  bad "timeout a: every command hook in the template carries a timeout" \
      "the template did not parse as JSON with its markers resolved; the check exercised nothing"
elif [[ "$TYPE_COUNT" -eq 0 ]]; then
  bad "timeout a: every command hook in the template carries a timeout" \
      "found zero command hooks in the template; the check exercised nothing"
elif [[ "$TYPE_COUNT" -eq "$TIMEOUT_COUNT" ]]; then
  ok "timeout a: all $TYPE_COUNT command hooks in the template carry an explicit timeout"
else
  bad "timeout a: every command hook in the template carries a timeout" \
      "$TYPE_COUNT command hooks but $TIMEOUT_COUNT timeout keys"
fi

# =============================================================================
# 1.0.3, IN-9: every exit 0 in a stamped hook justifies itself. A silent pass
# with no written reason is how IN-1 survived two releases: the reviewer
# found it by reading for unannotated exits, so the suite now reads for them
# forever. The annotation is `# fail-open-ok:` within the three lines above
# the exit.
# =============================================================================

# EVERY SESSION HOOK, BY GLOB, WITH A COUNT (F16 of the 2.8.0 leg, spec 0148).
# This loop named three hooks, `stop-hook.sh` was the stamped fourth, and a
# hardcoded list with no count reports nothing about the file it forgot. So it
# reads templates/hooks/*.sh and asserts the count equals the hooks the settings
# template wires, the shape the git-hooks loop below already uses.
#
# NO KNOWN SITES. Spec 0148 pinned stop-hook.sh's two out-of-window annotations
# with a staleness assertion owed to that hook's next edit; spec 0150 (DE11's fix,
# 0148's E-2) moved both inside the window and retired the pins with it.
FOK_TOTAL=0
FOK_HOOK_N=0
for HF in "$HOOKS"/*.sh; do
  [[ -f "$HF" ]] || continue
  hook="$(basename "$HF" .sh)"
  FOK_HOOK_N=$((FOK_HOOK_N + 1))
  UNANNOTATED="$(awk '
    { lines[NR] = $0 }
    # A BARE `exit` exits with the status of the last command, which is 0 far
    # more often than not, so it is a silent pass wearing different clothes. The
    # audit matched the literal string `exit 0` and could not see it, which is
    # item 26 exactly (grep-enforced, not meaning-enforced) and was found live by
    # the third 1.0.8 leg rather than remembered off the backlog.
    #
    # `exit 1`, `exit 2` and `exit "$rc"` are deliberately NOT matched: the first
    # two are refusals and the third is a status this audit cannot evaluate, so
    # flagging it would be noise that trains people to ignore the check.
    #
    # The match reads the CODE, not a trailing comment: `refuse() { # ... exit 0`
    # in stop-hook.sh matched on its comment text (found by F16 of the leg), a false
    # positive. A ` # ` after code starts a comment; `${#x}` has no space before.
    {
      code = $0
      sub(/[[:space:]]#[[:space:]].*$/, "", code)
    }
    (code ~ /(^|[;[:space:]])exit[[:space:]]*(0[[:space:]]*)?(;|$)/) && $0 !~ /^[[:space:]]*#/ {
      ok = 0
      for (i = NR - 3; i < NR; i++) if (lines[i] ~ /fail-open-ok/) ok = 1
      if (!ok) print NR": "$0
    }' "$HF")"
  ANNOTATED_N="$(grep -c 'fail-open-ok' "$HF")"
  FOK_TOTAL=$((FOK_TOTAL + ANNOTATED_N))
  if [[ -z "$UNANNOTATED" ]]; then
    ok "fail-open audit: every exit 0 in $hook.sh is annotated ($ANNOTATED_N justifications)"
  else
    bad "fail-open audit: every exit 0 in $hook.sh is annotated" \
        "unannotated silent passes: $UNANNOTATED"
  fi
done
# The audit greps for `exit 0`, so a hook that simply FALLS OFF THE END has no
# literal exit to annotate and passes the scan reporting nothing (1.0.4: found
# by review, latent rather than live, since all four hooks end explicitly
# today). A hook that ends by falling through exits with whatever its last
# command returned, which is a silent pass nobody wrote down. Require the last
# effective line of every hook to be an explicit exit.
FOK_WIRED_N="$(grep -oE '/\.claude/hooks/[A-Za-z0-9_-]+\.sh' "$ROOT/templates/claude/settings.json.tmpl" | sort -u | grep -c .)"
if [[ "$FOK_HOOK_N" -ge 4 && "$FOK_HOOK_N" -eq "$FOK_WIRED_N" ]]; then
  ok "fail-open audit: all $FOK_HOOK_N session hooks were read, the $FOK_WIRED_N the settings template wires"
else
  bad "fail-open audit: every session hook the settings template wires was read" \
      "read $FOK_HOOK_N files under templates/hooks/, the template wires $FOK_WIRED_N; a hook outside this audit is a silent pass nobody reads"
fi
for HF in "$HOOKS"/*.sh; do
  [[ -f "$HF" ]] || continue
  hook="$(basename "$HF" .sh)"
  LAST="$(grep -vE '^[[:space:]]*(#|$)' "$HF" | tail -n1)"
  case "$LAST" in
    exit\ [0-9]*) ok "fail-open audit: $hook.sh ends with an explicit exit" ;;
    *) bad "fail-open audit: $hook.sh ends with an explicit exit" \
           "ends with '$LAST', so it falls through with the previous command's status: a silent pass with no annotation to audit" ;;
  esac
done

# The same discipline, extended to scripts/ (1.0.5). The 1.0.3 wiring bug was
# NOT in a hook, so the audit above could never have seen it: a `|| true`
# swallowed grep's non-zero exit, the captured value made a numeric comparison
# a silent syntax error, and the check passed on exactly the input it existed
# to catch. `|| true` is the idiom that discards an error, so in scripts that
# CHECK things it is the place a predicate goes unevaluated. Each site must
# say why discarding the error is correct there.
SCRIPT_FOK=0
for s in "$SCRIPTS"/*.sh; do
  [[ -f "$s" ]] || continue
  sname="$(basename "$s")"
  UNJUSTIFIED="$(awk '
    { lines[NR] = $0 }
    /\|\| true/ && $0 !~ /^[[:space:]]*#/ {
      ok = 0
      for (i = NR - 3; i <= NR; i++) if (lines[i] ~ /fail-open-ok/) ok = 1
      if (!ok) print NR": "$0
    }' "$s")"
  if [[ -z "$UNJUSTIFIED" ]]; then
    ok "fail-open audit (scripts): every error-discarding site in $sname is justified"
  else
    bad "fail-open audit (scripts): every error-discarding site in $sname is justified" \
        "unjustified '|| true':$(printf '\n       %s' "$UNJUSTIFIED")"
  fi
  SCRIPT_FOK=$((SCRIPT_FOK + 1))
done
if [[ "$SCRIPT_FOK" -ge 3 ]]; then
  ok "fail-open audit (scripts): $SCRIPT_FOK scripts were scanned"
else
  bad "fail-open audit (scripts): the scan found scripts to read" \
      "only $SCRIPT_FOK scripts scanned; scripts/ should hold several"
fi

# THE SAME DISCIPLINE, EXTENDED TO THE GIT HOOKS (v1.7 dogfood gate, F26).
#
# This is the structural finding of that gate, and it is worth stating plainly:
# the audit above reads the session hooks and scripts/*.sh, and it had
# NEVER read templates/git-hooks/. v1.7 moved the enforcement guarantee into that
# directory and the tool whose entire job is finding silent passes was not
# looking at it. Eleven unannotated exit sites lived there, one of which was the
# BLOCKER: pre-merge-commit's `exit 0` for "not on the trunk", taken without ever
# evaluating its predicate because slh_trunk returned an unreduced ref path.
#
# A gate is only as good as the set of files its auditor knows about, and that
# set is a list somebody has to remember to extend. This is that extension, and
# the count assertion below is what makes forgetting it visible.
GITHOOK_FOK=0
GITHOOK_ANN=0
for g in "$ROOT"/templates/git-hooks/*; do
  [[ -f "$g" ]] || continue
  gname="$(basename "$g")"
  GH_UNANN="$(awk '
    { lines[NR] = $0 }
    ($0 ~ /(^|[;[:space:]])exit[[:space:]]*(0[[:space:]]*)?(;|$)/) && $0 !~ /^[[:space:]]*#/ {
      ok = 0
      for (i = NR - 3; i < NR; i++) if (lines[i] ~ /fail-open-ok/) ok = 1
      if (!ok) print NR": "$0
    }
    /\|\| true/ && $0 !~ /^[[:space:]]*#/ {
      ok = 0
      for (i = NR - 3; i <= NR; i++) if (lines[i] ~ /fail-open-ok/) ok = 1
      if (!ok) print NR": "$0
    }' "$g")"
  GH_ANN_N="$(grep -c 'fail-open-ok' "$g" || true)"
  GITHOOK_ANN=$((GITHOOK_ANN + GH_ANN_N))
  if [[ -z "$GH_UNANN" ]]; then
    ok "fail-open audit (git hooks): every silent-pass site in $gname is annotated"
  else
    bad "fail-open audit (git hooks): every silent-pass site in $gname is annotated" \
        "unannotated silent passes:$(printf '\n       %s' "$GH_UNANN")"
  fi
  GITHOOK_FOK=$((GITHOOK_FOK + 1))
done
# The scan must have found the directory at all. A loop over a path that does not
# match reports nothing and reads as clean, which is the defect class this whole
# block exists for.
if [[ "$GITHOOK_FOK" -ge 4 ]]; then
  ok "fail-open audit (git hooks): $GITHOOK_FOK git-hook files were scanned"
else
  bad "fail-open audit (git hooks): the scan found the git hooks to read" \
      "only $GITHOOK_FOK scanned; templates/git-hooks/ ships pre-commit, pre-merge-commit, pre-push and the library"
fi

# The audit must have exercised something: four hooks with zero annotations
# between them means the scan broke, not that the hooks are clean.
if [[ "$FOK_TOTAL" -ge 10 ]]; then
  ok "fail-open audit: the scan exercised $FOK_TOTAL annotations across the audited hooks"
else
  bad "fail-open audit: the scan exercised the hooks" \
      "only $FOK_TOTAL fail-open-ok annotations found; the audit covered almost nothing"
fi

# =============================================================================
# Reference integrity (parked by the artifact-fidelity chore, riding 1.0.3):
# every ${CLAUDE_PLUGIN_ROOT} path named in shipped skills and templates
# resolves in this tree. The publish script runs the same sweep over the
# staged export (gate 5f); this is the suite-side half, so a stale reference
# fails CI on the push that creates it instead of at the next publish.
# =============================================================================

REF_MISS=""
REF_N=0
REFS="$(grep -rohE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' "$ROOT/skills" "$ROOT/templates" 2>/dev/null | sort -u || true)"
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  p="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  p="${p%.}"
  REF_N=$((REF_N + 1))
  [[ -e "$ROOT/$p" ]] || REF_MISS="$REF_MISS $p"
done <<EOF
$REFS
EOF
if [[ "$REF_N" -eq 0 ]]; then
  bad "reference integrity: plugin-root paths in skills/templates resolve" \
      "extracted zero references; the tree is known to carry them, so the sweep is broken"
elif [[ -z "$REF_MISS" ]]; then
  ok "reference integrity: all $REF_N plugin-root paths named in skills/templates resolve"
else
  bad "reference integrity: plugin-root paths in skills/templates resolve" \
      "stale references:$REF_MISS"
fi

