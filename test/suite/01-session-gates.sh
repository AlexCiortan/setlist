#!/usr/bin/env bash
# test/suite/01-session-gates.sh: shard 1 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# close_fixture and MERGE_CMD: the shared spec-close fixture. The close gate it was
# written for left in 2.8.0 (spec 0144); the git-hook, audit and scope cases in
# later shards build their instances with it.
# =============================================================================

# close_fixture <dir> <closing> <qa> <diag> <statusrow> <dup> <gate_command>
#   closing:   yes|no      Closing report section present
#   qa:        yes|no|crossref|stray
#                yes       a PASS verdict between the QA Pass 1 and 2 fields
#                no        no verdict anywhere
#                crossref  QA-1 prose that cross-references QA Pass 2, ABOVE the
#                          verdict line: the 0112 field shape, which the bare
#                          substring anchor truncated into a false denial
#                stray     no verdict in the QA-1 block, but the word PASS
#                          AFTER the QA Pass 2 field marker: proves the end
#                          anchor still terminates the block
#   diag:      answered|unanswered
#   statusrow: yes|no      a CLOSED inventory row on the branch
#   dup:       yes|no      a second specs/0001-*.md file
close_fixture() {
  local d="$1" closing="$2" qa="$3" diag="$4" statusrow="$5" dup="$6" gate="$7"
  git_init "$d"
  sdd_json "$d" true main "$gate"
  git -C "$d" add .claude/sdd.json
  git -C "$d" commit -qm "sdd config"
  # A SECOND spec branch, added 1.0.7. Several findings need a payload to NAME
  # another spec branch, and until this existed such a payload named a branch
  # that does not exist: the gate could not resolve it and denied for the wrong
  # reason, so the assertion passed while testing nothing. A fixture that cannot
  # express a finding must never be read as evidence against it.
  git -C "$d" checkout -q -b spec/0002-other
  git -C "$d" checkout -q main
  git -C "$d" checkout -q -b spec/0001-thing
  mkdir -p "$d/specs"

  {
    printf '# Spec 0001 - thing\n\nStatus: CLOSED\n\n'
    if [[ "$closing" == "yes" ]]; then
      printf '## Closing report\n\n'
      # THE VERDICT IS THE STRUCTURED BLOCK (Part 6, 2026-08-05). The pasted
      # report stays beside it as the human-readable evidence and no gate reads
      # it any more, so the fixture emits both and only the block decides.
      [[ "$qa" == "yes" || "$qa" == "crossref" ]] && printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      [[ "$qa" == "crossref" ]] && printf 'Note: the visual criteria are deferred to QA Pass 2.\n\n'
      [[ "$qa" == "yes" || "$qa" == "crossref" ]] && printf 'criterion 1: PASS\n\n'
      printf -- '- QA Pass 2 (human): done\n\n'
      [[ "$qa" == "stray" ]] && printf -- '- Follow-ups filed: none; the regression suite came back PASS\n\n'
      if [[ "$diag" == "answered" ]]; then
        printf -- '- Architecture diagram: no impact\n'
      elif [[ "$diag" == "fenced" ]]; then
        # F6 (plugin-2.0.0 leg): the ONLY 'Architecture diagram:' line is inside
        # a fenced example, so it is not live text a reader routed through
        # SLH_LIVE_TEXT_AWK can see. The mandatory field is unanswered and must
        # be denied at every layer, including the push-time audit.
        printf 'Fill in the field like the example below:\n\n```\n- Architecture diagram: no impact\n```\n'
      else
        printf -- '- Architecture diagram: <updated in this commit | no impact>\n'
      fi
    fi
  } > "$d/specs/0001-thing.md"

  [[ "$dup" == "yes" ]] && cp "$d/specs/0001-thing.md" "$d/specs/0001-duplicate.md"

  {
    printf '# Spec inventory\n\n'
    printf '| Num | Title | Status | Note |\n'
    printf '| --- | --- | --- | --- |\n'
    if [[ "$statusrow" == "yes" ]]; then
      printf '| 0001 | Thing | CLOSED | shipped |\n'
    else
      printf '| 0001 | Thing | ACTIVE | in flight |\n'
    fi
  } > "$d/specs/STATUS.md"

  git -C "$d" add specs
  git -C "$d" commit -qm "spec 0001"
  git -C "$d" checkout -q main

  # A REAL remote-tracking ref (1.0.7, from F3). This fixture created none, so
  # its "a remote-tracking ref" case asserted a deny on a ref git itself could
  # not resolve: the deny came entirely from a string strip and had never once
  # been exercised against a remote-tracking ref that exists. A fixture that
  # cannot express a finding is not evidence against it, and this one silently
  # covered both halves of F3 for three releases.
  #
  # It points at the SAME commit as the local branch here, which is the ordinary
  # case. The divergent case (local compliant, remote not) is its own fixture in
  # the ref-identity axis, because it needs two different trees.
  git -C "$d" update-ref refs/remotes/origin/spec/0001-thing "$(git -C "$d" rev-parse spec/0001-thing)"
}

MERGE_CMD='git merge --no-ff spec/0001-thing'


# =============================================================================
# scope-hook.sh
# =============================================================================

SC="$WORK/scope"
git_init "$SC"
sdd_json "$SC"
mkdir -p "$SC/src" "$SC/specs"

# r. src/ on the trunk, absolute path
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/src/app.js")"
expect_deny "scope-hook r: src/ on the trunk, absolute path, is denied" "never lands directly on main"

# s. src/ on the trunk, relative path
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "src/app.js")"
expect_deny "scope-hook s: src/ on the trunk, relative path, is denied" "never lands directly on main"

# t. specs/ on the trunk
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/specs/0001-thing.md")"
expect_allow "scope-hook t: specs/ on the trunk is allowed"

# u. src/ on a spec branch
git -C "$SC" checkout -q -b spec/0001-thing
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/src/app.js")"
expect_allow "scope-hook u: src/ on a spec branch is allowed"
git -C "$SC" checkout -q main

# v. bootstrap exemption
sdd_json "$SC" false
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/src/app.js")"
expect_allow "scope-hook v: scaffolded=false exempts the bootstrap scaffold"
sdd_json "$SC" true

# The trunk is read from sdd.json and never assumed to be main, and role paths
# may be a list, a bare file, or the deliberately inert ".". All four were
# field-driven (Part 6) and all four are load-bearing for instances that are
# not a src/tests repo on main.
SCM="$WORK/scope-master"
git_init "$SCM" master
sdd_json "$SCM" true master
mkdir -p "$SCM/src"
run_hook "$HOOKS/scope-hook.sh" "$SCM" "$(edit_payload "$SCM/src/app.js")"
expect_deny "scope-hook trunk: a master-trunk instance is gated on master" "never lands directly on master"

git -C "$SCM" checkout -q -b spec/0001-thing
run_hook "$HOOKS/scope-hook.sh" "$SCM" "$(edit_payload "$SCM/src/app.js")"
expect_allow "scope-hook trunk: a spec branch off master is allowed"
git -C "$SCM" checkout -q master

# Path spelling must not decide enforcement. Each of these names the same file
# as case r; all three used to be allowed onto the trunk in silence.
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "./src/app.js")"
expect_deny "scope-hook path: a dot-prefixed relative path is gated" "never lands directly on main"
run_hook "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC//src/app.js")"
expect_deny "scope-hook path: a doubled slash in the project prefix is gated" "never lands directly on main"
run_hook "$HOOKS/scope-hook.sh" "$SC/" "$(edit_payload "$SC/src/app.js")"
expect_deny "scope-hook path: a trailing-slash project root is gated" "never lands directly on main"

SCL="$WORK/scope-listroles"
git_init "$SCL"
mkdir -p "$SCL/.claude" "$SCL/lib"
cat > "$SCL/.claude/sdd.json" <<'EOF'
{
  "scaffolded": true,
  "trunk": "main",
  "gate_command": "true",
  "roles": { "src": ["index.js", "lib"], "tests": "test.js" }
}
EOF
run_hook "$HOOKS/scope-hook.sh" "$SCL" "$(edit_payload "$SCL/lib/thing.js")"
expect_deny "scope-hook roles: a list-form role directory is gated" "never lands directly on main"
run_hook "$HOOKS/scope-hook.sh" "$SCL" "$(edit_payload "$SCL/index.js")"
expect_deny "scope-hook roles: a bare file named as a role is gated" "never lands directly on main"
run_hook "$HOOKS/scope-hook.sh" "$SCL" "$(edit_payload "$SCL/README.md")"
expect_allow "scope-hook roles: a path outside every role is allowed"

SCD="$WORK/scope-dotrole"
git_init "$SCD"
sdd_json "$SCD"
mkdir -p "$SCD/.claude"
cat > "$SCD/.claude/sdd.json" <<'EOF'
{
  "scaffolded": true,
  "trunk": "main",
  "gate_command": "true",
  "roles": { "src": ".", "tests": "." }
}
EOF
run_hook "$HOOKS/scope-hook.sh" "$SCD" "$(edit_payload "$SCD/anything.js")"
expect_allow "scope-hook roles: the inert dot role covers nothing, by design"

# =============================================================================
# regrounding-hook.sh
# =============================================================================

RG="$WORK/reground"
git_init "$RG"
sdd_json "$RG"
mkdir -p "$RG/specs"
printf '# Status\n' > "$RG/specs/STATUS.md"

# w. the three observed sources each produce their own pointer
run_hook "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload startup)"
expect_context "regrounding w1: startup points at specs/STATUS.md" "read specs/STATUS.md"
run_hook "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload resume)"
expect_context "regrounding w2: resume warns the repo may have moved" "repo may have moved"
run_hook "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload compact)"
expect_context "regrounding w3: compact warns a summary is not the spec" "a summary of the spec is not the spec"

# =============================================================================
# SPEC-HASH INTEGRITY (BL-005), the intake's acceptance criteria 1 through 5,
# plus the two things the intake did not specify and this build had to decide.
#
# The hash covers the spec from its first line to the line before "## Closing
# report", with the Spec-hash FIELD LINE ITSELF removed. That last exclusion is
# not in the intake, because the problem only appears when you try to write the
# value: the field lives in the header, inside the hashed range, so hashing it
# would change the thing being hashed. AC1 below is really an idempotence test.
#
# TWO IMPLEMENTATIONS, asserted to AGREE. scripts/spec-hash.sh serves checkpoint
# (which can reach the plugin tree); regrounding-hook.sh implements the recipe
# inline (which cannot, being stamped into an instance). This repo has been bitten
# by two copies of a rule often enough that the suite drives both over a corpus
# and compares OUTPUT, which is the right lockstep when the implementations are
# deliberately different in shape.
# =============================================================================

sh_fixture() { # sh_fixture <dir> <status> <with-hash: yes|no> <body>
  local d="$1" st="$2" wh="$3" body="$4"
  rm -rf "$d"; mkdir -p "$d/specs" "$d/.claude"
  printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  {
    printf '# Spec 0001 - thing\n\nStatus: %s\n' "$st"
    [[ "$wh" == "yes" ]] && printf 'Spec-hash: PLACEHOLDER\n'
    printf '\n## Goal\n%s\n\n## Closing report\n- What was built: pending\n' "$body"
  } > "$d/specs/0001-thing.md"
  printf '| Num | Title | Status | Note |\n|---|---|---|---|\n| 0001 | Thing | %s | wip |\n' "$st" > "$d/specs/STATUS.md"
  if [[ "$wh" == "yes" ]]; then
    local h; h="$(bash "$ROOT/scripts/spec-hash.sh" "$d/specs/0001-thing.md")"
    sed -e "s/Spec-hash: PLACEHOLDER/Spec-hash: $h/" "$d/specs/0001-thing.md" > "$d/specs/0001-thing.md.t" \
      && mv "$d/specs/0001-thing.md.t" "$d/specs/0001-thing.md"
  fi
}
sh_context() { printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // empty'; }

# AC1: writing the computed value does not change the value. Without the
# field-line exclusion this is false and the mechanism cannot work at all.
SH1="$WORK/spechash-1"; sh_fixture "$SH1" ACTIVE yes "Build the thing."
SH1_BEFORE="$(grep -m1 'Spec-hash:' "$SH1/specs/0001-thing.md" | sed 's/.*Spec-hash: //')"
SH1_AFTER="$(bash "$ROOT/scripts/spec-hash.sh" "$SH1/specs/0001-thing.md")"
if [[ -n "$SH1_BEFORE" && "$SH1_BEFORE" == "$SH1_AFTER" ]]; then
  ok "spec-hash AC1: recomputing after the value is written yields the same value (idempotent)"
else
  bad "spec-hash AC1: recomputing after the value is written yields the same value (idempotent)" \
      "recorded [$SH1_BEFORE] but recomputed [$SH1_AFTER]; the field is being hashed into itself"
fi

# AC2: an untouched ACTIVE spec produces no drift warning.
run_hook "$HOOKS/regrounding-hook.sh" "$SH1" "$(session_payload startup)"
if sh_context | grep -q 'SPEC DRIFT'; then
  bad "spec-hash AC2: an untouched spec produces NO drift warning" "it warned on a clean spec"
else
  ok "spec-hash AC2: an untouched spec produces NO drift warning"
fi
expect_context "spec-hash AC2b: the ordinary pointer still ships alongside the check" "read specs/STATUS.md"

# AC4 before AC3 on purpose: the Closing report is appended during every build,
# so if THIS warned, the mechanism would cry wolf on every honest close and be
# switched off within a day.
printf -- '- Deviations: none\n' >> "$SH1/specs/0001-thing.md"
run_hook "$HOOKS/regrounding-hook.sh" "$SH1" "$(session_payload startup)"
if sh_context | grep -q 'SPEC DRIFT'; then
  bad "spec-hash AC4: editing the Closing report produces NO drift warning" "it warned on an ordinary build append"
else
  ok "spec-hash AC4: editing the Closing report produces NO drift warning"
fi

# AC3: one byte above the Closing report is drift, on all three sources.
SH3="$WORK/spechash-3"; sh_fixture "$SH3" ACTIVE yes "Build the thing."
sed -e 's/Build the thing./Build the OTHER thing./' "$SH3/specs/0001-thing.md" > "$SH3/t" && mv "$SH3/t" "$SH3/specs/0001-thing.md"
for sh_src in startup resume compact; do
  run_hook "$HOOKS/regrounding-hook.sh" "$SH3" "$(session_payload "$sh_src")"
  if sh_context | grep -q 'SPEC DRIFT'; then
    ok "spec-hash AC3: a byte changed above the Closing report warns on source=$sh_src"
  else
    bad "spec-hash AC3: a byte changed above the Closing report warns on source=$sh_src" "no warning"
  fi
done

# AC5: a pre-v1.7 spec has no field. No warning, no error, valid JSON.
SH5="$WORK/spechash-5"; sh_fixture "$SH5" ACTIVE no "Build the thing."
run_hook "$HOOKS/regrounding-hook.sh" "$SH5" "$(session_payload startup)"
if [[ "$HOOK_RC" -eq 0 ]] && printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1 && ! sh_context | grep -q 'SPEC DRIFT'; then
  ok "spec-hash AC5: a spec with no Spec-hash field is silent and still emits valid JSON"
else
  bad "spec-hash AC5: a spec with no Spec-hash field is silent and still emits valid JSON" \
      "rc=$HOOK_RC out=${HOOK_OUT:-<empty>}"
fi

# AC9 in the direction that matters: no hasher must not read as "no drift". A
# silent skip here is the exact failure this project keeps writing down.
SHNH="$WORK/spechash-nohasher"; sh_fixture "$SHNH" ACTIVE yes "Build the thing."
sed -e 's/Build the thing./Build the OTHER thing./' "$SHNH/specs/0001-thing.md" > "$SHNH/t" && mv "$SHNH/t" "$SHNH/specs/0001-thing.md"
SHNH_BIN="$WORK/nohasher-bin"; mkdir -p "$SHNH_BIN"
for shim in sha256sum shasum; do printf '#!/bin/sh\nexit 127\n' > "$SHNH_BIN/$shim"; chmod +x "$SHNH_BIN/$shim"; done
HOOK_OUT="$(printf '%s' "$(session_payload startup)" | PATH="$SHNH_BIN:$PATH" CLAUDE_PROJECT_DIR="$SHNH" bash "$HOOKS/regrounding-hook.sh" 2>/dev/null)"
if sh_context | grep -q 'SPEC INTEGRITY: UNVERIFIED'; then
  ok "spec-hash AC9: with no sha256 tool the check reports UNVERIFIED rather than staying silent"
else
  bad "spec-hash AC9: with no sha256 tool the check reports UNVERIFIED rather than staying silent" \
      "it said nothing, so a drifted spec would look clean on a machine with no hasher"
fi

# THE LOCKSTEP: the script and the hook's inline copy must agree on OUTPUT,
# across shapes that exercise every branch of the recipe.
SHL_OK=1
for shl_case in "plain body" "body with - Spec-hash: decoy inside it" "body
spanning
several lines"; do
  SHL="$WORK/spechash-lock"; sh_fixture "$SHL" ACTIVE no "$shl_case"
  SHL_SCRIPT="$(bash "$ROOT/scripts/spec-hash.sh" "$SHL/specs/0001-thing.md")"
  SHL_INLINE="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' "$SHL/specs/0001-thing.md" \
    | grep -v '^[-*+[:space:]]*Spec-hash:' | sha256sum | cut -d' ' -f1)"
  [[ "$SHL_SCRIPT" == "$SHL_INLINE" ]] || SHL_OK=0
done
if [[ "$SHL_OK" -eq 1 ]]; then
  ok "spec-hash lockstep: scripts/spec-hash.sh and the hook's inline recipe agree on every corpus shape"
else
  bad "spec-hash lockstep: scripts/spec-hash.sh and the hook's inline recipe agree on every corpus shape" \
      "the two implementations of one recipe disagree, which is how a checker and its writer drift apart"
fi

# THE DOCUMENTED LIMITATION, asserted: this WARNS and cannot deny. SessionStart
# has no deny mechanic, the public README says so, and the docs-tree lockstep
# requires the claim be pinned. If a future edit ever made this emit a denial,
# the README would be understating what Setlist does, which is the rarer but
# still real direction of drift.
run_hook "$HOOKS/regrounding-hook.sh" "$SH3" "$(session_payload startup)"
if [[ "$HOOK_RC" -eq 0 ]] \
   && [[ -z "$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty')" ]] \
   && sh_context | grep -q 'SPEC DRIFT'; then
  ok "spec-hash limitation: drift WARNS and never denies (SessionStart has no deny mechanic)"
else
  bad "spec-hash limitation: drift WARNS and never denies (SessionStart has no deny mechanic)" \
      "rc=$HOOK_RC, decision=$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty')"
fi

# THE ADVISORY LAYER NAMES THE LAYER THAT VERIFIES, and says it does not (KL3
# section 7.1, applying the KL4-A1 ruling prospectively). One sentence, no second
# reader: SessionStart has no deny mechanic, so a verifier here could only warn
# about something the next commit refuses anyway, and a reader in this tree would
# be both an A9 violation and a dependency between two deliberately separate
# trees. Asserted on the DRIFT message, because that is the moment a user is
# most likely to think this notice is the enforcement.
run_hook "$HOOKS/regrounding-hook.sh" "$SH3" "$(session_payload startup)"
if sh_context | grep -q 'verified at the git-hook layer, which is the only layer that can refuse'; then
  ok "spec-hash advisory boundary: the drift notice names the layer that verifies and states this one does not"
else
  bad "spec-hash advisory boundary: the drift notice names the layer that verifies and states this one does not" \
      "a user meeting this warning cannot tell it is advisory, which is the divergence the 2026-08-28 ruling closed by honesty"
fi

# AND IT STILL HAS NO VERIFIER, asserted structurally rather than by reading the
# file: one sentence was the whole of the fix, and a second reader arriving in
# this tree is exactly what this pins against.
if ! grep -q 'slh_attest_verify\|slh_attest_load' "$HOOKS/regrounding-hook.sh"; then
  ok "spec-hash advisory boundary: the advisory tree carries NO attestation verifier, only the sentence"
else
  bad "spec-hash advisory boundary: the advisory tree carries NO attestation verifier, only the sentence" \
      "a second reader appeared in templates/hooks/, which is the A9 violation the ruling refused to buy"
fi

# A spec that is not ACTIVE is not the one being built, so it is not checked.
SHQ="$WORK/spechash-queued"; sh_fixture "$SHQ" QUEUED yes "Build the thing."
sed -e 's/Build the thing./Build the OTHER thing./' "$SHQ/specs/0001-thing.md" > "$SHQ/t" && mv "$SHQ/t" "$SHQ/specs/0001-thing.md"
run_hook "$HOOKS/regrounding-hook.sh" "$SHQ" "$(session_payload startup)"
if sh_context | grep -q 'SPEC DRIFT'; then
  bad "spec-hash scope: only the ACTIVE spec is checked" "it warned about a QUEUED spec"
else
  ok "spec-hash scope: only the ACTIVE spec is checked"
fi

# =============================================================================
# i. jq absent: the scope hook fails closed, the pointer still ships
# =============================================================================

run_hook_nojq "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/specs/0001-thing.md")"
expect_deny "no-jq i3: the scope hook fails closed" "jq"

run_hook_nojq "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload startup)"
expect_context "no-jq i5: the pointer still ships and names the condition" "jq is not usable"

# =============================================================================
# i-b. jq PRESENT BUT BROKEN: the same contract, through the failure mode the
# no-jq fixture could not express (leg 4, F1).
#
# `command -v jq` tests whether a file of that name is on PATH. A jq that EXISTS
# and exits nonzero (a broken dynamic library, an out-of-memory kill, a
# wrong-architecture binary) satisfied that and then produced nothing: the
# parses returned the empty string with their status discarded, the
# applicability tests matched nothing, and the close gate and the commit gate
# ALLOWED, silently, against a README that promises the opposite in as many
# words.
#
# Every case below has a HEALTHY control immediately beside it, because a deny
# that fires in all three states would satisfy this block while telling us
# nothing. The controls are the assertions that make the fixture real.
# =============================================================================

run_hook_brokenjq "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/specs/0001-thing.md")"
expect_deny "broken-jq j3: the scope hook fails CLOSED" "jq"


# And it must name the TOOL, not the config. The pre-fix scope hook failed
# closed for the wrong stated reason, blaming a perfectly valid sdd.json, which
# sends the operator to fix a file that is not broken while the gate stays down.
if printf '%s' "$HOOK_OUT" | grep -q 'sdd.json is not the problem'; then
  ok "broken-jq j3b: the scope hook names the broken tool, not the valid config"
else
  bad "broken-jq j3b: the scope hook names the broken tool, not the valid config" \
      "the deny reason did not clear sdd.json: $HOOK_OUT"
fi

# GIT, THE ONE LOAD-BEARING DEPENDENCY THAT WAS NEVER PROBED (v1.9 leg, V19-F1
# with F7; one fix, two gates, so two assertions).
#
# git is the tool these gates DECIDE with: close-gate resolves the merged ref and
# reads the spec off the branch, scope-hook asks which branch HEAD is on. With
# git present but broken every one of those reads returned an empty string, and
# empty read as "nothing to object to", so both gates emitted ZERO BYTES and the
# operation proceeded unwarned. Watched RED first on the pre-fix bytes: both
# cases below produced no output at all, while all three controls already held.
#
# Asserted on the CODE, like its toolchain siblings above and for the same
# reason: the merge payload is one the healthy gate denies anyway, so a bare
# "did it deny" would pass with or without the probe.
# The close gate's half of this fix (t3) left with that gate in 2.8.0 (spec 0144);
# the scope hook's half is t4, below.
build_brokentool_bin git

# The scope hook's fail-open was one level further in: a broken git makes the
# branch read empty, empty never equals the trunk, and the gate exits 0 on a
# write it exists to warn about.
run_hook_brokentool "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/src/app.js")"
expect_deny "toolchain t4: the scope hook names a no-git code when git is broken" "SH-NO-GIT"

# The re-grounding hook emitted literally
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":}}
# because its final `jq -Rs .` produced nothing. So on the one machine where the
# gates have silently stopped enforcing, session start produced malformed JSON
# carrying no warning at all: the notice is suppressed by exactly the condition
# it exists to announce.
run_hook_brokenjq "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload startup)"
if printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; then
  ok "broken-jq j5: the re-grounding hook still emits VALID JSON when jq is broken"
else
  bad "broken-jq j5: the re-grounding hook still emits VALID JSON when jq is broken" \
      "stdout does not parse: ${HOOK_OUT:-<empty>}"
fi
expect_context "broken-jq j6: and it carries the warning that the gates are down" "jq is not usable"

# =============================================================================
# x. no .claude/sdd.json: every hook stays silent
# =============================================================================

BARE="$WORK/bare"
git_init "$BARE"
run_hook "$HOOKS/scope-hook.sh" "$BARE" "$(edit_payload "$BARE/src/app.js")"
expect_allow "no-sdd x1: the scope hook stays silent outside an instance"
run_hook "$HOOKS/regrounding-hook.sh" "$BARE" "$(session_payload startup)"
expect_allow "no-sdd x2: the regrounding hook stays silent outside an instance"

# =============================================================================
# y. stamp integrity: hooks are copied byte-verbatim (C2)
# =============================================================================

STAMP_TARGET="$WORK/stamped"
cat > "$WORK/answers.txt" <<'EOF'
project_name=Fixture
stack=bash
working_mode=solo
ui=no
opusplan_verified=yes
design_surface=no
EOF
if bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STAMP_TARGET" >/dev/null 2>&1; then
  STAMP_DIFF=""
  for h in scope-hook regrounding-hook stop-hook bypass-deny; do
    if ! cmp -s "$HOOKS/$h.sh" "$STAMP_TARGET/.claude/hooks/$h.sh"; then
      STAMP_DIFF="$STAMP_DIFF $h.sh"
    fi
  done
  if [[ -z "$STAMP_DIFF" ]]; then
    ok "stamp y: stamp.sh copies all four hooks byte-verbatim"
  else
    bad "stamp y: stamp.sh copies all four hooks byte-verbatim" \
        "these differ from templates/hooks:$STAMP_DIFF (substitution must never touch hook files)"
  fi
else
  bad "stamp y: stamp.sh copies all four hooks byte-verbatim" "stamp.sh exited non-zero"
fi

