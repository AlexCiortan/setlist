#!/usr/bin/env bash
# Setlist phase-1 mechanical stamp. Copies the templates/ tree into a new framework
# instance with placeholder substitution, per the contract in
# templates/STAMP-TREE.md. Deterministic, zero model tokens, re-runnable onto an
# empty directory. The invoking command writes the answers file from the
# interview; nothing here asks anything.
#
# Usage: stamp.sh <answers-file> <target-dir>
#
# Answers file: KEY=VALUE lines (blank lines and # comments ignored).
#   Required: project_name, stack, working_mode,
#             ui=yes|no, opusplan_verified=yes|no, design_surface=yes|no
#   Optional: src_role (default src), tests_role (default tests),
#             mode=new|retrofit (default new)
#
# Substitution runs ONLY on templates named *.tmpl (suffix stripped at the
# destination). Everything else, notably templates/hooks/ and templates/git-hooks/,
# is copied byte-verbatim: the git-hook library builds its em-dash pattern from an
# escape sequence that must survive untouched.
#
# Collisions: in mode=new any existing destination file aborts the whole stamp
# before anything is written. In mode=retrofit existing files are skipped and
# reported (the repo already has a README; phase 2 merges by hand).
#
# Exit codes: 0 stamped (armed, or NOT-ARMED-no-repository, the ordinary
# /setlist:new state); 1 a refusal, nothing written; 4 stamped but the
# boundary was NOT armed because the target sits below its worktree top or is
# a linked worktree, so arming would be inert or displace the parent
# repository's layer.

set -euo pipefail
# Answers are substituted LITERALLY (spec 0158, the 2.9.0 external review's
# item 1). bash 5.2 turns patsub_replacement on by default, and under it an
# unquoted & in the replacement of ${content//pat/$VAR} means the matched
# text, so "R&D Tracker" was stamped as "R{{PROJECT_NAME}}D Tracker". Off here,
# a no-op on bash 3.2 and 4.x, which have no such option.
shopt -u patsub_replacement 2>/dev/null || true # fail-open-ok: bash 3.2 and 4.x have no such option and refuse the name, which is the state this line wants anyway

die() { printf '%s\n' "stamp.sh: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: stamp.sh <answers-file> <target-dir>"
ANSWERS="$1"
TARGET="$2"
[[ -f "$ANSWERS" ]] || die "answers file not found: $ANSWERS"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$ROOT/templates"
[[ -d "$TPL" ]] || die "templates/ not found at the plugin root ($ROOT)"

# The bundled edition: the stable setlist.md at the plugin root (same rule as
# part.sh). The edition version lives inside the file, never in the filename.
EDITION="$ROOT/setlist.md"
[[ -f "$EDITION" ]] || die "setlist.md not found at the plugin root ($ROOT)"
EDITION_FILE="setlist.md"

# The stamping plugin version, read live from this tree's manifest and recorded
# in the instance's sdd.json. Never a hardcoded string: a stamp that names the
# wrong version is worse than one that names none, because the refresh's
# downgrade refusal trusts what it finds there. Undeterminable is fatal for the
# same reason.
PLUGIN_VERSION="$(bash "$SCRIPT_DIR/plugin-version.sh" "$ROOT")" \
  || die "cannot determine this plugin's version, so the instance would be stamped without one; see the message above"

# --- answers -----------------------------------------------------------------

get() { # get <key> [default]
  local line
  # fail-open-ok: an absent answer is legitimate; callers below decide
  # whether a missing value is fatal, and the required ones are validated.
  line="$(grep -E "^$1=" "$ANSWERS" | tail -n1 || true)"
  if [[ -n "$line" ]]; then printf '%s' "${line#*=}"; else printf '%s' "${2-}"; fi
}

PROJECT_NAME="$(get project_name)"
STACK="$(get stack)"
WORKING_MODE="$(get working_mode)"
UI="$(get ui)"
OPUSPLAN="$(get opusplan_verified)"
DESIGN_SURFACE="$(get design_surface)"
SRC_ROLE="$(get src_role src)"
TESTS_ROLE="$(get tests_role tests)"
MODE="$(get mode new)"
STAMP_DATE="$(date +%F)"

[[ -n "$PROJECT_NAME" ]] || die "answers: project_name is required"
[[ -n "$STACK" ]] || die "answers: stack is required"
[[ -n "$WORKING_MODE" ]] || die "answers: working_mode is required"
for pair in "ui=$UI" "opusplan_verified=$OPUSPLAN" "design_surface=$DESIGN_SURFACE"; do
  case "${pair#*=}" in
    yes|no) ;;
    *) die "answers: ${pair%%=*} must be yes or no (got '${pair#*=}')" ;;
  esac
done
case "$MODE" in new|retrofit) ;; *) die "answers: mode must be new or retrofit" ;; esac

# THE ROLE ANSWERS ARE CLEAN RELATIVE PATHS, OR THE STAMP REFUSES BY NAME
# (spec 0158, the 2.9.0 external review's item 2). A role is written into
# .claude/sdd.json, which every hook reads, and becomes a directory below the
# target. Unchecked, src_role=src","evil":"1 injected a key, src_role=src\app
# left the file unparseable, and tests_role=../../etc created a directory two
# levels ABOVE the target. Checked here, with the other answers, so a refusal
# precedes every probe and every write.
role_unclean() { # role_unclean <value> -> prints why it is not clean, or nothing
  local v="$1" seg segs
  [[ -n "$v" ]] || { printf 'it is empty'; return 0; }
  [[ "$v" != /* ]] || { printf 'it begins with /'; return 0; }
  case "$v" in *\"*|*\'*) printf 'it contains a quote'; return 0 ;; esac
  case "$v" in *\\*) printf 'it contains a backslash'; return 0 ;; esac
  [[ "$v" != *[[:cntrl:]]* ]] || { printf 'it contains a control character'; return 0; }
  # A GLOB, A TRAILING SLASH AND A ./ PREFIX (spec 0164, fix round 2, F3 and F8
  # of the 2.10.0 leg): the hooks read this value four ways, and these three
  # spellings made the readers disagree (a glob expanded against the working
  # directory in one layer and matched literally in another; "src/" and "./src"
  # matched nothing in the attestation trigger). The hooks refuse a glob at read
  # time now and normalise the other two, and this refuses them where the value
  # is written, so an instance never carries a spelling that means two things.
  case "$v" in *'*'*|*'?'*|*'['*) printf 'it carries a glob character (* ? [), and a role path is a directory, not a pattern'; return 0 ;; esac
  [[ "$v" != */ ]] || { printf 'it ends with /'; return 0; }
  [[ "$v" != ./* ]] || { printf 'it begins with ./'; return 0; }
  case "$v" in *//*) printf 'it has an empty path segment (//)'; return 0 ;; esac
  IFS=/ read -r -a segs <<< "$v"
  for seg in "${segs[@]}"; do
    [[ "$seg" != ".." ]] || { printf 'it has a .. segment'; return 0; }
  done
}
for pair in "src_role=$SRC_ROLE" "tests_role=$TESTS_ROLE"; do
  ROLE_WHY="$(role_unclean "${pair#*=}")"
  [[ -z "$ROLE_WHY" ]] || die "answers: ${pair%%=*} must be a clean relative path (non-empty, no .. segment, no leading /, no quote, no backslash, no control character); got $(LC_ALL=C; v="${pair#*=}"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e"), and ${ROLE_WHY}. Nothing has been written."
done
# A RETROFIT'S ROLE PATHS ARE READ FROM THE TREE, NEVER DEFAULTED (spec 0179, the
# owner's finding of 2026-09-29). The answers default to src and tests, and the
# role directories used to be created in both modes, so a retrofit whose answers
# kept the defaults on a project laid out otherwise stamped an empty src/ and
# tests/, and every layer judged role paths that held none of the real code while
# the boundary read armed. In retrofit mode a role path must already exist in the
# target; the directories are created in new mode only, below.
if [[ "$MODE" == "retrofit" ]]; then
  for pair in "src_role=$SRC_ROLE" "tests_role=$TESTS_ROLE"; do
    [[ -e "$TARGET/${pair#*=}" ]] \
      || die "answers: ${pair%%=*} is $(LC_ALL=C; v="${pair#*=}"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e"), which does not exist in this repository, and a retrofit governs the code the repository already has, so its role paths come from the tree, never from the default. The retrofit skill's inventory scan (git ls-files grouped by top-level directory) names the real ones: answer with the directory or file your code lives in, and where it lives in more than one, stamp with one and list the rest in .claude/sdd.json's \"roles\", which takes a list. A repository with no tests yet creates the directory its tests will live in first. Nothing has been written."
  done
fi

# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
# jq, PROBED BY OUTPUT (spec 0158, E-a). .claude/sdd.json is built by jq below,
# every value entering by --arg, so a working jq is a precondition of a
# correct stamp; the git hooks this stamp delivers refuse every commit without
# one anyway (SLH-NO-JQ), so refusing here moves that moment to the one where
# it can be fixed. By output, the way the hooks probe it: a jq that exists and
# prints nothing is as absent as a missing one.
JQ_PROBE="$(jq -n 1 2>/dev/null || true)" # fail-open-ok: a jq that fails prints nothing, which fails the comparison below and refuses
[[ "$JQ_PROBE" == "1" ]] \
  || die "jq is missing or not working here (jq -n 1 did not print 1). The stamp builds .claude/sdd.json with jq, and the git hooks it delivers refuse every commit without it. Install jq and re-run. Nothing has been written."

# --- the file plan (mirrors templates/STAMP-TREE.md) ---------------------------

# Each entry: <source-relative-to-templates>TAB<dest-relative-to-target>
# .tmpl sources are templated; all others copy byte-verbatim.
PLAN=()
add() { PLAN+=("$1	$2"); }

add root/CLAUDE.md.tmpl        CLAUDE.md
# AGENTS.md BESIDE IT (spec 0176, C-58): a POINTER for any agent that reads
# AGENTS.md (pi, Codex, OpenCode; Claude Code where a project has no CLAUDE.md),
# never a second copy of the golden rules, which would drift the way the upgrade's
# drift report exists to catch. Byte-verbatim: nothing in it is per-project.
add root/AGENTS.md             AGENTS.md
add root/README.md.tmpl        README.md
add root/ROADMAP.md.tmpl       ROADMAP.md
add root/DECISIONS.md.tmpl     DECISIONS.md
add root/gitignore             .gitignore
add root/env.example           .env.example
add specs/STATUS.md.tmpl       specs/STATUS.md
add claude/settings.json.tmpl  .claude/settings.json
add claude/sdd.json.tmpl       .claude/sdd.json
# The structured status record (RP1, edition v1.12): stamped instances are
# structured FROM BIRTH, in both modes. Upgrades never receive this file (the
# BL-005 rule: mention the field, migrate NOTHING); an upgraded instance opts
# in through checkpoint's human-confirmed transcription, so the one path that
# creates the record unattended is a birth, where there is nothing to
# transcribe and therefore nothing to launder.
add claude/status.json         .claude/status.json
add claude/agents/qa-verifier.md .claude/agents/qa-verifier.md
add claude/agents/close-reviewer.md .claude/agents/close-reviewer.md
add hooks/scope-hook.sh        .claude/hooks/scope-hook.sh
add hooks/regrounding-hook.sh  .claude/hooks/regrounding-hook.sh
add hooks/stop-hook.sh         .claude/hooks/stop-hook.sh
add hooks/bypass-deny.sh       .claude/hooks/bypass-deny.sh
# The GIT hooks, into a TRACKED directory (.githooks/), not .git/hooks. The
# whole point of core.hooksPath is that .git/hooks is not cloned, so a hook that
# lives there protects exactly one working copy and a fresh clone is bare. A
# tracked directory is cloned, reviewed in diffs, and versioned with the code it
# governs. What is still per-clone is the CONFIG POINTING at it, which is the
# residual gap and is stated as such in the edition's Known limitations rather
# than glossed.
add git-hooks/pre-commit           .githooks/pre-commit
add git-hooks/pre-merge-commit     .githooks/pre-merge-commit
add git-hooks/pre-push             .githooks/pre-push
add git-hooks/setlist-hook-lib.sh  .githooks/setlist-hook-lib.sh
# THE FORGE CHECK'S WIRING (2.6.0, spec 0132, design section 4): the workflow
# that runs the stamped check as a required status check on every pull
# request. Stamped "always", byte-verbatim (ratification decision 6): a
# repository not on a forge carries one inert file, and an instance that is on
# one has the check from birth. It carries NO mechanism byte; the check it runs
# is .claude/hooks/forge-check.sh, delivered beside the audit below.
add root/.github/workflows/setlist-forge-check.yml  .github/workflows/setlist-forge-check.yml
# THE OWNERSHIP FILE (2.6.0, T1, design section 7): four protected paths under a
# phase-2 @OWNER slot. A required check whose bytes any pull request can edit
# protects nothing; with .githooks/, .claude/, specs/attest/ and .github/ owned
# (the fourth by ratification amendment 5, 2026-09-07: the check's workflow,
# this file and the issue form), the check, the config, the approvals and the
# wiring that runs the check are reviewed changes wherever the forge enforces
# the file, and the audit reads the same file for T1's verdicts.
add root/github/CODEOWNERS.tmpl  .github/CODEOWNERS
[[ "$MODE" == "new" ]] && add claude/skills/scaffold/SKILL.md.tmpl .claude/skills/scaffold/SKILL.md
[[ "$UI" == "yes" ]] && add claude/skills/browser-qa/SKILL.md .claude/skills/browser-qa/SKILL.md
[[ "$DESIGN_SURFACE" == "yes" ]] && add docs-design/INDEX.md docs/design/INDEX.md

for entry in "${PLAN[@]}"; do
  src="${entry%%	*}"
  [[ -f "$TPL/$src" ]] || die "template missing: templates/$src (STAMP-TREE.md and the tree disagree)"
done

# --- trunk detection -----------------------------------------------------------

# The trunk branch name is resolved from the target repo at stamp time and
# recorded in sdd.json; the scope and close hooks read it instead of assuming
# main (dogfood F6-2). Fallback order: origin/HEAD, the current branch at
# stamp, main. A mode=new target that is not yet a git repo gets main, which
# matches the branch /scaffold's git init creates later.
TRUNK=""
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # fail-open-ok: no origin/HEAD is the normal case for a fresh repo; the
  # next two lines fall back to the current branch, then to "main".
  TRUNK="$(git -C "$TARGET" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  # fail-open-ok: an unborn HEAD yields empty; the "main" default follows.
  # Same swap as the gates (leg F5): branch --show-current needs git 2.22, and
  # a stamp that silently records an empty trunk arms nothing.
  [[ -n "$TRUNK" ]] || TRUNK="$(git -C "$TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: empty is handled by the caller, which refuses to stamp a trunk it cannot name
fi
[[ -n "$TRUNK" ]] || TRUNK="main"

# --- foreign hooks layer: refuse BEFORE the first write (B2, 2026-08-13) ------
#
# The B1 fixture matrix measured what this script did without it: a retrofit
# onto a repository whose core.hooksPath pointed at husky moved that value to
# .githooks with no warning and no refusal, silently switching off the
# project's own hook layer, and what runs there is frequently itself a control
# (gitleaks, detect-secrets, commit-msg validation). refresh-instance.sh has
# carried this guard since 2026-08-07 and its corrected, content-based form
# since 2026-08-11; the stamp simply never got one (B2 inbox item 1).
#
# ONE RULE, ONE DEFINITION. The ownership test lives in setlist-delivery-lib.sh
# and is sourced, not copied: a second copy is how the role-path readers
# drifted apart. Sourcing fails closed, because a guard that fails to load has
# not degraded, it has vanished.
#
# BEFORE ANY WRITE, and the placement is the lesson of the F6 fix's own defect:
# its refusal first fired AFTER the copy loop, so "Nothing has been changed"
# was false at the moment it printed. This guard runs before the collision
# pre-flight's mkdir, so a refused stamp leaves the target byte-untouched.
[[ -f "$SCRIPT_DIR/setlist-delivery-lib.sh" ]] \
  || die "scripts/setlist-delivery-lib.sh is missing, so the hook-layer ownership rule cannot be loaded and a foreign core.hooksPath could be displaced silently. Refusing to stamp."
# shellcheck source=/dev/null
source "$SCRIPT_DIR/setlist-delivery-lib.sh"
declare -f hooks_layer_is_ours >/dev/null \
  || die "setlist-delivery-lib.sh loaded but hooks_layer_is_ours is not defined; refusing to stamp with the displacement guard absent."
# shellcheck disable=SC2034  # read by hooks_layer_is_ours in the sourced library, which is the contract that file's header states
GITHOOKS_SRC="$TPL/git-hooks"
# ONE ARMING DECISION, COMPUTED BEFORE THE FIRST WRITE AND NEVER RE-DERIVED
# (round 4, finding 1). The first cut ran this guard against $TARGET and the
# arming block re-tested is-inside-work-tree separately, ~130 lines and one
# mkdir later. A mode=new target that did not exist yet failed the first test
# (guards skipped), was created by the mkdir INSIDE a monorepo, and passed the
# second: core.hooksPath landed in the monorepo's config, the monorepo's own
# pre-commit stopped running, and .githooks sat where git never looks. So the
# decision is made ONCE, here, probing the nearest EXISTING ancestor of the
# target, and the arming block reads the decision instead of re-testing.
#
#   ARM_DECISION=arm          the target is (or will be) its own worktree top
#   ARM_DECISION=skip-norepo  no repository here: stamp, say NOT ARMED loudly
#   ARM_DECISION=skip-subdir  inside a worktree but below its top: stamp the
#                             files, NEVER touch config, say NOT ARMED loudly
#                             with the reason (git resolves hooks at the top,
#                             so arming here is either inert or a displacement
#                             of the parent repository's layer)
ARM_PROBE="$TARGET"
while [[ ! -d "$ARM_PROBE" && "$ARM_PROBE" != "/" && -n "$ARM_PROBE" ]]; do
  ARM_PROBE="$(dirname "$ARM_PROBE")"
done
BOUNDARY_UNSAFE="$(setlist_boundary_dir_unsafe "$TARGET" 2>/dev/null)"
[[ -z "$BOUNDARY_UNSAFE" ]] || die "refusing to stamp: $(printf '%s' "$BOUNDARY_UNSAFE" | tr '\n\r\t' '   ' | tr -d '\000-\037\177') Nothing has been written."
if git -C "$ARM_PROBE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TARGET_TOP="$(git -C "$ARM_PROBE" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: an empty top mismatches below and the arm is skipped, never performed blind
  GIT_DIR_HERE="$(git -C "$ARM_PROBE" rev-parse --git-dir 2>/dev/null || true)"       # fail-open-ok: both empty compares equal; the top test still governs
  GIT_COMMON_HERE="$(git -C "$ARM_PROBE" rev-parse --git-common-dir 2>/dev/null || true)" # fail-open-ok: same
  # Compared as DIRECTORIES (-ef), never as strings, for the reason the refresh's twin
  # test gives (spec 0159, E-h): a target typed in another case on a filesystem that
  # folds case is the same directory as git's top. A target that does not exist yet
  # cannot be the top.
  if [[ -z "$TARGET_TOP" ]] || ! [[ -d "$TARGET" && "$TARGET_TOP" -ef "$TARGET" ]]; then
    ARM_DECISION=skip-subdir
  elif [[ -n "$GIT_DIR_HERE" && -n "$GIT_COMMON_HERE" && "$GIT_DIR_HERE" != "$GIT_COMMON_HERE" ]]; then
    # Round 5, finding 4: a LINKED worktree shares its config with the main
    # worktree, so arming from here repoints the MAIN worktree's hooks while
    # the guard, anchored at the linked top, sees nothing to displace. Its
    # own decision value, because the below-top message told a linked-worktree
    # operator to go to the top they were already at (round 6, finding 5).
    ARM_DECISION=skip-linked
  else
    ARM_DECISION=arm
    CHAIN_MODE=0; CHAIN_VALUE=""; CHAIN_DIR=""; CHAIN_NAMES=""
    FOREIGN_HOOKSPATH="$(foreign_hookspath "$TARGET")"
    # core.hooksPath is REPOSITORY TEXT (spec 0169's E-j, bounded in spec 0173): git stores
    # whatever `git config` was given, a newline included, and every message below printed it whole,
    # so a value could put a line of its own choosing on stderr. The value is printed through the
    # stamp's own bound (the path set, 80 characters, the edit said), computed once here and used by
    # every message; the LOGIC keeps reading FOREIGN_HOOKSPATH. The stamp and the refresh carry the same
    # expression, moved in one commit, and 0158 stamp g2 and g3 pin the pair.
    FOREIGN_HOOKSPATH_SHOWN="$(LC_ALL=C; v="$FOREIGN_HOOKSPATH"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e")"
    if [[ -n "$FOREIGN_HOOKSPATH" && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]]; then
      FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$TARGET" "$FOREIGN_HOOKSPATH")" 2>/dev/null | tr '\n' ' ')"
      # WHICH OF THE TWO SHAPES THIS IS (spec 0158, SD2's twin, ruled into
      # this spec by spec 0157's E-a). The ownership test decides by BYTES,
      # deliberately, so a CUSTOMISED Setlist hook and a foreign file under a
      # Setlist name are one thing to it, and refusing is right for both. The
      # reason differs: when git already runs Setlist's own .githooks and every
      # objected-to file carries a stamped hook name, the displacement story
      # (move another tool's checks) answers a question nobody asked. The shape
      # test and the second reason are the refresh's (scripts/refresh-instance.sh,
      # spec 0157), with the stamp's own two words, and the suite holds them equal.
      SD2_OURS_EDITED=0
      if [[ "$FOREIGN_HOOKSPATH" == ".githooks" ]] \
         && [[ "$(git -C "$TARGET" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
         && [[ -n "${FOREIGN_HOOK_NAMES// /}" ]]; then
        SD2_OURS_EDITED=1
        for _fh in $FOREIGN_HOOK_NAMES; do
          case "$_fh" in
            pre-commit|pre-merge-commit|pre-push) ;;
            *) SD2_OURS_EDITED=0 ;;
          esac
        done
      fi
      if [[ "$SD2_OURS_EDITED" -eq 1 ]]; then
        die "refusing to arm: the hook layer git already runs from, $FOREIGN_HOOKSPATH_SHOWN, is Setlist's own directory, and these file(s) in it do not match any Setlist release byte for byte: ${FOREIGN_HOOK_NAMES% }. That is what a customised stamped hook looks like (the edition's Part 8c calls it a fork to surface), and it is also what a foreign file under a Setlist name looks like: this check decides by BYTES, deliberately, and cannot tell the two apart. Stamping would replace them either way. Nothing has been written. If you edited them, re-run with SETLIST_ADOPT_HOOKSPATH=1 to take this plugin's versions (the previous file is kept as .setlist-backup), or move your changes into a hook of your own; if they are another tool's, move those checks out of .githooks/ first."
      fi
      # CHAIN RATHER THAN REFUSE (spec 0173, item 2; the validator's E-c, option 1),
      # the refresh's rule through the shared helpers: a layer this stamp can see is
      # chained (recorded as "hooks_chain" in .claude/sdd.json, pass-throughs under the
      # other hook names it carries); a layer it cannot see still refuses.
      # The arming target is asked first (spec 0180, F10; the refresh says why): a
      # .githooks holding a file that is not Setlist's is not chained, and the refusal
      # below names it.
      CHAIN_DIR="$(setlist_refusal_dir "$TARGET" "$FOREIGN_HOOKSPATH")"
      if [[ -n "$(setlist_arming_target_foreign "$TARGET")" ]]; then
        FOREIGN_HOOKSPATH_SHOWN='".githooks"'
        FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$TARGET" .githooks)" 2>/dev/null | tr '\n' ' ')" # fail-open-ok: an empty list prints "unresolvable" in the refusal, which still refuses
        CHAIN_DIR=""
      fi
      if [[ -n "$CHAIN_DIR" ]] && setlist_chainable "$TARGET" "$CHAIN_DIR"; then
        CHAIN_MODE=1
        CHAIN_VALUE="$(setlist_chain_value "$TARGET")"
        CHAIN_NAMES="$(setlist_chain_passthrough_names "$CHAIN_DIR" | tr '\n' ' ')"
      else
        die "refusing to arm: a hook layer that is not Setlist's already runs from, or would be switched on at, $FOREIGN_HOOKSPATH_SHOWN (foreign: ${FOREIGN_HOOK_NAMES:-unresolvable}), and git runs one layer: arming Setlist (core.hooksPath=.githooks) would switch it off, silently taking whatever runs from $FOREIGN_HOOKSPATH_SHOWN with it (gitleaks, detect-secrets and commit-msg validation are commonly wired this way, and pre-commit and lefthook wire into .git/hooks with hooksPath unset). Nothing has been written. Move those checks into .githooks/, or re-run with SETLIST_ADOPT_HOOKSPATH=1 to displace $FOREIGN_HOOKSPATH_SHOWN on purpose."
      fi
    fi
  fi
else
  ARM_DECISION=skip-norepo
fi

# --- collision pre-flight ------------------------------------------------------

mkdir -p "$TARGET"
COLLISIONS=()
for entry in "${PLAN[@]}"; do
  dest="${entry#*	}"
  [[ -e "$TARGET/$dest" ]] && COLLISIONS+=("$dest")
done
[[ -e "$TARGET/specs/TEMPLATE.md" ]] && COLLISIONS+=("specs/TEMPLATE.md")
[[ -e "$TARGET/$EDITION_FILE" ]] && COLLISIONS+=("$EDITION_FILE")

if [[ "$MODE" == "new" && ${#COLLISIONS[@]} -gt 0 ]]; then
  printf 'stamp.sh: refusing to overwrite existing files (mode=new stamps onto an empty directory):\n' >&2
  printf '  %s\n' "${COLLISIONS[@]}" >&2
  exit 1
fi

skip() { # skip <dest> -> 0 if this dest collided in retrofit mode
  local d
  for d in ${COLLISIONS[@]+"${COLLISIONS[@]}"}; do
    [[ "$d" == "$1" ]] && return 0
  done
  return 1
}

# NO WRITE GOES THROUGH A LINK (2026-08 consolidation, leg F1's class). The
# collision rule above is `-e`, and `-e` is FALSE for a dangling symlink: a
# dangling link at any planned destination was not a collision in either mode,
# so cp and stamp_tmpl's redirect resolved it and created our file at whatever
# path the link names, possibly outside the target entirely (measured: the
# 107,776-byte close gate landed outside the instance at rc=0). Every
# destination this stamp will actually write is checked BEFORE the first write,
# through the same rule refresh-instance.sh uses. Destinations the retrofit
# skip rule keeps are exempt because they are not written; .githooks/* is
# exempt because the boundary branch below carries its own leg-pinned
# discipline (backup, link removal with a note) and its job is to deliver.
DEST_UNSAFE_LIST=()
for entry in "${PLAN[@]}"; do
  dest="${entry#*	}"
  case "$dest" in .githooks/*) continue ;; esac
  skip "$dest" && continue
  DEST_REASON="$(setlist_deliver_dest_unsafe "$TARGET" "$dest" 2>/dev/null)"
  [[ -z "$DEST_REASON" ]] || DEST_UNSAFE_LIST+=("$DEST_REASON")
done
for dest in "specs/TEMPLATE.md" "$EDITION_FILE"; do
  skip "$dest" && continue
  DEST_REASON="$(setlist_deliver_dest_unsafe "$TARGET" "$dest" 2>/dev/null)"
  [[ -z "$DEST_REASON" ]] || DEST_UNSAFE_LIST+=("$DEST_REASON")
done
# trunk-audit.sh is delivered UNCONDITIONALLY below (never skipped), so its
# destination is always checked, collision or not: a live symlink there is a
# collision by -e and would have been exempted by the skip rule while the
# unconditional copy still wrote through it.
DEST_REASON="$(setlist_deliver_dest_unsafe "$TARGET" ".claude/hooks/trunk-audit.sh" 2>/dev/null)"
[[ -z "$DEST_REASON" ]] || DEST_UNSAFE_LIST+=("$DEST_REASON")
if [[ ${#DEST_UNSAFE_LIST[@]} -gt 0 ]]; then
  printf 'stamp.sh: refusing to stamp, nothing has been written:\n' >&2
  for __u in "${DEST_UNSAFE_LIST[@]}"; do printf '  %s\n' "$(printf '%s' "$__u" | tr '\n\r\t' '   ' | tr -d '\000-\037\177')" >&2; done
  exit 1
fi

# THE FILE THIS RETROFIT SHADOWS, SAID BEFORE THE FIRST WRITE (spec 0176, C-58).
# Claude Code reads AGENTS.md where a project has no CLAUDE.md, and CLAUDE.md
# where both exist, so writing CLAUDE.md into a repository that governs its agents
# through AGENTS.md alone silently demotes the project's own instructions. The
# stamp cannot merge them (phase 2 does, by hand); it says so, and the retrofit
# skip rule leaves AGENTS.md byte-unchanged. With a CLAUDE.md already present the
# stamp shadows nothing new, and says nothing.
if [[ "$MODE" == "retrofit" && -e "$TARGET/AGENTS.md" && ! -e "$TARGET/CLAUDE.md" ]]; then
  printf 'stamp.sh: NOTICE: this repository carries AGENTS.md and no CLAUDE.md. The retrofit writes CLAUDE.md, and Claude Code reads CLAUDE.md where both exist, so your AGENTS.md will be shadowed: it stops being what Claude Code loads (agents that read only AGENTS.md still read it). AGENTS.md is left byte-unchanged (skipped below); merge what it says into CLAUDE.md in phase 2.\n'
fi

# --- stamping ------------------------------------------------------------------

stamp_tmpl() { # stamp_tmpl <abs-src> <abs-dest>
  local content
  content="$(<"$1")"
  # Conditional lines first: keep (marker stripped) or drop whole lines.
  if [[ "$OPUSPLAN" == "yes" ]]; then
    content="$(printf '%s\n' "$content" | sed 's/^{{IF:OPUSPLAN}}//')"
  else
    # fail-open-ok: grep exits 1 when every line is filtered out, which is a
    # legitimate result here (a template that is entirely conditional).
    content="$(printf '%s\n' "$content" | grep -v '^{{IF:OPUSPLAN}}' || true)"
  fi
  # Placeholders, replaced literally (bash replacement, no regex).
  content="${content//'{{PROJECT_NAME}}'/$PROJECT_NAME}"
  content="${content//'{{STACK}}'/$STACK}"
  content="${content//'{{WORKING_MODE}}'/$WORKING_MODE}"
  content="${content//'{{SRC_ROLE}}'/$SRC_ROLE}"
  content="${content//'{{TESTS_ROLE}}'/$TESTS_ROLE}"
  content="${content//'{{TRUNK}}'/$TRUNK}"
  content="${content//'{{STAMP_DATE}}'/$STAMP_DATE}"
  content="${content//'{{EDITION_FILE}}'/$EDITION_FILE}"
  content="${content//'{{PLUGIN_VERSION}}'/$PLUGIN_VERSION}"
  printf '%s\n' "$content" > "$2"
}

# .claude/sdd.json IS BUILT, NOT SUBSTITUTED (spec 0158, the 2.10.0 intake
# section 2b.2). The template parses as JSON as it stands, each placeholder
# being a JSON string, so jq reads it and sets the four values that land in the
# file, each by --arg: a value is data to jq and can never become syntax. The
# template stays the one copy of the file's shape (jq -n would be a second).
# Then read back, as the refresh reads back its own jq write: a jq that exits
# 0 with other bytes refuses too.
stamp_sdd_json() { # stamp_sdd_json <abs-src> <abs-dest>
  local key want got
  jq --arg src "$SRC_ROLE" --arg tests "$TESTS_ROLE" --arg trunk "$TRUNK" --arg version "$PLUGIN_VERSION" \
    '.roles.src = $src | .roles.tests = $tests | .trunk = $trunk | .plugin.version = $version' \
    "$1" > "$2" \
    || die "could not build .claude/sdd.json from templates/claude/sdd.json.tmpl with jq; the files listed above this line may already be stamped, and this instance has no usable config."
  for key in roles.src roles.tests trunk plugin.version; do
    case "$key" in
      roles.src) want="$SRC_ROLE" ;;
      roles.tests) want="$TESTS_ROLE" ;;
      trunk) want="$TRUNK" ;;
      plugin.version) want="$PLUGIN_VERSION" ;;
    esac
    got="$(jq -r ".$key" "$2" 2>/dev/null || true)" # fail-open-ok: an unreadable file reads empty and differs, which refuses below
    [[ "$got" == "$want" ]] \
      || die ".claude/sdd.json was written but does not read back: .$key is $(LC_ALL=C; v="$got"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e"), the stamp wrote $(LC_ALL=C; v="$want"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e"). Every hook reads this file; do not use this instance until it is re-stamped."
  done
}

STAMPED=0
SKIPPED=()
for entry in "${PLAN[@]}"; do
  src="${entry%%	*}"
  dest="${entry#*	}"
  # THE BOUNDARY FILES ARE NEVER SILENTLY KEPT (round 7, finding 1). The
  # retrofit skip rule is right for READMEs and specs (phase 2 merges by
  # hand) and wrong for .githooks/: keeping a pre-existing file there and
  # then printing ARMED presents a hook Setlist never wrote as Setlist's
  # boundary. The guard refuses a foreign target before this loop runs, so a
  # collision here is reachable only via SETLIST_ADOPT_HOOKSPATH=1 or with
  # files that hash as ours; the adopt case REPLACES with a named backup,
  # exactly like refresh-instance.sh, so the two delivery paths agree.
  case "$dest" in
    .githooks/*)
      # In the skip-subdir and skip-linked states the boundary files are NOT
      # delivered at all (round 8, finding 1): a RELATIVE core.hooksPath is
      # resolved per worktree, so a .githooks here can be LIVE, and the
      # replace-with-backup below would displace a running scanner on the
      # very branch whose message says nothing will be armed. No repository
      # (skip-norepo) still delivers inert files, the ordinary /setlist:new.
      if [[ "${ARM_DECISION:-}" == "skip-subdir" || "${ARM_DECISION:-}" == "skip-linked" ]]; then
        SKIPPED+=("$dest (boundary not delivered here; see the NOT ARMED note)")
        continue
      fi
      HOOK_DEST_UNSAFE="$(setlist_hook_dest_unsafe "$TARGET/$dest" 2>/dev/null)"
      [[ -z "$HOOK_DEST_UNSAFE" ]] || die "refusing to stamp: $TARGET/$HOOK_DEST_UNSAFE Nothing further was stamped."
      if [[ -L "$TARGET/$dest" && ! -e "$TARGET/$dest" ]]; then
        # A DANGLING link has no content to back up and no file to compare,
        # so both guards below are false for it, and cp would RESOLVE it and
        # create our hook body at whatever path the repository chose,
        # possibly outside it entirely (round 9, finding 1). The link goes;
        # nothing else is touched. Its target is read FIRST (spec 0169, fix
        # round 1, E-k): read after the removal, the note always said "unknown".
        __dl_to="$(readlink "$TARGET/$dest" 2>/dev/null || echo unknown)"
        rm -f "$TARGET/$dest" \
          || die "could not remove the dangling symlink at $dest; stamping through it would create a file at $(LC_ALL=C; v="$__dl_to"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e")."
        printf 'stamp.sh: %s was a DANGLING symlink (to %s); the link was removed and a regular file takes its place. Nothing was written at the link target.\n' "$dest" "$(LC_ALL=C; v="$__dl_to"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e")"
      fi
      if [[ -e "$TARGET/$dest" ]] && ! cmp -s "$TPL/$src" "$TARGET/$dest"; then
        # THE BACKUP PATH IS A DESTINATION TOO (2026-08 consolidation, second
        # adversary round): a symlink at the .setlist-backup sibling has this
        # cp resolve it and write the old file outside the boundary under a
        # "kept at .setlist-backup" message that is then false. The link is
        # removed (its target untouched), exactly as the hook-path symlink is
        # handled below, so a real backup takes its place.
        if [[ -L "$TARGET/$dest.setlist-backup" ]]; then
          rm -f "$TARGET/$dest.setlist-backup" \
            || die "could not remove the symlink at $dest.setlist-backup; backing up through it would overwrite $(LC_ALL=C; v="$(readlink "$TARGET/$dest.setlist-backup")"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e") outside .githooks/."
          printf 'stamp.sh: %s.setlist-backup was a symlink; it was removed (its target untouched) and a real backup takes its place.\n' "$dest"
        fi
        cp "$TARGET/$dest" "$TARGET/$dest.setlist-backup" \
          || die "could not back up $dest before replacing it; nothing further was stamped."
        if [[ -L "$TARGET/$dest" ]]; then
          # cp FOLLOWS a symlink and would overwrite the file it points to,
          # which lives OUTSIDE the boundary (round 8, finding 3: a husky-
          # style layer symlinks its hooks to project scripts). The link is
          # removed so the copy below creates a regular file and the linked
          # script is untouched.
          rm -f "$TARGET/$dest" \
            || die "could not remove the symlink at $dest; replacing through it would overwrite $(LC_ALL=C; v="$(readlink "$TARGET/$dest")"; b="${v//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""; [ "$b" = "$v" ] || e=" (characters outside a path set replaced with ?)"; [ "${#b}" -le 80 ] || { b="${b:0:80}"; e="$e (cut at 80 characters)"; }; printf '"%s"%s' "$b" "$e") outside .githooks/."
          printf 'stamp.sh: %s was a symlink; the link was replaced by a regular file and the linked script was NOT touched.\n' "$dest"
        fi
        printf 'stamp.sh: %s differed and was replaced; the previous file is kept at %s.setlist-backup\n' "$dest" "$dest"
      fi
      ;;
    *)
      if skip "$dest"; then SKIPPED+=("$dest"); continue; fi
      ;;
  esac
  mkdir -p "$TARGET/$(dirname "$dest")"
  if [[ "$dest" == ".claude/sdd.json" ]]; then
    stamp_sdd_json "$TPL/$src" "$TARGET/$dest"
  elif [[ "$src" == *.tmpl ]]; then
    stamp_tmpl "$TPL/$src" "$TARGET/$dest"
  else
    cp "$TPL/$src" "$TARGET/$dest"
  fi
  STAMPED=$((STAMPED + 1))
done
# fail-open-ok: cosmetic, as in refresh-instance.sh; the hooks run via bash.
chmod +x "$TARGET/.claude/hooks/"*.sh 2>/dev/null || true
# NOT cosmetic: git refuses to run a hook that is not executable, and it does so
# SILENTLY. A non-executable pre-merge-commit is a boundary that reports nothing
# and stops nothing, which is the fail-open shape this whole mechanism exists to
# remove, so this one is checked rather than shrugged off.
if [[ -d "$TARGET/.githooks" && "${ARM_DECISION:-}" != "skip-subdir" && "${ARM_DECISION:-}" != "skip-linked" ]]; then
  # The skip states delivered no boundary files (round 8, finding 1), so
  # there is nothing of ours to chmod or verify here, and a chmod over a
  # FOREIGN layer's files would itself be a write to that layer.
  chmod +x "$TARGET/.githooks/pre-commit" "$TARGET/.githooks/pre-merge-commit" "$TARGET/.githooks/pre-push" 2>/dev/null || true  # fail-open-ok: the chmod's own status is discarded because the loop immediately below DIES unless every hook is actually executable, so a filesystem that refused the bit is caught by the test rather than by this exit code
  for h in pre-commit pre-merge-commit pre-push; do
    [[ -x "$TARGET/.githooks/$h" ]] || die ".githooks/$h is not executable; git would skip it silently"
  done
  # The chain (spec 0173, item 2): the pass-through under each other hook name the
  # displaced layer carries, and the layer's location recorded in .claude/sdd.json.
  if [[ "${CHAIN_MODE:-0}" -eq 1 ]]; then
    for h in $CHAIN_NAMES; do
      if [[ -e "$TARGET/.githooks/$h" || -L "$TARGET/.githooks/$h" ]]; then
        cmp -s "$GITHOOKS_SRC/setlist-chain-passthrough" "$TARGET/.githooks/$h" \
          || printf 'stamp.sh: .githooks/%s already exists and is not the chain pass-through; it was left as is, so the chained layer%ss %s hook runs only if that file runs it.\n' "$h" "'" "$h"
        continue
      fi
      cp "$GITHOOKS_SRC/setlist-chain-passthrough" "$TARGET/.githooks/$h" \
        || die "could not write the chain pass-through .githooks/$h; the chained layer's $h hook would stop running in silence."
      chmod +x "$TARGET/.githooks/$h" 2>/dev/null || true # fail-open-ok: the test on the next line dies unless the file is executable
      [[ -x "$TARGET/.githooks/$h" ]] || die ".githooks/$h (the chain pass-through) is not executable; git would skip it silently"
    done
    CHAIN_TMP="$TARGET/.claude/sdd.json.stamp.$$"
    { jq --arg hc "$CHAIN_VALUE" '.hooks_chain = $hc' "$TARGET/.claude/sdd.json" > "$CHAIN_TMP" \
      && jq -e --arg hc "$CHAIN_VALUE" '.hooks_chain == $hc' "$CHAIN_TMP" >/dev/null 2>&1 \
      && mv "$CHAIN_TMP" "$TARGET/.claude/sdd.json"; } \
      || { rm -f "$CHAIN_TMP"; die "could not record \"hooks_chain\" in .claude/sdd.json, so the hook layer this stamp chains would stop running; the boundary is not armed. Nothing further was changed."; }
    printf 'stamp.sh: CHAINED the hook layer that ran from %s (foreign: %s): recorded as "hooks_chain" in .claude/sdd.json; each Setlist git hook runs its hook of the same name after its own verdict%s.\n' "$FOREIGN_HOOKSPATH_SHOWN" "${FOREIGN_HOOK_NAMES% }" "${CHAIN_NAMES:+ (pass-throughs written for: ${CHAIN_NAMES% })}"
  fi
  fi

# trunk-audit.sh is the ADVISORY tool pre-push runs; it lives in .claude/hooks
# and has nothing to do with core.hooksPath, so it is delivered regardless of
# the arming decision (round 11, finding 3: a linked worktree, whose shared
# config keeps the boundary LIVE, was left without it and refused every push).
if [[ -f "$ROOT/scripts/trunk-audit.sh" ]]; then
  mkdir -p "$TARGET/.claude/hooks"
  # Through the one write rule (2026-08 consolidation): the destination was
  # checked before the first write, and a differing existing file is backed up
  # with a named backup instead of being replaced in silence.
  TA_NOTE="$(setlist_deliver_file "$ROOT/scripts/trunk-audit.sh" "$TARGET" ".claude/hooks/trunk-audit.sh")" \
    || die "could not install trunk-audit.sh into .claude/hooks/: $(printf '%s' "${TA_NOTE:-the copy failed}" | tr '\n\r\t' '   ' | tr -d '\000-\037\177') pre-push would refuse every push outside a Claude Code session"
  [[ -z "$TA_NOTE" ]] || printf 'stamp.sh: %s\n' "$(printf '%s' "$TA_NOTE" | tr '\n\r\t' '   ' | tr -d '\000-\037\177')"
  [[ -f "$TARGET/.claude/hooks/trunk-audit.sh" ]] || die "could not install trunk-audit.sh into .claude/hooks/; pre-push would refuse every push outside a Claude Code session"
fi
# THE FORGE CHECK RIDES THE SAME RULE (2.6.0, spec 0132): delivered beside the
# audit, unconditionally, through the one write rule. It is what the stamped
# workflow runs and what the local hooks name when they defer custody C's
# approval question, so an instance without it has a workflow that refuses
# every pull request and a deferral that names nothing.
if [[ -f "$ROOT/scripts/forge-check.sh" ]]; then
  mkdir -p "$TARGET/.claude/hooks"
  FC_NOTE="$(setlist_deliver_file "$ROOT/scripts/forge-check.sh" "$TARGET" ".claude/hooks/forge-check.sh")" \
    || die "could not install forge-check.sh into .claude/hooks/: $(printf '%s' "${FC_NOTE:-the copy failed}" | tr '\n\r\t' '   ' | tr -d '\000-\037\177') the stamped workflow would refuse every pull request"
  [[ -z "$FC_NOTE" ]] || printf 'stamp.sh: %s\n' "$(printf '%s' "$FC_NOTE" | tr '\n\r\t' '   ' | tr -d '\000-\037\177')"
  [[ -f "$TARGET/.claude/hooks/forge-check.sh" ]] || die "could not install forge-check.sh into .claude/hooks/; the stamped workflow would refuse every pull request"
fi

# Point git at the tracked hooks directory, and stop fast-forward merges.
#
# BOTH settings, and the second is not a style preference. Measured 2026-08-01:
# a fast-forward merge fires NO git hook whatsoever, so `git merge spec/0001-x`
# walks unreviewed work onto the trunk past an otherwise airtight boundary. With
# merge.ff=false every merge creates a merge commit, which is what fires
# pre-merge-commit. The framework's own protocol already merges spec branches
# with --no-ff, so this makes the config agree with the practice.
#
# These are per-clone settings written to .git/config, which is NOT cloned. That
# is the residual hole core.hooksPath narrows rather than closes, and the
# edition's Known limitations says so in those words.
# ARM, OR SAY SO. NEVER SKIP IN SILENCE (v1.7 claims audit, R3-1).
#
# This block used to be a bare `if`: when the target was not yet a work tree the
# two settings were skipped and nothing was printed. /setlist:new runs in an
# EMPTY directory, so that was the ordinary case rather than the edge one, and
# every project the primary onboarding path produced shipped with .githooks/
# present, core.hooksPath unset, and therefore NO enforcement at all, while the
# README said /scaffold arms the hooks. Nine adversarial reviews missed it because
# every leg fixture stamped into an EXISTING repository.
#
# A delivery that could not deliver has not delivered, which is the same rule
# refresh-instance.sh already follows. When the repository exists the settings
# are written and read back; when it does not, the operator is told exactly what
# is not armed and what to run, because /scaffold creates the repository later
# and arming it there is the supported path.
if [[ ! -d "$TARGET/.githooks" && "${ARM_DECISION:-}" != "skip-subdir" && "${ARM_DECISION:-}" != "skip-linked" ]]; then
  printf 'stamp.sh: no .githooks/ was stamped, so there is no git-hook boundary to arm.\n' >&2
  exit 1
fi
if [[ "$ARM_DECISION" == "skip-linked" ]]; then
  GH_ARMED=0
  printf '\nstamp.sh: git-hook boundary NOT ARMED. %s is a LINKED worktree: core.hooksPath\n' "$TARGET" >&2
  printf 'lives in the config SHARED with the main worktree, so arming from here would\n' >&2
  printf 'repoint the main worktree'"'"'s hooks while this guard cannot see that layer.\n' >&2
  printf 'The boundary files were NOT delivered here (see the skipped list). Arm from the main worktree.\n' >&2
elif [[ "$ARM_DECISION" == "skip-subdir" ]]; then
  GH_ARMED=0
  printf '\nstamp.sh: git-hook boundary NOT ARMED. %s sits BELOW the top of its git\n' "$TARGET" >&2
  printf 'working tree (%s), and git resolves core.hooksPath at the top, so arming here\n' "${TARGET_TOP:-unknown}" >&2
  printf 'would either be inert or displace the parent repository'"'"'s own hook layer.\n' >&2
  printf 'The boundary files were NOT delivered here (see the skipped list). To get an\n' >&2
  printf 'armed boundary, make this instance its own repository, or run Setlist from\n' >&2
  printf 'the worktree top.\n' >&2
elif [[ "$ARM_DECISION" == "arm" ]]; then
  git -C "$TARGET" config core.hooksPath .githooks \
    || die "could not set core.hooksPath in $TARGET; the hooks are stamped but INERT."
  git -C "$TARGET" config merge.ff false \
    || die "could not set merge.ff in $TARGET; a fast-forward merge would bypass pre-merge-commit."
  # Read back rather than trusting the writes: a config that reports success and
  # does not hold the value delivers the same inert boundary.
  [[ "$(git -C "$TARGET" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
    || die "core.hooksPath was written without error but does not read back as .githooks, so the hooks would be inert."
  GH_ARMED=1
else
  GH_ARMED=0
  printf '\nstamp.sh: NOT ARMED. %s is not a git repository yet, so core.hooksPath and\n' "$TARGET" >&2
  printf 'merge.ff could NOT be set. The hooks are stamped into .githooks/ and are INERT\n' >&2
  printf 'until both are set. This is the ordinary state right after /setlist:new, and\n' >&2
  printf '/scaffold arms them when it creates the repository. If you are not running\n' >&2
  printf '/scaffold next, arm them by hand from inside the repository:\n' >&2
  printf '    git config core.hooksPath .githooks\n' >&2
  printf '    git config merge.ff false\n' >&2
fi

# specs/TEMPLATE.md: Appendix C extracted from the bundled edition at stamp
# time, unfenced (the template body between the ````markdown fences).
#
# FOUR BACKTICKS, and the toggle below counts them. The template itself now
# contains a fenced qa-pass-1 block (Part 6's structured QA verdict), and this
# extractor is a plain TOGGLE: with a three-backtick outer fence the inner
# block's opener would flip it off and the stamped template would be truncated
# mid-field, silently, in every instance created after that change. Widening
# the outer delimiter keeps the reader trivial instead of teaching it CommonMark
# nesting, which is the repair this repository has already paid for five times
# in its own report checker.
if skip "specs/TEMPLATE.md"; then
  SKIPPED+=("specs/TEMPLATE.md")
else
  mkdir -p "$TARGET/specs"
  "$SCRIPT_DIR/part.sh" appendix-c "$EDITION" \
    | awk '/^````/ { infence = !infence; next } infence { print }' \
    > "$TARGET/specs/TEMPLATE.md"
  [[ -s "$TARGET/specs/TEMPLATE.md" ]] || die "Appendix C extraction produced an empty specs/TEMPLATE.md"
  STAMPED=$((STAMPED + 1))
fi

# The edition copy: the audit-trail rule (Part 8 Step 3).
if skip "$EDITION_FILE"; then
  SKIPPED+=("$EDITION_FILE")
else
  cp "$EDITION" "$TARGET/$EDITION_FILE"
  STAMPED=$((STAMPED + 1))
fi

# The role directories. .gitkeep only where the directory is (still) empty. The
# two role paths are created for a NEW project only (spec 0179): a retrofit's
# already exist, refused above otherwise, and one may be a file.
STAMP_DIRS=(steering journal)
[[ "$MODE" == "new" ]] && STAMP_DIRS+=("$SRC_ROLE" "$TESTS_ROLE")
for d in "${STAMP_DIRS[@]}"; do
  mkdir -p "$TARGET/$d"
  if [[ -z "$(ls -A "$TARGET/$d")" ]]; then touch "$TARGET/$d/.gitkeep"; fi
done

# --- report --------------------------------------------------------------------

echo "stamp.sh: stamped $STAMPED files into $TARGET (mode=$MODE, ui=$UI, opusplan=$OPUSPLAN, design_surface=$DESIGN_SURFACE, trunk=$TRUNK, plugin=$PLUGIN_VERSION)"
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "stamp.sh: skipped existing files (retrofit; phase 2 merges by hand):"
  printf '  %s\n' "${SKIPPED[@]}"
fi
echo "stamp.sh: phase 2 (tailored generation) still owes every [PHASE 2 SLOT] marker."
# The arming state is repeated at the END as well as at the moment it happens,
# because the stamp prints a lot and the one line that decides whether this
# instance has an enforcement boundary should not scroll away.
if [[ "${GH_ARMED:-0}" -eq 1 ]]; then
  echo "stamp.sh: git-hook boundary ARMED (core.hooksPath=.githooks, merge.ff=false)."
else
  if [[ "${ARM_DECISION:-}" == "skip-subdir" || "${ARM_DECISION:-}" == "skip-linked" ]]; then
    echo "stamp.sh: git-hook boundary NOT ARMED: the target sits below its worktree top or is a linked worktree, so arming would be inert or would displace the parent repository's layer (see the note above). Exit 4 states this for callers."
  else
    echo "stamp.sh: git-hook boundary NOT ARMED (no repository yet). The hooks are INERT until core.hooksPath and merge.ff are set; /scaffold does this when it creates the repository."
  fi
if [[ "${ARM_DECISION:-}" == "skip-subdir" || "${ARM_DECISION:-}" == "skip-linked" ]]; then
  exit 4
fi
fi
