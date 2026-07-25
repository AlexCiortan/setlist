#!/usr/bin/env bash
# The plugin version, read live from a plugin tree's manifest, plus the ordered
# comparison every version-aware caller needs. One file owns version semantics
# so stamp.sh, refresh-instance.sh, and plugin-skew.sh cannot drift apart.
#
# Usage:
#   plugin-version.sh [tree-dir]        print the version of that plugin tree
#                                       (default: the tree this script lives in)
#   plugin-version.sh --name [tree-dir] print the plugin name that tree declares
#   plugin-version.sh --compare A B     print newer | older | same, comparing A to B
#
# Exit 0 on a determined answer, 1 on anything undeterminable, with the reason
# on stderr. Callers must treat exit 1 as "refuse", never as "assume equal":
# every downgrade this file exists to prevent looks exactly like an unknown
# version to the code above it.
#
# No jq. This reads the plugin's own manifest, a file the plugin controls and
# always ships pretty-printed, so a line-anchored extraction is sufficient and
# keeps the stamp free of runtime dependencies. If the manifest is ever shaped
# so the extraction cannot see the field, the answer is undeterminable and this
# script says so rather than returning an empty string that reads as a version.

set -u

die() { printf '%s\n' "plugin-version.sh: $*" >&2; exit 1; }

# A plain SemVer triple, optionally with a prerelease or build suffix that the
# comparison below ignores. Anything else is undeterminable.
valid() { # valid <string>
  case "$1" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) return 1 ;;
  esac
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([.+-].*)?$'
}

# Compare the numeric triples. Pure shell arithmetic: `sort -V` is GNU-only in
# practice and the macOS leg is where that would be discovered.
part() { # part <version> <1|2|3>
  local v="${1%%[-+]*}"
  case "$2" in
    1) printf '%s' "${v%%.*}" ;;
    2) v="${v#*.}"; printf '%s' "${v%%.*}" ;;
    3) v="${v#*.*.}"; printf '%s' "${v%%.*}" ;;
  esac
}

compare() { # compare <a> <b>
  valid "$1" || die "not a version: '$1'"
  valid "$2" || die "not a version: '$2'"
  local i a b
  for i in 1 2 3; do
    a="$(part "$1" "$i")"
    b="$(part "$2" "$i")"
    if [[ "$a" -gt "$b" ]]; then printf 'newer\n'; return 0; fi
    if [[ "$a" -lt "$b" ]]; then printf 'older\n'; return 0; fi
  done
  printf 'same\n'
}

field() { # field <tree-dir> <json-key>
  local manifest="$1/.claude-plugin/plugin.json" value
  [[ -f "$manifest" ]] || die "no plugin manifest at $manifest"
  value="$(sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$manifest" | head -n1)"
  [[ -n "$value" ]] || die "the manifest at $manifest declares no $2 field this script can read"
  printf '%s\n' "$value"
}

MODE=version
if [[ "${1:-}" == "--compare" ]]; then
  [[ $# -eq 3 ]] || die "usage: plugin-version.sh --compare <a> <b>"
  compare "$2" "$3"
  exit 0
elif [[ "${1:-}" == "--name" ]]; then
  MODE=name
  shift
fi

[[ $# -le 1 ]] || die "usage: plugin-version.sh [--name] [tree-dir]"
if [[ $# -eq 1 ]]; then
  TREE="$1"
else
  TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
[[ -d "$TREE" ]] || die "not a directory: $TREE"

if [[ "$MODE" == "name" ]]; then
  field "$TREE" name
  exit 0
fi

VERSION="$(field "$TREE" version)"
valid "$VERSION" || die "the manifest at $TREE/.claude-plugin/plugin.json declares an unreadable version: '$VERSION'"
printf '%s\n' "$VERSION"
