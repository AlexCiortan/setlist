#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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
#      one parser that survives it). Changed since, each time by decision and
#      moving the pin in the same edit: the owner's ruling of 2026-09-16 fixed
#      the 2.8.0 leg's confirmed false denials inside it (spec 0147, fix round
#      1); the owner's clean-release rule of 2026-09-18 took DE18 and DE17 (spec
#      0159); the 2.10.0 leg's lexer findings (spec 0164, fix round 2); and the
#      2.10.0 second leg's F12 and F17 (spec 0170).
# The suite asserts all three, in region bypass-deny-0143.
#
# THE LEXER'S TWO MEASURED RULES are why this is a lexer rather than a substring
# test: the assignment-position test (a commit message merely quoting the escape
# was denied) and the value-operand test (git log --grep "--no-verify" was
# denied). Both were false denials a leg measured on shipped bytes, and each
# rule exists so that the denial it corrected cannot come back.
# Spec 0147 added three for the 2.8.0 leg's confirmed
# false denials: a bare -- after the subcommand ends option reading, the log and
# grep family's value-taking short options, and a heredoc body read by cat, tee
# or git is data. Each keeps the deny it had wherever it does not apply. Spec
# 0159 widened the last one three ways: the owner is the command word after a
# short prefix walk; cat<<EOF glued to its owner is a heredoc too; and a body is
# judged when a later segment of the same pipeline on the opener's line
# (segments joined by | or |&) has bash, sh or zsh as its command word, found by
# the same walk, or behind a walked wrapper (env, command, nohup, exec, sudo, nice
# or time) read by that wrapper own option grammar (sudo -E bash, env -Sbash,
# sudo -Hu root bash), or is sudo -s or -i with no command (spec 0170). A new
# owner body piped to a reader that cannot run a shell (tee, cat, grep) is data.
# An owner only the walk or the glued rule finds has its body skipped only on a
# PLAIN opener line (no pipe, no parenthesis, brace or backtick, and no eval,
# source, . or interpreter as a command word), and judged on any other, as
# 2.9.0 judged it.
# For an owner 2.9.0 already read (cat, tee or git first, spaced), the rule is
# that and no wider, so an interpreter the walk does not reach is not seen:
# behind a wrapper spelled by its path (/usr/bin/env bash), by a reader the walk
# does not name (| dash, | awk with system()), in a brace group piped on, after
# a redirection such as 2>&1 before the pipe, or down a pipe carried past the
# newline. None of these is judged by 2.9.0
# either.
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
# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
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
# THE COMMAND WORD (spec 0159, DE18 F9 of the 2.9.0 leg). The owner test used to read W[1], so
# env cat << EOF or LC_ALL=C cat << EOF turned documentation prose back into a denial. The walk
# skips the prefix list of the DE18 entry and nothing wider: an assignment, env, export, command, nohup,
# exec, sudo, and one leading redirection. Any other prefix, or an option to a wrapper, stops the walk
# on a word that is no owner, which keeps the verdict the lexer had before.
function cmdw(n,   j, r) {
  r = 0
  for (j = 1; j <= n; j++) {
    if (W[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
    if (W[j] == "env" || W[j] == "export" || W[j] == "command" || W[j] == "nohup" || W[j] == "exec" || W[j] == "sudo") continue
    if (!r && W[j] ~ /^[0-9]*(<|>|>>)/) { r = 1; if (W[j] ~ /^[0-9]*(<|>|>>)$/) j++; continue }
    return j
  }
  return 0
}
# An interpreter in a segment marks the pipeline it belongs to (DE18 F4): a body an owner writes into
# a pipe that bash, sh or zsh reads is code, not data. Only a segment AFTER a heredoc was queued in the
# pipeline counts, since an interpreter before it does not read the body; and a walk that stops on an
# option of a wrapper (sudo -E bash, env -i sh) reads on for the interpreter (the cold review, round 4).
# WHICH OPTIONS OF EACH WALKED WRAPPER TAKE A VALUE (spec 0170, L2 F12 of the 2.10.0 second leg),
# from each tool own option grammar, never from a list of spellings: env takes -u, -C, -P and -S and
# the long --unset, --chdir and --split-string (GNU coreutils 9.4 and the BSD env macOS ships); sudo
# takes -a, -C, -c, -D, -g, -h, -p, -R, -r, -T, -t, -U and -u and the long name of each; exec takes -a;
# nice takes -n and --adjustment; time, which after a pipe is the command and not the keyword, takes
# -o and -f and --output and --format; command and nohup take none. optval answers for one short
# letter, longval for a long name or a prefix of one, because getopt accepts an unambiguous prefix
# (env --unse A runs, measured) and an exact name wins over a longer one (sudo --login is a flag).
function optval(wr, o) {
  if (wr == "env") return (o ~ /^[uCPS]$/)
  if (wr == "sudo") return (o ~ /^[aCcDghpRrTtUu]$/)
  if (wr == "exec") return (o == "a")
  if (wr == "nice") return (o == "n")
  if (wr == "time") return (o ~ /^[of]$/)
  return 0
}
function longval(wr, l,   n, i, L) {
  if (l == "" || (wr == "sudo" && l == "login")) return 0
  if (wr == "env") n = split("unset chdir split-string", L, " ")
  else if (wr == "sudo") n = split("auth-type close-from login-class chdir group host prompt chroot role type command-timeout other-user user", L, " ")
  else if (wr == "nice") n = split("adjustment", L, " ")
  else if (wr == "time") n = split("output format", L, " ")
  else return 0
  for (i = 1; i <= n; i++) if (index(L[i], l) == 1) return 1
  return 0
}
# THE COMMAND A WALKED WRAPPER RUNS, read by the rules getopt applies (spec 0170, L2 F12): in a
# short-option word the letters are read in turn, and the first that takes a value takes the REST of
# the word, or the NEXT word when the word ends there; a long option takes what follows =, or the next
# word; -- ends the options; env and sudo read NAME=value words before the command; the value of env
# -S (--split-string) is split into words that stand where the option stood, so env -Sbash runs bash;
# and sudo -s or -i (--shell, --login) runs a shell, which reads the body itself when no command
# follows. The walk goes on through a wrapper after a wrapper. X holds the words from the first
# option on; the index in X of the command word is returned, -1 for the shell of sudo -s or -i with
# no command, or 0.
function wcmd(wr,   j, op, sh, x, l, v, o, m, t, nt, T, U) {
  j = 1; op = 1; sh = 0
  while (j <= nx) {
    x = X[j]; v = ""; o = ""
    if (op && x == "--") { op = 0; j++; continue }
    if (op && wr == "env" && x == "-") { j++; continue }
    if (op && x ~ /^-./) {
      if (x ~ /^--/) {
        l = substr(x, 3); m = index(l, "=")
        if (m) { v = substr(l, m + 1); l = substr(l, 1, m - 1) }
        if (wr == "sudo" && l != "" && (index("shell", l) == 1 || l == "login")) sh = 1
        if (longval(wr, l)) { if (!m) { j++; v = X[j] }; if (wr == "env" && index("split-string", l) == 1) o = "S" }
      } else {
        for (m = 2; m <= length(x); m++) {
          o = substr(x, m, 1)
          if (optval(wr, o)) { v = substr(x, m + 1); if (v == "") { j++; v = X[j] }; break }
          if (wr == "sudo" && o ~ /^[si]$/) sh = 1
          o = ""
        }
      }
      if (o == "S" && wr == "env") {
        nt = split(v, T, " "); m = 0
        for (t = j + 1; t <= nx; t++) U[++m] = X[t]
        for (t = 1; t <= nt; t++) X[t] = T[t]
        for (t = 1; t <= m; t++) X[nt + t] = U[t]
        nx = nt + m; j = 1; continue
      }
      j++; continue
    }
    if ((wr == "env" || wr == "sudo") && x ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { j++; continue }
    if (x ~ /^(env|command|nohup|exec|sudo|nice|time)$/) { wr = x; op = 1; j++; continue }
    return j
  }
  return sh ? -1 : 0
}
# WHICH READERS ARE DATA SINKS. A body piped to one of these is read as bytes,
# never as commands, so a new-owner heredoc feeding one is still data (spec
# 0164, fix round 2, F11: `cat<<EOF | tee -a FILE` was refused while the
# redirection spelling one character away was allowed). awk, sed, less and more
# left the list in spec 0170 (L2 F17): each has a command that runs a shell (awk
# system(), the e command of GNU sed, the ! of a pager), so none of them is a
# sink. Anything not named here keeps the conservative reading a new owner has
# carried since 2.9.0.
function sink(w) { return (w ~ /^(tee|cat|wc|grep|egrep|fgrep|head|tail|sort|uniq|tr|cut|nl|fmt|tac|rev|column|jq|xxd|hexdump|md5|md5sum|shasum|sha256sum|diff|patch)$/) }
function interp(   k, j) {
  if (!HQ[pl]) return
  k = cmdw(nw)
  # Only a segment AFTER the opener counts: the owner itself is cat or tee, and
  # letting it mark its own pipeline benign would make every new-owner body data.
  if (HSEG) HSEG = 0
  else if (k && sink(W[k])) { if (BEN[pl] == "") BEN[pl] = 1 }
  else if (k) BEN[pl] = 0
  if (k && W[k] ~ /(^|\/)(bash|sh|zsh)$/) { PI[pl] = 1; return }
  # Past the options, and the value of each that takes one, to the command word: an interpreter named
  # later is an argument (grep -c bash), not the command (the cold review, round 7). By each wrapper
  # own grammar (spec 0164 fix round 2, F10, then spec 0170, F12), so neither command -p bash nor env
  # -Sbash nor sudo -Hu root bash hides the interpreter; nice and time, which the owner walk does not
  # skip, are walked here too (spec 0170, the validator ruling E-a).
  j = 0
  if (k && W[k] ~ /^(nice|time)$/) { nx = 0; for (j = k + 1; j <= nw; j++) X[++nx] = W[j]; j = wcmd(W[k]) }
  else if (k > 1 && W[k] ~ /^-/ && W[k - 1] ~ /^(env|command|nohup|exec|sudo)$/) { nx = 0; for (j = k; j <= nw; j++) X[++nx] = W[j]; j = wcmd(W[k - 1]) }
  if (j < 0 || (j > 0 && X[j] ~ /(^|\/)(bash|sh|zsh)$/)) PI[pl] = 1
}
# A line is PLAIN when it holds no pipe, no parenthesis, brace or backtick, and no segment whose command
# word is eval, source, . or an interpreter. Only on a plain line is the body of a NEW owner skipped, since
# anywhere else the shell may run the body (a pipe, a process or command substitution, an eval), and
# 2.9.0 judged it (the cold review of spec 0159, rounds 4, 6 and 7).
# A segment whose command word READS ITS INPUT AS CODE marks its own pipeline,
# not the whole line (spec 0164, fix round 2, F9): this used to set the
# line-wide flag, so `cat << A; cat << B | bash` judged A body because B
# segment was an interpreter, and each body is credited to its own opener now.
function plain(   k) { if (!HQ[pl]) return; k = cmdw(nw); if (k && W[k] ~ /^(eval|source|\.)$|(^|\/)(bash|sh|zsh)$/) PI[pl] = 1 }
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
  n = length(cmd); i = 1; w = ""; inw = 0; q = ""; nw = 0; nhd = 0; pl = 0; hnew = 0; LXG = 0; LXP = 0; SUBD = 0; HSEG = 0
  while (i <= n) {
    c = substr(cmd, i, 1)
    if (q == "\047") { if (c == "\047") q = ""; else w = w c; inw = 1; i++; continue }
    if (q == "\"") {
      if (c == "\\") { d = substr(cmd, i + 1, 1); if (d == "\"" || d == "\\" || d == "$" || d == "`") { w = w d; i += 2 } else { w = w c; i++ }; continue }
      if (c == "\"") { q = ""; i++; continue }
      w = w c; inw = 1; i++; continue
    }
    # A BACKSLASH-NEWLINE IS A LINE CONTINUATION, NOT A CHARACTER (spec 0164,
    # fix round 2, F15 of the 2.10.0 leg): appending the newline to the word
    # made a phantom word, so `git commit -m \` + newline + `"--no-verify"` and
    # a read-only `git log --grep \` + newline + `"--no-verify"` were both
    # refused, while the same commands on one line were allowed. The shell
    # removes the pair and joins the lines; so does this.
    if (c == "\\" && substr(cmd, i + 1, 1) == "\n") { i += 2; continue }
    if (c == "\\") { w = w substr(cmd, i + 1, 1); inw = 1; i += 2; continue }
    if (c == "\047" || c == "\"") { q = c; inw = 1; i++; continue }
    if (c == " " || c == "\t") { flush(); i++; continue }
    # A HEREDOC BODY IS DATA (the 2.8.0 leg F5 and F6, the same ruling). An unquoted
    # << queues its delimiter, and the next unquoted newline skips the body up to its
    # terminator line, but only when the command reading it is cat, tee or git (its
    # command word, found by the walk above). Everything else keeps being judged line
    # by line: an interpreter such as bash reading the body, directly or down the same
    # pipeline, a body with no terminator line, and an arithmetic shift inside a word.
    # A numbered opener in the segment of an owner (cat 2<<EOF) is a heredoc like any
    # other: its body goes to another descriptor and is data.
    # GLUED TO A WORD (spec 0159, DE17): cat<<EOF is a heredoc when the word it is glued
    # to, or the command word of its segment, is an owner. Nowhere else, so $((1<<2)) is not
    # an operator: ( ends a segment, and the 1 before << is a fresh word with no owner.
    # A < right after another < is never an opener: <<<y is a here-string, and its
    # second and third < are not a heredoc (the cold review of spec 0159, claim 1).
    if (c == "<" && substr(cmd, i + 1, 1) == "<" && substr(cmd, i + 2, 1) != "<" && inw && substr(cmd, i - 1, 1) != "<") {
      W[nw + 1] = w; k = cmdw(nw + 1); hg = (k && W[k] ~ /(^|\/)(cat|tee|git)$/); delete W[nw + 1]
      if (hg) { flush(); hnew = 1 }
    }
    if (c == "<" && !inw && substr(cmd, i + 1, 1) == "<" && substr(cmd, i + 2, 1) != "<") {
      i += 2; hdash = 0
      if (substr(cmd, i, 1) == "-") { hdash = 1; i++ }
      while (substr(cmd, i, 1) == " " || substr(cmd, i, 1) == "\t") i++
      hd_d = ""; hq = substr(cmd, i, 1)
      if (hq == "\047" || hq == "\"") { i++; while (i <= n && substr(cmd, i, 1) != hq) { hd_d = hd_d substr(cmd, i, 1); i++ }; i++ }
      else { if (hq == "\\") i++; while (i <= n && substr(cmd, i, 1) !~ /[ \t\n;&|<>()]/) { hd_d = hd_d substr(cmd, i, 1); i++ } }
      k = cmdw(nw)
      # An owner 2.9.0 did not read (found by the walk, or glued) is NEW: its body is skipped only when
      # the opener LINE is plain (the function above), so no spelling the pipeline test misses can
      # skip a body 2.9.0 judged (the cold review of spec 0159, rounds 4, 6 and 7).
      if (hd_d != "" && k && W[k] ~ /(^|\/)(cat|tee|git)$/) { HD[++nhd] = hd_d; HDT[nhd] = hdash; HPL[nhd] = pl; HNEW[nhd] = (k > 1 || hnew); HSUB[nhd] = (SUBD > 0); HQ[pl] = 1; HSEG = 1 }
      hnew = 0
      continue
    }
    if (c == "#" && !inw) { while (i <= n && substr(cmd, i, 1) != "\n") i++; continue }
    if (c == ";" || c == "|" || c == "&" || c == "\n" || c == "(" || c == ")" || c == "{" || c == "}") {
      flush(); interp(); plain(); judge()
      # LXG is a GROUPING or substitution on this line; LXP is a plain pipe.
      # They were one flag, and a pipe then judged a body no interpreter reads
      # (spec 0164, fix round 2, F11): `cat<<EOF | tee -a FILE` was refused
      # while the redirection spelling one character away was allowed. A pipe
      # only matters when a reader of that pipeline is an interpreter, which
      # PI[] already answers.
      if (c == "(" || c == ")" || c == "{" || c == "}") LXG = 1
      # A SUBSTITUTION is not a group: its output is read by the command around
      # it, so a heredoc opened inside one is judged wherever the opener sits
      # (spec 0164, fix round 2, F13). A brace or paren group is not, which is
      # what keeps the disclosed `{ cat << EOF; } | bash` shape where it was.
      if (c == "(" && substr(cmd, i - 1, 1) ~ /[$<>]/) SUBD++
      else if (c == ")" && SUBD > 0) SUBD--
      dbl = ((c == "&" || c == "|") && substr(cmd, i + 1, 1) == c)
      if (c == "|" && !dbl) LXP = 1
      if (dbl) i++
      # |& pipes stdout and stderr: one pipe, so the pipeline continues.
      else if (c == "|" && substr(cmd, i + 1, 1) == "&") i++
      if (c == "\n" && nhd > 0) {
        # A queued body whose pipeline reaches an interpreter by this newline is
        # judged, not skipped (E-a of spec 0159, RULED 2026-09-22: any later segment
        # joined by | alone). A pipe continued on a later line is not seen here.
        # EACH BODY IS CREDITED TO ITS OWN OPENER (spec 0164, fix round 2, F9).
        # One verdict used to cover every heredoc queued on the line, so a body
        # whose own segment reads it as data was judged because a LATER opener
        # on the same line was piped to an interpreter. The bodies arrive in
        # order, so each is skipped while it is data and the walk stops at the
        # first one that is not: that body, and everything after it, stays in
        # the stream to be judged.
        hp = i + 1; hlast = hp
        for (hh = 1; hh <= nhd; hh++) {
          # A line that ends while a pipe is still open hands the body to a
          # reader this pass cannot see, so it is judged rather than skipped.
          # A NEW owner (prefixed or glued) on a line with a pipe keeps the
          # conservative reading 2.9.0 gave it, EXCEPT where every reader after
          # it in that pipeline is a data sink (F11); a pipeline still open at
          # the newline hands the body to a reader this pass cannot see, so a
          # new owner there is judged too.
          if (PI[HPL[hh]] || HSUB[hh] \
              || (HNEW[hh] && LXP && (BEN[HPL[hh]] != 1 || substr(cmd, i - 1, 1) == "|"))) break
          hfound = 0
          while (hp <= n) {
            he = index(substr(cmd, hp), "\n"); hl = he ? substr(cmd, hp, he - 1) : substr(cmd, hp); hp = he ? hp + he : n + 1
            if (HDT[hh]) sub(/^\t+/, "", hl)
            if (hl == HD[hh]) { hfound = 1; break }
          }
          if (!hfound) break
          hlast = hp
        }
        if (hlast > i + 1) i = hlast - 1
        nhd = 0
      }
      # A pipeline ends at ; & && || and a newline; a single | continues it. A line
      # ends at a newline, and with it the record of whether the line held a pipe.
      if (c == ";" || c == "&" || c == "\n" || dbl) pl++
      if (c == "\n") { LXG = 0; LXP = 0 }
      i++; continue
    }
    if (c == "`") { LXG = 1; SUBD = SUBD ? SUBD - 1 : 1 }
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
