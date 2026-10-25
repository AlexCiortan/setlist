# Shard 23: the board (spec 0201). Sourced by test/run-tests.sh.
#
# =============================================================================
# THE BOARD (spec 0201; G3 to G6, G10, G11 of the session-zero rebuild). The
# trunk is the board: scripts/board.sh reads the trunk's status record and spec
# headers, the remote's spec/ branches and their own spec files, and prints every
# spec by state with its driver, its Owns: set, its branch and its age, and the
# collisions it can see. It REFUSES NOTHING, so these cases assert a report and an
# exit status of 0, never a verdict. No case touches a network: every remote is a
# bare repository on disk, named by its path. Every instance is built here from
# the real stamp, so each region depends on nothing outside this file.
# =============================================================================

# Helpers, defined outside every region so a region skipped by the independence
# run takes nothing another region needs with it.
bd_instance() { # bd_instance <dir> : a stamped instance with one commit on main
  mkdir -p "$1"
  printf 'project_name=Board\nstack=bash\nworking_mode=review-only\nui=no\nplanning_model=\nexecution_model=\ndesign_surface=no\nmode=new\n' > "$1.answers"
  bash "$ROOT/scripts/stamp.sh" "$1.answers" "$1" > "$1.stamp.log" 2>&1 || return 1
  git -C "$1" init -q -b main 2>/dev/null || { git -C "$1" init -q && git -C "$1" checkout -q -b main; } || return 1
  bd_config "$1" a@x.test
  git -C "$1" add -A && git -C "$1" commit -qm "chore: stamp"
}
bd_config() { # bd_config <clone> <email> : the identity and the armed hooks
  git -C "$1" config user.email "$2" && git -C "$1" config user.name "${2%%@*}" \
    && git -C "$1" config core.hooksPath .githooks && git -C "$1" config merge.ff false
}
bd_cut() { # bd_cut <clone> <num> <slug> <STATE> <driver> : the spec file, its row and its record token
  printf '# Spec %s - %s\n\nStatus: %s\nTier: full\nSpec-hash:\nDriver: %s\nDepends on: none\n\n## Goal\nx\n\n## Closing report\n' "$2" "$3" "$4" "$5" > "$1/specs/$2-$3.md"
  printf '| %s | %s | %s | cut |\n' "$2" "$3" "$4" >> "$1/specs/STATUS.md"
  jq --arg n "$2" --arg st "$(printf '%s' "$4" | tr '[:upper:]' '[:lower:]')" '.specs[$n] = {"status": $st}' \
    "$1/.claude/status.json" > "$1/.claude/status.json.new" && mv "$1/.claude/status.json.new" "$1/.claude/status.json"
}
bd_owns() { # bd_owns <clone> <spec-file> <role-file> : an Owns: line in the header, and the file
  awk -v f="$3" '/^Depends on:/ { print; print "Owns: " f; next } { print }' "$1/$2" > "$1/$2.new" && mv "$1/$2.new" "$1/$2"
  mkdir -p "$1/$(dirname "$3")" && printf '%s\n' "$2" >> "$1/$3"
}
bd_commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
bd_bare() { # bd_bare <path> : a bare remote whose HEAD names main, whatever init.defaultBranch
  # says on this machine (unset on a CI runner, HEAD names master and a clone of
  # the remote then checks out nothing)
  git init -q --bare "$1" && git --git-dir="$1" symbolic-ref HEAD refs/heads/main
}

# >>> SHARD-BEGIN board-0201 cost=1
if shard_region board-0201; then

BD="$WORK/board-0201"
mkdir -p "$BD"
BD_OK=1
bd_instance "$BD/inst" || BD_OK=0
bd_bare "$BD/remote.git" || BD_OK=0
git -C "$BD/inst" remote add origin "$BD/remote.git" || BD_OK=0
# 0002 ACTIVE on the trunk with an empty branch, Owns appended on the branch;
# 0003 ACTIVE on the trunk with no branch; 0005 BUILT; 0004 on a branch alone.
bd_cut "$BD/inst" 0002 alpha ACTIVE a@x.test
bd_cut "$BD/inst" 0003 gamma ACTIVE c@x.test
bd_cut "$BD/inst" 0005 epsilon BUILT a@x.test
bd_commit "$BD/inst" "docs: cut and flip on the trunk" || BD_OK=0
git -C "$BD/inst" branch spec/0002-alpha && git -C "$BD/inst" branch spec/0005-epsilon || BD_OK=0
git -C "$BD/inst" push -q --atomic origin main spec/0002-alpha spec/0005-epsilon > "$BD/push1.log" 2>&1 || BD_OK=0
git clone -q "$BD/remote.git" "$BD/lag" 2>/dev/null && bd_config "$BD/lag" l@x.test || BD_OK=0
git -C "$BD/inst" checkout -q spec/0002-alpha
bd_owns "$BD/inst" specs/0002-alpha.md src/shared.js
bd_commit "$BD/inst" "feat(0002): shared" && git -C "$BD/inst" push -q origin spec/0002-alpha > "$BD/push2.log" 2>&1 || BD_OK=0
git -C "$BD/inst" checkout -q -b spec/0004-delta main
bd_cut "$BD/inst" 0004 delta ACTIVE "d\"x@x.test"
bd_owns "$BD/inst" specs/0004-delta.md src/shared.js
bd_commit "$BD/inst" "feat(0004): on a branch alone" && git -C "$BD/inst" push -q origin spec/0004-delta > "$BD/push3.log" 2>&1 || BD_OK=0
git -C "$BD/inst" checkout -q main

BD_RC=0; bash "$ROOT/scripts/board.sh" --dir "$BD/lag" > "$BD/board.out" 2>&1 || BD_RC=$?

# a. Every spec by state, with its driver, its branch and its Owns: set (the
#    branch's header joined to the trunk's), read from a clone that never fetched
#    the branches it reports.
if [[ "$BD_OK" -eq 1 && "$BD_RC" -eq 0 ]] \
   && grep -qx 'ACTIVE' "$BD/board.out" && grep -qx 'BUILT' "$BD/board.out" \
   && grep -qE '^  0002-alpha  driver a@x\.test  branch spec/0002-alpha, last commit under an hour ago$' "$BD/board.out" \
   && grep -A1 '^  0002-alpha ' "$BD/board.out" | grep -qx '      owns: src/shared.js' \
   && grep -q 'read live (git ls-remote)' "$BD/board.out"; then
  ok "0201 board a: every spec by state with its driver, its branch and the Owns: set its branch appended, read live from a clone that never fetched them"
else
  bad "0201 board a: every spec by state with its driver, its branch and the Owns: set its branch appended, read live from a clone that never fetched them" \
      "setup=$BD_OK rc=$BD_RC out=$(tr '\n' '|' < "$BD/board.out" | cut -c1-600)"
fi

# b. Each collision it can see, by name, and the exit status is 0 regardless.
BD_MISS=""
grep -q '^  - overlap: spec 0002-alpha (driver a@x.test, branch spec/0002-alpha) and spec 0004-delta (driver d?x@x.test, branch spec/0004-delta) both declare src/shared.js' "$BD/board.out" || BD_MISS="$BD_MISS overlap"
grep -q '^  - not on the trunk: spec 0004-delta ' "$BD/board.out" || BD_MISS="$BD_MISS not-on-trunk"
grep -q '^  - no branch: spec 0003-gamma (driver c@x.test) is ACTIVE on the trunk with no spec branch on the remote' "$BD/board.out" || BD_MISS="$BD_MISS no-branch"
grep -q '^  - waiting to merge: spec 0005-epsilon ' "$BD/board.out" || BD_MISS="$BD_MISS waiting"
grep -q '^  - number:' "$BD/board.out" && BD_MISS="$BD_MISS spurious-number"
if [[ "$BD_RC" -eq 0 && -z "$BD_MISS" ]]; then
  ok "0201 board b: the overlap, the branch not on the trunk, the ACTIVE spec with no branch and the BUILT spec are each named, a quote in a handle shown as ?, and the board exits 0"
else
  bad "0201 board b: the overlap, the branch not on the trunk, the ACTIVE spec with no branch and the BUILT spec are each named, a quote in a handle shown as ?, and the board exits 0" \
      "rc=$BD_RC missing=[${BD_MISS# }]"
fi

# c. The per-driver count is a count: two drivers with one ACTIVE spec each.
if grep -qx '  a@x.test: 1' "$BD/board.out" && grep -qx '  c@x.test: 1' "$BD/board.out" && grep -q 'a count, never a limit' "$BD/board.out"; then
  ok "0201 board c: the per-driver count of ACTIVE specs is printed, as a count"
else
  bad "0201 board c: the per-driver count of ACTIVE specs is printed, as a count" "$(sed -n '/ACTIVE per driver/,/^$/p' "$BD/board.out" | tr '\n' '|')"
fi

# d. --offline reads the last fetch alone and names its age; a branch pushed
#    after that fetch is absent from it and present in the live reading.
git -C "$BD/lag" fetch -q origin 2>/dev/null
git -C "$BD/inst" branch spec/0006-zeta main && git -C "$BD/inst" push -q origin spec/0006-zeta > "$BD/push4.log" 2>&1
BD_OFF_RC=0; bash "$ROOT/scripts/board.sh" --dir "$BD/lag" --offline > "$BD/off.out" 2>&1 || BD_OFF_RC=$?
bash "$ROOT/scripts/board.sh" --dir "$BD/lag" > "$BD/live2.out" 2>&1
if [[ "$BD_OFF_RC" -eq 0 ]] && grep -qE 'read from the last fetch, under an hour old \(--offline\)' "$BD/off.out" \
   && ! grep -q 'spec/0006-zeta' "$BD/off.out" && grep -q 'not on the trunk: spec 0006-zeta' "$BD/live2.out"; then
  ok "0201 board d: --offline reads the last fetch and names its age, and misses the branch pushed after it, which the live read shows"
else
  bad "0201 board d: --offline reads the last fetch and names its age, and misses the branch pushed after it, which the live read shows" \
      "rc=$BD_OFF_RC off=$(head -n3 "$BD/off.out" | tr '\n' '|') zeta-off=$(grep -c 'spec/0006-zeta' "$BD/off.out") zeta-live=$(grep -c '0006-zeta' "$BD/live2.out")"
fi

# e. It cannot read: outside a repository, or without .claude/sdd.json, it exits
#    2 and names why; a clone with no remote reads its own trunk and says so.
mkdir -p "$BD/plain" "$BD/bare-repo"
git -C "$BD/bare-repo" init -q 2>/dev/null
BD_E1=0; bash "$ROOT/scripts/board.sh" --dir "$BD/plain" > "$BD/e1.out" 2>&1 || BD_E1=$?
BD_E2=0; bash "$ROOT/scripts/board.sh" --dir "$BD/bare-repo" > "$BD/e2.out" 2>&1 || BD_E2=$?
git clone -q "$BD/inst" "$BD/solo" 2>/dev/null && git -C "$BD/solo" remote remove origin 2>/dev/null
BD_E3=0; bash "$ROOT/scripts/board.sh" --dir "$BD/solo" > "$BD/e3.out" 2>&1 || BD_E3=$?
if [[ "$BD_E1" -eq 2 && "$BD_E2" -eq 2 && "$BD_E3" -eq 0 ]] && grep -q 'is not inside a git repository' "$BD/e1.out" \
   && grep -q 'has no .claude/sdd.json' "$BD/e2.out" && grep -q '^remote: none configured' "$BD/e3.out"; then
  ok "0201 board e: no repository or no sdd.json exits 2 with the reason; a clone with no remote reads its own trunk and says no other clone can see it"
else
  bad "0201 board e: no repository or no sdd.json exits 2 with the reason; a clone with no remote reads its own trunk and says no other clone can see it" \
      "plain=$BD_E1 nosdd=$BD_E2 solo=$BD_E3 $(head -n2 "$BD/e3.out" | tr '\n' '|')"
fi

fi; shard_region_end
# <<< SHARD-END board-0201

# >>> SHARD-BEGIN board-next-0201 cost=1
if shard_region board-next-0201; then

BN="$WORK/board-next-0201"
mkdir -p "$BN"
BN_OK=1
bd_instance "$BN/inst" || BN_OK=0
bd_bare "$BN/remote.git" && git -C "$BN/inst" remote add origin "$BN/remote.git" || BN_OK=0
bd_cut "$BN/inst" 0001 one QUEUED ""
bd_commit "$BN/inst" "docs(0001): cut" && git -C "$BN/inst" push -q origin main > "$BN/p1.log" 2>&1 || BN_OK=0
BN_N1="$(bash "$ROOT/scripts/board.sh" --dir "$BN/inst" --next 2>/dev/null)"
# a teammate's branch on the remote carries 0007, with no spec on the trunk
git -C "$BN/inst" checkout -q -b spec/0007-far main && bd_cut "$BN/inst" 0007 far ACTIVE b@x.test \
  && bd_commit "$BN/inst" "docs(0007): far" && git -C "$BN/inst" push -q origin spec/0007-far > "$BN/p2.log" 2>&1 || BN_OK=0
git -C "$BN/inst" checkout -q main
BN_N2="$(bash "$ROOT/scripts/board.sh" --dir "$BN/inst" --next 2>/dev/null)"
# a cut on this clone's trunk, not pushed, at 0009
bd_cut "$BN/inst" 0009 local QUEUED "" && bd_commit "$BN/inst" "docs(0009): local cut" || BN_OK=0
BN_N3="$(bash "$ROOT/scripts/board.sh" --dir "$BN/inst" --next 2>/dev/null)"
if [[ "$BN_OK" -eq 1 && "$BN_N1" == "0002" && "$BN_N2" == "0008" && "$BN_N3" == "0010" ]]; then
  ok "0201 next number: --next is the highest on the trunk (0002), then counts a remote spec branch (0008), then this clone's unpushed cut (0010)"
else
  bad "0201 next number: --next is the highest on the trunk (0002), then counts a remote spec branch (0008), then this clone's unpushed cut (0010)" \
      "setup=$BN_OK next=$BN_N1,$BN_N2,$BN_N3"
fi
# A spec file name with a non-ASCII byte is a spec like any other (spec 0205, the 2.14.0 leg's F6): git
# quotes such a path by default, and the board read the quoted form, dropped it, and offered its number
# again. A cut at 0011 named in UTF-8 makes --next 0012. Two spec/ branches with no number (F11) name
# no number collision.
bd_cut "$BN/inst" 0011 "caf$(printf '\303\251')" QUEUED "" && bd_commit "$BN/inst" "docs(0011): a non-ASCII slug" || BN_OK=0
BN_N4="$(bash "$ROOT/scripts/board.sh" --dir "$BN/inst" --next 2>/dev/null)"
git -C "$BN/inst" push -q origin main > "$BN/p4.log" 2>&1 || BN_OK=0
git -C "$BN/inst" branch spec/x-y && git -C "$BN/inst" branch spec/z-w && git -C "$BN/inst" push -q origin spec/x-y spec/z-w > "$BN/p3.log" 2>&1 || BN_OK=0
BN_B="$(bash "$ROOT/scripts/board.sh" --dir "$BN/inst" 2>&1)"
if [[ "$BN_OK" -eq 1 && "$BN_N4" == "0012" ]] && printf '%s' "$BN_B" | grep -q '0011' \
   && ! printf '%s' "$BN_B" | grep -q 'number: - is claimed twice'; then
  ok "0205 F6 F11 board: a non-ASCII spec name is read (--next 0012, the spec listed), and spec/ branches with no number name no number collision"
else
  bad "0205 F6 F11 board: a non-ASCII spec name is read (--next 0012, the spec listed), and spec/ branches with no number name no number collision" \
      "setup=$BN_OK next=$BN_N4 listed=$(printf '%s' "$BN_B" | grep -c '0011') dash-collisions=$(printf '%s' "$BN_B" | grep -c 'number: - is claimed twice')"
fi

fi; shard_region_end
# <<< SHARD-END board-next-0201

# >>> SHARD-BEGIN board-hook-0201 cost=1
if shard_region board-hook-0201; then

# The re-grounding hook names the remote's other spec branches from the LAST
# FETCH, with that fetch's age, and makes no network call: the remote's URL is
# pointed at a path that does not exist before the hook runs, and the names still
# come from the remote-tracking refs. The active spec's own branch is not named.
BH="$WORK/board-hook-0201"
mkdir -p "$BH"
BH_OK=1
bd_instance "$BH/inst" || BH_OK=0
bd_bare "$BH/remote.git" && git -C "$BH/inst" remote add origin "$BH/remote.git" || BH_OK=0
bd_cut "$BH/inst" 0002 alpha ACTIVE a@x.test
bd_commit "$BH/inst" "docs(0002): flip on the trunk" || BH_OK=0
git -C "$BH/inst" branch spec/0002-alpha && git -C "$BH/inst" branch spec/0003-beta || BH_OK=0
git -C "$BH/inst" push -q --atomic origin main spec/0002-alpha spec/0003-beta > "$BH/push.log" 2>&1 || BH_OK=0
git clone -q "$BH/remote.git" "$BH/clone" 2>/dev/null || BH_OK=0
BH_NOFETCH_OUT="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$BH/inst" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
git -C "$BH/clone" fetch -q origin 2>/dev/null
git -C "$BH/clone" remote set-url origin "$BH/no-such-remote.git"
BH_OUT="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$BH/clone" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if [[ "$BH_OK" -eq 1 ]] \
   && printf '%s' "$BH_OUT" | grep -qF 'OTHER SPEC BRANCHES ON THE REMOTE, as the last fetch left them (under an hour old; this hook makes no network call): spec/0003-beta.' \
   && ! printf '%s' "$BH_OUT" | grep -q 'spec/0002-alpha' \
   && printf '%s' "$BH_OUT" | grep -q '^Setlist re-grounding' \
   && printf '%s' "$BH_NOFETCH_OUT" | grep -qF 'spec/0003-beta'; then
  ok "0201 hook remote branches: the re-grounding hook names the remote's other spec branches from the last fetch with its age, the active spec's own left out, with the remote unreachable"
else
  bad "0201 hook remote branches: the re-grounding hook names the remote's other spec branches from the last fetch with its age, the active spec's own left out, with the remote unreachable" \
      "setup=$BH_OK out=$(printf '%s' "$BH_OUT" | tr '\n' '|' | cut -c1-500)"
fi

# Nothing is added where the remote carries no other spec branch.
git -C "$BH/inst" push -q origin --delete spec/0003-beta > "$BH/del.log" 2>&1
git clone -q "$BH/remote.git" "$BH/clone2" 2>/dev/null
BH_QUIET="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$BH/clone2" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if [[ -n "$BH_QUIET" ]] && ! printf '%s' "$BH_QUIET" | grep -q 'OTHER SPEC BRANCHES'; then
  ok "0201 hook remote branches quiet: with no other spec branch on the remote the hook adds nothing"
else
  bad "0201 hook remote branches quiet: with no other spec branch on the remote the hook adds nothing" "$(printf '%s' "$BH_QUIET" | tr '\n' '|' | cut -c1-300)"
fi

# The age and the names, in the shapes the 2.14.0 leg found (spec 0205: F2, F3 = F7, F8, F10, F13).
# The age is the last fetch that carried the remote's spec branches, or "of unknown age"; never
# "never fetched" beside branches the clone lists, never the age of an unrelated fetch, a linked
# worktree reads its repository's fetch, and a fetch dated in the future is of unknown age. The
# names are read under the remote's full name, so a remote called team/up lists spec/... and the
# active spec's own branch is still left out; a name cut or with characters replaced says so.
bx_hook() { printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$1" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
BX="$WORK/board-hook-0205"; mkdir -p "$BX"; BX_OK=1
bd_instance "$BX/inst" || BX_OK=0
bd_bare "$BX/remote.git" && git -C "$BX/inst" remote add origin "$BX/remote.git" || BX_OK=0
bd_cut "$BX/inst" 0002 alpha ACTIVE a@x.test
bd_commit "$BX/inst" "docs(0002): flip on the trunk" || BX_OK=0
git -C "$BX/inst" branch spec/0002-alpha && git -C "$BX/inst" branch spec/0003-beta || BX_OK=0
git -C "$BX/inst" push -q --atomic origin main spec/0002-alpha spec/0003-beta > "$BX/push.log" 2>&1 || BX_OK=0
git clone -q "$BX/remote.git" "$BX/fresh" 2>/dev/null || BX_OK=0
BX_FRESH="$(bx_hook "$BX/fresh")"
git clone -q "$BX/remote.git" "$BX/narrow" 2>/dev/null && git -C "$BX/narrow" fetch -q origin main 2>/dev/null || BX_OK=0
BX_NARROW="$(bx_hook "$BX/narrow")"
git clone -q "$BX/remote.git" "$BX/full" 2>/dev/null && git -C "$BX/full" fetch -q origin 2>/dev/null || BX_OK=0
git -C "$BX/full" worktree add -q "$BX/wt" 2>/dev/null || BX_OK=0
BX_WT="$(bx_hook "$BX/wt")"
touch -t 203001010000 "$BX/full/.git/FETCH_HEAD"
BX_FUTURE="$(bx_hook "$BX/full")"
if [[ "$BX_OK" -eq 1 ]] && ! printf '%s\n%s\n%s' "$BX_FRESH" "$BX_NARROW" "$BX_FUTURE" | grep -q 'never fetched' \
   && printf '%s' "$BX_FRESH" | grep -qF 'as the last fetch left them (of unknown age; this hook makes no network call): spec/0003-beta.' \
   && printf '%s' "$BX_NARROW" | grep -qF '(of unknown age; this hook makes no network call): spec/0003-beta.' \
   && printf '%s' "$BX_WT" | grep -qF '(under an hour old; this hook makes no network call): spec/0003-beta.' \
   && printf '%s' "$BX_FUTURE" | grep -qF '(of unknown age; this hook makes no network call): spec/0003-beta.'; then
  ok "0205 F2 F8 F13 hook age: a fresh clone, an unrelated fetch and a future-dated fetch read of unknown age, and a linked worktree reads its repository's fetch"
else
  bad "0205 F2 F8 F13 hook age: a fresh clone, an unrelated fetch and a future-dated fetch read of unknown age, and a linked worktree reads its repository's fetch" \
      "setup=$BX_OK fresh=$(printf '%s' "$BX_FRESH" | grep -o '(.*network call)' | head -1) narrow=$(printf '%s' "$BX_NARROW" | grep -o '(.*network call)' | head -1) wt=$(printf '%s' "$BX_WT" | grep -o '(.*network call)' | head -1) future=$(printf '%s' "$BX_FUTURE" | grep -o '(.*network call)' | head -1)"
fi
git clone -q "$BX/remote.git" "$BX/slash" 2>/dev/null && git -C "$BX/slash" remote rename origin team/up 2>/dev/null || BX_OK=0
BX_SLASH="$(bx_hook "$BX/slash")"
if [[ "$BX_OK" -eq 1 ]] && printf '%s' "$BX_SLASH" | grep -qF '): spec/0003-beta.' \
   && ! printf '%s' "$BX_SLASH" | grep -qE 'up/spec|spec/0002-alpha'; then
  ok "0205 F3 hook names: under a remote named team/up the list reads spec/0003-beta and the active spec's own branch is left out"
else
  bad "0205 F3 hook names: under a remote named team/up the list reads spec/0003-beta and the active spec's own branch is left out" "$(printf '%s' "$BX_SLASH" | grep -o 'OTHER SPEC BRANCHES.*' | head -1 | cut -c1-300)"
fi
BX_LONG="spec/0010-$(printf 'a%.0s' $(seq 1 90))"
git -C "$BX/inst" branch "spec/0009-a'b" && git -C "$BX/inst" branch "$BX_LONG" || BX_OK=0
git -C "$BX/inst" push -q origin "spec/0009-a'b" "$BX_LONG" > "$BX/push2.log" 2>&1 || BX_OK=0
git clone -q "$BX/remote.git" "$BX/odd" 2>/dev/null || BX_OK=0
BX_ODD="$(bx_hook "$BX/odd")"
if [[ "$BX_OK" -eq 1 ]] && printf '%s' "$BX_ODD" | grep -qF 'spec/0009-a?b' \
   && printf '%s' "$BX_ODD" | grep -qF '(characters outside a path set replaced with ?)' \
   && printf '%s' "$BX_ODD" | grep -qF '(cut at 80 characters)'; then
  ok "0205 F10 hook names: a name with characters replaced and a name cut each carry the notice the other paths print"
else
  bad "0205 F10 hook names: a name with characters replaced and a name cut each carry the notice the other paths print" "setup=$BX_OK $(printf '%s' "$BX_ODD" | grep -o 'OTHER SPEC BRANCHES.*' | head -1 | cut -c1-400)"
fi

fi; shard_region_end
# <<< SHARD-END board-hook-0201

# >>> SHARD-BEGIN board-owns-0201 cost=1
if shard_region board-owns-0201; then

# The append report: who else declares a file, from the trunk's ACTIVE specs and
# every spec on a remote spec/ branch, with its driver and the close's remedy; the
# spec making the append is not reported against itself; exit 0 either way.
BO="$WORK/board-owns-0201"
mkdir -p "$BO"
BO_OK=1
bd_instance "$BO/inst" || BO_OK=0
bd_bare "$BO/remote.git" && git -C "$BO/inst" remote add origin "$BO/remote.git" || BO_OK=0
bd_cut "$BO/inst" 0002 alpha ACTIVE a@x.test
bd_cut "$BO/inst" 0003 beta ACTIVE b@x.test
bd_commit "$BO/inst" "docs: two flips on the trunk" || BO_OK=0
git -C "$BO/inst" branch spec/0002-alpha && git -C "$BO/inst" push -q --atomic origin main spec/0002-alpha > "$BO/p1.log" 2>&1 || BO_OK=0
git -C "$BO/inst" checkout -q spec/0002-alpha && bd_owns "$BO/inst" specs/0002-alpha.md src/core.js \
  && bd_commit "$BO/inst" "feat(0002): core" && git -C "$BO/inst" push -q origin spec/0002-alpha > "$BO/p2.log" 2>&1 || BO_OK=0
git -C "$BO/inst" checkout -q main
git clone -q "$BO/remote.git" "$BO/b" 2>/dev/null && bd_config "$BO/b" b@x.test || BO_OK=0
BO_RC=0; bash "$ROOT/scripts/board.sh" --dir "$BO/b" --owns src/core.js --spec 0003 > "$BO/hit.out" 2>&1 || BO_RC=$?
BO_RC2=0; bash "$ROOT/scripts/board.sh" --dir "$BO/b" --owns src/other.js --spec 0003 > "$BO/miss.out" 2>&1 || BO_RC2=$?
git -C "$BO/inst" checkout -q spec/0002-alpha 2>/dev/null
BO_RC3=0; bash "$ROOT/scripts/board.sh" --dir "$BO/inst" --owns src/core.js --spec 0002 > "$BO/self.out" 2>&1 || BO_RC3=$?
if [[ "$BO_OK" -eq 1 && "$BO_RC" -eq 0 && "$BO_RC2" -eq 0 && "$BO_RC3" -eq 0 ]] \
   && grep -qx 'owns: src/core.js is also declared by:' "$BO/hit.out" \
   && grep -qx '  - spec 0002-alpha (active), driver a@x.test, branch spec/0002-alpha' "$BO/hit.out" \
   && grep -q 'merge the trunk into the second spec.s branch, re-run the close and merge again' "$BO/hit.out" \
   && grep -q 'This report refuses nothing' "$BO/hit.out" \
   && grep -q '^owns: no other spec' "$BO/miss.out" && grep -q '^owns: no other spec' "$BO/self.out"; then
  ok "0201 owns report: an append names the other spec declaring the file, from its remote branch, with its driver and the close's remedy; none for an undeclared file or for the spec itself; exit 0"
else
  bad "0201 owns report: an append names the other spec declaring the file, from its remote branch, with its driver and the close's remedy; none for an undeclared file or for the spec itself; exit 0" \
      "setup=$BO_OK rc=$BO_RC,$BO_RC2,$BO_RC3 hit=$(tr '\n' '|' < "$BO/hit.out" | cut -c1-300) self=$(head -c 200 "$BO/self.out")"
fi

fi; shard_region_end
# <<< SHARD-END board-owns-0201

# >>> SHARD-BEGIN board-stale-0201 cost=1
if shard_region board-stale-0201; then

# A claim with no commit for ten days is stale against the default and against
# stale_days 5, not against 30; a malformed value falls back to 7 and says so.
BS="$WORK/board-stale-0201"
mkdir -p "$BS"
BS_OK=1
bd_instance "$BS/inst" || BS_OK=0
bd_bare "$BS/remote.git" && git -C "$BS/inst" remote add origin "$BS/remote.git" || BS_OK=0
BS_OLD="$(( $(date +%s) - 10 * 86400 )) +0000"
bd_cut "$BS/inst" 0002 old ACTIVE a@x.test
GIT_COMMITTER_DATE="$BS_OLD" GIT_AUTHOR_DATE="$BS_OLD" bd_commit "$BS/inst" "docs(0002): flip, ten days ago" || BS_OK=0
git -C "$BS/inst" branch spec/0002-old && git -C "$BS/inst" push -q --atomic origin main spec/0002-old > "$BS/p.log" 2>&1 || BS_OK=0
bs_run() { # bs_run <stale_days json or "absent"> <out>
  if [[ "$1" == absent ]]; then jq 'del(.stale_days)' "$BS/inst/.claude/sdd.json" > "$BS/sdd.new"
  else jq --argjson v "$1" '.stale_days = $v' "$BS/inst/.claude/sdd.json" > "$BS/sdd.new"; fi
  mv "$BS/sdd.new" "$BS/inst/.claude/sdd.json"
  bash "$ROOT/scripts/board.sh" --dir "$BS/inst" > "$2" 2>&1
}
bs_run absent "$BS/absent.out"; bs_run 5 "$BS/five.out"; bs_run 30 "$BS/thirty.out"; bs_run '"soon"' "$BS/bad.out"; bs_run '"00"' "$BS/zeros.out"
git -C "$BS/inst" checkout -q -- .claude/sdd.json 2>/dev/null
BS_LINE='^  - stale: spec 0002-old (driver a@x.test, branch spec/0002-old) has had no commit for 10 days'
if [[ "$BS_OK" -eq 1 ]] && grep -q "$BS_LINE (more than 7)" "$BS/absent.out" && grep -q 'stale after 7 days (stale_days not set: the default)' "$BS/absent.out" \
   && grep -q "$BS_LINE (more than 5)" "$BS/five.out" \
   && ! grep -q '  - stale:' "$BS/thirty.out" && grep -q 'stale after 30 days' "$BS/thirty.out" \
   && grep -q "$BS_LINE (more than 7)" "$BS/bad.out" && grep -q 'stale_days reads "soon", not a positive whole number of days, so 7' "$BS/bad.out"; then
  ok "0201 stale claims: a ten-day claim is stale with its driver against the default 7 and against 5, not against 30, and a malformed stale_days reads as 7 and says so"
else
  bad "0201 stale claims: a ten-day claim is stale with its driver against the default 7 and against 5, not against 30, and a malformed stale_days reads as 7 and says so" \
      "setup=$BS_OK absent=$(grep -c '  - stale:' "$BS/absent.out") five=$(grep -c '  - stale:' "$BS/five.out") thirty=$(grep -c '  - stale:' "$BS/thirty.out") bad=$(grep -m1 'stale after' "$BS/bad.out")"
fi
# "00" is no more a positive number of days than "0" (spec 0205, the 2.14.0 leg's F9): it read as stale
# after 00 days and made every claim stale.
if [[ "$BS_OK" -eq 1 ]] && grep -q 'stale_days reads "00", not a positive whole number of days, so 7' "$BS/zeros.out" && grep -q "$BS_LINE (more than 7)" "$BS/zeros.out"; then
  ok "0205 F9 stale claims: stale_days \"00\" reads as not a positive number and falls back to 7"
else
  bad "0205 F9 stale claims: stale_days \"00\" reads as not a positive number and falls back to 7" "$(grep -m1 'stale after' "$BS/zeros.out")"
fi

fi; shard_region_end
# <<< SHARD-END board-stale-0201

# >>> SHARD-BEGIN two-clones-0201 cost=1
if shard_region two-clones-0201; then

# THE TWO-CLONE FIXTURE (spec 0201, item 9). Two clones of one instance claim the
# same number under two slugs and declare one file. The stamped git hooks are
# ARMED in every clone (core.hooksPath), so the two regression locks read the
# hooks as shipped: the opening flip committed on the trunk passes pre-commit and
# pre-push, and the empty claim branch pushed beside it passes pre-push. Clone B's
# flip push is refused (the race; the remote's end of its range was never
# fetched). The board, read from EITHER clone, names the collision by name.
TC_FX="$ROOT/test/fixtures/two-clones"
TC="$WORK/two-clones-0201"
mkdir -p "$TC"
TC_OK=1
bd_instance "$TC/inst" || TC_OK=0
bd_bare "$TC/remote.git" && git -C "$TC/inst" remote add origin "$TC/remote.git" \
  && git -C "$TC/inst" push -q origin main > "$TC/p0.log" 2>&1 || TC_OK=0
git clone -q "$TC/remote.git" "$TC/A" 2>/dev/null && bd_config "$TC/A" a@x.test || TC_OK=0
git clone -q "$TC/remote.git" "$TC/B" 2>/dev/null && bd_config "$TC/B" b@x.test || TC_OK=0
tc_flip() { # tc_flip <clone> <slug> : the fixture's spec file, its row and record token, on the trunk
  cp "$TC_FX/0002-$2.md" "$1/specs/0002-$2.md" \
    && printf '| 0002 | %s | ACTIVE | flipped on the trunk |\n' "$2" >> "$1/specs/STATUS.md" \
    && jq '.specs["0002"] = {"status": "active"}' "$1/.claude/status.json" > "$1/.claude/status.json.new" \
    && mv "$1/.claude/status.json.new" "$1/.claude/status.json" \
    && git -C "$1" add -A && git -C "$1" commit -qm "docs(0002): flip ACTIVE on the trunk" > "$1.flip.log" 2>&1
}
TC_AF=0; tc_flip "$TC/A" alpha || TC_AF=$?
git -C "$TC/A" branch spec/0002-alpha
TC_AP=0; git -C "$TC/A" push --atomic origin main spec/0002-alpha > "$TC/A.push.log" 2>&1 || TC_AP=$?
TC_A_CLAIM="$(git --git-dir="$TC/remote.git" rev-parse --verify -q refs/heads/spec/0002-alpha 2>/dev/null)"
TC_A_FLIP="$(git -C "$TC/A" rev-parse main 2>/dev/null)"
git -C "$TC/A" checkout -q spec/0002-alpha && bd_owns "$TC/A" specs/0002-alpha.md src/shared.js \
  && bd_commit "$TC/A" "feat(0002): shared, A" && git -C "$TC/A" push -q origin spec/0002-alpha > "$TC/A.push2.log" 2>&1 || TC_OK=0
TC_BF=0; tc_flip "$TC/B" beta || TC_BF=$?
git -C "$TC/B" branch spec/0002-beta
TC_BP=0; git -C "$TC/B" push --atomic origin main spec/0002-beta > "$TC/B.push.log" 2>&1 || TC_BP=$?
TC_B_CLAIM="$(git --git-dir="$TC/remote.git" rev-parse --verify -q refs/heads/spec/0002-beta 2>/dev/null)"
TC_REMOTE_MAIN="$(git --git-dir="$TC/remote.git" rev-parse main 2>/dev/null)"
git -C "$TC/B" checkout -q spec/0002-beta && bd_owns "$TC/B" specs/0002-beta.md src/shared.js \
  && bd_commit "$TC/B" "feat(0002): shared, B" && git -C "$TC/B" push -q origin spec/0002-beta > "$TC/B.push2.log" 2>&1 || TC_OK=0

# a. The two regression locks, through the stamped hooks unchanged.
if [[ "$TC_OK" -eq 1 && "$TC_AF" -eq 0 && "$TC_AP" -eq 0 && "$TC_BF" -eq 0 ]] \
   && [[ "$(git -C "$TC/A" config --get core.hooksPath)" == ".githooks" ]] \
   && grep -q 'audited .* commits on main: .* 0 violations' "$TC/A.push.log" \
   && [[ -n "$TC_A_CLAIM" && "$TC_A_CLAIM" == "$TC_A_FLIP" ]]; then
  ok "0201 two clones a: the opening flip committed on the trunk passes the armed pre-commit and pre-push, and the empty claim branch beside it lands at the flip commit"
else
  bad "0201 two clones a: the opening flip committed on the trunk passes the armed pre-commit and pre-push, and the empty claim branch beside it lands at the flip commit" \
      "setup=$TC_OK flipA=$TC_AF pushA=$TC_AP flipB=$TC_BF $(tail -n 3 "$TC/A.push.log" | tr '\n' '|')"
fi

# b. The race: clone B's flip push is refused, and the remote's trunk is A's.
if [[ "$TC_BP" -ne 0 && "$TC_REMOTE_MAIN" == "$TC_A_FLIP" && -z "$TC_B_CLAIM" ]]; then
  ok "0201 two clones b: the second clone's atomic flip push is refused, the remote's trunk is the first clone's, and no claim branch landed with the refused trunk"
else
  bad "0201 two clones b: the second clone's atomic flip push is refused, the remote's trunk is the first clone's, and no claim branch landed with the refused trunk" \
      "pushB=$TC_BP remote-main-is-A=$([[ "$TC_REMOTE_MAIN" == "$TC_A_FLIP" ]] && echo yes || echo no) beta-claim=${TC_B_CLAIM:-none} $(tail -n 3 "$TC/B.push.log" | tr '\n' '|')"
fi

# c. The board, from either clone, names the number collision and the overlap by name.
TC_MISS=""
for TC_C in A B; do
  bash "$ROOT/scripts/board.sh" --dir "$TC/$TC_C" > "$TC/board-$TC_C.out" 2>&1 || TC_MISS="$TC_MISS $TC_C:rc"
  grep -q '^  - number: 0002 is claimed twice, by spec 0002-alpha (driver a@x.test, branch spec/0002-alpha) and spec 0002-beta (driver b@x.test, branch spec/0002-beta)' "$TC/board-$TC_C.out" || TC_MISS="$TC_MISS $TC_C:number"
  grep -q '^  - overlap: spec 0002-alpha (driver a@x.test, branch spec/0002-alpha) and spec 0002-beta (driver b@x.test, branch spec/0002-beta) both declare src/shared.js' "$TC/board-$TC_C.out" || TC_MISS="$TC_MISS $TC_C:overlap"
  [[ "$(bash "$ROOT/scripts/board.sh" --dir "$TC/$TC_C" --next 2>/dev/null)" == "0003" ]] || TC_MISS="$TC_MISS $TC_C:next"
done
if [[ -z "$TC_MISS" ]]; then
  ok "0201 two clones c: the board from either clone names one number claimed twice and the overlap on src/shared.js with both drivers, and both read 0003 as next"
else
  bad "0201 two clones c: the board from either clone names one number claimed twice and the overlap on src/shared.js with both drivers, and both read 0003 as next" "missing=[${TC_MISS# }]"
fi

# d. The re-grounding hook in each clone names the OTHER claim of the number from
#    its last fetch (B fetched when its board ran; A fetches here).
git -C "$TC/A" fetch -q origin 2>/dev/null
TC_HA="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$TC/A" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
TC_HB="$(printf '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$TC/B" bash "$ROOT/templates/hooks/regrounding-hook.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if printf '%s' "$TC_HA" | grep -q 'OTHER SPEC BRANCHES ON THE REMOTE.*: spec/0002-beta\.' \
   && printf '%s' "$TC_HB" | grep -q 'OTHER SPEC BRANCHES ON THE REMOTE.*: spec/0002-alpha\.'; then
  ok "0201 two clones d: the re-grounding hook in each clone names the other clone's claim of the same number from its last fetch"
else
  bad "0201 two clones d: the re-grounding hook in each clone names the other clone's claim of the same number from its last fetch" \
      "A=$(printf '%s' "$TC_HA" | grep -o 'OTHER SPEC BRANCHES[^.]*\.' | head -n1) B=$(printf '%s' "$TC_HB" | grep -o 'OTHER SPEC BRANCHES[^.]*\.' | head -n1)"
fi

fi; shard_region_end
# <<< SHARD-END two-clones-0201
