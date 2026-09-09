#!/usr/bin/env bash
# test/suite/15-rc2-f10-jq-hardening.sh: shard 15 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# >>> SHARD-BEGIN rc2-config-blind cost=16
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

# --- e. the advisory commit gate under color.ui=always -----------------------
E="$WORK/rc2-e"; rm -rf "$E"; git_init "$E"; sdd_json "$E"; git -C "$E" config color.ui always
printf '%s\n' "$RC2_SECRET" > "$E/config.txt"; git -C "$E" add config.txt
run_hook "$HOOKS/commit-gate.sh" "$E" "$(bash_payload 'git commit -m "config"')"
expect_deny "RC2 e: the advisory commit gate denies a secret under color.ui=always" "secret-shaped"
git -C "$E" reset -q; rm -f "$E/config.txt"
printf 'clean\n' > "$E/clean.md"; git -C "$E" add clean.md
run_hook "$HOOKS/commit-gate.sh" "$E" "$(bash_payload 'git commit -m "clean"')"
expect_allow "RC2 e twin: the advisory commit gate allows clean content under color.ui=always"

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

# --- h. git DIES at the render under the advisory gate ---------------------------
H="$WORK/rc2-h"; rm -rf "$H"; git_init "$H"; sdd_json "$H"; rc2_break_render "$H"
printf 'clean\n' > "$H/clean.md"; git -C "$H" add clean.md
run_hook "$HOOKS/commit-gate.sh" "$H" "$(bash_payload 'git commit -m "clean"')"
RC2H_CODE="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.code // "<absent>"' 2>/dev/null)"
if [[ "$RC2H_CODE" == "CM-NO-GIT" ]]; then
  ok "RC2 h: the advisory commit gate reports CM-NO-GIT when git cannot render the staged diff"
else
  bad "RC2 h: the advisory commit gate reports CM-NO-GIT when git cannot render the staged diff" \
      "code=[$RC2H_CODE]: the probe saw git run, the render died, and the gate read empty as clean"
fi

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

# --- n. the same driver at the advisory gate's two sites -------------------------
N="$WORK/rc2-n"; rm -rf "$N"; git_init "$N"; sdd_json "$N"; mkdir -p "$N/specs"
printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n' > "$N/specs/0001-thing.md"
printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | thing | ACTIVE | |\n' > "$N/specs/STATUS.md"
git -C "$N" add -A >/dev/null 2>&1; git -C "$N" commit -qm "spec" >/dev/null 2>&1
git -C "$N" config diff.external false
printf '# Spec 0001 - thing\n\nStatus: BUILT\n' > "$N/specs/0001-thing.md"; git -C "$N" add specs/0001-thing.md
run_hook "$HOOKS/commit-gate.sh" "$N" "$(bash_payload 'git commit -m "flip"')"
expect_deny "RC2 n: the advisory gate ignores diff.external and still demands STATUS.md for a Status flip" "STATUS.md"
git -C "$N" reset -q; git -C "$N" checkout -q -- specs/0001-thing.md
printf '%s\n' "$RC2_SECRET" > "$N/config.txt"; git -C "$N" add config.txt
run_hook "$HOOKS/commit-gate.sh" "$N" "$(bash_payload 'git commit -m "config"')"
expect_deny "RC2 n2: the advisory gate ignores diff.external and still sees a secret" "secret-shaped"

# --- o. prefix settings, measured harmless and pinned as such ---------------------
O="$(rc2_mk o)"; git -C "$O" config diff.noprefix true; git -C "$O" config diff.mnemonicPrefix true
if rc2_commit "$O" docs/conf.txt "$RC2_SECRET" "$WORK/rc2o.out"; then
  bad "RC2 o: prefix settings do not blind the positional filter (measured; no prefix flag is pinned)" "it committed clean under diff.noprefix and diff.mnemonicPrefix"
else rc2_refused "RC2 o: prefix settings do not blind the positional filter (measured; no prefix flag is pinned)" "$WORK/rc2o.out" SLH-SECRET; fi

fi; shard_region_end
# <<< SHARD-END rc2-config-blind
# >>> SHARD-BEGIN merge-completion-f10 cost=4
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
if bash "$SCRIPTS/trunk-audit.sh" "$F10" >"$WORK/f10-audit.out" 2>&1; then
  bad "F10-2026 c: KNOWN-HOLE, the trunk audit then REFUSES the same commit at push" \
      "the audit passed it: the two layers now agree, so the bullet, its ledger row and this region leave together"
elif grep -q 'no recorded completion' "$WORK/f10-audit.out"; then
  ok "F10-2026 c: KNOWN-HOLE, the trunk audit then REFUSES the same commit at push"
else
  bad "F10-2026 c: KNOWN-HOLE, the trunk audit then REFUSES the same commit at push" "refused for another reason: $(tr '\n' ' ' < "$WORK/f10-audit.out" | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END merge-completion-f10
# >>> SHARD-BEGIN jq-cat-hardening-0130 cost=5
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
    [[ -n "$p" ]] && ln -sf "$p" "$1/$t"
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
JCL="$WORK/jc-close"; close_fixture "$JCL" no no answered yes no true   # healthy verdict: a deny (no Closing report)
JCC="$WORK/jc-commit"; git_init "$JCC"; sdd_json "$JCC" true main true
JSC="$WORK/jc-scope"; git_init "$JSC"; sdd_json "$JSC" true main true; mkdir -p "$JSC/src"; printf 'x\n' > "$JSC/src/app.js"
mkdir -p "$JCC/specs" "$JSC/specs"; printf '# inv\n' > "$JCC/specs/STATUS.md"; printf '# inv\n' > "$JSC/specs/STATUS.md"

jc_hook "$JC_HEALTHY" "$HOOKS/close-gate.sh" "$JCL" "$(bash_payload "$MERGE_CMD")"
expect_deny "0130 F6 control: the close gate denies the unauthored close under a healthy jq" "Closing report"
jc_hook "$JC_QUIETJQ" "$HOOKS/close-gate.sh" "$JCL" "$(bash_payload "$MERGE_CMD")"
expect_deny "0130 F6 a: the close gate names CG-JQ-BROKEN under a jq that exits 0 printing nothing" "CG-JQ-BROKEN"
jc_hook "$JC_QUIETJQ" "$HOOKS/commit-gate.sh" "$JCC" "$(bash_payload 'git commit -m "clean"')"
expect_deny "0130 F6 b: the commit gate names CM-JQ-BROKEN under a quiet jq" "CM-JQ-BROKEN"
jc_hook "$JC_QUIETJQ" "$HOOKS/scope-hook.sh" "$JSC" "$(edit_payload "$JSC/src/app.js")"
expect_deny "0130 F6 c: the scope hook names SH-JQ-BROKEN under a quiet jq, not a config code" "SH-JQ-BROKEN"
jc_hook "$JC_QUIETJQ" "$HOOKS/regrounding-hook.sh" "$JCC" '{"source":"startup"}'
expect_context "0130 F6 d: the regrounding hook still emits valid JSON carrying the jq warning under a quiet jq" "jq is not usable"
# The controls that keep a through d honest: a payload the gate does not govern stays silent.
jc_hook "$JC_QUIETJQ" "$HOOKS/close-gate.sh" "$JCL" "$(bash_payload 'ls -la')"
expect_allow "0130 F6 e: under a quiet jq a command the close gate does not govern is still silent"
jc_hook "$JC_QUIETJQ" "$HOOKS/commit-gate.sh" "$JCC" "$(bash_payload 'apt-get install -y jq')"
expect_allow "0130 F6 f: under a quiet jq the command that repairs jq is not gated"

# --- F12: the input is read by the shell, and an empty input is reported ----
jc_hook "$JC_NOCAT" "$HOOKS/close-gate.sh" "$JCL" "$(bash_payload "$MERGE_CMD")"
expect_deny "0130 F12 a: the close gate judges the merge on a PATH with no cat" "Closing report"
jc_hook "$JC_NOCAT" "$HOOKS/commit-gate.sh" "$JCC" "$(bash_payload 'git add -A && git commit -m "x"')"
expect_deny "0130 F12 b: the commit gate judges the compound commit on a PATH with no cat" "one step"
jc_hook "$JC_NOCAT" "$HOOKS/scope-hook.sh" "$JSC" "$(edit_payload "$JSC/src/app.js")"
expect_deny "0130 F12 c: the scope hook judges the trunk write on a PATH with no cat, not SH-NO-PATH" "SH-TRUNK-WRITE"
jc_hook "$JC_NOCAT" "$HOOKS/regrounding-hook.sh" "$JCC" '{"source":"startup"}'
expect_context "0130 F12 d: the regrounding hook delivers the pointer on a PATH with no cat" "STATUS.md"
jc_hook "$JC_HEALTHY" "$HOOKS/close-gate.sh" "$JCL" ""
expect_deny "0130 F12 e: an EMPTY payload at the close gate is reported as CG-NO-INPUT, not exit 0 in silence" "CG-NO-INPUT"
jc_hook "$JC_HEALTHY" "$HOOKS/commit-gate.sh" "$JCC" ""
expect_deny "0130 F12 f: an EMPTY payload at the commit gate is reported as CM-NO-INPUT" "CM-NO-INPUT"
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
jc_refused_by() { # jc_refused_by <name> <outfile> <code> after a NONZERO git status
  if grep -q "\[$3\]" "$2"; then ok "$1"; else bad "$1" "refused, but not by $3: $(tr '\n' ' ' < "$2" | cut -c1-240)"; fi
}
jc_layer() { # jc_layer <label> <bin> ; pre-commit, pre-merge-commit, pre-push and the audit under that PATH
  local label="$1" bin="$2" d
  d="$(jc_mk "$label")"
  printf 'n\n' > "$d/docs/n.txt"; git -C "$d" add -A >/dev/null 2>&1
  if PATH="$bin" git -C "$d" commit -qm docs >"$WORK/jc-$label.commit" 2>&1; then
    bad "0130 KL6 $label 1: pre-commit refuses under a $label jq" "it committed"
  else jc_refused_by "0130 KL6 $label 1: pre-commit refuses under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.commit" SLH-JQ-BROKEN; fi
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1; git -C "$d" clean -qfd >/dev/null 2>&1
  if PATH="$bin" git -C "$d" merge -q --no-ff -m "merge chore" chore/001-dep >"$WORK/jc-$label.merge" 2>&1; then
    bad "0130 KL6 $label 2: pre-merge-commit refuses under a $label jq" "it merged"
  else jc_refused_by "0130 KL6 $label 2: pre-merge-commit refuses under a $label jq, naming SLH-JQ-BROKEN" "$WORK/jc-$label.merge" SLH-JQ-BROKEN; fi
  git -C "$d" merge --abort >/dev/null 2>&1; git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  if PATH="$bin" git -C "$d" push -q origin main >"$WORK/jc-$label.push" 2>&1; then
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
if PATH="$JC_HEALTHY" git -C "$JCH" commit -qm docs >"$WORK/jc-healthy.commit" 2>&1 \
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
if PATH="$JC_HEALTHY" git -C "$JCM" commit -qm docs >"$WORK/jc-malformed.commit" 2>&1; then
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
# >>> SHARD-BEGIN refresh-silent-jq-0130 cost=1
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
  rsj_p="$(command -v "$rsj_t" 2>/dev/null || true)"; [[ -n "$rsj_p" ]] && ln -sf "$rsj_p" "$RSJ_BIN/$rsj_t"
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
