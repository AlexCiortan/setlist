#!/usr/bin/env bash
# test/suite/03-trunk-rules-and-hook-audits.sh: shard 3 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# 1.0.4: a trunk merge that NAMES a resolvable non-spec ref is not a close.
# 1.0.3 denied these, which broke syncing your own trunk while `git pull`
# achieved the same result untouched: friction with no safety.
# =============================================================================

CL="$WORK/close-namedref"; close_fixture "$CL" yes yes answered yes no true
git -C "$CL" branch -f release/2.0 HEAD
git -C "$CL" update-ref refs/remotes/origin/main HEAD
for spelling in 'git merge origin/main' 'git merge --no-ff release/2.0' 'git merge main'; do
  run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$spelling")"
  expect_allow "close-gate named: [$spelling] is a sync, not a close, and is allowed"
done
# A ref that does NOT resolve cannot vouch for the merge: message words must
# not pose as branch names.
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge -m "closing spec" $B')"
expect_deny "close-gate named: message words do not count as a named ref" "cannot be verified"
# A compound must not donate the checkout's argument to the merge.
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git checkout main && git merge $B')"
expect_deny "close-gate named: the compound form does not donate 'main' to the merge" "cannot be verified"
# And the merge of a spec branch is still fully gated (0001 has no CLOSED row
# here only because close_fixture built it compliant; use the real close).
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate named: the compliant spec close still merges"

# =============================================================================
# 1.0.3, IN-1: an indirectly named trunk merge DENIES instead of passing.
# The 1.0.1 fix widened the ref parser; these cases pin the DISPOSITION: when
# the target is the trunk and the command matched the merge grammar but no
# spec/ or chore/ ref could be extracted, the gate refuses to guess. The
# fixture is fully COMPLIANT, so any deny below comes from the extraction
# refusal alone, not from a missing close artifact.
# =============================================================================

CL="$WORK/close-indirect"; close_fixture "$CL" yes yes answered yes no true

for spelling in \
  'B=spec/0001-thing; git merge --no-ff $B' \
  'git merge -' \
  'git merge @{-1}' \
  'git merge FETCH_HEAD' \
  'git merge --no-ff 1a2b3c4d'; do
  run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$spelling")"
  expect_deny "close-gate indirect: [$spelling] into the trunk is denied" "literally"
done

# --continue/--abort finish or cancel a merge that was gated on its way in;
# blocking them would strand a conflicted close.
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge --continue')"
expect_allow "close-gate indirect: git merge --continue is exempt from the extraction deny"
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge --abort')"
expect_allow "close-gate indirect: git merge --abort is exempt from the extraction deny"

# The deny is scoped to TRUNK targets: syncing the trunk INTO a feature branch
# names no spec/chore ref either, and must stay ungated.
git -C "$CL" checkout -q spec/0001-thing
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge main')"
expect_allow "close-gate indirect: merging the trunk into a feature branch stays ungated"
git -C "$CL" checkout -q main

# And the literal compliant form still merges (the deny must not overreach).
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate indirect: the literal compliant merge is still allowed"

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

TYPE_COUNT="$(grep -c '"type": "command"' "$ROOT/templates/claude/settings.json.tmpl")"
TIMEOUT_COUNT="$(grep -c '"timeout":' "$ROOT/templates/claude/settings.json.tmpl")"
if [[ "$TYPE_COUNT" -eq 0 ]]; then
  bad "timeout a: every command hook in the template carries a timeout" \
      "found zero command hooks in the template; the check exercised nothing"
elif [[ "$TYPE_COUNT" -eq "$TIMEOUT_COUNT" ]]; then
  ok "timeout a: all $TYPE_COUNT command hooks in the template carry an explicit timeout"
else
  bad "timeout a: every command hook in the template carries a timeout" \
      "$TYPE_COUNT command hooks but $TIMEOUT_COUNT timeout keys"
fi

# =============================================================================
# 1.0.3, IN-4: git rm and git mv stage during command execution, after the
# gate scanned the index; compounded with a commit they are the git-add hole
# in different spelling.
# =============================================================================

RMV="$WORK/commit-rmv"
git_init "$RMV"
sdd_json "$RMV"

run_hook "$HOOKS/commit-gate.sh" "$RMV" "$(bash_payload 'git rm seed.txt && git commit -m "drop seed"')"
expect_deny "commit-gate rm: compound git rm plus commit is denied" "one step"
run_hook "$HOOKS/commit-gate.sh" "$RMV" "$(bash_payload 'git mv seed.txt seed2.txt && git commit -m "rename seed"')"
expect_deny "commit-gate mv: compound git mv plus commit is denied" "one step"
# Refusals must leave the tree untouched (the deny fired before the command ran).
if [[ -f "$RMV/seed.txt" && ! -e "$RMV/seed2.txt" ]]; then
  ok "commit-gate rm/mv: the denied compounds touched nothing"
else
  bad "commit-gate rm/mv: the denied compounds touched nothing" "seed.txt moved or vanished"
fi
# A message merely MENTIONING git rm stays allowed (quote-strip guard).
run_hook "$HOOKS/commit-gate.sh" "$RMV" "$(bash_payload 'git commit -m "docs: when to use git rm"')"
expect_allow "commit-gate rm-msg: a message mentioning git rm is not a compound"

# =============================================================================
# 1.0.3, IN-9: every exit 0 in a stamped hook justifies itself. A silent pass
# with no written reason is how IN-1 survived two releases: the reviewer
# found it by reading for unannotated exits, so the suite now reads for them
# forever. The annotation is `# fail-open-ok:` within the three lines above
# the exit.
# =============================================================================

FOK_TOTAL=0
for hook in scope-hook commit-gate close-gate regrounding-hook; do
  HF="$HOOKS/$hook.sh"
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
    ($0 ~ /(^|[;[:space:]])exit[[:space:]]*(0[[:space:]]*)?(;|$)/) && $0 !~ /^[[:space:]]*#/ {
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
for hook in scope-hook commit-gate close-gate regrounding-hook; do
  LAST="$(grep -vE '^[[:space:]]*(#|$)' "$HOOKS/$hook.sh" | tail -n1)"
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
# the audit above reads the four PreToolUse hooks and scripts/*.sh, and it had
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
  ok "fail-open audit: the scan exercised $FOK_TOTAL annotations across the four hooks"
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

