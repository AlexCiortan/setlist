#!/usr/bin/env bash
# test/suite/08-git-hooks.sh: shard 8 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE STAMPED GIT HOOKS (item 28 Stage B, cut worklist 4.2)
#
# pre-commit and pre-merge-commit, driven through REAL git operations rather
# than by invoking the scripts. Invoking a hook directly proves the script; only
# running `git merge` proves that git calls it, on this path, with these
# settings. The 1.0.8 macOS fail-open is the standing argument for the
# distinction: everything passed except the thing nobody ran.
#
# The firing table these cases encode was MEASURED, not read (2026-08-01):
# pre-commit fires for an ordinary commit and for the commit completing a squash
# or a stalled merge; pre-merge-commit fires only for a true merge commit; a
# fast-forward merge fires neither, which is why the stamp sets merge.ff=false.
# =============================================================================

gh_fixture() { # gh_fixture <dir> <closed: yes|no> [trunk-spelling]
  # The third argument defaults to "main" so every existing case is unchanged.
  # It exists because EVERY fixture in this suite wrote "main" and nothing else,
  # which is precisely why the v1.7 gate's BLOCKER survived 573 green assertions:
  # the trunk-SPELLING dimension was never varied against the git-hook layer, only
  # against close-gate.sh (the block at "trunk spelling" further up this file).
  local d="$1" closed="$2" trunkval="${3:-main}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"%s","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$trunkval" > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'work\n' > "$d/src/FEATURE.txt"
  if [[ "$closed" == "fenced" ]]; then
    # A FENCED EXAMPLE IS NOT A CLOSING REPORT. close-gate.sh learned this as
    # leg 5's F7 and strips fenced spans once before all four checks; the git
    # hooks and the trunk audit never got the same treatment, so a spec whose
    # entire Closing report is a quoted ```markdown example really merged
    # (v1.7 gate, adversarial review F9). This is ordinary authoring rather than an
    # attack: the template ships fenced in setlist.md and the spec-authoring
    # skill tells authors to copy it.
    # A HEREDOC, not printf. The first draft used one printf per line and three
    # of them began with "- ", which bash's printf parses as OPTIONS and drops:
    # the fixture wrote a spec containing the fence and the heading and NOTHING
    # ELSE, the hook refused it for having no QA verdict, and the assertion went
    # green while testing nothing at all. That is the exact defect class this
    # block exists to catch, committed by the test for the defect.
    cat > "$d/specs/0001-thing.md" <<'FENCEDSPEC'
# Spec 0001

Status: CLOSED

Here is the template I am going to fill in later:

```markdown
## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
```
FENCEDSPEC
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  elif [[ "$closed" == "yes" ]]; then
    printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-thing.md"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  else
    printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
    # The inventory row rides the same commit as the Status line. That is the
    # protocol, and it is also what makes this fixture BUILDABLE: the first
    # draft omitted it, pre-commit correctly refused the branch's only commit,
    # and every refusal case below then "passed" against a branch with no work
    # on it at all. The two allow-direction cases are what exposed that, which
    # is the whole reason a gate's positive direction is not optional.
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "work" >/dev/null 2>&1
  git -C "$d" checkout -q main
  # A remote-tracking ref, so the remote spellings under test RESOLVE rather than
  # failing for the uninteresting reason that nothing of that name exists. Every
  # ordinary clone has one; the upgrade skill's own trunk detection command,
  # `git symbolic-ref refs/remotes/origin/HEAD`, is what puts a ref PATH into
  # sdd.json in the first place.
  git -C "$d" update-ref refs/remotes/origin/main "$(git -C "$d" rev-parse main)" 2>/dev/null || true
  # The stamp, both halves, applied AFTER the fixture's own history exists so
  # the hooks judge the merge under test rather than the scaffolding.
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" config merge.ff false
  # CONTROL: the branch must actually carry work to merge. Without this, a
  # fixture that failed to build reports every refusal case as a pass.
  git -C "$d" cat-file -e "spec/0001-thing:src/FEATURE.txt" 2>/dev/null \
    || bad "git hooks fixture: spec/0001-thing carries the work under test" \
           "the fixture built no work commit, so every refusal case below would pass while testing nothing"
}

gh_landed() { git -C "$1" cat-file -e main:src/FEATURE.txt 2>/dev/null; }

# ===========================================================================
# THE AUDIT'S EXCUSE IS ABOUT AGE, SO IT ASKS ABOUT AGE (F2/F7, 2026-08-05).
#
# A chore-shaped merge with no recorded completion was reported "unverifiable"
# and tallied as a CHORE, leaving VIOLATIONS at 0 and the exit code at 0, which
# is the only thing pre-push reads. Any route that reaches the trunk without
# firing pre-merge-commit landed there: detached HEAD, --no-verify,
# core.hooksPath=/dev/null, and by commit shape the forge merge button. README
# names those routes and claims the audit catches every one.
#
# The block justified itself by ANTIQUITY and decided by SHAPE, and a merge made
# today that skipped the hook has the same shape as one made before the rule
# existed. It now asks when the instance adopted the rules and exempts only what
# is genuinely older. Both directions, because an exemption that never applies
# is as wrong as one that always does.
ta_flow() { # ta_flow <dir> -- an instance whose trunk carries a hook-skipping merge
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "stamp" >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  printf 'unspecced\n' > "$d/src/unspecced.js"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "unspecced" >/dev/null 2>&1
  git -C "$d" checkout -q --detach main
  git -C "$d" merge --no-verify --no-ff -m dm spec/0001-thing >/dev/null 2>&1
  git -C "$d" branch -f main HEAD; git -C "$d" checkout -q main
}
TAF="$WORK/ta-bypass"; ta_flow "$TAF"
if bash "$ROOT/scripts/trunk-audit.sh" "$TAF" >"$WORK/ta.out" 2>&1; then
  bad "audit age a: a hook-skipping merge made AFTER adoption is a violation, not an excuse" \
      "the audit exited 0, so pre-push allows it and the README's claim that the audit catches these routes is false"
else ok "audit age a: a hook-skipping merge made AFTER adoption is a violation, not an excuse"; fi

# THE RESTRAINT, still intact. A backstop that cries wolf about history it was
# never able to govern gets switched off, and then it guards nothing.
TAO="$WORK/ta-old"; rm -rf "$TAO"; mkdir -p "$TAO/src" "$TAO/specs" "$TAO/.claude"
git_init "$TAO"
printf 'x\n' > "$TAO/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$TAO/specs/STATUS.md"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm "before the framework" >/dev/null 2>&1
TAO_ROOT="$(git -C "$TAO" rev-parse HEAD)"
git -C "$TAO" checkout -q -b legacy; printf 'legacy\n' > "$TAO/src/legacy.js"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm legacy >/dev/null 2>&1
git -C "$TAO" checkout -q main
git -C "$TAO" merge -q --no-verify --no-ff -m "old merge" legacy >/dev/null 2>&1
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAO/.claude/sdd.json"
git -C "$TAO" add -A >/dev/null 2>&1; git -C "$TAO" commit -qm "stamp: adopt the rules" >/dev/null 2>&1
if bash "$ROOT/scripts/trunk-audit.sh" "$TAO" --since "$TAO_ROOT" >"$WORK/tao.out" 2>&1; then
  ok "audit age b: a chore merge that genuinely predates adoption keeps its exemption"
else
  bad "audit age b: a chore merge that genuinely predates adoption keeps its exemption" \
      "the audit condemned pre-rule history, which is the crying-wolf direction the exemption exists to prevent"
fi

# THE ARITY ARM IS GONE (B2 restatement, 2026-08-13), and these two cases are
# the proof it demanded. The audit used to condemn any merge with more than two
# parents outright, on the reasoning "an octopus merge is not pre-rule history",
# which infers AGE from SHAPE: the parent count is a spelling, and the question
# that decides the exemption is WHEN, answered by ancestry for every arity at
# once. Case c pins that nothing was relaxed: a post-adoption octopus is still
# condemned, by post_baseline rather than by counting parents. Case d pins the
# restatement itself: pre-adoption history keeps its exemption regardless of
# arity, because the restraint doctrine has no arity clause. Case d was watched
# RED against the pre-restatement audit (it condemned this exact fixture with
# "in a merge justified by another parent") before the change landed.
TAC="$WORK/ta-octo-post"; rm -rf "$TAC"; mkdir -p "$TAC/src" "$TAC/specs" "$TAC/.claude"
git_init "$TAC"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAC/.claude/sdd.json"
printf 'x\n' > "$TAC/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$TAC/specs/STATUS.md"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm stamp >/dev/null 2>&1
TAC_BASE="$(git -C "$TAC" rev-parse HEAD)"
git -C "$TAC" checkout -q -b spec/0001-first "$TAC_BASE"
printf 'export const legit = 1\n' > "$TAC/src/legit.js"
{ printf '# 0001 First\n\n## Closing report\n\nDone.\n\n```qa-pass-1\nc1: PASS\n```\n\n- Architecture diagram: no impact\n'; } > "$TAC/specs/0001-first.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$TAC/specs/STATUS.md"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm "close 0001" >/dev/null 2>&1
git -C "$TAC" checkout -q -b sneaky "$TAC_BASE"
printf 'export const evil = 1\n' > "$TAC/src/evil.js"
git -C "$TAC" add -A >/dev/null 2>&1; git -C "$TAC" commit -qm "sneaky code" >/dev/null 2>&1
git -C "$TAC" checkout -q main
git -C "$TAC" merge -q --no-ff --no-verify -m "close 0001 and pull sneaky" spec/0001-first sneaky >/dev/null 2>&1
if [ "$(git -C "$TAC" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" != "4" ]; then
  bad "audit age c: a POST-adoption octopus with an unjustified parent is still a violation" \
      "fixture error: the octopus folded instead of producing a 3-parent commit, so nothing below tests the arity-free path"
elif bash "$ROOT/scripts/trunk-audit.sh" "$TAC" >"$WORK/tac.out" 2>&1; then
  bad "audit age c: a POST-adoption octopus with an unjustified parent is still a violation" \
      "removing the arity arm RELAXED the audit: the sneaky parent passed, so ancestry is not carrying what shape used to"
else
  ok "audit age c: a POST-adoption octopus with an unjustified parent is still a violation"
fi

TAD="$WORK/ta-octo-pre"; rm -rf "$TAD"; mkdir -p "$TAD/src" "$TAD/specs"
git_init "$TAD"
printf 'x\n' > "$TAD/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$TAD/specs/STATUS.md"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "pre-framework root" >/dev/null 2>&1
TAD_ROOT="$(git -C "$TAD" rev-parse HEAD)"
git -C "$TAD" checkout -q -b oldb1 "$TAD_ROOT"; printf 'a\n' > "$TAD/src/a.js"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "old b1" >/dev/null 2>&1
git -C "$TAD" checkout -q -b oldb2 "$TAD_ROOT"; printf 'b\n' > "$TAD/src/b.js"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "old b2" >/dev/null 2>&1
git -C "$TAD" checkout -q main
git -C "$TAD" merge -q --no-ff --no-verify -m "old octopus" oldb1 oldb2 >/dev/null 2>&1
mkdir -p "$TAD/.claude"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TAD/.claude/sdd.json"
git -C "$TAD" add -A >/dev/null 2>&1; git -C "$TAD" commit -qm "stamp: adopt the rules" >/dev/null 2>&1
if [ "$(git -C "$TAD" rev-list --parents -n1 'HEAD^' | wc -w | tr -d ' ')" != "4" ]; then
  bad "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps" \
      "fixture error: the octopus folded, so the case tests nothing"
elif bash "$ROOT/scripts/trunk-audit.sh" "$TAD" --since "$TAD_ROOT" >"$WORK/tad.out" 2>&1; then
  ok "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps"
else
  bad "audit age d: a genuinely PRE-adoption octopus keeps the exemption every pre-rule merge keeps" \
      "the audit condemned pre-rule history by its parent count, which is age inferred from shape"
fi

# ===========================================================================
# THE RECORDED TRUNK NAME IS THE ONLY TRUNK TEST (F1 and F9, 2026-08-07).
#
# Between 2026-08-05 and 2026-08-07 slh_on_trunk also consulted what HEAD
# TRACKS, so a git-flow repository working on `trunk` while sdd.json recorded
# "main" would still be governed. It could not tell that shape apart from the
# ordinary one: `git checkout -b <name> origin/main` is git's own documented way
# to branch from a remote trunk, git announces it with "set up to track", and
# every such branch became the trunk to the hooks. Merges of role-path code into
# ordinary spec and feature branches were hard-refused SLH-CLOSES-NO-SPEC, with
# a message naming `main` as the target of a merge that never touched it, and
# the only remedies were an undocumented `git branch --unset-upstream` or
# SETLIST_SKIP_HOOKS=1, which turns the whole layer off.
#
# The discriminator was removed. These three assertions pin BOTH directions of
# that decision: the two ordinary shapes must be allowed, and the git-flow shape
# is a Known limitation rather than a silent hole. Re-introducing any tracking
# test turns the first two red before it can ship.
GHF="$WORK/gh-gitflow"; rm -rf "$GHF"; mkdir -p "$GHF/src" "$GHF/specs" "$GHF/.claude" "$GHF/.githooks"
git_init "$GHF"
git -C "$GHF" config merge.ff false
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$GHF/.claude/sdd.json"
printf 'x\n' > "$GHF/src/app.js"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$GHF/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$GHF/.githooks/"
chmod +x "$GHF/.githooks/pre-merge-commit"
git -C "$GHF" add -A >/dev/null 2>&1
git -C "$GHF" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
git -C "$GHF" config core.hooksPath .githooks
git init -q --bare "$WORK/gh-gitflow-rem.git"
git -C "$GHF" remote add origin "$WORK/gh-gitflow-rem.git"
git -C "$GHF" push -q origin main >/dev/null 2>&1
git -C "$GHF" fetch -q origin >/dev/null 2>&1

# The branch that carries the code the merges below bring. Committed with the
# hooks bypassed because what is under test is the MERGE decision, not this.
git -C "$GHF" checkout -q -b feat/help main
printf 'help\n' > "$GHF/src/help.js"
git -C "$GHF" add -A >/dev/null 2>&1
git -C "$GHF" -c core.hooksPath=/dev/null commit -qm help >/dev/null 2>&1

# ORDINARY WORK 1: a spec branch cut from origin/main. The upstream is set by
# git, not by the developer, and the branch is not the trunk.
git -C "$GHF" merge --abort >/dev/null 2>&1 || true
git -C "$GHF" checkout -q -f main
git -C "$GHF" checkout -q -b spec/0002-tracked origin/main >/dev/null 2>&1
( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m feat/help ) >"$WORK/ghf1.out" 2>&1
if git -C "$GHF" cat-file -e spec/0002-tracked:src/help.js 2>/dev/null; then
  ok "gitflow a: a spec branch cut from origin/main is not the trunk, and its merges land"
else
  bad "gitflow a: a spec branch cut from origin/main is not the trunk, and its merges land" \
      "the guarantee layer refused ordinary work on a branch git itself set up to track: $(head -3 "$WORK/ghf1.out" | tr '\n' ' ')"
fi

# ORDINARY WORK 2: the same for a feature branch, and for a purely LOCAL
# upstream, where no remote is involved at all.
git -C "$GHF" merge --abort >/dev/null 2>&1 || true
git -C "$GHF" checkout -q -f main
git -C "$GHF" checkout -q -b feat/localtrack >/dev/null 2>&1
git -C "$GHF" branch --set-upstream-to=main feat/localtrack >/dev/null 2>&1
( cd "$GHF" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m m feat/help ) >"$WORK/ghf2.out" 2>&1
if git -C "$GHF" cat-file -e feat/localtrack:src/help.js 2>/dev/null; then
  ok "gitflow b: a branch whose upstream is a LOCAL trunk is not the trunk either"
else
  bad "gitflow b: a branch whose upstream is a LOCAL trunk is not the trunk either" \
      "--set-upstream-to=main made an ordinary branch the trunk to the hooks: $(head -3 "$WORK/ghf2.out" | tr '\n' ' ')"
fi

# THE LIMITATION, ASSERTED: an instance working on `trunk` while sdd.json says
# "main" is NOT governed. This is a hole, and it is documented as one; the
# assertion exists so it cannot be re-closed by accident, without the
# false-denial cost above being paid again and re-decided.
GHG="$WORK/gh-gitflow2"; rm -rf "$GHG"; cp -R "$GHF" "$GHG"
git -C "$GHG" merge --abort >/dev/null 2>&1 || true
git -C "$GHG" checkout -q -f main
git -C "$GHG" branch -m main trunk >/dev/null 2>&1
git -C "$GHG" branch --set-upstream-to=origin/main trunk >/dev/null 2>&1
git -C "$GHG" branch main trunk >/dev/null 2>&1
git -C "$GHG" checkout -q -b spec/0001-thing
printf 'unspecced\n' > "$GHG/src/f.js"
git -C "$GHG" add -A >/dev/null 2>&1
git -C "$GHG" -c core.hooksPath=/dev/null commit -qm f >/dev/null 2>&1
git -C "$GHG" checkout -q trunk
( cd "$GHG" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m close spec/0001-thing ) >/dev/null 2>&1
if git -C "$GHG" cat-file -e trunk:src/f.js 2>/dev/null; then
  ok "gitflow c: KNOWN HOLE, an instance whose recorded trunk is not the branch it merges onto is ungoverned"
else
  bad "gitflow c: KNOWN HOLE, an instance whose recorded trunk is not the branch it merges onto is ungoverned" \
      "this hole closed, which is good news that has to be paid for: check the ordinary-work assertions above, then move the bullet out of Known limitations in the same commit"
fi


# ===========================================================================
# CONTENT SCANNING IS BOUND TO CONTENT, NOT TO AN OPERATION (F1, 2026-08-05).
#
# The em-dash and secret scans lived in pre-commit alone, so every route that
# creates a commit WITHOUT firing pre-commit carried unscanned bytes to the
# trunk. Measured on the shipped tree: cherry-pick, rebase, am, merge --no-ff
# and merge --ff each landed a live-shaped key at rc=0 while the identical bytes
# through `git commit` were refused SLH-SECRET.
#
# Both directions, because a scan that refuses everything is not a scan.
# ===========================================================================
SECRET_LINE='const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";'

# CONTROL, and it is the one that makes the rest mean anything: the ordinary
# commit path still refuses these bytes.
GHS="$WORK/gh-scan-ctl"; gh_fixture "$GHS" yes
printf '%s\n' "$SECRET_LINE" > "$GHS/src/leak.js"
git -C "$GHS" add src/leak.js >/dev/null 2>&1
if git -C "$GHS" commit -qm "leak" >/dev/null 2>&1; then
  bad "scan control: git commit still refuses a secret-shaped string" "the commit was allowed, so no result below is interpretable"
else ok "scan control: git commit still refuses a secret-shaped string"; fi

# THE MERGE PATH. pre-commit does not fire for a true merge, which is how the
# framework's own close path carried unscanned content.
GHM="$WORK/gh-scan-merge"; gh_fixture "$GHM" yes
git -C "$GHM" checkout -q spec/0001-thing
printf '%s\n' "$SECRET_LINE" > "$GHM/src/leak.js"
git -C "$GHM" add -A >/dev/null 2>&1
git -C "$GHM" -c core.hooksPath=/dev/null commit -qm "leak on the branch" >/dev/null 2>&1
git -C "$GHM" checkout -q main
( cd "$GHM" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if git -C "$GHM" cat-file -e main:src/leak.js 2>/dev/null; then
  bad "scan merge: a merge carrying a secret is refused" "the merge landed the secret on the trunk, which is F1 still open"
else ok "scan merge: a merge carrying a secret is refused"; fi

# THE CONTROL FOR THE MERGE PATH: clean content still merges. Without this the
# assertion above is satisfied by a hook that refuses every merge.
GHMC="$WORK/gh-scan-merge-ok"; gh_fixture "$GHMC" yes
( cd "$GHMC" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
# THE ROUTES GIT GIVES NO HOOK FOR, both halves. The scan is bound to content
# rather than to an operation, but git still fires nothing for cherry-pick, so
# the claim is not "every route is scanned at commit time", it is "no route
# reaches a REMOTE unscanned". Both halves are asserted because the second is
# the entire reason the first is acceptable.
GHC="$WORK/gh-scan-cherry"; gh_fixture "$GHC" yes
git -C "$GHC" checkout -q -b leaky
printf '%s\n' "$SECRET_LINE" > "$GHC/src/leak.js"
git -C "$GHC" add -A >/dev/null 2>&1
git -C "$GHC" -c core.hooksPath=/dev/null commit -qm "leak" >/dev/null 2>&1
GHC_SHA="$(git -C "$GHC" rev-parse HEAD)"
git -C "$GHC" checkout -q main
if git -C "$GHC" cherry-pick "$GHC_SHA" >/dev/null 2>&1 && git -C "$GHC" cat-file -e main:src/leak.js 2>/dev/null; then
  ok "scan cherry a: cherry-pick really does create a commit no commit-time scan sees (documented hole, still open)"
else
  ok "scan cherry a: cherry-pick is now caught at commit time, which CLOSES a documented hole; update Known limitations and this ledger entry"
fi
# The half that makes it acceptable: pre-push reads the range and refuses.
cp "$ROOT/templates/git-hooks/pre-push" "$GHC/.githooks/pre-push" 2>/dev/null
chmod +x "$GHC/.githooks/pre-push" 2>/dev/null
git init -q --bare "$WORK/gh-scan-cherry-rem.git"
git -C "$GHC" remote add origin "$WORK/gh-scan-cherry-rem.git" >/dev/null 2>&1
if git -C "$GHC" push -q origin main >/dev/null 2>&1; then
  bad "scan cherry b: the push-time range scan refuses a cherry-picked secret" \
      "the push succeeded, so the secret reached a remote and the README's claim that a pushed history cannot carry one is false"
else ok "scan cherry b: the push-time range scan refuses a cherry-picked secret"; fi

# ===========================================================================
# THE SCAN COVERS EVERY PUSHED BRANCH REF, NOT JUST THE TRUNK (F2, verdict leg).
#
# "scan cherry b" above pushes the TRUNK, and it passed the whole time while the
# ordinary push of a SPEC BRANCH published unscanned content: pre-push applied
# the trunk-name filter before the scan, so the scan inherited the audit's
# scope. The assertion was real and proved a narrower claim than the
# Known-limitations bullet beside it promised, which is how a true test sits
# next to a false sentence.
#
# So the corpus is the ref name as its own axis, across all three routes git
# gives no commit-time hook for, with a clean spec branch as the control that
# stops this being satisfied by a hook that refuses every push.
scan_ref_fixture() { # scan_ref_fixture <dir>
  local d="$1"; rm -rf "$d" "$d-rem.git"
  mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  # pre-push looks for the audit HERE; without it the hook refuses for an
  # unrelated reason and every case below would pass while testing nothing.
  # That exact fixture gap produced a false refutation of this finding during
  # triage, so the fixture is built to reach the scan rather than to fail early.
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # Seed the remote with a trunk so it is NOT empty. Pushing a spec branch is the
  # ordinary case of pushing to a repo that already has a trunk: the branch is
  # content-scanned but not trunk-audited. Since the F1 empty-remote fix
  # (plugin-2.0.0 leg), a branch pushed FIRST to an EMPTY remote is a trunk
  # candidate and IS audited, so these scan/toolchain controls -- which push spec
  # branches carrying role-path code -- would be refused as trunk on an empty
  # remote. That refusal is correct behaviour but not the false-denial these
  # controls exist to catch, so the fixture models the real scenario. The seed
  # push bypasses the hooks; it only needs to populate the remote's default ref.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
}
SCAN_SECRET='const token = "ghp_abcdefghijklmnop1234"'
SCAN_REF_BAD=""
SCAND="$WORK/scan-refs"; scan_ref_fixture "$SCAND"

# donor commits, each made without firing pre-commit, then carried onto a spec
# branch by a route git gives no hook for.
git -C "$SCAND" checkout -q -b donor1 main
printf '%s\n' "$SCAN_SECRET" > "$SCAND/src/leak1.js"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d1 >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0001-cherry main
git -C "$SCAND" cherry-pick donor1 >/dev/null 2>&1

git -C "$SCAND" checkout -q -b donor2 main
printf '%s\n' "$SCAN_SECRET" > "$SCAND/src/leak2.js"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d2 >/dev/null 2>&1
git -C "$SCAND" format-patch -1 donor2 -o "$WORK/scan-patches" >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0002-am main
git -C "$SCAND" am "$WORK"/scan-patches/*.patch >/dev/null 2>&1

git -C "$SCAND" checkout -q -b donor3 main
printf 'a %s b\n' "$EMDASH" > "$SCAND/note.md"
git -C "$SCAND" add -A >/dev/null 2>&1; git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm d3 >/dev/null 2>&1
git -C "$SCAND" checkout -q -b spec/0003-rebase donor3
git -C "$SCAND" rebase main >/dev/null 2>&1

for scan_ref in spec/0001-cherry spec/0002-am spec/0003-rebase; do
  if git -C "$SCAND" push -q origin "$scan_ref" >/dev/null 2>&1; then
    SCAN_REF_BAD="$SCAN_REF_BAD $scan_ref(pushed)"
  fi
done
if [[ -z "$SCAN_REF_BAD" ]]; then
  ok "scan refs: a spec-branch push carrying cherry-picked, am-applied or rebased content is scanned and refused"
else
  bad "scan refs: a spec-branch push carrying cherry-picked, am-applied or rebased content is scanned and refused" \
      "these reached the remote unscanned:$SCAN_REF_BAD; the scan is inheriting the audit's trunk-only scope again"
fi

# THE CONTROL, and without it the assertion above is satisfied by a hook that
# refuses every push.
git -C "$SCAND" checkout -q -b spec/0004-clean main
printf 'ordinary work\n' > "$SCAND/src/ok.js"
git -C "$SCAND" add -A >/dev/null 2>&1
git -C "$SCAND" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
if git -C "$SCAND" push -q origin spec/0004-clean >/dev/null 2>&1; then
  ok "scan refs control: a CLEAN spec-branch push is still allowed"
else
  bad "scan refs control: a CLEAN spec-branch push is still allowed" \
      "ordinary work was refused, which is the false-denial direction and makes the refusals above meaningless"
fi

if gh_landed "$GHMC"; then
  ok "scan merge control: a clean closed spec still merges"
else
  bad "scan merge control: a clean closed spec still merges" "the scan refuses compliant work, which is the false-denial direction"
fi


# --- the refusal direction ---
# >>> SHARD-BEGIN scan-ref-refusal cost=27
if shard_region scan-ref-refusal; then
GH="$WORK/gh-open"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks a: merging an UNCLOSED spec onto the trunk is refused" "the merge landed"
else ok "git hooks a: merging an UNCLOSED spec onto the trunk is refused"; fi

# The stalled merge. git leaves the refused merge STAGED and prints "use 'git
# commit' to complete the merge", and that commit fires pre-commit rather than
# pre-merge-commit. Found by the oracle: without MERGE_HEAD handling in
# pre-commit, the operator is one git-suggested command from landing the merge
# that was just refused.
( cd "$GH" && GIT_EDITOR=true git commit -m "complete the merge" ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks b: completing the STALLED merge with a plain commit is refused" "the merge landed"
else ok "git hooks b: completing the STALLED merge with a plain commit is refused"; fi

# The squash. git fires no pre-merge-commit for it at all.
#
# THIS ASSERTION EVALUATED NOTHING UNTIL 2026-08-03 (1.1.0 adversarial review, F13).
# It ran `git merge --squash` inside a fixture that sets `merge.ff=false`, and
# git refuses that combination: `fatal: options '--squash' and '--no-ff.'
# cannot be used together`, exit 128. stderr went to /dev/null so the fatal was
# invisible, `&&` short-circuited so the commit never ran, SQUASH_MSG was never
# written, and pre-commit never fired. gh_landed was therefore false and the
# test took the `else ok` branch. The ONLY assertion covering pre-commit's
# expensive squash branch reported a pass over a command that never reached it,
# and pre-commit's own header calls that branch the sole reason it exists.
#
# The hook is fine; the test was not. Reached by a spelling that survives the
# shipped config, pre-commit prints "this commit completes a squash merge onto
# main" and refuses. So: use that spelling, and assert the POSITIVE evidence
# (SQUASH_MSG written, the refusal text printed) rather than only that nothing
# landed. This fixture's own control comment states the general lesson, "a
# fixture that failed to build reports every refusal case as a pass"; here a
# git command that fatals for an unrelated reason was indistinguishable from a
# hook refusal.
GH="$WORK/gh-squash"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff --squash spec/0001-thing && git commit -m "squashed" ) >"$GH.out" 2>&1
if [[ -f "$GH/.git/SQUASH_MSG" ]]; then
  ok "git hooks c0: the squash spelling under test actually reaches the hook (SQUASH_MSG written)"
else
  bad "git hooks c0: the squash spelling under test actually reaches the hook (SQUASH_MSG written)" \
      "git never staged a squash, so the refusal case below tests nothing: $(head -n1 "$GH.out")"
fi
if gh_landed "$GH"; then
  bad "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit" "the squash landed"
elif grep -q "SLH-CLOSES-NO-SPEC\|SLH-NO-CLOSING-REPORT" "$GH.out"; then
  ok "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit"
else
  bad "git hooks c: a SQUASH merge of an unclosed spec is refused at the commit" \
      "nothing landed, but no setlist refusal was printed either, so this is not evidence the hook ran: $(head -n1 "$GH.out")"
fi

# The ALLOW direction of the same branch, which did not exist and is why the
# vacuous case above survived: with only a refusal case, a squash that never
# runs looks exactly like a squash that is refused.
GH="$WORK/gh-squash-ok"; gh_fixture "$GH" yes
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --ff --squash spec/0001-thing && git commit -m "squashed" ) >"$GH.out" 2>&1
if gh_landed "$GH"; then
  ok "git hooks c2: a SQUASH merge of a CLOSED spec completes"
else
  bad "git hooks c2: a SQUASH merge of a CLOSED spec completes" \
      "the hook refused a compliant squash close: $(grep -o 'SLH-[A-Z-]*' "$GH.out" | sort -u | tr '\n' ' ')"
fi

# And the config consequence itself, named in the edition's Known limitations
# since 1.1.0: the plain spelling is FATAL in every stamped instance. Asserted
# so that if the stamp ever drops merge.ff, the documentation goes stale loudly.
GH="$WORK/gh-squash-ff"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --squash spec/0001-thing ) >"$GH.out" 2>&1
if grep -q "cannot be used together" "$GH.out"; then
  ok "git hooks c3: plain git merge --squash is fatal under the stamp's merge.ff=false, as Known limitations says"
else
  bad "git hooks c3: plain git merge --squash is fatal under the stamp's merge.ff=false, as Known limitations says" \
      "it did not fatal, so the edition's Known limitations bullet is now wrong: $(head -n1 "$GH.out")"
fi

# The fast-forward, which fires NO hook. This asserts the STAMP, not the hook:
# merge.ff=false is what turns this into a merge commit that pre-merge-commit
# can see. Measured at 11 of 60 oracle cases before the setting existed.
GH="$WORK/gh-ff"; gh_fixture "$GH" no
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge spec/0001-thing -m "ff" ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks d: merge.ff=false stops the fast-forward path (no hook fires for a real ff)" "it fast-forwarded onto the trunk"
else ok "git hooks d: merge.ff=false stops the fast-forward path (no hook fires for a real ff)"; fi

# Spelling immunity, which is the entire claim of the boundary move. The parser
# gates needed four releases to survive these; the hook never reads the command.
for gh_spell in \
  '{ nice -n 5 git merge --no-ff -m x spec/0001-thing; }' \
  '>/dev/null 2>&1 git merge --no-ff -m x refs/heads/spec/0001-thing' \
  'M=merge; git $M --no-ff -m x spec/0001-thing'; do
  GH="$WORK/gh-spell"; gh_fixture "$GH" no
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true bash -c "$gh_spell" ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks e: spelling [$gh_spell] is refused" "it landed"
  else ok "git hooks e: spelling [$gh_spell] is refused"; fi
done

# --- THE TRUNK SPELLING. The v1.7 dogfood gate's BLOCKER, and the reason this
# block exists at all.
#
# close-gate.sh learned in 1.0.8 that a trunk value must NAME A LOCAL BRANCH
# rather than merely be a non-empty string, and carries a 20-line comment saying
# why the reduction has to ask git instead of stripping prefixes. When v1.7 moved
# the guarantee to the git hooks, slh_trunk() got the non-empty-string half and
# not the reduction, so slh_on_trunk() compared "refs/remotes/origin/main"
# against the "main" that `symbolic-ref --short HEAD` returns, the two could
# never be equal, and pre-merge-commit took its exit 0 without evaluating its
# predicate. Five spellings landed unreviewed work on the trunk in total silence
# while close-gate.sh, the layer v1.7 DEMOTES to advisory, denied all of them.
#
# The route is not adversarial: `refs/remotes/origin/main` is what the upgrade
# skill's own detection command returns on every ordinary clone.
#
# Asserted in BOTH directions, because a trunk check that refuses everything is
# the other way to fail this. ---
for gh_tv in refs/remotes/origin/main refs/heads/main heads/main origin/main; do
  GH="$WORK/gh-trunkspell"; gh_fixture "$GH" no "$gh_tv"
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks t: trunk spelled [$gh_tv] still refuses an UNCLOSED spec" \
        "it landed, silently and at exit 0: a ref-path trunk disables the whole boundary"
  else ok "git hooks t: trunk spelled [$gh_tv] still refuses an UNCLOSED spec"; fi
done

for gh_tv in refs/remotes/origin/main refs/heads/main origin/main; do
  GH="$WORK/gh-trunkspell-ok"; gh_fixture "$GH" yes "$gh_tv"
  ( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then ok "git hooks u: trunk spelled [$gh_tv] still ALLOWS a properly closed spec"
  else bad "git hooks u: trunk spelled [$gh_tv] still ALLOWS a properly closed spec" \
           "the reduction made an ordinary compliant close impossible, which is the other way to fail"; fi
done

# A FENCED Closing report is not a Closing report, in the layer that now carries
# the guarantee. close-gate.sh strips fenced spans once before all four close
# checks (leg 5, F7); nothing in templates/git-hooks/ did, so the whole close
# passed on quoted example text (v1.7 gate, adversarial review F9).
GH="$WORK/gh-fenced"; gh_fixture "$GH" fenced
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks w: a Closing report that exists only inside a fence is REFUSED" \
      "it landed: quoted example text satisfied every close condition"
else ok "git hooks w: a Closing report that exists only inside a fence is REFUSED"; fi

# ===========================================================================
# THE FENCED TEMPLATE FALSE DENIAL (V19-F2), FIXED 2026-08-26 AND PINNED IN THE
# ACCEPT DIRECTION.
#
# pre-commit's lifecycle detector used to read the RAW staged diff:
#   grep -qE "^\+Status:[[:space:]]*(STATES)|^\+#+[[:space:]]*Closing report"
# with no fence handling and no indent allowance. So a spec that QUOTED the
# closing-report template, changing no lifecycle state of its own, read as a
# real close and was refused SLH-STATUS-MISSING: a CONFIRMED FALSE DENIAL, it
# refused honest work. The mirror of the same regex missed an INDENTED heading
# entirely, while the three sibling readers accept it.
#
# The detector now asks slh_lifecycle_added, which strips template quotes with
# the shared SLH_TEMPLATE_FENCE_AWK and matches the shared
# SLH_CLOSING_REPORT_RE, so the fourth reader agrees with the other three (A9).
# These assertions were watched RED against the pre-fix bytes in both
# directions before the fix landed: fenced-template REFUSED and mirror-indented
# LANDED, while both controls held. THIS BLOCK IS NOW THE REGRESSION PIN: if the
# fence handling is ever lost, the first subject goes red again.
#
# Every case stages a file under specs/ and does NOT stage specs/STATUS.md. The
# discriminating variable is the CONTENT and nothing else, which is what makes
# the subject readable: a first cut of this measurement varied the PATH too and
# "reproduced" nothing.
f2_fixture() { # f2_fixture <dir> -- an armed instance sitting on the trunk
  local d="$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}

f2_commits() { # f2_commits <label> <spec-body> -> 0 if the commit LANDED
  local d="$WORK/f2-$1"
  f2_fixture "$d"
  printf '%s' "$2" > "$d/specs/9001-case.md"
  git -C "$d" add specs/9001-case.md >/dev/null 2>&1
  git -C "$d" commit -qm "docs: $1" >/dev/null 2>&1
}

# CONTROL a (the allow direction): an ordinary spec edit that moves no lifecycle
# state must COMMIT. Without this the refusals below would pass against a hook
# that refuses everything.
if f2_commits control-quiet '# Spec 9001

Ordinary prose about a spec that is not closing.
'; then
  ok "f2 control a: an ordinary spec edit that moves no lifecycle state commits"
else
  bad "f2 control a: an ordinary spec edit that moves no lifecycle state commits" \
      "the hook refused a spec edit with no lifecycle line, so every refusal below proves nothing"
fi

# CONTROL b (the deny direction): a REAL close without specs/STATUS.md staged
# must be REFUSED. This is the behaviour the detector exists for.
if f2_commits control-realclose '# Spec 9001

Status: CLOSED

## Closing report

Architecture diagram: no impact
'; then
  bad "f2 control b: a REAL close without specs/STATUS.md staged is refused" \
      "it committed, so the harness cannot observe this refusal and the subject below is unreadable"
else
  ok "f2 control b: a REAL close without specs/STATUS.md staged is refused"
fi

# THE SUBJECT. A quotation of the template, inside a fence, changing nothing.
if f2_commits fenced-template '# Spec 9001

This spec is ACTIVE. It shows readers what a closing report looks like:

```markdown
Status: CLOSED

## Closing report

Architecture diagram: no impact
```

Nothing above is this spec own lifecycle state: it is a quotation.
'; then
  ok "V19-F2 fixed: a FENCED quotation of the close template commits"
else
  bad "V19-F2 fixed: a FENCED quotation of the close template commits" \
      "it was REFUSED. The false denial is back: the detector has stopped stripping template quotes, and honest authoring that copies the shipped template is being refused SLH-STATUS-MISSING"
fi

# THE MIRROR DEFECT, same finding, opposite direction: an INDENTED heading was
# not matched at all, while the release's three other readers accept
# "^ {0,3}#{1,6}[ \t]+Closing report". Isolated to the indent by a control that
# differs in nothing else, because the first cut of this case carried a Status
# line too and so proved nothing about indentation. Now REFUSED, like its
# unindented sibling below and like the other three readers.
if f2_commits mirror-indented '# Spec 9001

  ## Closing report

Architecture diagram: no impact
'; then
  bad "V19-F2 mirror fixed: an INDENTED closing-report heading IS seen by this detector" \
      "it committed, so the detector has gone back to the column-anchored regex and disagrees with the three sibling readers about what a heading is"
else
  ok "V19-F2 mirror fixed: an INDENTED closing-report heading IS seen by this detector"
fi
if f2_commits mirror-control '# Spec 9001

## Closing report

Architecture diagram: no impact
'; then
  bad "f2 mirror control: an UNINDENTED closing-report heading IS seen" \
      "it committed, so the indent case above is not discriminating: the detector is missing the heading for some other reason"
else
  ok "f2 mirror control: an UNINDENTED closing-report heading IS seen"
fi

# THE GUARANTEE LAYER ALSO DEPENDS ON THE TOOLCHAIN, and F2 measured this half
# separately: with grep broken, the git hooks landed the merge at rc=0 in silence
# while broken awk, sed and tr still refused. The library's banner promises
# "EVERYTHING HERE FAILS CLOSED", so it owes the same probe the Bash gates now
# carry. Driven through a REAL merge on a shimmed PATH, not by calling the
# library, because what is being asserted is that git's invocation of the hook
# fails closed.
for bt in awk sed tr grep; do
  build_brokentool_bin "$bt"
  GH="$WORK/gh-toolchain"; gh_fixture "$GH" no
  ( cd "$GH" && PATH="$BROKENTOOL_BIN" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true \
      git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$GH"; then
    bad "git hooks x: the git hooks REFUSE when $bt is broken" \
        "it landed: the layer v1.7 makes the guarantee failed OPEN on a broken $bt"
  else ok "git hooks x: the git hooks REFUSE when $bt is broken"; fi
done

# A trunk that resolves to NOTHING must refuse rather than pass. The library's
# own banner promises "EVERYTHING HERE FAILS CLOSED", and the upgrade skill tells
# the reader the hooks "refuse a trunk that names no local branch".
GH="$WORK/gh-trunk-nobranch"; gh_fixture "$GH" no "no-such-branch"
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks v: a trunk naming NO local branch REFUSES rather than passing" \
      "it landed: the gate could not establish which branch it protects and allowed the merge anyway"
else ok "git hooks v: a trunk naming NO local branch REFUSES rather than passing"; fi

# --- the ALLOW direction, which is what stops this being a hook that refuses
# everything. Two of this repo's own bypasses were closed by making a gate
# unusable, so the positive case is not optional. ---
GH="$WORK/gh-closed"; gh_fixture "$GH" yes
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks f: a properly CLOSED spec still merges"
else bad "git hooks f: a properly CLOSED spec still merges" "a compliant close was refused"; fi

# Merging the TRUNK INTO a spec branch is how a long branch keeps up. It is not
# a close and must not be gated, or the ordinary workflow becomes impossible.
GH="$WORK/gh-into"; gh_fixture "$GH" no
( cd "$GH" && printf 'trunkside\n' > src/t.txt && git add -A && SETLIST_SKIP_HOOKS=1 git commit -qm trunkside ) >/dev/null 2>&1
( cd "$GH" && git checkout -q spec/0001-thing && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "catch up" main ) >/dev/null 2>&1
if [[ -f "$GH/src/t.txt" ]]; then ok "git hooks g: merging the trunk INTO a spec branch is not gated"
else bad "git hooks g: merging the trunk INTO a spec branch is not gated" "the catch-up merge was refused"; fi

# The documented escape hatch, and the non-instance case.
GH="$WORK/gh-skip"; gh_fixture "$GH" no
( cd "$GH" && SETLIST_SKIP_HOOKS=1 GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks h: SETLIST_SKIP_HOOKS=1 is a real, documented bypass"
else bad "git hooks h: SETLIST_SKIP_HOOKS=1 is a real, documented bypass" "the escape hatch did not work"; fi

GH="$WORK/gh-noinst"; gh_fixture "$GH" no; rm -f "$GH/.claude/sdd.json"
( cd "$GH" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then ok "git hooks i: a repo that is not a framework instance is untouched"
else bad "git hooks i: a repo that is not a framework instance is untouched" "a non-instance merge was refused"; fi

# The library must REFUSE when it cannot be found, never pass. Same rule as
# pre-push d: a check that cannot run has not passed.
GH="$WORK/gh-nolib"; gh_fixture "$GH" yes; rm -f "$GH/.githooks/setlist-hook-lib.sh"
( cd "$GH" && env -u CLAUDE_PLUGIN_ROOT GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m x spec/0001-thing ) >/dev/null 2>&1
if gh_landed "$GH"; then
  bad "git hooks j: a hook that cannot find its library REFUSES rather than passing" "it passed with no library"
else ok "git hooks j: a hook that cannot find its library REFUSES rather than passing"; fi

# THE DIAGRAM FIELD IS FIRST-LINE-WINS (KL1, ruled 2026-08-29 and shipped in
# 2.3.0; the public bullet left the list in spec 0126's public-list commit,
# worded fix-plus-correction because the bullet still described last-wins a
# day after the mechanics shipped first-wins). This replaces the old
# either-way "documented hole" pin, whose fixture named the field MID-LINE
# and so never exercised the anchored reader in either generation: a pin that
# passes both ways on an input the reader cannot see is the vacuous-comparison
# class, recorded here so it is not reinvented. Both directions, ANCHORED:
# a later bullet that repeats the label neither unanswers a real field nor
# answers a placeholder one.
DIAGN="$WORK/diag-note"; rm -rf "$DIAGN"; close_fixture "$DIAGN" yes yes answered yes no true
git -C "$DIAGN" checkout -q spec/0001-thing
printf -- '- Architecture diagram: <updated in this commit | no impact>\n' >> "$DIAGN/specs/0001-thing.md"
git -C "$DIAGN" add -A >/dev/null 2>&1
git -C "$DIAGN" commit -qm "an anchored later bullet repeating the label" >/dev/null 2>&1
git -C "$DIAGN" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$DIAGN" "$(bash_payload "$MERGE_CMD")"
if [[ -z "$HOOK_OUT" ]]; then
  ok "diagram first-wins a: an anchored later placeholder bullet cannot UNANSWER a real field (KL1's refuse direction, closed)"
else
  bad "diagram first-wins a: an anchored later placeholder bullet cannot UNANSWER a real field (KL1's refuse direction, closed)" \
      "the merge was denied, so a later line is deciding the field again; KL1's class is back"
fi
DIAGN2="$WORK/diag-note2"; rm -rf "$DIAGN2"; close_fixture "$DIAGN2" yes yes unanswered yes no true
git -C "$DIAGN2" checkout -q spec/0001-thing
printf -- '- Architecture diagram: no impact\n' >> "$DIAGN2/specs/0001-thing.md"
git -C "$DIAGN2" add -A >/dev/null 2>&1
git -C "$DIAGN2" commit -qm "an anchored later bullet answering for the field" >/dev/null 2>&1
git -C "$DIAGN2" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$DIAGN2" "$(bash_payload "$MERGE_CMD")"
if [[ -z "$HOOK_OUT" ]]; then
  bad "diagram first-wins b: an anchored later answering bullet cannot ANSWER a placeholder field (KL1's publish direction, closed)" \
      "the merge was allowed, so a later line answered a field nobody answered; KL1's class is back"
else
  ok "diagram first-wins b: an anchored later answering bullet cannot ANSWER a placeholder field (KL1's publish direction, closed)"
fi

# THE ESCAPE pre-push READS (the 2.5.0 leg, F7; the case was written at the v1.7
# second bound leg for the OPPOSITE fact and then, when 2.2.0's pre-push started
# honouring the variable, was left reporting ok on BOTH arms, so for four
# releases it pinned nothing while the public bullet went on saying the escape
# was inert at push). It is a real pin now, in the documented direction: with
# SETLIST_SKIP_HOOKS=1 the refused push LANDS (the whole-hook escape), and with
# SETLIST_SKIP_TRUNK_AUDIT=1, the narrow one, the same secret-carrying push is
# still refused by the content scan. BEHAVIOURAL, because the first version of
# this assertion grepped the source for the NAME and reported the hole closed: a
# mention is not a read, and a pattern match cannot tell them apart.
SKIPE="$WORK/skip-escape"; rm -rf "$SKIPE" "$SKIPE-rem.git"
scan_ref_fixture "$SKIPE"
git -C "$SKIPE" checkout -q -b spec/0007-esc main
printf '%s\n' "$SCAN_SECRET" > "$SKIPE/src/leak.js"
git -C "$SKIPE" add -A >/dev/null 2>&1
git -C "$SKIPE" -c core.hooksPath=/dev/null commit -qm leak >/dev/null 2>&1
if git -C "$SKIPE" push -q origin spec/0007-esc >/dev/null 2>&1; then
  bad "skip escape control: the push is refused without the escape" \
      "the push succeeded with no escape set, so the case below proves nothing"
else
  ok "skip escape control: the push is refused without the escape"
  if SETLIST_SKIP_TRUNK_AUDIT=1 git -C "$SKIPE" push -q origin spec/0007-esc >/dev/null 2>&1; then
    bad "skip escape narrow: SETLIST_SKIP_TRUNK_AUDIT=1 skips the audit ALONE, and the content scan still refuses the secret" \
        "the push landed under the narrow escape, so the content scan did not run; the bullet says it does"
  else
    ok "skip escape narrow: SETLIST_SKIP_TRUNK_AUDIT=1 skips the audit ALONE, and the content scan still refuses the secret"
  fi
  if SETLIST_SKIP_HOOKS=1 git -C "$SKIPE" push -q origin spec/0007-esc >/dev/null 2>&1; then
    ok "skip escape: SETLIST_SKIP_HOOKS=1 gets the refused push through, the whole-hook escape the bullet now describes"
  else
    bad "skip escape: SETLIST_SKIP_HOOKS=1 gets the refused push through, the whole-hook escape the bullet now describes" \
        "the push was still refused under the escape; pre-push no longer honours it, and the bullet, its ledger row and this case must move together"
  fi
fi

# ===========================================================================
# THE CHAINED MERGE (v1.7 claims round 4, F1), and the catch-up control.
#
# A close authorises the code riding with it, and "riding with it" used to be
# unbounded: unspecced role-path code merged INTO a spec branch, then that
# branch merged onto the trunk with a fully compliant close, reached the REMOTE
# with both layers reporting clean. Classified by replay as a GUARANTEE-layer
# falsification (unspecced code on the remote trunk), not a scan hole, so it was
# fixed under the standing amendment rather than documented.
#
# The third case is the one that matters most: merging the trunk INTO a spec
# branch is ordinary work, and a fix that refused it would be the false denial
# this repository treats as worse than the bypass.
fi; shard_region_end
# <<< SHARD-END scan-ref-refusal
chain_fixture() { # chain_fixture <dir>
  local d="$1"; rm -rf "$d"
  mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  git -C "$d" config merge.ff false
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | QUEUED | q |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
}
chain_close() { # chain_close <dir>
  local d="$1"
  printf 'export const legit = 1\n' > "$d/src/legit.js"
  printf '# Spec 0001 - First\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0001-first.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | First | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "spec 0001 + code" >/dev/null 2>&1
}
CHA="$WORK/chain-attack"; chain_fixture "$CHA"
git -C "$CHA" checkout -q -b junk main
printf 'export const sneaky = 1\n' > "$CHA/src/sneaky.js"
git -C "$CHA" add -A >/dev/null 2>&1; git -C "$CHA" commit -qm "sneaky, no spec" >/dev/null 2>&1
git -C "$CHA" checkout -q -b spec/0001-first main; chain_close "$CHA"
git -C "$CHA" merge -q --no-ff junk -m "merge junk into spec branch" >/dev/null 2>&1
git -C "$CHA" checkout -q main
git -C "$CHA" merge -q --no-ff -m "close 0001" spec/0001-first >/dev/null 2>&1
if bash "$SCRIPTS/trunk-audit.sh" "$CHA" >/dev/null 2>&1; then
  ok "chain a: KNOWN HOLE, a chained merge past a compliant close is reported clean, as Known limitations records"
else
  ok "chain a: a chained merge is refused again, which CLOSES a documented hole; re-run the two-clone assertion below and the ordinary-work controls, then move the bullet in the same commit"
fi

# A `<<\EOF` HEREDOC BODY IS READ AS CODE (leg F10), documented not fixed.
#
# The owner's decision on 2026-08-08 was to hold the v1.7 parser freeze and
# correct the documentation instead of widening hd_scan's delimiter class. This
# assertion exists because the ledger entry says "asserted", and because the day
# the freeze lifts, somebody needs to be told this closed.
#
# What made it worth a bullet rather than a shrug: it is not merely an absent
# warning. Through plugin 2.5.0 it RAN the project's gate command,
# synchronously, inside the PreToolUse hook, before an ordinary `git commit`,
# under the template's timeout 1800 for that entry.
#
# THE OBSERVABLE MOVED IN 2.6.0 (spec 0132 cluster C, the owner's ruling 1 on
# the 2.6.0 strategy): the close gate runs NO gate command in PreToolUse any
# more, so "ran the gate command" can no longer be the evidence that a body was
# read as code. The evidence is now the ADVISORY itself: a <<\EOF body naming a
# merge of a NON-compliant spec draws the close gate's verdict
# (CG-NO-CLOSING-REPORT) on a commit that merges nothing, and the quoted
# spelling draws none. The marker is asserted UNTOUCHED on every spelling, the
# real merge included, which is cluster C's own pin (watched red on 5825267,
# where the real merge touched it), and the public bullet lost its second
# clause in the same commit as this block.
#
# FOUR FIXTURES were needed to measure this, and the first three would each have
# produced a confidently wrong bullet: a non-existent merge operand
# short-circuited at CG-UNNAMEABLE-REF, a chore branch never reached the
# gate-command path at all, and a non-compliant spec was denied at
# CG-NO-CLOSING-REPORT first. Only a COMPLIANT spec reached the gate command, so
# only that fixture could see the run; the non-compliant branch is what sees
# the misreading now. The controls below are the reason that was caught rather
# than written up.
hd_fixture() { # hd_fixture <dir> <marker-path>
  local d="$1" mk="$2"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"touch %s","roles":{"src":"src"}}\n' "$mk" > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0100 | G | ACTIVE | a |\n| 0101 | B | ACTIVE | b |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm i >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0100-good
  printf 'export const g = 1\n' > "$d/src/g.js"
  printf '# Spec 0100\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\ncrit: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$d/specs/0100-good.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0100 | G | CLOSED | done |\n| 0101 | B | ACTIVE | b |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm w >/dev/null 2>&1
  git -C "$d" checkout -q main
  # The NON-compliant sibling: CLOSED with no Closing report, so a merge of it
  # (real or misread from a heredoc body) draws CG-NO-CLOSING-REPORT.
  git -C "$d" checkout -q -b spec/0101-bad
  printf 'export const b = 1\n' > "$d/src/b.js"
  printf '# Spec 0101\n\nStatus: CLOSED\n' > "$d/specs/0101-bad.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm b >/dev/null 2>&1
  git -C "$d" checkout -q main
}
# hd_ran <dir> <marker> <command> -> "YES"/"no": did the close gate run the gate command?
hd_ran() {
  rm -f "$2"
  printf %s "$(jq -nc --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}')" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/close-gate.sh" >/dev/null 2>&1
  [[ -f "$2" ]] && printf 'YES' || printf 'no'
}
# hd_code <dir> <command> -> the advisory code the close gate emitted, or "allow"
hd_code() {
  local out
  out="$(printf %s "$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  [[ -n "$out" ]] || { printf 'allow'; return 0; }
  printf '%s' "$out" | jq -r '.setlistAdvisory.code // "allow"' 2>/dev/null || printf 'unreadable'
}
HDD="$WORK/heredoc"; HDM="$WORK/heredoc-gate-ran"; hd_fixture "$HDD" "$HDM"
HD_CTL=""
[[ "$(hd_code "$HDD" 'git merge --no-ff spec/0101-bad')" == "CG-NO-CLOSING-REPORT" ]] || HD_CTL="$HD_CTL real-merge-of-the-bad-spec-not-advised"
[[ "$(hd_code "$HDD" 'git merge --no-ff spec/0100-good')" == "allow" ]] || HD_CTL="$HD_CTL real-merge-of-the-good-spec-not-allowed"
[[ "$(hd_code "$HDD" 'git commit -m "ordinary message"')" == "allow" ]] || HD_CTL="$HD_CTL plain-commit-advised"
if [[ -z "$HD_CTL" ]]; then
  ok "heredoc control: a real merge of a non-compliant spec is advised, a compliant one and a plain commit are not"
else
  bad "heredoc control: a real merge of a non-compliant spec is advised, a compliant one and a plain commit are not" \
      "the fixture proves nothing:$HD_CTL; the misreading is only visible on a NON-compliant merge target, which is what three earlier fixtures missed"
fi
# CLUSTER C's OWN PIN (2.6.0, ruling 1): no spelling runs the gate command in
# PreToolUse, the real merge of the compliant spec included. Red on 5825267:
# the real merge touched the marker there.
HD_RUN=""
[[ "$(hd_ran "$HDD" "$HDM" 'git merge --no-ff spec/0100-good')" == "no" ]] || HD_RUN="$HD_RUN real-merge-ran-it"
[[ "$(hd_ran "$HDD" "$HDM" 'git commit -m "ordinary message"')" == "no" ]] || HD_RUN="$HD_RUN plain-commit-ran-it"
[[ "$(hd_ran "$HDD" "$HDM" 'git commit -F - <<\EOF
git merge --no-ff spec/0100-good was reverted
EOF')" == "no" ]] || HD_RUN="$HD_RUN heredoc-body-ran-it"
if [[ -z "$HD_RUN" ]]; then
  ok "close gate (2.6.0, cluster C): the gate command is not run in PreToolUse on any spelling, the real merge included"
else
  bad "close gate (2.6.0, cluster C): the gate command is not run in PreToolUse on any spelling, the real merge included" \
      "the marker was touched by:$HD_RUN; the run left the close gate under the owner's ruling 1 and the git hook runs the close tier once"
fi
HD_BS="$(hd_code "$HDD" 'git commit -F - <<\EOF
git merge --no-ff spec/0101-bad was reverted
EOF')"
HD_Q="$(hd_code "$HDD" "git commit -F - <<'EOF'
git merge --no-ff spec/0101-bad was reverted
EOF")"
if [[ "$HD_BS" == "CG-NO-CLOSING-REPORT" && "$HD_Q" == "allow" ]]; then
  ok "heredoc: KNOWN HOLE, a <<\\EOF body is still read as a merge and draws the close verdict, as Known limitations records"
elif [[ "$HD_BS" == "allow" && "$HD_Q" == "allow" ]]; then
  ok "heredoc: a <<\\EOF body is no longer read as a merge, which CLOSES a documented hole; move the bullet and this ledger entry in the same commit"
else
  bad "heredoc: the quoted spelling must NOT be read as a merge" \
      "backslash=$HD_BS quoted=$HD_Q; the quoted form regressing means the parser got broader, not narrower, which is the direction the freeze exists to prevent"
fi

# THE REFRESH DISPLACES A FOREIGN HOOK LAYER IN SILENCE (leg F8 and F12).
#
# `git config core.hooksPath .githooks` ran unconditionally. Where a repository
# already pointed that at husky, lefthook or pre-commit, the previous value was
# not printed, not recorded and not backed up, and report mode said "git config
# still to set: core.hooksPath" while it WAS set, to something else that was
# about to be switched off. Measured: the identical `git commit` was refused by
# .husky/pre-commit before the refresh and committed cleanly after it.
#
# What is destroyed is often itself a control. gitleaks, detect-secrets and
# commit-msg validation are commonly wired exactly this way, so the failure mode
# is a project silently losing its secret scanning to a tool that arrived to add
# guarantees. git supports one hooksPath, so genuinely merging the layers is out
# of scope; the defect is that the displacement is INVISIBLE, not that it
# happens.
#
# F12 rides along because it is the same file and the same discipline: report
# what you are about to overwrite. trunk-audit.sh is a delivered file that
# appeared in no report, and the chmod globbed the whole directory rather than
# the four names the copy loop had just written.
# NOTE THE FLAG ORDER. The usage is `refresh-instance.sh [--apply] <dir>`, and
# the first cut of these assertions passed the flag AFTER the directory, so
# --apply was never parsed: every call aborted on a usage error. The "refuses to
# displace" case PASSED that way, vacuously, because core.hooksPath was left
# alone by a command that had done nothing at all. The control beside it failed
# and is the only reason it was caught.
rfi_fixture() { # rfi_fixture <dir> <existing-hookspath-or-empty>
  local d="$1" hp="$2"; rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  if [[ -n "$hp" ]]; then
    mkdir -p "$d/$hp"
    printf '#!/bin/sh\necho "foreign hook refusing"\nexit 1\n' > "$d/$hp/pre-commit"
    chmod +x "$d/$hp/pre-commit"
    git -C "$d" config core.hooksPath "$hp"
  fi
}

# REPORT MODE must NAME the value it is about to displace.
RFI="$WORK/rfi-report"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" "$RFI" >"$WORK/rfi-report.out" 2>&1
if grep -q '\.husky' "$WORK/rfi-report.out"; then
  ok "refresh a: report mode names the foreign core.hooksPath it would displace"
else
  bad "refresh a: report mode names the foreign core.hooksPath it would displace" \
      "the report never mentioned .husky, and said [$(grep -oE 'git config still to set:[^(]*' "$WORK/rfi-report.out" | head -1)], which reads as unconfigured rather than configured to something else"
fi

# --apply must NOT silently switch a foreign layer off.
RFI="$WORK/rfi-apply"; rfi_fixture "$RFI" .husky
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-apply.out" 2>&1
RFI_NOW="$(git -C "$RFI" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: an unreadable value is not .husky and fails the check below
if [[ "$RFI_NOW" == ".husky" ]] || grep -qE 'refus|REFUS' "$WORK/rfi-apply.out"; then
  ok "refresh b: --apply refuses rather than switching a foreign hook layer off in silence"
else
  bad "refresh b: --apply refuses rather than switching a foreign hook layer off in silence" \
      "core.hooksPath went from .husky to [$RFI_NOW] with no refusal; what was displaced is often itself a control (gitleaks, detect-secrets, commit-msg validation)"
fi

# THE DELIBERATE OVERRIDE MUST STILL WORK. Refusing is only defensible if the
# operator has a one-step way to say "yes, displace it, I know". Without this
# the fix trades a silent destruction for a dead end.
RFI="$WORK/rfi-adopt"; rfi_fixture "$RFI" .husky
SETLIST_ADOPT_HOOKSPATH=1 bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-adopt.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh d: SETLIST_ADOPT_HOOKSPATH=1 displaces the foreign layer on purpose"
else
  bad "refresh d: SETLIST_ADOPT_HOOKSPATH=1 displaces the foreign layer on purpose" \
      "the escape did not work, so the refusal above is a dead end rather than a decision point"
fi

# CONTROL: an ordinary instance, no foreign layer, must still be armed.
RFI="$WORK/rfi-plain"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-plain.out" 2>&1
if [[ "$(git -C "$RFI" config --get core.hooksPath 2>/dev/null)" == ".githooks" ]]; then
  ok "refresh control: an instance with no foreign hooksPath is still armed by --apply"
else
  bad "refresh control: an instance with no foreign hooksPath is still armed by --apply" \
      "the ordinary path stopped arming, which is the false-denial direction and worse than the hole above"
fi

# F6 of the 2026-08-11 leg: THE GUARD DECIDED BY NAME, NOT BY WHAT IS THERE.
# `case "$FOREIGN_HOOKSPATH" in ""|".githooks") FOREIGN_HOOKSPATH="" ;; esac`
# read ".githooks" as "already ours", but .githooks is the CONVENTIONAL name
# for a tracked hooks directory and nothing about the name makes the hooks in
# it Setlist's. A project whose own gitleaks-style layer lived there was
# displaced with neither the refusal nor the warning the README promises, which
# is the exact before-and-after this fix's own comment cites as its reason.
RFI="$WORK/rfi-githooks-foreign"; rfi_fixture "$RFI" .githooks
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-gh.out" 2>&1
RFI_GH_SURVIVED=0
grep -q 'foreign hook refusing' "$RFI/.githooks/pre-commit" 2>/dev/null && RFI_GH_SURVIVED=1
if grep -qE 'refus|REFUS|DISPLACE' "$WORK/rfi-gh.out" && [[ "$RFI_GH_SURVIVED" -eq 1 ]]; then
  ok "refresh F6a: a FOREIGN hook layer living at .githooks is refused, not silently displaced"
else
  bad "refresh F6a: a FOREIGN hook layer living at .githooks is refused, not silently displaced" \
      "no refusal was printed (survived=$RFI_GH_SURVIVED); the project's own pre-commit was switched off by name alone, and what gets displaced is frequently itself a control"
fi

# THE FALSE-DENIAL DIRECTION, which matters more than the hole: an instance
# whose .githooks really does hold Setlist's own hooks is the ORDINARY
# re-refresh, and it must not start reading as a foreign layer.
RFI="$WORK/rfi-githooks-ours"; rfi_fixture "$RFI" ""
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >/dev/null 2>&1
bash "$SCRIPTS/refresh-instance.sh" --apply "$RFI" >"$WORK/rfi-ghours.out" 2>&1
if grep -qE 'REFUS|WOULD DISPLACE' "$WORK/rfi-ghours.out"; then
  bad "refresh F6b: re-refreshing an instance armed by Setlist is not a displacement" \
      "the second --apply refused its own hooks, which would make every upgrade a dead end"
else
  ok "refresh F6b: re-refreshing an instance armed by Setlist is not a displacement"
fi


