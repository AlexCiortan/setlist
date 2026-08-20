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

# THE scope ADVISES, IT DOES NOT VETO (design-advisory-means-advisory.md,
# RATIFIED 2026-08-04).
#
# This function used to emit permissionDecision "deny" and hold a hard veto over
# the session. It now emits "allow" and reports what it WOULD have decided in a
# machine-readable field. The guarantee did not move with it: it stayed where
# edition v1.7 put it, in git's own hooks, which run from git's internal state
# after argument parsing and ref resolution and have nothing left to spell
# around.
#
# WHY, in one number. Across four hostile legs on 2026-08-03 and 2026-08-04,
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
advise() {
  ADV_CODE="$(printf '%s' "$1" | sed -n 's/.*\[\([A-Z][A-Z0-9-]*\)\].*/\1/p')"
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

# Advise with a fixed literal reason, for the paths where jq is unavailable to
# escape one. The text must contain no double quotes, backslashes, or newlines.
advise_literal() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"setlist %s","setlistAdvisory":{"gate":"scope","verdict":"deny","code":"","reason":"%s"}}\n' "$1" "$1" "$1"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$1"; }

INPUT=$(cat)
# Normalize to an absolute path so the prefix strip below works whether
# file_path arrives absolute or relative (hooks run with cwd = project dir).
# Both the given and the resolved forms are kept: they differ whenever the
# project root is reached through a symlink or a path with a trailing slash,
# and the strip below has to survive either.
PROJ_GIVEN="${CLAUDE_PROJECT_DIR:-.}"
PROJ_GIVEN="${PROJ_GIVEN%/}"
PROJ="$(cd "$PROJ_GIVEN" && pwd)"
SDD_JSON="$PROJ/.claude/sdd.json"

# Not an SDD instance, or pre-stamp: stay silent.
# fail-open-ok: no sdd.json means no framework contract to enforce; gating a
# repo that never opted in would make the plugin unusable outside instances.
[[ -f "$SDD_JSON" ]] || exit 0

# Decide WITHOUT jq when it is absent, and report. Advisory since v1.7, so this
# emits "allow" and the git hooks refuse. sdd.json is unreadable, so the branch rule
# cannot be evaluated at all. Scoped to stamped instances by the check above.
#
# JQ PRESENT IS NOT JQ USABLE (leg 4, F1). `command -v jq` tests only whether a
# file of that name is on PATH. A jq that EXISTS and exits nonzero reached the
# reads below, every one of which discards its status, and the hook blamed a
# perfectly valid .claude/sdd.json instead of naming the broken tool. Failing
# closed for the wrong stated reason sends the operator to fix a file that is
# not broken, so the gate stays down for as long as it takes them to work that
# out. jq is RUN here rather than merely located.
if ! command -v jq >/dev/null 2>&1; then
  deny_literal "scope hook [SH-NO-JQ]: jq is not installed, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk; it would otherwise allow feature code straight onto the trunk unchallenged. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi
if ! printf '{}' | jq -e . >/dev/null 2>&1; then
  deny_literal "scope hook [SH-JQ-BROKEN]: jq is installed but does not run on this machine, so this gate cannot read .claude/sdd.json and cannot tell whether this write lands on the trunk. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
fi

# AND THE REST OF THE TOOLCHAIN, which this hook never received (1.1.0 leg,
# fourth run, F19). commit-gate.sh and close-gate.sh have carried this block
# since the v1.7 gate's F2; scope-hook.sh got the jq probe and not this one, so
# a broken `tr` made `REL="$(printf '%s' "$FILE_PATH" | tr -s '/')"` yield the
# EMPTY STRING, the path matched no role, and the hook exited 0 in silence while
# feature code landed on the trunk. Measured, not reasoned: silent exit 0, no
# output, the write allowed.
#
# Each probe RUNS its tool and checks the OUTPUT as well as the status, because a
# tool that exits 0 and prints nothing disables this hook just as thoroughly. The
# comparisons are bash builtins, so a probe never depends on the thing it probes.
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

# The config must PARSE. jq being installed is not the same as sdd.json being
# readable: a truncated or half-merged file makes every extraction below
# return empty, so the scaffolded flag reads false, the trunk name reads
# empty, and the hook exits 0 having checked nothing. That is total silent
# disablement of the trunk rule from an ordinary accident (a bad merge, an
# interrupted write, a hand edit), and it is exactly the failure this hook's
# no-jq path was written to prevent, reached by a different road.
# `refresh-instance.sh` has refused on this since 1.0.2; the hooks had not.
# Found by the degraded-environment generator on its first run.
# The config must PARSE **AND BE AN OBJECT** (1.0.8, F1). `jq -e .` tests
# VALIDITY, not SHAPE, and two perfectly valid inputs then disable the trunk rule
# in silence:
#
#   a top-level array `[]`   -> `.trunk` errors, TRUNK reads EMPTY
#   two JSON documents in one file (a half-merged or doubly-written config)
#                            -> `.trunk` prints TWICE, TRUNK reads "main\nmain"
#
# Either way the trunk comparison can never match, so every governed operation
# passes unchecked. Neither needs an attacker: a hand-edited file and a bad merge
# produce exactly these.
#
# `-s` slurps ALL documents into one array, so `length == 1` is what rejects the
# multi-document case; nothing else here can see it. The object test rejects the
# array case. Both hooks carry this, because both read the trunk from it.
if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal "scope hook [SH-SDD-SHAPE]: .claude/sdd.json is not a single JSON OBJECT (it does not parse, or it is an array, or it contains more than one document), so this gate cannot read the trunk name or the role paths and cannot tell whether this write lands on the trunk. It would otherwise allow feature code straight onto the trunk unchallenged. Fix the file (jq -s . .claude/sdd.json shows both the syntax and how many documents it holds), then retry. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi

# Active only after /scaffold flips the flag, so the one-time bootstrap
# scaffold on main is not blocked.
# fail-open-ok: pre-scaffold, the trunk rule is deliberately not yet in force.
[[ "$(jq -r '.scaffolded // false' "$SDD_JSON")" == "true" ]] || exit 0

# The trunk branch name is recorded in sdd.json at stamp or upgrade time
# (F6-2); main is only the fallback for instances stamped before the field
# existed.
# The trunk VALUE, not just the config's shape.
#
# 1.0.8 added a check that sdd.json is a single JSON object and stopped there,
# so the shape was validated and the value never was. This line read
# `jq -r '.trunk // "main"'`, and jq's `//` falls back only on null and false.
# An EMPTY STRING is truthy in jq, so `{"trunk":""}` yielded TRUNK="", every
# comparison against the current branch failed, and the trunk rule was silently
# disabled in both hooks. `[]` and `{}` did the same by rendering as themselves.
#
# A half-merged or hand-edited config produces exactly that, which is the same
# population the shape check was written for. Checking the container and not
# the contents is the defect the shape check was supposed to close, one level in.
#
# Absent stays defaulted, because not declaring a trunk is ordinary. Present
# but not a non-empty string is REFUSED: the value is there and it is wrong,
# and guessing "main" over a stated intention would govern a branch the project
# did not name.
TRUNK="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "$SDD_JSON" 2>/dev/null)" # fail-open-ok: an unreadable value yields the empty string, which the check on the next line refuses
[[ -n "$TRUNK" ]] || deny "scope hook [SH-TRUNK-INVALID]: .claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."

# THE TRUNK VALUE MUST NAME A LOCAL BRANCH, not merely be a non-empty string
# (F1 of the second 1.0.8 leg). The check added earlier today required a
# non-empty string and stopped there, which is the same "container, not
# contents" error one level further in, and the leg walked straight through it.
#
# The route is not hypothetical, it is the SHIPPED UPGRADE PATH. skills/upgrade
# tells the agent to detect the trunk with `git symbolic-ref
# refs/remotes/origin/HEAD`, which returns `refs/remotes/origin/main`, a full
# ref path. Every ordinary clone has an origin/HEAD, so that is what gets
# recorded. TRUNK is then `refs/remotes/origin/main` while the branch you are
# standing on is `main`, the equality can never hold, and BOTH hooks allow every
# governed operation in total silence. Six spellings reproduce it.
#
# So the value is REDUCED BY ASKING GIT rather than by stripping prefixes, which
# is the mistake the ref rewrite already made once. A spelling that resolves to
# a local branch becomes that branch; a remote-tracking spelling becomes the
# local branch it tracks IF one exists. Anything that still names no local
# branch is REFUSED, because a gate that cannot establish which branch it
# protects must not guess: guessing "main" would silently govern a branch the
# project never named.
#
# The guard only bites once the repository HAS local branches, so a freshly
# initialised scaffold with no commits is not denied for the crime of being new.
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
# A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 leg, second run, then again
# in the third when the first repair proved partial). On a case-insensitive
# filesystem `refs/heads/main` is one file, so after `git checkout MAIN` this
# reads "MAIN", the byte comparison below is false, and the scope gate exits 0
# on every write to the trunk. One ordinary command in an EARLIER tool call is
# enough to disable it for the rest of the session, which is what makes this
# worse than a spelling trick: nothing in the governed command looks unusual.
#
# The trunk side is normalised too, because `{"trunk":"MAIN"}` reaches the same
# fail-open with HEAD untouched. Both sides through the same function or the
# comparison is only half fixed, which is exactly how the first repair of this
# defect left the session gates open while the git hooks were closed.
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
# GIT IS A DEPENDENCY, AND ITS VERSION IS PART OF IT (leg F5).
# This read `git branch --show-current`, which arrived in git 2.22 (2019). Below
# that it exits 129, this read empty, the empty value never equalled the trunk,
# and this gate took its ordinary-feature-work exit in SILENCE: zero bytes, no
# code, no reason. That is the one thing the fail-open rule sixty lines above
# forbids, since absence reads as permission, and git was the only dependency
# never held to it.
# `symbolic-ref --quiet --short HEAD` predates the floor and is what the git-hook
# layer has always used. Measured identical on current git in both cases that
# matter: the branch name on a branch, empty when detached.
BRANCH="$(git -C "$PROJ" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: a detached HEAD yields empty here exactly as it did before, and a detached HEAD is not the trunk
BRANCH="$(canonical_branch "$BRANCH")"
TRUNK="$(canonical_branch "$TRUNK")"
# fail-open-ok: off the trunk, writes are the point of a spec branch; this
# gate only guards the trunk. (Detached HEAD reads as empty, never equals the
# trunk, and passes: named in Known limitations.)
[[ "$BRANCH" == "$TRUNK" ]] || exit 0

# file_path for Write/Edit/MultiEdit; notebook_path for NotebookEdit. An
# event carrying NEITHER denies (1.0.3, IN-3): every tool this hook matches
# sends one of the two today, so an empty extraction means the harness
# changed shape under the hook, and a gate that cannot see the path cannot
# tell whether the write lands on the trunk. This used to exit 0, which is
# exactly how NotebookEdit's notebook_path slipped past the trunk rule.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
if [[ -z "$FILE_PATH" ]]; then
  deny "scope hook [SH-NO-PATH]: this tool call carries neither file_path nor notebook_path, so the gate cannot tell whether the write lands on $TRUNK and will not guess. If the harness has changed its tool-input shape, update .claude/hooks/scope-hook.sh (and report it); removing this hook entry from .claude/settings.json is the deliberate way to work without the gate."
fi

# Role paths: a string or a list of strings (multi-prefix repos, and flat-root
# repos that enumerate their shippable files). A directory entry covers its
# subtree; a file entry covers exactly that file. "." is deliberately inert:
# covering the whole root would deny the docs-only trunk commits the loop
# depends on; a flat-root repo lists its real code paths instead.
# `.roles` MUST BE AN OBJECT, and this is the trunk-value defect again one key
# across (F3 of the third leg). If `.roles` is a string, an array or a number,
# `.roles.src` is an error, jq writes nothing, ROLE_PATHS comes back EMPTY, and
# the deny loop below runs ZERO ITERATIONS: the hook allows every write to every
# feature path on the trunk, in silence. A half-merged or hand-edited config
# produces exactly that, which is the population the shape check was written for.
#
# Absent stays defaulted, because not declaring roles is ordinary. Present and
# not an object is REFUSED, because the value is there and it is wrong, and
# guessing src/tests over a stated intention would guard paths the project did
# not name.
if [[ "$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$SDD_JSON" 2>/dev/null)" == "bad" ]]; then
  deny "scope hook [SH-ROLES-SHAPE]: .claude/sdd.json has a \"roles\" value that is not an object, so the role paths this hook guards cannot be read and every write to the trunk would silently pass. Set \"roles\" to an object such as {\"src\": \"src\", \"tests\": \"tests\"}, or remove the key to accept the defaults."
fi
ROLE_PATHS="$(jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$SDD_JSON")"

# Canonicalize before comparing. A path that is merely SPELLED differently
# (`./src/app.js`, `src//app.js`, a project root reached with a trailing slash)
# used to survive the prefix strip as an absolute or dot-prefixed string,
# match no role path, and be allowed onto the trunk in silence. That is the
# same fail-open class as a gate running without jq: the check does not error,
# it just stops checking. Found by the suite on macOS, where TMPDIR carries a
# trailing slash, and reproduced on Linux with `./src/...`.
# Slash squeezing goes through tr rather than bash pattern substitution: the
# escaped-delimiter form (${v//\/\//\/}) squeezed correctly under bash 5 and
# did not under the bash 3.2 that ships with macOS, which the suite caught on
# the macOS CI leg. tr -s is POSIX and behaves the same everywhere.
REL="$(printf '%s' "$FILE_PATH" | tr -s '/')"
REL="${REL#"$PROJ"/}"
REL="${REL#"$PROJ_GIVEN"/}"
while [[ "$REL" == ./* ]]; do REL="${REL#./}"; done

# Slash squeezing and prefix stripping are not enough, because two spellings of
# the SAME file were reaching two different verdicts: `src/app.js` denied,
# while `docs/../src/app.js` and `srclink/app.js` (a symlinked role directory)
# landed on the trunk in silence. Neither needs an attacker: `..` is what a
# tool composing paths emits, and symlinked source directories are ordinary.
# So the path is resolved to what the filesystem says it IS, and that answer is
# authoritative. Done in shell rather than with realpath or readlink -f, which
# macOS does not ship in the form this needs (the suite's bash 3.2 leg exists
# for exactly this class of assumption).
#
# The file usually does not exist yet, since this hook runs BEFORE the write,
# so resolution walks up to the nearest existing ancestor and re-attaches the
# missing tail.
# Lexical normalisation runs FIRST and always, because the filesystem cannot
# help when the directories do not exist yet: this hook fires BEFORE the write,
# and `docs/../src/app.js` in a project whose docs/ has not been created yet
# resolves to nothing at all. Found by this hook's own suite fixture, whose
# trunk carries no src/ directory: the physical resolution below silently
# degraded to the string comparison it was added to replace, and the case that
# was supposed to prove the fix passed for the old reason.
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

# Physical resolution on top, for what lexical normalisation cannot see: a
# SYMLINKED role directory is a different file from the one its name suggests,
# and only the filesystem knows. Both answers are checked against the role
# paths below, and either one matching denies, because a gate that has two
# readings of a path must take the stricter one.
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
# THE ROLE PATH IS NORMALISED, NOT JUST TRIMMED (1.1.0 hostile leg, second run).
#
# The WRITE path above is canonicalised hard (duplicate slashes squeezed, ./ and
# ../ resolved, symlinked role directories resolved physically) because this file
# already knows that "two spellings of the SAME file were reaching two different
# verdicts" is the defect class. The ROLE path it is compared against got only
# `${ROLE%/}`, so a role recorded as "./src" never matched "src/App.js" and the
# trunk-write rule silently did nothing: measured, a Write of src/App.js on the
# trunk exited 0 in silence where the canonical spelling denies SH-TRUNK-WRITE,
# the commit landed on the trunk, and trunk-audit.sh then reported it clean at
# exit 0 so pre-push allowed the push. "/src" reproduces it identically.
#
# The value comes from an interview into {{SRC_ROLE}}, produces no error
# anywhere, and defeats every layer at once, so it is normalised rather than
# trusted: strip any leading "./" repeatedly, squeeze duplicate slashes, drop a
# leading "/" (a role path is repo-relative and there is no other reading of it),
# and drop a trailing "/". A value that normalises to nothing is skipped by the
# emptiness test that already guards this loop.
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
