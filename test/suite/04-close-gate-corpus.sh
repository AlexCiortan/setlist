#!/usr/bin/env bash
# test/suite/04-close-gate-corpus.sh: shard 4 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE ATTACK CORPUS (1.0.5)
#
# Every example test in this file encodes something its author thought of, and
# every bypass this project has shipped lived in what its author did not. Four
# releases in a row were repaired by an outside reader running payloads nobody
# here had written. That is not a discipline problem; it is what example-based
# testing does to a PARSER, whose input space is combinatorial and whose
# failures are adversarial.
#
# So the corpus is GENERATED, not enumerated. It crosses the generator classes
# that have actually drawn blood in this codebase:
#   - spelling variance   (the 1.0.1 class: whitespace, git options, quoting)
#   - indirection         (the 1.0.3 IN-1 class: $VAR, -, @{-1}, FETCH_HEAD, SHA)
#   - compounding         (the 1.0.4 class: && ; || and token donation between
#                          segments)
#   - content-as-code     (the 1.0.4 class: prose in -m containing the very
#                          keyword the parser anchors on)
# and asserts a single stated invariant:
#
#   If any segment of a command merges into the trunk and literally names a
#   spec/ or chore/ branch, the close conditions for that branch MUST be
#   evaluated. Nothing appended, prepended, or written in a message may
#   discard it.
#
# The inverse corpus matters as much: a checker that denies everything is a
# checker people rip out, so ordinary syncs must still pass.
# =============================================================================

CORP="$WORK/corpus"
close_fixture "$CORP" no no answered no no true   # deliberately UNCLOSED: every gated merge must deny
git -C "$CORP" branch -f tmp-alias spec/0001-thing
# A chore/ ref sitting on the unclosed spec branch's commit, added 2026-07-28.
#
# It is here rather than in a single dedicated test on purpose: with this ref in
# the shared corpus, EVERY close-gate assertion below runs with a chore sibling
# present, so a regression in the spec-versus-chore tie-break turns dozens of
# assertions red instead of one. 1.0.8 shipped that regression and the whole
# corpus stayed green, because the fixture held the repository constant while
# varying only the command.
#
# The state is ordinary, not adversarial: `git checkout -b chore/wip
# <spec-branch>` and promoting a chore branch to a spec branch both leave two
# refs on one commit, and Part 5b makes chore branches first-class.
git -C "$CORP" branch -f chore/cleanup spec/0001-thing
git -C "$CORP" update-ref refs/remotes/origin/main "$(git -C "$CORP" rev-parse main)"
git -C "$CORP" branch -f release/2.0 main

# corpus_verdict <command> -> echoes deny|allow|error
#
# THE THIRD STATE IS F9-2026, AND IT IS THIS REPOSITORY'S SIGNATURE DEFECT
# SITTING INSIDE THE SUITE THAT IS THE FIRST ITEM OF THE A1 TIER.
#
# This function returned deny or allow, and everything that was not a deny
# collapsed to `allow`: a crashed hook, a nonzero exit, output that is not JSON,
# a hook that never ran at all. So "the gate ALLOWED this" and "the gate
# produced nothing" were the same answer, and ~60 call sites below cannot tell
# them apart. That is the same shape as the macOS leg reading `tail`'s exit code
# and the attestation matching a version string: a check whose FAILURE cannot
# reach a verdict.
#
# The states, and the boundary between the last two is the whole fix:
#   deny   the gate produced a verdict and it is deny
#   allow  the gate exited 0 AND either said nothing (allow is silence, which is
#          this layer's documented contract) or produced parseable JSON whose
#          verdict is not deny
#   error  the gate exited NONZERO, or produced output that is not parseable
#          JSON. Neither of those is an allow, and calling them one is the
#          defect.
#
# `error` is deliberately not equal to `allow`, so every existing call site that
# tests `== "allow"` now fails on a crashed gate instead of passing on one. That
# is the point: the fix is worth nothing if the new state is swallowed by the
# comparison it exists to correct.
corpus_verdict() {
  local out rc verdict
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'error'; return; fi
  # Silence is the documented allow. Anything else must PARSE before it is read.
  if [[ -z "$out" ]]; then printf 'allow'; return; fi
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then printf 'error'; return; fi
  verdict="$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [[ "$verdict" == "deny" ]]; then printf 'deny'; else printf 'allow'; fi
}

# CONTROL FIRST (Phase 3 of the hostile-review protocol). A harness that has
# not proven it can see a deny proves nothing with a pass. Five fake ALLOWs
# were produced during the 1.0.4 strictness review by a fixture missing its
# sdd.json; this is the guard against repeating that.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus control a: the harness can observe a deny on the plain gated merge"
else
  bad "corpus control a: the harness can observe a deny on the plain gated merge" \
      "the control did not deny, so every corpus result below is meaningless"
fi
if [[ "$(corpus_verdict 'git status')" == "allow" ]]; then
  ok "corpus control b: the harness can observe an allow on an ungoverned command"
else
  bad "corpus control b: the harness can observe an allow on an ungoverned command" "git status was denied"
fi

# CONTROL C (F9-2026): the harness can observe an ERROR, and it is not an allow.
#
# Without this the third state is a claim rather than a capability, which is the
# vacuous-comparison family the two controls above already guard against one
# state at a time. A distinguishing input is constructed rather than waited for:
# a stand-in gate that exits nonzero having printed nothing is exactly the shape
# that used to read as `allow`, and the second case is the unparseable-output
# shape, which used to read as `allow` too.
CORP_REALHOOKS="$HOOKS"
HOOKS="$WORK/corp-brokenhook"; rm -rf "$HOOKS"; mkdir -p "$HOOKS"
printf '#!/usr/bin/env bash\nexit 3\n' > "$HOOKS/close-gate.sh"
CORP_V_CRASH="$(corpus_verdict 'git status')"
printf '#!/usr/bin/env bash\nprintf "not json at all\\n"\n' > "$HOOKS/close-gate.sh"
CORP_V_GARBAGE="$(corpus_verdict 'git status')"
HOOKS="$CORP_REALHOOKS"
if [[ "$CORP_V_CRASH" == "error" && "$CORP_V_GARBAGE" == "error" ]]; then
  ok "corpus control c (F9-2026): a crashed gate and an unparseable gate both read as error, not as allow"
else
  bad "corpus control c (F9-2026): a crashed gate and an unparseable gate both read as error, not as allow" \
      "nonzero-exit read as [$CORP_V_CRASH], unparseable output read as [$CORP_V_GARBAGE]; while either is 'allow', a corpus assertion that passes because the gate never ran is indistinguishable from one that passes because the gate decided"
fi

# --- the MUST-DENY corpus ----------------------------------------------------
# >>> SHARD-BEGIN corpus-deny cost=179
if shard_region corpus-deny; then
CORPUS_DENY_N=0
CORPUS_DENY_FAIL=""
for pfx in '' 'git checkout main && '; do
 for gopt in '' '-C . ' '--no-pager '; do
  for flag in '' '--no-ff ' '--squash '; do
   for ref in 'spec/0001-thing' '"spec/0001-thing"' 'origin/spec/0001-thing' 'refs/heads/spec/0001-thing'; do
    for sfx in '' ' -m "close spec"' ' -m "improve merge of main"' ' && git merge main' ' ; git status' ' && echo done' ' -m "merge "'; do
      cmd="${pfx}git ${gopt}merge ${flag}${ref}${sfx}"
      CORPUS_DENY_N=$((CORPUS_DENY_N + 1))
      [[ "$(corpus_verdict "$cmd")" == "deny" ]] || CORPUS_DENY_FAIL="$CORPUS_DENY_FAIL
    $cmd"
    done
   done
  done
 done
done
if [[ "$CORPUS_DENY_N" -lt 100 ]]; then
  bad "corpus deny: the generator produced a real corpus" \
      "only $CORPUS_DENY_N commands were generated; the cross product is broken and this proves almost nothing"
elif [[ -z "$CORPUS_DENY_FAIL" ]]; then
  ok "corpus deny: all $CORPUS_DENY_N generated spec-merge spellings are denied"
else
  bad "corpus deny: every generated spec-merge spelling must be denied ($CORPUS_DENY_N generated)" \
      "these reached the trunk with the close conditions unevaluated:$CORPUS_DENY_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END corpus-deny
corpus_verdict_reason() { # corpus_verdict_reason <command> -> the deny reason text
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  printf '%s' "$out" | jq -r '.setlistAdvisory.reason // .hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

# --- the DENY-CODE axis (1.0.8, routine item 4) ------------------------------
# Every deny carries a stable bracketed CODE, so an assertion can test the
# gate's IDENTITY instead of its prose. Backlog item 4's trigger was concrete:
# B2 reworded the commit gate's deny and dogfood/hook-smoke.sh still asserted
# the old wording, so a green suite sat beside a red smoke and neither the badge
# nor the publish could see it. A reworded message should never break a test,
# and a test should never pass because two different denials happen to share a
# phrase.
#
# Asserted STRUCTURALLY rather than one code at a time: every deny site in every
# stamped hook must carry a code, so adding a new deny without one fails here
# rather than being noticed later by whoever greps for it.
DC_MISSING=""
for hookfile in "$HOOKS"/close-gate.sh "$HOOKS"/commit-gate.sh "$HOOKS"/scope-hook.sh; do
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf '%s' "$line" | grep -qE '\[(CG|CM|SH)-[A-Z0-9-]+\]' || DC_MISSING="$DC_MISSING
    $(basename "$hookfile"): $(printf '%s' "$line" | cut -c1-72)"
  done <<DCEOF
$(grep -hE '^\s*deny(_literal)? "' "$hookfile")
DCEOF
done
if [[ -z "$DC_MISSING" ]]; then
  ok "deny codes: every deny site in every stamped hook carries a stable code"
else
  bad "deny codes: a deny without a code cannot be asserted except by its prose" \
      "these carry no [XX-CODE]:$DC_MISSING"
fi

# The codes must be UNIQUE, or two different failures are indistinguishable to
# any assertion that uses them, which is the defect this axis exists to remove
# wearing a different hat.
DC_DUPES="$(grep -ohE '\[(CG|CM|SH)-[A-Z0-9-]+\]' "$HOOKS"/close-gate.sh "$HOOKS"/commit-gate.sh "$HOOKS"/scope-hook.sh | sort | uniq -d)"
if [[ -z "$DC_DUPES" ]]; then
  ok "deny codes: every code is unique across the stamped hooks"
else
  bad "deny codes: two denials sharing a code cannot be told apart" "duplicated: $DC_DUPES"
fi

# And the code must actually REACH the agent, not merely exist in the source.
# The reason string is what the harness delivers verbatim, so it is read back
# out of a real deny rather than assumed to have survived.
if printf '%s' "$(corpus_verdict_reason 'git merge --no-ff spec/0001-thing')" | grep -q 'CG-'; then
  ok "deny codes: the code survives into the reason the agent actually receives"
else
  bad "deny codes: a code that does not reach the agent is not an interface" \
      "the delivered reason carried no CG- code"
fi

# --- the SDD-SHAPE axis (1.0.8, F1) -----------------------------------------
# `jq -e .` tests JSON VALIDITY, not SHAPE. Two perfectly valid inputs disabled
# the trunk rule in BOTH the close gate and the scope hook, in silence:
# a top-level array (so `.trunk` errors and TRUNK reads empty) and TWO documents
# in one file (so `.trunk` prints twice and TRUNK reads two lines). Neither needs
# an attacker: a hand-edited file and a half-merged config produce exactly these.
for shape in 'array' 'multidoc'; do
  SH="$WORK/inst-shape-$shape"
  close_fixture "$SH" no no answered no no true
  case "$shape" in
    array)    printf '[]' > "$SH/.claude/sdd.json" ;;
    multidoc) printf '{"trunk":"main"}\n{"trunk":"main"}\n' > "$SH/.claude/sdd.json" ;;
  esac
  # It really IS valid JSON to jq, which is the whole point of the finding.
  if [[ "$shape" == "array" ]]; then
    assert_true "sdd-shape $shape 0: the fixture is valid JSON, so validity is not the test" \
      "the fixture is malformed, so this case would pass for the wrong reason" \
      jq -e . "$SH/.claude/sdd.json"
  fi
  run_hook "$HOOKS/close-gate.sh" "$SH" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
  expect_deny "sdd-shape $shape a: the close gate refuses a config that is not one object" "JSON OBJECT"
  OUT="$(jq -nc --arg p "$SH/src/app.js" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' \
        | CLAUDE_PROJECT_DIR="$SH" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    ok "sdd-shape $shape b: the scope hook refuses it too, so the trunk rule is not silently off"
  else
    bad "sdd-shape $shape b: the scope hook must refuse a config it cannot read a trunk from" \
        "a $shape sdd.json disabled the trunk rule and the write reached the trunk"
  fi
done

# --- the QUOTED-CONTENT axis (1.0.8, B1/B3b and F4 to F7) -------------------
# The two gates handled quoting in the way that was wrong for the other. The
# close gate deleted quote CHARACTERS and kept their contents, so free text was
# fed to the parser as code; the commit gate deleted quoted SPANS, so quoting a
# word deleted the word it matches on. A quoted span of one shell-safe word is
# now kept as that word and anything else becomes an inert token.
#
# The dimensions here are the four that each produced a finding: quote character,
# POSITION (binary, subcommand, ref, message), and content (bare word, words with
# spaces, words containing a separator, words containing a git command).
QC_FAIL=""
for payload in \
  'git commit -m "todo (git checkout spec/0002-other)" && git merge --no-ff spec/0001-thing' \
  'echo "x && git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  'echo "x; git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  "git commit -m 'wip (git checkout spec/0002-other)' && git merge --no-ff spec/0001-thing" \
  'git merge --no-ff -m "closes spec/0003-done" spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_FAIL="$QC_FAIL
    $payload"
done
if [[ -z "$QC_FAIL" ]]; then
  ok "corpus quoted content: quoted text cannot donate a command or a segment boundary"
else
  bad "corpus quoted content: a quoted span must not contribute code" \
      "these reached the trunk unchecked:$QC_FAIL"
fi

# THE ARGUMENT DIRECTION, which is why the commit gate's span-dropping repair
# was reverted when it was tried on this gate: a quoted REF must still be read.
QC_ARG_FAIL=""
for payload in \
  'git merge "spec/0001-thing"' \
  "git merge 'spec/0001-thing'" \
  'git merge --no-ff "spec/0001-thing" -m "close"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_ARG_FAIL="$QC_ARG_FAIL
    $payload"
done
if [[ -z "$QC_ARG_FAIL" ]]; then
  ok "corpus quoted content: a quoted REF is still read, so the span is not simply dropped"
else
  bad "corpus quoted content: dropping quoted spans loses the branch name" \
      "these stopped being seen as merges at all:$QC_ARG_FAIL"
fi


# THE PLACEHOLDER MUST NOT BE FORGEABLE. `@@Q@@` is what a multi-word quoted
# span becomes, so a payload can type it literally and ask whether the gate
# treats its own internal marker as data. It must: the token is inert by
# construction (it is not a command word, not a separator and not a ref), but
# "inert by construction" is a claim, and this repo has been bitten by claims
# that were reasoned rather than asserted.
QC_TOK_FAIL=""
for payload in \
  'echo @@Q@@ && git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing @@Q@@' \
  'git commit -m "@@Q@@ git checkout spec/0002-other" && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_TOK_FAIL="$QC_TOK_FAIL
    $payload"
done
if [[ -z "$QC_TOK_FAIL" ]]; then
  ok "corpus quoted content: a literal @@Q@@ in the payload cannot hide a merge"
else
  bad "corpus quoted content: the internal placeholder must be inert as INPUT too" \
      "these escaped by typing the marker:$QC_TOK_FAIL"
fi
# And it gets NO privileged treatment: a trunk merge naming it is a merge whose
# target the gate cannot establish, so it refuses, exactly as it does for any
# other unresolvable ref. The first cut of this case expected an ALLOW and the
# gate was right and the test was wrong, which is worth leaving in the record:
# an unresolvable merge target denies, and the placeholder is not an exception
# to that in either direction.
if [[ "$(corpus_verdict 'git merge --no-ff @@Q@@')" == "deny" ]]; then
  ok "corpus quoted content: the placeholder is treated as an unresolvable ref, not as a special case"
else
  bad "corpus quoted content: @@Q@@ must be refused like any ref the gate cannot resolve" \
      "it was allowed, which means the marker is being special-cased somewhere"
fi

# AND THE ALLOW DIRECTION. A message is not code, and must not become a denial
# just because it contains words that look like one.
QC_ALLOW_FAIL=""
for payload in \
  'git commit -m "merge spec/0001-thing when review is done"' \
  'echo "git merge --no-ff spec/0001-thing"' \
  'git commit -m "an ordinary message"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_ALLOW_FAIL="$QC_ALLOW_FAIL
    $payload"
done
if [[ -z "$QC_ALLOW_FAIL" ]]; then
  ok "corpus quoted content: a message mentioning a merge is not a merge"
else
  bad "corpus quoted content: opaque tokens must not turn messages into denials" \
      "these were denied:$QC_ALLOW_FAIL"
fi

# --- the ESCAPE axis (leg 4, F5 and F31) ------------------------------------
#
# The opaque-token model closed content-as-code through the QUOTE path and left
# the ESCAPE path wide open. Outside quotes a backslash escapes the next
# character, and the normaliser consumed the backslash and emitted that
# character RAW, which handed it straight back to the parser as grammar:
#
#     git commit -m foo\;git\ checkout\ spec/0002-other && git merge --no-ff spec/0001-thing
#
# Bash parses that as ONE argument to -m, so nothing switches branch and the
# merge runs on the trunk. The gate saw a live `;` and live spaces, cut a
# synthetic `git checkout spec/0002-other` segment out of free text, believed
# the shell had moved off the trunk, and skipped every close check. The QUOTED
# spelling of the identical line was already denied, which is the control.
#
# Asserted over the SET of grammar-carrying characters rather than over the `;`
# and the space a finding used, and in BOTH directions, because the same defect
# produces a false DENIAL in the commit gate (F31): a plain commit whose message
# carries an escaped separator was read as a compound stage-and-commit.
QC_ESC_FAIL=""
for esc in '\;' '\&' '\|' '\(' '\)' '\>' '\<'; do
  # free text in a message must not inject a branch switch that hides the merge
  payload="git commit -m foo${esc}git\\ checkout\\ spec/0002-other && git merge --no-ff spec/0001-thing"
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_ESC_FAIL="$QC_ESC_FAIL
    $payload"
done
# and the escaped SPACE on its own, which splits a word into a command
QC_ESC_EXTRA='git\ checkout spec/0002-other && git merge --no-ff spec/0001-thing'
[[ "$(corpus_verdict "$QC_ESC_EXTRA")" == "deny" ]] || QC_ESC_FAIL="$QC_ESC_FAIL
    $QC_ESC_EXTRA"
if [[ -z "$QC_ESC_FAIL" ]]; then
  ok "corpus escape: an escaped separator or space is content, and cannot inject a branch switch"
else
  bad "corpus escape: an escaped character must not be handed back to the parser as grammar" \
      "these were ALLOWED, so unreviewed work reaches the trunk:$QC_ESC_FAIL"
fi

# The control that makes the case above real: the quoted spelling of the same
# line, which denied before this fix and must still deny after it.
if [[ "$(corpus_verdict 'git commit -m "foo;git checkout spec/0002-other" && git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus escape control: the quoted spelling of the same injection still denies"
else
  bad "corpus escape control: the quoted spelling of the same injection still denies" \
      "the control itself allowed, so the escape cases above prove nothing"
fi

# THE ALLOW DIRECTION. An escape that carries no grammar is ordinary text, and
# the fix must not turn every backslash into a denial. The escaped apostrophe in
# particular is the commonest one there is, and its own handling was added to
# fix a defect this file already records.
#
# `spec/0001-thing` is deliberately NOT in this list: it is the corpus fixture's
# non-compliant deny control, so asserting it allows would be asserting the
# fixture is broken. The first cut of this block used it and the suite said so.
QC_ESC_OK_FAIL=""
for payload in \
  "git commit -m it\\'s" \
  'git commit -m fixup\-typo' \
  'echo done\;echo more' \
  'git status' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_ESC_OK_FAIL="$QC_ESC_OK_FAIL
    $payload"
done
if [[ -z "$QC_ESC_OK_FAIL" ]]; then
  ok "corpus escape: an escape carrying no grammar stays ordinary text"
else
  bad "corpus escape: the fix must not deny every backslash" \
      "these were denied:$QC_ESC_OK_FAIL"
fi

# --- the LEG 5 axis, part 3: a quoted template is not evidence --------------
#
# The most reachable hole leg 5 found, because it needs no adversary. Every
# close-condition check read the spec file as one flat string, so a spec that
# QUOTES the Appendix C template inside a fence satisfied all four at once and a
# spec with no Closing report at all merged clean. The template ships fenced in
# setlist.md, it is stamped to specs/TEMPLATE.md, and the spec-authoring skill
# tells authors to copy it: quoting it is ordinary authoring.
#
# And the inventory row's STATUS is a CELL. Grepping the whole row for CLOSED
# let an ACTIVE spec pass on a note column that mentioned another spec's
# closure, which is prose a person writes without thinking.
L5C="$WORK/leg5-content"; close_fixture "$L5C" no no answered no no true
git -C "$L5C" checkout -q spec/0001-thing
cat > "$L5C/specs/0001-thing.md" <<'SPECEOF'
# Spec 0001

Not closed. There is no Closing report section here, only the template quoted
so the next author can copy it:

```markdown
## Closing report
- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact
```
SPECEOF
printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$L5C/specs/STATUS.md"
# close_fixture creates specs/ and NOT src/, so this redirect used to fail
# silently: the shell reported "No such file or directory" on stderr, the suite
# carried on, and the assertion passed on the spec-file change alone. A fixture
# line that has never once worked is worse than a missing one, because it reads
# as covered. Found on the 1.0.9 macOS repair (mkdir added, not the line removed:
# the intent was for the branch to touch code as well as its spec).
mkdir -p "$L5C/src"
echo work >> "$L5C/src/a.txt"
git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "quote the template" >/dev/null 2>&1
git -C "$L5C" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "leg5 content: a fenced quote of the template is not a Closing report" "CG-NO-CLOSING-REPORT"

# The same spec WITH a real report, still quoting the template, must merge. This
# is the direction that breaks every ordinary session if the fix overreaches.
git -C "$L5C" checkout -q spec/0001-thing
cat > "$L5C/specs/0001-thing.md" <<'SPECEOF'
# Spec 0001

## Closing report
- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact

For reference, the template authors copy:

```markdown
## Closing report
- QA Pass 1 report:
  - criterion 1: PASS
- QA Pass 2: done
- Architecture diagram: no impact
```
SPECEOF
git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "real report plus a quote" >/dev/null 2>&1
git -C "$L5C" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "leg5 content control: a real Closing report beside a fenced quote still closes"

# The status CELL, both directions, over every shape the note column takes.
for row_case in \
  'ACTIVE|follows on from 0000 which is CLOSED|deny' \
  'ACTIVE|superseded by 0002, now CLOSED|deny' \
  'DRAFT|see the CLOSED spec 0000|deny' \
  'CLOSED|done|allow' \
  ; do
  st="${row_case%%|*}"; rest="${row_case#*|}"; note="${rest%%|*}"; want="${rest##*|}"
  git -C "$L5C" checkout -q spec/0001-thing
  printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | %s | %s |\n' "$st" "$note" > "$L5C/specs/STATUS.md"
  git -C "$L5C" add -A >/dev/null 2>&1; git -C "$L5C" commit -qm "row $st" >/dev/null 2>&1
  git -C "$L5C" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$L5C" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
  if [[ "$want" == "deny" ]]; then
    expect_deny "leg5 row: status cell [$st] with note [$note] is not CLOSED" "CG-NO-STATUS-ROW"
  else
    expect_allow "leg5 row: status cell [$st] with note [$note] closes"
  fi
done

# --- the LEG 5 axis, part 2: branch tracking must fail closed ---------------
#
# Three of leg 5's seven bypasses are the same shape: a checkout or switch whose
# target the gate could not follow left the tracked branch OFF the trunk, so a
# merge compounded after it read as ordinary feature work and every close check
# was skipped. All three only reproduce from a fixture standing OFF the trunk.
# Tested from the trunk they deny, and a correct gate and a broken one both deny
# there, so a fixture on the trunk cannot fail. That nearly produced two false
# NOT-CONFIRMED verdicts during triage, so the fixture position is asserted
# first rather than assumed.
# spec/0001-thing must be NON-compliant here, or the merge is a legitimate close
# and every case below allows for the right reason while proving nothing. The
# first cut of this block used a compliant fixture and its own control failed,
# which is how it was caught.
L5="$WORK/leg5-track"; close_fixture "$L5" no no answered no no true
git -C "$L5" checkout -q -b spec/0002-track main 2>/dev/null || git -C "$L5" checkout -q spec/0002-track
assert_true "leg5 track 0: the fixture really stands OFF the trunk, or none of these can fail" \
  "the fixture is on the trunk, where a broken tracker denies for the wrong reason and the cases below prove nothing" \
  test "$(git -C "$L5" rev-parse --abbrev-ref HEAD)" != "main"

for track_cmd in \
  'git checkout main -- && git merge --no-ff spec/0001-thing' \
  'git checkout main >/dev/null && git merge --no-ff spec/0001-thing' \
  'git checkout main 2>/dev/null && git merge --no-ff spec/0001-thing' \
  'git checkout main # back to the trunk && git merge --no-ff spec/0001-thing' \
  'TRUNK=main; git switch $TRUNK && git merge --no-ff spec/0001-thing' \
  'git switch @{-1} && git merge --no-ff spec/0001-thing' \
  ; do
  run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload "$track_cmd")"
  expect_deny "leg5 track: [$track_cmd] cannot move the tracked branch off the trunk unchecked" "CG-"
done

# The control that makes those real: the plain spelling denies too, so the
# fixture and the gate are both working.
run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload 'git checkout main && git merge --no-ff spec/0001-thing')"
expect_deny "leg5 track control: the plain checkout spelling still denies" "CG-"

# And the ALLOW direction, which is the whole risk of this fix: a GENUINE
# pathspec restore switches nothing, and a merge from a real feature branch is
# not a close. If these regress, every ordinary session breaks.
for track_ok in \
  'git checkout main -- src/a.txt && git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing' \
  ; do
  run_hook "$HOOKS/close-gate.sh" "$L5" "$(bash_payload "$track_ok")"
  expect_allow "leg5 track control: [$track_ok] is not a trunk close and is allowed"
done

# --- the LEG 5 axis: comments, abbreviations, and switch operands -----------
#
# Seven replay-confirmed bypasses in the shipped gates, reducing to three
# mechanisms. Each is asserted here in BOTH directions, because five of the
# seven are cases where the gate reached a CONFIDENT WRONG ANSWER rather than
# failing closed, and the fix for that shape is always at risk of failing
# closed on everything instead.
QC_L5_FAIL=""
for payload in \
  'git merge --no-ff spec/0001-thing # will --continue if it conflicts' \
  'git merge --no-ff spec/0001-thing #--continue' \
  'git merge --no-ff spec/0001-thing --mess "--continue"' \
  'git merge --no-ff spec/0001-thing --messa "--continue"' \
  'git merge --no-ff spec/0001-thing --messag "--continue"' \
  'git merge --no-ff spec/0001-thing --into-nam "--abort"' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || QC_L5_FAIL="$QC_L5_FAIL
    $payload"
done
if [[ -z "$QC_L5_FAIL" ]]; then
  ok "corpus leg5: a trailing comment and an abbreviated option value cannot reach the resumption exemption"
else
  bad "corpus leg5: a trailing comment and an abbreviated option value cannot reach the resumption exemption" \
      "these were ALLOWED, so every close check was skipped:$QC_L5_FAIL"
fi

# The ALLOW direction. A REAL resumption must stay exempt or a conflicted close
# has no permitted way to finish, and an ordinary close must survive a comment.
QC_L5_OK=""
for payload in 'git merge --continue' 'git merge --abort'; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || QC_L5_OK="$QC_L5_OK
    $payload"
done
if [[ -z "$QC_L5_OK" ]]; then
  ok "corpus leg5 control: a real --continue and --abort are still exempt"
else
  bad "corpus leg5 control: a real --continue and --abort are still exempt" \
      "the comment and abbreviation fix denied a legitimate resumption:$QC_L5_OK"
fi

# --- the SHELL-GRAMMAR axis (1.0.8, F9) -------------------------------------
# A segment is judged only when its command word sits at the front, and shell has
# a vocabulary for putting something else there first. All four of these executed
# a real merge onto the trunk with every close check skipped:
#
#     { git merge --no-ff spec/0001-thing; }
#     if true; then git merge --no-ff spec/0001-thing; fi
#     for i in 1; do git merge --no-ff spec/0001-thing; done
#     ! git merge --no-ff spec/0001-thing
#
# None is exotic. `!` inverts an exit status and `{ ...; }` groups commands.
#
# Unlike the wrapper allowlist, THIS list is closed: bash reserved words are a
# fixed set defined by the language, not the open-ended family of programs that
# can exec another program. That is worth stating because the wrapper axis
# carries the opposite caveat, and confusing the two would be a false claim of
# completeness.
GRAM_N=0; GRAM_FAIL=""
for payload in \
  '{ git merge --no-ff spec/0001-thing; }' \
  'if true; then git merge --no-ff spec/0001-thing; fi' \
  'for i in 1; do git merge --no-ff spec/0001-thing; done' \
  'while false; do git merge --no-ff spec/0001-thing; done' \
  'until true; do git merge --no-ff spec/0001-thing; done' \
  '! git merge --no-ff spec/0001-thing' \
  'time git merge --no-ff spec/0001-thing' \
  '{ nice -n 5 git merge --no-ff spec/0001-thing; }' \
  'if true; then env -- git merge --no-ff spec/0001-thing; fi' \
  '{ git merge spec/0001-thing -m "close"; }' \
  ; do
  GRAM_N=$((GRAM_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || GRAM_FAIL="$GRAM_FAIL
    $payload"
done
if [[ -z "$GRAM_FAIL" ]]; then
  ok "corpus shell grammar: all $GRAM_N compound spellings are denied"
else
  bad "corpus shell grammar: a reserved word must not move the git verb out of command position" \
      "these reached the trunk unchecked:$GRAM_FAIL"
fi

# THE INVERSE. Stripping reserved words must not start denying ordinary lines
# that merely CONTAIN one, and must not turn a mention into an operation.
GRAM_ALLOW_FAIL=""
for payload in \
  'echo "{ git merge --no-ff spec/0001-thing; }"' \
  'if true; then git status; fi' \
  '{ echo git merge --no-ff spec/0001-thing; }' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "allow" ]] || GRAM_ALLOW_FAIL="$GRAM_ALLOW_FAIL
    $payload"
done
if [[ -z "$GRAM_ALLOW_FAIL" ]]; then
  ok "corpus shell grammar: a reserved word around a NON-merge does not create one"
else
  bad "corpus shell grammar: stripping grammar must not manufacture merges" \
      "these were denied:$GRAM_ALLOW_FAIL"
fi

# --- the REF-IDENTITY axis (1.0.8, F3 and F8) -------------------------------
# The gate used to decide what a merge argument MEANT by stripping three literal
# prefixes and testing the remainder for spec/ or chore/. Every other spelling of
# the same commit read as an ungoverned sync merge: heads/, remotes/origin/,
# another remote's name, a TAG, an alias branch, a raw object name. The prefix
# list could never be finished, because git accepts an open-ended set of names
# for one commit.
#
# It resolves the argument to a COMMIT now and asks git which refs point at it,
# so identity is by object rather than by string and a spelling nobody has
# thought of resolves like one everybody knows.
ri_fixture() { # ri_fixture <dir>  -> local 0001 COMPLIANT, origin/0001 NOT
  local d="$1"
  close_fixture "$d" yes yes answered yes no true
  # The DIVERGENT remote, which is F3 exactly: a compliant local branch and a
  # non-compliant remote-tracking branch of the same name. The gate must judge
  # the one git will actually merge.
  git -C "$d" checkout -q -b ri-remote-tmp main
  mkdir -p "$d/specs"
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
  printf 'unreviewed\n' > "$d/ri-unreviewed.txt"
  git -C "$d" add -A >/dev/null; git -C "$d" commit -qm "remote tip, NOT closed"
  git -C "$d" update-ref refs/remotes/origin/spec/0001-thing "$(git -C "$d" rev-parse ri-remote-tmp)"
  git -C "$d" branch -qD ri-remote-tmp >/dev/null 2>&1
  # A tag and an alias, both pointing at the compliant local tip.
  git -C "$d" tag -f ri-tag spec/0001-thing >/dev/null 2>&1
  git -C "$d" branch -f ri-alias spec/0001-thing >/dev/null 2>&1
  # A real origin/main, so the sync-merge case is exercised against a ref git
  # can resolve. Without one it denies because the ref does not exist, which
  # looks like the gate working and tests nothing. That trap has now appeared
  # three times in this repo in a single day.
  git -C "$d" update-ref refs/remotes/origin/main "$(git -C "$d" rev-parse main)"
  git -C "$d" checkout -q main
}
RI="$WORK/close-refidentity"; ri_fixture "$RI"
ri_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$RI" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}

assert_true "ref-identity0: the fixture's remote tip really differs from the local one" \
  "local and remote point at the same commit, so the divergent case below proves nothing" \
  test "$(git -C "$RI" rev-parse spec/0001-thing)" != "$(git -C "$RI" rev-parse refs/remotes/origin/spec/0001-thing)"

# F3. The local branch is COMPLIANT and the remote one is NOT. Merging the
# remote must be judged against the remote, or a compliant local branch vouches
# for code it does not contain.
if [[ "$(ri_verdict 'git merge --no-ff origin/spec/0001-thing')" == "deny" ]]; then
  ok "ref-identity a: a remote-tracking ref is judged on ITS tree, not the local branch of that name"
else
  bad "ref-identity a: the thing validated must be the thing merged" \
      "a compliant local spec/0001-thing green-lit a non-compliant origin/spec/0001-thing"
fi

# F8 and the alias/tag family. Every one of these names the same UNCLOSED commit
# as the remote tip or an unclosed branch, and each was allowed by name matching.
RI_FAIL=""
for c in 'git merge --no-ff refs/remotes/origin/spec/0001-thing' \
         'git merge --no-ff remotes/origin/spec/0001-thing' ; do
  [[ "$(ri_verdict "$c")" == "deny" ]] || RI_FAIL="$RI_FAIL
    $c"
done
if [[ -z "$RI_FAIL" ]]; then
  ok "ref-identity b: every spelling of the non-compliant remote tip is governed"
else
  bad "ref-identity b: a spelling of the merge target must not change whether it is governed" \
      "these reached the trunk unchecked:$RI_FAIL"
fi

# THE INVERSE, and it is what stops "deny everything" from passing this axis. A
# sync merge from the trunk's own remote is not a close and has never been
# governed; 1.0.3 denied it and broke ordinary work while `git pull` did the
# same thing ungated.
if [[ "$(ri_verdict 'git merge origin/main')" == "allow" ]]; then
  ok "ref-identity c: a sync merge from the trunk's own remote is still allowed"
else
  bad "ref-identity c: git merge origin/main must not be denied" \
      "resolving refs by commit must not turn ordinary syncs into denials, which is the 1.0.3 regression"
fi

# The INDIRECT forms stay denied, and for a reason that is about TIME rather
# than spelling: this hook runs before the command, so `@{-1}` here is not
# necessarily `@{-1}` when the merge runs. Resolving them would let the gate
# validate one branch while git merges another, which is F3 from the other end.
RI_IND_FAIL=""
for c in 'git merge @{-1}' 'git merge FETCH_HEAD' ; do
  [[ "$(ri_verdict "$c")" == "deny" ]] || RI_IND_FAIL="$RI_IND_FAIL
    $c"
done
if [[ -z "$RI_IND_FAIL" ]]; then
  ok "ref-identity d: time-varying indirect forms are still refused rather than resolved"
else
  bad "ref-identity d: an indirect form must not be resolved at hook time" \
      "these were resolved, and their meaning can change before the merge runs:$RI_IND_FAIL"
fi

# --- the SPEC-NUMBER-REUSE axis (1.0.7, B4) ---------------------------------
# Every close-gate check reads the spec file as it stands on the branch, which
# is right, and says nothing about WHO WROTE IT. A branch cut from the trunk
# after spec NNNN closed inherits that spec, Closing report and all, so reusing
# a CLOSED number as a branch name carries unreviewed work onto the trunk
# against somebody else's evidence, and the trunk audit then calls it compliant
# because it reads the same inherited artifacts.
#
# Reproduced by hand 2026-07-27. It was the one BLOCKER on the standing list
# that had never been replayed, and three of eleven claims in an earlier intake
# did not survive verification, so it got a repro before it got a fix.
reuse_fixture() { # reuse_fixture <dir> <where-the-spec-is-written: branch|trunk|inherited>
  local d="$1" mode="$2"
  rm -rf "$d"; mkdir -p "$d/specs" "$d/.claude" "$d/src"
  git_init "$d"
  sdd_json "$d" true main true
  printf 'x\n' > "$d/src/a.txt"
  git -C "$d" add -A && git -C "$d" commit -qm init
  git -C "$d" branch -M main

  # A legitimate spec 0001, closed and merged the honest way.
  git -C "$d" checkout -q -b spec/0001-thing
  { printf '# Spec 0001 - thing\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    printf -- '- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
  } > "$d/specs/0001-thing.md"
  { printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n'
    printf '| 0001 | Thing | CLOSED | shipped |\n'
  } > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0001 closed"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff spec/0001-thing -m "close 0001"

  case "$mode" in
    inherited)
      # THE DEFECT: a new branch reusing number 0001, contributing code but no
      # spec of its own. It inherits 0001-thing.md from the trunk.
      git -C "$d" checkout -q -b spec/0001-sneaky
      printf 'unreviewed\n' >> "$d/src/a.txt"
      git -C "$d" add -A && git -C "$d" commit -qm "unspecified work on a reused number"
      ;;
    trunk)
      # THE COMMON LEGITIMATE PATH, and the one a careless repair breaks: the
      # spec file is created on the trunk during planning, and the BRANCH adds
      # the Closing report to it. The blob exists at the merge base and differs
      # at the tip, which is exactly what authorship looks like.
      { printf '# Spec 0002 - planned\n\nStatus: ACTIVE\n'; } > "$d/specs/0002-planned.md"
      git -C "$d" add -A && git -C "$d" commit -qm "spec 0002 planned on the trunk"
      git -C "$d" checkout -q -b spec/0002-planned
      { printf '# Spec 0002 - planned\n\nStatus: CLOSED\n\n## Closing report\n\n'
        printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
        printf -- '- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n'
      } > "$d/specs/0002-planned.md"
      { printf '# Spec inventory\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n'
        printf '| 0001 | Thing | CLOSED | shipped |\n| 0002 | Planned | CLOSED | shipped |\n'
      } > "$d/specs/STATUS.md"
      git -C "$d" add -A && git -C "$d" commit -qm "close 0002"
      ;;
  esac
  git -C "$d" checkout -q main
}

CR="$WORK/close-reuse"; reuse_fixture "$CR" inherited
assert_true "close-gate reuse0: the fixture really did close 0001 onto the trunk first" \
  "0001-thing.md is not on the trunk, so the reused branch inherits nothing and this case proves nothing" \
  git -C "$CR" cat-file -e "main:specs/0001-thing.md"
assert_true "close-gate reuse0b: the reused branch really contributes no spec change" \
  "the branch modifies its spec, so it is not the inherited-artifact case at all" \
  test -z "$(git -C "$CR" diff --name-only main spec/0001-sneaky -- specs/)"
run_hook "$HOOKS/close-gate.sh" "$CR" "$(bash_payload 'git merge --no-ff spec/0001-sneaky')"
# Matches the stable CODE, not the prose. It asserted "does not modify" until
# 2026-08-01, which is a phrase from the deny MESSAGE, and item 8's promoted
# rider rewords exactly that message to name the chore route for evidence
# completion. The codes exist so prose can move without breaking a test; a test
# that matches prose quietly cancels that guarantee, and the whole point of the
# rewording being "cheap and safe" was that no test was doing this.
expect_deny "close-gate reuse a: a branch reusing a CLOSED spec number is denied" "CG-SPEC-NOT-AUTHORED"

CR2="$WORK/close-reuse-ok"; reuse_fixture "$CR2" trunk
run_hook "$HOOKS/close-gate.sh" "$CR2" "$(bash_payload 'git merge --no-ff spec/0002-planned')"
expect_allow "close-gate reuse b: a spec planned on the trunk and CLOSED on the branch still passes"

# --- the WRAPPER axis (1.0.6) -----------------------------------------------
# The command-position test that fixed `echo git merge ...` introduced its own
# false negative: a segment is only judged if it STARTS with git, and wrappers
# are how a shell legitimately starts git. The 504-spelling corpus had no
# wrapper dimension, which is why this shipped. The dimension list is itself an
# artifact written from what somebody thought of, and nothing reviews it.
CORPUS_WRAP_N=0
CORPUS_WRAP_FAIL=""
for wrap in 'command ' 'exec ' 'nice ' 'nohup ' 'env ' 'env GIT_PAGER=cat ' 'GIT_PAGER=cat ' 'time '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_WRAP_N=$((CORPUS_WRAP_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_WRAP_FAIL="$CORPUS_WRAP_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_WRAP_FAIL" ]]; then
  ok "corpus wrappers: all $CORPUS_WRAP_N wrapper-prefixed spec merges are denied"
else
  bad "corpus wrappers: a wrapper prefix must not escape the gate ($CORPUS_WRAP_N generated)" \
      "these reached the trunk unchecked:$CORPUS_WRAP_FAIL"
fi

# --- the FLAG-VALUED WRAPPER axis (1.0.7) -----------------------------------
# >>> SHARD-BEGIN wrapper-flag-valued cost=5
if shard_region wrapper-flag-valued; then
# The 1.0.6 wrapper axis above covers wrappers that take no argument, and the
# flag stripper it shipped with consumed dash flags one word at a time. A flag
# that takes a SEPARATE value strands that value at the head of the segment:
# `nice -n 5 git merge ...` strips `nice`, strips `-n`, and leaves `5 git merge
# ...`, which fails the command-position test and is never judged at all.
# `stdbuf -o0` survives only because its value is glued to the flag, which is
# the accident that hid this. Found by an external review of the SHIPPED 1.0.6,
# the second consecutive release whose bypass lived in a dimension the corpus
# did not have.
CORPUS_FLAGWRAP_N=0
CORPUS_FLAGWRAP_FAIL=""
# `timeout` is deliberately NOT here: it is not in either hook's wrapper
# allowlist, which the hooks say plainly is not a claim of completeness, and it
# is asserted below as a documented pass PAIRED with the trunk audit that
# catches it. Demanding a deny here would have quietly expanded the allowlist
# as a side effect of writing a regression test, which is a decision, not a fix.
for wrap in 'nice -n 5 ' 'LANG=C nice -n 5 ' 'env -u FOO ' 'env -i ' 'nice -n 5 nohup ' \
            'stdbuf -o0 ' 'stdbuf -o 0 ' 'time nice -n 5 '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_FLAGWRAP_N=$((CORPUS_FLAGWRAP_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_FLAGWRAP_FAIL="$CORPUS_FLAGWRAP_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_FLAGWRAP_FAIL" ]]; then
  ok "corpus flag-valued wrappers: all $CORPUS_FLAGWRAP_N spellings are denied"
else
  bad "corpus flag-valued wrappers: a wrapper flag with a separate value must not escape the gate ($CORPUS_FLAGWRAP_N generated)" \
      "these reached the trunk unchecked:$CORPUS_FLAGWRAP_FAIL"
fi

# The false-positive direction, which matters as much (law 3): stripping a flag
# and its value must not start eating the command itself.
CORPUS_FLAGWRAP_ALLOW_FAIL=""
for cmd in 'nice -n 5 git status' \
           'env -u GIT_DIR git log --oneline' \
           'nice -n 5 git merge origin/main' \
           'LANG=C git merge origin/main' \
           'env -i git fetch origin'; do
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_FLAGWRAP_ALLOW_FAIL="$CORPUS_FLAGWRAP_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_FLAGWRAP_ALLOW_FAIL" ]]; then
  ok "corpus flag-valued wrappers: ordinary wrapped commands still pass"
else
  bad "corpus flag-valued wrappers: ordinary wrapped commands must still pass" \
      "these were denied:$CORPUS_FLAGWRAP_ALLOW_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END wrapper-flag-valued
# --- the DASH-VALUED FLAG and OPTION TERMINATOR axes (1.0.7) ----------------
# >>> SHARD-BEGIN dash-valued-flags cost=10
if shard_region dash-valued-flags; then
# The axis above generates flag values two ways, non-dash (`nice -n 5`) and
# glued (`stdbuf -o0`), and both are values that LOOK like values. Neither
# spelling below appears anywhere in it:
#
#   nice -n -5 git merge ...     a flag value that begins with a dash
#   env -- git merge ...         the bare option terminator
#
# Both were DENIED by the shipped v1.0.6 and ALLOWED by 1.0.7 until this axis
# existed: the flag stripper consumed `-n`, stranded `-5`, and the command-position
# test then found no git to judge. The terminator matched none of its branches
# at all and sat at the head of the segment doing the same thing.
#
# This is the fourth consecutive release whose bypass lived in a corpus
# dimension nobody had written down, and the first where the differential
# strictness gate ALSO missed it, reporting "no undeclared relaxation" while two
# of its own regressions were live underneath. A generated corpus only varies
# what somebody listed; the list is the artifact that needs reviewing, and it is
# the reason this block exists rather than two more literal cases.
CORPUS_DASHVAL_N=0
CORPUS_DASHVAL_FAIL=""
# The NON-ALPHABETIC dash flag was added after an adversarial review found it: the axis
# above was written with alphabetic flags only (`nice -n -5`), so `nice -5`,
# where the FLAG itself is not a letter, matched none of the stripper branches
# and stayed stranded at the head of the segment. v1.0.6 denied it. The author of
# the axis directly above missed it while writing a commit message about exactly
# this failure mode, which is the most direct evidence available that a
# dimension list written from imagination is not a dimension list.
for wrap in 'nice -n -5 ' 'nice -n -5 nohup ' 'LANG=C nice -n -5 ' \
            'nice -5 ' 'nice -5 nohup ' 'LANG=C nice -5 ' 'nice --5 ' \
            'env -- ' 'command -- ' 'env -i -- ' 'env -u FOO -- ' \
            'nice -n -5 env -- ' 'time nice -n -5 ' 'time nice -5 '; do
  for tail in 'git merge --no-ff spec/0001-thing' 'git merge spec/0001-thing -m "close"'; do
    CORPUS_DASHVAL_N=$((CORPUS_DASHVAL_N + 1))
    [[ "$(corpus_verdict "${wrap}${tail}")" == "deny" ]] || CORPUS_DASHVAL_FAIL="$CORPUS_DASHVAL_FAIL
    ${wrap}${tail}"
  done
done
if [[ -z "$CORPUS_DASHVAL_FAIL" ]]; then
  ok "corpus dash-valued flags and option terminators: all $CORPUS_DASHVAL_N spellings are denied"
else
  bad "corpus dash-valued flags and option terminators: these must not escape the gate ($CORPUS_DASHVAL_N generated)" \
      "these reached the trunk unchecked:$CORPUS_DASHVAL_FAIL"
fi

# The false-positive direction. Stripping a dash-leading value must never eat
# the command word itself, and `env -i git ...` is the case that makes this
# delicate: git sits exactly where a value would.
CORPUS_DASHVAL_ALLOW_FAIL=""
for cmd in 'nice -n -5 git status' \
           'nice -5 git status' \
           'nice -5 git merge origin/main' \
           'env -- git status' \
           'env -i -- git log --oneline' \
           'nice -n -5 git merge origin/main' \
           'env -- git merge origin/main' \
           'command -- git fetch origin'; do
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_DASHVAL_ALLOW_FAIL="$CORPUS_DASHVAL_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_DASHVAL_ALLOW_FAIL" ]]; then
  ok "corpus dash-valued flags: ordinary commands behind them still pass"
else
  bad "corpus dash-valued flags: ordinary commands behind them must still pass" \
      "these were denied:$CORPUS_DASHVAL_ALLOW_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END dash-valued-flags
# --- the NEWLINE-SEPARATOR axis (1.0.7) -------------------------------------
# `tr -s '[:space:]' ' '` squeezes newlines into spaces before the segment
# splitter runs, so a multi-line command collapses into ONE segment and only its
# first command sits at command position. Everything after the first newline was
# never judged by either gate. Found independently by two generators in the same
# scoped run, which is what a dominant hole looks like.
#
# Pre-existing in v1.0.6, so it is a hole rather than a regression, and it is the
# widest one on the list.
# Built as explicit strings so the newline is unambiguous in the source.
NL_PAYLOADS=(
  "$(printf 'echo hi\ngit merge --no-ff spec/0001-thing')"
  "$(printf 'set -e\ngit status --short\ngit merge --no-ff spec/0001-thing')"
  "$(printf '# stage is ready\ngit merge spec/0001-thing -m "close"')"
  "$(printf 'git status\n\ngit merge --no-ff spec/0001-thing')"
)
CORPUS_NL_N=0
CORPUS_NL_FAIL=""
for payload in "${NL_PAYLOADS[@]}"; do
  CORPUS_NL_N=$((CORPUS_NL_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || CORPUS_NL_FAIL="$CORPUS_NL_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$CORPUS_NL_FAIL" ]]; then
  ok "corpus newline separator: all $CORPUS_NL_N multi-line spellings are denied"
else
  bad "corpus newline separator: a git operation after a newline must not escape the gate ($CORPUS_NL_N generated)" \
      "these reached the trunk unchecked (~ marks the newline):$CORPUS_NL_FAIL"
fi

# THE INVERSE, and it is the case that decides whether treating a newline as a
# separator is safe at all: a newline INSIDE a quoted message must not split the
# merge away from its branch argument. If it did, the fix for the case above
# would hand back a bypass in exchange, which is the trade this repo has
# accidentally made twice.
NL_QUOTED_FAIL=""
for payload in "$(printf 'git merge --no-ff -m "closes the spec\nnice work" spec/0001-thing')" \
               "$(printf 'git merge --no-ff spec/0001-thing -m "line one\nline two"')"; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || NL_QUOTED_FAIL="$NL_QUOTED_FAIL
    $(printf '%s' "$payload" | tr '\n' '~')"
done
if [[ -z "$NL_QUOTED_FAIL" ]]; then
  ok "corpus newline separator: a newline inside a merge message does not split the merge from its branch"
else
  bad "corpus newline separator: a quoted newline must not turn a deny into a bypass" \
      "these escaped (~ marks the newline):$NL_QUOTED_FAIL"
fi



# --- the AMPERSAND-SEPARATOR axis (1.0.7) -----------------------------------
# The splitter handled &&, ||, ;, | and (since the axis above) newlines. A SINGLE
# & backgrounds the preceding command and starts a new one, exactly as ; does,
# and it was not a separator at all, so:
#
#     echo hi & git merge --no-ff spec/0001-thing
#
# collapsed into ONE segment whose command word was `echo`, and the merge was
# never judged. Pre-existing in v1.0.6, found by the adversarial review as F8.
AMP_N=0; AMP_FAIL=""
for payload in \
  'echo hi & git merge --no-ff spec/0001-thing' \
  'sleep 1 & git merge --no-ff spec/0001-thing' \
  'echo hi & git merge spec/0001-thing -m "close"' \
  'git status & git merge --no-ff spec/0001-thing' \
  'echo a & echo b & git merge --no-ff spec/0001-thing' \
  'git merge --no-ff spec/0001-thing & echo done' \
  ; do
  AMP_N=$((AMP_N + 1))
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_FAIL="$AMP_FAIL
    $payload"
done
if [[ -z "$AMP_FAIL" ]]; then
  ok "corpus ampersand separator: all $AMP_N backgrounded spellings are denied"
else
  bad "corpus ampersand separator: a merge after a single & must not escape the gate" \
      "these reached the trunk unchecked:$AMP_FAIL"
fi

# THE INVERSE, which the intake called out by name: && must not be split into
# two & separators. POSIX ERE alternation is leftmost-longest so it is not, but
# "the awk on the reviewer's machine" is the assumption the macOS leg exists to
# doubt, and an && that silently became two separators would put an empty
# segment between every pair of commands on every line this gate ever sees.
AMP_PAIR="$(printf 'a && b & c\n' | awk '{ gsub(/&&|\|\||[;|()&]/, "\n"); print }' | grep -c .)"
if [[ "$AMP_PAIR" -eq 3 ]]; then
  ok "corpus ampersand separator: && is one separator, not two (a && b & c splits into 3, not 4)"
else
  bad "corpus ampersand separator: && must not split into two & separators" \
      "'a && b & c' produced $AMP_PAIR non-empty segments, expected 3. This awk is not leftmost-longest."
fi

# And the ordinary && line must still behave, which is the assertion that would
# catch the above turning into a bypass rather than merely into noise.
AMP_AND_FAIL=""
for payload in \
  'git status && git merge --no-ff spec/0001-thing' \
  'echo hi && git merge --no-ff spec/0001-thing' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_AND_FAIL="$AMP_AND_FAIL
    $payload"
done
if [[ -z "$AMP_AND_FAIL" ]]; then
  ok "corpus ampersand separator: && lines are unaffected by the & repair"
else
  bad "corpus ampersand separator: adding & as a separator must not break &&" \
      "these stopped being denied:$AMP_AND_FAIL"
fi

# A redirection contains an ampersand that is NOT a separator. Splitting `2>&1`
# yields the fragments `2>` and `1`, neither of which is a command, so the git
# operation on the line must still be found and judged. This is the false-DENY
# and false-ALLOW pair for the same character.
AMP_REDIR_FAIL=""
for payload in \
  'git merge --no-ff spec/0001-thing 2>&1' \
  'git merge --no-ff spec/0001-thing >/dev/null 2>&1' \
  ; do
  [[ "$(corpus_verdict "$payload")" == "deny" ]] || AMP_REDIR_FAIL="$AMP_REDIR_FAIL
    $payload"
done
if [[ -z "$AMP_REDIR_FAIL" ]]; then
  ok "corpus ampersand separator: an ampersand inside a redirection does not hide the merge"
else
  bad "corpus ampersand separator: 2>&1 must not split a merge away from command position" \
      "these stopped being denied:$AMP_REDIR_FAIL"
fi

# --- the CHECKOUT-TARGET axis (1.0.6) ---------------------------------------
# `git checkout -` is organic shorthand, not attacker spelling: it is exactly
# the state an agent is in after `git checkout spec/NNNN` from the trunk. The
# branch tracker took the first NON-DASH argument, so `-` was skipped, the
# running branch stayed on the spec branch, and the merge segment was judged
# as targeting a feature branch, which is an explicitly ALLOWED case. Not a
# fall-through: the gate reached a confident wrong answer.
CORP_DASH="$WORK/corpus-dash"
close_fixture "$CORP_DASH" no no answered no no true
git -C "$CORP_DASH" checkout -q spec/0001-thing   # @{-1} is now the trunk, the organic state
dash_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_DASH" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus dash0: the fixture really has the trunk as its previous branch" \
  "@{-1} does not resolve to the trunk, so the cases below prove nothing" \
  test "$(git -C "$CORP_DASH" rev-parse --abbrev-ref '@{-1}' 2>/dev/null)" = "main"
CORP_DASH_FAIL=""
for c in 'git checkout - && git merge --no-ff spec/0001-thing' \
         'git switch - && git merge --no-ff spec/0001-thing' \
         'git checkout @{-1} && git merge --no-ff spec/0001-thing'; do
  [[ "$(dash_verdict "$c")" == "deny" ]] || CORP_DASH_FAIL="$CORP_DASH_FAIL
    $c"
done
if [[ -z "$CORP_DASH_FAIL" ]]; then
  ok "corpus dash: returning to the trunk by shorthand does not escape the gate"
else
  bad "corpus dash: 'checkout -' back to the trunk must not escape the gate" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_DASH_FAIL"
fi

# --- the PATHSPEC-CHECKOUT axis (1.0.7) -------------------------------------
# >>> SHARD-BEGIN pathspec-checkout cost=6
if shard_region pathspec-checkout; then
# `git checkout -- .` and `git checkout .` do not switch branches at all: they
# discard working-tree changes, which is something agents do constantly right
# before merging. The tracker read the argument as a branch name, concluded the
# merge would run on a branch called ".", and skipped it as non-trunk. That is
# the `checkout -` defect class one door down: an argument that is not a branch
# name recorded as one, producing a CONFIDENT WRONG ANSWER rather than a
# fall-through. `git restore .` was always safe because restore never touches
# the tracker. Found by an external review of the shipped 1.0.6; the file-path
# spellings below were found while reproducing it, and widen the class beyond
# the dot the report named.
CORP_PATH="$WORK/corpus-pathspec"
close_fixture "$CORP_PATH" no no answered no no true
path_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_PATH" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus pathspec0: the fixture is standing on the trunk" \
  "the fixture is not on main, so a merge segment would be skipped for the RIGHT reason and these cases would prove nothing" \
  test "$(git -C "$CORP_PATH" branch --show-current)" = "main"
CORP_PATH_FAIL=""
for c in 'git checkout -- . && git merge --no-ff spec/0001-thing' \
         'git checkout . && git merge --no-ff spec/0001-thing' \
         'git checkout src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -f -- . && git merge --no-ff spec/0001-thing' \
         'git checkout ./src && git merge --no-ff spec/0001-thing'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_PATH_FAIL="$CORP_PATH_FAIL
    $c"
done
if [[ -z "$CORP_PATH_FAIL" ]]; then
  ok "corpus pathspec: discarding working-tree changes does not move the tracked branch"
else
  bad "corpus pathspec: a pathspec checkout must not be read as a branch switch" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_PATH_FAIL"
fi

# The TREE-ISH pathspec form (1.0.7, B3). The cases above all have nothing
# before the `--`, so no branch candidate was found and the tracker fell
# through. Put a real branch in front of the separator and a candidate IS found:
#
#     git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing
#
# switches nothing, but the tracker recorded a switch to spec/0002-other, judged
# the merge as ordinary feature work, and skipped it. The branch has to EXIST for
# this to reproduce, which is why the fixture below needs a second spec branch:
# the first cut of the replay fixture had only one, so any payload naming a
# second denied for the wrong reason and passed while testing nothing.
assert_true "corpus pathspec-treeish0: the fixture has a second spec branch to name" \
  "without a second EXISTING branch these payloads deny for the wrong reason and assert nothing" \
  git -C "$CORP_PATH" rev-parse --verify --quiet spec/0002-other
CORP_TI_FAIL=""
for c in 'git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'git checkout spec/0002-other -- . && git merge --no-ff spec/0001-thing' \
         'git checkout main -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout HEAD -- src/app.js && git merge --no-ff spec/0001-thing' \
         'git checkout -f spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'git checkout spec/0002-other -- src/a.txt src/b.txt && git merge spec/0001-thing -m close'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_TI_FAIL="$CORP_TI_FAIL
    $c"
done
if [[ -z "$CORP_TI_FAIL" ]]; then
  ok "corpus pathspec: a tree-ish before a -- pathspec does not move the tracked branch"
else
  bad "corpus pathspec: git checkout <tree-ish> -- <path> restores files and switches nothing" \
      "these merged an unclosed spec into the trunk with no checks:$CORP_TI_FAIL"
fi

# The interaction the intake named. A bare `--` at the HEAD of a segment is an
# option terminator that strip_wrappers removes; a `--` after the checkout verb
# is a pathspec separator that this tracker reads. The two positions must not be
# confused, so both are exercised on the same line.
CORP_TI_MIX_FAIL=""
for c in 'env -- git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing' \
         'env -- git merge --no-ff spec/0001-thing' \
         'nice -n 5 git checkout spec/0002-other -- . && git merge --no-ff spec/0001-thing'; do
  [[ "$(path_verdict "$c")" == "deny" ]] || CORP_TI_MIX_FAIL="$CORP_TI_MIX_FAIL
    $c"
done
if [[ -z "$CORP_TI_MIX_FAIL" ]]; then
  ok "corpus pathspec: the head -- option terminator and the pathspec -- do not confuse each other"
else
  bad "corpus pathspec: a wrapper's -- and a pathspec's -- occupy different positions and must stay distinct" \
      "these escaped:$CORP_TI_MIX_FAIL"
fi

# The false-positive direction for the tree-ish form specifically: a REAL switch
# to that same branch, with no separator, must still be tracked as a switch. If
# the repair above had keyed on the branch name instead of the separator, this
# is the assertion that would have caught it.
if [[ "$(path_verdict 'git checkout spec/0002-other && git merge --no-ff main')" == "allow" ]]; then
  ok "corpus pathspec: the same branch without a -- separator is still a real switch"
else
  bad "corpus pathspec: git checkout <branch> with no separator must still track the switch" \
      "the repair keyed on something other than the separator and broke ordinary branch switching"
fi

# An argument that is NEITHER a branch nor an existing path cannot be
# classified, and an unclassifiable branch must fail closed rather than read as
# "some other branch". This is the sentinel the 1.0.6 fix introduced, reused.
if [[ "$(path_verdict 'git checkout no-such-thing-at-all && git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "corpus pathspec: an unresolvable checkout target fails closed on the sentinel"
else
  bad "corpus pathspec: an unresolvable checkout target must fail closed" \
      "the gate decided it was on some other branch and skipped the merge"
fi

# The false-positive direction: a real branch switch must still be tracked, and
# ordinary discarding on a feature branch must stay silent.
CORP_PATH_ALLOW_FAIL=""
for c in 'git checkout spec/0001-thing && git merge --no-ff main' \
         'git checkout -- .' \
         'git checkout . && git status'; do
  [[ "$(path_verdict "$c")" == "allow" ]] || CORP_PATH_ALLOW_FAIL="$CORP_PATH_ALLOW_FAIL
    $c"
done
if [[ -z "$CORP_PATH_ALLOW_FAIL" ]]; then
  ok "corpus pathspec: real branch switches and plain discards still pass"
else
  bad "corpus pathspec: real branch switches and plain discards must still pass" \
      "these were denied:$CORP_PATH_ALLOW_FAIL"
fi

fi; shard_region_end
# <<< SHARD-END pathspec-checkout
# --- the RAW-OBJECT-NAME axis (1.0.7) ---------------------------------------
# A raw commit name is an indirect form: it identifies the commit without
# naming the branch, so the close conditions (which live in a branch's spec
# file) cannot be checked. The gate knew that and skipped SHAs by SHAPE,
# matching `[0-9a-f]{7,40}`. Every spelling outside that shape sailed through
# instead: a 6-character abbreviation, the same oid uppercased, and in a
# sha256 repository the 64-character oid. Shape was the wrong question. The
# right one is whether git considers the word a REF, which is shape-free.
CORP_OID="$WORK/corpus-oid"
close_fixture "$CORP_OID" no no answered no no true
OID="$(git -C "$CORP_OID" rev-parse spec/0001-thing)"
oid_verdict() {
  local out
  out="$(printf '%s' "$(bash_payload "$1")" | CLAUDE_PROJECT_DIR="$CORP_OID" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "corpus oid0: the fixture resolves a real object name for the unclosed branch" \
  "no oid, so every case below would be testing a word that resolves to nothing" \
  test -n "$OID"
CORP_OID_FAIL=""
for spelling in "${OID:0:4}" "${OID:0:6}" "${OID:0:7}" "${OID:0:12}" "$OID" \
                "$(printf '%s' "$OID" | tr 'a-f' 'A-F')" \
                "$(printf '%s' "${OID:0:10}" | tr 'a-f' 'A-F')"; do
  [[ "$(oid_verdict "git merge --no-ff $spelling")" == "deny" ]] || CORP_OID_FAIL="$CORP_OID_FAIL
    git merge --no-ff $spelling"
done
if [[ -z "$CORP_OID_FAIL" ]]; then
  ok "corpus raw object names: every spelling of a bare commit name is refused, not just the 7-to-40 lowercase shape"
else
  bad "corpus raw object names: a bare commit name must be refused whatever its shape" \
      "these merged an unclosed spec into the trunk with the close conditions unevaluated:$CORP_OID_FAIL"
fi
# The false-positive direction: a real branch name that happens to look hexish
# must still be treated as a branch, and ordinary syncs must still pass. The
# remote ref has to EXIST for the sync case to mean anything: without it the
# deny is the gate correctly refusing an unresolvable ref, which is a different
# fact than the one under test.
git -C "$CORP_OID" branch -f decade main
git -C "$CORP_OID" update-ref refs/remotes/origin/main "$(git -C "$CORP_OID" rev-parse main)"
CORP_OID_ALLOW_FAIL=""
for c in 'git merge origin/main' 'git merge decade'; do
  [[ "$(oid_verdict "$c")" == "allow" ]] || CORP_OID_ALLOW_FAIL="$CORP_OID_ALLOW_FAIL
    $c"
done
if [[ -z "$CORP_OID_ALLOW_FAIL" ]]; then
  ok "corpus raw object names: a branch whose name is hex-shaped is still a branch"
else
  bad "corpus raw object names: a hex-shaped BRANCH name must not be mistaken for an object name" \
      "these were denied:$CORP_OID_ALLOW_FAIL"
fi

# --- the MUST-ALLOW corpus ---------------------------------------------------
CORPUS_ALLOW_N=0
CORPUS_ALLOW_FAIL=""
for cmd in \
  'git merge origin/main' \
  'git merge --no-ff release/2.0' \
  'git merge main' \
  'git pull origin main' \
  'git status' \
  'git log --oneline' \
  'git merge --continue' \
  'git merge --abort' \
  'echo git merge spec/0001-thing' ; do
  CORPUS_ALLOW_N=$((CORPUS_ALLOW_N + 1))
  [[ "$(corpus_verdict "$cmd")" == "allow" ]] || CORPUS_ALLOW_FAIL="$CORPUS_ALLOW_FAIL
    $cmd"
done
if [[ -z "$CORPUS_ALLOW_FAIL" ]]; then
  ok "corpus allow: all $CORPUS_ALLOW_N ordinary operations still pass"
else
  bad "corpus allow: ordinary operations must not be denied" \
      "a gate that denies these is one people disable:$CORPUS_ALLOW_FAIL"
fi

# --- interpreter forms: documented passes, PAIRED with the audit catch -------
# The pathspec hole is asserted as a pass so its closure is detected. These go
# one better, because a deliberate hole should be pinned together with the
# thing that actually catches it: each interpreter form passes the gate AND its
# outcome is caught by the trunk audit. That pairing is the two-layer claim the
# README now makes, asserted rather than asserted-about.
INTERP="$WORK/interpreter"
close_fixture "$INTERP" no no answered no no true
for form in 'sh -c "git merge --no-ff spec/0001-thing"' 'bash -c "git merge --no-ff spec/0001-thing"' \
            'timeout -s KILL 10 git merge --no-ff spec/0001-thing' 'sudo git merge --no-ff spec/0001-thing'; do
  run_hook "$HOOKS/close-gate.sh" "$INTERP" "$(bash_payload "$form")"
  expect_allow "interpreter: [$form] passes the gate, as Known limitations states"
done
# The branch must carry ROLE-PATH changes for the audit to have an opinion: a
# docs-only merge is legitimately ignored, and the first cut of this case
# merged a spec-file-only branch and then reported the audit broken. The
# fixture has to look like the thing being claimed.
git -C "$INTERP" checkout -q spec/0001-thing
mkdir -p "$INTERP/src"; printf 'feature\n' > "$INTERP/src/f.js"
git -C "$INTERP" add -A && git -C "$INTERP" commit -qm "feature code, spec still unclosed"
git -C "$INTERP" checkout -q main
git -C "$INTERP" merge -q --no-ff -m "merge as an interpreter form would leave it" spec/0001-thing
run_script bash "$SCRIPTS/trunk-audit.sh" "$INTERP"
expect_script "interpreter: the trunk audit CATCHES the outcome the gate let past" 1 "VIOLATION"

#
# Each of these is a deliberate pass named in the README. They are asserted
# rather than ignored so that the day one of them closes, this file says so
# instead of nobody noticing.
for hole_cmd in \
  'git cherry-pick spec/0001-thing' \
  'git rebase spec/0001-thing' \
  'git reset --hard spec/0001-thing' \
  'git checkout spec/0001-thing -- src/app.js' ; do
  if [[ "$(corpus_verdict "$hole_cmd")" == "allow" ]]; then
    ok "documented hole: [$hole_cmd] still passes, as Known limitations states"
  else
    bad "documented hole: [$hole_cmd] still passes" \
        "this now DENIES. That is an improvement, but the README still lists it as a hole: update Known limitations and this assertion together"
  fi
done

# CLOSED 1.0.8, and it used to sit in the list above. Merging a spec branch under
# a SECOND NAME (`git branch tmp spec/0001-x && git merge tmp`) was a documented
# hole for as long as the gate decided what a ref meant by editing its name: an
# alias is a different string, so it read as an ungoverned sync merge.
#
# Identity by COMMIT closes it without anyone aiming at it. The alias points at
# the same object as the spec branch, `git for-each-ref --points-at` finds the
# spec ref, and the close conditions are evaluated. That is the difference
# between fixing a spelling and fixing a class: nobody wrote a rule about
# aliases, and aliases stopped working anyway.
#
# It is asserted in the DENY direction now, so a regression that reopens it
# fails here rather than quietly restoring a documented hole.
if [[ "$(corpus_verdict 'git merge --no-ff tmp-alias')" == "deny" ]]; then
  ok "closed hole: a spec branch merged under a second name is now caught by commit identity"
else
  bad "closed hole: a spec branch merged under a second name must stay caught" \
      "an alias of an unclosed spec branch reached the trunk again; ref identity has regressed to name matching"
fi

# A compound carrying TWO commits. HAS_COMMIT was a plain assignment, so the
# last commit segment overwrote the first and the auto-staging check inspected
# the harmless one. `git commit -am x && git commit -m y` therefore passed,
# although the -am segment is exactly the stage-and-commit-in-one-step shape
# CM-AUTOSTAGE-FLAG exists to catch. A command can carry more than one commit
# and the gate answers for all of them.
CMTWO="$WORK/commit-two"; close_fixture "$CMTWO" no no answered no no true
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -am x && git commit -m y')"
expect_deny "commit-gate two-commits: a later plain commit does not disarm the flag check on an earlier one" "CM-AUTOSTAGE-FLAG"
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -m y && git commit -am x')"
expect_deny "commit-gate two-commits: the offending commit is caught in either position" "CM-AUTOSTAGE-FLAG"
# The allow direction: two ordinary commits are not made suspicious by being two.
run_hook "$HOOKS/commit-gate.sh" "$CMTWO" "$(bash_payload 'git commit -m x && git commit -m y')"
expect_allow "commit-gate two-commits: two plain commits in one line are still allowed"

# =============================================================================
# UNLEXABLE INPUT, and a malformed trunk VALUE. Both 2026-07-28, both from the
# 1.0.8 leg, both the same shape: a check that validated the FORM of its input
# and never the substance.
#
# The awk normaliser in both gates appends `@@UNTERMINATED@@` when a quote never
# closes, under a comment saying a gate that cannot lex its input has not
# evaluated its predicate. No line read the marker, so the unlexable case fell
# through to the applicability test, matched nothing (everything after the
# opening quote had been swallowed into the span) and the gate exited 0 as "not
# a merge". An apostrophe in a shell comment or a heredoc body reaches it.
#
# The commit gate normalises TWICE, and the first cut of this guard read the
# whitespace pass rather than the opaque-token pass, so it never fired at all
# while the close gate's identical guard worked. That is asserted here too.
# =============================================================================
UNLEX="$WORK/unlexable"; close_fixture "$UNLEX" no no answered no no true

run_hook "$HOOKS/close-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine && $MERGE_CMD")"
expect_deny "close-gate unlexable: an unterminated quote refuses instead of reading past it" "CG-UNLEXABLE"

run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine && git commit -m x")"
expect_deny "commit-gate unlexable: an unterminated quote refuses instead of reading past it" "CM-UNLEXABLE"

# The ALLOW direction, and it is the one that matters. Failing closed on every
# stray apostrophe would gate unrelated Bash calls for the whole session, so a
# raw payload that does not mention the governed verb is none of the gate's
# business even when it cannot be lexed.
run_hook "$HOOKS/close-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine")"
expect_allow "close-gate unlexable: an unbalanced quote with no merge in it is not this gate's business"
run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "echo it's fine")"
expect_allow "commit-gate unlexable: an unbalanced quote with no commit in it is not this gate's business"

# And the ordinary contraction, which is BALANCED and must stay unaffected. This
# is the case F5 broke inside its own fix once already.
run_hook "$HOOKS/commit-gate.sh" "$UNLEX" "$(bash_payload "git commit -m 'don'\\''t'")"
expect_allow "commit-gate unlexable: the ordinary way of writing a contraction still lexes"

# A trunk that is PRESENT and not a non-empty string. jq's `//` falls back only
# on null and false, so `{"trunk":""}` yielded an empty TRUNK, every comparison
# against the current branch failed, and the trunk rule was silently disabled in
# both hooks. `[]` and `{}` did the same. Absent stays defaulted, because not
# declaring a trunk is ordinary; present-but-wrong is refused, because guessing
# "main" over a stated intention would govern a branch nobody named.
for bad_trunk in '""' '[]' '{}'; do
  TRV="$WORK/trunkval"; rm -rf "$TRV"; close_fixture "$TRV" no no answered no no true
  printf '{"scaffolded":true,"trunk":%s,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' "$bad_trunk" > "$TRV/.claude/sdd.json"
  run_hook "$HOOKS/close-gate.sh" "$TRV" "$(bash_payload "$MERGE_CMD")"
  expect_deny "close-gate trunk value: [$bad_trunk] is refused, not read as no trunk at all" "CG-TRUNK-INVALID"
  run_hook "$HOOKS/scope-hook.sh" "$TRV" "$(edit_payload "$TRV/src/app.js")"
  expect_deny "scope-hook trunk value: [$bad_trunk] is refused, not read as no trunk at all" "SH-TRUNK-INVALID"
done

# Backlog item 33a: the deny MESSAGE, not merely the deny CODE.
#
# Both lines built their text with unescaped nested double quotes, and bash
# concatenates "A"B"C" into ABC, so the quote marks silently vanished. The gate
# still denied, so no existing case noticed: what was lost is the only thing the
# message is for. "Set trunk to your trunk branch name" reads as a repetition;
# `Set "trunk" to your trunk branch name` names a JSON key.
#
# It was safe only by accident of content. `trunk`, `main` and `master` carry no
# glob characters and no whitespace, so the unquoted spans expanded to
# themselves. The next value with a space or a `*` in it would get word
# splitting or pathname expansion inside a deny string, which is a poor place to
# discover that. Asserted here because nothing read the emitted text before, and
# found by shellcheck (SC2140) in an instance's CI rather than by this repo's.
TRQ="$WORK/trunkquotes"; close_fixture "$TRQ" no no answered no no true
printf '{"scaffolded":true,"trunk":"","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRQ/.claude/sdd.json"

run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the key is quoted where the text declares it" 'declares a "trunk" that is not'
run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the key is quoted where the text says to set it" 'Set "trunk" to your trunk branch name'
run_hook "$HOOKS/close-gate.sh" "$TRQ" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk message: the example branch names keep their quotes" '(for example "main" or "master")'

run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the key is quoted where the text declares it" 'declares a "trunk" that is not'
run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the key is quoted where the text says to set it" 'Set "trunk" to your trunk branch name'
run_hook "$HOOKS/scope-hook.sh" "$TRQ" "$(edit_payload "$TRQ/src/app.js")"
expect_deny "scope-hook trunk message: the example branch names keep their quotes" '(for example "main" or "master")'

# The non-regression: a trunk key that is simply ABSENT still defaults, so this
# check cannot have turned an ordinary omission into a hard failure.
TRABS="$WORK/trunkabsent"; close_fixture "$TRABS" no no answered no no true
printf '{"scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRABS/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRABS" "$(bash_payload "$MERGE_CMD")"
expect_deny "close-gate trunk value: an ABSENT trunk still defaults to main and the gate still governs" "CG-"

# =============================================================================
# AN EMPTY QUOTED SPAN IS NOTHING, which is what the shell makes it. Two
# adjacent quotes concatenate to nothing, so a git prefixed or infixed by them
# IS git. The opaque-token scanner tested for ONE OR MORE shell-safe characters,
# so the empty string failed that test, became the inert @@Q@@ token, and split
# the very word it was glued to. Found by the fourth leg.
# =============================================================================
EMPTYQ="$WORK/empty-span"; close_fixture "$EMPTYQ" no no answered no no true
for eq_cmd in 'git ""commit -am x' '""git commit -am x' 'g""it commit -am x' "git ''commit -am x"; do
  run_hook "$HOOKS/commit-gate.sh" "$EMPTYQ" "$(bash_payload "$eq_cmd")"
  expect_deny "empty span: [$eq_cmd] is the same command as its unquoted form" "CM-"
done
for eq_cmd in 'git ""merge --no-ff spec/0001-thing' '""git merge --no-ff spec/0001-thing'; do
  run_hook "$HOOKS/close-gate.sh" "$EMPTYQ" "$(bash_payload "$eq_cmd")"
  expect_deny "empty span: [$eq_cmd] is the same command as its unquoted form" "CG-"
done
run_hook "$HOOKS/commit-gate.sh" "$EMPTYQ" "$(bash_payload 'git status')"
expect_allow "empty span: an ordinary command is unaffected by the empty-span rule"

# =============================================================================
# A QA VERDICT IS A VERDICT, NOT THE WORD PASS IN A SENTENCE (F5, third leg).
# The check matched PASS, PARTIAL or FAIL anywhere in the QA block, so prose
# satisfied it. Appendix C's shape puts the verdict at the end of its line, so
# that is what is required: narrow enough to reject prose, wide enough for every
# real shape. The ALLOW cases matter more than the deny one, because false
# denial is the direction that breaks honest closes.
#
# The verdict line is inserted against the QA Pass 2 marker, which is where
# close_fixture ends the QA Pass 1 block.
#
# PORTABLY, via awk and a temp file, because the two sed forms this used carried
# TWO GNU-only assumptions each and macOS has neither (1.0.9). `sed -i` without
# an argument is GNU: BSD sed reads the NEXT WORD as the backup suffix, so
# `sed -i 's|...|' file` consumes the script as a suffix and fails. And `\n` in a
# sed REPLACEMENT is GNU: BSD sed inserts a literal `n`, so even a corrected
# `-i ''` would have written "...not run" followed by "nn- QA Pass 2..." and the
# assertion would have failed for a reason having nothing to do with the gate.
#
# awk needs neither: it prints the inserted lines itself.
# insert_block_before <file> <marker-line> <block-file>
#
# insert_before below passes its text through `awk -v`, and BWK awk (the macOS
# userland) REFUSES a newline in a -v assignment: "awk: newline in string".
# It does not warn and carry on, it exits 2, so the awk writes nothing, the
# `&& mv` never runs, and the file is left UNCHANGED. A multi-line insertion
# through that path therefore inserts nothing and the fixture silently keeps
# whatever it already had, which is how a corpus written to prove a new rule
# passes by testing the old one. The QA verdict block is multi-line by
# construction, so it goes through a FILE and awk's getline instead.
insert_block_before() {
  awk -v marker="$2" -v bf="$3" '
    $0 == marker { while ((getline line < bf) > 0) print line; close(bf); print "" }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

insert_before() { # insert_before <file> <marker-line> <text>
  awk -v marker="$2" -v ins="$3" '
    $0 == marker { print ins; print "" }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ===========================================================================
# >>> SHARD-BEGIN qa-verdict-structure cost=10
if shard_region qa-verdict-structure; then
# THE QA VERDICT IS A STRUCTURE (2026-08-05 leg, F5).
#
# The rule these corpora used to pin was a regex over English, and F5 closed it
# with one line: `Criteria that did not PASS: 2, 5 and 7.` A sentence stating
# the OPPOSITE of a pass satisfied the close gate, the git hook and the trunk
# audit, and the merge landed. The three layers were in deliberate byte-identical
# lockstep, so the gate and its only backstop were blind together, as designed.
#
# The class fix is not a tighter pattern. Part 6 now requires a fenced qa-pass-1
# block whose every line is `<criterion>: PASS|PARTIAL|FAIL` with a space-free
# criterion, and the payload is UNWRITEABLE there rather than refused.
#
# Both directions, and the negative corpus is the one that matters: it is the
# F5 payload and its three measured siblings, plus the prose and tally cases the
# old rule already refused, all of which must stay refused.
# ===========================================================================

# NEGATIVE: a sentence is not a verdict, however it reads, and a spec carrying
# ONLY the pasted report has no verdict at all now.
for qa_prose in \
  'Criteria that did not PASS: 2, 5 and 7.' \
  'Blocked on staging: FAIL to reach the host, so QA Pass 1 never ran.' \
  'Mobile was never exercised, so nothing there can PASS.' \
  'No criterion was checked; there is nothing here that could PASS.' \
  'the browser tests PASS on my machine but mobile was never run' \
  'we expect the suite to PASS once the hardware arrives' \
  'a criterion that would FAIL under load was never exercised' \
  'the 3 browser tests PASS on my machine but mobile was never run'; do
  QAN="$WORK/qa-neg"; rm -rf "$QAN"; close_fixture "$QAN" yes no answered yes no true
  git -C "$QAN" checkout -q spec/0001-thing
  insert_before "$QAN/specs/0001-thing.md" '- QA Pass 2 (human): done' "$qa_prose"
  git -C "$QAN" add -A >/dev/null 2>&1; git -C "$QAN" commit -qm "prose" >/dev/null 2>&1
  git -C "$QAN" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAN" "$(bash_payload "$MERGE_CMD")"
  expect_deny "qa verdict negative: [$qa_prose] is not a verdict block" "CG-NO-QA-VERDICT"
done

# NEGATIVE, INSIDE THE BLOCK, which is the direction that makes the structure
# worth having. A non-verdict line inside the fence is REFUSED, not skipped,
# because skipping is exactly how a sentence gets back in.
for qa_inner in \
  'Criteria that did not PASS: 2, 5 and 7.' \
  '4 PASS / 0 FAIL' \
  'Section A: 17/17 PASS' \
  '| 1 | criterion | PASS | evidence |'; do
  QAI="$WORK/qa-inner"; rm -rf "$QAI"; close_fixture "$QAI" yes no answered yes no true
  git -C "$QAI" checkout -q spec/0001-thing
  printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n%s\n```\n' "$qa_inner" > "$WORK/qa-blk.txt"
  insert_block_before "$QAI/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
  git -C "$QAI" add -A >/dev/null 2>&1; git -C "$QAI" commit -qm "inner" >/dev/null 2>&1
  git -C "$QAI" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAI" "$(bash_payload "$MERGE_CMD")"
  expect_deny "qa verdict inner: [$qa_inner] inside the block is refused, not skipped" "CG-NO-QA-VERDICT"
done

# POSITIVE. The criterion is a bare identifier, so these are the shapes a real
# spec produces: plain numbers, the AC-style ids two live instances use, and
# dotted or underscored ids. The nine prose shapes item 35 collected from real
# specs are no longer load-bearing: they stay in the pasted report below the
# block, which no gate reads.
for qa_block in \
  '1: PASS' \
  '1: PASS
2: PARTIAL
3: FAIL' \
  'AC-B1: PASS' \
  'crit_2.a: PARTIAL' \
  '1:PASS'; do
  QAOK="$WORK/qa-ok"; rm -rf "$QAOK"; close_fixture "$QAOK" yes no answered yes no true
  git -C "$QAOK" checkout -q spec/0001-thing
  printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n%s\n```\n' "$qa_block" > "$WORK/qa-blk.txt"
  insert_block_before "$QAOK/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
  git -C "$QAOK" add -A >/dev/null 2>&1; git -C "$QAOK" commit -qm "verdict" >/dev/null 2>&1
  git -C "$QAOK" checkout -q main
  run_hook "$HOOKS/close-gate.sh" "$QAOK" "$(bash_payload "$MERGE_CMD")"
  expect_allow "qa verdict: a qa-pass-1 block of [$(printf '%s' "$qa_block" | tr '\n' ' ')] closes"
done

# THE UNEDITED TEMPLATE MUST NOT CLOSE. Appendix C ships the block with a
# placeholder inside it, and a placeholder is not a verdict.
QATPL="$WORK/qa-tpl"; rm -rf "$QATPL"; close_fixture "$QATPL" yes no answered yes no true
git -C "$QATPL" checkout -q spec/0001-thing
printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n<one line per criterion: delete this note>\n```\n' > "$WORK/qa-blk.txt"
insert_block_before "$QATPL/specs/0001-thing.md" '- QA Pass 2 (human): done' "$WORK/qa-blk.txt"
git -C "$QATPL" add -A >/dev/null 2>&1; git -C "$QATPL" commit -qm tpl >/dev/null 2>&1
git -C "$QATPL" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$QATPL" "$(bash_payload "$MERGE_CMD")"
expect_deny "qa verdict template: the unedited Appendix C placeholder does not close" "CG-NO-QA-VERDICT"

# THE LOCKSTEP ITSELF, and it is the point rather than a nicety. The three
# layers are written independently and asserted IDENTICAL, so a widening applied
# to one and not the others fails here rather than in the field. F5 reached the
# backstop THROUGH this lockstep, and the lockstep is kept anyway: the answer to
# a gate and its backstop agreeing on a wrong rule is a right rule, not two
# rules. Leading whitespace and the SLH_ prefix are stripped before comparing.
QA_LOCK_BAD=""
QA_LOCK_REF=""
for qa_lock_f in "$HOOKS/close-gate.sh" "$SCRIPTS/trunk-audit.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; do
  qa_lock_v="$(grep -m1 -E '^[[:space:]]*(SLH_)?QA_PASS1_AWK=' "$qa_lock_f" | sed 's/^[[:space:]]*//; s/^SLH_//' || true)" # fail-open-ok: an empty value is the finding and is tested immediately below
  if [[ -z "$qa_lock_v" ]]; then
    QA_LOCK_BAD="$QA_LOCK_BAD $(basename "$qa_lock_f"):absent"
  elif [[ -z "$QA_LOCK_REF" ]]; then
    QA_LOCK_REF="$qa_lock_v"
  elif [[ "$qa_lock_v" != "$QA_LOCK_REF" ]]; then
    QA_LOCK_BAD="$QA_LOCK_BAD $(basename "$qa_lock_f"):differs"
  fi
done
if [[ -z "$QA_LOCK_BAD" ]]; then
  ok "qa verdict lockstep: all three layers carry a byte-identical QA_PASS1_AWK"
else
  bad "qa verdict lockstep: all three layers carry a byte-identical QA_PASS1_AWK" \
      "these do not agree:$QA_LOCK_BAD"
fi

# THE SAME LOCKSTEP FOR THE TEMPLATE STRIPPER (v1.9 leg, V19-F4).
#
# Its three copies ARE byte-identical and always have been, so no gate was
# misbehaving. What was missing is the DETECTOR: a drifted copy passed the whole
# suite and nothing said so, while TWO comments in the shipped bytes claimed the
# lockstep was asserted. The sibling lexers QA_PASS1_AWK and SLH_LIVE_TEXT_AWK
# both have this assertion, which is why the pattern looked present until
# somebody checked which of the three had one: A9's sibling rule applied to the
# assertions rather than to the code.
#
# It matters more from 2026-08-26 than it did when it was filed. Until this
# commit the stripper had ONE caller in the library; the V19-F2 fix gave it a
# second (the lifecycle detector), so a drifted copy now moves what pre-commit
# accepts as well as what the close verification accepts.
#
# Watched RED first against a deliberately drifted copy: appending a single
# space to close-gate.sh's value took this assertion to close-gate.sh:differs
# with the rest of the suite unchanged.
TF_LOCK_BAD=""
TF_LOCK_REF=""
for tf_lock_f in "$HOOKS/close-gate.sh" "$SCRIPTS/trunk-audit.sh" "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; do
  tf_lock_v="$(grep -m1 -E '^[[:space:]]*(SLH_)?TEMPLATE_FENCE_AWK=' "$tf_lock_f" | sed 's/^[[:space:]]*//; s/^SLH_//' || true)" # fail-open-ok: an empty value is the finding and is tested immediately below
  if [[ -z "$tf_lock_v" ]]; then
    TF_LOCK_BAD="$TF_LOCK_BAD $(basename "$tf_lock_f"):absent"
  elif [[ -z "$TF_LOCK_REF" ]]; then
    TF_LOCK_REF="$tf_lock_v"
  elif [[ "$tf_lock_v" != "$TF_LOCK_REF" ]]; then
    TF_LOCK_BAD="$TF_LOCK_BAD $(basename "$tf_lock_f"):differs"
  fi
done
if [[ -n "$TF_LOCK_REF" && -z "$TF_LOCK_BAD" ]]; then
  ok "template stripper lockstep: all three layers carry a byte-identical TEMPLATE_FENCE_AWK"
else
  bad "template stripper lockstep: all three layers carry a byte-identical TEMPLATE_FENCE_AWK" \
      "ref-empty=[${TF_LOCK_REF:0:1}] disagreements:$TF_LOCK_BAD"
fi

fi; shard_region_end
# <<< SHARD-END qa-verdict-structure
# =============================================================================
# A FUNCTION DEFINITION AND A TWO-OPERAND CHECKOUT (F6/F7, third 1.0.8 leg).
# Both put something other than the governed verb where the gate looks, and the
# checkout one is the FOURTH spelling of a class the previous three repairs each
# closed one spelling at a time. Counting operands settles it without asking
# what any operand looks like, which is what the earlier repairs kept doing.
# =============================================================================
FN="$WORK/fn-and-pathspec"; close_fixture "$FN" no no answered no no true
git -C "$FN" branch feat-y main >/dev/null 2>&1

for fn_cmd in \
  'function f { git merge --no-ff spec/0001-thing; }; f' \
  'f() { git merge --no-ff spec/0001-thing; }; f' \
  'git checkout feat-y src/app.js; git merge --no-ff spec/0001-thing' \
  'git checkout feat-y specs/STATUS.md && git merge --no-ff spec/0001-thing' ; do
  run_hook "$HOOKS/close-gate.sh" "$FN" "$(bash_payload "$fn_cmd")"
  expect_deny "hidden verb: [$fn_cmd] is still judged" "CG-"
done

# ALLOW: a ONE-operand checkout is a real switch and must keep working, or the
# operand count has turned the branch tracker off rather than fixing it.
run_hook "$HOOKS/close-gate.sh" "$FN" "$(bash_payload 'git checkout feat-y && git merge --no-ff spec/0001-thing')"
expect_allow "hidden verb: a one-operand checkout still switches, so the tracker still works"

# A ROLES value that is not an object disabled the scope hook entirely: the jq
# extraction errored, ROLE_PATHS came back empty, and the deny loop ran zero
# times. Same shape as the trunk value, one key across.
for roles_v in '"src"' '[]' '123'; do
  RLS="$WORK/roles-shape"; rm -rf "$RLS"; close_fixture "$RLS" no no answered no no true
  printf '{"scaffolded":true,"trunk":"main","gate_command":"true","roles":%s}\n' "$roles_v" > "$RLS/.claude/sdd.json"
  run_hook "$HOOKS/scope-hook.sh" "$RLS" "$(edit_payload "$RLS/src/app.js")"
  expect_deny "roles shape: [$roles_v] is refused, not read as no roles at all" "SH-ROLES-SHAPE"
done

# =============================================================================
# THE TRUNK VALUE MUST NAME A LOCAL BRANCH (F1, second 1.0.8 leg). The check
# added earlier the same day required a non-empty string and stopped there,
# which is the same "container, not contents" error one level in.
#
# The route was the SHIPPED UPGRADE PATH: skills/upgrade told the agent to
# detect the trunk with `git symbolic-ref refs/remotes/origin/HEAD`, which
# returns a full ref path. Every ordinary clone has an origin/HEAD, so that is
# what got recorded, and both hooks then compared `refs/remotes/origin/main`
# against `main` and allowed every governed operation in silence.
# =============================================================================
TRB="$WORK/trunk-branch"; close_fixture "$TRB" no no answered no no true
git -C "$TRB" update-ref refs/remotes/origin/main "$(git -C "$TRB" rev-parse main)" 2>/dev/null
git -C "$TRB" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null

for trunk_spelling in 'refs/remotes/origin/main' 'refs/heads/main' 'heads/main' 'origin/main'; do
  printf '{"scaffolded":true,"trunk":"%s","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' \
    "$trunk_spelling" > "$TRB/.claude/sdd.json"
  run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
  expect_deny "trunk spelling: [$trunk_spelling] reduces to the branch and the gate still governs" "CG-"
  run_hook "$HOOKS/scope-hook.sh" "$TRB" "$(edit_payload "$TRB/src/app.js")"
  expect_deny "trunk spelling: [$trunk_spelling] still guards trunk writes" "SH-"
done

# A trunk naming NO local branch is refused rather than guessed at. Guessing
# "main" would silently govern a branch the project never named.
printf '{"scaffolded":true,"trunk":"no-such-branch","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRB/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
expect_deny "trunk spelling: a trunk that names no local branch is refused, not guessed" "CG-TRUNK-NOT-A-BRANCH"

# And the ordinary value is untouched.
printf '{"scaffolded":true,"trunk":"main","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$TRB/.claude/sdd.json"
run_hook "$HOOKS/close-gate.sh" "$TRB" "$(bash_payload "$MERGE_CMD")"
expect_deny "trunk spelling: a plain branch name still works exactly as before" "CG-"

# =============================================================================
# AN OPTION'S VALUE IS NOT AN OPTION, AND NOT A REF (F4/F5, second 1.0.8 leg).
# Every word after `merge` was scanned as both, so the VALUE of -m was read as
# though it had been typed as a flag: `-m "--continue"` matched the resumption
# exemption and skipped every close check, and a message word could resolve as
# a ref and make the gate validate a different branch from the one merged.
# =============================================================================
OPTV="$WORK/optvalue"; close_fixture "$OPTV" no no answered no no true

for optv_cmd in \
  'git merge --no-ff spec/0001-thing -m "--continue"' \
  'git merge --no-ff spec/0001-thing -m --abort' \
  'git merge --no-ff spec/0001-thing -m --quit' \
  'git merge --no-ff spec/0001-thing -m spec/0002-other' ; do
  run_hook "$HOOKS/close-gate.sh" "$OPTV" "$(bash_payload "$optv_cmd")"
  expect_deny "option value: [$optv_cmd] is judged on the branch, not on its message" "CG-"
done

# The two ALLOW directions, and they are why this is a value-stripping fix
# rather than a blanket refusal of -m. A REAL resumption must stay exempt, or a
# conflicted close has no permitted way to finish; and an ordinary close with an
# ordinary message must still pass.
run_hook "$HOOKS/close-gate.sh" "$OPTV" "$(bash_payload 'git merge --continue')"
expect_allow "option value: a REAL --continue is still exempt, so a conflicted close can finish"

# =============================================================================
# >>> SHARD-BEGIN octopus-merge cost=8
if shard_region octopus-merge; then
# AN OCTOPUS MERGE IS SEVERAL MERGES (F2/F6 of the second 1.0.8 leg). The word
# loop broke on the FIRST operand that resolved to a spec or chore ref, so
# `git merge --no-ff spec/0003-good spec/0004-bad` contributed exactly one ref:
# the compliant branch was judged and the unclosed one landed on the trunk with
# every close check skipped. A command that merges several branches answers for
# all of them, exactly as a command carrying several commits does.
# =============================================================================
OCTO="$WORK/octopus"; close_fixture "$OCTO" no no answered no no true
git -C "$OCTO" checkout -q main
git -C "$OCTO" checkout -q -b spec/0009-good
mkdir -p "$OCTO/specs"
printf '# Spec 0009\n\nStatus: CLOSED\n\n## Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n- QA Pass 2 (human): done\n\n- Architecture diagram: no impact\n' > "$OCTO/specs/0009-good.md"
printf '# Spec inventory\n\n| Num | Title | Status |\n| --- | --- | --- |\n| 0009 | Good | CLOSED |\n' > "$OCTO/specs/STATUS.md"
git -C "$OCTO" add -A >/dev/null 2>&1; git -C "$OCTO" commit -qm "close 0009" >/dev/null 2>&1
git -C "$OCTO" checkout -q main

# The compliant branch alone must pass, or the two cases below prove nothing.
run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good')"
expect_allow "octopus: the compliant branch alone is allowed, so the control is real"

run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good spec/0001-thing')"
expect_deny "octopus: a non-compliant SECOND operand is still judged" "CG-"

run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0001-thing spec/0009-good')"
expect_deny "octopus: order does not matter; the non-compliant operand is judged either way" "CG-"

# ---------------------------------------------------------------------------
# THE OTHER HALF OF THE SAME SENTENCE (leg 4, F3).
#
# The fix above extended the COLLECTION and left the DISPOSITION short-circuited.
# One operand that resolved reached `continue` and every operand beside it was
# never classified at all, so an operand this gate REFUSES on its own was waved
# through by a compliant sibling:
#
#     git merge --no-ff FETCH_HEAD                  DENY, correctly
#     git merge --no-ff spec/0009-good FETCH_HEAD   ALLOWED, and it landed
#
# Executed for real, the octopus merge succeeded and unreviewed content was on
# the trunk. The trunk audit did not catch it either: it read the smuggled
# parent as a chore merge and reported 0 violations.
#
# Asserted over the SET of indirect forms rather than over FETCH_HEAD, which is
# the one a finding happened to use, and with a chore branch as the resolvable
# operand as well as a spec branch: chore branches need no artifacts at all, so
# that is the cheapest spelling of the attack, not an exotic one.
git -C "$OCTO" update-ref FETCH_HEAD spec/0001-thing
git -C "$OCTO" checkout -q -b chore/octo-cleanup main 2>/dev/null || git -C "$OCTO" checkout -q chore/octo-cleanup
printf 'cleanup\n' > "$OCTO/cleanup.txt"
git -C "$OCTO" add -A >/dev/null 2>&1; git -C "$OCTO" commit -qm "chore" >/dev/null 2>&1
git -C "$OCTO" checkout -q main

for resolvable in spec/0009-good chore/octo-cleanup; do
  for indirect in FETCH_HEAD ORIG_HEAD HEAD '-' '@{-1}' '$EVIL'; do
    run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "git merge --no-ff $resolvable $indirect")"
    expect_deny "octopus indirect: [$resolvable $indirect] is refused; a resolvable sibling does not vouch for an unverifiable operand" "CG-UNNAMEABLE-REF"
    run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "git merge --no-ff $indirect $resolvable")"
    expect_deny "octopus indirect: [$indirect $resolvable] is refused in the other order too" "CG-UNNAMEABLE-REF"
  done
done

# An operand that LOOKS like a spec branch and resolves to nothing is the same
# case with a different cause, and it had the same hole: SEG_LOOKS_SPEC is set
# for spec-shaped words whether or not they resolve, so it could not answer
# "was anything left unresolved" and the disposition never asked.
run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload 'git merge --no-ff spec/0009-good spec/9999-nonexistent')"
expect_deny "octopus indirect: an unresolvable spec-shaped operand is refused beside a compliant one" "CG-UNNAMEABLE-REF"

# AND THE DIRECTION THAT MAKES IT A FIX RATHER THAN A BLANKET REFUSAL. An
# OPTION is not an operand, and `-` and `--no-ff` both start with a dash. If
# these regress, every close in the field breaks.
for allowed_cmd in \
  'git merge --no-ff spec/0009-good' \
  'git merge --squash spec/0009-good' \
  'git merge -s recursive --no-ff spec/0009-good' \
  'git merge -X ours --no-ff spec/0009-good' \
  'git merge --no-ff spec/0009-good -m "closing 0009"' \
  'git merge --no-ff spec/0009-good chore/octo-cleanup' ; do
  run_hook "$HOOKS/close-gate.sh" "$OCTO" "$(bash_payload "$allowed_cmd")"
  expect_allow "octopus indirect control: [$allowed_cmd] still merges, so options were not mistaken for operands"
done

fi; shard_region_end
# <<< SHARD-END octopus-merge
# =============================================================================
# A CHECKOUT IS CONDITIONAL (F7 of the 1.0.8 leg). The tracker modelled every
# checkout as unconditionally taken, which is false for the commonest failure
# there is: a checkout ABORTS when local changes would be overwritten, and after
# it aborts the shell is still on the trunk. So the merge ran on the trunk while
# the gate believed it was standing on a feature branch.
#
# Only `&&` implies the previous command succeeded. It is kept exact rather than
# swept in with the others, because denying it would break an ordinary workflow:
# if that checkout fails, the merge never runs at all.
# =============================================================================
SWFIX="$WORK/switch-conditional"; close_fixture "$SWFIX" no no answered no no true
git -C "$SWFIX" branch feat-x main >/dev/null 2>&1

run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x; git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: a merge reached across ; from a checkout is unresolved, not 'some other branch'" "CG-UNRESOLVED-SWITCH"

run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x || git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: || does not imply the checkout succeeded either" "CG-UNRESOLVED-SWITCH"

# ALLOW: && DOES imply success, so a merge onto a feature branch is not a close
# and must not be denied. This is the assertion that stops the repair from being
# "deny everything with a checkout in it".
run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout feat-x && git merge --no-ff spec/0001-thing')"
expect_allow "conditional switch: && implies success, so a merge on a feature branch is still allowed"

# DENY: the compound close is the whole reason the tracker exists, and it must
# survive the repair intact.
run_hook "$HOOKS/close-gate.sh" "$SWFIX" "$(bash_payload 'git checkout main && git merge --no-ff spec/0001-thing')"
expect_deny "conditional switch: the compound close onto the trunk is still gated" "CG-"

# =============================================================================
# COMMAND POSITION, part three: redirections and path-qualified wrappers.
# All three found by the 1.0.8 leg (F17, F18) and by the oracle once its corpus
# was taught to generate them. None is adversarial: a caller silencing output
# writes a redirection without thinking about parsers, /usr/bin/env is what a
# shebang produces, and 2>&1 is how everyone spells it.
# =============================================================================
for pos_cmd in \
  '>/dev/null git merge --no-ff spec/0001-thing' \
  '2>/dev/null git merge --no-ff spec/0001-thing' \
  '< /dev/null git merge --no-ff spec/0001-thing' \
  '>/tmp/out 2>&1 git merge --no-ff spec/0001-thing' \
  '/usr/bin/env git merge --no-ff spec/0001-thing' \
  '/bin/nice git merge --no-ff spec/0001-thing' \
  '/usr/bin/nohup git merge --no-ff spec/0001-thing' \
  '>/tmp/out 2>&1 /usr/bin/env git merge --no-ff spec/0001-thing' ; do
  if [[ "$(corpus_verdict "$pos_cmd")" == "deny" ]]; then
    ok "command position: [$pos_cmd] is judged"
  else
    bad "command position: [$pos_cmd] must be judged" \
        "something other than git sat at the head of the segment and the merge was never inspected"
  fi
done

# The `&` inside a redirection is NOT a control operator. `2>&1` was cut by the
# segment splitter into `2>` and `1 git merge ...`, so neither fragment began
# with git. Asserted separately from the loop above because it is a splitter
# defect rather than a stripping one, and the two fail differently.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing >/tmp/o 2>&1')" == "deny" ]]; then
  ok "command position: a trailing 2>&1 does not split the command away from its verb"
else
  bad "command position: a trailing 2>&1 must not split the command" \
      "the fd-duplication ampersand was read as a segment separator"
fi

# The ALLOW direction. Stripping redirections must not make the gate blind to
# what follows, nor deny ordinary redirected work that merges nothing.
if [[ "$(corpus_verdict '>/dev/null git status')" == "allow" ]]; then
  ok "command position: a redirected non-merge is still allowed"
else
  bad "command position: a redirected non-merge must still be allowed" \
      "stripping redirections turned an ordinary command into a denial"
fi

# =============================================================================
# The spec-versus-chore TIE-BREAK, and the ambiguity refusal beside it.
#
# 1.0.8's identity-by-commit rewrite ended in `... | head -n1` over a
# refname-sorted list. `refs/heads/chore/*` sorts before `refs/heads/spec/*`, so
# a chore ref on the same commit won, SPEC_BRANCH read as a chore branch, and
# the `== spec/*` guard skipped the entire close block: no Closing report, no QA
# verdict, no diagram, no STATUS row, no authorship check. It did not fail to
# close the alias hole, it INVERTED it, because 1.0.7 classified by NAME and so
# kept the canonical spelling governed whatever else pointed at the commit.
#
# Four assertions, because three of them can pass for the wrong reason alone.
# =============================================================================

# 1. The regression itself. chore/cleanup is on spec/0001-thing's commit (see
#    the corpus setup), and the merge names the SPEC branch, not the chore one.
if [[ "$(corpus_verdict 'git merge --no-ff spec/0001-thing')" == "deny" ]]; then
  ok "tie-break: a chore/ ref on the same commit does not disarm the close checks"
else
  bad "tie-break: a chore/ ref on the same commit must not disarm the close checks" \
      "a chore sibling made an unclosed spec branch mergeable; the spec-over-chore preference has regressed to head -n1"
fi

# 2. The deny must name the SPEC branch. Denying for the wrong reason is how two
#    of the 2026-07-27 findings first read as refutations.
if bash_payload 'git merge --no-ff spec/0001-thing' \
     | CLAUDE_PROJECT_DIR="$CORP" bash "$HOOKS/close-gate.sh" 2>/dev/null \
     | grep -q 'spec/0001-thing'; then
  ok "tie-break: the deny names the spec branch, not the chore ref beside it"
else
  bad "tie-break: the deny must name the spec branch" \
      "the gate denied but reported a chore ref, so it judged the wrong object and the verdict is right by accident"
fi

# 3. THE ALLOW DIRECTION, which is the assertion that carries the weight. A
#    tie-break repair that simply denies more would satisfy every check above.
#    A COMPLIANT close must still pass with a chore sibling present.
#    Uses the suite's own run_hook/expect_allow idiom rather than a hand-rolled
#    jq read. The first cut of this assertion piped the hook into
#    `jq -r '... // "allow"'`, and an ALLOW emits NOTHING, so jq had no input
#    document, the `//` default never fired, and an empty string was compared
#    against "allow". It reported the fix as breaking honest closes when the
#    fix was fine. That is this repo's signature defect appearing inside the
#    test written to catch this repo's signature defect.
TIEOK="$WORK/tiebreak-allow"
close_fixture "$TIEOK" yes yes answered yes no true
git -C "$TIEOK" branch -f chore/cleanup spec/0001-thing
run_hook "$HOOKS/close-gate.sh" "$TIEOK" "$(bash_payload "$MERGE_CMD")"
expect_allow "tie-break: a COMPLIANT close is still allowed with a chore ref on the same commit"

# 4. TWO DIFFERENT SPECS on one commit. The gate cannot tell whose Closing
#    report it is judging, so it refuses instead of picking one and validating
#    one spec's artifacts for a merge of another.
#
#    Distinctness is by spec NUMBER and not by ref count, deliberately: a local
#    branch, its remote-tracking copy and a tag are three refs for ONE spec, and
#    refusing those would deny every ordinary close. That non-regression is
#    covered by the remote-tracking cases elsewhere in this file.
TIEAMB="$WORK/tiebreak-ambiguous"
close_fixture "$TIEAMB" no no answered no no true
git -C "$TIEAMB" branch -f spec/0009-alias spec/0001-thing
if bash_payload 'git merge --no-ff spec/0001-thing' \
     | CLAUDE_PROJECT_DIR="$TIEAMB" bash "$HOOKS/close-gate.sh" 2>/dev/null \
     | grep -qF 'CG-AMBIGUOUS-SPEC'; then
  ok "tie-break: two different specs on one commit is refused, not resolved by sort order"
else
  bad "tie-break: two different specs on one commit must be refused" \
      "the gate picked one spec and judged its artifacts for a merge that could be either; that is the wrong-object class the rewrite exists to end"
fi

# The two remaining asserted holes are exercised elsewhere in this file and are
# named here so the ledger's "asserted" claims are all traceable:
#   - "Secret and style scanning is best-effort early warning, not a guarantee."
#     -> its pattern-set clause ("a first cut", a bullet of its own until the
#     2026-09-02 merge): commit-gate d (a shape it CATCHES) and the miss below
#     (a shape it does not).
#   - "The staged-content scans read every staged line." -> the vendored-content
#     case below: foreign content in a staged diff is denied on style alone.
SCAN="$WORK/scan-scope"
git_init "$SCAN"
sdd_json "$SCAN"
mkdir -p "$SCAN/vendor"
printf 'const x = 1; /* upstream file, not ours to restyle %s */\n' "$EMDASH" > "$SCAN/vendor/lib.js"
git -C "$SCAN" add vendor/lib.js
run_hook "$HOOKS/commit-gate.sh" "$SCAN" "$(bash_payload 'git commit -m "vendor: add upstream lib"')"
expect_deny "documented hole: vendored content is style-scanned like our own writing" "em-dash"
git -C "$SCAN" reset -q

printf 'token = "%s"\n' 'ghp_ShortOne' > "$SCAN/cfg.txt"
git -C "$SCAN" add cfg.txt
run_hook "$HOOKS/commit-gate.sh" "$SCAN" "$(bash_payload 'git commit -m cfg')"
expect_allow "documented hole: the secret scan misses values below its length threshold"
git -C "$SCAN" reset -q

