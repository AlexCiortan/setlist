#!/usr/bin/env bash
# Setlist Part extractor. Prints one Part (or Appendix) of the bundled edition by
# heading range, so commands load only the protocol text they bind instead of
# the full edition (design: the two-phase bootstrap's input reduction).
#
# Usage:
#   part.sh <part-id> [edition-file]     print that Part
#   part.sh --list [edition-file]        list every extractable id and heading
#
# Part ids are heading-anchored, not title-anchored: "8b" matches the heading
# line "## Part 8b - <any title>", "appendix-c" matches "## Appendix C - <any
# title>". Titles may change between editions; the anchors survive. The ids the
# plugin commands bind: 2, 6, 7, 8, 8b, 8c, appendix-c.
#
# A Part runs from its "## " heading to the next "## " heading OUTSIDE fenced
# code blocks. Fence-awareness is load-bearing: Appendix C embeds the spec
# template inside a ```markdown fence, and the template's own "## " lines must
# not terminate the range.
#
# The edition is THREE files at the plugin root (one directory above this
# script) since spec 0191, read in this order: setlist.md (the core, Parts 1 to
# 6), setlist-operations.md (Parts 7 to 10 and Appendices A to C) and
# setlist-changelog.md (the Changelog); the edition version lives inside each.
# With no file argument an id is resolved across the three, each file read ON
# ITS OWN: a Part never runs across a file boundary, so a file's opening lines
# (its Edition header and the sentence naming its companions) never join the
# previous file's last Part. A missing file fails loudly, by name. An explicit
# second argument names ONE file and keeps its old meaning (used by tests).

set -euo pipefail

die() { printf '%s\n' "part.sh: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: part.sh <part-id>|--list [edition-file]"
TARGET="$1"
EDITION="${2:-}"

EDITIONS=()
if [[ -z "$EDITION" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  for f in setlist.md setlist-operations.md setlist-changelog.md; do
    [[ -f "$ROOT/$f" ]] || die "$f not found at the plugin root ($ROOT); the edition is three files"
    EDITIONS+=("$ROOT/$f")
  done
  EDITION="${EDITIONS[*]}"
else
  [[ -f "$EDITION" ]] || die "edition file not found: $EDITION"
  EDITIONS=("$EDITION")
fi

# One awk program serves both modes. It walks the edition tracking fence state;
# every unfenced "## Part <id>" or "## Appendix <letter>" heading is an
# extractable unit. --list prints "id<TAB>heading" per unit; extract prints
# from the matching heading up to (not including) the next unfenced "## "
# heading and signals the match count through the exit status.
run_awk() {  # run_awk <mode> <target> <file>: one file, never the three joined
  awk -v mode="$1" -v target="$2" '
    function heading_id(line,   parts, id) {
      split(line, parts, /[[:space:]]+/)
      # parts[1]="##", parts[2]="Part"|"Appendix", parts[3]=the anchor token
      id = tolower(parts[3])
      sub(/[^0-9a-z].*$/, "", id)   # strip trailing punctuation, keep "8b"
      if (tolower(parts[2]) == "appendix") id = "appendix-" id
      return id
    }
    /^```/ { fence = !fence }
    !fence && /^## / {
      printing = 0
      if ($0 ~ /^## (Part|Appendix) /) {
        id = heading_id($0)
        if (mode == "list") printf "%s\t%s\n", id, $0
        if (mode == "extract" && id == target) { printing = 1; matches++ }
      }
    }
    printing { print }
    END {
      if (mode == "extract") exit (matches == 1 ? 0 : (matches == 0 ? 3 : 4))
    }
  ' "$3"
}
list_all() { local f; for f in "${EDITIONS[@]}"; do run_awk list "" "$f"; done; }

if [[ "$TARGET" == "--list" ]]; then
  list_all
  exit 0
fi

# The canonical spec-lifecycle enumeration, extracted rather than restated.
#
# This is what makes the lifecycle lockstep REAL rather than a convention. The
# pre-commit hook enumerates the lifecycle vocabulary literally, so a state the
# protocol gains and the hook does not is a transition the hook silently fails
# to notice. Binding the hook to the edition by grepping prose would be the same
# defect one layer up (a check reporting a result it did not earn), so the
# edition carries a marked, fenced block and THIS is the mechanism that reads
# it, the same extractor that already builds every instance's specs/TEMPLATE.md
# from Appendix C.
#
# Prints one state per line. Emptiness is an ERROR, not an empty list: a caller
# that got zero states would compare against nothing and pass.
if [[ "$TARGET" == "lifecycle-states" ]]; then
  STATES="$(awk '
    /<!-- SDD-LIFECYCLE-STATES:BEGIN -->/ { inblock = 1; next }
    /<!-- SDD-LIFECYCLE-STATES:END -->/   { inblock = 0 }
    inblock && !/^```/ && NF { print $1 }
  ' "${EDITIONS[@]}")"
  [[ -n "$STATES" ]] || die "no SDD-LIFECYCLE-STATES block found in $EDITION; the canonical lifecycle enumeration is missing or its markers were renamed"
  printf '%s\n' "$STATES"
  exit 0
fi

# Each file is asked on its own; the id must match exactly one heading across
# the three, so the found count is summed rather than taken from any one file.
ID="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"
FOUND=0; OUTPUT=""; STATUS=3
for f in "${EDITIONS[@]}"; do
  set +e
  out="$(run_awk extract "$ID" "$f")"; rc=$?
  set -e
  case $rc in
    0) FOUND=$((FOUND + 1)); OUTPUT="$out" ;;
    3) ;;
    4) FOUND=$((FOUND + 2)) ;;
    *) die "extraction failed with status $rc in $f" ;;
  esac
done
[[ "$FOUND" -eq 1 ]] && STATUS=0
[[ "$FOUND" -gt 1 ]] && STATUS=4

case $STATUS in
  0) printf '%s\n' "$OUTPUT" ;;
  3)
    printf 'part.sh: no Part matches id "%s" in %s\navailable ids:\n' "$TARGET" "$EDITION" >&2
    list_all | sed 's/^/  /' >&2
    exit 1
    ;;
  4)
    printf 'part.sh: id "%s" matches more than one heading in %s; the edition is malformed\n' "$TARGET" "$EDITION" >&2
    exit 1
    ;;
  *) die "extraction failed with status $STATUS" ;;
esac
