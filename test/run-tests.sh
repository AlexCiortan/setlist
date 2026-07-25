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
trap 'rm -rf "$WORK"' EXIT

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

run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'git merge --no-ff some-other-branch')"
expect_allow "spelling (merge): a merge of a non-spec branch is untouched"
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
instance_fixture() { # instance_fixture <dir> <recorded-version|none|broken>
  local d="$1" rec="$2" h
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

# --- summary -----------------------------------------------------------------

printf '\n%s\n' "-----------------------------------------------"
printf 'passed %d, failed %d, total %d\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]] || exit 1
