#!/usr/bin/env bash
# SDD Part extractor. Prints one Part (or Appendix) of the bundled edition by
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
# The edition file defaults to setlist.md at the plugin root (one directory
# above this script); the edition version lives inside the file. A missing file
# fails loudly; an explicit second argument overrides (used by tests).

set -euo pipefail

die() { printf '%s\n' "part.sh: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: part.sh <part-id>|--list [edition-file]"
TARGET="$1"
EDITION="${2:-}"

if [[ -z "$EDITION" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  EDITION="$ROOT/setlist.md"
  [[ -f "$EDITION" ]] || die "setlist.md not found at the plugin root ($ROOT)"
fi
[[ -f "$EDITION" ]] || die "edition file not found: $EDITION"

# One awk program serves both modes. It walks the edition tracking fence state;
# every unfenced "## Part <id>" or "## Appendix <letter>" heading is an
# extractable unit. --list prints "id<TAB>heading" per unit; extract prints
# from the matching heading up to (not including) the next unfenced "## "
# heading and signals the match count through the exit status.
run_awk() {
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
  ' "$EDITION"
}

if [[ "$TARGET" == "--list" ]]; then
  run_awk list ""
  exit 0
fi

# The canonical spec-lifecycle enumeration, extracted rather than restated.
#
# This is what makes the lifecycle lockstep REAL rather than a convention. The
# commit gate enumerates the lifecycle vocabulary literally, so a state the
# protocol gains and the gate does not is a transition the gate silently fails
# to notice. Binding the gate to the edition by grepping prose would be the same
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
  ' "$EDITION")"
  [[ -n "$STATES" ]] || die "no SDD-LIFECYCLE-STATES block found in $EDITION; the canonical lifecycle enumeration is missing or its markers were renamed"
  printf '%s\n' "$STATES"
  exit 0
fi

set +e
OUTPUT="$(run_awk extract "$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')")"
STATUS=$?
set -e

case $STATUS in
  0) printf '%s\n' "$OUTPUT" ;;
  3)
    printf 'part.sh: no Part matches id "%s" in %s\navailable ids:\n' "$TARGET" "$EDITION" >&2
    run_awk list "" | sed 's/^/  /' >&2
    exit 1
    ;;
  4)
    printf 'part.sh: id "%s" matches more than one heading in %s; the edition is malformed\n' "$TARGET" "$EDITION" >&2
    exit 1
    ;;
  *) die "extraction failed with status $STATUS" ;;
esac
