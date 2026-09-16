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
# NO TEST MAY MATCH A DENY ON ITS PROSE (cut worklist 4.5): the scan that stood
# here was scoped to CG-SPEC-NOT-AUTHORED's message and left with the close gate
# in 2.8.0 (spec 0144), with the three cases that tested its own verdict rule.
# =============================================================================

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

# The public README edition invariant and its publish gate, moved here from shard
# 05 in spec 0144 when that shard left with commit-gate.sh; neither reads a gate.
# =============================================================================
# THE PUBLIC README NAMES EXACTLY ONE EDITION (found in external review)
#
# publish/README.public.md line 12 said "edition v1.6" while four other lines in
# the same file said v1.7, so a publish would have named the shipping edition
# wrong in its opening paragraph. The staged export passed anyway, and THAT is
# the finding: publish-setlist.sh checked the README CONTAINS "edition v1.7" and
# never checked for the absence of a prior one, while CLAUDE.md describes the
# script as refusing "if publish/README.public.md still names a prior edition
# version". The description claimed more than the check did.
#
# Same class as the lifecycle-list drift this branch already caught: a fix that
# covered every copy somebody thought of. Two assertions, because they fail for
# different reasons: the INVARIANT (the file names one edition) runs on every
# commit and would have caught the defect the day it was written, and the GATE
# (the publish script refuses a stale one) is what stops it reaching a publish.
# =============================================================================
PUBR="$ROOT/publish/README.public.md"
if [[ ! -f "$PUBR" ]]; then
  ok "public README edition: SKIPPED, publish/ is absent (expected in the public repo, which does not carry the publish tooling)"
else
  ED_V="$(grep -oE '^\*\*Edition v[0-9]+\.[0-9]+' "$ROOT/setlist.md" | head -n1 | grep -oE 'v[0-9]+\.[0-9]+' || true)"
  assert_true "public README edition: the edition version was resolved from setlist.md" \
    "the Edition header could not be parsed, so the comparison below would compare against nothing" \
    test -n "$ED_V"
  # THE CLAIM LIVES ON ONE LINE, and the invariant is anchored there (narrowed
  # 2026-08-29 by owner ruling; the gate in publish-setlist.sh carries the full
  # reasoning and the cost). The self-description is the document's statement
  # about which edition users are getting; a provenance citation elsewhere
  # ("since v1.7") is a statement about when a claim was first made, and the
  # old whole-file rule could not tell those apart.
  PUB_SELF="$(grep -n 'The current edition of the framework document is' "$PUBR" | head -n1 || true)"
  PUB_SELF_EDS="$(printf '%s\n' "$PUB_SELF" | sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  PUB_SELF_STALE="$(printf '%s\n' "$PUB_SELF_EDS" | grep -v '^$' | grep -vx "$ED_V" || true)"
  if [[ -n "$PUB_SELF" && -z "$PUB_SELF_STALE" && -n "$PUB_SELF_EDS" ]]; then
    ok "public README edition: the self-description names $ED_V and no other edition"
  else
    bad "public README edition: the self-description names $ED_V and no other edition" \
        "line=[${PUB_SELF:-<absent>}] stale=[$(printf '%s' "$PUB_SELF_STALE" | tr '\n' ' ')]; an absent line is a failure, not a pass, because a check that cannot find its subject has not checked it"
  fi

  # THE SECOND CHECK, weaker and stated as such: every OTHER two-component
  # version must sit in a provenance construction. A bare stale version
  # anywhere in the file still fails, so the narrowing bought the ratified
  # boundary sentence and not a general exemption. Two-component versions only,
  # and never part of a three-component one, so a plugin version like v1.1.0 is
  # not mistaken for an edition.
  PUB_EDS="$(sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' "$PUBR" | sed -E 's/(since|in) v[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  PUB_STALE="$(printf '%s\n' "$PUB_EDS" | grep -v '^$' | grep -vx "$ED_V" || true)"
  if [[ -z "$PUB_STALE" ]]; then
    ok "public README edition: no BARE stale edition version outside a provenance citation"
  else
    bad "public README edition: no BARE stale edition version outside a provenance citation" \
        "it also names: $(printf '%s' "$PUB_STALE" | tr '\n' ' ')"
  fi

  # THE NARROWING IS NOT A HOLE, asserted rather than promised: a stale edition
  # planted BARE in the file must still fail the second check. Without this the
  # narrowing above is a claim about what the gate still catches, made by the
  # person who narrowed it.
  PUBN="$WORK/pub-narrow.md"; sed -e 's/$/ /' "$PUBR" > "$PUBN"
  printf 'This project has been on edition v0.9 for a while.\n' >> "$PUBN"
  PUBN_EDS="$(sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' "$PUBN" | sed -E 's/(since|in) v[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  if printf '%s\n' "$PUBN_EDS" | grep -qx 'v0.9'; then
    ok "public README edition control: a BARE stale version planted in the file is still caught after the narrowing"
  else
    bad "public README edition control: a BARE stale version planted in the file is still caught after the narrowing" \
        "the narrowing let a bare stale edition through, which is a hole and not a scoping decision"
  fi
fi

# The GATE itself, extracted verbatim from publish-setlist.sh and driven against
# a seeded stale README. Extracted rather than reimplemented, for the reason the
# CI scope check gives: a copy drifts, and then the test asserts things about a
# gate that is no longer the one running.
PUBSH="$ROOT/publish/publish-setlist.sh"
if [[ ! -f "$PUBSH" ]]; then
  ok "public README gate: SKIPPED, publish/ is absent (expected in the public repo)"
else
  PG="$WORK/pubgate"; rm -rf "$PG"; mkdir -p "$PG"
  awk '/# >>> EDITION-STRING-GATE-BEGIN/{f=1;next} /# <<< EDITION-STRING-GATE-END/{f=0} f' "$PUBSH" > "$PG/gate.sh"
  if [[ ! -s "$PG/gate.sh" ]]; then
    bad "public README gate: the EDITION-STRING-GATE markers exist in publish-setlist.sh" \
        "could not extract the gate; missing or renamed markers mean this check cannot run, which is a failure rather than a pass"
  else
    # THE SELF-DESCRIPTION LINE IS NOW THE GATE'S SUBJECT, so every fixture
    # carries one. That is not fixture bookkeeping: the gate anchors there
    # structurally (narrowed 2026-08-29), and a fixture without the line would
    # exercise only the absent-subject refusal and say nothing about the rule.
    SELF='The current edition of the framework document is setlist.md (edition v9.9).'

    # Clean: only the current edition. Must PASS.
    printf '%s\nSetlist, the current one.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a README naming only the current edition is accepted"
    else
      bad "public README gate: a README naming only the current edition is accepted" "it refused a clean file"
    fi
    # Stale: names a prior edition too, BARE. Must REFUSE.
    printf '%s\nBut this line still says edition v9.8.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a README still naming a PRIOR edition is refused" \
          "it accepted a file naming v9.8 alongside v9.9, which is the defect this gate exists for"
    else
      ok "public README gate: a README still naming a PRIOR edition is refused"
    fi
    # THE SELF-DESCRIPTION ITSELF NAMING A STALE EDITION. This is the defect the
    # gate was written for and the one the narrowing must not have loosened.
    printf 'The current edition of the framework document is setlist.md (edition v9.8).\n' > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a SELF-DESCRIPTION naming a stale edition is refused" \
          "the narrowing let the gate's own founding defect through, which would be a hole and not a scoping decision"
    else
      ok "public README gate: a SELF-DESCRIPTION naming a stale edition is refused"
    fi
    # ABSENT SUBJECT IS A REFUSAL, NOT A PASS. A check that cannot find the line
    # it judges has not judged it, which is this project's own rule about its
    # own checks and the reason the narrowing is safe to make at all.
    printf 'Setlist, edition v9.9, with no self-description anywhere.\n' > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a README with NO self-description line is refused" \
          "the gate passed a file whose subject it could not find, which is the empty-result-as-verdict class"
    else
      ok "public README gate: a README with NO self-description line is refused"
    fi
    # A PROVENANCE CITATION IS NOT A CLAIM ABOUT THE CURRENT EDITION. This is
    # what the narrowing bought, asserted rather than assumed, and it is the
    # ratified boundary sentence's exact shape.
    printf '%s\nwhere this project has said the real boundary lives since v1.7.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a 'since vX.Y' provenance citation is accepted, which is what the narrowing bought"
    else
      bad "public README gate: a 'since vX.Y' provenance citation is accepted, which is what the narrowing bought" \
          "the gate still cannot tell a citation of when a claim was made from a claim about what users are getting"
    fi
    # A three-component plugin version must not be read as an edition.
    printf '%s\nplugin v9.8.1 is irrelevant here.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a three-component plugin version is not mistaken for an edition"
    else
      bad "public README gate: a three-component plugin version is not mistaken for an edition" \
          "it refused on v9.8.1, so the gate would block ordinary publishes"
    fi
  fi
fi
