#!/usr/bin/env bash
# test/suite/05-commit-gate-corpus.sh: shard 5 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE COMMIT-GATE CORPUS (1.0.5)
#
# The close-gate corpus found 144 bypasses and an over-denial nobody had
# reported. The commit gate parses a different grammar (a command line PLUS a
# staged index) and had never been generated against, only exampled. This
# pins what it does across the input space, so a future change to it, S1's
# location check above all, is judged by a corpus that already exists rather
# than by cases written to justify the change.
#
# Invariant: a command that stages AND commits in one line must deny, because
# the gate reads the index BEFORE the command runs and would otherwise scan
# content that is not there yet. Inverse: an ordinary commit, and prose that
# merely mentions the staging verbs, must pass.
# =============================================================================

CGC="$WORK/commit-corpus"
git_init "$CGC"
sdd_json "$CGC"
printf 'clean content with nothing to find\n' > "$CGC/ok.md"
git -C "$CGC" add ok.md

cg_verdict() { # cg_verdict <command>
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CGC" bash "$HOOKS/commit-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}

# CONTROL FIRST, both directions.
if [[ "$(cg_verdict 'git add -A && git commit -m x')" == "deny" ]]; then
  ok "commit corpus control a: the harness observes a deny on a known compound"
else
  bad "commit corpus control a: the harness observes a deny on a known compound" \
      "the control did not deny; every result below is meaningless"
fi
if [[ "$(cg_verdict 'git commit -m x')" == "allow" ]]; then
  ok "commit corpus control b: the harness observes an allow on a clean staged commit"
else
  bad "commit corpus control b: the harness observes an allow on a clean staged commit" \
      "a plain commit with clean staged content was denied"
fi

# --- MUST DENY: every spelling of stage-and-commit ---------------------------
# >>> SHARD-BEGIN commit-stage-spellings cost=10
if shard_region commit-stage-spellings; then
CGD_N=0; CGD_FAIL=""
for stage in 'git add -A' 'git add .' 'git add src/x' 'git rm f.txt' 'git mv a.txt b.txt'; do
 for conn in ' && ' ' ; ' ' || '; do
  for commit in 'git commit -m x' 'git  commit -m x' 'git -C . commit -m x' 'git --no-pager commit -m x' '/usr/bin/git commit -m x'; do
    CGD_N=$((CGD_N + 1))
    [[ "$(cg_verdict "${stage}${conn}${commit}")" == "deny" ]] || CGD_FAIL="$CGD_FAIL
    ${stage}${conn}${commit}"
  done
 done
done
for auto in 'git commit -am x' 'git commit -a -m x' 'git commit --all -m x' 'git commit --include f -m x' 'git commit -ai -m x'; do
  CGD_N=$((CGD_N + 1))
  [[ "$(cg_verdict "$auto")" == "deny" ]] || CGD_FAIL="$CGD_FAIL
    $auto"
done
if [[ "$CGD_N" -lt 50 ]]; then
  bad "commit corpus deny: the generator produced a real corpus" "only $CGD_N commands generated"
elif [[ -z "$CGD_FAIL" ]]; then
  ok "commit corpus deny: all $CGD_N stage-and-commit spellings are denied"
else
  bad "commit corpus deny: every stage-and-commit spelling must be denied ($CGD_N generated)" \
      "these would have scanned an index that does not hold the content yet:$CGD_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END commit-stage-spellings
# --- the WRAPPER axis, commit gate (1.0.6) ----------------------------------
CGW_N=0; CGW_FAIL=""
for wrap in 'command ' 'exec ' 'nice ' 'env ' 'GIT_PAGER=cat '; do
  for tail in 'git commit -am x' 'git add -A && git commit -m x'; do
    CGW_N=$((CGW_N + 1))
    [[ "$(cg_verdict "${wrap}${tail}")" == "deny" ]] || CGW_FAIL="$CGW_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CGW_FAIL" ]]; then
  ok "commit corpus wrappers: all $CGW_N wrapper-prefixed staging compounds are denied"
else
  bad "commit corpus wrappers: a wrapper prefix must not escape the commit gate" \
      "these scanned a stale index unchecked:$CGW_FAIL"
fi

# --- the FLAG-VALUED WRAPPER axis, commit gate (1.0.7) ----------------------
# The same stranded-value defect, same stripper, other gate. Asserted here
# rather than assumed from the close-gate cases: the two hooks carry their own
# copies of strip_wrappers, so a fix in one is not a fix in the other, and this
# suite has already watched a repair land in one place and not the other.
CGFW_N=0; CGFW_FAIL=""
for wrap in 'nice -n 5 ' 'LANG=C nice -n 5 ' 'env -u FOO ' 'env -i ' 'stdbuf -o 0 '; do
  for tail in 'git commit -am x' 'git add -A && git commit -m x'; do
    CGFW_N=$((CGFW_N + 1))
    [[ "$(cg_verdict "${wrap}${tail}")" == "deny" ]] || CGFW_FAIL="$CGFW_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CGFW_FAIL" ]]; then
  ok "commit corpus flag-valued wrappers: all $CGFW_N spellings are denied"
else
  bad "commit corpus flag-valued wrappers: a wrapper flag with a separate value must not escape the commit gate" \
      "these reached the index unchecked:$CGFW_FAIL"
fi
CGFW_ALLOW_FAIL=""
for cmd in 'nice -n 5 git status' 'env -u GIT_DIR git log' 'env -i git fetch'; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGFW_ALLOW_FAIL="$CGFW_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGFW_ALLOW_FAIL" ]]; then
  ok "commit corpus flag-valued wrappers: ordinary wrapped commands still pass"
else
  bad "commit corpus flag-valued wrappers: ordinary wrapped commands must still pass" \
      "these were denied:$CGFW_ALLOW_FAIL"
fi


# --- the INDEX-VERB axis, commit gate (1.0.7) -------------------------------
# >>> SHARD-BEGIN index-verb-axis cost=10
if shard_region index-verb-axis; then
# Check 0 enumerated add, rm and mv. Every OTHER verb that writes the index
# could therefore be compounded with a commit, and the three staged-content
# checks would scan an index nobody had judged:
#
#     git stash pop && git commit -m x
#     git restore --staged . && git commit -m x
#
# Both were ALLOWED by v1.0.6 and by 1.0.7 until this axis. `git stage`, a plain
# synonym for `add`, was missing for the same reason: nobody wrote it down.
#
# This list is the DIMENSION. It is written here independently of the hook's, and
# the lockstep assertion below requires the two to be identical, so a verb added
# to one without the other is a suite failure rather than a reviewer's catch.
# That is the whole repair: the wrapper axis, the dash-valued flag axis and this
# one were all the same defect, an enumeration that looked complete because
# nobody had listed what completeness meant.
CG_INDEX_VERBS='add stage rm mv restore reset stash checkout switch merge pull rebase cherry-pick revert am apply update-index read-tree sparse-checkout'

# POSITION DECIDES, AND THIS CORPUS USED TO ASSERT OTHERWISE (1.1.0 adversarial review,
# F1). Both orders were required to deny, so the suite pinned the very behaviour
# the leg reported: `git commit -m "x" && git checkout -` was refused, and that
# is the canonical spec-branch workflow the framework prescribes, commit on the
# branch and return to where you were. Check 0's own stated reason is positional
# ("the gate would scan a stale index"), and when the commit runs FIRST the index
# the gate scanned is exactly the index that gets committed.
#
# So the two orders are now asserted in OPPOSITE directions, which is what makes
# this a test of the rule rather than of one side of it. The deny direction is
# unchanged and is still the one that matters.
CGIV_N=0; CGIV_FAIL=""
for verb in $CG_INDEX_VERBS; do
  cmd="git $verb x && git commit -m x"
  CGIV_N=$((CGIV_N + 1))
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGIV_FAIL="$CGIV_FAIL
    $cmd"
done
if [[ -z "$CGIV_FAIL" ]]; then
  ok "commit corpus index verbs: all $CGIV_N stage-THEN-commit compounds are denied"
else
  bad "commit corpus index verbs: a verb that writes the index BEFORE a commit must be denied" \
      "these scanned a stale index unchecked:$CGIV_FAIL"
fi

# The allow direction of the same rule. An index writer AFTER the commit stages
# for some later commit, which this gate will see when it is run; it cannot make
# the index this commit uses stale, because that index has already been read.
CGIVA_N=0; CGIVA_FAIL=""
for verb in $CG_INDEX_VERBS; do
  cmd="git commit -m x && git $verb x"
  CGIVA_N=$((CGIVA_N + 1))
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGIVA_FAIL="$CGIVA_FAIL
    $cmd"
done
if [[ -z "$CGIVA_FAIL" ]]; then
  ok "commit corpus index verbs: all $CGIVA_N commit-THEN-index-writer compounds are allowed"
else
  bad "commit corpus index verbs: an index writer AFTER the commit must not be denied" \
      "the framework refused work its own protocol prescribes:$CGIVA_FAIL"
fi

# The payload exactly as the leg wrote it, kept beside the generated dimension
# because a dimension only tests the shape somebody imagined.
if [[ "$(cg_verdict 'git commit -m "x" && git checkout -')" == "allow" ]]; then
  ok "commit corpus index verbs: the leg's own F1 payload (commit then return) is allowed"
else
  bad "commit corpus index verbs: the leg's own F1 payload (commit then return) is allowed" \
      "git commit -m \"x\" && git checkout - was denied, which is the canonical spec-branch workflow"
fi

# The real-world spellings from the adversarial review, with their actual flags rather
# than the generated `git <verb> x` shape. A dimension only tests the form you
# imagined, which is exactly how `nice -5` sailed through the dash-valued axis.
CGIV_REAL_FAIL=""
for cmd in \
  'git stash pop && git commit -m x' \
  'git stash apply && git commit -m x' \
  'git restore --staged . && git commit -m x' \
  'git stage -A && git commit -m x' \
  'git reset HEAD~1 && git commit -m x' \
  'git checkout HEAD -- src/a.txt && git commit -m x' \
  'git cherry-pick -n abc123 && git commit -m x' \
  'git revert --no-commit abc123 && git commit -m x' \
  'git apply --index p.patch && git commit -m x' \
  'git update-index --add src/a.txt && git commit -m x' \
  'nice -n 5 git stash pop && git commit -m x' \
  'git stash pop; git commit -m x' \
  'git stash pop | git commit -m x' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGIV_REAL_FAIL="$CGIV_REAL_FAIL
    $cmd"
done
if [[ -z "$CGIV_REAL_FAIL" ]]; then
  ok "commit corpus index verbs: the leg's real spellings are denied, with their own flags and separators"
else
  bad "commit corpus index verbs: a real index-writing spelling escaped the gate" \
      "these reached the index unchecked:$CGIV_REAL_FAIL"
fi

# The lockstep. The hook owns the pattern; this suite owns the dimension; they
# must agree. Read out of the shipped hook rather than restated, so the failure
# names the drift instead of hiding it.
CG_HOOK_VERBS="$(grep -E "^INDEX_VERBS='" "$HOOKS/commit-gate.sh" | sed -E "s/^INDEX_VERBS='//; s/'$//" | tr '|' ' ')"
CG_WANT="$(printf '%s\n' $CG_INDEX_VERBS | LC_ALL=C sort | tr '\n' ' ')"
CG_GOT="$(printf '%s\n' $CG_HOOK_VERBS | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$CG_WANT" == "$CG_GOT" && -n "$CG_GOT" ]]; then
  ok "commit corpus index verbs: the hook's enumeration and this corpus are identical"
else
  bad "commit corpus index verbs: the hook's INDEX_VERBS and this corpus have drifted" \
      "corpus: $CG_WANT
      hook  : $CG_GOT
      Adding a verb to one without the other is how this dimension went missing in the first place."
fi

# The INVERSE, and it carries the weight here. A gate that denies everything
# also denies every stale index, so a passing deny column proves nothing on its
# own. These are verbs that do NOT write the index, and a read-only command
# compounded with a commit must still pass.
CGIV_ALLOW_FAIL=""
for cmd in \
  'git status && git commit -m x' \
  'git log --oneline && git commit -m x' \
  'git diff --cached && git commit -m x' \
  'git fetch origin && git commit -m x' \
  'git branch -a && git commit -m x' \
  'echo git stash pop && git commit -m x' \
  'git commit -m "after git stash pop"' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGIV_ALLOW_FAIL="$CGIV_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGIV_ALLOW_FAIL" ]]; then
  ok "commit corpus index verbs: read-only verbs and mere mentions still pass"
else
  bad "commit corpus index verbs: a command that does not write the index must still pass" \
      "these were denied:$CGIV_ALLOW_FAIL"
fi

# The commit gate carries its own copy of strip_wrappers, and a repair in one
# has failed to be a repair in the other more than once in this repo.
CGGRAM_FAIL=""
for cmd in \
  '{ git add -A; git commit -m x; }' \
  'if true; then git add -A && git commit -m x; fi' \
  '! git commit -am x' \
  'for i in 1; do git commit -am x; done' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGGRAM_FAIL="$CGGRAM_FAIL
    $cmd"
done
if [[ -z "$CGGRAM_FAIL" ]]; then
  ok "commit corpus shell grammar: compound spellings are denied in the commit gate too"
else
  bad "commit corpus shell grammar: the same repair must land in both gates" \
      "these scanned a stale index unchecked:$CGGRAM_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END index-verb-axis
# --- the commit gate's QUOTED-WORD axis (1.0.8, B3b and F5) -----------------
# Quoting the binary or the subcommand deleted the word this gate matches on, so
# the line stopped being a commit as far as Check 0 could see. An odd number of
# quote characters anywhere swallowed the real `git commit` with them.
CGQ_FAIL=""
for cmd in \
  '"git" commit -am x' \
  'git "commit" -am x' \
  "'git' 'commit' -am x" \
  'git add . && "git" commit -m x' \
  "echo 'don'\\''t' && git add . && git commit -m x" \
  ; do
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGQ_FAIL="$CGQ_FAIL
    $cmd"
done
if [[ -z "$CGQ_FAIL" ]]; then
  ok "commit corpus quoted word: quoting the binary or the subcommand does not hide the commit"
else
  bad "commit corpus quoted word: a quoted command word must still be the command word" \
      "these skipped Check 0 and all three scans:$CGQ_FAIL"
fi

CGQ_ALLOW_FAIL=""
for cmd in \
  'echo "git add ." && git commit -m x' \
  'git commit -m "add everything and commit"' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGQ_ALLOW_FAIL="$CGQ_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGQ_ALLOW_FAIL" ]]; then
  ok "commit corpus quoted word: a mention inside quotes is still not an operation"
else
  bad "commit corpus quoted word: keeping quoted words must not manufacture staging" \
      "these were denied:$CGQ_ALLOW_FAIL"
fi

# --- the commit gate's AMPERSAND-SEPARATOR axis (1.0.7) ---------------------
# Same character, same missing separator, other gate. Asserted here rather than
# inferred from the close-gate cases: the two hooks carry their own copy of the
# splitter line, and this suite has already watched a repair land in one and not
# the other.
CGAMP_N=0; CGAMP_FAIL=""
for cmd in \
  'git stash pop & git commit -m x' \
  'git add -A & git commit -m x' \
  'echo hi & git commit -am x' \
  'git commit -m x & git add -A' \
  ; do
  # The last one is the case that keeps the F1 position rule honest, and it
  # caught the first cut of that rule. `&&` guarantees the commit finished
  # before the add starts, so the add cannot make the index stale; `&` does
  # NOT, because it backgrounds the commit and the two race. A position check
  # that does not know the difference clears a real hole.
  CGAMP_N=$((CGAMP_N + 1))
  [[ "$(cg_verdict "$cmd")" == "deny" ]] || CGAMP_FAIL="$CGAMP_FAIL
    $cmd"
done
if [[ -z "$CGAMP_FAIL" ]]; then
  ok "commit corpus ampersand separator: all $CGAMP_N backgrounded spellings are denied"
else
  bad "commit corpus ampersand separator: a staging verb after a single & must not escape the commit gate" \
      "these scanned a stale index unchecked:$CGAMP_FAIL"
fi

CGAMP_ALLOW_FAIL=""
for cmd in \
  'git status & git commit -m x' \
  'sleep 1 & git commit -m x' \
  ; do
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGAMP_ALLOW_FAIL="$CGAMP_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CGAMP_ALLOW_FAIL" ]]; then
  ok "commit corpus ampersand separator: a backgrounded read-only command still passes"
else
  bad "commit corpus ampersand separator: & must not turn read-only commands into denials" \
      "these were denied:$CGAMP_ALLOW_FAIL"
fi

# --- the commit gate's NEWLINE-SEPARATOR axis (1.0.7) -----------------------
# The same whitespace squeeze, the same collapse: a stage-and-commit split
# across two lines became one segment, so Check 0 saw only the first command and
# the three staged-content checks then read an index nobody had judged. Named by
# a finder in the scoped run alongside the close-gate half, which is what a
# shared normaliser defect looks like from two directions.
CG_NL_FAIL=""
CG_NL_N=0
for payload in "$(printf 'git add .\ngit commit -m x')" \
               "$(printf 'git status\ngit add -A\ngit commit -m x')" \
               "$(printf '# ready\ngit add -A && git commit -m x')"; do
  CG_NL_N=$((CG_NL_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_NL_FAIL="$CG_NL_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_NL_FAIL" ]]; then
  ok "commit corpus newline separator: all $CG_NL_N multi-line stage-and-commit spellings are denied"
else
  bad "commit corpus newline separator: a commit after a newline must not escape the gate ($CG_NL_N generated)" \
      "these escaped (~ marks the newline):$CG_NL_FAIL"
fi

# The inverse: a newline in a commit MESSAGE is ordinary, and must not start
# denying clean commits.
CG_NL_ALLOW_FAIL=""
for payload in "$(printf 'git commit -m "line one\nline two"')" \
               "$(printf 'echo building\ngit status')"; do
  [[ "$(cg_verdict "$payload")" == "allow" ]] || CG_NL_ALLOW_FAIL="$CG_NL_ALLOW_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_NL_ALLOW_FAIL" ]]; then
  ok "commit corpus newline separator: a newline inside a message does not deny a clean commit"
else
  bad "commit corpus newline separator: a newline inside a message must not deny a clean commit" \
      "these were denied (~ marks the newline):$CG_NL_ALLOW_FAIL"
fi

# --- the LINE-CONTINUATION axis (1.0.7, found by the adversarial review) -----------
# A backslash before a newline is a CONTINUATION, not a separator: the shell
# joins the lines into one command. The 1.0.7 newline fix converted every
# newline into a segment break, so `git commit \<newline> -am x` put -am in a
# different segment from the commit and the auto-staging check never saw it.
# v1.0.6 denied it. That is a regression introduced by a fix, which is this
# repo's most-repeated defect class, and it was caught by the leg rather than
# by the person who wrote it.
CG_CONT_FAIL=""
CG_CONT_N=0
for payload in "$(printf 'git commit \\\n  -am "x"')" \
               "$(printf 'git add -A \\\n  && git commit -m x')" \
               "$(printf 'git \\\n  commit \\\n  -am x')"; do
  CG_CONT_N=$((CG_CONT_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_CONT_FAIL="$CG_CONT_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CG_CONT_FAIL" ]]; then
  ok "commit corpus line continuation: all $CG_CONT_N continued spellings are denied"
else
  bad "commit corpus line continuation: a continued command is ONE command ($CG_CONT_N generated)" \
      "these escaped (~ marks the newline):$CG_CONT_FAIL"
fi

# And the close gate, same joint.
CORPUS_CONT_FAIL=""
for payload in "$(printf 'git merge --no-ff \\\n  spec/0001-thing')" \
               "$(printf 'git merge \\\n  --no-ff \\\n  spec/0001-thing')"; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || CORPUS_CONT_FAIL="$CORPUS_CONT_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CORPUS_CONT_FAIL" ]]; then
  ok "corpus line continuation: a continued merge is still one merge"
else
  bad "corpus line continuation: a continued merge must not escape the close gate" \
      "these escaped (~ marks the newline):$CORPUS_CONT_FAIL"
fi


# --- the QUOTE-PAIRING axis (1.0.7) -----------------------------------------
# The normaliser strips quoted spans so a message mentioning a staging verb
# cannot trip the gate. It did that with two independent sed passes, singles
# then doubles, which pairs quote characters ACROSS segments: an apostrophe in
# ordinary English in one segment pairs with an apostrophe in a later one and
# everything between them is deleted, including the governed token.
#
# Both spellings below must deny, and they are MIRRORS of each other. That is
# the whole point of asserting both: singles-first defeats the first, doubles-
# first defeats the second, and satisfying one by reordering the passes just
# moves the hole. Only a left-to-right scan that respects whichever quote opened
# first satisfies both at once.
CG_QUOTE_FAIL=""
CG_QUOTE_N=0
for payload in 'echo "here'"'"'s why" && git add . && echo "let'"'"'s go" && git commit -m "wip"' \
               'echo "it'"'"'s fine" && git add -A && git commit -m "don'"'"'t ship"' \
               "echo 'a\"b' && git add -A && git commit -m 'c\"d'" \
               "echo 'say \"go\"' && git add . && git commit -m 'ship \"it\"'"; do
  CG_QUOTE_N=$((CG_QUOTE_N + 1))
  [[ "$(cg_verdict "$payload")" == "deny" ]] || CG_QUOTE_FAIL="$CG_QUOTE_FAIL
    $payload"
done
if [[ -z "$CG_QUOTE_FAIL" ]]; then
  ok "commit corpus quote pairing: all $CG_QUOTE_N prose-punctuation spellings are denied"
else
  bad "commit corpus quote pairing: punctuation in prose must not erase the commit ($CG_QUOTE_N generated)" \
      "these escaped:$CG_QUOTE_FAIL"
fi

# The inverse, and it is the reason the spans are stripped at all: a message
# that merely MENTIONS a staging verb is not a staging command, and an ordinary
# apostrophe must not start denying clean commits.
CG_QUOTE_ALLOW_FAIL=""
for payload in 'git commit -m "it'"'"'s fine"' \
               'git commit -m "we should git add . later"'; do
  [[ "$(cg_verdict "$payload")" == "allow" ]] || CG_QUOTE_ALLOW_FAIL="$CG_QUOTE_ALLOW_FAIL
    $payload"
done
if [[ -z "$CG_QUOTE_ALLOW_FAIL" ]]; then
  ok "commit corpus quote pairing: a clean commit whose message contains punctuation or a verb still passes"
else
  bad "commit corpus quote pairing: a clean commit must not be denied by its own message" \
      "these were denied:$CG_QUOTE_ALLOW_FAIL"
fi


# --- MUST ALLOW: ordinary work, and prose that mentions the verbs ------------
CGA_N=0; CGA_FAIL=""
for cmd in \
  'git commit -m x' \
  'git commit -m "remember to git add the new file next time"' \
  'git commit -m "this supersedes the git rm approach"' \
  'git commit --amend --no-edit' \
  'git status' \
  'git log --oneline' \
  'git add -A' \
  'npm run build' \
  'echo git add . && git commit -m x' ; do
  CGA_N=$((CGA_N + 1))
  [[ "$(cg_verdict "$cmd")" == "allow" ]] || CGA_FAIL="$CGA_FAIL
    $cmd"
done
if [[ -z "$CGA_FAIL" ]]; then
  ok "commit corpus allow: all $CGA_N ordinary commit-path operations pass"
else
  bad "commit corpus allow: ordinary operations must not be denied" \
      "a gate that denies these is one people disable:$CGA_FAIL"
fi

# --- THE INDEX THE SCANS READ: a documented hole (1.0.7) --------------------
# The commit gate scans the index of CLAUDE_PROJECT_DIR, which is not
# necessarily the index the commit will actually use: `git -C sub commit`
# commits a nested repository's index, and GIT_INDEX_FILE names a different one
# outright. Both were confirmed against the shipped tree.
#
# Documented rather than fixed, deliberately. Making the gate follow the index
# would mean re-deriving the target repository from the command line for every
# spelling, which is the parser-chasing this project has now been burned by
# twice; and a nested repository is a different project, whose own instance
# governs it if it has one. So the hole is named where users read and asserted
# here, which is the standing bargain for every deliberate gap.
CGIDX="$WORK/commit-index"
git_init "$CGIDX"; sdd_json "$CGIDX"
mkdir -p "$CGIDX/sub"
git_init "$CGIDX/sub"
printf 'a line with an %s in it\n' "$EMDASH" > "$CGIDX/sub/prose.md"
git -C "$CGIDX/sub" add -A
assert_true "commit index 0: the nested repo really has em-dash content staged" \
  "the fixture does not carry the content whose escape is being asserted, so the pass below would prove nothing" \
  test -n "$(git -C "$CGIDX/sub" diff --cached --name-only)"
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'git -C sub commit -m "add fixture"')"
expect_allow "commit index a: a nested repo's commit is not scanned (documented hole)"
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'GIT_INDEX_FILE=alt.index git commit -m x')"
expect_allow "commit index b: a commit against a named index file is not scanned (same hole)"
# The pairing that makes the hole survivable: the project's OWN index is still
# scanned, so the gap is about other repositories, not about this one.
printf 'a line with an %s in it\n' "$EMDASH" > "$CGIDX/prose.md"
git -C "$CGIDX" add -A
run_hook "$HOOKS/commit-gate.sh" "$CGIDX" "$(bash_payload 'git commit -m "add fixture"')"
expect_deny "commit index c: this project's own staged content is still scanned" "em-dash"

# =============================================================================
# THE PUBLIC README NAMES EXACTLY ONE EDITION (found in external review)
#
# publish/README.public.md line 12 said "edition v1.6" while four other lines in
# the same file said v1.7, so a publish would have named the shipping edition
# wrong in its opening paragraph. The staged export passed anyway, and THAT is
# the finding: publish-setlist.sh checked the README CONTAINS "edition v1.7" and
# never checked for the absence of a prior one, while CLAUDE.md describes the
# script as refusing "if publish/README.public.md still names a prior edition
# version". The description claimed more than the check did.
#
# Same class as the lifecycle-list drift this branch already caught: a fix that
# covered every copy somebody thought of. Two assertions, because they fail for
# different reasons: the INVARIANT (the file names one edition) runs on every
# commit and would have caught the defect the day it was written, and the GATE
# (the publish script refuses a stale one) is what stops it reaching a publish.
# =============================================================================
PUBR="$ROOT/publish/README.public.md"
if [[ ! -f "$PUBR" ]]; then
  ok "public README edition: SKIPPED, publish/ is absent (expected in the public repo, which does not carry the publish tooling)"
else
  ED_V="$(grep -oE '^\*\*Edition v[0-9]+\.[0-9]+' "$ROOT/setlist.md" | head -n1 | grep -oE 'v[0-9]+\.[0-9]+' || true)"
  assert_true "public README edition: the edition version was resolved from setlist.md" \
    "the Edition header could not be parsed, so the comparison below would compare against nothing" \
    test -n "$ED_V"
  # THE CLAIM LIVES ON ONE LINE, and the invariant is anchored there (narrowed
  # 2026-08-29 by owner ruling; the gate in publish-setlist.sh carries the full
  # reasoning and the cost). The self-description is the document's statement
  # about which edition users are getting; a provenance citation elsewhere
  # ("since v1.7") is a statement about when a claim was first made, and the
  # old whole-file rule could not tell those apart.
  PUB_SELF="$(grep -n 'The current edition of the framework document is' "$PUBR" | head -n1 || true)"
  PUB_SELF_EDS="$(printf '%s\n' "$PUB_SELF" | sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  PUB_SELF_STALE="$(printf '%s\n' "$PUB_SELF_EDS" | grep -v '^$' | grep -vx "$ED_V" || true)"
  if [[ -n "$PUB_SELF" && -z "$PUB_SELF_STALE" && -n "$PUB_SELF_EDS" ]]; then
    ok "public README edition: the self-description names $ED_V and no other edition"
  else
    bad "public README edition: the self-description names $ED_V and no other edition" \
        "line=[${PUB_SELF:-<absent>}] stale=[$(printf '%s' "$PUB_SELF_STALE" | tr '\n' ' ')]; an absent line is a failure, not a pass, because a check that cannot find its subject has not checked it"
  fi

  # THE SECOND CHECK, weaker and stated as such: every OTHER two-component
  # version must sit in a provenance construction. A bare stale version
  # anywhere in the file still fails, so the narrowing bought the ratified
  # boundary sentence and not a general exemption. Two-component versions only,
  # and never part of a three-component one, so a plugin version like v1.1.0 is
  # not mistaken for an edition.
  PUB_EDS="$(sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' "$PUBR" | sed -E 's/(since|in) v[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  PUB_STALE="$(printf '%s\n' "$PUB_EDS" | grep -v '^$' | grep -vx "$ED_V" || true)"
  if [[ -z "$PUB_STALE" ]]; then
    ok "public README edition: no BARE stale edition version outside a provenance citation"
  else
    bad "public README edition: no BARE stale edition version outside a provenance citation" \
        "it also names: $(printf '%s' "$PUB_STALE" | tr '\n' ' ')"
  fi

  # THE NARROWING IS NOT A HOLE, asserted rather than promised: a stale edition
  # planted BARE in the file must still fail the second check. Without this the
  # narrowing above is a claim about what the gate still catches, made by the
  # person who narrowed it.
  PUBN="$WORK/pub-narrow.md"; sed -e 's/$/ /' "$PUBR" > "$PUBN"
  printf 'This project has been on edition v0.9 for a while.\n' >> "$PUBN"
  PUBN_EDS="$(sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/ /g' "$PUBN" | sed -E 's/(since|in) v[0-9]+\.[0-9]+/ /g' | grep -oE 'v[0-9]+\.[0-9]+' | sort -u || true)"
  if printf '%s\n' "$PUBN_EDS" | grep -qx 'v0.9'; then
    ok "public README edition control: a BARE stale version planted in the file is still caught after the narrowing"
  else
    bad "public README edition control: a BARE stale version planted in the file is still caught after the narrowing" \
        "the narrowing let a bare stale edition through, which is a hole and not a scoping decision"
  fi
fi

# The GATE itself, extracted verbatim from publish-setlist.sh and driven against
# a seeded stale README. Extracted rather than reimplemented, for the reason the
# CI scope check gives: a copy drifts, and then the test asserts things about a
# gate that is no longer the one running.
PUBSH="$ROOT/publish/publish-setlist.sh"
if [[ ! -f "$PUBSH" ]]; then
  ok "public README gate: SKIPPED, publish/ is absent (expected in the public repo)"
else
  PG="$WORK/pubgate"; rm -rf "$PG"; mkdir -p "$PG"
  awk '/# >>> EDITION-STRING-GATE-BEGIN/{f=1;next} /# <<< EDITION-STRING-GATE-END/{f=0} f' "$PUBSH" > "$PG/gate.sh"
  if [[ ! -s "$PG/gate.sh" ]]; then
    bad "public README gate: the EDITION-STRING-GATE markers exist in publish-setlist.sh" \
        "could not extract the gate; missing or renamed markers mean this check cannot run, which is a failure rather than a pass"
  else
    # THE SELF-DESCRIPTION LINE IS NOW THE GATE'S SUBJECT, so every fixture
    # carries one. That is not fixture bookkeeping: the gate anchors there
    # structurally (narrowed 2026-08-29), and a fixture without the line would
    # exercise only the absent-subject refusal and say nothing about the rule.
    SELF='The current edition of the framework document is setlist.md (edition v9.9).'

    # Clean: only the current edition. Must PASS.
    printf '%s\nSetlist, the current one.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a README naming only the current edition is accepted"
    else
      bad "public README gate: a README naming only the current edition is accepted" "it refused a clean file"
    fi
    # Stale: names a prior edition too, BARE. Must REFUSE.
    printf '%s\nBut this line still says edition v9.8.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a README still naming a PRIOR edition is refused" \
          "it accepted a file naming v9.8 alongside v9.9, which is the defect this gate exists for"
    else
      ok "public README gate: a README still naming a PRIOR edition is refused"
    fi
    # THE SELF-DESCRIPTION ITSELF NAMING A STALE EDITION. This is the defect the
    # gate was written for and the one the narrowing must not have loosened.
    printf 'The current edition of the framework document is setlist.md (edition v9.8).\n' > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a SELF-DESCRIPTION naming a stale edition is refused" \
          "the narrowing let the gate's own founding defect through, which would be a hole and not a scoping decision"
    else
      ok "public README gate: a SELF-DESCRIPTION naming a stale edition is refused"
    fi
    # ABSENT SUBJECT IS A REFUSAL, NOT A PASS. A check that cannot find the line
    # it judges has not judged it, which is this project's own rule about its
    # own checks and the reason the narrowing is safe to make at all.
    printf 'Setlist, edition v9.9, with no self-description anywhere.\n' > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      bad "public README gate: a README with NO self-description line is refused" \
          "the gate passed a file whose subject it could not find, which is the empty-result-as-verdict class"
    else
      ok "public README gate: a README with NO self-description line is refused"
    fi
    # A PROVENANCE CITATION IS NOT A CLAIM ABOUT THE CURRENT EDITION. This is
    # what the narrowing bought, asserted rather than assumed, and it is the
    # ratified boundary sentence's exact shape.
    printf '%s\nwhere this project has said the real boundary lives since v1.7.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a 'since vX.Y' provenance citation is accepted, which is what the narrowing bought"
    else
      bad "public README gate: a 'since vX.Y' provenance citation is accepted, which is what the narrowing bought" \
          "the gate still cannot tell a citation of when a claim was made from a claim about what users are getting"
    fi
    # A three-component plugin version must not be read as an edition.
    printf '%s\nplugin v9.8.1 is irrelevant here.\n' "$SELF" > "$PG/README.public.md"
    if ( SCRIPT_DIR="$PG" EDITION_V="v9.9" bash "$PG/gate.sh" ) >/dev/null 2>&1; then
      ok "public README gate: a three-component plugin version is not mistaken for an edition"
    else
      bad "public README gate: a three-component plugin version is not mistaken for an edition" \
          "it refused on v9.8.1, so the gate would block ordinary publishes"
    fi
  fi
fi

# =============================================================================
# CHECK 4, THE GIT IDENTITY GATE (BL-007, plugin 1.1.0)
#
# One machine holding a work identity and a personal one is the ordinary case,
# and a commit under the wrong one is a compliance problem on a work repo. The
# gate catches it at COMMIT time, where the fix is `git config` plus an amend,
# rather than at push time, where it is a rebase.
#
# THE ABSENT-KEY CASE IS THE ONE THAT MATTERS MOST, because it is every instance
# that already exists: no `identity` key means no check and no output, and the
# gate must behave exactly as it did before this release.
# =============================================================================
CGID="$WORK/commit-identity"
git_init "$CGID"; sdd_json "$CGID"
mkdir -p "$CGID/specs"; printf 'x\n' > "$CGID/a.txt"
git -C "$CGID" add -A >/dev/null 2>&1

# No identity key: unchanged behaviour.
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity a: no identity key means no check (every pre-1.1.0 instance)"

# Configured and MATCHING: still allowed, and the gate is otherwise untouched.
CGID_EMAIL="$(git -C "$CGID" config user.email)"
jq --arg e "$CGID_EMAIL" '. + {identity:{user_email:$e}}' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity b: a matching identity is allowed"

# Configured and MISMATCHED: denied, naming both values and the remedy.
jq '.identity.user_email = "someone-else@example.invalid"' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity c: a mismatched identity is refused" "CM-IDENTITY"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity d: the denial names the EXPECTED identity" "someone-else@example.invalid"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity e: the denial names the ACTUAL identity" "$CGID_EMAIL"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_deny "commit identity f: the denial names the remedy" "git config user.email"

# An identity key present but EMPTY is not a declaration, so it is not a check.
jq '.identity.user_email = ""' "$CGID/.claude/sdd.json" > "$CGID/.claude/sdd.json.tmp" \
  && mv "$CGID/.claude/sdd.json.tmp" "$CGID/.claude/sdd.json"
run_hook "$HOOKS/commit-gate.sh" "$CGID" "$(bash_payload 'git commit -m x')"
expect_allow "commit identity g: an empty declared identity is treated as absent, not as a mismatch"

# =============================================================================
# CHECK 3, THE SPEC-LIFECYCLE LOCKSTEP (D5, cut worklist 4.2)
#
# Until now the suite had NO case for CM-STATUS-MISSING at all, which is exactly
# how the gap was able to open: the edition gained BUILT and PARKED, check 3
# enumerates the vocabulary literally, and nothing anywhere compared the two. A
# staged `Status: BUILT` without specs/STATUS.md was allowed through by a check
# whose whole job is to catch that.
#
# Two mechanisms, because either alone is insufficient. The SET comparison
# catches a state added to the protocol and not to the gate. The BEHAVIOURAL
# cases catch a list that agrees with the edition and does not actually work,
# which is the failure a pure string comparison cannot see.
#
# The behavioural cases are parametrised over the canonical set rather than
# written out per state (redesign section 8, promoted to doctrine at addendum
# 6.4). A new state therefore arrives already covered in both directions, which
# is the point: the 2026-07-29 mutation run found two fixed defects each held
# closed by a SINGLE assertion, and that is what parametrising prevents.
# =============================================================================

CANON_STATES="$(bash "$SCRIPTS/part.sh" lifecycle-states "$ROOT/setlist.md" 2>/dev/null | sort | tr '\n' ' ')"
assert_true "lifecycle canon: the edition's SDD-LIFECYCLE-STATES block extracts non-empty" \
  "part.sh lifecycle-states returned nothing, so every comparison below would compare against an empty set and pass" \
  test -n "$(printf '%s' "$CANON_STATES" | tr -d '[:space:]')"

HOOK_STATES="$(grep -m1 -E "^CM_LIFECYCLE_STATES=" "$HOOKS/commit-gate.sh" \
  | sed -e "s/^CM_LIFECYCLE_STATES='//" -e "s/'.*$//" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [[ "$CANON_STATES" == "$HOOK_STATES" ]]; then
  ok "lifecycle lockstep: commit-gate.sh's enumeration equals the edition's canonical block"
else
  bad "lifecycle lockstep: commit-gate.sh's enumeration equals the edition's canonical block" \
      "edition has [$CANON_STATES] and the hook has [$HOOK_STATES]"
fi

# The STATUS template's legend is the third copy, and it is stamped into every
# instance, so a state missing there is a state operators never learn about.

# Every PROSE copy of the enumeration, not just the stamped legend. The
# spec-authoring skill carried "QUEUED, ACTIVE, REVISED, CLOSED, DRAFT" through
# the whole of the D5 work and nothing noticed, because the lockstep only
# covered the hook, the edition and the template. A list a human reads and
# copies into a spec is as much a copy as one a gate greps, and it drifts the
# same way; it was found by a manual sweep, which is exactly the thing that does
# not happen reliably.
for lc_file in "$ROOT/templates/specs/STATUS.md.tmpl" "$ROOT/skills/spec-authoring/SKILL.md"; do
  lc_name="$(basename "$lc_file")"
  for st in $CANON_STATES; do
    if grep -q "$st" "$lc_file"; then
      ok "lifecycle legend: $lc_name names the state $st"
    else
      bad "lifecycle legend: $lc_name names the state $st" "this copy of the enumeration omits it"
    fi
  done
done

# Both directions, per state, against the real hook.
for st in $CANON_STATES; do
  CGL="$WORK/cg-lifecycle"; rm -rf "$CGL"
  git_init "$CGL"; sdd_json "$CGL"
  mkdir -p "$CGL/specs"
  # The base carries NO Status line, so every state below is a genuine staged
  # addition. Seeding it with a real state made the QUEUED case a no-op diff:
  # the assertion failed for a fixture reason and said nothing about the gate,
  # which is the shape of evidence scoped to the wrong thing.
  printf '# Spec 0001\n\nBody text.\n' > "$CGL/specs/0001-thing.md"
  printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | (none) |\n' > "$CGL/specs/STATUS.md"
  git -C "$CGL" add -A >/dev/null 2>&1; git -C "$CGL" commit -qm "base" >/dev/null 2>&1

  # DENY: the transition is staged, STATUS.md is not.
  printf '# Spec 0001\n\nStatus: %s\n\nBody text.\n' "$st" > "$CGL/specs/0001-thing.md"
  git -C "$CGL" add specs/0001-thing.md >/dev/null 2>&1
  run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "move the spec"')"
  expect_deny "lifecycle check 3: a staged transition to $st without specs/STATUS.md is refused" "CM-STATUS-MISSING"

  # ALLOW: the same transition WITH STATUS.md staged. Without this direction the
  # case above is satisfied by a gate that denies everything.
  printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | %s |\n' "$st" > "$CGL/specs/STATUS.md"
  git -C "$CGL" add -A >/dev/null 2>&1
  run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "move the spec"')"
  expect_allow "lifecycle check 3: a staged transition to $st WITH specs/STATUS.md is allowed"
done

# The non-regression: an ordinary mid-build spec edit that moves no state must
# not demand STATUS.md. This is the false-denial direction, and it is the one
# that would make the gate unusable rather than merely leaky.
CGL="$WORK/cg-lifecycle-noop"; rm -rf "$CGL"
git_init "$CGL"; sdd_json "$CGL"
mkdir -p "$CGL/specs"
printf '# Spec 0001\n\nStatus: ACTIVE\n\nSome body text.\n' > "$CGL/specs/0001-thing.md"
printf '| Spec | Title | Status |\n|---|---|---|\n| 0001 | Thing | ACTIVE |\n' > "$CGL/specs/STATUS.md"
git -C "$CGL" add -A >/dev/null 2>&1; git -C "$CGL" commit -qm "base" >/dev/null 2>&1
printf '# Spec 0001\n\nStatus: ACTIVE\n\nSome body text.\nAnd another paragraph.\n' > "$CGL/specs/0001-thing.md"
git -C "$CGL" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$CGL" "$(bash_payload 'git commit -m "mid-build edit"')"
expect_allow "lifecycle check 3: an ordinary spec edit that moves no state does not demand STATUS.md"

