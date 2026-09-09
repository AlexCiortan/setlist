#!/usr/bin/env bash
# test/suite/10-delivery-and-ownership.sh: shard 10 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# OWNERSHIP IS WHAT EXECUTES, ASKED WHEREVER HOOKS LIVE (2.0.0 leg, F2+F6).
#
# Two holes in the displacement refusal README:176 promises, found by one leg.
# F2: `pre-commit install` and `lefthook install` wire the project's hooks into
# .git/hooks and leave core.hooksPath UNSET, and the guard returned early on
# unset, so --apply set core.hooksPath=.githooks and the project's own secret
# scan silently stopped firing. Two of the three tools the README names wire
# exactly this way, so "unset" is the COMMON foreign state, not the empty one.
# F6: hooks_layer_is_ours claimed a foreign hook as ours if any line merely
# CONTAINED the string setlist-hook-lib.sh, so an ordinary shellcheck-exclusion
# mention defeated the refusal and the foreign layer was overwritten. The
# ownership question is now positional: a file is ours when it is byte-identical
# to a shipped hook, or when the library appears where the shell would LOAD it
# (a source/dot target, or a standalone path word such as the resolver's
# candidate lines), never when it appears as data in some other command's
# argument list.
# =============================================================================

# F2, report mode: hooks at the DEFAULT .git/hooks with hooksPath unset must be
# named as a displacement, exactly as an explicit foreign hooksPath is.
RFI="$WORK/rfi-default-report"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-default-report.out" 2>&1
if grep -q 'DISPLACE' "$WORK/rfi-default-report.out" && grep -q '\.git/hooks' "$WORK/rfi-default-report.out"; then
  ok "refresh F2a: report mode names a foreign layer at the default .git/hooks (hooksPath unset)"
else
  bad "refresh F2a: report mode names a foreign layer at the default .git/hooks (hooksPath unset)" \
      "the report said nothing about the hook already installed in .git/hooks, which is how pre-commit and lefthook actually wire; the operator learns their secret scan is off only when it fails to fire"
fi

# F2, --apply: the probe pair from the leg's own replay. The commit is refused
# by the project's hook BEFORE the refresh; whatever --apply does, the refusal
# must still exist AFTER it, because "nothing was silently switched off" is the
# whole claim.
RFI="$WORK/rfi-default-apply"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
RFI_BEFORE=0; git -C "$RFI" commit --allow-empty -qm "probe before" >/dev/null 2>&1 || RFI_BEFORE=1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-default-apply.out" 2>&1
RFI_AFTER=0; git -C "$RFI" commit --allow-empty -qm "probe after" >/dev/null 2>&1 || RFI_AFTER=1
if [[ "$RFI_BEFORE" -eq 1 && "$RFI_AFTER" -eq 1 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-default-apply.out"; then
  ok "refresh F2b: --apply refuses to disarm a project's own .git/hooks layer, and the probe commit stays refused"
else
  bad "refresh F2b: --apply refuses to disarm a project's own .git/hooks layer, and the probe commit stays refused" \
      "probe refused before=$RFI_BEFORE after=$RFI_AFTER; a commit the project's hook refused before the refresh landing after it is the leg's F2 replay, verbatim"
fi

# F2, the deliberate override still works at the default location.
RFI="$WORK/rfi-default-adopt"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh F2c: SETLIST_ADOPT_HOOKSPATH=1 adopts over a .git/hooks layer on purpose"
else
  bad "refresh F2c: SETLIST_ADOPT_HOOKSPATH=1 adopts over a .git/hooks layer on purpose" \
      "the escape did not arm, so the new refusal is a dead end rather than a decision point"
fi

# F2, the stamp path has the same blind spot and must get the same refusal:
# retrofit is precisely the onto-an-existing-project case.
STF="$WORK/stamp-default-foreign"; rm -rf "$STF"; mkdir -p "$STF"
git_init "$STF"
printf 'x\n' > "$STF/keep.txt"; git -C "$STF" add -A >/dev/null 2>&1; git -C "$STF" commit -qm seed >/dev/null 2>&1
mkdir -p "$STF/.git/hooks"
printf '#!/bin/sh\necho "PROJECT PRE-COMMIT: secret scan refuses this commit" >&2\nexit 1\n' > "$STF/.git/hooks/pre-commit"
chmod +x "$STF/.git/hooks/pre-commit"
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF" >"$WORK/stamp-default.out" 2>&1
STF_RC=$?
STF_HP="$(git -C "$STF" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: empty means not armed, which is what the refusal direction wants
if [[ "$STF_RC" -ne 0 && "$STF_HP" != ".githooks" ]] && grep -qE 'refus|REFUS' "$WORK/stamp-default.out"; then
  ok "stamp F2d: a retrofit onto a project with its own .git/hooks layer refuses rather than disarming it"
else
  bad "stamp F2d: a retrofit onto a project with its own .git/hooks layer refuses rather than disarming it" \
      "rc=$STF_RC hooksPath=[$STF_HP]; a stamp that arms here switches off the host project's own hook layer, secret scanning included, while reporting success"
fi

# CONTROL for the F2 family: a fresh repository's .git/hooks holds only git's
# own .sample files, which are executable on most platforms. They are not a
# layer (git never runs them), so the ordinary arm must not start refusing.
RFI="$WORK/rfi-samples-only"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho sample\n' > "$RFI/.git/hooks/pre-commit.sample"
chmod +x "$RFI/.git/hooks/pre-commit.sample"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-samples.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] && ! grep -q 'DISPLACE' "$WORK/rfi-samples.out"; then
  ok "refresh F2 control: git's own .sample files do not read as a foreign layer"
else
  bad "refresh F2 control: git's own .sample files do not read as a foreign layer" \
      "the ordinary path stopped arming or warned about samples; this is the false-denial direction and it would fire on every fresh repository"
fi

# F6, the mention: a foreign hook whose text merely NAMES the library (an
# ordinary shellcheck exclusion in a repo that vendors hooks) is not ours.
RFI="$WORK/rfi-mention"; rfi_fixture "$RFI" .githooks
cat > "$RFI/.githooks/pre-commit" <<'MENTIONHOOK'
#!/bin/sh
# lint everything except the vendored setlist library
shellcheck $(git ls-files '*.sh' | grep -v setlist-hook-lib.sh) 2>/dev/null || true
echo "foreign hook refusing"
exit 1
MENTIONHOOK
chmod +x "$RFI/.githooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-mention.out" 2>&1
RFI_MENTION_SURVIVED=0
grep -q 'foreign hook refusing' "$RFI/.githooks/pre-commit" 2>/dev/null && RFI_MENTION_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-mention.out" && [[ "$RFI_MENTION_SURVIVED" -eq 1 ]]; then
  ok "refresh F6c: a hook that merely MENTIONS setlist-hook-lib.sh is not claimed as ours"
else
  bad "refresh F6c: a hook that merely MENTIONS setlist-hook-lib.sh is not claimed as ours" \
      "survived=$RFI_MENTION_SURVIVED; a grep-visible mention defeated the displacement refusal, so the ownership test is still a substring search rather than a question about what executes"
fi

# =============================================================================
# OWNERSHIP IS A SET OF BYTES, NOT A GRAMMAR (fix round 3, both adversary
# rounds). Two cold reviews broke every text reading of "does this file load
# our artifact", in both directions, seventeen shapes across two rounds; the
# session-gate parser history, replayed inside the guard. A hook is OURS when
# its content hash is in the set of bytes this project ever shipped for
# templates/git-hooks/ (the embedded blob list), or byte-identical to the
# current shipped file. An operator-ADJUSTED copy REFUSES with the file named
# and SETLIST_ADOPT_HOOKSPATH=1 as the one-step escape: a refusal with an
# escape is a decision point; a text guess is a displaced secret scanner or a
# silent adoption.
# =============================================================================

# The embedded blob list is NOT hand-maintained: whenever this suite runs
# where the repository history is visible, the list must contain every
# historical blob of templates/git-hooks/, so a hook edit that forgets to
# regenerate goes red in the commit that makes it.
if git -C "$ROOT" rev-list --all -- templates/git-hooks/ >/dev/null 2>&1 && [[ -n "$(git -C "$ROOT" rev-list --all -- templates/git-hooks/ 2>/dev/null | head -1)" ]]; then
  BLOB_MISSING=""
  while IFS= read -r bl; do
    [[ -n "$bl" ]] || continue
    ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; case "$KNOWN_SETLIST_HOOK_BLOBS" in *"$bl"*) exit 0 ;; *) exit 1 ;; esac ) \
      || BLOB_MISSING="$BLOB_MISSING $bl"
  done <<< "$(git -C "$ROOT" rev-list --all -- templates/git-hooks/ | while read -r c; do git -C "$ROOT" ls-tree "$c" -- templates/git-hooks/ | awk '{print $3}'; done | sort -u)"
  if [[ -z "$BLOB_MISSING" ]]; then
    ok "ownership blob list: every historical templates/git-hooks blob is in the embedded set"
  else
    bad "ownership blob list: every historical templates/git-hooks blob is in the embedded set" \
        "missing:$BLOB_MISSING; regenerate KNOWN_SETLIST_HOOK_BLOBS in setlist-delivery-lib.sh in this same commit (the recipe is in its comment)"
  fi
else
  ok "ownership blob list: history not visible here (export tree); the source-repo run asserts the list"
fi

# The REAL upgrade state: a layer built from an EARLIER commit's actual bytes
# must refresh cleanly. Gated on history visibility for the same reason.
OLDC="$(git -C "$ROOT" rev-list --all --skip=20 -- templates/git-hooks/ 2>/dev/null | head -1)"
if [[ -n "$OLDC" ]]; then
  RFI="$WORK/rfi-historical"; rfi_fixture "$RFI" ""
  mkdir -p "$RFI/.githooks"
  RFI_HIST_BUILT=1
  for h in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
    git -C "$ROOT" show "$OLDC:templates/git-hooks/$h" > "$RFI/.githooks/$h" 2>/dev/null || RFI_HIST_BUILT=0
  done
  chmod +x "$RFI/.githooks/"* 2>/dev/null
  git -C "$RFI" config core.hooksPath .githooks
  if [[ "$RFI_HIST_BUILT" -eq 1 ]]; then
    bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-hist.out" 2>&1
    if grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-hist.out"; then
      bad "refresh F6d: a layer of an earlier commit's REAL bytes refreshes cleanly" \
          "the upgrade path refused this project's own historical hooks (commit $OLDC); the blob list is not doing its one job"
    else
      ok "refresh F6d: a layer of an earlier commit's REAL bytes refreshes cleanly"
    fi
  else
    ok "refresh F6d: historical bytes incomplete at $OLDC (file set differed); skipped"
  fi
else
  ok "refresh F6d: history not visible here (export tree); the source-repo run asserts the upgrade state"
fi

# The ADJUSTED-copy direction, decided deliberately in fix round 3: an
# operator-annotated hook is NOT silently ours, it REFUSES with the escape
# working, because the two text-based attempts to bless adjusted copies were
# each broken by a $5 review in both directions.
RFI="$WORK/rfi-prepush-adjusted"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
printf '\n# instance note\n' >> "$RFI/.githooks/pre-push"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adj.out" 2>&1
RFI_ADJ_REFUSED=0
grep -qE 'REFUS|refusing to arm' "$WORK/rfi-adj.out" && RFI_ADJ_REFUSED=1
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adj2.out" 2>&1
if [[ "$RFI_ADJ_REFUSED" -eq 1 && "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]] \
   && ls "$RFI/.githooks/"*.setlist-backup >/dev/null 2>&1; then
  ok "refresh F6e: an adjusted copy refuses by name, and the escape adopts with a backup"
else
  bad "refresh F6e: an adjusted copy refuses by name, and the escape adopts with a backup" \
      "refused=$RFI_ADJ_REFUSED hooksPath=[$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)]; either an adjusted copy was silently claimed (the text-guess hole) or the escape is a dead end"
fi

# Adversary round 2, finding 1: a project whose own script is NAMED
# trunk-audit.sh must not donate its hook layer. End to end: the probe commit
# refused before must still be refused after a refusal-mode --apply.
RFI="$WORK/rfi-genericname"; rfi_fixture "$RFI" ""
mkdir -p "$RFI/.git/hooks" "$RFI/tools"
printf '#!/bin/sh\nexec tools/trunk-audit.sh\n' > "$RFI/.git/hooks/pre-commit"
printf '#!/bin/sh\necho "PROJECT SECRET SCAN RAN, COMMIT BLOCKED" >&2\nexit 1\n' > "$RFI/tools/trunk-audit.sh"
chmod +x "$RFI/.git/hooks/pre-commit" "$RFI/tools/trunk-audit.sh"
RFI_GN_BEFORE=0; git -C "$RFI" commit --allow-empty -qm probe >/dev/null 2>&1 || RFI_GN_BEFORE=1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-gn.out" 2>&1
RFI_GN_AFTER=0; git -C "$RFI" commit --allow-empty -qm probe2 >/dev/null 2>&1 || RFI_GN_AFTER=1
if [[ "$RFI_GN_BEFORE" -eq 1 && "$RFI_GN_AFTER" -eq 1 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-gn.out"; then
  ok "refresh F6f: a project's own script merely NAMED trunk-audit.sh does not donate its layer"
else
  bad "refresh F6f: a project's own script merely NAMED trunk-audit.sh does not donate its layer" \
      "probe before=$RFI_GN_BEFORE after=$RFI_GN_AFTER; a generic filename claimed ownership, which is the name-decides defect at one remove"
fi

# DIRECTION CONTROL: naming trunk-audit.sh as DATA is still nobody's.
RFI="$WORK/rfi-ta-mention"; rfi_fixture "$RFI" .githooks
cat > "$RFI/.githooks/pre-push" <<'TAMENTION'
#!/bin/sh
# lint all scripts except the vendored audit tool
shellcheck $(git ls-files '*.sh' | grep -v trunk-audit.sh) 2>/dev/null || true
echo "foreign pre-push refusing"
exit 1
TAMENTION
chmod +x "$RFI/.githooks/pre-push"
rm -f "$RFI/.githooks/pre-commit"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-tament.out" 2>&1
RFI_TAM_SURVIVED=0
grep -q 'foreign pre-push refusing' "$RFI/.githooks/pre-push" 2>/dev/null && RFI_TAM_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-tament.out" && [[ "$RFI_TAM_SURVIVED" -eq 1 ]]; then
  ok "refresh F6g: a hook that merely MENTIONS trunk-audit.sh is not claimed as ours"
else
  bad "refresh F6g: a hook that merely MENTIONS trunk-audit.sh is not claimed as ours" \
      "survived=$RFI_TAM_SURVIVED; widening identity to the second artifact must not reopen the mention hole it was built to close"
fi

# =============================================================================
# A RUN THAT ENDS IN REFUSAL WRITES NOTHING, generically (second 2.0.0 leg, F5).
#
# The F6 second-order lesson ("the refusal comes before the first write")
# recurred one layer up: the displacement refusal was hoisted above the
# .githooks copy loop, and the four .claude/hooks session-gate copies sat
# seventy lines EARLIER still, so --apply performed four unbacked writes and
# then printed "Nothing has been changed." The assertion here is the CLASS,
# not the instance: snapshot every file in the instance plus the two config
# values, run an --apply that must refuse, and require the snapshot identical.
# Any future write added above the refusal fails this without a new test.
# =============================================================================
rfi_snapshot() { # rfi_snapshot <dir> -> content+config fingerprint on stdout
  ( cd "$1" && find . -path ./.git -prune -o -type f -print0 2>/dev/null \
      | sort -z | xargs -0 shasum 2>/dev/null )
  git -C "$1" config --get core.hooksPath 2>/dev/null || printf 'hooksPath-unset\n'
  git -C "$1" config --get merge.ff 2>/dev/null || printf 'merge.ff-unset\n'
}
RFI="$WORK/rfi-nowrite"; rfi_fixture "$RFI" ""
for h in scope-hook commit-gate close-gate regrounding-hook stop-hook; do
  printf '#!/bin/sh\n# PROJECT FORK of %s\nexit 0\n' "$h" > "$RFI/.claude/hooks/$h.sh"
done
mkdir -p "$RFI/.git/hooks"
printf '#!/bin/sh\necho "project secret scan refuses" >&2\nexit 1\n' > "$RFI/.git/hooks/pre-commit"
chmod +x "$RFI/.git/hooks/pre-commit"
RFI_SNAP_BEFORE="$(rfi_snapshot "$RFI")"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-nowrite.out" 2>&1
RFI_NOWRITE_RC=$?
RFI_SNAP_AFTER="$(rfi_snapshot "$RFI")"
if [[ "$RFI_NOWRITE_RC" -ne 0 && "$RFI_SNAP_BEFORE" == "$RFI_SNAP_AFTER" ]] && grep -qE 'refus|REFUS' "$WORK/rfi-nowrite.out"; then
  ok "refresh F5: a refused --apply writes NOTHING, snapshot-identical across the whole instance"
else
  bad "refresh F5: a refused --apply writes NOTHING, snapshot-identical across the whole instance" \
      "rc=$RFI_NOWRITE_RC; a refusal whose message says nothing changed printed over an instance whose files moved: $(diff <(printf '%s' "$RFI_SNAP_BEFORE") <(printf '%s' "$RFI_SNAP_AFTER") | head -4 | tr '\n' ' ')"
fi
# DIRECTION CONTROL: the same fixture WITH the override applies fully, so the
# no-write property is the refusal's and not a general paralysis.
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]] \
   && cmp -s "$HOOKS/close-gate.sh" "$RFI/.claude/hooks/close-gate.sh"; then
  ok "refresh F5 control: the adopted run still delivers both layers in full"
else
  bad "refresh F5 control: the adopted run still delivers both layers in full" \
      "the no-write fix went too far: the deliberate override no longer refreshes"
fi

# =============================================================================
# THE GUARD RESOLVES core.hooksPath THE WAY GIT DOES (second 2.0.0 leg, F7).
#
# git expands a tilde in core.hooksPath and RUNS the layer there; the guard
# treated the value as repo-relative, built <repo>/~/.githooks, found nothing,
# and --apply silently displaced the layer README promises to refuse while
# report mode called the setting unset. Raw on one side, normalized on the
# other: the slh_trunk lesson, recurred in a path. The corpus below drives the
# SPELLINGS (tilde, relative, absolute, trailing slash), each both directions.
# =============================================================================
RFI_HP_BAD=""
rfi_hp_case() { # rfi_hp_case <label> <configured-value> <real-dir-under> <want: refuse|arm>
  local label="$1" spelled="$2" where="$3" want="$4"
  local d="$WORK/rfi-hp-$label" fh="$WORK/rfi-hp-home-$label"
  rm -rf "$d" "$fh"; mkdir -p "$fh"
  rfi_fixture "$d" ""
  local hookdir
  case "$where" in
    home) hookdir="$fh/.githooks" ;;
    *)    hookdir="$d/$where" ;;
  esac
  mkdir -p "$hookdir"
  printf '#!/bin/sh\necho "foreign layer refusing"\nexit 1\n' > "$hookdir/pre-commit"
  chmod +x "$hookdir/pre-commit"
  git -C "$d" config core.hooksPath "$spelled"
  HOME="$fh" bash "$SCRIPTS/refresh-instance.sh" --apply "$d" >"$WORK/rfi-hp-$label.out" 2>&1
  local rc=$? hp; hp="$(git -C "$d" config --get core.hooksPath 2>/dev/null || true)"
  if [[ "$want" == "refuse" ]]; then
    if [[ "$rc" -ne 0 && "$hp" == "$spelled" ]] && grep -qE 'refus|REFUS' "$WORK/rfi-hp-$label.out"; then :; else
      RFI_HP_BAD="$RFI_HP_BAD
    $label: spelled [$spelled], wanted refusal, got rc=$rc hooksPath=[$hp]; the layer git actually runs was silently displaced"
    fi
  else
    if [[ "$rc" -eq 0 && "$hp" == ".githooks" ]]; then :; else
      RFI_HP_BAD="$RFI_HP_BAD
    $label: spelled [$spelled], wanted a clean arm, got rc=$rc hooksPath=[$hp]; the normalization refuses what it should recognise"
    fi
  fi
}
# Adversary finding 2: git resolves a RELATIVE value against the work-tree
# TOP; an instance in a subdirectory must still see the repository's layer.
RFI_HP_SUB="$WORK/rfi-hp-subroot"; rm -rf "$RFI_HP_SUB"; mkdir -p "$RFI_HP_SUB/app/.claude/hooks" "$RFI_HP_SUB/.myhooks"
git_init "$RFI_HP_SUB"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_HP_SUB/app/.claude/sdd.json"
printf '#!/bin/sh\necho "top-level scan refusing"\nexit 1\n' > "$RFI_HP_SUB/.myhooks/pre-commit"
chmod +x "$RFI_HP_SUB/.myhooks/pre-commit"
git -C "$RFI_HP_SUB" config core.hooksPath .myhooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_HP_SUB/app" >"$WORK/rfi-hp-sub.out" 2>&1
# Round 4/5 semantics: below the top nothing arms at all, so the top-level
# layer is safe by construction; the assertion is that the run says so and
# touches no config, not that a displacement refusal fires.
if grep -q 'NOT ARMED' "$WORK/rfi-hp-sub.out" && [[ "$(git -C "$RFI_HP_SUB" config --get core.hooksPath)" == ".myhooks" ]] \
   && ! grep -qE 'refusing to arm' "$WORK/rfi-hp-sub.out"; then
  ok "refresh F7b: below the top the run arms nothing and says so; the top-level layer is untouched"
else
  RFI_HP_BAD="$RFI_HP_BAD
    subdir: hooksPath=[$(git -C "$RFI_HP_SUB" config --get core.hooksPath 2>/dev/null)] (adversary finding 2 / round-4 semantics)"
  bad "refresh F7b: below the top the run arms nothing and says so; the top-level layer is untouched" \
      "either config moved from a subdirectory run, or the skip was silent, or a refusal fired on a run that arms nothing"
fi
# Adversary finding 7: a ~user spelling under a git without --type=path is
# UNRESOLVABLE, and unresolvable fails CLOSED, never silent.
RFI_HP_OG="$WORK/rfi-hp-oldgit"; rm -rf "$RFI_HP_OG"; mkdir -p "$RFI_HP_OG/bin"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in --type=*) exit 129;; esac; done\nexec %s "$@"\n' "$(command -v git)" > "$RFI_HP_OG/bin/git"
chmod +x "$RFI_HP_OG/bin/git"
rfi_fixture "$RFI_HP_OG/inst" ""
git -C "$RFI_HP_OG/inst" config core.hooksPath "~$(id -un)/.githooks"
PATH="$RFI_HP_OG/bin:$PATH" bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_HP_OG/inst" >"$WORK/rfi-hp-og.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refus|REFUS' "$WORK/rfi-hp-og.out"; then
  ok "refresh F7c: a ~user hooksPath under a git without --type=path refuses rather than assuming"
else
  bad "refresh F7c: a ~user hooksPath under a git without --type=path refuses rather than assuming" \
      "an unresolvable spelling proceeded to arm; a guard that cannot see a layer must not conclude it is absent"
fi
rfi_hp_case tilde '~/.githooks' home refuse
rfi_hp_case tildeslash '~/.githooks/' home refuse
rfi_hp_case relslash '.theirs/' '.theirs' refuse
rfi_hp_case abs "$WORK/rfi-hp-absdir" ../rfi-hp-absdir refuse
# The ours direction: a layer of OUR OWN hooks reachable only via tilde must
# not be refused (the guard recognises it and the arm proceeds).
RFI="$WORK/rfi-hp-ours"; FH="$WORK/rfi-hp-home-ours"; rm -rf "$RFI" "$FH"
mkdir -p "$FH/.githooks"; rfi_fixture "$RFI" ""
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
   "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$FH/.githooks/"
chmod +x "$FH/.githooks/"*
git -C "$RFI" config core.hooksPath '~/.githooks'
HOME="$FH" bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-hp-ours.out" 2>&1
# The rc is NOT asserted zero: this fixture has no settings wiring, so a full
# arm legitimately exits 3 (INCOMPLETE), exactly like the plain refresh
# control above. What the ours-direction claims is narrower: recognised (no
# displacement refusal) and armed.
if [[ "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]] \
   && ! grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-hp-ours.out"; then :; else
  RFI_HP_BAD="$RFI_HP_BAD
    ours-tilde: our own layer spelled with a tilde was refused or the arm did not complete (hooksPath=[$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)])"
fi
if [[ -z "$RFI_HP_BAD" ]]; then
  ok "refresh F7: core.hooksPath is resolved the way git resolves it, five spellings both directions"
else
  bad "refresh F7: core.hooksPath is resolved the way git resolves it, five spellings both directions" \
      "raw-vs-normalized in a path:$RFI_HP_BAD"
fi

# =============================================================================
# THE TEXT-SHAPE CORPUS IS NOW A ONE-SIDED CONTROL (fix round 3, final form).
#
# Under hash ownership every text shape the two adversary rounds produced is
# FOREIGN, because no text confers ownership at all. The corpus is kept as a
# standing control that no future "convenience" clause quietly reintroduces a
# grammar: if any of these ever reads as ours, someone has started parsing
# again.
# =============================================================================
OWN_CORPUS_BAD=""
own_case() { # own_case <name> <want: ours|foreign> <<'BODY'
  local name="$1" want="$2" f="$WORK/own-corpus-$1" got
  cat > "$f"; chmod +x "$f"
  if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; setlist_hook_blob_is_known "$f" ); then got=ours; else got=foreign; fi
  [[ "$got" == "$want" ]] || OWN_CORPUS_BAD="$OWN_CORPUS_BAD
    $name: predicate said $got, the shape is $want"
}
own_case lint-skip-data foreign <<'B'
#!/bin/sh
bash tools/shellcheck-all.sh --skip trunk-audit.sh
B
own_case exec-arg-data foreign <<'B'
#!/bin/sh
exec shellcheck --external-sources setlist-hook-lib.sh
B
own_case dot-arg-data foreign <<'B'
#!/bin/sh
. ./ci/lib.sh --skip trunk-audit.sh
B
own_case usage-string foreign <<'B'
#!/bin/sh
echo "to enable: source hooks/trunk-audit.sh" >&2
B
own_case diff-dot-arg foreign <<'B'
#!/bin/sh
diff -q . vendor/trunk-audit.sh >/dev/null || echo drift
B
own_case var-load foreign <<'B'
#!/usr/bin/env bash
LIB="$(dirname "$0")/setlist-hook-lib.sh"
. "$LIB"
slh_main "$@"
B
own_case one-line-resolver foreign <<'B'
#!/bin/sh
for cand in "$X/setlist-hook-lib.sh" "$Y/setlist-hook-lib.sh"; do :; done
B
own_case generic-name-exec foreign <<'B'
#!/bin/sh
exec tools/trunk-audit.sh
B
# The OURS side is bytes, not text: the current shipped file's exact content.
cp "$ROOT/templates/git-hooks/pre-push" "$WORK/own-corpus-shipped"; chmod +x "$WORK/own-corpus-shipped"
if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; setlist_hook_blob_is_known "$WORK/own-corpus-shipped" ); then :; else
  OWN_CORPUS_BAD="$OWN_CORPUS_BAD
    shipped-bytes: the current shipped pre-push is not in its own blob list"
fi
if [[ -z "$OWN_CORPUS_BAD" ]]; then
  ok "ownership corpus: eight text shapes are nobody's, the shipped bytes are ours"
else
  bad "ownership corpus: eight text shapes are nobody's, the shipped bytes are ours" \
      "a text shape moved sides, so a grammar is creeping back into a hash question:$OWN_CORPUS_BAD"
fi

# =============================================================================
# THE HASH IS CONTEXT-FREE AND BLINDNESS FAILS CLOSED (adversary round 3).
# =============================================================================
OWN_CTX_BAD=""
# finding 1/2: the verdict must not depend on the caller's cwd, the repo's
# object format, or its clean filters.
OWN_CTX_R="$WORK/own-ctx-repo"; rm -rf "$OWN_CTX_R"
if git init -q --object-format=sha256 "$OWN_CTX_R" 2>/dev/null; then :; else git init -q "$OWN_CTX_R"; fi
printf '* filter=x\n' > "$OWN_CTX_R/.gitattributes"
git -C "$OWN_CTX_R" config filter.x.clean 'tr a-z A-Z'
if ( cd "$OWN_CTX_R" && GITHOOKS_SRC="$ROOT/templates/git-hooks" && source "$ROOT/scripts/setlist-delivery-lib.sh" && setlist_hook_blob_is_known "$ROOT/templates/git-hooks/pre-push" ); then :; else
  OWN_CTX_BAD="$OWN_CTX_BAD
    context: the shipped pre-push stopped being ours when judged from inside a sha256/filtered repo cwd"
fi
# finding 4: an unreadable hooks directory is refused, never vouched for.
OWN_CTX_D="$WORK/own-ctx-unread"; rm -rf "$OWN_CTX_D"; mkdir -p "$OWN_CTX_D"
printf '#!/bin/sh\nexit 1\n' > "$OWN_CTX_D/pre-commit"; chmod +x "$OWN_CTX_D/pre-commit"; chmod 000 "$OWN_CTX_D"
if perm_fixture_bites "$OWN_CTX_D" "ownership context blindness"; then
  if ( GITHOOKS_SRC="$ROOT/templates/git-hooks"; source "$ROOT/scripts/setlist-delivery-lib.sh"; hooks_layer_is_ours "$OWN_CTX_D" ); then
    OWN_CTX_BAD="$OWN_CTX_BAD
    unreadable: a directory the guard cannot list was vouched for as ours"
  fi
fi
chmod 755 "$OWN_CTX_D"
if [[ -z "$OWN_CTX_BAD" ]]; then
  ok "ownership context: the hash is cwd/format/filter-independent and blindness refuses"
else
  bad "ownership context: the hash is cwd/format/filter-independent and blindness refuses" \
      "the verdict depended on where the operator stood, or blindness passed:$OWN_CTX_BAD"
fi

# Adversary round 3, finding 3: the ALREADY-ARMED exemption. An armed instance
# that gained one extra hook (the git-lfs shape) refreshes rather than
# dead-ending: nothing is displaced because the arm changes nothing about
# where git looks; our-named files are replaced with backups.
RFI="$WORK/rfi-armed-extra"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
printf '#!/bin/sh\ngitleaks protect --staged || exit 1\n' > "$RFI/.githooks/commit-msg"
chmod +x "$RFI/.githooks/commit-msg"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-armed-extra.out" 2>&1
if ! grep -qE 'refusing to arm' "$WORK/rfi-armed-extra.out" \
   && [[ -x "$RFI/.githooks/commit-msg" ]] \
   && [[ "$(git -C "$RFI" config --get core.hooksPath)" == ".githooks" ]]; then
  ok "refresh F6h: an armed instance with one extra hook refreshes; nothing is displaced by a no-op arm"
else
  bad "refresh F6h: an armed instance with one extra hook refreshes; nothing is displaced by a no-op arm" \
      "the refusal told the operator to move their checks into the directory they were already in, and every git-lfs install dead-ended the refresh"
fi
# The refusal, where it IS real, names the foreign files (finding 3's message half).
RFI="$WORK/rfi-named"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-named.out" 2>&1
if grep -q 'foreign: pre-commit' "$WORK/rfi-named.out"; then
  ok "refresh F6i: the displacement refusal names the foreign files it protects"
else
  bad "refresh F6i: the displacement refusal names the foreign files it protects" \
      "the refusal gestured at a directory without naming what runs there"
fi

# Adversary round 3 finding 5, softened by round 4 finding 6: an instance
# below the worktree top gets its ADVISORY hooks refreshed, the git-hook
# boundary is skipped LOUDLY with the reason, nothing touches config, and the
# run exits 3 because part of the promise is not in force.
RFI_SUB="$WORK/rfi-subinst"; rm -rf "$RFI_SUB"; mkdir -p "$RFI_SUB/app/.claude/hooks"
git_init "$RFI_SUB"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_SUB/app/.claude/sdd.json"
printf '#!/bin/sh\n# stale close gate\n' > "$RFI_SUB/app/.claude/hooks/close-gate.sh"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_SUB/app" >"$WORK/rfi-subinst.out" 2>&1
RFI_SUB_RC=$?
RFI_SUB_BAD=""
[[ "$RFI_SUB_RC" -eq 3 ]] || RFI_SUB_BAD="$RFI_SUB_BAD rc=$RFI_SUB_RC(want 3)"
grep -q 'NOT ARMED' "$WORK/rfi-subinst.out" || RFI_SUB_BAD="$RFI_SUB_BAD no-not-armed-note"
[[ -z "$(git -C "$RFI_SUB" config --get core.hooksPath 2>/dev/null)" ]] || RFI_SUB_BAD="$RFI_SUB_BAD parent-config-touched"
[[ ! -e "$RFI_SUB/app/.githooks" ]] || RFI_SUB_BAD="$RFI_SUB_BAD githooks-delivered-inert"
cmp -s "$HOOKS/close-gate.sh" "$RFI_SUB/app/.claude/hooks/close-gate.sh" || RFI_SUB_BAD="$RFI_SUB_BAD advisory-not-refreshed"
if [[ -z "$RFI_SUB_BAD" ]]; then
  ok "refresh F6j: below the worktree top the advisory layer refreshes, the boundary skips loudly, exit 3"
else
  bad "refresh F6j: below the worktree top the advisory layer refreshes, the boundary skips loudly, exit 3" \
      "problems:$RFI_SUB_BAD; either an inert boundary shipped under a success message, or the advisory refresh was held hostage to a config git cannot honor here"
fi
# The stamp path: same start state, one decision computed BEFORE any write, so
# a target that does not exist yet cannot dodge the guard (round 4, finding 1).
STF_SUB="$WORK/stamp-subinst"; rm -rf "$STF_SUB"; mkdir -p "$STF_SUB"
git_init "$STF_SUB"
mkdir -p "$STF_SUB/.git/hooks"
printf '#!/bin/sh\necho "MONOREPO GITLEAKS refuses" >&2\nexit 1\n' > "$STF_SUB/.git/hooks/pre-commit"
chmod +x "$STF_SUB/.git/hooks/pre-commit"
printf 'x\n' > "$STF_SUB/keep.txt"; git -C "$STF_SUB" add keep.txt >/dev/null 2>&1
STF_SUB_BEFORE=0; git -C "$STF_SUB" commit -qm probe >/dev/null 2>&1 || STF_SUB_BEFORE=1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF_SUB/apps/newapp" >"$WORK/stamp-subinst.out" 2>&1
STF_SUB_BAD=""
grep -q 'NOT ARMED' "$WORK/stamp-subinst.out" || STF_SUB_BAD="$STF_SUB_BAD no-not-armed-note"
[[ -z "$(git -C "$STF_SUB" config --get core.hooksPath 2>/dev/null)" ]] || STF_SUB_BAD="$STF_SUB_BAD monorepo-config-armed"
STF_SUB_AFTER=0; git -C "$STF_SUB" commit -qm probe2 --allow-empty >/dev/null 2>&1 || STF_SUB_AFTER=1
[[ "$STF_SUB_BEFORE" -eq 1 && "$STF_SUB_AFTER" -eq 1 ]] || STF_SUB_BAD="$STF_SUB_BAD gitleaks-disarmed(before=$STF_SUB_BEFORE after=$STF_SUB_AFTER)"
if [[ -z "$STF_SUB_BAD" ]]; then
  ok "stamp F6k: a not-yet-existing subdir target cannot dodge the arming decision; the monorepo layer keeps running"
else
  bad "stamp F6k: a not-yet-existing subdir target cannot dodge the arming decision; the monorepo layer keeps running" \
      "problems:$STF_SUB_BAD; two is-inside-work-tree tests at different times is how the mkdir smuggled the arm past both guards"
fi
# Round 4, finding 2: an armed .githooks the guard cannot LIST voids the
# exemption; the refusal fires instead of a silent overwrite.
RFI_300="$WORK/rfi-mode300"; rfi_fixture "$RFI_300" ""
mkdir -p "$RFI_300/.githooks"
printf '#!/bin/sh\nexec gitleaks protect --staged\n' > "$RFI_300/.githooks/pre-commit"
chmod 755 "$RFI_300/.githooks/pre-commit"
git -C "$RFI_300" config core.hooksPath .githooks
chmod 300 "$RFI_300/.githooks"
if ! perm_fixture_bites "$RFI_300/.githooks" "refresh F6l"; then
  chmod 755 "$RFI_300/.githooks"
  RFI_300_SKIPPED=1
else
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_300" >"$WORK/rfi-mode300.out" 2>&1
RFI_300_RC=$?
chmod 755 "$RFI_300/.githooks"
if [[ "$RFI_300_RC" -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/rfi-mode300.out" \
   && grep -q 'exec gitleaks' "$RFI_300/.githooks/pre-commit"; then
  ok "refresh F6l: an armed layer the guard cannot list refuses; blindness voids the exemption too"
else
  bad "refresh F6l: an armed layer the guard cannot list refuses; blindness voids the exemption too" \
      "rc=$RFI_300_RC; a mode-300 directory slid past the exemption and a live scanner was overwritten"
fi
fi
# Round 4, finding 3: the ./.githooks spelling reaches the same exemption.
RFI_DOT="$WORK/rfi-dotslash"; rfi_fixture "$RFI_DOT" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DOT" >/dev/null 2>&1
printf '#!/bin/sh\ngit lfs post-checkout "$@"\n' > "$RFI_DOT/.githooks/post-checkout"
chmod 755 "$RFI_DOT/.githooks/post-checkout"
git -C "$RFI_DOT" config core.hooksPath ./.githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DOT" >"$WORK/rfi-dotslash.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-dotslash.out" && [[ -x "$RFI_DOT/.githooks/post-checkout" ]]; then
  ok "refresh F6m: the ./.githooks spelling reaches the already-armed exemption like its siblings"
else
  bad "refresh F6m: the ./.githooks spelling reaches the already-armed exemption like its siblings" \
      "a dot-segment spelling git treats as identical dead-ended the refresh; the normalizer stops at trailing slashes"
fi

# =============================================================================
# ROUND 5 PINS: the softened paths tell one truth everywhere.
# =============================================================================
# F1: below the top WITH a foreign layer at the parent's default dir, the
# advisory refresh still proceeds (nothing arms, so nothing displaces).
RFI_R51="$WORK/rfi-r5-subforeign"; rm -rf "$RFI_R51"; mkdir -p "$RFI_R51/app/.claude/hooks"
git_init "$RFI_R51"
mkdir -p "$RFI_R51/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$RFI_R51/.git/hooks/pre-commit"; chmod +x "$RFI_R51/.git/hooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_R51/app/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R51/app" >"$WORK/rfi-r51.out" 2>&1
RFI_R51_RC=$?
if [[ "$RFI_R51_RC" -eq 3 ]] && ! grep -q 'refusing to arm' "$WORK/rfi-r51.out" \
   && cmp -s "$HOOKS/close-gate.sh" "$RFI_R51/app/.claude/hooks/close-gate.sh" \
   && grep -q 'NOT ARMED' "$WORK/rfi-r51.out"; then
  ok "refresh R5a: below the top, a parent-layer foreign dir does not block the advisory refresh"
else
  bad "refresh R5a: below the top, a parent-layer foreign dir does not block the advisory refresh" \
      "rc=$RFI_R51_RC; the displacement refusal fired on a run that was never going to arm anything"
fi
# F2: report mode and apply mode describe the same future below the top.
bash "$SCRIPTS/refresh-instance.sh" "$RFI_R51/app" >"$WORK/rfi-r52.out" 2>&1
if grep -q 'NOT ARMED here and will not be' "$WORK/rfi-r52.out" && ! grep -q 'git config still to set' "$WORK/rfi-r52.out"; then
  ok "refresh R5b: report mode says NOT ARMED where apply will not arm, promising nothing it skips"
else
  bad "refresh R5b: report mode says NOT ARMED where apply will not arm, promising nothing it skips" \
      "the decision surface promised the boundary that apply then skipped"
fi
# F3: stamp exits 4 for the skip-subdir state and its tail names the reason.
STF_R5="$WORK/stamp-r5-sub"; rm -rf "$STF_R5"; mkdir -p "$STF_R5"; git_init "$STF_R5"
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STF_R5/app" >"$WORK/stamp-r5.out" 2>&1
STF_R5_RC=$?
if [[ "$STF_R5_RC" -eq 4 ]] && grep -q 'below its worktree top or is a linked worktree' "$WORK/stamp-r5.out" \
   && ! grep -q 'no repository yet' "$WORK/stamp-r5.out"; then
  ok "stamp R5c: skip-subdir exits 4 and the last line names the real reason, not /scaffold"
else
  bad "stamp R5c: skip-subdir exits 4 and the last line names the real reason, not /scaffold" \
      "rc=$STF_R5_RC; the tail advised the displacement the run just refused, at exit 0 no caller could see"
fi
# F4: a linked worktree never arms (the config is shared with the main).
LW="$WORK/rfi-linked"; rm -rf "$LW"; mkdir -p "$LW/main"
git_init "$LW/main"
mkdir -p "$LW/main/.husky"
printf '#!/bin/sh\nexit 1\n' > "$LW/main/.husky/pre-commit"; chmod +x "$LW/main/.husky/pre-commit"
git -C "$LW/main" config core.hooksPath .husky
printf 'x\n' > "$LW/main/f"; git -C "$LW/main" add f >/dev/null 2>&1; git -C "$LW/main" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git -C "$LW/main" worktree add -q "$LW/lw" -b lwb >/dev/null 2>&1
mkdir -p "$LW/lw/.claude/hooks"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$LW/lw/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$LW/lw" >"$WORK/rfi-lw.out" 2>&1
if [[ "$(git -C "$LW/main" config --get core.hooksPath)" == ".husky" ]] && grep -q 'LINKED worktree' "$WORK/rfi-lw.out"; then
  ok "refresh R5d: a linked worktree refreshes advisory-only; the main worktree's layer is untouched"
else
  bad "refresh R5d: a linked worktree refreshes advisory-only; the main worktree's layer is untouched" \
      "hooksPath=[$(git -C "$LW/main" config --get core.hooksPath 2>/dev/null)]; the shared config was repointed from a worktree whose guard could not see the main's layer"
fi
# F5: a CONFIGURED hooks dir that is absent refuses; the default's absence means nothing.
RFI_ABS="$WORK/rfi-absdir"; rfi_fixture "$RFI_ABS" ""
git -C "$RFI_ABS" config core.hooksPath "$WORK/rfi-absdir-mnt"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_ABS" >"$WORK/rfi-abs.out" 2>&1
RFI_ABS_RC=$?
if [[ "$RFI_ABS_RC" -ne 0 && "$(git -C "$RFI_ABS" config --get core.hooksPath)" != ".githooks" ]] && grep -qE 'refus' "$WORK/rfi-abs.out"; then
  ok "refresh R5e: a configured-but-absent hooks dir refuses; the guard does not vouch for what it cannot see"
else
  bad "refresh R5e: a configured-but-absent hooks dir refuses; the guard does not vouch for what it cannot see" \
      "rc=$RFI_ABS_RC hooksPath=[$(git -C "$RFI_ABS" config --get core.hooksPath 2>/dev/null)]; an unmounted layer was destroyed silently"
fi
# F6: the .// spelling reaches the exemption like its siblings.
RFI_DS="$WORK/rfi-dslash"; rfi_fixture "$RFI_DS" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DS" >/dev/null 2>&1
printf '#!/bin/sh\nexit 0\n' > "$RFI_DS/.githooks/commit-msg"; chmod +x "$RFI_DS/.githooks/commit-msg"
git -C "$RFI_DS" config core.hooksPath './/.githooks'
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_DS" >"$WORK/rfi-ds.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-ds.out"; then
  ok "refresh R5f: the .//.githooks spelling reaches the already-armed exemption"
else
  bad "refresh R5f: the .//.githooks spelling reaches the already-armed exemption" \
      "a doubled slash git treats as nothing dead-ended the refresh"
fi

# =============================================================================
# ROUND 6 PINS.
# =============================================================================
# R6-1: an armed instance whose .githooks was cleaned away re-arms (the absent
# arming target is ours to create); an absent dir ELSEWHERE still refuses.
RFI_R61="$WORK/rfi-r6-cleaned"; rfi_fixture "$RFI_R61" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R61" >/dev/null 2>&1
rm -rf "$RFI_R61/.githooks"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R61" >"$WORK/rfi-r61.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-r61.out" && [[ -x "$RFI_R61/.githooks/pre-commit" ]]; then
  ok "refresh R6a: a cleaned-away .githooks re-arms; the absent arming target is ours to create"
else
  bad "refresh R6a: a cleaned-away .githooks re-arms; the absent arming target is ours to create" \
      "git clean -fdx dead-ended the instance with a refusal naming a layer that does not exist"
fi
# R6-2: a CRLF checkout of our own hooks is still ours.
RFI_R62="$WORK/rfi-r6-crlf"; rfi_fixture "$RFI_R62" ""
mkdir -p "$RFI_R62/.githooks"
for h in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
  sed $'s/$/\r/' "$ROOT/templates/git-hooks/$h" > "$RFI_R62/.githooks/$h"
done
chmod +x "$RFI_R62/.githooks/pre-commit" "$RFI_R62/.githooks/pre-merge-commit" "$RFI_R62/.githooks/pre-push"
git -C "$RFI_R62" config core.hooksPath .githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R62" >"$WORK/rfi-r62.out" 2>&1
if ! grep -q 'refusing to arm' "$WORK/rfi-r62.out"; then
  ok "refresh R6b: a CRLF checkout of our own hooks is still ours (git rewrote the bytes, not the operator)"
else
  bad "refresh R6b: a CRLF checkout of our own hooks is still ours (git rewrote the bytes, not the operator)" \
      "the ordinary Windows checkout was named foreign and every upgrade dead-ended"
fi
# R6-3: a linked worktree still receives trunk-audit.sh with the advisory half.
LW6="$WORK/rfi-r6-lw"; rm -rf "$LW6"; mkdir -p "$LW6/main/.claude/hooks"
git_init "$LW6/main"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$LW6/main/.claude/sdd.json"
git -C "$LW6/main" add -A >/dev/null 2>&1; git -C "$LW6/main" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git -C "$LW6/main" worktree add -q "$LW6/lw" -b lw6 >/dev/null 2>&1
mkdir -p "$LW6/lw/.claude/hooks"
bash "$SCRIPTS/refresh-instance.sh" --apply "$LW6/lw" >/dev/null 2>&1
if [[ -f "$LW6/lw/.claude/hooks/trunk-audit.sh" ]]; then
  ok "refresh R6c: the linked worktree receives trunk-audit.sh with the advisory half"
else
  bad "refresh R6c: the linked worktree receives trunk-audit.sh with the advisory half" \
      "the tool pre-push resolves was skipped with the boundary and every push would be refused for want of it"
fi
# R6-5: stamp's linked-worktree skip names the shared config, not the top.
STL="$WORK/stamp-r6-lw"; rm -rf "$STL"; mkdir -p "$STL/main"
git_init "$STL/main"
git -C "$STL/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$STL/main" worktree add -q "$STL/lw" -b lw6b >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$WORK/answers.txt" "$STL/lw" >"$WORK/stamp-r6.out" 2>&1
STL_RC=$?
if [[ "$STL_RC" -eq 4 ]] && grep -q 'LINKED worktree' "$WORK/stamp-r6.out" && ! grep -q 'sits BELOW the top' "$WORK/stamp-r6.out"; then
  ok "stamp R6d: the linked-worktree skip names the shared config, not a top the operator is already at"
else
  bad "stamp R6d: the linked-worktree skip names the shared config, not a top the operator is already at" \
      "rc=$STL_RC; the diagnostic told the operator to go where they were standing"
fi

# =============================================================================
# ROUND 7 PINS: the arming target is inspected before it is armed.
# =============================================================================
# R7-F1: the fresh-clone state (tracked .githooks, config never clones) must
# refuse on both delivery paths, and ADOPT must truly install OUR boundary
# with a named backup rather than keeping the foreign file under an ARMED line.
R7O="$WORK/r7-origin"; rm -rf "$R7O" "$WORK/r7-clone"
git_init "$R7O"
mkdir -p "$R7O/.githooks"
printf '#!/bin/sh\necho "project scanner refuses" >&2\nexit 1\n' > "$R7O/.githooks/pre-commit"
chmod +x "$R7O/.githooks/pre-commit"
git -C "$R7O" add -A >/dev/null 2>&1; git -C "$R7O" -c core.hooksPath=/dev/null commit -qm i >/dev/null 2>&1
git clone -q "$R7O" "$WORK/r7-clone" 2>/dev/null
git -C "$WORK/r7-clone" config user.email t@t; git -C "$WORK/r7-clone" config user.name t
R7_ANS="$WORK/answers-retrofit.txt"
# get() takes the LAST match, so appending mode=retrofit is authoritative
# whatever the base file carries. The first cut sed-replaced a mode line that
# does not exist, ran mode=new, and R7a passed on a COLLISION refusal instead
# of the guard, which R7b then unmasked.
cat "$WORK/answers.txt" > "$R7_ANS"; printf 'mode=retrofit\n' >> "$R7_ANS"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$WORK/r7-clone" >"$WORK/r7-stamp.out" 2>&1
R7_RC=$?
if [[ "$R7_RC" -ne 0 && -z "$(git -C "$WORK/r7-clone" config --get core.hooksPath 2>/dev/null)" ]] \
   && grep -qE 'refusing to arm' "$WORK/r7-stamp.out" && grep -q 'project scanner' "$WORK/r7-clone/.githooks/pre-commit"; then
  ok "stamp R7a: the fresh-clone state refuses; a foreign target is not presented as an ARMED boundary"
else
  bad "stamp R7a: the fresh-clone state refuses; a foreign target is not presented as an ARMED boundary" \
      "rc=$R7_RC hooksPath=[$(git -C "$WORK/r7-clone" config --get core.hooksPath 2>/dev/null)]; every clone of a tracked-.githooks project is this state"
fi
SETLIST_ADOPT_HOOKSPATH=1 bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$WORK/r7-clone" >"$WORK/r7-adopt.out" 2>&1
if cmp -s "$ROOT/templates/git-hooks/pre-commit" "$WORK/r7-clone/.githooks/pre-commit" \
   && [[ -f "$WORK/r7-clone/.githooks/pre-commit.setlist-backup" ]] \
   && [[ "$(git -C "$WORK/r7-clone" config --get core.hooksPath)" == ".githooks" ]]; then
  ok "stamp R7b: ADOPT installs OUR boundary with a named backup; ARMED means armed with our hooks"
else
  bad "stamp R7b: ADOPT installs OUR boundary with a named backup; ARMED means armed with our hooks" \
      "the adopt path kept the foreign file under an ARMED report, or lost it without a backup"
fi
# R7-F1b: a dormant extra-name hook must not be switched on silently.
R7B="$WORK/r7-dormant"; rm -rf "$R7B"; git_init "$R7B"
mkdir -p "$R7B/.githooks"
printf '#!/bin/sh\nexit 1\n' > "$R7B/.githooks/commit-msg"; chmod +x "$R7B/.githooks/commit-msg"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R7B" >"$WORK/r7-dormant.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/r7-dormant.out" && [[ -z "$(git -C "$R7B" config --get core.hooksPath 2>/dev/null)" ]]; then
  ok "stamp R7c: arming does not silently switch on a dormant extra-name hook"
else
  bad "stamp R7c: arming does not silently switch on a dormant extra-name hook" \
      "a commit-msg that ran nowhere yesterday would run tomorrow with no line naming it"
fi
# The refresh path sees the same clone state the same way.
RFI_R7="$WORK/rfi-r7-clone"; rm -rf "$RFI_R7"
git clone -q "$R7O" "$RFI_R7" 2>/dev/null
mkdir -p "$RFI_R7/.claude/hooks"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$RFI_R7/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI_R7" >"$WORK/rfi-r7.out" 2>&1
if [[ $? -ne 0 ]] && grep -qE 'refusing to arm' "$WORK/rfi-r7.out" && grep -q 'project scanner' "$RFI_R7/.githooks/pre-commit"; then
  ok "refresh R7d: the clone state refuses identically on the refresh path; the two deliveries agree"
else
  bad "refresh R7d: the clone state refuses identically on the refresh path; the two deliveries agree" \
      "stamp and refresh returned different verdicts on byte-identical trees"
fi

# =============================================================================
# ROUND 8 PINS: the skip states write nothing live, refusals name the right
# directory, and a symlinked hook never bleeds outside the boundary.
# =============================================================================
# R8a: a linked worktree with a LIVE relative-hooksPath layer is untouched.
R8A="$WORK/r8-linkedlive"; rm -rf "$R8A"; mkdir -p "$R8A/main"
git_init "$R8A/main"
git -C "$R8A/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
mkdir -p "$R8A/main/.githooks"
printf '#!/bin/sh\nexit 1\n' > "$R8A/main/.githooks/pre-commit"; chmod +x "$R8A/main/.githooks/pre-commit"
git -C "$R8A/main" config core.hooksPath .githooks
git -C "$R8A/main" worktree add -q "$R8A/link" -b r8lb >/dev/null 2>&1
mkdir -p "$R8A/link/.githooks"
printf '#!/bin/sh\necho "LINK SCANNER refuses" >&2\nexit 1\n' > "$R8A/link/.githooks/pre-commit"
chmod +x "$R8A/link/.githooks/pre-commit"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R8A/link" >"$WORK/r8a.out" 2>&1
R8A_RC=$?
R8A_AFTER=0; git -C "$R8A/link" commit --allow-empty -qm p >/dev/null 2>&1 || R8A_AFTER=1
if [[ "$R8A_RC" -eq 4 && "$R8A_AFTER" -eq 1 ]] && grep -q 'LINK SCANNER' "$R8A/link/.githooks/pre-commit"; then
  ok "stamp R8a: the linked-worktree skip delivers no boundary files; a live per-worktree layer keeps running"
else
  bad "stamp R8a: the linked-worktree skip delivers no boundary files; a live per-worktree layer keeps running" \
      "rc=$R8A_RC after=$R8A_AFTER; the skip branch kept the destructive half and displaced a live scanner while promising inertness"
fi
# R8b: a refusal about the arming target names the target's files.
R8B="$WORK/r8-names"; rm -rf "$R8B"; git_init "$R8B"
mkdir -p "$R8B/.githooks" "$R8B/.claude/hooks"
printf '#!/bin/sh\nexit 1\n' > "$R8B/.githooks/pre-commit"
printf '#!/bin/sh\nexit 0\n' > "$R8B/.githooks/commit-msg"
chmod +x "$R8B/.githooks/"*
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R8B/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$R8B" >"$WORK/r8b.out" 2>&1
if grep -qE 'foreign: (commit-msg pre-commit|pre-commit commit-msg)' "$WORK/r8b.out"; then
  ok "refresh R8b: the arming-target refusal names the target's own files, never 'unresolvable'"
else
  bad "refresh R8b: the arming-target refusal names the target's own files, never 'unresolvable'" \
      "$(grep -o 'foreign: [^)]*' "$WORK/r8b.out" | head -1); the message listed a directory the refusal was not about"
fi
# R8c: replacing a SYMLINKED hook never touches the linked script.
R8C="$WORK/r8-symlink"; rm -rf "$R8C"; git_init "$R8C"
mkdir -p "$R8C/scripts" "$R8C/.githooks" "$R8C/.claude/hooks"
printf '#!/bin/sh\necho SCAN\nexit 1\n' > "$R8C/scripts/secrets.sh"; chmod +x "$R8C/scripts/secrets.sh"
ln -s ../scripts/secrets.sh "$R8C/.githooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R8C/.claude/sdd.json"
git -C "$R8C" config core.hooksPath .githooks
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$R8C" >"$WORK/r8c.out" 2>&1
if grep -q 'echo SCAN' "$R8C/scripts/secrets.sh" && [[ ! -L "$R8C/.githooks/pre-commit" ]] \
   && cmp -s "$ROOT/templates/git-hooks/pre-commit" "$R8C/.githooks/pre-commit" \
   && grep -q 'was a symlink' "$WORK/r8c.out"; then
  ok "refresh R8c: the adopt path replaces a symlinked hook without touching the linked script, and says so"
else
  bad "refresh R8c: the adopt path replaces a symlinked hook without touching the linked script, and says so" \
      "cp followed the link and destroyed a file outside .githooks/ while claiming the previous file was kept"
fi

# =============================================================================
# ROUND 9 PINS.
# =============================================================================
# R9a: a DANGLING symlink at a hook name never causes a write at its target.
R9A="$WORK/r9-dangling"; rm -rf "$R9A"; mkdir -p "$R9A/outside"; git_init "$R9A/proj"
mkdir -p "$R9A/proj/.githooks" "$R9A/proj/.claude/hooks"
ln -s ../../outside/planted "$R9A/proj/.githooks/pre-commit"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R9A/proj/.claude/sdd.json"
git -C "$R9A/proj" config core.hooksPath .githooks
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$R9A/proj" >"$WORK/r9a.out" 2>&1
if [[ ! -e "$R9A/outside/planted" && ! -L "$R9A/proj/.githooks/pre-commit" ]] \
   && cmp -s "$ROOT/templates/git-hooks/pre-commit" "$R9A/proj/.githooks/pre-commit" \
   && grep -q 'DANGLING' "$WORK/r9a.out"; then
  ok "refresh R9a: a dangling symlink is removed, named, and nothing is written at its target"
else
  bad "refresh R9a: a dangling symlink is removed, named, and nothing is written at its target" \
      "planted=$([[ -e "$R9A/outside/planted" ]] && echo yes || echo no); cp resolved a dangling link and created our hook body at a path the repository chose"
fi
# R9b: a Closing report inside an HTML comment is invisible to the gate the
# way it is to every renderer; a one-line comment in a real section is inert.
# Self-contained: qa_atx_run is defined in the qa corpus section BELOW this
# point in the file, so the readers are extracted inline here.
R9B_TF="$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")"
R9B_QA="$(grep -m1 -E '^[[:space:]]*QA_PASS1_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*QA_PASS1_AWK='//" -e "s/'$//")"
R9B_STATE="$(printf '# S\n\n<!--\n## Closing report\n\n```qa-pass-1\n1: PASS\n```\n-->\n' | awk "$R9B_TF" | awk "$R9B_QA")"
R9B_CTL="$(printf '## Closing report\n\n<!-- reviewed -->\n\n```qa-pass-1\n1: PASS\n```\n' | awk "$R9B_TF" | awk "$R9B_QA")"
if [[ "$R9B_STATE" == "none" && "$R9B_CTL" == "ok" ]]; then
  ok "qa R9b: an HTML-commented Closing report is invisible to the gate; a one-line comment is inert"
else
  bad "qa R9b: an HTML-commented Closing report is invisible to the gate; a one-line comment is inert" \
      "commented=$R9B_STATE (want none) control=$R9B_CTL (want ok); a spec that renders as nothing satisfied every close condition"
fi
# R9c: report mode warns about a refusal apply will make, even when the
# boundary files are current (the unreadable-armed state).
R9C="$WORK/r9-warn"; rfi_fixture "$R9C" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$R9C" >/dev/null 2>&1
chmod 300 "$R9C/.githooks"
# THIS IS THE ONE A CONTAINER ACTUALLY REPORTED (V1b): `808/1` on this assertion,
# against a tree this host runs green, because chmod is a no-op against uid 0 so
# .githooks stayed readable, apply had nothing to refuse, and report mode
# correctly said "present and byte-identical, config already set" -- which is
# verbatim the text the container read as a failure.
if perm_fixture_bites "$R9C/.githooks" "refresh R9c"; then
  bash "$SCRIPTS/refresh-instance.sh" "$R9C" >"$WORK/r9c.out" 2>&1
  chmod 755 "$R9C/.githooks"
  if grep -q 'apply will REFUSE' "$WORK/r9c.out"; then
    ok "refresh R9c: report mode names the refusal apply will make; no all-clear over a refusing state"
  else
    bad "refresh R9c: report mode names the refusal apply will make; no all-clear over a refusing state" \
        "the report said present-and-set while apply exits 1, the round-5 divergence class recurred"
  fi
else
  chmod 755 "$R9C/.githooks"
fi
# R9d: stamp's skip notes no longer claim files that were not delivered.
R9D="$WORK/r9-note"; rm -rf "$R9D"; mkdir -p "$R9D"; git_init "$R9D"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R9D/app" >"$WORK/r9d.out" 2>"$WORK/r9d.err"
if ! grep -q 'are stamped into .githooks' "$WORK/r9d.err" && grep -q 'NOT delivered here' "$WORK/r9d.err"; then
  ok "stamp R9d: the skip note says the boundary was not delivered, which is what happened"
else
  bad "stamp R9d: the skip note says the boundary was not delivered, which is what happened" \
      "a sentence that is false when it prints, contradicted by the same run's stdout"
fi

# =============================================================================
# >>> SHARD-BEGIN hooks-round11 cost=45
if shard_region hooks-round11; then
# ROUND 11 (CONFIRMING) PINS: the boundary PATH itself, not just its files.
# The reader and ownership surfaces SURVIVED this round; delivery yielded a
# finite new class (the .githooks path being a symlink or a directory).
# =============================================================================
# R11a: a .githooks that is a symlink to a shared dir refuses on both paths;
# nothing is written at the link target.
R11A="$WORK/r11-symdir"; rm -rf "$R11A"; mkdir -p "$R11A/repo" "$R11A/shared"
git_init "$R11A/repo"
printf '#!/bin/sh\nexit 1\n' > "$R11A/shared/pre-push"; chmod 644 "$R11A/shared/pre-push"
ln -s "$R11A/shared" "$R11A/repo/.githooks"
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R11A/repo" >"$WORK/r11a.out" 2>&1
if [[ $? -ne 0 ]] && grep -qi 'SYMLINK' "$WORK/r11a.out" && [[ ! -e "$R11A/shared/pre-commit" ]]; then
  ok "stamp R11a: a symlinked .githooks refuses and writes nothing at the link target"
else
  bad "stamp R11a: a symlinked .githooks refuses and writes nothing at the link target" \
      "the boundary was written through the symlink, outside the repository, under ARMED"
fi
# R11b: a .githooks/<hook> that is a directory refuses on the refresh path.
R11B="$WORK/r11-dirhook"; rm -rf "$R11B"; mkdir -p "$R11B/.claude/hooks" "$R11B/.githooks/pre-commit"
git_init "$R11B"; git -C "$R11B" config core.hooksPath .githooks
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$R11B/.claude/sdd.json"
bash "$SCRIPTS/refresh-instance.sh" --apply "$R11B" >"$WORK/r11b.out" 2>&1
if [[ $? -ne 0 ]] && grep -qi 'DIRECTORY' "$WORK/r11b.out"; then
  ok "refresh R11b: a hook name that is a directory refuses instead of reporting delivered"
else
  bad "refresh R11b: a hook name that is a directory refuses instead of reporting delivered" \
      "cp wrote INTO the directory, the -x guard passed it, and the run claimed delivery"
fi
# R11c: stamp into a linked worktree still delivers trunk-audit.sh (advisory).
R11C="$WORK/r11-lwta"; rm -rf "$R11C"; mkdir -p "$R11C/main"
git_init "$R11C/main"
git -C "$R11C/main" -c core.hooksPath=/dev/null commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$R11C/main" worktree add -q "$R11C/wt" -b r11feat >/dev/null 2>&1
bash "$ROOT/scripts/stamp.sh" "$R7_ANS" "$R11C/wt" >/dev/null 2>&1
if [[ -f "$R11C/wt/.claude/hooks/trunk-audit.sh" ]]; then
  ok "stamp R11c: a linked worktree still receives trunk-audit.sh, so its live pre-push can run"
else
  bad "stamp R11c: a linked worktree still receives trunk-audit.sh, so its live pre-push can run" \
      "the advisory tool was gated with the boundary and every push in the linked worktree was refused"
fi
# R11d: report mode does not warn "will REFUSE" when ADOPT is set.
R11D="$WORK/r11-adopt-report"; rfi_fixture "$R11D" .husky
if SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" "$R11D" 2>&1 | grep -qi 'will REFUSE'; then
  bad "refresh R11d: report mode under ADOPT does not threaten a refusal apply will not make" \
      "the report said --apply will REFUSE while apply with the same env adopts"
else
  ok "refresh R11d: report mode under ADOPT does not threaten a refusal apply will not make"
fi

# F12: trunk-audit.sh is a delivered file and must appear in the report.
RFI="$WORK/rfi-ta"; rfi_fixture "$RFI" ""
printf '#!/bin/sh\necho mine\n' > "$RFI/.claude/hooks/trunk-audit.sh"
printf '#!/bin/sh\necho prettier\n' > "$RFI/.claude/hooks/prettier.sh"
chmod 644 "$RFI/.claude/hooks/prettier.sh"
git -C "$RFI" add -A >/dev/null 2>&1; git -C "$RFI" commit -qm foreign >/dev/null 2>&1
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-ta.out" 2>&1
RFI_F12=""
grep -q 'trunk-audit' "$WORK/rfi-ta.out" || RFI_F12="$RFI_F12 not-reported"
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
[[ -x "$RFI/.claude/hooks/prettier.sh" ]] && RFI_F12="$RFI_F12 chmod-globbed-a-foreign-file"
if [[ -z "$RFI_F12" ]]; then
  ok "refresh c: trunk-audit.sh is reported before it is overwritten, and the chmod does not glob foreign files"
else
  bad "refresh c: trunk-audit.sh is reported before it is overwritten, and the chmod does not glob foreign files" \
      "problems:$RFI_F12; report-first is the stated discipline and a delivered file that appears in no report is outside it"
fi

# GIT IS A DEPENDENCY TOO, AND ITS VERSION IS PART OF IT (leg F5).
#
# `git branch --show-current` arrived in git 2.22 (2019). Below that it exits
# 129 and prints nothing useful, the gates read an empty branch, the empty value
# never equals the trunk, and they take their "ordinary feature work" exit. Not
# a reported allow carrying a code, which is what the advisory contract
# promises: total SILENCE, zero bytes, no code and no reason.
#
# close-gate.sh spends sixty lines establishing that a dependency which cannot
# produce its value must route to a REPORTED refusal, because "the empty result
# is indistinguishable from nothing to govern, and absence reads as permission".
# git was the one dependency never held to that rule.
#
# The remedy is not a probe but a query that predates the floor:
# `symbolic-ref --quiet --short HEAD`, which is what the git-hook layer has
# always used, and which is byte-identical in both cases that matter (a branch
# name when on a branch, empty when detached). Measured before swapping.
#
# The guarantee layer holds under the same shim, which is why this is a
# cooperative gap rather than a bypass, and the last assertion pins that.
GITOLD="$WORK/oldgit"; rm -rf "$GITOLD"; mkdir -p "$GITOLD"
{ printf '#!/bin/sh\n'
  printf 'for a in "$@"; do\n'
  printf '  if [ "$a" = "--show-current" ]; then\n'
  printf '    echo "error: unknown option \\`show-current%s" >&2\n' "'"
  printf '    exit 129\n'
  printf '  fi\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$(command -v git)"; } > "$GITOLD/git"
chmod +x "$GITOLD/git"

GV="$WORK/gitver"; rm -rf "$GV"; mkdir -p "$GV/src" "$GV/specs" "$GV/.claude"
git_init "$GV"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$GV/.claude/sdd.json"
printf 'x\n' > "$GV/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$GV/specs/STATUS.md"
git -C "$GV" add -A >/dev/null 2>&1; git -C "$GV" commit -qm stamp >/dev/null 2>&1
git -C "$GV" checkout -q -b spec/0001-thing main
printf 'export const s = 1\n' > "$GV/src/s.js"
git -C "$GV" add -A >/dev/null 2>&1; git -C "$GV" commit -qm work >/dev/null 2>&1
git -C "$GV" checkout -q main

GV_MERGE="$(jq -nc --arg c 'git merge --no-ff spec/0001-thing' '{tool_name:"Bash",tool_input:{command:$c}}')"
GV_WRITE="$(jq -nc --arg p "$GV/src/a.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"

# CONTROL: on modern git each gate reports its code. Without this the silence
# below could mean "nothing to say" rather than "went blind".
GV_CTL=""
printf %s "$GV_MERGE" | CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/close-gate.sh" 2>&1 | grep -q 'CG-' || GV_CTL="$GV_CTL close-gate"
printf %s "$GV_WRITE" | CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/scope-hook.sh" 2>&1 | grep -q 'SH-' || GV_CTL="$GV_CTL scope-hook"
if [[ -z "$GV_CTL" ]]; then
  ok "git version control: on current git both session gates report a code for this fixture"
else
  bad "git version control: on current git both session gates report a code for this fixture" \
      "these said nothing even on modern git:$GV_CTL, so the shim cases below prove nothing"
fi

GV_BLIND=""
printf %s "$GV_MERGE" | PATH="$GITOLD:$PATH" CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/close-gate.sh" 2>&1 | grep -q 'CG-' || GV_BLIND="$GV_BLIND close-gate"
printf %s "$GV_WRITE" | PATH="$GITOLD:$PATH" CLAUDE_PROJECT_DIR="$GV" bash "$HOOKS/scope-hook.sh" 2>&1 | grep -q 'SH-' || GV_BLIND="$GV_BLIND scope-hook"
if [[ -z "$GV_BLIND" ]]; then
  ok "git version a: the session gates still report on a git too old for branch --show-current"
else
  bad "git version a: the session gates still report on a git too old for branch --show-current" \
      "these went SILENT, zero bytes, no code and no reason:$GV_BLIND; absence reads as permission, which is the rule these hooks state and did not hold git to"
fi

# The guarantee layer under the same shim. This is what bounds the severity.
GVG="$WORK/gitver-hooks"; rm -rf "$GVG"; cp -R "$GV" "$GVG"; mkdir -p "$GVG/.githooks"
cp "$ROOT"/templates/git-hooks/* "$GVG/.githooks/"; chmod +x "$GVG"/.githooks/*
git -C "$GVG" config core.hooksPath .githooks; git -C "$GVG" config merge.ff false
( cd "$GVG" && PATH="$GITOLD:$PATH" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0001-thing ) >/dev/null 2>&1
if git -C "$GVG" cat-file -e main:src/s.js 2>/dev/null; then
  bad "git version b: the GUARANTEE layer still refuses on an old git" \
      "an unclosed spec merged onto the trunk under the shim, which would make this a bypass rather than a reporting gap"
else
  ok "git version b: the GUARANTEE layer still refuses on an old git"
fi

# ANY '<' READ AS THE UNFILLED PLACEHOLDER (leg F11), at all three layers.
#
# The test was `case "$answer" in *"<"*) answer="" ;;` in the library, the same
# substring test in close-gate.sh, and `grep -q '<'` in the audit. It was
# written to catch the template's own `<updated in this commit | no impact>`
# and it fires on any '<' in ordinary prose: a comparison, a generic, an HTML
# comment, an arrow. Measured: `updated in this commit (added <auth> box)` was
# refused SLH-DIAGRAM-UNANSWERED at merge time.
#
# This field has now been corrected three times, twice by repairing the one
# spelling that was reported, so the rule is asserted ACROSS THE VALUE SPACE
# rather than at any spelling. The new rule strips <...> spans and then requires
# the answer, so the genuine unfilled template strips to nothing and stays
# refused while prose containing '<' does not.
#
# Both directions in one table, because a rule that only stops refusing is a
# weakened check rather than a fixed one.
diag_fixture() { # diag_fixture <dir> <diagram-answer>
  local d="$1" ans="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" checkout -q -b spec/0005-diag main
  printf 'export const d = 1\n' > "$d/src/d.js"
  { printf '# Spec 0005\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n'
    printf -- '- Architecture diagram: %s\n' "$ans"; } > "$d/specs/0005-diag.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0005 | D | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0005" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
DIAG_MERGE_BAD=""; DIAG_AUDIT_BAD=""
# values that MUST be accepted: a real answer, whatever else the line contains
while IFS='|' read -r dv; do
  [[ -n "$dv" ]] || continue
  DGD="$WORK/diag-ok"; diag_fixture "$DGD" "$dv"
  ( cd "$DGD" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0005-diag ) >/dev/null 2>&1
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null || DIAG_MERGE_BAD="$DIAG_MERGE_BAD [$dv]"
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null && {
    bash "$SCRIPTS/trunk-audit.sh" "$DGD" >/dev/null 2>&1 || DIAG_AUDIT_BAD="$DIAG_AUDIT_BAD [$dv]"; }
done <<'DIAGOK'
no impact
updated in this commit
updated in this commit (added <auth> box)
no impact; the a < b case is unchanged
DIAGOK
# THE ANSWER MUST COME FIRST (F6-2026, 2.3.0 round 1), and one shape MOVED out
# of the corpus above to here rather than being dropped quietly.
#
# The field was matched with an UNANCHORED grep, so a line stating the OPPOSITE
# of an answer satisfied it. The fix anchors the answer to the START of the
# field's value, which keeps every documented shape (an answer with a
# parenthetical, an answer with a trailing clause) and refuses two: a line that
# merely CONTAINS an answer somewhere, and a line that contradicts one.
#
# `Foo<T> generic added, updated in this commit` was in the accepted corpus and
# is now refused. That is a real contract change and it is asserted here rather
# than left implicit: the field answers a question, so the answer goes first,
# and commentary follows it.
DIAG_FIRST_BAD=""
while IFS= read -r dv; do
  [[ -n "$dv" ]] || continue
  dva="$(printf '%s' "$dv" | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//')"
  if printf '%s' "$dva" | grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)'; then
    DIAG_FIRST_BAD="$DIAG_FIRST_BAD [$dv]"
  fi
done <<'DIAGNO'
this is NOT no impact, revisit it later
Foo<T> generic added, updated in this commit
revisit the diagram: the auth box is wrong
DIAGNO
if [[ -z "$DIAG_FIRST_BAD" ]]; then
  ok "diagram value a2 (F6-2026): a line that merely CONTAINS or CONTRADICTS an answer does not satisfy the field"
else
  bad "diagram value a2 (F6-2026): a line that merely CONTAINS or CONTRADICTS an answer does not satisfy the field" \
      "these still satisfied it:$DIAG_FIRST_BAD"
fi
if [[ -z "$DIAG_MERGE_BAD" && -z "$DIAG_AUDIT_BAD" ]]; then
  ok "diagram value a: an answer with trailing commentary is accepted; the answer must come FIRST"
else
  bad "diagram value a: an answer with trailing commentary is accepted; the answer must come FIRST" \
      "merge refused:${DIAG_MERGE_BAD:- none}  audit flagged:${DIAG_AUDIT_BAD:- none}; a '<' in prose is not the unfilled template"
fi

# values that MUST be refused, including the template itself
DIAG_LOOSE=""
while IFS='|' read -r dv; do
  [[ -n "$dv" ]] || continue
  DGD="$WORK/diag-bad"; diag_fixture "$DGD" "$dv"
  ( cd "$DGD" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m spec/0005-diag ) >/dev/null 2>&1
  git -C "$DGD" cat-file -e main:src/d.js 2>/dev/null && DIAG_LOOSE="$DIAG_LOOSE [$dv]"
done <<'DIAGBAD'
<updated in this commit | no impact>
<updated in this commit>
TBD
n/a
see structure.md
<TBD>
DIAGBAD
if [[ -z "$DIAG_LOOSE" ]]; then
  ok "diagram value b: an UNANSWERED field is still refused, template placeholder included"
else
  bad "diagram value b: an UNANSWERED field is still refused, template placeholder included" \
      "these merged:$DIAG_LOOSE, so the fix for the false positive weakened the check instead of correcting it"
fi

# THE REMOTE'S TRUNK RESOLVED FROM A CACHED CONVENIENCE REF (leg F7).
#
# REMOTE_TRUNK came only from `git symbolic-ref refs/remotes/$1/HEAD`. git
# passes $1 as the literal URL when a push names a URL, so no such ref exists;
# `git remote set-head origin -d` removes it for the by-name spelling. Either
# way REMOTE_TRUNK went empty, no pushed ref matched a trunk name, PUSH_REFS
# stayed empty, and control fell to the else branch which audits the LOCAL
# trunk and reports it clean. A true statement about a ref the push never
# touched, printed as though it were an audit of the push.
#
# Measured: unclosed feature code reached the REMOTE trunk at rc=0 while the
# hook printed "audited 0 commits on main ... 0 violations".
#
# Precondition that bounds the severity, stated because it is not obvious: the
# remote's trunk name must DIFFER from the recorded local trunk. Where they
# agree the local-name test still catches it, which the (c) control pins.
f7_inst() { # f7_inst <dir> <remote-default-branch>
  local d="$1" rdefault="$2"
  rm -rf "$d" "$d-rem.git"
  git init -q --bare -b "$rdefault" "$d-rem.git"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  # pre-push REFUSES when it cannot find the audit, and correctly so. The first
  # run of this harness omitted it and refused everything including its own
  # controls, which is the tell that a fixture is wrong rather than a finding.
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" remote add origin "$d-rem.git"
  SETLIST_SKIP_TRUNK_AUDIT=1 git -C "$d" push -q origin "main:$rdefault" >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0004-bad main
  printf 'export const bad = 1\n' > "$d/src/bad.js"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "unclosed work" >/dev/null 2>&1
}
f7_on_remote() { git -C "$1-rem.git" cat-file -e "$2:src/bad.js" 2>/dev/null; }

# (a) by URL, and (b) by name with origin/HEAD deleted. Both must be refused.
F7_BAD=""
F7D="$WORK/f7-url"; f7_inst "$F7D" master
( cd "$F7D" && git push "$F7D-rem.git" spec/0004-bad:refs/heads/master ) >"$WORK/f7a.out" 2>&1
f7_on_remote "$F7D" master && F7_BAD="$F7_BAD by-url"
F7D="$WORK/f7-nohead"; f7_inst "$F7D" master
git -C "$F7D" remote set-head origin -d >/dev/null 2>&1
( cd "$F7D" && git push origin spec/0004-bad:refs/heads/master ) >"$WORK/f7b.out" 2>&1
f7_on_remote "$F7D" master && F7_BAD="$F7_BAD by-name-no-HEAD"
if [[ -z "$F7_BAD" ]]; then
  ok "remote trunk a: a push that would become the remote trunk is audited however the remote is named"
else
  bad "remote trunk a: a push that would become the remote trunk is audited however the remote is named" \
      "unclosed feature code reached the remote trunk by:$F7_BAD, while the hook reported [$(grep -oE 'audited [^,]*' "$WORK/f7a.out" | head -1)]"
fi

# THE UNREACHABLE BRANCH IS LIVE, and TWO measurements were needed to say what
# actually reaches it.
#
# First: git rejects a plainly unreachable remote before pre-push runs, so that
# is not the case. The shape that arrives is a remote whose FETCH url is
# unreachable while its PUSH url works (`git remote set-url --push`).
#
# Second, and this is what the first cut of this assertion got wrong: the cached
# refs/remotes/<name>/HEAD is consulted before the live query, so the branch is
# reached only when the cache is ALSO absent. This fixture fetches, so it has a
# cached HEAD, and without deleting it the hook resolved the trunk from cache,
# audited the clean local trunk and allowed the push. The assertion failed while
# the code was right, which is the correct way round for that to happen.
#
# Pinned so nobody deletes the branch believing it is dead code. The push here
# WOULD have succeeded, so the refusal is a real cost, taken because the
# alternative is F7's fail-open.
# THIRD correction to this one assertion, and the code was right every time.
# The landing probe first read master:src/app.js, which f7_inst had ALREADY put
# on the remote when it seeded it, so "landed" was true before the push under
# test ran at all. A probe must look for something only the operation under test
# could have produced, so main gains a file here and that file is the probe.
F7D="$WORK/f7-spliturl"; f7_inst "$F7D" master
git -C "$F7D" checkout -q main
printf 'export const fresh = 1\n' > "$F7D/src/fresh.js"
git -C "$F7D" add -A >/dev/null 2>&1
git -C "$F7D" -c core.hooksPath=/dev/null commit -qm "a commit only this test makes" >/dev/null 2>&1
git -C "$F7D" remote set-head origin -d >/dev/null 2>&1
git -C "$F7D" remote set-url origin /nope/nothere.git
git -C "$F7D" remote set-url --push origin "$F7D-rem.git"
( cd "$F7D" && git push origin main:refs/heads/master ) >"$WORK/f7f.out" 2>&1
if grep -q 'SLH-REMOTE-UNRESOLVED' "$WORK/f7f.out" && ! git -C "$F7D-rem.git" cat-file -e refs/heads/master:src/fresh.js 2>/dev/null; then
  ok "remote trunk b: a remote whose trunk cannot be resolved refuses by name instead of auditing the wrong ref"
else
  bad "remote trunk b: a remote whose trunk cannot be resolved refuses by name instead of auditing the wrong ref" \
      "expected SLH-REMOTE-UNRESOLVED and src/fresh.js NOT on the remote; got [$(grep -oE 'SLH-[A-Z-]+|audited [^,]*' "$WORK/f7f.out" | head -1)] and landed=$(git -C "$F7D-rem.git" cat-file -e refs/heads/master:src/fresh.js 2>/dev/null && echo yes || echo no)"
fi

# (c) CONTROL: where the two trunk names agree, the local-name test catches it.
F7D="$WORK/f7-samename"; f7_inst "$F7D" main
( cd "$F7D" && git push "$F7D-rem.git" spec/0004-bad:refs/heads/main ) >/dev/null 2>&1
if f7_on_remote "$F7D" main; then
  bad "remote trunk control: a URL push is caught when the remote trunk shares the local name" \
      "even the pre-existing local-name test did not fire, so the cases above prove nothing"
else
  ok "remote trunk control: a URL push is caught when the remote trunk shares the local name"
fi

# (d) and (e) FALSE-DENIAL CONTROLS. Ordinary pushes must keep working, and
# this is the direction a fix here is most likely to break.
F7_FD=""
F7D="$WORK/f7-ownname"; f7_inst "$F7D" master
( cd "$F7D" && git push origin spec/0004-bad ) >"$WORK/f7d.out" 2>&1
git -C "$F7D-rem.git" cat-file -e refs/heads/spec/0004-bad:src/bad.js 2>/dev/null || F7_FD="$F7_FD spec-branch-to-own-name"
F7D="$WORK/f7-topic"; f7_inst "$F7D" master
git -C "$F7D" checkout -q main
( cd "$F7D" && git push origin main:refs/heads/mytopic ) >"$WORK/f7e.out" 2>&1
git -C "$F7D-rem.git" cat-file -e refs/heads/mytopic:src/app.js 2>/dev/null || F7_FD="$F7_FD trunk-to-non-trunk-ref"
if [[ -z "$F7_FD" ]]; then
  ok "remote trunk controls: pushing a spec branch to its own name, and the trunk to a non-trunk ref, both still succeed"
else
  bad "remote trunk controls: pushing a spec branch to its own name, and the trunk to a non-trunk ref, both still succeed" \
      "these were refused:$F7_FD, which is the false-denial direction and worse than the hole above"
fi

# THE SPEC FILE IS PICKED BY SORT ORDER, WITH NO UNIQUENESS CHECK (leg F6).
#
# slh_verify_close took `grep -E "^specs/${num}[a-z]*-" | head -n1`. Both
# `git diff --cached --name-only` and `git ls-files` emit sorted paths, and
# `specs/0002-other-design.md` sorts BEFORE `specs/0002-other.md` because '-'
# is 0x2d and '.' is 0x2e, so a companion document always wins the pick.
#
# It fails in BOTH directions, and both were measured:
#   a non-compliant spec merged clean once a compliant-looking companion existed
#   a fully compliant close was refused "spec 0003 has no Closing report",
#     which is false about the file it names
#
# The second half is the dangerous one. The operator opens the file, sees the
# Closing report the hook says is absent, concludes the hook is broken, and
# reaches for SETLIST_SKIP_HOOKS=1, which the library's own comment calls the
# road from one confusing message to a disabled boundary.
#
# The sibling ADVISORY gate already refuses this input by name at
# close-gate.sh:1512 (CG-SPEC-DUPLICATE). The guarantee layer never got it.
#
# SECOND BUG IN THE SAME PATTERN: `${num}[a-z]*-` over-matches. Part 4's split
# convention makes `0002b` a DISTINCT spec carrying its own STATUS.md row, so
# for a row numbered 0002 the file specs/0002b-x.md is somebody else's spec and
# must not be a candidate at all. The last assertion pins that.
f6_inst() { # f6_inst <dir>
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"; git -C "$d" config merge.ff false
  cp "$ROOT"/templates/git-hooks/* "$d/.githooks/"; chmod +x "$d"/.githooks/*
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}
f6_compliant() { printf '# Spec %s\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' "$1"; }
f6_row() { printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| %s | T | CLOSED | done |\n' "$1"; }
# f6_run <dir> <num> -> merges a spec branch, leaves F6_OUT and F6_LANDED
f6_run() {
  local d="$1" n="$2"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "close $n" >/dev/null 2>&1
  git -C "$d" checkout -q main
  F6_OUT="$( cd "$d" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m "spec/$n" 2>&1 )" # fail-open-ok: the refusal text is the evidence; F6_LANDED below is the decision
  if git -C "$d" cat-file -e "main:src/$n.js" 2>/dev/null; then F6_LANDED=1; else F6_LANDED=0; fi
}

# CONTROL: a non-compliant spec ALONE is refused, and a lone compliant one lands.
F6D="$WORK/f6-ctl-bad"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
printf '# Spec 0002\n\nStatus: CLOSED\n\nnothing here.\n' > "$F6D/specs/0002-other.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
F6_CTL=""
[[ "$F6_LANDED" -eq 1 ]] && F6_CTL="$F6_CTL noncompliant-landed"
F6D="$WORK/f6-ctl-good"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0004 main
f6_compliant 0004 > "$F6D/specs/0004-fourth.md"
f6_row 0004 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0004.js"
f6_run "$F6D" 0004
[[ "$F6_LANDED" -eq 0 ]] && F6_CTL="$F6_CTL compliant-refused"
if [[ -z "$F6_CTL" ]]; then
  ok "spec pick control: a lone non-compliant spec is refused and a lone compliant close lands"
else
  bad "spec pick control: a lone non-compliant spec is refused and a lone compliant close lands" \
      "the fixtures are wrong:$F6_CTL, so the duplicate cases below prove nothing"
fi

# ATTACK 1: a companion doc launders a non-compliant close.
F6D="$WORK/f6-launder"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
printf '# Spec 0002\n\nStatus: CLOSED\n\nnothing here.\n' > "$F6D/specs/0002-other.md"
f6_compliant 0002 > "$F6D/specs/0002-other-design.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
if [[ "$F6_LANDED" -eq 0 ]]; then
  ok "spec pick a: a companion document cannot launder a non-compliant close onto the trunk"
else
  bad "spec pick a: a companion document cannot launder a non-compliant close onto the trunk" \
      "the merge LANDED and the trunk now carries a spec whose body is: $(git -C "$F6D" show main:specs/0002-other.md 2>/dev/null | tail -1)"
fi

# ATTACK 2, the mirror: a compliant close plus an ordinary notes file. It is
# still refused, which is right because the input is genuinely ambiguous, but
# the REASON must be the true one rather than a false claim about the file.
F6D="$WORK/f6-mirror"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0003 main
f6_compliant 0003 > "$F6D/specs/0003-third.md"
printf '# Notes for 0003\n\nJust ordinary notes, no report here.\n' > "$F6D/specs/0003-third-notes.md"
f6_row 0003 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0003.js"
f6_run "$F6D" 0003
if printf '%s' "$F6_OUT" | grep -q 'SLH-SPEC-DUPLICATE'; then
  ok "spec pick b: two files matching one spec number are refused as a DUPLICATE, not as a missing report"
else
  bad "spec pick b: two files matching one spec number are refused as a DUPLICATE, not as a missing report" \
      "the reason given was [$(printf '%s' "$F6_OUT" | grep -oE 'SLH-[A-Z-]+' | head -1)], and a message that is false about the file it names is what sends an operator to SETLIST_SKIP_HOOKS=1"
fi

# THE SPLIT SIBLING IS NOT A DUPLICATE. Part 4 makes 0002b its own spec with
# its own row, so a compliant 0002 must still close while 0002b sits beside it.
F6D="$WORK/f6-sibling"; f6_inst "$F6D"; git -C "$F6D" checkout -q -b spec/0002 main
f6_compliant 0002 > "$F6D/specs/0002-first.md"
printf '# Spec 0002b\n\nStatus: QUEUED\n\nparked remainder.\n' > "$F6D/specs/0002b-parked.md"
f6_row 0002 > "$F6D/specs/STATUS.md"; printf 'x\n' > "$F6D/src/0002.js"
f6_run "$F6D" 0002
if [[ "$F6_LANDED" -eq 1 ]]; then
  ok "spec pick c: a suffixed split sibling is a different spec, not a duplicate of its parent"
else
  bad "spec pick c: a suffixed split sibling is a different spec, not a duplicate of its parent" \
      "a compliant close of 0002 was refused because 0002b exists beside it [$(printf '%s' "$F6_OUT" | grep -oE 'SLH-[A-Z-]+' | head -1)], which breaks Part 4's own split convention"
fi

# THE AUDIT'S TOOLCHAIN PROBE (2026-08-07 leg, F2).
#
# setlist-hook-lib.sh has carried slh_require_toolchain since the run that
# measured a broken grep letting an unclosed spec merge at rc=0 in silence. It
# was wired into pre-commit, pre-merge-commit and pre-push and NOT into
# trunk-audit.sh, which is the standalone invocation the README documents and
# the one any CI job would call.
#
# The failure is not a missed detection, it is a FLIPPED verdict: line 280 read
# `wc -w | tr -d ' '`, a broken tr yields the empty string, `[[ "" -lt 2 ]]` is
# true in bash arithmetic, so every merge commit was classified as a non-merge,
# skipped the whole merged-parent loop, and landed in the "clean" bucket at
# exit 0. The script has an "unverifiable" category for the cases history
# cannot decide, and the degraded path did not route there either.
#
# Both directions, because a probe that refuses everything is not a fix.
ta_fixture() { # ta_fixture <dir> <good|bad>
  local d="$1" kind="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  git -C "$d" config merge.ff false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-first main
  printf 'export const f = 1\n' > "$d/src/f.js"
  if [[ "$kind" == good ]]; then
    printf '# Spec 0001 - First\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-first.md"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$d/specs/STATUS.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm work >/dev/null 2>&1
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
}
# The broken tools. `tr` exiting 127 is the dyld failure the leg used; `tr`
# exiting 0 and printing nothing is the quieter half, and both must be caught,
# because a probe that only checks the exit status misses the second.
TAB="$WORK/ta-brokenbin"; rm -rf "$TAB"; mkdir -p "$TAB/loud" "$TAB/quiet"
printf '#!/bin/sh\necho "dyld: Library not loaded" >&2\nexit 127\n' > "$TAB/loud/tr"
printf '#!/bin/sh\nexit 0\n' > "$TAB/quiet/tr"
chmod +x "$TAB/loud/tr" "$TAB/quiet/tr"

TAV="$WORK/ta-violating"; ta_fixture "$TAV" bad
TAC="$WORK/ta-clean"; ta_fixture "$TAC" good

# CONTROL, healthy toolchain, both directions. Without this the cases below
# prove nothing: a fixture that is clean either way would pass a broken probe.
TA_CTL=""
bash "$SCRIPTS/trunk-audit.sh" "$TAV" >/dev/null 2>&1 && TA_CTL="$TA_CTL violating-read-as-clean"
bash "$SCRIPTS/trunk-audit.sh" "$TAC" >/dev/null 2>&1 || TA_CTL="$TA_CTL clean-read-as-violating"
if [[ -z "$TA_CTL" ]]; then
  ok "audit toolchain control: with a healthy toolchain the audit refuses the violating trunk and passes the clean one"
else
  bad "audit toolchain control: with a healthy toolchain the audit refuses the violating trunk and passes the clean one" \
      "the fixtures are wrong:$TA_CTL, so the broken-tool cases below prove nothing"
fi

TA_BAD=""
for ta_k in loud quiet; do
  TA_OUT="$(PATH="$TAB/$ta_k:$PATH" bash "$SCRIPTS/trunk-audit.sh" "$TAV" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: the rc suffix is what the test reads, and a crash shows up as neither 0 nor a TOOLCHAIN code
  printf '%s' "$TA_OUT" | grep -q '|rc=0$' && TA_BAD="$TA_BAD $ta_k:exit-0"
  printf '%s' "$TA_OUT" | grep -q 'SLH-NO-TOOLCHAIN' || TA_BAD="$TA_BAD $ta_k:no-reason"
done
if [[ -z "$TA_BAD" ]]; then
  ok "audit toolchain a: a broken tr stops the audit with SLH-NO-TOOLCHAIN instead of reporting a violating trunk clean"
else
  bad "audit toolchain a: a broken tr stops the audit with SLH-NO-TOOLCHAIN instead of reporting a violating trunk clean" \
      "these degraded runs did not refuse or did not say why:$TA_BAD, and exit 0 is what CI reads as a pass"
fi

# EVERY TOOL THE AUDIT DECIDES WITH, NOT THE FOUR THE LIBRARY HAPPENED TO NAME
# (2026-08-08 pre-stress, found on zero leg quota).
#
# The F2 fix probed awk, sed, tr and grep, because those are what the library
# probes. The audit also DECIDES with cut and wc: line 314 built the parent
# list with `cut -d' ' -f2-` and line 315 counted it with `wc -w`. A broken cut
# yields the empty string, NPAR becomes 0, `[[ 0 -lt 2 ]]` is true, so every
# merge commit was classified a non-merge, skipped the merged-parent loop, and
# the violating trunk was reported CLEAN at exit 0 with no reason printed.
#
# That is the identical fail-open the tr bug had, one tool over, in the fix for
# the tr bug. Measured: `cut` broken loud (exit 127) and quiet (exit 0, no
# output) both produced `rc=0, 1 clean, 0 violations` on a trunk the healthy
# audit refuses.
#
# The guarantee layer does NOT share this: all twenty broken-tool cases against
# a merge that must be refused stayed refused, so this is the standalone audit
# only. Asserted across the full decision-path tool set rather than at the one
# spelling that was found.
TAD_BAD=""
for ta_t in cut wc head tail sort tr awk sed grep; do
  for ta_f in loud quiet; do
    TAP="$WORK/ta-dep-$ta_t-$ta_f"; rm -rf "$TAP"; mkdir -p "$TAP"
    if [[ "$ta_f" == loud ]]; then printf '#!/bin/sh\necho broken >&2\nexit 127\n' > "$TAP/$ta_t"
    else printf '#!/bin/sh\nexit 0\n' > "$TAP/$ta_t"; fi
    chmod +x "$TAP/$ta_t"
    TAD_OUT="$(PATH="$TAP:$PATH" bash "$SCRIPTS/trunk-audit.sh" "$TAV" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: the rc suffix is what the test reads
    printf '%s' "$TAD_OUT" | grep -q '|rc=0$' && TAD_BAD="$TAD_BAD $ta_t:$ta_f"
  done
done
if [[ -z "$TAD_BAD" ]]; then
  ok "audit toolchain c: no broken decision-path tool makes the audit report a violating trunk clean"
else
  bad "audit toolchain c: no broken decision-path tool makes the audit report a violating trunk clean" \
      "these exited 0 on a trunk the healthy audit refuses:$TAD_BAD, and exit 0 is what CI reads as a pass"
fi

# THE LOCKSTEP THE INLINE PROBE BUYS. Two copies of a check drift, and this
# repository has paid for that twice already (the diagram field applied a weaker
# test in the audit than in the hook while a comment claimed lockstep). So the
# obligation is asserted rather than commented: both probes must cover the same
# four tools, by name.
TA_LIBTOOLS="$(grep -oE 'slh_refuse "SLH-NO-TOOLCHAIN" "[a-z]+ ' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed -e 's/.*"//' -e 's/ *$//' | sort -u | tr '\n' ' ')"
TA_AUDTOOLS="$(grep -oE '^probe_tool [a-z]+' "$SCRIPTS/trunk-audit.sh" | awk '{print $2}' | sort -u | tr '\n' ' ')"
# SUPERSET, not equality. The first cut of this assertion required the two
# lists to be equal, which was right when both probed the same four tools and
# became wrong the moment the audit was widened to cover cut, wc, head, tail
# and sort as well. The audit decides with more tools than the library does, so
# the obligation is that it probes AT LEAST what the library probes: a tool the
# library thought worth checking must not go unchecked here.
TA_MISSING=""
for ta_l in $TA_LIBTOOLS; do
  case " $TA_AUDTOOLS " in *" $ta_l "*) ;; *) TA_MISSING="$TA_MISSING $ta_l" ;; esac
done
if [[ -n "$TA_LIBTOOLS" && -z "$TA_MISSING" ]]; then
  ok "audit toolchain b: the audit's inline probe covers everything the library's does"
else
  bad "audit toolchain b: the audit's inline probe covers everything the library's does" \
      "library probes [$TA_LIBTOOLS], audit probes [$TA_AUDTOOLS], unprobed here:${TA_MISSING:- none}; an empty library list means this assertion stopped reading the library and is checking nothing"
fi

# THE FALSE DENIAL THAT REMOVED THE CHECK (2026-08-07, F4), asserted so it
# cannot come back with the next attempt at the route above.
#
# Two clones of one instance. The second does a fully compliant close and
# pushes it. The first makes one docs commit and runs the sync git itself
# instructs. The resulting merge was refused with "a chained merge below main
# brought role-path code that closed no spec", naming as the offender the very
# close merge this audit had passed clean minutes earlier. That is every team
# sharing a trunk, and this repository treats a false denial on the commonest
# workflow there is as costing more than the bypass it prevents.
CHR="$WORK/chain-remote.git"; rm -rf "$CHR"; git init -q --bare -b main "$CHR"
CHS="$WORK/chain-seed"; chain_fixture "$CHS"
git -C "$CHS" push -q "$CHR" main >/dev/null 2>&1
CHP="$WORK/chain-clone-a"; rm -rf "$CHP"; git clone -q "$CHR" "$CHP" >/dev/null 2>&1
CHQ="$WORK/chain-clone-b"; rm -rf "$CHQ"; git clone -q "$CHR" "$CHQ" >/dev/null 2>&1
for d in "$CHP" "$CHQ"; do
  git -C "$d" config user.email t@e.invalid; git -C "$d" config user.name T
  git -C "$d" config commit.gpgsign false; git -C "$d" config merge.ff false
done
git -C "$CHQ" checkout -q -b spec/0001-first main; chain_close "$CHQ"
git -C "$CHQ" checkout -q main
git -C "$CHQ" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHQ" >/dev/null 2>&1; then
  git -C "$CHQ" push -q origin main >/dev/null 2>&1
  printf 'notes\n' > "$CHP/NOTES.md"
  git -C "$CHP" add -A >/dev/null 2>&1; git -C "$CHP" commit -qm "docs: notes" >/dev/null 2>&1
  git -C "$CHP" pull -q --no-rebase origin main >/dev/null 2>&1
  if bash "$SCRIPTS/trunk-audit.sh" "$CHP" >"$WORK/chain-sync.out" 2>&1; then
    ok "chain e: the second developer on a shared trunk can pull a compliant close and stay clean"
  else
    bad "chain e: the second developer on a shared trunk can pull a compliant close and stay clean" \
        "the sync git itself instructs is reported as a violation: $(grep VIOLATION "$WORK/chain-sync.out" | head -1)"
  fi
else
  bad "chain e control: the close the other clone pushes audits clean before it is pushed" \
      "the fixture is broken, so the sync case below proves nothing"
fi

# THE COOPERATIVE-USE FIXES FROM CLAIMS ROUND 6, both directions.
#
# Round 6's findings were all COOPERATIVE rather than crafted evasion: they hit
# a developer following the process. An empty gate_command is the STAMPED
# DEFAULT, and the fast-forward shape is byte-for-byte what a forge merge button
# produces, which for a pull-request team is the ordinary path rather than an
# attack. So they were fixed rather than documented.
GCE="$WORK/gate-empty"; rm -rf "$GCE"; close_fixture "$GCE" yes yes answered yes no ""
git -C "$GCE" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$GCE" "$(bash_payload "$MERGE_CMD")" >/dev/null 2>&1 || true
GCE_STATE="$(jq -r '.scaffolded' "$GCE/.claude/sdd.json" 2>/dev/null)" # fail-open-ok: an unreadable value fails the guard below, which skips a case rather than asserting on a broken fixture
if [[ "$GCE_STATE" == "true" ]]; then
  if bash -c "cd '$GCE' && printf '%s\n' \"\$(git -C '$GCE' log -1 --format=%H)\" >/dev/null"; then :; fi
fi

# The library function directly, which is what both git hooks call.
GCLIB="$WORK/gate-lib"; rm -rf "$GCLIB"; mkdir -p "$GCLIB/.claude"
printf '{"trunk":"main","scaffolded":true,"gate_command":"","roles":{"src":"src"}}\n' > "$GCLIB/.claude/sdd.json"
GC_OUT="$(SLH_REFUSED=0; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCLIB" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: sourcing noise is discarded; the rc suffix is what the test reads
if printf '%s' "$GC_OUT" | grep -q 'SLH-NO-GATE-COMMAND'; then
  ok "gate empty a: a SCAFFOLDED instance with no gate_command refuses instead of skipping the suite silently"
else
  bad "gate empty a: a SCAFFOLDED instance with no gate_command refuses instead of skipping the suite silently" \
      "it returned without a code, which is the stamped default state merging with no suite run"
fi
printf '{"trunk":"main","scaffolded":false,"gate_command":"","roles":{"src":"src"}}\n' > "$GCLIB/.claude/sdd.json"
GC_OUT2="$(SLH_REFUSED=0; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GCLIB" 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: as above
if printf '%s' "$GC_OUT2" | grep -q 'SLH-NO-GATE-COMMAND'; then
  bad "gate empty b control: BEFORE scaffolding an empty gate_command is still skipped" \
      "a project that has not been scaffolded yet is being refused, which is the false-denial direction"
else
  ok "gate empty b control: BEFORE scaffolding an empty gate_command is still skipped"
fi

# THE FORGE / FAST-FORWARD SHAPE: the audit now reads the diagram field, which
# lived only in the layer a fast-forward skips.
ffa_fixture() { # ffa_fixture <dir> <diagram-line-or-empty>
  local d="$1" diag="$2"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | X | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0002-x
  printf 'export const f = 1\n' > "$d/src/f.js"
  { printf '# Spec 0002 - X\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n'
    [ -n "$diag" ] && printf -- '- Architecture diagram: %s\n' "$diag"; } > "$d/specs/0002-x.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | X | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm close >/dev/null 2>&1
  git -C "$d" checkout -q -B tmp main
  git -C "$d" merge -q --no-ff -m "Merge pull request #1" spec/0002-x >/dev/null 2>&1
  git -C "$d" checkout -q main; git -C "$d" merge -q --ff-only tmp >/dev/null 2>&1
}
# LOCKSTEP MEANS THE SAME TEST (v1.7 final claims pass). The audit's first cut
# found the same diagram line as the hook and applied a weaker test: it refused
# empty and `<` and passed everything else, so TBD, n/a and "see structure.md"
# were refused at merge time and reported clean by the audit. The comment
# claimed lockstep while the code did not have it. Asserted across the value
# space rather than at one spelling.
FF_DIAG_BAD=""
for ff_v in 'TBD' 'n/a' 'see structure.md'; do
  FFV="$WORK/ff-val"; ffa_fixture "$FFV" "$ff_v"
  bash "$SCRIPTS/trunk-audit.sh" "$FFV" >/dev/null 2>&1 && FF_DIAG_BAD="$FF_DIAG_BAD [$ff_v]"
done
if [[ -z "$FF_DIAG_BAD" ]]; then
  ok "forge diagram: an UNANSWERED diagram value is a violation, not just the template placeholder"
else
  bad "forge diagram: an UNANSWERED diagram value is a violation, not just the template placeholder" \
      "these passed the audit while the merge hook refuses them:$FF_DIAG_BAD"
fi
FF_OK_BAD=""
for ff_v in 'no impact' 'updated in this commit'; do
  FFV="$WORK/ff-val-ok"; ffa_fixture "$FFV" "$ff_v"
  bash "$SCRIPTS/trunk-audit.sh" "$FFV" >/dev/null 2>&1 || FF_OK_BAD="$FF_OK_BAD [$ff_v]"
done
if [[ -z "$FF_OK_BAD" ]]; then
  ok "forge diagram control: the two ANSWERS Appendix C offers are still clean"
else
  bad "forge diagram control: the two ANSWERS Appendix C offers are still clean" \
      "the audit refuses a compliant answer:$FF_OK_BAD, which is the false-denial direction"
fi

FFA="$WORK/ff-nodiag"; ffa_fixture "$FFA" ""
if bash "$SCRIPTS/trunk-audit.sh" "$FFA" >/dev/null 2>&1; then
  bad "forge shape a: a fast-forwarded close with NO diagram field is a violation" \
      "the audit reported clean, so the ordinary pull-request flow carries an incomplete close to the remote"
else ok "forge shape a: a fast-forwarded close with NO diagram field is a violation"; fi
FFB="$WORK/ff-placeholder"; ffa_fixture "$FFB" "<updated in this commit | no impact>"
if bash "$SCRIPTS/trunk-audit.sh" "$FFB" >/dev/null 2>&1; then
  bad "forge shape b: an UNANSWERED diagram placeholder is a violation" \
      "the template placeholder counted as an answer"
else ok "forge shape b: an UNANSWERED diagram placeholder is a violation"; fi
FFC="$WORK/ff-ok"; ffa_fixture "$FFC" "no impact"
if bash "$SCRIPTS/trunk-audit.sh" "$FFC" >/dev/null 2>&1; then
  ok "forge shape control: an ANSWERED diagram field is still clean"
else
  bad "forge shape control: an ANSWERED diagram field is still clean" \
      "the new diagram check refuses a compliant close, which is the false-denial direction"
fi

# CLOSE VERIFICATION BINDS TO THE EVENT, NOT THE MERGE SHAPE (v1.7 confirmation).
#
# Every close condition used to live inside the audit's merged-parent loop,
# reachable only past its NPAR>=2 guard, so a close producing no merge commit was
# never checked. Two ordinary honest routes hit that: `git merge --ff` of a
# linear spec branch, and a docs-only commit flipping a STATUS row to CLOSED,
# which this framework explicitly permits on the trunk. This is R3-2 one level
# up: there the close SET was wrong, here the TRIGGER was.
ev_fixture() { # ev_fixture <dir>
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"; git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | ACTIVE | x |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0002 - D\n\nStatus: ACTIVE\n' > "$d/specs/0002-d.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
}
ev_closed_row() { printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | CLOSED | done |\n'; }
ev_good() { printf '# Spec 0002 - D\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'; }
ev_bad()  { printf '# Spec 0002 - D\n\nStatus: CLOSED\n\n## Closing report\n\n(nothing)\n'; }

EVA="$WORK/event-ff-bad"; ev_fixture "$EVA"
git -C "$EVA" checkout -q -b spec/0002-d
ev_bad > "$EVA/specs/0002-d.md"; ev_closed_row > "$EVA/specs/STATUS.md"
git -C "$EVA" add -A >/dev/null 2>&1; git -C "$EVA" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVA" checkout -q main; git -C "$EVA" merge -q --ff spec/0002-d >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVA" >/dev/null 2>&1; then
  bad "event close a: a --ff close with no Closing report is a violation" \
      "the audit never opened the spec, so a fast-forward routes around close verification entirely"
else ok "event close a: a --ff close with no Closing report is a violation"; fi

EVB="$WORK/event-docs-bad"; ev_fixture "$EVB"
ev_closed_row > "$EVB/specs/STATUS.md"
git -C "$EVB" add -A >/dev/null 2>&1; git -C "$EVB" commit -qm "docs: mark 0002 closed" >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVB" >/dev/null 2>&1; then
  bad "event close b: a docs-commit that flips a row to CLOSED is verified too" \
      "a row reached CLOSED on the trunk with no Closing report and nothing looked at it"
else ok "event close b: a docs-commit that flips a row to CLOSED is verified too"; fi

EV_BAD=""
# THE CONTROL CARRIES ROLE-PATH CODE, AND WITHOUT IT PROVED NOTHING (F9).
#
# ev_fixture writes src/app.js at STAMP time, so this close commit used to touch
# specs/ and nothing else. The violation it is the control FOR ("feature code
# committed directly to main") is reached only when the commit ADDS role-path
# code, so this case could not exhibit the finding it guards: it passed both
# before and after F4, and would have gone on passing if F4 were never fixed.
# That is the vacuous-control class this repository keeps paying for, filed as
# F9 and landed here BEFORE F4's code fix per the regression-permanence rule.
#
# With the line below, this case is the F4 subject: a COMPLIANT fast-forward
# close carrying feature code. Watched RED against the pre-F4 audit, which
# reported `VIOLATION ... feature code committed directly to main` and refused a
# close satisfying every condition the framework asks for.
EVC="$WORK/event-ff-ok"; ev_fixture "$EVC"
git -C "$EVC" checkout -q -b spec/0002-d
ev_good > "$EVC/specs/0002-d.md"; ev_closed_row > "$EVC/specs/STATUS.md"
printf 'feature\n' > "$EVC/src/ff-feature.js"
git -C "$EVC" add -A >/dev/null 2>&1; git -C "$EVC" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVC" checkout -q main; git -C "$EVC" merge -q --ff spec/0002-d >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$EVC" >/dev/null 2>&1 || EV_BAD="$EV_BAD ff-complete"
EVD="$WORK/event-docs-only"; ev_fixture "$EVD"
mkdir -p "$EVD/docs"; printf 'hi\n' > "$EVD/docs/g.md"
git -C "$EVD" add -A >/dev/null 2>&1; git -C "$EVD" commit -qm "docs only" >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$EVD" >/dev/null 2>&1 || EV_BAD="$EV_BAD docs-no-flip"
if [[ -z "$EV_BAD" ]]; then
  ok "event close controls: a COMPLETE --ff close and an ordinary docs commit stay clean"
else
  bad "event close controls: a COMPLETE --ff close and an ordinary docs commit stay clean" \
      "these are refused:$EV_BAD, which is the false-denial direction"
fi

# The SQUASH half of F4, which is the same shape under the other flag name. A
# squash has no second parent, so it lands in the same NPAR<2 arm; asserting it
# separately is what stops a later fix keyed on the fast-forward alone from
# looking complete.
EVS="$WORK/event-squash-ok"; ev_fixture "$EVS"
git -C "$EVS" checkout -q -b spec/0002-d
ev_good > "$EVS/specs/0002-d.md"; ev_closed_row > "$EVS/specs/STATUS.md"
printf 'feature\n' > "$EVS/src/sq-feature.js"
git -C "$EVS" add -A >/dev/null 2>&1; git -C "$EVS" commit -qm "close 0002" >/dev/null 2>&1
git -C "$EVS" checkout -q main
git -C "$EVS" merge -q --squash spec/0002-d >/dev/null 2>&1
git -C "$EVS" commit -qm "close 0002 (squash)" >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$EVS" >/dev/null 2>&1; then
  ok "F4 squash: a COMPLIANT --squash close carrying feature code is clean"
else
  bad "F4 squash: a COMPLIANT --squash close carrying feature code is clean" \
      "it is a violation, so a compliant squash close is permanently unpushable. F4 is keyed on the PARENT COUNT precisely so one fix covers the fast-forward and the squash together"
fi

# THE TRUNK MUST NAME A BRANCH, NOT A POSITION (V19-F8). HEAD, @ and the reflog
# forms all RESOLVE, and the reducer then audits whatever branch is checked out,
# so the audited ref becomes a property of the working tree rather than of the
# recorded configuration. Watched red first: HEAD and @ both audited CLEAN.
EV8_BAD=""
for ev8 in HEAD '@' '@{-1}'; do
  EV8="$WORK/ev8"; ev_fixture "$EV8"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' "$ev8" > "$EV8/.claude/sdd.json"
  git -C "$EV8" add -A >/dev/null 2>&1; git -C "$EV8" commit -qm "record trunk" >/dev/null 2>&1
  bash "$SCRIPTS/trunk-audit.sh" "$EV8" >/dev/null 2>&1
  [[ "$?" -eq 2 ]] || EV8_BAD="$EV8_BAD $ev8"
done
if [[ -z "$EV8_BAD" ]]; then
  ok "V19-F8: a trunk recorded as HEAD, @ or a reflog form is refused"
else
  bad "V19-F8: a trunk recorded as HEAD, @ or a reflog form is refused" \
      "these were accepted and audited:$EV8_BAD. The audited ref then depends on where HEAD happens to point, so a spec branch can be audited as though it were the trunk"
fi
# CONTROL: the ordinary spelling still audits, or the refusal above is a blanket one.
EV8OK="$WORK/ev8ok"; ev_fixture "$EV8OK"
if bash "$SCRIPTS/trunk-audit.sh" "$EV8OK" >/dev/null 2>&1; then
  ok "V19-F8 control: a plain branch name still audits"
else
  bad "V19-F8 control: a plain branch name still audits" \
      "the position guard is refusing ordinary configurations, so the case above proves nothing"
fi

# THE TALLY CANNOT PRINT AN IMPOSSIBLE PAIR (V19-F9). The chore arm incremented
# CLEAN inside the PER-PARENT loop and the per-commit bucket incremented it
# again, so `clean` could exceed `audited`. No violation was ever missed; a
# shipped counter that prints an impossible pair is still a claim users read.
EV9="$WORK/ev9"; ev_fixture "$EV9"
git -C "$EV9" checkout -q -b chore/one
printf 'x\n' > "$EV9/src/chore.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0002 | D | ACTIVE | x |\n\n- CHORE-007: DONE 2026-08-27. did a thing\n' > "$EV9/specs/STATUS.md"
git -C "$EV9" add -A >/dev/null 2>&1; git -C "$EV9" commit -qm "chore work" >/dev/null 2>&1
git -C "$EV9" checkout -q main
git -C "$EV9" merge -q --no-ff -m "merge chore/one" chore/one >/dev/null 2>&1
EV9_LINE="$(bash "$SCRIPTS/trunk-audit.sh" "$EV9" 2>&1 | grep '^audited' || true)" # fail-open-ok: an absent line is caught by the emptiness test below
EV9_A="$(printf '%s' "$EV9_LINE" | sed -E 's/^audited ([0-9]+).*/\1/')"
EV9_C="$(printf '%s' "$EV9_LINE" | sed -E 's/.*: ([0-9]+) clean.*/\1/')"
if [[ -z "$EV9_LINE" || -z "$EV9_A" || -z "$EV9_C" ]]; then
  bad "V19-F9: the audit tally never reports more clean than audited" \
      "no audited/clean line was produced, so this comparison read nothing: [$EV9_LINE]"
elif [[ "$EV9_C" -le "$EV9_A" ]]; then
  ok "V19-F9: the audit tally never reports more clean than audited ($EV9_C of $EV9_A)"
else
  bad "V19-F9: the audit tally never reports more clean than audited" \
      "it printed $EV9_C clean of $EV9_A audited, which is impossible: a commit is being counted in more than one bucket"
fi

# THE CLI GUARDS (F12). A value-less --since used to `shift 2` with one argument
# left, which is an error that leaves $# UNCHANGED, so the loop spun forever.
# Not reachable from pre-push, which always passes a value; a human or a CI job
# running the CLI hangs. Watched red first by the reproduction hanging.
EVF="$WORK/evf12"; ev_fixture "$EVF"
EV12_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$EVF" --since 2>&1)"; EV12_RC=$?
if [[ "$EV12_RC" -eq 2 ]] && printf '%s' "$EV12_OUT" | grep -q 'needs a <ref>'; then
  ok "F12: a value-less --since is refused by name rather than looping"
else
  bad "F12: a value-less --since is refused by name rather than looping" \
      "rc=$EV12_RC out=[$EV12_OUT]; the guard must refuse before the shift, because `shift 2` past the end leaves the argument list unchanged"
fi
EV12_BASE="$(git -C "$EVF" rev-parse HEAD)"
if bash "$SCRIPTS/trunk-audit.sh" "$EVF" --since="$EV12_BASE" >/dev/null 2>&1; then
  ok "F12: the --since=<ref> spelling is accepted"
else
  bad "F12: the --since=<ref> spelling is accepted" \
      "it was read as the instance directory, which is the confusing error a correct command used to get"
fi

# SP2-F5: the file stops describing itself as harmless while pre-push uses it as
# a gate. Asserted on the SHIPPED BYTES rather than on prose, and stated as the
# absence of the retired claims: the correction paraphrases them rather than
# quoting them, precisely so a grep like this one cannot read a quotation as a
# claim.
if grep -qE '^# ADVISORY as of plugin|it does not gate a commit|a finding does not block anything' "$SCRIPTS/trunk-audit.sh"; then
  bad "SP2-F5: trunk-audit.sh does not call itself advisory" \
      "the header still carries a retired advisory claim verbatim. pre-push RUNS this script on every push and refuses the push on its verdict, so a file calling itself harmless is a shipped claim that is false"
else
  ok "SP2-F5: trunk-audit.sh does not call itself advisory"
fi

# THE OCTOPUS SUB-MERGE (v1.7 claims round 5), and why this assertion exists.
#
# The round-4 chained-merge check read only the SECOND parent of a sub-merge, so
# `git merge --no-ff main sneaky` put the trunk in parent 2, was skipped as a
# catch-up, and the unspecced parent 3 was never examined. The verdict flipped on
# the ARGUMENT ORDER of a merge with identical content.
#
# This file already carried the lesson in those words at the top-level parent
# loop ("EVERY merged parent, not just the second", 1.0.5), and the fix written
# to be that check's backstop reintroduced it. So the assertion pins the ORDER
# dimension explicitly rather than one spelling of it.
CHO="$WORK/chain-octopus"; chain_fixture "$CHO"
CHO_BASE="$(git -C "$CHO" rev-parse HEAD)"
printf 'docs\n' > "$CHO/D.md"
git -C "$CHO" add -A >/dev/null 2>&1; git -C "$CHO" commit -qm "main moves on" >/dev/null 2>&1
git -C "$CHO" checkout -q -b sneaky "$CHO_BASE"
printf 'export const evil = 1\n' > "$CHO/src/evil.js"
git -C "$CHO" add -A >/dev/null 2>&1; git -C "$CHO" commit -qm "sneaky code" >/dev/null 2>&1
git -C "$CHO" checkout -q -b spec/0001-first "$CHO_BASE"; chain_close "$CHO"
git -C "$CHO" merge -q --no-ff -m "sync main and pull in sneaky" main sneaky >/dev/null 2>&1
git -C "$CHO" checkout -q main
git -C "$CHO" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHO" >/dev/null 2>&1; then
  ok "chain d: KNOWN HOLE, the OCTOPUS spelling of the chained merge is reported clean too, as Known limitations records"
else
  ok "chain d: the octopus sub-merge is refused again, which CLOSES a documented hole; check chain e first, then move the bullet in the same commit"
fi

CHB="$WORK/chain-plain"; chain_fixture "$CHB"
git -C "$CHB" checkout -q -b spec/0001-first main; chain_close "$CHB"
git -C "$CHB" checkout -q main
git -C "$CHB" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHB" >/dev/null 2>&1; then
  ok "chain b control: an ordinary compliant close is still clean"
else
  bad "chain b control: an ordinary compliant close is still clean" \
      "the chained-merge check is refusing ordinary closes, so case a proves nothing"
fi

CHC="$WORK/chain-catchup"; chain_fixture "$CHC"
printf 'docs\n' > "$CHC/README2.md"
git -C "$CHC" add -A >/dev/null 2>&1; git -C "$CHC" commit -qm "trunk moves on" >/dev/null 2>&1
git -C "$CHC" checkout -q -b spec/0001-first HEAD~1; chain_close "$CHC"
git -C "$CHC" merge -q --no-ff main -m "catch up with the trunk" >/dev/null 2>&1
git -C "$CHC" checkout -q main
git -C "$CHC" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHC" >/dev/null 2>&1; then
  ok "chain c control: merging the TRUNK into a spec branch stays clean (catch-up merges are ordinary)"
else
  bad "chain c control: merging the TRUNK into a spec branch stays clean (catch-up merges are ordinary)" \
      "the commonest legitimate workflow is refused, which is the false-denial direction"
fi

# THE ++ DIFF-PARSER INSTANCE (v1.7 claims round 4, F2), documented not fixed.
#
# slh_scan_added drops the `+++ b/path` diff header with `grep -vE '^\+\+\+'`,
# and a SOURCE line beginning `++` renders as `+++...`, so it is dropped too.
# Classified by replay as SCAN-ONLY: trunk discipline still refuses the merge
# (SLH-CLOSES-NO-SPEC), so no unclosed code reaches the trunk by this route.
# Under the standing rule a bypass of the already-documented best-effort scan is
# not a finding, and fixing the scan to see more is the coverage extension the
# original bound forbade. Pinned here so that the day it closes we find out.
PLUSD="$WORK/plus-prefix"; rm -rf "$PLUSD"; scan_ref_fixture "$PLUSD"
git -C "$PLUSD" checkout -q -b spec/0012-plus main
printf '++%s\n' "$SCAN_SECRET" > "$PLUSD/src/plus.txt"
git -C "$PLUSD" add -A >/dev/null 2>&1
if git -C "$PLUSD" commit -qm "++ prefixed secret" >/dev/null 2>&1; then
  ok "plus prefix: a source line beginning ++ is dropped by the diff reader, as Known limitations records (documented hole, still open)"
else
  ok "plus prefix: a source line beginning ++ is now scanned, which CLOSES a documented hole; update the bullet and this ledger entry"
fi

# THE EMPTY-DIRECTORY DELIVERY PATH (v1.7 claims audit, R3-1).
#
# THIS FIXTURE EXISTS BECAUSE OF WHAT IT CAUGHT, and the shape of the miss
# matters more than the defect. /setlist:new runs in an EMPTY directory, so no
# git repository exists when stamp.sh runs, so stamp.sh could not set
# core.hooksPath or merge.ff and (before R3-1) said nothing about it. Every
# project from the primary onboarding path shipped with .githooks/ present and
# NO enforcement: a secret committed, an unclosed spec merged onto the trunk,
# and both reached a remote, every command exiting 0.
#
# NINE HOSTILE LEGS AT ROUGHLY 45 USD EACH MISSED IT, because every fixture in
# this suite and in the leg driver stamps into an EXISTING repository. The
# corpus was not wrong about the mechanism; it was wrong about the POPULATION.
# A single fixture that starts from an empty directory finds it for nothing.
#
# Two halves, and the second is what makes the first safe to rely on.
EMPTYD="$WORK/empty-start"; rm -rf "$EMPTYD"; mkdir -p "$EMPTYD"
printf 'project_name=P\nstack=Node\nworking_mode=review only\nui=no\nopusplan_verified=yes\ndesign_surface=no\n' > "$EMPTYD/answers"
( cd "$EMPTYD" && bash "$SCRIPTS/stamp.sh" answers proj ) > "$EMPTYD/stamp.out" 2>&1
if grep -qi 'NOT ARMED' "$EMPTYD/stamp.out"; then
  ok "empty start a: stamping into a directory with no repository SAYS it could not arm the boundary"
else
  bad "empty start a: stamping into a directory with no repository SAYS it could not arm the boundary" \
      "the stamp was silent about it, which is how every /setlist:new project shipped unenforced"
fi

# The second half: a scaffold that follows the shipped instruction ends ARMED,
# and the boundary then actually refuses. Without this, half a says only that
# the stamp complains.
ESP="$EMPTYD/proj"
if [[ -d "$ESP" ]]; then
  git_init "$ESP"
  git -C "$ESP" config core.hooksPath .githooks
  git -C "$ESP" config merge.ff false
  git -C "$ESP" add -A >/dev/null 2>&1
  git -C "$ESP" -c core.hooksPath=/dev/null commit -qm "scaffold: first commit" >/dev/null 2>&1
  ES_HP="$(git -C "$ESP" config --get core.hooksPath 2>/dev/null || printf unset)" # fail-open-ok: an unset value prints "unset" and fails the test below, which is the finding rather than a skipped check
  if [[ "$ES_HP" == ".githooks" ]]; then
    ok "empty start b: a scaffold that follows the shipped instruction ends with the boundary armed"
  else
    bad "empty start b: a scaffold that follows the shipped instruction ends with the boundary armed" \
        "core.hooksPath reads [$ES_HP], so the instruction does not produce an enforced project"
  fi
  git -C "$ESP" checkout -q -b spec/0001-x 2>/dev/null
  mkdir -p "$ESP/src"
  printf 'api_key = "AKIAABCDEFGH12345678"\n' > "$ESP/src/a.js"
  git -C "$ESP" add -A >/dev/null 2>&1
  if git -C "$ESP" commit -qm "code plus a secret" >/dev/null 2>&1; then
    bad "empty start c: the armed boundary refuses a secret in a project built from an empty directory" \
        "the commit was allowed, so the project is stamped but unenforced, which is R3-1 still open"
  else
    ok "empty start c: the armed boundary refuses a secret in a project built from an empty directory"
  fi
fi

# COVERAGE NOTE FOR THE OTHER DELIVERY PATHS, filed rather than fixed here.
# retrofit and upgrade both operate on an EXISTING repository by definition, so
# the empty-start shape does not apply to them; refresh-instance.sh is covered
# for the cannot-write-config case by "refresh cfgfail" above. The gap this
# leaves, and it is filed in the backlog rather than closed here, is that no
# fixture drives retrofit into a repository that has NO commits yet, which is a
# different unusual start from an empty directory.

# THE PUSH-TIME SCAN REFUSES WHEN IT CANNOT RUN (v1.7 claims audit, R2-3).
#
# pre-commit and pre-merge-commit probed their toolchain; pre-push did not, and
# its scan is pure grep. A grep that exits non-zero with no output is
# indistinguishable from "nothing matched", so the scan reported clean and the
# push succeeded with the secret reaching the remote, while the SAME broken grep
# correctly refused the same content at commit time. That is the fail-open the
# library banner exists to say was removed, in the layer the release calls its
# guarantee, so it was fixed rather than documented.
#
# Both directions, because a hook that refuses every push would satisfy the
# first half alone.
TCHK="$WORK/toolchain-push"; rm -rf "$TCHK" "$TCHK-rem.git"
scan_ref_fixture "$TCHK"
mkdir -p "$WORK/brokenbin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/brokenbin/grep"
chmod +x "$WORK/brokenbin/grep"
git -C "$TCHK" checkout -q -b spec/0010-tc main
printf '%s\n' "$SCAN_SECRET" > "$TCHK/src/leak.js"
git -C "$TCHK" add -A >/dev/null 2>&1
git -C "$TCHK" -c core.hooksPath=/dev/null commit -qm leak >/dev/null 2>&1
if git -C "$TCHK" push -q origin spec/0010-tc >/dev/null 2>&1; then
  bad "toolchain push control: a healthy grep refuses the secret at push" \
      "the push succeeded with a working grep, so the broken-grep case below proves nothing"
else
  ok "toolchain push control: a healthy grep refuses the secret at push"
  if PATH="$WORK/brokenbin:$PATH" git -C "$TCHK" push -q origin spec/0010-tc >/dev/null 2>&1; then
    bad "toolchain push: a BROKEN grep refuses instead of reporting a clean scan" \
        "the push succeeded with a grep that cannot run, so the scan reported clean without reading anything"
  else ok "toolchain push: a BROKEN grep refuses instead of reporting a clean scan"; fi
fi
# THE FALSE-DENIAL DIRECTION: ordinary work must still push with a healthy toolchain.
git -C "$TCHK" checkout -q -b spec/0011-ok main
printf 'ordinary\n' > "$TCHK/src/ok.js"
git -C "$TCHK" add -A >/dev/null 2>&1
git -C "$TCHK" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
if git -C "$TCHK" push -q origin spec/0011-ok >/dev/null 2>&1; then
  ok "toolchain push control 2: a clean branch still pushes under a healthy toolchain"
else
  bad "toolchain push control 2: a clean branch still pushes under a healthy toolchain" \
      "the probe is refusing ordinary work, which is the false-denial direction"
fi

# THE CHECKOUT SWITCH (v1.7 second bound leg, F1), documented and pinned.
#
# Every git hook opens by checking that the CHECKED-OUT branch carries
# .claude/sdd.json and exits silently when it does not. That guard is what stops
# a stamped hooksPath governing unrelated repositories, and it also means a
# checkout is an enforcement switch: the same push refused from the trunk
# succeeds from a branch that lacks the file. This is scope-reduced rather than
# repaired, per the owner's bound, so it is asserted HERE so that the day it
# closes we find out instead of shipping a document describing a hole we no
# longer have.
SDDSW="$WORK/sdd-switch"; rm -rf "$SDDSW" "$SDDSW-rem.git"
mkdir -p "$SDDSW/src" "$SDDSW/specs" "$SDDSW/.claude/hooks" "$SDDSW/.githooks"
git_init "$SDDSW"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SDDSW/.claude/sdd.json"
printf 'x\n' > "$SDDSW/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SDDSW/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
   "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SDDSW/.githooks/"
chmod +x "$SDDSW/.githooks/pre-commit" "$SDDSW/.githooks/pre-merge-commit" "$SDDSW/.githooks/pre-push"
cp "$ROOT/scripts/trunk-audit.sh" "$SDDSW/.claude/hooks/trunk-audit.sh"
git -C "$SDDSW" config core.hooksPath .githooks
git -C "$SDDSW" add -A >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
git init -q --bare "$SDDSW-rem.git"; git -C "$SDDSW" remote add origin "$SDDSW-rem.git"
git -C "$SDDSW" push -q origin main >/dev/null 2>&1
git -C "$SDDSW" checkout -q -b work
printf 'unclosed\n' > "$SDDSW/src/FEATURE.txt"
git -C "$SDDSW" add -A >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm feat >/dev/null 2>&1
git -C "$SDDSW" checkout -q main
git -C "$SDDSW" merge -q --no-verify --no-ff -m m work >/dev/null 2>&1
# CONTROL: from the trunk, with sdd.json present, the audit refuses this push.
if git -C "$SDDSW" push -q origin main >/dev/null 2>&1; then
  bad "sdd switch control: with sdd.json present the unclosed trunk is refused" \
      "the push was allowed, so the case below proves nothing about the guard"
else ok "sdd switch control: with sdd.json present the unclosed trunk is refused"; fi
# THE HOLE: the same push from a branch WITHOUT the file.
git -C "$SDDSW" checkout -q --orphan legacy >/dev/null 2>&1
git -C "$SDDSW" rm -rq --cached . >/dev/null 2>&1
rm -f "$SDDSW/.claude/sdd.json"
printf 'legacy\n' > "$SDDSW/legacy.txt"
git -C "$SDDSW" add legacy.txt >/dev/null 2>&1
git -C "$SDDSW" -c core.hooksPath=/dev/null commit -qm legacy >/dev/null 2>&1
if git -C "$SDDSW" push -q origin main >/dev/null 2>&1; then
  ok "sdd switch: a checkout without .claude/sdd.json makes every hook inert (documented hole, still open)"
else
  ok "sdd switch: the checkout switch is now CLOSED, which means Known limitations describes a hole that no longer exists; update the bullet and this ledger entry"
fi

# THE TWO DOCUMENTED GIT-HOOK HOLES, asserted rather than merely described.
# Both are in the public README's Known limitations and therefore in the suite's
# hole ledger, and the docs-tree lockstep gate refuses a publish where the two
# disagree. Asserting a hole is not endorsing it: it is making sure that the day
# it closes, we find out, instead of shipping a document describing a weakness
# we no longer have.
GH="$WORK/gh-noverify"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-verify --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  ok "git hooks m: --no-verify really does skip the hooks (documented hole, still open)"
else
  bad "git hooks m: --no-verify really does skip the hooks (documented hole, still open)" \
      "it was blocked, so the README's Known limitations now describes a hole that does not exist"
fi

# The per-clone gap, both halves: the TRACKED directory survives a clone (which
# is why the hooks live there rather than in .git/hooks), and the CONFIG pointing
# at it does not (which is the residual hole the README states).
GH="$WORK/gh-clone-src"; gh_fixture "$GH" no
GHC="$WORK/gh-clone-dst"; rm -rf "$GHC"
if git clone -q "$GH" "$GHC" >/dev/null 2>&1; then
  if [[ -f "$GHC/.githooks/pre-merge-commit" ]]; then
    ok "git hooks n: a fresh clone DOES carry the tracked .githooks/ directory"
  else
    bad "git hooks n: a fresh clone DOES carry the tracked .githooks/ directory" "the hooks did not survive the clone"
  fi
  if [[ -z "$(git -C "$GHC" config --get core.hooksPath || true)" ]]; then
    ok "git hooks o: a fresh clone does NOT carry core.hooksPath (documented per-clone hole)"
  else
    bad "git hooks o: a fresh clone does NOT carry core.hooksPath (documented per-clone hole)" \
        "the config survived the clone, so the README overstates the gap"
  fi
else
  bad "git hooks n/o: the clone fixture could be created" "git clone failed, so neither half was checked"
fi

# --ff-only, the documented hole, asserted in BOTH directions: it really does
# skip the merge hooks (so the README is not describing a hole that closed), and
# pre-push really does catch the result (so the README is not overstating the
# damage). Found by the v1.7 dogfood gate's merge.ff probe.
GHF="$WORK/gh-ffonly"; gh_fixture "$GHF" no
# CONTROL: a fast-forward has to be POSSIBLE for this case to test anything. If
# the trunk is not an ancestor of the spec branch there is nothing to fast
# forward and the assertion below would pass for the wrong reason.
assert_true "git hooks p0: the fixture can actually fast-forward (trunk is an ancestor)" \
  "the trunk is not an ancestor of the spec branch, so --ff-only cannot apply and the case below tests nothing" \
  git -C "$GHF" merge-base --is-ancestor main spec/0001-thing
GHF_OUT="$( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff-only spec/0001-thing 2>&1 )"
if gh_landed "$GHF"; then
  ok "git hooks p: --ff-only really does skip the merge hooks (documented hole, still open)"
else
  bad "git hooks p: --ff-only really does skip the merge hooks (documented hole, still open)" \
      "it did not land; git said: ${GHF_OUT:-<no output>}"
fi
GHF_REMOTE="$WORK/gh-ffonly-remote.git"; rm -rf "$GHF_REMOTE"; git init -q --bare "$GHF_REMOTE"
git -C "$GHF" remote add origin "$GHF_REMOTE" 2>/dev/null || true
cp "$ROOT/templates/git-hooks/pre-push" "$GHF/.githooks/pre-push"; chmod +x "$GHF/.githooks/pre-push"
mkdir -p "$GHF/.claude/hooks"; cp "$ROOT/scripts/trunk-audit.sh" "$GHF/.claude/hooks/trunk-audit.sh"
( cd "$GHF" && env -u CLAUDE_PLUGIN_ROOT git push origin main ) >/dev/null 2>&1
if git -C "$GHF_REMOTE" cat-file -e main:src/FEATURE.txt 2>/dev/null; then
  bad "git hooks q: pre-push CATCHES what --ff-only let onto the local trunk" \
      "it reached the remote, so the mitigation the README claims does not hold and --ff-only is a full bypass"
else
  ok "git hooks q: pre-push CATCHES what --ff-only let onto the local trunk"
fi

fi; shard_region_end
# <<< SHARD-END hooks-round11
