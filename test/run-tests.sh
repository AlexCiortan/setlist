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

# A CALL TO AN UNDEFINED FUNCTION IS FATAL (1.0.8).
#
# The verdict helpers are defined partway down this file, and a block placed
# above its helper calls a function that does not exist yet. bash prints
# "command not found" to stderr and the command substitution yields the EMPTY
# STRING, which every verdict helper's caller reads as "allow". An assertion
# expecting a deny then fails with a confusing message, and an assertion
# expecting an ALLOW passes while testing nothing at all. The second is the
# dangerous one, and it is the silent-pass shape this suite exists to hunt.
#
# Found by putting a commit-gate block above cg_verdict's definition and
# watching it report a hook defect that did not exist.
#
# bash 3.2 (macOS) has no command_not_found_handle, so this is a Linux and CI
# guard rather than a universal one. It costs nothing where it is unsupported
# and the ordering rule holds on both.
command_not_found_handle() {
  printf 'SUITE ABORTED: "%s" is not defined at this point in the file.\n' "$1" >&2
  printf '  A helper is being called ABOVE its definition. Move the block below the\n' >&2
  printf '  helper: an undefined call returns empty, which reads as ALLOW, and an\n' >&2
  printf '  assertion in the allow direction would pass while testing nothing.\n' >&2
  exit 1
}


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

# A PERMISSION FIXTURE THAT CANNOT ARM ITSELF MUST NOT REPORT A PASS (V1b).
#
# Three fixtures in this file make a directory unreadable with `chmod 000` or
# `chmod 300` and then assert that the code REFUSES rather than vouching for what
# it cannot see. `chmod` is a no-op against uid 0, which a cold container
# typically runs as, so on those hosts the directory stayed readable, the
# refusal never fired, and the assertion failed for a fixture reason while
# looking like a real defect. A remote session reported exactly that: `808/1` on
# `refresh R9c` in a container, against a tree this host runs green.
#
# The guard asks whether the restriction ACTUALLY BIT rather than asking who we
# are. That is deliberate and it is the stronger question: uid 0 is only the
# common reason chmod does nothing, and a filesystem mounted without permission
# support, an ACL, or a container's user namespace produce the same no-op
# without producing uid 0. Testing the effect covers all of them, and it cannot
# drift from the thing it is a proxy for, because it is not a proxy.
#
# It SKIPS LOUDLY rather than refusing to run the whole suite: these are three
# assertions out of hundreds, the rest are perfectly meaningful as root, and
# refusing outright would make the suite unrunnable in exactly the environment
# CI containers use. The skip names the reason so it can never be read as a pass.
# THE PROBE IS A SHELL BUILTIN, NOT `ls`, AND THAT WAS MEASURED RATHER THAN
# ASSUMED. The first cut asked `ls "$dir" >/dev/null 2>&1`. On this development
# machine `ls` is a replacement that prints "Permission denied ... code: 13" and
# EXITS 0, so the probe concluded the chmod had not bitten, and all three
# assertions would have skipped silently on the one host that can actually run
# them. A guard against a silent pass that introduces a silent pass is worth
# catching, and only running it caught it.
#
# `[ -r ] && [ -x ]` is a bash builtin, so it depends on no external tool, and it
# is the SAME predicate hooks_layer_is_ours uses to decide it cannot vouch for a
# directory. Asking the code's own question is what makes this a precondition
# check rather than a second opinion. As root, access(2) succeeds on both
# regardless of mode, which is exactly the case that must skip.
perm_fixture_bites() { # perm_fixture_bites <path> <label> -> 0 when the chmod really restricts
  if [[ -r "$1" && -x "$1" ]]; then
    ok "$2: SKIPPED, chmod does not restrict this process here (uid $(id -u)), so the fixture cannot arm its own precondition and a pass would be unearned"
    return 1
  fi
  return 0
}

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

# And the state build_nojq_bin cannot express (leg 4, F1): a jq that is PRESENT
# and does not run. Unlinking jq from PATH tests one failure mode and the guards
# were written against exactly that one, so a jq that exists and exits nonzero
# walked past `command -v jq` and made two governing gates allow in silence.
#
# A fixture that cannot express a failure is not evidence against it, which this
# suite has now written down three times about three different fixtures.
BROKENJQ_BIN="$WORK/brokenjq-bin"
build_brokenjq_bin() {
  mkdir -p "$BROKENJQ_BIN"
  local t p
  for t in bash sh git grep sed awk cat head tail od tr wc cut sort uniq \
           printf env dirname basename mkdir rm cp mv ls chmod date mktemp; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$BROKENJQ_BIN/$t"
  done
  # The failure a broken dynamic link actually produces: a message on stderr and
  # a nonzero status, with nothing on stdout.
  printf '#!/bin/sh\necho "jq: error while loading shared libraries: libonig.so.5" >&2\nexit 127\n' > "$BROKENJQ_BIN/jq"
  chmod +x "$BROKENJQ_BIN/jq"
  # The fixture proves itself before anything is asserted with it: a stub that
  # accidentally worked would make every case below pass for the wrong reason.
  if PATH="$BROKENJQ_BIN" command -v jq >/dev/null 2>&1; then :; else
    printf 'harness error: the broken-jq stub is not on the fixture PATH\n' >&2
    exit 2
  fi
  if PATH="$BROKENJQ_BIN" jq --version >/dev/null 2>&1; then
    printf 'harness error: the broken-jq stub RUNS, so it does not test a broken jq\n' >&2
    exit 2
  fi
}

run_hook_brokenjq() { # run_hook_brokenjq <hook-file> <project-dir> <payload>
  HOOK_OUT="$(printf '%s' "$3" | PATH="$BROKENJQ_BIN" CLAUDE_PROJECT_DIR="$2" bash "$1" 2>/dev/null)"
  HOOK_RC=$?
}

# THE SAME TRICK, FOR THE REST OF THE TOOLCHAIN (v1.7 gate, adversarial review F2).
#
# jq was the only dependency anyone probed, and close-gate.sh:133-145 states the
# rule in general terms ("A gate whose lexer can fail must not treat lexer
# failure as a clean parse") while implementing it for exactly one tool. Break
# awk, sed, tr or grep instead and both Bash gates ALLOWED in silence, because
# CMD_NORM came back empty and the applicability grep then matched nothing:
# absence read as "nothing to govern", which is the 1.0.8 macOS fail-open exactly.
BROKENTOOL_BIN="$WORK/brokentool-bin"
build_brokentool_bin() { # build_brokentool_bin <tool-to-break>
  local broken="$1" t p
  rm -rf "$BROKENTOOL_BIN"; mkdir -p "$BROKENTOOL_BIN"
  for t in bash sh git jq grep sed awk cat head tail od tr wc cut sort uniq \
           printf env dirname basename mkdir rm cp mv ls chmod date mktemp; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$BROKENTOOL_BIN/$t"
  done
  # The symlink for the tool under test is REMOVED before the stub is written.
  # Without this, the redirection follows the symlink and writes through it to
  # the real binary on the system PATH: the first draft tried to overwrite
  # /usr/bin/awk and was saved by file permissions rather than by design. The
  # self-check below is what surfaced it, by reporting that the stub still ran.
  rm -f "$BROKENTOOL_BIN/$broken"
  printf '#!/bin/sh\necho "%s: error while loading shared libraries: lib.so.1" >&2\nexit 127\n' \
    "$broken" > "$BROKENTOOL_BIN/$broken"
  chmod +x "$BROKENTOOL_BIN/$broken"
  # The fixture proves itself in BOTH directions before anything is asserted with
  # it, because a stub that accidentally worked would make every case below pass
  # for the wrong reason, and a PATH missing the OTHER tools would make them all
  # deny for the wrong reason.
  if ! PATH="$BROKENTOOL_BIN" sh -c "command -v $broken" >/dev/null 2>&1; then
    printf 'harness error: the broken-%s stub is not on the fixture PATH\n' "$broken" >&2; exit 2
  fi
  if PATH="$BROKENTOOL_BIN" sh -c "printf x | $broken --version" >/dev/null 2>&1; then
    printf 'harness error: the broken-%s stub RUNS, so it tests nothing\n' "$broken" >&2; exit 2
  fi
  # ... and every OTHER tool in the shim still works.
  for t in awk sed tr grep jq git; do
    [[ "$t" == "$broken" ]] && continue
    if ! PATH="$BROKENTOOL_BIN" sh -c "command -v $t" >/dev/null 2>&1; then
      printf 'harness error: %s is missing from the shim while breaking %s\n' "$t" "$broken" >&2; exit 2
    fi
  done
}

run_hook_brokentool() { # run_hook_brokentool <hook-file> <project-dir> <payload>
  HOOK_OUT="$(printf '%s' "$3" | PATH="$BROKENTOOL_BIN" CLAUDE_PROJECT_DIR="$2" bash "$1" 2>/dev/null)"
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
  decision="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty')"
  if [[ "$decision" != "deny" ]]; then
    bad "$name" "expected permissionDecision deny, got '${decision:-<none>}'"
    return
  fi
  reason="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.reason // .hookSpecificOutput.permissionDecisionReason // empty')"
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
build_brokenjq_bin

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
printf 'api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789"\n' > "$CG/config.txt"
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

# f2. THE SAME GUARD THROUGH THE ESCAPE PATH (leg 4, F31). Case f covers the
# quoted spelling; an UNQUOTED message using backslash escapes was un-escaped
# into live grammar, so a plain commit read as a compound stage-and-commit and
# was denied. That is the false-positive twin of the close gate's F5, and it is
# asserted here because a fix aimed only at the injection direction can pass
# every one of those cases while breaking ordinary commits.
git -C "$CG" add clean.md 2>/dev/null || true
for esc_msg in 'git commit -m foo\;git\ add\ .' 'git commit -m explain\ why\ git\ add\ runs\ first' 'git commit -m fixup\&cleanup'; do
  run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload "$esc_msg")"
  expect_allow "commit-gate f2: [$esc_msg] is one commit, not a compound"
done

# f3. And the compound must STILL be seen, so f2 cannot pass by blinding the
# separator test outright. This is the direction that would silently disarm the
# gate if the escape fix went one step too far.
for real_compound in 'git add . && git commit -m fixup' 'git add . ; git commit -m fixup' 'git add .; git commit -m fixup'; do
  run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload "$real_compound")"
  expect_deny "commit-gate f3: [$real_compound] is a real compound and is still denied" "one step"
done
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

# j. no Closing report
# F2 of the 2.2.0 leg, a CONFIRMED FALSE DENIAL and F1's root cause on the READ
# side. A fully compliant spec whose FILENAME carries a non-ASCII byte was
# refused CG-SPEC-MISSING, the message naming a file that is present, because
# `git ls-tree --name-only` emits the path QUOTED and the gate's
# ^specs/NNNN-[^/]*\.md$ pattern could not match through the quotes and escapes.
#
# The CONTROL runs first and is the ASCII sibling of the same fixture, so a green
# here is evidence about the FILENAME rather than about close_fixture.
CL="$WORK/close-f2-ascii"; close_fixture "$CL" yes yes answered yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate F2 control: a compliant spec with an ASCII filename merges"

# THE RENAME MUST HAPPEN ON THE SPEC BRANCH, not on the trunk. The first cut of
# this case renamed on main, because close_fixture leaves you there, so the gate
# read the still-ASCII file from MERGED_REF and the case PASSED against pre-fix
# bytes: a vacuous assertion that would have shipped as evidence for a fix it
# never exercised. Caught by running it against the unfixed tree, which is the
# only reason it is written this way.
CL="$WORK/close-f2-utf8"; close_fixture "$CL" yes yes answered yes no true
git -C "$CL" checkout -q spec/0001-thing
git -C "$CL" mv "specs/0001-thing.md" "specs/0001-$(printf 'caf\303\251').md"
git -C "$CL" add -A && git -C "$CL" commit -qm "the spec file carries a non-ASCII byte"
git -C "$CL" checkout -q main
# The fixture asserts its own shape: the branch must really carry the renamed
# file, or the case below tests nothing.
if ! git -C "$CL" ls-tree -r -z --name-only spec/0001-thing | tr '\0' '\n' | grep -q "^specs/0001-"; then
  printf 'FIXTURE BROKEN: close-f2-utf8 has no specs/0001-* on the spec branch\n' >&2
fi
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_allow "close-gate F2: a compliant spec whose FILENAME carries a non-ASCII byte still merges"

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

# l2. a diagram field only inside a code fence is not live text (F6, plugin-2.0.0 leg)
CL="$WORK/close-l2"; close_fixture "$CL" yes yes fenced yes no true
run_hook "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate l2: a diagram field only inside a code fence does not answer the mandatory field and is denied (F6)" "diagram"

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

run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "clean"')"
CG_HEALTHY_RC="$HOOK_RC"; CG_HEALTHY_OUT="$HOOK_OUT"
run_hook_brokenjq "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "clean"')"
expect_deny "broken-jq j1: the commit gate fails CLOSED when jq runs and fails" "jq"

run_hook_brokenjq "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "broken-jq j2: the close gate fails CLOSED even on a compliant merge" "jq"

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

# THE REST OF THE TOOLCHAIN, one tool at a time (adversarial review F2).
#
# Asserted on the CODE rather than on "it denied", deliberately. The payload
# below is a governed merge that the healthy gate already denies for an ordinary
# reason, so an assertion that only checked for a denial would pass whether or
# not the toolchain probe exists. Naming the code is what makes this test about
# the probe.
for bt in awk sed tr grep; do
  build_brokentool_bin "$bt"
  run_hook_brokentool "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
  expect_deny "toolchain t1: the close gate fails CLOSED when $bt is broken" "CG-NO-TOOLCHAIN"
  run_hook_brokentool "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "clean"')"
  expect_deny "toolchain t2: the commit gate fails CLOSED when $bt is broken" "CM-NO-TOOLCHAIN"
done

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
build_brokentool_bin git
run_hook_brokentool "$HOOKS/close-gate.sh" "$CL" "$(bash_payload "$MERGE_CMD")"
expect_deny "toolchain t3: the close gate names a no-git code when git is broken" "CG-NO-GIT"

# The scope hook's fail-open was one level further in: a broken git makes the
# branch read empty, empty never equals the trunk, and the gate exits 0 on a
# write it exists to warn about.
run_hook_brokentool "$HOOKS/scope-hook.sh" "$SC" "$(edit_payload "$SC/src/app.js")"
expect_deny "toolchain t4: the scope hook names a no-git code when git is broken" "SH-NO-GIT"

# CONTROL, and it is the one that keeps t3 honest: with git broken, a payload
# this gate does NOT govern must stay silent. Without it the fix could have
# turned every Bash call into a warning and t3 would still pass.
run_hook_brokentool "$HOOKS/close-gate.sh" "$CL" "$(bash_payload 'ls -la')"
expect_allow "toolchain t5 control: broken git, ungoverned payload, still silent"

# F3-2026: THE THIRD SIBLING of the same probe, reinstated in the 2.3.0 cycle
# from the patch parked with its backlog entry. V19-F1 fixed t3 and t4 in the
# 2.2.0 cycle and left commit-gate.sh alone, so a broken git made ADDED read
# empty, every grep over it miss, and a staged em-dash AND a staged secret both
# report clean at exit 0 with no output.
#
# Asserted on the CODE for its siblings' reason: this gate denies an em-dash
# anyway when git works, so "did it deny" would pass with or without the probe.
run_hook_brokentool "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "x"')"
expect_deny "toolchain t6 (F3-2026): the commit gate names a no-git code when git is broken" "CM-NO-GIT"

# F11-2026: THE ADVISORY JSON CONTRACT, asserted on the FIELD and not on the
# reason text, which is the whole reason this survived three adversarial legs.
# advise_literal() hardcoded "code":"" while the gates' frozen header promises
# setlistAdvisory {gate, verdict, code, reason}. It never blocked, so nothing
# ever failed on it: 1.1.0 filed it as F21, 2.0.0 filed it as F12 with a full
# reproduction, and both times it was rediscovered rather than fixed. The suite
# could not notice a regression here at all until this assertion existed.
#
# The literal path is reached with jq ABSENT, which is what that path is for.
run_hook_nojq "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "x"')"
F11_CODE="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.code // "<absent>"' 2>/dev/null)"
if [[ -n "$F11_CODE" && "$F11_CODE" != "<absent>" && "$F11_CODE" =~ ^[A-Z][A-Z0-9-]*$ ]]; then
  ok "F11-2026: a literal-reason deny carries a real setlistAdvisory.code ($F11_CODE), not the empty string"
else
  bad "F11-2026: a literal-reason deny carries a real setlistAdvisory.code, not the empty string" \
      "code=[$F11_CODE]; the gates' own frozen header promises this field and the literal path has emitted an empty one since 1.1.0"
fi

# KL4-A1: the advisory gate is NOT path-scoped, it still is not, and it now SAYS
# SO. The ruling of 2026-08-28 closed the divergence by honesty rather than by
# coupling, so this asserts the SENTENCE and leaves the pinned divergence
# assertion below exactly as it was: the entry does not close by drift and this
# is not a claim that it did.
KL4A1_OUT=0
for kl4a1_case in "$EMDASH" 'api_key = "abcdefghijklmnop1234"'; do
  run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "x"')" 2>/dev/null || true
done
printf 'a %s b\n' "$EMDASH" > "$CG/note.md"
git -C "$CG" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'git commit -m "x"')"
if printf '%s' "$HOOK_OUT" | grep -q 'evaluated at the git-hook layer, and this advisory does not read them'; then
  ok "KL4-A1: the advisory gate's refusal states that path exclusions are evaluated at the git-hook layer and not here"
else
  bad "KL4-A1: the advisory gate's refusal states that path exclusions are evaluated at the git-hook layer and not here" \
      "the user still cannot tell from this message whether the commit will actually be blocked, which is the measured harm the ruling priced"
fi
git -C "$CG" rm -q -f --cached note.md >/dev/null 2>&1; rm -f "$CG/note.md"


# The blast radius stays narrow in this state too: the session must still be
# able to run the command that repairs jq.
run_hook_brokenjq "$HOOKS/commit-gate.sh" "$CG" "$(bash_payload 'apt-get install -y jq')"
expect_allow "broken-jq j4: unrelated Bash commands still run, so jq can be repaired"

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

# --- the release block (D1, edition v1.7) ---------------------------------------
#
# The block is a DECLARATION, so what the suite pins is that the stamp ships the
# documented default and that the default is the one the skills are written
# against. An instance stamped with a different default would make checkpoint's
# "an absent block reads as none" rule and validate's check 13 disagree with the
# tree they run on.
STAMP_RELEASE="$(jq -r '.release.model // empty' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null || true)"
if [[ "$STAMP_RELEASE" == "none" ]]; then
  ok "release block: a stamped instance declares the documented default (model: none)"
else
  bad "release block: a stamped instance declares the documented default (model: none)" \
      "sdd.json records release.model '${STAMP_RELEASE:-<absent>}'"
fi
# Ordering, per the sdd.json shape contract in STAMP-TREE.md: framework blocks
# APPEND after the flat repo facts rather than reordering them, so an instance's
# file grows by addition and every reader can keep treating an absent block as
# "stamped before that block existed".
if jq -e 'keys_unsorted | index("release") > index("plugin")' "$STAMP_TARGET/.claude/sdd.json" >/dev/null 2>&1; then
  ok "release block: it appends after the plugin block rather than reordering the file"
else
  bad "release block: it appends after the plugin block rather than reordering the file" \
      "key order is $(jq -c 'keys_unsorted' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null)"
fi
# The three models the edition names, read from the edition rather than retyped,
# so a model added to Part 6 and not to this list fails here.
for rel_model in none tags version-file; do
  if bash "$SCRIPTS/part.sh" 6 "$ROOT/setlist.md" 2>/dev/null | grep -qF -- "\`$rel_model\`"; then
    ok "release block: Part 6 documents the '$rel_model' model"
  else
    bad "release block: Part 6 documents the '$rel_model' model" "the release rail section does not name it"
  fi
done

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
  local matcher='Write|Edit|MultiEdit|NotebookEdit' t1='"timeout": 120,' t2='"timeout": 300,' t3='"timeout": 1800,' t4='"timeout": 60,'
  local gates_block=1
  case "$wiring" in
    stale-matcher) matcher='Write|Edit' ;;
    no-timeouts)   t1='' ; t2='' ; t3='' ; t4='' ;;
    missing)       return 0 ;;
    no-gates)      gates_block=0 ;;
  esac
  # The command paths must be the REAL ones. The wiring check identifies this
  # plugin's own hook entries by their command pointing into .claude/hooks/,
  # so a fixture using a made-up path is not an instance: it is a settings file
  # with no Setlist hooks in it, and every check would vacuously pass. Found by
  # the 1.0.4 rewrite, and it is the same lesson the upgrade-seam leg exists
  # for: a fixture is only evidence to the extent it matches the real artifact.
  #
  # ALL FOUR hooks are wired, including the SessionStart re-grounding hook. Until
  # 1.0.7 this fixture wired three and omitted SessionStart, so it was not an
  # instance: it was an instance with a hook permanently disarmed, and every case
  # built on it asserted against a shape no scaffold produces. It went unnoticed
  # because nothing yet checked that a stamped hook was wired AT ALL, which is
  # the same blind spot as the defect (B5) that made this check necessary. The
  # fixture and the checker were incomplete in exactly the same place.
  local gates=''
  if [[ "$gates_block" -eq 1 ]]; then
    gates=",
      { \"matcher\": \"Bash\",
        \"hooks\": [ { \"type\": \"command\", $t2 \"command\": \"\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/commit-gate.sh\" },
                   { \"type\": \"command\", $t3 \"command\": \"\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/close-gate.sh\" } ] }"
  fi
  cat > "$d/.claude/settings.json" <<SETTINGS
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "$matcher",
        "hooks": [ { "type": "command", $t1 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/scope-hook.sh" } ] }$gates
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", $t4 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/regrounding-hook.sh" } ] }
    ]
  }
}
SETTINGS
  jq -e . "$d/.claude/settings.json" >/dev/null 2>&1 || {
    printf 'instance_fixture: produced settings.json that does not parse (wiring=%s)\n' "$wiring" >&2
    return 1
  }
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

# --- the refresh DELIVERS the git-hook boundary (v1.7 dogfood BLOCKER) ----------
#
# Found by the Phase 5 dogfood gate, and it is plugin 1.0.3's defect restated:
# refresh-instance.sh copied what it knew about (the four PreToolUse hooks),
# reported the instance current, recorded plugin 1.1.0, and delivered NO
# .githooks/, NO core.hooksPath and NO merge.ff. So a freshly stamped instance
# had the v1.7 boundary and an UPGRADED one did not, while both claimed the same
# version.
#
# It was worse than 1.0.3's version. v1.7 also DEMOTES the PreToolUse layer to
# advisory and reclassifies its bypasses from BLOCKER to MAJOR, so an upgraded
# instance would have been strictly WEAKER after the upgrade than before it,
# and told it was current.
INST="$WORK/inst-boundary"
instance_fixture "$INST" 1.0.9
# A real instance is a git work tree, and the two config settings can only exist
# in one. The shared fixture is not git-initialised, so this case initialises it
# rather than changing a fixture the other refresh cases depend on.
git_init "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
for gh in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
  if [[ -f "$INST/.githooks/$gh" ]] && cmp -s "$ROOT/templates/git-hooks/$gh" "$INST/.githooks/$gh"; then
    ok "refresh boundary: .githooks/$gh is delivered byte-identical to the template"
  else
    bad "refresh boundary: .githooks/$gh is delivered byte-identical to the template" \
        "an upgraded instance does not carry the file the edition calls the guarantee"
  fi
done
for gh in pre-commit pre-merge-commit pre-push; do
  if [[ -x "$INST/.githooks/$gh" ]]; then
    ok "refresh boundary: .githooks/$gh is executable"
  else
    bad "refresh boundary: .githooks/$gh is executable" "git skips a non-executable hook SILENTLY, so this is a boundary that stops nothing and says nothing"
  fi
done
# THE HOOK'S OWN TOOL MUST BE DELIVERED WITH IT (v1.7 gate session 4, leg F2).
#
# pre-push resolves trunk-audit.sh from $CLAUDE_PLUGIN_ROOT/scripts/ or from
# .claude/hooks/trunk-audit.sh. Neither the stamp nor the refresh had ever
# installed the second, and the first is unset in any ordinary terminal, so a
# stamped instance refused every push from outside a Claude Code session with
# "cannot find trunk-audit.sh". Delivering a hook without the tool it runs is
# delivering a boundary that only fails.
if [[ -f "$INST/.claude/hooks/trunk-audit.sh" ]]; then
  ok "refresh boundary: trunk-audit.sh is delivered where pre-push looks for it"
else
  bad "refresh boundary: trunk-audit.sh is delivered where pre-push looks for it" \
      "pre-push falls back to .claude/hooks/trunk-audit.sh when CLAUDE_PLUGIN_ROOT is unset, which is every ordinary terminal, and it is not there"
fi

if [[ "$(git -C "$INST" config --get core.hooksPath 2>/dev/null || true)" == ".githooks" ]]; then
  ok "refresh boundary: core.hooksPath points at the tracked directory"
else
  bad "refresh boundary: core.hooksPath points at the tracked directory" \
      "without it git runs .git/hooks and every delivered file above is inert"
fi
if [[ "$(git -C "$INST" config --get merge.ff 2>/dev/null || true)" == "false" ]]; then
  ok "refresh boundary: merge.ff is false after the refresh"
else
  bad "refresh boundary: merge.ff is false after the refresh" \
      "a fast-forward merge fires NO git hook, so without this the boundary has a hole the size of one flag"
fi

# --- refusal: a DELIVERY that could not deliver (F1, verdict leg) ---------------
#
# refresh-instance.sh --apply read neither `git config` write's exit status, so
# an instance whose config write failed still got "delivered the git-hook
# boundary" on stdout, had the new plugin version recorded, and exited 0 with
# core.hooksPath unset and therefore every git hook inert. A positive claim of
# delivery that was never checked is worse than a silent failure: nothing tells
# the operator to look again.
#
# The lock file is how a config write is made to fail without root or a
# read-only filesystem: git takes .git/config.lock before writing and refuses if
# it already exists.
INST="$WORK/inst-cfgfail"
instance_fixture "$INST" 1.0.0
# instance_fixture does NOT create a git repository, and refresh-instance.sh
# only reaches its config writes inside a work tree. Without this the lock file
# below cannot be created and the healthy control never sets core.hooksPath
# either, so every assertion here would report the same result on both trees and
# discriminate nothing. Caught by watching these fail red on BOTH sides.
git_init "$INST"
: > "$INST/.git/config.lock"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh cfgfail: a failed config write refuses instead of claiming delivery" 1 "FAILED"
if printf '%s' "$SCRIPT_OUT" | grep -q "delivered the git-hook boundary"; then
  bad "refresh cfgfail2: a failed delivery does NOT claim it delivered the boundary" \
      "the summary announced the git-hook boundary delivered while core.hooksPath was never set"
else
  ok "refresh cfgfail2: a failed delivery does NOT claim it delivered the boundary"
fi
REFRESH_REC="$(jq -r '.plugin.version // "none"' "$INST/.claude/sdd.json" 2>/dev/null)" # fail-open-ok: an unreadable file yields "none", which fails the comparison below, and that is the correct answer for an instance whose sdd.json did not survive
if [[ "$REFRESH_REC" == "1.0.0" ]]; then
  ok "refresh cfgfail3: the version is NOT recorded when the boundary was not delivered"
else
  bad "refresh cfgfail3: the version is NOT recorded when the boundary was not delivered" \
      "sdd.json records [$REFRESH_REC]; an instance must never claim a version whose boundary it does not carry"
fi

# THE CONTROL. Without it every assertion above is satisfied by a script that
# refuses every refresh, which is the false-denial direction.
INST="$WORK/inst-cfgok"
instance_fixture "$INST" 1.0.0
git_init "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
REFRESH_HP="$(git -C "$INST" config --get core.hooksPath 2>/dev/null || printf unset)" # fail-open-ok: an unset value is printed as "unset" and fails the test below, which is the finding rather than a skipped check
if [[ "$REFRESH_HP" == ".githooks" ]]; then
  ok "refresh cfgok: the healthy path still delivers the boundary"
else
  bad "refresh cfgok: the healthy path still delivers the boundary" \
      "core.hooksPath reads [$REFRESH_HP], so the refusal above is not discriminating"
fi

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

# THE SAME CASE IN ITS REAL SHAPE (1.0.7, F23). The fixture above puts the
# foreign hook's command at `npx prettier --write`, which is not a path into
# .claude/hooks/ at all, so it was excluded by the one condition 1.0.4's
# selector actually tested. A project hook LIVING WHERE PROJECT HOOKS LIVE was
# never tried, and that is the case that still failed: the selector matched the
# directory, so .claude/hooks/prettier.sh counted as Setlist's, and its missing
# timeout produced an exit 3 no edit to Setlist's wiring could clear.
#
# A fixture that cannot express a finding is not evidence against it. This case
# carried the name of the defect for three releases while testing the one
# spelling that already worked.
INST="$WORK/inst-foreign-hook-in-dir"
instance_fixture "$INST" 1.0.0 current
printf '#!/usr/bin/env bash\nexit 0\n' > "$INST/.claude/hooks/prettier.sh"
chmod +x "$INST/.claude/hooks/prettier.sh"
jq '.hooks.PostToolUse=[{matcher:"Write",hooks:[{type:"command",command:"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prettier.sh"}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring h2: a foreign hook INSIDE .claude/hooks/ is still not Setlist's" 0 "refreshed the four stamped hooks"
if printf '%s' "$SCRIPT_OUT" | grep -q prettier; then
  bad "wiring h2: the report must not name a hook the project owns" \
      "prettier.sh was named as a Setlist entry: $SCRIPT_OUT"
else
  ok "wiring h2: the report does not name the project's own hook"
fi

# THE GATES MUST BE WIRED AT ALL (1.0.7, B5/F5). Every wiring case above finds
# fault with an entry that is PRESENT: a stale matcher, a missing timeout, a
# malformed file. Delete the two gate entries outright and there was nothing
# left to object to, so the refresh reported a complete apply, exit 0, and told
# the operator the refreshed gates would bind from the next session, of a pair
# of gates that would never bind again.
#
# This is the seam that carried plugin 1.0.3's worst defect. An upgrade path
# that certifies a disarmed instance is worse than no check at all: it turns
# "verify this yourself" into "this was verified".
INST="$WORK/inst-gates-unwired"
instance_fixture "$INST" 1.0.0 no-gates
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring m: both gates unwired exits INCOMPLETE and names them" 3 "commit-gate.sh" "close-gate.sh"

# The hook FILES are current in that instance, which is the whole trap: byte
# freshness and enforcement are different claims, and the first was being
# reported as though it settled the second.
if cmp -s "$HOOKS/commit-gate.sh" "$INST/.claude/hooks/commit-gate.sh"; then
  ok "wiring m2: the unwired instance's hook bytes ARE current, so freshness is not enforcement"
else
  bad "wiring m2: the unwired instance's hook bytes should still have been refreshed" \
      "an INCOMPLETE refresh still copies the files; only the wiring is outstanding"
fi

# And the inverse, so "names them" cannot be satisfied by naming them always.
INST="$WORK/inst-gates-wired"
instance_fixture "$INST" 1.0.0 current
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
if printf '%s' "$SCRIPT_OUT" | grep -q 'NOTHING IN'; then
  bad "wiring m3: a fully wired instance must not be reported as unwired" \
      "the unwired message fired on a complete instance: $SCRIPT_OUT"
else
  ok "wiring m3: a fully wired instance is not reported as unwired"
fi

# =============================================================================
# 1.0.8 (leg 4, F2): WIRED MEANS THIS INSTANCE'S FILE, NOT A FILE WITH THAT NAME.
#
# The predicate above was tightened on 2026-07-28 from a bare substring match to
# an anchored pattern, and the anchored pattern still asked about SHAPE:
#
#   ^[^ ]*/[.]claude/hooks/<name>[.]sh([^ ]*)?( |$)
#          ^^^^^^                          ^^^^^^^
#          any root                        any suffix
#
# So `close-gate.sh.disabled` was Setlist's close gate, and so was a sibling
# package's copy in a monorepo, and so was one under $HOME or /opt. Renaming a
# hook to `.disabled` is exactly how a person turns a gate off. The instance
# reported zero wiring gaps, --apply exited 0, and printed "the refreshed gates
# bind from the NEXT session onward" about a gate that would never bind.
#
# The 2026-07-28 fix closed the two examples its own comment named (a fork one
# level deeper, a bare mention) and not the class around them. That is the same
# stop-at-the-example error as the heading-depth range in the report checker,
# twice in two days, which is why these cases are written as a LOOP OVER THE SET
# rather than as the two spellings a finding happened to report.
#
# The upgrade path is the one surface a user cannot check by hand, and its whole
# purpose since 1.0.7 is to notice a disarmed instance.
rewire() { # rewire <settings.json> <hook-name> <new-command-string>
  jq --arg h "$2" --arg c "$3" '
    walk(if type == "object" and has("command") and ((.command // "") | test($h))
         then .command = $c else . end)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# Every spelling below names a file that is NOT the one this script stamps at
# $INSTANCE/.claude/hooks/<name>.sh, so every one must report UNWIRED. Run
# against all four stamped hooks, because a predicate that is right for the
# close gate and wrong for the scope hook is the defect one file over.
for h in scope-hook commit-gate close-gate regrounding-hook; do
  for spell in \
    'SUFFIX-disabled|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh.disabled' \
    'SUFFIX-orig|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh.orig' \
    'SUFFIX-wrapper|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.shell-wrapper' \
    'ROOT-sibling|"$CLAUDE_PROJECT_DIR"/packages/api/.claude/hooks/HOOK.sh' \
    'ROOT-home|$HOME/.claude/hooks/HOOK.sh' \
    'ROOT-vendor|/opt/vendor/.claude/hooks/HOOK.sh' \
    'FORK-deeper|"$CLAUDE_PROJECT_DIR"/.claude/hooks/local/HOOK.sh'
  do
    label="${spell%%|*}"; cmd="${spell#*|}"; cmd="${cmd//HOOK/$h}"
    INST="$WORK/inst-disarm-$h-$label"
    instance_fixture "$INST" 1.0.0 current
    rewire "$INST/.claude/settings.json" "$h" "$cmd"
    run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
    expect_script "disarm $h/$label: a command that does not run this instance's $h.sh is UNWIRED" 3 "$h.sh"
  done
done

# The other direction, which is the one that makes the check usable rather than
# merely strict: every spelling this script actually stamps, plus the literal
# absolute path an instance may legitimately be wired with, must stay WIRED. A
# predicate that reports everything unwired would pass every case above and be
# worthless.
for spell in \
  'quoted-var|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh' \
  'braced-var|${CLAUDE_PROJECT_DIR}/.claude/hooks/HOOK.sh' \
  'quoted-braced|"${CLAUDE_PROJECT_DIR}"/.claude/hooks/HOOK.sh' \
  'bare-var|$CLAUDE_PROJECT_DIR/.claude/hooks/HOOK.sh'
do
  label="${spell%%|*}"; tmpl="${spell#*|}"
  INST="$WORK/inst-armed-$label"
  instance_fixture "$INST" 1.0.0 current
  for h in scope-hook commit-gate close-gate regrounding-hook; do
    rewire "$INST/.claude/settings.json" "$h" "${tmpl//HOOK/$h}"
  done
  run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
  expect_script "armed $label: a spelling this script stamps stays WIRED" 0 "refreshed the four stamped hooks"
done

# THE ENUMERATED-SET RESTRICTION, pinned as the documented Known-limitations
# bullet says (2.4.0 leg F11): `bash <stamped path>` genuinely runs the gate,
# and the check still reports it NOT WIRED, because the set is the spellings
# settings.json.tmpl ships and nothing else. Fails safe (over-reports, never
# certifies a disarmed instance). If this pin flips, the set was widened:
# widen the bullet in the same commit.
INST="$WORK/inst-bash-prefix"
instance_fixture "$INST" 1.0.0 current
rewire "$INST/.claude/settings.json" "close-gate" 'bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/close-gate.sh'
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring restriction (2.4.0 leg F11, documented): an interpreter-prefixed spelling that runs the stamped file is still reported NOT WIRED" 3 "close-gate.sh"

# The absolute path of the instance itself, which cannot be templated above
# because it is only known at run time.
INST="$WORK/inst-armed-absolute"
instance_fixture "$INST" 1.0.0 current
INST_ABS="$(cd "$INST" && pwd)"
for h in scope-hook commit-gate close-gate regrounding-hook; do
  rewire "$INST/.claude/settings.json" "$h" "$INST_ABS/.claude/hooks/$h.sh"
done
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "armed absolute: this instance's own absolute path stays WIRED" 0 "refreshed the four stamped hooks"

# And an entry that is not a command hook does not run a command however its
# string reads, so it cannot arm a gate.
INST="$WORK/inst-disarm-type"
instance_fixture "$INST" 1.0.0 current
jq 'walk(if type == "object" and has("command") and ((.command // "") | test("close-gate"))
         then .type = "output" else . end)' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "disarm type: an entry whose type is not 'command' does not arm the close gate" 3 "close-gate.sh"

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

# THE SCOPE-MATCHER CERTIFICATION, AS COVERAGE (F3 with V19-F5 and V19-F10, and
# F5's three spellings). One block, because they are one function and three
# separate repairs to one predicate is how the second reintroduces the first.
#
# Watched RED first, every subject, on the pre-fix bytes: the substring test
# certified `Write|Edit|MultiEdit|NotebookEditor` and `Write|NotebookEdit` CLEAN,
# `| first` reported a two-entry instance whose union covers everything as
# unwired, and all three match-all spellings were read as covering nothing.
# The comma case "passed" before the fix for the WRONG reason (the substring
# search found the token inside it), which is F3 in one line.
sm_settings() { # sm_settings <matcher-json>... -> a settings.json body
  local entries="" m
  for m in "$@"; do
    [[ -n "$entries" ]] && entries="$entries,"
    entries="$entries{\"matcher\":$m,\"hooks\":[{\"type\":\"command\",\"command\":\"\$CLAUDE_PROJECT_DIR/.claude/hooks/scope-hook.sh\",\"timeout\":10}]}"
  done
  printf '{"hooks":{"PreToolUse":[%s],"SessionStart":[]}}' "$entries"
}
sm_case() { # sm_case <label> <want: GAP|CLEAN> <matcher-json>...
  local label="$1" want="$2"; shift 2
  local inst="$WORK/inst-sm"; rm -rf "$inst"
  instance_fixture "$inst" 1.0.0 current
  sm_settings "$@" > "$inst/.claude/settings.json"
  run_script bash "$SCRIPTS/refresh-instance.sh" "$inst"
  local got
  if printf '%s' "$SCRIPT_OUT" | grep -qiE 'scope hook.*(does not cover|do not cover|not wired|could not be)'; then got=GAP; else got=CLEAN; fi
  if [[ "$got" == "$want" ]]; then
    ok "scope coverage [$label]"
  else
    bad "scope coverage [$label]" \
        "wanted $want, measured $got. The matcher set is judged by COVERAGE over Write/Edit/MultiEdit/NotebookEdit, taking the UNION of every entry that runs the scope hook, with a catch-all treated as match-all and a comma spelling translated first. A substring search over the first entry is what this replaced."
  fi
}
sm_case "a matcher CONTAINING the token but covering nothing" GAP '"Write|Edit|MultiEdit|NotebookEditor"'
sm_case "a matcher missing Edit and MultiEdit"                GAP '"Write|NotebookEdit"'
sm_case "control: the correct matcher certifies clean"      CLEAN '"Write|Edit|MultiEdit|NotebookEdit"'
sm_case "two entries whose UNION covers everything"         CLEAN '"Write|Edit"' '"MultiEdit|NotebookEdit"'
sm_case "match-all *"                                       CLEAN '"*"'
sm_case "match-all empty"                                   CLEAN '""'
sm_case "match-all absent"                                  CLEAN 'null'
sm_case "the comma spelling"                                CLEAN '"Write,Edit,MultiEdit,NotebookEdit"'
sm_case "control: no scope-hook entry at all is a gap"        GAP

# F10: the advisory backup notice ends its own line. It was printed without a
# trailing newline at two call sites, so the one line telling an operator a
# foreign file was replaced was glued onto the success line.
if grep -qE "printf 'refresh-instance\.sh: %s' " "$SCRIPTS/refresh-instance.sh"; then
  bad "F10: the advisory backup notice ends with a newline" \
      "a call site still prints it without one, so the notice is glued to the next line"
else
  ok "F10: the advisory backup notice ends with a newline"
fi

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
# A chore/ ref sitting on the unclosed spec branch's commit, added 2026-07-28.
#
# It is here rather than in a single dedicated test on purpose: with this ref in
# the shared corpus, EVERY close-gate assertion below runs with a chore sibling
# present, so a regression in the spec-versus-chore tie-break turns dozens of
# assertions red instead of one. 1.0.8 shipped that regression and the whole
# corpus stayed green, because the fixture held the repository constant while
# varying only the command.
#
# The state is ordinary, not adversarial: `git checkout -b chore/wip
# <spec-branch>` and promoting a chore branch to a spec branch both leave two
# refs on one commit, and Part 5b makes chore branches first-class.
git -C "$CORP" branch -f chore/cleanup spec/0001-thing
git -C "$CORP" update-ref refs/remotes/origin/main "$(git -C "$CORP" rev-parse main)"
git -C "$CORP" branch -f release/2.0 main

# corpus_verdict <command> -> echoes deny|allow|error
#
# THE THIRD STATE IS F9-2026, AND IT IS THIS REPOSITORY'S SIGNATURE DEFECT
# SITTING INSIDE THE SUITE THAT IS THE FIRST ITEM OF THE A1 TIER.
#
# This function returned deny or allow, and everything that was not a deny
# collapsed to `allow`: a crashed hook, a nonzero exit, output that is not JSON,
# a hook that never ran at all. So "the gate ALLOWED this" and "the gate
# produced nothing" were the same answer, and ~60 call sites below cannot tell
# them apart. That is the same shape as the macOS leg reading `tail`'s exit code
# and the attestation matching a version string: a check whose FAILURE cannot
# reach a verdict.
#
# The states, and the boundary between the last two is the whole fix:
#   deny   the gate produced a verdict and it is deny
#   allow  the gate exited 0 AND either said nothing (allow is silence, which is
#          this layer's documented contract) or produced parseable JSON whose
#          verdict is not deny
#   error  the gate exited NONZERO, or produced output that is not parseable
#          JSON. Neither of those is an allow, and calling them one is the
#          defect.
#
# `error` is deliberately not equal to `allow`, so every existing call site that
# tests `== "allow"` now fails on a crashed gate instead of passing on one. That
# is the point: the fix is worth nothing if the new state is swallowed by the
# comparison it exists to correct.
corpus_verdict() {
  local out rc verdict
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'error'; return; fi
  # Silence is the documented allow. Anything else must PARSE before it is read.
  if [[ -z "$out" ]]; then printf 'allow'; return; fi
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then printf 'error'; return; fi
  verdict="$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [[ "$verdict" == "deny" ]]; then printf 'deny'; else printf 'allow'; fi
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

# CONTROL C (F9-2026): the harness can observe an ERROR, and it is not an allow.
#
# Without this the third state is a claim rather than a capability, which is the
# vacuous-comparison family the two controls above already guard against one
# state at a time. A distinguishing input is constructed rather than waited for:
# a stand-in gate that exits nonzero having printed nothing is exactly the shape
# that used to read as `allow`, and the second case is the unparseable-output
# shape, which used to read as `allow` too.
CORP_REALHOOKS="$HOOKS"
HOOKS="$WORK/corp-brokenhook"; rm -rf "$HOOKS"; mkdir -p "$HOOKS"
printf '#!/usr/bin/env bash\nexit 3\n' > "$HOOKS/close-gate.sh"
CORP_V_CRASH="$(corpus_verdict 'git status')"
printf '#!/usr/bin/env bash\nprintf "not json at all\\n"\n' > "$HOOKS/close-gate.sh"
CORP_V_GARBAGE="$(corpus_verdict 'git status')"
HOOKS="$CORP_REALHOOKS"
if [[ "$CORP_V_CRASH" == "error" && "$CORP_V_GARBAGE" == "error" ]]; then
  ok "corpus control c (F9-2026): a crashed gate and an unparseable gate both read as error, not as allow"
else
  bad "corpus control c (F9-2026): a crashed gate and an unparseable gate both read as error, not as allow" \
      "nonzero-exit read as [$CORP_V_CRASH], unparseable output read as [$CORP_V_GARBAGE]; while either is 'allow', a corpus assertion that passes because the gate never ran is indistinguishable from one that passes because the gate decided"
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

corpus_verdict_reason() { # corpus_verdict_reason <command> -> the deny reason text
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  printf '%s' "$out" | jq -r '.setlistAdvisory.reason // .hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

# --- the DENY-CODE axis (1.0.8, routine item 4) ------------------------------
# Every deny carries a stable bracketed CODE, so an assertion can test the
# gate's IDENTITY instead of its prose. Backlog item 4's trigger was concrete:
# B2 reworded the commit gate's deny and dogfood/hook-smoke.sh still asserted
# the old wording, so a green suite sat beside a red smoke and neither the badge
# nor the publish could see it. A reworded message should never break a test,
# and a test should never pass because two different denials happen to share a
# phrase.
#
# Asserted STRUCTURALLY rather than one code at a time: every deny site in every
# stamped hook must carry a code, so adding a new deny without one fails here
# rather than being noticed later by whoever greps for it.
DC_MISSING=""
for hookfile in "$HOOKS"/close-gate.sh "$HOOKS"/commit-gate.sh "$HOOKS"/scope-hook.sh; do
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s' "$line" | grep -qE '\[(CG|CM|SH)-[A-Z0-9-]+\]' || DC_MISSING="$DC_MISSING
    $(basename "$hookfile"): $(printf '%s' "$line" | cut -c1-72)"
  done <<DCEOF
$(grep -hE '^\s*deny(_literal)? "' "$hookfile")
DCEOF
done
if [[ -z "$DC_MISSING" ]]; then
  ok "deny codes: every deny site in every stamped hook carries a stable code"
else
  bad "deny codes: a deny without a code cannot be asserted except by its prose" \
      "these carry no [XX-CODE]:$DC_MISSING"
fi

# The codes must be UNIQUE, or two different failures are indistinguishable to
# any assertion that uses them, which is the defect this axis exists to remove
# wearing a different hat.
DC_DUPES="$(grep -ohE '\[(CG|CM|SH)-[A-Z0-9-]+\]' "$HOOKS"/close-gate.sh "$HOOKS"/commit-gate.sh "$HOOKS"/scope-hook.sh | sort | uniq -d)"
if [[ -z "$DC_DUPES" ]]; then
  ok "deny codes: every code is unique across the stamped hooks"
else
  bad "deny codes: two denials sharing a code cannot be told apart" "duplicated: $DC_DUPES"
fi

# And the code must actually REACH the agent, not merely exist in the source.
# The reason string is what the harness delivers verbatim, so it is read back
# out of a real deny rather than assumed to have survived.
if printf '%s' "$(corpus_verdict_reason 'git merge --no-ff spec/0001-thing')" | grep -q 'CG-'; then
  ok "deny codes: the code survives into the reason the agent actually receives"
else
  bad "deny codes: a code that does not reach the agent is not an interface" \
      "the delivered reason carried no CG- code"
fi

# --- the SDD-SHAPE axis (1.0.8, F1) -----------------------------------------
# `jq -e .` tests JSON VALIDITY, not SHAPE. Two perfectly valid inputs disabled
# the trunk rule in BOTH the close gate and the scope hook, in silence:
# a top-level array (so `.trunk` errors and TRUNK reads empty) and TWO documents
# in one file (so `.trunk` prints twice and TRUNK reads two lines). Neither needs
# an attacker: a hand-edited file and a half-merged config produce exactly these.
for shape in 'array' 'multidoc'; do
  SH="$WORK/inst-shape-$shape"
  close_fixture "$SH" no no answered no no true
  case "$shape" in
    array)    printf '[]' > "$SH/.claude/sdd.json" ;;
    multidoc) printf '{"trunk":"main"}\n{"trunk":"main"}\n' > "$SH/.claude/sdd.json" ;;
  esac
  # It really IS valid JSON to jq, which is the whole point of the finding.
  if [[ "$shape" == "array" ]]; then
    assert_true "sdd-shape $shape 0: the fixture is valid JSON, so validity is not the test" \
      "the fixture is malformed, so this case would pass for the wrong reason" \
      jq -e . "$SH/.claude/sdd.json"
  fi
  run_hook "$HOOKS/close-gate.sh" "$SH" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
  expect_deny "sdd-shape $shape a: the close gate refuses a config that is not one object" "JSON OBJECT"
  OUT="$(jq -nc --arg p "$SH/src/app.js" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' \
        | CLAUDE_PROJECT_DIR="$SH" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    ok "sdd-shape $shape b: the scope hook refuses it too, so the trunk rule is not silently off"
  else
    bad "sdd-shape $shape b: the scope hook must refuse a config it cannot read a trunk from" \
        "a $shape sdd.json disabled the trunk rule and the write reached the trunk"
  fi
done

# --- the QUOTED-CONTENT axis (1.0.8, B1/B3b and F4 to F7) -------------------
# The two gates handled quoting in the way that was wrong for the other. The
# close gate deleted quote CHARACTERS and kept their contents, so free text was
# fed to the parser as code; the commit gate deleted quoted SPANS, so quoting a
# word deleted the word it matches on. A quoted span of one shell-safe word is
# now kept as that word and anything else becomes an inert token.
#
# The dimensions here are the four that each produced a finding: quote character,
# POSITION (binary, subcommand, ref, message), and content (bare word, words with
# spaces, words containing a separator, words containing a git command).
QC_FAIL=""
for payload in \
  'git commit -m "todo (git checkout spec/0002-other)" && git merge --no-ff spec/0001-thing' \
  'echo "x && git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  'echo "x; git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  "git commit -m 'wip (git checkout spec/0002-other)' && git merge --no-ff spec/0001-thing" \
  'git merge --no-ff -m "closes spec/0003-done" spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_FAIL="$QC_FAIL
    $payload"
done
if [[ -z "$QC_FAIL" ]]; then
  ok "corpus quoted content: quoted text cannot donate a command or a segment boundary"
else
  bad "corpus quoted content: a quoted span must not contribute code" \
      "these reached the trunk unchecked:$QC_FAIL"
fi

# THE ARGUMENT DIRECTION, which is why the commit gate's span-dropping repair
# was reverted when it was tried on this gate: a quoted REF must still be read.
QC_ARG_FAIL=""
for payload in \
  'git merge "spec/0001-thing"' \
  "git merge 'spec/0001-thing'" \
  'git merge --no-ff "spec/0001-thing" -m "close"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_ARG_FAIL="$QC_ARG_FAIL
    $payload"
done
if [[ -z "$QC_ARG_FAIL" ]]; then
  ok "corpus quoted content: a quoted REF is still read, so the span is not simply dropped"
else
  bad "corpus quoted content: dropping quoted spans loses the branch name" \
      "these stopped being seen as merges at all:$QC_ARG_FAIL"
fi


# THE PLACEHOLDER MUST NOT BE FORGEABLE. `@@Q@@` is what a multi-word quoted
# span becomes, so a payload can type it literally and ask whether the gate
# treats its own internal marker as data. It must: the token is inert by
# construction (it is not a command word, not a separator and not a ref), but
# "inert by construction" is a claim, and this repo has been bitten by claims
# that were reasoned rather than asserted.
QC_TOK_FAIL=""
for payload in \
  'echo @@Q@@ && git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing @@Q@@' \
  'git commit -m "@@Q@@ git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_TOK_FAIL="$QC_TOK_FAIL
    $payload"
done
if [[ -z "$QC_TOK_FAIL" ]]; then
  ok "corpus quoted content: a literal @@Q@@ in the payload cannot hide a merge"
else
  bad "corpus quoted content: the internal placeholder must be inert as INPUT too" \
      "these escaped by typing the marker:$QC_TOK_FAIL"
fi
# And it gets NO privileged treatment: a trunk merge naming it is a merge whose
# target the gate cannot establish, so it refuses, exactly as it does for any
# other unresolvable ref. The first cut of this case expected an ALLOW and the
# gate was right and the test was wrong, which is worth leaving in the record:
# an unresolvable merge target denies, and the placeholder is not an exception
# to that in either direction.
if [[ "$(corpus_verdict 'git merge --no-ff @@Q@@')" == "deny" ]]; then
  ok "corpus quoted content: the placeholder is treated as an unresolvable ref, not as a special case"
else
  bad "corpus quoted content: @@Q@@ must be refused like any ref the gate cannot resolve" \
      "it was allowed, which means the marker is being special-cased somewhere"
fi

# AND THE ALLOW DIRECTION. A message is not code, and must not become a denial
# just because it contains words that look like one.
QC_ALLOW_FAIL=""
for payload in \
  'git commit -m "merge spec/0001-thing when review is done"' \
  'echo "git merge --no-ff spec/0001-thing"' \
  'git commit -m "an ordinary message"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_ALLOW_FAIL="$QC_ALLOW_FAIL
    $payload"
done
if [[ -z "$QC_ALLOW_FAIL" ]]; then
  ok "corpus quoted content: a message mentioning a merge is not a merge"
else
  bad "corpus quoted content: opaque tokens must not turn messages into denials" \
      "these were denied:$QC_ALLOW_FAIL"
fi

# --- the ESCAPE axis (leg 4, F5 and F31) ------------------------------------
#
# The opaque-token model closed content-as-code through the QUOTE path and left
# the ESCAPE path wide open. Outside quotes a backslash escapes the next
# character, and the normaliser consumed the backslash and emitted that
# character RAW, which handed it straight back to the parser as grammar:
#
#     git commit -m foo\;git\ checkout\ spec/0002-other && git merge --no-ff spec/0001-thing
#
# Bash parses that as ONE argument to -m, so nothing switches branch and the
# merge runs on the trunk. The gate saw a live `;` and live spaces, cut a
# synthetic `git checkout spec/0002-other` segment out of free text, believed
# the shell had moved off the trunk, and skipped every close check. The QUOTED
# spelling of the identical line was already denied, which is the control.
#
# Asserted over the SET of grammar-carrying characters rather than over the `;`
# and the space a finding used, and in BOTH directions, because the same defect
# produces a false DENIAL in the commit gate (F31): a plain commit whose message
# carries an escaped separator was read as a compound stage-and-commit.
QC_ESC_FAIL=""
for esc in '\;' '\&' '\|' '\(' '\)' '\>' '\<'; do
  # free text in a message must not inject a branch switch that hides the merge
  payload="git commit -m foo${esc}git\\ checkout\\ spec/0002-other && git merge --no-ff spec/0001-thing"
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_ESC_FAIL="$QC_ESC_FAIL
    $payload"
done
# and the escaped SPACE on its own, which splits a word into a command
QC_ESC_EXTRA='git\ checkout spec/0002-other && git merge --no-ff spec/0001-thing'
[[ "$(corpus_verdict "$QC_ESC_EXTRA")" == "deny" ]] || QC_ESC_FAIL="$QC_ESC_FAIL
    $QC_ESC_EXTRA"
if [[ -z "$QC_ESC_FAIL" ]]; then
  ok "corpus escape: an escaped separator or space is content, and cannot inject a branch switch"
else
  bad "corpus escape: an escaped character must not be handed back to the parser as grammar" \
      "these were ALLOWED, so unreviewed work reaches the trunk:$QC_ESC_FAIL"
fi

# The control that makes the case above real: the quoted spelling of the same
# line, which denied before this fix and must still deny after it.
if [[ "$(corpus_verdict 'git commit -m "foo;git checkout spec/0002-other" && git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus escape control: the quoted spelling of the same injection still denies"
else
  bad "corpus escape control: the quoted spelling of the same injection still denies" \
      "the control itself allowed, so the escape cases above prove nothing"
fi

# THE ALLOW DIRECTION. An escape that carries no grammar is ordinary text, and
# the fix must not turn every backslash into a denial. The escaped apostrophe in
# particular is the commonest one there is, and its own handling was added to
# fix a defect this file already records.
#
# `spec/0001-thing` is deliberately NOT in this list: it is the corpus fixture's
# non-compliant deny control, so asserting it allows would be asserting the
# fixture is broken. The first cut of this block used it and the suite said so.
QC_ESC_OK_FAIL=""
for payload in \
  "git commit -m it\\'s" \
  'git commit -m fixup\-typo' \
  'echo done\;echo more' \
  'git status' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_ESC_OK_FAIL="$QC_ESC_OK_FAIL
    $payload"
done
if [[ -z "$QC_ESC_OK_FAIL" ]]; then
  ok "corpus escape: an escape carrying no grammar stays ordinary text"
else
  bad "corpus escape: the fix must not deny every backslash" \
      "these were denied:$QC_ESC_OK_FAIL"
fi

# --- the LEG 5 axis, part 3: a quoted template is not evidence --------------
#
# The most reachable hole leg 5 found, because it needs no adversary. Every
# close-condition check read the spec file as one flat string, so a spec that
# QUOTES the Appendix C template inside a fence satisfied all four at once and a
# spec with no Closing report at all merged clean. The template ships fenced in
# setlist.md, it is stamped to specs/TEMPLATE.md, and the spec-authoring skill
# tells authors to copy it: quoting it is ordinary authoring.
#
# And the inventory row's STATUS is a CELL. Grepping the whole row for CLOSED
# let an ACTIVE spec pass on a note column that mentioned another spec's
# closure, which is prose a person writes without thinking.
L5C="$WORK/leg5-content"; close_fixture "$L5C" no no answered no no true
git -C "$L5C" checkout -q spec/0001-thing
cat > "$L5C/specs/0001-thing.md" <<'SPECEOF'
# Spec 0001

Not closed. There is no Closing report section here, only the template quoted
so the next author can copy it:

```markdown
## Closing report
- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact
```
SPECEOF
printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$L5C/specs/STATUS.md"
# close_fixture creates specs/ and NOT src/, so this redirect used to fail
# silently: the shell reported "No such file or directory" on stderr, the suite
# carried on, and the assertion passed on the spec-file change alone. A fixture
# line that has never once worked is worse than a missing one, because it reads
# as covered. Found on the 1.0.9 macOS repair (mkdir added, not the line removed:
# the intent was for the branch to touch code as well as its spec).
mkdir -p "$L5C/src"
echo work >> "$L5C/src/a.txt"
git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "quote the template" >/dev/null 2>&1
git -C "$L5C" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "leg5 content: a fenced quote of the template is not a Closing report" "CG-NO-CLOSING-REPORT"

# The same spec WITH a real report, still quoting the template, must merge. This
# is the direction that breaks every ordinary session if the fix overreaches.
git -C "$L5C" checkout -q spec/0001-thing
cat > "$L5C/specs/0001-thing.md" <<'SPECEOF'
# Spec 0001

## Closing report
- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact

For reference, the template authors copy:

```markdown
## Closing report
- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact
```
SPECEOF
git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "real report plus a quote" >/dev/null 2>&1
git -C "$L5C" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "leg5 content control: a real Closing report beside a fenced quote still closes"

# The status CELL, both directions, over every shape the note column takes.
for row_case in \
  'ACTIVE|follows on from 0000 which is CLOSED|deny' \
  'ACTIVE|superseded by 0002, now CLOSED|deny' \
  'DRAFT|see the CLOSED spec 0000|deny' \
  'CLOSED|done|allow' \
  ; do
  st="${row_case%%|*}"; rest="${row_case#*|}"; note="${rest%%|*}"; want="${rest##*|}"
  git -C "$L5C" checkout -q spec/0001-thing
  printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | %s | %s |\n' "$st" "$note" > "$L5C/specs/STATUS.md"
  git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "row $st" >/dev/null 2>&1
  git -C "$L5C" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
  if [[ "$want" == "deny" ]]; then
    expect_deny "leg5 row: status cell [$st] with note [$note] is not CLOSED" "CG-NO-STATUS-ROW"
  else
    expect_allow "leg5 row: status cell [$st] with note [$note] closes"
  fi
done

# --- the LEG 5 axis, part 2: branch tracking must fail closed ---------------
#
# Three of leg 5's seven bypasses are the same shape: a checkout or switch whose
# target the gate could not follow left the tracked branch OFF the trunk, so a
# merge compounded after it read as ordinary feature work and every close check
# was skipped. All three only reproduce from a fixture standing OFF the trunk.
# Tested from the trunk they deny, and a correct gate and a broken one both deny
# there, so a fixture on the trunk cannot fail. That nearly produced two false
# NOT-CONFIRMED verdicts during triage, so the fixture position is asserted
# first rather than assumed.
# spec/0001-thing must be NON-compliant here, or the merge is a legitimate close
# and every case below allows for the right reason while proving nothing. The
# first cut of this block used a compliant fixture and its own control failed,
# which is how it was caught.
L5="$WORK/leg5-track"; close_fixture "$L5" no no answered no no true
git -C "$L5" checkout -q -b spec/0002-track main 2>/dev/null || git -C "$L5" checkout -q spec/0002-track
assert_true "leg5 track 0: the fixture really stands OFF the trunk, or none of these can fail" \
  "the fixture is on the trunk, where a broken tracker denies for the wrong reason and the cases below prove nothing" \
  test "$(git -C "$L5" rev-parse --abbrev-ref HEAD)" != "main"

for track_cmd in \
  'git checkout main -- && git merge --no-ff spec/0001-thing' \
  'git checkout main >/dev/null && git merge --no-ff spec/0001-thing' \
  'git checkout main 2>/dev/null && git merge --no-ff spec/0001-thing' \
  'git checkout main # back to the trunk && git merge --no-ff spec/0001-thing' \
  'TRUNK=main; git switch $TRUNK && git merge --no-ff spec/0001-thing' \
  'git switch @{-1} && git merge --no-ff spec/0001-thing' \
  ; do
  run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload "$track_cmd")"
  expect_deny "leg5 track: [$track_cmd] cannot move the tracked branch off the trunk unchecked" "CG-"
done

# The control that makes those real: the plain spelling denies too, so the
# fixture and the gate are both working.
run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload 'git checkout main && git merge --no-ff spec/0001-thing')"
expect_deny "leg5 track control: the plain checkout spelling still denies" "CG-"

# And the ALLOW direction, which is the whole risk of this fix: a GENUINE
# pathspec restore switches nothing, and a merge from a real feature branch is
# not a close. If these regress, every ordinary session breaks.
for track_ok in \
  'git checkout main -- src/a.txt && git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing' \
  ; do
  run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload "$track_ok")"
  expect_allow "leg5 track control: [$track_ok] is not a trunk close and is allowed"
done

# --- the LEG 5 axis: comments, abbreviations, and switch operands -----------
#
# Seven replay-confirmed bypasses in the shipped gates, reducing to three
# mechanisms. Each is asserted here in BOTH directions, because five of the
# seven are cases where the gate reached a CONFIDENT WRONG ANSWER rather than
# failing closed, and the fix for that shape is always at risk of failing
# closed on everything instead.
QC_L5_FAIL=""
for payload in \
  'git merge --no-ff spec/0001-thing # will --continue if it conflicts' \
  'git merge --no-ff spec/0001-thing #--continue' \
  'git merge --no-ff spec/0001-thing --mess "--continue"' \
  'git merge --no-ff spec/0001-thing --messa "--continue"' \
  'git merge --no-ff spec/0001-thing --messag "--continue"' \
  'git merge --no-ff spec/0001-thing --into-nam "--abort"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_L5_FAIL="$QC_L5_FAIL
    $payload"
done
if [[ -z "$QC_L5_FAIL" ]]; then
  ok "corpus leg5: a trailing comment and an abbreviated option value cannot reach the resumption exemption"
else
  bad "corpus leg5: a trailing comment and an abbreviated option value cannot reach the resumption exemption" \
      "these were ALLOWED, so every close check was skipped:$QC_L5_FAIL"
fi

# The ALLOW direction. A REAL resumption must stay exempt or a conflicted close
# has no permitted way to finish, and an ordinary close must survive a comment.
QC_L5_OK=""
for payload in 'git merge --continue' 'git merge --abort'; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_L5_OK="$QC_L5_OK
    $payload"
done
if [[ -z "$QC_L5_OK" ]]; then
  ok "corpus leg5 control: a real --continue and --abort are still exempt"
else
  bad "corpus leg5 control: a real --continue and --abort are still exempt" \
      "the comment and abbreviation fix denied a legitimate resumption:$QC_L5_OK"
fi

# --- the SHELL-GRAMMAR axis (1.0.8, F9) -------------------------------------
# A segment is judged only when its command word sits at the front, and shell has
# a vocabulary for putting something else there first. All four of these executed
# a real merge onto the trunk with every close check skipped:
#
#     { git merge --no-ff spec/0001-thing; }
#     if true; then git merge --no-ff spec/0001-thing; fi
#     for i in 1; do git merge --no-ff spec/0001-thing; done
#     ! git merge --no-ff spec/0001-thing
#
# None is exotic. `!` inverts an exit status and `{ ...; }` groups commands.
#
# Unlike the wrapper allowlist, THIS list is closed: bash reserved words are a
# fixed set defined by the language, not the open-ended family of programs that
# can exec another program. That is worth stating because the wrapper axis
# carries the opposite caveat, and confusing the two would be a false claim of
# completeness.
GRAM_N=0; GRAM_FAIL=""
for payload in \
  '{ git merge --no-ff spec/0001-thing; }' \
  'if true; then git merge --no-ff spec/0001-thing; fi' \
  'for i in 1; do git merge --no-ff spec/0001-thing; done' \
  'while false; do git merge --no-ff spec/0001-thing; done' \
  'until true; do git merge --no-ff spec/0001-thing; done' \
  '! git merge --no-ff spec/0001-thing' \
  'time git merge --no-ff spec/0001-thing' \
  '{ nice -n 5 git merge --no-ff spec/0001-thing; }' \
  'if true; then env -- git merge --no-ff spec/0001-thing; fi' \
  '{ git merge spec/0001-thing -m "close"; }' \
  ; do
  GRAM_N=$((GRAM_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || GRAM_FAIL="$GRAM_FAIL
    $payload"
done
if [[ -z "$GRAM_FAIL" ]]; then
  ok "corpus shell grammar: all $GRAM_N compound spellings are denied"
else
  bad "corpus shell grammar: a reserved word must not move the git verb out of command position" \
      "these reached the trunk unchecked:$GRAM_FAIL"
fi

# THE INVERSE. Stripping reserved words must not start denying ordinary lines
# that merely CONTAIN one, and must not turn a mention into an operation.
GRAM_ALLOW_FAIL=""
for payload in \
  'echo "{ git merge --no-ff spec/0001-thing; }"' \
  'if true; then git status; fi' \
  '{ echo git merge --no-ff spec/0001-thing; }' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || GRAM_ALLOW_FAIL="$GRAM_ALLOW_FAIL
    $payload"
done
if [[ -z "$GRAM_ALLOW_FAIL" ]]; then
  ok "corpus shell grammar: a reserved word around a NON-merge does not create one"
else
  bad "corpus shell grammar: stripping grammar must not manufacture merges" \
      "these were denied:$GRAM_ALLOW_FAIL"
fi

# --- the REF-IDENTITY axis (1.0.8, F3 and F8) -------------------------------
# The gate used to decide what a merge argument MEANT by stripping three literal
# prefixes and testing the remainder for spec/ or chore/. Every other spelling of
# the same commit read as an ungoverned sync merge: heads/, remotes/origin/,
# another remote's name, a TAG, an alias branch, a raw object name. The prefix
# list could never be finished, because git accepts an open-ended set of names
# for one commit.
#
# It resolves the argument to a COMMIT now and asks git which refs point at it,
# so identity is by object rather than by string and a spelling nobody has
# thought of resolves like one everybody knows.
ri_fixture() { # ri_fixture <dir>  -> local 0001 COMPLIANT, origin/0001 NOT
  local d="$1"
  close_fixture "$d" yes yes answered yes no true
  # The DIVERGENT remote, which is F3 exactly: a compliant local branch and a
  # non-compliant remote-tracking branch of the same name. The gate must judge
  # the one git will actually merge.
  git -C "$d" checkout -q -b ri-remote-tmp main
  mkdir -p "$d/specs"
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
  printf 'unreviewed\n' > "$d/ri-unreviewed.txt"
  git -C "$d" add -A >/dev/null; git -C "$d" commit -qm "remote tip, NOT closed"
  git -C "$d" update-ref refs/remotes/origin/spec/0001-thing "$(git -C "$d" rev-parse ri-remote-tmp)"
  git -C "$d" branch -qD ri-remote-tmp >/dev/null 2>&1
  # A tag and an alias, both pointing at the compliant local tip.
  git -C "$d" tag -f ri-tag spec/0001-thing >/dev/null 2>&1
  git -C "$d" branch -f ri-alias spec/0001-thing >/dev/null 2>&1
  # A real origin/main, so the sync-merge case is exercised against a ref git
  # can resolve. Without one it denies because the ref does not exist, which
  # looks like the gate working and tests nothing. That trap has now appeared
  # three times in this repo in a single day.
  git -C "$d" update-ref refs/remotes/origin/main "$(git -C "$d" rev-parse main)"
  git -C "$d" checkout -q main
}
RI="$WORK/close-refidentity"; ri_fixture "$RI"
ri_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$RI" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}

assert_true "ref-identity0: the fixture's remote tip really differs from the local one" \
  "local and remote point at the same commit, so the divergent case below proves nothing" \
  test "$(git -C "$RI" rev-parse spec/0001-thing)" != "$(git -C "$RI" rev-parse refs/remotes/origin/spec/0001-thing)"

# F3. The local branch is COMPLIANT and the remote one is NOT. Merging the
# remote must be judged against the remote, or a compliant local branch vouches
# for code it does not contain.
if [[ "$(ri_verdict 'git merge --no-ff origin/spec/0001-thing')" == "deny" ]]; then
  ok "ref-identity a: a remote-tracking ref is judged on ITS tree, not the local branch of that name"
else
  bad "ref-identity a: the thing validated must be the thing merged" \
      "a compliant local spec/0001-thing green-lit a non-compliant origin/spec/0001-thing"
fi

# F8 and the alias/tag family. Every one of these names the same UNCLOSED commit
# as the remote tip or an unclosed branch, and each was allowed by name matching.
RI_FAIL=""
for c in 'git merge --no-ff refs/remotes/origin/spec/0001-thing' \
         'git merge --no-ff remotes/origin/spec/0001-thing' ; do
  [[ "$(ri_verdict "$c")" == "deny" ]] || RI_FAIL="$RI_FAIL
    $c"
done
if [[ -z "$RI_FAIL" ]]; then
  ok "ref-identity b: every spelling of the non-compliant remote tip is governed"
else
  bad "ref-identity b: a spelling of the merge target must not change whether it is governed" \
      "these reached the trunk unchecked:$RI_FAIL"
fi

# THE INVERSE, and it is what stops "deny everything" from passing this axis. A
# sync merge from the trunk's own remote is not a close and has never been
# governed; 1.0.3 denied it and broke ordinary work while `git pull` did the
# same thing ungated.
if [[ "$(ri_verdict 'git merge origin/main')" == "allow" ]]; then
  ok "ref-identity c: a sync merge from the trunk's own remote is still allowed"
else
  bad "ref-identity c: git merge origin/main must not be denied" \
      "resolving refs by commit must not turn ordinary syncs into denials, which is the 1.0.3 regression"
fi

# The INDIRECT forms stay denied, and for a reason that is about TIME rather
# than spelling: this hook runs before the command, so `@{-1}` here is not
# necessarily `@{-1}` when the merge runs. Resolving them would let the gate
# validate one branch while git merges another, which is F3 from the other end.
RI_IND_FAIL=""
for c in 'git merge @{-1}' 'git merge FETCH_HEAD' ; do
  [[ "$(ri_verdict "$c")" == "deny" ]] || RI_IND_FAIL="$RI_IND_FAIL
    $c"
done
if [[ -z "$RI_IND_FAIL" ]]; then
  ok "ref-identity d: time-varying indirect forms are still refused rather than resolved"
else
  bad "ref-identity d: an indirect form must not be resolved at hook time" \
      "these were resolved, and their meaning can change before the merge runs:$RI_IND_FAIL"
fi

# --- the SPEC-NUMBER-REUSE axis (1.0.7, B4) ---------------------------------
# Every close-gate check reads the spec file as it stands on the branch, which
# is right, and says nothing about WHO WROTE IT. A branch cut from the trunk
# after spec NNNN closed inherits that spec, Closing report and all, so reusing
# a CLOSED number as a branch name carries unreviewed work onto the trunk
# against somebody else's evidence, and the trunk audit then calls it compliant
# because it reads the same inherited artifacts.
#
# Reproduced by hand 2026-07-27. It was the one BLOCKER on the standing list
# that had never been replayed, and three of eleven claims in an earlier intake
# did not survive verification, so it got a repro before it got a fix.
reuse_fixture() { # reuse_fixture <dir> <where-the-spec-is-written: branch|trunk|inherited>
  local d="$1" mode="$2"
  rm -rf "$d"; mkdir -p "$d/specs" "$d/.claude" "$d/src"
  git_init "$d"
  sdd_json "$d" true main true
  printf 'x\n' > "$d/src/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm init
  git -C "$d" branch -M main

  # A legitimate spec 0001, closed and merged the honest way.
  git -C "$d" checkout -q -b spec/0001-thing
  { printf '# Spec 0001 - thing\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    printf -- '- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
  } > "$d/specs/0001-thing.md"
  { printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n'
    printf '| 0001 | Thing | CLOSED | shipped |\n'
  } > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0001 closed"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff spec/0001-thing -m "close 0001"

  case "$mode" in
    inherited)
      # THE DEFECT: a new branch reusing number 0001, contributing code but no
      # spec of its own. It inherits 0001-thing.md from the trunk.
      git -C "$d" checkout -q -b spec/0001-sneaky
      printf 'unreviewed\n' >> "$d/src/a.txt"
      git -C "$d" add -A && git -C "$d" commit -qm "unspecified work on a reused number"
      ;;
    trunk)
      # THE COMMON LEGITIMATE PATH, and the one a careless repair breaks: the
      # spec file is created on the trunk during planning, and the BRANCH adds
      # the Closing report to it. The blob exists at the merge base and differs
      # at the tip, which is exactly what authorship looks like.
      { printf '# Spec 0002 - planned\n\nStatus: ACTIVE\n'; } > "$d/specs/0002-planned.md"
      git -C "$d" add -A && git -C "$d" commit -qm "spec 0002 planned on the trunk"
      git -C "$d" checkout -q -b spec/0002-planned
      { printf '# Spec 0002 - planned\n\nStatus: CLOSED\n\n## Closing report\n\n'
        printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
        printf -- '- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
      } > "$d/specs/0002-planned.md"
      { printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n'
        printf '| 0001 | Thing | CLOSED | shipped |\n| 0002 | Planned | CLOSED | shipped |\n'
      } > "$d/specs/STATUS.md"
      git -C "$d" add -A && git -C "$d" commit -qm "close 0002"
      ;;
  esac
  git -C "$d" checkout -q main
}

CR="$WORK/close-reuse"; reuse_fixture "$CR" inherited
assert_true "close-gate reuse0: the fixture really did close 0001 onto the trunk first" \
  "0001-thing.md is not on the trunk, so the reused branch inherits nothing and this case proves nothing" \
  git -C "$CR" cat-file -e "main:specs/0001-thing.md"
assert_true "close-gate reuse0b: the reused branch really contributes no spec change" \
  "the branch modifies its spec, so it is not the inherited-artifact case at all" \
  test -z "$(git -C "$CR" diff --name-only main spec/0001-sneaky -- specs/)"
run_hook "$HOOKS/close-gate.sh" "$CR" "$(bash_payload 'git merge --no-ff spec/0001-sneaky')"
# Matches the stable CODE, not the prose. It asserted "does not modify" until
# 2026-08-01, which is a phrase from the deny MESSAGE, and item 8's promoted
# rider rewords exactly that message to name the chore route for evidence
# completion. The codes exist so prose can move without breaking a test; a test
# that matches prose quietly cancels that guarantee, and the whole point of the
# rewording being "cheap and safe" was that no test was doing this.
expect_deny "close-gate reuse a: a branch reusing a CLOSED spec number is denied" "CG-SPEC-NOT-AUTHORED"

CR2="$WORK/close-reuse-ok"; reuse_fixture "$CR2" trunk
run_hook "$HOOKS/close-gate.sh" "$CR2" "$(bash_payload 'git merge --no-ff spec/0002-planned')"
expect_allow "close-gate reuse b: a spec planned on the trunk and CLOSED on the branch still passes"

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

# --- the FLAG-VALUED WRAPPER axis (1.0.7) -----------------------------------
# The 1.0.6 wrapper axis above covers wrappers that take no argument, and the
# flag stripper it shipped with consumed dash flags one word at a time. A flag
# that takes a SEPARATE value strands that value at the head of the segment:
# `nice -n 5 git merge ...` strips `nice`, strips `-n`, and leaves `5 git merge
# ...`, which fails the command-position test and is never judged at all.
# `stdbuf -o0` survives only because its value is glued to the flag, which is
# the accident that hid this. Found by an external review of the SHIPPED 1.0.6,
# the second consecutive release whose bypass lived in a dimension the corpus
# did not have.
CORPUS_FLAGWRAP_N=0
CORPUS_FLAGWRAP_FAIL=""
# `timeout` is deliberately NOT here: it is not in either hook's wrapper
# allowlist, which the hooks say plainly is not a claim of completeness, and it
# is asserted below as a documented pass PAIRED with the trunk audit that
# catches it. Demanding a deny here would have quietly expanded the allowlist
# as a side effect of writing a regression test, which is a decision, not a fix.
for wrap in 'nice -n 5 ' 'LANG=C nice -n 5 ' 'env -u FOO ' 'env -i ' 'nice -n 5 nohup ' \
            'stdbuf -o0 ' 'stdbuf -o 0 ' 'time nice -n 5 '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_FLAGWRAP_N=$((CORPUS_FLAGWRAP_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_FLAGWRAP_FAIL="$CORPUS_FLAGWRAP_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_FLAGWRAP_FAIL" ]]; then
  ok "corpus flag-valued wrappers: all $CORPUS_FLAGWRAP_N spellings are denied"
else
  bad "corpus flag-valued wrappers: a wrapper flag with a separate value must not escape the gate ($CORPUS_FLAGWRAP_N generated)" \
      "these reached the trunk unchecked:$CORPUS_FLAGWRAP_FAIL"
fi

# The false-positive direction, which matters as much (law 3): stripping a flag
# and its value must not start eating the command itself.
CORPUS_FLAGWRAP_ALLOW_FAIL=""
for cmd in 'nice -n 5 git status' \
           'env -u GIT_DIR git log --oneline' \
           'nice -n 5 git merge origin/main' \
           'LANG=C git merge origin/main' \
           'env -i git fetch origin'; do
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_FLAGWRAP_ALLOW_FAIL="$CORPUS_FLAGWRAP_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_FLAGWRAP_ALLOW_FAIL" ]]; then
  ok "corpus flag-valued wrappers: ordinary wrapped commands still pass"
else
  bad "corpus flag-valued wrappers: ordinary wrapped commands must still pass" \
      "these were denied:$CORPUS_FLAGWRAP_ALLOW_FAIL"
fi

# --- the DASH-VALUED FLAG and OPTION TERMINATOR axes (1.0.7) ----------------
# The axis above generates flag values two ways, non-dash (`nice -n 5`) and
# glued (`stdbuf -o0`), and both are values that LOOK like values. Neither
# spelling below appears anywhere in it:
#
#   nice -n -5 git merge ...     a flag value that begins with a dash
#   env -- git merge ...         the bare option terminator
#
# Both were DENIED by the shipped v1.0.6 and ALLOWED by 1.0.7 until this axis
# existed: the flag stripper consumed `-n`, stranded `-5`, and the command-position
# test then found no git to judge. The terminator matched none of its branches
# at all and sat at the head of the segment doing the same thing.
#
# This is the fourth consecutive release whose bypass lived in a corpus
# dimension nobody had written down, and the first where the differential
# strictness gate ALSO missed it, reporting "no undeclared relaxation" while two
# of its own regressions were live underneath. A generated corpus only varies
# what somebody listed; the list is the artifact that needs reviewing, and it is
# the reason this block exists rather than two more literal cases.
CORPUS_DASHVAL_N=0
CORPUS_DASHVAL_FAIL=""
# The NON-ALPHABETIC dash flag was added after an adversarial review found it: the axis
# above was written with alphabetic flags only (`nice -n -5`), so `nice -5`,
# where the FLAG itself is not a letter, matched none of the stripper branches
# and stayed stranded at the head of the segment. v1.0.6 denied it. The author of
# the axis directly above missed it while writing a commit message about exactly
# this failure mode, which is the most direct evidence available that a
# dimension list written from imagination is not a dimension list.
for wrap in 'nice -n -5 ' 'nice -n -5 nohup ' 'LANG=C nice -n -5 ' \
            'nice -5 ' 'nice -5 nohup ' 'LANG=C nice -5 ' 'nice --5 ' \
            'env -- ' 'command -- ' 'env -i -- ' 'env -u FOO -- ' \
            'nice -n -5 env -- ' 'time nice -n -5 ' 'time nice -5 '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_DASHVAL_N=$((CORPUS_DASHVAL_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_DASHVAL_FAIL="$CORPUS_DASHVAL_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_DASHVAL_FAIL" ]]; then
  ok "corpus dash-valued flags and option terminators: all $CORPUS_DASHVAL_N spellings are denied"
else
  bad "corpus dash-valued flags and option terminators: these must not escape the gate ($CORPUS_DASHVAL_N generated)" \
      "these reached the trunk unchecked:$CORPUS_DASHVAL_FAIL"
fi

# The false-positive direction. Stripping a dash-leading value must never eat
# the command word itself, and `env -i git ...` is the case that makes this
# delicate: git sits exactly where a value would.
CORPUS_DASHVAL_ALLOW_FAIL=""
for cmd in 'nice -n -5 git status' \
           'nice -5 git status' \
           'nice -5 git merge origin/main' \
           'env -- git status' \
           'env -i -- git log --oneline' \
           'nice -n -5 git merge origin/main' \
           'env -- git merge origin/main' \
           'command -- git fetch origin'; do
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_DASHVAL_ALLOW_FAIL="$CORPUS_DASHVAL_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_DASHVAL_ALLOW_FAIL" ]]; then
  ok "corpus dash-valued flags: ordinary commands behind them still pass"
else
  bad "corpus dash-valued flags: ordinary commands behind them must still pass" \
      "these were denied:$CORPUS_DASHVAL_ALLOW_FAIL"
fi

# --- the NEWLINE-SEPARATOR axis (1.0.7) -------------------------------------
# `tr -s '[:space:]' ' '` squeezes newlines into spaces before the segment
# splitter runs, so a multi-line command collapses into ONE segment and only its
# first command sits at command position. Everything after the first newline was
# never judged by either gate. Found independently by two generators in the same
# scoped run, which is what a dominant hole looks like.
#
# Pre-existing in v1.0.6, so it is a hole rather than a regression, and it is the
# widest one on the list.
# Built as explicit strings so the newline is unambiguous in the source.
NL_PAYLOADS=(
  "$(printf 'echo hi\ngit merge --no-ff spec/0001-thing')"
  "$(printf 'set -e\ngit status --short\ngit merge --no-ff spec/0001-thing')"
  "$(printf '# stage is ready\ngit merge spec/0001-thing -m "close"')"
  "$(printf 'git status\n\ngit merge --no-ff spec/0001-thing')"
)
CORPUS_NL_N=0
CORPUS_NL_FAIL=""
for payload in "${NL_PAYLOADS[@]}"; do
  CORPUS_NL_N=$((CORPUS_NL_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || CORPUS_NL_FAIL="$CORPUS_NL_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CORPUS_NL_FAIL" ]]; then
  ok "corpus newline separator: all $CORPUS_NL_N multi-line spellings are denied"
else
  bad "corpus newline separator: a git operation after a newline must not escape the gate ($CORPUS_NL_N generated)" \
      "these reached the trunk unchecked (~ marks the newline):$CORPUS_NL_FAIL"
fi

# THE INVERSE, and it is the case that decides whether treating a newline as a
# separator is safe at all: a newline INSIDE a quoted message must not split the
# merge away from its branch argument. If it did, the fix for the case above
# would hand back a bypass in exchange, which is the trade this repo has
# accidentally made twice.
NL_QUOTED_FAIL=""
for payload in "$(printf 'git merge --no-ff -m "closes the spec\nnice work" spec/0001-thing')" \
               "$(printf 'git merge --no-ff spec/0001-thing -m "line one\nline two"')"; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || NL_QUOTED_FAIL="$NL_QUOTED_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$NL_QUOTED_FAIL" ]]; then
  ok "corpus newline separator: a newline inside a merge message does not split the merge from its branch"
else
  bad "corpus newline separator: a quoted newline must not turn a deny into a bypass" \
      "these escaped (~ marks the newline):$NL_QUOTED_FAIL"
fi



# --- the AMPERSAND-SEPARATOR axis (1.0.7) -----------------------------------
# The splitter handled &&, ||, ;, | and (since the axis above) newlines. A SINGLE
# & backgrounds the preceding command and starts a new one, exactly as ; does,
# and it was not a separator at all, so:
#
#     echo hi & git merge --no-ff spec/0001-thing
#
# collapsed into ONE segment whose command word was `echo`, and the merge was
# never judged. Pre-existing in v1.0.6, found by the adversarial review as F8.
AMP_N=0; AMP_FAIL=""
for payload in \
  'echo hi & git merge --no-ff spec/0001-thing' \
  'sleep 1 & git merge --no-ff spec/0001-thing' \
  'echo hi & git merge spec/0001-thing -m "close"' \
  'git status & git merge --no-ff spec/0001-thing' \
  'echo a & echo b & git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing & echo done' \
  ; do
  AMP_N=$((AMP_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_FAIL="$AMP_FAIL
    $payload"
done
if [[ -z "$AMP_FAIL" ]]; then
  ok "corpus ampersand separator: all $AMP_N backgrounded spellings are denied"
else
  bad "corpus ampersand separator: a merge after a single & must not escape the gate" \
      "these reached the trunk unchecked:$AMP_FAIL"
fi

# THE INVERSE, which the intake called out by name: && must not be split into
# two & separators. POSIX ERE alternation is leftmost-longest so it is not, but
# "the awk on the reviewer's machine" is the assumption the macOS leg exists to
# doubt, and an && that silently became two separators would put an empty
# segment between every pair of commands on every line this gate ever sees.
AMP_PAIR="$(printf 'a && b & c\n' | awk '{ gsub(/&&|\|\||[;|()&]/, "\n"); print }' | grep -c .)"
if [[ "$AMP_PAIR" -eq 3 ]]; then
  ok "corpus ampersand separator: && is one separator, not two (a && b & c splits into 3, not 4)"
else
  bad "corpus ampersand separator: && must not split into two & separators" \
      "'a && b & c' produced $AMP_PAIR non-empty segments, expected 3. This awk is not leftmost-longest."
fi

# And the ordinary && line must still behave, which is the assertion that would
# catch the above turning into a bypass rather than merely into noise.
AMP_AND_FAIL=""
for payload in \
  'git status && git merge --no-ff spec/0001-thing' \
  'echo hi && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_AND_FAIL="$AMP_AND_FAIL
    $payload"
done
if [[ -z "$AMP_AND_FAIL" ]]; then
  ok "corpus ampersand separator: && lines are unaffected by the & repair"
else
  bad "corpus ampersand separator: adding & as a separator must not break &&" \
      "these stopped being denied:$AMP_AND_FAIL"
fi

# A redirection contains an ampersand that is NOT a separator. Splitting `2>&1`
# yields the fragments `2>` and `1`, neither of which is a command, so the git
# operation on the line must still be found and judged. This is the false-DENY
# and false-ALLOW pair for the same character.
AMP_REDIR_FAIL=""
for payload in \
  'git merge --no-ff spec/0001-thing 2>&1' \
  'git merge --no-ff spec/0001-thing >/dev/null 2>&1' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_REDIR_FAIL="$AMP_REDIR_FAIL
    $payload"
done
if [[ -z "$AMP_REDIR_FAIL" ]]; then
  ok "corpus ampersand separator: an ampersand inside a redirection does not hide the merge"
else
  bad "corpus ampersand separator: 2>&1 must not split a merge away from command position" \
      "these stopped being denied:$AMP_REDIR_FAIL"
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
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
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

# --- the PATHSPEC-CHECKOUT axis (1.0.7) -------------------------------------
# `git checkout -- .` and `git checkout .` do not switch branches at all: they
# discard working-tree changes, which is something agents do constantly right
# before merging. The tracker read the argument as a branch name, concluded the
# merge would run on a branch called ".", and skipped it as non-trunk. That is
# the `checkout -` defect class one door down: an argument that is not a branch
# name recorded as one, producing a CONFIDENT WRONG ANSWER rather than a
# fall-through. `git restore .` was always safe because restore never touches
# the tracker. Found by an external review of the shipped 1.0.6; the file-path
# spellings below were found while reproducing it, and widen the class beyond
# the dot the report named.
CORP_PATH="$WORK/corpus-pathspec"
close_fixture "$CORP_PATH" no no answered no no true
path_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_PATH" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus pathspec0: the fixture is standing on the trunk" \
  "the fixture is not on main, so a merge segment would be skipped for the RIGHT reason and these cases would prove nothing" \
  test "$(git -C "$CORP_PATH" branch --show-current)" = "main"
CORP_PATH_FAIL=""
for c in 'git checkout -- . && git merge --no-ff spec/0001-thing' \
         'git checkout . && git merge --no-ff spec/0001-thing' \
         'git checkout src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -f -- . && git merge --no-ff spec/0001-thing' \
         'git checkout ./src && git merge --no-ff spec/0001-thing'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_PATH_FAIL="$CORP_PATH_FAIL
    $c"
done
if [[ -z "$CORP_PATH_FAIL" ]]; then
  ok "corpus pathspec: discarding working-tree changes does not move the tracked branch"
else
  bad "corpus pathspec: a pathspec checkout must not be read as a branch switch" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_PATH_FAIL"
fi

# The TREE-ISH pathspec form (1.0.7, B3). The cases above all have nothing
# before the `--`, so no branch candidate was found and the tracker fell
# through. Put a real branch in front of the separator and a candidate IS found:
#
#     git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing
#
# switches nothing, but the tracker recorded a switch to spec/0002-other, judged
# the merge as ordinary feature work, and skipped it. The branch has to EXIST for
# this to reproduce, which is why the fixture below needs a second spec branch:
# the first cut of the replay fixture had only one, so any payload naming a
# second denied for the wrong reason and passed while testing nothing.
assert_true "corpus pathspec-treeish0: the fixture has a second spec branch to name" \
  "without a second EXISTING branch these payloads deny for the wrong reason and assert nothing" \
  git -C "$CORP_PATH" rev-parse --verify --quiet spec/0002-other
CORP_TI_FAIL=""
for c in 'git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'git checkout spec/0002-other -- . && git merge --no-ff spec/0001-thing' \
         'git checkout main -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout HEAD -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -f spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'git checkout spec/0002-other -- src/a.txt src/b.txt && git merge spec/0001-thing -m close'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_TI_FAIL="$CORP_TI_FAIL
    $c"
done
if [[ -z "$CORP_TI_FAIL" ]]; then
  ok "corpus pathspec: a tree-ish before a -- pathspec does not move the tracked branch"
else
  bad "corpus pathspec: git checkout <tree-ish> -- <path> restores files and switches nothing" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_TI_FAIL"
fi

# The interaction the intake named. A bare `--` at the HEAD of a segment is an
# option terminator that strip_wrappers removes; a `--` after the checkout verb
# is a pathspec separator that this tracker reads. The two positions must not be
# confused, so both are exercised on the same line.
CORP_TI_MIX_FAIL=""
for c in 'env -- git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'env -- git merge --no-ff spec/0001-thing' \
         'nice -n 5 git checkout spec/0002-other -- . && git merge --no-ff spec/0001-thing'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_TI_MIX_FAIL="$CORP_TI_MIX_FAIL
    $c"
done
if [[ -z "$CORP_TI_MIX_FAIL" ]]; then
  ok "corpus pathspec: the head -- option terminator and the pathspec -- do not confuse each other"
else
  bad "corpus pathspec: a wrapper's -- and a pathspec's -- occupy different positions and must stay distinct" \
      "these escaped:$CORP_TI_MIX_FAIL"
fi

# The false-positive direction for the tree-ish form specifically: a REAL switch
# to that same branch, with no separator, must still be tracked as a switch. If
# the repair above had keyed on the branch name instead of the separator, this
# is the assertion that would have caught it.
if [[ "$(path_verdict 'git checkout spec/0002-other && git merge --no-ff main')" == "allow" ]]; then
  ok "corpus pathspec: the same branch without a -- separator is still a real switch"
else
  bad "corpus pathspec: git checkout <branch> with no separator must still track the switch" \
      "the repair keyed on something other than the separator and broke ordinary branch switching"
fi

# An argument that is NEITHER a branch nor an existing path cannot be
# classified, and an unclassifiable branch must fail closed rather than read as
# "some other branch". This is the sentinel the 1.0.6 fix introduced, reused.
if [[ "$(path_verdict 'git checkout no-such-thing-at-all && git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus pathspec: an unresolvable checkout target fails closed on the sentinel"
else
  bad "corpus pathspec: an unresolvable checkout target must fail closed" \
      "the gate decided it was on some other branch and skipped the merge"
fi

# The false-positive direction: a real branch switch must still be tracked, and
# ordinary discarding on a feature branch must stay silent.
CORP_PATH_ALLOW_FAIL=""
for c in 'git checkout spec/0001-thing && git merge --no-ff main' \
         'git checkout -- .' \
         'git checkout . && git status'; do
  [[ "$(path_verdict "$c")" == "allow" ]] || CORP_PATH_ALLOW_FAIL="$CORP_PATH_ALLOW_FAIL
    $c"
done
if [[ -z "$CORP_PATH_ALLOW_FAIL" ]]; then
  ok "corpus pathspec: real branch switches and plain discards still pass"
else
  bad "corpus pathspec: real branch switches and plain discards must still pass" \
      "these were denied:$CORP_PATH_ALLOW_FAIL"
fi

# --- the RAW-OBJECT-NAME axis (1.0.7) ---------------------------------------
# A raw commit name is an indirect form: it identifies the commit without
# naming the branch, so the close conditions (which live in a branch's spec
# file) cannot be checked. The gate knew that and skipped SHAs by SHAPE,
# matching `[0-9a-f]{7,40}`. Every spelling outside that shape sailed through
# instead: a 6-character abbreviation, the same oid uppercased, and in a
# sha256 repository the 64-character oid. Shape was the wrong question. The
# right one is whether git considers the word a REF, which is shape-free.
CORP_OID="$WORK/corpus-oid"
close_fixture "$CORP_OID" no no answered no no true
OID="$(git -C "$CORP_OID" rev-parse spec/0001-thing)"
oid_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_OID" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus oid0: the fixture resolves a real object name for the unclosed branch" \
  "no oid, so every case below would be testing a word that resolves to nothing" \
  test -n "$OID"
CORP_OID_FAIL=""
for spelling in "${OID:0:4}" "${OID:0:6}" "${OID:0:7}" "${OID:0:12}" "$OID" \
                "$(printf '%s' "$OID" | tr 'a-f' 'A-F')" \
                "$(printf '%s' "${OID:0:10}" | tr 'a-f' 'A-F')"; do
  [[ "$(oid_verdict "git merge --no-ff $spelling")" == "deny" ]] || CORP_OID_FAIL="$CORP_OID_FAIL
    git merge --no-ff $spelling"
done
if [[ -z "$CORP_OID_FAIL" ]]; then
  ok "corpus raw object names: every spelling of a bare commit name is refused, not just the 7-to-40 lowercase shape"
else
  bad "corpus raw object names: a bare commit name must be refused whatever its shape" \
      "these merged an unclosed spec into the trunk with the close conditions unevaluated:$CORP_OID_FAIL"
fi
# The false-positive direction: a real branch name that happens to look hexish
# must still be treated as a branch, and ordinary syncs must still pass. The
# remote ref has to EXIST for the sync case to mean anything: without it the
# deny is the gate correctly refusing an unresolvable ref, which is a different
# fact than the one under test.
git -C "$CORP_OID" branch -f decade main
git -C "$CORP_OID" update-ref refs/remotes/origin/main "$(git -C "$CORP_OID" rev-parse main)"
CORP_OID_ALLOW_FAIL=""
for c in 'git merge origin/main' 'git merge decade'; do
  [[ "$(oid_verdict "$c")" == "allow" ]] || CORP_OID_ALLOW_FAIL="$CORP_OID_ALLOW_FAIL
    $c"
done
if [[ -z "$CORP_OID_ALLOW_FAIL" ]]; then
  ok "corpus raw object names: a branch whose name is hex-shaped is still a branch"
else
  bad "corpus raw object names: a hex-shaped BRANCH name must not be mistaken for an object name" \
      "these were denied:$CORP_OID_ALLOW_FAIL"
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
for form in 'sh -c "git merge --no-ff spec/0001-thing"' 'bash -c "git merge --no-ff spec/0001-thing"' \
            'timeout -s KILL 10 git merge --no-ff spec/0001-thing' 'sudo git merge --no-ff spec/0001-thing'; do
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
# hole: `git rebase` onto a spec branch brings that branch's commits to the trunk with no closing merge. | asserted
# hole: `git reset --hard <spec-branch>` moves the trunk onto unclosed work outright. | asserted
# hole: `git checkout <spec-branch> -- <path>` copies role-path files onto the trunk without any merge to read. | asserted
# hole: The pathspec hole. | asserted
# hole: The secret scan is a first cut. | asserted
# hole: A broken or missing `jq` is handled by the GIT hooks, not by the session gates. | asserted
# hole: A timed-out hook is a skipped gate. | unassertable | harness behaviour, not hook behaviour; verified live 2026-07-25 with a sleeping hook under timeout 1 and 10, recorded in close-gate.sh's header
# hole: The staged-content scans read every staged line unless you scope them. | asserted
# hole: The scans read this project's own index. | asserted
# hole: `--no-verify` skips git hooks | asserted
# hole: Git hooks are per-clone, and the tracked directory narrows that without closing it. | asserted
# hole: `git merge --ff-only` and `git merge --ff` skip the merge hooks. | asserted
# hole: `git merge --squash` needs one flag to work in a Setlist instance, and the error does not say so. | asserted
# hole: The close gate refuses `@{u}` and other revision-suffix spellings of a merge operand. | asserted
# hole: A role directory spelled in a different case is not seen by the session scope gate on macOS or Windows. | asserted
# hole: A `<<\EOF` heredoc body is read as code by the session gates, and can run your whole gate command before an ordinary `git commit`. | asserted
# hole: The session gates are text parsers, and a growing list of spellings read a command wrongly. | asserted
# hole: The session gates' warnings do not reach the agent on current harnesses. | unassertable | a property of the HARNESS, not of these bytes: a shell test can see the hook emit the reason on three channels but not what Claude Code renders. dogfood/advisory-visibility-probe.sh measures it with a live session and a deny-control, and is the check that lifts this limitation when it changes
# hole: A first push to a brand-new EMPTY remote audits every pushed branch as a trunk candidate. | asserted
# hole: The trunk audit cannot tell a merge that EDITS a file from ordinary conflict resolution. | asserted
# hole: The headless integrity chain is only as strong as where your signing key lives, and a key your build can reach is not custody. | asserted
# hole: The close audit's single-parent arm is as strong as your declarations, and a declaration is a claim, not a verified fact. | asserted
# hole: The hashed range ends at the FIRST line reading `## Closing report`, fences included, and the ownership reader agrees with that cut. | asserted
# hole: Identity-by-commit governs an alias only while a spec or chore ref still points at that exact commit. | asserted
# hole: The wiring check recognises only the command spellings `settings.json.tmpl` ships. | asserted
# hole: The set of tested platforms is a list, not a proof. | unassertable | a statement ABOUT the CI matrix rather than about hook behaviour; the matrix in .github/workflows/test.yml is the evidence, and the honest check is reading which platforms it actually runs
# hole: Secret and style scanning is best-effort early warning, not a guarantee. | asserted
# hole: git allows one `core.hooksPath`, so Setlist cannot coexist with husky, lefthook or pre-commit, and `refresh-instance.sh --apply` now REFUSES rather than displace one silently. | asserted
# hole: A checkout is an enforcement switch: every git hook is inert on a branch without `.claude/sdd.json`. | asserted
# hole: The `SETLIST_SKIP_HOOKS=1` escape is not read by `pre-push`. | asserted
# hole: Merges crafted to evade the trunk audit can succeed, and the list of known routes is maintained rather than complete. | asserted
# hole: The trunk is recognised by the NAME recorded in `.claude/sdd.json`, so an instance that merges onto a differently-named branch is ungoverned. | asserted
# LEDGER-END
#
# Each of these is a deliberate pass named in the README. They are asserted
# rather than ignored so that the day one of them closes, this file says so
# instead of nobody noticing.
for hole_cmd in \
  'git cherry-pick spec/0001-thing' \
  'git rebase spec/0001-thing' \
  'git reset --hard spec/0001-thing' \
  'git checkout spec/0001-thing -- src/app.js' ; do
  if [[ "$(corpus_verdict "$hole_cmd")" == "allow" ]]; then
    ok "documented hole: [$hole_cmd] still passes, as Known limitations states"
  else
    bad "documented hole: [$hole_cmd] still passes" \
        "this now DENIES. That is an improvement, but the README still lists it as a hole: update Known limitations and this assertion together"
  fi
done

# CLOSED 1.0.8, and it used to sit in the list above. Merging a spec branch under
# a SECOND NAME (`git branch tmp spec/0001-x && git merge tmp`) was a documented
# hole for as long as the gate decided what a ref meant by editing its name: an
# alias is a different string, so it read as an ungoverned sync merge.
#
# Identity by COMMIT closes it without anyone aiming at it. The alias points at
# the same object as the spec branch, `git for-each-ref --points-at` finds the
# spec ref, and the close conditions are evaluated. That is the difference
# between fixing a spelling and fixing a class: nobody wrote a rule about
# aliases, and aliases stopped working anyway.
#
# It is asserted in the DENY direction now, so a regression that reopens it
# fails here rather than quietly restoring a documented hole.
if [[ "$(corpus_verdict 'git merge --no-ff tmp-alias')" == "deny" ]]; then
  ok "closed hole: a spec branch merged under a second name is now caught by commit identity"
else
  bad "closed hole: a spec branch merged under a second name must stay caught" \
      "an alias of an unclosed spec branch reached the trunk again; ref identity has regressed to name matching"
fi

# A compound carrying TWO commits. HAS_COMMIT was a plain assignment, so the
# last commit segment overwrote the first and the auto-staging check inspected
# the harmless one. `git commit -am x && git commit -m y` therefore passed,
# although the -am segment is exactly the stage-and-commit-in-one-step shape
# CM-AUTOSTAGE-FLAG exists to catch. A command can carry more than one commit
# and the gate answers for all of them.
CMTWO="$WORK/commit-two"; close_fixture "$CMTWO" no no answered no no true
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -am x && git commit -m y')"
expect_deny "commit-gate two-commits: a later plain commit does not disarm the flag check on an earlier one" "CM-AUTOSTAGE-FLAG"
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -m y && git commit -am x')"
expect_deny "commit-gate two-commits: the offending commit is caught in either position" "CM-AUTOSTAGE-FLAG"
# The allow direction: two ordinary commits are not made suspicious by being two.
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -m x && git commit -m y')"
expect_allow "commit-gate two-commits: two plain commits in one line are still allowed"

# =============================================================================
# UNLEXABLE INPUT, and a malformed trunk VALUE. Both 2026-07-28, both from the
# 1.0.8 leg, both the same shape: a check that validated the FORM of its input
# and never the substance.
#
# The awk normaliser in both gates appends `@@UNTERMINATED@@` when a quote never
# closes, under a comment saying a gate that cannot lex its input has not
# evaluated its predicate. No line read the marker, so the unlexable case fell
# through to the applicability test, matched nothing (everything after the
# opening quote had been swallowed into the span) and the gate exited 0 as "not
# a merge". An apostrophe in a shell comment or a heredoc body reaches it.
#
# The commit gate normalises TWICE, and the first cut of this guard read the
# whitespace pass rather than the opaque-token pass, so it never fired at all
# while the close gate's identical guard worked. That is asserted here too.
# =============================================================================
UNLEX="$WORK/unlexable"; close_fixture "$UNLEX" no no answered no no true

run_hook "$HOOKS/close-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine && $MERGE_CMD")"
expect_deny "close-gate unlexable: an unterminated quote refuses instead of reading past it" "CG-UNLEXABLE"

run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine && git commit -m x")"
expect_deny "commit-gate unlexable: an unterminated quote refuses instead of reading past it" "CM-UNLEXABLE"

# The ALLOW direction, and it is the one that matters. Failing closed on every
# stray apostrophe would gate unrelated Bash calls for the whole session, so a
# raw payload that does not mention the governed verb is none of the gate's
# business even when it cannot be lexed.
run_hook "$HOOKS/close-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine")"
expect_allow "close-gate unlexable: an unbalanced quote with no merge in it is not this gate's business"
run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine")"
expect_allow "commit-gate unlexable: an unbalanced quote with no commit in it is not this gate's business"

# And the ordinary contraction, which is BALANCED and must stay unaffected. This
# is the case F5 broke inside its own fix once already.
run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "git commit -m 'don'\\''t'")"
expect_allow "commit-gate unlexable: the ordinary way of writing a contraction still lexes"

# A trunk that is PRESENT and not a non-empty string. jq's `//` falls back only
# on null and false, so `{"trunk":""}` yielded an empty TRUNK, every comparison
# against the current branch failed, and the trunk rule was silently disabled in
# both hooks. `[]` and `{}` did the same. Absent stays defaulted, because not
# declaring a trunk is ordinary; present-but-wrong is refused, because guessing
# "main" over a stated intention would govern a branch nobody named.
for bad_trunk in '""' '[]' '{}'; do
  TRV="$WORK/trunkval"; rm -rf "$TRV"; close_fixture "$TRV" no no answered no no true
  printf '{"scaffolded":true,"trunk":%s,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$bad_trunk" > "$TRV/.claude/sdd.json"
  run_hook "$HOOKS/close-gate.sh" "$TRV" "$(bash_payload "$MERGE_CMD")"
  expect_deny "close-gate trunk value: [$bad_trunk] is refused, not read as no trunk at all" "CG-TRUNK-INVALID"
  run_hook "$HOOKS/scope-hook.sh" "$TRV" "$(edit_payload "$TRV/src/app.js")"
  expect_deny "scope-hook trunk value: [$bad_trunk] is refused, not read as no trunk at all" "SH-TRUNK-INVALID"
done

# Backlog item 33a: the deny MESSAGE, not merely the deny CODE.
#
# Both lines built their text with unescaped nested double quotes, and bash
# concatenates "A"B"C" into ABC, so the quote marks silently vanished. The gate
# still denied, so no existing case noticed: what was lost is the only thing the
# message is for. "Set trunk to your trunk branch name" reads as a repetition;
# `Set "trunk" to your trunk branch name` names a JSON key.
#
# It was safe only by accident of content. `trunk`, `main` and `master` carry no
# glob characters and no whitespace, so the unquoted spans expanded to
# themselves. The next value with a space or a `*` in it would get word
# splitting or pathname expansion inside a deny string, which is a poor place to
# discover that. Asserted here because nothing read the emitted text before, and
# found by shellcheck (SC2140) in an instance's CI rather than by this repo's.
TRQ="$WORK/trunkquotes"; close_fixture "$TRQ" no no answered no no true
printf '{"scaffolded":true,"trunk":"","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRQ/.claude/sdd.json"

run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the key is quoted where the text declares it" 'declares a "trunk" that is not'
run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the key is quoted where the text says to set it" 'Set "trunk" to your trunk branch name'
run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the example branch names keep their quotes" '(for example "main" or "master")'

run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the key is quoted where the text declares it" 'declares a "trunk" that is not'
run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the key is quoted where the text says to set it" 'Set "trunk" to your trunk branch name'
run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the example branch names keep their quotes" '(for example "main" or "master")'

# The non-regression: a trunk key that is simply ABSENT still defaults, so this
# check cannot have turned an ordinary omission into a hard failure.
TRABS="$WORK/trunkabsent"; close_fixture "$TRABS" no no answered no no true
printf '{"scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRABS/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRABS" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk value: an ABSENT trunk still defaults to main and the gate still governs" "CG-"

# =============================================================================
# AN EMPTY QUOTED SPAN IS NOTHING, which is what the shell makes it. Two
# adjacent quotes concatenate to nothing, so a git prefixed or infixed by them
# IS git. The opaque-token scanner tested for ONE OR MORE shell-safe characters,
# so the empty string failed that test, became the inert @@Q@@ token, and split
# the very word it was glued to. Found by the fourth leg.
# =============================================================================
EMPTYQ="$WORK/empty-span"; close_fixture "$EMPTYQ" no no answered no no true
for eq_cmd in 'git ""commit -am x' '""git commit -am x' 'g""it commit -am x' "git ''commit -am x"; do
  run_hook "$HOOKS/commit-gate.sh" "$EMPTYQ" "$(bash_payload "$eq_cmd")"
  expect_deny "empty span: [$eq_cmd] is the same command as its unquoted form" "CM-"
done
for eq_cmd in 'git ""merge --no-ff spec/0001-thing' '""git merge --no-ff spec/0001-thing'; do
  run_hook "$HOOKS/close-gate.sh" "$EMPTYQ" "$(bash_payload "$eq_cmd")"
  expect_deny "empty span: [$eq_cmd] is the same command as its unquoted form" "CG-"
done
run_hook "$HOOKS/commit-gate.sh" "$EMPTYQ" "$(bash_payload 'git status')"
expect_allow "empty span: an ordinary command is unaffected by the empty-span rule"

# =============================================================================
# A QA VERDICT IS A VERDICT, NOT THE WORD PASS IN A SENTENCE (F5, third leg).
# The check matched PASS, PARTIAL or FAIL anywhere in the QA block, so prose
# satisfied it. Appendix C's shape puts the verdict at the end of its line, so
# that is what is required: narrow enough to reject prose, wide enough for every
# real shape. The ALLOW cases matter more than the deny one, because false
# denial is the direction that breaks honest closes.
#
# The verdict line is inserted against the QA Pass 2 marker, which is where
# close_fixture ends the QA Pass 1 block.
#
# PORTABLY, via awk and a temp file, because the two sed forms this used carried
# TWO GNU-only assumptions each and macOS has neither (1.0.9). `sed -i` without
# an argument is GNU: BSD sed reads the NEXT WORD as the backup suffix, so
# `sed -i 's|...|' file` consumes the script as a suffix and fails. And `\n` in a
# sed REPLACEMENT is GNU: BSD sed inserts a literal `n`, so even a corrected
# `-i ''` would have written "...not run" followed by "nn- QA Pass 2..." and the
# assertion would have failed for a reason having nothing to do with the gate.
#
# awk needs neither: it prints the inserted lines itself.
# insert_block_before <file> <marker-line> <block-file>
#
# insert_before below passes its text through `awk -v`, and BWK awk (the macOS
# userland) REFUSES a newline in a -v assignment: "awk: newline in string".
# It does not warn and carry on, it exits 2, so the awk writes nothing, the
# `&& mv` never runs, and the file is left UNCHANGED. A multi-line insertion
# through that path therefore inserts nothing and the fixture silently keeps
# whatever it already had, which is how a corpus written to prove a new rule
# passes by testing the old one. The QA verdict block is multi-line by
# construction, so it goes through a FILE and awk's getline instead.
insert_block_before() {
  awk -v marker="$2" -v bf="$3" '
    $0 == marker { while ((getline line < bf) > 0) print line; close(bf); print "" }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

insert_before() { # insert_before <file> <marker-line> <text>
  awk -v marker="$2" -v ins="$3" '
    $0 == marker { print ins; print "" }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ===========================================================================
# THE QA VERDICT IS A STRUCTURE (2026-08-05 leg, F5).
#
# The rule these corpora used to pin was a regex over English, and F5 closed it
# with one line: `Criteria that did not PASS: 2, 5 and 7.` A sentence stating
# the OPPOSITE of a pass satisfied the close gate, the git hook and the trunk
# audit, and the merge landed. The three layers were in deliberate byte-identical
# lockstep, so the gate and its only backstop were blind together, as designed.
#
# The class fix is not a tighter pattern. Part 6 now requires a fenced qa-pass-1
# block whose every line is `<criterion>: PASS|PARTIAL|FAIL` with a space-free
# criterion, and the payload is UNWRITEABLE there rather than refused.
#
# Both directions, and the negative corpus is the one that matters: it is the
# F5 payload and its three measured siblings, plus the prose and tally cases the
# old rule already refused, all of which must stay refused.
# ===========================================================================

# NEGATIVE: a sentence is not a verdict, however it reads, and a spec carrying
# ONLY the pasted report has no verdict at all now.
for qa_prose in \
  'Criteria that did not PASS: 2, 5 and 7.' \
  'Blocked on staging: FAIL to reach the host, so QA Pass 1 never ran.' \
  'Mobile was never exercised, so nothing there can PASS.' \
  'No criterion was checked; there is nothing here that could PASS.' \
  'the browser tests PASS on my machine but mobile was never run' \
  'we expect the suite to PASS once the hardware arrives' \
  'a criterion that would FAIL under load was never exercised' \
  'the 3 browser tests PASS on my machine but mobile was never run'; do
  QAN="$WORK/qa-neg"; rm -rf "$QAN"; close_fixture "$QAN" yes no answered yes no true
  git -C "$QAN" checkout -q spec/0001-thing
  insert_before "$QAN/specs/0001-thing.md" '- QA Pass 2 (human): done' "$qa_prose"
  git -C "$QAN" add -A >/dev/null 2>&1; git -C "$QAN" commit -qm "prose" >/dev/null 2>&1
  git -C "$QAN" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAN" "$(bash_payload "$MERGE_CMD")"
  expect_deny "qa verdict negative: [$qa_prose] is not a verdict block" "CG-NO-QA-VERDICT"
done

# NEGATIVE, INSIDE THE BLOCK, which is the direction that makes the structure
# worth having. A non-verdict line inside the fence is REFUSED, not skipped,
# because skipping is exactly how a sentence gets back in.
for qa_inner in \
  'Criteria that did not PASS: 2, 5 and 7.' \
  '4 PASS / 0 FAIL' \
  'Section A: 17/17 PASS' \
  '| 1 | criterion | PASS | evidence |'; do
  QAI="$WORK/qa-inner"; rm -rf "$QAI"; close_fixture "$QAI" yes no answered yes no true
  git -C "$QAI" checkout -q spec/0001-thing
  printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n%s\n```\n' "$qa_inner" > "$WORK/qa-blk.txt"
  insert_block_before "$QAI/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
  git -C "$QAI" add -A >/dev/null 2>&1; git -C "$QAI" commit -qm "inner" >/dev/null 2>&1
  git -C "$QAI" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAI" "$(bash_payload "$MERGE_CMD")"
  expect_deny "qa verdict inner: [$qa_inner] inside the block is refused, not skipped" "CG-NO-QA-VERDICT"
done

# POSITIVE. The criterion is a bare identifier, so these are the shapes a real
# spec produces: plain numbers, the AC-style ids two live instances use, and
# dotted or underscored ids. The nine prose shapes item 35 collected from real
# specs are no longer load-bearing: they stay in the pasted report below the
# block, which no gate reads.
for qa_block in \
  '1: PASS' \
  '1: PASS
2: PARTIAL
3: FAIL' \
  'AC-B1: PASS' \
  'crit_2.a: PARTIAL' \
  '1:PASS'; do
  QAOK="$WORK/qa-ok"; rm -rf "$QAOK"; close_fixture "$QAOK" yes no answered yes no true
  git -C "$QAOK" checkout -q spec/0001-thing
  printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n%s\n```\n' "$qa_block" > "$WORK/qa-blk.txt"
  insert_block_before "$QAOK/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
  git -C "$QAOK" add -A >/dev/null 2>&1; git -C "$QAOK" commit -qm "verdict" >/dev/null 2>&1
  git -C "$QAOK" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAOK" "$(bash_payload "$MERGE_CMD")"
  expect_allow "qa verdict: a qa-pass-1 block of [$(printf '%s' "$qa_block" | tr '\n' ' ')] closes"
done

# THE UNEDITED TEMPLATE MUST NOT CLOSE. Appendix C ships the block with a
# placeholder inside it, and a placeholder is not a verdict.
QATPL="$WORK/qa-tpl"; rm -rf "$QATPL"; close_fixture "$QATPL" yes no answered yes no true
git -C "$QATPL" checkout -q spec/0001-thing
printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n<one line per criterion: delete this note>\n```\n' > "$WORK/qa-blk.txt"
insert_block_before "$QATPL/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
git -C "$QATPL" add -A >/dev/null 2>&1; git -C "$QATPL" commit -qm tpl >/dev/null 2>&1
git -C "$QATPL" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$QATPL" "$(bash_payload "$MERGE_CMD")"
expect_deny "qa verdict template: the unedited Appendix C placeholder does not close" "CG-NO-QA-VERDICT"

# THE LOCKSTEP ITSELF, and it is the point rather than a nicety. The three
# layers are written independently and asserted IDENTICAL, so a widening applied
# to one and not the others fails here rather than in the field. F5 reached the
# backstop THROUGH this lockstep, and the lockstep is kept anyway: the answer to
# a gate and its backstop agreeing on a wrong rule is a right rule, not two
# rules. Leading whitespace and the SLH_ prefix are stripped before comparing.
QA_LOCK_BAD=""
QA_LOCK_REF=""
for qa_lock_f in "$HOOKS/close-gate.sh" "$SCRIPTS/trunk-audit.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; do
  qa_lock_v="$(grep -m1 -E '^[[:space:]]*(SLH_)?QA_PASS1_AWK=' "$qa_lock_f" | sed 's/^[[:space:]]*//; s/^SLH_//' || true)" # fail-open-ok: an empty value is the finding and is tested immediately below
  if [[ -z "$qa_lock_v" ]]; then
    QA_LOCK_BAD="$QA_LOCK_BAD $(basename "$qa_lock_f"):absent"
  elif [[ -z "$QA_LOCK_REF" ]]; then
    QA_LOCK_REF="$qa_lock_v"
  elif [[ "$qa_lock_v" != "$QA_LOCK_REF" ]]; then
    QA_LOCK_BAD="$QA_LOCK_BAD $(basename "$qa_lock_f"):differs"
  fi
done
if [[ -z "$QA_LOCK_BAD" ]]; then
  ok "qa verdict lockstep: all three layers carry a byte-identical QA_PASS1_AWK"
else
  bad "qa verdict lockstep: all three layers carry a byte-identical QA_PASS1_AWK" \
      "these do not agree:$QA_LOCK_BAD"
fi

# THE SAME LOCKSTEP FOR THE TEMPLATE STRIPPER (v1.9 leg, V19-F4).
#
# Its three copies ARE byte-identical and always have been, so no gate was
# misbehaving. What was missing is the DETECTOR: a drifted copy passed the whole
# suite and nothing said so, while TWO comments in the shipped bytes claimed the
# lockstep was asserted. The sibling lexers QA_PASS1_AWK and SLH_LIVE_TEXT_AWK
# both have this assertion, which is why the pattern looked present until
# somebody checked which of the three had one: A9's sibling rule applied to the
# assertions rather than to the code.
#
# It matters more from 2026-08-26 than it did when it was filed. Until this
# commit the stripper had ONE caller in the library; the V19-F2 fix gave it a
# second (the lifecycle detector), so a drifted copy now moves what pre-commit
# accepts as well as what the close verification accepts.
#
# Watched RED first against a deliberately drifted copy: appending a single
# space to close-gate.sh's value took this assertion to close-gate.sh:differs
# with the rest of the suite unchanged.
TF_LOCK_BAD=""
TF_LOCK_REF=""
for tf_lock_f in "$HOOKS/close-gate.sh" "$SCRIPTS/trunk-audit.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; do
  tf_lock_v="$(grep -m1 -E '^[[:space:]]*(SLH_)?TEMPLATE_FENCE_AWK=' "$tf_lock_f" | sed 's/^[[:space:]]*//; s/^SLH_//' || true)" # fail-open-ok: an empty value is the finding and is tested immediately below
  if [[ -z "$tf_lock_v" ]]; then
    TF_LOCK_BAD="$TF_LOCK_BAD $(basename "$tf_lock_f"):absent"
  elif [[ -z "$TF_LOCK_REF" ]]; then
    TF_LOCK_REF="$tf_lock_v"
  elif [[ "$tf_lock_v" != "$TF_LOCK_REF" ]]; then
    TF_LOCK_BAD="$TF_LOCK_BAD $(basename "$tf_lock_f"):differs"
  fi
done
if [[ -n "$TF_LOCK_REF" && -z "$TF_LOCK_BAD" ]]; then
  ok "template stripper lockstep: all three layers carry a byte-identical TEMPLATE_FENCE_AWK"
else
  bad "template stripper lockstep: all three layers carry a byte-identical TEMPLATE_FENCE_AWK" \
      "ref-empty=[${TF_LOCK_REF:0:1}] disagreements:$TF_LOCK_BAD"
fi

# =============================================================================
# A FUNCTION DEFINITION AND A TWO-OPERAND CHECKOUT (F6/F7, third 1.0.8 leg).
# Both put something other than the governed verb where the gate looks, and the
# checkout one is the FOURTH spelling of a class the previous three repairs each
# closed one spelling at a time. Counting operands settles it without asking
# what any operand looks like, which is what the earlier repairs kept doing.
# =============================================================================
FN="$WORK/fn-and-pathspec"; close_fixture "$FN" no no answered no no true
git -C "$FN" branch feat-y main >/dev/null 2>&1

for fn_cmd in \
  'function f { git merge --no-ff spec/0001-thing; }; f' \
  'f() { git merge --no-ff spec/0001-thing; }; f' \
  'git checkout feat-y src/app.js; git merge --no-ff spec/0001-thing' \
  'git checkout feat-y specs/STATUS.md && git merge --no-ff spec/0001-thing' ; do
  run_hook "$HOOKS/close-gate.sh" "$FN" "$(bash_payload "$fn_cmd")"
  expect_deny "hidden verb: [$fn_cmd] is still judged" "CG-"
done

# ALLOW: a ONE-operand checkout is a real switch and must keep working, or the
# operand count has turned the branch tracker off rather than fixing it.
run_hook "$HOOKS/close-gate.sh" "$FN" "$(bash_payload 'git checkout feat-y && git merge --no-ff spec/0001-thing')"
expect_allow "hidden verb: a one-operand checkout still switches, so the tracker still works"

# A ROLES value that is not an object disabled the scope hook entirely: the jq
# extraction errored, ROLE_PATHS came back empty, and the deny loop ran zero
# times. Same shape as the trunk value, one key across.
for roles_v in '"src"' '[]' '123'; do
  RLS="$WORK/roles-shape"; rm -rf "$RLS"; close_fixture "$RLS" no no answered no no true
  printf '{"scaffolded":true,"trunk":"main","gate_command":"true","roles":%s}\n' "$roles_v" > "$RLS/.claude/sdd.json"
  run_hook "$HOOKS/scope-hook.sh" "$RLS" "$(edit_payload "$RLS/src/app.js")"
  expect_deny "roles shape: [$roles_v] is refused, not read as no roles at all" "SH-ROLES-SHAPE"
done

# =============================================================================
# THE TRUNK VALUE MUST NAME A LOCAL BRANCH (F1, second 1.0.8 leg). The check
# added earlier the same day required a non-empty string and stopped there,
# which is the same "container, not contents" error one level in.
#
# The route was the SHIPPED UPGRADE PATH: skills/upgrade told the agent to
# detect the trunk with `git symbolic-ref refs/remotes/origin/HEAD`, which
# returns a full ref path. Every ordinary clone has an origin/HEAD, so that is
# what got recorded, and both hooks then compared `refs/remotes/origin/main`
# against `main` and allowed every governed operation in silence.
# =============================================================================
TRB="$WORK/trunk-branch"; close_fixture "$TRB" no no answered no no true
git -C "$TRB" update-ref refs/remotes/origin/main "$(git -C "$TRB" rev-parse main)" 2>/dev/null
git -C "$TRB" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null

for trunk_spelling in 'refs/remotes/origin/main' 'refs/heads/main' 'heads/main' 'origin/main'; do
  printf '{"scaffolded":true,"trunk":"%s","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' \
    "$trunk_spelling" > "$TRB/.claude/sdd.json"
  run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
  expect_deny "trunk spelling: [$trunk_spelling] reduces to the branch and the gate still governs" "CG-"
  run_hook "$HOOKS/scope-hook.sh" "$TRB" "$(edit_payload "$TRB/src/app.js")"
  expect_deny "trunk spelling: [$trunk_spelling] still guards trunk writes" "SH-"
done

# A trunk naming NO local branch is refused rather than guessed at. Guessing
# "main" would silently govern a branch the project never named.
printf '{"scaffolded":true,"trunk":"no-such-branch","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRB/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
expect_deny "trunk spelling: a trunk that names no local branch is refused, not guessed" "CG-TRUNK-NOT-A-BRANCH"

# And the ordinary value is untouched.
printf '{"scaffolded":true,"trunk":"main","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRB/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
expect_deny "trunk spelling: a plain branch name still works exactly as before" "CG-"

# =============================================================================
# AN OPTION'S VALUE IS NOT AN OPTION, AND NOT A REF (F4/F5, second 1.0.8 leg).
# Every word after `merge` was scanned as both, so the VALUE of -m was read as
# though it had been typed as a flag: `-m "--continue"` matched the resumption
# exemption and skipped every close check, and a message word could resolve as
# a ref and make the gate validate a different branch from the one merged.
# =============================================================================
OPTV="$WORK/optvalue"; close_fixture "$OPTV" no no answered no no true

for optv_cmd in \
  'git merge --no-ff spec/0001-thing -m "--continue"' \
  'git merge --no-ff spec/0001-thing -m --abort' \
  'git merge --no-ff spec/0001-thing -m --quit' \
  'git merge --no-ff spec/0001-thing -m spec/0002-other' ; do
  run_hook "$HOOKS/close-gate.sh" "$OPTV" "$(bash_payload "$optv_cmd")"
  expect_deny "option value: [$optv_cmd] is judged on the branch, not on its message" "CG-"
done

# The two ALLOW directions, and they are why this is a value-stripping fix
# rather than a blanket refusal of -m. A REAL resumption must stay exempt, or a
# conflicted close has no permitted way to finish; and an ordinary close with an
# ordinary message must still pass.
run_hook "$HOOKS/close-gate.sh" "$OPTV" "$(bash_payload 'git merge --continue')"
expect_allow "option value: a REAL --continue is still exempt, so a conflicted close can finish"

# =============================================================================
# AN OCTOPUS MERGE IS SEVERAL MERGES (F2/F6 of the second 1.0.8 leg). The word
# loop broke on the FIRST operand that resolved to a spec or chore ref, so
# `git merge --no-ff spec/0003-good spec/0004-bad` contributed exactly one ref:
# the compliant branch was judged and the unclosed one landed on the trunk with
# every close check skipped. A command that merges several branches answers for
# all of them, exactly as a command carrying several commits does.
# =============================================================================
OCTO="$WORK/octopus"; close_fixture "$OCTO" no no answered no no true
git -C "$OCTO" checkout -q main
git -C "$OCTO" checkout -q -b spec/0009-good
mkdir -p "$OCTO/specs"
printf '# Spec 0009\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$OCTO/specs/0009-good.md"
printf '# Spec inventory\n\n| Num | Title | Status |\n| --- | --- | --- |\n| 0009 | Good | CLOSED |\n' > "$OCTO/specs/STATUS.md"
git -C "$OCTO" add -A >/dev/null 2>&1; git -C "$OCTO" commit -qm "close 0009" >/dev/null 2>&1
git -C "$OCTO" checkout -q main

# The compliant branch alone must pass, or the two cases below prove nothing.
run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good')"
expect_allow "octopus: the compliant branch alone is allowed, so the control is real"

run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good spec/0001-thing')"
expect_deny "octopus: a non-compliant SECOND operand is still judged" "CG-"

run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0001-thing spec/0009-good')"
expect_deny "octopus: order does not matter; the non-compliant operand is judged either way" "CG-"

# ---------------------------------------------------------------------------
# THE OTHER HALF OF THE SAME SENTENCE (leg 4, F3).
#
# The fix above extended the COLLECTION and left the DISPOSITION short-circuited.
# One operand that resolved reached `continue` and every operand beside it was
# never classified at all, so an operand this gate REFUSES on its own was waved
# through by a compliant sibling:
#
#     git merge --no-ff FETCH_HEAD                  DENY, correctly
#     git merge --no-ff spec/0009-good FETCH_HEAD   ALLOWED, and it landed
#
# Executed for real, the octopus merge succeeded and unreviewed content was on
# the trunk. The trunk audit did not catch it either: it read the smuggled
# parent as a chore merge and reported 0 violations.
#
# Asserted over the SET of indirect forms rather than over FETCH_HEAD, which is
# the one a finding happened to use, and with a chore branch as the resolvable
# operand as well as a spec branch: chore branches need no artifacts at all, so
# that is the cheapest spelling of the attack, not an exotic one.
git -C "$OCTO" update-ref FETCH_HEAD spec/0001-thing
git -C "$OCTO" checkout -q -b chore/octo-cleanup main 2>/dev/null || git -C "$OCTO" checkout -q chore/octo-cleanup
printf 'cleanup\n' > "$OCTO/cleanup.txt"
git -C "$OCTO" add -A >/dev/null 2>&1; git -C "$OCTO" commit -qm "chore" >/dev/null 2>&1
git -C "$OCTO" checkout -q main

for resolvable in spec/0009-good chore/octo-cleanup; do
  for indirect in FETCH_HEAD ORIG_HEAD HEAD '-' '@{-1}' '$EVIL'; do
    run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "git merge --no-ff $resolvable $indirect")"
    expect_deny "octopus indirect: [$resolvable $indirect] is refused; a resolvable sibling does not vouch for an unverifiable operand" "CG-UNNAMEABLE-REF"
    run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "git merge --no-ff $indirect $resolvable")"
    expect_deny "octopus indirect: [$indirect $resolvable] is refused in the other order too" "CG-UNNAMEABLE-REF"
  done
done

# An operand that LOOKS like a spec branch and resolves to nothing is the same
# case with a different cause, and it had the same hole: SEG_LOOKS_SPEC is set
# for spec-shaped words whether or not they resolve, so it could not answer
# "was anything left unresolved" and the disposition never asked.
run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good spec/9999-nonexistent')"
expect_deny "octopus indirect: an unresolvable spec-shaped operand is refused beside a compliant one" "CG-UNNAMEABLE-REF"

# AND THE DIRECTION THAT MAKES IT A FIX RATHER THAN A BLANKET REFUSAL. An
# OPTION is not an operand, and `-` and `--no-ff` both start with a dash. If
# these regress, every close in the field breaks.
for allowed_cmd in \
  'git merge --no-ff spec/0009-good' \
  'git merge --squash spec/0009-good' \
  'git merge -s recursive --no-ff spec/0009-good' \
  'git merge -X ours --no-ff spec/0009-good' \
  'git merge --no-ff spec/0009-good -m "closing 0009"' \
  'git merge --no-ff spec/0009-good chore/octo-cleanup' ; do
  run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "$allowed_cmd")"
  expect_allow "octopus indirect control: [$allowed_cmd] still merges, so options were not mistaken for operands"
done

# =============================================================================
# A CHECKOUT IS CONDITIONAL (F7 of the 1.0.8 leg). The tracker modelled every
# checkout as unconditionally taken, which is false for the commonest failure
# there is: a checkout ABORTS when local changes would be overwritten, and after
# it aborts the shell is still on the trunk. So the merge ran on the trunk while
# the gate believed it was standing on a feature branch.
#
# Only `&&` implies the previous command succeeded. It is kept exact rather than
# swept in with the others, because denying it would break an ordinary workflow:
# if that checkout fails, the merge never runs at all.
# =============================================================================
SWFIX="$WORK/switch-conditional"; close_fixture "$SWFIX" no no answered no no true
git -C "$SWFIX" branch feat-x main >/dev/null 2>&1

run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x; git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: a merge reached across ; from a checkout is unresolved, not 'some other branch'" "CG-UNRESOLVED-SWITCH"

run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x || git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: || does not imply the checkout succeeded either" "CG-UNRESOLVED-SWITCH"

# ALLOW: && DOES imply success, so a merge onto a feature branch is not a close
# and must not be denied. This is the assertion that stops the repair from being
# "deny everything with a checkout in it".
run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x && git merge --no-ff spec/0001-thing')"
expect_allow "conditional switch: && implies success, so a merge on a feature branch is still allowed"

# DENY: the compound close is the whole reason the tracker exists, and it must
# survive the repair intact.
run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout main && git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: the compound close onto the trunk is still gated" "CG-"

# =============================================================================
# COMMAND POSITION, part three: redirections and path-qualified wrappers.
# All three found by the 1.0.8 leg (F17, F18) and by the oracle once its corpus
# was taught to generate them. None is adversarial: a caller silencing output
# writes a redirection without thinking about parsers, /usr/bin/env is what a
# shebang produces, and 2>&1 is how everyone spells it.
# =============================================================================
for pos_cmd in \
  '>/dev/null git merge --no-ff spec/0001-thing' \
  '2>/dev/null git merge --no-ff spec/0001-thing' \
  '< /dev/null git merge --no-ff spec/0001-thing' \
  '>/tmp/out 2>&1 git merge --no-ff spec/0001-thing' \
  '/usr/bin/env git merge --no-ff spec/0001-thing' \
  '/bin/nice git merge --no-ff spec/0001-thing' \
  '/usr/bin/nohup git merge --no-ff spec/0001-thing' \
  '>/tmp/out 2>&1 /usr/bin/env git merge --no-ff spec/0001-thing' ; do
  if [[ "$(corpus_verdict "$pos_cmd")" == "deny" ]]; then
    ok "command position: [$pos_cmd] is judged"
  else
    bad "command position: [$pos_cmd] must be judged" \
        "something other than git sat at the head of the segment and the merge was never inspected"
  fi
done

# The `&` inside a redirection is NOT a control operator. `2>&1` was cut by the
# segment splitter into `2>` and `1 git merge ...`, so neither fragment began
# with git. Asserted separately from the loop above because it is a splitter
# defect rather than a stripping one, and the two fail differently.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing >/tmp/o 2>&1')" == "deny" ]]; then
  ok "command position: a trailing 2>&1 does not split the command away from its verb"
else
  bad "command position: a trailing 2>&1 must not split the command" \
      "the fd-duplication ampersand was read as a segment separator"
fi

# The ALLOW direction. Stripping redirections must not make the gate blind to
# what follows, nor deny ordinary redirected work that merges nothing.
if [[ "$(corpus_verdict '>/dev/null git status')" == "allow" ]]; then
  ok "command position: a redirected non-merge is still allowed"
else
  bad "command position: a redirected non-merge must still be allowed" \
      "stripping redirections turned an ordinary command into a denial"
fi

# =============================================================================
# The spec-versus-chore TIE-BREAK, and the ambiguity refusal beside it.
#
# 1.0.8's identity-by-commit rewrite ended in `... | head -n1` over a
# refname-sorted list. `refs/heads/chore/*` sorts before `refs/heads/spec/*`, so
# a chore ref on the same commit won, SPEC_BRANCH read as a chore branch, and
# the `== spec/*` guard skipped the entire close block: no Closing report, no QA
# verdict, no diagram, no STATUS row, no authorship check. It did not fail to
# close the alias hole, it INVERTED it, because 1.0.7 classified by NAME and so
# kept the canonical spelling governed whatever else pointed at the commit.
#
# Four assertions, because three of them can pass for the wrong reason alone.
# =============================================================================

# 1. The regression itself. chore/cleanup is on spec/0001-thing's commit (see
#    the corpus setup), and the merge names the SPEC branch, not the chore one.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "tie-break: a chore/ ref on the same commit does not disarm the close checks"
else
  bad "tie-break: a chore/ ref on the same commit must not disarm the close checks" \
      "a chore sibling made an unclosed spec branch mergeable; the spec-over-chore preference has regressed to head -n1"
fi

# 2. The deny must name the SPEC branch. Denying for the wrong reason is how two
#    of the 2026-07-27 findings first read as refutations.
if bash_payload 'git merge --no-ff spec/0001-thing' \
     | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null \
     | grep -q 'spec/0001-thing'; then
  ok "tie-break: the deny names the spec branch, not the chore ref beside it"
else
  bad "tie-break: the deny must name the spec branch" \
      "the gate denied but reported a chore ref, so it judged the wrong object and the verdict is right by accident"
fi

# 3. THE ALLOW DIRECTION, which is the assertion that carries the weight. A
#    tie-break repair that simply denies more would satisfy every check above.
#    A COMPLIANT close must still pass with a chore sibling present.
#    Uses the suite's own run_hook/expect_allow idiom rather than a hand-rolled
#    jq read. The first cut of this assertion piped the hook into
#    `jq -r '... // "allow"'`, and an ALLOW emits NOTHING, so jq had no input
#    document, the `//` default never fired, and an empty string was compared
#    against "allow". It reported the fix as breaking honest closes when the
#    fix was fine. That is this repo's signature defect appearing inside the
#    test written to catch this repo's signature defect.
TIEOK="$WORK/tiebreak-allow"
close_fixture "$TIEOK" yes yes answered yes no true
git -C "$TIEOK" branch -f chore/cleanup spec/0001-thing
run_hook "$HOOKS/close-gate.sh" "$TIEOK" "$(bash_payload "$MERGE_CMD")"
expect_allow "tie-break: a COMPLIANT close is still allowed with a chore ref on the same commit"

# 4. TWO DIFFERENT SPECS on one commit. The gate cannot tell whose Closing
#    report it is judging, so it refuses instead of picking one and validating
#    one spec's artifacts for a merge of another.
#
#    Distinctness is by spec NUMBER and not by ref count, deliberately: a local
#    branch, its remote-tracking copy and a tag are three refs for ONE spec, and
#    refusing those would deny every ordinary close. That non-regression is
#    covered by the remote-tracking cases elsewhere in this file.
TIEAMB="$WORK/tiebreak-ambiguous"
close_fixture "$TIEAMB" no no answered no no true
git -C "$TIEAMB" branch -f spec/0009-alias spec/0001-thing
if bash_payload 'git merge --no-ff spec/0001-thing' \
     | CLAUDE_PROJECT_DIR="$TIEAMB" bash "$HOOKS/close-gate.sh" 2>/dev/null \
     | grep -qF 'CG-AMBIGUOUS-SPEC'; then
  ok "tie-break: two different specs on one commit is refused, not resolved by sort order"
else
  bad "tie-break: two different specs on one commit must be refused" \
      "the gate picked one spec and judged its artifacts for a merge that could be either; that is the wrong-object class the rewrite exists to end"
fi

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
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
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

# --- the FLAG-VALUED WRAPPER axis, commit gate (1.0.7) ----------------------
# The same stranded-value defect, same stripper, other gate. Asserted here
# rather than assumed from the close-gate cases: the two hooks carry their own
# copies of strip_wrappers, so a fix in one is not a fix in the other, and this
# suite has already watched a repair land in one place and not the other.
CGFW_N=0; CGFW_FAIL=""
for wrap in 'nice -n 5 ' 'LANG=C nice -n 5 ' 'env -u FOO ' 'env -i ' 'stdbuf -o 0 '; do
  for tail in 'git commit -am x' 'git add -A && git commit -m x'; do
    CGFW_N=$((CGFW_N + 1))
    [[ "$(cg_verdict "${wrap}${tail}")" == "deny" ]] || CGFW_FAIL="$CGFW_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CGFW_FAIL" ]]; then
  ok "commit corpus flag-valued wrappers: all $CGFW_N spellings are denied"
else
  bad "commit corpus flag-valued wrappers: a wrapper flag with a separate value must not escape the commit gate" \
      "these reached the index unchecked:$CGFW_FAIL"
fi
CGFW_ALLOW_FAIL=""
for cmd in 'nice -n 5 git status' 'env -u GIT_DIR git log' 'env -i git fetch'; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGFW_ALLOW_FAIL="$CGFW_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGFW_ALLOW_FAIL" ]]; then
  ok "commit corpus flag-valued wrappers: ordinary wrapped commands still pass"
else
  bad "commit corpus flag-valued wrappers: ordinary wrapped commands must still pass" \
      "these were denied:$CGFW_ALLOW_FAIL"
fi


# --- the INDEX-VERB axis, commit gate (1.0.7) -------------------------------
# Check 0 enumerated add, rm and mv. Every OTHER verb that writes the index
# could therefore be compounded with a commit, and the three staged-content
# checks would scan an index nobody had judged:
#
#     git stash pop && git commit -m x
#     git restore --staged . && git commit -m x
#
# Both were ALLOWED by v1.0.6 and by 1.0.7 until this axis. `git stage`, a plain
# synonym for `add`, was missing for the same reason: nobody wrote it down.
#
# This list is the DIMENSION. It is written here independently of the hook's, and
# the lockstep assertion below requires the two to be identical, so a verb added
# to one without the other is a suite failure rather than a reviewer's catch.
# That is the whole repair: the wrapper axis, the dash-valued flag axis and this
# one were all the same defect, an enumeration that looked complete because
# nobody had listed what completeness meant.
CG_INDEX_VERBS='add stage rm mv restore reset stash checkout switch merge pull rebase cherry-pick revert am apply update-index read-tree sparse-checkout'

# POSITION DECIDES, AND THIS CORPUS USED TO ASSERT OTHERWISE (1.1.0 adversarial review,
# F1). Both orders were required to deny, so the suite pinned the very behaviour
# the leg reported: `git commit -m "x" && git checkout -` was refused, and that
# is the canonical spec-branch workflow the framework prescribes, commit on the
# branch and return to where you were. Check 0's own stated reason is positional
# ("the gate would scan a stale index"), and when the commit runs FIRST the index
# the gate scanned is exactly the index that gets committed.
#
# So the two orders are now asserted in OPPOSITE directions, which is what makes
# this a test of the rule rather than of one side of it. The deny direction is
# unchanged and is still the one that matters.
CGIV_N=0; CGIV_FAIL=""
for verb in $CG_INDEX_VERBS; do
  cmd="git $verb x && git commit -m x"
  CGIV_N=$((CGIV_N + 1))
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGIV_FAIL="$CGIV_FAIL
    $cmd"
done
if [[ -z "$CGIV_FAIL" ]]; then
  ok "commit corpus index verbs: all $CGIV_N stage-THEN-commit compounds are denied"
else
  bad "commit corpus index verbs: a verb that writes the index BEFORE a commit must be denied" \
      "these scanned a stale index unchecked:$CGIV_FAIL"
fi

# The allow direction of the same rule. An index writer AFTER the commit stages
# for some later commit, which this gate will see when it is run; it cannot make
# the index this commit uses stale, because that index has already been read.
CGIVA_N=0; CGIVA_FAIL=""
for verb in $CG_INDEX_VERBS; do
  cmd="git commit -m x && git $verb x"
  CGIVA_N=$((CGIVA_N + 1))
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGIVA_FAIL="$CGIVA_FAIL
    $cmd"
done
if [[ -z "$CGIVA_FAIL" ]]; then
  ok "commit corpus index verbs: all $CGIVA_N commit-THEN-index-writer compounds are allowed"
else
  bad "commit corpus index verbs: an index writer AFTER the commit must not be denied" \
      "the framework refused work its own protocol prescribes:$CGIVA_FAIL"
fi

# The payload exactly as the leg wrote it, kept beside the generated dimension
# because a dimension only tests the shape somebody imagined.
if [[ "$(cg_verdict 'git commit -m "x" && git checkout -')" == "allow" ]]; then
  ok "commit corpus index verbs: the leg's own F1 payload (commit then return) is allowed"
else
  bad "commit corpus index verbs: the leg's own F1 payload (commit then return) is allowed" \
      "git commit -m \"x\" && git checkout - was denied, which is the canonical spec-branch workflow"
fi

# The real-world spellings from the adversarial review, with their actual flags rather
# than the generated `git <verb> x` shape. A dimension only tests the form you
# imagined, which is exactly how `nice -5` sailed through the dash-valued axis.
CGIV_REAL_FAIL=""
for cmd in \
  'git stash pop && git commit -m x' \
  'git stash apply && git commit -m x' \
  'git restore --staged . && git commit -m x' \
  'git stage -A && git commit -m x' \
  'git reset HEAD~1 && git commit -m x' \
  'git checkout HEAD -- src/a.txt && git commit -m x' \
  'git cherry-pick -n abc123 && git commit -m x' \
  'git revert --no-commit abc123 && git commit -m x' \
  'git apply --index p.patch && git commit -m x' \
  'git update-index --add src/a.txt && git commit -m x' \
  'nice -n 5 git stash pop && git commit -m x' \
  'git stash pop; git commit -m x' \
  'git stash pop | git commit -m x' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGIV_REAL_FAIL="$CGIV_REAL_FAIL
    $cmd"
done
if [[ -z "$CGIV_REAL_FAIL" ]]; then
  ok "commit corpus index verbs: the leg's real spellings are denied, with their own flags and separators"
else
  bad "commit corpus index verbs: a real index-writing spelling escaped the gate" \
      "these reached the index unchecked:$CGIV_REAL_FAIL"
fi

# The lockstep. The hook owns the pattern; this suite owns the dimension; they
# must agree. Read out of the shipped hook rather than restated, so the failure
# names the drift instead of hiding it.
CG_HOOK_VERBS="$(grep -E "^INDEX_VERBS='" "$HOOKS/commit-gate.sh" | sed -E "s/^INDEX_VERBS='//; s/'$//" | tr '|' ' ')"
CG_WANT="$(printf '%s\n' $CG_INDEX_VERBS | LC_ALL=C sort | tr '\n' ' ')"
CG_GOT="$(printf '%s\n' $CG_HOOK_VERBS | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$CG_WANT" == "$CG_GOT" && -n "$CG_GOT" ]]; then
  ok "commit corpus index verbs: the hook's enumeration and this corpus are identical"
else
  bad "commit corpus index verbs: the hook's INDEX_VERBS and this corpus have drifted" \
      "corpus: $CG_WANT
      hook  : $CG_GOT
      Adding a verb to one without the other is how this dimension went missing in the first place."
fi

# The INVERSE, and it carries the weight here. A gate that denies everything
# also denies every stale index, so a passing deny column proves nothing on its
# own. These are verbs that do NOT write the index, and a read-only command
# compounded with a commit must still pass.
CGIV_ALLOW_FAIL=""
for cmd in \
  'git status && git commit -m x' \
  'git log --oneline && git commit -m x' \
  'git diff --cached && git commit -m x' \
  'git fetch origin && git commit -m x' \
  'git branch -a && git commit -m x' \
  'echo git stash pop && git commit -m x' \
  'git commit -m "after git stash pop"' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGIV_ALLOW_FAIL="$CGIV_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGIV_ALLOW_FAIL" ]]; then
  ok "commit corpus index verbs: read-only verbs and mere mentions still pass"
else
  bad "commit corpus index verbs: a command that does not write the index must still pass" \
      "these were denied:$CGIV_ALLOW_FAIL"
fi

# The commit gate carries its own copy of strip_wrappers, and a repair in one
# has failed to be a repair in the other more than once in this repo.
CGGRAM_FAIL=""
for cmd in \
  '{ git add -A; git commit -m x; }' \
  'if true; then git add -A && git commit -m x; fi' \
  '! git commit -am x' \
  'for i in 1; do git commit -am x; done' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGGRAM_FAIL="$CGGRAM_FAIL
    $cmd"
done
if [[ -z "$CGGRAM_FAIL" ]]; then
  ok "commit corpus shell grammar: compound spellings are denied in the commit gate too"
else
  bad "commit corpus shell grammar: the same repair must land in both gates" \
      "these scanned a stale index unchecked:$CGGRAM_FAIL"
fi

# --- the commit gate's QUOTED-WORD axis (1.0.8, B3b and F5) -----------------
# Quoting the binary or the subcommand deleted the word this gate matches on, so
# the line stopped being a commit as far as Check 0 could see. An odd number of
# quote characters anywhere swallowed the real `git commit` with them.
CGQ_FAIL=""
for cmd in \
  '"git" commit -am x' \
  'git "commit" -am x' \
  "'git' 'commit' -am x" \
  'git add . && "git" commit -m x' \
  "echo 'don'\\''t' && git add . && git commit -m x" \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGQ_FAIL="$CGQ_FAIL
    $cmd"
done
if [[ -z "$CGQ_FAIL" ]]; then
  ok "commit corpus quoted word: quoting the binary or the subcommand does not hide the commit"
else
  bad "commit corpus quoted word: a quoted command word must still be the command word" \
      "these skipped Check 0 and all three scans:$CGQ_FAIL"
fi

CGQ_ALLOW_FAIL=""
for cmd in \
  'echo "git add ." && git commit -m x' \
  'git commit -m "add everything and commit"' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGQ_ALLOW_FAIL="$CGQ_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGQ_ALLOW_FAIL" ]]; then
  ok "commit corpus quoted word: a mention inside quotes is still not an operation"
else
  bad "commit corpus quoted word: keeping quoted words must not manufacture staging" \
      "these were denied:$CGQ_ALLOW_FAIL"
fi

# --- the commit gate's AMPERSAND-SEPARATOR axis (1.0.7) ---------------------
# Same character, same missing separator, other gate. Asserted here rather than
# inferred from the close-gate cases: the two hooks carry their own copy of the
# splitter line, and this suite has already watched a repair land in one and not
# the other.
CGAMP_N=0; CGAMP_FAIL=""
for cmd in \
  'git stash pop & git commit -m x' \
  'git add -A & git commit -m x' \
  'echo hi & git commit -am x' \
  'git commit -m x & git add -A' \
  ; do
  # The last one is the case that keeps the F1 position rule honest, and it
  # caught the first cut of that rule. `&&` guarantees the commit finished
  # before the add starts, so the add cannot make the index stale; `&` does
  # NOT, because it backgrounds the commit and the two race. A position check
  # that does not know the difference clears a real hole.
  CGAMP_N=$((CGAMP_N + 1))
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGAMP_FAIL="$CGAMP_FAIL
    $cmd"
done
if [[ -z "$CGAMP_FAIL" ]]; then
  ok "commit corpus ampersand separator: all $CGAMP_N backgrounded spellings are denied"
else
  bad "commit corpus ampersand separator: a staging verb after a single & must not escape the commit gate" \
      "these scanned a stale index unchecked:$CGAMP_FAIL"
fi

CGAMP_ALLOW_FAIL=""
for cmd in \
  'git status & git commit -m x' \
  'sleep 1 & git commit -m x' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGAMP_ALLOW_FAIL="$CGAMP_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGAMP_ALLOW_FAIL" ]]; then
  ok "commit corpus ampersand separator: a backgrounded read-only command still passes"
else
  bad "commit corpus ampersand separator: & must not turn read-only commands into denials" \
      "these were denied:$CGAMP_ALLOW_FAIL"
fi

# --- the commit gate's NEWLINE-SEPARATOR axis (1.0.7) -----------------------
# The same whitespace squeeze, the same collapse: a stage-and-commit split
# across two lines became one segment, so Check 0 saw only the first command and
# the three staged-content checks then read an index nobody had judged. Named by
# a finder in the scoped run alongside the close-gate half, which is what a
# shared normaliser defect looks like from two directions.
CG_NL_FAIL=""
CG_NL_N=0
for payload in "$(printf 'git add .\ngit commit -m x')" \
               "$(printf 'git status\ngit add -A\ngit commit -m x')" \
               "$(printf '# ready\ngit add -A && git commit -m x')"; do
  CG_NL_N=$((CG_NL_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_NL_FAIL="$CG_NL_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_NL_FAIL" ]]; then
  ok "commit corpus newline separator: all $CG_NL_N multi-line stage-and-commit spellings are denied"
else
  bad "commit corpus newline separator: a commit after a newline must not escape the gate ($CG_NL_N generated)" \
      "these escaped (~ marks the newline):$CG_NL_FAIL"
fi

# The inverse: a newline in a commit MESSAGE is ordinary, and must not start
# denying clean commits.
CG_NL_ALLOW_FAIL=""
for payload in "$(printf 'git commit -m "line one\nline two"')" \
               "$(printf 'echo building\ngit status')"; do
  [[ "$(cg_verdict "$payload")" == "allow" ]] || CG_NL_ALLOW_FAIL="$CG_NL_ALLOW_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_NL_ALLOW_FAIL" ]]; then
  ok "commit corpus newline separator: a newline inside a message does not deny a clean commit"
else
  bad "commit corpus newline separator: a newline inside a message must not deny a clean commit" \
      "these were denied (~ marks the newline):$CG_NL_ALLOW_FAIL"
fi

# --- the LINE-CONTINUATION axis (1.0.7, found by the adversarial review) -----------
# A backslash before a newline is a CONTINUATION, not a separator: the shell
# joins the lines into one command. The 1.0.7 newline fix converted every
# newline into a segment break, so `git commit \<newline> -am x` put -am in a
# different segment from the commit and the auto-staging check never saw it.
# v1.0.6 denied it. That is a regression introduced by a fix, which is this
# repo's most-repeated defect class, and it was caught by the leg rather than
# by the person who wrote it.
CG_CONT_FAIL=""
CG_CONT_N=0
for payload in "$(printf 'git commit \\\n  -am "x"')" \
               "$(printf 'git add -A \\\n  && git commit -m x')" \
               "$(printf 'git \\\n  commit \\\n  -am x')"; do
  CG_CONT_N=$((CG_CONT_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_CONT_FAIL="$CG_CONT_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_CONT_FAIL" ]]; then
  ok "commit corpus line continuation: all $CG_CONT_N continued spellings are denied"
else
  bad "commit corpus line continuation: a continued command is ONE command ($CG_CONT_N generated)" \
      "these escaped (~ marks the newline):$CG_CONT_FAIL"
fi

# And the close gate, same joint.
CORPUS_CONT_FAIL=""
for payload in "$(printf 'git merge --no-ff \\\n  spec/0001-thing')" \
               "$(printf 'git merge \\\n  --no-ff \\\n  spec/0001-thing')"; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || CORPUS_CONT_FAIL="$CORPUS_CONT_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CORPUS_CONT_FAIL" ]]; then
  ok "corpus line continuation: a continued merge is still one merge"
else
  bad "corpus line continuation: a continued merge must not escape the close gate" \
      "these escaped (~ marks the newline):$CORPUS_CONT_FAIL"
fi


# --- the QUOTE-PAIRING axis (1.0.7) -----------------------------------------
# The normaliser strips quoted spans so a message mentioning a staging verb
# cannot trip the gate. It did that with two independent sed passes, singles
# then doubles, which pairs quote characters ACROSS segments: an apostrophe in
# ordinary English in one segment pairs with an apostrophe in a later one and
# everything between them is deleted, including the governed token.
#
# Both spellings below must deny, and they are MIRRORS of each other. That is
# the whole point of asserting both: singles-first defeats the first, doubles-
# first defeats the second, and satisfying one by reordering the passes just
# moves the hole. Only a left-to-right scan that respects whichever quote opened
# first satisfies both at once.
CG_QUOTE_FAIL=""
CG_QUOTE_N=0
for payload in 'echo "here'"'"'s why" && git add . && echo "let'"'"'s go" && git commit -m "wip"' \
               'echo "it'"'"'s fine" && git add -A && git commit -m "don'"'"'t ship"' \
               "echo 'a\"b' && git add -A && git commit -m 'c\"d'" \
               "echo 'say \"go\"' && git add . && git commit -m 'ship \"it\"'"; do
  CG_QUOTE_N=$((CG_QUOTE_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_QUOTE_FAIL="$CG_QUOTE_FAIL
    $payload"
done
if [[ -z "$CG_QUOTE_FAIL" ]]; then
  ok "commit corpus quote pairing: all $CG_QUOTE_N prose-punctuation spellings are denied"
else
  bad "commit corpus quote pairing: punctuation in prose must not erase the commit ($CG_QUOTE_N generated)" \
      "these escaped:$CG_QUOTE_FAIL"
fi

# The inverse, and it is the reason the spans are stripped at all: a message
# that merely MENTIONS a staging verb is not a staging command, and an ordinary
# apostrophe must not start denying clean commits.
CG_QUOTE_ALLOW_FAIL=""
for payload in 'git commit -m "it'"'"'s fine"' \
               'git commit -m "we should git add . later"'; do
  [[ "$(cg_verdict "$payload")" == "allow" ]] || CG_QUOTE_ALLOW_FAIL="$CG_QUOTE_ALLOW_FAIL
    $payload"
done
if [[ -z "$CG_QUOTE_ALLOW_FAIL" ]]; then
  ok "commit corpus quote pairing: a clean commit whose message contains punctuation or a verb still passes"
else
  bad "commit corpus quote pairing: a clean commit must not be denied by its own message" \
      "these were denied:$CG_QUOTE_ALLOW_FAIL"
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

# --- THE INDEX THE SCANS READ: a documented hole (1.0.7) --------------------
# The commit gate scans the index of CLAUDE_PROJECT_DIR, which is not
# necessarily the index the commit will actually use: `git -C sub commit`
# commits a nested repository's index, and GIT_INDEX_FILE names a different one
# outright. Both were confirmed against the shipped tree.
#
# Documented rather than fixed, deliberately. Making the gate follow the index
# would mean re-deriving the target repository from the command line for every
# spelling, which is the parser-chasing this project has now been burned by
# twice; and a nested repository is a different project, whose own instance
# governs it if it has one. So the hole is named where users read and asserted
# here, which is the standing bargain for every deliberate gap.
CGIDX="$WORK/commit-index"
git_init "$CGIDX"; sdd_json "$CGIDX"
mkdir -p "$CGIDX/sub"
git_init "$CGIDX/sub"
printf 'a line with an %s in it\n' "$EMDASH" > "$CGIDX/sub/prose.md"
git -C "$CGIDX/sub" add -A
assert_true "commit index 0: the nested repo really has em-dash content staged" \
  "the fixture does not carry the content whose escape is being asserted, so the pass below would prove nothing" \
  test -n "$(git -C "$CGIDX/sub" diff --cached --name-only)"
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'git -C sub commit -m "add fixture"')"
expect_allow "commit index a: a nested repo's commit is not scanned (documented hole)"
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'GIT_INDEX_FILE=alt.index git commit -m x')"
expect_allow "commit index b: a commit against a named index file is not scanned (same hole)"
# The pairing that makes the hole survivable: the project's OWN index is still
# scanned, so the gap is about other repositories, not about this one.
printf 'a line with an %s in it\n' "$EMDASH" > "$CGIDX/prose.md"
git -C "$CGIDX" add -A
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'git commit -m "add fixture"')"
expect_deny "commit index c: this project's own staged content is still scanned" "em-dash"

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

# =============================================================================
# CHECK 4, THE GIT IDENTITY GATE (BL-007, plugin 1.1.0)
#
# One machine holding a work identity and a personal one is the ordinary case,
# and a commit under the wrong one is a compliance problem on a work repo. The
# gate catches it at COMMIT time, where the fix is `git config` plus an amend,
# rather than at push time, where it is a rebase.
#
# THE ABSENT-KEY CASE IS THE ONE THAT MATTERS MOST, because it is every instance
# that already exists: no `identity` key means no check and no output, and the
# gate must behave exactly as it did before this release.
# =============================================================================
CGID="$WORK/commit-identity"
git_init "$CGID"; sdd_json "$CGID"
mkdir -p "$CGID/specs"; printf 'x\n' > "$CGID/a.txt"
git -C "$CGID" add -A >/dev/null 2>&1

# No identity key: unchanged behaviour.
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity a: no identity key means no check (every pre-1.1.0 instance)"

# Configured and MATCHING: still allowed, and the gate is otherwise untouched.
CGID_EMAIL="$(git -C "$CGID" config user.email)"
jq --arg e "$CGID_EMAIL" '. + {identity:{user_email:$e}}' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity b: a matching identity is allowed"

# Configured and MISMATCHED: denied, naming both values and the remedy.
jq '.identity.user_email = "someone-else@example.invalid"' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity c: a mismatched identity is refused" "CM-IDENTITY"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity d: the denial names the EXPECTED identity" "someone-else@example.invalid"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity e: the denial names the ACTUAL identity" "$CGID_EMAIL"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity f: the denial names the remedy" "git config user.email"

# An identity key present but EMPTY is not a declaration, so it is not a check.
jq '.identity.user_email = ""' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity g: an empty declared identity is treated as absent, not as a mismatch"

# =============================================================================
# CHECK 3, THE SPEC-LIFECYCLE LOCKSTEP (D5, cut worklist 4.2)
#
# Until now the suite had NO case for CM-STATUS-MISSING at all, which is exactly
# how the gap was able to open: the edition gained BUILT and PARKED, check 3
# enumerates the vocabulary literally, and nothing anywhere compared the two. A
# staged `Status: BUILT` without specs/STATUS.md was allowed through by a check
# whose whole job is to catch that.
#
# Two mechanisms, because either alone is insufficient. The SET comparison
# catches a state added to the protocol and not to the gate. The BEHAVIOURAL
# cases catch a list that agrees with the edition and does not actually work,
# which is the failure a pure string comparison cannot see.
#
# The behavioural cases are parametrised over the canonical set rather than
# written out per state (redesign section 8, promoted to doctrine at addendum
# 6.4). A new state therefore arrives already covered in both directions, which
# is the point: the 2026-07-29 mutation run found two fixed defects each held
# closed by a SINGLE assertion, and that is what parametrising prevents.
# =============================================================================

CANON_STATES="$(bash "$SCRIPTS/part.sh" lifecycle-states "$ROOT/setlist.md" 2>/dev/null | sort | tr '\n' ' ')"
assert_true "lifecycle canon: the edition's SDD-LIFECYCLE-STATES block extracts non-empty" \
  "part.sh lifecycle-states returned nothing, so every comparison below would compare against an empty set and pass" \
  test -n "$(printf '%s' "$CANON_STATES" | tr -d '[:space:]')"

HOOK_STATES="$(grep -m1 -E "^CM_LIFECYCLE_STATES=" "$HOOKS/commit-gate.sh" \
  | sed -e "s/^CM_LIFECYCLE_STATES='//" -e "s/'.*$//" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [[ "$CANON_STATES" == "$HOOK_STATES" ]]; then
  ok "lifecycle lockstep: commit-gate.sh's enumeration equals the edition's canonical block"
else
  bad "lifecycle lockstep: commit-gate.sh's enumeration equals the edition's canonical block" \
      "edition has [$CANON_STATES] and the hook has [$HOOK_STATES]"
fi

# The STATUS template's legend is the third copy, and it is stamped into every
# instance, so a state missing there is a state operators never learn about.

# Every PROSE copy of the enumeration, not just the stamped legend. The
# spec-authoring skill carried "QUEUED, ACTIVE, REVISED, CLOSED, DRAFT" through
# the whole of the D5 work and nothing noticed, because the lockstep only
# covered the hook, the edition and the template. A list a human reads and
# copies into a spec is as much a copy as one a gate greps, and it drifts the
# same way; it was found by a manual sweep, which is exactly the thing that does
# not happen reliably.
for lc_file in "$ROOT/templates/specs/STATUS.md.tmpl" "$ROOT/skills/spec-authoring/SKILL.md"; do
  lc_name="$(basename "$lc_file")"
  for st in $CANON_STATES; do
    if grep -q "$st" "$lc_file"; then
      ok "lifecycle legend: $lc_name names the state $st"
    else
      bad "lifecycle legend: $lc_name names the state $st" "this copy of the enumeration omits it"
    fi
  done
done

# Both directions, per state, against the real hook.
for st in $CANON_STATES; do
  CGL="$WORK/cg-lifecycle"; rm -rf "$CGL"
  git_init "$CGL"; sdd_json "$CGL"
  mkdir -p "$CGL/specs"
  # The base carries NO Status line, so every state below is a genuine staged
  # addition. Seeding it with a real state made the QUEUED case a no-op diff:
  # the assertion failed for a fixture reason and said nothing about the gate,
  # which is the shape of evidence scoped to the wrong thing.
  printf '# Spec 0001\n\nBody text.\n' > "$CGL/specs/0001-thing.md"
  printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | (none) |\n' > "$CGL/specs/STATUS.md"
  git -C "$CGL" add -A >/dev/null 2>&1; git -C "$CGL" commit -qm "base" >/dev/null 2>&1

  # DENY: the transition is staged, STATUS.md is not.
  printf '# Spec 0001\n\nStatus: %s\n\nBody text.\n' "$st" > "$CGL/specs/0001-thing.md"
  git -C "$CGL" add specs/0001-thing.md >/dev/null 2>&1
  run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "move the spec"')"
  expect_deny "lifecycle check 3: a staged transition to $st without specs/STATUS.md is refused" "CM-STATUS-MISSING"

  # ALLOW: the same transition WITH STATUS.md staged. Without this direction the
  # case above is satisfied by a gate that denies everything.
  printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | %s |\n' "$st" > "$CGL/specs/STATUS.md"
  git -C "$CGL" add -A >/dev/null 2>&1
  run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "move the spec"')"
  expect_allow "lifecycle check 3: a staged transition to $st WITH specs/STATUS.md is allowed"
done

# The non-regression: an ordinary mid-build spec edit that moves no state must
# not demand STATUS.md. This is the false-denial direction, and it is the one
# that would make the gate unusable rather than merely leaky.
CGL="$WORK/cg-lifecycle-noop"; rm -rf "$CGL"
git_init "$CGL"; sdd_json "$CGL"
mkdir -p "$CGL/specs"
printf '# Spec 0001\n\nStatus: ACTIVE\n\nSome body text.\n' > "$CGL/specs/0001-thing.md"
printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | ACTIVE |\n' > "$CGL/specs/STATUS.md"
git -C "$CGL" add -A >/dev/null 2>&1; git -C "$CGL" commit -qm "base" >/dev/null 2>&1
printf '# Spec 0001\n\nStatus: ACTIVE\n\nSome body text.\nAnd another paragraph.\n' > "$CGL/specs/0001-thing.md"
git -C "$CGL" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "mid-build edit"')"
expect_allow "lifecycle check 3: an ordinary spec edit that moves no state does not demand STATUS.md"

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
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    # THE DIAGRAM FIELD, which this fixture omitted. It was "compliant" only
    # against the audit's OLD close-condition subset; the merge hook has always
    # required this line, so a spec without it would be refused at merge time.
    # Round 6 gave the audit the same check, and that is what exposed the gap.
    printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
  } > "$d/specs/0005b-thing.md"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0005b"
  if [[ "$mode" == "unclosed" ]]; then
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | ACTIVE |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "not closed after all"
  fi
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge spec 0005b" spec/0005b-thing
  # A chore merge carrying role-path changes and no spec. It RECORDS ITS
  # COMPLETION, which is what makes it legitimate rather than merely
  # unfalsifiable.
  #
  # This fixture used to omit the archive line and the comment here called it
  # "legitimate, and indistinguishable from an unspecced feature in history".
  # The second half was true and is exactly the finding: F2/F7 of the 2026-08-05
  # leg showed that the audit excused every such merge as "unverifiable" at exit
  # 0, so any route reaching the trunk without firing pre-merge-commit was waved
  # through by the backstop. Part 5b's rule is that a chore records an archive
  # line; a chore merge without one, made after the instance adopted the rules,
  # is a violation now. So the compliant fixture is compliant.
  git -C "$d" checkout -q -b chore/tidy
  printf 'tidy\n' >> "$d/src/f.js"
  printf -- '- CHORE-007: DONE 2026-08-05. tidy the source tree\n' >> "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "chore work"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge chore: tidy" chore/tidy
  if [[ "$mode" == "direct" ]]; then
    printf 'snuck in\n' >> "$d/src/f.js"
    git -C "$d" add -A && git -C "$d" commit -qm "hotfix straight onto the trunk"
  fi
  # F1 of the 2.2.0 leg: the same direct-commit violation as "direct" above,
  # differing ONLY in the filename. Each of these four names is emitted QUOTED by
  # git's --name-only, which is what made the role test blind to it. The ASCII
  # sibling is `plainrole` and runs first as the control, so a green row here is
  # evidence about the NAME and not about the fixture builder.
  case "$mode" in
    plainrole)  TA_NAME='plain.js' ;;
    utf8role)   TA_NAME="$(printf 'caf\303\251.js')" ;;
    bslashrole) TA_NAME='ba\ck.js' ;;
    quoterole)  TA_NAME='qu"ote.js' ;;
    tabrole)    TA_NAME="$(printf 'ta\tb.js')" ;;
    *)          TA_NAME='' ;;
  esac
  if [[ -n "$TA_NAME" ]]; then
    printf 'const b=2\n' > "$d/src/$TA_NAME"
    git -C "$d" add -A && git -C "$d" commit -qm "direct role-path commit"
    # The fixture ASSERTS ITS OWN SHAPE before the audit reads it. A path git
    # refused to stage would leave a commit that touches nothing, and every case
    # below would then pass by testing an empty diff, which is the vacuous
    # comparison this suite exists to refuse.
    if [[ -z "$(git -C "$d" diff --name-only HEAD~1 HEAD 2>/dev/null)" ]]; then
      printf 'FIXTURE BROKEN: audit_fixture %s staged no path\n' "$mode" >&2
    fi
  fi
  # B6, all three shapes. Each rides on the fixture above, which has left spec
  # 0005b CLOSED on the trunk: that already-closed spec is the laundering
  # vehicle in two of the three.
  if [[ "$mode" == "prose" ]]; then
    # A Closing report whose QA block carries NO pasted verdict, only prose
    # that happens to contain the word PASS. The close gate rejects this; its
    # backstop accepted it, which is the half of B6 that makes an audit worse
    # than useless: it reports clean on the exact text the gate refuses.
    git -C "$d" checkout -q -b spec/0006-prose
    printf 'more\n' >> "$d/src/f.js"
    {
      printf '# Spec 0006\n\nStatus: CLOSED\n\n## Closing report\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      printf 'the browser tests PASS on my machine but mobile was never run\n\n'
      printf -- '- QA Pass 2 (human): done\n'
    } > "$d/specs/0006-prose.md"
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0006 | Prose | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0006"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0006" spec/0006-prose
  fi
  if [[ "$mode" == "fencedclose" ]]; then
    # The audit's half of adversarial review F9. close-gate.sh strips fenced spans
    # before its close checks; this script never did, so a spec whose entire
    # Closing report is a quoted example was reported clean by the backstop that
    # README:176 sells as reading "what ended up in your history".
    git -C "$d" checkout -q -b spec/0008-fenced
    printf 'fenced\n' >> "$d/src/f.js"
    cat > "$d/specs/0008-fenced.md" <<'AUDITFENCED'
# Spec 0008

Status: CLOSED

I will fill this in later; here is the shape:

```markdown
## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
```
AUDITFENCED
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0008 | Fenced | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0008"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0008" spec/0008-fenced
  fi
  if [[ "$mode" == "secondspec" ]]; then
    # A branch touching TWO spec files: the already-CLOSED 0005b (which sorts
    # first, so `head -n1` picked it) and a genuinely non-compliant 0007. The
    # audit validated the compliant one and never looked at the other.
    git -C "$d" checkout -q -b spec/0007-second
    printf 'second\n' >> "$d/src/f.js"
    printf '\nA one-line amendment.\n' >> "$d/specs/0005b-thing.md"
    printf '# Spec 0007\n\nStatus: ACTIVE\n\nNo closing report at all.\n' > "$d/specs/0007-second.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0007 plus an edit to 0005b"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0007" spec/0007-second
  fi
  if [[ "$mode" == "tablecell" ]]; then
    # Item 35's positive direction on the BACKSTOP side. A compliant close whose
    # QA verdicts are table cells, which is the commonest real shape and which
    # the pre-widening rule refused. If the gate widens and the audit does not,
    # the audit starts reporting violations against merges the gate permits,
    # which is F8's disagreement running the other way.
    git -C "$d" checkout -q -b spec/0008-table
    printf 'table\n' >> "$d/src/f.js"
    {
      printf '# Spec 0008\n\nStatus: CLOSED\n\n## Closing report\n\n'
      printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n2: PARTIAL\n```\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      printf '| # | Criterion | Verdict | Evidence |\n'
      printf '|---|-----------|---------|----------|\n'
      printf '| 1 | the thing works | PASS | bats 76-80 ok |\n'
      printf '| 2 | the other thing | PARTIAL | no hardware here |\n\n'
      printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
    } > "$d/specs/0008-table.md"
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0008 | Table | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0008"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0008" spec/0008-table
  fi
  if [[ "$mode" == "launder" ]]; then
    # Role-path code merged under a spec that was ALREADY CLOSED on the trunk
    # before this merge. Every spec the branch touches is compliant, so
    # dispositioning all of them is not enough on its own: the question is
    # whether this merge CLOSED anything, and it did not.
    git -C "$d" checkout -q -b spec/0005b-again
    printf 'laundered\n' >> "$d/src/f.js"
    printf '\nA one-line amendment.\n' >> "$d/specs/0005b-thing.md"
    git -C "$d" add -A && git -C "$d" commit -qm "amend 0005b and slip code in"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0005b again" spec/0005b-again
  fi
}

# A PARENTLESS commit offered as the new trunk (F2 of the 2026-08-11 leg).
#
# The attack is `git checkout --orphan`, commit role-path code, then
# `git push --force <orphan>:refs/heads/main`. pre-push audits the oid that
# WOULD become the remote trunk with --until, which is why this fixture leaves
# the real trunk alone and returns the orphan's name: that is the shape the
# hook actually evaluates.
#
# The old walk asked `[[ -n "$P1" ]] && touches_role "$P1" "$C"`, so a commit
# with no first parent failed the guard and fell to the CLEAN arm having had
# its content read by nothing, and the whole trunk could be replaced at
# "0 violations", exit 0.
audit_orphan_fixture() { # audit_orphan_fixture <dir> <mode: code|docs>
  local d="$1" mode="$2"
  audit_fixture "$d" clean
  git -C "$d" checkout -q --orphan wholesale
  git -C "$d" rm -rq --cached . >/dev/null 2>&1
  ( cd "$d" && rm -rf src specs .claude seed.txt )
  if [[ "$mode" == "code" ]]; then
    mkdir -p "$d/src"
    printf 'unreviewed feature\n' > "$d/src/evil.js"
  else
    mkdir -p "$d/docs"
    printf 'just docs\n' > "$d/docs/notes.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "wholesale replacement" >/dev/null 2>&1
  git -C "$d" checkout -q -f main >/dev/null 2>&1
}

# THE OTHER DIRECTION, and the one a careless fix breaks: every repository's
# ROOT commit is parentless and entirely legitimate. Here the root carries
# feature code AND the stamp, so it is both parentless and role-touching, which
# is exactly the shape the orphan attack has. What separates them is identity,
# not shape: the root is an ancestor of the rule baseline and the injected
# orphan shares no history with it at all.
audit_rootcode_fixture() { # audit_rootcode_fixture <dir>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email "tests@example.invalid"
  git -C "$d" config user.name "Setlist Tests"
  git -C "$d" config commit.gpgsign false
  sdd_json "$d"
  printf 'feature\n' > "$d/src/f.js"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A
  git -C "$d" commit -qm "root commit: feature code and the stamp together"
  git -C "$d" checkout -q -b spec/0005b-thing
  printf 'more\n' >> "$d/src/f.js"
  {
    printf '# Spec 0005b\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
  } > "$d/specs/0005b-thing.md"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0005b"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge spec 0005b" spec/0005b-thing
}

AUD="$WORK/audit-clean"; audit_fixture "$AUD" clean
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit a: a compliant trunk reports zero violations" 0 "0 violations"
expect_script "trunk audit b: a suffixed spec number (0005b) is recognised, not flagged" 0 "0 violations"
# A RECORDED chore merge is CLEAN, not merely unverifiable. The old expectation
# here was that it landed in the "unverifiable" bucket, which is the bucket F2/F7
# showed was excusing hook-skipping merges at exit 0. A chore that records its
# completion is distinguishable from an unspecced feature, which is the whole
# point of the archive line; the unrecorded case is asserted as a VIOLATION by
# "audit age a" further down, and the pre-adoption exemption by "audit age b".
expect_script "trunk audit c: a chore merge that records its completion is clean, not a violation" 0 "0 violations"

AUD="$WORK/audit-direct"; audit_fixture "$AUD" direct
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit d: feature code committed straight to the trunk is a violation" 1 \
  "feature code committed directly" "1 violations"

AUD="$WORK/audit-unclosed"; audit_fixture "$AUD" unclosed
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit e: a merge whose spec has no CLOSED row is a violation" 1 "no-CLOSED-row"

# F2, 2026-08-11 leg. Both directions, and the second one is the trap: the fix
# must separate an INJECTED parentless commit from a repository's own ROOT
# commit, which is parentless too and completely ordinary.
AUD="$WORK/audit-orphan-code"; audit_orphan_fixture "$AUD" code
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --until wholesale
expect_script "audit orphan a: a parentless commit carrying role code is a violation, not clean" 1 \
  "parentless" "1 violations"

# The false-positive direction of the same fix: it must judge the CONTENT of a
# parentless commit, not refuse the shape outright.
AUD="$WORK/audit-orphan-docs"; audit_orphan_fixture "$AUD" docs
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --until wholesale
expect_script "audit orphan b: a parentless commit touching no role path is not flagged" 0 "0 violations"

# THE ROOT-COMMIT CONTROL. Parentless and role-touching, exactly like the
# attack, and it must still audit clean.
AUD="$WORK/audit-rootcode"; audit_rootcode_fixture "$AUD"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "audit root a: a repository whose ROOT commit carries feature code still audits clean" 0 \
  "0 violations"

# THE TRUNK SPELLING, in the BACKSTOP. The v1.7 gate found the same root cause
# here as in slh_trunk, in a different file, so fixing the library does not touch
# this: trunk-audit.sh audited whatever ref .trunk NAMED, and a remote-tracking
# spelling made it walk the REMOTE's history instead of the local trunk being
# pushed. `rev-parse --verify` does not catch it, because a remote-tracking ref
# resolves perfectly well. The violating merge simply was not in the audited
# range, so the audit reported "1 clean, 0 violations", exit 0, and pre-push
# allowed the push. README:176 sells this script as the layer that "reads what
# ended up in your history and does not care how the command was spelled".
#
# Same bytes, same history, only the SPELLING of the trunk differs from case e.
for ta_tv in refs/remotes/origin/main origin/main refs/heads/main heads/main; do
  AUD="$WORK/audit-spell"; audit_fixture "$AUD" unclosed
  # origin/main deliberately sits BEHIND local main, at the stamp commit, which
  # is the ordinary state of a repo with unpushed work and the state in which the
  # defect reports a clean sheet rather than "nothing was audited".
  git -C "$AUD" update-ref refs/remotes/origin/main \
    "$(git -C "$AUD" log --format=%H --diff-filter=A -- .claude/sdd.json | tail -n1)" 2>/dev/null || true
  ta_tmp="$(jq --arg t "$ta_tv" '.trunk = $t' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit f: trunk spelled [$ta_tv] still audits the LOCAL trunk" 1 "no-CLOSED-row"
done

# And the refusal direction, in the two shapes it actually comes in. They take
# DIFFERENT paths through the script and the first draft of this block tested the
# wrong one twice: a value that does not resolve at all is caught by the older
# rev-parse check and never reaches the reduction, so asserting it proves nothing
# about the reduction.
#
# g1: resolves, but names no local branch and tracks none. A TAG is the honest
# case here, and it is the only one that reaches the new show-ref refusal.
AUD="$WORK/audit-tagtrunk"; audit_fixture "$AUD" unclosed
git -C "$AUD" tag audit-tag-trunk main 2>/dev/null || true
ta_tmp="$(jq '.trunk = "audit-tag-trunk"' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit g1: a trunk that RESOLVES but is not a local branch is refused" 2 "not a local branch"

# g2: does not resolve at all. Older path, asserted so it stays refused.
AUD="$WORK/audit-nobranch"; audit_fixture "$AUD" unclosed
ta_tmp="$(jq '.trunk = "no-such-branch"' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit g2: a trunk that does not resolve at all is refused" 2 "does not resolve"

# B6 (leg 5, F15/F29). The backstop was satisfied by ordinary prose and read
# only the FIRST spec file a branch touched. Both halves are fixed here, ahead
# of item 28 Stage B promoting this script to Part 6 enforcement: promoting a
# backstop that prose satisfies converts an honest "opt-in" into a false
# "enforced", which is worse than the opt-in it replaces.
AUD="$WORK/audit-prose"; audit_fixture "$AUD" prose
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6a: a QA block of prose containing the word PASS is not a verdict" 1 "no-qa-verdict"

# A FRESHLY STAMPED INSTANCE MUST BE PUSHABLE (v1.7 gate session 4, leg F2).
#
# It was not. The audit exits 2 on "nothing was audited", which pre-push correctly
# reports as a refusal, so the stamp handed the user a repository configured to
# reject every push before they had written anything. "Nothing to audit" is not an
# error when the baseline IS the trunk tip: it is a clean trunk with no work on it
# yet. It stays an error when the range is malformed, because an audit that walks
# the wrong range and reports clean is the fail-open this script exists to avoid.
AUD="$WORK/audit-fresh"; rm -rf "$AUD"; mkdir -p "$AUD"; git_init "$AUD"; sdd_json "$AUD"
git -C "$AUD" add .claude/sdd.json >/dev/null 2>&1
git -C "$AUD" commit -qm "stamp" >/dev/null 2>&1
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit h1: a freshly stamped instance with no work yet is CLEAN" 0 "audited 0"

# The other direction, so h1 cannot be satisfied by simply making the script
# permissive. Once "nothing to audit" becomes a clean answer, an UNRESOLVABLE
# baseline must not quietly borrow it: that would turn a typo into a clean sheet,
# which is the exact fail-open this script exists to avoid. The first draft of
# this case used an orphan commit as --since, which does NOT produce an empty
# range (it lists the whole trunk), so it tested nothing about the empty path.
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --since no-such-baseline-ref
expect_script "trunk audit h2: an UNRESOLVABLE --since is an error, not a clean sheet" 2 "does not resolve"

AUD="$WORK/audit-fenced"; audit_fixture "$AUD" fencedclose
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit F9: a Closing report that exists only inside a fence is a violation" 1 "spec 0008"

AUD="$WORK/audit-secondspec"; audit_fixture "$AUD" secondspec
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6b: EVERY spec a branch touches is dispositioned, not just the first" 1 "spec 0007"

# Item 35 on the backstop: a table-cell verdict is a verdict here too. Paired
# with B6a above, which keeps prose refused, these two are the lockstep's two
# directions expressed against the audit rather than against the gate.
AUD="$WORK/audit-tablecell"; audit_fixture "$AUD" tablecell
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit item 35: a table-cell QA verdict is accepted, not reported as no-qa-verdict" 0 "0 violations"

# --- F1 of the 2.2.0 leg: git QUOTES paths, and the role test read the quotes ---
#
# THE BLOCKER. `git diff --name-only` and `git ls-tree --name-only` emit a path
# containing a non-ASCII byte, a double quote, a backslash or a control
# character as a QUOTED C string: "src/caf\303\251.js", quotes and octal escapes
# included. touches_role fed that 15-byte string to touches_role_file, whose
# `case "$f" in "$r"/*)` cannot match `src/`, so the file was invisible to the
# role test and unreviewed feature code landed on the trunk at exit 0 with the
# push allowed. The trunk audit IS the guarantee, so this sat above MAJOR.
#
# WHY -z AND NOT core.quotePath=false. Measured before the fix was written:
# flipping core.quotePath restores the NON-ASCII case only. A double quote, a
# backslash and a control character are quoted UNCONDITIONALLY at any setting.
# `-z` emits paths NUL-delimited and unquoted, which is the only spelling that
# covers all four classes, so every case below is run with quotePath BOTH ways
# and must give the same answer.
#
# The ASCII control runs FIRST in each pair. Four cases that all expect "1
# violations" prove nothing if the fixture builder silently produced no commit.
for TA_QP in true false; do
  AUD="$WORK/audit-qp-ascii-$TA_QP"; audit_fixture "$AUD" plainrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 control [quotePath=$TA_QP]: an ASCII role path committed direct to the trunk IS a violation" 1 "1 violations"

  AUD="$WORK/audit-qp-utf8-$TA_QP"; audit_fixture "$AUD" utf8role
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a NON-ASCII role path is seen by the role test" 1 "1 violations"

  AUD="$WORK/audit-qp-bslash-$TA_QP"; audit_fixture "$AUD" bslashrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a BACKSLASH role path is seen (quoted at any setting)" 1 "1 violations"

  AUD="$WORK/audit-qp-quote-$TA_QP"; audit_fixture "$AUD" quoterole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a DOUBLE-QUOTE role path is seen (quoted at any setting)" 1 "1 violations"

  AUD="$WORK/audit-qp-tab-$TA_QP"; audit_fixture "$AUD" tabrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a TAB role path is seen (quoted at any setting)" 1 "1 violations"
done

AUD="$WORK/audit-launder"; audit_fixture "$AUD" launder
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6c: code merged under an already-CLOSED spec closes nothing and is a violation" 1 "closes-no-spec"

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

# THE REF-NAMESPACE ANCHOR (2.4.0 leg F2): a ref the instance does not govern,
# whose name merely CONTAINS /spec/, must not hijack the classification of an
# ordinary feature merge. Both leg spellings: a remote NAMED spec, and a
# nesting namespace in front of spec/.
git -C "$FOR1" branch -f feature/iso main
git -C "$FOR1" update-ref refs/remotes/spec/main feature/iso
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/iso')"
expect_allow "foreign b2 (2.4.0 leg F2): a remote NAMED spec does not turn a feature merge into an unclosed close"
git -C "$FOR1" update-ref -d refs/remotes/spec/main
git -C "$FOR1" branch -f archive/spec/0099-old feature/iso
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/iso')"
expect_allow "foreign b3 (2.4.0 leg F2): a nesting namespace in front of spec/ is not the governed namespace"
git -C "$FOR1" branch -D archive/spec/0099-old >/dev/null 2>&1
# The direction that must NOT loosen, the remote-tracking copy of a GOVERNED
# spec branch staying governed, is already pinned by the ref-identity corpus
# below (remote-tracking spellings deny), which the 2.4.0 leg re-verified live.

# THE IDENTITY-BY-COMMIT BOUNDARY (2.4.0 leg F9, documented): an alias is
# governed only while a spec or chore ref still points at that exact commit.
# Both spellings pinned as the documented Known-limitations bullet says, so
# the delisting cannot silently return. The guarantee layers refuse these
# merges (leg-verified by execution); what these pins record is the session
# gate's classification boundary, on fresh copies so FOR1 stays untouched.
FOR3="$WORK/foreign-alias-adv"
rm -rf "$FOR3"; cp -R "$FOR1" "$FOR3"
git -C "$FOR3" branch -f tmp/alias spec/0001-thing
git -C "$FOR3" checkout -q spec/0001-thing 2>/dev/null
printf 'more\n' >> "$FOR3/src/app.js" 2>/dev/null || printf 'more\n' > "$FOR3/src/later.txt"
git -C "$FOR3" add -A >/dev/null 2>&1
git -C "$FOR3" -c core.hooksPath=/dev/null commit -qm "branch advances past the alias" >/dev/null 2>&1
git -C "$FOR3" checkout -q main 2>/dev/null
run_hook "$HOOKS/close-gate.sh" "$FOR3" "$(bash_payload 'git merge --no-ff tmp/alias')"
expect_allow "alias a (2.4.0 leg F9, documented boundary): an alias the spec branch advanced past classifies as an ungoverned sync at the session layer"
FOR4="$WORK/foreign-alias-del"
rm -rf "$FOR4"; cp -R "$FOR1" "$FOR4"
git -C "$FOR4" branch -f tmp/alias spec/0001-thing
git -C "$FOR4" branch -D spec/0001-thing >/dev/null 2>&1
run_hook "$HOOKS/close-gate.sh" "$FOR4" "$(bash_payload 'git merge --no-ff tmp/alias')"
expect_allow "alias b (2.4.0 leg F9, documented boundary): an alias that outlives the deleted spec branch classifies as an ungoverned sync at the session layer"

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
done < <(grep -hoE 'expect_deny "[^"]*" "[^"]*"' "$ROOT/test/run-tests.sh" 2>/dev/null \
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
SUITE_SELF_REL="$(grep -n 'test/run-tests\.sh' "$ROOT/test/run-tests.sh" 2>/dev/null \
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

# =============================================================================
# THE STAMPED GIT HOOKS (item 28 Stage B, cut worklist 4.2)
#
# pre-commit and pre-merge-commit, driven through REAL git operations rather
# than by invoking the scripts. Invoking a hook directly proves the script; only
# running `git merge` proves that git calls it, on this path, with these
# settings. The 1.0.8 macOS fail-open is the standing argument for the
# distinction: everything passed except the thing nobody ran.
#
# The firing table these cases encode was MEASURED, not read (2026-08-01):
# pre-commit fires for an ordinary commit and for the commit completing a squash
# or a stalled merge; pre-merge-commit fires only for a true merge commit; a
# fast-forward merge fires neither, which is why the stamp sets merge.ff=false.
# =============================================================================

gh_fixture() { # gh_fixture <dir> <closed: yes|no> [trunk-spelling]
  # The third argument defaults to "main" so every existing case is unchanged.
  # It exists because EVERY fixture in this suite wrote "main" and nothing else,
  # which is precisely why the v1.7 gate's BLOCKER survived 573 green assertions:
  # the trunk-SPELLING dimension was never varied against the git-hook layer, only
  # against close-gate.sh (the block at "trunk spelling" further up this file).
  local d="$1" closed="$2" trunkval="${3:-main}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$trunkval" > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'work\n' > "$d/src/FEATURE.txt"
  if [[ "$closed" == "fenced" ]]; then
    # A FENCED EXAMPLE IS NOT A CLOSING REPORT. close-gate.sh learned this as
    # leg 5's F7 and strips fenced spans once before all four checks; the git
    # hooks and the trunk audit never got the same treatment, so a spec whose
    # entire Closing report is a quoted ```markdown example really merged
    # (v1.7 gate, adversarial review F9). This is ordinary authoring rather than an
    # attack: the template ships fenced in setlist.md and the spec-authoring
    # skill tells authors to copy it.
    # A HEREDOC, not printf. The first draft used one printf per line and three
    # of them began with "- ", which bash's printf parses as OPTIONS and drops:
    # the fixture wrote a spec containing the fence and the heading and NOTHING
    # ELSE, the hook refused it for having no QA verdict, and the assertion went
    # green while testing nothing at all. That is the exact defect class this
    # block exists to catch, committed by the test for the defect.
    cat > "$d/specs/0001-thing.md" <<'FENCEDSPEC'
# Spec 0001

Status: CLOSED

Here is the template I am going to fill in later:

```markdown
## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
```
FENCEDSPEC
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  elif [[ "$closed" == "yes" ]]; then
    printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-thing.md"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  else
    printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
    # The inventory row rides the same commit as the Status line. That is the
    # protocol, and it is also what makes this fixture BUILDABLE: the first
    # draft omitted it, pre-commit correctly refused the branch's only commit,
    # and every refusal case below then "passed" against a branch with no work
    # on it at all. The two allow-direction cases are what exposed that, which
    # is the whole reason a gate's positive direction is not optional.
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "work" >/dev/null 2>&1
  git -C "$d" checkout -q main
  # A remote-tracking ref, so the remote spellings under test RESOLVE rather than
  # failing for the uninteresting reason that nothing of that name exists. Every
  # ordinary clone has one; the upgrade skill's own trunk detection command,
  # `git symbolic-ref refs/remotes/origin/HEAD`, is what puts a ref PATH into
  # sdd.json in the first place.
  git -C "$d" update-ref refs/remotes/origin/main "$(git -C "$d" rev-parse main)" 2>/dev/null || true
  # The stamp, both halves, applied AFTER the fixture's own history exists so
  # the hooks judge the merge under test rather than the scaffolding.
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" config merge.ff false
  # CONTROL: the branch must actually carry work to merge. Without this, a
  # fixture that failed to build reports every refusal case as a pass.
  git -C "$d" cat-file -e "spec/0001-thing:src/FEATURE.txt" 2>/dev/null \
    || bad "git hooks fixture: spec/0001-thing carries the work under test" \
           "the fixture built no work commit, so every refusal case below would pass while testing nothing"
}

gh_landed() { git -C "$1" cat-file -e main:src/FEATURE.txt 2>/dev/null; }

# ===========================================================================
# THE AUDIT'S EXCUSE IS ABOUT AGE, SO IT ASKS ABOUT AGE (F2/F7, 2026-08-05).
#
# A chore-shaped merge with no recorded completion was reported "unverifiable"
# and tallied as a CHORE, leaving VIOLATIONS at 0 and the exit code at 0, which
# is the only thing pre-push reads. Any route that reaches the trunk without
# firing pre-merge-commit landed there: detached HEAD, --no-verify,
# core.hooksPath=/dev/null, and by commit shape the forge merge button. README
# names those routes and claims the audit catches every one.
#
# The block justified itself by ANTIQUITY and decided by SHAPE, and a merge made
# today that skipped the hook has the same shape as one made before the rule
# existed. It now asks when the instance adopted the rules and exempts only what
# is genuinely older. Both directions, because an exemption that never applies
# is as wrong as one that always does.
ta_flow() { # ta_flow <dir> -- an instance whose trunk carries a hook-skipping merge
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "stamp" >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'unspecced\n' > "$d/src/unspecced.js"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "unspecced" >/dev/null 2>&1
  git -C "$d" checkout -q --detach main
  git -C "$d" merge --no-verify --no-ff -m dm spec/0001-thing >/dev/null 2>&1
  git -C "$d" branch -f main HEAD; git -C "$d" checkout -q main
}
TAF="$WORK/ta-bypass"; ta_flow "$TAF"
if bash "$ROOT/scripts/trunk-audit.sh" "$TAF" >"$WORK/ta.out" 2>&1; then
  bad "audit age a: a hook-skipping merge made AFTER adoption is a violation, not an excuse" \
      "the audit exited 0, so pre-push allows it and the README's claim that the audit catches these routes is false"
else ok "audit age a: a hook-skipping merge made AFTER adoption is a violation, not an excuse"; fi

# THE RESTRAINT, still intact. A backstop that cries wolf about history it was
# never able to govern gets switched off, and then it guards nothing.
TAO="$WORK/ta-old"; rm -rf "$TAO"; mkdir -p "$TAO/src" "$TAO/specs" "$TAO/.claude"
git_init "$TAO"
printf 'x\n' > "$TAO/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$TAO/specs/STATUS.md"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm "before the framework" >/dev/null 2>&1
TAO_ROOT="$(git -C "$TAO" rev-parse HEAD)"
git -C "$TAO" checkout -q -b legacy; printf 'legacy\n' > "$TAO/src/legacy.js"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm legacy >/dev/null 2>&1
git -C "$TAO" checkout -q main
git -C "$TAO" merge -q --no-verify --no-ff -m "old merge" legacy >/dev/null 2>&1
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAO/.claude/sdd.json"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm "stamp: adopt the rules" >/dev/null 2>&1
if bash "$ROOT/scripts/trunk-audit.sh" "$TAO" --since "$TAO_ROOT" >"$WORK/tao.out" 2>&1; then
  ok "audit age b: a chore merge that genuinely predates adoption keeps its exemption"
else
  bad "audit age b: a chore merge that genuinely predates adoption keeps its exemption" \
      "the audit condemned pre-rule history, which is the crying-wolf direction the exemption exists to prevent"
fi

# THE ARITY ARM IS GONE (B2 restatement, 2026-08-13), and these two cases are
# the proof it demanded. The audit used to condemn any merge with more than two
# parents outright, on the reasoning "an octopus merge is not pre-rule history",
# which infers AGE from SHAPE: the parent count is a spelling, and the question
# that decides the exemption is WHEN, answered by ancestry for every arity at
# once. Case c pins that nothing was relaxed: a post-adoption octopus is still
# condemned, by post_baseline rather than by counting parents. Case d pins the
# restatement itself: pre-adoption history keeps its exemption regardless of
# arity, because the restraint doctrine has no arity clause. Case d was watched
# RED against the pre-restatement audit (it condemned this exact fixture with
# "in a merge justified by another parent") before the change landed.
TAC="$WORK/ta-octo-post"; rm -rf "$TAC"; mkdir -p "$TAC/src" "$TAC/specs" "$TAC/.claude"
git_init "$TAC"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAC/.claude/sdd.json"
printf 'x\n' > "$TAC/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$TAC/specs/STATUS.md"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm stamp >/dev/null 2>&1
TAC_BASE="$(git -C "$TAC" rev-parse HEAD)"
git -C "$TAC" checkout -q -b spec/0001-first "$TAC_BASE"
printf 'export const legit = 1\n' > "$TAC/src/legit.js"
{ printf '# 0001 First\n\n## Closing report\n\nDone.\n\n```qa-pass-1\nc1: PASS\n```\n\n- Architecture diagram: no impact\n'; } > "$TAC/specs/0001-first.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$TAC/specs/STATUS.md"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm "close 0001" >/dev/null 2>&1
git -C "$TAC" checkout -q -b sneaky "$TAC_BASE"
printf 'export const evil = 1\n' > "$TAC/src/evil.js"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm "sneaky code" >/dev/null 2>&1
git -C "$TAC" checkout -q main
git -C "$TAC" merge -q --no-ff --no-verify -m "close 0001 and pull sneaky" spec/0001-first sneaky >/dev/null 2>&1
if [ "$(git -C "$TAC" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" != "4" ]; then
  bad "audit age c: a POST-adoption octopus with an unjustified parent is still a violation" \
      "fixture error: the octopus folded instead of producing a 3-parent commit, so nothing below tests the arity-free path"
elif bash "$ROOT/scripts/trunk-audit.sh" "$TAC" >"$WORK/tac.out" 2>&1; then
  bad "audit age c: a POST-adoption octopus with an unjustified parent is still a violation" \
      "removing the arity arm RELAXED the audit: the sneaky parent passed, so ancestry is not carrying what shape used to"
else
  ok "audit age c: a POST-adoption octopus with an unjustified parent is still a violation"
fi

TAD="$WORK/ta-octo-pre"; rm -rf "$TAD"; mkdir -p "$TAD/src" "$TAD/specs"
git_init "$TAD"
printf 'x\n' > "$TAD/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$TAD/specs/STATUS.md"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "pre-framework root" >/dev/null 2>&1
TAD_ROOT="$(git -C "$TAD" rev-parse HEAD)"
git -C "$TAD" checkout -q -b oldb1 "$TAD_ROOT"; printf 'a\n' > "$TAD/src/a.js"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "old b1" >/dev/null 2>&1
git -C "$TAD" checkout -q -b oldb2 "$TAD_ROOT"; printf 'b\n' > "$TAD/src/b.js"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "old b2" >/dev/null 2>&1
git -C "$TAD" checkout -q main
git -C "$TAD" merge -q --no-ff --no-verify -m "old octopus" oldb1 oldb2 >/dev/null 2>&1
mkdir -p "$TAD/.claude"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAD/.claude/sdd.json"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "stamp: adopt the rules" >/dev/null 2>&1
if [ "$(git -C "$TAD" rev-list --parents -n1 'HEAD^' | wc -w | tr -d ' ')" != "4" ]; then
  bad "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps" \
      "fixture error: the octopus folded, so the case tests nothing"
elif bash "$ROOT/scripts/trunk-audit.sh" "$TAD" --since "$TAD_ROOT" >"$WORK/tad.out" 2>&1; then
  ok "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps"
else
  bad "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps" \
      "the audit condemned pre-rule history by its parent count, which is age inferred from shape"
fi

# ===========================================================================
# THE RECORDED TRUNK NAME IS THE ONLY TRUNK TEST (F1 and F9, 2026-08-07).
#
# Between 2026-08-05 and 2026-08-07 slh_on_trunk also consulted what HEAD
# TRACKS, so a git-flow repository working on `trunk` while sdd.json recorded
# "main" would still be governed. It could not tell that shape apart from the
# ordinary one: `git checkout -b <name> origin/main` is git's own documented way
# to branch from a remote trunk, git announces it with "set up to track", and
# every such branch became the trunk to the hooks. Merges of role-path code into
# ordinary spec and feature branches were hard-refused SLH-CLOSES-NO-SPEC, with
# a message naming `main` as the target of a merge that never touched it, and
# the only remedies were an undocumented `git branch --unset-upstream` or
# SETLIST_SKIP_HOOKS=1, which turns the whole layer off.
#
# The discriminator was removed. These three assertions pin BOTH directions of
# that decision: the two ordinary shapes must be allowed, and the git-flow shape
# is a Known limitation rather than a silent hole. Re-introducing any tracking
# test turns the first two red before it can ship.
GHF="$WORK/gh-gitflow"; rm -rf "$GHF"; mkdir -p "$GHF/src" "$GHF/specs" "$GHF/.claude" "$GHF/.githooks"
git_init "$GHF"
git -C "$GHF" config merge.ff false
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$GHF/.claude/sdd.json"
printf 'x\n' > "$GHF/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$GHF/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$GHF/.githooks/"
chmod +x "$GHF/.githooks/pre-merge-commit"
git -C "$GHF" add -A >/dev/null 2>&1
git -C "$GHF" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
git -C "$GHF" config core.hooksPath .githooks
git init -q --bare "$WORK/gh-gitflow-rem.git"
git -C "$GHF" remote add origin "$WORK/gh-gitflow-rem.git"
git -C "$GHF" push -q origin main >/dev/null 2>&1
git -C "$GHF" fetch -q origin >/dev/null 2>&1

# The branch that carries the code the merges below bring. Committed with the
# hooks bypassed because what is under test is the MERGE decision, not this.
git -C "$GHF" checkout -q -b feat/help main
printf 'help\n' > "$GHF/src/help.js"
git -C "$GHF" add -A >/dev/null 2>&1
git -C "$GHF" -c core.hooksPath=/dev/null commit -qm help >/dev/null 2>&1

# ORDINARY WORK 1: a spec branch cut from origin/main. The upstream is set by
# git, not by the developer, and the branch is not the trunk.
git -C "$GHF" merge --abort >/dev/null 2>&1 || true
git -C "$GHF" checkout -q -f main
git -C "$GHF" checkout -q -b spec/0002-tracked origin/main >/dev/null 2>&1
( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m feat/help ) >"$WORK/ghf1.out" 2>&1
if git -C "$GHF" cat-file -e spec/0002-tracked:src/help.js 2>/dev/null; then
  ok "gitflow a: a spec branch cut from origin/main is not the trunk, and its merges land"
else
  bad "gitflow a: a spec branch cut from origin/main is not the trunk, and its merges land" \
      "the guarantee layer refused ordinary work on a branch git itself set up to track: $(head -3 "$WORK/ghf1.out" | tr '\n' ' ')"
fi

# ORDINARY WORK 2: the same for a feature branch, and for a purely LOCAL
# upstream, where no remote is involved at all.
git -C "$GHF" merge --abort >/dev/null 2>&1 || true
git -C "$GHF" checkout -q -f main
git -C "$GHF" checkout -q -b feat/localtrack >/dev/null 2>&1
git -C "$GHF" branch --set-upstream-to=main feat/localtrack >/dev/null 2>&1
( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m feat/help ) >"$WORK/ghf2.out" 2>&1
if git -C "$GHF" cat-file -e feat/localtrack:src/help.js 2>/dev/null; then
  ok "gitflow b: a branch whose upstream is a LOCAL trunk is not the trunk either"
else
  bad "gitflow b: a branch whose upstream is a LOCAL trunk is not the trunk either" \
      "--set-upstream-to=main made an ordinary branch the trunk to the hooks: $(head -3 "$WORK/ghf2.out" | tr '\n' ' ')"
fi

# THE LIMITATION, ASSERTED: an instance working on `trunk` while sdd.json says
# "main" is NOT governed. This is a hole, and it is documented as one; the
# assertion exists so it cannot be re-closed by accident, without the
# false-denial cost above being paid again and re-decided.
GHG="$WORK/gh-gitflow2"; rm -rf "$GHG"; cp -R "$GHF" "$GHG"
git -C "$GHG" merge --abort >/dev/null 2>&1 || true
git -C "$GHG" checkout -q -f main
git -C "$GHG" branch -m main trunk >/dev/null 2>&1
git -C "$GHG" branch --set-upstream-to=origin/main trunk >/dev/null 2>&1
git -C "$GHG" branch main trunk >/dev/null 2>&1
git -C "$GHG" checkout -q -b spec/0001-thing
printf 'unspecced\n' > "$GHG/src/f.js"
git -C "$GHG" add -A >/dev/null 2>&1
git -C "$GHG" -c core.hooksPath=/dev/null commit -qm f >/dev/null 2>&1
git -C "$GHG" checkout -q trunk
( cd "$GHG" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m close spec/0001-thing ) >/dev/null 2>&1
if git -C "$GHG" cat-file -e trunk:src/f.js 2>/dev/null; then
  ok "gitflow c: KNOWN HOLE, an instance whose recorded trunk is not the branch it merges onto is ungoverned"
else
  bad "gitflow c: KNOWN HOLE, an instance whose recorded trunk is not the branch it merges onto is ungoverned" \
      "this hole closed, which is good news that has to be paid for: check the ordinary-work assertions above, then move the bullet out of Known limitations in the same commit"
fi


# ===========================================================================
# CONTENT SCANNING IS BOUND TO CONTENT, NOT TO AN OPERATION (F1, 2026-08-05).
#
# The em-dash and secret scans lived in pre-commit alone, so every route that
# creates a commit WITHOUT firing pre-commit carried unscanned bytes to the
# trunk. Measured on the shipped tree: cherry-pick, rebase, am, merge --no-ff
# and merge --ff each landed a live-shaped key at rc=0 while the identical bytes
# through `git commit` were refused SLH-SECRET.
#
# Both directions, because a scan that refuses everything is not a scan.
# ===========================================================================
SECRET_LINE='const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";'

# CONTROL, and it is the one that makes the rest mean anything: the ordinary
# commit path still refuses these bytes.
GHS="$WORK/gh-scan-ctl"; gh_fixture "$GHS" yes
printf '%s\n' "$SECRET_LINE" > "$GHS/src/leak.js"
git -C "$GHS" add src/leak.js >/dev/null 2>&1
if git -C "$GHS" commit -qm "leak" >/dev/null 2>&1; then
  bad "scan control: git commit still refuses a secret-shaped string" "the commit was allowed, so no result below is interpretable"
else ok "scan control: git commit still refuses a secret-shaped string"; fi

# THE MERGE PATH. pre-commit does not fire for a true merge, which is how the
# framework's own close path carried unscanned content.
GHM="$WORK/gh-scan-merge"; gh_fixture "$GHM" yes
git -C "$GHM" checkout -q spec/0001-thing
printf '%s\n' "$SECRET_LINE" > "$GHM/src/leak.js"
git -C "$GHM" add -A >/dev/null 2>&1
git -C "$GHM" -c core.hooksPath=/dev/null commit -qm "leak on the branch" >/dev/null 2>&1
git -C "$GHM" checkout -q main
( cd "$GHM" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if git -C "$GHM" cat-file -e main:src/leak.js 2>/dev/null; then
  bad "scan merge: a merge carrying a secret is refused" "the merge landed the secret on the trunk, which is F1 still open"
else ok "scan merge: a merge carrying a secret is refused"; fi

# THE CONTROL FOR THE MERGE PATH: clean content still merges. Without this the
# assertion above is satisfied by a hook that refuses every merge.
GHMC="$WORK/gh-scan-merge-ok"; gh_fixture "$GHMC" yes
( cd "$GHMC" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
# THE ROUTES GIT GIVES NO HOOK FOR, both halves. The scan is bound to content
# rather than to an operation, but git still fires nothing for cherry-pick, so
# the claim is not "every route is scanned at commit time", it is "no route
# reaches a REMOTE unscanned". Both halves are asserted because the second is
# the entire reason the first is acceptable.
GHC="$WORK/gh-scan-cherry"; gh_fixture "$GHC" yes
git -C "$GHC" checkout -q -b leaky
printf '%s\n' "$SECRET_LINE" > "$GHC/src/leak.js"
git -C "$GHC" add -A >/dev/null 2>&1
git -C "$GHC" -c core.hooksPath=/dev/null commit -qm "leak" >/dev/null 2>&1
GHC_SHA="$(git -C "$GHC" rev-parse HEAD)"
git -C "$GHC" checkout -q main
if git -C "$GHC" cherry-pick "$GHC_SHA" >/dev/null 2>&1 && git -C "$GHC" cat-file -e main:src/leak.js 2>/dev/null; then
  ok "scan cherry a: cherry-pick really does create a commit no commit-time scan sees (documented hole, still open)"
else
  ok "scan cherry a: cherry-pick is now caught at commit time, which CLOSES a documented hole; update Known limitations and this ledger entry"
fi
# The half that makes it acceptable: pre-push reads the range and refuses.
cp "$ROOT/templates/git-hooks/pre-push" "$GHC/.githooks/pre-push" 2>/dev/null
chmod +x "$GHC/.githooks/pre-push" 2>/dev/null
git init -q --bare "$WORK/gh-scan-cherry-rem.git"
git -C "$GHC" remote add origin "$WORK/gh-scan-cherry-rem.git" >/dev/null 2>&1
if git -C "$GHC" push -q origin main >/dev/null 2>&1; then
  bad "scan cherry b: the push-time range scan refuses a cherry-picked secret" \
      "the push succeeded, so the secret reached a remote and the README's claim that a pushed history cannot carry one is false"
else ok "scan cherry b: the push-time range scan refuses a cherry-picked secret"; fi

# ===========================================================================
# THE SCAN COVERS EVERY PUSHED BRANCH REF, NOT JUST THE TRUNK (F2, verdict leg).
#
# "scan cherry b" above pushes the TRUNK, and it passed the whole time while the
# ordinary push of a SPEC BRANCH published unscanned content: pre-push applied
# the trunk-name filter before the scan, so the scan inherited the audit's
# scope. The assertion was real and proved a narrower claim than the
# Known-limitations bullet beside it promised, which is how a true test sits
# next to a false sentence.
#
# So the corpus is the ref name as its own axis, across all three routes git
# gives no commit-time hook for, with a clean spec branch as the control that
# stops this being satisfied by a hook that refuses every push.
scan_ref_fixture() { # scan_ref_fixture <dir>
  local d="$1"; rm -rf "$d" "$d-rem.git"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  # pre-push looks for the audit HERE; without it the hook refuses for an
  # unrelated reason and every case below would pass while testing nothing.
  # That exact fixture gap produced a false refutation of this finding during
  # triage, so the fixture is built to reach the scan rather than to fail early.
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # Seed the remote with a trunk so it is NOT empty. Pushing a spec branch is the
  # ordinary case of pushing to a repo that already has a trunk: the branch is
  # content-scanned but not trunk-audited. Since the F1 empty-remote fix
  # (plugin-2.0.0 leg), a branch pushed FIRST to an EMPTY remote is a trunk
  # candidate and IS audited, so these scan/toolchain controls -- which push spec
  # branches carrying role-path code -- would be refused as trunk on an empty
  # remote. That refusal is correct behaviour but not the false-denial these
  # controls exist to catch, so the fixture models the real scenario. The seed
  # push bypasses the hooks; it only needs to populate the remote's default ref.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
}
SCAN_SECRET='const token = "ghp_abcdefghijklmnop1234"'
SCAN_REF_BAD=""
SCAND="$WORK/scan-refs"; scan_ref_fixture "$SCAND"

# donor commits, each made without firing pre-commit, then carried onto a spec
# branch by a route git gives no hook for.
git -C "$SCAND" checkout -q -b donor1 main
printf '%s\n' "$SCAN_SECRET" > "$SCAND/src/leak1.js"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d1 >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0001-cherry main
git -C "$SCAND" cherry-pick donor1 >/dev/null 2>&1

git -C "$SCAND" checkout -q -b donor2 main
printf '%s\n' "$SCAN_SECRET" > "$SCAND/src/leak2.js"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d2 >/dev/null 2>&1
git -C "$SCAND" format-patch -1 donor2 -o "$WORK/scan-patches" >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0002-am main
git -C "$SCAND" am "$WORK"/scan-patches/*.patch >/dev/null 2>&1

git -C "$SCAND" checkout -q -b donor3 main
printf 'a %s b\n' "$EMDASH" > "$SCAND/note.md"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d3 >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0003-rebase donor3
git -C "$SCAND" rebase main >/dev/null 2>&1

for scan_ref in spec/0001-cherry spec/0002-am spec/0003-rebase; do
  if git -C "$SCAND" push -q origin "$scan_ref" >/dev/null 2>&1; then
    SCAN_REF_BAD="$SCAN_REF_BAD $scan_ref(pushed)"
  fi
done
if [[ -z "$SCAN_REF_BAD" ]]; then
  ok "scan refs: a spec-branch push carrying cherry-picked, am-applied or rebased content is scanned and refused"
else
  bad "scan refs: a spec-branch push carrying cherry-picked, am-applied or rebased content is scanned and refused" \
      "these reached the remote unscanned:$SCAN_REF_BAD; the scan is inheriting the audit's trunk-only scope again"
fi

# THE CONTROL, and without it the assertion above is satisfied by a hook that
# refuses every push.
git -C "$SCAND" checkout -q -b spec/0004-clean main
printf 'ordinary work\n' > "$SCAND/src/ok.js"
git -C "$SCAND" add -A >/dev/null 2>&1
git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
if git -C "$SCAND" push -q origin spec/0004-clean >/dev/null 2>&1; then
  ok "scan refs control: a CLEAN spec-branch push is still allowed"
else
  bad "scan refs control: a CLEAN spec-branch push is still allowed" \
      "ordinary work was refused, which is the false-denial direction and makes the refusals above meaningless"
fi

if gh_landed "$GHMC"; then
  ok "scan merge control: a clean closed spec still merges"
else
  bad "scan merge control: a clean closed spec still merges" "the scan refuses compliant work, which is the false-denial direction"
fi


# --- the refusal direction ---
GH="$WORK/gh-open"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks a: merging an UNCLOSED spec onto the trunk is refused" "the merge landed"
else ok "git hooks a: merging an UNCLOSED spec onto the trunk is refused"; fi

# The stalled merge. git leaves the refused merge STAGED and prints "use 'git
# commit' to complete the merge", and that commit fires pre-commit rather than
# pre-merge-commit. Found by the oracle: without MERGE_HEAD handling in
# pre-commit, the operator is one git-suggested command from landing the merge
# that was just refused.
( cd "$GH" && GIT_EDITOR=true git commit -m "complete the merge" ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks b: completing the STALLED merge with a plain commit is refused" "the merge landed"
else ok "git hooks b: completing the STALLED merge with a plain commit is refused"; fi

# The squash. git fires no pre-merge-commit for it at all.
#
# THIS ASSERTION EVALUATED NOTHING UNTIL 2026-08-03 (1.1.0 adversarial review, F13).
# It ran `git merge --squash` inside a fixture that sets `merge.ff=false`, and
# git refuses that combination: `fatal: options '--squash' and '--no-ff.'
# cannot be used together`, exit 128. stderr went to /dev/null so the fatal was
# invisible, `&&` short-circuited so the commit never ran, SQUASH_MSG was never
# written, and pre-commit never fired. gh_landed was therefore false and the
# test took the `else ok` branch. The ONLY assertion covering pre-commit's
# expensive squash branch reported a pass over a command that never reached it,
# and pre-commit's own header calls that branch the sole reason it exists.
#
# The hook is fine; the test was not. Reached by a spelling that survives the
# shipped config, pre-commit prints "this commit completes a squash merge onto
# main" and refuses. So: use that spelling, and assert the POSITIVE evidence
# (SQUASH_MSG written, the refusal text printed) rather than only that nothing
# landed. This fixture's own control comment states the general lesson, "a
# fixture that failed to build reports every refusal case as a pass"; here a
# git command that fatals for an unrelated reason was indistinguishable from a
# hook refusal.
GH="$WORK/gh-squash"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff --squash spec/0001-thing && git commit -m "squashed" ) >"$GH.out" 2>&1
if [[ -f "$GH/.git/SQUASH_MSG" ]]; then
  ok "git hooks c0: the squash spelling under test actually reaches the hook (SQUASH_MSG written)"
else
  bad "git hooks c0: the squash spelling under test actually reaches the hook (SQUASH_MSG written)" \
      "git never staged a squash, so the refusal case below tests nothing: $(head -n1 "$GH.out")"
fi
if gh_landed "$GH"; then
  bad "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit" "the squash landed"
elif grep -q "SLH-CLOSES-NO-SPEC\|SLH-NO-CLOSING-REPORT" "$GH.out"; then
  ok "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit"
else
  bad "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit" \
      "nothing landed, but no setlist refusal was printed either, so this is not evidence the hook ran: $(head -n1 "$GH.out")"
fi

# The ALLOW direction of the same branch, which did not exist and is why the
# vacuous case above survived: with only a refusal case, a squash that never
# runs looks exactly like a squash that is refused.
GH="$WORK/gh-squash-ok"; gh_fixture "$GH" yes
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff --squash spec/0001-thing && git commit -m "squashed" ) >"$GH.out" 2>&1
if gh_landed "$GH"; then
  ok "git hooks c2: a SQUASH merge of a CLOSED spec completes"
else
  bad "git hooks c2: a SQUASH merge of a CLOSED spec completes" \
      "the hook refused a compliant squash close: $(grep -o 'SLH-[A-Z-]*' "$GH.out" | sort -u | tr '\n' ' ')"
fi

# And the config consequence itself, named in the edition's Known limitations
# since 1.1.0: the plain spelling is FATAL in every stamped instance. Asserted
# so that if the stamp ever drops merge.ff, the documentation goes stale loudly.
GH="$WORK/gh-squash-ff"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --squash spec/0001-thing ) >"$GH.out" 2>&1
if grep -q "cannot be used together" "$GH.out"; then
  ok "git hooks c3: plain git merge --squash is fatal under the stamp's merge.ff=false, as Known limitations says"
else
  bad "git hooks c3: plain git merge --squash is fatal under the stamp's merge.ff=false, as Known limitations says" \
      "it did not fatal, so the edition's Known limitations bullet is now wrong: $(head -n1 "$GH.out")"
fi

# The fast-forward, which fires NO hook. This asserts the STAMP, not the hook:
# merge.ff=false is what turns this into a merge commit that pre-merge-commit
# can see. Measured at 11 of 60 oracle cases before the setting existed.
GH="$WORK/gh-ff"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge spec/0001-thing -m "ff" ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks d: merge.ff=false stops the fast-forward path (no hook fires for a real ff)" "it fast-forwarded onto the trunk"
else ok "git hooks d: merge.ff=false stops the fast-forward path (no hook fires for a real ff)"; fi

# Spelling immunity, which is the entire claim of the boundary move. The parser
# gates needed four releases to survive these; the hook never reads the command.
for gh_spell in \
  '{ nice -n 5 git merge --no-ff -m x spec/0001-thing; }' \
  '>/dev/null 2>&1 git merge --no-ff -m x refs/heads/spec/0001-thing' \
  'M=merge; git $M --no-ff -m x spec/0001-thing'; do
  GH="$WORK/gh-spell"; gh_fixture "$GH" no
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true bash -c "$gh_spell" ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks e: spelling [$gh_spell] is refused" "it landed"
  else ok "git hooks e: spelling [$gh_spell] is refused"; fi
done

# --- THE TRUNK SPELLING. The v1.7 dogfood gate's BLOCKER, and the reason this
# block exists at all.
#
# close-gate.sh learned in 1.0.8 that a trunk value must NAME A LOCAL BRANCH
# rather than merely be a non-empty string, and carries a 20-line comment saying
# why the reduction has to ask git instead of stripping prefixes. When v1.7 moved
# the guarantee to the git hooks, slh_trunk() got the non-empty-string half and
# not the reduction, so slh_on_trunk() compared "refs/remotes/origin/main"
# against the "main" that `symbolic-ref --short HEAD` returns, the two could
# never be equal, and pre-merge-commit took its exit 0 without evaluating its
# predicate. Five spellings landed unreviewed work on the trunk in total silence
# while close-gate.sh, the layer v1.7 DEMOTES to advisory, denied all of them.
#
# The route is not adversarial: `refs/remotes/origin/main` is what the upgrade
# skill's own detection command returns on every ordinary clone.
#
# Asserted in BOTH directions, because a trunk check that refuses everything is
# the other way to fail this. ---
for gh_tv in refs/remotes/origin/main refs/heads/main heads/main origin/main; do
  GH="$WORK/gh-trunkspell"; gh_fixture "$GH" no "$gh_tv"
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks t: trunk spelled [$gh_tv] still refuses an UNCLOSED spec" \
        "it landed, silently and at exit 0: a ref-path trunk disables the whole boundary"
  else ok "git hooks t: trunk spelled [$gh_tv] still refuses an UNCLOSED spec"; fi
done

for gh_tv in refs/remotes/origin/main refs/heads/main origin/main; do
  GH="$WORK/gh-trunkspell-ok"; gh_fixture "$GH" yes "$gh_tv"
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then ok "git hooks u: trunk spelled [$gh_tv] still ALLOWS a properly closed spec"
  else bad "git hooks u: trunk spelled [$gh_tv] still ALLOWS a properly closed spec" \
           "the reduction made an ordinary compliant close impossible, which is the other way to fail"; fi
done

# A FENCED Closing report is not a Closing report, in the layer that now carries
# the guarantee. close-gate.sh strips fenced spans once before all four close
# checks (leg 5, F7); nothing in templates/git-hooks/ did, so the whole close
# passed on quoted example text (v1.7 gate, adversarial review F9).
GH="$WORK/gh-fenced"; gh_fixture "$GH" fenced
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks w: a Closing report that exists only inside a fence is REFUSED" \
      "it landed: quoted example text satisfied every close condition"
else ok "git hooks w: a Closing report that exists only inside a fence is REFUSED"; fi

# ===========================================================================
# THE FENCED TEMPLATE FALSE DENIAL (V19-F2), FIXED 2026-08-26 AND PINNED IN THE
# ACCEPT DIRECTION.
#
# pre-commit's lifecycle detector used to read the RAW staged diff:
#   grep -qE "^\+Status:[[:space:]]*(STATES)|^\+#+[[:space:]]*Closing report"
# with no fence handling and no indent allowance. So a spec that QUOTED the
# closing-report template, changing no lifecycle state of its own, read as a
# real close and was refused SLH-STATUS-MISSING: a CONFIRMED FALSE DENIAL, it
# refused honest work. The mirror of the same regex missed an INDENTED heading
# entirely, while the three sibling readers accept it.
#
# The detector now asks slh_lifecycle_added, which strips template quotes with
# the shared SLH_TEMPLATE_FENCE_AWK and matches the shared
# SLH_CLOSING_REPORT_RE, so the fourth reader agrees with the other three (A9).
# These assertions were watched RED against the pre-fix bytes in both
# directions before the fix landed: fenced-template REFUSED and mirror-indented
# LANDED, while both controls held. THIS BLOCK IS NOW THE REGRESSION PIN: if the
# fence handling is ever lost, the first subject goes red again.
#
# Every case stages a file under specs/ and does NOT stage specs/STATUS.md. The
# discriminating variable is the CONTENT and nothing else, which is what makes
# the subject readable: a first cut of this measurement varied the PATH too and
# "reproduced" nothing.
f2_fixture() { # f2_fixture <dir> -- an armed instance sitting on the trunk
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}

f2_commits() { # f2_commits <label> <spec-body> -> 0 if the commit LANDED
  local d="$WORK/f2-$1"
  f2_fixture "$d"
  printf '%s' "$2" > "$d/specs/9001-case.md"
  git -C "$d" add specs/9001-case.md >/dev/null 2>&1
  git -C "$d" commit -qm "docs: $1" >/dev/null 2>&1
}

# CONTROL a (the allow direction): an ordinary spec edit that moves no lifecycle
# state must COMMIT. Without this the refusals below would pass against a hook
# that refuses everything.
if f2_commits control-quiet '# Spec 9001

Ordinary prose about a spec that is not closing.
'; then
  ok "f2 control a: an ordinary spec edit that moves no lifecycle state commits"
else
  bad "f2 control a: an ordinary spec edit that moves no lifecycle state commits" \
      "the hook refused a spec edit with no lifecycle line, so every refusal below proves nothing"
fi

# CONTROL b (the deny direction): a REAL close without specs/STATUS.md staged
# must be REFUSED. This is the behaviour the detector exists for.
if f2_commits control-realclose '# Spec 9001

Status: CLOSED

## Closing report

Architecture diagram: no impact
'; then
  bad "f2 control b: a REAL close without specs/STATUS.md staged is refused" \
      "it committed, so the harness cannot observe this refusal and the subject below is unreadable"
else
  ok "f2 control b: a REAL close without specs/STATUS.md staged is refused"
fi

# THE SUBJECT. A quotation of the template, inside a fence, changing nothing.
if f2_commits fenced-template '# Spec 9001

This spec is ACTIVE. It shows readers what a closing report looks like:

```markdown
Status: CLOSED

## Closing report

Architecture diagram: no impact
```

Nothing above is this spec own lifecycle state: it is a quotation.
'; then
  ok "V19-F2 fixed: a FENCED quotation of the close template commits"
else
  bad "V19-F2 fixed: a FENCED quotation of the close template commits" \
      "it was REFUSED. The false denial is back: the detector has stopped stripping template quotes, and honest authoring that copies the shipped template is being refused SLH-STATUS-MISSING"
fi

# THE MIRROR DEFECT, same finding, opposite direction: an INDENTED heading was
# not matched at all, while the release's three other readers accept
# "^ {0,3}#{1,6}[ \t]+Closing report". Isolated to the indent by a control that
# differs in nothing else, because the first cut of this case carried a Status
# line too and so proved nothing about indentation. Now REFUSED, like its
# unindented sibling below and like the other three readers.
if f2_commits mirror-indented '# Spec 9001

  ## Closing report

Architecture diagram: no impact
'; then
  bad "V19-F2 mirror fixed: an INDENTED closing-report heading IS seen by this detector" \
      "it committed, so the detector has gone back to the column-anchored regex and disagrees with the three sibling readers about what a heading is"
else
  ok "V19-F2 mirror fixed: an INDENTED closing-report heading IS seen by this detector"
fi
if f2_commits mirror-control '# Spec 9001

## Closing report

Architecture diagram: no impact
'; then
  bad "f2 mirror control: an UNINDENTED closing-report heading IS seen" \
      "it committed, so the indent case above is not discriminating: the detector is missing the heading for some other reason"
else
  ok "f2 mirror control: an UNINDENTED closing-report heading IS seen"
fi

# THE GUARANTEE LAYER ALSO DEPENDS ON THE TOOLCHAIN, and F2 measured this half
# separately: with grep broken, the git hooks landed the merge at rc=0 in silence
# while broken awk, sed and tr still refused. The library's banner promises
# "EVERYTHING HERE FAILS CLOSED", so it owes the same probe the Bash gates now
# carry. Driven through a REAL merge on a shimmed PATH, not by calling the
# library, because what is being asserted is that git's invocation of the hook
# fails closed.
for bt in awk sed tr grep; do
  build_brokentool_bin "$bt"
  GH="$WORK/gh-toolchain"; gh_fixture "$GH" no
  ( cd "$GH" && PATH="$BROKENTOOL_BIN" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true \
      git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks x: the git hooks REFUSE when $bt is broken" \
        "it landed: the layer v1.7 makes the guarantee failed OPEN on a broken $bt"
  else ok "git hooks x: the git hooks REFUSE when $bt is broken"; fi
done

# A trunk that resolves to NOTHING must refuse rather than pass. The library's
# own banner promises "EVERYTHING HERE FAILS CLOSED", and the upgrade skill tells
# the reader the hooks "refuse a trunk that names no local branch".
GH="$WORK/gh-trunk-nobranch"; gh_fixture "$GH" no "no-such-branch"
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks v: a trunk naming NO local branch REFUSES rather than passing" \
      "it landed: the gate could not establish which branch it protects and allowed the merge anyway"
else ok "git hooks v: a trunk naming NO local branch REFUSES rather than passing"; fi

# --- the ALLOW direction, which is what stops this being a hook that refuses
# everything. Two of this repo's own bypasses were closed by making a gate
# unusable, so the positive case is not optional. ---
GH="$WORK/gh-closed"; gh_fixture "$GH" yes
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks f: a properly CLOSED spec still merges"
else bad "git hooks f: a properly CLOSED spec still merges" "a compliant close was refused"; fi

# Merging the TRUNK INTO a spec branch is how a long branch keeps up. It is not
# a close and must not be gated, or the ordinary workflow becomes impossible.
GH="$WORK/gh-into"; gh_fixture "$GH" no
( cd "$GH" && printf 'trunkside\n' > src/t.txt && git add -A && SETLIST_SKIP_HOOKS=1 git commit -qm trunkside ) >/dev/null 2>&1
( cd "$GH" && git checkout -q spec/0001-thing && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "catch up" main ) >/dev/null 2>&1
if [[ -f "$GH/src/t.txt" ]]; then ok "git hooks g: merging the trunk INTO a spec branch is not gated"
else bad "git hooks g: merging the trunk INTO a spec branch is not gated" "the catch-up merge was refused"; fi

# The documented escape hatch, and the non-instance case.
GH="$WORK/gh-skip"; gh_fixture "$GH" no
( cd "$GH" && SETLIST_SKIP_HOOKS=1 GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks h: SETLIST_SKIP_HOOKS=1 is a real, documented bypass"
else bad "git hooks h: SETLIST_SKIP_HOOKS=1 is a real, documented bypass" "the escape hatch did not work"; fi

GH="$WORK/gh-noinst"; gh_fixture "$GH" no; rm -f "$GH/.claude/sdd.json"
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks i: a repo that is not a framework instance is untouched"
else bad "git hooks i: a repo that is not a framework instance is untouched" "a non-instance merge was refused"; fi

# The library must REFUSE when it cannot be found, never pass. Same rule as
# pre-push d: a check that cannot run has not passed.
GH="$WORK/gh-nolib"; gh_fixture "$GH" yes; rm -f "$GH/.githooks/setlist-hook-lib.sh"
( cd "$GH" && env -u CLAUDE_PLUGIN_ROOT GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks j: a hook that cannot find its library REFUSES rather than passing" "it passed with no library"
else ok "git hooks j: a hook that cannot find its library REFUSES rather than passing"; fi

# THE DIAGRAM FIELD IS FIRST-LINE-WINS (KL1, ruled 2026-08-29 and shipped in
# 2.3.0; the public bullet left the list in spec 0126's public-list commit,
# worded fix-plus-correction because the bullet still described last-wins a
# day after the mechanics shipped first-wins). This replaces the old
# either-way "documented hole" pin, whose fixture named the field MID-LINE
# and so never exercised the anchored reader in either generation: a pin that
# passes both ways on an input the reader cannot see is the vacuous-comparison
# class, recorded here so it is not reinvented. Both directions, ANCHORED:
# a later bullet that repeats the label neither unanswers a real field nor
# answers a placeholder one.
DIAGN="$WORK/diag-note"; rm -rf "$DIAGN"; close_fixture "$DIAGN" yes yes answered yes no true
git -C "$DIAGN" checkout -q spec/0001-thing
printf -- '- Architecture diagram: <updated in this commit | no impact>\n' >> "$DIAGN/specs/0001-thing.md"
git -C "$DIAGN" add -A >/dev/null 2>&1
git -C "$DIAGN" commit -qm "an anchored later bullet repeating the label" >/dev/null 2>&1
git -C "$DIAGN" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$DIAGN" "$(bash_payload "$MERGE_CMD")"
if [[ -z "$HOOK_OUT" ]]; then
  ok "diagram first-wins a: an anchored later placeholder bullet cannot UNANSWER a real field (KL1's refuse direction, closed)"
else
  bad "diagram first-wins a: an anchored later placeholder bullet cannot UNANSWER a real field (KL1's refuse direction, closed)" \
      "the merge was denied, so a later line is deciding the field again; KL1's class is back"
fi
DIAGN2="$WORK/diag-note2"; rm -rf "$DIAGN2"; close_fixture "$DIAGN2" yes yes unanswered yes no true
git -C "$DIAGN2" checkout -q spec/0001-thing
printf -- '- Architecture diagram: no impact\n' >> "$DIAGN2/specs/0001-thing.md"
git -C "$DIAGN2" add -A >/dev/null 2>&1
git -C "$DIAGN2" commit -qm "an anchored later bullet answering for the field" >/dev/null 2>&1
git -C "$DIAGN2" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$DIAGN2" "$(bash_payload "$MERGE_CMD")"
if [[ -z "$HOOK_OUT" ]]; then
  bad "diagram first-wins b: an anchored later answering bullet cannot ANSWER a placeholder field (KL1's publish direction, closed)" \
      "the merge was allowed, so a later line answered a field nobody answered; KL1's class is back"
else
  ok "diagram first-wins b: an anchored later answering bullet cannot ANSWER a placeholder field (KL1's publish direction, closed)"
fi

# THE ESCAPE pre-push DOES NOT READ (v1.7 second bound leg, F9), pinned because
# the hook's own refusal text names it and a reader will try it. Documented
# rather than fixed: the message is mechanism, and the bound forbids a repair
# round. The assertion is on the SOURCE rather than on a live push, because what
# is being pinned is that pre-push consults no such variable at all.
# BEHAVIOURAL, because the first version of this assertion grepped the source for
# the NAME and reported the hole closed: the string is present in pre-push, only
# inside the refusal message that recommends it. A mention is not a read, and a
# pattern match cannot tell them apart. So a real refusal is provoked and the
# escape is actually set.
SKIPE="$WORK/skip-escape"; rm -rf "$SKIPE" "$SKIPE-rem.git"
scan_ref_fixture "$SKIPE"
git -C "$SKIPE" checkout -q -b spec/0007-esc main
printf '%s\n' "$SCAN_SECRET" > "$SKIPE/src/leak.js"
git -C "$SKIPE" add -A >/dev/null 2>&1
git -C "$SKIPE" -c core.hooksPath=/dev/null commit -qm leak >/dev/null 2>&1
if git -C "$SKIPE" push -q origin spec/0007-esc >/dev/null 2>&1; then
  bad "skip escape control: the push is refused without the escape" \
      "the push succeeded with no escape set, so the case below proves nothing"
else
  ok "skip escape control: the push is refused without the escape"
  if SETLIST_SKIP_HOOKS=1 git -C "$SKIPE" push -q origin spec/0007-esc >/dev/null 2>&1; then
    ok "skip escape: SETLIST_SKIP_HOOKS now gets a push through, which CLOSES a documented hole; update the bullet and this ledger entry"
  else
    ok "skip escape: SETLIST_SKIP_HOOKS does not get a refused push through, as Known limitations records (documented hole, still open)"
  fi
fi

# ===========================================================================
# THE CHAINED MERGE (v1.7 claims round 4, F1), and the catch-up control.
#
# A close authorises the code riding with it, and "riding with it" used to be
# unbounded: unspecced role-path code merged INTO a spec branch, then that
# branch merged onto the trunk with a fully compliant close, reached the REMOTE
# with both layers reporting clean. Classified by replay as a GUARANTEE-layer
# falsification (unspecced code on the remote trunk), not a scan hole, so it was
# fixed under the standing amendment rather than documented.
#
# The third case is the one that matters most: merging the trunk INTO a spec
# branch is ordinary work, and a fix that refused it would be the false denial
# this repository treats as worse than the bypass.
chain_fixture() { # chain_fixture <dir>
  local d="$1"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  git -C "$d" config merge.ff false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
}
chain_close() { # chain_close <dir>
  local d="$1"
  printf 'export const legit = 1\n' > "$d/src/legit.js"
  printf '# Spec 0001 - First\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-first.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "spec 0001 + code" >/dev/null 2>&1
}
CHA="$WORK/chain-attack"; chain_fixture "$CHA"
git -C "$CHA" checkout -q -b junk main
printf 'export const sneaky = 1\n' > "$CHA/src/sneaky.js"
git -C "$CHA" add -A >/dev/null 2>&1; git -C "$CHA" commit -qm "sneaky, no spec" >/dev/null 2>&1
git -C "$CHA" checkout -q -b spec/0001-first main; chain_close "$CHA"
git -C "$CHA" merge -q --no-ff junk -m "merge junk into spec branch" >/dev/null 2>&1
git -C "$CHA" checkout -q main
git -C "$CHA" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHA" >/dev/null 2>&1; then
  ok "chain a: KNOWN HOLE, a chained merge past a compliant close is reported clean, as Known limitations records"
else
  ok "chain a: a chained merge is refused again, which CLOSES a documented hole; re-run the two-clone assertion below and the ordinary-work controls, then move the bullet in the same commit"
fi

# A `<<\EOF` HEREDOC BODY IS READ AS CODE (leg F10), documented not fixed.
#
# The owner's decision on 2026-08-08 was to hold the v1.7 parser freeze and
# correct the documentation instead of widening hd_scan's delimiter class. This
# assertion exists because the ledger entry says "asserted", and because the day
# the freeze lifts, somebody needs to be told this closed.
#
# What made it worth a bullet rather than a shrug: it is not merely an absent
# warning. It RUNS the project's gate command, synchronously, inside the
# PreToolUse hook, before an ordinary `git commit`. The template ships
# timeout 1800 for that entry.
#
# FOUR FIXTURES were needed to measure this, and the first three would each have
# produced a confidently wrong bullet: a non-existent merge operand
# short-circuited at CG-UNNAMEABLE-REF, a chore branch never reached the
# gate-command path at all, and a non-compliant spec was denied at
# CG-NO-CLOSING-REPORT first. Only a COMPLIANT spec reaches the gate command, so
# only that fixture can see this. The controls below are the reason that was
# caught rather than written up.
hd_fixture() { # hd_fixture <dir> <marker-path>
  local d="$1" mk="$2"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"touch %s","roles":{"src":"src"}}\n' "$mk" > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0100 | G | ACTIVE | a |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm i >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0100-good
  printf 'export const g = 1\n' > "$d/src/g.js"
  printf '# Spec 0100\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0100-good.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0100 | G | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm w >/dev/null 2>&1
  git -C "$d" checkout -q main
}
# hd_ran <dir> <marker> <command> -> "YES"/"no"
hd_ran() {
  rm -f "$2"
  printf %s "$(jq -nc --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}')" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/close-gate.sh" >/dev/null 2>&1
  [[ -f "$2" ]] && printf 'YES' || printf 'no'
}
HDD="$WORK/heredoc"; HDM="$WORK/heredoc-gate-ran"; hd_fixture "$HDD" "$HDM"
HD_CTL=""
[[ "$(hd_ran "$HDD" "$HDM" 'git merge --no-ff spec/0100-good')" == "YES" ]] || HD_CTL="$HD_CTL real-merge-did-not-run-it"
[[ "$(hd_ran "$HDD" "$HDM" 'git commit -m "ordinary message"')" == "no" ]] || HD_CTL="$HD_CTL plain-commit-ran-it"
if [[ -z "$HD_CTL" ]]; then
  ok "heredoc control: a real merge runs the gate command and a plain commit does not"
else
  bad "heredoc control: a real merge runs the gate command and a plain commit does not" \
      "the fixture proves nothing:$HD_CTL; only a COMPLIANT spec reaches the gate-command path, which is what three earlier fixtures missed"
fi
HD_BS="$(hd_ran "$HDD" "$HDM" 'git commit -F - <<\EOF
git merge --no-ff spec/0100-good was reverted
EOF')"
HD_Q="$(hd_ran "$HDD" "$HDM" "git commit -F - <<'EOF'
git merge --no-ff spec/0100-good was reverted
EOF")"
if [[ "$HD_BS" == "YES" && "$HD_Q" == "no" ]]; then
  ok "heredoc: KNOWN HOLE, a <<\\EOF body still runs the gate command, as Known limitations records"
elif [[ "$HD_BS" == "no" ]]; then
  ok "heredoc: a <<\\EOF body no longer runs the gate command, which CLOSES a documented hole; move the bullet and this ledger entry in the same commit"
else
  bad "heredoc: the quoted spelling must NOT run the gate command" \
      "backslash=$HD_BS quoted=$HD_Q; the quoted form regressing means the parser got broader, not narrower, which is the direction the freeze exists to prevent"
fi

# THE REFRESH DISPLACES A FOREIGN HOOK LAYER IN SILENCE (leg F8 and F12).
#
# `git config core.hooksPath .githooks` ran unconditionally. Where a repository
# already pointed that at husky, lefthook or pre-commit, the previous value was
# not printed, not recorded and not backed up, and report mode said "git config
# still to set: core.hooksPath" while it WAS set, to something else that was
# about to be switched off. Measured: the identical `git commit` was refused by
# .husky/pre-commit before the refresh and committed cleanly after it.
#
# What is destroyed is often itself a control. gitleaks, detect-secrets and
# commit-msg validation are commonly wired exactly this way, so the failure mode
# is a project silently losing its secret scanning to a tool that arrived to add
# guarantees. git supports one hooksPath, so genuinely merging the layers is out
# of scope; the defect is that the displacement is INVISIBLE, not that it
# happens.
#
# F12 rides along because it is the same file and the same discipline: report
# what you are about to overwrite. trunk-audit.sh is a delivered file that
# appeared in no report, and the chmod globbed the whole directory rather than
# the four names the copy loop had just written.
# NOTE THE FLAG ORDER. The usage is `refresh-instance.sh [--apply] <dir>`, and
# the first cut of these assertions passed the flag AFTER the directory, so
# --apply was never parsed: every call aborted on a usage error. The "refuses to
# displace" case PASSED that way, vacuously, because core.hooksPath was left
# alone by a command that had done nothing at all. The control beside it failed
# and is the only reason it was caught.
rfi_fixture() { # rfi_fixture <dir> <existing-hookspath-or-empty>
  local d="$1" hp="$2"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  if [[ -n "$hp" ]]; then
    mkdir -p "$d/$hp"
    printf '#!/bin/sh\necho "foreign hook refusing"\nexit 1\n' > "$d/$hp/pre-commit"
    chmod +x "$d/$hp/pre-commit"
    git -C "$d" config core.hooksPath "$hp"
  fi
}

# REPORT MODE must NAME the value it is about to displace.
RFI="$WORK/rfi-report"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-report.out" 2>&1
if grep -q '\.husky' "$WORK/rfi-report.out"; then
  ok "refresh a: report mode names the foreign core.hooksPath it would displace"
else
  bad "refresh a: report mode names the foreign core.hooksPath it would displace" \
      "the report never mentioned .husky, and said [$(grep -oE 'git config still to set:[^(]*' "$WORK/rfi-report.out" | head -1)], which reads as unconfigured rather than configured to something else"
fi

# --apply must NOT silently switch a foreign layer off.
RFI="$WORK/rfi-apply"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-apply.out" 2>&1
RFI_NOW="$(git -C "$RFI" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: an unreadable value is not .husky and fails the check below
if [[ "$RFI_NOW" == ".husky" ]] || grep -qE 'refus|REFUS' "$WORK/rfi-apply.out"; then
  ok "refresh b: --apply refuses rather than switching a foreign hook layer off in silence"
else
  bad "refresh b: --apply refuses rather than switching a foreign hook layer off in silence" \
      "core.hooksPath went from .husky to [$RFI_NOW] with no refusal; what was displaced is often itself a control (gitleaks, detect-secrets, commit-msg validation)"
fi

# THE DELIBERATE OVERRIDE MUST STILL WORK. Refusing is only defensible if the
# operator has a one-step way to say "yes, displace it, I know". Without this
# the fix trades a silent destruction for a dead end.
RFI="$WORK/rfi-adopt"; rfi_fixture "$RFI" .husky
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adopt.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh d: SETLIST_ADOPT_HOOKSPATH=1 displaces the foreign layer on purpose"
else
  bad "refresh d: SETLIST_ADOPT_HOOKSPATH=1 displaces the foreign layer on purpose" \
      "the escape did not work, so the refusal above is a dead end rather than a decision point"
fi

# CONTROL: an ordinary instance, no foreign layer, must still be armed.
RFI="$WORK/rfi-plain"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-plain.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh control: an instance with no foreign hooksPath is still armed by --apply"
else
  bad "refresh control: an instance with no foreign hooksPath is still armed by --apply" \
      "the ordinary path stopped arming, which is the false-denial direction and worse than the hole above"
fi

# F6 of the 2026-08-11 leg: THE GUARD DECIDED BY NAME, NOT BY WHAT IS THERE.
# `case "$FOREIGN_HOOKSPATH" in ""|".githooks") FOREIGN_HOOKSPATH="" ;; esac`
# read ".githooks" as "already ours", but .githooks is the CONVENTIONAL name
# for a tracked hooks directory and nothing about the name makes the hooks in
# it Setlist's. A project whose own gitleaks-style layer lived there was
# displaced with neither the refusal nor the warning the README promises, which
# is the exact before-and-after this fix's own comment cites as its reason.
RFI="$WORK/rfi-githooks-foreign"; rfi_fixture "$RFI" .githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-gh.out" 2>&1
RFI_GH_SURVIVED=0
grep -q 'foreign hook refusing' "$RFI/.githooks/pre-commit" 2>/dev/null && RFI_GH_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-gh.out" && [[ "$RFI_GH_SURVIVED" -eq 1 ]]; then
  ok "refresh F6a: a FOREIGN hook layer living at .githooks is refused, not silently displaced"
else
  bad "refresh F6a: a FOREIGN hook layer living at .githooks is refused, not silently displaced" \
      "no refusal was printed (survived=$RFI_GH_SURVIVED); the project's own pre-commit was switched off by name alone, and what gets displaced is frequently itself a control"
fi

# THE FALSE-DENIAL DIRECTION, which matters more than the hole: an instance
# whose .githooks really does hold Setlist's own hooks is the ORDINARY
# re-refresh, and it must not start reading as a foreign layer.
RFI="$WORK/rfi-githooks-ours"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-ghours.out" 2>&1
if grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-ghours.out"; then
  bad "refresh F6b: re-refreshing an instance armed by Setlist is not a displacement" \
      "the second --apply refused its own hooks, which would make every upgrade a dead end"
else
  ok "refresh F6b: re-refreshing an instance armed by Setlist is not a displacement"
fi


# =============================================================================
# THE HEADLESS BUILD INTEGRITY CHAIN (KL3), spec 0124, from the ratified design
# `design-attestation-kl3-2026-08-28.md`.
#
# WHAT THESE ASSERTIONS ARE EVIDENCE OF, stated first because A8 requires it and
# because this is the one feature where the distinction decides the design: a
# green here is evidence that a SIGNATURE VERIFIED, never that a PERSON
# APPROVED. Nothing a suite can write establishes the second. That is why the
# mechanism prints its declared custody on every verification INCLUDING the
# passes, and why one of the assertions below is about the PASSING message
# rather than about a refusal. It is the only one that covers the failure mode
# the design exists inside, and it would be the easiest to leave out.
#
# The tokens the verifier may print are a closed set, and the caller refuses
# anything that is not exactly VERIFIED. The empty-token case is asserted with a
# deliberately broken verifier rather than argued, because "every failure of the
# verifier itself lands in the allow branch" is F3-2026's class and asserting it
# by reading the code is how it survives.
# =============================================================================

# ssh-keygen is PROBED, not located. `-Y sign` arrived in OpenSSH 8.2 and a
# host can carry an older binary; a `command -v` that passed for a tool whose
# subcommand does not exist would leave every assertion below reporting on a
# mechanism it never reached.
ATT_HAVE_SSH=0
if command -v ssh-keygen >/dev/null 2>&1 \
   && ssh-keygen -q -t ed25519 -N "" -C probe@example.test -f "$WORK/att-probe" >/dev/null 2>&1 \
   && printf 'probe\n' > "$WORK/att-probe.txt" \
   && ssh-keygen -Y sign -f "$WORK/att-probe" -n setlist-attestation "$WORK/att-probe.txt" >/dev/null 2>&1; then
  ATT_HAVE_SSH=1
fi

# att_fixture <dir> <custody|off> [verify_with]
# A stamped instance carrying an ACTIVE spec and staged role-path work, which is
# exactly the shape a headless build produces: the commit is ordinary and it is
# what pre-commit sees first.
att_fixture() { # att_fixture <dir> <custody|off> [verify_with]
  local d="$1" custody="$2" vw="${3:-.claude/approvers.pub}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs/attest" "$d/.claude" "$d/.githooks"
  git_init "$d"
  if [[ "$custody" == "off" ]]; then
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  else
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"attestation":{"required":true,"custody":"%s","verify_with":"%s"}}\n' "$custody" "$vw" > "$d/.claude/sdd.json"
  fi
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n\n## Goal\nBuild the thing.\n\n## Closing report\n- pending\n' > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  # The work: role-path content, which is what makes the predicate apply at all.
  printf 'work\n' > "$d/src/FEATURE.txt"
  git -C "$d" add -A >/dev/null 2>&1
}

# att_sign <dir> [spec-field] [num-field] [hash-override] [verdict]
# Writes the attestation document and signs it with the fixture's own key. Each
# override exists so a NEGATIVE case differs from the positive one in exactly
# one field, which is what makes a red mean what it says.
att_sign() { # att_sign <dir> [spec] [num] [hash] [verdict]
  local d="$1" spec="${2:-specs/0001-thing.md}" num="${3:-0001}" h="${4:-}" v="${5:-APPROVED}"
  [[ -n "$h" ]] || h="$(bash "$ROOT/scripts/spec-hash.sh" "$d/specs/0001-thing.md")"
  mkdir -p "$d/specs/attest"
  printf '{\n  "setlist_attestation": 1,\n  "spec": "%s",\n  "spec_number": "%s",\n  "spec_hash": "%s",\n  "verdict": "%s",\n  "approver": "approver@example.test",\n  "custody": "signer",\n  "tool": "setlist/checkpoint",\n  "tool_version": "2.3.0",\n  "at": "2026-08-29T00:00:00Z",\n  "notes": ""\n}\n' \
    "$spec" "$num" "$h" "$v" > "$d/specs/attest/${num}.json"
  if [[ ! -f "$WORK/att-key" ]]; then
    ssh-keygen -q -t ed25519 -N "" -C approver@example.test -f "$WORK/att-key" >/dev/null 2>&1
  fi
  printf 'approver@example.test %s\n' "$(cat "$WORK/att-key.pub")" > "$d/.claude/approvers.pub"
  ssh-keygen -Y sign -f "$WORK/att-key" -n setlist-attestation \
    "$d/specs/attest/${num}.json" >/dev/null 2>&1
  mv "$d/specs/attest/${num}.json.sig" "$d/specs/attest/${num}.sig" 2>/dev/null || true
}

att_commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm "attest case" >"$WORK/att-out" 2>&1; }
att_out() { cat "$WORK/att-out" 2>/dev/null; }

if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then

# --- THE OFF DIRECTION, and it goes first ---------------------------------
# UNDECLARED MEANS OFF AND OFF MEANS BYTE-IDENTICAL TO AN INSTANCE THAT NEVER
# HEARD OF THIS. KL4's precedent and its proof method. If this fails, every
# refusal below is a feature that breaks every existing repository.
ATT="$WORK/att-off"; att_fixture "$ATT" off
if att_commit "$ATT"; then
  if att_out | grep -q 'SLH-ATTEST'; then
    bad "attest off: an instance declaring no attestation commits with NO attestation output at all" \
        "it printed an attestation message: off must be silent, not merely permissive"
  else
    ok "attest off: an instance declaring no attestation commits with NO attestation output at all"
  fi
else
  bad "attest off: an instance declaring no attestation commits with NO attestation output at all" \
      "the commit was refused: $(att_out | tr '\n' ' ')"
fi

# --- THE PASS, AND WHAT IT SAYS WHILE PASSING -----------------------------
# THE ASSERTION THIS FEATURE WOULD MOST EASILY SHIP WITHOUT. A pass that does
# not name its custody lets an instance install this, watch its checks go
# green, and believe it has an integrity chain whose strength nobody ever
# established. The failure mode is invisible to every test that asks whether
# signatures verify, and visible in every message.
ATT="$WORK/att-pass"; att_fixture "$ATT" signer; att_sign "$ATT"
if att_commit "$ATT"; then
  if att_out | grep -q 'verified under "signer" custody'; then
    ok "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing"
  else
    bad "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing" \
        "it allowed silently, so a passing chain says nothing about how strong it is: $(att_out | tr '\n' ' ')"
  fi
else
  bad "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing" \
      "a correctly signed approval was refused, which is the false-denial direction: $(att_out | tr '\n' ' ')"
fi

# The same, under the custody that is WEAK BY CONSTRUCTION. This one has to say
# so out loud: a key the build can reach establishes that the run had the key,
# not that a person approved. Asserted on a PASS, which is the only place it
# can be said.
ATT="$WORK/att-pass-ci"; att_fixture "$ATT" ci-secret; att_sign "$ATT"
if att_commit "$ATT" && att_out | grep -q 'A KEY THE BUILD CAN REACH'; then
  ok "attest pass ci-secret: a PASSING verification under a build-reachable key says what it does not prove"
else
  bad "attest pass ci-secret: a PASSING verification under a build-reachable key says what it does not prove" \
      "the green did not state the strength of its own evidence: $(att_out | tr '\n' ' ')"
fi

# --- THE SIX REFUSALS, EACH ASSERTED ON ITS CODE --------------------------
# On the CODE and not on the verdict, for the reason the toolchain probes give:
# these fixtures could be refused for a dozen unrelated reasons and a bare "did
# it refuse" would pass with or without the mechanism.

ATT="$WORK/att-missing"; att_fixture "$ATT" signer
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MISSING'; then
  ok "attest MISSING: role-path work under an ACTIVE spec with no attestation is refused"
else
  bad "attest MISSING: role-path work under an ACTIVE spec with no attestation is refused" "$(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-malformed"; att_fixture "$ATT" signer; att_sign "$ATT"
: > "$ATT/specs/attest/0001.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MALFORMED'; then
  ok "attest MALFORMED: an EMPTY attestation document is refused and is never a pass"
else
  bad "attest MALFORMED: an EMPTY attestation document is refused and is never a pass" "$(att_out | tr '\n' ' ')"
fi

# The unparseable half of the same code, asserted apart from the empty half:
# an empty file and a file of garbage reach the reader by different routes.
ATT="$WORK/att-garbage"; att_fixture "$ATT" signer; att_sign "$ATT"
printf 'this is not json at all\n' > "$ATT/specs/attest/0001.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MALFORMED'; then
  ok "attest MALFORMED b: an UNPARSEABLE attestation document is refused"
else
  bad "attest MALFORMED b: an UNPARSEABLE attestation document is refused" "$(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-unsigned"; att_fixture "$ATT" signer; att_sign "$ATT"
rm -f "$ATT/specs/attest/0001.sig"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNSIGNED'; then
  ok "attest UNSIGNED a: an attestation with no signature is treated exactly as an absent one"
else
  bad "attest UNSIGNED a: an attestation with no signature is treated exactly as an absent one" "$(att_out | tr '\n' ' ')"
fi

# The signature that EXISTS and does not verify: a different route to the same
# refusal, and the one an attacker takes.
ATT="$WORK/att-badsig"; att_fixture "$ATT" signer; att_sign "$ATT"
ssh-keygen -q -t ed25519 -N "" -C other@example.test -f "$WORK/att-other" >/dev/null 2>&1
ssh-keygen -Y sign -f "$WORK/att-other" -n setlist-attestation "$ATT/specs/attest/0001.json" >/dev/null 2>&1
mv "$ATT/specs/attest/0001.json.sig" "$ATT/specs/attest/0001.sig" 2>/dev/null || true
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNSIGNED'; then
  ok "attest UNSIGNED b: a signature by a key that is NOT enrolled does not verify and is refused"
else
  bad "attest UNSIGNED b: a signature by a key that is NOT enrolled does not verify and is refused" "$(att_out | tr '\n' ' ')"
fi

# CO1'S CLASS ONE LEVEL DOWN. Perfectly valid, perfectly signed, and about a
# DIFFERENT spec. A mechanism that checks a claim without checking its SUBJECT
# is checking nothing, and this row exists because the publish gate learned it
# the expensive way.
ATT="$WORK/att-subject"; att_fixture "$ATT" signer
att_sign "$ATT" "specs/0002-other.md" "0001"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-SUBJECT'; then
  ok "attest SUBJECT: a valid, correctly SIGNED attestation naming another spec is refused"
else
  bad "attest SUBJECT: a valid, correctly SIGNED attestation naming another spec is refused" "$(att_out | tr '\n' ' ')"
fi

# THE THREAT ITSELF: a spec edited after approval. The attestation covers the
# approved hash and the current bytes hash to something else.
ATT="$WORK/att-stale"; att_fixture "$ATT" signer; att_sign "$ATT"
# THE EDIT GOES ABOVE THE CLOSING REPORT HEADING, and the first draft of this
# fixture did not: it appended to the END of the file, which is BELOW that
# heading and therefore excluded from the hash by the BL-005 recipe. So this
# case and its control were byte-for-byte the same experiment, and this one
# reported the mechanism broken while the control reported it working. Caught
# by running the pair rather than by reading them, which is the whole argument
# for the control existing.
sed -e 's/^Build the thing\./Build the OTHER thing, edited after approval./' \
    "$ATT/specs/0001-thing.md" > "$ATT/t" && mv "$ATT/t" "$ATT/specs/0001-thing.md"
if ! grep -q 'edited after approval' "$ATT/specs/0001-thing.md"; then
  bad "attest STALE fixture: the drift was applied ABOVE the Closing report heading" \
      "the fixture did not drift, so the assertion below would report on nothing"
fi
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-STALE'; then
  ok "attest STALE: a spec edited AFTER approval refuses the build's commit (the threat this exists for)"
else
  bad "attest STALE: a spec edited AFTER approval refuses the build's commit (the threat this exists for)" "$(att_out | tr '\n' ' ')"
fi

# The control for STALE, and it is not optional: without it the assertion above
# is satisfied by a mechanism that refuses every commit. An edit BELOW the
# Closing report heading is excluded from the hash by the BL-005 recipe, so an
# ordinary build append must NOT read as drift.
ATT="$WORK/att-stale-control"; att_fixture "$ATT" signer; att_sign "$ATT"
printf -- '- an ordinary build append\n' >> "$ATT/specs/0001-thing.md"
if att_commit "$ATT"; then
  ok "attest STALE control: an append BELOW the Closing report heading is not drift and still commits"
else
  bad "attest STALE control: an append BELOW the Closing report heading is not drift and still commits" \
      "the mechanism cries wolf on every honest build, which is how a warning gets switched off in a day: $(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-unverifiable"; att_fixture "$ATT" signer; att_sign "$ATT"
rm -f "$ATT/.claude/approvers.pub"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest UNVERIFIABLE a: an unreadable allowed-signers file refuses, and says the check could not RUN"
else
  bad "attest UNVERIFIABLE a: an unreadable allowed-signers file refuses, and says the check could not RUN" "$(att_out | tr '\n' ' ')"
fi

# A HALF-CONFIGURED CHAIN IS A REFUSAL AND NOT A DEFAULT. Reachable by
# omission is the one way this must not be reachable, because it is the worst
# of the four custody states and the easiest to arrive at by accident.
ATT="$WORK/att-halfconf"; att_fixture "$ATT" signer
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"attestation":{"required":true}}\n' > "$ATT/.claude/sdd.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest UNVERIFIABLE b: required:true with no custody declared is a REFUSAL, never a default"
else
  bad "attest UNVERIFIABLE b: required:true with no custody declared is a REFUSAL, never a default" "$(att_out | tr '\n' ' ')"
fi

# CUSTODY C IS DECLARABLE AND ITS VERIFIER IS AN OPEN QUESTION WITH THE OWNER.
# This assertion pins the HONEST state rather than a mechanism: declaring it
# refuses, saying what it cannot do, which is the design's own doctrine that a
# gate unable to evaluate its predicate denies. It is pinned in its CURRENT
# direction so it cannot close by drift, exactly as KL4-A1's pin is.
ATT="$WORK/att-forge"; att_fixture "$ATT" forge; att_sign "$ATT"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest forge (PINNED, open with the owner): declared custody C refuses rather than passing on an unrun query"
else
  bad "attest forge (PINNED, open with the owner): declared custody C refuses rather than passing on an unrun query" "$(att_out | tr '\n' ' ')"
fi

# --- THE CALLING CONVENTION, ASSERTED STRUCTURALLY ------------------------
# F3-2026's class, closed by construction rather than by vigilance. A verifier
# that prints NOTHING must refuse, and the only honest way to assert that is to
# break the verifier and watch what the caller does.
ATT="$WORK/att-mute"; att_fixture "$ATT" signer; att_sign "$ATT"
# The mute is applied by APPENDING an override rather than by editing the
# definition, which keeps the mutation one line and keeps it obviously the
# thing under test. A redefinition later in the file wins in shell.
printf '\nslh_attest_verify() { return 0; }\n' >> "$ATT/.githooks/setlist-hook-lib.sh"
if ! grep -q 'slh_attest_verify() { return 0; }' "$ATT/.githooks/setlist-hook-lib.sh"; then
  bad "attest convention fixture: the muted verifier was installed" "the mutation did not apply, so the assertion below would test nothing"
fi
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest convention: a verifier that prints NOTHING produces a REFUSAL, not an allow (the F3-2026 class)"
else
  bad "attest convention: a verifier that prints NOTHING produces a REFUSAL, not an allow (the F3-2026 class)" \
      "an empty verifier result reached the allow branch, which is the empty-result-as-verdict class this convention exists to remove: $(att_out | tr '\n' ' ')"
fi

else
  # NOT SILENTLY SKIPPED. A dependency that cannot run is reported, never
  # quietly passed over, which is this project's own rule about its own checks.
  bad "attest: ssh-keygen is required to exercise the integrity chain and is not usable here" \
      "the attestation assertions did not run, so this tree carries NO evidence about the KL3 mechanism"
fi

# A9: ONE VERIFIER, and the count is pinned rather than reviewed. The advisory
# layer gets one honest sentence and no reader of its own, which is the
# 2026-08-28 ruling; a second definition arriving anywhere is what this catches.
ATT_DEFS="$(grep -rl 'slh_attest_verify() {' "$ROOT/templates" "$ROOT/scripts" 2>/dev/null | grep -c . || true)"
if [[ "$ATT_DEFS" == "1" ]]; then
  ok "attest A9: exactly ONE file defines slh_attest_verify, and it is the git-hook library"
else
  bad "attest A9: exactly ONE file defines slh_attest_verify, and it is the git-hook library" \
      "found $ATT_DEFS definitions; one rule with two readers is how the two drift apart"
fi
if grep -q 'slh_attest_verify() {' "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; then
  ok "attest A9b: the one definition lives in templates/git-hooks/setlist-hook-lib.sh"
else
  bad "attest A9b: the one definition lives in templates/git-hooks/setlist-hook-lib.sh" "it moved out of the only layer that can refuse"
fi

# THE THREE-WAY HASH LOCKSTEP. The recipe now has THREE implementations in
# deliberate behavioural lockstep, and the count is pinned so a fourth cannot
# arrive unasserted. Both cheaper routes are foreclosed: a shared recipe file
# across the two hook trees is the cross-tree dependency the 2026-08-28 ruling
# refused, and shelling out to scripts/spec-hash.sh breaks the stamped-hook
# independence the inline copy exists to preserve. This is the price, it was
# named in the design before the work started, and it is not optional.
ATT_LOCK_OK=1
ATT_LOCK_N=0
for shl_case in "plain body" "body with - Spec-hash: decoy inside it" "body
spanning
several lines"; do
  SHL="$WORK/attest-lock"; sh_fixture "$SHL" ACTIVE no "$shl_case"
  A_SCRIPT="$(bash "$ROOT/scripts/spec-hash.sh" "$SHL/specs/0001-thing.md")"
  A_INLINE="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' "$SHL/specs/0001-thing.md" \
    | grep -v '^[-*+[:space:]]*Spec-hash:' | sha256sum | cut -d' ' -f1)"
  A_HOOK="$(bash -c '. "$1" >/dev/null 2>&1; slh_attest_spec_hash "$2"' _ \
    "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SHL/specs/0001-thing.md" 2>/dev/null)"
  ATT_LOCK_N=$((ATT_LOCK_N + 1))
  [[ "$A_SCRIPT" == "$A_INLINE" && "$A_SCRIPT" == "$A_HOOK" && -n "$A_SCRIPT" ]] || ATT_LOCK_OK=0
done
# A8: the size of what is compared is asserted before the comparison is
# believed. A lockstep over zero fixtures agrees with itself perfectly.
if [[ "$ATT_LOCK_N" -eq 3 && "$ATT_LOCK_OK" -eq 1 ]]; then
  ok "spec-hash lockstep (THREE implementations): script, regrounding hook and git-hook verifier agree on every corpus shape"
else
  bad "spec-hash lockstep (THREE implementations): script, regrounding hook and git-hook verifier agree on every corpus shape" \
      "$ATT_LOCK_N of 3 shapes compared, agreement=$ATT_LOCK_OK; three copies of one recipe that disagree is how a checker and its writer drift apart"
fi

# The count itself, pinned. Three is a decision with a price attached; a fourth
# copy arriving without this assertion being changed is the thing to catch.
# THE MARKER IS THE FIELD EXCLUSION, not the awk range, and that is a
# correction this assertion made to itself on its first run. The range is
# spelled on one line in the two hooks and across three lines in
# scripts/spec-hash.sh, so a pattern matching the compact form found 2 of 3 and
# would have reported a missing implementation as a missing copy. The `grep -v`
# that removes the Spec-hash field line is byte-identical in all three, which
# is the right marker because it is the exclusion the recipe cannot work
# without.
ATT_HASH_RE='^[-*+[:space:]]*Spec-hash:'
ATT_HASH_COPIES="$(grep -lF "$ATT_HASH_RE" \
  "$ROOT/scripts/spec-hash.sh" "$ROOT/templates/hooks/regrounding-hook.sh" \
  "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | grep -c . || true)"
ATT_HASH_ALL="$(grep -rlF "$ATT_HASH_RE" "$ROOT/scripts" "$ROOT/templates" 2>/dev/null | grep -c . || true)"
if [[ "$ATT_HASH_COPIES" == "3" && "$ATT_HASH_ALL" == "3" ]]; then
  ok "spec-hash lockstep count: the recipe has exactly THREE implementations, all three under lockstep"
else
  bad "spec-hash lockstep count: the recipe has exactly THREE implementations, all three under lockstep" \
      "expected 3 named and 3 total, found $ATT_HASH_COPIES named and $ATT_HASH_ALL total; a fourth copy is a fourth thing that can drift"
fi

# --- THE PUSH LAYER'S ARM ---------------------------------------------------
# The guarantee, per the enforcement boundary: a commit that never met
# pre-commit (--no-verify, an unset core.hooksPath, the per-clone gap) is
# caught before the work is SHARED. Every fixture below builds its history
# with the hooks bypassed, which is the only honest way to reach this layer:
# a fixture whose commits went through pre-commit is testing pre-commit twice.
att_push_fixture() { # att_push_fixture <dir> <custody|off>
  local d="$1" custody="$2"
  att_fixture "$d" "$custody"
  # THE ROLE-PATH WORK IS COMMITTED ON THE SPEC BRANCH AND NEVER ON main, and
  # the ordering here is a correction rather than a preference. The first cut
  # committed the staged work before branching, so main carried feature code
  # that arrived through no closed spec, and the TRUNK AUDIT refused every
  # push in this block: the control, the docs-only case and the off case all
  # went red against bytes that have no approval arm at all. A refusal for the
  # wrong reason is indistinguishable from the refusal under test, and it was
  # the CONTROL going red on the pre-feature tree that said so.
  # `git checkout -b` carries the index across, so the work follows the branch.
  mkdir -p "$d/.claude/hooks"
  cp "$ROOT/templates/git-hooks/pre-push" "$d/.githooks/pre-push"
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push"
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # The remote is SEEDED so it is not empty: on an empty remote every pushed
  # ref is a trunk candidate and is audited, so these cases would be refused
  # for a reason that has nothing to do with approval. The fixture models the
  # real scenario rather than the convenient one.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "work, hooks bypassed" >/dev/null 2>&1
  # THE PREMISE THIS BLOCK RESTS ON, asserted per fixture rather than once:
  # main must carry NO role-path content, or the trunk audit refuses every
  # push here for a reason that is not approval.
  if git -C "$d" ls-tree -r --name-only main 2>/dev/null | grep -q "^src/"; then
    bad "attest push fixture: main carries no role-path content ($d)" \
        "the trunk audit will refuse every push in this block for a reason that is not approval"
  fi
}
att_push() { git -C "$1" push -q origin spec/0001-thing >"$WORK/att-push-out" 2>&1; }
att_push_out() { cat "$WORK/att-push-out" 2>/dev/null; }
# The work commit is made on the spec branch with hooks bypassed, so the range
# this push publishes carries role-path content that pre-commit never saw.
att_push_work() { # att_push_work <dir>
  printf 'more work\n' > "$1/src/MORE.txt"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c core.hooksPath=/dev/null commit -qm "unapproved build, hooks bypassed" >/dev/null 2>&1
}

if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then

# THE FIXTURE'S OWN PREMISE, ASSERTED BEFORE ANY CASE RUNS. If the work commit
# did not land, or landed with role-path content the range does not carry,
# every refusal below passes while testing nothing. The opener of this cycle
# shipped exactly that defect twice in one sitting, so the premise is checked
# rather than assumed.
ATTP="$WORK/attp-premise"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
att_push_work "$ATTP"
ATTP_RANGE="$(git -C "$ATTP" rev-list origin/main..spec/0001-thing 2>/dev/null | grep -c . || true)"
ATTP_ROLE="$(git -C "$ATTP" show --name-only --format= spec/0001-thing 2>/dev/null | grep -c '^src/' || true)"
if [[ "$ATTP_RANGE" -ge 1 && "$ATTP_ROLE" -ge 1 ]]; then
  ok "attest push fixture: the range carries $ATTP_RANGE commit(s) and role-path content, so the arm has something to judge"
else
  bad "attest push fixture: the range carries $ATTP_RANGE commit(s) and role-path content, so the arm has something to judge" \
      "range=$ATTP_RANGE role-files=$ATTP_ROLE; every push case below would pass while testing nothing"
fi

# THE CONTROL FIRST, because every refusal below is worthless without it: an
# approved branch whose spec has not drifted must still PUSH.
if att_push "$ATTP"; then
  ok "attest push control: an APPROVED branch whose spec has not drifted still pushes"
else
  bad "attest push control: an APPROVED branch whose spec has not drifted still pushes" \
      "the arm refuses compliant work, which is the false-denial direction and makes every case below meaningless: $(att_push_out | tr '\n' ' ')"
fi

# THE CASE THE LAYER EXISTS FOR: a build that never met pre-commit. Not a
# contrived route, and named in Known limitations as a documented hole at
# commit time precisely because THIS layer is what covers it.
ATTP="$WORK/attp-missing"; att_push_fixture "$ATTP" signer
att_push_work "$ATTP"
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-MISSING'; then
  ok "attest push MISSING: an unapproved build that bypassed pre-commit is refused BEFORE it is shared"
else
  bad "attest push MISSING: an unapproved build that bypassed pre-commit is refused BEFORE it is shared" "$(att_push_out | tr '\n' ' ')"
fi

# THE READING THAT DECIDES THE WHOLE ARM: the spec is drifted ONLY IN THE
# PUSHED TREE and is clean on disk. A verifier that hashed the working copy
# would pass this, and it would pass it for exactly the push it exists to stop.
ATTP="$WORK/attp-tree"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
sed -e 's/^Build the thing\./Build the OTHER thing, drifted in the pushed commit only./' \
    "$ATTP/specs/0001-thing.md" > "$ATTP/t" && mv "$ATTP/t" "$ATTP/specs/0001-thing.md"
printf 'more work\n' > "$ATTP/src/MORE.txt"
git -C "$ATTP" add -A >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "drift, hooks bypassed" >/dev/null 2>&1
# Now put the WORKING COPY back to the approved bytes. The tree being pushed
# still carries the drift; the filesystem does not.
git -C "$ATTP" show "HEAD~1:specs/0001-thing.md" > "$ATTP/specs/0001-thing.md"
ATTP_DISK="$(bash "$ROOT/scripts/spec-hash.sh" "$ATTP/specs/0001-thing.md")"
ATTP_DOC="$(jq -r .spec_hash "$ATTP/specs/attest/0001.json" 2>/dev/null)"
if [[ "$ATTP_DISK" == "$ATTP_DOC" ]]; then
  ok "attest push tree fixture: the working copy MATCHES the approval, so only the pushed tree is drifted"
else
  bad "attest push tree fixture: the working copy MATCHES the approval, so only the pushed tree is drifted" \
      "disk=$ATTP_DISK doc=$ATTP_DOC; the case below would not distinguish a tree reader from a disk reader"
fi
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-STALE'; then
  ok "attest push STALE: a spec drifted ONLY in the pushed tree is refused, so the arm reads the tree and not the disk"
else
  bad "attest push STALE: a spec drifted ONLY in the pushed tree is refused, so the arm reads the tree and not the disk" \
      "a clean working copy satisfied a check about bytes nobody is publishing: $(att_push_out | tr '\n' ' ')"
fi

# A DOCS-ONLY PUSH CARRIES NO BUILD TO APPROVE. Without this the mechanism is a
# toll on every commit rather than a gate on building, which is the direction
# that gets a gate switched off.
ATTP="$WORK/attp-docs"; att_push_fixture "$ATTP" signer
# THE BRANCH IS RESET TO THE TRUNK FIRST, because att_push_fixture lands the
# role-path work commit on it and a "docs-only" branch that carries a build is
# not the case under test. Found by running it: the assertion went red against
# the finished arm, and the arm was right. The range has to be docs-only for
# the words to mean anything.
git -C "$ATTP" reset -q --hard origin/main
printf 'notes\n' > "$ATTP/NOTES.md"
git -C "$ATTP" add -A >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "docs only" >/dev/null 2>&1
ATTP_DOCS_ROLE="$(git -C "$ATTP" diff --name-only origin/main..HEAD 2>/dev/null | grep -c '^src/' || true)"
if [[ "$ATTP_DOCS_ROLE" != "0" ]]; then
  bad "attest push docs fixture: the range carries NO role-path content" \
      "found $ATTP_DOCS_ROLE role-path file(s), so this is not the docs-only case it claims to be"
fi
if att_push "$ATTP"; then
  ok "attest push scope: a push carrying NO role-path content needs no approval and is allowed"
else
  bad "attest push scope: a push carrying NO role-path content needs no approval and is allowed" \
      "a docs-only push was refused, which makes this a toll on every commit rather than a gate on building: $(att_push_out | tr '\n' ' ')"
fi

# OFF IS OFF AT THIS LAYER TOO, and it is asserted here rather than inferred
# from the commit layer: two layers, two readers of the same declaration.
ATTP="$WORK/attp-push-off"; att_push_fixture "$ATTP" off
att_push_work "$ATTP"
if att_push "$ATTP" && ! att_push_out | grep -q 'SLH-ATTEST'; then
  ok "attest push off: an instance declaring no attestation pushes with NO attestation output at all"
else
  bad "attest push off: an instance declaring no attestation pushes with NO attestation output at all" "$(att_push_out | tr '\n' ' ')"
fi

# THE ALLOWED-SIGNERS FILE IS READ FROM THE PUSHED TREE TOO. Enrolment is a
# commit, so judging a push against whatever this clone has checked out would
# let a key removed in the pushed range still verify, or refuse a key the push
# itself enrols. Asserted in the direction that publishes.
ATTP="$WORK/attp-enrol"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
git -C "$ATTP" rm -q --cached .claude/approvers.pub >/dev/null 2>&1
printf 'more work\n' > "$ATTP/src/MORE.txt"
git -C "$ATTP" add src >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "drop the enrolled key from the tree" >/dev/null 2>&1
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest push enrolment: the allowed-signers file is read from the PUSHED tree, so a push that drops it cannot verify"
else
  bad "attest push enrolment: the allowed-signers file is read from the PUSHED tree, so a push that drops it cannot verify" \
      "the check used this clone's checked-out keys to judge a tree that does not contain them: $(att_push_out | tr '\n' ' ')"
fi

fi

# THE HELPER AND THE VERIFIER, ROUND TRIP. The writer and the checker are
# different programs in different trees, and "they agree" is the claim that
# matters and the one nothing else here makes: every other assertion builds its
# attestation with the test's own signing code, which proves the VERIFIER works
# and says nothing about what /setlist:checkpoint actually writes. This drives
# scripts/spec-attest.sh and then asks the git-hook library's verifier.
if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then
  ATTH="$WORK/attest-helper"; att_fixture "$ATTH" signer
  ssh-keygen -q -t ed25519 -N "" -C helper@example.test -f "$WORK/att-helper-key" >/dev/null 2>&1
  printf 'helper@example.test %s\n' "$(cat "$WORK/att-helper-key.pub")" > "$ATTH/.claude/approvers.pub"
  ( cd "$ATTH" && bash "$ROOT/scripts/spec-attest.sh" specs/0001-thing.md \
      --key "$WORK/att-helper-key" --approver helper@example.test ) >"$WORK/att-helper.out" 2>&1
  ATTH_TOK="$(bash -c '. "$1" >/dev/null 2>&1; slh_attest_load "$2" >/dev/null 2>&1; slh_attest_verify "$2" "specs/0001-thing.md"' \
      _ "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ATTH" 2>/dev/null)"
  if [[ -f "$ATTH/specs/attest/0001.json" && -f "$ATTH/specs/attest/0001.sig" && "$ATTH_TOK" == "VERIFIED" ]]; then
    ok "attest round trip: what scripts/spec-attest.sh WRITES is what the git-hook verifier ACCEPTS"
  else
    bad "attest round trip: what scripts/spec-attest.sh WRITES is what the git-hook verifier ACCEPTS" \
        "token=[$ATTH_TOK]; the writer and the checker disagree, which is the one defect no single-sided test can see: $(head -3 "$WORK/att-helper.out" | tr '\n' ' ')"
  fi

  # THE HELPER REFUSES TO WRITE WHAT NOTHING WILL ACCEPT. Under the custody
  # ruled designed-and-not-built, a signed document would be a file that looks
  # like an approval and is refused at every layer, which is worse than an
  # error message because it looks done.
  ATTH2="$WORK/attest-helper-forge"; att_fixture "$ATTH2" forge
  ( cd "$ATTH2" && bash "$ROOT/scripts/spec-attest.sh" specs/0001-thing.md \
      --key "$WORK/att-helper-key" --approver helper@example.test ) >"$WORK/att-helper2.out" 2>&1
  if [[ ! -f "$ATTH2/specs/attest/0001.json" ]] && grep -q 'DESIGNED AND NOT BUILT' "$WORK/att-helper2.out"; then
    ok "attest helper: under forge custody it writes NOTHING and says why, rather than signing an unacceptable document"
  else
    bad "attest helper: under forge custody it writes NOTHING and says why, rather than signing an unacceptable document" \
        "$(head -3 "$WORK/att-helper2.out" | tr '\n' ' ')"
  fi
fi

# F1-2026, FIXED FOR DECLARING CLOSES AND PINNED AS A BOUNDARY FOR THE REST
# (2.3.0 leg F1; the RP1 ownership arm, spec 0126, design section 8.2).
#
# The old pin asserted the hole as it was: the NPAR<2 arm's LIN_CLOSED_OK
# short-circuited the role-path question for the ENTIRE commit on one
# compliant row flip. The 2026-08-29 ruling deferred the narrow fix because
# it was MEASURED not to discriminate: an honest squash close and the attack
# are one spec file plus one role-path file each, neither in any parent.
# Separating them needed a recorded fact the framework did not keep. It keeps
# it now: `Owns:` lines in the spec's hashed range, and the arm asks per-file
# coverage against the declared set instead of exempting the commit.
#
# THE PIN FLIPPED RED IN THIS COMMIT, exactly as the old pin's own failure
# message demanded, and is REWRITTEN here rather than deleted: the DECLARING
# attack (below) audited "1 clean, 0 violations" on the pre-fix bytes,
# watched, and now refuses on the smuggled file BY NAME. What remains pinned
# in the old direction is the BOUNDARY: a close that declares NOTHING keeps
# today's whole-commit exemption exactly (the Spec-hash absence precedent;
# anything else re-refuses the compliant legacy squash close spec 0121's F4
# fix exists to permit), and the public bullet is REPLACED by the boundary
# sentence that SAYS so, never deleted.
F1P="$WORK/f1-pin"; rm -rf "$F1P"; mkdir -p "$F1P/src" "$F1P/specs" "$F1P/.claude"
git_init "$F1P"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$F1P/.claude/sdd.json"
printf '{"setlist_status":1,"specs":{"0004":{"status":"active"},"0005":{"status":"active"}},"chores":{}}\n' > "$F1P/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0004 | wip | ACTIVE | in progress |\n| 0005 | docs | ACTIVE | in progress |\n' > "$F1P/specs/STATUS.md"
printf 'base\n' > "$F1P/base.txt"
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm seed >/dev/null 2>&1
F1P_BASE="$(git -C "$F1P" rev-parse HEAD)"
git -C "$F1P" checkout -q -b spec/0004-wip
printf 'work in progress; 0004 is still ACTIVE\n' > "$F1P/src/wip.txt"
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm 'wip on 0004' >/dev/null 2>&1
git -C "$F1P" checkout -q main
# The DECLARING close of 0005: it owns src/feat.txt and says so, closes with
# its recorded facts, and smuggles still-active 0004's file beside its own.
printf '# Spec 0005\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\nsmoke: PASS\n```\n' > "$F1P/specs/0005-docs.md"
printf 'the declared file\n' > "$F1P/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0004":{"status":"active"},"0005":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$F1P/.claude/status.json"
sed -e 's/| 0005 | docs | ACTIVE | in progress |/| 0005 | docs | CLOSED | done |/' "$F1P/specs/STATUS.md" > "$F1P/t" && mv "$F1P/t" "$F1P/specs/STATUS.md"
git -C "$F1P" checkout spec/0004-wip -- src/wip.txt 2>/dev/null
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm 'close spec 0005' >/dev/null 2>&1
F1P_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1P" --since "$F1P_BASE" 2>&1)"
# THE NEGATIVE CONTROL FIRST: the same injected file with NO close at all must
# be refused. Without it this pin passes against an audit that refuses nothing.
F1C="$WORK/f1-ctl"; rm -rf "$F1C"; cp -R "$F1P" "$F1C"
git -C "$F1C" reset -q --hard HEAD~1
git -C "$F1C" checkout spec/0004-wip -- src/wip.txt 2>/dev/null
git -C "$F1C" add -A >/dev/null 2>&1; git -C "$F1C" commit -qm 'no close, same file' >/dev/null 2>&1
F1C_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1C" --since "$F1P_BASE" 2>&1)"
if printf '%s' "$F1C_OUT" | grep -q 'VIOLATION'; then
  ok "F1-2026 control: the same injected file WITHOUT a close is still refused"
else
  bad "F1-2026 control: the same injected file WITHOUT a close is still refused" \
      "the audit refuses nothing here, so the pin below would pass against a dead check"
fi
if printf '%s' "$F1P_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/wip.txt'; then
  ok "F1-2026 (FIXED for declaring closes): the attack refuses ON SHAPE, naming the smuggled file, because still-active 0004's file is not in closing 0005's declared set"
else
  bad "F1-2026 (FIXED for declaring closes): the attack refuses ON SHAPE, naming the smuggled file, because still-active 0004's file is not in closing 0005's declared set" \
      "audit said: $(printf '%s' "$F1P_OUT" | tail -2 | tr '\n' ' ')"
fi
# The declared file itself is NOT named: the refusal is per file, not per
# commit, or the fix would be the old exemption inverted.
if printf '%s' "$F1P_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/feat.txt'; then
  bad "F1-2026 per-file: the declared file is covered; only the smuggled one refuses" \
      "src/feat.txt was refused despite being declared, so coverage is not being read per file"
else
  ok "F1-2026 per-file: the declared file is covered; only the smuggled one refuses"
fi

# THE BOUNDARY, PINNED IN ITS DISCLOSED DIRECTION so it cannot close by
# drift: a close that declares NOTHING (this legacy-shaped instance has no
# record and no Owns) keeps the whole-commit exemption EXACTLY, and the
# public boundary sentence says so. If someone widens or closes this, the
# sentence moves in the same commit.
F1L="$WORK/f1-legacy"; rm -rf "$F1L"; mkdir -p "$F1L/src" "$F1L/specs" "$F1L/.claude"
git_init "$F1L"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$F1L/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0004 | wip | ACTIVE | in progress |\n| 0005 | docs | ACTIVE | in progress |\n' > "$F1L/specs/STATUS.md"
printf 'base\n' > "$F1L/base.txt"
git -C "$F1L" add -A >/dev/null 2>&1; git -C "$F1L" commit -qm seed >/dev/null 2>&1
F1L_BASE="$(git -C "$F1L" rev-parse HEAD)"
printf '# Spec 0005\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\nsmoke: PASS\n```\n' > "$F1L/specs/0005-docs.md"
sed -e 's/| 0005 | docs | ACTIVE | in progress |/| 0005 | docs | CLOSED | done |/' "$F1L/specs/STATUS.md" > "$F1L/t" && mv "$F1L/t" "$F1L/specs/STATUS.md"
printf 'undeclared ride\n' > "$F1L/src/wip.txt"
git -C "$F1L" add -A >/dev/null 2>&1; git -C "$F1L" commit -qm 'close spec 0005' >/dev/null 2>&1
F1L_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1L" --since "$F1L_BASE" 2>&1)"
if printf '%s' "$F1L_OUT" | grep -q '0 violations'; then
  ok "F1-2026 boundary (PINNED, disclosed): a close declaring NOTHING keeps the whole-commit exemption exactly, as the boundary sentence says"
else
  bad "F1-2026 boundary (PINNED, disclosed): a close declaring NOTHING keeps the whole-commit exemption exactly, as the boundary sentence says" \
      "the non-declaring exemption changed; behaviour 4 of the ratified design says it must not, and the public sentence must move with any deliberate change here"
fi

# F2-2026 (leg F4, scaffolded evaluated as a boolean) IS FIXED HERE, and this
# block is the PIN REWRITTEN in the fix's own commit rather than deleted.
#
# What it pinned, in its previous direction: a non-boolean `scaffolded` stood
# the whole trunk-write gate down in SILENCE, having evaluated nothing. The pin
# asserted that hole so it could not close by drift, and it went red against
# these bytes exactly as it was built to.
#
# WHY THE FIX EXISTS NOW AND DID NOT AT 2.3.0, because it is not that anyone
# changed their mind. Two standing rules point opposite ways at fix-round size:
#
#   A2's trigger says a NEW deny code is a changed QUESTION and costs a full
#   leg. The publish-time attestation gate refused the 2.3.0 round for exactly
#   that when the fix raised SH-SCAFFOLDED-SHAPE.
#
#   The suite says two denials sharing a code cannot be told apart. Re-scoping
#   onto the existing SH-SDD-SHAPE to dodge the trigger tripped THAT instead.
#
# The entry priced the way out in advance: the cycle that takes it either owes
# a leg anyway, or needs a distinguishable code that does not already mean
# something else. The 2.4.0 cycle owes a leg BY COMPUTATION before its first
# byte, because the status record's deny codes change the guarantee-check
# identifier set. So the new identifiers cost nothing extra, and the fix ships
# with the identifiers it wanted rather than with the shared-code workaround.
#
# FOUR DIRECTIONS, because three of them are the ones a narrower fix breaks.
SCFP="$WORK/scaffold-pin"; rm -rf "$SCFP"; mkdir -p "$SCFP/src" "$SCFP/specs" "$SCFP/.claude"
git_init "$SCFP"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCFP/specs/STATUS.md"
SCFP_PAY="$(jq -nc --arg p "$SCFP/src/x.js" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
if printf '%s' "$HOOK_OUT" | grep -q 'SH-TRUNK-WRITE'; then
  ok "scaffolded control: a boolean true arms the trunk-write gate"
else
  bad "scaffolded control: a boolean true arms the trunk-write gate" "the gate is dead, so the assertions below would prove nothing"
fi

# The fix, asserted on the CODE and across every non-boolean shape the leg
# measured, not just the string it happened to reproduce with.
SCFP_SHAPE_MISS=""
for SCFP_V in '"yes"' '1' '{}' '[]' '"true"'; do
  printf '{"trunk":"main","scaffolded":%s,"roles":{"src":"src","tests":"tests"}}\n' "$SCFP_V" > "$SCFP/.claude/sdd.json"
  run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
  printf '%s' "$HOOK_OUT" | grep -q 'SH-SCAFFOLDED-SHAPE' || SCFP_SHAPE_MISS="$SCFP_SHAPE_MISS $SCFP_V"
done
if [[ -z "$SCFP_SHAPE_MISS" ]]; then
  ok "F2-2026 (FIXED): every present non-boolean scaffolded refuses with SH-SCAFFOLDED-SHAPE instead of standing the gate down in silence"
else
  bad "F2-2026 (FIXED): every present non-boolean scaffolded refuses with SH-SCAFFOLDED-SHAPE instead of standing the gate down in silence" \
      "these values still silenced the gate:$SCFP_SHAPE_MISS"
fi

# THE HONEST ZERO IS THE HALF A FIX BREAKS. Absent and boolean false must stay
# SILENTLY off: that is what every pre-scaffold instance depends on, and turning
# it into a refusal would refuse the one-time bootstrap this line exists to
# permit. Asserted on emptiness, because "allow is silence" here.
SCFP_ZERO_MISS=""
printf '{"trunk":"main","scaffolded":false,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
[[ -z "$HOOK_OUT" ]] || SCFP_ZERO_MISS="$SCFP_ZERO_MISS false"
printf '{"trunk":"main","roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
[[ -z "$HOOK_OUT" ]] || SCFP_ZERO_MISS="$SCFP_ZERO_MISS absent"
if [[ -z "$SCFP_ZERO_MISS" ]]; then
  ok "F2-2026 control: boolean false and an absent flag are still SILENTLY off, so the bootstrap this line permits is not refused"
else
  bad "F2-2026 control: boolean false and an absent flag are still SILENTLY off, so the bootstrap this line permits is not refused" \
      "the honest zero now warns for:$SCFP_ZERO_MISS; a fix that refuses the pre-scaffold state has broken the case it exists to allow"
fi

# F11-2026, THE THIRD EMITTER, and the reason this assertion exists at all.
#
# The entry was DISCHARGED 2026-08-29 naming an assertion as what makes a fourth
# rediscovery impossible rather than unlikely. The discharge was one emitter
# short: advise_literal() gained the code extraction in commit-gate.sh and
# close-gate.sh, THIS gate kept "code":"", and the assertion that was supposed
# to make the class permanent reads commit-gate.sh alone. So the record said the
# class was closed while a third of it was open, and nothing could notice.
#
# That is the entry's own A9 diagnosis, a rule that exists in some of its places
# and not all, surviving its own discharge note. The fix is one line; the reason
# it is worth a comment is that the DISCHARGE was the defect, not the code.
#
# The literal path is reached with jq ABSENT, which is what that path is for.
printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook_nojq "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
SCFP_CODE="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.code // "<absent>"' 2>/dev/null)"
if [[ -n "$SCFP_CODE" && "$SCFP_CODE" != "<absent>" && "$SCFP_CODE" =~ ^[A-Z][A-Z0-9-]*$ ]]; then
  ok "F11-2026 third emitter: the scope hook's literal-reason deny carries a real setlistAdvisory.code ($SCFP_CODE), not the empty string"
else
  bad "F11-2026 third emitter: the scope hook's literal-reason deny carries a real setlistAdvisory.code, not the empty string" \
      "code=[$SCFP_CODE]; two of the three emitters were fixed in 2.3.0 and the entry recorded the whole class as discharged"
fi

# THE HEADER STRIP IS POSITIONAL, NOT SHAPED (2.3.0 leg, F3 and F5).
#
# A unified diff prefixes every added line with one `+`, so an added line whose
# CONTENT begins `++ b/` arrives as `+++ b/...` and is indistinguishable by
# SHAPE from the diff's own file header. The strip was anchored to the header's
# shape, so it ate the content: a secret on such a line passed both the
# guarantee layer and the advisory gate at rc=0, silently.
#
# The rule that fixes it is positional and it is git's own: a `+++` line is a
# HEADER only outside a hunk. Once `@@` has been seen, every `+` line is
# content, whatever it looks like. The scoped scan already worked this way,
# which is why this defect lived only in the unscoped branch and in the
# advisory gate's private copy.
#
# Asserted on the CODE at the git-hook layer and on the DENIAL at the advisory
# layer, with a clean twin at each so the fix cannot pass by refusing
# everything.
SCANHDR="$WORK/scan-hdr"; rm -rf "$SCANHDR"; mkdir -p "$SCANHDR/src" "$SCANHDR/specs" "$SCANHDR/.claude" "$SCANHDR/.githooks"
git_init "$SCANHDR"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SCANHDR/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCANHDR/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SCANHDR/.githooks/"
chmod +x "$SCANHDR/.githooks/pre-commit"
printf 'seed\n' > "$SCANHDR/seed.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
git -C "$SCANHDR" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
git -C "$SCANHDR" config core.hooksPath .githooks

# The payload: a secret on a line whose content begins `++ b/`.
printf '++ b/decoy\nconst t = "ghp_abcdefghijklmnop1234"\n' > "$SCANHDR/src/evil.txt"
# Put the secret ON the `++ b/` line itself, which is the exact shape.
printf '++ b/x api_key = "abcdefghijklmnop1234"\n' > "$SCANHDR/src/evil.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
if git -C "$SCANHDR" commit -qm "header-shaped secret" >"$WORK/scanhdr.out" 2>&1; then
  bad "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer" \
      "it committed clean: the header strip ate the content line, so the scan read nothing and reported nothing"
else
  if grep -q 'SLH-SECRET' "$WORK/scanhdr.out"; then
    ok "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer"
  else
    bad "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/scanhdr.out")"
  fi
fi
# THE CLEAN TWIN: an ordinary `++ b/` line with no secret must still commit, so
# the fix is a scan and not a ban on a spelling.
git -C "$SCANHDR" reset -q HEAD -- . 2>/dev/null
printf '++ b/x just an ordinary line\n' > "$SCANHDR/src/evil.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
if git -C "$SCANHDR" commit -qm "header-shaped clean" >"$WORK/scanhdr2.out" 2>&1; then
  ok "scan header F3 twin: an ordinary line beginning '++ b/' still commits, so the fix scans rather than bans"
else
  bad "scan header F3 twin: an ordinary line beginning '++ b/' still commits, so the fix scans rather than bans" \
      "$(tr '\n' ' ' < "$WORK/scanhdr2.out")"
fi

# THE ADVISORY LAYER'S OWN COPY (leg F5), asserted on its code.
SCANHDR2="$WORK/scan-hdr-adv"; rm -rf "$SCANHDR2"; mkdir -p "$SCANHDR2/src" "$SCANHDR2/specs" "$SCANHDR2/.claude"
git_init "$SCANHDR2"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SCANHDR2/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCANHDR2/specs/STATUS.md"
printf 'seed\n' > "$SCANHDR2/seed.txt"
git -C "$SCANHDR2" add -A >/dev/null 2>&1; git -C "$SCANHDR2" commit -qm seed >/dev/null 2>&1
printf '++ b/x api_key = "abcdefghijklmnop1234"\n' > "$SCANHDR2/src/evil.txt"
git -C "$SCANHDR2" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$SCANHDR2" "$(bash_payload 'git commit -m x')"
expect_deny "scan header F5: the advisory gate names a secret on an added line beginning '++ b/'" "CM-SECRET"

# THE BLOB-PINNED DIFFERENTIAL: off is byte-identical, PROVEN rather than said.
#
# The KL3 banner claims that an instance declaring no attestation behaves
# exactly as one that never heard of the feature. That claim was NARROWED when
# the claims sweep flagged it, because what the suite proved was only the
# behavioural half (the off path emits nothing and commits). This is the other
# half, and it is KL4's method: pin the PRE-FEATURE hook blobs, run both
# generations over the same cases, and compare stdout, stderr and exit code
# byte for byte. Absence proven identical rather than asserted.
#
# A8: the case count is asserted before the agreement is believed. Two
# generations that were never run over anything agree perfectly.
DIFFPRE="$ROOT/test/fixtures/pre-attest-hooks"
if [[ ! -d "$DIFFPRE" ]]; then
  ok "attest differential: SKIPPED, the pre-feature hook blobs are not present in this tree (export copy)"
else
  DIFFD="$WORK/attest-diff"; rm -rf "$DIFFD"; mkdir -p "$DIFFD"
  DIFF_N=0; DIFF_BAD=""
  for diff_case in clean emdash secret lifecycle; do
    for diff_gen in pre now; do
      d="$DIFFD/$diff_case-$diff_gen"
      rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
      git_init "$d"
      # NO attestation block at all: this is custody D, the honest zero.
      printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
      printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
      printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
      if [[ "$diff_gen" == "pre" ]]; then
        cp "$DIFFPRE/pre-commit" "$DIFFPRE/setlist-hook-lib.sh" "$d/.githooks/"
      else
        cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
      fi
      chmod +x "$d/.githooks/pre-commit"
      printf 'seed\n' > "$d/seed.txt"
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
      git -C "$d" config core.hooksPath .githooks
      case "$diff_case" in
        clean)     printf 'ordinary work\n' > "$d/src/app.js" ;;
        emdash)    printf 'a %s b\n' "$EMDASH" > "$d/src/app.js" ;;
        secret)    printf 'const token = "ghp_abcdefghijklmnop1234"\n' > "$d/src/app.js" ;;
        lifecycle) printf 'work\n' > "$d/src/app.js"; printf '# Spec 0001\n\nStatus: BUILT\n' > "$d/specs/0001-thing.md" ;;
      esac
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" commit -qm "case $diff_case" >"$DIFFD/$diff_case-$diff_gen.out" 2>&1
      printf 'exit=%s\n' "$?" >> "$DIFFD/$diff_case-$diff_gen.out"
    done
    DIFF_N=$((DIFF_N + 1))
    if ! cmp -s "$DIFFD/$diff_case-pre.out" "$DIFFD/$diff_case-now.out"; then
      DIFF_BAD="$DIFF_BAD $diff_case"
    fi
  done
  if [[ "$DIFF_N" -eq 4 && -z "$DIFF_BAD" ]]; then
    ok "attest differential: with NO attestation declared, all 4 cases are byte-identical between the pre-feature and current hooks"
  else
    bad "attest differential: with NO attestation declared, all 4 cases are byte-identical between the pre-feature and current hooks" \
        "$DIFF_N of 4 cases compared, differing:${DIFF_BAD:- none}; off must mean off, and this is the half a behavioural assertion cannot reach"
  fi
fi

# CO1: THE CITED LEG MUST BE A LEG OF THIS RELEASE, asserted at last.
#
# The refusal itself was bought by the owner ruling of 2026-08-21 and has been
# in the shipped bytes since. What was missing is this: nothing asserted it, so
# the file's own residual comment went on describing the hole for a week after
# it closed, CO1 was filed against that comment, and the 2026-08-28 ruling
# bought a refusal that already existed. A property that is true and unwatched
# is how that happens, and the assertion is the part that stops it happening
# again rather than the extraction being the part that fixed anything.
#
# Driven against the SHIPPED predicate, extracted from attestation-check.sh
# rather than reimplemented, for the reason the CI scope check gives: a copy
# drifts and then the test asserts things about a function that is no longer the
# one running.
CO1SH="$ROOT/publish/attestation-check.sh"
if [[ ! -f "$CO1SH" ]]; then
  ok "CO1 leg-of-this-release: SKIPPED, publish/ is absent (expected in the public repo)"
else
  CO1D="$WORK/co1"; rm -rf "$CO1D"; mkdir -p "$CO1D"
  awk '/^is_leg_of\(\) \{/,/^\}/' "$CO1SH" > "$CO1D/pred.sh"
  if [[ ! -s "$CO1D/pred.sh" ]]; then
    bad "CO1 leg-of-this-release: is_leg_of was extracted from attestation-check.sh" \
        "could not extract the predicate, so this check cannot run, which is a failure rather than a pass"
  else
    printf 'HOSTILE-REVIEW: 2.2.0 PASS\nRESOLVED-TREE: abc\n' > "$CO1D/stale.md"
    printf 'HOSTILE-REVIEW: 2.3.0 PASS\nRESOLVED-TREE: abc\n' > "$CO1D/same.md"
    printf 'HOSTILE-REVIEW: 2.3.0 PASS-WITH-FINDINGS\nRESOLVED-TREE: abc\n' > "$CO1D/round2.md"
    co1_run() { bash -c 'refused_family() { :; }; . "$1"; if is_leg_of "$2" "$3"; then echo ACCEPT; else echo REFUSE; fi' _ "$CO1D/pred.sh" "$1" "$2" 2>/dev/null; }
    # THE CASE THAT HAD TO STOP: an older release's leg, with its smaller
    # finding list, satisfying coverage for this release.
    if [[ "$(co1_run "$CO1D/stale.md" 2.3.0)" == "REFUSE" ]]; then
      ok "CO1: a leg attesting a PRIOR release is refused as this release's cited leg"
    else
      bad "CO1: a leg attesting a PRIOR release is refused as this release's cited leg" \
          "a record could satisfy replay coverage over a finding list that is not this release's"
    fi
    # THE CASE THAT HAD TO KEEP WORKING, and the reason the ruling scoped itself
    # to the version string ALONE: a fix round cites the leg that reviewed the
    # PREVIOUS CANDIDATE of the same release, which is the ordinary shape.
    if [[ "$(co1_run "$CO1D/same.md" 2.3.0)" == "ACCEPT" && "$(co1_run "$CO1D/round2.md" 2.3.0)" == "ACCEPT" ]]; then
      ok "CO1 control: a SAME-version leg, including PASS-WITH-FINDINGS, is still accepted"
    else
      bad "CO1 control: a SAME-version leg, including PASS-WITH-FINDINGS, is still accepted" \
          "the refusal is over-wide and would refuse a round-2 record citing candidate 1's leg, which is the cost the ruling scoped itself to avoid"
    fi
  fi
fi

# A9 AT THE PUSH LAYER: the range arm has exactly one definition and pre-push
# reaches the predicate through it rather than asking its own way. Three
# content-seeing layers already reach the scan through one function; this
# pins the same property for the approval check before a second reader exists.
ATTW_DEFS="$(grep -rl 'slh_attest_walk() {' "$ROOT/templates" "$ROOT/scripts" 2>/dev/null | grep -c . || true)"
ATTW_CALL="$(grep -c 'slh_attest_walk ' "$ROOT/templates/git-hooks/pre-push" 2>/dev/null || true)"
if [[ "$ATTW_DEFS" == "1" && "$ATTW_CALL" -ge 1 ]]; then
  ok "attest push A9: one definition of slh_attest_walk, and pre-push reaches the predicate through it"
else
  bad "attest push A9: one definition of slh_attest_walk, and pre-push reaches the predicate through it" \
      "definitions=$ATTW_DEFS callers-in-pre-push=$ATTW_CALL"
fi

# =============================================================================
# OWNERSHIP IS WHAT EXECUTES, ASKED WHEREVER HOOKS LIVE (2.0.0 leg, F2+F6).
#
# Two holes in the displacement refusal README:176 promises, found by one leg.
# F2: `pre-commit install` and `lefthook install` wire the project's hooks into
# .git/hooks and leave core.hooksPath UNSET, and the guard returned early on
# unset, so --apply set core.hooksPath=.githooks and the project's own secret
# scan silently stopped firing. Two of the three tools the README names wire
# exactly this way, so "unset" is the COMMON foreign state, not the empty one.
# F6: hooks_layer_is_ours claimed a foreign hook as ours if any line merely
# CONTAINED the string setlist-hook-lib.sh, so an ordinary shellcheck-exclusion
# mention defeated the refusal and the foreign layer was overwritten. The
# ownership question is now positional: a file is ours when it is byte-identical
# to a shipped hook, or when the library appears where the shell would LOAD it
# (a source/dot target, or a standalone path word such as the resolver's
# candidate lines), never when it appears as data in some other command's
# argument list.
# =============================================================================

# F2, report mode: hooks at the DEFAULT .git/hooks with hooksPath unset must be
# named as a displacement, exactly as an explicit foreign hooksPath is.
RFI="$WORK/rfi-default-report"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-default-report.out" 2>&1
if grep -q 'DISPLACE' "$WORK/rfi-default-report.out" && grep -q '\.git/hooks' "$WORK/rfi-default-report.out"; then
  ok "refresh F2a: report mode names a foreign layer at the default .git/hooks (hooksPath unset)"
else
  bad "refresh F2a: report mode names a foreign layer at the default .git/hooks (hooksPath unset)" \
      "the report said nothing about the hook already installed in .git/hooks, which is how pre-commit and lefthook actually wire; the operator learns their secret scan is off only when it fails to fire"
fi

# F2, --apply: the probe pair from the leg's own replay. The commit is refused
# by the project's hook BEFORE the refresh; whatever --apply does, the refusal
# must still exist AFTER it, because "nothing was silently switched off" is the
# whole claim.
RFI="$WORK/rfi-default-apply"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
RFI_BEFORE=0; git -C "$RFI" commit --allow-empty -qm "probe before" >/dev/null 2>&1 || RFI_BEFORE=1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-default-apply.out" 2>&1
RFI_AFTER=0; git -C "$RFI" commit --allow-empty -qm "probe after" >/dev/null 2>&1 || RFI_AFTER=1
if [[ "$RFI_BEFORE" -eq 1 && "$RFI_AFTER" -eq 1 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-default-apply.out"; then
  ok "refresh F2b: --apply refuses to disarm a project's own .git/hooks layer, and the probe commit stays refused"
else
  bad "refresh F2b: --apply refuses to disarm a project's own .git/hooks layer, and the probe commit stays refused" \
      "probe refused before=$RFI_BEFORE after=$RFI_AFTER; a commit the project's hook refused before the refresh landing after it is the leg's F2 replay, verbatim"
fi

# F2, the deliberate override still works at the default location.
RFI="$WORK/rfi-default-adopt"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh F2c: SETLIST_ADOPT_HOOKSPATH=1 adopts over a .git/hooks layer on purpose"
else
  bad "refresh F2c: SETLIST_ADOPT_HOOKSPATH=1 adopts over a .git/hooks layer on purpose" \
      "the escape did not arm, so the new refusal is a dead end rather than a decision point"
fi

# F2, the stamp path has the same blind spot and must get the same refusal:
# retrofit is precisely the onto-an-existing-project case.
STF="$WORK/stamp-default-foreign"; rm -rf "$STF"; mkdir -p "$STF"
git_init "$STF"
printf 'x\n' > "$STF/keep.txt"; git -C "$STF" add -A >/dev/null 2>&1; git -C "$STF" commit -qm seed >/dev/null 2>&1
mkdir -p "$STF/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$STF/.git/hooks/pre-commit"
chmod +x "$STF/.git/hooks/pre-commit"
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF" >"$WORK/stamp-default.out" 2>&1
STF_RC=$?
STF_HP="$(git -C "$STF" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: empty means not armed, which is what the refusal direction wants
if [[ "$STF_RC" -ne 0 && "$STF_HP" != ".githooks" ]] && grep -qE 'refus|REFUS' "$WORK/stamp-default.out"; then
  ok "stamp F2d: a retrofit onto a project with its own .git/hooks layer refuses rather than disarming it"
else
  bad "stamp F2d: a retrofit onto a project with its own .git/hooks layer refuses rather than disarming it" \
      "rc=$STF_RC hooksPath=[$STF_HP]; a stamp that arms here switches off the host project's own hook layer, secret scanning included, while reporting success"
fi

# CONTROL for the F2 family: a fresh repository's .git/hooks holds only git's
# own .sample files, which are executable on most platforms. They are not a
# layer (git never runs them), so the ordinary arm must not start refusing.
RFI="$WORK/rfi-samples-only"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho sample\n' > "$RFI/.git/hooks/pre-commit.sample"
chmod +x "$RFI/.git/hooks/pre-commit.sample"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-samples.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] && ! grep -q 'DISPLACE' "$WORK/rfi-samples.out"; then
  ok "refresh F2 control: git's own .sample files do not read as a foreign layer"
else
  bad "refresh F2 control: git's own .sample files do not read as a foreign layer" \
      "the ordinary path stopped arming or warned about samples; this is the false-denial direction and it would fire on every fresh repository"
fi

# F6, the mention: a foreign hook whose text merely NAMES the library (an
# ordinary shellcheck exclusion in a repo that vendors hooks) is not ours.
RFI="$WORK/rfi-mention"; rfi_fixture "$RFI" .githooks
cat > "$RFI/.githooks/pre-commit" <<'MENTIONHOOK'
#!/bin/sh
# lint everything except the vendored setlist library
shellcheck $(git ls-files '*.sh' | grep -v setlist-hook-lib.sh) 2>/dev/null || true
echo "foreign hook refusing"
exit 1
MENTIONHOOK
chmod +x "$RFI/.githooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-mention.out" 2>&1
RFI_MENTION_SURVIVED=0
grep -q 'foreign hook refusing' "$RFI/.githooks/pre-commit" 2>/dev/null && RFI_MENTION_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-mention.out" && [[ "$RFI_MENTION_SURVIVED" -eq 1 ]]; then
  ok "refresh F6c: a hook that merely MENTIONS setlist-hook-lib.sh is not claimed as ours"
else
  bad "refresh F6c: a hook that merely MENTIONS setlist-hook-lib.sh is not claimed as ours" \
      "survived=$RFI_MENTION_SURVIVED; a grep-visible mention defeated the displacement refusal, so the ownership test is still a substring search rather than a question about what executes"
fi

# =============================================================================
# OWNERSHIP IS A SET OF BYTES, NOT A GRAMMAR (fix round 3, both adversary
# rounds). Two cold reviews broke every text reading of "does this file load
# our artifact", in both directions, seventeen shapes across two rounds; the
# session-gate parser history, replayed inside the guard. A hook is OURS when
# its content hash is in the set of bytes this project ever shipped for
# templates/git-hooks/ (the embedded blob list), or byte-identical to the
# current shipped file. An operator-ADJUSTED copy REFUSES with the file named
# and SETLIST_ADOPT_HOOKSPATH=1 as the one-step escape: a refusal with an
# escape is a decision point; a text guess is a displaced secret scanner or a
# silent adoption.
# =============================================================================

# The embedded blob list is NOT hand-maintained: whenever this suite runs
# where the repository history is visible, the list must contain every
# historical blob of templates/git-hooks/, so a hook edit that forgets to
# regenerate goes red in the commit that makes it.
if git -C "$ROOT" rev-list --all -- templates/git-hooks/ >/dev/null 2>&1 && [[ -n "$(git -C "$ROOT" rev-list --all -- templates/git-hooks/ 2>/dev/null | head -1)" ]]; then
  BLOB_MISSING=""
  while IFS= read -r bl; do
    [[ -n "$bl" ]] || continue
    ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; case "$KNOWN_SETLIST_HOOK_BLOBS" in *"$bl"*) exit 0 ;; *) exit 1 ;; esac ) \
      || BLOB_MISSING="$BLOB_MISSING $bl"
  done <<< "$(git -C "$ROOT" rev-list --all -- templates/git-hooks/ | while read -r c; do git -C "$ROOT" ls-tree "$c" -- templates/git-hooks/ | awk '{print $3}'; done | sort -u)"
  if [[ -z "$BLOB_MISSING" ]]; then
    ok "ownership blob list: every historical templates/git-hooks blob is in the embedded set"
  else
    bad "ownership blob list: every historical templates/git-hooks blob is in the embedded set" \
        "missing:$BLOB_MISSING; regenerate KNOWN_SETLIST_HOOK_BLOBS in setlist-delivery-lib.sh in this same commit (the recipe is in its comment)"
  fi
else
  ok "ownership blob list: history not visible here (export tree); the source-repo run asserts the list"
fi

# The REAL upgrade state: a layer built from an EARLIER commit's actual bytes
# must refresh cleanly. Gated on history visibility for the same reason.
OLDC="$(git -C "$ROOT" rev-list --all --skip=20 -- templates/git-hooks/ 2>/dev/null | head -1)"
if [[ -n "$OLDC" ]]; then
  RFI="$WORK/rfi-historical"; rfi_fixture "$RFI" ""
  mkdir -p "$RFI/.githooks"
  RFI_HIST_BUILT=1
  for h in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
    git -C "$ROOT" show "$OLDC:templates/git-hooks/$h" > "$RFI/.githooks/$h" 2>/dev/null || RFI_HIST_BUILT=0
  done
  chmod +x "$RFI/.githooks/"* 2>/dev/null
  git -C "$RFI" config core.hooksPath .githooks
  if [[ "$RFI_HIST_BUILT" -eq 1 ]]; then
    bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-hist.out" 2>&1
    if grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-hist.out"; then
      bad "refresh F6d: a layer of an earlier commit's REAL bytes refreshes cleanly" \
          "the upgrade path refused this project's own historical hooks (commit $OLDC); the blob list is not doing its one job"
    else
      ok "refresh F6d: a layer of an earlier commit's REAL bytes refreshes cleanly"
    fi
  else
    ok "refresh F6d: historical bytes incomplete at $OLDC (file set differed); skipped"
  fi
else
  ok "refresh F6d: history not visible here (export tree); the source-repo run asserts the upgrade state"
fi

# The ADJUSTED-copy direction, decided deliberately in fix round 3: an
# operator-annotated hook is NOT silently ours, it REFUSES with the escape
# working, because the two text-based attempts to bless adjusted copies were
# each broken by a $5 review in both directions.
RFI="$WORK/rfi-prepush-adjusted"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
printf '\n# instance note\n' >> "$RFI/.githooks/pre-push"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adj.out" 2>&1
RFI_ADJ_REFUSED=0
grep -qE 'REFUS|refusing to arm' "$WORK/rfi-adj.out" && RFI_ADJ_REFUSED=1
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adj2.out" 2>&1
if [[ "$RFI_ADJ_REFUSED" -eq 1 && "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]] \
   && ls "$RFI/.githooks/"*.setlist-backup >/dev/null 2>&1; then
  ok "refresh F6e: an adjusted copy refuses by name, and the escape adopts with a backup"
else
  bad "refresh F6e: an adjusted copy refuses by name, and the escape adopts with a backup" \
      "refused=$RFI_ADJ_REFUSED hooksPath=[$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)]; either an adjusted copy was silently claimed (the text-guess hole) or the escape is a dead end"
fi

# Adversary round 2, finding 1: a project whose own script is NAMED
# trunk-audit.sh must not donate its hook layer. End to end: the probe commit
# refused before must still be refused after a refusal-mode --apply.
RFI="$WORK/rfi-genericname"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks" "$RFI/tools"
printf '#!/bin/sh\nexec tools/trunk-audit.sh\n' > "$RFI/.git/hooks/pre-commit"
printf '#!/bin/sh\necho "PROJECT SECRET SCAN RAN, COMMIT BLOCKED" >&2\nexit 1\n' > "$RFI/tools/trunk-audit.sh"
chmod +x "$RFI/.git/hooks/pre-commit" "$RFI/tools/trunk-audit.sh"
RFI_GN_BEFORE=0; git -C "$RFI" commit --allow-empty -qm probe >/dev/null 2>&1 || RFI_GN_BEFORE=1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-gn.out" 2>&1
RFI_GN_AFTER=0; git -C "$RFI" commit --allow-empty -qm probe2 >/dev/null 2>&1 || RFI_GN_AFTER=1
if [[ "$RFI_GN_BEFORE" -eq 1 && "$RFI_GN_AFTER" -eq 1 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-gn.out"; then
  ok "refresh F6f: a project's own script merely NAMED trunk-audit.sh does not donate its layer"
else
  bad "refresh F6f: a project's own script merely NAMED trunk-audit.sh does not donate its layer" \
      "probe before=$RFI_GN_BEFORE after=$RFI_GN_AFTER; a generic filename claimed ownership, which is the name-decides defect at one remove"
fi

# DIRECTION CONTROL: naming trunk-audit.sh as DATA is still nobody's.
RFI="$WORK/rfi-ta-mention"; rfi_fixture "$RFI" .githooks
cat > "$RFI/.githooks/pre-push" <<'TAMENTION'
#!/bin/sh
# lint all scripts except the vendored audit tool
shellcheck $(git ls-files '*.sh' | grep -v trunk-audit.sh) 2>/dev/null || true
echo "foreign pre-push refusing"
exit 1
TAMENTION
chmod +x "$RFI/.githooks/pre-push"
rm -f "$RFI/.githooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-tament.out" 2>&1
RFI_TAM_SURVIVED=0
grep -q 'foreign pre-push refusing' "$RFI/.githooks/pre-push" 2>/dev/null && RFI_TAM_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-tament.out" && [[ "$RFI_TAM_SURVIVED" -eq 1 ]]; then
  ok "refresh F6g: a hook that merely MENTIONS trunk-audit.sh is not claimed as ours"
else
  bad "refresh F6g: a hook that merely MENTIONS trunk-audit.sh is not claimed as ours" \
      "survived=$RFI_TAM_SURVIVED; widening identity to the second artifact must not reopen the mention hole it was built to close"
fi

# =============================================================================
# A RUN THAT ENDS IN REFUSAL WRITES NOTHING, generically (second 2.0.0 leg, F5).
#
# The F6 second-order lesson ("the refusal comes before the first write")
# recurred one layer up: the displacement refusal was hoisted above the
# .githooks copy loop, and the four .claude/hooks session-gate copies sat
# seventy lines EARLIER still, so --apply performed four unbacked writes and
# then printed "Nothing has been changed." The assertion here is the CLASS,
# not the instance: snapshot every file in the instance plus the two config
# values, run an --apply that must refuse, and require the snapshot identical.
# Any future write added above the refusal fails this without a new test.
# =============================================================================
rfi_snapshot() { # rfi_snapshot <dir> -> content+config fingerprint on stdout
  ( cd "$1" && find . -path ./.git -prune -o -type f -print0 2>/dev/null \
      | sort -z | xargs -0 shasum 2>/dev/null )
  git -C "$1" config --get core.hooksPath 2>/dev/null || printf 'hooksPath-unset\n'
  git -C "$1" config --get merge.ff 2>/dev/null || printf 'merge.ff-unset\n'
}
RFI="$WORK/rfi-nowrite"; rfi_fixture "$RFI" ""
for h in scope-hook commit-gate close-gate regrounding-hook; do
  printf '#!/bin/sh\n# PROJECT FORK of %s\nexit 0\n' "$h" > "$RFI/.claude/hooks/$h.sh"
done
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "project secret scan refuses" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
RFI_SNAP_BEFORE="$(rfi_snapshot "$RFI")"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-nowrite.out" 2>&1
RFI_NOWRITE_RC=$?
RFI_SNAP_AFTER="$(rfi_snapshot "$RFI")"
if [[ "$RFI_NOWRITE_RC" -ne 0 && "$RFI_SNAP_BEFORE" == "$RFI_SNAP_AFTER" ]] && grep -qE 'refus|REFUS' "$WORK/rfi-nowrite.out"; then
  ok "refresh F5: a refused --apply writes NOTHING, snapshot-identical across the whole instance"
else
  bad "refresh F5: a refused --apply writes NOTHING, snapshot-identical across the whole instance" \
      "rc=$RFI_NOWRITE_RC; a refusal whose message says nothing changed printed over an instance whose files moved: $(diff <(printf '%s' "$RFI_SNAP_BEFORE") <(printf '%s' "$RFI_SNAP_AFTER") | head -4 | tr '\n' ' ')"
fi
# DIRECTION CONTROL: the same fixture WITH the override applies fully, so the
# no-write property is the refusal's and not a general paralysis.
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
   && cmp -s "$HOOKS/close-gate.sh" "$RFI/.claude/hooks/close-gate.sh"; then
  ok "refresh F5 control: the adopted run still delivers both layers in full"
else
  bad "refresh F5 control: the adopted run still delivers both layers in full" \
      "the no-write fix went too far: the deliberate override no longer refreshes"
fi

# =============================================================================
# THE GUARD RESOLVES core.hooksPath THE WAY GIT DOES (second 2.0.0 leg, F7).
#
# git expands a tilde in core.hooksPath and RUNS the layer there; the guard
# treated the value as repo-relative, built <repo>/~/.githooks, found nothing,
# and --apply silently displaced the layer README promises to refuse while
# report mode called the setting unset. Raw on one side, normalized on the
# other: the slh_trunk lesson, recurred in a path. The corpus below drives the
# SPELLINGS (tilde, relative, absolute, trailing slash), each both directions.
# =============================================================================
RFI_HP_BAD=""
rfi_hp_case() { # rfi_hp_case <label> <configured-value> <real-dir-under> <want: refuse|arm>
  local label="$1" spelled="$2" where="$3" want="$4"
  local d="$WORK/rfi-hp-$label" fh="$WORK/rfi-hp-home-$label"
  rm -rf "$d" "$fh"; mkdir -p "$fh"
  rfi_fixture "$d" ""
  local hookdir
  case "$where" in
    home) hookdir="$fh/.githooks" ;;
    *)    hookdir="$d/$where" ;;
  esac
  mkdir -p "$hookdir"
  printf '#!/bin/sh\necho "foreign layer refusing"\nexit 1\n' > "$hookdir/pre-commit"
  chmod +x "$hookdir/pre-commit"
  git -C "$d" config core.hooksPath "$spelled"
  HOME="$fh" bash "$SCRIPTS/refresh-instance.sh" --apply "$d" >"$WORK/rfi-hp-$label.out" 2>&1
  local rc=$? hp; hp="$(git -C "$d" config --get core.hooksPath 2>/dev/null || true)"
  if [[ "$want" == "refuse" ]]; then
    if [[ "$rc" -ne 0 && "$hp" == "$spelled" ]] && grep -qE 'refus|REFUS' "$WORK/rfi-hp-$label.out"; then :; else
      RFI_HP_BAD="$RFI_HP_BAD
    $label: spelled [$spelled], wanted refusal, got rc=$rc hooksPath=[$hp]; the layer git actually runs was silently displaced"
    fi
  else
    if [[ "$rc" -eq 0 && "$hp" == ".githooks" ]]; then :; else
      RFI_HP_BAD="$RFI_HP_BAD
    $label: spelled [$spelled], wanted a clean arm, got rc=$rc hooksPath=[$hp]; the normalization refuses what it should recognise"
    fi
  fi
}
# Adversary finding 2: git resolves a RELATIVE value against the work-tree
# TOP; an instance in a subdirectory must still see the repository's layer.
RFI_HP_SUB="$WORK/rfi-hp-subroot"; rm -rf "$RFI_HP_SUB"; mkdir -p "$RFI_HP_SUB/app/.claude/hooks" "$RFI_HP_SUB/.myhooks"
git_init "$RFI_HP_SUB"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_HP_SUB/app/.claude/sdd.json"
printf '#!/bin/sh\necho "top-level scan refusing"\nexit 1\n' > "$RFI_HP_SUB/.myhooks/pre-commit"
chmod +x "$RFI_HP_SUB/.myhooks/pre-commit"
git -C "$RFI_HP_SUB" config core.hooksPath .myhooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_HP_SUB/app" >"$WORK/rfi-hp-sub.out" 2>&1
# Round 4/5 semantics: below the top nothing arms at all, so the top-level
# layer is safe by construction; the assertion is that the run says so and
# touches no config, not that a displacement refusal fires.
if grep -q 'NOT ARMED' "$WORK/rfi-hp-sub.out" && [[ "$(git -C "$RFI_HP_SUB" config --get core.hooksPath)" == ".myhooks" ]] \
   && ! grep -qE 'refusing to arm' "$WORK/rfi-hp-sub.out"; then
  ok "refresh F7b: below the top the run arms nothing and says so; the top-level layer is untouched"
else
  RFI_HP_BAD="$RFI_HP_BAD
    subdir: hooksPath=[$(git -C "$RFI_HP_SUB" config --get core.hooksPath 2>/dev/null)] (adversary finding 2 / round-4 semantics)"
  bad "refresh F7b: below the top the run arms nothing and says so; the top-level layer is untouched" \
      "either config moved from a subdirectory run, or the skip was silent, or a refusal fired on a run that arms nothing"
fi
# Adversary finding 7: a ~user spelling under a git without --type=path is
# UNRESOLVABLE, and unresolvable fails CLOSED, never silent.
RFI_HP_OG="$WORK/rfi-hp-oldgit"; rm -rf "$RFI_HP_OG"; mkdir -p "$RFI_HP_OG/bin"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in --type=*) exit 129;; esac; done\nexec %s "$@"\n' "$(command -v git)" > "$RFI_HP_OG/bin/git"
chmod +x "$RFI_HP_OG/bin/git"
rfi_fixture "$RFI_HP_OG/inst" ""
git -C "$RFI_HP_OG/inst" config core.hooksPath "~$(id -un)/.githooks"
PATH="$RFI_HP_OG/bin:$PATH" bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_HP_OG/inst" >"$WORK/rfi-hp-og.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-hp-og.out"; then
  ok "refresh F7c: a ~user hooksPath under a git without --type=path refuses rather than assuming"
else
  bad "refresh F7c: a ~user hooksPath under a git without --type=path refuses rather than assuming" \
      "an unresolvable spelling proceeded to arm; a guard that cannot see a layer must not conclude it is absent"
fi
rfi_hp_case tilde '~/.githooks' home refuse
rfi_hp_case tildeslash '~/.githooks/' home refuse
rfi_hp_case relslash '.theirs/' '.theirs' refuse
rfi_hp_case abs "$WORK/rfi-hp-absdir" ../rfi-hp-absdir refuse
# The ours direction: a layer of OUR OWN hooks reachable only via tilde must
# not be refused (the guard recognises it and the arm proceeds).
RFI="$WORK/rfi-hp-ours"; FH="$WORK/rfi-hp-home-ours"; rm -rf "$RFI" "$FH"
mkdir -p "$FH/.githooks"; rfi_fixture "$RFI" ""
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
   "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$FH/.githooks/"
chmod +x "$FH/.githooks/"*
git -C "$RFI" config core.hooksPath '~/.githooks'
HOME="$FH" bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-hp-ours.out" 2>&1
# The rc is NOT asserted zero: this fixture has no settings wiring, so a full
# arm legitimately exits 3 (INCOMPLETE), exactly like the plain refresh
# control above. What the ours-direction claims is narrower: recognised (no
# displacement refusal) and armed.
if [[ "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]] \
   && ! grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-hp-ours.out"; then :; else
  RFI_HP_BAD="$RFI_HP_BAD
    ours-tilde: our own layer spelled with a tilde was refused or the arm did not complete (hooksPath=[$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)])"
fi
if [[ -z "$RFI_HP_BAD" ]]; then
  ok "refresh F7: core.hooksPath is resolved the way git resolves it, five spellings both directions"
else
  bad "refresh F7: core.hooksPath is resolved the way git resolves it, five spellings both directions" \
      "raw-vs-normalized in a path:$RFI_HP_BAD"
fi

# =============================================================================
# THE TEXT-SHAPE CORPUS IS NOW A ONE-SIDED CONTROL (fix round 3, final form).
#
# Under hash ownership every text shape the two adversary rounds produced is
# FOREIGN, because no text confers ownership at all. The corpus is kept as a
# standing control that no future "convenience" clause quietly reintroduces a
# grammar: if any of these ever reads as ours, someone has started parsing
# again.
# =============================================================================
OWN_CORPUS_BAD=""
own_case() { # own_case <name> <want: ours|foreign> <<'BODY'
  local name="$1" want="$2" f="$WORK/own-corpus-$1" got
  cat > "$f"; chmod +x "$f"
  if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; setlist_hook_blob_is_known "$f" ); then got=ours; else got=foreign; fi
  [[ "$got" == "$want" ]] || OWN_CORPUS_BAD="$OWN_CORPUS_BAD
    $name: predicate said $got, the shape is $want"
}
own_case lint-skip-data foreign <<'B'
#!/bin/sh
bash tools/shellcheck-all.sh --skip trunk-audit.sh
B
own_case exec-arg-data foreign <<'B'
#!/bin/sh
exec shellcheck --external-sources setlist-hook-lib.sh
B
own_case dot-arg-data foreign <<'B'
#!/bin/sh
. ./ci/lib.sh --skip trunk-audit.sh
B
own_case usage-string foreign <<'B'
#!/bin/sh
echo "to enable: source hooks/trunk-audit.sh" >&2
B
own_case diff-dot-arg foreign <<'B'
#!/bin/sh
diff -q . vendor/trunk-audit.sh >/dev/null || echo drift
B
own_case var-load foreign <<'B'
#!/usr/bin/env bash
LIB="$(dirname "$0")/setlist-hook-lib.sh"
. "$LIB"
slh_main "$@"
B
own_case one-line-resolver foreign <<'B'
#!/bin/sh
for cand in "$X/setlist-hook-lib.sh" "$Y/setlist-hook-lib.sh"; do :; done
B
own_case generic-name-exec foreign <<'B'
#!/bin/sh
exec tools/trunk-audit.sh
B
# The OURS side is bytes, not text: the current shipped file's exact content.
cp "$ROOT/templates/git-hooks/pre-push" "$WORK/own-corpus-shipped"; chmod +x "$WORK/own-corpus-shipped"
if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; setlist_hook_blob_is_known "$WORK/own-corpus-shipped" ); then :; else
  OWN_CORPUS_BAD="$OWN_CORPUS_BAD
    shipped-bytes: the current shipped pre-push is not in its own blob list"
fi
if [[ -z "$OWN_CORPUS_BAD" ]]; then
  ok "ownership corpus: eight text shapes are nobody's, the shipped bytes are ours"
else
  bad "ownership corpus: eight text shapes are nobody's, the shipped bytes are ours" \
      "a text shape moved sides, so a grammar is creeping back into a hash question:$OWN_CORPUS_BAD"
fi

# =============================================================================
# THE HASH IS CONTEXT-FREE AND BLINDNESS FAILS CLOSED (adversary round 3).
# =============================================================================
OWN_CTX_BAD=""
# finding 1/2: the verdict must not depend on the caller's cwd, the repo's
# object format, or its clean filters.
OWN_CTX_R="$WORK/own-ctx-repo"; rm -rf "$OWN_CTX_R"
if git init -q --object-format=sha256 "$OWN_CTX_R" 2>/dev/null; then :; else git init -q "$OWN_CTX_R"; fi
printf '* filter=x\n' > "$OWN_CTX_R/.gitattributes"
git -C "$OWN_CTX_R" config filter.x.clean 'tr a-z A-Z'
if ( cd "$OWN_CTX_R" && GITHOOKS_SRC="$ROOT/templates/git-hooks" && source "$ROOT/scripts/setlist-delivery-lib.sh" && setlist_hook_blob_is_known "$ROOT/templates/git-hooks/pre-push" ); then :; else
  OWN_CTX_BAD="$OWN_CTX_BAD
    context: the shipped pre-push stopped being ours when judged from inside a sha256/filtered repo cwd"
fi
# finding 4: an unreadable hooks directory is refused, never vouched for.
OWN_CTX_D="$WORK/own-ctx-unread"; rm -rf "$OWN_CTX_D"; mkdir -p "$OWN_CTX_D"
printf '#!/bin/sh\nexit 1\n' > "$OWN_CTX_D/pre-commit"; chmod +x "$OWN_CTX_D/pre-commit"; chmod 000 "$OWN_CTX_D"
if perm_fixture_bites "$OWN_CTX_D" "ownership context blindness"; then
  if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; hooks_layer_is_ours "$OWN_CTX_D" ); then
    OWN_CTX_BAD="$OWN_CTX_BAD
    unreadable: a directory the guard cannot list was vouched for as ours"
  fi
fi
chmod 755 "$OWN_CTX_D"
if [[ -z "$OWN_CTX_BAD" ]]; then
  ok "ownership context: the hash is cwd/format/filter-independent and blindness refuses"
else
  bad "ownership context: the hash is cwd/format/filter-independent and blindness refuses" \
      "the verdict depended on where the operator stood, or blindness passed:$OWN_CTX_BAD"
fi

# Adversary round 3, finding 3: the ALREADY-ARMED exemption. An armed instance
# that gained one extra hook (the git-lfs shape) refreshes rather than
# dead-ending: nothing is displaced because the arm changes nothing about
# where git looks; our-named files are replaced with backups.
RFI="$WORK/rfi-armed-extra"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
printf '#!/bin/sh\ngitleaks protect --staged || exit 1\n' > "$RFI/.githooks/commit-msg"
chmod +x "$RFI/.githooks/commit-msg"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-armed-extra.out" 2>&1
if ! grep -qE 'refusing to arm' "$WORK/rfi-armed-extra.out" \
   && [[ -x "$RFI/.githooks/commit-msg" ]] \
   && [[ "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]]; then
  ok "refresh F6h: an armed instance with one extra hook refreshes; nothing is displaced by a no-op arm"
else
  bad "refresh F6h: an armed instance with one extra hook refreshes; nothing is displaced by a no-op arm" \
      "the refusal told the operator to move their checks into the directory they were already in, and every git-lfs install dead-ended the refresh"
fi
# The refusal, where it IS real, names the foreign files (finding 3's message half).
RFI="$WORK/rfi-named"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-named.out" 2>&1
if grep -q 'foreign: pre-commit' "$WORK/rfi-named.out"; then
  ok "refresh F6i: the displacement refusal names the foreign files it protects"
else
  bad "refresh F6i: the displacement refusal names the foreign files it protects" \
      "the refusal gestured at a directory without naming what runs there"
fi

# Adversary round 3 finding 5, softened by round 4 finding 6: an instance
# below the worktree top gets its ADVISORY hooks refreshed, the git-hook
# boundary is skipped LOUDLY with the reason, nothing touches config, and the
# run exits 3 because part of the promise is not in force.
RFI_SUB="$WORK/rfi-subinst"; rm -rf "$RFI_SUB"; mkdir -p "$RFI_SUB/app/.claude/hooks"
git_init "$RFI_SUB"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_SUB/app/.claude/sdd.json"
printf '#!/bin/sh\n# stale close gate\n' > "$RFI_SUB/app/.claude/hooks/close-gate.sh"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_SUB/app" >"$WORK/rfi-subinst.out" 2>&1
RFI_SUB_RC=$?
RFI_SUB_BAD=""
[[ "$RFI_SUB_RC" -eq 3 ]] || RFI_SUB_BAD="$RFI_SUB_BAD rc=$RFI_SUB_RC(want 3)"
grep -q 'NOT ARMED' "$WORK/rfi-subinst.out" || RFI_SUB_BAD="$RFI_SUB_BAD no-not-armed-note"
[[ -z "$(git -C "$RFI_SUB" config --get core.hooksPath 2>/dev/null)" ]] || RFI_SUB_BAD="$RFI_SUB_BAD parent-config-touched"
[[ ! -e "$RFI_SUB/app/.githooks" ]] || RFI_SUB_BAD="$RFI_SUB_BAD githooks-delivered-inert"
cmp -s "$HOOKS/close-gate.sh" "$RFI_SUB/app/.claude/hooks/close-gate.sh" || RFI_SUB_BAD="$RFI_SUB_BAD advisory-not-refreshed"
if [[ -z "$RFI_SUB_BAD" ]]; then
  ok "refresh F6j: below the worktree top the advisory layer refreshes, the boundary skips loudly, exit 3"
else
  bad "refresh F6j: below the worktree top the advisory layer refreshes, the boundary skips loudly, exit 3" \
      "problems:$RFI_SUB_BAD; either an inert boundary shipped under a success message, or the advisory refresh was held hostage to a config git cannot honor here"
fi
# The stamp path: same start state, one decision computed BEFORE any write, so
# a target that does not exist yet cannot dodge the guard (round 4, finding 1).
STF_SUB="$WORK/stamp-subinst"; rm -rf "$STF_SUB"; mkdir -p "$STF_SUB"
git_init "$STF_SUB"
mkdir -p "$STF_SUB/.git/hooks"
printf '#!/bin/sh\necho "MONOREPO GITLEAKS refuses" >&2\nexit 1\n' > "$STF_SUB/.git/hooks/pre-commit"
chmod +x "$STF_SUB/.git/hooks/pre-commit"
printf 'x\n' > "$STF_SUB/keep.txt"; git -C "$STF_SUB" add keep.txt >/dev/null 2>&1
STF_SUB_BEFORE=0; git -C "$STF_SUB" commit -qm probe >/dev/null 2>&1 || STF_SUB_BEFORE=1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF_SUB/apps/newapp" >"$WORK/stamp-subinst.out" 2>&1
STF_SUB_BAD=""
grep -q 'NOT ARMED' "$WORK/stamp-subinst.out" || STF_SUB_BAD="$STF_SUB_BAD no-not-armed-note"
[[ -z "$(git -C "$STF_SUB" config --get core.hooksPath 2>/dev/null)" ]] || STF_SUB_BAD="$STF_SUB_BAD monorepo-config-armed"
STF_SUB_AFTER=0; git -C "$STF_SUB" commit -qm probe2 --allow-empty >/dev/null 2>&1 || STF_SUB_AFTER=1
[[ "$STF_SUB_BEFORE" -eq 1 && "$STF_SUB_AFTER" -eq 1 ]] || STF_SUB_BAD="$STF_SUB_BAD gitleaks-disarmed(before=$STF_SUB_BEFORE after=$STF_SUB_AFTER)"
if [[ -z "$STF_SUB_BAD" ]]; then
  ok "stamp F6k: a not-yet-existing subdir target cannot dodge the arming decision; the monorepo layer keeps running"
else
  bad "stamp F6k: a not-yet-existing subdir target cannot dodge the arming decision; the monorepo layer keeps running" \
      "problems:$STF_SUB_BAD; two is-inside-work-tree tests at different times is how the mkdir smuggled the arm past both guards"
fi
# Round 4, finding 2: an armed .githooks the guard cannot LIST voids the
# exemption; the refusal fires instead of a silent overwrite.
RFI_300="$WORK/rfi-mode300"; rfi_fixture "$RFI_300" ""
mkdir -p "$RFI_300/.githooks"
printf '#!/bin/sh\nexec gitleaks protect --staged\n' > "$RFI_300/.githooks/pre-commit"
chmod 755 "$RFI_300/.githooks/pre-commit"
git -C "$RFI_300" config core.hooksPath .githooks
chmod 300 "$RFI_300/.githooks"
if ! perm_fixture_bites "$RFI_300/.githooks" "refresh F6l"; then
  chmod 755 "$RFI_300/.githooks"
  RFI_300_SKIPPED=1
else
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_300" >"$WORK/rfi-mode300.out" 2>&1
RFI_300_RC=$?
chmod 755 "$RFI_300/.githooks"
if [[ "$RFI_300_RC" -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/rfi-mode300.out" \
   && grep -q 'exec gitleaks' "$RFI_300/.githooks/pre-commit"; then
  ok "refresh F6l: an armed layer the guard cannot list refuses; blindness voids the exemption too"
else
  bad "refresh F6l: an armed layer the guard cannot list refuses; blindness voids the exemption too" \
      "rc=$RFI_300_RC; a mode-300 directory slid past the exemption and a live scanner was overwritten"
fi
fi
# Round 4, finding 3: the ./.githooks spelling reaches the same exemption.
RFI_DOT="$WORK/rfi-dotslash"; rfi_fixture "$RFI_DOT" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DOT" >/dev/null 2>&1
printf '#!/bin/sh\ngit lfs post-checkout "$@"\n' > "$RFI_DOT/.githooks/post-checkout"
chmod 755 "$RFI_DOT/.githooks/post-checkout"
git -C "$RFI_DOT" config core.hooksPath ./.githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DOT" >"$WORK/rfi-dotslash.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-dotslash.out" && [[ -x "$RFI_DOT/.githooks/post-checkout" ]]; then
  ok "refresh F6m: the ./.githooks spelling reaches the already-armed exemption like its siblings"
else
  bad "refresh F6m: the ./.githooks spelling reaches the already-armed exemption like its siblings" \
      "a dot-segment spelling git treats as identical dead-ended the refresh; the normalizer stops at trailing slashes"
fi

# =============================================================================
# ROUND 5 PINS: the softened paths tell one truth everywhere.
# =============================================================================
# F1: below the top WITH a foreign layer at the parent's default dir, the
# advisory refresh still proceeds (nothing arms, so nothing displaces).
RFI_R51="$WORK/rfi-r5-subforeign"; rm -rf "$RFI_R51"; mkdir -p "$RFI_R51/app/.claude/hooks"
git_init "$RFI_R51"
mkdir -p "$RFI_R51/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$RFI_R51/.git/hooks/pre-commit"; chmod +x "$RFI_R51/.git/hooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_R51/app/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R51/app" >"$WORK/rfi-r51.out" 2>&1
RFI_R51_RC=$?
if [[ "$RFI_R51_RC" -eq 3 ]] && ! grep -q 'refusing to arm' "$WORK/rfi-r51.out" \
   && cmp -s "$HOOKS/close-gate.sh" "$RFI_R51/app/.claude/hooks/close-gate.sh" \
   && grep -q 'NOT ARMED' "$WORK/rfi-r51.out"; then
  ok "refresh R5a: below the top, a parent-layer foreign dir does not block the advisory refresh"
else
  bad "refresh R5a: below the top, a parent-layer foreign dir does not block the advisory refresh" \
      "rc=$RFI_R51_RC; the displacement refusal fired on a run that was never going to arm anything"
fi
# F2: report mode and apply mode describe the same future below the top.
bash "$SCRIPTS/refresh-instance.sh" "$RFI_R51/app" >"$WORK/rfi-r52.out" 2>&1
if grep -q 'NOT ARMED here and will not be' "$WORK/rfi-r52.out" && ! grep -q 'git config still to set' "$WORK/rfi-r52.out"; then
  ok "refresh R5b: report mode says NOT ARMED where apply will not arm, promising nothing it skips"
else
  bad "refresh R5b: report mode says NOT ARMED where apply will not arm, promising nothing it skips" \
      "the decision surface promised the boundary that apply then skipped"
fi
# F3: stamp exits 4 for the skip-subdir state and its tail names the reason.
STF_R5="$WORK/stamp-r5-sub"; rm -rf "$STF_R5"; mkdir -p "$STF_R5"; git_init "$STF_R5"
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF_R5/app" >"$WORK/stamp-r5.out" 2>&1
STF_R5_RC=$?
if [[ "$STF_R5_RC" -eq 4 ]] && grep -q 'below its worktree top or is a linked worktree' "$WORK/stamp-r5.out" \
   && ! grep -q 'no repository yet' "$WORK/stamp-r5.out"; then
  ok "stamp R5c: skip-subdir exits 4 and the last line names the real reason, not /scaffold"
else
  bad "stamp R5c: skip-subdir exits 4 and the last line names the real reason, not /scaffold" \
      "rc=$STF_R5_RC; the tail advised the displacement the run just refused, at exit 0 no caller could see"
fi
# F4: a linked worktree never arms (the config is shared with the main).
LW="$WORK/rfi-linked"; rm -rf "$LW"; mkdir -p "$LW/main"
git_init "$LW/main"
mkdir -p "$LW/main/.husky"
printf '#!/bin/sh\nexit 1\n' > "$LW/main/.husky/pre-commit"; chmod +x "$LW/main/.husky/pre-commit"
git -C "$LW/main" config core.hooksPath .husky
printf 'x\n' > "$LW/main/f"; git -C "$LW/main" add f >/dev/null 2>&1; git -C "$LW/main" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git -C "$LW/main" worktree add -q "$LW/lw" -b lwb >/dev/null 2>&1
mkdir -p "$LW/lw/.claude/hooks"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$LW/lw/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$LW/lw" >"$WORK/rfi-lw.out" 2>&1
if [[ "$(git -C "$LW/main" config --get core.hooksPath)" == ".husky" ]] && grep -q 'LINKED worktree' "$WORK/rfi-lw.out"; then
  ok "refresh R5d: a linked worktree refreshes advisory-only; the main worktree's layer is untouched"
else
  bad "refresh R5d: a linked worktree refreshes advisory-only; the main worktree's layer is untouched" \
      "hooksPath=[$(git -C "$LW/main" config --get core.hooksPath 2>/dev/null)]; the shared config was repointed from a worktree whose guard could not see the main's layer"
fi
# F5: a CONFIGURED hooks dir that is absent refuses; the default's absence means nothing.
RFI_ABS="$WORK/rfi-absdir"; rfi_fixture "$RFI_ABS" ""
git -C "$RFI_ABS" config core.hooksPath "$WORK/rfi-absdir-mnt"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_ABS" >"$WORK/rfi-abs.out" 2>&1
RFI_ABS_RC=$?
if [[ "$RFI_ABS_RC" -ne 0 && "$(git -C "$RFI_ABS" config --get core.hooksPath)" != ".githooks" ]] && grep -qE 'refus' "$WORK/rfi-abs.out"; then
  ok "refresh R5e: a configured-but-absent hooks dir refuses; the guard does not vouch for what it cannot see"
else
  bad "refresh R5e: a configured-but-absent hooks dir refuses; the guard does not vouch for what it cannot see" \
      "rc=$RFI_ABS_RC hooksPath=[$(git -C "$RFI_ABS" config --get core.hooksPath 2>/dev/null)]; an unmounted layer was destroyed silently"
fi
# F6: the .// spelling reaches the exemption like its siblings.
RFI_DS="$WORK/rfi-dslash"; rfi_fixture "$RFI_DS" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DS" >/dev/null 2>&1
printf '#!/bin/sh\nexit 0\n' > "$RFI_DS/.githooks/commit-msg"; chmod +x "$RFI_DS/.githooks/commit-msg"
git -C "$RFI_DS" config core.hooksPath './/.githooks'
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DS" >"$WORK/rfi-ds.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-ds.out"; then
  ok "refresh R5f: the .//.githooks spelling reaches the already-armed exemption"
else
  bad "refresh R5f: the .//.githooks spelling reaches the already-armed exemption" \
      "a doubled slash git treats as nothing dead-ended the refresh"
fi

# =============================================================================
# ROUND 6 PINS.
# =============================================================================
# R6-1: an armed instance whose .githooks was cleaned away re-arms (the absent
# arming target is ours to create); an absent dir ELSEWHERE still refuses.
RFI_R61="$WORK/rfi-r6-cleaned"; rfi_fixture "$RFI_R61" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R61" >/dev/null 2>&1
rm -rf "$RFI_R61/.githooks"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R61" >"$WORK/rfi-r61.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-r61.out" && [[ -x "$RFI_R61/.githooks/pre-commit" ]]; then
  ok "refresh R6a: a cleaned-away .githooks re-arms; the absent arming target is ours to create"
else
  bad "refresh R6a: a cleaned-away .githooks re-arms; the absent arming target is ours to create" \
      "git clean -fdx dead-ended the instance with a refusal naming a layer that does not exist"
fi
# R6-2: a CRLF checkout of our own hooks is still ours.
RFI_R62="$WORK/rfi-r6-crlf"; rfi_fixture "$RFI_R62" ""
mkdir -p "$RFI_R62/.githooks"
for h in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
  sed $'s/$/\r/' "$ROOT/templates/git-hooks/$h" > "$RFI_R62/.githooks/$h"
done
chmod +x "$RFI_R62/.githooks/pre-commit" "$RFI_R62/.githooks/pre-merge-commit" "$RFI_R62/.githooks/pre-push"
git -C "$RFI_R62" config core.hooksPath .githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R62" >"$WORK/rfi-r62.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-r62.out"; then
  ok "refresh R6b: a CRLF checkout of our own hooks is still ours (git rewrote the bytes, not the operator)"
else
  bad "refresh R6b: a CRLF checkout of our own hooks is still ours (git rewrote the bytes, not the operator)" \
      "the ordinary Windows checkout was named foreign and every upgrade dead-ended"
fi
# R6-3: a linked worktree still receives trunk-audit.sh with the advisory half.
LW6="$WORK/rfi-r6-lw"; rm -rf "$LW6"; mkdir -p "$LW6/main/.claude/hooks"
git_init "$LW6/main"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$LW6/main/.claude/sdd.json"
git -C "$LW6/main" add -A >/dev/null 2>&1; git -C "$LW6/main" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git -C "$LW6/main" worktree add -q "$LW6/lw" -b lw6 >/dev/null 2>&1
mkdir -p "$LW6/lw/.claude/hooks"
bash "$SCRIPTS/refresh-instance.sh" --apply "$LW6/lw" >/dev/null 2>&1
if [[ -f "$LW6/lw/.claude/hooks/trunk-audit.sh" ]]; then
  ok "refresh R6c: the linked worktree receives trunk-audit.sh with the advisory half"
else
  bad "refresh R6c: the linked worktree receives trunk-audit.sh with the advisory half" \
      "the tool pre-push resolves was skipped with the boundary and every push would be refused for want of it"
fi
# R6-5: stamp's linked-worktree skip names the shared config, not the top.
STL="$WORK/stamp-r6-lw"; rm -rf "$STL"; mkdir -p "$STL/main"
git_init "$STL/main"
git -C "$STL/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$STL/main" worktree add -q "$STL/lw" -b lw6b >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STL/lw" >"$WORK/stamp-r6.out" 2>&1
STL_RC=$?
if [[ "$STL_RC" -eq 4 ]] && grep -q 'LINKED worktree' "$WORK/stamp-r6.out" && ! grep -q 'sits BELOW the top' "$WORK/stamp-r6.out"; then
  ok "stamp R6d: the linked-worktree skip names the shared config, not a top the operator is already at"
else
  bad "stamp R6d: the linked-worktree skip names the shared config, not a top the operator is already at" \
      "rc=$STL_RC; the diagnostic told the operator to go where they were standing"
fi

# =============================================================================
# ROUND 7 PINS: the arming target is inspected before it is armed.
# =============================================================================
# R7-F1: the fresh-clone state (tracked .githooks, config never clones) must
# refuse on both delivery paths, and ADOPT must truly install OUR boundary
# with a named backup rather than keeping the foreign file under an ARMED line.
R7O="$WORK/r7-origin"; rm -rf "$R7O" "$WORK/r7-clone"
git_init "$R7O"
mkdir -p "$R7O/.githooks"
printf '#!/bin/sh\necho "project scanner refuses" >&2\nexit 1\n' > "$R7O/.githooks/pre-commit"
chmod +x "$R7O/.githooks/pre-commit"
git -C "$R7O" add -A >/dev/null 2>&1; git -C "$R7O" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git clone -q "$R7O" "$WORK/r7-clone" 2>/dev/null
git -C "$WORK/r7-clone" config user.email t@t; git -C "$WORK/r7-clone" config user.name t
R7_ANS="$WORK/answers-retrofit.txt"
# get() takes the LAST match, so appending mode=retrofit is authoritative
# whatever the base file carries. The first cut sed-replaced a mode line that
# does not exist, ran mode=new, and R7a passed on a COLLISION refusal instead
# of the guard, which R7b then unmasked.
cat "$WORK/answers.txt" > "$R7_ANS"; printf 'mode=retrofit\n' >> "$R7_ANS"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$WORK/r7-clone" >"$WORK/r7-stamp.out" 2>&1
R7_RC=$?
if [[ "$R7_RC" -ne 0 && -z "$(git -C "$WORK/r7-clone" config --get core.hooksPath 2>/dev/null)" ]] \
   && grep -qE 'refusing to arm' "$WORK/r7-stamp.out" && grep -q 'project scanner' "$WORK/r7-clone/.githooks/pre-commit"; then
  ok "stamp R7a: the fresh-clone state refuses; a foreign target is not presented as an ARMED boundary"
else
  bad "stamp R7a: the fresh-clone state refuses; a foreign target is not presented as an ARMED boundary" \
      "rc=$R7_RC hooksPath=[$(git -C "$WORK/r7-clone" config --get core.hooksPath 2>/dev/null)]; every clone of a tracked-.githooks project is this state"
fi
SETLIST_ADOPT_HOOKSPATH=1 bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$WORK/r7-clone" >"$WORK/r7-adopt.out" 2>&1
if cmp -s "$ROOT/templates/git-hooks/pre-commit" "$WORK/r7-clone/.githooks/pre-commit" \
   && [[ -f "$WORK/r7-clone/.githooks/pre-commit.setlist-backup" ]] \
   && [[ "$(git -C "$WORK/r7-clone" config --get core.hooksPath)" == ".githooks" ]]; then
  ok "stamp R7b: ADOPT installs OUR boundary with a named backup; ARMED means armed with our hooks"
else
  bad "stamp R7b: ADOPT installs OUR boundary with a named backup; ARMED means armed with our hooks" \
      "the adopt path kept the foreign file under an ARMED report, or lost it without a backup"
fi
# R7-F1b: a dormant extra-name hook must not be switched on silently.
R7B="$WORK/r7-dormant"; rm -rf "$R7B"; git_init "$R7B"
mkdir -p "$R7B/.githooks"
printf '#!/bin/sh\nexit 1\n' > "$R7B/.githooks/commit-msg"; chmod +x "$R7B/.githooks/commit-msg"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R7B" >"$WORK/r7-dormant.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/r7-dormant.out" && [[ -z "$(git -C "$R7B" config --get core.hooksPath 2>/dev/null)" ]]; then
  ok "stamp R7c: arming does not silently switch on a dormant extra-name hook"
else
  bad "stamp R7c: arming does not silently switch on a dormant extra-name hook" \
      "a commit-msg that ran nowhere yesterday would run tomorrow with no line naming it"
fi
# The refresh path sees the same clone state the same way.
RFI_R7="$WORK/rfi-r7-clone"; rm -rf "$RFI_R7"
git clone -q "$R7O" "$RFI_R7" 2>/dev/null
mkdir -p "$RFI_R7/.claude/hooks"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_R7/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R7" >"$WORK/rfi-r7.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/rfi-r7.out" && grep -q 'project scanner' "$RFI_R7/.githooks/pre-commit"; then
  ok "refresh R7d: the clone state refuses identically on the refresh path; the two deliveries agree"
else
  bad "refresh R7d: the clone state refuses identically on the refresh path; the two deliveries agree" \
      "stamp and refresh returned different verdicts on byte-identical trees"
fi

# =============================================================================
# ROUND 8 PINS: the skip states write nothing live, refusals name the right
# directory, and a symlinked hook never bleeds outside the boundary.
# =============================================================================
# R8a: a linked worktree with a LIVE relative-hooksPath layer is untouched.
R8A="$WORK/r8-linkedlive"; rm -rf "$R8A"; mkdir -p "$R8A/main"
git_init "$R8A/main"
git -C "$R8A/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
mkdir -p "$R8A/main/.githooks"
printf '#!/bin/sh\nexit 1\n' > "$R8A/main/.githooks/pre-commit"; chmod +x "$R8A/main/.githooks/pre-commit"
git -C "$R8A/main" config core.hooksPath .githooks
git -C "$R8A/main" worktree add -q "$R8A/link" -b r8lb >/dev/null 2>&1
mkdir -p "$R8A/link/.githooks"
printf '#!/bin/sh\necho "LINK SCANNER refuses" >&2\nexit 1\n' > "$R8A/link/.githooks/pre-commit"
chmod +x "$R8A/link/.githooks/pre-commit"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R8A/link" >"$WORK/r8a.out" 2>&1
R8A_RC=$?
R8A_AFTER=0; git -C "$R8A/link" commit --allow-empty -qm p >/dev/null 2>&1 || R8A_AFTER=1
if [[ "$R8A_RC" -eq 4 && "$R8A_AFTER" -eq 1 ]] && grep -q 'LINK SCANNER' "$R8A/link/.githooks/pre-commit"; then
  ok "stamp R8a: the linked-worktree skip delivers no boundary files; a live per-worktree layer keeps running"
else
  bad "stamp R8a: the linked-worktree skip delivers no boundary files; a live per-worktree layer keeps running" \
      "rc=$R8A_RC after=$R8A_AFTER; the skip branch kept the destructive half and displaced a live scanner while promising inertness"
fi
# R8b: a refusal about the arming target names the target's files.
R8B="$WORK/r8-names"; rm -rf "$R8B"; git_init "$R8B"
mkdir -p "$R8B/.githooks" "$R8B/.claude/hooks"
printf '#!/bin/sh\nexit 1\n' > "$R8B/.githooks/pre-commit"
printf '#!/bin/sh\nexit 0\n' > "$R8B/.githooks/commit-msg"
chmod +x "$R8B/.githooks/"*
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R8B/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$R8B" >"$WORK/r8b.out" 2>&1
if grep -qE 'foreign: (commit-msg pre-commit|pre-commit commit-msg)' "$WORK/r8b.out"; then
  ok "refresh R8b: the arming-target refusal names the target's own files, never 'unresolvable'"
else
  bad "refresh R8b: the arming-target refusal names the target's own files, never 'unresolvable'" \
      "$(grep -o 'foreign: [^)]*' "$WORK/r8b.out" | head -1); the message listed a directory the refusal was not about"
fi
# R8c: replacing a SYMLINKED hook never touches the linked script.
R8C="$WORK/r8-symlink"; rm -rf "$R8C"; git_init "$R8C"
mkdir -p "$R8C/scripts" "$R8C/.githooks" "$R8C/.claude/hooks"
printf '#!/bin/sh\necho SCAN\nexit 1\n' > "$R8C/scripts/secrets.sh"; chmod +x "$R8C/scripts/secrets.sh"
ln -s ../scripts/secrets.sh "$R8C/.githooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R8C/.claude/sdd.json"
git -C "$R8C" config core.hooksPath .githooks
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$R8C" >"$WORK/r8c.out" 2>&1
if grep -q 'echo SCAN' "$R8C/scripts/secrets.sh" && [[ ! -L "$R8C/.githooks/pre-commit" ]] \
   && cmp -s "$ROOT/templates/git-hooks/pre-commit" "$R8C/.githooks/pre-commit" \
   && grep -q 'was a symlink' "$WORK/r8c.out"; then
  ok "refresh R8c: the adopt path replaces a symlinked hook without touching the linked script, and says so"
else
  bad "refresh R8c: the adopt path replaces a symlinked hook without touching the linked script, and says so" \
      "cp followed the link and destroyed a file outside .githooks/ while claiming the previous file was kept"
fi

# =============================================================================
# ROUND 9 PINS.
# =============================================================================
# R9a: a DANGLING symlink at a hook name never causes a write at its target.
R9A="$WORK/r9-dangling"; rm -rf "$R9A"; mkdir -p "$R9A/outside"; git_init "$R9A/proj"
mkdir -p "$R9A/proj/.githooks" "$R9A/proj/.claude/hooks"
ln -s ../../outside/planted "$R9A/proj/.githooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R9A/proj/.claude/sdd.json"
git -C "$R9A/proj" config core.hooksPath .githooks
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$R9A/proj" >"$WORK/r9a.out" 2>&1
if [[ ! -e "$R9A/outside/planted" && ! -L "$R9A/proj/.githooks/pre-commit" ]] \
   && cmp -s "$ROOT/templates/git-hooks/pre-commit" "$R9A/proj/.githooks/pre-commit" \
   && grep -q 'DANGLING' "$WORK/r9a.out"; then
  ok "refresh R9a: a dangling symlink is removed, named, and nothing is written at its target"
else
  bad "refresh R9a: a dangling symlink is removed, named, and nothing is written at its target" \
      "planted=$([[ -e "$R9A/outside/planted" ]] && echo yes || echo no); cp resolved a dangling link and created our hook body at a path the repository chose"
fi
# R9b: a Closing report inside an HTML comment is invisible to the gate the
# way it is to every renderer; a one-line comment in a real section is inert.
# Self-contained: qa_atx_run is defined in the qa corpus section BELOW this
# point in the file, so the readers are extracted inline here.
R9B_TF="$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")"
R9B_QA="$(grep -m1 -E '^[[:space:]]*QA_PASS1_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*QA_PASS1_AWK='//" -e "s/'$//")"
R9B_STATE="$(printf '# S\n\n<!--\n## Closing report\n\n```qa-pass-1\n1: PASS\n```\n-->\n' | awk "$R9B_TF" | awk "$R9B_QA")"
R9B_CTL="$(printf '## Closing report\n\n<!-- reviewed -->\n\n```qa-pass-1\n1: PASS\n```\n' | awk "$R9B_TF" | awk "$R9B_QA")"
if [[ "$R9B_STATE" == "none" && "$R9B_CTL" == "ok" ]]; then
  ok "qa R9b: an HTML-commented Closing report is invisible to the gate; a one-line comment is inert"
else
  bad "qa R9b: an HTML-commented Closing report is invisible to the gate; a one-line comment is inert" \
      "commented=$R9B_STATE (want none) control=$R9B_CTL (want ok); a spec that renders as nothing satisfied every close condition"
fi
# R9c: report mode warns about a refusal apply will make, even when the
# boundary files are current (the unreadable-armed state).
R9C="$WORK/r9-warn"; rfi_fixture "$R9C" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$R9C" >/dev/null 2>&1
chmod 300 "$R9C/.githooks"
# THIS IS THE ONE A CONTAINER ACTUALLY REPORTED (V1b): `808/1` on this assertion,
# against a tree this host runs green, because chmod is a no-op against uid 0 so
# .githooks stayed readable, apply had nothing to refuse, and report mode
# correctly said "present and byte-identical, config already set" -- which is
# verbatim the text the container read as a failure.
if perm_fixture_bites "$R9C/.githooks" "refresh R9c"; then
  bash "$SCRIPTS/refresh-instance.sh" "$R9C" >"$WORK/r9c.out" 2>&1
  chmod 755 "$R9C/.githooks"
  if grep -q 'apply will REFUSE' "$WORK/r9c.out"; then
    ok "refresh R9c: report mode names the refusal apply will make; no all-clear over a refusing state"
  else
    bad "refresh R9c: report mode names the refusal apply will make; no all-clear over a refusing state" \
        "the report said present-and-set while apply exits 1, the round-5 divergence class recurred"
  fi
else
  chmod 755 "$R9C/.githooks"
fi
# R9d: stamp's skip notes no longer claim files that were not delivered.
R9D="$WORK/r9-note"; rm -rf "$R9D"; mkdir -p "$R9D"; git_init "$R9D"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R9D/app" >"$WORK/r9d.out" 2>"$WORK/r9d.err"
if ! grep -q 'are stamped into .githooks' "$WORK/r9d.err" && grep -q 'NOT delivered here' "$WORK/r9d.err"; then
  ok "stamp R9d: the skip note says the boundary was not delivered, which is what happened"
else
  bad "stamp R9d: the skip note says the boundary was not delivered, which is what happened" \
      "a sentence that is false when it prints, contradicted by the same run's stdout"
fi

# =============================================================================
# ROUND 11 (CONFIRMING) PINS: the boundary PATH itself, not just its files.
# The reader and ownership surfaces SURVIVED this round; delivery yielded a
# finite new class (the .githooks path being a symlink or a directory).
# =============================================================================
# R11a: a .githooks that is a symlink to a shared dir refuses on both paths;
# nothing is written at the link target.
R11A="$WORK/r11-symdir"; rm -rf "$R11A"; mkdir -p "$R11A/repo" "$R11A/shared"
git_init "$R11A/repo"
printf '#!/bin/sh\nexit 1\n' > "$R11A/shared/pre-push"; chmod 644 "$R11A/shared/pre-push"
ln -s "$R11A/shared" "$R11A/repo/.githooks"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R11A/repo" >"$WORK/r11a.out" 2>&1
if [[ $? -ne 0 ]] && grep -qi 'SYMLINK' "$WORK/r11a.out" && [[ ! -e "$R11A/shared/pre-commit" ]]; then
  ok "stamp R11a: a symlinked .githooks refuses and writes nothing at the link target"
else
  bad "stamp R11a: a symlinked .githooks refuses and writes nothing at the link target" \
      "the boundary was written through the symlink, outside the repository, under ARMED"
fi
# R11b: a .githooks/<hook> that is a directory refuses on the refresh path.
R11B="$WORK/r11-dirhook"; rm -rf "$R11B"; mkdir -p "$R11B/.claude/hooks" "$R11B/.githooks/pre-commit"
git_init "$R11B"; git -C "$R11B" config core.hooksPath .githooks
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R11B/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$R11B" >"$WORK/r11b.out" 2>&1
if [[ $? -ne 0 ]] && grep -qi 'DIRECTORY' "$WORK/r11b.out"; then
  ok "refresh R11b: a hook name that is a directory refuses instead of reporting delivered"
else
  bad "refresh R11b: a hook name that is a directory refuses instead of reporting delivered" \
      "cp wrote INTO the directory, the -x guard passed it, and the run claimed delivery"
fi
# R11c: stamp into a linked worktree still delivers trunk-audit.sh (advisory).
R11C="$WORK/r11-lwta"; rm -rf "$R11C"; mkdir -p "$R11C/main"
git_init "$R11C/main"
git -C "$R11C/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$R11C/main" worktree add -q "$R11C/wt" -b r11feat >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R11C/wt" >/dev/null 2>&1
if [[ -f "$R11C/wt/.claude/hooks/trunk-audit.sh" ]]; then
  ok "stamp R11c: a linked worktree still receives trunk-audit.sh, so its live pre-push can run"
else
  bad "stamp R11c: a linked worktree still receives trunk-audit.sh, so its live pre-push can run" \
      "the advisory tool was gated with the boundary and every push in the linked worktree was refused"
fi
# R11d: report mode does not warn "will REFUSE" when ADOPT is set.
R11D="$WORK/r11-adopt-report"; rfi_fixture "$R11D" .husky
if SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" "$R11D" 2>&1 | grep -qi 'will REFUSE'; then
  bad "refresh R11d: report mode under ADOPT does not threaten a refusal apply will not make" \
      "the report said --apply will REFUSE while apply with the same env adopts"
else
  ok "refresh R11d: report mode under ADOPT does not threaten a refusal apply will not make"
fi

# F12: trunk-audit.sh is a delivered file and must appear in the report.
RFI="$WORK/rfi-ta"; rfi_fixture "$RFI" ""
printf '#!/bin/sh\necho mine\n' > "$RFI/.claude/hooks/trunk-audit.sh"
printf '#!/bin/sh\necho prettier\n' > "$RFI/.claude/hooks/prettier.sh"
chmod 644 "$RFI/.claude/hooks/prettier.sh"
git -C "$RFI" add -A >/dev/null 2>&1; git -C "$RFI" commit -qm foreign >/dev/null 2>&1
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-ta.out" 2>&1
RFI_F12=""
grep -q 'trunk-audit' "$WORK/rfi-ta.out" || RFI_F12="$RFI_F12 not-reported"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
[[ -x "$RFI/.claude/hooks/prettier.sh" ]] && RFI_F12="$RFI_F12 chmod-globbed-a-foreign-file"
if [[ -z "$RFI_F12" ]]; then
  ok "refresh c: trunk-audit.sh is reported before it is overwritten, and the chmod does not glob foreign files"
else
  bad "refresh c: trunk-audit.sh is reported before it is overwritten, and the chmod does not glob foreign files" \
      "problems:$RFI_F12; report-first is the stated discipline and a delivered file that appears in no report is outside it"
fi

# GIT IS A DEPENDENCY TOO, AND ITS VERSION IS PART OF IT (leg F5).
#
# `git branch --show-current` arrived in git 2.22 (2019). Below that it exits
# 129 and prints nothing useful, the gates read an empty branch, the empty value
# never equals the trunk, and they take their "ordinary feature work" exit. Not
# a reported allow carrying a code, which is what the advisory contract
# promises: total SILENCE, zero bytes, no code and no reason.
#
# close-gate.sh spends sixty lines establishing that a dependency which cannot
# produce its value must route to a REPORTED refusal, because "the empty result
# is indistinguishable from nothing to govern, and absence reads as permission".
# git was the one dependency never held to that rule.
#
# The remedy is not a probe but a query that predates the floor:
# `symbolic-ref --quiet --short HEAD`, which is what the git-hook layer has
# always used, and which is byte-identical in both cases that matter (a branch
# name when on a branch, empty when detached). Measured before swapping.
#
# The guarantee layer holds under the same shim, which is why this is a
# cooperative gap rather than a bypass, and the last assertion pins that.
GITOLD="$WORK/oldgit"; rm -rf "$GITOLD"; mkdir -p "$GITOLD"
{ printf '#!/bin/sh\n'
  printf 'for a in "$@"; do\n'
  printf '  if [ "$a" = "--show-current" ]; then\n'
  printf '    echo "error: unknown option \\`show-current%s" >&2\n' "'"
  printf '    exit 129\n'
  printf '  fi\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$(command -v git)"; } > "$GITOLD/git"
chmod +x "$GITOLD/git"

GV="$WORK/gitver"; rm -rf "$GV"; mkdir -p "$GV/src" "$GV/specs" "$GV/.claude"
git_init "$GV"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$GV/.claude/sdd.json"
printf 'x\n' > "$GV/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$GV/specs/STATUS.md"
git -C "$GV" add -A >/dev/null 2>&1; git -C "$GV" commit -qm stamp >/dev/null 2>&1
git -C "$GV" checkout -q -b spec/0001-thing main
printf 'export const s = 1\n' > "$GV/src/s.js"
git -C "$GV" add -A >/dev/null 2>&1; git -C "$GV" commit -qm work >/dev/null 2>&1
git -C "$GV" checkout -q main

GV_MERGE="$(jq -nc --arg c 'git merge --no-ff spec/0001-thing' '{tool_name:"Bash",tool_input:{command:$c}}')"
GV_WRITE="$(jq -nc --arg p "$GV/src/a.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"

# CONTROL: on modern git each gate reports its code. Without this the silence
# below could mean "nothing to say" rather than "went blind".
GV_CTL=""
printf %s "$GV_MERGE" | CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/close-gate.sh" 2>&1 | grep -q 'CG-' || GV_CTL="$GV_CTL close-gate"
printf %s "$GV_WRITE" | CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/scope-hook.sh" 2>&1 | grep -q 'SH-' || GV_CTL="$GV_CTL scope-hook"
if [[ -z "$GV_CTL" ]]; then
  ok "git version control: on current git both session gates report a code for this fixture"
else
  bad "git version control: on current git both session gates report a code for this fixture" \
      "these said nothing even on modern git:$GV_CTL, so the shim cases below prove nothing"
fi

GV_BLIND=""
printf %s "$GV_MERGE" | PATH="$GITOLD:$PATH" CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/close-gate.sh" 2>&1 | grep -q 'CG-' || GV_BLIND="$GV_BLIND close-gate"
printf %s "$GV_WRITE" | PATH="$GITOLD:$PATH" CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/scope-hook.sh" 2>&1 | grep -q 'SH-' || GV_BLIND="$GV_BLIND scope-hook"
if [[ -z "$GV_BLIND" ]]; then
  ok "git version a: the session gates still report on a git too old for branch --show-current"
else
  bad "git version a: the session gates still report on a git too old for branch --show-current" \
      "these went SILENT, zero bytes, no code and no reason:$GV_BLIND; absence reads as permission, which is the rule these hooks state and did not hold git to"
fi

# The guarantee layer under the same shim. This is what bounds the severity.
GVG="$WORK/gitver-hooks"; rm -rf "$GVG"; cp -R "$GV" "$GVG"; mkdir -p "$GVG/.githooks"
cp "$ROOT"/templates/git-hooks/* "$GVG/.githooks/"; chmod +x "$GVG"/.githooks/*
git -C "$GVG" config core.hooksPath .githooks; git -C "$GVG" config merge.ff false
( cd "$GVG" && PATH="$GITOLD:$PATH" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0001-thing ) >/dev/null 2>&1
if git -C "$GVG" cat-file -e main:src/s.js 2>/dev/null; then
  bad "git version b: the GUARANTEE layer still refuses on an old git" \
      "an unclosed spec merged onto the trunk under the shim, which would make this a bypass rather than a reporting gap"
else
  ok "git version b: the GUARANTEE layer still refuses on an old git"
fi

# ANY '<' READ AS THE UNFILLED PLACEHOLDER (leg F11), at all three layers.
#
# The test was `case "$answer" in *"<"*) answer="" ;;` in the library, the same
# substring test in close-gate.sh, and `grep -q '<'` in the audit. It was
# written to catch the template's own `<updated in this commit | no impact>`
# and it fires on any '<' in ordinary prose: a comparison, a generic, an HTML
# comment, an arrow. Measured: `updated in this commit (added <auth> box)` was
# refused SLH-DIAGRAM-UNANSWERED at merge time.
#
# This field has now been corrected three times, twice by repairing the one
# spelling that was reported, so the rule is asserted ACROSS THE VALUE SPACE
# rather than at any spelling. The new rule strips <...> spans and then requires
# the answer, so the genuine unfilled template strips to nothing and stays
# refused while prose containing '<' does not.
#
# Both directions in one table, because a rule that only stops refusing is a
# weakened check rather than a fixed one.
diag_fixture() { # diag_fixture <dir> <diagram-answer>
  local d="$1" ans="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" checkout -q -b spec/0005-diag main
  printf 'export const d = 1\n' > "$d/src/d.js"
  { printf '# Spec 0005\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n'
    printf -- '- Architecture diagram: %s\n' "$ans"; } > "$d/specs/0005-diag.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0005 | D | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0005" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
DIAG_MERGE_BAD=""; DIAG_AUDIT_BAD=""
# values that MUST be accepted: a real answer, whatever else the line contains
while IFS='|' read -r dv; do
  [[ -n "$dv" ]] || continue
  DGD="$WORK/diag-ok"; diag_fixture "$DGD" "$dv"
  ( cd "$DGD" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0005-diag ) >/dev/null 2>&1
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null || DIAG_MERGE_BAD="$DIAG_MERGE_BAD [$dv]"
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null && {
    bash "$SCRIPTS/trunk-audit.sh" "$DGD" >/dev/null 2>&1 || DIAG_AUDIT_BAD="$DIAG_AUDIT_BAD [$dv]"; }
done <<'DIAGOK'
no impact
updated in this commit
updated in this commit (added <auth> box)
no impact; the a < b case is unchanged
DIAGOK
# THE ANSWER MUST COME FIRST (F6-2026, 2.3.0 round 1), and one shape MOVED out
# of the corpus above to here rather than being dropped quietly.
#
# The field was matched with an UNANCHORED grep, so a line stating the OPPOSITE
# of an answer satisfied it. The fix anchors the answer to the START of the
# field's value, which keeps every documented shape (an answer with a
# parenthetical, an answer with a trailing clause) and refuses two: a line that
# merely CONTAINS an answer somewhere, and a line that contradicts one.
#
# `Foo<T> generic added, updated in this commit` was in the accepted corpus and
# is now refused. That is a real contract change and it is asserted here rather
# than left implicit: the field answers a question, so the answer goes first,
# and commentary follows it.
DIAG_FIRST_BAD=""
while IFS= read -r dv; do
  [[ -n "$dv" ]] || continue
  dva="$(printf '%s' "$dv" | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//')"
  if printf '%s' "$dva" | grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)'; then
    DIAG_FIRST_BAD="$DIAG_FIRST_BAD [$dv]"
  fi
done <<'DIAGNO'
this is NOT no impact, revisit it later
Foo<T> generic added, updated in this commit
revisit the diagram: the auth box is wrong
DIAGNO
if [[ -z "$DIAG_FIRST_BAD" ]]; then
  ok "diagram value a2 (F6-2026): a line that merely CONTAINS or CONTRADICTS an answer does not satisfy the field"
else
  bad "diagram value a2 (F6-2026): a line that merely CONTAINS or CONTRADICTS an answer does not satisfy the field" \
      "these still satisfied it:$DIAG_FIRST_BAD"
fi
if [[ -z "$DIAG_MERGE_BAD" && -z "$DIAG_AUDIT_BAD" ]]; then
  ok "diagram value a: an answer with trailing commentary is accepted; the answer must come FIRST"
else
  bad "diagram value a: an answer with trailing commentary is accepted; the answer must come FIRST" \
      "merge refused:${DIAG_MERGE_BAD:- none}  audit flagged:${DIAG_AUDIT_BAD:- none}; a '<' in prose is not the unfilled template"
fi

# values that MUST be refused, including the template itself
DIAG_LOOSE=""
while IFS='|' read -r dv; do
  [[ -n "$dv" ]] || continue
  DGD="$WORK/diag-bad"; diag_fixture "$DGD" "$dv"
  ( cd "$DGD" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0005-diag ) >/dev/null 2>&1
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null && DIAG_LOOSE="$DIAG_LOOSE [$dv]"
done <<'DIAGBAD'
<updated in this commit | no impact>
<updated in this commit>
TBD
n/a
see structure.md
<TBD>
DIAGBAD
if [[ -z "$DIAG_LOOSE" ]]; then
  ok "diagram value b: an UNANSWERED field is still refused, template placeholder included"
else
  bad "diagram value b: an UNANSWERED field is still refused, template placeholder included" \
      "these merged:$DIAG_LOOSE, so the fix for the false positive weakened the check instead of correcting it"
fi

# THE REMOTE'S TRUNK RESOLVED FROM A CACHED CONVENIENCE REF (leg F7).
#
# REMOTE_TRUNK came only from `git symbolic-ref refs/remotes/$1/HEAD`. git
# passes $1 as the literal URL when a push names a URL, so no such ref exists;
# `git remote set-head origin -d` removes it for the by-name spelling. Either
# way REMOTE_TRUNK went empty, no pushed ref matched a trunk name, PUSH_REFS
# stayed empty, and control fell to the else branch which audits the LOCAL
# trunk and reports it clean. A true statement about a ref the push never
# touched, printed as though it were an audit of the push.
#
# Measured: unclosed feature code reached the REMOTE trunk at rc=0 while the
# hook printed "audited 0 commits on main ... 0 violations".
#
# Precondition that bounds the severity, stated because it is not obvious: the
# remote's trunk name must DIFFER from the recorded local trunk. Where they
# agree the local-name test still catches it, which the (c) control pins.
f7_inst() { # f7_inst <dir> <remote-default-branch>
  local d="$1" rdefault="$2"
  rm -rf "$d" "$d-rem.git"
  git init -q --bare -b "$rdefault" "$d-rem.git"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  # pre-push REFUSES when it cannot find the audit, and correctly so. The first
  # run of this harness omitted it and refused everything including its own
  # controls, which is the tell that a fixture is wrong rather than a finding.
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" remote add origin "$d-rem.git"
  SETLIST_SKIP_TRUNK_AUDIT=1 git -C "$d" push -q origin "main:$rdefault" >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0004-bad main
  printf 'export const bad = 1\n' > "$d/src/bad.js"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "unclosed work" >/dev/null 2>&1
}
f7_on_remote() { git -C "$1-rem.git" cat-file -e "$2:src/bad.js" 2>/dev/null; }

# (a) by URL, and (b) by name with origin/HEAD deleted. Both must be refused.
F7_BAD=""
F7D="$WORK/f7-url"; f7_inst "$F7D" master
( cd "$F7D" && git push "$F7D-rem.git" spec/0004-bad:refs/heads/master ) >"$WORK/f7a.out" 2>&1
f7_on_remote "$F7D" master && F7_BAD="$F7_BAD by-url"
F7D="$WORK/f7-nohead"; f7_inst "$F7D" master
git -C "$F7D" remote set-head origin -d >/dev/null 2>&1
( cd "$F7D" && git push origin spec/0004-bad:refs/heads/master ) >"$WORK/f7b.out" 2>&1
f7_on_remote "$F7D" master && F7_BAD="$F7_BAD by-name-no-HEAD"
if [[ -z "$F7_BAD" ]]; then
  ok "remote trunk a: a push that would become the remote trunk is audited however the remote is named"
else
  bad "remote trunk a: a push that would become the remote trunk is audited however the remote is named" \
      "unclosed feature code reached the remote trunk by:$F7_BAD, while the hook reported [$(grep -oE 'audited [^,]*' "$WORK/f7a.out" | head -1)]"
fi

# THE UNREACHABLE BRANCH IS LIVE, and TWO measurements were needed to say what
# actually reaches it.
#
# First: git rejects a plainly unreachable remote before pre-push runs, so that
# is not the case. The shape that arrives is a remote whose FETCH url is
# unreachable while its PUSH url works (`git remote set-url --push`).
#
# Second, and this is what the first cut of this assertion got wrong: the cached
# refs/remotes/<name>/HEAD is consulted before the live query, so the branch is
# reached only when the cache is ALSO absent. This fixture fetches, so it has a
# cached HEAD, and without deleting it the hook resolved the trunk from cache,
# audited the clean local trunk and allowed the push. The assertion failed while
# the code was right, which is the correct way round for that to happen.
#
# Pinned so nobody deletes the branch believing it is dead code. The push here
# WOULD have succeeded, so the refusal is a real cost, taken because the
# alternative is F7's fail-open.
# THIRD correction to this one assertion, and the code was right every time.
# The landing probe first read master:src/app.js, which f7_inst had ALREADY put
# on the remote when it seeded it, so "landed" was true before the push under
# test ran at all. A probe must look for something only the operation under test
# could have produced, so main gains a file here and that file is the probe.
F7D="$WORK/f7-spliturl"; f7_inst "$F7D" master
git -C "$F7D" checkout -q main
printf 'export const fresh = 1\n' > "$F7D/src/fresh.js"
git -C "$F7D" add -A >/dev/null 2>&1
git -C "$F7D" -c core.hooksPath=/dev/null commit -qm "a commit only this test makes" >/dev/null 2>&1
git -C "$F7D" remote set-head origin -d >/dev/null 2>&1
git -C "$F7D" remote set-url origin /nope/nothere.git
git -C "$F7D" remote set-url --push origin "$F7D-rem.git"
( cd "$F7D" && git push origin main:refs/heads/master ) >"$WORK/f7f.out" 2>&1
if grep -q 'SLH-REMOTE-UNRESOLVED' "$WORK/f7f.out" && ! git -C "$F7D-rem.git" cat-file -e refs/heads/master:src/fresh.js 2>/dev/null; then
  ok "remote trunk b: a remote whose trunk cannot be resolved refuses by name instead of auditing the wrong ref"
else
  bad "remote trunk b: a remote whose trunk cannot be resolved refuses by name instead of auditing the wrong ref" \
      "expected SLH-REMOTE-UNRESOLVED and src/fresh.js NOT on the remote; got [$(grep -oE 'SLH-[A-Z-]+|audited [^,]*' "$WORK/f7f.out" | head -1)] and landed=$(git -C "$F7D-rem.git" cat-file -e refs/heads/master:src/fresh.js 2>/dev/null && echo yes || echo no)"
fi

# (c) CONTROL: where the two trunk names agree, the local-name test catches it.
F7D="$WORK/f7-samename"; f7_inst "$F7D" main
( cd "$F7D" && git push "$F7D-rem.git" spec/0004-bad:refs/heads/main ) >/dev/null 2>&1
if f7_on_remote "$F7D" main; then
  bad "remote trunk control: a URL push is caught when the remote trunk shares the local name" \
      "even the pre-existing local-name test did not fire, so the cases above prove nothing"
else
  ok "remote trunk control: a URL push is caught when the remote trunk shares the local name"
fi

# (d) and (e) FALSE-DENIAL CONTROLS. Ordinary pushes must keep working, and
# this is the direction a fix here is most likely to break.
F7_FD=""
F7D="$WORK/f7-ownname"; f7_inst "$F7D" master
( cd "$F7D" && git push origin spec/0004-bad ) >"$WORK/f7d.out" 2>&1
git -C "$F7D-rem.git" cat-file -e refs/heads/spec/0004-bad:src/bad.js 2>/dev/null || F7_FD="$F7_FD spec-branch-to-own-name"
F7D="$WORK/f7-topic"; f7_inst "$F7D" master
git -C "$F7D" checkout -q main
( cd "$F7D" && git push origin main:refs/heads/mytopic ) >"$WORK/f7e.out" 2>&1
git -C "$F7D-rem.git" cat-file -e refs/heads/mytopic:src/app.js 2>/dev/null || F7_FD="$F7_FD trunk-to-non-trunk-ref"
if [[ -z "$F7_FD" ]]; then
  ok "remote trunk controls: pushing a spec branch to its own name, and the trunk to a non-trunk ref, both still succeed"
else
  bad "remote trunk controls: pushing a spec branch to its own name, and the trunk to a non-trunk ref, both still succeed" \
      "these were refused:$F7_FD, which is the false-denial direction and worse than the hole above"
fi

# THE SPEC FILE IS PICKED BY SORT ORDER, WITH NO UNIQUENESS CHECK (leg F6).
#
# slh_verify_close took `grep -E "^specs/${num}[a-z]*-" | head -n1`. Both
# `git diff --cached --name-only` and `git ls-files` emit sorted paths, and
# `specs/0002-other-design.md` sorts BEFORE `specs/0002-other.md` because '-'
# is 0x2d and '.' is 0x2e, so a companion document always wins the pick.
#
# It fails in BOTH directions, and both were measured:
#   a non-compliant spec merged clean once a compliant-looking companion existed
#   a fully compliant close was refused "spec 0003 has no Closing report",
#     which is false about the file it names
#
# The second half is the dangerous one. The operator opens the file, sees the
# Closing report the hook says is absent, concludes the hook is broken, and
# reaches for SETLIST_SKIP_HOOKS=1, which the library's own comment calls the
# road from one confusing message to a disabled boundary.
#
# The sibling ADVISORY gate already refuses this input by name at
# close-gate.sh:1512 (CG-SPEC-DUPLICATE). The guarantee layer never got it.
#
# SECOND BUG IN THE SAME PATTERN: `${num}[a-z]*-` over-matches. Part 4's split
# convention makes `0002b` a DISTINCT spec carrying its own STATUS.md row, so
# for a row numbered 0002 the file specs/0002b-x.md is somebody else's spec and
# must not be a candidate at all. The last assertion pins that.
f6_inst() { # f6_inst <dir>
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}
f6_compliant() { printf '# Spec %s\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' "$1"; }
f6_row() { printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| %s | T | CLOSED | done |\n' "$1"; }
# f6_run <dir> <num> -> merges a spec branch, leaves F6_OUT and F6_LANDED
f6_run() {
  local d="$1" n="$2"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close $n" >/dev/null 2>&1
  git -C "$d" checkout -q main
  F6_OUT="$( cd "$d" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m "spec/$n" 2>&1 )" # fail-open-ok: the refusal text is the evidence; F6_LANDED below is the decision
  if git -C "$d" cat-file -e "main:src/$n.js" 2>/dev/null; then F6_LANDED=1; else F6_LANDED=0; fi
}

# CONTROL: a non-compliant spec ALONE is refused, and a lone compliant one lands.
F6D="$WORK/f6-ctl-bad"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
printf '# Spec 0002\n\nStatus: CLOSED\n\nnothing here.\n' > "$F6D/specs/0002-other.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
F6_CTL=""
[[ "$F6_LANDED" -eq 1 ]] && F6_CTL="$F6_CTL noncompliant-landed"
F6D="$WORK/f6-ctl-good"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0004 main
f6_compliant 0004 > "$F6D/specs/0004-fourth.md"
f6_row 0004 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0004.js"
f6_run "$F6D" 0004
[[ "$F6_LANDED" -eq 0 ]] && F6_CTL="$F6_CTL compliant-refused"
if [[ -z "$F6_CTL" ]]; then
  ok "spec pick control: a lone non-compliant spec is refused and a lone compliant close lands"
else
  bad "spec pick control: a lone non-compliant spec is refused and a lone compliant close lands" \
      "the fixtures are wrong:$F6_CTL, so the duplicate cases below prove nothing"
fi

# ATTACK 1: a companion doc launders a non-compliant close.
F6D="$WORK/f6-launder"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
printf '# Spec 0002\n\nStatus: CLOSED\n\nnothing here.\n' > "$F6D/specs/0002-other.md"
f6_compliant 0002 > "$F6D/specs/0002-other-design.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
if [[ "$F6_LANDED" -eq 0 ]]; then
  ok "spec pick a: a companion document cannot launder a non-compliant close onto the trunk"
else
  bad "spec pick a: a companion document cannot launder a non-compliant close onto the trunk" \
      "the merge LANDED and the trunk now carries a spec whose body is: $(git -C "$F6D" show main:specs/0002-other.md 2>/dev/null | tail -1)"
fi

# ATTACK 2, the mirror: a compliant close plus an ordinary notes file. It is
# still refused, which is right because the input is genuinely ambiguous, but
# the REASON must be the true one rather than a false claim about the file.
F6D="$WORK/f6-mirror"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0003 main
f6_compliant 0003 > "$F6D/specs/0003-third.md"
printf '# Notes for 0003\n\nJust ordinary notes, no report here.\n' > "$F6D/specs/0003-third-notes.md"
f6_row 0003 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0003.js"
f6_run "$F6D" 0003
if printf '%s' "$F6_OUT" | grep -q 'SLH-SPEC-DUPLICATE'; then
  ok "spec pick b: two files matching one spec number are refused as a DUPLICATE, not as a missing report"
else
  bad "spec pick b: two files matching one spec number are refused as a DUPLICATE, not as a missing report" \
      "the reason given was [$(printf '%s' "$F6_OUT" | grep -oE 'SLH-[A-Z-]+' | head -1)], and a message that is false about the file it names is what sends an operator to SETLIST_SKIP_HOOKS=1"
fi

# THE SPLIT SIBLING IS NOT A DUPLICATE. Part 4 makes 0002b its own spec with
# its own row, so a compliant 0002 must still close while 0002b sits beside it.
F6D="$WORK/f6-sibling"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
f6_compliant 0002 > "$F6D/specs/0002-first.md"
printf '# Spec 0002b\n\nStatus: QUEUED\n\nparked remainder.\n' > "$F6D/specs/0002b-parked.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
if [[ "$F6_LANDED" -eq 1 ]]; then
  ok "spec pick c: a suffixed split sibling is a different spec, not a duplicate of its parent"
else
  bad "spec pick c: a suffixed split sibling is a different spec, not a duplicate of its parent" \
      "a compliant close of 0002 was refused because 0002b exists beside it [$(printf '%s' "$F6_OUT" | grep -oE 'SLH-[A-Z-]+' | head -1)], which breaks Part 4's own split convention"
fi

# THE AUDIT'S TOOLCHAIN PROBE (2026-08-07 leg, F2).
#
# setlist-hook-lib.sh has carried slh_require_toolchain since the run that
# measured a broken grep letting an unclosed spec merge at rc=0 in silence. It
# was wired into pre-commit, pre-merge-commit and pre-push and NOT into
# trunk-audit.sh, which is the standalone invocation the README documents and
# the one any CI job would call.
#
# The failure is not a missed detection, it is a FLIPPED verdict: line 280 read
# `wc -w | tr -d ' '`, a broken tr yields the empty string, `[[ "" -lt 2 ]]` is
# true in bash arithmetic, so every merge commit was classified as a non-merge,
# skipped the whole merged-parent loop, and landed in the "clean" bucket at
# exit 0. The script has an "unverifiable" category for the cases history
# cannot decide, and the degraded path did not route there either.
#
# Both directions, because a probe that refuses everything is not a fix.
ta_fixture() { # ta_fixture <dir> <good|bad>
  local d="$1" kind="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  git -C "$d" config merge.ff false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-first main
  printf 'export const f = 1\n' > "$d/src/f.js"
  if [[ "$kind" == good ]]; then
    printf '# Spec 0001 - First\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-first.md"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$d/specs/STATUS.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm work >/dev/null 2>&1
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
}
# The broken tools. `tr` exiting 127 is the dyld failure the leg used; `tr`
# exiting 0 and printing nothing is the quieter half, and both must be caught,
# because a probe that only checks the exit status misses the second.
TAB="$WORK/ta-brokenbin"; rm -rf "$TAB"; mkdir -p "$TAB/loud" "$TAB/quiet"
printf '#!/bin/sh\necho "dyld: Library not loaded" >&2\nexit 127\n' > "$TAB/loud/tr"
printf '#!/bin/sh\nexit 0\n' > "$TAB/quiet/tr"
chmod +x "$TAB/loud/tr" "$TAB/quiet/tr"

TAV="$WORK/ta-violating"; ta_fixture "$TAV" bad
TAC="$WORK/ta-clean"; ta_fixture "$TAC" good

# CONTROL, healthy toolchain, both directions. Without this the cases below
# prove nothing: a fixture that is clean either way would pass a broken probe.
TA_CTL=""
bash "$SCRIPTS/trunk-audit.sh" "$TAV" >/dev/null 2>&1 && TA_CTL="$TA_CTL violating-read-as-clean"
bash "$SCRIPTS/trunk-audit.sh" "$TAC" >/dev/null 2>&1 || TA_CTL="$TA_CTL clean-read-as-violating"
if [[ -z "$TA_CTL" ]]; then
  ok "audit toolchain control: with a healthy toolchain the audit refuses the violating trunk and passes the clean one"
else
  bad "audit toolchain control: with a healthy toolchain the audit refuses the violating trunk and passes the clean one" \
      "the fixtures are wrong:$TA_CTL, so the broken-tool cases below prove nothing"
fi

TA_BAD=""
for ta_k in loud quiet; do
  TA_OUT="$(PATH="$TAB/$ta_k:$PATH" bash "$SCRIPTS/trunk-audit.sh" "$TAV" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: the rc suffix is what the test reads, and a crash shows up as neither 0 nor a TOOLCHAIN code
  printf '%s' "$TA_OUT" | grep -q '|rc=0$' && TA_BAD="$TA_BAD $ta_k:exit-0"
  printf '%s' "$TA_OUT" | grep -q 'SLH-NO-TOOLCHAIN' || TA_BAD="$TA_BAD $ta_k:no-reason"
done
if [[ -z "$TA_BAD" ]]; then
  ok "audit toolchain a: a broken tr stops the audit with SLH-NO-TOOLCHAIN instead of reporting a violating trunk clean"
else
  bad "audit toolchain a: a broken tr stops the audit with SLH-NO-TOOLCHAIN instead of reporting a violating trunk clean" \
      "these degraded runs did not refuse or did not say why:$TA_BAD, and exit 0 is what CI reads as a pass"
fi

# EVERY TOOL THE AUDIT DECIDES WITH, NOT THE FOUR THE LIBRARY HAPPENED TO NAME
# (2026-08-08 pre-stress, found on zero leg quota).
#
# The F2 fix probed awk, sed, tr and grep, because those are what the library
# probes. The audit also DECIDES with cut and wc: line 314 built the parent
# list with `cut -d' ' -f2-` and line 315 counted it with `wc -w`. A broken cut
# yields the empty string, NPAR becomes 0, `[[ 0 -lt 2 ]]` is true, so every
# merge commit was classified a non-merge, skipped the merged-parent loop, and
# the violating trunk was reported CLEAN at exit 0 with no reason printed.
#
# That is the identical fail-open the tr bug had, one tool over, in the fix for
# the tr bug. Measured: `cut` broken loud (exit 127) and quiet (exit 0, no
# output) both produced `rc=0, 1 clean, 0 violations` on a trunk the healthy
# audit refuses.
#
# The guarantee layer does NOT share this: all twenty broken-tool cases against
# a merge that must be refused stayed refused, so this is the standalone audit
# only. Asserted across the full decision-path tool set rather than at the one
# spelling that was found.
TAD_BAD=""
for ta_t in cut wc head tail sort tr awk sed grep; do
  for ta_f in loud quiet; do
    TAP="$WORK/ta-dep-$ta_t-$ta_f"; rm -rf "$TAP"; mkdir -p "$TAP"
    if [[ "$ta_f" == loud ]]; then printf '#!/bin/sh\necho broken >&2\nexit 127\n' > "$TAP/$ta_t"
    else printf '#!/bin/sh\nexit 0\n' > "$TAP/$ta_t"; fi
    chmod +x "$TAP/$ta_t"
    TAD_OUT="$(PATH="$TAP:$PATH" bash "$SCRIPTS/trunk-audit.sh" "$TAV" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: the rc suffix is what the test reads
    printf '%s' "$TAD_OUT" | grep -q '|rc=0$' && TAD_BAD="$TAD_BAD $ta_t:$ta_f"
  done
done
if [[ -z "$TAD_BAD" ]]; then
  ok "audit toolchain c: no broken decision-path tool makes the audit report a violating trunk clean"
else
  bad "audit toolchain c: no broken decision-path tool makes the audit report a violating trunk clean" \
      "these exited 0 on a trunk the healthy audit refuses:$TAD_BAD, and exit 0 is what CI reads as a pass"
fi

# THE LOCKSTEP THE INLINE PROBE BUYS. Two copies of a check drift, and this
# repository has paid for that twice already (the diagram field applied a weaker
# test in the audit than in the hook while a comment claimed lockstep). So the
# obligation is asserted rather than commented: both probes must cover the same
# four tools, by name.
TA_LIBTOOLS="$(grep -oE 'slh_refuse "SLH-NO-TOOLCHAIN" "[a-z]+ ' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed -e 's/.*"//' -e 's/ *$//' | sort -u | tr '\n' ' ')"
TA_AUDTOOLS="$(grep -oE '^probe_tool [a-z]+' "$SCRIPTS/trunk-audit.sh" | awk '{print $2}' | sort -u | tr '\n' ' ')"
# SUPERSET, not equality. The first cut of this assertion required the two
# lists to be equal, which was right when both probed the same four tools and
# became wrong the moment the audit was widened to cover cut, wc, head, tail
# and sort as well. The audit decides with more tools than the library does, so
# the obligation is that it probes AT LEAST what the library probes: a tool the
# library thought worth checking must not go unchecked here.
TA_MISSING=""
for ta_l in $TA_LIBTOOLS; do
  case " $TA_AUDTOOLS " in *" $ta_l "*) ;; *) TA_MISSING="$TA_MISSING $ta_l" ;; esac
done
if [[ -n "$TA_LIBTOOLS" && -z "$TA_MISSING" ]]; then
  ok "audit toolchain b: the audit's inline probe covers everything the library's does"
else
  bad "audit toolchain b: the audit's inline probe covers everything the library's does" \
      "library probes [$TA_LIBTOOLS], audit probes [$TA_AUDTOOLS], unprobed here:${TA_MISSING:- none}; an empty library list means this assertion stopped reading the library and is checking nothing"
fi

# THE FALSE DENIAL THAT REMOVED THE CHECK (2026-08-07, F4), asserted so it
# cannot come back with the next attempt at the route above.
#
# Two clones of one instance. The second does a fully compliant close and
# pushes it. The first makes one docs commit and runs the sync git itself
# instructs. The resulting merge was refused with "a chained merge below main
# brought role-path code that closed no spec", naming as the offender the very
# close merge this audit had passed clean minutes earlier. That is every team
# sharing a trunk, and this repository treats a false denial on the commonest
# workflow there is as costing more than the bypass it prevents.
CHR="$WORK/chain-remote.git"; rm -rf "$CHR"; git init -q --bare -b main "$CHR"
CHS="$WORK/chain-seed"; chain_fixture "$CHS"
git -C "$CHS" push -q "$CHR" main >/dev/null 2>&1
CHP="$WORK/chain-clone-a"; rm -rf "$CHP"; git clone -q "$CHR" "$CHP" >/dev/null 2>&1
CHQ="$WORK/chain-clone-b"; rm -rf "$CHQ"; git clone -q "$CHR" "$CHQ" >/dev/null 2>&1
for d in "$CHP" "$CHQ"; do
  git -C "$d" config user.email t@e.invalid; git -C "$d" config user.name T
  git -C "$d" config commit.gpgsign false; git -C "$d" config merge.ff false
done
git -C "$CHQ" checkout -q -b spec/0001-first main; chain_close "$CHQ"
git -C "$CHQ" checkout -q main
git -C "$CHQ" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHQ" >/dev/null 2>&1; then
  git -C "$CHQ" push -q origin main >/dev/null 2>&1
  printf 'notes\n' > "$CHP/NOTES.md"
  git -C "$CHP" add -A >/dev/null 2>&1; git -C "$CHP" commit -qm "docs: notes" >/dev/null 2>&1
  git -C "$CHP" pull -q --no-rebase origin main >/dev/null 2>&1
  if bash "$SCRIPTS/trunk-audit.sh" "$CHP" >"$WORK/chain-sync.out" 2>&1; then
    ok "chain e: the second developer on a shared trunk can pull a compliant close and stay clean"
  else
    bad "chain e: the second developer on a shared trunk can pull a compliant close and stay clean" \
        "the sync git itself instructs is reported as a violation: $(grep VIOLATION "$WORK/chain-sync.out" | head -1)"
  fi
else
  bad "chain e control: the close the other clone pushes audits clean before it is pushed" \
      "the fixture is broken, so the sync case below proves nothing"
fi

# THE COOPERATIVE-USE FIXES FROM CLAIMS ROUND 6, both directions.
#
# Round 6's findings were all COOPERATIVE rather than crafted evasion: they hit
# a developer following the process. An empty gate_command is the STAMPED
# DEFAULT, and the fast-forward shape is byte-for-byte what a forge merge button
# produces, which for a pull-request team is the ordinary path rather than an
# attack. So they were fixed rather than documented.
GCE="$WORK/gate-empty"; rm -rf "$GCE"; close_fixture "$GCE" yes yes answered yes no ""
git -C "$GCE" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$GCE" "$(bash_payload "$MERGE_CMD")" >/dev/null 2>&1 || true
GCE_STATE="$(jq -r '.scaffolded' "$GCE/.claude/sdd.json" 2>/dev/null)" # fail-open-ok: an unreadable value fails the guard below, which skips a case rather than asserting on a broken fixture
if [[ "$GCE_STATE" == "true" ]]; then
  if bash -c "cd '$GCE' && printf '%s\n' \"\$(git -C '$GCE' log -1 --format=%H)\" >/dev/null"; then :; fi
fi

# The library function directly, which is what both git hooks call.
GCLIB="$WORK/gate-lib"; rm -rf "$GCLIB"; mkdir -p "$GCLIB/.claude"
printf '{"trunk":"main","scaffolded":true,"gate_command":"","roles":{"src":"src"}}\n' > "$GCLIB/.claude/sdd.json"
GC_OUT="$(SLH_REFUSED=0; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCLIB" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: sourcing noise is discarded; the rc suffix is what the test reads
if printf '%s' "$GC_OUT" | grep -q 'SLH-NO-GATE-COMMAND'; then
  ok "gate empty a: a SCAFFOLDED instance with no gate_command refuses instead of skipping the suite silently"
else
  bad "gate empty a: a SCAFFOLDED instance with no gate_command refuses instead of skipping the suite silently" \
      "it returned without a code, which is the stamped default state merging with no suite run"
fi
printf '{"trunk":"main","scaffolded":false,"gate_command":"","roles":{"src":"src"}}\n' > "$GCLIB/.claude/sdd.json"
GC_OUT2="$(SLH_REFUSED=0; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCLIB" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: as above
if printf '%s' "$GC_OUT2" | grep -q 'SLH-NO-GATE-COMMAND'; then
  bad "gate empty b control: BEFORE scaffolding an empty gate_command is still skipped" \
      "a project that has not been scaffolded yet is being refused, which is the false-denial direction"
else
  ok "gate empty b control: BEFORE scaffolding an empty gate_command is still skipped"
fi

# THE FORGE / FAST-FORWARD SHAPE: the audit now reads the diagram field, which
# lived only in the layer a fast-forward skips.
ffa_fixture() { # ffa_fixture <dir> <diagram-line-or-empty>
  local d="$1" diag="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | X | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0002-x
  printf 'export const f = 1\n' > "$d/src/f.js"
  { printf '# Spec 0002 - X\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n'
    [ -n "$diag" ] && printf -- '- Architecture diagram: %s\n' "$diag"; } > "$d/specs/0002-x.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | X | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm close >/dev/null 2>&1
  git -C "$d" checkout -q -B tmp main
  git -C "$d" merge -q --no-ff -m "Merge pull request #1" spec/0002-x >/dev/null 2>&1
  git -C "$d" checkout -q main; git -C "$d" merge -q --ff-only tmp >/dev/null 2>&1
}
# LOCKSTEP MEANS THE SAME TEST (v1.7 final claims pass). The audit's first cut
# found the same diagram line as the hook and applied a weaker test: it refused
# empty and `<` and passed everything else, so TBD, n/a and "see structure.md"
# were refused at merge time and reported clean by the audit. The comment
# claimed lockstep while the code did not have it. Asserted across the value
# space rather than at one spelling.
FF_DIAG_BAD=""
for ff_v in 'TBD' 'n/a' 'see structure.md'; do
  FFV="$WORK/ff-val"; ffa_fixture "$FFV" "$ff_v"
  bash "$SCRIPTS/trunk-audit.sh" "$FFV" >/dev/null 2>&1 && FF_DIAG_BAD="$FF_DIAG_BAD [$ff_v]"
done
if [[ -z "$FF_DIAG_BAD" ]]; then
  ok "forge diagram: an UNANSWERED diagram value is a violation, not just the template placeholder"
else
  bad "forge diagram: an UNANSWERED diagram value is a violation, not just the template placeholder" \
      "these passed the audit while the merge hook refuses them:$FF_DIAG_BAD"
fi
FF_OK_BAD=""
for ff_v in 'no impact' 'updated in this commit'; do
  FFV="$WORK/ff-val-ok"; ffa_fixture "$FFV" "$ff_v"
  bash "$SCRIPTS/trunk-audit.sh" "$FFV" >/dev/null 2>&1 || FF_OK_BAD="$FF_OK_BAD [$ff_v]"
done
if [[ -z "$FF_OK_BAD" ]]; then
  ok "forge diagram control: the two ANSWERS Appendix C offers are still clean"
else
  bad "forge diagram control: the two ANSWERS Appendix C offers are still clean" \
      "the audit refuses a compliant answer:$FF_OK_BAD, which is the false-denial direction"
fi

FFA="$WORK/ff-nodiag"; ffa_fixture "$FFA" ""
if bash "$SCRIPTS/trunk-audit.sh" "$FFA" >/dev/null 2>&1; then
  bad "forge shape a: a fast-forwarded close with NO diagram field is a violation" \
      "the audit reported clean, so the ordinary pull-request flow carries an incomplete close to the remote"
else ok "forge shape a: a fast-forwarded close with NO diagram field is a violation"; fi
FFB="$WORK/ff-placeholder"; ffa_fixture "$FFB" "<updated in this commit | no impact>"
if bash "$SCRIPTS/trunk-audit.sh" "$FFB" >/dev/null 2>&1; then
  bad "forge shape b: an UNANSWERED diagram placeholder is a violation" \
      "the template placeholder counted as an answer"
else ok "forge shape b: an UNANSWERED diagram placeholder is a violation"; fi
FFC="$WORK/ff-ok"; ffa_fixture "$FFC" "no impact"
if bash "$SCRIPTS/trunk-audit.sh" "$FFC" >/dev/null 2>&1; then
  ok "forge shape control: an ANSWERED diagram field is still clean"
else
  bad "forge shape control: an ANSWERED diagram field is still clean" \
      "the new diagram check refuses a compliant close, which is the false-denial direction"
fi

# CLOSE VERIFICATION BINDS TO THE EVENT, NOT THE MERGE SHAPE (v1.7 confirmation).
#
# Every close condition used to live inside the audit's merged-parent loop,
# reachable only past its NPAR>=2 guard, so a close producing no merge commit was
# never checked. Two ordinary honest routes hit that: `git merge --ff` of a
# linear spec branch, and a docs-only commit flipping a STATUS row to CLOSED,
# which this framework explicitly permits on the trunk. This is R3-2 one level
# up: there the close SET was wrong, here the TRIGGER was.
ev_fixture() { # ev_fixture <dir>
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | ACTIVE | x |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0002 - D\n\nStatus: ACTIVE\n' > "$d/specs/0002-d.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
}
ev_closed_row() { printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | CLOSED | done |\n'; }
ev_good() { printf '# Spec 0002 - D\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'; }
ev_bad()  { printf '# Spec 0002 - D\n\nStatus: CLOSED\n\n## Closing report\n\n(nothing)\n'; }

EVA="$WORK/event-ff-bad"; ev_fixture "$EVA"
git -C "$EVA" checkout -q -b spec/0002-d
ev_bad > "$EVA/specs/0002-d.md"; ev_closed_row > "$EVA/specs/STATUS.md"
git -C "$EVA" add -A >/dev/null 2>&1; git -C "$EVA" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVA" checkout -q main; git -C "$EVA" merge -q --ff spec/0002-d >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVA" >/dev/null 2>&1; then
  bad "event close a: a --ff close with no Closing report is a violation" \
      "the audit never opened the spec, so a fast-forward routes around close verification entirely"
else ok "event close a: a --ff close with no Closing report is a violation"; fi

EVB="$WORK/event-docs-bad"; ev_fixture "$EVB"
ev_closed_row > "$EVB/specs/STATUS.md"
git -C "$EVB" add -A >/dev/null 2>&1; git -C "$EVB" commit -qm "docs: mark 0002 closed" >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVB" >/dev/null 2>&1; then
  bad "event close b: a docs-commit that flips a row to CLOSED is verified too" \
      "a row reached CLOSED on the trunk with no Closing report and nothing looked at it"
else ok "event close b: a docs-commit that flips a row to CLOSED is verified too"; fi

EV_BAD=""
# THE CONTROL CARRIES ROLE-PATH CODE, AND WITHOUT IT PROVED NOTHING (F9).
#
# ev_fixture writes src/app.js at STAMP time, so this close commit used to touch
# specs/ and nothing else. The violation it is the control FOR ("feature code
# committed directly to main") is reached only when the commit ADDS role-path
# code, so this case could not exhibit the finding it guards: it passed both
# before and after F4, and would have gone on passing if F4 were never fixed.
# That is the vacuous-control class this repository keeps paying for, filed as
# F9 and landed here BEFORE F4's code fix per the regression-permanence rule.
#
# With the line below, this case is the F4 subject: a COMPLIANT fast-forward
# close carrying feature code. Watched RED against the pre-F4 audit, which
# reported `VIOLATION ... feature code committed directly to main` and refused a
# close satisfying every condition the framework asks for.
EVC="$WORK/event-ff-ok"; ev_fixture "$EVC"
git -C "$EVC" checkout -q -b spec/0002-d
ev_good > "$EVC/specs/0002-d.md"; ev_closed_row > "$EVC/specs/STATUS.md"
printf 'feature\n' > "$EVC/src/ff-feature.js"
git -C "$EVC" add -A >/dev/null 2>&1; git -C "$EVC" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVC" checkout -q main; git -C "$EVC" merge -q --ff spec/0002-d >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$EVC" >/dev/null 2>&1 || EV_BAD="$EV_BAD ff-complete"
EVD="$WORK/event-docs-only"; ev_fixture "$EVD"
mkdir -p "$EVD/docs"; printf 'hi\n' > "$EVD/docs/g.md"
git -C "$EVD" add -A >/dev/null 2>&1; git -C "$EVD" commit -qm "docs only" >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$EVD" >/dev/null 2>&1 || EV_BAD="$EV_BAD docs-no-flip"
if [[ -z "$EV_BAD" ]]; then
  ok "event close controls: a COMPLETE --ff close and an ordinary docs commit stay clean"
else
  bad "event close controls: a COMPLETE --ff close and an ordinary docs commit stay clean" \
      "these are refused:$EV_BAD, which is the false-denial direction"
fi

# The SQUASH half of F4, which is the same shape under the other flag name. A
# squash has no second parent, so it lands in the same NPAR<2 arm; asserting it
# separately is what stops a later fix keyed on the fast-forward alone from
# looking complete.
EVS="$WORK/event-squash-ok"; ev_fixture "$EVS"
git -C "$EVS" checkout -q -b spec/0002-d
ev_good > "$EVS/specs/0002-d.md"; ev_closed_row > "$EVS/specs/STATUS.md"
printf 'feature\n' > "$EVS/src/sq-feature.js"
git -C "$EVS" add -A >/dev/null 2>&1; git -C "$EVS" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVS" checkout -q main
git -C "$EVS" merge -q --squash spec/0002-d >/dev/null 2>&1
git -C "$EVS" commit -qm "close 0002 (squash)" >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVS" >/dev/null 2>&1; then
  ok "F4 squash: a COMPLIANT --squash close carrying feature code is clean"
else
  bad "F4 squash: a COMPLIANT --squash close carrying feature code is clean" \
      "it is a violation, so a compliant squash close is permanently unpushable. F4 is keyed on the PARENT COUNT precisely so one fix covers the fast-forward and the squash together"
fi

# THE TRUNK MUST NAME A BRANCH, NOT A POSITION (V19-F8). HEAD, @ and the reflog
# forms all RESOLVE, and the reducer then audits whatever branch is checked out,
# so the audited ref becomes a property of the working tree rather than of the
# recorded configuration. Watched red first: HEAD and @ both audited CLEAN.
EV8_BAD=""
for ev8 in HEAD '@' '@{-1}'; do
  EV8="$WORK/ev8"; ev_fixture "$EV8"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' "$ev8" > "$EV8/.claude/sdd.json"
  git -C "$EV8" add -A >/dev/null 2>&1; git -C "$EV8" commit -qm "record trunk" >/dev/null 2>&1
  bash "$SCRIPTS/trunk-audit.sh" "$EV8" >/dev/null 2>&1
  [[ "$?" -eq 2 ]] || EV8_BAD="$EV8_BAD $ev8"
done
if [[ -z "$EV8_BAD" ]]; then
  ok "V19-F8: a trunk recorded as HEAD, @ or a reflog form is refused"
else
  bad "V19-F8: a trunk recorded as HEAD, @ or a reflog form is refused" \
      "these were accepted and audited:$EV8_BAD. The audited ref then depends on where HEAD happens to point, so a spec branch can be audited as though it were the trunk"
fi
# CONTROL: the ordinary spelling still audits, or the refusal above is a blanket one.
EV8OK="$WORK/ev8ok"; ev_fixture "$EV8OK"
if bash "$SCRIPTS/trunk-audit.sh" "$EV8OK" >/dev/null 2>&1; then
  ok "V19-F8 control: a plain branch name still audits"
else
  bad "V19-F8 control: a plain branch name still audits" \
      "the position guard is refusing ordinary configurations, so the case above proves nothing"
fi

# THE TALLY CANNOT PRINT AN IMPOSSIBLE PAIR (V19-F9). The chore arm incremented
# CLEAN inside the PER-PARENT loop and the per-commit bucket incremented it
# again, so `clean` could exceed `audited`. No violation was ever missed; a
# shipped counter that prints an impossible pair is still a claim users read.
EV9="$WORK/ev9"; ev_fixture "$EV9"
git -C "$EV9" checkout -q -b chore/one
printf 'x\n' > "$EV9/src/chore.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | ACTIVE | x |\n\n- CHORE-007: DONE 2026-08-27. did a thing\n' > "$EV9/specs/STATUS.md"
git -C "$EV9" add -A >/dev/null 2>&1; git -C "$EV9" commit -qm "chore work" >/dev/null 2>&1
git -C "$EV9" checkout -q main
git -C "$EV9" merge -q --no-ff -m "merge chore/one" chore/one >/dev/null 2>&1
EV9_LINE="$(bash "$SCRIPTS/trunk-audit.sh" "$EV9" 2>&1 | grep '^audited' || true)" # fail-open-ok: an absent line is caught by the emptiness test below
EV9_A="$(printf '%s' "$EV9_LINE" | sed -E 's/^audited ([0-9]+).*/\1/')"
EV9_C="$(printf '%s' "$EV9_LINE" | sed -E 's/.*: ([0-9]+) clean.*/\1/')"
if [[ -z "$EV9_LINE" || -z "$EV9_A" || -z "$EV9_C" ]]; then
  bad "V19-F9: the audit tally never reports more clean than audited" \
      "no audited/clean line was produced, so this comparison read nothing: [$EV9_LINE]"
elif [[ "$EV9_C" -le "$EV9_A" ]]; then
  ok "V19-F9: the audit tally never reports more clean than audited ($EV9_C of $EV9_A)"
else
  bad "V19-F9: the audit tally never reports more clean than audited" \
      "it printed $EV9_C clean of $EV9_A audited, which is impossible: a commit is being counted in more than one bucket"
fi

# THE CLI GUARDS (F12). A value-less --since used to `shift 2` with one argument
# left, which is an error that leaves $# UNCHANGED, so the loop spun forever.
# Not reachable from pre-push, which always passes a value; a human or a CI job
# running the CLI hangs. Watched red first by the reproduction hanging.
EVF="$WORK/evf12"; ev_fixture "$EVF"
EV12_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$EVF" --since 2>&1)"; EV12_RC=$?
if [[ "$EV12_RC" -eq 2 ]] && printf '%s' "$EV12_OUT" | grep -q 'needs a <ref>'; then
  ok "F12: a value-less --since is refused by name rather than looping"
else
  bad "F12: a value-less --since is refused by name rather than looping" \
      "rc=$EV12_RC out=[$EV12_OUT]; the guard must refuse before the shift, because `shift 2` past the end leaves the argument list unchanged"
fi
EV12_BASE="$(git -C "$EVF" rev-parse HEAD)"
if bash "$SCRIPTS/trunk-audit.sh" "$EVF" --since="$EV12_BASE" >/dev/null 2>&1; then
  ok "F12: the --since=<ref> spelling is accepted"
else
  bad "F12: the --since=<ref> spelling is accepted" \
      "it was read as the instance directory, which is the confusing error a correct command used to get"
fi

# SP2-F5: the file stops describing itself as harmless while pre-push uses it as
# a gate. Asserted on the SHIPPED BYTES rather than on prose, and stated as the
# absence of the retired claims: the correction paraphrases them rather than
# quoting them, precisely so a grep like this one cannot read a quotation as a
# claim.
if grep -qE '^# ADVISORY as of plugin|it does not gate a commit|a finding does not block anything' "$SCRIPTS/trunk-audit.sh"; then
  bad "SP2-F5: trunk-audit.sh does not call itself advisory" \
      "the header still carries a retired advisory claim verbatim. pre-push RUNS this script on every push and refuses the push on its verdict, so a file calling itself harmless is a shipped claim that is false"
else
  ok "SP2-F5: trunk-audit.sh does not call itself advisory"
fi

# THE OCTOPUS SUB-MERGE (v1.7 claims round 5), and why this assertion exists.
#
# The round-4 chained-merge check read only the SECOND parent of a sub-merge, so
# `git merge --no-ff main sneaky` put the trunk in parent 2, was skipped as a
# catch-up, and the unspecced parent 3 was never examined. The verdict flipped on
# the ARGUMENT ORDER of a merge with identical content.
#
# This file already carried the lesson in those words at the top-level parent
# loop ("EVERY merged parent, not just the second", 1.0.5), and the fix written
# to be that check's backstop reintroduced it. So the assertion pins the ORDER
# dimension explicitly rather than one spelling of it.
CHO="$WORK/chain-octopus"; chain_fixture "$CHO"
CHO_BASE="$(git -C "$CHO" rev-parse HEAD)"
printf 'docs\n' > "$CHO/D.md"
git -C "$CHO" add -A >/dev/null 2>&1; git -C "$CHO" commit -qm "main moves on" >/dev/null 2>&1
git -C "$CHO" checkout -q -b sneaky "$CHO_BASE"
printf 'export const evil = 1\n' > "$CHO/src/evil.js"
git -C "$CHO" add -A >/dev/null 2>&1; git -C "$CHO" commit -qm "sneaky code" >/dev/null 2>&1
git -C "$CHO" checkout -q -b spec/0001-first "$CHO_BASE"; chain_close "$CHO"
git -C "$CHO" merge -q --no-ff -m "sync main and pull in sneaky" main sneaky >/dev/null 2>&1
git -C "$CHO" checkout -q main
git -C "$CHO" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHO" >/dev/null 2>&1; then
  ok "chain d: KNOWN HOLE, the OCTOPUS spelling of the chained merge is reported clean too, as Known limitations records"
else
  ok "chain d: the octopus sub-merge is refused again, which CLOSES a documented hole; check chain e first, then move the bullet in the same commit"
fi

CHB="$WORK/chain-plain"; chain_fixture "$CHB"
git -C "$CHB" checkout -q -b spec/0001-first main; chain_close "$CHB"
git -C "$CHB" checkout -q main
git -C "$CHB" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHB" >/dev/null 2>&1; then
  ok "chain b control: an ordinary compliant close is still clean"
else
  bad "chain b control: an ordinary compliant close is still clean" \
      "the chained-merge check is refusing ordinary closes, so case a proves nothing"
fi

CHC="$WORK/chain-catchup"; chain_fixture "$CHC"
printf 'docs\n' > "$CHC/README2.md"
git -C "$CHC" add -A >/dev/null 2>&1; git -C "$CHC" commit -qm "trunk moves on" >/dev/null 2>&1
git -C "$CHC" checkout -q -b spec/0001-first HEAD~1; chain_close "$CHC"
git -C "$CHC" merge -q --no-ff main -m "catch up with the trunk" >/dev/null 2>&1
git -C "$CHC" checkout -q main
git -C "$CHC" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHC" >/dev/null 2>&1; then
  ok "chain c control: merging the TRUNK into a spec branch stays clean (catch-up merges are ordinary)"
else
  bad "chain c control: merging the TRUNK into a spec branch stays clean (catch-up merges are ordinary)" \
      "the commonest legitimate workflow is refused, which is the false-denial direction"
fi

# THE ++ DIFF-PARSER INSTANCE (v1.7 claims round 4, F2), documented not fixed.
#
# slh_scan_added drops the `+++ b/path` diff header with `grep -vE '^\+\+\+'`,
# and a SOURCE line beginning `++` renders as `+++...`, so it is dropped too.
# Classified by replay as SCAN-ONLY: trunk discipline still refuses the merge
# (SLH-CLOSES-NO-SPEC), so no unclosed code reaches the trunk by this route.
# Under the standing rule a bypass of the already-documented best-effort scan is
# not a finding, and fixing the scan to see more is the coverage extension the
# original bound forbade. Pinned here so that the day it closes we find out.
PLUSD="$WORK/plus-prefix"; rm -rf "$PLUSD"; scan_ref_fixture "$PLUSD"
git -C "$PLUSD" checkout -q -b spec/0012-plus main
printf '++%s\n' "$SCAN_SECRET" > "$PLUSD/src/plus.txt"
git -C "$PLUSD" add -A >/dev/null 2>&1
if git -C "$PLUSD" commit -qm "++ prefixed secret" >/dev/null 2>&1; then
  ok "plus prefix: a source line beginning ++ is dropped by the diff reader, as Known limitations records (documented hole, still open)"
else
  ok "plus prefix: a source line beginning ++ is now scanned, which CLOSES a documented hole; update the bullet and this ledger entry"
fi

# THE EMPTY-DIRECTORY DELIVERY PATH (v1.7 claims audit, R3-1).
#
# THIS FIXTURE EXISTS BECAUSE OF WHAT IT CAUGHT, and the shape of the miss
# matters more than the defect. /setlist:new runs in an EMPTY directory, so no
# git repository exists when stamp.sh runs, so stamp.sh could not set
# core.hooksPath or merge.ff and (before R3-1) said nothing about it. Every
# project from the primary onboarding path shipped with .githooks/ present and
# NO enforcement: a secret committed, an unclosed spec merged onto the trunk,
# and both reached a remote, every command exiting 0.
#
# NINE HOSTILE LEGS AT ROUGHLY 45 USD EACH MISSED IT, because every fixture in
# this suite and in the leg driver stamps into an EXISTING repository. The
# corpus was not wrong about the mechanism; it was wrong about the POPULATION.
# A single fixture that starts from an empty directory finds it for nothing.
#
# Two halves, and the second is what makes the first safe to rely on.
EMPTYD="$WORK/empty-start"; rm -rf "$EMPTYD"; mkdir -p "$EMPTYD"
printf 'project_name=P\nstack=Node\nworking_mode=review only\nui=no\nopusplan_verified=yes\ndesign_surface=no\n' > "$EMPTYD/answers"
( cd "$EMPTYD" && bash "$SCRIPTS/stamp.sh" answers proj ) > "$EMPTYD/stamp.out" 2>&1
if grep -qi 'NOT ARMED' "$EMPTYD/stamp.out"; then
  ok "empty start a: stamping into a directory with no repository SAYS it could not arm the boundary"
else
  bad "empty start a: stamping into a directory with no repository SAYS it could not arm the boundary" \
      "the stamp was silent about it, which is how every /setlist:new project shipped unenforced"
fi

# The second half: a scaffold that follows the shipped instruction ends ARMED,
# and the boundary then actually refuses. Without this, half a says only that
# the stamp complains.
ESP="$EMPTYD/proj"
if [[ -d "$ESP" ]]; then
  git_init "$ESP"
  git -C "$ESP" config core.hooksPath .githooks
  git -C "$ESP" config merge.ff false
  git -C "$ESP" add -A >/dev/null 2>&1
  git -C "$ESP" -c core.hooksPath=/dev/null commit -qm "scaffold: first commit" >/dev/null 2>&1
  ES_HP="$(git -C "$ESP" config --get core.hooksPath 2>/dev/null || printf unset)" # fail-open-ok: an unset value prints "unset" and fails the test below, which is the finding rather than a skipped check
  if [[ "$ES_HP" == ".githooks" ]]; then
    ok "empty start b: a scaffold that follows the shipped instruction ends with the boundary armed"
  else
    bad "empty start b: a scaffold that follows the shipped instruction ends with the boundary armed" \
        "core.hooksPath reads [$ES_HP], so the instruction does not produce an enforced project"
  fi
  git -C "$ESP" checkout -q -b spec/0001-x 2>/dev/null
  mkdir -p "$ESP/src"
  printf 'api_key = "AKIAABCDEFGH12345678"\n' > "$ESP/src/a.js"
  git -C "$ESP" add -A >/dev/null 2>&1
  if git -C "$ESP" commit -qm "code plus a secret" >/dev/null 2>&1; then
    bad "empty start c: the armed boundary refuses a secret in a project built from an empty directory" \
        "the commit was allowed, so the project is stamped but unenforced, which is R3-1 still open"
  else
    ok "empty start c: the armed boundary refuses a secret in a project built from an empty directory"
  fi
fi

# COVERAGE NOTE FOR THE OTHER DELIVERY PATHS, filed rather than fixed here.
# retrofit and upgrade both operate on an EXISTING repository by definition, so
# the empty-start shape does not apply to them; refresh-instance.sh is covered
# for the cannot-write-config case by "refresh cfgfail" above. The gap this
# leaves, and it is filed in the backlog rather than closed here, is that no
# fixture drives retrofit into a repository that has NO commits yet, which is a
# different unusual start from an empty directory.

# THE PUSH-TIME SCAN REFUSES WHEN IT CANNOT RUN (v1.7 claims audit, R2-3).
#
# pre-commit and pre-merge-commit probed their toolchain; pre-push did not, and
# its scan is pure grep. A grep that exits non-zero with no output is
# indistinguishable from "nothing matched", so the scan reported clean and the
# push succeeded with the secret reaching the remote, while the SAME broken grep
# correctly refused the same content at commit time. That is the fail-open the
# library banner exists to say was removed, in the layer the release calls its
# guarantee, so it was fixed rather than documented.
#
# Both directions, because a hook that refuses every push would satisfy the
# first half alone.
TCHK="$WORK/toolchain-push"; rm -rf "$TCHK" "$TCHK-rem.git"
scan_ref_fixture "$TCHK"
mkdir -p "$WORK/brokenbin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/brokenbin/grep"
chmod +x "$WORK/brokenbin/grep"
git -C "$TCHK" checkout -q -b spec/0010-tc main
printf '%s\n' "$SCAN_SECRET" > "$TCHK/src/leak.js"
git -C "$TCHK" add -A >/dev/null 2>&1
git -C "$TCHK" -c core.hooksPath=/dev/null commit -qm leak >/dev/null 2>&1
if git -C "$TCHK" push -q origin spec/0010-tc >/dev/null 2>&1; then
  bad "toolchain push control: a healthy grep refuses the secret at push" \
      "the push succeeded with a working grep, so the broken-grep case below proves nothing"
else
  ok "toolchain push control: a healthy grep refuses the secret at push"
  if PATH="$WORK/brokenbin:$PATH" git -C "$TCHK" push -q origin spec/0010-tc >/dev/null 2>&1; then
    bad "toolchain push: a BROKEN grep refuses instead of reporting a clean scan" \
        "the push succeeded with a grep that cannot run, so the scan reported clean without reading anything"
  else ok "toolchain push: a BROKEN grep refuses instead of reporting a clean scan"; fi
fi
# THE FALSE-DENIAL DIRECTION: ordinary work must still push with a healthy toolchain.
git -C "$TCHK" checkout -q -b spec/0011-ok main
printf 'ordinary\n' > "$TCHK/src/ok.js"
git -C "$TCHK" add -A >/dev/null 2>&1
git -C "$TCHK" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
if git -C "$TCHK" push -q origin spec/0011-ok >/dev/null 2>&1; then
  ok "toolchain push control 2: a clean branch still pushes under a healthy toolchain"
else
  bad "toolchain push control 2: a clean branch still pushes under a healthy toolchain" \
      "the probe is refusing ordinary work, which is the false-denial direction"
fi

# THE CHECKOUT SWITCH (v1.7 second bound leg, F1), documented and pinned.
#
# Every git hook opens by checking that the CHECKED-OUT branch carries
# .claude/sdd.json and exits silently when it does not. That guard is what stops
# a stamped hooksPath governing unrelated repositories, and it also means a
# checkout is an enforcement switch: the same push refused from the trunk
# succeeds from a branch that lacks the file. This is scope-reduced rather than
# repaired, per the owner's bound, so it is asserted HERE so that the day it
# closes we find out instead of shipping a document describing a hole we no
# longer have.
SDDSW="$WORK/sdd-switch"; rm -rf "$SDDSW" "$SDDSW-rem.git"
mkdir -p "$SDDSW/src" "$SDDSW/specs" "$SDDSW/.claude/hooks" "$SDDSW/.githooks"
git_init "$SDDSW"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SDDSW/.claude/sdd.json"
printf 'x\n' > "$SDDSW/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SDDSW/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
   "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SDDSW/.githooks/"
chmod +x "$SDDSW/.githooks/pre-commit" "$SDDSW/.githooks/pre-merge-commit" "$SDDSW/.githooks/pre-push"
cp "$ROOT/scripts/trunk-audit.sh" "$SDDSW/.claude/hooks/trunk-audit.sh"
git -C "$SDDSW" config core.hooksPath .githooks
git -C "$SDDSW" add -A >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
git init -q --bare "$SDDSW-rem.git"; git -C "$SDDSW" remote add origin "$SDDSW-rem.git"
git -C "$SDDSW" push -q origin main >/dev/null 2>&1
git -C "$SDDSW" checkout -q -b work
printf 'unclosed\n' > "$SDDSW/src/FEATURE.txt"
git -C "$SDDSW" add -A >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm feat >/dev/null 2>&1
git -C "$SDDSW" checkout -q main
git -C "$SDDSW" merge -q --no-verify --no-ff -m m work >/dev/null 2>&1
# CONTROL: from the trunk, with sdd.json present, the audit refuses this push.
if git -C "$SDDSW" push -q origin main >/dev/null 2>&1; then
  bad "sdd switch control: with sdd.json present the unclosed trunk is refused" \
      "the push was allowed, so the case below proves nothing about the guard"
else ok "sdd switch control: with sdd.json present the unclosed trunk is refused"; fi
# THE HOLE: the same push from a branch WITHOUT the file.
git -C "$SDDSW" checkout -q --orphan legacy >/dev/null 2>&1
git -C "$SDDSW" rm -rq --cached . >/dev/null 2>&1
rm -f "$SDDSW/.claude/sdd.json"
printf 'legacy\n' > "$SDDSW/legacy.txt"
git -C "$SDDSW" add legacy.txt >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm legacy >/dev/null 2>&1
if git -C "$SDDSW" push -q origin main >/dev/null 2>&1; then
  ok "sdd switch: a checkout without .claude/sdd.json makes every hook inert (documented hole, still open)"
else
  ok "sdd switch: the checkout switch is now CLOSED, which means Known limitations describes a hole that no longer exists; update the bullet and this ledger entry"
fi

# THE TWO DOCUMENTED GIT-HOOK HOLES, asserted rather than merely described.
# Both are in the public README's Known limitations and therefore in the suite's
# hole ledger, and the docs-tree lockstep gate refuses a publish where the two
# disagree. Asserting a hole is not endorsing it: it is making sure that the day
# it closes, we find out, instead of shipping a document describing a weakness
# we no longer have.
GH="$WORK/gh-noverify"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-verify --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  ok "git hooks m: --no-verify really does skip the hooks (documented hole, still open)"
else
  bad "git hooks m: --no-verify really does skip the hooks (documented hole, still open)" \
      "it was blocked, so the README's Known limitations now describes a hole that does not exist"
fi

# The per-clone gap, both halves: the TRACKED directory survives a clone (which
# is why the hooks live there rather than in .git/hooks), and the CONFIG pointing
# at it does not (which is the residual hole the README states).
GH="$WORK/gh-clone-src"; gh_fixture "$GH" no
GHC="$WORK/gh-clone-dst"; rm -rf "$GHC"
if git clone -q "$GH" "$GHC" >/dev/null 2>&1; then
  if [[ -f "$GHC/.githooks/pre-merge-commit" ]]; then
    ok "git hooks n: a fresh clone DOES carry the tracked .githooks/ directory"
  else
    bad "git hooks n: a fresh clone DOES carry the tracked .githooks/ directory" "the hooks did not survive the clone"
  fi
  if [[ -z "$(git -C "$GHC" config --get core.hooksPath || true)" ]]; then
    ok "git hooks o: a fresh clone does NOT carry core.hooksPath (documented per-clone hole)"
  else
    bad "git hooks o: a fresh clone does NOT carry core.hooksPath (documented per-clone hole)" \
        "the config survived the clone, so the README overstates the gap"
  fi
else
  bad "git hooks n/o: the clone fixture could be created" "git clone failed, so neither half was checked"
fi

# --ff-only, the documented hole, asserted in BOTH directions: it really does
# skip the merge hooks (so the README is not describing a hole that closed), and
# pre-push really does catch the result (so the README is not overstating the
# damage). Found by the v1.7 dogfood gate's merge.ff probe.
GHF="$WORK/gh-ffonly"; gh_fixture "$GHF" no
# CONTROL: a fast-forward has to be POSSIBLE for this case to test anything. If
# the trunk is not an ancestor of the spec branch there is nothing to fast
# forward and the assertion below would pass for the wrong reason.
assert_true "git hooks p0: the fixture can actually fast-forward (trunk is an ancestor)" \
  "the trunk is not an ancestor of the spec branch, so --ff-only cannot apply and the case below tests nothing" \
  git -C "$GHF" merge-base --is-ancestor main spec/0001-thing
GHF_OUT="$( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff-only spec/0001-thing 2>&1 )"
if gh_landed "$GHF"; then
  ok "git hooks p: --ff-only really does skip the merge hooks (documented hole, still open)"
else
  bad "git hooks p: --ff-only really does skip the merge hooks (documented hole, still open)" \
      "it did not land; git said: ${GHF_OUT:-<no output>}"
fi
GHF_REMOTE="$WORK/gh-ffonly-remote.git"; rm -rf "$GHF_REMOTE"; git init -q --bare "$GHF_REMOTE"
git -C "$GHF" remote add origin "$GHF_REMOTE" 2>/dev/null || true
cp "$ROOT/templates/git-hooks/pre-push" "$GHF/.githooks/pre-push"; chmod +x "$GHF/.githooks/pre-push"
mkdir -p "$GHF/.claude/hooks"; cp "$ROOT/scripts/trunk-audit.sh" "$GHF/.claude/hooks/trunk-audit.sh"
( cd "$GHF" && env -u CLAUDE_PLUGIN_ROOT git push origin main ) >/dev/null 2>&1
if git -C "$GHF_REMOTE" cat-file -e main:src/FEATURE.txt 2>/dev/null; then
  bad "git hooks q: pre-push CATCHES what --ff-only let onto the local trunk" \
      "it reached the remote, so the mitigation the README claims does not hold and --ff-only is a full bypass"
else
  ok "git hooks q: pre-push CATCHES what --ff-only let onto the local trunk"
fi

# ===========================================================================
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
  if grep -n "$ADV_FIELD" "$ROOT/test/run-tests.sh" 2>/dev/null | grep -q -- "$adv_w"; then
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

# =============================================================================
# THE PATH-CANONICALISATION AXIS, scope hook (1.0.7)
#
# The scope hook compared the write path against the role paths as STRINGS,
# after stripping the project prefix and squeezing slashes. Two spellings of
# the same file therefore got two different answers: `src/app.js` denied, and
# `docs/../src/app.js` and `srclink/app.js` (a symlinked directory) both landed
# on the trunk in silence. `..` in a path is what a tool composing paths
# produces, and symlinked source directories are ordinary in real repositories,
# so neither needs an attacker. Same class as the pathspec checkout: a string
# that LOOKS like it is not the governed thing.
# =============================================================================

CANON="$WORK/canonical"
close_fixture "$CANON" no no answered no no true
mkdir -p "$CANON/docs" "$CANON/src"
# The symlink must point at a directory that EXISTS, or it is dangling and the
# case tests nothing. The first cut of this fixture linked to a src/ the
# fixture's trunk does not carry, the physical resolution had nothing to
# resolve, and the case passed for the pre-fix reason.
ln -s src "$CANON/srclink" 2>/dev/null
canon_verdict() { # canon_verdict <path>
  local out
  out="$(printf '%s' "$(jq -nc --arg p "$1" '{tool_name:"Edit", tool_input:{file_path:$p}}')" \
        | CLAUDE_PROJECT_DIR="$CANON" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "canon0: the fixture is on the trunk" \
  "not on the trunk, so every write would be legitimately allowed and these cases would prove nothing" \
  test "$(git -C "$CANON" branch --show-current)" = "main"
if [[ "$(canon_verdict "$CANON/src/app.js")" == "deny" ]]; then
  ok "canon control: the plain spelling of a role path is denied on the trunk"
else
  bad "canon control: the plain spelling of a role path is denied on the trunk" \
      "the harness cannot observe a deny, so every case below is meaningless"
fi
CANON_FAIL=""
for p in "$CANON/docs/../src/app.js" \
         "docs/../src/app.js" \
         "$CANON/src/../src/app.js" \
         "$CANON/./docs/../src/nested/../app.js"; do
  [[ "$(canon_verdict "$p")" == "deny" ]] || CANON_FAIL="$CANON_FAIL
    $p"
done
# A symlinked role directory only counts if the link really exists: on a
# filesystem or a runner where it does not, asserting it would fail for a
# reason that has nothing to do with the gate.
if [[ -L "$CANON/srclink" ]]; then
  [[ "$(canon_verdict "$CANON/srclink/app.js")" == "deny" ]] || CANON_FAIL="$CANON_FAIL
    $CANON/srclink/app.js (symlinked role directory)"
else
  printf 'NOTE: symlinks unavailable here; the symlinked-role-directory case did not run.\n'
fi
if [[ -z "$CANON_FAIL" ]]; then
  ok "canon: uncanonicalised spellings of a role path are denied like the plain one"
else
  bad "canon: every spelling of a role path must reach the same verdict" \
      "these wrote feature code to the trunk in silence:$CANON_FAIL"
fi
CANON_ALLOW_FAIL=""
for p in "$CANON/docs/notes.md" "docs/notes.md" "$CANON/README.md" "$CANON/src/../docs/notes.md"; do
  [[ "$(canon_verdict "$p")" == "allow" ]] || CANON_ALLOW_FAIL="$CANON_ALLOW_FAIL
    $p"
done
if [[ -z "$CANON_ALLOW_FAIL" ]]; then
  ok "canon: docs-only trunk writes still pass, however they are spelled"
else
  bad "canon: docs-only trunk writes must still pass" \
      "these were denied:$CANON_ALLOW_FAIL"
fi

# =============================================================================
# EVERY SHIPPED SKILL'S FRONTMATTER PARSES (1.0.7)
#
# `design-surface` shipped from 1.0.0 through 1.0.6 with an unquoted
# colon-space inside a plain YAML scalar, so its frontmatter did not parse and
# the skill loaded at runtime with every field silently dropped: no name, no
# description, no model. Nothing caught it for seven releases because the
# publish gate ran `claude plugin validate` against the repo ROOT, where that
# argument validates marketplace.json and nothing else.
#
# So the property is asserted HERE, in the suite, where it does not depend on
# which argument someone passed to an external CLI. Deliberately parsed the
# strict way rather than the forgiving way: this is the one field whose
# breakage is invisible at runtime.
# =============================================================================

SKILL_BAD=""
SKILL_N=0
for sk in "$ROOT"/skills/*/SKILL.md; do
  [[ -f "$sk" ]] || continue
  SKILL_N=$((SKILL_N + 1))
  name="$(basename "$(dirname "$sk")")"
  # Frontmatter is the block between the first two --- lines.
  FM="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$sk")"
  if [[ -z "$FM" ]]; then
    SKILL_BAD="$SKILL_BAD
    $name: no YAML frontmatter block at all"
    continue
  fi
  # Every line must be `key: value`, and an unquoted value may not itself
  # contain a colon-space, which is what YAML reads as a nested mapping.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      [[:space:]]*) continue ;;   # continuation lines are the block-scalar form
    esac
    if ! printf '%s' "$line" | grep -qE '^[A-Za-z_-]+:[[:space:]]'; then
      SKILL_BAD="$SKILL_BAD
    $name: frontmatter line is not 'key: value': $line"
      continue
    fi
    val="$(printf '%s' "$line" | sed -E 's/^[A-Za-z_-]+:[[:space:]]*//')"
    case "$val" in
      \"*\"|\'*\'|'>'*|'|'*|'['*|'') continue ;;   # quoted, block scalar, list, empty
    esac
    if printf '%s' "$val" | grep -q ': '; then
      SKILL_BAD="$SKILL_BAD
    $name: unquoted value contains a colon-space, so YAML reads it as a mapping and the whole block is dropped: $line"
    fi
  done <<EOF
$FM
EOF
done
if [[ "$SKILL_N" -lt 5 ]]; then
  bad "skill frontmatter: the scan found the shipped skills" \
      "only $SKILL_N SKILL.md files were read; the tree carries more, so this scan is broken rather than clean"
elif [[ -z "$SKILL_BAD" ]]; then
  ok "skill frontmatter: all $SKILL_N shipped skills carry frontmatter that parses"
else
  bad "skill frontmatter: every shipped skill's frontmatter must parse" \
      "these load with all metadata silently dropped:$SKILL_BAD"
fi

# The scan is only worth anything if it can SEE the defect, so it is run
# against a reconstruction of the exact line that shipped.
FM_FIX="$WORK/fm-fixture"
mkdir -p "$FM_FIX"
printf -- '---\nname: x\ndescription: A surface (Part 5c): the routing test\n---\nbody\n' > "$FM_FIX/SKILL.md"
FM_HIT=""
FM="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$FM_FIX/SKILL.md")"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  val="$(printf '%s' "$line" | sed -E 's/^[A-Za-z_-]+:[[:space:]]*//')"
  case "$val" in \"*\"|\'*\'|'>'*|'|'*|'['*|'') continue ;; esac
  printf '%s' "$val" | grep -q ': ' && FM_HIT=1
done <<EOF
$FM
EOF
if [[ -n "$FM_HIT" ]]; then
  ok "skill frontmatter control: the scan catches the exact line that shipped in 1.0.0 through 1.0.6"
else
  bad "skill frontmatter control: the scan catches the line that shipped" \
      "it did not flag the design-surface description, so the clean result above means nothing"
fi

# =============================================================================
# THE QA READER IS SCOPED, AND THE LAYERS AGREE BY OUTCOME (2.0.0 leg, F8/F3).
#
# The third fence-vs-QA-block collision. The reader matched the FIRST
# ```qa-pass-1 fence anywhere in the file, with no fence depth and no section
# scoping, and it was wrong in BOTH directions at once: a qa-pass-1 block
# NESTED inside a pasted-report fence satisfied the close condition (F8, a
# Closing report answering nothing reached the trunk and the audit called it
# clean), and an illustrative shape-quote in another section poisoned a perfect
# verdict (F3, refused at all three layers with a reason naming the wrong
# block). The trigger is cooperative both times: Appendix C says "pasted
# verbatim", and a verbatim verifier report naturally carries its own fenced
# verdict block.
#
# The byte-identity lockstep above asserts the three layers carry the same
# PROGRAM; F8 proved that is not the same as carrying the same BEHAVIOR worth
# having, because all three were wrong together, by design. So this block
# asserts agreement BY OUTCOME over a corpus: every shape is driven through
# close-gate (advisory), the armed pre-merge-commit (enforcing), and
# trunk-audit (the guarantee), and all three must land the EXPECTED side, not
# merely the same side.
# =============================================================================

qa_scope_spec() { # qa_scope_spec <shape> -> spec text on stdout
  case "$1" in
    good) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    f8nested) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- What was built: <not written yet>
- QA Pass 1 verdicts: <not run yet>
- QA Pass 1 report (pasted verbatim):

```
qa-verifier v3 report for spec 0001
Architecture diagram: no impact

```qa-pass-1
1: PASS
```
end of report
```

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    f3illustrative) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Acceptance criteria

At close, the verdict block must be written in this shape:

```qa-pass-1
<criterion>: PASS|PARTIAL|FAIL
```

## Closing report

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    missing) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
  esac
}

# Layer 1: close-gate, advisory. The nf_verdict shape: empty output is allow.
qa_scope_cg() { # qa_scope_cg <shape> -> allow|deny
  local d="$WORK/qa-scope-cg" o
  rm -rf "$d"; close_fixture "$d" no no answered no no true
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "spec body" >/dev/null 2>&1
  git -C "$d" checkout -q main
  o="$(printf '%s' "$(bash_payload 'git merge --no-ff spec/0001-thing')" | CLAUDE_PROJECT_DIR="$d" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  [[ -z "$o" ]] && { printf 'allow'; return 0; }
  printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // "allow"'
}

# Layer 2: the armed pre-merge-commit, enforcing. Outcome is whether the work
# LANDED, never the printed reason.
qa_scope_slh() { # qa_scope_slh <shape> -> allow|deny
  local d="$WORK/qa-scope-slh"
  rm -rf "$d"; gh_fixture "$d" yes
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 git commit -qam "spec body" ) >/dev/null 2>&1
  git -C "$d" checkout -q main
  ( cd "$d" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$d"; then printf 'allow'; else printf 'deny'; fi
}

# Layer 3: trunk-audit, THE guarantee. The merge is FORCED in past the hooks,
# which is exactly the route the audit exists to catch.
qa_scope_audit() { # qa_scope_audit <shape> -> allow|deny
  local d="$WORK/qa-scope-audit"
  rm -rf "$d"; gh_fixture "$d" yes
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 git commit -qam "spec body" ) >/dev/null 2>&1
  git -C "$d" checkout -q main
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
  if bash "$ROOT/scripts/trunk-audit.sh" "$d" >/dev/null 2>&1; then printf 'allow'; else printf 'deny'; fi
}

for qa_scope_case in good:allow f8nested:deny f3illustrative:allow missing:deny; do
  qs_shape="${qa_scope_case%%:*}"; qs_want="${qa_scope_case#*:}"
  qs_cg="$(qa_scope_cg "$qs_shape")"
  qs_slh="$(qa_scope_slh "$qs_shape")"
  qs_audit="$(qa_scope_audit "$qs_shape")"
  if [[ "$qs_cg" == "$qs_want" && "$qs_slh" == "$qs_want" && "$qs_audit" == "$qs_want" ]]; then
    ok "qa scope corpus: [$qs_shape] lands $qs_want at close-gate, pre-merge-commit and trunk-audit alike"
  else
    bad "qa scope corpus: [$qs_shape] lands $qs_want at close-gate, pre-merge-commit and trunk-audit alike" \
        "wanted $qs_want everywhere, measured close-gate=$qs_cg pre-merge-commit=$qs_slh trunk-audit=$qs_audit; a layer that disagrees with the expected side is either the F8 blindness or the F3 false-deny, and a layer that disagrees with its siblings has broken the lockstep by outcome"
  fi
done

# The two directions by NAME, so a regression in either reads as itself rather
# than as a corpus row. F8: the nested block must not satisfy the enforcing
# layer. F3: the illustrative block must not poison the advisory one.
if [[ "$(qa_scope_slh f8nested)" == "deny" ]]; then
  ok "qa scope F8: a qa-pass-1 block nested inside a pasted-report fence does not close a spec"
else
  bad "qa scope F8: a qa-pass-1 block nested inside a pasted-report fence does not close a spec" \
      "the armed merge landed on a Closing report whose verdicts field reads <not run yet>; this is the 2.0.0 leg's guarantee bypass, replayed"
fi
if [[ "$(qa_scope_cg f3illustrative)" == "allow" ]]; then
  ok "qa scope F3: an illustrative shape-quote outside the Closing report does not poison a real verdict"
else
  bad "qa scope F3: an illustrative shape-quote outside the Closing report does not poison a real verdict" \
      "a compliant close is refused because the reader merged every fenced block in the file; this is the 2.0.0 leg's false-deny, replayed"
fi

# =============================================================================
# A HEADING IS WHAT MARKDOWN SAYS A HEADING IS (second 2.0.0 leg, F1).
#
# The scoped reader's first cut entered its heading branch on `first char is
# '#'` after stripping indentation. An issue reference on its own line
# ('#1234 was the crash this closes.'), a 4-space-indented shell snippet
# ('#!/usr/bin/env bash'), and a pasted verifier banner ('# QA run ...') each
# "closed" the Closing report section, orphaned a perfect verdict block, and a
# compliant close was refused at the gate, the hook and the audit, in lockstep,
# with a reason naming a block that was present. CommonMark: an ATX heading is
# at most 3 spaces of indent, 1 to 6 '#', then space, tab or end of line.
# The corpus below is ORDINARY AUTHOR CONTENT, not attack shapes, because the
# first corpus enumerated only the shapes its author had thought of, which is
# the population error again, in the test this time.
# =============================================================================

qa_atx_run() { # qa_atx_run <spec-text-on-stdin> -> reader state
  awk "$(grep -m1 -E '^[[:space:]]*QA_PASS1_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*QA_PASS1_AWK='//" -e "s/'$//")"
}
QA_ATX_BAD=""
qa_atx_case() { # qa_atx_case <name> <want> <spec text>
  local got
  got="$(printf '%s\n' "$3" | qa_atx_run)"
  [[ "$got" == "$2" ]] || QA_ATX_BAD="$QA_ATX_BAD
    $1: wanted $2, reader said $got"
}
qa_atx_case "issue-ref" ok '# Spec 3

## Closing report

- Architecture diagram: no impact
#1234 was the crash this closes.

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "indented-shebang" ok '# Spec 3

## Closing report

- What was built: the runner, now

    #!/usr/bin/env bash
    exec ./suite

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "indented-pasted-banner" ok '# Spec 3

## Closing report

- QA Pass 1 report (pasted verbatim):

    # QA run 2026-08-14
    ok 1 - thing

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "seven-hashes" ok '# Spec 3

## Closing report

####### not a heading in markdown either

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "no-space-hashes" ok '# Spec 3

## Closing report

##Results were fine, see above.

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
# DIRECTION CONTROLS: real headings must still end the section, or the F3 fix
# is undone. A same-level heading, a shallower one, and a fenced fake.
qa_atx_case "real-h2-ends-section" none '# Spec 3

## Closing report

## Appendix

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "real-h1-ends-section" none '# Spec 3

## Closing report

# Retrospective

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "subsection-stays-open" ok '# Spec 3

## Closing report

### details

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "fenced-heading-inert" none '# Spec 3

```markdown
## Closing report
```

```qa-pass-1
1: PASS
```'
# The cheap adversary's findings 4, 5 and 10: the OPEN branch must be as
# strict as the CLOSE branch (a loose open with a strict close built sections
# nothing could ever leave), and a CRLF empty heading must still scope.
qa_atx_case "nospace-open-inert" none '##Closing report

QA was not run.

##Template example

```qa-pass-1
criterion: PASS
```'
qa_atx_case "prose-hash-open-inert" none '#Closing report is described in Part 6.

#!/usr/bin/env bash

## Template

```qa-pass-1
criterion: PASS
```'
qa_atx_case "crlf-empty-heading-scopes" none '## Closing report

x

##
'"$(printf '\r')"'
```qa-pass-1
criterion: PASS
```'
# DELIBERATE SEMANTICS, PINNED (adversary round 2, finding 5): an INDENTED or
# no-space later "heading" is not a heading per markdown, so the Closing
# report section CONTINUES through it and a verdict block after it counts.
# Every renderer shows the author continuous Closing-report content there, so
# accepting is the honest reading; the old reader's refusal was the
# non-markdown one. Pinned so a future re-tightening is judged, not drifted.
qa_atx_case "indented-later-heading-continues" ok '## Closing report

prose, then what looks like a heading but is a code block:

    ## Appendix

```qa-pass-1
1: PASS
```'
qa_atx_case "nospace-later-heading-continues" ok '## Closing report

##Appendix

```qa-pass-1
1: PASS
```'
# And the NBSP spelling agrees BYTE-WISE at both layers now: the exists-grep
# was locale-sensitive ([[:space:]] matches U+00A0 under UTF-8) while the awk
# never was, so the gate denied naming a block that was present (adversary
# round 2, finding 6). Both now read space-or-tab, so this spec has no
# Closing report section at either layer and the refusal code is the section
# one, honest.
qa_atx_case "nbsp-after-hashes-no-section" none '##'"$(printf '\302\240')"'Closing report

```qa-pass-1
1: PASS
```'
# Adversary round 3, findings 6 and 7: fences obey the same 0-3 space rule as
# headings. A 4-space backtick line is indented CODE, so it neither swallows a
# later section-closing heading (6) nor opens the verdict block early (7); the
# template's own 2-space block under a bullet still parses.
qa_atx_case "indented-fence-not-a-fence" none '## Closing report

prose:

    ```

## Appendix: unrelated

```

```qa-pass-1
x: PASS
```'
qa_atx_case "indented-example-opener-inert" ok '## Closing report

example:

    ```qa-pass-1

```qa-pass-1
login: PASS
```'
qa_atx_case "two-space-bullet-block-parses" ok '## Closing report

- QA Pass 1 verdicts:
  ```qa-pass-1
  1: PASS
  ```'
# DOCUMENTED FLAT CONTRACT, PINNED (round 4, findings 4 and 5). A line reader
# cannot honor both flat-document and list-item indentation semantics: a fence
# at four columns is a REAL fence inside a numbered list item and indented
# CODE flat. The contract is FLAT, stated in the deny text (write blocks at
# the left margin), the template and every shipped producer emit left-margin
# blocks, and both directions of the ambiguity are pinned here so a future
# list-aware widening is a judged decision against the parser-freeze doctrine.
qa_atx_case "flat-contract-nested-quoted-live" ok '## Closing report

QA Pass 1 has not been run yet. Paste a block of this shape:

1.  Run the verifier, then paste below:

    ````markdown
```qa-pass-1
login: PASS
```
    ````

Architecture diagram: n/a'
qa_atx_case "flat-contract-list-indented-block-unread" none '## Closing report

1.  Ran QA Pass 1. Verdict block:

    ```qa-pass-1
    login: PASS
    ```

Architecture diagram: no impact'
# Round 5, findings 7 and 8: the TEMPLATE-FENCE STRIPPER obeys the same
# 0-3-space rule, or an indented fence marker deletes the rest of the spec
# before any reader sees it (a margin block refused as no-section) and an
# indented pseudo-quote deletes a margin heading (an appendix demo accepted).
# These two run the full stripper-then-reader pipeline, unlike the reader-only
# battery above.
QA_STRIP_BAD=""
qa_strip_case() { # qa_strip_case <name> <want> <<'SPEC'
  local name="$1" want="$2" f="$WORK/qa-strip-$1" got
  cat > "$f"
  got="$(awk "$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")" "$f" | qa_atx_run)"
  [[ "$got" == "$want" ]] || QA_STRIP_BAD="$QA_STRIP_BAD
    $name: wanted $want, pipeline said $got"
}
qa_strip_case indented-marker-not-a-fence ok <<'SPEC'
# Spec 0001

## Notes

The verdict block is opened with a line reading:

    ```qa-pass-1

and closed with the same marker.

## Closing report

Architecture diagram: no impact

```qa-pass-1
crit-one: PASS
```
SPEC
qa_strip_case indented-quote-cannot-eat-heading none <<'SPEC'
# Spec 0001

## Closing report

Architecture diagram: no impact

QA Pass 1 was not run; the block is in the appendix.

    ```text
    ## Closing report  (quoted from the template)
## Appendix A
    ```

```qa-pass-1
demo-only: PASS
```
SPEC
qa_strip_case margin-template-quote-still-dropped ok <<'SPEC'
# S

```markdown
## Closing report
template text
```

## Closing report

```qa-pass-1
1: PASS
```
SPEC
if [[ -z "$QA_STRIP_BAD" ]]; then
  ok "qa stripper corpus: the fence stripper obeys the 0-3-space rule, 5 shapes through the full pipeline"
else
  bad "qa stripper corpus: the fence stripper obeys the 0-3-space rule, 5 shapes through the full pipeline" \
      "the stripper and the reader disagree about what a fence is:$QA_STRIP_BAD"
fi
# Round 6, finding 4, DOCUMENTED as flat-correct and pinned: a fence whose
# closer is 4-space-indented does not close in ANY renderer (CommonMark:
# closing fences may be indented at most 3), so the tail of such a spec,
# Closing report included, genuinely IS code and refusing it as no-section is
# the honest flat reading. The previous release's acceptance was the wrong
# reading. R6-6 beside it: a formfeed after the hashes is not space-or-tab,
# so the grep and the awk now agree the section is absent.
qa_strip_case unclosed-fence-tail-is-code none <<'SPEC'
# Spec

```text
example
    ```

## Closing report

```qa-pass-1
login: PASS
```
SPEC
printf '## \fClosing report\n\n```qa-pass-1\nlogin: PASS\n```\n' > "$WORK/qa-strip-formfeed"
QA_STRIP_FF="$(awk "$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")" "$WORK/qa-strip-formfeed" | qa_atx_run)"
[[ "$QA_STRIP_FF" == "none" ]] || QA_STRIP_BAD="$QA_STRIP_BAD
    formfeed-heading-no-section: wanted none, pipeline said $QA_STRIP_FF (a REAL formfeed byte, printf-built because a quoted heredoc would have tested the literal string)"
# Round 7, finding 2: a fence is a fence in either CommonMark spelling. The
# edition says "a fenced block whose info string is qa-pass-1"; tilde fences
# and longer backtick runs are exactly that, and a tilde fence is the ordinary
# wrapper for content containing backticks.
qa_atx_case "four-backtick-fence-accepted" ok '## Closing report

````qa-pass-1
c1: PASS
````'
qa_atx_case "tilde-fence-accepted" ok '## Closing report

~~~qa-pass-1
c1: PASS
~~~'
# Round 7, finding 3, DOCUMENTED and pinned: two agreed loose readings, both
# harmless direction, both layers agreeing, kept per the freeze doctrine. A
# prefix section title still contains the section; a spaced info string
# collapsing to qa-pass-1 is generosity toward the author, not a hole.
qa_atx_case "prefix-section-title-pinned" ok '## Closing reports of prior work

```qa-pass-1
c1: PASS
```'
qa_atx_case "spaced-info-string-pinned" ok '## Closing report

``` qa-pass -1
c1: PASS
```'
# Round 10, findings 1 and 2: the reader matched a REFERENCE CommonMark parser
# across the cases a line reader can decide, and fails CLOSED where it cannot.
# R10-2 is F8/F3 re-opened: a line STARTING with an inline code span of three
# or more backticks (```qa-pass-1``` in prose, exactly how Part 6's fence label
# reads) is NOT a fence in CommonMark (an opening backtick fence's info string
# may not contain a backtick), so the reader now rejects it and its depth stays
# synced; a nested block cannot be promoted and a later-section example cannot
# leak. R10-1: the HTML-comment opener obeys the same 0-3-space rule as fences
# and headings, so an indented (code-block) comment marker is content; and an
# UNCLOSED comment REFUSES rather than swallowing to EOF, which closes the
# one case a line reader cannot otherwise resolve (a comment opened inside a
# list item) in the fail-safe direction.
# REORDERED FOR FIRST-BLOCK-WINS (F7-2026, ruled 2026-08-29), not just re-graded.
# These two shapes used a good first block and a bad SECOND one, so under
# last-block-wins the second decided and the case read `malformed`. Under
# first-block-wins a trailing block cannot decide anything, so simply flipping
# the expectation to `ok` would have left the construction under test unable to
# change the answer: a green labelled with the verdict instead of the evidence.
# The construction now comes BEFORE the only real verdict, which is where it can
# still discriminate: read as a fence opener, it would mis-scope and the reader
# would not say `ok`.
qa_atx_case "backtick-info-not-a-fence" ok '## Closing report

```` ```qa-pass-1 ```` is the fence you need.

```qa-pass-1
smoke: PASS
```'
qa_atx_case "backtick-info-nested-not-promoted" none '## Closing report

```qa-pass-1``` is the fence label used below.

````
$ setlist verify
```qa-pass-1
smoke: PASS
```
(verifier exited 0)
````'
qa_atx_case "backtick-info-section-no-leak" none '## Closing report

QA Pass 1 has not been run yet.

```qa-pass-1``` is the fence label required by Part 6.

## Appendix A

```text
(shape)
```

```qa-pass-1
example: PASS
```'
qa_atx_case "indented-comment-is-content" ok '## Closing report

    <!-- reviewer note kept verbatim in a code block

```qa-pass-1
smoke: PASS
```'

# F7-2026's DIRECTION, asserted both ways. A trailing block cannot replace a
# real verdict, and a MALFORMED first block is not rescued by a good second.
qa_atx_case "first-block-wins-example-after" ok '## Closing report

```qa-pass-1
smoke: PASS
```

An illustrative block, which is not a verdict:

```qa-pass-1
this line is prose
```'
qa_atx_case "first-block-wins-bad-first" malformed '## Closing report

```qa-pass-1
this line is prose
```

```qa-pass-1
smoke: PASS
```'
qa_atx_case "unclosed-comment-refuses" unclosed-comment '## Closing report

```qa-pass-1
smoke: PASS
```

- reviewer note

  <!-- internal: do not ship

```qa-pass-1
smoke: regressed
```'
# KNOWN LIMITATION, PINNED (adversary finding 9): setext headings (a line
# underlined with ---- or ====) do not end the section. Markdown calls them
# headings; the reader reads ATX only, the framework's own documents write
# ATX only, and widening the reader is exactly the parser-repair class the
# freeze doctrine prices. Pinned GREEN so a future widening fails here loudly
# and gets judged rather than slipping in.
qa_atx_case "setext-pinned-limitation" ok '## Closing report

No QA was run.

Appendix
--------

```qa-pass-1
criterion: PASS
```'
if [[ -z "$QA_ATX_BAD" ]]; then
  ok "qa heading corpus: ordinary #-prose is content, real headings still scope, 31 shapes"
else
  bad "qa heading corpus: ordinary #-prose is content, real headings still scope, 31 shapes" \
      "the reader and markdown disagree about what a heading is:$QA_ATX_BAD"
fi

# End to end: a spec whose only Closing heading is the no-space spelling has,
# per markdown, NO Closing report section, and the unified exists-grep says so
# with the honest code rather than letting the loose-open reader accept a
# fenced example from a section nothing could close (adversary finding 4).
NSC="$WORK/qa-nospace-close"; rm -rf "$NSC"; close_fixture "$NSC" no no answered no no true
git -C "$NSC" checkout -q spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n##Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- Architecture diagram: no impact\n' > "$NSC/specs/0001-thing.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$NSC/specs/STATUS.md"
git -C "$NSC" add -A >/dev/null 2>&1; git -C "$NSC" commit -qm ns >/dev/null 2>&1
git -C "$NSC" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$NSC" "$(bash_payload "$MERGE_CMD")"
expect_deny "qa heading e2e: a no-space ##Closing report is not a section, refused with the section code" "CG-NO-CLOSING-REPORT"

# =============================================================================
# THE PUSH-TIME SCAN: KL2 AND THE FOUR SCAN SUB-HOLES (spec 0121, 2026-08-26).
#
# Every case pushes to a real local bare remote through the armed hook layer,
# because what is being asserted is what git's own invocation of pre-push
# decides, not what a function returns when called directly.
#
# THE SCAN IS ISOLATED FROM THE AUDIT by putting the secret OUTSIDE the declared
# role paths, so the trunk audit has nothing to say and only the scan can refuse.
# A first cut of this block put it in src/, and then the audit refused three of
# the cases for its own unrelated reason: the assertions passed while proving
# nothing about the scan. The two KL2 cases below are the exception, because they
# are ABOUT which check the escape variable turns off.
#
# Watched RED first against the pre-fix bytes, all six subjects, with both
# controls holding in the same run: the plain-secret control, KL2's scan case,
# SC3, SC4, SC5 and SC6 were all PUSHED where they should have been REFUSED.
# =============================================================================
sp_mk() { # sp_mk <name> -> an armed instance with a bare remote, prints its path
  local d="$WORK/sp-$1"
  rm -rf "$d" "$WORK/sp-$1.git"
  mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs" "$d/docs"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm base >/dev/null 2>&1
  git init -q --bare "$WORK/sp-$1.git"
  git -C "$d" remote add origin "$WORK/sp-$1.git"
  printf '%s' "$d"
}
sp_commit() { # sp_commit <dir> <path> <content>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$1" commit -qm "add $2" >/dev/null 2>&1
}
sp_push() { # sp_push <dir> [env-assignment...] -> 0 when the push LANDED
  local d="$1"; shift
  env "$@" git -C "$d" push -q origin main >/dev/null 2>&1
}
SP_SECRET='api_key = "AKIAQQQQZZZZ1234567890abcd"'

# CONTROL a, the ALLOW direction. Without it every refusal below would pass
# against a hook that refuses everything.
SPD="$(sp_mk clean)"; SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -q --allow-empty -m x >/dev/null 2>&1
if sp_push "$SPD"; then
  ok "push scan control a: a clean push succeeds"
else
  bad "push scan control a: a clean push succeeds" \
      "a clean first push was refused, so every refusal below proves nothing. This is the shape the SC4 fix broke and its own control caught: merge-base(trunk, tip) IS the tip, so a naive range is empty for the trunk itself"
fi

# CONTROL b, the DENY direction, and it is also SC4's subject: a first push whose
# history carries a secret. On the pre-fix bytes this PUSHED.
SPD="$(sp_mk plain)"; sp_commit "$SPD" docs/a.txt "$SP_SECRET"
if sp_push "$SPD"; then
  bad "push scan control b: a secret in a first push is refused (SC sub-hole 4)" \
      "it pushed. The first push of a trunk has no remote oid and no merge base with itself, so the range came out empty and the push that ESTABLISHES a repository is scanned by nothing"
else
  ok "push scan control b: a secret in a first push is refused (SC sub-hole 4)"
fi

# KL2, direction 1: the AUDIT escape must not turn the SCAN off.
SPD="$(sp_mk kl2a)"; sp_commit "$SPD" src/a.txt "$SP_SECRET"
if sp_push "$SPD" SETLIST_SKIP_TRUNK_AUDIT=1; then
  bad "KL2: SETLIST_SKIP_TRUNK_AUDIT=1 does NOT skip the content scan" \
      "the secret was published. The audit's escape is turning off the secret scan as well, which is the whole of KL2: the variable is named for the audit and must skip the audit"
else
  ok "KL2: SETLIST_SKIP_TRUNK_AUDIT=1 does NOT skip the content scan"
fi

# KL2, direction 2: it really does skip the audit. Asserted because a narrowing
# that quietly stopped honouring the variable would also pass direction 1.
SPD="$(sp_mk kl2b)"; sp_commit "$SPD" src/f.txt 'ordinary feature code'
if sp_push "$SPD" SETLIST_SKIP_TRUNK_AUDIT=1; then
  ok "KL2 control: SETLIST_SKIP_TRUNK_AUDIT=1 still skips the audit"
else
  bad "KL2 control: SETLIST_SKIP_TRUNK_AUDIT=1 still skips the audit" \
      "the escape no longer works at all, so direction 1 above proves nothing about narrowing"
fi

# KL2, direction 3: without the escape that same push IS refused by the audit,
# which is what makes direction 2 a skip rather than a clean trunk.
SPD="$(sp_mk kl2c)"; sp_commit "$SPD" src/f.txt 'ordinary feature code'
if sp_push "$SPD"; then
  bad "KL2 control: with no escape the audit refuses that same push" \
      "it pushed with no escape set, so the case above proves nothing"
else
  ok "KL2 control: with no escape the audit refuses that same push"
fi

# SC sub-hole 3: content ADDED and then REMOVED inside the pushed range. An
# endpoint diff never renders it while every object still reaches the remote.
SPD="$(sp_mk sc3)"; sp_commit "$SPD" docs/a.txt "$SP_SECRET"
rm -f "$SPD/docs/a.txt"; git -C "$SPD" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -qm rm >/dev/null 2>&1
if sp_push "$SPD"; then
  bad "SC sub-hole 3: a secret added then removed inside the range is refused" \
      "it pushed. The scan is reading an ENDPOINT diff again, so it asks what the range CHANGES when the question is what the range CARRIES"
else
  ok "SC sub-hole 3: a secret added then removed inside the range is refused"
fi

# SC sub-hole 5: a TAG push carrying a secret no pushed branch reaches.
SPD="$(sp_mk sc5)"; SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -q --allow-empty -m base >/dev/null 2>&1
git -C "$SPD" push -q origin main >/dev/null 2>&1
git -C "$SPD" checkout -q -b side
sp_commit "$SPD" docs/a.txt "$SP_SECRET"
git -C "$SPD" tag sp-v9.9.9 >/dev/null 2>&1
git -C "$SPD" checkout -q main; git -C "$SPD" branch -qD side >/dev/null 2>&1
if git -C "$SPD" push -q origin sp-v9.9.9 >/dev/null 2>&1; then
  bad "SC sub-hole 5: a tag push carrying a secret is refused" \
      "it pushed. Every ref that is not refs/heads/* is being skipped, and a tag can name a commit no branch reaches, so it is the one shape where the content is reachable ONLY through the ref being pushed"
else
  ok "SC sub-hole 5: a tag push carrying a secret is refused"
fi

# SC sub-hole 6: a secret on a line whose own content begins with +++, which the
# unanchored header strip removed from the scan's input.
SPD="$(sp_mk sc6)"; sp_commit "$SPD" docs/a.txt "+++$SP_SECRET"
if sp_push "$SPD"; then
  bad "SC sub-hole 6: a secret behind a +++ prefix is refused" \
      "it pushed. The header strip is unanchored again, so it is eating added lines whose content starts with ++ as well as the diff's own +++ b/ header"
else
  ok "SC sub-hole 6: a secret behind a +++ prefix is refused"
fi

# ===========================================================================
# KL4: PATH-SCOPED SCANS, THE DECLARED EXCLUSION SET NAMED OUT LOUD (spec 0122).
#
# The em-dash and secret scans read every added line, so a vendored tree, a
# fixture carrying a dummy credential, and quoted external text are refused
# identically to the author's own writing. The fix is a DECLARED set of
# repo-relative globs in .claude/sdd.json, honoured by both content scans at
# both the commit and the push layer.
#
# WHAT THIS BLOCK IS EVIDENCE OF, said once so no green below is read as more
# than it is (A8). An excluded-path green is evidence of SCOPING, never of
# scanning: it proves the scan declined to read a path it was told to decline,
# and it proves nothing at all about the scanner. That is why every excluded
# cell has a non-excluded twin immediately beside it, and why the twin is the
# assertion that keeps the pair honest.
#
# THE SKIP IS NAMED, EVERY TIME. An exclusion nobody is told about is the same
# hole one directory over, which this project has already paid for once in the
# hooksPath displacement. So the assertions below check the OUTPUT as well as
# the verdict: a clean commit whose stderr says nothing about the file it did
# not read would fail here even though the commit succeeded.
# ===========================================================================

KL4_SECRET='const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";'
KL4_DASHLINE="a $EMDASH b"

kl4_fixture() { # kl4_fixture <dir> [scan_exclusions-json]
  local d="$1" ex="${2:-}"
  rm -rf "$d" "$d-rem.git"
  mkdir -p "$d/src" "$d/vendor/dep" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"
  if [[ -n "$ex" ]]; then
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"scan_exclusions":%s}\n' "$ex" > "$d/.claude/sdd.json"
  else
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  fi
  printf 'x\n' > "$d/src/app.js"
  printf 'v\n' > "$d/vendor/dep/lib.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  # pre-push refuses for want of the audit tool if this is missing, and every
  # case below would then pass while reaching nothing (the fixture gap that
  # produced a false refutation during the F2 triage).
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # The remote is seeded with a trunk so it is NOT empty: on an empty remote
  # every pushed ref is a trunk candidate and IS audited, which would refuse
  # these branches for a reason that has nothing to do with the scan.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b work
}

KL4_ERR=""
kl4_commit() { # kl4_commit <dir> <msg> -> rc, output in KL4_ERR
  KL4_ERR="$(git -C "$1" commit -qm "$2" 2>&1)"
}
kl4_push() { # kl4_push <dir> <branch> -> rc, output in KL4_ERR
  KL4_ERR="$(git -C "$1" push -q origin "$2" 2>&1)"
}

# --- the four cells, both directions at both layers -------------------------

# CELL 1: an excluded path carrying BOTH shapes commits clean AND says so.
KL4A="$WORK/kl4-commit-excluded"; kl4_fixture "$KL4A" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4A/vendor/dep/lib.js"
git -C "$KL4A" add -A >/dev/null 2>&1
if kl4_commit "$KL4A" "vendored"; then
  ok "KL4 cell 1a: an excluded path carrying an em-dash and a secret COMMITS clean"
else
  bad "KL4 cell 1a: an excluded path carrying an em-dash and a secret COMMITS clean" \
      "refused: $KL4_ERR"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/dep/lib.js' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/\*\*'; then
  ok "KL4 cell 1b: the commit-layer skip NAMES the path and the glob that caused it"
else
  bad "KL4 cell 1b: the commit-layer skip NAMES the path and the glob that caused it" \
      "a scan that silently skips a path is the vacuous-green class wearing a feature's name. stderr was: $KL4_ERR"
fi

# CELL 2: the IDENTICAL content on a non-excluded path is still refused, with
# the existing codes. Without this the cell above is satisfied by a hook that
# stopped scanning.
KL4B="$WORK/kl4-commit-scanned"; kl4_fixture "$KL4B" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4B/src/app.js"
git -C "$KL4B" add -A >/dev/null 2>&1
if kl4_commit "$KL4B" "mine"; then
  bad "KL4 cell 2a: the identical content on a NON-excluded path is still refused at commit" \
      "it committed, so the exclusion set is over-wide and the scan is off for everything"
else
  ok "KL4 cell 2a: the identical content on a NON-excluded path is still refused at commit"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-EMDASH' && printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 cell 2b: the refusal carries the EXISTING codes, both of them"
else
  bad "KL4 cell 2b: the refusal carries the EXISTING codes, both of them" "stderr was: $KL4_ERR"
fi

# CELL 3: the push layer, excluded path. The commit is made with the hooks
# bypassed so the PUSH is what is being measured.
KL4C="$WORK/kl4-push-excluded"; kl4_fixture "$KL4C" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4C/vendor/dep/lib.js"
git -C "$KL4C" add -A >/dev/null 2>&1
git -C "$KL4C" -c core.hooksPath=/dev/null commit -qm "vendored" >/dev/null 2>&1
if kl4_push "$KL4C" work; then
  ok "KL4 cell 3a: an excluded path carrying an em-dash and a secret PUSHES clean"
else
  bad "KL4 cell 3a: an excluded path carrying an em-dash and a secret PUSHES clean" \
      "refused: $KL4_ERR"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/dep/lib.js'; then
  ok "KL4 cell 3b: the push-layer skip NAMES the path, at the layer that publishes"
else
  bad "KL4 cell 3b: the push-layer skip NAMES the path, at the layer that publishes" \
      "stderr was: $KL4_ERR"
fi

# CELL 4: the push layer, non-excluded path, still refuses.
KL4D="$WORK/kl4-push-scanned"; kl4_fixture "$KL4D" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4D/src/app.js"
git -C "$KL4D" add -A >/dev/null 2>&1
git -C "$KL4D" -c core.hooksPath=/dev/null commit -qm "mine" >/dev/null 2>&1
if kl4_push "$KL4D" work; then
  bad "KL4 cell 4: the identical content on a NON-excluded path is still refused at push" \
      "it pushed, so the secret reached a remote and the exclusion set is scoping the whole scan"
else
  ok "KL4 cell 4: the identical content on a NON-excluded path is still refused at push"
fi

# --- the default: absence changes NOTHING, proven rather than asserted ------
#
# The feature is invisible until asked for, and "byte-identical to today" is a
# claim about BEHAVIOUR that a reading of the code cannot settle. So the two
# generations are run side by side over a corpus, in fixtures that differ in
# nothing but the hook bytes, and the verdict AND the operator-visible output
# are compared exactly. The pre-feature generation is pinned by BLOB, not by a
# revision expression: a blob is immutable, so this differential keeps meaning
# the same thing after every later commit.
KL4_OLD_PRECOMMIT=87e0c147ab413a6448675703d4a16b9e7fc7436a
KL4_OLD_PREMERGE=eac8743342281e4edfe17be7052e713f28f405c2
KL4_OLD_PREPUSH=273d972c024696cda2bb8b9e4d09e4c7cbbd093e
KL4_OLD_LIB=72c493c4efc0fff1ada3e08994ba66045586bed6

if git -C "$ROOT" cat-file -e "$KL4_OLD_LIB" 2>/dev/null; then
  KL4_OLD="$WORK/kl4-default-old"; kl4_fixture "$KL4_OLD"
  KL4_NEW="$WORK/kl4-default-new"; kl4_fixture "$KL4_NEW"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PRECOMMIT" > "$KL4_OLD/.githooks/pre-commit"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PREMERGE"  > "$KL4_OLD/.githooks/pre-merge-commit"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PREPUSH"   > "$KL4_OLD/.githooks/pre-push"
  git -C "$ROOT" cat-file blob "$KL4_OLD_LIB"       > "$KL4_OLD/.githooks/setlist-hook-lib.sh"
  chmod +x "$KL4_OLD/.githooks/pre-commit" "$KL4_OLD/.githooks/pre-merge-commit" "$KL4_OLD/.githooks/pre-push"

  # The corpus. Every shape the header strip and the added-line reader have ever
  # been wrong about, plus the ordinary ones, because a differential over three
  # easy cases proves the easy cases only.
  KL4_DIFF_CASES=0
  KL4_DIFF_BAD=""
  kl4_diff_one() { # kl4_diff_one <label> <path> <content...>
    local label="$1" p="$2"; shift 2
    local d rc out old="" new=""
    for d in "$KL4_OLD" "$KL4_NEW"; do
      mkdir -p "$d/$(dirname "$p")"
      printf '%s\n' "$@" > "$d/$p"
      git -C "$d" add -A >/dev/null 2>&1
      out="$(git -C "$d" commit -qm "$label" 2>&1)"; rc=$?
      out="${out//$d/<DIR>}"
      if [[ "$d" == "$KL4_OLD" ]]; then old="rc=$rc
$out"; else new="rc=$rc
$out"; fi
      [[ "$rc" -eq 0 ]] || { git -C "$d" reset -q --hard HEAD >/dev/null 2>&1; }
    done
    KL4_DIFF_CASES=$((KL4_DIFF_CASES + 1))
    [[ "$old" == "$new" ]] || KL4_DIFF_BAD="$KL4_DIFF_BAD
[$label]
OLD: $old
NEW: $new"
  }

  kl4_diff_one "clean"        src/d1.txt "ordinary content" "second line"
  kl4_diff_one "emdash"       src/d2.txt "$KL4_DASHLINE"
  kl4_diff_one "secret"       src/d3.txt "$KL4_SECRET"
  kl4_diff_one "both"         src/d4.txt "$KL4_DASHLINE" "$KL4_SECRET"
  kl4_diff_one "plusplusplus" src/d5.txt "+++$KL4_SECRET"
  kl4_diff_one "plusplus"     src/d6.txt "++$KL4_DASHLINE"
  kl4_diff_one "forgedheader" src/d7.txt "+++ b/vendor/dep/lib.js" "$KL4_SECRET"
  kl4_diff_one "devnullline"  src/d8.txt "+++ /dev/null" "$KL4_DASHLINE"
  kl4_diff_one "vendorclean"  vendor/dep/other.js "ordinary vendored content"
  kl4_diff_one "vendordirty"  vendor/dep/dirty.js "$KL4_SECRET"
  kl4_diff_one "deepclean"    src/nested/deep/x.txt "nothing to see"
  kl4_diff_one "url"          src/d9.txt 'https://user:supersecretvalue@example.invalid/x'

  if [[ "$KL4_DIFF_CASES" -eq 12 ]]; then
    ok "KL4 default-unchanged: the differential ran all 12 corpus cases (count asserted before comparing)"
  else
    bad "KL4 default-unchanged: the differential ran all 12 corpus cases (count asserted before comparing)" \
        "ran $KL4_DIFF_CASES; a differential over a corpus nobody counted is the vacuous comparison A8 exists for"
  fi
  if [[ -z "$KL4_DIFF_BAD" ]]; then
    ok "KL4 default-unchanged: with NO scan_exclusions key, the new hook bytes are verdict- and output-identical to the pre-feature generation over the whole corpus"
  else
    bad "KL4 default-unchanged: with NO scan_exclusions key, the new hook bytes are verdict- and output-identical to the pre-feature generation over the whole corpus" \
        "the feature is supposed to be invisible until asked for, and it is not:$KL4_DIFF_BAD"
  fi
else
  ok "KL4 default-unchanged: pre-feature hook blobs not present here (export tree); the source-repo run asserts the differential"
fi

# --- malformed config fails CLOSED, at both layers, asserted both ways ------
#
# Never a silent full-scan and never a silent no-scan. Both directions are
# needed because each alone is satisfiable by the wrong fix: a config error that
# quietly scans everything looks fine until somebody relies on the exclusion,
# and a config error that quietly scans nothing is the empty-result-as-verdict
# class with a feature's name on it.
kl4_malformed() { # kl4_malformed <label> <json> <expected-code>
  local label="$1" json="$2" code="$3" d
  d="$WORK/kl4-bad-$label"; kl4_fixture "$d" "$json"
  # DIRECTION ONE: clean content. A malformed set must refuse even here, or the
  # scan is running on an unread configuration.
  printf 'ordinary clean content\n' >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  if kl4_commit "$d" clean; then
    bad "KL4 malformed/$label: CLEAN content is refused at commit (never a silent scan on an unread config)" \
        "it committed, so the hook decided with a configuration it could not read"
  else
    ok "KL4 malformed/$label: CLEAN content is refused at commit (never a silent scan on an unread config)"
  fi
  if printf '%s' "$KL4_ERR" | grep -q "$code"; then
    ok "KL4 malformed/$label: the refusal carries the named code $code"
  else
    bad "KL4 malformed/$label: the refusal carries the named code $code" "stderr was: $KL4_ERR"
  fi
  # DIRECTION TWO: a real secret. A malformed set must not become an accidental
  # exemption.
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  printf '%s\n' "$KL4_SECRET" >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  if kl4_commit "$d" dirty; then
    bad "KL4 malformed/$label: a SECRET is refused at commit (a broken config is not an exemption)" \
        "it committed, so an unparseable exclusion set turned the scan off"
  else
    ok "KL4 malformed/$label: a SECRET is refused at commit (a broken config is not an exemption)"
  fi
  # AND AT THE PUSH LAYER, which is the one that publishes.
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  printf 'ordinary clean content\n' >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
  if kl4_push "$d" work; then
    bad "KL4 malformed/$label: the PUSH layer refuses on the same unreadable config" \
        "it pushed, so the two layers disagree about a configuration neither can read"
  else
    ok "KL4 malformed/$label: the PUSH layer refuses on the same unreadable config"
  fi
  if printf '%s' "$KL4_ERR" | grep -q "$code"; then
    ok "KL4 malformed/$label: the push refusal carries the same named code $code"
  else
    bad "KL4 malformed/$label: the push refusal carries the same named code $code" "stderr was: $KL4_ERR"
  fi
}

kl4_malformed string   '"vendor/**"'            SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed object   '{"a":"b"}'              SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed number   '[123]'                  SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed nested   '[["vendor/**"]]'        SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed empty    '[""]'                   SLH-SCAN-EXCLUSION-INVALID
kl4_malformed dotdot   '["../outside/**"]'      SLH-SCAN-EXCLUSION-INVALID
kl4_malformed space    '["my vendor/**"]'       SLH-SCAN-EXCLUSION-INVALID
kl4_malformed shellish '["vendor/**)rm -rf ."]' SLH-SCAN-EXCLUSION-INVALID
kl4_malformed star     '["*"]'                  SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed starstar '["**"]'                 SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed slashy   '["*/*"]'                SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed anychar  '["?"]'                  SLH-SCAN-EXCLUSION-CATCHALL

# An EMPTY array is not malformed: it is a project that declared the key and
# excluded nothing, and it must behave exactly like absence. This is the
# shipped-template state, so getting it wrong refuses every commit in a freshly
# stamped instance.
#
# THE REFUSAL IS CHECKED BY CODE, NOT BY VERDICT, and this pair is why. The
# first cut of this assertion only asked whether the commit was refused. It was,
# with SLH-SCAN-EXCLUSION-INVALID, because [] and [""] collapsed to the same
# string once command substitution stripped the trailing newline: the reader
# refused a project that had declared nothing, the assertion went green, and the
# defect was found by hook-smoke and delivery-matrix instead. A green labelled
# with the verdict rather than with the evidence (A8), committed by the test for
# that very class.
KL4E="$WORK/kl4-empty-array"; kl4_fixture "$KL4E" '[]'
printf '%s\n' "$KL4_SECRET" >> "$KL4E/src/app.js"
git -C "$KL4E" add -A >/dev/null 2>&1
if kl4_commit "$KL4E" dirty; then
  bad "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses" \
      "it committed, so [] read as 'exclude everything', which is the direction that publishes"
elif printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses"
else
  bad "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses" \
      "it was refused, but not by the scan: $KL4_ERR. A refusal for the wrong reason is a green that proves the opposite of what it claims"
fi
# And the clean twin: an empty set must let ordinary work through, which is the
# direction the shipped template lands in every stamped instance.
git -C "$KL4E" reset -q --hard HEAD >/dev/null 2>&1
printf 'ordinary content\n' >> "$KL4E/src/app.js"
git -C "$KL4E" add -A >/dev/null 2>&1
if kl4_commit "$KL4E" clean; then
  ok "KL4 empty array: and clean content COMMITS, so the shipped template does not refuse every commit in a fresh instance"
else
  bad "KL4 empty array: and clean content COMMITS, so the shipped template does not refuse every commit in a fresh instance" \
      "refused: $KL4_ERR"
fi

# --- the boundary cases the traps live in -----------------------------------

# A glob that matches NOTHING must not read as coverage. The scan still refuses,
# and nothing is announced as skipped: an exclusion that did not fire has no
# business printing that it did.
KL4N="$WORK/kl4-matches-nothing"; kl4_fixture "$KL4N" '["nosuchdir/**"]'
printf '%s\n' "$KL4_SECRET" >> "$KL4N/src/app.js"
git -C "$KL4N" add -A >/dev/null 2>&1
if kl4_commit "$KL4N" dirty; then
  bad "KL4 matches-nothing: a glob matching no path in the change changes no verdict" "it committed"
else
  ok "KL4 matches-nothing: a glob matching no path in the change changes no verdict"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED'; then
  bad "KL4 matches-nothing: nothing is ANNOUNCED as skipped when nothing was skipped" \
      "the hook printed an exclusion notice for a path it scanned, which is a skip report that reads as coverage: $KL4_ERR"
else
  ok "KL4 matches-nothing: nothing is ANNOUNCED as skipped when nothing was skipped"
fi

# PATH NORMALISATION. The declared side is normalised the way role paths already
# are, so the four spellings of one directory mean one thing. The raw-vs-
# normalised split is what made the guarantee layer go blind on "./src" once.
kl4_spelling() { # kl4_spelling <label> <json> <expect: excluded|scanned>
  local label="$1" json="$2" expect="$3" d rc
  d="$WORK/kl4-spell-$label"; kl4_fixture "$d" "$json"
  printf '%s\n' "$KL4_SECRET" >> "$d/vendor/dep/lib.js"
  git -C "$d" add -A >/dev/null 2>&1
  kl4_commit "$d" spell; rc=$?
  if [[ "$expect" == "excluded" ]]; then
    if [[ "$rc" -eq 0 ]] && printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED'; then
      ok "KL4 spelling/$label: $json excludes vendor/dep/lib.js and says so"
    else
      bad "KL4 spelling/$label: $json excludes vendor/dep/lib.js and says so" "rc=$rc stderr: $KL4_ERR"
    fi
  else
    if [[ "$rc" -ne 0 ]]; then
      ok "KL4 spelling/$label: $json does NOT exclude vendor/dep/lib.js, so the scan still refuses"
    else
      bad "KL4 spelling/$label: $json does NOT exclude vendor/dep/lib.js, so the scan still refuses" \
          "it committed, so a spelling that names a different path is silently excluding this one"
    fi
  fi
}
kl4_spelling glob       '["vendor/**"]'      excluded
kl4_spelling single     '["vendor/*"]'       excluded
kl4_spelling bare       '["vendor"]'         excluded
kl4_spelling trailing   '["vendor/"]'        excluded
kl4_spelling dotslash   '["./vendor/**"]'    excluded
kl4_spelling leading    '["/vendor/**"]'     excluded
kl4_spelling doubled    '["vendor//dep/**"]' excluded
kl4_spelling exactfile  '["vendor/dep/lib.js"]' excluded
kl4_spelling suffix     '["*.js"]'           excluded
# CASE IS EXACT, DELIBERATELY, and the direction is the safe one: a case variant
# fails to match, so the scan RUNS. On a case-insensitive filesystem the file is
# the same file, and an exclusion that guessed would be an exclusion nobody
# declared. Pinned so a later widening is a decision rather than drift.
kl4_spelling casevariant '["VENDOR/**"]'     scanned
kl4_spelling neighbour   '["vendors/**"]'    scanned
kl4_spelling prefixonly  '["vend"]'          scanned

# A CONTENT LINE CANNOT FORGE A FILE HEADER. Added lines carry a prefix column,
# so `diff --git` and `@@` are unforgeable inside a hunk; attribution is taken
# from the header state machine rather than from any line that looks like one.
# Without that, a diff-of-a-diff could point the scanner's attribution at an
# excluded path and carry a secret through under its name.
KL4F="$WORK/kl4-forged-attribution"; kl4_fixture "$KL4F" '["vendor/**"]'
{ printf '%s\n' "+++ b/vendor/dep/lib.js"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4F/src/app.js"
git -C "$KL4F" add -A >/dev/null 2>&1
if kl4_commit "$KL4F" forged; then
  bad "KL4 forged attribution: a content line spelled like a file header cannot move a secret into an excluded path" \
      "it committed. The scanner is taking attribution from line text rather than from diff structure, so any excluded glob is a universal exemption for anyone who can write one line"
else
  ok "KL4 forged attribution: a content line spelled like a file header cannot move a secret into an excluded path"
fi

# MIXED CHANGE: one excluded file and one scanned file in the SAME commit. The
# excluded half is skipped and named, the scanned half still refuses. A filter
# that worked per-commit rather than per-path would pass this by exempting both.
KL4M="$WORK/kl4-mixed"; kl4_fixture "$KL4M" '["vendor/**"]'
printf '%s\n' "$KL4_SECRET" >> "$KL4M/vendor/dep/lib.js"
printf '%s\n' "$KL4_SECRET" >> "$KL4M/src/app.js"
git -C "$KL4M" add -A >/dev/null 2>&1
if kl4_commit "$KL4M" mixed; then
  bad "KL4 mixed change: an excluded file beside a scanned file does not exempt the scanned one" \
      "it committed, so the exclusion is scoped to the COMMIT rather than to the PATH"
else
  ok "KL4 mixed change: an excluded file beside a scanned file does not exempt the scanned one"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' && printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 mixed change: the same output carries BOTH the named skip and the refusal it did not cover"
else
  bad "KL4 mixed change: the same output carries BOTH the named skip and the refusal it did not cover" \
      "stderr was: $KL4_ERR"
fi

# --- the negative boundary: the set scopes the CONTENT scans and NOTHING else
#
# The scans are a seatbelt and an exclusion set that can hide anything is not
# one. These assert the negative the spec asks for: a glob covering a role path,
# the specs tree, or the config itself changes no judgment anywhere else.
KL4_ROLE="$WORK/kl4-neg-role"; kl4_fixture "$KL4_ROLE" '["src/**","specs/**",".claude/**"]'
printf 'unspecced feature code\n' > "$KL4_ROLE/src/feature.js"
git -C "$KL4_ROLE" add -A >/dev/null 2>&1
git -C "$KL4_ROLE" -c core.hooksPath=/dev/null commit -qm work >/dev/null 2>&1
git -C "$KL4_ROLE" checkout -q main
if ( cd "$KL4_ROLE" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close" work ) >/dev/null 2>&1; then
  bad "KL4 negative/role-path: a glob covering a role path changes NOTHING about role-path judgment" \
      "the merge landed unspecced feature code on the trunk, so the exclusion set reached SLH-CLOSES-NO-SPEC"
else
  ok "KL4 negative/role-path: a glob covering a role path changes NOTHING about role-path judgment"
fi

# LIFECYCLE DETECTION: a spec Status line moves without specs/STATUS.md staged.
# The glob covers specs/, and the detector must not care.
KL4_LC="$WORK/kl4-neg-lifecycle"; kl4_fixture "$KL4_LC" '["specs/**"]'
printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$KL4_LC/specs/0001-thing.md"
git -C "$KL4_LC" add specs/0001-thing.md >/dev/null 2>&1
if kl4_commit "$KL4_LC" lifecycle; then
  bad "KL4 negative/lifecycle: a glob covering specs/ changes NOTHING about lifecycle detection" \
      "it committed, so the exclusion set reached SLH-STATUS-MISSING"
else
  ok "KL4 negative/lifecycle: a glob covering specs/ changes NOTHING about lifecycle detection"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-STATUS-MISSING'; then
  ok "KL4 negative/lifecycle: and the refusal is still the lifecycle code, not a scan code"
else
  bad "KL4 negative/lifecycle: and the refusal is still the lifecycle code, not a scan code" "stderr was: $KL4_ERR"
fi

# THE CLOSE CHECKS: a row flips to CLOSED with no Closing report, under a glob
# that covers the specs tree AND the config that declares the glob.
KL4_CL="$WORK/kl4-neg-close"; kl4_fixture "$KL4_CL" '["specs/**",".claude/**"]'
printf '# Spec 0001\n\nStatus: CLOSED\n' > "$KL4_CL/specs/0001-thing.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$KL4_CL/specs/STATUS.md"
printf 'work\n' > "$KL4_CL/src/FEATURE.txt"
git -C "$KL4_CL" add -A >/dev/null 2>&1
git -C "$KL4_CL" -c core.hooksPath=/dev/null commit -qm close >/dev/null 2>&1
git -C "$KL4_CL" checkout -q main
if ( cd "$KL4_CL" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close" work ) >/dev/null 2>&1; then
  bad "KL4 negative/close-checks: a glob covering specs/ and the config changes NOTHING about the close checks" \
      "a spec with no Closing report closed on the trunk, so the exclusion set reached the guarantee layer"
else
  ok "KL4 negative/close-checks: a glob covering specs/ and the config changes NOTHING about the close checks"
fi

# THE TRUNK AUDIT: an exclusion set does not quiet the push-time audit.
KL4_TA="$WORK/kl4-neg-audit"; kl4_fixture "$KL4_TA" '["src/**","specs/**"]'
git -C "$KL4_TA" checkout -q main
printf 'straight to the trunk\n' > "$KL4_TA/src/direct.js"
git -C "$KL4_TA" add -A >/dev/null 2>&1
git -C "$KL4_TA" -c core.hooksPath=/dev/null commit -qm direct >/dev/null 2>&1
if kl4_push "$KL4_TA" main; then
  bad "KL4 negative/trunk-audit: a glob covering the role paths changes NOTHING about the trunk audit" \
      "it pushed, so the exclusion set is scoping a check it was never given"
else
  ok "KL4 negative/trunk-audit: a glob covering the role paths changes NOTHING about the trunk audit"
fi

# --- A9: ONE reader, in the shared lib, called by both layers ---------------
#
# The same shape the lexer lockstep assertions carry. Three copies of a rule is
# how a gate and its backstop went blind together in leg 5; the exclusion reader
# gets the assertion rather than a comment asking people to remember.
KL4_READERS="$(grep -l 'scan_exclusions' "$ROOT/templates/git-hooks/"* 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$KL4_READERS" == "1" ]] && grep -q 'scan_exclusions' "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; then
  ok "KL4 A9: exactly ONE file under templates/git-hooks/ names the scan_exclusions key, and it is the shared lib"
else
  bad "KL4 A9: exactly ONE file under templates/git-hooks/ names the scan_exclusions key, and it is the shared lib" \
      "$KL4_READERS files read it; a second reader of one value is the defect class this hook layer was repaired for"
fi
KL4_JQ_READS="$(grep -c 'scan_exclusions' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | tr -d ' ')"
if [[ "$KL4_JQ_READS" -ge 1 ]] && [[ "$(grep -c 'slh_scan_exclusions_load()' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | tr -d ' ')" == "1" ]]; then
  ok "KL4 A9: the reader has exactly one implementation (slh_scan_exclusions_load)"
else
  bad "KL4 A9: the reader has exactly one implementation (slh_scan_exclusions_load)" \
      "found $(grep -c 'slh_scan_exclusions_load()' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null) definitions"
fi
KL4_CALLERS=0
for h in pre-commit pre-merge-commit pre-push; do
  grep -q 'slh_scan_added' "$ROOT/templates/git-hooks/$h" && KL4_CALLERS=$((KL4_CALLERS + 1))
done
if [[ "$KL4_CALLERS" -eq 3 ]]; then
  ok "KL4 A9: all three content-seeing layers reach the scan through the one shared entry point"
else
  bad "KL4 A9: all three content-seeing layers reach the scan through the one shared entry point" \
      "$KL4_CALLERS of 3 call slh_scan_added; a layer that scans its own way is a layer the exclusion set does not govern"
fi

# --- THE ADVISORY SESSION GATE IS NOT PATH-SCOPED, AND THAT IS MEASURED -----
#
# THIS IS A GAP, PINNED RATHER THAN CLOSED. templates/hooks/commit-gate.sh runs
# its own em-dash and secret scans over the whole staged diff, in a different
# tree, without sourcing this library, and spec 0122 does not name it: its Owner
# docs list the git-hook layer, the delivery scripts, the suite, the edition and
# the public bullet, and its design contract says anything beyond the declared
# shape goes back to the owner rather than being decided at working time.
#
# So the consequence is asserted instead of fixed, because an unasserted gap is
# the one that surprises somebody: inside a Claude Code session, a commit of
# excluded content is still DENIED by the advisory gate, while the same commit
# run outside a session (or after the advisory ALLOW) is accepted by the git
# hooks. The feature works at the layer carrying the guarantee and does not yet
# work at the layer carrying the convenience. Filed for the owner as KL4-A1.
#
# The assertion is written in the CURRENT direction on purpose. If somebody
# later scopes the advisory gate too, this goes red and says so, which is the
# right way for a pinned limitation to be reopened: by a decision, not by drift.
CGX="$WORK/kl4-advisory-gate"; kl4_fixture "$CGX" '["vendor/**"]'
printf '%s\n' "$KL4_SECRET" >> "$CGX/vendor/dep/lib.js"
git -C "$CGX" add -A >/dev/null 2>&1
CGX_OUT="$(printf '%s' "$(bash_payload 'git commit -m x')" | CLAUDE_PROJECT_DIR="$CGX" bash "$HOOKS/commit-gate.sh" 2>/dev/null)"
CGX_V="$(printf '%s' "$CGX_OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [[ "$CGX_V" == "deny" ]]; then
  ok "KL4 gap KL4-A1 (PINNED, not closed): the ADVISORY commit gate is not path-scoped, so it still denies excluded content inside a session"
else
  bad "KL4 gap KL4-A1 (PINNED, not closed): the ADVISORY commit gate is not path-scoped, so it still denies excluded content inside a session" \
      "the advisory gate stopped denying. If that was deliberate, this is the assertion to update, in the commit that made the decision and with the ledger row and the public bullet moved with it; if it was not, the two layers have silently drifted apart on what the exclusion set governs"
fi
# The twin that keeps the pin honest: the GUARANTEE layer, same content, same
# config, accepts it. Without this the assertion above is satisfied by a repo
# where nothing works at all.
if git -C "$CGX" -c core.hooksPath=.githooks commit -qm vendored >/dev/null 2>&1; then
  ok "KL4 gap KL4-A1 twin: the guarantee layer accepts the same content the advisory gate denies, which is what makes the gap a gap rather than a feature that does not work"
else
  bad "KL4 gap KL4-A1 twin: the guarantee layer accepts the same content the advisory gate denies, which is what makes the gap a gap rather than a feature that does not work" \
      "the git hooks refused too, so the feature is not working at the layer it was built for"
fi

# --- delivery: the config surface is stamped and survives a refresh ---------
KL4_TMPL="$ROOT/templates/claude/sdd.json.tmpl"
if jq -e 'has("scan_exclusions") and (.scan_exclusions | type) == "array" and (.scan_exclusions | length) == 0' "$KL4_TMPL" >/dev/null 2>&1; then
  ok "KL4 delivery: the stamped sdd.json template DECLARES scan_exclusions, empty, so the surface is discoverable without changing a verdict"
else
  bad "KL4 delivery: the stamped sdd.json template DECLARES scan_exclusions, empty, so the surface is discoverable without changing a verdict" \
      "a config surface nobody can find is a feature nobody has; an empty array is byte-identical in behaviour to absence and names the key"
fi

# PRESERVED ACROSS AN UPGRADE. A declared set that a refresh silently dropped
# would turn a working exclusion into a wall of refusals on the next commit, at
# the moment the operator is least expecting the hooks to have changed their
# mind. refresh-instance.sh rewrites .plugin.version through jq and nothing
# else, so preservation is a property of how it writes rather than a special
# case for this key; the assertion pins that property where this key can see it.
KL4_INST="$WORK/kl4-refresh-preserve"
if instance_fixture "$KL4_INST" 1.0.0 >/dev/null 2>&1; then
  jq '. + {scan_exclusions: ["vendor/**", "test/fixtures/**"]}' "$KL4_INST/.claude/sdd.json" > "$KL4_INST/.claude/sdd.json.new" \
    && mv "$KL4_INST/.claude/sdd.json.new" "$KL4_INST/.claude/sdd.json"
  bash "$SCRIPTS/refresh-instance.sh" --apply "$KL4_INST" >/dev/null 2>&1
  KL4_KEPT="$(jq -c '.scan_exclusions' "$KL4_INST/.claude/sdd.json" 2>/dev/null)"
  if [[ "$KL4_KEPT" == '["vendor/**","test/fixtures/**"]' ]]; then
    ok "KL4 delivery: a refresh PRESERVES a declared exclusion set, value for value"
  else
    bad "KL4 delivery: a refresh PRESERVES a declared exclusion set, value for value" \
        "after the refresh the set reads $KL4_KEPT; an upgrade that drops it turns a working exclusion into a wall of refusals nobody asked for"
  fi
  if [[ "$(jq -r '.plugin.version' "$KL4_INST/.claude/sdd.json" 2>/dev/null)" == "$PLUGIN_VERSION" ]]; then
    ok "KL4 delivery: and the refresh it survived was a REAL one (the version moved)"
  else
    bad "KL4 delivery: and the refresh it survived was a REAL one (the version moved)" \
        "the version did not move, so the preservation assertion above survived a refresh that did not happen"
  fi
else
  bad "KL4 delivery: the refresh fixture builds" "instance_fixture failed, so the preservation assertions test nothing"
fi

# ABSENCE STAYS ABSENT. The other half of opt-in: a refresh must not invent the
# key, because a key that appears on upgrade is a config surface the operator
# never chose and a diff they have to explain.
KL4_INST2="$WORK/kl4-refresh-absent"
if instance_fixture "$KL4_INST2" 1.0.0 >/dev/null 2>&1; then
  bash "$SCRIPTS/refresh-instance.sh" --apply "$KL4_INST2" >/dev/null 2>&1
  if jq -e 'has("scan_exclusions") | not' "$KL4_INST2/.claude/sdd.json" >/dev/null 2>&1; then
    ok "KL4 delivery: a refresh does NOT invent the key in an instance that never declared one"
  else
    bad "KL4 delivery: a refresh does NOT invent the key in an instance that never declared one" \
        "the upgrade added a config surface the operator did not choose"
  fi
else
  bad "KL4 delivery: the absent-key refresh fixture builds" "instance_fixture failed"
fi

# =============================================================================
# RP1: THE STRUCTURED STATUS RECORD (spec 0126, edition v1.12).
#
# The machine reads only records whose grammar it owns. These cases pin four
# properties, in the order a reader should doubt them: the seven jq readers are
# BYTE-IDENTICAL across the three carriers (the lockstep, extended); the two
# frozen awk readers are byte-identical to the PRE-RECORD generation pinned in
# test/fixtures/pre-record-hooks (the absence path retained, proven against
# the blob rather than inspected); a present-and-malformed record REFUSES on
# otherwise CLEAN content at every layer that reads it, and never falls back;
# and absence is byte-identical to the pre-record generation across a case
# battery, with a discrimination control proving the differential can see a
# difference at all.
# =============================================================================

# --- the lockstep, extended to the record readers ---------------------------
RP1_JQ_NAMES='SLH_RECORD_CHECK_JQ SLH_RECORD_CLOSED_JQ SLH_RECORD_ACTIVE_JQ SLH_RECORD_DONE_JQ SLH_RECORD_STATUS_JQ SLH_RECORD_FACTS_JQ SLH_RECORD_CHORE_FILES_JQ'
RP1_LOCK_BAD=""
for RP1_NAME in $RP1_JQ_NAMES; do
  RP1_REF="$(grep -m1 -E "^[[:space:]]*${RP1_NAME}=" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*//')"
  [[ -n "$RP1_REF" ]] || RP1_LOCK_BAD="$RP1_LOCK_BAD lib:$RP1_NAME:absent"
  for RP1_F in "$SCRIPTS/trunk-audit.sh" "$HOOKS/close-gate.sh"; do
    RP1_GOT="$(grep -m1 -E "^[[:space:]]*${RP1_NAME}=" "$RP1_F" | sed 's/^[[:space:]]*//')"
    # fail-open-ok: an absent line is recorded as a mismatch, not skipped.
    [[ "$RP1_GOT" == "$RP1_REF" && -n "$RP1_GOT" ]] || RP1_LOCK_BAD="$RP1_LOCK_BAD $(basename "$RP1_F"):$RP1_NAME"
  done
done
if [[ -z "$RP1_LOCK_BAD" ]]; then
  ok "record lockstep: all seven SLH_RECORD_*_JQ readers are byte-identical across the hook library, trunk-audit.sh and close-gate.sh"
else
  bad "record lockstep: all seven SLH_RECORD_*_JQ readers are byte-identical across the hook library, trunk-audit.sh and close-gate.sh" \
      "mismatched or absent:$RP1_LOCK_BAD"
fi

# The advisory commit gate keeps its OWN copy rather than sourcing the library
# (the KL4-A1 ruling: the trees are separate, the RULE is shared and the suite
# is what asserts it). Compare VALUES after stripping the differing names.
RP1_CM_VAL="$(grep -m1 -E '^[[:space:]]*CM_RECORD_CHECK_JQ=' "$HOOKS/commit-gate.sh" | sed 's/^[[:space:]]*CM_RECORD_CHECK_JQ=//')"
RP1_LIB_VAL="$(grep -m1 -E '^[[:space:]]*SLH_RECORD_CHECK_JQ=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*SLH_RECORD_CHECK_JQ=//')"
if [[ -n "$RP1_CM_VAL" && "$RP1_CM_VAL" == "$RP1_LIB_VAL" ]]; then
  ok "record lockstep: commit-gate's CM_RECORD_CHECK_JQ carries the library's grammar byte for byte"
else
  bad "record lockstep: commit-gate's CM_RECORD_CHECK_JQ carries the library's grammar byte for byte" \
      "the advisory copy drifted from the library's, so the two layers would disagree about what parses"
fi

# --- the frozen readers, byte-identical to the PRE-RECORD blob --------------
RP1_PRE="$ROOT/test/fixtures/pre-record-hooks"
if [[ ! -d "$RP1_PRE" ]]; then
  ok "record frozen readers: SKIPPED, the pre-record hook blobs are not present in this tree (export copy)"
else
  RP1_FROZEN_BAD=""
  for RP1_AWKNAME in QA_PASS1_AWK TEMPLATE_FENCE_AWK LIVE_TEXT_AWK; do
    for RP1_PAIR in \
      "templates/git-hooks/setlist-hook-lib.sh:setlist-hook-lib.sh" \
      "scripts/trunk-audit.sh:trunk-audit.sh" \
      "templates/hooks/close-gate.sh:close-gate.sh"; do
      RP1_CUR="$ROOT/${RP1_PAIR%%:*}"; RP1_OLD="$RP1_PRE/${RP1_PAIR#*:}"
      RP1_CURL="$(grep -m1 -E "^[[:space:]]*(SLH_)?${RP1_AWKNAME}=" "$RP1_CUR" | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
      RP1_OLDL="$(grep -m1 -E "^[[:space:]]*(SLH_)?${RP1_AWKNAME}=" "$RP1_OLD" | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
      # fail-open-ok: an empty extraction is a mismatch, never a silent pass.
      [[ -n "$RP1_CURL" && "$RP1_CURL" == "$RP1_OLDL" ]] || RP1_FROZEN_BAD="$RP1_FROZEN_BAD ${RP1_PAIR%%:*}:$RP1_AWKNAME"
    done
  done
  if [[ -z "$RP1_FROZEN_BAD" ]]; then
    ok "record frozen readers: the three frozen awk programs are byte-identical to the pre-record generation in all three carriers (the absence path is RETAINED, proven against the pinned blob)"
  else
    bad "record frozen readers: the three frozen awk programs are byte-identical to the pre-record generation in all three carriers (the absence path is RETAINED, proven against the pinned blob)" \
        "drifted:$RP1_FROZEN_BAD; the frozen readers are never repaired and never removed"
  fi
fi

# --- a structured fixture builder --------------------------------------------
# rp1_fixture <dir> -> a stamped-shaped structured instance, spec 0001 active,
# git hooks wired from the CURRENT templates.
rp1_fixture() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001\n\nStatus: ACTIVE\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}

# --- the grammar corpus: malformed REFUSES on CLEAN content ------------------
# The staged content beside the record is an ordinary docs edit, so the refusal
# is attributable to the record and to nothing else. The corpus enumerates the
# GRAMMAR (this is a grammar we own, so the corpus can be complete in kind):
# unparseable, missing version, wrong version type, unknown top-level key,
# unknown lifecycle token, unknown entry field, non-object entry, bad spec key,
# bad chore status, files not an array.
RP1G="$WORK/rp1-grammar"
rp1_fixture "$RP1G"
RP1_GRAMMAR_BAD=""
RP1_GRAMMAR_N=0
while IFS='	' read -r RP1_LABEL RP1_JSON; do
  [[ -n "$RP1_LABEL" ]] || continue
  RP1_GRAMMAR_N=$((RP1_GRAMMAR_N + 1))
  printf '%s\n' "$RP1_JSON" > "$RP1G/.claude/status.json"
  printf 'note %s\n' "$RP1_GRAMMAR_N" > "$RP1G/docs.txt"
  printf '| 0001 | Thing | ACTIVE | wip %s |\n' "$RP1_GRAMMAR_N" >> "$RP1G/specs/STATUS.md"
  git -C "$RP1G" add -A >/dev/null 2>&1
  if git -C "$RP1G" commit -qm "grammar $RP1_LABEL" >"$WORK/rp1-grammar.out" 2>&1; then
    RP1_GRAMMAR_BAD="$RP1_GRAMMAR_BAD $RP1_LABEL:committed"
    git -C "$RP1G" reset -q --hard HEAD~1 2>/dev/null
  elif ! grep -q 'SLH-RECORD-MALFORMED' "$WORK/rp1-grammar.out"; then
    RP1_GRAMMAR_BAD="$RP1_GRAMMAR_BAD $RP1_LABEL:wrong-reason"
    git -C "$RP1G" reset -q --hard HEAD 2>/dev/null
  else
    git -C "$RP1G" reset -q --hard HEAD 2>/dev/null
  fi
done <<'RP1GRAMMAR'
unparseable	not json at all
missing-version	{"specs":{},"chores":{}}
version-string	{"setlist_status":"1","specs":{},"chores":{}}
version-future	{"setlist_status":2,"specs":{},"chores":{}}
unknown-top-key	{"setlist_status":1,"specs":{},"chores":{},"extra":true}
unknown-token	{"setlist_status":1,"specs":{"0001":{"status":"finished"}},"chores":{}}
uppercase-token	{"setlist_status":1,"specs":{"0001":{"status":"CLOSED"}},"chores":{}}
unknown-field	{"setlist_status":1,"specs":{"0001":{"status":"active","note":"x"}},"chores":{}}
entry-not-object	{"setlist_status":1,"specs":{"0001":"active"},"chores":{}}
bad-spec-key	{"setlist_status":1,"specs":{"bogus":{"status":"active"}},"chores":{}}
qa-not-token	{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"3/4"}},"chores":{}}
diagram-not-token	{"setlist_status":1,"specs":{"0001":{"status":"closed","diagram":"none"}},"chores":{}}
chore-bad-status	{"setlist_status":1,"specs":{},"chores":{"CHORE-1":{"status":"finished"}}}
chore-files-not-array	{"setlist_status":1,"specs":{},"chores":{"CHORE-1":{"status":"done","files":"x"}}}
chore-bad-key	{"setlist_status":1,"specs":{},"chores":{"chore-1":{"status":"open"}}}
two-documents	{"setlist_status":1}{"setlist_status":1}
RP1GRAMMAR
if [[ "$RP1_GRAMMAR_N" -lt 16 ]]; then
  bad "record grammar: the corpus enumerates the grammar" \
      "only $RP1_GRAMMAR_N cases ran; the corpus is broken and proves almost nothing"
elif [[ -z "$RP1_GRAMMAR_BAD" ]]; then
  ok "record grammar: all $RP1_GRAMMAR_N malformed shapes REFUSE with SLH-RECORD-MALFORMED on otherwise clean content, and none falls back"
else
  bad "record grammar: all $RP1_GRAMMAR_N malformed shapes REFUSE with SLH-RECORD-MALFORMED on otherwise clean content, and none falls back" \
      "failures:$RP1_GRAMMAR_BAD"
fi

# The valid twin: a well-formed record edit with the page staged commits clean,
# so the grammar refuses shapes rather than refusing the feature.
printf '{"setlist_status":1,"specs":{"0001":{"status":"built"}},"chores":{}}\n' > "$RP1G/.claude/status.json"
printf '| 0001 | Thing | BUILT | done on branch |\n' >> "$RP1G/specs/STATUS.md"
git -C "$RP1G" add -A >/dev/null 2>&1
if git -C "$RP1G" commit -qm "valid lifecycle flip" >"$WORK/rp1-valid.out" 2>&1; then
  ok "record grammar twin: a well-formed record flip with the page staged commits clean"
else
  bad "record grammar twin: a well-formed record flip with the page staged commits clean" \
      "$(tr '\n' ' ' < "$WORK/rp1-valid.out")"
fi

# --- the muted reader: the caller refuses what the reader did not say -------
# The one-token convention is the mechanism, so it is asserted the way the
# attestation's was: MUTE the reader (a jq that produces nothing at exit 0)
# over a perfectly VALID record, and watch the caller refuse. A crashed reader
# and a silent reader are the same non-answer, and neither is exactly "ok".
# Driven against the shipped library sourced whole, never a re-implementation.
RP1M="$WORK/rp1-muted"
rp1_fixture "$RP1M"
RP1_MUTED_OUT="$(
  # shellcheck disable=SC1091
  . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"
  jq() { return 0; }
  slh_active_specs "$RP1M" "" 2>&1
  printf 'rc=%s\n' "$?"
)"
if printf '%s' "$RP1_MUTED_OUT" | grep -q 'SLH-RECORD-MALFORMED' && printf '%s' "$RP1_MUTED_OUT" | grep -q 'rc=1'; then
  ok "record muted reader: a reader that says nothing at exit 0 over a VALID record is refused by its caller (one token out, and it was not ok)"
else
  bad "record muted reader: a reader that says nothing at exit 0 over a VALID record is refused by its caller (one token out, and it was not ok)" \
      "got: $(printf '%s' "$RP1_MUTED_OUT" | tr '\n' ' ')"
fi

# --- the lifecycle trigger, re-keyed ------------------------------------------
# Structured: a staged record MODIFICATION without the page is refused; the
# ADOPTION commit (the record's addition) is not a flip and is not refused; and
# the advisory gate mirrors both with its own codes.
RP1L="$WORK/rp1-lifecycle"
rp1_fixture "$RP1L"
printf '{"setlist_status":1,"specs":{"0001":{"status":"built"}},"chores":{}}\n' > "$RP1L/.claude/status.json"
git -C "$RP1L" add -A >/dev/null 2>&1
if git -C "$RP1L" commit -qm "record flip alone" >"$WORK/rp1-lc.out" 2>&1; then
  bad "record lifecycle a: a staged record modification without specs/STATUS.md is refused" \
      "it committed: the record and the page can now drift apart at the write moment checkpoint owns"
else
  if grep -q 'SLH-STATUS-MISSING' "$WORK/rp1-lc.out"; then
    ok "record lifecycle a: a staged record modification without specs/STATUS.md is refused (SLH-STATUS-MISSING, the existing code re-keyed)"
  else
    bad "record lifecycle a: a staged record modification without specs/STATUS.md is refused" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-lc.out")"
  fi
fi
run_hook "$HOOKS/commit-gate.sh" "$RP1L" "$(bash_payload 'git commit -m "flip"')"
expect_deny "record lifecycle b: the advisory gate mirrors the record-without-page demand" "CM-STATUS-MISSING"
git -C "$RP1L" reset -q --hard HEAD 2>/dev/null

# The ADOPTION commit: a legacy instance gains the record; the addition is an
# opt-in, not a lifecycle flip, so no page is demanded and the commit lands.
RP1A="$WORK/rp1-adopt"
rp1_fixture "$RP1A"
git -C "$RP1A" rm -q --cached .claude/status.json >/dev/null 2>&1
rm -f "$RP1A/.claude/status.json"
git -C "$RP1A" commit -qm "legacy instance" >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$RP1A/.claude/status.json"
git -C "$RP1A" add -A >/dev/null 2>&1
if git -C "$RP1A" commit -qm "adoption" >"$WORK/rp1-adopt.out" 2>&1; then
  ok "record lifecycle c: the ADOPTION commit (record added, page untouched) lands; an opt-in is not a flip"
else
  bad "record lifecycle c: the ADOPTION commit (record added, page untouched) lands; an opt-in is not a flip" \
      "$(tr '\n' ' ' < "$WORK/rp1-adopt.out")"
fi

# --- the audit's record codes, green direction --------------------------------
# (Each was watched RED against the pre-record bytes before its fix existed;
# the observations are in spec 0126 and its commit. These pin the green.)
RP1B="$WORK/rp1-audit-noclose"
rp1_fixture "$RP1B"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed"}},"chores":{}}\n' > "$RP1B/.claude/status.json"
git -C "$RP1B" add -A >/dev/null 2>&1
git -C "$RP1B" -c core.hooksPath=/dev/null commit -qm "record-only factless close" >/dev/null 2>&1
RP1B_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1B" 2>&1)" || true
if printf '%s' "$RP1B_OUT" | grep -q '\[SLH-RECORD-NO-CLOSE\]'; then
  ok "record audit a: a record flip to closed without close facts is a VIOLATION named SLH-RECORD-NO-CLOSE"
else
  bad "record audit a: a record flip to closed without close facts is a VIOLATION named SLH-RECORD-NO-CLOSE" \
      "audit said: $(printf '%s' "$RP1B_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1C="$WORK/rp1-audit-nospec"
rp1_fixture "$RP1C"
git -C "$RP1C" checkout -qb spec/0002-other
printf '# Spec 0002\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1C/specs/0002-other.md"
printf '| 0002 | Other | CLOSED | x |\n' >> "$RP1C/specs/STATUS.md"
printf 'code\n' > "$RP1C/src/f.js"
git -C "$RP1C" add -A >/dev/null 2>&1
git -C "$RP1C" -c core.hooksPath=/dev/null commit -qm "close 0002 without recording it" >/dev/null 2>&1
git -C "$RP1C" checkout -q main
git -C "$RP1C" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0002-other >/dev/null 2>&1
RP1C_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1C" 2>&1)" || true
if printf '%s' "$RP1C_OUT" | grep -q '\[SLH-RECORD-NO-SPEC\]'; then
  ok "record audit b: a merged spec with NO record entry is a VIOLATION named SLH-RECORD-NO-SPEC, and the message names the one-line way out"
else
  bad "record audit b: a merged spec with NO record entry is a VIOLATION named SLH-RECORD-NO-SPEC, and the message names the one-line way out" \
      "audit said: $(printf '%s' "$RP1C_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1D="$WORK/rp1-audit-malformed"
rp1_fixture "$RP1D"
printf 'not json at all\n' > "$RP1D/.claude/status.json"
printf 'docs\n' > "$RP1D/docs.txt"
git -C "$RP1D" add -A >/dev/null 2>&1
git -C "$RP1D" -c core.hooksPath=/dev/null commit -qm "malformed record" >/dev/null 2>&1
RP1D_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1D" 2>&1)" || true
if printf '%s' "$RP1D_OUT" | grep -q '\[SLH-RECORD-MALFORMED\]'; then
  ok "record audit c: a present-and-malformed record is a VIOLATION named SLH-RECORD-MALFORMED, never a fallback to the page readers"
else
  bad "record audit c: a present-and-malformed record is a VIOLATION named SLH-RECORD-MALFORMED, never a fallback to the page readers" \
      "audit said: $(printf '%s' "$RP1D_OUT" | tail -2 | tr '\n' ' ')"
fi

# The honest structured close, BOTH merge shapes, stays clean: the codes above
# refuse hand edits, not the feature.
RP1E="$WORK/rp1-audit-clean"
rp1_fixture "$RP1E"
git -C "$RP1E" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1E/specs/0001-thing.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1E/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1E/specs/STATUS.md" > "$RP1E/specs/STATUS.md.new" && mv "$RP1E/specs/STATUS.md.new" "$RP1E/specs/STATUS.md"
printf 'code\n' > "$RP1E/src/f.js"
git -C "$RP1E" add -A >/dev/null 2>&1
git -C "$RP1E" -c core.hooksPath=/dev/null commit -qm "compliant recorded close" >/dev/null 2>&1
git -C "$RP1E" checkout -q main
git -C "$RP1E" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0001-thing >/dev/null 2>&1
RP1E_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1E" 2>&1)" || true
if printf '%s' "$RP1E_OUT" | grep -q ' 0 violations'; then
  ok "record audit d: the honest structured --no-ff close audits clean"
else
  bad "record audit d: the honest structured --no-ff close audits clean" \
      "audit said: $(printf '%s' "$RP1E_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1F="$WORK/rp1-audit-squash"
rp1_fixture "$RP1F"
git -C "$RP1F" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1F/specs/0001-thing.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1F/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1F/specs/STATUS.md" > "$RP1F/specs/STATUS.md.new" && mv "$RP1F/specs/STATUS.md.new" "$RP1F/specs/STATUS.md"
printf 'code\n' > "$RP1F/src/f.js"
git -C "$RP1F" add -A >/dev/null 2>&1
git -C "$RP1F" -c core.hooksPath=/dev/null commit -qm "compliant recorded close" >/dev/null 2>&1
git -C "$RP1F" checkout -q main
git -C "$RP1F" -c core.hooksPath=/dev/null merge --squash spec/0001-thing >/dev/null 2>&1
git -C "$RP1F" -c core.hooksPath=/dev/null commit -qm "squash close of 0001" >/dev/null 2>&1
RP1F_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1F" 2>&1)" || true
if printf '%s' "$RP1F_OUT" | grep -q ' 0 violations'; then
  ok "record audit e: the honest structured SQUASH close audits clean (F4's honest shape, record-verified)"
else
  bad "record audit e: the honest structured SQUASH close audits clean (F4's honest shape, record-verified)" \
      "audit said: $(printf '%s' "$RP1F_OUT" | tail -2 | tr '\n' ' ')"
fi

# --- the session mirror at close-gate ----------------------------------------
RP1CG="$WORK/rp1-cg"
rp1_fixture "$RP1CG"
git -C "$RP1CG" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1CG/specs/0001-thing.md"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1CG/specs/STATUS.md" > "$RP1CG/specs/STATUS.md.new" && mv "$RP1CG/specs/STATUS.md.new" "$RP1CG/specs/STATUS.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed"}},"chores":{}}\n' > "$RP1CG/.claude/status.json"
printf 'code\n' > "$RP1CG/src/f.js"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "record without facts" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate a: a branch record without close facts is warned CG-RECORD-NO-CLOSE (prose fully compliant, so the record is the only reader that can see it)" "CG-RECORD-NO-CLOSE"

git -C "$RP1CG" checkout -q spec/0001-thing
printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "entry removed" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate b: a spec with no record entry is warned CG-RECORD-NO-SPEC" "CG-RECORD-NO-SPEC"

git -C "$RP1CG" checkout -q spec/0001-thing
printf 'not json at all\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "record garbage" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate c: a malformed branch record is warned CG-RECORD-MALFORMED, in the git hooks' own words" "CG-RECORD-MALFORMED"

git -C "$RP1CG" checkout -q spec/0001-thing
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "facts complete" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "record close-gate d: the compliant recorded close is allowed in silence"

# --- the advisory commit gate's malformed mirror ------------------------------
RP1CM="$WORK/rp1-cm"
rp1_fixture "$RP1CM"
printf 'not json at all\n' > "$RP1CM/.claude/status.json"
printf 'x\n' >> "$RP1CM/specs/STATUS.md"
git -C "$RP1CM" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$RP1CM" "$(bash_payload 'git commit -m x')"
expect_deny "record commit-gate: a staged malformed record is warned CM-RECORD-MALFORMED at the earliest layer that sees it" "CM-RECORD-MALFORMED"

# --- feature code without a record flip: the structured SLH-CLOSES-NO-SPEC ----
RP1N="$WORK/rp1-noflip"
rp1_fixture "$RP1N"
git -C "$RP1N" checkout -qb spec/0001-thing
printf 'code\n' > "$RP1N/src/f.js"
git -C "$RP1N" add -A >/dev/null 2>&1
git -C "$RP1N" -c core.hooksPath=/dev/null commit -qm "code, no record flip" >/dev/null 2>&1
git -C "$RP1N" checkout -q main
if git -C "$RP1N" merge --no-ff --no-edit spec/0001-thing >"$WORK/rp1-noflip.out" 2>&1; then
  bad "record closes-no-spec: feature code without a record flip or chore is refused at the merge" \
      "the merge landed; the record path lost the closes-no-spec rule"
else
  if grep -q 'SLH-CLOSES-NO-SPEC' "$WORK/rp1-noflip.out"; then
    ok "record closes-no-spec: feature code without a record flip or chore is refused at the merge, and the message names checkpoint"
  else
    bad "record closes-no-spec: feature code without a record flip or chore is refused at the merge" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-noflip.out")"
  fi
fi

# --- the chore route through the record ---------------------------------------
RP1CH="$WORK/rp1-chore"
rp1_fixture "$RP1CH"
git -C "$RP1CH" checkout -qb chore/tidy
printf 'tidied\n' > "$RP1CH/src/tidy.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-001":{"status":"done"}}}\n' > "$RP1CH/.claude/status.json"
printf '- CHORE-001: DONE 2026-08-30. Tidied.\n' >> "$RP1CH/specs/STATUS.md"
git -C "$RP1CH" add -A >/dev/null 2>&1
git -C "$RP1CH" -c core.hooksPath=/dev/null commit -qm "chore recorded in the record" >/dev/null 2>&1
git -C "$RP1CH" checkout -q main
if git -C "$RP1CH" merge --no-ff --no-edit chore/tidy >"$WORK/rp1-chore.out" 2>&1; then
  ok "record chore: a chore newly done in the record authorises its merge (the record half of Part 5b)"
else
  bad "record chore: a chore newly done in the record authorises its merge (the record half of Part 5b)" \
      "$(tr '\n' ' ' < "$WORK/rp1-chore.out")"
fi

# --- THE ABSENCE DIFFERENTIAL: blob-pinned, both directions -------------------
# A8: the case count is asserted before the agreement is believed, and a
# DISCRIMINATION control proves the harness can see a difference at all, so a
# green here is never green because nothing ran.
if [[ ! -d "$RP1_PRE" ]]; then
  ok "record differential: SKIPPED, the pre-record hook blobs are not present in this tree (export copy)"
else
  RP1DD="$WORK/rp1-diff"; rm -rf "$RP1DD"; mkdir -p "$RP1DD"
  RP1_DIFF_N=0; RP1_DIFF_BAD=""
  for RP1_CASE in clean lifecycle emdash close-merge close-gate-deny commit-gate-lc audit-close; do
    for RP1_GEN in pre now; do
      d="$RP1DD/$RP1_CASE-$RP1_GEN"
      rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
      git_init "$d"
      # NO .claude/status.json anywhere: this is the legacy instance, and the
      # claim under test is that it cannot tell the generations apart.
      printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
      printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
      printf '# Spec 0001\n\nStatus: ACTIVE\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
      if [[ "$RP1_GEN" == "pre" ]]; then
        cp "$RP1_PRE/pre-commit" "$RP1_PRE/pre-merge-commit" "$RP1_PRE/setlist-hook-lib.sh" "$d/.githooks/"
        RP1_CG="$RP1_PRE/close-gate.sh"; RP1_CM="$RP1_PRE/commit-gate.sh"; RP1_TA="$RP1_PRE/trunk-audit.sh"
      else
        cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
        RP1_CG="$HOOKS/close-gate.sh"; RP1_CM="$HOOKS/commit-gate.sh"; RP1_TA="$SCRIPTS/trunk-audit.sh"
      fi
      chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
      printf 'seed\n' > "$d/seed.txt"
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
      git -C "$d" config core.hooksPath .githooks
      : > "$RP1DD/$RP1_CASE-$RP1_GEN.out"
      case "$RP1_CASE" in
        clean)
          printf 'ordinary work\n' > "$d/docs.txt"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "clean" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        lifecycle)
          printf '# Spec 0001\n\nStatus: BUILT\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "flip without page" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        emdash)
          printf 'a %s b\n' "$EMDASH" > "$d/src/app.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "emdash" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        close-merge)
          git -C "$d" checkout -qb spec/0001-thing 2>/dev/null
          printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$d/specs/0001-thing.md"
          sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
          printf 'code\n' > "$d/src/f.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" -c core.hooksPath=/dev/null commit -qm "close" >/dev/null 2>&1
          git -C "$d" checkout -q main 2>/dev/null
          git -C "$d" merge --no-ff --no-edit spec/0001-thing >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out"
          # The merge subject line embeds nothing generation-specific; strip
          # the object names git prints, which differ per repo by hash.
          sed -e 's/[0-9a-f]\{7,40\}/HASH/g' "$RP1DD/$RP1_CASE-$RP1_GEN.out" > "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" && mv "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        close-gate-deny)
          printf '%s' "$(bash_payload 'git merge --no-ff spec/0009-none')" | CLAUDE_PROJECT_DIR="$d" bash "$RP1_CG" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        commit-gate-lc)
          printf '# Spec 0001\n\nStatus: BUILT\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
          git -C "$d" add -A >/dev/null 2>&1
          printf '%s' "$(bash_payload 'git commit -m flip')" | CLAUDE_PROJECT_DIR="$d" bash "$RP1_CM" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        audit-close)
          git -C "$d" checkout -qb spec/0001-thing 2>/dev/null
          printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$d/specs/0001-thing.md"
          sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
          printf 'code\n' > "$d/src/f.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" -c core.hooksPath=/dev/null commit -qm "close" >/dev/null 2>&1
          git -C "$d" checkout -q main 2>/dev/null
          git -C "$d" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0001-thing >/dev/null 2>&1
          bash "$RP1_TA" "$d" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out"
          # The audit echoes the instance path and commit hashes, which differ
          # per generation BY CONSTRUCTION (two fixture dirs); normalise both,
          # because the claim under comparison is behaviour, not the echo.
          sed -e "s#$d#INSTANCE#g" -e 's/[0-9a-f]\{7,40\}/HASH/g' "$RP1DD/$RP1_CASE-$RP1_GEN.out" > "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" && mv "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
      esac
    done
    RP1_DIFF_N=$((RP1_DIFF_N + 1))
    if ! cmp -s "$RP1DD/$RP1_CASE-pre.out" "$RP1DD/$RP1_CASE-now.out"; then
      RP1_DIFF_BAD="$RP1_DIFF_BAD $RP1_CASE"
    fi
  done
  if [[ "$RP1_DIFF_N" -eq 7 && -z "$RP1_DIFF_BAD" ]]; then
    ok "record differential: with NO record present, all 7 cases are byte-identical between the pre-record and current generations, at every layer"
  else
    bad "record differential: with NO record present, all 7 cases are byte-identical between the pre-record and current generations, at every layer" \
        "$RP1_DIFF_N of 7 cases compared, differing:${RP1_DIFF_BAD:- none}; absent must mean today's behaviour exactly"
  fi

  # THE DISCRIMINATION CONTROL: a structured input where the generations MUST
  # diverge, so the identity above is evidence about absence rather than about
  # a harness that compares nothing.
  RP1DC="$RP1DD/disc"; rm -rf "$RP1DC-pre" "$RP1DC-now"
  for RP1_GEN in pre now; do
    d="$RP1DC-$RP1_GEN"
    rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
    git_init "$d"
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
    printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
    if [[ "$RP1_GEN" == "pre" ]]; then
      cp "$RP1_PRE/pre-commit" "$RP1_PRE/pre-merge-commit" "$RP1_PRE/setlist-hook-lib.sh" "$d/.githooks/"
    else
      cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
    fi
    chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
    printf 'seed\n' > "$d/seed.txt"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
    git -C "$d" config core.hooksPath .githooks
    printf '{"setlist_status":1,"specs":{"0001":{"status":"FINISHED"}}}\n' > "$d/.claude/status.json"
    printf 'x\n' >> "$d/specs/STATUS.md"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" commit -qm "malformed record" >"$RP1DD/disc-$RP1_GEN.out" 2>&1
    printf 'exit=%s\n' "$?" >> "$RP1DD/disc-$RP1_GEN.out"
  done
  if cmp -s "$RP1DD/disc-pre.out" "$RP1DD/disc-now.out"; then
    bad "record differential control: a structured input DIVERGES between the generations" \
        "the generations agreed on a malformed record, so the identity cases above may be identical because the harness compares nothing"
  else
    ok "record differential control: a structured input DIVERGES between the generations, so the 7-case identity is evidence about absence"
  fi
fi

# --- the scaffold template and the upgrade's restraint -------------------------
if [[ -f "$ROOT/templates/claude/status.json" ]]; then
  RP1_TPL_VERDICT="$(jq -r "$(grep -m1 -E '^[[:space:]]*SLH_RECORD_CHECK_JQ=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed -e "s/^[[:space:]]*SLH_RECORD_CHECK_JQ='//" -e "s/'$//")" "$ROOT/templates/claude/status.json" 2>/dev/null || printf 'malformed')"
  if [[ "$RP1_TPL_VERDICT" == "ok" ]]; then
    ok "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)"
  else
    bad "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)" \
        "the reader said: $RP1_TPL_VERDICT"
  fi
else
  bad "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)" \
      "the template file is missing; stamp.sh names it in the PLAN"
fi

# --- OWNERSHIP (design section 8): the declared set and the per-file arm ----
# The lockstep for the Owns reader: TWO homes (the library asks the question
# at the squash landing, the audit at the pushed history), byte-identical.
RP1_OWNS_LIB="$(grep -m1 -E '^[[:space:]]*SLH_OWNS_AWK=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*//')"
RP1_OWNS_TA="$(grep -m1 -E '^[[:space:]]*SLH_OWNS_AWK=' "$SCRIPTS/trunk-audit.sh" | sed 's/^[[:space:]]*//')"
if [[ -n "$RP1_OWNS_LIB" && "$RP1_OWNS_LIB" == "$RP1_OWNS_TA" ]]; then
  ok "owns lockstep: SLH_OWNS_AWK is byte-identical in the hook library and trunk-audit.sh"
else
  bad "owns lockstep: SLH_OWNS_AWK is byte-identical in the hook library and trunk-audit.sh" \
      "the two homes of the ownership grammar drifted"
fi

# The honest DECLARING squash close: files declared, files carried, clean.
RP1O1="$WORK/rp1-owns-honest"
rp1_fixture "$RP1O1"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O1/specs/0001-thing.md"
printf 'declared work\n' > "$RP1O1/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O1/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O1/specs/STATUS.md" > "$RP1O1/specs/STATUS.md.new" && mv "$RP1O1/specs/STATUS.md.new" "$RP1O1/specs/STATUS.md"
git -C "$RP1O1" add -A >/dev/null 2>&1
git -C "$RP1O1" -c core.hooksPath=/dev/null commit -qm "declaring squash-shaped close" >/dev/null 2>&1
RP1O1_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O1" 2>&1)" || true
if printf '%s' "$RP1O1_OUT" | grep -q ' 0 violations'; then
  ok "owns a: the honest declaring squash close passes on shape (its files were declared during the build)"
else
  bad "owns a: the honest declaring squash close passes on shape (its files were declared during the build)" \
      "audit said: $(printf '%s' "$RP1O1_OUT" | tail -2 | tr '\n' ' ')"
fi

# The refusal names BOTH honest exits, because a false-deny without a way out
# teaches the operator to reach for the skip hatch.
RP1O2="$WORK/rp1-owns-exits"
rp1_fixture "$RP1O2"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O2/specs/0001-thing.md"
printf 'declared\n' > "$RP1O2/src/feat.txt"
printf 'forgotten\n' > "$RP1O2/src/extra.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O2/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O2/specs/STATUS.md" > "$RP1O2/specs/STATUS.md.new" && mv "$RP1O2/specs/STATUS.md.new" "$RP1O2/specs/STATUS.md"
git -C "$RP1O2" add -A >/dev/null 2>&1
git -C "$RP1O2" -c core.hooksPath=/dev/null commit -qm "undeclared extra" >/dev/null 2>&1
RP1O2_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O2" 2>&1)" || true
if printf '%s' "$RP1O2_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/extra.txt' \
   && printf '%s' "$RP1O2_OUT" | grep -q 'checkpoint' \
   && printf '%s' "$RP1O2_OUT" | grep -q -- '--no-ff'; then
  ok "owns b: an undeclared role file in a declaring close refuses naming BOTH honest exits (declare through checkpoint, or the --no-ff route)"
else
  bad "owns b: an undeclared role file in a declaring close refuses naming BOTH honest exits (declare through checkpoint, or the --no-ff route)" \
      "audit said: $(printf '%s' "$RP1O2_OUT" | tail -3 | tr '\n' ' ')"
fi

# The grammar refusals: a glob, a directory, a below-the-heading line. Each is
# an exemption wearing a declaration, and each refuses AT THE ARM rather than
# being read charitably.
RP1_OWNS_BAD_MISS=""
while IFS='	' read -r RP1_OLBL RP1_OLINE; do
  [[ -n "$RP1_OLBL" ]] || continue
  RP1O3="$WORK/rp1-owns-$RP1_OLBL"
  rp1_fixture "$RP1O3"
  printf '# Spec 0001\n\nStatus: CLOSED\n%s\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' "$RP1_OLINE" > "$RP1O3/specs/0001-thing.md"
  printf 'work\n' > "$RP1O3/src/feat.txt"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O3/.claude/status.json"
  sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O3/specs/STATUS.md" > "$RP1O3/specs/STATUS.md.new" && mv "$RP1O3/specs/STATUS.md.new" "$RP1O3/specs/STATUS.md"
  git -C "$RP1O3" add -A >/dev/null 2>&1
  git -C "$RP1O3" -c core.hooksPath=/dev/null commit -qm "owns $RP1_OLBL" >/dev/null 2>&1
  bash "$SCRIPTS/trunk-audit.sh" "$RP1O3" 2>&1 | grep -q '\[SLH-OWNS-MALFORMED\]' || RP1_OWNS_BAD_MISS="$RP1_OWNS_BAD_MISS $RP1_OLBL"
done <<'RP1OWNSBAD'
glob	Owns: src/*.txt
dir	Owns: src/
nospace	Owns:src/feat.txt
dotdot	Owns: src/../secrets.txt
RP1OWNSBAD
# The out-of-range case separately: the declaration sits BELOW the Closing
# report heading, outside what the attestation signs, so it counts for nothing
# and refuses rather than being silently ignored while a human reads it.
RP1O4="$WORK/rp1-owns-range"
rp1_fixture "$RP1O4"
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nOwns: src/feat.txt\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O4/specs/0001-thing.md"
printf 'work\n' > "$RP1O4/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O4/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O4/specs/STATUS.md" > "$RP1O4/specs/STATUS.md.new" && mv "$RP1O4/specs/STATUS.md.new" "$RP1O4/specs/STATUS.md"
git -C "$RP1O4" add -A >/dev/null 2>&1
git -C "$RP1O4" -c core.hooksPath=/dev/null commit -qm "owns out of range" >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$RP1O4" 2>&1 | grep -q '\[SLH-OWNS-MALFORMED\]' || RP1_OWNS_BAD_MISS="$RP1_OWNS_BAD_MISS out-of-range"
if [[ -z "$RP1_OWNS_BAD_MISS" ]]; then
  ok "owns c: a glob, a directory, a spaceless label, a dot-dot path and an out-of-range line each refuse SLH-OWNS-MALFORMED at the arm that would consume them"
else
  bad "owns c: a glob, a directory, a spaceless label, a dot-dot path and an out-of-range line each refuse SLH-OWNS-MALFORMED at the arm that would consume them" \
      "not refused:$RP1_OWNS_BAD_MISS"
fi

# THE CHORE HALF (F5-2026): the compliant --squash chore close is accepted at
# the COMMIT layer (the squash landing through the real hooks) and at the PUSH
# layer (the audit), and the widening the 2.3.0 leg warned about does not
# occur: an undeclared file beside the chore flip still refuses per file.
RP1O5="$WORK/rp1-owns-chore"
rp1_fixture "$RP1O5"
git -C "$RP1O5" checkout -qb chore/tidy 2>/dev/null
printf 'tidied\n' > "$RP1O5/src/tidy.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-002":{"status":"done","files":["src/tidy.js"]}}}\n' > "$RP1O5/.claude/status.json"
printf -- '- CHORE-002: DONE 2026-08-30. Tidied.\n' >> "$RP1O5/specs/STATUS.md"
git -C "$RP1O5" add -A >/dev/null 2>&1
git -C "$RP1O5" -c core.hooksPath=/dev/null commit -qm "chore on branch" >/dev/null 2>&1
git -C "$RP1O5" checkout -q main 2>/dev/null
git -C "$RP1O5" merge --squash chore/tidy >/dev/null 2>&1
if git -C "$RP1O5" commit -qm "squash chore close" >"$WORK/rp1-owns-chore.out" 2>&1; then
  ok "owns d (F5-2026): the compliant --squash CHORE close is accepted at the commit layer"
else
  bad "owns d (F5-2026): the compliant --squash CHORE close is accepted at the commit layer" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-chore.out")"
fi
RP1O5_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O5" 2>&1)" || true
if printf '%s' "$RP1O5_OUT" | grep -q ' 0 violations'; then
  ok "owns e (F5-2026): the same chore close is accepted at the push layer, so the two layers stop disagreeing"
else
  bad "owns e (F5-2026): the same chore close is accepted at the push layer, so the two layers stop disagreeing" \
      "audit said: $(printf '%s' "$RP1O5_OUT" | tail -2 | tr '\n' ' ')"
fi
# The non-widening control: the chore route exempts ITS declared files only.
RP1O6="$WORK/rp1-owns-chorewide"
rp1_fixture "$RP1O6"
printf 'tidied\n' > "$RP1O6/src/tidy.js"
printf 'smuggled beside the chore\n' > "$RP1O6/src/extra.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-002":{"status":"done","files":["src/tidy.js"]}}}\n' > "$RP1O6/.claude/status.json"
printf -- '- CHORE-002: DONE 2026-08-30. Tidied.\n' >> "$RP1O6/specs/STATUS.md"
git -C "$RP1O6" add -A >/dev/null 2>&1
git -C "$RP1O6" -c core.hooksPath=/dev/null commit -qm "chore flip with a rider" >/dev/null 2>&1
RP1O6_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O6" 2>&1)" || true
if printf '%s' "$RP1O6_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/extra.js'; then
  ok "owns f (F5-2026 non-widening): a chore flip exempts nothing but its declared files; the rider refuses by name"
else
  bad "owns f (F5-2026 non-widening): a chore flip exempts nothing but its declared files; the rider refuses by name" \
      "audit said: $(printf '%s' "$RP1O6_OUT" | tail -2 | tr '\n' ' ')"
fi

# THE LIBRARY'S HALF AT THE SQUASH LANDING: the same question, asked at the
# earliest layer that can refuse it, with the first honest exit then taken and
# the landing succeeding.
RP1O7="$WORK/rp1-owns-landing"
rp1_fixture "$RP1O7"
git -C "$RP1O7" checkout -qb spec/0001-thing 2>/dev/null
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O7/specs/0001-thing.md"
printf 'declared\n' > "$RP1O7/src/feat.txt"
printf 'smuggled\n' > "$RP1O7/src/wip.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O7/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O7/specs/STATUS.md" > "$RP1O7/specs/STATUS.md.new" && mv "$RP1O7/specs/STATUS.md.new" "$RP1O7/specs/STATUS.md"
git -C "$RP1O7" add -A >/dev/null 2>&1
git -C "$RP1O7" -c core.hooksPath=/dev/null commit -qm "close with smuggle" >/dev/null 2>&1
git -C "$RP1O7" checkout -q main 2>/dev/null
git -C "$RP1O7" merge --squash spec/0001-thing >/dev/null 2>&1
if git -C "$RP1O7" commit -qm "squash close" >"$WORK/rp1-owns-landing.out" 2>&1; then
  bad "owns g: the squash landing refuses the undeclared file at the commit layer too" \
      "the landing succeeded carrying an undeclared role file"
else
  if grep -q 'SLH-OWNS-UNDECLARED' "$WORK/rp1-owns-landing.out"; then
    ok "owns g: the squash landing refuses the undeclared file at the commit layer too"
  else
    bad "owns g: the squash landing refuses the undeclared file at the commit layer too" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-owns-landing.out")"
  fi
fi
# The first honest exit: declare it, and the same landing succeeds.
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\nOwns: src/wip.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O7/specs/0001-thing.md"
git -C "$RP1O7" add specs/0001-thing.md >/dev/null 2>&1
if git -C "$RP1O7" commit -qm "squash close, declared" >"$WORK/rp1-owns-landing2.out" 2>&1; then
  ok "owns h: declaring the file (the first honest exit) lets the same landing succeed"
else
  bad "owns h: declaring the file (the first honest exit) lets the same landing succeed" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-landing2.out")"
fi

# THE DELETION AXIS (2.4.0 leg F7): a deleted path cannot carry unspecced
# content to the trunk, which is the only question the per-file arm is asked.
# The merge arm's own sibling already filters (--diff-filter=A at the
# provenance check); the single-parent arm must not read a deletion as a file
# the close "does not declare". Two closes: 0001 brings src/old.txt declared,
# 0002 brings src/new.txt declared and DELETES src/old.txt.
RP1O8="$WORK/rp1-owns-delete"
rp1_fixture "$RP1O8"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O8/specs/0001-thing.md"
printf 'first\n' > "$RP1O8/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1O8/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1O8/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1O8/specs/STATUS.md"
git -C "$RP1O8" add -A >/dev/null 2>&1
git -C "$RP1O8" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O8/specs/0002-other.md"
printf 'second\n' > "$RP1O8/src/new.txt"
git -C "$RP1O8" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O8/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1O8/specs/STATUS.md"
git -C "$RP1O8" add -A >/dev/null 2>&1
git -C "$RP1O8" -c core.hooksPath=/dev/null commit -qm "declaring close of 0002, retiring src/old.txt" >/dev/null 2>&1
RP1O8_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O8" 2>&1)" || true
if printf '%s' "$RP1O8_OUT" | grep -q ' 0 violations' \
   && ! printf '%s' "$RP1O8_OUT" | grep -q 'SLH-OWNS-UNDECLARED'; then
  ok "owns i (2.4.0 leg F7): a declaring close that DELETES a role-path file audits clean; stop shipping a file is not smuggling one"
else
  bad "owns i (2.4.0 leg F7): a declaring close that DELETES a role-path file audits clean; stop shipping a file is not smuggling one" \
      "audit said: $(printf '%s' "$RP1O8_OUT" | tail -3 | tr '\n' ' ')"
fi

# The false-negative guard beside it: the deletion filter must not mask an
# undeclared ADDITION riding the same close.
RP1O9="$WORK/rp1-owns-delete-smuggle"
rp1_fixture "$RP1O9"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O9/specs/0001-thing.md"
printf 'first\n' > "$RP1O9/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1O9/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1O9/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1O9/specs/STATUS.md"
git -C "$RP1O9" add -A >/dev/null 2>&1
git -C "$RP1O9" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O9/specs/0002-other.md"
printf 'second\n' > "$RP1O9/src/new.txt"
printf 'smuggled\n' > "$RP1O9/src/sneak.txt"
git -C "$RP1O9" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O9/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1O9/specs/STATUS.md"
git -C "$RP1O9" add -A >/dev/null 2>&1
git -C "$RP1O9" -c core.hooksPath=/dev/null commit -qm "close of 0002 with a rider" >/dev/null 2>&1
RP1O9_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O9" 2>&1)" || true
if printf '%s' "$RP1O9_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/sneak.txt' \
   && ! printf '%s' "$RP1O9_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/old.txt'; then
  ok "owns j (2.4.0 leg F7 guard): the deletion filter does not mask an undeclared addition riding the same close"
else
  bad "owns j (2.4.0 leg F7 guard): the deletion filter does not mask an undeclared addition riding the same close" \
      "audit said: $(printf '%s' "$RP1O9_OUT" | tail -3 | tr '\n' ' ')"
fi

# The library's half at the squash landing: the same deletion, refused today at
# the earliest layer, must land once declared coverage holds for what ARRIVES.
# A REAL `merge --squash` then commit, because the landing arm keys on the
# squash-completion state and a hand-staged equivalent never enters it.
RP1OA="$WORK/rp1-owns-delete-landing"
rp1_fixture "$RP1OA"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OA/specs/0001-thing.md"
printf 'first\n' > "$RP1OA/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1OA/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1OA/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1OA/specs/STATUS.md"
git -C "$RP1OA" add -A >/dev/null 2>&1
git -C "$RP1OA" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
git -C "$RP1OA" checkout -qb spec/0002-other 2>/dev/null
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OA/specs/0002-other.md"
printf 'second\n' > "$RP1OA/src/new.txt"
git -C "$RP1OA" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1OA/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1OA/specs/STATUS.md"
git -C "$RP1OA" add -A >/dev/null 2>&1
git -C "$RP1OA" -c core.hooksPath=/dev/null commit -qm "build 0002, retiring src/old.txt" >/dev/null 2>&1
git -C "$RP1OA" checkout -q main 2>/dev/null
git -C "$RP1OA" -c merge.ff=true merge --squash spec/0002-other >/dev/null 2>&1
if git -C "$RP1OA" commit -qm "squash close of 0002, retiring src/old.txt" >"$WORK/rp1-owns-del-landing.out" 2>&1; then
  ok "owns k (2.4.0 leg F7): the squash landing accepts a declaring close whose only extra path is a deletion"
else
  bad "owns k (2.4.0 leg F7): the squash landing accepts a declaring close whose only extra path is a deletion" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-del-landing.out")"
fi

# THE FENCED-QUOTE LAYOUT (2.4.0 leg F1, ruled option C 2026-09-01): a fenced
# copy of the Closing-report template ABOVE the declaration ends the hashed
# range early, the reader and spec-hash.sh agree on that cut byte for byte, and
# the ruling keeps them agreed: the layout REFUSES, and the refusal must name
# the actual cause and the one-edit fix instead of stating the opposite of the
# file's contents. If a later change fence-strips the reader, this pin flips
# and the Known-limitations bullet, spec-hash.sh and the attestation-custody
# question all have to move in the same commit.
RP1OB="$WORK/rp1-owns-fenced"
rp1_fixture "$RP1OB"
printf '# Spec 0001\n\nStatus: CLOSED\n\nI will fill this in at the close:\n\n```markdown\n## Closing report\n\nArchitecture diagram: <updated in this commit | no impact>\n```\n\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OB/specs/0001-thing.md"
printf 'declared\n' > "$RP1OB/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1OB/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1OB/specs/STATUS.md" > "$RP1OB/specs/STATUS.md.new" && mv "$RP1OB/specs/STATUS.md.new" "$RP1OB/specs/STATUS.md"
git -C "$RP1OB" add -A >/dev/null 2>&1
git -C "$RP1OB" -c core.hooksPath=/dev/null commit -qm "close with a fenced template quote above the declaration" >/dev/null 2>&1
RP1OB_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1OB" 2>&1)" || true
if printf '%s' "$RP1OB_OUT" | grep -q '\[SLH-OWNS-MALFORMED\]' \
   && printf '%s' "$RP1OB_OUT" | grep -q 'fences included' \
   && printf '%s' "$RP1OB_OUT" | grep -q 'one edit'; then
  ok "owns l (2.4.0 leg F1, ruled option C): the fenced-quote layout refuses WITH the honest message naming the cause and the one-edit fix"
else
  bad "owns l (2.4.0 leg F1, ruled option C): the fenced-quote layout refuses WITH the honest message naming the cause and the one-edit fix" \
      "audit said: $(printf '%s' "$RP1OB_OUT" | tail -3 | tr '\n' ' ')"
fi

# stamp.sh delivers the record in BOTH modes; refresh-instance.sh (the upgrade
# deliverer) must NEVER deliver it: mention the field, migrate NOTHING.
if grep -qE '^add claude/status\.json' "$SCRIPTS/stamp.sh"; then
  ok "record delivery a: stamp.sh stamps .claude/status.json (structured from birth, both modes)"
else
  bad "record delivery a: stamp.sh stamps .claude/status.json (structured from birth, both modes)" \
      "no add line names claude/status.json"
fi
if grep -q 'status\.json' "$SCRIPTS/refresh-instance.sh"; then
  bad "record delivery b: refresh-instance.sh never delivers or creates the record (BL-005: mention the field, migrate NOTHING)" \
      "refresh-instance.sh mentions status.json; the upgrade path must not touch the record"
else
  ok "record delivery b: refresh-instance.sh never delivers or creates the record (BL-005: mention the field, migrate NOTHING)"
fi

# --- summary -----------------------------------------------------------------

printf '\n%s\n' "-----------------------------------------------"
printf 'passed %d, failed %d, total %d\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]] || exit 1
