#!/usr/bin/env bash
# test/suite/13-push-scan-kl2-kl4.sh: shard 13 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# >>> SHARD-BEGIN push-scan-kl2 cost=9
if shard_region push-scan-kl2; then
# THE PUSH-TIME SCAN: KL2 AND THE FOUR SCAN SUB-HOLES (spec 0121, 2026-08-26).
#
# Every case pushes to a real local bare remote through the armed hook layer,
# because what is being asserted is what git's own invocation of pre-push
# decides, not what a function returns when called directly.
#
# THE SCAN IS ISOLATED FROM THE AUDIT by putting the secret OUTSIDE the declared
# role paths, so the trunk audit has nothing to say and only the scan can refuse.
# A first cut of this block put it in src/, and then the audit refused three of
# the cases for its own unrelated reason: the assertions passed while proving
# nothing about the scan. The two KL2 cases below are the exception, because they
# are ABOUT which check the escape variable turns off.
#
# Watched RED first against the pre-fix bytes, all six subjects, with both
# controls holding in the same run: the plain-secret control, KL2's scan case,
# SC3, SC4, SC5 and SC6 were all PUSHED where they should have been REFUSED.
# =============================================================================
sp_mk() { # sp_mk <name> -> an armed instance with a bare remote, prints its path
  local d="$WORK/sp-$1"
  rm -rf "$d" "$WORK/sp-$1.git"
  mkdir -p "$d/.claude/hooks" "$d/.githooks" "$d/src" "$d/specs" "$d/docs"
  git_init "$d"
  printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src"}}\n' > "$d/.claude/sdd.json"
  printf '# inv\n\n| Spec | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" \
     "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" "$d/.githooks/"
  cp "$SCRIPTS/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push" "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$d" commit -qm base >/dev/null 2>&1
  git init -q --bare "$WORK/sp-$1.git"
  git -C "$d" remote add origin "$WORK/sp-$1.git"
  printf '%s' "$d"
}
sp_commit() { # sp_commit <dir> <path> <content>
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A >/dev/null 2>&1
  SETLIST_SKIP_HOOKS=1 git -C "$1" commit -qm "add $2" >/dev/null 2>&1
}
sp_push() { # sp_push <dir> [env-assignment...] -> 0 when the push LANDED
  local d="$1"; shift
  env "$@" git -C "$d" push -q origin main >/dev/null 2>&1
}
SP_SECRET='api_key = "AKIAQQQQZZZZ1234567890abcd"'

# CONTROL a, the ALLOW direction. Without it every refusal below would pass
# against a hook that refuses everything.
SPD="$(sp_mk clean)"; SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -q --allow-empty -m x >/dev/null 2>&1
if sp_push "$SPD"; then
  ok "push scan control a: a clean push succeeds"
else
  bad "push scan control a: a clean push succeeds" \
      "a clean first push was refused, so every refusal below proves nothing. This is the shape the SC4 fix broke and its own control caught: merge-base(trunk, tip) IS the tip, so a naive range is empty for the trunk itself"
fi

# CONTROL b, the DENY direction, and it is also SC4's subject: a first push whose
# history carries a secret. On the pre-fix bytes this PUSHED.
SPD="$(sp_mk plain)"; sp_commit "$SPD" docs/a.txt "$SP_SECRET"
if sp_push "$SPD"; then
  bad "push scan control b: a secret in a first push is refused (SC sub-hole 4)" \
      "it pushed. The first push of a trunk has no remote oid and no merge base with itself, so the range came out empty and the push that ESTABLISHES a repository is scanned by nothing"
else
  ok "push scan control b: a secret in a first push is refused (SC sub-hole 4)"
fi

# KL2, direction 1: the AUDIT escape must not turn the SCAN off.
SPD="$(sp_mk kl2a)"; sp_commit "$SPD" src/a.txt "$SP_SECRET"
if sp_push "$SPD" SETLIST_SKIP_TRUNK_AUDIT=1; then
  bad "KL2: SETLIST_SKIP_TRUNK_AUDIT=1 does NOT skip the content scan" \
      "the secret was published. The audit's escape is turning off the secret scan as well, which is the whole of KL2: the variable is named for the audit and must skip the audit"
else
  ok "KL2: SETLIST_SKIP_TRUNK_AUDIT=1 does NOT skip the content scan"
fi

# KL2, direction 2: it really does skip the audit. Asserted because a narrowing
# that quietly stopped honouring the variable would also pass direction 1.
SPD="$(sp_mk kl2b)"; sp_commit "$SPD" src/f.txt 'ordinary feature code'
if sp_push "$SPD" SETLIST_SKIP_TRUNK_AUDIT=1; then
  ok "KL2 control: SETLIST_SKIP_TRUNK_AUDIT=1 still skips the audit"
else
  bad "KL2 control: SETLIST_SKIP_TRUNK_AUDIT=1 still skips the audit" \
      "the escape no longer works at all, so direction 1 above proves nothing about narrowing"
fi

# KL2, direction 3: without the escape that same push IS refused by the audit,
# which is what makes direction 2 a skip rather than a clean trunk.
SPD="$(sp_mk kl2c)"; sp_commit "$SPD" src/f.txt 'ordinary feature code'
if sp_push "$SPD"; then
  bad "KL2 control: with no escape the audit refuses that same push" \
      "it pushed with no escape set, so the case above proves nothing"
else
  ok "KL2 control: with no escape the audit refuses that same push"
fi

# SC sub-hole 3: content ADDED and then REMOVED inside the pushed range. An
# endpoint diff never renders it while every object still reaches the remote.
SPD="$(sp_mk sc3)"; sp_commit "$SPD" docs/a.txt "$SP_SECRET"
rm -f "$SPD/docs/a.txt"; git -C "$SPD" add -A >/dev/null 2>&1
SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -qm rm >/dev/null 2>&1
if sp_push "$SPD"; then
  bad "SC sub-hole 3: a secret added then removed inside the range is refused" \
      "it pushed. The scan is reading an ENDPOINT diff again, so it asks what the range CHANGES when the question is what the range CARRIES"
else
  ok "SC sub-hole 3: a secret added then removed inside the range is refused"
fi

# SC sub-hole 5: a TAG push carrying a secret no pushed branch reaches.
SPD="$(sp_mk sc5)"; SETLIST_SKIP_HOOKS=1 git -C "$SPD" commit -q --allow-empty -m base >/dev/null 2>&1
git -C "$SPD" push -q origin main >/dev/null 2>&1
git -C "$SPD" checkout -q -b side
sp_commit "$SPD" docs/a.txt "$SP_SECRET"
git -C "$SPD" tag sp-v9.9.9 >/dev/null 2>&1
git -C "$SPD" checkout -q main; git -C "$SPD" branch -qD side >/dev/null 2>&1
if git -C "$SPD" push -q origin sp-v9.9.9 >/dev/null 2>&1; then
  bad "SC sub-hole 5: a tag push carrying a secret is refused" \
      "it pushed. Every ref that is not refs/heads/* is being skipped, and a tag can name a commit no branch reaches, so it is the one shape where the content is reachable ONLY through the ref being pushed"
else
  ok "SC sub-hole 5: a tag push carrying a secret is refused"
fi

# SC sub-hole 6: a secret on a line whose own content begins with +++, which the
# unanchored header strip removed from the scan's input.
SPD="$(sp_mk sc6)"; sp_commit "$SPD" docs/a.txt "+++$SP_SECRET"
if sp_push "$SPD"; then
  bad "SC sub-hole 6: a secret behind a +++ prefix is refused" \
      "it pushed. The header strip is unanchored again, so it is eating added lines whose content starts with ++ as well as the diff's own +++ b/ header"
else
  ok "SC sub-hole 6: a secret behind a +++ prefix is refused"
fi

fi; shard_region_end
# <<< SHARD-END push-scan-kl2
# ===========================================================================
# KL4: PATH-SCOPED SCANS, THE DECLARED EXCLUSION SET NAMED OUT LOUD (spec 0122).
#
# The em-dash and secret scans read every added line, so a vendored tree, a
# fixture carrying a dummy credential, and quoted external text are refused
# identically to the author's own writing. The fix is a DECLARED set of
# repo-relative globs in .claude/sdd.json, honoured by both content scans at
# both the commit and the push layer.
#
# WHAT THIS BLOCK IS EVIDENCE OF, said once so no green below is read as more
# than it is (A8). An excluded-path green is evidence of SCOPING, never of
# scanning: it proves the scan declined to read a path it was told to decline,
# and it proves nothing at all about the scanner. That is why every excluded
# cell has a non-excluded twin immediately beside it, and why the twin is the
# assertion that keeps the pair honest.
#
# THE SKIP IS NAMED, EVERY TIME. An exclusion nobody is told about is the same
# hole one directory over, which this project has already paid for once in the
# hooksPath displacement. So the assertions below check the OUTPUT as well as
# the verdict: a clean commit whose stderr says nothing about the file it did
# not read would fail here even though the commit succeeded.
# ===========================================================================

KL4_SECRET='const api_key = "EXAMPLE_NOT_A_REAL_SECRET_0123456789";'
KL4_DASHLINE="a $EMDASH b"

kl4_fixture() { # kl4_fixture <dir> [scan_exclusions-json]
  local d="$1" ex="${2:-}"
  rm -rf "$d" "$d-rem.git"
  mkdir -p "$d/src" "$d/vendor/dep" "$d/specs" "$d/.claude/hooks" "$d/.githooks"
  git_init "$d"
  if [[ -n "$ex" ]]; then
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"scan_exclusions":%s}\n' "$ex" > "$d/.claude/sdd.json"
  else
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  fi
  printf 'x\n' > "$d/src/app.js"
  printf 'v\n' > "$d/vendor/dep/lib.js"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/pre-push" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit" "$d/.githooks/pre-push"
  # pre-push refuses for want of the audit tool if this is missing, and every
  # case below would then pass while reaching nothing (the fixture gap that
  # produced a false refutation during the F2 triage).
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm stamp >/dev/null 2>&1
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # The remote is seeded with a trunk so it is NOT empty: on an empty remote
  # every pushed ref is a trunk candidate and IS audited, which would refuse
  # these branches for a reason that has nothing to do with the scan.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b work
}

KL4_ERR=""
kl4_commit() { # kl4_commit <dir> <msg> -> rc, output in KL4_ERR
  KL4_ERR="$(git -C "$1" commit -qm "$2" 2>&1)"
}
kl4_push() { # kl4_push <dir> <branch> -> rc, output in KL4_ERR
  KL4_ERR="$(git -C "$1" push -q origin "$2" 2>&1)"
}

# --- the four cells, both directions at both layers -------------------------

# CELL 1: an excluded path carrying BOTH shapes commits clean AND says so.
KL4A="$WORK/kl4-commit-excluded"; kl4_fixture "$KL4A" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4A/vendor/dep/lib.js"
git -C "$KL4A" add -A >/dev/null 2>&1
if kl4_commit "$KL4A" "vendored"; then
  ok "KL4 cell 1a: an excluded path carrying an em-dash and a secret COMMITS clean"
else
  bad "KL4 cell 1a: an excluded path carrying an em-dash and a secret COMMITS clean" \
      "refused: $KL4_ERR"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/dep/lib.js' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/\*\*'; then
  ok "KL4 cell 1b: the commit-layer skip NAMES the path and the glob that caused it"
else
  bad "KL4 cell 1b: the commit-layer skip NAMES the path and the glob that caused it" \
      "a scan that silently skips a path is the vacuous-green class wearing a feature's name. stderr was: $KL4_ERR"
fi

# CELL 2: the IDENTICAL content on a non-excluded path is still refused, with
# the existing codes. Without this the cell above is satisfied by a hook that
# stopped scanning.
KL4B="$WORK/kl4-commit-scanned"; kl4_fixture "$KL4B" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4B/src/app.js"
git -C "$KL4B" add -A >/dev/null 2>&1
if kl4_commit "$KL4B" "mine"; then
  bad "KL4 cell 2a: the identical content on a NON-excluded path is still refused at commit" \
      "it committed, so the exclusion set is over-wide and the scan is off for everything"
else
  ok "KL4 cell 2a: the identical content on a NON-excluded path is still refused at commit"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-EMDASH' && printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 cell 2b: the refusal carries the EXISTING codes, both of them"
else
  bad "KL4 cell 2b: the refusal carries the EXISTING codes, both of them" "stderr was: $KL4_ERR"
fi

# CELL 3: the push layer, excluded path. The commit is made with the hooks
# bypassed so the PUSH is what is being measured.
KL4C="$WORK/kl4-push-excluded"; kl4_fixture "$KL4C" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4C/vendor/dep/lib.js"
git -C "$KL4C" add -A >/dev/null 2>&1
git -C "$KL4C" -c core.hooksPath=/dev/null commit -qm "vendored" >/dev/null 2>&1
if kl4_push "$KL4C" work; then
  ok "KL4 cell 3a: an excluded path carrying an em-dash and a secret PUSHES clean"
else
  bad "KL4 cell 3a: an excluded path carrying an em-dash and a secret PUSHES clean" \
      "refused: $KL4_ERR"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' \
   && printf '%s' "$KL4_ERR" | grep -q 'vendor/dep/lib.js'; then
  ok "KL4 cell 3b: the push-layer skip NAMES the path, at the layer that publishes"
else
  bad "KL4 cell 3b: the push-layer skip NAMES the path, at the layer that publishes" \
      "stderr was: $KL4_ERR"
fi

# CELL 4: the push layer, non-excluded path, still refuses.
KL4D="$WORK/kl4-push-scanned"; kl4_fixture "$KL4D" '["vendor/**"]'
{ printf '%s\n' "$KL4_DASHLINE"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4D/src/app.js"
git -C "$KL4D" add -A >/dev/null 2>&1
git -C "$KL4D" -c core.hooksPath=/dev/null commit -qm "mine" >/dev/null 2>&1
if kl4_push "$KL4D" work; then
  bad "KL4 cell 4: the identical content on a NON-excluded path is still refused at push" \
      "it pushed, so the secret reached a remote and the exclusion set is scoping the whole scan"
else
  ok "KL4 cell 4: the identical content on a NON-excluded path is still refused at push"
fi

# --- the default: absence changes NOTHING, proven rather than asserted ------
#
# The feature is invisible until asked for, and "byte-identical to today" is a
# claim about BEHAVIOUR that a reading of the code cannot settle. So the two
# generations are run side by side over a corpus, in fixtures that differ in
# nothing but the hook bytes, and the verdict AND the operator-visible output
# are compared exactly. The pre-feature generation is pinned by BLOB, not by a
# revision expression: a blob is immutable, so this differential keeps meaning
# the same thing after every later commit.
KL4_OLD_PRECOMMIT=87e0c147ab413a6448675703d4a16b9e7fc7436a
KL4_OLD_PREMERGE=eac8743342281e4edfe17be7052e713f28f405c2
KL4_OLD_PREPUSH=273d972c024696cda2bb8b9e4d09e4c7cbbd093e
KL4_OLD_LIB=72c493c4efc0fff1ada3e08994ba66045586bed6

if git -C "$ROOT" cat-file -e "$KL4_OLD_LIB" 2>/dev/null; then
  KL4_OLD="$WORK/kl4-default-old"; kl4_fixture "$KL4_OLD"
  KL4_NEW="$WORK/kl4-default-new"; kl4_fixture "$KL4_NEW"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PRECOMMIT" > "$KL4_OLD/.githooks/pre-commit"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PREMERGE"  > "$KL4_OLD/.githooks/pre-merge-commit"
  git -C "$ROOT" cat-file blob "$KL4_OLD_PREPUSH"   > "$KL4_OLD/.githooks/pre-push"
  git -C "$ROOT" cat-file blob "$KL4_OLD_LIB"       > "$KL4_OLD/.githooks/setlist-hook-lib.sh"
  chmod +x "$KL4_OLD/.githooks/pre-commit" "$KL4_OLD/.githooks/pre-merge-commit" "$KL4_OLD/.githooks/pre-push"

  # The corpus. Every shape the header strip and the added-line reader have ever
  # been wrong about, plus the ordinary ones, because a differential over three
  # easy cases proves the easy cases only.
  KL4_DIFF_CASES=0
  KL4_DIFF_BAD=""
  kl4_diff_one() { # kl4_diff_one <label> <path> <content...>
    local label="$1" p="$2"; shift 2
    local d rc out old="" new=""
    for d in "$KL4_OLD" "$KL4_NEW"; do
      mkdir -p "$d/$(dirname "$p")"
      printf '%s\n' "$@" > "$d/$p"
      git -C "$d" add -A >/dev/null 2>&1
      out="$(git -C "$d" commit -qm "$label" 2>&1)"; rc=$?
      out="${out//$d/<DIR>}"
      out="$(norm_escape_coaching_str "$out")"
      if [[ "$d" == "$KL4_OLD" ]]; then old="rc=$rc
$out"; else new="rc=$rc
$out"; fi
      [[ "$rc" -eq 0 ]] || { git -C "$d" reset -q --hard HEAD >/dev/null 2>&1; }
    done
    KL4_DIFF_CASES=$((KL4_DIFF_CASES + 1))
    [[ "$old" == "$new" ]] || KL4_DIFF_BAD="$KL4_DIFF_BAD
[$label]
OLD: $old
NEW: $new"
  }

  kl4_diff_one "clean"        src/d1.txt "ordinary content" "second line"
  kl4_diff_one "emdash"       src/d2.txt "$KL4_DASHLINE"
  kl4_diff_one "secret"       src/d3.txt "$KL4_SECRET"
  kl4_diff_one "both"         src/d4.txt "$KL4_DASHLINE" "$KL4_SECRET"
  kl4_diff_one "plusplusplus" src/d5.txt "+++$KL4_SECRET"
  kl4_diff_one "plusplus"     src/d6.txt "++$KL4_DASHLINE"
  kl4_diff_one "forgedheader" src/d7.txt "+++ b/vendor/dep/lib.js" "$KL4_SECRET"
  kl4_diff_one "devnullline"  src/d8.txt "+++ /dev/null" "$KL4_DASHLINE"
  kl4_diff_one "vendorclean"  vendor/dep/other.js "ordinary vendored content"
  kl4_diff_one "vendordirty"  vendor/dep/dirty.js "$KL4_SECRET"
  kl4_diff_one "deepclean"    src/nested/deep/x.txt "nothing to see"
  kl4_diff_one "url"          src/d9.txt 'https://user:supersecretvalue@example.invalid/x'

  if [[ "$KL4_DIFF_CASES" -eq 12 ]]; then
    ok "KL4 default-unchanged: the differential ran all 12 corpus cases (count asserted before comparing)"
  else
    bad "KL4 default-unchanged: the differential ran all 12 corpus cases (count asserted before comparing)" \
        "ran $KL4_DIFF_CASES; a differential over a corpus nobody counted is the vacuous comparison A8 exists for"
  fi
  if [[ -z "$KL4_DIFF_BAD" ]]; then
    ok "KL4 default-unchanged: with NO scan_exclusions key, the new hook bytes are verdict- and output-identical to the pre-feature generation over the whole corpus"
  else
    bad "KL4 default-unchanged: with NO scan_exclusions key, the new hook bytes are verdict- and output-identical to the pre-feature generation over the whole corpus" \
        "the feature is supposed to be invisible until asked for, and it is not:$KL4_DIFF_BAD"
  fi
else
  ok "KL4 default-unchanged: pre-feature hook blobs not present here (export tree); the source-repo run asserts the differential"
fi

# --- malformed config fails CLOSED, at both layers, asserted both ways ------
# >>> SHARD-BEGIN kl4-malformed-config cost=15
if shard_region kl4-malformed-config; then
#
# Never a silent full-scan and never a silent no-scan. Both directions are
# needed because each alone is satisfiable by the wrong fix: a config error that
# quietly scans everything looks fine until somebody relies on the exclusion,
# and a config error that quietly scans nothing is the empty-result-as-verdict
# class with a feature's name on it.
kl4_malformed() { # kl4_malformed <label> <json> <expected-code>
  local label="$1" json="$2" code="$3" d
  d="$WORK/kl4-bad-$label"; kl4_fixture "$d" "$json"
  # DIRECTION ONE: clean content. A malformed set must refuse even here, or the
  # scan is running on an unread configuration.
  printf 'ordinary clean content\n' >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  if kl4_commit "$d" clean; then
    bad "KL4 malformed/$label: CLEAN content is refused at commit (never a silent scan on an unread config)" \
        "it committed, so the hook decided with a configuration it could not read"
  else
    ok "KL4 malformed/$label: CLEAN content is refused at commit (never a silent scan on an unread config)"
  fi
  if printf '%s' "$KL4_ERR" | grep -q "$code"; then
    ok "KL4 malformed/$label: the refusal carries the named code $code"
  else
    bad "KL4 malformed/$label: the refusal carries the named code $code" "stderr was: $KL4_ERR"
  fi
  # DIRECTION TWO: a real secret. A malformed set must not become an accidental
  # exemption.
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  printf '%s\n' "$KL4_SECRET" >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  if kl4_commit "$d" dirty; then
    bad "KL4 malformed/$label: a SECRET is refused at commit (a broken config is not an exemption)" \
        "it committed, so an unparseable exclusion set turned the scan off"
  else
    ok "KL4 malformed/$label: a SECRET is refused at commit (a broken config is not an exemption)"
  fi
  # AND AT THE PUSH LAYER, which is the one that publishes.
  git -C "$d" reset -q --hard HEAD >/dev/null 2>&1
  printf 'ordinary clean content\n' >> "$d/src/app.js"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm clean >/dev/null 2>&1
  if kl4_push "$d" work; then
    bad "KL4 malformed/$label: the PUSH layer refuses on the same unreadable config" \
        "it pushed, so the two layers disagree about a configuration neither can read"
  else
    ok "KL4 malformed/$label: the PUSH layer refuses on the same unreadable config"
  fi
  if printf '%s' "$KL4_ERR" | grep -q "$code"; then
    ok "KL4 malformed/$label: the push refusal carries the same named code $code"
  else
    bad "KL4 malformed/$label: the push refusal carries the same named code $code" "stderr was: $KL4_ERR"
  fi
}

kl4_malformed string   '"vendor/**"'            SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed object   '{"a":"b"}'              SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed number   '[123]'                  SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed nested   '[["vendor/**"]]'        SLH-SCAN-EXCLUSIONS-SHAPE
kl4_malformed empty    '[""]'                   SLH-SCAN-EXCLUSION-INVALID
kl4_malformed dotdot   '["../outside/**"]'      SLH-SCAN-EXCLUSION-INVALID
kl4_malformed space    '["my vendor/**"]'       SLH-SCAN-EXCLUSION-INVALID
kl4_malformed shellish '["vendor/**)rm -rf ."]' SLH-SCAN-EXCLUSION-INVALID
kl4_malformed star     '["*"]'                  SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed starstar '["**"]'                 SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed slashy   '["*/*"]'                SLH-SCAN-EXCLUSION-CATCHALL
kl4_malformed anychar  '["?"]'                  SLH-SCAN-EXCLUSION-CATCHALL

# An EMPTY array is not malformed: it is a project that declared the key and
# excluded nothing, and it must behave exactly like absence. This is the
# shipped-template state, so getting it wrong refuses every commit in a freshly
# stamped instance.
#
# THE REFUSAL IS CHECKED BY CODE, NOT BY VERDICT, and this pair is why. The
# first cut of this assertion only asked whether the commit was refused. It was,
# with SLH-SCAN-EXCLUSION-INVALID, because [] and [""] collapsed to the same
# string once command substitution stripped the trailing newline: the reader
# refused a project that had declared nothing, the assertion went green, and the
# defect was found by hook-smoke and delivery-matrix instead. A green labelled
# with the verdict rather than with the evidence (A8), committed by the test for
# that very class.
KL4E="$WORK/kl4-empty-array"; kl4_fixture "$KL4E" '[]'
printf '%s\n' "$KL4_SECRET" >> "$KL4E/src/app.js"
git -C "$KL4E" add -A >/dev/null 2>&1
if kl4_commit "$KL4E" dirty; then
  bad "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses" \
      "it committed, so [] read as 'exclude everything', which is the direction that publishes"
elif printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses"
else
  bad "KL4 empty array: an empty exclusion set excludes nothing and the SECRET SCAN is what refuses" \
      "it was refused, but not by the scan: $KL4_ERR. A refusal for the wrong reason is a green that proves the opposite of what it claims"
fi
# And the clean twin: an empty set must let ordinary work through, which is the
# direction the shipped template lands in every stamped instance.
git -C "$KL4E" reset -q --hard HEAD >/dev/null 2>&1
printf 'ordinary content\n' >> "$KL4E/src/app.js"
git -C "$KL4E" add -A >/dev/null 2>&1
if kl4_commit "$KL4E" clean; then
  ok "KL4 empty array: and clean content COMMITS, so the shipped template does not refuse every commit in a fresh instance"
else
  bad "KL4 empty array: and clean content COMMITS, so the shipped template does not refuse every commit in a fresh instance" \
      "refused: $KL4_ERR"
fi

fi; shard_region_end
# <<< SHARD-END kl4-malformed-config
# --- the boundary cases the traps live in -----------------------------------
# >>> SHARD-BEGIN kl4-boundary-traps cost=14
if shard_region kl4-boundary-traps; then

# A glob that matches NOTHING must not read as coverage. The scan still refuses,
# and nothing is announced as skipped: an exclusion that did not fire has no
# business printing that it did.
KL4N="$WORK/kl4-matches-nothing"; kl4_fixture "$KL4N" '["nosuchdir/**"]'
printf '%s\n' "$KL4_SECRET" >> "$KL4N/src/app.js"
git -C "$KL4N" add -A >/dev/null 2>&1
if kl4_commit "$KL4N" dirty; then
  bad "KL4 matches-nothing: a glob matching no path in the change changes no verdict" "it committed"
else
  ok "KL4 matches-nothing: a glob matching no path in the change changes no verdict"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED'; then
  bad "KL4 matches-nothing: nothing is ANNOUNCED as skipped when nothing was skipped" \
      "the hook printed an exclusion notice for a path it scanned, which is a skip report that reads as coverage: $KL4_ERR"
else
  ok "KL4 matches-nothing: nothing is ANNOUNCED as skipped when nothing was skipped"
fi

# PATH NORMALISATION. The declared side is normalised the way role paths already
# are, so the four spellings of one directory mean one thing. The raw-vs-
# normalised split is what made the guarantee layer go blind on "./src" once.
kl4_spelling() { # kl4_spelling <label> <json> <expect: excluded|scanned>
  local label="$1" json="$2" expect="$3" d rc
  d="$WORK/kl4-spell-$label"; kl4_fixture "$d" "$json"
  printf '%s\n' "$KL4_SECRET" >> "$d/vendor/dep/lib.js"
  git -C "$d" add -A >/dev/null 2>&1
  kl4_commit "$d" spell; rc=$?
  if [[ "$expect" == "excluded" ]]; then
    if [[ "$rc" -eq 0 ]] && printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED'; then
      ok "KL4 spelling/$label: $json excludes vendor/dep/lib.js and says so"
    else
      bad "KL4 spelling/$label: $json excludes vendor/dep/lib.js and says so" "rc=$rc stderr: $KL4_ERR"
    fi
  else
    if [[ "$rc" -ne 0 ]]; then
      ok "KL4 spelling/$label: $json does NOT exclude vendor/dep/lib.js, so the scan still refuses"
    else
      bad "KL4 spelling/$label: $json does NOT exclude vendor/dep/lib.js, so the scan still refuses" \
          "it committed, so a spelling that names a different path is silently excluding this one"
    fi
  fi
}
kl4_spelling glob       '["vendor/**"]'      excluded
kl4_spelling single     '["vendor/*"]'       excluded
kl4_spelling bare       '["vendor"]'         excluded
kl4_spelling trailing   '["vendor/"]'        excluded
kl4_spelling dotslash   '["./vendor/**"]'    excluded
kl4_spelling leading    '["/vendor/**"]'     excluded
kl4_spelling doubled    '["vendor//dep/**"]' excluded
kl4_spelling exactfile  '["vendor/dep/lib.js"]' excluded
kl4_spelling suffix     '["*.js"]'           excluded
# CASE IS EXACT, DELIBERATELY, and the direction is the safe one: a case variant
# fails to match, so the scan RUNS. On a case-insensitive filesystem the file is
# the same file, and an exclusion that guessed would be an exclusion nobody
# declared. Pinned so a later widening is a decision rather than drift.
kl4_spelling casevariant '["VENDOR/**"]'     scanned
kl4_spelling neighbour   '["vendors/**"]'    scanned
kl4_spelling prefixonly  '["vend"]'          scanned

# A CONTENT LINE CANNOT FORGE A FILE HEADER. Added lines carry a prefix column,
# so `diff --git` and `@@` are unforgeable inside a hunk; attribution is taken
# from the header state machine rather than from any line that looks like one.
# Without that, a diff-of-a-diff could point the scanner's attribution at an
# excluded path and carry a secret through under its name.
KL4F="$WORK/kl4-forged-attribution"; kl4_fixture "$KL4F" '["vendor/**"]'
{ printf '%s\n' "+++ b/vendor/dep/lib.js"; printf '%s\n' "$KL4_SECRET"; } >> "$KL4F/src/app.js"
git -C "$KL4F" add -A >/dev/null 2>&1
if kl4_commit "$KL4F" forged; then
  bad "KL4 forged attribution: a content line spelled like a file header cannot move a secret into an excluded path" \
      "it committed. The scanner is taking attribution from line text rather than from diff structure, so any excluded glob is a universal exemption for anyone who can write one line"
else
  ok "KL4 forged attribution: a content line spelled like a file header cannot move a secret into an excluded path"
fi

# MIXED CHANGE: one excluded file and one scanned file in the SAME commit. The
# excluded half is skipped and named, the scanned half still refuses. A filter
# that worked per-commit rather than per-path would pass this by exempting both.
KL4M="$WORK/kl4-mixed"; kl4_fixture "$KL4M" '["vendor/**"]'
printf '%s\n' "$KL4_SECRET" >> "$KL4M/vendor/dep/lib.js"
printf '%s\n' "$KL4_SECRET" >> "$KL4M/src/app.js"
git -C "$KL4M" add -A >/dev/null 2>&1
if kl4_commit "$KL4M" mixed; then
  bad "KL4 mixed change: an excluded file beside a scanned file does not exempt the scanned one" \
      "it committed, so the exclusion is scoped to the COMMIT rather than to the PATH"
else
  ok "KL4 mixed change: an excluded file beside a scanned file does not exempt the scanned one"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-SCAN-EXCLUDED' && printf '%s' "$KL4_ERR" | grep -q 'SLH-SECRET'; then
  ok "KL4 mixed change: the same output carries BOTH the named skip and the refusal it did not cover"
else
  bad "KL4 mixed change: the same output carries BOTH the named skip and the refusal it did not cover" \
      "stderr was: $KL4_ERR"
fi

# --- the negative boundary: the set scopes the CONTENT scans and NOTHING else
#
# The scans are a seatbelt and an exclusion set that can hide anything is not
# one. These assert the negative the spec asks for: a glob covering a role path,
# the specs tree, or the config itself changes no judgment anywhere else.
KL4_ROLE="$WORK/kl4-neg-role"; kl4_fixture "$KL4_ROLE" '["src/**","specs/**",".claude/**"]'
printf 'unspecced feature code\n' > "$KL4_ROLE/src/feature.js"
git -C "$KL4_ROLE" add -A >/dev/null 2>&1
git -C "$KL4_ROLE" -c core.hooksPath=/dev/null commit -qm work >/dev/null 2>&1
git -C "$KL4_ROLE" checkout -q main
if ( cd "$KL4_ROLE" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close" work ) >/dev/null 2>&1; then
  bad "KL4 negative/role-path: a glob covering a role path changes NOTHING about role-path judgment" \
      "the merge landed unspecced feature code on the trunk, so the exclusion set reached SLH-CLOSES-NO-SPEC"
else
  ok "KL4 negative/role-path: a glob covering a role path changes NOTHING about role-path judgment"
fi

# LIFECYCLE DETECTION: a spec Status line moves without specs/STATUS.md staged.
# The glob covers specs/, and the detector must not care.
KL4_LC="$WORK/kl4-neg-lifecycle"; kl4_fixture "$KL4_LC" '["specs/**"]'
printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$KL4_LC/specs/0001-thing.md"
git -C "$KL4_LC" add specs/0001-thing.md >/dev/null 2>&1
if kl4_commit "$KL4_LC" lifecycle; then
  bad "KL4 negative/lifecycle: a glob covering specs/ changes NOTHING about lifecycle detection" \
      "it committed, so the exclusion set reached SLH-STATUS-MISSING"
else
  ok "KL4 negative/lifecycle: a glob covering specs/ changes NOTHING about lifecycle detection"
fi
if printf '%s' "$KL4_ERR" | grep -q 'SLH-STATUS-MISSING'; then
  ok "KL4 negative/lifecycle: and the refusal is still the lifecycle code, not a scan code"
else
  bad "KL4 negative/lifecycle: and the refusal is still the lifecycle code, not a scan code" "stderr was: $KL4_ERR"
fi

# THE CLOSE CHECKS: a row flips to CLOSED with no Closing report, under a glob
# that covers the specs tree AND the config that declares the glob.
KL4_CL="$WORK/kl4-neg-close"; kl4_fixture "$KL4_CL" '["specs/**",".claude/**"]'
printf '# Spec 0001\n\nStatus: CLOSED\n' > "$KL4_CL/specs/0001-thing.md"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | CLOSED | done |\n' > "$KL4_CL/specs/STATUS.md"
printf 'work\n' > "$KL4_CL/src/FEATURE.txt"
git -C "$KL4_CL" add -A >/dev/null 2>&1
git -C "$KL4_CL" -c core.hooksPath=/dev/null commit -qm close >/dev/null 2>&1
git -C "$KL4_CL" checkout -q main
if ( cd "$KL4_CL" && GIT_MERGE_AUTOEDIT=no GIT_EDITOR=true git merge --no-ff -m "close" work ) >/dev/null 2>&1; then
  bad "KL4 negative/close-checks: a glob covering specs/ and the config changes NOTHING about the close checks" \
      "a spec with no Closing report closed on the trunk, so the exclusion set reached the guarantee layer"
else
  ok "KL4 negative/close-checks: a glob covering specs/ and the config changes NOTHING about the close checks"
fi

# THE TRUNK AUDIT: an exclusion set does not quiet the push-time audit.
KL4_TA="$WORK/kl4-neg-audit"; kl4_fixture "$KL4_TA" '["src/**","specs/**"]'
git -C "$KL4_TA" checkout -q main
printf 'straight to the trunk\n' > "$KL4_TA/src/direct.js"
git -C "$KL4_TA" add -A >/dev/null 2>&1
git -C "$KL4_TA" -c core.hooksPath=/dev/null commit -qm direct >/dev/null 2>&1
if kl4_push "$KL4_TA" main; then
  bad "KL4 negative/trunk-audit: a glob covering the role paths changes NOTHING about the trunk audit" \
      "it pushed, so the exclusion set is scoping a check it was never given"
else
  ok "KL4 negative/trunk-audit: a glob covering the role paths changes NOTHING about the trunk audit"
fi

fi; shard_region_end
# <<< SHARD-END kl4-boundary-traps
# --- A9: ONE reader, in the shared lib, called by both layers ---------------
#
# The same shape the lexer lockstep assertions carry. Three copies of a rule is
# how a gate and its backstop went blind together in leg 5; the exclusion reader
# gets the assertion rather than a comment asking people to remember.
KL4_READERS="$(grep -l 'scan_exclusions' "$ROOT/templates/git-hooks/"* 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$KL4_READERS" == "1" ]] && grep -q 'scan_exclusions' "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; then
  ok "KL4 A9: exactly ONE file under templates/git-hooks/ names the scan_exclusions key, and it is the shared lib"
else
  bad "KL4 A9: exactly ONE file under templates/git-hooks/ names the scan_exclusions key, and it is the shared lib" \
      "$KL4_READERS files read it; a second reader of one value is the defect class this hook layer was repaired for"
fi
KL4_JQ_READS="$(grep -c 'scan_exclusions' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | tr -d ' ')"
if [[ "$KL4_JQ_READS" -ge 1 ]] && [[ "$(grep -c 'slh_scan_exclusions_load()' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | tr -d ' ')" == "1" ]]; then
  ok "KL4 A9: the reader has exactly one implementation (slh_scan_exclusions_load)"
else
  bad "KL4 A9: the reader has exactly one implementation (slh_scan_exclusions_load)" \
      "found $(grep -c 'slh_scan_exclusions_load()' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null) definitions"
fi
KL4_CALLERS=0
for h in pre-commit pre-merge-commit pre-push; do
  # pre-push reaches slh_scan_added through slh_scan_walk since 2.6.0 (the walk
  # moved into the library so the forge check runs the same bytes over a pull
  # request's range); the walk itself is asserted below to call the one entry.
  grep -qE 'slh_scan_added|slh_scan_walk' "$ROOT/templates/git-hooks/$h" && KL4_CALLERS=$((KL4_CALLERS + 1))
done
if grep -A40 '^slh_scan_walk()' "$ROOT/templates/git-hooks/setlist-hook-lib.sh" | grep -q 'slh_scan_added "\$proj"'; then
  ok "KL4 A9: the library's range walk reaches the scan through slh_scan_added, so pre-push and the forge check share the one entry point"
else
  bad "KL4 A9: the library's range walk reaches the scan through slh_scan_added, so pre-push and the forge check share the one entry point" \
      "slh_scan_walk does not call slh_scan_added; a second scanner is the fail-open class"
fi
if [[ "$KL4_CALLERS" -eq 3 ]]; then
  ok "KL4 A9: all three content-seeing layers reach the scan through the one shared entry point"
else
  bad "KL4 A9: all three content-seeing layers reach the scan through the one shared entry point" \
      "$KL4_CALLERS of 3 call slh_scan_added; a layer that scans its own way is a layer the exclusion set does not govern"
fi

# --- THE ADVISORY SESSION GATE IS NOT PATH-SCOPED, AND THAT IS MEASURED -----
#
# THIS IS A GAP, PINNED RATHER THAN CLOSED. templates/hooks/commit-gate.sh runs
# its own em-dash and secret scans over the whole staged diff, in a different
# tree, without sourcing this library, and spec 0122 does not name it: its Owner
# docs list the git-hook layer, the delivery scripts, the suite, the edition and
# the public bullet, and its design contract says anything beyond the declared
# shape goes back to the owner rather than being decided at working time.
#
# So the consequence is asserted instead of fixed, because an unasserted gap is
# the one that surprises somebody: inside a Claude Code session, a commit of
# excluded content is still DENIED by the advisory gate, while the same commit
# run outside a session (or after the advisory ALLOW) is accepted by the git
# hooks. The feature works at the layer carrying the guarantee and does not yet
# work at the layer carrying the convenience. Filed for the owner as KL4-A1.
#
# The assertion is written in the CURRENT direction on purpose. If somebody
# later scopes the advisory gate too, this goes red and says so, which is the
# right way for a pinned limitation to be reopened: by a decision, not by drift.
CGX="$WORK/kl4-advisory-gate"; kl4_fixture "$CGX" '["vendor/**"]'
printf '%s\n' "$KL4_SECRET" >> "$CGX/vendor/dep/lib.js"
git -C "$CGX" add -A >/dev/null 2>&1
CGX_OUT="$(printf '%s' "$(bash_payload 'git commit -m x')" | CLAUDE_PROJECT_DIR="$CGX" bash "$HOOKS/commit-gate.sh" 2>/dev/null)"
CGX_V="$(printf '%s' "$CGX_OUT" | jq -r '.setlistAdvisory.verdict // .hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [[ "$CGX_V" == "deny" ]]; then
  ok "KL4 gap KL4-A1 (PINNED, not closed): the ADVISORY commit gate is not path-scoped, so it still denies excluded content inside a session"
else
  bad "KL4 gap KL4-A1 (PINNED, not closed): the ADVISORY commit gate is not path-scoped, so it still denies excluded content inside a session" \
      "the advisory gate stopped denying. If that was deliberate, this is the assertion to update, in the commit that made the decision and with the ledger row and the public bullet moved with it; if it was not, the two layers have silently drifted apart on what the exclusion set governs"
fi
# The twin that keeps the pin honest: the GUARANTEE layer, same content, same
# config, accepts it. Without this the assertion above is satisfied by a repo
# where nothing works at all.
if git -C "$CGX" -c core.hooksPath=.githooks commit -qm vendored >/dev/null 2>&1; then
  ok "KL4 gap KL4-A1 twin: the guarantee layer accepts the same content the advisory gate denies, which is what makes the gap a gap rather than a feature that does not work"
else
  bad "KL4 gap KL4-A1 twin: the guarantee layer accepts the same content the advisory gate denies, which is what makes the gap a gap rather than a feature that does not work" \
      "the git hooks refused too, so the feature is not working at the layer it was built for"
fi

# --- delivery: the config surface is stamped and survives a refresh ---------
KL4_TMPL="$ROOT/templates/claude/sdd.json.tmpl"
if jq -e 'has("scan_exclusions") and (.scan_exclusions | type) == "array" and (.scan_exclusions | length) == 0' "$KL4_TMPL" >/dev/null 2>&1; then
  ok "KL4 delivery: the stamped sdd.json template DECLARES scan_exclusions, empty, so the surface is discoverable without changing a verdict"
else
  bad "KL4 delivery: the stamped sdd.json template DECLARES scan_exclusions, empty, so the surface is discoverable without changing a verdict" \
      "a config surface nobody can find is a feature nobody has; an empty array is byte-identical in behaviour to absence and names the key"
fi

# PRESERVED ACROSS AN UPGRADE. A declared set that a refresh silently dropped
# would turn a working exclusion into a wall of refusals on the next commit, at
# the moment the operator is least expecting the hooks to have changed their
# mind. refresh-instance.sh rewrites .plugin.version through jq and nothing
# else, so preservation is a property of how it writes rather than a special
# case for this key; the assertion pins that property where this key can see it.
KL4_INST="$WORK/kl4-refresh-preserve"
if instance_fixture "$KL4_INST" 1.0.0 >/dev/null 2>&1; then
  jq '. + {scan_exclusions: ["vendor/**", "test/fixtures/**"]}' "$KL4_INST/.claude/sdd.json" > "$KL4_INST/.claude/sdd.json.new" \
    && mv "$KL4_INST/.claude/sdd.json.new" "$KL4_INST/.claude/sdd.json"
  bash "$SCRIPTS/refresh-instance.sh" --apply "$KL4_INST" >/dev/null 2>&1
  KL4_KEPT="$(jq -c '.scan_exclusions' "$KL4_INST/.claude/sdd.json" 2>/dev/null)"
  if [[ "$KL4_KEPT" == '["vendor/**","test/fixtures/**"]' ]]; then
    ok "KL4 delivery: a refresh PRESERVES a declared exclusion set, value for value"
  else
    bad "KL4 delivery: a refresh PRESERVES a declared exclusion set, value for value" \
        "after the refresh the set reads $KL4_KEPT; an upgrade that drops it turns a working exclusion into a wall of refusals nobody asked for"
  fi
  if [[ "$(jq -r '.plugin.version' "$KL4_INST/.claude/sdd.json" 2>/dev/null)" == "$PLUGIN_VERSION" ]]; then
    ok "KL4 delivery: and the refresh it survived was a REAL one (the version moved)"
  else
    bad "KL4 delivery: and the refresh it survived was a REAL one (the version moved)" \
        "the version did not move, so the preservation assertion above survived a refresh that did not happen"
  fi
else
  bad "KL4 delivery: the refresh fixture builds" "instance_fixture failed, so the preservation assertions test nothing"
fi

# ABSENCE STAYS ABSENT. The other half of opt-in: a refresh must not invent the
# key, because a key that appears on upgrade is a config surface the operator
# never chose and a diff they have to explain.
KL4_INST2="$WORK/kl4-refresh-absent"
if instance_fixture "$KL4_INST2" 1.0.0 >/dev/null 2>&1; then
  bash "$SCRIPTS/refresh-instance.sh" --apply "$KL4_INST2" >/dev/null 2>&1
  if jq -e 'has("scan_exclusions") | not' "$KL4_INST2/.claude/sdd.json" >/dev/null 2>&1; then
    ok "KL4 delivery: a refresh does NOT invent the key in an instance that never declared one"
  else
    bad "KL4 delivery: a refresh does NOT invent the key in an instance that never declared one" \
        "the upgrade added a config surface the operator did not choose"
  fi
else
  bad "KL4 delivery: the absent-key refresh fixture builds" "instance_fixture failed"
fi

