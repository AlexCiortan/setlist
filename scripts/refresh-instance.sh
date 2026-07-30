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
  # fail-open-ok: an empty CMP is handled by the *) branch below, which
  # refuses. The error is discarded here so the refusal can name the value.
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

# --- the settings wiring -------------------------------------------------------
#
# The hooks are only half the enforcement layer; the other half is how
# .claude/settings.json WIRES them, and that half is not a stamped file this
# script can copy: it carries the instance's own permissions, model settings,
# and any hooks the project added for itself. Fixes can live entirely in that
# wiring (1.0.3's write-tool matcher and per-hook timeouts both did), so a
# refresh that copied hook bytes and reported success would install neither
# while claiming the instance is current.
#
# READ THE STRUCTURE, NEVER THE TEXT (rewritten in 1.0.4). The 1.0.3 cut of
# this block grepped the file, and grep cannot see JSON. Two defects, both
# found in the field and both reproduced in the suite below:
#   - It counted `grep -c` hits, which counts LINES, not occurrences. Against a
#     minified settings.json (Claude Code rewrites this file when a user
#     toggles config) four command entries carrying one timeout read as
#     "1 and 1", the comparison balanced, and the refresh exited 0 over three
#     untimed hooks. A check that cannot evaluate its predicate passing as
#     clean is backlog item 19 verbatim, inside the block written to enforce it.
#   - It counted EVERY command hook and matched `NotebookEdit` anywhere in the
#     file. A project's own prettier hook with no timeout produced a permanent
#     INCOMPLETE that no edit to Setlist's own wiring could clear, and a
#     foreign hook merely MENTIONING NotebookEdit masked a stale scope matcher.
# jq is guaranteed present here: this script has already refused without it.
# So the checks below address the four entries this plugin owns, identified by
# their command path, and ignore every hook the project added for itself.
SETTINGS="$INSTANCE/.claude/settings.json"
WIRING_GAPS=""
if [[ ! -f "$SETTINGS" ]]; then
  WIRING_GAPS="  .claude/settings.json is missing entirely; the hooks are stamped but nothing runs them."
elif ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  WIRING_GAPS="  .claude/settings.json does not parse as JSON, so the wiring cannot be
  read at all. Fix the file, then re-run: this check does not guess."
else
  # Our own hook entries, identified BY NAME (1.0.7). The 1.0.4 cut selected on
  # the command path containing `.claude/hooks/`, which is the directory the
  # instance keeps ALL of its hooks in, Setlist's four and its own alike. So a
  # project hook living where it belongs was counted as ours: a prettier hook at
  # .claude/hooks/prettier.sh with no timeout produced
  #
  #     these Setlist hook entries carry no explicit "timeout": prettier.sh
  #
  # and a permanent exit 3 that no edit to Setlist's wiring could clear, because
  # Setlist's wiring was already correct. That is the same false positive 1.0.4
  # believed it had fixed, moved one directory deeper: the selector went from
  # "every command hook anywhere" to "every hook in our directory", and the
  # second is still not "our four". Reproduced 2026-07-27 (F23).
  #
  # The four names are the ones this script stamps, so the list cannot drift
  # from what is actually installed.
  # `[.]sh`, not `\.sh`. A backslash here has to survive shell interpolation AND
  # arrive as a valid JSON string escape inside the jq program, and `"\."` is not
  # one: jq rejects the whole program, prints it to stderr, and the command
  # substitution below yields the empty string. That reads as "no untimed
  # entries" and the check passes while not running, which is backlog item 19
  # verbatim, in the same block whose comment above describes item 19. Caught
  # here only because the broken program was echoed where a test could see it.
  # A character class needs no escape and cannot lose one.
# WHAT COUNTS AS ONE OF OURS, tightened 2026-07-28.
#
# Both predicates below used to be `test("/<name>[.]sh")`, a substring match at
# any position in any command string. Two things satisfied it that must not:
#
#   a FORK. `"$CLAUDE_PROJECT_DIR"/.claude/hooks/local/close-gate.sh` is a
#   different file that this script neither stamps nor updates, and with
#   Setlist's own entry deleted the instance was reported CLEAN and --apply
#   said "the refreshed gates bind from the NEXT session onward" about a gate
#   that will never bind. A local fork is not adversarial: this script's own
#   header treats a customized stamped copy as an anticipated fork.
#
#   a MENTION. `echo not-really/commit-gate.sh /close-gate.sh >> audit.log`
#   passed, and the 1.0.8 comment names that exact string as one of the roads
#   it had closed. It had not.
#
# The predicate is now "one of MY four stamped files is what this entry
# EXECUTES": anchored at the command word, the path segment before the filename
# must be exactly `.claude/hooks`, and a deeper path is refused. The `type`
# field is checked too, because an entry that is not a command hook does not run
# a command however its string reads.
#
# This is the same defect as the close gate's: asking whether a name APPEARS
# rather than whether the thing named is the thing that acts.
#
# ANCHORING THE PATTERN WAS NOT ENOUGH (2026-07-29, leg 4 F2). The anchored
# regex above refused the two examples the comment names and not the class,
# because a pattern with `[^ ]*` at each end still asks about SHAPE:
#
#   ANY SUFFIX. `([^ ]*)?` after `[.]sh` accepted `close-gate.sh.disabled`,
#   `close-gate.sh.orig` and `close-gate.shell-wrapper`. Renaming a hook to
#   `.disabled` is precisely how a person turns a gate off, and the instance
#   certified clean, exit 0, "the refreshed gates bind from the NEXT session".
#
#   ANY ROOT. `^[^ ]*` accepted any path ending in `.claude/hooks/<name>.sh`,
#   so a sibling package's gate in a monorepo, `$HOME`'s, or a vendored one
#   under `/opt` all satisfied "MY stamped file is what this entry executes".
#   None of them is the file this script stamps or updates.
#
# So the predicate stops being a pattern. It is now membership in an ENUMERATED
# SET of exact command words: the spellings this script stamps, plus this
# instance's own absolute path. An entry counts when it executes one of those
# and not when it merely looks like it might. A shape test cannot express "the
# file I stamped"; a set of names can.
#
# ours_spellings <hook> -> JSON array of every command word that RUNS the file
# this script stamps at $INSTANCE/.claude/hooks/<hook>.sh.
#
# $CLAUDE_PROJECT_DIR cannot be resolved from here (it is set by the client at
# session start), so its spellings are enumerated rather than expanded. The
# absolute forms are included because an instance may legitimately be wired with
# a literal path, and both quoted and bare forms because both run.
ours_spellings() {
  local h="$1" abs
  abs="$(cd "$INSTANCE" 2>/dev/null && pwd)" || abs="$INSTANCE" # fail-open-ok: an unreadable instance falls back to the given path, and the caller has already refused a missing one
  printf '%s\n' \
    "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/$h.sh" \
    "\${CLAUDE_PROJECT_DIR}/.claude/hooks/$h.sh" \
    "\"\${CLAUDE_PROJECT_DIR}\"/.claude/hooks/$h.sh" \
    "\$CLAUDE_PROJECT_DIR/.claude/hooks/$h.sh" \
    "$abs/.claude/hooks/$h.sh" \
    "\"$abs\"/.claude/hooks/$h.sh" \
    "\"$abs/.claude/hooks/$h.sh\"" \
  | jq -R . | jq -s .
}

# ours_test <hook> -> a jq boolean expression over one hook entry.
#
# The command WORD is the string up to the first space, which is what the shell
# would execute. Whole-string equality is tested too so an instance path
# containing a space still matches when no arguments follow; the combination
# fails CLOSED (reports UNWIRED) rather than open when it cannot tell.
OURS_TEST='
  (.type // "command") == "command"
  and ((.command // "") as $c
       | ($allowed | index($c)) != null
         or ($allowed | index($c | split(" ")[0])) != null)
'
  OURS_ALL="$(for h in $STAMPED_HOOKS; do ours_spellings "$h"; done | jq -s 'add')"
  OURS="[.hooks | to_entries[] | .value[]? | .hooks[]? | select($OURS_TEST)]"

  # THE GATES MUST BE WIRED AT ALL, which nothing here checked until 1.0.7.
  # The block below verified the scope hook's matcher and every entry's timeout,
  # so it could only ever find fault with an entry that was PRESENT. Delete the
  # commit gate and close gate entries outright and there was nothing left to
  # object to: the refresh reported a complete apply, exit 0, and said the
  # refreshed gates would bind from the next session, of a pair of gates that
  # would never bind again. Reproduced 2026-07-27 (F5).
  #
  # This is the seam that carried plugin 1.0.3's worst defect, and an upgrade
  # path that certifies a disarmed instance is worse than no check: it converts
  # "you must verify this yourself" into "this was verified".
  # WIRED MEANS WIRED IN THE RIGHT EVENT, WITH A MATCHER THAT REACHES THE TOOL
  # (1.0.8, F2). The 1.0.7 version of this check tested whether the hook FILENAME
  # appeared as a substring of any command, in any hook event, with no matcher
  # constraint. Three things satisfied it that must not:
  #
  #   - both gates moved from PreToolUse to a Stop hook, where a PreToolUse deny
  #     does nothing at all, and the instance still certified clean
  #   - `echo not-really/commit-gate.sh /close-gate.sh` in an unrelated entry
  #   - a gate wired on a matcher that never names Bash
  #
  # That is grep-enforced rather than meaning-enforced, which is backlog item 26,
  # in a check written to close exactly that class. Both roads were reproduced by
  # hand on 2026-07-27.
  #
  # The 1.0.7 triage note said REVERT rather than patch, and the intent behind
  # that rule is not to leave a broken check limping. This is not a patch over
  # the old test: it is the test the old comment already claimed to be, asserted
  # in both directions. Reverting instead is a one-hunk change if that is
  # preferred, and it costs the ability to notice a disarmed instance at all,
  # which is the property the check was added for.
  #
  # Each stamped hook declares the EVENT it must live in and the TOOL its matcher
  # must reach. A matcher is a regex, so coverage is tested by matching the tool
  # name against it rather than by comparing strings.
  UNWIRED=""
  for h in $STAMPED_HOOKS; do
    case "$h" in
      scope-hook)        ev=PreToolUse;  tool=Write ;;
      commit-gate)       ev=PreToolUse;  tool=Bash ;;
      close-gate)        ev=PreToolUse;  tool=Bash ;;
      regrounding-hook)  ev=SessionStart; tool="" ;;
      *)                 ev=PreToolUse;  tool="" ;;
    esac
    if ! jq -e --arg ev "$ev" --arg tool "$tool" --argjson allowed "$(ours_spellings "$h")" "
          [ (.hooks[\$ev] // [])[]
            | select(any(.hooks[]?; $OURS_TEST))
            | select((\$tool == \"\") or (.matcher as \$m | \$tool | test(\"^(\" + (\$m // \"\") + \")\$\")))
          ] | length > 0" "$SETTINGS" >/dev/null 2>&1; then
      UNWIRED="$UNWIRED $h.sh"
    fi
  done
  if [[ -n "$UNWIRED" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  these Setlist hooks are stamped into .claude/hooks/ but are NOT WIRED IN A WAY
  THAT RUNS THEM:$UNWIRED
  Being present in the file is not the same as being in force: an entry in the
  wrong hook event, or on a matcher that never names the tool it governs, never
  fires. Restore each entry from the plugin's templates/claude/settings.json.tmpl
  (the scope hook on PreToolUse matching Write|Edit|MultiEdit|NotebookEdit, the
  commit and close gates on PreToolUse matching Bash, the re-grounding hook on
  SessionStart), keeping this file's own permissions and model settings."
  fi

  # The scope hook is identified by what its entry EXECUTES, and only ITS
  # matcher is read.
  #
  # This predicate was left as an unanchored substring when its two neighbours
  # above were anchored on 2026-07-28, so a fork at .claude/hooks/local/ or a
  # bare MENTION of the filename still satisfied it and the matcher of a hook
  # that never runs was read as the scope hook's. Fixing the two predicates a
  # finding named and not the third one in the same file is the same
  # stop-at-the-example error as the heading-depth range next door.
  SCOPE_MATCHER="$(jq -r --argjson allowed "$(ours_spellings scope-hook)" "[.hooks.PreToolUse[]?
      | select(any(.hooks[]?; $OURS_TEST))
      | .matcher // \"\"] | first // \"<unwired>\"" "$SETTINGS")"
  if [[ "$SCOPE_MATCHER" == "<unwired>" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  the scope hook is not wired in PreToolUse at all, so the trunk rule never runs."
  elif [[ "$SCOPE_MATCHER" != *NotebookEdit* ]]; then
    WIRING_GAPS="$WIRING_GAPS
  the scope hook's matcher is \"$SCOPE_MATCHER\", which does not cover
  NotebookEdit. Set that entry's matcher to
    \"Write|Edit|MultiEdit|NotebookEdit\"
  or a notebook write reaches the trunk without tripping the scope rule."
  fi

  # Timeouts, on OUR entries only, and the message names each offender.
  UNTIMED="$(jq -r --argjson allowed "$OURS_ALL" "$OURS"' | map(select(.timeout == null))
      | map((.command // "") | split("/") | last | sub("\"$"; ""))
      | join(", ")' "$SETTINGS")"
  if [[ -n "$UNTIMED" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  these Setlist hook entries carry no explicit \"timeout\": $UNTIMED
  A hook the harness cancels is a gate that did not run, verified live on
  Claude Code 2.1.x: a hook exceeding its timeout is dropped and the tool call
  PROCEEDS. The value is in SECONDS. The template ships 120 for the scope
  hook, 300 for the commit gate, 1800 for the close gate (it re-runs your full
  suite), and 60 for the re-grounding hook."
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
# fail-open-ok: cosmetic. A filesystem that refuses the mode bit does not
# make the copied hook bytes wrong, and the hooks are invoked via bash.
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
