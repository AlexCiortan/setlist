#!/usr/bin/env bash
# test/suite/06-trunk-audit.sh: shard 6 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE TRUNK AUDIT (1.0.5, advisory)
#
# The hooks decide by parsing a command before it runs; this reads history
# after the fact, which is decidable where the parser never can be. Covered
# in both directions, and the fixtures mirror the shapes real history turned
# out to have: a suffixed spec number (0005b), and a chore merge with no spec
# at all. Both were false positives on the first run against a real repo.
# =============================================================================

audit_fixture() { # audit_fixture <dir> <mode: clean|direct|unclosed>
  local d="$1" mode="$2"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git_init "$d"
  sdd_json "$d"
  git -C "$d" add .claude/sdd.json && git -C "$d" commit -qm "stamp"
  # a compliant spec close, with a SUFFIXED number
  git -C "$d" checkout -q -b spec/0005b-thing
  mkdir -p "$d/src"
  printf 'feature\n' > "$d/src/f.js"
  {
    printf '# Spec 0005b\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    # THE DIAGRAM FIELD, which this fixture omitted. It was "compliant" only
    # against the audit's OLD close-condition subset; the merge hook has always
    # required this line, so a spec without it would be refused at merge time.
    # Round 6 gave the audit the same check, and that is what exposed the gap.
    printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
  } > "$d/specs/0005b-thing.md"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0005b"
  if [[ "$mode" == "unclosed" ]]; then
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | ACTIVE |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "not closed after all"
  fi
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge spec 0005b" spec/0005b-thing
  # A chore merge carrying role-path changes and no spec. It RECORDS ITS
  # COMPLETION, which is what makes it legitimate rather than merely
  # unfalsifiable.
  #
  # This fixture used to omit the archive line and the comment here called it
  # "legitimate, and indistinguishable from an unspecced feature in history".
  # The second half was true and is exactly the finding: F2/F7 of the 2026-08-05
  # leg showed that the audit excused every such merge as "unverifiable" at exit
  # 0, so any route reaching the trunk without firing pre-merge-commit was waved
  # through by the backstop. Part 5b's rule is that a chore records an archive
  # line; a chore merge without one, made after the instance adopted the rules,
  # is a violation now. So the compliant fixture is compliant.
  git -C "$d" checkout -q -b chore/tidy
  printf 'tidy\n' >> "$d/src/f.js"
  printf -- '- CHORE-007: DONE 2026-08-05. tidy the source tree\n' >> "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "chore work"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge chore: tidy" chore/tidy
  if [[ "$mode" == "direct" ]]; then
    printf 'snuck in\n' >> "$d/src/f.js"
    git -C "$d" add -A && git -C "$d" commit -qm "hotfix straight onto the trunk"
  fi
  # F1 of the 2.2.0 leg: the same direct-commit violation as "direct" above,
  # differing ONLY in the filename. Each of these four names is emitted QUOTED by
  # git's --name-only, which is what made the role test blind to it. The ASCII
  # sibling is `plainrole` and runs first as the control, so a green row here is
  # evidence about the NAME and not about the fixture builder.
  case "$mode" in
    plainrole)  TA_NAME='plain.js' ;;
    utf8role)   TA_NAME="$(printf 'caf\303\251.js')" ;;
    bslashrole) TA_NAME='ba\ck.js' ;;
    quoterole)  TA_NAME='qu"ote.js' ;;
    tabrole)    TA_NAME="$(printf 'ta\tb.js')" ;;
    *)          TA_NAME='' ;;
  esac
  if [[ -n "$TA_NAME" ]]; then
    printf 'const b=2\n' > "$d/src/$TA_NAME"
    git -C "$d" add -A && git -C "$d" commit -qm "direct role-path commit"
    # The fixture ASSERTS ITS OWN SHAPE before the audit reads it. A path git
    # refused to stage would leave a commit that touches nothing, and every case
    # below would then pass by testing an empty diff, which is the vacuous
    # comparison this suite exists to refuse.
    if [[ -z "$(git -C "$d" diff --name-only HEAD~1 HEAD 2>/dev/null)" ]]; then
      printf 'FIXTURE BROKEN: audit_fixture %s staged no path\n' "$mode" >&2
    fi
  fi
  # B6, all three shapes. Each rides on the fixture above, which has left spec
  # 0005b CLOSED on the trunk: that already-closed spec is the laundering
  # vehicle in two of the three.
  if [[ "$mode" == "prose" ]]; then
    # A Closing report whose QA block carries NO pasted verdict, only prose
    # that happens to contain the word PASS. The close gate rejects this; its
    # backstop accepted it, which is the half of B6 that makes an audit worse
    # than useless: it reports clean on the exact text the gate refuses.
    git -C "$d" checkout -q -b spec/0006-prose
    printf 'more\n' >> "$d/src/f.js"
    {
      printf '# Spec 0006\n\nStatus: CLOSED\n\n## Closing report\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      printf 'the browser tests PASS on my machine but mobile was never run\n\n'
      printf -- '- QA Pass 2 (human): done\n'
    } > "$d/specs/0006-prose.md"
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0006 | Prose | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0006"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0006" spec/0006-prose
  fi
  if [[ "$mode" == "fencedclose" ]]; then
    # The audit's half of adversarial review F9. close-gate.sh strips fenced spans
    # before its close checks; this script never did, so a spec whose entire
    # Closing report is a quoted example was reported clean by the backstop that
    # README:176 sells as reading "what ended up in your history".
    git -C "$d" checkout -q -b spec/0008-fenced
    printf 'fenced\n' >> "$d/src/f.js"
    cat > "$d/specs/0008-fenced.md" <<'AUDITFENCED'
# Spec 0008

Status: CLOSED

I will fill this in later; here is the shape:

```markdown
## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
```
AUDITFENCED
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0008 | Fenced | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0008"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0008" spec/0008-fenced
  fi
  if [[ "$mode" == "secondspec" ]]; then
    # A branch touching TWO spec files: the already-CLOSED 0005b (which sorts
    # first, so `head -n1` picked it) and a genuinely non-compliant 0007. The
    # audit validated the compliant one and never looked at the other.
    git -C "$d" checkout -q -b spec/0007-second
    printf 'second\n' >> "$d/src/f.js"
    printf '\nA one-line amendment.\n' >> "$d/specs/0005b-thing.md"
    printf '# Spec 0007\n\nStatus: ACTIVE\n\nNo closing report at all.\n' > "$d/specs/0007-second.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0007 plus an edit to 0005b"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0007" spec/0007-second
  fi
  if [[ "$mode" == "tablecell" ]]; then
    # Item 35's positive direction on the BACKSTOP side. A compliant close whose
    # QA verdicts are table cells, which is the commonest real shape and which
    # the pre-widening rule refused. If the gate widens and the audit does not,
    # the audit starts reporting violations against merges the gate permits,
    # which is F8's disagreement running the other way.
    git -C "$d" checkout -q -b spec/0008-table
    printf 'table\n' >> "$d/src/f.js"
    {
      printf '# Spec 0008\n\nStatus: CLOSED\n\n## Closing report\n\n'
      printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n2: PARTIAL\n```\n\n'
      printf -- '- QA Pass 1 report (pasted verbatim):\n\n'
      printf '| # | Criterion | Verdict | Evidence |\n'
      printf '|---|-----------|---------|----------|\n'
      printf '| 1 | the thing works | PASS | bats 76-80 ok |\n'
      printf '| 2 | the other thing | PARTIAL | no hardware here |\n\n'
      printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
    } > "$d/specs/0008-table.md"
    printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n| 0008 | Table | CLOSED |\n' > "$d/specs/STATUS.md"
    git -C "$d" add -A && git -C "$d" commit -qm "spec 0008"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0008" spec/0008-table
  fi
  if [[ "$mode" == "launder" ]]; then
    # Role-path code merged under a spec that was ALREADY CLOSED on the trunk
    # before this merge. Every spec the branch touches is compliant, so
    # dispositioning all of them is not enough on its own: the question is
    # whether this merge CLOSED anything, and it did not.
    git -C "$d" checkout -q -b spec/0005b-again
    printf 'laundered\n' >> "$d/src/f.js"
    printf '\nA one-line amendment.\n' >> "$d/specs/0005b-thing.md"
    git -C "$d" add -A && git -C "$d" commit -qm "amend 0005b and slip code in"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge spec 0005b again" spec/0005b-again
  fi
}
# >>> SHARD-BEGIN trunk-audit cost=6
if shard_region trunk-audit; then

# A PARENTLESS commit offered as the new trunk (F2 of the 2026-08-11 leg).
#
# The attack is `git checkout --orphan`, commit role-path code, then
# `git push --force <orphan>:refs/heads/main`. pre-push audits the oid that
# WOULD become the remote trunk with --until, which is why this fixture leaves
# the real trunk alone and returns the orphan's name: that is the shape the
# hook actually evaluates.
#
# The old walk asked `[[ -n "$P1" ]] && touches_role "$P1" "$C"`, so a commit
# with no first parent failed the guard and fell to the CLEAN arm having had
# its content read by nothing, and the whole trunk could be replaced at
# "0 violations", exit 0.
audit_orphan_fixture() { # audit_orphan_fixture <dir> <mode: code|docs>
  local d="$1" mode="$2"
  audit_fixture "$d" clean
  git -C "$d" checkout -q --orphan wholesale
  git -C "$d" rm -rq --cached . >/dev/null 2>&1
  ( cd "$d" && rm -rf src specs .claude seed.txt )
  if [[ "$mode" == "code" ]]; then
    mkdir -p "$d/src"
    printf 'unreviewed feature\n' > "$d/src/evil.js"
  else
    mkdir -p "$d/docs"
    printf 'just docs\n' > "$d/docs/notes.md"
  fi
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "wholesale replacement" >/dev/null 2>&1
  git -C "$d" checkout -q -f main >/dev/null 2>&1
}

# THE OTHER DIRECTION, and the one a careless fix breaks: every repository's
# ROOT commit is parentless and entirely legitimate. Here the root carries
# feature code AND the stamp, so it is both parentless and role-touching, which
# is exactly the shape the orphan attack has. What separates them is identity,
# not shape: the root is an ancestor of the rule baseline and the injected
# orphan shares no history with it at all.
audit_rootcode_fixture() { # audit_rootcode_fixture <dir>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git -C "$d" init -q
  git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email "tests@example.invalid"
  git -C "$d" config user.name "Setlist Tests"
  git -C "$d" config commit.gpgsign false
  sdd_json "$d"
  printf 'feature\n' > "$d/src/f.js"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A
  git -C "$d" commit -qm "root commit: feature code and the stamp together"
  git -C "$d" checkout -q -b spec/0005b-thing
  printf 'more\n' >> "$d/src/f.js"
  {
    printf '# Spec 0005b\n\nStatus: CLOSED\n\n## Closing report\n\n'
    printf -- '- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- QA Pass 1 report (pasted verbatim):\n\ncriterion 1: PASS\n\n'
    printf -- '- QA Pass 2 (human): done\n- Architecture diagram: no impact\n'
  } > "$d/specs/0005b-thing.md"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n| 0005b | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A && git -C "$d" commit -qm "spec 0005b"
  git -C "$d" checkout -q main
  git -C "$d" merge -q --no-ff -m "Merge spec 0005b" spec/0005b-thing
}

AUD="$WORK/audit-clean"; audit_fixture "$AUD" clean
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit a: a compliant trunk reports zero violations" 0 "0 violations"
expect_script "trunk audit b: a suffixed spec number (0005b) is recognised, not flagged" 0 "0 violations"
# A RECORDED chore merge is CLEAN, not merely unverifiable. The old expectation
# here was that it landed in the "unverifiable" bucket, which is the bucket F2/F7
# showed was excusing hook-skipping merges at exit 0. A chore that records its
# completion is distinguishable from an unspecced feature, which is the whole
# point of the archive line; the unrecorded case is asserted as a VIOLATION by
# "audit age a" further down, and the pre-adoption exemption by "audit age b".
expect_script "trunk audit c: a chore merge that records its completion is clean, not a violation" 0 "0 violations"

AUD="$WORK/audit-direct"; audit_fixture "$AUD" direct
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit d: feature code committed straight to the trunk is a violation" 1 \
  "feature code committed directly" "1 violations"

AUD="$WORK/audit-unclosed"; audit_fixture "$AUD" unclosed
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit e: a merge whose spec has no CLOSED row is a violation" 1 "no-CLOSED-row"

# F2, 2026-08-11 leg. Both directions, and the second one is the trap: the fix
# must separate an INJECTED parentless commit from a repository's own ROOT
# commit, which is parentless too and completely ordinary.
AUD="$WORK/audit-orphan-code"; audit_orphan_fixture "$AUD" code
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --until wholesale
expect_script "audit orphan a: a parentless commit carrying role code is a violation, not clean" 1 \
  "parentless" "1 violations"

# The false-positive direction of the same fix: it must judge the CONTENT of a
# parentless commit, not refuse the shape outright.
AUD="$WORK/audit-orphan-docs"; audit_orphan_fixture "$AUD" docs
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --until wholesale
expect_script "audit orphan b: a parentless commit touching no role path is not flagged" 0 "0 violations"

# THE ROOT-COMMIT CONTROL. Parentless and role-touching, exactly like the
# attack, and it must still audit clean.
AUD="$WORK/audit-rootcode"; audit_rootcode_fixture "$AUD"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "audit root a: a repository whose ROOT commit carries feature code still audits clean" 0 \
  "0 violations"

# THE TRUNK SPELLING, in the BACKSTOP. The v1.7 gate found the same root cause
# here as in slh_trunk, in a different file, so fixing the library does not touch
# this: trunk-audit.sh audited whatever ref .trunk NAMED, and a remote-tracking
# spelling made it walk the REMOTE's history instead of the local trunk being
# pushed. `rev-parse --verify` does not catch it, because a remote-tracking ref
# resolves perfectly well. The violating merge simply was not in the audited
# range, so the audit reported "1 clean, 0 violations", exit 0, and pre-push
# allowed the push. README:176 sells this script as the layer that "reads what
# ended up in your history and does not care how the command was spelled".
#
# Same bytes, same history, only the SPELLING of the trunk differs from case e.
for ta_tv in refs/remotes/origin/main origin/main refs/heads/main heads/main; do
  AUD="$WORK/audit-spell"; audit_fixture "$AUD" unclosed
  # origin/main deliberately sits BEHIND local main, at the stamp commit, which
  # is the ordinary state of a repo with unpushed work and the state in which the
  # defect reports a clean sheet rather than "nothing was audited".
  git -C "$AUD" update-ref refs/remotes/origin/main \
    "$(git -C "$AUD" log --format=%H --diff-filter=A -- .claude/sdd.json | tail -n1)" 2>/dev/null || true
  ta_tmp="$(jq --arg t "$ta_tv" '.trunk = $t' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit f: trunk spelled [$ta_tv] still audits the LOCAL trunk" 1 "no-CLOSED-row"
done

# And the refusal direction, in the two shapes it actually comes in. They take
# DIFFERENT paths through the script and the first draft of this block tested the
# wrong one twice: a value that does not resolve at all is caught by the older
# rev-parse check and never reaches the reduction, so asserting it proves nothing
# about the reduction.
#
# g1: resolves, but names no local branch and tracks none. A TAG is the honest
# case here, and it is the only one that reaches the new show-ref refusal.
AUD="$WORK/audit-tagtrunk"; audit_fixture "$AUD" unclosed
git -C "$AUD" tag audit-tag-trunk main 2>/dev/null || true
ta_tmp="$(jq '.trunk = "audit-tag-trunk"' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit g1: a trunk that RESOLVES but is not a local branch is refused" 2 "not a local branch"

# g2: does not resolve at all. Older path, asserted so it stays refused.
AUD="$WORK/audit-nobranch"; audit_fixture "$AUD" unclosed
ta_tmp="$(jq '.trunk = "no-such-branch"' "$AUD/.claude/sdd.json")" && printf '%s\n' "$ta_tmp" > "$AUD/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit g2: a trunk that does not resolve at all is refused" 2 "does not resolve"

# B6 (leg 5, F15/F29). The backstop was satisfied by ordinary prose and read
# only the FIRST spec file a branch touched. Both halves are fixed here, ahead
# of item 28 Stage B promoting this script to Part 6 enforcement: promoting a
# backstop that prose satisfies converts an honest "opt-in" into a false
# "enforced", which is worse than the opt-in it replaces.
AUD="$WORK/audit-prose"; audit_fixture "$AUD" prose
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6a: a QA block of prose containing the word PASS is not a verdict" 1 "no-qa-verdict"

# A FRESHLY STAMPED INSTANCE MUST BE PUSHABLE (v1.7 gate session 4, leg F2).
#
# It was not. The audit exits 2 on "nothing was audited", which pre-push correctly
# reports as a refusal, so the stamp handed the user a repository configured to
# reject every push before they had written anything. "Nothing to audit" is not an
# error when the baseline IS the trunk tip: it is a clean trunk with no work on it
# yet. It stays an error when the range is malformed, because an audit that walks
# the wrong range and reports clean is the fail-open this script exists to avoid.
AUD="$WORK/audit-fresh"; rm -rf "$AUD"; mkdir -p "$AUD"; git_init "$AUD"; sdd_json "$AUD"
git -C "$AUD" add .claude/sdd.json >/dev/null 2>&1
git -C "$AUD" commit -qm "stamp" >/dev/null 2>&1
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit h1: a freshly stamped instance with no work yet is CLEAN" 0 "audited 0"

# The other direction, so h1 cannot be satisfied by simply making the script
# permissive. Once "nothing to audit" becomes a clean answer, an UNRESOLVABLE
# baseline must not quietly borrow it: that would turn a typo into a clean sheet,
# which is the exact fail-open this script exists to avoid. The first draft of
# this case used an orphan commit as --since, which does NOT produce an empty
# range (it lists the whole trunk), so it tested nothing about the empty path.
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD" --since no-such-baseline-ref
expect_script "trunk audit h2: an UNRESOLVABLE --since is an error, not a clean sheet" 2 "does not resolve"

AUD="$WORK/audit-fenced"; audit_fixture "$AUD" fencedclose
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit F9: a Closing report that exists only inside a fence is a violation" 1 "spec 0008"

AUD="$WORK/audit-secondspec"; audit_fixture "$AUD" secondspec
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6b: EVERY spec a branch touches is dispositioned, not just the first" 1 "spec 0007"

# Item 35 on the backstop: a table-cell verdict is a verdict here too. Paired
# with B6a above, which keeps prose refused, these two are the lockstep's two
# directions expressed against the audit rather than against the gate.
AUD="$WORK/audit-tablecell"; audit_fixture "$AUD" tablecell
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit item 35: a table-cell QA verdict is accepted, not reported as no-qa-verdict" 0 "0 violations"

fi; shard_region_end
# <<< SHARD-END trunk-audit
# --- F1 of the 2.2.0 leg: git QUOTES paths, and the role test read the quotes ---
# >>> SHARD-BEGIN role-path-quoting cost=10
if shard_region role-path-quoting; then
#
# THE BLOCKER. `git diff --name-only` and `git ls-tree --name-only` emit a path
# containing a non-ASCII byte, a double quote, a backslash or a control
# character as a QUOTED C string: "src/caf\303\251.js", quotes and octal escapes
# included. touches_role fed that 15-byte string to touches_role_file, whose
# `case "$f" in "$r"/*)` cannot match `src/`, so the file was invisible to the
# role test and unreviewed feature code landed on the trunk at exit 0 with the
# push allowed. The trunk audit IS the guarantee, so this sat above MAJOR.
#
# WHY -z AND NOT core.quotePath=false. Measured before the fix was written:
# flipping core.quotePath restores the NON-ASCII case only. A double quote, a
# backslash and a control character are quoted UNCONDITIONALLY at any setting.
# `-z` emits paths NUL-delimited and unquoted, which is the only spelling that
# covers all four classes, so every case below is run with quotePath BOTH ways
# and must give the same answer.
#
# The ASCII control runs FIRST in each pair. Four cases that all expect "1
# violations" prove nothing if the fixture builder silently produced no commit.
for TA_QP in true false; do
  AUD="$WORK/audit-qp-ascii-$TA_QP"; audit_fixture "$AUD" plainrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 control [quotePath=$TA_QP]: an ASCII role path committed direct to the trunk IS a violation" 1 "1 violations"

  AUD="$WORK/audit-qp-utf8-$TA_QP"; audit_fixture "$AUD" utf8role
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a NON-ASCII role path is seen by the role test" 1 "1 violations"

  AUD="$WORK/audit-qp-bslash-$TA_QP"; audit_fixture "$AUD" bslashrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a BACKSLASH role path is seen (quoted at any setting)" 1 "1 violations"

  AUD="$WORK/audit-qp-quote-$TA_QP"; audit_fixture "$AUD" quoterole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a DOUBLE-QUOTE role path is seen (quoted at any setting)" 1 "1 violations"

  AUD="$WORK/audit-qp-tab-$TA_QP"; audit_fixture "$AUD" tabrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a TAB role path is seen (quoted at any setting)" 1 "1 violations"
done

AUD="$WORK/audit-launder"; audit_fixture "$AUD" launder
run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
expect_script "trunk audit B6c: code merged under an already-CLOSED spec closes nothing and is a violation" 1 "closes-no-spec"

fi; shard_region_end
# <<< SHARD-END role-path-quoting
# =============================================================================
# GENERATOR 6: DEGRADED ENVIRONMENT (1.0.5)
#
# The gates are only ever exercised against a healthy repo in the cases above.
# Real repos are detached, unborn, half-configured, and reformatted by the
# harness itself. Every one of these is an input the gates must survive, and
# the question for each is the one from Phase 4: when the check cannot
# evaluate its predicate, does it deny or does it fall through?
# =============================================================================

DEG="$WORK/degraded"
close_fixture "$DEG" no no answered no no true

# DETACHED HEAD. `branch --show-current` returns empty, so no gate can tell
# whether it is on the trunk. Documented as a sideways route; asserted here so
# the day it closes we find out.
DEG_HEAD="$(git -C "$DEG" rev-parse main)"
git -C "$DEG" checkout -q --detach "$DEG_HEAD"
run_hook "$HOOKS/close-gate.sh" "$DEG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "degraded a: on a detached HEAD the close gate passes (documented sideways route)"
run_hook "$HOOKS/scope-hook.sh" "$DEG" "$(jq -nc --arg p "$DEG/src/x.js" '{tool_name:"Edit", tool_input:{file_path:$p}}')"
expect_allow "degraded b: on a detached HEAD the scope hook passes (same route)"
git -C "$DEG" checkout -q main

# UNPARSEABLE sdd.json. jq is present, the file is not readable as JSON. The
# hooks read the trunk and role paths from it; with neither, they cannot tell
# a trunk write from a branch write.
DEG2="$WORK/degraded-badjson"
close_fixture "$DEG2" no no answered no no true
printf '{ "trunk": \n' > "$DEG2/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$DEG2" "$(jq -nc --arg p "$DEG2/src/x.js" '{tool_name:"Write", tool_input:{file_path:$p}}')"
expect_deny "degraded c: an unparseable sdd.json denies the write rather than guessing" "scope hook"
run_hook "$HOOKS/close-gate.sh" "$DEG2" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "degraded d: an unparseable sdd.json denies the merge rather than guessing" "close gate"

# MINIFIED sdd.json. Claude Code rewrites config files, and the 1.0.3 wiring
# check was defeated by exactly this. The hooks read sdd.json with jq, which
# is format-blind, so this must behave identically to the pretty form.
DEG3="$WORK/degraded-minified"
close_fixture "$DEG3" no no answered no no true
jq -c . "$DEG3/.claude/sdd.json" > "$DEG3/t" && mv "$DEG3/t" "$DEG3/.claude/sdd.json"
assert_true "degraded e0: the fixture really is minified" \
  "the fixture is not one line, so case e proves nothing" \
  test "$(wc -l < "$DEG3/.claude/sdd.json")" -le 1
run_hook "$HOOKS/close-gate.sh" "$DEG3" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "degraded e: a minified sdd.json is read identically to a pretty one" "Closing report"

# EMPTY role paths. A config that parses but records nothing usable.
DEG4="$WORK/degraded-noroles"
close_fixture "$DEG4" no no answered no no true
jq '.roles = {}' "$DEG4/.claude/sdd.json" > "$DEG4/t" && mv "$DEG4/t" "$DEG4/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$DEG4" "$(jq -nc --arg p "$DEG4/src/x.js" '{tool_name:"Write", tool_input:{file_path:$p}}')"
expect_deny "degraded f: absent role paths fall back to src/tests rather than allowing everything" "never lands"

# =============================================================================
# GENERATOR 7: FOREIGN MATERIAL (1.0.5)
#
# A checker must judge what it owns and ignore what it does not. The 1.0.3
# wiring check failed this in both directions at once. These put material the
# gates do NOT own next to material they do.
# =============================================================================

FOR1="$WORK/foreign"
close_fixture "$FOR1" yes yes answered yes no true
# A file that LOOKS like a spec but is not in specs/, beside the real one.
mkdir -p "$FOR1/vendor/specs"
printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$FOR1/vendor/specs/0001-decoy.md"
git -C "$FOR1" add -A && git -C "$FOR1" commit -qm "vendored decoy that mimics a spec"
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "foreign a: a decoy spec outside specs/ does not confuse the close gate"

# A branch whose NAME contains a spec-like string but is not a spec branch.
git -C "$FOR1" branch -f feature/not-spec/0002-x main
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/not-spec/0002-x')"
expect_allow "foreign b: a branch whose name merely contains a spec-like path is not gated as a close"

# THE REF-NAMESPACE ANCHOR (2.4.0 leg F2): a ref the instance does not govern,
# whose name merely CONTAINS /spec/, must not hijack the classification of an
# ordinary feature merge. Both leg spellings: a remote NAMED spec, and a
# nesting namespace in front of spec/.
git -C "$FOR1" branch -f feature/iso main
git -C "$FOR1" update-ref refs/remotes/spec/main feature/iso
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/iso')"
expect_allow "foreign b2 (2.4.0 leg F2): a remote NAMED spec does not turn a feature merge into an unclosed close"
git -C "$FOR1" update-ref -d refs/remotes/spec/main
git -C "$FOR1" branch -f archive/spec/0099-old feature/iso
run_hook "$HOOKS/close-gate.sh" "$FOR1" "$(bash_payload 'git merge --no-ff feature/iso')"
expect_allow "foreign b3 (2.4.0 leg F2): a nesting namespace in front of spec/ is not the governed namespace"
git -C "$FOR1" branch -D archive/spec/0099-old >/dev/null 2>&1
# The direction that must NOT loosen, the remote-tracking copy of a GOVERNED
# spec branch staying governed, is already pinned by the ref-identity corpus
# below (remote-tracking spellings deny), which the 2.4.0 leg re-verified live.

# THE IDENTITY-BY-COMMIT BOUNDARY (2.4.0 leg F9, documented): an alias is
# governed only while a spec or chore ref still points at that exact commit.
# Both spellings pinned as the documented Known-limitations bullet says, so
# the delisting cannot silently return. The guarantee layers refuse these
# merges (leg-verified by execution); what these pins record is the session
# gate's classification boundary, on fresh copies so FOR1 stays untouched.
FOR3="$WORK/foreign-alias-adv"
rm -rf "$FOR3"; cp -R "$FOR1" "$FOR3"
git -C "$FOR3" branch -f tmp/alias spec/0001-thing
git -C "$FOR3" checkout -q spec/0001-thing 2>/dev/null
printf 'more\n' >> "$FOR3/src/app.js" 2>/dev/null || printf 'more\n' > "$FOR3/src/later.txt"
git -C "$FOR3" add -A >/dev/null 2>&1
git -C "$FOR3" -c core.hooksPath=/dev/null commit -qm "branch advances past the alias" >/dev/null 2>&1
git -C "$FOR3" checkout -q main 2>/dev/null
run_hook "$HOOKS/close-gate.sh" "$FOR3" "$(bash_payload 'git merge --no-ff tmp/alias')"
expect_allow "alias a (2.4.0 leg F9, documented boundary): an alias the spec branch advanced past classifies as an ungoverned sync at the session layer"
FOR4="$WORK/foreign-alias-del"
rm -rf "$FOR4"; cp -R "$FOR1" "$FOR4"
git -C "$FOR4" branch -f tmp/alias spec/0001-thing
git -C "$FOR4" branch -D spec/0001-thing >/dev/null 2>&1
run_hook "$HOOKS/close-gate.sh" "$FOR4" "$(bash_payload 'git merge --no-ff tmp/alias')"
expect_allow "alias b (2.4.0 leg F9, documented boundary): an alias that outlives the deleted spec branch classifies as an ungoverned sync at the session layer"

# Foreign paths in the staged diff beside owned ones: the scan judges content,
# and this pins that it does not judge ownership (a documented limitation).
FOR2="$WORK/foreign-staged"
git_init "$FOR2"; sdd_json "$FOR2"
mkdir -p "$FOR2/node_modules/pkg"
printf 'const a = 1;\n' > "$FOR2/node_modules/pkg/index.js"
printf 'ours\n' > "$FOR2/ours.md"
git -C "$FOR2" add -A
run_hook "$HOOKS/commit-gate.sh" "$FOR2" "$(bash_payload 'git commit -m "add dependency"')"
expect_allow "foreign c: clean vendored content beside our own passes the content scans"

# =============================================================================
# GENERATOR 5: EQUIVALENT OPERATIONS (1.0.5)
#
# Every sibling command that achieves the governed effect is either gated, or
# named in Known limitations AND asserted here so its closure is detected.
# The close-gate siblings are asserted in the documented-hole block above;
# these are the COMMIT-gate siblings, which create or stage content without
# the word "commit" ever appearing at command position.
# =============================================================================

EQ="$WORK/equivalent"
git_init "$EQ"; sdd_json "$EQ"
printf 'x\n' > "$EQ/a.md"; git -C "$EQ" add -A; git -C "$EQ" commit -qm base
for sib in 'git revert --no-edit HEAD' 'git stash pop' 'git apply /tmp/p.patch' 'git cherry-pick --no-commit HEAD' 'git commit --amend --no-edit'; do
  run_hook "$HOOKS/commit-gate.sh" "$EQ" "$(bash_payload "$sib")"
  case "$sib" in
    *--amend*) expect_allow "equivalent: [$sib] reaches the content scans (clean here)" ;;
    *) expect_allow "equivalent: [$sib] bypasses the content scans (documented gap, item 30)" ;;
  esac
done

