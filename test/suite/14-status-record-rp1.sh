#!/usr/bin/env bash
# test/suite/14-status-record-rp1.sh: shard 14 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# RP1: THE STRUCTURED STATUS RECORD (spec 0126, edition v1.12).
#
# The machine reads only records whose grammar it owns. These cases pin four
# properties, in the order a reader should doubt them: the seven jq readers are
# BYTE-IDENTICAL across the three carriers (the lockstep, extended); the two
# frozen awk readers are byte-identical to the PRE-RECORD generation pinned in
# test/fixtures/pre-record-hooks (the absence path retained, proven against
# the blob rather than inspected); a present-and-malformed record REFUSES on
# otherwise CLEAN content at every layer that reads it, and never falls back;
# and absence is byte-identical to the pre-record generation across a case
# battery, with a discrimination control proving the differential can see a
# difference at all.
# =============================================================================

# --- the lockstep, extended to the record readers ---------------------------
RP1_JQ_NAMES='SLH_RECORD_CHECK_JQ SLH_RECORD_CLOSED_JQ SLH_RECORD_ACTIVE_JQ SLH_RECORD_DONE_JQ SLH_RECORD_STATUS_JQ SLH_RECORD_FACTS_JQ SLH_RECORD_CHORE_FILES_JQ'
RP1_LOCK_BAD=""
for RP1_NAME in $RP1_JQ_NAMES; do
  RP1_REF="$(grep -m1 -E "^[[:space:]]*${RP1_NAME}=" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*//')"
  [[ -n "$RP1_REF" ]] || RP1_LOCK_BAD="$RP1_LOCK_BAD lib:$RP1_NAME:absent"
  for RP1_F in "$SCRIPTS/trunk-audit.sh" "$HOOKS/close-gate.sh"; do
    RP1_GOT="$(grep -m1 -E "^[[:space:]]*${RP1_NAME}=" "$RP1_F" | sed 's/^[[:space:]]*//')"
    # fail-open-ok: an absent line is recorded as a mismatch, not skipped.
    [[ "$RP1_GOT" == "$RP1_REF" && -n "$RP1_GOT" ]] || RP1_LOCK_BAD="$RP1_LOCK_BAD $(basename "$RP1_F"):$RP1_NAME"
  done
done
if [[ -z "$RP1_LOCK_BAD" ]]; then
  ok "record lockstep: all seven SLH_RECORD_*_JQ readers are byte-identical across the hook library, trunk-audit.sh and close-gate.sh"
else
  bad "record lockstep: all seven SLH_RECORD_*_JQ readers are byte-identical across the hook library, trunk-audit.sh and close-gate.sh" \
      "mismatched or absent:$RP1_LOCK_BAD"
fi

# The advisory commit gate keeps its OWN copy rather than sourcing the library
# (the KL4-A1 ruling: the trees are separate, the RULE is shared and the suite
# is what asserts it). Compare VALUES after stripping the differing names.
RP1_CM_VAL="$(grep -m1 -E '^[[:space:]]*CM_RECORD_CHECK_JQ=' "$HOOKS/commit-gate.sh" | sed 's/^[[:space:]]*CM_RECORD_CHECK_JQ=//')"
RP1_LIB_VAL="$(grep -m1 -E '^[[:space:]]*SLH_RECORD_CHECK_JQ=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*SLH_RECORD_CHECK_JQ=//')"
if [[ -n "$RP1_CM_VAL" && "$RP1_CM_VAL" == "$RP1_LIB_VAL" ]]; then
  ok "record lockstep: commit-gate's CM_RECORD_CHECK_JQ carries the library's grammar byte for byte"
else
  bad "record lockstep: commit-gate's CM_RECORD_CHECK_JQ carries the library's grammar byte for byte" \
      "the advisory copy drifted from the library's, so the two layers would disagree about what parses"
fi

# --- the frozen readers, byte-identical to the PRE-RECORD blob --------------
RP1_PRE="$ROOT/test/fixtures/pre-record-hooks"
if [[ ! -d "$RP1_PRE" ]]; then
  ok "record frozen readers: SKIPPED, the pre-record hook blobs are not present in this tree (export copy)"
else
  RP1_FROZEN_BAD=""
  for RP1_AWKNAME in QA_PASS1_AWK TEMPLATE_FENCE_AWK LIVE_TEXT_AWK; do
    for RP1_PAIR in \
      "templates/git-hooks/setlist-hook-lib.sh:setlist-hook-lib.sh" \
      "scripts/trunk-audit.sh:trunk-audit.sh" \
      "templates/hooks/close-gate.sh:close-gate.sh"; do
      RP1_CUR="$ROOT/${RP1_PAIR%%:*}"; RP1_OLD="$RP1_PRE/${RP1_PAIR#*:}"
      RP1_CURL="$(grep -m1 -E "^[[:space:]]*(SLH_)?${RP1_AWKNAME}=" "$RP1_CUR" | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
      RP1_OLDL="$(grep -m1 -E "^[[:space:]]*(SLH_)?${RP1_AWKNAME}=" "$RP1_OLD" | sed -e 's/^[[:space:]]*//' -e 's/^SLH_//')"
      # fail-open-ok: an empty extraction is a mismatch, never a silent pass.
      [[ -n "$RP1_CURL" && "$RP1_CURL" == "$RP1_OLDL" ]] || RP1_FROZEN_BAD="$RP1_FROZEN_BAD ${RP1_PAIR%%:*}:$RP1_AWKNAME"
    done
  done
  if [[ -z "$RP1_FROZEN_BAD" ]]; then
    ok "record frozen readers: the three frozen awk programs are byte-identical to the pre-record generation in all three carriers (the absence path is RETAINED, proven against the pinned blob)"
  else
    bad "record frozen readers: the three frozen awk programs are byte-identical to the pre-record generation in all three carriers (the absence path is RETAINED, proven against the pinned blob)" \
        "drifted:$RP1_FROZEN_BAD; the frozen readers are never repaired and never removed"
  fi
fi

# --- a structured fixture builder --------------------------------------------
# rp1_fixture <dir> -> a stamped-shaped structured instance, spec 0001 active,
# git hooks wired from the CURRENT templates.
rp1_fixture() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  printf '# Spec 0001\n\nStatus: ACTIVE\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
}

# --- the grammar corpus: malformed REFUSES on CLEAN content ------------------
# The staged content beside the record is an ordinary docs edit, so the refusal
# is attributable to the record and to nothing else. The corpus enumerates the
# GRAMMAR (this is a grammar we own, so the corpus can be complete in kind):
# unparseable, missing version, wrong version type, unknown top-level key,
# unknown lifecycle token, unknown entry field, non-object entry, bad spec key,
# bad chore status, files not an array.
RP1G="$WORK/rp1-grammar"
rp1_fixture "$RP1G"
RP1_GRAMMAR_BAD=""
RP1_GRAMMAR_N=0
while IFS='	' read -r RP1_LABEL RP1_JSON; do
  [[ -n "$RP1_LABEL" ]] || continue
  RP1_GRAMMAR_N=$((RP1_GRAMMAR_N + 1))
  printf '%s\n' "$RP1_JSON" > "$RP1G/.claude/status.json"
  printf 'note %s\n' "$RP1_GRAMMAR_N" > "$RP1G/docs.txt"
  printf '| 0001 | Thing | ACTIVE | wip %s |\n' "$RP1_GRAMMAR_N" >> "$RP1G/specs/STATUS.md"
  git -C "$RP1G" add -A >/dev/null 2>&1
  if git -C "$RP1G" commit -qm "grammar $RP1_LABEL" >"$WORK/rp1-grammar.out" 2>&1; then
    RP1_GRAMMAR_BAD="$RP1_GRAMMAR_BAD $RP1_LABEL:committed"
    git -C "$RP1G" reset -q --hard HEAD~1 2>/dev/null
  elif ! grep -q 'SLH-RECORD-MALFORMED' "$WORK/rp1-grammar.out"; then
    RP1_GRAMMAR_BAD="$RP1_GRAMMAR_BAD $RP1_LABEL:wrong-reason"
    git -C "$RP1G" reset -q --hard HEAD 2>/dev/null
  else
    git -C "$RP1G" reset -q --hard HEAD 2>/dev/null
  fi
done <<'RP1GRAMMAR'
unparseable	not json at all
missing-version	{"specs":{},"chores":{}}
version-string	{"setlist_status":"1","specs":{},"chores":{}}
version-future	{"setlist_status":2,"specs":{},"chores":{}}
unknown-top-key	{"setlist_status":1,"specs":{},"chores":{},"extra":true}
unknown-token	{"setlist_status":1,"specs":{"0001":{"status":"finished"}},"chores":{}}
uppercase-token	{"setlist_status":1,"specs":{"0001":{"status":"CLOSED"}},"chores":{}}
unknown-field	{"setlist_status":1,"specs":{"0001":{"status":"active","note":"x"}},"chores":{}}
entry-not-object	{"setlist_status":1,"specs":{"0001":"active"},"chores":{}}
bad-spec-key	{"setlist_status":1,"specs":{"bogus":{"status":"active"}},"chores":{}}
qa-not-token	{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"3/4"}},"chores":{}}
diagram-not-token	{"setlist_status":1,"specs":{"0001":{"status":"closed","diagram":"none"}},"chores":{}}
chore-bad-status	{"setlist_status":1,"specs":{},"chores":{"CHORE-1":{"status":"finished"}}}
chore-files-not-array	{"setlist_status":1,"specs":{},"chores":{"CHORE-1":{"status":"done","files":"x"}}}
chore-bad-key	{"setlist_status":1,"specs":{},"chores":{"chore-1":{"status":"open"}}}
two-documents	{"setlist_status":1}{"setlist_status":1}
RP1GRAMMAR
if [[ "$RP1_GRAMMAR_N" -lt 16 ]]; then
  bad "record grammar: the corpus enumerates the grammar" \
      "only $RP1_GRAMMAR_N cases ran; the corpus is broken and proves almost nothing"
elif [[ -z "$RP1_GRAMMAR_BAD" ]]; then
  ok "record grammar: all $RP1_GRAMMAR_N malformed shapes REFUSE with SLH-RECORD-MALFORMED on otherwise clean content, and none falls back"
else
  bad "record grammar: all $RP1_GRAMMAR_N malformed shapes REFUSE with SLH-RECORD-MALFORMED on otherwise clean content, and none falls back" \
      "failures:$RP1_GRAMMAR_BAD"
fi

# The valid twin: a well-formed record edit with the page staged commits clean,
# so the grammar refuses shapes rather than refusing the feature.
printf '{"setlist_status":1,"specs":{"0001":{"status":"built"}},"chores":{}}\n' > "$RP1G/.claude/status.json"
printf '| 0001 | Thing | BUILT | done on branch |\n' >> "$RP1G/specs/STATUS.md"
git -C "$RP1G" add -A >/dev/null 2>&1
if git -C "$RP1G" commit -qm "valid lifecycle flip" >"$WORK/rp1-valid.out" 2>&1; then
  ok "record grammar twin: a well-formed record flip with the page staged commits clean"
else
  bad "record grammar twin: a well-formed record flip with the page staged commits clean" \
      "$(tr '\n' ' ' < "$WORK/rp1-valid.out")"
fi

# --- the muted reader: the caller refuses what the reader did not say -------
# The one-token convention is the mechanism, so it is asserted the way the
# attestation's was: MUTE the reader (a jq that produces nothing at exit 0)
# over a perfectly VALID record, and watch the caller refuse. A crashed reader
# and a silent reader are the same non-answer, and neither is exactly "ok".
# Driven against the shipped library sourced whole, never a re-implementation.
RP1M="$WORK/rp1-muted"
rp1_fixture "$RP1M"
RP1_MUTED_OUT="$(
  # shellcheck disable=SC1091
  . "$ROOT/templates/git-hooks/setlist-hook-lib.sh"
  jq() { return 0; }
  slh_active_specs "$RP1M" "" 2>&1
  printf 'rc=%s\n' "$?"
)"
if printf '%s' "$RP1_MUTED_OUT" | grep -q 'SLH-RECORD-MALFORMED' && printf '%s' "$RP1_MUTED_OUT" | grep -q 'rc=1'; then
  ok "record muted reader: a reader that says nothing at exit 0 over a VALID record is refused by its caller (one token out, and it was not ok)"
else
  bad "record muted reader: a reader that says nothing at exit 0 over a VALID record is refused by its caller (one token out, and it was not ok)" \
      "got: $(printf '%s' "$RP1_MUTED_OUT" | tr '\n' ' ')"
fi

# --- the lifecycle trigger, re-keyed ------------------------------------------
# Structured: a staged record MODIFICATION without the page is refused; the
# ADOPTION commit (the record's addition) is not a flip and is not refused; and
# the advisory gate mirrors both with its own codes.
RP1L="$WORK/rp1-lifecycle"
rp1_fixture "$RP1L"
printf '{"setlist_status":1,"specs":{"0001":{"status":"built"}},"chores":{}}\n' > "$RP1L/.claude/status.json"
git -C "$RP1L" add -A >/dev/null 2>&1
if git -C "$RP1L" commit -qm "record flip alone" >"$WORK/rp1-lc.out" 2>&1; then
  bad "record lifecycle a: a staged record modification without specs/STATUS.md is refused" \
      "it committed: the record and the page can now drift apart at the write moment checkpoint owns"
else
  if grep -q 'SLH-STATUS-MISSING' "$WORK/rp1-lc.out"; then
    ok "record lifecycle a: a staged record modification without specs/STATUS.md is refused (SLH-STATUS-MISSING, the existing code re-keyed)"
  else
    bad "record lifecycle a: a staged record modification without specs/STATUS.md is refused" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-lc.out")"
  fi
fi
run_hook "$HOOKS/commit-gate.sh" "$RP1L" "$(bash_payload 'git commit -m "flip"')"
expect_deny "record lifecycle b: the advisory gate mirrors the record-without-page demand" "CM-STATUS-MISSING"
git -C "$RP1L" reset -q --hard HEAD 2>/dev/null

# The ADOPTION commit: a legacy instance gains the record; the addition is an
# opt-in, not a lifecycle flip, so no page is demanded and the commit lands.
RP1A="$WORK/rp1-adopt"
rp1_fixture "$RP1A"
git -C "$RP1A" rm -q --cached .claude/status.json >/dev/null 2>&1
rm -f "$RP1A/.claude/status.json"
git -C "$RP1A" commit -qm "legacy instance" >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$RP1A/.claude/status.json"
git -C "$RP1A" add -A >/dev/null 2>&1
if git -C "$RP1A" commit -qm "adoption" >"$WORK/rp1-adopt.out" 2>&1; then
  ok "record lifecycle c: the ADOPTION commit (record added, page untouched) lands; an opt-in is not a flip"
else
  bad "record lifecycle c: the ADOPTION commit (record added, page untouched) lands; an opt-in is not a flip" \
      "$(tr '\n' ' ' < "$WORK/rp1-adopt.out")"
fi

# --- the audit's record codes, green direction --------------------------------
# (Each was watched RED against the pre-record bytes before its fix existed;
# the observations are in spec 0126 and its commit. These pin the green.)
RP1B="$WORK/rp1-audit-noclose"
rp1_fixture "$RP1B"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed"}},"chores":{}}\n' > "$RP1B/.claude/status.json"
git -C "$RP1B" add -A >/dev/null 2>&1
git -C "$RP1B" -c core.hooksPath=/dev/null commit -qm "record-only factless close" >/dev/null 2>&1
RP1B_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1B" 2>&1)" || true
if printf '%s' "$RP1B_OUT" | grep -q '\[SLH-RECORD-NO-CLOSE\]'; then
  ok "record audit a: a record flip to closed without close facts is a VIOLATION named SLH-RECORD-NO-CLOSE"
else
  bad "record audit a: a record flip to closed without close facts is a VIOLATION named SLH-RECORD-NO-CLOSE" \
      "audit said: $(printf '%s' "$RP1B_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1C="$WORK/rp1-audit-nospec"
rp1_fixture "$RP1C"
git -C "$RP1C" checkout -qb spec/0002-other
printf '# Spec 0002\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1C/specs/0002-other.md"
printf '| 0002 | Other | CLOSED | x |\n' >> "$RP1C/specs/STATUS.md"
printf 'code\n' > "$RP1C/src/f.js"
git -C "$RP1C" add -A >/dev/null 2>&1
git -C "$RP1C" -c core.hooksPath=/dev/null commit -qm "close 0002 without recording it" >/dev/null 2>&1
git -C "$RP1C" checkout -q main
git -C "$RP1C" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0002-other >/dev/null 2>&1
RP1C_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1C" 2>&1)" || true
if printf '%s' "$RP1C_OUT" | grep -q '\[SLH-RECORD-NO-SPEC\]'; then
  ok "record audit b: a merged spec with NO record entry is a VIOLATION named SLH-RECORD-NO-SPEC, and the message names the one-line way out"
else
  bad "record audit b: a merged spec with NO record entry is a VIOLATION named SLH-RECORD-NO-SPEC, and the message names the one-line way out" \
      "audit said: $(printf '%s' "$RP1C_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1D="$WORK/rp1-audit-malformed"
rp1_fixture "$RP1D"
printf 'not json at all\n' > "$RP1D/.claude/status.json"
printf 'docs\n' > "$RP1D/docs.txt"
git -C "$RP1D" add -A >/dev/null 2>&1
git -C "$RP1D" -c core.hooksPath=/dev/null commit -qm "malformed record" >/dev/null 2>&1
RP1D_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1D" 2>&1)" || true
if printf '%s' "$RP1D_OUT" | grep -q '\[SLH-RECORD-MALFORMED\]'; then
  ok "record audit c: a present-and-malformed record is a VIOLATION named SLH-RECORD-MALFORMED, never a fallback to the page readers"
else
  bad "record audit c: a present-and-malformed record is a VIOLATION named SLH-RECORD-MALFORMED, never a fallback to the page readers" \
      "audit said: $(printf '%s' "$RP1D_OUT" | tail -2 | tr '\n' ' ')"
fi

# The honest structured close, BOTH merge shapes, stays clean: the codes above
# refuse hand edits, not the feature.
RP1E="$WORK/rp1-audit-clean"
rp1_fixture "$RP1E"
git -C "$RP1E" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1E/specs/0001-thing.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1E/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1E/specs/STATUS.md" > "$RP1E/specs/STATUS.md.new" && mv "$RP1E/specs/STATUS.md.new" "$RP1E/specs/STATUS.md"
printf 'code\n' > "$RP1E/src/f.js"
git -C "$RP1E" add -A >/dev/null 2>&1
git -C "$RP1E" -c core.hooksPath=/dev/null commit -qm "compliant recorded close" >/dev/null 2>&1
git -C "$RP1E" checkout -q main
git -C "$RP1E" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0001-thing >/dev/null 2>&1
RP1E_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1E" 2>&1)" || true
if printf '%s' "$RP1E_OUT" | grep -q ' 0 violations'; then
  ok "record audit d: the honest structured --no-ff close audits clean"
else
  bad "record audit d: the honest structured --no-ff close audits clean" \
      "audit said: $(printf '%s' "$RP1E_OUT" | tail -2 | tr '\n' ' ')"
fi

RP1F="$WORK/rp1-audit-squash"
rp1_fixture "$RP1F"
git -C "$RP1F" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1F/specs/0001-thing.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1F/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1F/specs/STATUS.md" > "$RP1F/specs/STATUS.md.new" && mv "$RP1F/specs/STATUS.md.new" "$RP1F/specs/STATUS.md"
printf 'code\n' > "$RP1F/src/f.js"
git -C "$RP1F" add -A >/dev/null 2>&1
git -C "$RP1F" -c core.hooksPath=/dev/null commit -qm "compliant recorded close" >/dev/null 2>&1
git -C "$RP1F" checkout -q main
git -C "$RP1F" -c core.hooksPath=/dev/null merge --squash spec/0001-thing >/dev/null 2>&1
git -C "$RP1F" -c core.hooksPath=/dev/null commit -qm "squash close of 0001" >/dev/null 2>&1
RP1F_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1F" 2>&1)" || true
if printf '%s' "$RP1F_OUT" | grep -q ' 0 violations'; then
  ok "record audit e: the honest structured SQUASH close audits clean (F4's honest shape, record-verified)"
else
  bad "record audit e: the honest structured SQUASH close audits clean (F4's honest shape, record-verified)" \
      "audit said: $(printf '%s' "$RP1F_OUT" | tail -2 | tr '\n' ' ')"
fi

# --- the session mirror at close-gate ----------------------------------------
RP1CG="$WORK/rp1-cg"
rp1_fixture "$RP1CG"
git -C "$RP1CG" checkout -qb spec/0001-thing
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1CG/specs/0001-thing.md"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1CG/specs/STATUS.md" > "$RP1CG/specs/STATUS.md.new" && mv "$RP1CG/specs/STATUS.md.new" "$RP1CG/specs/STATUS.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed"}},"chores":{}}\n' > "$RP1CG/.claude/status.json"
printf 'code\n' > "$RP1CG/src/f.js"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "record without facts" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate a: a branch record without close facts is warned CG-RECORD-NO-CLOSE (prose fully compliant, so the record is the only reader that can see it)" "CG-RECORD-NO-CLOSE"

git -C "$RP1CG" checkout -q spec/0001-thing
printf '{"setlist_status":1,"specs":{},"chores":{}}\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "entry removed" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate b: a spec with no record entry is warned CG-RECORD-NO-SPEC" "CG-RECORD-NO-SPEC"

git -C "$RP1CG" checkout -q spec/0001-thing
printf 'not json at all\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "record garbage" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_deny "record close-gate c: a malformed branch record is warned CG-RECORD-MALFORMED, in the git hooks' own words" "CG-RECORD-MALFORMED"

git -C "$RP1CG" checkout -q spec/0001-thing
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1CG/.claude/status.json"
git -C "$RP1CG" add -A >/dev/null 2>&1
git -C "$RP1CG" -c core.hooksPath=/dev/null commit -qm "facts complete" >/dev/null 2>&1
git -C "$RP1CG" checkout -q main
run_hook "$HOOKS/close-gate.sh" "$RP1CG" "$(bash_payload 'git merge --no-ff spec/0001-thing')"
expect_allow "record close-gate d: the compliant recorded close is allowed in silence"

# --- the advisory commit gate's malformed mirror ------------------------------
RP1CM="$WORK/rp1-cm"
rp1_fixture "$RP1CM"
printf 'not json at all\n' > "$RP1CM/.claude/status.json"
printf 'x\n' >> "$RP1CM/specs/STATUS.md"
git -C "$RP1CM" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$RP1CM" "$(bash_payload 'git commit -m x')"
expect_deny "record commit-gate: a staged malformed record is warned CM-RECORD-MALFORMED at the earliest layer that sees it" "CM-RECORD-MALFORMED"

# --- feature code without a record flip: the structured SLH-CLOSES-NO-SPEC ----
RP1N="$WORK/rp1-noflip"
rp1_fixture "$RP1N"
git -C "$RP1N" checkout -qb spec/0001-thing
printf 'code\n' > "$RP1N/src/f.js"
git -C "$RP1N" add -A >/dev/null 2>&1
git -C "$RP1N" -c core.hooksPath=/dev/null commit -qm "code, no record flip" >/dev/null 2>&1
git -C "$RP1N" checkout -q main
if git -C "$RP1N" merge --no-ff --no-edit spec/0001-thing >"$WORK/rp1-noflip.out" 2>&1; then
  bad "record closes-no-spec: feature code without a record flip or chore is refused at the merge" \
      "the merge landed; the record path lost the closes-no-spec rule"
else
  if grep -q 'SLH-CLOSES-NO-SPEC' "$WORK/rp1-noflip.out"; then
    ok "record closes-no-spec: feature code without a record flip or chore is refused at the merge, and the message names checkpoint"
  else
    bad "record closes-no-spec: feature code without a record flip or chore is refused at the merge" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-noflip.out")"
  fi
fi

# --- the chore route through the record ---------------------------------------
RP1CH="$WORK/rp1-chore"
rp1_fixture "$RP1CH"
git -C "$RP1CH" checkout -qb chore/tidy
printf 'tidied\n' > "$RP1CH/src/tidy.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-001":{"status":"done"}}}\n' > "$RP1CH/.claude/status.json"
printf '- CHORE-001: DONE 2026-08-30. Tidied.\n' >> "$RP1CH/specs/STATUS.md"
git -C "$RP1CH" add -A >/dev/null 2>&1
git -C "$RP1CH" -c core.hooksPath=/dev/null commit -qm "chore recorded in the record" >/dev/null 2>&1
git -C "$RP1CH" checkout -q main
if git -C "$RP1CH" merge --no-ff --no-edit chore/tidy >"$WORK/rp1-chore.out" 2>&1; then
  ok "record chore: a chore newly done in the record authorises its merge (the record half of Part 5b)"
else
  bad "record chore: a chore newly done in the record authorises its merge (the record half of Part 5b)" \
      "$(tr '\n' ' ' < "$WORK/rp1-chore.out")"
fi

# --- THE ABSENCE DIFFERENTIAL: blob-pinned, both directions -------------------
# >>> SHARD-BEGIN rp1-absence-differential cost=7
if shard_region rp1-absence-differential; then
# A8: the case count is asserted before the agreement is believed, and a
# DISCRIMINATION control proves the harness can see a difference at all, so a
# green here is never green because nothing ran.
if [[ ! -d "$RP1_PRE" ]]; then
  ok "record differential: SKIPPED, the pre-record hook blobs are not present in this tree (export copy)"
else
  RP1DD="$WORK/rp1-diff"; rm -rf "$RP1DD"; mkdir -p "$RP1DD"
  RP1_DIFF_N=0; RP1_DIFF_BAD=""
  for RP1_CASE in clean lifecycle emdash close-merge close-gate-deny commit-gate-lc audit-close; do
    for RP1_GEN in pre now; do
      d="$RP1DD/$RP1_CASE-$RP1_GEN"
      rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
      git_init "$d"
      # NO .claude/status.json anywhere: this is the legacy instance, and the
      # claim under test is that it cannot tell the generations apart.
      printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
      printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
      printf '# Spec 0001\n\nStatus: ACTIVE\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
      if [[ "$RP1_GEN" == "pre" ]]; then
        cp "$RP1_PRE/pre-commit" "$RP1_PRE/pre-merge-commit" "$RP1_PRE/setlist-hook-lib.sh" "$d/.githooks/"
        RP1_CG="$RP1_PRE/close-gate.sh"; RP1_CM="$RP1_PRE/commit-gate.sh"; RP1_TA="$RP1_PRE/trunk-audit.sh"
      else
        cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
        RP1_CG="$HOOKS/close-gate.sh"; RP1_CM="$HOOKS/commit-gate.sh"; RP1_TA="$SCRIPTS/trunk-audit.sh"
      fi
      chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
      printf 'seed\n' > "$d/seed.txt"
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
      git -C "$d" config core.hooksPath .githooks
      : > "$RP1DD/$RP1_CASE-$RP1_GEN.out"
      case "$RP1_CASE" in
        clean)
          printf 'ordinary work\n' > "$d/docs.txt"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "clean" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        lifecycle)
          printf '# Spec 0001\n\nStatus: BUILT\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "flip without page" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        emdash)
          printf 'a %s b\n' "$EMDASH" > "$d/src/app.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" commit -qm "emdash" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        close-merge)
          git -C "$d" checkout -qb spec/0001-thing 2>/dev/null
          printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$d/specs/0001-thing.md"
          sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
          printf 'code\n' > "$d/src/f.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" -c core.hooksPath=/dev/null commit -qm "close" >/dev/null 2>&1
          git -C "$d" checkout -q main 2>/dev/null
          git -C "$d" merge --no-ff --no-edit spec/0001-thing >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out"
          # The merge subject line embeds nothing generation-specific; strip
          # the object names git prints, which differ per repo by hash.
          sed -e 's/[0-9a-f]\{7,40\}/HASH/g' "$RP1DD/$RP1_CASE-$RP1_GEN.out" > "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" && mv "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        close-gate-deny)
          printf '%s' "$(bash_payload 'git merge --no-ff spec/0009-none')" | CLAUDE_PROJECT_DIR="$d" bash "$RP1_CG" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        commit-gate-lc)
          printf '# Spec 0001\n\nStatus: BUILT\n\n## Goal\n\nthing\n' > "$d/specs/0001-thing.md"
          git -C "$d" add -A >/dev/null 2>&1
          printf '%s' "$(bash_payload 'git commit -m flip')" | CLAUDE_PROJECT_DIR="$d" bash "$RP1_CM" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
        audit-close)
          git -C "$d" checkout -qb spec/0001-thing 2>/dev/null
          printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$d/specs/0001-thing.md"
          sed -e 's/| ACTIVE |/| CLOSED |/' "$d/specs/STATUS.md" > "$d/specs/STATUS.md.new" && mv "$d/specs/STATUS.md.new" "$d/specs/STATUS.md"
          printf 'code\n' > "$d/src/f.js"
          git -C "$d" add -A >/dev/null 2>&1
          git -C "$d" -c core.hooksPath=/dev/null commit -qm "close" >/dev/null 2>&1
          git -C "$d" checkout -q main 2>/dev/null
          git -C "$d" -c core.hooksPath=/dev/null merge -q --no-ff --no-edit spec/0001-thing >/dev/null 2>&1
          bash "$RP1_TA" "$d" >>"$RP1DD/$RP1_CASE-$RP1_GEN.out" 2>&1
          printf 'exit=%s\n' "$?" >> "$RP1DD/$RP1_CASE-$RP1_GEN.out"
          # The audit echoes the instance path and commit hashes, which differ
          # per generation BY CONSTRUCTION (two fixture dirs); normalise both,
          # because the claim under comparison is behaviour, not the echo.
          sed -e "s#$d#INSTANCE#g" -e 's/[0-9a-f]\{7,40\}/HASH/g' "$RP1DD/$RP1_CASE-$RP1_GEN.out" > "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" && mv "$RP1DD/$RP1_CASE-$RP1_GEN.out.n" "$RP1DD/$RP1_CASE-$RP1_GEN.out" ;;
      esac
    done
    RP1_DIFF_N=$((RP1_DIFF_N + 1))
    norm_escape_coaching "$RP1DD/$RP1_CASE-pre.out"; norm_escape_coaching "$RP1DD/$RP1_CASE-now.out"
    if ! cmp -s "$RP1DD/$RP1_CASE-pre.out" "$RP1DD/$RP1_CASE-now.out"; then
      RP1_DIFF_BAD="$RP1_DIFF_BAD $RP1_CASE"
    fi
  done
  if [[ "$RP1_DIFF_N" -eq 7 && -z "$RP1_DIFF_BAD" ]]; then
    ok "record differential: with NO record present, all 7 cases are byte-identical between the pre-record and current generations, at every layer"
  else
    bad "record differential: with NO record present, all 7 cases are byte-identical between the pre-record and current generations, at every layer" \
        "$RP1_DIFF_N of 7 cases compared, differing:${RP1_DIFF_BAD:- none}; absent must mean today's behaviour exactly"
  fi

  # THE DISCRIMINATION CONTROL: a structured input where the generations MUST
  # diverge, so the identity above is evidence about absence rather than about
  # a harness that compares nothing.
  RP1DC="$RP1DD/disc"; rm -rf "$RP1DC-pre" "$RP1DC-now"
  for RP1_GEN in pre now; do
    d="$RP1DC-$RP1_GEN"
    rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
    git_init "$d"
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
    printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{}}\n' > "$d/.claude/status.json"
    printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
    if [[ "$RP1_GEN" == "pre" ]]; then
      cp "$RP1_PRE/pre-commit" "$RP1_PRE/pre-merge-commit" "$RP1_PRE/setlist-hook-lib.sh" "$d/.githooks/"
    else
      cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
    fi
    chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
    printf 'seed\n' > "$d/seed.txt"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
    git -C "$d" config core.hooksPath .githooks
    printf '{"setlist_status":1,"specs":{"0001":{"status":"FINISHED"}}}\n' > "$d/.claude/status.json"
    printf 'x\n' >> "$d/specs/STATUS.md"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" commit -qm "malformed record" >"$RP1DD/disc-$RP1_GEN.out" 2>&1
    printf 'exit=%s\n' "$?" >> "$RP1DD/disc-$RP1_GEN.out"
  done
  if cmp -s "$RP1DD/disc-pre.out" "$RP1DD/disc-now.out"; then
    bad "record differential control: a structured input DIVERGES between the generations" \
        "the generations agreed on a malformed record, so the identity cases above may be identical because the harness compares nothing"
  else
    ok "record differential control: a structured input DIVERGES between the generations, so the 7-case identity is evidence about absence"
  fi
fi

fi; shard_region_end
# <<< SHARD-END rp1-absence-differential
# --- the scaffold template and the upgrade's restraint -------------------------
if [[ -f "$ROOT/templates/claude/status.json" ]]; then
  RP1_TPL_VERDICT="$(jq -r "$(grep -m1 -E '^[[:space:]]*SLH_RECORD_CHECK_JQ=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed -e "s/^[[:space:]]*SLH_RECORD_CHECK_JQ='//" -e "s/'$//")" "$ROOT/templates/claude/status.json" 2>/dev/null || printf 'malformed')"
  if [[ "$RP1_TPL_VERDICT" == "ok" ]]; then
    ok "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)"
  else
    bad "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)" \
        "the reader said: $RP1_TPL_VERDICT"
  fi
else
  bad "record template: templates/claude/status.json parses against the shipped grammar (structured from birth means born valid)" \
      "the template file is missing; stamp.sh names it in the PLAN"
fi

# --- OWNERSHIP (design section 8): the declared set and the per-file arm ----
# >>> SHARD-BEGIN rp1-ownership cost=9
if shard_region rp1-ownership; then
# The lockstep for the Owns reader: TWO homes (the library asks the question
# at the squash landing, the audit at the pushed history), byte-identical.
RP1_OWNS_LIB="$(grep -m1 -E '^[[:space:]]*SLH_OWNS_AWK=' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | sed 's/^[[:space:]]*//')"
RP1_OWNS_TA="$(grep -m1 -E '^[[:space:]]*SLH_OWNS_AWK=' "$SCRIPTS/trunk-audit.sh" | sed 's/^[[:space:]]*//')"
if [[ -n "$RP1_OWNS_LIB" && "$RP1_OWNS_LIB" == "$RP1_OWNS_TA" ]]; then
  ok "owns lockstep: SLH_OWNS_AWK is byte-identical in the hook library and trunk-audit.sh"
else
  bad "owns lockstep: SLH_OWNS_AWK is byte-identical in the hook library and trunk-audit.sh" \
      "the two homes of the ownership grammar drifted"
fi

# The honest DECLARING squash close: files declared, files carried, clean.
RP1O1="$WORK/rp1-owns-honest"
rp1_fixture "$RP1O1"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O1/specs/0001-thing.md"
printf 'declared work\n' > "$RP1O1/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O1/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O1/specs/STATUS.md" > "$RP1O1/specs/STATUS.md.new" && mv "$RP1O1/specs/STATUS.md.new" "$RP1O1/specs/STATUS.md"
git -C "$RP1O1" add -A >/dev/null 2>&1
git -C "$RP1O1" -c core.hooksPath=/dev/null commit -qm "declaring squash-shaped close" >/dev/null 2>&1
RP1O1_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O1" 2>&1)" || true
if printf '%s' "$RP1O1_OUT" | grep -q ' 0 violations'; then
  ok "owns a: the honest declaring squash close passes on shape (its files were declared during the build)"
else
  bad "owns a: the honest declaring squash close passes on shape (its files were declared during the build)" \
      "audit said: $(printf '%s' "$RP1O1_OUT" | tail -2 | tr '\n' ' ')"
fi

# The refusal names BOTH honest exits, because a false-deny without a way out
# teaches the operator to reach for the skip hatch.
RP1O2="$WORK/rp1-owns-exits"
rp1_fixture "$RP1O2"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O2/specs/0001-thing.md"
printf 'declared\n' > "$RP1O2/src/feat.txt"
printf 'forgotten\n' > "$RP1O2/src/extra.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O2/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O2/specs/STATUS.md" > "$RP1O2/specs/STATUS.md.new" && mv "$RP1O2/specs/STATUS.md.new" "$RP1O2/specs/STATUS.md"
git -C "$RP1O2" add -A >/dev/null 2>&1
git -C "$RP1O2" -c core.hooksPath=/dev/null commit -qm "undeclared extra" >/dev/null 2>&1
RP1O2_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O2" 2>&1)" || true
if printf '%s' "$RP1O2_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/extra.txt' \
   && printf '%s' "$RP1O2_OUT" | grep -q 'checkpoint' \
   && printf '%s' "$RP1O2_OUT" | grep -q -- '--no-ff'; then
  ok "owns b: an undeclared role file in a declaring close refuses naming BOTH honest exits (declare through checkpoint, or the --no-ff route)"
else
  bad "owns b: an undeclared role file in a declaring close refuses naming BOTH honest exits (declare through checkpoint, or the --no-ff route)" \
      "audit said: $(printf '%s' "$RP1O2_OUT" | tail -3 | tr '\n' ' ')"
fi

# The grammar refusals: a glob, a directory, a below-the-heading line. Each is
# an exemption wearing a declaration, and each refuses AT THE ARM rather than
# being read charitably.
RP1_OWNS_BAD_MISS=""
while IFS='	' read -r RP1_OLBL RP1_OLINE; do
  [[ -n "$RP1_OLBL" ]] || continue
  RP1O3="$WORK/rp1-owns-$RP1_OLBL"
  rp1_fixture "$RP1O3"
  printf '# Spec 0001\n\nStatus: CLOSED\n%s\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' "$RP1_OLINE" > "$RP1O3/specs/0001-thing.md"
  printf 'work\n' > "$RP1O3/src/feat.txt"
  printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O3/.claude/status.json"
  sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O3/specs/STATUS.md" > "$RP1O3/specs/STATUS.md.new" && mv "$RP1O3/specs/STATUS.md.new" "$RP1O3/specs/STATUS.md"
  git -C "$RP1O3" add -A >/dev/null 2>&1
  git -C "$RP1O3" -c core.hooksPath=/dev/null commit -qm "owns $RP1_OLBL" >/dev/null 2>&1
  bash "$SCRIPTS/trunk-audit.sh" "$RP1O3" 2>&1 | grep -q '\[SLH-OWNS-MALFORMED\]' || RP1_OWNS_BAD_MISS="$RP1_OWNS_BAD_MISS $RP1_OLBL"
done <<'RP1OWNSBAD'
glob	Owns: src/*.txt
dir	Owns: src/
nospace	Owns:src/feat.txt
dotdot	Owns: src/../secrets.txt
RP1OWNSBAD
# The out-of-range case separately: the declaration sits BELOW the Closing
# report heading, outside what the attestation signs, so it counts for nothing
# and refuses rather than being silently ignored while a human reads it.
RP1O4="$WORK/rp1-owns-range"
rp1_fixture "$RP1O4"
printf '# Spec 0001\n\nStatus: CLOSED\n\n## Closing report\n\nOwns: src/feat.txt\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O4/specs/0001-thing.md"
printf 'work\n' > "$RP1O4/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O4/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O4/specs/STATUS.md" > "$RP1O4/specs/STATUS.md.new" && mv "$RP1O4/specs/STATUS.md.new" "$RP1O4/specs/STATUS.md"
git -C "$RP1O4" add -A >/dev/null 2>&1
git -C "$RP1O4" -c core.hooksPath=/dev/null commit -qm "owns out of range" >/dev/null 2>&1
bash "$SCRIPTS/trunk-audit.sh" "$RP1O4" 2>&1 | grep -q '\[SLH-OWNS-MALFORMED\]' || RP1_OWNS_BAD_MISS="$RP1_OWNS_BAD_MISS out-of-range"
if [[ -z "$RP1_OWNS_BAD_MISS" ]]; then
  ok "owns c: a glob, a directory, a spaceless label, a dot-dot path and an out-of-range line each refuse SLH-OWNS-MALFORMED at the arm that would consume them"
else
  bad "owns c: a glob, a directory, a spaceless label, a dot-dot path and an out-of-range line each refuse SLH-OWNS-MALFORMED at the arm that would consume them" \
      "not refused:$RP1_OWNS_BAD_MISS"
fi

# THE CHORE HALF (F5-2026): the compliant --squash chore close is accepted at
# the COMMIT layer (the squash landing through the real hooks) and at the PUSH
# layer (the audit), and the widening the 2.3.0 leg warned about does not
# occur: an undeclared file beside the chore flip still refuses per file.
RP1O5="$WORK/rp1-owns-chore"
rp1_fixture "$RP1O5"
git -C "$RP1O5" checkout -qb chore/tidy 2>/dev/null
printf 'tidied\n' > "$RP1O5/src/tidy.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-002":{"status":"done","files":["src/tidy.js"]}}}\n' > "$RP1O5/.claude/status.json"
printf -- '- CHORE-002: DONE 2026-08-30. Tidied.\n' >> "$RP1O5/specs/STATUS.md"
git -C "$RP1O5" add -A >/dev/null 2>&1
git -C "$RP1O5" -c core.hooksPath=/dev/null commit -qm "chore on branch" >/dev/null 2>&1
git -C "$RP1O5" checkout -q main 2>/dev/null
git -C "$RP1O5" merge --squash chore/tidy >/dev/null 2>&1
if git -C "$RP1O5" commit -qm "squash chore close" >"$WORK/rp1-owns-chore.out" 2>&1; then
  ok "owns d (F5-2026): the compliant --squash CHORE close is accepted at the commit layer"
else
  bad "owns d (F5-2026): the compliant --squash CHORE close is accepted at the commit layer" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-chore.out")"
fi
RP1O5_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O5" 2>&1)" || true
if printf '%s' "$RP1O5_OUT" | grep -q ' 0 violations'; then
  ok "owns e (F5-2026): the same chore close is accepted at the push layer, so the two layers stop disagreeing"
else
  bad "owns e (F5-2026): the same chore close is accepted at the push layer, so the two layers stop disagreeing" \
      "audit said: $(printf '%s' "$RP1O5_OUT" | tail -2 | tr '\n' ' ')"
fi
# The non-widening control: the chore route exempts ITS declared files only.
RP1O6="$WORK/rp1-owns-chorewide"
rp1_fixture "$RP1O6"
printf 'tidied\n' > "$RP1O6/src/tidy.js"
printf 'smuggled beside the chore\n' > "$RP1O6/src/extra.js"
printf '{"setlist_status":1,"specs":{"0001":{"status":"active"}},"chores":{"CHORE-002":{"status":"done","files":["src/tidy.js"]}}}\n' > "$RP1O6/.claude/status.json"
printf -- '- CHORE-002: DONE 2026-08-30. Tidied.\n' >> "$RP1O6/specs/STATUS.md"
git -C "$RP1O6" add -A >/dev/null 2>&1
git -C "$RP1O6" -c core.hooksPath=/dev/null commit -qm "chore flip with a rider" >/dev/null 2>&1
RP1O6_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O6" 2>&1)" || true
if printf '%s' "$RP1O6_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/extra.js'; then
  ok "owns f (F5-2026 non-widening): a chore flip exempts nothing but its declared files; the rider refuses by name"
else
  bad "owns f (F5-2026 non-widening): a chore flip exempts nothing but its declared files; the rider refuses by name" \
      "audit said: $(printf '%s' "$RP1O6_OUT" | tail -2 | tr '\n' ' ')"
fi

# THE LIBRARY'S HALF AT THE SQUASH LANDING: the same question, asked at the
# earliest layer that can refuse it, with the first honest exit then taken and
# the landing succeeding.
RP1O7="$WORK/rp1-owns-landing"
rp1_fixture "$RP1O7"
git -C "$RP1O7" checkout -qb spec/0001-thing 2>/dev/null
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O7/specs/0001-thing.md"
printf 'declared\n' > "$RP1O7/src/feat.txt"
printf 'smuggled\n' > "$RP1O7/src/wip.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O7/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1O7/specs/STATUS.md" > "$RP1O7/specs/STATUS.md.new" && mv "$RP1O7/specs/STATUS.md.new" "$RP1O7/specs/STATUS.md"
git -C "$RP1O7" add -A >/dev/null 2>&1
git -C "$RP1O7" -c core.hooksPath=/dev/null commit -qm "close with smuggle" >/dev/null 2>&1
git -C "$RP1O7" checkout -q main 2>/dev/null
git -C "$RP1O7" merge --squash spec/0001-thing >/dev/null 2>&1
if git -C "$RP1O7" commit -qm "squash close" >"$WORK/rp1-owns-landing.out" 2>&1; then
  bad "owns g: the squash landing refuses the undeclared file at the commit layer too" \
      "the landing succeeded carrying an undeclared role file"
else
  if grep -q 'SLH-OWNS-UNDECLARED' "$WORK/rp1-owns-landing.out"; then
    ok "owns g: the squash landing refuses the undeclared file at the commit layer too"
  else
    bad "owns g: the squash landing refuses the undeclared file at the commit layer too" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/rp1-owns-landing.out")"
  fi
fi
# The first honest exit: declare it, and the same landing succeeds.
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/feat.txt\nOwns: src/wip.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O7/specs/0001-thing.md"
git -C "$RP1O7" add specs/0001-thing.md >/dev/null 2>&1
if git -C "$RP1O7" commit -qm "squash close, declared" >"$WORK/rp1-owns-landing2.out" 2>&1; then
  ok "owns h: declaring the file (the first honest exit) lets the same landing succeed"
else
  bad "owns h: declaring the file (the first honest exit) lets the same landing succeed" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-landing2.out")"
fi

# THE DELETION AXIS (2.4.0 leg F7): a deleted path cannot carry unspecced
# content to the trunk, which is the only question the per-file arm is asked.
# The merge arm's own sibling already filters (--diff-filter=A at the
# provenance check); the single-parent arm must not read a deletion as a file
# the close "does not declare". Two closes: 0001 brings src/old.txt declared,
# 0002 brings src/new.txt declared and DELETES src/old.txt.
RP1O8="$WORK/rp1-owns-delete"
rp1_fixture "$RP1O8"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O8/specs/0001-thing.md"
printf 'first\n' > "$RP1O8/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1O8/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1O8/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1O8/specs/STATUS.md"
git -C "$RP1O8" add -A >/dev/null 2>&1
git -C "$RP1O8" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O8/specs/0002-other.md"
printf 'second\n' > "$RP1O8/src/new.txt"
git -C "$RP1O8" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O8/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1O8/specs/STATUS.md"
git -C "$RP1O8" add -A >/dev/null 2>&1
git -C "$RP1O8" -c core.hooksPath=/dev/null commit -qm "declaring close of 0002, retiring src/old.txt" >/dev/null 2>&1
RP1O8_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O8" 2>&1)" || true
if printf '%s' "$RP1O8_OUT" | grep -q ' 0 violations' \
   && ! printf '%s' "$RP1O8_OUT" | grep -q 'SLH-OWNS-UNDECLARED'; then
  ok "owns i (2.4.0 leg F7): a declaring close that DELETES a role-path file audits clean; stop shipping a file is not smuggling one"
else
  bad "owns i (2.4.0 leg F7): a declaring close that DELETES a role-path file audits clean; stop shipping a file is not smuggling one" \
      "audit said: $(printf '%s' "$RP1O8_OUT" | tail -3 | tr '\n' ' ')"
fi

# The false-negative guard beside it: the deletion filter must not mask an
# undeclared ADDITION riding the same close.
RP1O9="$WORK/rp1-owns-delete-smuggle"
rp1_fixture "$RP1O9"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O9/specs/0001-thing.md"
printf 'first\n' > "$RP1O9/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1O9/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1O9/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1O9/specs/STATUS.md"
git -C "$RP1O9" add -A >/dev/null 2>&1
git -C "$RP1O9" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1O9/specs/0002-other.md"
printf 'second\n' > "$RP1O9/src/new.txt"
printf 'smuggled\n' > "$RP1O9/src/sneak.txt"
git -C "$RP1O9" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1O9/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1O9/specs/STATUS.md"
git -C "$RP1O9" add -A >/dev/null 2>&1
git -C "$RP1O9" -c core.hooksPath=/dev/null commit -qm "close of 0002 with a rider" >/dev/null 2>&1
RP1O9_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1O9" 2>&1)" || true
if printf '%s' "$RP1O9_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/sneak.txt' \
   && ! printf '%s' "$RP1O9_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/old.txt'; then
  ok "owns j (2.4.0 leg F7 guard): the deletion filter does not mask an undeclared addition riding the same close"
else
  bad "owns j (2.4.0 leg F7 guard): the deletion filter does not mask an undeclared addition riding the same close" \
      "audit said: $(printf '%s' "$RP1O9_OUT" | tail -3 | tr '\n' ' ')"
fi

# The library's half at the squash landing: the same deletion, refused today at
# the earliest layer, must land once declared coverage holds for what ARRIVES.
# A REAL `merge --squash` then commit, because the landing arm keys on the
# squash-completion state and a hand-staged equivalent never enters it.
RP1OA="$WORK/rp1-owns-delete-landing"
rp1_fixture "$RP1OA"
printf '# Spec 0001\n\nStatus: CLOSED\nOwns: src/old.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OA/specs/0001-thing.md"
printf 'first\n' > "$RP1OA/src/old.txt"
printf '# Spec 0002\n\nStatus: ACTIVE\n\n## Goal\n\nother\n' > "$RP1OA/specs/0002-other.md"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"active"}},"chores":{}}\n' > "$RP1OA/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | ACTIVE | wip |\n' > "$RP1OA/specs/STATUS.md"
git -C "$RP1OA" add -A >/dev/null 2>&1
git -C "$RP1OA" -c core.hooksPath=/dev/null commit -qm "declaring close of 0001" >/dev/null 2>&1
git -C "$RP1OA" checkout -qb spec/0002-other 2>/dev/null
printf '# Spec 0002\n\nStatus: CLOSED\nOwns: src/new.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OA/specs/0002-other.md"
printf 'second\n' > "$RP1OA/src/new.txt"
git -C "$RP1OA" rm -q src/old.txt >/dev/null 2>&1
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"},"0002":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1OA/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n| 0002 | Other | CLOSED | done |\n' > "$RP1OA/specs/STATUS.md"
git -C "$RP1OA" add -A >/dev/null 2>&1
git -C "$RP1OA" -c core.hooksPath=/dev/null commit -qm "build 0002, retiring src/old.txt" >/dev/null 2>&1
git -C "$RP1OA" checkout -q main 2>/dev/null
git -C "$RP1OA" -c merge.ff=true merge --squash spec/0002-other >/dev/null 2>&1
if git -C "$RP1OA" commit -qm "squash close of 0002, retiring src/old.txt" >"$WORK/rp1-owns-del-landing.out" 2>&1; then
  ok "owns k (2.4.0 leg F7): the squash landing accepts a declaring close whose only extra path is a deletion"
else
  bad "owns k (2.4.0 leg F7): the squash landing accepts a declaring close whose only extra path is a deletion" \
      "$(tr '\n' ' ' < "$WORK/rp1-owns-del-landing.out")"
fi

# THE FENCED-QUOTE LAYOUT (2.4.0 leg F1, ruled option C 2026-09-01): a fenced
# copy of the Closing-report template ABOVE the declaration ends the hashed
# range early, the reader and spec-hash.sh agree on that cut byte for byte, and
# the ruling keeps them agreed: the layout REFUSES, and the refusal must name
# the actual cause and the one-edit fix instead of stating the opposite of the
# file's contents. If a later change fence-strips the reader, this pin flips
# and the Known-limitations bullet, spec-hash.sh and the attestation-custody
# question all have to move in the same commit.
RP1OB="$WORK/rp1-owns-fenced"
rp1_fixture "$RP1OB"
printf '# Spec 0001\n\nStatus: CLOSED\n\nI will fill this in at the close:\n\n```markdown\n## Closing report\n\nArchitecture diagram: <updated in this commit | no impact>\n```\n\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\na: PASS\n```\n' > "$RP1OB/specs/0001-thing.md"
printf 'declared\n' > "$RP1OB/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0001":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$RP1OB/.claude/status.json"
sed -e 's/| ACTIVE |/| CLOSED |/' "$RP1OB/specs/STATUS.md" > "$RP1OB/specs/STATUS.md.new" && mv "$RP1OB/specs/STATUS.md.new" "$RP1OB/specs/STATUS.md"
git -C "$RP1OB" add -A >/dev/null 2>&1
git -C "$RP1OB" -c core.hooksPath=/dev/null commit -qm "close with a fenced template quote above the declaration" >/dev/null 2>&1
RP1OB_OUT="$(bash "$SCRIPTS/trunk-audit.sh" "$RP1OB" 2>&1)" || true
if printf '%s' "$RP1OB_OUT" | grep -q '\[SLH-OWNS-MALFORMED\]' \
   && printf '%s' "$RP1OB_OUT" | grep -q 'fences included' \
   && printf '%s' "$RP1OB_OUT" | grep -q 'one edit'; then
  ok "owns l (2.4.0 leg F1, ruled option C): the fenced-quote layout refuses WITH the honest message naming the cause and the one-edit fix"
else
  bad "owns l (2.4.0 leg F1, ruled option C): the fenced-quote layout refuses WITH the honest message naming the cause and the one-edit fix" \
      "audit said: $(printf '%s' "$RP1OB_OUT" | tail -3 | tr '\n' ' ')"
fi

# stamp.sh delivers the record in BOTH modes; refresh-instance.sh (the upgrade
# deliverer) must NEVER deliver it: mention the field, migrate NOTHING.
if grep -qE '^add claude/status\.json' "$SCRIPTS/stamp.sh"; then
  ok "record delivery a: stamp.sh stamps .claude/status.json (structured from birth, both modes)"
else
  bad "record delivery a: stamp.sh stamps .claude/status.json (structured from birth, both modes)" \
      "no add line names claude/status.json"
fi
if grep -q 'status\.json' "$SCRIPTS/refresh-instance.sh"; then
  bad "record delivery b: refresh-instance.sh never delivers or creates the record (BL-005: mention the field, migrate NOTHING)" \
      "refresh-instance.sh mentions status.json; the upgrade path must not touch the record"
else
  ok "record delivery b: refresh-instance.sh never delivers or creates the record (BL-005: mention the field, migrate NOTHING)"
fi

fi; shard_region_end
# <<< SHARD-END rp1-ownership
