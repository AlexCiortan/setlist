#!/usr/bin/env bash
#
# run-shards.sh - run test/run-tests.sh as N parallel shards and aggregate.
#
# Usage: bash test/run-shards.sh [--shards N] [--verify]
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
SHARDS=4
VERIFY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shards) SHARDS="${2:-}"; shift 2 || exit 2 ;;
    --verify) VERIFY=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf 'usage: %s [--shards N] [--verify]\n' "$0" >&2; exit 2 ;;
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

# --- the manifest, fail closed ----------------------------------------------
bash "$SUITE" --list-regions > "$W/manifest" 2>/dev/null || {
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

printf 'run-shards: %s regions, %s shards, one TMPDIR each\n\n' "$MANIFEST_N" "$SHARDS"

# --- run ---------------------------------------------------------------------
START="$(date +%s)"
k=1
while [[ "$k" -le "$SHARDS" ]]; do
  mkdir -p "$W/tmp$k"
  (
    TMPDIR="$W/tmp$k" bash "$SUITE" --shard "$k/$SHARDS" > "$W/log$k" 2>&1
    printf '%d\n' "$?" > "$W/rc$k"
  ) &
  k=$((k + 1))
done
wait
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
    grep -A1 '^FAIL ' "$W/log$k" | sed 's/^/    /' >&2
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
  TMPDIR="$W/tmpfull" bash "$SUITE" > "$W/logfull" 2>&1
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

printf '\n%s\n' "-----------------------------------------------"
printf 'shards %d, regions %d, wall-clock %ds\n' "$SHARDS" "$MANIFEST_N" "$((END - START))"
printf 'passed %d, failed %d, total %d\n' "$sum_pass" "$sum_fail" "$((sum_pass + sum_fail))"

if [[ "$fails" -ne 0 ]] || [[ "$sum_fail" -ne 0 ]]; then
  exit 1
fi
exit 0
