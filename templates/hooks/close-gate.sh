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
# because this gate re-runs the project's whole suite and is the entry most
# likely to run long. The unit is SECONDS, and the key is honoured: a hook
# sleeping 3s under "timeout": 10 delivered its deny, and the same hook under
# "timeout": 1 was CANCELLED and the tool call PROCEEDED. That second result is
# the fail-open this gate's timeout exists to prevent, so it is measured here
# rather than assumed. The template ships 1800 (30 minutes) for this entry.
# Requires jq, and FAILS CLOSED without it: a missing jq used to make every
# extraction below return empty, every check fall through, and the gate allow
# every merge unchecked. Disable with a one-line edit: remove this hook's entry
# from .claude/settings.json.

set -u

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)"
  # fail-open-ok: not a pass at all; exit 0 is how the hook protocol delivers
  # the deny JSON emitted above.
  exit 0
}

# Deny with a fixed literal reason, for the paths where jq is unavailable to
# escape one. The text must contain no double quotes, backslashes, or newlines.
deny_literal() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  # fail-open-ok: not a pass at all; exit 0 delivers the deny JSON above.
  exit 0
}

INPUT=$(cat)

# Fail closed when jq is absent. The raw payload is scanned instead of the
# parsed command so that a missing jq gates the merges this hook governs
# rather than every Bash call in the session.
#
# JQ PRESENT IS NOT JQ USABLE (leg 4, F1). This file said that sentence a
# hundred lines further down and did not act on it. The guard was
# `command -v jq`, which tests only whether a file of that name is on PATH, and
# a jq that EXISTS and exits nonzero (a broken dynamic link, an OOM kill, the
# wrong architecture) walked straight past it. The parse below then produced the
# empty string with its status discarded, the applicability grep matched
# nothing, and the gate ALLOWED every merge in silence. Reproduced with a stub
# printing a loader error and exiting 127: healthy jq denied, absent jq denied,
# broken jq allowed.
#
# That is the shape this class always has: the gate's INPUT fails to
# materialise, the empty result is indistinguishable from "nothing to govern",
# and absence reads as permission. Whether the dependency is INSTALLED is a
# different question from whether it WORKED, and only the second one matters.
#
# So jq is RUN here, not merely located, and the parse below carries its status.
JQ_STATE=ok
if ! command -v jq >/dev/null 2>&1; then
  JQ_STATE=absent
elif ! printf '{}' | jq -e . >/dev/null 2>&1; then
  JQ_STATE=broken
fi
if [[ "$JQ_STATE" != "ok" ]]; then
  case "$INPUT" in
    *merge*)
      if [[ "$JQ_STATE" == "absent" ]]; then
        deny_literal "close gate [CG-NO-JQ]: jq is not installed, so this gate cannot verify the Closing report, the QA verdict, or the inventory row, and would otherwise allow every merge unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      fi
      deny_literal "close gate [CG-JQ-BROKEN]: jq is installed but does not run on this machine, so this gate cannot verify the Closing report, the QA verdict, or the inventory row, and would otherwise allow every merge unchecked. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: without a usable jq the raw payload does not mention
    # merging, so this is not a command the gate governs; gating every Bash call
    # would block the very install command that fixes the broken jq.
    *) exit 0 ;;
  esac
fi

# The status of THIS parse, not of jq in general. A jq that runs on {} can still
# fail on the payload in front of it, and a decision taken on a value that was
# never produced is the same fail-open one level down.
if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  case "$INPUT" in
    *merge*)
      deny_literal "close gate [CG-JQ-UNPARSED]: jq could not parse the payload this hook was given, so the command being run cannot be read and this gate cannot tell whether it merges into the trunk. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      ;;
    # fail-open-ok: the unparseable payload does not mention merging either, so
    # it is not a command this gate governs.
    *) exit 0 ;;
  esac
fi

# Whether this gate applies must not depend on how the command is SPELLED.
# A literal "git merge" substring test let `git  merge`, `git -C . merge`, and
# `git --no-pager merge` past untouched. Whitespace is squeezed, quotes are
# removed (not their contents: the branch name is an argument this gate needs),
# and git's global options are tolerated before the subcommand.
# QUOTED SPANS BECOME OPAQUE TOKENS (1.0.8, B1 and F4/F6/F7).
#
# This line used to end in `tr -d "\"'"`, which deletes quote CHARACTERS and
# keeps their CONTENTS. So free text was fed to the parser as if it were code:
#
#     git commit -m "todo (git checkout spec/0002-other)" && git merge --no-ff spec/0001-thing
#
# The branch tracker read a `git checkout` out of a commit MESSAGE, believed the
# merge ran on spec/0002-other, and skipped it. Separators inside quotes split
# segments, and words inside quotes supplied command names.
#
# The obvious repair is the commit gate's: drop the span entirely. It was tried
# on 2026-07-27 and reverted, because this gate NEEDS quoted arguments:
# `git merge "spec/0001-thing"` loses its ref and three assertions go red.
#
# So the test is what the span CONTAINS, not whether it exists. A ref cannot
# contain a space, and neither can a binary or a subcommand name; a message
# almost always does. One shell-safe word is kept as that word. Everything else
# becomes `@@Q@@`, a single token that is not a command, not a separator, and not
# a ref, so it can contribute nothing to any decision. That is the opaque-token
# model from design-opaque-token-gate-parsing.md, and it needs no placeholder map
# precisely because the only spans worth reading are the ones that survive.
#
# An UNTERMINATED quote appends a marker rather than silently swallowing the rest
# of the line. A gate that cannot lex its input has not evaluated its predicate.
CMD_NORM="$(printf '%s' "$CMD" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | tr '\n\r' ';;' | tr -s '[:space:]' ' ' | awk '{
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
}\')"
GIT_OPTS='( +-{1,2}[A-Za-z][^ ]*( +[^- ][^ ]*)?)*'

# THE MARKER IS NOW READ, and until 2026-07-28 it was not.
#
# The awk above appends `@@UNTERMINATED@@` when a quote never closes, with a
# comment saying "a gate that cannot lex its input has not evaluated its
# predicate". That was the right sentence attached to nothing: no line ever
# tested for the marker, so the unlexable case fell straight through to the
# applicability test below, matched nothing (everything after the opening quote
# had been swallowed into the span), and the gate exited 0 as "not a merge".
#
# The reachable form is not adversarial. An apostrophe in a shell comment, a
# heredoc body, or an ANSI-C $'...' string leaves an odd quote count, and
# everything after it disappears including the governed git command.
#
# So it fails CLOSED, and the RAW command decides whether this gate is the one
# to refuse: the normalised text cannot be consulted, because the swallowing is
# the defect. A raw payload that never mentions merge is not this gate's
# business, and denying it would gate every Bash call in the session over a
# stray apostrophe.
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

# The config must PARSE, for the same reason the scope hook now requires it: a
# truncated sdd.json makes TRUNK read empty, so the trunk comparison below can
# never match and every merge passes unchecked. jq present is not jq usable.
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
  deny_literal "close gate [CG-SDD-SHAPE]: .claude/sdd.json is not a single JSON OBJECT (it does not parse, or it is an array, or it contains more than one document), so this gate cannot read the trunk name and cannot tell whether this merge lands on the trunk. It would otherwise allow every merge unchecked. Fix the file (jq -s . .claude/sdd.json shows both the syntax and how many documents it holds), then retry. Gates fail closed by design."
fi

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
[[ -n "$TRUNK" ]] || deny "close gate [CG-TRUNK-INVALID]: .claude/sdd.json declares a "trunk" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set "trunk" to your trunk branch name (for example "main" or "master"), or remove the key to accept the default."

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
    deny "close gate [CG-TRUNK-NOT-A-BRANCH]: .claude/sdd.json records trunk \"$TRUNK\", which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which is what the upgrade skill's own detection command returns."
  fi
fi

# --- segment-wise evaluation (1.0.5) -----------------------------------------
#
# A command line is not one command, and every parser this gate has shipped
# did string surgery on the whole line. Each was defeated by that assumption:
#
#   1.0.3 scanned every word, so `git checkout spec/0001-x && git merge main`
#         read the spec branch off the CHECKOUT and gated the wrong operation.
#   1.0.4 took the text after the LAST " merge ". That discarded the first
#         merge's arguments outright (`git merge spec/X && git merge main`
#         passed with nothing checked) and handed the parser a commit MESSAGE
#         whenever one contained the word (`-m "improve merge of main"`
#         passed). A generated corpus found 144 spellings of that class, and
#         the 1.0.4 comment claiming last-occurrence "survives a commit
#         message that happens to contain the word" had it exactly backwards.
#
# So the line is split on its connectors and each segment is judged on its
# own, with the branch each segment RUNS ON tracked across the split. A merge
# counts only at COMMAND POSITION within its segment, which is what stops
# `echo git merge spec/0001-x` from being read as a merge. Any segment that
# denies denies the whole command.
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
    # A TRAILING SHELL COMMENT IS NOT ARGUMENTS (leg 5, F4 and F3).
    #
    # Bash discards everything from an unquoted `#` at a word start to the end
    # of the line. This gate read it as text, and two separate bypasses came out
    # of the same misreading:
    #
    #     git merge --no-ff spec/0001-thing # will --continue if it conflicts
    #
    # matched the resumption exemption and skipped EVERY close check, on a
    # comment the gate's own CG-UNLEXABLE message suggests writing. And
    #
    #     git checkout main # back to the trunk
    #
    # counted the comment's words as checkout operands, so the segment looked
    # like a multi-operand pathspec checkout and no branch switch was recorded.
    #
    # The `#` must begin a WORD. A `#` inside a word is an ordinary character
    # (`git merge --no-ff spec/0001-thing` is unaffected, and so is a ref
    # containing one), and a `#` inside quotes never reaches here because the
    # opaque-token pass has already dealt with the span.
    #
    # A comment containing a separator was already split by the segmenter, so
    # what remains here is at most the comment's head; its tail became its own
    # segment, which is not a git command and is ignored. That direction is
    # safe: it strips less, never more.
    seg="$(printf '%s' "$seg" | sed -E 's/(^|[[:space:]])#.*$//')"
    # A TRAILING REDIRECTION IS NOT AN OPERAND (leg 5, F3).
    #
    # The leading form was closed on 2026-07-28 because it hid the command word.
    # The trailing form hides nothing and does something worse: it is COUNTED.
    # `git checkout main >/dev/null` reads as a two-operand checkout, which this
    # gate classifies as a pathspec restore that switches nothing, so a later
    # merge is judged against whatever branch the shell was on before. Silencing
    # output is the most ordinary thing a caller does.
    seg="$(printf '%s' "$seg" | sed -E 's/[[:space:]]+[0-9]*(>>|>|<)[[:space:]]*(&[0-9@A-Za-z-]+|[^ ]+)[[:space:]]*$//')"
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
    # A FUNCTION DEFINITION also puts something other than the verb at the head
    # of a segment (F6 of the third leg):
    #
    #     function f { git merge --no-ff spec/0001-x; }; f
    #     f() { git merge --no-ff spec/0001-x; }; f
    #
    # The body runs when `f` is called, which is on the same command line, so
    # the governed command really does execute. Stripping the definition head
    # judges the body as though it were inline, which is the fail-closed reading:
    # the alternative is a gate that cannot follow the call and therefore does
    # not look.
    seg="$(printf '%s' "$seg" | sed -E 's/^function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\(\)[[:space:]]*)?//; s/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*//')"
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
    # A wrapper flag may take its value as a SEPARATE word, and 1.0.6 consumed
    # the flag alone: `nice -n 5 git merge ...` stripped `nice`, stripped `-n`,
    # and left `5` at the head of the segment, which then failed the
    # command-position test and was never judged at all. `stdbuf -o0` survived
    # only because its value is glued to the flag, which is the accident that
    # hid the class. So a flag is consumed together with one optional following
    # non-dash value.
    #
    # The command word is never eaten as a value, which is why this is three
    # branches and not one regex: `env -i git merge ...` has git sitting where
    # a value would be, and consuming it would delete the very token the
    # command-position test looks for. The loop runs to a fixed point, so
    # handling one flag per pass costs nothing.
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
# meant `echo hi & git merge --no-ff spec/0001-thing` collapsed to one segment
# whose command word was `echo`, so the merge was never judged at all. Both gates
# carry their own copy of this line, so this is fixed in both.
#
# `&&` must not become two separators. It does not: POSIX ERE alternation is
# leftmost-LONGEST and the two-character alternative is listed first. Asserted in
# the suite rather than trusted, in both directions.
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
# The separator is KEPT, because it says whether the previous segment SUCCEEDED
# (F7 of the 1.0.8 leg). Only `&&` implies success. Order matters: && before a
# single &, || before a single |.
SEGMENTS="$(printf '%s\n' "$CMD_NORM" | awk '{ gsub(/>&/, ">@@FD@@"); gsub(/<&/, "<@@FD@@"); gsub(/&&/, "\n@@AND@@ "); gsub(/\|\|/, "\n@@SEQ@@ "); gsub(/[;|()&]/, "\n@@SEQ@@ "); print }')"

CUR_BRANCH="$(git -C "$PROJ" branch --show-current 2>/dev/null || true)"
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

while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -e 's/^ *//' -e 's/ *$//')"
  [[ -n "$seg" ]] || continue

  # HOW WAS THIS SEGMENT REACHED? A checkout was modelled as unconditionally
  # taken, which is false for the commonest failure there is: a checkout aborts
  # whenever local changes would be overwritten, and after it aborts the shell
  # is STILL ON THE TRUNK. So
  #
  #     git checkout feat/x; git merge --no-ff spec/0001-thing
  #     git checkout feat/x || git merge --no-ff spec/0001-thing
  #
  # ran the merge on the trunk with every close check skipped, because the gate
  # believed it was standing on feat/x. Replayed with a dirty file that feat/x
  # also modifies: the checkout really does abort and the merge really does land.
  #
  # `&&` is the one separator that IMPLIES the previous command succeeded, so it
  # is the only one that may be trusted to have moved the branch. After any
  # other separator the branch is UNKNOWN, which is a sentinel this gate already
  # has and which makes a later merge fail closed rather than read as "some
  # other branch". `&&` is left exact rather than swept into the same bucket,
  # because denying `git checkout feat/x && git merge ...` would break an
  # ordinary workflow: if that checkout fails the merge never runs at all.
  SEP=""
  case "$seg" in
    "@@AND@@ "*) SEP=AND; seg="${seg#@@AND@@ }" ;;
    "@@SEQ@@ "*) SEP=SEQ; seg="${seg#@@SEQ@@ }" ;;
  esac
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

  # A checkout or switch changes the branch every LATER segment runs on. This
  # is how the compound close (`git checkout main && git merge --no-ff
  # spec/X`) is still recognised, without letting the checkout donate its
  # argument to the merge.
  if printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +(checkout|switch) +"; then
    # `-` and `@{-1}` mean "the branch I was on before", and they are ORGANIC:
    # after `git checkout spec/NNNN` from the trunk, `git checkout -` is how a
    # person and an agent both go back. The first cut of this took the first
    # NON-DASH argument, so `-` was skipped entirely, the running branch stayed
    # on the spec branch, and the following merge was judged as targeting a
    # feature branch, which is an explicitly ALLOWED case. That is not a
    # fall-through; it is the gate reaching a confident wrong answer.
    #
    # This hook runs BEFORE the command, so `@{-1}` still resolves to the
    # pre-command previous branch, which is exactly what `-` is about to
    # become. Resolve it. If it cannot be resolved the running branch is
    # unknown, and an unknown branch must not read as "not the trunk": the
    # sentinel below makes any later merge segment fail closed instead.
    # `git checkout` is TWO commands wearing one name. With a branch it
    # switches; with a pathspec it discards working-tree changes and switches
    # nothing, which is something agents do constantly right before merging.
    # 1.0.6 recorded the argument as a branch either way, so `git checkout -- .
    # && git merge --no-ff spec/0001-x` decided the merge would run on a branch
    # called "." and skipped it as not-the-trunk. That is the same class as the
    # `checkout -` defect it had just fixed: an argument that is not a branch
    # name recorded as one, producing a CONFIDENT WRONG ANSWER rather than a
    # fall-through. `git restore` was never affected because it does not touch
    # this tracker, and `git switch` needs none of it because switch only ever
    # takes a branch.
    #
    # So the argument is CLASSIFIED, and the classification has a disposition
    # for every outcome including "cannot tell":
    IS_SWITCH=0
    printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +switch +" && IS_SWITCH=1

    # Everything after a bare `--` is pathspec by definition, never a branch.
    SEG_HEAD="$seg"
    HAS_PATHSPEC_SEP=0
    if [[ "$IS_SWITCH" -eq 0 ]]; then
      case "$seg" in
        *" -- "*) SEG_HEAD="${seg%% -- *}"; HAS_PATHSPEC_SEP=1 ;;
        # A BARE TRAILING `--` IS NOT THE PATHSPEC FORM (leg 5, F2). With
        # nothing after the separator there is no pathspec, and git falls back
        # to the branch form: `git checkout main --` prints "Switched to branch
        # main" and HEAD really moves. Treating it as a restore recorded no
        # switch, so a merge compounded after it was judged against the branch
        # the shell was on before, which is the confident wrong answer this
        # whole block exists to stop producing.
        #
        # The separator settles the form only when it SEPARATES something. This
        # is the fifth spelling of that class, and it is the one the previous
        # four fixes created by testing the punctuation rather than what the
        # punctuation does.
        *" --")   : ;;
      esac
    fi

    # `git checkout [<tree-ish>] -- <pathspec>` RESTORES FILES AND SWITCHES
    # NOTHING. git's own synopsis separates the two forms on exactly this
    # punctuation, and the presence of the separator settles it: whatever sits
    # before the `--` is a source to read blobs OUT of, not a branch to stand on.
    #
    # 1.0.7 handled only the case where nothing preceded the separator
    # (`git checkout -- .`), by finding no branch candidate and falling through.
    # With a tree-ish in front, a candidate WAS found and it was a real branch,
    # so the tracker recorded a switch that never happens:
    #
    #     git checkout spec/0002-other -- src/a.txt && git merge --no-ff spec/0001-thing
    #
    # The merge was then judged against spec/0002-other, read as ordinary
    # feature work, and skipped. Same class as `checkout -` and `checkout -- .`
    # before it: an argument that is not a branch to stand on recorded as one,
    # which produces a CONFIDENT WRONG ANSWER rather than a fall-through. This
    # is the third time that class has been closed one spelling at a time, so
    # the test is now the SEPARATOR rather than the shape of what surrounds it.
    #
    # MIND THE OTHER `--`. strip_wrappers removes a bare `--` at the HEAD of a
    # segment, where it is an option terminator (`env -- git merge`), and that
    # already ran above. The two positions never collide: the head strip is
    # anchored at position 0 and every separator here follows the checkout verb.
    if [[ "$HAS_PATHSPEC_SEP" -eq 1 ]]; then
      continue
    fi

    # `-b`, `-B` and `--orphan` NAME a branch that is about to exist, so the
    # word after them is a branch by construction and no lookup can confirm it
    # (it does not exist yet). Without this, creating a branch would land in
    # the unresolvable case below and fail closed on ordinary work.
    NEWB="$(printf '%s' "$SEG_HEAD" | awk '{
      for (i = 1; i < NF; i++)
        if ($i == "-b" || $i == "-B" || $i == "--orphan") { print $(i + 1); exit }
    }')"

    # TWO OR MORE OPERANDS IS A PATHSPEC CHECKOUT, separator or not (F7 of the
    # third leg, and the FOURTH spelling of this same class). The block above
    # ends by saying "the test is now the SEPARATOR rather than the shape of
    # what surrounds it", and git does not require the separator:
    #
    #     git checkout spec/0002-other src/a.txt
    #
    # restores one file and switches NOTHING, but the tracker read the first
    # operand as a branch and recorded a switch that never happened. A later
    # merge was then judged against the wrong branch, which is the confident
    # wrong answer this class keeps producing.
    #
    # `git checkout <branch>` takes exactly ONE operand. More than one means git
    # is reading blobs out of the first and writing paths named by the rest, so
    # no switch occurs. Counting operands settles it without asking what any of
    # them looks like, which is the mistake the previous three repairs made.
    #
    # -b/-B/--orphan are handled above and return before this, so a creating
    # checkout with a start point is not miscounted.
    SEG_OPERANDS="$(printf '%s' "$SEG_HEAD" | awk '{
      f = 0; n = 0
      for (i = 1; i <= NF; i++) {
        if (f && ($i == "-" || $i !~ /^-/)) n++
        if ($i == "checkout" || $i == "switch") f = 1
      }
      print n
    }')"
    if [[ "${SEG_OPERANDS:-0}" -gt 1 ]]; then
      # fail-open-ok: not a branch switch at all, so the branch this gate is
      # standing on is unchanged and any later merge is still judged against it.
      # Recording no switch is the FAIL-CLOSED direction here: it leaves
      # CUR_BRANCH as the trunk rather than moving it somewhere unguarded.
      continue
    fi

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
          # `-` and `@{-1}` mean "the branch I was on before", and they are
          # ORGANIC: after `git checkout spec/NNNN` from the trunk, this is how
          # a person and an agent both go back. This hook runs BEFORE the
          # command, so `@{-1}` still resolves to the pre-command previous
          # branch, which is exactly what `-` is about to become.
          NEWB="$(git -C "$PROJ" rev-parse --abbrev-ref '@{-1}' 2>/dev/null || true)" # fail-open-ok: an unresolvable previous branch is converted to the UNKNOWN sentinel on the next line, which makes any later merge fail closed rather than read as "some other branch"
          [[ -n "$NEWB" ]] || NEWB="$UNKNOWN_BRANCH"
          ;;
        *)
          if [[ "$IS_SWITCH" -eq 0 ]]; then
            if git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$NEWB" >/dev/null 2>&1; then
              : # a real local branch: the switch is real, record it
            elif [[ -e "$PROJ/$NEWB" || -e "$NEWB" ]]; then
              # An existing path and not a branch: this discards changes and
              # switches nothing. `.` lands here, and so does any file or
              # directory an agent names.
              continue
            else
              # Neither a branch nor a path. The gate cannot establish which
              # branch a later segment would run on, and an unknown branch must
              # never read as "not the trunk": the sentinel makes the merge
              # fail closed.
              NEWB="$UNKNOWN_BRANCH"
            fi
          else
            # `git switch` ONLY EVER TAKES A BRANCH, and that was read as
            # meaning its operand needs no checking (leg 5, F10). It does. The
            # operand still has to NAME a branch this gate can find, and
            #
            #     TRUNK=main; git switch $TRUNK && git merge --no-ff spec/0001-x
            #
            # recorded the literal text `$TRUNK` as the branch. That is not the
            # trunk by string comparison, so the merge read as ordinary feature
            # work and every close check was skipped. The equivalent checkout
            # spelling denies, and `git switch main` denies, so this was the one
            # unguarded corner of a family the gate otherwise handles.
            #
            # An operand that names no branch here becomes the sentinel, exactly
            # as it does for checkout: a switch this gate cannot follow must
            # make the next merge fail closed rather than move the tracked
            # branch somewhere unguarded. `-b`/`-c` creation is handled above
            # and returns before this.
            if ! git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$NEWB" >/dev/null 2>&1; then
              NEWB="$UNKNOWN_BRANCH"
            fi
          fi
          ;;
      esac
    fi
    # Held, not applied. The next segment's separator decides whether this
    # checkout may be believed; see the loop head.
    [[ -n "$NEWB" ]] && PENDING_BRANCH="$NEWB"
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

  # AN OPTION'S VALUE IS NOT AN OPTION, AND NOT A REF (F4/F5 of the second
  # 1.0.8 leg). Every word after `merge` was scanned as both, so the VALUE of
  # -m was read as though the user had typed it as a flag:
  #
  #     git merge --no-ff spec/0002-other -m "--continue"
  #
  # matched the resumption exemption below and skipped every close check, and
  # `-m --abort` did the same. In the other direction a message word could
  # resolve as a ref and make the gate validate a different branch from the one
  # being merged, which is the wrong-object class the ref rewrite exists to end.
  #
  # The value-taking options are dropped with their values before either test.
  # `-S`/`--gpg-sign` is deliberately NOT in the list: git takes its key id
  # ATTACHED, so a separate word after it is a ref, and skipping it would drop a
  # real merge target. Erring toward scanning an extra word is the fail-closed
  # direction here.
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

  # WHICH BRANCH IS BEING MERGED, asked of git rather than of the string.
  #
  # This used to strip three literal prefixes (refs/heads/, refs/remotes/,
  # origin/) and then test the remainder for spec/ or chore/. Every other way of
  # naming the same commit therefore read as an ungoverned sync merge and was
  # allowed with every close check skipped: `heads/spec/0001-thing`,
  # `remotes/origin/spec/0001-thing`, `upstream/spec/0001-thing`, a TAG pointing
  # at the branch tip, a raw object name. That is F8, and the prefix list could
  # never have been finished, because git accepts an open-ended set of spellings
  # for one commit and a hand-maintained list of three is a guess about which
  # three people use.
  #
  # Worse, and this is F3: for `origin/spec/0001-thing` the strip produced
  # `spec/0001-thing`, and every content check below then read the LOCAL branch
  # of that name while git merged the REMOTE-TRACKING one. A compliant local
  # branch green-lit a non-compliant remote. The thing validated was not the
  # thing merged, which is the class this whole gate exists to prevent, sitting
  # inside the gate.
  #
  # Both die the same way: resolve the word to a COMMIT, then ask git which refs
  # point at that commit. Identity by object, not by name. A spelling nobody has
  # thought of yet resolves to the same commit as one everybody knows, so this
  # does not need extending when someone invents a fourth prefix.
  #
  # The matched FULL ref name is what is carried forward, not a short name, so
  # the content checks read the bytes git is about to merge. That is the half
  # that fixes F3.
  SEG_REF=""
  SEG_REFS=""
  SEG_LOOKS_SPEC=""
  # EVERY operand gets a disposition, not just the ones that resolve (leg 4, F3).
  # These two carry the operands that could NOT be dispositioned, so the check
  # after the loop can refuse on them even when a sibling operand resolved
  # cleanly. Collecting them is the whole fix; see the comment at the loop's end.
  SEG_INDIRECT=""
  SEG_UNRESOLVED=""
  for word in $MARGS; do
    # The INDIRECT forms are excluded from resolution on purpose, and the reason
    # is timing rather than tidiness. This hook runs BEFORE the command, so a
    # spelling whose meaning depends on repository state resolves here to
    # something the merge may not use: in `git checkout X && git merge @{-1}`,
    # `@{-1}` at hook time is the branch before the checkout and at merge time
    # is the branch before THAT. Resolving it would let the gate validate one
    # branch while git merges another, which is the exact failure (F3) this
    # rewrite exists to close, reintroduced from the other end.
    #
    # Left unresolved they fall through to the UNNAMEABLE path below and deny,
    # which is the honest answer: the gate cannot establish what will be merged.
    #
    # An OPTION is not an operand, and the two must not share a branch here.
    # `--no-ff` and `-` both begin with a dash and mean opposite things: one is a
    # flag this gate has no opinion about, the other is the previous-branch
    # shorthand, which is a merge target whose meaning depends on state this hook
    # cannot see. Lumping them together is why `-` used to be silently skipped
    # rather than refused when another operand resolved.
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
    # A word that LOOKS like a spec or chore branch but does not resolve is
    # remembered, and it is what stops resolution-by-commit from being a
    # relaxation. v1.0.6 classified by NAME, so an unresolvable
    # `origin/spec/0001-x` was still governed and denied. Resolving by commit
    # alone would let it fall through to the sync-merge path and be ALLOWED,
    # which the strictness diff caught against 18 spellings: a gate that cannot
    # find the branch must refuse, never shrug.
    #
    # SEG_LOOKS_SPEC is set for a word that looks spec-shaped whether or not it
    # resolves, so it cannot answer "was anything left unresolved". That is what
    # SEG_UNRESOLVED is for, and conflating the two is how the disposition below
    # was written short.
    WORD_LOOKS_SPEC=""
    case "${word#refs/}" in
      spec/*|chore/*|*/spec/*|*/chore/*) SEG_LOOKS_SPEC="$word"; WORD_LOOKS_SPEC="$word" ;;
    esac
    SEG_SHA="$(git -C "$PROJ" rev-parse --verify --quiet "${word}^{commit}" 2>/dev/null)" # fail-open-ok: a word that names no commit is not a merge target, and the emptiness test below is what acts on it
    if [[ -z "$SEG_SHA" ]]; then
      [[ -n "$WORD_LOOKS_SPEC" ]] && SEG_UNRESOLVED="$SEG_UNRESOLVED $WORD_LOOKS_SPEC"
      continue
    fi
    # Already an ancestor of the trunk means merging it lands NOTHING NEW, so
    # there is nothing for a close gate to govern. Without this, a spec branch
    # that was merged an hour ago and a trunk ref that happens to point at the
    # same commit both read as an unclosed merge, and the gate would deny
    # ordinary no-op syncs. Harm is unreviewed work ARRIVING; a merge that
    # brings nothing cannot do it.
    if git -C "$PROJ" merge-base --is-ancestor "$SEG_SHA" "$TRUNK" 2>/dev/null; then
      continue
    fi
    # WHICH ref at this commit is the merge being judged?
    #
    # 1.0.8 shipped `... | head -n1` here and it was a release-blocking
    # regression. for-each-ref emits refname-sorted output, so with two refs on
    # one commit `refs/heads/chore/cleanup` sorts before `refs/heads/spec/0001`
    # and won. SPEC_BRANCH then read as a chore branch and the `== spec/*`
    # guard below skipped the ENTIRE close block: no Closing report, no QA
    # verdict, no diagram, no STATUS row, no authorship check. One ordinary
    # `git branch chore/wip` while standing on a spec branch reversed the
    # gate's verdict on a command that never mentioned the chore branch.
    #
    # It did not merely fail to close the alias hole, it INVERTED it: 1.0.7
    # classified by NAME, so the canonical spelling stayed governed no matter
    # what else pointed at the commit.
    #
    # Two rules replace the lexical accident.
    #
    # A spec ref WINS over a chore ref. Governing is the stricter reading, and
    # a commit that is both is a spec close being done under a chore alias.
    #
    # Ambiguity between DIFFERENT SPECS refuses rather than picks. Distinctness
    # is by spec NUMBER, not by ref count, because a local branch, its
    # remote-tracking copy and a tag are three refs for one spec and denying
    # those would break every ordinary close. Two different NUMBERS on one
    # commit is a question this gate cannot answer (whose Closing report is it
    # judging?), and the rest of this gate already refuses such questions
    # rather than guessing.
    SEG_ALL="$(git -C "$PROJ" for-each-ref --points-at "$SEG_SHA" --format='%(refname)' refs/heads refs/remotes 2>/dev/null \
                | grep -E '/(spec|chore)/')" # fail-open-ok: no spec or chore ref at this commit means the merge is a sync or an integration merge, which this gate has never governed; the emptiness is the classification
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
    # EVERY operand is collected, not just the first (F2/F6 of the second 1.0.8
    # leg). This used to `break` on the first word that resolved to a spec or
    # chore ref, so `git merge --no-ff spec/0003-good spec/0004-bad` contributed
    # exactly ONE ref and every later operand was never looked at: the compliant
    # branch was judged, the unclosed one landed on the trunk with every close
    # check skipped. An octopus merge is one command that merges several
    # branches, and the gate answers for all of them, exactly as it does for
    # several commits in one line.
    #
    # The comment further down already promised this ("Every collected ref is
    # checked; the first failure denies the whole command"). The collection is
    # what was short, not the checking.
    if [[ -n "$SEG_REF" ]]; then
      case " $SEG_REFS " in
        *" $SEG_REF "*) ;;
        *) SEG_REFS="$SEG_REFS $SEG_REF" ;;
      esac
      SEG_REF=""
    fi
  done
  SEG_REF="${SEG_REFS# }"

  # DISPOSITION EVERY OPERAND BEFORE LEAVING THE SEGMENT (leg 4, F3).
  #
  # The second 1.0.8 leg fixed the COLLECTION: the loop above stopped `break`ing
  # on the first operand that resolved, so an octopus merge contributed every
  # ref rather than one. The DISPOSITION stayed short-circuited, and that is a
  # different half of the same sentence. One resolvable operand reached the
  # `continue` below and every operand beside it was never classified at all:
  #
  #     git merge --no-ff FETCH_HEAD                  -> DENY, correctly
  #     git merge --no-ff spec/0003-good FETCH_HEAD   -> ALLOWED, and it lands
  #
  # A fully compliant spec branch vouched for an operand nobody had looked at,
  # and unreviewed work reached the trunk by the octopus strategy with every
  # close check skipped. The cheapest form used a chore branch as the resolvable
  # operand, because chore branches need no artifacts at all. The trunk audit did
  # not catch it either: it bucketed the smuggled parent as a chore merge and
  # reported "0 violations".
  #
  # So the refusal comes FIRST, before the resolvable refs are accepted. An
  # operand this gate cannot verify is not made verifiable by a sibling that can
  # be: a merge is one command and the gate answers for all of it, which is the
  # rule the octopus fix already stated and applied to only one half.
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

  # A ref that is NAMED but is not a spec or chore branch is a sync or an
  # integration merge, which this gate has never governed. 1.0.3 denied those
  # too, breaking `git merge origin/main` while `git pull` did the same thing
  # ungated: friction with no safety. A ref counts as named when it RESOLVES
  # here and is not a form whose target cannot be read off the command line.
  # Requiring resolution is what stops the words of
  # `git merge -m "closing spec" $B` from posing as a branch name.
  NAMED_REF=""
  for word in $MARGS; do
    case "$word" in
      -*|*'$'*|*'`'*|@*|'') continue ;;
      HEAD|FETCH_HEAD|ORIG_HEAD|MERGE_HEAD|CHERRY_PICK_HEAD|REVERT_HEAD) continue ;;
    esac
    printf '%s' "$word" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._/-]*$' || continue
    # A raw object name identifies the commit without NAMING the branch, and
    # the close conditions live in a branch's spec file, so there is nothing to
    # check: it belongs with the other indirect forms. 1.0.6 recognised one by
    # its SHAPE, `[0-9a-f]{7,40}`, and every spelling outside that shape walked
    # through instead: a 6-character abbreviation, the same oid uppercased, and
    # in a sha256 repository the 64-character oid. Shape was the wrong
    # question, and the right one is free of it: ask git whether the word NAMES
    # anything. A ref has a symbolic full name; an object name does not, at any
    # length or case. This also stops a branch that happens to be spelled in
    # hex from being mistaken for an oid, which the shape test got wrong in the
    # other direction.
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
  deny "close gate [CG-UNRESOLVED-SWITCH]: this command switches branches by a shorthand this gate cannot resolve (git checkout - or @{-1} with no previous branch recorded), so it cannot establish which branch [$UNRESOLVED_TARGET] would run on, and cannot tell whether it merges into the trunk. Name the branch you are switching to."
fi

# Two different specs on one commit. The gate cannot establish whose close it
# is judging, and picking one would validate one spec's artifacts for a merge
# of another, which is the "the thing checked is not the thing merged" class
# this whole ref-identity rewrite exists to end.
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

  # MERGED_REF is now a FULL ref name (refs/heads/spec/... or
  # refs/remotes/<remote>/spec/...), because reading content off the exact ref
  # git will merge is what stops a compliant local branch from vouching for a
  # non-compliant remote one. The BRANCH NAME is still what carries the spec
  # number, so it is derived here rather than assumed to be the same string.
  # Taking everything from `spec/` or `chore/` onward handles both namespaces
  # and any remote name, including one containing a slash.
  case "$MERGED_REF" in
    */spec/*)  SPEC_BRANCH="spec/${MERGED_REF#*/spec/}" ;;
    */chore/*) SPEC_BRANCH="chore/${MERGED_REF#*/chore/}" ;;
    *)         SPEC_BRANCH="$MERGED_REF" ;;
  esac

  # Chore branches (chore/<slug>, unnumbered per Part 5b) have no spec file or
  # inventory row to verify; for them only the gate command below applies.
  if [[ "$SPEC_BRANCH" == spec/* ]]; then
    # Derive the spec file from the branch NUMBER (Part 6: spec/NNNN-<slug>
    # builds specs/NNNN-*.md), looked up in the merged ref's tree. The slug may
    # legitimately differ between branch and file; the number may not. Fail
    # closed on zero or multiple matches.
    SPEC_NUM="${SPEC_BRANCH#spec/}"
    SPEC_NUM="${SPEC_NUM%%-*}"
    SPEC_PATHS="$(git -C "$PROJ" ls-tree -r --name-only "$MERGED_REF" -- specs/ 2>/dev/null | grep -E "^specs/${SPEC_NUM}-[^/]*\.md$" || true)"
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

    # THE BRANCH MUST HAVE WRITTEN ITS OWN SPEC (1.0.7, B4). Every check below
    # reads the spec file as it stands on the branch, which is right, but says
    # nothing about who put it there. A branch cut from the trunk AFTER spec
    # NNNN was closed inherits that spec, Closing report and all, so reusing a
    # CLOSED number as a branch name carries unreviewed work onto the trunk
    # against artifacts somebody else wrote:
    #
    #     spec/0001-thing closes legitimately and merges
    #     spec/0001-sneaky is cut from the trunk, changes code, adds no spec
    #     git merge --no-ff spec/0001-sneaky  <- every check passes, on 0001-thing's report
    #
    # The trunk audit then reports the merge as compliant, because it is reading
    # the same inherited artifacts.
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

    # A FENCED EXAMPLE IS NOT A CLOSING REPORT (leg 5, F7).
    #
    # Every check below reads SPEC_TEXT as one flat string, so a spec that
    # QUOTES the Appendix C template inside a ```markdown fence satisfied all
    # four of them at once: the section heading, the QA verdict, the diagram
    # field and, with the row, the whole close. A spec with no Closing report at
    # all merged clean.
    #
    # That is not a contrived input. The template ships in setlist.md as a
    # fenced block containing exactly these markers, it is stamped to
    # specs/TEMPLATE.md, and the spec-authoring skill tells authors to copy it.
    # A spec that quotes its own template is ordinary authoring, which makes
    # this the most reachable hole the leg found.
    #
    # Fenced content is stripped ONCE here rather than in each check, so the
    # four cannot drift apart the way the report checker's three readers did.
    SPEC_TEXT="$(printf '%s\n' "$SPEC_TEXT" | awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      !fence
    ')"

    # The Closing report section exists (Appendix C: "## Closing report ...").
    if ! printf '%s\n' "$SPEC_TEXT" | grep -qE '^#+[[:space:]]*Closing report'; then
      deny "close gate [CG-NO-CLOSING-REPORT]: the spec file for $MERGED_REF has no Closing report section on the branch; complete it, commit it to the branch, then merge."
    fi

    # The pasted QA Pass 1 block: between the "QA Pass 1 report" field and the
    # "QA Pass 2" field there must be at least one PASS / PARTIAL / FAIL verdict.
    # Both boundaries anchor on the Appendix C FIELD MARKER (start of line, past
    # any list bullet or bold markers), never on a bare substring anywhere in the
    # line. The bare "QA Pass 2" test ended the block at the first sentence of
    # QA-1 prose that merely cross-referenced QA Pass 2, truncating the verdict
    # out of the block and denying a compliant merge in the field.
    QA_BLOCK="$(printf '%s\n' "$SPEC_TEXT" | awk '
      /^[-*+[:space:]]*QA Pass 1 report/ { inqa = 1 }
      /^[-*+[:space:]]*QA Pass 2/        { inqa = 0 }
      inqa')"
    # A VERDICT SITS AT THE END OF ITS LINE (F5 of the third leg). This matched
    # PASS, PARTIAL or FAIL ANYWHERE in the QA block, so ordinary prose satisfied
    # it: "the browser tests PASS on my machine but I could not run the mobile
    # ones" is not a pasted verdict, and neither is a sentence explaining why a
    # criterion could not be judged.
    #
    # Appendix C's shape is `criterion N: VERDICT`, one per line, so the verdict
    # ends its line. Requiring that is narrow enough to reject prose and wide
    # enough for every real shape: a bare `PASS`, `- criterion 2: FAIL.`, and a
    # trailing parenthesis all still pass. The false-denial direction is the
    # dangerous one here, which is why this is anchored at the END rather than
    # tightened into a full line format nobody actually writes.
    if ! printf '%s\n' "$QA_BLOCK" | grep -qE '(^|[^A-Za-z])(PASS|PARTIAL|FAIL)[[:space:]]*[.);:]?[[:space:]]*$'; then
      deny "close gate [CG-NO-QA-VERDICT]: the Closing report for $MERGED_REF carries no pasted QA Pass 1 PASS/PARTIAL/FAIL block; run QA Pass 1, paste the report, commit it to the branch, then merge."
    fi

    # The architecture-diagram field (Appendix C, exact label "Architecture
    # diagram:") is answered: "updated in this commit" or "no impact", never the
    # template placeholder (which still carries angle brackets).
    DIAG_LINE="$(printf '%s\n' "$SPEC_TEXT" | grep -E 'Architecture diagram:' | tail -n1)"
    if [[ -z "$DIAG_LINE" ]]; then
      deny "close gate [CG-NO-DIAGRAM-FIELD]: the Closing report for $MERGED_REF is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    fi
    DIAG_ANSWER="${DIAG_LINE#*Architecture diagram:}"
    if [[ "$DIAG_ANSWER" == *"<"* ]] || ! printf '%s' "$DIAG_ANSWER" | grep -qE 'updated in this commit|no impact'; then
      deny "close gate [CG-DIAGRAM-UNANSWERED]: the architecture-diagram field for $MERGED_REF is unanswered; answer it 'updated in this commit' or 'no impact', commit to the branch, then merge."
    fi

    # STATUS.md carries the spec's inventory row, updated to CLOSED, on the
    # branch (Part 6: the row rides the same commit as the Closing report; the
    # merge is what brings it to the trunk). Row format from the stamped
    # STATUS.md: | NNNN | Title | Status | note |.
    #
    # THE STATUS IS A CELL, NOT A WORD IN THE ROW (leg 5, F8). This grepped the
    # WHOLE row for CLOSED, so an ACTIVE spec whose free-text note column
    # happened to mention another spec's closure satisfied it:
    #
    #     | 0001 | Thing | ACTIVE | follows on from 0000 which is CLOSED |
    #
    # A note that references another spec is ordinary prose, not an attack, and
    # it blinded the gate on the one field that says whether the work is done.
    # The row has a shape, so the shape is read: field 4 of the pipe-delimited
    # row is the status, and it must BE closed rather than contain the word.
    STATUS_TEXT="$(git -C "$PROJ" show "${MERGED_REF}:specs/STATUS.md" 2>/dev/null || true)"
    if ! printf '%s\n' "$STATUS_TEXT" | awk -F'|' -v num="$SPEC_NUM" '
      function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
      NF >= 5 && trim($2) == num && trim($4) == "CLOSED" { found = 1 }
      END { exit found ? 0 : 1 }
    '; then
      deny "close gate [CG-NO-STATUS-ROW]: specs/STATUS.md on branch $MERGED_REF has no inventory row marking spec $SPEC_NUM CLOSED; update the row in the same commit as the Closing report, then merge."
    fi
  fi
done

# The gate command (the full test suite) must exit 0, run fresh. /scaffold
# records it in sdd.json when it flips the scaffolded flag; before that flip
# (bootstrap-era, docs-only merges) there is nothing to run yet.
SCAFFOLDED="$(jq -r '.scaffolded // false' "$SDD_JSON" 2>/dev/null)"
GATE_CMD="$(jq -r '.gate_command // empty' "$SDD_JSON" 2>/dev/null)"
if [[ "$SCAFFOLDED" == "true" && -z "$GATE_CMD" ]]; then
  deny "close gate [CG-NO-GATE-COMMAND]: .claude/sdd.json is scaffolded but carries no gate_command; record the full-suite command there before merging."
fi
if [[ -n "$GATE_CMD" ]]; then
  if ! (cd "$PROJ" && bash -c "$GATE_CMD" >/dev/null 2>&1); then
    deny "close gate [CG-GATE-COMMAND-RED]: the gate command ($GATE_CMD) failed on a fresh run; gates must be green before merging."
  fi
fi

# fail-open-ok: every close condition above was checked against the merged
# ref's committed tree and held; this is the gate's green path.
exit 0
