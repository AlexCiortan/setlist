#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Setlist scope hook: PreToolUse on matcher "Write|Edit|MultiEdit|NotebookEdit",
# stamped into the instance. (MultiEdit is absent from current Claude Code,
# folded into Edit; it stays in the matcher defensively for older harnesses,
# where matching a tool that never fires costs nothing and missing one that
# does costs the trunk. NotebookEdit is live and sends notebook_path, not
# file_path; both are read below.)
# Enforces Part 6: feature code never lands directly on the trunk branch
# (read from .claude/sdd.json, never assumed to be main).
# Output: one JSON object on stdout, exit 0 on every path; the reason reaches the
# agent through additionalContext. It answers no permission prompt (spec 0181).
# Requires jq: a missing jq used to make the scaffolded flag, the trunk name,
# and the role paths all read empty, so every check fell through and feature
# code could land on the trunk unchallenged. Because none of those facts are
# readable without jq, the jq-less path REPORTS rather than guesses: it emits
# the SH-NO-JQ code below (unbracketed here on purpose: the suite reads a
# bracketed code twice in this file as two denials sharing one code), whose
# own text says gates report their verdict and PERMIT, this hook having been
# advisory since v1.7, and the git hooks are what refuse.
# Bash is untouched, so the session can install jq and continue.
# Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

# THE scope ADVISES, IT DOES NOT VETO (the advisory-gate decision, RATIFIED 2026-08-04).
#
# ADVISORIES PERSUADE; HOOKS REFUSE. Since 2.9.0 the reason below reaches the
# agent's context (additionalContext, measured delivered on PreToolUse at Claude
# Code 2.1.274, spec 0151), and an agent that receives it may still judge the
# write harmless and proceed: a delivered warning is not an enforcement channel.
# What refuses is git's own hooks, at commit, merge and push.
#
# This function used to deny the write and hold a hard veto over the session.
# From 2026-08-04 it permitted the write and reported what it WOULD have decided in
# a machine-readable field. The guarantee did not move with it: it stayed where
# edition v1.7 put it, in git's own hooks, which run from git's internal state
# after argument parsing and ref resolution and have nothing left to spell
# around.
#
# THE PERMISSION PROMPT IS THE USER'S (spec 0181, the directory review of
# 2026-10-06). From 2026-08-04 the permit was a permission decision printed in the
# hook's output, and a PreToolUse hook that prints a decision ANSWERS the user's
# permission prompt: every write this hook spoke about was approved on the user's
# behalf. The hook now prints no decision field and no decision reason on any
# path, so the harness asks the user exactly as it would with no hook at all, in
# whatever permission mode the user chose. Its verdict, its code and its reason are
# unchanged; only the answer to the prompt left.
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
#   hookSpecificOutput   {hookEventName: "PreToolUse", additionalContext} and
#                        nothing else: NO decision field and NO decision reason
#                        (spec 0181), so the permission prompt stays the user's.
#   additionalContext    the reason, prefixed, for the MODEL (design P, spec
#                        0151): documented as added to Claude's context beside the
#                        tool result, measured delivered on this event at Claude
#                        Code 2.1.274, and re-measured with no decision field by
#                        spec 0181.
#   setlistAdvisory      {gate, verdict: deny|allow, code, reason}
# `systemMessage` carried the reason until 2.9.0 and was measured never
# reaching the model; it left with design P. The decision's own reason, kept for
# the user's view by the owner's ruling E-3 of 2026-09-17, left with the decision
# in spec 0181: it was the reason of an answer the hook no longer gives.
#
# `setlistAdvisory.verdict` is evidence about THIS layer only. Every
# guarantee-layer check binds to observed repository state instead, because a
# guarantee that asked the parser whether the parser was right would be the
# laundering defect this cycle is a record of, one layer up.
# THE CODE IS THE CALLER'S, NEVER READ BACK OUT OF THE REASON (spec 0171, L2 F20
# of the 2.10.0 second leg; the twin of that release's round-2 F19 fix in the
# Stop hook). Until 2.4.0 every emitter extracted it with sed, and under a sed
# that exits 0 printing nothing the field went empty (KL11, the 2.5.0 leg's F12);
# 2.6.0 moved the extraction into parameter expansion, the LAST well-formed
# bracketed token winning. But a reason can quote the repository's own text,
# and the not-a-branch reason quotes the recorded trunk, so a trunk carrying a
# bracketed token became setlistAdvisory.code. Each emitter now takes the code
# as its first argument, and the reason keeps its own bracket, so a reader of
# either sees the same code. No sed and no scan: KL11's case holds by
# construction.
advise() { # advise <code> <reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s},"setlistAdvisory":{"gate":"scope","verdict":"deny","code":%s,"reason":%s}}\n' \
    "$(printf 'setlist scope hook (advisory; the write proceeds): %s' "$2" | jq -Rs .)" \
    "$(printf '%s' "$1" | jq -Rs .)" \
    "$(printf '%s' "$2" | jq -Rs .)"
  # fail-open-ok: the gate is advisory by design as of 2026-08-04. It has
  # reported its verdict, answered no permission prompt, and the session proceeds
  # as the user's permission mode decides; the git hooks carry the guarantee.
  exit 0
}
deny() { advise "$@"; }

# HISTORY: ruling SC-01 (plugin 2.3.0): Advise with a fixed literal reason, for the paths where jq is unavailable to escape one.
advise_literal() { # advise_literal <code> <fixed reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"setlist scope hook (advisory; the write proceeds): %s"},"setlistAdvisory":{"gate":"scope","verdict":"deny","code":"%s","reason":"%s"}}\n' "$2" "$1" "$2"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$@"; }

# THE WINDOWS SPELLINGS OF A PATH, READ AS ONE (spec 0179, cause N). Under Git Bash a
# path can arrive as C:\x\y, C:/x/y or /c/x/y (Claude Code's file_path and cwd,
# CLAUDE_PROJECT_DIR, git's --git-common-dir, a recorded core.hooksPath), and a reader
# that tested for a leading / read the first two as relative and matched nothing.
# Under MSYS or Cygwin (OSTYPE) all three become git's own spelling, C:/x/y, its
# backslashes read as separators: that is the one spelling whose `cd -P` answers the
# same form as the project root's wherever a mount covers the path (Git Bash mounts
# the user's Temp at /tmp, and `cd -P /c/...` there answers /c/..., `cd -P C:/...`
# answers /tmp/..., measured on the probe machine). A reader then treats a leading
# drive as absolute. On every other platform, and for every other path, the value
# comes back unchanged, because there "C:" is an ordinary directory name and a
# backslash an ordinary character. The result is left in SLH_PATH_NORMED, so a
# caller pays no subshell. LOCKSTEP: byte-identical in scope-hook.sh and
# setlist-hook-lib.sh, asserted.
slh_path_norm() { # slh_path_norm <path> -> SLH_PATH_NORMED
  local p="$1"
  case "${OSTYPE:-}" in
    msys*|cygwin*)
      case "$p" in
        [A-Za-z]:[\\/]*|[A-Za-z]:) p="${p//\\//}"; [ "${#p}" -eq 2 ] && p="$p/" ;;
        /[A-Za-z]/*|/[A-Za-z]) p="${p:1:1}:/${p:3}" ;;
      esac ;;
  esac
  SLH_PATH_NORMED="$p"
}
# slh_path_abs <path>: rc 0 for an absolute path, a drive spelling counting only under MSYS
# or Cygwin, where slh_path_norm writes one; elsewhere C:/x stays relative. LOCKSTEP too.
slh_path_abs() { case "$1" in /*) return 0 ;; [A-Za-z]:/*) case "${OSTYPE:-}" in msys*|cygwin*) return 0 ;; esac ;; esac; return 1; }
# HISTORY: ruling SC-02 (plugin 2.4.0): THE INPUT IS READ BY THE SHELL, NOT BY cat (spec 0130; the 2.4.0 leg's F12).
IFS= read -r -d '' INPUT || true
# HISTORY: ruling SC-03 (undated): Normalize to an absolute path so the prefix strip below works whether file_path arrives absolute or relative (hooks run with cwd = project dir).
PROJ_GIVEN="${CLAUDE_PROJECT_DIR:-.}"
PROJ_GIVEN="${PROJ_GIVEN%/}"
slh_path_norm "$PROJ_GIVEN"; PROJ_GIVEN="$SLH_PATH_NORMED"
PROJ="$(cd "$PROJ_GIVEN" && pwd)"
SDD_JSON="$PROJ/.claude/sdd.json"

# Not a Setlist instance, or pre-stamp: stay silent.
# fail-open-ok: no sdd.json means no framework contract to enforce; gating a
# repo that never opted in would make the plugin unusable outside instances.
[[ -f "$SDD_JSON" ]] || exit 0

# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
# HISTORY: ruling SC-04 (plugin v1.7): Decide WITHOUT jq when it is absent, and report.
if ! command -v jq >/dev/null 2>&1; then
  deny_literal SH-NO-JQ "scope hook [SH-NO-JQ]: jq is not installed, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk; it would otherwise allow feature code straight onto the trunk unchallenged. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi
if [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  # OUTPUT compared, not only status (spec 0130; the 2.4.0 leg's F6): a jq that
  # exits 0 printing nothing walked past `jq -e .` and this hook refused under a
  # config code for a file that was fine.
  deny_literal SH-JQ-BROKEN "scope hook [SH-JQ-BROKEN]: jq is installed but does not work on this machine (it exits nonzero, or exits 0 and prints nothing), so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# HISTORY: ruling SC-05 (plugin v1.7): AND THE REST OF THE TOOLCHAIN, which this hook never received (1.1.0 leg, fourth run, F19).
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
  deny_literal SH-NO-TOOLCHAIN "scope hook [SH-NO-TOOLCHAIN]: $SH_TOOLCHAIN_BROKEN is installed but does not work on this machine, so this gate cannot normalise the path it is meant to check and would otherwise allow feature code straight onto the trunk unchallenged. Run '$SH_TOOLCHAIN_BROKEN --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# HISTORY: ruling SC-06 (plugin 1.0.8): The config must PARSE. jq being installed is not the same as sdd.json being readable:
if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal SH-SDD-SHAPE "scope hook [SH-SDD-SHAPE]: .claude/sdd.json is not a single JSON OBJECT (it does not parse, or it is an array, or it contains more than one document), so this gate cannot read the trunk name or the role paths and cannot tell whether this write lands on the trunk. It would otherwise allow feature code straight onto the trunk unchallenged. Fix the file (jq -s . .claude/sdd.json shows both the syntax and how many documents it holds), then retry. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi

# HISTORY: ruling SC-07 (plugin 2.3.0): Active only after /scaffold flips the flag, so the one-time bootstrap scaffold on main is not blocked.
SH_SCAFFOLDED="$(jq -r 'if (.scaffolded == null) then "off" elif (.scaffolded == true) then "on" elif (.scaffolded == false) then "off" else "shape" end' "$SDD_JSON" 2>/dev/null)" || SH_SCAFFOLDED=""
if [[ "$SH_SCAFFOLDED" == "shape" ]]; then
  deny_literal SH-SCAFFOLDED-SHAPE "scope hook [SH-SCAFFOLDED-SHAPE]: .claude/sdd.json has a scaffolded value that is present and is not a boolean, so this gate cannot tell whether the trunk rule is in force and would otherwise stand down in silence, allowing feature code straight onto the trunk. Set scaffolded to true or false (a JSON boolean, not a quoted string). Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi
if [[ -z "$SH_SCAFFOLDED" ]]; then
  deny_literal SH-SCAFFOLDED-UNREADABLE "scope hook [SH-SCAFFOLDED-UNREADABLE]: the scaffolded flag in .claude/sdd.json could not be read (the reader returned no verdict), so whether the trunk rule is in force is not established. Refusing to proceed on an unread configuration rather than standing down in silence. Check jq --version and jq . .claude/sdd.json. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi
# fail-open-ok: pre-scaffold, the trunk rule is deliberately not yet in force.
# Reached only for a value this gate READ and understood as false or absent.
[[ "$SH_SCAFFOLDED" == "on" ]] || exit 0

# HISTORY: ruling SC-08 (plugin 1.0.8): The trunk branch name is recorded in sdd.json at stamp or upgrade time (F6-2); main is only the fallback for instances stamped before the field existed.
TRUNK="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "$SDD_JSON" 2>/dev/null)" # fail-open-ok: an unreadable value yields the empty string, which the check on the next line refuses
[[ -n "$TRUNK" ]] || deny SH-TRUNK-INVALID "scope hook [SH-TRUNK-INVALID]: .claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."

# HISTORY: ruling SC-09 (plugin 1.0.8): THE TRUNK VALUE MUST NAME A LOCAL BRANCH, not merely be a non-empty string (F1 of the second 1.0.8 leg).
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
    # THE RECORDED TRUNK IS THE REPOSITORY'S TEXT, AND THIS REASON IS READ BY THE
    # MODEL (spec 0171, sweep I2 of 0169, the site of L2 F20). It failed to name a
    # branch, so git's ref-name rules never bounded it: it is printed through the
    # path set every Setlist message uses (every other byte a ?, 80 characters at
    # most, the edit said), inline, so no second copy of the rule lives here. Its
    # length was unbounded too, which made this hook's output longer than the
    # harness's 10,000-character spill threshold (C-62, measured 12,431).
    SH_TS="$(LC_ALL=C; t="${TRUNK//[^A-Za-z0-9._\/ :+=@-]/?}"; e=""
      [[ "$t" == "$TRUNK" ]] || e=" (characters outside a path set replaced with ?)"
      if [[ "${#t}" -gt 80 ]]; then t="${t:0:80}"; e="$e (cut at 80 characters)"; fi
      printf '"%s"%s' "$t" "$e")"
    deny SH-TRUNK-NOT-A-BRANCH "scope hook [SH-TRUNK-NOT-A-BRANCH]: .claude/sdd.json records trunk $SH_TS, which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which names a remote-tracking ref rather than a local branch."
  fi
fi
# HISTORY: ruling SC-10 (plugin 1.1.0): A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 leg, second run, then again in the third when the first repair proved partial).
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
# HISTORY: ruling SC-11 (plugin v1.9): GIT IS A DEPENDENCY, AND ITS VERSION IS PART OF IT (leg F5).
_shgit="$(git -C "$PROJ" rev-parse --git-dir 2>/dev/null)" || _shgit=""
if [[ -z "$_shgit" ]]; then
  deny_literal SH-NO-GIT "scope hook [SH-NO-GIT]: git is not usable here (it is missing, broken, or this is not a git repository), so this gate cannot tell which branch this write lands on and would otherwise allow feature code straight onto the trunk unchallenged. Run 'git rev-parse --git-dir' in this directory to see the failure; a missing binary, a broken dynamic library, a wrong-architecture build and a directory that is not a repository all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

BRANCH="$(git -C "$PROJ" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: a detached HEAD yields empty here exactly as it did before, and a detached HEAD is not the trunk
BRANCH="$(canonical_branch "$BRANCH")"
TRUNK="$(canonical_branch "$TRUNK")"
# fail-open-ok: off the trunk, writes are the point of a spec branch; this
# gate only guards the trunk. (Detached HEAD reads as empty, never equals the
# trunk, and passes: named in Known limitations.)
[[ "$BRANCH" == "$TRUNK" ]] || exit 0

# HISTORY: ruling SC-12 (plugin 1.0.3): file_path for Write/Edit/MultiEdit; notebook_path for NotebookEdit.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
slh_path_norm "$FILE_PATH"; FILE_PATH="$SLH_PATH_NORMED"
if [[ -z "$FILE_PATH" ]]; then
  deny SH-NO-PATH "scope hook [SH-NO-PATH]: this tool call carries neither file_path nor notebook_path, so the gate cannot tell whether the write lands on $TRUNK and will not guess. If the harness has changed its tool-input shape, update .claude/hooks/scope-hook.sh (and report it); removing this hook entry from .claude/settings.json is the deliberate way to work without the gate."
fi
# A RELATIVE PATH IS THE SESSION'S, NOT THE ROOT'S (spec 0159; the 2.9.0 disclosure
# relative-write-path). A path that is not absolute is resolved against the payload's
# cwd field, the working directory the session wrote from; a.txt written from src/
# is src/a.txt. Only when the payload carries no cwd is it read against the project
# root, which is what every earlier release did for every relative path.
if ! slh_path_abs "$FILE_PATH"; then
    SH_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || SH_CWD="" # fail-open-ok: an unreadable cwd leaves the root reading below, the behaviour before this read existed
    slh_path_norm "$SH_CWD"; SH_CWD="$SLH_PATH_NORMED"
    [[ -n "$SH_CWD" ]] && FILE_PATH="${SH_CWD%/}/$FILE_PATH"
fi

# HISTORY: ruling SC-13 (undated): Role paths: a string or a list of strings (multi-prefix repos, and flat-root repos that enumerate their shippable files).
# ONE QUESTION, ONE SITE: can the role paths be read at all. Since 2.9.0 (F10 of
# that release's leg, spec 0154) it has two causes, and they share this one code
# on this one deny: a "roles" value that is not an object, and a roles OBJECT whose
# values yield no path string (an object, null, an empty list, a number), which
# the extraction reads EMPTY and the loop below would have ended in silence on a
# trunk write the roles were declared to guard. The extraction is the three
# readers' shared expression and does not change.
ROLES_WHY=""
if [[ "$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$SDD_JSON" 2>/dev/null)" == "bad" ]]; then
  ROLES_WHY='has a "roles" value that is not an object'
else
  ROLE_PATHS="$(jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$SDD_JSON")"
  [[ -n "$ROLE_PATHS" ]] || ROLES_WHY='declares "roles" but none of its values is a path string or a list of them'
  # A `..` SEGMENT IS REFUSED BY NAME, as the hook library and the trunk audit
  # refuse it (spec 0169, L2 F10): such a role matched no write in this loop and
  # this hook fell silent on the trunk writes it was declared to guard.
  # And a GLOB, which the hook library and the trunk audit have refused by name
  # since 2.10.0 (F3 of its leg) and this hook matched literally (spec 0169, E-f).
  while IFS= read -r SH_R; do
    case "/$SH_R/" in */../*) ROLES_WHY='declares a role path with a .. segment, which names no directory any layer can match' ;; esac
    # And a `.` segment after any leading ./ (spec 0180, F8; the hook library says why).
    SH_RT="$SH_R"; while [[ "${SH_RT#./}" != "$SH_RT" ]]; do SH_RT="${SH_RT#./}"; done
    case "/$SH_RT/" in */./*) ROLES_WHY='declares a role path with a . segment after its start, which names no directory any layer can match' ;; esac
    case "$SH_R" in *'*'*|*'?'*|*'['*) ROLES_WHY='declares a role path with a glob character (* ? [), which the layers that read it would not agree about; name the directory itself' ;; esac
  done <<< "$ROLE_PATHS"
fi
if [[ -n "$ROLES_WHY" ]]; then
  deny SH-ROLES-SHAPE "scope hook [SH-ROLES-SHAPE]: .claude/sdd.json $ROLES_WHY, so the role paths this hook guards cannot be read and every write to the trunk would silently pass. Set \"roles\" to an object whose values are paths, such as {\"src\": \"src\", \"tests\": \"tests\"}, or remove the key to accept the defaults."
fi

# HISTORY: ruling SC-14 (undated): Canonicalize before comparing.
# Runs of / squeezed in the shell, not by tr (spec 0179, O-13: each fork is tens of
# milliseconds under Git Bash, and this runs on every write).
SH_DS=//; SH_S=/
REL="$FILE_PATH"; while [[ "$REL" == *//* ]]; do REL="${REL//$SH_DS/$SH_S}"; done
REL="${REL#"$PROJ"/}"
REL="${REL#"$PROJ_GIVEN"/}"
while [[ "$REL" == ./* ]]; do REL="${REL#./}"; done

# HISTORY: ruling SC-15 (undated): Slash squeezing and prefix stripping are not enough, because two spellings of the SAME file were reaching two different verdicts:
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
  local p="$1" d b missing="" real t n=0
  slh_path_abs "$p" || p="$PROJ/$p"
  # A SYMLINKED LEAF is resolved too (spec 0159; the 2.4.1 review's finding, disclosed
  # under case-spelling until then): the directory was resolved physically and the
  # final name re-attached literally, so a link whose target is a role-path file drew
  # no advisory. A chain is followed, sixteen links at most.
  while [[ -L "$p" && "$n" -lt 16 ]]; do
    t="$(readlink "$p" 2>/dev/null)" || break
    if slh_path_abs "$t"; then p="$t"; else p="$(dirname "$p")/$t"; fi
    n=$((n + 1))
  done
  d="$(dirname "$p")"; b="$(basename "$p")"
  while [[ ! -d "$d" && "$d" != "/" && "$d" != "." && -n "$d" ]]; do
    missing="$(basename "$d")/$missing"; d="$(dirname "$d")"
  done
  # PHYSICAL, NOT LOGICAL (spec 0169, L2 F8): bash's default cd collapses
  # `link/..` in the TEXT before pwd -P runs, so a `..` after a symlinked
  # component resolved to the wrong directory; -P hands the path to the kernel.
  real="$(cd -P "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s%s' "$real" "$missing" "$b"
}
# PROJ is canonicalised the same way or the prefix strip cannot match: on macOS
# TMPDIR itself lives behind a symlink, so a resolved path and an unresolved
# project root never share a prefix.
PROJ_REAL="$(cd "$PROJ" 2>/dev/null && pwd -P || printf '%s' "$PROJ")" # fail-open-ok: an unreachable project dir falls back to the given path, and the string comparison below then behaves exactly as it did before canonicalisation existed rather than skipping the check
REL="$(lex_norm "$REL")"

# HISTORY: ruling SC-16 (undated): Physical resolution on top, for what lexical normalisation cannot see:
REL_PHYS=""
CANON="$(canon_rel "$FILE_PATH" 2>/dev/null || true)" # fail-open-ok: a path that cannot be resolved leaves this empty, and the lexically normalised REL above is still checked against every role path below
# The resolved directory is physical, so a `..` left in the part that does not
# exist yet (a directory the write will create) collapses correctly as text.
[[ -n "$CANON" ]] && CANON="/$(lex_norm "$CANON")"
if [[ -n "$CANON" ]]; then
  case "$CANON" in
    "$PROJ_REAL"/*) REL_PHYS="${CANON#"$PROJ_REAL"/}" ;;
    # Resolves outside the project entirely. The trunk rule is about THIS
    # repository's role paths, so there is nothing here to govern, and no
    # verdict is invented from it.
  esac
fi
# A `..` SEGMENT IS JUDGED WHERE THE KERNEL PUTS IT (spec 0169, L2 F8). The
# lexical collapse above reads `src/lnk/../a.txt` as `src/a.txt` while the
# kernel writes `docs/a.txt` when src/lnk is a link into docs/, and it reads
# `link/../a.txt` as `a.txt` while the kernel writes into link's target's
# parent. Where the path carries a `..` and resolved, the physical reading is
# the only one consulted, so the verdict follows the filesystem both ways; a
# path that could not be resolved keeps the lexical reading, as before.
case "/$FILE_PATH/" in
  */../*) [[ -n "$CANON" ]] && REL="$REL_PHYS" ;;
esac
# HISTORY: ruling SC-17 (plugin 1.1.0): THE ROLE PATH IS NORMALISED, NOT JUST TRIMMED (1.1.0 adversarial review, second run).
#
# LOCKSTEP: scripts/trunk-audit.sh and setlist-hook-lib.sh normalise identically.
# Fixing only this file would leave the backstop blind in the same way, which is
# leg 5's F8 exactly.
# A ROLE SPELLED IN ANOTHER CASE (spec 0159; the 2.9.0 disclosure case-spelling). On a
# filesystem that folds case, SRC/a.txt IS src/a.txt, and git stores it under the role's
# spelling. Whether this filesystem folds case is ASKED, never inferred from the platform:
# a probe file is created under a temporary name beside the role directory, its upper-case
# spelling is tested, and it is removed. A probe that cannot write leaves the predicate
# case-exact and reports nothing. It runs only for a write that matched no role exactly
# and matches one ignoring case, so an ordinary write costs no probe.
# THE PROBE STANDS BESIDE THE ROLE DIRECTORY, NOT AT THE ROOT (spec 0169, L2
# F16): a repository can span volumes, and a role directory mounted from a
# volume whose case behaviour differs from the root's was judged by the root's.
# The probe is written in the deepest directory of the role path that exists,
# inside the project, so it measures the filesystem the role's files land on;
# its answer is kept per directory for the rest of this call.
SH_FOLD_SEEN=""
sh_folds_case() { # sh_folds_case <role> -> rc 0 when the role directory's filesystem folds case
  local n u dir="$PROJ_REAL/$1" ans
  while [[ ! -d "$dir" && "$dir" != "$PROJ_REAL" && "$dir" == "$PROJ_REAL"/* ]]; do dir="$(dirname "$dir")"; done
  [[ -d "$dir" ]] || dir="$PROJ_REAL"
  case "$SH_FOLD_SEEN" in
    *"|$dir=yes|"*) return 0 ;;
    *"|$dir=no|"*) return 1 ;;
  esac
  ans=no
  n=".setlist-case-probe.$$.${RANDOM:-0}"
  u="$(printf '%s' "$n" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
  if ( : > "$dir/$n" ) 2>/dev/null; then
    [[ -e "$dir/$u" ]] && ans=yes
    rm -f "$dir/$n" 2>/dev/null
  fi
  SH_FOLD_SEEN="$SH_FOLD_SEEN|$dir=$ans|"
  [[ "$ans" == yes ]]
}
# THE FOLD IS ASCII-ONLY, AS THE TRUNK AUDIT'S IS (spec 0169, the validator's
# ruling on E-b): the audit reads bytes since 0169, so a fold here under the
# caller's locale would match a non-ASCII capital the audit does not, and the
# two layers would disagree about the same role directory.
# In the shell, not by tr (spec 0179, O-13): the same ASCII fold, the letters named
# one by one so no locale's collation can widen a range, the result left in
# SH_LOWERED so no call pays a subshell.
sh_lower() { # sh_lower <text> -> SH_LOWERED
  local s="$1" o="" c t u=ABCDEFGHIJKLMNOPQRSTUVWXYZ l=abcdefghijklmnopqrstuvwxyz
  while [[ -n "$s" ]]; do
    c="${s:0:1}"; s="${s:1}"
    case "$c" in [ABCDEFGHIJKLMNOPQRSTUVWXYZ]) t="${u%%"$c"*}"; c="${l:${#t}:1}" ;; esac
    o="$o$c"
  done
  SH_LOWERED="$o"
}
sh_lower "$REL"; REL_L="$SH_LOWERED"; sh_lower "$REL_PHYS"; REL_PHYS_L="$SH_LOWERED"
while IFS= read -r ROLE; do
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  while [[ "$ROLE" == ./* ]]; do ROLE="${ROLE#./}"; done
  while [[ "$ROLE" == *//* ]]; do ROLE="${ROLE//$SH_DS/$SH_S}"; done
  ROLE="${ROLE#/}"
  ROLE="${ROLE%/}"
  [[ -n "$ROLE" && "$ROLE" != "." ]] || continue
  sh_lower "$ROLE"; ROLE_L="$SH_LOWERED"
  if [[ "$REL" == "$ROLE"/* || "$REL" == "$ROLE" ]] \
     || [[ -n "$REL_PHYS" && ( "$REL_PHYS" == "$ROLE"/* || "$REL_PHYS" == "$ROLE" ) ]] \
     || { { [[ "$REL_L" == "$ROLE_L"/* || "$REL_L" == "$ROLE_L" ]] \
            || [[ -n "$REL_PHYS_L" && ( "$REL_PHYS_L" == "$ROLE_L"/* || "$REL_PHYS_L" == "$ROLE_L" ) ]]; } && sh_folds_case "$ROLE"; }; then
    deny SH-TRUNK-WRITE "[SH-TRUNK-WRITE] feature code never lands directly on $TRUNK; open a spec or chore branch via /setlist:checkpoint."
  fi
done <<< "$ROLE_PATHS"
# A CHAIN LONGER THAN THE CAP IS REPORTED, NEVER SILENT (spec 0164, fix round
# 2, F22): the resolution stops at sixteen links, and until this release the
# path was then judged as whatever it had reached, so a longer chain ending in
# a role path was allowed with nothing said. This hook is advisory, so it says
# what it could not finish and the write proceeds either way.
# The same walk, asked in THIS shell: canon_rel runs inside a command
# substitution, so a variable it sets dies with the subshell (the defect this
# project has paid for before, recorded in its own hook library).
link_capped() { # link_capped <path> -> 0 when it is still a link after the cap
  local p="$1" t n=0
  slh_path_abs "$p" || p="$PROJ/$p"
  while [[ -L "$p" && "$n" -lt 16 ]]; do
    t="$(readlink "$p" 2>/dev/null)" || return 1
    if slh_path_abs "$t"; then p="$t"; else p="$(dirname "$p")/$t"; fi
    n=$((n + 1))
  done
  [[ -L "$p" ]]
}
# A CHAIN LONGER THAN THE CAP IS REPORTED, NEVER SILENT (spec 0164, fix round 2,
# F22): the resolution stops at sixteen links, and until this release the path
# was then judged as whatever it had reached, so a longer chain ending in a role
# path was allowed with nothing said.
if link_capped "$FILE_PATH"; then
  advise SH-LINK-CAP "[SH-LINK-CAP] this path is still a symbolic link after sixteen links, so the scope gate stopped following it and judged what it had reached; a longer chain ending in a role path is not seen here. Shorten the chain, or write the file the link points at."
fi
# fail-open-ok: the write matched no role path; docs-only trunk writes are
# the allowed case the whole loop exists to distinguish.
exit 0
