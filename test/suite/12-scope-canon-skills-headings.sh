#!/usr/bin/env bash
# test/suite/12-scope-canon-skills-headings.sh: shard 12 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE PATH-CANONICALISATION AXIS, scope hook (1.0.7)
#
# The scope hook compared the write path against the role paths as STRINGS,
# after stripping the project prefix and squeezing slashes. Two spellings of
# the same file therefore got two different answers: `src/app.js` denied, and
# `docs/../src/app.js` and `srclink/app.js` (a symlinked directory) both landed
# on the trunk in silence. `..` in a path is what a tool composing paths
# produces, and symlinked source directories are ordinary in real repositories,
# so neither needs an attacker. Same class as the pathspec checkout: a string
# that LOOKS like it is not the governed thing.
# =============================================================================

CANON="$WORK/canonical"
close_fixture "$CANON" no no answered no no true
mkdir -p "$CANON/docs" "$CANON/src"
# The symlink must point at a directory that EXISTS, or it is dangling and the
# case tests nothing. The first cut of this fixture linked to a src/ the
# fixture's trunk does not carry, the physical resolution had nothing to
# resolve, and the case passed for the pre-fix reason.
ln -s src "$CANON/srclink" 2>/dev/null
canon_verdict() { # canon_verdict <path>
  local out
  out="$(printf '%s' "$(jq -nc --arg p "$1" '{tool_name:"Edit", tool_input:{file_path:$p}}')" \
        | CLAUDE_PROJECT_DIR="$CANON" bash "$HOOKS/scope-hook.sh" 2>/dev/null)"
  if [[ "$(printf '%s' "$out" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" == "deny" ]]; then
    printf 'deny'; else printf 'allow'; fi
}
assert_true "canon0: the fixture is on the trunk" \
  "not on the trunk, so every write would be legitimately allowed and these cases would prove nothing" \
  test "$(git -C "$CANON" branch --show-current)" = "main"
if [[ "$(canon_verdict "$CANON/src/app.js")" == "deny" ]]; then
  ok "canon control: the plain spelling of a role path is denied on the trunk"
else
  bad "canon control: the plain spelling of a role path is denied on the trunk" \
      "the harness cannot observe a deny, so every case below is meaningless"
fi
CANON_FAIL=""
for p in "$CANON/docs/../src/app.js" \
         "docs/../src/app.js" \
         "$CANON/src/../src/app.js" \
         "$CANON/./docs/../src/nested/../app.js"; do
  [[ "$(canon_verdict "$p")" == "deny" ]] || CANON_FAIL="$CANON_FAIL
    $p"
done
# A symlinked role directory only counts if the link really exists: on a
# filesystem or a runner where it does not, asserting it would fail for a
# reason that has nothing to do with the gate.
if [[ -L "$CANON/srclink" ]]; then
  [[ "$(canon_verdict "$CANON/srclink/app.js")" == "deny" ]] || CANON_FAIL="$CANON_FAIL
    $CANON/srclink/app.js (symlinked role directory)"
else
  printf 'NOTE: symlinks unavailable here; the symlinked-role-directory case did not run.\n'
fi
if [[ -z "$CANON_FAIL" ]]; then
  ok "canon: uncanonicalised spellings of a role path are denied like the plain one"
else
  bad "canon: every spelling of a role path must reach the same verdict" \
      "these wrote feature code to the trunk in silence:$CANON_FAIL"
fi
CANON_ALLOW_FAIL=""
for p in "$CANON/docs/notes.md" "docs/notes.md" "$CANON/README.md" "$CANON/src/../docs/notes.md"; do
  [[ "$(canon_verdict "$p")" == "allow" ]] || CANON_ALLOW_FAIL="$CANON_ALLOW_FAIL
    $p"
done
if [[ -z "$CANON_ALLOW_FAIL" ]]; then
  ok "canon: docs-only trunk writes still pass, however they are spelled"
else
  bad "canon: docs-only trunk writes must still pass" \
      "these were denied:$CANON_ALLOW_FAIL"
fi

# =============================================================================
# EVERY SHIPPED SKILL'S FRONTMATTER PARSES (1.0.7)
#
# `design-surface` shipped from 1.0.0 through 1.0.6 with an unquoted
# colon-space inside a plain YAML scalar, so its frontmatter did not parse and
# the skill loaded at runtime with every field silently dropped: no name, no
# description, no model. Nothing caught it for seven releases because the
# publish gate ran `claude plugin validate` against the repo ROOT, where that
# argument validates marketplace.json and nothing else.
#
# So the property is asserted HERE, in the suite, where it does not depend on
# which argument someone passed to an external CLI. Deliberately parsed the
# strict way rather than the forgiving way: this is the one field whose
# breakage is invisible at runtime.
# =============================================================================

SKILL_BAD=""
SKILL_N=0
for sk in "$ROOT"/skills/*/SKILL.md; do
  [[ -f "$sk" ]] || continue
  SKILL_N=$((SKILL_N + 1))
  name="$(basename "$(dirname "$sk")")"
  # Frontmatter is the block between the first two --- lines.
  FM="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$sk")"
  if [[ -z "$FM" ]]; then
    SKILL_BAD="$SKILL_BAD
    $name: no YAML frontmatter block at all"
    continue
  fi
  # Every line must be `key: value`, and an unquoted value may not itself
  # contain a colon-space, which is what YAML reads as a nested mapping.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      [[:space:]]*) continue ;;   # continuation lines are the block-scalar form
    esac
    if ! printf '%s' "$line" | grep -qE '^[A-Za-z_-]+:[[:space:]]'; then
      SKILL_BAD="$SKILL_BAD
    $name: frontmatter line is not 'key: value': $line"
      continue
    fi
    val="$(printf '%s' "$line" | sed -E 's/^[A-Za-z_-]+:[[:space:]]*//')"
    case "$val" in
      \"*\"|\'*\'|'>'*|'|'*|'['*|'') continue ;;   # quoted, block scalar, list, empty
    esac
    if printf '%s' "$val" | grep -q ': '; then
      SKILL_BAD="$SKILL_BAD
    $name: unquoted value contains a colon-space, so YAML reads it as a mapping and the whole block is dropped: $line"
    fi
  done <<EOF
$FM
EOF
done
if [[ "$SKILL_N" -lt 5 ]]; then
  bad "skill frontmatter: the scan found the shipped skills" \
      "only $SKILL_N SKILL.md files were read; the tree carries more, so this scan is broken rather than clean"
elif [[ -z "$SKILL_BAD" ]]; then
  ok "skill frontmatter: all $SKILL_N shipped skills carry frontmatter that parses"
else
  bad "skill frontmatter: every shipped skill's frontmatter must parse" \
      "these load with all metadata silently dropped:$SKILL_BAD"
fi

# The scan is only worth anything if it can SEE the defect, so it is run
# against a reconstruction of the exact line that shipped.
FM_FIX="$WORK/fm-fixture"
mkdir -p "$FM_FIX"
printf -- '---\nname: x\ndescription: A surface (Part 5c): the routing test\n---\nbody\n' > "$FM_FIX/SKILL.md"
FM_HIT=""
FM="$(awk 'NR==1 && $0 != "---" { exit } NR>1 { if ($0 == "---") exit; print }' "$FM_FIX/SKILL.md")"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  val="$(printf '%s' "$line" | sed -E 's/^[A-Za-z_-]+:[[:space:]]*//')"
  case "$val" in \"*\"|\'*\'|'>'*|'|'*|'['*|'') continue ;; esac
  printf '%s' "$val" | grep -q ': ' && FM_HIT=1
done <<EOF
$FM
EOF
if [[ -n "$FM_HIT" ]]; then
  ok "skill frontmatter control: the scan catches the exact line that shipped in 1.0.0 through 1.0.6"
else
  bad "skill frontmatter control: the scan catches the line that shipped" \
      "it did not flag the design-surface description, so the clean result above means nothing"
fi

# =============================================================================
# >>> SHARD-BEGIN heading-markdown cost=12
if shard_region heading-markdown; then
# THE QA READER IS SCOPED, AND THE LAYERS AGREE BY OUTCOME (2.0.0 leg, F8/F3).
#
# The third fence-vs-QA-block collision. The reader matched the FIRST
# ```qa-pass-1 fence anywhere in the file, with no fence depth and no section
# scoping, and it was wrong in BOTH directions at once: a qa-pass-1 block
# NESTED inside a pasted-report fence satisfied the close condition (F8, a
# Closing report answering nothing reached the trunk and the audit called it
# clean), and an illustrative shape-quote in another section poisoned a perfect
# verdict (F3, refused at all three layers with a reason naming the wrong
# block). The trigger is cooperative both times: Appendix C says "pasted
# verbatim", and a verbatim verifier report naturally carries its own fenced
# verdict block.
#
# The byte-identity lockstep above asserts the three layers carry the same
# PROGRAM; F8 proved that is not the same as carrying the same BEHAVIOR worth
# having, because all three were wrong together, by design. So this block
# asserts agreement BY OUTCOME over a corpus: every shape is driven through
# close-gate (advisory), the armed pre-merge-commit (enforcing), and
# trunk-audit (the guarantee), and all three must land the EXPECTED side, not
# merely the same side.
# =============================================================================

qa_scope_spec() { # qa_scope_spec <shape> -> spec text on stdout
  case "$1" in
    good) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    f8nested) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- What was built: <not written yet>
- QA Pass 1 verdicts: <not run yet>
- QA Pass 1 report (pasted verbatim):

```
qa-verifier v3 report for spec 0001
Architecture diagram: no impact

```qa-pass-1
1: PASS
```
end of report
```

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    f3illustrative) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Acceptance criteria

At close, the verdict block must be written in this shape:

```qa-pass-1
<criterion>: PASS|PARTIAL|FAIL
```

## Closing report

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
    missing) cat <<'QSPEC'
# Spec 0001

Status: CLOSED

## Closing report

- QA Pass 1 report (pasted verbatim):

criterion 1: PASS

- QA Pass 2 (human): done

- Architecture diagram: no impact
QSPEC
    ;;
  esac
}

# Layer 1: close-gate, advisory. The nf_verdict shape: empty output is allow.
qa_scope_cg() { # qa_scope_cg <shape> -> allow|deny
  local d="$WORK/qa-scope-cg" o
  rm -rf "$d"; close_fixture "$d" no no answered no no true
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" commit -qm "spec body" >/dev/null 2>&1
  git -C "$d" checkout -q main
  o="$(printf '%s' "$(bash_payload 'git merge --no-ff spec/0001-thing')" | CLAUDE_PROJECT_DIR="$d" bash "$HOOKS/close-gate.sh" 2>/dev/null)"
  [[ -z "$o" ]] && { printf 'allow'; return 0; }
  printf '%s' "$o" | jq -r '.setlistAdvisory.verdict // "allow"'
}

# Layer 2: the armed pre-merge-commit, enforcing. Outcome is whether the work
# LANDED, never the printed reason.
qa_scope_slh() { # qa_scope_slh <shape> -> allow|deny
  local d="$WORK/qa-scope-slh"
  rm -rf "$d"; gh_fixture "$d" yes
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 git commit -qam "spec body" ) >/dev/null 2>&1
  git -C "$d" checkout -q main
  ( cd "$d" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
  if gh_landed "$d"; then printf 'allow'; else printf 'deny'; fi
}

# Layer 3: trunk-audit, THE guarantee. The merge is FORCED in past the hooks,
# which is exactly the route the audit exists to catch.
qa_scope_audit() { # qa_scope_audit <shape> -> allow|deny
  local d="$WORK/qa-scope-audit"
  rm -rf "$d"; gh_fixture "$d" yes
  git -C "$d" checkout -q spec/0001-thing
  qa_scope_spec "$1" > "$d/specs/0001-thing.md"
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 git commit -qam "spec body" ) >/dev/null 2>&1
  git -C "$d" checkout -q main
  ( cd "$d" && SETLIST_SKIP_HOOKS=1 GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close 0001" spec/0001-thing ) >/dev/null 2>&1
  if bash "$ROOT/scripts/trunk-audit.sh" "$d" >/dev/null 2>&1; then printf 'allow'; else printf 'deny'; fi
}

for qa_scope_case in good:allow f8nested:deny f3illustrative:allow missing:deny; do
  qs_shape="${qa_scope_case%%:*}"; qs_want="${qa_scope_case#*:}"
  qs_cg="$(qa_scope_cg "$qs_shape")"
  qs_slh="$(qa_scope_slh "$qs_shape")"
  qs_audit="$(qa_scope_audit "$qs_shape")"
  if [[ "$qs_cg" == "$qs_want" && "$qs_slh" == "$qs_want" && "$qs_audit" == "$qs_want" ]]; then
    ok "qa scope corpus: [$qs_shape] lands $qs_want at close-gate, pre-merge-commit and trunk-audit alike"
  else
    bad "qa scope corpus: [$qs_shape] lands $qs_want at close-gate, pre-merge-commit and trunk-audit alike" \
        "wanted $qs_want everywhere, measured close-gate=$qs_cg pre-merge-commit=$qs_slh trunk-audit=$qs_audit; a layer that disagrees with the expected side is either the F8 blindness or the F3 false-deny, and a layer that disagrees with its siblings has broken the lockstep by outcome"
  fi
done

# The two directions by NAME, so a regression in either reads as itself rather
# than as a corpus row. F8: the nested block must not satisfy the enforcing
# layer. F3: the illustrative block must not poison the advisory one.
if [[ "$(qa_scope_slh f8nested)" == "deny" ]]; then
  ok "qa scope F8: a qa-pass-1 block nested inside a pasted-report fence does not close a spec"
else
  bad "qa scope F8: a qa-pass-1 block nested inside a pasted-report fence does not close a spec" \
      "the armed merge landed on a Closing report whose verdicts field reads <not run yet>; this is the 2.0.0 leg's guarantee bypass, replayed"
fi
if [[ "$(qa_scope_cg f3illustrative)" == "allow" ]]; then
  ok "qa scope F3: an illustrative shape-quote outside the Closing report does not poison a real verdict"
else
  bad "qa scope F3: an illustrative shape-quote outside the Closing report does not poison a real verdict" \
      "a compliant close is refused because the reader merged every fenced block in the file; this is the 2.0.0 leg's false-deny, replayed"
fi

fi; shard_region_end
# <<< SHARD-END heading-markdown
# =============================================================================
# A HEADING IS WHAT MARKDOWN SAYS A HEADING IS (second 2.0.0 leg, F1).
#
# The scoped reader's first cut entered its heading branch on `first char is
# '#'` after stripping indentation. An issue reference on its own line
# ('#1234 was the crash this closes.'), a 4-space-indented shell snippet
# ('#!/usr/bin/env bash'), and a pasted verifier banner ('# QA run ...') each
# "closed" the Closing report section, orphaned a perfect verdict block, and a
# compliant close was refused at the gate, the hook and the audit, in lockstep,
# with a reason naming a block that was present. CommonMark: an ATX heading is
# at most 3 spaces of indent, 1 to 6 '#', then space, tab or end of line.
# The corpus below is ORDINARY AUTHOR CONTENT, not attack shapes, because the
# first corpus enumerated only the shapes its author had thought of, which is
# the population error again, in the test this time.
# =============================================================================

qa_atx_run() { # qa_atx_run <spec-text-on-stdin> -> reader state
  awk "$(grep -m1 -E '^[[:space:]]*QA_PASS1_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*QA_PASS1_AWK='//" -e "s/'$//")"
}
QA_ATX_BAD=""
qa_atx_case() { # qa_atx_case <name> <want> <spec text>
  local got
  got="$(printf '%s\n' "$3" | qa_atx_run)"
  [[ "$got" == "$2" ]] || QA_ATX_BAD="$QA_ATX_BAD
    $1: wanted $2, reader said $got"
}
qa_atx_case "issue-ref" ok '# Spec 3

## Closing report

- Architecture diagram: no impact
#1234 was the crash this closes.

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "indented-shebang" ok '# Spec 3

## Closing report

- What was built: the runner, now

    #!/usr/bin/env bash
    exec ./suite

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "indented-pasted-banner" ok '# Spec 3

## Closing report

- QA Pass 1 report (pasted verbatim):

    # QA run 2026-08-14
    ok 1 - thing

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "seven-hashes" ok '# Spec 3

## Closing report

####### not a heading in markdown either

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "no-space-hashes" ok '# Spec 3

## Closing report

##Results were fine, see above.

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
# DIRECTION CONTROLS: real headings must still end the section, or the F3 fix
# is undone. A same-level heading, a shallower one, and a fenced fake.
qa_atx_case "real-h2-ends-section" none '# Spec 3

## Closing report

## Appendix

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "real-h1-ends-section" none '# Spec 3

## Closing report

# Retrospective

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "subsection-stays-open" ok '# Spec 3

## Closing report

### details

- QA Pass 1 verdicts:

```qa-pass-1
1: PASS
```'
qa_atx_case "fenced-heading-inert" none '# Spec 3

```markdown
## Closing report
```

```qa-pass-1
1: PASS
```'
# The cheap adversary's findings 4, 5 and 10: the OPEN branch must be as
# strict as the CLOSE branch (a loose open with a strict close built sections
# nothing could ever leave), and a CRLF empty heading must still scope.
qa_atx_case "nospace-open-inert" none '##Closing report

QA was not run.

##Template example

```qa-pass-1
criterion: PASS
```'
qa_atx_case "prose-hash-open-inert" none '#Closing report is described in Part 6.

#!/usr/bin/env bash

## Template

```qa-pass-1
criterion: PASS
```'
qa_atx_case "crlf-empty-heading-scopes" none '## Closing report

x

##
'"$(printf '\r')"'
```qa-pass-1
criterion: PASS
```'
# DELIBERATE SEMANTICS, PINNED (adversary round 2, finding 5): an INDENTED or
# no-space later "heading" is not a heading per markdown, so the Closing
# report section CONTINUES through it and a verdict block after it counts.
# Every renderer shows the author continuous Closing-report content there, so
# accepting is the honest reading; the old reader's refusal was the
# non-markdown one. Pinned so a future re-tightening is judged, not drifted.
qa_atx_case "indented-later-heading-continues" ok '## Closing report

prose, then what looks like a heading but is a code block:

    ## Appendix

```qa-pass-1
1: PASS
```'
qa_atx_case "nospace-later-heading-continues" ok '## Closing report

##Appendix

```qa-pass-1
1: PASS
```'
# And the NBSP spelling agrees BYTE-WISE at both layers now: the exists-grep
# was locale-sensitive ([[:space:]] matches U+00A0 under UTF-8) while the awk
# never was, so the gate denied naming a block that was present (adversary
# round 2, finding 6). Both now read space-or-tab, so this spec has no
# Closing report section at either layer and the refusal code is the section
# one, honest.
qa_atx_case "nbsp-after-hashes-no-section" none '##'"$(printf '\302\240')"'Closing report

```qa-pass-1
1: PASS
```'
# Adversary round 3, findings 6 and 7: fences obey the same 0-3 space rule as
# headings. A 4-space backtick line is indented CODE, so it neither swallows a
# later section-closing heading (6) nor opens the verdict block early (7); the
# template's own 2-space block under a bullet still parses.
qa_atx_case "indented-fence-not-a-fence" none '## Closing report

prose:

    ```

## Appendix: unrelated

```

```qa-pass-1
x: PASS
```'
qa_atx_case "indented-example-opener-inert" ok '## Closing report

example:

    ```qa-pass-1

```qa-pass-1
login: PASS
```'
qa_atx_case "two-space-bullet-block-parses" ok '## Closing report

- QA Pass 1 verdicts:
  ```qa-pass-1
  1: PASS
  ```'
# DOCUMENTED FLAT CONTRACT, PINNED (round 4, findings 4 and 5). A line reader
# cannot honor both flat-document and list-item indentation semantics: a fence
# at four columns is a REAL fence inside a numbered list item and indented
# CODE flat. The contract is FLAT, stated in the deny text (write blocks at
# the left margin), the template and every shipped producer emit left-margin
# blocks, and both directions of the ambiguity are pinned here so a future
# list-aware widening is a judged decision against the parser-freeze doctrine.
qa_atx_case "flat-contract-nested-quoted-live" ok '## Closing report

QA Pass 1 has not been run yet. Paste a block of this shape:

1.  Run the verifier, then paste below:

    ````markdown
```qa-pass-1
login: PASS
```
    ````

Architecture diagram: n/a'
qa_atx_case "flat-contract-list-indented-block-unread" none '## Closing report

1.  Ran QA Pass 1. Verdict block:

    ```qa-pass-1
    login: PASS
    ```

Architecture diagram: no impact'
# Round 5, findings 7 and 8: the TEMPLATE-FENCE STRIPPER obeys the same
# 0-3-space rule, or an indented fence marker deletes the rest of the spec
# before any reader sees it (a margin block refused as no-section) and an
# indented pseudo-quote deletes a margin heading (an appendix demo accepted).
# These two run the full stripper-then-reader pipeline, unlike the reader-only
# battery above.
QA_STRIP_BAD=""
qa_strip_case() { # qa_strip_case <name> <want> <<'SPEC'
  local name="$1" want="$2" f="$WORK/qa-strip-$1" got
  cat > "$f"
  got="$(awk "$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")" "$f" | qa_atx_run)"
  [[ "$got" == "$want" ]] || QA_STRIP_BAD="$QA_STRIP_BAD
    $name: wanted $want, pipeline said $got"
}
qa_strip_case indented-marker-not-a-fence ok <<'SPEC'
# Spec 0001

## Notes

The verdict block is opened with a line reading:

    ```qa-pass-1

and closed with the same marker.

## Closing report

Architecture diagram: no impact

```qa-pass-1
crit-one: PASS
```
SPEC
qa_strip_case indented-quote-cannot-eat-heading none <<'SPEC'
# Spec 0001

## Closing report

Architecture diagram: no impact

QA Pass 1 was not run; the block is in the appendix.

    ```text
    ## Closing report  (quoted from the template)
## Appendix A
    ```

```qa-pass-1
demo-only: PASS
```
SPEC
qa_strip_case margin-template-quote-still-dropped ok <<'SPEC'
# S

```markdown
## Closing report
template text
```

## Closing report

```qa-pass-1
1: PASS
```
SPEC
if [[ -z "$QA_STRIP_BAD" ]]; then
  ok "qa stripper corpus: the fence stripper obeys the 0-3-space rule, 5 shapes through the full pipeline"
else
  bad "qa stripper corpus: the fence stripper obeys the 0-3-space rule, 5 shapes through the full pipeline" \
      "the stripper and the reader disagree about what a fence is:$QA_STRIP_BAD"
fi
# Round 6, finding 4, DOCUMENTED as flat-correct and pinned: a fence whose
# closer is 4-space-indented does not close in ANY renderer (CommonMark:
# closing fences may be indented at most 3), so the tail of such a spec,
# Closing report included, genuinely IS code and refusing it as no-section is
# the honest flat reading. The previous release's acceptance was the wrong
# reading. R6-6 beside it: a formfeed after the hashes is not space-or-tab,
# so the grep and the awk now agree the section is absent.
qa_strip_case unclosed-fence-tail-is-code none <<'SPEC'
# Spec

```text
example
    ```

## Closing report

```qa-pass-1
login: PASS
```
SPEC
printf '## \fClosing report\n\n```qa-pass-1\nlogin: PASS\n```\n' > "$WORK/qa-strip-formfeed"
QA_STRIP_FF="$(awk "$(grep -m1 -E '^[[:space:]]*TEMPLATE_FENCE_AWK=' "$HOOKS/close-gate.sh" | sed -e "s/^[[:space:]]*TEMPLATE_FENCE_AWK='//" -e "s/'$//")" "$WORK/qa-strip-formfeed" | qa_atx_run)"
[[ "$QA_STRIP_FF" == "none" ]] || QA_STRIP_BAD="$QA_STRIP_BAD
    formfeed-heading-no-section: wanted none, pipeline said $QA_STRIP_FF (a REAL formfeed byte, printf-built because a quoted heredoc would have tested the literal string)"
# Round 7, finding 2: a fence is a fence in either CommonMark spelling. The
# edition says "a fenced block whose info string is qa-pass-1"; tilde fences
# and longer backtick runs are exactly that, and a tilde fence is the ordinary
# wrapper for content containing backticks.
qa_atx_case "four-backtick-fence-accepted" ok '## Closing report

````qa-pass-1
c1: PASS
````'
qa_atx_case "tilde-fence-accepted" ok '## Closing report

~~~qa-pass-1
c1: PASS
~~~'
# Round 7, finding 3, DOCUMENTED and pinned: two agreed loose readings, both
# harmless direction, both layers agreeing, kept per the freeze doctrine. A
# prefix section title still contains the section; a spaced info string
# collapsing to qa-pass-1 is generosity toward the author, not a hole.
qa_atx_case "prefix-section-title-pinned" ok '## Closing reports of prior work

```qa-pass-1
c1: PASS
```'
qa_atx_case "spaced-info-string-pinned" ok '## Closing report

``` qa-pass -1
c1: PASS
```'
# Round 10, findings 1 and 2: the reader matched a REFERENCE CommonMark parser
# across the cases a line reader can decide, and fails CLOSED where it cannot.
# R10-2 is F8/F3 re-opened: a line STARTING with an inline code span of three
# or more backticks (```qa-pass-1``` in prose, exactly how Part 6's fence label
# reads) is NOT a fence in CommonMark (an opening backtick fence's info string
# may not contain a backtick), so the reader now rejects it and its depth stays
# synced; a nested block cannot be promoted and a later-section example cannot
# leak. R10-1: the HTML-comment opener obeys the same 0-3-space rule as fences
# and headings, so an indented (code-block) comment marker is content; and an
# UNCLOSED comment REFUSES rather than swallowing to EOF, which closes the
# one case a line reader cannot otherwise resolve (a comment opened inside a
# list item) in the fail-safe direction.
# REORDERED FOR FIRST-BLOCK-WINS (F7-2026, ruled 2026-08-29), not just re-graded.
# These two shapes used a good first block and a bad SECOND one, so under
# last-block-wins the second decided and the case read `malformed`. Under
# first-block-wins a trailing block cannot decide anything, so simply flipping
# the expectation to `ok` would have left the construction under test unable to
# change the answer: a green labelled with the verdict instead of the evidence.
# The construction now comes BEFORE the only real verdict, which is where it can
# still discriminate: read as a fence opener, it would mis-scope and the reader
# would not say `ok`.
qa_atx_case "backtick-info-not-a-fence" ok '## Closing report

```` ```qa-pass-1 ```` is the fence you need.

```qa-pass-1
smoke: PASS
```'
qa_atx_case "backtick-info-nested-not-promoted" none '## Closing report

```qa-pass-1``` is the fence label used below.

````
$ setlist verify
```qa-pass-1
smoke: PASS
```
(verifier exited 0)
````'
qa_atx_case "backtick-info-section-no-leak" none '## Closing report

QA Pass 1 has not been run yet.

```qa-pass-1``` is the fence label required by Part 6.

## Appendix A

```text
(shape)
```

```qa-pass-1
example: PASS
```'
qa_atx_case "indented-comment-is-content" ok '## Closing report

    <!-- reviewer note kept verbatim in a code block

```qa-pass-1
smoke: PASS
```'

# F7-2026's DIRECTION, asserted both ways. A trailing block cannot replace a
# real verdict, and a MALFORMED first block is not rescued by a good second.
qa_atx_case "first-block-wins-example-after" ok '## Closing report

```qa-pass-1
smoke: PASS
```

An illustrative block, which is not a verdict:

```qa-pass-1
this line is prose
```'
qa_atx_case "first-block-wins-bad-first" malformed '## Closing report

```qa-pass-1
this line is prose
```

```qa-pass-1
smoke: PASS
```'
qa_atx_case "unclosed-comment-refuses" unclosed-comment '## Closing report

```qa-pass-1
smoke: PASS
```

- reviewer note

  <!-- internal: do not ship

```qa-pass-1
smoke: regressed
```'
# KNOWN LIMITATION, PINNED (adversary finding 9): setext headings (a line
# underlined with ---- or ====) do not end the section. Markdown calls them
# headings; the reader reads ATX only, the framework's own documents write
# ATX only, and widening the reader is exactly the parser-repair class the
# freeze doctrine prices. Pinned GREEN so a future widening fails here loudly
# and gets judged rather than slipping in.
qa_atx_case "setext-pinned-limitation" ok '## Closing report

No QA was run.

Appendix
--------

```qa-pass-1
criterion: PASS
```'
if [[ -z "$QA_ATX_BAD" ]]; then
  ok "qa heading corpus: ordinary #-prose is content, real headings still scope, 31 shapes"
else
  bad "qa heading corpus: ordinary #-prose is content, real headings still scope, 31 shapes" \
      "the reader and markdown disagree about what a heading is:$QA_ATX_BAD"
fi

# End to end: a spec whose only Closing heading is the no-space spelling has,
# per markdown, NO Closing report section, and the unified exists-grep says so
# with the honest code rather than letting the loose-open reader accept a
# fenced example from a section nothing could close (adversary finding 4).
NSC="$WORK/qa-nospace-close"; rm -rf "$NSC"; close_fixture "$NSC" no no answered no no true
git -C "$NSC" checkout -q spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n##Closing report\n\n- QA Pass 1 verdicts:\n\n```qa-pass-1\n1: PASS\n```\n\n- Architecture diagram: no impact\n' > "$NSC/specs/0001-thing.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$NSC/specs/STATUS.md"
git -C "$NSC" add -A >/dev/null 2>&1; git -C "$NSC" commit -qm ns >/dev/null 2>&1
git -C "$NSC" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$NSC" "$(bash_payload "$MERGE_CMD")"
expect_deny "qa heading e2e: a no-space ##Closing report is not a section, refused with the section code" "CG-NO-CLOSING-REPORT"

