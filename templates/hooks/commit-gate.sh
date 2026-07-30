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
if [[ "$JQ_STATE" != "ok" ]]; then
  case "$INPUT" in
    *commit*)
      if [[ "$JQ_STATE" == "absent" ]]; then
        deny_literal "commit gate [CM-NO-JQ]: jq is not installed, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Install jq (apt-get install jq, brew install jq, or the package manager for this system), then retry. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
      fi
      deny_literal "commit gate [CM-JQ-BROKEN]: jq is installed but does not run on this machine, so this gate cannot read the command it is meant to check and would otherwise allow every commit unchecked. Run jq --version to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
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
      deny_literal "commit gate [CM-JQ-UNPARSED]: jq could not parse the payload this hook was given, so the command being run cannot be read and this gate cannot check what it stages. Gates fail closed by design; removing this hook entry from .claude/settings.json is the deliberate way to work without it."
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
CMD_NORM="$(printf '%s' "$CMD" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | tr '\n\r' ';;' | tr -s '[:space:]' ' ')"
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
}\')"
GIT_OPTS='( +-{1,2}[A-Za-z][^ ]*( +[^- ][^ ]*)?)*'

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
SEGMENTS="$(printf '%s\n' "$CMD_BARE" | awk '{ gsub(/>&/, ">@@FD@@"); gsub(/<&/, "<@@FD@@"); gsub(/&&|\|\||[;|()&]/, "\n"); print }')"
HAS_COMMIT=""
HAS_STAGE=""
while IFS= read -r seg; do
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
  elif printf '%s' "$seg" | grep -qE "^([^ ]*/)?git${GIT_OPTS} +($INDEX_VERBS)( |$)"; then
    HAS_STAGE="$seg"
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
if printf '%s' "$HAS_COMMIT" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[ai][a-zA-Z]*([[:space:]]|$)|--all([[:space:]]|$)|--include([[:space:]]|$)|--interactive([[:space:]]|$)'; then
  deny "commit gate [CM-AUTOSTAGE-FLAG]: git commit with -a, -i, --all, or --include stages at commit time, so the gate would scan an empty index and check nothing. Stage the exact files with git add first, then run git commit without auto-staging flags."
fi

# Staged additions only: lines the commit would introduce.
ADDED="$(git -C "$PROJ" diff --cached --unified=0 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"

# Check 1: em-dash scan on staged new content. The character is built from an
# escape so this script never contains it literally (repo rule 1 applies to the
# instances too).
EMDASH="$(printf '\342\200\224')"
if printf '%s\n' "$ADDED" | grep -q "$EMDASH"; then
  deny "commit gate [CM-EMDASH]: staged new content contains an em-dash; replace it with a comma, colon, parentheses, or separate sentences, then retry."
fi

# Check 2: secret scan. Token-shaped, connection-string-shaped, password-shaped.
# STUB NOTE: the pattern set is a first cut; tune it as dogfood and field runs
# surface false positives or misses.
if printf '%s\n' "$ADDED" | grep -qiE '(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'; then
  deny "commit gate [CM-SECRET]: staged content contains a secret-shaped string; move the value to the environment, reference it, and stage .env.example instead."
fi

# Check 3: STATUS-in-same-commit. A staged spec lifecycle transition (Status
# line change or a Closing report section added) requires specs/STATUS.md in
# the same commit. Ordinary mid-build spec edits do not trip it. The formats
# bound here are Appendix C exactly: the header line "Status: QUEUED" (bare
# label, one lifecycle state) and the "## Closing report" heading.
SPEC_ADDED="$(git -C "$PROJ" diff --cached --unified=0 -- 'specs/*.md' ':(exclude)specs/STATUS.md' ':(exclude)specs/TEMPLATE.md' 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' || true)"
if printf '%s\n' "$SPEC_ADDED" | grep -qE '^\+Status:[[:space:]]*(QUEUED|ACTIVE|REVISED|CLOSED|DRAFT)|^\+#+[[:space:]]*Closing report'; then
  if ! git -C "$PROJ" diff --cached --name-only | grep -qx 'specs/STATUS.md'; then
    deny "commit gate [CM-STATUS-MISSING]: this commit changes a spec lifecycle state but does not stage specs/STATUS.md; update the STATUS.md inventory line in the same commit."
  fi
fi

# fail-open-ok: every check above ran against the staged content and found
# nothing to deny; this is the gate's green path.
exit 0
