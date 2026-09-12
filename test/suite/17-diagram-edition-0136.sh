#!/usr/bin/env bash
# test/suite/17-diagram-edition-0136.sh: shard 17 of the hook test suite, SOURCED by
# test/run-tests.sh (spec 0133's file-order split). Not a program of its own: every
# helper it calls is defined in the driver or in an earlier shard.

# =============================================================================
# THE DIAGRAM EDITION'S MECHANISM (spec 0136), built to the contract in
# specs/0135-diagram-edition-design-intake.md as amended by the owner's rulings
# S1 to S4 of 2026-09-10.
#
# WHAT THESE ASSERTIONS ARE EVIDENCE OF, in one sentence each:
#
#   - that an instance which has NOT opted in behaves exactly as v1.14, proven by
#     running the SHIPPED v1.14 library and audit beside the new ones over the
#     same corpus and requiring byte-identical output (the differential, not an
#     assertion that the code "returns early");
#   - that the switch is read in the FIRST PARENT's tree (ruling S2), which is
#     what makes history before adoption unarmed and the baseline chore that
#     creates docs/diagrams/ un-judged by the checks it turns on;
#   - that each new refusal fires on the input it exists for and is SILENT on the
#     corrected input, both directions, because a check only ever watched red is
#     a check nobody has seen work;
#   - that the stale-node resolver's two verdicts split by WHOSE node it is
#     (D11), and that a label it cannot resolve is PRINTED rather than skipped in
#     silence (S4);
#   - that FC-STRICT-NOT-REQUIRED refuses under forge custody, reports under
#     every other, and does NOT fire where FC-CHECK-NOT-REQUIRED fires (S3);
#   - that the render step refuses a block that does not parse and REPORTS the
#     absence of a renderer, with a stub renderer on PATH so .github/workflows/
#     test.yml does not move (KL8 stays recorded);
#   - that the readers the library and the audit share are byte-identical, so the
#     gate and its backstop cannot go blind the same way at the same time.
#
# THE RED WATCH for every arm below is recorded in spec 0136's Progress with the
# output quoted: each was driven against a crafted fixture before the arm existed
# and again after, and the differential was run against the 79549f2 bytes.
# =============================================================================

DG_LIB="$ROOT/templates/git-hooks/setlist-hook-lib.sh"
DG_AUDIT="$ROOT/scripts/trunk-audit.sh"

# An instance armed or not, with one role file, one spec and a structure.md whose
# Mermaid block draws a path that DOES exist, so the fixtures below add staleness
# deliberately rather than inheriting it.
dg_fixture() { # dg_fixture <dir>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.claude" "$d/src/auth" "$d/specs" "$d/steering"
  git_init "$d" main
  printf '{"scaffolded":true,"trunk":"main","gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf 'seed\n' > "$d/src/auth/main.txt"
  printf '# structure\n\nprose\n\n```mermaid\ngraph TD\n  a["src/auth"] --> b["src/auth"]\n```\n' > "$d/steering/structure.md"
  printf '# inv\n\n| Num | Title | Status |\n| --- | --- | --- |\n| 0001 | Thing | OPEN |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "seed" >/dev/null 2>&1
}

dg_arm() { # dg_arm <dir> : the baseline chore commit that CREATES docs/diagrams/
  local d="$1"
  mkdir -p "$d/docs/diagrams/components"
  printf 'Shows: the context\nAltitude: L1\nSynced by: chore diagram-baseline\nEncodes: the boundary\n\n```mermaid\ngraph TD\n  a["src/auth"]\n```\n' > "$d/docs/diagrams/context.md"
  git -C "$d" add -A >/dev/null; git -C "$d" -c core.hooksPath=/dev/null commit -qm "chore diagram-baseline" >/dev/null 2>&1
}

dg_stage_close() { # dg_stage_close <dir> <field-line>
  local d="$1" f="$2"
  { printf '# Spec - a\nOwns: src/auth/main.txt\n\n## Closing report\n%s\n\n' "$f"
    printf '```qa-pass-1\ncrit: PASS\n```\n'; } > "$d/specs/0001-a.md"
  printf '# inv\n\n| Num | Title | Status |\n| --- | --- | --- |\n| 0001 | Thing | CLOSED |\n' > "$d/specs/STATUS.md"
  git -C "$d" add -A >/dev/null
}

# The close verification, driven directly out of a NAMED library so the same
# corpus can be put to the shipped v1.14 bytes and to this tree's.
dg_verify() { # dg_verify <library> <dir> -> stdout+stderr of one close verification, plus REFUSED=n
  local lib="$1" d="$2"
  bash -c '
    set -u
    SLH_REFUSED=0
    SLH_CLOSE_SINGLE_PARENT=1
    # shellcheck disable=SC1090
    . "$1"
    SLH_REFUSED=0
    slh_verify_close "$2" main "the close"
    echo "REFUSED=$SLH_REFUSED"
  ' _ "$lib" "$d" 2>&1
}

# >>> SHARD-BEGIN diagram-absence-0136 cost=14
if shard_region diagram-absence-0136; then

# --- THE ABSENCE DIFFERENTIAL, WHICH IS THE WHOLE OPT-IN CLAIM ---------------
#
# "Absent, every reader behaves exactly as v1.14" is the sentence the edition
# sells and the one an upgrading instance is entitled to. It is proven by
# RUNNING the shipped bytes, not by reading the new ones: the v1.14 library and
# audit are extracted from the commit that shipped them and put to the same
# corpus, and the outputs must match byte for byte.
# THE OLD BYTES ARE A VENDORED FIXTURE, NOT A GIT READ (fixed 2026-09-10 after
# CI went red on it). The first cut recovered them with `git show 79549f2:...`,
# which works in a clone and returns nothing inside the mutation check, because
# that harness copies the tree somewhere with no repository history: the
# differential passed on the developer's machine and failed on the Linux runner.
# A fixture travels with the suite and runs wherever the suite runs, which is the
# same method and the same reason as test/fixtures/pre-record-hooks/.
DG_PRE="$ROOT/test/fixtures/pre-diagram-hooks"
DG_V114_LIB="$DG_PRE/setlist-hook-lib.sh"
DG_V114_AUDIT="$DG_PRE/trunk-audit.sh"
if [[ -s "$DG_V114_LIB" && -s "$DG_V114_AUDIT" ]] && ! grep -q 'slh_diagram_switch_on' "$DG_V114_LIB"; then
  ok "diagram absence: the vendored pre-diagram carriers are present and carry no diagram half, so the differential compares two generations"
  DG_DIFF_BAD=0; DG_DIFF_N=0
  for DG_F in 'Architecture diagram: updated in this commit' \
              'Architecture diagram: no impact' \
              'Architecture diagram: updated (docs/diagrams/components/auth.md)' \
              'Architecture diagram: TBD' \
              'Architecture diagram: <updated in this commit | no impact>' \
              'Architecture diagram:'; do
    DG_DIFF_N=$((DG_DIFF_N + 1))
    DG_D="$WORK/dg-abs-$DG_DIFF_N"; dg_fixture "$DG_D"
    printf 'x\n' >> "$DG_D/src/auth/main.txt"; dg_stage_close "$DG_D" "$DG_F"
    if [[ "$(dg_verify "$DG_V114_LIB" "$DG_D")" != "$(dg_verify "$DG_LIB" "$DG_D")" ]]; then
      DG_DIFF_BAD=$((DG_DIFF_BAD + 1))
    fi
    # the audit over the same commit, both versions
    git -C "$DG_D" -c core.hooksPath=/dev/null commit -qm "close 0001" >/dev/null 2>&1
    if [[ "$(bash "$DG_V114_AUDIT" "$DG_D" 2>&1)" != "$(bash "$DG_AUDIT" "$DG_D" 2>&1)" ]]; then
      DG_DIFF_BAD=$((DG_DIFF_BAD + 1))
    fi
  done
  if [[ "$DG_DIFF_BAD" -eq 0 ]]; then
    ok "diagram absence: an instance with no docs/diagrams/ is byte-identical to v1.14 at both layers over $DG_DIFF_N field forms"
  else
    bad "diagram absence: an instance with no docs/diagrams/ is byte-identical to v1.14 at both layers over $DG_DIFF_N field forms" \
        "$DG_DIFF_BAD of $((DG_DIFF_N * 2)) comparisons differed"
  fi
else
  bad "diagram absence: the vendored pre-diagram carriers are present and carry no diagram half" \
      "test/fixtures/pre-diagram-hooks/ is missing, empty, or already carries the diagram half; the differential is the opt-in claim and is never skipped"
fi

# --- THE SWITCH IS THE FIRST PARENT'S TREE (ruling S2) -----------------------
#
# Three cases, and the middle one is the reason the rule exists: the commit that
# CREATES docs/diagrams/ must not be judged by the checks it enables, or the
# baseline chore is the first thing the edition refuses.
DG_S2="$WORK/dg-s2"; dg_fixture "$DG_S2"
printf 'x\n' >> "$DG_S2/src/auth/main.txt"; dg_stage_close "$DG_S2" 'Architecture diagram: no impact'
if [[ "$(dg_verify "$DG_LIB" "$DG_S2")" == *"REFUSED=0"* ]]; then
  ok "S2 a: a close BEFORE adoption is unarmed and passes"
else
  bad "S2 a: a close BEFORE adoption is unarmed and passes" "it refused"
fi

DG_S2B="$WORK/dg-s2b"; dg_fixture "$DG_S2B"
printf 'x\n' >> "$DG_S2B/src/auth/main.txt"
mkdir -p "$DG_S2B/docs/diagrams"
printf 'Shows: c\nAltitude: L1\nSynced by: chore\nEncodes: e\n\n```mermaid\ngraph TD\n  z["src/gone"] %%%% spec 0001\n```\n' > "$DG_S2B/docs/diagrams/context.md"
dg_stage_close "$DG_S2B" 'Architecture diagram: no impact'
if [[ "$(dg_verify "$DG_LIB" "$DG_S2B")" == *"REFUSED=0"* ]]; then
  ok "S2 b: the baseline commit that CREATES docs/diagrams/ is not judged by the checks it enables"
else
  bad "S2 b: the baseline commit that CREATES docs/diagrams/ is not judged by the checks it enables" \
      "it refused; the first parent's tree is what arms the checks"
fi

DG_S2C="$WORK/dg-s2c"; dg_fixture "$DG_S2C"; dg_arm "$DG_S2C"
printf 'x\n' >> "$DG_S2C/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_S2C/docs/diagrams/components/auth.md"
dg_stage_close "$DG_S2C" 'Architecture diagram: no impact'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_S2C")"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-UNDECLARED"* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "S2 c: the FIRST close after adoption is armed and refuses an undeclared diagram"
else
  bad "S2 c: the FIRST close after adoption is armed and refuses an undeclared diagram" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

# THE DELETION CASE, decided rather than discovered (S2's last clause). The
# commit that REMOVES the switch still has an armed first parent, so it is still
# judged; the commit after it is back to v1.14 exactly.
DG_S2D="$WORK/dg-s2d"; dg_fixture "$DG_S2D"; dg_arm "$DG_S2D"
printf 'x\n' >> "$DG_S2D/src/auth/main.txt"
git -C "$DG_S2D" rm -rq docs/diagrams >/dev/null 2>&1
dg_stage_close "$DG_S2D" 'Architecture diagram: no impact'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_S2D")"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-UNDECLARED"* ]]; then
  ok "S2 d: the commit that DELETES the switch is still judged, so diagrams cannot be removed undeclared"
else
  bad "S2 d: the commit that DELETES the switch is still judged, so diagrams cannot be removed undeclared" \
      "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END diagram-absence-0136

# 16 profiled 2026-09-02 (spec 0127), raised by a measured 4 for spec 0139's cases: four
# git fixtures and two extra staged closes, the fixtures alone timed at 2s on the same host
# class. The hint is advisory, so a stale number costs wall clock and never an assertion;
# it must also end the line, because the region id is the marker with ` cost=N` stripped
# from the END and a trailing comment would become part of the id.
# >>> SHARD-BEGIN diagram-field-nodes-0136 cost=27
if shard_region diagram-field-nodes-0136; then

# --- THE TWO FIELD CHECKS, BOTH DIRECTIONS -----------------------------------
DG_A="$WORK/dg-claim"; dg_fixture "$DG_A"; dg_arm "$DG_A"
printf 'x\n' >> "$DG_A/src/auth/main.txt"
dg_stage_close "$DG_A" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_A")"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-CLAIM"* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "field a: 'updated' naming a file the commit does not touch refuses as SLH-DIAGRAM-CLAIM"
else
  bad "field a: 'updated' naming a file the commit does not touch refuses as SLH-DIAGRAM-CLAIM" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

dg_stage_close "$DG_A" 'Architecture diagram: no impact'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_A")"
if [[ "$DG_OUT" == *"REFUSED=0"* ]]; then
  ok "field a2: the same commit answering 'no impact' truthfully passes (the check is silent when the claim is true)"
else
  bad "field a2: the same commit answering 'no impact' truthfully passes" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

# THE OLD FILE-LESS FORM ON AN ARMED INSTANCE: a claim that names nothing cannot
# be checked, so it is refused rather than read as an answer.
dg_stage_close "$DG_A" 'Architecture diagram: updated in this commit'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_A")"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-CLAIM"* && "$DG_OUT" == *"names no files"* ]]; then
  ok "field b: the v1.14 file-less form on an ARMED instance refuses as a claim that names nothing"
else
  bad "field b: the v1.14 file-less form on an ARMED instance refuses as a claim that names nothing" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

# --- NODE EVIDENCE: the two verdicts split by WHOSE node it is (D11) ---------
DG_N="$WORK/dg-node"; dg_fixture "$DG_N"; dg_arm "$DG_N"
printf 'x\n' >> "$DG_N/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"] --> r["src/nonexistent"] %%%% spec 0001\n```\n' > "$DG_N/docs/diagrams/components/auth.md"
dg_stage_close "$DG_N" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_N")"
if [[ "$DG_OUT" == *"setlist [SLH-DIAGRAM-STALE-NODE]"* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "node a: a stale node the CLOSING spec drew refuses (D11's first verdict)"
else
  bad "node a: a stale node the CLOSING spec drew refuses (D11's first verdict)" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"] --> r["src/nonexistent"] %%%% spec 0009\n```\n' > "$DG_N/docs/diagrams/components/auth.md"
dg_stage_close "$DG_N" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_N")"
if [[ "$DG_OUT" == *"setlist report [SLH-DIAGRAM-STALE-NODE]"* && "$DG_OUT" == *"REFUSED=0"* ]]; then
  ok "node b: a stale node an EARLIER spec drew is REPORTED and does not refuse (D11's second verdict)"
else
  bad "node b: a stale node an EARLIER spec drew is REPORTED and does not refuse (D11's second verdict)" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

# S4: A SKIP IS PRINTED. The count, the ids up to ten, and "and N more" beyond,
# on this project's own scan_exclusions rule that a skip nobody is told about is
# a hole one directory over.
DG_S="$WORK/dg-skip"; dg_fixture "$DG_S"; dg_arm "$DG_S"
printf 'x\n' >> "$DG_S/src/auth/main.txt"
{ printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n'
  for DG_I in $(seq 1 14); do printf '  n%s["Label %s"]\n' "$DG_I" "$DG_I"; done
  printf '```\n'; } > "$DG_S/docs/diagrams/components/auth.md"
dg_stage_close "$DG_S" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_S")"
# The listed form gained the KIND in spec 0139, so each line reads
# `<file>: node "Label N"` rather than `<file>: Label N`: a report that named
# every drawn name a node label was the defect that spec fixed.
DG_LISTED="$(printf '%s\n' "$DG_OUT" | grep -c '  docs/diagrams/components/auth.md: node "Label ' || true)"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-NODE-SKIPPED"* && "$DG_OUT" == *"14 drawn names are not path-shaped"* \
      && "$DG_LISTED" -eq 10 && "$DG_OUT" == *"and 4 more"* && "$DG_OUT" == *"REFUSED=0"* ]]; then
  ok "S4: 14 non-path-shaped names are reported with the count, ten named with their kind and 'and 4 more', and refuse nothing"
else
  bad "S4: 14 non-path-shaped names are reported with the count, ten named with their kind and 'and 4 more', and refuse nothing" \
      "listed=$DG_LISTED; $(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-220)"
fi

# --- DE6, SPEC 0139: A DRAWN NAME COMES ONLY FROM A DECLARATION --------------
#
# The owner's ruling of 2026-09-11 on DE6, filed by spec 0138 at its STOP 1 and
# fixed here because a refusal that fires on ordinary Mermaid at the GUARANTEE
# layer is the class this project has twice removed checks over. Each case below
# was watched RED against the 240a0f7 library first, with the output quoted in
# spec 0139's Progress, and each is the defect's shape rather than its probe.

# THE EXTRACTOR ITSELF, read directly, because every case below depends on what
# it emits and a fixture can pass for the wrong reason. Three fields now, and the
# KIND is what lets the messages name their own subject.
DG_G="$(printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart LR\n  a["src/a"] -->|"reads (src/gone/x.json), sync"| b["src/b"] %%%% spec 0142\n  subgraph src/sg["a title"]\n    c(("src/c")); d[("src/d")]\n  end\n```\n' \
        | awk "$(bash -c '. "$1" >/dev/null 2>&1; printf "%s" "$SLH_DIAGRAM_NODE_AWK"' _ "$DG_LIB")")"
DG_WANT="$(printf '0142\tnode\tsrc/a\n0142\tnode\tsrc/b\n-\tsubgraph id\tsrc/sg\n-\tsubgraph title\ta title\n-\tnode\tsrc/c\n-\tnode\tsrc/d')"
if [[ "$DG_G" == "$DG_WANT" ]]; then
  ok "0139 extractor: six drawn names in three kinds, and the edge label's parenthesised path is not one of them"
else
  bad "0139 extractor: six drawn names in three kinds, and the edge label's parenthesised path is not one of them" \
      "got [$(printf '%s' "$DG_G" | tr '\n\t' '; ')]"
fi

# CASE 1, THE PROBE DE6 NAMED: a parenthesised path inside an EDGE label was
# attributed to the closing spec and refused as a stale node nobody drew.
DG_E="$WORK/dg-edgelabel"; dg_fixture "$DG_E"; dg_arm "$DG_E"
printf 'x\n' >> "$DG_E/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart LR\n  a["src/auth"] -->|"reads (src/gone/config.json), sync"| b["src/auth/main.txt"] %%%% spec 0001\n```\n' > "$DG_E/docs/diagrams/components/auth.md"
dg_stage_close "$DG_E" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_E")"
if [[ "$DG_OUT" == *"REFUSED=0"* && "$DG_OUT" != *"SLH-DIAGRAM-STALE-NODE"* && "$DG_OUT" != *"SLH-DIAGRAM-NODE-SKIPPED"* ]]; then
  ok "0139 a: a parenthesised path inside an edge label is not a node, and the close is SILENT (DE6's false refusal)"
else
  bad "0139 a: a parenthesised path inside an edge label is not a node, and the close is SILENT" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# A MERMAID COMMENT IS NOT A DECLARATION EITHER, the same rule one character over.
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart LR\n  a["src/auth"] %%%% spec 0001 and a note about (src/gone/note.json)\n```\n' > "$DG_E/docs/diagrams/components/auth.md"
dg_stage_close "$DG_E" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_E")"
if [[ "$DG_OUT" == *"REFUSED=0"* && "$DG_OUT" != *"SLH-DIAGRAM-"* ]]; then
  ok "0139 a2: a path named inside a %% comment is not a node, and the close is SILENT"
else
  bad "0139 a2: a path named inside a %% comment is not a node, and the close is SILENT" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# CASE 2, THE SILENCE: a subgraph id and its title are drawn names. Path-shaped
# and stale refuses by its KIND; path-shaped and true is quiet; neither shape is
# reported. Before this, a stale subgraph id emitted NOTHING AT ALL, which is the
# third outcome the skill's "every unresolved name is PRINTED" sentence forbids.
DG_SG="$WORK/dg-subgraph"; dg_fixture "$DG_SG"; dg_arm "$DG_SG"
printf 'x\n' >> "$DG_SG/src/auth/main.txt"
{ printf 'Shows: x\nAltitude: L2\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart TB\n'
  printf '  subgraph src/auth["the auth layer"]\n    h["src/auth/main.txt"]\n  end\n'
  printf '  subgraph src/gone %%%% spec 0001\n    g["src/auth"]\n  end\n'
  printf '  subgraph Legend\n    l["src/auth"]\n  end\n'
  printf '```\n'; } > "$DG_SG/docs/diagrams/components/layers.md"
dg_stage_close "$DG_SG" 'Architecture diagram: updated (docs/diagrams/components/layers.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_SG")"
if [[ "$DG_OUT" == *'draws a subgraph id "src/gone"'* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "0139 b: a path-shaped subgraph id the closing spec drew and the tree does not have REFUSES, naming it a subgraph id"
else
  bad "0139 b: a path-shaped subgraph id the closing spec drew and the tree does not have REFUSES, naming it a subgraph id" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi
if [[ "$DG_OUT" == *'2 drawn names are not path-shaped'* \
      && "$DG_OUT" == *'subgraph title "the auth layer"'* && "$DG_OUT" == *'subgraph id "Legend"'* \
      && "$DG_OUT" != *'"src/auth"'* ]]; then
  ok "0139 b2: the non-path-shaped title and id are PRINTED with their kinds, and the path-shaped TRUE id is silent"
else
  bad "0139 b2: the non-path-shaped title and id are PRINTED with their kinds, and the path-shaped TRUE id is silent" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# CASE 3, WHAT MUST STAY QUIET: several nodes on one line, and the compound
# shapes. A single-pair reader gave `(("src/auth` for a circle node, which is
# path-shaped with no whitespace, so every circle, cylinder and stadium node in
# an instance was a false refusal waiting to be drawn.
DG_Q="$WORK/dg-quiet"; dg_fixture "$DG_Q"; dg_arm "$DG_Q"
printf 'x\n' >> "$DG_Q/src/auth/main.txt"
{ printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart LR\n'
  printf '  p["src/auth"]; q["src/auth/main.txt"] --> r(("src/auth"))\n'
  printf '  s[("src/auth")] --> t(["src/auth"]) %%%% spec 0001\n'
  printf '  u[["src/auth"]] --> v[/"src/auth"/]\n'
  printf '```\n'; } > "$DG_Q/docs/diagrams/components/quiet.md"
dg_stage_close "$DG_Q" 'Architecture diagram: updated (docs/diagrams/components/quiet.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_Q")"
if [[ "$DG_OUT" == *"REFUSED=0"* && "$DG_OUT" != *"SLH-DIAGRAM-"* ]]; then
  ok "0139 c: seven true nodes across three lines in six Mermaid shapes are SILENT, compound shapes included"
else
  bad "0139 c: seven true nodes across three lines in six Mermaid shapes are SILENT, compound shapes included" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# AND THE ACCUSING DIRECTION STILL ACCUSES, which is the half a narrowing fix can
# quietly lose: a node label the closing spec drew and the tree does not have.
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart LR\n  p((("src/still-gone"))) %%%% spec 0001\n```\n' > "$DG_Q/docs/diagrams/components/quiet.md"
dg_stage_close "$DG_Q" 'Architecture diagram: updated (docs/diagrams/components/quiet.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_Q")"
if [[ "$DG_OUT" == *'draws a node "src/still-gone"'* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "0139 c2: a stale path in a COMPOUND shape still refuses, read clean of its shape punctuation"
else
  bad "0139 c2: a stale path in a COMPOUND shape still refuses, read clean of its shape punctuation" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# THE AUDIT'S OWN CONSUMER, which the lockstep assertion does NOT cover: the
# byte-identical block ends before `audit_diagram_nodes`, so the audit reads the
# reader's three fields in code of its own. A library updated alone would leave
# the backstop reading `kind` as the label. Measured: the pre-fix audit reported
# this history as "2 clean, 0 violations", total silence at the layer that exists
# to catch what the hook missed.
DG_AN="$WORK/dg-audit-nodes"; dg_fixture "$DG_AN"; dg_arm "$DG_AN"
printf 'x\n' >> "$DG_AN/src/auth/main.txt"
{ printf 'Shows: x\nAltitude: L2\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\nflowchart TB\n'
  printf '  subgraph src/gone %%%% spec 0001\n    g["src/auth"]\n  end\n'
  printf '  subgraph Legend\n    l["src/auth"]\n  end\n'
  printf '```\n'; } > "$DG_AN/docs/diagrams/components/layers.md"
dg_stage_close "$DG_AN" 'Architecture diagram: updated (docs/diagrams/components/layers.md)'
git -C "$DG_AN" -c core.hooksPath=/dev/null commit -qm "close 0001 with a stale subgraph id" >/dev/null 2>&1
DG_OUT="$(bash "$DG_AUDIT" "$DG_AN" 2>&1)"
if [[ "$DG_OUT" == *"diagram-stale-node(docs/diagrams/components/layers.md:src/gone)"* ]]; then
  ok "0139 d: the AUDIT's own consumer reads the kind field, so a stale subgraph id is a violation there too and not silence"
else
  bad "0139 d: the AUDIT's own consumer reads the kind field, so a stale subgraph id is a violation there too" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi
if [[ "$DG_OUT" == *"1 drawn name(s) at this commit (nodes, subgraph ids, subgraph titles) are not path-shaped"* ]]; then
  ok "0139 d2: the audit's skip report names the three classes it covers rather than calling them all node labels"
else
  bad "0139 d2: the audit's skip report names the three classes it covers" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-240)"
fi

# --- THE GENERATED VIEW AS A LOCKFILE ----------------------------------------
DG_L="$WORK/dg-lock"; dg_fixture "$DG_L"
# The command is a SCRIPT in the fixture, not a JSON-escaped one-liner: the
# escaping needed to put a printf with newlines through bash, JSON and jq is
# three layers of quoting nobody can read, and the first cut of this fixture got
# it wrong in a way that looked like a mechanism defect.
printf '#!/usr/bin/env bash\nprintf "\`\`\`mermaid\\ngraph TD\\n  a[\\"src/auth\\"]\\n\`\`\`\\n"\n' > "$DG_L/.claude/gen.sh"
chmod +x "$DG_L/.claude/gen.sh"
printf '{"scaffolded":true,"trunk":"main","gate_command":"true","diagram_command":"bash .claude/gen.sh","roles":{"src":"src","tests":"tests"}}\n' > "$DG_L/.claude/sdd.json"
mkdir -p "$DG_L/docs/diagrams/generated"
printf '```mermaid\ngraph TD\n  a["src/OLD"]\n```\n' > "$DG_L/docs/diagrams/generated/view.md"
git -C "$DG_L" add -A >/dev/null; git -C "$DG_L" -c core.hooksPath=/dev/null commit -qm "declare diagram_command" >/dev/null 2>&1
printf 'x\n' >> "$DG_L/src/auth/main.txt"
dg_stage_close "$DG_L" 'Architecture diagram: no impact'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_L")"
if [[ "$DG_OUT" == *"SLH-DIAGRAM-DRIFT"* && "$DG_OUT" == *"REFUSED=1"* ]]; then
  ok "lockfile a: a committed generated view that differs from the command's output refuses as SLH-DIAGRAM-DRIFT"
else
  bad "lockfile a: a committed generated view that differs from the command's output refuses as SLH-DIAGRAM-DRIFT" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

printf '```mermaid\ngraph TD\n  a["src/auth"]\n```\n' > "$DG_L/docs/diagrams/generated/view.md"
dg_stage_close "$DG_L" 'Architecture diagram: updated (docs/diagrams/generated/view.md)'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_L")"
if [[ "$DG_OUT" == *"REFUSED=0"* ]]; then
  ok "lockfile a2: the view regenerated to agree, and declared, passes"
else
  bad "lockfile a2: the view regenerated to agree, and declared, passes" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

for DG_CMD in 'exit 3' 'echo hello'; do
  python3 - "$DG_L/.claude/sdd.json" "$DG_CMD" <<'PY' 2>/dev/null || sed -i.bak 's/"diagram_command":"[^"]*"/"diagram_command":"REPLACED"/' "$DG_L/.claude/sdd.json"
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["diagram_command"]=sys.argv[2]; json.dump(d,open(p,"w"))
PY
  git -C "$DG_L" add -A >/dev/null
  DG_OUT="$(dg_verify "$DG_LIB" "$DG_L")"
  if [[ "$DG_OUT" == *"SLH-DIAGRAM-SHAPE"* && "$DG_OUT" == *"REFUSED=1"* ]]; then
    ok "lockfile b: a diagram_command that [$DG_CMD] refuses as SLH-DIAGRAM-SHAPE, never a pass"
  else
    bad "lockfile b: a diagram_command that [$DG_CMD] refuses as SLH-DIAGRAM-SHAPE, never a pass" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
  fi
done

# ABSENT, BYTE-IDENTICAL TO TODAY: no declaration, no reader, no output.
DG_L2="$WORK/dg-lock-absent"; dg_fixture "$DG_L2"; dg_arm "$DG_L2"
printf 'x\n' >> "$DG_L2/src/auth/main.txt"; dg_stage_close "$DG_L2" 'Architecture diagram: no impact'
DG_OUT="$(dg_verify "$DG_LIB" "$DG_L2")"
if [[ "$DG_OUT" != *"SLH-DIAGRAM-DRIFT"* && "$DG_OUT" != *"SLH-DIAGRAM-SHAPE"* && "$DG_OUT" == *"REFUSED=0"* ]]; then
  ok "lockfile c: an armed instance with NO diagram_command runs no lockfile reader at all"
else
  bad "lockfile c: an armed instance with NO diagram_command runs no lockfile reader at all" "$(printf '%s' "$DG_OUT" | tr '\n' ' ' | cut -c1-200)"
fi

# --- THE AUDIT CARRIES THE SAME ARMS ON BOTH ROUTES --------------------------
DG_AU="$WORK/dg-audit-linear"; dg_fixture "$DG_AU"; dg_arm "$DG_AU"
printf 'x\n' >> "$DG_AU/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_AU/docs/diagrams/components/auth.md"
dg_stage_close "$DG_AU" 'Architecture diagram: no impact'
git -C "$DG_AU" -c core.hooksPath=/dev/null commit -qm "close 0001 undeclared" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_AU" 2>/dev/null | grep -q 'diagram-undeclared'; then
  ok "audit a: the SINGLE-PARENT route refuses an undeclared diagram, so a fast-forward close cannot dodge the check"
else
  bad "audit a: the SINGLE-PARENT route refuses an undeclared diagram" "no diagram-undeclared token in the audit's violations"
fi

DG_AM="$WORK/dg-audit-merge"; dg_fixture "$DG_AM"; dg_arm "$DG_AM"
git -C "$DG_AM" checkout -q -b spec/0001
printf 'x\n' >> "$DG_AM/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_AM/docs/diagrams/components/auth.md"
dg_stage_close "$DG_AM" 'Architecture diagram: no impact'
git -C "$DG_AM" -c core.hooksPath=/dev/null commit -qm "work" >/dev/null 2>&1
git -C "$DG_AM" checkout -q main
git -C "$DG_AM" -c core.hooksPath=/dev/null merge -q --no-ff spec/0001 -m "Merge spec/0001" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_AM" 2>/dev/null | grep -q 'diagram-undeclared'; then
  ok "audit b: the MERGE route refuses the same undeclared diagram, so the two routes agree"
else
  bad "audit b: the MERGE route refuses the same undeclared diagram" "no diagram-undeclared token in the audit's violations"
fi

# --- THE SAME TWO ROUTES ON A RECORD-CARRYING INSTANCE (F1, 2.7.0 leg) --------
# WHY THESE TWO CASES EXIST, and they matter more than the bug they pin.
#
# Every diagram assertion above builds its fixture with dg_fixture, which writes
# .claude/sdd.json and NO .claude/status.json. That is the record-ABSENCE shape,
# and no instance has had it since v1.12, because /setlist:checkpoint writes the
# record at every close. So the whole diagram corpus was green against a shape
# the field does not produce, while on the shape it DOES produce neither audit
# route ran the field-versus-diff or node arms at all. The suite could not see
# the difference, which is why a leg found it and 1409 assertions did not.
#
# A fixture without a record tests the absence path only. Any future arm added
# to either route needs BOTH shapes or it lands behind this same blind spot.
dg_record() { # dg_record <dir> <diagram-token>   -- the CLOSED record
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"%s"}},"chores":{}}\n' \
    "$2" > "$1/.claude/status.json"
}
# THE RECORD MUST EXIST AT THE PARENT TOO, and that is not a detail of these
# fixtures, it is what a real instance looks like. The audit computes which specs
# a commit NEWLY closes by diffing the record at the commit against the record at
# its parent, so a commit that INTRODUCES the record closes nothing as far as the
# audit is concerned (the one-time adoption commit, deliberately). A fixture that
# writes the record only at the close is therefore still not the field's shape:
# it is a third shape, neither absence nor steady state, and it silently checks
# nothing. Seeded ACTIVE here, flipped to closed at the close.
dg_record_seed() { # dg_record_seed <dir>  -- the record as it stands before the close
  printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$1/.claude/status.json"
  git -C "$1" add -A >/dev/null
  git -C "$1" -c core.hooksPath=/dev/null commit -qm "record: 0001 active" >/dev/null 2>&1
}

# F5 OF THE SECOND 2.7.0 LEG, fix round 2: WHAT ARMS THE HALF.
# The switch was the mere existence of any file under docs/diagrams/, of any type,
# so upgrading armed the checks for any project that already kept diagrams at that
# conventional path and started refusing closes it had passed before. The switch is
# now the four-line header that chore/diagram-baseline and /setlist:new phase 2
# write. Both directions, because arming on too little is a false denial and arming
# on too much is the hole this replaced.
DG_SW="$WORK/dg-switch-foreign"; dg_fixture "$DG_SW"
mkdir -p "$DG_SW/docs/diagrams"
printf '# our own picture\n\n```mermaid\ngraph TD\n  a["src/auth"]\n```\n' > "$DG_SW/docs/diagrams/legacy.md"
printf 'PNG\n' > "$DG_SW/docs/diagrams/architecture.png"
git -C "$DG_SW" add -A >/dev/null
git -C "$DG_SW" -c core.hooksPath=/dev/null commit -qm "a project that already keeps diagrams here" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_SW" 2>/dev/null | grep -q 'diagram'; then
  bad "switch foreign: a docs/diagrams/ tree with no header does NOT arm the checks" "the audit reported a diagram token against a project that never opted in"
else
  ok "switch foreign: a docs/diagrams/ tree with no header does NOT arm the checks, so an upgrade cannot arm a project that merely uses the path"
fi
printf 'Shows: x\nAltitude: L2\nSynced by: chore diagram-baseline\nEncodes: y\n\n```mermaid\ngraph TD\n  a["src/auth"]\n```\n' > "$DG_SW/docs/diagrams/legacy.md"
git -C "$DG_SW" add -A >/dev/null
git -C "$DG_SW" -c core.hooksPath=/dev/null commit -qm "cut the baseline chore" >/dev/null 2>&1
# The touch and the close must be the SAME commit: the checks iterate over the
# specs a commit closes, so a diagram edited in a commit that closes nothing is
# nobody to ask about. My first version of this case split them and asserted a
# refusal that could never fire, which is the vacuous shape this file hunts.
printf 'x\n' >> "$DG_SW/src/auth/main.txt"
printf 'Shows: x\nAltitude: L2\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  a["src/auth"]\n```\n' > "$DG_SW/docs/diagrams/legacy.md"
dg_stage_close "$DG_SW" 'Architecture diagram: no impact'
git -C "$DG_SW" add -A >/dev/null
git -C "$DG_SW" -c core.hooksPath=/dev/null commit -qm "close 0001 with the diagram touched and undeclared" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_SW" 2>/dev/null | grep -q 'diagram'; then
  ok "switch header: once a file carries the header, the checks ARE armed, so the opt-in really opts in"
else
  bad "switch header: once a file carries the header, the checks ARE armed" "no diagram token after the header was added"
fi

# THE SECOND MARKER, which the cold review of this very round caught the tests not
# covering: arming on the header alone had already been fixed to accept a declared
# diagram_command, and nothing here exercised that branch, so these assertions
# would have passed whether or not the code read diagram_command at all. That is
# the vacuous-coverage shape, in the case added to close a vacuous-coverage gap.
DG_SWC="$WORK/dg-switch-command"; dg_fixture "$DG_SWC"
python3 - "$DG_SWC/.claude/sdd.json" <<'PY' 2>/dev/null || \
  sed -i.bak 's/"gate_command":"true"/"gate_command":"true","diagram_command":"bash .claude\/gen.sh"/' "$DG_SWC/.claude/sdd.json"
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["diagram_command"]="bash .claude/gen.sh"; json.dump(d,open(p,"w"))
PY
git -C "$DG_SWC" add -A >/dev/null
git -C "$DG_SWC" -c core.hooksPath=/dev/null commit -qm "declare diagram_command, no docs/diagrams at all" >/dev/null 2>&1
if bash -c 'eval "$(awk "/^slh_diagram_switch_on\(\)/,/^}\$/" "$1")"; slh_diagram_switch_on "$2" HEAD' _ "$DG_AUDIT" "$DG_SWC"; then
  ok "switch command: a declared diagram_command arms the half on its own, with no docs/diagrams/ in the tree, because the lockfile arm is what it opted into"
else
  bad "switch command: a declared diagram_command arms the half on its own" "the predicate read no diagram_command, so a project whose only surface is a generated view is unarmed"
fi
DG_SWN="$WORK/dg-switch-neither"; dg_fixture "$DG_SWN"
git -C "$DG_SWN" add -A >/dev/null
git -C "$DG_SWN" -c core.hooksPath=/dev/null commit -qm "neither marker" >/dev/null 2>&1
if bash -c 'eval "$(awk "/^slh_diagram_switch_on\(\)/,/^}\$/" "$1")"; slh_diagram_switch_on "$2" HEAD' _ "$DG_AUDIT" "$DG_SWN"; then
  bad "switch neither: with neither marker the half is UNARMED" "the predicate armed a project that opted into nothing"
else
  ok "switch neither: with neither marker the half is UNARMED, which is the absence claim both public layers make"
fi

DG_AUR="$WORK/dg-audit-linear-record"; dg_fixture "$DG_AUR"; dg_arm "$DG_AUR"; dg_record_seed "$DG_AUR"
printf 'x\n' >> "$DG_AUR/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_AUR/docs/diagrams/components/auth.md"
dg_stage_close "$DG_AUR" 'Architecture diagram: no impact'
dg_record "$DG_AUR" 'no-impact'
git -C "$DG_AUR" add -A >/dev/null
git -C "$DG_AUR" -c core.hooksPath=/dev/null commit -qm "close 0001 undeclared, recorded" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_AUR" 2>/dev/null | grep -q 'diagram-undeclared'; then
  ok "audit a-record: the SINGLE-PARENT route refuses an undeclared diagram on a RECORD-carrying instance, the shape every instance since v1.12 actually has"
else
  bad "audit a-record: the SINGLE-PARENT route refuses an undeclared diagram on a RECORD-carrying instance" "no diagram-undeclared token; the structured path is skipping the diagram arms (F1 of the 2.7.0 leg)"
fi

DG_AMR="$WORK/dg-audit-merge-record"; dg_fixture "$DG_AMR"; dg_arm "$DG_AMR"; dg_record_seed "$DG_AMR"
git -C "$DG_AMR" checkout -q -b spec/0001
printf 'x\n' >> "$DG_AMR/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_AMR/docs/diagrams/components/auth.md"
dg_stage_close "$DG_AMR" 'Architecture diagram: no impact'
dg_record "$DG_AMR" 'no-impact'
git -C "$DG_AMR" add -A >/dev/null
git -C "$DG_AMR" -c core.hooksPath=/dev/null commit -qm "work, recorded" >/dev/null 2>&1
git -C "$DG_AMR" checkout -q main
git -C "$DG_AMR" -c core.hooksPath=/dev/null merge -q --no-ff spec/0001 -m "Merge spec/0001" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_AMR" 2>/dev/null | grep -q 'diagram-undeclared'; then
  ok "audit b-record: the MERGE route refuses the same undeclared diagram on a RECORD-carrying instance, so both routes hold on the real shape"
else
  bad "audit b-record: the MERGE route refuses the same undeclared diagram on a RECORD-carrying instance" "no diagram-undeclared token; the structured path is skipping the diagram arms (F1 of the 2.7.0 leg)"
fi

# THE HONEST DIRECTION, on the same shape: a truthful close must NOT be refused.
DG_AOK="$WORK/dg-audit-record-honest"; dg_fixture "$DG_AOK"; dg_arm "$DG_AOK"; dg_record_seed "$DG_AOK"
printf 'x\n' >> "$DG_AOK/src/auth/main.txt"
printf 'Shows: x\nAltitude: L3\nSynced by: spec 0001\nEncodes: y\n\n```mermaid\ngraph TD\n  q["src/auth"]\n```\n' > "$DG_AOK/docs/diagrams/components/auth.md"
dg_stage_close "$DG_AOK" 'Architecture diagram: updated (docs/diagrams/components/auth.md)'
dg_record "$DG_AOK" 'updated'
git -C "$DG_AOK" add -A >/dev/null
git -C "$DG_AOK" -c core.hooksPath=/dev/null commit -qm "close 0001 declared, recorded" >/dev/null 2>&1
if bash "$DG_AUDIT" "$DG_AOK" 2>/dev/null | grep -q 'diagram-'; then
  bad "audit c-record: a TRUTHFUL diagram close on a record-carrying instance is not refused" "the audit reported a diagram token against a close that names the file it touched"
else
  ok "audit c-record: a TRUTHFUL diagram close on a record-carrying instance is not refused, so the fix did not buy its refusals with a false denial"
fi

# --- THE LOCKSTEP, WHICH IS THE POINT RATHER THAN A NICETY -------------------
#
# The gate and its backstop read the field through ONE text. Leg 5's F8 is what
# happens when they read it through two.
# Trailing blank lines are stripped from BOTH sides before the comparison: each
# copy is followed by a different closing banner in its own file, so the block's
# last newline is an artifact of where it sits rather than part of what it says.
dg_trim() { awk 'BEGIN{n=0} {lines[NR]=$0} END{last=NR; while (last>0 && lines[last] ~ /^[[:space:]]*$/) last--; for(i=1;i<=last;i++) print lines[i]}'; }
DG_BLOCK="$(awk '/^slh_diagram_switch_on\(\) \{/,/^# THE TWO FIELD CHECKS \(contract item 2\)/' "$DG_LIB" | sed '$d' | dg_trim)"
if [[ -n "$DG_BLOCK" ]] && printf '%s\n' "$DG_BLOCK" | grep -q 'slh_diagram_field_files' \
   && diff <(printf '%s\n' "$DG_BLOCK") <(awk '/^slh_diagram_switch_on\(\) \{/,/^# --- end of the byte-identical diagram readers/' "$DG_AUDIT" | sed '$d' | dg_trim) >/dev/null 2>&1; then
  ok "lockstep: the diagram readers are byte-identical in setlist-hook-lib.sh and trunk-audit.sh"
else
  bad "lockstep: the diagram readers are byte-identical in setlist-hook-lib.sh and trunk-audit.sh" \
      "the two copies differ; a backstop that reads a claim differently from the gate is leg 5's F8"
fi

# A READER THAT COULD NOT RUN HAS NOT READ. The audit aliases the library's
# fence reader; an empty alias would read every document as empty and pass every
# diagram claim in silence. Measured during this spec's own build.
if grep -q '^SLH_TEMPLATE_FENCE_AWK="\$TEMPLATE_FENCE_AWK"' "$DG_AUDIT" \
   && grep -q 'the template-fence reader is empty' "$DG_AUDIT"; then
  ok "audit guard: the fence-reader alias is assigned from the real reader and an empty one refuses rather than reporting clean"
else
  bad "audit guard: the fence-reader alias is assigned from the real reader and an empty one refuses" "the alias or its guard is missing"
fi

fi; shard_region_end
# <<< SHARD-END diagram-field-nodes-0136

# >>> SHARD-BEGIN diagram-forge-0136 cost=18
if shard_region diagram-forge-0136; then

# --- THE RENDER STEP, WITH A STUB RENDERER SO test.yml DOES NOT MOVE ---------
#
# KL8 stays RECORDED and not fired: the suite pins this step with a stub on PATH
# rather than installing node in CI, so .github/workflows/test.yml is untouched.
DG_BIN="$WORK/dg-bin"; mkdir -p "$DG_BIN"
cat > "$DG_BIN/setlist-mermaid-parse" <<'STUBP'
#!/usr/bin/env bash
# The stub renderer: a block "parses" unless it contains the word BROKEN. Enough
# to pin the step's plumbing (which blocks it finds, which file it names, which
# verdict it takes) without a toolchain in CI.
grep -q 'BROKEN' "$1" && { echo "stub: parse error near BROKEN"; exit 1; }
exit 0
STUBP
chmod +x "$DG_BIN/setlist-mermaid-parse"


# A PATH WITH NO MERMAID RENDERER ON IT, built rather than assumed. The first cut
# of the absence case simply restored the ambient PATH and asserted that nothing
# rendered; this host has mmdc installed at /opt/homebrew/bin, so the "absent"
# run used the REAL renderer, refused the broken block, and the assertion failed
# for the one reason that was not a defect. A suite whose verdict depends on what
# the developer happens to have installed is not a suite. The directories that
# hold a renderer are replaced by a shim that symlinks everything else they hold,
# because on this host the same directory holds jq and git.
dg_path_without_renderer() { # -> prints a PATH with no mmdc / setlist-mermaid-parse
  local shim="$WORK/dg-norenderer" out="" d e n=0
  rm -rf "$shim"; mkdir -p "$shim"
  local IFS=':'
  for d in $PATH; do
    [[ -n "$d" ]] || continue
    if [[ -x "$d/mmdc" || -x "$d/setlist-mermaid-parse" ]]; then
      n=$((n + 1))
      local sub="$shim/$n"; mkdir -p "$sub"
      for e in "$d"/*; do
        case "${e##*/}" in mmdc|setlist-mermaid-parse) continue ;; esac
        ln -sf "$e" "$sub/${e##*/}" 2>/dev/null || true
      done
      out="$out:$sub"
    else
      out="$out:$d"
    fi
  done
  printf '%s' "${out#:}"
}

DG_FR="$WORK/dg-forge-render"; fc_fixture "$DG_FR" off
mkdir -p "$DG_FR/docs/diagrams"
printf 'Shows: ok\nAltitude: L1\nSynced by: spec 0001\nEncodes: e\n\n```mermaid\ngraph TD\n  a["src"] --> b["src"]\n```\n' > "$DG_FR/docs/diagrams/context.md"
git -C "$DG_FR" add -A >/dev/null; git -C "$DG_FR" -c core.hooksPath=/dev/null commit -qm "diagrams" >/dev/null 2>&1
fc_close_branch "$DG_FR"

DG_SAVED_PATH="$PATH"
PATH="$DG_BIN:$PATH"; export PATH
fc_run "$DG_FR" --base main --head spec/0001-thing --forge none
fc_case "render control: every block parses, so the check still PASSES" 0 "PASS (custody: none declared)"
PATH="$DG_SAVED_PATH"; export PATH

# THE RED DIRECTION: one block that does not parse.
DG_FR2="$WORK/dg-forge-render-bad"; fc_fixture "$DG_FR2" off
mkdir -p "$DG_FR2/docs/diagrams"
printf 'Shows: bad\nAltitude: L1\nSynced by: spec 0001\nEncodes: e\n\n```mermaid\ngraph TD\n  a[[BROKEN --> \n```\n' > "$DG_FR2/docs/diagrams/context.md"
git -C "$DG_FR2" add -A >/dev/null; git -C "$DG_FR2" -c core.hooksPath=/dev/null commit -qm "diagrams" >/dev/null 2>&1
fc_close_branch "$DG_FR2"
PATH="$DG_BIN:$PATH"; export PATH
fc_run "$DG_FR2" --base main --head spec/0001-thing --forge none
fc_case "render a: a block that does not parse refuses as FC-DIAGRAM-RENDER" 1 "DIAGRAM-RENDER" FC-DIAGRAM-RENDER
PATH="$DG_SAVED_PATH"; export PATH

# ABSENCE IS A REPORT HERE, AND A FAILED JOB IN THE WORKFLOW (condition (a)).
DG_NOREND_PATH="$(dg_path_without_renderer)"
if command -v mmdc >/dev/null 2>&1 || command -v setlist-mermaid-parse >/dev/null 2>&1; then
  PATH="$DG_NOREND_PATH"; export PATH
fi
if command -v mmdc >/dev/null 2>&1 || command -v setlist-mermaid-parse >/dev/null 2>&1; then
  bad "render b precondition: the absence case runs with no renderer on PATH" "a renderer is still reachable, so the next two rows would measure the wrong thing"
else
  ok "render b precondition: the absence case runs with no renderer on PATH, built rather than assumed"
fi
fc_run "$DG_FR2" --base main --head spec/0001-thing --forge none
if printf '%s' "$FC_ERR" | grep -qF '[FC-DIAGRAM-NO-RENDERER]'; then
  ok "render b: with no renderer on PATH the step REPORTS FC-DIAGRAM-NO-RENDERER and refuses nothing on that ground"
else
  bad "render b: with no renderer on PATH the step REPORTS FC-DIAGRAM-NO-RENDERER" "no report line; absence must be visible"
fi
if [[ "$FC_RC" -eq 0 ]]; then
  ok "render b2: the same unparseable diagram passes when there is no renderer, which is why the workflow's install step fails the job"
else
  bad "render b2: the same unparseable diagram passes when there is no renderer" "rc=$FC_RC; absence must not refuse here"
fi

PATH="$DG_SAVED_PATH"; export PATH

# THE WORKFLOW: the renderer is PINNED and its step verifies itself both ways.
DG_WF="$ROOT/templates/root/.github/workflows/setlist-forge-check.yml"
if grep -q 'mermaid@11\.14\.0' "$DG_WF" && grep -q 'jsdom@25\.0\.1' "$DG_WF"; then
  ok "workflow a: the renderer is installed at a PINNED version, as its own step"
else
  bad "workflow a: the renderer is installed at a PINNED version, as its own step" "no pinned mermaid/jsdom version in the workflow"
fi
if grep -q 'rejected a VALID block' "$DG_WF" && grep -q 'ACCEPTED a broken block' "$DG_WF" \
   && grep -q 'set -euo pipefail' "$DG_WF"; then
  ok "workflow b: the install step verifies the parser in BOTH directions and fails the job on either, so the check never passes on a renderer it could not install (D14a)"
else
  bad "workflow b: the install step verifies the parser in BOTH directions and fails the job on either" "one of the two guards is missing"
fi

# --- TE4: THE STRICT SETTING (D15), AND S3's ONE REFUSAL PER ROOT CAUSE ------
DG_ST="$WORK/dg-strict"; fc_forge_fixture "$DG_ST" trunk
DG_STUB2="$WORK/dg-forge-stub2.sh"
cat > "$DG_STUB2" <<'STUB2'
#!/usr/bin/env bash
strict_rules='[{"type":"pull_request","parameters":{"required_approving_review_count":1}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"setlist forge check"}]}}]'
loose_rules='[{"type":"pull_request","parameters":{"required_approving_review_count":1}},{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"setlist forge check"}]}}]'
nocheck_rules='[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]'
case "$FC_STUB_MODE" in
  strict)  case "$1" in repos/*/rules/*) printf '200\n%s\n' "$strict_rules" ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  loose)   case "$1" in repos/*/rules/*) printf '200\n%s\n' "$loose_rules" ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  nocheck) case "$1" in repos/*/rules/*) printf '200\n%s\n' "$nocheck_rules" ;; repos/*/protection) printf '404\n{"message":"Branch not protected"}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  classicstrict) case "$1" in repos/*/rules/*) printf '200\n[]\n' ;; repos/*/protection) printf '200\n{"required_pull_request_reviews":{"required_approving_review_count":1},"required_status_checks":{"strict":true,"contexts":["setlist forge check"]}}\n' ;; *) printf '200\n{"allow_rebase_merge":false}\n' ;; esac ;;
  *) exit 1 ;;
esac
STUB2
chmod +x "$DG_STUB2"

FC_STUB_MODE=strict fc_run "$DG_ST" --base main --head spec/0002-other --forge github --repo o/r --forge-query "$DG_STUB2" --author dev
fc_case "TE4 control: a trunk that DOES require branches up to date passes under forge custody" 0 "PASS (custody: forge"

FC_STUB_MODE=loose fc_run "$DG_ST" --base main --head spec/0002-other --forge github --repo o/r --forge-query "$DG_STUB2" --author dev
fc_case "TE4 a: a trunk that does NOT require branches up to date refuses under forge custody" 1 "STRICT-NOT-REQUIRED" FC-STRICT-NOT-REQUIRED

FC_STUB_MODE=classicstrict fc_run "$DG_ST" --base main --head spec/0002-other --forge github --repo o/r --forge-query "$DG_STUB2" --author dev
fc_case "TE4 b: the strict fact is read from the CLASSIC endpoint too, as a union (amendment 4's shape)" 0 "PASS (custody: forge"

# S3: ONE REFUSAL PER ROOT CAUSE. A trunk that does not require the check at all
# has nothing to be strict about, so FC-CHECK-NOT-REQUIRED fires ALONE.
FC_STUB_MODE=nocheck fc_run "$DG_ST" --base main --head spec/0002-other --forge github --repo o/r --forge-query "$DG_STUB2" --author dev
if printf '%s' "$FC_ERR" | grep -qF '[FC-CHECK-NOT-REQUIRED]' && ! printf '%s' "$FC_ERR" | grep -qF '[FC-STRICT-NOT-REQUIRED]'; then
  ok "S3: where the check is not required at all, FC-CHECK-NOT-REQUIRED fires ALONE and the strict code stays silent"
else
  bad "S3: where the check is not required at all, FC-CHECK-NOT-REQUIRED fires ALONE and the strict code stays silent" \
      "codes: $(printf '%s' "$FC_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' ')"
fi

# THE REPORT HALF: under a custody that is not C, the same trunk is a report and
# the verdict stands (the split step 9 already makes, correction 3).
DG_ST2="$WORK/dg-strict-report"; fc_fixture "$DG_ST2" off; fc_close_branch "$DG_ST2"
FC_STUB_MODE=loose fc_run "$DG_ST2" --base main --head spec/0001-thing --forge github --repo o/r --forge-query "$DG_STUB2" --author dev
if [[ "$FC_RC" -eq 0 ]] && printf '%s' "$FC_ERR" | grep -qF '[FC-STRICT-NOT-REQUIRED]'; then
  ok "TE4 c: under a custody that is not forge the same trunk is REPORTED and the verdict stands"
else
  bad "TE4 c: under a custody that is not forge the same trunk is REPORTED and the verdict stands" \
      "rc=$FC_RC codes: $(printf '%s' "$FC_ERR" | grep -o '\[FC-[A-Z-]*\]' | sort -u | tr '\n' ' ')"
fi

fi; shard_region_end
# <<< SHARD-END diagram-forge-0136
