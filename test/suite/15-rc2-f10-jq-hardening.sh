#!/usr/bin/env bash
# test/suite/15-rc2-f10-jq-hardening.sh: shard 15 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# >>> SHARD-BEGIN rc2-config-blind cost=13
if shard_region rc2-config-blind; then
# =============================================================================
# RC2-2026: CONFIGURATION-DRIVEN DIFF RENDERING BLINDS THE CONTENT SCANS (spec
# 0129, 2026-09-02; the 2.4.0 leg's F2 as filed, confirmed by control in spec
# 0128 and fixed here).
#
# Every content scan and every lifecycle detector reads the OUTPUT of `git diff`
# or `git show`, which is a RENDERING the repository's own configuration
# controls. With `color.ui=always` (or `color.diff=always`) git colours its
# output into a pipe, every `+` line arrives as `ESC[32m+...`, the added-line
# filter matches nothing, and a live-shaped secret commits and pushes clean at
# exit 0 with nothing printed. SLH-SCAN-FILTER-FAILED did not fire, because awk
# exits 0 over lines it merely fails to match. Watched RED before the fix at
# every subject case below, with every clean twin green in the same run.
#
# THE FIX IS FLAGS THAT IGNORE CONFIGURATION at every site that renders a diff
# for a scan or a detector: --no-color, --no-ext-diff and --no-textconv, plus
# --root at the push-time walk. Each member was MEASURED rather than assumed
# (spec 0129's record): colour blinds every site; an external diff driver blinds
# the three sites that lacked --no-ext-diff; a textconv driver hides the content
# it converts; `log.showRoot=false` empties `git show` on a root commit; and the
# prefix settings (diff.noprefix, diff.mnemonicPrefix, diff.srcPrefix,
# diff.dstPrefix) blind NOTHING, because the added-line filter is positional
# since 2.3.0, so no prefix flag is pinned and the last case here pins that
# measurement instead of a flag.
#
# AND ONE MORE THING THE MEASUREMENT FOUND, ruled 2026-09-02: every site took
# its diff through $(git ... 2>/dev/null), so git's own exit status was lost,
# and a git that ran and died rendered nothing, which read as clean. Every site
# now captures git's status and refuses under the codes that already exist for
# a scan that could not run: SLH-SCAN-FILTER-FAILED at the guarantee layer,
# CM-NO-GIT at the advisory layer. No new identifier; the leg trigger verified
# quiet. Case g says how the death is reproduced, and why neither an
# unparseable config value nor a PATH shim can reproduce it.
#
# THE SECRET IS OUTSIDE THE ROLE PATHS (docs/) at every case, on the push-scan
# block's lesson: the trunk audit and the close checks then have nothing to say
# and only the scan or the detector can refuse, so a refusal here is evidence
# about the subject and not about a neighbour.
# =============================================================================
RC2_SECRET='api_key = "AKIAQQQQZZZZ1234567890abcd"'
rc2_mk() { # rc2_mk <name> [root-secret] -> an armed instance with a bare remote, prints its path
  local d="$WORK/rc2-$1"
  rm -rf "$d" "$WORK/rc2-$1.git"
  mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs" "$d/docs"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | thing | ACTIVE | |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n\n## Goal\n\nx\n' > "$d/specs/0001-thing.md"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$d/docs/root.txt"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm base >/dev/null 2>&1
  git init -q --bare "$WORK/rc2-$1.git"
  git -C "$d" remote add origin "$WORK/rc2-$1.git"
  printf '%s' "$d"
}
rc2_commit() { # rc2_commit <dir> <path> <content> <outfile> -> git's status with the hooks ON
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -qm "add $2" >"$4" 2>&1
}
rc2_clean() { # rc2_clean <dir> -> drop whatever a refused commit left staged
  git -C "$1" reset -q --hard HEAD >/dev/null 2>&1
  git -C "$1" clean -qfd >/dev/null 2>&1
  mkdir -p "$1/docs"   # clean -d takes an emptied directory with it
}
rc2_refused() { # rc2_refused <name> <outfile> <code> <how-it-passed> after a commit/merge/push that returned NONZERO
  if grep -q "$3" "$2"; then ok "$1"; else bad "$1" "refused, but not by $3: $(tr '\n' ' ' < "$2" | cut -c1-240)"; fi
}

# --- a. pre-commit under color.ui=always ------------------------------------
A="$(rc2_mk a)"; git -C "$A" config color.ui always
if rc2_commit "$A" docs/conf.txt "$RC2_SECRET" "$WORK/rc2a.out"; then
  bad "RC2 a: pre-commit refuses a secret under color.ui=always" \
      "it committed clean: git coloured the diff into the pipe and the added-line filter read nothing"
else rc2_refused "RC2 a: pre-commit refuses a secret under color.ui=always" "$WORK/rc2a.out" SLH-SECRET; fi
rc2_clean "$A"
if rc2_commit "$A" docs/notes.txt "ordinary prose, nothing to find" "$WORK/rc2a2.out"; then
  ok "RC2 a twin: clean content still commits under color.ui=always"
else bad "RC2 a twin: clean content still commits under color.ui=always" "$(tr '\n' ' ' < "$WORK/rc2a2.out" | cut -c1-200)"; fi

# --- b. the other spelling, color.diff=always --------------------------------
B="$(rc2_mk b)"; git -C "$B" config color.diff always
if rc2_commit "$B" docs/conf.txt "$RC2_SECRET" "$WORK/rc2b.out"; then
  bad "RC2 b: pre-commit refuses a secret under color.diff=always" "it committed clean"
else rc2_refused "RC2 b: pre-commit refuses a secret under color.diff=always" "$WORK/rc2b.out" SLH-SECRET; fi

# --- c. pre-merge-commit under color.ui=always -------------------------------
C="$(rc2_mk c)"; git -C "$C" config color.ui always
git -C "$C" checkout -q -b sync
printf '%s\n' "$RC2_SECRET" > "$C/docs/conf.txt"; git -C "$C" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$C" commit -qm "sync brings a secret" >/dev/null 2>&1
git -C "$C" checkout -q main
if git -C "$C" merge -q --no-ff -m "merge sync" sync >"$WORK/rc2c.out" 2>&1; then
  bad "RC2 c: pre-merge-commit refuses a secret under color.ui=always" "the merge landed: the merge's content scan read a coloured diff as empty"
else rc2_refused "RC2 c: pre-merge-commit refuses a secret under color.ui=always" "$WORK/rc2c.out" SLH-SECRET; fi
git -C "$C" merge --abort >/dev/null 2>&1 || true; rc2_clean "$C"
git -C "$C" checkout -q -b sync2 main
printf 'clean\n' > "$C/docs/clean.txt"; git -C "$C" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$C" commit -qm "sync brings prose" >/dev/null 2>&1
git -C "$C" checkout -q main
if git -C "$C" merge -q --no-ff -m "merge sync2" sync2 >"$WORK/rc2c2.out" 2>&1; then
  ok "RC2 c twin: a clean merge still lands under color.ui=always"
else bad "RC2 c twin: a clean merge still lands under color.ui=always" "$(tr '\n' ' ' < "$WORK/rc2c2.out" | cut -c1-200)"; fi

# --- d. pre-push under color.ui=always ----------------------------------------
D="$(rc2_mk d)"; git -C "$D" config color.ui always
printf '%s\n' "$RC2_SECRET" > "$D/docs/conf.txt"; git -C "$D" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$D" commit -qm "secret" >/dev/null 2>&1
if git -C "$D" push -q origin main >"$WORK/rc2d.out" 2>&1; then
  bad "RC2 d: pre-push refuses a secret under color.ui=always" "it pushed: the per-commit walk read a coloured diff as empty"
else rc2_refused "RC2 d: pre-push refuses a secret under color.ui=always" "$WORK/rc2d.out" SLH-SECRET; fi
D2="$(rc2_mk d2)"; git -C "$D2" config color.ui always
printf 'prose\n' > "$D2/docs/notes.txt"; git -C "$D2" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$D2" commit -qm "prose" >/dev/null 2>&1
if git -C "$D2" push -q origin main >"$WORK/rc2d2.out" 2>&1; then
  ok "RC2 d twin: a clean push still lands under color.ui=always"
else bad "RC2 d twin: a clean push still lands under color.ui=always" "$(tr '\n' ' ' < "$WORK/rc2d2.out" | cut -c1-200)"; fi

# --- f. the lifecycle detector under color.ui=always --------------------------
F="$(rc2_mk f)"; git -C "$F" config color.ui always
printf '# Spec 0001 - thing\n\nStatus: BUILT\n\n## Goal\n\nx\n' > "$F/specs/0001-thing.md"
git -C "$F" add specs/0001-thing.md >/dev/null 2>&1
if git -C "$F" commit -qm "flip" >"$WORK/rc2f.out" 2>&1; then
  bad "RC2 f: the lifecycle detector sees a Status flip under color.ui=always and demands STATUS.md" \
      "it committed: the detector read a coloured diff as adding no lifecycle line"
else rc2_refused "RC2 f: the lifecycle detector sees a Status flip under color.ui=always and demands STATUS.md" "$WORK/rc2f.out" SLH-STATUS-MISSING; fi
printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | thing | BUILT | |\n' > "$F/specs/STATUS.md"
git -C "$F" add specs/STATUS.md >/dev/null 2>&1
if git -C "$F" commit -qm "flip with the row" >"$WORK/rc2f2.out" 2>&1; then
  ok "RC2 f twin: the same flip with STATUS.md staged commits under color.ui=always"
else bad "RC2 f twin: the same flip with STATUS.md staged commits under color.ui=always" "$(tr '\n' ' ' < "$WORK/rc2f2.out" | cut -c1-200)"; fi

# --- g. git DIES at the render, and only at the render ------------------------
# Under an UNPARSEABLE repository config value (diff.colorMoved=always,
# diff.context=abc) git refuses the commit ITSELF at rc 128 before the object is
# written (measured: HEAD unmoved), and at push the trunk audit dies first, so
# such a value cannot produce a silent landing on its own. A PATH shim cannot
# reach a hook either: git prepends its own exec path when it runs hooks. What
# kills the render and nothing else is a diff driver whose hunk-header regex
# does not compile: `git diff --cached --unified=0` dies at rc 128 with empty
# output while `--name-only`, `rev-parse` and `git commit` all succeed, so
# before the fix the scan read empty as clean and the commit LANDED. Measured
# by the fixture check below before anything rests on it.
rc2_break_render() { # rc2_break_render <dir> -> every path's diff driver has an uncompilable funcname regex
  printf '* diff=broken\n' > "$1/.gitattributes"
  git -C "$1" config diff.broken.xfuncname '('
}
G="$(rc2_mk g)"; rc2_break_render "$G"
printf 'probe\n' > "$G/docs/probe.txt"; git -C "$G" add -A >/dev/null 2>&1
if ! git -C "$G" diff --cached --unified=0 >/dev/null 2>&1 && git -C "$G" diff --cached --name-only >/dev/null 2>&1; then
  ok "RC2 g0: the broken driver kills the patch render and leaves name-only reads alone"
else
  bad "RC2 g0: the broken driver kills the patch render and leaves name-only reads alone" "the fixture is broken, so g through j prove nothing"
fi
git -C "$G" reset -q -- docs/probe.txt >/dev/null 2>&1; rm -f "$G/docs/probe.txt"
RC2_G_BASE="$(git -C "$G" rev-parse HEAD)"
if rc2_commit "$G" docs/notes.txt "clean prose" "$WORK/rc2g.out"; then
  bad "RC2 g: pre-commit refuses when git cannot render the staged diff" \
      "it committed clean: git died rendering the diff, the scan read empty as clean, and HEAD moved"
elif [[ "$(git -C "$G" rev-parse HEAD)" != "$RC2_G_BASE" ]]; then
  bad "RC2 g: pre-commit refuses when git cannot render the staged diff" "refused, but HEAD moved anyway"
else rc2_refused "RC2 g: pre-commit refuses when git cannot render the staged diff" "$WORK/rc2g.out" SLH-SCAN-FILTER-FAILED; fi
rc2_clean "$G"; rm -f "$G/.gitattributes"; git -C "$G" config --unset diff.broken.xfuncname
if rc2_commit "$G" docs/notes.txt "clean prose" "$WORK/rc2g2.out"; then
  ok "RC2 g twin: with the driver removed, the same content commits"
else bad "RC2 g twin: with the driver removed, the same content commits" "$(tr '\n' ' ' < "$WORK/rc2g2.out" | cut -c1-200)"; fi

# --- i. git DIES at the render under the push-time walk --------------------------
I="$(rc2_mk i)"
printf 'prose\n' > "$I/docs/notes.txt"; git -C "$I" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$I" commit -qm "prose" >/dev/null 2>&1
rc2_break_render "$I"
if git -C "$I" push -q origin main >"$WORK/rc2i.out" 2>&1; then
  bad "RC2 i: pre-push refuses when git cannot render a commit in the pushed range" \
      "it pushed: the walk's git show died, the scan read empty as clean, and the remote moved"
elif [[ -n "$(git -C "$I" ls-remote origin main 2>/dev/null)" ]]; then
  bad "RC2 i: pre-push refuses when git cannot render a commit in the pushed range" "refused, but the remote moved anyway"
else rc2_refused "RC2 i: pre-push refuses when git cannot render a commit in the pushed range" "$WORK/rc2i.out" SLH-SCAN-FILTER-FAILED; fi

# --- j. git DIES at the render under the lifecycle detector, which names itself ---
J="$(rc2_mk j)"; rc2_break_render "$J"; RC2_J_BASE="$(git -C "$J" rev-parse HEAD)"
printf '# Spec 0001 - thing\n\nStatus: BUILT\n\n## Goal\n\nx\n' > "$J/specs/0001-thing.md"
git -C "$J" add specs/0001-thing.md >/dev/null 2>&1
if git -C "$J" commit -qm "flip" >"$WORK/rc2j.out" 2>&1; then
  bad "RC2 j: the lifecycle detector refuses by name when git cannot render the spec's diff" \
      "it committed: a Status flip went through without STATUS.md because the detector read empty as no flip"
elif [[ "$(git -C "$J" rev-parse HEAD)" != "$RC2_J_BASE" ]]; then
  bad "RC2 j: the lifecycle detector refuses by name when git cannot render the spec's diff" "refused, but HEAD moved anyway"
elif grep -q 'SLH-SCAN-FILTER-FAILED' "$WORK/rc2j.out" && grep -q 'lifecycle detector' "$WORK/rc2j.out"; then
  ok "RC2 j: the lifecycle detector refuses by name when git cannot render the spec's diff"
else
  bad "RC2 j: the lifecycle detector refuses by name when git cannot render the spec's diff" \
      "refused, but the detector did not name itself: $(tr '\n' ' ' < "$WORK/rc2j.out" | cut -c1-240)"
fi

# --- k. log.showRoot=false: two readers on the ROOT commit --------------------
# git_init makes a seed commit, so rc2_mk's base is never the root; this fixture
# adopts the rules IN its root commit, which is exactly what /setlist:new does.
# Two readers go blind on that shape under log.showRoot=false, and they mask
# each other: the walk's `git show` renders the root as nothing (the scan
# reads empty), and the trunk audit's `git log --diff-filter=A` cannot find
# the commit that adopted the rules, so it refused every push BY ACCIDENT, a
# false denial that hid the scan's blindness. Both take --root now.
rc2_mk_root() { # rc2_mk_root <name> <root-content> -> the rules adopted in the ROOT commit
  local d="$WORK/rc2-$1"
  rm -rf "$d" "$WORK/rc2-$1.git"
  mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs" "$d/docs"
  git -C "$d" init -q; git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email "tests@example.invalid"; git -C "$d" config user.name "Setlist Tests"
  git -C "$d" config commit.gpgsign false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  printf '%s\n' "$2" > "$d/docs/root.txt"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "root: adopt the rules" >/dev/null 2>&1
  git init -q --bare "$WORK/rc2-$1.git"
  git -C "$d" remote add origin "$WORK/rc2-$1.git"
  git -C "$d" config log.showRoot false
  printf '%s' "$d"
}
K="$(rc2_mk_root k "$RC2_SECRET")"
if git -C "$K" push -q origin main >"$WORK/rc2k.out" 2>&1; then
  bad "RC2 k: pre-push scans a ROOT commit under log.showRoot=false" "it pushed: git show rendered the root as nothing and the walk read nothing"
else rc2_refused "RC2 k: pre-push scans a ROOT commit under log.showRoot=false" "$WORK/rc2k.out" SLH-SECRET; fi
K2="$(rc2_mk_root k2 "ordinary prose at the root")"
if git -C "$K2" push -q origin main >"$WORK/rc2k2.out" 2>&1; then
  ok "RC2 k twin: a clean root commit pushes under log.showRoot=false (the audit finds its baseline with --root)"
else bad "RC2 k twin: a clean root commit pushes under log.showRoot=false (the audit finds its baseline with --root)" \
         "refused: $(tr '\n' ' ' < "$WORK/rc2k2.out" | cut -c1-200)"; fi

# --- l. a textconv driver hides the content it converts ------------------------
L="$(rc2_mk l)"
printf 'docs/* diff=hide\n' > "$L/.gitattributes"
git -C "$L" config diff.hide.textconv 'echo hidden #'
git -C "$L" add .gitattributes >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$L" commit -qm "attributes" >/dev/null 2>&1
if rc2_commit "$L" docs/conf.txt "$RC2_SECRET" "$WORK/rc2l.out"; then
  bad "RC2 l: pre-commit reads the raw bytes, not a textconv rendering" "it committed clean: the scan read the converted text"
else rc2_refused "RC2 l: pre-commit reads the raw bytes, not a textconv rendering" "$WORK/rc2l.out" SLH-SECRET; fi
rc2_clean "$L"
if rc2_commit "$L" docs/notes.txt "clean prose" "$WORK/rc2l2.out"; then
  ok "RC2 l twin: clean content under a textconv driver still commits"
else bad "RC2 l twin: clean content under a textconv driver still commits" "$(tr '\n' ' ' < "$WORK/rc2l2.out" | cut -c1-200)"; fi

# --- m. an external diff driver at the one guarantee-layer site that lacked --no-ext-diff
M="$(rc2_mk m)"; git -C "$M" config diff.external false
printf '# Spec 0001 - thing\n\nStatus: BUILT\n\n## Goal\n\nx\n' > "$M/specs/0001-thing.md"
git -C "$M" add specs/0001-thing.md >/dev/null 2>&1
if git -C "$M" commit -qm "flip" >"$WORK/rc2m.out" 2>&1; then
  bad "RC2 m: the lifecycle detector ignores diff.external and still sees the Status flip" \
      "it committed: the external driver died, the detector read nothing, and the flip went through without STATUS.md"
else rc2_refused "RC2 m: the lifecycle detector ignores diff.external and still sees the Status flip" "$WORK/rc2m.out" SLH-STATUS-MISSING; fi

# --- o. prefix settings, measured harmless and pinned as such ---------------------
O="$(rc2_mk o)"; git -C "$O" config diff.noprefix true; git -C "$O" config diff.mnemonicPrefix true
if rc2_commit "$O" docs/conf.txt "$RC2_SECRET" "$WORK/rc2o.out"; then
  bad "RC2 o: prefix settings do not blind the positional filter (measured; no prefix flag is pinned)" "it committed clean under diff.noprefix and diff.mnemonicPrefix"
else rc2_refused "RC2 o: prefix settings do not blind the positional filter (measured; no prefix flag is pinned)" "$WORK/rc2o.out" SLH-SECRET; fi

fi; shard_region_end
# <<< SHARD-END rc2-config-blind
# >>> SHARD-BEGIN merge-completion-f10 cost=16
if shard_region merge-completion-f10; then
# =============================================================================
# F10-2026, THE DOCUMENTED HOLE PINNED IN ITS DOCUMENTED DIRECTION (2.4.1 leg F2,
# deferred under the 2026-09-03 A7b bound). pre-merge-commit refuses a chore
# merge with no archive line and its message says to add the line "in this
# same commit"; git says to complete the merge with `git commit`. Doing exactly
# that puts the line on the TRUNK side of the merge: pre-commit's
# merge-completion verification reads the merge INDEX and accepts, the trunk
# audit reads the merged PARENTS and refuses. Pinned so the day the two layers
# ask the same question of the merge commit, this goes red and the bullet
# leaves the list in the same commit. Measured identical on the shipped 2.4.0
# hooks, which is the deferral's not-a-regression proof.
# =============================================================================
F10="$WORK/f10-completion"; rm -rf "$F10"
mkdir -p "$F10/.claude/hooks" "$F10/.githooks" "$F10/src" "$F10/specs"
git_init "$F10"
git -C "$F10" config merge.ff false
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$F10/.claude/sdd.json"
printf '# Inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n\n## Archive\n\n' > "$F10/specs/STATUS.md"
printf 'x\n' > "$F10/src/a.txt"
cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
   "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$F10/.githooks/"
cp "$SCRIPTS/trunk-audit.sh" "$F10/.claude/hooks/trunk-audit.sh"
chmod +x "$F10/.githooks/pre-push" "$F10/.githooks/pre-commit" "$F10/.githooks/pre-merge-commit"
git -C "$F10" config core.hooksPath .githooks
git -C "$F10" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$F10" commit -qm "adopt" >/dev/null 2>&1
git -C "$F10" checkout -q -b chore/bump main
printf 'bump\n' >> "$F10/src/a.txt"; git -C "$F10" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$F10" commit -qm "chore work" >/dev/null 2>&1
git -C "$F10" checkout -q main
if git -C "$F10" merge --no-ff chore/bump -m "chore: merge" >"$WORK/f10-merge.out" 2>&1; then
  bad "F10-2026 a: the chore merge with no archive line is refused at merge time" "it merged clean, so the case below tests nothing"
elif grep -q 'SLH-CLOSES-NO-SPEC' "$WORK/f10-merge.out"; then
  ok "F10-2026 a: the chore merge with no archive line is refused at merge time"
else
  bad "F10-2026 a: the chore merge with no archive line is refused at merge time" "refused for another reason: $(tr '\n' ' ' < "$WORK/f10-merge.out" | cut -c1-200)"
fi
printf -- '- CHORE-007: DONE 2026-09-03. dependency bump\n' >> "$F10/specs/STATUS.md"
git -C "$F10" add specs/STATUS.md >/dev/null 2>&1
if git -C "$F10" commit -q --no-edit >"$WORK/f10-complete.out" 2>&1; then
  ok "F10-2026 b: KNOWN-HOLE, completing the merge with the archive line on the trunk side is ACCEPTED by pre-commit"
else
  bad "F10-2026 b: KNOWN-HOLE, completing the merge with the archive line on the trunk side is ACCEPTED by pre-commit" \
      "refused: $(tr '\n' ' ' < "$WORK/f10-complete.out" | cut -c1-200). If this is the fix landing, delete the public bullet, its ledger row and this region in the same commit"
fi
# FIXED IN 2.10.0 (spec 0157): the audit's merge arm asks the merge COMMIT the
# question pre-commit asks of the index, for a two-parent merge whose merged
# parent answers it with nothing. The case keeps its fixture and flips its
# direction; the public bullet and its ledger row leave in 0162, which lands the
# whole list in one commit.
if bash "$SCRIPTS/trunk-audit.sh" "$F10" >"$WORK/f10-audit.out" 2>&1; then
  ok "F10-2026 c: the trunk audit ACCEPTS the merge completed on the trunk side, the route the refusal text prescribes"
else
  bad "F10-2026 c: the trunk audit ACCEPTS the merge completed on the trunk side, the route the refusal text prescribes" \
      "still refused at push: $(tr '\n' ' ' < "$WORK/f10-audit.out" | cut -c1-200)"
fi

# THE SAME QUESTION ON THE SHAPE EVERY INSTANCE SINCE v1.12 ACTUALLY HAS (DE15):
# the record-carrying route. Both branches of MRG_STRUCTURED are exercised,
# because the merge arm reads the completion from .claude/status.json when the
# merged branch carries one and from specs/STATUS.md when it does not.
f10_fixture() { # f10_fixture <dir> <record|page>
  local d="$1" shape="$2"
  rm -rf "$d"; mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs"
  git_init "$d"
  git -C "$d" config merge.ff false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '# Inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n\n## Archive\n\n' > "$d/specs/STATUS.md"
  printf 'x\n' > "$d/src/a.txt"
  [[ "$shape" == "record" ]] && printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$d/.claude/status.json"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "adopt" >/dev/null 2>&1
}
f10_chore_branch() { # f10_chore_branch <dir> <branch>
  local d="$1" b="$2"
  git -C "$d" checkout -q -b "$b" main
  printf 'bump\n' >> "$d/src/a.txt"
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "chore work on $b" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
f10_audits_clean() { # f10_audits_clean <dir> <out>
  bash "$SCRIPTS/trunk-audit.sh" "$1" >"$2" 2>&1
}

F10R="$WORK/f10-completion-record"; f10_fixture "$F10R" record
f10_chore_branch "$F10R" chore/bump
if git -C "$F10R" merge --no-ff chore/bump -m "chore: merge" >"$WORK/f10r-merge.out" 2>&1; then
  bad "F10-2026 d: the record-carrying chore merge with no completion is refused at merge time" "it merged clean, so the case below tests nothing"
else
  ok "F10-2026 d: the record-carrying chore merge with no completion is refused at merge time"
fi
jq '.chores["CHORE-007"] = {"status":"done"}' "$F10R/.claude/status.json" > "$F10R/t" && mv "$F10R/t" "$F10R/.claude/status.json"
printf -- '- CHORE-007: DONE 2026-09-22. dependency bump\n' >> "$F10R/specs/STATUS.md"
git -C "$F10R" add -A >/dev/null 2>&1
if git -C "$F10R" commit -q --no-edit >"$WORK/f10r-complete.out" 2>&1; then
  ok "F10-2026 e: completing it with the record written on the trunk side is ACCEPTED by pre-commit, as it always was"
else
  bad "F10-2026 e: completing it with the record written on the trunk side is ACCEPTED by pre-commit, as it always was" \
      "refused: $(tr '\n' ' ' < "$WORK/f10r-complete.out" | cut -c1-200)"
fi
if f10_audits_clean "$F10R" "$WORK/f10r-audit.out"; then
  ok "F10-2026 f: and the audit ACCEPTS it on the record route too, so both shapes agree with pre-commit"
else
  bad "F10-2026 f: and the audit ACCEPTS it on the record route too, so both shapes agree with pre-commit" \
      "refused: $(tr '\n' ' ' < "$WORK/f10r-audit.out" | cut -c1-200)"
fi

# A CLOSE completed the same way: the refusal text prescribes this route for a
# missing close record or CLOSED row just as it does for an archive line.
f10_spec_branch() { # f10_spec_branch <dir> <shape>
  local d="$1" shape="$2"
  git -C "$d" checkout -q -b spec/0001-thing main
  printf 'feature\n' > "$d/src/f.js"
  {
    printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n'
    printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
  } > "$d/specs/0001-thing.md"
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "close 0001 on the branch" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
for F10C_SHAPE in page record; do
  F10C="$WORK/f10-close-$F10C_SHAPE"; f10_fixture "$F10C" "$F10C_SHAPE"
  f10_spec_branch "$F10C" "$F10C_SHAPE"
  if git -C "$F10C" merge --no-ff spec/0001-thing -m "Merge spec/0001-thing" >"$WORK/f10c-merge.out" 2>&1; then
    bad "F10-2026 g ($F10C_SHAPE): a close whose row and record are not on the branch is refused at merge time" \
        "it merged clean, so the case below tests nothing"
  else
    ok "F10-2026 g ($F10C_SHAPE): a close whose row and record are not on the branch is refused at merge time"
  fi
  printf '| 0001 | Thing | CLOSED | |\n' >> "$F10C/specs/STATUS.md"
  if [[ "$F10C_SHAPE" == "record" ]]; then
    jq '.specs["0001"] = {"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}' "$F10C/.claude/status.json" > "$F10C/t" \
      && mv "$F10C/t" "$F10C/.claude/status.json"
  fi
  git -C "$F10C" add -A >/dev/null 2>&1
  if git -C "$F10C" commit -q --no-edit >"$WORK/f10c-complete.out" 2>&1; then
    ok "F10-2026 h ($F10C_SHAPE): completing the close on the trunk side is ACCEPTED by pre-commit"
  else
    bad "F10-2026 h ($F10C_SHAPE): completing the close on the trunk side is ACCEPTED by pre-commit" \
        "refused: $(tr '\n' ' ' < "$WORK/f10c-complete.out" | cut -c1-200)"
  fi
  if f10_audits_clean "$F10C" "$WORK/f10c-audit.out"; then
    ok "F10-2026 i ($F10C_SHAPE): and the audit ACCEPTS the same commit, so the close route agrees at both layers"
  else
    bad "F10-2026 i ($F10C_SHAPE): and the audit ACCEPTS the same commit, so the close route agrees at both layers" \
        "refused: $(tr '\n' ' ' < "$WORK/f10c-audit.out" | cut -c1-200)"
  fi
done

# THE CONTROLS. What the fix widens is where the completion may be written, and
# nothing else: a merge completed with the record on NEITHER side is still a
# violation, and an octopus is not credited with a record on the merge commit,
# because crediting one record to several merged parents re-opens the
# laundering route the B6 fix closed (decision 9 of the intake).
for F10N_SHAPE in page record; do
  F10N="$WORK/f10-neither-$F10N_SHAPE"; f10_fixture "$F10N" "$F10N_SHAPE"
  f10_chore_branch "$F10N" chore/bump
  SETLIST_SKIP_HOOKS=1 git -C "$F10N" merge -q --no-ff chore/bump -m "chore: merge with no completion anywhere" >/dev/null 2>&1
  if f10_audits_clean "$F10N" "$WORK/f10n-audit.out"; then
    bad "F10-2026 j ($F10N_SHAPE): a merge with the completion on NEITHER side is still refused" \
        "the audit passed a chore merge nothing records: $(tr '\n' ' ' < "$WORK/f10n-audit.out" | cut -c1-200)"
  elif grep -q 'no recorded completion' "$WORK/f10n-audit.out"; then
    ok "F10-2026 j ($F10N_SHAPE): a merge with the completion on NEITHER side is still refused"
  else
    bad "F10-2026 j ($F10N_SHAPE): a merge with the completion on NEITHER side is still refused" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/f10n-audit.out" | cut -c1-200)"
  fi
done

F10O="$WORK/f10-octopus"; f10_fixture "$F10O" page
f10_chore_branch "$F10O" chore/one
f10_chore_branch "$F10O" chore/two
printf -- '- CHORE-009: DONE 2026-09-22. both at once\n' >> "$F10O/specs/STATUS.md"
git -C "$F10O" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$F10O" commit -qm "the archive line, staged for the octopus" >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$F10O" merge -q --no-ff chore/one chore/two -m "chore: octopus" >/dev/null 2>&1
if f10_audits_clean "$F10O" "$WORK/f10o-audit.out"; then
  bad "F10-2026 k: an OCTOPUS is not credited with a completion written on the merge commit" \
      "one record excused several merged parents: $(tr '\n' ' ' < "$WORK/f10o-audit.out" | cut -c1-200)"
else
  ok "F10-2026 k: an OCTOPUS is not credited with a completion written on the merge commit"
fi


# THE MIXED SHAPE (spec 0167, decision 3; L2 F6 of the 2.10.0 second leg): a
# branch cut BEFORE the instance adopted .claude/status.json, merged after it.
# pre-commit chooses record or page from the INDEX of the commit completing the
# merge, which carries the trunk's record, so it judged by the record; the
# audit chose from the merged parent P2, which has none, so it judged by the
# page and demanded a Closing report the branch never wrote. Accepted at
# commit, refused at push, and no amend could fix it. Both layers now choose
# from the merge commit's own tree; the page path on P2 stays the fallback for
# a two-parent merge whose own record completes nothing. With the page shape
# and the record shape above this is DE15's third shape.
f10_mixed() { # f10_mixed <dir> <spec|chore> : a pre-record branch, then the record adopted on the trunk
  local d="$1" kind="$2"
  f10_fixture "$d" page
  if [[ "$kind" == "spec" ]]; then
    git -C "$d" checkout -q -b spec/0001-thing main
    printf '# Spec 0001: thing\n\nWork in progress.\n' > "$d/specs/0001-thing.md"
    printf 'work\n' >> "$d/src/a.txt"
    printf '| 0001 | Thing | BUILT | |\n' >> "$d/specs/STATUS.md"
    git -C "$d" add -A >/dev/null 2>&1
    SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "spec 0001 work, before the record existed" >/dev/null 2>&1
    git -C "$d" checkout -q main
  else
    f10_chore_branch "$d" chore/bump
  fi
  printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$d/.claude/status.json"
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "adopt the status record" >/dev/null 2>&1
}
F10M="$WORK/f10-mixed-spec"; f10_mixed "$F10M" spec
if git -C "$F10M" merge --no-ff spec/0001-thing -m "Merge spec/0001-thing" >"$WORK/f10m-merge.out" 2>&1; then
  bad "0167 F6 a (mixed, close): the pre-record branch's merge is refused at merge time" "it merged clean, so the case below tests nothing"
else
  ok "0167 F6 a (mixed, close): the pre-record branch's merge is refused at merge time"
fi
jq '.specs["0001"] = {"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}' "$F10M/.claude/status.json" > "$F10M/t" \
  && mv "$F10M/t" "$F10M/.claude/status.json"
sed 's/| 0001 | Thing | BUILT | |/| 0001 | Thing | CLOSED | |/' "$F10M/specs/STATUS.md" > "$F10M/t" && mv "$F10M/t" "$F10M/specs/STATUS.md"
git -C "$F10M" add -A >/dev/null 2>&1
if git -C "$F10M" commit -q --no-edit >"$WORK/f10m-complete.out" 2>&1 \
   && [[ "$(git -C "$F10M" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" == "3" ]]; then
  ok "0167 F6 b (mixed, close): completed as the refusal says, the two-parent merge is ACCEPTED by pre-commit"
else
  bad "0167 F6 b (mixed, close): completed as the refusal says, the two-parent merge is ACCEPTED by pre-commit" \
      "refused or not a merge: $(tr '\n' ' ' < "$WORK/f10m-complete.out" | cut -c1-200)"
fi
if f10_audits_clean "$F10M" "$WORK/f10m-audit.out"; then
  ok "0167 F6 c (mixed, close): and the audit ACCEPTS the same commit at push, by the merge commit's own record"
else
  bad "0167 F6 c (mixed, close): and the audit ACCEPTS the same commit at push, by the merge commit's own record" \
      "refused at push: $(tr '\n' ' ' < "$WORK/f10m-audit.out" | cut -c1-200)"
fi
F10MC="$WORK/f10-mixed-chore"; f10_mixed "$F10MC" chore
if git -C "$F10MC" merge --no-ff chore/bump -m "chore: merge" >"$WORK/f10mc-merge.out" 2>&1; then
  bad "0167 F6 d (mixed, chore): the pre-record chore merge with no completion is refused at merge time" "it merged clean"
else
  ok "0167 F6 d (mixed, chore): the pre-record chore merge with no completion is refused at merge time"
fi
# checkpoint writes the record AND the page (pre-commit refuses a record change
# without STATUS.md staged, SLH-STATUS-MISSING), so the chore completion carries
# its archive line too; 0157's page fallback on C already read that line, which
# makes this pair a CONTROL, green before and after, beside the close case above.
jq '.chores["CHORE-007"] = {"status":"done"}' "$F10MC/.claude/status.json" > "$F10MC/t" && mv "$F10MC/t" "$F10MC/.claude/status.json"
printf -- '- CHORE-007: DONE 2026-09-23. dependency bump\n' >> "$F10MC/specs/STATUS.md"
git -C "$F10MC" add -A >/dev/null 2>&1
if git -C "$F10MC" commit -q --no-edit >"$WORK/f10mc-complete.out" 2>&1; then
  ok "0167 F6 e (mixed, chore, control): completed with the record and the page on the trunk side, ACCEPTED by pre-commit"
else
  bad "0167 F6 e (mixed, chore, control): completed with the record and the page on the trunk side, ACCEPTED by pre-commit" \
      "refused: $(tr '\n' ' ' < "$WORK/f10mc-complete.out" | cut -c1-200)"
fi
if f10_audits_clean "$F10MC" "$WORK/f10mc-audit.out"; then
  ok "0167 F6 f (mixed, chore, control): and the audit ACCEPTS it at push"
else
  bad "0167 F6 f (mixed, chore, control): and the audit ACCEPTS it at push" "refused at push: $(tr '\n' ' ' < "$WORK/f10mc-audit.out" | cut -c1-200)"
fi
# THE CONTROLS on the mixed shape: completion on neither side still refused;
# and the page fallback kept: a pre-record branch that recorded its chore on
# its own page, merged with no record completion on the merge commit, reads
# as it always did at push (the page path on P2).
F10MN="$WORK/f10-mixed-neither"; f10_mixed "$F10MN" chore
SETLIST_SKIP_HOOKS=1 git -C "$F10MN" merge -q --no-ff chore/bump -m "chore: merge with no completion anywhere" >/dev/null 2>&1
if f10_audits_clean "$F10MN" "$WORK/f10mn-audit.out"; then
  bad "0167 F6 g (mixed): a merge with the completion on NEITHER side is still refused" \
      "passed: $(tr '\n' ' ' < "$WORK/f10mn-audit.out" | cut -c1-200)"
elif grep -q 'no recorded completion' "$WORK/f10mn-audit.out"; then
  ok "0167 F6 g (mixed): a merge with the completion on NEITHER side is still refused"
else
  bad "0167 F6 g (mixed): a merge with the completion on NEITHER side is still refused" \
      "refused for another reason: $(tr '\n' ' ' < "$WORK/f10mn-audit.out" | cut -c1-200)"
fi
F10MP="$WORK/f10-mixed-pagechore"; f10_fixture "$F10MP" page
git -C "$F10MP" checkout -q -b chore/bump main
printf 'bump\n' >> "$F10MP/src/a.txt"
printf -- '- CHORE-007: DONE 2026-09-23. bump, recorded on the branch page\n' >> "$F10MP/specs/STATUS.md"
git -C "$F10MP" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$F10MP" commit -qm "chore with its archive line" >/dev/null 2>&1
git -C "$F10MP" checkout -q main
printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$F10MP/.claude/status.json"
git -C "$F10MP" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$F10MP" commit -qm "adopt the status record" >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$F10MP" merge -q --no-ff chore/bump -m "chore: merge" >/dev/null 2>&1
if f10_audits_clean "$F10MP" "$WORK/f10mp-audit.out"; then
  ok "0167 F6 h (mixed): the page fallback is kept, a pre-record branch's page-recorded chore still reads clean at push"
else
  bad "0167 F6 h (mixed): the page fallback is kept, a pre-record branch's page-recorded chore still reads clean at push" \
      "newly refused: $(tr '\n' ' ' < "$WORK/f10mp-audit.out" | cut -c1-200)"
fi
# 0169's E-d (0167's E-e), homed in spec 0173, item 7: the page-chore shape F6 h reads at push, MADE
# WITH THE HOOKS. pre-merge-commit read only the index's record, which the trunk side carries and which
# completes nothing, and refused (SLH-CLOSES-NO-SPEC) the merge the audit accepts. It now keeps the
# audit's page fallback on the one merged head that carries no record. F6 d (the mixed chore with no
# completion anywhere, refused at merge) is the control and is unchanged.
F10MH="$WORK/f10-mixed-pagechore-hooks"; f10_fixture "$F10MH" page
git -C "$F10MH" checkout -q -b chore/bump main
printf 'bump\n' >> "$F10MH/src/a.txt"
printf -- '- CHORE-007: DONE 2026-09-23. bump, recorded on the branch page\n' >> "$F10MH/specs/STATUS.md"
git -C "$F10MH" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$F10MH" commit -qm "chore with its archive line" >/dev/null 2>&1
git -C "$F10MH" checkout -q main
printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$F10MH/.claude/status.json"
git -C "$F10MH" add -A >/dev/null 2>&1; SETLIST_SKIP_HOOKS=1 git -C "$F10MH" commit -qm "adopt the status record" >/dev/null 2>&1
if git -C "$F10MH" merge --no-ff chore/bump -m "chore: merge" >"$WORK/f10mh-merge.out" 2>&1 \
   && f10_audits_clean "$F10MH" "$WORK/f10mh-audit.out"; then
  ok "0173 record a (mixed, page chore): pre-merge-commit accepts the merge the audit accepts at push, one reading at both layers"
else
  bad "0173 record a (mixed, page chore): pre-merge-commit accepts the merge the audit accepts at push, one reading at both layers" \
      "merge: $(grep -o 'SLH-[A-Z-]*' "$WORK/f10mh-merge.out" | sort -u | tr '\n' ' '); audit: $(grep audited "$WORK/f10mh-audit.out" 2>/dev/null)"
fi
fi; shard_region_end
# <<< SHARD-END merge-completion-f10
# >>> SHARD-BEGIN jq-cat-hardening-0130 smoke=bins cost=16
if shard_region jq-cat-hardening-0130; then
# =============================================================================
# THE jq-AND-cat HARDENING AT KL6's JOIN (spec 0130, plugin 2.5.0), pinned RED
# FIRST on the shipped 2.4.1 bytes. Two findings of the 2.4.0 leg and the fix
# the public jq bullet had scheduled since 2.3.0:
#
#   F6   the advisory gates' jq probe (`printf '{}' | jq -e .`) checks STATUS
#        and not OUTPUT, so a jq that exits 0 printing nothing is classified
#        usable and close-gate and commit-gate emit ZERO BYTES; the scope hook
#        denies under a config code that names the file; the regrounding hook
#        emits the malformed object leg 4's F1 fixed for the nonzero shape.
#   F12  `INPUT=$(cat)` is the one load-bearing dependency no gate probes, and
#        every degradation arm is scoped behind `case "$INPUT" in *merge*)`, so
#        a PATH that loses cat suppresses every deny at once.
#   KL6  the git-hook layer never RUNS jq before reading .claude/sdd.json: a jq
#        that fails refuses under SLH-UNREADABLE-CONFIG (the config's code) and
#        a jq that prints nothing refuses under SLH-TRUNK-INVALID (the file
#        declared nothing wrong), both fail-closed and both pointing at a file
#        that is fine.
#
# Every fixture proves itself before it is used, on the suite's standing rule
# that a stub which accidentally works makes every case pass for the wrong
# reason. Every case has a healthy control beside it.
# =============================================================================

JC_QUIETJQ="$WORK/jc-quietjq-bin"; JC_NOCAT="$WORK/jc-nocat-bin"; JC_LOUDJQ="$WORK/jc-loudjq-bin"; JC_HEALTHY="$WORK/jc-healthy-bin"
jc_bin() { # jc_bin <dir> <omit-tool-or-empty> ; links the toolchain, git included, minus one tool
  rm -rf "$1"; mkdir -p "$1"
  local t p
  for t in bash sh git grep sed awk cat head tail od tr wc cut sort uniq printf env dirname basename \
           mkdir rm cp mv ls chmod date mktemp shasum find xargs comm diff jq; do
    [[ "$t" == "$2" ]] && continue
    p="$(command -v "$t" 2>/dev/null || true)"
    [[ -n "$p" ]] && setlist_wrap_bin "$p" "$1/$t"
  done
}
jc_bin "$JC_HEALTHY" ""
jc_bin "$JC_NOCAT" cat
jc_bin "$JC_QUIETJQ" jq; printf '#!/bin/sh\nexit 0\n' > "$JC_QUIETJQ/jq"; chmod +x "$JC_QUIETJQ/jq"
jc_bin "$JC_LOUDJQ" jq;  printf '#!/bin/sh\necho "jq: error while loading shared libraries: libonig.so.5" >&2\nexit 127\n' > "$JC_LOUDJQ/jq"; chmod +x "$JC_LOUDJQ/jq"
# The fixtures prove themselves.
if [[ "$(PATH="$JC_QUIETJQ" sh -c 'printf "{}" | jq -e . ; printf "|rc=%s" $?' 2>/dev/null)" == "|rc=0" ]]; then
  ok "0130 fixture: the quiet jq exits 0 and prints nothing, which is the shape F6 named"
else
  bad "0130 fixture: the quiet jq exits 0 and prints nothing" "the stub is not quiet: $(PATH="$JC_QUIETJQ" sh -c 'printf "{}" | jq -e . ; printf "|rc=%s" $?' 2>&1)"
fi
if PATH="$JC_NOCAT" sh -c 'command -v cat' >/dev/null 2>&1; then
  bad "0130 fixture: the no-cat PATH has no cat" "cat leaked into the fixture PATH"
else
  ok "0130 fixture: the no-cat PATH has no cat, and has jq"
fi
if PATH="$JC_LOUDJQ" jq --version >/dev/null 2>&1; then
  bad "0130 fixture: the loud jq fails" "the loud stub RUNS"
else
  ok "0130 fixture: the loud jq exits nonzero"
fi
jc_hook() { # jc_hook <bin> <hook-file> <project-dir> <payload>
  HOOK_OUT="$(printf '%s' "$4" | PATH="$1" CLAUDE_PROJECT_DIR="$3" bash "$2" 2>/dev/null)"
  HOOK_RC=$?
}

# --- F6 at the four advisory hooks: a quiet jq is a broken jq --------------
JCC="$WORK/jc-commit"; git_init "$JCC"; sdd_json "$JCC" true main true
JSC="$WORK/jc-scope"; git_init "$JSC"; sdd_json "$JSC" true main true; mkdir -p "$JSC/src"; printf 'x\n' > "$JSC/src/app.js"
mkdir -p "$JCC/specs" "$JSC/specs"; printf '# inv\n' > "$JCC/specs/STATUS.md"; printf '# inv\n' > "$JSC/specs/STATUS.md"

jc_hook "$JC_QUIETJQ" "$HOOKS/scope-hook.sh" "$JSC" "$(edit_payload "$JSC/src/app.js")"
expect_deny "0130 F6 c: the scope hook names SH-JQ-BROKEN under a quiet jq, not a config code" "SH-JQ-BROKEN"
# The literal path (advise_literal, no jq to build JSON with) carries the same
# channels as advise under design P (spec 0151): the reason in additionalContext,
# no systemMessage; and since spec 0181 no decision field and no decision reason,
# because a hook that answers the permission prompt pre-approves the write.
# Read with the suite's working jq, not the stub.
if printf '%s' "$HOOK_OUT" | jq -e '(.hookSpecificOutput.additionalContext // "" | contains("SH-JQ-BROKEN")) and (has("systemMessage") | not) and (.hookSpecificOutput | has("permissionDecision") or has("permissionDecisionReason") | not)' >/dev/null 2>&1; then
  ok "0151 P a: the scope hook's literal path carries the reason in additionalContext, answers no permission prompt, no systemMessage"
else
  bad "0151 P a: the scope hook's literal path carries the reason in additionalContext, answers no permission prompt, no systemMessage" "$(printf '%s' "$HOOK_OUT" | cut -c1-240)"
fi
jc_hook "$JC_QUIETJQ" "$HOOKS/regrounding-hook.sh" "$JCC" '{"source":"startup"}'
expect_context "0130 F6 d: the regrounding hook still emits valid JSON carrying the jq warning under a quiet jq" "jq is not usable"
# SPEC 0159 (h), review item 12 of the 2.9.0 external review: the product is Setlist, and the
# strings a hook puts in front of the model say so. Red first on the four "SDD re-grounding"
# strings. Not renamed, by 0156 decision 8: the code SH-SDD-SHAPE, the variable $SDD and SDD_JSON,
# the file name sdd.json, and the SDD-LIFECYCLE-STATES markers scripts/part.sh reads.
expect_context "0159 h a: the jq-less re-grounding literal names Setlist" "Setlist re-grounding (the read budget"
for jc_src in startup resume compact; do
  jc_hook "$JC_HEALTHY" "$HOOKS/regrounding-hook.sh" "$JCC" "{\"source\":\"$jc_src\"}"
  expect_context "0159 h b: the $jc_src re-grounding string names Setlist" "Setlist re-grounding ("
done
JC_SDD="$(grep -n 'SDD' "$HOOKS"/*.sh "$ROOT"/scripts/*.sh 2>/dev/null \
  | grep -vE 'SH-SDD-SHAPE|\$SDD|SDD_JSON|SDD-LIFECYCLE|sdd\.json' || true)"
if [[ -z "$JC_SDD" ]]; then
  ok "0159 h c: no string or comment in the stamped hooks or scripts/ says SDD outside the kept names"
else
  bad "0159 h c: no string or comment in the stamped hooks or scripts/ says SDD outside the kept names" "$(printf '%s' "$JC_SDD" | cut -c1-200 | head -8)"
fi

# --- F12: the input is read by the shell, and an empty input is reported ----
jc_hook "$JC_NOCAT" "$HOOKS/scope-hook.sh" "$JSC" "$(edit_payload "$JSC/src/app.js")"
expect_deny "0130 F12 c: the scope hook judges the trunk write on a PATH with no cat, not SH-NO-PATH" "SH-TRUNK-WRITE"
jc_hook "$JC_NOCAT" "$HOOKS/regrounding-hook.sh" "$JCC" '{"source":"startup"}'
expect_context "0130 F12 d: the regrounding hook delivers the pointer on a PATH with no cat" "STATUS.md"
jc_hook "$JC_HEALTHY" "$HOOKS/scope-hook.sh" "$JSC" ""
expect_deny "0130 F12 g: an EMPTY payload at the scope hook keeps SH-NO-PATH" "SH-NO-PATH"

# --- KL6: the git-hook layer probes jq by OUTPUT before it reads anything ---
jc_mk() { # jc_mk <name> -> an armed instance with a bare remote and a chore branch, prints its path
  local d="$WORK/jc-$1"
  rm -rf "$d" "$WORK/jc-$1.git"
  mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs" "$d/docs"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | thing | ACTIVE | |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n\n## Goal\n\nx\n' > "$d/specs/0001-thing.md"
  printf 'base\n' > "$d/docs/base.txt"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm base >/dev/null 2>&1
  git init -q --bare "$WORK/jc-$1.git"
  git -C "$d" remote add origin "$WORK/jc-$1.git"
  git -C "$d" checkout -q -b chore/001-dep
  printf 'dep\n' > "$d/docs/dep.txt"; git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm "chore: dep" >/dev/null 2>&1
  git -C "$d" checkout -q main
  printf '%s' "$d"
}
# GIT FOR WINDOWS STARTS A HOOK THROUGH A REAL INTERPRETER (spec 0179, 0168's E-f, the
# ninth fixture bin). git.exe reads the hook's shebang and starts the sh or env it finds
# on PATH as a Windows process, and a wrapper script is not one, so under a PATH of
# wrappers alone every hook failed "cannot spawn". Under MSYS or Cygwin only, the
# PATH git runs a hook under is a copy of the fixture bin without its sh, bash and
# env wrappers, with the directory of the real sh BEHIND it: git finds a real
# interpreter, and every tool the bin carries, the fixture jq included, still wins.
# git-receive-pack's directory goes behind it too: a local push starts it through the
# PATH there (it sits beside git.exe, /mingw64/bin on x64, /clangarm64/bin on ARM64).
# The precondition is asserted. Everywhere else the bin is used as it stands.
JC_GITSH=""
case "${OSTYPE:-}" in msys*|cygwin*) JC_GITSH=":$(dirname "$(command -v sh)"):$(dirname "$(command -v git-receive-pack)")" ;; esac
jc_gitpath() { # jc_gitpath <bin> -> the PATH git runs a hook under
  [[ -n "$JC_GITSH" ]] || { printf '%s' "$1"; return 0; }
  rm -rf "$1-git"; cp -R "$1" "$1-git"; rm -f "$1-git/sh" "$1-git/bash" "$1-git/env"
  printf '%s%s' "$1-git" "$JC_GITSH"
}
if [[ -n "$JC_GITSH" ]]; then
  JC_GP="$(jc_gitpath "$JC_LOUDJQ")"
  if [[ "$(PATH="$JC_GP"; command -v jq)" == "$JC_LOUDJQ-git/jq" ]] \
     && [[ "$(PATH="$JC_GP"; command -v sh)" != "$JC_LOUDJQ"* ]] \
     && [[ -n "$(PATH="$JC_GP"; command -v git-receive-pack)" ]]; then
    ok "0179 fixture: under MSYS the KL6 PATH finds the fixture jq first, and a real sh and git-receive-pack behind it"
  else
    bad "0179 fixture: under MSYS the KL6 PATH finds the fixture jq first, and a real sh and git-receive-pack behind it" "jq: $(PATH="$JC_GP"; command -v jq), sh: $(PATH="$JC_GP"; command -v sh)"
  fi
fi
jc_refused_by() { # jc_refused_by <name> <outfile> <code> after a NONZERO git status
  if grep -q "\[$3\]" "$2"; then ok "$1"; else bad "$1" "refused, but not by $3: $(tr '\n' ' ' < "$2" | cut -c1-240)"; fi
}
jc_layer() { # jc_layer <label> <bin> ; pre-commit, pre-merge-commit, pre-push and the audit under that PATH
  local label="$1" bin="$2" d
  local gp; gp="$(jc_gitpath "$bin")"
  d="$(jc_mk "$label")"
  printf 'n\n' > "$d/docs/n.txt"; git -C "$d" add -A >/dev/null 2>&1
  if PATH="$gp" git -C "$d" commit -qm docs >"$WORK/jc-$label.commit" 2>&1; then
    bad "0130 KL6 $label 1: pre-commit refuses under a $label jq" "it committed"
  else jc_refused_by "0130 KL6 $label 1: pre-commit refuses under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.commit" SLH-JQ-BROKEN; fi
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1; git -C "$d" clean -qfd >/dev/null 2>&1
  if PATH="$gp" git -C "$d" merge -q --no-ff -m "merge chore" chore/001-dep >"$WORK/jc-$label.merge" 2>&1; then
    bad "0130 KL6 $label 2: pre-merge-commit refuses under a $label jq" "it merged"
  else jc_refused_by "0130 KL6 $label 2: pre-merge-commit refuses under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.merge" SLH-JQ-BROKEN; fi
  git -C "$d" merge --abort >/dev/null 2>&1; git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  if PATH="$gp" git -C "$d" push -q origin main >"$WORK/jc-$label.push" 2>&1; then
    bad "0130 KL6 $label 3: pre-push refuses under a $label jq" "it pushed"
  else jc_refused_by "0130 KL6 $label 3: pre-push refuses under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.push" SLH-JQ-BROKEN; fi
  PATH="$bin" bash "$SCRIPTS/trunk-audit.sh" "$d" >"$WORK/jc-$label.audit" 2>&1
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    bad "0130 KL6 $label 4: the trunk audit stops under a $label jq" "it audited clean at exit 0"
  else jc_refused_by "0130 KL6 $label 4: the trunk audit stops under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.audit" SLH-JQ-BROKEN; fi
}
jc_layer loud  "$JC_LOUDJQ"
jc_layer quiet "$JC_QUIETJQ"
# CONTROL: the same instance under a healthy PATH commits, and the audit passes.
JCH="$(jc_mk healthy)"
printf 'n\n' > "$JCH/docs/n.txt"; git -C "$JCH" add -A >/dev/null 2>&1
JC_HEALTHY_GP="$(jc_gitpath "$JC_HEALTHY")"
if PATH="$JC_HEALTHY_GP" git -C "$JCH" commit -qm docs >"$WORK/jc-healthy.commit" 2>&1 \
   && PATH="$JC_HEALTHY" bash "$SCRIPTS/trunk-audit.sh" "$JCH" >"$WORK/jc-healthy.audit" 2>&1; then
  ok "0130 KL6 control: under a healthy jq the same instance commits and audits clean"
else
  bad "0130 KL6 control: under a healthy jq the same instance commits and audits clean" \
      "$(tr '\n' ' ' < "$WORK/jc-healthy.commit" | cut -c1-120) / $(tail -1 "$WORK/jc-healthy.audit" | cut -c1-120)"
fi
# THE INVERTED MESSAGE: once jq has been probed, a jq that then fails on the
# file points at the FILE. A malformed .claude/sdd.json under a healthy jq.
JCM="$(jc_mk malformed)"
printf '{"trunk":"main",\n' > "$JCM/.claude/sdd.json"
printf 'n\n' > "$JCM/docs/n.txt"; git -C "$JCM" add -A >/dev/null 2>&1
if PATH="$JC_HEALTHY_GP" git -C "$JCM" commit -qm docs >"$WORK/jc-malformed.commit" 2>&1; then
  bad "0130 KL6 5: a malformed .claude/sdd.json under a healthy jq is refused" "it committed"
elif grep -q '\[SLH-UNREADABLE-CONFIG\]' "$WORK/jc-malformed.commit" \
     && grep -q 'jq \. \.claude/sdd\.json' "$WORK/jc-malformed.commit" \
     && ! grep -q 'LIKELIER CAUSE IS THE TOOLCHAIN' "$WORK/jc-malformed.commit"; then
  ok "0130 KL6 5: a malformed .claude/sdd.json under a probed-healthy jq refuses with SLH-UNREADABLE-CONFIG pointing at the FILE"
else
  bad "0130 KL6 5: a malformed .claude/sdd.json under a probed-healthy jq refuses with SLH-UNREADABLE-CONFIG pointing at the FILE" \
      "$(tr '\n' ' ' < "$WORK/jc-malformed.commit" | cut -c1-300)"
fi

fi; shard_region_end
# <<< SHARD-END jq-cat-hardening-0130
# >>> SHARD-BEGIN refresh-silent-jq-0130 smoke=bins cost=4
if shard_region refresh-silent-jq-0130; then
# =============================================================================
# THE REFRESH SCRIPT UNDER A jq THAT EXITS 0 PRINTING NOTHING (the 2.5.0 leg,
# fix round 1). The one carrier of the "JQ PRESENT IS NOT JQ USABLE" rule that
# located jq and then read with it: the recorded version read as empty, the
# downgrade guard stood down, and the version write truncated .claude/sdd.json
# to ZERO BYTES while the summary reported success. Pinned RED on the 2.5.0
# candidate first: an instance recording a NEWER plugin than the tree, refreshed
# under the quiet jq, must be REFUSED with its config byte-identical.
# =============================================================================
RSJ_BIN="$WORK/rsj-bin"; rm -rf "$RSJ_BIN"; mkdir -p "$RSJ_BIN"
for rsj_t in bash sh git grep sed awk cat head tail od tr wc cut sort uniq printf env dirname basename mkdir rm cp mv ls chmod date mktemp diff cmp; do
  rsj_p="$(command -v "$rsj_t" 2>/dev/null || true)"; [[ -n "$rsj_p" ]] && setlist_wrap_bin "$rsj_p" "$RSJ_BIN/$rsj_t"
done
printf '#!/bin/sh\nexit 0\n' > "$RSJ_BIN/jq"; chmod +x "$RSJ_BIN/jq"
RSJ="$WORK/rsj-inst"; instance_fixture "$RSJ" 9.9.9 current
RSJ_BEFORE="$(cat "$RSJ/.claude/sdd.json")"
# control: a healthy jq refuses the backwards move and writes nothing
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$RSJ"
if [[ "$SCRIPT_RC" -ne 0 ]] && printf '%s' "$SCRIPT_OUT" | grep -q "BACKWARDS" && [[ "$(cat "$RSJ/.claude/sdd.json")" == "$RSJ_BEFORE" ]]; then
  ok "refresh silent-jq control: a healthy jq refuses the backwards move and leaves sdd.json byte-identical"
else
  bad "refresh silent-jq control: a healthy jq refuses the backwards move and leaves sdd.json byte-identical" "rc=$SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tr '\n' ' ' | cut -c1-200)"
fi
SCRIPT_OUT="$(PATH="$RSJ_BIN" bash "$SCRIPTS/refresh-instance.sh" --apply "$RSJ" 2>&1)"; SCRIPT_RC=$?
if [[ "$SCRIPT_RC" -ne 0 ]] && printf '%s' "$SCRIPT_OUT" | grep -q "does not work here"; then
  ok "refresh silent-jq a: a jq that exits 0 printing nothing is REFUSED before anything is read, naming jq"
else
  bad "refresh silent-jq a: a jq that exits 0 printing nothing is REFUSED before anything is read, naming jq" \
      "rc=$SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tr '\n' ' ' | cut -c1-240). On the 2.5.0 candidate this ran to completion and reported success."
fi
if [[ "$(cat "$RSJ/.claude/sdd.json")" == "$RSJ_BEFORE" ]]; then
  ok "refresh silent-jq b: .claude/sdd.json is byte-identical after the refusal ($(printf '%s' "$RSJ_BEFORE" | wc -c | tr -d ' ') bytes)"
else
  bad "refresh silent-jq b: .claude/sdd.json is byte-identical after the refusal" \
      "it is now $(wc -c < "$RSJ/.claude/sdd.json" | tr -d ' ') bytes; on the 2.5.0 candidate the version write truncated it to zero"
fi
# THE SECOND HALF: a jq that is healthy at the probe and writes NOTHING at the
# version write (an OOM kill between the two, modelled by a jq that answers the
# probe and nothing else) must leave the old config in place.
printf '#!/bin/sh\ncase "$*" in *probe*) printf x ;; *-e*) exit 0 ;; *) exit 0 ;; esac\n' > "$RSJ_BIN/jq"; chmod +x "$RSJ_BIN/jq"
RSJ2="$WORK/rsj-inst2"; instance_fixture "$RSJ2" 1.0.0 current
RSJ2_BEFORE="$(cat "$RSJ2/.claude/sdd.json")"
SCRIPT_OUT="$(PATH="$RSJ_BIN" bash "$SCRIPTS/refresh-instance.sh" --apply "$RSJ2" 2>&1)"; SCRIPT_RC=$?
if [[ "$(cat "$RSJ2/.claude/sdd.json")" == "$RSJ2_BEFORE" ]]; then
  ok "refresh silent-jq c: a version write that produces no JSON leaves .claude/sdd.json untouched (rc=$SCRIPT_RC)"
else
  bad "refresh silent-jq c: a version write that produces no JSON leaves .claude/sdd.json untouched" \
      "sdd.json changed to $(wc -c < "$RSJ2/.claude/sdd.json" | tr -d ' ') bytes; rc=$SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tr '\n' ' ' | cut -c1-200)"
fi
fi; shard_region_end
# <<< SHARD-END refresh-silent-jq-0130
