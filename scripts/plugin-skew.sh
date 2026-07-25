#!/usr/bin/env bash
# Session-versus-plugin skew: is the plugin tree this session is bound to the
# newest one present in the plugin cache?
#
# Usage: plugin-skew.sh [tree-dir]     (default: the tree this script lives in)
#
# Why this exists (backlog item 21, second field occurrence). A session binds
# its plugin tree at session start, and the cache keeps every installed version
# side by side as <cache>/<marketplace>/<plugin>/<version>/. After a marketplace
# update, a session opened before it stays on the old tree and reports that
# version honestly, having no way to know a newer one arrived. In the field that
# session read the OLD upgrade instructions and would have refreshed an instance
# from the OLD hook bytes while reporting an upgrade. The document that would
# have warned about the situation was itself the stale thing.
#
# Exit codes, and the deliberate asymmetry between them:
#   0  no skew: sibling trees were found and none is newer than this one.
#   1  SKEW: a newer tree is demonstrably present. Callers refuse on this.
#   2  unverified: no sibling trees to compare against. A local checkout and a
#      single-version cache both look like this, so this is the normal state
#      outside the cache and callers must NOT refuse on it, only report it.
#      Refusing here would make the plugin unusable from a working checkout,
#      which is how a safety check turns into a habit of bypassing safety
#      checks. The refusal that protects the instance is the DIRECTION check in
#      refresh-instance.sh, which does refuse when undeterminable.
#
# No check here can prove the marketplace holds nothing newer; the honest claim
# is about the trees present locally, and the output says only that.

set -u

VER_TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin-version.sh"

if [[ $# -ge 1 ]]; then
  TREE="$1"
else
  TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ ! -d "$TREE" ]]; then
  printf 'plugin-skew.sh: not a directory: %s\n' "$TREE" >&2
  exit 2
fi
TREE="$(cd "$TREE" && pwd)"

CURRENT="$(bash "$VER_TOOL" "$TREE" 2>/dev/null || true)"
NAME="$(bash "$VER_TOOL" --name "$TREE" 2>/dev/null || true)"
if [[ -z "$CURRENT" || -z "$NAME" ]]; then
  printf 'Plugin name or version undeterminable at %s, so session skew cannot be evaluated. Say so before refreshing anything.\n' "$TREE"
  exit 2
fi

# Sibling trees: the cache lays versions out beside each other under the
# plugin's directory. A neighbour counts only if it declares the SAME plugin
# name: run from a working checkout, the neighbours are unrelated repositories,
# and comparing their versions produced a confident false SKEW the first time
# this script was pointed at one.
PARENT="$(dirname "$TREE")"
EXAMINED=0
NEWEST="$CURRENT"
NEWEST_PATH="$TREE"
UNREADABLE=0

for candidate in "$PARENT"/*; do
  [[ -d "$candidate" ]] || continue
  [[ -f "$candidate/.claude-plugin/plugin.json" ]] || continue
  candidate="$(cd "$candidate" && pwd)"
  [[ "$candidate" == "$TREE" ]] && continue
  [[ "$(bash "$VER_TOOL" --name "$candidate" 2>/dev/null || true)" == "$NAME" ]] || continue
  EXAMINED=$((EXAMINED + 1))
  found="$(bash "$VER_TOOL" "$candidate" 2>/dev/null || true)"
  if [[ -z "$found" ]]; then
    UNREADABLE=$((UNREADABLE + 1))
    continue
  fi
  if [[ "$(bash "$VER_TOOL" --compare "$found" "$NEWEST" 2>/dev/null)" == "newer" ]]; then
    NEWEST="$found"
    NEWEST_PATH="$candidate"
  fi
done

# Coverage before result (backlog item 19): a check that compared against
# nothing must never read as a clean bill of health.
if [[ "$EXAMINED" -eq 0 ]]; then
  printf 'Plugin %s (%s), from %s.\n' "$CURRENT" "$NAME" "$TREE"
  printf 'No other %s trees sit beside it, so this check cannot prove the session is on the newest available plugin (a working checkout and a single-version cache both look like this). Unverified, not clean.\n' "$NAME"
  exit 2
fi

if [[ "$NEWEST_PATH" != "$TREE" ]]; then
  printf 'SKEW: this session is bound to plugin %s, from %s, but the plugin cache also holds %s, at %s.\n' \
    "$CURRENT" "$TREE" "$NEWEST" "$NEWEST_PATH"
  printf 'A session binds its plugin tree at session start, and /reload-plugins rebinds only the session that runs it, so this session cannot act on %s: its skills, templates, and hook bytes are all the %s ones. Restart the session before refreshing or upgrading anything.\n' \
    "$NEWEST" "$CURRENT"
  exit 1
fi

printf 'Plugin %s, from %s. Newest of the %d tree(s) present in the plugin cache, so no session skew.\n' \
  "$CURRENT" "$TREE" "$((EXAMINED + 1))"
if [[ "$UNREADABLE" -gt 0 ]]; then
  printf 'Note: %d neighbouring tree(s) declared no readable version and were not compared.\n' "$UNREADABLE"
fi
exit 0
