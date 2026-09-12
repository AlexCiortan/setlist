#!/usr/bin/env bash
# test/suite/07-pre-push-and-suite-audits.sh: shard 7 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE OPT-IN PRE-PUSH HOOK (1.0.5, Tier 3 Stage A's delivery half)
# Both directions, plus the refusal that matters most: a check that cannot
# find its own tool must NOT exit 0.
# =============================================================================

PP="$ROOT/templates/git-hooks/pre-push"
# STDIN IS CLOSED ON EVERY HAND-INVOCATION OF pre-push, and it must be.
#
# git feeds pre-push its refspecs on stdin. A test that invokes the hook
# directly supplies none, and `read` then BLOCKS until EOF: with stdin inherited
# from a pipe that never closes, the suite hangs forever rather than failing.
# Measured 2026-08-07: a suite run sat for 90 minutes inside this fixture with
# no output. The hook already handles empty stdin as its documented
# hand-invocation path, so </dev/null is what the test owed it.
PPD="$WORK/prepush-clean"; audit_fixture "$PPD" clean
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' </dev/null"
expect_script "pre-push a: a compliant trunk is allowed to push" 0

PPD="$WORK/prepush-dirty"; audit_fixture "$PPD" direct
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' </dev/null"
expect_script "pre-push b: feature code straight on the trunk refuses the push" 1 "did not arrive through a"

run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && SETLIST_SKIP_TRUNK_AUDIT=1 CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' </dev/null"
expect_script "pre-push c: the documented escape hatch works and says so" 0 "skipped by SETLIST_SKIP"

run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && bash '$PP' </dev/null"
expect_script "pre-push d: unable to find its own tool, it REFUSES rather than passing" 1 "has not passed"

# THE "AUDIT COULD NOT RUN" BRANCH IS REACHABLE (v1.7 gate, adversarial review F11).
#
# It was dead code: `RC=$?` sat after `if bash "$AUDIT" ...; then exit 0; fi`,
# and the status of an if-compound whose condition FAILED and which has no else
# branch is 0, not the condition's status. So RC was always 0, the RC==2 test
# never fired, and an audit that could not run at all was reported to the
# operator as "the trunk carries work that did not arrive through a closed spec",
# which is a statement about their history that nobody had checked.
#
# Not a bypass: both paths refuse, so the push is still blocked. It is a wrong
# diagnostic, which sends someone to rewrite history that may be perfectly fine.
PPD="$WORK/prepush-audit2"; audit_fixture "$PPD" clean
mkdir -p "$WORK/fakeplugin/scripts"
printf '#!/usr/bin/env bash\nprintf "trunk-audit.sh: simulated INVALID\\n" >&2\nexit 2\n' \
  > "$WORK/fakeplugin/scripts/trunk-audit.sh"
chmod +x "$WORK/fakeplugin/scripts/trunk-audit.sh"
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$WORK/fakeplugin' bash '$PP' </dev/null"
expect_script "pre-push f: an audit that CANNOT RUN is reported as such, not as a dirty trunk" 1 "could not run"

PPD="$WORK/prepush-noinstance"; rm -rf "$PPD"; mkdir -p "$PPD"; git_init "$PPD"
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' </dev/null"
expect_script "pre-push e: a repo that is not a framework instance is untouched" 0

# THE EMPTY-REMOTE FIRST-PUSH GAP (plugin-2.0.0 adversarial review, F1).
#
# On a FIRST push to an empty remote, `ls-remote --symref <remote> HEAD` prints
# nothing, so REMOTE_TRUNK is empty and REMOTE_UNREACHABLE is 0. A pushed branch
# whose name is not the local trunk used to miss PUSH_REFS, control fell through
# to auditing the LOCAL trunk, and unclosed feature code was ALLOWED onto the
# remote's about-to-be default branch, a ref the push never touched. The fix
# detects the empty remote (no HEAD symref AND no branch refs) and audits EVERY
# pushed ref as a trunk candidate. These invoke the hook the way git does, with a
# remote name and stdin refspecs, against a real bare remote, because the fall-
# through only exists on that path (the </dev/null tests above cannot reach it).
ZERO=0000000000000000000000000000000000000000
PPE="$WORK/prepush-emptyremote"; audit_fixture "$PPE" clean
git -C "$PPE" checkout -q -b spec/0009-raw
printf 'raw feature, no closed spec\n' >> "$PPE/src/f.js"
git -C "$PPE" add -A && git -C "$PPE" commit -qm "raw feature straight on a spec branch"
FOID="$(git -C "$PPE" rev-parse spec/0009-raw)"
MOID="$(git -C "$PPE" rev-parse main)"

# g: a feature branch pushed FIRST to an EMPTY remote is audited as trunk and refused.
git init --bare -q "$WORK/emptyremote-g.git"
git -C "$PPE" remote add origin_g "$WORK/emptyremote-g.git"
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPE' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' origin_g '$WORK/emptyremote-g.git' <<< 'refs/heads/spec/0009-raw $FOID refs/heads/spec/0009-raw $ZERO'"
expect_script "pre-push g: a feature branch pushed first to an EMPTY remote is audited as trunk and refused (F1)" 1 "did not arrive through a"

# h: a clean trunk pushed first to an EMPTY remote still bootstraps (allow).
git init --bare -q "$WORK/emptyremote-h.git"
git -C "$PPE" remote add origin_h "$WORK/emptyremote-h.git"
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPE' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' origin_h '$WORK/emptyremote-h.git' <<< 'refs/heads/main $MOID refs/heads/main $ZERO'"
expect_script "pre-push h: a clean trunk pushed first to an EMPTY remote still bootstraps (allow)" 0

# i: the same feature branch pushed to a NON-EMPTY remote (has a default) is an
# ordinary spec-branch push: content-scanned, NOT trunk-audited, allowed. This is
# the other direction, proving the fix did not widen the audit past the empty case.
git init --bare -q "$WORK/nonempty-i.git"
git -C "$PPE" remote add origin_i "$WORK/nonempty-i.git"
git -C "$PPE" push -q origin_i main:refs/heads/main
git -C "$WORK/nonempty-i.git" symbolic-ref HEAD refs/heads/main
git -C "$PPE" fetch -q origin_i
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPE' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' origin_i '$WORK/nonempty-i.git' <<< 'refs/heads/spec/0009-raw $FOID refs/heads/spec/0009-raw $ZERO'"
expect_script "pre-push i: a feature branch pushed to a NON-EMPTY remote is an ordinary spec push, allowed" 0

# DE14, the review-ref namespace (F4 of the 2.7.0 leg, fix round 1). The hook
# matches refs/heads/* and refs/tags/* and nothing else, so a push to Gerrit's
# refs/for/<branch> ran neither the content scan nor the trunk audit AND SAID
# NOTHING, leaving at exit 0 looking governed. The scope is unchanged by ruling,
# because teaching this hook another forge's ref grammar ships a spelling nobody
# here can exercise; what changed is the silence. Both directions in one case:
# the report fires by its CODE (never its prose, per the rule below), and the
# push is still ALLOWED, so a hook that has merely declined to audit a ref it
# does not own denies nothing. It reuses origin_i because a resolvable remote is
# what lets the rest of the hook run to its ordinary end.
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPE' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP' origin_i '$WORK/nonempty-i.git' <<< 'refs/heads/main $MOID refs/for/main $ZERO'"
expect_script "pre-push reviewref: a push to a namespace this hook does not read is REPORTED by code and still allowed" 0 "SLH-REF-NOT-AUDITED"

# =============================================================================
# NO TEST MAY MATCH A DENY ON ITS PROSE (cut worklist 4.5)
#
# Every denial carries a stable bracketed code precisely so the MESSAGE can be
# reworded without breaking a test. Item 8's promoted rider rewords the
# CG-SPEC-NOT-AUTHORED text to name the chore route, and the cut called that
# "cheap and safe because every denial now carries a stable code, so prose can
# move without breaking a test that was matching it".
#
# That was not true when it was written. `close-gate reuse a` matched the phrase
# "does not modify", straight out of the deny message, so the safe rewording
# would have gone red for a reason having nothing to do with behaviour. This
# check is what makes the claim true rather than aspirational.
#
# SCOPED TO CG-SPEC-NOT-AUTHORED, which is what the worklist names and what item
# 8 is about to reword. A first draft scanned EVERY deny message and reported 19
# hits, but nearly all of them are assertions on a domain term that happens to
# appear in the text ("em-dash", "CLOSED", "Closing report") rather than on the
# message's phrasing. Forcing all of those onto codes is a large unrelated
# refactor that no section-4 bullet authorises, so it is not done here; the
# narrow check that the cut actually promoted is, and the general version is
# noted as a candidate rather than smuggled in.
# =============================================================================
PROSE_VIOLATIONS=0
PROSE_CHECKED=0
# The verdict rule, hoisted into a function so BOTH directions of it can be
# asserted (F4/F10, 2026-08-11). A scan that read no input has not passed, and
# that has to be a property something can test rather than the shape of one
# branch nobody exercises.
prose_verdict() { # prose_verdict <checked> <violations> -> vacuous|ok|violations
  if [[ "$1" -eq 0 ]]; then printf 'vacuous'
  elif [[ "$2" -eq 0 ]]; then printf 'ok'
  else printf 'violations'; fi
}
# The one deny message this check governs, code stripped.
DENY_PROSE="$(grep -ho 'deny "close gate \[CG-SPEC-NOT-AUTHORED\][^"]*"' "$HOOKS"/close-gate.sh 2>/dev/null \
  | sed -e 's/^deny "//' -e 's/"$//')"
assert_true "deny-prose scan: the CG-SPEC-NOT-AUTHORED message was actually located" \
  "the deny text could not be extracted, so the scan below would compare against an empty string and pass" \
  test -n "$DENY_PROSE"
# Every substring an expect_deny asserts on.
while IFS= read -r want; do
  [[ -n "$want" ]] || continue
  PROSE_CHECKED=$((PROSE_CHECKED + 1))
  # A code is the contract; anything else has to be justified.
  case "$want" in
    CG-*|CM-*|SH-*|SLH-*) continue ;;
  esac
  # Only a phrase UNIQUE to this deny is dangerous. "Closing report" appears in
  # this message and in three others, and a test keyed to it is asserting on the
  # message that owns it, not on this one. Rewording CG-SPEC-NOT-AUTHORED cannot
  # break those; it can only break a test keyed to a phrase found nowhere else.
  OTHER_PROSE="$(grep -ho 'deny "[^"]*"' "$HOOKS"/*.sh 2>/dev/null \
    | sed -e 's/^deny "//' -e 's/"$//' | grep -vF 'CG-SPEC-NOT-AUTHORED')"
  if printf '%s\n' "$DENY_PROSE" | grep -qF -- "$want" \
     && ! printf '%s\n' "$OTHER_PROSE" | grep -qF -- "$want"; then
    PROSE_VIOLATIONS=$((PROSE_VIOLATIONS + 1))
    printf '       matches deny PROSE, not a code: [%s]\n' "$want"
  fi
done < <(grep -hoE 'expect_deny "[^"]*" "[^"]*"' "${SUITE_FILES[@]}" 2>/dev/null \
         | sed -E 's/.*" "([^"]*)"$/\1/')

assert_true "deny-prose scan: the scan actually found expect_deny assertions to check" \
  "it parsed zero assertions, so a clean result would mean nothing" \
  test "$PROSE_CHECKED" -gt 20
# F4/F10 of the 2026-08-11 leg: this printed
# "PASS ... (0 assertions scanned)" whenever the scan read nothing, which is a
# check reporting success having evaluated no input. Zero scanned is now its
# own FAILURE of this check rather than a pass sitting beside a separate red.
case "$(prose_verdict "$PROSE_CHECKED" "$PROSE_VIOLATIONS")" in
  vacuous)
    bad "no test matches CG-SPEC-NOT-AUTHORED on prose rather than on its stable code" \
        "the scan evaluated ZERO assertions, so this is not a pass: it is a check that ran over nothing" ;;
  ok)
    ok "no test matches CG-SPEC-NOT-AUTHORED on prose rather than on its stable code ($PROSE_CHECKED assertions scanned)" ;;
  *)
    bad "no test matches CG-SPEC-NOT-AUTHORED on prose rather than on its stable code" \
        "$PROSE_VIOLATIONS assertion(s) match that deny's text; item 8 rewords it, so they would go red for no behavioural reason" ;;
esac

# THE VACUITY RULE ITSELF, asserted in both directions. The rule is what the
# leg found missing, so it gets pinned rather than left as a shape in one
# branch of one case statement.
assert_true "suite F10a: zero assertions scanned is NOT a clean deny-prose result" \
  "prose_verdict called a scan of nothing clean, which is the vacuous-pass class this suite exists to catch" \
  test "$(prose_verdict 0 0)" = "vacuous"
assert_true "suite F10b: a real scan with no violations IS clean" \
  "prose_verdict refused a healthy scan, which is the false-denial direction" \
  test "$(prose_verdict 85 0)" = "ok"
assert_true "suite F10c: a real scan WITH violations is not clean" \
  "prose_verdict swallowed a violation" \
  test "$(prose_verdict 85 3)" = "violations"

# F4: THE SUITE MUST GIVE THE SAME VERDICT FROM ANY CWD, which line 9 of this
# file states as its usage. One read of its own path was relative, so run from
# anywhere but the repo root the scan above matched no file, parsed zero
# assertions and printed PASS, while the guard beside it turned the whole suite
# red on a healthy tree. Both directions of law 3 on a single line. Every other
# read in the file is rooted on $ROOT or $HOOKS; this pins that.
SUITE_SELF_REL="$(grep -hn 'test/run-tests\.sh' "${SUITE_FILES[@]}" 2>/dev/null \
  | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vF '$ROOT/test/run-tests.sh' || true)" # fail-open-ok: an empty result is the healthy case and is asserted as such below, never defaulted
assert_true "suite F4: every read of the suite's own file is rooted, not relative to the cwd" \
  "an unrooted self-read makes the verdict depend on the working directory: [$SUITE_SELF_REL]" \
  test -z "$SUITE_SELF_REL"

# =============================================================================
# APPENDIX C FIELD ORDERING (cut worklist 4.5)
#
# The close gate extracts the QA Pass 1 verdict block between two field markers,
# `QA Pass 1 report` and `QA Pass 2`. D4's migrations field and D5's
# open-criterion field must therefore land AFTER the QA Pass 2 field. D5's is the
# trap: it is ABOUT a blocked QA Pass 2 criterion, so its natural label begins
# with the exact string that TERMINATES the block, and placing it between the two
# anchors truncates the verdict out of the extraction and rebuilds the false
# denial plugin 1.0.2 shipped a fix for.
#
# Pinned behaviourally rather than by grepping Appendix C, so the guard holds
# whatever wording the fields end up with.
# =============================================================================
# The STRUCTURAL half: the fields v1.7 actually added must sit after the QA Pass
# 2 marker in Appendix C itself. The behavioural cases below pin the RULE; this
# pins the EDITION obeying it, which is the thing a future edit would break.
APXC="$(bash "$SCRIPTS/part.sh" appendix-c "$ROOT/setlist.md" 2>/dev/null)"
apxc_line() { printf '%s\n' "$APXC" | grep -nE "$1" | head -n1 | cut -d: -f1; }
QA1_LN="$(apxc_line '^[-*+[:space:]]*QA Pass 1 report')"
QA2_LN="$(apxc_line '^[-*+[:space:]]*QA Pass 2')"
assert_true "appendix C structure: both QA field markers are present to order against" \
  "one of the anchors is missing, so the ordering assertions below would compare against nothing" \
  test -n "$QA1_LN" -a -n "$QA2_LN"
for apxc_field in 'Open mandatory criterion' 'Migrations'; do
  FLN="$(apxc_line "^[-*+[:space:]]*${apxc_field}")"
  if [[ -z "$FLN" ]]; then
    bad "appendix C structure: the '$apxc_field' field exists" "no such field in Appendix C"
  elif [[ "$FLN" -gt "$QA2_LN" ]]; then
    ok "appendix C structure: '$apxc_field' lands after the QA Pass 2 marker"
  else
    bad "appendix C structure: '$apxc_field' lands after the QA Pass 2 marker" \
        "it sits at line $FLN, between the QA anchors ($QA1_LN and $QA2_LN), which truncates the verdict out of the close gate's extraction"
  fi
done
# And the label itself must not begin with the terminating string, belt and
# braces: a field named "QA Pass 2 criterion ..." placed correctly today becomes
# the trap the moment anybody reorders the section.
if printf '%s\n' "$APXC" | grep -qE '^[-*+[:space:]]*QA Pass 2 [A-Za-z]'; then
  bad "appendix C structure: no Closing-report field label begins with the block terminator" \
      "a field label starting 'QA Pass 2 ...' would end the QA extraction wherever it sits"
else
  ok "appendix C structure: no Closing-report field label begins with the block terminator"
fi

ACO="$WORK/appendixc-order"; close_fixture "$ACO" yes no answered yes no true
git -C "$ACO" checkout -q spec/0001-thing
insert_before "$ACO/specs/0001-thing.md" '- QA Pass 2 (human): done' \
  '- QA Pass 2 criterion blocked: STRUCTURALLY BLOCKED (no Mac reachable this session)'
printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n' > "$WORK/qa-blk.txt"
insert_block_before "$ACO/specs/0001-thing.md" '- QA Pass 2 criterion blocked: STRUCTURALLY BLOCKED (no Mac reachable this session)' "$WORK/qa-blk.txt"
git -C "$ACO" add -A >/dev/null 2>&1; git -C "$ACO" commit -qm "field between the anchors" >/dev/null 2>&1
git -C "$ACO" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$ACO" "$(bash_payload "$MERGE_CMD")"
expect_allow "appendix C ordering: a verdict BEFORE a QA-Pass-2-prefixed field still closes"

ACO2="$WORK/appendixc-order-bad"; close_fixture "$ACO2" yes no answered yes no true
git -C "$ACO2" checkout -q spec/0001-thing
# The trap, made concrete: the new field sits BETWEEN the anchors and ahead of
# the verdict, so the extraction ends before the verdict is ever seen.
insert_before "$ACO2/specs/0001-thing.md" '- QA Pass 2 (human): done' 'criterion 1: PASS'
insert_before "$ACO2/specs/0001-thing.md" 'criterion 1: PASS' \
  '- QA Pass 2 criterion blocked: STRUCTURALLY BLOCKED (no Mac reachable this session)'
git -C "$ACO2" add -A >/dev/null 2>&1; git -C "$ACO2" commit -qm "field ahead of the verdict" >/dev/null 2>&1
git -C "$ACO2" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$ACO2" "$(bash_payload "$MERGE_CMD")"
expect_deny "appendix C ordering: a QA-Pass-2-prefixed field AHEAD of the verdict truncates the block (the 1.0.2 false denial)" "CG-NO-QA-VERDICT"

