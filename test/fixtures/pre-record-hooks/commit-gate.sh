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

# Advise with a fixed literal reason, for the paths where jq is unavailable to
# escape one. The text must contain no double quotes, backslashes, or newlines.
#
# THE CODE IS EXTRACTED HERE TOO (F11-2026), and the reason this went three legs
# unfixed is worth stating: it never blocks. This function hardcoded `"code":""`
# while the gates' own frozen header promises
# `setlistAdvisory {gate, verdict, code, reason}`, so every literal-reason deny
# emitted a contract violation that nothing failed on. 1.1.0's adversarial review
# filed it as F21, 2.0.0's filed it as F12 with a full reproduction against a
# jq-less PATH, and it survived both for the same reason: a defect whose only
# consequence is a wrong field in a JSON object nobody asserts on is a defect
# with no way to make itself felt. The suite now asserts .setlistAdvisory.code
# rather than the reason text, which is what makes a fourth rediscovery
# impossible rather than unlikely.
#
# The extraction is sed, deliberately the SAME expression advise() uses, and it
# cannot use jq: this whole path exists because jq is unavailable.
advise_literal() {
  ADV_CODE="$(printf '%s' "$1" | sed -n 's/.*\[\([A-Z][A-Z0-9-]*\)\].*/\1/p')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"},"systemMessage":"setlist %s","setlistAdvisory":{"gate":"commit","verdict":"deny","code":"%s","reason":"%s"}}\n' "$1" "$1" "$ADV_CODE" "$1"
  # fail-open-ok: advisory by design; see advise() above.
  exit 0
}
deny_literal() { advise_literal "$1"; }

INPUT=$(cat)

# Decide WITHOUT jq when it is absent, and report. This gate is advisory since
# v1.7, so the verdict below is emitted with permissionDecision "allow": the
# GIT hooks are the layer that refuses. The raw payload is scanned instead of the
# parsed command so that a missing jq gates the commands this hook governs
# rather than every Bash call in the session: the agent can still run the
# install command that fixes it. The match is the bare word here, not "git
# commit": without jq there is no reliable parse, so this path errs toward
# denying anything that mentions committing at all.
#
# JQ PRESENT IS NOT JQ USABLE (leg 4, F1). `command -v jq` tests only whether a
# file of that name is on PATH. A jq that EXISTS and exits nonzero (a broken
# dynamic library, an out-of-memory kill, a wrong-architecture binary) walked
# past this guard, the parse below returned the empty string with its status
# discarded, the applicability test matched nothing, and the gate ALLOWED every
# commit in silence. Reproduced with a stub exiting 127 and an em-dash staged:
# healthy jq denied with CM-EMDASH, absent jq denied with CM-NO-JQ, broken jq
# allowed.
#
# Whether the dependency is INSTALLED is a different question from whether it
# WORKED, and only the second one matters. So jq is RUN here rather than merely
# located, and the parse below carries its own status.
JQ_STATE=ok
if ! command -v jq >/dev/null 2>&1; then
  JQ_STATE=absent
elif ! printf '{}' | jq -e . >/dev/null 2>&1; then
  JQ_STATE=broken
fi
# AND THE REST OF THE TOOLCHAIN, for exactly the same reason (v1.7 gate, F2).
#
# jq was the only tool anyone probed, while awk, sed, tr and grep are just as
# load-bearing: break any one of them and the normalised command came back empty,
# the applicability test matched nothing, and this gate ALLOWED every commit in
# silence. Each probe RUNS its tool and checks the OUTPUT as well as the status,
# because a tool that exits 0 and prints nothing breaks this gate just as
# thoroughly. The comparisons are bash builtins, so the probe never depends on
# the thing it is probing.
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
      deny_literal "commit gate [CM-JQ-BROKEN]: jq is installed but does not run on this machine, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse); removing this hook entry from .claude/settings.json is the deliberate way to work without it."
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

# Whether this gate applies must not depend on how the command is SPELLED.
# A literal "git commit" substring test let `git  commit` (two spaces),
# `git -C . commit`, `git --no-pager commit`, and `git -c k=v commit` past the
# gate untouched: it did not error, it stopped checking, in silence. Whitespace
# is squeezed once, quoted strings are dropped so a message mentioning the word
# cannot trip it, and git's own global options are tolerated between the binary
# and the subcommand.
# A HEREDOC BODY IS A QUOTING CONSTRUCT, AND THE LEXER DID NOT KNOW IT
# (1.1.0 adversarial review, F9). The line-joining below turns every newline into a
# separator, and a heredoc body is not inside quotes as far as the quote scan
# is concerned, so every LINE OF THE COMMIT MESSAGE became its own segment
# judged at command position. A message reading "git add . is no longer needed
# here" was denied as a compound stage-and-commit, and the remediation named no
# command the author could move, because there was none: the words were prose.
# The quoted spelling of the same message allows, so two spellings of one commit
# disagreed and the shorter one was the one that worked.
#
# Bash never executes these lines, so the gate must not read them. The body is
# removed BEFORE the join, which is the only place it is still identifiable.
# `<<<` is neutralised first: a herestring is not a heredoc, and without that
# guard `<<<WORD` matched at its second character and swallowed the rest of the
# command, which is a fail-open dressed as a fix.
#
# An unterminated heredoc drops everything after it. That is safe rather than
# convenient: bash would refuse the same command as a syntax error, so nothing
# the gate stops reading was ever going to run.
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
# Quoted spans are removed by a LEFT-TO-RIGHT scan, not by two sed passes.
#
# The two passes paired quote characters across the whole line, and across
# segments: `echo "it@s fine" && git commit -m "don@t ship"` (with @ an
# apostrophe) has the apostrophe of the first message pair with the apostrophe
# of the second, deleting everything between them including the `git commit`
# this gate exists to see. Reordering the passes does not fix it, it mirrors it:
# singles-first loses the case above, doubles-first loses `echo @a"b@ && git
# commit -m @c"d@`. Both spellings are asserted in the suite for exactly that
# reason.
#
# A scan has no such failure mode. Whichever quote opens first owns the span
# until its own closing character, which is what a shell does.
# QUOTED SPANS BECOME OPAQUE TOKENS (1.0.8, B3b and F5).
#
# The scan below used to DROP each quoted span outright, which is right for a
# message and wrong for a word: quoting the binary or the subcommand deleted the
# word this gate matches on, so `"git" commit -am x` and `git "commit" -am x`
# were not commits at all as far as Check 0 could see, and an odd number of
# quote characters anywhere in the line swallowed the real `git commit` with
# them.
#
# It keeps a span that is ONE shell-safe word (the binary, the subcommand, a
# path) and replaces anything else with `@@Q@@`, which cannot be a command word
# and cannot separate segments. Same model as the close gate now uses, from the
# opposite starting point: that gate kept too much and this one kept too little.
#
# THE PROGRAM BELOW MUST NOT END IN A BACKSLASH (1.0.9). From 1.0.8 it closed
# with `}\'` instead of `}'`, a stray byte gawk and mawk accept in silence. The
# BWK "one true awk" that macOS ships as /usr/bin/awk does not: it reports a
# syntax error, exits 2, and writes NOTHING to stdout. CMD_BARE then came out
# empty, the applicability grep below matched nothing, the gate concluded it had
# no commit to govern, and every Mac running 1.0.8 ALLOWED the commits this file
# exists to check. See the identical note in close-gate.sh; the two lexers broke
# together because they were written together.
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
# ONLY SOME GLOBAL OPTIONS TAKE A SEPARATE VALUE (1.1.0 leg, third run).
#
# This used to allow ANY option to swallow the next non-dash word, so the option
# run ate the SUBCOMMAND itself and any later bare word could satisfy the
# applicability test. `git --no-pager grep -n merge -- src` was therefore judged
# as a trunk merge and DENIED with CG-UNNAMEABLE-REF, telling the operator to
# author a Closing report for a grep. `git --no-pager log --grep merge` did the
# same. Agents in this harness write `git --no-pager ...` constantly.
#
# The subcommand is the first NON-OPTION word after git, so only the options
# that genuinely take a separate argument may consume one. The attached spellings
# (`--git-dir=x`, `-c k=v` written as one word) still match the generic branch,
# which is why that branch keeps no value clause at all.
GIT_OPTS='( +(-[cC] +[^ ]+|--(exec-path|git-dir|work-tree|namespace|super-prefix|config-env|attr-source) +[^ ]+|-{1,2}[A-Za-z][^ ]*))*'

# THE MARKER IS NOW READ, and until 2026-07-28 it was not.
#
# The awk above appends `@@UNTERMINATED@@` when a quote never closes, with a
# comment saying "a gate that cannot lex its input has not evaluated its
# predicate". That was the right sentence attached to nothing: no line ever
# tested for the marker, so the unlexable case fell straight through to the
# applicability test below, matched nothing (everything after the opening quote
# had been swallowed into the span), and the gate exited 0 as "not a commit".
#
# The reachable form is not adversarial. An apostrophe in a shell comment, a
# heredoc body, or an ANSI-C $'...' string leaves an odd quote count, and
# everything after it disappears including the governed git command.
#
# So it fails CLOSED, and the RAW command decides whether this gate is the one
# to refuse: the normalised text cannot be consulted, because the swallowing is
# the defect. A raw payload that never mentions commit is not this gate's
# business, and denying it would gate every Bash call in the session over a
# stray apostrophe.
# Tested against CMD_BARE, not CMD_NORM. This gate normalises TWICE: CMD_NORM
# is the whitespace pass and knows nothing about quotes, and CMD_BARE is the
# opaque-token pass that emits the marker. The first cut of this guard read
# CMD_NORM, so it never fired, and the payload below reached the gate unjudged
# while the close gate's identical guard worked. Two variables, one of them
# always empty of the thing being looked for, is how the marker went unread for
# a whole release in the first place.
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

# The verbs that WRITE THE INDEX, which is the whole population Check 0 has to
# recognise. Until 1.0.7 this enumeration was `add|rm|mv`, so every other verb
# that writes the index could be compounded with a commit and all three
# staged-content checks below would read an index nobody had judged:
#
#     git stash pop && git commit -m x        <- allowed, index changed after the scan
#     git restore --staged . && git commit -m x
#
# `stage` is here because it is a plain synonym for `add` and was simply never
# written down. The rest are the verbs whose documented effect includes writing
# the index, whether or not that is their headline purpose: a branch switch, a
# merge with --no-commit, a half-applied cherry-pick and a plumbing read-tree
# all leave an index the scan above did not see.
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

# Segment-wise, for the same reason the close gate is (1.0.5). A command line
# is not one command, and a whole-line grep cannot tell an operation from a
# mention of one: `echo git add . && git commit -m x` was denied though the
# only staging in it is a word being printed. The generated commit-gate corpus
# found that on its first run. Each segment is judged at COMMAND POSITION.
# Strip the ways a shell legitimately STARTS a git command before judging
# whether a segment is one (1.0.6). The command-position test that removed the
# `echo git merge ...` false positive introduced this false negative: a segment
# is only judged when it starts with `git`, so `command git merge ...`,
# `env git merge ...` and `nice git merge ...` were never judged at all.
#
# The allowlist is deliberately NOT a claim of completeness: `timeout`,
# `setsid`, `ionice`, `sudo`, `xargs` and whatever comes next are not covered,
# and no allowlist can be, because this is the shell-escape-hatch family. It
# closes the forms a person or an agent actually types. The designed catch for
# the whole family is the trunk audit, which reads the outcome in history and
# does not care how the command was spelled.
strip_wrappers() { # strip_wrappers <segment> -> echoes the segment, unwrapped
  local seg="$1" prev=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    # SHELL GRAMMAR at the head of a segment (1.0.8, F9). A segment is only
    # judged when its command word sits at the front, and shell has a whole
    # vocabulary for putting something else there first:
    #
    #     { git merge --no-ff spec/0001-x; }
    #     if true; then git merge --no-ff spec/0001-x; fi
    #     for i in 1; do git merge --no-ff spec/0001-x; done
    #     ! git merge --no-ff spec/0001-x
    #
    # All four executed a real merge onto the trunk with every close check
    # skipped, because after the splitter ran the segment began with `{`, `then`,
    # `do` or `!` rather than with git. These are not exotic: `!` is how you
    # invert an exit status and `{ ...; }` is how you group commands, and the
    # oracle reproduces all four as merges that actually land.
    #
    # They are grammar, not commands, so they are removed the same way a wrapper
    # word is. This list IS closed in a way the wrapper allowlist is not: these
    # are bash reserved words, a fixed set defined by the language, rather than
    # the open-ended family of programs that can exec another program.
    seg="$(printf '%s' "$seg" | sed -E 's/^(\{|\}|!|if|then|elif|else|fi|while|until|do|done|for|select|case|esac|in|time|coproc)([[:space:]]+|$)//')"
    # leading VAR=val assignments (FOO=bar git ...)
    seg="$(printf '%s' "$seg" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^ ]* *//')"
    # a wrapper word, plus env/stdbuf style flags and assignments after it
    # A LEADING REDIRECTION is not a command either (F18 of the 1.0.8 leg).
    # `>/dev/null git merge ...`, `2>/dev/null git merge ...` and
    # `< /dev/null git merge ...` all put something other than git at the head
    # of the segment, so the command-position test below never fired and the
    # merge landed unjudged. The oracle reproduced 115 of these across four
    # redirection forms once the corpus was taught to generate them.
    #
    # Redirections are ordinary rather than adversarial: a caller silencing
    # output writes one without thinking about parsers. Each pass strips one
    # and the loop runs to a fixed point, so `>/tmp/out 2>&1 git ...` unwinds.
    seg="$(printf '%s' "$seg" | sed -E 's/^[0-9]*(>>|>|<)[[:space:]]*(&[0-9-]+|[^ ]+)[[:space:]]*//')"
    # A wrapper word, plus env/stdbuf style flags and assignments after it.
    # The optional leading PATH matters: stripping was name-only until
    # 2026-07-28, so `/usr/bin/env git merge ...` and `/bin/nice git merge ...`
    # walked a governed command past both gates unjudged (F17). An absolute
    # path is how a shebang and most generated command lines spell it.
    seg="$(printf '%s' "$seg" | sed -E 's#^([^ ]*/)?(command|exec|nice|nohup|time|stdbuf|env) +##')"
    # A wrapper flag may take its value as a SEPARATE word (`nice -n 5 git
    # commit -am x`), and consuming the flag alone strands the value at the
    # head of the segment, where it defeats the command-position test. The
    # command word is never eaten as a value: `env -i git commit ...` has git
    # sitting exactly where a value would be. Same defect and same fix as
    # close-gate.sh, repeated because the two hooks each carry their own copy
    # and a repair in one is not a repair in the other.
    # The bare `--` option terminator is not a flag, not a value and not a
    # command: it is punctuation that every branch below ignored, so it sat at
    # the head of the segment and defeated the command-position test on its own.
    # v1.0.6 DENIED `env -- git merge ...`; 1.0.7 allowed it until this line.
    seg="$(printf '%s' "$seg" | sed -E 's/^-- +//')"
    if printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +([^ ]*/)?git( |$)'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +-[^ ]* +'; then
      # A flag value may itself begin with a dash: `nice -n -5 git ...` is an
      # ordinary negative niceness. The value branch below requires a NON-dash
      # value, so `-n` was consumed one word at a time and `-5` was stranded at
      # the head, which is the same stranding the value branch was written to
      # stop. v1.0.6 DENIED this; 1.0.7 allowed it until this branch.
      #
      # It sits AFTER the git branch on purpose. That branch has already taken
      # any case where the command word follows the flag directly, so nothing
      # here can eat git: a dash-leading word is never the command.
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +-[^ ]* +//')"
    elif printf '%s' "$seg" | grep -qE '^-{1,2}[^ ]* +[^- ][^ ]* +'; then
      seg="$(printf '%s' "$seg" | sed -E 's/^-{1,2}[^ ]* +[^- ][^ ]* +//')"
    else
      seg="$(printf '%s' "$seg" | sed -E 's/^(-{1,2}[^ ]* +)+//')"
    fi
  done
  printf '%s' "$seg"
}

# The separator set. `&` is here as of 1.0.7: a SINGLE ampersand backgrounds the
# preceding command and starts a new one, exactly as `;` does, and its absence
# meant `git stash pop & git commit -m x` collapsed to one unrecognised segment.
# Both gates carry their own copy of this line, so this is fixed in both; a
# repair in one has already failed to be a repair in the other more than once.
#
# `&&` must not become two separators. It does not: POSIX ERE alternation is
# leftmost-LONGEST, the two-character alternative is listed first, and the
# behaviour is asserted in the suite rather than trusted, because "the awk on
# the reviewer's machine" is precisely the assumption the macOS leg exists to
# doubt. Even if it did split, the empty middle segment is skipped below, so
# this is belt and braces on a case that must not regress silently.
# A REDIRECTION'S `&` IS NOT A CONTROL OPERATOR (2026-07-28). `2>&1` is one
# token meaning "send stderr where stdout goes", but the splitter below treats
# a bare `&` as a segment separator (correctly, since `a & b` backgrounds a),
# so `>/tmp/out 2>&1 git merge ...` was cut into `>/tmp/out 2>` and
# `1 git merge ...`. Neither fragment begins with git, so the command-position
# test never fired and the merge landed unjudged. The oracle showed this as the
# last 27 misses after the leading-redirection fix, all of them carrying `2>&1`.
#
# The fd-duplication forms are neutralised BEFORE the split, so the `&` inside
# them can never be read as a separator. Two literal substitutions rather than a
# capture-group rewrite, because POSIX awk gsub has no backreferences and a
# clever regex here would be the third thing in this file to be too clever.
#
# A SINGLE `&` IS NOT A SEQUENCER, and the positional rule below depends on the
# difference. `&&`, `;` and `|` all guarantee the previous command finished
# before the next starts; `&` BACKGROUNDS it, so `git commit -m x & git add -A`
# runs both at once and the add really can reach the index before the commit
# reads it. That is the stale-index case, and it survives the position check
# that correctly clears `git commit -m x && git add -A`. Marked rather than
# flattened so the loop can tell them apart: the suite caught this the first
# time the position check was written without it, which is what that corpus is
# for.
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
    # EVERY commit segment is kept, not just the last one. This was a plain
    # assignment until 2026-07-28, so a second `git commit` appended to a line
    # overwrote the first and the auto-staging check below then inspected the
    # harmless one:
    #
    #     git commit -am x && git commit -m y
    #
    # The -am segment is the one that stages and commits in a single step,
    # which is the whole population CM-AUTOSTAGE-FLAG exists to catch, and it
    # was silently dropped. A command can carry more than one commit and the
    # gate has to answer for all of them; keeping only the last is a decision
    # about which one to ignore.
    #
    # The checks downstream read this as newline-separated segments, and
    # `grep -q` over several lines matches when ANY line matches, which is the
    # semantics wanted: one offending commit in a compound is enough to deny.
    HAS_COMMIT="${HAS_COMMIT}${HAS_COMMIT:+
}$seg"
    # An index writer seen EARLIER on this line stages content this commit will
    # carry, and the gate scanned the index before any of it existed. That is
    # the stale-index case check 0 is for, and it is the only one.
    if [[ -n "$STAGE_PENDING" && -z "$HAS_STAGE" ]]; then
      HAS_STAGE="$STAGE_PENDING"
    fi
  elif printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +($INDEX_VERBS)( |$)"; then
    # POSITION IS THE WHOLE POINT (1.1.0 adversarial review, F1). This recorded any
    # index writer ANYWHERE on the line and check 0 denied on its presence
    # alone, so `git commit -m "x" && git checkout -` was refused: the canonical
    # spec-branch workflow this framework prescribes, commit on the branch and
    # return to where you were. The remedy the message gives ("run the
    # index-writing command on its own first") inverts the author's intent,
    # because they deliberately put it second.
    #
    # The rationale check 0 states is entirely positional: the index writer runs
    # "after this gate scanned it, so the gate would scan a stale index". When
    # the commit runs FIRST, the index the gate scanned is exactly the index
    # that gets committed and every staged-content check below is meaningful.
    # So the pending writer is remembered, and it only becomes a finding when a
    # commit segment follows it. The very next check was already careful about
    # this same attribution problem; check 0 was not.
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

# Check 0: compound stage-and-commit forms are denied outright (F4-1). This
# hook runs BEFORE the command, so a command that both stages and commits
# would have its staged-content checks below scan an index that does not yet
# hold the content: every check would pass vacuously.
if [[ -n "$HAS_STAGE" ]]; then
  deny "commit gate [CM-INDEX-COMPOUND]: this command writes the index and commits in one step (git add, stage, rm, mv, restore, reset, stash, checkout, switch, merge, pull, rebase, cherry-pick, revert, am, apply, update-index, read-tree and sparse-checkout can all write the index during command execution, after this gate scanned it), so the gate would scan a stale index and check nothing. Run the index-writing command on its own first, then git commit separately; the gate scans the staged content and names any finding."
fi
# Read the COMMIT segment's own flags, not the whole line: another command's
# -a on the same line is not this commit's auto-staging flag.
#
# GIT ACCEPTS ABBREVIATIONS, and this check matched fixed strings (1.1.0
# adversarial review, F14). `git commit --inc src/a.txt -m "x"` ALLOWED while
# `--include` denied; so did `--incl`, `--inclu`, `--includ` and `--interacti`,
# all of them accepted by real git. close-gate.sh learned this exact class as
# leg 5's F5 and closed it by matching a PREFIX rather than a list, and its own
# comment says why: "enumerating abbreviations would be the same mistake as
# enumerating wrapper names". One file was left behind, which is this
# repository's signature failure, so the close gate's approach is ported here
# rather than reinvented.
#
# AN OPTION'S VALUE IS NOT AN OPTION (1.1.0 adversarial review, F10). The scan ran over
# the raw segment, so `git commit -m "-fix"` was denied as auto-staging: the
# one-word message survives the lexer as a bare word and the old regex matched
# the `i` in it. `-m "-i18n strings"` allowed, because a multi-word span becomes
# @@Q@@, so the one-word message was the unlucky spelling. Value-taking options
# are dropped WITH their values first, exactly as the close gate's MARGS
# stripper does, and then the flags are read.
#
# The prefix match requires five characters (`--all`, `--inc`, `--int` are all
# five) so a shorter fragment that git itself rejects as ambiguous is not
# treated as a flag here.
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

# GIT IS PROBED BEFORE ITS ANSWER IS BELIEVED (F3 of the 2.2.0 adversarial
# review, deferred to this cycle under a recorded owner bound and REINSTATED
# here from the patch parked with its backlog entry rather than rediscovered).
#
# V19-F1 put this probe into close-gate.sh and scope-hook.sh in the 2.2.0 cycle
# and did not put one here, so this file was the third sibling of a rule that
# then existed in two places and not the third: A9's exact shape. Measured on
# the shipped bytes: with git exiting 127, absent from PATH, or present but
# printing nothing, every read below yields the EMPTY STRING, every grep over it
# misses, and a staged em-dash AND a staged secret-shaped string are both
# reported clean at exit 0 with zero bytes of output.
#
# The comment at the foot of this file used to say "fail-open-ok: every check
# above ran against the staged content", which was false on precisely this path:
# the checks ran against nothing and found nothing, which is not the same as
# running against content and finding it clean. That is the
# empty-result-as-verdict class this whole layer exists to remove, asserted in a
# comment that made it look considered.
#
# It RUNS git and checks the OUTPUT as well as the status, like its two
# siblings: a git that exits 0 and prints nothing disables these reads just as
# thoroughly. The gate is advisory since v1.7, so this warns and permits; the
# git hooks are what refuse.
_cm_gitprobe="$(git -C "$PROJ" rev-parse --git-dir 2>/dev/null)" || _cm_gitprobe=""
if [[ -z "$_cm_gitprobe" ]]; then
  deny "commit gate [CM-NO-GIT]: git is not usable here (it is missing, broken, or this is not a git repository), so this gate cannot read the staged diff and would otherwise report every staged line clean having read nothing at all. Run 'git rev-parse --git-dir' in this directory to see the failure; a missing binary, a broken dynamic library, a wrong-architecture build and a directory that is not a repository all look like this. Gates report their verdict and PERMIT (they are advisory since v1.7, so this is a warning and not a block; the git hooks are what refuse)."
fi

# THE ADVISORY SCANS ARE NOT PATH-SCOPED, AND THEY SAY SO (KL4-A1, owner ruling
# 2026-08-28: the divergence closes by HONESTY, not by coupling).
#
# The git-hook layer honours "scan_exclusions" from .claude/sdd.json through one
# function in its shared library. This gate runs its own scans, in a different
# tree, and does not read that set: with vendor/** excluded and a secret in
# vendor/, this layer objects to a commit the guarantee layer accepts.
#
# NEITHER EXPENSIVE ROUTE WAS BOUGHT, and the ruling says why. Sourcing the
# shared library from templates/hooks/ creates a dependency between two trees
# that are deliberately separate; a second exclusion reader is an A9 violation
# of exactly the kind that feature's own acceptance criterion forbids. What
# makes the divergence costly is not the warning, which is noise from a layer
# that cannot refuse anything, but the user's inability to tell whether the
# commit will actually be blocked. One sentence in each refusal answers exactly
# that question at the moment it is asked, for the price of one string.
#
# THE FULL FIX STAYS AVAILABLE AND STAYS UNBOUGHT, on one named condition: field
# reports showing the over-warning actually costing users. The suite assertion
# pinning this divergence in its CURRENT direction stays as it is, so the entry
# cannot close by drift.
#
# Staged additions only: lines the commit would introduce.
# POSITIONAL HEADER CONSUMPTION (2.3.0 leg, F5), the advisory half of the same
# defect the guarantee layer carried as F3. This read `grep -vE '^\+\+\+'`,
# which drops the diff's own header AND any added line whose content begins
# `++`: a unified diff prefixes added lines with one `+`, so `++ b/x` arrives
# as `+++ b/x` and no single-line pattern can tell it from a header. A secret
# on such a line was deleted from this gate's input before the scan ran.
#
# The separating fact is position, which is git's own structure: a `+++` line
# is a header only outside a hunk. This gate keeps its own copy rather than
# sourcing the library, because the two trees are deliberately separate (the
# KL4-A1 ruling); what is shared is the RULE, and the suite asserts both layers
# refuse the same payload.
CG_ADDED_AWK='
{
  if ($0 ~ /^diff --git / || $0 ~ /^diff --cc /) { inhunk = 0; next }
  if (!inhunk && $0 ~ /^@@/) { inhunk = 1; next }
  if (!inhunk) next
  if ($0 ~ /^\+/) print
}'
ADDED="$(git -C "$PROJ" diff --cached --unified=0 2>/dev/null | awk "$CG_ADDED_AWK" || true)"

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

# Check 3: STATUS-in-same-commit. A staged spec lifecycle transition (Status
# line change or a Closing report section added) requires specs/STATUS.md in
# the same commit. Ordinary mid-build spec edits do not trip it. The formats
# bound here are Appendix C exactly: the header line "Status: QUEUED" (bare
# label, one lifecycle state) and the "## Closing report" heading.
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
SPEC_ADDED="$(git -C "$PROJ" diff --cached --unified=0 -- 'specs/*.md' ':(exclude)specs/STATUS.md' ':(exclude)specs/TEMPLATE.md' 2>/dev/null | awk "$CG_ADDED_AWK" || true)"
if printf '%s\n' "$SPEC_ADDED" | grep -qE "^\+Status:[[:space:]]*(${CM_STATES_RE})|^\+#+[[:space:]]*Closing report"; then
  if ! git -C "$PROJ" diff --cached --name-only | grep -qx 'specs/STATUS.md'; then
    deny "commit gate [CM-STATUS-MISSING]: this commit changes a spec lifecycle state but does not stage specs/STATUS.md; update the STATUS.md inventory line in the same commit."
  fi
fi

# Check 4: git identity (BL-007, new in plugin 1.1.0). One machine often holds a
# work identity and a personal one, and a commit under the wrong one is annoying
# on a private repo and a compliance problem on a work or public one. Catching it
# at COMMIT time is earlier and cheaper than at push time, when the fix is a
# rebase rather than an amend.
#
# OPT-IN BY CONSTRUCTION, and that is the whole compatibility story: no
# `identity` key means no check and no output. Every instance stamped before this
# release therefore behaves exactly as it did. A project that wants the check
# adds one key; nothing infers an identity from the machine, because the value of
# this check is that somebody DECLARED which identity this repo uses, and a
# gate that guesses would just ratify whatever was already configured.
# jq is already proven working by this point: this gate fails CLOSED on a missing
# or broken jq long before check 1, so an empty read here means an absent key
# rather than a silent parse failure.
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

# THE EXCEPTION THIS COMMENT USED TO NAME IS CLOSED. It read "the green path has
# one named exception", because if git was unusable every read above yielded the
# empty string and this path was reached having examined NOTHING rather than
# having examined content and found it clean. The probe above (F3-2026) is that
# exception's fix, and the annotation is corrected in the same commit rather
# than left describing a hole that no longer exists: a comment that outlives the
# defect it documents is the KL6 shape, and this file is not going to teach it
# twice.
#
# fail-open-ok: git was probed above, so every check above ran against staged
# content it actually read, and found nothing to deny; this is the gate's green
# path.
exit 0
