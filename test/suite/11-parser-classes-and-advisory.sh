#!/usr/bin/env bash
# test/suite/11-parser-classes-and-advisory.sh: shard 11 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# ===========================================================================
# >>> SHARD-BEGIN class-c-commit-shape cost=10
if shard_region class-c-commit-shape; then
# ===========================================================================
# THE FROZEN PARSER SPELLINGS THIS FILE EXERCISES (documented 2026-08-04, and
# pinned here so
# the day one of them closes this file says so instead of the README describing
# a weakness the release no longer has).
#
# Each is a WARNING that is absent or misleading, never a command wrongly
# blocked, because the gates are advisory. The git hooks judge the same
# operation correctly afterwards, which is why these are documented rather than
# chased: the parsers and their corpus are frozen together.
FROZEN_BAD=""
# F11: a checkout in ANOTHER repository is credited to this one, so no warning.
[[ "$(corpus_verdict 'cd vendor/lib && git checkout spec/0002-other && cd - && git merge --no-ff spec/0001-thing')" == "allow" ]] \
  || FROZEN_BAD="$FROZEN_BAD
    F11 (cross-repo checkout) now warns: the limitation has CLOSED and the README must stop naming it"
# F13: a loop body that commits before it stages gets no warning.
[[ "$(cg_verdict 'for f in a b; do git commit -m "$f"; git add "$f"; done')" == "allow" ]] \
  || FROZEN_BAD="$FROZEN_BAD
    F13 (loop body) now warns: the limitation has CLOSED and the README must stop naming it"
if [[ -z "$FROZEN_BAD" ]]; then
  ok "frozen parsers: the two spellings this file exercises still behave as Known limitations records"
else
  bad "frozen parsers: the two spellings this file exercises still behave as Known limitations records" \
      "a documented limitation no longer holds, so the docs are now wrong in the safe direction:$FROZEN_BAD"
fi

# ===========================================================================
# CLASS C: THE COMMIT SHAPE IS DERIVED FROM GIT, NOT ENUMERATED (final leg,
# F1 octopus and F9 --amend).
#
# Both causes were "the close verification enumerates commit shapes and the
# enumeration is incomplete". Rather than add two more entries to a hand-kept
# list, the audit now asks git two questions that need no list:
#
#   1. did a NON-FIRST parent bring role-path code with no spec and no recorded
#      chore, in a commit another parent already justified? The spec-less
#      restraint is right for pre-rule history and wrong here: nothing shipped
#      before the rule merged three branches at once to launder one of them.
#   2. does the commit's own tree carry role-path files that NO parent has?
#      `--amend` on a completed merge and an evil merge are the same question.
#
# The residue is labelled rather than hidden: an EDIT to a file a parent already
# had is indistinguishable from ordinary conflict resolution, so it is named in
# Known limitations instead of being flagged, because flagging it would refuse
# every real merge.
#
# Proved red against the pre-fix audit: both shapes exited 0 with the code on the
# trunk.
SHAPE_BAD=""
shape_build() { # shape_build <dir>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
  git -C "$d" branch -M main
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'feature\n' > "$d/src/feature.txt"
  printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "close spec 0001" >/dev/null 2>&1
  git -C "$d" checkout -q main; git -C "$d" config merge.ff false
}
# CONTROL: an ordinary compliant close must stay CLEAN, or every rc=1 below is noise.
SHC="$WORK/shape-ok"; shape_build "$SHC"
( cd "$SHC" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
bash "$ROOT/scripts/trunk-audit.sh" "$SHC" >/dev/null 2>&1 \
  || SHAPE_BAD="$SHAPE_BAD
    CONTROL: an ordinary compliant close was reported as a violation"
# F1: octopus, one compliant parent and one unspecced role-carrying parent.
SHO="$WORK/shape-octo"; shape_build "$SHO"
git -C "$SHO" checkout -q -b feat/sneak main
printf 'unspecced\n' > "$SHO/src/sneaky.txt"
git -C "$SHO" add -A >/dev/null 2>&1; git -C "$SHO" commit -qm sneak >/dev/null 2>&1
git -C "$SHO" checkout -q main
( cd "$SHO" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing feat/sneak ) >/dev/null 2>&1
if git -C "$SHO" cat-file -e main:src/sneaky.txt 2>/dev/null; then
  bash "$ROOT/scripts/trunk-audit.sh" "$SHO" >/dev/null 2>&1 \
    && SHAPE_BAD="$SHAPE_BAD
    F1: an octopus merge laundered unspecced role code and the audit exited 0"
fi
# F9: amend a completed merge to inject a file no parent carries.
SHA="$WORK/shape-amend"; shape_build "$SHA"
( cd "$SHA" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
printf 'backdoor\n' > "$SHA/src/evil.txt"
git -C "$SHA" add src/evil.txt >/dev/null 2>&1
( cd "$SHA" && git commit -q --amend --no-edit ) >/dev/null 2>&1
if git -C "$SHA" cat-file -e main:src/evil.txt 2>/dev/null; then
  bash "$ROOT/scripts/trunk-audit.sh" "$SHA" >/dev/null 2>&1 \
    && SHAPE_BAD="$SHAPE_BAD
    F9: an amend injected role code into a merge and the audit exited 0"
fi
if [[ -z "$SHAPE_BAD" ]]; then
  ok "shape class: an octopus launder and an amend injection are both reported, and an ordinary close stays clean"
else
  bad "shape class: an octopus launder and an amend injection are both reported, and an ordinary close stays clean" \
      "a commit shape put role code on the trunk with the audit at exit 0:$SHAPE_BAD"
fi

# ORDERING: this block calls shape_build, which is defined in the class C block
# ABOVE. The first cut sat before that definition, so the fixture was never
# built, trunk-audit.sh died on a directory with no sdd.json, and the assertion
# failed reporting an empty reason. A test that calls a function defined later
# in the same file fails for a reason that has nothing to do with its subject.
# THE LABELLED RESIDUE OF CLASS C, pinned so it stays a documented trade-off
# rather than drifting into a silent hole. A merge that EDITS a role file a
# parent already had is not reported, because that is indistinguishable from
# ordinary conflict resolution. If this ever starts being reported, the README
# bullet is wrong and this assertion says so.
SHE="$WORK/shape-edit"; shape_build "$SHE"
git -C "$SHE" checkout -q -b feat/edit main
printf 'edited\n' > "$SHE/src/app.js"
git -C "$SHE" add -A >/dev/null 2>&1; git -C "$SHE" commit -qm edit >/dev/null 2>&1
git -C "$SHE" checkout -q main
( cd "$SHE" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
printf 'resolved differently\n' > "$SHE/src/app.js"
git -C "$SHE" add src/app.js >/dev/null 2>&1
( cd "$SHE" && git commit -q --amend --no-edit ) >/dev/null 2>&1
# ONE ok AND ONE bad. The first cut of this had an ok() on BOTH branches, so it
# could not fail: it would have reported either outcome as a pass and told
# nobody which one happened. A check that cannot fail is the defect this file
# exists to catch, written into this file.
if bash "$ROOT/scripts/trunk-audit.sh" "$SHE" >/dev/null 2>&1; then
  ok "shape residue: an EDIT to a file a parent already had is not reported, as Known limitations records"
else
  bad "shape residue: an EDIT to a file a parent already had is not reported, as Known limitations records" \
      "the audit reported it, so either the limitation has CLOSED (update the README bullet and the ledger) or the injection check is over-matching and will refuse ordinary conflict resolutions: $(bash "$ROOT/scripts/trunk-audit.sh" "$SHE" 2>&1 | grep -E 'VIOLATION|audited' | tail -2 | tr '\n' ' ')"
fi


# ===========================================================================
# CLASS B: THE ROLE PATHS ARE READ THE SAME WAY BY EVERY LAYER (final leg,
# F5 and F13), asserted BY OUTCOME through the guarantee layer.
#
# The F8 repair unified the jq EXTRACTION and the suite asserted that, which is
# why this looked closed. Two other axes had drifted and the GUARANTEE layer was
# the odd one out on both: it alone had no SHAPE refusal, so `{"roles":123}` let
# an unclosed spec merge onto the trunk in silence; and its match required a
# trailing slash, so a FILE-valued role could never set carries_code and a
# flat-root instance merged unreviewed code and pushed it.
#
# Asserting the extraction was not enough, so this asserts the MERGE.
ROLE_SHAPE_CASES='{"src":"src","tests":"tests"}|src/FEATURE.txt
{"src":["src","lib"],"tests":"tests"}|src/FEATURE.txt
{"src":"app.js","tests":"tests"}|app.js
123|src/FEATURE.txt
true|src/FEATURE.txt'
ROLE_CLASS_BAD=""
while IFS= read -r rcase; do
  [[ -n "$rcase" ]] || continue
  rjson="${rcase%%|*}"; rfile="${rcase##*|}"
  rcd="$WORK/roleclass-$(printf '%s' "$rjson" | tr -c '[:alnum:]' _ | cut -c1-24)"
  rm -rf "$rcd"; mkdir -p "$rcd/src" "$rcd/specs" "$rcd/.claude" "$rcd/.githooks"
  git_init "$rcd"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":%s}\n' "$rjson" > "$rcd/.claude/sdd.json"
  printf 'x\n' > "$rcd/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$rcd/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$rcd/.githooks/"
  chmod +x "$rcd/.githooks/pre-commit" "$rcd/.githooks/pre-merge-commit"
  git -C "$rcd" add -A >/dev/null 2>&1; git -C "$rcd" commit -qm seed >/dev/null 2>&1
  git -C "$rcd" branch -M main
  git -C "$rcd" checkout -q -b spec/0001-thing
  mkdir -p "$(dirname "$rcd/$rfile")"; printf 'UNREVIEWED\n' > "$rcd/$rfile"
  printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$rcd/specs/0001-thing.md"
  git -C "$rcd" add -A >/dev/null 2>&1
  ( cd "$rcd" && SETLIST_SKIP_HOOKS=1 git commit -qm work ) >/dev/null 2>&1
  git -C "$rcd" checkout -q main
  git -C "$rcd" config core.hooksPath .githooks; git -C "$rcd" config merge.ff false
  git -C "$rcd" cat-file -e "spec/0001-thing:$rfile" 2>/dev/null \
    || { ROLE_CLASS_BAD="$ROLE_CLASS_BAD
    [$rjson] FIXTURE DID NOT BUILD"; continue; }
  ( cd "$rcd" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0001-thing ) >/dev/null 2>&1
  git -C "$rcd" cat-file -e "main:$rfile" 2>/dev/null \
    && ROLE_CLASS_BAD="$ROLE_CLASS_BAD
    [$rjson] unreviewed code reached the trunk"
done <<< "$ROLE_SHAPE_CASES"
if [[ -z "$ROLE_CLASS_BAD" ]]; then
  ok "role class: every roles shape (string, list, FILE-valued, and non-object) refuses an unclosed merge at the guarantee layer"
else
  bad "role class: every roles shape (string, list, FILE-valued, and non-object) refuses an unclosed merge at the guarantee layer" \
      "the guarantee layer read roles differently from its siblings:$ROLE_CLASS_BAD"
fi

# ===========================================================================
# CLASS A: THE TRUNK IDENTITY HAS ONE REDUCER (1.1.0 final leg, F2/F3/F4/F11).
#
# Three finders reported one cause: pre-push compared the recorded trunk RAW
# while the shared library REDUCES it, so for a trunk spelled
# refs/remotes/origin/main, which is exactly what the upgrade skill's own
# detection command returns, the refspec audit added that same morning was dead
# code and `git push origin spec/0001-x:refs/heads/main` put unreviewed work on
# the REMOTE trunk at rc=0.
#
# That was the THIRD instance in one cycle of a comparison with one side
# normalised and the other raw, and the second written while fixing the previous
# instance. So it is repaired as a class: every reader binds to slh_trunk, and
# the agreement is asserted BY OUTCOME over a corpus of ref spellings rather than
# by the readers looking alike. Byte-identity would not have caught this, because
# pre-push had no reduction to be identical to.
#
# Measured against the pre-fix tree, three of these four spellings landed
# unreviewed work on the remote trunk; after the class fix, none do.
TRUNK_SPELLINGS='main
refs/heads/main
refs/remotes/origin/main
MAIN'
TRUNK_CLASS_BAD=""
while IFS= read -r tsp; do
  [[ -n "$tsp" ]] || continue
  tcd="$WORK/trunkclass-$(printf '%s' "$tsp" | tr -c '[:alnum:]' _)"
  rm -rf "$tcd" "$tcd.git"
  mkdir -p "$tcd/src" "$tcd/specs" "$tcd/.claude/hooks" "$tcd/.githooks"
  git_init "$tcd"
  printf 'x\n' > "$tcd/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$tcd/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/"* "$tcd/.githooks/" 2>/dev/null
  cp "$ROOT/scripts/trunk-audit.sh" "$tcd/.claude/hooks/trunk-audit.sh"
  chmod +x "$tcd/.githooks/pre-commit" "$tcd/.githooks/pre-merge-commit" "$tcd/.githooks/pre-push"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$tsp" > "$tcd/.claude/sdd.json"
  git -C "$tcd" add -A >/dev/null 2>&1; git -C "$tcd" commit -qm seed >/dev/null 2>&1
  git -C "$tcd" branch -M main
  git init -q --bare "$tcd.git"; git -C "$tcd" remote add origin "$tcd.git"
  git -C "$tcd" push -q origin main 2>/dev/null
  git -C "$tcd" update-ref refs/remotes/origin/main "$(git -C "$tcd" rev-parse main)"
  git -C "$tcd" config core.hooksPath .githooks; git -C "$tcd" config merge.ff false
  git -C "$tcd" checkout -q -b spec/0001-thing
  printf 'UNREVIEWED\n' > "$tcd/src/FEATURE.txt"
  printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$tcd/specs/0001-thing.md"
  git -C "$tcd" add -A >/dev/null 2>&1
  ( cd "$tcd" && SETLIST_SKIP_HOOKS=1 git commit -qm work ) >/dev/null 2>&1
  git -C "$tcd" checkout -q main
  # CONTROL: the branch must really carry work, or a refusal below proves nothing.
  git -C "$tcd" cat-file -e "spec/0001-thing:src/FEATURE.txt" 2>/dev/null \
    || { TRUNK_CLASS_BAD="$TRUNK_CLASS_BAD
    [$tsp] FIXTURE DID NOT BUILD"; continue; }
  ( cd "$tcd" && env -u CLAUDE_PLUGIN_ROOT git push origin spec/0001-thing:refs/heads/main ) >/dev/null 2>&1
  git -C "$tcd.git" cat-file -e main:src/FEATURE.txt 2>/dev/null \
    && TRUNK_CLASS_BAD="$TRUNK_CLASS_BAD
    [$tsp] unreviewed work reached the REMOTE trunk"
done <<< "$TRUNK_SPELLINGS"
if [[ -z "$TRUNK_CLASS_BAD" ]]; then
  ok "trunk class: every recorded trunk spelling reduces to one identity, and the refspec push is refused for all of them"
else
  bad "trunk class: every recorded trunk spelling reduces to one identity, and the refspec push is refused for all of them" \
      "a reader compared the trunk raw:$TRUNK_CLASS_BAD"
fi

fi; shard_region_end
# <<< SHARD-END class-c-commit-shape
# ===========================================================================
# THE ADVISORY FLIP (the advisory-gate decision, RATIFIED 2026-08-04).
#
# The three session gates no longer hold a veto. They emit permissionDecision
# "allow" always, and report what they WOULD have decided in setlistAdvisory.
# These assertions are the field's contract, and the contract is frozen with the
# parsers: after this lands, a new spelling is a documented limitation rather
# than a corpus entry or a fix.
# ===========================================================================
ADV_BAD=""
for adv_gate in close-gate commit-gate scope-hook; do
  case "$adv_gate" in
    scope-hook) adv_payload="$(jq -nc '{tool_name:"Write",tool_input:{file_path:"src/App.js",content:"x"}}')" ;;
    commit-gate) adv_payload="$(bash_payload 'git add . && git commit -m x')" ;;
    *)           adv_payload="$(bash_payload 'git merge --no-ff spec/0001-thing')" ;;
  esac
  adv_out="$(printf '%s' "$adv_payload" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/$adv_gate.sh" 2>/dev/null)"
  [[ -n "$adv_out" ]] || { ADV_BAD="$ADV_BAD
    $adv_gate emitted nothing on a governed command"; continue; }
  adv_dec="$(printf '%s' "$adv_out" | jq -r '.hookSpecificOutput.permissionDecision // "MISSING"')"
  adv_ver="$(printf '%s' "$adv_out" | jq -r '.setlistAdvisory.verdict // "MISSING"')"
  adv_gat="$(printf '%s' "$adv_out" | jq -r '.setlistAdvisory.gate // "MISSING"')"
  adv_rsn="$(printf '%s' "$adv_out" | jq -r '.setlistAdvisory.reason // "MISSING"')"
  adv_sys="$(printf '%s' "$adv_out" | jq -r '.systemMessage // "MISSING"')"
  [[ "$adv_dec" == "allow" ]] || ADV_BAD="$ADV_BAD
    $adv_gate still holds a veto: permissionDecision=$adv_dec"
  [[ "$adv_ver" == "deny" ]]  || ADV_BAD="$ADV_BAD
    $adv_gate lost its verdict: setlistAdvisory.verdict=$adv_ver"
  [[ "$adv_gat" != "MISSING" ]] || ADV_BAD="$ADV_BAD
    $adv_gate names no gate in setlistAdvisory"
  [[ "$adv_rsn" != "MISSING" && -n "$adv_rsn" ]] || ADV_BAD="$ADV_BAD
    $adv_gate carries no reason in setlistAdvisory"
  [[ "$adv_sys" != "MISSING" && -n "$adv_sys" ]] || ADV_BAD="$ADV_BAD
    $adv_gate emits no systemMessage, so the session is told nothing"
done
if [[ -z "$ADV_BAD" ]]; then
  ok "advisory a: all three session gates ALLOW while reporting their verdict, reason and systemMessage"
else
  bad "advisory a: all three session gates ALLOW while reporting their verdict, reason and systemMessage" \
      "the advisory contract is broken:$ADV_BAD"
fi

# THE TWO EVIDENCE CLASSES MUST NEVER MERGE (owner condition 1 of the
# ratification). setlistAdvisory is evidence about the ADVISORY layer. Every
# guarantee-layer check binds to observed repository state. A guarantee-layer
# test that read this field would be asking the parser whether the parser was
# right, which is the laundering defect this cycle is a record of, one layer up.
ADV_LEAK=""
for adv_f in "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
             "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
             "$ROOT/scripts/trunk-audit.sh"; do
  [[ -f "$adv_f" ]] || continue
  grep -q 'setlistAdvisory' "$adv_f" && ADV_LEAK="$ADV_LEAK $(basename "$adv_f")"
done
# ...and no line of this suite may read the advisory field while also touching a
# guarantee-layer fixture.
# THE CHECK MUST NOT MATCH ITSELF, and the first two cuts did. A case statement
# naming both the field and the guarantee-layer words IS a line containing both,
# so scanning the file for such lines found the scanner. That is the `pgrep`
# waiter matching its own command line, which this repo's ledger records twice,
# in a new costume.
#
# The literals now live in variables, so no single line of this block contains
# both a field name and a guarantee-layer word, and the scan has nothing of its
# own to find.
ADV_FIELD='setlistAdvisory'
for adv_w in 'gh_' 'githooks' 'trunk-audit'; do
  if grep -hn "$ADV_FIELD" "${SUITE_FILES[@]}" 2>/dev/null | grep -q -- "$adv_w"; then
    ADV_LEAK="$ADV_LEAK [suite reads the advisory field beside $adv_w]"
  fi
done
if [[ -z "$ADV_LEAK" ]]; then
  ok "advisory b: no guarantee-layer file or test reads the advisory verdict (the two evidence classes stay separate)"
else
  bad "advisory b: no guarantee-layer file or test reads the advisory verdict (the two evidence classes stay separate)" \
      "the guarantee layer is reading the parser's own opinion:$ADV_LEAK"
fi

# THE 1.1.0 LEG'S FOURTH RUN (the first COMPLETE leg). F5: the template-fence
# stripper read fences as a BOOLEAN TOGGLE and ignored backtick run length, so a
# four-backtick block quoting a three-backtick one was closed early by the inner
# delimiter and everything after it, including the quoted "## Closing report",
# was emitted as the spec's own text. All three layers went blind together,
# which is the lockstep failure the stripper's own comment names.
# ===========================================================================
NF_DIR="$WORK/nested-fence"
nf_spec() { # nf_spec <mode: nested|none|real> -> writes a spec body to stdout
  local mode="$1" b3='```' b4='````'
  printf '# Spec 0001\n\nStatus: CLOSED\n\n'
  case "$mode" in
    nested)
      printf '%smarkdown\nExample output:\n%s\n' "$b4" "$b3"
      printf '## Closing report\n\n- QA Pass 1 report (pasted verbatim):\n\n| 1 | c | PASS | e |\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
      printf '%s\n%s\n\nNothing above is a real report.\n' "$b3" "$b4" ;;
    none) printf 'No closing report at all.\n' ;;
    real)
      printf '%s\n%s\nquoted\n%s\n%s\n\n' "$b4" "$b3" "$b3" "$b4"
      printf '## Closing report\n\n- QA Pass 1 report (pasted verbatim):\n\n| 1 | c | PASS | e |\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' ;;
  esac
}
nf_build() { # nf_build <dir> <mode>
  local d="$1"
  close_fixture "$d" no no answered no no true
  git -C "$d" checkout -q spec/0001-thing
  nf_spec "$2" > "$d/specs/0001-thing.md"
  # The honest mode must carry the structured verdict (Part 6). The other two
  # modes are the no-report and quoted-only cases and must stay denied, so they
  # deliberately do not get one.
  [[ "$2" == "real" ]] && printf -- '\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n' >> "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "spec body" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
nf_verdict() { local o; o="$(printf '%s' "$(bash_payload 'git merge --no-ff spec/0001-thing')" | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/close-gate.sh" 2>/dev/null)"; [[ -z "$o" ]] && { printf 'allow'; return 0; }; printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'; }

nf_build "$NF_DIR-none" none
if [[ "$(nf_verdict "$NF_DIR-none")" == "deny" ]]; then
  ok "nested fence a: CONTROL, a spec with no Closing report at all is denied"
else
  bad "nested fence a: CONTROL, a spec with no Closing report at all is denied" \
      "the control did not deny, so nothing below means anything"
fi
nf_build "$NF_DIR-nested" nested
if [[ "$(nf_verdict "$NF_DIR-nested")" == "deny" ]]; then
  ok "nested fence b: a Closing report that exists ONLY inside a nested fence is refused"
else
  bad "nested fence b: a Closing report that exists ONLY inside a nested fence is refused" \
      "quoted documentation was accepted as the spec's own Closing report"
fi
nf_build "$NF_DIR-real" real
if [[ "$(nf_verdict "$NF_DIR-real")" == "allow" ]]; then
  ok "nested fence c: an HONEST report after a quoted nested fence still merges"
else
  bad "nested fence c: an HONEST report after a quoted nested fence still merges" \
      "the same defect firing the other way: a real report swallowed as template body"
fi

# THE 1.1.0 LEG'S THIRD RUN. Six repairs, every payload kept, and the ALLOW and
# DENY directions asserted side by side because five of the six were FALSE
# DENIALS created by earlier fixes. Law 2 in one block: the heredoc pass was a
# 1.1.0 fix and it opened a BLOCKER; the case-variant repair was a 1.1.0 fix and
# it covered only half its own comparison.
# ===========================================================================

# S6-6 BLOCKER: a heredoc-looking token in FREE TEXT swallowed every later line,
# so a real trunk merge was allowed with every check skipped. Bash opens no
# heredoc inside quotes or after a comment, which is exactly what the broken
# version's justification claimed it did.
L3_BAD=""
while IFS= read -r l3_c; do
  [[ -n "$l3_c" ]] || continue
  [[ "$(corpus_verdict "$(printf '%b' "$l3_c")")" == "deny" ]] || L3_BAD="$L3_BAD
    $l3_c"
done <<'L3EOF'
git commit -m "use <<EOF heredoc in the installer"\ngit merge --no-ff spec/0001-thing
git commit -m 'use <<EOF heredoc'\ngit merge --no-ff spec/0001-thing
# see <<EOF below\ngit merge --no-ff spec/0001-thing
echo "shift << AMOUNT bits"\ngit merge --no-ff spec/0001-thing
git commit -m x <<<WORD\ngit merge --no-ff spec/0001-thing
L3EOF
if [[ -z "$L3_BAD" ]]; then
  ok "leg3 a: a heredoc-looking token in free text does not swallow a later trunk merge"
else
  bad "leg3 a: a heredoc-looking token in free text does not swallow a later trunk merge" \
      "these merges were ALLOWED because the gate stopped reading:$L3_BAD"
fi
# The other direction, which is the F9 fix this must not undo: a REAL heredoc
# body is still not read as commands.
if [[ "$(corpus_verdict "$(printf 'git commit -F - <<%sMSG%s\nrefactor\n\ngit merge --no-ff spec/0001-thing is prose\nMSG\n' "'" "'")")" == "allow" ]]; then
  ok "leg3 b: a REAL heredoc body is still not judged as commands (the F9 fix holds)"
else
  bad "leg3 b: a REAL heredoc body is still not judged as commands (the F9 fix holds)" \
      "a line of the commit MESSAGE was judged as a trunk merge"
fi
# And a merge AFTER a properly terminated heredoc is still judged.
if [[ "$(corpus_verdict "$(printf 'cat <<EOF > /tmp/f\ntext\nEOF\ngit merge --no-ff spec/0001-thing\n')")" == "deny" ]]; then
  ok "leg3 c: a merge after a terminated heredoc is still judged"
else
  bad "leg3 c: a merge after a terminated heredoc is still judged" "the merge was allowed"
fi

# F8 (fourth run): the three readers of .roles DISAGREED, and the guarantee layer
# was the one that was wrong. setlist-hook-lib.sh used `to_entries[] | .value`
# with no flatten, so a LIST-valued role path printed raw JSON, carries_code
# stayed 0, and an unclosed spec branch merged past pre-merge-commit in silence.
# The edition's Part 3 names `packages/*` when it says paths are roles, so a list
# is documented usage rather than an exotic input.
#
# Asserted by OUTPUT over a corpus of role shapes rather than by byte-identity of
# the expression, because agreement on bytes is a weaker claim than agreement on
# behaviour, and this is the reader that had neither.
ROLE_SHAPES='{"roles":{"src":"src","tests":"tests"}}
{"roles":{"src":["packages/app","packages/lib"],"tests":"tests"}}
{"roles":{}}
{}
{"roles":{"src":"src","tests":"tests","docs":"docs"}}'
# ANCHORED ON THE EXTRACTION, not on the first jq line mentioning .roles. Both
# of these files now ALSO carry a shape check that mentions .roles and returns
# "ok", and a first-match grep found that one and compared an "ok" against a
# list of paths. That is the second time this assertion has caught its own
# anchor rather than its subject, which is worth more than it sounds: an
# extraction pointed at the wrong line reports confidently about nothing.
ROLE_JQ_LIB="$(grep -m1 -o "jq -r '[^']*flatten[^']*'" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed -e "s/^jq -r '//" -e "s/'$//")"
ROLE_JQ_AUD="$(grep -m1 -o "jq -r '[^']*flatten[^']*'" "$ROOT/scripts/trunk-audit.sh" | sed -e "s/^jq -r '//" -e "s/'$//")"
# Anchored on the ROLE_PATHS assignment, not on the first jq line mentioning
# .roles: scope-hook.sh checks the SHAPE of .roles earlier in the file, and a
# bare grep found that one and compared an "ok" against a list of paths. The
# assertion caught its own extraction, which is the behaviour wanted, but the
# lesson is that a checker anchored on the wrong line reports about the wrong
# thing rather than failing to report.
ROLE_JQ_SCP="$(grep -m1 -o "jq -r '[^']*flatten[^']*'" "$HOOKS/scope-hook.sh" | sed -e "s/^jq -r '//" -e "s/'$//")"
if [[ -n "$ROLE_JQ_LIB" && -n "$ROLE_JQ_AUD" && -n "$ROLE_JQ_SCP" ]]; then
  ROLE_BAD=""
  while IFS= read -r role_shape; do
    [[ -n "$role_shape" ]] || continue
    r_lib="$(printf '%s' "$role_shape" | jq -r "$ROLE_JQ_LIB" 2>/dev/null | tr '\n' ' ')"
    r_aud="$(printf '%s' "$role_shape" | jq -r "$ROLE_JQ_AUD" 2>/dev/null | tr '\n' ' ')"
    r_scp="$(printf '%s' "$role_shape" | jq -r "$ROLE_JQ_SCP" 2>/dev/null | tr '\n' ' ')"
    if [[ "$r_lib" != "$r_aud" || "$r_aud" != "$r_scp" ]]; then
      ROLE_BAD="$ROLE_BAD
    $role_shape -> lib[$r_lib] audit[$r_aud] scope[$r_scp]"
    fi
    # And a LIST must yield its members, not raw JSON.
    case "$role_shape" in
      *packages*)
        [[ "$r_lib" == *"packages/app"* && "$r_lib" != *"["* ]] || ROLE_BAD="$ROLE_BAD
    a list value did not flatten in the hook library: [$r_lib]" ;;
    esac
  done <<< "$ROLE_SHAPES"
  if [[ -z "$ROLE_BAD" ]]; then
    ok "roles a: the three .roles readers agree on every role shape, and a list flattens"
  else
    bad "roles a: the three .roles readers agree on every role shape, and a list flattens" \
        "the guarantee layer and its backstop read the same config differently:$ROLE_BAD"
  fi
else
  bad "roles a: the three .roles readers agree on every role shape, and a list flattens" \
      "could not extract all three jq expressions, so this assertion checked nothing"
fi

# THE FOURTH RUN'S REGRESSIONS FROM THE THIRD RUN'S FIXES. All three are mine
# from the same day, which is why they are asserted with the case they broke
# sitting next to the case they were written for.
#
# F15: adding switch's -c/-C to the creation-flag list collided with GIT'S OWN
#      global options, spelled identically and sitting BEFORE the subcommand.
# F16: a created branch name was trusted verbatim even when it was not a literal.
# F22: two of git's separate-value global options were missing from GIT_OPTS.
L3_REG_DENY=""
for l3r in \
  'git -C . checkout main && git merge --no-ff spec/0001-thing' \
  'git -c user.name=x checkout main && git merge --no-ff spec/0001-thing' \
  'git checkout -B $V && git merge --no-ff spec/0001-thing' \
  'git checkout -b "$B" && git merge --no-ff spec/0001-thing' \
  'git --config-env x=Y merge --no-ff spec/0001-thing' \
  'git --attr-source x merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$l3r")" == "deny" ]] || L3_REG_DENY="$L3_REG_DENY
    $l3r"
done
if [[ -z "$L3_REG_DENY" ]]; then
  ok "leg4 a: a global git option is not a branch creation, and an unreadable creation target fails closed"
else
  bad "leg4 a: a global git option is not a branch creation, and an unreadable creation target fails closed" \
      "these reached the trunk with the close conditions unevaluated:$L3_REG_DENY"
fi
# The other direction, which is what those fixes were FOR: a literal creation
# followed by a merge onto the new branch is ordinary work and must still pass.
L3_REG_ALLOW=""
for l3r in \
  'git switch -c feat/x && git merge --no-ff spec/0001-thing' \
  'git checkout -b feat/z main && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$l3r")" == "allow" ]] || L3_REG_ALLOW="$L3_REG_ALLOW
    $l3r"
done
if [[ -z "$L3_REG_ALLOW" ]]; then
  ok "leg4 b: a LITERAL branch creation followed by a merge onto it is still allowed"
else
  bad "leg4 b: a LITERAL branch creation followed by a merge onto it is still allowed" \
      "the regression fix went too far and re-broke the case it was written for:$L3_REG_ALLOW"
fi

# F3 (fourth run): ARITHMETIC IS A THIRD CONTEXT WHERE BASH SEES NO HEREDOC.
# The 1.1.0 F9 repair taught the scanner about quotes and comments and stopped
# there, so `echo $((1 << 2))` was read as opening a heredoc with delimiter `2`
# and every later line was discarded: the merge on the next line was allowed in
# silence, oracle-confirmed landing on the trunk. Two causes, both fixed: the
# delimiter could start with a DIGIT, and arithmetic spans were not skipped.
L3_ARITH_BAD=""
while IFS= read -r l3a; do
  [[ -n "$l3a" ]] || continue
  [[ "$(corpus_verdict "$(printf '%b' "$l3a")")" == "deny" ]] || L3_ARITH_BAD="$L3_ARITH_BAD
    $l3a"
done <<'L3AEOF'
echo $((1 << 2))\ngit merge --no-ff spec/0001-thing
echo $((x << y))\ngit merge --no-ff spec/0001-thing
((v = 1 << 3))\ngit merge --no-ff spec/0001-thing
echo a << 2\ngit merge --no-ff spec/0001-thing
L3AEOF
if [[ -z "$L3_ARITH_BAD" ]]; then
  ok "leg3 h: an arithmetic left-shift does not swallow a later trunk merge"
else
  bad "leg3 h: an arithmetic left-shift does not swallow a later trunk merge" \
      "these merges were ALLOWED because the gate stopped reading:$L3_ARITH_BAD"
fi

# S6-3, S6-4, S6-11: branch CREATION spellings. Merging a spec branch into a
# newly created feature branch cannot move the trunk, and the checkout -b
# spelling was allowed while the switch -c spelling was denied.
L3_CREATE_BAD=""
for l3_c in \
  'git switch -c feat/x && git merge --no-ff spec/0001-thing' \
  'git switch -C feat/x && git merge --no-ff spec/0001-thing' \
  'git switch --create feat/x && git merge --no-ff spec/0001-thing' \
  'git checkout -b feat/x && git merge --no-ff spec/0001-thing' \
  'git checkout -b feat/z main && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$l3_c")" == "allow" ]] || L3_CREATE_BAD="$L3_CREATE_BAD
    $l3_c"
done
if [[ -z "$L3_CREATE_BAD" ]]; then
  ok "leg3 d: creating a branch then merging a spec into it is allowed, in every creation spelling"
else
  bad "leg3 d: creating a branch then merging a spec into it is allowed, in every creation spelling" \
      "the framework refused work that cannot reach the trunk:$L3_CREATE_BAD"
fi
# The guard the creation fix relaxed must still hold: a PATHSPEC checkout with
# two operands records no switch, so a merge after it is judged against the trunk.
L3_PATH_BAD=""
for l3_c in \
  'git checkout spec/0002-other src/a.txt && git merge --no-ff spec/0001-thing' \
  'git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$l3_c")" == "deny" ]] || L3_PATH_BAD="$L3_PATH_BAD
    $l3_c"
done
if [[ -z "$L3_PATH_BAD" ]]; then
  ok "leg3 e: a pathspec checkout still records no switch, so a later merge is judged against the trunk"
else
  bad "leg3 e: a pathspec checkout still records no switch, so a later merge is judged against the trunk" \
      "the creation-flag relaxation opened the pathspec hole:$L3_PATH_BAD"
fi

# S6-7: the global-option run swallowed the SUBCOMMAND, so read-only commands
# whose free text contains "merge" were denied and told to write a Closing report.
L3_RO_BAD=""
for l3_c in 'git --no-pager grep -n merge -- src' 'git --no-pager log --grep merge' 'git grep commit'; do
  [[ "$(corpus_verdict "$l3_c")" == "allow" ]] || L3_RO_BAD="$L3_RO_BAD
    $l3_c"
done
if [[ -z "$L3_RO_BAD" ]]; then
  ok "leg3 f: read-only git commands mentioning merge in free text are not judged as merges"
else
  bad "leg3 f: read-only git commands mentioning merge in free text are not judged as merges" \
      "a search was refused as if it were a close:$L3_RO_BAD"
fi
# ...and the global-option spellings of a REAL merge must still be caught, which
# is what the greedy clause was there for in the first place.
L3_GO_BAD=""
for l3_c in \
  'git -C . merge --no-ff spec/0001-thing' \
  'git --no-pager merge --no-ff spec/0001-thing' \
  'git -c user.name=x merge --no-ff spec/0001-thing' \
  'git --git-dir=.git --work-tree=. merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$l3_c")" == "deny" ]] || L3_GO_BAD="$L3_GO_BAD
    $l3_c"
done
if [[ -z "$L3_GO_BAD" ]]; then
  ok "leg3 g: a real merge behind git's global options is still denied"
else
  bad "leg3 g: a real merge behind git's global options is still denied" \
      "the GIT_OPTS repair opened the spelling hole it replaced:$L3_GO_BAD"
fi

# THE TWO DOCUMENTED TRADE-OFFS FROM THE 1.1.0 LEG'S SECOND RUN, asserted so
# that the day either one closes this file says so instead of the README quietly
# describing a weakness the release no longer has.
#
# 1. `@{u}` is refused while `origin/main` is allowed. Both name the same ref.
#    The refusal is conservative rather than wrong (the gate declines operands it
#    cannot reduce to a literal branch), but it IS a refusal of a workflow the
#    suite protects one spelling over, so it is documented rather than silent.
GHU="$WORK/gh-upstream"
close_fixture "$GHU" no no answered no no true
GHU_REMOTE="$WORK/gh-upstream-remote.git"; rm -rf "$GHU_REMOTE"; git init -q --bare "$GHU_REMOTE"
git -C "$GHU" remote add origin "$GHU_REMOTE" 2>/dev/null || true
git -C "$GHU" push -q origin main 2>/dev/null || true
git -C "$GHU" branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
ghu_verdict() { # ghu_verdict <command> -> deny|allow
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$GHU" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  [[ -z "$out" ]] && { printf 'allow'; return 0; }
  printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'
}
# >>> SHARD-BEGIN advisory-flip cost=8
if shard_region advisory-flip; then
# CONTROL, THE DENY DIRECTION FIRST, and the ordering is the whole point.
#
# This block used to open with the ALLOW control alone, and the 1.1.0 leg caught
# it passing VACUOUSLY: the fixture was built by a script absent from the staged
# export, so nothing existed at $GHU, the close gate emitted nothing, silence
# reads as allow, and a control that cannot fail reported green. A green from a
# control is only worth the fixture behind it, so the fixture is proven to DENY
# something before its allow is believed.
if [[ "$(ghu_verdict 'git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "upstream a0: CONTROL, the fixture exists and the gate is live (a governed merge denies)"
else
  bad "upstream a0: CONTROL, the fixture exists and the gate is live (a governed merge denies)" \
      "the gate said nothing about a merge it governs, so this fixture proves nothing and every verdict below is noise"
fi
if [[ "$(ghu_verdict 'git merge origin/main')" == "allow" ]]; then
  ok "upstream a: CONTROL, the spelled-out sync merge from the trunk's own remote is allowed"
else
  bad "upstream a: CONTROL, the spelled-out sync merge from the trunk's own remote is allowed" \
      "the control was denied, so the fixture is wrong and the documented trade-off below cannot be judged"
fi
GHU_BAD=""
for ghu_c in 'git merge @{u}' 'git merge @{upstream}' 'git merge main@{u}'; do
  [[ "$(ghu_verdict "$ghu_c")" == "deny" ]] || GHU_BAD="$GHU_BAD
    $ghu_c"
done
if [[ -z "$GHU_BAD" ]]; then
  ok "upstream b: the @{u} spellings are refused, as Known limitations records"
else
  bad "upstream b: the @{u} spellings are refused, as Known limitations records" \
      "these are now ALLOWED, so the documented trade-off has closed and the README must stop naming it:$GHU_BAD"
fi

# 2. A role directory spelled in a different case is missed by the scope gate on
#    a case-insensitive filesystem, and the trunk audit catches it. Both halves
#    are asserted, because the second is the entire reason the first is MINOR.
SCP="$WORK/scope-case"; rm -rf "$SCP"; mkdir -p "$SCP/src" "$SCP/specs" "$SCP/.claude"
git_init "$SCP"
jq -n '{trunk:"main",scaffolded:true,gate_command:"true",roles:{src:"src",tests:"tests"}}' > "$SCP/.claude/sdd.json"
printf 'x\n' > "$SCP/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCP/specs/STATUS.md"
git -C "$SCP" add -A >/dev/null 2>&1; git -C "$SCP" commit -qm seed >/dev/null 2>&1
git -C "$SCP" branch -M main
scp_verdict() { # scp_verdict <path> -> deny|allow
  local out
  out="$(printf '%s' "$(jq -nc --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')" \
        | CLAUDE_PROJECT_DIR="$SCP" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"
  [[ -z "$out" ]] && { printf 'allow'; return 0; }
  printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'
}
if [[ "$(scp_verdict 'src/feature.txt')" == "deny" ]]; then
  ok "scope case a: CONTROL, the canonical role spelling denies a trunk write"
else
  bad "scope case a: CONTROL, the canonical role spelling denies a trunk write" \
      "the control did not deny, so nothing below means anything"
fi
SCP_PROBE="$WORK/scope-case-probe"; rm -rf "$SCP_PROBE"; mkdir -p "$SCP_PROBE"; : > "$SCP_PROBE/aa"
if [[ -e "$SCP_PROBE/AA" ]]; then
  if [[ "$(scp_verdict 'SRC/feature.txt')" == "allow" ]]; then
    ok "scope case b: a case-variant role directory is missed by the scope gate, as Known limitations records"
  else
    ok "scope case b: a case-variant role directory is now DENIED, which CLOSES a documented hole; update Known limitations and this ledger entry"
  fi
  # The half that makes it MINOR: the backstop must actually catch it.
  #
  # THE ROLE DIRECTORY MUST NOT ALREADY EXIST IN CANONICAL FORM (F8, 2026-08-05).
  # This used to write $SCP/SRC while $SCP/src had been created above, so on a
  # case-insensitive filesystem the mkdir was a no-op, git staged the CANONICAL
  # `src/feature.txt`, and this asserted that the audit catches a canonical trunk
  # write. It never exercised the case variant at all, and passed for that
  # reason while the mitigation it exists to prove was false: with the directory
  # absent git records the literal spelling and the audit's role matching was
  # case-sensitive too, so BOTH layers missed it and the push succeeded.
  # `tests` is used instead precisely because the fixture does not create it.
  mkdir -p "$SCP/TESTS"; printf 'code\n' > "$SCP/TESTS/feature.txt"
  git -C "$SCP" add -A >/dev/null 2>&1
  git -C "$SCP" commit -qm "feature via the SRC spelling" >/dev/null 2>&1
  SCP_RECORDED="$(git -C "$SCP" show --name-only --format= HEAD | grep -i 'feature.txt' | head -n1)" # fail-open-ok: an empty value fails the discriminator below, which is the correct answer for a fixture that staged nothing
  if [[ "$SCP_RECORDED" != TESTS/* ]]; then
    bad "scope case c: the trunk audit CATCHES what the case-variant spelling slipped past the scope gate" \
        "the fixture recorded [$SCP_RECORDED], not the TESTS/ variant, so this assertion would pass without ever exercising the case it is written for"
  elif bash "$ROOT/scripts/trunk-audit.sh" "$SCP" >"$SCP/audit.out" 2>&1; then
    bad "scope case c: the trunk audit CATCHES what the case-variant spelling slipped past the scope gate" \
        "the audit reported clean, so the mitigation Known limitations claims does not hold and this is not a MINOR"
  else
    ok "scope case c: the trunk audit CATCHES what the case-variant spelling slipped past the scope gate"
  fi
else
  ok "scope case b: SKIPPED, this filesystem is case-SENSITIVE so the role-case hole cannot exist here"
fi

# THE CASE-VARIANT TRUNK ALIAS (1.1.0 adversarial review, second run, BLOCKER).
#
# On a case-insensitive filesystem `refs/heads/main` is one loose file, so
# `git checkout MAIN` resolves and attaches HEAD to the same ref while
# `symbolic-ref --short HEAD` answers "MAIN". Every layer compared that to the
# configured "main" as bytes and concluded it was not on the trunk. Measured:
# the close gate allowed, pre-merge-commit stayed SILENT where the canonical
# spelling gets SLH-CLOSES-NO-SPEC, the trunk really moved, and with a branch
# carrying no spec file the audit filed it under "chore merges (unverifiable)"
# at exit 0, so pre-push passed it too. Four layers, none refused.
#
# This block is PLATFORM-CONDITIONAL and the skip announces itself, because the
# defect does not exist where the filesystem distinguishes the two names. On
# Linux CI the alias cannot be created, so asserting the refusal there would
# pass for the wrong reason.
CI_PROBE="$WORK/case-probe"; rm -rf "$CI_PROBE"; mkdir -p "$CI_PROBE"; : > "$CI_PROBE/aa"
if [[ -e "$CI_PROBE/AA" ]]; then
  GHC="$WORK/gh-casealias"; gh_fixture "$GHC" no
  # CONTROL: the alias must actually RESOLVE, or the case below tests nothing.
  assert_true "git hooks r0: refs/heads/MAIN resolves on this filesystem (the alias exists)" \
    "MAIN does not resolve, so this filesystem does not have the defect and the case below would pass for the wrong reason" \
    git -C "$GHC" rev-parse --verify --quiet refs/heads/MAIN
  GHC_BEFORE="$(git -C "$GHC" rev-parse main)"
  ( cd "$GHC" && git checkout -q MAIN && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true \
      git merge --no-ff -m "Merge spec/0001-thing into MAIN" spec/0001-thing ) >"$GHC.out" 2>&1
  GHC_AFTER="$(git -C "$GHC" rev-parse main)"
  if [[ "$GHC_BEFORE" == "$GHC_AFTER" ]] && ! gh_landed "$GHC"; then
    ok "git hooks r: a case-variant of the trunk name is still the trunk, and the merge is refused"
  else
    bad "git hooks r: a case-variant of the trunk name is still the trunk, and the merge is refused" \
        "unreviewed work reached the trunk through 'git checkout MAIN'; the trunk moved ${GHC_BEFORE:0:7} -> ${GHC_AFTER:0:7}"
  fi
  # The refusal must be the SETLIST one, not git failing for its own reasons.
  if grep -q "SLH-" "$GHC.out"; then
    ok "git hooks r2: the alias merge is refused BY THE HOOK, with a setlist reason"
  else
    bad "git hooks r2: the alias merge is refused BY THE HOOK, with a setlist reason" \
        "nothing landed but no SLH- reason was printed, so this is not evidence the hook ran: $(head -n1 "$GHC.out")"
  fi
  # The ALLOW direction, which is what stops the repair from calling every
  # branch the trunk: ordinary work on a real feature branch still commits.
  GHC2="$WORK/gh-casealias-ok"; gh_fixture "$GHC2" no
  ( cd "$GHC2" && git checkout -q spec/0001-thing && printf 'more\n' >> src/FEATURE.txt \
      && git add -A && git commit -qm "ordinary feature work" ) >"$GHC2.out" 2>&1
  if [[ "$(git -C "$GHC2" log -1 --format=%s spec/0001-thing)" == "ordinary feature work" ]]; then
    ok "git hooks r3: ordinary work on a real feature branch is still allowed (the fix does not over-match)"
  else
    bad "git hooks r3: ordinary work on a real feature branch is still allowed (the fix does not over-match)" \
        "the commit was refused: $(grep -o 'SLH-[A-Z-]*' "$GHC2.out" | sort -u | tr '\n' ' ')"
  fi
else
  ok "git hooks r: SKIPPED, this filesystem is case-SENSITIVE so the trunk alias cannot exist here (the defect is macOS/NTFS only, and is asserted where it is reachable)"
fi

# S6-9: the FIRST repair of the case alias covered the git hooks and the checkout
# OPERAND and left the session gates' own CUR_BRANCH, the scope hook's BRANCH and
# the configured trunk raw. So one ordinary `git checkout MAIN` in an EARLIER tool
# call disabled both session gates for the rest of the session, and
# {"trunk":"MAIN"} did it with HEAD untouched. A comparison is only as normalised
# as its weaker side, which is why both sides are asserted here.
if [[ -e "$CI_PROBE/AA" ]]; then
  SGA="$WORK/sess-alias"
  close_fixture "$SGA" no no answered no no true
  # A SILENT HOOK IS THE ALLOW PATH, and piping its empty output into jq yields
  # NOTHING rather than the `// "allow"` default: with no input document there is
  # no document for the alternative operator to apply to. The emptiness has to be
  # tested before jq is asked anything. This is the same misread that made a
  # control look like a failure earlier in this cycle.
  sga_close() { local o; o="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$SGA" bash "$HOOKS/close-gate.sh" 2>/dev/null)"; [[ -z "$o" ]] && { printf 'allow'; return 0; }; printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'; }
  sga_scope() { local o; o="$(printf '%s' "$(jq -nc --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')" | CLAUDE_PROJECT_DIR="$SGA" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"; [[ -z "$o" ]] && { printf 'allow'; return 0; }; printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'; }
  # CONTROL on the canonical spelling first.
  if [[ "$(sga_close 'git merge --no-ff spec/0001-thing')" == "deny" && "$(sga_scope 'src/x.js')" == "deny" ]]; then
    ok "git hooks s0: CONTROL, both session gates refuse on the canonical trunk spelling"
  else
    bad "git hooks s0: CONTROL, both session gates refuse on the canonical trunk spelling" \
        "the control did not deny, so nothing below means anything"
  fi
  git -C "$SGA" checkout -q MAIN 2>/dev/null
  if [[ "$(sga_close 'git merge --no-ff spec/0001-thing')" == "deny" && "$(sga_scope 'src/x.js')" == "deny" ]]; then
    ok "git hooks s: a prior 'git checkout MAIN' does not disable the session gates"
  else
    bad "git hooks s: a prior 'git checkout MAIN' does not disable the session gates" \
        "one ordinary command in an earlier tool call turned both session gates off"
  fi
  git -C "$SGA" checkout -q main 2>/dev/null
  jq '.trunk="MAIN"' "$SGA/.claude/sdd.json" > "$SGA/.claude/sdd.json.t" && mv "$SGA/.claude/sdd.json.t" "$SGA/.claude/sdd.json"
  if [[ "$(sga_close 'git merge --no-ff spec/0001-thing')" == "deny" && "$(sga_scope 'src/x.js')" == "deny" ]]; then
    ok "git hooks s2: a case-variant trunk in sdd.json does not disable the session gates"
  else
    bad "git hooks s2: a case-variant trunk in sdd.json does not disable the session gates" \
        "the configured side of the comparison is still raw"
  fi
else
  ok "git hooks s: SKIPPED, case-SENSITIVE filesystem (asserted where the alias is reachable)"
fi

# S6-12: the already-merged exemption was dead for every spec/-shaped ref, so
# re-merging a branch that landed an hour ago was denied with CG-UNNAMEABLE-REF,
# a reason produced by the code path that had just resolved the branch. git says
# "Already up to date." for the same command, and there was NO user remedy: the
# refusal fires before any close check, so writing a Closing report cannot clear it.
AMG="$WORK/already-merged"
close_fixture "$AMG" no no answered no no true
( cd "$AMG" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0001-thing ) >/dev/null 2>&1
amg_verdict() { local o; o="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$AMG" bash "$HOOKS/close-gate.sh" 2>/dev/null)"; [[ -z "$o" ]] && { printf 'allow'; return 0; }; printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"'; }
assert_true "git hooks t0: CONTROL, the branch really is an ancestor of the trunk now" \
  "the fixture did not merge, so the exemption below is not being exercised" \
  git -C "$AMG" merge-base --is-ancestor spec/0001-thing main
if [[ "$(amg_verdict 'git merge --no-ff spec/0001-thing')" == "allow" ]]; then
  ok "git hooks t: re-merging an ALREADY-MERGED spec branch is allowed (it lands nothing)"
else
  bad "git hooks t: re-merging an ALREADY-MERGED spec branch is allowed (it lands nothing)" \
      "a no-op the framework's own comment calls an ordinary sync was refused, with no remedy available"
fi
# The control that keeps the exemption honest: an UNMERGED spec branch must still deny.
AMG2="$WORK/not-merged"
close_fixture "$AMG2" no no answered no no true
if [[ "$(printf '%s' "$(bash_payload 'git merge --no-ff spec/0001-thing')" | CLAUDE_PROJECT_DIR="$AMG2" bash "$HOOKS/close-gate.sh" 2>/dev/null | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // "allow"')" == "deny" ]]; then
  ok "git hooks t2: an UNMERGED spec branch is still denied (the exemption did not become a hole)"
else
  bad "git hooks t2: an UNMERGED spec branch is still denied (the exemption did not become a hole)" \
      "clearing the spec-shaped flag on the ancestor path opened the close gate"
fi

# BARE `--ff` IS THE SAME HOLE UNDER A NAME THE DOCUMENTATION LEFT OUT (1.1.0
# adversarial review, F16). The block above pins `--ff-only` and nothing pinned `--ff`,
# so the README told a reader to watch for one flag while the other did exactly
# the same thing in exactly the same silence. Measured: it fast-forwards a spec
# branch with no Closing report onto the trunk, fires neither hook, and the
# resulting tip has ONE parent. Asserted here so the pair stays in step, which
# is the whole point of the hole ledger.
GHF2="$WORK/gh-ff"; gh_fixture "$GHF2" no
assert_true "git hooks p2-0: the fixture can actually fast-forward (trunk is an ancestor)" \
  "the trunk is not an ancestor of the spec branch, so --ff cannot apply and the case below tests nothing" \
  git -C "$GHF2" merge-base --is-ancestor main spec/0001-thing
GHF2_OUT="$( cd "$GHF2" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff spec/0001-thing 2>&1 )"
if gh_landed "$GHF2"; then
  ok "git hooks p2: bare --ff skips the merge hooks exactly as --ff-only does (documented hole, still open)"
else
  bad "git hooks p2: bare --ff skips the merge hooks exactly as --ff-only does (documented hole, still open)" \
      "it did not land; git said: ${GHF2_OUT:-<no output>}"
fi
# And it really was a FAST-FORWARD rather than a merge commit that slipped past,
# because those are different facts and only one of them is this hole.
if [[ "$(git -C "$GHF2" rev-list --parents -n1 main | wc -w | tr -d ' ')" == "2" ]]; then
  ok "git hooks p3: the --ff result is a true fast-forward (one parent), so no merge commit existed for a hook to see"
else
  bad "git hooks p3: the --ff result is a true fast-forward (one parent), so no merge commit existed for a hook to see" \
      "the tip has more than one parent, so this tested a merge commit rather than the fast-forward hole"
fi

# The gate command's RUNNABILITY, asserted in both directions. Found by the v1.7
# dogfood gate: the hooks run gate_command in a bare shell, so a project whose
# toolchain lives in a virtualenv exits 127 and used to be refused with "does
# not pass", which is a different fact from "the suite failed". The operator who
# runs the same command in their own shell watches it pass and concludes the
# hook is broken; the next thing they reach for is SETLIST_SKIP_HOOKS=1, so a
# misleading refusal here costs the whole boundary.
GCF="$WORK/gate-cmd-runnable"; rm -rf "$GCF"; mkdir -p "$GCF/.claude"
# The missing command is invoked through a CHILD bash on purpose. This suite
# installs its own command_not_found_handle (see the top of this file) which
# turns a missing command into exit 1 with a helper-ordering message, so a
# gate_command naming the tool directly could never produce the 127 this case is
# about. The child shell has no such handler, which is also what a real hook
# sees when it evals a gate command in a bare shell.
printf '{"gate_command":"bash -c definitely-not-a-real-tool-xyz"}\n' > "$GCF/.claude/sdd.json"
GC_OUT="$( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCF" 2>&1 )"
case "$GC_OUT" in
  *"could not RUN here"*)
    ok "gate command: a gate that cannot RUN says so, instead of claiming the work failed" ;;
  *)
    bad "gate command: a gate that cannot RUN says so, instead of claiming the work failed" \
        "got: ${GC_OUT:-<no output>}" ;;
esac
# CONTROL: a gate that genuinely RAN and failed must still say so, or the case
# above would pass by relabelling every failure as an environment problem.
printf '{"gate_command":"echo boom-3-tests-broke; exit 1"}\n' > "$GCF/.claude/sdd.json"
GC_OUT2="$( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCF" 2>&1 )"
case "$GC_OUT2" in
  *"does not pass (exit 1)"*boom-3-tests-broke*)
    ok "gate command: a gate that RAN and failed reports its exit status and its output" ;;
  *)
    bad "gate command: a gate that RAN and failed reports its exit status and its output" \
        "got: ${GC_OUT2:-<no output>}" ;;
esac

# The three-way QA lockstep. close-gate.sh and trunk-audit.sh were asserted
# identical by item 35; the git-hook library is now the third copy of the same
# rule and joins the same assertion.
LIB_QA_RE="$(grep -m1 -E '^[[:space:]]*SLH_QA_PASS1_AWK=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
  | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
CG_QA_RE2="$(grep -m1 -E '^[[:space:]]*QA_PASS1_AWK=' "$HOOKS/close-gate.sh" | sed 's/^[[:space:]]*//')"
if [[ -n "$LIB_QA_RE" && "$LIB_QA_RE" == "$CG_QA_RE2" ]]; then
  ok "git hooks k: the hook library's QA verdict program matches close-gate.sh byte for byte"
else
  bad "git hooks k: the hook library's QA verdict program matches close-gate.sh byte for byte" \
      "lib has [$LIB_QA_RE] and close-gate has [$CG_QA_RE2]"
fi

# THE CHORE LOCKSTEP (F30's fix). The chore-completion rule now lives in the hook
# library AND in trunk-audit.sh, which is the same two-copies-of-one-rule shape as
# leg 5's F8, where a gate and its only backstop went blind the same way at the
# same time. Asserted byte for byte rather than trusted, because the whole reason
# the QA rule has this assertion is that nobody can hold three copies in their head.
LIB_CHORE_RE="$(grep -m1 -E '^[[:space:]]*SLH_CHORE_DONE_RE=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
  | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
AUDIT_CHORE_RE="$(grep -m1 -E "^[[:space:]]*CHORE_DONE_RE=" "$ROOT/scripts/trunk-audit.sh" | sed 's/^[[:space:]]*//')"
if [[ -n "$LIB_CHORE_RE" && "$LIB_CHORE_RE" == "$AUDIT_CHORE_RE" ]]; then
  ok "chore route a: the chore-completion rule matches trunk-audit.sh byte for byte"
else
  bad "chore route a: the chore-completion rule matches trunk-audit.sh byte for byte" \
      "lib has [$LIB_CHORE_RE] and the audit has [$AUDIT_CHORE_RE]"
fi

# And the rule has to be the one the EDITION documents, not merely two matching
# copies of something nobody wrote down. Part 5b's archive-line example is the
# contract; if the example stops satisfying the regex the two agree on, the
# delivery has drifted from the prose again, which is the failure this whole
# cycle keeps repeating.
CHORE_RE_VALUE="$(printf '%s' "$LIB_CHORE_RE" | sed -e "s/^CHORE_DONE_RE='//" -e "s/'$//")"
EDITION_CHORE_LINE="$(grep -m1 -E '^- CHORE-[0-9]+: DONE ' "$ROOT/setlist.md" || true)"
if [[ -n "$EDITION_CHORE_LINE" ]] && printf '%s\n' "$EDITION_CHORE_LINE" | grep -qE "$CHORE_RE_VALUE"; then
  ok "chore route b: Part 5b's own archive-line example satisfies the shipped chore rule"
else
  bad "chore route b: Part 5b's own archive-line example satisfies the shipped chore rule" \
      "edition line [${EDITION_CHORE_LINE:-<none found>}] against [$CHORE_RE_VALUE]"
fi

# The NEGATIVE direction of the same rule, and it is the one that matters. The
# loosening is only safe if a completion claimed inside a SENTENCE does not count:
# "this is done once CHORE-007 lands" is a note, not a record, and the same
# distinction (a field, not a word in a sentence) is what leg 5's F8 was about.
if printf -- '- this is done once CHORE-007 lands\n' | grep -qE "$CHORE_RE_VALUE"; then
  bad "chore route c: a chore mentioned in a sentence is not a completion record" \
      "the rule matched prose"
else
  ok "chore route c: a chore mentioned in a sentence is not a completion record"
fi

# THE STAMPED TEMPLATE MUST NOT SHIP A SATISFIED RECORD. Found by the 1.1.0
# adversarial review (finder/content-as-code, BLOCKER) against the Phase 4 fix that
# introduced it: the STATUS.md template's own EXAMPLE archive line matched the
# chore rule, so every stamped instance shipped a pre-satisfied completion and a
# branch that ADDS specs/STATUS.md could carry arbitrary role-path code onto the
# trunk while the audit reported clean. In the other direction a genuine CHORE-007
# was then refused, because the example already made that number non-new.
#
# This is leg 5's F7 ("a fenced example is not a closing report") in a second
# costume, and the guard is the general form rather than the fix: no line of any
# stamped template may satisfy the rule, so the next example someone writes cannot
# reintroduce it.
# NOT `grep -c ... || printf 0`. That was the first cut and it is plugin 1.0.3's
# F2 verbatim: grep -c PRINTS 0 and EXITS 1 when nothing matches, so the fallback
# fires too and the variable becomes "0\n0", which is not an integer and makes the
# numeric test a silent error. Writing the repo's own catalogued defect into the
# assertion meant to prevent a class from recurring is worth the comment.
# grep -q has no count to mangle and no fallback to double-fire.
if grep -qE "$CHORE_RE_VALUE" "$ROOT/templates/specs/STATUS.md.tmpl" 2>/dev/null; then
  bad "chore route d: the stamped STATUS.md template ships no line the chore rule accepts" \
      "$(grep -nE "$CHORE_RE_VALUE" "$ROOT/templates/specs/STATUS.md.tmpl" | head -3)"
else
  ok "chore route d: the stamped STATUS.md template ships no line the chore rule accepts"
fi

fi; shard_region_end
# <<< SHARD-END advisory-flip
# =============================================================================
# THE LIVE-TEXT RULE (2026-08 consolidation, blocker F2 and the row readers).
# STATUS.md is judged by what a human sees in the rendered file: fenced blocks,
# HTML comment spans and indented-code lines are illustrations, not records.
# Four pins, because the F2 class was never one defect: the rule itself, its
# two byte-identical copies, the routing that keeps every reader behind it, and
# the writers' one-write-path sibling from the same sweep.
# =============================================================================

# Pin 1: all THREE copies are byte-identical, the QA/chore lockstep shape.
# close-gate.sh joined the reader in the second adversary round (it read the
# STATUS row raw), so it is the third layer that must agree, exactly as it is
# for QA_PASS1_AWK and TEMPLATE_FENCE_AWK.
LIB_LIVE_AWK="$(grep -m1 -E '^[[:space:]]*SLH_LIVE_TEXT_AWK=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
  | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
LIVE_LOCK_BAD=""
for live_lock_f in "$ROOT/scripts/trunk-audit.sh" "$HOOKS/close-gate.sh"; do
  live_lock_v="$(grep -m1 -E '^[[:space:]]*SLH_LIVE_TEXT_AWK=' "$live_lock_f" | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
  if [[ -z "$live_lock_v" ]]; then
    LIVE_LOCK_BAD="$LIVE_LOCK_BAD $(basename "$live_lock_f"):absent"
  elif [[ "$live_lock_v" != "$LIB_LIVE_AWK" ]]; then
    LIVE_LOCK_BAD="$LIVE_LOCK_BAD $(basename "$live_lock_f"):differs"
  fi
done
if [[ -n "$LIB_LIVE_AWK" && -z "$LIVE_LOCK_BAD" ]]; then
  ok "live text a: SLH_LIVE_TEXT_AWK is byte-identical in the hook library, trunk-audit.sh and close-gate.sh"
else
  bad "live text a: SLH_LIVE_TEXT_AWK is byte-identical in the hook library, trunk-audit.sh and close-gate.sh" \
      "lib-empty=[${LIB_LIVE_AWK:0:1}] disagreements:$LIVE_LOCK_BAD"
fi

# FREEZE AMENDMENT 1 (V19-F6, 2026-08-26): a CONTAINER-PREFIXED table row is not
# a record. The reader printed blockquote and list-item lines verbatim, prefix
# and all, and a real GFM row starts with '|' so its field 1 is empty: a '> ' or
# '- ' prefix simply BECAME field 1 and the illustrative row's cells landed in
# $2 and $4 exactly like a real row's. Measured at the guarantee layer: the
# blockquote and list-item merges exited 0 and landed while the fenced control
# was refused.
#
# The controls are the point of this block. Deleting container-prefixed lines
# wholesale would take the CHORE ROUTE with it, because a chore archive line IS
# a list item; the rule keys on the pipe, not on the bullet, and the last two
# cases are what says so. Watched RED first: the three subjects all read CLOSED
# on the pre-amendment bytes with every control already green.
# Both values are extracted here rather than reused from below, because the pins
# that define them run AFTER this block and a forward reference would silently
# run these cases against an EMPTY awk program: every line would survive, the
# subjects would read CLOSED, and the failure would look like the defect.
LT_AWK="$(printf '%s' "$LIB_LIVE_AWK" | sed -e "s/^LIVE_TEXT_AWK='//" -e "s/'\$//")"
LT_CHORE_RE="$(grep -m1 -E '^[[:space:]]*SLH_CHORE_DONE_RE=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
  | sed -e 's/^[[:space:]]*//' -e "s/^SLH_CHORE_DONE_RE='//" -e "s/'\$//")"
if [[ -z "$LT_AWK" || -z "$LT_CHORE_RE" ]]; then
  bad "live text i: the amendment corpus has a program to run" \
      "awk-empty=[${LT_AWK:0:1}] chore-re-empty=[${LT_CHORE_RE:0:1}]; an empty program keeps every line and would make these cases pass for the wrong reason"
fi
lt_row_closed() { # lt_row_closed <status-text> -> 0 when spec 0003 reads CLOSED
  printf '%s\n' "$1" | awk "$LT_AWK" | sed 's/\\|/ /g' \
    | awk -F'|' -v num=0003 'function t(x){gsub(/^[[:space:]]+|[[:space:]]+$/,"",x);return x} NF>=4 && t($2)==num && toupper(t($4))=="CLOSED"{f=1} END{exit(f?0:1)}'
}
LT_HDR='# inv

| Spec | Title | Status | Note |
| --- | --- | --- | --- |'
for lt_case in "real:| 0003 | Thing | CLOSED | done |:CLOSED" \
               "indented:   | 0003 | Thing | CLOSED | done |:CLOSED" \
               "blockquote:> | 0003 | Thing | CLOSED | done |:HIDDEN" \
               "listitem:- | 0003 | Thing | CLOSED | done |:HIDDEN" \
               "quotedlist:> - | 0003 | Thing | CLOSED | done |:HIDDEN"; do
  lt_name="${lt_case%%:*}"; lt_rest="${lt_case#*:}"
  lt_line="${lt_rest%:*}"; lt_want="${lt_rest##*:}"
  if lt_row_closed "$LT_HDR
$lt_line"; then lt_got=CLOSED; else lt_got=HIDDEN; fi
  if [[ "$lt_got" == "$lt_want" ]]; then
    ok "live text i [$lt_name]: a container-prefixed row is not a record, a real row still is"
  else
    bad "live text i [$lt_name]: a container-prefixed row is not a record, a real row still is" \
        "wanted $lt_want, measured $lt_got. A quotation of a row is not the row (V19-F6); dropping a REAL row instead would launder a spec past the row-flip union check"
  fi
done
# The chore route, both directions, because the rule must not have eaten it.
LT_CHORE="$(printf '%s\n' "$LT_HDR

- CHORE-007: DONE 2026-08-26. did a thing" | awk "$LT_AWK")"
if printf '%s\n' "$LT_CHORE" | grep -qE "$LT_CHORE_RE"; then
  ok "live text i control: a LIVE chore archive line is still a list item and still counts"
else
  bad "live text i control: a LIVE chore archive line is still a list item and still counts" \
      "the amendment ate the chore route: an archive line IS a list item, so a rule keyed on the bullet rather than on the pipe removes the chore route entirely"
fi

# Pin 2: the rule's semantics, asserted on the program itself. Each hidden
# spelling reads as absent; the live line and the live row survive. This is
# the corpus the leg replayed, mechanised at the cheapest layer that decides.
LIVE_AWK_VALUE="$(printf '%s' "$LIB_LIVE_AWK" | sed -e "s/^LIVE_TEXT_AWK='//" -e "s/'$//")"
LIVE_IN="$(printf '%s\n' \
  '- CHORE-001: DONE 2026-01-01. live archive line' \
  '| 0001 | x | CLOSED | live row |' \
  '<!-- - CHORE-002: DONE 2026-01-01. hidden in a comment -->' \
  '<!-- | 0011 | z | CLOSED | commented row | -->' \
  'live text <!-- inline comment --> tail survives' \
  'visible prefix <!-- reviewer aside opens mid-line' \
  '- CHORE-042: DONE 2026-01-01. hidden by a mid-line comment open' \
  '| 0042 | q | CLOSED | hidden row after mid-line open |' \
  '-->' \
  '```text' \
  '- CHORE-003: DONE 2026-01-01. fenced example' \
  '| 0009 | y | CLOSED | fenced row |' \
  'x <!-- not a comment: this open sits inside a code fence' \
  '```' \
  '    - CHORE-004: DONE 2026-01-01. indented example' \
  '   ```text' \
  '   - CHORE-055: DONE 2026-01-01. indented-fence example' \
  '   | 0055 | i | CLOSED | indented-fence row |' \
  '   ```' \
  '> ```text' \
  '> - CHORE-066: DONE 2026-01-01. blockquoted-fence example' \
  '> | 0066 | b | CLOSED | blockquoted-fence row |' \
  '> ```' \
  '- ```' \
  '  - CHORE-088: DONE 2026-01-01. list-item-fence example' \
  '  | 0088 | l | CLOSED | list-item-fence row |' \
  '  ```' \
  '1. ```text' \
  '   - CHORE-099: DONE 2026-01-01. ordered-list-fence example' \
  '   | 0099 | n | CLOSED | ordered-fence row |' \
  '   ```' \
  '- ```' \
  '  - ```' \
  '  CHORE-111: DONE 2026-01-01. body after a forged-close line' \
  '  ```' \
  '```text' \
  'a bare top-level fence' \
  '> ```' \
  '- CHORE-122: DONE 2026-01-01. after a blockquote-marker forged close' \
  '| 0122 | q | CLOSED | forged-close row |' \
  '```' \
  '> How to archive, for reference:' \
  '>' \
  '>     CHORE-133: DONE 2026-01-01. indented code inside a blockquote' \
  '>     | 0133 | c | CLOSED | blockquote-indented-code row |' \
  '-     CHORE-144: DONE 2026-01-01. indented code inside a list item' \
  '-     | 0144 | d | CLOSED | list-item-indented-code row |' \
  '<script>' \
  '- CHORE-155: DONE 2026-01-01. hidden in a script HTML block' \
  '| 0155 | s | CLOSED | script-block row |' \
  '</script>' \
  '<pre>' \
  '- CHORE-177: DONE 2026-01-01. renders as a code block, not a record' \
  '| 0177 | p | CLOSED | pre-block row |' \
  '</pre>' \
  '<details><summary>archive</summary>' \
  '' \
  '- CHORE-199: DONE 2026-01-01. collapsed, not shown by default' \
  '| 0199 | e | CLOSED | details-block row |' \
  '' \
  '</details>' \
  '' \
  '    - CHORE-166: DONE 2026-01-01. a real indented code block after a blank' \
  '<!-->' \
  '- CHORE-001b: DONE 2026-01-01. a LIVE list-item chore that must survive' \
  '- CHORE-777: DONE 2026-01-01. live again after the fence closed')"
LIVE_OUT="$(printf '%s\n' "$LIVE_IN" | awk "$LIVE_AWK_VALUE")"
LIVE_BAD=""
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-001' || LIVE_BAD="$LIVE_BAD live-chore-dropped"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0001 |' || LIVE_BAD="$LIVE_BAD live-row-dropped"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-002' && LIVE_BAD="$LIVE_BAD comment-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-003' && LIVE_BAD="$LIVE_BAD fence-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0009 |' && LIVE_BAD="$LIVE_BAD fenced-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-004' && LIVE_BAD="$LIVE_BAD indent-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0011 |' && LIVE_BAD="$LIVE_BAD commented-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'tail survives' || LIVE_BAD="$LIVE_BAD inline-tail-dropped"
# The mid-line comment open (second adversary round): the visible prefix
# survives, everything the comment hides drops, and text after the close is
# live again. The fake fence marker must NOT trip comment state.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-042' && LIVE_BAD="$LIVE_BAD midline-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0042 |' && LIVE_BAD="$LIVE_BAD midline-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'visible prefix' || LIVE_BAD="$LIVE_BAD midline-prefix-dropped"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-777' || LIVE_BAD="$LIVE_BAD post-comment-dropped"
# A fence indented 1-3 spaces renders as a code block; its body must strip too.
# The rule missed this until its left-trim caught up with its siblings (third
# adversary round). Both the hidden chore and the hidden row must go.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-055' && LIVE_BAD="$LIVE_BAD indented-fence-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0055 |' && LIVE_BAD="$LIVE_BAD indented-fence-row-kept"
# A fence inside a blockquote or a list item renders as a quoted/listed code
# example; the readers tolerate the block prefix, so the strip must see the
# fence through it (third adversary round). Both the hidden chore and row go,
# and a LIVE list-item chore at column 0 must still survive.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-066' && LIVE_BAD="$LIVE_BAD blockquote-fence-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0066 |' && LIVE_BAD="$LIVE_BAD blockquote-fence-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-088' && LIVE_BAD="$LIVE_BAD list-fence-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0088 |' && LIVE_BAD="$LIVE_BAD list-fence-row-kept"
# An ordered-list step (1. ```) is a container the readers see through too
# (round 4), and a bullet-prefixed line INSIDE an open fence must not forge a
# close and leak the rest of the block (round 4, distinct root cause).
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-099' && LIVE_BAD="$LIVE_BAD ordered-fence-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0099 |' && LIVE_BAD="$LIVE_BAD ordered-fence-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-111' && LIVE_BAD="$LIVE_BAD forged-close-leak"
# A bare top-level fence must not be closed by a >-prefixed line at a different
# blockquote depth (round 5): the marker peel on close forged an early close and
# leaked the record after it, the >-analog of the round-4 bullet forge.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-122' && LIVE_BAD="$LIVE_BAD bq-forged-close-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0122 |' && LIVE_BAD="$LIVE_BAD bq-forged-close-row-kept"
# Four-space indented code inside a blockquote renders as a <pre> example; the
# indent must be read relative to the blockquote depth (round 6), not discarded
# by the marker peel.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-133' && LIVE_BAD="$LIVE_BAD bq-indent-code-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0133 |' && LIVE_BAD="$LIVE_BAD bq-indent-code-row-kept"
# Indented code inside a LIST ITEM (marker + 5 spaces) renders as <pre> too
# (round 7); and an abrupt empty comment <!--> must close on its own line, not
# hide every following record to EOF (round 7) -- if it did not close, the live
# CHORE-001b after it would be dropped, which the live-list check below catches.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-144' && LIVE_BAD="$LIVE_BAD list-indent-code-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0144 |' && LIVE_BAD="$LIVE_BAD list-indent-code-row-kept"
# A <script>/<style>/<textarea> HTML block is deleted by GitHub's sanitizer, so
# its content is invisible (round 8); and a genuine indented code block after a
# blank line is still stripped, while the lazy-continuation case above is kept.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-155' && LIVE_BAD="$LIVE_BAD script-block-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0155 |' && LIVE_BAD="$LIVE_BAD script-block-row-kept"
# <pre> renders as a code block (round 11), so its content strips like a fence.
# <details> is a CommonMark type-6 block whose content renders as a LIVE
# (collapsible, diff-visible) table, so it is KEPT like <div>/<table> (round 12):
# stripping it to </details> over-swallowed and dropped a live CLOSED row, which
# escaped the row-flip union check (direction ii). Both directions are pinned.
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-177' && LIVE_BAD="$LIVE_BAD pre-block-chore-kept"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0177 |' && LIVE_BAD="$LIVE_BAD pre-block-row-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-199' || LIVE_BAD="$LIVE_BAD details-chore-dropped"
printf '%s\n' "$LIVE_OUT" | grep -q '| 0199 |' || LIVE_BAD="$LIVE_BAD details-row-dropped"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-166' && LIVE_BAD="$LIVE_BAD indented-code-after-blank-kept"
printf '%s\n' "$LIVE_OUT" | grep -q 'CHORE-001b' || LIVE_BAD="$LIVE_BAD live-list-chore-dropped-or-comment-ate-to-eof"
if [[ -z "$LIVE_BAD" ]]; then
  ok "live text b: hidden spellings (comment inc. mid-line, fence inc. indented, indent) read as absent; live text survives"
else
  bad "live text b: hidden spellings (comment inc. mid-line, fence inc. indented, indent) read as absent; live text survives" \
      "divergences:$LIVE_BAD"
fi

# Pin 3: the ROUTING. The strip lives at the extraction points, so a reader
# added later cannot be blind by default. Every git-show of specs/STATUS.md in
# the audit, and both guard_close extractions in the library, must pipe
# through the rule; a new raw extraction fails here before a leg prices it.
AUDIT_RAW_STATUS="$(grep -nE 'show "[^"]*:specs/STATUS.md"' "$ROOT/scripts/trunk-audit.sh" | grep -v 'SLH_LIVE_TEXT_AWK' || true)"
if [[ -z "$AUDIT_RAW_STATUS" ]]; then
  ok "live text c: every STATUS.md extraction in trunk-audit.sh routes through the live-text rule"
else
  bad "live text c: every STATUS.md extraction in trunk-audit.sh routes through the live-text rule" \
      "raw extraction(s): $AUDIT_RAW_STATUS"
fi
LIB_RAW_STATUS="$(grep -nE '(slh_index_show|slh_head_show) "\$proj" specs/STATUS.md' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | grep -v 'SLH_LIVE_TEXT_AWK' || true)"
if [[ -z "$LIB_RAW_STATUS" ]]; then
  ok "live text d: both STATUS.md extractions in the hook library route through the live-text rule"
else
  bad "live text d: both STATUS.md extractions in the hook library route through the live-text rule" \
      "raw extraction(s): $LIB_RAW_STATUS"
fi
# close-gate.sh reads the STATUS row too (CG-NO-STATUS-ROW); its git-show of
# specs/STATUS.md must route through the rule, the gap the second adversary
# round found.
CG_RAW_STATUS="$(grep -nE 'show "[^"]*:specs/STATUS.md"' "$HOOKS/close-gate.sh" | grep -v 'SLH_LIVE_TEXT_AWK' || true)"
if [[ -z "$CG_RAW_STATUS" ]]; then
  ok "live text e: close-gate.sh's STATUS.md extraction routes through the live-text rule"
else
  bad "live text e: close-gate.sh's STATUS.md extraction routes through the live-text rule" \
      "raw extraction(s): $CG_RAW_STATUS"
fi

# Pin: the DIAGRAM-field reader routes through the live-text rule too (F6,
# plugin-2.0.0 adversarial review). Pins c/d/e above covered only the STATUS.md
# extractions, so the Architecture-diagram field reader stayed a RAW grep of the
# spec file while its sibling STATUS-row reader was stripped: a fenced
# 'Architecture diagram: no impact' example satisfied the mandatory close
# condition at every layer including the push-time audit, and this pin family
# stayed green through it because it named STATUS.md alone. Generalised here to
# the field reader: every 'Architecture diagram:' reader, in all three lockstep
# files, must pipe through the rule, so a fourth sibling cannot be blind by
# default. A new raw field reader fails here before a leg prices it.
# The selection moved from `tail -n1` to `head -n1` at KL1's ruling (2026-08-29,
# first-match), so this pin's own pattern moved with it. The PROPERTY is
# unchanged and is the point: every reader pipes through the live-text rule.
DIAG_RAW="$(grep -rnE "Architecture diagram:'.*head -n1" "$HOOKS/close-gate.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ROOT/scripts/trunk-audit.sh" | grep -v 'SLH_LIVE_TEXT_AWK' || true)"
DIAG_COUNT="$(grep -rcE "Architecture diagram:'.*head -n1" "$HOOKS/close-gate.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ROOT/scripts/trunk-audit.sh" | awk -F: '{s+=$2} END{print s+0}')"
if [[ -z "$DIAG_RAW" && "$DIAG_COUNT" -eq 4 ]]; then
  ok "live text h: every Architecture-diagram field reader (4, across the three lockstep files) routes through the live-text rule"
else
  bad "live text h: every Architecture-diagram field reader routes through the live-text rule" \
      "found $DIAG_COUNT reader(s) (expect 4); raw (unrouted): ${DIAG_RAW:-none}"
fi

# Pin: the live-text program uses NO {n,m} interval. The git hooks run under
# whatever awk the platform provides, and on Debian/Ubuntu that is mawk, whose
# 1.3.3 lineage REJECTS interval expressions in a regex; a `#{1,6}` added in the
# round-9 heading rule made SLH_LIVE_TEXT_AWK error at load on the CI runner's
# awk, so every close-gate/trunk-audit/guard_close read of STATUS returned empty
# and denied compliant merges (60 red on Linux, green on the BWK-awk macOS leg).
# grep -E intervals elsewhere are fine (POSIX grep supports them); this checks
# the awk PROGRAM only. Byte-identity is already pinned, so checking one copy is
# enough, but all three are checked to name the offender.
LT_INTERVAL_BAD=""
for lt_awk_f in "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ROOT/scripts/trunk-audit.sh" "$HOOKS/close-gate.sh"; do
  lt_awk_v="$(grep -m1 -E "^[[:space:]]*SLH_LIVE_TEXT_AWK=" "$lt_awk_f")"
  if printf '%s' "$lt_awk_v" | grep -qE '\{[0-9]+,[0-9]*\}'; then
    LT_INTERVAL_BAD="$LT_INTERVAL_BAD $(basename "$lt_awk_f")"
  fi
done
if [[ -z "$LT_INTERVAL_BAD" ]]; then
  ok "live text g: SLH_LIVE_TEXT_AWK carries no {n,m} interval, so it loads on mawk as well as gawk and the BWK awk"
else
  bad "live text g: SLH_LIVE_TEXT_AWK carries no {n,m} interval, so it loads on mawk as well as gawk and the BWK awk" \
      "interval(s) present in:$LT_INTERVAL_BAD -- old mawk rejects them and the whole reader returns empty"
fi

# The row readers handle a GFM \|-escaped pipe (round 11). A CLOSED row whose
# Title cell carries a literal pipe via \| renders as closed to a human, but a
# naive awk -F'|' split shifts CLOSED out of field 4 and the flip escapes the
# union check. slh_row_closed and the audit's row_is_closed must still read it
# CLOSED; source the library so this exercises the shipped function, not a copy.
( unset -f slh_row_closed 2>/dev/null; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null
  if slh_row_closed '| 0002 | Fix a\|b parser | CLOSED | shipped |' 0002; then exit 0; else exit 1; fi ) \
  && ok "row reader escaped-pipe: a CLOSED row with a \\|-escaped pipe in its Title still reads closed" \
  || bad "row reader escaped-pipe: a CLOSED row with a \\|-escaped pipe in its Title still reads closed" \
         "the -F'|' split counted the escaped pipe as a separator, so a real close-flip escaped the union check (R3-2 via GFM escape)"

# Pin 4: the WRITER sibling from the same sweep (leg F1's class). No writer in
# the delivery scripts copies into .claude/hooks/ with a bare cp; the one
# write rule (setlist_deliver_file / setlist_deliver_dest_unsafe) is the only
# route, and both delivery scripts consult it. A new bare copy, or a consumer
# dropping the check, fails here before a leg prices it.
BARE_ADVISORY_CP="$(grep -nE '\bcp .*\.claude/hooks/' "$ROOT/scripts/stamp.sh" "$ROOT/scripts/refresh-instance.sh" | grep -vE ':[[:space:]]*#' | grep -v 'setlist_deliver_file' || true)"
if [[ -z "$BARE_ADVISORY_CP" ]]; then
  ok "one write rule a: no bare cp into .claude/hooks/ remains in the delivery scripts"
else
  bad "one write rule a: no bare cp into .claude/hooks/ remains in the delivery scripts" \
      "bare copies: $BARE_ADVISORY_CP"
fi
OWR_STAMP="$(grep -c 'setlist_deliver_dest_unsafe' "$ROOT/scripts/stamp.sh" || true)"
OWR_REFRESH="$(grep -c 'setlist_deliver_dest_unsafe' "$ROOT/scripts/refresh-instance.sh" || true)"
if [[ "$OWR_STAMP" -ge 1 && "$OWR_REFRESH" -ge 1 ]]; then
  ok "one write rule b: both delivery scripts consult the destination check (stamp=$OWR_STAMP refresh=$OWR_REFRESH sites)"
else
  bad "one write rule b: both delivery scripts consult the destination check" \
      "stamp=$OWR_STAMP refresh=$OWR_REFRESH consult sites; a consumer with zero sites has left the one write rule"
fi

# Pin 5: indented code CANNOT interrupt a paragraph (round 8, direction ii). A
# four-space-indented CLOSED row directly under a text line is a lazy
# continuation a renderer SHOWS, so the strip must KEEP it (dropping it would
# let a row-flip close escape the union check and launder a spec); the SAME row
# after a blank line is a real code block and must be STRIPPED. This is the one
# case where over-stripping is a bypass, not a cooperative refusal, so it is
# pinned in both directions.
LT_LAZY="$(printf '%s\n' 'Delivered in this branch:' '    | 0207 | X | CLOSED | lazy continuation, visible |' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
LT_CODE="$(printf '%s\n' 'intro paragraph' '' '    | 0208 | Y | CLOSED | real indented code block |' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
# Only a genuine PARAGRAPH makes a following indented line a lazy continuation
# (round 9). After a heading, a setext underline or a thematic break, with no
# blank, the indented line is a code block, and keeping it admitted a laundered
# chore/row through SLH-CLOSES-NO-SPEC. STATUS.md naturally carries headings, so
# this is pinned for all three non-paragraph shapes.
LT_HEAD="$(printf '%s\n' '## Spec inventory' '    | 0209 | Z | CLOSED | code after heading |' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
LT_SETEXT="$(printf '%s\n' 'Section Title' '===' '    CHORE-210: DONE code after setext' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
LT_HR="$(printf '%s\n' '---' '    CHORE-211: DONE code after thematic break' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
# A GFM table is not a paragraph (round 10): an indented line right after the
# inventory table is code, but a lone pipe row (no delimiter) is a paragraph and
# keeps its continuation.
LT_TABLE="$(printf '%s\n' '| S | St |' '|---|---|' '| 0001 | ACTIVE |' '    | 0212 | W | CLOSED | code after table |' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
LT_LONEPIPE="$(printf '%s\n' 'One lone pipe paragraph row:' '    | 0213 | V | CLOSED | lazy after prose |' | awk "$LIVE_AWK_VALUE" 2>/dev/null)"
LT_PARA_BAD=""
printf '%s\n' "$LT_LAZY" | grep -q '| 0207 |' || LT_PARA_BAD="$LT_PARA_BAD lazy-continuation-row-dropped"
printf '%s\n' "$LT_CODE" | grep -q '| 0208 |' && LT_PARA_BAD="$LT_PARA_BAD code-after-blank-kept"
printf '%s\n' "$LT_HEAD" | grep -q '| 0209 |' && LT_PARA_BAD="$LT_PARA_BAD code-after-heading-kept"
printf '%s\n' "$LT_SETEXT" | grep -q 'CHORE-210' && LT_PARA_BAD="$LT_PARA_BAD code-after-setext-kept"
printf '%s\n' "$LT_HR" | grep -q 'CHORE-211' && LT_PARA_BAD="$LT_PARA_BAD code-after-hr-kept"
printf '%s\n' "$LT_TABLE" | grep -q '| 0212 |' && LT_PARA_BAD="$LT_PARA_BAD code-after-table-kept"
printf '%s\n' "$LT_LONEPIPE" | grep -q '| 0213 |' || LT_PARA_BAD="$LT_PARA_BAD lonepipe-lazy-dropped"
if [[ -z "$LT_PARA_BAD" ]]; then
  ok "live text f: an indented line is a lazy continuation only after a real paragraph; after a heading/setext/HR/table or a blank it is code"
else
  bad "live text f: an indented line is a lazy continuation only after a real paragraph; after a heading/setext/HR or a blank it is code" \
      "divergences:$LT_PARA_BAD -- a dropped lazy row launders (ii), a kept code line admits on the excuse (i)"
fi

# The lifecycle enumeration is now in a fourth place too.
GHOOK_STATES="$(grep -m1 -E "^SLH_LIFECYCLE_STATES=" "$ROOT/templates/git-hooks/pre-commit" \
  | sed -e "s/^SLH_LIFECYCLE_STATES='//" -e "s/'.*$//" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [[ "$GHOOK_STATES" == "$CANON_STATES" ]]; then
  ok "git hooks l: pre-commit's lifecycle enumeration equals the edition's canonical block"
else
  bad "git hooks l: pre-commit's lifecycle enumeration equals the edition's canonical block" \
      "pre-commit has [$GHOOK_STATES] and the edition has [$CANON_STATES]"
fi

