#!/usr/bin/env bash
#
# run-shards.sh - run test/run-tests.sh as N parallel shards and aggregate.
#
# Usage: bash test/run-shards.sh [--shards N] [--verify] [--smoke] [--retry-dead] [--whole-failures]
#        (N defaults to the host's core count)
# Exit:  0  every shard green and every invariant held
#        1  a shard was red, or the aggregation refused
#        2  usage error, or a precondition that makes the answer meaningless
#
# ============================================================================
# WHY THIS EXISTS (backlog CI1, spec 0127).
#
# The suite is the multiplier behind the CI bill. Measured 2026-09-01 on the
# real runners: it is 11m00s of the macOS leg's 13m58s, and
# dogfood/mutation-check.sh runs it once per mutation plus a control, which is
# nine serial runs and 20m18s of the Linux leg's 25m43s. Sharding it is worth
# more through the mutation check than through the suite step, which is the
# fact CI1 was filed without.
#
# SEPARATE PROCESSES, SEPARATE TMPDIRS. The owner pre-decided the shard version
# over backgrounding cases inside the suite, and the TMPDIR split is what makes
# that decision real: the suite builds a fixture git repository per case under
# ${TMPDIR}, so two shards sharing one TMPDIR would be the shared state the
# decision exists to avoid.
#
# THE AGGREGATION REFUSES RATHER THAN REPORTS, which is the whole reason this
# file is longer than a for-loop. CI1 names the risk by name: a shard that
# silently did not run must not read as a shard with nothing to report. So a
# missing shard, a missing totals line, a region claimed by nobody, a region
# claimed twice, a region that ran and asserted nothing, and a region reported
# that is not in the manifest are each a refusal that NAMES the region. A
# parallel harness whose failure mode is a smaller number is worse than no
# parallel harness, because the number still looks like a result.
#
# THE MANIFEST IS READ FROM THE SUITE, not carried here. `--list-regions` reads
# the SHARD-BEGIN markers that the guards themselves key on, so there is one
# statement of what the regions are and this file cannot disagree with it.
#
# Private only in the sense that nothing else is: test/ is exported, so this
# file ships. It depends on nothing outside test/.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SCRIPT_DIR/run-tests.sh"
# ONE SHARD PER CORE by default (spec 0168, item 2). The default was 4 while the
# prelude ran in every shard and more shards only repeated it: on the reference
# Mac 8 and 10 shards read 215 and 245 s against 243 s at 4. With the prelude in
# measured regions the same host reads 171, 125, 109 and 106 s at 4, 6, 8 and 10,
# so the host's own core count is the default and --shards still overrides it.
SHARDS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
case "$SHARDS" in ''|*[!0-9]*|0) SHARDS=4 ;; esac
VERIFY=0
SMOKE_ARG=""   # --smoke: the platform smoke's regions only (spec 0168, item 8)
RETRY_DEAD=0   # --retry-dead: one retry of a shard that died before its first case (spec 0180)
WHOLE_FAIL=0   # --whole-failures: every detail line of a red shard's failures (spec 0180, E-j)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shards) SHARDS="${2:-}"; shift 2 || exit 2 ;;
    --verify) VERIFY=1; shift ;;
    --smoke) SMOKE_ARG="--smoke"; shift ;;
    --retry-dead) RETRY_DEAD=1; shift ;;
    --whole-failures) WHOLE_FAIL=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) printf 'usage: %s [--shards N] [--verify] [--smoke] [--retry-dead] [--whole-failures]\n' "$0" >&2; exit 2 ;;
  esac
done

case "$SHARDS" in
  ''|*[!0-9]*) printf 'run-shards: --shards wants a positive integer, got "%s"\n' "$SHARDS" >&2; exit 2 ;;
esac
[[ "$SHARDS" -ge 1 ]] || { printf 'run-shards: --shards must be at least 1\n' >&2; exit 2; }
[[ -f "$SUITE" ]] || { printf 'run-shards: no suite at %s\n' "$SUITE" >&2; exit 2; }

W="$(mktemp -d "${TMPDIR:-/tmp}/setlist-shards.XXXXXX")" || {
  printf 'run-shards: could not create a work directory under %s. Refusing rather than\n' "${TMPDIR:-/tmp}" >&2
  printf '            running the shards somewhere they would collide.\n' >&2
  exit 2
}
trap 'rm -rf "$W"' EXIT
# A DEAD SHARD'S LOG OUTLIVES THE SCRATCH (spec 0179, 0168's E-i as ruled). A shard
# that recorded no exit status or no totals line is the one whose log matters, and
# the trap above deletes it with the scratch, so a shard that died on the Windows
# guest in run 35955750662 left nothing to diagnose. The log is copied beside the
# scratch, under the same TMPDIR, and its path is printed with the refusal.
keep_dead_log() { # keep_dead_log <k>
  local keep
  [[ -f "$W/log$1" ]] || { printf '                    It left no log at all.\n' >&2; return 0; }
  keep="$(mktemp "${TMPDIR:-/tmp}/setlist-dead-shard-$1of$SHARDS.XXXXXX")" && cp "$W/log$1" "$keep" \
    && printf '                    Its whole log is kept at %s\n' "$keep" >&2
}

# --- the manifest, fail closed ----------------------------------------------
bash "$SUITE" --list-regions $SMOKE_ARG > "$W/manifest" 2>"$W/manifest.err" || {
  cat "$W/manifest.err" >&2
  printf 'run-shards: the suite refused --list-regions, so the region set is unknown.\n' >&2
  exit 2
}
MANIFEST_N="$(grep -c . < "$W/manifest" | tr -d ' ')"
if [[ "$MANIFEST_N" -eq 0 ]]; then
  printf 'run-shards: the suite declares NO shard regions, so every shard would run the\n' >&2
  printf '            same thing and the coverage invariant below would compare nothing\n' >&2
  printf '            against nothing. Refusing rather than reporting a clean parallel run.\n' >&2
  exit 2
fi
if [[ "$(LC_ALL=C sort -u "$W/manifest" | grep -c .)" -ne "$MANIFEST_N" ]]; then
  printf 'run-shards: the region manifest has duplicate ids, so a region cannot be\n' >&2
  printf '            attributed to one shard. Refusing.\n' >&2
  LC_ALL=C sort "$W/manifest" | uniq -d | sed 's/^/            duplicated: /' >&2
  exit 2
fi

printf 'run-shards: %s regions, %s shards, one TMPDIR each%s\n\n' "$MANIFEST_N" "$SHARDS" "${SMOKE_ARG:+ (the platform smoke)}"

# --- run ---------------------------------------------------------------------
START="$(date +%s)"
run_shard() { # run_shard <k>: one shard, its log, exit status and end time under $W
  TMPDIR="$W/tmp$1" bash "$SUITE" --shard "$1/$SHARDS" $SMOKE_ARG > "$W/log$1" 2>&1
  printf '%d\n' "$?" > "$W/rc$1"
  date +%s > "$W/end$1"
}
k=1
while [[ "$k" -le "$SHARDS" ]]; do
  mkdir -p "$W/tmp$k"
  run_shard "$k" &
  k=$((k + 1))
done
wait

# ONE RETRY OF A SHARD THAT DIED BEFORE ITS FIRST CASE (spec 0180; the validator's ruling at 0179's
# close). On the Windows guest a shard's own bash has died about 26 s in, before any case, under the
# runner's service account on the emulated machine (the E-h class of 0179 reaching a shard process):
# its log held the header and the root line and nothing else (254a928, e1aee07), and the same bytes
# read green on the next run. With --retry-dead, and only then, such a shard is run ONCE more in a
# fresh TMPDIR, and its first log is printed whole into this output first, with a DEAD-SHARD: line per
# death so every sighting is counted. A shard that died after a case line is never retried, and a
# second death is refused exactly as the first would have been: the retry adds a run, it never removes
# a refusal. The Windows jobs pass the flag; every other caller reads the wrapper as it was.
shard_dead() { [[ ! -f "$W/rc$1" ]] || ! grep -qE '^passed [0-9]+, failed [0-9]+, total [0-9]+$' "$W/log$1" 2>/dev/null; }
shard_casefree() { ! grep -qE '^(PASS|FAIL) ' "$W/log$1" 2>/dev/null; }
print_dead_log() { # print_dead_log <k> <label>
  printf 'DEAD-SHARD: shard %d/%d %s; its whole log (%s lines):\n' "$1" "$SHARDS" "$2" "$( (cat "$W/log$1" 2>/dev/null || true) | wc -l | tr -d ' ')" >&2
  if [[ -f "$W/log$1" ]]; then sed 's/^/    | /' "$W/log$1" >&2; else printf '    | (no log)\n' >&2; fi
}
if [[ "$RETRY_DEAD" -eq 1 ]]; then
  k=1
  while [[ "$k" -le "$SHARDS" ]]; do
    if shard_dead "$k"; then
      if shard_casefree "$k"; then
        print_dead_log "$k" "died before its first case, retried once"
        keep_dead_log "$k"
        rm -rf "$W/tmp$k" "$W/rc$k" "$W/end$k"; mkdir -p "$W/tmp$k"
        run_shard "$k"
        if shard_dead "$k"; then
          print_dead_log "$k" "died AGAIN on its one retry, so it is refused below, by name"
        else
          printf 'DEAD-SHARD: shard %d/%d completed on its one retry.\n' "$k" "$SHARDS" >&2
        fi
      else
        print_dead_log "$k" "died after a case line, which is never retried"
      fi
    fi
    k=$((k + 1))
  done
fi
END="$(date +%s)"

# --- aggregate ---------------------------------------------------------------
fails=0
sum_pass=0
sum_fail=0
: > "$W/claimed"
: > "$W/preludes"

k=1
while [[ "$k" -le "$SHARDS" ]]; do
  if [[ ! -f "$W/rc$k" ]]; then
    printf 'run-shards REFUSED: shard %d/%d never recorded an exit status. It did not run to\n' "$k" "$SHARDS" >&2
    printf '                    completion, and a missing shard is not an empty shard.\n' >&2
    keep_dead_log "$k"
    fails=$((fails + 1)); k=$((k + 1)); continue
  fi
  rc="$(cat "$W/rc$k")"

  # The totals line is the shard's own denominator. Its ABSENCE is the missing
  # shard case CI1 names: the process may have exited 0 having died before it
  # asserted anything.
  tot="$(grep -E '^passed [0-9]+, failed [0-9]+, total [0-9]+$' "$W/log$k" | tail -n 1)"
  if [[ -z "$tot" ]]; then
    printf 'run-shards REFUSED: shard %d/%d produced no totals line, so it reported no\n' "$k" "$SHARDS" >&2
    printf '                    denominator at all. Last lines of its log:\n' >&2
    tail -n 5 "$W/log$k" | sed 's/^/                    /' >&2
    keep_dead_log "$k"
    fails=$((fails + 1)); k=$((k + 1)); continue
  fi
  p="$(printf '%s' "$tot" | sed -E 's/^passed ([0-9]+), failed ([0-9]+).*/\1/')"
  f="$(printf '%s' "$tot" | sed -E 's/^passed ([0-9]+), failed ([0-9]+).*/\2/')"

  # THE PRELUDE IS COUNTED ONCE, NOT N TIMES, and getting this wrong is what a
  # first cut of this file did. Everything OUTSIDE a marked region runs in every
  # shard by design, so summing the shards' own totals counts that work N times
  # and the sum can never equal an unsharded run. The shard's total minus its
  # region assertions IS the prelude, so it is derived rather than declared, and
  # every shard must agree on it: a disagreement means the always-run part of
  # the suite behaved differently in different shards, which is a finding in
  # itself and not something to average away.
  rp="$(awk '/^__REGION__ /{p+=$3; f+=$4} END{printf "%d %d", p+0, f+0}' "$W/log$k")"
  reg_pass="${rp%% *}"; reg_fail="${rp##* }"
  sum_pass=$((sum_pass + reg_pass))
  sum_fail=$((sum_fail + reg_fail))
  printf '%d %d\n' "$((p - reg_pass))" "$((f - reg_fail))" >> "$W/preludes"

  nreg="$(grep -c '^__REGION__ ' "$W/log$k" | tr -d ' ')"
  printf 'shard %d/%d: rc=%s, %s regions, passed %s, failed %s (regions %s, prelude %s)\n' \
    "$k" "$SHARDS" "$rc" "$nreg" "$p" "$f" "$reg_pass" "$((p - reg_pass))"

  if [[ "$rc" -ne 0 ]]; then
    printf '  shard %d/%d is RED. Its failures:\n' "$k" "$SHARDS" >&2
    if [[ "$WHOLE_FAIL" -eq 1 ]]; then
      # Every line of each failure, up to the next case, region or timing line (spec 0180, E-j:
      # one detail line per failure named no cause for the runner account's five cases). Each
      # terminator is the suite's own spelling of that line, the case lines' two spaces included
      # (spec 0180, fix round 2, the 2.11.0 leg's F14): a detail line that merely BEGAN with one
      # of the words, "PASS 2 of a captured sub-run", ended the failure and dropped the cause.
      awk '/^FAIL  /{on=1; print; next} on && (/^PASS  / || /^__REGION__ [^ ]+ [0-9]+ [0-9]+/ || /^__SHARD__ [0-9]+\/[0-9]+ / || /^TIME [0-9]+\.[0-9][0-9][0-9][0-9][0-9][0-9] / || /^HOOKTIME [^ ]+ [0-9]+\.[0-9][0-9][0-9][0-9][0-9][0-9] / || /^passed [0-9]+, failed [0-9]+, total [0-9]+/){on=0} on' "$W/log$k" | sed 's/^/    /' >&2
    else
      grep -A1 '^FAIL ' "$W/log$k" | sed 's/^/    /' >&2
    fi
    fails=$((fails + 1))
  fi

  # A region that ran and asserted NOTHING is the vacuous-comparison shape one
  # level up: it reads as coverage and is not.
  while IFS=' ' read -r _ id rp rf; do
    printf '%s\n' "$id" >> "$W/claimed"
    if [[ "$((rp + rf))" -eq 0 ]]; then
      printf 'run-shards REFUSED: region %s ran in shard %d/%d and asserted NOTHING. A region\n' "$id" "$k" "$SHARDS" >&2
      printf '                    with an empty denominator reads as covered and is not.\n' >&2
      fails=$((fails + 1))
    fi
  done < <(grep '^__REGION__ ' "$W/log$k")

  k=$((k + 1))
done

# --- the prelude invariant ---------------------------------------------------
if [[ "$(LC_ALL=C sort -u "$W/preludes" | grep -c .)" -gt 1 ]]; then
  printf 'run-shards REFUSED: the shards disagree about the always-run part of the suite.\n' >&2
  printf '                    Every shard runs everything outside a marked region, so these\n' >&2
  printf '                    numbers must be identical. Observed (passed failed):\n' >&2
  LC_ALL=C sort -u "$W/preludes" | sed 's/^/                    /' >&2
  fails=$((fails + 1))
fi
prelude_pass="$(head -n 1 "$W/preludes" | cut -d' ' -f1)"
prelude_fail="$(head -n 1 "$W/preludes" | cut -d' ' -f2)"
sum_pass=$((sum_pass + prelude_pass))
sum_fail=$((sum_fail + prelude_fail))

# --- the coverage invariant --------------------------------------------------
LC_ALL=C sort "$W/claimed" > "$W/claimed_sorted"
LC_ALL=C sort "$W/manifest" > "$W/manifest_sorted"
# UNIQUE for the set comparisons, the full list for the duplicate detection.
# Without this split, `comm` reads the second copy of a duplicated region as a
# region that is not in the manifest, and the run refuses TWICE for one fault
# with one of the two messages stating something false. Watched: a region
# claimed by all four shards printed three "not in the manifest" lines about a
# region that is in the manifest, beside the correct duplicate refusal.
LC_ALL=C sort -u "$W/claimed" > "$W/claimed_uniq"

if LC_ALL=C comm -23 "$W/manifest_sorted" "$W/claimed_uniq" > "$W/unclaimed" && [[ -s "$W/unclaimed" ]]; then
  while IFS= read -r id; do
    printf 'run-shards REFUSED: region %s was claimed by NO shard, so it did not run in this\n' "$id" >&2
    printf '                    parallel run at all and the total below would be short by it.\n' >&2
  done < "$W/unclaimed"
  # The shard that should have run them is one that claimed NO region although the
  # manifest gave it some: it printed its totals, so the refusal above kept no log.
  # Its log is the one that says why (spec 0179: shard 5 of 8 did this once on the
  # Windows guest, the platform smoke at b85d71b, and left nothing to read).
  k=1
  while [[ "$k" -le "$SHARDS" ]]; do
    if [[ -f "$W/log$k" ]] && ! grep -q '^__REGION__ ' "$W/log$k"; then
      printf 'run-shards: shard %d/%d claimed no region.\n' "$k" "$SHARDS" >&2
      keep_dead_log "$k"
    fi
    k=$((k + 1))
  done
  fails=$((fails + 1))
fi
if LC_ALL=C comm -13 "$W/manifest_sorted" "$W/claimed_uniq" > "$W/unknown" && [[ -s "$W/unknown" ]]; then
  while IFS= read -r id; do
    printf 'run-shards REFUSED: shard output names region %s, which is not in the manifest.\n' "$id" >&2
  done < "$W/unknown"
  fails=$((fails + 1))
fi
if LC_ALL=C uniq -d "$W/claimed_sorted" > "$W/twice" && [[ -s "$W/twice" ]]; then
  while IFS= read -r id; do
    printf 'run-shards REFUSED: region %s was claimed by more than one shard, so its\n' "$id" >&2
    printf '                    assertions are counted twice in the total below.\n' >&2
  done < "$W/twice"
  fails=$((fails + 1))
fi

# --- the optional same-host comparison ---------------------------------------
#
# Deliberately NOT the default. Running the suite unsharded on every sharded run
# would spend exactly what the sharding saves. It is the measurement a session
# takes when it CHANGES the partition, and it compares against a run on THIS
# host in THIS session rather than against a pinned number, because the suite's
# total legitimately differs by host (a case guarded on ssh-keygen, among
# others), and a pinned total would turn a host difference into a false red.
if [[ "$VERIFY" -eq 1 ]]; then
  printf '\nrun-shards --verify: running the suite unsharded on this host to compare.\n'
  mkdir -p "$W/tmpfull"
  TMPDIR="$W/tmpfull" bash "$SUITE" $SMOKE_ARG > "$W/logfull" 2>&1
  fullrc=$?
  fulltot="$(grep -E '^passed [0-9]+, failed [0-9]+, total [0-9]+$' "$W/logfull" | tail -n 1)"
  fullp="$(printf '%s' "$fulltot" | sed -E 's/^passed ([0-9]+),.*/\1/')"
  fullf="$(printf '%s' "$fulltot" | sed -E 's/^passed [0-9]+, failed ([0-9]+).*/\1/')"
  printf 'unsharded: rc=%d, %s\n' "$fullrc" "$fulltot"
  if [[ "$((sum_pass + sum_fail))" -ne "$((fullp + fullf))" ]]; then
    printf 'run-shards REFUSED: the shards total %d assertions and the unsharded suite totals\n' "$((sum_pass + sum_fail))" >&2
    printf '                    %d on this same host. The partition is losing or repeating work.\n' "$((fullp + fullf))" >&2
    fails=$((fails + 1))
  else
    printf 'verify: sharded and unsharded agree at %d assertions on this host.\n' "$((sum_pass + sum_fail))"
  fi
fi

# PER-SHARD ELAPSED, and with SETLIST_SUITE_TIMES=1 every case's TIME line
# (spec 0165, the owner's instruction on the Windows measurement): the wall
# clock alone cannot say which shard, or which case, carries a platform's gap.
# Printed before the totals line, which stays the last line its callers read.
printf '\n'
k=1
while [[ "$k" -le "$SHARDS" ]]; do
  if [[ -f "$W/end$k" ]]; then
    printf 'shard %d/%d: elapsed %ds\n' "$k" "$SHARDS" "$(( $(cat "$W/end$k") - START ))"
  fi
  k=$((k + 1))
done
if [[ "${SETLIST_SUITE_TIMES:-}" == "1" || "${SETLIST_SUITE_HOOKTIME:-}" == "1" ]]; then
  # HOOKTIME lines too (spec 0168, item 7): the hooks' share measured per shard would
  # otherwise stay in the shard logs this wrapper deletes.
  k=1
  while [[ "$k" -le "$SHARDS" ]]; do
    grep -E '^(TIME|HOOKTIME) ' "$W/log$k" 2>/dev/null | sed "s|^|shard $k/$SHARDS |"
    k=$((k + 1))
  done
fi

printf '\n%s\n' "-----------------------------------------------"
printf 'shards %d, regions %d, wall-clock %ds\n' "$SHARDS" "$MANIFEST_N" "$((END - START))"
printf 'passed %d, failed %d, total %d\n' "$sum_pass" "$sum_fail" "$((sum_pass + sum_fail))"

if [[ "$fails" -ne 0 ]] || [[ "$sum_fail" -ne 0 ]]; then
  exit 1
fi
exit 0
