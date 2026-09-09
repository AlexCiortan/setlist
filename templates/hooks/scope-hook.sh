#!/usr/bin/env bash
# SDD scope hook: PreToolUse on matcher "Write|Edit|MultiEdit|NotebookEdit",
# stamped into the instance. (MultiEdit is absent from current Claude Code,
# folded into Edit; it stays in the matcher defensively for older harnesses,
# where matching a tool that never fires costs nothing and missing one that
# does costs the trunk. NotebookEdit is live and sends notebook_path, not
# file_path; both are read below.)
# Enforces Part 6: feature code never lands directly on the trunk branch
# (read from .claude/sdd.json, never assumed to be main).
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make the
# scaffolded flag, the trunk name, and the role paths all read empty, so every
# check fell through and feature code could land on the trunk unchallenged.
# Because none of those facts are readable without jq, the fail-closed path
# denies every Write and Edit inside a stamped instance rather than guessing;
# Bash is untouched, so the session can install jq and continue.
# Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

# THE scope ADVISES, IT DOES NOT VETO (the advisory-gate decision, RATIFIED 2026-08-04).
#
# This function used to emit permissionDecision "deny" and hold a hard veto over
# the session. It now emits "allow" and reports what it WOULD have decided in a
# machine-readable field. The guarantee did not move with it: it stayed where
# edition v1.7 put it, in git's own hooks, which run from git's internal state
# after argument parsing and ref resolution and have nothing left to spell
# around.
#
# WHY, in one number. Across four adversarial reviews on 2026-08-03 and 2026-08-04,
# five of six BLOCKERs and three MAJORs were in parser code written that same
# day to fix the previous leg: roughly a fifth of parser repairs introduced a
# new defect. That rate is a property of changing a shell command parser at all,
# not of any one change, and while the parsers could DENY, every one of those
# defects was a release blocker. The README has told users this layer only warns
# since v1.7; the leg filed a finding because it did not. The mechanism is the
# half that moved.
#
# THE CONTRACT, frozen with the parsers:
#   permissionDecision   ALWAYS "allow"
#   setlistAdvisory      {gate, verdict: deny|allow, code, reason}
#   systemMessage        the reason, again, because permissionDecisionReason is
#                        documented as reaching the USER rather than the model
#                        when the decision is allow, and the point of a warning
#                        is that the session sees it.
#
# `setlistAdvisory.verdict` is evidence about THIS layer only. Every
# guarantee-layer check binds to observed repository state instead, because a
# guarantee that asked the parser whether the parser was right would be the
# laundering defect this cycle is a record of, one layer up.
# THE CODE IS EXTRACTED BY THE SHELL, NOT BY sed (KL11, the 2.5.0 leg's F12;
# fixed 2026-09-07, spec 0132 cluster C). Every emitter below used
# `sed -n 's/.*\[\([A-Z][A-Z0-9-]*\)\].*/\1/p'`, and under a sed that exits 0
# printing nothing the deny still fired with the code in its reason text and
# `setlistAdvisory.code` EMPTY: exactly the reader that keys on the field lost
# it, on exactly the deny that reports the broken tool. Parameter expansion
# depends on nothing outside bash. The semantics are sed's: the LAST bracketed
# token of the form [A-Z][A-Z0-9-]* wins, and a bracket holding anything else
# is skipped. Pinned red-first under a silent sed for all three gates.
adv_code_of() { # adv_code_of <reason> -> sets ADV_CODE
  local rest="$1" cand
  ADV_CODE=""
  while [[ "$rest" == *"["* ]]; do
    rest="${rest#*\[}"
    [[ "$rest" == *"]"* ]] || break
    cand="${rest%%\]*}"
    case "$cand" in
      [A-Z]*) case "$cand" in *[!A-Z0-9-]*) ;; *) ADV_CODE="$cand" ;; esac ;;
    esac
  done
}
advise() {
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":%s},"systemMessage":%s,"setlistAdvisory":{"gate":"scope","verdict":"deny","code":%s,"reason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)" \
    "$(printf 'setlist %s' "$1" | jq -Rs .)" \
    "$(printf '%s' "$ADV_CODE" | jq -Rs .)" \
    "$(printf '%s' "$1" | jq -Rs .)"
  # fail-open-ok: the gate is advisory by design as of 2026-08-04. It has
  # reported its verdict and the session proceeds; the git hooks carry the
  # guarantee.
  exit 0
}
deny() { advise "$1"; }

# HISTORY: ruling SC-01 (plugin 2.3.0), in the framework source's private hook-rulings record: Advise with a fixed literal reason, for the paths where jq is unavailable to.
advise_literal() {
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"setlist %s","setlistAdvisory":{"gate":"scope","verdict":"deny","code":"%s","reason":"%s"}}\n' "$1" "$1" "$ADV_CODE" "$1"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$1"; }

# HISTORY: ruling SC-02 (plugin 2.4.0), in the framework source's private hook-rulings record: THE INPUT IS READ BY THE SHELL, NOT BY cat (spec 0130; the 2.4.0 leg's F12).
IFS= read -r -d '' INPUT || true
# HISTORY: ruling SC-03 (undated), in the framework source's private hook-rulings record: Normalize to an absolute path so the prefix strip below works whether.
PROJ_GIVEN="${CLAUDE_PROJECT_DIR:-.}"
PROJ_GIVEN="${PROJ_GIVEN%/}"
PROJ="$(cd "$PROJ_GIVEN" && pwd)"
SDD_JSON="$PROJ/.claude/sdd.json"

# Not an SDD instance, or pre-stamp: stay silent.
# fail-open-ok: no sdd.json means no framework contract to enforce; gating a
# repo that never opted in would make the plugin unusable outside instances.
[[ -f "$SDD_JSON" ]] || exit 0

# HISTORY: ruling SC-04 (plugin v1.7), in the framework source's private hook-rulings record: Decide WITHOUT jq when it is absent, and report.
if ! command -v jq >/dev/null 2>&1; then
  deny_literal "scope hook [SH-NO-JQ]: jq is not installed, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk; it would otherwise allow feature code straight onto the trunk unchallenged. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi
if [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  # OUTPUT compared, not only status (spec 0130; the 2.4.0 leg's F6): a jq that
  # exits 0 printing nothing walked past `jq -e .` and this hook refused under a
  # config code for a file that was fine.
  deny_literal "scope hook [SH-JQ-BROKEN]: jq is installed but does not work on this machine (it exits nonzero, or exits 0 and prints nothing), so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# HISTORY: ruling SC-05 (plugin v1.7), in the framework source's private hook-rulings record: AND THE REST OF THE TOOLCHAIN, which this hook never received (1.1.0 leg.
SH_TOOLCHAIN_BROKEN=""
_shp="$(printf 'x\n' | awk '{ print }' 2>/dev/null)" || _shp=""
[[ "$_shp" == "x" ]] || SH_TOOLCHAIN_BROKEN="awk"
if [[ -z "$SH_TOOLCHAIN_BROKEN" ]]; then
  _shp="$(printf 'x\n' | sed 's/x/y/' 2>/dev/null)" || _shp=""
  [[ "$_shp" == "y" ]] || SH_TOOLCHAIN_BROKEN="sed"
fi
if [[ -z "$SH_TOOLCHAIN_BROKEN" ]]; then
  _shp="$(printf 'x\n' | tr 'x' 'y' 2>/dev/null)" || _shp=""
  [[ "$_shp" == "y" ]] || SH_TOOLCHAIN_BROKEN="tr"
fi
if [[ -z "$SH_TOOLCHAIN_BROKEN" ]]; then
  _shp="$(printf 'x\n' | grep -E '^x$' 2>/dev/null)" || _shp=""
  [[ "$_shp" == "x" ]] || SH_TOOLCHAIN_BROKEN="grep"
fi
if [[ -n "$SH_TOOLCHAIN_BROKEN" ]]; then
  deny_literal "scope hook [SH-NO-TOOLCHAIN]: $SH_TOOLCHAIN_BROKEN is installed but does not work on this machine, so this gate cannot normalise the path it is meant to check and would otherwise allow feature code straight onto the trunk unchallenged. Run '$SH_TOOLCHAIN_BROKEN --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# HISTORY: ruling SC-06 (plugin 1.0.8), in the framework source's private hook-rulings record: The config must PARSE. jq being installed is not the same as sdd.json being.
if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal "scope hook [SH-SDD-SHAPE]: .claude/sdd.json is not a single JSON OBJECT (it does not parse, or it is an array, or it contains more than one document), so this gate cannot read the trunk name or the role paths and cannot tell whether this write lands on the trunk. It would otherwise allow feature code straight onto the trunk unchallenged. Fix the file (jq -s . .claude/sdd.json shows both the syntax and how many documents it holds), then retry. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi

# HISTORY: ruling SC-07 (plugin 2.3.0), in the framework source's private hook-rulings record: Active only after /scaffold flips the flag, so the one-time bootstrap.
SH_SCAFFOLDED="$(jq -r 'if (.scaffolded == null) then "off" elif (.scaffolded == true) then "on" elif (.scaffolded == false) then "off" else "shape" end' "$SDD_JSON" 2>/dev/null)" || SH_SCAFFOLDED=""
if [[ "$SH_SCAFFOLDED" == "shape" ]]; then
  deny_literal "scope hook [SH-SCAFFOLDED-SHAPE]: .claude/sdd.json has a scaffolded value that is present and is not a boolean, so this gate cannot tell whether the trunk rule is in force and would otherwise stand down in silence, allowing feature code straight onto the trunk. Set scaffolded to true or false (a JSON boolean, not a quoted string). Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi
if [[ -z "$SH_SCAFFOLDED" ]]; then
  deny_literal "scope hook [SH-SCAFFOLDED-UNREADABLE]: the scaffolded flag in .claude/sdd.json could not be read (the reader returned no verdict), so whether the trunk rule is in force is not established. Refusing to proceed on an unread configuration rather than standing down in silence. Check jq --version and jq . .claude/sdd.json. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi
# fail-open-ok: pre-scaffold, the trunk rule is deliberately not yet in force.
# Reached only for a value this gate READ and understood as false or absent.
[[ "$SH_SCAFFOLDED" == "on" ]] || exit 0

# HISTORY: ruling SC-08 (plugin 1.0.8), in the framework source's private hook-rulings record: The trunk branch name is recorded in sdd.json at stamp or upgrade time.
TRUNK="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "$SDD_JSON" 2>/dev/null)" # fail-open-ok: an unreadable value yields the empty string, which the check on the next line refuses
[[ -n "$TRUNK" ]] || deny "scope hook [SH-TRUNK-INVALID]: .claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."

# HISTORY: ruling SC-09 (plugin 1.0.8), in the framework source's private hook-rulings record: THE TRUNK VALUE MUST NAME A LOCAL BRANCH, not merely be a non-empty string.
if [[ -n "$TRUNK" ]] && ! git -C "$PROJ" show-ref --verify --quiet "refs/heads/$TRUNK" 2>/dev/null; then
  TRUNK_FULL="$(git -C "$PROJ" rev-parse --symbolic-full-name "$TRUNK" 2>/dev/null || true)" # fail-open-ok: an unresolvable spelling leaves TRUNK unchanged and is refused below
  case "$TRUNK_FULL" in
    refs/heads/*)
      TRUNK="${TRUNK_FULL#refs/heads/}"
      ;;
    refs/remotes/*)
      TRUNK_CAND="${TRUNK_FULL#refs/remotes/}"
      TRUNK_CAND="${TRUNK_CAND#*/}"
      if git -C "$PROJ" show-ref --verify --quiet "refs/heads/$TRUNK_CAND" 2>/dev/null; then
        TRUNK="$TRUNK_CAND"
      fi
      ;;
  esac
  if ! git -C "$PROJ" show-ref --verify --quiet "refs/heads/$TRUNK" 2>/dev/null \
     && [[ -n "$(git -C "$PROJ" for-each-ref --count=1 refs/heads 2>/dev/null)" ]]; then
    deny "scope hook [SH-TRUNK-NOT-A-BRANCH]: .claude/sdd.json records trunk \"$TRUNK\", which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which is what the upgrade skill's own detection command returns."
  fi
fi
# HISTORY: ruling SC-10 (plugin 1.1.0), in the framework source's private hook-rulings record: A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 leg, second run, then again.
canonical_branch() { # canonical_branch <name> -> git's stored spelling of it
  local name="$1" ci
  [[ -n "$name" ]] || return 0
  if git -C "$PROJ" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
     | grep -qxF -- "$name"; then
    printf '%s' "$name"; return 0
  fi
  ci="$(git -C "$PROJ" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
        | awk -v n="$name" 'tolower($0) == tolower(n) { print; exit }')" # fail-open-ok: no match leaves this empty and the name is returned unchanged, which is the behaviour for any branch that is not a case variant
  if [[ -n "$ci" ]]; then printf '%s' "$ci"; return 0; fi
  printf '%s' "$name"
}
# HISTORY: ruling SC-11 (plugin v1.9), in the framework source's private hook-rulings record: GIT IS A DEPENDENCY, AND ITS VERSION IS PART OF IT (leg F5).
_shgit="$(git -C "$PROJ" rev-parse --git-dir 2>/dev/null)" || _shgit=""
if [[ -z "$_shgit" ]]; then
  deny_literal "scope hook [SH-NO-GIT]: git is not usable here (it is missing, broken, or this is not a git repository), so this gate cannot tell which branch this write lands on and would otherwise allow feature code straight onto the trunk unchallenged. Run 'git rev-parse --git-dir' in this directory to see the failure; a missing binary, a broken dynamic library, a wrong-architecture build and a directory that is not a repository all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

BRANCH="$(git -C "$PROJ" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: a detached HEAD yields empty here exactly as it did before, and a detached HEAD is not the trunk
BRANCH="$(canonical_branch "$BRANCH")"
TRUNK="$(canonical_branch "$TRUNK")"
# fail-open-ok: off the trunk, writes are the point of a spec branch; this
# gate only guards the trunk. (Detached HEAD reads as empty, never equals the
# trunk, and passes: named in Known limitations.)
[[ "$BRANCH" == "$TRUNK" ]] || exit 0

# HISTORY: ruling SC-12 (plugin 1.0.3), in the framework source's private hook-rulings record: file_path for Write/Edit/MultiEdit; notebook_path for NotebookEdit.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
if [[ -z "$FILE_PATH" ]]; then
  deny "scope hook [SH-NO-PATH]: this tool call carries neither file_path nor notebook_path, so the gate cannot tell whether the write lands on $TRUNK and will not guess. If the harness has changed its tool-input shape, update .claude/hooks/scope-hook.sh (and report it); removing this hook entry from .claude/settings.json is the deliberate way to work without the gate."
fi

# HISTORY: ruling SC-13 (undated), in the framework source's private hook-rulings record: Role paths: a string or a list of strings (multi-prefix repos, and flat-root.
if [[ "$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$SDD_JSON" 2>/dev/null)" == "bad" ]]; then
  deny "scope hook [SH-ROLES-SHAPE]: .claude/sdd.json has a \"roles\" value that is not an object, so the role paths this hook guards cannot be read and every write to the trunk would silently pass. Set \"roles\" to an object such as {\"src\": \"src\", \"tests\": \"tests\"}, or remove the key to accept the defaults."
fi
ROLE_PATHS="$(jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$SDD_JSON")"

# HISTORY: ruling SC-14 (undated), in the framework source's private hook-rulings record: Canonicalize before comparing.
REL="$(printf '%s' "$FILE_PATH" | tr -s '/')"
REL="${REL#"$PROJ"/}"
REL="${REL#"$PROJ_GIVEN"/}"
while [[ "$REL" == ./* ]]; do REL="${REL#./}"; done

# HISTORY: ruling SC-15 (undated), in the framework source's private hook-rulings record: Slash squeezing and prefix stripping are not enough, because two spellings of.
lex_norm() { # lex_norm <relative-path> -> the same path with . and .. collapsed
  local p="$1" out="" seg
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ''|.) continue ;;
      ..)   [[ -n "$out" ]] && out="${out%/*}" ;;
      *)    out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out#/}"
}

canon_rel() { # canon_rel <path> -> path relative to the real project root
  local p="$1" d b missing="" real
  case "$p" in /*) ;; *) p="$PROJ/$p" ;; esac
  d="$(dirname "$p")"; b="$(basename "$p")"
  while [[ ! -d "$d" && "$d" != "/" && "$d" != "." && -n "$d" ]]; do
    missing="$(basename "$d")/$missing"; d="$(dirname "$d")"
  done
  real="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s%s' "$real" "$missing" "$b"
}
# PROJ is canonicalised the same way or the prefix strip cannot match: on macOS
# TMPDIR itself lives behind a symlink, so a resolved path and an unresolved
# project root never share a prefix.
PROJ_REAL="$(cd "$PROJ" 2>/dev/null && pwd -P || printf '%s' "$PROJ")" # fail-open-ok: an unreachable project dir falls back to the given path, and the string comparison below then behaves exactly as it did before canonicalisation existed rather than skipping the check
REL="$(lex_norm "$REL")"

# HISTORY: ruling SC-16 (undated), in the framework source's private hook-rulings record: Physical resolution on top, for what lexical normalisation cannot see.
REL_PHYS=""
CANON="$(canon_rel "$FILE_PATH" 2>/dev/null || true)" # fail-open-ok: a path that cannot be resolved leaves this empty, and the lexically normalised REL above is still checked against every role path below
if [[ -n "$CANON" ]]; then
  case "$CANON" in
    "$PROJ_REAL"/*) REL_PHYS="${CANON#"$PROJ_REAL"/}" ;;
    # Resolves outside the project entirely. The trunk rule is about THIS
    # repository's role paths, so there is nothing here to govern, and no
    # verdict is invented from it.
  esac
fi
# HISTORY: ruling SC-17 (plugin 1.1.0), in the framework source's private hook-rulings record: THE ROLE PATH IS NORMALISED, NOT JUST TRIMMED (1.1.0 adversarial review, second run).
#
# LOCKSTEP: scripts/trunk-audit.sh and setlist-hook-lib.sh normalise identically.
# Fixing only this file would leave the backstop blind in the same way, which is
# leg 5's F8 exactly.
while IFS= read -r ROLE; do
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  while [[ "$ROLE" == ./* ]]; do ROLE="${ROLE#./}"; done
  ROLE="$(printf '%s' "$ROLE" | tr -s '/')"
  ROLE="${ROLE#/}"
  ROLE="${ROLE%/}"
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  if [[ "$REL" == "$ROLE"/* || "$REL" == "$ROLE" ]] \
     || [[ -n "$REL_PHYS" && ( "$REL_PHYS" == "$ROLE"/* || "$REL_PHYS" == "$ROLE" ) ]]; then
    deny "[SH-TRUNK-WRITE] feature code never lands directly on $TRUNK; open a spec or chore branch via /setlist:checkpoint."
  fi
done <<< "$ROLE_PATHS"
# fail-open-ok: the write matched no role path; docs-only trunk writes are
# the allowed case the whole loop exists to distinguish.
exit 0
