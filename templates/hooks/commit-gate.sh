#!/usr/bin/env bash
# SDD commit gate: PreToolUse on matcher "Bash", fires only on `git commit`.
# Stamped into the instance. Check 0 denies compound stage-and-commit commands
# (the gate can only scan content that is already staged when the hook runs);
# then three staged-content checks (Part 6): em-dash scan, secret scan,
# STATUS-in-same-commit. Each deny names the specific failure so the agent can
# fix and retry. Known residual hole: `git commit <pathspec>` commits the
# working-tree copy of the named path without staging; distinguishing a
# pathspec from a message word needs real shell parsing, so it is out of
# scope here and the split-form doctrine plus prompted discipline cover it.
# Deny mechanic verified live 2026-07-04 on Claude Code 2.1.200: JSON
# permissionDecision output, exit 0; the reason reaches the agent verbatim.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make every
# extraction below return empty, every check fall through, and the gate allow
# everything silently. Disable with a one-line edit: remove this hook's entry
# from .claude/settings.json.

set -u

# THE commit ADVISES, IT DOES NOT VETO (the advisory-gate decision, RATIFIED 2026-08-04).
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
#   permissionDecision   ALWAYS "allow", with ONE exception ruled 2026-09-06
#                        and stated in the next paragraph
#   setlistAdvisory      {gate, verdict: deny|allow, code, reason}
#   systemMessage        the reason, again, because permissionDecisionReason is
#                        documented as reaching the USER rather than the model
#                        when the decision is allow, and the point of a warning
#                        is that the session sees it.
#
# THE ONE DENY (ER1; the 2.6.0 strategy's ruling 1, 2026-09-06; spec 0132
# cluster B). A command that SPELLS a bypass of the git-hook boundary, an
# assignment of SETLIST_SKIP_HOOKS=1 or SETLIST_SKIP_TRUNK_AUDIT=1, `--no-verify`
# as a word in a git command, or `-c core.hooksPath` in a git command, is
# denied with permissionDecision "deny" (CM-BYPASS-SPELLED, CM-HOOKSPATH-MOVED).
# WHY this rule and no other: an advisory here is an allow with the reason in
# systemMessage, and the A1c probe has measured that reason NOT-SEEN by the
# model at every walk since 2.4.1 (RP5). A detection the model never sees is
# the coaching leak restated one layer up: the hook saw the bypass and told
# nobody who could act. This is the highest-confidence rule the layer could
# hold, and since fix round 1 of the 2.6.0 leg (2026-09-08) it is a WORD test,
# not a substring test: the command is lexed once, here, into segments and
# words the way the shell hands them to git (backslash escapes, single and
# double quotes, the separators), and a git segment carrying the word
# `--no-verify` or a prefix git accepts for it (`--no-verif`, `--no-veri`), the
# word `-n` or a bundled `-n` when the subcommand is `commit`, or
# `-c core.hooksPath` as words, is denied, as is any segment carrying the
# assignment word SETLIST_SKIP_HOOKS=1 or SETLIST_SKIP_TRUNK_AUDIT=1. The
# first cut deleted quoted SPANS with two sed substitutions and tested the
# remainder as text; that missed every spelling a quote touched (`"--no-verify"`
# is the flag to bash and to git alike), paired quotes ACROSS segments (the
# leg's F2, F3, F10, F11), and hard-denied prose it promised to allow (F8, F9).
# The lexer is LOCAL to this rule, runs ABOVE strip_wrappers and every
# segmenter below, and shares no byte with the frozen parsers (PD1 stands): a
# defect in the parsers cannot reach it. The false-denial surface is stated
# rather than discovered: a `-m` message is one word and never matches, a
# filename that CONTAINS the spelling is not the spelling, `-n` on `push` is a
# dry run and is not denied, and the reason says how a person proceeds. The
# residual: a message whose ENTIRE text is the spelling (`-m --no-verify`), a
# bypass reached through a variable or a here-document, and the whole-hook
# escape spelled to any value but 1; the git hooks such a command would bypass
# are the layer the design says carries the guarantee, and the forge check is
# the layer that survives it (2.6.0). The escapes stay DOCUMENTED, here and in
# the hooks' headers and the edition; what left in 2.6.0 is their spelling in
# the refusal text the model reads.
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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":%s},"systemMessage":%s,"setlistAdvisory":{"gate":"commit","verdict":"deny","code":%s,"reason":%s}}\n' \
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

# HISTORY: ruling CM-01 (plugin 2.0.0), in the framework source's private hook-rulings record: Advise with a fixed literal reason, for the paths where jq is unavailable to.
advise_literal() {
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"setlist %s","setlistAdvisory":{"gate":"commit","verdict":"deny","code":"%s","reason":"%s"}}\n' "$1" "$1" "$ADV_CODE" "$1"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$1"; }

# HISTORY: ruling CM-02 (plugin 2.4.0), in the framework source's private hook-rulings record: THE INPUT IS READ BY THE SHELL, NOT BY cat (spec 0130; the 2.4.0 leg's F12).
IFS= read -r -d '' INPUT || true
if [[ -z "$INPUT" ]]; then
  deny_literal "commit gate [CM-NO-INPUT]: this hook was given no payload at all, so the command being run cannot be read and this gate cannot check what it stages. If cat, bash or the harness pipe is broken this is what it looks like; run the commit again once the environment is repaired. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse)."
fi

# HISTORY: ruling CM-03 (plugin v1.7), in the framework source's private hook-rulings record: Decide WITHOUT jq when it is absent, and report.
JQ_STATE=ok
if ! command -v jq >/dev/null 2>&1; then
  JQ_STATE=absent
elif [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  # The probe compares OUTPUT, not only status (spec 0130; the 2.4.0 leg's F6):
  # `printf '{}' | jq -e .` discarded stdout, so a jq that exited 0 printing
  # nothing was classified usable and this gate emitted ZERO BYTES.
  JQ_STATE=broken
fi
# HISTORY: ruling CM-04 (plugin v1.7), in the framework source's private hook-rulings record: AND THE REST OF THE TOOLCHAIN, for exactly the same reason (v1.7 gate, F2).
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
    *commit*)
      deny_literal "commit gate [CM-NO-TOOLCHAIN]: $TOOLCHAIN_BROKEN is installed but does not work on this machine, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Run '$TOOLCHAIN_BROKEN --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the raw payload does not mention committing, so this is not a
    # command the gate governs, and gating every Bash call would block the very
    # command that repairs the broken tool.
    *) exit 0 ;;
  esac
fi

if [[ "$JQ_STATE" != "ok" ]]; then
  case "$INPUT" in
    *commit*)
      if [[ "$JQ_STATE" == "absent" ]]; then
        deny_literal "commit gate [CM-NO-JQ]: jq is not installed, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      fi
      deny_literal "commit gate [CM-JQ-BROKEN]: jq is installed but does not work on this machine (it exits nonzero, or exits 0 and prints nothing), so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: without a usable jq the raw payload does not mention
    # committing, so this is not a command the gate governs; gating every Bash
    # call would block the very install command that fixes the broken jq.
    *) exit 0 ;;
  esac
fi

# The status of THIS parse, not of jq in general. A jq that runs on {} can still
# fail on the payload in front of it, and a decision taken on a value that was
# never produced is the same fail-open one level down.
if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  case "$INPUT" in
    *commit*)
      deny_literal "commit gate [CM-JQ-UNPARSED]: jq could not parse the payload this hook was given, so the command being run cannot be read and this gate cannot check what it stages. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the unparseable payload does not mention committing either.
    *) exit 0 ;;
  esac
fi

# THE ONE DENY, above every parser (the contract paragraph at the head of this
# file says why). The command is lexed ONCE, here, into segments and words the
# way the shell would hand them to git, and nothing else is done to the text:
# no wrapper stripping, no normalisation, and none of the parsers below is
# consulted. A word is the act; a message is one word.
deny_hard() { # deny_hard <reason>  ->  permissionDecision "deny", the one rule that vetoes
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s},"systemMessage":%s,"setlistAdvisory":{"gate":"commit","verdict":"deny","code":%s,"reason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)" \
    "$(printf 'setlist %s' "$1" | jq -Rs .)" \
    "$(printf '%s' "$ADV_CODE" | jq -Rs .)" \
    "$(printf '%s' "$1" | jq -Rs .)"
  # fail-open-ok: this exit 0 delivers a DENY, not an allow: the harness reads
  # the JSON's permissionDecision, and a hook that exits non-zero would be an
  # error the harness reports rather than a verdict it enforces.
  exit 0
}
# HISTORY: ruling CM-05 (undated), in the framework source's private hook-rulings record: The lexer, in awk so the same bytes run under bash 3.2 and BWK awk.
BYPASS_LEX_AWK='
function flush() { if (inw) { W[++nw] = w }; w = ""; inw = 0 }
function judge(   j, g, k, sub_, x) {
  if (verdict != "") { nw = 0; return }
  for (j = 1; j <= nw; j++) if (W[j] ~ /^SETLIST_SKIP_(HOOKS|TRUNK_AUDIT)=1$/) { verdict = "var"; nw = 0; return }
  g = 0
  for (j = 1; j <= nw; j++) if (W[j] ~ /(^|\/)git$/) { g = j; break }
  if (g == 0) { nw = 0; return }
  # the subcommand: the first word after git that is not a global option or the
  # value of one (-c k=v, -C dir, --git-dir, --work-tree, --namespace, --exec-path)
  sub_ = ""; k = g + 1
  while (k <= nw && W[k] ~ /^-/) {
    if (W[k] == "-c" || W[k] == "-C" || W[k] == "--git-dir" || W[k] == "--work-tree" || W[k] == "--namespace" || W[k] == "--exec-path") k += 2; else k++
  }
  if (k <= nw) sub_ = W[k]
  for (j = g + 1; j <= nw; j++) {
    x = W[j]
    if (x == "--no-verify" || x == "--no-verif" || x == "--no-veri") { verdict = "noverify"; break }
    if (sub_ == "commit" && j > k && x ~ /^-[aeiopqsvz]*n[a-zA-Z]*$/) { verdict = "noverify"; break }
    if ((x == "-c" && j < nw && tolower(W[j + 1]) ~ /^core\.hookspath(=|$)/) || tolower(x) ~ /^-ccore\.hookspath(=|$)/) { verdict = "hookspath"; break }
  }
  nw = 0
}
BEGIN { RS = "\001"; cmd = ""; verdict = "" }
{ cmd = cmd $0 }
END {
  n = length(cmd); i = 1; w = ""; inw = 0; q = ""; nw = 0
  while (i <= n) {
    c = substr(cmd, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; else w = w c; inw = 1; i++; continue }
    if (q == "\"") {
      if (c == "\\") { d = substr(cmd, i + 1, 1); if (d == "\"" || d == "\\" || d == "$" || d == "`") { w = w d; i += 2 } else { w = w c; i++ }; continue }
      if (c == "\"") { q = ""; i++; continue }
      w = w c; inw = 1; i++; continue
    }
    if (c == "\\") { w = w substr(cmd, i + 1, 1); inw = 1; i += 2; continue }
    if (c == "\047" || c == "\"") { q = c; inw = 1; i++; continue }
    if (c == " " || c == "\t") { flush(); i++; continue }
    if (c == "#" && !inw) { while (i <= n && substr(cmd, i, 1) != "\n") i++; continue }
    if (c == ";" || c == "|" || c == "&" || c == "\n" || c == "(" || c == ")" || c == "{" || c == "}") {
      flush(); judge()
      if ((c == "&" || c == "|") && substr(cmd, i + 1, 1) == c) i++
      i++; continue
    }
    w = w c; inw = 1; i++
  }
  flush(); judge()
  print verdict
}'
BYPASS_VERDICT="$(printf '%s' "$CMD" | awk "$BYPASS_LEX_AWK" 2>/dev/null)" || BYPASS_VERDICT="" # fail-open-ok: an awk that cannot run yields no deny, and the toolchain probe above this rule has already refused a broken awk under CM-NO-TOOLCHAIN
BYPASS_WHAT=""
case "$BYPASS_VERDICT" in
  hookspath)
    deny_hard "commit gate [CM-HOOKSPATH-MOVED]: this git command moves core.hooksPath for its own run, which disarms every Setlist git hook at once (commit, merge and push) without touching the repository's configuration. This gate DENIES it (the one rule in this layer that does). If a hook refused something, fix what it named; if you are the person who owns this exception, run the command yourself in a terminal." ;;
  var)      BYPASS_WHAT="sets a Setlist escape variable, which switches the git-hook boundary off for everything it runs" ;;
  noverify) BYPASS_WHAT="passes --no-verify to git (or a spelling git reads as it), which skips the git hooks that carry the boundary for this one operation" ;;
esac
if [[ -n "$BYPASS_WHAT" ]]; then
  deny_hard "commit gate [CM-BYPASS-SPELLED]: this command $BYPASS_WHAT. The escapes exist for a PERSON who owns an exception, and a session does not get to spend them: this gate DENIES the command (the one rule in this layer that does). If the boundary refused something, fix what it named; if you are the person and this is your deliberate exception, run the command yourself in a terminal. A message that merely quotes the spelling is not denied."
fi

# HISTORY: ruling CM-06 (plugin 1.1.0), in the framework source's private hook-rulings record: Whether this gate applies must not depend on how the command is SPELLED.
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
CMD_NORM="$(printf '%s' "$CMD_HD" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | tr '\n\r' ';;' | tr -s '[:space:]' ' ')"
# HISTORY: ruling CM-07 (plugin 1.0.8), in the framework source's private hook-rulings record: Quoted spans are removed by a LEFT-TO-RIGHT scan, not by two sed passes.
CMD_BARE="$(printf '%s' "$CMD_NORM" | awk '{
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
# HISTORY: ruling CM-08 (plugin 1.1.0), in the framework source's private hook-rulings record: ONLY SOME GLOBAL OPTIONS TAKE A SEPARATE VALUE (1.1.0 leg, third run).
GIT_OPTS='( +(-[cC] +[^ ]+|--(exec-path|git-dir|work-tree|namespace|super-prefix|config-env|attr-source) +[^ ]+|-{1,2}[A-Za-z][^ ]*))*'

# HISTORY: ruling CM-09 (2026-07-28), in the framework source's private hook-rulings record: THE MARKER IS NOW READ, and until 2026-07-28 it was not.
if [[ "$CMD_BARE" == *"@@UNTERMINATED@@"* ]]; then
  case "$CMD" in
    *commit*)
      deny "commit gate [CM-UNLEXABLE]: this command contains an unterminated quote, so the gate could not determine where the command ends and cannot scan what would be staged. It refuses rather than guess. Balance the quotes, or move the text containing the apostrophe out of the command line, then retry."
      ;;
    # fail-open-ok: the input could not be lexed, but it does not mention
    # commit even in raw form, so it is not a command this gate governs and
    # refusing it would block unrelated work over an unbalanced quote.
    *) exit 0 ;;
  esac
fi

# HISTORY: ruling CM-10 (plugin 1.0.7), in the framework source's private hook-rulings record: The verbs that WRITE THE INDEX, which is the whole population Check 0 has to.
#
# THIS LIST IS A CORPUS DIMENSION, not a constant. test/run-tests.sh carries its
# own copy, asserts every verb in it is denied when compounded with a commit,
# and asserts the two lists are IDENTICAL, so a verb added here without a
# corpus entry (or the reverse) fails the suite. That lockstep is the point: the
# defect this list replaces was not a wrong pattern, it was a dimension nobody
# had enumerated, and the repo has now shipped that same shape three times (the
# wrapper axis, the dash-valued flag axis, this). An enumeration a reviewer must
# remember to extend is the same defect waiting.
INDEX_VERBS='add|stage|rm|mv|restore|reset|stash|checkout|switch|merge|pull|rebase|cherry-pick|revert|am|apply|update-index|read-tree|sparse-checkout'

# HISTORY: ruling CM-11 (plugin 1.0.6), in the framework source's private hook-rulings record: Segment-wise, for the same reason the close gate is (1.0.5).
strip_wrappers() { # strip_wrappers <segment> -> echoes the segment, unwrapped
  local seg="$1" prev=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    # HISTORY: ruling CM-12 (plugin 1.0.8), in the framework source's private hook-rulings record: SHELL GRAMMAR at the head of a segment (1.0.8, F9).
    seg="$(printf '%s' "$seg" | sed -E 's/^(\{|\}|!|if|then|elif|else|fi|while|until|do|done|for|select|case|esac|in|time|coproc)([[:space:]]+|$)//')"
    # leading VAR=val assignments (FOO=bar git ...)
    seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^ ]* *//')"
    # HISTORY: ruling CM-13 (plugin 1.0.8), in the framework source's private hook-rulings record: a wrapper word, plus env/stdbuf style flags and assignments after it.
    seg="$(printf '%s' "$seg" | sed -E 's/^[0-9]*(>>|>|<)[[:space:]]*(&[0-9-]+|[^ ]+)[[:space:]]*//')"
    # HISTORY: ruling CM-14 (2026-07-28), in the framework source's private hook-rulings record: A wrapper word, plus env/stdbuf style flags and assignments after it.
    seg="$(printf '%s' "$seg" | sed -E 's#^([^ ]*/)?(command|exec|nice|nohup|time|stdbuf|env) +##')"
    # HISTORY: ruling CM-15 (plugin 1.0.7), in the framework source's private hook-rulings record: A wrapper flag may take its value as a SEPARATE word (`nice -n 5 git.
    seg="$(printf '%s' "$seg" | sed -E 's/^-- +//')"
    if printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +([^ ]*/)?git( |$)'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +-[^ ]* +'; then
      # HISTORY: ruling CM-16 (plugin 1.0.7), in the framework source's private hook-rulings record: A flag value may itself begin with a dash.
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +-[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +[^- ][^ ]* +'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +[^- ][^ ]* +//')"
    else
      seg="$(printf '%s' "$seg" | sed -E 's/^(-{1,2}[^ ]* +)+//')"
    fi
  done
  printf '%s' "$seg"
}

# HISTORY: ruling CM-17 (2026-07-28), in the framework source's private hook-rulings record: The separator set. `&` is here as of 1.0.7.
SEGMENTS="$(printf '%s\n' "$CMD_BARE" | awk '{ gsub(/>&/, ">@@FD@@"); gsub(/<&/, "<@@FD@@"); gsub(/&&/, "\n"); gsub(/\|\|/, "\n"); gsub(/&/, "\n@@BG@@ "); gsub(/[;|()]/, "\n"); print }')"
HAS_COMMIT=""
HAS_STAGE=""
STAGE_PENDING=""
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  # Was the command BEFORE this segment backgrounded? Matched with and without
  # the trailing space, because the trim above has already removed it from a
  # marker-only segment.
  BACKGROUNDED=""
  case "$seg" in
    "@@BG@@ "*) BACKGROUNDED=1; seg="${seg#@@BG@@ }" ;;
    "@@BG@@")   BACKGROUNDED=1; seg="" ;;
  esac
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue
  seg="$(strip_wrappers "$seg")"
  [[ -n "$seg" ]] || continue
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +commit( |$)"; then
    # HISTORY: ruling CM-18 (2026-07-28), in the framework source's private hook-rulings record: EVERY commit segment is kept, not just the last one.
    HAS_COMMIT="${HAS_COMMIT}${HAS_COMMIT:+
}$seg"
    # An index writer seen EARLIER on this line stages content this commit will
    # carry, and the gate scanned the index before any of it existed. That is
    # the stale-index case check 0 is for, and it is the only one.
    if [[ -n "$STAGE_PENDING" && -z "$HAS_STAGE" ]]; then
      HAS_STAGE="$STAGE_PENDING"
    fi
  elif printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +($INDEX_VERBS)( |$)"; then
    # HISTORY: ruling CM-19 (plugin 1.1.0), in the framework source's private hook-rulings record: POSITION IS THE WHOLE POINT (1.1.0 adversarial review, F1).
    STAGE_PENDING="$seg"
    # ...unless the commit before it was BACKGROUNDED, in which case there is no
    # "before": the two run concurrently and the add can beat the commit to the
    # index. Position proves nothing across a `&`.
    if [[ -n "$BACKGROUNDED" && -n "$HAS_COMMIT" && -z "$HAS_STAGE" ]]; then
      HAS_STAGE="$seg"
    fi
  fi
done <<SEGEOF
$SEGMENTS
SEGEOF

if [[ -z "$HAS_COMMIT" ]]; then
  # fail-open-ok: no segment is a commit at command position; this gate
  # governs commits only.
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# HISTORY: ruling CM-20 (undated), in the framework source's private hook-rulings record: Check 0: compound stage-and-commit forms are denied outright (F4-1).
if [[ -n "$HAS_STAGE" ]]; then
  deny "commit gate [CM-INDEX-COMPOUND]: this command writes the index and commits in one step (git add, stage, rm, mv, restore, reset, stash, checkout, switch, merge, pull, rebase, cherry-pick, revert, am, apply, update-index, read-tree and sparse-checkout can all write the index during command execution, after this gate scanned it), so the gate would scan a stale index and check nothing. Run the index-writing command on its own first, then git commit separately; the gate scans the staged content and names any finding."
fi
# HISTORY: ruling CM-21 (plugin 1.1.0), in the framework source's private hook-rulings record: Read the COMMIT segment's own flags, not the whole line.
AUTOSTAGE="$(printf '%s\n' "$HAS_COMMIT" | awk '
function is_value_opt(w,   i, opts, n, o) {
  if (w !~ /^--[a-z-]+$/) return 0
  n = split("--message --file --author --date --template --cleanup --reuse-message --reedit-message --fixup --squash --trailer --pathspec-from-file", opts, " ")
  for (i = 1; i <= n; i++) { o = opts[i]; if (substr(o, 1, length(w)) == w) return 1 }
  return 0
}
function is_autostage(w,   i, opts, n, o) {
  if (w ~ /^-[a-zA-Z]+$/) { if (w ~ /[ai]/) return 1; return 0 }
  if (w !~ /^--[a-z-]+$/) return 0
  if (length(w) < 5) return 0
  n = split("--all --include --interactive", opts, " ")
  for (i = 1; i <= n; i++) { o = opts[i]; if (substr(o, 1, length(w)) == w) return 1 }
  return 0
}
{
  skip = 0
  for (i = 1; i <= NF; i++) {
    if (skip) { skip = 0; continue }
    w = $i
    if (w ~ /^(-m|-F|-c|-C|-t)$/ || is_value_opt(w)) { skip = 1; continue }
    if (w ~ /^--[a-z-]+=/) { if (is_autostage(substr(w, 1, index(w, "=") - 1))) { print "YES"; exit } ; continue }
    if (is_autostage(w)) { print "YES"; exit }
  }
}')"
if [[ "$AUTOSTAGE" == "YES" ]]; then
  deny "commit gate [CM-AUTOSTAGE-FLAG]: git commit with -a, -i, --all, or --include stages at commit time, so the gate would scan an empty index and check nothing. Stage the exact files with git add first, then run git commit without auto-staging flags."
fi

# HISTORY: ruling CM-22 (2026-09-02), in the framework source's private hook-rulings record: GIT IS PROBED BEFORE ITS ANSWER IS BELIEVED (F3 of the 2.2.0 adversarial.
#
# The comment at the foot of this file used to say "fail-open-ok: every check
# above ran against the staged content", which was false on precisely this path:
# the checks ran against nothing and found nothing, which is not the same as
# running against content and finding it clean. That is the
# empty-result-as-verdict class this whole layer exists to remove, asserted in a
# comment that made it look considered.
#
_cm_gitprobe="$(git -C "$PROJ" rev-parse --git-dir 2>/dev/null)" || _cm_gitprobe=""
CM_GIT_FAIL=""
CM_DIFF=""
CM_SPEC_DIFF=""
if [[ -z "$_cm_gitprobe" ]]; then
  CM_GIT_FAIL="git is not usable here (it is missing, broken, or this is not a git repository), so this gate cannot read the staged diff and would otherwise report every staged line clean having read nothing at all. Run 'git rev-parse --git-dir' in this directory to see the failure; a missing binary, a broken dynamic library, a wrong-architecture build and a directory that is not a repository all look like this."
elif ! CM_DIFF="$(git -C "$PROJ" diff --cached --unified=0 --no-color --no-ext-diff --no-textconv 2>/dev/null)"; then
  CM_GIT_FAIL="git ran here but could not render the staged diff (a configuration value git cannot parse, or a diff driver that fails, looks like this), so this gate cannot read the staged content and would otherwise report every staged line clean having read nothing at all. Run 'git diff --cached' in this directory to see the failure."
elif ! CM_SPEC_DIFF="$(git -C "$PROJ" diff --cached --unified=0 --no-color --no-ext-diff --no-textconv -- 'specs/*.md' ':(exclude)specs/STATUS.md' ':(exclude)specs/TEMPLATE.md' 2>/dev/null)"; then
  CM_GIT_FAIL="git ran here but could not render the staged diff of specs/, so this gate cannot tell whether this commit changes a spec's lifecycle state. Run 'git diff --cached -- specs' in this directory to see the failure."
fi
if [[ -n "$CM_GIT_FAIL" ]]; then
  deny "commit gate [CM-NO-GIT]: $CM_GIT_FAIL Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse)."
fi

# HISTORY: ruling CM-23 (2026-08-28), in the framework source's private hook-rulings record: THE ADVISORY SCANS ARE NOT PATH-SCOPED, AND THEY SAY SO (KL4-A1, owner ruling.
CG_ADDED_AWK='
{
  if ($0 ~ /^diff --git / || $0 ~ /^diff --cc /) { inhunk = 0; next }
  if (!inhunk && $0 ~ /^@@/) { inhunk = 1; next }
  if (!inhunk) next
  if ($0 ~ /^\+/) print
}'
# The staged diff was rendered and status-checked at the git probe above
# (RC2-2026): this is the read of what it produced, nothing more.
ADDED="$(printf '%s\n' "$CM_DIFF" | awk "$CG_ADDED_AWK" || true)"

# Check 1: em-dash scan on staged new content. The character is built from an
# escape so this script never contains it literally (repo rule 1 applies to the
# instances too).
EMDASH="$(printf '\342\200\224')"
if printf '%s\n' "$ADDED" | grep -q "$EMDASH"; then
  deny "commit gate [CM-EMDASH]: staged new content contains an em-dash; replace it with a comma, colon, parentheses, or separate sentences, then retry. NOTE: path exclusions (\"scan_exclusions\" in .claude/sdd.json) are evaluated at the git-hook layer, and this advisory does not read them, so a file your project excludes can be named here and still commit and push cleanly."
fi

# Check 2: secret scan. Token-shaped, connection-string-shaped, password-shaped.
# STUB NOTE: the pattern set is a first cut; tune it as dogfood and field runs
# surface false positives or misses.
if printf '%s\n' "$ADDED" | grep -qiE '(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'; then
  deny "commit gate [CM-SECRET]: staged content contains a secret-shaped string; move the value to the environment, reference it, and stage .env.example instead. NOTE: path exclusions (\"scan_exclusions\" in .claude/sdd.json) are evaluated at the git-hook layer, and this advisory does not read them, so a file your project excludes can be named here and still commit and push cleanly."
fi

# HISTORY: ruling CM-24 (undated), in the framework source's private hook-rulings record: Check 3: STATUS-in-same-commit.
#
# THE ENUMERATION IS A LOCKSTEP, AND IT IS THE CLASS FIX RATHER THAN THE
# INSTANCE FIX. This check recognises the lifecycle vocabulary LITERALLY, so a
# state the protocol gains and this list does not is not a missing feature: it
# is a lifecycle transition the gate silently allows through without asking for
# STATUS.md, which is a check quietly switching itself off. That is exactly what
# happened when the edition gained BUILT and PARKED: probed on the shipped hook,
# a staged `Status: CLOSED` without specs/STATUS.md denied, while `Status: BUILT`
# and `Status: PARKED` both allowed.
#
# So the list below is bound to the CANONICAL enumeration in the edition (Part 5,
# between the SDD-LIFECYCLE-STATES markers), which `scripts/part.sh
# lifecycle-states` extracts and the test suite compares against this line as a
# SET. Adding a state to the edition without adding it here turns the suite red.
# The binding is to an extractor a production path already uses, never to prose
# by grep, because a lockstep against prose is the same defect it exists to stop.
# B2's INDEX_VERBS pairing is the precedent.
CM_LIFECYCLE_STATES='DRAFT QUEUED ACTIVE REVISED BUILT PARKED CLOSED'
CM_STATES_RE="$(printf '%s' "$CM_LIFECYCLE_STATES" | tr ' ' '|')"
# HISTORY: ruling CM-25 (plugin v1.12), in the framework source's private hook-rulings record: THE RECORD, OR THE PAGE (RP1, edition v1.12).
#
# This gate keeps its own copy of the grammar rather than sourcing the
# library, because the two trees are deliberately separate (the KL4-A1
# ruling); what is shared is the RULE, and the suite asserts this value is
# byte-identical to the library's SLH_RECORD_CHECK_JQ.
CM_RECORD_CHECK_JQ='if (type != "object") or (.setlist_status != 1) or (((keys - ["setlist_status","specs","chores"]) | length) > 0) or (((.specs // {}) | type) != "object") or (((.chores // {}) | type) != "object") then "malformed" elif (((.specs // {}) | to_entries | all((.key | test("^[0-9]+[a-z]*$")) and (.value | if type != "object" then false else (((keys - ["status","qa_pass_1","diagram"]) | length) == 0) and (.status as $s | (["draft","queued","active","revised","built","parked","closed"] | index($s)) != null) and ((.qa_pass_1 == null) or (.qa_pass_1 == "ok")) and ((.diagram == null) or (.diagram == "updated") or (.diagram == "no-impact")) end))) | not) then "malformed" elif (((.chores // {}) | to_entries | all((.key | test("^CHORE-[0-9]+$")) and (.value | if type != "object" then false else (((keys - ["status","files"]) | length) == 0) and ((.status == "open") or (.status == "done")) and ((.files == null) or (((.files | type) == "array") and (.files | all(type == "string")))) end))) | not) then "malformed" else "ok" end'
# ONE DENY SITE, TWO TRIGGERS: the suite's rule that two denials sharing a
# code cannot be told apart binds the SITES, so the structured and legacy
# triggers set the message and one deny carries the code.
CM_SM_MSG=""
if [ -n "$(git -C "$PROJ" ls-files --cached -- .claude/status.json 2>/dev/null)" ]; then
  if git -C "$PROJ" diff --cached --name-only --diff-filter=M 2>/dev/null | grep -qx '.claude/status.json'; then
    if ! git -C "$PROJ" diff --cached --name-only | grep -qx 'specs/STATUS.md'; then
      CM_SM_MSG="this commit changes the status record (.claude/status.json) but does not stage specs/STATUS.md; /setlist:checkpoint writes the record and the human inventory page in the same commit, so a record change arriving alone is a hand edit or half a checkpoint."
    fi
  fi
  if git -C "$PROJ" diff --cached --name-only 2>/dev/null | grep -qx '.claude/status.json'; then
    CM_REC_STAGED="$(git -C "$PROJ" show ':.claude/status.json' 2>/dev/null || true)"
    CM_REC_VERDICT="$(printf '%s' "$CM_REC_STAGED" | jq -r "$CM_RECORD_CHECK_JQ" 2>/dev/null || printf 'malformed')"
    if [ "$CM_REC_VERDICT" != "ok" ]; then
      deny "commit gate [CM-RECORD-MALFORMED]: the staged .claude/status.json is not a well-formed status record, so no gate can read a close or chore fact from it and the git hooks will refuse it outright rather than falling back to the STATUS.md page. Only /setlist:checkpoint writes this file; fix the staged copy (Part 3 of the edition shows the grammar)."
    fi
  fi
else
  # Rendered and status-checked at the git probe above (RC2-2026): a rendering
  # this reader could not read is not "no lifecycle line was added".
  SPEC_ADDED="$(printf '%s\n' "$CM_SPEC_DIFF" | awk "$CG_ADDED_AWK" || true)"
  if printf '%s\n' "$SPEC_ADDED" | grep -qE "^\+Status:[[:space:]]*(${CM_STATES_RE})|^\+#+[[:space:]]*Closing report"; then
    if ! git -C "$PROJ" diff --cached --name-only | grep -qx 'specs/STATUS.md'; then
      CM_SM_MSG="this commit changes a spec lifecycle state but does not stage specs/STATUS.md; update the STATUS.md inventory line in the same commit."
    fi
  fi
fi
if [ -n "$CM_SM_MSG" ]; then
  deny "commit gate [CM-STATUS-MISSING]: $CM_SM_MSG"
fi

# HISTORY: ruling CM-26 (plugin 1.1.0), in the framework source's private hook-rulings record: Check 4: git identity (BL-007, new in plugin 1.1.0).
IDENTITY_EMAIL="$(jq -r '.identity.user_email // empty' "$PROJ/.claude/sdd.json" 2>/dev/null || true)"
if [[ -n "$IDENTITY_EMAIL" ]]; then
  # The exit status is carried: a git that cannot read its own config yields an
  # empty value, and an empty value must not silently equal the declared one.
  if ! ACTUAL_EMAIL="$(git -C "$PROJ" config user.email 2>/dev/null)"; then
    ACTUAL_EMAIL=""
  fi
  if [[ "$ACTUAL_EMAIL" != "$IDENTITY_EMAIL" ]]; then
    deny "commit gate [CM-IDENTITY]: this repository declares the git identity ${IDENTITY_EMAIL} in .claude/sdd.json, but git is configured to commit as ${ACTUAL_EMAIL:-<unset>}. Fix it with: git config user.email ${IDENTITY_EMAIL}"
  fi
fi

# HISTORY: ruling CM-27 (undated), in the framework source's private hook-rulings record: THE EXCEPTION THIS COMMENT USED TO NAME IS CLOSED.
#
# fail-open-ok: git was probed above, so every check above ran against staged
# content it actually read, and found nothing to deny; this is the gate's green
# path.
exit 0
