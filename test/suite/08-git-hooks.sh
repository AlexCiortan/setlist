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

# Shared with later regions and shards (spec 0168, item 2): defined above the region, so a
# shard that does not own it still has them.
SECRET_LINE='const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";'
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

# >>> SHARD-BEGIN git-hooks-early-08 cost=9
# A prelude block moved into a measured region (spec 0168, item 2): independent both ways, measured.
if shard_region git-hooks-early-08; then

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

# audit age e (spec 0180, 0174's E-e as the validator ruled it): the octopus refusal is a 2.11.0
# rule, so it is dated as 0174's arms and 0175's reader are, by the plugin.version the merge's OWN
# tree stamps (rule_in_force), with post_baseline beside it. A post-adoption octopus of two docs
# branches made under 2.10.0 was accepted when it was made and must not refuse the upgraded
# instance's every push; the same octopus made under 2.11.0 is refused by name. Watched RED on the
# pre-fix audit (the 2.10.0 octopus refused SLH-OCTOPUS-MERGE).
tae_octo() { # tae_octo <dir> <plugin.version in the merge's tree>
  local d="$1" v="$2"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/docs"
  git_init "$d"
  jq -n --arg v "$v" '{trunk:"main",scaffolded:true,gate_command:"true",roles:{src:"src",tests:"tests"},plugin:{version:$v}}' > "$d/.claude/sdd.json"
  printf 'x\n' > "$d/src/app.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "stamp: adopt the rules" >/dev/null 2>&1
  local base; base="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -b docs/a "$base"; mkdir -p "$d/docs"; printf 'a\n' > "$d/docs/a.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "docs: a" >/dev/null 2>&1
  git -C "$d" checkout -q -b docs/b "$base"; mkdir -p "$d/docs"; printf 'b\n' > "$d/docs/b.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "docs: b" >/dev/null 2>&1
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff --no-verify -m "an octopus of two docs branches" docs/a docs/b >/dev/null 2>&1
}
TAE="$WORK/ta-octo-dated"
tae_octo "$TAE" 2.10.0
if [ "$(git -C "$TAE" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" != "4" ]; then
  bad "audit age e: a post-adoption octopus made under 2.10.0 (its own tree) is not refused by a 2.11.0 rule" "fixture error: the octopus folded"
elif bash "$ROOT/scripts/trunk-audit.sh" "$TAE" >"$WORK/tae.out" 2>&1; then
  ok "audit age e: a post-adoption octopus made under 2.10.0 (its own tree) is not refused by a 2.11.0 rule"
else
  bad "audit age e: a post-adoption octopus made under 2.10.0 (its own tree) is not refused by a 2.11.0 rule" \
      "the audit refused history made before the rule existed: $(grep -E 'VIOLATION|SLH-' "$WORK/tae.out" | head -n2 | tr '\n' ' ' | cut -c1-240)"
fi
tae_octo "$TAE" 2.11.0
if bash "$ROOT/scripts/trunk-audit.sh" "$TAE" >"$WORK/tae.out" 2>&1; then
  bad "audit age e: the same octopus made under 2.11.0 is refused by name (SLH-OCTOPUS-MERGE)" "the audit accepted it"
elif grep -q 'SLH-OCTOPUS-MERGE' "$WORK/tae.out"; then
  ok "audit age e: the same octopus made under 2.11.0 is refused by name (SLH-OCTOPUS-MERGE)"
else
  bad "audit age e: the same octopus made under 2.11.0 is refused by name (SLH-OCTOPUS-MERGE)" \
      "refused, but not by name: $(grep -E 'VIOLATION' "$WORK/tae.out" | head -n2 | tr '\n' ' ' | cut -c1-240)"
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
# (SECRET_LINE is defined above region git-hooks-early-08.)

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
# (scan_ref_fixture and SCAN_SECRET are defined above region git-hooks-early-08.)
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
fi; shard_region_end
# <<< SHARD-END git-hooks-early-08


# --- the refusal direction ---
# >>> SHARD-BEGIN scan-ref-refusal cost=30
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

# THE SCANS AND THE ALIAS AT THE GIT-HOOK LAYER (spec 0146, 0144's escalation E-g). Two
# public bullets were pinned only through the session gates 2.8.0 removed; these cases
# pin what the git hooks themselves do, measured first on a scratch instance. Each is
# decided by the refusal code AND by whether the commit or merge landed, so a hook that
# refuses for an unrelated reason cannot pass it.
OIX="$WORK/gh-own-index"; gh_fixture "$OIX" no
git -C "$OIX" config core.hooksPath .githooks
cp "$OIX/.git/index" "$WORK/gh-own-index-alt.index"
printf 'a %s b\n' "$(printf '\342\200\224')" > "$OIX/alt.md"
GIT_INDEX_FILE="$WORK/gh-own-index-alt.index" git -C "$OIX" add alt.md >/dev/null 2>&1
OIX_OUT="$(GIT_INDEX_FILE="$WORK/gh-own-index-alt.index" git -C "$OIX" commit -qm "alt index" 2>&1)"
if [[ "$(git -C "$OIX" log -1 --format=%s)" != "alt index" ]] && printf '%s' "$OIX_OUT" | grep -q 'SLH-EMDASH'; then
  ok "own index a: a commit through GIT_INDEX_FILE is scanned by pre-commit and refused (SLH-EMDASH)"
else
  bad "own index a: a commit through GIT_INDEX_FILE is scanned by pre-commit and refused (SLH-EMDASH)" \
      "last commit: $(git -C "$OIX" log -1 --format=%s); output: $(printf '%s' "$OIX_OUT" | head -c 200)"
fi
git_init "$OIX/nested" >/dev/null 2>&1
printf 'a %s b\n' "$(printf '\342\200\224')" > "$OIX/nested/n.md"
git -C "$OIX/nested" add n.md >/dev/null 2>&1
if git -C "$OIX/nested" commit -qm "nested" >/dev/null 2>&1; then
  ok "own index b: a git -C commit into a nested repository runs that repository's hooks, so this project's scan does not read it (documented hole, still open)"
else
  bad "own index b: a git -C commit into a nested repository runs that repository's hooks, so this project's scan does not read it (documented hole, still open)" \
      "the nested commit was refused, which CLOSES the hole the bullet names; update the bullet and this ledger entry"
fi
ALX="$WORK/gh-alias"; gh_fixture "$ALX" no
git -C "$ALX" config core.hooksPath .githooks
git -C "$ALX" branch alias-of-thing spec/0001-thing
git -C "$ALX" checkout -q spec/0001-thing
printf 'more\n' > "$ALX/src/MORE.txt"
git -C "$ALX" add -A >/dev/null 2>&1; git -C "$ALX" commit -qm "spec advances" >/dev/null 2>&1
git -C "$ALX" checkout -q main
ALX_OUT="$(cd "$ALX" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "merge the alias" alias-of-thing 2>&1)"
if ! git -C "$ALX" cat-file -e main:src/FEATURE.txt 2>/dev/null && printf '%s' "$ALX_OUT" | grep -q 'SLH-CLOSES-NO-SPEC'; then
  ok "alias close a: an alias of an unclosed spec branch, merged after the branch advances, is refused by pre-merge-commit (SLH-CLOSES-NO-SPEC)"
else
  bad "alias close a: an alias of an unclosed spec branch, merged after the branch advances, is refused by pre-merge-commit (SLH-CLOSES-NO-SPEC)" \
      "main carries src/FEATURE.txt: $(git -C "$ALX" cat-file -e main:src/FEATURE.txt 2>/dev/null && echo yes || echo no); output: $(printf '%s' "$ALX_OUT" | head -c 200)"
fi
( cd "$ALX" && git merge --abort >/dev/null 2>&1 ) || true

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

# Shared with later shards (spec 0168, item 2): defined above the region.
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

# >>> SHARD-BEGIN chain-refresh-08 cost=3
# A prelude block moved into a measured region (spec 0168, item 2): independent both ways, measured.
if shard_region chain-refresh-08; then
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
# (rfi_fixture is defined above region chain-refresh-08: later shards call it.)

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
fi; shard_region_end
# <<< SHARD-END chain-refresh-08



# >>> SHARD-BEGIN scan-bytes-0164 cost=6
if shard_region scan-bytes-0164; then
# =============================================================================
# THE CONTENT SCANS READ BYTES, NOT CHARACTERS (spec 0164, fix round 1, the
# 2.10.0 cold run's F-b). Measured on this project's own release candidate and on
# the published 2.9.0 hooks, identically: under a UTF-8 locale the macOS system
# awk (BWK, 20200816) aborts on an added line holding a byte that is not valid
# UTF-8 ("awk: towc: multibyte conversion failure"), the scans fail closed with
# SLH-SCAN-FILTER-FAILED, and pre-commit, pre-merge-commit and pre-push each
# refuse a file with a Latin-1 byte in it. The push added a false reason ("the
# history being pushed carries content the commit-time scans never saw").
#
# Every git call below runs under an explicit UTF-8 locale, because the suite
# inherits its caller's and a C locale would hide the defect. Where the host has
# no such locale, or its awk reads invalid bytes without aborting (GNU awk,
# mawk), the cases still assert the allow direction and the controls; the red
# was watched on BWK awk.
#
# Both directions: the byte is scanned, not refused; a secret or an em-dash in
# the same file, and on the same line as the byte, is still refused.
# =============================================================================
SB_U8="en_US.UTF-8"
SB_LATIN="$(printf 'caf\351 cr\350me\n')"

SBC="$WORK/sb-commit"; gh_fixture "$SBC" yes
printf '%s\n' "$SB_LATIN" > "$SBC/src/notes.txt"
git -C "$SBC" add src/notes.txt >/dev/null 2>&1
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBC" commit -qm "latin-1 notes" >"$WORK/sb-commit.out" 2>&1; then
  ok "scan bytes a: pre-commit scans a line holding a byte that is not valid UTF-8, and commits it"
else
  bad "scan bytes a: pre-commit scans a line holding a byte that is not valid UTF-8, and commits it" \
      "refused: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-commit.out" | tr '\n' ' ' | cut -c1-200)"
fi

SBS="$WORK/sb-secret"; gh_fixture "$SBS" yes
{ printf '%s\n' "$SB_LATIN"; printf '%s\n' "$SECRET_LINE"; } > "$SBS/src/notes.txt"
git -C "$SBS" add src/notes.txt >/dev/null 2>&1
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBS" commit -qm "latin-1 and a secret" >"$WORK/sb-secret.out" 2>&1; then
  bad "scan bytes b: a secret in the same file as the byte is still refused" "the commit landed a secret-shaped line"
elif grep -q 'SLH-SECRET' "$WORK/sb-secret.out"; then
  ok "scan bytes b: a secret in the same file as the byte is still refused, by SLH-SECRET"
else
  bad "scan bytes b: a secret in the same file as the byte is still refused" \
      "refused, but not by SLH-SECRET: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-secret.out" | tr '\n' ' ' | cut -c1-200)"
fi

SBL="$WORK/sb-sameline"; gh_fixture "$SBL" yes
printf 'caf\351 const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";\n' > "$SBL/src/notes.txt"
git -C "$SBL" add src/notes.txt >/dev/null 2>&1
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBL" commit -qm "same line" >"$WORK/sb-sameline.out" 2>&1; then
  bad "scan bytes c: a secret on the same line as the byte is still refused" "the commit landed a secret-shaped line"
elif grep -q 'SLH-SECRET' "$WORK/sb-sameline.out"; then
  ok "scan bytes c: a secret on the same line as the byte is still refused, by SLH-SECRET"
else
  bad "scan bytes c: a secret on the same line as the byte is still refused" \
      "refused, but not by SLH-SECRET: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-sameline.out" | tr '\n' ' ' | cut -c1-200)"
fi

SBE="$WORK/sb-emdash"; gh_fixture "$SBE" yes
printf 'caf\351 then a dash \342\200\224 here\n' > "$SBE/src/notes.txt"
git -C "$SBE" add src/notes.txt >/dev/null 2>&1
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBE" commit -qm "emdash" >"$WORK/sb-emdash.out" 2>&1; then
  bad "scan bytes d: an em-dash beside the byte is still refused" "the commit landed an em-dash"
elif grep -q 'SLH-EMDASH' "$WORK/sb-emdash.out"; then
  ok "scan bytes d: an em-dash beside the byte is still refused, by SLH-EMDASH"
else
  bad "scan bytes d: an em-dash beside the byte is still refused" \
      "refused, but not by SLH-EMDASH: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-emdash.out" | tr '\n' ' ' | cut -c1-200)"
fi

# The merge path: pre-merge-commit scans the merge's content with the same code.
SBM="$WORK/sb-merge"; gh_fixture "$SBM" yes
git -C "$SBM" checkout -q spec/0001-thing
printf '%s\n' "$SB_LATIN" > "$SBM/src/notes.txt"
git -C "$SBM" add -A >/dev/null 2>&1
git -C "$SBM" -c core.hooksPath=/dev/null commit -qm "latin-1 on the branch" >/dev/null 2>&1
git -C "$SBM" checkout -q main
( cd "$SBM" && LC_ALL="$SB_U8" LANG="$SB_U8" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >"$WORK/sb-merge.out" 2>&1
if git -C "$SBM" cat-file -e main:src/notes.txt 2>/dev/null; then
  ok "scan bytes e: pre-merge-commit scans the byte and the merge lands"
else
  bad "scan bytes e: pre-merge-commit scans the byte and the merge lands" \
      "refused: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-merge.out" | tr '\n' ' ' | cut -c1-200)"
fi

# The push path: the same bytes reach a remote, and a refusal that is about
# the content still says so.
sb_push_fixture() { # sb_push_fixture <dir> <file-content-printf-format>
  local d="$1" fmt="$2"
  gh_fixture "$d" yes
  cp "$ROOT/templates/git-hooks/pre-push" "$d/.githooks/pre-push"; chmod +x "$d/.githooks/pre-push"
  # pre-push refuses before any scan when it cannot find the audit, so the
  # fixture delivers it where the stamp does; without it every push case here
  # would read red or green for that reason and not for the one it names.
  mkdir -p "$d/.claude/hooks"; cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" checkout -q main
  # A NON-ROLE path: a direct commit of role code on the trunk is the audit's
  # own refusal, which is not what these cases are about.
  mkdir -p "$d/docs"
  # shellcheck disable=SC2059
  printf "$fmt" > "$d/docs/notes.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "notes" >/dev/null 2>&1
  rm -rf "$d-rem.git"; git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git" >/dev/null 2>&1
}
SBP="$WORK/sb-push"; sb_push_fixture "$SBP" 'caf\351 cr\350me\n'
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBP" push -q origin main >"$WORK/sb-push.out" 2>&1; then
  ok "scan bytes f: pre-push scans the byte and the history reaches the remote"
else
  bad "scan bytes f: pre-push scans the byte and the history reaches the remote" \
      "refused: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-push.out" | tr '\n' ' ' | cut -c1-240)"
fi
SBQ="$WORK/sb-push-secret"; sb_push_fixture "$SBQ" 'caf\351\nconst api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";\n'
if LC_ALL="$SB_U8" LANG="$SB_U8" git -C "$SBQ" push -q origin main >"$WORK/sb-push-secret.out" 2>&1; then
  bad "scan bytes g: a pushed secret beside the byte is still refused, and the refusal says the content is the reason" "the push landed a secret-shaped line"
elif grep -q 'SLH-SECRET' "$WORK/sb-push-secret.out" && grep -q 'carries content' "$WORK/sb-push-secret.out"; then
  ok "scan bytes g: a pushed secret beside the byte is still refused, and the refusal says the content is the reason"
else
  bad "scan bytes g: a pushed secret beside the byte is still refused, and the refusal says the content is the reason" \
      "$(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-push-secret.out" | tr '\n' ' ' | cut -c1-240)"
fi
# A push refused for a reason that is NOT the content must not be told the
# content is the reason. A pushed tip that does not resolve here is the one
# no-content refusal a fixture reaches without breaking the toolchain
# (SLH-SCAN-UNRESOLVED-TIP), fed to the hook on stdin as git would.
SBR="$WORK/sb-push-norun"; sb_push_fixture "$SBR" 'plain\n'
( cd "$SBR" && printf 'refs/heads/main %s refs/heads/main %s\n' "0123456789012345678901234567890123456789" 0000000000000000000000000000000000000000 \
    | LC_ALL="$SB_U8" LANG="$SB_U8" bash .githooks/pre-push origin "$SBR-rem.git" ) >"$WORK/sb-norun.out" 2>&1
SBR_RC=$?
if [[ "$SBR_RC" -ne 0 ]] && ! grep -q 'carries content' "$WORK/sb-norun.out"; then
  ok "scan bytes h: a push refused for a reason other than the content does not say the content is the reason"
else
  bad "scan bytes h: a push refused for a reason other than the content does not say the content is the reason" \
      "rc=$SBR_RC: $(LC_ALL=C tr -d '\200-\377' < "$WORK/sb-norun.out" | tr '\n' ' ' | cut -c1-240)"
fi
fi; shard_region_end
# <<< SHARD-END scan-bytes-0164

# --- EVERY READER OF THE RECORDS READS BYTES (spec 0169; L2 F2, F11) --------
#
# Fix round 1 of 2.10.0 put LC_ALL=C on the five content-scan stages and not on
# the readers of specs/STATUS.md and of the spec records, so one byte that is
# not valid UTF-8 aborted macOS awk and sed mid-read under a UTF-8 locale: a
# compliant close was refused at merge and at every push after it (F2), and a
# second close after the byte was never seen, so a spec with no Closing report
# merged (F11). Since 0169 the hook library and the trunk audit export LC_ALL=C
# once, at their tops, so every reader in their processes reads bytes.
#
# Every case below runs its hook or its reader under an EXPLICIT UTF-8 locale
# the host has, because the suite inherits its caller's and a C harness would
# hide the defect. On Linux the awks read the byte without aborting, so there
# the cases are the control: green before and after.
RB_U8="$(locale -a 2>/dev/null | grep -iE '^(en_US\.utf-?8|C\.utf-?8)$' | head -n1)"
RB_LIB="$ROOT/templates/git-hooks/setlist-hook-lib.sh"
RB_SPEC_OK='# Spec %s\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
rb_lib() { # rb_lib <script>: the library sourced by a shell under the host's UTF-8 locale, then <script>
  LC_ALL="$RB_U8" LANG="$RB_U8" bash -c '. "$1"; eval "$2"' _ "$RB_LIB" "$1" 2>/dev/null
}
rb_out() { # the lines that say why, else the head of the output
  local w; w="$(LC_ALL=C tr -d '\200-\377' < "$1" | grep -E 'SLH-|VIOLATION|awk:|sed:|refus' | tr '\n' ' ' | cut -c1-300)"
  [[ -n "$w" ]] && printf '%s' "$w" || LC_ALL=C tr -d '\200-\377' < "$1" | tr '\n' ' ' | cut -c1-300
}
rb_merge() { # rb_merge <dir> <branch>: merge under the UTF-8 locale, output in <dir>.out
  ( cd "$1" && LC_ALL="$RB_U8" LANG="$RB_U8" GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge $2" "$2" ) >"$1.out" 2>&1
}
rb_branch_close() { # rb_branch_close <dir> <status-printf> <spec-printf>: rewrite the spec branch's close, hooks off
  local d="$1"
  git -C "$d" checkout -q spec/0001-thing
  # shellcheck disable=SC2059
  printf "$2" > "$d/specs/STATUS.md"
  # shellcheck disable=SC2059
  printf "$3" > "$d/specs/0001-thing.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -q --amend --no-edit >/dev/null 2>&1
  git -C "$d" checkout -q main
}
rb_push_ready() { # rb_push_ready <dir>: deliver pre-push and the audit, seed a bare remote with main
  local d="$1"
  cp "$ROOT/templates/git-hooks/pre-push" "$d/.githooks/pre-push"; chmod +x "$d/.githooks/pre-push"
  mkdir -p "$d/.claude/hooks"; cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "deliver pre-push" >/dev/null 2>&1
  rm -rf "$d-rem.git"; git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git" >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main >/dev/null 2>&1
}
rb_push() { ( cd "$1" && LC_ALL="$RB_U8" LANG="$RB_U8" git push -q origin main ) >"$1.push" 2>&1; }
RB_ROW_HDR='# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n'

# >>> SHARD-BEGIN record-bytes-0169 cost=8
if shard_region record-bytes-0169; then
if [[ -z "$RB_U8" ]]; then
  ok "record bytes: SKIPPED BY NAME, this host has no UTF-8 locale (en_US.UTF-8 or C.UTF-8), so the byte cannot abort a reader here"
else
# The export's POSITION is the fix, so it is pinned: in both files the line
# must precede the first function definition, or a reader could run before it.
for rb_f in "$RB_LIB" "$ROOT/scripts/trunk-audit.sh"; do
  rb_exp="$(grep -n '^LC_ALL=C; export LC_ALL' "$rb_f" | head -n1 | cut -d: -f1)"
  rb_fn="$(grep -nE '^[a-z_]+\(\) *\{' "$rb_f" | head -n1 | cut -d: -f1)"
  if [[ -n "$rb_exp" && -n "$rb_fn" && "$rb_exp" -lt "$rb_fn" ]]; then
    ok "record bytes 0: ${rb_f##*/} exports LC_ALL=C (line $rb_exp) before its first function (line $rb_fn)"
  else
    bad "record bytes 0: ${rb_f##*/} exports LC_ALL=C before its first function" "export line [${rb_exp:-none}], first function [${rb_fn:-none}]"
  fi
done

# THE READERS, ONE BY ONE, with the byte AHEAD of the text each one decides by.
rb_st="$(printf "$RB_ROW_HDR"'| 0009 | Caf\351 menu | ACTIVE | wip |\n| 0001 | One | CLOSED | done |\n| 0003 | Three | ACTIVE | wip |\n')"
rb_old="$(printf "$RB_ROW_HDR"'| 0009 | Caf\351 menu | ACTIVE | wip |\n| 0001 | One | ACTIVE | wip |\n| 0003 | Three | ACTIVE | wip |\n')"
rb_r="$(ST="$rb_st" rb_lib 'slh_row_closed "$ST" 0001 && echo CLOSED || echo NOT')"
[[ "$rb_r" == "CLOSED" ]] && ok "record bytes r1: slh_row_closed reads a row after a Latin-1 row whole (CLOSED)" \
  || bad "record bytes r1: slh_row_closed reads a row after a Latin-1 row whole" "read [$rb_r]"
rb_r="$(ST="$rb_st" OLD="$rb_old" rb_lib 'slh_rows_newly_closed "$ST" "$OLD"' | tr '\n' ' ')"
[[ "$rb_r" == "0001 " ]] && ok "record bytes r2: slh_rows_newly_closed sees the close after the byte" \
  || bad "record bytes r2: slh_rows_newly_closed sees the close after the byte" "read [$rb_r]"
rb_r="$(ST="$rb_st" rb_lib 'slh_attest_active_specs "$ST"' | tr '\n' ' ')"
[[ "$rb_r" == "0009 0003 " ]] && ok "record bytes r3: slh_attest_active_specs reads every ACTIVE row, the byte's own and the one after it" \
  || bad "record bytes r3: slh_attest_active_specs reads every ACTIVE row" "read [$rb_r]"
rb_r="$(NEW="$(printf 'caf\351 notes\n- CHORE-001: DONE 2026-09-24. a chore\n')" rb_lib 'slh_chores_completed "$NEW" ""' | tr '\n' ' ')"
[[ "$rb_r" == "CHORE-001 " ]] && ok "record bytes r4: slh_chores_completed sees an archive line after the byte" \
  || bad "record bytes r4: slh_chores_completed sees an archive line after the byte" "read [$rb_r]"
rb_txt="$(printf '# Spec 0001\n\ncaf\351 goal\n\nStatus: ACTIVE\n\n## Goal\nbuild\n\n## Closing report\n- pending\n')"
rb_c="$(printf '%s\n' "$rb_txt" | LC_ALL=C bash -c '. "$1"; slh_attest_hash_stdin' _ "$RB_LIB" 2>/dev/null)"
rb_r="$(TXT="$rb_txt" rb_lib 'printf "%s\n" "$TXT" | slh_attest_hash_stdin')"
[[ -n "$rb_c" && "$rb_r" == "$rb_c" ]] && ok "record bytes r5: the spec hash covers every byte above the Closing report under a UTF-8 caller" \
  || bad "record bytes r5: the spec hash covers every byte above the Closing report under a UTF-8 caller" "C [$rb_c] UTF-8 [$rb_r]"
rb_r="$(TXT="$(printf '# Spec 0001\n\ncaf\351\n\n- Architecture diagram: no impact\n')" rb_lib 'slh_diagram_field_line "$TXT"')"
[[ "$rb_r" == *"Architecture diagram: no impact"* ]] && ok "record bytes r6: the diagram field reader finds the field after the byte" \
  || bad "record bytes r6: the diagram field reader finds the field after the byte" "read [$rb_r]"

# THE LAYERS. F2 at merge: the closing row itself carries the byte.
RBM="$WORK/rb-merge-f2"; gh_fixture "$RBM" yes
rb_branch_close "$RBM" "$RB_ROW_HDR"'| 0001 | Caf\351 menu | CLOSED | done |\n' "$(printf "$RB_SPEC_OK" 0001)"
rb_merge "$RBM" spec/0001-thing
if gh_landed "$RBM"; then ok "record bytes m1 (F2): a compliant close whose row carries a Latin-1 byte merges"
else bad "record bytes m1 (F2): a compliant close whose row carries a Latin-1 byte merges" "refused: $(rb_out "$RBM.out")"; fi

# F11 at merge, the fail-open half: two closes, the byte between their rows,
# the second with no Closing report. Refused with the byte and without it.
for rb_t in 'Caf\351' 'Cafe'; do
  RBF="$WORK/rb-merge-f11"; gh_fixture "$RBF" yes
  git -C "$RBF" checkout -q main
  printf "$RB_ROW_HDR"'| 0001 | One | ACTIVE | wip |\n| 0009 | '"$rb_t"' menu | ACTIVE | wip |\n| 0002 | Two | ACTIVE | wip |\n' > "$RBF/specs/STATUS.md"
  printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$RBF/specs/0001-thing.md"
  printf '# Spec 0002\n\nStatus: ACTIVE\n' > "$RBF/specs/0002-two.md"
  printf '# Spec 0009\n\nStatus: ACTIVE\n' > "$RBF/specs/0009-menu.md"
  git -C "$RBF" add -A >/dev/null 2>&1; git -C "$RBF" -c core.hooksPath=/dev/null commit -qm "three active specs" >/dev/null 2>&1
  git -C "$RBF" checkout -q spec/0001-thing
  git -C "$RBF" -c core.hooksPath=/dev/null merge -q --no-ff -m "sync" main >/dev/null 2>&1
  printf "$RB_ROW_HDR"'| 0001 | One | CLOSED | done |\n| 0009 | '"$rb_t"' menu | ACTIVE | wip |\n| 0002 | Two | CLOSED | done |\n' > "$RBF/specs/STATUS.md"
  printf "$RB_SPEC_OK" 0001 > "$RBF/specs/0001-thing.md"
  printf '# Spec 0002\n\nStatus: CLOSED\n' > "$RBF/specs/0002-two.md"
  git -C "$RBF" add -A >/dev/null 2>&1; git -C "$RBF" -c core.hooksPath=/dev/null commit -qm "close two" >/dev/null 2>&1
  git -C "$RBF" checkout -q main
  rb_merge "$RBF" spec/0001-thing
  if gh_landed "$RBF"; then
    bad "record bytes m2 (F11, row [$rb_t]): a second close after the byte with no Closing report is refused" "the merge landed: $(rb_out "$RBF.out")"
  elif grep -q 'SLH-NO-CLOSING-REPORT' "$RBF.out" && grep -q '0002' "$RBF.out"; then
    ok "record bytes m2 (F11, row [$rb_t]): a second close after the byte with no Closing report is refused, naming spec 0002"
  else
    bad "record bytes m2 (F11, row [$rb_t]): a second close after the byte with no Closing report is refused, naming spec 0002" "$(rb_out "$RBF.out")"
  fi
done

# The spec text's readers at merge: the byte above the Closing report, above
# the diagram field, and above an Owns: line.
rb_i=0
for rb_spec in \
  '# Spec 0001\n\ncaf\351 notes\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' \
  '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): caf\351 done\n\n- Architecture diagram: no impact\n' \
  '# Spec 0001\n\ncaf\351 notes\nOwns: src/FEATURE.txt\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'; do
  rb_i=$((rb_i + 1))
  RBS="$WORK/rb-spec-$rb_i"; gh_fixture "$RBS" yes
  rb_branch_close "$RBS" "$RB_ROW_HDR"'| 0001 | Thing | CLOSED | done |\n' "$rb_spec"
  rb_merge "$RBS" spec/0001-thing
  if gh_landed "$RBS"; then ok "record bytes s$rb_i: the close verification reads the spec text whole past a Latin-1 byte, and the merge lands"
  else bad "record bytes s$rb_i: the close verification reads the spec text whole past a Latin-1 byte, and the merge lands" "refused: $(rb_out "$RBS.out")"; fi
done

# A chore at merge: the archive line comes after a line carrying the byte.
RBC="$WORK/rb-chore"; gh_fixture "$RBC" no
git -C "$RBC" checkout -q main
git -C "$RBC" checkout -q -b chore/bump
printf 'bump\n' > "$RBC/src/app.js"
printf "$RB_ROW_HDR"'| 0001 | Thing | ACTIVE | wip |\n\ncaf\351 archive\n\n- CHORE-001: DONE 2026-09-24. a bump\n' > "$RBC/specs/STATUS.md"
git -C "$RBC" add -A >/dev/null 2>&1; git -C "$RBC" -c core.hooksPath=/dev/null commit -qm "chore" >/dev/null 2>&1
git -C "$RBC" checkout -q main
rb_merge "$RBC" chore/bump
if [[ "$(git -C "$RBC" show main:src/app.js 2>/dev/null)" == "bump" ]]; then ok "record bytes c1: a chore whose archive line follows a Latin-1 byte merges"
else bad "record bytes c1: a chore whose archive line follows a Latin-1 byte merges" "refused: $(rb_out "$RBC.out")"; fi

# F2 at commit: the squash route, where pre-commit completes the close.
RBQ="$WORK/rb-squash"; gh_fixture "$RBQ" yes
rb_branch_close "$RBQ" "$RB_ROW_HDR"'| 0001 | Caf\351 menu | CLOSED | done |\n' "$(printf "$RB_SPEC_OK" 0001)"
( cd "$RBQ" && LC_ALL="$RB_U8" LANG="$RB_U8" git -c merge.ff=true merge --squash spec/0001-thing \
  && LC_ALL="$RB_U8" LANG="$RB_U8" git commit -qm "Squash spec/0001-thing" ) >"$RBQ.out" 2>&1
if gh_landed "$RBQ"; then ok "record bytes q1 (F2 at commit): the squash commit completing a close whose row carries the byte is accepted"
else bad "record bytes q1 (F2 at commit): the squash commit completing a close whose row carries the byte is accepted" "refused: $(rb_out "$RBQ.out")"; fi

# F2 at push: the audit's row reader, its spec-text reader, and the squash
# commit's single-parent route, each on a trunk the merge put there.
rb_j=0
for rb_case in merge-row merge-spec squash; do
  rb_j=$((rb_j + 1))
  RBP="$WORK/rb-push-$rb_j"; gh_fixture "$RBP" yes; git -C "$RBP" checkout -q main; rb_push_ready "$RBP"
  case "$rb_case" in
    merge-row) rb_branch_close "$RBP" "$RB_ROW_HDR"'| 0001 | Caf\351 menu | CLOSED | done |\n' "$(printf "$RB_SPEC_OK" 0001)" ;;
    merge-spec) rb_branch_close "$RBP" "$RB_ROW_HDR"'| 0001 | Thing | CLOSED | done |\n' '# Spec 0001\n\ncaf\351 notes\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' ;;
    squash) rb_branch_close "$RBP" "$RB_ROW_HDR"'| 0001 | Caf\351 menu | CLOSED | done |\n' "$(printf "$RB_SPEC_OK" 0001)" ;;
  esac
  if [[ "$rb_case" == squash ]]; then
    git -C "$RBP" -c core.hooksPath=/dev/null -c merge.ff=true merge -q --squash spec/0001-thing >/dev/null 2>&1
    git -C "$RBP" -c core.hooksPath=/dev/null commit -qm "Squash spec/0001-thing" >/dev/null 2>&1
  else
    git -C "$RBP" -c core.hooksPath=/dev/null merge -q --no-ff -m "Merge spec/0001-thing" spec/0001-thing >/dev/null 2>&1
  fi
  if rb_push "$RBP"; then ok "record bytes p$rb_j (F2 at push, $rb_case): the audit reads the record whole past the byte and the push lands"
  else bad "record bytes p$rb_j (F2 at push, $rb_case): the audit reads the record whole past the byte and the push lands" "refused: $(rb_out "$RBP.push")"; fi
done
fi
fi; shard_region_end
# <<< SHARD-END record-bytes-0169

# --- A ROLE IS A LITERAL PREFIX AT EVERY LAYER (spec 0169, E-e) ------------------
# The hook library and pre-commit matched a role against staged paths as a
# regular expression while the trunk audit matches it literally: `c++` (an
# ordinary directory name) made BSD grep exit 2 ("repetition-operator operand
# invalid"), so the merge hook read "no feature code" and the closes-no-spec
# refusal never fired, and `a.b` matched `axb/`. Since 0169 every layer reads the
# role as the audit does. THE THREE READERS AGREEING IS THE THESIS.
rl_fixture() { # rl_fixture <dir> <role> <branch-file> [owns-line]: a spec branch adding one file, closing nothing
  local d="$1" role="$2" file="$3"
  rm -rf "$d"; mkdir -p "$d/specs" "$d/.claude" "$d/.githooks" "$d/docs"
  git_init "$d"
  jq -nc --arg r "$role" '{trunk:"main",scaffolded:true,gate_command:"true",roles:{src:$r,tests:"tests"}}' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
  printf 'seed\n' > "$d/docs/readme.txt"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" checkout -q -b spec/0001-thing
  mkdir -p "$d/$(dirname "$file")"; printf 'work\n' > "$d/$file"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "work" >/dev/null 2>&1
  git -C "$d" checkout -q main
}
rl_merge() { ( cd "$1" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "Merge spec/0001-thing" spec/0001-thing ) >"$1.out" 2>&1; }
rl_landed() { git -C "$1" cat-file -e "main:$2" 2>/dev/null; }

# >>> SHARD-BEGIN role-literal-0169 cost=2
if shard_region role-literal-0169; then
# c++ : feature code under the role, merged without closing a spec.
RL="$WORK/rl-cpp"; rl_fixture "$RL" 'c++' 'c++/x.cpp'; rl_merge "$RL"
if ! rl_landed "$RL" 'c++/x.cpp' && grep -q 'SLH-CLOSES-NO-SPEC' "$RL.out"; then
  ok "role literal 1: a role named c++ is feature code at merge, refused SLH-CLOSES-NO-SPEC when no spec closes"
else
  bad "role literal 1: a role named c++ is feature code at merge, refused SLH-CLOSES-NO-SPEC when no spec closes" \
      "$(LC_ALL=C tr -d '\200-\377' < "$RL.out" | grep -E 'SLH-|grep|Merge made' | tr '\n' ' ' | cut -c1-240)"
fi
# the audit agrees at push: the same role, the same file straight onto main
RLA="$WORK/rl-cpp-audit"; rl_fixture "$RLA" 'c++' 'docs/other.txt'
mkdir -p "$RLA/c++"; printf 'x\n' > "$RLA/c++/y.cpp"
git -C "$RLA" add -A >/dev/null 2>&1; git -C "$RLA" -c core.hooksPath=/dev/null commit -qm "c++ straight onto main" >/dev/null 2>&1
rl_a="$(bash "$SCRIPTS/trunk-audit.sh" "$RLA" 2>&1)"; rl_arc=$?
if [[ "$rl_arc" -eq 1 && "$rl_a" == *"VIOLATION"* ]]; then
  ok "role literal 2: the trunk audit reads the c++ role literally too, reporting the direct commit (the three readers agree)"
else
  bad "role literal 2: the trunk audit reads the c++ role literally too" "rc $rl_arc: $(printf '%s' "$rl_a" | tail -n2 | tr '\n' ' ')"
fi
# a.b : axb/ is not the role, so a docs-shaped merge that closes nothing lands.
RL="$WORK/rl-dot"; rl_fixture "$RL" 'a.b' 'axb/f.txt'; rl_merge "$RL"
if rl_landed "$RL" 'axb/f.txt'; then
  ok "role literal 3: a role named a.b does not match axb/, so a merge touching only axb/ is not feature code"
else
  bad "role literal 3: a role named a.b does not match axb/" "refused: $(LC_ALL=C tr -d '\200-\377' < "$RL.out" | grep -E 'SLH-' | tr '\n' ' ' | cut -c1-240)"
fi
# the control: a.b/ itself is the role
RL="$WORK/rl-dot-ctl"; rl_fixture "$RL" 'a.b' 'a.b/f.txt'; rl_merge "$RL"
if ! rl_landed "$RL" 'a.b/f.txt' && grep -q 'SLH-CLOSES-NO-SPEC' "$RL.out"; then
  ok "role literal 4: a.b/f.txt is under the role a.b, refused when no spec closes (the control)"
else
  bad "role literal 4: a.b/f.txt is under the role a.b, refused when no spec closes (the control)" "$(LC_ALL=C tr -d '\200-\377' < "$RL.out" | tr '\n' ' ' | cut -c1-200)"
fi
# The Owns: reader: a declaring close whose role-path file under c++ is not declared.
RL="$WORK/rl-owns"; rl_fixture "$RL" 'c++' 'c++/x.cpp'
# the per-file check runs where the status record decides, so the instance carries one
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$RL/.claude/status.json"
git -C "$RL" add -A >/dev/null 2>&1; git -C "$RL" -c core.hooksPath=/dev/null commit -qm "record" >/dev/null 2>&1
git -C "$RL" checkout -q spec/0001-thing
git -C "$RL" -c core.hooksPath=/dev/null merge -q --no-ff -m sync main >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RL/.claude/status.json"
mkdir -p "$RL/c++"; printf 'more\n' > "$RL/c++/undeclared.cpp"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$RL/specs/STATUS.md"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: c++/x.cpp\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$RL/specs/0001-thing.md"
git -C "$RL" add -A >/dev/null 2>&1; git -C "$RL" -c core.hooksPath=/dev/null commit -qm "close, one file undeclared" >/dev/null 2>&1
git -C "$RL" checkout -q main
# The file-by-file check is the SINGLE-PARENT close's (a --no-ff merge takes the provenance arm), so the squash route.
( cd "$RL" && git -c merge.ff=true merge --squash spec/0001-thing >/dev/null 2>&1 && git commit -qm "Squash spec/0001-thing" ) >"$RL.out" 2>&1
if ! rl_landed "$RL" 'c++/undeclared.cpp' && grep -q 'SLH-OWNS-UNDECLARED' "$RL.out"; then
  ok "role literal 5: under a c++ role, a declaring squash close's undeclared role-path file is refused SLH-OWNS-UNDECLARED"
else
  bad "role literal 5: under a c++ role, a declaring squash close's undeclared role-path file is refused SLH-OWNS-UNDECLARED" \
      "landed=$(rl_landed "$RL" 'c++/undeclared.cpp' && echo yes || echo no): $(LC_ALL=C tr -d '\200-\377' < "$RL.out" | tr '\n' ' ' | cut -c1-300)"
fi
fi; shard_region_end
# <<< SHARD-END role-literal-0169

# THE CLOSE REVIEW (spec 0175): one block, one reader, two layers. cr_fixture builds an
# instance in e174_fixture's shape (roles src and tests, the four git hooks armed from this
# tree, the audit beside them), record-carrying or page-only (DE15), "plugin":{"version"}
# 2.11.0 unless told otherwise, and spec 0001 closed on spec/0001 with a complete Closing
# report whose close-review block is the case's text (empty: no block at all). cr_judge
# merges it --no-ff through the armed gate, completes a refused merge with hooks off so the
# audit has the close to read, and prints "<gate> <audit>", each "ok" or the [SLH-...]
# code it refused with ("rc<N>" for a refusal carrying no code).
# cr_fixture <dir> <record|page> <block-text> [branch-file] [plugin-version|none] [pasted-text]
# pasted-text (spec 0180, F-a): written between the qa-pass-1 block and the close-review block,
# the place /setlist:checkpoint pastes the QA report verbatim.
cr_fixture() {
  local d="$1" kind="$2" blk="$3" f="${4:-src/a.txt}" v="${5:-2.11.0}" pv="" pasted="${6:-}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"
  [[ "$v" == "none" ]] || pv=',"plugin":{"version":"'"$v"'"}'
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}%s}\n' "$pv" > "$d/.claude/sdd.json"
  [[ "$kind" == "page" ]] || printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | A | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
  git -C "$d" checkout -qb spec/0001
  { printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\n1: PASS\n2: PASS\n```\n'
    [[ -z "$pasted" ]] || printf '\n%s\n' "$pasted"
    [[ -z "$blk" ]] || printf '\n```close-review\n%s\n```\n\nThe reviewer'"'"'s report, pasted verbatim.\n' "$blk"; } > "$d/specs/0001-x.md"
  mkdir -p "$(dirname "$d/$f")"; printf 'A\n' > "$d/$f"
  if [[ "$kind" != "page" ]]; then
    jq '.specs["0001"]={"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}' "$d/.claude/status.json" > "$d/.claude/status.json.new" \
      && mv "$d/.claude/status.json.new" "$d/.claude/status.json"
  fi
  sed -e 's/^| 0001 | A | ACTIVE |/| 0001 | A | CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
  git -C "$d" checkout -q main
  git -C "$d" config core.hooksPath .githooks
}
cr_code() { # cr_code <rc> <output> -> ok | [SLH-...] | rc<N>
  local c
  if [[ "$1" -eq 0 ]]; then printf 'ok'; return; fi
  c="$(grep -oE '\[SLH-(NO-CLOSE-REVIEW|CLOSE-REVIEW-[A-Z-]+)\]' <<< "$2" | head -1)"
  printf '%s' "${c:-rc$1}"
}
cr_judge() { # cr_judge <dir> [squash] -> "<gate> <audit>"
  local d="$1" out rc g a
  if [[ "${2:-}" == "squash" ]]; then
    out="$( { git -C "$d" merge -q --squash spec/0001 && git -C "$d" commit -qm "squash close 0001"; } 2>&1)"; rc=$?
    g="$(cr_code "$rc" "$out")"
    if [[ "$rc" -ne 0 ]]; then git -C "$d" -c core.hooksPath=/dev/null commit -qm "squash close 0001" >/dev/null 2>&1; fi
  else
    out="$(git -C "$d" merge -q --no-ff -m "merge spec/0001" spec/0001 2>&1)"; rc=$?
    g="$(cr_code "$rc" "$out")"
    if [[ "$rc" -ne 0 ]]; then
      git -C "$d" merge --abort >/dev/null 2>&1
      git -C "$d" -c core.hooksPath=/dev/null merge -q --no-ff -m "merge spec/0001" spec/0001 >/dev/null 2>&1
    fi
  fi
  out="$(bash "$SCRIPTS/trunk-audit.sh" "$d" 2>&1)"; rc=$?
  a="$(cr_code "$rc" "$(grep '^VIOLATION' <<< "$out")")"
  printf '%s %s' "$g" "$a"
}
CR_ROUND1_FAIL=$'round 1: FAIL\n1: PASS\n2: FAIL\nF1 | 2 | MAJOR | src/a.txt:1 | the file says A where criterion 2 wants B | write B'
CR_ROUND2_PASS=$'round 2: PASS\n1: PASS\n2: PASS'

# >>> SHARD-BEGIN close-review-0175 cost=8
if shard_region close-review-0175; then
# The corpus (groups A, B and C): each shape through the gate and the audit, on a record-
# carrying and a record-less instance, against the outcome the design names. One table,
# so the two layers are compared shape by shape rather than case by case.
CR_BAD=""; CR_ROWS=0
while IFS='|' read -r CR_NAME CR_FILE CR_WANT; do
  [[ -n "$CR_NAME" ]] || continue
  case "$CR_NAME" in
    absent)       CR_BLK="" ;;
    fail)         CR_BLK="$CR_ROUND1_FAIL" ;;
    malformed-fl) CR_BLK=$'round 1: FAIL\n2: FAIL\nF1 | 2 | MAJOR | src/a.txt | no line here | fix' ;;
    malformed-r3) CR_BLK="$CR_ROUND1_FAIL"$'\nround 2: FAIL\n2: FAIL\nF2 | 2 | MAJOR | src/a.txt:1 | w | f\nround 3: PASS\n1: PASS\n2: PASS' ;;
    malformed-pre) CR_BLK=$'1: PASS\nround 1: PASS\n1: PASS' ;;
    malformed-pm) CR_BLK=$'round 1: PASS\n1: PASS\n2: PASS\nF1 | 2 | MAJOR | src/a.txt:1 | w | f' ;;
    pass)         CR_BLK=$'round 1: PASS\n1: PASS\n2: PASS\nF1 | - | MINOR | src/a.txt:1 | a nit | optional' ;;
    two-rounds)   CR_BLK="$CR_ROUND1_FAIL"$'\n'"$CR_ROUND2_PASS" ;;
    skip)         CR_BLK='round 1: SKIP-DOCS-ONLY' ;;
    skip-role)    CR_BLK='round 1: SKIP-DOCS-ONLY' ;;
    accepted)     CR_BLK="$CR_ROUND1_FAIL"$'\nround 2: FAIL\n1: PASS\n2: FAIL\nF2 | 2 | MAJOR | src/a.txt:1 | still A | write B\nverdict: ACCEPTED-BY-HUMAN F2' ;;
    accepted-r1)  CR_BLK="$CR_ROUND1_FAIL"$'\nverdict: ACCEPTED-BY-HUMAN F1' ;;
    accepted-bad) CR_BLK="$CR_ROUND1_FAIL"$'\nround 2: FAIL\n2: FAIL\nF2 | 2 | MAJOR | src/a.txt:1 | w | f\nverdict: ACCEPTED-BY-HUMAN F7' ;;
  esac
  for CR_KIND in record page; do
    CR_D="$WORK/cr-$CR_NAME-$CR_KIND"
    cr_fixture "$CR_D" "$CR_KIND" "$CR_BLK" "$CR_FILE"
    CR_GOT="$(cr_judge "$CR_D")"; CR_ROWS=$((CR_ROWS + 1))
    [[ "$CR_GOT" == "$CR_WANT $CR_WANT" ]] || CR_BAD="$CR_BAD $CR_NAME/$CR_KIND: gate,audit=$CR_GOT want $CR_WANT;"
  done
done <<'CRTABLE'
absent|src/a.txt|[SLH-NO-CLOSE-REVIEW]
fail|src/a.txt|[SLH-CLOSE-REVIEW-FAIL]
malformed-fl|src/a.txt|[SLH-NO-CLOSE-REVIEW]
malformed-r3|src/a.txt|[SLH-NO-CLOSE-REVIEW]
malformed-pre|src/a.txt|[SLH-NO-CLOSE-REVIEW]
malformed-pm|src/a.txt|[SLH-NO-CLOSE-REVIEW]
pass|src/a.txt|ok
two-rounds|src/a.txt|ok
skip|docs/x.md|ok
skip-role|src/a.txt|[SLH-CLOSE-REVIEW-SKIP-REFUSED]
accepted|src/a.txt|ok
accepted-r1|src/a.txt|[SLH-NO-CLOSE-REVIEW]
accepted-bad|src/a.txt|[SLH-NO-CLOSE-REVIEW]
CRTABLE
if [[ -z "$CR_BAD" && "$CR_ROWS" -eq 26 ]]; then
  ok "0175 cr corpus: 13 block shapes, record and page, read identically by the close gate and the trunk audit, each as designed"
else
  bad "0175 cr corpus: 13 block shapes, record and page, read identically by the close gate and the trunk audit, each as designed" "rows=$CR_ROWS:$CR_BAD"
fi
# A PASTED REPORT CARRYING HEADINGS (spec 0180, F-a of the 2.11.0 cold run, and fix round 2 as the
# validator ruled). /setlist:checkpoint pastes the QA report verbatim above the close-review block,
# and an agent's report can carry `##` headings; the reader ended the Closing report at the first
# one and said the block was absent. Fix round 1 read to the end of the file, which also read a
# block in a SECTION AFTER the Closing report when the report carried none (the widening the leg's
# triage recorded): a pasted heading and a real later section are the same bytes. So a report is
# pasted inside a fence, where its headings are content (a); a report with no block is still
# refused (b); and an unfenced paste, F-a's own shape, is refused with the heading that ended the
# section named, never read as absent (c). Both record kinds, the gate and the audit.
CR_PASTED=$'## QA Pass 1 report\n\nEvery criterion passed.\n\n## Findings\n\n### Minor\n\nNone.'
CR_FENCED=$'````text\n'"$CR_PASTED"$'\n````'
CR_H_BAD=""
for CR_KIND in record page; do
  CR_D="$WORK/cr-heading-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" $'round 1: PASS\n1: PASS\n2: PASS' src/a.txt 2.11.0 "$CR_FENCED"
  CR_GOT="$(cr_judge "$CR_D")"; [[ "$CR_GOT" == "ok ok" ]] || CR_H_BAD="$CR_H_BAD a/$CR_KIND: gate,audit=$CR_GOT want ok;"
  CR_D="$WORK/cr-heading-none-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" "" src/a.txt 2.11.0 "$CR_FENCED"
  CR_GOT="$(cr_judge "$CR_D")"; [[ "$CR_GOT" == "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" ]] || CR_H_BAD="$CR_H_BAD b/$CR_KIND: gate,audit=$CR_GOT want [SLH-NO-CLOSE-REVIEW];"
  CR_D="$WORK/cr-heading-bare-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" $'round 1: PASS\n1: PASS\n2: PASS' src/a.txt 2.11.0 "$CR_PASTED"
  CR_GOT="$(cr_judge "$CR_D")"; [[ "$CR_GOT" == "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" ]] || CR_H_BAD="$CR_H_BAD c/$CR_KIND: gate,audit=$CR_GOT want [SLH-NO-CLOSE-REVIEW];"
  bash "$SCRIPTS/trunk-audit.sh" "$CR_D" 2>&1 | grep -q 'sits after the heading "## QA Pass 1 report"' || CR_H_BAD="$CR_H_BAD c/$CR_KIND: the reason does not name the heading;"
done
if [[ -z "$CR_H_BAD" ]]; then
  ok "0180 cr heading: a report pasted inside a fence is read through, record and page, gate and audit; with no block it is refused; unfenced, its heading ends the section and is named"
else
  bad "0180 cr heading: a report pasted inside a fence is read through, record and page, gate and audit; with no block it is refused; unfenced, its heading ends the section and is named" "$CR_H_BAD"
fi
# THE SECTION AND THE FENCE, READ AS MARKDOWN READS THEM (spec 0180, fix round 2, the leg's F3,
# F12 and F16). F3: a heading that merely BEGAN "Closing report" ("## Closing report contract")
# opened the section, and first-wins let a decoy PASS above the real section pre-empt a real FAIL.
# F12: the info string was compared with every space deleted, so "close - review", a `close`
# block to every renderer, was taken as the block and pre-empted the real one. F16: an unclosed
# ordinary fence above a valid block hid it and the refusal said no block was carried; it names
# the unclosed fence by line now. Each row through the gate and the audit, page kind.
CR_FAIL_BLK=$'```close-review\nround 1: FAIL\n1: PASS\n2: FAIL\nF1 | 2 | BLOCKER | src/a.txt:1 | criterion 2 is not met | implement it\n```'
CR_S_BAD=""
cr_spec_case() { # cr_spec_case <name> <spec text> <want gate,audit> [<reason text the refusal must carry>]
  local d="$WORK/cr-s-$1" got out
  cr_fixture "$d" page ""
  git -C "$d" checkout -q spec/0001
  printf '%s\n' "$2" > "$d/specs/0001-x.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "close 0001, shaped" >/dev/null 2>&1
  git -C "$d" checkout -q main
  got="$(cr_judge "$d")"
  [[ "$got" == "$3" ]] || CR_S_BAD="$CR_S_BAD $1: gate,audit=$got want $3;"
  if [[ -n "${4:-}" ]]; then
    out="$(bash "$SCRIPTS/trunk-audit.sh" "$d" 2>&1)"
    grep -qF "$4" <<< "$out" || CR_S_BAD="$CR_S_BAD $1: the audit's reason does not carry '$4';"
  fi
}
CR_HEAD=$'# Spec 0001\n\nStatus: CLOSED\n'
CR_QA=$'Architecture diagram: no impact\n\n```qa-pass-1\n1: PASS\n2: PASS\n```\n'
cr_spec_case decoy-heading "$CR_HEAD"$'\n## Closing report contract (filled in at the close)\n\n```close-review\nround 1: PASS\n1: PASS\n2: PASS\n```\n\n## Design\n\nwork happened.\n\n## Closing report\n\n'"$CR_QA"$'\n'"$CR_FAIL_BLK" "[SLH-CLOSE-REVIEW-FAIL] [SLH-CLOSE-REVIEW-FAIL]"
cr_spec_case template-heading "$CR_HEAD"$'\n## Closing report (completed at close; checkpoint gates on this section)\n\n'"$CR_QA"$'\n```close-review\nround 1: PASS\n1: PASS\n2: PASS\n```' "ok ok"
cr_spec_case squeezed-info "$CR_HEAD"$'\n## Closing report\n\n'"$CR_QA"$'\n```close - review\nround 1: PASS\n1: PASS\n2: PASS\n```\n\n'"$CR_FAIL_BLK" "[SLH-CLOSE-REVIEW-FAIL] [SLH-CLOSE-REVIEW-FAIL]"
cr_spec_case padded-info "$CR_HEAD"$'\n## Closing report\n\n'"$CR_QA"$'\n```  close-review  \nround 1: PASS\n1: PASS\n2: PASS\n```' "ok ok"
cr_spec_case unclosed-fence "$CR_HEAD"$'\n## Closing report\n\n'"$CR_QA"$'\n- QA Pass 1 report (pasted verbatim): the suite output was\n\n  ```\n  12 tests, 0 failures\n\n- Close review:\n\n  ```close-review\n  round 1: PASS\n  1: PASS\n  2: PASS\n  ```' "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" "the close-review fence at line 21 opens inside a fence opened at line 16"
cr_spec_case late-section "$CR_HEAD"$'\n## Closing report\n\n'"$CR_QA"$'\n## Appendix: an example\n\n```close-review\nround 1: PASS\n1: PASS\n2: PASS\n```' "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" 'sits after the heading "## Appendix: an example"'
cr_spec_case unclosed-eof "$CR_HEAD"$'\n## Closing report\n\n'"$CR_QA"$'\n````\nthe transcript was cut here\n' "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" "an unclosed fence opened at line 14"
if [[ -z "$CR_S_BAD" ]]; then
  ok "0180 cr section: only a heading that IS Closing report opens the section, a later section is not read, the info string is compared trimmed, and an unclosed fence above the block is named by line; gate and audit"
else
  bad "0180 cr section: only a heading that IS Closing report opens the section, a later section is not read, the info string is compared trimmed, and an unclosed fence above the block is named by line; gate and audit" "$CR_S_BAD"
fi
# THE TREE THE GATE READ (spec 0180, fix round 2, the leg's F9). The gate reads the close-review
# block from the index, which becomes the merge commit; the audit read it from the MERGED
# PARENT's copy, so one close was judged two ways. D1: a block written in the merge resolution
# passed the gate and was refused at push. D2: a FAIL block written in the resolution over the
# branch's PASS reached the trunk and the audit called it clean. The audit reads the merge
# commit's own tree now, both kinds, both directions.
CR_T_BAD=""
for CR_KIND in record page; do
  CR_D="$WORK/cr-tree-d1-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" ""
  git -C "$CR_D" merge -q --no-commit --no-ff spec/0001 >/dev/null 2>&1
  printf '\n```close-review\nround 1: PASS\n1: PASS\n2: PASS\n```\n' >> "$CR_D/specs/0001-x.md"
  git -C "$CR_D" add -A >/dev/null 2>&1
  CR_OUT="$(git -C "$CR_D" commit -qm "merge spec/0001" 2>&1)"; CR_RC=$?
  [[ "$CR_RC" -eq 0 ]] || CR_T_BAD="$CR_T_BAD d1/$CR_KIND: the gate refused ($(tr '\n' ' ' <<< "$CR_OUT" | cut -c1-120));"
  CR_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$CR_D" 2>&1)"; CR_RC=$?
  [[ "$CR_RC" -eq 0 ]] || CR_T_BAD="$CR_T_BAD d1/$CR_KIND: audit rc=$CR_RC $(grep -m1 '^VIOLATION' <<< "$CR_OUT" | cut -c1-120);"
  CR_D="$WORK/cr-tree-d2-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" $'round 1: PASS\n1: PASS\n2: PASS'
  git -C "$CR_D" merge -q --no-commit --no-ff spec/0001 >/dev/null 2>&1
  awk '/^```close-review$/{print; print "round 1: FAIL"; print "1: PASS"; print "2: FAIL"; print "F1 | 2 | BLOCKER | src/a.txt:1 | criterion 2 is not met | implement it"; skip=1; next} skip && /^```$/{skip=0} !skip' \
    "$CR_D/specs/0001-x.md" > "$CR_D/specs/0001-x.md.new" && mv "$CR_D/specs/0001-x.md.new" "$CR_D/specs/0001-x.md"
  git -C "$CR_D" add -A >/dev/null 2>&1
  git -C "$CR_D" -c core.hooksPath=/dev/null commit -qm "merge spec/0001" >/dev/null 2>&1
  CR_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$CR_D" 2>&1)"; CR_RC=$?
  [[ "$CR_RC" -eq 1 ]] && grep -q '^VIOLATION .*\[SLH-CLOSE-REVIEW-FAIL\]' <<< "$CR_OUT" \
    || CR_T_BAD="$CR_T_BAD d2/$CR_KIND: audit rc=$CR_RC, no [SLH-CLOSE-REVIEW-FAIL];"
done
if [[ -z "$CR_T_BAD" ]]; then
  ok "0180 cr tree: the audit reads the close-review block from the merge commit's own tree, as the gate reads the index: a block written in the resolution passes both, a FAIL written over a PASS is refused; record and page"
else
  bad "0180 cr tree: the audit reads the close-review block from the merge commit's own tree, as the gate reads the index: a block written in the resolution passes both, a FAIL written over a PASS is refused; record and page" "$CR_T_BAD"
fi
# The reason names what the reader found (a malformed block says why).
CR_D="$WORK/cr-reason"; cr_fixture "$CR_D" page $'round 1: PASS\n1: PASS\n2: PASS\nF1 | 2 | MAJOR | src/a.txt:1 | w | f'
CR_OUT="$(git -C "$CR_D" merge -q --no-ff -m m spec/0001 2>&1)"
if grep -q 'SLH-NO-CLOSE-REVIEW' <<< "$CR_OUT" && grep -q 'round 1 reads PASS beside F1 MAJOR' <<< "$CR_OUT"; then
  ok "0175 cr reason: a PASS round beside a MAJOR finding is refused with the disagreement named"
else
  bad "0175 cr reason: a PASS round beside a MAJOR finding is refused with the disagreement named" "$(tr '\n' ' ' <<< "$CR_OUT" | cut -c1-300)"
fi
# Group D: the dating (not in force before 2.11, at both layers).
CR_BAD=""
for CR_V in 2.10.0 none; do
  for CR_KIND in record page; do
    CR_D="$WORK/cr-dated-$CR_V-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" "" src/a.txt "$CR_V"
    CR_GOT="$(cr_judge "$CR_D")"; [[ "$CR_GOT" == "ok ok" ]] || CR_BAD="$CR_BAD $CR_V/$CR_KIND=$CR_GOT;"
  done
done
if [[ -z "$CR_BAD" ]]; then
  ok "0175 cr dated: a block-less close under plugin 2.10.0 or no version is not judged by the review rule, at either layer"
else
  bad "0175 cr dated: a block-less close under plugin 2.10.0 or no version is not judged by the review rule, at either layer" "$CR_BAD"
fi
# Group D: the squash close, through pre-commit and the audit's linear arm.
CR_BAD=""
for CR_KIND in record page; do
  CR_D="$WORK/cr-squash-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" ""
  CR_GOT="$(cr_judge "$CR_D" squash)"; [[ "$CR_GOT" == "[SLH-NO-CLOSE-REVIEW] [SLH-NO-CLOSE-REVIEW]" ]] || CR_BAD="$CR_BAD absent/$CR_KIND=$CR_GOT;"
  CR_D="$WORK/cr-squash-pass-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" $'round 1: PASS\n1: PASS\n2: PASS'
  CR_GOT="$(cr_judge "$CR_D" squash)"; [[ "$CR_GOT" == "ok ok" ]] || CR_BAD="$CR_BAD pass/$CR_KIND=$CR_GOT;"
  CR_D="$WORK/cr-squash-skip-$CR_KIND"; cr_fixture "$CR_D" "$CR_KIND" 'round 1: SKIP-DOCS-ONLY' docs/x.md
  CR_GOT="$(cr_judge "$CR_D" squash)"; [[ "$CR_GOT" == "ok ok" ]] || CR_BAD="$CR_BAD skip/$CR_KIND=$CR_GOT;"
done
if [[ -z "$CR_BAD" ]]; then
  ok "0175 cr squash: a squash close is read by pre-commit and the audit's linear arm alike (absent refused, PASS and a docs-only skip accepted)"
else
  bad "0175 cr squash: a squash close is read by pre-commit and the audit's linear arm alike (absent refused, PASS and a docs-only skip accepted)" "$CR_BAD"
fi
fi; shard_region_end
# <<< SHARD-END close-review-0175
