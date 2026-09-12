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
# The suite is a driver plus per-gate shards, sourced in order (spec 0133). Every
# read of "the suite's own text" reads this list, never one file.
SUITE_DIR="$ROOT/test/suite"
SUITE_FILES=("$ROOT/test/run-tests.sh" "$SUITE_DIR"/*.sh)

# --- sharding (backlog CI1, spec 0127) ---------------------------------------
#
# WHY. This suite is the multiplier behind the whole CI bill. It is the macOS
# leg's critical path (11m00s of a 13m58s job, measured 2026-09-01 on run
# 33529658494), and dogfood/mutation-check.sh runs it once per mutation plus a
# control, which is nine serial runs and 20m18s of a 25m43s Linux job. So the
# suite is not the longest single step on Linux and is still the reason that
# leg is long.
#
# THE SHARD VERSION, NOT INTERNAL PARALLELISM, pre-decided by the owner and not
# reopened here: a shared-state audit across 14k lines of fixture-building bash
# is not a trade this repo takes. Shards are separate processes with separate
# TMPDIRs, so they share nothing by construction rather than by audit.
#
# THE PARTITION UNIT IS AN OPT-IN MARKED REGION, and the alternative is worth
# recording because it is the obvious one. Cutting automatically at this file's
# 74 banner sections was tried on paper and refused: helper functions and
# fixture variables are defined throughout the file and used across section
# boundaries, so an automatic cut would drop a definition or a variable and the
# failure would surface as a puzzling assertion rather than as a refusal.
# Marked regions invert that. Everything NOT inside a region runs in EVERY
# shard, so the default is always correct, and a region is only marked once it
# has been MEASURED independent in both directions (run alone, and run
# excluded). Regions are placed by the measured profile rather than by the
# banner structure, because the work is not evenly spread: the 1.0.5 attack
# corpus alone was 228 seconds of a 605-second run.
#
# A REGION THAT DID NOT RUN MUST NOT READ AS A REGION WITH NOTHING TO REPORT.
# That is CI1's named risk and it is answered by the __REGION__ lines below
# plus the aggregator in test/run-shards.sh: every shard announces the regions
# it ran, and the wrapper refuses unless the union is exactly the manifest,
# with nothing claimed twice and nothing claimed by nobody.
SHARD_K=0            # 0 means unsharded: every region runs, in file order
SHARD_N=0
SHARD_IDX=0          # how many regions have been REACHED, sharded or not
SHARD_OPEN=""
SHARD_OPEN_PASS=0
SHARD_OPEN_FAIL=0
SHARD_SKIP=" "       # space-delimited ids to skip, for the independence measurement
SHARD_OWNED=" "

shard_usage() {
  printf 'usage: %s [--shard K/N] [--skip-region ID] [--list-regions]\n' "$0" >&2
  printf '  no flag      run everything, in file order (the default, unchanged)\n' >&2
  printf '  --shard K/N  run only the regions this shard owns, 1 <= K <= N\n' >&2
  printf '  --skip-region ID  run everything EXCEPT this region (the independence measurement)\n' >&2
  printf '  --list-regions  print the region manifest and exit\n' >&2
  exit 2
}

# The manifest is read from the SHARD-BEGIN markers in the suite's files rather than
# from a list maintained beside them. A list is a second place to be wrong, and
# the markers are what the guards below actually key on.
shard_manifest() {
  grep -ho '^# >>> SHARD-BEGIN .*' "${SUITE_FILES[@]}" \
    | sed 's/^# >>> SHARD-BEGIN //; s/ cost=[0-9]*$//'
}

# THE COST HINT IS ADVISORY AND CAN ONLY AFFECT BALANCE, NEVER CORRECTNESS.
#
# Assignment was round-robin in the first cut, and round-robin is the wrong
# instrument when one region is 179 of 445 marked seconds: whichever shard drew
# the attack corpus finished long after the others and the run was as slow as
# that shard. The markers therefore carry a MEASURED cost in seconds (profiled
# 2026-09-02 on an arm64 macOS host, spec 0127) and regions are packed
# longest-first into the least-loaded shard.
#
# If a hint goes stale the packing gets worse and NOTHING ELSE: the coverage
# invariant in test/run-shards.sh is computed from the regions actually claimed,
# not from the hints, so a wrong number costs wall-clock and cannot cost a
# missed assertion. The wrapper prints the wall clock, which is where a stale
# hint shows up. Two hints (trunk-audit, advisory-flip) are approximations
# rather than direct readings, because those regions begin part-way through a
# profiled block; they are marked here rather than presented as measurements.
#
# Both the suite and the wrapper derive the assignment from these same marker
# lines, so they agree by construction rather than by being kept in step.
shard_assignment() { # shard_assignment <k> <n> -> the ids shard k owns
  grep -ho '^# >>> SHARD-BEGIN .*' "${SUITE_FILES[@]}" \
    | sed 's/^# >>> SHARD-BEGIN //' \
    | awk -v k="$1" -v n="$2" '
      { id[NR]=$1; c=$2; sub(/^cost=/,"",c); cost[NR]=(c==""?1:c+0); m=NR }
      END {
        for (b=1; b<=n; b++) load[b]=0
        # longest-processing-time-first: repeatedly place the largest unplaced
        # region into the least-loaded shard. Deterministic, so every process
        # computes the same assignment without talking to any other.
        for (t=1; t<=m; t++) {
          best=0; bestc=-1
          for (i=1; i<=m; i++) if (!done[i] && cost[i]>bestc) { bestc=cost[i]; best=i }
          done[best]=1
          lb=1; for (b=2; b<=n; b++) if (load[b]<load[lb]) lb=b
          load[lb]+=cost[best]
          if (lb==k) print id[best]
        }
      }'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shard)
      [[ $# -ge 2 ]] || shard_usage
      case "$2" in
        [0-9]*/[0-9]*) SHARD_K="${2%%/*}"; SHARD_N="${2##*/}" ;;
        *) shard_usage ;;
      esac
      [[ "$SHARD_N" -ge 1 ]] || shard_usage
      [[ "$SHARD_K" -ge 1 && "$SHARD_K" -le "$SHARD_N" ]] || shard_usage
      shift 2 ;;
    --list-regions) shard_manifest; exit 0 ;;
    # --skip-region is the INDEPENDENCE MEASUREMENT's instrument, not a way to
    # run less of the suite. A region is only allowed a SHARD-BEGIN marker once
    # the suite has been run with that region excluded and everything outside it
    # was still green: that is what proves nothing outside the region depends on
    # a fixture, a variable or a function the region builds. Guessing this from
    # reading is how the first cut of the partition went red on three shards.
    --skip-region)
      [[ $# -ge 2 ]] || shard_usage
      SHARD_SKIP="$SHARD_SKIP$2 "; shift 2 ;;
    -h|--help) shard_usage ;;
    *) shard_usage ;;
  esac
done

if [[ "$SHARD_N" -ne 0 ]]; then
  SHARD_OWNED=" $(shard_assignment "$SHARD_K" "$SHARD_N" | tr '\n' ' ')"
fi

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


# --- ER1's normalisation for the generation differentials (2.6.0, spec 0132) -----
#
# Three differentials below prove ABSENCE by running a pinned pre-feature
# generation of the hooks and the current one over a corpus and comparing their
# output byte for byte. Cluster B of 2.6.0 changed refusal TEXT on purpose: the
# escape spellings left every remedy sentence (the reader of a refusal in a
# session is the model, and coaching the bypass lowers its cost, review B1). A
# pinned generation still coaches, so its output differs from today's by exactly
# those clauses and by nothing else. The clauses are deleted from BOTH sides
# before comparing, literally and by enumeration (the eleven sentences that
# carried them), so the differentials keep proving what they proved and any
# OTHER change still goes red. Literal, not regex: a normaliser that matched
# loosely would be a way for a real divergence to hide inside it.
norm_escape_coaching() { # norm_escape_coaching <file>  (rewritten in place)
  awk 'function repl(t, a, b,   i, out) { out = ""; while ((i = index(t, a)) > 0) { out = out substr(t, 1, i - 1) b; t = substr(t, i + length(a)) } return out t }
       BEGIN { RS = "\001" }
       { t = $0
         t = repl(t, " Fix the above, or commit with\nSETLIST_SKIP_HOOKS=1 if this is a deliberate exception you are willing to own.", " Fix the above.")
         t = repl(t, " Fix the above, or merge\nwith SETLIST_SKIP_HOOKS=1 if this is a deliberate exception you are willing to own.", " Fix the above.")
         t = repl(t, ", or commit with SETLIST_SKIP_HOOKS=1 if this is an exception you are willing to own.", ".")
         t = repl(t, ", or merge with SETLIST_SKIP_HOOKS=1 if this is an exception you are willing to own.", ".")
         t = repl(t, ", or push with SETLIST_SKIP_HOOKS=1 if this is an exception you are willing to own.", ".")
         t = repl(t, "Fix the toolchain, or commit with SETLIST_SKIP_HOOKS=1 if this is an exception you are willing to own.", "Fix the toolchain.")
         t = repl(t, " Push with SETLIST_SKIP_HOOKS=1 if you are willing to own the exception.", "")
         t = repl(t, " Use SETLIST_SKIP_HOOKS=1 to skip both.", "")
         t = repl(t, "Fix the content, or push with SETLIST_SKIP_HOOKS=1 if this is a\ndeliberate exception you are willing to own. SETLIST_SKIP_TRUNK_AUDIT=1 does\nNOT skip this scan.", "Fix the content. Skipping the trunk audit does NOT skip this scan.")
         t = repl(t, "Fix connectivity, or push with SETLIST_SKIP_HOOKS=1 if you are willing\nto own the exception.", "Fix connectivity.")
         t = repl(t, "Fix the history, or push with SETLIST_SKIP_TRUNK_AUDIT=1 if\nthis is a deliberate exception you are willing to own.", "Fix the history.")
         printf "%s", t }' "$1" > "$1.norm" && mv "$1.norm" "$1"
}
norm_escape_coaching_str() { # norm_escape_coaching_str <string> -> the normalised string on stdout
  local f; f="$(mktemp "${TMPDIR:-/tmp}/setlist-norm.XXXXXX")"
  printf '%s' "$1" > "$f"; norm_escape_coaching "$f"; cat "$f"; rm -f "$f"
}

# --- the shard guards --------------------------------------------------------
#
# shard_region <id>  opens region <id>; true when this shard owns it.
# shard_region_end   closes the open region and reports its own denominator.
#
# Assignment is round-robin over the order regions are REACHED, which needs no
# weights file to keep true. The balance it produces is measured and recorded in
# spec 0127 rather than assumed: a partition whose balance nobody measured is
# how a four-way split turns into a three-way one.
shard_region() { # shard_region <id>
  shard_region_end
  SHARD_IDX=$((SHARD_IDX + 1))
  case "$SHARD_SKIP" in *" $1 "*) return 1 ;; esac
  if [[ "$SHARD_N" -eq 0 ]] || [[ "$SHARD_OWNED" == *" $1 "* ]]; then
    SHARD_OPEN="$1"; SHARD_OPEN_PASS="$PASS"; SHARD_OPEN_FAIL="$FAIL"
    return 0
  fi
  return 1
}

# The per-region denominator is printed whether or not the region asserted
# anything, and a region that ran and asserted NOTHING is a finding rather than
# a blank: it is the vacuous-comparison shape this file exists to hunt, one
# level up. The aggregator refuses on it.
shard_region_end() {
  [[ -n "$SHARD_OPEN" ]] || return 0
  printf '__REGION__ %s %d %d\n' "$SHARD_OPEN" \
    "$((PASS - SHARD_OPEN_PASS))" "$((FAIL - SHARD_OPEN_FAIL))"
  SHARD_OPEN=""
  return 0
}

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


# --- the hole ledger, read by name from THIS file (gate 5g, I4) ----------------

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
# hole: The session layer's one hard deny is defeated by ordinary variable expansion, so read it as a nudge and never as a boundary. | asserted
# hole: The push-time hooks read only the branch and tag namespaces, so a push to a review-ref namespace is ungoverned by them. | asserted
# hole: The Bash escape hatch. | asserted
# hole: The forge check governs the merge button only where the trunk requires it. | asserted
# hole: The CODEOWNERS bridge reads a subset of the file's grammar, and a pattern is a claim about paths. | asserted
# hole: The forge check reads the trunk's protection as it stands, not as it stood. | asserted
# hole: A session killed from outside fires no Stop, and the Stop hook is a nudge, never a lock. | asserted
# hole: Sideways routes to the trunk. | asserted
# hole: `git rebase` onto a spec branch brings that branch's commits to the trunk with no closing merge. | asserted
# hole: `git reset --hard <spec-branch>` moves the trunk onto unclosed work outright. | asserted
# hole: `git checkout <spec-branch> -- <path>` copies role-path files onto the trunk without any merge to read. | asserted
# hole: The pathspec hole. | asserted
# hole: Completing a refused merge on the trunk side, as the hook's own message prescribes, is accepted at commit and refused at push. | asserted
# hole: A timed-out hook is a skipped gate. | unassertable | harness behaviour, not hook behaviour; verified live 2026-07-25 with a sleeping hook under timeout 1 and 10, recorded in close-gate.sh's header
# hole: The staged-content scans read every staged line unless you scope them. | asserted
# hole: The scans read this project's own index. | asserted
# hole: `--no-verify` skips git hooks | asserted
# hole: Git hooks are per-clone, and the tracked directory narrows that without closing it. | asserted
# hole: `git merge --ff-only` and `git merge --ff` skip the merge hooks. | asserted
# hole: `git merge --squash` needs one flag to work in a Setlist instance, and the error does not say so. | asserted
# hole: The close gate refuses `@{u}` and other revision-suffix spellings of a merge operand. | asserted
# hole: A role directory spelled in a different case is not seen by the session scope gate on macOS or Windows. | asserted
# hole: A `<<\EOF` heredoc body is read as code by the session gates. | asserted
# hole: The session gates are text parsers, and a growing list of spellings read a command wrongly. | asserted
# hole: The session gates' warnings do not reach the agent on current harnesses. | unassertable | a property of the HARNESS, not of these bytes: a shell test can see the hook emit the reason on three channels but not what Claude Code renders. dogfood/advisory-visibility-probe.sh measures it with a live session and a deny-control, and is the check that lifts this limitation when it changes
# hole: A first push to a brand-new EMPTY remote audits every pushed branch as a trunk candidate. | asserted
# hole: The trunk audit cannot tell a merge that EDITS a file from ordinary conflict resolution. | asserted
# hole: The headless integrity chain is only as strong as where your signing key lives, and a key your build can reach is not custody. | asserted
# hole: The close audit's single-parent arm is as strong as your declarations, and a declaration is a claim, not a verified fact. | asserted
# hole: The hashed range ends at the FIRST line reading `## Closing report`, fences included, and the ownership reader agrees with that cut. | asserted
# hole: Identity-by-commit governs an alias only while a spec or chore ref still points at that exact commit. | asserted
# hole: The wiring check recognises only the command spellings `settings.json.tmpl` ships. | asserted
# hole: The set of tested platforms is a list, not a proof. | unassertable | a statement ABOUT the CI matrix rather than about hook behaviour; the matrix in .github/workflows/test.yml is the evidence, and the honest check is reading which platforms it actually runs. Extended 2026-09-02 (spec 0127, backlog KL8, ratified decision 5): the Linux leg now runs this suite a second time under GNU awk, so the list is Linux/mawk, Linux/gawk and macOS/BWK awk, and the public bullet moved with it. Still unassertable here for the same reason, and Windows is still unrun
# hole: Secret and style scanning is best-effort early warning, not a guarantee. | asserted
# hole: git allows one `core.hooksPath`, so Setlist cannot coexist with husky, lefthook or pre-commit, and `refresh-instance.sh --apply` now REFUSES rather than displace one silently. | asserted
# hole: A checkout is an enforcement switch: every git hook is inert on a branch without `.claude/sdd.json`. | asserted
# hole: The `SETLIST_SKIP_HOOKS=1` escape skips EVERY git hook, `pre-push`'s trunk audit and content scan included. | asserted
# hole: Merges crafted to evade the trunk audit can succeed, and the list of known routes is maintained rather than complete. | asserted
# hole: The trunk is recognised by the NAME recorded in `.claude/sdd.json`, so an instance that merges onto a differently-named branch is ungoverned. | asserted
# hole: A diagram check compares a claim to a diff and a lockfile to a command's output; it does not judge whether a drawing is true of the code. | asserted
# hole: A drawn name is verified only when it is path-shaped, and everything else is reported rather than checked. | asserted
# hole: The render check runs where a renderer runs, and the stamped workflow fails its job rather than passing without one. | unassertable | the REFUSAL half is asserted (the forge check refuses a block that does not parse, under a stub parser on PATH); what is unassertable here is the WORKFLOW half, that the stamped renderer step fails its job rather than letting the check pass, because that is a property of a GitHub Actions step and not of these bytes. The stamped workflow's own step verifies its parser in both directions before the check runs, and the release's forge-check run is the evidence
# hole: Mermaid's inline edge-text form can refuse a close for a path nobody drew. | asserted
# LEDGER-END

# --- the shards, in order; the program is their concatenation ---------------
source "$SUITE_DIR/01-session-gates.sh"
source "$SUITE_DIR/02-plugin-version-and-refresh.sh"
source "$SUITE_DIR/03-trunk-rules-and-hook-audits.sh"
source "$SUITE_DIR/04-close-gate-corpus.sh"
source "$SUITE_DIR/05-commit-gate-corpus.sh"
source "$SUITE_DIR/06-trunk-audit.sh"
source "$SUITE_DIR/07-pre-push-and-suite-audits.sh"
source "$SUITE_DIR/08-git-hooks.sh"
source "$SUITE_DIR/09-attestation-kl3.sh"
source "$SUITE_DIR/10-delivery-and-ownership.sh"
source "$SUITE_DIR/11-parser-classes-and-advisory.sh"
source "$SUITE_DIR/12-scope-canon-skills-headings.sh"
source "$SUITE_DIR/13-push-scan-kl2-kl4.sh"
source "$SUITE_DIR/14-status-record-rp1.sh"
source "$SUITE_DIR/15-rc2-f10-jq-hardening.sh"
source "$SUITE_DIR/16-team-edition-0132.sh"
source "$SUITE_DIR/17-diagram-edition-0136.sh"

# EVERY SHARD FILE ON DISK IS SOURCED ABOVE, asserted rather than remembered
# (spec 0136, 2026-09-10, from the defect that produced it). SUITE_FILES globs
# test/suite/*.sh so the shard MANIFEST sees every file, while the sourcing
# above is a written list; a shard added to the directory and not to the list is
# therefore counted in the manifest's denominator and never reached, and its
# assertions are silently absent from a run that reports green. That is exactly
# what happened to 17-diagram-edition-0136.sh on its first full run: 1366
# assertions passed and not one of them was the new shard's. A suite that can
# quietly not run a file is the failure this whole project keeps rediscovering,
# so the two lists are compared here and disagreement is a FAILED assertion
# rather than a comment asking the next person to remember.
SUITE_ON_DISK="$(cd "$SUITE_DIR" && ls -1 ./*.sh 2>/dev/null | sed 's|^\./||' | sort)"
SUITE_SOURCED="$(grep -oE '^source "\$SUITE_DIR/[^"]+"' "$ROOT/test/run-tests.sh" | sed 's|^source "\$SUITE_DIR/||; s|"$||' | sort)"
if [[ "$SUITE_ON_DISK" == "$SUITE_SOURCED" ]]; then
  ok "suite wiring: every shard file in test/suite/ is sourced by the driver ($(printf '%s\n' "$SUITE_ON_DISK" | grep -c .) files)"
else
  bad "suite wiring: every shard file in test/suite/ is sourced by the driver" \
      "on disk but not sourced: [$(comm -23 <(printf '%s\n' "$SUITE_ON_DISK") <(printf '%s\n' "$SUITE_SOURCED") | tr '\n' ' ')]; sourced but not on disk: [$(comm -13 <(printf '%s\n' "$SUITE_ON_DISK") <(printf '%s\n' "$SUITE_SOURCED") | tr '\n' ' ')]"
fi

# --- summary -----------------------------------------------------------------

shard_region_end

printf '\n%s\n' "-----------------------------------------------"
# The shard line is printed BEFORE the totals line and in its own format, so
# every existing reader that greps `passed %d, failed %d, total %d` keeps
# working unchanged (A9: the surfaces that read this line were checked in spec
# 0127 and the format is deliberately untouched).
if [[ "$SHARD_N" -ne 0 ]]; then
  printf 'shard %d/%d, regions reached %d of %d\n' \
    "$SHARD_K" "$SHARD_N" "$SHARD_IDX" "$(shard_manifest | grep -c .)"
fi
printf 'passed %d, failed %d, total %d\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]] || exit 1
