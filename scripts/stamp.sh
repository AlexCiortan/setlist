#!/usr/bin/env bash
# SDD phase-1 mechanical stamp. Copies the templates/ tree into a new framework
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
# destination). Everything else, notably templates/hooks/, is copied
# byte-verbatim: the commit gate builds its em-dash pattern from an escape
# sequence that must survive untouched.
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

# --- the file plan (mirrors templates/STAMP-TREE.md) ---------------------------

# Each entry: <source-relative-to-templates>TAB<dest-relative-to-target>
# .tmpl sources are templated; all others copy byte-verbatim.
PLAN=()
add() { PLAN+=("$1	$2"); }

add root/CLAUDE.md.tmpl        CLAUDE.md
add root/README.md.tmpl        README.md
add root/ROADMAP.md.tmpl       ROADMAP.md
add root/DECISIONS.md.tmpl     DECISIONS.md
add root/gitignore             .gitignore
add root/env.example           .env.example
add specs/STATUS.md.tmpl       specs/STATUS.md
add claude/settings.json.tmpl  .claude/settings.json
add claude/sdd.json.tmpl       .claude/sdd.json
add claude/agents/qa-verifier.md .claude/agents/qa-verifier.md
add hooks/scope-hook.sh        .claude/hooks/scope-hook.sh
add hooks/commit-gate.sh       .claude/hooks/commit-gate.sh
add hooks/close-gate.sh        .claude/hooks/close-gate.sh
add hooks/regrounding-hook.sh  .claude/hooks/regrounding-hook.sh
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
[[ -z "$BOUNDARY_UNSAFE" ]] || die "refusing to stamp: $BOUNDARY_UNSAFE Nothing has been written."
if git -C "$ARM_PROBE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TARGET_TOP="$(git -C "$ARM_PROBE" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: an empty top mismatches below and the arm is skipped, never performed blind
  if [[ -d "$TARGET" ]]; then
    TARGET_REAL="$(cd "$TARGET" 2>/dev/null && pwd -P)"
  else
    TARGET_REAL="$(cd "$ARM_PROBE" 2>/dev/null && pwd -P)/${TARGET#"$ARM_PROBE"/}"
  fi
  GIT_DIR_HERE="$(git -C "$ARM_PROBE" rev-parse --git-dir 2>/dev/null || true)"       # fail-open-ok: both empty compares equal; the top test still governs
  GIT_COMMON_HERE="$(git -C "$ARM_PROBE" rev-parse --git-common-dir 2>/dev/null || true)" # fail-open-ok: same
  if [[ -z "$TARGET_TOP" || "$TARGET_REAL" != "$TARGET_TOP" ]]; then
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
    FOREIGN_HOOKSPATH="$(foreign_hookspath "$TARGET")"
    if [[ -n "$FOREIGN_HOOKSPATH" && "${SETLIST_ADOPT_HOOKSPATH:-0}" != "1" ]]; then
      FOREIGN_HOOK_NAMES="$(hooks_layer_foreign_entries "$(setlist_refusal_dir "$TARGET" "$FOREIGN_HOOKSPATH")" 2>/dev/null | tr '\n' ' ')"
      die "refusing to arm: a hook layer that is not Setlist's already runs from, or would be switched on at, $FOREIGN_HOOKSPATH (foreign: ${FOREIGN_HOOK_NAMES:-unresolvable}), and git runs one layer: arming Setlist (core.hooksPath=.githooks) would switch it off, silently taking whatever runs from $FOREIGN_HOOKSPATH with it (gitleaks, detect-secrets and commit-msg validation are commonly wired this way, and pre-commit and lefthook wire into .git/hooks with hooksPath unset). Nothing has been written. Move those checks into .githooks/, or re-run with SETLIST_ADOPT_HOOKSPATH=1 to displace $FOREIGN_HOOKSPATH on purpose."
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
  printf '  %s\n' "${DEST_UNSAFE_LIST[@]}" >&2
  exit 1
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
        # nothing else is touched.
        rm -f "$TARGET/$dest" \
          || die "could not remove the dangling symlink at $dest; stamping through it would create a file at $(readlink "$TARGET/$dest")."
        printf 'stamp.sh: %s was a DANGLING symlink (to %s); the link was removed and a regular file takes its place. Nothing was written at the link target.\n' "$dest" "$(readlink "$TARGET/$dest" 2>/dev/null || echo unknown)"
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
            || die "could not remove the symlink at $dest.setlist-backup; backing up through it would overwrite $(readlink "$TARGET/$dest.setlist-backup") outside .githooks/."
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
            || die "could not remove the symlink at $dest; replacing through it would overwrite $(readlink "$TARGET/$dest") outside .githooks/."
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
  if [[ "$src" == *.tmpl ]]; then
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
    || die "could not install trunk-audit.sh into .claude/hooks/: ${TA_NOTE:-the copy failed} pre-push would refuse every push outside a Claude Code session"
  [[ -z "$TA_NOTE" ]] || printf 'stamp.sh: %s' "$TA_NOTE"
  [[ -f "$TARGET/.claude/hooks/trunk-audit.sh" ]] || die "could not install trunk-audit.sh into .claude/hooks/; pre-push would refuse every push outside a Claude Code session"
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

# The role directories. .gitkeep only where the directory is (still) empty.
for d in steering journal "$SRC_ROLE" "$TESTS_ROLE"; do
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
