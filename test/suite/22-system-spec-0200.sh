# Shard 22: the system spec of a system of repositories (spec 0200). Sourced by test/run-tests.sh.
#
# =============================================================================
# THE system_spec KEY (spec 0200, item 2; D4 of the session-zero rebuild). A
# system of several repositories has one system spec (Part 4), and each step of
# the bootstrap plan stamps its repository with an answers line
# system_spec=<path or URL>. The stamp records it in .claude/sdd.json by --arg
# and reads it back; absent, no key is written and the file is what it was. The
# refresh's one write merges, so the key is kept across --apply, and its reading
# names it. No hook reads the key: these cases assert a record, not a verdict.
# Every fixture is built here, from the real stamp, so the region depends on
# nothing outside it.
# =============================================================================
# >>> SHARD-BEGIN system-spec-0200 cost=1
if shard_region system-spec-0200; then

SY="$WORK/system-spec-0200"
rm -rf "$SY"; mkdir -p "$SY/plain" "$SY/with" "$SY/quoted" "$SY/refreshed"
printf 'project_name=Sys\nstack=bash\nworking_mode=review-only\nui=no\nplanning_model=\nexecution_model=\ndesign_surface=no\nmode=new\n' > "$SY/answers.txt"
{ cat "$SY/answers.txt"; printf 'system_spec=../shop-system/system.md\n'; } > "$SY/answers-with.txt"
{ cat "$SY/answers.txt"; printf 'system_spec=../my "sys"/system.md\n'; } > "$SY/answers-quoted.txt"
SY_PLAIN_RC=0; bash "$ROOT/scripts/stamp.sh" "$SY/answers.txt" "$SY/plain" > "$SY/plain.log" 2>&1 || SY_PLAIN_RC=$?
SY_WITH_RC=0; bash "$ROOT/scripts/stamp.sh" "$SY/answers-with.txt" "$SY/with" > "$SY/with.log" 2>&1 || SY_WITH_RC=$?

# a. The answer is recorded and read back, and the summary names it.
if [[ "$SY_WITH_RC" -eq 0 ]] \
   && [[ "$(jq -r '.system_spec // empty' "$SY/with/.claude/sdd.json" 2>/dev/null)" == "../shop-system/system.md" ]] \
   && grep -qF 'recorded the system spec in .claude/sdd.json: system_spec="../shop-system/system.md"' "$SY/with.log"; then
  ok "0200 system spec a: the stamp records system_spec from the answers in .claude/sdd.json and names it in its summary"
else
  bad "0200 system spec a: the stamp records system_spec from the answers in .claude/sdd.json and names it in its summary" \
      "rc=$SY_WITH_RC value=$(jq -r '.system_spec // "absent"' "$SY/with/.claude/sdd.json" 2>/dev/null) summary=$(grep -c 'system spec' "$SY/with.log" 2>/dev/null)"
fi

# b. Without the answer no key is written, the field set is the template's, and
#    the file with the answer differs from it by that one field only.
SY_TPL_FIELDS="$(jq -c '[path(.[])[0]] | sort' "$ROOT/templates/claude/sdd.json.tmpl" 2>/dev/null)"
SY_PLAIN_FIELDS="$(jq -c '[path(.[])[0]] | sort' "$SY/plain/.claude/sdd.json" 2>/dev/null)"
if [[ "$SY_PLAIN_RC" -eq 0 ]] && [[ -n "$SY_TPL_FIELDS" ]] && [[ "$SY_PLAIN_FIELDS" == "$SY_TPL_FIELDS" ]] \
   && ! grep -q 'system spec' "$SY/plain.log" \
   && [[ "$(jq -S 'del(.system_spec)' "$SY/with/.claude/sdd.json" 2>/dev/null)" == "$(jq -S . "$SY/plain/.claude/sdd.json" 2>/dev/null)" ]]; then
  ok "0200 system spec b: without the answer the stamp writes no system_spec, and the file with the answer differs by that field alone"
else
  bad "0200 system spec b: without the answer the stamp writes no system_spec, and the file with the answer differs by that field alone" \
      "rc=$SY_PLAIN_RC template-fields=$SY_TPL_FIELDS plain-fields=$SY_PLAIN_FIELDS"
fi

# c. A value carrying a quote and a space is data to jq: the file parses as one
#    object and holds the value as given.
SY_Q_RC=0; bash "$ROOT/scripts/stamp.sh" "$SY/answers-quoted.txt" "$SY/quoted" > "$SY/quoted.log" 2>&1 || SY_Q_RC=$?
if [[ "$SY_Q_RC" -eq 0 ]] && [[ "$(jq -s 'length' "$SY/quoted/.claude/sdd.json" 2>/dev/null)" == "1" ]] \
   && [[ "$(jq -r '.system_spec' "$SY/quoted/.claude/sdd.json" 2>/dev/null)" == '../my "sys"/system.md' ]]; then
  ok "0200 system spec c: a system_spec carrying a quote and a space is recorded as data, and the file stays one object"
else
  bad "0200 system spec c: a system_spec carrying a quote and a space is recorded as data, and the file stays one object" \
      "rc=$SY_Q_RC value=$(jq -r '.system_spec // "absent"' "$SY/quoted/.claude/sdd.json" 2>/dev/null | cut -c1-80)"
fi

# d. The refresh names the key in its reading and keeps it across --apply.
git -C "$SY/refreshed" init -q 2>/dev/null
SY_R_RC=0; bash "$ROOT/scripts/stamp.sh" "$SY/answers-with.txt" "$SY/refreshed" > /dev/null 2>&1 || SY_R_RC=$?
bash "$ROOT/scripts/refresh-instance.sh" "$SY/refreshed" > "$SY/refresh-read.log" 2>&1 || true # fail-open-ok: the reading's exit is not the claim; the line below is
SY_A_RC=0; bash "$ROOT/scripts/refresh-instance.sh" --apply "$SY/refreshed" > "$SY/refresh-apply.log" 2>&1 || SY_A_RC=$?
if [[ "$SY_R_RC" -eq 0 && "$SY_A_RC" -eq 0 ]] \
   && grep -qF '.claude/sdd.json records the system spec: system_spec=../shop-system/system.md' "$SY/refresh-read.log" \
   && [[ "$(jq -r '.system_spec // empty' "$SY/refreshed/.claude/sdd.json" 2>/dev/null)" == "../shop-system/system.md" ]]; then
  ok "0200 system spec d: the refresh names the recorded system_spec in its reading and keeps it across --apply"
else
  bad "0200 system spec d: the refresh names the recorded system_spec in its reading and keeps it across --apply" \
      "stamp-rc=$SY_R_RC apply-rc=$SY_A_RC read-line=$(grep -c 'records the system spec' "$SY/refresh-read.log" 2>/dev/null) value=$(jq -r '.system_spec // "absent"' "$SY/refreshed/.claude/sdd.json" 2>/dev/null)"
fi

# e. An instance without the key: the refresh's reading says nothing about one.
git -C "$SY/plain" init -q 2>/dev/null
bash "$ROOT/scripts/refresh-instance.sh" "$SY/plain" > "$SY/plain-read.log" 2>&1 || true # fail-open-ok: the reading's exit is not the claim; the line below is
if ! grep -q 'system spec' "$SY/plain-read.log" && grep -q 'refresh' "$SY/plain-read.log"; then
  ok "0200 system spec e: an instance without system_spec reads as before (the refresh prints no system-spec line)"
else
  bad "0200 system spec e: an instance without system_spec reads as before (the refresh prints no system-spec line)" \
      "$(grep 'system spec' "$SY/plain-read.log" | head -1 | cut -c1-160)"
fi

fi; shard_region_end
# <<< SHARD-END system-spec-0200

# =============================================================================
# BOTH REPOSITORIES STAMPED FROM ONE PLAN (spec 0200, item 3; F1). The fixture
# test/fixtures/system-of-two/ holds an API and a web front end as they exist
# before Setlist, and system/system.md, the shape of a system spec with its
# bootstrap plan. This region walks that plan as a session would, one numbered
# step per repository: each repository's answers file with its system_spec, the
# real stamp in retrofit mode into its directory. Then both instances must
# record the same system spec, and the path each records must resolve to the
# system spec from that repository, which is what /setlist:validate reads.
# =============================================================================
# >>> SHARD-BEGIN system-of-two-0200 cost=1
if shard_region system-of-two-0200; then

ST_FX="$ROOT/test/fixtures/system-of-two"
ST="$WORK/system-of-two-0200"
rm -rf "$ST"; mkdir -p "$ST"
cp -R "$ST_FX/api" "$ST_FX/web" "$ST_FX/system" "$ST/"
ST_PLAN="$(grep -E '^[0-9]+\. ' "$ST/system/system.md" 2>/dev/null || true)" # fail-open-ok: an empty plan fails the step count below
ST_STEPS=0; ST_DONE=0; ST_BAD=""
while IFS= read -r ST_LINE; do
  [[ -n "$ST_LINE" ]] || continue
  ST_STEPS=$((ST_STEPS + 1))
  ST_NAME="$(printf '%s' "$ST_LINE" | sed -E 's/^[0-9]+\. ([^:]+):.*/\1/')"
  ST_DIR="$(printf '%s' "$ST_LINE" | sed -E 's/.*directory `([^`]+)`.*/\1/')"
  ST_SRC="$(printf '%s' "$ST_LINE" | sed -E 's/.* src `([^`]+)`.*/\1/')"
  ST_TESTS="$(printf '%s' "$ST_LINE" | sed -E 's/.* tests `([^`]+)`.*/\1/')"
  ST_SPEC="$(printf '%s' "$ST_LINE" | sed -E 's/.*system_spec `([^`]+)`.*/\1/')"
  ST_TARGET="$ST/system/$ST_DIR"
  git -C "$ST_TARGET" init -q 2>/dev/null || { ST_BAD="$ST_BAD $ST_NAME:no-repository"; break; }
  printf 'project_name=%s\nstack=node\nworking_mode=review-only\nui=no\nplanning_model=\nexecution_model=\ndesign_surface=no\nsrc_role=%s\ntests_role=%s\nsizing=estate\nsystem_spec=%s\nmode=retrofit\n' \
    "$ST_NAME" "$ST_SRC" "$ST_TESTS" "$ST_SPEC" > "$ST/answers-$ST_NAME.txt"
  ST_RC=0; bash "$ROOT/scripts/stamp.sh" "$ST/answers-$ST_NAME.txt" "$ST_TARGET" > "$ST/stamp-$ST_NAME.log" 2>&1 || ST_RC=$?
  [[ "$ST_RC" -eq 0 ]] || { ST_BAD="$ST_BAD $ST_NAME:stamp-rc=$ST_RC"; break; }
  [[ "$(jq -r '.system_spec // empty' "$ST_TARGET/.claude/sdd.json" 2>/dev/null)" == "$ST_SPEC" ]] || ST_BAD="$ST_BAD $ST_NAME:not-recorded"
  [[ -f "$ST_TARGET/$ST_SPEC" ]] || ST_BAD="$ST_BAD $ST_NAME:does-not-resolve"
  ST_DONE=$((ST_DONE + 1))
done <<< "$ST_PLAN"
if [[ "$ST_STEPS" -eq 2 && "$ST_DONE" -eq 2 && -z "$ST_BAD" ]] \
   && [[ "$(jq -r '.system_spec' "$ST/api/.claude/sdd.json" 2>/dev/null)" == "$(jq -r '.system_spec' "$ST/web/.claude/sdd.json" 2>/dev/null)" ]]; then
  ok "0200 system of two a: the fixture's plan stamps both repositories in order, and both record the one system spec, which resolves from each"
else
  bad "0200 system of two a: the fixture's plan stamps both repositories in order, and both record the one system spec, which resolves from each" \
      "steps=$ST_STEPS done=$ST_DONE problems=[${ST_BAD# }]"
fi

fi; shard_region_end
# <<< SHARD-END system-of-two-0200
