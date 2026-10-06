#!/usr/bin/env bash
# Refresh an existing instance's stamped enforcement files from this plugin
# tree, with direction. Replaces the byte comparison the upgrade skill used to
# describe in prose, which could not tell newer from older and so could reinstall
# older hooks over newer ones while reporting success (backlog item 21).
#
# Usage:
#   refresh-instance.sh <instance-dir>            report what would change
#   refresh-instance.sh --apply <instance-dir>    perform the refresh
#   refresh-instance.sh --observe [--merges N] [--trunk <name>] --role <path>... <repo>
#       what the trunk audit would have refused over a repository's last N merges,
#       for a repository Setlist never touched (spec 0176); writes nothing there
#   refresh-instance.sh --delta [--merges N] <instance-dir>
#       the verdict delta: the stamped audit and this plugin's over the instance's
#       last N merges, printed both ways before an upgrade lands (spec 0176)
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
# THE TWO REPORT MODES OF SPEC 0176, parsed only when named first, so every
# existing spelling of this command reads exactly as it did.
REPORT_MODE=""
OBS_MERGES=50
OBS_TRUNK=""
OBS_ROLES=()
if [[ "${1:-}" == "--observe" || "${1:-}" == "--delta" ]]; then
  REPORT_MODE="${1#--}"
  shift
  while [[ $# -gt 1 ]]; do
    case "$1" in
      --merges|--trunk|--role)
        [[ $# -ge 3 ]] || die "$1 needs a value, followed by the directory"
        case "$1" in
          --merges) OBS_MERGES="$2" ;;
          --trunk)  [[ "$REPORT_MODE" == "observe" ]] || die "--trunk is --observe's: --delta reads the trunk the instance records"; OBS_TRUNK="$2" ;;
          --role)   [[ "$REPORT_MODE" == "observe" ]] || die "--role is --observe's: --delta reads the roles the instance records"; OBS_ROLES[${#OBS_ROLES[@]}]="$2" ;;
        esac
        shift 2 ;;
      *) die "--$REPORT_MODE: unknown argument '$1' (usage: --observe [--merges N] [--trunk <name>] --role <path>... <repo>, or --delta [--merges N] <instance-dir>)" ;;
    esac
  done
  [[ "$OBS_MERGES" =~ ^[1-9][0-9]*$ ]] || die "--merges takes a positive whole number of merges; got '$OBS_MERGES'"
elif [[ "${1:-}" == "--apply" ]]; then
  APPLY=yes
  shift
fi
[[ $# -eq 1 ]] || die "usage: refresh-instance.sh [--apply] <instance-dir>, or --observe [--merges N] [--trunk <name>] --role <path>... <repo>, or --delta [--merges N] <instance-dir>"
INSTANCE="$1"
[[ -d "$INSTANCE" ]] || die "not a directory: $INSTANCE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS="$ROOT/templates/hooks"
[[ -d "$HOOKS" ]] || die "templates/hooks/ not found at the plugin root ($ROOT)"

PLUGIN_VERSION="$(bash "$SCRIPT_DIR/plugin-version.sh" "$ROOT")" \
  || die "refusing to refresh: this plugin's own version is undeterminable, so the direction of the move cannot be established"

# --- OBSERVE AND THE VERDICT DELTA (spec 0176) ---------------------------------
# Both modes ask the trunk audit what it WOULD refuse, over the last N merges on
# the trunk's first-parent line, and both write NOTHING in the repository they
# read: the audit runs in a private clone (git clone --shared: the clone borrows
# the objects and the source is not touched), which is deleted on exit, and any
# configuration the question needs is written into that clone only. The clone
# is --no-checkout (spec 0180, fix round 2, the leg's F1 and F2): checked out at
# the trunk it materialised the history's own tracked symlinks, and a link at
# .claude or .claude/sdd.json carried the configuration write out of the clone,
# into the observed repository, over a file outside it, and through an
# instance's shared configuration, truncating it. With nothing checked out no
# tracked path exists to follow, and the audit reads history, not the worktree
# (its case probe beside a role directory falls back to the clone's root). The
# audit reads history and runs no command from it, so a foreign history executes
# nothing. It carries the close checks too (the Closing report, the QA verdict,
# the close review, Owns:), so one run answers both; the forge check is not run,
# because a history has no pull request to ask the forge about.
OBS_DIR=""
OBS_CLONE=""
OBS_AUDIT_OUT=""
OBS_AUDIT_RC=0
obs_cleanup() { [[ -z "$OBS_DIR" ]] || rm -rf "$OBS_DIR"; }
obs_text() { # obs_text <text> -> one line, no control bytes, cut at 160 characters
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\037\177' | cut -c1-160
}
obs_clone() { # obs_clone <repo> <trunk> -> sets OBS_CLONE, the clone at the trunk with nothing checked out (never in a subshell: the trap is this shell's)
  local c
  if [[ -z "$OBS_DIR" ]]; then
    OBS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/setlist-observe.XXXXXX")" || die "no private workspace for the clone; check TMPDIR. Nothing was written."
    trap obs_cleanup EXIT
  fi
  c="$OBS_DIR/clone"
  git clone -q --shared --no-checkout -b "$2" -- "$1" "$c" >/dev/null 2>&1 \
    || die "could not clone the repository privately to read it (git clone --shared --no-checkout -b $(obs_text "$2") failed). Nothing was written."
  OBS_CLONE="$c"
}
obs_range() { # obs_range <repo> <tip> -> "since merges commits": the parent of the Nth-newest first-parent merge, or the root
  local repo="$1" tip="$2" nth since nm nc
  nth="$(git -C "$repo" rev-list --first-parent --merges "$tip" 2>/dev/null | sed -n "${OBS_MERGES}p")"
  if [[ -n "$nth" ]]; then
    since="$(git -C "$repo" rev-parse --verify --quiet "$nth^1" 2>/dev/null)"
  else
    since="$(git -C "$repo" rev-list --first-parent "$tip" 2>/dev/null | tail -n1)"
  fi
  nm="$(git -C "$repo" rev-list --first-parent --merges "$since..$tip" 2>/dev/null | wc -l | tr -d ' ')"
  nc="$(git -C "$repo" rev-list --first-parent "$since..$tip" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s %s %s' "$since" "$nm" "$nc"
}
obs_range_line() { # obs_range_line <repo> <trunk> <since> <merges> <commits>
  local repo="$1" since="$3" root=""
  [[ "$4" -lt "$OBS_MERGES" ]] && root=", fewer than $OBS_MERGES merges on this line, so the range reaches back to the root commit (the root itself is not audited)"
  printf 'range: the last %s merge(s) on %s, %s commit(s) on its first-parent line, after %s (%s, exclusive) up to %s (%s)%s\n' \
    "$4" "$(obs_text "$2")" "$5" "$(git -C "$repo" rev-parse --short "$since")" "$(obs_text "$(git -C "$repo" log -1 --format=%s "$since")")" \
    "$(git -C "$repo" rev-parse --short "$2")" "$(obs_text "$(git -C "$repo" log -1 --format=%s "$2")")" "$root"
}
obs_refusals() { # obs_refusals <audit output> <range commits, short, one per line> -> "sha<TAB>key<TAB>shown" per refusal in range
  local out="$1" inrange="$2" line sha rest code
  while IFS= read -r line; do
    case "$line" in VIOLATION\ *) ;; *) continue ;; esac
    rest="${line#VIOLATION }"; sha="${rest%% *}"; rest="${rest#"$sha"}"; rest="${rest#"${rest%%[! ]*}"}"
    grep -qx -- "$sha" <<< "$inrange" || continue
    if [[ "$rest" =~ ^\[(SLH-[A-Z0-9-]+)\] ]]; then
      code="${BASH_REMATCH[1]}"
      printf '%s\t%s\t[%s]\n' "$sha" "$code" "$code"
    else
      # No code (E-2): the sentence stands in its place, and its first six words key it.
      printf '%s\t%s\t%s\n' "$sha" "$(awk '{ for (i = 1; i <= 6 && i <= NF; i++) printf "%s%s", (i > 1 ? " " : ""), $i }' <<< "$rest")" "$(obs_text "$rest")"
    fi
  done <<< "$out"
}
obs_audit() { # obs_audit <audit-script> <clone> [args] -> sets OBS_AUDIT_OUT and OBS_AUDIT_RC (never in a subshell)
  OBS_AUDIT_RC=0
  OBS_AUDIT_OUT="$(env -u CLAUDE_PLUGIN_ROOT bash "$1" "$2" "${@:3}" 2>&1)" || OBS_AUDIT_RC=$?
}
OBS_HEADER='what the trunk audit WOULD refuse had this repository adopted Setlist at the start of the range (by commit; the code where the audit gives one, its own sentence where it does not):'

# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
if [[ "$REPORT_MODE" == "observe" ]]; then
  OBS_REPO="$INSTANCE"
  git -C "$OBS_REPO" rev-parse --git-dir >/dev/null 2>&1 || die "--observe: $(obs_text "$OBS_REPO") is not a git repository, so there is no history to read. Nothing was written."
  [[ "$(git -C "$OBS_REPO" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]] \
    || die "--observe: this is a shallow clone, so the merges in the range may not be here to read; fetch the full history (git fetch --unshallow) and retry. Nothing was written."
  command -v jq >/dev/null 2>&1 && [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" == "x" ]] \
    || die "--observe: jq is missing or not working here, and the audit reads its configuration with it. Nothing was written."
  if [[ -z "$OBS_TRUNK" ]]; then
    OBS_TRUNK="$(git -C "$OBS_REPO" symbolic-ref --short HEAD 2>/dev/null || true)" # fail-open-ok: an empty trunk is refused on the next line
  fi
  [[ -n "$OBS_TRUNK" ]] && git -C "$OBS_REPO" rev-parse --verify --quiet "refs/heads/$OBS_TRUNK^{commit}" >/dev/null 2>&1 \
    || die "--observe: the trunk $(obs_text "${OBS_TRUNK:-(none: HEAD is detached)}") is not a local branch here; name the branch this project merges onto with --trunk. Nothing was written."
  [[ "${#OBS_ROLES[@]}" -gt 0 ]] \
    || die "--observe: no --role given. The audit judges the commits that touch a role path (where the feature code lives: src, lib, app ...), so it needs at least one. Nothing was written."
  for r in "${OBS_ROLES[@]}"; do
    case "$r" in ''|/*|*..*|.) die "--observe: the role path $(obs_text "$r") is not a clean path relative to the repository root. Nothing was written." ;; esac
  done
  obs_clone "$OBS_REPO" "$OBS_TRUNK"; OBS_C="$OBS_CLONE"
  mkdir -p "$OBS_C/.claude"
  jq -n --arg trunk "$OBS_TRUNK" --arg version "$PLUGIN_VERSION" '{trunk: $trunk, roles: {src: $ARGS.positional}, plugin: {version: $version}}' --args "${OBS_ROLES[@]}" > "$OBS_C/.claude/sdd.json" \
    || die "--observe: could not write the configuration into the private clone. Nothing was written in the repository."
  read -r OBS_SINCE OBS_NM OBS_NC <<< "$(obs_range "$OBS_C" "$OBS_TRUNK")"
  printf 'observe (plugin %s): %s, read in a private clone; nothing was installed or written in it.\n' "$PLUGIN_VERSION" "$(obs_text "$OBS_REPO")"
  printf 'roles: %s\n' "$(obs_text "${OBS_ROLES[*]}")"
  obs_range_line "$OBS_C" "$OBS_TRUNK" "$OBS_SINCE" "$OBS_NM" "$OBS_NC"
  if [[ "$OBS_NC" -eq 0 ]]; then
    printf 'nothing to read: %s carries no commit after its root.\n' "$(obs_text "$OBS_TRUNK")"
    exit 0
  fi
  obs_audit "$SCRIPT_DIR/trunk-audit.sh" "$OBS_C" --since "$OBS_SINCE"; OBS_OUT="$OBS_AUDIT_OUT"
  if [[ "$OBS_AUDIT_RC" -ge 2 ]]; then
    printf 'the audit could not read this history (exit %s):\n' "$OBS_AUDIT_RC"
    printf '%s\n' "$OBS_OUT" | tail -n3 | while IFS= read -r l; do printf '  %s\n' "$(obs_text "$l")"; done
    exit 1
  fi
  OBS_INRANGE="$(git -C "$OBS_C" log --first-parent --format=%h "$OBS_SINCE..$OBS_TRUNK")"
  OBS_LIST="$(obs_refusals "$OBS_OUT" "$OBS_INRANGE")"
  printf '%s\n' "$OBS_HEADER"
  if [[ -z "$OBS_LIST" ]]; then
    printf '  none\n'
  else
    printf '%s\n' "$OBS_LIST" | while IFS="$(printf '\t')" read -r sha _ shown; do
      printf '  %s %s  %s\n' "$sha" "$shown" "$(obs_text "$(git -C "$OBS_C" log -1 --format=%s "$sha")")"
    done
  fi
  printf '%s\n' "$OBS_OUT" | grep -E '^audited ' | sed 's/^/the audit: /'
  printf 'This is a report: nothing above was refused, and exit 0 says the read completed. /setlist:retrofit installs the hooks that would refuse these.\n'
  exit 0
fi

SDD="$INSTANCE/.claude/sdd.json"
[[ -f "$SDD" ]] || die "refusing to refresh: no .claude/sdd.json at $INSTANCE, so this is not a framework instance (or its config is missing)"

command -v jq >/dev/null 2>&1 \
  || die "refusing to refresh: jq is not installed, so the version recorded in .claude/sdd.json cannot be read and a downgrade would be indistinguishable from an upgrade. Install jq, then retry."

# JQ PRESENT IS NOT JQ USABLE, here too (the 2.5.0 leg, F-degraded-1). Every
# other carrier of this rule probes jq by OUTPUT before reading the config;
# this script located it and read. Under a jq that exits 0 printing nothing the
# recorded version read as EMPTY, the empty read was taken as "stamped before
# the version was recorded", the downgrade guard stood down, the refresh ran to
# completion, and the version write below truncated .claude/sdd.json to zero
# bytes while the summary reported success. Measured on the 2.5.0 candidate.
[[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" == "x" ]] \
  || die "refusing to refresh: jq is installed but does not work here (run on a one-key document it did not print the value back: it exited nonzero, or exited 0 and printed nothing), so the version recorded in .claude/sdd.json cannot be read and a downgrade would be indistinguishable from an upgrade. Run 'jq --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Nothing was written."

jq -e . "$SDD" >/dev/null 2>&1 \
  || die "refusing to refresh: $SDD does not parse as JSON, so the recorded plugin version cannot be read. Fix the file, then retry."

# ABSENT AND UNREADABLE ARE DIFFERENT ANSWERS (F4 of the second 2.7.0 leg, fix
# round 2). This read .plugin.version directly, and when .plugin was present but
# not an object jq exited nonzero with "Cannot index string with string"; the
# error went to stderr, the substitution captured an empty stdout, and the empty
# value was then read as "stamped before the plugin version was recorded". So an
# instance recording a NEWER plugin in a malformed field was refreshed FORWARD,
# the older enforcement files were written over the newer ones, and report mode
# printed "forward" to the one person who could have caught it. The downgrade
# guard exists to make exactly that impossible, and it failed open.
if ! RECORDED="$(jq -r 'if has("plugin") and ((.plugin | type) != "object") then error("plugin-not-object") else (.plugin.version // empty) end' "$SDD" 2>/dev/null)"; then
  die "refusing to refresh: .claude/sdd.json has a .plugin field that is not an object, so the version this instance records cannot be read and a downgrade would be indistinguishable from an upgrade. A check that could not run has not passed. Make .plugin an object, for example {\"version\": \"2.6.1\"}, then retry. Nothing was written."
fi

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

# --- the four stamped enforcement files (four through 2.5.0; the Stop hook joined
# in 2.6.0, spec 0132 cluster H; the one hard deny's own hook in the 2.8.0 cycle,
# spec 0143; the two Bash gates left in 2.8.0, spec 0144) -----------------------------------------------------------------------

STAMPED_HOOKS="scope-hook regrounding-hook stop-hook bypass-deny"
# RETIRED WITH 2.8.0 (spec 0144): the two Bash advisory gates. No longer stamped,
# and never removed by this script: removal from someone's repository is
# destructive, so what is left of them is REPORTED with the exact edit and the
# owner makes it (spec 0142 section 10, the owner's ruling R-D of 2026-09-13).
RETIRED_HOOKS="commit-gate close-gate"
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

# The retired files still present. A symlink counts and is not followed.
RETIRED_FILES=""
for h in $RETIRED_HOOKS; do
  if [[ -e "$INSTANCE/.claude/hooks/$h.sh" || -L "$INSTANCE/.claude/hooks/$h.sh" ]]; then
    RETIRED_FILES="$RETIRED_FILES .claude/hooks/$h.sh"
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
# core.hooksPath is REPOSITORY TEXT (spec 0169's E-j, bounded in spec 0173): git stores
# whatever `git config` was given, a newline included, and every message below printed it whole,
# so a value could put a line of its own choosing on stderr. The value is printed through the
# stamp's own bound (the path set, 80 characters, the edit said), computed once here and used by
# every message; the LOGIC keeps reading FOREIGN_HOOKSPATH. The stamp and the refresh carry the same
# expression, moved in one commit, and 0158 stamp g2 and g3 pin the pair.
FOREIGN_HOOKSPATH_SHOWN="$(LC_ALL=C; v="$FOREIGN_HOOKSPATH"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e")"
# WHICH OF THE TWO SHAPES THIS IS (spec 0157, SD2), decided once and used by the
# report and by the refusal, so both tell the same story.
#
# hooks_layer_is_ours decides by BYTES, deliberately: every text-based reading
# of "is this file ours" broke in both directions across three adversary rounds,
# and to a byte test a CUSTOMISED Setlist hook and a foreign file under a
# Setlist name are the same thing. Refusing is right for both. But the REASON
# printed was the displacement one for both, so an operator who had edited
# .githooks/pre-push was told another tool's layer was about to be switched off
# and to move their gitleaks checks into the directory they were already in
# (spec 0121's upgrade-seam fixtures measured it).
#
# The shape is named by what is observable: git already runs Setlist's own
# directory, and every file the ownership test objects to carries one of the
# three stamped hook names. What cannot be observed is whether a person edited
# them, and the message says so rather than guessing.
FOREIGN_HOOK_NAMES=""
SD2_OURS_EDITED=0
if [[ -n "$FOREIGN_HOOKSPATH" ]] && git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$INSTANCE" "$FOREIGN_HOOKSPATH")" 2>/dev/null | tr '\n' ' ')" # fail-open-ok: an empty list leaves SD2_OURS_EDITED at 0 and the DISPLACEMENT reason, which is the reason this refusal has always given
  if [[ "$FOREIGN_HOOKSPATH" == ".githooks" ]] \
     && [[ "$(git -C "$INSTANCE" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
     && [[ -n "${FOREIGN_HOOK_NAMES// /}" ]]; then
    SD2_OURS_EDITED=1
    for _fh in $FOREIGN_HOOK_NAMES; do
      case "$_fh" in
        pre-commit|pre-merge-commit|pre-push) ;;
        *) SD2_OURS_EDITED=0 ;;
      esac
    done
  fi
fi
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
  # The instance and git's top are compared as DIRECTORIES (-ef: the same device and
  # inode), never as strings: bash's pwd -P keeps a path's typed case and git reports
  # the stored one, so on a filesystem that folds case a correct instance read as
  # sitting below its own top and was never armed (spec 0159, E-h).
  if [[ -z "$INSTANCE_TOP" ]] || ! [[ "$INSTANCE_TOP" -ef "$INSTANCE" ]]; then
    GITHOOKS_SKIP_NOTE="this instance ($INSTANCE_REAL) sits BELOW the top of its git working tree ($INSTANCE_TOP); git resolves core.hooksPath at the top, so a boundary delivered here would be inert or would displace the parent repository's layer. The git-hook boundary was NOT touched. Make the instance its own repository, or run Setlist from the worktree top."
  elif [[ -n "$GIT_DIR_HERE" && -n "$GIT_COMMON_HERE" && "$GIT_DIR_HERE" != "$GIT_COMMON_HERE" ]]; then
    GITHOOKS_SKIP_NOTE="this instance is a LINKED worktree; core.hooksPath lives in the shared config, so arming from here would repoint the MAIN worktree's hooks (and the guard cannot see that worktree's layer from here). The git-hook boundary was NOT touched. Arm from the main worktree."
  fi
fi

# CHAIN RATHER THAN REFUSE (spec 0173, item 2; the validator's E-c, option 1). A
# foreign layer this run can SEE (a directory that exists and lists) is chained: the
# boundary is armed, the layer's location is recorded as "hooks_chain" in
# .claude/sdd.json, a fixed pass-through is written under each other hook name it
# carries, and every Setlist git hook runs its hook of the same name after its own
# verdict. What still refuses: Setlist's own directory with edited files (SD2, the
# reason above), and a layer this run cannot see (unresolvable, absent, unlistable),
# because a guard that cannot see a layer cannot promise to run it.
# SETLIST_ADOPT_HOOKSPATH=1 keeps its meaning: displace, nothing chained.
# AND THE ARMING TARGET IS ASKED FIRST (spec 0180, fix round 2, the 2.11.0 leg's
# F10): chaining arms .githooks, so a foreign hook already vendored there, dormant
# while the other layer ran, went live with nothing said, where the path without a
# chain refused to arm. A .githooks holding a file that is not Setlist's is not
# chained: the refusal below names it, as the round-7 guard names it unchained.
CHAIN_MODE=0; CHAIN_VALUE=""; CHAIN_DIR=""; CHAIN_NAMES=""
if [[ -n "$FOREIGN_HOOKSPATH" && -z "$GITHOOKS_SKIP_NOTE" && "$SD2_OURS_EDITED" -eq 0 && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]]; then
  CHAIN_DIR="$(setlist_refusal_dir "$INSTANCE" "$FOREIGN_HOOKSPATH")"
  if [[ -n "$(setlist_arming_target_foreign "$INSTANCE")" ]]; then
    FOREIGN_HOOKSPATH=".githooks"; FOREIGN_HOOKSPATH_SHOWN='".githooks"'
    FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$INSTANCE" .githooks)" 2>/dev/null | tr '\n' ' ')" # fail-open-ok: an empty list prints "unresolvable" in the refusal, which still refuses
  elif setlist_chainable "$INSTANCE" "$CHAIN_DIR"; then
    CHAIN_MODE=1
    CHAIN_VALUE="$(setlist_chain_value "$INSTANCE")"
    CHAIN_NAMES="$(setlist_chain_passthrough_names "$CHAIN_DIR" | tr '\n' ' ')"
  fi
fi

# THE TRUNK AUDIT'S BASELINE (spec 0157, the 2.10.0 intake section 1.2).
#
# The audit's default baseline is the commit that introduced .claude/sdd.json,
# which is right for a project born with its hooks and WRONG in the worst
# direction for one that was not: every merge between the stamp and the boundary
# was made when no pre-merge-commit existed to record the completion the audit
# asks for, so the audit refuses every push from then on and says those commits
# were "made after this instance adopted the rules". Measured on a real
# instance: 33 violations at the default, 0 at the commit that delivered
# .githooks/.
#
# This script is the one moment that knows both dates, so this is where the
# baseline is recorded. DECIDED HERE, before the report, so report mode and
# --apply describe the same future (round 5, finding 2), and WRITTEN in the same
# jq write that records the plugin version, so it lands in the migration commit
# /setlist:upgrade makes.
#
# Never over a value that is already there: the key is a declaration in a
# reviewed file, and a declaration is the declarer's. A present value that fails
# the audit's own tests is REPORTED as a finding with what this refresh would
# have written, because a report is what this script owes and rewriting someone's
# declaration to fix it is not.
AUDIT_BASELINE_WRITE=""
AUDIT_BASELINE_NOTE=""
# --- THE BASELINE FRAME (spec 0167) -------------------------------------------
# LOCKSTEP: everything from this banner to the one that closes it is
# BYTE-IDENTICAL in scripts/trunk-audit.sh and scripts/refresh-instance.sh, and
# the suite asserts it (the audit ships alone into .claude/hooks/ and sources
# nothing from the plugin, so one text in two files is how it is shared).
#
# ONE READER FOR THREE CALLERS: the trunk audit, the refresh's usability probe,
# and /setlist:validate step 18, which reaches it through the refresh's report
# mode. The 2.10.0 second leg's F1, F3, F4, F5 and F9 were these callers asking
# three different questions of one key: the audit required the key on the
# trunk's first-parent line, the refresh wrote the commit that ADDED
# .githooks/pre-push, which sits on a side branch whenever the hooks arrived
# through a merge (the upgrade's chore branch under merge.ff=false makes that
# the ordinary shape), and the refresh's probe asked plain ancestry. Every push
# after such an upgrade was refused by name while the refresh called the key
# healthy. Measured on the owner's instance: refused at once.
#
# So the frame is COMPUTED, not required. Any ancestor of the tip is a valid
# declaration, and the walk starts at the OLDEST commit on the tip's
# first-parent line that contains it: the declared commit itself when it is on
# that line, otherwise the merge that brought it in. Containment is monotone
# along the line (a commit that contains it has descendants that do too), so
# walking from the tip and stopping at the first commit that does NOT contain
# it finds that frame. Never the tip for an older declaration: that would walk
# nothing and attest every trunk clean (spec 0167, ruling E-a).
#
# One line out, compared by bytes across the callers by the suite's key corpus:
#   absent                                  no key
#   frame <frame-id> <declared-id>          walk from <frame-id>
#   refuse SLH-BASELINE-<CODE> <reason>     the audit refuses it at exit 2
# A git failure while computing the frame refuses: a later frame walks less, so
# a guessed one is the fail-open direction. Every git call is tested with
# if/else rather than `$?` so the function behaves the same under `set -e`.
slh_baseline_frame() { # slh_baseline_frame <repo> <sdd.json> <tip>
  local repo="$1" sdd="$2" tip="$3" v c prev="" rc fp
  # The shape guard both scripts carried since 0157: a present "audit" that is
  # not an object, or a present baseline that is not a string (JSON false and
  # null included, spec 0164 F21), is MALFORMED, never read as "no key".
  if ! v="$(jq -r 'if has("audit") and ((.audit | type) != "object") then error("audit-not-object")
        elif ((.audit // {}) | has("baseline")) and ((.audit.baseline | type) != "string") then error("baseline-not-string")
        else (.audit.baseline // empty) end' "$sdd" 2>/dev/null)"; then
    printf 'refuse SLH-BASELINE-MALFORMED type\n'; return 0
  fi
  if [[ -z "$v" ]]; then printf 'absent\n'; return 0; fi
  # LC_ALL=C: a shell bracket range collates by the LOCALE, so under a UTF-8
  # locale `[!0-9a-f]` does not match `A` (spec 0157, the suite's case b3).
  if ! LC_ALL=C grep -qE '^[0-9a-f]{40}$' <<< "$v"; then
    printf 'refuse SLH-BASELINE-MALFORMED shape\n'; return 0
  fi
  if ! git -C "$repo" rev-parse --verify --quiet "${v}^{commit}" >/dev/null 2>&1; then
    printf 'refuse SLH-BASELINE-UNRESOLVED commit\n'; return 0
  fi
  if git -C "$repo" merge-base --is-ancestor "$v" "$tip" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  case "$rc" in
    0) ;;
    1) printf 'refuse SLH-BASELINE-NOT-ANCESTOR ancestry\n'; return 0 ;;
    *) printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0 ;;
  esac
  if ! fp="$(git -C "$repo" rev-list --first-parent "$tip" 2>/dev/null)"; then
    printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0
  fi
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    if git -C "$repo" merge-base --is-ancestor "$v" "$c" >/dev/null 2>&1; then rc=0; else rc=$?; fi
    case "$rc" in
      0) prev="$c" ;;
      1) break ;;
      *) printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0 ;;
    esac
  done <<SLH_FRAME_EOF
$fp
SLH_FRAME_EOF
  if [[ -z "$prev" ]]; then printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0; fi
  printf 'frame %s %s\n' "$prev" "$v"
}
# --- END THE BASELINE FRAME ---------------------------------------------------
if git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # The recorded trunk's tip, falling back to HEAD: the value written on a FIRST
  # delivery has to be a commit the migration commit will descend from, and the
  # branch a refresh happens to run on may not be the trunk.
  AUDIT_TRUNK_NAME="$(jq -r '.trunk // "main"' "$SDD" 2>/dev/null || true)" # fail-open-ok: an unreadable trunk name leaves the tip resolution to HEAD below, which writes a commit this history carries either way
  AUDIT_TRUNK_TIP="$(git -C "$INSTANCE" rev-parse --verify --quiet "refs/heads/${AUDIT_TRUNK_NAME}^{commit}" 2>/dev/null || true)" # fail-open-ok: an unresolvable trunk writes NO key, handled below
  # NO HEAD FALLBACK (spec 0164, fix round 2, F20 of the 2.10.0 leg). It used to
  # fall back to HEAD and call the result "this trunk's tip": run from a spec
  # branch in a clone whose recorded trunk is not a local branch (a
  # --single-branch clone, a renamed default branch, a typo in the key), it
  # wrote that branch's HEAD, and every later push from the trunk was refused
  # by name, SLH-BASELINE-NOT-ANCESTOR, or SLH-BASELINE-UNRESOLVED once the
  # branch was gone. A key this instance cannot use is worse than no key.
  AUDIT_TRUNK_TIP_MISSING=""
  [[ -n "$AUDIT_TRUNK_TIP" ]] || AUDIT_TRUNK_TIP_MISSING="$AUDIT_TRUNK_NAME"
  # THE ONE READER (spec 0167): the verdict comes from slh_baseline_frame, the
  # function the audit itself runs, against the recorded trunk's tip. With no
  # trunk tip here there is nothing to measure ancestry against, and a present
  # key is reported as unchecked rather than guessed at.
  AUDIT_BASELINE_VERDICT="$(slh_baseline_frame "$INSTANCE" "$SDD" "${AUDIT_TRUNK_TIP:-}")"
  # DISPLAY ONLY: the value as written, quoted back in the note.
  AUDIT_BASELINE_SHOWN="$(jq -r '(.audit.baseline? // empty) | tostring' "$SDD" 2>/dev/null || true)" # fail-open-ok: display only, the verdict above decides
  # The commit that ADDED .githooks/pre-push: the arrival of the push-time audit
  # is the arrival of the boundary, and --root is here for the same reason the
  # audit carries it (RC2-2026): without it git renders a ROOT commit as adding
  # nothing.
  AUDIT_BASELINE_ADDED="$(git -C "$INSTANCE" log --root --diff-filter=A --format=%H -- .githooks/pre-push 2>/dev/null | tail -n1 || true)" # fail-open-ok: no adding commit means the boundary is arriving now, handled as a first delivery below
  AUDIT_BASELINE_WOULD="$AUDIT_BASELINE_ADDED"
  [[ -n "$AUDIT_BASELINE_WOULD" ]] || AUDIT_BASELINE_WOULD="$AUDIT_TRUNK_TIP"
  if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
    : # no boundary is delivered here, so there is no boundary to record
  elif [[ "$AUDIT_BASELINE_VERDICT" != "absent" ]]; then
    # PRESENT: reported, never rewritten. A declaration is the declarer's.
    case "$AUDIT_BASELINE_VERDICT" in
      "frame "*)
        read -r _ AUDIT_BASELINE_FRAME _ <<< "$AUDIT_BASELINE_VERDICT"
        if [[ "$AUDIT_BASELINE_FRAME" == "$AUDIT_BASELINE_SHOWN" ]]; then
          AUDIT_BASELINE_NOTE="already recorded ($AUDIT_BASELINE_SHOWN), left as declared; the audit walks from $AUDIT_BASELINE_FRAME, the declared commit itself"
        else
          AUDIT_BASELINE_NOTE="already recorded ($AUDIT_BASELINE_SHOWN), left as declared; the audit walks from $AUDIT_BASELINE_FRAME, the first commit on the trunk's own line that contains it"
        fi
        ;;
      "refuse SLH-BASELINE-UNRESOLVED git")
        if [[ -n "$AUDIT_TRUNK_TIP_MISSING" ]]; then
          AUDIT_BASELINE_NOTE="recorded as '$AUDIT_BASELINE_SHOWN' and left as declared, but NOT checked: this instance records its trunk as \"$AUDIT_TRUNK_TIP_MISSING\", which is not a branch in this clone, so there is no history to measure it against here"
        else
          AUDIT_BASELINE_NOTE="recorded as '$AUDIT_BASELINE_SHOWN', which the trunk audit refuses [SLH-BASELINE-UNRESOLVED] (git could not compute its frame here); this refresh would have written $AUDIT_BASELINE_WOULD and leaves your declaration alone"
        fi
        ;;
      "refuse "*)
        read -r _ AUDIT_BASELINE_CODE AUDIT_BASELINE_WHY <<< "$AUDIT_BASELINE_VERDICT"
        case "$AUDIT_BASELINE_WHY" in
          type)     AUDIT_BASELINE_WHY="the \"audit\" value is not an object, or the baseline is not a string" ;;
          shape)    AUDIT_BASELINE_WHY="it is not a full 40-character lowercase commit id" ;;
          commit)   AUDIT_BASELINE_WHY="no such commit in this repository" ;;
          ancestry) AUDIT_BASELINE_WHY="it is not an ancestor of this trunk" ;;
        esac
        AUDIT_BASELINE_NOTE="recorded as '$AUDIT_BASELINE_SHOWN', which the trunk audit refuses [$AUDIT_BASELINE_CODE] ($AUDIT_BASELINE_WHY), so every push is refused until it is corrected; this refresh would have written $AUDIT_BASELINE_WOULD and leaves your declaration alone"
        ;;
    esac
  elif [[ -z "$AUDIT_BASELINE_ADDED" && -n "$AUDIT_TRUNK_TIP_MISSING" ]]; then
    # A first delivery whose trunk ref does not resolve here: nothing is written,
    # and the note names the branch it looked for (F20).
    AUDIT_BASELINE_NOTE="NOT recorded: this instance records its trunk as \"$AUDIT_TRUNK_TIP_MISSING\", which is not a branch in this clone, so the commit the audit should start from cannot be named here and writing the current branch's tip would refuse every later push from the trunk. Run the refresh where that branch exists, or correct the \"trunk\" key first"
  elif [[ -n "$AUDIT_BASELINE_WOULD" ]]; then
    AUDIT_BASELINE_WRITE="$AUDIT_BASELINE_WOULD"
    if [[ -n "$AUDIT_BASELINE_ADDED" ]]; then
      AUDIT_BASELINE_NOTE="would be recorded as $AUDIT_BASELINE_WOULD, the commit that added .githooks/pre-push, so the audit stops judging history from before this instance had any hooks"
    else
      AUDIT_BASELINE_NOTE="would be recorded as $AUDIT_BASELINE_WOULD, this trunk's tip, which the commit delivering the boundary will descend from"
    fi
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
# THE PREDICATE IS IDENTITY, NOT SPELLING (spec 0173, item 3; KL10 taken; the public bullet
# "The wiring check recognises only the command spellings settings.json.tmpl ships" retired).
# The enumerated set above was the honest answer to "a shape test cannot express the file I
# stamped", and it had two residuals the 2.4.0 and 2.7.0 reviews measured, one in each direction:
# `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/bypass-deny.sh`, which RUNS the stamped file, was
# reported NOT WIRED (the first word is `bash`), and `"$CLAUDE_PROJECT_DIR"/.claude/hooks/
# bypass-deny.sh >/dev/null`, which runs it and throws its stdout (the JSON decision) away, was
# certified wired (the first word matched). A set of names cannot express "the file I stamped"
# either; the file system can. So an entry now counts when the file its command RUNS is, by
# device and inode (`-ef`), the file this script stamps:
#
#   - the command is read by wiring_cmd_file, a restricted word reader: bare, single-quoted and
#     double-quoted words, and $CLAUDE_PROJECT_DIR or ${CLAUDE_PROJECT_DIR} replaced by this
#     instance's absolute path. ANY other shell construct (another `$`, a backtick, a backslash,
#     `;`, `|`, `&`, a redirect, a subshell, a glob, a comment) makes the entry not ours, because a
#     reader that guessed at a construct it does not model would be the spelling test again;
#   - the command is exactly one word naming the file, or `bash` or `sh` then exactly one word;
#     anything after it (an argument, a redirect) is not the stamped hook speaking for itself;
#   - the named path is absolute after expansion (a hook's working directory is the session's,
#     not the instance's, so a relative path does not reliably name the stamped file), and it is
#     the same file as <instance>/.claude/hooks/<hook>.sh; for a hook this release no longer
#     stamps, whose file may be gone, the same resolved directory and name.
#
# ours_spellings <hook> keeps its name and its contract for every caller below (the wiring loop,
# the scope matcher reader, the timeouts, the retired entries): a JSON array of the command
# strings in this settings file that run the file, which OURS_TEST tests by whole-string
# membership. A settings file jq cannot read yields an empty array, which reads as NOT WIRED:
# fail closed, as before.
wiring_cmd_file() { # wiring_cmd_file <command> -> the path the command runs; 1 when it is not one plain run of one file
  local c="$1" i=0 n ch q="" w="" inword=0 abs
  local -a words=()
  abs="$(cd "$INSTANCE" 2>/dev/null && pwd)" || abs="$INSTANCE" # fail-open-ok: an unreadable instance falls back to the given path, and the caller has already refused a missing one
  n=${#c}
  while (( i < n )); do
    ch="${c:i:1}"
    if [[ "$q" == "'" ]]; then
      if [[ "$ch" == "'" ]]; then q=""; else w="$w$ch"; fi
      i=$((i + 1)); continue
    fi
    if [[ "$q" == '"' ]]; then
      case "$ch" in
        '"') q=""; i=$((i + 1)); continue ;;
        '`'|'\') return 1 ;;
        '$') ;;
        *) w="$w$ch"; i=$((i + 1)); continue ;;
      esac
    else
      case "$ch" in
        ' '|$'\t')
          if (( inword )); then words+=("$w"); w=""; inword=0; fi
          i=$((i + 1)); continue ;;
        "'"|'"') q="$ch"; inword=1; i=$((i + 1)); continue ;;
        '$') ;;
        [A-Za-z0-9/._+=:@%,-]) w="$w$ch"; inword=1; i=$((i + 1)); continue ;;
        *) return 1 ;;
      esac
    fi
    # A `$`, bare or inside double quotes: only the project variable is modelled.
    if [[ "${c:i:21}" == '${CLAUDE_PROJECT_DIR}' ]]; then
      w="$w$abs"; inword=1; i=$((i + 21)); continue
    fi
    if [[ "${c:i:19}" == '$CLAUDE_PROJECT_DIR' ]] && [[ ! "${c:i+19:1}" =~ [A-Za-z0-9_] ]]; then
      w="$w$abs"; inword=1; i=$((i + 19)); continue
    fi
    return 1
  done
  [[ -z "$q" ]] || return 1
  if (( inword )); then words+=("$w"); fi
  case "${#words[@]}" in
    1) w="${words[0]}" ;;
    2) case "${words[0]}" in bash|sh) w="${words[1]}" ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
  # A drive spelling (C:/...) is absolute too, under MSYS or Cygwin only, where settings.json
  # on Windows spells an absolute hook path that way and -ef compares it as a file (spec 0179);
  # elsewhere C:/x is a relative path, and a relative path is not the stamped file.
  case "$w" in
    /*) printf '%s' "$w" ;;
    [A-Za-z]:/*) case "${OSTYPE:-}" in msys*|cygwin*) printf '%s' "$w" ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}
wiring_runs_stamped() { # wiring_runs_stamped <command> <hook> -> 0 when the command runs <instance>/.claude/hooks/<hook>.sh
  local f target fd td
  f="$(wiring_cmd_file "$1")" || return 1
  target="$INSTANCE/.claude/hooks/$2.sh"
  if [[ -e "$f" && -e "$target" ]]; then
    [[ "$f" -ef "$target" ]]; return
  fi
  # A retired hook's file may be gone: the same resolved directory and the same name.
  [[ "${f##*/}" == "$2.sh" ]] || return 1
  fd="$(cd "${f%/*}" 2>/dev/null && pwd -P)" || return 1
  td="$(cd "$INSTANCE/.claude/hooks" 2>/dev/null && pwd -P)" || return 1
  [[ "$fd" == "$td" ]]
}
ours_spellings() { # ours_spellings <hook> -> JSON array of the command strings in $SETTINGS that run the stamped <hook>
  local h="$1" j c
  local -a hit=()
  while IFS= read -r j; do
    [[ -n "$j" ]] || continue
    c="$(printf '%s' "$j" | jq -r . 2>/dev/null)" || continue
    wiring_runs_stamped "$c" "$h" && hit+=("$j")
  done <<< "$(jq -c '[.hooks // {} | .. | objects | select(has("command")) | .command | strings] | unique | .[]' "$SETTINGS" 2>/dev/null)"
  # The certified strings go back to jq as the JSON strings they already are, on stdin, never
  # as --args (spec 0179): MSYS rewrites a path-shaped argument it hands a native program, and
  # "$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh reached a Windows jq as "$CLAUDE_PROJECT_DIR"C:/Program
  # Files/Git/.claude/hooks/x.sh, so the wiring check certified nothing there.
  printf '%s\n' ${hit[@]+"${hit[@]}"} | jq -cs .
}

# ours_test <hook> -> a jq boolean expression over one hook entry: a command hook whose command
# is one of the strings ours_spellings certified. Whole-string membership only since spec 0173;
# the first-word clause is gone, because the first word is how `X >/dev/null` was certified.
OURS_TEST='
  (.type // "command") == "command"
  and ((.command // "") as $c | ($allowed | index($c)) != null)
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
      regrounding-hook)  ev=SessionStart; tool="" ;;
      # KL10 TAKEN (2026-09-07, spec 0132 cluster H): the wiring check learns the
      # fifth session hook, on the Stop event, which takes no matcher.
      stop-hook)         ev=Stop;        tool="" ;;
      # The one hard deny's own hook (spec 0143): a PreToolUse hook that must
      # reach Bash (the two gates that stood beside it left in 2.8.0, spec 0144).
      bypass-deny)       ev=PreToolUse;  tool=Bash ;;
      *)                 ev=PreToolUse;  tool="" ;;
    esac
    # A MATCH-ALL MATCHER IS COVERAGE, NOT A GAP (F4-2026, 2.2.0 leg finding F4).
    #
    # This test built a regex by interpolation: `test("^(" + ($m // "") + ")$")`.
    # Two ordinary spellings broke it, both in the direction that reports a
    # WORKING instance as broken. `"*"` makes `^(*)$`, which is not a valid
    # regex at all, so jq ERRORS and `jq -e` fails, which this reads as
    # unwired. An ABSENT matcher makes `^()$`, which matches only the empty
    # string, so no tool name matches and it also reads as unwired. Measured
    # both ways on the shipped bytes before the fix.
    #
    # The consequence was not cosmetic: --apply exits 3 INCOMPLETE every time,
    # so an instance whose protection is genuinely live can never certify, and
    # the documented workaround was to name tools explicitly. Claude Code
    # treats an absent matcher and `*` as "every tool", so both are FULL
    # coverage and the check now says so before it builds any regex.
    #
    # The empty-$tool case (a hook with no tool to reach, like SessionStart)
    # keeps its own arm above; this one is about a tool that IS named and a
    # matcher that covers everything.
    if ! jq -e --arg ev "$ev" --arg tool "$tool" --argjson allowed "$(ours_spellings "$h")" "
          [ (.hooks[\$ev] // [])[]
            | select(any(.hooks[]?; $OURS_TEST))
            | select((\$tool == \"\")
                     or ((.matcher // \"\") == \"\")
                     or (.matcher == \"*\")
                     or ((.matcher | gsub(\",\"; \"|\")) as \$m | \$tool | test(\"^(\" + \$m + \")\$\")))
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
  bypass deny on PreToolUse matching Bash, the
  re-grounding hook on SessionStart, the stop hook on Stop), keeping this file's
  own permissions and model settings."
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
  # COVERAGE OVER THE FULL TOOL SET, EVERY ENTRY, ONE FIX (F3 with V19-F5 and
  # V19-F10). Three findings, one function, and they are fixed together on
  # purpose: three separate repairs to one predicate is how the second
  # reintroduces the first, which is the repair-defect rate this repository
  # measures at about one in five.
  #
  #   F3/V19-F5  the test was `[[ "$SCOPE_MATCHER" != *NotebookEdit* ]]`, a bash
  #              SUBSTRING search sitting next to two neighbours that were real
  #              coverage tests. `Write|Edit|MultiEdit|NotebookEditor` contains
  #              the token and covers nothing, so it certified CLEAN; and
  #              `Write|NotebookEdit` certified CLEAN while Edit and MultiEdit
  #              were checked by nothing at all. Both directions measured with
  #              controls: an UNDER-protected instance was told it was wired.
  #   V19-F10    `| first` read only the FIRST entry running the scope hook, so
  #              a correctly protected instance carrying two registrations was
  #              told notebook writes reach the trunk. A false REPORT rather
  #              than a false refusal, but it sends an operator to repair a
  #              boundary that is already in force.
  #   F5         a catch-all matcher (`*`, `.*`, empty, absent) is MATCH-ALL and
  #              was read as covering nothing; the `Write,Edit` comma spelling
  #              the harness also accepts became one impossible alternative; and
  #              a jq that ERRORED yielded an empty string that read as "does
  #              not count" rather than as "could not be checked".
  #
  # So: every entry's matcher, the UNION of what they cover, tested per tool as
  # an ANCHORED alternation, with match-all and the comma spelling handled
  # before the regex is built and a jq failure reported as a gap rather than
  # swallowed.
  SCOPE_MATCHERS="$(jq -c --argjson allowed "$(ours_spellings scope-hook)" "[.hooks.PreToolUse[]?
      | select(any(.hooks[]?; $OURS_TEST))
      | .matcher // \"\"]" "$SETTINGS" 2>/dev/null)" || SCOPE_MATCHERS=""
  if [[ -z "$SCOPE_MATCHERS" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  the scope hook's wiring could not be READ from $SETTINGS, so whether the trunk
  rule runs is unknown. That is reported as a gap rather than as a pass: a check
  that could not run has not passed."
  elif [[ "$SCOPE_MATCHERS" == "[]" ]]; then
    WIRING_GAPS="$WIRING_GAPS
  the scope hook is not wired in PreToolUse at all, so the trunk rule never runs."
  else
    # An invalid regex in a matcher makes jq's test() throw. The status is
    # CARRIED so that failure becomes "could not be checked" below, never an
    # empty uncovered-list that reads as full coverage.
    SCOPE_UNCOVERED="$(printf '%s' "$SCOPE_MATCHERS" | jq -r '
      def norm: gsub(","; "|");
      def matchall: (. == "" or . == "*" or . == ".*");
      . as $ms
      | ["Write","Edit","MultiEdit","NotebookEdit"]
      | map(. as $t
            | select(($ms | any(matchall)) | not)
            | select(($ms | any(. as $m | ($t | test("^(" + ($m | norm) + ")$")))) | not))
      | join(", ")' 2>/dev/null)" || SCOPE_UNCOVERED="<unreadable>"
    if [[ "$SCOPE_UNCOVERED" == "<unreadable>" ]]; then
      WIRING_GAPS="$WIRING_GAPS
  the scope hook's matcher(s) $SCOPE_MATCHERS could not be evaluated as a
  pattern, so which tools they cover is unknown. Reported as a gap rather than a
  pass. Set the matcher to \"Write|Edit|MultiEdit|NotebookEdit\"."
    elif [[ -n "$SCOPE_UNCOVERED" ]]; then
      WIRING_GAPS="$WIRING_GAPS
  the scope hook's matcher(s) $SCOPE_MATCHERS do not cover: $SCOPE_UNCOVERED.
  Set that entry's matcher to
    \"Write|Edit|MultiEdit|NotebookEdit\"
  or a write through an uncovered tool reaches the trunk without tripping the
  scope rule."
    fi
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
  hook, 300 for the bypass deny, 60 for the
  re-grounding hook and 60 for the Stop hook."
  fi

  # RETIRED ENTRIES (spec 0144). The wiring check above asks whether a STAMPED hook
  # is wired, so an entry that runs a hook this release no longer stamps was never
  # a gap to it and was never seen. It is read here with the same predicate, so a
  # retired entry means exactly what a wired one means one check up; a command
  # word naming a retired hook at any OTHER path is a FORK, named and never edited.
  RETIRED_SPELLINGS="$(for h in $RETIRED_HOOKS; do ours_spellings "$h"; done | jq -s -c 'add')"
  RETIRED_ENTRIES="$(jq -r --argjson allowed "$RETIRED_SPELLINGS" '[.hooks | to_entries[] | .key as $ev | .value[]? | .hooks[]? | select('"$OURS_TEST"') | "\($ev): \(.command)"] | unique | .[]' "$SETTINGS" 2>/dev/null)" \
    || RETIRED_ENTRIES="<unreadable>"
  RETIRED_FORKS="$(jq -r --argjson allowed "$RETIRED_SPELLINGS" '[.hooks | to_entries[] | .key as $ev | .value[]? | .hooks[]? | select(('"$OURS_TEST"') | not) | select((.command // "") | split(" ")[0] | test("(^|/)(commit|close)-gate[.]sh\"?$")) | "\($ev): \(.command)"] | unique | .[]' "$SETTINGS" 2>/dev/null)" \
    || RETIRED_FORKS="<unreadable>"
fi

# THE VERDICT DELTA (spec 0176, I1). Computed here because everything the next
# push will be judged under is known now and nothing has been printed or written:
# the OLD side is the instance's stamped audit under its current configuration,
# the NEW side is this plugin's audit under the configuration --apply would
# write (the audit.baseline computed above, this plugin's version). Each walks
# from its OWN frame, because an explicit --since switches the frame off and the
# frame is exactly what an upgrade can move; the range of the last N merges
# bounds which refusals are printed. Two lists, both ways, and it writes nothing.
verdict_delta() { # verdict_delta -> prints the delta; exit status 0 when both sides were read
  local trunk tip c old new since nm nc inrange ol nl oldl newl only_new only_old l
  trunk="$(jq -r '.trunk // "main"' "$SDD" 2>/dev/null || printf 'main')" # fail-open-ok: an unreadable name falls back to main, and a trunk that is no branch refuses below
  tip="$(git -C "$INSTANCE" rev-parse --verify --quiet "refs/heads/${trunk}^{commit}" 2>/dev/null)" \
    || die "--delta: the recorded trunk $(obs_text "$trunk") is not a local branch here, so there is no history to compare. Nothing was written."
  [[ "$(git -C "$INSTANCE" rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]] \
    || die "--delta: this is a shallow clone, so the merges in the range may not be here to read. Nothing was written."
  obs_clone "$INSTANCE" "$trunk"; c="$OBS_CLONE"
  mkdir -p "$c/.claude" && cp "$SDD" "$c/.claude/sdd.json"
  read -r since nm nc <<< "$(obs_range "$c" "$trunk")"
  printf 'verdict delta (plugin %s against the audit this instance has stamped), read in a private clone; nothing was written.\n' "$PLUGIN_VERSION"
  obs_range_line "$c" "$trunk" "$since" "$nm" "$nc"
  inrange="$(git -C "$c" log --first-parent --format=%h "$since..$trunk")"
  oldl=""
  if [[ -f "$INSTANCE/.claude/hooks/trunk-audit.sh" ]]; then
    obs_audit "$INSTANCE/.claude/hooks/trunk-audit.sh" "$c"; old="$OBS_AUDIT_OUT"
    printf 'the stamped audit:  %s\n' "$(obs_text "$(printf '%s\n' "$old" | grep -m1 -E '^  since: ' | sed 's/^  //')")"
    if [[ "$OBS_AUDIT_RC" -ge 2 ]]; then
      printf '  it could not read this history (exit %s): %s\n' "$OBS_AUDIT_RC" "$(obs_text "$(printf '%s\n' "$old" | tail -n1)")"
    else
      oldl="$(obs_refusals "$old" "$inrange" | sort -u)"
    fi
  else
    printf 'the stamped audit:  none (.claude/hooks/trunk-audit.sh is not in this instance), so only the new side is printed.\n'
  fi
  jq --arg v "$PLUGIN_VERSION" --arg b "${AUDIT_BASELINE_WRITE:-}" \
    '.plugin = ((.plugin // {}) + {version: $v}) | if $b != "" then .audit = ((.audit // {}) + {baseline: $b}) else . end' \
    "$SDD" > "$c/.claude/sdd.json" 2>/dev/null \
    || die "--delta: could not write the upgraded configuration into the private clone. Nothing was written in the instance."
  obs_audit "$SCRIPT_DIR/trunk-audit.sh" "$c"; new="$OBS_AUDIT_OUT"
  printf 'this plugin'"'"'s audit: %s%s\n' "$(obs_text "$(printf '%s\n' "$new" | grep -m1 -E '^  since: ' | sed 's/^  //')")" \
    "$([[ -n "${AUDIT_BASELINE_WRITE:-}" ]] && printf ' (under the audit.baseline --apply would record, %s)' "$(git -C "$c" rev-parse --short "$AUDIT_BASELINE_WRITE" 2>/dev/null)")"
  if [[ "$OBS_AUDIT_RC" -ge 2 ]]; then
    printf '  it could not read this history (exit %s): %s\n' "$OBS_AUDIT_RC" "$(obs_text "$(printf '%s\n' "$new" | tail -n1)")"
    return 1
  fi
  newl="$(obs_refusals "$new" "$inrange" | sort -u)"
  ol="$(cut -f1,2 <<< "$oldl" | sort -u)"; nl="$(cut -f1,2 <<< "$newl" | sort -u)"
  only_new="$(comm -13 <(printf '%s\n' "$ol") <(printf '%s\n' "$nl") | grep -v '^$' || true)" # fail-open-ok: an empty difference is the answer "none", printed below
  only_old="$(comm -23 <(printf '%s\n' "$ol") <(printf '%s\n' "$nl") | grep -v '^$' || true)" # fail-open-ok: as above
  printf 'the new edition would refuse, the old allowed:\n'
  if [[ -z "$only_new" ]]; then printf '  none\n'; else
    while IFS= read -r l; do
      printf '  %s %s  %s\n' "${l%%	*}" "$(grep -F -m1 "$l	" <<< "$newl" | cut -f3)" "$(obs_text "$(git -C "$c" log -1 --format=%s "${l%%	*}")")"
    done <<< "$only_new"
  fi
  printf 'the old refused, the new allows:\n'
  if [[ -z "$only_old" ]]; then printf '  none\n'; else
    while IFS= read -r l; do
      printf '  %s %s  %s\n' "${l%%	*}" "$(grep -F -m1 "$l	" <<< "$oldl" | cut -f3)" "$(obs_text "$(git -C "$c" log -1 --format=%s "${l%%	*}")")"
    done <<< "$only_old"
  fi
  printf 'A report: it refuses nothing. Read it before --apply, so the next push meets no surprise.\n'
  return 0
}
if [[ "$REPORT_MODE" == "delta" ]]; then
  verdict_delta || exit 1
  exit 0
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
# The forge check and its workflow are reported the same way (2.6.0, spec
# 0132): the check is a delivered file beside the audit; the workflow is
# WIRING and is delivered only when absent, because an instance that edited
# its workflow (a runner label, a matrix) keeps its edit, and the workflow
# carries no mechanism byte to go stale.
FC_DEST="$INSTANCE/.claude/hooks/forge-check.sh"
FC_NOTE=""
if [[ -f "$ROOT/scripts/forge-check.sh" ]]; then
  if [[ ! -f "$FC_DEST" ]]; then FC_NOTE="missing, would be delivered"
  elif ! cmp -s "$ROOT/scripts/forge-check.sh" "$FC_DEST"; then FC_NOTE="bytes differ, would be REPLACED"
  fi
fi
[[ -n "$FC_NOTE" ]] && printf '  .claude/hooks/forge-check.sh: %s\n' "$FC_NOTE"
FCW_SRC="$ROOT/templates/root/.github/workflows/setlist-forge-check.yml"
FCW_DEST="$INSTANCE/.github/workflows/setlist-forge-check.yml"
FCW_NOTE=""
if [[ -f "$FCW_SRC" ]]; then
  if [[ ! -f "$FCW_DEST" ]]; then FCW_NOTE="missing, would be delivered (wiring: the required check's workflow)"
  elif ! cmp -s "$FCW_SRC" "$FCW_DEST"; then FCW_NOTE="differs from the template and is LEFT AS IS (wiring, not mechanism; the check it runs is refreshed above)"
  fi
fi
[[ -n "$FCW_NOTE" ]] && printf '  .github/workflows/setlist-forge-check.yml: %s\n' "$FCW_NOTE"
# THE QUESTION IS COVERAGE, NOT A SPELLING (spec 0157, SD12; the 2.9.0 leg's
# F14). This tested one regex, `^[[:space:]]*/\.github/([[:space:]]|$)`, and so
# it was wrong in both directions at once: a strictly BROADER rule
# (`.github/**`, or a catch-all `*`) was reported as missing, and an OWNERLESS
# `/.github/` line silenced it while leaving the path owned by nobody.
#
# What a reader of the report actually needs to know is whether a change under
# .github/ requires an owner's review, and in CODEOWNERS that is decided by the
# LAST matching line: a later ownerless line takes the path back out of an
# earlier owner's hands. So this walks every line, keeps the last one whose
# pattern covers the path, and answers with whether THAT line names an owner.
#
# The covering patterns are enumerated rather than glob-matched, because a
# CODEOWNERS pattern language re-implemented here would be a second place to be
# wrong: `*`, `.github`, `/.github`, and each of those directory spellings with
# a trailing slash or a trailing `/**`. A narrower rule (`/.github/workflows/`)
# or a single-level one (`/.github/*`) does NOT cover the path, and the note
# fires, which is the safe direction: the team is told to add a line.
codeowners_covers_github() { # codeowners_covers_github <file> -> 0 when .github/ is owned
  awk '
    { sub(/#.*/, "") }
    { gsub(/^[[:space:]]+|[[:space:]]+$/, "") }
    $0 == "" { next }
    {
      p = $1
      sub(/\/\*\*$/, "", p)
      sub(/\/$/, "", p)
      sub(/^\//, "", p)
      if (p == ".github" || $1 == "*") { owned = (NF >= 2) }
    }
    END { exit(owned ? 0 : 1) }
  ' "$1" 2>/dev/null
}

# The ownership file rides the same rule as the workflow (T1, 2.6.0): wiring
# the team edits (the @OWNER slot is theirs to fill), delivered when absent and
# otherwise left as is.
CO_SRC="$ROOT/templates/root/github/CODEOWNERS.tmpl"
CO_DEST="$INSTANCE/.github/CODEOWNERS"
CO_NOTE=""
if [[ -f "$CO_SRC" ]]; then
  if [[ ! -f "$CO_DEST" ]]; then CO_NOTE="missing, would be delivered (wiring: the ownership file with its @OWNER slot)"
  elif ! cmp -s "$CO_SRC" "$CO_DEST"; then
    CO_NOTE="differs from the template and is LEFT AS IS (the team fills its slot and owns its edits)"
    # Amendment 5 (2026-09-07): an instance stamped between T1 and the fourth
    # path carries three. The leave stands (ruling 2); the report SAYS what
    # the file lacks, by path, so the team adds the line under its own owner
    # rather than diffing the template to find out.
    codeowners_covers_github "$CO_DEST" \
      || CO_NOTE="$CO_NOTE; no line in it puts the fourth protected path /.github/ under an owner (2.6.0 amendment 5: the check's workflow, the ownership file and the issue form), which the team adds under its own owner"
  fi
fi
[[ -n "$CO_NOTE" ]] && printf '  .github/CODEOWNERS: %s\n' "$CO_NOTE"
# The displacement warning is printed WHENEVER apply would refuse, not only
# when boundary files also happen to differ (round 9, finding 3: a current
# boundary behind an unreadable directory reported "present and
# byte-identical, config already set" while apply refused).
if [[ -n "$FOREIGN_HOOKSPATH" && -z "$GITHOOKS_SKIP_NOTE" && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]]; then
  if [[ "$SD2_OURS_EDITED" -eq 1 ]]; then
    printf 'the git-hook boundary: --apply will REFUSE: git already runs Setlist'"'"'s own %s, and the file(s) in it do not match any Setlist release byte for byte:%s (a customised stamped hook, or a foreign file under a Setlist name; this check cannot tell them apart).\n' "$FOREIGN_HOOKSPATH_SHOWN" " ${FOREIGN_HOOK_NAMES% }"
  elif [[ "$CHAIN_MODE" -eq 1 ]]; then
    printf 'the git-hook boundary: --apply will CHAIN the hook layer that runs from %s: git runs one hooks directory, so Setlist arms .githooks and each Setlist git hook then runs that layer'"'"'s hook of the same name after its own verdict, both refusals surfacing (recorded as "hooks_chain" in .claude/sdd.json).\n' "$FOREIGN_HOOKSPATH_SHOWN"
  else
    printf 'the git-hook boundary: --apply will REFUSE: a hook layer that is not Setlist'"'"'s (or cannot be verified) runs from, or would be switched on at, %s.\n' "$FOREIGN_HOOKSPATH_SHOWN"
  fi
fi
if [[ -n "$AUDIT_BASELINE_NOTE" ]]; then
  printf '  .claude/sdd.json audit.baseline (the trunk audit'"'"'s frame): %s\n' "$AUDIT_BASELINE_NOTE"
fi
if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
  printf 'the git-hook boundary: NOT ARMED here and will not be: %s\n' "$GITHOOKS_SKIP_NOTE"
elif [[ -n "$GH_NEW" || -n "$GH_CHANGED" || -n "$GH_CFG_NEEDED" ]]; then
  printf 'the git-hook boundary (this is the layer that carries the guarantee):\n'
  [[ -n "$GH_NEW" ]]     && printf '  missing, would be delivered:%s\n' "$GH_NEW"
  [[ -n "$GH_CHANGED" ]] && printf '  bytes differ, would be replaced (the previous file is kept as .setlist-backup):%s\n' "$GH_CHANGED"
  [[ -n "$GH_CFG_NEEDED" ]] && printf '  git config still to set:%s   (without BOTH of these the hooks are inert)\n' "$GH_CFG_NEEDED"
  if [[ -n "$FOREIGN_HOOKSPATH" && "$SD2_OURS_EDITED" -eq 1 ]]; then
    printf '  WOULD REPLACE FILES THAT ARE NOT THIS RELEASE%ss:%s in %s\n' "'" " ${FOREIGN_HOOK_NAMES% }" "$FOREIGN_HOOKSPATH_SHOWN"
    printf '    git already runs that directory, so nothing is switched off; what changes is\n'
    printf '    the bytes of the hook(s) above. --apply REFUSES rather than overwrite an edit\n'
    printf '    it cannot distinguish from a foreign file. Re-run with SETLIST_ADOPT_HOOKSPATH=1\n'
    printf '    to take this plugin%ss versions (the previous file is kept as .setlist-backup).\n' "'"
  elif [[ "$CHAIN_MODE" -eq 1 ]]; then
    printf '  WOULD CHAIN ANOTHER HOOK LAYER: hooks that are not Setlist%ss run from %s (foreign: %s)\n' "'" "$FOREIGN_HOOKSPATH_SHOWN" "${FOREIGN_HOOK_NAMES% }"
    printf '    git runs one hooks directory, so --apply arms .githooks and records that\n'
    printf '    layer as "hooks_chain" in .claude/sdd.json; each Setlist git hook runs the\n'
    printf '    layer%ss hook of the same name after its own verdict, and both refusals print.\n' "'"
    [[ -z "${CHAIN_NAMES// /}" ]] || printf '    Pass-throughs would be written for the names Setlist does not stamp:%s\n' " ${CHAIN_NAMES% }"
    printf '    SETLIST_ADOPT_HOOKSPATH=1 displaces the layer instead, chaining nothing.\n'
  elif [[ -n "$FOREIGN_HOOKSPATH" ]]; then
    printf '  WOULD DISPLACE ANOTHER HOOK LAYER: hooks that are not Setlist%ss already run from %s\n' "'" "$FOREIGN_HOOKSPATH_SHOWN"
    printf '    git runs one hook layer, so arming Setlist here SWITCHES THAT OFF. This is\n'
    printf '    true whether core.hooksPath points there or it is the default .git/hooks\n'
    printf '    (where pre-commit and lefthook install themselves with hooksPath unset).\n'
    printf '    Whatever runs from %s stops running: often gitleaks, detect-secrets\n' "$FOREIGN_HOOKSPATH_SHOWN"
    printf '    or commit-msg validation. --apply REFUSES rather than do this silently.\n'
    printf '    Decide deliberately: move those checks into %s/, or re-run with\n' ".githooks"
    printf '    SETLIST_ADOPT_HOOKSPATH=1 to displace %s on purpose.\n' "$FOREIGN_HOOKSPATH_SHOWN"
  fi
else
  printf 'the git-hook boundary: present and byte-identical, config already set.\n'
fi
if [[ -n "$WIRING_GAPS" ]]; then
  printf 'settings wiring, NOT refreshed by this script (it holds your own permissions and model settings):%s\n' "$WIRING_GAPS"
fi
# THE EDITION AND BINDING DRIFT REPORT (spec 0153, SKEW part B; spec 0149
# section 5 and the owner's ruling 6 of 2026-09-17, which put it here rather
# than in a new file). Printed in report mode and under --apply alike, and like
# the retired-hooks report below it changes NO exit status.
#
# THE CLASS, MEASURED THREE TIMES BEFORE THIS ARM EXISTED. An instance ran four
# plugin versions and four editions behind its stamp with nothing surfacing it.
# An instance upgraded to v1.14 kept a CLAUDE.md header naming v1.6, because the
# CLAUDE.md rewrite is delta-driven and a stale edition string in phase-2 prose
# is in no delta. And this plugin's own `new` skill told session zero to run
# `/model opus` on the escalation tier while Part 2's bindings table bound that
# tier to `fable`. Text that names a version or a model is a SECOND COPY of
# something setlist.md already holds, and a second copy drifts.
#
# ONE VALUE, READ, NEVER COPIED. The new edition is read from the committed
# setlist.md at this plugin's root, and the bindings from Part 2's table in the
# same file, by the tier name in column 1 and the backticked aliases in column
# 2. Nothing here holds an edition string or a model alias: a check that held
# either would be this drift class itself, one layer down, and the suite asserts
# the absence over these bytes rather than trusting the sentence.
#
# THE FAMILY NAMES IN THE BINDING CELLS ARE NOT THE VOCABULARY, and that is a
# measured decision rather than a simplification: the escalation cell names Opus
# twice in prose about what Fable sits above, so reading family names would put
# `opus` in the escalation set and make the exact drift this arm was built to
# catch invisible to it. Backticked aliases only.
#
# WHAT IT READS: the instance's CLAUDE.md, AGENTS.md (spec 0176), RUNBOOK.md,
# specs/TEMPLATE.md and every markdown file under .claude/skills/. History is excluded by RULE, not by
# judgement: ADRs, journal/ and closed specs are not in the set at all, and
# inside the set a fenced code block or a blockquote is not compared, with the
# number of lines skipped for that reason PRINTED rather than dropped.
#
# THE WINDOW FOR A BINDING CLAIM IS THE SENTENCE, cut at ". " inside a paragraph
# whose wrapped lines are joined first, because these files wrap prose at their
# own width and a line-sized window splits "the escalation tier ... /model opus"
# in half. A sentence naming MORE THAN ONE tier restates Part 2's table rather
# than claiming one tier's binding, so it is not compared; it is printed with
# its file and line, on the same rule as every other thing this project skips.
#
# IT NEVER WRITES AND NEVER EDITS. Rewriting text in someone's repository is
# their act, on the same precedent as the retired-hooks report. What holds the
# migration chore open is the upgrade skill's step, which quotes this output.
EDITION_SRC="$ROOT/setlist.md"
DRIFT_ED=""
DRIFT_BIND=""
if [[ -f "$EDITION_SRC" ]]; then
  DRIFT_ED="$(grep -oE '^\*\*Edition v[0-9]+\.[0-9]+' "$EDITION_SRC" | head -n1 | grep -oE 'v[0-9]+\.[0-9]+' || true)" # fail-open-ok: an edition header this grep cannot find yields the empty string, and the guard below runs the whole report only when BOTH the edition and the bindings were read, so an unreadable edition reports nothing rather than comparing against nothing
  DRIFT_BIND="$(awk -F'|' '
    /^\| Tier \| Binding \|/ { f = 1; next }
    f && /^\|[[:space:]]*---/ { next }
    f && /^\|/ {
      t = $2
      gsub(/^[ \t]+|[ \t]+$/, "", t)
      n = split($3, p, "`")
      printf "%s:", tolower(t)
      for (i = 2; i <= n; i += 2) printf " %s", p[i]
      printf ";"
    }
    f && !/^\|/ { f = 0 }
  ' "$EDITION_SRC")"
fi
DRIFT_SET=()
# AGENTS.md since spec 0176 (C-58): an agent that reads only AGENTS.md is primed
# by it, so a stale edition there is the same drift as one in CLAUDE.md.
for f in CLAUDE.md AGENTS.md RUNBOOK.md specs/TEMPLATE.md; do
  [[ -f "$INSTANCE/$f" ]] && DRIFT_SET[${#DRIFT_SET[@]}]="$INSTANCE/$f"
done
if [[ -d "$INSTANCE/.claude/skills" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && DRIFT_SET[${#DRIFT_SET[@]}]="$f"
  done <<EOF
$(find "$INSTANCE/.claude/skills" -type f -name '*.md' 2>/dev/null | sort)
EOF
fi
if [[ -n "$DRIFT_ED" && -n "$DRIFT_BIND" && "${#DRIFT_SET[@]}" -gt 0 ]]; then
  DRIFT_RAW="$(awk -v NEWED="$DRIFT_ED" -v BIND="$DRIFT_BIND" '
BEGIN {
  nb = split(BIND, rows, ";")
  for (i = 1; i <= nb; i++) {
    if (rows[i] == "") continue
    p = index(rows[i], ":")
    t = substr(rows[i], 1, p - 1)
    al = substr(rows[i], p + 1)
    tierset[t] = " " al " "
    na = split(al, aa, " ")
    for (j = 1; j <= na; j++) if (aa[j] != "") vocab[aa[j]] = 1
  }
  ntier = split("planning execution escalation", TIERS, " ")
  skipped = 0; np = 0
}
function paraline(pat,   a) {
  for (a = 1; a <= np; a++) if (index(tolower(ptext[a]), pat) > 0) return pline[a]
  return pline[1]
}
function flushpara(   i, J, ns, s, low, k, tname, seen, cand, nc, c, tok, ln, rest) {
  if (np == 0) return
  J = ""
  for (i = 1; i <= np; i++) J = (J == "" ? ptext[i] : J " " ptext[i])
  gsub(/\. /, "\001", J)
  ns = split(J, SENT, "\001")
  for (s = 1; s <= ns; s++) {
    low = tolower(SENT[s])
    tname = ""; seen = 0
    for (k = 1; k <= ntier; k++)
      if (index(low, TIERS[k] " tier") > 0) { seen++; if (tname == "") tname = TIERS[k] }
    if (seen == 0) continue
    if (seen > 1) { printf "M\t%s\t%d\n", pfile, paraline(tname " tier"); continue }
    cand = ""
    rest = low
    while (match(rest, /`[^`]*`/)) {
      cand = cand " " substr(rest, RSTART + 1, RLENGTH - 2)
      rest = substr(rest, RSTART + RLENGTH)
    }
    rest = low
    while (match(rest, /\/model[ \t]+[a-z0-9_.-]+/)) {
      c = substr(rest, RSTART, RLENGTH)
      sub(/^\/model[ \t]+/, "", c)
      cand = cand " " c
      rest = substr(rest, RSTART + RLENGTH)
    }
    gsub(/\/model/, " ", cand)
    nc = split(cand, CW, /[^a-z0-9_.-]+/)
    for (c = 1; c <= nc; c++) {
      tok = CW[c]
      if (tok == "" || !(tok in vocab)) continue
      if (index(tierset[tname], " " tok " ") > 0) continue
      ln = paraline(tok)
      if ((pfile SUBSEP ln SUBSEP tok) in reported) continue
      reported[pfile SUBSEP ln SUBSEP tok] = 1
      printf "B\t%s\t%d\t%s\t%s\n", pfile, ln, tok, tname
    }
  }
  np = 0
}
# A FENCE, read the way CommonMark reads one (spec 0154, fix round 1; findings
# F5 and F7 of the 2.9.0 leg): up to three spaces, then a run of at least three backticks or
# tildes. It closes only on the SAME character at a run at least as long, with
# nothing after it. Four spaces or a tab before the marker make it text, not a
# delimiter. A fence still open at the end of a file is a GAP, reported by file
# and line, never a clean read.
function fencerun(s,   i, n, c) {
  i = 1
  while (substr(s, i, 1) == " ") i++
  if (i > 4) return 0
  c = substr(s, i, 1)
  if (c != "`" && c != "~") return 0
  n = 0
  while (substr(s, i + n, 1) == c) n++
  if (n < 3) return 0
  FR_CHAR = c; FR_LEN = n; FR_REST = substr(s, i + n)
  return 1
}
function fencegap() {
  if (infence) printf "U\t%s\t%d\n", pfile, fstart
  infence = 0
}
FNR == 1 { flushpara(); fencegap(); pfile = FILENAME }
{
  line = $0
  if (infence) {
    if (fencerun(line) && FR_CHAR == fchar && FR_LEN >= flen && FR_REST ~ /^[[:space:]]*$/) infence = 0
    skipped++; next
  }
  if (fencerun(line) && !(FR_CHAR == "`" && index(FR_REST, "`") > 0)) {
    flushpara(); infence = 1; fchar = FR_CHAR; flen = FR_LEN; fstart = FNR; skipped++; next
  }
  if (line ~ /^[[:space:]]*>/) { flushpara(); skipped++; next }
  if (line ~ /^[[:space:]]*$/) { flushpara(); next }
  low = tolower(line); off = 0
  while (match(low, /edition v[0-9]+\.[0-9]+/)) {
    ver = substr(low, RSTART, RLENGTH); ver = substr(ver, index(ver, "v"))
    if (ver != tolower(NEWED))
      printf "E\t%s\t%d\t%s\n", FILENAME, FNR, substr(line, off + RSTART, RLENGTH)
    off = off + RSTART + RLENGTH - 1
    low = substr(low, RSTART + RLENGTH)
  }
  np++; ptext[np] = line; pline[np] = FNR
}
END { flushpara(); fencegap(); printf "S\t%d\n", skipped }
' "${DRIFT_SET[@]}")"
  DRIFT_FINDINGS="$(printf '%s\n' "$DRIFT_RAW" | grep -E '^(E|B)	' || true)" # fail-open-ok: grep exits 1 when the awk pass found no drift, which is the CLEAN case and the only case this discards; the block below prints nothing for an empty value, which is what a clean instance should see
  if [[ -n "$DRIFT_FINDINGS" ]]; then
    printf 'edition and binding drift, REPORTED and never rewritten by this script (the words are yours):\n'
    printf '  the edition this refresh moves you to is %s, and Part 2 binds the tiers as: %s\n' \
      "$DRIFT_ED" "$(printf '%s' "$DRIFT_BIND" | sed -e 's/;$//' -e 's/;/; /g')"
    printf '%s\n' "$DRIFT_FINDINGS" | while IFS="$(printf '\t')" read -r kind file line found tier; do
      rel="${file#$INSTANCE/}"
      case "$kind" in
        E) printf '  %s:%s [SLH-EDITION-DRIFT] names "%s"; the edition this instance is moving to is %s.\n' \
             "$rel" "$line" "$found" "$DRIFT_ED" ;;
        B) printf '  %s:%s [SLH-BINDING-DRIFT] names the %s tier beside "%s"; Part 2 binds that tier to:%s.\n' \
             "$rel" "$line" "$tier" "$found" \
             "$(printf '%s' "$DRIFT_BIND" | tr ';' '\n' | sed -n "s/^$tier://p")" ;;
      esac
    done
    printf '  Each line above is a second copy of something setlist.md already holds, and a second copy drifts:\n'
    printf '  that is how an instance comes to describe a protocol it is no longer running. Rewrite a\n'
    printf '  current-state sentence to the value named beside it; where the text is a provenance citation\n'
    printf '  (the edition a field arrived in), record it as reconciled in the umbrella ADR. The migration\n'
    printf '  chore does not close while a listed line stands.\n'
    # fail-open-ok: grep exits 1 when no sentence named more than one tier, which is the ordinary case; an empty value prints no "not compared" line, and the drift lines themselves are unaffected
    DRIFT_MULTI="$(printf '%s\n' "$DRIFT_RAW" | grep -E '^M	' | awk -F'\t' -v inst="$INSTANCE/" '{ f = $2; sub(inst, "", f); printf "%s%s:%s", (NR > 1 ? ", " : ""), f, $3 }' || true)"
    [[ -n "$DRIFT_MULTI" ]] && \
      printf '  These sentences name more than one tier and restate Part 2 rather than claim one tier, so they\n  were not compared: %s\n' "$DRIFT_MULTI"
  fi
  # THE COUNT OF WHAT WAS NOT READ, AND ANY FILE NOT READ TO ITS END, printed
  # whether or not a line was listed (spec 0154, fix round 1; the 2.9.0 leg's F7):
  # the run that lists nothing is the one where a reader most needs to know what
  # it did not compare. Under the drift block when there is one; under its own
  # lead-in when there is not, so a clean instance still draws no drift block.
  DRIFT_SKIPPED="$(printf '%s\n' "$DRIFT_RAW" | sed -n 's/^S	//p' | head -n1)"
  # fail-open-ok: grep exits 1 when every fence closed, the ordinary case; an empty value prints no gap line
  DRIFT_GAPS="$(printf '%s\n' "$DRIFT_RAW" | grep -E '^U	' || true)"
  if [[ "${DRIFT_SKIPPED:-0}" -gt 0 || -n "$DRIFT_GAPS" ]]; then
    [[ -n "$DRIFT_FINDINGS" ]] || printf 'drift report: no stale edition or binding line was found in the text it compared.\n'
    [[ "${DRIFT_SKIPPED:-0}" -gt 0 ]] && \
      printf '  %s line(s) inside a code fence or a blockquote were not compared (history is excluded by rule).\n' "$DRIFT_SKIPPED"
    [[ -n "$DRIFT_GAPS" ]] && printf '%s\n' "$DRIFT_GAPS" | while IFS="$(printf '\t')" read -r kind file line; do
      printf '  %s:%s opens a code fence that never closes, so no line after it was compared: that file was NOT read to its end.\n' \
        "${file#$INSTANCE/}" "$line"
    done
  fi
  # THE OTHER HALF OF THE QUESTION, NAMED (spec 0178, C-67). Claude Code 2.1.283's
  # /doctor prompt-audit reads the same kinds of file for prompts written for older
  # models and for stale paths; this report reads them for what the edition binds.
  # One line, printed whenever the report ran, so a reader knows which tool asks which.
  printf 'model-era wording is not what this report reads: Claude Code'"'"'s /doctor prompt-audit (2.1.283 and later) reads the same files for prompts written for older models and for stale paths, and this report reads them for what the edition binds.\n'
fi
# WHAT LOADS FROM OUTSIDE THE INSTANCE, NAMED (spec 0176, C-55; ruling O-12,
# report-only). Claude Code loads the user's own skills and plugins, and the
# ones the account syncs onto this machine, into every session here, beside the
# instance's. No Setlist reader compares them: the drift report above reads the
# instance's files only. So a stale edition claim or model binding living there
# is not in any report, and this block at least NAMES what loaded, by directory
# or install key only, reading no content. Printed in report mode and under
# --apply alike; it changes no exit status. The paths are the ones measured on
# Claude Code 2.1.284: skills/<name>/ and skills/synced/<bucket>/<name>/;
# plugins/installed_plugins.json's plugin keys and plugins/synced/<bucket>/<name>/.
outside_names() { # outside_names <dir> [depth-2] -> the directory names under it, one per line, dot-files and files excluded
  local d="$1" e
  [[ -d "$d" ]] || return 0
  for e in "$d"/*/; do
    [[ -d "$e" ]] || continue
    e="${e%/}"; e="${e##*/}"
    [[ "$e" == "synced" ]] && continue
    if [[ -n "${2:-}" ]]; then outside_names "$d/$e"; else printf '%s\n' "$e"; fi
  done
}
outside_line() { # outside_line <label> <names> -> one report line, at most 20 names and the rest counted
  local n=0 out="" l
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    n=$((n + 1))
    [[ "$n" -le 20 ]] && out="${out:+$out, }$(printf '%s' "$l" | tr -d '\000-\037\177' | cut -c1-80)"
  done <<< "$2"
  [[ "$n" -gt 0 ]] || return 0
  [[ "$n" -gt 20 ]] && out="$out and $((n - 20)) more"
  printf '  %s: %s\n' "$1" "$out"
}
OUTSIDE_BASE="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
OUTSIDE_PLUGINS=""
if [[ -f "$OUTSIDE_BASE/plugins/installed_plugins.json" ]]; then
  OUTSIDE_PLUGINS="$(jq -r '(.plugins // {}) | keys[]' "$OUTSIDE_BASE/plugins/installed_plugins.json" 2>/dev/null || printf '(installed_plugins.json could not be read)\n')" # fail-open-ok: an unreadable file is named as unreadable, never as empty
fi
OUTSIDE_TEXT="$(outside_line 'your skills' "$(outside_names "$OUTSIDE_BASE/skills")")
$(outside_line 'skills synced from your account' "$(outside_names "$OUTSIDE_BASE/skills/synced" 2)")
$(outside_line 'your plugins' "$OUTSIDE_PLUGINS")
$(outside_line 'plugins synced from your account' "$(outside_names "$OUTSIDE_BASE/plugins/synced" 2)")"
OUTSIDE_TEXT="$(grep -v '^$' <<< "$OUTSIDE_TEXT" || true)" # fail-open-ok: no names at all is the empty answer, and nothing is printed for it
if [[ -n "$OUTSIDE_TEXT" ]]; then
  printf 'outside this instance, and read by no Setlist check (they load into every Claude Code session on this machine; a stale edition or model binding in them is not in any report above):\n'
  printf '%s\n' "$OUTSIDE_TEXT"
fi
# THE RETIRED-HOOKS REPORT (spec 0144; spec 0142 section 10, ruling R-D). Printed in
# report mode and under --apply alike, and it changes no exit status: a stale
# advisory gate PERMITS, the git hooks carry every refusal, so nothing this release
# promises is out of force, and removing files from someone's repository is the
# owner's act. The edit is printed between two fixed lines so it can be run as
# printed, and the suite runs it exactly that way.
RETIRED_JQ='def retired_entry: ((.type // "command") == "command") and ((.command // "") as $c | (($retired | index($c)) != null) or (($retired | index($c | split(" ")[0])) != null)); .hooks |= with_entries(((.value // []) | length) as $n | .value |= ((. // []) | map(if ((.hooks | type) == "array") and any(.hooks[]; retired_entry) then (.hooks |= map(select(retired_entry | not))) | select((.hooks | length) > 0) else . end)) | select(($n == 0) or ((.value | length) > 0)))'
if [[ -n "$RETIRED_FILES" || ( -n "${RETIRED_ENTRIES:-}" && "${RETIRED_ENTRIES:-}" != "<unreadable>" ) || ( -n "${RETIRED_FORKS:-}" && "${RETIRED_FORKS:-}" != "<unreadable>" ) ]]; then
  printf 'retired hooks, NOT removed by this script (removing files from your repository is yours to do):\n'
  [[ -n "$RETIRED_FILES" ]] && printf '  these hooks were retired with 2.8.0 and are still in this instance:%s\n' "$RETIRED_FILES"
  if [[ "${RETIRED_ENTRIES:-}" == "<unreadable>" ]]; then
    printf '  whether .claude/settings.json still runs them could not be read, so the edit below removes the files only.\n'
  elif [[ -n "${RETIRED_ENTRIES:-}" ]]; then
    printf '  .claude/settings.json still runs them:\n'
    printf '%s\n' "$RETIRED_ENTRIES" | sed 's/^/    /'
  fi
  printf '  They are the commit and close gates, advisory parsers whose questions the git hooks now answer;\n'
  printf '  left in place they keep running on every Bash call. If you changed either file, keep a copy first.\n'
  if [[ -n "$RETIRED_FILES" || ( -n "${RETIRED_ENTRIES:-}" && "${RETIRED_ENTRIES:-}" != "<unreadable>" ) ]]; then
    printf '  To remove exactly what is named here and nothing else, run from the instance root:\n'
    printf '  --- the edit, verbatim ---\n'
    [[ -n "$RETIRED_FILES" ]] && printf '    rm -f --%s\n' "$RETIRED_FILES"
    if [[ -n "${RETIRED_ENTRIES:-}" && "${RETIRED_ENTRIES:-}" != "<unreadable>" ]]; then
      RETIRED_SPELLINGS_Q="${RETIRED_SPELLINGS//\'/\'\\\'\'}"
      printf "    jq --argjson retired '%s' '%s' .claude/settings.json > .claude/settings.json.new && mv .claude/settings.json.new .claude/settings.json\n" "$RETIRED_SPELLINGS_Q" "$RETIRED_JQ"
    fi
    printf '  --- end of the edit ---\n'
  fi
  if [[ -n "${RETIRED_FORKS:-}" && "${RETIRED_FORKS:-}" != "<unreadable>" ]]; then
    printf '  a FORK of a retired hook is wired, and the edit above leaves it alone:\n'
    printf '%s\n' "$RETIRED_FORKS" | sed 's/^/    /'
    printf '  Setlist no longer ships the file it was forked from; keep it, or delete it and its entry yourself.\n'
  fi
fi
# THE gates BLOCK MIGRATION (P2, 2.6.0; design section 8 as amended by the
# owner's ruling of 2026-09-07, spec 0132 "What the contract left open" 5). An
# instance stamped before the block reads, through the library's one reader,
# exactly as if the block said {commit: "", close: gate_command, push:
# gate_command}; --apply WRITES that block so the shape is visible and
# editable, and no verdict changes. A present block is left alone. A block the
# reader would refuse (SLH-GATES-SHAPE) is reported here and left alone too: a
# declaration somebody wrote is not this script's to rewrite. Computed HERE,
# before the report, so report mode and apply mode describe the same future.
GATES_WRITE=0
GATES_STATE="$(jq -r 'if (.gates == null) then "absent" elif ((.gates | type) != "object") then "shape" elif ([.gates.commit, .gates.close, .gates.push] | map(type == "string") | all) then "present" else "shape" end' "$SDD" 2>/dev/null || printf 'unreadable')" # fail-open-ok: an unreadable answer is reported below and nothing is written for it
GATES_SINGLE="$(jq -r '.gate_command // ""' "$SDD" 2>/dev/null || printf '')" # fail-open-ok: the value is only echoed into the report; the write reads the file again through jq
case "$GATES_STATE" in
  absent)
    GATES_WRITE=1
    printf '.claude/sdd.json: no gates block (the three gate tiers, 2.6.0); --apply writes {"commit": "", "close": "%s", "push": "%s"}, the single gate_command at the close and push tiers and nothing at commit, which is what the hooks already read for an absent block, so no verdict changes.\n' "$GATES_SINGLE" "$GATES_SINGLE" ;;
  shape)
    printf '.claude/sdd.json: the gates block is not an object of three string tiers (commit, close, push), so the hooks refuse SLH-GATES-SHAPE until it is written as {"commit": "", "close": "<the full gate>", "push": "<the full suite>"} or removed; --apply LEAVES it as it is.\n' ;;
  present) ;;
  *)
    printf '.claude/sdd.json: the gates block could not be read; --apply leaves it as it is.\n' ;;
esac

# A ROLE PATH THAT HOLDS NOTHING IS NAMED (spec 0179, the owner's finding of
# 2026-09-29). Every layer judges code by the role paths, so a role that names a
# directory the repository does not have, or one that holds no tracked file,
# governs nothing while the instance reads armed: the shape a retrofit stamped
# with the default src and tests left on a project laid out otherwise. Reported
# in both modes, with the tracked files by top-level directory beside it (the
# retrofit skill's inventory scan, the same ranking, held equal by the suite);
# nothing is rewritten, because which directory holds the code is the operator's.
ROLE_SCAN_AWK='{ top = (NF > 1) ? $1 : "."; k = split($NF, part, "."); ext = (k > 1) ? tolower(part[k]) : "" } ext ~ /^(c|cc|cpp|cs|go|java|js|jsx|kt|m|mjs|php|py|rb|rs|scala|sh|swift|ts|tsx|vue|dart|ex|exs|clj|lua|r|sql|hs|ml|fs|elm|erl|zig)$/ { n[top]++ } END { for (d in n) printf "%d %s%s\n", n[d], d, (tolower(d) ~ /^(test|tests|spec|__tests__|e2e|testing)$/ ? " (tests)" : "") }'
ROLE_EMPTY=""
while IFS= read -r ROLE_R; do
  ROLE_R="${ROLE_R%/}"
  [[ -n "$ROLE_R" && "$ROLE_R" != "." ]] || continue
  if [[ ! -e "$INSTANCE/$ROLE_R" ]]; then
    ROLE_EMPTY="$ROLE_EMPTY \"$(obs_text "$ROLE_R")\" (does not exist)"
  elif git -C "$INSTANCE" rev-parse --git-dir >/dev/null 2>&1 \
       && [[ -z "$(git -C "$INSTANCE" ls-files -- "$ROLE_R" 2>/dev/null | head -n 1)" ]]; then
    ROLE_EMPTY="$ROLE_EMPTY \"$(obs_text "$ROLE_R")\" (holds no tracked file)"
  fi
done <<< "$(jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$SDD" 2>/dev/null)"
if [[ -n "$ROLE_EMPTY" ]]; then
  ROLE_TOP="$(git -C "$INSTANCE" ls-files 2>/dev/null | awk -F/ "$ROLE_SCAN_AWK" | sort -rn | head -n 5 | awk '{ $1 = $1 " source files in"; print }' | tr '\n' ';' | sed 's/;$/./; s/;/; /g')"
  printf '.claude/sdd.json: the role path%s, so no layer judges any code by it. The tracked source files by top-level directory (the retrofit inventory scan): %s Record the directories the code lives in as "roles" (each a string or a list of strings); nothing is rewritten here.\n' \
    "$ROLE_EMPTY" "$(obs_text "${ROLE_TOP:-none found.}")"
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

if [[ -n "$FOREIGN_HOOKSPATH" && -z "$GITHOOKS_SKIP_NOTE" && "$CHAIN_MODE" -eq 0 && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]] \
   && git -C "$INSTANCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # The reason that fits the shape decided at the top of this run (spec 0157,
  # SD2): the refusal itself is unchanged in both directions.
  if [[ "$SD2_OURS_EDITED" -eq 1 ]]; then
    die "refusing to arm: the hook layer git already runs from, $FOREIGN_HOOKSPATH_SHOWN, is Setlist's own directory, and these file(s) in it do not match any Setlist release byte for byte: ${FOREIGN_HOOK_NAMES% }. That is what a customised stamped hook looks like (the edition's Part 8c calls it a fork to surface), and it is also what a foreign file under a Setlist name looks like: this check decides by BYTES, deliberately, and cannot tell the two apart. Refreshing would replace them either way. Nothing has been changed. If you edited them, re-run with SETLIST_ADOPT_HOOKSPATH=1 to take this plugin's versions (the previous file is kept as .setlist-backup), or move your changes into a hook of your own; if they are another tool's, move those checks out of .githooks/ first."
  fi
    die "refusing to arm: a hook layer that is not Setlist's already runs from, or would be switched on at, $FOREIGN_HOOKSPATH_SHOWN (foreign: ${FOREIGN_HOOK_NAMES:-unresolvable}), and git runs one layer: arming Setlist (core.hooksPath=.githooks) would switch it off, silently taking whatever runs from $FOREIGN_HOOKSPATH_SHOWN with it (gitleaks, detect-secrets and commit-msg validation are commonly wired this way, and pre-commit and lefthook wire into .git/hooks with hooksPath unset). Nothing has been changed. Move those checks into .githooks/, or re-run with SETLIST_ADOPT_HOOKSPATH=1 to displace $FOREIGN_HOOKSPATH_SHOWN on purpose."
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
for h in $STAMPED_HOOKS trunk-audit forge-check; do
  ADV_UNSAFE="$(setlist_deliver_dest_unsafe "$INSTANCE" ".claude/hooks/$h.sh" 2>/dev/null)"
  [[ -z "$ADV_UNSAFE" ]] || die "refusing to refresh: $ADV_UNSAFE Nothing has been changed."
done
mkdir -p "$INSTANCE/.claude/hooks" \
  || die "could not create .claude/hooks in $INSTANCE; nothing was refreshed."
for h in $STAMPED_HOOKS; do
  ADV_NOTE="$(setlist_deliver_file "$HOOKS/$h.sh" "$INSTANCE" ".claude/hooks/$h.sh")" \
    || die "could not refresh .claude/hooks/$h.sh: ${ADV_NOTE:-the copy failed} Nothing has been recorded, so re-run once the cause is fixed."
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s\n' "$ADV_NOTE"
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
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s\n' "$ADV_NOTE"
  [[ -f "$INSTANCE/.claude/hooks/trunk-audit.sh" ]] || die "could not deliver trunk-audit.sh to .claude/hooks/; pre-push would refuse every push outside a Claude Code session."
fi
# The forge check, beside the audit, same rule (2.6.0, spec 0132); and its
# workflow, delivered only when absent (see the report above for why).
if [[ -f "$ROOT/scripts/forge-check.sh" ]]; then
  mkdir -p "$INSTANCE/.claude/hooks" # fail-open-ok: as above, the guarded delivery names the file if this failed
  ADV_NOTE="$(setlist_deliver_file "$ROOT/scripts/forge-check.sh" "$INSTANCE" ".claude/hooks/forge-check.sh")" \
    || die "could not deliver forge-check.sh to .claude/hooks/: ${ADV_NOTE:-the copy failed} the stamped workflow would refuse every pull request."
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s\n' "$ADV_NOTE"
  [[ -f "$INSTANCE/.claude/hooks/forge-check.sh" ]] || die "could not deliver forge-check.sh to .claude/hooks/; the stamped workflow would refuse every pull request."
fi
if [[ -f "$CO_SRC" && ! -e "$CO_DEST" && ! -L "$CO_DEST" ]]; then
  mkdir -p "$INSTANCE/.github" # fail-open-ok: the guarded delivery below reports the failure by name
  ADV_NOTE="$(setlist_deliver_file "$CO_SRC" "$INSTANCE" ".github/CODEOWNERS")" \
    || die "could not deliver the ownership file to .github/CODEOWNERS: ${ADV_NOTE:-the copy failed}"
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s\n' "$ADV_NOTE"
fi
if [[ -f "$FCW_SRC" && ! -e "$FCW_DEST" && ! -L "$FCW_DEST" ]]; then
  mkdir -p "$INSTANCE/.github/workflows" # fail-open-ok: the guarded delivery below reports the failure by name
  ADV_NOTE="$(setlist_deliver_file "$FCW_SRC" "$INSTANCE" ".github/workflows/setlist-forge-check.yml")" \
    || die "could not deliver the forge check's workflow to .github/workflows/: ${ADV_NOTE:-the copy failed}"
  [[ -z "$ADV_NOTE" ]] || printf 'refresh-instance.sh: %s\n' "$ADV_NOTE"
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
  # The chain's pass-throughs (spec 0173, item 2): one fixed file under each other hook
  # name the displaced layer carries, so its commit-msg (say) keeps running. A file
  # already at that name in .githooks is left alone and named: it is someone's.
  if [[ "$CHAIN_MODE" -eq 1 ]]; then
    for h in $CHAIN_NAMES; do
      if [[ -e "$INSTANCE/.githooks/$h" || -L "$INSTANCE/.githooks/$h" ]]; then
        cmp -s "$GITHOOKS_SRC/setlist-chain-passthrough" "$INSTANCE/.githooks/$h" \
          || printf 'refresh-instance.sh: .githooks/%s already exists and is not the chain pass-through; it was left as is, so the chained layer%ss %s hook runs only if that file runs it.\n' "$h" "'" "$h"
        continue
      fi
      deliver "installing the chain pass-through .githooks/$h" cp "$GITHOOKS_SRC/setlist-chain-passthrough" "$INSTANCE/.githooks/$h"
      chmod +x "$INSTANCE/.githooks/$h" 2>/dev/null || true # fail-open-ok: the test on the next line dies unless the file is executable
      [[ -x "$INSTANCE/.githooks/$h" ]] || die "wrote the chain pass-through .githooks/$h but it is not executable; git would skip it in silence. Fix the mode, then re-run."
    done
  fi
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
# The gates block rides the same write when it is owed (GATES_WRITE, decided
# above before the report), appended after every existing key on STAMP-TREE's
# rule, its close and push tiers the single gate_command read from the file
# itself here rather than from the report's echo.
# The audit's baseline rides this write too (spec 0157), for the reason the
# gates block does: one write, one read-back, and the value lands in the same
# migration commit as the version it belongs to. Empty means nothing to record
# (a present declaration, or no boundary here), and then this expression is the
# identity it always was.
# The chain's record (spec 0173, item 2) rides the same write, only when this run chained.
CHAIN_WRITE=""
[[ "$CHAIN_MODE" -eq 1 ]] && CHAIN_WRITE="$CHAIN_VALUE"
if ! jq --arg v "$PLUGIN_VERSION" --argjson g "$GATES_WRITE" --arg ab "$AUDIT_BASELINE_WRITE" --arg hc "$CHAIN_WRITE" '.plugin = ((.plugin // {}) + {version: $v}) | if ($g == 1 and .gates == null) then .gates = {commit: "", close: (.gate_command // ""), push: (.gate_command // "")} else . end | if ($ab != "") then .audit = ((.audit // {}) + {baseline: $ab}) else . end | if ($hc != "") then .hooks_chain = $hc else . end' "$SDD" > "$TMP"; then
  rm -f "$TMP"
  die "the hooks were refreshed but recording the plugin version in $SDD failed; record .plugin.version = \"$PLUGIN_VERSION\" by hand before closing"
fi
# THE OUTPUT IS VALIDATED BEFORE IT REPLACES THE CONFIG, not only jq's status
# (the 2.5.0 leg, F-degraded-1, its second half). A jq healthy at the top of
# this run can die between there and here, and a jq that exits 0 having written
# nothing produced an EMPTY temp file that the mv below then made the instance's
# config. The write must be one JSON object carrying the version it claims to
# record, or the old file stays and the refusal names the state.
if ! [[ -s "$TMP" ]] \
   || ! jq -e -s --arg v "$PLUGIN_VERSION" --argjson g "$GATES_WRITE" --arg ab "$AUDIT_BASELINE_WRITE" --arg hc "$CHAIN_WRITE" 'length == 1 and (.[0] | type == "object") and (.[0].plugin.version == $v) and ($g == 0 or ((.[0].gates | type) == "object" and ([.[0].gates.commit, .[0].gates.close, .[0].gates.push] | map(type == "string") | all))) and ($ab == "" or (.[0].audit.baseline == $ab)) and ($hc == "" or (.[0].hooks_chain == $hc))' "$TMP" >/dev/null 2>&1; then
  rm -f "$TMP"
  die "the hooks were refreshed but the rewritten $SDD did not read back as one JSON object recording plugin $PLUGIN_VERSION, so the old file is left in place untouched (jq exited 0 and wrote nothing, or wrote something else). Check 'jq --version', then record .plugin.version = \"$PLUGIN_VERSION\" by hand before closing"
fi
# The version is only recorded if the file really moved. A failed mv here would
# leave the OLD sdd.json in place while the summary below announces the new
# version, which is the F1 shape one statement further on.
mv "$TMP" "$SDD" \
  || { rm -f "$TMP"; die "the hooks and the git-hook boundary were delivered, but writing the recorded plugin version to $SDD failed. Set .plugin.version = \"$PLUGIN_VERSION\" by hand, or re-run this script."; }

[[ "$GATES_WRITE" -eq 1 ]] && printf 'refresh-instance.sh: wrote the gates block to %s (commit empty; close and push the single gate_command), the shape the hooks already read for an absent block.\n' "$SDD"
[[ -n "$AUDIT_BASELINE_WRITE" ]] && printf 'refresh-instance.sh: recorded audit.baseline %s in %s, so the trunk audit judges this history from the commit this instance was first governed at rather than from the stamp.\n' "$AUDIT_BASELINE_WRITE" "$SDD"
if [[ -n "$GITHOOKS_SKIP_NOTE" ]]; then
  printf 'refresh-instance.sh: refreshed the four stamped hooks and recorded plugin %s in %s; the git-hook boundary was NOT touched (see above).\n' "$PLUGIN_VERSION" "$SDD"
else
  printf 'refresh-instance.sh: refreshed the four stamped hooks, delivered the git-hook boundary (.githooks/ plus core.hooksPath and merge.ff), and recorded plugin %s in %s\n' "$PLUGIN_VERSION" "$SDD"
  if [[ "$CHAIN_MODE" -eq 1 ]]; then printf 'refresh-instance.sh: CHAINED the hook layer that ran from %s (foreign: %s): it is recorded as "hooks_chain" in .claude/sdd.json, and each Setlist git hook runs its hook of the same name after its own verdict%s. Commit .claude/sdd.json%s with the migration.\n' "$FOREIGN_HOOKSPATH_SHOWN" "${FOREIGN_HOOK_NAMES% }" "${CHAIN_NAMES:+ (pass-throughs written for: ${CHAIN_NAMES% })}" "${CHAIN_NAMES:+ and those .githooks files}"; fi
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
