#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Shared logic for the Setlist git hooks. Sourced by pre-commit and
# pre-merge-commit; not executable on its own.
#
# WHY A LIBRARY RATHER THAN TWO COPIES. The close verification has to run from
# two different hooks, because git fires different hooks for a true merge and
# for the commit that completes a squash (measured, see pre-commit's header).
# Two copies of a rule is exactly the shape of leg 5's F8, where a gate and its
# only backstop went blind the same way at the same time, and of backlog item 35,
# where a gate and its backstop agreed on something wrong. One copy, sourced
# twice.
#
# The QA verdict rule below is byte-identical to the assignment in
# scripts/trunk-audit.sh, and the test suite asserts the two match (a third
# copy left in 2.8.0). Two copies are already more than anybody can hold in
# their head, which is why the assertion exists rather than a comment asking
# people to remember.
#
# EVERYTHING IN THE GIT-HOOK LAYER FAILS CLOSED: a dependency that is absent,
# broken, or merely stricter than expected routes to a refusal, never to a
# silent pass. That rule is not general caution: plugin 1.0.8 shipped a
# fail-open to every Mac because an awk that exited 2 produced an empty string
# and an empty string read as "nothing to govern"
# (the pipeline redesign that made every awk stage carry its own status).
#
# THE SCOPE OF THAT SENTENCE IS THIS LAYER, and it was overstated until the
# v1.7 claims audit. Two corrections, both measured rather than argued. The
# PreToolUse session gates in templates/hooks/ do NOT fail closed: they were
# made advisory in v1.7 and every failure path there reports a code without
# refusing (and, since spec 0181, without answering the user's permission
# prompt), so a broken jq leaves the write to the session's own permission mode
# and this layer is what refuses it afterwards. And pre-push itself did not probe its toolchain until the same
# audit, so a broken grep made its scan report clean; that is fixed, and the
# fix is why this paragraph can say "never to a silent pass" about the git
# hooks at all.

# EVERY READER IN THIS PROCESS READS BYTES (spec 0169; L2 F2 and F11 of the
# 2.10.0 cycle). Fix round 1 put LC_ALL=C on the five content-scan stages and
# left the readers of specs/STATUS.md and of the spec records on the caller's
# locale, so one byte that is not valid UTF-8 aborted macOS awk and sed
# mid-read: the caller kept the partial output, a compliant close was refused
# at merge and at push with a false reason, and a close after the byte was
# never seen, so a spec with no Closing report merged. Set ONCE here, where
# every hook that sources this file and every process those hooks start
# inherits it, rather than stage by stage, because the stage-by-stage fix is
# the one that covered five sites and missed ten. The C locale reads the same
# answer from every valid byte and a whole answer from an invalid one; git's
# own messages in these processes read in English, and a case fold here is
# ASCII-only.
LC_ALL=C; export LC_ALL

# NO READER EXITS BEFORE ITS WRITER IS DONE (spec 0169, CHK-REPORT-READ's cause,
# h5). `printf ... | grep -q` let grep exit at its first match while the writer
# was still writing; where SIGPIPE is ignored (the Linux CI runner) the writer
# then printed "write error: Broken pipe" into the hook's or the audit's output,
# so a report varied under load while its verdict did not. Readers of computed
# text are fed from a here-string, and a first line is taken by a reader that
# reads the whole text. A git writer is left as it is: git exits quietly.

# A VALUE THE REPOSITORY CHOSE, IN A SENTENCE THIS FILE SPEAKS (spec 0169, sweep
# A.3.4). A refusal is read by the model driving git and by a CI log a forge
# parses for workflow commands, and it used to carry repository text whole: a
# file name holding a newline printed forged report lines, and a configured
# string shaped as prose read as the framework speaking. The precedent is the
# regrounding hook's armed check (spec 0164, F14). Three kinds:
#   name  <v>     a path, a trunk, a role, a label, a token, an identity or a
#                 configured string: quoted, every byte outside the set a path
#                 needs replaced with ?, cut at 80 characters, and the edit said.
#   names <list>  one name per line, each bounded as above, joined with ", ",
#                 at most 20 and the rest counted.
#   text  <v>     free text by design (a commit subject, a command's output):
#                 its characters and the caller's cap kept, its control bytes,
#                 escapes and newlines gone.
# BYTE-IDENTICAL to the copy in scripts/trunk-audit.sh, which ships alone, and
# the suite asserts the two match.
# The CODEOWNERS reader's own description of a line it does not evaluate is
# fixed text, except the one that quotes the offending owner token: only that
# token is the repository's, so only it is bounded (spec 0169, sweep A.3.4).
# BYTE-IDENTICAL to the copy in scripts/trunk-audit.sh.
slh_codeowners_what() { # slh_codeowners_what <description> -> the description with its owner token bounded
  local d="$1" t
  case "$d" in
    "an owner that is not @login, @org/team or an email ("*")")
      t="${d#an owner that is not @login, @org/team or an email (}"; t="${t%)}"
      printf 'an owner that is not @login, @org/team or an email (%s)' "$(slh_bound name "$t")" ;;
    *) printf '%s' "$d" ;;
  esac
}
slh_bound() { # slh_bound <name|names|text> <value>
  local k="$1" v="$2" s e="" n=0 l out=""
  case "$k" in
    text)
      v="${v//$'\n'/ }"; v="${v//$'\r'/ }"; v="${v//$'\t'/ }"
      printf '%s' "$v" | tr -d '\000-\037\177'
      return 0 ;;
    names)
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        n=$((n + 1))
        [ "$n" -le 20 ] && out="${out:+$out, }$(slh_bound name "$l")"
      done <<SLHBOUNDEOF
$v
SLHBOUNDEOF
      [ "$n" -gt 20 ] && out="$out and $((n - 20)) more"
      printf '%s' "$out"
      return 0 ;;
  esac
  s="${v//[^A-Za-z0-9._\/ :+=@-]/?}"
  [ "$s" = "$v" ] || e=" (characters outside a path set replaced with ?)"
  if [ "${#s}" -gt 80 ]; then s="${s:0:80}"; e="$e (cut at 80 characters)"; fi
  printf '"%s"%s' "$s" "$e"
}


# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
# The verdict rule. LOCKSTEP: trunk-audit.sh and this file.
#
# SCOPED (2.0.0 leg, F8/F3): the block that decides is the FIRST qa-pass-1 fence
# at fence depth ZERO inside a Closing report section. Third fence-vs-QA-block
# collision, so the scoping is structural rather than another special case: the
# reader tracks fences the way the template stripper does (open on three or
# more backticks or tildes, close on a bare fence of the same character and at
# least the same length), and an opener seen inside another fence is CONTENT.
# That closes both directions at once: a block nested inside a pasted verifier
# report cannot satisfy the check (F8, which reached the trunk and the audit
# called it clean), and an illustrative shape-quote outside the Closing report
# cannot poison a real verdict (F3, refused at all three layers with a reason
# naming the wrong block).
#
# FIRST WINS, ruled 2026-08-29 (F7-2026), and this reader read LAST until then.
# The Closing report owns ONE verdict. An illustrative block comes after the
# real one by construction, so last-wins let a later example replace a real
# verdict in both directions; and a genuine revision EDITS THE VERDICT IN PLACE
# rather than appending a rival, so nothing legitimate depended on the old
# rule. A second block is now read as an ordinary fence: it neither satisfies
# nor poisons. Headings are
# read only at depth zero, so a template quoted in a fence cannot open the
# section, and the section ends at the next heading of the same or shallower
# level. A HEADING IS WHAT MARKDOWN SAYS A HEADING IS (second 2.0.0 leg, F1):
# at most three spaces of indent, one to six hashes, then space, tab or end of
# line. The first cut entered the heading branch on "first char is #" after
# stripping indentation, so an issue reference (#1234), an indented shell
# snippet (#!/usr/bin/env bash) and a pasted verifier banner each closed the
# section and a compliant close was refused at all three layers with a reason
# naming a block that was present. The Closing-report OPEN branch deliberately
# now requires the SAME strict ATX shape as the close branch to agree with the
# section-exists grep elsewhere in this file. The cheap adversary then priced the
# asymmetry the first refinement left: a LOOSE open beside a STRICT close
# builds sections nothing can ever leave (##Closing report opened and ran
# to EOF, accepting any later example fence), so the OPEN branch now
# requires the same ATX shape and the section-exists greps in all three
# files carry the identical definition. Lines are CR-stripped at ingest,
# so a CRLF empty heading still scopes. SETEXT headings (underlined) are a
# KNOWN, PINNED limitation: markdown calls them headings, this reader
# reads ATX only, and the pin in the suite makes any future widening a
# judged decision rather than drift. A tab-indented heading is a code
# block per markdown AND has always failed the column-anchored
# section-exists grep, so its refusal reason is the section code, honest
# at both layers. The suite asserts the three layers agree BY OUTCOME over a corpus,
# beside the byte-identity lockstep, because F8 proved three identical readers
# are just three readers wrong together.
SLH_QA_PASS1_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; qa_seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } } else { if (__r == "qa-pass-1" && inclose && !qa_seen) { inb = 1; qch = __c; qlen = __m; n = 0; bad = 0; next } fence = 1; fch = __c; flen = __m; next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "") next; if (l ~ /^[A-Za-z0-9._-]+[[:space:]]*:[[:space:]]*(PASS|PARTIAL|FAIL)$/) n++; else bad = 1; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) inclose = 0 } } END { if (incmt) print "unclosed-comment"; else if (inb) print "unclosed"; else if (!qa_seen) print "none"; else if (bad) print "malformed"; else if (n == 0) print "empty"; else print "ok" }'

# THE CLOSE REVIEW BLOCK (spec 0175). LOCKSTEP: trunk-audit.sh and this file, asserted.
#
# A second model reads every close against its spec before git merges it (the stamped
# close-reviewer agent, run by /setlist:checkpoint), and its verdict is a STRUCTURE for the
# reason the qa-pass-1 block is one: a pattern over prose cannot decide it. The block is the
# FIRST close-review fence at fence depth zero AFTER the Closing report heading, comments and
# nested fences read as the qa-pass-1 reader reads them, and the section ends at the next heading
# of the same or shallower level, as that reader's does. HOW A PASTED REPORT'S HEADINGS STAY
# CONTENT (spec 0180): the QA report is pasted verbatim above the block and an agent's report can
# carry `##` headings, which ended the section before the block (F-a of the 2.11.0 cold run).
# Fix round 1 read to the end of the file, and that also read a block in a SECTION AFTER the
# Closing report when the report carried none: a pasted heading and a real later section are the
# same bytes. So, as the validator ruled in fix round 2, /setlist:checkpoint pastes each report
# inside a four-backtick fence, where its headings are content, and a block found after a heading
# that ended the section is refused with both lines named, never reported absent.
# THE SECTION AND THE FENCE ARE READ AS MARKDOWN READS THEM (spec 0180, fix round 2, the 2.11.0
# leg's F3, F12 and F16). Only a heading that IS "Closing report" opens the section, the
# template's parenthetical and closing hashes allowed: a heading that merely began with the words
# ("## Closing report contract") opened it, and first-wins let a decoy PASS above the real
# section pre-empt a real FAIL. The info string is compared trimmed, never squeezed: deleting
# every space read "close - review", a `close` block to every renderer, as the block. And a block
# no reader reached because an ordinary fence above it was left open is refused with that fence
# named by line (the reader's own line count, which is the file's unless a template example above
# was stripped), never as a block the spec does not carry. Every line inside the block is one of
# four shapes:
#   round <1|2>: PASS|FAIL|SKIP-DOCS-ONLY            the reviewer's verdict for the round
#   <criterion>: PASS|PARTIAL|FAIL                   one per criterion, the qa-pass-1 grammar
#   <id> | <criterion or -> | BLOCKER|MAJOR|MINOR | <path>:<line> | <what> | <fix>
#   verdict: ACCEPTED-BY-HUMAN <id>...               the human's decision at the cap
# Any other line refuses, never skips. Rounds run 1 then 2, never a third (the loop's cap); a
# finding without a file and a line is not a finding; a reviewed round carries at least one
# criterion verdict; a round reading PASS beside a FAIL criterion or a finding at MAJOR or above
# disagrees with itself and refuses, naming the disagreement; SKIP-DOCS-ONLY is round 1 and the
# only round, and carries nothing. The human's line comes last, only after a round 2 reading
# FAIL, and names every round-2 finding at MAJOR or above and nothing round 2 does not carry, so
# the reviewer's verdict stays verbatim beside the override instead of under it. ONE LINE out,
# its first word the token: none | unclosed | unclosed-comment | empty | malformed <why> |
# pass | fail | skip | accepted.
SLH_CLOSE_REVIEW_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); __ti = __raw; sub(/^[ \t]+/, "", __ti); sub(/[ \t]+$/, "", __ti); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } if (__ti == "close-review" && inclose && !seen && !nin) { nin = NR; ninl = fline; nint = ftext } } else { if (__ti == "close-review" && inclose && !seen) { inb = 1; qch = __c; qlen = __m; next } if (__ti == "close-review" && !inclose && endl && !seen && !late) late = NR; fence = 1; fch = __c; flen = __m; fline = NR; ftext = substr(__l, 1, 40); next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "" || bad != "") next; if (acc) { bad = "a line after the ACCEPTED-BY-HUMAN verdict"; next } if (l ~ /^round[ \t]+[0-9]+[ \t]*:[ \t]*(PASS|FAIL|SKIP-DOCS-ONLY)$/) { __n = l; sub(/^round[ \t]+/, "", __n); sub(/[ \t]*:.*$/, "", __n); __n = __n + 0; __t = l; sub(/^[^:]*:[ \t]*/, "", __t); if (__n > 2) bad = "a third round"; else if (__n != nr + 1) bad = "round " __n " out of order"; else if (nr >= 1 && (tok[1] == "SKIP-DOCS-ONLY" || __t == "SKIP-DOCS-ONLY")) bad = "SKIP-DOCS-ONLY beside another round"; else { nr = __n; tok[nr] = __t } next } if (l ~ /^verdict[ \t]*:/) { if (l !~ /^verdict[ \t]*:[ \t]*ACCEPTED-BY-HUMAN([ \t]|$)/) { bad = "a verdict line other than ACCEPTED-BY-HUMAN"; next } if (nr != 2) { bad = "ACCEPTED-BY-HUMAN outside round 2"; next } if (tok[2] != "FAIL") { bad = "ACCEPTED-BY-HUMAN beside round 2 reading " tok[2]; next } __ids = l; sub(/^verdict[ \t]*:[ \t]*ACCEPTED-BY-HUMAN[ \t]*/, "", __ids); __k = split(__ids, __a, /[ \t]+/); if (__k == 0) { bad = "ACCEPTED-BY-HUMAN names no finding"; next } for (__i = 1; __i <= __k; __i++) { if (__a[__i] !~ /^[A-Za-z0-9._-]+$/) { bad = "ACCEPTED-BY-HUMAN names something that is not a finding id"; next } acc_id[__a[__i]] = 1; acc_list = acc_list " " __a[__i] } acc = 1; next } if (nr == 0) { bad = "a line before the first round header"; next } if (tok[nr] == "SKIP-DOCS-ONLY") { bad = "a SKIP-DOCS-ONLY round that carries lines"; next } if (l ~ /^[A-Za-z0-9._-]+[ \t]*:[ \t]*(PASS|PARTIAL|FAIL)$/) { cn[nr]++; if (l ~ /FAIL$/ && cf[nr] == "") { __cn = l; sub(/[ \t]*:.*$/, "", __cn); cf[nr] = __cn } next } if (index(l, "|")) { __k = split(l, __f, "|"); if (__k < 6) { bad = "a finding line with fewer than six fields"; next } for (__i = 1; __i <= 5; __i++) { sub(/^[ \t]+/, "", __f[__i]); sub(/[ \t]+$/, "", __f[__i]) } __fx = __f[6]; for (__i = 7; __i <= __k; __i++) __fx = __fx "|" __f[__i]; sub(/^[ \t]+/, "", __fx); sub(/[ \t]+$/, "", __fx); if (__f[1] !~ /^[A-Za-z0-9._-]+$/) { bad = "a finding whose id is not a bare identifier"; next } if (__f[2] !~ /^([A-Za-z0-9._-]+|-)$/) { bad = "finding " __f[1] " names no criterion"; next } if (__f[3] !~ /^(BLOCKER|MAJOR|MINOR)$/) { bad = "finding " __f[1] " has no severity"; next } if (__f[4] !~ /^[^ \t|]+:[0-9]+$/) { bad = "finding " __f[1] " has no file and line"; next } if (__f[5] == "" || __fx == "") { bad = "finding " __f[1] " says no what or no fix"; next } __key = nr SUBSEP __f[1]; if (__key in fid) { bad = "finding " __f[1] " appears twice in round " nr; next } fid[__key] = __f[3]; if (__f[3] != "MINOR") { if (mj[nr] == "") mj[nr] = __f[1] " " __f[3]; if (nr == 2) mj2[__f[1]] = __f[3] } next } bad = "a line that is not a round header, a criterion verdict, a finding or the human verdict"; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report([ \t]+\(.*\))?[ \t]*(#+[ \t]*)?$/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) { inclose = 0; endl = NR; endh = substr(__l, 1, 60) } } } END { if (incmt) { print "unclosed-comment"; exit } if (inb) { print "unclosed"; exit } if (!seen && nin) { print "malformed the close-review fence at line " nin " opens inside a fence opened at line " ninl " (" nint ") that is not closed before it, so it is read as content of that fence"; exit } if (!seen && late) { print "malformed the close-review fence at line " late " sits after the heading \"" endh "\" at line " endl ", which ends the Closing report section; a report pasted into the Closing report goes inside a fence, where its headings are content"; exit } if (fence && !seen) { print "malformed an unclosed fence opened at line " fline " (" ftext ") runs to the end of the spec, so no block after it is read"; exit } if (!seen) { print "none"; exit } if (bad != "") { print "malformed " bad; exit } if (nr == 0) { print "empty"; exit } for (__i = 1; __i <= nr; __i++) { if (tok[__i] == "SKIP-DOCS-ONLY") continue; if (cn[__i] == 0) { print "malformed round " __i " carries no criterion verdict"; exit } if (tok[__i] == "PASS" && mj[__i] != "") { print "malformed round " __i " reads PASS beside " mj[__i]; exit } if (tok[__i] == "PASS" && cf[__i] != "") { print "malformed round " __i " reads PASS beside criterion " cf[__i] " FAIL"; exit } } if (acc) { __k = split(acc_list, __a, " "); for (__i = 1; __i <= __k; __i++) { __key = 2 SUBSEP __a[__i]; if (!(__key in fid)) { print "malformed ACCEPTED-BY-HUMAN names " __a[__i] ", which round 2 does not carry"; exit } } for (__x in mj2) if (!(__x in acc_id)) { print "malformed ACCEPTED-BY-HUMAN leaves round 2 finding " __x " " mj2[__x] " unaccepted"; exit } print "accepted"; exit } if (tok[nr] == "PASS") print "pass"; else if (tok[nr] == "FAIL") print "fail"; else print "skip" }'

# A RULE IN FORCE BY THE CLOSE'S OWN VERSION (spec 0175): the version comparison the audit's
# rule_in_force made first, shared so the gate and the audit date one rule the same way. Exit 0
# when v (a plugin version) is at least want (major.minor). An empty or unreadable version is
# not in force: the pre-rule exemption's direction, stated rather than hidden. LOCKSTEP:
# trunk-audit.sh and this file, asserted.
# fail-open-ok: every exit below is the awk program's answer (0 in force, 1 not), never the hook's.
SLH_VERSION_AT_LEAST_AWK='BEGIN { if (v !~ /^[0-9]+\.[0-9]+(\.|$)/) exit 1; split(v, a, /[.]/); split(want, w, /[.]/); if (a[1] + 0 > w[1] + 0) exit 0; if (a[1] + 0 == w[1] + 0 && a[2] + 0 >= w[2] + 0) exit 0; exit 1 }'

# A FENCED EXAMPLE IS NOT A CLOSING REPORT, and the rule is stated ONCE here
# because it now has two callers rather than one. It was assigned inside
# slh_verify_close until 2026-08-26; the value is unchanged, byte for byte, and
# the reasoning for what it strips stays at its use site in that function.
# Hoisting it is what let the lifecycle detector below become a sibling of the
# three readers that already carry it instead of a fourth private copy (A9).
#
# LOCKSTEP: byte-identical to trunk-audit.sh, asserted.
SLH_TEMPLATE_FENCE_AWK='function __f(k,  i){ if(k) for(i=1;i<=n;i++) print b[i]; n=0 } { __l=$0; sub(/\r$/,"",__l); sub(/^[[:space:]]*/,"",__l); if (incmt) { __cb[++__cn]=$0; if (index(__l, "-->")) { incmt = 0; __cn=0 } next } if (!fence && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; __cn=0; __cb[++__cn]=$0; next } __c=substr(__l,1,1); if ((__c=="`" || __c=="~") && $0 ~ /^ ? ? ?[`~]/) { __m=0; while(substr(__l,__m+1,1)==__c) __m++; __raw=substr(__l,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { if (!fence) { fence=1; fch=__c; flen=__m; n=0; t=0; b[++n]=$0; next } else if (__c==fch && __m>=flen && __r=="") { fence=0; b[++n]=$0; __f(!t); next } } } if (fence) { b[++n]=$0; if($0 ~ /^ ? ? ?#+[ \t]+Closing report/) t=1; next } print } END { if(fence) __f(!t); if(incmt) for(__ci=1;__ci<=__cn;__ci++) print __cb[__ci] }'

# A HEADING IS WHAT MARKDOWN SAYS A HEADING IS, IN THE FOURTH READER TOO
# (v1.9 leg, V19-F2). One definition, used by every reader in this file.
SLH_CLOSING_REPORT_RE=$'^ {0,3}#{1,6}[ \t]+Closing report'

# HISTORY: ruling LIB-01 (plugin 2.1.0): THE LIFECYCLE DETECTOR, MADE A SIBLING OF THE THREE READERS IT DISAGREED WITH.
slh_lifecycle_added() { # slh_lifecycle_added <proj> <states-re> <spec-path...> -> 0 when this change ADDS a live lifecycle line
  local proj="$1" states_re="$2"; shift 2
  local f live added __ldiff
  for f in "$@"; do
    [ -n "$f" ] || continue
    # A path with no index version (a deletion) has no live text, and a removed
    # Status line was never an added one. The old detector read added lines only
    # for the same reason.
    # fail-open-ok: no live lifecycle line in this spec is nothing to pair with an inventory row.
    live="$(slh_index_show "$proj" "$f" | awk "$SLH_TEMPLATE_FENCE_AWK" | grep -E "^Status:[[:space:]]*(${states_re})|${SLH_CLOSING_REPORT_RE}" || true)"
    [ -n "$live" ] || continue
    # HISTORY: ruling LIB-02 (2026-09-02): THIS READER TAKES THE SAME RENDERING THE SCANS TAKE, so it takes the same flags (RC2-2026, fixed 2026-09-02, spec 0129; the reasons are written out at pre-commit's scan site).
    if ! __ldiff="$(git -C "$proj" diff --cached --unified=0 --no-color --no-ext-diff --no-textconv -- "$f" 2>/dev/null)"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "git could not render the staged diff of $(slh_bound name "$f"), so the lifecycle detector read nothing and cannot tell whether this commit changes a spec's lifecycle state. A reader that could not run has not passed. Run git diff --cached on that path here to see the failure."
      return 1
    fi
    # fail-open-ok: a file whose staged diff adds nothing adds no lifecycle line.
    added="$(printf '%s\n' "$__ldiff" | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^+//' || true)"
    [ -n "$added" ] || continue
    # A multi-line `live` cannot be passed to grep -F as one pattern argument
    # without matching the JOINED text, so the set test is done line by line.
    while IFS= read -r __lline; do
      [ -n "$__lline" ] || continue
      if grep -qxF -- "$__lline" <<< "$added"; then return 0; fi
    done <<EOF
$live
EOF
  done
  return 1
}

# HISTORY: ruling LIB-03 (2026-08-05): CONTENT SCANNING, BOUND TO CONTENT RATHER THAN TO AN OPERATION (F1, 2026-08-05).
SLH_EMDASH="$(printf '\342\200\224')"
SLH_SECRET_RE='(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'

# HISTORY: ruling LIB-04 (undated): PATH-SCOPED SCANS: THE DECLARED EXCLUSION SET, NAMED OUT LOUD (KL4, spec 0122).
#
# 2. ABSENCE IS BYTE-IDENTICAL TO THE PRE-FEATURE BEHAVIOUR, BY CONSTRUCTION.
#    With nothing declared, slh_scan_added takes the SAME two greps over the
#    SAME input it has always taken; the scoped path is not entered at all. That
#    is deliberate: reproducing the old behaviour carefully inside the new code
#    path is how a rewrite ships a difference nobody meant, and the suite's
#    differential against the pinned pre-feature blobs would only tell us
#    afterwards.
#

# HISTORY: ruling LIB-05 (undated): The glob charset. A pattern is interpolated into a `case` pattern, which is what makes shell globbing available at all, and an unrestricted string there would be config-driven code:
SLH_SCAN_GLOB_BAD='[!A-Za-z0-9._/*?-]'

# HISTORY: ruling LIB-06 (plugin 1.0.8): The diff reader. ONE program, two modes, because the path census and the line filter must agree about what a header is:
SLH_SCAN_SCOPE_AWK='
BEGIN { if ("SLH_SCAN_EXLIST" in ENVIRON && ENVIRON["SLH_SCAN_EXLIST"] != "") { __n = split(ENVIRON["SLH_SCAN_EXLIST"], __a, "\n"); for (__i = 1; __i <= __n; __i++) if (__a[__i] != "") ex[__a[__i]] = 1 } }
{
  if ($0 ~ /^diff --git / || $0 ~ /^diff --cc /) { inhunk = 0; path = ""; known = 0; next }
  if (!inhunk && $0 ~ /^@@/) { inhunk = 1; next }
  if (!inhunk) {
    if ($0 ~ /^\+\+\+ /) {
      if ($0 ~ /^\+\+\+ b\//) { path = substr($0, 7); known = 1 }
      else if ($0 == "+++ /dev/null") { path = ""; known = 1 }
      else { path = ""; known = 0; unreadable = 1 }
    }
    next
  }
  if ($0 !~ /^\+/) next
  if (mode == "paths") {
    if (known && path != "") { if (!(path in seen)) { seen[path] = 1; print path } }
    else if (!known) unattributed = 1
    next
  }
  if (known && path != "" && (path in ex)) next
  print
}
END { if (mode == "paths" && (unreadable || unattributed)) print "\001unreadable" }
'

# HISTORY: ruling LIB-07 (undated): THE ONE READER (A9). Both layers, both scans, one implementation.
SLH_SCAN_EXCLUSIONS=""
SLH_SCAN_EXCLUSIONS_STATE=""
slh_scan_exclusions_load() { # slh_scan_exclusions_load <proj> -> 0 with SLH_SCAN_EXCLUSIONS set, 1 after refusing
  # HISTORY: ruling LIB-08 (undated): THE ENTRIES ARE PREFIXED AND COUNTED, and that is a measured correction rather than defensiveness.
  local proj="$1" raw verdict pat lit out="" declared="" seen=0
  if [ -n "$SLH_SCAN_EXCLUSIONS_STATE" ]; then
    [ "$SLH_SCAN_EXCLUSIONS_STATE" = "ok" ] && return 0
    return 1
  fi
  # HISTORY: ruling LIB-09 (undated): jq's STATUS is carried, not discarded, for the same reason slh_trunk carries it:
  if ! raw="$(jq -r '
        if (.scan_exclusions == null) then "absent"
        elif ((.scan_exclusions | type) != "array") then "shape"
        elif ([.scan_exclusions[] | select(type != "string")] | length) > 0 then "shape"
        elif ([.scan_exclusions[] | select(contains("\n") or contains("\r"))] | length) > 0 then "shape"
        else ((["ok " + (.scan_exclusions | length | tostring)]) + [.scan_exclusions[] | ">" + .] | join("\n")) end' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    SLH_SCAN_EXCLUSIONS_STATE="bad"
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading the scan exclusion set from .claude/sdd.json, so which paths this scan may skip could not be determined. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than scanning against a configuration nobody read."
    return 1
  fi
  verdict="${raw%%$'\n'*}"
  case "$verdict" in
    "ok "*) declared="${verdict#ok }" ;;
  esac
  case "$verdict" in
    ok*) verdict="ok" ;;
  esac
  case "$verdict" in
    absent)
      SLH_SCAN_EXCLUSIONS_STATE="ok"
      SLH_SCAN_EXCLUSIONS=""
      return 0
      ;;
    ok) ;;
    shape)
      SLH_SCAN_EXCLUSIONS_STATE="bad"
      slh_refuse "SLH-SCAN-EXCLUSIONS-SHAPE" ".claude/sdd.json has a \"scan_exclusions\" that is not an array of plain strings, so which paths the em-dash and secret scans may skip cannot be read. Refusing rather than guessing in either direction: scanning everything would ignore a set this project declared, and scanning nothing would turn an unreadable line into a silent exemption. Set \"scan_exclusions\" to an array of repo-relative globs, for example [\"vendor/**\"], or remove the key to scan every path."
      return 1
      ;;
    *)
      # An empty or unrecognised verdict means the reader did not read. That is
      # a refusal, never a default: this is the one place where "no evidence of
      # an exclusion" and "no exclusion" must not be conflated.
      SLH_SCAN_EXCLUSIONS_STATE="bad"
      slh_refuse "SLH-UNREADABLE-CONFIG" "the scan exclusion set in .claude/sdd.json could not be read (the reader returned no verdict), so the em-dash and secret scans have no configuration to honour. Refusing rather than scanning against an unread file."
      return 1
      ;;
  esac
  while IFS= read -r pat; do
    # An empty line here is the heredoc's own trailing newline, never an entry:
    # a real entry always carries the ">" prefix, including an empty one.
    [ -n "$pat" ] || continue
    case "$pat" in
      ">"*) pat="${pat#>}" ;;
      *)
        SLH_SCAN_EXCLUSIONS_STATE="bad"
        slh_refuse "SLH-UNREADABLE-CONFIG" "the scan exclusion set in .claude/sdd.json was read in a form this hook does not recognise, so which paths the scans may skip is not established. Refusing rather than proceeding on a partial read."
        return 1
        ;;
    esac
    seen=$((seen + 1))
    # HISTORY: ruling LIB-10 (undated): NORMALISED, NOT USED RAW, and normalised the way role paths already are in this file.
    pat="$(printf '%s' "$pat" | tr -s '/')"
    pat="${pat#/}"
    while [ "${pat#./}" != "$pat" ]; do pat="${pat#./}"; done
    while [ "${pat%/}" != "$pat" ]; do pat="${pat%/}"; done
    case "$pat" in
      *$SLH_SCAN_GLOB_BAD*)
        SLH_SCAN_EXCLUSIONS_STATE="bad"
        slh_refuse "SLH-SCAN-EXCLUSION-INVALID" ".claude/sdd.json declares a scan exclusion containing a character a repo-relative path glob does not use. A glob here is letters, digits and . _ - / * ?; anything else is refused rather than sanitised, because these patterns are matched as shell globs and a value carrying shell syntax would be configuration deciding what this hook runs. A path that needs one of those characters cannot be excluded and will be scanned."
        return 1
        ;;
    esac
    case "/$pat/" in
      *//*|*/./*|*/../*)
        SLH_SCAN_EXCLUSIONS_STATE="bad"
        slh_refuse "SLH-SCAN-EXCLUSION-INVALID" ".claude/sdd.json declares a scan exclusion that is empty, or that contains a . or .. path segment. Git paths are repo-relative and carry neither, so such a pattern can never match anything: it would sit in the config reading as coverage while excluding nothing. Write the path as git records it, for example \"vendor/**\"."
        return 1
        ;;
    esac
    # HISTORY: ruling LIB-11 (undated): A PATTERN MUST NAME SOMETHING.
    lit="$(printf '%s' "$pat" | tr -d '*?/')"
    if [ -z "$lit" ]; then
      SLH_SCAN_EXCLUSIONS_STATE="bad"
      slh_refuse "SLH-SCAN-EXCLUSION-CATCHALL" ".claude/sdd.json declares a scan exclusion made only of wildcards, which matches every path in the repository and would switch the em-dash and secret scans off entirely while looking like a scoping decision. The exclusion set scopes these scans to make foreign content committable; it is not an off switch. Name the tree you mean, for example \"vendor/**\"."
      return 1
    fi
    out="$out$pat
"
  done <<EOF
$(printf '%s\n' "$raw" | tail -n +2)
EOF
  # HISTORY: ruling LIB-12 (undated): THE COUNT IS ASSERTED BEFORE THE SET IS USED.
  if [ -n "$declared" ] && [ "$seen" != "$declared" ]; then
    SLH_SCAN_EXCLUSIONS_STATE="bad"
    slh_refuse "SLH-SCAN-EXCLUSIONS-SHAPE" ".claude/sdd.json declares $declared scan exclusions but this hook read $seen of them, so the set it would honour is not the set the file records. Refusing rather than scanning against a partial read of a configuration."
    return 1
  fi
  SLH_SCAN_EXCLUSIONS="$out"
  SLH_SCAN_EXCLUSIONS_STATE="ok"
  return 0
}

# slh_path_excluded <path> <globs> -> prints the glob that matched, or nothing.
# `$g` is deliberately unquoted: that is the glob match. The charset check in the
# reader above is what makes it safe, and the two belong together.
slh_path_excluded() { # slh_path_excluded <path> <globs>
  local p="$1" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    # shellcheck disable=SC2254  # The unquoted expansion IS the mechanism: these
    # patterns are declared globs and quoting them would match them literally, so
    # "vendor/**" would exclude a file actually named `vendor/**` and nothing else.
    # What makes it safe is not quoting but the CHARSET check in the reader above,
    # which refuses any pattern outside [A-Za-z0-9._/*?-] before it ever reaches
    # here: without that, a value carrying `)` or `;` would be configuration
    # deciding what this hook runs. The two belong together and neither is
    # sufficient alone.
    case "$p" in
      $g|$g/*) printf '%s' "$g"; return 0 ;;
    esac
  done <<EOF
$2
EOF
  return 1
}

# HISTORY: ruling LIB-13 (undated): The scoped filter. Announcements go to STDERR from inside here on purpose:
slh_scan_scoped_added() { # slh_scan_scoped_added <diff-text> <globs> <what-it-is>
  local diff_text="$1" globs="$2" where="$3" paths p g ex=""
  # HISTORY: ruling LIB-14 (undated): EVERY AWK STAGE CARRIES ITS OWN STATUS.
  paths="$(printf '%s\n' "$diff_text" | LC_ALL=C awk -v mode=paths "$SLH_SCAN_SCOPE_AWK")" || return 2
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$p" = "$(printf '\001unreadable')" ]; then
      printf 'setlist [SLH-SCAN-PATH-UNREADABLE]: %s: at least one file path could not be read from the diff header (git quotes paths carrying non-ASCII or control characters), so its added lines were SCANNED rather than matched against the exclusion set. That is the safe direction and it is reported rather than assumed.\n' "$where" >&2
      continue
    fi
    g="$(slh_path_excluded "$p" "$globs")" || continue
    ex="$ex$p
"
    printf 'setlist [SLH-SCAN-EXCLUDED]: %s: %s was NOT scanned (matched "%s" in .claude/sdd.json scan_exclusions). Nothing in that file was read by the em-dash or secret scan.\n' "$where" "$(slh_bound name "$p")" "$g" >&2
  done <<EOF
$paths
EOF
  printf '%s\n' "$diff_text" | SLH_SCAN_EXLIST="$ex" LC_ALL=C awk -v mode=filter "$SLH_SCAN_SCOPE_AWK"
}

# HISTORY: ruling LIB-15 (plugin v1.7): slh_scan_added <proj> <diff-text> <what-it-is> Reads a unified diff and refuses on added lines only, so pre-existing content is never re-judged by a later layer.
slh_rows_newly_closed() {
  local status_new="$1" status_old="$2" num
  printf '%s\n' "$status_new" | sed 's/\\|/ /g' | awk -F'|' 'NF >= 5 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^[0-9]+[a-z]*$/) print $2 }' | while IFS= read -r num; do  # sed: GFM escaped pipe is literal, not a field separator (round 11)
    [ -n "$num" ] || continue
    if slh_row_closed "$status_new" "$num" && ! slh_row_closed "$status_old" "$num"; then
      printf '%s\n' "$num"
    fi
  done
}

# slh_spec_path_for <proj> <num> -> the spec file for a number, read from the
# INDEX, for the case where a row flipped without the file being staged.
slh_spec_path_for() {
  local proj="$1" num="$2" hits n
  # HISTORY: ruling LIB-16 (undated): EXACT NUMBER, THEN A HYPHEN (leg F6 and its second half).
  hits="$(git -C "$proj" ls-files "specs/${num}-*.md" 2>/dev/null)"
  [ -n "$hits" ] || return 0
  n="$(printf '%s\n' "$hits" | grep -c .)"
  # A pick among several is a guess. Report nothing and let the caller refuse,
  # rather than return the alphabetically first and call it the spec.
  [ "$n" -eq 1 ] || return 0
  printf '%s\n' "$hits"
}

# HISTORY: ruling LIB-17 (undated): THE HEADER STRIP IS POSITIONAL, AND TWO SHAPE-BASED ATTEMPTS PRECEDED IT.
#
# It was `grep -vE '^\+\+\+'`, which dropped the diff's own `+++ b/path` line
# and also dropped any ADDED line whose content began `++` (SC sub-hole 6).
# That was tightened to an anchored `^\+\+\+ (b/|/dev/null)`, which was the
# right direction and the wrong instrument, and the 2.3.0 leg found the
# residue as F3: a unified diff prefixes every added line with ONE `+`, so an
# added line whose content begins `++ b/` arrives as `+++ b/...` and is
# BYTE-IDENTICAL to a header. No pattern over a single line can separate two
# things that have the same shape. A secret on such a line passed both layers
# at rc=0, in silence.
#
SLH_ADDED_AWK='
{
  if ($0 ~ /^diff --git / || $0 ~ /^diff --cc /) { inhunk = 0; next }
  if (!inhunk && $0 ~ /^@@/) { inhunk = 1; next }
  if (!inhunk) next
  if ($0 ~ /^\+/) print
}'


# BYTES, NOT CHARACTERS (spec 0164, 2026-09-22). Every awk and grep stage of the
# content scans runs under LC_ALL=C. Under a UTF-8 locale the macOS system awk
# (BWK) aborts on an added line holding a byte that is not valid UTF-8, the scan
# fails closed, and a Latin-1 file was refused at commit, merge and push for
# being unreadable rather than for anything in it. Both patterns are bytes
# already: the em-dash is its three UTF-8 bytes and the secret pattern is ASCII,
# so the C locale reads them exactly and loses nothing a person would call a
# match. SLH_SCAN_CONTENT_REFUSED records that a refusal was about the content,
# so pre-push says "fix the content" only when that is true.
# shellcheck disable=SC2034 # read by pre-push, which sources this file
SLH_SCAN_CONTENT_REFUSED=0

slh_scan_added() {
  local proj="$1" diff_text="$2" where="$3" added
  # HISTORY: ruling LIB-18 (undated): The exclusion set is read ONCE per hook run and refuses for the whole run if it cannot be read.
  if ! slh_scan_exclusions_load "$proj"; then
    SLH_REFUSED=1
    return 1
  fi
  if [ -z "$SLH_SCAN_EXCLUSIONS" ]; then
    # HISTORY: ruling LIB-19 (undated): NOTHING DECLARED: the pre-feature path, entered verbatim rather than reproduced.
    if ! added="$(printf '%s\n' "$diff_text" | LC_ALL=C awk "$SLH_ADDED_AWK")"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "the scan of $where could not read the change, so it read nothing and has judged nothing. A scan that could not run has not passed. Check 'awk --version'."
      return 1
    fi
  else
    # NOT fail-open-ok, and deliberately the only branch here that is not: the
    # scoped filter can FAIL, and a failed filter prints nothing, which the
    # emptiness test below would read as a clean diff. A scan that could not run
    # has not passed.
    if ! added="$(slh_scan_scoped_added "$diff_text" "$SLH_SCAN_EXCLUSIONS" "$where")"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "the path-scoped scan of $where could not read the change, so it read nothing and has judged nothing. A scan that could not run has not passed. This points at the toolchain rather than at the content: check 'awk --version'. Remove \"scan_exclusions\" from .claude/sdd.json to fall back to scanning every path."
      return 1
    fi
  fi
  [ -n "$added" ] || return 0
  # shellcheck disable=SC2034 # the flag is read by pre-push, which sources this file
  if LC_ALL=C grep -q "$SLH_EMDASH" <<< "$added"; then
    slh_refuse "SLH-EMDASH" "$where contains an em-dash; replace it with a comma, colon, parentheses, or separate sentences."
    SLH_SCAN_CONTENT_REFUSED=1
  fi
  # shellcheck disable=SC2034 # the flag is read by pre-push, which sources this file
  if LC_ALL=C grep -qiE "$SLH_SECRET_RE" <<< "$added"; then
    slh_refuse "SLH-SECRET" "$where contains a secret-shaped string; move the value to the environment, reference it, and stage .env.example instead."
    SLH_SCAN_CONTENT_REFUSED=1
  fi
}

# The chore completion rule (Part 5b's archive line). LOCKSTEP: trunk-audit.sh and
# this file. DONE is the first token after the chore's colon, so it is a FIELD and
# not a word in a sentence: "this is done once CHORE-007 lands" must not count, for
# the same reason an ACTIVE spec's note mentioning another spec's closure must not
# satisfy the status check (leg 5, F8).
SLH_CHORE_DONE_RE='^[-*+>[:space:]]*(CHORE-[0-9]+)[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)'

# HISTORY: ruling LIB-20 (undated): LIVE TEXT ONLY (2026-08 consolidation, blocker F2).
#
# LOCKSTEP: byte-identical to trunk-audit.sh. NEW function, not an edit
# to the frozen QA_PASS1_AWK/TEMPLATE_FENCE_AWK (dogfood/QA-READER-FREEZE.md):
# those exist to find a specific block and must keep real content they are not
# stripping FOR; this one exists to delete anything that is not live prose before
# a plain grep runs over what remains, and needs none of that block-finding state.
SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } if ((__d>0 || __peeled) && __ic ~ /^[[:space:]]*[|]/) next; print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

SLH_REFUSED=0

# HISTORY: ruling LIB-21 (undated): Set to 1 by a CALLER (pre-commit's squash-landing branch) before slh_verify_close when the commit being verified will have a SINGLE parent:
SLH_CLOSE_SINGLE_PARENT=0

# HISTORY: ruling LIB-22 (plugin 2.6.0): slh_scan_walk <proj> <what-it-is> <rev-list-arg...> -> 0, or 1 after recording a refusal.
# TEXT PAST THE ATTRIBUTE (spec 0173, item 5; the validator's E-h, option 1). The scans read
# git's diff, a RENDERING the repository controls, and a .gitattributes entry marking a path
# `-diff` or `binary` made git print "Binary files differ" for it: a live-shaped secret reached a
# remote at exit 0 by the ordinary commit-and-push path (measured, and on the list since 1.1.0).
# `git diff --text` renders such a path, but applied to EVERY path it also feeds real binaries to
# the em-dash scan, and this repository's own publish/demo.gif carries one em-dash byte triple
# (measured), so the blanket flag would refuse an ordinary asset. So only the paths the plain
# rendering reported as binary are asked about, and only those whose NEW blob passes git's own
# text test (no NUL byte in its first 8,000 bytes) are re-rendered with --text and scanned: an
# attribute can no longer hide text, and a real binary stays unread. Prints the extra diff text
# (possibly nothing) for the caller to hand to slh_scan_added with its own rendering.
#   slh_scan_text_past_attributes <proj> cached [<rev>]   the index against <rev> (none: git's default)
#   slh_scan_text_past_attributes <proj> commit <c>       one non-merge commit against its parent
# A merge commit's combined diff (--cc) prints "Binary files differ" under --text as well (git
# 2.55.0, measured), so the push walk does not ask it; that residue is named in Known limitations.
slh_scan_text_past_attributes() { # slh_scan_text_past_attributes <proj> <cached|commit> [<rev>]
  local proj="$1" kind="$2" rev="${3:-}" rec path head nul
  local -a numstat_cmd diff_cmd
  case "$kind" in
    cached) numstat_cmd=(diff --cached --numstat -z --no-ext-diff --no-textconv ${rev:+"$rev"})
            diff_cmd=(diff --cached --text --unified=0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ ${rev:+"$rev"}) ;;
    commit) numstat_cmd=(show --root --numstat -z --format= --no-ext-diff --no-textconv "$rev")
            diff_cmd=(show --root --text --unified=0 --format=%n --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ "$rev") ;;
    *) return 0 ;;
  esac
  while IFS= read -r -d '' rec; do
    case "$rec" in -$'\t'-$'\t'*) ;; *) continue ;; esac
    path="${rec#-$'\t'-$'\t'}"
    [ -n "$path" ] || continue
    if [ "$kind" = "cached" ]; then
      git -C "$proj" cat-file -e ":$path" 2>/dev/null || continue
      head="$(git -C "$proj" show ":$path" 2>/dev/null | head -c 8000 | od -An -c | grep -c '\\0' || true)" # fail-open-ok: an unreadable blob reads as holding no NUL, so it is rendered and scanned, the stricter direction
    else
      git -C "$proj" cat-file -e "$rev:$path" 2>/dev/null || continue
      head="$(git -C "$proj" show "$rev:$path" 2>/dev/null | head -c 8000 | od -An -c | grep -c '\\0' || true)" # fail-open-ok: as above
    fi
    nul="${head:-0}"
    [ "$nul" = "0" ] || continue
    git -C "$proj" "${diff_cmd[@]}" -- "$path" 2>/dev/null || true # fail-open-ok: a path git cannot render with --text adds nothing, and the plain rendering already had its say
  done < <(git -C "$proj" "${numstat_cmd[@]}" 2>/dev/null)
  return 0
}

slh_scan_walk() { # slh_scan_walk <proj> <what-it-is> <rev-list-arg...>
  local proj="$1" what="$2"; shift 2
  local c revs rc __DIFF
  revs="$(git -C "$proj" rev-list "$@" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" != "0" ]; then
    slh_refuse "SLH-SCAN-UNREADABLE-RANGE" "the push-time scan could not enumerate the commits for $what, so it read nothing. A scan that could not run has not passed."
    return 1
  fi
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # HISTORY: ruling LIB-23 (2026-09-02): The flags ignore the repository's own diff configuration (RC2-2026, fixed 2026-09-02, spec 0129; the reasons are at pre-commit's scan site), plus --root, which is this site's own member:
    if ! __DIFF="$(git -C "$proj" show --root --unified=0 --cc --format=%n --no-color --no-ext-diff --no-textconv \
                        --src-prefix=a/ --dst-prefix=b/ "$c" 2>/dev/null)"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "git could not render commit $c for $what, so the push-time scan read nothing and has judged nothing. A scan that could not run has not passed. Run 'git show $c' here to see the failure (a configuration value git cannot parse, or a diff driver that fails, looks like this)."
      return 1
    fi
    # Text past a -diff or binary attribute (spec 0173, item 5), for a commit with one parent
    # or none: a merge's combined diff does not render past the attribute even under --text.
    if [ "$(git -C "$proj" rev-list --parents -n1 "$c" 2>/dev/null | wc -w)" -le 2 ]; then
      __DIFF="$__DIFF
$(slh_scan_text_past_attributes "$proj" commit "$c")"
    fi
    slh_scan_added "$proj" "$__DIFF" "$what ($c)"
  done <<EOF
$revs
EOF
  return 0
}

slh_refuse() { # slh_refuse <code> <message...>
  local code="$1"; shift
  printf 'setlist [%s]: %s\n' "$code" "$*" >&2
  SLH_REFUSED=1
}

# Is this repository a framework instance at all? A repo with no sdd.json is
# somebody else's repo and none of our business.
slh_is_instance() { [ -f "$1/.claude/sdd.json" ]; }

# THE CONFIGURATION THIS RUN READS (spec 0173, item 1: the checkout switch, at push).
# Every reader of .claude/sdd.json in this library asks slh_sdd for the file, so the
# hooks read ONE configuration however many readers they run. It is the working
# tree's file, as it has always been, unless the hook set SLH_SDD: pre-push does,
# when the checked-out branch carries no .claude/sdd.json and a pushed tip does, to
# a private copy of THAT commit's file, so a push of governed history is governed by
# the history's own configuration whatever is checked out. The variable is emptied
# here, when the library loads, so the environment cannot choose it: only a hook's
# own code, after sourcing, can.
SLH_SDD=""
slh_sdd() { printf '%s' "${SLH_SDD:-$1/.claude/sdd.json}"; } # slh_sdd <proj> -> the configuration file to read
# Inside this file each reader spells the expansion itself, "${SLH_SDD:-$proj/.claude/sdd.json}",
# rather than calling slh_sdd in a command substitution: the same bytes, without a
# process for each read (spec 0179, O-13, where a fork costs tens of milliseconds).

# HISTORY: ruling LIB-24 (plugin v1.12): THE STRUCTURED STATUS RECORD (RP1, edition v1.12).
#
# THE SWITCH IS THE PRESENCE OF THE FILE, per tree. Absent: the instance is a
# legacy instance and every reader takes the page path below, byte-identical,
# frozen awk readers and all (proven by the pre-record differential in the
# suite, not asserted). Present: these readers are authoritative for inventory,
# chore and close facts, and the page readers do not run; there is no mixed
# mode, because mixed mode is two readers per fact, which is the A9 violation
# that makes drift invisible.
#
#
# LOCKSTEP: the seven SLH_RECORD_*_JQ assignments below are byte-identical in
# this file and scripts/trunk-audit.sh, asserted
# by the suite exactly as the three frozen awk readers are. The frozen readers
# themselves are RETAINED byte-identical as the permanent absence path, never
# repaired and never removed (both freeze documents name that role).
SLH_RECORD_CHECK_JQ='if (type != "object") or (.setlist_status != 1) or (((keys - ["setlist_status","specs","chores"]) | length) > 0) or (((.specs // {}) | type) != "object") or (((.chores // {}) | type) != "object") then "malformed" elif (((.specs // {}) | to_entries | all((.key | test("^[0-9]+[a-z]*$")) and (.value | if type != "object" then false else (((keys - ["status","qa_pass_1","diagram"]) | length) == 0) and (.status as $s | (["draft","queued","active","revised","built","parked","closed"] | index($s)) != null) and ((.qa_pass_1 == null) or (.qa_pass_1 == "ok")) and ((.diagram == null) or (.diagram == "updated") or (.diagram == "no-impact")) end))) | not) then "malformed" elif (((.chores // {}) | to_entries | all((.key | test("^CHORE-[0-9]+$")) and (.value | if type != "object" then false else (((keys - ["status","files"]) | length) == 0) and ((.status == "open") or (.status == "done")) and ((.files == null) or (((.files | type) == "array") and (.files | all(type == "string")))) end))) | not) then "malformed" else "ok" end'
SLH_RECORD_CLOSED_JQ='((.specs // {}) | to_entries[] | select(.value.status == "closed") | .key)'
SLH_RECORD_ACTIVE_JQ='((.specs // {}) | to_entries[] | select(.value.status == "active") | .key)'
SLH_RECORD_DONE_JQ='((.chores // {}) | to_entries[] | select(.value.status == "done") | .key)'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_STATUS_JQ='((.specs // {})[$num]) | if . == null then "absent" else .status end'
SLH_RECORD_FACTS_JQ='((.specs // {})[$num]) | if . == null then "absent" elif ((.status == "closed") and (.qa_pass_1 == "ok") and ((.diagram == "updated") or (.diagram == "no-impact"))) then "ok" else "missing" end'
SLH_RECORD_CHORE_FILES_JQ='(((.chores // {})[$id].files) // []) | .[]'

# THE OWNERSHIP FACT (RP1, design section 8): `Owns:` header lines inside the
# spec's HASHED RANGE (first line to the line before "## Closing report", the
# same boundary scripts/spec-hash.sh cuts, so declared attestation custody
# signs the declaration). Grammar: `Owns: ` at column 0, ONE verbatim
# repo-relative path, no globs, no quoting, no directories, because a declared
# set you cannot enumerate is an exemption wearing a declaration. The reader
# prints paths, or lines starting with "!" for anything outside the grammar
# (out of range, wrong shape), and the consumer REFUSES on any "!" token.
# LOCKSTEP: byte-identical to scripts/trunk-audit.sh, whose single-parent arm
# asks the same question of the pushed history.
SLH_OWNS_AWK='{ l=$0; sub(/\r$/,"",l) } l ~ /^##[[:space:]]*Closing report/{r=1} r!=1 && l=="Tier: lite"{t=1} l ~ /^Owns:/{ if(r==1){print "!range";next} if(substr(l,1,6) != "Owns: "){print "!shape";next} p=substr(l,7); if(p=="" || p ~ /^[ \t]/ || p ~ /[ \t]$/ || index(p,"*") || index(p,"?") || index(p,"[") || index(p,"]") || index(p,"\\") || index(p,"\"") || index(p,"\047") || substr(p,1,1)=="/" || substr(p,1,2)=="./" || substr(p,length(p),1)=="/" || p ~ /(^|\/)\.\.(\/|$)/){print "!shape";next} n++; print p } END{ if(t && n>5) print "!lite-oversized" }'

slh_record_present() { # slh_record_present <proj> <rev>  ("" means the index)
  if [ -z "$2" ]; then
    [ -n "$(git -C "$1" ls-files --cached -- .claude/status.json 2>/dev/null)" ]
  else
    git -C "$1" cat-file -e "$2:.claude/status.json" 2>/dev/null
  fi
}

slh_record_show() { # slh_record_show <proj> <rev>  ("" means the index)
  # fail-open-ok: an unreadable-but-present record yields empty text, and empty
  # text is not "ok" to slh_record_verdict, so every consumer refuses it.
  if [ -z "$2" ]; then
    git -C "$1" show ":.claude/status.json" 2>/dev/null || true # fail-open-ok: empty is not "ok" to the verdict reader, so every consumer refuses it
  else
    git -C "$1" show "$2:.claude/status.json" 2>/dev/null || true # fail-open-ok: same as above, an unreadable record refuses at the caller
  fi
}

slh_record_verdict() { # slh_record_verdict <record-text> -> ONE TOKEN: ok | malformed
  # The jq exit status is carried, not discarded: a jq that exists and fails
  # while reading the record is a refusal (SLH-RECORD-MALFORMED at the caller),
  # never a silent pass and never a fallback.
  printf '%s' "$1" | jq -r "$SLH_RECORD_CHECK_JQ" 2>/dev/null || printf 'malformed'
}

# The query readers below run ONLY on a record slh_record_verdict already
# passed; each still carries jq's exit status so a mid-query failure reaches
# the caller as a refusal rather than as an empty (and therefore quieter) set.
slh_record_closed() { printf '%s' "$1" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null; }
slh_record_done()   { printf '%s' "$1" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null; }
slh_record_facts()  { printf '%s' "$1" | jq -r --arg num "$2" "$SLH_RECORD_FACTS_JQ" 2>/dev/null; }

# The one place the "which specs are ACTIVE" question switches between the
# record and the page, used by pre-commit's attestation arm. The page half is
# the same reading slh_attest_walk's legacy path performs.
slh_active_specs() { # slh_active_specs <proj> <rev-or-""-for-index> -> active spec numbers; refuses and returns 1 on a malformed record
  local proj="$1" rev="$2" rec
  if slh_record_present "$proj" "$rev"; then
    rec="$(slh_record_show "$proj" "$rev")"
    if [ "$(slh_record_verdict "$rec")" != "ok" ]; then
      slh_refuse "SLH-RECORD-MALFORMED" ".claude/status.json is present and is not a well-formed status record, so which spec is active cannot be read from it. Nothing falls back to the STATUS.md page, because a fallback would let one syntax error buy back the frozen page readers' residual class. Fix the record (jq . .claude/status.json shows the syntax; Part 3 of the edition shows the grammar), or restore it from HEAD."
      return 1
    fi
    printf '%s' "$rec" | jq -r "$SLH_RECORD_ACTIVE_JQ" 2>/dev/null || {
      slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading .claude/status.json, so which spec is active cannot be established. A reader that could not run has not read; refusing rather than treating the failure as an empty set."
      return 1
    }
  else
    if [ -z "$rev" ]; then
      slh_attest_active_specs "$(slh_index_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
    else
      slh_attest_active_specs "$(git -C "$proj" show "$rev:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK")"
    fi
  fi
}

# HISTORY: ruling LIB-25 (plugin v1.7): THE TOOLS THIS FILE RUNS ON MUST ACTUALLY WORK (v1.7 gate, adversarial review F2).
slh_require_toolchain() { # slh_require_toolchain
  local probe
  probe="$(printf 'x\n' | awk '{ print }' 2>/dev/null)" || probe=""
  if [ "$probe" != "x" ]; then
    slh_refuse "SLH-NO-TOOLCHAIN" "awk is installed but does not work here, so the close verification cannot read the spec and would otherwise let this through unchecked. Run 'awk --version' to see the failure. Hooks fail closed by design."
    return 1
  fi
  probe="$(printf 'x\n' | sed 's/x/y/' 2>/dev/null)" || probe=""
  if [ "$probe" != "y" ]; then
    slh_refuse "SLH-NO-TOOLCHAIN" "sed is installed but does not work here, so the close verification cannot read the spec and would otherwise let this through unchecked. Run 'sed --version' to see the failure. Hooks fail closed by design."
    return 1
  fi
  probe="$(printf 'x\n' | tr 'x' 'y' 2>/dev/null)" || probe=""
  if [ "$probe" != "y" ]; then
    slh_refuse "SLH-NO-TOOLCHAIN" "tr is installed but does not work here, so the close verification cannot read the spec and would otherwise let this through unchecked. Run 'tr --version' to see the failure. Hooks fail closed by design."
    return 1
  fi
  probe="$(printf 'x\n' | grep -E '^x$' 2>/dev/null)" || probe=""
  if [ "$probe" != "x" ]; then
    slh_refuse "SLH-NO-TOOLCHAIN" "grep is installed but does not work here, so the close verification cannot read the spec and would otherwise let this through unchecked. Run 'grep --version' to see the failure. Hooks fail closed by design."
    return 1
  fi
  # HISTORY: ruling LIB-26 (plugin 2.4.0): jq, RUN and its OUTPUT compared (spec 0130, KL6's join).
  if command -v jq >/dev/null 2>&1; then
    probe="$(printf '{"probe":"x"}\n' | jq -r '.probe' 2>/dev/null)" || probe=""
    if [ "$probe" != "x" ]; then
      slh_refuse "SLH-JQ-BROKEN" "jq is installed but does not work here: run on a one-key document it did not print the value back (it exited nonzero, or exited 0 and printed nothing). Every reader of .claude/sdd.json in this layer needs jq, so nothing below can be trusted and this refuses before reading anything. Run 'jq --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem. Hooks fail closed by design."
      return 1
    fi
  fi
  return 0
}

# HISTORY: ruling LIB-27 (plugin v1.7): The trunk name. Mirrors close-gate.sh, including the refusal on a present-but-invalid value:
slh_trunk() { # slh_trunk <proj>  -> prints the REDUCED trunk, or refuses
  local proj="$1" v full cand
  if ! command -v jq >/dev/null 2>&1; then
    slh_refuse "SLH-NO-JQ" "jq is required to read .claude/sdd.json and is not installed. Refusing rather than assuming a trunk: a gate that cannot read its own configuration has not passed."
    return 1
  fi
  # The exit status is carried, not discarded. A jq that EXISTS and fails (a
  # broken link, an OOM kill, the wrong architecture) would otherwise yield an
  # empty string indistinguishable from a legitimate absent key.
  if ! v="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading .claude/sdd.json, so the trunk could not be determined. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than defaulting."
    return 1
  fi
  if [ -z "$v" ]; then
    slh_refuse "SLH-TRUNK-INVALID" ".claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."
    return 1
  fi

  # HISTORY: ruling LIB-28 (undated): THE VALUE MUST NAME A LOCAL BRANCH.
  if ! git -C "$proj" show-ref --verify --quiet "refs/heads/$v" 2>/dev/null; then
    # fail-open-ok: an unresolvable spelling leaves `full` empty, the case below
    # matches nothing, and the show-ref test then REFUSES. Empty routes to a
    # refusal here, never to a pass.
    full="$(git -C "$proj" rev-parse --symbolic-full-name "$v" 2>/dev/null || true)"
    case "$full" in
      refs/heads/*)
        v="${full#refs/heads/}"
        ;;
      refs/remotes/*)
        cand="${full#refs/remotes/}"
        cand="${cand#*/}"
        if git -C "$proj" show-ref --verify --quiet "refs/heads/$cand" 2>/dev/null; then
          v="$cand"
        fi
        ;;
    esac
    # The guard only bites once the repository HAS local branches, so a freshly
    # initialised scaffold sitting on an unborn branch is not refused for the
    # crime of being new.
    if ! git -C "$proj" show-ref --verify --quiet "refs/heads/$v" 2>/dev/null \
       && [ -n "$(git -C "$proj" for-each-ref --count=1 refs/heads 2>/dev/null)" ]; then
      slh_refuse "SLH-TRUNK-NOT-A-BRANCH" ".claude/sdd.json records trunk $(slh_bound name "$v"), which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which names a remote-tracking ref rather than a local branch."
      return 1
    fi
  fi

  # HISTORY: ruling LIB-29 (undated): AND THE CASE-VARIANT SPELLING, which is the same class one more time.
  v="$(slh_canonical_branch "$proj" "$v")"

  printf '%s' "$v"
}

# The role paths (src, tests, ...) this project declares. Feature code lives
# under these; docs, specs and journals do not.
slh_role_paths() { # slh_role_paths <proj>
  local proj="$1"
  # HISTORY: ruling LIB-30 (plugin 1.1.0): THE SHAPE, WHICH THIS READER ALONE DID NOT CHECK (1.1.0 final leg, F13).
  local shape
  if ! shape="$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading the role paths from .claude/sdd.json. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than treating an unreadable config as a project with no feature code."
    return 1
  fi
  if [ "$shape" = "bad" ]; then
    slh_refuse "SLH-ROLES-SHAPE" ".claude/sdd.json has a \"roles\" value that is not an object, so the role paths this hook guards cannot be read and unreviewed feature code would reach the trunk unchallenged. Set \"roles\" to an object such as {\"src\": \"src\", \"tests\": \"tests\"}, or remove the key to accept the defaults."
    return 1
  fi
  # The trailing `|| true` below: grep exits non-zero when it filters everything
  # out, which means this project declared NO role paths. Stated plainly, because
  # the direction is permissive: with no roles, `carries_code` stays 0 and the
  # closes-no-spec refusal cannot fire. That is a statement the project made in
  # its own sdd.json, not an error being swallowed, and every close-condition
  # check still runs for any spec this commit does close. jq itself is probed in
  # slh_trunk, which refuses before this line is ever reached.
  # fail-open-ok: no declared role paths, so there is no feature code to detect.
  # A GLOB IN A ROLE VALUE IS REFUSED AT READ TIME (spec 0164, fix round 2, F3
  # of the 2.10.0 leg). The readers of this list disagreed about it: the close
  # verification expanded it against the working directory (an unquoted `for`),
  # while the trunk audit matched it literally, so `packages/*` made a merge
  # read clean at push and `*` refused a docs-only merge. One spelling, two
  # answers, is the shape A9 exists to refuse; the honest reading is that a
  # glob is not a path this layer can decide by, so it is refused by the code
  # that already names a roles value this hook cannot use.
  local __roles_raw __r
  __roles_raw="$(jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null \
    | grep -v '^$' | grep -v '^\.$' || true)" # fail-open-ok: no declared role paths, the pre-feature path this reader has always taken (the comment above)
  while IFS= read -r __r; do
    [ -n "$__r" ] || continue
    case "$__r" in
      *'*'*|*'?'*|*'['*)
        slh_refuse "SLH-ROLES-SHAPE" ".claude/sdd.json declares the role path $(slh_bound name "$__r"), which carries a glob character (* ? [). The layers that read this list would not agree about it: the close verification would expand it against the working directory while the push-time audit matches it literally, so one spelling would mean two different sets and work could reach the trunk unchallenged. Name the directory itself, one role per path."
        return 1 ;;
    esac
    # A `..` SEGMENT IS REFUSED THE SAME WAY (spec 0169, L2 F10 of the 2.10.0
    # cycle): git's paths never carry one, so such a role matched nothing in
    # any reader and guarded nothing, silently, while the stage refused the
    # same spelling where it is written. It is never collapsed: `src/..` is
    # not a role this layer can decide by, whatever it would collapse to.
    case "/$__r/" in
      */../*)
        slh_refuse "SLH-ROLES-SHAPE" ".claude/sdd.json declares the role path $(slh_bound name "$__r"), which has a .. segment. Git records no path with one, so the role would match nothing at any layer and the work under it would reach the trunk unchallenged, with nothing said. Name the directory itself by its path from the repository root."
        return 1 ;;
    esac
    # AND A `.` SEGMENT (spec 0180, fix round 2, the 2.11.0 leg's F8), which git's paths
    # never carry either: `src/./` guarded nothing at all three readers, in silence. A
    # LEADING ./ is not one: every reader drops it, and ./src guards as src does.
    __rt="$__r"; while [ "${__rt#./}" != "$__rt" ]; do __rt="${__rt#./}"; done
    case "/$__rt/" in
      */./*)
        slh_refuse "SLH-ROLES-SHAPE" ".claude/sdd.json declares the role path $(slh_bound name "$__r"), which has a . segment after its start. Git records no path with one, so the role would match nothing at any layer and the work under it would reach the trunk unchallenged, with nothing said. Name the directory itself by its path from the repository root."
        return 1 ;;
    esac
  done <<EOF
$__roles_raw
EOF
  printf '%s\n' "$__roles_raw" | grep -v '^$' || true # fail-open-ok: grep exits non-zero when the list is empty, which is the no-roles case the caller reads as no feature code
}

# The one normalisation every reader of a role path uses (spec 0164, fix round
# 2, F8): leading ./ segments dropped, runs of / collapsed, a leading and a
# trailing / removed. It was written out at three sites and forgotten at a
# fourth (the attestation trigger), where `src/` then matched nothing and the
# requirement fell silent.
slh_role_norm() { # slh_role_norm <role> -> the comparable path, empty when there is none
  local rp="$1"
  local ds=// s=/ # runs of / squeezed in the shell, not by tr (spec 0179, O-13)
  while [ "${rp#./}" != "$rp" ]; do rp="${rp#./}"; done
  while [ "${rp#*//}" != "$rp" ]; do rp="${rp//$ds/$s}"; done
  rp="${rp#/}"
  rp="${rp%/}"
  [ "$rp" = "." ] && rp=""
  printf '%s' "$rp"
}

# HISTORY: ruling LIB-31 (plugin v1.7): A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 adversarial review, second run).
slh_canonical_branch() { # slh_canonical_branch <proj> <name> -> stored spelling
  local proj="$1" name="$2" ci
  [ -n "$name" ] || return 0
  if git -C "$proj" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
     | grep -qxF -- "$name"; then
    printf '%s' "$name"; return 0
  fi
  # The name reaches awk through ENVIRON, not -v (spec 0169, sweep A.3.4): -v
  # reads escapes, and BWK awk's error for a name holding a newline echoed the
  # recorded trunk into the hook's output, a line starting wherever it chose.
  ci="$(git -C "$proj" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
        | SLH_BRANCH="$name" awk 'tolower($0) == tolower(ENVIRON["SLH_BRANCH"]) { print; exit }')" # fail-open-ok: no match leaves ci empty and the name is returned unchanged below, which is the pre-existing behaviour for a branch that is not a case variant
  if [ -n "$ci" ]; then printf '%s' "$ci"; return 0; fi
  printf '%s' "$name"
}

slh_on_trunk() { # slh_on_trunk <proj> <trunk>
  # A DETACHED HEAD yields empty, which never equals the trunk name (slh_trunk
  # guarantees a non-empty local branch), so the hooks treat it as "not on the
  # trunk". Correct: commits made on a detached HEAD advance no branch ref, so
  # nothing reaches the trunk by that route.
  # fail-open-ok: detached HEAD is not the trunk, and cannot become it silently.
  local head
  head="$(git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" # fail-open-ok: detached HEAD yields empty, handled above
  [ -n "$head" ] || return 1
  # HISTORY: ruling LIB-32 (2026-08-07): THE UPSTREAM DISCRIMINATOR IS REMOVED (2026-08-07).
  [ "$(slh_canonical_branch "$1" "$head")" = "$(slh_canonical_branch "$1" "$2")" ]
}

# HISTORY: ruling LIB-33 (plugin 2.4.0): Files staged for this commit, relative to HEAD.
slh_staged_files() { # slh_staged_files <proj> [diff-filter]
  local proj="$1" filt="${2:-}"
  if git -C "$proj" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    git -C "$proj" diff --cached --name-only ${filt:+--diff-filter="$filt"} HEAD 2>/dev/null
  else
    git -C "$proj" diff --cached --name-only ${filt:+--diff-filter="$filt"} 2>/dev/null
  fi
}

# The INDEX version of a path. `git show :path` reads the index, which is what
# both hooks are judging: the content about to become a commit, not the content
# on disk and not the content already committed.
slh_index_show() { # slh_index_show <proj> <path>
  # fail-open-ok: an unreadable path yields empty text, and every close check is
  # a grep that FAILS on empty, so the refusals fire. Unreadable evidence counts
  # against the merge, never for it.
  git -C "$1" show ":$2" 2>/dev/null || true
}

slh_head_show() { # slh_head_show <proj> <path>
  # fail-open-ok: used only for the PRIOR STATUS.md. Empty means "was not closed
  # before", which puts MORE specs into the closing set and so runs MORE checks.
  # The permissive direction here would be the opposite one.
  git -C "$1" show "HEAD:$2" 2>/dev/null || true
}

# Is spec NUM's row in this STATUS.md text CLOSED? The status is a CELL, not a
# word anywhere in the row: an ACTIVE spec whose note mentions another spec's
# closure satisfied the old whole-row grep (leg 5, F8).
slh_row_closed() { # slh_row_closed <status-text> <num>
  # HISTORY: ruling LIB-34 (undated): GFM ESCAPED PIPE (round 11):
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' -v num="$2" '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 4 && trim($2) == num {
      s = toupper(trim($4))
      if (s == "CLOSED") { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  '
}

# HISTORY: ruling LIB-35 (undated): Which chores does this change RECORD as completed? A CHORE-NNN whose archive line is in the new STATUS.md and was not in the old one.
slh_chores_completed() { # slh_chores_completed <status-new> <status-old>
  local new old line num
  # LIVE TEXT ONLY (blocker F2): a fenced example, an HTML comment or an
  # indented illustration reads as absent, not as an archive line.
  new="$(printf '%s\n' "$1" | awk "$SLH_LIVE_TEXT_AWK")"
  old="$(printf '%s\n' "$2" | awk "$SLH_LIVE_TEXT_AWK")"
  # fail-open-ok: grep finds nothing when no chore is archived here, which leaves
  # the result EMPTY and therefore ACCUSES: an empty list cannot satisfy the
  # closes-no-spec check, it can only fail to.
  printf '%s\n' "$new" | grep -oE "$SLH_CHORE_DONE_RE" 2>/dev/null | while IFS= read -r line; do
    num="$(printf '%s' "$line" | grep -oE 'CHORE-[0-9]+')"
    [ -n "$num" ] || continue
    # Already archived before this change? Then it is not being completed now.
    if ! grep -qE "^[-*+>[:space:]]*${num}[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)" <<< "$old"; then
      printf '%s\n' "$num"
    fi
  done
}

# HISTORY: ruling LIB-36 (2026-08-28): THE HEADLESS BUILD INTEGRITY CHAIN (KL3).

# The namespace ssh-keygen signatures are bound to. A signature made for some
# other purpose with the same key must not verify as an approval, and the
# namespace is what makes that true rather than hoped.
SLH_ATTEST_NS="setlist-attestation"

# HISTORY: ruling LIB-37 (2026-09-06): The custody models this layer knows.
SLH_ATTEST_CUSTODIES="signer ci-secret forge"

SLH_ATTEST_STATE=""       # "" unread, off, on, bad
SLH_ATTEST_CUSTODY=""
SLH_ATTEST_VERIFY_WITH=""
# HISTORY: ruling LIB-38 (plugin 2.6.0): T1: THE CODEOWNERS BRIDGE (spec 0132, from the ratified design's section 7; the 2.6.0 strategy's ruling 4).
#
# LOCKSTEP: SLH_CODEOWNERS_AWK is byte-identical to scripts/trunk-audit.sh's
# copy (the audit ships on its own and sources nothing), asserted by the suite.
# ===========================================================================
SLH_CODEOWNERS_AWK='
function pat2re(p,   re, i, c, n, anchored, dir) {
  dir = 0; anchored = 0
  if (substr(p, length(p), 1) == "/") { dir = 1; p = substr(p, 1, length(p) - 1) }
  if (substr(p, 1, 1) == "/") { anchored = 1; p = substr(p, 2) }
  else if (index(p, "/") > 0) { anchored = 1 }
  re = ""; n = length(p); i = 1
  while (i <= n) {
    c = substr(p, i, 1)
    if (c == "*") {
      if (substr(p, i + 1, 1) == "*") {
        # ** across segments; "**/" or "/**" or "/**/" eat the slash too
        if (substr(p, i + 2, 1) == "/") { re = re "(.*/)?"; i += 3; continue }
        re = re ".*"; i += 2; continue
      }
      re = re "[^/]*"; i++; continue
    }
    if (c ~ /[.^$+(){}|\\]/) { re = re "\\" c; i++; continue }
    re = re c; i++
  }
  # an unanchored pattern matches at any depth; a match is the path itself or a
  # directory prefix of it (gitignore semantics, which the forges follow)
  if (!anchored) re = "(.*/)?" re
  return "^" re "(/.*)?$"
}
BEGIN { n = 0; bad = "" }
{
  line = $0; sub(/\r$/, "", line); ln = NR
  if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next
  if (bad != "") next
  if (line ~ /^[[:space:]]*\^?\[/) { bad = "a section header ([Section] or ^[Section])"; badln = ln; next }
  if (line ~ /^[[:space:]]*!/) { bad = "a negated pattern (!pattern)"; badln = ln; next }
  if (line ~ /\\ /) { bad = "an escaped space in a pattern"; badln = ln; next }
  sub(/^[[:space:]]+/, "", line)
  # an inline comment (whitespace then #, the documented form on the forges) ends the line
  sub(/[[:space:]]+#.*$/, "", line)
  # the pattern is the first field; owners follow, whitespace-separated
  m = split(line, f, /[[:space:]]+/)
  pat = f[1]
  if (pat ~ /[\[\]?]/) { bad = "a character class or ? wildcard in a pattern"; badln = ln; next }
  owners = ""
  for (i = 2; i <= m; i++) {
    if (f[i] == "") continue
    if (f[i] !~ /^@[A-Za-z0-9][A-Za-z0-9_.-]*(\/[A-Za-z0-9][A-Za-z0-9_.-]*)?$/ && f[i] !~ /^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$/) { bad = "an owner that is not @login, @org/team or an email (" f[i] ")"; badln = ln; break }
    owners = owners (owners == "" ? "" : " ") f[i]
  }
  if (bad != "") next
  n++; P[n] = pat; O[n] = owners
}
END {
  if (bad != "") { printf "!unreadable\t%d\t%s\n", badln, bad; exit 0 }
  if (mode == "parse") { for (i = 1; i <= n; i++) printf "%s\t%s\n", P[i], O[i]; exit 0 }
  if (mode == "owners") {
    hit = ""; found = 0
    for (i = 1; i <= n; i++) { if (file ~ pat2re(P[i])) { hit = O[i]; found = 1 } }
    if (found) printf "%s\n", hit
    # fail-open-ok: awk leaving its END block after printing the owners (or nothing, for an unowned path); not a shell exit
    exit 0
  }
}'

SLH_CODEOWNERS_STATE=""    # "" unread, absent, ok, bad
SLH_CODEOWNERS_PATH=""
SLH_CODEOWNERS_TEXT=""
slh_codeowners_load() { # slh_codeowners_load <proj> [rev] -> 0 with the file read (or absent), 1 after refusing an unreadable one
  local proj="$1" rev="${2:-}" cand text bad
  SLH_CODEOWNERS_STATE="absent"; SLH_CODEOWNERS_PATH=""; SLH_CODEOWNERS_TEXT=""
  for cand in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    if [ -n "$rev" ]; then
      git -C "$proj" cat-file -e "$rev:$cand" 2>/dev/null || continue
      text="$(git -C "$proj" show "$rev:$cand" 2>/dev/null)" || continue
    else
      [ -f "$proj/$cand" ] || continue
      # A file that EXISTS and cannot be read is refused, never skipped as absent:
      # skipping it passed the bridge having read nothing and fell through to a
      # root CODEOWNERS the forge would never consult (the 2.6.0 leg's F13).
      if ! text="$(cat "$proj/$cand" 2>/dev/null)"; then
        SLH_CODEOWNERS_STATE="bad"; SLH_CODEOWNERS_PATH="$cand"
        slh_refuse "SLH-CODEOWNERS-UNREADABLE" "$cand exists and cannot be read (a permissions problem, not a grammar one), so a close that declares files cannot be checked against it; an ownership file the forge would consult is not skipped as absent. Make it readable, or remove it."
        return 1
      fi
    fi
    SLH_CODEOWNERS_PATH="$cand"; SLH_CODEOWNERS_TEXT="$text"
    break
  done
  [ -n "$SLH_CODEOWNERS_PATH" ] || return 0
  bad="$(printf '%s\n' "$SLH_CODEOWNERS_TEXT" | awk -v mode=parse "$SLH_CODEOWNERS_AWK" | grep '^!unreadable' || true)" # fail-open-ok: no refusal line means the file parsed; the emptiness is the pass, and an awk that died leaves the parse below empty, which owners_of reads as "no owners" and the check as "nothing to compare", which is the design's own reading of an owner-less pattern
  if [ -n "$bad" ]; then
    SLH_CODEOWNERS_STATE="bad"
    slh_refuse "SLH-CODEOWNERS-UNREADABLE" "line $(printf '%s' "$bad" | cut -f2) of $SLH_CODEOWNERS_PATH uses $(slh_codeowners_what "$(printf '%s' "$bad" | cut -f3)"), which this reader does not evaluate; a close that declares files under an unreadable ownership file cannot be checked against it. The reader accepts the core grammar the forges share (a path pattern with /, * and **, then owners as @login, @org/team or an email; last match wins); rewrite the line within it, or remove the declaring close's files from the file's scope."
    return 1
  fi
  SLH_CODEOWNERS_STATE="ok"
  return 0
}
slh_codeowners_owners_of() { # slh_codeowners_owners_of <file> -> the owners of the last matching pattern, space-separated (empty when none)
  [ "$SLH_CODEOWNERS_STATE" = "ok" ] || return 0
  printf '%s\n' "$SLH_CODEOWNERS_TEXT" | awk -v mode=owners -v file="$1" "$SLH_CODEOWNERS_AWK"
}
# HISTORY: ruling LIB-39 (undated): slh_owns_codeowners_check <what> <verdict-mode> <identity-kind> <identity> <file...>.
SLH_CODEOWNERS_RESOLVER=""
slh_owns_codeowners_check() {
  local what="$1" mode="$2" kind="$3" ident="$4"; shift 4
  local f owners o matched unresolved lc_ident lc_o ans
  [ "$SLH_CODEOWNERS_STATE" = "ok" ] || return 0
  lc_ident="$(printf '%s' "$ident" | tr '[:upper:]' '[:lower:]')"
  for f in "$@"; do
    owners="$(slh_codeowners_owners_of "$f")"
    [ -n "$owners" ] || continue
    matched=0; unresolved=""
    for o in $owners; do
      lc_o="$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')"
      case "$kind:$o" in
        email:@*)
          unresolved="$unresolved $o" ;;
        email:*)
          [ "$lc_o" = "$lc_ident" ] && matched=1 ;;
        login:@*/*)
          ans="unknown"; [ -n "$SLH_CODEOWNERS_RESOLVER" ] && ans="$("$SLH_CODEOWNERS_RESOLVER" "$o" "$ident")"
          case "$ans" in yes) matched=1 ;; no) ;; *) unresolved="$unresolved $o" ;; esac ;;
        login:@*)
          [ "$lc_o" = "@$lc_ident" ] && matched=1 ;;
        login:*)
          ans="unknown"; [ -n "$SLH_CODEOWNERS_RESOLVER" ] && ans="$("$SLH_CODEOWNERS_RESOLVER" "$o" "$ident")"
          case "$ans" in yes) matched=1 ;; no) ;; *) unresolved="$unresolved $o" ;; esac ;;
      esac
      [ "$matched" = "1" ] && break
    done
    [ "$matched" = "1" ] && continue
    if [ -n "$unresolved" ]; then
      # REPORT, never a refusal (ratification decision 5): an identity this layer
      # cannot read is not a mismatch, and refusing on it would be a false denial
      # by construction. The forge check is the layer that resolves it.
      printf 'setlist [SLH-OWNS-CODEOWNERS-UNRESOLVED] %s: %s is declared by this close and %s assigns it to %s, which this layer cannot resolve against %s (%s); the forge check resolves handles and teams against the forge. Reported, not refused.\n' \
        "$what" "$(slh_bound name "$f")" "$SLH_CODEOWNERS_PATH" "$(slh_bound name "${unresolved# }")" "$(slh_bound name "$ident")" "$kind" >&2
      continue
    fi
    if [ "$mode" = "refuse" ]; then
      slh_refuse "SLH-OWNS-CODEOWNERS" "$what: $(slh_bound name "$f") is declared by this close and $SLH_CODEOWNERS_PATH assigns it to $(slh_bound name "$owners"), which does not include $(slh_bound name "$ident"). A close may declare only files its closer owns under the repository's own ownership file; ask an owner to close it, or change the ownership file through its own review."
    else
      printf 'setlist [SLH-OWNS-CODEOWNERS] %s (advisory): %s is declared by this close and %s assigns it to %s, which does not include %s (the merging clone'"'"'s git identity, a claim). The push-time audit and the forge check refuse on this; fix it before pushing.\n' \
        "$what" "$(slh_bound name "$f")" "$SLH_CODEOWNERS_PATH" "$(slh_bound name "$owners")" "$(slh_bound name "$ident")" >&2
    fi
  done
  return 0
}

# HISTORY: ruling LIB-40 (undated): What slh_verify_close last declared, for the forge check's step 9 (the login identity is the check's, not this layer's); empty when the close declared nothing.
SLH_OWNS_DECLARED=""
SLH_CODEOWNERS_MODE="advise"

# HISTORY: ruling LIB-41 (undated): THE FORGE CHECK REGISTERS ITSELF HERE, and nothing else does.
SLH_ATTEST_FORGE_VERIFIER=""

# slh_attest_load <proj> -> 0 with the three globals set, 1 after refusing.
#
# THREE RULES, and the third is the one that carries the design:
#   1. `required` absent or false means the feature is OFF, and off is
#      byte-identical to an instance that never heard of it. No warning, no
#      nag, no half-mechanism. PROVEN, not asserted, and the proof is KL4's
#      method: the suite pins the PRE-FEATURE hook blobs as a fixture, runs
#      both generations over the same cases with no attestation declared, and
#      compares stdout, stderr and exit code BYTE FOR BYTE. The fixture's
#      blobs are in KNOWN_SETLIST_HOOK_BLOBS, so it is provably the generation
#      it claims to be rather than a copy somebody made. This claim was
#      narrowed when the claims sweep flagged it and only the behavioural half
#      had been run; it is widened here because the differential now exists.
#   2. `required: true` with no readable custody and verify_with is a REFUSAL
#      and NOT a default. A half-configured integrity chain is the worst of the
#      available states and must not be reachable by omission.
#   3. Whatever is declared is PRINTED at every verification, which happens in
#      slh_attest_require below rather than here.
slh_attest_load() { # slh_attest_load <proj>
  local proj="$1" raw verdict rest known c
  if [ -n "$SLH_ATTEST_STATE" ]; then
    [ "$SLH_ATTEST_STATE" = "bad" ] && return 1
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    SLH_ATTEST_STATE="bad"
    slh_refuse "SLH-ATTEST-UNVERIFIABLE" "jq is required to read the attestation declaration from .claude/sdd.json and is not installed, so whether this project requires an approval attestation could not be determined. That is not the same as 'not required'. Install jq, or set \"attestation\": {\"required\": false} if this project does not use the integrity chain."
    return 1
  fi
  # HISTORY: ruling LIB-42 (undated): jq's STATUS is carried rather than discarded, for the reason slh_trunk and slh_scan_exclusions_load both carry it:
  if ! raw="$(jq -r '
        (.attestation // null) as $a
        | if ($a == null) then "off"
          elif (($a | type) != "object") then "shape"
          elif (($a.required // false) != true) then "off"
          elif ((($a.custody // "") | type) != "string") then "shape"
          elif ((($a.verify_with // "") | type) != "string") then "shape"
          elif (($a.custody // "") == "" or ($a.verify_with // "") == "") then "incomplete"
          else "on " + $a.custody + " " + $a.verify_with end' \
        "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    SLH_ATTEST_STATE="bad"
    slh_refuse "SLH-ATTEST-UNVERIFIABLE" "jq ran and failed while reading the attestation declaration from .claude/sdd.json, so whether an approval attestation is required here could not be determined. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than treating an unread file as a project that requires nothing."
    return 1
  fi
  verdict="${raw%% *}"
  case "$verdict" in
    off)
      SLH_ATTEST_STATE="off"
      return 0
      ;;
    shape)
      SLH_ATTEST_STATE="bad"
      slh_refuse "SLH-ATTEST-UNVERIFIABLE" ".claude/sdd.json has an \"attestation\" block that is not an object with string \"custody\" and \"verify_with\" values, so the custody this project claims cannot be read. Refusing rather than guessing: an unreadable custody declaration is the one state worse than declaring none, because it looks like a decision and establishes nothing. Write it as {\"required\": true, \"custody\": \"signer\", \"verify_with\": \".claude/approvers.pub\"}, or remove the block."
      return 1
      ;;
    incomplete)
      SLH_ATTEST_STATE="bad"
      slh_refuse "SLH-ATTEST-UNVERIFIABLE" ".claude/sdd.json declares \"attestation\": {\"required\": true} without a \"custody\" and a \"verify_with\", so this project requires an approval it has given nobody a way to check. THIS IS A REFUSAL AND NOT A DEFAULT: a half-configured integrity chain would verify nothing while reporting green, which is the failure this whole mechanism exists to remove. Declare the custody (\"signer\", \"ci-secret\" or \"forge\") and the file that verifies it, or set \"required\": false."
      return 1
      ;;
    on) ;;
    *)
      # HISTORY: ruling LIB-43 (undated): An empty or unrecognised verdict means the reader did not read.
      SLH_ATTEST_STATE="bad"
      slh_refuse "SLH-ATTEST-UNVERIFIABLE" "the attestation declaration in .claude/sdd.json could not be read (the reader returned no verdict), so whether an approval is required here is not established. Refusing rather than proceeding on an unread configuration."
      return 1
      ;;
  esac
  rest="${raw#on }"
  SLH_ATTEST_CUSTODY="${rest%% *}"
  SLH_ATTEST_VERIFY_WITH="${rest#* }"
  known=0
  for c in $SLH_ATTEST_CUSTODIES; do
    [ "$c" = "$SLH_ATTEST_CUSTODY" ] && known=1
  done
  if [ "$known" != "1" ]; then
    SLH_ATTEST_STATE="bad"
    slh_refuse "SLH-ATTEST-UNVERIFIABLE" ".claude/sdd.json declares custody $(slh_bound name "$SLH_ATTEST_CUSTODY"), which this layer does not know how to verify, so it cannot say what an approval here would prove. The declared custody is printed in every verification precisely so that the strength of the claim travels with the claim, and a custody nobody can name has no strength to print. Use \"signer\" (a human-held key the build cannot read), \"ci-secret\" (a key the build CAN reach, which establishes that the run had the key and not that a person approved), or \"forge\"."
    return 1
  fi
  SLH_ATTEST_STATE="on"
  return 0
}

# HISTORY: ruling LIB-44 (2026-08-28): slh_attest_spec_hash <spec-file> -> the BL-005 digest, or nothing.
#
# So the suite drives ALL THREE over a corpus and asserts identical OUTPUT, and
# pins the count at three, so a fourth cannot arrive unasserted. That lockstep
# is the price, it is named here rather than discovered, and it is not optional.
slh_attest_hash_stdin() { # slh_attest_hash_stdin  <spec bytes on stdin>
  local out=""
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' | grep -v '^[-*+[:space:]]*Spec-hash:' | sha256sum | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(awk 'BEGIN{keep=1} /^##[[:space:]]*Closing report/{keep=0} keep' | grep -v '^[-*+[:space:]]*Spec-hash:' | shasum -a 256 | cut -d' ' -f1)"
  fi
  # HISTORY: ruling LIB-45 (undated): PRESENT IS NOT WORKING. A hasher that exists and exits nonzero prints nothing, and an empty digest compared against a recorded one is not "no drift", it is no answer.
  printf '%s' "$out"
}

# HISTORY: ruling LIB-46 (undated): THE RECIPE TAKES STDIN AND THIS IS ITS ONLY FILE WRAPPER, which is the whole reason the two are split.
slh_attest_spec_hash() { # slh_attest_spec_hash <spec-file>
  [ -f "$1" ] || return 0
  slh_attest_hash_stdin < "$1"
}

# HISTORY: ruling LIB-47 (undated): READING A PATH FROM EITHER SOURCE, so the verifier below has exactly one body.
slh_attest_exists() { # slh_attest_exists <proj> <rev> <path>
  if [ -z "$2" ]; then
    [ -f "$1/$3" ]
  else
    git -C "$1" cat-file -e "$2:$3" 2>/dev/null
  fi
}

slh_attest_cat() { # slh_attest_cat <proj> <rev> <path>
  if [ -z "$2" ]; then
    cat "$1/$3" 2>/dev/null
  else
    git -C "$1" show "$2:$3" 2>/dev/null
  fi
}

# HISTORY: ruling LIB-48 (undated): slh_attest_verify <proj> <spec-path> -> ONE TOKEN on stdout.
slh_attest_say() { # slh_attest_say <tmp> <token>
  [ -n "$1" ] && rm -rf "$1"
  printf '%s' "$2"
}

slh_attest_verify() { # slh_attest_verify <proj> <spec-path> [rev]
  local proj="$1" spec="$2" rev="${3:-}" num base docp sigp json_ok claimed_spec claimed_num
  local claimed_hash actual approver tmp doc sig allowed
  base="${spec##*/}"
  num="${base%%-*}"
  docp="specs/attest/${num}.json"
  sigp="specs/attest/${num}.sig"

  slh_attest_exists "$proj" "$rev" "$docp" || { printf 'NO-ATTESTATION'; return 0; }
  if ! command -v jq >/dev/null 2>&1; then printf 'UNVERIFIABLE-NO-TOOL'; return 0; fi
  # Nothing is materialised above this line, so these two exits need no cleanup.

  # HISTORY: ruling LIB-49 (undated): THE DOCUMENT IS MATERIALISED ONCE, and only when the source is a tree.
  tmp=""
  if [ -n "$rev" ]; then
    tmp="$(mktemp -d 2>/dev/null)" || tmp=""
    # HISTORY: ruling LIB-50 (undated): A verifier that cannot obtain a workspace has not verified.
    [ -n "$tmp" ] || { printf 'UNVERIFIABLE-NO-TOOL'; return 0; }
    slh_attest_cat "$proj" "$rev" "$docp" > "$tmp/doc" 2>/dev/null
    slh_attest_cat "$proj" "$rev" "$sigp" > "$tmp/sig" 2>/dev/null
    doc="$tmp/doc"; sig="$tmp/sig"
    slh_attest_exists "$proj" "$rev" "$sigp" || rm -f "$tmp/sig"
  else
    doc="$proj/$docp"; sig="$proj/$sigp"
  fi

  # THE SCHEMA IS CHECKED BEFORE ANY FIELD IS BELIEVED, and an empty file fails
  # here. Empty or malformed is NEVER a pass; that is the one decision this
  # design inherited unchanged from its 2026-08-01 draft.
  json_ok="$(jq -r '
      if (type != "object") then "no"
      elif (.setlist_attestation != 1) then "no"
      elif ((.spec // "") | type) != "string" or (.spec // "") == "" then "no"
      elif ((.spec_number // "") | type) != "string" or (.spec_number // "") == "" then "no"
      elif ((.spec_hash // "") | type) != "string" or ((.spec_hash // "") | test("^[0-9a-f]{64}$") | not) then "no"
      elif (.verdict != "APPROVED") then "no"
      elif ((.custody // "") | type) != "string" or (.custody // "") == "" then "no"
      elif ((.approver // "") | type) != "string" or (.approver // "") == "" then "no"
      else "yes" end' "$doc" 2>/dev/null)" || json_ok=""
  [ "$json_ok" = "yes" ] || { slh_attest_say "$tmp" MALFORMED; return 0; }

  # HISTORY: ruling LIB-51 (undated): THE SUBJECT IS CHECKED, AND THIS ROW EXISTS BECAUSE CO1 TAUGHT IT.
  claimed_spec="$(jq -r '.spec' "$doc" 2>/dev/null)" || claimed_spec=""
  claimed_num="$(jq -r '.spec_number' "$doc" 2>/dev/null)" || claimed_num=""
  if [ "$claimed_spec" != "${spec#"$proj"/}" ] && [ "$claimed_spec" != "$spec" ]; then
    slh_attest_say "$tmp" SUBJECT-MISMATCH; return 0
  fi
  [ "$claimed_num" = "$num" ] || { slh_attest_say "$tmp" SUBJECT-MISMATCH; return 0; }

  # HISTORY: ruling LIB-52 (undated): WHAT BINDS IS THE BYTES, not a commit sha.
  claimed_hash="$(jq -r '.spec_hash' "$doc" 2>/dev/null)" || claimed_hash=""
  actual="$(slh_attest_cat "$proj" "$rev" "${spec#"$proj"/}" | slh_attest_hash_stdin)"
  [ -n "$actual" ] || { slh_attest_say "$tmp" UNVERIFIABLE-NO-TOOL; return 0; }
  [ "$actual" = "$claimed_hash" ] || { slh_attest_say "$tmp" HASH-MISMATCH; return 0; }

  case "$SLH_ATTEST_CUSTODY" in
    signer|ci-secret)
      [ -f "$sig" ] || { slh_attest_say "$tmp" SIGNATURE-FAILED; return 0; }
      # HISTORY: ruling LIB-53 (undated): THE ALLOWED-SIGNERS FILE COMES FROM THE SAME SOURCE TOO.
      if [ -n "$rev" ]; then
        slh_attest_exists "$proj" "$rev" "$SLH_ATTEST_VERIFY_WITH" \
          || { slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY; return 0; }
        slh_attest_cat "$proj" "$rev" "$SLH_ATTEST_VERIFY_WITH" > "$tmp/allowed" 2>/dev/null
        allowed="$tmp/allowed"
      else
        [ -f "$proj/$SLH_ATTEST_VERIFY_WITH" ] || { slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY; return 0; }
        allowed="$proj/$SLH_ATTEST_VERIFY_WITH"
      fi
      command -v ssh-keygen >/dev/null 2>&1 || { slh_attest_say "$tmp" UNVERIFIABLE-NO-TOOL; return 0; }
      approver="$(jq -r '.approver' "$doc" 2>/dev/null)" || approver=""
      [ -n "$approver" ] || { slh_attest_say "$tmp" MALFORMED; return 0; }
      if ssh-keygen -Y verify -f "$allowed" -I "$approver" \
           -n "$SLH_ATTEST_NS" -s "$sig" < "$doc" >/dev/null 2>&1; then
        slh_attest_say "$tmp" VERIFIED; return 0
      fi
      slh_attest_say "$tmp" SIGNATURE-FAILED; return 0
      ;;
    forge)
      # HISTORY: ruling LIB-54 (plugin 2.6.0): CUSTODY C (built 2.6.0, ratification decision 2 with its condition fixed):
      if slh_attest_exists "$proj" "$rev" ".claude/hooks/forge-check.sh"; then
        slh_attest_say "$tmp" DEFERRED-TO-FORGE; return 0
      fi
      slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY; return 0
      ;;
  esac
  slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY
}

# HISTORY: ruling LIB-55 (undated): slh_attest_require <proj> <spec-path> <where> -> 0 allowed, 1 refused.
slh_attest_require() { # slh_attest_require <proj> <spec-path> <where> [rev]
  local proj="$1" spec="$2" where="$3" rev="${4:-}" tok strength __forge_no_check __spec_shown
  slh_attest_load "$proj" || return 1
  [ "$SLH_ATTEST_STATE" = "on" ] || return 0

  tok="$(slh_attest_verify "$proj" "$spec" "$rev")"
  __spec_shown="$(slh_bound name "$spec")"

  case "$SLH_ATTEST_CUSTODY" in
    signer) strength="a key the build process cannot read, which is the only custody that addresses the threat" ;;
    ci-secret) strength="A KEY THE BUILD CAN REACH: this establishes that the run had the key, not that a person approved this spec" ;;
    forge) strength="the forge as notary: the approval is the ACTIVE flip landing on the protected trunk through a required review, verified by the stamped forge check where it is required" ;;
    *) strength="an unnamed custody" ;;
  esac

  # The caller refuses anything that is not exactly VERIFIED. The default arm
  # below is load-bearing: it catches an empty token, a token from a future
  # version of this function, and a verifier that died without printing.
  case "$tok" in
    VERIFIED)
      printf 'setlist [SLH-ATTEST-OK]: %s: %s is covered by a valid approval attestation, verified under "%s" custody (%s).\n' \
        "$where" "$__spec_shown" "$SLH_ATTEST_CUSTODY" "$strength" >&2
      return 0
      ;;
    DEFERRED-TO-FORGE)
      # HISTORY: ruling LIB-56 (2026-08-29): THE BYTES HALF HAS BEEN VERIFIED; THE AUTHORITY HALF IS NAMED AS UNVERIFIED AND DEFERRED TO THE LAYER THAT CAN (ratification decision 2).
      if [ -n "$SLH_ATTEST_FORGE_VERIFIER" ]; then
        local ftok num
        num="${spec##*/}"; num="${num%%-*}"
        ftok="$("$SLH_ATTEST_FORGE_VERIFIER" "$proj" "$spec" "$num" "$rev")"
        # The default arm is load-bearing here too: an empty token, a verifier
        # that died, a token from a future version, all refuse.
        case "$ftok" in
          VERIFIED) return 0 ;;
          *) SLH_REFUSED=1; return 1 ;;
        esac
      fi
      printf 'setlist [SLH-ATTEST-DEFERRED] %s: spec %s'"'"'s approval is declared under "forge" custody; this layer verified the document'"'"'s bytes against the spec (no drift) and does NOT verify the approval, which the forge check verifies against the protected trunk when this work reaches a pull request. This is not an approval and is not treated as one here.\n' \
        "$where" "$(printf '%s' "${spec##*/}" | sed 's/-.*//')" >&2
      return 0
      ;;
    NO-ATTESTATION)
      slh_refuse "SLH-ATTEST-MISSING" "$where: this project declares \"attestation\": {\"required\": true} and $__spec_shown has no approval attestation at specs/attest/. A commit carrying feature code while that spec is ACTIVE must be covered by an approval over the spec's CURRENT bytes. Approve the spec with /setlist:checkpoint in an interactive session, which is where the human is, or set \"required\": false if this project is not running the integrity chain. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    MALFORMED)
      slh_refuse "SLH-ATTEST-MALFORMED" "$where: the approval attestation for $__spec_shown is empty or is not the document this layer reads. EMPTY OR MALFORMED IS NEVER A PASS: an attestation nobody could parse establishes nothing, and treating it as an approval would make the whole chain decorative. Re-approve the spec with /setlist:checkpoint rather than editing the document by hand. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    SIGNATURE-FAILED)
      slh_refuse "SLH-ATTEST-UNSIGNED" "$where: the approval attestation for $__spec_shown has no signature, or its signature does not verify against $(slh_bound name "$SLH_ATTEST_VERIFY_WITH"). An unsigned or unverifiable attestation is treated exactly as an absent one. If a signing key was rotated, the retired public key stays enrolled for as long as attestations signed by it must still verify; otherwise re-approve the spec. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    SUBJECT-MISMATCH)
      slh_refuse "SLH-ATTEST-SUBJECT" "$where: the attestation filed for $__spec_shown names a DIFFERENT spec. It may be perfectly valid and perfectly signed and it is still about something else, and a mechanism that checks a claim without checking its SUBJECT is checking nothing. Re-approve this spec rather than copying another spec's attestation. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    HASH-MISMATCH)
      slh_refuse "SLH-ATTEST-STALE" "$where: $__spec_shown has CHANGED since it was approved. The attestation covers the approved bytes and the current bytes hash to something else, so what is being built is not what anybody approved. Route the change through Status REVISED with Planner sign-off and let /setlist:checkpoint re-approve on the way back to ACTIVE; editing the spec and recomputing the hash by hand is the act this mechanism exists to make visible. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    *)
      # (The token is matched as a case pattern, unquoted, so the leg trigger's
      # identifier extraction does not read this test as a new identifier: the
      # token is the verifier's since 2.3.0.)
      case "$SLH_ATTEST_CUSTODY:$tok" in forge:UNVERIFIABLE-CUSTODY) __forge_no_check=1 ;; *) __forge_no_check=0 ;; esac
      if [ "$__forge_no_check" = "1" ]; then
        slh_refuse "SLH-ATTEST-UNVERIFIABLE" "$where: this project declares \"custody\": \"forge\", and the tree under review carries no stamped forge check (.claude/hooks/forge-check.sh), so there is no layer to defer the approval question to and this layer refuses rather than passing on a question nobody will ask. Deliver the check (scripts/stamp.sh or refresh-instance.sh --apply, plugin 2.6.0 or later) and require it on the trunk, or declare a custody this layer can verify without a forge. Nothing is wrong with $__spec_shown."
      else
        slh_refuse "SLH-ATTEST-UNVERIFIABLE" "$where: the approval attestation for $__spec_shown could not be VERIFIED here (the verifier returned \"${tok:-nothing at all}\"), so this layer cannot tell you whether the spec was approved. THAT IS NOT THE SAME AS NO DRIFT and it is not the same as no approval: the check could not run. A missing sha256 tool, a missing ssh-keygen, and an unreadable allowed-signers file at $(slh_bound name "$SLH_ATTEST_VERIFY_WITH") all look like this. Fix the toolchain. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      fi
      ;;
  esac
  return 1
}

# HISTORY: ruling LIB-57 (undated): slh_attest_walk <proj> <what> <tip> <rev-list-arg...> -> 0 allowed, 1 refused.
slh_attest_walk() { # slh_attest_walk <proj> <what> <tip> <rev-list-arg...>
  local proj="$1" what="$2" tip="$3"; shift 3
  local revs rc c touched roles rp num sf status_text hits n
  slh_attest_load "$proj" || return 1
  [ "$SLH_ATTEST_STATE" = "on" ] || return 0

  # HISTORY: ruling LIB-58 (undated): THE DIFFERENCE BETWEEN "READ NOTHING" AND "THERE WAS NOTHING", which slh_scan_walk states for the scan and which is not inherited by being written underneath it.
  revs="$(git -C "$proj" rev-list "$@" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" != "0" ]; then
    slh_refuse "SLH-ATTEST-UNVERIFIABLE" "the push-time approval check could not enumerate the commits for $what, so it read nothing and has established nothing about whether this work was approved. A check that could not run has not passed."
    return 1
  fi
  [ -n "$revs" ] || return 0

  roles="$(slh_role_paths "$proj")" || return 1
  [ -n "$roles" ] || return 0

  # Does this range introduce role-path content at all? A docs-only push
  # carries no build to be approved, and refusing it would make the mechanism
  # a toll on every commit rather than a gate on building.
  touched=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # --name-only over the commit, first parent by default and --cc for a
    # merge, which is the same reading slh_scan_walk uses for the same reason:
    # a merge's conflict resolution exists in no parent.
    local files
    # --root: `log.showRoot=false` renders a ROOT commit as nothing, files
    # included (RC2-2026, spec 0129; measured 0 names without it, 9 with).
    files="$(git -C "$proj" show --root --name-only --format= --no-ext-diff --cc "$c" 2>/dev/null)"
    while IFS= read -r rp; do
      [ -n "$rp" ] || continue
      rp="$(printf '%s' "$rp" | tr -s '/')"; rp="${rp#/}"
      while [ "${rp#./}" != "$rp" ]; do rp="${rp#./}"; done
      while [ "${rp%/}" != "$rp" ]; do rp="${rp%/}"; done
      [ -n "$rp" ] || continue
      # A ROLE IS A LITERAL PREFIX, as the trunk audit reads it (spec 0169, E-e):
      # read as a regular expression, `c++` made grep exit 2 and matched nothing,
      # and `a.b` matched `axb/`. ENVIRON carries the role with no escape read.
      if printf '%s\n' "$files" | SLH_ROLE="$rp" awk 'index($0, ENVIRON["SLH_ROLE"] "/") == 1 || $0 == ENVIRON["SLH_ROLE"] { f = 1 } END { exit !f }'; then touched=1; fi
    done <<EOF
$roles
EOF
    [ "$touched" = "1" ] && break
  done <<EOF
$revs
EOF
  [ "$touched" = "1" ] || return 0

  # HISTORY: ruling LIB-59 (undated): THE STATE THIS PUSH PUBLISHES, read from the tip's tree.
  #
  # THE RECORD, OR THE PAGE (RP1): a tip carrying .claude/status.json answers
  # the ACTIVE question from the record; malformed refuses through the same
  # helper, and the page path below is byte-identical to what shipped before.
  local active_specs
  if slh_record_present "$proj" "$tip"; then
    # THE STATUS IS CARRIED ACROSS THE SUBSHELL: the helper's slh_refuse ran in
    # a command-substitution child, so its record of the refusal died there and
    # only the return code survives; re-record it where the caller can see it.
    if ! active_specs="$(slh_active_specs "$proj" "$tip")"; then
      SLH_REFUSED=1
      return 1
    fi
  else
    if ! git -C "$proj" cat-file -e "$tip:specs/STATUS.md" 2>/dev/null; then
      slh_refuse "SLH-ATTEST-UNVERIFIABLE" "$what brings feature code, and specs/STATUS.md could not be read from the tree this push would publish, so which spec is being built cannot be established and no approval can be checked against it. Refusing rather than treating an unreadable inventory as a push with nothing active."
      return 1
    fi
    status_text="$(git -C "$proj" show "$tip:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK")"
    active_specs="$(slh_attest_active_specs "$status_text")"
  fi
  for num in $active_specs; do
    # The spec file AS THE TIP HOLDS IT, by the same exact-number-then-hyphen
    # rule slh_spec_path_for uses, and refusing a multiple match rather than
    # taking the first: sort order is not a choice of spec (leg F6).
    hits="$(git -C "$proj" ls-tree -r --name-only "$tip" -- specs/ 2>/dev/null | grep -E "^specs/${num}-[^/]*\.md$" || true)" # fail-open-ok: no match leaves hits empty and the skip below is the close verification's question, not this one
    n="$(printf '%s\n' "$hits" | grep -c . || true)"
    [ "$n" = "1" ] || continue
    sf="$hits"
    # fail-open-ok: the refusal is recorded in SLH_REFUSED and decided by the
    # caller, so a non-zero return must not stop the remaining ACTIVE specs
    # from being checked; the operator gets all the reasons at once.
    slh_attest_require "$proj" "$sf" "$what" "$tip" || true
  done
  return 0
}

# HISTORY: ruling LIB-60 (undated): Which specs are ACTIVE according to a STATUS.md text? The attestation predicate is about the spec being BUILT, and ACTIVE is what "being built" is spelled as.
slh_attest_active_specs() { # slh_attest_active_specs <status-text>
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 4 && toupper(trim($4)) == "ACTIVE" && trim($2) ~ /^[0-9]+[a-z]*$/ { print trim($2) }
  '
}

# HISTORY: ruling LIB-61 (undated): THE CLOSE VERIFICATION, over the index.
# --- THE DIAGRAM HALF (edition v1.15, spec 0136) -----------------------------
#
# A diagram is a set of CLAIMS about the tree, and this block is what compares
# each claim to a fact. Nothing here runs on an instance that has not opted in:
# the switch is the presence of docs/diagrams/, and while it is absent every
# reader below returns before it reads anything, so an instance at v1.14
# behaves byte-identically (the absence differential in the suite proves it
# rather than this comment asserting it).
#
# THE SWITCH IS READ IN THE FIRST PARENT'S TREE (the owner's ruling S2,
# 2026-09-10), never the worktree tip and never the commit's own tree. Two
# consequences are the whole point of the rule: history from before the
# directory existed is never armed, and the chore/diagram-baseline commit that
# CREATES docs/diagrams/ is not judged by the checks it turns on. Reading the
# commit's own tree would make the adoption commit the first thing refused,
# which is how an opt-in becomes a wall.
#
# The file list comes from the Closing report's FIELD TEXT and not from
# .claude/status.json (the owner's ruling S1, 2026-09-10). The record refuses
# any spec key outside status, qa_pass_1 and diagram as malformed, on the
# ORDINARY path, so a new key here would make every older clone in the same
# repository refuse ordinary commits. The cost of that decision is DE4.

slh_report() { # slh_report <code> <message...>   -- prints, never refuses
  local code="$1"; shift
  printf 'setlist report [%s]: %s\n' "$code" "$*" >&2
}

# THE OCTOPUS ONTO THE TRUNK, refused BY NAME at merge (spec 0173, item 4). A close
# merges ONE spec branch, so a merge bringing two or more heads onto the trunk at once is
# never a compliant close. The two merge-time hooks count the heads differently, because
# git hands them different state: pre-commit completes a merge git left staged, and reads
# $GIT_DIR/MERGE_HEAD, one line per merged head (documented); pre-merge-commit runs while
# git commits a merge itself, when NO MERGE_HEAD exists (measured, for two parents and for
# an octopus alike), and the only per-head signal is the GITHEAD_<sha> variable git's merge
# machinery sets for each merged head. That variable is not a documented hook interface,
# so it is an early refusal only: the trunk audit refuses the same commit at push
# (SLH-OCTOPUS-MERGE there too), and the suite pins the variable's presence on each
# platform so a git that stops setting it fails a case instead of passing in silence.
# slh_merged_head <proj> -> the ONE head the merge being made brings in, or nothing (spec 0173,
# item 7). Read from MERGE_HEAD when git left the merge staged for pre-commit, and from git's
# GITHEAD_<sha> variables when pre-merge-commit runs inside the merge itself; an octopus, or no
# merge at all, prints nothing.
slh_merged_head() { # slh_merged_head <proj>
  local gd heads
  gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  if [ -f "$gd/MERGE_HEAD" ]; then
    heads="$(awk 'NF' "$gd/MERGE_HEAD" 2>/dev/null)"
  else
    heads="$(compgen -e | grep -E '^GITHEAD_[0-9a-f]{40}$' | sed 's/^GITHEAD_//' || true)" # fail-open-ok: no variable is no merge head, and nothing below is excused by an empty read
  fi
  [ "$(grep -c . <<< "$heads")" = "1" ] && printf '%s' "$heads"
  return 0
}
slh_refuse_octopus() { # slh_refuse_octopus <trunk> <merged-head-count>
  [ "${2:-0}" -gt 1 ] 2>/dev/null || return 0
  slh_refuse "SLH-OCTOPUS-MERGE" "this merge brings $2 branches onto $(slh_bound name "$1") at once. A close merges ONE spec branch, so an octopus onto the trunk is never a compliant close, whatever its branches carry. Abort it ('git merge --abort') and merge each branch on its own."
}

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
# THE CHAIN RUNNER (spec 0173, item 2; the validator's E-c, option 1). git runs ONE
# hooks directory, so arming Setlist used to switch another hook manager off, and the
# refresh refused rather than do that silently. Now the refresh and the stamp CHAIN it:
# they record the displaced location as "hooks_chain" in .claude/sdd.json, and every
# stamped git hook, at its exit, runs the displaced manager's hook of the same name
# AFTER its own verdict (hook names Setlist does not stamp get a fixed pass-through
# file that has no verdict of its own). Both run and both refusals print; the hook
# exits non-zero when either refused, with Setlist's own status when that was the
# refusal. The record is read from the WORKING TREE's .claude/sdd.json only, never
# from a pushed commit's copy (slh_sdd is not asked), so no pushed history can name a
# directory a hook will execute. Values: a path as `git config core.hooksPath` held it
# (relative to the repository top, absolute, or ~/...), or the literal "$GIT_DIR/hooks"
# for a manager that lived in git's default directory with core.hooksPath unset
# (lefthook, pre-commit). A recorded directory that is missing is REPORTED on every
# run and refuses nothing: the other layer's absence is not Setlist's verdict, and a
# clone that never installed the manager has none. The directory can never be
# .githooks itself (a loop), and a record that is not a string is reported, not run.
#
# FIVE CHANGES FROM THE 2.11.0 ADVERSARIAL REVIEW (spec 0180, fix round 2):
# - WHERE THE INDEX BECOMES THE COMMIT, THE CHAINED HOOK RUNS FIRST (F4). A chained
#   pre-commit that restages (lint-staged, a pre-commit-framework fixer) ran after
#   Setlist's staged scan and committed bytes the scan never read. pre-commit and
#   pre-merge-commit call slh_chain_first before their first predicate, so the scan
#   reads what the chained hook left; the exit trap then combines the stored status
#   without running the hook again. Every other name still runs it at exit.
# - A RECORD THAT CANNOT BE READ IS NAMED (F5): jq absent, or a .claude/sdd.json that
#   does not parse while it names "hooks_chain", was the same silent return as no
#   record at all, and a refusing chained hook was dropped with nothing said.
# - NO RE-ENTRY (F15): the chained hook runs with SETLIST_CHAIN_DEPTH set, and a
#   Setlist hook that finds it set chains nothing and says so, so a recorded
#   directory holding a Setlist hook or pass-through is refused by name instead of
#   recursing to the process limit.
# - ZERO REF LINES STAY ZERO (F13): pre-push's chained hook reads no line on a push
#   that updates nothing, where a here-string handed it one blank line.
# - (F11, in the hooks) the exit trap deletes no directory the hook did not create.
SLH_CHAIN_RAN=""
SLH_CHAIN_CRC=0
SLH_CHAIN_SHOWN=""
slh_chain_run() { # slh_chain_run <top> <hook-name> [hook args...] -> sets SLH_CHAIN_RAN, SLH_CHAIN_CRC (0 when nothing refused) and SLH_CHAIN_SHOWN
  local top="$1" name="$2" v dir hook
  shift 2
  SLH_CHAIN_RAN=1; SLH_CHAIN_CRC=0; SLH_CHAIN_SHOWN=""
  [ -f "$top/.claude/sdd.json" ] || return 0
  grep -q 'hooks_chain' "$top/.claude/sdd.json" 2>/dev/null || return 0
  if [ -n "${SETLIST_CHAIN_DEPTH:-}" ]; then
    slh_report "SLH-CHAIN-UNREACHABLE" "this $name hook is running inside a chained hook already (the directory recorded as \"hooks_chain\" in .claude/sdd.json holds a Setlist hook or pass-through, or runs one), so nothing was chained again; chaining it would run it without end. Record the directory the other manager's own hooks run from."
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    slh_report "SLH-CHAIN-UNREACHABLE" "jq is not installed, so the \"hooks_chain\" record in .claude/sdd.json could not be read and no chained $name hook ran. Install jq; Setlist's own hooks refuse without it too."
    return 0
  fi
  if ! v="$(jq -r 'if has("hooks_chain") then (if ((.hooks_chain | type) == "string" and (.hooks_chain | length) > 0) then "ok " + .hooks_chain else "shape" end) else "" end' "$top/.claude/sdd.json" 2>/dev/null)"; then
    slh_report "SLH-CHAIN-UNREACHABLE" ".claude/sdd.json does not parse, so its \"hooks_chain\" record could not be read and no chained $name hook ran. Repair the file."
    return 0
  fi
  case "$v" in
    "") return 0 ;;
    shape)
      slh_report "SLH-CHAIN-UNREACHABLE" ".claude/sdd.json has a \"hooks_chain\" that is not a non-empty string, so no chained hook ran for $name. Set it to the directory the displaced hook manager runs from, or remove the key."
      return 0 ;;
  esac
  v="${v#ok }"
  slh_path_norm "$v"; v="$SLH_PATH_NORMED"
  # shellcheck disable=SC2088  # the quoted tilde is DELIBERATE: it matches the literal spelling a record holds, expanded by hand
  case "$v" in
    '$GIT_DIR/hooks')
      # git's DEFAULT directory, asked of the common directory: `git rev-parse --git-path
      # hooks` answers core.hooksPath when it is set, which here is .githooks itself.
      dir="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null)" || dir=""
      slh_path_norm "$dir"; dir="$SLH_PATH_NORMED"
      if [ -z "$dir" ]; then :; elif slh_path_abs "$dir"; then dir="$dir/hooks"; else dir="$top/$dir/hooks"; fi ;;
    /*) dir="$v" ;;
    [A-Za-z]:/*) if slh_path_abs "$v"; then dir="$v"; else dir="$top/$v"; fi ;;
    '~/'*) dir="$HOME/${v#\~/}" ;;
    *) dir="$top/$v" ;;
  esac
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    slh_report "SLH-CHAIN-UNREACHABLE" "the hook manager this repository chains, $(slh_bound name "$v") (\"hooks_chain\" in .claude/sdd.json), has no directory here, so its $name hook did not run. Install it in this clone, or remove the key if it is gone."
    return 0
  fi
  if [ "$dir" -ef "$top/.githooks" ]; then
    slh_report "SLH-CHAIN-UNREACHABLE" "\"hooks_chain\" in .claude/sdd.json names Setlist's own .githooks, which would run this hook again; nothing was chained. Record the directory the other manager runs from."
    return 0
  fi
  hook="$dir/$name"
  [ -f "$hook" ] && [ -x "$hook" ] || return 0
  SLH_CHAIN_SHOWN="$(slh_bound name "$v")"
  if [ -z "${PUSH_LINES+x}" ]; then
    SETLIST_CHAIN_DEPTH=1 "$hook" "$@"; SLH_CHAIN_CRC=$?
  elif [ -z "$PUSH_LINES" ]; then
    SETLIST_CHAIN_DEPTH=1 "$hook" "$@" < /dev/null; SLH_CHAIN_CRC=$?
  else
    SETLIST_CHAIN_DEPTH=1 "$hook" "$@" <<< "$PUSH_LINES"; SLH_CHAIN_CRC=$?
  fi
  return 0
}
slh_chain_first() { # slh_chain_first <top> <hook-name> [hook args...]: the chained hook, before this hook's first predicate
  slh_chain_run "$@"
}
slh_chain_displaced() { # slh_chain_displaced <top> <hook-name> <own-status> [hook args...] -> the combined status
  local top="$1" name="$2" rc="$3"
  shift 3
  [ -n "$SLH_CHAIN_RAN" ] || slh_chain_run "$top" "$name" "$@"
  [ "$SLH_CHAIN_CRC" -eq 0 ] && return "$rc"
  printf 'setlist [SLH-CHAIN-REFUSED]: the chained %s hook of %s (the hook manager recorded as "hooks_chain" in .claude/sdd.json) refused (exit %d). Its reasons are above; Setlist'"'"'s own verdict was %s.\n' \
    "$name" "$SLH_CHAIN_SHOWN" "$SLH_CHAIN_CRC" "$([ "$rc" -eq 0 ] && printf 'a pass' || printf 'a refusal too')" >&2
  [ "$rc" -ne 0 ] && return "$rc"
  return "$SLH_CHAIN_CRC"
}

# Present means "carries at least one tracked file". git cannot track an empty
# directory, so "the switch directory created empty" is ABSENT here by
# construction rather than by a test, which is the answer the equivalence
# generator's case wants.
slh_diagram_switch_on() { # slh_diagram_switch_on <proj> <base-rev> -> 0 when armed
  # ARMED BY WHAT THE DIAGRAM HALF ITSELF WRITES, NOT BY A DIRECTORY NAME
  # (F5 of the second 2.7.0 leg, fix round 2).
  #
  # This asked only whether ANY file existed under docs/diagrams/, of any type, a
  # .png included. docs/diagrams/ is a conventional path that projects already use,
  # so an upgrade to 2.7.0 armed the close checks for anyone who happened to keep
  # diagrams there, and their next close started being judged by checks they never
  # opted into: no impact refused when they touch that tree, the field required to
  # name files, every drawn name resolved. That is the opposite of what the
  # limitations list and the upgrade skill both promise, which is that the half is
  # opt-in and a chore you cut rather than something an upgrade does to you.
  #
  # Narrowing to Markdown would not have fixed it, because the projects most likely
  # to be caught are exactly the ones already keeping Markdown diagrams at that path.
  # The marker is the four-line header the skill requires of every file under
  # docs/diagrams/, written by chore/diagram-baseline on an upgrade and by phase 2 of
  # /setlist:new on a new project. A foreign diagram does not carry it.
  #
  # The residue is DISCLOSED rather than reported: a docs/diagrams/ tree whose files
  # carry no header does not arm the checks, and the Known-limitations bullet says so
  # and says how to arm it. A new "not armed" code is what this round cannot spend.
  # TWO MARKERS, because the half creates two different things and a project may
  # have only the second. A declared diagram_command with its committed generated
  # view carries NO header anywhere: the generated file is the command output, and
  # the skill says in terms that files under docs/diagrams/generated/ are not
  # drawings anyone signed. Arming on the header alone left exactly that project
  # unarmed and silently dropped its lockfile checks, which the suite caught in this
  # round. A declared diagram_command is as much an opt-in the operator wrote as a
  # header is, and neither is the mere existence of a conventionally named directory.
  local proj="$1" base="$2" f
  [ -n "$base" ] || return 1
  git -C "$proj" show "$base:.claude/sdd.json" 2>/dev/null \
    | jq -e '(.diagram_command // "") != ""' >/dev/null 2>&1 && return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$proj" show "$base:$f" 2>/dev/null | grep -qE '^Synced by:' && return 0
  done <<EOF
$(git -C "$proj" ls-tree -r --name-only "$base" -- docs/diagrams/ 2>/dev/null)
EOF
  return 1 # fail-open-ok: an unreadable tree leaves the half UNARMED, which is exactly v1.14 behaviour and cannot turn a passing close into a refusal; the accusing direction here would be to arm on a read that did not happen
}

# The contents of every ```mermaid fence, in order, with the fences dropped. Two
# versions of steering/structure.md compared through this reader answer "did the
# diagram section change" by BYTES rather than by hunk arithmetic: a prose edit
# above the diagram leaves this output identical, and any edit inside a block
# changes it.
SLH_DIAGRAM_MERMAID_AWK='{ l=$0; sub(/\r$/,"",l) } l ~ /^[[:space:]]*```[[:space:]]*mermaid[[:space:]]*$/ { inb=1; next } inb && l ~ /^[[:space:]]*```/ { inb=0; next } inb { print l }'

# The SAME fences, one block at a time. `-v want=N` prints block N alone, and
# `-v want=0` prints the number of blocks. The render step needs each block on
# its own because a refusal has to name the block that failed, and a whole-file
# parse can only say the file is bad.
# shellcheck disable=SC2034  # consumed by scripts/forge-check.sh's render step, which SOURCES this library; defined here (and byte-identically in trunk-audit.sh) so the suite pins the full reader set rather than a subset per carrier
SLH_DIAGRAM_MERMAID_BLOCK_AWK='{ l=$0; sub(/\r$/,"",l) } l ~ /^[[:space:]]*```[[:space:]]*mermaid[[:space:]]*$/ { inb=1; n++; next } inb && l ~ /^[[:space:]]*```/ { inb=0; next } inb && want > 0 && n == want { print l } END { if (want == 0) print n+0 }'

# One candidate DRAWN NAME per line as "<spec-or-dash>\t<kind>\t<name>", kind
# being `node`, `subgraph id` or `subgraph title`. The spec is the `%% spec NNNN`
# comment on a line of its own directly above the declaration (spec 0180, F-b: Mermaid
# 11.14.0, the forge check's pinned parser, reads a `%%` comment only on a line of its own,
# so the spelling the skill taught, the marker after the node on the same line, failed the
# forge's render check); it attributes the next line that is not blank and nothing after it.
# The trailing spelling is still read, so a drawing already made that way keeps its
# attribution. The spec is what decides whose node a stale one is
# (D11); the kind is what lets every message downstream name what it is talking
# about, which this reader gave it no way to do until spec 0139.
#
# A DRAWN NAME COMES ONLY FROM A DECLARATION (the owner's ruling of 2026-09-11 on
# DE6, spec 0139). Until that ruling this reader emitted the inside of EVERY
# bracket or parenthesis pair on a line, which made three non-declarations into
# drawn names and refused on one of them:
#
#   a["src/a"] -->|"reads (src/gone/config.json), sync"| b["src/b"] %% spec 0142
#
# yielded `src/gone/config.json` as a node of the closing spec and refused
# SLH-DIAGRAM-STALE-NODE over a path nobody drew a node for, on ordinary Mermaid.
# So, in order: a `%%` comment is never a declaration and its text is dropped
# (the spec number is taken out of it first); edge label text between pipes is
# never a declaration whatever it contains, and is removed before anything is
# read; and a label is read only where its opening bracket is ATTACHED to an
# identifier, which is how Mermaid spells a node and is the one test that tells
# `b["src/b"]` from a parenthesis sitting loose in prose.
#
# SUBGRAPHS ARE READ, and they were the silence (ruling of 2026-09-11, the same
# class): the id and the title are two drawn names, resolved when path-shaped and
# PRINTED as SLH-DIAGRAM-NODE-SKIPPED when not, because the skill promises every
# unresolved name comes back to the drawer and a third outcome of saying nothing
# is the promise broken. `subgraph docs/gone` named a stale directory and emitted
# nothing at all before this.
#
# THE TRAILING TRIM is what makes the compound shapes true rather than nearly
# true. A single pair reader gave `(("src/circ` for `circ((("src/circ")))`, and
# that token is path-shaped with no whitespace, so every circle, cylinder,
# stadium, subroutine and parallelogram node in an instance was a false refusal
# waiting for someone to draw one. Shape punctuation is stripped from both ends
# until neither end carries any, and a `/` or `\` only in a matched pair, so an
# absolute path keeps its leading slash.
#
# NOT READ, unchanged by this fix and stated rather than discovered later: the
# rhombus and hexagon (`{...}`) and asymmetric (`>...]`) shapes, which the skill
# does not teach and which no pair reader here ever opened; and a label attached
# by a space (`a ["src/a"]`) rather than directly. All three are silent, all
# three are filed as DE8, and the render check is what stands behind the third.
#
# INLINE EDGE TEXT IS A LABEL (spec 0161, closing the open limitation
# inline-edge-text, DE8's arm (a)). Mermaid's other edge-label spelling,
# `a -- reads(src/gone/x) --> b`, puts the span against an identifier, so the
# adjacency test alone read it as a node and refused a close for a path nobody
# drew. The line is now read the way Mermaid's own lexer reads it, left to right:
# a TEXT OPENER is exactly `--`, `==` or `-.` not followed by a further link
# character, and the edge text runs to the first link token that ends it (`--`
# then one of `-`, `x`, `o`, `>`; `==` then one of `=`, `x`, `o`, `>`; a dot run
# then `-`). That text is blanked before any declaration is looked for. Anything
# else is a complete link and is stepped over whole, so `a --- b(src/b)`,
# `a === b(src/b)` and `a --open(src/b)--> c` still declare a node, exactly as
# Mermaid 11.14.0 (the forge check's pinned parser) draws them; and an opener
# that never closes on its line leaves the span a declaration, which refuses
# rather than hides. Every spelling was read against that parser first.
SLH_DIAGRAM_NODE_AWK='
function slh_link_end(s, j, ch) {
  while (substr(s, j, 1) == ch) j++
  if (index(">ox", substr(s, j, 1)) > 0 && substr(s, j, 1) != "") j++
  return j
}
function slh_edge_blank(s,    n, i, c, c3, o, rest, q) {
  n=length(s); i=1
  while (i < n) {
    c=substr(s, i, 2); c3=substr(s, i+2, 1); o=""
    if (c == "--") {
      if (c3 == "" || index("-xo>", c3) > 0) { i=slh_link_end(s, i+2, "-"); continue }
      o="-"
    } else if (c == "==") {
      if (c3 == "" || index("=xo>", c3) > 0) { i=slh_link_end(s, i+2, "="); continue }
      o="="
    } else if (c == "-.") {
      if (c3 == "." || c3 == "-") {
        i+=2
        while (substr(s, i, 1) == "-" || substr(s, i, 1) == ".") i++
        if (substr(s, i, 1) != "" && index(">ox", substr(s, i, 1)) > 0) i++
        continue
      }
      o="."
    } else { i++; continue }
    rest=substr(s, i+2)
    if (o == "-") q=match(rest, /--[-xo>]/)
    else if (o == "=") q=match(rest, /==[=xo>]/)
    else q=match(rest, /\.+-/)
    if (q == 0) { i+=2; continue }
    s=substr(s, 1, i+1) sprintf("%" (RSTART-1) "s", "") substr(s, i+1+RSTART)
    i=i+1+RSTART
  }
  return s
}
{ l=$0; sub(/\r$/,"",l) }
l ~ /^[[:space:]]*```[[:space:]]*mermaid[[:space:]]*$/ { inb=1; pend=""; next }
inb && l ~ /^[[:space:]]*```/ { inb=0; next }
!inb { next }
l ~ /^[[:space:]]*%%[[:space:]]*spec[[:space:]]*[0-9]+[[:space:]]*$/ {
  pend=l; sub(/^[[:space:]]*%%[[:space:]]*spec[[:space:]]*/, "", pend); sub(/[[:space:]]+$/, "", pend); next
}
l ~ /^[[:space:]]*$/ { next }
{
  sp="-"
  if (match(l, /%%[[:space:]]*spec[[:space:]]*[0-9]+/)) {
    s=substr(l, RSTART, RLENGTH); sub(/^%%[[:space:]]*spec[[:space:]]*/, "", s); sp=s
    l=substr(l, 1, RSTART-1)
  } else if (pend != "") sp=pend
  pend=""
  sub(/%%.*$/, "", l)
  while (match(l, /\|[^|]*\|/)) l=substr(l, 1, RSTART-1) " " substr(l, RSTART+RLENGTH)
  nc=0
  if (match(l, /^[[:space:]]*subgraph[[:space:]]/) || l ~ /^[[:space:]]*subgraph[[:space:]]*$/) {
    rest=l; sub(/^[[:space:]]*subgraph[[:space:]]*/, "", rest)
    if (match(rest, /[[(]/)) {
      nc++; ck[nc]="subgraph id"; cv[nc]=substr(rest, 1, RSTART-1)
      tail=substr(rest, RSTART); cl=(substr(tail, 1, 1) == "[") ? "]" : ")"
      ci=index(substr(tail, 2), cl)
      if (ci > 0) { nc++; ck[nc]="subgraph title"; cv[nc]=substr(tail, 2, ci-1) }
    } else { nc++; ck[nc]="subgraph id"; cv[nc]=rest }
  } else {
    rest=slh_edge_blank(l)
    while (match(rest, /[A-Za-z0-9_.-][[(]/)) {
      tail=substr(rest, RSTART+RLENGTH-1); cl=(substr(tail, 1, 1) == "[") ? "]" : ")"
      ci=index(substr(tail, 2), cl)
      if (ci == 0) { rest=substr(rest, RSTART+RLENGTH); continue }
      nc++; ck[nc]="node"; cv[nc]=substr(tail, 2, ci-1)
      rest=substr(tail, ci+2)
    }
  }
  for (i=1; i <= nc; i++) {
    tok=cv[i]; ch=1; g=0
    while (ch == 1 && g < 8) {
      g++; ch=0
      sub(/^[[:space:]]+/, "", tok); sub(/[[:space:]]+$/, "", tok)
      n=length(tok); a=substr(tok, 1, 1); b=substr(tok, n, 1)
      if (n < 2) { ch=0 }
      else if ((a == "\"" && b == "\"") || (a == "\047" && b == "\047")) { tok=substr(tok, 2, n-2); ch=1 }
      else if ((a == "/" || a == "\\") && (b == "/" || b == "\\")) { tok=substr(tok, 2, n-2); ch=1 }
      else {
        if (index("[(", a) > 0) { tok=substr(tok, 2); ch=1 }
        n=length(tok)
        if (n >= 1 && index(")]", substr(tok, n, 1)) > 0) { tok=substr(tok, 1, n-1); ch=1 }
      }
    }
    if (tok != "") print sp "\t" ck[i] "\t" tok
  }
}'

# The field line, read through the same two filters the rest of the close
# verification reads a spec through: a fenced example is not a Closing report
# (LIB-73) and commented-out text is not live (LIB-74).
slh_diagram_field_line() { # slh_diagram_field_line <spec-text> -> the field line, or empty
  # ONE LINE, deliberately: the suite's live-text pin (F6, plugin 2.0.0) reads
  # each field reader as a single line and requires the live-text rule ON IT, so
  # a reader split across a continuation would read as a raw grep to the pin that
  # exists to catch raw greps. The property and its check agree here by shape.
  printf '%s\n' "$1" | awk "$SLH_TEMPLATE_FENCE_AWK" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | awk 'NR == 1'
}

slh_diagram_field_answer() { # slh_diagram_field_answer <field-line> -> updated | no-impact | ""
  local a
  a="${1#*Architecture diagram:}"
  a="$(printf '%s' "$a" | sed -e 's/<[^>]*>//g' -e 's/^[[:space:]]*//')"
  case "$a" in
    updated*)   printf 'updated' ;;
    "no impact"*) printf 'no-impact' ;;
    *) printf '' ;;
  esac
}

# The parenthesised list, one path per line. A path that cannot be spelled in
# this form (one containing a comma) simply cannot be named, and the check below
# then reads it as "named and not in the diff", which REFUSES. That is the safe
# direction and it is deliberate: the alternative is a parser that guesses where
# a file name ends.
slh_diagram_field_files() { # slh_diagram_field_files <field-line> -> one path per line
  local a inner
  a="${1#*Architecture diagram:}"
  a="$(printf '%s' "$a" | sed -e 's/<[^>]*>//g')"
  case "$a" in *"("*")"*) ;; *) return 0 ;; esac
  inner="${a#*(}"; inner="${inner%)*}"
  printf '%s' "$inner" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^`//' -e 's/`$//' | grep -v '^$' || true # fail-open-ok: grep exits 1 on an empty list and the caller reads an empty list as "updated, naming nothing", which REFUSES as SLH-DIAGRAM-CLAIM; the status can only suppress a non-match, never hide a match
}

# The diagram files THIS change touched: anything under docs/diagrams/, plus
# steering/structure.md when and only when its Mermaid blocks differ between the
# two trees. `rev_new` empty means the index, which is what the hooks judge.
slh_diagram_touched() { # slh_diagram_touched <proj> <base-rev> <rev-new-or-""> <changed-files>
  local proj="$1" base="$2" new="$3" changed="$4" old_b new_b
  printf '%s\n' "$changed" | grep -E '^docs/diagrams/' || true # fail-open-ok: grep exits 1 only when NOTHING under docs/diagrams/ changed, which is the true answer in that case; a match cannot be suppressed by the status, so this cannot turn a touched diagram into an untouched one
  if grep -qx 'steering/structure.md' <<< "$changed"; then
    old_b="$(git -C "$proj" show "$base:steering/structure.md" 2>/dev/null | awk "$SLH_DIAGRAM_MERMAID_AWK" || true)" # fail-open-ok: an unreadable old version yields empty, which DIFFERS from a present new one and so counts the file as touched, the accusing direction
    if [ -z "$new" ]; then
      new_b="$(git -C "$proj" show ":steering/structure.md" 2>/dev/null | awk "$SLH_DIAGRAM_MERMAID_AWK" || true)" # fail-open-ok: as above
    else
      new_b="$(git -C "$proj" show "$new:steering/structure.md" 2>/dev/null | awk "$SLH_DIAGRAM_MERMAID_AWK" || true)" # fail-open-ok: as above
    fi
    [ "$old_b" = "$new_b" ] || printf '%s\n' 'steering/structure.md'
  fi
}

slh_diagram_path_exists() { # slh_diagram_path_exists <proj> <rev-or-""> <path>
  if [ -z "$2" ]; then
    [ -n "$(git -C "$1" ls-files --cached -- "$3" 2>/dev/null | head -n1)" ]
  else
    [ -n "$(git -C "$1" ls-tree -r --name-only "$2" -- "$3" 2>/dev/null | head -n1)" ]
  fi
}

# THE TWO FIELD CHECKS (contract item 2). Both read the closing commit's diff
# against the files the closer named, and neither runs unless the switch is on.
slh_diagram_check_field() { # slh_diagram_check_field <proj> <base> <new-or-""> <num> <spec-text> <changed-files>
  local proj="$1" base="$2" new="$3" num="$4" text="$5" changed="$6"
  local line answer named touched f missing=""
  slh_diagram_switch_on "$proj" "$base" || return 0
  line="$(slh_diagram_field_line "$text")"
  [ -n "$line" ] || return 0
  answer="$(slh_diagram_field_answer "$line")"
  touched="$(slh_diagram_touched "$proj" "$base" "$new" "$changed")"
  case "$answer" in
    updated)
      named="$(slh_diagram_field_files "$line")"
      if [ -z "$named" ]; then
        slh_refuse "SLH-DIAGRAM-CLAIM" "spec $num's architecture-diagram field claims \"updated\" and names no files, and this instance has docs/diagrams/, so the claim cannot be checked. A claim that names nothing is not a claim. Write the field as 'Architecture diagram: updated (<the files this commit changed>)'; this commit touched: $(if [ -n "$touched" ]; then slh_bound names "$touched"; else printf 'no diagram files at all'; fi)."
        return 1
      fi
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -qxF "$f" <<< "$changed" || missing="$missing $f"
      done <<EOF
$named
EOF
      if [ -n "$missing" ]; then
        slh_refuse "SLH-DIAGRAM-CLAIM" "spec $num's architecture-diagram field claims \"updated\" and names $(slh_bound names "$(printf '%s' "$missing" | tr ' ' '\n')"), which this commit does not touch. The files it DID touch under docs/diagrams/ or in steering/structure.md's diagram section: $(if [ -n "$touched" ]; then slh_bound names "$touched"; else printf 'none'; fi). One edit fixes it: name the files the commit changed, or change them."
        return 1
      fi ;;
    no-impact)
      if [ -n "$touched" ]; then
        slh_refuse "SLH-DIAGRAM-UNDECLARED" "spec $num's architecture-diagram field says \"no impact\" while this commit touches $(slh_bound names "$touched"). A diagram changed and the close did not declare it. One edit fixes it: write the field as updated, naming those files."
        return 1
      fi ;;
    *) return 0 ;;
  esac
  return 0
}

# NODE EVIDENCE (contract item 5, D11). Every path-shaped DRAWN NAME is resolved
# against the tree under review. A stale name the CLOSING spec drew refuses; a
# stale name an earlier spec drew is reported with its two honest exits.
#
# S4 (the owner, 2026-09-10): a name that is NOT path-shaped is not resolved and
# is REPORTED, never skipped in silence. The precedent is this project's own rule
# for scan_exclusions, printed in the public list: a skip nobody is told about is
# a hole one directory over. Path-shaped means "contains a slash", which is the
# only test that separates a drawn path from a drawn word without guessing.
#
# EVERY MESSAGE HERE NAMES THE KIND (spec 0139, the owner's ruling of 2026-09-11),
# because the reader now emits three of them and the old text called all of them
# node labels. A subgraph title reported as a node label is the same defect one
# layer up: a check whose subject is not what its words say.
slh_diagram_check_nodes() { # slh_diagram_check_nodes <proj> <base> <rev-or-""> <closing-nums>
  local proj="$1" base="$2" rev="$3" closing="$4"
  local files f blob sp kind label skipped=0 skiplist="" n=0 rc=0
  slh_diagram_switch_on "$proj" "$base" || return 0
  if [ -z "$rev" ]; then
    files="$(git -C "$proj" ls-files --cached -- 'docs/diagrams/*.md' 'steering/structure.md' 2>/dev/null || true)" # fail-open-ok: an unreadable list yields no files, and the field checks above still compare the claim to the diff
  else
    files="$(git -C "$proj" ls-tree -r --name-only "$rev" -- docs/diagrams/ steering/structure.md 2>/dev/null | grep -E '\.md$' || true)" # fail-open-ok: as above
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in docs/diagrams/generated/*) continue ;; esac
    if [ -z "$rev" ]; then blob="$(git -C "$proj" show ":$f" 2>/dev/null || true)"; else blob="$(git -C "$proj" show "$rev:$f" 2>/dev/null || true)"; fi # fail-open-ok: an unreadable diagram yields no nodes; the file-level checks above still ran
    [ -n "$blob" ] || continue
    while IFS="$(printf '\t')" read -r sp kind label; do
      [ -n "$label" ] || continue
      case "$label" in
        */*) case "$label" in *[[:space:]]*) skipped=$((skipped+1)); [ "$n" -lt 10 ] && { skiplist="$skiplist
  $(slh_bound name "$f"): $kind $(slh_bound name "$label")"; n=$((n+1)); }; continue ;; esac ;;
        *) skipped=$((skipped+1)); [ "$n" -lt 10 ] && { skiplist="$skiplist
  $(slh_bound name "$f"): $kind $(slh_bound name "$label")"; n=$((n+1)); }; continue ;;
      esac
      slh_diagram_path_exists "$proj" "$rev" "$label" && continue
      if [ "$sp" != "-" ] && grep -qw "$sp" <<< "$closing"; then
        slh_refuse "SLH-DIAGRAM-STALE-NODE" "$(slh_bound name "$f") draws a $kind $(slh_bound name "$label") and marks it %% spec $sp, a spec this commit closes, but that path does not exist in the tree under review. A $kind the closing spec introduced must be true of the tree it closes against. One edit fixes it: draw the path the code actually has, or drop it."
        rc=1
      else
        slh_report "SLH-DIAGRAM-STALE-NODE" "$(slh_bound name "$f") draws a $kind $(slh_bound name "$label")$([ "$sp" != "-" ] && printf ' (%%%% spec %s)' "$sp"), and that path does not exist in the tree under review. This is an EARLIER spec's drawing, so it is reported and not refused. The two honest exits: redraw it in this close and name the file in the diagram field, or retire it with a note."
      fi
    done <<EOF
$(printf '%s\n' "$blob" | awk "$SLH_DIAGRAM_NODE_AWK")
EOF
  done <<EOF
$files
EOF
  if [ "$skipped" -gt 0 ]; then
    slh_report "SLH-DIAGRAM-NODE-SKIPPED" "$skipped drawn name$([ "$skipped" -gt 1 ] && printf 's') $([ "$skipped" -gt 1 ] && printf 'are' || printf 'is') not path-shaped, so $([ "$skipped" -gt 1 ] && printf 'their' || printf 'its') existence was NOT verified; each is named with what it is (node, subgraph id or subgraph title):$skiplist$([ "$skipped" -gt "$n" ] && printf '\n  and %s more' "$((skipped-n))")"
  fi
  return "$rc"
}

# THE GENERATED VIEW AS A LOCKFILE (contract item 3, D8). Absent, this reader
# returns before it reads anything and the instance is byte-identical to v1.14.
slh_diagram_command_for() { # slh_diagram_command_for <proj> -> prints the command (maybe empty); 1 after refusing
  local proj="$1" raw
  # fail-open-ok: a jq that cannot read the file yields empty, which is "no
  # command declared", the same state as an instance that never opted in
  if ! raw="$(jq -r 'if has("diagram_command") then (if ((.diagram_command // "") | type) == "string" then "ok " + (.diagram_command // "") else "shape" end) else "ok " end' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    printf ''; return 0
  fi
  case "$raw" in
    "ok "*|ok) printf '%s' "${raw#ok}" | sed 's/^ //' ;;
    shape)
      slh_refuse "SLH-DIAGRAM-SHAPE" ".claude/sdd.json declares diagram_command and it is not a string, so the command that generates the committed view cannot be read. Refusing rather than guessing. Write it as \"diagram_command\": \"<the command that prints one Mermaid block>\", or remove the key."
      return 1 ;;
    *) printf '' ;;
  esac
  return 0
}

slh_diagram_check_lockfile() { # slh_diagram_check_lockfile <proj> <base> <rev-or-"">
  local proj="$1" base="$2" rev="$3" cmd out rc gen committed n
  slh_diagram_switch_on "$proj" "$base" || return 0
  cmd="$(slh_diagram_command_for "$proj")" || { SLH_REFUSED=1; return 1; }
  [ -n "$cmd" ] || return 0
  out="$( ( cd "$proj" && eval "$cmd" ) 2>&1 )" && rc=0 || rc=$?
  if [ "$rc" != "0" ]; then
    slh_refuse "SLH-DIAGRAM-SHAPE" "the declared diagram_command ($(slh_bound name "$cmd")) does not run here (exit $rc), so the generated view cannot be compared to what is committed and this close proves nothing about it. Last output: $(slh_bound text "$(printf '%s\n' "$out" | tail -3)")"
    return 1
  fi
  if [ -z "$(printf '%s\n' "$out" | awk "$SLH_DIAGRAM_MERMAID_AWK")" ]; then
    slh_refuse "SLH-DIAGRAM-SHAPE" "the declared diagram_command ($(slh_bound name "$cmd")) ran and printed no Mermaid block, so there is nothing to compare against docs/diagrams/generated/. A command that emits no diagram is never a pass. Make it print the generated view on stdout inside a \`\`\`mermaid fence."
    return 1
  fi
  if [ -z "$rev" ]; then
    gen="$(git -C "$proj" ls-files --cached -- 'docs/diagrams/generated/*' 2>/dev/null || true)" # fail-open-ok: an empty list is the missing-view refusal below
  else
    gen="$(git -C "$proj" ls-tree -r --name-only "$rev" -- docs/diagrams/generated/ 2>/dev/null || true)" # fail-open-ok: as above
  fi
  n="$(printf '%s\n' "$gen" | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then
    slh_refuse "SLH-DIAGRAM-SHAPE" "this instance declares diagram_command and commits no generated view under docs/diagrams/generated/, so the lockfile has nothing to lock. Commit the command's output there, or remove diagram_command."
    return 1
  fi
  if [ "${n:-0}" -gt 1 ]; then
    slh_refuse "SLH-DIAGRAM-SHAPE" "this instance declares diagram_command and commits $n files under docs/diagrams/generated/ ($(slh_bound names "$gen")), and the contract is one command and one generated view. Refusing rather than guessing which file the command's output belongs to. Keep one file there, or drop the declaration."
    return 1
  fi
  if [ -z "$rev" ]; then committed="$(git -C "$proj" show ":$gen" 2>/dev/null || true)"; else committed="$(git -C "$proj" show "$rev:$gen" 2>/dev/null || true)"; fi # fail-open-ok: an unreadable view yields empty, which DIFFERS from the command's output and refuses, the accusing direction
  if [ "$(printf '%s\n' "$committed" | awk "$SLH_DIAGRAM_MERMAID_AWK")" != "$(printf '%s\n' "$out" | awk "$SLH_DIAGRAM_MERMAID_AWK")" ]; then
    slh_refuse "SLH-DIAGRAM-DRIFT" "$(slh_bound name "$gen") does not match what diagram_command ($(slh_bound name "$cmd")) prints, so the committed generated view is stale. The difference: $(slh_bound text "$(diff <(printf '%s\n' "$committed" | awk "$SLH_DIAGRAM_MERMAID_AWK") <(printf '%s\n' "$out" | awk "$SLH_DIAGRAM_MERMAID_AWK") 2>/dev/null | awk 'NR <= 20' | tr '\n' '~' | sed 's/~/ | /g')"). One edit fixes it: re-run the command and commit its output."
    return 1
  fi
  return 0
}

slh_rule_in_force() { # slh_rule_in_force <proj> <major.minor> -> 0 when the INDEX's .claude/sdd.json stamps that version or later
  # The close's own tree is the index this hook judges, as the audit's rule_in_force reads the
  # commit's own tree: one rule dated one way at both layers (spec 0175, decision 1), so an
  # upgraded instance is never refused for a close made before the rule existed.
  local v
  v="$(slh_index_show "$1" .claude/sdd.json | jq -r '(.plugin.version // "") | strings' 2>/dev/null || true)" # fail-open-ok: an unreadable stamp is the pre-rule exemption this function exists to state
  awk -v v="$v" -v want="$2" "$SLH_VERSION_AT_LEAST_AWK"
}

slh_close_review_check() { # slh_close_review_check <proj> <num> <spec-text> <carries-code 0|1> -> 1 after refusing by name
  # THE CLOSE REVIEW (spec 0175): the close-review block's LAST round, read by the one reader
  # the audit shares. The skip is the role paths' decision, never the reviewer's: a
  # SKIP-DOCS-ONLY block is accepted only on a change that brings no role-path file.
  local out tok
  slh_rule_in_force "$1" 2.11 || return 0
  out="$(printf '%s\n' "$3" | awk "$SLH_TEMPLATE_FENCE_AWK" | awk "$SLH_CLOSE_REVIEW_AWK")"
  tok="${out%% *}"
  case "$tok" in
    pass|accepted) return 0 ;;
    skip)
      [ "$4" = "1" ] || return 0
      slh_refuse "SLH-CLOSE-REVIEW-SKIP-REFUSED" "spec $2's close review reads SKIP-DOCS-ONLY, but this change brings a file under a declared role path. The skip is decided by the role paths, never by the reviewer or the session: it covers a close that touches no role path. Run the review through /setlist:checkpoint close."
      return 1 ;;
    fail)
      slh_refuse "SLH-CLOSE-REVIEW-FAIL" "spec $2's close review ends in a round reading FAIL. Fix what its findings name and let /setlist:checkpoint run the review again on the new diff (two rounds at most); after round 2 the decision is yours, written as the block's last line: verdict: ACCEPTED-BY-HUMAN followed by the ids of the round-2 findings you accept."
      return 1 ;;
    *)
      slh_refuse "SLH-NO-CLOSE-REVIEW" "spec $2 carries no usable close-review block (the reader said: ${out:-nothing}). Since plugin 2.11.0 a close carries, in its Closing report beside the qa-pass-1 block, the block /setlist:checkpoint writes from the close-reviewer agent: a round header (round 1 or round 2: PASS or FAIL), one <criterion>: PASS|PARTIAL|FAIL line per criterion, and each finding as <id> | <criterion or -> | BLOCKER|MAJOR|MINOR | <path>:<line> | <what> | <fix>; a close that touches no role path carries round 1: SKIP-DOCS-ONLY alone. A line that is none of these is refused, not skipped. Run the review through /setlist:checkpoint close."
      return 1 ;;
  esac
}

slh_verify_close() { # slh_verify_close <proj> <trunk> <what>
  local proj="$1" trunk="$2" what="$3"
  local staged spec_files role_paths closing_specs f num status_new status_old text

  staged="$(slh_staged_files "$proj")"
  # Nothing staged is nothing to judge. Note the direction: an EMPTY staged list
  # is the only thing that short-circuits, and it short-circuits to "fine"
  # because an empty commit carries no work to the trunk.
  [ -n "$staged" ] || return 0

  # fail-open-ok: no staged spec files leaves the closing set empty, so feature
  # code arriving with it triggers SLH-CLOSES-NO-SPEC. Empty accuses, not excuses.
  spec_files="$(printf '%s\n' "$staged" | grep -E '^specs/[0-9]+[a-z]*-[^/]*\.md$' || true)"
  # HISTORY: ruling LIB-62 (undated): THE STATUS IS CARRIED ACROSS THE SUBSHELL, and it was not.
  if ! role_paths="$(slh_role_paths "$proj")"; then
    SLH_REFUSED=1
    return 1
  fi

  # THE RECORD, OR THE PAGE (RP1, edition v1.12). A structured instance is one
  # whose index carries .claude/status.json: its close and chore facts are read
  # from the record and the page readers below DO NOT RUN. A legacy instance
  # takes the page path, byte-identical to what shipped before the record
  # existed. A record present at either end and malformed is a refusal here and
  # now, because every set computed below would be a guess.
  #
  # HISTORY: ruling LIB-63 (undated): THE ADOPTION COMMIT CLOSES NOTHING, by construction:
  local structured=0 record_new="" record_old="" newly_closed=""
  if slh_record_present "$proj" ""; then
    structured=1
    record_new="$(slh_record_show "$proj" "")"
    if [ "$(slh_record_verdict "$record_new")" != "ok" ]; then
      slh_refuse "SLH-RECORD-MALFORMED" ".claude/status.json in this commit is not a well-formed status record, so no close or chore fact can be read from it and this merge cannot be verified. Nothing falls back to the STATUS.md page: a fallback would let one syntax error buy back the frozen page readers' residual class. Fix the record (jq . .claude/status.json shows the syntax; Part 3 of the edition shows the grammar). Only /setlist:checkpoint writes this file."
      return 1
    fi
    if slh_record_present "$proj" HEAD; then
      record_old="$(slh_head_show "$proj" .claude/status.json)"
      if [ "$(slh_record_verdict "$record_old")" != "ok" ]; then
        slh_refuse "SLH-RECORD-MALFORMED" ".claude/status.json at HEAD is not a well-formed status record, so which specs this change NEWLY closes cannot be computed. Fix the record at HEAD before closing anything over it."
        return 1
      fi
    fi
    local __rec_new_closed __rec_old_closed __rn
    if ! __rec_new_closed="$(slh_record_closed "$record_new")"; then
      slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading .claude/status.json, so the closing set cannot be established. A reader that could not run has not read."
      return 1
    fi
    __rec_old_closed=""
    if [ -n "$record_old" ]; then
      if ! __rec_old_closed="$(slh_record_closed "$record_old")"; then
        slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading HEAD's .claude/status.json, so which specs were already closed cannot be established. A reader that could not run has not read."
        return 1
      fi
      for __rn in $__rec_new_closed; do
        grep -qxF -- "$__rn" <<< "$__rec_old_closed" && continue
        newly_closed="$newly_closed $__rn"
      done
    fi
  else
    # HISTORY: ruling LIB-64 (undated): LIVE TEXT AT THE SOURCE (2026-08 consolidation, the F2 class made a rule).
    status_new="$(slh_index_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
    status_old="$(slh_head_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
    newly_closed="$(slh_rows_newly_closed "$status_new" "$status_old")"
  fi

  # HISTORY: ruling LIB-65 (plugin v1.7): Which specs does this change CLOSE? A spec whose record entry (or, on the page path, whose row) reads closed now and did not before.
  closing_specs=""
  for num in $newly_closed; do
    # HISTORY: ruling LIB-66 (undated): SORT ORDER IS NOT A CHOICE OF SPEC (leg F6).
    f="$(printf '%s\n' "$spec_files" | grep -E "^specs/${num}-[^/]*\.md$" || true)" # fail-open-ok: no match leaves f empty and the index fallback below runs
    if [ -n "$f" ] && [ "$(printf '%s\n' "$f" | grep -c .)" -ne 1 ]; then
      slh_refuse "SLH-SPEC-DUPLICATE" "$(printf '%s\n' "$f" | grep -c .) files match specs/${num}-*.md in this change, so which one carries spec $num's Closing report is a guess: $(slh_bound names "$f"). Spec numbers must be unique. Rename the companion out of the specs/<number>-*.md namespace, or give it its own number."
      continue
    fi
    if [ -z "$f" ]; then
      # The row flipped but the file is not in this change: read it from the
      # index so the close conditions are checked against what the tree will
      # hold, rather than skipped because the author did not touch the file.
      f="$(slh_spec_path_for "$proj" "$num")"
    fi
    [ -n "$f" ] || {
      slh_refuse "SLH-CLOSES-NO-SPEC-FILE" "specs/STATUS.md marks spec $num CLOSED but no specs/${num}-*.md exists to verify. Add the spec file with its Closing report, or correct the row."
      continue
    }
    closing_specs="$closing_specs $num:$f"
  done

  # HISTORY: ruling LIB-67 (plugin 1.1.0): Is feature code arriving? Any staged path under a declared role.
  local carries_code=0 rp
  if [ -n "$role_paths" ]; then
    # QUOTED, read line by line (spec 0164, fix round 2, F3): `for rp in
    # $role_paths` split on whitespace AND expanded globs against the working
    # directory, so a declared `packages/*` became whatever happened to exist
    # beside the hook. slh_attest_walk already read this list the careful way.
    while IFS= read -r rp; do
      rp="$(slh_role_norm "$rp")"
      [ -n "$rp" ] || continue
      # HISTORY: ruling LIB-68 (plugin 1.1.0): A ROLE MAY NAME A FILE, not only a directory (1.1.0 final leg, F5).
      # A literal prefix, as the audit reads a role (spec 0169, E-e).
      if printf '%s\n' "$staged" | SLH_ROLE="$rp" awk 'index($0, ENVIRON["SLH_ROLE"] "/") == 1 || $0 == ENVIRON["SLH_ROLE"] { f = 1 } END { exit !f }'; then carries_code=1; break; fi
    done <<EOF
$role_paths
EOF
  fi

  # HISTORY: ruling LIB-69 (2026-08-02): THE CHORE ROUTE (v1.7 gate, F30).
  local closing_chores
  if [ "$structured" = "1" ]; then
    # The record's chore map, same before-and-after rule: a chore whose entry
    # reads done now and did not before. The adoption commit records nothing
    # here either, for the same both-directions-safe reason as the specs.
    local __rec_new_done __rec_old_done __rc
    if ! __rec_new_done="$(slh_record_done "$record_new")"; then
      slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading .claude/status.json's chore map. A reader that could not run has not read."
      return 1
    fi
    __rec_old_done=""
    closing_chores=""
    if [ -n "$record_old" ]; then
      if ! __rec_old_done="$(slh_record_done "$record_old")"; then
        slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading HEAD's .claude/status.json chore map. A reader that could not run has not read."
        return 1
      fi
      for __rc in $__rec_new_done; do
        grep -qxF -- "$__rc" <<< "$__rec_old_done" && continue
        closing_chores="$closing_chores $__rc"
      done
      closing_chores="${closing_chores# }"
    fi
  else
    closing_chores="$(slh_chores_completed "$status_new" "$status_old")"
  fi

  # THE PAGE FALLBACK ON THE MERGED BRANCH (spec 0173, item 7; 0169's E-d, from 0167's E-e).
  # A branch cut BEFORE the instance adopted .claude/status.json records a chore on its own
  # page, and the index's record, which the trunk side carries, completes nothing: this hook
  # refused that merge while the audit accepted it at push, because the audit keeps the page
  # path on the merged parent for a two-parent merge whose own record completes nothing (0167,
  # decision 6). The hook now asks the same question of the same bytes: the one merged head,
  # when it carries no record, and its archive lines against the trunk side's page. Two layers,
  # one reading; an octopus has no single head and is refused on its own ground.
  if [ "$structured" = "1" ] && [ "$carries_code" = "1" ] && [ -z "$closing_specs" ] && [ -z "$closing_chores" ]; then
    local __mh
    __mh="$(slh_merged_head "$proj")"
    if [ -n "$__mh" ] && ! slh_record_present "$proj" "$__mh"; then
      closing_chores="$(slh_chores_completed "$(git -C "$proj" show "$__mh:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK")" "$(slh_head_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")")" # fail-open-ok: an unreadable page completes nothing, and the refusal below still fires
    fi
  fi

  if [ "$carries_code" = "1" ] && [ -z "$closing_specs" ] && [ -z "$closing_chores" ]; then
    if [ "$structured" = "1" ]; then
      slh_refuse "SLH-CLOSES-NO-SPEC" "$what brings feature code to $trunk without closing any spec that was not already closed in .claude/status.json, and without a chore newly recorded done there. Work reaches the trunk through a closed spec or a completed chore, and /setlist:checkpoint is what records both. If this closes a spec cut before the record existed, run checkpoint first to record the spec, then close; if this is deliberate maintenance, have checkpoint record the chore in this same commit."
    else
      slh_refuse "SLH-CLOSES-NO-SPEC" "$what brings feature code to $trunk without closing any spec that was not already CLOSED, and without recording a completed chore. Work reaches the trunk through a closed spec or a recorded chore. If this is deliberate maintenance, add its archive line to specs/STATUS.md in this same commit, in the form: - CHORE-007: DONE $(date +%F). <what changed>"
    fi
  fi

  # Every spec this change closes must satisfy the close conditions, read from
  # the index rather than from a branch tip.
  local entry __owns_list="" __owns_declaring=0 __owns_blockless=0 __owns_shape_bad=0
  # THE SWITCH, READ ONCE, IN THE FIRST PARENT'S TREE (ruling S2). HEAD is the
  # first parent of the commit this index is about to become.
  local __armed=0
  slh_diagram_switch_on "$proj" HEAD && __armed=1
  for entry in $closing_specs; do
    num="${entry%%:*}"; f="${entry#*:}"
    text="$(slh_index_show "$proj" "$f")"

    # THE CLOSE IS THE STRONGEST POINT IN THE ATTESTATION CHAIN, and it is
    # nearly free: this function already knows which specs the change closes,
    # so requiring the approval to cover the spec's FINAL bytes costs one call.
    # A spec legitimately revised mid-build went ACTIVE -> REVISED -> ACTIVE
    # with Planner sign-off and checkpoint produced a NEW attestation on the
    # way back, so the legitimate path is the existing lifecycle and needs no
    # new ceremony here.
    # fail-open-ok: the refusal is recorded in SLH_REFUSED and decided by the
    # caller, so a non-zero return must not skip the four checks below.
    slh_attest_require "$proj" "$f" "$what" || true

    # THE DIAGRAM FIELD, COMPARED TO THE DIFF (edition v1.15, contract item 2).
    # Placed ABOVE the structured path's `continue` deliberately: the record and
    # the page disagree about where the close FACTS live, and they do not
    # disagree about where the diagram field lives, which is the Closing report
    # in both (the owner's ruling S1). One call site, both paths, so the two
    # cannot drift apart the way a gate and its backstop did in leg 5's F8.
    # fail-open-ok: the refusal is recorded in SLH_REFUSED by slh_refuse itself
    # and decided by the caller, so a non-zero return must not skip what follows.
    slh_diagram_check_field "$proj" HEAD "" "$num" "$text" "$staged" || true

    # THE CLOSE REVIEW (spec 0175), above the structured path's `continue` for the diagram
    # field's reason: the record carries three keys and no review (DE4 prices a fourth), so
    # both paths read the block from the one Closing report. Dated by the index's own
    # plugin.version inside the call. The forge check reaches this same line.
    # fail-open-ok: the refusal is recorded in SLH_REFUSED by slh_refuse itself and decided by
    # the caller, so a non-zero return must not skip what follows.
    slh_close_review_check "$proj" "$num" "$text" "$carries_code" || true

    # HISTORY: ruling LIB-70 (undated): THE CLOSE FACTS COME FROM THE RECORD on the structured path (RP1):
    if [ "$structured" = "1" ]; then
      local __facts __owns_out
      if ! __facts="$(slh_record_facts "$record_new" "$num")"; then
        slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading spec $num's close facts from .claude/status.json. A reader that could not run has not read."
        continue
      fi
      if [ "$__facts" != "ok" ]; then
        slh_refuse "SLH-RECORD-NO-CLOSE" "spec $num is newly closed in .claude/status.json without its close facts: the entry must carry status closed, qa_pass_1 ok, and diagram updated or no-impact, written by /setlist:checkpoint at the close. Run the close through checkpoint rather than editing the record by hand."
      fi
      # HISTORY: ruling LIB-71 (undated): The ownership declaration, gathered here and consumed after the loop when this landing is single-parent (design 8.2).
      __owns_out="$(slh_index_show "$proj" "$f" | awk "$SLH_OWNS_AWK")" || __owns_out="!read-failed"
      # HISTORY: ruling LIB-72 (2026-09-06): THE LITE TIER'S CAP (edition v1.14, P1, the owner's ruling 3 of 2026-09-06):
      if grep -q '^!lite-oversized$' <<< "$__owns_out"; then
        slh_refuse "SLH-LITE-OVERSIZED" "spec $num is declared Tier: lite and declares more than five files under Owns:. A lite spec is at most five files (Part 3 of the edition); the two honest exits are to drop the tier line (a full spec, judged exactly as before) or to split the work, both through /setlist:checkpoint. The tier is a claim about size, and a claim the close cannot honour is refused rather than reread."
        __owns_out="$(printf '%s\n' "$__owns_out" | grep -v '^!lite-oversized$')"
      fi
      if grep -q '^!' <<< "$__owns_out"; then
        if [ "$SLH_CLOSE_SINGLE_PARENT" = "1" ]; then
          slh_refuse "SLH-OWNS-MALFORMED" "spec $num declares ownership outside the grammar (a glob, a directory, a quoted or empty path, or an Owns: line below the Closing report heading). One verbatim repo-relative file per 'Owns: ' line, at column 0, inside the hashed range. The range ends at the FIRST line reading '## Closing report', fences included, because that byte-same cut is what attestation signs: a fenced or quoted copy of the Closing-report template ABOVE your declaration ends the range early, and the fix is one edit (move the declaration above the quote, or drop the quoted heading line). A declared set that cannot be enumerated is an exemption wearing a declaration. Fix the declaration through /setlist:checkpoint."
        fi
        __owns_shape_bad=1
      elif [ -z "$__owns_out" ]; then
        __owns_blockless=1
      else
        __owns_declaring=1
        __owns_list="$__owns_list
$__owns_out"
      fi
      continue
    fi

    # HISTORY: ruling LIB-73 (plugin 1.1.0): A FENCED EXAMPLE IS NOT A CLOSING REPORT.
    #
    # LOCKSTEP: byte-identical to trunk-audit.sh, asserted.
    # The value is defined once at the top of this file, because the lifecycle
    # detector reads it too (V19-F2).
    text="$(printf '%s\n' "$text" | awk "$SLH_TEMPLATE_FENCE_AWK")"

    if ! grep -qE "$SLH_CLOSING_REPORT_RE" <<< "$text"; then
      slh_refuse "SLH-NO-CLOSING-REPORT" "spec $num has no Closing report section; complete it and stage it before closing."
      continue
    fi

    if [[ "$(printf '%s\n' "$text" | awk "$SLH_QA_PASS1_AWK")" != "ok" ]]; then
      slh_refuse "SLH-NO-QA-VERDICT" "spec $num carries no usable QA Pass 1 verdict block. Part 6 requires a fenced qa-pass-1 block whose every line is <criterion>: PASS|PARTIAL|FAIL, the criterion a bare identifier with no spaces. The block must sit inside the Closing report section at fence depth zero: one nested inside a pasted-report fence is content, not a verdict, and a fenced example elsewhere neither satisfies nor poisons this check. A line inside that is not a verdict line is refused, not skipped, because skipping is how a sentence gets in. An HTML comment opened with <!-- and never closed refuses too, because the reader cannot see past it. Write the block at the left margin (three spaces of indent at most): the reader reads the document FLAT, and a block indented four or more spaces, including inside a numbered list item, is indented code."
    fi

    local diag answer
    # HISTORY: ruling LIB-74 (2026-08-29): A FIELD, NOT A SUBSTRING (1.1.0 adversarial review, F8).
    diag="$(printf '%s\n' "$text" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | awk 'NR == 1')"
    if [ -z "$diag" ]; then
      slh_refuse "SLH-NO-DIAGRAM-FIELD" "spec $num is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    else
      answer="${diag#*Architecture diagram:}"
      # HISTORY: ruling LIB-75 (undated): PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11).
      answer="$(printf '%s' "$answer" | sed 's/<[^>]*>//g')"
      # THE ARMED FORM IS AN ANSWER TOO (edition v1.15), and ONLY when armed.
      # `updated (<files>)` is the v1.15 spelling; on an instance with no
      # docs/diagrams/ it is not a form this edition recognises, and widening
      # the reader there would change what an unarmed instance accepts, which
      # is exactly what the absence differential forbids. So the widening is
      # gated on the same switch every other diagram byte is gated on.
      if ! grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)' <<< "$(printf '%s' "$answer" | sed 's/^[[:space:]]*//')" \
         && ! { [ "$__armed" = "1" ] && grep -qE '^updated[[:space:]]*\(' <<< "$(printf '%s' "$answer" | sed 's/^[[:space:]]*//')"; }; then
        slh_refuse "SLH-DIAGRAM-UNANSWERED" "spec $num's architecture-diagram field is unanswered; answer it 'updated in this commit' or 'no impact'$([ "$__armed" = "1" ] && printf ", or name the files this commit changed as 'updated (<files>)'")."
      fi
    fi
  done

  # NODE EVIDENCE AND THE LOCKFILE, ONCE PER CHANGE rather than once per spec:
  # both read the whole diagram surface and the whole generated view, so running
  # them inside the loop would repeat identical work and print a report twice for
  # a change closing two specs. The closing set is passed in, because whose node
  # a stale one is decides whether it refuses or reports (D11).
  # fail-open-ok: both record their own refusals through slh_refuse; the `|| true`
  # keeps a refusal from skipping the arm below it.
  slh_diagram_check_nodes "$proj" HEAD "" "$(printf '%s\n' $closing_specs | sed 's/:.*$//')" || true
  slh_diagram_check_lockfile "$proj" HEAD "" || true

  # HISTORY: ruling LIB-76 (undated): THE PER-FILE OWNERSHIP QUESTION AT THE SINGLE-PARENT LANDING (design 8.2), the refusing layer's early copy of the audit's NPAR<2 arm:
  if [ "$structured" = "1" ] && [ "$SLH_CLOSE_SINGLE_PARENT" = "1" ] && \
     [ "$__owns_blockless" = "0" ] && [ "$__owns_shape_bad" = "0" ] && \
     { [ "$__owns_declaring" = "1" ] || [ -n "$closing_chores" ]; }; then
    local __ch __cf __sf __owns_staged
    # HISTORY: ruling LIB-77 (plugin 2.4.0): The arm asks what ARRIVES on the trunk, so deletions are out of scope (2.4.0 leg F7):
    __owns_staged="$(slh_staged_files "$proj" d)"
    for __ch in $closing_chores; do
      __cf="$(printf '%s' "$record_new" | jq -r --arg id "$__ch" "$SLH_RECORD_CHORE_FILES_JQ" 2>/dev/null || true)" # fail-open-ok: no files declared covers nothing, it cannot widen
      [ -n "$__cf" ] && __owns_list="$__owns_list
$__cf"
    done
    while IFS= read -r __sf; do
      [ -n "$__sf" ] || continue
      # The same role test carries_code used, one file at a time; declared
      # paths match by EXACT bytes, never by fold or glob (PD9's class reads
      # as undeclared and refuses, the safe direction).
      # LINE BY LINE, as the library's other role loops read the list (spec 0169,
      # fix round 1, E-i): an unquoted `for` split a role holding a space, which
      # the stamp accepts, into two roles, and expanded a glob character.
      local __is_role=0 __rp2
      while IFS= read -r __rp2; do
        while [ "${__rp2#./}" != "$__rp2" ]; do __rp2="${__rp2#./}"; done
        __rp2="$(printf '%s' "$__rp2" | tr -s '/')"
        __rp2="${__rp2#/}"; __rp2="${__rp2%/}"
        [ -n "$__rp2" ] && [ "$__rp2" != "." ] || continue
        if printf '%s\n' "$__sf" | SLH_ROLE="$__rp2" awk 'index($0, ENVIRON["SLH_ROLE"] "/") == 1 || $0 == ENVIRON["SLH_ROLE"] { f = 1 } END { exit !f }'; then __is_role=1; break; fi
      done <<SLHOWNSROLES
$role_paths
SLHOWNSROLES
      [ "$__is_role" = "1" ] || continue
      if ! grep -qxF -- "$__sf" <<< "$__owns_list"; then
        slh_refuse "SLH-OWNS-UNDECLARED" "$(slh_bound name "$__sf") is a role-path file this close does not declare. A declaring close is audited file by file against its declared set, so a whole commit can no longer be exempted by one record flip. Two honest exits: declare the file through /setlist:checkpoint (under attestation custody that means re-approval, correctly), or take the --no-ff merge route, whose arm asks the provenance question instead."
      fi
    done <<EOF
$__owns_staged
EOF
  fi

  # HISTORY: ruling LIB-78 (undated): T1 at THIS layer, at BOTH landings (a true merge and a single-parent completion):
  SLH_OWNS_DECLARED=""
  if [ "$structured" = "1" ] && [ "$__owns_declaring" = "1" ] && [ "$__owns_shape_bad" = "0" ]; then
    SLH_OWNS_DECLARED="$(printf '%s\n' "$__owns_list" | grep . | tr '\n' ' ' | sed 's/ $//')" # fail-open-ok: an empty declared set is "nothing to compare", the design's own reading
    if [ -n "$SLH_CODEOWNERS_MODE" ] && [ -n "$SLH_OWNS_DECLARED" ]; then
      if slh_codeowners_load "$proj"; then
        # shellcheck disable=SC2086  # the declared set is space-separated by construction (Owns: forbids spaces)
        slh_owns_codeowners_check "$what" "$SLH_CODEOWNERS_MODE" email "$(git -C "$proj" config --get user.email 2>/dev/null || printf 'nobody')" $SLH_OWNS_DECLARED
      fi
    fi
  fi

  [ "$SLH_REFUSED" = "0" ]
}

# HISTORY: ruling LIB-79 (undated): The project's own gate command.
slh_gate_command_for() { # slh_gate_command_for <proj> <commit|close|push> -> prints the command (maybe empty); 1 after refusing
  local proj="$1" tier="$2" raw
  case "$tier" in commit|close|push) ;; *) slh_refuse "SLH-GATES-SHAPE" "an unknown gate tier \"$tier\" was asked for; the tiers are commit, close and push."; return 1 ;; esac
  # fail-open-ok: jq's status is carried below; an unreadable file refuses
  # through the callers' scaffolded rule rather than skipping.
  if ! raw="$(jq -r --arg t "$tier" '
        (.gates // null) as $g
        | if ($g == null) then
            (if $t == "commit" then "" else (.gate_command // "") end | if type == "string" then "ok " + . else "shape" end)
          elif (($g | type) != "object") then "shape"
          elif ((($g[$t] // "") | type) != "string") then "shape"
          else "ok " + ($g[$t] // "") end' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null)"; then
    printf ''
    return 0
  fi
  case "$raw" in
    "ok "*|ok) printf '%s' "${raw#ok}" | sed 's/^ //' ;;
    shape)
      slh_refuse "SLH-GATES-SHAPE" ".claude/sdd.json has a \"gates\" block that is not an object of string tiers (commit, close, push), so which command runs at which event cannot be read. Refusing rather than guessing: an unreadable declaration is worse than none. Write it as {\"commit\": \"\", \"close\": \"<the full gate>\", \"push\": \"<the full suite>\"}, or remove the block to read the single gate_command as before."
      return 1 ;;
    *) printf '' ;;
  esac
  return 0
}

slh_run_gate_command() { # slh_run_gate_command <proj> [commit|close|push]
  local proj="$1" tier="${2:-close}" cmd out rc last
  # HISTORY: ruling LIB-80 (plugin v1.7): AN EMPTY gate_command IS THE STAMPED DEFAULT, SO SKIPPING IT SILENTLY WAS A FAIL-OPEN IN THE DEFAULT STATE (v1.7 claims round 6, finding 3).
  #
  # Permissive on MISSING EVIDENCE was the one such path left in this file, and
  # it is the class the banner above says was removed. Before scaffolding the
  # skip is still right, so the flag decides.
  # fail-open-ok: a jq that cannot read the file yields empty, which the
  # scaffolded test below turns into a refusal rather than a skip.
  # THE READER'S REFUSAL MUST SURVIVE THE SUBSTITUTION (found by P2's red-first
  # pin, 2026-09-07, spec 0132 session 2). slh_gate_command_for refuses inside
  # this command substitution, a subshell, so its slh_refuse printed the
  # SLH-GATES-SHAPE line and set SLH_REFUSED in a shell that then exited: the
  # hook printed a refusal and ALLOWED. The caller's shell records the refusal
  # here, on the reader's status, so the message and the verdict agree.
  cmd="$(slh_gate_command_for "$proj" "$tier")" || { SLH_REFUSED=1; return 1; }
  if [ -z "$cmd" ]; then
    # THE commit TIER IS EMPTY BY DEFAULT AND THAT IS NOT A DECLARATION
    # MISSING: no commit-time gate is the ordinary case (design section 8), so
    # the scaffolded rule below applies to the close and push tiers only.
    [ "$tier" = "commit" ] && return 0
    local scaffolded
    scaffolded="$(jq -r '.scaffolded // false' "${SLH_SDD:-$proj/.claude/sdd.json}" 2>/dev/null || printf 'true')" # fail-open-ok: an unreadable file yields "true", which refuses rather than skips, and that is the safe direction here
    if [ "$scaffolded" = "true" ]; then
      slh_refuse "SLH-NO-GATE-COMMAND" "this instance is scaffolded but records no gate_command, so no suite ran for this close. Record the single command that runs the FULL suite as .gate_command in .claude/sdd.json, then merge."
      return 1
    fi
    return 0
  fi
  # The output is CAPTURED rather than discarded. A refusal that cannot say why
  # is the failure mode this check used to have: the operator runs the same
  # command in their own shell, watches it pass, and concludes the hook is
  # broken. The next thing they reach for is SETLIST_SKIP_HOOKS=1, which turns
  # one confusing message into a disabled boundary.
  # The `&& rc=0 || rc=$?` tail is not decoration: a bare assignment from a
  # failing command substitution ABORTS under `set -e`, which would turn this
  # refusal into a silent no-op in any caller that sets it. The shipped hooks do
  # not, today. Making the function safe anyway costs nothing and removes a trap
  # from whoever adds `set -e` later.
  out="$( ( cd "$proj" && eval "$cmd" ) 2>&1 )" && rc=0 || rc=$?
  [ "$rc" = "0" ] && return 0
  last="$(printf '%s\n' "$out" | tail -3)"
  # HISTORY: ruling LIB-81 (undated): 127 is "a command in the gate was not found", which is a DIFFERENT fact from "the suite failed":
  if [ "$rc" = "127" ]; then
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($(slh_bound name "$cmd")) could not RUN here (exit 127, a command was not found), so it proves nothing about this work. Hooks run it in a bare shell: if your toolchain lives in a virtualenv or a version-manager shim, put the activation inside gate_command itself. Last output: $(slh_bound text "$last")"
  else
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($(slh_bound name "$cmd")) does not pass (exit $rc), so this work is not ready to reach the trunk. Last output: $(slh_bound text "$last")"
  fi
  return 1
}
