#!/usr/bin/env bash
# SETLIST BYPASS DENY: PreToolUse on matcher "Bash", stamped into the instance
# (the 2.8.0 cycle, spec 0143; its design is spec 0142 section 1, option A,
# ruled by the owner 2026-09-13).
#
# ONE QUESTION: does this command disarm the git hooks for its own run? A
# command that spells a bypass of the git-hook boundary (an assignment of
# SETLIST_SKIP_HOOKS=1 or SETLIST_SKIP_TRUNK_AUDIT=1 at assignment position,
# --no-verify or a spelling git reads as it in a git command, or
# -c core.hooksPath in a git command) is denied with permissionDecision "deny".
# Every other command draws no output at all.
#
# WHY A HOOK OF ITS OWN. The two Bash advisory gates leave in 2.8.0 (ER8): they
# are parsers whose verdicts the model is measured not to see (RP5). This rule
# is the exception, because a DENY reason is delivered and read, which the
# advisory probe's own control has shown on every run. It moved out of the
# commit gate so it survives that deletion, and to a NEW path so an upgraded
# instance's settings entry for the old gate can never silently start to mean
# something else (spec 0142, ruling 2).
#
# WHAT MAKES IT MINIMAL, three checks a later reader can run (spec 0143):
#   1. one question: no git invocation, and no read of the instance's config,
#      its status record, a spec or a ref
#   2. one verdict shape: a deny, or nothing and exit 0; no advisory path, and
#      the only codes are CM-BYPASS-SPELLED and CM-HOOKSPATH-MOVED
#   3. one reader, bounded and pinned: BYPASS_LEX_AWK moved verbatim, and the
#      suite pins its SHA-256, so a new spelling breaks the pin and becomes a
#      visible decision rather than a drift (PD1's freeze, made mechanical on the
#      one parser that survives it). Changed once since, by decision: the owner's
#      ruling of 2026-09-16 fixed the 2.8.0 leg's confirmed false denials inside
#      it (spec 0147, fix round 1), and the pin moved with that edit.
# The suite asserts all three, in region bypass-deny-0143.
#
# THE LEXER'S TWO MEASURED RULES are why this is a lexer rather than a substring
# test: the assignment-position test (a commit message merely quoting the escape
# was denied) and the value-operand test (git log --grep "--no-verify" was
# denied). Both were false denials a leg measured on shipped bytes; the rulings
# behind them are in the framework source's private hook-rulings record, under
# the commit gate's region. Spec 0147 added three for the 2.8.0 leg's confirmed
# false denials: a bare -- after the subcommand ends option reading, the log and
# grep family's value-taking short options, and a heredoc body read by cat, tee
# or git is data. Each keeps the deny it had wherever it does not apply.
#
# NO TOOLCHAIN CODE (spec 0143, decision 1). Without a working jq or awk this
# hook cannot read the command, and a deny it cannot attribute to a command
# would deny every Bash call, the one that repairs the tool included. So it
# says nothing. That is a gap, not a fallback: the spellings this rule governs
# are exactly the ones that disarm the git hooks, so on a degraded toolchain the
# rule is simply absent (the 2.8.0 leg's F2, corrected by spec 0147).
#
# UNTIL SPEC 0144 the commit gate carried this same rule, so a disarming
# command drew two denials carrying the same code. That state was spec 0142's
# recorded decision, and it ended when the commit gate was deleted in 2.8.0.
#
# Disable with a one-line edit: remove this hook's entry from
# .claude/settings.json.

set -u

# The code in a deny reason is its LAST bracketed token of the form
# [A-Z][A-Z0-9-]*, extracted by parameter expansion rather than sed (KL11).

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

# The payload is read by the shell, not by cat.
IFS= read -r -d '' INPUT || true
if [[ -z "$INPUT" ]]; then
  # fail-open-ok: no payload means no command to read, and this hook has no
  # question to ask of an empty one (decision 1).
  exit 0
fi
if [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  # fail-open-ok: jq is absent or broken (the probe compares OUTPUT, so a jq
  # that exits 0 printing nothing is broken too); without it the command cannot
  # be read and a deny could not be attributed to it (decision 1).
  exit 0
fi
_probe="$(printf 'x\n' | awk '{ print }' 2>/dev/null)" || _probe=""
if [[ "$_probe" != "x" ]]; then
  # fail-open-ok: awk is absent or broken, so the lexer cannot run; this hook
  # says nothing rather than deny commands it has not read (decision 1).
  exit 0
fi
if ! CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  # fail-open-ok: a payload jq cannot parse carries no command this hook can
  # read (decision 1).
  exit 0
fi

# THE ONE DENY. The command is lexed ONCE, into segments and words the way the
# shell would hand them to git, and nothing else is done to the text. A word is
# the act; a message is one word.
deny_hard() { # deny_hard <reason>  ->  permissionDecision "deny", the one rule that vetoes
  adv_code_of "$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s},"systemMessage":%s,"setlistAdvisory":{"gate":"bypass-deny","verdict":"deny","code":%s,"reason":%s}}\n' \
    "$(printf '%s' "$1" | jq -Rs .)" \
    "$(printf 'setlist %s' "$1" | jq -Rs .)" \
    "$(printf '%s' "$ADV_CODE" | jq -Rs .)" \
    "$(printf '%s' "$1" | jq -Rs .)"
  # fail-open-ok: this exit 0 delivers a DENY, not an allow: the harness reads
  # the JSON's permissionDecision, and a hook that exits non-zero would be an
  # error the harness reports rather than a verdict it enforces.
  exit 0
}
# The lexer, in awk so the same bytes run under bash 3.2 and BWK awk. PINNED:
# the suite hashes this assignment block, from its opening line to its closing
# quote, and refuses any change to it (spec 0143, decision 6).
BYPASS_LEX_AWK='
function flush() { if (inw) { W[++nw] = w }; w = ""; inw = 0 }
function judge(   j, g, k, sub_, x) {
  if (verdict != "") { nw = 0; return }
  # F2 OF THE SECOND 2.7.0 LEG: AT ASSIGNMENT POSITION, NOT ANYWHERE IN THE SEGMENT.
  # This loop read EVERY word of the segment, so any command carrying the spelling
  # as data drew the one hard deny in the session layer. Measured on the shipped
  # bytes: echo "SETLIST_SKIP_HOOKS=1", grep -rn SETLIST_SKIP_HOOKS=1 . and
  # git commit -m "SETLIST_SKIP_HOOKS=1" all denied, while one more character in
  # the message cleared it. Two of those are read-only commands and the third is an
  # ordinary commit, and the deny reason promised in its own last sentence that a
  # message merely quoting the spelling is not denied.
  # A shell assignment prefix can only appear BEFORE the command word, optionally
  # after env or export, so that is where the test belongs. Past the command word
  # every remaining word is data as far as this gate is concerned.
  for (j = 1; j <= nw; j++) {
    if (W[j] ~ /^SETLIST_SKIP_(HOOKS|TRUNK_AUDIT)=1$/) { verdict = "var"; nw = 0; return }
    if (W[j] == "env" || W[j] == "export") continue
    if (W[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
    break
  }
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
    # F2, second half: the OPERAND of a value-taking option is data, not a flag.
    # git log --grep "--no-verify" was vetoed while the equals spelling of the same
    # read-only command allowed, so two spellings of one command disagreed and the
    # unpinned one was the hole. A word git consumes as a value cannot also be the
    # flag that disables hooks: git commit --message --no-verify sets a message and
    # passes no such flag. The attacking spellings are untouched, because in
    # git commit --no-verify -m x and in git commit -m x --no-verify the word is not
    # preceded by an option expecting a value.
    if (j > g + 1 && W[j - 1] ~ /^(-m|--message|--grep|--author|--committer|--date|-F|--file|--pathspec-from-file)$/) continue
    # THE 2.8.0 LEG FALSE DENIALS F11, F12 AND F14, fixed by the owner ruling of
    # 2026-09-16 (spec 0147, fix round 1). Each is scoped so that what it does not
    # cover keeps the deny it had: a bare -- after the subcommand ends option
    # reading, as the git option parser does; -S, -G, -L and -e take a value only for
    # the log and grep family named here, never for commit, where -S signs and -e
    # edits; and a combined short flag of commit ending in m or F takes the next word
    # as its value (-am, -sm), while -nm is still read as -n first, one word earlier.
    # FIX ROUND 3 (spec 0147, the owner A4 exception of 2026-09-16), repairing a bypass ROUND 1
    # INTRODUCED. git gives a value-taking short option the REST of the combined flag as its value,
    # so -amm is -a plus -m whose value is the embedded m, and the next word is not a value at all:
    # it is --no-verify, still live. Round 1 skipped that word and the deny never fired; five
    # spellings returned allow and four of them LANDED a commit past a failing pre-commit hook.
    # [^mF]* requires every letter before the final m or F to be non-value-taking, which is exactly
    # the case where the value IS the next word. Measured identical under BWK awk, gawk and mawk.
    # FIX ROUND 2 (spec 0147, 2026-09-16): the search-option rule reads a COMBINED
    # short flag too. Round 1 matched one letter only, so git log -pS --no-verify
    # stayed DENIED although git runs it (measured rc 0) while the separated spelling
    # git log -p -S --no-verify was allowed: two spellings of one command disagreeing,
    # which is the hole the F2 rule above closes for long options. The scope is
    # unchanged, so git commit -sS --no-verify is still denied, and only the single
    # word after the flag is skipped, so a chained git commit --no-verify still denies.
    # Found by the COLD ADVERSARY ROUND of this release, not by the leg.
    if (j > k && x == "--") break
    if (j > g + 1 && sub_ ~ /^(log|show|whatchanged|grep|blame|annotate|reflog|rev-list|shortlog)$/ && W[j - 1] ~ /^-[A-Za-z]*[SGLe]$/) continue
    if (j > k + 1 && sub_ == "commit" && W[j - 1] ~ /^-[^mF]*[mF]$/) continue
    if (x == "--no-verify" || x == "--no-verif" || x == "--no-veri") { verdict = "noverify"; break }
    if (sub_ == "commit" && j > k && x ~ /^-[aeiopqsvz]*n[a-zA-Z]*$/) { verdict = "noverify"; break }
    if ((x == "-c" && j < nw && tolower(W[j + 1]) ~ /^core\.hookspath(=|$)/) || tolower(x) ~ /^-ccore\.hookspath(=|$)/) { verdict = "hookspath"; break }
  }
  nw = 0
}
BEGIN { RS = "\001"; cmd = ""; verdict = "" }
{ cmd = cmd $0 }
END {
  n = length(cmd); i = 1; w = ""; inw = 0; q = ""; nw = 0; nhd = 0
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
    # A HEREDOC BODY IS DATA (the 2.8.0 leg F5 and F6, the same ruling). An unquoted
    # << that starts a word queues its delimiter, and the next unquoted newline skips
    # the body up to its terminator line, but only when the command reading it is cat,
    # tee or git. Everything else keeps being judged line by line: an interpreter such
    # as bash reading the body, a body with no terminator line, an opener glued to a
    # word or numbered, and an arithmetic shift inside a word.
    if (c == "<" && !inw && substr(cmd, i + 1, 1) == "<" && substr(cmd, i + 2, 1) != "<") {
      i += 2; hdash = 0
      if (substr(cmd, i, 1) == "-") { hdash = 1; i++ }
      while (substr(cmd, i, 1) == " " || substr(cmd, i, 1) == "\t") i++
      hd_d = ""; hq = substr(cmd, i, 1)
      if (hq == "\047" || hq == "\"") { i++; while (i <= n && substr(cmd, i, 1) != hq) { hd_d = hd_d substr(cmd, i, 1); i++ }; i++ }
      else { if (hq == "\\") i++; while (i <= n && substr(cmd, i, 1) !~ /[ \t\n;&|<>()]/) { hd_d = hd_d substr(cmd, i, 1); i++ } }
      if (hd_d != "" && nw >= 1 && W[1] ~ /(^|\/)(cat|tee|git)$/) { HD[++nhd] = hd_d; HDT[nhd] = hdash }
      continue
    }
    if (c == "#" && !inw) { while (i <= n && substr(cmd, i, 1) != "\n") i++; continue }
    if (c == ";" || c == "|" || c == "&" || c == "\n" || c == "(" || c == ")" || c == "{" || c == "}") {
      flush(); judge()
      if ((c == "&" || c == "|") && substr(cmd, i + 1, 1) == c) i++
      if (c == "\n" && nhd > 0) {
        hp = i + 1; hok = 1
        for (hh = 1; hh <= nhd && hok; hh++) {
          hfound = 0
          while (hp <= n) {
            he = index(substr(cmd, hp), "\n"); hl = he ? substr(cmd, hp, he - 1) : substr(cmd, hp); hp = he ? hp + he : n + 1
            if (HDT[hh]) sub(/^\t+/, "", hl)
            if (hl == HD[hh]) { hfound = 1; break }
          }
          if (!hfound) hok = 0
        }
        if (hok) i = hp - 1
        nhd = 0
      }
      i++; continue
    }
    w = w c; inw = 1; i++
  }
  flush(); judge()
  print verdict
}'
BYPASS_VERDICT="$(printf '%s' "$CMD" | awk "$BYPASS_LEX_AWK" 2>/dev/null)" || BYPASS_VERDICT="" # fail-open-ok: an awk that fails on this command yields no deny; the probe above has already let a broken awk through silently, by decision 1
BYPASS_WHAT=""
case "$BYPASS_VERDICT" in
  hookspath)
    deny_hard "bypass deny [CM-HOOKSPATH-MOVED]: this git command moves core.hooksPath for its own run, which disarms every Setlist git hook at once (commit, merge and push) without touching the repository's configuration. This hook DENIES it (the one rule in this layer that does). If a hook refused something, fix what it named; if you are the person who owns this exception, run the command yourself in a terminal." ;;
  var)      BYPASS_WHAT="sets a Setlist escape variable, which switches the git-hook boundary off for everything it runs" ;;
  noverify) BYPASS_WHAT="passes --no-verify to git (or a spelling git reads as it), which skips the git hooks that carry the boundary for this one operation" ;;
esac
if [[ -n "$BYPASS_WHAT" ]]; then
  deny_hard "bypass deny [CM-BYPASS-SPELLED]: this command $BYPASS_WHAT. The escapes exist for a PERSON who owns an exception, and a session does not get to spend them: this hook DENIES the command (the one rule in this layer that does). If the boundary refused something, fix what it named; if you are the person and this is your deliberate exception, run the command yourself in a terminal. A message that merely quotes the spelling is not denied."
fi

# fail-open-ok: no disarming spelling was read. This hook asks one question and
# has no other verdict to give, so it says nothing.
exit 0
