#!/usr/bin/env bash
# test/suite/16-team-edition-0132.sh: shard 16 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE FORGE CHECK (KL5), spec 0132 cluster A, from the ratified design
# `design-forge-check-kl5-2026-09-06.md` (sections 2 through 6, 8 and 9).
#
# WHAT THESE ASSERTIONS ARE EVIDENCE OF: that the check MAKES the merge a pull
# request would land and asks the hooks' own questions of it from the
# checkout's stamped copies, printing ONE token; that every row of the design's
# failure table refuses (or reports) with its named code; and that the local
# hook under custody C defers the approval question BY NAME to this check and
# refuses when the check is not in the tree. Nothing here establishes that a
# PERSON approved anything: under custody C the forge's review is the custody,
# and the verifier's own sentence says so on every pass.
#
# THE FORGE IS A STUB, deliberately. The check's --forge-query seam replaces the
# curl it would run with a command handed the API path; each case below answers
# with the exact shape the forge answers with (measured 2026-09-06 on the
# owner's repositories: an empty rules list, "Branch not protected" at 404, and
# the plan-limit 403 the design's row 2 did not anticipate). A suite that
# reached a real forge would be a suite that fails on Sunday.
#
# Every refusal is asserted on its CODE and on the stdout TOKEN, not on the
# exit status alone: these fixtures could be refused for a dozen unrelated
# reasons and "did it refuse" would pass with or without the mechanism. Each
# row was watched RED before the arm existed (the check absent: exit 127 and
# no token; then the check present without the arm: the wrong code), recorded
# in spec 0132's Progress.
# =============================================================================
# The fixtures and the runner are defined OUTSIDE the region so the CODEOWNERS
# region below (a separate shard region) can use them on any shard; a helper
# defined inside a region is undefined on every shard that does not own it,
# which command_not_found_handle turns into an aborted suite rather than a
# silent pass.
FC_SCRIPT="$ROOT/scripts/forge-check.sh"

fc_fixture() { # fc_fixture <dir> <custody|off> : an instance at main, spec 0001 ACTIVE, the stamped copies in the tree
  local d="$1" custody="${2:-off}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email "tests@example.invalid"; git -C "$d" config user.name "Setlist Tests"; git -C "$d" config commit.gpgsign false
  if [[ "$custody" == "off" ]]; then
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  else
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"attestation":{"required":true,"custody":"%s","verify_with":".claude/approvers.pub"}}\n' "$custody" > "$d/.claude/sdd.json"
  fi
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/pre-push" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  cp "$ROOT/scripts/trunk-audit.sh" "$FC_SCRIPT" "$d/.claude/hooks/"
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n\n## Goal\nBuild the thing.\n\n## Closing report\n- pending\n' > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
}
fc_closed_spec() { printf '# Spec %s - %s\n\nStatus: CLOSED\n\n## Goal\nBuild it.\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' "$1" "$2"; }
fc_close_branch() { # fc_close_branch <dir> : spec/0001-thing carrying feature work and a compliant close of 0001
  local d="$1"
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'work\n' > "$d/src/FEATURE.txt"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm work >/dev/null 2>&1
  fc_closed_spec 0001 thing > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | shipped |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
fc_doc() { # fc_doc <slug> <num> <spec-file> -> a forge-custody attestation document over the file's bytes
  printf '{"setlist_attestation":1,"spec":"specs/%s.md","spec_number":"%s","spec_hash":"%s","verdict":"APPROVED","approver":"planner@example.test","custody":"forge","tool":"setlist/checkpoint","tool_version":"2.6.0","at":"2026-09-06T00:00:00Z","notes":""}\n' \
    "$1" "$2" "$(bash "$ROOT/scripts/spec-hash.sh" "$3")"
}
# fc_forge_fixture <dir> <trunk|branch>: custody C; spec 0001 ACTIVE with its
# document on main (the flip the trunk accepted); spec 0002 closed compliantly
# on spec/0002-other and RE-ATTESTED there over its final bytes, which is what
# checkpoint writes at a close. With "branch" the 0002 document is introduced
# ON THE BRANCH, the flip the trunk never saw.
fc_forge_fixture() {
  local d="$1" where="${2:-trunk}"
  fc_fixture "$d" forge
  printf '# Spec 0002 - other\n\nStatus: ACTIVE\n\n## Goal\nOther.\n\n## Closing report\n- pending\n' > "$d/specs/0002-other.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n| 0002 | Other | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  mkdir -p "$d/specs/attest"
  fc_doc 0001-thing 0001 "$d/specs/0001-thing.md" > "$d/specs/attest/0001.json"
  [[ "$where" == "trunk" ]] && fc_doc 0002-other 0002 "$d/specs/0002-other.md" > "$d/specs/attest/0002.json"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "specs; the ACTIVE flips" >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0002-other
  printf 'work\n' > "$d/src/F.txt"
  fc_closed_spec 0002 other > "$d/specs/0002-other.md"
  fc_doc 0002-other 0002 "$d/specs/0002-other.md" > "$d/specs/attest/0002.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n| 0002 | Other | CLOSED | shipped |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0002, re-attested" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
# The forge stub: FC_STUB_MODE decides, the API path is $1, the status is the
# first line and the body follows, which is the seam's contract.
FC_STUB="$WORK/fc-forge-stub.sh"
cat > "$FC_STUB" <<'STUB'
#!/usr/bin/env bash
# TE4 (edition v1.15, spec 0136): a FULLY protected trunk now also requires
# branches to be up to date before merging, so every stub mode below that stands
# for "properly protected" carries strict_required_status_checks_policy. Without
# it these fixtures would stop meaning what their assertions say they mean: the
# PASS rows would be asserting that a trunk missing a requirement passes.
rules_ok='[{"type":"pull_request","parameters":{"required_approving_review_count":1}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]'
case "$FC_STUB_MODE" in
  down) exit 1 ;;
  forbidden) printf '403\n{"message":"Resource not accessible by integration"}\n' ;;
  ratelimit) printf '429\n{"message":"API rate limit exceeded"}\n' ;;
  plan403) case "$1" in repos/*/rules/*|repos/*/protection) printf '403\n{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  plan403classic) case "$1" in repos/*/rules/*) printf '200\n[]\n' ;; repos/*/protection) printf '403\n{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  unprotected) case "$1" in repos/*/rules/*) printf '200\n[]\n' ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  nocheck) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]\n' ;; repos/*/protection) printf '404\n{\"message\":\"Branch not protected\"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  noreview) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"setlist forge check"}]}}]\n' ;; repos/*/protection) printf '404\n{\"message\":\"Branch not protected\"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  ok) case "$1" in repos/*/rules/*) printf '200\n%s\n' "$rules_ok" ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  # AMENDMENTS 3 AND 4 (the owner's rulings of 2026-09-07, session 3): the
  # ruleset's allowed_merge_methods beside the repository's allow_rebase_merge,
  # and the two protection mechanisms composing as the forge composes them.
  rulesetnorebase) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1,"allowed_merge_methods":["merge","squash"]}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]\n' ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  rulesetrebase) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1,"allowed_merge_methods":["merge","squash","rebase"]}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]\n' ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  reporebaseoff) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1,"allowed_merge_methods":["merge","squash","rebase"]}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]\n' ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  split) case "$1" in repos/*/rules/*) printf '200\n[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]\n' ;; repos/*/protection) printf '200\n{"required_pull_request_reviews":{"required_approving_review_count":1}}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  splitrev) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]\n' ;; repos/*/protection) printf '200\n{"required_status_checks":{"strict":true,"contexts":["setlist forge check"]}}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  okclassic403) case "$1" in repos/*/rules/*) printf '200\n%s\n' "$rules_ok" ;; repos/*/protection) printf '403\n{"message":"Resource not accessible by integration"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  nocheckclassic403) case "$1" in repos/*/rules/*) printf '200\n[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]\n' ;; repos/*/protection) printf '403\n{"message":"Resource not accessible by integration"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  classic) case "$1" in repos/*/rules/*) printf '200\n[]\n' ;; repos/*/protection) printf '200\n{"required_pull_request_reviews":{"required_approving_review_count":2},"required_status_checks":{"strict":true,"contexts":["setlist forge check"]}}\n' ;; *) printf '200\n{"allow_rebase_merge":true}\n' ;; esac ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$FC_STUB"

FC_OUT=""; FC_ERR=""; FC_RC=0; FC_LAST=""
fc_run() { # fc_run <dir> <args...> -> FC_OUT (stdout), FC_ERR, FC_RC, FC_LAST (the last stdout line)
  local d="$1"; shift
  FC_OUT="$(bash "$d/.claude/hooks/forge-check.sh" --instance "$d" "$@" 2>"$WORK/fc-err")"; FC_RC=$?
  FC_ERR="$(cat "$WORK/fc-err" 2>/dev/null)"
  FC_LAST="$(printf '%s\n' "$FC_OUT" | tail -n1)"
}
fc_case() { # fc_case <name> <want-rc> <want-last-line-prefix> [want-stderr-code...]
  local name="$1" rc="$2" last="$3"; shift 3
  local okc=1 c
  [[ "$FC_RC" == "$rc" ]] || okc=0
  case "$FC_LAST" in "$last"*) ;; *) okc=0 ;; esac
  for c in "$@"; do printf '%s' "$FC_ERR" | grep -qF -- "[$c]" || okc=0; done
  if [[ "$okc" -eq 1 ]]; then
    ok "forge check $name"
  else
    bad "forge check $name" "rc=$FC_RC last=[$FC_LAST] wanted rc=$rc last=[$last...] codes=[$*]; stderr: $(printf '%s' "$FC_ERR" | grep -o '\[[A-Z-]*\]' | sort -u | tr '\n' ' ') $(printf '%s' "$FC_ERR" | tail -2 | tr '\n' ' ' | cut -c1-200)"
  fi
}

# >>> SHARD-BEGIN forge-check-0132 cost=25
if shard_region forge-check-0132; then

# --- THE CONTROL FIRST: a compliant close PASSES with ONE token --------------
FCD="$WORK/fc-control"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "control: a compliant close of the trunk PASSES naming the custody" 0 "PASS (custody: none declared)"
if [[ "$(printf '%s\n' "$FC_OUT" | grep -c .)" -eq 1 ]]; then
  ok "forge check control: stdout is exactly one line, the token"
else
  bad "forge check control: stdout is exactly one line, the token" "stdout had $(printf '%s\n' "$FC_OUT" | grep -c .) lines: $(printf '%s' "$FC_OUT" | tr '\n' '|')"
fi
if printf '%s' "$FC_ERR" | grep -q 'audited 1 commits on main: 1 clean'; then
  ok "forge check control: the trunk audit ran over the scratch merge (step 8) and read exactly the merge commit"
else
  bad "forge check control: the trunk audit ran over the scratch merge (step 8) and read exactly the merge commit" "$(printf '%s' "$FC_ERR" | grep audited | head -1)"
fi
# The scratch clone is gone afterwards; a check that leaves merges on disk is a
# check that fills a runner.
if ls -d "${TMPDIR:-/tmp}"/setlist-forge-check.* >/dev/null 2>&1; then
  bad "forge check control: the scratch clone is removed after the verdict" "left behind: $(ls -d "${TMPDIR:-/tmp}"/setlist-forge-check.* | head -3 | tr '\n' ' ')"
else
  ok "forge check control: the scratch clone is removed after the verdict"
fi

# --- THE PREDICATES THE HOOKS RUN, each refusing with its own code ------------
FCD="$WORK/fc-noclose"; fc_fixture "$FCD" off
git -C "$FCD" checkout -q -b spec/0001-thing; printf 'w\n' > "$FCD/src/F.txt"; git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm work >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 4: feature code closing no spec is CLOSE-REFUSED (pre-merge-commit's predicate)" 1 "CLOSE-REFUSED" SLH-CLOSES-NO-SPEC

FCD="$WORK/fc-scan"; fc_fixture "$FCD" off
git -C "$FCD" checkout -q -b spec/0001-thing
printf 'a %s dash\n' "$EMDASH" > "$FCD/notes.md"; git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "dash" >/dev/null 2>&1
git -C "$FCD" rm -q notes.md; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "gone again" >/dev/null 2>&1
printf 'work\n' > "$FCD/src/FEATURE.txt"; fc_closed_spec 0001 thing > "$FCD/specs/0001-thing.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | shipped |\n' > "$FCD/specs/STATUS.md"
git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "close" >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 6: content added and removed INSIDE the range is SCAN-REFUSED (the merge diff never shows it)" 1 "SCAN-REFUSED" SLH-EMDASH

FCD="$WORK/fc-gate"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
git -C "$FCD" checkout -q spec/0001-thing; jq '.gate_command = "false"' "$FCD/.claude/sdd.json" > "$FCD/.x" && mv "$FCD/.x" "$FCD/.claude/sdd.json"
git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "red gate" >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 7 (row 14a): a failing gate command in the merged tree is GATE-RED" 1 "GATE-RED" SLH-GATE-COMMAND-FAILED
FCD="$WORK/fc-nogate"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
git -C "$FCD" checkout -q spec/0001-thing; jq '.gate_command = ""' "$FCD/.claude/sdd.json" > "$FCD/.x" && mv "$FCD/.x" "$FCD/.claude/sdd.json"
git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "no gate" >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 7 (row 14b): an absent gate command under a scaffolded instance is GATE-RED, never a skip" 1 "GATE-RED" SLH-NO-GATE-COMMAND

# Step 8's plumbing, pinned with a stand-in audit named as such: the check acts
# on the audit's exit status (1 refuses AUDIT-VIOLATION, 2 is "could not run").
FCD="$WORK/fc-audit1"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
printf '#!/usr/bin/env bash\nprintf "VIOLATION stand-in\\n"; exit 1\n' > "$FCD/.claude/hooks/trunk-audit.sh"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 8: an audit verdict of 1 is AUDIT-VIOLATION" 1 "AUDIT-VIOLATION"
printf '#!/usr/bin/env bash\nprintf "could not run stand-in\\n" >&2; exit 2\n' > "$FCD/.claude/hooks/trunk-audit.sh"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "step 8: an audit that could not run (exit 2) is exit 2 with NOTHING on stdout, never clean" 2 ""

# --- THE CHECKOUT AND THE INSTANCE (rows 10 through 13) -----------------------
FCD="$WORK/fc-shallow-src"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
FCS="$WORK/fc-shallow"; rm -rf "$FCS"
git clone -q --depth 1 --no-single-branch "file://$FCD" "$FCS" >/dev/null 2>&1
mkdir -p "$FCS/.claude/hooks"; cp "$FC_SCRIPT" "$FCS/.claude/hooks/forge-check.sh"
fc_run "$FCS" --base main --head origin/spec/0001-thing --forge none
fc_case "row 10: a shallow checkout is SHALLOW-CHECKOUT, naming fetch-depth" 1 "SHALLOW-CHECKOUT" FC-SHALLOW-CHECKOUT

FCD="$WORK/fc-conflict"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
printf 'main moved\n' > "$FCD/seed.txt"; git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "main moves" >/dev/null 2>&1
git -C "$FCD" checkout -q spec/0001-thing; printf 'branch moved\n' > "$FCD/seed.txt"; git -C "$FCD" add -A >/dev/null; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "branch moves" >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "row 11: a head that does not merge cleanly is NOT-MERGEABLE" 1 "NOT-MERGEABLE" FC-NOT-MERGEABLE

FCD="$WORK/fc-nottrunk"; fc_fixture "$FCD" off; fc_close_branch "$FCD"; git -C "$FCD" branch -q release/1 main
fc_run "$FCD" --base release/1 --head spec/0001-thing --forge none
fc_case "row 12: a base that is not the recorded trunk PASSES with the statement of no subject" 0 "PASS (not a trunk pull request; nothing to verify)"
if printf '%s' "$FC_ERR" | grep -q 'not a trunk pull request (base release/1, recorded trunk main)'; then
  ok "forge check row 12: the no-subject line names the base and the trunk on stderr"
else
  bad "forge check row 12: the no-subject line names the base and the trunk on stderr" "$(printf '%s' "$FC_ERR" | tail -1)"
fi

FCD="$WORK/fc-nosdd"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
git -C "$FCD" checkout -q spec/0001-thing; git -C "$FCD" rm -q .claude/sdd.json; git -C "$FCD" -c core.hooksPath=/dev/null commit -qm "remove the config" >/dev/null 2>&1; git -C "$FCD" checkout -q main
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "row 13: a head that removes .claude/sdd.json is NOT-AN-INSTANCE, not waved through (PD3 at the one layer that reads rather than checks out)" 1 "NOT-AN-INSTANCE" FC-NOT-AN-INSTANCE

# --- F1 of the 2.6.0 leg (fix round 1, 2026-09-08): the trunk comparison TRUSTED A
# VALUE THE HOOKS ENFORCE. The check reduced the recorded trunk textually and read a
# mismatch with the base as "not a trunk pull request", its one pass-on-nothing
# branch, so a trunk spelled origin/main (which the git hooks accept and enforce),
# a case or whitespace variant, and a head that rewrites the trunk in its own
# commit all passed every pull request having evaluated nothing. Every spelling
# below was watched RED on the leg's candidate 2217acea before the fix. The fix
# (design amendment 6): the trunk is read from the BASE's config, both names are
# resolved through git and compared as refs, an unresolvable or case-variant trunk
# refuses under the library's own SLH-TRUNK-NOT-A-BRANCH, and a head whose recorded
# trunk differs from the base's is refused under a widened FC-NOT-AN-INSTANCE. The
# controls: the compliant close still PASSES under origin/main, and row 12's
# genuinely different base still passes with its statement of no subject.
fc_unclosed_branch() { # fc_unclosed_branch <dir> : spec/0001-thing carrying feature work and NO close
  local d="$1"
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'work\n' > "$d/src/FEATURE.txt"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm work >/dev/null 2>&1
  git -C "$d" checkout -q main
}
fc_record_trunk() { # fc_record_trunk <dir> <value> : rewrite the recorded trunk on the current branch, one commit
  local d="$1" v="$2"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$v" > "$d/.claude/sdd.json"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "record trunk" >/dev/null 2>&1
}
FCD="$WORK/fc-trunk-origin"; fc_fixture "$FCD" off; fc_record_trunk "$FCD" origin/main; fc_unclosed_branch "$FCD"
git -C "$FCD" update-ref refs/remotes/origin/main "$(git -C "$FCD" rev-parse main)"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "F1 a: a trunk recorded as origin/main (the hooks accept it) judges the merge: an unclosed head is CLOSE-REFUSED, not waved through" 1 "CLOSE-REFUSED" SLH-CLOSES-NO-SPEC
FCD="$WORK/fc-trunk-origin-ok"; fc_fixture "$FCD" off; fc_record_trunk "$FCD" origin/main; fc_close_branch "$FCD"
git -C "$FCD" update-ref refs/remotes/origin/main "$(git -C "$FCD" rev-parse main)"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "F1 a control: the compliant close under origin/main still PASSES (the honest case is not refused by the fix)" 0 "PASS (custody: none declared)"
FCD="$WORK/fc-trunk-case"; fc_fixture "$FCD" off; fc_record_trunk "$FCD" Main; fc_unclosed_branch "$FCD"
git -C "$FCD" update-ref refs/remotes/origin/main "$(git -C "$FCD" rev-parse main)"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "F1 b: a trunk recorded as Main (a case variant) is refused as not a branch, never a pass on nothing" 1 "NOT-AN-INSTANCE" SLH-TRUNK-NOT-A-BRANCH
FCD="$WORK/fc-trunk-space"; fc_fixture "$FCD" off; fc_record_trunk "$FCD" "main "; fc_unclosed_branch "$FCD"
git -C "$FCD" update-ref refs/remotes/origin/main "$(git -C "$FCD" rev-parse main)"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "F1 c: a trunk recorded with a trailing space is refused as not a branch, never a pass on nothing" 1 "NOT-AN-INSTANCE" SLH-TRUNK-NOT-A-BRANCH
FCD="$WORK/fc-trunk-redirect"; fc_fixture "$FCD" off; fc_unclosed_branch "$FCD"
git -C "$FCD" checkout -q spec/0001-thing; fc_record_trunk "$FCD" trunk; git -C "$FCD" checkout -q main
git -C "$FCD" update-ref refs/remotes/origin/main "$(git -C "$FCD" rev-parse main)"
fc_run "$FCD" --base main --head spec/0001-thing --forge none
fc_case "F1 d: a head that REDIRECTS the recorded trunk in its own commit is NOT-AN-INSTANCE (the base's config governs), not waved through" 1 "NOT-AN-INSTANCE" FC-NOT-AN-INSTANCE
if printf '%s' "$FC_ERR" | grep -q 'records trunk "trunk" where the base records "main"'; then
  ok "forge check F1 d: the refusal names both recorded values"
else
  bad "forge check F1 d: the refusal names both recorded values" "$(printf '%s' "$FC_ERR" | grep 'NOT-AN-INSTANCE' | cut -c1-200)"
fi

# --- F15 of the 2.6.0 leg: a runner without jq is "could not run", naming jq -----
FCD="$WORK/fc-nojq"; fc_fixture "$FCD" off; fc_close_branch "$FCD"; build_nojq_bin
FC_OUT="$(PATH="$NOJQ_BIN" bash "$FCD/.claude/hooks/forge-check.sh" --instance "$FCD" --base main --head spec/0001-thing --forge none 2>"$WORK/fc-err")"; FC_RC=$?
FC_ERR="$(cat "$WORK/fc-err")"; FC_LAST="$(printf '%s\n' "$FC_OUT" | tail -n1)"
if [[ "$FC_RC" -eq 2 && -z "$FC_LAST" ]] && printf '%s' "$FC_ERR" | grep -q 'jq is not installed' && ! printf '%s' "$FC_ERR" | grep -q 'SLH-UNREADABLE-CONFIG'; then
  ok "forge check F15: with jq absent the check could not run (exit 2, no token) and names jq, not the instance's config"
else
  bad "forge check F15: with jq absent the check could not run (exit 2, no token) and names jq, not the instance's config" "rc=$FC_RC last=[$FC_LAST] $(printf '%s' "$FC_ERR" | tail -2 | tr '\n' ' ' | cut -c1-220)"
fi

# --- ROW 17: a broken toolchain is exit 2 and NOTHING on stdout ----------------
FCD="$WORK/fc-brokenjq"; fc_fixture "$FCD" off; fc_close_branch "$FCD"
FC_BIN="$WORK/fc-brokenjq-bin"; mkdir -p "$FC_BIN"; printf '#!/bin/sh\nexit 0\n' > "$FC_BIN/jq"; chmod +x "$FC_BIN/jq"
FC_OUT="$(PATH="$FC_BIN:$PATH" bash "$FCD/.claude/hooks/forge-check.sh" --instance "$FCD" --base main --head spec/0001-thing --forge none 2>"$WORK/fc-err")"; FC_RC=$?
FC_ERR="$(cat "$WORK/fc-err")"; FC_LAST="$(printf '%s\n' "$FC_OUT" | tail -n1)"
fc_case "row 17: a jq that exits 0 printing nothing is exit 2, no token, SLH-JQ-BROKEN named" 2 "" SLH-JQ-BROKEN

# --- CUSTODY C AT THE CHECK (rows 1 through 9), the forge a stub ---------------
FCF="$WORK/fc-forge"; fc_forge_fixture "$FCF" trunk
fc_run "$FCF" --base main --head spec/0002-other --forge none
fc_case "row 9: custody C with no forge to ask refuses FC-NO-FORGE (a forge the check cannot query cannot be the notary)" 1 "FORGE-UNREACHABLE" FC-NO-FORGE
FC_STUB_MODE=down fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 1: a forge that does not answer refuses FC-FORGE-UNREACHABLE" 1 "FORGE-UNREACHABLE" FC-FORGE-UNREACHABLE
FC_STUB_MODE=forbidden fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 2: a token that may not read the rules refuses FC-FORGE-FORBIDDEN" 1 "FORGE-UNREACHABLE" FC-FORGE-FORBIDDEN
# ROW 2's THIRD CAUSE HAS ITS OWN CODE (ratification amendment 1, ruling 1 of
# 2026-09-07): the plan-limit 403 measured on the owner's private repository
# routes to FC-FORGE-PLAN-LIMITED with a remedy that exists (the plan, or a
# public repository), and a permission 403 stays FC-FORGE-FORBIDDEN with the
# design's two readings. Pinned beside each other, both directions, so the two
# cannot collapse: each case asserts its own code present AND the other absent.
# Watched red first on 5825267 (the plan body landed in FORBIDDEN there).
FC_FORBIDDEN_ERR="$FC_ERR"
FC_STUB_MODE=plan403 fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 2b (amendment 1): the plan-limit 403 refuses FC-FORGE-PLAN-LIMITED under custody C" 1 "FORGE-UNREACHABLE" FC-FORGE-PLAN-LIMITED
if ! printf '%s' "$FC_ERR" | grep -qF '[FC-FORGE-FORBIDDEN]' && ! printf '%s' "$FC_FORBIDDEN_ERR" | grep -qF '[FC-FORGE-PLAN-LIMITED]'; then
  ok "forge check row 2b: PLAN-LIMITED and FORBIDDEN are two codes and neither case emits the other's"
else
  bad "forge check row 2b: PLAN-LIMITED and FORBIDDEN are two codes and neither case emits the other's" "plan403 stderr codes: $(printf '%s' "$FC_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' '); forbidden stderr codes: $(printf '%s' "$FC_FORBIDDEN_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' ')"
fi
if printf '%s' "$FC_ERR" | grep -F '[FC-FORGE-PLAN-LIMITED]' | grep -q 'plan that offers branch protection, or make the repository public'; then
  ok "forge check row 2b: the plan-limited sentence names its remedy (the plan, or a public repository)"
else
  bad "forge check row 2b: the plan-limited sentence names its remedy (the plan, or a public repository)" "$(printf '%s' "$FC_ERR" | grep PLAN-LIMITED | cut -c1-200)"
fi
if printf '%s' "$FC_FORBIDDEN_ERR" | grep -F '[FC-FORGE-FORBIDDEN]' | grep -q 'contents: read' && ! printf '%s' "$FC_FORBIDDEN_ERR" | grep -F '[FC-FORGE-FORBIDDEN]' | grep -q 'on its plan'; then
  ok "forge check row 2: the forbidden sentence keeps the design's two readings and no longer carries the plan one"
else
  bad "forge check row 2: the forbidden sentence keeps the design's two readings and no longer carries the plan one" "$(printf '%s' "$FC_FORBIDDEN_ERR" | grep FORBIDDEN | cut -c1-200)"
fi
# The permission 403 at the CLASSIC endpoint (rulesets empty, then a plan 403
# at the protection query) routes the same way: the split reads the body, not
# the endpoint.
FC_STUB_MODE=plan403classic fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 2b: a plan-limit 403 at the classic endpoint after an empty rules list is PLAN-LIMITED too" 1 "FORGE-UNREACHABLE" FC-FORGE-PLAN-LIMITED
FC_STUB_MODE=ratelimit fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 3: a rate-limited forge refuses FC-FORGE-RATE-LIMITED and is not retried" 1 "FORGE-UNREACHABLE" FC-FORGE-RATE-LIMITED
if [[ "$(printf '%s' "$FC_ERR" | grep -c 'RATE-LIMITED')" -eq 1 ]]; then
  ok "forge check row 3: one refusal, one query, no retry loop"
else
  bad "forge check row 3: one refusal, one query, no retry loop" "$(printf '%s' "$FC_ERR" | grep -c RATE-LIMITED) rate-limit lines"
fi
FC_STUB_MODE=unprotected fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 4: an empty rules list and 'Branch not protected' is FC-FORGE-UNPROTECTED under custody C" 1 "FORGE-UNPROTECTED" FC-FORGE-UNPROTECTED
FC_STUB_MODE=nocheck fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 5: a protected trunk that does not require this check is FC-CHECK-NOT-REQUIRED" 1 "CHECK-NOT-REQUIRED" FC-CHECK-NOT-REQUIRED
FC_STUB_MODE=noreview fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 6: a protected trunk requiring no approving review is FC-NO-REVIEW-REQUIRED" 1 "FORGE-UNPROTECTED" FC-NO-REVIEW-REQUIRED
FC_STUB_MODE=ok fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "custody C pass: rules requiring a review and this check PASS naming the custody" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
# THE SENTENCE, VERBATIM (design section 5, ratification decision 4), for the
# spec the walk verifies at the tip (0001, ACTIVE) and for the spec the close
# re-attests (0002). It names what was established and what was not.
FC_SENTENCE='setlist forge check [FC-CUSTODY-VERIFIED] spec 0001 is covered by an approval under "forge" custody: the trunk main is protected on this forge (a pull request with at least one approving review and the required check "setlist forge check" are required to land on it), the ACTIVE flip that wrote specs/attest/0001.json is an ancestor of that trunk, and the attestation'"'"'s hash covers the spec'"'"'s bytes in this merge. This establishes that the approval reached the trunk through the forge'"'"'s review, not that any particular person decided; the forge'"'"'s account security is the custody.'
if printf '%s\n' "$FC_ERR" | grep -qxF -- "$FC_SENTENCE"; then
  ok "forge check custody C pass: the verification sentence is the design's, byte for byte, for the ACTIVE spec at the tip"
else
  bad "forge check custody C pass: the verification sentence is the design's, byte for byte, for the ACTIVE spec at the tip" "$(printf '%s' "$FC_ERR" | grep 'CUSTODY-VERIFIED\] spec 0001' | cut -c1-240)"
fi
if printf '%s' "$FC_ERR" | grep -q 'CUSTODY-VERIFIED\] spec 0002 is covered'; then
  ok "forge check custody C pass: the closing spec's re-attestation is verified at the forge too (step 4's arm)"
else
  bad "forge check custody C pass: the closing spec's re-attestation is verified at the forge too (step 4's arm)" "$(printf '%s' "$FC_ERR" | grep -c CUSTODY-VERIFIED) verified lines"
fi
FC_STUB_MODE=classic fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "custody C pass via classic protection: an empty rules list falls back to branch protection and PASSES" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
if printf '%s' "$FC_ERR" | grep -q 'report \[FC-REBASE-MERGE-ENABLED\]' && [[ "$FC_RC" -eq 0 ]]; then
  ok "forge check rebase (decision 3): a repository allowing rebase merges gets a REPORT line and is not refused"
else
  bad "forge check rebase (decision 3): a repository allowing rebase merges gets a REPORT line and is not refused" "rc=$FC_RC: $(printf '%s' "$FC_ERR" | grep REBASE | cut -c1-160)"
fi

FCF2="$WORK/fc-forge-branchflip"; fc_forge_fixture "$FCF2" branch
FC_STUB_MODE=ok fc_run "$FCF2" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 8: a document introduced on the pull request's own branch is FC-FLIP-NOT-ON-TRUNK, whatever the forge says" 1 "ATTEST-REFUSED" FC-FLIP-NOT-ON-TRUNK

# --- THE REPORT CELLS (rows 4 through 6 under a custody that is not C) ---------
# Asserted as a REPORT LINE plus a PASS on the other predicates, never as a
# pass on absence: under signer or none the trunk's protection is not part of
# any claim the instance makes.
FCR="$WORK/fc-report"; fc_fixture "$FCR" off; fc_close_branch "$FCR"
FC_STUB_MODE=unprotected fc_run "$FCR" --base main --head spec/0001-thing --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "REPORT cell row 4: an unprotected trunk under no custody PASSES and reports FC-FORGE-UNPROTECTED" 0 "PASS (custody: none declared)" FC-FORGE-UNPROTECTED
if printf '%s' "$FC_ERR" | grep -q 'report \[FC-FORGE-UNPROTECTED\]' && ! printf '%s' "$FC_ERR" | grep -q '^setlist forge check \[FC-FORGE-UNPROTECTED\]'; then
  ok "forge check REPORT cell row 4: the line is a report, not a refusal"
else
  bad "forge check REPORT cell row 4: the line is a report, not a refusal" "$(printf '%s' "$FC_ERR" | grep UNPROTECTED | cut -c1-120)"
fi
FC_STUB_MODE=nocheck fc_run "$FCR" --base main --head spec/0001-thing --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "REPORT cell row 5: this check not required, under no custody, PASSES and reports FC-CHECK-NOT-REQUIRED" 0 "PASS (custody: none declared)" FC-CHECK-NOT-REQUIRED
FC_STUB_MODE=noreview fc_run "$FCR" --base main --head spec/0001-thing --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "REPORT cell row 6: no review required, under no custody, PASSES and reports FC-NO-REVIEW-REQUIRED" 0 "PASS (custody: none declared)" FC-NO-REVIEW-REQUIRED
FC_STUB_MODE=down fc_run "$FCR" --base main --head spec/0001-thing --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "row 1 under no custody: a forge that does not answer is NOT asked to decide; the verdict rests on the predicates" 0 "PASS (custody: none declared)"
if printf '%s' "$FC_ERR" | grep -q 'the forge did not answer the protection query'; then
  ok "forge check row 1 under no custody: the unanswered query is reported, not silent"
else
  bad "forge check row 1 under no custody: the unanswered query is reported, not silent" "$(printf '%s' "$FC_ERR" | tail -1 | cut -c1-160)"
fi

# --- NO ESCAPE, AND THE RESOLUTION PIN -----------------------------------------
if ! grep -qE 'SETLIST_SKIP_(HOOKS|TRUNK_AUDIT)[:-]' "$FC_SCRIPT" && ! grep -E "^[^#]*(printf|fc_say|fc_report)" "$FC_SCRIPT" | grep -q 'SETLIST_SKIP'; then
  ok "forge check has no escape: neither variable is read, and no stderr line names one"
else
  bad "forge check has no escape: neither variable is read, and no stderr line names one" "$(grep -n 'SETLIST_SKIP' "$FC_SCRIPT" | grep -v '^[0-9]*:#' | head -3 | tr '\n' ' ')"
fi
# The check resolves the audit through the SAME two candidates pre-push tries,
# in the same order (design section 2, measured against pre-push's loop). Pinned
# by text: both files name the two paths in that order.
FC_RES="$(grep -A3 '^for cand in' "$FC_SCRIPT" | head -4 | grep -o 'CLAUDE_PLUGIN_ROOT:-}/scripts/trunk-audit.sh\|\$REPO/.claude/hooks/trunk-audit.sh' | tr '\n' ' ')"
PP_RES="$(grep -A3 '^for cand in' "$ROOT/templates/git-hooks/pre-push" | head -4 | grep -o 'CLAUDE_PLUGIN_ROOT:-}/scripts/trunk-audit.sh\|\$REPO/.claude/hooks/trunk-audit.sh' | tr '\n' ' ')"
if [[ -n "$FC_RES" && "$FC_RES" == "$PP_RES" ]]; then
  ok "forge check resolves the audit through pre-push's two candidates in pre-push's order ($FC_RES)"
else
  bad "forge check resolves the audit through pre-push's two candidates in pre-push's order" "check=[$FC_RES] pre-push=[$PP_RES]"
fi

# --- THE LOCAL HOOK UNDER CUSTODY C (ratification decision 2) ------------------
# With the stamped check in the tree the hook verifies the bytes, DEFERS the
# approval question to the check by name, says it is not an approval, and
# allows; without the check in the tree it refuses as it did while custody C
# was designed and not built. Both directions, so the deferral cannot widen
# into an offline pass by drift.
FCL="$WORK/fc-local"; fc_forge_fixture "$FCL" trunk
git -C "$FCL" checkout -q spec/0002-other; git -C "$FCL" config core.hooksPath .githooks
printf 'more\n' > "$FCL/src/G.txt"; git -C "$FCL" add -A >/dev/null
if git -C "$FCL" commit -qm "build under forge custody" >"$WORK/fc-local.out" 2>&1 && grep -q 'SLH-ATTEST-DEFERRED' "$WORK/fc-local.out"; then
  ok "local hook under custody C: with the check in the tree the commit is ALLOWED with SLH-ATTEST-DEFERRED"
else
  bad "local hook under custody C: with the check in the tree the commit is ALLOWED with SLH-ATTEST-DEFERRED" "$(tr '\n' ' ' < "$WORK/fc-local.out" | cut -c1-240)"
fi
FC_DEFER='setlist [SLH-ATTEST-DEFERRED] staged content: spec 0001'"'"'s approval is declared under "forge" custody; this layer verified the document'"'"'s bytes against the spec (no drift) and does NOT verify the approval, which the forge check verifies against the protected trunk when this work reaches a pull request. This is not an approval and is not treated as one here.'
if grep -qxF -- "$FC_DEFER" "$WORK/fc-local.out"; then
  ok "local hook under custody C: the deferral sentence is the design's, byte for byte"
else
  bad "local hook under custody C: the deferral sentence is the design's, byte for byte" "$(grep DEFERRED "$WORK/fc-local.out" | cut -c1-240)"
fi
git -C "$FCL" rm -q .claude/hooks/forge-check.sh; git -C "$FCL" -c core.hooksPath=/dev/null commit -qm "the check leaves the tree" >/dev/null 2>&1
printf 'more2\n' > "$FCL/src/H.txt"; git -C "$FCL" add -A >/dev/null
if ! git -C "$FCL" commit -qm "build without the check" >"$WORK/fc-local2.out" 2>&1 && grep -q 'SLH-ATTEST-UNVERIFIABLE' "$WORK/fc-local2.out" && grep -q 'no stamped forge check' "$WORK/fc-local2.out"; then
  ok "local hook under custody C: with NO check in the tree the commit is REFUSED, naming the missing layer"
else
  bad "local hook under custody C: with NO check in the tree the commit is REFUSED, naming the missing layer" "$(tr '\n' ' ' < "$WORK/fc-local2.out" | cut -c1-240)"
fi
if ! grep -q 'DESIGNED AND NOT BUILT' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ROOT/scripts/spec-attest.sh"; then
  ok "custody C built: the DESIGNED AND NOT BUILT strings are gone from the library and the attest helper"
else
  bad "custody C built: the DESIGNED AND NOT BUILT strings are gone from the library and the attest helper" "$(grep -n 'DESIGNED AND NOT BUILT' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ROOT/scripts/spec-attest.sh" | head -2)"
fi

# --- THE GATES READER (design section 8), absent block byte-identical -----------
FCG="$WORK/fc-gates"; mkdir -p "$FCG/.claude"
fc_gate_for() { ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_gate_command_for "$1" "$2"; printf '|%s' "$SLH_REFUSED" ) 2>/dev/null; }
printf '{"trunk":"main","scaffolded":true,"gate_command":"make check"}\n' > "$FCG/.claude/sdd.json"
if [[ "$(fc_gate_for "$FCG" close)" == "make check|0" && "$(fc_gate_for "$FCG" push)" == "make check|0" && "$(fc_gate_for "$FCG" commit)" == "|0" ]]; then
  ok "gates reader: with no gates block, close and push read gate_command and commit reads empty (byte-identical absence)"
else
  bad "gates reader: with no gates block, close and push read gate_command and commit reads empty (byte-identical absence)" "close=[$(fc_gate_for "$FCG" close)] push=[$(fc_gate_for "$FCG" push)] commit=[$(fc_gate_for "$FCG" commit)]"
fi
printf '{"trunk":"main","scaffolded":true,"gate_command":"make check","gates":{"commit":"make lint","close":"make check","push":"make everything"}}\n' > "$FCG/.claude/sdd.json"
if [[ "$(fc_gate_for "$FCG" commit)" == "make lint|0" && "$(fc_gate_for "$FCG" push)" == "make everything|0" ]]; then
  ok "gates reader: with the block present each tier reads its own string"
else
  bad "gates reader: with the block present each tier reads its own string" "commit=[$(fc_gate_for "$FCG" commit)] push=[$(fc_gate_for "$FCG" push)]"
fi
printf '{"trunk":"main","scaffolded":true,"gate_command":"make check","gates":"make check"}\n' > "$FCG/.claude/sdd.json"
FC_GS="$( ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_gate_command_for "$FCG" push >/dev/null ) 2>&1 )"
if printf '%s' "$FC_GS" | grep -q 'SLH-GATES-SHAPE'; then
  ok "gates reader: a gates value that is not an object of string tiers refuses SLH-GATES-SHAPE"
else
  bad "gates reader: a gates value that is not an object of string tiers refuses SLH-GATES-SHAPE" "$FC_GS"
fi
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","gates":{"commit":"","close":"true","push":""}}\n' > "$FCG/.claude/sdd.json"
FC_GC="$( ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_run_gate_command "$FCG" commit && printf 'commit-ok'; slh_run_gate_command "$FCG" push || printf ' push-refused' ) 2>&1 )"
if printf '%s' "$FC_GC" | grep -q 'commit-ok' && printf '%s' "$FC_GC" | grep -q 'SLH-NO-GATE-COMMAND'; then
  ok "gates reader: an empty commit tier is no gate (ordinary), an empty push tier under a scaffolded instance refuses SLH-NO-GATE-COMMAND"
else
  bad "gates reader: an empty commit tier is no gate (ordinary), an empty push tier under a scaffolded instance refuses SLH-NO-GATE-COMMAND" "$(printf '%s' "$FC_GC" | tr '\n' ' ' | cut -c1-200)"
fi

# --- DELIVERY: the check beside the audit, the workflow byte-verbatim ----------
FCS="$WORK/fc-stamp"; rm -rf "$FCS"; mkdir -p "$FCS"; git -C "$FCS" init -q >/dev/null 2>&1; git -C "$FCS" commit -q --allow-empty -m seed >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$FCS" >/dev/null 2>&1
if cmp -s "$FC_SCRIPT" "$FCS/.claude/hooks/forge-check.sh" && cmp -s "$ROOT/templates/root/.github/workflows/setlist-forge-check.yml" "$FCS/.github/workflows/setlist-forge-check.yml"; then
  ok "delivery: stamp.sh delivers the check beside the audit and the workflow byte-verbatim"
else
  bad "delivery: stamp.sh delivers the check beside the audit and the workflow byte-verbatim" "check=$([[ -f "$FCS/.claude/hooks/forge-check.sh" ]] && echo present || echo absent) workflow=$([[ -f "$FCS/.github/workflows/setlist-forge-check.yml" ]] && echo present || echo absent)"
fi
if grep -q 'root/.github/workflows/setlist-forge-check.yml' "$ROOT/templates/STAMP-TREE.md" && grep -q 'forge-check.sh' "$ROOT/templates/STAMP-TREE.md"; then
  ok "delivery: STAMP-TREE.md carries the workflow row and names the check"
else
  bad "delivery: STAMP-TREE.md carries the workflow row and names the check" "the mapping and the stamp disagree"
fi
FCR2="$WORK/fc-refresh"; instance_fixture "$FCR2" 2.5.0 current; git_init "$FCR2" >/dev/null 2>&1
run_script bash "$SCRIPTS/refresh-instance.sh" "$FCR2"
if printf '%s' "$SCRIPT_OUT" | grep -q 'forge-check.sh: missing, would be delivered' && printf '%s' "$SCRIPT_OUT" | grep -q 'setlist-forge-check.yml: missing, would be delivered'; then
  ok "delivery: refresh-instance.sh REPORTS the check and the workflow a 2.5.0 instance lacks"
else
  bad "delivery: refresh-instance.sh REPORTS the check and the workflow a 2.5.0 instance lacks" "$(printf '%s' "$SCRIPT_OUT" | grep -i forge | tr '\n' ' ' | cut -c1-200)"
fi
bash "$SCRIPTS/refresh-instance.sh" --apply "$FCR2" >/dev/null 2>&1
if cmp -s "$FC_SCRIPT" "$FCR2/.claude/hooks/forge-check.sh" && cmp -s "$ROOT/templates/root/.github/workflows/setlist-forge-check.yml" "$FCR2/.github/workflows/setlist-forge-check.yml"; then
  ok "delivery: refresh-instance.sh --apply delivers both to a 2.5.0 instance in one apply"
else
  bad "delivery: refresh-instance.sh --apply delivers both to a 2.5.0 instance in one apply" "check=$([[ -f "$FCR2/.claude/hooks/forge-check.sh" ]] && echo present || echo absent) workflow=$([[ -f "$FCR2/.github/workflows/setlist-forge-check.yml" ]] && echo present || echo absent)"
fi
printf '# a local edit: a runner label\n' >> "$FCR2/.github/workflows/setlist-forge-check.yml"
run_script bash "$SCRIPTS/refresh-instance.sh" "$FCR2"
bash "$SCRIPTS/refresh-instance.sh" --apply "$FCR2" >/dev/null 2>&1
if printf '%s' "$SCRIPT_OUT" | grep -q 'LEFT AS IS (wiring, not mechanism' && tail -n1 "$FCR2/.github/workflows/setlist-forge-check.yml" | grep -q 'a local edit'; then
  ok "delivery: an edited workflow is reported and LEFT AS IS by refresh (wiring, not mechanism)"
else
  bad "delivery: an edited workflow is reported and LEFT AS IS by refresh (wiring, not mechanism)" "$(printf '%s' "$SCRIPT_OUT" | grep -i 'setlist-forge' | cut -c1-160); tail=$(tail -n1 "$FCR2/.github/workflows/setlist-forge-check.yml")"
fi
# RULING 2 (2026-09-07): the divergence is reported BY FILE, in report mode
# and again on --apply, so neither a silent replace nor a silent leave is
# possible (PD10's precedent: what is left alone is named).
FCR2_APPLY_OUT="$(bash "$SCRIPTS/refresh-instance.sh" --apply "$FCR2" 2>&1)"
if printf '%s' "$SCRIPT_OUT" | grep -q '^  \.github/workflows/setlist-forge-check\.yml: differs from the template and is LEFT AS IS' \
   && printf '%s' "$FCR2_APPLY_OUT" | grep -q '^  \.github/workflows/setlist-forge-check\.yml: differs from the template and is LEFT AS IS'; then
  ok "delivery (ruling 2): the edited workflow's divergence is reported BY FILE in report mode and on --apply"
else
  bad "delivery (ruling 2): the edited workflow's divergence is reported BY FILE in report mode and on --apply" "report: $(printf '%s' "$SCRIPT_OUT" | grep 'setlist-forge-check.yml' | cut -c1-120); apply: $(printf '%s' "$FCR2_APPLY_OUT" | grep 'setlist-forge-check.yml' | cut -c1-120)"
fi

# --- AMENDMENTS 3 AND 4 (the owner's rulings of 2026-09-07, session 3) ----------
#
# Amendment 3 (spec 0132's "What the contract left open" 6): the rebase report
# fires only where a rebase merge is POSSIBLE on the trunk, which is the
# repository's allow_rebase_merge AND every ruleset pull_request rule that
# lists allowed_merge_methods for the trunk (the forge intersects them). A
# ruleset that forbids rebase silences the report; report, never refuse,
# unchanged. Pinned both ways. Watched red first on a21bfdc, where the
# forbidding ruleset still drew the report.
FC_STUB_MODE=rulesetnorebase fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 3: a ruleset forbidding rebase on the trunk PASSES under custody C though the repository allows rebase merges" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
if ! printf '%s' "$FC_ERR" | grep -q 'FC-REBASE-MERGE-ENABLED'; then
  ok "forge check amendment 3: a ruleset that forbids rebase SILENCES the rebase report (the repository flag alone is not the fact)"
else
  bad "forge check amendment 3: a ruleset that forbids rebase SILENCES the rebase report (the repository flag alone is not the fact)" "$(printf '%s' "$FC_ERR" | grep REBASE | cut -c1-160)"
fi
FC_STUB_MODE=rulesetrebase fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 3: a ruleset allowing rebase beside a repository allowing it draws the rebase REPORT and passes" 0 "PASS (custody: forge, verified at the forge)" FC-REBASE-MERGE-ENABLED
if printf '%s' "$FC_ERR" | grep -q 'report \[FC-REBASE-MERGE-ENABLED\]' && ! printf '%s' "$FC_ERR" | grep -q '^setlist forge check \[FC-REBASE-MERGE-ENABLED\]'; then
  ok "forge check amendment 3: the rebase line is still a report, never a refusal (decision 3 unchanged)"
else
  bad "forge check amendment 3: the rebase line is still a report, never a refusal (decision 3 unchanged)" "$(printf '%s' "$FC_ERR" | grep REBASE | cut -c1-160)"
fi
FC_STUB_MODE=reporebaseoff fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 3 control: a ruleset listing rebase cannot enable what the repository forbids: PASS, no report" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
if ! printf '%s' "$FC_ERR" | grep -q 'FC-REBASE-MERGE-ENABLED'; then
  ok "forge check amendment 3 control: repository rebase off, ruleset lists rebase: no report (the two are ANDed)"
else
  bad "forge check amendment 3 control: repository rebase off, ruleset lists rebase: no report (the two are ANDed)" "$(printf '%s' "$FC_ERR" | grep REBASE | cut -c1-160)"
fi
#
# Amendment 4 (entry 7): rulesets and classic protection are enforced as a
# UNION at the forge, so the check reads BOTH endpoints and takes the union:
# the trunk is protected when either carries a rule, the review requirement
# is the higher of the two, the check is required when either requires it;
# neither present is FC-FORGE-UNPROTECTED. Pinned for the three shapes
# (ruleset only, classic only, neither) and for the two SPLIT shapes that
# motivated the entry, which a21bfdc refused on the ruleset alone (red).
FC_STUB_MODE=ok fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 shape 1: a ruleset carrying both requirements and no classic protection (404 Branch not protected) PASSES" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
FC_STUB_MODE=classic fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 shape 2: classic protection carrying both requirements and no ruleset PASSES" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
FC_STUB_MODE=unprotected fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 shape 3: neither a ruleset nor classic protection is FC-FORGE-UNPROTECTED under custody C" 1 "FORGE-UNPROTECTED" FC-FORGE-UNPROTECTED
FC_STUB_MODE=split fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 split: the required check in a ruleset and the required review in classic protection COMPOSE to a PASS" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
FC_STUB_MODE=splitrev fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 split (the other way): the required review in a ruleset and the required check in classic protection COMPOSE to a PASS" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
# A classic answer the token may not read is UNVERIFIABLE only where the
# verdict DEPENDS on it: a ruleset that already requires both is not undone
# by a 403 at the classic endpoint (the classic layer can only ADD
# protection), and a ruleset that lacks one requirement with a 403 beside it
# cannot be read as lacking it (row 2's rule: a permission answer is never
# absence). Both directions pinned; the second was CHECK-NOT-REQUIRED on
# a21bfdc, a verdict on a fact the check had not read.
FC_STUB_MODE=okclassic403 fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4: a sufficient ruleset beside a classic endpoint the token may not read still PASSES (nothing depends on the classic answer)" 0 "PASS (custody: forge, verified at the forge)" FC-CUSTODY-VERIFIED
FC_STUB_MODE=nocheckclassic403 fc_run "$FCF" --base main --head spec/0002-other --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4: a ruleset lacking the check beside a classic endpoint the token may not read is FC-FORGE-FORBIDDEN, not CHECK-NOT-REQUIRED (a permission answer is never absence)" 1 "FORGE-UNREACHABLE" FC-FORGE-FORBIDDEN
if ! printf '%s' "$FC_ERR" | grep -q 'FC-CHECK-NOT-REQUIRED'; then
  ok "forge check amendment 4: the unreadable classic layer is not judged absent (no CHECK-NOT-REQUIRED beside the FORBIDDEN)"
else
  bad "forge check amendment 4: the unreadable classic layer is not judged absent (no CHECK-NOT-REQUIRED beside the FORBIDDEN)" "$(printf '%s' "$FC_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' ')"
fi
# The REPORT cells read the union too: under no custody the split shape draws
# neither report line, because both requirements are met between the two.
FC_STUB_MODE=split fc_run "$FCR" --base main --head spec/0001-thing --forge github --repo owner/repo --forge-query "$FC_STUB"
fc_case "amendment 4 REPORT cells: the split shape under no custody PASSES with no review or check report (the union meets both)" 0 "PASS (custody: none declared)"
if ! printf '%s' "$FC_ERR" | grep -q 'FC-NO-REVIEW-REQUIRED\|FC-CHECK-NOT-REQUIRED\|FC-FORGE-UNPROTECTED'; then
  ok "forge check amendment 4 REPORT cells: no false report on a requirement the other mechanism carries"
else
  bad "forge check amendment 4 REPORT cells: no false report on a requirement the other mechanism carries" "$(printf '%s' "$FC_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' ')"
fi
# The header says the read is a union and names the two endpoints, so the
# next reader of this file does not restore the fallback order.
if grep -q 'BOTH endpoints' "$FC_SCRIPT" && grep -q 'allowed_merge_methods' "$FC_SCRIPT"; then
  ok "forge check amendments 3 and 4: the script's own text names the union read and the ruleset's merge methods"
else
  bad "forge check amendments 3 and 4: the script's own text names the union read and the ruleset's merge methods" "one of the two phrases is absent from scripts/forge-check.sh"
fi

# --- THE ATTEST HELPER'S FORGE ARM: writes the document, signs nothing --------
FCH="$WORK/fc-helper"; fc_fixture "$FCH" forge
( cd "$FCH" && bash "$ROOT/scripts/spec-attest.sh" specs/0001-thing.md --approver planner@example.test ) >"$WORK/fc-helper.out" 2>&1
if [[ -f "$FCH/specs/attest/0001.json" && ! -f "$FCH/specs/attest/0001.sig" ]] && grep -q 'not an approval until' "$WORK/fc-helper.out" \
   && [[ "$(jq -r '.custody' "$FCH/specs/attest/0001.json" 2>/dev/null)" == "forge" ]]; then
  ok "attest helper under forge custody: writes the document, NO signature, and says it is a claim the forge verifies"
else
  bad "attest helper under forge custody: writes the document, NO signature, and says it is a claim the forge verifies" "$(tr '\n' ' ' < "$WORK/fc-helper.out" | cut -c1-200); sig=$([[ -f "$FCH/specs/attest/0001.sig" ]] && echo present || echo absent)"
fi

fi; shard_region_end
# <<< SHARD-END forge-check-0132

# =============================================================================
# THE COACHING LEAK (ER1), spec 0132 cluster B: the escape spellings leave the
# hooks' stderr, and the commit gate gains its ONE deny above the parsers.
#
# Two halves, both directions each. The stderr half: no refusal in
# templates/git-hooks/ may name an escape spelling as a remedy (the reader of a
# refusal in a session is the model, and the product's own output lowering the
# cost of the bypass it documents is the review's B1); the four skip
# ANNOUNCEMENTS and the header comments stay, because a silent bypass is the
# worse defect (PD11). The deny half: a command that SPELLS a bypass is denied
# with permissionDecision "deny" (ruling 1 of the 2.6.0 strategy), a substring
# test over the raw text with quoted spans removed, so a message that quotes the
# spelling ALLOWS (the false-denial surface, pinned in the allowing direction)
# and no frozen parser byte moves (PD1). Watched red on e3626ef first: every
# spelling below was allowed with no code.
# =============================================================================
# >>> SHARD-BEGIN bypass-deny-0132 cost=14
if shard_region bypass-deny-0132; then

# --- the stderr half: only the four announcements name a spelling ------------
BD_NONCOMMENT="$(grep -nE 'SETLIST_SKIP_(HOOKS|TRUNK_AUDIT)=1' "$ROOT/templates/git-hooks/"* | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
BD_REMEDIES="$(printf '%s\n' "$BD_NONCOMMENT" | grep -v 'skipped' | grep -v 'skipped by' | grep -vE 'if \[\[? "\$\{SETLIST_SKIP' | grep . || true)"
BD_ANNOUNCE="$(printf '%s\n' "$BD_NONCOMMENT" | grep -c 'skipped' || true)"
if [[ -z "$BD_REMEDIES" && "$BD_ANNOUNCE" -eq 4 ]]; then
  ok "coaching leak: no stderr line in templates/git-hooks/ names an escape spelling as a remedy; the four skip announcements stay"
else
  bad "coaching leak: no stderr line in templates/git-hooks/ names an escape spelling as a remedy; the four skip announcements stay" \
      "announcements=$BD_ANNOUNCE (want 4); remedy lines: $(printf '%s' "$BD_REMEDIES" | cut -c1-160 | tr '\n' '|')"
fi
# The hooks still HONOUR the escapes (the pins exercising them stand elsewhere in
# this file); the header comments still document them. This asserts the second.
BD_HDR=0
for h in pre-commit pre-merge-commit pre-push; do
  grep -E '^#.*SETLIST_SKIP_HOOKS' "$ROOT/templates/git-hooks/$h" >/dev/null && BD_HDR=$((BD_HDR + 1))
done
if [[ "$BD_HDR" -eq 3 ]]; then
  ok "coaching leak: the three hooks' header comments still document the whole-hook escape (documentation is where the human reads)"
else
  bad "coaching leak: the three hooks' header comments still document the whole-hook escape (documentation is where the human reads)" "$BD_HDR of 3 headers name it"
fi

# --- the deny half ------------------------------------------------------------
BDC="$WORK/bypass-deny"; git_init "$BDC"; sdd_json "$BDC"
printf 'clean content with nothing to find\n' > "$BDC/ok.md"; git -C "$BDC" add ok.md
bd_out() { printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$BDC" bash "$HOOKS/commit-gate.sh" 2>/dev/null; }
bd_deny() { # bd_deny <name> <command> <code>
  local out dec code
  out="$(bd_out "$2")"
  dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  code="$(printf '%s' "$out" | jq -r '.setlistAdvisory.code // empty' 2>/dev/null)"
  if [[ "$dec" == "deny" && "$code" == "$3" ]]; then
    ok "bypass deny $1: [$2] is DENIED (permissionDecision deny) as $3"
  else
    bad "bypass deny $1: [$2] is DENIED (permissionDecision deny) as $3" "decision=[${dec:-none}] code=[${code:-none}]"
  fi
}
bd_allow() { # bd_allow <name> <command>
  local out dec
  out="$(bd_out "$2")"
  dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "silent"' 2>/dev/null)"
  if [[ "$dec" != "deny" ]]; then
    ok "bypass allow $1: [$2] is NOT denied ($dec)"
  else
    bad "bypass allow $1: [$2] is NOT denied" "denied as $(printf '%s' "$out" | jq -r '.setlistAdvisory.code // empty' 2>/dev/null)"
  fi
}
bd_deny a 'SETLIST_SKIP_HOOKS=1 git commit -m x' CM-BYPASS-SPELLED
bd_deny b 'SETLIST_SKIP_TRUNK_AUDIT=1 git push origin main' CM-BYPASS-SPELLED
bd_deny c 'export SETLIST_SKIP_HOOKS=1' CM-BYPASS-SPELLED
bd_deny d 'git commit --no-verify -m x' CM-BYPASS-SPELLED
bd_deny e 'git push --no-verify origin main' CM-BYPASS-SPELLED
bd_deny f 'git -c core.hooksPath=/dev/null commit -m x' CM-HOOKSPATH-MOVED
bd_deny g 'git  -c   core.hooksPath=.nothing merge --no-ff spec/0001-thing' CM-HOOKSPATH-MOVED
bd_deny h 'cd repo && git commit -m "x" --no-verify' CM-BYPASS-SPELLED

# THE FOUR SPELLINGS THAT DEFEAT THE ONE HARD DENY (DE13, measured by the 2.7.0
# adversarial review, each with a replay). Pinned as ALLOWED on purpose, the way
# the pathspec hole is: this is a documented boundary, so the day one of them
# starts denying, the suite says so instead of the docs quietly going stale.
#
# The first is the one that matters and the reason the public bullet does not say
# "crafted spellings": `-m ${MSG}` is how a shell script writes a message, so a
# cooperating developer meets it while doing nothing unusual. The parser freeze of
# 2026-08-04 is why none of the four is repaired; the git hooks are unaffected by
# all of them, which is where the guarantee lives.
bd_allow de13a 'git commit -m ${MSG} --no-verify'
bd_allow de13b "git commit \$'--no-verify' -m x"
bd_allow de13c 'git --attr-source HEAD commit -n -m x'
bd_allow de13d 'EV=/tmp/nohooks git --config-env=core.hooksPath=EV commit -m x'

# F2 OF THE SECOND 2.7.0 LEG, fix round 2: the one hard veto stopped firing on
# data. All four of these were DENIED on the shipped 2.7.0 candidate, and two of
# them are read-only commands: the veto read every word of the segment for the
# assignment spelling, and read the operand of a value-taking option as a flag.
# Pinned in the ALLOWING direction, because a veto that fires on a grep is a false
# denial at the only place in the session layer that can actually stop you.
bd_allow f2a 'git commit -m "SETLIST_SKIP_HOOKS=1"'
bd_allow f2b 'grep -rn SETLIST_SKIP_HOOKS=1 .'
bd_allow f2c 'echo "SETLIST_SKIP_HOOKS=1"'
bd_allow f2d 'git log --grep "--no-verify"'
# And the escapes they are NOT allowed to have freed: assignment position, in all
# three spellings the shell gives it, plus the flag forms on both sides of -m.
bd_deny f2e 'SETLIST_SKIP_HOOKS=1 git commit -m x' CM-BYPASS-SPELLED
bd_deny f2f 'env SETLIST_SKIP_TRUNK_AUDIT=1 git push origin main' CM-BYPASS-SPELLED
bd_deny f2g 'git commit -m x --no-verify' CM-BYPASS-SPELLED
# The 2.6.0 leg's F2, F3, F10, F11 (fix round 1, 2026-09-08), watched RED on the
# candidate 2217acea: the span-deleting un-quoter missed every spelling git honours
# that a quote touched, and sed paired quotes ACROSS segments. The deny is a word
# test over a deny-local lexer now; these are the evasions.
bd_deny i 'git commit "--no-verify" -m x' CM-BYPASS-SPELLED
bd_deny j "git commit '--no-verify' -m x" CM-BYPASS-SPELLED
bd_deny k 'git commit --no-veri"f"y -m x' CM-BYPASS-SPELLED
bd_deny l 'echo "a \" b" && git commit --no-verify -m x && echo "c \" d"' CM-BYPASS-SPELLED
bd_deny m 'git commit -n -m x' CM-BYPASS-SPELLED
bd_deny n 'git commit -an -m x' CM-BYPASS-SPELLED
bd_deny o 'git commit --no-veri -m x' CM-BYPASS-SPELLED
bd_deny p 'git push --no-verif origin main' CM-BYPASS-SPELLED
bd_deny q 'git -c "core.hooksPath=/dev/null" commit -m x' CM-HOOKSPATH-MOVED
bd_deny r 'git -ccore.hooksPath=/dev/null commit -m x' CM-HOOKSPATH-MOVED
bd_deny s 'SETLIST_SKIP_HOOKS="1" git commit -m x' CM-BYPASS-SPELLED
bd_deny t 'env SETLIST_SKIP_TRUNK_AUDIT=1 git push' CM-BYPASS-SPELLED
# THE FALSE-DENIAL SURFACE, pinned in the allowing direction: a spelling inside
# quotes is prose, a flag word without git is not a git flag, and the variable's
# NAME without an assignment is a grep.
bd_allow a 'git commit -m "never use SETLIST_SKIP_HOOKS=1 here"'
bd_allow b "git commit -m 'the flag --no-verify is refused by the gate'"
bd_allow c 'grep -r core.hooksPath .'
bd_allow d 'echo --no-verify'
bd_allow e 'grep -n SETLIST_SKIP_HOOKS templates/git-hooks/pre-push'
bd_allow f 'git commit -m x'
# The 2.6.0 leg's F8 and F9: the same detector HARD-DENIED prose. A message is one
# word to the lexer and never matches; a filename carrying the spelling is not
# the spelling; -n on push is a dry run; these are the false-denial surface,
# pinned in the allowing direction beside the evasions above.
bd_allow g 'git commit -m "he said \"use --no-verify\" once"'
bd_allow h "git commit -m \"it's about --no-verify\""
bd_allow i 'echo "a \" b" && git commit -m "prose --no-verify prose" && echo "c \" d"'
bd_allow j 'git add notes/--no-verify.md'
bd_allow k 'git push -n origin main'
bd_allow l 'git commit -m "SETLIST_SKIP_HOOKS=1 is documented, not coached"'
bd_allow m 'git log --grep=--no-verify'
# The deny reaches the MODEL: the reason is on permissionDecisionReason (deny
# reasons are delivered verbatim, unlike allow reasons, RP5) and repeated in
# systemMessage and setlistAdvisory.reason, the frozen contract's three fields.
BD_OUT="$(bd_out 'SETLIST_SKIP_HOOKS=1 git commit -m x')"
if [[ "$(printf '%s' "$BD_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)" == *"CM-BYPASS-SPELLED"* ]] \
   && [[ "$(printf '%s' "$BD_OUT" | jq -r '.systemMessage' 2>/dev/null)" == *"CM-BYPASS-SPELLED"* ]] \
   && [[ "$(printf '%s' "$BD_OUT" | jq -r '.setlistAdvisory.reason' 2>/dev/null)" == *"run the command yourself in a terminal"* ]]; then
  ok "bypass deny: the reason carries the code in all three contract fields and says how a person proceeds"
else
  bad "bypass deny: the reason carries the code in all three contract fields and says how a person proceeds" "$(printf '%s' "$BD_OUT" | cut -c1-200)"
fi
# ABOVE THE PARSERS: the detection precedes the heredoc lexer and the wrapper
# stripper in the file, so no parser byte is between the payload and the deny.
BD_DENY_LINE="$(grep -n 'CM-BYPASS-SPELLED' "$HOOKS/commit-gate.sh" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)"
BD_LEXER_LINE="$(grep -n "^HEREDOC_AWK=" "$HOOKS/commit-gate.sh" | head -1 | cut -d: -f1)"
BD_STRIP_LINE="$(grep -n "^strip_wrappers()" "$HOOKS/commit-gate.sh" | head -1 | cut -d: -f1)"
if [[ -n "$BD_DENY_LINE" && -n "$BD_LEXER_LINE" && -n "$BD_STRIP_LINE" && "$BD_DENY_LINE" -lt "$BD_LEXER_LINE" && "$BD_DENY_LINE" -lt "$BD_STRIP_LINE" ]]; then
  ok "bypass deny sits ABOVE the parsers (line $BD_DENY_LINE, before the heredoc lexer at $BD_LEXER_LINE and strip_wrappers at $BD_STRIP_LINE)"
else
  bad "bypass deny sits ABOVE the parsers" "deny=$BD_DENY_LINE lexer=$BD_LEXER_LINE strip=$BD_STRIP_LINE"
fi
# And the contract paragraph names the exception, so the header and the bytes
# say the same thing (the repository's signature defect is a header that lies).
if grep -q 'ALWAYS "allow", with ONE exception' "$HOOKS/commit-gate.sh" && grep -q '^# THE ONE DENY' "$HOOKS/commit-gate.sh"; then
  ok "bypass deny: the advisory contract at the gate's head names its one exception and why"
else
  bad "bypass deny: the advisory contract at the gate's head names its one exception and why" "the header still promises ALWAYS allow without the exception"
fi

fi; shard_region_end
# <<< SHARD-END bypass-deny-0132

# =============================================================================
# T1: THE CODEOWNERS BRIDGE (TE1), spec 0132, from the ratified design's section
# 7 and the 2.6.0 strategy's ruling 4.
#
# WHAT THESE ASSERTIONS ARE EVIDENCE OF: that the reader accepts the core grammar
# the forges share and refuses the edges BY NAME; that a declaring close whose
# declared file another owner's pattern claims is REFUSED at the audit (on an
# email owner) and at the forge check (on the forge's identity), ADVISED at the
# merge hook, and REPORTED rather than refused where the local layer cannot
# resolve the identity (ratification decision 5); and that the template lands
# with its three paths and its slot. Nothing here establishes who a person IS:
# ownership is what the file says, and the forge's identity is the one the check
# trusts. Watched red first on the tree before this arm existed (recorded in
# spec 0132's Progress).
# =============================================================================
# >>> SHARD-BEGIN codeowners-t1-0132 cost=8
if shard_region codeowners-t1-0132; then

# --- LOCKSTEP: one grammar, two homes --------------------------------------------
T1_LIB="$(grep -m1 -E "^[[:space:]]*SLH_CODEOWNERS_AWK='" "$ROOT/templates/git-hooks/setlist-hook-lib.sh")"
T1_AUD="$(grep -m1 -E "^[[:space:]]*SLH_CODEOWNERS_AWK='" "$SCRIPTS/trunk-audit.sh")"
T1_LIB_BLOCK="$(awk "/^SLH_CODEOWNERS_AWK='/,/^}'$/" "$ROOT/templates/git-hooks/setlist-hook-lib.sh")"
T1_AUD_BLOCK="$(awk "/^SLH_CODEOWNERS_AWK='/,/^}'$/" "$SCRIPTS/trunk-audit.sh")"
if [[ -n "$T1_LIB" && -n "$T1_AUD" && -n "$T1_LIB_BLOCK" && "$T1_LIB_BLOCK" == "$T1_AUD_BLOCK" ]]; then
  ok "codeowners lockstep: SLH_CODEOWNERS_AWK is byte-identical in the hook library and trunk-audit.sh"
else
  bad "codeowners lockstep: SLH_CODEOWNERS_AWK is byte-identical in the hook library and trunk-audit.sh" "the two homes of the ownership grammar drifted (lib $(printf '%s' "$T1_LIB_BLOCK" | wc -l | tr -d ' ') lines, audit $(printf '%s' "$T1_AUD_BLOCK" | wc -l | tr -d ' ') lines)"
fi

# --- THE GRAMMAR, both directions, through the library's own reader ---------------
T1G="$WORK/t1-grammar"; mkdir -p "$T1G/.github"
t1_owners() { # t1_owners <codeowners-text> <file> -> the owners the reader returns, "!UNREADABLE" when refused
  printf '%s\n' "$1" > "$T1G/.github/CODEOWNERS"
  ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"
    if slh_codeowners_load "$T1G" 2>/dev/null; then slh_codeowners_owners_of "$2"; else printf '!UNREADABLE'; fi )
}
T1_CO='# a comment
* @org/everyone
/.githooks/      @OWNER
/.claude/        @OWNER
/specs/attest/   @OWNER
/.github/        @OWNER
docs/            @writer alice@example.test
*.js             @js-team
apps/web/**/*.css @css
build/logs/
/src/deep/ @deep
/src/deep/keep.txt @keeper'
T1_GRAM_BAD=""
t1_expect() { # t1_expect <file> <want-owners>
  local got; got="$(t1_owners "$T1_CO" "$1")"
  [[ "$got" == "$2" ]] || T1_GRAM_BAD="$T1_GRAM_BAD
    $1 -> [$got], wanted [$2]"
}
t1_expect .githooks/pre-push "@OWNER"
t1_expect .claude/hooks/forge-check.sh "@OWNER"
t1_expect specs/attest/0001.json "@OWNER"
t1_expect .github/workflows/setlist-forge-check.yml "@OWNER"
t1_expect specs/0001-x.md "@org/everyone"
t1_expect docs/a/b.md "@writer alice@example.test"
t1_expect a/docs/x.md "@writer alice@example.test"
t1_expect src/app.js "@js-team"
t1_expect apps/web/a/b/c.css "@css"
t1_expect apps/web/x.css "@css"
t1_expect build/logs/out.txt ""
t1_expect src/deep/other.txt "@deep"
t1_expect src/deep/keep.txt "@keeper"
t1_expect README.md "@org/everyone"
if [[ -z "$T1_GRAM_BAD" ]]; then
  ok "codeowners grammar: anchored and unanchored patterns, directories, * and **, no-owner patterns, and LAST MATCH WINS (13 shapes)"
else
  bad "codeowners grammar: anchored and unanchored patterns, directories, * and **, no-owner patterns, and LAST MATCH WINS (13 shapes)" "$T1_GRAM_BAD"
fi
T1_REFUSED_BAD=""
while IFS='	' read -r T1_LBL T1_LINE; do
  [[ -n "$T1_LBL" ]] || continue
  T1_OUT="$( printf '%s\n' "$T1_LINE" > "$T1G/.github/CODEOWNERS"; ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1G" ) 2>&1 )"
  printf '%s' "$T1_OUT" | grep -q 'SLH-CODEOWNERS-UNREADABLE' && printf '%s' "$T1_OUT" | grep -qF -- "$T1_LBL" \
    || T1_REFUSED_BAD="$T1_REFUSED_BAD
    [$T1_LINE] was not refused naming '$T1_LBL': $(printf '%s' "$T1_OUT" | cut -c1-100)"
done <<'T1EOF'
section header	[Section]
section header	^[Section]
negated pattern	!foo @alice
escaped space	a\ b @alice
character class	a[bc] @alice
? wildcard	x? @alice
owner that is not	x nobody
T1EOF
if [[ -z "$T1_REFUSED_BAD" ]]; then
  ok "codeowners grammar: sections, negations, escaped spaces, classes, ? and a malformed owner are refused BY NAME under SLH-CODEOWNERS-UNREADABLE (7 edges)"
else
  bad "codeowners grammar: sections, negations, escaped spaces, classes, ? and a malformed owner are refused BY NAME under SLH-CODEOWNERS-UNREADABLE (7 edges)" "$T1_REFUSED_BAD"
fi
# And the reader is NOT consulted when nothing declares: an exotic file with no
# declaring close refuses nobody.
if [[ "$(t1_owners '[Section]
* @a' README.md)" == "!UNREADABLE" ]]; then
  ok "codeowners grammar control: the unreadable file IS refused when loaded (the cases above are not vacuous)"
else
  bad "codeowners grammar control: the unreadable file IS refused when loaded (the cases above are not vacuous)" "an unreadable file loaded"
fi
# The 2.6.0 leg's F12 and F13 (fix round 1, 2026-09-08), watched RED on the
# candidate 2217acea: GitHub's documented INLINE comment was read as a malformed
# owner and refused a valid file (a false denial at every declaring close and every
# pull request), and a file that EXISTS and cannot be read was skipped as absent
# (the bridge passed having read nothing, and fell through to a root CODEOWNERS
# the forge would never consult).
T1I="$WORK/t1-inline"; mkdir -p "$T1I/.github"
printf '*.js    @js-owner #This is an inline comment.\ndocs/  @docs-team    # trailing\n' > "$T1I/.github/CODEOWNERS"
T1I_OUT="$( ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1I" >/dev/null 2>&1; printf '%s|%s|%s' "$SLH_CODEOWNERS_STATE" "$(slh_codeowners_owners_of src/a.js)" "$(slh_codeowners_owners_of docs/x.md)" ) 2>/dev/null )"
if [[ "$T1I_OUT" == "ok|@js-owner|@docs-team" ]]; then
  ok "codeowners grammar F12: an inline comment after an owner is a comment (GitHub's documented syntax), and the owners resolve"
else
  bad "codeowners grammar F12: an inline comment after an owner is a comment (GitHub's documented syntax), and the owners resolve" "got [$T1I_OUT], wanted [ok|@js-owner|@docs-team]"
fi
if [[ "$(id -u)" -ne 0 ]]; then
  T1U="$WORK/t1-unreadable"; mkdir -p "$T1U/.github"; printf '/src/ alice@x.com\n' > "$T1U/.github/CODEOWNERS"; printf '/src/ bob@x.com\n' > "$T1U/CODEOWNERS"
  chmod 000 "$T1U/.github/CODEOWNERS"
  T1U_OUT="$( ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1U"; printf 'rc=%s state=%s path=%s' "$?" "$SLH_CODEOWNERS_STATE" "$SLH_CODEOWNERS_PATH" ) 2>&1 )"
  chmod 644 "$T1U/.github/CODEOWNERS"
  T1U_CTL="$( ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1U"; printf 'rc=%s state=%s path=%s' "$?" "$SLH_CODEOWNERS_STATE" "$SLH_CODEOWNERS_PATH" ) 2>&1 )"
  if printf '%s' "$T1U_OUT" | grep -q 'SLH-CODEOWNERS-UNREADABLE' && printf '%s' "$T1U_OUT" | grep -q 'cannot be read' && [[ "$T1U_OUT" == *"rc=1 state=bad path=.github/CODEOWNERS"* ]] \
     && [[ "$T1U_CTL" == *"rc=0 state=ok path=.github/CODEOWNERS"* ]]; then
    ok "codeowners F13: an ownership file that EXISTS and cannot be read refuses SLH-CODEOWNERS-UNREADABLE (never absent, never the root file); readable again, it loads (control)"
  else
    bad "codeowners F13: an ownership file that EXISTS and cannot be read refuses SLH-CODEOWNERS-UNREADABLE (never absent, never the root file); readable again, it loads (control)" "unreadable: [$(printf '%s' "$T1U_OUT" | tr '\n' ' ' | cut -c1-160)] control: [$T1U_CTL]"
  fi
else
  printf 'note: codeowners F13 skipped: running as root, where chmod 000 does not make a file unreadable\n'
fi

# --- THE THREE LAYERS -----------------------------------------------------------
# A declaring squash-shaped close: spec 0001 declares src/feat.txt, the record
# says closed, and .github/CODEOWNERS assigns src/ to an owner. The closing
# commit's author email is the fixture's tests@example.invalid (git_init).
t1_declaring_fixture() { # t1_declaring_fixture <dir> <codeowners-line>
  local d="$1"
  rp1_fixture "$d"
  mkdir -p "$d/.github"
  printf '%s\n' "$2" > "$d/.github/CODEOWNERS"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "ownership file" >/dev/null 2>&1
  printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$d/specs/0001-thing.md"
  printf 'declared work\n' > "$d/src/feat.txt"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$d/.claude/status.json"
  sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
}
# (a) pre-push's AUDIT, single-parent arm: an email owner that is not the author REFUSES.
T1A="$WORK/t1-audit-mismatch"; t1_declaring_fixture "$T1A" 'src/ alice@example.test'
git -C "$T1A" -c core.hooksPath=/dev/null commit -qm "declaring close" >/dev/null 2>&1
T1A_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1A" 2>&1)"; T1A_RC=$?
if [[ "$T1A_RC" -ne 0 ]] && printf '%s' "$T1A_OUT" | grep -q '\[SLH-OWNS-CODEOWNERS\] src/feat.txt' && printf '%s' "$T1A_OUT" | grep -q 'alice@example.test, which does not include tests@example.invalid'; then
  ok "codeowners audit a: a declared file another EMAIL owns is REFUSED at the audit, naming the file, the owners and the closer"
else
  bad "codeowners audit a: a declared file another EMAIL owns is REFUSED at the audit, naming the file, the owners and the closer" "rc=$T1A_RC: $(printf '%s' "$T1A_OUT" | grep -i 'codeowners\|violations' | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# (b) the matching email owner passes, silently on this axis.
T1B="$WORK/t1-audit-match"; t1_declaring_fixture "$T1B" 'src/ tests@example.invalid'
git -C "$T1B" -c core.hooksPath=/dev/null commit -qm "declaring close" >/dev/null 2>&1
T1B_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1B" 2>&1)"; T1B_RC=$?
if [[ "$T1B_RC" -eq 0 ]] && ! printf '%s' "$T1B_OUT" | grep -q 'CODEOWNERS'; then
  ok "codeowners audit b: the owner closing their own file passes with no ownership line (the false-denial direction)"
else
  bad "codeowners audit b: the owner closing their own file passes with no ownership line (the false-denial direction)" "rc=$T1B_RC: $(printf '%s' "$T1B_OUT" | grep -i 'codeowners' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (c) a HANDLE owner cannot be resolved locally: REPORTED, not refused (decision 5).
T1C="$WORK/t1-audit-handle"; t1_declaring_fixture "$T1C" 'src/ @alice'
git -C "$T1C" -c core.hooksPath=/dev/null commit -qm "declaring close" >/dev/null 2>&1
T1C_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1C" 2>&1)"; T1C_RC=$?
if [[ "$T1C_RC" -eq 0 ]] && printf '%s' "$T1C_OUT" | grep -q '\[SLH-OWNS-CODEOWNERS-UNRESOLVED\] src/feat.txt' && ! printf '%s' "$T1C_OUT" | grep -q 'VIOLATION.*CODEOWNERS'; then
  ok "codeowners audit c: a handle owner the audit cannot resolve is REPORTED (SLH-OWNS-CODEOWNERS-UNRESOLVED) and the push is not refused"
else
  bad "codeowners audit c: a handle owner the audit cannot resolve is REPORTED (SLH-OWNS-CODEOWNERS-UNRESOLVED) and the push is not refused" "rc=$T1C_RC: $(printf '%s' "$T1C_OUT" | grep -i 'codeowners' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (d) an email owner beside a handle: the email matches, so no report and no refusal.
T1D="$WORK/t1-audit-mixed"; t1_declaring_fixture "$T1D" 'src/ @alice tests@example.invalid'
git -C "$T1D" -c core.hooksPath=/dev/null commit -qm "declaring close" >/dev/null 2>&1
T1D_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1D" 2>&1)"; T1D_RC=$?
if [[ "$T1D_RC" -eq 0 ]] && ! printf '%s' "$T1D_OUT" | grep -q 'CODEOWNERS'; then
  ok "codeowners audit d: a matching email beside an unresolvable handle is a match, not a report"
else
  bad "codeowners audit d: a matching email beside an unresolvable handle is a match, not a report" "rc=$T1D_RC: $(printf '%s' "$T1D_OUT" | grep -i 'codeowners' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (e) an unreadable file with a declaring close refuses BY NAME at the audit.
T1E="$WORK/t1-audit-unreadable"; t1_declaring_fixture "$T1E" '[Section]
src/ @alice'
git -C "$T1E" -c core.hooksPath=/dev/null commit -qm "declaring close" >/dev/null 2>&1
T1E_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1E" 2>&1)"; T1E_RC=$?
if [[ "$T1E_RC" -ne 0 ]] && printf '%s' "$T1E_OUT" | grep -q '\[SLH-CODEOWNERS-UNREADABLE\] line 1 of .github/CODEOWNERS uses a section header'; then
  ok "codeowners audit e: an unreadable ownership file under a declaring close refuses SLH-CODEOWNERS-UNREADABLE naming the line and the feature"
else
  bad "codeowners audit e: an unreadable ownership file under a declaring close refuses SLH-CODEOWNERS-UNREADABLE naming the line and the feature" "rc=$T1E_RC: $(printf '%s' "$T1E_OUT" | grep -i 'codeowners' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (f) the same unreadable file with NO declaring close refuses nobody: the reader is not consulted.
T1F="$WORK/t1-audit-quiet"; rp1_fixture "$T1F"; mkdir -p "$T1F/.github"; printf '[Section]\nsrc/ @alice\n' > "$T1F/.github/CODEOWNERS"
printf 'docs only\n' > "$T1F/README.md"; git -C "$T1F" add -A >/dev/null 2>&1; git -C "$T1F" -c core.hooksPath=/dev/null commit -qm "docs and an exotic ownership file" >/dev/null 2>&1
T1F_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$T1F" 2>&1)"; T1F_RC=$?
if [[ "$T1F_RC" -eq 0 ]] && ! printf '%s' "$T1F_OUT" | grep -q 'CODEOWNERS'; then
  ok "codeowners audit f: an exotic ownership file with no declaring close is never read (a team is not refused for a file the check never needed)"
else
  bad "codeowners audit f: an exotic ownership file with no declaring close is never read" "rc=$T1F_RC: $(printf '%s' "$T1F_OUT" | grep -i 'codeowners' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (g) pre-merge-commit ADVISES (ruling 4): a declaring close merged locally with
# the hooks armed lands, with the advisory line on stderr.
T1M="$WORK/t1-merge-advise"; rp1_fixture "$T1M"; mkdir -p "$T1M/.github"; printf 'src/ alice@example.test\n' > "$T1M/.github/CODEOWNERS"
git -C "$T1M" add -A >/dev/null 2>&1; git -C "$T1M" -c core.hooksPath=/dev/null commit -qm "ownership file" >/dev/null 2>&1
git -C "$T1M" checkout -q -b spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$T1M/specs/0001-thing.md"
printf 'declared work\n' > "$T1M/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$T1M/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$T1M/specs/STATUS.md" > "$T1M/specs/STATUS.md.new" && mv "$T1M/specs/STATUS.md.new" "$T1M/specs/STATUS.md"
git -C "$T1M" add -A >/dev/null 2>&1; git -C "$T1M" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
git -C "$T1M" checkout -q main
if ( cd "$T1M" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "merge 0001" spec/0001-thing ) >"$WORK/t1-merge.out" 2>&1 \
   && grep -q 'SLH-OWNS-CODEOWNERS\] this merge (advisory): src/feat.txt' "$WORK/t1-merge.out" && grep -q 'a claim' "$WORK/t1-merge.out"; then
  ok "codeowners merge g: pre-merge-commit ADVISES on a mismatch (the clone's identity is a claim) and the merge lands"
else
  bad "codeowners merge g: pre-merge-commit ADVISES on a mismatch (the clone's identity is a claim) and the merge lands" "$(tr '\n' ' ' < "$WORK/t1-merge.out" | cut -c1-240)"
fi
# (h) the FORGE CHECK refuses on the forge's identity: the pull request's author login.
T1P="$WORK/t1-forge"; fc_fixture "$T1P" off
mkdir -p "$T1P/.github"; printf 'src/ @alice\ndocs/ @org/writers\nlib/ carol@example.test\n' > "$T1P/.github/CODEOWNERS"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$T1P/.claude/status.json"
git -C "$T1P" add -A >/dev/null 2>&1; git -C "$T1P" -c core.hooksPath=/dev/null commit -qm "ownership and the record" >/dev/null 2>&1
git -C "$T1P" checkout -q -b spec/0001-thing
printf '# Spec 0001 - thing\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Goal\nBuild the thing.\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$T1P/specs/0001-thing.md"
printf 'declared work\n' > "$T1P/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$T1P/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | shipped |\n' > "$T1P/specs/STATUS.md"
git -C "$T1P" add -A >/dev/null 2>&1; git -C "$T1P" -c core.hooksPath=/dev/null commit -qm "close 0001, declaring" >/dev/null 2>&1
git -C "$T1P" checkout -q main
fc_run "$T1P" --base main --head spec/0001-thing --forge none --author alice
fc_case "codeowners h: the pull request's author owns the declared file: PASS" 0 "PASS (custody: none declared)"
fc_run "$T1P" --base main --head spec/0001-thing --forge none --author bob
fc_case "codeowners i: another author is CODEOWNERS-MISMATCH at the check (row 16), on the forge's identity" 1 "CODEOWNERS-MISMATCH" SLH-OWNS-CODEOWNERS
# Teams and emails are resolved at the forge; the stub answers the membership
# and user queries. An unanswered query is UNVERIFIABLE, never "not a member".
T1_STUB="$WORK/t1-forge-stub.sh"
cat > "$T1_STUB" <<'STUB'
#!/usr/bin/env bash
case "$T1_STUB_MODE:$1" in
  *:repos/*) printf '200\n{"allow_rebase_merge":false}\n' ;;
  member:orgs/org/teams/writers/memberships/dana) printf '200\n{"state":"active"}\n' ;;
  notmember:orgs/org/teams/writers/memberships/dana) printf '404\n{"message":"Not Found"}\n' ;;
  forbidden:orgs/*) printf '403\n{"message":"Resource not accessible by integration"}\n' ;;
  *:users/carol) printf '200\n{"login":"carol","email":"carol@example.test"}\n' ;;
  *:users/*) printf '200\n{"login":"x","email":null}\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T1_STUB"
git -C "$T1P" checkout -q spec/0001-thing
printf '# Spec 0001 - thing\n\nStatus: CLOSED\nOwns: docs/guide.md\n\n## Goal\nBuild the thing.\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$T1P/specs/0001-thing.md"
git -C "$T1P" rm -q src/feat.txt; mkdir -p "$T1P/docs"; printf 'guide\n' > "$T1P/docs/guide.md"
git -C "$T1P" add -A >/dev/null 2>&1; git -C "$T1P" -c core.hooksPath=/dev/null commit -qm "declare a team-owned file instead" >/dev/null 2>&1
git -C "$T1P" checkout -q main
T1_STUB_MODE=member fc_run "$T1P" --base main --head spec/0001-thing --forge github --repo org/repo --author dana --forge-query "$T1_STUB"
fc_case "codeowners j: a team owner is resolved at the forge; an active member PASSES" 0 "PASS (custody: none declared)"
T1_STUB_MODE=notmember fc_run "$T1P" --base main --head spec/0001-thing --forge github --repo org/repo --author dana --forge-query "$T1_STUB"
fc_case "codeowners k: a team owner is resolved at the forge; a non-member is CODEOWNERS-MISMATCH" 1 "CODEOWNERS-MISMATCH" SLH-OWNS-CODEOWNERS
T1_STUB_MODE=forbidden fc_run "$T1P" --base main --head spec/0001-thing --forge github --repo org/repo --author dana --forge-query "$T1_STUB"
fc_case "codeowners l: a membership query the token may not make is UNVERIFIABLE (FC-FORGE-FORBIDDEN), never 'not a member'" 1 "FORGE-UNREACHABLE" FC-FORGE-FORBIDDEN
git -C "$T1P" checkout -q spec/0001-thing
printf '# Spec 0001 - thing\n\nStatus: CLOSED\nOwns: lib/x.txt\n\n## Goal\nBuild the thing.\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$T1P/specs/0001-thing.md"
git -C "$T1P" rm -q docs/guide.md; mkdir -p "$T1P/lib"; printf 'x\n' > "$T1P/lib/x.txt"
git -C "$T1P" add -A >/dev/null 2>&1; git -C "$T1P" -c core.hooksPath=/dev/null commit -qm "declare an email-owned file" >/dev/null 2>&1
git -C "$T1P" checkout -q main
T1_STUB_MODE=member fc_run "$T1P" --base main --head spec/0001-thing --forge github --repo org/repo --author carol --forge-query "$T1_STUB"
fc_case "codeowners m: an email owner is matched through the forge's user record: PASS" 0 "PASS (custody: none declared)"
T1_STUB_MODE=member fc_run "$T1P" --base main --head spec/0001-thing --forge github --repo org/repo --author erin --forge-query "$T1_STUB"
fc_case "codeowners n: an email owner that is not the author's public email is CODEOWNERS-MISMATCH" 1 "CODEOWNERS-MISMATCH" SLH-OWNS-CODEOWNERS
# (o) an unreadable file under a declaring close refuses at the check too (row 15).
git -C "$T1P" checkout -q spec/0001-thing; printf '!src/ @alice\n' > "$T1P/.github/CODEOWNERS"
git -C "$T1P" add -A >/dev/null 2>&1; git -C "$T1P" -c core.hooksPath=/dev/null commit -qm "an exotic ownership file" >/dev/null 2>&1; git -C "$T1P" checkout -q main
fc_run "$T1P" --base main --head spec/0001-thing --forge none --author carol
fc_case "codeowners o (row 15): an unreadable ownership file under a declaring close is CODEOWNERS-UNREADABLE at the check" 1 "CODEOWNERS-UNREADABLE" SLH-CODEOWNERS-UNREADABLE

# --- THE TEMPLATE AND ITS DELIVERY ------------------------------------------------
if [[ -f "$ROOT/templates/root/github/CODEOWNERS.tmpl" ]] \
   && grep -qE '^/\.githooks/[[:space:]]+@OWNER$' "$ROOT/templates/root/github/CODEOWNERS.tmpl" \
   && grep -qE '^/\.claude/[[:space:]]+@OWNER$' "$ROOT/templates/root/github/CODEOWNERS.tmpl" \
   && grep -qE '^/specs/attest/[[:space:]]+@OWNER$' "$ROOT/templates/root/github/CODEOWNERS.tmpl" \
   && grep -qE '^/\.github/[[:space:]]+@OWNER$' "$ROOT/templates/root/github/CODEOWNERS.tmpl" \
   && grep -q 'PHASE 2 SLOT' "$ROOT/templates/root/github/CODEOWNERS.tmpl"; then
  ok "codeowners template: the four protected paths under the @OWNER phase-2 slot (amendment 5 added /.github/)"
else
  bad "codeowners template: the four protected paths under the @OWNER phase-2 slot (amendment 5 added /.github/)" "the template is missing a path or the slot"
fi
T1S="$WORK/t1-stamp"; rm -rf "$T1S"; mkdir -p "$T1S"; git -C "$T1S" init -q >/dev/null 2>&1; git -C "$T1S" commit -q --allow-empty -m seed >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$T1S" >/dev/null 2>&1
if [[ -f "$T1S/.github/CODEOWNERS" ]] && cmp -s "$ROOT/templates/root/github/CODEOWNERS.tmpl" "$T1S/.github/CODEOWNERS" \
   && grep -q 'root/github/CODEOWNERS.tmpl' "$ROOT/templates/STAMP-TREE.md"; then
  ok "codeowners delivery: stamp.sh lands .github/CODEOWNERS byte-verbatim and STAMP-TREE.md carries its row"
else
  bad "codeowners delivery: stamp.sh lands .github/CODEOWNERS byte-verbatim and STAMP-TREE.md carries its row" "stamped=$([[ -f "$T1S/.github/CODEOWNERS" ]] && echo present || echo absent)"
fi
T1R="$WORK/t1-refresh"; instance_fixture "$T1R" 2.5.0 current; git_init "$T1R" >/dev/null 2>&1
bash "$SCRIPTS/refresh-instance.sh" --apply "$T1R" >/dev/null 2>&1
if [[ -f "$T1R/.github/CODEOWNERS" ]] && cmp -s "$ROOT/templates/root/github/CODEOWNERS.tmpl" "$T1R/.github/CODEOWNERS"; then
  ok "codeowners delivery: refresh-instance.sh --apply delivers .github/CODEOWNERS to a 2.5.0 instance"
else
  bad "codeowners delivery: refresh-instance.sh --apply delivers .github/CODEOWNERS to a 2.5.0 instance" "absent or differing after the apply"
fi
printf '/.githooks/ @the-team\n' > "$T1R/.github/CODEOWNERS"
run_script bash "$SCRIPTS/refresh-instance.sh" "$T1R"
T1R_APPLY_OUT="$(bash "$SCRIPTS/refresh-instance.sh" --apply "$T1R" 2>&1)"
if [[ "$(cat "$T1R/.github/CODEOWNERS")" == "/.githooks/ @the-team" ]]; then
  ok "codeowners delivery: a team's filled-in ownership file is LEFT AS IS by refresh (the slot is theirs)"
else
  bad "codeowners delivery: a team's filled-in ownership file is LEFT AS IS by refresh (the slot is theirs)" "the refresh replaced the team's file"
fi
# RULING 2 (2026-09-07): the leave is NAMED, by file, in both modes.
if printf '%s' "$SCRIPT_OUT" | grep -q '^  \.github/CODEOWNERS: differs from the template and is LEFT AS IS' \
   && printf '%s' "$T1R_APPLY_OUT" | grep -q '^  \.github/CODEOWNERS: differs from the template and is LEFT AS IS'; then
  ok "codeowners delivery (ruling 2): the filled-in file's divergence is reported BY FILE in report mode and on --apply"
else
  bad "codeowners delivery (ruling 2): the filled-in file's divergence is reported BY FILE in report mode and on --apply" "report: $(printf '%s' "$SCRIPT_OUT" | grep 'CODEOWNERS' | cut -c1-120); apply: $(printf '%s' "$T1R_APPLY_OUT" | grep 'CODEOWNERS' | cut -c1-120)"
fi
# The stamped file itself parses in the reader, so the template never ships an
# ownership file the audit would refuse.
T1T="$WORK/t1-template"; mkdir -p "$T1T/.github"; cp "$ROOT/templates/root/github/CODEOWNERS.tmpl" "$T1T/.github/CODEOWNERS"
if ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1T" && [[ "$(slh_codeowners_owners_of .claude/sdd.json)" == "@OWNER" ]] ) 2>/dev/null; then
  ok "codeowners template: the stamped file is within the reader's grammar and owns .claude/ as written"
else
  bad "codeowners template: the stamped file is within the reader's grammar and owns .claude/ as written" "the template refuses in its own reader"
fi

# --- AMENDMENT 5 (the owner's ruling of 2026-09-07, session 3; entry 8) ---------
# The template's three paths did not cover the check's own workflow, so the
# escape paragraph's "a reviewed change" held only where the team had added
# the path. /.github/ is the fourth protected path under the slot: the
# workflow, the ownership file itself and the issue-form template are reviewed
# changes from birth. Watched red first on a21bfdc (three paths; the workflow
# owned by nobody through the template).
T1T4="$WORK/t1-template4"; mkdir -p "$T1T4/.github"; cp "$ROOT/templates/root/github/CODEOWNERS.tmpl" "$T1T4/.github/CODEOWNERS"
if ( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; slh_codeowners_load "$T1T4" \
     && [[ "$(slh_codeowners_owners_of .github/workflows/setlist-forge-check.yml)" == "@OWNER" ]] \
     && [[ "$(slh_codeowners_owners_of .github/CODEOWNERS)" == "@OWNER" ]] \
     && [[ "$(slh_codeowners_owners_of .github/ISSUE_TEMPLATE/refusal.yml)" == "@OWNER" ]] ) 2>/dev/null; then
  ok "codeowners template (amendment 5): through the reader, the check's workflow, the ownership file and the issue form are the slot's"
else
  bad "codeowners template (amendment 5): through the reader, the check's workflow, the ownership file and the issue form are the slot's" "the template does not own .github/ as stamped"
fi
if grep -q 'root/github/CODEOWNERS.tmpl' "$ROOT/templates/STAMP-TREE.md" && grep 'root/github/CODEOWNERS.tmpl' "$ROOT/templates/STAMP-TREE.md" | grep -q '/\.github/'; then
  ok "codeowners template (amendment 5): STAMP-TREE's row names the fourth path"
else
  bad "codeowners template (amendment 5): STAMP-TREE's row names the fourth path" "the row does not mention /.github/"
fi
if grep -q 'fourth protected path' "$ROOT/skills/validate/SKILL.md" && grep -q 'fourth protected path' "$SCRIPTS/refresh-instance.sh"; then
  ok "codeowners (amendment 5): the validate skill's check 20 and the refresh's report both know the fourth path by name"
else
  bad "codeowners (amendment 5): the validate skill's check 20 and the refresh's report both know the fourth path by name" "the phrase 'fourth protected path' is absent from one of them"
fi
# An instance stamped between T1 and this amendment carries the three-path
# file with its slot filled. Ruling 2 leaves it alone; this amendment makes
# the report SAY what the file lacks, by path, in both modes, so the team can
# add the line under its own owner rather than diff the template to find out.
T1R4="$WORK/t1-refresh4"; instance_fixture "$T1R4" 2.5.0 current; git_init "$T1R4" >/dev/null 2>&1
mkdir -p "$T1R4/.github"; printf '/.githooks/      @the-team\n/.claude/        @the-team\n/specs/attest/   @the-team\n' > "$T1R4/.github/CODEOWNERS"
run_script bash "$SCRIPTS/refresh-instance.sh" "$T1R4"
T1R4_APPLY_OUT="$(bash "$SCRIPTS/refresh-instance.sh" --apply "$T1R4" 2>&1)"
if printf '%s' "$SCRIPT_OUT" | grep -q '^  \.github/CODEOWNERS: differs from the template and is LEFT AS IS.*does not name the fourth protected path /\.github/' \
   && printf '%s' "$T1R4_APPLY_OUT" | grep -q '^  \.github/CODEOWNERS: differs from the template and is LEFT AS IS.*does not name the fourth protected path /\.github/' \
   && [[ "$(cat "$T1R4/.github/CODEOWNERS")" == "$(printf '/.githooks/      @the-team\n/.claude/        @the-team\n/specs/attest/   @the-team')" ]]; then
  ok "codeowners refresh (amendment 5): a three-path file is LEFT AS IS and the missing fourth path is named in report mode and on --apply"
else
  bad "codeowners refresh (amendment 5): a three-path file is LEFT AS IS and the missing fourth path is named in report mode and on --apply" "report: $(printf '%s' "$SCRIPT_OUT" | grep 'CODEOWNERS' | cut -c1-160); apply: $(printf '%s' "$T1R4_APPLY_OUT" | grep 'CODEOWNERS' | cut -c1-160)"
fi
# A file that names the fourth path under its own owner is a plain divergence
# (the slot is theirs), so the fourth-path clause does NOT appear.
printf '/.githooks/ @the-team\n/.claude/ @the-team\n/specs/attest/ @the-team\n/.github/ @the-team\n' > "$T1R4/.github/CODEOWNERS"
run_script bash "$SCRIPTS/refresh-instance.sh" "$T1R4"
if printf '%s' "$SCRIPT_OUT" | grep -q '^  \.github/CODEOWNERS: differs from the template and is LEFT AS IS' \
   && ! printf '%s' "$SCRIPT_OUT" | grep -q 'fourth protected path'; then
  ok "codeowners refresh (amendment 5): a filled-in file that names /.github/ draws the plain divergence line, no fourth-path clause"
else
  bad "codeowners refresh (amendment 5): a filled-in file that names /.github/ draws the plain divergence line, no fourth-path clause" "$(printf '%s' "$SCRIPT_OUT" | grep 'CODEOWNERS' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END codeowners-t1-0132

# =============================================================================
# CLUSTER C, THE ADVISORY RULING (spec 0132, the owner's ruling 1 of 2026-09-06
# on the 2.6.0 strategy: position (iii)). The close gate's PreToolUse run of
# the instance's gate command is GONE, its two codes retired, the template's
# timeout for the entry 300; KL11 taken in the same cluster (the advisory
# code is extracted by parameter expansion, pinned under a silent sed). Every
# case below was watched red on 5825267 before the bytes moved, except the two
# that assert a public bullet's new wording, which are pins on prose.
# =============================================================================
# ar_bin <dir> : a PATH holding every tool the hooks use except sed, which is a
# stub that exits 0 printing nothing (KL11's exact scenario, the 2.5.0 leg's
# F12). Defined outside the region, as every region's helpers are.
ar_bin() {
  local t p; rm -rf "$1"; mkdir -p "$1"
  for t in bash sh git grep awk cat head tail od tr wc cut sort uniq printf env dirname basename \
           mkdir rm cp mv ls chmod date mktemp shasum find xargs comm diff jq; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$1/$t"
  done
  printf '#!/bin/sh\nexit 0\n' > "$1/sed"; chmod +x "$1/sed"
}
# ar_code_of <reason> : the suite's OWN reading of the bracketed code, by bash
# and not by the hook's helper, so the assertion does not trust what it tests.
ar_code_of() {
  local rest="$1" cand out=""
  while [[ "$rest" == *"["* ]]; do
    rest="${rest#*\[}"; [[ "$rest" == *"]"* ]] || break; cand="${rest%%\]*}"
    case "$cand" in [A-Z]*) case "$cand" in *[!A-Z0-9-]*) ;; *) out="$cand" ;; esac ;; esac
  done
  printf '%s' "$out"
}

# >>> SHARD-BEGIN advisory-ruling-0132 cost=6
if shard_region advisory-ruling-0132; then

# --- the removal, asserted absent -----------------------------------------------
if ! grep -q 'CG-GATE-COMMAND-RED\|CG-NO-GATE-COMMAND' "$HOOKS/close-gate.sh" && ! grep -q 'bash -c "\$GATE_CMD"' "$HOOKS/close-gate.sh"; then
  ok "advisory ruling: the close gate carries neither retired code nor the gate-command run"
else
  bad "advisory ruling: the close gate carries neither retired code nor the gate-command run" "$(grep -n 'CG-GATE-COMMAND-RED\|CG-NO-GATE-COMMAND\|bash -c \"\$GATE_CMD\"' "$HOOKS/close-gate.sh" | head -3 | cut -c1-100 | tr '\n' ' ')"
fi
if grep -q 'WHAT LEFT IN 2.6.0, AND WHY' "$HOOKS/close-gate.sh" && grep -q 'THE GATE COMMAND IS NOT RUN HERE' "$HOOKS/close-gate.sh"; then
  ok "advisory ruling: the contract at the gate's head names what left and why, and the green path says where the run went"
else
  bad "advisory ruling: the contract at the gate's head names what left and why, and the green path says where the run went" "one of the two sentences is missing"
fi
AR_TMPL="$(grep -v '^{{IF:' "$ROOT/templates/claude/settings.json.tmpl")"
AR_CLOSE_T="$(printf '%s' "$AR_TMPL" | jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("close-gate")) | .timeout] | .[0]' 2>/dev/null)"
AR_COMMIT_T="$(printf '%s' "$AR_TMPL" | jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("commit-gate")) | .timeout] | .[0]' 2>/dev/null)"
if [[ "$AR_CLOSE_T" == "300" && "$AR_COMMIT_T" == "300" ]]; then
  ok "advisory ruling: the template's close-gate timeout fell to 300, the commit gate's figure"
else
  bad "advisory ruling: the template's close-gate timeout fell to 300, the commit gate's figure" "close=$AR_CLOSE_T commit=$AR_COMMIT_T"
fi

# --- ONE gate-command invocation per close across both layers --------------------
# The measurement the ruling was priced on: through 2.5.0 a close ran the suite
# twice (the close gate's PreToolUse run, verdict discarded; pre-merge-commit's
# run, verdict acted on). The gate command here appends one byte per run; the
# session layer is driven with the merge command's payload, then the merge
# itself fires the git hook. Red on 5825267: two bytes.
AR1="$WORK/ar-once"; gh_fixture "$AR1" yes
AR1_CNT="$WORK/ar-once.count"; rm -f "$AR1_CNT"
jq --arg c "printf x >> $AR1_CNT" '.gate_command = $c' "$AR1/.claude/sdd.json" > "$AR1/.claude/sdd.json.n" && mv "$AR1/.claude/sdd.json.n" "$AR1/.claude/sdd.json"
git -C "$AR1" add -A >/dev/null 2>&1; git -C "$AR1" commit -qm "gate command" >/dev/null 2>&1
git -C "$AR1" config core.hooksPath .githooks
printf %s "$(jq -nc '{tool_name:"Bash",tool_input:{command:"git merge --no-ff spec/0001-thing"}}')" \
  | CLAUDE_PROJECT_DIR="$AR1" bash "$HOOKS/close-gate.sh" >/dev/null 2>&1
AR1_SESSION="$( { [[ -f "$AR1_CNT" ]] && wc -c < "$AR1_CNT" || printf 0; } | tr -d ' ')"
git -C "$AR1" merge --no-ff -q -m "close 0001" spec/0001-thing >/dev/null 2>&1; AR1_MRC=$?
AR1_TOTAL="$( { [[ -f "$AR1_CNT" ]] && wc -c < "$AR1_CNT" || printf 0; } | tr -d ' ')"
if [[ "$AR1_MRC" -eq 0 && "$AR1_TOTAL" == "1" && "$AR1_SESSION" == "0" ]]; then
  ok "advisory ruling: a close runs the gate command ONCE, at the git hook, and never in the session layer (measured 1 where 2.5.0 measured 2)"
else
  bad "advisory ruling: a close runs the gate command ONCE, at the git hook, and never in the session layer (measured 1 where 2.5.0 measured 2)" "merge rc=$AR1_MRC, runs after the session layer=$AR1_SESSION, runs after the merge=$AR1_TOTAL"
fi

# --- KL11: the code survives a silent sed, in all three gates ----------------------
AR_BIN="$WORK/ar-silent-sed"; ar_bin "$AR_BIN"
if [[ "$(printf 'x\n' | PATH="$AR_BIN" sed 's/x/y/')" == "" ]]; then
  ok "KL11 fixture: the stub sed exits 0 printing nothing"
else
  bad "KL11 fixture: the stub sed exits 0 printing nothing" "the stub is not silent"
fi
AR2="$WORK/ar-kl11"; rm -rf "$AR2"; mkdir -p "$AR2/.claude" "$AR2/src" "$AR2/specs"; git_init "$AR2"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$AR2/.claude/sdd.json"
ar_kl11_case() { # ar_kl11_case <hook> <payload-json> <label>
  local out verdict code reason want
  out="$(printf '%s' "$2" | PATH="$AR_BIN" CLAUDE_PROJECT_DIR="$AR2" bash "$HOOKS/$1.sh" 2>/dev/null)"
  verdict="$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // "<none>"' 2>/dev/null)"
  code="$(printf '%s' "$out" | jq -r '.setlistAdvisory.code // "<absent>"' 2>/dev/null)"
  reason="$(printf '%s' "$out" | jq -r '.setlistAdvisory.reason // ""' 2>/dev/null)"
  want="$(ar_code_of "$reason")"
  if [[ "$verdict" == "deny" && -n "$want" && "$code" == "$want" ]]; then
    ok "KL11 $3: under a silent sed the deny carries its code ($code) in setlistAdvisory.code, read back equal to the reason's bracket"
  else
    bad "KL11 $3: under a silent sed the deny carries its code in setlistAdvisory.code, read back equal to the reason's bracket" "verdict=$verdict code=[$code] reason-bracket=[$want]: sed extracted the code through 2.5.0 and a silent sed emptied the field (the 2.5.0 leg's F12)"
  fi
}
ar_kl11_case commit-gate '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' "commit gate"
ar_kl11_case close-gate  '{"tool_name":"Bash","tool_input":{"command":"git merge --no-ff spec/0001-thing"}}' "close gate"
ar_kl11_case scope-hook  "$(jq -nc --arg p "$AR2/src/x.js" '{tool_name:"Write",tool_input:{file_path:$p}}')" "scope hook"
# The no-jq path is the one the fix was filed against (advise_literal cannot
# escape through jq, and could not extract through sed either): the commit
# gate's no-input deny under the same silent sed.
ar_kl11_case commit-gate '' "commit gate, the literal path (no payload)"
# The healthy direction: with a working sed nothing about the field changed.
AR_H_OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$AR2" bash "$HOOKS/commit-gate.sh" 2>/dev/null)"
if [[ -z "$AR_H_OUT" ]] || [[ "$(printf '%s' "$AR_H_OUT" | jq -r '.setlistAdvisory.code // ""' 2>/dev/null)" =~ ^[A-Z][A-Z0-9-]*$ ]]; then
  ok "KL11 control: with a healthy sed the commit gate's verdict is unchanged (an allow, or a deny with a well-formed code)"
else
  bad "KL11 control: with a healthy sed the commit gate's verdict is unchanged" "$(printf '%s' "$AR_H_OUT" | cut -c1-160)"
fi
if ! grep -q "sed -n 's/\.\*\\\[" "$HOOKS/commit-gate.sh" "$HOOKS/close-gate.sh" "$HOOKS/scope-hook.sh" 2>/dev/null; then
  ok "KL11: no advisory hook extracts the code with sed any more (the expression is gone from all three)"
else
  bad "KL11: no advisory hook extracts the code with sed any more (the expression is gone from all three)" "$(grep -c "sed -n 's/\.\*\\\[" "$HOOKS/commit-gate.sh" "$HOOKS/close-gate.sh" "$HOOKS/scope-hook.sh" | tr '\n' ' ')"
fi

# --- the two public bullets that named the run ------------------------------------
# The public README lives at publish/README.public.md in the source and ships as
# README.md; the export carries no publish/. These two cases READ the shipped
# text in both places rather than skipping in one: the first cut read the source
# path unguarded and the public repository's CI was the first thing to execute
# it (the 2.6.0 walk's macOS gate, fix round 2, 2026-09-08; RP23).
AR_README="$ROOT/publish/README.public.md"
[[ -f "$AR_README" ]] || AR_README="$ROOT/README.md"
# The list is two layers since spec 0134 (2.6.1): the README carries each hole as its
# title plus one sentence, LIMITATIONS.md the full text. The title is read from the
# README (the ledger keys on it); the sentence inside a bullet is read from the full text.
# Both files are read where they are: the source paths here, the export's at the root.
AR_LIM="$ROOT/publish/LIMITATIONS.md"
[[ -f "$AR_LIM" ]] || AR_LIM="$ROOT/LIMITATIONS.md"
if grep -qF -- '- **A `<<\EOF` heredoc body is read as code by the session gates.**' "$AR_README" && ! grep -q 'can run your whole gate command' "$AR_README"; then
  ok "advisory ruling: the heredoc bullet lost its gate-command clause and keeps its title (the ledger keys on it)"
else
  bad "advisory ruling: the heredoc bullet lost its gate-command clause and keeps its title (the ledger keys on it)" "$(grep -n 'heredoc body' "$AR_README" | cut -c1-120)"
fi
if grep -q '300 seconds for each Bash gate since 2.6.0' "$AR_LIM" && ! grep -q '30 minutes for the close gate, which re-runs' "$AR_LIM"; then
  ok "advisory ruling: the timed-out-hook bullet names 300 and no longer promises a 30-minute suite run in the hook"
else
  bad "advisory ruling: the timed-out-hook bullet names 300 and no longer promises a 30-minute suite run in the hook" "$(grep -n 'timed-out hook' "$AR_LIM" | cut -c1-120)"
fi

fi; shard_region_end
# <<< SHARD-END advisory-ruling-0132

# =============================================================================
# P2, THE gates BLOCK (spec 0132 session 2; design section 8; the owner's
# ruling of 2026-09-07 on the migration). The template stamps the block with
# three empty tiers after `release`; pre-commit runs `commit` on every commit;
# pre-merge-commit runs `close`; the forge check runs `push` (pinned in its
# own region); the refresh WRITES the block on an instance that lacks it, with
# close and push the single gate_command so no verdict changes, names what it
# would write in report mode, and leaves a present or malformed block alone.
# Watched red on the cluster C commit before the bytes moved.
# =============================================================================
# gb_commit_case <label> <gates-json|absent> <want: allow|SLH-GATE-COMMAND-FAILED|SLH-GATES-SHAPE>
# An ORDINARY commit on the spec branch of a gh_fixture through pre-commit,
# with the gates block set as given in the working tree's sdd.json.
gb_commit_case() {
  local label="$1" gates="$2" want="$3" d="$WORK/gb-commit" out rc got
  gh_fixture "$d" no
  git -C "$d" checkout -q spec/0001-thing
  if [[ "$gates" == "absent" ]]; then
    jq 'del(.gates)' "$d/.claude/sdd.json" > "$d/.claude/sdd.json.n"
  else
    jq --argjson g "$gates" '.gates = $g' "$d/.claude/sdd.json" > "$d/.claude/sdd.json.n"
  fi
  mv "$d/.claude/sdd.json.n" "$d/.claude/sdd.json"
  printf 'more\n' >> "$d/src/FEATURE.txt"; git -C "$d" add src/FEATURE.txt
  out="$(git -C "$d" commit -qm "more work" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then got=allow; else got="$(printf '%s' "$out" | grep -o 'SLH-GATE-COMMAND-FAILED\|SLH-GATES-SHAPE\|SLH-NO-GATE-COMMAND' | head -1)"; [[ -n "$got" ]] || got="refused:other"; fi
  if [[ "$got" == "$want" ]]; then
    ok "gates commit tier [$label]: $want"
  else
    bad "gates commit tier [$label]: wanted $want" "got $got (rc=$rc): $(printf '%s' "$out" | grep -i 'setlist\|SLH-' | head -2 | tr '\n' ' ' | cut -c1-200)"
  fi
}
# gb_merge_case <label> <gate_command> <gates-json> <want: allow|SLH-GATE-COMMAND-FAILED>
gb_merge_case() {
  local label="$1" single="$2" gates="$3" want="$4" d="$WORK/gb-merge" out rc got
  gh_fixture "$d" yes
  jq --arg s "$single" --argjson g "$gates" '.gate_command = $s | .gates = $g' "$d/.claude/sdd.json" > "$d/.claude/sdd.json.n" && mv "$d/.claude/sdd.json.n" "$d/.claude/sdd.json"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "gates" >/dev/null 2>&1
  out="$(git -C "$d" merge --no-ff -q -m "close 0001" spec/0001-thing 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then got=allow; else got="$(printf '%s' "$out" | grep -o 'SLH-GATE-COMMAND-FAILED\|SLH-GATES-SHAPE\|SLH-NO-GATE-COMMAND' | head -1)"; [[ -n "$got" ]] || got="refused:other"; fi
  if [[ "$got" == "$want" ]]; then
    ok "gates close tier [$label]: $want"
  else
    bad "gates close tier [$label]: wanted $want" "got $got (rc=$rc): $(printf '%s' "$out" | grep -i 'setlist\|SLH-' | head -2 | tr '\n' ' ' | cut -c1-200)"
  fi
}

# >>> SHARD-BEGIN gates-block-0132 cost=8
if shard_region gates-block-0132; then

GB_TMPL="$ROOT/templates/claude/sdd.json.tmpl"
if jq -e '.gates == {commit: "", close: "", push: ""}' "$GB_TMPL" >/dev/null 2>&1 && jq -e 'keys_unsorted | index("gates") > index("release")' "$GB_TMPL" >/dev/null 2>&1; then
  ok "gates template: sdd.json.tmpl stamps the block with three empty string tiers, appended after release"
else
  bad "gates template: sdd.json.tmpl stamps the block with three empty string tiers, appended after release" "$(jq -c '{gates, keys: keys_unsorted}' "$GB_TMPL" 2>/dev/null | cut -c1-160)"
fi
if grep -q 'The `gates`' "$ROOT/templates/STAMP-TREE.md" && grep -q 'slh_gate_command_for' "$ROOT/templates/STAMP-TREE.md"; then
  ok "gates template: STAMP-TREE.md names the block as the third framework block and its one reader"
else
  bad "gates template: STAMP-TREE.md names the block as the third framework block and its one reader" "the stamp contract does not describe the block"
fi
if grep -q '"gates" block' "$ROOT/templates/claude/skills/scaffold/SKILL.md.tmpl"; then
  ok "gates template: the scaffold skill records the three tiers beside gate_command (an empty close tier under scaffolded refuses every close)"
else
  bad "gates template: the scaffold skill records the three tiers beside gate_command (an empty close tier under scaffolded refuses every close)" "a stamped block with empty tiers and a scaffold that fills only gate_command refuses every close of a new instance"
fi

# --- pre-commit runs the commit tier on every commit -----------------------------
gb_commit_case "block absent: byte-identical, no commit-time gate"          absent                                          allow
gb_commit_case "commit tier declared and green"                             '{"commit":"true","close":"","push":""}'        allow
gb_commit_case "commit tier declared and RED refuses the commit"            '{"commit":"false","close":"","push":""}'       SLH-GATE-COMMAND-FAILED
gb_commit_case "a red close tier does not run at an ordinary commit"        '{"commit":"","close":"false","push":"false"}'  allow
gb_commit_case "SLH-GATES-SHAPE: the block is a string"                     '"npm test"'                                    SLH-GATES-SHAPE
gb_commit_case "SLH-GATES-SHAPE: a tier that is not a string"               '{"commit":1,"close":"","push":""}'             SLH-GATES-SHAPE
gb_commit_case "SLH-GATES-SHAPE: the block is a list"                       '["npm test"]'                                  SLH-GATES-SHAPE

# --- pre-merge-commit runs the close tier, which wins over the single command ---
gb_merge_case "close tier RED with a green gate_command refuses the merge"  true  '{"commit":"","close":"false","push":"true"}' SLH-GATE-COMMAND-FAILED
gb_merge_case "close tier green with a red gate_command allows the merge"   false '{"commit":"","close":"true","push":"false"}' allow
# THE VERDICT AGREES WITH THE MESSAGE (found by this region's red watch,
# 2026-09-07): session 1's reader refused SLH-GATES-SHAPE inside a command
# substitution, so the hook printed the refusal and ALLOWED. The counter is now
# set in the caller's shell; both hooks refuse. Red on the cluster C commit.
gb_merge_case "SLH-GATES-SHAPE at the merge: the refusal survives the reader's subshell" true '"npm test"' SLH-GATES-SHAPE

# --- the refresh's migration ----------------------------------------------------------
GB_R="$WORK/gb-refresh"; instance_fixture "$GB_R" 2.5.0 current; git_init "$GB_R" >/dev/null 2>&1
printf '{"trunk":"main","gate_command":"npm test","scaffolded":true,"roles":{"src":"src"},"plugin":{"version":"2.5.0"},"release":{"model":"none"}}\n' > "$GB_R/.claude/sdd.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$GB_R"
if printf '%s' "$SCRIPT_OUT" | grep -q '^\.claude/sdd\.json: no gates block.*"close": "npm test", "push": "npm test"'; then
  ok "gates migration: report mode names the block it would write, with the instance's own command at close and push"
else
  bad "gates migration: report mode names the block it would write, with the instance's own command at close and push" "$(printf '%s' "$SCRIPT_OUT" | grep -i 'gates' | head -2 | cut -c1-160 | tr '\n' ' ')"
fi
if [[ "$(jq -c '.gates' "$GB_R/.claude/sdd.json" 2>/dev/null)" == "null" ]]; then
  ok "gates migration: report mode writes nothing"
else
  bad "gates migration: report mode writes nothing" "report mode wrote: $(jq -c '.gates' "$GB_R/.claude/sdd.json")"
fi
GB_APPLY_OUT="$(bash "$SCRIPTS/refresh-instance.sh" --apply "$GB_R" 2>&1)"
if [[ "$(jq -c '.gates' "$GB_R/.claude/sdd.json" 2>/dev/null)" == '{"commit":"","close":"npm test","push":"npm test"}' ]] \
   && jq -e 'keys_unsorted | index("gates") > index("release")' "$GB_R/.claude/sdd.json" >/dev/null 2>&1 \
   && printf '%s' "$GB_APPLY_OUT" | grep -q 'wrote the gates block'; then
  ok "gates migration: --apply writes the block after release, close and push the single command, commit empty, and says so"
else
  bad "gates migration: --apply writes the block after release, close and push the single command, commit empty, and says so" "gates=$(jq -c '.gates' "$GB_R/.claude/sdd.json" 2>/dev/null) keys=$(jq -c 'keys_unsorted' "$GB_R/.claude/sdd.json" 2>/dev/null) out: $(printf '%s' "$GB_APPLY_OUT" | grep -i 'gates' | head -1 | cut -c1-120)"
fi
if [[ "$(jq -r '.gate_command' "$GB_R/.claude/sdd.json" 2>/dev/null)" == "npm test" && "$(jq -r '.plugin.version' "$GB_R/.claude/sdd.json" 2>/dev/null)" == "$PLUGIN_VERSION" ]]; then
  ok "gates migration: the single command and the recorded version survive the write"
else
  bad "gates migration: the single command and the recorded version survive the write" "$(jq -c '{gate_command, plugin}' "$GB_R/.claude/sdd.json" 2>/dev/null)"
fi
GB_BEFORE="$(jq -c '.gates' "$GB_R/.claude/sdd.json")"
run_script bash "$SCRIPTS/refresh-instance.sh" "$GB_R"
GB_APPLY2_OUT="$(bash "$SCRIPTS/refresh-instance.sh" --apply "$GB_R" 2>&1)"
if [[ "$(jq -c '.gates' "$GB_R/.claude/sdd.json")" == "$GB_BEFORE" ]] && ! printf '%s' "$SCRIPT_OUT" | grep -q 'no gates block' && ! printf '%s' "$GB_APPLY2_OUT" | grep -q 'wrote the gates block'; then
  ok "gates migration: a present block is left alone, and neither mode mentions a write (idempotent)"
else
  bad "gates migration: a present block is left alone, and neither mode mentions a write (idempotent)" "before=$GB_BEFORE after=$(jq -c '.gates' "$GB_R/.claude/sdd.json")"
fi
jq '.gates = {commit: "lint", close: "a", push: "b"}' "$GB_R/.claude/sdd.json" > "$GB_R/.claude/sdd.json.n" && mv "$GB_R/.claude/sdd.json.n" "$GB_R/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$GB_R" >/dev/null 2>&1
if [[ "$(jq -c '.gates' "$GB_R/.claude/sdd.json")" == '{"commit":"lint","close":"a","push":"b"}' ]]; then
  ok "gates migration: a team's filled-in block survives a refresh value for value"
else
  bad "gates migration: a team's filled-in block survives a refresh value for value" "$(jq -c '.gates' "$GB_R/.claude/sdd.json")"
fi
jq '.gates = "npm test"' "$GB_R/.claude/sdd.json" > "$GB_R/.claude/sdd.json.n" && mv "$GB_R/.claude/sdd.json.n" "$GB_R/.claude/sdd.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$GB_R"
bash "$SCRIPTS/refresh-instance.sh" --apply "$GB_R" >/dev/null 2>&1
if printf '%s' "$SCRIPT_OUT" | grep -q '^\.claude/sdd\.json: the gates block is not an object.*SLH-GATES-SHAPE.*LEAVES' && [[ "$(jq -c '.gates' "$GB_R/.claude/sdd.json")" == '"npm test"' ]]; then
  ok "gates migration: a block the hooks would refuse is reported by name (SLH-GATES-SHAPE) and LEFT, in both modes"
else
  bad "gates migration: a block the hooks would refuse is reported by name (SLH-GATES-SHAPE) and LEFT, in both modes" "report: $(printf '%s' "$SCRIPT_OUT" | grep -i 'gates' | head -1 | cut -c1-140); after apply: $(jq -c '.gates' "$GB_R/.claude/sdd.json")"
fi

fi; shard_region_end
# <<< SHARD-END gates-block-0132

# =============================================================================
# CLUSTER H, THE STOP HOOK AND THE .env DENY (spec 0132 session 2; the owner's
# ruling 5 on the 2.6.0 strategy; external review minors 1 and 2). The fifth
# session hook refuses to end a turn that leaves a spec or specs/STATUS.md
# changed and unstaged, once per end of turn; the wiring check learns it (KL10
# taken); the deny list gains Bash(cat .env*) and its spelling-list note in the
# one place the harness tolerates (measured). Watched red on the P2 commit,
# where the file did not exist.
# =============================================================================
# sh_nojq_bin <dir> : the toolchain linked minus jq, then a jq stub of its
# own (exits 0, prints nothing). Its own helper rather than jc_bin, which is
# defined inside another region and is absent when this one runs alone or in
# a shard; and the omission of jq from the link loop is the point: a stub
# written over a symlink writes THROUGH it into the real binary (the first cut
# of this fixture did exactly that and was saved by the Cellar's read-only bit).
sh_nojq_bin() {
  local t p; rm -rf "$1"; mkdir -p "$1"
  for t in bash sh git grep sed awk cat head tail od tr wc cut sort uniq printf env dirname basename \
           mkdir rm cp mv ls chmod date mktemp shasum find xargs comm diff; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$1/$t"
  done
  printf '#!/bin/sh\nexit 0\n' > "$1/jq"; chmod +x "$1/jq"
}
# sh_fixture <dir> : a committed instance with specs/STATUS.md and one spec
sh_fixture() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/.claude" "$d/specs" "$d/src"; git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
  printf 'x\n' > "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
}
# sh_run <dir> <payload> [PATH] -> SH_OUT
sh_run() {
  if [[ -n "${3:-}" ]]; then
    SH_OUT="$(printf '%s' "$2" | PATH="$3" CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/stop-hook.sh" 2>/dev/null)"
  else
    SH_OUT="$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/stop-hook.sh" 2>/dev/null)"
  fi
  SH_RC=$?
}
# sh_case <label> <want: allow|<code>>
sh_case() {
  local label="$1" want="$2" got
  if [[ "$SH_RC" -ne 0 ]]; then got="exit-$SH_RC"
  elif [[ -z "$SH_OUT" ]]; then got=allow
  else got="$(printf '%s' "$SH_OUT" | jq -r 'if .decision == "block" and .setlistAdvisory.gate == "stop" and .setlistAdvisory.verdict == "block" then .setlistAdvisory.code else "malformed" end' 2>/dev/null)"; [[ -n "$got" ]] || got="unparseable"; fi
  if [[ "$got" == "$want" ]]; then
    ok "stop hook [$label]: $want"
  else
    bad "stop hook [$label]: wanted $want" "got $got: $(printf '%s' "$SH_OUT" | cut -c1-200)"
  fi
}
SH_STOP_OFF='{"hook_event_name":"Stop","stop_hook_active":false}'
SH_STOP_ON='{"hook_event_name":"Stop","stop_hook_active":true}'

# >>> SHARD-BEGIN stop-hook-0132 cost=4
if shard_region stop-hook-0132; then

SHD="$WORK/stop-inst"; sh_fixture "$SHD"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "a clean tree ends the turn in silence" allow
printf 'edit\n' >> "$SHD/specs/STATUS.md"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "specs/STATUS.md changed and unstaged" SP-UNSTAGED-STATUS
if printf '%s' "$SH_OUT" | jq -e '.reason | test("specs/STATUS.md") and test("git add")' >/dev/null 2>&1; then
  ok "stop hook: the reason names the file and how to proceed"
else
  bad "stop hook: the reason names the file and how to proceed" "$(printf '%s' "$SH_OUT" | cut -c1-200)"
fi
sh_run "$SHD" "$SH_STOP_ON";                                         sh_case "the continuation this hook asked for is allowed (stop_hook_active), no loop" allow
git -C "$SHD" add specs/STATUS.md
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "a STAGED change is the session's deliberate act and passes" allow
printf 'edit\n' >> "$SHD/specs/0001-thing.md"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "a spec changed and unstaged" SP-UNSTAGED-SPEC
if printf '%s' "$SH_OUT" | jq -e '.setlistAdvisory.reason | test("specs/0001-thing.md")' >/dev/null 2>&1; then
  ok "stop hook: the refusal names the spec file"
else
  bad "stop hook: the refusal names the spec file" "$(printf '%s' "$SH_OUT" | cut -c1-200)"
fi
git -C "$SHD" add specs/0001-thing.md
printf '# new\n' > "$SHD/specs/0002-new.md"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "an UNTRACKED spec is unstaged too" SP-UNSTAGED-SPEC
rm -f "$SHD/specs/0002-new.md"
printf 'more\n' >> "$SHD/specs/STATUS.md"; printf 'more\n' >> "$SHD/specs/0001-thing.md"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "both changed: the inventory's code wins and the spec is named" SP-UNSTAGED-STATUS
if printf '%s' "$SH_OUT" | jq -e '.setlistAdvisory.reason | test("specs/0001-thing.md")' >/dev/null 2>&1; then
  ok "stop hook: with both unstaged the spec file is still named"
else
  bad "stop hook: with both unstaged the spec file is still named" "$(printf '%s' "$SH_OUT" | cut -c1-200)"
fi
git -C "$SHD" checkout -q -- specs/ 2>/dev/null; git -C "$SHD" reset -q >/dev/null 2>&1; git -C "$SHD" checkout -q -- specs/
printf 'y\n' >> "$SHD/src/app.js"
sh_run "$SHD" "$SH_STOP_OFF";                                        sh_case "a change OUTSIDE specs/ is not this hook's question" allow
SHN="$WORK/stop-notinst"; rm -rf "$SHN"; mkdir -p "$SHN/specs"; git_init "$SHN"; printf 'x\n' > "$SHN/specs/STATUS.md"
sh_run "$SHN" "$SH_STOP_OFF";                                        sh_case "not an instance (no sdd.json): none of this hook's business" allow
SHG="$WORK/stop-nogit"; rm -rf "$SHG"; mkdir -p "$SHG/.claude" "$SHG/specs"; printf '{}' > "$SHG/.claude/sdd.json"
sh_run "$SHG" "$SH_STOP_OFF";                                        sh_case "no git work tree: refused by name, never a pass on silence" SP-NO-GIT
# jq is not load-bearing: the decision and the verdict survive a jq that
# exits 0 printing nothing, and the state is REPORTED ahead of the refusal.
SH_NOJQ="$WORK/stop-nojq-bin"; sh_nojq_bin "$SH_NOJQ"
if [[ ! -L "$SH_NOJQ/jq" && "$(printf '{"p":"x"}' | PATH="$SH_NOJQ" jq -r .p 2>/dev/null)" == "" ]]; then
  ok "stop hook fixture: the stub jq is a file of its own, exits 0 and prints nothing"
else
  bad "stop hook fixture: the stub jq is a file of its own, exits 0 and prints nothing" "the stub is a symlink or is not silent; the real jq may have been written through"
fi
printf 'edit\n' >> "$SHD/specs/STATUS.md"
sh_run "$SHD" "$SH_STOP_OFF" "$SH_NOJQ";                              sh_case "under a silent jq the refusal keeps its own code" SP-UNSTAGED-STATUS
if printf '%s' "$SH_OUT" | jq -e '.setlistAdvisory.reason | startswith("[SP-JQ-BROKEN]")' >/dev/null 2>&1; then
  ok "stop hook: the broken jq is REPORTED ahead of the refusal (SP-JQ-BROKEN), by the layer that can still speak"
else
  bad "stop hook: the broken jq is REPORTED ahead of the refusal (SP-JQ-BROKEN), by the layer that can still speak" "$(printf '%s' "$SH_OUT" | cut -c1-200)"
fi
sh_run "$SHD" "$SH_STOP_ON" "$SH_NOJQ";                               sh_case "under a silent jq the continuation is still read from the raw payload" allow
if [[ "$(grep -o '\[SP-[A-Z-]*\]' "$HOOKS/stop-hook.sh" | sort -u | tr '\n' ' ')" == "[SP-JQ-BROKEN] [SP-NO-GIT] [SP-UNSTAGED-SPEC] [SP-UNSTAGED-STATUS] " ]]; then
  ok "stop hook: the code family is exactly the four the spec named, bracketed where the leg trigger reads them"
else
  bad "stop hook: the code family is exactly the four the spec named, bracketed where the leg trigger reads them" "$(grep -o '\[SP-[A-Z-]*\]' "$HOOKS/stop-hook.sh" | sort -u | tr '\n' ' ')"
fi

# --- the wiring: template, STAMP-TREE, delivery, the wiring check (KL10) ---------
SH_TMPL="$(grep -v '^{{IF:' "$ROOT/templates/claude/settings.json.tmpl")"
if [[ "$(printf '%s' "$SH_TMPL" | jq -r '[.hooks.Stop[] | .hooks[] | select(.command | test("stop-hook")) | .timeout] | .[0]' 2>/dev/null)" =~ ^[0-9]+$ ]]; then
  ok "stop hook wiring: the template wires it on the Stop event with an explicit timeout (a timed-out hook is a skipped gate)"
else
  bad "stop hook wiring: the template wires it on the Stop event with an explicit timeout (a timed-out hook is a skipped gate)" "$(printf '%s' "$SH_TMPL" | jq -c '.hooks.Stop' 2>/dev/null | cut -c1-160)"
fi
if [[ "$(printf '%s' "$SH_TMPL" | jq -c '.permissions.deny' 2>/dev/null)" == '["Read(.env)","Read(.env.*)","Bash(cat .env*)"]' ]]; then
  ok ".env deny: the template denies the Read pair and the one Bash spelling (measured 2026-09-07: cat .env and cat .env.local refused, cat env.txt allowed)"
else
  bad ".env deny: the template denies the Read pair and the one Bash spelling" "$(printf '%s' "$SH_TMPL" | jq -c '.permissions.deny' 2>/dev/null)"
fi
if printf '%s' "$SH_TMPL" | jq -e '.permissions._comment | test("SPELLING list") and test("Bash\\(cat \\.env\\*\\)") and test("less, head")' >/dev/null 2>&1 && ! grep -q '^[[:space:]]*//' "$ROOT/templates/claude/settings.json.tmpl"; then
  ok ".env deny: the spelling-list note lives in the _comment key the harness tolerates, and no // comment is in the file (measured: a // comment drops every rule)"
else
  bad ".env deny: the spelling-list note lives in the _comment key the harness tolerates, and no // comment is in the file" "$(printf '%s' "$SH_TMPL" | jq -r '.permissions._comment // "<none>"' | cut -c1-120)"
fi
if grep -q '`hooks/stop-hook.sh`' "$ROOT/templates/STAMP-TREE.md"; then
  ok "stop hook wiring: STAMP-TREE.md carries its row (always, byte-verbatim)"
else
  bad "stop hook wiring: STAMP-TREE.md carries its row (always, byte-verbatim)" "no row"
fi
# A 2.5.0 instance: four hooks, no Stop entry. The refresh REPORTS the fifth
# as missing, the wiring check names it NOT WIRED (KL10 taken: the check
# learned the spelling), --apply delivers the file and exits 3 INCOMPLETE over
# the wiring it does not write.
SHR="$WORK/stop-refresh"; instance_fixture "$SHR" 2.5.0 current; git_init "$SHR" >/dev/null 2>&1
rm -f "$SHR/.claude/hooks/stop-hook.sh"
jq 'del(.hooks.Stop)' "$SHR/.claude/settings.json" > "$SHR/.claude/settings.json.n" && mv "$SHR/.claude/settings.json.n" "$SHR/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$SHR"
if printf '%s' "$SCRIPT_OUT" | grep -q 'stop-hook.sh' && printf '%s' "$SCRIPT_OUT" | grep -A1 'NOT WIRED IN A WAY' | grep -q 'stop-hook.sh'; then
  ok "stop hook wiring (KL10 taken): a 2.5.0 instance's report names the fifth hook as missing AND as not wired"
else
  bad "stop hook wiring (KL10 taken): a 2.5.0 instance's report names the fifth hook as missing AND as not wired" "$(printf '%s' "$SCRIPT_OUT" | grep -i 'stop-hook\|NOT WIRED' | head -3 | tr '\n' ' ' | cut -c1-200)"
fi
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$SHR"
if [[ "$SCRIPT_RC" -eq 3 ]] && cmp -s "$HOOKS/stop-hook.sh" "$SHR/.claude/hooks/stop-hook.sh" && printf '%s' "$SCRIPT_OUT" | grep -q 'stop hook on Stop'; then
  ok "stop hook wiring: --apply delivers the file, exits 3 over the missing Stop entry, and names the entry that restores it"
else
  bad "stop hook wiring: --apply delivers the file, exits 3 over the missing Stop entry, and names the entry that restores it" "rc=$SCRIPT_RC delivered=$([[ -f "$SHR/.claude/hooks/stop-hook.sh" ]] && echo yes || echo no): $(printf '%s' "$SCRIPT_OUT" | grep -i 'stop' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
SHW="$WORK/stop-wired"; instance_fixture "$SHW" 2.5.0 current; git_init "$SHW" >/dev/null 2>&1
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$SHW"
if [[ "$SCRIPT_RC" -eq 0 ]] && printf '%s' "$SCRIPT_OUT" | grep -q 'refreshed the five stamped hooks'; then
  ok "stop hook wiring: the template's Stop entry certifies WIRED and the refresh completes (five hooks)"
else
  bad "stop hook wiring: the template's Stop entry certifies WIRED and the refresh completes (five hooks)" "rc=$SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tail -3 | tr '\n' ' ' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END stop-hook-0132

# =============================================================================
# THE LITE TIER (spec 0132, P1, edition v1.14; the owner's ruling 3 of
# 2026-09-06: at most five files in Owns:, no role path outside them, stated in
# Part 3, pinned here under SLH-LITE-OVERSIZED at the close). The tier is ONE
# header line read by the ownership reader the two homes already share; the
# reader counts what it prints and appends a token past the cap, and every
# consumer of the declaration refuses on it (the merge hook, the landing
# commit, the audit on both routes, the forge check). Absence is byte-identical
# to v1.13: the controls below close six files under no tier line, under
# `Tier: full`, and under a `Tier: lite` line below the Closing report heading
# (outside the hashed range), and the record differential above still reads
# the pre-record generation identical. Watched red first (recorded in spec
# 0132's Progress).
# =============================================================================
# >>> SHARD-BEGIN lite-tier-0132 cost=4
if shard_region lite-tier-0132; then

lt_spec() { # lt_spec <tier-line-or-empty> <n-owns> [below] -> a closed, declaring spec text
  local tier="$1" n="$2" where="${3:-above}" i owns=""
  for ((i=1; i<=n; i++)); do owns="${owns}Owns: src/f$i.txt
"; done
  if [[ "$where" == "below" ]]; then
    printf '# Spec 0001\n\nStatus: CLOSED\n%s\n## Closing report\n\n%s\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' "$owns" "$tier"
  else
    printf '# Spec 0001\n\nStatus: CLOSED\n%s%s\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' "${tier:+$tier
}" "$owns"
  fi
}
lt_close_on_trunk() { # lt_close_on_trunk <dir> <spec-text> : a single-parent close committed on main with the hooks bypassed
  local d="$1"
  printf '%s' "$2" > "$d/specs/0001-thing.md"
  printf 'declared\n' > "$d/src/f1.txt"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$d/.claude/status.json"
  sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
}
# (a) the audit's single-parent arm refuses six under the tier
LT1="$WORK/lt-six"; rp1_fixture "$LT1"; lt_close_on_trunk "$LT1" "$(lt_spec 'Tier: lite' 6)"
LT1_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT1" 2>&1)" || true
if printf '%s' "$LT1_OUT" | grep -q '\[SLH-LITE-OVERSIZED\] spec 0001 is declared Tier: lite and declares more than five files' && ! printf '%s' "$LT1_OUT" | grep -q ' 0 violations'; then
  ok "lite a: a Tier: lite spec declaring six files is refused SLH-LITE-OVERSIZED at the audit's single-parent arm"
else
  bad "lite a: a Tier: lite spec declaring six files is refused SLH-LITE-OVERSIZED at the audit's single-parent arm" "audit said: $(printf '%s' "$LT1_OUT" | grep -i 'lite\|violation' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
if printf '%s' "$LT1_OUT" | grep -F '[SLH-LITE-OVERSIZED]' | grep -q 'drop the tier line' && printf '%s' "$LT1_OUT" | grep -F '[SLH-LITE-OVERSIZED]' | grep -q 'split the work'; then
  ok "lite a: the refusal names both honest exits (drop the tier line; split the work)"
else
  bad "lite a: the refusal names both honest exits (drop the tier line; split the work)" "$(printf '%s' "$LT1_OUT" | grep LITE | cut -c1-200)"
fi
# (b) five under the tier is clean
LT2="$WORK/lt-five"; rp1_fixture "$LT2"; lt_close_on_trunk "$LT2" "$(lt_spec 'Tier: lite' 5)"
LT2_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT2" 2>&1)" || true
if printf '%s' "$LT2_OUT" | grep -q ' 0 violations'; then
  ok "lite b: a Tier: lite spec declaring five files closes clean (the cap is at most five)"
else
  bad "lite b: a Tier: lite spec declaring five files closes clean (the cap is at most five)" "audit said: $(printf '%s' "$LT2_OUT" | tail -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (c) six with NO tier line is clean: the cap is the tier's, and absence reads as v1.13
LT3="$WORK/lt-notier"; rp1_fixture "$LT3"; lt_close_on_trunk "$LT3" "$(lt_spec '' 6)"
LT3_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT3" 2>&1)" || true
if printf '%s' "$LT3_OUT" | grep -q ' 0 violations' && ! printf '%s' "$LT3_OUT" | grep -q 'LITE'; then
  ok "lite c (absence): six declared files with no tier line close clean, exactly as before the tier existed"
else
  bad "lite c (absence): six declared files with no tier line close clean, exactly as before the tier existed" "audit said: $(printf '%s' "$LT3_OUT" | tail -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (d) `Tier: full` with six is clean; (e) a `Tier: lite` line BELOW the Closing report heading is outside the range and not read
LT4="$WORK/lt-full"; rp1_fixture "$LT4"; lt_close_on_trunk "$LT4" "$(lt_spec 'Tier: full' 6)"
LT4_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT4" 2>&1)" || true
LT5="$WORK/lt-below"; rp1_fixture "$LT5"; lt_close_on_trunk "$LT5" "$(lt_spec 'Tier: lite' 6 below)"
LT5_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT5" 2>&1)" || true
if printf '%s' "$LT4_OUT" | grep -q ' 0 violations' && printf '%s' "$LT5_OUT" | grep -q ' 0 violations'; then
  ok "lite d and e: 'Tier: full' with six files, and 'Tier: lite' below the Closing report heading, are both full specs (only the exact line inside the hashed range is read)"
else
  bad "lite d and e: 'Tier: full' with six files, and 'Tier: lite' below the Closing report heading, are both full specs (only the exact line inside the hashed range is read)" "full: $(printf '%s' "$LT4_OUT" | tail -1 | cut -c1-100); below: $(printf '%s' "$LT5_OUT" | tail -1 | cut -c1-100)"
fi
# (f) the squash landing at pre-commit refuses; (j) five is allowed there
lt_branch_close() { # lt_branch_close <dir> <spec-text> : the close on spec/0001-thing, hooks bypassed; main checked out after
  local d="$1"
  git -C "$d" checkout -qb spec/0001-thing 2>/dev/null
  printf '%s' "$2" > "$d/specs/0001-thing.md"
  printf 'declared\n' > "$d/src/f1.txt"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$d/.claude/status.json"
  sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
  git -C "$d" checkout -q main 2>/dev/null
}
LT6="$WORK/lt-squash"; rp1_fixture "$LT6"; lt_branch_close "$LT6" "$(lt_spec 'Tier: lite' 6)"
git -C "$LT6" merge --squash spec/0001-thing >/dev/null 2>&1
if git -C "$LT6" commit -qm "squash close" >"$WORK/lt-squash.out" 2>&1; then
  bad "lite f: the squash landing of a six-file lite spec is refused at pre-commit" "the landing succeeded"
elif grep -q 'SLH-LITE-OVERSIZED' "$WORK/lt-squash.out"; then
  ok "lite f: the squash landing of a six-file lite spec is refused at pre-commit"
else
  bad "lite f: the squash landing of a six-file lite spec is refused at pre-commit" "refused for another reason: $(tr '\n' ' ' < "$WORK/lt-squash.out" | cut -c1-200)"
fi
LT7="$WORK/lt-squash5"; rp1_fixture "$LT7"; lt_branch_close "$LT7" "$(lt_spec 'Tier: lite' 5)"
git -C "$LT7" merge --squash spec/0001-thing >/dev/null 2>&1
if git -C "$LT7" commit -qm "squash close" >"$WORK/lt-squash5.out" 2>&1; then
  ok "lite j: the squash landing of a five-file lite spec is allowed at pre-commit"
else
  bad "lite j: the squash landing of a five-file lite spec is allowed at pre-commit" "$(tr '\n' ' ' < "$WORK/lt-squash5.out" | cut -c1-200)"
fi
# (g) the --no-ff merge at pre-merge-commit refuses: the tier is a claim about the spec, not the route
LT8="$WORK/lt-merge"; rp1_fixture "$LT8"; lt_branch_close "$LT8" "$(lt_spec 'Tier: lite' 6)"
if ( cd "$LT8" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "merge 0001" spec/0001-thing ) >"$WORK/lt-merge.out" 2>&1; then
  bad "lite g: the --no-ff merge of a six-file lite spec is refused at pre-merge-commit" "the merge landed"
elif grep -q 'SLH-LITE-OVERSIZED' "$WORK/lt-merge.out"; then
  ok "lite g: the --no-ff merge of a six-file lite spec is refused at pre-merge-commit"
else
  bad "lite g: the --no-ff merge of a six-file lite spec is refused at pre-merge-commit" "refused for another reason: $(tr '\n' ' ' < "$WORK/lt-merge.out" | cut -c1-200)"
fi
# (h) the audit's merge arm refuses the same landing when the hooks were bypassed
LT9="$WORK/lt-merge-audit"; rp1_fixture "$LT9"; lt_branch_close "$LT9" "$(lt_spec 'Tier: lite' 6)"
( cd "$LT9" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git -c core.hooksPath=/dev/null merge --no-ff -m "merge 0001" spec/0001-thing ) >/dev/null 2>&1
LT9_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$LT9" 2>&1)" || true
if printf '%s' "$LT9_OUT" | grep -q '\[SLH-LITE-OVERSIZED\] spec 0001' && ! printf '%s' "$LT9_OUT" | grep -q ' 0 violations'; then
  ok "lite h: a six-file lite spec landed by merge with the hooks bypassed is refused at the audit's merge arm"
else
  bad "lite h: a six-file lite spec landed by merge with the hooks bypassed is refused at the audit's merge arm" "audit said: $(printf '%s' "$LT9_OUT" | grep -i 'lite\|violation' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi
# (i) the forge check refuses at step 4 through the same library site
LT10="$WORK/lt-forge"; fc_fixture "$LT10" off
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$LT10/.claude/status.json"
git -C "$LT10" add -A >/dev/null; git -C "$LT10" -c core.hooksPath=/dev/null commit -qm "the record" >/dev/null 2>&1
git -C "$LT10" checkout -q -b spec/0001-thing
printf '%s' "$(lt_spec 'Tier: lite' 6)" > "$LT10/specs/0001-thing.md"
printf 'declared\n' > "$LT10/src/f1.txt"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | shipped |\n' > "$LT10/specs/STATUS.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$LT10/.claude/status.json"
git -C "$LT10" add -A >/dev/null; git -C "$LT10" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
git -C "$LT10" checkout -q main
fc_run "$LT10" --base main --head spec/0001-thing --forge none
fc_case "lite i: the forge check refuses a six-file lite spec at its close verification" 1 "CLOSE-REFUSED" SLH-LITE-OVERSIZED
# The edition and the derived surfaces (rule 6) say the same thing.
if grep -q 'at most five files under `Owns:`' "$ROOT/setlist.md" && grep -q '^| a spec declared `Tier: lite`.*`SLH-LITE-OVERSIZED` |' "$ROOT/setlist.md" \
   && grep -q '^Tier: full ' "$ROOT/setlist.md" && grep -q 'SLH-LITE-OVERSIZED' "$ROOT/skills/checkpoint/SKILL.md" && grep -q 'Tier: lite' "$ROOT/skills/spec-authoring/SKILL.md"; then
  ok "lite edition: Part 3 states the five-file threshold, Part 6's table carries the code, Appendix C's template carries the Tier line, and the checkpoint and spec-authoring skills know the tier"
else
  bad "lite edition: Part 3 states the five-file threshold, Part 6's table carries the code, Appendix C's template carries the Tier line, and the checkpoint and spec-authoring skills know the tier" "one of the five surfaces is silent"
fi
# The stamped template carries the line, so a new instance's specs state their tier from birth.
LTS="$WORK/lt-stamp"; rm -rf "$LTS"; mkdir -p "$LTS"; git -C "$LTS" init -q >/dev/null 2>&1; git -C "$LTS" commit -q --allow-empty -m seed >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$LTS" >/dev/null 2>&1
if grep -q '^Tier: full ' "$LTS/specs/TEMPLATE.md"; then
  ok "lite template: the stamped specs/TEMPLATE.md carries the Tier line (Appendix C by construction)"
else
  bad "lite template: the stamped specs/TEMPLATE.md carries the Tier line (Appendix C by construction)" "absent from the stamped template"
fi

fi; shard_region_end
# <<< SHARD-END lite-tier-0132

