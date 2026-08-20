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

# --- the GIT hooks, the enforcement boundary as of edition v1.7 -----------------
#
# THIS BLOCK EXISTS BECAUSE ITS ABSENCE WAS A BLOCKER, found by the v1.7 dogfood
# gate. The four files above are the ADVISORY layer now; the guarantee lives in
# git hooks stamped into a tracked .githooks/ plus two git config settings. This
# script knew nothing about them, so an UPGRADED instance recorded plugin 1.1.0,
# reported its hooks current, and had no boundary at all, while a freshly stamped
# one did. That is plugin 1.0.3's defect exactly (the refresh copied what it knew
# about and reported success while the headline mechanism stayed inert), and it
# was worse this time: v1.7 also DEMOTES the advisory layer, so an upgraded
# instance would have been strictly weaker than before the upgrade while being
# told it was current.
GIT_HOOK_FILES="pre-commit pre-merge-commit pre-push"
GIT_HOOK_LIB="setlist-hook-lib.sh"
GITHOOKS_SRC="$ROOT/templates/git-hooks"
GH_CHANGED=""; GH_SAME=""; GH_NEW=""
for h in $GIT_HOOK_FILES $GIT_HOOK_LIB; do
  dest="$INSTANCE/.githooks/$h"
  if [[ ! -f "$dest" ]]; then
    GH_NEW="$GH_NEW $h"
  elif cmp -s "$GITHOOKS_SRC/$h" "$dest"; then
    GH_SAME="$GH_SAME $h"
  else
    GH_CHANGED="$GH_CHANGED $h"
  fi
done
# A FOREIGN HOOKS LAYER IS NOT AN UNSET ONE (leg F8). `git config
# core.hooksPath .githooks` ran unconditionally, and where a repository already
# pointed that at husky, lefthook or pre-commit the previous value was not
# printed, not recorded and not backed up. Report mode said "git config still to
# set: core.hooksPath" while it WAS set, to something this run was about to
# switch off. Measured: the identical `git commit` was refused by
# .husky/pre-commit before the refresh and committed cleanly after it.
#
# What gets displaced is frequently itself a control: gitleaks, detect-secrets
# and commit-msg validation are commonly wired exactly this way, so the failure
# is a project losing its secret scanning to a tool that arrived offering
# guarantees. git supports ONE hooksPath, so merging the layers is not on the
# table; the defect is that the displacement was invisible, not that it happens.
# THE OWNERSHIP RULE LIVES IN setlist-delivery-lib.sh, NOT HERE (B2, 2026-08-13).
# It used to be defined inline; stamp.sh then needed the identical rule and a
# second copy is how `slh_role_paths` drifted, so the definition moved to the
# shared library and both delivery scripts source it. The full reasoning,
# including the F6 name-versus-content lesson, travels with the function.
#
# Sourcing FAILS CLOSED: a guard that silently fails to load is a guard that
# silently stops guarding, which is R3-1's shape one layer up.
[[ -f "$SCRIPT_DIR/setlist-delivery-lib.sh" ]] \
  || die "scripts/setlist-delivery-lib.sh is missing, so the hook-layer ownership rule cannot be loaded and a foreign core.hooksPath could be displaced silently. Refusing to continue."
# shellcheck source=/dev/null
source "$SCRIPT_DIR/setlist-delivery-lib.sh"
declare -f hooks_layer_is_ours >/dev/null \
  || die "setlist-delivery-lib.sh loaded but hooks_layer_is_ours is not defined; refusing to run with the displacement guard absent."
FOREIGN_HOOKSPATH="$(foreign_hookspath "$INSTANCE")"
# The boundary-skip decision is computed HERE, before the report, so report
# mode and apply mode describe the same future (round 5, finding 2: the report
# promised four files and two config writes that apply then skipped). Two
# skip states, both loud:
#   - below the worktree top (round 4, finding 6)
#   - a LINKED worktree (round 5, finding 4): core.hooksPath lives in the
#     SHARED config, so arming from here would repoint the MAIN worktree's
#     hooks; the guard resolved the value against the linked top and saw
#     nothing, which is how a husky layer in the main worktree was displaced.
GITHOOKS_SKIP_NOTE=""
if git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  INSTANCE_TOP="$(git -C "$INSTANCE" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: emptiness lands in the mismatch branch below and skips the arm, never performs it blind
  INSTANCE_REAL="$(cd "$INSTANCE" 2>/dev/null && pwd -P)"
  GIT_DIR_HERE="$(git -C "$INSTANCE" rev-parse --git-dir 2>/dev/null || true)"       # fail-open-ok: both empty compares equal and the linked test stays quiet; the worktree-top test above still governs
  GIT_COMMON_HERE="$(git -C "$INSTANCE" rev-parse --git-common-dir 2>/dev/null || true)" # fail-open-ok: same
  if [[ -z "$INSTANCE_TOP" || "$INSTANCE_REAL" != "$INSTANCE_TOP" ]]; then
    GITHOOKS_SKIP_NOTE="this instance ($INSTANCE_REAL) sits BELOW the top of its git working tree ($INSTANCE_TOP); git resolves core.hooksPath at the top, so a boundary delivered here would be inert or would displace the parent repository's layer. The git-hook boundary was NOT touched. Make the instance its own repository, or run Setlist from the worktree top."
  elif [[ -n "$GIT_DIR_HERE" && -n "$GIT_COMMON_HERE" && "$GIT_DIR_HERE" != "$GIT_COMMON_HERE" ]]; then
    GITHOOKS_SKIP_NOTE="this instance is a LINKED worktree; core.hooksPath lives in the shared config, so arming from here would repoint the MAIN worktree's hooks (and the guard cannot see that worktree's layer from here). The git-hook boundary was NOT touched. Arm from the main worktree."
  fi
fi

GH_CFG_NEEDED=""
if [[ "$(git -C "$INSTANCE" config --get core.hooksPath 2>/dev/null || true)" != ".githooks" ]]; then  # fail-open-ok: this read DETECTS what needs setting rather than deciding anything; an unreadable config yields the empty string, which does not equal the wanted value, so the setting is reported as needed and then SET below, failing toward doing the work
  GH_CFG_NEEDED="$GH_CFG_NEEDED core.hooksPath"
fi
if [[ "$(git -C "$INSTANCE" config --get merge.ff 2>/dev/null || true)" != "false" ]]; then  # fail-open-ok: same as above, the read only detects; an unreadable value is not "false" so merge.ff is reported as needed and then set
  GH_CFG_NEEDED="$GH_CFG_NEEDED merge.ff"
fi

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
# THE GIT-HOOK BOUNDARY IS REPORTED TOO (1.1.0 leg, fourth run, F21).
#
# GH_NEW, GH_CHANGED and GH_CFG_NEEDED were computed a hundred lines above and
# then never printed, so report mode said nothing whatever about the layer v1.7
# made the guarantee. A 1.0.9 instance with NO boundary at all read "already
# byte-identical: <the four advisory hooks>" and "Re-run with --apply", which is
# a true sentence about the wrong layer and reads as an all-clear. The operator
# deciding whether to apply could not see that the thing they were deciding about
# was missing entirely.
# trunk-audit.sh IS A DELIVERED FILE (leg F12), and appeared in no report. An
# operator deciding whether to apply should see every file that would be
# written, and this one is 700 lines that can land on a same-named foreign
# script. Reported here rather than delivered in silence.
TA_DEST="$INSTANCE/.claude/hooks/trunk-audit.sh"
TA_NOTE=""
if [[ -f "$ROOT/scripts/trunk-audit.sh" ]]; then
  if [[ ! -f "$TA_DEST" ]]; then TA_NOTE="missing, would be delivered"
  elif ! cmp -s "$ROOT/scripts/trunk-audit.sh" "$TA_DEST"; then TA_NOTE="bytes differ, would be REPLACED"
  fi
fi
[[ -n "$TA_NOTE" ]] && printf '  .claude/hooks/trunk-audit.sh: %s\n' "$TA_NOTE"
# The displacement warning is printed WHENEVER apply would refuse, not only
# when boundary files also happen to differ (round 9, finding 3: a current
# boundary behind an unreadable directory reported "present and
# byte-identical, config already set" while apply refused).
if [[ -n "$FOREIGN_HOOKSPATH" && -z "$GITHOOKS_SKIP_NOTE" && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]]; then
  printf 'the git-hook boundary: --apply will REFUSE: a hook layer that is not Setlist'"'"'s (or cannot be verified) runs from, or would be switched on at, %s.\n' "$FOREIGN_HOOKSPATH"
fi
if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
  printf 'the git-hook boundary: NOT ARMED here and will not be: %s\n' "$GITHOOKS_SKIP_NOTE"
elif [[ -n "$GH_NEW" || -n "$GH_CHANGED" || -n "$GH_CFG_NEEDED" ]]; then
  printf 'the git-hook boundary (this is the layer that carries the guarantee):\n'
  [[ -n "$GH_NEW" ]]     && printf '  missing, would be delivered:%s\n' "$GH_NEW"
  [[ -n "$GH_CHANGED" ]] && printf '  bytes differ, would be replaced (the previous file is kept as .setlist-backup):%s\n' "$GH_CHANGED"
  [[ -n "$GH_CFG_NEEDED" ]] && printf '  git config still to set:%s   (without BOTH of these the hooks are inert)\n' "$GH_CFG_NEEDED"
  if [[ -n "$FOREIGN_HOOKSPATH" ]]; then
    printf '  WOULD DISPLACE ANOTHER HOOK LAYER: hooks that are not Setlist%ss already run from %s\n' "'" "$FOREIGN_HOOKSPATH"
    printf '    git runs one hook layer, so arming Setlist here SWITCHES THAT OFF. This is\n'
    printf '    true whether core.hooksPath points there or it is the default .git/hooks\n'
    printf '    (where pre-commit and lefthook install themselves with hooksPath unset).\n'
    printf '    Whatever runs from %s stops running: often gitleaks, detect-secrets\n' "$FOREIGN_HOOKSPATH"
    printf '    or commit-msg validation. --apply REFUSES rather than do this silently.\n'
    printf '    Decide deliberately: move those checks into %s/, or re-run with\n' ".githooks"
    printf '    SETLIST_ADOPT_HOOKSPATH=1 to displace %s on purpose.\n' "$FOREIGN_HOOKSPATH"
  fi
else
  printf 'the git-hook boundary: present and byte-identical, config already set.\n'
fi
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

# THE REFUSAL COMES BEFORE THE FIRST WRITE, AND "FIRST" MEANS FIRST (second
# 2.0.0 leg, F5, the same lesson's third telling). The F6 second-order fix
# hoisted this refusal above the .githooks copy loop and left it inside that
# block, seventy lines BELOW the four .claude/hooks session-gate copies, so a
# refusing --apply performed four unbacked writes and then printed "Nothing
# has been changed", a sentence that has to be true when it prints. Every
# input this decision needs (FOREIGN_HOOKSPATH, the override, the work-tree
# test) is known before any write, so the decision now sits at the top of
# apply mode, above everything, and the suite asserts the CLASS generically:
# a run that ends in this refusal leaves the whole instance snapshot-identical.
# THE BOUNDARY LIVES AT THE WORKTREE TOP OR NOWHERE (adversary round 3,
# finding 5). git resolves core.hooksPath against the top of the working
# tree, so an instance in a SUBDIRECTORY would have its .githooks delivered
# where git never looks and core.hooksPath pointed where nothing was
# delivered: an inert boundary under a success message, which is R3-1's
# shape verbatim. Refusing is the truth: per-subdirectory git hooks do not
# exist in git.
# Round 4, finding 6, softened the first cut: a hard die here also blocked
# the four ADVISORY .claude/hooks copies, which have nothing to do with
# core.hooksPath, so a subdirectory instance could never receive even a
# session-gate update and report mode promised a refresh that apply then
# refused. The boundary half is SKIPPED, loudly, with the reason; the
# advisory half proceeds; the run exits 3 because part of what this version
# promises is not in force here.

if [[ -n "$FOREIGN_HOOKSPATH" && -z "$GITHOOKS_SKIP_NOTE" && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]] \
   && git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$INSTANCE" "$FOREIGN_HOOKSPATH")" 2>/dev/null | tr '\n' ' ')"
    die "refusing to arm: a hook layer that is not Setlist's already runs from, or would be switched on at, $FOREIGN_HOOKSPATH (foreign: ${FOREIGN_HOOK_NAMES:-unresolvable}), and git runs one layer: arming Setlist (core.hooksPath=.githooks) would switch it off, silently taking whatever runs from $FOREIGN_HOOKSPATH with it (gitleaks, detect-secrets and commit-msg validation are commonly wired this way, and pre-commit and lefthook wire into .git/hooks with hooksPath unset). Nothing has been changed. Move those checks into .githooks/, or re-run with SETLIST_ADOPT_HOOKSPATH=1 to displace $FOREIGN_HOOKSPATH on purpose."
fi

# The boundary directory must be a real directory in the repository, not a
# symlink git would resolve to write the boundary outside it (round 11,
# findings 1 and 5). Checked before the first write, on both delivery paths.
BOUNDARY_UNSAFE="$(setlist_boundary_dir_unsafe "$INSTANCE" 2>/dev/null)"
[[ -z "$BOUNDARY_UNSAFE" ]] || die "refusing to arm: $BOUNDARY_UNSAFE Nothing has been changed."

# THE SAME CLASS AS THE GIT-HOOK COPIES BELOW (F1 sweep). A failed copy here
# leaves the PREVIOUS session gate in place, which is a working file, so nothing
# downstream notices and the summary reports the hooks refreshed.
#
# THE REFUSAL COMES BEFORE THE FIRST WRITE, here too (leg F1, the 2026-08
# consolidation). These copies are the first writes of apply mode, and the loop
# was a bare cp: a symlink at .claude/hooks/close-gate.sh had cp resolve it and
# write the shipped gate OVER the linked file, outside the instance, with no
# backup, under the "refreshed the four stamped hooks" success line, while the
# .githooks/ loop sixty lines down has refused this exact shape for three
# rounds. Every advisory destination is checked before the first one is
# written, so this refusal can still say "Nothing has been changed" and mean it.
for h in $STAMPED_HOOKS trunk-audit; do
  ADV_UNSAFE="$(setlist_deliver_dest_unsafe "$INSTANCE" ".claude/hooks/$h.sh" 2>/dev/null)"
  [[ -z "$ADV_UNSAFE" ]] || die "refusing to refresh: $ADV_UNSAFE Nothing has been changed."
done
mkdir -p "$INSTANCE/.claude/hooks" \
  || die "could not create .claude/hooks in $INSTANCE; nothing was refreshed."
for h in $STAMPED_HOOKS; do
  ADV_NOTE="$(setlist_deliver_file "$HOOKS/$h.sh" "$INSTANCE" ".claude/hooks/$h.sh")" \
    || die "could not refresh .claude/hooks/$h.sh: ${ADV_NOTE:-the copy failed} Nothing has been recorded, so re-run once the cause is fixed."
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s' "$ADV_NOTE"
done
# fail-open-ok: cosmetic. A filesystem that refuses the mode bit does not
# make the copied hook bytes wrong, and the hooks are invoked via bash.
# NAMED, NOT GLOBBED (leg F12). This was `.claude/hooks/`*.sh, which flips the
# mode on every foreign script sitting in that directory: measured, a project's
# own prettier.sh went 644 -> 755. Only the files this loop just copied are
# ours to chmod.
for h in $STAMPED_HOOKS; do
  chmod +x "$INSTANCE/.claude/hooks/$h.sh" 2>/dev/null || true # fail-open-ok: cosmetic, the hooks are invoked via bash
done

# The git hooks and their two config settings. Both halves, because either alone
# is inert: the hooks without core.hooksPath are never invoked, and the config
# without merge.ff leaves the fast-forward path (which fires no hook at all) wide
# open.
# deliver() reports a failed write with its command and stderr and dies with
# the partial-state summary; hoisted to top level in round 6 when the
# trunk-audit delivery moved above the gated boundary block that used to
# define it.
deliver() { # deliver <what> <cmd...>
  local what="$1"; shift
  local err rc
  err="$("$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '\nrefresh-instance.sh: %s FAILED (exit %s)\n' "$what" "$rc" >&2
    printf '  command: %s\n' "$*" >&2
    [[ -n "$err" ]] && printf '  stderr:  %s\n' "$err" >&2
    printf '\nPARTIAL APPLICATION. What is true right now:\n' >&2
    printf '  - .githooks/ %s\n' "${DELIVERED_HOOKS:-was NOT updated}" >&2
    printf '  - core.hooksPath and merge.ff %s\n' "${DELIVERED_CFG:-were NOT set, so any hooks present are INERT}" >&2
    printf '  - .claude/sdd.json still records the PREVIOUS plugin version, deliberately:\n' >&2
    printf '    an instance must never claim a version whose boundary it does not carry.\n' >&2
    printf '\nFix the cause above and re-run; this script is idempotent.\n' >&2
    exit 1
  fi
}

# trunk-audit.sh lives in .claude/hooks and has nothing to do with
# core.hooksPath, so it is delivered with the ADVISORY half (round 6, finding
# 3): in a linked worktree the shared config keeps the boundary LIVE, the
# report promised this file, and the gated block below skipped it, after
# which every push was refused for want of the tool.
if [[ -f "$ROOT/scripts/trunk-audit.sh" ]]; then
  mkdir -p "$INSTANCE/.claude/hooks" # fail-open-ok: the guarded delivery on the next line fails if this did, and names the file the operator actually cares about
  # Through the one write rule (2026-08 consolidation): the destination was
  # checked in the pre-write pass above, and the delivery backs up a differing
  # file with a named backup instead of replacing 700 lines in silence.
  ADV_NOTE="$(setlist_deliver_file "$ROOT/scripts/trunk-audit.sh" "$INSTANCE" ".claude/hooks/trunk-audit.sh")" \
    || die "could not deliver trunk-audit.sh to .claude/hooks/: ${ADV_NOTE:-the copy failed} pre-push would refuse every push outside a Claude Code session."
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s' "$ADV_NOTE"
  [[ -f "$INSTANCE/.claude/hooks/trunk-audit.sh" ]] || die "could not deliver trunk-audit.sh to .claude/hooks/; pre-push would refuse every push outside a Claude Code session."
fi

if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
  printf '\nrefresh-instance.sh: git-hook boundary NOT ARMED: %s\n' "$GITHOOKS_SKIP_NOTE" >&2
elif [[ -d "$GITHOOKS_SRC" ]]; then
  mkdir -p "$INSTANCE/.githooks" # fail-open-ok: a directory that could not be created makes the guarded copy below fail, and THAT failure is the one with the diagnostic worth printing; checking here would report the same problem twice in a less useful place
  # A DIFFERING GIT HOOK IS BACKED UP, NOT DESTROYED (1.1.0 leg, fourth run, F20).
  #
  # This loop overwrote .githooks/* unconditionally and said nothing before or
  # after, so a project's own pre-commit, or a deliberate fork of the stamped
  # one, was gone with no record and no way back. The four ADVISORY hooks have
  # had fork discipline for releases; the git hooks, which are the layer v1.7
  # made the guarantee, had none.
  #
  # Backed up rather than refused, because refusing would leave the boundary
  # un-refreshed and this script's whole job is delivering it. The backup is
  # NAMED on stdout, since a backup nobody is told about is the same data loss
  # one directory over.
  # A DELIVERY THAT COULD NOT DELIVER HAS NOT DELIVERED (F1, verdict leg).
  #
  # This block used to run its copies and its two `git config` writes and read
  # none of their exit statuses. A failed write therefore printed "delivered the
  # git-hook boundary", recorded the new plugin version, and exited 0 over an
  # instance whose guarantee layer was entirely inert. That is worse than a
  # silent failure: it is a positive claim of delivery that was never checked,
  # and the operator has no reason to look again.
  #
  # The failing command and its stderr are NAMED, because "refresh failed" sends
  # someone to the wrong place. The partial state is named too, because an apply
  # that dies halfway leaves a real instance in a real condition and the next
  # action depends on which half ran.

  # The displacement refusal used to live here (leg F6, second order), which
  # put it above the .githooks copies and BELOW the .claude/hooks copies, the
  # exact half-measure the second 2.0.0 leg priced as F5. It now fires at the
  # TOP of apply mode, before any write at all; see the comment there.

  for h in $GIT_HOOK_FILES $GIT_HOOK_LIB; do
    HOOK_DEST_UNSAFE="$(setlist_hook_dest_unsafe "$INSTANCE/.githooks/$h" 2>/dev/null)"
    [[ -z "$HOOK_DEST_UNSAFE" ]] || die "refusing to arm: $INSTANCE/.githooks/$HOOK_DEST_UNSAFE Nothing further was changed."
    if [[ -L "$INSTANCE/.githooks/$h" && ! -e "$INSTANCE/.githooks/$h" ]]; then
      # Dangling link: -f is false, so the branch below never fires, and the
      # copy loop's cp would resolve the link and write our hook body at the
      # repository's chosen path (round 9, finding 1). Remove it and say so.
      deliver "removing the dangling symlink at .githooks/$h" rm -f "$INSTANCE/.githooks/$h"
      printf 'refresh-instance.sh: .githooks/%s was a DANGLING symlink; it was removed and a regular file takes its place. Nothing was written at the link target.\n' "$h"
    fi
    if [[ -f "$INSTANCE/.githooks/$h" ]] && ! cmp -s "$GITHOOKS_SRC/$h" "$INSTANCE/.githooks/$h"; then
      GH_BACKUP="$INSTANCE/.githooks/$h.setlist-backup"
      # THE BACKUP PATH IS A DESTINATION TOO (2026-08 consolidation, second
      # adversary round). The advisory writer learned this one directory over:
      # a symlink pre-placed at the .setlist-backup sibling has the backup cp
      # RESOLVE it and write the old hook body over whatever it points at,
      # outside the instance, under a "kept at .setlist-backup" message that is
      # then false. Reachable here on the adopt path. The link is removed (its
      # target untouched), matching this loop's own symlink-at-the-hook-path
      # handling below, so a real backup takes its place.
      if [[ -L "$GH_BACKUP" ]]; then
        deliver "removing the symlink at .githooks/$h.setlist-backup" rm -f "$GH_BACKUP"
        printf 'refresh-instance.sh: .githooks/%s.setlist-backup was a symlink; it was removed (its target untouched) and a real backup takes its place.\n' "$h"
      fi
      deliver "backing up the previous .githooks/$h" cp "$INSTANCE/.githooks/$h" "$GH_BACKUP"
      if [[ -L "$INSTANCE/.githooks/$h" ]]; then
        # cp follows a symlink and would overwrite the linked file OUTSIDE
        # the boundary (round 8, finding 3); the link goes, its target stays.
        deliver "removing the symlink at .githooks/$h" rm -f "$INSTANCE/.githooks/$h"
        printf 'refresh-instance.sh: .githooks/%s was a symlink; it becomes a regular file and the linked script was NOT touched.\n' "$h"
      fi
      printf 'refresh-instance.sh: .githooks/%s differed from the shipped hook; the previous file is kept at .githooks/%s.setlist-backup\n' "$h" "$h"
    fi
    # A FAILED COPY LEAVES THE OLD FILE, which is still executable, so the
    # executability loop below would pass over stale bytes and report them
    # delivered. The copy's own status is the only thing that distinguishes
    # "refreshed" from "unchanged and claimed refreshed".
    deliver "installing .githooks/$h" cp "$GITHOOKS_SRC/$h" "$INSTANCE/.githooks/$h"
  done
  DELIVERED_HOOKS="was updated from the shipped templates"
  chmod +x "$INSTANCE/.githooks/pre-commit" "$INSTANCE/.githooks/pre-merge-commit" "$INSTANCE/.githooks/pre-push" 2>/dev/null || true  # fail-open-ok: the chmod's own status is discarded because the loop immediately below DIES unless every git hook is actually executable, so a filesystem that refused the bit is caught by the test rather than by this exit code
  # NOT cosmetic, unlike the chmod above: git skips a non-executable hook
  # SILENTLY, so an unexecutable pre-merge-commit is a boundary that stops
  # nothing and says nothing.
  for h in $GIT_HOOK_FILES; do
    [[ -x "$INSTANCE/.githooks/$h" ]] || die "refreshed .githooks/$h but it is not executable; git would skip it in silence. Fix the mode, then re-run."
  done
  # THE HOOK'S OWN TOOL SHIPS WITH THE HOOK (v1.7 gate session 4, leg F2).
  #
  # pre-push resolves trunk-audit.sh from $CLAUDE_PLUGIN_ROOT/scripts/ or from
  # .claude/hooks/trunk-audit.sh, and nothing had ever installed the second. The
  # first is unset in any ordinary terminal, so a stamped instance refused every
  # push from outside a Claude Code session with "cannot find trunk-audit.sh".
  # Delivering a hook without the tool it runs delivers a boundary that can only
  # fail, which is the same defect class as delivering hooks with no hooksPath.
  if git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # The displacement refusal now fires BEFORE the copy loop above, so by the
    # time control reaches here either there was nothing foreign to displace or
    # the operator asked for it with SETLIST_ADOPT_HOOKSPATH=1.
    deliver "setting core.hooksPath" git -C "$INSTANCE" config core.hooksPath .githooks
    deliver "setting merge.ff"        git -C "$INSTANCE" config merge.ff false
    # Read BACK rather than trusting the writes: a config that reports success
    # and does not hold the value delivers the same inert boundary.
    [[ "$(git -C "$INSTANCE" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
      || die "core.hooksPath was written without error but does not read back as .githooks, so the hooks would be inert. Check for a conflicting include or a repository-level override."
    [[ "$(git -C "$INSTANCE" config --get merge.ff 2>/dev/null)" == "false" ]] \
      || die "merge.ff was written without error but does not read back as false, so a fast-forward merge would bypass pre-merge-commit."
    DELIVERED_CFG="are set and read back correctly"
  else
    printf 'WARNING: %s is not a git work tree, so core.hooksPath and merge.ff were NOT set.\n' "$INSTANCE" >&2
    printf '         The git hooks are copied but INERT until those two settings exist.\n' >&2
  fi
fi

# Record the stamping version. Written last, so a failed copy never leaves an
# instance claiming a version whose bytes it does not carry.
TMP="$SDD.refresh.$$"
if ! jq --arg v "$PLUGIN_VERSION" '.plugin = ((.plugin // {}) + {version: $v})' "$SDD" > "$TMP"; then
  rm -f "$TMP"
  die "the hooks were refreshed but recording the plugin version in $SDD failed; record .plugin.version = \"$PLUGIN_VERSION\" by hand before closing"
fi
# The version is only recorded if the file really moved. A failed mv here would
# leave the OLD sdd.json in place while the summary below announces the new
# version, which is the F1 shape one statement further on.
mv "$TMP" "$SDD" \
  || { rm -f "$TMP"; die "the hooks and the git-hook boundary were delivered, but writing the recorded plugin version to $SDD failed. Set .plugin.version = \"$PLUGIN_VERSION\" by hand, or re-run this script."; }

if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
  printf 'refresh-instance.sh: refreshed the four stamped hooks and recorded plugin %s in %s; the git-hook boundary was NOT touched (see above).\n' "$PLUGIN_VERSION" "$SDD"
else
  printf 'refresh-instance.sh: refreshed the four stamped hooks, delivered the git-hook boundary (.githooks/ plus core.hooksPath and merge.ff), and recorded plugin %s in %s\n' "$PLUGIN_VERSION" "$SDD"
fi
printf 'Hooks load at session start, so the refreshed gates bind from the NEXT session onward.\n'

# An INCOMPLETE refresh must not read as a finished one. The hook bytes are
# current and the version is recorded, but if the wiring above is stale then
# part of what this version promises is not in force, and the operator has to
# know that from the exit status, not from reading past a success line.
if [[ -n "$WIRING_GAPS" || -n "$GITHOOKS_SKIP_NOTE" ]]; then
  [[ -n "$WIRING_GAPS" ]] && printf '\nINCOMPLETE: the hooks are current but .claude/settings.json still needs the edit(s) named above.\n' >&2 \
    && printf 'Make them by hand (the file carries your own settings, so this script will not rewrite it), then re-run to confirm.\n' >&2
  [[ -n "$GITHOOKS_SKIP_NOTE" ]] && printf '\nINCOMPLETE: the git-hook boundary is NOT in force here (see the NOT ARMED note above).\n' >&2
  exit 3
fi
