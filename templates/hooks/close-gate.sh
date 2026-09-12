#!/usr/bin/env bash
# SDD close gate: PreToolUse on matcher "Bash", fires only on `git merge` into
# the trunk branch (read from .claude/sdd.json, never assumed to be main) from
# a spec/ or chore/ branch. Stamped into the instance. Independently verifies
# the Part 6 close conditions before the merge; /setlist:checkpoint runs the same
# checks first and will normally be the thing that satisfies them.
# Two facts shape this script (dogfood F4-2/F5-1): PreToolUse runs BEFORE the
# command, so the merge target is derived from the command text plus repo
# state (a compound "git checkout <trunk> && git merge ..." is gated even
# though the current branch is not yet the trunk); and the Closing report
# exists on the branch being merged, so every content check reads the merged
# ref via `git show <ref>:<path>`, never the working tree.
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Hook TIMEOUT verified live 2026-07-25 on Claude Code 2.1.x, both directions,
# because through plugin 2.5.0 this gate re-ran the project's whole suite and
# was the entry most likely to run long. The unit is SECONDS, and the key is
# honoured: a hook sleeping 3s under "timeout": 10 delivered its deny, and the
# same hook under "timeout": 1 was CANCELLED and the tool call PROCEEDED. That
# second result is the fail-open this gate's timeout exists to prevent, so it
# is measured here rather than assumed. The template shipped 1800 (30 minutes)
# for this entry while the suite ran here; since 2.6.0 it ships 300, the
# commit gate's figure, because the run left (see the contract below).
# Requires jq, and FAILS CLOSED without it: a missing jq used to make every
# extraction below return empty, every check fall through, and the gate allow
# every merge unchecked. Disable with a one-line edit: remove this hook's entry
# from .claude/settings.json.

set -u

# THE close ADVISES, IT DOES NOT VETO (the advisory-gate decision, RATIFIED 2026-08-04).
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
#
# WHAT LEFT IN 2.6.0, AND WHY (the owner's ruling 1 on the 2.6.0 strategy,
# 2026-09-06; spec 0132 cluster C, position (iii)). Through 2.5.0 this gate
# also RAN the instance's gate command (the full suite) inside PreToolUse, under
# the template's 1800-second timeout, and then emitted `allow` whatever the
# result: a side-effecting run whose verdict was discarded, while the git hook
# `pre-merge-commit` ran the same command at the merge and REFUSED on failure.
# So every close ran the suite twice and only the second verdict was acted on
# (external review M1 and N3; backlog `ER2`). No ruling had decided that the
# first run should exist, and the advisory decision above is the reason it
# should not: this layer reports, and a report that costs a full suite run to
# produce is not one. The run is gone, and the two `CG-` codes that named it (a
# red gate command; a scaffolded instance with none recorded) retired with it:
# the git hook carries both questions as `SLH-GATE-COMMAND-FAILED` and
# `SLH-NO-GATE-COMMAND`. The template's
# timeout for this entry fell from 1800 to 300. Everything else this gate
# reads, it still reads; what it says, it still says.
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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":%s},"systemMessage":%s,"setlistAdvisory":{"gate":"close","verdict":"deny","code":%s,"reason":%s}}\n' \
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
  # HISTORY: ruling CG-01 (plugin 2.3.0), in the framework source's private hook-rulings record: THE CODE IS EXTRACTED HERE TOO (F11-2026, and the SIBLING half of it).
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"setlist %s","setlistAdvisory":{"gate":"close","verdict":"deny","code":"%s","reason":"%s"}}\n' "$1" "$1" "$ADV_CODE" "$1"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$1"; }

# HISTORY: ruling CG-02 (plugin 2.4.0), in the framework source's private hook-rulings record: THE INPUT IS READ BY THE SHELL, NOT BY cat (spec 0130; the 2.4.0 leg's F12).
IFS= read -r -d '' INPUT || true
if [[ -z "$INPUT" ]]; then
  deny_literal "close gate [CG-NO-INPUT]: this hook was given no payload at all, so the command being run cannot be read and this gate cannot tell whether it merges into the trunk. If cat, bash or the harness pipe is broken this is what it looks like; run the merge again once the environment is repaired. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse)."
fi

# HISTORY: ruling CG-03 (plugin v1.7), in the framework source's private hook-rulings record: Decide WITHOUT jq when it is absent, and report.
JQ_STATE=ok
if ! command -v jq >/dev/null 2>&1; then
  JQ_STATE=absent
elif [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  # The probe compares OUTPUT, not only status (spec 0130; the 2.4.0 leg's F6):
  # `printf '{}' | jq -e .` discarded stdout, so a jq that exited 0 printing
  # nothing was classified usable and this gate emitted ZERO BYTES.
  JQ_STATE=broken
fi
# HISTORY: ruling CG-04 (plugin v1.7), in the framework source's private hook-rulings record: AND THE REST OF THE TOOLCHAIN, for exactly the same reason (v1.7 gate, F2).
TOOLCHAIN_BROKEN=""
_probe="$(printf 'x\n' | awk '{ print }' 2>/dev/null)" || _probe=""
[[ "$_probe" == "x" ]] || TOOLCHAIN_BROKEN="awk"
if [[ -z "$TOOLCHAIN_BROKEN" ]]; then
  _probe="$(printf 'x\n' | sed 's/x/y/' 2>/dev/null)" || _probe=""
  [[ "$_probe" == "y" ]] || TOOLCHAIN_BROKEN="sed"
fi
if [[ -z "$TOOLCHAIN_BROKEN" ]]; then
  _probe="$(printf 'x\n' | tr 'x' 'y' 2>/dev/null)" || _probe=""
  [[ "$_probe" == "y" ]] || TOOLCHAIN_BROKEN="tr"
fi
if [[ -z "$TOOLCHAIN_BROKEN" ]]; then
  _probe="$(printf 'x\n' | grep -E '^x$' 2>/dev/null)" || _probe=""
  [[ "$_probe" == "x" ]] || TOOLCHAIN_BROKEN="grep"
fi
if [[ -n "$TOOLCHAIN_BROKEN" ]]; then
  case "$INPUT" in
    *merge*)
      deny_literal "close gate [CG-NO-TOOLCHAIN]: $TOOLCHAIN_BROKEN is installed but does not work on this machine, so this gate cannot parse the command or verify the Closing report, the QA verdict and the inventory row, and would otherwise allow every merge unchecked. Run '$TOOLCHAIN_BROKEN --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the raw payload names no merge at all, so this is not a
    # command this gate governs, and gating every Bash call would block the very
    # command that repairs the broken tool.
    *) exit 0 ;;
  esac
fi

if [[ "$JQ_STATE" != "ok" ]]; then
  case "$INPUT" in
    *merge*)
      if [[ "$JQ_STATE" == "absent" ]]; then
        deny_literal "close gate [CG-NO-JQ]: jq is not installed, so this gate cannot verify the Closing report, the QA verdict, or the inventory row, and would otherwise allow every merge unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      fi
      deny_literal "close gate [CG-JQ-BROKEN]: jq is installed but does not work on this machine (it exits nonzero, or exits 0 and prints nothing), so this gate cannot verify the Closing report, the QA verdict, or the inventory row, and would otherwise allow every merge unchecked. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: without a usable jq the raw payload does not mention
    # merging, so this is not a command the gate governs; gating every Bash call
    # would block the very install command that fixes the broken jq.
    *) exit 0 ;;
  esac
fi

# HISTORY: ruling CG-05 (plugin v1.9), in the framework source's private hook-rulings record: GIT IS THE ONE LOAD-BEARING DEPENDENCY THAT WAS NEVER PROBED (v1.9 leg, V19-F1.
_gitprobe="$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --git-dir 2>/dev/null)" || _gitprobe=""
if [[ -z "$_gitprobe" ]]; then
  case "$INPUT" in
    *merge*)
      deny_literal "close gate [CG-NO-GIT]: git is not usable here (it is missing, broken, or this is not a git repository), so this gate cannot resolve the merged branch, read its Closing report, or find the inventory row, and would otherwise report nothing at all and let the merge proceed unchecked. Run 'git rev-parse --git-dir' in this directory to see the failure; a missing binary, a broken dynamic library, a wrong-architecture build and a directory that is not a repository all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the raw payload names no merge, so this is not a command this
    # gate governs, and warning on every Bash call would block the very command
    # that repairs the broken git.
    *) exit 0 ;;
  esac
fi

# The status of THIS parse, not of jq in general. A jq that runs on {} can still
# fail on the payload in front of it, and a decision taken on a value that was
# never produced is the same fail-open one level down.
if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  case "$INPUT" in
    *merge*)
      deny_literal "close gate [CG-JQ-UNPARSED]: jq could not parse the payload this hook was given, so the command being run cannot be read and this gate cannot tell whether it merges into the trunk. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the unparseable payload does not mention merging either, so
    # it is not a command this gate governs.
    *) exit 0 ;;
  esac
fi

# HISTORY: ruling CG-06 (2026-07-27), in the framework source's private hook-rulings record: Whether this gate applies must not depend on how the command is SPELLED.
HEREDOC_AWK='
# A HEREDOC OPENER IS ONLY AN OPENER OUTSIDE QUOTES AND OUTSIDE A COMMENT.
#
# The first cut of this pass (1.1.0, F9) matched << anywhere on the raw line and
# it opened a BLOCKER the very next leg found: `git commit -m "use <<EOF heredoc
# in the installer"` followed by a real `git merge --no-ff spec/0001-thing`
# swallowed the merge as heredoc body and the gate allowed it in silence. The
# oracle confirmed the merge really lands. It reproduced from a quoted message,
# from a shell comment, and from ordinary prose, and the trunk audit called the
# result a chore merge at exit 0.
#
# The justification that shipped with the broken version was the load-bearing
# error and is worth quoting: "an unterminated heredoc drops everything after it
# ... bash would refuse the same command as a syntax error, so nothing the gate
# stops reading was ever going to run". That is false exactly where it matters.
# Bash sees NO heredoc inside quotes or after #, and runs every line.
#
# So this tracks quote state across lines the way a shell does, skips a comment
# that starts a word, and treats <<< as the herestring it is. Only a delimiter
# found outside quotes opens a body.
function hd_scan(s,   i, c, n, d, j, ch) {
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (hdq == "") {
      if (c == "\\") { i += 2; continue }
      if (c == "'"'"'" || c == "\"") { hdq = c; i++; continue }
      if (c == "#" && (i == 1 || substr(s, i-1, 1) ~ /[ \t;&|(]/)) return ""
      if (c == "(" && substr(s, i+1, 1) == "(") { __d = 0; while (i <= n) { __x = substr(s, i, 1); if (__x == "(") __d++; else if (__x == ")") { __d--; if (__d == 0) { i++; break } } i++ } continue }
      if (c == "<" && substr(s, i+1, 1) == "<") {
        if (substr(s, i+2, 1) == "<") { i += 3; continue }
        j = i + 2
        if (substr(s, j, 1) == "-") j++
        while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
        d = ""; ch = substr(s, j, 1)
        if (ch == "'"'"'" || ch == "\"") {
          j++
          while (j <= n && substr(s, j, 1) != ch) { d = d substr(s, j, 1); j++ }
        } else {
          if (substr(s, j, 1) !~ /[A-Za-z_]/) return ""
          while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) { d = d substr(s, j, 1); j++ }
        }
        if (d != "") return d
        i = j; continue
      }
      i++
    } else {
      if (hdq == "\"" && c == "\\") { i += 2; continue }
      if (c == hdq) hdq = ""
      i++
    }
  }
  return ""
}
{
  if (hdin) { hdl = $0; sub(/^[ \t]+/, "", hdl); if (hdl == hddelim) hdin = 0; next }
  hdd = hd_scan($0)
  print $0
  if (hdd != "") { hddelim = hdd; hdin = 1 }
}'
CMD_HD="$(printf '%s' "$CMD" | awk "$HEREDOC_AWK")"
CMD_NORM="$(printf '%s' "$CMD_HD" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | tr '\n\r' ';;' | tr -s '[:space:]' ' ' | awk '{
  out = ""; q = ""; buf = ""
  n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (q == "") {
      # A BACKSLASH outside quotes escapes the next character, so an escaped
      # apostrophe is a literal one and NOT the start of a span. Without this,
      # the ordinary shell idiom for an apostrophe inside single quotes was read
      # as opening a span that never closed, and everything after it (including
      # the real git commit) vanished. That is F5 reappearing inside its own
      # fix, and the suite caught it.
      #
      # AN ESCAPED CHARACTER IS CONTENT, NOT GRAMMAR (leg 4, F5). Consuming the
      # backslash and emitting the next character RAW handed the escaped
      # character back to the parser as code, which is the whole class the
      # opaque-token model exists to close, reached through the escape path
      # instead of the quote path:
      #
      #   git commit -m foo\\;git\\ checkout\\ spec/0002-other && git merge ...
      #
      # Bash parses that as ONE argument to -m; nothing switches branch. The
      # gate un-escaped it into a live `;` and a live space, cut a synthetic
      # `git checkout spec/0002-other` segment out of free text, believed the
      # shell had moved off the trunk, and skipped every close check on the
      # merge that followed. The QUOTED spelling of the same line denies.
      #
      # So an escaped character is judged exactly as a quoted span is: shell-safe
      # word material is kept, and anything that would carry grammar (a
      # separator, a space, a redirection, a quote) becomes the inert token. It
      # stays glued to its neighbours, so the word is still one word, and that
      # word is no longer a command, a separator or a ref.
      if (c == "\\") {
        i++
        e = substr($0, i, 1)
        if (e == "") { }
        else if (e ~ /^[A-Za-z0-9._\/@{}^~+=:-]$/) { out = out e }
        else { out = out "@@Q@@" }
      }
      else if (c == "\"" || c == "\047") { q = c; buf = "" }
      else { out = out c }
    } else if (q == "\"" && c == "\\") {
      # Inside DOUBLE quotes a backslash escapes too, so an escaped quote does
      # not close the span. Inside SINGLE quotes it does not: bash treats every
      # character literally there, which is why this branch tests q.
      i++; buf = buf substr($0, i, 1)
    } else if (c == q) {
      q = ""
      # A quoted span that is ONE shell-safe word is kept as that word: it is a
      # ref, a binary name or a subcommand, and the gate needs to read it.
      # Anything else (spaces, separators, punctuation) is a MESSAGE or a
      # multi-word argument, and becomes one inert token that can neither sit at
      # command position nor split a segment.
      # An EMPTY span contributes NOTHING, because that is what the shell does:
      # two adjacent quotes concatenate to nothing, so a git prefixed by them IS
      # git. The one-or-more test below rejected the empty string, so an empty
      # span became @@Q@@ and split the very word it was glued to: the command
      # then matched nothing and sailed past the gate. Found by the fourth leg.
      if (buf == "") { }
      else if (buf ~ /^[A-Za-z0-9._\/@{}^~+=:-]+$/) { out = out buf } else { out = out "@@Q@@" }
    } else { buf = buf c }
  }
  if (q != "") { out = out " @@UNTERMINATED@@" }
  print out
}')"
# HISTORY: ruling CG-07 (plugin 1.1.0), in the framework source's private hook-rulings record: ONLY SOME GLOBAL OPTIONS TAKE A SEPARATE VALUE (1.1.0 leg, third run).
GIT_OPTS='( +(-[cC] +[^ ]+|--(exec-path|git-dir|work-tree|namespace|super-prefix|config-env|attr-source) +[^ ]+|-{1,2}[A-Za-z][^ ]*))*'

# HISTORY: ruling CG-08 (2026-07-28), in the framework source's private hook-rulings record: THE MARKER IS NOW READ, and until 2026-07-28 it was not.
if [[ "$CMD_NORM" == *"@@UNTERMINATED@@"* ]]; then
  case "$CMD" in
    *merge*)
      deny "close gate [CG-UNLEXABLE]: this command contains an unterminated quote, so the gate could not determine where the command ends and cannot verify the close conditions for any merge inside it. It refuses rather than guess. Balance the quotes, or move the text containing the apostrophe out of the command line (a shell comment, a heredoc body and an ANSI-C \$'...' string all do this), then retry."
      ;;
    # fail-open-ok: the input could not be lexed, but it does not mention
    # merge even in raw form, so it is not a command this gate governs and
    # refusing it would block unrelated work over an unbalanced quote.
    *) exit 0 ;;
  esac
fi
if ! printf '%s' "$CMD_NORM" | grep -qE "(^|[;&|(]| )([^ ]*/)?git${GIT_OPTS} +merge( |$)"; then
  # fail-open-ok: not a merge; this gate governs merges only.
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# Not an SDD instance: stay silent.
# fail-open-ok: no sdd.json means no framework contract to enforce.
SDD_JSON="$PROJ/.claude/sdd.json"
[[ -f "$SDD_JSON" ]] || exit 0

# HISTORY: ruling CG-09 (plugin 1.0.8), in the framework source's private hook-rulings record: The config must PARSE, for the same reason the scope hook now requires it.
if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$SDD_JSON" >/dev/null 2>&1; then
  deny_literal "close gate [CG-SDD-SHAPE]: .claude/sdd.json is not a single JSON OBJECT (it does not parse, or it is an array, or it contains more than one document), so this gate cannot read the trunk name and cannot tell whether this merge lands on the trunk. It would otherwise allow every merge unchecked. Fix the file (jq -s . .claude/sdd.json shows both the syntax and how many documents it holds), then retry. Gates report their verdict and PERMIT: advisory since v1.7, so this warns and the git hooks are what refuse."
fi

# THE STRUCTURED STATUS RECORD (RP1, edition v1.12). Where the merged branch's
# tree carries .claude/status.json, this gate's close questions are answered
# from the record and the frozen page readers further down DO NOT RUN for that
# close; where it is absent, the page path below is byte-identical to what
# shipped before the record existed. Present-and-malformed is warned as a
# refusal-in-waiting, never a pass, never a fallback: the git-hook layer is
# what refuses, in the same words, and this gate's job is saying so EARLY.
#
# LOCKSTEP: the seven SLH_RECORD_*_JQ assignments below are byte-identical to
# templates/git-hooks/setlist-hook-lib.sh and scripts/trunk-audit.sh, asserted
# by the suite exactly as the three frozen awk readers are. The full grammar
# reasoning lives with the library's copy.
SLH_RECORD_CHECK_JQ='if (type != "object") or (.setlist_status != 1) or (((keys - ["setlist_status","specs","chores"]) | length) > 0) or (((.specs // {}) | type) != "object") or (((.chores // {}) | type) != "object") then "malformed" elif (((.specs // {}) | to_entries | all((.key | test("^[0-9]+[a-z]*$")) and (.value | if type != "object" then false else (((keys - ["status","qa_pass_1","diagram"]) | length) == 0) and (.status as $s | (["draft","queued","active","revised","built","parked","closed"] | index($s)) != null) and ((.qa_pass_1 == null) or (.qa_pass_1 == "ok")) and ((.diagram == null) or (.diagram == "updated") or (.diagram == "no-impact")) end))) | not) then "malformed" elif (((.chores // {}) | to_entries | all((.key | test("^CHORE-[0-9]+$")) and (.value | if type != "object" then false else (((keys - ["status","files"]) | length) == 0) and ((.status == "open") or (.status == "done")) and ((.files == null) or (((.files | type) == "array") and (.files | all(type == "string")))) end))) | not) then "malformed" else "ok" end'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_CLOSED_JQ='((.specs // {}) | to_entries[] | select(.value.status == "closed") | .key)'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_ACTIVE_JQ='((.specs // {}) | to_entries[] | select(.value.status == "active") | .key)'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_DONE_JQ='((.chores // {}) | to_entries[] | select(.value.status == "done") | .key)'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_STATUS_JQ='((.specs // {})[$num]) | if . == null then "absent" else .status end'
SLH_RECORD_FACTS_JQ='((.specs // {})[$num]) | if . == null then "absent" elif ((.status == "closed") and (.qa_pass_1 == "ok") and ((.diagram == "updated") or (.diagram == "no-impact"))) then "ok" else "missing" end'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_CHORE_FILES_JQ='(((.chores // {})[$id].files) // []) | .[]'

# HISTORY: ruling CG-10 (plugin 1.0.8), in the framework source's private hook-rulings record: The trunk branch name is recorded in sdd.json at stamp or upgrade time.
TRUNK="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "$SDD_JSON" 2>/dev/null)" # fail-open-ok: an unreadable value yields the empty string, which the check on the next line refuses
[[ -n "$TRUNK" ]] || deny "close gate [CG-TRUNK-INVALID]: .claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."

# HISTORY: ruling CG-11 (plugin 1.0.8), in the framework source's private hook-rulings record: THE TRUNK VALUE MUST NAME A LOCAL BRANCH, not merely be a non-empty string.
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
    deny "close gate [CG-TRUNK-NOT-A-BRANCH]: .claude/sdd.json records trunk \"$TRUNK\", which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which names a remote-tracking ref rather than a local branch."
  fi
fi

# HISTORY: ruling CG-12 (plugin 1.0.6), in the framework source's private hook-rulings record: --- segment-wise evaluation (1.0.5) -----------------------------------------.
strip_wrappers() { # strip_wrappers <segment> -> echoes the segment, unwrapped
  local seg="$1" prev=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    # HISTORY: ruling CG-13 (undated), in the framework source's private hook-rulings record: A TRAILING SHELL COMMENT IS NOT ARGUMENTS (leg 5, F4 and F3).
    seg="$(printf '%s' "$seg" | sed -E 's/(^|[[:space:]])#.*$//')"
    # HISTORY: ruling CG-14 (2026-07-28), in the framework source's private hook-rulings record: A TRAILING REDIRECTION IS NOT AN OPERAND (leg 5, F3).
    seg="$(printf '%s' "$seg" | sed -E 's/[[:space:]]+[0-9]*(>>|>|<)[[:space:]]*(&[0-9@A-Za-z-]+|[^ ]+)[[:space:]]*$//')"
    # HISTORY: ruling CG-15 (plugin 1.0.8), in the framework source's private hook-rulings record: SHELL GRAMMAR at the head of a segment (1.0.8, F9).
    seg="$(printf '%s' "$seg" | sed -E 's/^function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\(\)[[:space:]]*)?//; s/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*//')"
    seg="$(printf '%s' "$seg" | sed -E 's/^(\{|\}|!|if|then|elif|else|fi|while|until|do|done|for|select|case|esac|in|time|coproc)([[:space:]]+|$)//')"
    # leading VAR=val assignments (FOO=bar git ...)
    seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^ ]* *//')"
    # HISTORY: ruling CG-16 (plugin 1.0.8), in the framework source's private hook-rulings record: a wrapper word, plus env/stdbuf style flags and assignments after it.
    seg="$(printf '%s' "$seg" | sed -E 's/^[0-9]*(>>|>|<)[[:space:]]*(&[0-9-]+|[^ ]+)[[:space:]]*//')"
    # HISTORY: ruling CG-17 (2026-07-28), in the framework source's private hook-rulings record: A wrapper word, plus env/stdbuf style flags and assignments after it.
    seg="$(printf '%s' "$seg" | sed -E 's#^([^ ]*/)?(command|exec|nice|nohup|time|stdbuf|env) +##')"
    # HISTORY: ruling CG-18 (plugin 1.0.7), in the framework source's private hook-rulings record: A wrapper flag may take its value as a SEPARATE word, and 1.0.6 consumed.
    seg="$(printf '%s' "$seg" | sed -E 's/^-- +//')"
    if printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +([^ ]*/)?git( |$)'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +-[^ ]* +'; then
      # HISTORY: ruling CG-19 (plugin 1.0.7), in the framework source's private hook-rulings record: A flag value may itself begin with a dash.
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +-[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +[^- ][^ ]* +'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +[^- ][^ ]* +//')"
    else
      seg="$(printf '%s' "$seg" | sed -E 's/^(-{1,2}[^ ]* +)+//')"
    fi
  done
  printf '%s' "$seg"
}

# HISTORY: ruling CG-20 (2026-07-28), in the framework source's private hook-rulings record: The separator set. `&` is here as of 1.0.7.
SEGMENTS="$(printf '%s\n' "$CMD_NORM" | awk '{ gsub(/>&/, ">@@FD@@"); gsub(/<&/, "<@@FD@@"); gsub(/&&/, "\n@@AND@@ "); gsub(/\|\|/, "\n@@SEQ@@ "); gsub(/[()]/, "\n@@GRP@@ "); gsub(/[;|&]/, "\n@@SEQ@@ "); print }')"

# HISTORY: ruling CG-21 (plugin 1.1.0), in the framework source's private hook-rulings record: A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 adversarial review, second run).
#
# LOCKSTEP: setlist-hook-lib.sh carries the same function as slh_canonical_branch
# and its header carries the full reasoning, including why comparing OIDs instead
# would deny all work on a freshly cut feature branch.
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

# HISTORY: ruling CG-22 (undated), in the framework source's private hook-rulings record: BOTH SIDES, not just the operand.
CUR_BRANCH="$(git -C "$PROJ" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: a detached HEAD yields empty here exactly as it did before, and a detached HEAD is not the trunk
CUR_BRANCH="$(canonical_branch "$CUR_BRANCH")"
TRUNK="$(canonical_branch "$TRUNK")"
MERGED_REFS=""
UNNAMEABLE=""
AMBIGUOUS_SPEC=""
# A branch this gate could not establish. It must never compare equal to the
# trunk (that would deny ordinary feature work) and must never be treated as
# "some other branch" either (that is the bypass). It is checked explicitly.
UNKNOWN_BRANCH=$'\x01unknown'
UNRESOLVED_TARGET=""

# A checkout whose success is not implied by the separator (F7). The branch it
# would move to is held here until the NEXT segment says how it was reached.
PENDING_BRANCH=""
# A separator that arrived on a segment of its own, because punctuation sat next
# to it. Carried to the next segment that actually holds a command (F2).
HELD_SEP=""
# Has an earlier segment on THIS line already switched branches, and if so what
# did it switch away from? A later `-` means that origin rather than the
# pre-command reflog (F11).
SWITCHED_ONLINE=""
ORIGIN_BRANCH=""

while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue

  # HISTORY: ruling CG-23 (undated), in the framework source's private hook-rulings record: HOW WAS THIS SEGMENT REACHED? A checkout was modelled as unconditionally.
  SEP=""
  MARKER_ONLY=""
  case "$seg" in
    "@@AND@@ "*) SEP=AND; seg="${seg#@@AND@@ }" ;;
    "@@AND@@")   SEP=AND; seg=""; MARKER_ONLY=1 ;;
    "@@SEQ@@ "*) SEP=SEQ; seg="${seg#@@SEQ@@ }" ;;
    "@@SEQ@@")   SEP=SEQ; seg=""; MARKER_ONLY=1 ;;
    "@@GRP@@ "*) seg="${seg#@@GRP@@ }" ;;
    "@@GRP@@")   seg=""; MARKER_ONLY=1 ;;
  esac
  # HISTORY: ruling CG-24 (undated), in the framework source's private hook-rulings record: A segment that is nothing but punctuation carries no command, so it must not.
  if [[ -n "$MARKER_ONLY" ]]; then
    if [[ -n "$SEP" && -z "$HELD_SEP" ]]; then HELD_SEP="$SEP"; fi
    continue
  fi
  if [[ -n "$HELD_SEP" ]]; then
    SEP="$HELD_SEP"
    HELD_SEP=""
  fi
  if [[ -n "$PENDING_BRANCH" ]]; then
    if [[ "$SEP" == "AND" ]]; then
      CUR_BRANCH="$PENDING_BRANCH"
    else
      CUR_BRANCH="$UNKNOWN_BRANCH"
    fi
    PENDING_BRANCH=""
  fi

  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue
  seg="$(strip_wrappers "$seg")"
  [[ -n "$seg" ]] || continue

  # HISTORY: ruling CG-25 (undated), in the framework source's private hook-rulings record: A checkout or switch changes the branch every LATER segment runs on.
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +(checkout|switch) +"; then
    # HISTORY: ruling CG-26 (plugin 1.0.6), in the framework source's private hook-rulings record: `-` and `@{-1}` mean "the branch I was on before", and they are ORGANIC.
    IS_SWITCH=0
    printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +switch +" && IS_SWITCH=1

    # Everything after a bare `--` is pathspec by definition, never a branch.
    SEG_HEAD="$seg"
    HAS_PATHSPEC_SEP=0
    if [[ "$IS_SWITCH" -eq 0 ]]; then
      case "$seg" in
        *" -- "*) SEG_HEAD="${seg%% -- *}"; HAS_PATHSPEC_SEP=1 ;;
        # HISTORY: ruling CG-27 (undated), in the framework source's private hook-rulings record: A BARE TRAILING `--` IS NOT THE PATHSPEC FORM (leg 5, F2).
        *" --")   : ;;
      esac
    fi

    # HISTORY: ruling CG-28 (plugin 1.0.7), in the framework source's private hook-rulings record: `git checkout [<tree-ish>] -- <pathspec>` RESTORES FILES AND SWITCHES.
    if [[ "$HAS_PATHSPEC_SEP" -eq 1 ]]; then
      continue
    fi

    # HISTORY: ruling CG-29 (plugin 1.1.0), in the framework source's private hook-rulings record: `-b`, `-B` and `--orphan` NAME a branch that is about to exist, so the.
    NEWB="$(printf '%s' "$SEG_HEAD" | awk '{
      f = 0
      for (i = 1; i < NF; i++) {
        if (f && ($i == "-b" || $i == "-B" || $i == "--orphan" ||
                  $i == "-c" || $i == "-C" || $i == "--create" || $i == "--force-create")) { print $(i + 1); exit }
        if ($i == "checkout" || $i == "switch") f = 1
      }
    }')"

    # HISTORY: ruling CG-30 (plugin 1.1.0), in the framework source's private hook-rulings record: A CREATED BRANCH NAME MUST BE A LITERAL (1.1.0 leg, fourth run, F16).
    if [[ -n "$NEWB" ]]; then
      case "$NEWB" in
        *'$'*|*'`'*|*'@@Q@@'*|*'*'*|*'?'*|*'{'*) NEWB="$UNKNOWN_BRANCH" ;;
      esac
    fi

    # HISTORY: ruling CG-31 (undated), in the framework source's private hook-rulings record: TWO OR MORE OPERANDS IS A PATHSPEC CHECKOUT, separator or not (F7 of the.
    SEG_OPERANDS="$(printf '%s' "$SEG_HEAD" | awk '{
      f = 0; n = 0
      for (i = 1; i <= NF; i++) {
        if (f && ($i == "-" || $i !~ /^-/)) n++
        if ($i == "checkout" || $i == "switch") f = 1
      }
      print n
    }')"
    if [[ -z "$NEWB" && "${SEG_OPERANDS:-0}" -gt 1 ]]; then
      # fail-open-ok: not a branch switch at all, so the branch this gate is
      # standing on is unchanged and any later merge is still judged against it.
      # Recording no switch is the FAIL-CLOSED direction here: it leaves
      # CUR_BRANCH as the trunk rather than moving it somewhere unguarded.
      continue
    fi
    # HISTORY: ruling CG-32 (plugin 1.1.0), in the framework source's private hook-rulings record: THE `-z "$NEWB"` GUARD IS THE FIX, and the comment above it was already.

    if [[ -z "$NEWB" ]]; then
      NEWB="$(printf '%s' "$SEG_HEAD" | awk '{
        f = 0
        for (i = 1; i <= NF; i++) {
          if (f && ($i == "-" || $i !~ /^-/)) { print $i; exit }
          if ($i == "checkout" || $i == "switch") f = 1
        }
      }')"

      # No candidate at all before the `--`: the pure pathspec form
      # (`git checkout -- .`). Nothing switched, so the tracked branch is
      # unchanged. Leaving it alone is the whole fix.
      if [[ -z "$NEWB" ]]; then
        continue
      fi

      case "$NEWB" in
        -|@\{-1\})
          # HISTORY: ruling CG-33 (plugin 1.1.0), in the framework source's private hook-rulings record: `-` and `@{-1}` mean "the branch I was on before", and they are.
          if [[ -n "$SWITCHED_ONLINE" ]]; then
            NEWB="$ORIGIN_BRANCH"
          else
            NEWB="$(git -C "$PROJ" rev-parse --abbrev-ref '@{-1}' 2>/dev/null || true)" # fail-open-ok: an unresolvable previous branch is converted to the UNKNOWN sentinel on the next line, which makes any later merge fail closed rather than read as "some other branch"
          fi
          [[ -n "$NEWB" ]] || NEWB="$UNKNOWN_BRANCH"
          ;;
        *)
          if [[ "$IS_SWITCH" -eq 0 ]]; then
            if git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$NEWB" >/dev/null 2>&1; then
              # A real local branch: the switch is real, record it under the
              # name GIT stores rather than the one the command typed, or a case
              # variant of the trunk is tracked as some other branch entirely.
              NEWB="$(canonical_branch "$NEWB")"
            elif [[ -e "$PROJ/$NEWB" || -e "$NEWB" ]]; then
              # An existing path and not a branch: this discards changes and
              # switches nothing. `.` lands here, and so does any file or
              # directory an agent names.
              continue
            else
              # HISTORY: ruling CG-34 (undated), in the framework source's private hook-rulings record: Neither a branch nor a path.
              NEWB="$UNKNOWN_BRANCH"
            fi
          else
            # HISTORY: ruling CG-35 (undated), in the framework source's private hook-rulings record: `git switch` ONLY EVER TAKES A BRANCH, and that was read as.
            if ! git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$NEWB" >/dev/null 2>&1; then
              NEWB="$UNKNOWN_BRANCH"
            else
              # Same canonicalisation as the checkout path: `git switch MAIN`
              # reaches the trunk exactly as `git checkout MAIN` does.
              NEWB="$(canonical_branch "$NEWB")"
            fi
          fi
          ;;
      esac
    fi
    # Held, not applied. The next segment's separator decides whether this
    # checkout may be believed; see the loop head.
    if [[ -n "$NEWB" ]]; then
      PENDING_BRANCH="$NEWB"
      # Where this switch came FROM, which is what a later `-` on the same line
      # actually means at run time (F11). Recorded here rather than derived
      # later, because by then CUR_BRANCH has already moved.
      ORIGIN_BRANCH="$CUR_BRANCH"
      SWITCHED_ONLINE=1
    fi
    continue
  fi

  printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +merge( |$)" || continue

  # This gate guards the trunk. A merge running on any other branch is not a
  # close and never was, EXCEPT when the branch could not be established at
  # all, which is a question the gate cannot answer and so must not pass.
  if [[ "$CUR_BRANCH" == "$UNKNOWN_BRANCH" ]]; then
    UNRESOLVED_TARGET="$seg"
    continue
  fi
  [[ "$CUR_BRANCH" == "$TRUNK" ]] || continue

  # The merge's own arguments: everything after the FIRST merge token in THIS
  # segment. First, not last, so prose in -m cannot displace the real ones.
  MARGS="$(printf '%s' "$seg" | awk '{ f=0; for (i=1;i<=NF;i++) { if (f) printf "%s ", $i; if (!f && $i=="merge") f=1 } }')"

  # HISTORY: ruling CG-36 (plugin 1.0.8), in the framework source's private hook-rulings record: AN OPTION'S VALUE IS NOT AN OPTION, AND NOT A REF (F4/F5 of the second.
  MARGS="$(printf '%s' "$MARGS" | awk '
  function is_value_opt(w,   i, opts, n, o) {
    # -> 1 if w is a long option, or any UNIQUE PREFIX of one, that takes its
    #    value as a separate word.
    #
    # GIT ACCEPTS ABBREVIATIONS (leg 5, F5). `--mess`, `--messa`, `--mes` are
    # all `--message` to git, and this stripper matched the spelled-out forms
    # only. So `git merge --no-ff spec/0001-x --mess "--continue"` left the
    # value in the argument list, it matched the resumption exemption, and every
    # close check was skipped. `-m "--continue"` denies, which is the control:
    # two spellings of one command disagreed, and the shorter one was the hole.
    #
    # Matching a PREFIX rather than a fixed list is what closes the class rather
    # than the reported spelling; enumerating abbreviations would be the same
    # mistake as enumerating wrapper names.
    if (w !~ /^--[a-z-]+$/) return 0
    n = split("--message --file --strategy --strategy-option --into-name", opts, " ")
    for (i = 1; i <= n; i++) {
      o = opts[i]
      if (substr(o, 1, length(w)) == w) return 1
    }
    return 0
  }
  {
    out = ""; skip = 0
    for (i = 1; i <= NF; i++) {
      if (skip) { skip = 0; continue }
      w = $i
      if (w ~ /^(-m|-F|-s|-X)$/ || is_value_opt(w)) { skip = 1; continue }
      if (w ~ /^--[a-z-]+=/ && is_value_opt(substr(w, 1, index(w, "=") - 1))) { continue }
      out = out w " "
    }
    print out
  }')"

  if printf '%s' "$MARGS" | grep -qE '(^| )--(continue|abort|quit)( |$)'; then
    # fail-open-ok: the in-progress merge was gated when it was initiated;
    # blocking --continue/--abort would strand a conflicted close with no
    # permitted way to finish it or back out.
    continue
  fi

  # HISTORY: ruling CG-37 (undated), in the framework source's private hook-rulings record: WHICH BRANCH IS BEING MERGED, asked of git rather than of the string.
  SEG_REF=""
  SEG_REFS=""
  SEG_LOOKS_SPEC=""
  # HISTORY: ruling CG-38 (undated), in the framework source's private hook-rulings record: EVERY operand gets a disposition, not just the ones that resolve (leg 4, F3).
  SEG_INDIRECT=""
  SEG_UNRESOLVED=""
  for word in $MARGS; do
    # HISTORY: ruling CG-39 (undated), in the framework source's private hook-rulings record: The INDIRECT forms are excluded from resolution on purpose, and the reason.
    WORD_INDIRECT=""
    case "$word" in
      -) WORD_INDIRECT="$word" ;;
      -*) continue ;;
      '') continue ;;
      @*|*'$'*|*'`'*) WORD_INDIRECT="$word" ;;
      HEAD|FETCH_HEAD|ORIG_HEAD|MERGE_HEAD|CHERRY_PICK_HEAD|REVERT_HEAD) WORD_INDIRECT="$word" ;;
    esac
    if [[ -n "$WORD_INDIRECT" ]]; then
      SEG_INDIRECT="$SEG_INDIRECT $WORD_INDIRECT"
      continue
    fi
    # HISTORY: ruling CG-40 (plugin v1.0.6), in the framework source's private hook-rulings record: A word that LOOKS like a spec or chore branch but does not resolve is.
    WORD_LOOKS_SPEC=""
    case "${word#refs/}" in
      spec/*|chore/*|*/spec/*|*/chore/*) SEG_LOOKS_SPEC="$word"; WORD_LOOKS_SPEC="$word" ;;
    esac
    SEG_SHA="$(git -C "$PROJ" rev-parse --verify --quiet "${word}^{commit}" 2>/dev/null)" # fail-open-ok: a word that names no commit is not a merge target, and the emptiness test below is what acts on it
    if [[ -z "$SEG_SHA" ]]; then
      [[ -n "$WORD_LOOKS_SPEC" ]] && SEG_UNRESOLVED="$SEG_UNRESOLVED $WORD_LOOKS_SPEC"
      continue
    fi
    # HISTORY: ruling CG-41 (undated), in the framework source's private hook-rulings record: Already an ancestor of the trunk means merging it lands NOTHING NEW, so.
    if git -C "$PROJ" merge-base --is-ancestor "$SEG_SHA" "$TRUNK" 2>/dev/null; then
      # HISTORY: ruling CG-42 (plugin 1.1.0), in the framework source's private hook-rulings record: AND THE EXEMPTION HAS TO CLEAR THE SPEC-SHAPED FLAG, or it applies to.
      SEG_LOOKS_SPEC=""
      WORD_LOOKS_SPEC=""
      continue
    fi
    # HISTORY: ruling CG-43 (plugin 1.0.7), in the framework source's private hook-rulings record: WHICH ref at this commit is the merge being judged?.
    SEG_ALL="$(git -C "$PROJ" for-each-ref --points-at "$SEG_SHA" --format='%(refname)' refs/heads refs/remotes 2>/dev/null \
                | grep -E '^refs/(heads|remotes/[^/]+)/(spec|chore)/')" # fail-open-ok: no spec or chore ref at this commit means the merge is a sync or an integration merge, which this gate has never governed; the emptiness is the classification
    # HISTORY: ruling CG-44 (plugin 2.4.0), in the framework source's private hook-rulings record: The predicate is ANCHORED to the namespaces this instance governs (2.4.0.
    if [[ -n "$SEG_ALL" ]]; then
      SEG_SPECS="$(printf '%s\n' "$SEG_ALL" | grep -E '/spec/' || true)"
      if [[ -n "$SEG_SPECS" ]]; then
        SEG_NUMS="$(printf '%s\n' "$SEG_SPECS" | sed 's#.*/spec/##; s/-.*$//' | sort -u | grep -c .)"
        if [[ "$SEG_NUMS" -gt 1 ]]; then
          AMBIGUOUS_SPEC="$(printf '%s\n' "$SEG_SPECS" | tr '\n' ' ')"
          break
        fi
        # Prefer a local head for the message; any ref of the same spec would
        # read the same artifacts, so this is legibility, not correctness.
        SEG_REF="$(printf '%s\n' "$SEG_SPECS" | grep '^refs/heads/' | head -n1)"
        [[ -n "$SEG_REF" ]] || SEG_REF="$(printf '%s\n' "$SEG_SPECS" | head -n1)"
      else
        SEG_REF="$(printf '%s\n' "$SEG_ALL" | head -n1)"
      fi
    fi
    # HISTORY: ruling CG-45 (plugin 1.0.8), in the framework source's private hook-rulings record: EVERY operand is collected, not just the first (F2/F6 of the second 1.0.8.
    if [[ -n "$SEG_REF" ]]; then
      case " $SEG_REFS " in
        *" $SEG_REF "*) ;;
        *) SEG_REFS="$SEG_REFS $SEG_REF" ;;
      esac
      SEG_REF=""
    fi
  done
  SEG_REF="${SEG_REFS# }"

  # HISTORY: ruling CG-46 (plugin 1.0.8), in the framework source's private hook-rulings record: DISPOSITION EVERY OPERAND BEFORE LEAVING THE SEGMENT (leg 4, F3).
  if [[ -n "$SEG_INDIRECT$SEG_UNRESOLVED" ]]; then
    UNNAMEABLE="$seg"
    continue
  fi

  if [[ -n "$SEG_REF" ]]; then
    MERGED_REFS="$MERGED_REFS $SEG_REF"
    continue
  fi

  # Named like a spec branch, resolvable as nothing. The close conditions live
  # in a specific branch's artifacts, so with no branch there is nothing to read
  # and the only honest answers are "refuse" and "guess". This refuses.
  if [[ -n "$SEG_LOOKS_SPEC" ]]; then
    UNNAMEABLE="$seg"
    continue
  fi

  # HISTORY: ruling CG-47 (plugin 1.0.3), in the framework source's private hook-rulings record: A ref that is NAMED but is not a spec or chore branch is a sync or an.
  NAMED_REF=""
  for word in $MARGS; do
    case "$word" in
      -*|*'$'*|*'`'*|@*|'') continue ;;
      HEAD|FETCH_HEAD|ORIG_HEAD|MERGE_HEAD|CHERRY_PICK_HEAD|REVERT_HEAD) continue ;;
    esac
    printf '%s' "$word" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._/-]*$' || continue
    # HISTORY: ruling CG-48 (plugin 1.0.6), in the framework source's private hook-rulings record: A raw object name identifies the commit without NAMING the branch, and.
    SFN="$(git -C "$PROJ" rev-parse --symbolic-full-name "$word" 2>/dev/null)" # fail-open-ok: a word that is not a ref at all exits nonzero here, and the emptiness test below is what acts on it; the status carries no information the value does not
    [[ -n "$SFN" ]] || continue
    if git -C "$PROJ" rev-parse --verify --quiet "${word}^{commit}" >/dev/null 2>&1; then
      NAMED_REF="$word"; break
    fi
  done
  [[ -n "$NAMED_REF" ]] || UNNAMEABLE="$seg"
done <<SEGEOF
$SEGMENTS
SEGEOF

# A trunk-targeting merge whose branch cannot be established at all: the close
# conditions are about a specific branch's artifacts, so with no branch there
# is nothing to check and the gate refuses rather than guessing.
if [[ -n "$UNRESOLVED_TARGET" ]]; then
  # HISTORY: ruling CG-49 (plugin 1.1.0), in the framework source's private hook-rulings record: THE MESSAGE HAS TO NAME THE ACTUAL CAUSE (1.1.0 adversarial review, F2).
  deny "close gate [CG-UNRESOLVED-SWITCH]: this gate cannot establish which branch [$UNRESOLVED_TARGET] would run on, so it cannot tell whether it merges into the trunk. Either the switch used a shorthand with no previous branch recorded (git checkout - or @{-1}), in which case name the branch in full; or the switch was reached by a separator that does not imply it succeeded (; or | or ||), in which case a failed checkout leaves the shell on the trunk and the merge lands there. Join them with && so the merge runs only if the switch did, or run the switch as its own command first."
fi

# HISTORY: ruling CG-50 (undated), in the framework source's private hook-rulings record: Two different specs on one commit.
if [[ -n "$AMBIGUOUS_SPEC" ]]; then
  deny "close gate [CG-AMBIGUOUS-SPEC]: more than one spec branch points at the commit being merged ($AMBIGUOUS_SPEC). The close conditions live in a specific spec's artifacts, so the gate cannot tell which spec's Closing report to judge. Delete or move the refs that do not belong on this commit, then merge."
fi

if [[ -n "$UNNAMEABLE" ]]; then
  deny "close gate [CG-UNNAMEABLE-REF]: this merges into the trunk, but no argument of [$UNNAMEABLE] names a branch this gate can resolve. Indirect forms (a shell variable, -, @{-1}, FETCH_HEAD, a raw commit SHA) cannot be verified, so the close conditions cannot be checked at all. Name the branch literally: git merge --no-ff spec/NNNN-slug."
fi

if [[ -z "$MERGED_REFS" ]]; then
  # fail-open-ok: no segment merges a spec or chore branch into the trunk, so
  # no close is being attempted here.
  exit 0
fi

# Every collected ref is checked; the first failure denies the whole command.
for MERGED_REF in $MERGED_REFS; do
  # The ref must resolve; every check below reads the merged ref's committed
  # tree, so working-tree edits that were never committed to the branch do not
  # count.
  if ! git -C "$PROJ" rev-parse --verify --quiet "${MERGED_REF}^{commit}" >/dev/null 2>&1; then
    deny "close gate [CG-REF-UNRESOLVED]: branch $MERGED_REF does not resolve to a commit; the close gate cannot verify the Closing report. Check the branch name."
  fi

  # HISTORY: ruling CG-51 (undated), in the framework source's private hook-rulings record: MERGED_REF is now a FULL ref name (refs/heads/spec/.
  case "$MERGED_REF" in
    */spec/*)  SPEC_BRANCH="spec/${MERGED_REF#*/spec/}" ;;
    */chore/*) SPEC_BRANCH="chore/${MERGED_REF#*/chore/}" ;;
    *)         SPEC_BRANCH="$MERGED_REF" ;;
  esac

  # Chore branches (chore/<slug>, unnumbered per Part 5b) have no spec file or
  # inventory row to verify; for them only the gate command below applies.
  if [[ "$SPEC_BRANCH" == spec/* ]]; then
    # HISTORY: ruling CG-52 (undated), in the framework source's private hook-rulings record: Derive the spec file from the branch NUMBER (Part 6.
    SPEC_NUM="${SPEC_BRANCH#spec/}"
    SPEC_NUM="${SPEC_NUM%%-*}"
    # HISTORY: ruling CG-53 (plugin 2.2.0), in the framework source's private hook-rulings record: F2 of the 2.2.0 leg, a CONFIRMED FALSE DENIAL and the same root cause as.
    SPEC_PATHS="$(git -C "$PROJ" ls-tree -r -z --name-only "$MERGED_REF" -- specs/ 2>/dev/null | grep -zE "^specs/${SPEC_NUM}-[^/]*\.md$" | tr '\0' '\n' || true)"
    MATCHES=0
    [[ -n "$SPEC_PATHS" ]] && MATCHES="$(printf '%s\n' "$SPEC_PATHS" | grep -c .)"
    if [[ "$MATCHES" -eq 0 ]]; then
      deny "close gate [CG-SPEC-MISSING]: no spec file matches specs/$SPEC_NUM-*.md on branch $MERGED_REF; the close gate cannot verify the Closing report. Commit the spec file to the branch before merging."
    fi
    if [[ "$MATCHES" -ne 1 ]]; then
      deny "close gate [CG-SPEC-DUPLICATE]: $MATCHES spec files match specs/$SPEC_NUM-*.md on branch $MERGED_REF; spec numbers must be unique. Resolve the duplicate before merging."
    fi
    SPEC_PATH="$(printf '%s\n' "$SPEC_PATHS" | head -n1)"
    SPEC_TEXT="$(git -C "$PROJ" show "${MERGED_REF}:${SPEC_PATH}" 2>/dev/null || true)"

    # HISTORY: ruling CG-54 (plugin 1.0.7), in the framework source's private hook-rulings record: THE BRANCH MUST HAVE WRITTEN ITS OWN SPEC (1.0.7, B4).
    #
    # The test is AUTHORSHIP, not staleness: if the spec file is byte-identical
    # between the merge base and the branch tip, this branch contributed nothing
    # to its own spec and the Closing report it is being judged on is not its
    # own. A legitimate close always modifies its spec file, because writing the
    # Closing report into it IS the close, so the honest path cannot trip this.
    MERGE_BASE="$(git -C "$PROJ" merge-base "$TRUNK" "$MERGED_REF" 2>/dev/null || true)" # fail-open-ok: an empty base is refused immediately below rather than skipped
    if [[ -z "$MERGE_BASE" ]]; then
      deny "close gate [CG-NO-MERGE-BASE]: no merge base between $TRUNK and $MERGED_REF, so the gate cannot tell whether this branch wrote its own Closing report or inherited one from an earlier spec with the same number. Refusing rather than guessing."
    fi
    BASE_BLOB="$(git -C "$PROJ" rev-parse --quiet --verify "${MERGE_BASE}:${SPEC_PATH}" 2>/dev/null || true)" # fail-open-ok: an absent blob means the branch ADDED this spec, which is the legitimate case and is handled by the emptiness test below
    TIP_BLOB="$(git -C "$PROJ" rev-parse --quiet --verify "${MERGED_REF}:${SPEC_PATH}" 2>/dev/null || true)" # fail-open-ok: the file was resolved from this same ref above, so an empty value here is a torn repository and denies on the comparison below
    if [[ -n "$BASE_BLOB" && "$BASE_BLOB" == "$TIP_BLOB" ]]; then
      deny "close gate [CG-SPEC-NOT-AUTHORED]: branch $MERGED_REF does not modify $SPEC_PATH, so the Closing report it would be judged on was written by earlier work on spec $SPEC_NUM and already sits on $TRUNK. Reusing a closed spec's number carries unreviewed changes onto the trunk against somebody else's evidence. Open a spec with a NEW number for this work, or commit this branch's own Closing report to $SPEC_PATH."
    fi

    # HISTORY: ruling CG-55 (plugin v1.12), in the framework source's private hook-rulings record: THE RECORD, OR THE PAGE (RP1, edition v1.12).
    CG_RECORD_STRUCTURED=0
    if git -C "$PROJ" cat-file -e "${MERGED_REF}:.claude/status.json" 2>/dev/null; then
      CG_RECORD_STRUCTURED=1
      CG_REC="$(git -C "$PROJ" show "${MERGED_REF}:.claude/status.json" 2>/dev/null || true)" # fail-open-ok: unreadable-but-present reads as empty, which is not "ok" below and warns
      CG_REC_VERDICT="$(printf '%s' "$CG_REC" | jq -r "$SLH_RECORD_CHECK_JQ" 2>/dev/null || printf 'malformed')"
      if [[ "$CG_REC_VERDICT" != "ok" ]]; then
        deny "close gate [CG-RECORD-MALFORMED]: .claude/status.json on branch $MERGED_REF is not a well-formed status record, so no close fact can be read from it and the git hooks will refuse this merge outright. Nothing falls back to the STATUS.md page. Only /setlist:checkpoint writes this file; fix the record on the branch (jq . .claude/status.json shows the syntax; Part 3 of the edition shows the grammar), then merge."
      fi
      CG_FACTS="$(printf '%s' "$CG_REC" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_FACTS_JQ" 2>/dev/null || printf 'malformed')"
      if [[ "$CG_FACTS" == "absent" ]]; then
        deny "close gate [CG-RECORD-NO-SPEC]: spec $SPEC_NUM has no entry in .claude/status.json on branch $MERGED_REF, so this close is not recorded and the git hooks will refuse it. Run /setlist:checkpoint to record the spec (a spec cut before the record existed gets its entry backfilled at its next checkpoint touch), close through checkpoint, then merge."
      fi
      if [[ "$CG_FACTS" != "ok" ]]; then
        deny "close gate [CG-RECORD-NO-CLOSE]: spec $SPEC_NUM's entry in .claude/status.json on branch $MERGED_REF does not carry its close facts (status closed, qa_pass_1 ok, diagram updated or no-impact), so the git hooks will refuse this merge. /setlist:checkpoint writes these at the close; run the close through checkpoint rather than editing the record by hand, then merge."
      fi
    fi
    if [[ "$CG_RECORD_STRUCTURED" == "0" ]]; then

    # HISTORY: ruling CG-56 (plugin 1.0.9), in the framework source's private hook-rulings record: A FENCED EXAMPLE IS NOT A CLOSING REPORT (leg 5, F7).
    #
    # LOCKSTEP: setlist-hook-lib.sh and trunk-audit.sh carry this same program
    # byte for byte and the suite asserts all three are identical. Narrowing one
    # alone is leg 5's F8, where a gate and its only backstop went blind together.
    TEMPLATE_FENCE_AWK='function __f(k,  i){ if(k) for(i=1;i<=n;i++) print b[i]; n=0 } { __l=$0; sub(/\r$/,"",__l); sub(/^[[:space:]]*/,"",__l); if (incmt) { __cb[++__cn]=$0; if (index(__l, "-->")) { incmt = 0; __cn=0 } next } if (!fence && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; __cn=0; __cb[++__cn]=$0; next } __c=substr(__l,1,1); if ((__c=="`" || __c=="~") && $0 ~ /^ ? ? ?[`~]/) { __m=0; while(substr(__l,__m+1,1)==__c) __m++; __raw=substr(__l,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { if (!fence) { fence=1; fch=__c; flen=__m; n=0; t=0; b[++n]=$0; next } else if (__c==fch && __m>=flen && __r=="") { fence=0; b[++n]=$0; __f(!t); next } } } if (fence) { b[++n]=$0; if($0 ~ /^ ? ? ?#+[ \t]+Closing report/) t=1; next } print } END { if(fence) __f(!t); if(incmt) for(__ci=1;__ci<=__cn;__ci++) print __cb[__ci] }'
    SPEC_TEXT="$(printf '%s\n' "$SPEC_TEXT" | awk "$TEMPLATE_FENCE_AWK")"
    # LIVE TEXT for the spec-file field readers below too (F6, plugin-2.0.0 leg).
    # The diagram-field reader read this SPEC_TEXT raw while its sibling STATUS-row
    # reader stripped it, so a fenced "Architecture diagram:" example satisfied the
    # mandatory field. Assigned here, above the first consumer, so the diagram check
    # and the STATUS-row check share the one frozen reader. LOCKSTEP with setlist-
    # hook-lib.sh and trunk-audit.sh; the suite compares all three byte-identical.
    SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } if ((__d>0 || __peeled) && __ic ~ /^[[:space:]]*[|]/) next; print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

    # The Closing report section exists (Appendix C: "## Closing report ...").
    if ! printf '%s\n' "$SPEC_TEXT" | grep -qE $'^ {0,3}#{1,6}[ \t]+Closing report'; then
      deny "close gate [CG-NO-CLOSING-REPORT]: the spec file for $MERGED_REF has no Closing report section on the branch; complete it, commit it to the branch, then merge."
    fi

    # HISTORY: ruling CG-57 (2026-08-05), in the framework source's private hook-rulings record: The pasted QA Pass 1 block.
    #
    # SCOPED (2.0.0 leg, F8/F3). The previous comment here claimed the block's
    # content cannot contain a fence delimiter "which is what keeps this reader
    # trivial: no nesting and no info-string rule", and that sentence was the
    # defect: the trivial reader matched the first qa-pass-1 opener ANYWHERE,
    # so a block nested inside a pasted verifier report satisfied the check
    # (F8, and the trunk audit was blind in lockstep) while an illustrative
    # shape-quote in another section poisoned a real verdict (F3). Third
    # fence-vs-QA-block collision, so the fix is structural: the reader tracks
    # fences the way the template stripper does, reads headings only at fence
    # depth zero, and the block that decides is the FIRST qa-pass-1 fence at
    # depth zero inside a Closing report section. An opener inside another
    # fence is content.
    #
    # FIRST WINS, ruled 2026-08-29 (F7-2026), and this reader took the LAST
    # until then. The Closing report owns ONE verdict. An illustrative block
    # comes after the real one by construction, so last-wins let an example
    # replace a real verdict in both directions; a genuine revision EDITS THE
    # VERDICT IN PLACE rather than appending a rival, so nothing legitimate
    # rested on the old rule. A second block is now an ordinary fence: it
    # neither satisfies nor poisons. The old comment justified last-wins by the
    # diagram field's revision convention, and that convention changed in the
    # same ruling, so the justification had outlived its rule as well.
    # The suite asserts the three layers agree BY OUTCOME over a corpus,
    # beside the byte-identity lockstep.
    #
    #
    # LOCKSTEP: templates/git-hooks/setlist-hook-lib.sh and scripts/trunk-audit.sh
    # carry this same program byte for byte and the suite asserts it. The
    # lockstep is why F5 reached the backstop, and it is kept because the answer
    # to a gate and its backstop agreeing on a WRONG rule is a right rule, not
    # two rules.
    QA_PASS1_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; qa_seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } } else { if (__r == "qa-pass-1" && inclose && !qa_seen) { inb = 1; qch = __c; qlen = __m; n = 0; bad = 0; next } fence = 1; fch = __c; flen = __m; next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "") next; if (l ~ /^[A-Za-z0-9._-]+[[:space:]]*:[[:space:]]*(PASS|PARTIAL|FAIL)$/) n++; else bad = 1; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) inclose = 0 } } END { if (incmt) print "unclosed-comment"; else if (inb) print "unclosed"; else if (!qa_seen) print "none"; else if (bad) print "malformed"; else if (n == 0) print "empty"; else print "ok" }'
    QA_STATE="$(printf '%s\n' "$SPEC_TEXT" | awk "$QA_PASS1_AWK")"
    if [[ "$QA_STATE" != "ok" ]]; then
      deny "close gate [CG-NO-QA-VERDICT]: the Closing report for $MERGED_REF carries no usable QA Pass 1 verdict block ($QA_STATE). Part 6 requires a fenced qa-pass-1 block whose every line is <criterion>: PASS|PARTIAL|FAIL, the criterion a bare identifier with no spaces, sitting inside the Closing report section at fence depth zero. none: no such block there; a block nested inside a pasted-report fence is content, and a fenced example in another section neither satisfies nor poisons this check. unclosed-comment: an HTML comment (<!--) was opened and never closed before the end of the spec, so what follows it cannot be read; close the comment with -->. unclosed: no closing fence. malformed: a line inside is not a verdict line, and a sentence is not a verdict however it reads. empty: the block has no criteria. Write the block at the left margin (three spaces of indent at most): this reader reads the document FLAT, so a block or fence indented four or more spaces, including inside a numbered list item, is indented code and is not read. Run QA Pass 1, write one line per criterion, paste the report below it, commit, then merge."
    fi

    # HISTORY: ruling CG-58 (2026-08-29), in the framework source's private hook-rulings record: The architecture-diagram field (Appendix C, exact label "Architecture.
    DIAG_LINE="$(printf '%s\n' "$SPEC_TEXT" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | head -n1)"
    if [[ -z "$DIAG_LINE" ]]; then
      deny "close gate [CG-NO-DIAGRAM-FIELD]: the Closing report for $MERGED_REF is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    fi
    DIAG_ANSWER="${DIAG_LINE#*Architecture diagram:}"
    # HISTORY: ruling CG-59 (undated), in the framework source's private hook-rulings record: PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11).
    DIAG_ANSWER="$(printf '%s' "$DIAG_ANSWER" | sed 's/<[^>]*>//g')"
    if ! printf '%s' "$DIAG_ANSWER" | sed 's/^[[:space:]]*//' | grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)'; then
      deny "close gate [CG-DIAGRAM-UNANSWERED]: the architecture-diagram field for $MERGED_REF is unanswered; answer it 'updated in this commit' or 'no impact', commit to the branch, then merge."
    fi

    # HISTORY: ruling CG-60 (undated), in the framework source's private hook-rulings record: STATUS.md carries the spec's inventory row, updated to CLOSED, on the.
    #
    # A note that references another spec is ordinary prose, not an attack, and
    # it blinded the gate on the one field that says whether the work is done.
    # The row has a shape, so the shape is read: field 4 of the pipe-delimited
    # row is the status, and it must BE closed rather than contain the word.
    # LIVE TEXT ONLY (2026-08 consolidation, blocker F2 and its mid-line
    # sibling). This gate reads STATUS.md's inventory row too, and read it RAW
    # while the guarantee layer stripped it: a fenced or commented `| NNNN | ...
    # | CLOSED |` example row satisfied CG-NO-STATUS-ROW here alone. Routed
    # through the same rule, so the advisory layer and the guarantee layer read
    # the row a human sees. LOCKSTEP: byte-identical to setlist-hook-lib.sh and
    # trunk-audit.sh; the agreement audit and the suite compare all three.
    STATUS_TEXT="$(git -C "$PROJ" show "${MERGED_REF}:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"
    # sed: a GFM \|-escaped pipe is literal, not a field separator (round 11).
    if ! printf '%s\n' "$STATUS_TEXT" | sed 's/\\|/ /g' | awk -F'|' -v num="$SPEC_NUM" '
      function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
      NF >= 5 && trim($2) == num && trim($4) == "CLOSED" { found = 1 }
      END { exit found ? 0 : 1 }
    '; then
      deny "close gate [CG-NO-STATUS-ROW]: specs/STATUS.md on branch $MERGED_REF has no inventory row marking spec $SPEC_NUM CLOSED; update the row in the same commit as the Closing report, then merge."
    fi
    fi
  fi
done

# THE GATE COMMAND IS NOT RUN HERE (2.6.0, spec 0132 cluster C; the contract
# at the head of this file says why). The git hook `pre-merge-commit` runs the
# instance's `close` tier once, at the merge, and refuses on failure
# (`SLH-GATE-COMMAND-FAILED`; an unrecorded command under a scaffolded instance
# `SLH-NO-GATE-COMMAND`). This gate reports the close conditions it can read
# without running anything, and the suite pins that a close runs the gate
# command exactly once across both layers.

# fail-open-ok: every close condition above was checked against the merged
# ref's committed tree and held; this is the gate's green path.
exit 0
