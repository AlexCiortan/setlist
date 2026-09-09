#!/usr/bin/env bash
# test/suite/09-attestation-kl3.sh: shard 9 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# THE HEADLESS BUILD INTEGRITY CHAIN (KL3), spec 0124, from the ratified design
# `design-attestation-kl3-2026-08-28.md`.
#
# WHAT THESE ASSERTIONS ARE EVIDENCE OF, stated first because A8 requires it and
# because this is the one feature where the distinction decides the design: a
# green here is evidence that a SIGNATURE VERIFIED, never that a PERSON
# APPROVED. Nothing a suite can write establishes the second. That is why the
# mechanism prints its declared custody on every verification INCLUDING the
# passes, and why one of the assertions below is about the PASSING message
# rather than about a refusal. It is the only one that covers the failure mode
# the design exists inside, and it would be the easiest to leave out.
#
# The tokens the verifier may print are a closed set, and the caller refuses
# anything that is not exactly VERIFIED. The empty-token case is asserted with a
# deliberately broken verifier rather than argued, because "every failure of the
# verifier itself lands in the allow branch" is F3-2026's class and asserting it
# by reading the code is how it survives.
# =============================================================================

# ssh-keygen is PROBED, not located. `-Y sign` arrived in OpenSSH 8.2 and a
# host can carry an older binary; a `command -v` that passed for a tool whose
# subcommand does not exist would leave every assertion below reporting on a
# mechanism it never reached.
ATT_HAVE_SSH=0
if command -v ssh-keygen >/dev/null 2>&1 \
   && ssh-keygen -q -t ed25519 -N "" -C probe@example.test -f "$WORK/att-probe" >/dev/null 2>&1 \
   && printf 'probe\n' > "$WORK/att-probe.txt" \
   && ssh-keygen -Y sign -f "$WORK/att-probe" -n setlist-attestation "$WORK/att-probe.txt" >/dev/null 2>&1; then
  ATT_HAVE_SSH=1
fi

# att_fixture <dir> <custody|off> [verify_with]
# A stamped instance carrying an ACTIVE spec and staged role-path work, which is
# exactly the shape a headless build produces: the commit is ordinary and it is
# what pre-commit sees first.
att_fixture() { # att_fixture <dir> <custody|off> [verify_with]
  local d="$1" custody="$2" vw="${3:-.claude/approvers.pub}"
  rm -rf "$d"; mkdir -p "$d/src" "$d/specs/attest" "$d/.claude" "$d/.githooks"
  git_init "$d"
  if [[ "$custody" == "off" ]]; then
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
  else
    printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"attestation":{"required":true,"custody":"%s","verify_with":"%s"}}\n' "$custody" "$vw" > "$d/.claude/sdd.json"
  fi
  printf '# Spec 0001 - thing\n\nStatus: ACTIVE\n\n## Goal\nBuild the thing.\n\n## Closing report\n- pending\n' > "$d/specs/0001-thing.md"
  printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
  cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/pre-merge-commit" \
     "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
  chmod +x "$d/.githooks/pre-commit" "$d/.githooks/pre-merge-commit"
  printf 'seed\n' > "$d/seed.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
  git -C "$d" config core.hooksPath .githooks
  # The work: role-path content, which is what makes the predicate apply at all.
  printf 'work\n' > "$d/src/FEATURE.txt"
  git -C "$d" add -A >/dev/null 2>&1
}

# att_sign <dir> [spec-field] [num-field] [hash-override] [verdict]
# Writes the attestation document and signs it with the fixture's own key. Each
# override exists so a NEGATIVE case differs from the positive one in exactly
# one field, which is what makes a red mean what it says.
att_sign() { # att_sign <dir> [spec] [num] [hash] [verdict]
  local d="$1" spec="${2:-specs/0001-thing.md}" num="${3:-0001}" h="${4:-}" v="${5:-APPROVED}"
  [[ -n "$h" ]] || h="$(bash "$ROOT/scripts/spec-hash.sh" "$d/specs/0001-thing.md")"
  mkdir -p "$d/specs/attest"
  printf '{\n  "setlist_attestation": 1,\n  "spec": "%s",\n  "spec_number": "%s",\n  "spec_hash": "%s",\n  "verdict": "%s",\n  "approver": "approver@example.test",\n  "custody": "signer",\n  "tool": "setlist/checkpoint",\n  "tool_version": "2.3.0",\n  "at": "2026-08-29T00:00:00Z",\n  "notes": ""\n}\n' \
    "$spec" "$num" "$h" "$v" > "$d/specs/attest/${num}.json"
  if [[ ! -f "$WORK/att-key" ]]; then
    ssh-keygen -q -t ed25519 -N "" -C approver@example.test -f "$WORK/att-key" >/dev/null 2>&1
  fi
  printf 'approver@example.test %s\n' "$(cat "$WORK/att-key.pub")" > "$d/.claude/approvers.pub"
  ssh-keygen -Y sign -f "$WORK/att-key" -n setlist-attestation \
    "$d/specs/attest/${num}.json" >/dev/null 2>&1
  mv "$d/specs/attest/${num}.json.sig" "$d/specs/attest/${num}.sig" 2>/dev/null || true
}

att_commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm "attest case" >"$WORK/att-out" 2>&1; }
att_out() { cat "$WORK/att-out" 2>/dev/null; }

if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then

# --- THE OFF DIRECTION, and it goes first ---------------------------------
# UNDECLARED MEANS OFF AND OFF MEANS BYTE-IDENTICAL TO AN INSTANCE THAT NEVER
# HEARD OF THIS. KL4's precedent and its proof method. If this fails, every
# refusal below is a feature that breaks every existing repository.
ATT="$WORK/att-off"; att_fixture "$ATT" off
if att_commit "$ATT"; then
  if att_out | grep -q 'SLH-ATTEST'; then
    bad "attest off: an instance declaring no attestation commits with NO attestation output at all" \
        "it printed an attestation message: off must be silent, not merely permissive"
  else
    ok "attest off: an instance declaring no attestation commits with NO attestation output at all"
  fi
else
  bad "attest off: an instance declaring no attestation commits with NO attestation output at all" \
      "the commit was refused: $(att_out | tr '\n' ' ')"
fi

# --- THE PASS, AND WHAT IT SAYS WHILE PASSING -----------------------------
# THE ASSERTION THIS FEATURE WOULD MOST EASILY SHIP WITHOUT. A pass that does
# not name its custody lets an instance install this, watch its checks go
# green, and believe it has an integrity chain whose strength nobody ever
# established. The failure mode is invisible to every test that asks whether
# signatures verify, and visible in every message.
ATT="$WORK/att-pass"; att_fixture "$ATT" signer; att_sign "$ATT"
if att_commit "$ATT"; then
  if att_out | grep -q 'verified under "signer" custody'; then
    ok "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing"
  else
    bad "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing" \
        "it allowed silently, so a passing chain says nothing about how strong it is: $(att_out | tr '\n' ' ')"
  fi
else
  bad "attest pass: a valid attestation ALLOWS and NAMES the declared custody while passing" \
      "a correctly signed approval was refused, which is the false-denial direction: $(att_out | tr '\n' ' ')"
fi

# The same, under the custody that is WEAK BY CONSTRUCTION. This one has to say
# so out loud: a key the build can reach establishes that the run had the key,
# not that a person approved. Asserted on a PASS, which is the only place it
# can be said.
ATT="$WORK/att-pass-ci"; att_fixture "$ATT" ci-secret; att_sign "$ATT"
if att_commit "$ATT" && att_out | grep -q 'A KEY THE BUILD CAN REACH'; then
  ok "attest pass ci-secret: a PASSING verification under a build-reachable key says what it does not prove"
else
  bad "attest pass ci-secret: a PASSING verification under a build-reachable key says what it does not prove" \
      "the green did not state the strength of its own evidence: $(att_out | tr '\n' ' ')"
fi

# --- THE SIX REFUSALS, EACH ASSERTED ON ITS CODE --------------------------
# >>> SHARD-BEGIN attest-six-refusals cost=6
if shard_region attest-six-refusals; then
# On the CODE and not on the verdict, for the reason the toolchain probes give:
# these fixtures could be refused for a dozen unrelated reasons and a bare "did
# it refuse" would pass with or without the mechanism.

ATT="$WORK/att-missing"; att_fixture "$ATT" signer
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MISSING'; then
  ok "attest MISSING: role-path work under an ACTIVE spec with no attestation is refused"
else
  bad "attest MISSING: role-path work under an ACTIVE spec with no attestation is refused" "$(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-malformed"; att_fixture "$ATT" signer; att_sign "$ATT"
: > "$ATT/specs/attest/0001.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MALFORMED'; then
  ok "attest MALFORMED: an EMPTY attestation document is refused and is never a pass"
else
  bad "attest MALFORMED: an EMPTY attestation document is refused and is never a pass" "$(att_out | tr '\n' ' ')"
fi

# The unparseable half of the same code, asserted apart from the empty half:
# an empty file and a file of garbage reach the reader by different routes.
ATT="$WORK/att-garbage"; att_fixture "$ATT" signer; att_sign "$ATT"
printf 'this is not json at all\n' > "$ATT/specs/attest/0001.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-MALFORMED'; then
  ok "attest MALFORMED b: an UNPARSEABLE attestation document is refused"
else
  bad "attest MALFORMED b: an UNPARSEABLE attestation document is refused" "$(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-unsigned"; att_fixture "$ATT" signer; att_sign "$ATT"
rm -f "$ATT/specs/attest/0001.sig"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNSIGNED'; then
  ok "attest UNSIGNED a: an attestation with no signature is treated exactly as an absent one"
else
  bad "attest UNSIGNED a: an attestation with no signature is treated exactly as an absent one" "$(att_out | tr '\n' ' ')"
fi

# The signature that EXISTS and does not verify: a different route to the same
# refusal, and the one an attacker takes.
ATT="$WORK/att-badsig"; att_fixture "$ATT" signer; att_sign "$ATT"
ssh-keygen -q -t ed25519 -N "" -C other@example.test -f "$WORK/att-other" >/dev/null 2>&1
ssh-keygen -Y sign -f "$WORK/att-other" -n setlist-attestation "$ATT/specs/attest/0001.json" >/dev/null 2>&1
mv "$ATT/specs/attest/0001.json.sig" "$ATT/specs/attest/0001.sig" 2>/dev/null || true
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNSIGNED'; then
  ok "attest UNSIGNED b: a signature by a key that is NOT enrolled does not verify and is refused"
else
  bad "attest UNSIGNED b: a signature by a key that is NOT enrolled does not verify and is refused" "$(att_out | tr '\n' ' ')"
fi

# CO1'S CLASS ONE LEVEL DOWN. Perfectly valid, perfectly signed, and about a
# DIFFERENT spec. A mechanism that checks a claim without checking its SUBJECT
# is checking nothing, and this row exists because the publish gate learned it
# the expensive way.
ATT="$WORK/att-subject"; att_fixture "$ATT" signer
att_sign "$ATT" "specs/0002-other.md" "0001"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-SUBJECT'; then
  ok "attest SUBJECT: a valid, correctly SIGNED attestation naming another spec is refused"
else
  bad "attest SUBJECT: a valid, correctly SIGNED attestation naming another spec is refused" "$(att_out | tr '\n' ' ')"
fi

# THE THREAT ITSELF: a spec edited after approval. The attestation covers the
# approved hash and the current bytes hash to something else.
ATT="$WORK/att-stale"; att_fixture "$ATT" signer; att_sign "$ATT"
# THE EDIT GOES ABOVE THE CLOSING REPORT HEADING, and the first draft of this
# fixture did not: it appended to the END of the file, which is BELOW that
# heading and therefore excluded from the hash by the BL-005 recipe. So this
# case and its control were byte-for-byte the same experiment, and this one
# reported the mechanism broken while the control reported it working. Caught
# by running the pair rather than by reading them, which is the whole argument
# for the control existing.
sed -e 's/^Build the thing\./Build the OTHER thing, edited after approval./' \
    "$ATT/specs/0001-thing.md" > "$ATT/t" && mv "$ATT/t" "$ATT/specs/0001-thing.md"
if ! grep -q 'edited after approval' "$ATT/specs/0001-thing.md"; then
  bad "attest STALE fixture: the drift was applied ABOVE the Closing report heading" \
      "the fixture did not drift, so the assertion below would report on nothing"
fi
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-STALE'; then
  ok "attest STALE: a spec edited AFTER approval refuses the build's commit (the threat this exists for)"
else
  bad "attest STALE: a spec edited AFTER approval refuses the build's commit (the threat this exists for)" "$(att_out | tr '\n' ' ')"
fi

# The control for STALE, and it is not optional: without it the assertion above
# is satisfied by a mechanism that refuses every commit. An edit BELOW the
# Closing report heading is excluded from the hash by the BL-005 recipe, so an
# ordinary build append must NOT read as drift.
ATT="$WORK/att-stale-control"; att_fixture "$ATT" signer; att_sign "$ATT"
printf -- '- an ordinary build append\n' >> "$ATT/specs/0001-thing.md"
if att_commit "$ATT"; then
  ok "attest STALE control: an append BELOW the Closing report heading is not drift and still commits"
else
  bad "attest STALE control: an append BELOW the Closing report heading is not drift and still commits" \
      "the mechanism cries wolf on every honest build, which is how a warning gets switched off in a day: $(att_out | tr '\n' ' ')"
fi

ATT="$WORK/att-unverifiable"; att_fixture "$ATT" signer; att_sign "$ATT"
rm -f "$ATT/.claude/approvers.pub"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest UNVERIFIABLE a: an unreadable allowed-signers file refuses, and says the check could not RUN"
else
  bad "attest UNVERIFIABLE a: an unreadable allowed-signers file refuses, and says the check could not RUN" "$(att_out | tr '\n' ' ')"
fi

# A HALF-CONFIGURED CHAIN IS A REFUSAL AND NOT A DEFAULT. Reachable by
# omission is the one way this must not be reachable, because it is the worst
# of the four custody states and the easiest to arrive at by accident.
ATT="$WORK/att-halfconf"; att_fixture "$ATT" signer
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"},"attestation":{"required":true}}\n' > "$ATT/.claude/sdd.json"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest UNVERIFIABLE b: required:true with no custody declared is a REFUSAL, never a default"
else
  bad "attest UNVERIFIABLE b: required:true with no custody declared is a REFUSAL, never a default" "$(att_out | tr '\n' ' ')"
fi

# CUSTODY C WITHOUT THE CHECK IN THE TREE REFUSES (2.6.0, ratification decision
# 2's condition). This fixture carries no .claude/hooks/forge-check.sh, so the
# deferral has no layer to name and the refusal is the one that shipped while
# custody C was designed and not built. The other direction (the check in the
# tree, the deferral allow with its sentence) is pinned in the forge-check
# region below.
ATT="$WORK/att-forge"; att_fixture "$ATT" forge; att_sign "$ATT"
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE' && att_out | grep -q 'no stamped forge check'; then
  ok "attest forge: declared custody C with NO forge check in the tree refuses, naming the missing layer"
else
  bad "attest forge: declared custody C with NO forge check in the tree refuses, naming the missing layer" "$(att_out | tr '\n' ' ')"
fi

fi; shard_region_end
# <<< SHARD-END attest-six-refusals
# --- THE CALLING CONVENTION, ASSERTED STRUCTURALLY ------------------------
# F3-2026's class, closed by construction rather than by vigilance. A verifier
# that prints NOTHING must refuse, and the only honest way to assert that is to
# break the verifier and watch what the caller does.
ATT="$WORK/att-mute"; att_fixture "$ATT" signer; att_sign "$ATT"
# The mute is applied by APPENDING an override rather than by editing the
# definition, which keeps the mutation one line and keeps it obviously the
# thing under test. A redefinition later in the file wins in shell.
printf '\nslh_attest_verify() { return 0; }\n' >> "$ATT/.githooks/setlist-hook-lib.sh"
if ! grep -q 'slh_attest_verify() { return 0; }' "$ATT/.githooks/setlist-hook-lib.sh"; then
  bad "attest convention fixture: the muted verifier was installed" "the mutation did not apply, so the assertion below would test nothing"
fi
if ! att_commit "$ATT" && att_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest convention: a verifier that prints NOTHING produces a REFUSAL, not an allow (the F3-2026 class)"
else
  bad "attest convention: a verifier that prints NOTHING produces a REFUSAL, not an allow (the F3-2026 class)" \
      "an empty verifier result reached the allow branch, which is the empty-result-as-verdict class this convention exists to remove: $(att_out | tr '\n' ' ')"
fi

else
  # NOT SILENTLY SKIPPED. A dependency that cannot run is reported, never
  # quietly passed over, which is this project's own rule about its own checks.
  bad "attest: ssh-keygen is required to exercise the integrity chain and is not usable here" \
      "the attestation assertions did not run, so this tree carries NO evidence about the KL3 mechanism"
fi

# A9: ONE VERIFIER, and the count is pinned rather than reviewed. The advisory
# layer gets one honest sentence and no reader of its own, which is the
# 2026-08-28 ruling; a second definition arriving anywhere is what this catches.
ATT_DEFS="$(grep -rl 'slh_attest_verify() {' "$ROOT/templates" "$ROOT/scripts" 2>/dev/null | grep -c . || true)"
if [[ "$ATT_DEFS" == "1" ]]; then
  ok "attest A9: exactly ONE file defines slh_attest_verify, and it is the git-hook library"
else
  bad "attest A9: exactly ONE file defines slh_attest_verify, and it is the git-hook library" \
      "found $ATT_DEFS definitions; one rule with two readers is how the two drift apart"
fi
if grep -q 'slh_attest_verify() {' "$ROOT/templates/git-hooks/setlist-hook-lib.sh"; then
  ok "attest A9b: the one definition lives in templates/git-hooks/setlist-hook-lib.sh"
else
  bad "attest A9b: the one definition lives in templates/git-hooks/setlist-hook-lib.sh" "it moved out of the only layer that can refuse"
fi

# THE THREE-WAY HASH LOCKSTEP. The recipe now has THREE implementations in
# deliberate behavioural lockstep, and the count is pinned so a fourth cannot
# arrive unasserted. Both cheaper routes are foreclosed: a shared recipe file
# across the two hook trees is the cross-tree dependency the 2026-08-28 ruling
# refused, and shelling out to scripts/spec-hash.sh breaks the stamped-hook
# independence the inline copy exists to preserve. This is the price, it was
# named in the design before the work started, and it is not optional.
ATT_LOCK_OK=1
ATT_LOCK_N=0
for shl_case in "plain body" "body with - Spec-hash: decoy inside it" "body
spanning
several lines"; do
  SHL="$WORK/attest-lock"; sh_fixture "$SHL" ACTIVE no "$shl_case"
  A_SCRIPT="$(bash "$ROOT/scripts/spec-hash.sh" "$SHL/specs/0001-thing.md")"
  A_INLINE="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' "$SHL/specs/0001-thing.md" \
    | grep -v '^[-*+[:space:]]*Spec-hash:' | sha256sum | cut -d' ' -f1)"
  A_HOOK="$(bash -c '. "$1" >/dev/null 2>&1; slh_attest_spec_hash "$2"' _ \
    "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SHL/specs/0001-thing.md" 2>/dev/null)"
  ATT_LOCK_N=$((ATT_LOCK_N + 1))
  [[ "$A_SCRIPT" == "$A_INLINE" && "$A_SCRIPT" == "$A_HOOK" && -n "$A_SCRIPT" ]] || ATT_LOCK_OK=0
done
# A8: the size of what is compared is asserted before the comparison is
# believed. A lockstep over zero fixtures agrees with itself perfectly.
if [[ "$ATT_LOCK_N" -eq 3 && "$ATT_LOCK_OK" -eq 1 ]]; then
  ok "spec-hash lockstep (THREE implementations): script, regrounding hook and git-hook verifier agree on every corpus shape"
else
  bad "spec-hash lockstep (THREE implementations): script, regrounding hook and git-hook verifier agree on every corpus shape" \
      "$ATT_LOCK_N of 3 shapes compared, agreement=$ATT_LOCK_OK; three copies of one recipe that disagree is how a checker and its writer drift apart"
fi

# The count itself, pinned. Three is a decision with a price attached; a fourth
# copy arriving without this assertion being changed is the thing to catch.
# THE MARKER IS THE FIELD EXCLUSION, not the awk range, and that is a
# correction this assertion made to itself on its first run. The range is
# spelled on one line in the two hooks and across three lines in
# scripts/spec-hash.sh, so a pattern matching the compact form found 2 of 3 and
# would have reported a missing implementation as a missing copy. The `grep -v`
# that removes the Spec-hash field line is byte-identical in all three, which
# is the right marker because it is the exclusion the recipe cannot work
# without.
ATT_HASH_RE='^[-*+[:space:]]*Spec-hash:'
ATT_HASH_COPIES="$(grep -lF "$ATT_HASH_RE" \
  "$ROOT/scripts/spec-hash.sh" "$ROOT/templates/hooks/regrounding-hook.sh" \
  "$ROOT/templates/git-hooks/setlist-hook-lib.sh" 2>/dev/null | grep -c . || true)"
ATT_HASH_ALL="$(grep -rlF "$ATT_HASH_RE" "$ROOT/scripts" "$ROOT/templates" 2>/dev/null | grep -c . || true)"
if [[ "$ATT_HASH_COPIES" == "3" && "$ATT_HASH_ALL" == "3" ]]; then
  ok "spec-hash lockstep count: the recipe has exactly THREE implementations, all three under lockstep"
else
  bad "spec-hash lockstep count: the recipe has exactly THREE implementations, all three under lockstep" \
      "expected 3 named and 3 total, found $ATT_HASH_COPIES named and $ATT_HASH_ALL total; a fourth copy is a fourth thing that can drift"
fi

# --- THE PUSH LAYER'S ARM ---------------------------------------------------
# >>> SHARD-BEGIN attest-push-arm cost=13
if shard_region attest-push-arm; then
# The guarantee, per the enforcement boundary: a commit that never met
# pre-commit (--no-verify, an unset core.hooksPath, the per-clone gap) is
# caught before the work is SHARED. Every fixture below builds its history
# with the hooks bypassed, which is the only honest way to reach this layer:
# a fixture whose commits went through pre-commit is testing pre-commit twice.
att_push_fixture() { # att_push_fixture <dir> <custody|off>
  local d="$1" custody="$2"
  att_fixture "$d" "$custody"
  # THE ROLE-PATH WORK IS COMMITTED ON THE SPEC BRANCH AND NEVER ON main, and
  # the ordering here is a correction rather than a preference. The first cut
  # committed the staged work before branching, so main carried feature code
  # that arrived through no closed spec, and the TRUNK AUDIT refused every
  # push in this block: the control, the docs-only case and the off case all
  # went red against bytes that have no approval arm at all. A refusal for the
  # wrong reason is indistinguishable from the refusal under test, and it was
  # the CONTROL going red on the pre-feature tree that said so.
  # `git checkout -b` carries the index across, so the work follows the branch.
  mkdir -p "$d/.claude/hooks"
  cp "$ROOT/templates/git-hooks/pre-push" "$d/.githooks/pre-push"
  cp "$ROOT/scripts/trunk-audit.sh" "$d/.claude/hooks/trunk-audit.sh"
  chmod +x "$d/.githooks/pre-push"
  git init -q --bare "$d-rem.git"
  git -C "$d" remote add origin "$d-rem.git"
  # The remote is SEEDED so it is not empty: on an empty remote every pushed
  # ref is a trunk candidate and is audited, so these cases would be refused
  # for a reason that has nothing to do with approval. The fixture models the
  # real scenario rather than the convenient one.
  git -C "$d" -c core.hooksPath=/dev/null push -q origin main:refs/heads/main >/dev/null 2>&1
  git -C "$d-rem.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  git -C "$d" fetch -q origin >/dev/null 2>&1
  git -C "$d" checkout -q -b spec/0001-thing
  git -C "$d" -c core.hooksPath=/dev/null commit -qm "work, hooks bypassed" >/dev/null 2>&1
  # THE PREMISE THIS BLOCK RESTS ON, asserted per fixture rather than once:
  # main must carry NO role-path content, or the trunk audit refuses every
  # push here for a reason that is not approval.
  if git -C "$d" ls-tree -r --name-only main 2>/dev/null | grep -q "^src/"; then
    bad "attest push fixture: main carries no role-path content ($d)" \
        "the trunk audit will refuse every push in this block for a reason that is not approval"
  fi
}
att_push() { git -C "$1" push -q origin spec/0001-thing >"$WORK/att-push-out" 2>&1; }
att_push_out() { cat "$WORK/att-push-out" 2>/dev/null; }
# The work commit is made on the spec branch with hooks bypassed, so the range
# this push publishes carries role-path content that pre-commit never saw.
att_push_work() { # att_push_work <dir>
  printf 'more work\n' > "$1/src/MORE.txt"
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c core.hooksPath=/dev/null commit -qm "unapproved build, hooks bypassed" >/dev/null 2>&1
}

if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then

# THE FIXTURE'S OWN PREMISE, ASSERTED BEFORE ANY CASE RUNS. If the work commit
# did not land, or landed with role-path content the range does not carry,
# every refusal below passes while testing nothing. The opener of this cycle
# shipped exactly that defect twice in one sitting, so the premise is checked
# rather than assumed.
ATTP="$WORK/attp-premise"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
att_push_work "$ATTP"
ATTP_RANGE="$(git -C "$ATTP" rev-list origin/main..spec/0001-thing 2>/dev/null | grep -c . || true)"
ATTP_ROLE="$(git -C "$ATTP" show --name-only --format= spec/0001-thing 2>/dev/null | grep -c '^src/' || true)"
if [[ "$ATTP_RANGE" -ge 1 && "$ATTP_ROLE" -ge 1 ]]; then
  ok "attest push fixture: the range carries $ATTP_RANGE commit(s) and role-path content, so the arm has something to judge"
else
  bad "attest push fixture: the range carries $ATTP_RANGE commit(s) and role-path content, so the arm has something to judge" \
      "range=$ATTP_RANGE role-files=$ATTP_ROLE; every push case below would pass while testing nothing"
fi

# THE CONTROL FIRST, because every refusal below is worthless without it: an
# approved branch whose spec has not drifted must still PUSH.
if att_push "$ATTP"; then
  ok "attest push control: an APPROVED branch whose spec has not drifted still pushes"
else
  bad "attest push control: an APPROVED branch whose spec has not drifted still pushes" \
      "the arm refuses compliant work, which is the false-denial direction and makes every case below meaningless: $(att_push_out | tr '\n' ' ')"
fi

# THE CASE THE LAYER EXISTS FOR: a build that never met pre-commit. Not a
# contrived route, and named in Known limitations as a documented hole at
# commit time precisely because THIS layer is what covers it.
ATTP="$WORK/attp-missing"; att_push_fixture "$ATTP" signer
att_push_work "$ATTP"
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-MISSING'; then
  ok "attest push MISSING: an unapproved build that bypassed pre-commit is refused BEFORE it is shared"
else
  bad "attest push MISSING: an unapproved build that bypassed pre-commit is refused BEFORE it is shared" "$(att_push_out | tr '\n' ' ')"
fi

# THE READING THAT DECIDES THE WHOLE ARM: the spec is drifted ONLY IN THE
# PUSHED TREE and is clean on disk. A verifier that hashed the working copy
# would pass this, and it would pass it for exactly the push it exists to stop.
ATTP="$WORK/attp-tree"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
sed -e 's/^Build the thing\./Build the OTHER thing, drifted in the pushed commit only./' \
    "$ATTP/specs/0001-thing.md" > "$ATTP/t" && mv "$ATTP/t" "$ATTP/specs/0001-thing.md"
printf 'more work\n' > "$ATTP/src/MORE.txt"
git -C "$ATTP" add -A >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "drift, hooks bypassed" >/dev/null 2>&1
# Now put the WORKING COPY back to the approved bytes. The tree being pushed
# still carries the drift; the filesystem does not.
git -C "$ATTP" show "HEAD~1:specs/0001-thing.md" > "$ATTP/specs/0001-thing.md"
ATTP_DISK="$(bash "$ROOT/scripts/spec-hash.sh" "$ATTP/specs/0001-thing.md")"
ATTP_DOC="$(jq -r .spec_hash "$ATTP/specs/attest/0001.json" 2>/dev/null)"
if [[ "$ATTP_DISK" == "$ATTP_DOC" ]]; then
  ok "attest push tree fixture: the working copy MATCHES the approval, so only the pushed tree is drifted"
else
  bad "attest push tree fixture: the working copy MATCHES the approval, so only the pushed tree is drifted" \
      "disk=$ATTP_DISK doc=$ATTP_DOC; the case below would not distinguish a tree reader from a disk reader"
fi
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-STALE'; then
  ok "attest push STALE: a spec drifted ONLY in the pushed tree is refused, so the arm reads the tree and not the disk"
else
  bad "attest push STALE: a spec drifted ONLY in the pushed tree is refused, so the arm reads the tree and not the disk" \
      "a clean working copy satisfied a check about bytes nobody is publishing: $(att_push_out | tr '\n' ' ')"
fi

# A DOCS-ONLY PUSH CARRIES NO BUILD TO APPROVE. Without this the mechanism is a
# toll on every commit rather than a gate on building, which is the direction
# that gets a gate switched off.
ATTP="$WORK/attp-docs"; att_push_fixture "$ATTP" signer
# THE BRANCH IS RESET TO THE TRUNK FIRST, because att_push_fixture lands the
# role-path work commit on it and a "docs-only" branch that carries a build is
# not the case under test. Found by running it: the assertion went red against
# the finished arm, and the arm was right. The range has to be docs-only for
# the words to mean anything.
git -C "$ATTP" reset -q --hard origin/main
printf 'notes\n' > "$ATTP/NOTES.md"
git -C "$ATTP" add -A >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "docs only" >/dev/null 2>&1
ATTP_DOCS_ROLE="$(git -C "$ATTP" diff --name-only origin/main..HEAD 2>/dev/null | grep -c '^src/' || true)"
if [[ "$ATTP_DOCS_ROLE" != "0" ]]; then
  bad "attest push docs fixture: the range carries NO role-path content" \
      "found $ATTP_DOCS_ROLE role-path file(s), so this is not the docs-only case it claims to be"
fi
if att_push "$ATTP"; then
  ok "attest push scope: a push carrying NO role-path content needs no approval and is allowed"
else
  bad "attest push scope: a push carrying NO role-path content needs no approval and is allowed" \
      "a docs-only push was refused, which makes this a toll on every commit rather than a gate on building: $(att_push_out | tr '\n' ' ')"
fi

# OFF IS OFF AT THIS LAYER TOO, and it is asserted here rather than inferred
# from the commit layer: two layers, two readers of the same declaration.
ATTP="$WORK/attp-push-off"; att_push_fixture "$ATTP" off
att_push_work "$ATTP"
if att_push "$ATTP" && ! att_push_out | grep -q 'SLH-ATTEST'; then
  ok "attest push off: an instance declaring no attestation pushes with NO attestation output at all"
else
  bad "attest push off: an instance declaring no attestation pushes with NO attestation output at all" "$(att_push_out | tr '\n' ' ')"
fi

# THE ALLOWED-SIGNERS FILE IS READ FROM THE PUSHED TREE TOO. Enrolment is a
# commit, so judging a push against whatever this clone has checked out would
# let a key removed in the pushed range still verify, or refuse a key the push
# itself enrols. Asserted in the direction that publishes.
ATTP="$WORK/attp-enrol"; att_push_fixture "$ATTP" signer; att_sign "$ATTP"
git -C "$ATTP" add -A >/dev/null 2>&1; git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm attest >/dev/null 2>&1
git -C "$ATTP" rm -q --cached .claude/approvers.pub >/dev/null 2>&1
printf 'more work\n' > "$ATTP/src/MORE.txt"
git -C "$ATTP" add src >/dev/null 2>&1
git -C "$ATTP" -c core.hooksPath=/dev/null commit -qm "drop the enrolled key from the tree" >/dev/null 2>&1
if ! att_push "$ATTP" && att_push_out | grep -q 'SLH-ATTEST-UNVERIFIABLE'; then
  ok "attest push enrolment: the allowed-signers file is read from the PUSHED tree, so a push that drops it cannot verify"
else
  bad "attest push enrolment: the allowed-signers file is read from the PUSHED tree, so a push that drops it cannot verify" \
      "the check used this clone's checked-out keys to judge a tree that does not contain them: $(att_push_out | tr '\n' ' ')"
fi

fi

# THE HELPER AND THE VERIFIER, ROUND TRIP. The writer and the checker are
# different programs in different trees, and "they agree" is the claim that
# matters and the one nothing else here makes: every other assertion builds its
# attestation with the test's own signing code, which proves the VERIFIER works
# and says nothing about what /setlist:checkpoint actually writes. This drives
# scripts/spec-attest.sh and then asks the git-hook library's verifier.
if [[ "$ATT_HAVE_SSH" -eq 1 ]]; then
  ATTH="$WORK/attest-helper"; att_fixture "$ATTH" signer
  ssh-keygen -q -t ed25519 -N "" -C helper@example.test -f "$WORK/att-helper-key" >/dev/null 2>&1
  printf 'helper@example.test %s\n' "$(cat "$WORK/att-helper-key.pub")" > "$ATTH/.claude/approvers.pub"
  ( cd "$ATTH" && bash "$ROOT/scripts/spec-attest.sh" specs/0001-thing.md \
      --key "$WORK/att-helper-key" --approver helper@example.test ) >"$WORK/att-helper.out" 2>&1
  ATTH_TOK="$(bash -c '. "$1" >/dev/null 2>&1; slh_attest_load "$2" >/dev/null 2>&1; slh_attest_verify "$2" "specs/0001-thing.md"' \
      _ "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$ATTH" 2>/dev/null)"
  if [[ -f "$ATTH/specs/attest/0001.json" && -f "$ATTH/specs/attest/0001.sig" && "$ATTH_TOK" == "VERIFIED" ]]; then
    ok "attest round trip: what scripts/spec-attest.sh WRITES is what the git-hook verifier ACCEPTS"
  else
    bad "attest round trip: what scripts/spec-attest.sh WRITES is what the git-hook verifier ACCEPTS" \
        "token=[$ATTH_TOK]; the writer and the checker disagree, which is the one defect no single-sided test can see: $(head -3 "$WORK/att-helper.out" | tr '\n' ' ')"
  fi

  # THE HELPER UNDER FORGE CUSTODY WRITES A DOCUMENT AND NO SIGNATURE (2.6.0):
  # custody C has no key by design, and what it writes is what the library's
  # forge arm reads (structure, subject, hash) before deferring the approval
  # question to the forge check. Round-tripped here like the signer case.
  ATTH2="$WORK/attest-helper-forge"; att_fixture "$ATTH2" forge
  ( cd "$ATTH2" && bash "$ROOT/scripts/spec-attest.sh" specs/0001-thing.md \
      --approver helper@example.test ) >"$WORK/att-helper2.out" 2>&1
  if [[ -f "$ATTH2/specs/attest/0001.json" && ! -f "$ATTH2/specs/attest/0001.sig" ]] \
     && [[ "$(jq -r '.custody + " " + .spec_number' "$ATTH2/specs/attest/0001.json" 2>/dev/null)" == "forge 0001" ]]; then
    ok "attest helper: under forge custody it writes the document, signs NOTHING, and the document is the verifier's shape"
  else
    bad "attest helper: under forge custody it writes the document, signs NOTHING, and the document is the verifier's shape" \
        "$(head -3 "$WORK/att-helper2.out" | tr '\n' ' ')"
  fi
fi

# F1-2026, FIXED FOR DECLARING CLOSES AND PINNED AS A BOUNDARY FOR THE REST
# (2.3.0 leg F1; the RP1 ownership arm, spec 0126, design section 8.2).
#
# The old pin asserted the hole as it was: the NPAR<2 arm's LIN_CLOSED_OK
# short-circuited the role-path question for the ENTIRE commit on one
# compliant row flip. The 2026-08-29 ruling deferred the narrow fix because
# it was MEASURED not to discriminate: an honest squash close and the attack
# are one spec file plus one role-path file each, neither in any parent.
# Separating them needed a recorded fact the framework did not keep. It keeps
# it now: `Owns:` lines in the spec's hashed range, and the arm asks per-file
# coverage against the declared set instead of exempting the commit.
#
# THE PIN FLIPPED RED IN THIS COMMIT, exactly as the old pin's own failure
# message demanded, and is REWRITTEN here rather than deleted: the DECLARING
# attack (below) audited "1 clean, 0 violations" on the pre-fix bytes,
# watched, and now refuses on the smuggled file BY NAME. What remains pinned
# in the old direction is the BOUNDARY: a close that declares NOTHING keeps
# today's whole-commit exemption exactly (the Spec-hash absence precedent;
# anything else re-refuses the compliant legacy squash close spec 0121's F4
# fix exists to permit), and the public bullet is REPLACED by the boundary
# sentence that SAYS so, never deleted.
F1P="$WORK/f1-pin"; rm -rf "$F1P"; mkdir -p "$F1P/src" "$F1P/specs" "$F1P/.claude"
git_init "$F1P"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$F1P/.claude/sdd.json"
printf '{"setlist_status":1,"specs":{"0004":{"status":"active"},"0005":{"status":"active"}},"chores":{}}\n' > "$F1P/.claude/status.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0004 | wip | ACTIVE | in progress |\n| 0005 | docs | ACTIVE | in progress |\n' > "$F1P/specs/STATUS.md"
printf 'base\n' > "$F1P/base.txt"
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm seed >/dev/null 2>&1
F1P_BASE="$(git -C "$F1P" rev-parse HEAD)"
git -C "$F1P" checkout -q -b spec/0004-wip
printf 'work in progress; 0004 is still ACTIVE\n' > "$F1P/src/wip.txt"
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm 'wip on 0004' >/dev/null 2>&1
git -C "$F1P" checkout -q main
# The DECLARING close of 0005: it owns src/feat.txt and says so, closes with
# its recorded facts, and smuggles still-active 0004's file beside its own.
printf '# Spec 0005\n\nStatus: CLOSED\nOwns: src/feat.txt\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\nsmoke: PASS\n```\n' > "$F1P/specs/0005-docs.md"
printf 'the declared file\n' > "$F1P/src/feat.txt"
printf '{"setlist_status":1,"specs":{"0004":{"status":"active"},"0005":{"status":"closed","qa_pass_1":"ok","diagram":"no-impact"}},"chores":{}}\n' > "$F1P/.claude/status.json"
sed -e 's/| 0005 | docs | ACTIVE | in progress |/| 0005 | docs | CLOSED | done |/' "$F1P/specs/STATUS.md" > "$F1P/t" && mv "$F1P/t" "$F1P/specs/STATUS.md"
git -C "$F1P" checkout spec/0004-wip -- src/wip.txt 2>/dev/null
git -C "$F1P" add -A >/dev/null 2>&1; git -C "$F1P" commit -qm 'close spec 0005' >/dev/null 2>&1
F1P_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1P" --since "$F1P_BASE" 2>&1)"
# THE NEGATIVE CONTROL FIRST: the same injected file with NO close at all must
# be refused. Without it this pin passes against an audit that refuses nothing.
F1C="$WORK/f1-ctl"; rm -rf "$F1C"; cp -R "$F1P" "$F1C"
git -C "$F1C" reset -q --hard HEAD~1
git -C "$F1C" checkout spec/0004-wip -- src/wip.txt 2>/dev/null
git -C "$F1C" add -A >/dev/null 2>&1; git -C "$F1C" commit -qm 'no close, same file' >/dev/null 2>&1
F1C_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1C" --since "$F1P_BASE" 2>&1)"
if printf '%s' "$F1C_OUT" | grep -q 'VIOLATION'; then
  ok "F1-2026 control: the same injected file WITHOUT a close is still refused"
else
  bad "F1-2026 control: the same injected file WITHOUT a close is still refused" \
      "the audit refuses nothing here, so the pin below would pass against a dead check"
fi
if printf '%s' "$F1P_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/wip.txt'; then
  ok "F1-2026 (FIXED for declaring closes): the attack refuses ON SHAPE, naming the smuggled file, because still-active 0004's file is not in closing 0005's declared set"
else
  bad "F1-2026 (FIXED for declaring closes): the attack refuses ON SHAPE, naming the smuggled file, because still-active 0004's file is not in closing 0005's declared set" \
      "audit said: $(printf '%s' "$F1P_OUT" | tail -2 | tr '\n' ' ')"
fi
# The declared file itself is NOT named: the refusal is per file, not per
# commit, or the fix would be the old exemption inverted.
if printf '%s' "$F1P_OUT" | grep -q '\[SLH-OWNS-UNDECLARED\] src/feat.txt'; then
  bad "F1-2026 per-file: the declared file is covered; only the smuggled one refuses" \
      "src/feat.txt was refused despite being declared, so coverage is not being read per file"
else
  ok "F1-2026 per-file: the declared file is covered; only the smuggled one refuses"
fi

# THE BOUNDARY, PINNED IN ITS DISCLOSED DIRECTION so it cannot close by
# drift: a close that declares NOTHING (this legacy-shaped instance has no
# record and no Owns) keeps the whole-commit exemption EXACTLY, and the
# public boundary sentence says so. If someone widens or closes this, the
# sentence moves in the same commit.
F1L="$WORK/f1-legacy"; rm -rf "$F1L"; mkdir -p "$F1L/src" "$F1L/specs" "$F1L/.claude"
git_init "$F1L"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$F1L/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0004 | wip | ACTIVE | in progress |\n| 0005 | docs | ACTIVE | in progress |\n' > "$F1L/specs/STATUS.md"
printf 'base\n' > "$F1L/base.txt"
git -C "$F1L" add -A >/dev/null 2>&1; git -C "$F1L" commit -qm seed >/dev/null 2>&1
F1L_BASE="$(git -C "$F1L" rev-parse HEAD)"
printf '# Spec 0005\n\nStatus: CLOSED\n\n## Closing report\n\nArchitecture diagram: no impact\n\n```qa-pass-1\nsmoke: PASS\n```\n' > "$F1L/specs/0005-docs.md"
sed -e 's/| 0005 | docs | ACTIVE | in progress |/| 0005 | docs | CLOSED | done |/' "$F1L/specs/STATUS.md" > "$F1L/t" && mv "$F1L/t" "$F1L/specs/STATUS.md"
printf 'undeclared ride\n' > "$F1L/src/wip.txt"
git -C "$F1L" add -A >/dev/null 2>&1; git -C "$F1L" commit -qm 'close spec 0005' >/dev/null 2>&1
F1L_OUT="$(bash "$ROOT/scripts/trunk-audit.sh" --instance "$F1L" --since "$F1L_BASE" 2>&1)"
if printf '%s' "$F1L_OUT" | grep -q '0 violations'; then
  ok "F1-2026 boundary (PINNED, disclosed): a close declaring NOTHING keeps the whole-commit exemption exactly, as the boundary sentence says"
else
  bad "F1-2026 boundary (PINNED, disclosed): a close declaring NOTHING keeps the whole-commit exemption exactly, as the boundary sentence says" \
      "the non-declaring exemption changed; behaviour 4 of the ratified design says it must not, and the public sentence must move with any deliberate change here"
fi

# F2-2026 (leg F4, scaffolded evaluated as a boolean) IS FIXED HERE, and this
# block is the PIN REWRITTEN in the fix's own commit rather than deleted.
#
# What it pinned, in its previous direction: a non-boolean `scaffolded` stood
# the whole trunk-write gate down in SILENCE, having evaluated nothing. The pin
# asserted that hole so it could not close by drift, and it went red against
# these bytes exactly as it was built to.
#
# WHY THE FIX EXISTS NOW AND DID NOT AT 2.3.0, because it is not that anyone
# changed their mind. Two standing rules point opposite ways at fix-round size:
#
#   A2's trigger says a NEW deny code is a changed QUESTION and costs a full
#   leg. The publish-time attestation gate refused the 2.3.0 round for exactly
#   that when the fix raised SH-SCAFFOLDED-SHAPE.
#
#   The suite says two denials sharing a code cannot be told apart. Re-scoping
#   onto the existing SH-SDD-SHAPE to dodge the trigger tripped THAT instead.
#
# The entry priced the way out in advance: the cycle that takes it either owes
# a leg anyway, or needs a distinguishable code that does not already mean
# something else. The 2.4.0 cycle owes a leg BY COMPUTATION before its first
# byte, because the status record's deny codes change the guarantee-check
# identifier set. So the new identifiers cost nothing extra, and the fix ships
# with the identifiers it wanted rather than with the shared-code workaround.
#
# FOUR DIRECTIONS, because three of them are the ones a narrower fix breaks.
SCFP="$WORK/scaffold-pin"; rm -rf "$SCFP"; mkdir -p "$SCFP/src" "$SCFP/specs" "$SCFP/.claude"
git_init "$SCFP"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCFP/specs/STATUS.md"
SCFP_PAY="$(jq -nc --arg p "$SCFP/src/x.js" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
if printf '%s' "$HOOK_OUT" | grep -q 'SH-TRUNK-WRITE'; then
  ok "scaffolded control: a boolean true arms the trunk-write gate"
else
  bad "scaffolded control: a boolean true arms the trunk-write gate" "the gate is dead, so the assertions below would prove nothing"
fi

# The fix, asserted on the CODE and across every non-boolean shape the leg
# measured, not just the string it happened to reproduce with.
SCFP_SHAPE_MISS=""
for SCFP_V in '"yes"' '1' '{}' '[]' '"true"'; do
  printf '{"trunk":"main","scaffolded":%s,"roles":{"src":"src","tests":"tests"}}\n' "$SCFP_V" > "$SCFP/.claude/sdd.json"
  run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
  printf '%s' "$HOOK_OUT" | grep -q 'SH-SCAFFOLDED-SHAPE' || SCFP_SHAPE_MISS="$SCFP_SHAPE_MISS $SCFP_V"
done
if [[ -z "$SCFP_SHAPE_MISS" ]]; then
  ok "F2-2026 (FIXED): every present non-boolean scaffolded refuses with SH-SCAFFOLDED-SHAPE instead of standing the gate down in silence"
else
  bad "F2-2026 (FIXED): every present non-boolean scaffolded refuses with SH-SCAFFOLDED-SHAPE instead of standing the gate down in silence" \
      "these values still silenced the gate:$SCFP_SHAPE_MISS"
fi

# THE HONEST ZERO IS THE HALF A FIX BREAKS. Absent and boolean false must stay
# SILENTLY off: that is what every pre-scaffold instance depends on, and turning
# it into a refusal would refuse the one-time bootstrap this line exists to
# permit. Asserted on emptiness, because "allow is silence" here.
SCFP_ZERO_MISS=""
printf '{"trunk":"main","scaffolded":false,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
[[ -z "$HOOK_OUT" ]] || SCFP_ZERO_MISS="$SCFP_ZERO_MISS false"
printf '{"trunk":"main","roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
[[ -z "$HOOK_OUT" ]] || SCFP_ZERO_MISS="$SCFP_ZERO_MISS absent"
if [[ -z "$SCFP_ZERO_MISS" ]]; then
  ok "F2-2026 control: boolean false and an absent flag are still SILENTLY off, so the bootstrap this line permits is not refused"
else
  bad "F2-2026 control: boolean false and an absent flag are still SILENTLY off, so the bootstrap this line permits is not refused" \
      "the honest zero now warns for:$SCFP_ZERO_MISS; a fix that refuses the pre-scaffold state has broken the case it exists to allow"
fi

# F11-2026, THE THIRD EMITTER, and the reason this assertion exists at all.
#
# The entry was DISCHARGED 2026-08-29 naming an assertion as what makes a fourth
# rediscovery impossible rather than unlikely. The discharge was one emitter
# short: advise_literal() gained the code extraction in commit-gate.sh and
# close-gate.sh, THIS gate kept "code":"", and the assertion that was supposed
# to make the class permanent reads commit-gate.sh alone. So the record said the
# class was closed while a third of it was open, and nothing could notice.
#
# That is the entry's own A9 diagnosis, a rule that exists in some of its places
# and not all, surviving its own discharge note. The fix is one line; the reason
# it is worth a comment is that the DISCHARGE was the defect, not the code.
#
# The literal path is reached with jq ABSENT, which is what that path is for.
printf '{"trunk":"main","scaffolded":true,"roles":{"src":"src","tests":"tests"}}\n' > "$SCFP/.claude/sdd.json"
run_hook_nojq "$HOOKS/scope-hook.sh" "$SCFP" "$SCFP_PAY"
SCFP_CODE="$(printf '%s' "$HOOK_OUT" | jq -r '.setlistAdvisory.code // "<absent>"' 2>/dev/null)"
if [[ -n "$SCFP_CODE" && "$SCFP_CODE" != "<absent>" && "$SCFP_CODE" =~ ^[A-Z][A-Z0-9-]*$ ]]; then
  ok "F11-2026 third emitter: the scope hook's literal-reason deny carries a real setlistAdvisory.code ($SCFP_CODE), not the empty string"
else
  bad "F11-2026 third emitter: the scope hook's literal-reason deny carries a real setlistAdvisory.code, not the empty string" \
      "code=[$SCFP_CODE]; two of the three emitters were fixed in 2.3.0 and the entry recorded the whole class as discharged"
fi

# THE HEADER STRIP IS POSITIONAL, NOT SHAPED (2.3.0 leg, F3 and F5).
#
# A unified diff prefixes every added line with one `+`, so an added line whose
# CONTENT begins `++ b/` arrives as `+++ b/...` and is indistinguishable by
# SHAPE from the diff's own file header. The strip was anchored to the header's
# shape, so it ate the content: a secret on such a line passed both the
# guarantee layer and the advisory gate at rc=0, silently.
#
# The rule that fixes it is positional and it is git's own: a `+++` line is a
# HEADER only outside a hunk. Once `@@` has been seen, every `+` line is
# content, whatever it looks like. The scoped scan already worked this way,
# which is why this defect lived only in the unscoped branch and in the
# advisory gate's private copy.
#
# Asserted on the CODE at the git-hook layer and on the DENIAL at the advisory
# layer, with a clean twin at each so the fix cannot pass by refusing
# everything.
SCANHDR="$WORK/scan-hdr"; rm -rf "$SCANHDR"; mkdir -p "$SCANHDR/src" "$SCANHDR/specs" "$SCANHDR/.claude" "$SCANHDR/.githooks"
git_init "$SCANHDR"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SCANHDR/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCANHDR/specs/STATUS.md"
cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$SCANHDR/.githooks/"
chmod +x "$SCANHDR/.githooks/pre-commit"
printf 'seed\n' > "$SCANHDR/seed.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
git -C "$SCANHDR" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
git -C "$SCANHDR" config core.hooksPath .githooks

# The payload: a secret on a line whose content begins `++ b/`.
printf '++ b/decoy\nconst t = "ghp_abcdefghijklmnop1234"\n' > "$SCANHDR/src/evil.txt"
# Put the secret ON the `++ b/` line itself, which is the exact shape.
printf '++ b/x api_key = "abcdefghijklmnop1234"\n' > "$SCANHDR/src/evil.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
if git -C "$SCANHDR" commit -qm "header-shaped secret" >"$WORK/scanhdr.out" 2>&1; then
  bad "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer" \
      "it committed clean: the header strip ate the content line, so the scan read nothing and reported nothing"
else
  if grep -q 'SLH-SECRET' "$WORK/scanhdr.out"; then
    ok "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer"
  else
    bad "scan header F3: a secret on an added line beginning '++ b/' is REFUSED at the git-hook layer" \
        "refused for another reason: $(tr '\n' ' ' < "$WORK/scanhdr.out")"
  fi
fi
# THE CLEAN TWIN: an ordinary `++ b/` line with no secret must still commit, so
# the fix is a scan and not a ban on a spelling.
git -C "$SCANHDR" reset -q HEAD -- . 2>/dev/null
printf '++ b/x just an ordinary line\n' > "$SCANHDR/src/evil.txt"
git -C "$SCANHDR" add -A >/dev/null 2>&1
if git -C "$SCANHDR" commit -qm "header-shaped clean" >"$WORK/scanhdr2.out" 2>&1; then
  ok "scan header F3 twin: an ordinary line beginning '++ b/' still commits, so the fix scans rather than bans"
else
  bad "scan header F3 twin: an ordinary line beginning '++ b/' still commits, so the fix scans rather than bans" \
      "$(tr '\n' ' ' < "$WORK/scanhdr2.out")"
fi

# THE ADVISORY LAYER'S OWN COPY (leg F5), asserted on its code.
SCANHDR2="$WORK/scan-hdr-adv"; rm -rf "$SCANHDR2"; mkdir -p "$SCANHDR2/src" "$SCANHDR2/specs" "$SCANHDR2/.claude"
git_init "$SCANHDR2"
printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$SCANHDR2/.claude/sdd.json"
printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n' > "$SCANHDR2/specs/STATUS.md"
printf 'seed\n' > "$SCANHDR2/seed.txt"
git -C "$SCANHDR2" add -A >/dev/null 2>&1; git -C "$SCANHDR2" commit -qm seed >/dev/null 2>&1
printf '++ b/x api_key = "abcdefghijklmnop1234"\n' > "$SCANHDR2/src/evil.txt"
git -C "$SCANHDR2" add -A >/dev/null 2>&1
run_hook "$HOOKS/commit-gate.sh" "$SCANHDR2" "$(bash_payload 'git commit -m x')"
expect_deny "scan header F5: the advisory gate names a secret on an added line beginning '++ b/'" "CM-SECRET"

# THE BLOB-PINNED DIFFERENTIAL: off is byte-identical, PROVEN rather than said.
#
# The KL3 banner claims that an instance declaring no attestation behaves
# exactly as one that never heard of the feature. That claim was NARROWED when
# the claims sweep flagged it, because what the suite proved was only the
# behavioural half (the off path emits nothing and commits). This is the other
# half, and it is KL4's method: pin the PRE-FEATURE hook blobs, run both
# generations over the same cases, and compare stdout, stderr and exit code
# byte for byte. Absence proven identical rather than asserted.
#
# A8: the case count is asserted before the agreement is believed. Two
# generations that were never run over anything agree perfectly.
DIFFPRE="$ROOT/test/fixtures/pre-attest-hooks"
if [[ ! -d "$DIFFPRE" ]]; then
  ok "attest differential: SKIPPED, the pre-feature hook blobs are not present in this tree (export copy)"
else
  DIFFD="$WORK/attest-diff"; rm -rf "$DIFFD"; mkdir -p "$DIFFD"
  DIFF_N=0; DIFF_BAD=""
  for diff_case in clean emdash secret lifecycle; do
    for diff_gen in pre now; do
      d="$DIFFD/$diff_case-$diff_gen"
      rm -rf "$d"; mkdir -p "$d/src" "$d/specs" "$d/.claude" "$d/.githooks"
      git_init "$d"
      # NO attestation block at all: this is custody D, the honest zero.
      printf '{"trunk":"main","scaffolded":true,"gate_command":"true","roles":{"src":"src","tests":"tests"}}\n' > "$d/.claude/sdd.json"
      printf '# inv\n\n| Num | Title | Status | Note |\n| --- | --- | --- | --- |\n| 0001 | Thing | ACTIVE | wip |\n' > "$d/specs/STATUS.md"
      printf '# Spec 0001\n\nStatus: ACTIVE\n' > "$d/specs/0001-thing.md"
      if [[ "$diff_gen" == "pre" ]]; then
        cp "$DIFFPRE/pre-commit" "$DIFFPRE/setlist-hook-lib.sh" "$d/.githooks/"
      else
        cp "$ROOT/templates/git-hooks/pre-commit" "$ROOT/templates/git-hooks/setlist-hook-lib.sh" "$d/.githooks/"
      fi
      chmod +x "$d/.githooks/pre-commit"
      printf 'seed\n' > "$d/seed.txt"
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" -c core.hooksPath=/dev/null commit -qm seed >/dev/null 2>&1
      git -C "$d" config core.hooksPath .githooks
      case "$diff_case" in
        clean)     printf 'ordinary work\n' > "$d/src/app.js" ;;
        emdash)    printf 'a %s b\n' "$EMDASH" > "$d/src/app.js" ;;
        secret)    printf 'const token = "ghp_abcdefghijklmnop1234"\n' > "$d/src/app.js" ;;
        lifecycle) printf 'work\n' > "$d/src/app.js"; printf '# Spec 0001\n\nStatus: BUILT\n' > "$d/specs/0001-thing.md" ;;
      esac
      git -C "$d" add -A >/dev/null 2>&1
      git -C "$d" commit -qm "case $diff_case" >"$DIFFD/$diff_case-$diff_gen.out" 2>&1
      printf 'exit=%s\n' "$?" >> "$DIFFD/$diff_case-$diff_gen.out"
      norm_escape_coaching "$DIFFD/$diff_case-$diff_gen.out"
    done
    DIFF_N=$((DIFF_N + 1))
    if ! cmp -s "$DIFFD/$diff_case-pre.out" "$DIFFD/$diff_case-now.out"; then
      DIFF_BAD="$DIFF_BAD $diff_case"
    fi
  done
  if [[ "$DIFF_N" -eq 4 && -z "$DIFF_BAD" ]]; then
    ok "attest differential: with NO attestation declared, all 4 cases are byte-identical between the pre-feature and current hooks"
  else
    bad "attest differential: with NO attestation declared, all 4 cases are byte-identical between the pre-feature and current hooks" \
        "$DIFF_N of 4 cases compared, differing:${DIFF_BAD:- none}; off must mean off, and this is the half a behavioural assertion cannot reach"
  fi
fi

# CO1: THE CITED LEG MUST BE A LEG OF THIS RELEASE, asserted at last.
#
# The refusal itself was bought by the owner ruling of 2026-08-21 and has been
# in the shipped bytes since. What was missing is this: nothing asserted it, so
# the file's own residual comment went on describing the hole for a week after
# it closed, CO1 was filed against that comment, and the 2026-08-28 ruling
# bought a refusal that already existed. A property that is true and unwatched
# is how that happens, and the assertion is the part that stops it happening
# again rather than the extraction being the part that fixed anything.
#
# Driven against the SHIPPED predicate, extracted from attestation-check.sh
# rather than reimplemented, for the reason the CI scope check gives: a copy
# drifts and then the test asserts things about a function that is no longer the
# one running.
CO1SH="$ROOT/publish/attestation-check.sh"
if [[ ! -f "$CO1SH" ]]; then
  ok "CO1 leg-of-this-release: SKIPPED, publish/ is absent (expected in the public repo)"
else
  CO1D="$WORK/co1"; rm -rf "$CO1D"; mkdir -p "$CO1D"
  awk '/^is_leg_of\(\) \{/,/^\}/' "$CO1SH" > "$CO1D/pred.sh"
  if [[ ! -s "$CO1D/pred.sh" ]]; then
    bad "CO1 leg-of-this-release: is_leg_of was extracted from attestation-check.sh" \
        "could not extract the predicate, so this check cannot run, which is a failure rather than a pass"
  else
    printf 'HOSTILE-REVIEW: 2.2.0 PASS\nRESOLVED-TREE: abc\n' > "$CO1D/stale.md"
    printf 'HOSTILE-REVIEW: 2.3.0 PASS\nRESOLVED-TREE: abc\n' > "$CO1D/same.md"
    printf 'HOSTILE-REVIEW: 2.3.0 PASS-WITH-FINDINGS\nRESOLVED-TREE: abc\n' > "$CO1D/round2.md"
    co1_run() { bash -c 'refused_family() { :; }; . "$1"; if is_leg_of "$2" "$3"; then echo ACCEPT; else echo REFUSE; fi' _ "$CO1D/pred.sh" "$1" "$2" 2>/dev/null; }
    # THE CASE THAT HAD TO STOP: an older release's leg, with its smaller
    # finding list, satisfying coverage for this release.
    if [[ "$(co1_run "$CO1D/stale.md" 2.3.0)" == "REFUSE" ]]; then
      ok "CO1: a leg attesting a PRIOR release is refused as this release's cited leg"
    else
      bad "CO1: a leg attesting a PRIOR release is refused as this release's cited leg" \
          "a record could satisfy replay coverage over a finding list that is not this release's"
    fi
    # THE CASE THAT HAD TO KEEP WORKING, and the reason the ruling scoped itself
    # to the version string ALONE: a fix round cites the leg that reviewed the
    # PREVIOUS CANDIDATE of the same release, which is the ordinary shape.
    if [[ "$(co1_run "$CO1D/same.md" 2.3.0)" == "ACCEPT" && "$(co1_run "$CO1D/round2.md" 2.3.0)" == "ACCEPT" ]]; then
      ok "CO1 control: a SAME-version leg, including PASS-WITH-FINDINGS, is still accepted"
    else
      bad "CO1 control: a SAME-version leg, including PASS-WITH-FINDINGS, is still accepted" \
          "the refusal is over-wide and would refuse a round-2 record citing candidate 1's leg, which is the cost the ruling scoped itself to avoid"
    fi
  fi
fi

# A9 AT THE PUSH LAYER: the range arm has exactly one definition and pre-push
# reaches the predicate through it rather than asking its own way. Three
# content-seeing layers already reach the scan through one function; this
# pins the same property for the approval check before a second reader exists.
ATTW_DEFS="$(grep -rl 'slh_attest_walk() {' "$ROOT/templates" "$ROOT/scripts" 2>/dev/null | grep -c . || true)"
ATTW_CALL="$(grep -c 'slh_attest_walk ' "$ROOT/templates/git-hooks/pre-push" 2>/dev/null || true)"
if [[ "$ATTW_DEFS" == "1" && "$ATTW_CALL" -ge 1 ]]; then
  ok "attest push A9: one definition of slh_attest_walk, and pre-push reaches the predicate through it"
else
  bad "attest push A9: one definition of slh_attest_walk, and pre-push reaches the predicate through it" \
      "definitions=$ATTW_DEFS callers-in-pre-push=$ATTW_CALL"
fi

fi; shard_region_end
# <<< SHARD-END attest-push-arm
