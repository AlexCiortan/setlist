#!/usr/bin/env bash
# Trunk audit: does the trunk's HISTORY show every piece of feature code
# arriving through a closed spec?
#
# Usage:
#   trunk-audit.sh [<instance-dir>] [--since <ref>]
#
# ADVISORY as of plugin 1.0.5. Nothing calls this automatically: it is not
# wired as a hook, it does not gate a commit, and a finding does not block
# anything. Run it by hand or from /setlist:validate. That is deliberate for
# a first release, because it reads real project history and real history is
# the only honest test of it.
#
# Why this exists, and why it is different in kind from the hooks. The three
# PreToolUse gates decide by parsing a shell command before it runs, and a
# shell command can compute its own arguments: no parser can be correct about
# what a command will do. Four releases of this plugin were spent improving
# that parser, and each improvement was itself the next release's defect. This
# asks a question that needs no parsing at all, and is decidable:
#
#   Every commit on the trunk that touches a role path is either part of a
#   merge from a branch whose spec carries a Closing report and a CLOSED
#   inventory row, or it is a violation.
#
# That catches what the parser misses BY CONSTRUCTION: chained merges, a
# branch renamed to hide it, a cherry-pick, a tag, a squash, the forge's merge
# button, and the ways nobody has thought of yet. All of them leave history,
# and history is what this reads.
#
# What it cannot do, stated so it is not oversold:
#   - A squash merge has no second parent, so the branch it came from is not
#     recoverable from history. Squashed work is reported as a direct commit.
#   - Rewritten or force-pushed history defeats it, as it defeats any audit.
#   - It says nothing about whether the QA behind a Closing report was honest.
#     It checks that the artifacts exist, not that they were earned.

set -u

INSTANCE="."
SINCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    *) INSTANCE="$1"; shift ;;
  esac
done

die() { printf 'trunk-audit.sh: %s\n' "$1" >&2; exit 2; }

[[ -d "$INSTANCE" ]] || die "not a directory: $INSTANCE"
command -v jq >/dev/null 2>&1 || die "jq is required to read .claude/sdd.json"
SDD="$INSTANCE/.claude/sdd.json"
[[ -f "$SDD" ]] || die "no .claude/sdd.json at $INSTANCE; this is not a framework instance"
jq -e . "$SDD" >/dev/null 2>&1 || die "$SDD does not parse"

TRUNK="$(jq -r '.trunk // "main"' "$SDD")"
mapfile_roles() { jq -r '[.roles.src // "src", .roles.tests // "tests"] | flatten | .[]' "$SDD"; }
ROLES="$(mapfile_roles)"
[[ -n "$ROLES" ]] || die "no role paths recorded in $SDD"

git -C "$INSTANCE" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 \
  || die "the recorded trunk '$TRUNK' does not resolve in this repository"

# Baseline. Everything before the instance was stamped is pre-framework and
# not this audit's business; auditing it would produce noise that trains the
# reader to ignore the report.
if [[ -z "$SINCE" ]]; then
  SINCE="$(git -C "$INSTANCE" log --format=%H --diff-filter=A -- .claude/sdd.json | tail -n1)"
  [[ -n "$SINCE" ]] || die "cannot find the commit that introduced .claude/sdd.json; pass --since <ref>"
fi

printf 'trunk audit: %s\n' "$(cd "$INSTANCE" && pwd)"
printf '  trunk: %s   roles: %s\n' "$TRUNK" "$(printf '%s' "$ROLES" | tr '\n' ' ')"
printf '  since: %s (%s)\n\n' "$(git -C "$INSTANCE" rev-parse --short "$SINCE")" \
  "$(git -C "$INSTANCE" log -1 --format=%s "$SINCE" | cut -c1-60)"

touches_role() { # touches_role <from> <to>
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    while IFS= read -r r; do
      [[ -n "$r" && "$r" != "." ]] || continue
      r="${r%/}"
      case "$f" in "$r"/*|"$r") return 0 ;; esac
    done <<EOF
$ROLES
EOF
  done < <(git -C "$INSTANCE" diff --name-only "$1" "$2" 2>/dev/null)
  return 1
}

VIOLATIONS=0
AUDITED=0
CLEAN=0
CHORES=0

while IFS= read -r C; do
  [[ -n "$C" ]] || continue
  AUDITED=$((AUDITED + 1))
  PARENTS="$(git -C "$INSTANCE" rev-list --parents -n1 "$C" | cut -d' ' -f2-)"
  NPAR="$(printf '%s' "$PARENTS" | wc -w | tr -d ' ')"
  P1="$(printf '%s' "$PARENTS" | cut -d' ' -f1)"
  SUBJ="$(git -C "$INSTANCE" log -1 --format=%s "$C" | cut -c1-58)"
  SHORT="$(git -C "$INSTANCE" rev-parse --short "$C")"

  if [[ "$NPAR" -lt 2 ]]; then
    # A direct commit on the trunk. Docs-only is the allowed case the whole
    # loop exists to distinguish.
    if [[ -n "$P1" ]] && touches_role "$P1" "$C"; then
      printf 'VIOLATION %s  feature code committed directly to %s\n' "$SHORT" "$TRUNK"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
    else
      CLEAN=$((CLEAN + 1))
    fi
    continue
  fi

  if ! touches_role "$P1" "$C"; then
    CLEAN=$((CLEAN + 1))
    continue
  fi

  # EVERY merged parent, not just the second (1.0.5, found by attacking this
  # script). An octopus merge has three or more parents, and reading only
  # parent 2 validated the compliant spec branch while ignoring everything
  # else merged in the same commit: `git merge spec/0001-ok sneaky` put
  # unspecced feature code on the trunk and this reported "1 clean, 0
  # violations". That is the close gate's own defect class, examining one
  # thing when there are several, reproduced in the backstop written to catch
  # what the close gate misses.
  MERGED_PARENTS="$(printf '%s' "$PARENTS" | cut -d' ' -f2-)"
  SEEN_BAD=0
  SEEN_CHORE=0
  for P2 in $MERGED_PARENTS; do

    # Which spec did the merged branch carry? Read it from the branch side, so a
    # renamed branch or a lost branch name changes nothing.
    # Unrelated histories have no merge-base, leaving BASE empty so the diff
    # reads the whole branch. That over-reports spec files rather than under-
    # reporting them, and erring toward FINDING a spec errs toward CHECKING it.
    # fail-open-ok: an empty BASE widens the search, it does not skip it.
    BASE="$(git -C "$INSTANCE" merge-base "$P1" "$P2" 2>/dev/null || true)"
    # Spec numbers carry an optional letter suffix in the field: 0005b and
    # 0008c are ordinary parallel-track specs, and the first cut of this regex
    # required digits-then-dash, so it read every one of them as "no spec file"
    # and reported a compliant merge as a violation. Found by running against
    # real history, which is the only reason this leg was gated on doing so.
    SPECS_TOUCHED="$(git -C "$INSTANCE" diff --name-only "$BASE" "$P2" 2>/dev/null \
      | grep -E '^specs/[0-9]+[a-z]*-[^/]*\.md$' | head -n1 || true)"   # fail-open-ok: no match means no spec on the branch, handled as a chore below

    if [[ -z "$SPECS_TOUCHED" ]]; then
      # A merge carrying role-path changes and NO spec file is a chore branch
      # (Part 5b: chores are unnumbered and have no spec), which is legitimate
      # and which history cannot distinguish from an unspecced feature. The
      # close gate has the same limit and checks only the gate command for
      # chores. Reported so it is visible, counted separately so it does not
      # train the reader to ignore violations.
      printf 'unverifiable %s  chore merge (no spec on the branch); history cannot say more\n' "$SHORT"
      CHORES=$((CHORES + 1))
      SEEN_CHORE=1
      continue
    fi

    SPEC_NUM="$(printf '%s' "$SPECS_TOUCHED" | sed -e 's#^specs/##' -e 's#-.*##')"
    # fail-open-ok: an unreadable spec or STATUS yields empty text, and every
    # check below is a grep that FAILS on empty, so the merge is reported as a
    # violation. Unreadable evidence counts against the merge, never for it.
    SPEC_TEXT="$(git -C "$INSTANCE" show "$P2:$SPECS_TOUCHED" 2>/dev/null || true)"
    # fail-open-ok: same, an unreadable STATUS.md fails the row grep below.
    STATUS_TEXT="$(git -C "$INSTANCE" show "$P2:specs/STATUS.md" 2>/dev/null || true)"

    MISSING=""
    printf '%s\n' "$SPEC_TEXT" | grep -qE '^#+[[:space:]]*Closing report' || MISSING="$MISSING no-closing-report"
    printf '%s\n' "$SPEC_TEXT" | grep -qE '(^|[^A-Z])(PASS|PARTIAL|FAIL)([^A-Z]|$)' || MISSING="$MISSING no-qa-verdict"
    # The status is a CELL, not a word anywhere in the row (leg 5, F8). The
    # close gate carried the identical defect and is fixed in the same commit:
    # an ACTIVE row whose note column mentions another spec's closure satisfied
    # both layers at once, so the gate and its only backstop went blind
    # together, which is precisely the case the two-layer design claims to
    # cover. Fixing one and not the other would have left the backstop making a
    # claim the gate no longer makes.
    printf '%s\n' "$STATUS_TEXT" | awk -F'|' -v num="$SPEC_NUM" '
      function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
      NF >= 5 && trim($2) == num && trim($4) == "CLOSED" { found = 1 }
      END { exit found ? 0 : 1 }
    ' \
      || MISSING="$MISSING no-CLOSED-row"
    if [[ -n "$MISSING" ]]; then
      printf 'VIOLATION %s  spec %s reached %s without:%s\n' "$SHORT" "$SPEC_NUM" "$TRUNK" "$MISSING"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
      SEEN_BAD=1
    fi
  done
  # A commit is counted once, in exactly one bucket: a violation if any merged
  # parent failed, otherwise unverifiable if any parent was a chore, otherwise
  # clean. Counting it clean AND chore inflated the clean figure, which is the
  # kind of reporting error that makes a report reassuring rather than true.
  if [[ "$SEEN_BAD" -eq 0 && "$SEEN_CHORE" -eq 0 ]]; then
    CLEAN=$((CLEAN + 1))
  fi
done < <(git -C "$INSTANCE" rev-list --first-parent "$SINCE".."$TRUNK" 2>/dev/null)

printf '\n-----------------------------------------------\n'
printf 'audited %d commits on %s: %d clean, %d chore merges (unverifiable), %d violations\n' \
  "$AUDITED" "$TRUNK" "$CLEAN" "$CHORES" "$VIOLATIONS"
if [[ "$AUDITED" -eq 0 ]]; then
  printf 'NOTE: nothing was audited. Check --since, or the trunk name in sdd.json.\n'
  exit 2
fi
[[ "$VIOLATIONS" -eq 0 ]] || exit 1
