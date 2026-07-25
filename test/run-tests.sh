#!/usr/bin/env bash
# Setlist hook test suite. Dependency-free beyond bash 3.2+, git, jq, and
# coreutils; no bats, no python. Builds every fixture programmatically under
# mktemp, runs the four stamped hooks against simulated PreToolUse and
# SessionStart payloads, and asserts BOTH contracts on every deny: the machine
# contract (stdout parses as JSON, permissionDecision is deny, rc 0) and the
# human contract (the reason names the specific failure).
#
# Usage: bash test/run-tests.sh          (from any cwd)
#
# Why this exists: the hooks previously carried "verified live on Claude Code
# X.Y.Z" comments and nothing else. The hook contract has changed repeatedly;
# without a suite the next change produces a silently dead gate in every
# stamped instance instead of a red run here.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$ROOT/templates/hooks"

PASS=0
FAIL=0
# Canonicalized deliberately: macOS sets TMPDIR with a trailing slash, which
# produces fixture paths containing `//`. Those belong in explicit test cases
# (see the path-spelling block), not silently in every other fixture's path.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/setlist-tests.XXXXXX")" && pwd)"

# The verdict is enforced on EXIT, not only by the summary block at the end.
# A case added AFTER that block records its failure into FAIL and then the
# script ends with the status of whatever ran last, so the failure is silent
# and the suite reports success. That is the Phase 0 finding in the review
# methodology, "a suite that reports failures but exits 0 is itself a
# finding", and it was reproduced here by accident while attacking the
# publish gate: a probe appended to the end of this file failed and the suite
# still exited 0. Binding the verdict to EXIT makes the position of a case in
# the file irrelevant.
on_exit() {
  local rc=$?
  rm -rf "$WORK"
  [[ "${FAIL:-0}" -eq 0 ]] || exit 1
  exit "$rc"
}
trap on_exit EXIT

# The em-dash is never typed literally in this repo (rule 1) and never built
# with \x escapes, which are not POSIX and silently produce the literal text
# under dash (C6). Octal only.
EMDASH="$(printf '\342\200\224')"

# --- reporting ---------------------------------------------------------------

ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n       %s\n' "$1" "$2"; }

# --- fixtures ----------------------------------------------------------------

git_init() { # git_init <dir> [trunk]
  local d="$1" trunk="${2:-main}"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD "refs/heads/$trunk"
  git -C "$d" config user.email "tests@example.invalid"
  git -C "$d" config user.name "Setlist Tests"
  git -C "$d" config commit.gpgsign false
  # An initial commit is mandatory: on an unborn HEAD `git diff --cached`
  # behaves differently and produces false ALLOWs that look like gate bugs.
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add seed.txt
  git -C "$d" commit -qm "seed"
}

sdd_json() { # sdd_json <dir> [scaffolded] [trunk] [gate_command]
  local d="$1" scaffolded="${2:-true}" trunk="${3:-main}" gate="${4:-true}"
  mkdir -p "$d/.claude"
  cat > "$d/.claude/sdd.json" <<EOF
{
  "scaffolded": $scaffolded,
  "trunk": "$trunk",
  "gate_command": "$gate",
  "roles": { "src": "src", "tests": "tests" }
}
EOF
}

# A PreToolUse payload for the Bash matcher. jq builds it so quoting in the
# command survives exactly as the harness would deliver it.
bash_payload() { # bash_payload <command>
  jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'
}

edit_payload() { # edit_payload <file_path>
  jq -nc --arg p "$1" '{tool_name:"Edit", tool_input:{file_path:$p}}'
}

session_payload() { # session_payload <source>
  jq -nc --arg s "$1" '{hook_event_name:"SessionStart", source:$s}'
}

# --- running hooks -----------------------------------------------------------

HOOK_OUT=""
HOOK_RC=0

run_hook() { # run_hook <hook-file> <project-dir> <payload>
  HOOK_OUT="$(printf '%s' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$1" 2>/dev/null)"
  HOOK_RC=$?
}

# Same, with jq removed from PATH. A scratch bin holding symlinks to the tools
# the hooks legitimately use is more portable than uninstalling jq.
NOJQ_BIN="$WORK/nojq-bin"
build_nojq_bin() {
  mkdir -p "$NOJQ_BIN"
  local t p
  for t in bash sh git grep sed awk cat head tail od tr wc cut sort uniq \
           printf env dirname basename mkdir rm cp mv ls chmod date mktemp; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$NOJQ_BIN/$t"
  done
  if [[ -e "$NOJQ_BIN/jq" ]]; then
    printf 'harness error: jq leaked into the no-jq PATH\n' >&2
    exit 2
  fi
}

run_hook_nojq() { # run_hook_nojq <hook-file> <project-dir> <payload>
  HOOK_OUT="$(printf '%s' "$3" | PATH="$NOJQ_BIN" CLAUDE_PROJECT_DIR="$2" bash "$1" 2>/dev/null)"
  HOOK_RC=$?
}

# --- assertions --------------------------------------------------------------

expect_deny() { # expect_deny <name> <substring>
  local name="$1" want="$2" decision reason
  if [[ "$HOOK_RC" -ne 0 ]]; then
    bad "$name" "expected rc 0 (deny is delivered in JSON, not an exit code), got $HOOK_RC"
    return
  fi
  if ! printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; then
    bad "$name" "stdout is not valid JSON: ${HOOK_OUT:-<empty>}"
    return
  fi
  decision="$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
  if [[ "$decision" != "deny" ]]; then
    bad "$name" "expected permissionDecision deny, got '${decision:-<none>}'"
    return
  fi
  reason="$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')"
  case "$reason" in
    *"$want"*) ok "$name" ;;
    *) bad "$name" "deny reason does not mention '$want': $reason" ;;
  esac
}

expect_allow() { # expect_allow <name>
  if [[ "$HOOK_RC" -ne 0 ]]; then
    bad "$1" "expected rc 0, got $HOOK_RC"
  elif [[ -n "$HOOK_OUT" ]]; then
    bad "$1" "expected no stdout (allow is silence), got: $HOOK_OUT"
  else
    ok "$1"
  fi
}

expect_context() { # expect_context <name> <substring>
  local name="$1" want="$2" ctx
  if ! printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; then
    bad "$name" "stdout is not valid JSON: ${HOOK_OUT:-<empty>}"
    return
  fi
  ctx="$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // empty')"
  case "$ctx" in
    *"$want"*) ok "$name" ;;
    *) bad "$name" "additionalContext does not mention '$want': $ctx" ;;
  esac
}

printf 'Setlist hook suite\nroot: %s\n\n' "$ROOT"
build_nojq_bin

# =============================================================================
# commit-gate.sh
# =============================================================================

CG="$WORK/commit-gate"
git_init "$CG"
sdd_json "$CG"

# a. compound stage-and-commit
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git add -A && git commit -m "docs"')"
expect_deny "commit-gate a: compound git add plus git commit is denied" "one step"

# b. auto-staging flag
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -am "docs"')"
expect_deny "commit-gate b: git commit -am is denied" "auto-staging"

# c. staged em-dash. The fixture verifies its own bytes first, so the C6 trap
# (hex escapes producing literal text under dash) can never hollow this out.
printf 'a line with an %s in it\n' "$EMDASH" > "$CG/prose.md"
if od -An -to1 "$CG/prose.md" | tr -s ' \n' ' ' | grep -q '342 200 224'; then
  ok "commit-gate c0: fixture really contains the em-dash byte sequence"
else
  bad "commit-gate c0: fixture really contains the em-dash byte sequence" \
      "od found no 342 200 224 in the fixture; the rest of case c proves nothing"
fi
git -C "$CG" add prose.md
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "prose"')"
expect_deny "commit-gate c: staged em-dash is denied" "em-dash"
git -C "$CG" reset -q

# d. staged secret
printf 'api_key = "sk_live_51H8xQ2eZvKYlo2C"\n' > "$CG/config.txt"
git -C "$CG" add config.txt
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "config"')"
expect_deny "commit-gate d: staged secret-shaped string is denied" "secret-shaped"
git -C "$CG" reset -q
rm -f "$CG/config.txt" "$CG/prose.md"

# e. clean staged commit
printf 'clean content, nothing to find\n' > "$CG/clean.md"
git -C "$CG" add clean.md
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "clean"')"
expect_allow "commit-gate e: a clean staged commit is allowed"

# f. quote-stripping regression guard: "git add" inside the message only
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "explain why git add runs first"')"
expect_allow "commit-gate f: the words git add inside a quoted message are allowed"
git -C "$CG" commit -qm "clean"

# g. spec lifecycle transition without specs/STATUS.md staged
mkdir -p "$CG/specs"
cat > "$CG/specs/0001-thing.md" <<'EOF'
# Spec 0001 - thing
Status: CLOSED
EOF
cat > "$CG/specs/STATUS.md" <<'EOF'
| 0001 | Thing | ACTIVE | in flight |
EOF
git -C "$CG" add specs/0001-thing.md
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "close 0001"')"
expect_deny "commit-gate g: a lifecycle change without STATUS.md is denied" "STATUS.md"
git -C "$CG" add specs/STATUS.md
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "close 0001"')"
expect_allow "commit-gate g2: the same change with STATUS.md staged is allowed"
git -C "$CG" reset -q

# h. KNOWN HOLE, documented rather than hidden: `git commit <pathspec>` commits
# the working-tree copy without staging, so a staged-content scan sees nothing.
# Named in the README's Known limitations section; asserted here so the day it
# closes, this test fails and tells us.
printf 'working tree %s not staged\n' "$EMDASH" > "$CG/hole.md"
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "msg" hole.md')"
expect_allow "commit-gate h: KNOWN-HOLE, pathspec commit bypasses the staged scan"
rm -f "$CG/hole.md"

# =============================================================================
# close-gate.sh
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
  git -C "$d" checkout -q -b spec/0001-thing
  mkdir -p "$d/specs"

  {
    printf '# Spec 0001 - thing\n\nStatus: CLOSED\n\n'
    if [[ "$closing" == "yes" ]]; then
      printf '## Closing report\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      [[ "$qa" == "crossref" ]] && printf 'Note: the visual criteria are deferred to QA Pass 2.\n\n'
      [[ "$qa" == "yes" || "$qa" == "crossref" ]] && printf 'criterion 1: PASS\n\n'
      printf -- '- QA Pass 2 (human): done\n\n'
      [[ "$qa" == "stray" ]] && printf -- '- Follow-ups filed: none; the regression suite came back PASS\n\n'
      if [[ "$diag" == "answered" ]]; then
        printf -- '- Architecture diagram: no impact\n'
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
}

MERGE_CMD='git merge --no-ff spec/0001-thing'

# j. no Closing report
CL="$WORK/close-j"; close_fixture "$CL" no no answered yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate j: a branch with no Closing report is denied" "Closing report"

# k. Closing report, no QA verdict
CL="$WORK/close-k"; close_fixture "$CL" yes no answered yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate k: a Closing report with no QA verdict is denied" "QA Pass 1"

# l. unanswered architecture-diagram field
CL="$WORK/close-l"; close_fixture "$CL" yes yes unanswered yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate l: an unanswered architecture-diagram field is denied" "architecture-diagram"

# m. no CLOSED inventory row
CL="$WORK/close-m"; close_fixture "$CL" yes yes answered no no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate m: a missing CLOSED inventory row is denied" "CLOSED"

# n. compound checkout-then-merge from another branch: the target is derived
# from the command text, not the current branch.
CL="$WORK/close-n"; close_fixture "$CL" no no answered yes no true
git -C "$CL" checkout -q spec/0001-thing
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git checkout main && git merge --no-ff spec/0001-thing')"
expect_deny "close-gate n: the compound checkout-then-merge form is gated" "Closing report"

# q. duplicate spec numbers
CL="$WORK/close-q"; close_fixture "$CL" yes yes answered yes yes true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate q: duplicate spec numbers on the branch are denied" "unique"

# p. gate command fails
CL="$WORK/close-p"; close_fixture "$CL" yes yes answered yes no false
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate p: a failing gate command is denied" "gate command"

# o. fully compliant merge
CL="$WORK/close-o"; close_fixture "$CL" yes yes answered yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate o: a fully compliant merge is allowed"

# The QA Pass 1 block is delimited by the Appendix C FIELD MARKERS, not by the
# bare substring "QA Pass 2" anywhere in a line. The bare test ended the block
# at the first line of QA-1 prose that cross-referenced QA Pass 2, dropping the
# verdict out of the block and denying a compliant merge in the field (0112).
CL="$WORK/close-crossref"; close_fixture "$CL" yes crossref answered yes no true
CROSSREF_SPEC="$(git -C "$CL" show spec/0001-thing:specs/0001-thing.md)"
XREF_LINE="$(printf '%s\n' "$CROSSREF_SPEC" | grep -n 'deferred to QA Pass 2' | head -n1 | cut -d: -f1)"
VERDICT_LINE="$(printf '%s\n' "$CROSSREF_SPEC" | grep -n 'criterion 1: PASS' | head -n1 | cut -d: -f1)"
MARKER_LINE="$(printf '%s\n' "$CROSSREF_SPEC" | grep -n '^[-*+[:space:]]*QA Pass 2' | head -n1 | cut -d: -f1)"
if [[ -n "$XREF_LINE" && -n "$VERDICT_LINE" && -n "$MARKER_LINE" \
      && "$XREF_LINE" -lt "$VERDICT_LINE" && "$VERDICT_LINE" -lt "$MARKER_LINE" ]]; then
  ok "close-gate crossref0: the fixture really cross-references QA Pass 2 above the verdict"
else
  bad "close-gate crossref0: the fixture really cross-references QA Pass 2 above the verdict" \
      "prose line '$XREF_LINE', verdict line '$VERDICT_LINE', field marker line '$MARKER_LINE'; the case below proves nothing unless prose precedes verdict precedes marker"
fi
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate crossref: QA-1 prose mentioning QA Pass 2 no longer truncates the verdict"

# The other direction of the same fix: the end anchor must still terminate the
# block, so a verdict-shaped word AFTER the QA Pass 2 field cannot satisfy a
# Closing report whose QA-1 block is genuinely empty.
CL="$WORK/close-stray"; close_fixture "$CL" yes stray answered yes no true
STRAY_SPEC="$(git -C "$CL" show spec/0001-thing:specs/0001-thing.md)"
STRAY_LINE="$(printf '%s\n' "$STRAY_SPEC" | grep -n 'regression suite came back PASS' | head -n1 | cut -d: -f1)"
MARKER_LINE="$(printf '%s\n' "$STRAY_SPEC" | grep -n '^[-*+[:space:]]*QA Pass 2' | head -n1 | cut -d: -f1)"
if [[ -n "$STRAY_LINE" && -n "$MARKER_LINE" && "$MARKER_LINE" -lt "$STRAY_LINE" ]]; then
  ok "close-gate stray0: the fixture really places a PASS below the QA Pass 2 field marker"
else
  bad "close-gate stray0: the fixture really places a PASS below the QA Pass 2 field marker" \
      "field marker line '$MARKER_LINE', stray PASS line '$STRAY_LINE'"
fi
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate stray: a PASS below the QA Pass 2 field does not satisfy an empty QA-1 block" "QA Pass 1"

# =============================================================================
# Command spelling must not decide enforcement
#
# Both Bash gates used to decide whether they applied with a literal substring
# test ("git commit", "git merge"). Every spelling below names the same
# operation and every one of them walked straight past the gate in silence.
# =============================================================================

SP="$WORK/spelling-commit"
git_init "$SP"
sdd_json "$SP"
printf 'staged prose with an %s in it\n' "$EMDASH" > "$SP/prose.md"
git -C "$SP" add prose.md

spell_deny() { # spell_deny <label> <command> <substring>
  run_hook "$HOOKS/commit-gate.sh" "$SP" "$(bash_payload "$2")"
  expect_deny "spelling (commit): $1" "$3"
}
spell_deny "two spaces between git and commit" 'git  commit -m x' "em-dash"
spell_deny "a -C global option before commit"  'git -C . commit -m x' "em-dash"
spell_deny "a --no-pager global option"        'git --no-pager commit -m x' "em-dash"
spell_deny "a -c key=value global option"      'git -c user.name=z commit -m x' "em-dash"
spell_deny "an absolute path to the binary"    '/usr/bin/git commit -m x' "em-dash"

# The other direction matters just as much: a gate that denies everything
# mentioning the word is a gate people rip out.
run_hook "$HOOKS/commit-gate.sh" "$SP" "$(bash_payload 'git log --oneline')"
expect_allow "spelling (commit): a git command that is not a commit is untouched"
run_hook "$HOOKS/commit-gate.sh" "$SP" "$(bash_payload 'npm run build')"
expect_allow "spelling (commit): an unrelated command is untouched"

CL="$WORK/spelling-merge"; close_fixture "$CL" no no answered yes no true
spell_merge_deny() { # spell_merge_deny <label> <command>
  run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$2")"
  expect_deny "spelling (merge): $1" "Closing report"
}
spell_merge_deny "a double-quoted branch name"  'git merge --no-ff "spec/0001-thing"'
spell_merge_deny "a single-quoted branch name"  "git merge --no-ff 'spec/0001-thing'"
spell_merge_deny "two spaces before merge"      'git  merge --no-ff spec/0001-thing'
spell_merge_deny "a -C global option"           'git -C . merge --no-ff spec/0001-thing'
spell_merge_deny "a fully qualified ref"        'git merge --no-ff refs/heads/spec/0001-thing'
spell_merge_deny "a remote-tracking ref"        'git merge --no-ff origin/spec/0001-thing'
spell_merge_deny "quoting inside the compound form" 'git checkout main && git merge --no-ff "spec/0001-thing"'

# DISPOSITION CHANGED IN 1.0.3 (IN-1). This case used to assert that a merge
# naming a non-spec branch passed untouched, on the reasoning that the gate
# only governs spec and chore closes. That reasoning was the loophole: only
# spec/ and chore/ branches enter the trunk through the ceremony, so a merge
# into the trunk naming anything else is either a mistake or a way around the
# gate, and "some-other-branch" is indistinguishable from a shell variable
# that expanded to one. The gate now denies it, and the neighbouring cases
# above pin the boundary: merges into a NON-trunk target stay ungated, and
# --continue/--abort stay exempt.
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge --no-ff some-other-branch')"
expect_deny "spelling (merge): a trunk merge naming a non-spec branch is denied" "literally"
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git status')"
expect_allow "spelling (merge): a non-merge git command is untouched"

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
# i. jq absent: the three gates fail closed, the pointer still ships
# =============================================================================

run_hook_nojq "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "clean"')"
expect_deny "no-jq i1: the commit gate fails closed" "jq"

CL="$WORK/close-o"
run_hook_nojq "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "no-jq i2: the close gate fails closed even on a compliant merge" "jq"

run_hook_nojq "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/specs/0001-thing.md")"
expect_deny "no-jq i3: the scope hook fails closed" "jq"

# The Bash blast radius stays narrow: without jq the commit gate cannot tell a
# commit from anything else, so it must not deny every Bash call. The session
# has to stay able to run the install command that fixes the condition.
run_hook_nojq "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'apt-get install -y jq')"
expect_allow "no-jq i4: unrelated Bash commands still run, so jq can be installed"

run_hook_nojq "$HOOKS/regrounding-hook.sh" "$RG" "$(session_payload startup)"
expect_context "no-jq i5: the pointer still ships and names the condition" "jq is not installed"

# =============================================================================
# x. no .claude/sdd.json: every hook stays silent
# =============================================================================

BARE="$WORK/bare"
git_init "$BARE"
run_hook "$HOOKS/scope-hook.sh" "$BARE" "$(edit_payload "$BARE/src/app.js")"
expect_allow "no-sdd x1: the scope hook stays silent outside an instance"
run_hook "$HOOKS/regrounding-hook.sh" "$BARE" "$(session_payload startup)"
expect_allow "no-sdd x2: the regrounding hook stays silent outside an instance"
run_hook "$HOOKS/close-gate.sh" "$BARE" "$(bash_payload "$MERGE_CMD")"
expect_allow "no-sdd x3: the close gate stays silent outside an instance"
run_hook "$HOOKS/commit-gate.sh" "$BARE" "$(bash_payload 'ls -la')"
expect_allow "no-sdd x4: the commit gate ignores non-commit commands"

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
  for h in scope-hook commit-gate close-gate regrounding-hook; do
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

# =============================================================================
# Plugin version, refresh direction, and session skew (plugin 1.0.2, item 21)
#
# The failure this whole section exists for: a refresh that compares bytes
# without direction can reinstall older enforcement files over newer ones and
# report success. Every refusal below is asserted to have refused AND to have
# left the instance's bytes alone, because a refusal that copied anyway is the
# same defect wearing a warning label.
# =============================================================================

SCRIPTS="$ROOT/scripts"
SCRIPT_OUT=""
SCRIPT_RC=0

run_script() { # run_script <cmd> [args...]
  SCRIPT_OUT="$("$@" 2>&1)"
  SCRIPT_RC=$?
}

run_script_nojq() { # run_script_nojq <cmd> [args...]
  SCRIPT_OUT="$(PATH="$NOJQ_BIN" "$@" 2>&1)"
  SCRIPT_RC=$?
}

expect_script() { # expect_script <name> <want-rc> [substring...]
  local name="$1" want="$2" s
  shift 2
  if [[ "$SCRIPT_RC" -ne "$want" ]]; then
    bad "$name" "expected rc $want, got $SCRIPT_RC. Output: ${SCRIPT_OUT:-<empty>}"
    return
  fi
  for s in "$@"; do
    case "$SCRIPT_OUT" in
      *"$s"*) ;;
      *) bad "$name" "output does not mention '$s': ${SCRIPT_OUT:-<empty>}"; return ;;
    esac
  done
  ok "$name"
}

assert_true() { # assert_true <name> <message-if-false> <cmd> [args...]
  local name="$1" msg="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "$msg"; fi
}

PLUGIN_VERSION="$(bash "$SCRIPTS/plugin-version.sh" "$ROOT" 2>/dev/null || true)"
if [[ -n "$PLUGIN_VERSION" ]]; then
  ok "version 0: this plugin tree declares a readable version ($PLUGIN_VERSION)"
else
  bad "version 0: this plugin tree declares a readable version" \
      "plugin-version.sh could not read one, so every case in this section would be comparing against nothing"
fi

# The ordering is the whole point of the file; a comparison that answers "same"
# for everything would let every case below pass while proving nothing.
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.2 1.0.1
expect_script "version a: 1.0.2 is newer than 1.0.1" 0 "newer"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.1 1.0.2
expect_script "version b: 1.0.1 is older than 1.0.2" 0 "older"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.1 1.0.1
expect_script "version c: equal versions compare same" 0 "same"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.2.0 1.10.0
expect_script "version d: components compare numerically, not as text" 0 "older"
run_script bash "$SCRIPTS/plugin-version.sh" --compare "" 1.0.1
expect_script "version e: an unreadable version refuses rather than guessing" 1 "not a version"

# --- the stamp records the stamping version ------------------------------------

STAMP_RECORDED="$(jq -r '.plugin.version // empty' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null || true)"
if [[ "$STAMP_RECORDED" == "$PLUGIN_VERSION" && -n "$PLUGIN_VERSION" ]]; then
  ok "stamp version: the stamped instance records the stamping plugin version ($STAMP_RECORDED)"
else
  bad "stamp version: the stamped instance records the stamping plugin version" \
      "sdd.json records '${STAMP_RECORDED:-<none>}', the manifest declares '${PLUGIN_VERSION:-<none>}'"
fi
if [[ "$STAMP_RECORDED" != *"{{"* ]]; then
  ok "stamp version 2: the recorded version is a real value, not an unsubstituted placeholder"
else
  bad "stamp version 2: the recorded version is a real value, not an unsubstituted placeholder" \
      "sdd.json still carries the template placeholder: $STAMP_RECORDED"
fi

# --- refresh fixtures -----------------------------------------------------------

# A minimal instance: the four stamped hooks plus sdd.json. close-gate.sh
# carries a marker line, so "did the refresh copy anything?" is decidable by
# looking rather than by trusting the exit code.
MARKER="# instance marker, must survive every refusal"
instance_fixture() { # instance_fixture <dir> <recorded-version|none|broken> [wiring]
  # wiring: current (default) | stale-matcher | no-timeouts | missing
  local d="$1" rec="$2" wiring="${3:-current}" h
  rm -rf "$d"
  mkdir -p "$d/.claude/hooks"
  for h in scope-hook commit-gate close-gate regrounding-hook; do
    cp "$HOOKS/$h.sh" "$d/.claude/hooks/$h.sh"
  done
  printf '%s\n' "$MARKER" >> "$d/.claude/hooks/close-gate.sh"
  case "$rec" in
    broken) printf '{ "trunk": "main", \n' > "$d/.claude/sdd.json" ;;
    none)   printf '{ "trunk": "main", "gate_command": "", "scaffolded": false }\n' > "$d/.claude/sdd.json" ;;
    *)      printf '{ "trunk": "main", "gate_command": "", "scaffolded": false, "plugin": { "version": "%s" } }\n' \
              "$rec" > "$d/.claude/sdd.json" ;;
  esac
  # The settings wiring is the OTHER half of the enforcement layer, and the
  # refresh checks it without rewriting it (1.0.3). Fixtures default to the
  # current wiring so the direction cases below stay about direction.
  local matcher='Write|Edit|MultiEdit|NotebookEdit' t1='"timeout": 120,' t2='"timeout": 300,' t3='"timeout": 1800,'
  case "$wiring" in
    stale-matcher) matcher='Write|Edit' ;;
    no-timeouts)   t1='' ; t2='' ; t3='' ;;
    missing)       return 0 ;;
  esac
  # The command paths must be the REAL ones. The wiring check identifies this
  # plugin's own hook entries by their command pointing into .claude/hooks/,
  # so a fixture using a made-up path is not an instance: it is a settings file
  # with no Setlist hooks in it, and every check would vacuously pass. Found by
  # the 1.0.4 rewrite, and it is the same lesson the upgrade-seam leg exists
  # for: a fixture is only evidence to the extent it matches the real artifact.
  cat > "$d/.claude/settings.json" <<SETTINGS
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "$matcher",
        "hooks": [ { "type": "command", $t1 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/scope-hook.sh" } ] },
      { "matcher": "Bash",
        "hooks": [ { "type": "command", $t2 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/commit-gate.sh" },
                   { "type": "command", $t3 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/close-gate.sh" } ] }
    ]
  }
}
SETTINGS
}

marker_intact() { # marker_intact <dir>
  grep -q "^$MARKER\$" "$1/.claude/hooks/close-gate.sh"
}

# --- refusal: a backwards move --------------------------------------------------

INST="$WORK/inst-downgrade"
instance_fixture "$INST" 9.9.9
assert_true "refresh down0: the fixture really records a version newer than this plugin" \
  "the fixture does not record 9.9.9, so the downgrade case below is not a downgrade" \
  test "$(jq -r '.plugin.version' "$INST/.claude/sdd.json")" = "9.9.9"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh down: a backwards refresh is refused and names both versions" 1 \
  "BACKWARDS" "9.9.9" "$PLUGIN_VERSION"
assert_true "refresh down2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker, so the refusal overwrote the file it refused to touch" \
  marker_intact "$INST"

# --- refusal: an undeterminable recorded version --------------------------------

INST="$WORK/inst-unreadable"
instance_fixture "$INST" "banana"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh unreadable: an unreadable recorded version refuses" 1 "cannot read" "banana"
assert_true "refresh unreadable2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

INST="$WORK/inst-broken"
instance_fixture "$INST" broken
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh broken: sdd.json that does not parse refuses" 1 "does not parse"
assert_true "refresh broken2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

INST="$WORK/inst-nosdd"
instance_fixture "$INST" 1.0.0
rm -f "$INST/.claude/sdd.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh nosdd: an instance with no sdd.json refuses" 1 "no .claude/sdd.json"

# Without jq the recorded version cannot be read at all, which is precisely the
# state in which a downgrade is indistinguishable from an upgrade.
INST="$WORK/inst-nojq"
instance_fixture "$INST" 1.0.0
run_script_nojq bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh nojq: without jq the refresh refuses rather than copying blind" 1 "jq"
assert_true "refresh nojq2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

# --- forward moves are performed and recorded ------------------------------------

INST="$WORK/inst-legacy"
instance_fixture "$INST" none
assert_true "refresh legacy0: the fixture really records no plugin version" \
  "the fixture already records one, so this is not the pre-1.0.2 case" \
  test -z "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")"
run_script bash "$SCRIPTS/refresh-instance.sh" "$INST"
expect_script "refresh legacy: a report-only run names the differing file and changes nothing" 0 \
  "close-gate.sh" "Re-run with --apply"
assert_true "refresh legacy2: the report-only run copied nothing" \
  "report mode overwrote the instance's close-gate.sh" \
  marker_intact "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh legacy3: an instance recording no version is refreshed forward" 0 "forward"
if marker_intact "$INST"; then
  bad "refresh legacy4: --apply restores the hook bytes" \
      "close-gate.sh still carries the instance marker, so nothing was copied"
elif cmp -s "$HOOKS/close-gate.sh" "$INST/.claude/hooks/close-gate.sh"; then
  ok "refresh legacy4: --apply restores the hook bytes byte-verbatim"
else
  bad "refresh legacy4: --apply restores the hook bytes" "close-gate.sh differs from the template"
fi
if [[ "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")" == "$PLUGIN_VERSION" ]]; then
  ok "refresh legacy5: --apply records the plugin version in the instance"
else
  bad "refresh legacy5: --apply records the plugin version in the instance" \
      "sdd.json records '$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")', expected '$PLUGIN_VERSION'"
fi
if [[ "$(jq -r '.trunk // empty' "$INST/.claude/sdd.json")" == "main" ]]; then
  ok "refresh legacy6: recording the version preserves the rest of sdd.json"
else
  bad "refresh legacy6: recording the version preserves the rest of sdd.json" \
      "the trunk field did not survive the rewrite"
fi

# --- session skew ----------------------------------------------------------------

# The cache lays versions of the same plugin out side by side, which is the
# shape the field case had: two trees present, the session bound to the older.
fake_tree() { # fake_tree <dir> <version> [name]
  mkdir -p "$1/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "${3:-setlist}" "$2" > "$1/.claude-plugin/plugin.json"
}

CACHE="$WORK/cache/setlist/setlist"
fake_tree "$CACHE/1.0.1" 1.0.1
fake_tree "$CACHE/1.0.2" 1.0.2
assert_true "skew 0: the fixture cache really holds two trees of the same plugin" \
  "the two-version cache fixture was not built, so the skew cases below prove nothing" \
  test -f "$CACHE/1.0.1/.claude-plugin/plugin.json" -a -f "$CACHE/1.0.2/.claude-plugin/plugin.json"

run_script bash "$SCRIPTS/plugin-skew.sh" "$CACHE/1.0.1"
expect_script "skew a: a session on the older cached tree reports SKEW" 1 "SKEW" "1.0.1" "1.0.2"
run_script bash "$SCRIPTS/plugin-skew.sh" "$CACHE/1.0.2"
expect_script "skew b: a session on the newest cached tree reports no skew" 0 "no session skew"

# A neighbour that is a DIFFERENT plugin is not a newer version of this one.
# Pointed at a working checkout, the first cut of this compared unrelated
# repositories sitting beside it and announced a confident false SKEW.
OTHER="$WORK/cache/other"
fake_tree "$OTHER/setlist-solo" 1.0.3 setlist
fake_tree "$OTHER/unrelated" 9.9.9 some-other-plugin
run_script bash "$SCRIPTS/plugin-skew.sh" "$OTHER/setlist-solo"
expect_script "skew c: a differently named neighbouring plugin is not a newer version" 2 "Unverified, not clean"

# A tree with no manifest cannot be evaluated, and says so instead of passing.
mkdir -p "$WORK/not-a-plugin"
run_script bash "$SCRIPTS/plugin-skew.sh" "$WORK/not-a-plugin"
expect_script "skew d: an unreadable tree reports undeterminable, not clean" 2 "undeterminable"

# --- a stale session must not refresh at all --------------------------------------

# The field case end to end: the plugin tree the session is bound to is real and
# complete, a newer tree sits beside it in the cache, and the instance is
# willing. Refreshing here would install the OLD hook bytes and report an
# upgrade, which is the exact chore that was nearly closed in the field.
STALE="$WORK/cache/stale/setlist/1.0.1"
mkdir -p "$STALE"
cp -R "$ROOT/scripts" "$STALE/scripts"
cp -R "$ROOT/templates" "$STALE/templates"
fake_tree "$STALE" 1.0.1
fake_tree "$WORK/cache/stale/setlist/1.0.2" 1.0.2
assert_true "stale 0: the stale-session fixture really carries a runnable plugin tree" \
  "the copied tree is missing refresh-instance.sh, so the case below is not testing the field shape" \
  test -f "$STALE/scripts/refresh-instance.sh"

INST="$WORK/inst-stale"
instance_fixture "$INST" 1.0.0
run_script bash "$STALE/scripts/refresh-instance.sh" --apply "$INST"
expect_script "stale a: a session bound to a superseded plugin tree refuses to refresh" 1 \
  "SKEW" "Restart the session"
assert_true "stale a2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

# The same tree, with no newer neighbour, refreshes normally: the refusal above
# is caused by the skew and not by the fixture being unusable.
SOLO="$WORK/cache/solo/setlist/1.0.1"
mkdir -p "$SOLO"
cp -R "$ROOT/scripts" "$SOLO/scripts"
cp -R "$ROOT/templates" "$SOLO/templates"
fake_tree "$SOLO" 1.0.1
INST="$WORK/inst-solo"
instance_fixture "$INST" 1.0.0
run_script bash "$SOLO/scripts/refresh-instance.sh" --apply "$INST"
expect_script "stale b: the same plugin tree without a newer neighbour refreshes forward" 0 "forward"

# =============================================================================
# hygiene
# =============================================================================

# z. every shell file parses
SYNTAX_BAD=""
for f in "$ROOT"/templates/hooks/*.sh "$ROOT"/scripts/*.sh "$ROOT"/test/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" 2>/dev/null || SYNTAX_BAD="$SYNTAX_BAD ${f#$ROOT/}"
done
if [[ -z "$SYNTAX_BAD" ]]; then
  ok "hygiene z: bash -n passes on every shell file in templates, scripts, and test"
else
  bad "hygiene z: bash -n passes on every shell file in templates, scripts, and test" \
      "syntax errors in:$SYNTAX_BAD"
fi

# aa. no literal em-dash byte anywhere in the shipped surface. Scoped to what
# rule 1 governs forward: the plugin tree, the edition, the READMEs, and this
# suite. Historical editions and journals keep theirs by design and are not
# part of the publishable set.
SURFACE="setlist.md README.md .claude-plugin skills templates scripts test .github"
EM_HITS=""
EM_FILES=""
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  EM_FILES="$(cd "$ROOT" && git ls-files -- $SURFACE 2>/dev/null || true)"
fi
# An export staged into a fresh clone is a git work tree whose files are not
# tracked yet, so ls-files returns nothing and this check would pass having
# scanned zero bytes. Fall back to the filesystem, and treat an empty list as
# a failure: a hygiene check that silently covers nothing is the same defect
# class as a gate that silently allows everything.
if [[ -z "$EM_FILES" ]]; then
  EM_FILES="$(cd "$ROOT" && find $SURFACE -type f 2>/dev/null || true)"
fi
EM_COUNT=0
[[ -n "$EM_FILES" ]] && EM_COUNT="$(printf '%s\n' "$EM_FILES" | grep -c .)"
while IFS= read -r f; do
  [[ -n "$f" && -f "$ROOT/$f" ]] || continue
  # The suite's own fixture builds the character at runtime from an octal
  # escape; the literal byte must appear in no tracked file.
  if LC_ALL=C grep -q "$EMDASH" "$ROOT/$f" 2>/dev/null; then
    EM_HITS="$EM_HITS $f"
  fi
done <<EOF
$EM_FILES
EOF
if [[ "$EM_COUNT" -lt 20 ]]; then
  bad "hygiene aa: no literal em-dash byte in the shipped surface" \
      "only $EM_COUNT files were scanned; the surface is far larger, so this check covered almost nothing"
elif [[ -z "$EM_HITS" ]]; then
  ok "hygiene aa: no literal em-dash byte across $EM_COUNT files in the shipped surface"
else
  bad "hygiene aa: no literal em-dash byte in the shipped surface" "found in:$EM_HITS"
fi

# =============================================================================
# 1.0.3: the refresh checks the settings WIRING it cannot copy. Two of this
# release's fixes live in .claude/settings.json (the write-tool matcher set
# and the per-hook timeouts), and that file holds the instance's own
# permissions and model settings, so the script must not rewrite it. The
# failure to avoid is a refresh that copies hook bytes, records the new
# version, exits 0, and leaves two fixes inert while reporting success.
# =============================================================================

INST="$WORK/inst-wiring-matcher"
instance_fixture "$INST" 1.0.0 stale-matcher
run_script bash "$SCRIPTS/refresh-instance.sh" "$INST"
expect_script "wiring a: a report names the stale matcher" 0 "NotebookEdit"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring b: applying over a stale matcher exits INCOMPLETE, not 0" 3 "INCOMPLETE" "NotebookEdit"
# The hooks must still have landed: incomplete is not the same as refused.
if cmp -s "$HOOKS/close-gate.sh" "$INST/.claude/hooks/close-gate.sh"; then
  ok "wiring c: an incomplete refresh still refreshed the hook bytes"
else
  bad "wiring c: an incomplete refresh still refreshed the hook bytes" "close-gate.sh was not copied"
fi
if [[ "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")" == "$PLUGIN_VERSION" ]]; then
  ok "wiring d: an incomplete refresh still recorded the plugin version"
else
  bad "wiring d: an incomplete refresh still recorded the plugin version" "version not recorded"
fi

INST="$WORK/inst-wiring-timeouts"
instance_fixture "$INST" 1.0.0 no-timeouts
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring e: hook entries with no timeout exit INCOMPLETE" 3 "timeout"

INST="$WORK/inst-wiring-missing"
instance_fixture "$INST" 1.0.0 missing
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring f: a missing settings.json exits INCOMPLETE" 3 "missing entirely"

# And current wiring must NOT trip it: a check that fires on everything is a
# check people learn to ignore.
INST="$WORK/inst-wiring-ok"
instance_fixture "$INST" 1.0.0 current
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring g: current wiring refreshes completely and exits 0" 0 "refreshed the four stamped hooks"

# =============================================================================
# 1.0.4: the wiring check reads STRUCTURE, not text. Both directions, from two
# field reviews of the shipped 1.0.3: it must not fire on hooks the project
# owns, and it must not be defeated by JSON formatting.
# =============================================================================

# A project's own hooks are none of this check's business. A prettier hook with
# no timeout produced a permanent INCOMPLETE in 1.0.3 that no edit to Setlist's
# wiring could clear, because the demanded fix was editing someone else's hook.
INST="$WORK/inst-foreign-hook"
instance_fixture "$INST" 1.0.0 current
jq '.hooks.PostToolUse=[{matcher:"Write",hooks:[{type:"command",command:"npx prettier --write"}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring h: a foreign hook with no timeout does NOT make the refresh incomplete" 0 "refreshed the four stamped hooks"

# grep -c counts LINES. Against a minified settings.json (Claude Code rewrites
# this file when a user toggles config) four entries carrying one timeout read
# as "1 and 1" in 1.0.3, balanced, and the refresh exited 0 over three untimed
# hooks: a check that could not evaluate its predicate passing as clean.
INST="$WORK/inst-minified"
instance_fixture "$INST" 1.0.0 current
jq -c '(.hooks.PreToolUse[1].hooks[]|.timeout) |= null | del(.hooks.PreToolUse[1].hooks[].timeout)' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
assert_true "wiring i0: the fixture really is minified and really is short a timeout" \
  "the fixture is not one line, or carries every timeout, so case i proves nothing" \
  test "$(wc -l < "$INST/.claude/settings.json")" -le 1
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring i: a minified settings.json short a timeout is still caught" 3 "timeout"
expect_script "wiring i2: and the report NAMES the offending entries" 3 "commit-gate.sh"

# A foreign hook that merely MENTIONS NotebookEdit must not mask a stale scope
# matcher: 1.0.3 grepped the whole file for the token.
INST="$WORK/inst-masked-matcher"
instance_fixture "$INST" 1.0.0 stale-matcher
jq '.hooks.PostToolUse=[{matcher:"NotebookEdit",hooks:[{type:"command",command:"echo x",timeout:5}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring j: a foreign hook naming NotebookEdit does not mask a stale scope matcher" 3 "Write|Edit"

# Unparseable settings cannot be evaluated, so they are named, never assumed.
INST="$WORK/inst-badjson"
instance_fixture "$INST" 1.0.0 current
printf '{ "hooks": \n' > "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring k: settings.json that does not parse is reported, not guessed at" 3 "does not parse"

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
    /exit 0/ && $0 !~ /^[[:space:]]*#/ {
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

# =============================================================================
# THE ATTACK CORPUS (1.0.5)
#
# Every example test in this file encodes something its author thought of, and
# every bypass this project has shipped lived in what its author did not. Four
# releases in a row were repaired by an outside reader running payloads nobody
# here had written. That is not a discipline problem; it is what example-based
# testing does to a PARSER, whose input space is combinatorial and whose
# failures are adversarial.
#
# So the corpus is GENERATED, not enumerated. It crosses the generator classes
# that have actually drawn blood in this codebase:
#   - spelling variance   (the 1.0.1 class: whitespace, git options, quoting)
#   - indirection         (the 1.0.3 IN-1 class: $VAR, -, @{-1}, FETCH_HEAD, SHA)
#   - compounding         (the 1.0.4 class: && ; || and token donation between
#                          segments)
#   - content-as-code     (the 1.0.4 class: prose in -m containing the very
#                          keyword the parser anchors on)
# and asserts a single stated invariant:
#
#   If any segment of a command merges into the trunk and literally names a
#   spec/ or chore/ branch, the close conditions for that branch MUST be
#   evaluated. Nothing appended, prepended, or written in a message may
#   discard it.
#
# The inverse corpus matters as much: a checker that denies everything is a
# checker people rip out, so ordinary syncs must still pass.
# =============================================================================

CORP="$WORK/corpus"
close_fixture "$CORP" no no answered no no true   # deliberately UNCLOSED: every gated merge must deny
git -C "$CORP" branch -f tmp-alias spec/0001-thing
git -C "$CORP" update-ref refs/remotes/origin/main "$(git -C "$CORP" rev-parse main)"
git -C "$CORP" branch -f release/2.0 main

corpus_verdict() { # corpus_verdict <command> -> echoes deny|allow
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'
  else
    printf 'allow'
  fi
}

# CONTROL FIRST (Phase 3 of the hostile-review protocol). A harness that has
# not proven it can see a deny proves nothing with a pass. Five fake ALLOWs
# were produced during the 1.0.4 strictness review by a fixture missing its
# sdd.json; this is the guard against repeating that.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus control a: the harness can observe a deny on the plain gated merge"
else
  bad "corpus control a: the harness can observe a deny on the plain gated merge" \
      "the control did not deny, so every corpus result below is meaningless"
fi
if [[ "$(corpus_verdict 'git status')" == "allow" ]]; then
  ok "corpus control b: the harness can observe an allow on an ungoverned command"
else
  bad "corpus control b: the harness can observe an allow on an ungoverned command" "git status was denied"
fi

# --- the MUST-DENY corpus ----------------------------------------------------
CORPUS_DENY_N=0
CORPUS_DENY_FAIL=""
for pfx in '' 'git checkout main && '; do
 for gopt in '' '-C . ' '--no-pager '; do
  for flag in '' '--no-ff ' '--squash '; do
   for ref in 'spec/0001-thing' '"spec/0001-thing"' 'origin/spec/0001-thing' 'refs/heads/spec/0001-thing'; do
    for sfx in '' ' -m "close spec"' ' -m "improve merge of main"' ' && git merge main' ' ; git status' ' && echo done' ' -m "merge "'; do
      cmd="${pfx}git ${gopt}merge ${flag}${ref}${sfx}"
      CORPUS_DENY_N=$((CORPUS_DENY_N + 1))
      [[ "$(corpus_verdict "$cmd")" == "deny" ]] || CORPUS_DENY_FAIL="$CORPUS_DENY_FAIL
    $cmd"
    done
   done
  done
 done
done
if [[ "$CORPUS_DENY_N" -lt 100 ]]; then
  bad "corpus deny: the generator produced a real corpus" \
      "only $CORPUS_DENY_N commands were generated; the cross product is broken and this proves almost nothing"
elif [[ -z "$CORPUS_DENY_FAIL" ]]; then
  ok "corpus deny: all $CORPUS_DENY_N generated spec-merge spellings are denied"
else
  bad "corpus deny: every generated spec-merge spelling must be denied ($CORPUS_DENY_N generated)" \
      "these reached the trunk with the close conditions unevaluated:$CORPUS_DENY_FAIL"
fi

# --- the WRAPPER axis (1.0.6) -----------------------------------------------
# The command-position test that fixed `echo git merge ...` introduced its own
# false negative: a segment is only judged if it STARTS with git, and wrappers
# are how a shell legitimately starts git. The 504-spelling corpus had no
# wrapper dimension, which is why this shipped. The dimension list is itself an
# artifact written from what somebody thought of, and nothing reviews it.
CORPUS_WRAP_N=0
CORPUS_WRAP_FAIL=""
for wrap in 'command ' 'exec ' 'nice ' 'nohup ' 'env ' 'env GIT_PAGER=cat ' 'GIT_PAGER=cat ' 'time '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_WRAP_N=$((CORPUS_WRAP_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_WRAP_FAIL="$CORPUS_WRAP_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_WRAP_FAIL" ]]; then
  ok "corpus wrappers: all $CORPUS_WRAP_N wrapper-prefixed spec merges are denied"
else
  bad "corpus wrappers: a wrapper prefix must not escape the gate ($CORPUS_WRAP_N generated)" \
      "these reached the trunk unchecked:$CORPUS_WRAP_FAIL"
fi

# --- the CHECKOUT-TARGET axis (1.0.6) ---------------------------------------
# `git checkout -` is organic shorthand, not attacker spelling: it is exactly
# the state an agent is in after `git checkout spec/NNNN` from the trunk. The
# branch tracker took the first NON-DASH argument, so `-` was skipped, the
# running branch stayed on the spec branch, and the merge segment was judged
# as targeting a feature branch, which is an explicitly ALLOWED case. Not a
# fall-through: the gate reached a confident wrong answer.
CORP_DASH="$WORK/corpus-dash"
close_fixture "$CORP_DASH" no no answered no no true
git -C "$CORP_DASH" checkout -q spec/0001-thing   # @{-1} is now the trunk, the organic state
dash_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_DASH" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus dash0: the fixture really has the trunk as its previous branch" \
  "@{-1} does not resolve to the trunk, so the cases below prove nothing" \
  test "$(git -C "$CORP_DASH" rev-parse --abbrev-ref '@{-1}' 2>/dev/null)" = "main"
CORP_DASH_FAIL=""
for c in 'git checkout - && git merge --no-ff spec/0001-thing' \
         'git switch - && git merge --no-ff spec/0001-thing' \
         'git checkout @{-1} && git merge --no-ff spec/0001-thing'; do
  [[ "$(dash_verdict "$c")" == "deny" ]] || CORP_DASH_FAIL="$CORP_DASH_FAIL
    $c"
done
if [[ -z "$CORP_DASH_FAIL" ]]; then
  ok "corpus dash: returning to the trunk by shorthand does not escape the gate"
else
  bad "corpus dash: 'checkout -' back to the trunk must not escape the gate" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_DASH_FAIL"
fi

# --- the MUST-ALLOW corpus ---------------------------------------------------
CORPUS_ALLOW_N=0
CORPUS_ALLOW_FAIL=""
for cmd in \
  'git merge origin/main' \
  'git merge --no-ff release/2.0' \
  'git merge main' \
  'git pull origin main' \
  'git status' \
  'git log --oneline' \
  'git merge --continue' \
  'git merge --abort' \
  'echo git merge spec/0001-thing' ; do
  CORPUS_ALLOW_N=$((CORPUS_ALLOW_N + 1))
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_ALLOW_FAIL="$CORPUS_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_ALLOW_FAIL" ]]; then
  ok "corpus allow: all $CORPUS_ALLOW_N ordinary operations still pass"
else
  bad "corpus allow: ordinary operations must not be denied" \
      "a gate that denies these is one people disable:$CORPUS_ALLOW_FAIL"
fi

# --- interpreter forms: documented passes, PAIRED with the audit catch -------
# The pathspec hole is asserted as a pass so its closure is detected. These go
# one better, because a deliberate hole should be pinned together with the
# thing that actually catches it: each interpreter form passes the gate AND its
# outcome is caught by the trunk audit. That pairing is the two-layer claim the
# README now makes, asserted rather than asserted-about.
INTERP="$WORK/interpreter"
close_fixture "$INTERP" no no answered no no true
for form in 'sh -c "git merge --no-ff spec/0001-thing"' 'bash -c "git merge --no-ff spec/0001-thing"'; do
  run_hook "$HOOKS/close-gate.sh" "$INTERP" "$(bash_payload "$form")"
  expect_allow "interpreter: [$form] passes the gate, as Known limitations states"
done
# The branch must carry ROLE-PATH changes for the audit to have an opinion: a
# docs-only merge is legitimately ignored, and the first cut of this case
# merged a spec-file-only branch and then reported the audit broken. The
# fixture has to look like the thing being claimed.
git -C "$INTERP" checkout -q spec/0001-thing
mkdir -p "$INTERP/src"; printf 'feature\n' > "$INTERP/src/f.js"
git -C "$INTERP" add -A && git -C "$INTERP" commit -qm "feature code, spec still unclosed"
git -C "$INTERP" checkout -q main
git -C "$INTERP" merge -q --no-ff -m "merge as an interpreter form would leave it" spec/0001-thing
run_script bash "$SCRIPTS/trunk-audit.sh" "$INTERP"
expect_script "interpreter: the trunk audit CATCHES the outcome the gate let past" 1 "VIOLATION"

# --- THE HOLE LEDGER ---------------------------------------------------------
#
# Docs-tree lockstep, the honest version. Every entry in the public README's
# "Known limitations" appears here EXACTLY ONCE, with one of two dispositions:
#
#   asserted:    a test below pins it, so the day the hole closes the suite
#                fails and tells us the docs are now wrong.
#   unassertable: it cannot be exercised from a bash suite, with the reason
#                and the manual procedure that would check it. These become
#                the human pre-release checklist rather than silently
#                vanishing.
#
# publish-setlist.sh refuses to export when a README bullet is missing from
# this ledger or a ledger line names no README bullet. Counting was the first
# design and it was too crude: it could be satisfied by asserting the easy
# holes twice while an unassertable one went unrecorded.
#
# LEDGER-BEGIN
# hole: The Bash escape hatch. | asserted
# hole: The remote-merge bypass. | unassertable | needs a forge; verify by opening a PR and merging it in the web UI, confirming the close gate never runs
# hole: Sideways routes to the trunk. | asserted
# hole: The pathspec hole. | asserted
# hole: The secret scan is a first cut. | asserted
# hole: The gates need `jq`, and fail closed without it. | asserted
# hole: A timed-out hook is a skipped gate. | unassertable | harness behaviour, not hook behaviour; verified live 2026-07-25 with a sleeping hook under timeout 1 and 10, recorded in close-gate.sh's header
# hole: The staged-content scans read every staged line. | asserted
# LEDGER-END
#
# Each of these is a deliberate pass named in the README. They are asserted
# rather than ignored so that the day one of them closes, this file says so
# instead of nobody noticing.
for hole_cmd in \
  'git cherry-pick spec/0001-thing' \
  'git rebase spec/0001-thing' \
  'git reset --hard spec/0001-thing' \
  'git checkout spec/0001-thing -- src/app.js' \
  'git merge --no-ff tmp-alias' ; do
  if [[ "$(corpus_verdict "$hole_cmd")" == "allow" ]]; then
    ok "documented hole: [$hole_cmd] still passes, as Known limitations states"
  else
    bad "documented hole: [$hole_cmd] still passes" \
        "this now DENIES. That is an improvement, but the README still lists it as a hole: update Known limitations and this assertion together"
  fi
done

# The two remaining asserted holes are exercised elsewhere in this file and are
# named here so the ledger's "asserted" claims are all traceable:
#   - "The secret scan is a first cut."      -> commit-gate d (a shape it CATCHES)
#     and the miss below (a shape it does not).
#   - "The staged-content scans read every staged line." -> the vendored-content
#     case below: foreign content in a staged diff is denied on style alone.
SCAN="$WORK/scan-scope"
git_init "$SCAN"
sdd_json "$SCAN"
mkdir -p "$SCAN/vendor"
printf 'const x = 1; /* upstream file, not ours to restyle %s */\n' "$EMDASH" > "$SCAN/vendor/lib.js"
git -C "$SCAN" add vendor/lib.js
run_hook "$HOOKS/commit-gate.sh" "$SCAN" "$(bash_payload 'git commit -m "vendor: add upstream lib"')"
expect_deny "documented hole: vendored content is style-scanned like our own writing" "em-dash"
git -C "$SCAN" reset -q

printf 'token = "%s"\n' 'ghp_ShortOne' > "$SCAN/cfg.txt"
git -C "$SCAN" add cfg.txt
run_hook "$HOOKS/commit-gate.sh" "$SCAN" "$(bash_payload 'git commit -m cfg')"
expect_allow "documented hole: the secret scan misses values below its length threshold"
git -C "$SCAN" reset -q

# =============================================================================
# THE COMMIT-GATE CORPUS (1.0.5)
#
# The close-gate corpus found 144 bypasses and an over-denial nobody had
# reported. The commit gate parses a different grammar (a command line PLUS a
# staged index) and had never been generated against, only exampled. This
# pins what it does across the input space, so a future change to it, S1's
# location check above all, is judged by a corpus that already exists rather
# than by cases written to justify the change.
#
# Invariant: a command that stages AND commits in one line must deny, because
# the gate reads the index BEFORE the command runs and would otherwise scan
# content that is not there yet. Inverse: an ordinary commit, and prose that
# merely mentions the staging verbs, must pass.
# =============================================================================

CGC="$WORK/commit-corpus"
git_init "$CGC"
sdd_json "$CGC"
printf 'clean content with nothing to find\n' > "$CGC/ok.md"
git -C "$CGC" add ok.md

cg_verdict() { # cg_verdict <command>
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CGC" bash "$HOOKS/commit-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}

# CONTROL FIRST, both directions.
if [[ "$(cg_verdict 'git add -A && git commit -m x')" == "deny" ]]; then
  ok "commit corpus control a: the harness observes a deny on a known compound"
else
  bad "commit corpus control a: the harness observes a deny on a known compound" \
      "the control did not deny; every result below is meaningless"
fi
if [[ "$(cg_verdict 'git commit -m x')" == "allow" ]]; then
  ok "commit corpus control b: the harness observes an allow on a clean staged commit"
else
  bad "commit corpus control b: the harness observes an allow on a clean staged commit" \
      "a plain commit with clean staged content was denied"
fi

# --- MUST DENY: every spelling of stage-and-commit ---------------------------
CGD_N=0; CGD_FAIL=""
for stage in 'git add -A' 'git add .' 'git add src/x' 'git rm f.txt' 'git mv a.txt b.txt'; do
 for conn in ' && ' ' ; ' ' || '; do
  for commit in 'git commit -m x' 'git  commit -m x' 'git -C . commit -m x' 'git --no-pager commit -m x' '/usr/bin/git commit -m x'; do
    CGD_N=$((CGD_N + 1))
    [[ "$(cg_verdict "${stage}${conn}${commit}")" == "deny" ]] || CGD_FAIL="$CGD_FAIL
    ${stage}${conn}${commit}"
  done
 done
done
for auto in 'git commit -am x' 'git commit -a -m x' 'git commit --all -m x' 'git commit --include f -m x' 'git commit -ai -m x'; do
  CGD_N=$((CGD_N + 1))
  [[ "$(cg_verdict "$auto")" == "deny" ]] || CGD_FAIL="$CGD_FAIL
    $auto"
done
if [[ "$CGD_N" -lt 50 ]]; then
  bad "commit corpus deny: the generator produced a real corpus" "only $CGD_N commands generated"
elif [[ -z "$CGD_FAIL" ]]; then
  ok "commit corpus deny: all $CGD_N stage-and-commit spellings are denied"
else
  bad "commit corpus deny: every stage-and-commit spelling must be denied ($CGD_N generated)" \
      "these would have scanned an index that does not hold the content yet:$CGD_FAIL"
fi

# --- the WRAPPER axis, commit gate (1.0.6) ----------------------------------
CGW_N=0; CGW_FAIL=""
for wrap in 'command ' 'exec ' 'nice ' 'env ' 'GIT_PAGER=cat '; do
  for tail in 'git commit -am x' 'git add -A && git commit -m x'; do
    CGW_N=$((CGW_N + 1))
    [[ "$(cg_verdict "${wrap}${tail}")" == "deny" ]] || CGW_FAIL="$CGW_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CGW_FAIL" ]]; then
  ok "commit corpus wrappers: all $CGW_N wrapper-prefixed staging compounds are denied"
else
  bad "commit corpus wrappers: a wrapper prefix must not escape the commit gate" \
      "these scanned a stale index unchecked:$CGW_FAIL"
fi

# --- MUST ALLOW: ordinary work, and prose that mentions the verbs ------------
CGA_N=0; CGA_FAIL=""
for cmd in \
  'git commit -m x' \
  'git commit -m "remember to git add the new file next time"' \
  'git commit -m "this supersedes the git rm approach"' \
  'git commit --amend --no-edit' \
  'git status' \
  'git log --oneline' \
  'git add -A' \
  'npm run build' \
  'echo git add . && git commit -m x' ; do
  CGA_N=$((CGA_N + 1))
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGA_FAIL="$CGA_FAIL
    $cmd"
done
if [[ -z "$CGA_FAIL" ]]; then
  ok "commit corpus allow: all $CGA_N ordinary commit-path operations pass"
else
  bad "commit corpus allow: ordinary operations must not be denied" \
      "a gate that denies these is one people disable:$CGA_FAIL"
fi

# =============================================================================
# THE TRUNK AUDIT (1.0.5, advisory)
#
# The hooks decide by parsing a command before it runs; this reads history
# after the fact, which is decidable where the parser never can be. Covered
# in both directions, and the fixtures mirror the shapes real history turned
# out to have: a suffixed spec number (0005b), and a chore merge with no spec
# at all. Both were false positives on the first run against a real repo.
# =============================================================================

audit_fixture() { # audit_fixture <dir> <mode: clean|direct|unclosed>
  local d="$1" mode="$2"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git_init "$d"
  sdd_json "$d"
  git -C "$d" add .claude/sdd.json && git -C "$d" commit -qm "stamp"
  # a compliant spec close, with a SUFFIXED number
  git -C "$d" checkout -q -b spec/0005b-thing
  mkdir -p "$d/src"
  printf 'feature\n' > "$d/src/f.js"
  {
    printf '# Spec 0005b\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    printf -- '- QA Pass 2 (human): done\n'
  } > "$d/specs/0005b-thing.md"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0005b"
  if [[ "$mode" == "unclosed" ]]; then
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | ACTIVE |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "not closed after all"
  fi
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge spec 0005b" spec/0005b-thing
  # a chore merge carrying role-path changes and no spec: legitimate, and
  # indistinguishable from an unspecced feature in history
  git -C "$d" checkout -q -b chore/tidy
  printf 'tidy\n' >> "$d/src/f.js"
  git -C "$d" add -A && git -C "$d" commit -qm "chore work"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge chore: tidy" chore/tidy
  if [[ "$mode" == "direct" ]]; then
    printf 'snuck in\n' >> "$d/src/f.js"
    git -C "$d" add -A && git -C "$d" commit -qm "hotfix straight onto the trunk"
  fi
}

AUD="$WORK/audit-clean"; audit_fixture "$AUD" clean
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit a: a compliant trunk reports zero violations" 0 "0 violations"
expect_script "trunk audit b: a suffixed spec number (0005b) is recognised, not flagged" 0 "0 violations"
expect_script "trunk audit c: a chore merge is counted as unverifiable, not as a violation" 0 "chore merges"

AUD="$WORK/audit-direct"; audit_fixture "$AUD" direct
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit d: feature code committed straight to the trunk is a violation" 1 \
  "feature code committed directly" "1 violations"

AUD="$WORK/audit-unclosed"; audit_fixture "$AUD" unclosed
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit e: a merge whose spec has no CLOSED row is a violation" 1 "no-CLOSED-row"

# =============================================================================
# GENERATOR 6: DEGRADED ENVIRONMENT (1.0.5)
#
# The gates are only ever exercised against a healthy repo in the cases above.
# Real repos are detached, unborn, half-configured, and reformatted by the
# harness itself. Every one of these is an input the gates must survive, and
# the question for each is the one from Phase 4: when the check cannot
# evaluate its predicate, does it deny or does it fall through?
# =============================================================================

DEG="$WORK/degraded"
close_fixture "$DEG" no no answered no no true

# DETACHED HEAD. `branch --show-current` returns empty, so no gate can tell
# whether it is on the trunk. Documented as a sideways route; asserted here so
# the day it closes we find out.
DEG_HEAD="$(git -C "$DEG" rev-parse main)"
git -C "$DEG" checkout -q --detach "$DEG_HEAD"
run_hook "$HOOKS/close-gate.sh" "$DEG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "degraded a: on a detached HEAD the close gate passes (documented sideways route)"
run_hook "$HOOKS/scope-hook.sh" "$DEG" "$(jq -nc --arg p "$DEG/src/x.js" '{tool_name:"Edit", tool_input:{file_path:$p}}')"
expect_allow "degraded b: on a detached HEAD the scope hook passes (same route)"
git -C "$DEG" checkout -q main

# UNPARSEABLE sdd.json. jq is present, the file is not readable as JSON. The
# hooks read the trunk and role paths from it; with neither, they cannot tell
# a trunk write from a branch write.
DEG2="$WORK/degraded-badjson"
close_fixture "$DEG2" no no answered no no true
printf '{ "trunk": \n' > "$DEG2/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$DEG2" "$(jq -nc --arg p "$DEG2/src/x.js" '{tool_name:"Write", tool_input:{file_path:$p}}')"
expect_deny "degraded c: an unparseable sdd.json denies the write rather than guessing" "scope hook"
run_hook "$HOOKS/close-gate.sh" "$DEG2" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "degraded d: an unparseable sdd.json denies the merge rather than guessing" "close gate"

# MINIFIED sdd.json. Claude Code rewrites config files, and the 1.0.3 wiring
# check was defeated by exactly this. The hooks read sdd.json with jq, which
# is format-blind, so this must behave identically to the pretty form.
DEG3="$WORK/degraded-minified"
close_fixture "$DEG3" no no answered no no true
jq -c . "$DEG3/.claude/sdd.json" > "$DEG3/t" && mv "$DEG3/t" "$DEG3/.claude/sdd.json"
assert_true "degraded e0: the fixture really is minified" \
  "the fixture is not one line, so case e proves nothing" \
  test "$(wc -l < "$DEG3/.claude/sdd.json")" -le 1
run_hook "$HOOKS/close-gate.sh" "$DEG3" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "degraded e: a minified sdd.json is read identically to a pretty one" "Closing report"

# EMPTY role paths. A config that parses but records nothing usable.
DEG4="$WORK/degraded-noroles"
close_fixture "$DEG4" no no answered no no true
jq '.roles = {}' "$DEG4/.claude/sdd.json" > "$DEG4/t" && mv "$DEG4/t" "$DEG4/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$DEG4" "$(jq -nc --arg p "$DEG4/src/x.js" '{tool_name:"Write", tool_input:{file_path:$p}}')"
expect_deny "degraded f: absent role paths fall back to src/tests rather than allowing everything" "never lands"

# =============================================================================
# GENERATOR 7: FOREIGN MATERIAL (1.0.5)
#
# A checker must judge what it owns and ignore what it does not. The 1.0.3
# wiring check failed this in both directions at once. These put material the
# gates do NOT own next to material they do.
# =============================================================================

FOR1="$WORK/foreign"
close_fixture "$FOR1" yes yes answered yes no true
# A file that LOOKS like a spec but is not in specs/, beside the real one.
mkdir -p "$FOR1/vendor/specs"
printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$FOR1/vendor/specs/0001-decoy.md"
git -C "$FOR1" add -A && git -C "$FOR1" commit -qm "vendored decoy that mimics a spec"
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "foreign a: a decoy spec outside specs/ does not confuse the close gate"

# A branch whose NAME contains a spec-like string but is not a spec branch.
git -C "$FOR1" branch -f feature/not-spec/0002-x main
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/not-spec/0002-x')"
expect_allow "foreign b: a branch whose name merely contains a spec-like path is not gated as a close"

# Foreign paths in the staged diff beside owned ones: the scan judges content,
# and this pins that it does not judge ownership (a documented limitation).
FOR2="$WORK/foreign-staged"
git_init "$FOR2"; sdd_json "$FOR2"
mkdir -p "$FOR2/node_modules/pkg"
printf 'const a = 1;\n' > "$FOR2/node_modules/pkg/index.js"
printf 'ours\n' > "$FOR2/ours.md"
git -C "$FOR2" add -A
run_hook "$HOOKS/commit-gate.sh" "$FOR2" "$(bash_payload 'git commit -m "add dependency"')"
expect_allow "foreign c: clean vendored content beside our own passes the content scans"

# =============================================================================
# GENERATOR 5: EQUIVALENT OPERATIONS (1.0.5)
#
# Every sibling command that achieves the governed effect is either gated, or
# named in Known limitations AND asserted here so its closure is detected.
# The close-gate siblings are asserted in the documented-hole block above;
# these are the COMMIT-gate siblings, which create or stage content without
# the word "commit" ever appearing at command position.
# =============================================================================

EQ="$WORK/equivalent"
git_init "$EQ"; sdd_json "$EQ"
printf 'x\n' > "$EQ/a.md"; git -C "$EQ" add -A; git -C "$EQ" commit -qm base
for sib in 'git revert --no-edit HEAD' 'git stash pop' 'git apply /tmp/p.patch' 'git cherry-pick --no-commit HEAD' 'git commit --amend --no-edit'; do
  run_hook "$HOOKS/commit-gate.sh" "$EQ" "$(bash_payload "$sib")"
  case "$sib" in
    *--amend*) expect_allow "equivalent: [$sib] reaches the content scans (clean here)" ;;
    *) expect_allow "equivalent: [$sib] bypasses the content scans (documented gap, item 30)" ;;
  esac
done

# =============================================================================
# THE OPT-IN PRE-PUSH HOOK (1.0.5, Tier 3 Stage A's delivery half)
# Both directions, plus the refusal that matters most: a check that cannot
# find its own tool must NOT exit 0.
# =============================================================================

PP="$ROOT/templates/git-hooks/pre-push"
PPD="$WORK/prepush-clean"; audit_fixture "$PPD" clean
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP'"
expect_script "pre-push a: a compliant trunk is allowed to push" 0

PPD="$WORK/prepush-dirty"; audit_fixture "$PPD" direct
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP'"
expect_script "pre-push b: feature code straight on the trunk refuses the push" 1 "did not arrive through a"

run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && SETLIST_SKIP_TRUNK_AUDIT=1 CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP'"
expect_script "pre-push c: the documented escape hatch works and says so" 0 "skipped by SETLIST_SKIP"

run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && bash '$PP'"
expect_script "pre-push d: unable to find its own tool, it REFUSES rather than passing" 1 "has not passed"

PPD="$WORK/prepush-noinstance"; rm -rf "$PPD"; mkdir -p "$PPD"; git_init "$PPD"
run_script env -u CLAUDE_PLUGIN_ROOT bash -c "cd '$PPD' && CLAUDE_PLUGIN_ROOT='$ROOT' bash '$PP'"
expect_script "pre-push e: a repo that is not a framework instance is untouched" 0

# --- summary -----------------------------------------------------------------

printf '\n%s\n' "-----------------------------------------------"
printf 'passed %d, failed %d, total %d\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]] || exit 1
