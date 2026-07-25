#!/usr/bin/env bash
# Refresh an existing instance's stamped enforcement files from this plugin
# tree, with direction. Replaces the byte comparison the upgrade skill used to
# describe in prose, which could not tell newer from older and so could reinstall
# older hooks over newer ones while reporting success (backlog item 21).
#
# Usage:
#   refresh-instance.sh <instance-dir>            report what would change
#   refresh-instance.sh --apply <instance-dir>    perform the refresh
#
# The default is a report because a stamped copy that differs may be a fork the
# instance made deliberately, and Part 8c is explicit that a customized stamped
# copy is a fork to surface, never a file to silently overwrite. The reporting
# run gives the upgrade session the file list to diff before it commits to
# anything.
#
# What this refuses, and why refusal rather than a best guess (backlog item 19:
# a check that cannot evaluate its predicate denies and says why, and never
# falls through):
#   - the plugin's own version is undeterminable
#   - jq is absent, so the instance's recorded version cannot be read
#   - .claude/sdd.json is absent or does not parse
#   - sdd.json records a version this script cannot read
#   - the recorded version is NEWER than this plugin's (the downgrade case)
#   - a newer tree of this same plugin sits in the cache, meaning this session
#     is stale and its hook bytes are the old ones (--apply only)
# An instance that records no version at all is NOT a refusal: it was stamped
# before the field existed, which is a move forward by definition, and refusing
# would strand exactly the instances this release is meant to repair.
#
# Exit codes:
#   0  the refresh reported, or applied completely
#   1  a refusal (any of the conditions above); nothing was copied
#   3  applied INCOMPLETELY (1.0.3): the hook bytes and the version record are
#      current, but .claude/settings.json still needs a hand edit named in the
#      output. This script does not rewrite that file, because it holds the
#      instance's own permissions and model settings next to the hook block.
#      Part of what the new version promises is not in force until the edit
#      lands, and an incomplete refresh must not exit 0 and read as a finished
#      one: that is the same "reports success, layer is weaker" shape the
#      whole release exists to remove.

set -u

die() { printf '%s\n' "refresh-instance.sh: $*" >&2; exit 1; }

APPLY=no
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=yes
  shift
fi
[[ $# -eq 1 ]] || die "usage: refresh-instance.sh [--apply] <instance-dir>"
INSTANCE="$1"
[[ -d "$INSTANCE" ]] || die "not a directory: $INSTANCE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS="$ROOT/templates/hooks"
[[ -d "$HOOKS" ]] || die "templates/hooks/ not found at the plugin root ($ROOT)"

PLUGIN_VERSION="$(bash "$SCRIPT_DIR/plugin-version.sh" "$ROOT")" \
  || die "refusing to refresh: this plugin's own version is undeterminable, so the direction of the move cannot be established"

SDD="$INSTANCE/.claude/sdd.json"
[[ -f "$SDD" ]] || die "refusing to refresh: no .claude/sdd.json at $INSTANCE, so this is not a framework instance (or its config is missing)"

command -v jq >/dev/null 2>&1 \
  || die "refusing to refresh: jq is not installed, so the version recorded in .claude/sdd.json cannot be read and a downgrade would be indistinguishable from an upgrade. Install jq, then retry."

jq -e . "$SDD" >/dev/null 2>&1 \
  || die "refusing to refresh: $SDD does not parse as JSON, so the recorded plugin version cannot be read. Fix the file, then retry."

RECORDED="$(jq -r '.plugin.version // empty' "$SDD")"

# --- direction ----------------------------------------------------------------

if [[ -z "$RECORDED" ]]; then
  DIRECTION=forward
  FROM="none recorded (stamped before the plugin version was recorded)"
else
  FROM="$RECORDED"
  CMP="$(bash "$SCRIPT_DIR/plugin-version.sh" --compare "$PLUGIN_VERSION" "$RECORDED" 2>/dev/null || true)"
  case "$CMP" in
    newer) DIRECTION=forward ;;
    same)  DIRECTION=same ;;
    older)
      die "refusing to refresh: this would move the instance BACKWARDS. The instance records plugin $RECORDED; this plugin tree is $PLUGIN_VERSION. Refreshing would reinstall the older enforcement files over the newer ones and report success. If the older plugin is genuinely the one you want, say so deliberately by editing .plugin.version in $SDD first."
      ;;
    *)
      die "refusing to refresh: $SDD records a plugin version this script cannot read ('$RECORDED'), so the direction of the move cannot be established. Correct the value, then retry."
      ;;
  esac
fi

# --- session skew --------------------------------------------------------------

SKEW_OUT="$(bash "$SCRIPT_DIR/plugin-skew.sh" "$ROOT" 2>&1)"
SKEW_RC=$?
if [[ "$SKEW_RC" -eq 1 && "$APPLY" == "yes" ]]; then
  printf '%s\n' "$SKEW_OUT" >&2
  die "refusing to refresh: this session is not bound to the newest plugin tree present in the cache, so it would install the older hook bytes and report an upgrade. Restart the session, then retry."
fi

# --- the four stamped enforcement files ------------------------------------------

STAMPED_HOOKS="scope-hook commit-gate close-gate regrounding-hook"
CHANGED=""
SAME=""
NEW=""
for h in $STAMPED_HOOKS; do
  dest="$INSTANCE/.claude/hooks/$h.sh"
  if [[ ! -f "$dest" ]]; then
    NEW="$NEW $h.sh"
  elif cmp -s "$HOOKS/$h.sh" "$dest"; then
    SAME="$SAME $h.sh"
  else
    CHANGED="$CHANGED $h.sh"
  fi
done

# --- the settings wiring (1.0.3) ---------------------------------------------
#
# The hooks are only half the enforcement layer; the other half is how
# .claude/settings.json WIRES them, and that half is not a stamped file this
# script can copy: it carries the instance's own permissions and model
# settings alongside the hook block. Two 1.0.3 fixes live entirely in that
# wiring (the write-tool matcher set, and the explicit per-hook timeouts), so
# a refresh that copied hook bytes and reported success would have installed
# neither while saying the instance is on 1.0.3. That is the exact failure
# this release exists to remove, so the wiring is checked, named, and allowed
# to fail the refresh rather than being silently skipped.
SETTINGS="$INSTANCE/.claude/settings.json"
WIRING_GAPS=""
if [[ ! -f "$SETTINGS" ]]; then
  WIRING_GAPS="  .claude/settings.json is missing entirely; the hooks are stamped but nothing runs them."
else
  if ! grep -q 'NotebookEdit' "$SETTINGS"; then
    WIRING_GAPS="$WIRING_GAPS
  the scope hook's matcher does not cover NotebookEdit. Set it to
    \"matcher\": \"Write|Edit|MultiEdit|NotebookEdit\"
  or a notebook write reaches the trunk without tripping the scope rule."
  fi
  # grep -c PRINTS 0 and EXITS 1 when it matches nothing, so a `|| printf 0`
  # fallback appends a second zero and the comparison below becomes a bash
  # syntax error, which evaluates false and passes the check silently. That is
  # this release's own defect class inside the check that hunts for it; the
  # suite caught it. Take grep's output, and only default when it is empty.
  HOOK_ENTRIES="$(grep -c '"type": *"command"' "$SETTINGS" 2>/dev/null || true)"
  TIMEOUT_KEYS="$(grep -c '"timeout"' "$SETTINGS" 2>/dev/null || true)"
  [[ -n "$HOOK_ENTRIES" ]] || HOOK_ENTRIES=0
  [[ -n "$TIMEOUT_KEYS" ]] || TIMEOUT_KEYS=0
  if [[ "$HOOK_ENTRIES" -gt 0 && "$TIMEOUT_KEYS" -lt "$HOOK_ENTRIES" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  $HOOK_ENTRIES command hooks are wired but only $TIMEOUT_KEYS carry an explicit
  \"timeout\". A hook the harness cancels is a gate that did not run; the close
  gate re-runs the full suite and needs the most room (the template ships 1800)."
  fi
fi

printf 'refresh-instance.sh: plugin %s -> instance recorded %s (%s)\n' "$PLUGIN_VERSION" "$FROM" "$DIRECTION"
printf '%s\n' "$SKEW_OUT"
[[ -n "$NEW" ]]     && printf '  missing, would be stamped:%s\n' "$NEW"
[[ -n "$CHANGED" ]] && printf '  bytes differ, would be replaced:%s\n' "$CHANGED"
[[ -n "$SAME" ]]    && printf '  already byte-identical:%s\n' "$SAME"
if [[ -n "$WIRING_GAPS" ]]; then
  printf 'settings wiring, NOT refreshed by this script (it holds your own permissions and model settings):%s\n' "$WIRING_GAPS"
fi

if [[ "$APPLY" != "yes" ]]; then
  if [[ -n "$CHANGED" ]]; then
    printf 'Report only. Diff each differing file against the plugin template before applying: a deliberate instance edit is a fork to surface in the umbrella ADR, not a file to overwrite in silence.\n'
  fi
  printf 'Re-run with --apply to perform the refresh and record plugin %s in the instance.\n' "$PLUGIN_VERSION"
  exit 0
fi

mkdir -p "$INSTANCE/.claude/hooks"
for h in $STAMPED_HOOKS; do
  cp "$HOOKS/$h.sh" "$INSTANCE/.claude/hooks/$h.sh"
done
chmod +x "$INSTANCE/.claude/hooks/"*.sh 2>/dev/null || true

# Record the stamping version. Written last, so a failed copy never leaves an
# instance claiming a version whose bytes it does not carry.
TMP="$SDD.refresh.$$"
if ! jq --arg v "$PLUGIN_VERSION" '.plugin = ((.plugin // {}) + {version: $v})' "$SDD" > "$TMP"; then
  rm -f "$TMP"
  die "the hooks were refreshed but recording the plugin version in $SDD failed; record .plugin.version = \"$PLUGIN_VERSION\" by hand before closing"
fi
mv "$TMP" "$SDD"

printf 'refresh-instance.sh: refreshed the four stamped hooks and recorded plugin %s in %s\n' "$PLUGIN_VERSION" "$SDD"
printf 'Hooks load at session start, so the refreshed gates bind from the NEXT session onward.\n'

# An INCOMPLETE refresh must not read as a finished one. The hook bytes are
# current and the version is recorded, but if the wiring above is stale then
# part of what this version promises is not in force, and the operator has to
# know that from the exit status, not from reading past a success line.
if [[ -n "$WIRING_GAPS" ]]; then
  printf '\nINCOMPLETE: the hooks are current but .claude/settings.json still needs the edit(s) named above.\n' >&2
  printf 'Make them by hand (the file carries your own settings, so this script will not rewrite it), then re-run to confirm.\n' >&2
  exit 3
fi
