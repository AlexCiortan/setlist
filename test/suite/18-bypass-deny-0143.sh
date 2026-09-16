# Shard 18: the 2.8.0 successor (spec 0143). Sourced by test/run-tests.sh.
#
# =============================================================================
# THE ONE HARD DENY, IN A HOOK OF ITS OWN (spec 0143; spec 0142 section 1,
# option A, ruled by the owner 2026-09-13).
#
# The deny moved out of the commit gate into templates/hooks/bypass-deny.sh, so
# it survives 2.8.0's deletion of the two advisory gates. This region drives
# the NEW hook through every deny and allow case bypass-deny-0132 drives the
# commit gate through, and then asserts the three tests of "minimal" that spec
# 0143 writes out: one question, one verdict shape, one reader pinned by digest.
#
# THE ALLOW DIRECTION IS STRICTER HERE THAN IN 0132, on purpose. The commit gate
# can advise on a command it does not deny, so 0132 asserts only "not denied".
# This hook has no advisory path at all (test 2), so an allowed command must
# draw NO OUTPUT and exit 0; any byte on stdout is a verdict shape the hook is
# not allowed to have.
#
# THE PIN (test 3, the ruling's condition). The lexer's assignment block, from
# the line BYPASS_LEX_AWK=' through its closing quote, is hashed with SHA-256
# and compared with the value below. A change to that block, a new spelling
# included, turns this region red; that is the point, and the fix is a decision
# by the owner rather than an edit to this number. Watched red first at a wrong
# digest (spec 0143, Progress).
#
# Until spec 0144 the commit gate carried the same block, and one case here
# pinned ITS copy to the same digest so the two could not diverge while both
# stood. That old-gate case left with the gate in 2.8.0.
# =============================================================================
# >>> SHARD-BEGIN bypass-deny-0143 cost=12
if shard_region bypass-deny-0143; then

BDS_HOOK="$HOOKS/bypass-deny.sh"
BDS_PIN="e23bc289f3b335848b9693db6dd051da27cafabbf60496375cecebcccab52ee7"

if [[ -f "$BDS_HOOK" ]]; then
  ok "successor: templates/hooks/bypass-deny.sh exists at its own path"
else
  bad "successor: templates/hooks/bypass-deny.sh exists at its own path" "the file is absent, so every case below is reading nothing"
fi

BDS="$WORK/bypass-deny-0143"; git_init "$BDS"; sdd_json "$BDS"
printf 'clean content with nothing to find\n' > "$BDS/ok.md"; git -C "$BDS" add ok.md
BDS_RC=0
bds_out() { # bds_out <command> -> the hook's stdout; its exit status in BDS_RC
  local p out
  p="$(bash_payload "$1")"
  out="$(printf '%s' "$p" | CLAUDE_PROJECT_DIR="$BDS" bash "$BDS_HOOK" 2>/dev/null)"; BDS_RC=$?
  printf '%s' "$out"
}
bds_deny() { # bds_deny <name> <command> <code>
  local out dec code
  out="$(bds_out "$2")"
  dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  code="$(printf '%s' "$out" | jq -r '.setlistAdvisory.code // empty' 2>/dev/null)"
  if [[ "$dec" == "deny" && "$code" == "$3" ]]; then
    ok "successor deny $1: [$2] is DENIED by bypass-deny.sh as $3"
  else
    bad "successor deny $1: [$2] is DENIED by bypass-deny.sh as $3" "decision=[${dec:-none}] code=[${code:-none}]"
  fi
}
bds_allow() { # bds_allow <name> <command>
  local out rc
  out="$(bds_out "$2"; printf '\001%s' "$BDS_RC")"
  rc="${out##*$'\001'}"; out="${out%$'\001'*}"
  if [[ -f "$BDS_HOOK" && -z "$out" && "$rc" == "0" ]]; then
    ok "successor allow $1: [$2] draws no output from bypass-deny.sh and exits 0"
  else
    bad "successor allow $1: [$2] draws no output from bypass-deny.sh and exits 0" "rc=$rc out=[$(printf '%s' "$out" | cut -c1-120)]"
  fi
}

# --- the deny direction, every case bypass-deny-0132 drives ------------------
bds_deny a 'SETLIST_SKIP_HOOKS=1 git commit -m x' CM-BYPASS-SPELLED
bds_deny b 'SETLIST_SKIP_TRUNK_AUDIT=1 git push origin main' CM-BYPASS-SPELLED
bds_deny c 'export SETLIST_SKIP_HOOKS=1' CM-BYPASS-SPELLED
bds_deny d 'git commit --no-verify -m x' CM-BYPASS-SPELLED
bds_deny e 'git push --no-verify origin main' CM-BYPASS-SPELLED
bds_deny f 'git -c core.hooksPath=/dev/null commit -m x' CM-HOOKSPATH-MOVED
bds_deny g 'git  -c   core.hooksPath=.nothing merge --no-ff spec/0001-thing' CM-HOOKSPATH-MOVED
bds_deny h 'cd repo && git commit -m "x" --no-verify' CM-BYPASS-SPELLED
bds_deny f2e 'SETLIST_SKIP_HOOKS=1 git commit -m x' CM-BYPASS-SPELLED
bds_deny f2f 'env SETLIST_SKIP_TRUNK_AUDIT=1 git push origin main' CM-BYPASS-SPELLED
bds_deny f2g 'git commit -m x --no-verify' CM-BYPASS-SPELLED
bds_deny i 'git commit "--no-verify" -m x' CM-BYPASS-SPELLED
bds_deny j "git commit '--no-verify' -m x" CM-BYPASS-SPELLED
bds_deny k 'git commit --no-veri"f"y -m x' CM-BYPASS-SPELLED
bds_deny l 'echo "a \" b" && git commit --no-verify -m x && echo "c \" d"' CM-BYPASS-SPELLED
bds_deny m 'git commit -n -m x' CM-BYPASS-SPELLED
bds_deny n 'git commit -an -m x' CM-BYPASS-SPELLED
bds_deny o 'git commit --no-veri -m x' CM-BYPASS-SPELLED
bds_deny p 'git push --no-verif origin main' CM-BYPASS-SPELLED
bds_deny q 'git -c "core.hooksPath=/dev/null" commit -m x' CM-HOOKSPATH-MOVED
bds_deny r 'git -ccore.hooksPath=/dev/null commit -m x' CM-HOOKSPATH-MOVED
bds_deny s 'SETLIST_SKIP_HOOKS="1" git commit -m x' CM-BYPASS-SPELLED
bds_deny t 'env SETLIST_SKIP_TRUNK_AUDIT=1 git push' CM-BYPASS-SPELLED

# --- the allow direction: DE13's four documented defeats, F2's false denials,
# and the false-denial surface, every case bypass-deny-0132 drives -----------
bds_allow de13a 'git commit -m ${MSG} --no-verify'
bds_allow de13b "git commit \$'--no-verify' -m x"
bds_allow de13c 'git --attr-source HEAD commit -n -m x'
bds_allow de13d 'EV=/tmp/nohooks git --config-env=core.hooksPath=EV commit -m x'
bds_allow f2a 'git commit -m "SETLIST_SKIP_HOOKS=1"'
bds_allow f2b 'grep -rn SETLIST_SKIP_HOOKS=1 .'
bds_allow f2c 'echo "SETLIST_SKIP_HOOKS=1"'
bds_allow f2d 'git log --grep "--no-verify"'
bds_allow a 'git commit -m "never use SETLIST_SKIP_HOOKS=1 here"'
bds_allow b "git commit -m 'the flag --no-verify is refused by the gate'"
bds_allow c 'grep -r core.hooksPath .'
bds_allow d 'echo --no-verify'
bds_allow e 'grep -n SETLIST_SKIP_HOOKS templates/git-hooks/pre-push'
bds_allow f 'git commit -m x'
bds_allow g 'git commit -m "he said \"use --no-verify\" once"'
bds_allow h "git commit -m \"it's about --no-verify\""
bds_allow i 'echo "a \" b" && git commit -m "prose --no-verify prose" && echo "c \" d"'
bds_allow j 'git add notes/--no-verify.md'
bds_allow k 'git push -n origin main'
bds_allow l 'git commit -m "SETLIST_SKIP_HOOKS=1 is documented, not coached"'
bds_allow m 'git log --grep=--no-verify'

# --- the 2.8.0 leg's confirmed false denials, FIXED by the owner's ruling of 2026-09-16 ---
# Spec 0147, fix round 1. The parser freeze of 2026-08-04 was lifted for these rows only
# (F5, F6, F11, F12, F14 of dogfood/2026-09-16-plugin-2.8.0-hostile-leg.md), each measured
# denying on the published v2.7.0 commit gate as well, so none was a 2.8.0 regression.
# Written red-first against the pre-fix lexer. Every change is scoped so that what it does
# not cover keeps today's deny, and the guards below the allows pin that direction.
bds_allow fr1a $'cat <<\'EOF\' > notes.md\ngit commit --no-verify -m x\nEOF'
bds_allow fr1b $'cat <<EOF >> LIMITATIONS.md\nNever run git commit --no-verify here.\nEOF'
bds_allow fr1c $'cat > doc.md <<\'EOF\'\nThe escape hatch is git commit --no-verify -m msg, for a person only.\nEOF'
bds_allow fr1d $'git commit -F - <<\'EOF\'\nnever run git commit --no-verify here\nEOF'
bds_allow fr1e $'tee -a notes.md <<-EOF\n\tSETLIST_SKIP_HOOKS=1 git commit -m x is documented, not coached\n\tEOF'
bds_allow fr1f 'git commit -am "--no-verify"'
bds_allow fr1g 'git commit -sm "--no-verify"'
bds_allow fr1h 'git grep -e --no-verify'
bds_allow fr1i 'git log -S --no-verify --oneline'
bds_allow fr1j 'git log -G --no-verify'
bds_allow fr1k 'git grep -- --no-verify'
bds_allow fr1l 'git checkout -- --no-verify'
bds_allow fr1m 'git log --oneline -- --no-verify'
# FIX ROUND 2, the 2.8.0 cold adversary round's claim 0 (spec 0147). A COMBINED short flag whose
# last letter is a value-taking search option takes the next word as its value exactly as the
# separated spelling does, and git runs all three of these (measured rc 0), so denying them is a
# false denial of the same class the owner ruled fixed on 2026-09-16.
bds_allow fr2a 'git log -pS --no-verify'
bds_allow fr2b 'git log -pG --no-verify'
bds_allow fr2c 'git log -pS --no-verify --oneline'
# FIX ROUND 3 (spec 0147, the owner's A4 exception of 2026-09-16), the control in the allowing
# direction: -F takes the NEXT word as a message file, so this command carries no disarming flag and
# must keep allowing before and after the narrowing.
bds_allow fr3f 'git commit -aF --no-verify'
# The guards: nothing the fix skips may be a command git would run with the flag.
bds_deny fr1n $'bash <<\'EOF\'\ngit commit --no-verify -m x\nEOF' CM-BYPASS-SPELLED
bds_deny fr1o $'cat <<EOF\ngit commit --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1p $'cat <<\'EOF\' > a.md\nhello\nEOF\ngit commit --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1q 'echo $((1<<2)); git commit --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1r 'git commit -S --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1s 'git commit -e --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1t 'git ci --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr1u 'git log -S x && git commit --no-verify -m y' CM-BYPASS-SPELLED
bds_deny fr1v 'git commit -nm x' CM-BYPASS-SPELLED
# Fix round 2's guards: the widening is scoped to the search family and skips ONE word only.
bds_deny fr2d 'git commit -sS --no-verify -m x' CM-BYPASS-SPELLED
bds_deny fr2e 'git log -pS x && git commit --no-verify -m y' CM-BYPASS-SPELLED
bds_deny fr2f $'git log -pS --no-verify\ngit commit --no-verify -m x' CM-BYPASS-SPELLED
# FIX ROUND 3: the bypass fix round 1 introduced. git gives a value-taking short option the REST of
# the combined flag as its value, so in -amm the -m takes the embedded m and the NEXT word is not a
# value at all: it is the disarming flag, still live. Each of these five returns allow on the bytes
# this round repairs, and four of them LAND a commit past a failing pre-commit hook (measured).
bds_deny fr3a 'git commit -amm --no-verify' CM-BYPASS-SPELLED
bds_deny fr3b 'git commit -smF --no-verify' CM-BYPASS-SPELLED
bds_deny fr3c 'git commit -smm --no-verify' CM-BYPASS-SPELLED
bds_deny fr3d 'git commit -amF --no-verify' CM-BYPASS-SPELLED
bds_deny fr3e 'git commit -amm -n' CM-BYPASS-SPELLED

# The deny reaches the MODEL: the reason is on permissionDecisionReason and
# repeated in systemMessage and setlistAdvisory.reason, as the commit gate's.
BDS_OUT="$(bds_out 'SETLIST_SKIP_HOOKS=1 git commit -m x')"
if [[ "$(printf '%s' "$BDS_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)" == *"CM-BYPASS-SPELLED"* ]] \
   && [[ "$(printf '%s' "$BDS_OUT" | jq -r '.systemMessage' 2>/dev/null)" == *"CM-BYPASS-SPELLED"* ]] \
   && [[ "$(printf '%s' "$BDS_OUT" | jq -r '.setlistAdvisory.reason' 2>/dev/null)" == *"run the command yourself in a terminal"* ]]; then
  ok "successor deny: the reason carries the code in all three fields and says how a person proceeds"
else
  bad "successor deny: the reason carries the code in all three fields and says how a person proceeds" "$(printf '%s' "$BDS_OUT" | cut -c1-200)"
fi

# --- test 1: ONE QUESTION ------------------------------------------------------
# No git invocation, and no read of repository state: the instance's config, its
# status record and the project directory are all absent from the code lines.
BDS_CODE="$(grep -vE '^[[:space:]]*#' "$BDS_HOOK" 2>/dev/null)"
BDS_GIT="$(printf '%s\n' "$BDS_CODE" | grep -nE '(^|[;&|(`]|\$\()[[:space:]]*git[[:space:]]' || true)"
if [[ -n "$BDS_CODE" && -z "$BDS_GIT" ]]; then
  ok "successor test 1 (one question): bypass-deny.sh invokes no git"
else
  bad "successor test 1 (one question): bypass-deny.sh invokes no git" "code lines=$(printf '%s\n' "$BDS_CODE" | grep -c .); git at command position: $(printf '%s' "$BDS_GIT" | cut -c1-160)"
fi
BDS_STATE="$(printf '%s\n' "$BDS_CODE" | grep -nE 'sdd\.json|status\.json|STATUS\.md|CLAUDE_PROJECT_DIR|specs/' || true)"
if [[ -n "$BDS_CODE" && -z "$BDS_STATE" ]]; then
  ok "successor test 1 (one question): bypass-deny.sh reads no config, no status record, no spec and no project directory"
else
  bad "successor test 1 (one question): bypass-deny.sh reads no config, no status record, no spec and no project directory" "$(printf '%s' "$BDS_STATE" | cut -c1-160)"
fi

# --- test 2: ONE VERDICT SHAPE -------------------------------------------------
if [[ -f "$BDS_HOOK" ]] && ! grep -q '"allow"' "$BDS_HOOK"; then
  ok "successor test 2 (one verdict shape): the string \"allow\" appears nowhere in bypass-deny.sh"
else
  bad "successor test 2 (one verdict shape): the string \"allow\" appears nowhere in bypass-deny.sh" "$(grep -n '"allow"' "$BDS_HOOK" 2>/dev/null | cut -c1-120)"
fi
# An identifier is two or more capitals, a hyphen, then hyphen-joined words. The
# first cut read one capital, so the bracket expressions [A-Z] and [A-Z0-9-] in
# the code extractor's own text counted as codes (found by the wrong-digest
# watch, the first run with the file present; spec 0143, Progress).
BDS_CODES="$(grep -oE '\[[A-Z]{2,}-[A-Z0-9]+(-[A-Z0-9]+)*\]' "$BDS_HOOK" 2>/dev/null | sort -u | tr '\n' ' ')"
if [[ "$BDS_CODES" == "[CM-BYPASS-SPELLED] [CM-HOOKSPATH-MOVED] " ]]; then
  ok "successor test 2 (one verdict shape): the code family is exactly the two deny codes, and no toolchain code (decision 1)"
else
  bad "successor test 2 (one verdict shape): the code family is exactly the two deny codes, and no toolchain code (decision 1)" "found: [$BDS_CODES]"
fi
# Decision 1, in both tools: a broken jq or a broken awk draws nothing, exit 0,
# even for a command that spells the bypass. The payload is built BEFORE the
# stub goes on PATH, because the payload builder is jq.
BDS_BIN="$WORK/bds-broken-tools"; rm -rf "$BDS_BIN"; mkdir -p "$BDS_BIN/jq" "$BDS_BIN/awk"
printf '#!/bin/sh\nexit 1\n' > "$BDS_BIN/jq/jq"; chmod +x "$BDS_BIN/jq/jq"
printf '#!/bin/sh\nexit 1\n' > "$BDS_BIN/awk/awk"; chmod +x "$BDS_BIN/awk/awk"
BDS_P="$(bash_payload 'git commit --no-verify -m x')"
for tool in jq awk; do
  out="$(printf '%s' "$BDS_P" | PATH="$BDS_BIN/$tool:$PATH" CLAUDE_PROJECT_DIR="$BDS" bash "$BDS_HOOK" 2>/dev/null)"; rc=$?
  if [[ -f "$BDS_HOOK" && -z "$out" && "$rc" -eq 0 ]]; then
    ok "successor decision 1: with a broken $tool the hook says nothing and exits 0, rather than deny a command it cannot read"
  else
    bad "successor decision 1: with a broken $tool the hook says nothing and exits 0, rather than deny a command it cannot read" "rc=$rc out=[$(printf '%s' "$out" | cut -c1-120)]"
  fi
done

# --- test 3: ONE READER, BOUNDED AND PINNED ------------------------------------
bds_lexer_block() { # bds_lexer_block <file> -> the assignment block, opening line to closing quote
  awk -v q="'" '$0 == "BYPASS_LEX_AWK=" q { f = 1 } f { print } f && $0 == "}" q { exit }' "$1" 2>/dev/null
}
bds_sha256() { # stdin -> hex digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}
BDS_DIGEST="$(bds_lexer_block "$BDS_HOOK" | bds_sha256)"
BDS_LINES="$(bds_lexer_block "$BDS_HOOK" | grep -c '' || true)"
if [[ "$BDS_DIGEST" == "$BDS_PIN" ]]; then
  ok "successor test 3 (pinned): the lexer block in bypass-deny.sh digests to the pin ($BDS_LINES lines)"
else
  bad "successor test 3 (pinned): the lexer block in bypass-deny.sh digests to the pin" "got $BDS_DIGEST over $BDS_LINES lines, pin $BDS_PIN. A changed lexer is the owner's decision (spec 0142, ruling 1), not an edit to this pin"
fi
BDS_ASSIGN="$(grep -c '^BYPASS_LEX_AWK=' "$BDS_HOOK" 2>/dev/null || true)"
if [[ "$BDS_ASSIGN" == "1" ]] && grep -q 'awk "\$BYPASS_LEX_AWK"' "$BDS_HOOK"; then
  ok "successor test 3 (pinned): the file assigns the lexer once and runs exactly that program"
else
  bad "successor test 3 (pinned): the file assigns the lexer once and runs exactly that program" "assignments=$BDS_ASSIGN"
fi
# --- the wiring (spec 0143 criteria 9 and 10) ----------------------------------
BDS_TMPL="$(grep -v '^{{IF:' "$ROOT/templates/claude/settings.json.tmpl")"
BDS_BASH="$(printf '%s' "$BDS_TMPL" | jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | ((.command | capture("hooks/(?<h>[a-z-]+)\\.sh").h) + "=" + (.timeout | tostring))] | join(" ")' 2>/dev/null)"
if [[ "$BDS_BASH" == "bypass-deny=300" ]]; then
  ok "successor wiring: the template runs bypass-deny.sh as its ONE Bash entry, timeout 300"
else
  bad "successor wiring: the template runs bypass-deny.sh as its ONE Bash entry, timeout 300" "Bash entries: [$BDS_BASH]"
fi
if grep -q '^| `hooks/bypass-deny.sh` | `.claude/hooks/bypass-deny.sh` | always, byte-verbatim' "$ROOT/templates/STAMP-TREE.md" \
   && grep -qE '^add hooks/bypass-deny\.sh +\.claude/hooks/bypass-deny\.sh$' "$ROOT/scripts/stamp.sh"; then
  ok "successor wiring: STAMP-TREE.md carries the row and scripts/stamp.sh the add line that executes it"
else
  bad "successor wiring: STAMP-TREE.md carries the row and scripts/stamp.sh the add line that executes it" "the mapping and the stamp disagree, or one is missing"
fi
if grep -qE '^STAMPED_HOOKS=".* bypass-deny( |")' "$SCRIPTS/refresh-instance.sh" \
   && grep -qE '^[[:space:]]+bypass-deny\)[[:space:]]+ev=PreToolUse;[[:space:]]+tool=Bash' "$SCRIPTS/refresh-instance.sh"; then
  ok "successor wiring: the refresh enumerates the hook and requires it on PreToolUse reaching Bash"
else
  bad "successor wiring: the refresh enumerates the hook and requires it on PreToolUse reaching Bash" "STAMPED_HOOKS or the event arm is missing"
fi
# An instance stamped before this hook existed: the report names it missing AND
# not wired, and --apply delivers the file and refuses to certify the wiring.
BDR="$WORK/bds-refresh"; instance_fixture "$BDR" 2.7.0 current; git_init "$BDR" >/dev/null 2>&1
rm -f "$BDR/.claude/hooks/bypass-deny.sh"
jq '(.hooks.PreToolUse[] | .hooks) |= map(select(((.command // "") | test("bypass-deny")) | not))' "$BDR/.claude/settings.json" > "$BDR/.claude/settings.json.n" && mv "$BDR/.claude/settings.json.n" "$BDR/.claude/settings.json"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$BDR"
if [[ "$SCRIPT_RC" -eq 3 ]] && cmp -s "$HOOKS/bypass-deny.sh" "$BDR/.claude/hooks/bypass-deny.sh" \
   && printf '%s' "$SCRIPT_OUT" | grep -A1 'NOT WIRED IN A WAY' | grep -q 'bypass-deny.sh'; then
  ok "successor wiring: a 2.7.0 instance gets the file under --apply, exit 3, and the hook is named NOT WIRED"
else
  bad "successor wiring: a 2.7.0 instance gets the file under --apply, exit 3, and the hook is named NOT WIRED" "rc=$SCRIPT_RC delivered=$([[ -f "$BDR/.claude/hooks/bypass-deny.sh" ]] && echo yes || echo no): $(printf '%s' "$SCRIPT_OUT" | grep -i 'bypass\|NOT WIRED' | head -2 | tr '\n' ' ' | cut -c1-200)"
fi

fi; shard_region_end
# <<< SHARD-END bypass-deny-0143

# =============================================================================
# THE RETIRED-HOOKS REPORT (spec 0144 criterion 12; spec 0142 section 10 and the
# owner's ruling R-D of 2026-09-13).
#
# 2.8.0 deletes commit-gate.sh and close-gate.sh. A refresh that only knows the
# hooks it STAMPS never sees a file that left the list, and its wiring check only
# asks whether a stamped hook is wired, never whether an entry runs a file that is
# no longer stamped. So an upgraded instance kept both gates on disk and both
# entries in settings.json, running the parsers the release notes say were
# removed, and nothing told its owner (measured in 0142 section 10).
#
# R-D: removal from someone's repository is destructive, so the refresh REPORTS
# what it would remove, with the exact edit, removes NOTHING itself, and names a
# forked copy the same way while leaving it out of the edit. These cases pin all
# of that, and the edit is RUN verbatim, so a printed command that does not do
# what it says fails here. Watched red first against the refresh that predates
# the report (spec 0144, Progress).
# =============================================================================
# rh_instance <dir> <shape: v27|v26|fork> : a current instance carrying what a
# 2.7.0 (or 2.6.x) instance leaves behind after --apply. Helpers stay OUTSIDE the
# region, as every region's helpers do.
rh_instance() {
  local d="$1" shape="$2" h
  instance_fixture "$d" 2.7.0 current
  for h in commit-gate close-gate; do
    printf '#!/usr/bin/env bash\n# the %s shipped through 2.7.0\nexit 0\n' "$h" > "$d/.claude/hooks/$h.sh"
  done
  jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks) |=
        ([{type:"command", timeout:300, command:"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/commit-gate.sh"},
          {type:"command", timeout:300, command:"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/close-gate.sh"}] + .)' \
    "$d/.claude/settings.json" > "$d/.claude/settings.json.n" && mv "$d/.claude/settings.json.n" "$d/.claude/settings.json"
  case "$shape" in
    v26)
      # A 2.6.x Bash group held the two gates and nothing else.
      jq '(.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks) |= map(select((.command | test("bypass-deny")) | not))' \
        "$d/.claude/settings.json" > "$d/.claude/settings.json.n" && mv "$d/.claude/settings.json.n" "$d/.claude/settings.json" ;;
    fork)
      mkdir -p "$d/.claude/hooks/local"
      cp "$d/.claude/hooks/close-gate.sh" "$d/.claude/hooks/local/close-gate.sh"
      printf '# a project edit\n' >> "$d/.claude/hooks/local/close-gate.sh"
      jq '(.hooks.PreToolUse[].hooks[]? | select((.command // "") | test("hooks/close-gate[.]sh$"))).command
            = "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/local/close-gate.sh"' \
        "$d/.claude/settings.json" > "$d/.claude/settings.json.n" && mv "$d/.claude/settings.json.n" "$d/.claude/settings.json" ;;
  esac
  git_init "$d" >/dev/null 2>&1
}
# rh_edit <out-file> : the lines between the report's two markers, verbatim.
rh_edit() {
  awk '/^  --- the edit, verbatim ---$/ {f = 1; next} /^  --- end of the edit ---$/ {f = 0} f { sub(/^    /, ""); print }' "$1"
}
# >>> SHARD-BEGIN retired-hooks-0144 cost=6
if shard_region retired-hooks-0144; then

# a. report mode names both stale files and both stale entries, and exits as it would without them
RHA="$WORK/rh-v27"; rh_instance "$RHA" v27
run_script bash "$SCRIPTS/refresh-instance.sh" "$RHA"
printf '%s' "$SCRIPT_OUT" > "$WORK/rh-v27.report"
RHA_BAD=""
[[ "$SCRIPT_RC" -eq 0 ]] || RHA_BAD="$RHA_BAD rc=$SCRIPT_RC"
grep -q 'retired hooks' "$WORK/rh-v27.report" || RHA_BAD="$RHA_BAD no-retired-section"
for rh_n in '.claude/hooks/commit-gate.sh' '.claude/hooks/close-gate.sh' '"$CLAUDE_PROJECT_DIR"/.claude/hooks/commit-gate.sh' '"$CLAUDE_PROJECT_DIR"/.claude/hooks/close-gate.sh'; do
  grep -qF -- "$rh_n" "$WORK/rh-v27.report" || RHA_BAD="$RHA_BAD unnamed:$rh_n"
done
if [[ -z "$RHA_BAD" ]]; then
  ok "retired a: report mode names both retired gate files and both settings entries that still run them"
else
  bad "retired a: report mode names both retired gate files and both settings entries that still run them" "problems:$RHA_BAD"
fi

# b. --apply removes nothing: both files and settings.json keep their bytes
cp "$RHA/.claude/hooks/commit-gate.sh" "$WORK/rh-cg.before"; cp "$RHA/.claude/hooks/close-gate.sh" "$WORK/rh-cl.before"; cp "$RHA/.claude/settings.json" "$WORK/rh-set.before"
run_script bash "$SCRIPTS/refresh-instance.sh" --apply "$RHA"
if [[ "$SCRIPT_RC" -eq 0 ]] && cmp -s "$WORK/rh-cg.before" "$RHA/.claude/hooks/commit-gate.sh" && cmp -s "$WORK/rh-cl.before" "$RHA/.claude/hooks/close-gate.sh" \
   && cmp -s "$WORK/rh-set.before" "$RHA/.claude/settings.json" && printf '%s' "$SCRIPT_OUT" | grep -q 'retired hooks'; then
  ok "retired b: --apply reports the retired hooks and removes nothing, exit 0 (R-D: the removal is the owner's act)"
else
  bad "retired b: --apply reports the retired hooks and removes nothing, exit 0 (R-D: the removal is the owner's act)" \
      "rc=$SCRIPT_RC files-kept=$(cmp -s "$WORK/rh-cg.before" "$RHA/.claude/hooks/commit-gate.sh" && cmp -s "$WORK/rh-cl.before" "$RHA/.claude/hooks/close-gate.sh" && echo yes || echo no) settings-kept=$(cmp -s "$WORK/rh-set.before" "$RHA/.claude/settings.json" && echo yes || echo no)"
fi

# c. the printed edit, run verbatim, removes exactly what it named and nothing else
rh_edit "$WORK/rh-v27.report" > "$WORK/rh-v27.edit"
RHC_BAD=""
[[ -s "$WORK/rh-v27.edit" ]] || RHC_BAD="$RHC_BAD no-edit-printed"
RHC_OTHERS_BEFORE="$(jq -c '[.hooks | to_entries[] | .value[]? | .hooks[]? | .command | select(test("gate[.]sh$") | not)] | sort' "$RHA/.claude/settings.json" 2>/dev/null)"
( cd "$RHA" && bash "$WORK/rh-v27.edit" ) >/dev/null 2>&1 || RHC_BAD="$RHC_BAD edit-exited-nonzero"
[[ ! -e "$RHA/.claude/hooks/commit-gate.sh" && ! -e "$RHA/.claude/hooks/close-gate.sh" ]] || RHC_BAD="$RHC_BAD a-file-remains"
jq -e . "$RHA/.claude/settings.json" >/dev/null 2>&1 || RHC_BAD="$RHC_BAD settings-unparseable"
[[ "$(jq -r '[.. | .command? // empty | select(test("(commit|close)-gate[.]sh"))] | length' "$RHA/.claude/settings.json" 2>/dev/null)" == "0" ]] || RHC_BAD="$RHC_BAD an-entry-remains"
[[ "$(jq -c '[.hooks | to_entries[] | .value[]? | .hooks[]? | .command | select(test("gate[.]sh$") | not)] | sort' "$RHA/.claude/settings.json" 2>/dev/null)" == "$RHC_OTHERS_BEFORE" ]] || RHC_BAD="$RHC_BAD another-entry-moved"
run_script bash "$SCRIPTS/refresh-instance.sh" "$RHA"
printf '%s' "$SCRIPT_OUT" | grep -q 'retired hooks' && RHC_BAD="$RHC_BAD still-reported-after-the-edit"
if [[ -z "$RHC_BAD" ]]; then
  ok "retired c: the printed edit, run verbatim from the instance root, removes both files and both entries and nothing else, and the report then goes quiet"
else
  bad "retired c: the printed edit, run verbatim from the instance root, removes both files and both entries and nothing else, and the report then goes quiet" "problems:$RHC_BAD"
fi

# d. a forked copy is reported as a fork and left out of the edit
RHD="$WORK/rh-fork"; rh_instance "$RHD" fork
run_script bash "$SCRIPTS/refresh-instance.sh" "$RHD"
printf '%s' "$SCRIPT_OUT" > "$WORK/rh-fork.report"
rh_edit "$WORK/rh-fork.report" > "$WORK/rh-fork.edit"
( cd "$RHD" && bash "$WORK/rh-fork.edit" ) >/dev/null 2>&1
RHD_BAD=""
grep -qi 'fork' "$WORK/rh-fork.report" && grep -qF '.claude/hooks/local/close-gate.sh' "$WORK/rh-fork.report" || RHD_BAD="$RHD_BAD fork-not-named"
grep -qF 'local/close-gate.sh' "$WORK/rh-fork.edit" && RHD_BAD="$RHD_BAD fork-inside-the-edit"
[[ -f "$RHD/.claude/hooks/local/close-gate.sh" ]] || RHD_BAD="$RHD_BAD fork-file-deleted"
[[ "$(jq -r '[.. | .command? // empty | select(test("local/close-gate[.]sh"))] | length' "$RHD/.claude/settings.json" 2>/dev/null)" == "1" ]] || RHD_BAD="$RHD_BAD fork-entry-removed"
if [[ -z "$RHD_BAD" ]]; then
  ok "retired d: a forked copy of a retired gate is reported as a fork, kept out of the printed edit, and survives running it"
else
  bad "retired d: a forked copy of a retired gate is reported as a fork, kept out of the printed edit, and survives running it" "problems:$RHD_BAD"
fi

# e. a 2.6.x Bash group that held only the two gates: the edit leaves no empty group behind
RHE="$WORK/rh-v26"; rh_instance "$RHE" v26
run_script bash "$SCRIPTS/refresh-instance.sh" "$RHE"
printf '%s' "$SCRIPT_OUT" > "$WORK/rh-v26.report"
rh_edit "$WORK/rh-v26.report" > "$WORK/rh-v26.edit"
( cd "$RHE" && bash "$WORK/rh-v26.edit" ) >/dev/null 2>&1
if jq -e '[.hooks | to_entries[] | .value[]? | select((.hooks // []) | length == 0)] | length == 0' "$RHE/.claude/settings.json" >/dev/null 2>&1 \
   && [[ "$(jq -r '[.. | .command? // empty | select(test("(commit|close)-gate[.]sh"))] | length' "$RHE/.claude/settings.json" 2>/dev/null)" == "0" ]]; then
  ok "retired e: where the Bash group held only the two gates, the edit removes the emptied group and the file still parses"
else
  bad "retired e: where the Bash group held only the two gates, the edit removes the emptied group and the file still parses" "$(jq -c '.hooks.PreToolUse' "$RHE/.claude/settings.json" 2>&1 | cut -c1-200)"
fi

# f. control: an instance with nothing retired prints no retired section
RHF="$WORK/rh-clean"; instance_fixture "$RHF" 2.7.0 current; git_init "$RHF" >/dev/null 2>&1
run_script bash "$SCRIPTS/refresh-instance.sh" "$RHF"
if [[ "$SCRIPT_RC" -eq 0 ]] && ! printf '%s' "$SCRIPT_OUT" | grep -q 'retired hooks'; then
  ok "retired f: control, an instance with no retired hook prints no retired section"
else
  bad "retired f: control, an instance with no retired hook prints no retired section" "rc=$SCRIPT_RC: $(printf '%s' "$SCRIPT_OUT" | grep -i retired | head -2 | tr '\n' ' ')"
fi

fi; shard_region_end
# <<< SHARD-END retired-hooks-0144
