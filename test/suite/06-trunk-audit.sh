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
# THE DECLARED BASELINE (spec 0157, 0156 section 1). An instance whose
# .claude/sdd.json was committed long before its .githooks/ arrived: every merge
# between the two was made when no pre-merge-commit existed to write the
# completion the audit asks for, so the default baseline refuses the push
# forever and the sentence it prints ("made after this instance adopted the
# rules") is false about every one of them. Measured on the owner's own instance
# at 33 violations before the fix and 0 at the hook boundary.
baseline_fixture() { # baseline_fixture <dir> <mode: bare|after-clean|after-dirty>
  local d="$1" mode="${2:-bare}" i
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git_init "$d"
  sdd_json "$d"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "stamp"
  # three merges of role-path work with no completion, the pre-rule era
  for i in 1 2 3; do
    git -C "$d" checkout -q -b "work/$i"
    printf 'feature %s\n' "$i" >> "$d/src/f.js"
    git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "work $i"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge work/$i" "work/$i"
  done
  # the boundary arrives: this commit is what the refresh records as the baseline
  mkdir -p "$d/.githooks"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.githooks/pre-push"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.githooks/setlist-hook-lib.sh"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "deliver the git-hooks boundary"
  case "$mode" in
    after-clean|after-dirty)
      git -C "$d" checkout -q -b chore/after
      printf 'tidy\n' >> "$d/src/f.js"
      [[ "$mode" == "after-clean" ]] \
        && printf -- '- CHORE-001: DONE 2026-09-22. tidy after the boundary\n' >> "$d/specs/STATUS.md"
      git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "chore work after the boundary"
      git -C "$d" checkout -q main
      git -C "$d" merge -q --no-ff -m "Merge chore/after" chore/after
      ;;
  esac
}

# The key as a person or the refresh writes it: one value in .claude/sdd.json,
# never a ref, never a position (the `trunk` key's own rule, one file over).
baseline_key() { # baseline_key <dir> <value>
  local d="$1" v="$2"
  jq --arg b "$v" '.audit = ((.audit // {}) + {baseline: $b})' "$d/.claude/sdd.json" > "$d/.claude/sdd.json.new"
  mv "$d/.claude/sdd.json.new" "$d/.claude/sdd.json"
}
baseline_hook_commit() { # baseline_hook_commit <dir> -> the commit that ADDED .githooks/pre-push
  git -C "$1" log --root --diff-filter=A --format=%H -- .githooks/pre-push | tail -n1
}

# >>> SHARD-BEGIN trunk-audit cost=25
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

# --- THE DECLARED BASELINE (spec 0157) ---------------------------------------
#
# Every case below reads .audit.baseline out of the fixture's own sdd.json, the
# file the audit already takes its whole frame from. The key is read by BOTH
# baseline readers (the walk start and the pre-rule exemption) and by neither
# when --since is on the command line, which is what keeps the forge check,
# whose only caller passes --since, byte-for-byte unaffected.

# (a) THE DEFECT, and the fix, on one fixture.
BLD="$WORK/audit-baseline-default"; baseline_fixture "$BLD" bare
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLD"
expect_script "0157 baseline a1: with NO key the default still refuses the pre-boundary merges, unchanged" 1 \
  "3 violations" "made after this instance adopted the rules"
case "$SCRIPT_OUT" in
  *"(default)"*) ok "0157 baseline a2: the report header says the frame is the DEFAULT one" ;;
  *) bad "0157 baseline a2: the report header says the frame is the DEFAULT one" "no (default) in the since: line: ${SCRIPT_OUT:-<empty>}" ;;
esac

BL_HOOK="$(baseline_hook_commit "$BLD")"
baseline_key "$BLD" "$BL_HOOK"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLD"
expect_script "0157 baseline a3: with the key at the hook boundary the same instance reads CLEAN" 0 \
  "0 violations" "(declared)"
case "$SCRIPT_OUT" in
  *"Merge work/"*) bad "0157 baseline a4: nothing before the declared baseline is walked" "a pre-baseline merge was reported: ${SCRIPT_OUT:-<empty>}" ;;
  *) ok "0157 baseline a4: nothing before the declared baseline is walked, so the false sentence cannot be printed about it" ;;
esac

# (a) BOTH READERS ON ONE VALUE. A merge made AFTER the declared baseline gets
# no pre-rule exemption: if the exemption's baseline were later than the walk
# start, this merge would be excused and the report would read clean.
BLA="$WORK/audit-baseline-after-dirty"; baseline_fixture "$BLA" after-dirty
baseline_key "$BLA" "$(baseline_hook_commit "$BLA")"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLA"
expect_script "0157 baseline a5: a merge with no completion made AFTER the declared baseline is still a violation" 1 \
  "1 violation" "Merge chore/after"
BLC="$WORK/audit-baseline-after-clean"; baseline_fixture "$BLC" after-clean
baseline_key "$BLC" "$(baseline_hook_commit "$BLC")"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLC"
expect_script "0157 baseline a6: a merge that RECORDS its completion after the baseline is clean" 0 "0 violations"

# (b) THE THREE REFUSALS, each drawn by its input: exit 2, the code in the
# message, and nothing walked. A baseline that cannot be used is never a clean
# sheet, the same rule --since has carried since the empty range became clean.
baseline_refused() { # baseline_refused <name> <dir> <code>
  local name="$1" d="$2" code="$3"
  if [[ "$SCRIPT_RC" -ne 2 ]]; then
    bad "$name" "expected rc 2, got $SCRIPT_RC: ${SCRIPT_OUT:-<empty>}"; return
  fi
  case "$SCRIPT_OUT" in *"$code"*) ;; *) bad "$name" "no $code in: ${SCRIPT_OUT:-<empty>}"; return ;; esac
  # Nothing walked: the refusal happens before the report header, so neither the
  # header's trunk line nor a walk tally nor a finding can be in the output.
  case "$SCRIPT_OUT" in
    *"commits on"*|*"VIOLATION"*|*"  trunk: "*) bad "$name" "something was walked before the refusal: ${SCRIPT_OUT:-<empty>}"; return ;;
  esac
  case "$SCRIPT_OUT" in
    *SETLIST_SKIP*) bad "$name" "the refusal offers a bypass: ${SCRIPT_OUT:-<empty>}"; return ;;
  esac
  ok "$name"
}
BLR="$WORK/audit-baseline-refusals"; baseline_fixture "$BLR" bare
BLR_HOOK="$(baseline_hook_commit "$BLR")"
baseline_key "$BLR" "main"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b1: a REF name as the baseline is refused by name" "$BLR" "[SLH-BASELINE-MALFORMED]"
baseline_key "$BLR" "${BLR_HOOK:0:12}"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b2: an ABBREVIATED commit id is refused, because the key is an identity" "$BLR" "[SLH-BASELINE-MALFORMED]"
baseline_key "$BLR" "$(printf '%s' "$BLR_HOOK" | tr 'a-f' 'A-F')"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b3: an uppercase-hex spelling is refused rather than silently accepted" "$BLR" "[SLH-BASELINE-MALFORMED]"
baseline_key "$BLR" "0000000000000000000000000000000000000000"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b4: a well-formed id that names no commit here is refused" "$BLR" "[SLH-BASELINE-UNRESOLVED]"
git -C "$BLR" checkout -q -b sideways
printf 'elsewhere\n' >> "$BLR/src/f.js"
git -C "$BLR" add -A >/dev/null 2>&1 && git -C "$BLR" commit -qm "a commit on another branch"
BLR_SIDE="$(git -C "$BLR" rev-parse HEAD)"
git -C "$BLR" checkout -q main
baseline_key "$BLR" "$BLR_SIDE"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b5: a baseline that is not an ancestor of the audited tip is refused, not walked from" "$BLR" "[SLH-BASELINE-NOT-ANCESTOR]"
baseline_key "$BLR" "$(git -C "$BLR" rev-parse main)"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
expect_script "0157 baseline b6: a baseline equal to the tip is an EMPTY walk and reports clean, a declaration and not a refusal" 0 "audited 0"
jq '.audit = "yes"' "$BLR/.claude/sdd.json" > "$BLR/.claude/sdd.json.new" && mv "$BLR/.claude/sdd.json.new" "$BLR/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLR"
baseline_refused "0157 baseline b7: an \"audit\" value that is not an object is refused rather than read as absent" "$BLR" "[SLH-BASELINE-MALFORMED]"

# (c) --SINCE ON THE COMMAND LINE WINS, and the key is not read at all: this is
# what makes scripts/forge-check.sh, whose every call passes --since, unaffected
# by the key, and what stops a pull request that moves the key in its own
# checkout moving the forge's exemption with it.
BLS="$WORK/audit-baseline-since"; baseline_fixture "$BLS" bare
BLS_HOOK="$(baseline_hook_commit "$BLS")"
baseline_key "$BLS" "main"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLS" --since "$BLS_HOOK"
expect_script "0157 baseline c1: --since overrides a present key, malformed or not, and the key is never read" 0 "0 violations"
case "$SCRIPT_OUT" in
  *SLH-BASELINE*|*"(declared)"*|*"(default)"*)
    bad "0157 baseline c2: under --since the header keeps today's bytes and no key is read" "the run mentioned the key: ${SCRIPT_OUT:-<empty>}" ;;
  *) ok "0157 baseline c2: under --since the header keeps today's bytes and no key is read" ;;
esac
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLS" --since="$BLS_HOOK"
expect_script "0157 baseline c3: the --since=<ref> spelling overrides the key too" 0 "0 violations"

# (d) THE ORPHAN, with a key: the force-pushed orphan tip does not descend from
# the declared baseline, so the audit refuses to run rather than walking a tip
# under a frame nobody declared. Still refused at push, by the fail-CLOSED arm.
BLO="$WORK/audit-baseline-orphan"; audit_orphan_fixture "$BLO" code
baseline_key "$BLO" "$(git -C "$BLO" log --root --diff-filter=A --format=%H -- .claude/sdd.json | tail -n1)"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLO" --until wholesale
baseline_refused "0157 baseline d1: an orphan tip audited under a declared baseline is refused, never reported clean" "$BLO" "[SLH-BASELINE-NOT-ANCESTOR]"


# (e) THE CHECKERS SAY THE SAME THING AS THE MECHANISM. /setlist:validate is
# prose a session executes, so what the suite can hold is that the step names
# both directions of the key and stays REPORT-ONLY, and that the upgrade skill
# tells an instance with pre-boundary history what changed for it. A checker
# that knows only the present direction leaves the refused instance, which is
# the one the key exists for, with nothing said about it.
BL_VS="$ROOT/skills/validate/SKILL.md"
if grep -q 'audit.baseline' "$BL_VS" \
   && awk '/^18\./{f=1} /^19\./{f=0} f' "$BL_VS" | grep -q 'audit.baseline'; then
  ok "0157 validate e1: step 18 carries the baseline part, beside the three that were already there"
else
  bad "0157 validate e1: step 18 carries the baseline part, beside the three that were already there" \
      "the git-hook boundary step says nothing about audit.baseline, so the health check cannot see the instance the key exists for"
fi
BL_S18="$(awk '/^18\./{f=1} /^19\./{f=0} f' "$BL_VS")"
# The accepted values moved with the writer (spec 0164, fix round 2, F12): the
# refresh writes the commit that added .githooks/pre-push, or the trunk tip when
# it is delivering the boundary now. Spec 0167 moved the predicate: the key must
# be an ANCESTOR of the trunk, framed at the first first-parent commit that
# contains it, and step 18 reaches that answer through the refresh's report
# mode rather than re-deriving it (e5 below). Step 18 names what the refresh can
# write, not a third value.
if printf '%s' "$BL_S18" | grep -q 'an ancestor of the recorded trunk' \
   && printf '%s' "$BL_S18" | grep -q 'tip' \
   && printf '%s' "$BL_S18" | grep -qi 'absent' \
   && printf '%s' "$BL_S18" | grep -q 'FINDING'; then
  ok "0157 validate e2: both directions are named, the accepted values and the absent-key finding"
else
  bad "0157 validate e2: both directions are named, the accepted values and the absent-key finding" \
      "one direction is missing from step 18, so half the instances it is for read as clean"
fi
if printf '%s' "$BL_S18" | grep -qi 'report-only\|REPORT-ONLY\|leave it alone'; then
  ok "0157 validate e3: the baseline part reports and fixes nothing, like the rest of the step"
else
  bad "0157 validate e3: the baseline part reports and fixes nothing, like the rest of the step" \
      "nothing in the step says the check is report-only, and a health check that edits sdd.json is not one"
fi
# e5 (spec 0167, ruling E-b): step 18 asks through the ONE function by running
# the refresh in report mode, and says so; a step that re-derived the answer in
# prose is how its accepted values went stale in 0164 and again here.
if printf '%s' "$BL_S18" | grep -q 'refresh-instance.sh' \
   && printf '%s' "$BL_S18" | grep -q 'slh_baseline_frame' \
   && printf '%s' "$BL_S18" | grep -q 'REPORT'; then
  ok "0167 validate e5: step 18 reads the baseline through the refresh's report mode, the audit's own function"
else
  bad "0167 validate e5: step 18 reads the baseline through the refresh's report mode, the audit's own function" \
      "step 18 does not route the question through refresh-instance.sh and slh_baseline_frame"
fi
if grep -q 'audit.baseline' "$ROOT/skills/upgrade/SKILL.md"; then
  ok "0157 upgrade e4: the upgrade skill tells an instance with pre-boundary history what the migration commit records"
else
  bad "0157 upgrade e4: the upgrade skill tells an instance with pre-boundary history what the migration commit records" \
      "Part 8c's delta says nothing about the baseline, so the operator meets it only as a changed file"
fi


# --- THE BASELINE FRAME, COMPUTED (spec 0167, the 2.11.0 intake design 1) -----
#
# The 2.10.0 second leg's F1, F3, F4, F5 and F9 were ONE defect: the audit
# required audit.baseline on the trunk's first-parent line, the refresh wrote
# the commit that ADDED .githooks/pre-push, which sits on a side branch
# whenever the hooks arrived through a merge (the upgrade skill's chore branch
# under merge.ff=false makes that the ordinary shape), and the refresh's probe
# asked plain ancestry. Every push after such an upgrade was refused by name
# while the refresh reported the key healthy. Now the frame is COMPUTED: any
# ancestor of the tip is a valid declaration, and the walk starts at the OLDEST
# first-parent commit that contains it. The three readers (the audit, the
# refresh's probe, and validate step 18 through the refresh's report mode) take
# their verdict from one function, slh_baseline_frame, and the key corpus below
# compares them by bytes.
frame_fixture() { # frame_fixture <dir> : the hooks arrive on a MERGED chore branch
  local d="$1" i
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs"
  git_init "$d"; sdd_json "$d"
  printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "stamp"
  for i in 1 2; do
    git -C "$d" checkout -q -b "work/$i"
    printf 'feature %s\n' "$i" >> "$d/src/f.js"
    git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "work $i"
    git -C "$d" checkout -q main
    git -C "$d" merge -q --no-ff -m "Merge work/$i" "work/$i"
  done
  # the boundary arrives on a chore branch while the trunk moves on
  git -C "$d" checkout -q -b chore/hooks
  mkdir -p "$d/.githooks"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.githooks/pre-push"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.githooks/setlist-hook-lib.sh"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "deliver the git-hooks boundary"
  printf 'hooks readme\n' > "$d/.githooks/README"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "hooks readme"
  git -C "$d" checkout -q main
  printf 'notes\n' > "$d/NOTES.md"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "trunk moves meanwhile"
  git -C "$d" merge -q --no-ff -m "Merge chore/hooks" chore/hooks
  # a later trunk commit, so the tip is never the frame (E-a's guard)
  printf 'more notes\n' >> "$d/NOTES.md"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "later trunk commit"
  # a side branch never merged, and a commit sharing no history at all
  git -C "$d" checkout -q -b side/never "Merge chore/hooks^1" 2>/dev/null || git -C "$d" checkout -q -b side/never HEAD~2
  printf 'never\n' > "$d/NEVER.md"
  git -C "$d" add -A >/dev/null 2>&1 && git -C "$d" commit -qm "side commit never merged"
  git -C "$d" checkout -q main
}
frame_merge_of() { git -C "$1" log --first-parent --format=%H --grep='^Merge chore/hooks$' main | head -n1; }
frame_side_of() { git -C "$1" rev-parse side/never; }
frame_orphan_of() { # a commit that shares no history with the trunk
  git -C "$1" commit-tree "$(git -C "$1" mktree </dev/null)" -m orphan
}
frame_value() { # frame_value <dir> <json-value>
  local t; t="$(jq --argjson v "$2" '.audit = {baseline: $v}' "$1/.claude/sdd.json")" && printf '%s\n' "$t" > "$1/.claude/sdd.json"
}
frame_absent() { local t; t="$(jq 'del(.audit)' "$1/.claude/sdd.json")" && printf '%s\n' "$t" > "$1/.claude/sdd.json"; }

# The three readers, each normalised to one line: `absent`, `frame <short-id>`,
# or `refuse <CODE>`. A reader that cannot produce one of the three prints
# `unreadable`, which never equals a verdict, so a missing reader is red.
frame_norm_audit() { # the audit, run as pre-push runs it; its header names the frame
  local d="$1" out rc code sh
  out="$(bash "$SCRIPTS/trunk-audit.sh" "$d" 2>&1)"; rc=$?
  if [[ "$rc" -eq 2 ]]; then
    code="$(printf '%s\n' "$out" | grep -oE 'SLH-BASELINE-[A-Z-]+' | head -n1)"
    [[ -n "$code" ]] && { printf 'refuse %s\n' "$code"; return; }
    printf 'unreadable\n'; return
  fi
  case "$out" in *"(default)"*) printf 'absent\n'; return ;; esac
  sh="$(printf '%s\n' "$out" | sed -n 's/^  since: \([0-9a-f][0-9a-f]*\) .*/\1/p' | head -n1)"
  [[ -n "$sh" ]] && printf 'frame %s\n' "$sh" || printf 'unreadable\n'
}
frame_norm_refresh() { # the refresh in REPORT mode, which is validate step 18's route
  local d="$1" line code id
  line="$(bash "$SCRIPTS/refresh-instance.sh" "$d" 2>&1 | grep 'audit.baseline (the trunk audit' | head -n1)"
  code="$(printf '%s' "$line" | grep -oE 'SLH-BASELINE-[A-Z-]+' | head -n1)"
  if [[ -n "$code" ]]; then printf 'refuse %s\n' "$code"; return; fi
  case "$line" in *"would be recorded"*) printf 'absent\n'; return ;; esac
  id="$(printf '%s' "$line" | sed -n 's/.*the audit walks from \([0-9a-f]\{40\}\).*/\1/p')"
  [[ -n "$id" ]] && printf 'frame %s\n' "$(git -C "$d" rev-parse --short "$id")" || printf 'unreadable\n'
}
frame_norm_fn() { # frame_norm_fn <script> <dir> : the function as it stands in that file, called directly
  local f="$1" d="$2" body v
  body="$(awk '/^# --- THE BASELINE FRAME \(spec 0167\)/{p=1} p{print} /^# --- END THE BASELINE FRAME/{p=0}' "$f")"
  [[ -n "$body" ]] || { printf 'unreadable\n'; return; }
  v="$( eval "$body"; slh_baseline_frame "$d" "$d/.claude/sdd.json" main 2>/dev/null )"
  case "$v" in
    absent) printf 'absent\n' ;;
    "refuse "*) printf 'refuse %s\n' "$(printf '%s' "$v" | awk '{print $2}')" ;;
    "frame "*) printf 'frame %s\n' "$(git -C "$d" rev-parse --short "$(printf '%s' "$v" | awk '{print $2}')")" ;;
    *) printf 'unreadable\n' ;;
  esac
}

FRD="$WORK/audit-frame-merged"; frame_fixture "$FRD"
FR_ADDED="$(baseline_hook_commit "$FRD")"
FR_MERGE="$(frame_merge_of "$FRD")"
FR_MERGE_S="$(git -C "$FRD" rev-parse --short "$FR_MERGE")"

# (a) F1: the refresh's own choice on the merged-branch shape. Red on the
# folded bytes: [SLH-BASELINE-NOT-ANCESTOR] at exit 2, every push refused.
baseline_key "$FRD" "$FR_ADDED"
run_script bash "$SCRIPTS/trunk-audit.sh" "$FRD"
expect_script "0167 frame a1: the commit that added .githooks/pre-push on a MERGED branch is a valid baseline, framed at the merge" 0 \
  "0 violations" "since: $FR_MERGE_S" "declared $(git -C "$FRD" rev-parse --short "$FR_ADDED")"
case "$SCRIPT_OUT" in
  *"Merge work/"*) bad "0167 frame a2: nothing before the computed frame is walked" "a pre-frame merge was reported: ${SCRIPT_OUT:-<empty>}" ;;
  *) ok "0167 frame a2: nothing before the computed frame is walked" ;;
esac

# (a) BOTH READERS ON ONE VALUE, after the frame: a merge with no completion
# made after the hooks' merge is still a violation, so the pre-rule exemption
# begins at the frame and not later.
git -C "$FRD" checkout -q -b chore/later
printf 'later\n' >> "$FRD/src/f.js"
git -C "$FRD" add -A >/dev/null 2>&1 && git -C "$FRD" commit -qm "chore work after the frame"
git -C "$FRD" checkout -q main
git -C "$FRD" merge -q --no-ff -m "Merge chore/later" chore/later
run_script bash "$SCRIPTS/trunk-audit.sh" "$FRD"
expect_script "0167 frame a3: a merge with no completion after the computed frame is still a violation" 1 \
  "1 violation" "Merge chore/later"
git -C "$FRD" reset -q --hard HEAD~1

# (b) F9: a HAND-EDITED ancestor, both ways. A later commit on the merged
# chore branch is usable and framed at the same merge by BOTH readers; a
# commit on a branch never merged is refused by BOTH, with the same code.
# Red on the folded bytes: the refresh read "already recorded ..., left as
# declared" for the first while the audit refused it.
baseline_key "$FRD" "$(git -C "$FRD" rev-parse chore/hooks)"
FR_A="$(frame_norm_audit "$FRD")"; FR_R="$(frame_norm_refresh "$FRD")"
if [[ "$FR_A" == "frame $FR_MERGE_S" && "$FR_R" == "$FR_A" ]]; then
  ok "0167 frame b1: a hand-edited ancestor off the first-parent line: the refresh and the audit both frame it at the merge"
else
  bad "0167 frame b1: a hand-edited ancestor off the first-parent line: the refresh and the audit both frame it at the merge" \
      "audit '$FR_A', refresh '$FR_R', wanted 'frame $FR_MERGE_S' from both"
fi
baseline_key "$FRD" "$(frame_side_of "$FRD")"
FR_A="$(frame_norm_audit "$FRD")"; FR_R="$(frame_norm_refresh "$FRD")"
if [[ "$FR_A" == "refuse SLH-BASELINE-NOT-ANCESTOR" && "$FR_R" == "$FR_A" ]]; then
  ok "0167 frame b2: a hand-edited commit that is no ancestor: the refresh names the audit's own refusal"
else
  bad "0167 frame b2: a hand-edited commit that is no ancestor: the refresh names the audit's own refusal" \
      "audit '$FR_A', refresh '$FR_R', wanted 'refuse SLH-BASELINE-NOT-ANCESTOR' from both"
fi

# (c) F5: ONE FUNCTION. The refresh's probe asked `merge-base --is-ancestor`
# where the audit asked first-parent membership; now both files carry one
# definition, byte for byte, and the old probe is gone.
FR_FA="$(awk '/^# --- THE BASELINE FRAME \(spec 0167\)/{p=1} p{print} /^# --- END THE BASELINE FRAME/{p=0}' "$SCRIPTS/trunk-audit.sh")"
FR_FR="$(awk '/^# --- THE BASELINE FRAME \(spec 0167\)/{p=1} p{print} /^# --- END THE BASELINE FRAME/{p=0}' "$SCRIPTS/refresh-instance.sh")"
if [[ -n "$FR_FA" && "$FR_FA" == "$FR_FR" ]] && printf '%s' "$FR_FA" | grep -q '^slh_baseline_frame() {'; then
  ok "0167 frame c1: slh_baseline_frame is defined byte-identically in the audit and the refresh"
else
  bad "0167 frame c1: slh_baseline_frame is defined byte-identically in the audit and the refresh" \
      "the LOCKSTEP block is missing from one file or differs between them"
fi
if grep -q 'audit_baseline_usable' "$SCRIPTS/refresh-instance.sh"; then
  bad "0167 frame c2: the refresh's own weaker probe is gone" "audit_baseline_usable is still in refresh-instance.sh"
else
  ok "0167 frame c2: the refresh's own weaker probe is gone"
fi

# (d) THE KEY CORPUS (analysis A.3.2): every shape through all three readers,
# normalised, byte-identical, and each equal to the verdict the design says.
# The readers: the audit; the refresh's report mode (validate step 18's
# route); and the function as each file carries it, called directly.
FR_TIP="$(git -C "$FRD" rev-parse main)"
FR_LINEAR="$(git -C "$FRD" rev-parse "$FR_MERGE^1")"
FR_WANT=""; FR_GOT=""
for fr_shape in linear merged hand-edited non-ancestor side-branch false null abbreviation absent tip; do
  case "$fr_shape" in
    linear)       baseline_key "$FRD" "$FR_LINEAR";        fr_want="frame $(git -C "$FRD" rev-parse --short "$FR_LINEAR")" ;;
    merged)       baseline_key "$FRD" "$FR_ADDED";         fr_want="frame $FR_MERGE_S" ;;
    hand-edited)  baseline_key "$FRD" "$(git -C "$FRD" rev-parse chore/hooks)"; fr_want="frame $FR_MERGE_S" ;;
    non-ancestor) baseline_key "$FRD" "$(frame_orphan_of "$FRD")"; fr_want="refuse SLH-BASELINE-NOT-ANCESTOR" ;;
    side-branch)  baseline_key "$FRD" "$(frame_side_of "$FRD")";   fr_want="refuse SLH-BASELINE-NOT-ANCESTOR" ;;
    false)        frame_value "$FRD" false;                fr_want="refuse SLH-BASELINE-MALFORMED" ;;
    null)         frame_value "$FRD" null;                 fr_want="refuse SLH-BASELINE-MALFORMED" ;;
    abbreviation) baseline_key "$FRD" "${FR_ADDED:0:12}";  fr_want="refuse SLH-BASELINE-MALFORMED" ;;
    absent)       frame_absent "$FRD";                     fr_want="absent" ;;
    tip)          baseline_key "$FRD" "$FR_TIP";           fr_want="frame $(git -C "$FRD" rev-parse --short "$FR_TIP")" ;;
  esac
  FR_WANT="$FR_WANT$fr_shape $fr_want"$'\n'
  FR_GOT="$FR_GOT$fr_shape audit $(frame_norm_audit "$FRD") | refresh $(frame_norm_refresh "$FRD") | fn-audit $(frame_norm_fn "$SCRIPTS/trunk-audit.sh" "$FRD") | fn-refresh $(frame_norm_fn "$SCRIPTS/refresh-instance.sh" "$FRD")"$'\n'
done
FR_BAD=""
while IFS= read -r fr_line; do
  [[ -n "$fr_line" ]] || continue
  fr_shape="${fr_line%% *}"
  fr_want="$(printf '%s' "$FR_WANT" | sed -n "s/^$fr_shape //p")"
  fr_expect="$fr_shape audit $fr_want | refresh $fr_want | fn-audit $fr_want | fn-refresh $fr_want"
  [[ "$fr_line" == "$fr_expect" ]] || FR_BAD="$FR_BAD"$'\n'"  got:  $fr_line"$'\n'"  want: $fr_expect"
done <<< "$FR_GOT"
if [[ -z "$FR_BAD" ]]; then
  ok "0167 frame d1: the key corpus, ten shapes through the three readers, byte-identical and as designed"
else
  bad "0167 frame d1: the key corpus, ten shapes through the three readers, byte-identical and as designed" "$FR_BAD"
fi
# E-a's guard: for a declaration older than the tip the frame is NEVER the tip,
# which would walk nothing and attest every trunk clean.
baseline_key "$FRD" "$FR_ADDED"
if [[ "$(frame_norm_audit "$FRD")" == "frame $(git -C "$FRD" rev-parse --short "$FR_TIP")" ]]; then
  bad "0167 frame d2: the frame of an older declaration is never the tip" "the audit framed at the tip, so it walked nothing"
elif [[ "$(frame_norm_fn "$SCRIPTS/trunk-audit.sh" "$FRD")" == "frame $FR_MERGE_S" ]]; then
  ok "0167 frame d2: the frame of an older declaration is never the tip, it is the oldest first-parent commit containing it"
else
  bad "0167 frame d2: the frame of an older declaration is never the tip, it is the oldest first-parent commit containing it" \
      "the function read '$(frame_norm_fn "$SCRIPTS/trunk-audit.sh" "$FRD")', wanted 'frame $FR_MERGE_S'"
fi

fi; shard_region_end
# >>> SHARD-BEGIN trunk-audit-late-06 cost=3
# A prelude block moved into a measured region (spec 0168, item 2): independent both ways, measured.
if shard_region trunk-audit-late-06; then

# (h) UNRELATED HISTORIES ARE READ, NOT SKIPPED (spec 0164, fix round 2, F5 of
# the 2.10.0 leg). With no merge-base the discovery diffed against an empty
# string, which is a fatal argument error, so it read NOTHING and the arm that
# followed named the wrong defect: a merge carrying a spec and role-path files
# was reported as a chore-shaped merge with no completion record. Red watched
# on the pre-fix bytes: that wrong reason. The branch is diffed against the
# empty tree now, so its whole content is read.
BLU="$WORK/audit-unrelated"
rm -rf "$BLU"; mkdir -p "$BLU/src" "$BLU/specs"
git_init "$BLU"; sdd_json "$BLU"
printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$BLU/specs/STATUS.md"
git -C "$BLU" add -A >/dev/null 2>&1 && git -C "$BLU" commit -qm stamp >/dev/null 2>&1
git -C "$BLU" checkout -q --orphan imported
git -C "$BLU" rm -rq --cached . >/dev/null 2>&1
rm -rf "$BLU/src" "$BLU/specs" "$BLU/.claude"
mkdir -p "$BLU/src" "$BLU/specs"
printf 'code\n' > "$BLU/src/2.js"
printf '# Spec 0002 - imported\n\nStatus: ACTIVE\n\n## Closing report\n- pending\n' > "$BLU/specs/0002-imported.md"
git -C "$BLU" add -A >/dev/null 2>&1 && git -C "$BLU" commit -qm "imported subproject" >/dev/null 2>&1
git -C "$BLU" checkout -q main
git -C "$BLU" merge -q --no-ff --allow-unrelated-histories -m "merge imported" imported >/dev/null 2>&1
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLU"
expect_script "0164 unrelated h1: a merge of unrelated histories is read, and the spec it carries is named" 1 "spec 0002"
case "$SCRIPT_OUT" in
  *"no recorded completion"*) bad "0164 unrelated h2: the reason is the defect that is there, not a missing chore record" "$SCRIPT_OUT" ;;
  *) ok "0164 unrelated h2: the reason is the defect that is there, not a missing chore record" ;;
esac

# (i) A SHALLOW CLONE IS REFUSED BY NAME (spec 0164, fix round 2, F7). The walk
# reads history a --depth 1 clone does not have, so the audit reported "nothing
# to audit yet" at exit 0 over a violating trunk; the forge check has refused
# this since 2.6.0. Red watched on the pre-fix bytes: exit 0 with that line.
BLSH="$WORK/audit-shallow-src"; baseline_fixture "$BLSH" bare
rm -rf "$WORK/audit-shallow"
if git clone -q --depth 1 --no-local "file://$BLSH" "$WORK/audit-shallow" 2>/dev/null \
   && [[ "$(git -C "$WORK/audit-shallow" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  run_script bash "$SCRIPTS/trunk-audit.sh" "$WORK/audit-shallow"
  expect_script "0164 shallow i1: a shallow clone is refused by name, never reported clean" 2 "SLH-SHALLOW-CLONE"
else
  ok "0164 shallow i1: SKIPPED BY NAME, this host could not build a shallow clone of the fixture"
fi

# (g) A GLOB IN A ROLE VALUE IS REFUSED BY BOTH LAYERS (spec 0164, fix round 2,
# F3 of the 2.10.0 leg). The close verification expanded it against the working
# directory while this audit matched it literally, so `packages/*` made a merge
# the hooks refused audit clean at push, and `*` refused a docs-only merge.
# Red watched on the pre-fix bytes: "nothing to audit yet", exit 0.
BLG="$WORK/audit-roles-glob"; baseline_fixture "$BLG" bare
for blg_v in 'packages/*' 'src?' 'tests[0-9]'; do
  blg_tmp="$(jq --arg r "$blg_v" '.roles.src = $r' "$BLG/.claude/sdd.json")" \
    && printf '%s\n' "$blg_tmp" > "$BLG/.claude/sdd.json"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$BLG"
  expect_script "0164 roles g ($blg_v): a glob in a role path is refused by name, not matched literally" 2 "SLH-ROLES-SHAPE"
done
blg_tmp="$(jq '.roles.src = "src"' "$BLG/.claude/sdd.json")" && printf '%s\n' "$blg_tmp" > "$BLG/.claude/sdd.json"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLG"
case "$SCRIPT_RC" in
  2) bad "0164 roles g control: an ordinary role path still audits" "refused: ${SCRIPT_OUT:-<empty>}" ;;
  *) ok "0164 roles g control: an ordinary role path still audits" ;;
esac

# (e2) A PRESENT BASELINE THAT IS NOT A STRING IS MALFORMED (spec 0164, fix
# round 2, F21 of the 2.10.0 leg). `// empty` read JSON false and null as "no
# key", so those two were the one wrong type the audit accepted: it walked the
# default frame while the file declared another. Red watched on the pre-fix
# bytes: exit 1 over the default frame, no code printed.
BLN="$WORK/audit-baseline-nonstring"; baseline_fixture "$BLN" bare
for bln_v in false null 0 '[]'; do
  bln_tmp="$(jq --argjson v "$bln_v" '.audit = {baseline: $v}' "$BLN/.claude/sdd.json")" \
    && printf '%s\n' "$bln_tmp" > "$BLN/.claude/sdd.json"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$BLN"
  expect_script "0164 baseline e2 ($bln_v): a present baseline that is not a string is refused by name" 2 \
    "SLH-BASELINE-MALFORMED"
done

# (f) THE BASELINE MUST LIE ON THE TRUNK'S OWN LINE (spec 0164, fix round 2,
# F2 of the 2.10.0 leg). `merge-base --is-ancestor` says yes to a commit a
# merge brought in from a side branch, while the walk reads --first-parent, so
# such a key framed the audit by a commit the walk never passes and a
# chore-shaped merge with no completion record was excused as predating the
# rules. Red watched on the pre-fix bytes: "0 violations, 1 chore merges
# (unverifiable)" where the control read "1 violations".
BLS="$WORK/audit-baseline-sideline"
rm -rf "$BLS"; mkdir -p "$BLS/src" "$BLS/specs"
git_init "$BLS"; sdd_json "$BLS"
printf '| Num | Title | Status |\n| --- | --- | --- |\n' > "$BLS/specs/STATUS.md"
git -C "$BLS" add -A >/dev/null 2>&1 && git -C "$BLS" commit -qm "stamp" >/dev/null 2>&1
bls_stamp="$(git -C "$BLS" rev-parse HEAD)"
git -C "$BLS" checkout -q -b chore/early
printf 'feature\n' >> "$BLS/src/f.js"
git -C "$BLS" add -A >/dev/null 2>&1 && git -C "$BLS" commit -qm "chore work" >/dev/null 2>&1
git -C "$BLS" checkout -q main
git -C "$BLS" merge -q --no-ff -m "chore: merge chore/early" chore/early
git -C "$BLS" checkout -q -b side "$bls_stamp"
printf 'docs\n' > "$BLS/NOTES.md"
git -C "$BLS" add -A >/dev/null 2>&1 && git -C "$BLS" commit -qm "side docs" >/dev/null 2>&1
bls_side="$(git -C "$BLS" rev-parse HEAD)"
git -C "$BLS" checkout -q main
git -C "$BLS" merge -q --no-ff -m "merge side docs" side
# the control: with no key the merge is a violation
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLS"
expect_script "0164 baseline f1: with no key the chore-shaped merge is a violation (the control)" 1 "1 violations"
# the payload: a key on the side branch, reachable but not on the walk's line.
# FLIPPED BY SPEC 0167 (the frame computed). 0164 refused this key, and that
# refusal was the 2.10.0 second leg's F1: the refresh writes exactly such a
# commit whenever the hooks arrive by a merge. The defect f2 guarded against,
# a walk from a commit the first-parent line never passes, cannot happen now:
# the walk starts at the merge that brought the side commit in ("merge side
# docs"), the pre-rule exemption begins at that same commit, and nothing
# before it is walked or excused. Here nothing follows it, so the walk is
# empty, which is the key moved forward walking less, disclosed and reviewed
# like the rest of .claude/.
baseline_key "$BLS" "$bls_side"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLS"
expect_script "0164 baseline f2 (flipped by 0167): a baseline off the first-parent line is framed at the merge that brought it in" 0 \
  "audited 0" "since: $(git -C "$BLS" rev-parse --short HEAD)" "declared $(git -C "$BLS" rev-parse --short "$bls_side")"
# and the on-line control still audits, so f2 is about the line and not about keys
baseline_key "$BLS" "$(git -C "$BLS" rev-list --first-parent HEAD | sed -n 2p)"
run_script bash "$SCRIPTS/trunk-audit.sh" "$BLS"
expect_script "0164 baseline f3: a baseline ON the first-parent line is honoured, declared" 0 "(declared)"

fi; shard_region_end
# <<< SHARD-END trunk-audit-late-06

# >>> SHARD-BEGIN case-probe-06 smoke=path,mktemp,perm cost=3
# Split out of trunk-audit-late-06 so the platform smoke carries mktemp and TMPDIR, permissions and the audit's role reads at the case probe's cost alone (spec 0168, item 8).
if shard_region case-probe-06; then
# ===========================================================================
# THE CASE-FOLD PROBE ASKS ABOUT THE REPOSITORY (spec 0164, fix round 2; F1 and
# F4 of the 2.10.0 leg). It used to probe under TMPDIR, so the verdict followed
# a filesystem nobody was auditing: measured on this project, one repository
# read 1 violation with the ordinary TMPDIR and 0 with TMPDIR on a
# case-sensitive volume, and the mirror refused legitimate work. A probe that
# cannot run now refuses by name instead of reading an unset status.
# ===========================================================================
cfp_fixture() { # cfp_fixture <dir> <role-dir-spelling> : one direct trunk commit under that spelling
  local d="$1" spell="$2"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/$spell"
  git_init "$d"; sdd_json "$d"
  printf '# inv\n\n| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm stamp >/dev/null 2>&1
  printf 'code\n' > "$d/$spell/f.js"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "direct trunk commit" >/dev/null 2>&1
}
# The fixture needs a volume whose case behaviour DIFFERS from the one the audit
# would otherwise have probed. macOS builds one with hdiutil; elsewhere the case
# is skipped BY NAME rather than passing over a fixture that does not exist.
CFP_ALT=""; CFP_DMG=""
if command -v hdiutil >/dev/null 2>&1; then
  CFP_DMG="$WORK/cfp-cs.dmg"; CFP_ALT="$WORK/cfp-cs"
  if hdiutil create -size 10m -fs "Case-sensitive APFS" -volname cfpcs "$CFP_DMG" >/dev/null 2>&1 \
     && hdiutil attach "$CFP_DMG" -mountpoint "$CFP_ALT" -nobrowse >/dev/null 2>&1; then :; else CFP_ALT=""; fi
fi
if [[ -n "$CFP_ALT" ]]; then
  # This host's own disk folds case (the fixture below is built on it), so the
  # alternate volume is the case-sensitive one and TESTS/ is a real role path
  # here whichever directory the probe writes in. The verdict must not move.
  cfp_fixture "$WORK/cfp-a" TESTS
  cfp_out1="$(bash "$SCRIPTS/trunk-audit.sh" "$WORK/cfp-a" 2>&1)"; cfp_rc1=$?
  cfp_out2="$(TMPDIR="$CFP_ALT" bash "$SCRIPTS/trunk-audit.sh" "$WORK/cfp-a" 2>&1)"; cfp_rc2=$?
  if [[ "$cfp_rc1" == "$cfp_rc2" ]] && [[ "$(printf '%s' "$cfp_out1" | grep -c VIOLATION)" == "$(printf '%s' "$cfp_out2" | grep -c VIOLATION)" ]]; then
    ok "case probe a: the verdict does not follow TMPDIR's filesystem (rc $cfp_rc1 both ways)"
  else
    bad "case probe a: the verdict does not follow TMPDIR's filesystem" \
        "rc $cfp_rc1 with the ordinary TMPDIR, rc $cfp_rc2 with TMPDIR on another volume"
  fi
  # The mirror, on the alternate volume: a case-sensitive repository where
  # TESTS/ is genuinely NOT the role path, audited from a host whose TMPDIR
  # folds case. Refusing it is the false denial F1 filed.
  cfp_fixture "$CFP_ALT/cfp-b" TESTS
  cfp_outb="$(bash "$SCRIPTS/trunk-audit.sh" "$CFP_ALT/cfp-b" 2>&1)"; cfp_rcb=$?
  if [[ "$cfp_rcb" -eq 0 ]]; then
    ok "case probe b: a case-sensitive repository is not refused for a path that only looks like a role"
  else
    bad "case probe b: a case-sensitive repository is not refused for a path that only looks like a role" \
        "rc $cfp_rcb: $(printf '%s' "$cfp_outb" | grep VIOLATION | head -n1)"
  fi
  hdiutil detach "$CFP_ALT" >/dev/null 2>&1 || true
else
  ok "case probe a/b: SKIPPED BY NAME, this host cannot build a volume whose case behaviour differs (no hdiutil); the macOS leg asserts the pair"
fi
# A probe that cannot run refuses BY NAME, on every platform. Skipped BY NAME where the
# denial does not hold for this account (root, or a Windows administrator; spec 0179
# measures the condition instead of assuming it from the uid, perm_holds).
cfp_fixture "$WORK/cfp-ro" TESTS
# Since 0169 the probe stands in each role directory (L2 F16), so the
# directories it writes in are the ones made read-only: the instance root and
# both role directories (tests resolves to TESTS/ on a folding disk).
chmod 555 "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"
for cfp_d in "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"; do perm_deny "$cfp_d" W; done
if perm_holds "$WORK/cfp-ro" W && perm_holds "$WORK/cfp-ro/src" W && perm_holds "$WORK/cfp-ro/TESTS" W; then
  cfp_outro="$(bash "$SCRIPTS/trunk-audit.sh" "$WORK/cfp-ro" 2>&1)"; cfp_rcro=$?
  for cfp_d in "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"; do perm_undeny "$cfp_d"; done
  chmod 755 "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"
  if [[ "$cfp_rcro" -eq 2 ]] && printf '%s' "$cfp_outro" | grep -q 'SLH-CASE-PROBE-FAILED'; then
    ok "case probe c: a probe that cannot write refuses by name instead of reporting clean"
  else
    bad "case probe c: a probe that cannot write refuses by name instead of reporting clean" \
        "rc $cfp_rcro: $(printf '%s' "$cfp_outro" | tail -n1 | cut -c1-160)"
  fi
else
  for cfp_d in "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"; do perm_undeny "$cfp_d"; done
  chmod 755 "$WORK/cfp-ro" "$WORK/cfp-ro/src" "$WORK/cfp-ro/TESTS"
  ok "case probe c: SKIPPED BY NAME, $PERM_WHY"
fi
# The probe leaves nothing behind.
cfp_fixture "$WORK/cfp-clean" TESTS
bash "$SCRIPTS/trunk-audit.sh" "$WORK/cfp-clean" >/dev/null 2>&1
# Since 0169 the probe stands beside each role directory, so every directory is looked in.
cfp_left="$(find "$WORK/cfp-clean" -name '.setlist-case-probe*' 2>/dev/null)"
if [[ -z "$cfp_left" ]]; then
  ok "case probe d: the probe file is removed after the run"
else
  bad "case probe d: the probe file is removed after the run" "$cfp_left"
fi

fi; shard_region_end
# <<< SHARD-END case-probe-06

# --- THE CASE PROBE MEASURES THE ROLE DIRECTORY'S VOLUME (spec 0169, L2 F16) ----
# 2.10.0 moved the probe from TMPDIR to the project root; a repository can span
# volumes, so a role directory mounted from a volume whose case behaviour
# differs from the root's was judged by the root's, at the scope hook and at
# the audit alike. Both arms: a case-SENSITIVE role directory inside a folding
# root (the leg's arm, a false denial), and a FOLDING role directory inside a
# case-sensitive root (the mirror, a silent pass the leg could not build).
# And the fold itself is ASCII-only at both layers (the validator's ruling on
# E-b), so the two cannot disagree about a non-ASCII capital.
cv_instance() { # cv_instance <dir> <roles-json-object>: git and sdd.json, on the trunk, nothing committed under src
  local d="$1"
  mkdir -p "$d/specs" "$d/.claude"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":%s}\n' "$2" > "$d/.claude/sdd.json"
  printf '# inv\n\n| Num | Title | Status |\n| --- | --- | --- |\n' > "$d/specs/STATUS.md"
  git -C "$d" add .claude specs >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
}
cv_scope() { # cv_scope <proj> <abs-path> -> the advisory code, or "silent"
  local o
  o="$(jq -nc --arg p "$2" --arg c "$1" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:$c}' \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/scope-hook.sh" 2>/dev/null | jq -r '.setlistAdvisory.code // "silent"' 2>/dev/null)"
  printf '%s' "${o:-silent}"
}
cv_audit() { # cv_audit <proj> <relative-file>: commit it straight onto main, then audit -> "rc=N violations=M"
  local d="$1" f="$2" o rc
  mkdir -p "$d/$(dirname "$f")"; printf 'x\n' > "$d/$f"
  git -C "$d" add -- "$f" >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "write $f" >/dev/null 2>&1
  o="$(bash "$SCRIPTS/trunk-audit.sh" "$d" 2>&1)"; rc=$?
  git -C "$d" -c core.hooksPath=/dev/null reset -q --hard HEAD~1 >/dev/null 2>&1
  printf 'rc=%s violations=%s' "$rc" "$(printf '%s\n' "$o" | grep -c '^VIOLATION')"
}
cv_folds() { local p="$1/.cv-probe.$$"; : > "$p" 2>/dev/null || return 2; [[ -e "$1/.CV-PROBE.$$" ]]; local r=$?; rm -f "$p"; return $r; }

# >>> SHARD-BEGIN case-volume-0169 cost=4
if shard_region case-volume-0169; then
CV_MOUNTS=""
cv_mount() { # cv_mount <fs> <mountpoint>: a 10 MB image of that filesystem, mounted there
  local img="$WORK/cv-$RANDOM.dmg"
  hdiutil create -size 10m -fs "$1" -volname cv "$img" >/dev/null 2>&1 \
    && hdiutil attach "$img" -mountpoint "$2" -nobrowse >/dev/null 2>&1 \
    && CV_MOUNTS="$2 $CV_MOUNTS"
}
if command -v hdiutil >/dev/null 2>&1 && cv_folds "$WORK"; then
  # ARM 1, the leg's: the root folds (this host's disk), src/ is case-sensitive.
  CV1="$WORK/cv-arm1"; rm -rf "$CV1"; mkdir -p "$CV1/src"
  if cv_mount "Case-sensitive APFS" "$CV1/src"; then
    cv_instance "$CV1" '{"src":"src/app","tests":"tests"}'
    mkdir -p "$CV1/src/app" "$CV1/src/APP"
    cv_s="$(cv_scope "$CV1" "$CV1/src/APP/b.txt")"; cv_a="$(cv_audit "$CV1" src/APP/b.txt)"
    [[ "$cv_s" == silent ]] && ok "case volume 1a: src/APP on a case-sensitive role volume is not the role src/app, and the scope hook is silent" \
      || bad "case volume 1a: src/APP on a case-sensitive role volume is not the role src/app, and the scope hook is silent" "got [$cv_s]"
    [[ "$cv_a" == "rc=0 violations=0" ]] && ok "case volume 1b: the audit reads the same commit clean" \
      || bad "case volume 1b: the audit reads the same commit clean" "got [$cv_a]"
    cv_s="$(cv_scope "$CV1" "$CV1/src/app/a.txt")"; cv_a="$(cv_audit "$CV1" src/app/a.txt)"
    [[ "$cv_s" == SH-TRUNK-WRITE && "$cv_a" == "rc=1 violations=1" ]] && ok "case volume 1c: the role path itself still draws the advisory and the violation (the control)" \
      || bad "case volume 1c: the role path itself still draws the advisory and the violation (the control)" "scope [$cv_s] audit [$cv_a]"
  else
    bad "case volume arm 1: the case-sensitive image mounts" "hdiutil could not build or mount it under $CV1/src"
  fi
  # ARM 2, the mirror: the root is case-sensitive, the role directory folds.
  # macOS refuses a user a mount inside a mounted image ("hdiutil: attach
  # failed - Permission denied", measured with and without -owners on), so the
  # folding role directory reaches the case-sensitive root through a link to
  # this host's own disk, which is also how a directory on another volume is
  # commonly placed. The commit is made while src/ is a real directory, then
  # src becomes the link: the audit reads the committed path and probes where
  # the role directory now lives.
  CV2R="$WORK/cv-arm2-root"; rm -rf "$CV2R" "$WORK/cv-arm2-fold"; mkdir -p "$CV2R" "$WORK/cv-arm2-fold/app"
  if cv_mount "Case-sensitive APFS" "$CV2R"; then
    CV2="$CV2R/p"; mkdir -p "$CV2"
    cv_instance "$CV2" '{"src":"src/app","tests":"tests"}'
    mkdir -p "$CV2/src/APP"; printf 'x\n' > "$CV2/src/APP/b.txt"
    git -C "$CV2" add -- src/APP/b.txt >/dev/null 2>&1; git -C "$CV2" -c core.hooksPath=/dev/null commit -qm "write src/APP/b.txt" >/dev/null 2>&1
    rm -rf "$CV2/src"; ln -s "$WORK/cv-arm2-fold" "$CV2/src"
    cv_a="$(bash "$SCRIPTS/trunk-audit.sh" "$CV2" 2>&1)"; cv_arc=$?
    cv_a="rc=$cv_arc violations=$(printf '%s\n' "$cv_a" | grep -c '^VIOLATION')"
    cv_s="$(cv_scope "$CV2" "$CV2/src/APP/c.txt")"
    [[ "$cv_s" == SH-TRUNK-WRITE ]] && ok "case volume 2a: src/APP where the role directory folds IS the role src/app, and the scope hook advises" \
      || bad "case volume 2a: src/APP where the role directory folds IS the role src/app, and the scope hook advises" "got [$cv_s]"
    [[ "$cv_a" == "rc=1 violations=1" ]] && ok "case volume 2b: the audit reports the committed src/APP/b.txt as feature code on the trunk" \
      || bad "case volume 2b: the audit reports the committed src/APP/b.txt as feature code on the trunk" "got [$cv_a]"
    cv_s="$(cv_scope "$CV2" "$CV2/README.md")"
    [[ "$cv_s" == silent ]] && ok "case volume 2c: a docs write on the case-sensitive root stays silent (the control)" \
      || bad "case volume 2c: a docs write on the case-sensitive root stays silent (the control)" "got [$cv_s]"
  else
    bad "case volume arm 2: the case-sensitive image mounts" "hdiutil could not build or mount it at $CV2R"
  fi
  for cv_m in $CV_MOUNTS; do hdiutil detach "$cv_m" >/dev/null 2>&1 || hdiutil detach -force "$cv_m" >/dev/null 2>&1 || true; done
else
  ok "case volume 1 and 2: SKIPPED BY NAME, this host cannot build a volume whose case behaviour differs from its own (no hdiutil, or a root that does not fold); the macOS leg asserts both arms"
fi
# E-b, THE FOLD IS ASCII-ONLY AT BOTH LAYERS: a role whose name carries a
# non-ASCII capital, written in its lower-case spelling where no such directory
# exists yet. Neither layer folds it, so they agree; the residue is named in the
# spec's Closing report. Needs a root that folds; skipped by name elsewhere.
if cv_folds "$WORK"; then
  CVB="$WORK/cv-eb"; rm -rf "$CVB"; mkdir -p "$CVB"
  cv_instance "$CVB" "$(printf '{"src":"\303\204dir","tests":"tests"}')"
  cv_s="$(cv_scope "$CVB" "$(printf '%s/\303\244dir/x.txt' "$CVB")")"
  cv_a="$(cv_audit "$CVB" "$(printf '\303\244dir/x.txt')")"
  [[ "$cv_s" == silent ]] && ok "case fold eb1: the scope hook folds ASCII only, so a non-ASCII capital is not folded" \
    || bad "case fold eb1: the scope hook folds ASCII only" "got [$cv_s]"
  [[ "$cv_a" == "rc=0 violations=0" ]] && ok "case fold eb2: the trunk audit folds ASCII only, so a non-ASCII capital is not folded" \
    || bad "case fold eb2: the trunk audit folds ASCII only" "got [$cv_a]"
  if { [[ "$cv_s" == silent ]] && [[ "$cv_a" == "rc=0 violations=0" ]]; } || { [[ "$cv_s" == SH-TRUNK-WRITE ]] && [[ "$cv_a" == "rc=1 violations=1" ]]; }; then
    ok "case fold eb3: the scope hook and the trunk audit AGREE about a non-ASCII case variant of a role directory"
  else
    bad "case fold eb3: the scope hook and the trunk audit agree about a non-ASCII case variant of a role directory" "scope [$cv_s] audit [$cv_a]"
  fi
else
  ok "case fold eb1 to eb3: SKIPPED BY NAME, this host's disk does not fold case, so no layer folds and there is nothing to disagree about"
fi
fi; shard_region_end
# <<< SHARD-END case-volume-0169
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

  # A backslash in a file name, which NTFS cannot hold (spec 0179, name_holds).
  if name_holds 'x\y.txt'; then
  AUD="$WORK/audit-qp-bslash-$TA_QP"; audit_fixture "$AUD" bslashrole
  git -C "$AUD" config core.quotePath "$TA_QP"
  run_script bash "$SCRIPTS/trunk-audit.sh" "$AUD"
  expect_script "trunk audit F1 [quotePath=$TA_QP]: a BACKSLASH role path is seen (quoted at any setting)" 1 "1 violations"
  else
    ok "trunk audit F1 [quotePath=$TA_QP]: a BACKSLASH role path: SKIPPED BY NAME, $NAME_WHY"
  fi

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

# >>> SHARD-BEGIN trunk-degraded-06 smoke=path cost=1
# A prelude block moved into a measured region (spec 0168, item 2): independent both ways, measured.
if shard_region trunk-degraded-06; then
DEG="$WORK/degraded"
close_fixture "$DEG" no no answered no no true

# DETACHED HEAD. `branch --show-current` returns empty, so no gate can tell
# whether it is on the trunk. Documented as a sideways route; asserted here so
# the day it closes we find out.
DEG_HEAD="$(git -C "$DEG" rev-parse main)"
git -C "$DEG" checkout -q --detach "$DEG_HEAD"
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

# EMPTY role paths. A config that parses but records nothing usable.
DEG4="$WORK/degraded-noroles"
close_fixture "$DEG4" no no answered no no true
jq '.roles = {}' "$DEG4/.claude/sdd.json" > "$DEG4/t" && mv "$DEG4/t" "$DEG4/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$DEG4" "$(jq -nc --arg p "$DEG4/src/x.js" '{tool_name:"Write", tool_input:{file_path:$p}}')"
expect_deny "degraded f: absent role paths fall back to src/tests rather than allowing everything" "never lands"

# --- interpreter forms: the audit catch (moved here from shard 04 in spec 0144) --
# The interpreter forms (sh -c, bash -c, timeout, sudo) passed the close gate by
# design and were pinned together with what catches their outcome: this audit.
# The gate half left with close-gate.sh in 2.8.0; the catch stays. The branch must
# carry ROLE-PATH changes for the audit to have an opinion.
INTERP="$WORK/interpreter"
close_fixture "$INTERP" no no answered no no true
git -C "$INTERP" checkout -q spec/0001-thing
mkdir -p "$INTERP/src"; printf 'feature\n' > "$INTERP/src/f.js"
git -C "$INTERP" add -A && git -C "$INTERP" commit -qm "feature code, spec still unclosed"
git -C "$INTERP" checkout -q main
git -C "$INTERP" merge -q --no-ff -m "merge as an interpreter form would leave it" spec/0001-thing
run_script bash "$SCRIPTS/trunk-audit.sh" "$INTERP"
expect_script "interpreter: the trunk audit CATCHES the outcome the gate let past" 1 "VIOLATION"
fi; shard_region_end
# <<< SHARD-END trunk-degraded-06

# =============================================================================
# SPEC 0174: THE EVIL-EDIT ARM (report-only) AND TE1's OVERLAP REFUSAL.
# Helpers here, outside the regions, so shard 16's merge-landing pin can use them
# too. e174_fixture builds a structured instance (the record and the page both
# carried, roles src and tests) with specs 0001 and 0002 active and, unless told
# otherwise, "plugin":{"version":"2.11.0"} in .claude/sdd.json: both new arms are
# dated by the plugin version in the merge's own tree (spec 0174, decision 3), so
# a fixture that carries none exercises the pre-rule exemption, not the arm.
# e174_fixture <dir> [plugin-version|none] [record|page]
e174_fixture() {
  local d="$1" v="${2:-2.11.0}" kind="${3:-record}" pv=""
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude"
  git_init "$d"
  [[ "$v" == "none" ]] || pv=',"plugin":{"version":"'"$v"'"}'
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}%s}\n' "$pv" > "$d/.claude/sdd.json"
  [[ "$kind" == "page" ]] || printf '{"setlist_status":1,"specs":{"0001":{"status":"active"},"0002":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | A | ACTIVE | wip |\n| 0002 | B | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf 'shared v0\n' > "$d/src/shared.txt"; printf 'other\n' > "$d/src/other.txt"; printf 'readme\n' > "$d/README.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm base >/dev/null 2>&1
}
# e174_close <dir> <num> <branch> <file> <content> : on <branch>, spec <num> declares <file>,
# writes it and closes (the spec file, the record when the instance carries one, the page row)
e174_close() {
  local d="$1" n="$2" b="$3" f="$4"
  git -C "$d" checkout -q "$b"
  printf '# Spec %s\n\nStatus: CLOSED\nOwns: %s\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n\n```close-review\nround 1: PASS\na: PASS\n```\n' "$n" "$f" > "$d/specs/$n-x.md"
  mkdir -p "$(dirname "$d/$f")"; printf '%s\n' "$5" > "$d/$f"
  if [[ -f "$d/.claude/status.json" ]]; then
    jq --arg n "$n" '.specs[$n]={"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}' "$d/.claude/status.json" > "$d/.claude/status.json.new" \
      && mv "$d/.claude/status.json.new" "$d/.claude/status.json"
  fi
  sed -e "s/^| $n | \(.\) | ACTIVE |/| $n | \1 | CLOSED |/" "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "close $n" >/dev/null 2>&1
}
# e174_merge <dir> <branch> [target] : --no-ff onto the target (main by default), hooks off. A
# conflict is resolved by hand the way a person would: the record and the page keep every
# close from both sides, and any other conflicted path takes the merged branch's side.
e174_merge() {
  local d="$1" t="${3:-main}" f
  git -C "$d" checkout -q "$t"
  git -C "$d" -c core.hooksPath=/dev/null merge -q --no-ff -m "merge $2" "$2" >/dev/null 2>&1 && return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in
      .claude/status.json)
        { git -C "$d" show ":2:$f"; git -C "$d" show ":3:$f"; } | jq -s '.[0] as $a | .[1] as $b | ($a * $b) | .specs = ([$a.specs, $b.specs] | map(to_entries) | add | group_by(.key) | map({key: .[0].key, value: (map(.value) | (map(select(.status == "closed")) + .)[0])}) | from_entries)' > "$d/$f" ;; # stdin, never <(...): a native jq cannot open /proc/<pid>/fd (spec 0179)
      specs/STATUS.md)
        git -C "$d" show ":3:$f" > "$d/$f"
        git -C "$d" show ":2:$f" | awk -F' [|] ' '$3 == "CLOSED" { sub(/^[|] /, "", $1); print $1 }' | while IFS= read -r n; do
          sed -e "s/^| $n | \(.\) | ACTIVE |/| $n | \1 | CLOSED |/" "$d/$f" > "$d/$f.new" && mv "$d/$f.new" "$d/$f"
        done ;;
      *) git -C "$d" checkout -q --theirs -- "$f" ;;
    esac
  done < <(git -C "$d" diff --name-only --diff-filter=U)
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "merge $2 (resolved)" >/dev/null 2>&1
}
# mt_evil <dir> <file-edited-in-the-merge> : spec 0001 closes on its branch (declaring src/a.txt),
# and its --no-ff close merge onto main also edits a file neither side changed
mt_evil() {
  git -C "$1" branch spec/0001; e174_close "$1" 0001 spec/0001 src/a.txt A; git -C "$1" checkout -q main
  git -C "$1" -c core.hooksPath=/dev/null merge -q --no-ff --no-commit spec/0001 >/dev/null 2>&1
  printf 'EVIL\n' >> "$1/$2"; git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c core.hooksPath=/dev/null commit -qm "merge spec/0001" >/dev/null 2>&1
}
# mt_git_shim <dir> : a PATH entry whose git reports 2.37.0 and runs the real git for everything else
mt_git_shim() {
  rm -rf "$1"; mkdir -p "$1"
  printf '#!/bin/sh\ncase "$1" in version|--version) echo "git version 2.37.0"; exit 0 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$1/git"
  chmod +x "$1/git"
}

# >>> SHARD-BEGIN merge-tree-0174 cost=4
if shard_region merge-tree-0174; then
MT_CODE='SLH-MERGE-EDIT-OUTSIDE-CONFLICT'
# a: the close merge edits a role-path file neither side changed.
MTA="$WORK/mt-a"; e174_fixture "$MTA"; mt_evil "$MTA" src/other.txt
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTA" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && grep -q "^report .*\[$MT_CODE\].*\"src/other.txt\"" <<< "$MT_OUT" && ! grep -q '"src/a.txt"' <<< "$MT_OUT"; then
  ok "0174 mt a: a close merge that edits a file outside its conflicts is REPORTED by name, the exit status unchanged"
else
  bad "0174 mt a: a close merge that edits a file outside its conflicts is REPORTED by name, the exit status unchanged" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# a2: every file, not role paths only.
MTA2="$WORK/mt-a2"; e174_fixture "$MTA2"; mt_evil "$MTA2" README.md
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTA2" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && grep -q "^report .*\[$MT_CODE\].*\"README.md\"" <<< "$MT_OUT"; then
  ok "0174 mt a2: an edit to a file outside every role (README.md) is named too"
else
  bad "0174 mt a2: an edit to a file outside every role (README.md) is named too" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# b (control): a real conflict, resolved by hand; the merge differs from the clean merge only
# inside the conflicted set, so nothing is reported.
MTB="$WORK/mt-b"; e174_fixture "$MTB"; git -C "$MTB" branch spec/0001
git -C "$MTB" checkout -q spec/0001; printf 'readme from the branch\n' > "$MTB/README.md"; git -C "$MTB" add -A >/dev/null 2>&1; git -C "$MTB" -c core.hooksPath=/dev/null commit -qm "branch readme" >/dev/null 2>&1
e174_close "$MTB" 0001 spec/0001 src/a.txt A; git -C "$MTB" checkout -q main
printf 'readme on the trunk\n' > "$MTB/README.md"; git -C "$MTB" add -A >/dev/null 2>&1; git -C "$MTB" -c core.hooksPath=/dev/null commit -qm "trunk readme" >/dev/null 2>&1
git -C "$MTB" -c core.hooksPath=/dev/null merge -q --no-ff spec/0001 >/dev/null 2>&1
MTB_CONFLICT="$(git -C "$MTB" diff --name-only --diff-filter=U)"
printf 'readme, resolved by hand\n' > "$MTB/README.md"; git -C "$MTB" add -A >/dev/null 2>&1; git -C "$MTB" -c core.hooksPath=/dev/null commit -qm "merge spec/0001 (resolved)" >/dev/null 2>&1
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTB" 2>&1)"; MT_RC=$?
if [[ "$MTB_CONFLICT" == "README.md" && "$MT_RC" -eq 0 ]] && ! grep -q "$MT_CODE" <<< "$MT_OUT"; then
  ok "0174 mt b (control): a conflict resolved by hand differs only inside the conflicted set and is not reported"
else
  bad "0174 mt b (control): a conflict resolved by hand differs only inside the conflicted set and is not reported" "conflicted=[$MTB_CONFLICT] rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# b2 (control): a clean close merge.
MTB2="$WORK/mt-b2"; e174_fixture "$MTB2"; git -C "$MTB2" branch spec/0001; e174_close "$MTB2" 0001 spec/0001 src/a.txt A; e174_merge "$MTB2" spec/0001
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTB2" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && ! grep -q "$MT_CODE" <<< "$MT_OUT"; then
  ok "0174 mt b2 (control): a clean close merge is not reported"
else
  bad "0174 mt b2 (control): a clean close merge is not reported" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# c: git below 2.38 (a shim that reports 2.37.0): the arm is skipped BY NAME, once, and no
# merge is compared.
mt_git_shim "$WORK/mt-oldgit"
MT_OUT="$(PATH="$WORK/mt-oldgit:$PATH" bash "$SCRIPTS/trunk-audit.sh" "$MTA" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && [[ "$(grep -c "$MT_CODE" <<< "$MT_OUT")" == "1" ]] && grep -q "^report .*\[$MT_CODE\].*skipped.*2\.37\.0" <<< "$MT_OUT" && ! grep -q '"src/other.txt"' <<< "$MT_OUT"; then
  ok "0174 mt c: under git 2.37.0 the arm is SKIPPED BY NAME once, and no merge is compared"
else
  bad "0174 mt c: under git 2.37.0 the arm is SKIPPED BY NAME once, and no merge is compared" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# d (control): the same merge in an instance whose stamp predates the arm (2.10.0) is not compared.
MTD="$WORK/mt-d"; e174_fixture "$MTD" 2.10.0; mt_evil "$MTD" src/other.txt
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTD" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && ! grep -q "$MT_CODE" <<< "$MT_OUT"; then
  ok "0174 mt d (control): a merge whose own tree stamps plugin 2.10.0 is not compared (the pre-rule exemption)"
else
  bad "0174 mt d (control): a merge whose own tree stamps plugin 2.10.0 is not compared (the pre-rule exemption)" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# e (DE15): the record-less (page-only) instance reports the same merge.
MTE="$WORK/mt-e"; e174_fixture "$MTE" 2.11.0 page; mt_evil "$MTE" src/other.txt
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTE" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && grep -q "^report .*\[$MT_CODE\].*\"src/other.txt\"" <<< "$MT_OUT"; then
  ok "0174 mt e: a record-less (page-only) instance reports the same edit (DE15)"
else
  bad "0174 mt e: a record-less (page-only) instance reports the same edit (DE15)" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# f: the audit writes nothing into the repository it reads (merge-tree's objects go elsewhere).
MTF="$WORK/mt-f"; e174_fixture "$MTF"; mt_evil "$MTF" src/other.txt
MTF_BEFORE="$(git -C "$MTF" count-objects -v | grep -E '^(count|in-pack):' | tr '\n' ' ')"
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTF" 2>&1)"; MT_RC=$?
MTF_AFTER="$(git -C "$MTF" count-objects -v | grep -E '^(count|in-pack):' | tr '\n' ' ')"
if [[ "$MT_RC" -eq 0 && "$MTF_BEFORE" == "$MTF_AFTER" ]] && grep -q "$MT_CODE" <<< "$MT_OUT"; then
  ok "0174 mt f: the compared merge leaves the repository's object count unchanged"
else
  bad "0174 mt f: the compared merge leaves the repository's object count unchanged" "rc=$MT_RC before=[$MTF_BEFORE] after=[$MTF_AFTER] reported=$(grep -c "$MT_CODE" <<< "$MT_OUT")"
fi
# g: a merge that brings NO role-path change (a docs-only branch) and edits README.md in the
# merge itself: the arm is asked before the audit's role-path shortcut.
MTG="$WORK/mt-g"; e174_fixture "$MTG"; git -C "$MTG" checkout -q -b docs
printf 'notes\n' > "$MTG/NOTES.md"; git -C "$MTG" add -A >/dev/null 2>&1; git -C "$MTG" -c core.hooksPath=/dev/null commit -qm notes >/dev/null 2>&1
git -C "$MTG" checkout -q main; git -C "$MTG" -c core.hooksPath=/dev/null merge -q --no-ff --no-commit docs >/dev/null 2>&1
printf 'EVIL\n' >> "$MTG/README.md"; git -C "$MTG" add -A >/dev/null 2>&1; git -C "$MTG" -c core.hooksPath=/dev/null commit -qm "merge docs" >/dev/null 2>&1
MT_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$MTG" 2>&1)"; MT_RC=$?
if [[ "$MT_RC" -eq 0 ]] && grep -q "^report .*\[$MT_CODE\].*\"README.md\"" <<< "$MT_OUT" && ! grep -q '"NOTES.md"' <<< "$MT_OUT"; then
  ok "0174 mt g: a merge bringing no role-path change that edits a file itself is named (asked before the role-path shortcut)"
else
  bad "0174 mt g: a merge bringing no role-path change that edits a file itself is named (asked before the role-path shortcut)" "rc=$MT_RC: $(grep -E 'report|VIOLATION|audited' <<< "$MT_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
fi; shard_region_end
# <<< SHARD-END merge-tree-0174

# ov_squash <dir> <branch> : --squash onto main, the conflict resolved as e174_merge resolves one
ov_squash() {
  local d="$1" f
  git -C "$d" checkout -q main
  git -C "$d" -c core.hooksPath=/dev/null merge -q --squash "$2" >/dev/null 2>&1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in
      .claude/status.json)
        { git -C "$d" show ":2:$f"; git -C "$d" show ":3:$f"; } | jq -s '.[0] as $a | .[1] as $b | ($a * $b) | .specs = ([$a.specs, $b.specs] | map(to_entries) | add | group_by(.key) | map({key: .[0].key, value: (map(.value) | (map(select(.status == "closed")) + .)[0])}) | from_entries)' > "$d/$f" ;; # stdin, never <(...): a native jq cannot open /proc/<pid>/fd (spec 0179)
      specs/STATUS.md)
        git -C "$d" show ":3:$f" > "$d/$f"
        git -C "$d" show ":2:$f" | awk -F' [|] ' '$3 == "CLOSED" { sub(/^[|] /, "", $1); print $1 }' | while IFS= read -r n; do
          sed -e "s/^| $n | \(.\) | ACTIVE |/| $n | \1 | CLOSED |/" "$d/$f" > "$d/$f.new" && mv "$d/$f.new" "$d/$f"
        done ;;
      *) git -C "$d" checkout -q --theirs -- "$f" ;;
    esac
  done < <(git -C "$d" diff --name-only --diff-filter=U)
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c core.hooksPath=/dev/null commit -qm "squash $2" >/dev/null 2>&1
}
# ov_parallel <dir> <file-A> <file-B> [version] [record|page] : specs 0001 and 0002 both branch from
# main before either closes; 0001 closes declaring <file-A> and merges; 0002 closes on its branch
# declaring <file-B> (the caller merges it, so each case chooses how)
ov_parallel() {
  e174_fixture "$1" "${4:-2.11.0}" "${5:-record}"
  git -C "$1" branch spec/0001; git -C "$1" branch spec/0002
  e174_close "$1" 0001 spec/0001 "$2" "from A"; e174_merge "$1" spec/0001
  e174_close "$1" 0002 spec/0002 "$3" "from B"
}

# >>> SHARD-BEGIN owns-overlap-0174 cost=4
if shard_region owns-overlap-0174; then
OV_CODE='SLH-OWNS-OVERLAP'
ov_refused() { # ov_refused <audit-output> : the second close refused by name, naming the file and both specs, the first not
  grep -q "^VIOLATION .*\[$OV_CODE\] spec 0002 declares \"src/shared.txt\", which spec 0001 also declares and closed at [0-9a-f]* after this branch left \"main\"" <<< "$1" \
    && [[ "$(grep -c "\[$OV_CODE\]" <<< "$1")" == "1" ]] && grep -q 'Merge "main" into the spec branch' <<< "$1"
}
# a: overlapping sets, both --no-ff.
OVA="$WORK/ov-a"; ov_parallel "$OVA" src/shared.txt src/shared.txt; e174_merge "$OVA" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVA" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -ne 0 ]] && ov_refused "$OV_OUT"; then
  ok "0174 overlap a: two parallel specs declaring one file: the SECOND close is refused by name (SLH-OWNS-OVERLAP), the first accepted"
else
  bad "0174 overlap a: two parallel specs declaring one file: the SECOND close is refused by name (SLH-OWNS-OVERLAP), the first accepted" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# b (control): disjoint sets.
OVB="$WORK/ov-b"; ov_parallel "$OVB" src/a.txt src/b.txt; e174_merge "$OVB" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVB" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap b (control): two parallel specs with disjoint Owns: sets both close"
else
  bad "0174 overlap b (control): two parallel specs with disjoint Owns: sets both close" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# c (control): the remedy. 0002's branch takes the trunk (a catch-up merge) before it closes.
OVC="$WORK/ov-c"; e174_fixture "$OVC"; git -C "$OVC" branch spec/0001; git -C "$OVC" branch spec/0002
e174_close "$OVC" 0001 spec/0001 src/shared.txt "from A"; e174_merge "$OVC" spec/0001
e174_merge "$OVC" main spec/0002; e174_close "$OVC" 0002 spec/0002 src/shared.txt "from B"; e174_merge "$OVC" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVC" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap c (control): after a catch-up merge of the trunk into the second branch, the same overlapping close is accepted"
else
  bad "0174 overlap c (control): after a catch-up merge of the trunk into the second branch, the same overlapping close is accepted" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# d (control): sequential. 0002 is cut from main after 0001 closed, both declaring the file.
OVD="$WORK/ov-d"; e174_fixture "$OVD"; git -C "$OVD" branch spec/0001
e174_close "$OVD" 0001 spec/0001 src/shared.txt "from A"; e174_merge "$OVD" spec/0001
git -C "$OVD" branch spec/0002 main; e174_close "$OVD" 0002 spec/0002 src/shared.txt "from B"; e174_merge "$OVD" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVD" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap d (control): a spec cut after the earlier close, declaring the same file, is accepted (a double declaration across time)"
else
  bad "0174 overlap d (control): a spec cut after the earlier close, declaring the same file, is accepted (a double declaration across time)" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# e (control): overlap a in an instance whose stamp predates the rule (2.10.0).
OVE="$WORK/ov-e"; ov_parallel "$OVE" src/shared.txt src/shared.txt 2.10.0; e174_merge "$OVE" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVE" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap e (control): the same overlap under a plugin 2.10.0 stamp is not judged (the pre-rule exemption)"
else
  bad "0174 overlap e (control): the same overlap under a plugin 2.10.0 stamp is not judged (the pre-rule exemption)" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# f (DE15): overlap a on a record-less (page-only) instance.
OVF="$WORK/ov-f"; ov_parallel "$OVF" src/shared.txt src/shared.txt 2.11.0 page; e174_merge "$OVF" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVF" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -ne 0 ]] && ov_refused "$OV_OUT"; then
  ok "0174 overlap f: on a record-less (page-only) instance the second overlapping close is refused by name (DE15)"
else
  bad "0174 overlap f: on a record-less (page-only) instance the second overlapping close is refused by name (DE15)" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# g (pin, the stated boundary): the second close lands by --squash, which has no branch point.
OVG="$WORK/ov-g"; ov_parallel "$OVG" src/shared.txt src/shared.txt; ov_squash "$OVG" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVG" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap g (pin): a second overlapping close landed by --squash is not judged (no branch point; the stated boundary)"
else
  bad "0174 overlap g (pin): a second overlapping close landed by --squash is not judged (no branch point; the stated boundary)" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
# h (control, ruling E-b): the second branch took spec 0001's change by merging 0001's BRANCH, not
# the trunk: refused with the remedy (the stated false refusal); after the catch-up merge of the
# trunk, the same close is accepted.
OVH="$WORK/ov-h"; e174_fixture "$OVH"; git -C "$OVH" branch spec/0001; git -C "$OVH" branch spec/0002
e174_close "$OVH" 0001 spec/0001 src/shared.txt "from A"; e174_merge "$OVH" spec/0001
# (0002 has work of its own first, as a branch in flight does; without it, its --no-ff merge of
# 0001's branch would be byte-identical to the trunk's and the same commit, the trunk's own close)
git -C "$OVH" checkout -q spec/0002; printf 'b work\n' > "$OVH/src/b-work.txt"; git -C "$OVH" add -A >/dev/null 2>&1; git -C "$OVH" -c core.hooksPath=/dev/null commit -qm "0002 work" >/dev/null 2>&1
e174_merge "$OVH" spec/0001 spec/0002; e174_close "$OVH" 0002 spec/0002 src/shared.txt "from B"; e174_merge "$OVH" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVH" 2>&1)"; OV_RC=$?
git -C "$OVH" reset -q --hard HEAD~1; e174_merge "$OVH" main spec/0002; e174_merge "$OVH" spec/0002
OV_OUT2="$(bash "$SCRIPTS/trunk-audit.sh" "$OVH" 2>&1)"; OV_RC2=$?
if [[ "$OV_RC" -ne 0 && "$OV_RC2" -eq 0 ]] && ov_refused "$OV_OUT" && ! grep -q "$OV_CODE" <<< "$OV_OUT2"; then
  ok "0174 overlap h (control, E-b): a branch that merged the earlier spec's BRANCH is refused with the remedy; after the catch-up merge of the trunk the same close is accepted"
else
  bad "0174 overlap h (control, E-b): a branch that merged the earlier spec's BRANCH is refused with the remedy; after the catch-up merge of the trunk the same close is accepted" "first rc=$OV_RC then rc=$OV_RC2: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT$OV_OUT2" | head -4 | tr '\n' ' ' | cut -c1-260)"
fi
# i (control, the live-text rule): on a page-only instance a trunk commit quotes a CLOSED row for
# spec 0001 inside a fence while 0001 stays ACTIVE; 0002, branched before it, declares a file 0001's
# spec declares. A quoted row is not a close, so nothing was closed in the window and the close is
# accepted (every page read in the audit goes through SLH_LIVE_TEXT_AWK).
OVI="$WORK/ov-i"; e174_fixture "$OVI" 2.11.0 page
printf '# Spec 0001\n\nStatus: ACTIVE\nOwns: src/shared.txt\n\n## Goal\n\nthing\n' > "$OVI/specs/0001-x.md"
git -C "$OVI" add -A >/dev/null 2>&1; git -C "$OVI" -c core.hooksPath=/dev/null commit -qm "cut 0001" >/dev/null 2>&1
git -C "$OVI" branch spec/0002
printf '\nAn example of a closed row:\n\n```\n| 0001 | A | CLOSED | example |\n```\n' >> "$OVI/specs/STATUS.md"
git -C "$OVI" add -A >/dev/null 2>&1; git -C "$OVI" -c core.hooksPath=/dev/null commit -qm "docs: an example row" >/dev/null 2>&1
e174_close "$OVI" 0002 spec/0002 src/shared.txt "from B"; e174_merge "$OVI" spec/0002
OV_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$OVI" 2>&1)"; OV_RC=$?
if [[ "$OV_RC" -eq 0 ]] && ! grep -q "$OV_CODE" <<< "$OV_OUT"; then
  ok "0174 overlap i (control): a CLOSED row quoted in a fence on the page is not a close, so the overlap is not read"
else
  bad "0174 overlap i (control): a CLOSED row quoted in a fence on the page is not a close, so the overlap is not read" "rc=$OV_RC: $(grep -E 'VIOLATION|audited' <<< "$OV_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
fi
fi; shard_region_end
# <<< SHARD-END owns-overlap-0174
