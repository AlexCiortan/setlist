#!/usr/bin/env bash
# test/suite/02-plugin-version-and-refresh.sh: shard 2 of the hook test suite, SOURCED by test/run-tests.sh
# in this order (spec 0133, the file-order split of the one-file suite). Not a
# program of its own: every helper it calls is defined in the driver or in an
# earlier shard, and the driver's verdict, TMPDIR and exit trap are its own.

# =============================================================================
# Plugin version, refresh direction, and session skew (plugin 1.0.2, item 21)
#
# The failure this whole section exists for: a refresh that compares bytes
# without direction can reinstall older enforcement files over newer ones and
# report success. Every refusal below is asserted to have refused AND to have
# left the instance's bytes alone, because a refusal that copied anyway is the
# same defect wearing a warning label.
# =============================================================================

SCRIPTS="$ROOT/scripts"
SCRIPT_OUT=""
SCRIPT_RC=0

run_script() { # run_script <cmd> [args...]
  SCRIPT_OUT="$("$@" 2>&1)"
  SCRIPT_RC=$?
}

run_script_nojq() { # run_script_nojq <cmd> [args...]
  SCRIPT_OUT="$(PATH="$NOJQ_BIN" "$@" 2>&1)"
  SCRIPT_RC=$?
}

expect_script() { # expect_script <name> <want-rc> [substring...]
  local name="$1" want="$2" s
  shift 2
  if [[ "$SCRIPT_RC" -ne "$want" ]]; then
    bad "$name" "expected rc $want, got $SCRIPT_RC. Output: ${SCRIPT_OUT:-<empty>}"
    return
  fi
  for s in "$@"; do
    case "$SCRIPT_OUT" in
      *"$s"*) ;;
      *) bad "$name" "output does not mention '$s': ${SCRIPT_OUT:-<empty>}"; return ;;
    esac
  done
  ok "$name"
}

assert_true() { # assert_true <name> <message-if-false> <cmd> [args...]
  local name="$1" msg="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "$msg"; fi
}

PLUGIN_VERSION="$(bash "$SCRIPTS/plugin-version.sh" "$ROOT" 2>/dev/null || true)"
if [[ -n "$PLUGIN_VERSION" ]]; then
  ok "version 0: this plugin tree declares a readable version ($PLUGIN_VERSION)"
else
  bad "version 0: this plugin tree declares a readable version" \
      "plugin-version.sh could not read one, so every case in this section would be comparing against nothing"
fi

# The ordering is the whole point of the file; a comparison that answers "same"
# for everything would let every case below pass while proving nothing.
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.2 1.0.1
expect_script "version a: 1.0.2 is newer than 1.0.1" 0 "newer"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.1 1.0.2
expect_script "version b: 1.0.1 is older than 1.0.2" 0 "older"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.0.1 1.0.1
expect_script "version c: equal versions compare same" 0 "same"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 1.2.0 1.10.0
expect_script "version d: components compare numerically, not as text" 0 "older"
run_script bash "$SCRIPTS/plugin-version.sh" --compare "" 1.0.1
expect_script "version e: an unreadable version refuses rather than guessing" 1 "not a version"
# The 2.6.0 leg's F14 (fix round 1, 2026-09-08), watched RED on the candidate
# 2217acea: a leading zero read as OCTAL by [[ -gt ]] printed two arithmetic
# errors and then "same" at exit 0, standing the downgrade guard down.
run_script bash "$SCRIPTS/plugin-version.sh" --compare 2.6.0 2.08.0
expect_script "version f: a leading zero compares in base 10 (2.08.0 is 2.8.0, newer than 2.6.0), never 'same'" 0 "older"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 2.08.0 2.6.0
expect_script "version g: the same pair the other way is newer" 0 "newer"
run_script bash "$SCRIPTS/plugin-version.sh" --compare 2.08.0 2.8.0
expect_script "version h: 2.08.0 and 2.8.0 are the same version" 0 "same"

# --- the stamp records the stamping version ------------------------------------

STAMP_RECORDED="$(jq -r '.plugin.version // empty' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null || true)"
if [[ "$STAMP_RECORDED" == "$PLUGIN_VERSION" && -n "$PLUGIN_VERSION" ]]; then
  ok "stamp version: the stamped instance records the stamping plugin version ($STAMP_RECORDED)"
else
  bad "stamp version: the stamped instance records the stamping plugin version" \
      "sdd.json records '${STAMP_RECORDED:-<none>}', the manifest declares '${PLUGIN_VERSION:-<none>}'"
fi
if [[ "$STAMP_RECORDED" != *"{{"* ]]; then
  ok "stamp version 2: the recorded version is a real value, not an unsubstituted placeholder"
else
  bad "stamp version 2: the recorded version is a real value, not an unsubstituted placeholder" \
      "sdd.json still carries the template placeholder: $STAMP_RECORDED"
fi

# --- the release block (D1, edition v1.7) ---------------------------------------
#
# The block is a DECLARATION, so what the suite pins is that the stamp ships the
# documented default and that the default is the one the skills are written
# against. An instance stamped with a different default would make checkpoint's
# "an absent block reads as none" rule and validate's check 13 disagree with the
# tree they run on.
STAMP_RELEASE="$(jq -r '.release.model // empty' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null || true)"
if [[ "$STAMP_RELEASE" == "none" ]]; then
  ok "release block: a stamped instance declares the documented default (model: none)"
else
  bad "release block: a stamped instance declares the documented default (model: none)" \
      "sdd.json records release.model '${STAMP_RELEASE:-<absent>}'"
fi
# Ordering, per the sdd.json shape contract in STAMP-TREE.md: framework blocks
# APPEND after the flat repo facts rather than reordering them, so an instance's
# file grows by addition and every reader can keep treating an absent block as
# "stamped before that block existed".
if jq -e 'keys_unsorted | index("release") > index("plugin")' "$STAMP_TARGET/.claude/sdd.json" >/dev/null 2>&1; then
  ok "release block: it appends after the plugin block rather than reordering the file"
else
  bad "release block: it appends after the plugin block rather than reordering the file" \
      "key order is $(jq -c 'keys_unsorted' "$STAMP_TARGET/.claude/sdd.json" 2>/dev/null)"
fi
# The three models the edition names, read from the edition rather than retyped,
# so a model added to Part 6 and not to this list fails here.
for rel_model in none tags version-file; do
  if bash "$SCRIPTS/part.sh" 6 "$ROOT/setlist.md" 2>/dev/null | grep -qF -- "\`$rel_model\`"; then
    ok "release block: Part 6 documents the '$rel_model' model"
  else
    bad "release block: Part 6 documents the '$rel_model' model" "the release rail section does not name it"
  fi
done

# --- refresh fixtures -----------------------------------------------------------

# A minimal instance: the four stamped hooks plus sdd.json. close-gate.sh
# carries a marker line, so "did the refresh copy anything?" is decidable by
# looking rather than by trusting the exit code.
MARKER="# instance marker, must survive every refusal"
instance_fixture() { # instance_fixture <dir> <recorded-version|none|broken> [wiring]
  # wiring: current (default) | stale-matcher | no-timeouts | missing
  local d="$1" rec="$2" wiring="${3:-current}" h
  rm -rf "$d"
  mkdir -p "$d/.claude/hooks"
  for h in scope-hook commit-gate close-gate regrounding-hook stop-hook; do
    cp "$HOOKS/$h.sh" "$d/.claude/hooks/$h.sh"
  done
  printf '%s\n' "$MARKER" >> "$d/.claude/hooks/close-gate.sh"
  case "$rec" in
    broken) printf '{ "trunk": "main", \n' > "$d/.claude/sdd.json" ;;
    none)   printf '{ "trunk": "main", "gate_command": "", "scaffolded": false }\n' > "$d/.claude/sdd.json" ;;
    *)      printf '{ "trunk": "main", "gate_command": "", "scaffolded": false, "plugin": { "version": "%s" } }\n' \
              "$rec" > "$d/.claude/sdd.json" ;;
  esac
  # The settings wiring is the OTHER half of the enforcement layer, and the
  # refresh checks it without rewriting it (1.0.3). Fixtures default to the
  # current wiring so the direction cases below stay about direction.
  local matcher='Write|Edit|MultiEdit|NotebookEdit' t1='"timeout": 120,' t2='"timeout": 300,' t3='"timeout": 300,' t4='"timeout": 60,' t5='"timeout": 60,'
  local gates_block=1
  case "$wiring" in
    stale-matcher) matcher='Write|Edit' ;;
    no-timeouts)   t1='' ; t2='' ; t3='' ; t4='' ; t5='' ;;
    missing)       return 0 ;;
    no-gates)      gates_block=0 ;;
  esac
  # The command paths must be the REAL ones. The wiring check identifies this
  # plugin's own hook entries by their command pointing into .claude/hooks/,
  # so a fixture using a made-up path is not an instance: it is a settings file
  # with no Setlist hooks in it, and every check would vacuously pass. Found by
  # the 1.0.4 rewrite, and it is the same lesson the upgrade-seam leg exists
  # for: a fixture is only evidence to the extent it matches the real artifact.
  #
  # ALL FOUR hooks are wired, including the SessionStart re-grounding hook. Until
  # 1.0.7 this fixture wired three and omitted SessionStart, so it was not an
  # instance: it was an instance with a hook permanently disarmed, and every case
  # built on it asserted against a shape no scaffold produces. It went unnoticed
  # because nothing yet checked that a stamped hook was wired AT ALL, which is
  # the same blind spot as the defect (B5) that made this check necessary. The
  # fixture and the checker were incomplete in exactly the same place.
  local gates=''
  if [[ "$gates_block" -eq 1 ]]; then
    gates=",
      { \"matcher\": \"Bash\",
        \"hooks\": [ { \"type\": \"command\", $t2 \"command\": \"\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/commit-gate.sh\" },
                   { \"type\": \"command\", $t3 \"command\": \"\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/close-gate.sh\" } ] }"
  fi
  cat > "$d/.claude/settings.json" <<SETTINGS
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "$matcher",
        "hooks": [ { "type": "command", $t1 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/scope-hook.sh" } ] }$gates
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", $t4 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/regrounding-hook.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", $t5 "command": "\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-hook.sh" } ] }
    ]
  }
}
SETTINGS
  jq -e . "$d/.claude/settings.json" >/dev/null 2>&1 || {
    printf 'instance_fixture: produced settings.json that does not parse (wiring=%s)\n' "$wiring" >&2
    return 1
  }
}

marker_intact() { # marker_intact <dir>
  grep -q "^$MARKER\$" "$1/.claude/hooks/close-gate.sh"
}

# --- refusal: a backwards move --------------------------------------------------

INST="$WORK/inst-downgrade"
instance_fixture "$INST" 9.9.9
assert_true "refresh down0: the fixture really records a version newer than this plugin" \
  "the fixture does not record 9.9.9, so the downgrade case below is not a downgrade" \
  test "$(jq -r '.plugin.version' "$INST/.claude/sdd.json")" = "9.9.9"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh down: a backwards refresh is refused and names both versions" 1 \
  "BACKWARDS" "9.9.9" "$PLUGIN_VERSION"
assert_true "refresh down2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker, so the refusal overwrote the file it refused to touch" \
  marker_intact "$INST"

# F4 OF THE SECOND 2.7.0 LEG, fix round 2: ABSENT AND UNREADABLE ARE DIFFERENT.
# The guard read .plugin.version directly, so a .plugin that was present but not an
# object made jq exit nonzero, the substitution captured empty stdout, and empty was
# read as "stamped before the version was recorded". The instance above records a
# NEWER plugin; with the field malformed the same instance was refreshed FORWARD,
# older enforcement files written over newer ones, and report mode printed "forward"
# to the one person who could have caught it. The guard exists to make that
# impossible and it failed open, so both directions are pinned here.
INST="$WORK/inst-plugin-not-object"
instance_fixture "$INST" 9.9.9
python3 - "$INST/.claude/sdd.json" <<'PY' 2>/dev/null ||   sed -i.bak 's/"plugin": *{[^}]*}/"plugin": "9.9.9"/' "$INST/.claude/sdd.json"
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["plugin"]="9.9.9"; json.dump(d,open(p,"w"))
PY
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh notobj: a .plugin that is not an object REFUSES rather than reading as unrecorded" 1 \
  "not an object"
assert_true "refresh notobj2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker, so the refusal overwrote the file it refused to touch" \
  marker_intact "$INST"

# --- the refresh DELIVERS the git-hook boundary (v1.7 dogfood BLOCKER) ----------
#
# Found by the Phase 5 dogfood gate, and it is plugin 1.0.3's defect restated:
# refresh-instance.sh copied what it knew about (the four PreToolUse hooks),
# reported the instance current, recorded plugin 1.1.0, and delivered NO
# .githooks/, NO core.hooksPath and NO merge.ff. So a freshly stamped instance
# had the v1.7 boundary and an UPGRADED one did not, while both claimed the same
# version.
#
# It was worse than 1.0.3's version. v1.7 also DEMOTES the PreToolUse layer to
# advisory and reclassifies its bypasses from BLOCKER to MAJOR, so an upgraded
# instance would have been strictly WEAKER after the upgrade than before it,
# and told it was current.
INST="$WORK/inst-boundary"
instance_fixture "$INST" 1.0.9
# A real instance is a git work tree, and the two config settings can only exist
# in one. The shared fixture is not git-initialised, so this case initialises it
# rather than changing a fixture the other refresh cases depend on.
git_init "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
for gh in pre-commit pre-merge-commit pre-push setlist-hook-lib.sh; do
  if [[ -f "$INST/.githooks/$gh" ]] && cmp -s "$ROOT/templates/git-hooks/$gh" "$INST/.githooks/$gh"; then
    ok "refresh boundary: .githooks/$gh is delivered byte-identical to the template"
  else
    bad "refresh boundary: .githooks/$gh is delivered byte-identical to the template" \
        "an upgraded instance does not carry the file the edition calls the guarantee"
  fi
done
for gh in pre-commit pre-merge-commit pre-push; do
  if [[ -x "$INST/.githooks/$gh" ]]; then
    ok "refresh boundary: .githooks/$gh is executable"
  else
    bad "refresh boundary: .githooks/$gh is executable" "git skips a non-executable hook SILENTLY, so this is a boundary that stops nothing and says nothing"
  fi
done
# THE HOOK'S OWN TOOL MUST BE DELIVERED WITH IT (v1.7 gate session 4, leg F2).
#
# pre-push resolves trunk-audit.sh from $CLAUDE_PLUGIN_ROOT/scripts/ or from
# .claude/hooks/trunk-audit.sh. Neither the stamp nor the refresh had ever
# installed the second, and the first is unset in any ordinary terminal, so a
# stamped instance refused every push from outside a Claude Code session with
# "cannot find trunk-audit.sh". Delivering a hook without the tool it runs is
# delivering a boundary that only fails.
if [[ -f "$INST/.claude/hooks/trunk-audit.sh" ]]; then
  ok "refresh boundary: trunk-audit.sh is delivered where pre-push looks for it"
else
  bad "refresh boundary: trunk-audit.sh is delivered where pre-push looks for it" \
      "pre-push falls back to .claude/hooks/trunk-audit.sh when CLAUDE_PLUGIN_ROOT is unset, which is every ordinary terminal, and it is not there"
fi

if [[ "$(git -C "$INST" config --get core.hooksPath 2>/dev/null || true)" == ".githooks" ]]; then
  ok "refresh boundary: core.hooksPath points at the tracked directory"
else
  bad "refresh boundary: core.hooksPath points at the tracked directory" \
      "without it git runs .git/hooks and every delivered file above is inert"
fi
if [[ "$(git -C "$INST" config --get merge.ff 2>/dev/null || true)" == "false" ]]; then
  ok "refresh boundary: merge.ff is false after the refresh"
else
  bad "refresh boundary: merge.ff is false after the refresh" \
      "a fast-forward merge fires NO git hook, so without this the boundary has a hole the size of one flag"
fi

# --- refusal: a DELIVERY that could not deliver (F1, verdict leg) ---------------
#
# refresh-instance.sh --apply read neither `git config` write's exit status, so
# an instance whose config write failed still got "delivered the git-hook
# boundary" on stdout, had the new plugin version recorded, and exited 0 with
# core.hooksPath unset and therefore every git hook inert. A positive claim of
# delivery that was never checked is worse than a silent failure: nothing tells
# the operator to look again.
#
# The lock file is how a config write is made to fail without root or a
# read-only filesystem: git takes .git/config.lock before writing and refuses if
# it already exists.
INST="$WORK/inst-cfgfail"
instance_fixture "$INST" 1.0.0
# instance_fixture does NOT create a git repository, and refresh-instance.sh
# only reaches its config writes inside a work tree. Without this the lock file
# below cannot be created and the healthy control never sets core.hooksPath
# either, so every assertion here would report the same result on both trees and
# discriminate nothing. Caught by watching these fail red on BOTH sides.
git_init "$INST"
: > "$INST/.git/config.lock"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh cfgfail: a failed config write refuses instead of claiming delivery" 1 "FAILED"
if printf '%s' "$SCRIPT_OUT" | grep -q "delivered the git-hook boundary"; then
  bad "refresh cfgfail2: a failed delivery does NOT claim it delivered the boundary" \
      "the summary announced the git-hook boundary delivered while core.hooksPath was never set"
else
  ok "refresh cfgfail2: a failed delivery does NOT claim it delivered the boundary"
fi
REFRESH_REC="$(jq -r '.plugin.version // "none"' "$INST/.claude/sdd.json" 2>/dev/null)" # fail-open-ok: an unreadable file yields "none", which fails the comparison below, and that is the correct answer for an instance whose sdd.json did not survive
if [[ "$REFRESH_REC" == "1.0.0" ]]; then
  ok "refresh cfgfail3: the version is NOT recorded when the boundary was not delivered"
else
  bad "refresh cfgfail3: the version is NOT recorded when the boundary was not delivered" \
      "sdd.json records [$REFRESH_REC]; an instance must never claim a version whose boundary it does not carry"
fi

# THE CONTROL. Without it every assertion above is satisfied by a script that
# refuses every refresh, which is the false-denial direction.
INST="$WORK/inst-cfgok"
instance_fixture "$INST" 1.0.0
git_init "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
REFRESH_HP="$(git -C "$INST" config --get core.hooksPath 2>/dev/null || printf unset)" # fail-open-ok: an unset value is printed as "unset" and fails the test below, which is the finding rather than a skipped check
if [[ "$REFRESH_HP" == ".githooks" ]]; then
  ok "refresh cfgok: the healthy path still delivers the boundary"
else
  bad "refresh cfgok: the healthy path still delivers the boundary" \
      "core.hooksPath reads [$REFRESH_HP], so the refusal above is not discriminating"
fi

# --- refusal: an undeterminable recorded version --------------------------------

INST="$WORK/inst-unreadable"
instance_fixture "$INST" "banana"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh unreadable: an unreadable recorded version refuses" 1 "cannot read" "banana"
assert_true "refresh unreadable2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

INST="$WORK/inst-broken"
instance_fixture "$INST" broken
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh broken: sdd.json that does not parse refuses" 1 "does not parse"
assert_true "refresh broken2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

INST="$WORK/inst-nosdd"
instance_fixture "$INST" 1.0.0
rm -f "$INST/.claude/sdd.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh nosdd: an instance with no sdd.json refuses" 1 "no .claude/sdd.json"

# Without jq the recorded version cannot be read at all, which is precisely the
# state in which a downgrade is indistinguishable from an upgrade.
INST="$WORK/inst-nojq"
instance_fixture "$INST" 1.0.0
run_script_nojq bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh nojq: without jq the refresh refuses rather than copying blind" 1 "jq"
assert_true "refresh nojq2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

# --- forward moves are performed and recorded ------------------------------------

INST="$WORK/inst-legacy"
instance_fixture "$INST" none
assert_true "refresh legacy0: the fixture really records no plugin version" \
  "the fixture already records one, so this is not the pre-1.0.2 case" \
  test -z "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")"
run_script bash "$SCRIPTS/refresh-instance.sh" "$INST"
expect_script "refresh legacy: a report-only run names the differing file and changes nothing" 0 \
  "close-gate.sh" "Re-run with --apply"
assert_true "refresh legacy2: the report-only run copied nothing" \
  "report mode overwrote the instance's close-gate.sh" \
  marker_intact "$INST"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "refresh legacy3: an instance recording no version is refreshed forward" 0 "forward"
if marker_intact "$INST"; then
  bad "refresh legacy4: --apply restores the hook bytes" \
      "close-gate.sh still carries the instance marker, so nothing was copied"
elif cmp -s "$HOOKS/close-gate.sh" "$INST/.claude/hooks/close-gate.sh"; then
  ok "refresh legacy4: --apply restores the hook bytes byte-verbatim"
else
  bad "refresh legacy4: --apply restores the hook bytes" "close-gate.sh differs from the template"
fi
if [[ "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")" == "$PLUGIN_VERSION" ]]; then
  ok "refresh legacy5: --apply records the plugin version in the instance"
else
  bad "refresh legacy5: --apply records the plugin version in the instance" \
      "sdd.json records '$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")', expected '$PLUGIN_VERSION'"
fi
if [[ "$(jq -r '.trunk // empty' "$INST/.claude/sdd.json")" == "main" ]]; then
  ok "refresh legacy6: recording the version preserves the rest of sdd.json"
else
  bad "refresh legacy6: recording the version preserves the rest of sdd.json" \
      "the trunk field did not survive the rewrite"
fi

# --- session skew ----------------------------------------------------------------

# The cache lays versions of the same plugin out side by side, which is the
# shape the field case had: two trees present, the session bound to the older.
fake_tree() { # fake_tree <dir> <version> [name]
  mkdir -p "$1/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "${3:-setlist}" "$2" > "$1/.claude-plugin/plugin.json"
}

CACHE="$WORK/cache/setlist/setlist"
fake_tree "$CACHE/1.0.1" 1.0.1
fake_tree "$CACHE/1.0.2" 1.0.2
assert_true "skew 0: the fixture cache really holds two trees of the same plugin" \
  "the two-version cache fixture was not built, so the skew cases below prove nothing" \
  test -f "$CACHE/1.0.1/.claude-plugin/plugin.json" -a -f "$CACHE/1.0.2/.claude-plugin/plugin.json"

run_script bash "$SCRIPTS/plugin-skew.sh" "$CACHE/1.0.1"
expect_script "skew a: a session on the older cached tree reports SKEW" 1 "SKEW" "1.0.1" "1.0.2"
run_script bash "$SCRIPTS/plugin-skew.sh" "$CACHE/1.0.2"
expect_script "skew b: a session on the newest cached tree reports no skew" 0 "no session skew"

# A neighbour that is a DIFFERENT plugin is not a newer version of this one.
# Pointed at a working checkout, the first cut of this compared unrelated
# repositories sitting beside it and announced a confident false SKEW.
OTHER="$WORK/cache/other"
fake_tree "$OTHER/setlist-solo" 1.0.3 setlist
fake_tree "$OTHER/unrelated" 9.9.9 some-other-plugin
run_script bash "$SCRIPTS/plugin-skew.sh" "$OTHER/setlist-solo"
expect_script "skew c: a differently named neighbouring plugin is not a newer version" 2 "Unverified, not clean"

# A tree with no manifest cannot be evaluated, and says so instead of passing.
mkdir -p "$WORK/not-a-plugin"
run_script bash "$SCRIPTS/plugin-skew.sh" "$WORK/not-a-plugin"
expect_script "skew d: an unreadable tree reports undeterminable, not clean" 2 "undeterminable"

# --- a stale session must not refresh at all --------------------------------------

# The field case end to end: the plugin tree the session is bound to is real and
# complete, a newer tree sits beside it in the cache, and the instance is
# willing. Refreshing here would install the OLD hook bytes and report an
# upgrade, which is the exact chore that was nearly closed in the field.
STALE="$WORK/cache/stale/setlist/1.0.1"
mkdir -p "$STALE"
cp -R "$ROOT/scripts" "$STALE/scripts"
cp -R "$ROOT/templates" "$STALE/templates"
fake_tree "$STALE" 1.0.1
fake_tree "$WORK/cache/stale/setlist/1.0.2" 1.0.2
assert_true "stale 0: the stale-session fixture really carries a runnable plugin tree" \
  "the copied tree is missing refresh-instance.sh, so the case below is not testing the field shape" \
  test -f "$STALE/scripts/refresh-instance.sh"

INST="$WORK/inst-stale"
instance_fixture "$INST" 1.0.0
run_script bash "$STALE/scripts/refresh-instance.sh" --apply "$INST"
expect_script "stale a: a session bound to a superseded plugin tree refuses to refresh" 1 \
  "SKEW" "Restart the session"
assert_true "stale a2: the refused refresh copied nothing" \
  "the instance's close-gate.sh lost its marker despite the refusal" \
  marker_intact "$INST"

# The same tree, with no newer neighbour, refreshes normally: the refusal above
# is caused by the skew and not by the fixture being unusable.
SOLO="$WORK/cache/solo/setlist/1.0.1"
mkdir -p "$SOLO"
cp -R "$ROOT/scripts" "$SOLO/scripts"
cp -R "$ROOT/templates" "$SOLO/templates"
fake_tree "$SOLO" 1.0.1
INST="$WORK/inst-solo"
instance_fixture "$INST" 1.0.0
run_script bash "$SOLO/scripts/refresh-instance.sh" --apply "$INST"
expect_script "stale b: the same plugin tree without a newer neighbour refreshes forward" 0 "forward"

# =============================================================================
# hygiene
# =============================================================================

# z. every shell file parses
SYNTAX_BAD=""
for f in "$ROOT"/templates/hooks/*.sh "$ROOT"/scripts/*.sh "$ROOT"/test/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" 2>/dev/null || SYNTAX_BAD="$SYNTAX_BAD ${f#$ROOT/}"
done
if [[ -z "$SYNTAX_BAD" ]]; then
  ok "hygiene z: bash -n passes on every shell file in templates, scripts, and test"
else
  bad "hygiene z: bash -n passes on every shell file in templates, scripts, and test" \
      "syntax errors in:$SYNTAX_BAD"
fi

# aa. no literal em-dash byte anywhere in the shipped surface. Scoped to what
# rule 1 governs forward: the plugin tree, the edition, the READMEs, and this
# suite. Historical editions and journals keep theirs by design and are not
# part of the publishable set.
SURFACE="setlist.md README.md .claude-plugin skills templates scripts test .github"
EM_HITS=""
EM_FILES=""
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  EM_FILES="$(cd "$ROOT" && git ls-files -- $SURFACE 2>/dev/null || true)"
fi
# An export staged into a fresh clone is a git work tree whose files are not
# tracked yet, so ls-files returns nothing and this check would pass having
# scanned zero bytes. Fall back to the filesystem, and treat an empty list as
# a failure: a hygiene check that silently covers nothing is the same defect
# class as a gate that silently allows everything.
if [[ -z "$EM_FILES" ]]; then
  EM_FILES="$(cd "$ROOT" && find $SURFACE -type f 2>/dev/null || true)"
fi
EM_COUNT=0
[[ -n "$EM_FILES" ]] && EM_COUNT="$(printf '%s\n' "$EM_FILES" | grep -c .)"
while IFS= read -r f; do
  [[ -n "$f" && -f "$ROOT/$f" ]] || continue
  # The suite's own fixture builds the character at runtime from an octal
  # escape; the literal byte must appear in no tracked file.
  if LC_ALL=C grep -q "$EMDASH" "$ROOT/$f" 2>/dev/null; then
    EM_HITS="$EM_HITS $f"
  fi
done <<EOF
$EM_FILES
EOF
if [[ "$EM_COUNT" -lt 20 ]]; then
  bad "hygiene aa: no literal em-dash byte in the shipped surface" \
      "only $EM_COUNT files were scanned; the surface is far larger, so this check covered almost nothing"
elif [[ -z "$EM_HITS" ]]; then
  ok "hygiene aa: no literal em-dash byte across $EM_COUNT files in the shipped surface"
else
  bad "hygiene aa: no literal em-dash byte in the shipped surface" "found in:$EM_HITS"
fi

# =============================================================================
# 1.0.3: the refresh checks the settings WIRING it cannot copy. Two of this
# release's fixes live in .claude/settings.json (the write-tool matcher set
# and the per-hook timeouts), and that file holds the instance's own
# permissions and model settings, so the script must not rewrite it. The
# failure to avoid is a refresh that copies hook bytes, records the new
# version, exits 0, and leaves two fixes inert while reporting success.
# =============================================================================

INST="$WORK/inst-wiring-matcher"
instance_fixture "$INST" 1.0.0 stale-matcher
run_script bash "$SCRIPTS/refresh-instance.sh" "$INST"
expect_script "wiring a: a report names the stale matcher" 0 "NotebookEdit"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring b: applying over a stale matcher exits INCOMPLETE, not 0" 3 "INCOMPLETE" "NotebookEdit"
# The hooks must still have landed: incomplete is not the same as refused.
if cmp -s "$HOOKS/close-gate.sh" "$INST/.claude/hooks/close-gate.sh"; then
  ok "wiring c: an incomplete refresh still refreshed the hook bytes"
else
  bad "wiring c: an incomplete refresh still refreshed the hook bytes" "close-gate.sh was not copied"
fi
if [[ "$(jq -r '.plugin.version // empty' "$INST/.claude/sdd.json")" == "$PLUGIN_VERSION" ]]; then
  ok "wiring d: an incomplete refresh still recorded the plugin version"
else
  bad "wiring d: an incomplete refresh still recorded the plugin version" "version not recorded"
fi

INST="$WORK/inst-wiring-timeouts"
instance_fixture "$INST" 1.0.0 no-timeouts
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring e: hook entries with no timeout exit INCOMPLETE" 3 "timeout"

INST="$WORK/inst-wiring-missing"
instance_fixture "$INST" 1.0.0 missing
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring f: a missing settings.json exits INCOMPLETE" 3 "missing entirely"

# And current wiring must NOT trip it: a check that fires on everything is a
# check people learn to ignore.
INST="$WORK/inst-wiring-ok"
instance_fixture "$INST" 1.0.0 current
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring g: current wiring refreshes completely and exits 0" 0 "refreshed the five stamped hooks"

# =============================================================================
# >>> SHARD-BEGIN refresh-wiring cost=16
if shard_region refresh-wiring; then
# 1.0.4: the wiring check reads STRUCTURE, not text. Both directions, from two
# field reviews of the shipped 1.0.3: it must not fire on hooks the project
# owns, and it must not be defeated by JSON formatting.
# =============================================================================

# A project's own hooks are none of this check's business. A prettier hook with
# no timeout produced a permanent INCOMPLETE in 1.0.3 that no edit to Setlist's
# wiring could clear, because the demanded fix was editing someone else's hook.
INST="$WORK/inst-foreign-hook"
instance_fixture "$INST" 1.0.0 current
jq '.hooks.PostToolUse=[{matcher:"Write",hooks:[{type:"command",command:"npx prettier --write"}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring h: a foreign hook with no timeout does NOT make the refresh incomplete" 0 "refreshed the five stamped hooks"

# THE SAME CASE IN ITS REAL SHAPE (1.0.7, F23). The fixture above puts the
# foreign hook's command at `npx prettier --write`, which is not a path into
# .claude/hooks/ at all, so it was excluded by the one condition 1.0.4's
# selector actually tested. A project hook LIVING WHERE PROJECT HOOKS LIVE was
# never tried, and that is the case that still failed: the selector matched the
# directory, so .claude/hooks/prettier.sh counted as Setlist's, and its missing
# timeout produced an exit 3 no edit to Setlist's wiring could clear.
#
# A fixture that cannot express a finding is not evidence against it. This case
# carried the name of the defect for three releases while testing the one
# spelling that already worked.
INST="$WORK/inst-foreign-hook-in-dir"
instance_fixture "$INST" 1.0.0 current
printf '#!/usr/bin/env bash\nexit 0\n' > "$INST/.claude/hooks/prettier.sh"
chmod +x "$INST/.claude/hooks/prettier.sh"
jq '.hooks.PostToolUse=[{matcher:"Write",hooks:[{type:"command",command:"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prettier.sh"}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring h2: a foreign hook INSIDE .claude/hooks/ is still not Setlist's" 0 "refreshed the five stamped hooks"
if printf '%s' "$SCRIPT_OUT" | grep -q prettier; then
  bad "wiring h2: the report must not name a hook the project owns" \
      "prettier.sh was named as a Setlist entry: $SCRIPT_OUT"
else
  ok "wiring h2: the report does not name the project's own hook"
fi

# THE GATES MUST BE WIRED AT ALL (1.0.7, B5/F5). Every wiring case above finds
# fault with an entry that is PRESENT: a stale matcher, a missing timeout, a
# malformed file. Delete the two gate entries outright and there was nothing
# left to object to, so the refresh reported a complete apply, exit 0, and told
# the operator the refreshed gates would bind from the next session, of a pair
# of gates that would never bind again.
#
# This is the seam that carried plugin 1.0.3's worst defect. An upgrade path
# that certifies a disarmed instance is worse than no check at all: it turns
# "verify this yourself" into "this was verified".
INST="$WORK/inst-gates-unwired"
instance_fixture "$INST" 1.0.0 no-gates
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring m: both gates unwired exits INCOMPLETE and names them" 3 "commit-gate.sh" "close-gate.sh"

# The hook FILES are current in that instance, which is the whole trap: byte
# freshness and enforcement are different claims, and the first was being
# reported as though it settled the second.
if cmp -s "$HOOKS/commit-gate.sh" "$INST/.claude/hooks/commit-gate.sh"; then
  ok "wiring m2: the unwired instance's hook bytes ARE current, so freshness is not enforcement"
else
  bad "wiring m2: the unwired instance's hook bytes should still have been refreshed" \
      "an INCOMPLETE refresh still copies the files; only the wiring is outstanding"
fi

# And the inverse, so "names them" cannot be satisfied by naming them always.
INST="$WORK/inst-gates-wired"
instance_fixture "$INST" 1.0.0 current
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
if printf '%s' "$SCRIPT_OUT" | grep -q 'NOTHING IN'; then
  bad "wiring m3: a fully wired instance must not be reported as unwired" \
      "the unwired message fired on a complete instance: $SCRIPT_OUT"
else
  ok "wiring m3: a fully wired instance is not reported as unwired"
fi

# =============================================================================
# 1.0.8 (leg 4, F2): WIRED MEANS THIS INSTANCE'S FILE, NOT A FILE WITH THAT NAME.
#
# The predicate above was tightened on 2026-07-28 from a bare substring match to
# an anchored pattern, and the anchored pattern still asked about SHAPE:
#
#   ^[^ ]*/[.]claude/hooks/<name>[.]sh([^ ]*)?( |$)
#          ^^^^^^                          ^^^^^^^
#          any root                        any suffix
#
# So `close-gate.sh.disabled` was Setlist's close gate, and so was a sibling
# package's copy in a monorepo, and so was one under $HOME or /opt. Renaming a
# hook to `.disabled` is exactly how a person turns a gate off. The instance
# reported zero wiring gaps, --apply exited 0, and printed "the refreshed gates
# bind from the NEXT session onward" about a gate that would never bind.
#
# The 2026-07-28 fix closed the two examples its own comment named (a fork one
# level deeper, a bare mention) and not the class around them. That is the same
# stop-at-the-example error as the heading-depth range in the report checker,
# twice in two days, which is why these cases are written as a LOOP OVER THE SET
# rather than as the two spellings a finding happened to report.
#
# The upgrade path is the one surface a user cannot check by hand, and its whole
# purpose since 1.0.7 is to notice a disarmed instance.
rewire() { # rewire <settings.json> <hook-name> <new-command-string>
  jq --arg h "$2" --arg c "$3" '
    walk(if type == "object" and has("command") and ((.command // "") | test($h))
         then .command = $c else . end)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# Every spelling below names a file that is NOT the one this script stamps at
# $INSTANCE/.claude/hooks/<name>.sh, so every one must report UNWIRED. Run
# against all four stamped hooks, because a predicate that is right for the
# close gate and wrong for the scope hook is the defect one file over.
for h in scope-hook commit-gate close-gate regrounding-hook stop-hook; do
  for spell in \
    'SUFFIX-disabled|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh.disabled' \
    'SUFFIX-orig|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh.orig' \
    'SUFFIX-wrapper|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.shell-wrapper' \
    'ROOT-sibling|"$CLAUDE_PROJECT_DIR"/packages/api/.claude/hooks/HOOK.sh' \
    'ROOT-home|$HOME/.claude/hooks/HOOK.sh' \
    'ROOT-vendor|/opt/vendor/.claude/hooks/HOOK.sh' \
    'FORK-deeper|"$CLAUDE_PROJECT_DIR"/.claude/hooks/local/HOOK.sh'
  do
    label="${spell%%|*}"; cmd="${spell#*|}"; cmd="${cmd//HOOK/$h}"
    INST="$WORK/inst-disarm-$h-$label"
    instance_fixture "$INST" 1.0.0 current
    rewire "$INST/.claude/settings.json" "$h" "$cmd"
    run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
    expect_script "disarm $h/$label: a command that does not run this instance's $h.sh is UNWIRED" 3 "$h.sh"
  done
done

# The other direction, which is the one that makes the check usable rather than
# merely strict: every spelling this script actually stamps, plus the literal
# absolute path an instance may legitimately be wired with, must stay WIRED. A
# predicate that reports everything unwired would pass every case above and be
# worthless.
for spell in \
  'quoted-var|"$CLAUDE_PROJECT_DIR"/.claude/hooks/HOOK.sh' \
  'braced-var|${CLAUDE_PROJECT_DIR}/.claude/hooks/HOOK.sh' \
  'quoted-braced|"${CLAUDE_PROJECT_DIR}"/.claude/hooks/HOOK.sh' \
  'bare-var|$CLAUDE_PROJECT_DIR/.claude/hooks/HOOK.sh'
do
  label="${spell%%|*}"; tmpl="${spell#*|}"
  INST="$WORK/inst-armed-$label"
  instance_fixture "$INST" 1.0.0 current
  for h in scope-hook commit-gate close-gate regrounding-hook stop-hook; do
    rewire "$INST/.claude/settings.json" "$h" "${tmpl//HOOK/$h}"
  done
  run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
  expect_script "armed $label: a spelling this script stamps stays WIRED" 0 "refreshed the five stamped hooks"
done

# THE ENUMERATED-SET RESTRICTION, pinned as the documented Known-limitations
# bullet says (2.4.0 leg F11): `bash <stamped path>` genuinely runs the gate,
# and the check still reports it NOT WIRED, because the set is the spellings
# settings.json.tmpl ships and nothing else. Fails safe (over-reports, never
# certifies a disarmed instance). If this pin flips, the set was widened:
# widen the bullet in the same commit.
INST="$WORK/inst-bash-prefix"
instance_fixture "$INST" 1.0.0 current
rewire "$INST/.claude/settings.json" "close-gate" 'bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/close-gate.sh'
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring restriction (2.4.0 leg F11, documented): an interpreter-prefixed spelling that runs the stamped file is still reported NOT WIRED" 3 "close-gate.sh"

# The absolute path of the instance itself, which cannot be templated above
# because it is only known at run time.
INST="$WORK/inst-armed-absolute"
instance_fixture "$INST" 1.0.0 current
INST_ABS="$(cd "$INST" && pwd)"
for h in scope-hook commit-gate close-gate regrounding-hook stop-hook; do
  rewire "$INST/.claude/settings.json" "$h" "$INST_ABS/.claude/hooks/$h.sh"
done
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "armed absolute: this instance's own absolute path stays WIRED" 0 "refreshed the five stamped hooks"

# And an entry that is not a command hook does not run a command however its
# string reads, so it cannot arm a gate.
INST="$WORK/inst-disarm-type"
instance_fixture "$INST" 1.0.0 current
jq 'walk(if type == "object" and has("command") and ((.command // "") | test("close-gate"))
         then .type = "output" else . end)' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "disarm type: an entry whose type is not 'command' does not arm the close gate" 3 "close-gate.sh"

# grep -c counts LINES. Against a minified settings.json (Claude Code rewrites
# this file when a user toggles config) four entries carrying one timeout read
# as "1 and 1" in 1.0.3, balanced, and the refresh exited 0 over three untimed
# hooks: a check that could not evaluate its predicate passing as clean.
INST="$WORK/inst-minified"
instance_fixture "$INST" 1.0.0 current
jq -c '(.hooks.PreToolUse[1].hooks[]|.timeout) |= null | del(.hooks.PreToolUse[1].hooks[].timeout)' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
assert_true "wiring i0: the fixture really is minified and really is short a timeout" \
  "the fixture is not one line, or carries every timeout, so case i proves nothing" \
  test "$(wc -l < "$INST/.claude/settings.json")" -le 1
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring i: a minified settings.json short a timeout is still caught" 3 "timeout"
expect_script "wiring i2: and the report NAMES the offending entries" 3 "commit-gate.sh"

# A foreign hook that merely MENTIONS NotebookEdit must not mask a stale scope
# matcher: 1.0.3 grepped the whole file for the token.
INST="$WORK/inst-masked-matcher"
instance_fixture "$INST" 1.0.0 stale-matcher
jq '.hooks.PostToolUse=[{matcher:"NotebookEdit",hooks:[{type:"command",command:"echo x",timeout:5}]}]' \
  "$INST/.claude/settings.json" > "$INST/t" && mv "$INST/t" "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring j: a foreign hook naming NotebookEdit does not mask a stale scope matcher" 3 "Write|Edit"

# THE SCOPE-MATCHER CERTIFICATION, AS COVERAGE (F3 with V19-F5 and V19-F10, and
# F5's three spellings). One block, because they are one function and three
# separate repairs to one predicate is how the second reintroduces the first.
#
# Watched RED first, every subject, on the pre-fix bytes: the substring test
# certified `Write|Edit|MultiEdit|NotebookEditor` and `Write|NotebookEdit` CLEAN,
# `| first` reported a two-entry instance whose union covers everything as
# unwired, and all three match-all spellings were read as covering nothing.
# The comma case "passed" before the fix for the WRONG reason (the substring
# search found the token inside it), which is F3 in one line.
sm_settings() { # sm_settings <matcher-json>... -> a settings.json body
  local entries="" m
  for m in "$@"; do
    [[ -n "$entries" ]] && entries="$entries,"
    entries="$entries{\"matcher\":$m,\"hooks\":[{\"type\":\"command\",\"command\":\"\$CLAUDE_PROJECT_DIR/.claude/hooks/scope-hook.sh\",\"timeout\":10}]}"
  done
  printf '{"hooks":{"PreToolUse":[%s],"SessionStart":[]}}' "$entries"
}
# TWO PREDICATES, READ SEPARATELY (RC3-2026 F7, the 2.4.1 leg; fixed 2026-09-04,
# spec 0130). The classifier below was one line-oriented grep for 'scope hook'
# followed by a gap word, and the UNWIRED block puts the hook NAMES on the line
# AFTER 'NOT WIRED IN A WAY', so no line ever carried both and the comma case
# passed having evaluated nothing: the coverage reader normalises a comma, the
# UNWIRED reader does not (KL10, a documented boundary), and this assertion
# could see only the first. Now each case states BOTH expectations: the
# COVERAGE verdict from the coverage messages, and the WIRED verdict from the
# hook list the UNWIRED block prints. Watched red first by asking the comma
# spelling for WIRED on the shipped bytes, which the old classifier could not
# have refused.
sm_case() { # sm_case <label> <want-coverage: GAP|CLEAN> <want-wired: WIRED|UNWIRED> <matcher-json>...
  local label="$1" want="$2" want_wired="$3"; shift 3
  local inst="$WORK/inst-sm"; rm -rf "$inst"
  instance_fixture "$inst" 1.0.0 current
  sm_settings "$@" > "$inst/.claude/settings.json"
  run_script bash "$SCRIPTS/refresh-instance.sh" "$inst"
  local got got_wired unwired_list
  if printf '%s' "$SCRIPT_OUT" | grep -qiE 'scope hook.*(does not cover|do not cover|not wired|could not be)'; then got=GAP; else got=CLEAN; fi
  # The UNWIRED list is the line after 'NOT WIRED IN A WAY'; scope-hook.sh in it
  # is the fact the old grep could never see.
  unwired_list="$(printf '%s' "$SCRIPT_OUT" | grep -A1 'NOT WIRED IN A WAY' | tail -n1)"
  case "$unwired_list" in *scope-hook.sh*) got_wired=UNWIRED ;; *) got_wired=WIRED ;; esac
  if [[ "$got" == "$want" && "$got_wired" == "$want_wired" ]]; then
    ok "scope coverage [$label]: coverage $got, scope hook $got_wired"
  else
    bad "scope coverage [$label]" \
        "wanted coverage $want and scope hook $want_wired, measured coverage $got and scope hook $got_wired. Coverage is judged over Write/Edit/MultiEdit/NotebookEdit, taking the UNION of every entry that runs the scope hook, with a catch-all treated as match-all and a comma treated as a pipe; WIRED is read from the hook list the UNWIRED block prints."
  fi
}
sm_case "a matcher CONTAINING the token but covering nothing" GAP   WIRED   '"Write|Edit|MultiEdit|NotebookEditor"'
sm_case "a matcher missing Edit and MultiEdit"                GAP   WIRED   '"Write|NotebookEdit"'
sm_case "control: the correct matcher certifies clean"      CLEAN WIRED   '"Write|Edit|MultiEdit|NotebookEdit"'
sm_case "two entries whose UNION covers everything"         CLEAN WIRED   '"Write|Edit"' '"MultiEdit|NotebookEdit"'
sm_case "match-all *"                                       CLEAN WIRED   '"*"'
sm_case "match-all empty"                                   CLEAN WIRED   '""'
sm_case "match-all absent"                                  CLEAN WIRED   'null'
# KL10, pinned in its documented direction: the coverage reader normalises the
# comma and certifies coverage; the UNWIRED reader does not and reports the
# scope hook unwired (a false negative in the safe direction, its bullet a
# design boundary since 2.4.1). The day KL10's fix lands this reads WIRED, goes
# red, and the expectation moves with the bullet.
sm_case "the comma spelling"                                CLEAN UNWIRED '"Write,Edit,MultiEdit,NotebookEdit"'
sm_case "control: no scope-hook entry at all is a gap"        GAP   UNWIRED

# F10: the advisory backup notice ends its own line. It was printed without a
# trailing newline at two call sites, so the one line telling an operator a
# foreign file was replaced was glued onto the success line.
if grep -qE "printf 'refresh-instance\.sh: %s' " "$SCRIPTS/refresh-instance.sh"; then
  bad "F10: the advisory backup notice ends with a newline" \
      "a call site still prints it without one, so the notice is glued to the next line"
else
  ok "F10: the advisory backup notice ends with a newline"
fi

# Unparseable settings cannot be evaluated, so they are named, never assumed.
INST="$WORK/inst-badjson"
instance_fixture "$INST" 1.0.0 current
printf '{ "hooks": \n' > "$INST/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$INST"
expect_script "wiring k: settings.json that does not parse is reported, not guessed at" 3 "does not parse"

fi; shard_region_end
# <<< SHARD-END refresh-wiring
