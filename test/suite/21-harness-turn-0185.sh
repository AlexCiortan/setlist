# Shard 21: the stamped instance's harness turn (spec 0185). Sourced by test/run-tests.sh.
#
# =============================================================================
# THE VERIFY SKILL (spec 0185, item 1; C-71 of the 2026-10-05 scan). Claude Code
# asks for a skill named verify before a commit (measured on 2.1.287 and 2.1.292
# with a neutral description; 2.1.221 does not call it). Every instance carries
# one: the stamp writes it in both modes, its block runs gate_command once and
# reports, and the refresh delivers it on upgrade on the session hooks' NEW /
# SAME / CHANGED shape (E-d), keeping a differing copy as .setlist-backup.
# The cases run the skill's OWN bash block, extracted from the template, so the
# bytes an agent runs are the bytes asserted.
# =============================================================================
# >>> SHARD-BEGIN verify-skill-0185 cost=2
if shard_region verify-skill-0185; then

VS="$WORK/verify-skill-0185"
rm -rf "$VS"; mkdir -p "$VS"
VS_TPL="$ROOT/templates/claude/skills/verify/SKILL.md"
VS_REL=".claude/skills/verify/SKILL.md"

# a. The prelude's new-mode stamp, and a retrofit stamp, both carry it byte-verbatim; STAMP-TREE maps it.
VS_BAD=""
[[ "$STAMP_RC" -eq 0 ]] || VS_BAD="$VS_BAD new-stamp-rc=$STAMP_RC"
cmp -s "$VS_TPL" "$STAMP_TARGET/$VS_REL" 2>/dev/null || VS_BAD="$VS_BAD new-mode-absent-or-differs"
printf 'project_name=Retro\nstack=bash\nworking_mode=solo\nui=no\nopusplan_verified=no\ndesign_surface=no\nmode=retrofit\n' > "$VS/answers-retro.txt"
mkdir -p "$VS/retro/src" "$VS/retro/tests"
bash "$ROOT/scripts/stamp.sh" "$VS/answers-retro.txt" "$VS/retro" >/dev/null 2>&1 || VS_BAD="$VS_BAD retrofit-stamp-rc"
cmp -s "$VS_TPL" "$VS/retro/$VS_REL" 2>/dev/null || VS_BAD="$VS_BAD retrofit-mode-absent-or-differs"
grep -qF '| `claude/skills/verify/SKILL.md` | `.claude/skills/verify/SKILL.md` | always' "$ROOT/templates/STAMP-TREE.md" || VS_BAD="$VS_BAD stamp-tree-row"
VS_FM="$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$VS_TPL" 2>/dev/null || true)" # fail-open-ok: an empty frontmatter fails the line below
grep -qx 'name: verify' <<< "$VS_FM" || VS_BAD="$VS_BAD name"
if [[ -z "$VS_BAD" ]]; then
  ok "0185 verify a: both stamp modes write the verify skill byte-verbatim, named verify, and STAMP-TREE maps it"
else
  bad "0185 verify a: both stamp modes write the verify skill byte-verbatim, named verify, and STAMP-TREE maps it" "$VS_BAD"
fi

# b to d. The skill's own block, run in an instance: the gate's lines and rc; an empty command; no jq.
VS_BLOCK="$(awk '/^```bash$/ { on = 1; next } on && /^```$/ { exit } on' "$VS_TPL")"
mkdir -p "$VS/inst/.claude"
printf '{"gate_command":"echo GATE-LINE-0185; exit 3"}\n' > "$VS/inst/.claude/sdd.json"
VS_OUT="$(cd "$VS/inst" && bash -c "$VS_BLOCK" 2>&1)"; VS_RC=$?
if [[ "$VS_RC" -eq 3 && "$VS_OUT" == *"GATE-LINE-0185"* && "$VS_OUT" == *"verify: the gate command exited 3"* ]]; then
  ok "0185 verify b: the skill's block runs gate_command once and reports its lines and its exit status"
else
  bad "0185 verify b: the skill's block runs gate_command once and reports its lines and its exit status" "rc $VS_RC, output: ${VS_OUT:-<empty>}"
fi
printf '{"gate_command":""}\n' > "$VS/inst/.claude/sdd.json"
VS_OUT="$(cd "$VS/inst" && bash -c "$VS_BLOCK" 2>&1)"; VS_RC=$?
if [[ "$VS_RC" -eq 2 && "$VS_OUT" == *"no gate command is recorded"* ]]; then
  ok "0185 verify c: an empty gate_command is reported as a gate that did not run, never as a pass"
else
  bad "0185 verify c: an empty gate_command is reported as a gate that did not run, never as a pass" "rc $VS_RC, output: ${VS_OUT:-<empty>}"
fi
# A PATH with no jq: wrapper scripts, never links (spec 0168: Windows cannot run a linked MSYS executable).
mkdir -p "$VS/nojq"
for t in mktemp tail rm; do
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$(command -v "$t")" > "$VS/nojq/$t"; chmod +x "$VS/nojq/$t"
done
VS_BASH="$(command -v bash)"
VS_OUT="$(cd "$VS/inst" && PATH="$VS/nojq" "$VS_BASH" -c "$VS_BLOCK" 2>&1)"; VS_RC=$?
if [[ "$VS_RC" -eq 2 && "$VS_OUT" == *"jq is not on PATH"* ]]; then
  ok "0185 verify d: without jq the skill names jq and reports that the gate did not run"
else
  bad "0185 verify d: without jq the skill names jq and reports that the gate did not run" "rc $VS_RC, output: ${VS_OUT:-<empty>}"
fi
# h, i (spec 0189 fix round 1, the 2.12.0 leg's F6): where .claude/sdd.json declares a gates
# block the hooks run its close tier (setlist-hook-lib.sh slh_gate_command_for), so the skill
# runs that, never the single gate_command beside it; a gates block that cannot be read is a
# gate that did not run.
printf '{"gate_command":"true","gates":{"commit":"","close":"echo CLOSE-TIER-0189; exit 4","push":"true"}}\n' > "$VS/inst/.claude/sdd.json"
VS_OUT="$(cd "$VS/inst" && bash -c "$VS_BLOCK" 2>&1)"; VS_RC=$?
if [[ "$VS_RC" -eq 4 && "$VS_OUT" == *"CLOSE-TIER-0189"* && "$VS_OUT" == *"verify: the gate command exited 4"* ]]; then
  ok "0189 verify h: with a gates block the skill runs its close tier, the gate the hooks run, and reports it red"
else
  bad "0189 verify h: with a gates block the skill runs its close tier, the gate the hooks run, and reports it red" "rc $VS_RC, output: ${VS_OUT:-<empty>}"
fi
printf '{"gate_command":"true","gates":"not an object"}\n' > "$VS/inst/.claude/sdd.json"
VS_OUT="$(cd "$VS/inst" && bash -c "$VS_BLOCK" 2>&1)"; VS_RC=$?
if [[ "$VS_RC" -eq 2 && "$VS_OUT" == *"gates block"* ]]; then
  ok "0189 verify i: a gates block that cannot be read is reported as a gate that did not run, never as a pass"
else
  bad "0189 verify i: a gates block that cannot be read is reported as a gate that did not run, never as a pass" "rc $VS_RC, output: ${VS_OUT:-<empty>}"
fi

# e to h. The refresh: missing, delivered, same, then an edited copy replaced with its backup.
VS_I="$VS/upg"
instance_fixture "$VS_I" 2.11.0
run_script bash "$SCRIPTS/refresh-instance.sh" "$VS_I"
expect_script "0185 verify e: the refresh's report names the missing verify skill" 0 "missing, would be stamped:" "$VS_REL"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$VS_I"
if [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$VS_TPL" "$VS_I/$VS_REL"; then
  ok "0185 verify f: --apply delivers the verify skill byte-identical to the template"
else
  bad "0185 verify f: --apply delivers the verify skill byte-identical to the template" "rc $SCRIPT_RC, output: ${SCRIPT_OUT:-<empty>}"
fi
run_script bash "$SCRIPTS/refresh-instance.sh" "$VS_I"
expect_script "0185 verify g: a delivered copy reads already byte-identical" 0 "already byte-identical:" "$VS_REL"
printf '\nA hand edit.\n' >> "$VS_I/$VS_REL"
cp "$VS_I/$VS_REL" "$VS/edited"
run_script bash "$SCRIPTS/refresh-instance.sh" "$VS_I"
VS_REPORT="$SCRIPT_OUT"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$VS_I"
if [[ "$VS_REPORT" == *"bytes differ, would be replaced (the previous file is kept as .setlist-backup):"*"$VS_REL"* ]] \
   && [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$VS_TPL" "$VS_I/$VS_REL" && cmp -s "$VS/edited" "$VS_I/$VS_REL.setlist-backup"; then
  ok "0185 verify h: an edited copy is reported, replaced, and kept beside it as .setlist-backup"
else
  bad "0185 verify h: an edited copy is reported, replaced, and kept beside it as .setlist-backup" "report: $VS_REPORT; apply rc $SCRIPT_RC: $SCRIPT_OUT"
fi
# j (spec 0189 fix round 1, the 2.12.0 leg's F11): a second differing refresh keeps the FIRST
# backup; the user's original survives any number of refreshes, and the report says so first.
printf '\nA second edit.\n' >> "$VS_I/$VS_REL"
run_script bash "$SCRIPTS/refresh-instance.sh" "$VS_I"
VS_REPORT="$SCRIPT_OUT"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$VS_I"
if [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$VS/edited" "$VS_I/$VS_REL.setlist-backup" && cmp -s "$VS_TPL" "$VS_I/$VS_REL" \
   && [[ "$VS_REPORT" == *"is already there and is kept"*"$VS_REL"* ]] && [[ "$SCRIPT_OUT" == *"was not overwritten"* ]]; then
  ok "0189 verify j: a second differing refresh keeps the first .setlist-backup, named in the report and in the apply"
else
  bad "0189 verify j: a second differing refresh keeps the first .setlist-backup, named in the report and in the apply" "report: $VS_REPORT; apply rc $SCRIPT_RC: $SCRIPT_OUT"
fi

# i. The drift report reads the skill (every markdown file under .claude/skills/) and finds nothing stale in it.
run_script bash "$SCRIPTS/refresh-instance.sh" "$VS_I"
if [[ "$SCRIPT_OUT" != *"$VS_REL:"* ]]; then
  ok "0185 verify i: the drift report reads the stamped verify skill and names no stale line in it"
else
  bad "0185 verify i: the drift report reads the stamped verify skill and names no stale line in it" "$SCRIPT_OUT"
fi
fi; shard_region_end
# <<< SHARD-END verify-skill-0185


# =============================================================================
# THE SERVED MODEL PER PHASE (spec 0185, item 2; 0177's E-2). The probe prints a
# machine line per phase; the bootstrap writes the ids into the answers; the stamp
# records them as "models" and writes the model line from them; the legacy yes or
# no is read for one release with a notice; the refresh measures nothing and
# reports an absent record (E-b as ruled). Two phases only (E-c, the validator's
# alternative): no escalation key. Its own stub claude, so the region stands alone.
# =============================================================================
# >>> SHARD-BEGIN served-model-0185 cost=2
if shard_region served-model-0185; then

SM="$WORK/served-model-0185"
rm -rf "$SM"; mkdir -p "$SM/bin"
cat > "$SM/bin/claude" <<'STUB'
#!/usr/bin/env bash
d="$(dirname "$0")/.."
phase=exec
for a in "$@"; do [[ "$a" == plan ]] && phase=plan; done
cat "$d/$phase.json"
STUB
chmod +x "$SM/bin/claude"
printf '{"type":"result","is_error":false,"result":"ok","usage":{"output_tokens":5},"modelUsage":{"claude-opus-test":{"outputTokens":5}}}\n' > "$SM/plan.json"
printf '{"type":"result","is_error":false,"result":"ok","usage":{"output_tokens":5},"modelUsage":{"claude-sonnet-test":{"outputTokens":5}}}\n' > "$SM/exec.json"
run_script env PATH="$SM/bin:$PATH" bash "$SCRIPTS/model-probe.sh"
expect_script "0185 served a: the probe prints one machine line per phase beside its human lines" 0 \
  "served planning claude-opus-test" "served execution claude-sonnet-test" "plan: claude-opus-test"
if grep -q 'served escalation' <<< "$SCRIPT_OUT"; then
  bad "0185 served a2: two phases only, no escalation line (E-c as ruled)" "$SCRIPT_OUT"
else
  ok "0185 served a2: two phases only, no escalation line (E-c as ruled)"
fi

sm_stamp() { # sm_stamp <name> <answers-tail> -> SM_OUT, SM_RC, the instance at $SM/<name>
  mkdir -p "$SM/$1"
  printf 'project_name=P\nstack=bash\nworking_mode=solo\nui=no\ndesign_surface=no\n%b\n' "$2" > "$SM/$1.answers"
  SM_OUT="$(bash "$ROOT/scripts/stamp.sh" "$SM/$1.answers" "$SM/$1" 2>&1)"; SM_RC=$?
}
sm_stamp new 'planning_model=claude-opus-test\nexecution_model=claude-sonnet-test'
if [[ "$SM_RC" -eq 0 ]] \
   && [[ "$(jq -c '.models' "$SM/new/.claude/sdd.json" 2>/dev/null)" == '{"planning":"claude-opus-test","execution":"claude-sonnet-test"}' ]] \
   && [[ "$(jq -r '.model // empty' "$SM/new/.claude/settings.json" 2>/dev/null)" == "opusplan" ]] \
   && jq -e '[to_entries[].key] | index("models") > index("plugin")' "$SM/new/.claude/sdd.json" >/dev/null 2>&1; then
  ok "0185 served b: the stamp records both served ids as models (appended) and writes the opusplan line"
else
  bad "0185 served b: the stamp records both served ids as models (appended) and writes the opusplan line" "rc $SM_RC: $SM_OUT"
fi
sm_stamp offtier 'planning_model=claude-sonnet-test\nexecution_model=claude-sonnet-test'
if [[ "$SM_RC" -eq 0 ]] && [[ "$(jq -r '.models.planning' "$SM/offtier/.claude/sdd.json" 2>/dev/null)" == "claude-sonnet-test" ]] \
   && [[ -z "$(jq -r '.model // empty' "$SM/offtier/.claude/settings.json" 2>/dev/null)" ]]; then
  ok "0185 served c: a planning phase served off its tier is recorded and leaves the model line out"
else
  bad "0185 served c: a planning phase served off its tier is recorded and leaves the model line out" "rc $SM_RC: $SM_OUT"
fi
sm_stamp empty 'planning_model=\nexecution_model='
if [[ "$SM_RC" -eq 0 ]] && ! jq -e 'has("models")' "$SM/empty/.claude/sdd.json" >/dev/null 2>&1 \
   && [[ -z "$(jq -r '.model // empty' "$SM/empty/.claude/settings.json" 2>/dev/null)" ]]; then
  ok "0185 served d: a probe that read nothing records no models block and no model line"
else
  bad "0185 served d: a probe that read nothing records no models block and no model line" "rc $SM_RC: $SM_OUT"
fi
sm_stamp legacy 'opusplan_verified=yes'
if [[ "$SM_RC" -eq 0 && "$SM_OUT" == *"NOTICE: the answers carry opusplan_verified"* ]] \
   && ! jq -e 'has("models")' "$SM/legacy/.claude/sdd.json" >/dev/null 2>&1 \
   && [[ "$(jq -r '.model // empty' "$SM/legacy/.claude/settings.json" 2>/dev/null)" == "opusplan" ]]; then
  ok "0185 served e: the legacy opusplan_verified is read for one release, with its notice, and records no models"
else
  bad "0185 served e: the legacy opusplan_verified is read for one release, with its notice, and records no models" "rc $SM_RC: $SM_OUT"
fi
sm_stamp badid 'planning_model=claude"opus\nexecution_model='
if [[ "$SM_RC" -ne 0 && "$SM_OUT" == *"planning_model is not a model id"* && ! -e "$SM/badid/.claude" ]]; then
  ok "0185 served f: an answer that is not a model id is refused by name before anything is written"
else
  bad "0185 served f: an answer that is not a model id is refused by name before anything is written" "rc $SM_RC: $SM_OUT"
fi

# g, h. The refresh measures nothing: an opusplan instance with no record is reported, the legacy answer named.
cp -R "$SM/legacy" "$SM/upg"
run_script bash "$SCRIPTS/refresh-instance.sh" "$SM/upg"
expect_script "0185 served g: the refresh reports an opusplan instance that records no served model" 0 \
  'records no served model ("models")' "records none it did not measure"
printf 'opusplan_verified=yes\n' > "$SM/upg/.claude/stamp-answers.txt"
run_script bash "$SCRIPTS/refresh-instance.sh" "$SM/upg"
expect_script "0185 served h: a kept answers file's legacy yes or no is named and not migrated" 0 \
  "carries opusplan_verified=yes, the legacy yes or no"
run_script bash "$SCRIPTS/refresh-instance.sh" "$SM/new"
if [[ "$SCRIPT_OUT" != *"records no served model"* ]]; then
  ok "0185 served i (control): an instance that records its served models draws no such line"
else
  bad "0185 served i (control): an instance that records its served models draws no such line" "$SCRIPT_OUT"
fi

# j. The two bootstrap skills write the new keys and no longer the boolean.
SM_BAD=""
for f in new retrofit; do
  grep -q '^planning_model=' "$ROOT/skills/$f/SKILL.md" || SM_BAD="$SM_BAD $f-no-planning_model"
  grep -q '^execution_model=' "$ROOT/skills/$f/SKILL.md" || SM_BAD="$SM_BAD $f-no-execution_model"
  grep -q '^opusplan_verified=' "$ROOT/skills/$f/SKILL.md" && SM_BAD="$SM_BAD $f-still-writes-the-boolean"
  grep -qF 'scripts/model-probe.sh' "$ROOT/skills/$f/SKILL.md" || SM_BAD="$SM_BAD $f-no-probe"
done
if [[ -z "$SM_BAD" ]]; then
  ok "0185 served j: /setlist:new and /setlist:retrofit run the probe and write planning_model and execution_model"
else
  bad "0185 served j: /setlist:new and /setlist:retrofit run the probe and write planning_model and execution_model" "$SM_BAD"
fi
fi; shard_region_end
# <<< SHARD-END served-model-0185


# =============================================================================
# THE VERSION FLOOR FOR THE STAMPED RULES (spec 0185, item 3; C-68 of the
# 2026-10-05 scan). Claude Code 2.1.289 fixed a deny or ask rule being skipped
# under sandbox auto-allow behind a variable-assignment prefix. The floor is said
# where the rules are read: the stamped _comment, the validate skill's version
# line, the README's floor sentence and Part 3. Pinned by substring at each site.
# =============================================================================
# >>> SHARD-BEGIN rules-floor-0185 cost=1
if shard_region rules-floor-0185; then
RF_BAD=""
RF_C="$(sed 's/^{{IF:OPUSPLAN}}//' "$ROOT/templates/claude/settings.json.tmpl" | jq -r '.permissions._comment' 2>/dev/null)"
grep -q 'below 2.1.289 read the ask rules in front of git reset --hard and rm -rf as advisory' <<< "$RF_C" || RF_BAD="$RF_BAD comment"
grep -q 'Below 2.1.289, report' "$ROOT/skills/validate/SKILL.md" || RF_BAD="$RF_BAD validate"
# The public README by its source name only since spec 0192 (public_readme, the prelude): in the
# export the README site prints SKIPPED by name and the other three sites are still read.
if public_readme "0185 floor a, the README site"; then
  grep -qF 'the stamped deny and ask rules hold under sandbox auto-allow from 2.1.289' "$PUBLIC_README" || RF_BAD="$RF_BAD readme"
fi
bash "$SCRIPTS/part.sh" 3 "$ROOT/setlist.md" 2>/dev/null | tr '\n' ' ' | grep -q 'below 2.1.289 the ask rules in front of' || RF_BAD="$RF_BAD part-3"
if [[ -z "$RF_BAD" ]]; then
  ok "0185 floor a: the 2.1.289 floor for the stamped rules is said at its four sites"
else
  bad "0185 floor a: the 2.1.289 floor for the stamped rules is said at its four sites" "missing at:$RF_BAD"
fi
# The note is still a key the harness tolerates: the template, its model line stripped, parses.
if sed 's/^{{IF:OPUSPLAN}}//' "$ROOT/templates/claude/settings.json.tmpl" | jq -e '.permissions.ask | length == 4' >/dev/null 2>&1; then
  ok "0185 floor b (control): the template still parses with its four ask rules"
else
  bad "0185 floor b (control): the template still parses with its four ask rules" "the template does not parse"
fi
fi; shard_region_end
# <<< SHARD-END rules-floor-0185


# =============================================================================
# THE CLOSE REVIEWER'S TOOL LIST (spec 0185, item 4; 0175's E-e; C-75). An
# allow-list in place of disallowedTools. Measured on 2.1.292 (logs
# ~/setlist-leg-logs/0185/reviewer-*): the agent reads the diff and reports a
# finding by file and line; it has no Write tool (asked to write, it could not);
# a Bash(git:*) qualifier did NOT stop `echo x > file` with every permission granted,
# so the line names plain Bash and the body carries the read-only Bash rule. The
# refresh replaces a 2.11.0 copy and keeps it as .setlist-backup (E-d).
# =============================================================================
# >>> SHARD-BEGIN reviewer-tools-0185 cost=1
if shard_region reviewer-tools-0185; then
RT="$WORK/reviewer-tools-0185"
rm -rf "$RT"; mkdir -p "$RT"
RT_TPL="$ROOT/templates/claude/agents/close-reviewer.md"
RT_FM="$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$RT_TPL")"
RT_BAD=""
grep -qx 'tools: Read, Grep, Glob, Bash' <<< "$RT_FM" || RT_BAD="$RT_BAD tools-line"
grep -q '^disallowedTools:' <<< "$RT_FM" && RT_BAD="$RT_BAD still-a-deny-line"
grep -qx 'model: opus' <<< "$RT_FM" || RT_BAD="$RT_BAD model"
grep -qF 'Never redirect output into a file or run a command that writes.' "$RT_TPL" || RT_BAD="$RT_BAD body-bash-rule"
if [[ -z "$RT_BAD" ]]; then
  ok "0185 reviewer a: the agent carries an allow-list without Write or Edit, and its body keeps Bash to reading"
else
  bad "0185 reviewer a: the agent carries an allow-list without Write or Edit, and its body keeps Bash to reading" "$RT_BAD"
fi
# b. An instance carrying the 2.11.0 reviewer (the disallowedTools line) gets this one, the old kept beside it.
instance_fixture "$RT/upg" 2.11.0
mkdir -p "$RT/upg/.claude/agents"
git -C "$ROOT" show 7104c55:templates/claude/agents/close-reviewer.md > "$RT/upg/.claude/agents/close-reviewer.md" 2>/dev/null \
  || printf -- '---\nname: close-reviewer\nmodel: opus\ndisallowedTools: Write, Edit\n---\n' > "$RT/upg/.claude/agents/close-reviewer.md"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$RT/upg"
if [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$RT_TPL" "$RT/upg/.claude/agents/close-reviewer.md" \
   && grep -qx 'disallowedTools: Write, Edit' "$RT/upg/.claude/agents/close-reviewer.md.setlist-backup" 2>/dev/null; then
  ok "0185 reviewer b: the refresh replaces a 2.11.0 reviewer with this one and keeps the old as .setlist-backup"
else
  bad "0185 reviewer b: the refresh replaces a 2.11.0 reviewer with this one and keeps the old as .setlist-backup" "rc $SCRIPT_RC: $SCRIPT_OUT"
fi
fi; shard_region_end
# <<< SHARD-END reviewer-tools-0185


# =============================================================================
# THE FAIL-CLOSED READING (spec 0185, item 5; C-70 of the 2026-10-05 scan). On
# Claude Code 2.1.287 and 2.1.292 a PreToolUse hook whose matcher is an invalid
# pattern did not run and the write went through (logs
# ~/setlist-leg-logs/0185/failclosed-*); no prompt produced an input the harness
# could not serialize, so that half is the 2.1.288 changelog's. The clauses sat in
# the BODY of "A timed-out hook is a skipped gate." on both layers until 2.13.0;
# spec 0194 retired that upstream condition into "The session layer persuades;
# its one deny is a nudge a crafted command passes.", whose history block keeps
# the measured skip and the 2.1.288 inverse verbatim and whose short form says a
# hook with an invalid matcher never runs. Both layers carry one copy of the
# merged title and none of the retired one.
# =============================================================================
# >>> SHARD-BEGIN failclosed-0185 cost=1
if shard_region failclosed-0185; then
FC_BAD=""
FC_T='- **The session layer persuades; its one deny is a nudge a crafted command passes.**'
# The full text by its source name here, by its exported name in the public repository (spec
# 0189 fix round 1, the 2.12.0 leg's F1); the README by its source name only since spec 0192
# (public_readme, the prelude), its half SKIPPED by name in the export.
FC_LD="$ROOT/publish/LIMITATIONS.md"; [[ -f "$FC_LD" ]] || FC_LD="$ROOT/LIMITATIONS.md"
FC_L="$(awk -v t="$FC_T" 'index($0, t) == 1 { on = 1 } on { print } on && /^<\/details>/ { exit }' "$FC_LD")"
[[ "$(grep -cF -- "$FC_T" "$FC_LD")" -eq 1 ]] || FC_BAD="$FC_BAD limitations-title"
grep -qF -- '- **A timed-out hook is a skipped gate.**' "$FC_LD" && FC_BAD="$FC_BAD limitations-retired-title-still-a-bullet"
if public_readme "0185 failclosed a, the README layer"; then
  FC_R="$(grep -F -- "$FC_T" "$PUBLIC_README")"
  [[ "$(grep -cF -- "$FC_T" "$PUBLIC_README")" -eq 1 ]] || FC_BAD="$FC_BAD readme-title"
  grep -qF -- '- **A timed-out hook is a skipped gate.**' "$PUBLIC_README" && FC_BAD="$FC_BAD readme-retired-title-still-a-bullet"
  grep -qF 'a hook whose matcher is not a valid pattern never runs' <<< "$FC_R" || FC_BAD="$FC_BAD readme-skip-clause"
fi
grep -qF 'a PreToolUse hook with the matcher `Write|(` did not run and the write went through' <<< "$FC_L" || FC_BAD="$FC_BAD limitations-skip-clause"
grep -qF 'The inverse case fails closed: since 2.1.288' <<< "$FC_L" || FC_BAD="$FC_BAD limitations-inverse-clause"
if [[ -z "$FC_BAD" ]]; then
  ok "0185 failclosed a: the measured skip and the 2.1.288 inverse stand in the merged session-layer bullet (2.13.0) on both layers, the retired title a bullet on neither"
else
  bad "0185 failclosed a: the measured skip and the 2.1.288 inverse stand in the merged session-layer bullet (2.13.0) on both layers, the retired title a bullet on neither" "$FC_BAD"
fi
fi; shard_region_end
# <<< SHARD-END failclosed-0185


# =============================================================================
# THE DELEGATED RUNG (spec 0194, item 2; the owner's ruling of 2026-10-08, R11).
# QA Pass 1 runs on the delegated tier: the stamped qa-verifier names `haiku`
# and a `medium` effort default; the close reviewer stays on `opus`, with the
# same default and the instruction to record the effort it was told (C-78). An
# upgraded instance receives the new qa-verifier through the refresh's report of
# changed bytes, the old copy kept as .setlist-backup; before 2.13.0 the refresh
# never delivered that agent at all, so an instance kept the one it was stamped with.
# =============================================================================
# >>> SHARD-BEGIN rung-0194 cost=1
if shard_region rung-0194; then
RG="$WORK/rung-0194"
rm -rf "$RG"; mkdir -p "$RG"
rg_fm() { awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on' "$1"; }
RG_BAD=""
RG_QA="$(rg_fm "$ROOT/templates/claude/agents/qa-verifier.md")"
RG_CR="$(rg_fm "$ROOT/templates/claude/agents/close-reviewer.md")"
grep -qx 'model: haiku' <<< "$RG_QA" || RG_BAD="$RG_BAD qa-model"
grep -qx 'effort: medium' <<< "$RG_QA" || RG_BAD="$RG_BAD qa-effort"
grep -qx 'model: opus' <<< "$RG_CR" || RG_BAD="$RG_BAD cr-model"
grep -qx 'effort: medium' <<< "$RG_CR" || RG_BAD="$RG_BAD cr-effort"
grep -qF 'the line `effort: <level>`' "$ROOT/templates/claude/agents/close-reviewer.md" || RG_BAD="$RG_BAD cr-effort-line"
if [[ -z "$RG_BAD" ]]; then
  ok "0194 rung a: qa-verifier on haiku at medium, the close reviewer on opus at medium and told to record the effort it ran at"
else
  bad "0194 rung a: qa-verifier on haiku at medium, the close reviewer on opus at medium and told to record the effort it ran at" "$RG_BAD"
fi
# b. An instance carrying the qa-verifier stamped before 2.13.0 (no model line) gets this one, the old kept beside it.
instance_fixture "$RG/upg" 2.12.0
mkdir -p "$RG/upg/.claude/agents"
printf -- '---\nname: qa-verifier\ndescription: QA Pass 1 verifier.\ndisallowedTools: Write, Edit\n---\n\nThe 2.12.0 body.\n' > "$RG/upg/.claude/agents/qa-verifier.md"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$RG/upg"
if [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$ROOT/templates/claude/agents/qa-verifier.md" "$RG/upg/.claude/agents/qa-verifier.md" \
   && grep -qx 'The 2.12.0 body.' "$RG/upg/.claude/agents/qa-verifier.md.setlist-backup" 2>/dev/null; then
  ok "0194 rung b: the refresh replaces a qa-verifier stamped before 2.13.0 with this one and keeps the old as .setlist-backup"
else
  bad "0194 rung b: the refresh replaces a qa-verifier stamped before 2.13.0 with this one and keeps the old as .setlist-backup" "rc $SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tail -n 5)"
fi
# c. The spec reader (spec 0194, item 4) reaches an instance stamped before it existed, through the same arm.
if [[ -f "$RG/upg/.claude/agents/spec-reader.md" ]] && cmp -s "$ROOT/templates/claude/agents/spec-reader.md" "$RG/upg/.claude/agents/spec-reader.md"; then
  ok "0194 rung c: the refresh stamps the spec-reader agent where an instance has none"
else
  bad "0194 rung c: the refresh stamps the spec-reader agent where an instance has none" "$(ls "$RG/upg/.claude/agents" 2>&1 | tr '\n' ' ')"
fi
fi; shard_region_end
# <<< SHARD-END rung-0194


# =============================================================================
# THE BYPASS DENY BLOCKS ON FAILURE (spec 0194, item 3; C-77, R7.1). Measured
# 2026-10-14 in a scratch instance: at Claude Code 2.1.299 a PreToolUse Bash hook
# that timed out, or could not start, let the call through without the key and
# blocked it with `"onFailure": "block"` ("timed out; blocking because onFailure
# is "block""); at 2.1.292 the key was ignored, the hook still ran (its deny
# held) and a permission rule in the same file held. So the stamped bypass deny
# carries the key and the scope and Stop entries do not (a, read from the
# template as JSON, its markers deleted); an instance whose entry lacks it is
# told the one edit by the refresh, and an instance that has it is told nothing
# (b, c); the edit it prints adds the key and keeps the rest of the file (d).
# =============================================================================
# >>> SHARD-BEGIN onfailure-0194 cost=1
if shard_region onfailure-0194; then
OF="$WORK/onfailure-0194"
rm -rf "$OF"; mkdir -p "$OF"
OF_T="$(sed -e 's/{{IF:[A-Z_]*}}//g' "$ROOT/templates/claude/settings.json.tmpl")"
OF_BAD=""
of_entry() { jq -r --arg h "$1" '[(.hooks[]?[]? | .hooks[]?) | select((.command // "") | contains($h)) | (.onFailure // "none")] | join(",")' <<< "$OF_T" 2>/dev/null; }
[[ "$(of_entry bypass-deny.sh)" == "block" ]] || OF_BAD="$OF_BAD bypass-deny=$(of_entry bypass-deny.sh)"
[[ "$(of_entry scope-hook.sh)" == "none" ]] || OF_BAD="$OF_BAD scope=$(of_entry scope-hook.sh)"
[[ "$(of_entry stop-hook.sh)" == "none" ]] || OF_BAD="$OF_BAD stop=$(of_entry stop-hook.sh)"
if [[ -z "$OF_BAD" ]]; then
  ok "0194 onfailure a: the stamped bypass deny blocks on failure, the scope hook and the Stop hook do not"
else
  bad "0194 onfailure a: the stamped bypass deny blocks on failure, the scope hook and the Stop hook do not" "$OF_BAD"
fi
instance_fixture "$OF/old" 2.12.0
run_script bash "$SCRIPTS/refresh-instance.sh" "$OF/old"
OF_EDIT="$(printf '%s\n' "$SCRIPT_OUT" | sed -n 's/^    jq //p' | grep 'onFailure' | head -n 1)"
if [[ "$SCRIPT_OUT" == *"the bypass deny's entry carries no \"onFailure\": \"block\""* && -n "$OF_EDIT" ]]; then
  ok "0194 onfailure b: an instance whose bypass deny entry lacks the key is told the one edit"
else
  bad "0194 onfailure b: an instance whose bypass deny entry lacks the key is told the one edit" "rc $SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | tail -n 4)"
fi
OF_PROG="$(printf '%s\n' "$SCRIPT_OUT" | sed -n "s/^    jq '\\(.*onFailure.*\\)' \\.claude.*/\\1/p" | head -n 1)"
if [[ -n "$OF_PROG" ]] && jq "$OF_PROG" "$OF/old/.claude/settings.json" > "$OF/new.json" 2>/dev/null \
   && [[ "$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.command | contains("bypass-deny.sh")) | .onFailure] | join(",")' "$OF/new.json")" == "block" ]] \
   && [[ "$(jq -c 'del(.hooks.PreToolUse[].hooks[].onFailure)' "$OF/new.json")" == "$(jq -c . "$OF/old/.claude/settings.json")" ]]; then
  ok "0194 onfailure d: the printed edit adds the key to the bypass deny's entry and leaves the rest of the file as it was"
else
  bad "0194 onfailure d: the printed edit adds the key to the bypass deny's entry and leaves the rest of the file as it was" "program '${OF_PROG:-<none read>}'"
fi
cp "$OF/new.json" "$OF/old/.claude/settings.json" 2>/dev/null
run_script bash "$SCRIPTS/refresh-instance.sh" "$OF/old"
if [[ -s "$OF/new.json" && "$SCRIPT_OUT" != *"carries no \"onFailure\""* ]]; then
  ok "0194 onfailure c: an instance whose bypass deny entry has the key is told nothing about it"
else
  bad "0194 onfailure c: an instance whose bypass deny entry has the key is told nothing about it" "$(printf '%s' "$SCRIPT_OUT" | grep onFailure | head -n 2)"
fi
fi; shard_region_end
# <<< SHARD-END onfailure-0194


# =============================================================================
# THE DECLARED COMMAND RUNS AS WRITTEN (spec 0196, fix round 1, the 2.13.0 leg's F2).
# The readers of gate_command, the gates tiers and diagram_command printed the jq
# value through `sed 's/^ //'` to drop the "ok " marker, and sed strips a leading
# space from EVERY line, so a multi-line command (an indented heredoc body, a
# `python -c` block) ran changed and the hook disagreed with the verify skill, which
# reads the same declaration without sed. The marker is now stripped from the whole
# string once. (a) an indented heredoc gate runs green, as `bash -c` of the same
# string does; (b) the command the reader prints is the declared string byte for
# byte; (c) the diagram reader the same; (d) the control: a one-line command reads
# as before.
# =============================================================================
# >>> SHARD-BEGIN gate-command-0196 cost=1
if shard_region gate-command-0196; then
GK="$WORK/gate-command-0196"; rm -rf "$GK"; mkdir -p "$GK/.claude"
GK_CMD=$'cat <<E | grep -q "^ x"\n x\nE'
jq -n --arg c "$GK_CMD" '{scaffolded: true, gate_command: $c, diagram_command: $c}' > "$GK/.claude/sdd.json"
GK_DIRECT="$(bash -c "$GK_CMD" >/dev/null 2>&1; printf '%s' "$?")"
GK_OUT="$(SLH_REFUSED=0; . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_run_gate_command "$GK" close 2>&1; printf '|rc=%s' "$?")" # fail-open-ok: sourcing noise is discarded; the rc suffix is what the test reads
if [[ "$GK_DIRECT" == "0" && "$GK_OUT" == *"|rc=0" && "$GK_OUT" != *SLH-GATE-COMMAND-FAILED* ]]; then
  ok "0196 gate a: a gate command with an indented heredoc body runs green, as bash -c of the same string does"
else
  bad "0196 gate a: a gate command with an indented heredoc body runs green, as bash -c of the same string does" "direct rc $GK_DIRECT; hook: $(printf '%s' "$GK_OUT" | tail -n 3)"
fi
GK_READ="$( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_gate_command_for "$GK" close; printf '|' )"
if [[ "${GK_READ%|}" == "$GK_CMD" ]]; then
  ok "0196 gate b: the gate command the reader prints is the declared string, every line's leading space kept"
else
  bad "0196 gate b: the gate command the reader prints is the declared string, every line's leading space kept" "read: $(printf '%q' "${GK_READ%|}")"
fi
GK_DREAD="$( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_diagram_command_for "$GK"; printf '|' )"
if [[ "${GK_DREAD%|}" == "$GK_CMD" ]]; then
  ok "0196 gate c: the diagram command the reader prints is the declared string"
else
  bad "0196 gate c: the diagram command the reader prints is the declared string" "read: $(printf '%q' "${GK_DREAD%|}")"
fi
jq -n '{scaffolded: true, gate_command: "true"}' > "$GK/.claude/sdd.json"
GK_ONE="$( . "$ROOT/templates/git-hooks/setlist-hook-lib.sh" >/dev/null 2>&1; slh_gate_command_for "$GK" close; printf '|' )"
if [[ "${GK_ONE%|}" == "true" ]]; then
  ok "0196 gate d: a one-line gate command reads as it always did"
else
  bad "0196 gate d: a one-line gate command reads as it always did" "read: $(printf '%q' "${GK_ONE%|}")"
fi
fi; shard_region_end
# <<< SHARD-END gate-command-0196


# =============================================================================
# THE onFailure REPORT READS THE STAMPED ENTRY, AND ITS EDIT TOUCHES ONLY IT (spec 0196,
# fix round 1, the 2.13.0 leg's F4, F10 and F17). The report and its printed edit chose
# entries by the substring "bypass-deny.sh" and asked whether ALL of them lacked the key,
# so a project's own hook of that name gained "onFailure": "block" from the edit (F4), and
# one carrying the key silenced the report while the stamped one lacked it (F10, F17).
# Now the stamped entry is the one the wiring check certifies (ours_spellings), the report
# fires when any stamped entry lacks the key, the edit addresses that entry by position,
# and a settings file whose PreToolUse cannot be read is named rather than passed over.
# =============================================================================
# >>> SHARD-BEGIN onfailure-0196 cost=1
if shard_region onfailure-0196; then
OG="$WORK/onfailure-0196"; rm -rf "$OG"; mkdir -p "$OG"
OG_FOREIGN='{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/audit-bypass-deny.sh.mine --log"}]}'
og_prog() { printf '%s\n' "$1" | sed -n "s/^    jq '\\(.*onFailure.*\\)' \\.claude.*/\\1/p" | head -n 1; }
og_entries() { jq -r '[.hooks.PreToolUse[]?.hooks[]? | "\(.command)=\(.onFailure // "none")"] | join(" ")' "$1" 2>/dev/null; }
# (a) F4: the stamped entry lacks the key, a foreign hook's command contains the substring.
instance_fixture "$OG/a" 2.12.0
jq --argjson f "$OG_FOREIGN" '.hooks.PreToolUse += [$f]' "$OG/a/.claude/settings.json" > "$OG/a.json" && mv "$OG/a.json" "$OG/a/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$OG/a"
OG_P="$(og_prog "$SCRIPT_OUT")"
if [[ -n "$OG_P" ]] && jq "$OG_P" "$OG/a/.claude/settings.json" > "$OG/a-new.json" 2>/dev/null \
   && [[ "$(og_entries "$OG/a-new.json")" == *'bypass-deny.sh=block'* && "$(og_entries "$OG/a-new.json")" == *'audit-bypass-deny.sh.mine --log=none'* ]]; then
  ok "0196 onfailure a: the printed edit gives the stamped bypass deny the key and leaves a foreign hook of that name as it was"
else
  bad "0196 onfailure a: the printed edit gives the stamped bypass deny the key and leaves a foreign hook of that name as it was" "program '${OG_P:-<none>}'; after: $(og_entries "$OG/a-new.json")"
fi
# (b) F10, F17: the foreign entry carries the key, the stamped one does not.
instance_fixture "$OG/b" 2.12.0
jq --argjson f "$OG_FOREIGN" '.hooks.PreToolUse += [$f | .hooks[0].onFailure = "block"]' "$OG/b/.claude/settings.json" > "$OG/b.json" && mv "$OG/b.json" "$OG/b/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$OG/b"
if [[ "$SCRIPT_OUT" == *"the bypass deny's entry carries no \"onFailure\": \"block\""* ]]; then
  ok "0196 onfailure b: a foreign entry carrying the key does not silence the report while the stamped one lacks it"
else
  bad "0196 onfailure b: a foreign entry carrying the key does not silence the report while the stamped one lacks it" "$(printf '%s' "$SCRIPT_OUT" | grep -i onfailure | head -n 2)"
fi
# (c) the control: the stamped entry carries the key, a foreign one does not; no report.
jq '(.hooks.PreToolUse[]?.hooks[]? | select(.command == "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/bypass-deny.sh")) += {"onFailure": "block"} | (.hooks.PreToolUse[]?.hooks[]? | select(.command | startswith("/usr/local"))) |= del(.onFailure)' "$OG/b/.claude/settings.json" > "$OG/c.json" && mv "$OG/c.json" "$OG/b/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$OG/b"
if [[ "$(og_entries "$OG/b/.claude/settings.json")" == *'bypass-deny.sh=block'* && "$SCRIPT_OUT" != *'carries no "onFailure"'* && "$SCRIPT_OUT" != *'could not be read for the bypass deny'* ]]; then
  ok "0196 onfailure c: a stamped entry carrying the key is reported as nothing, whatever a foreign entry carries"
else
  bad "0196 onfailure c: a stamped entry carrying the key is reported as nothing, whatever a foreign entry carries" "keys: $(og_entries "$OG/b/.claude/settings.json"); $(printf '%s' "$SCRIPT_OUT" | grep -i onfailure | head -n 2)"
fi
# (d) F17: a PreToolUse that is not a list is named, never passed over in silence.
instance_fixture "$OG/d" 2.12.0
jq '.hooks.PreToolUse = "not a list"' "$OG/d/.claude/settings.json" > "$OG/d.json" && mv "$OG/d.json" "$OG/d/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" "$OG/d"
if [[ "$SCRIPT_OUT" == *'could not be read for the bypass deny'* ]]; then
  ok "0196 onfailure d: a settings file whose PreToolUse is not a list is named in the onFailure report"
else
  bad "0196 onfailure d: a settings file whose PreToolUse is not a list is named in the onFailure report" "$(printf '%s' "$SCRIPT_OUT" | grep -iE 'onfailure|PreToolUse' | head -n 3)"
fi
fi; shard_region_end
# <<< SHARD-END onfailure-0196


# =============================================================================
# TWO SHIPPED SENTENCES THE COLD RUN OF 2.13.0 FOUND WRONG (spec 0196, fix round 1, the
# cold run's M-2 and M-3). (a) M-3: the scaffold template said that arming the scope hook
# makes feature code on the trunk "blocked"; the scope hook is advisory (it warns and lets
# the write proceed, since 2.11.0 answering no permission prompt), and the session repeated
# it to the human. (b) M-2: session zero filled the CODEOWNERS `@OWNER` slot with the plugin
# author's handle, inferred from the plugin manifest; the skill named no source for the slot.
# Both are words an agent reads, so the cases assert the words; what the agent then does is
# observed at the cold round and recorded there (the R9.1 shape).
# =============================================================================
# >>> SHARD-BEGIN wording-0196 cost=1
if shard_region wording-0196; then
WD_SC="$ROOT/templates/claude/skills/scaffold/SKILL.md.tmpl"
if grep -A3 'This arms the scope hook' "$WD_SC" | grep -qiE 'is blocked|blocks' ; then
  bad "0196 wording a: the scaffold template calls the advisory scope hook a block" "$(grep -A3 'This arms the scope hook' "$WD_SC" | tr '\n' ' ' | cut -c1-200)"
elif grep -A4 'This arms the scope hook' "$WD_SC" | grep -qi 'warns' && grep -A5 'This arms the scope hook' "$WD_SC" | grep -qi 'git hooks'; then
  ok "0196 wording a: the scaffold template says the scope hook warns and the git hooks refuse"
else
  bad "0196 wording a: the scaffold template says the scope hook warns and the git hooks refuse" "$(grep -A4 'This arms the scope hook' "$WD_SC" | tr '\n' ' ' | cut -c1-200)"
fi
WD_NEW="$ROOT/skills/new/SKILL.md"
if grep -A4 '@OWNER' "$WD_NEW" | tr '\n' ' ' | grep -q 'never inferred from the plugin'; then
  ok "0196 wording b: the new skill names the CODEOWNERS slot's source and forbids inferring it from the plugin"
else
  bad "0196 wording b: the new skill names the CODEOWNERS slot's source and forbids inferring it from the plugin" "$(grep -A4 '@OWNER' "$WD_NEW" | tr '\n' ' ' | cut -c1-220)"
fi
fi; shard_region_end
# <<< SHARD-END wording-0196
