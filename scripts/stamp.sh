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

# --- answers -----------------------------------------------------------------

get() { # get <key> [default]
  local line
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
  TRUNK="$(git -C "$TARGET" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  [[ -n "$TRUNK" ]] || TRUNK="$(git -C "$TARGET" branch --show-current 2>/dev/null || true)"
fi
[[ -n "$TRUNK" ]] || TRUNK="main"

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

# --- stamping ------------------------------------------------------------------

stamp_tmpl() { # stamp_tmpl <abs-src> <abs-dest>
  local content
  content="$(<"$1")"
  # Conditional lines first: keep (marker stripped) or drop whole lines.
  if [[ "$OPUSPLAN" == "yes" ]]; then
    content="$(printf '%s\n' "$content" | sed 's/^{{IF:OPUSPLAN}}//')"
  else
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
  printf '%s\n' "$content" > "$2"
}

STAMPED=0
SKIPPED=()
for entry in "${PLAN[@]}"; do
  src="${entry%%	*}"
  dest="${entry#*	}"
  if skip "$dest"; then SKIPPED+=("$dest"); continue; fi
  mkdir -p "$TARGET/$(dirname "$dest")"
  if [[ "$src" == *.tmpl ]]; then
    stamp_tmpl "$TPL/$src" "$TARGET/$dest"
  else
    cp "$TPL/$src" "$TARGET/$dest"
  fi
  STAMPED=$((STAMPED + 1))
done
chmod +x "$TARGET/.claude/hooks/"*.sh 2>/dev/null || true

# specs/TEMPLATE.md: Appendix C extracted from the bundled edition at stamp
# time, unfenced (the template body between the ```markdown fences).
if skip "specs/TEMPLATE.md"; then
  SKIPPED+=("specs/TEMPLATE.md")
else
  mkdir -p "$TARGET/specs"
  "$SCRIPT_DIR/part.sh" appendix-c "$EDITION" \
    | awk '/^```/ { infence = !infence; next } infence { print }' \
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

echo "stamp.sh: stamped $STAMPED files into $TARGET (mode=$MODE, ui=$UI, opusplan=$OPUSPLAN, design_surface=$DESIGN_SURFACE, trunk=$TRUNK)"
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "stamp.sh: skipped existing files (retrofit; phase 2 merges by hand):"
  printf '  %s\n' "${SKIPPED[@]}"
fi
echo "stamp.sh: phase 2 (tailored generation) still owes every [PHASE 2 SLOT] marker."
