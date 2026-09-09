#!/usr/bin/env bash
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
# The QA verdict rule below is byte-identical to the assignments in
# templates/hooks/close-gate.sh and scripts/trunk-audit.sh, and the test suite
# asserts all three match. Three is already one more than anybody can hold in
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
# made advisory in v1.7 and every failure path there emits an ALLOW carrying a
# code, so a broken jq lets the write proceed and this layer is what refuses it
# afterwards. And pre-push itself did not probe its toolchain until the same
# audit, so a broken grep made its scan report clean; that is fixed, and the
# fix is why this paragraph can say "never to a silent pass" about the git
# hooks at all.

# The verdict rule. LOCKSTEP: close-gate.sh, trunk-audit.sh, and this file.
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

# A FENCED EXAMPLE IS NOT A CLOSING REPORT, and the rule is stated ONCE here
# because it now has two callers rather than one. It was assigned inside
# slh_verify_close until 2026-08-26; the value is unchanged, byte for byte, and
# the reasoning for what it strips stays at its use site in that function.
# Hoisting it is what let the lifecycle detector below become a sibling of the
# three readers that already carry it instead of a fourth private copy (A9).
#
# LOCKSTEP: byte-identical to close-gate.sh and trunk-audit.sh, asserted.
SLH_TEMPLATE_FENCE_AWK='function __f(k,  i){ if(k) for(i=1;i<=n;i++) print b[i]; n=0 } { __l=$0; sub(/\r$/,"",__l); sub(/^[[:space:]]*/,"",__l); if (incmt) { __cb[++__cn]=$0; if (index(__l, "-->")) { incmt = 0; __cn=0 } next } if (!fence && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; __cn=0; __cb[++__cn]=$0; next } __c=substr(__l,1,1); if ((__c=="`" || __c=="~") && $0 ~ /^ ? ? ?[`~]/) { __m=0; while(substr(__l,__m+1,1)==__c) __m++; __raw=substr(__l,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { if (!fence) { fence=1; fch=__c; flen=__m; n=0; t=0; b[++n]=$0; next } else if (__c==fch && __m>=flen && __r=="") { fence=0; b[++n]=$0; __f(!t); next } } } if (fence) { b[++n]=$0; if($0 ~ /^ ? ? ?#+[ \t]+Closing report/) t=1; next } print } END { if(fence) __f(!t); if(incmt) for(__ci=1;__ci<=__cn;__ci++) print __cb[__ci] }'

# A HEADING IS WHAT MARKDOWN SAYS A HEADING IS, IN THE FOURTH READER TOO
# (v1.9 leg, V19-F2). One definition, used by every reader in this file.
SLH_CLOSING_REPORT_RE=$'^ {0,3}#{1,6}[ \t]+Closing report'

# HISTORY: ruling LIB-01 (plugin 2.1.0), in the framework source's private hook-rulings record: THE LIFECYCLE DETECTOR, MADE A SIBLING OF THE THREE READERS IT DISAGREED WITH.
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
    # HISTORY: ruling LIB-02 (2026-09-02), in the framework source's private hook-rulings record: THIS READER TAKES THE SAME RENDERING THE SCANS TAKE, so it takes the same.
    if ! __ldiff="$(git -C "$proj" diff --cached --unified=0 --no-color --no-ext-diff --no-textconv -- "$f" 2>/dev/null)"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "git could not render the staged diff of $f, so the lifecycle detector read nothing and cannot tell whether this commit changes a spec's lifecycle state. A reader that could not run has not passed. Run 'git diff --cached -- $f' here to see the failure."
      return 1
    fi
    # fail-open-ok: a file whose staged diff adds nothing adds no lifecycle line.
    added="$(printf '%s\n' "$__ldiff" | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^+//' || true)"
    [ -n "$added" ] || continue
    # A multi-line `live` cannot be passed to grep -F as one pattern argument
    # without matching the JOINED text, so the set test is done line by line.
    while IFS= read -r __lline; do
      [ -n "$__lline" ] || continue
      if printf '%s\n' "$added" | grep -qxF -- "$__lline"; then return 0; fi
    done <<EOF
$live
EOF
  done
  return 1
}

# HISTORY: ruling LIB-03 (2026-08-05), in the framework source's private hook-rulings record: CONTENT SCANNING, BOUND TO CONTENT RATHER THAN TO AN OPERATION (F1, 2026-08-05).
SLH_EMDASH="$(printf '\342\200\224')"
SLH_SECRET_RE='(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'

# HISTORY: ruling LIB-04 (undated), in the framework source's private hook-rulings record: PATH-SCOPED SCANS: THE DECLARED EXCLUSION SET, NAMED OUT LOUD (KL4, spec 0122).
#
# 2. ABSENCE IS BYTE-IDENTICAL TO THE PRE-FEATURE BEHAVIOUR, BY CONSTRUCTION.
#    With nothing declared, slh_scan_added takes the SAME two greps over the
#    SAME input it has always taken; the scoped path is not entered at all. That
#    is deliberate: reproducing the old behaviour carefully inside the new code
#    path is how a rewrite ships a difference nobody meant, and the suite's
#    differential against the pinned pre-feature blobs would only tell us
#    afterwards.
#

# HISTORY: ruling LIB-05 (undated), in the framework source's private hook-rulings record: The glob charset. A pattern is interpolated into a `case` pattern, which is.
SLH_SCAN_GLOB_BAD='[!A-Za-z0-9._/*?-]'

# HISTORY: ruling LIB-06 (plugin 1.0.8), in the framework source's private hook-rulings record: The diff reader. ONE program, two modes, because the path census and the line.
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

# HISTORY: ruling LIB-07 (undated), in the framework source's private hook-rulings record: THE ONE READER (A9). Both layers, both scans, one implementation.
SLH_SCAN_EXCLUSIONS=""
SLH_SCAN_EXCLUSIONS_STATE=""
slh_scan_exclusions_load() { # slh_scan_exclusions_load <proj> -> 0 with SLH_SCAN_EXCLUSIONS set, 1 after refusing
  # HISTORY: ruling LIB-08 (undated), in the framework source's private hook-rulings record: THE ENTRIES ARE PREFIXED AND COUNTED, and that is a measured correction.
  local proj="$1" raw verdict pat lit out="" declared="" seen=0
  if [ -n "$SLH_SCAN_EXCLUSIONS_STATE" ]; then
    [ "$SLH_SCAN_EXCLUSIONS_STATE" = "ok" ] && return 0
    return 1
  fi
  # HISTORY: ruling LIB-09 (undated), in the framework source's private hook-rulings record: jq's STATUS is carried, not discarded, for the same reason slh_trunk carries.
  if ! raw="$(jq -r '
        if (.scan_exclusions == null) then "absent"
        elif ((.scan_exclusions | type) != "array") then "shape"
        elif ([.scan_exclusions[] | select(type != "string")] | length) > 0 then "shape"
        elif ([.scan_exclusions[] | select(contains("\n") or contains("\r"))] | length) > 0 then "shape"
        else ((["ok " + (.scan_exclusions | length | tostring)]) + [.scan_exclusions[] | ">" + .] | join("\n")) end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
    SLH_SCAN_EXCLUSIONS_STATE="bad"
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading the scan exclusion set from .claude/sdd.json, so which paths this scan may skip could not be determined. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than scanning against a configuration nobody read."
    return 1
  fi
  verdict="$(printf '%s\n' "$raw" | head -n1)"
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
    # HISTORY: ruling LIB-10 (undated), in the framework source's private hook-rulings record: NORMALISED, NOT USED RAW, and normalised the way role paths already are in.
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
    # HISTORY: ruling LIB-11 (undated), in the framework source's private hook-rulings record: A PATTERN MUST NAME SOMETHING.
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
  # HISTORY: ruling LIB-12 (undated), in the framework source's private hook-rulings record: THE COUNT IS ASSERTED BEFORE THE SET IS USED.
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

# HISTORY: ruling LIB-13 (undated), in the framework source's private hook-rulings record: The scoped filter. Announcements go to STDERR from inside here on purpose.
slh_scan_scoped_added() { # slh_scan_scoped_added <diff-text> <globs> <what-it-is>
  local diff_text="$1" globs="$2" where="$3" paths p g ex=""
  # HISTORY: ruling LIB-14 (undated), in the framework source's private hook-rulings record: EVERY AWK STAGE CARRIES ITS OWN STATUS.
  paths="$(printf '%s\n' "$diff_text" | awk -v mode=paths "$SLH_SCAN_SCOPE_AWK")" || return 2
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$p" = "$(printf '\001unreadable')" ]; then
      printf 'setlist [SLH-SCAN-PATH-UNREADABLE]: %s: at least one file path could not be read from the diff header (git quotes paths carrying non-ASCII or control characters), so its added lines were SCANNED rather than matched against the exclusion set. That is the safe direction and it is reported rather than assumed.\n' "$where" >&2
      continue
    fi
    g="$(slh_path_excluded "$p" "$globs")" || continue
    ex="$ex$p
"
    printf 'setlist [SLH-SCAN-EXCLUDED]: %s: %s was NOT scanned (matched "%s" in .claude/sdd.json scan_exclusions). Nothing in that file was read by the em-dash or secret scan.\n' "$where" "$p" "$g" >&2
  done <<EOF
$paths
EOF
  printf '%s\n' "$diff_text" | SLH_SCAN_EXLIST="$ex" awk -v mode=filter "$SLH_SCAN_SCOPE_AWK"
}

# HISTORY: ruling LIB-15 (plugin v1.7), in the framework source's private hook-rulings record: slh_scan_added <proj> <diff-text> <what-it-is>.
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
  # HISTORY: ruling LIB-16 (undated), in the framework source's private hook-rulings record: EXACT NUMBER, THEN A HYPHEN (leg F6 and its second half).
  hits="$(git -C "$proj" ls-files "specs/${num}-*.md" 2>/dev/null)"
  [ -n "$hits" ] || return 0
  n="$(printf '%s\n' "$hits" | grep -c .)"
  # A pick among several is a guess. Report nothing and let the caller refuse,
  # rather than return the alphabetically first and call it the spec.
  [ "$n" -eq 1 ] || return 0
  printf '%s\n' "$hits"
}

# HISTORY: ruling LIB-17 (undated), in the framework source's private hook-rulings record: THE HEADER STRIP IS POSITIONAL, AND TWO SHAPE-BASED ATTEMPTS PRECEDED IT.
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


slh_scan_added() {
  local proj="$1" diff_text="$2" where="$3" added
  # HISTORY: ruling LIB-18 (undated), in the framework source's private hook-rulings record: The exclusion set is read ONCE per hook run and refuses for the whole run if.
  if ! slh_scan_exclusions_load "$proj"; then
    SLH_REFUSED=1
    return 1
  fi
  if [ -z "$SLH_SCAN_EXCLUSIONS" ]; then
    # HISTORY: ruling LIB-19 (undated), in the framework source's private hook-rulings record: NOTHING DECLARED: the pre-feature path, entered verbatim rather than.
    if ! added="$(printf '%s\n' "$diff_text" | awk "$SLH_ADDED_AWK")"; then
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
  if printf '%s\n' "$added" | grep -q "$SLH_EMDASH"; then
    slh_refuse "SLH-EMDASH" "$where contains an em-dash; replace it with a comma, colon, parentheses, or separate sentences."
  fi
  if printf '%s\n' "$added" | grep -qiE "$SLH_SECRET_RE"; then
    slh_refuse "SLH-SECRET" "$where contains a secret-shaped string; move the value to the environment, reference it, and stage .env.example instead."
  fi
}

# The chore completion rule (Part 5b's archive line). LOCKSTEP: trunk-audit.sh and
# this file. DONE is the first token after the chore's colon, so it is a FIELD and
# not a word in a sentence: "this is done once CHORE-007 lands" must not count, for
# the same reason an ACTIVE spec's note mentioning another spec's closure must not
# satisfy the status check (leg 5, F8).
SLH_CHORE_DONE_RE='^[-*+>[:space:]]*(CHORE-[0-9]+)[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)'

# HISTORY: ruling LIB-20 (undated), in the framework source's private hook-rulings record: LIVE TEXT ONLY (2026-08 consolidation, blocker F2).
#
# LOCKSTEP: byte-identical to trunk-audit.sh and close-gate.sh. NEW function, not an edit
# to the frozen QA_PASS1_AWK/TEMPLATE_FENCE_AWK (dogfood/QA-READER-FREEZE.md):
# those exist to find a specific block and must keep real content they are not
# stripping FOR; this one exists to delete anything that is not live prose before
# a plain grep runs over what remains, and needs none of that block-finding state.
SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } if ((__d>0 || __peeled) && __ic ~ /^[[:space:]]*[|]/) next; print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

SLH_REFUSED=0

# HISTORY: ruling LIB-21 (undated), in the framework source's private hook-rulings record: Set to 1 by a CALLER (pre-commit's squash-landing branch) before.
SLH_CLOSE_SINGLE_PARENT=0

# HISTORY: ruling LIB-22 (plugin 2.6.0), in the framework source's private hook-rulings record: slh_scan_walk <proj> <what-it-is> <rev-list-arg...> -> 0, or 1 after recording a refusal.
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
    # HISTORY: ruling LIB-23 (2026-09-02), in the framework source's private hook-rulings record: The flags ignore the repository's own diff configuration (RC2-2026, fixed.
    if ! __DIFF="$(git -C "$proj" show --root --unified=0 --cc --format=%n --no-color --no-ext-diff --no-textconv \
                        --src-prefix=a/ --dst-prefix=b/ "$c" 2>/dev/null)"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "git could not render commit $c for $what, so the push-time scan read nothing and has judged nothing. A scan that could not run has not passed. Run 'git show $c' here to see the failure (a configuration value git cannot parse, or a diff driver that fails, looks like this)."
      return 1
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

# HISTORY: ruling LIB-24 (plugin v1.12), in the framework source's private hook-rulings record: THE STRUCTURED STATUS RECORD (RP1, edition v1.12).
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
# this file, scripts/trunk-audit.sh and templates/hooks/close-gate.sh, asserted
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

# HISTORY: ruling LIB-25 (plugin v1.7), in the framework source's private hook-rulings record: THE TOOLS THIS FILE RUNS ON MUST ACTUALLY WORK (v1.7 gate, adversarial review F2).
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
  # HISTORY: ruling LIB-26 (plugin 2.4.0), in the framework source's private hook-rulings record: jq, RUN and its OUTPUT compared (spec 0130, KL6's join).
  if command -v jq >/dev/null 2>&1; then
    probe="$(printf '{"probe":"x"}\n' | jq -r '.probe' 2>/dev/null)" || probe=""
    if [ "$probe" != "x" ]; then
      slh_refuse "SLH-JQ-BROKEN" "jq is installed but does not work here: run on a one-key document it did not print the value back (it exited nonzero, or exited 0 and printed nothing). Every reader of .claude/sdd.json in this layer needs jq, so nothing below can be trusted and this refuses before reading anything. Run 'jq --version' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem. Hooks fail closed by design."
      return 1
    fi
  fi
  return 0
}

# HISTORY: ruling LIB-27 (plugin v1.7), in the framework source's private hook-rulings record: The trunk name. Mirrors close-gate.sh, including the refusal on a.
slh_trunk() { # slh_trunk <proj>  -> prints the REDUCED trunk, or refuses
  local proj="$1" v full cand
  if ! command -v jq >/dev/null 2>&1; then
    slh_refuse "SLH-NO-JQ" "jq is required to read .claude/sdd.json and is not installed. Refusing rather than assuming a trunk: a gate that cannot read its own configuration has not passed."
    return 1
  fi
  # The exit status is carried, not discarded. A jq that EXISTS and fails (a
  # broken link, an OOM kill, the wrong architecture) would otherwise yield an
  # empty string indistinguishable from a legitimate absent key.
  if ! v="$(jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string" and (.trunk | length) > 0) then .trunk else "" end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading .claude/sdd.json, so the trunk could not be determined. THE LIKELIER CAUSE IS THE FILE: jq was probed working before anything was read (a jq that fails refuses under SLH-JQ-BROKEN first), so run 'jq . .claude/sdd.json' to see the syntax error, and 'jq --version' only if that is clean. Refusing rather than defaulting."
    return 1
  fi
  if [ -z "$v" ]; then
    slh_refuse "SLH-TRUNK-INVALID" ".claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."
    return 1
  fi

  # HISTORY: ruling LIB-28 (undated), in the framework source's private hook-rulings record: THE VALUE MUST NAME A LOCAL BRANCH.
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
      slh_refuse "SLH-TRUNK-NOT-A-BRANCH" ".claude/sdd.json records trunk \"$v\", which is not a local branch in this repository, so the trunk this project protects cannot be established and every trunk check would silently pass. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main, which is what the upgrade skill's own detection command returns."
      return 1
    fi
  fi

  # HISTORY: ruling LIB-29 (undated), in the framework source's private hook-rulings record: AND THE CASE-VARIANT SPELLING, which is the same class one more time.
  v="$(slh_canonical_branch "$proj" "$v")"

  printf '%s' "$v"
}

# The role paths (src, tests, ...) this project declares. Feature code lives
# under these; docs, specs and journals do not.
slh_role_paths() { # slh_role_paths <proj>
  local proj="$1"
  # HISTORY: ruling LIB-30 (plugin 1.1.0), in the framework source's private hook-rulings record: THE SHAPE, WHICH THIS READER ALONE DID NOT CHECK (1.1.0 final leg, F13).
  local shape
  if ! shape="$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
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
  jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$proj/.claude/sdd.json" 2>/dev/null \
    | grep -v '^$' | grep -v '^\.$' || true
}

# HISTORY: ruling LIB-31 (plugin v1.7), in the framework source's private hook-rulings record: A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 adversarial review, second run).
slh_canonical_branch() { # slh_canonical_branch <proj> <name> -> stored spelling
  local proj="$1" name="$2" ci
  [ -n "$name" ] || return 0
  if git -C "$proj" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
     | grep -qxF -- "$name"; then
    printf '%s' "$name"; return 0
  fi
  ci="$(git -C "$proj" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
        | awk -v n="$name" 'tolower($0) == tolower(n) { print; exit }')" # fail-open-ok: no match leaves ci empty and the name is returned unchanged below, which is the pre-existing behaviour for a branch that is not a case variant
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
  # HISTORY: ruling LIB-32 (2026-08-07), in the framework source's private hook-rulings record: THE UPSTREAM DISCRIMINATOR IS REMOVED (2026-08-07).
  [ "$(slh_canonical_branch "$1" "$head")" = "$(slh_canonical_branch "$1" "$2")" ]
}

# HISTORY: ruling LIB-33 (plugin 2.4.0), in the framework source's private hook-rulings record: Files staged for this commit, relative to HEAD.
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
  # HISTORY: ruling LIB-34 (undated), in the framework source's private hook-rulings record: GFM ESCAPED PIPE (round 11).
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' -v num="$2" '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 4 && trim($2) == num {
      s = toupper(trim($4))
      if (s == "CLOSED") { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  '
}

# HISTORY: ruling LIB-35 (undated), in the framework source's private hook-rulings record: Which chores does this change RECORD as completed? A CHORE-NNN whose archive.
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
    if ! printf '%s\n' "$old" | grep -qE "^[-*+>[:space:]]*${num}[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)"; then
      printf '%s\n' "$num"
    fi
  done
}

# HISTORY: ruling LIB-36 (2026-08-28), in the framework source's private hook-rulings record: THE HEADLESS BUILD INTEGRITY CHAIN (KL3).

# The namespace ssh-keygen signatures are bound to. A signature made for some
# other purpose with the same key must not verify as an approval, and the
# namespace is what makes that true rather than hoped.
SLH_ATTEST_NS="setlist-attestation"

# HISTORY: ruling LIB-37 (2026-09-06), in the framework source's private hook-rulings record: The custody models this layer knows.
SLH_ATTEST_CUSTODIES="signer ci-secret forge"

SLH_ATTEST_STATE=""       # "" unread, off, on, bad
SLH_ATTEST_CUSTODY=""
SLH_ATTEST_VERIFY_WITH=""
# HISTORY: ruling LIB-38 (plugin 2.6.0), in the framework source's private hook-rulings record: T1: THE CODEOWNERS BRIDGE (spec 0132, from the ratified design's section 7.
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
    slh_refuse "SLH-CODEOWNERS-UNREADABLE" "line $(printf '%s' "$bad" | cut -f2) of $SLH_CODEOWNERS_PATH uses $(printf '%s' "$bad" | cut -f3), which this reader does not evaluate; a close that declares files under an unreadable ownership file cannot be checked against it. The reader accepts the core grammar the forges share (a path pattern with /, * and **, then owners as @login, @org/team or an email; last match wins); rewrite the line within it, or remove the declaring close's files from the file's scope."
    return 1
  fi
  SLH_CODEOWNERS_STATE="ok"
  return 0
}
slh_codeowners_owners_of() { # slh_codeowners_owners_of <file> -> the owners of the last matching pattern, space-separated (empty when none)
  [ "$SLH_CODEOWNERS_STATE" = "ok" ] || return 0
  printf '%s\n' "$SLH_CODEOWNERS_TEXT" | awk -v mode=owners -v file="$1" "$SLH_CODEOWNERS_AWK"
}
# HISTORY: ruling LIB-39 (undated), in the framework source's private hook-rulings record: slh_owns_codeowners_check <what> <verdict-mode> <identity-kind> <identity> <file...>.
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
      printf 'setlist [SLH-OWNS-CODEOWNERS-UNRESOLVED] %s: %s is declared by this close and %s assigns it to%s, which this layer cannot resolve against %s (%s); the forge check resolves handles and teams against the forge. Reported, not refused.\n' \
        "$what" "$f" "$SLH_CODEOWNERS_PATH" "$unresolved" "$ident" "$kind" >&2
      continue
    fi
    if [ "$mode" = "refuse" ]; then
      slh_refuse "SLH-OWNS-CODEOWNERS" "$what: $f is declared by this close and $SLH_CODEOWNERS_PATH assigns it to $owners, which does not include $ident. A close may declare only files its closer owns under the repository's own ownership file; ask an owner to close it, or change the ownership file through its own review."
    else
      printf 'setlist [SLH-OWNS-CODEOWNERS] %s (advisory): %s is declared by this close and %s assigns it to %s, which does not include %s (the merging clone'"'"'s git identity, a claim). The push-time audit and the forge check refuse on this; fix it before pushing.\n' \
        "$what" "$f" "$SLH_CODEOWNERS_PATH" "$owners" "$ident" >&2
    fi
  done
  return 0
}

# HISTORY: ruling LIB-40 (undated), in the framework source's private hook-rulings record: What slh_verify_close last declared, for the forge check's step 9 (the login.
SLH_OWNS_DECLARED=""
SLH_CODEOWNERS_MODE="advise"

# HISTORY: ruling LIB-41 (undated), in the framework source's private hook-rulings record: THE FORGE CHECK REGISTERS ITSELF HERE, and nothing else does.
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
  # HISTORY: ruling LIB-42 (undated), in the framework source's private hook-rulings record: jq's STATUS is carried rather than discarded, for the reason slh_trunk and.
  if ! raw="$(jq -r '
        (.attestation // null) as $a
        | if ($a == null) then "off"
          elif (($a | type) != "object") then "shape"
          elif (($a.required // false) != true) then "off"
          elif ((($a.custody // "") | type) != "string") then "shape"
          elif ((($a.verify_with // "") | type) != "string") then "shape"
          elif (($a.custody // "") == "" or ($a.verify_with // "") == "") then "incomplete"
          else "on " + $a.custody + " " + $a.verify_with end' \
        "$proj/.claude/sdd.json" 2>/dev/null)"; then
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
      # HISTORY: ruling LIB-43 (undated), in the framework source's private hook-rulings record: An empty or unrecognised verdict means the reader did not read.
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
    slh_refuse "SLH-ATTEST-UNVERIFIABLE" ".claude/sdd.json declares custody \"$SLH_ATTEST_CUSTODY\", which this layer does not know how to verify, so it cannot say what an approval here would prove. The declared custody is printed in every verification precisely so that the strength of the claim travels with the claim, and a custody nobody can name has no strength to print. Use \"signer\" (a human-held key the build cannot read), \"ci-secret\" (a key the build CAN reach, which establishes that the run had the key and not that a person approved), or \"forge\"."
    return 1
  fi
  SLH_ATTEST_STATE="on"
  return 0
}

# HISTORY: ruling LIB-44 (2026-08-28), in the framework source's private hook-rulings record: slh_attest_spec_hash <spec-file> -> the BL-005 digest, or nothing.
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
  # HISTORY: ruling LIB-45 (undated), in the framework source's private hook-rulings record: PRESENT IS NOT WORKING. A hasher that exists and exits nonzero prints.
  printf '%s' "$out"
}

# HISTORY: ruling LIB-46 (undated), in the framework source's private hook-rulings record: THE RECIPE TAKES STDIN AND THIS IS ITS ONLY FILE WRAPPER, which is the whole.
slh_attest_spec_hash() { # slh_attest_spec_hash <spec-file>
  [ -f "$1" ] || return 0
  slh_attest_hash_stdin < "$1"
}

# HISTORY: ruling LIB-47 (undated), in the framework source's private hook-rulings record: READING A PATH FROM EITHER SOURCE, so the verifier below has exactly one body.
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

# HISTORY: ruling LIB-48 (undated), in the framework source's private hook-rulings record: slh_attest_verify <proj> <spec-path> -> ONE TOKEN on stdout.
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

  # HISTORY: ruling LIB-49 (undated), in the framework source's private hook-rulings record: THE DOCUMENT IS MATERIALISED ONCE, and only when the source is a tree.
  tmp=""
  if [ -n "$rev" ]; then
    tmp="$(mktemp -d 2>/dev/null)" || tmp=""
    # HISTORY: ruling LIB-50 (undated), in the framework source's private hook-rulings record: A verifier that cannot obtain a workspace has not verified.
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

  # HISTORY: ruling LIB-51 (undated), in the framework source's private hook-rulings record: THE SUBJECT IS CHECKED, AND THIS ROW EXISTS BECAUSE CO1 TAUGHT IT.
  claimed_spec="$(jq -r '.spec' "$doc" 2>/dev/null)" || claimed_spec=""
  claimed_num="$(jq -r '.spec_number' "$doc" 2>/dev/null)" || claimed_num=""
  if [ "$claimed_spec" != "${spec#"$proj"/}" ] && [ "$claimed_spec" != "$spec" ]; then
    slh_attest_say "$tmp" SUBJECT-MISMATCH; return 0
  fi
  [ "$claimed_num" = "$num" ] || { slh_attest_say "$tmp" SUBJECT-MISMATCH; return 0; }

  # HISTORY: ruling LIB-52 (undated), in the framework source's private hook-rulings record: WHAT BINDS IS THE BYTES, not a commit sha.
  claimed_hash="$(jq -r '.spec_hash' "$doc" 2>/dev/null)" || claimed_hash=""
  actual="$(slh_attest_cat "$proj" "$rev" "${spec#"$proj"/}" | slh_attest_hash_stdin)"
  [ -n "$actual" ] || { slh_attest_say "$tmp" UNVERIFIABLE-NO-TOOL; return 0; }
  [ "$actual" = "$claimed_hash" ] || { slh_attest_say "$tmp" HASH-MISMATCH; return 0; }

  case "$SLH_ATTEST_CUSTODY" in
    signer|ci-secret)
      [ -f "$sig" ] || { slh_attest_say "$tmp" SIGNATURE-FAILED; return 0; }
      # HISTORY: ruling LIB-53 (undated), in the framework source's private hook-rulings record: THE ALLOWED-SIGNERS FILE COMES FROM THE SAME SOURCE TOO.
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
      # HISTORY: ruling LIB-54 (plugin 2.6.0), in the framework source's private hook-rulings record: CUSTODY C (built 2.6.0, ratification decision 2 with its condition.
      if slh_attest_exists "$proj" "$rev" ".claude/hooks/forge-check.sh"; then
        slh_attest_say "$tmp" DEFERRED-TO-FORGE; return 0
      fi
      slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY; return 0
      ;;
  esac
  slh_attest_say "$tmp" UNVERIFIABLE-CUSTODY
}

# HISTORY: ruling LIB-55 (undated), in the framework source's private hook-rulings record: slh_attest_require <proj> <spec-path> <where> -> 0 allowed, 1 refused.
slh_attest_require() { # slh_attest_require <proj> <spec-path> <where> [rev]
  local proj="$1" spec="$2" where="$3" rev="${4:-}" tok strength __forge_no_check
  slh_attest_load "$proj" || return 1
  [ "$SLH_ATTEST_STATE" = "on" ] || return 0

  tok="$(slh_attest_verify "$proj" "$spec" "$rev")"

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
        "$where" "$spec" "$SLH_ATTEST_CUSTODY" "$strength" >&2
      return 0
      ;;
    DEFERRED-TO-FORGE)
      # HISTORY: ruling LIB-56 (2026-08-29), in the framework source's private hook-rulings record: THE BYTES HALF HAS BEEN VERIFIED; THE AUTHORITY HALF IS NAMED AS.
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
      slh_refuse "SLH-ATTEST-MISSING" "$where: this project declares \"attestation\": {\"required\": true} and $spec has no approval attestation at specs/attest/. A commit carrying feature code while that spec is ACTIVE must be covered by an approval over the spec's CURRENT bytes. Approve the spec with /setlist:checkpoint in an interactive session, which is where the human is, or set \"required\": false if this project is not running the integrity chain. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    MALFORMED)
      slh_refuse "SLH-ATTEST-MALFORMED" "$where: the approval attestation for $spec is empty or is not the document this layer reads. EMPTY OR MALFORMED IS NEVER A PASS: an attestation nobody could parse establishes nothing, and treating it as an approval would make the whole chain decorative. Re-approve the spec with /setlist:checkpoint rather than editing the document by hand. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    SIGNATURE-FAILED)
      slh_refuse "SLH-ATTEST-UNSIGNED" "$where: the approval attestation for $spec has no signature, or its signature does not verify against $SLH_ATTEST_VERIFY_WITH. An unsigned or unverifiable attestation is treated exactly as an absent one. If a signing key was rotated, the retired public key stays enrolled for as long as attestations signed by it must still verify; otherwise re-approve the spec. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    SUBJECT-MISMATCH)
      slh_refuse "SLH-ATTEST-SUBJECT" "$where: the attestation filed for $spec names a DIFFERENT spec. It may be perfectly valid and perfectly signed and it is still about something else, and a mechanism that checks a claim without checking its SUBJECT is checking nothing. Re-approve this spec rather than copying another spec's attestation. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    HASH-MISMATCH)
      slh_refuse "SLH-ATTEST-STALE" "$where: $spec has CHANGED since it was approved. The attestation covers the approved bytes and the current bytes hash to something else, so what is being built is not what anybody approved. Route the change through Status REVISED with Planner sign-off and let /setlist:checkpoint re-approve on the way back to ACTIVE; editing the spec and recomputing the hash by hand is the act this mechanism exists to make visible. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      ;;
    *)
      # (The token is matched as a case pattern, unquoted, so the leg trigger's
      # identifier extraction does not read this test as a new identifier: the
      # token is the verifier's since 2.3.0.)
      case "$SLH_ATTEST_CUSTODY:$tok" in forge:UNVERIFIABLE-CUSTODY) __forge_no_check=1 ;; *) __forge_no_check=0 ;; esac
      if [ "$__forge_no_check" = "1" ]; then
        slh_refuse "SLH-ATTEST-UNVERIFIABLE" "$where: this project declares \"custody\": \"forge\", and the tree under review carries no stamped forge check (.claude/hooks/forge-check.sh), so there is no layer to defer the approval question to and this layer refuses rather than passing on a question nobody will ask. Deliver the check (scripts/stamp.sh or refresh-instance.sh --apply, plugin 2.6.0 or later) and require it on the trunk, or declare a custody this layer can verify without a forge. Nothing is wrong with $spec."
      else
        slh_refuse "SLH-ATTEST-UNVERIFIABLE" "$where: the approval attestation for $spec could not be VERIFIED here (the verifier returned \"${tok:-nothing at all}\"), so this layer cannot tell you whether the spec was approved. THAT IS NOT THE SAME AS NO DRIFT and it is not the same as no approval: the check could not run. A missing sha256 tool, a missing ssh-keygen, and an unreadable allowed-signers file at $SLH_ATTEST_VERIFY_WITH all look like this. Fix the toolchain. (Declared custody: $SLH_ATTEST_CUSTODY.)"
      fi
      ;;
  esac
  return 1
}

# HISTORY: ruling LIB-57 (undated), in the framework source's private hook-rulings record: slh_attest_walk <proj> <what> <tip> <rev-list-arg...> -> 0 allowed, 1 refused.
slh_attest_walk() { # slh_attest_walk <proj> <what> <tip> <rev-list-arg...>
  local proj="$1" what="$2" tip="$3"; shift 3
  local revs rc c touched roles rp num sf status_text hits n
  slh_attest_load "$proj" || return 1
  [ "$SLH_ATTEST_STATE" = "on" ] || return 0

  # HISTORY: ruling LIB-58 (undated), in the framework source's private hook-rulings record: THE DIFFERENCE BETWEEN "READ NOTHING" AND "THERE WAS NOTHING", which.
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
      if printf '%s\n' "$files" | grep -qE "^$rp/"; then touched=1; fi
    done <<EOF
$roles
EOF
    [ "$touched" = "1" ] && break
  done <<EOF
$revs
EOF
  [ "$touched" = "1" ] || return 0

  # HISTORY: ruling LIB-59 (undated), in the framework source's private hook-rulings record: THE STATE THIS PUSH PUBLISHES, read from the tip's tree.
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
    hits="$(git -C "$proj" ls-tree -r --name-only "$tip" -- specs/ 2>/dev/null | grep -E "^specs/${num}-[^/]*\.md$" || true)" # fail-open-ok: no match leaves hits empty and the skip below is the close gate's question, not this one
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

# HISTORY: ruling LIB-60 (undated), in the framework source's private hook-rulings record: Which specs are ACTIVE according to a STATUS.md text? The attestation.
slh_attest_active_specs() { # slh_attest_active_specs <status-text>
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 4 && toupper(trim($4)) == "ACTIVE" && trim($2) ~ /^[0-9]+[a-z]*$/ { print trim($2) }
  '
}

# HISTORY: ruling LIB-61 (undated), in the framework source's private hook-rulings record: THE CLOSE VERIFICATION, over the index.
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
  # HISTORY: ruling LIB-62 (undated), in the framework source's private hook-rulings record: THE STATUS IS CARRIED ACROSS THE SUBSHELL, and it was not.
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
  # HISTORY: ruling LIB-63 (undated), in the framework source's private hook-rulings record: THE ADOPTION COMMIT CLOSES NOTHING, by construction.
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
        printf '%s\n' "$__rec_old_closed" | grep -qxF -- "$__rn" && continue
        newly_closed="$newly_closed $__rn"
      done
    fi
  else
    # HISTORY: ruling LIB-64 (undated), in the framework source's private hook-rulings record: LIVE TEXT AT THE SOURCE (2026-08 consolidation, the F2 class made a rule).
    status_new="$(slh_index_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
    status_old="$(slh_head_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
    newly_closed="$(slh_rows_newly_closed "$status_new" "$status_old")"
  fi

  # HISTORY: ruling LIB-65 (plugin v1.7), in the framework source's private hook-rulings record: Which specs does this change CLOSE? A spec whose record entry (or, on the.
  closing_specs=""
  for num in $newly_closed; do
    # HISTORY: ruling LIB-66 (undated), in the framework source's private hook-rulings record: SORT ORDER IS NOT A CHOICE OF SPEC (leg F6).
    f="$(printf '%s\n' "$spec_files" | grep -E "^specs/${num}-[^/]*\.md$" || true)" # fail-open-ok: no match leaves f empty and the index fallback below runs
    if [ -n "$f" ] && [ "$(printf '%s\n' "$f" | grep -c .)" -ne 1 ]; then
      slh_refuse "SLH-SPEC-DUPLICATE" "$(printf '%s\n' "$f" | grep -c .) files match specs/${num}-*.md in this change, so which one carries spec $num's Closing report is a guess: $(printf '%s' "$f" | tr '\n' ' '). Spec numbers must be unique. Rename the companion out of the specs/<number>-*.md namespace, or give it its own number."
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

  # HISTORY: ruling LIB-67 (plugin 1.1.0), in the framework source's private hook-rulings record: Is feature code arriving? Any staged path under a declared role.
  local carries_code=0 rp
  if [ -n "$role_paths" ]; then
    for rp in $role_paths; do
      while [ "${rp#./}" != "$rp" ]; do rp="${rp#./}"; done
      rp="$(printf '%s' "$rp" | tr -s '/')"
      rp="${rp#/}"
      rp="${rp%/}"
      [ -n "$rp" ] && [ "$rp" != "." ] || continue
      # HISTORY: ruling LIB-68 (plugin 1.1.0), in the framework source's private hook-rulings record: A ROLE MAY NAME A FILE, not only a directory (1.1.0 final leg, F5).
      if printf '%s\n' "$staged" | grep -qE "^${rp}(/|$)"; then carries_code=1; break; fi
    done
  fi

  # HISTORY: ruling LIB-69 (2026-08-02), in the framework source's private hook-rulings record: THE CHORE ROUTE (v1.7 gate, F30).
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
        printf '%s\n' "$__rec_old_done" | grep -qxF -- "$__rc" && continue
        closing_chores="$closing_chores $__rc"
      done
      closing_chores="${closing_chores# }"
    fi
  else
    closing_chores="$(slh_chores_completed "$status_new" "$status_old")"
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

    # HISTORY: ruling LIB-70 (undated), in the framework source's private hook-rulings record: THE CLOSE FACTS COME FROM THE RECORD on the structured path (RP1).
    if [ "$structured" = "1" ]; then
      local __facts __owns_out
      if ! __facts="$(slh_record_facts "$record_new" "$num")"; then
        slh_refuse "SLH-RECORD-MALFORMED" "jq failed while reading spec $num's close facts from .claude/status.json. A reader that could not run has not read."
        continue
      fi
      if [ "$__facts" != "ok" ]; then
        slh_refuse "SLH-RECORD-NO-CLOSE" "spec $num is newly closed in .claude/status.json without its close facts: the entry must carry status closed, qa_pass_1 ok, and diagram updated or no-impact, written by /setlist:checkpoint at the close. Run the close through checkpoint rather than editing the record by hand."
      fi
      # HISTORY: ruling LIB-71 (undated), in the framework source's private hook-rulings record: The ownership declaration, gathered here and consumed after the loop.
      __owns_out="$(slh_index_show "$proj" "$f" | awk "$SLH_OWNS_AWK")" || __owns_out="!read-failed"
      # HISTORY: ruling LIB-72 (2026-09-06), in the framework source's private hook-rulings record: THE LITE TIER'S CAP (edition v1.14, P1, the owner's ruling 3 of.
      if printf '%s\n' "$__owns_out" | grep -q '^!lite-oversized$'; then
        slh_refuse "SLH-LITE-OVERSIZED" "spec $num is declared Tier: lite and declares more than five files under Owns:. A lite spec is at most five files (Part 3 of the edition); the two honest exits are to drop the tier line (a full spec, judged exactly as before) or to split the work, both through /setlist:checkpoint. The tier is a claim about size, and a claim the close cannot honour is refused rather than reread."
        __owns_out="$(printf '%s\n' "$__owns_out" | grep -v '^!lite-oversized$')"
      fi
      if printf '%s\n' "$__owns_out" | grep -q '^!'; then
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

    # HISTORY: ruling LIB-73 (plugin 1.1.0), in the framework source's private hook-rulings record: A FENCED EXAMPLE IS NOT A CLOSING REPORT.
    #
    # LOCKSTEP: byte-identical to close-gate.sh and trunk-audit.sh, asserted.
    # The value is defined once at the top of this file, because the lifecycle
    # detector reads it too (V19-F2).
    text="$(printf '%s\n' "$text" | awk "$SLH_TEMPLATE_FENCE_AWK")"

    if ! printf '%s\n' "$text" | grep -qE "$SLH_CLOSING_REPORT_RE"; then
      slh_refuse "SLH-NO-CLOSING-REPORT" "spec $num has no Closing report section; complete it and stage it before closing."
      continue
    fi

    if [[ "$(printf '%s\n' "$text" | awk "$SLH_QA_PASS1_AWK")" != "ok" ]]; then
      slh_refuse "SLH-NO-QA-VERDICT" "spec $num carries no usable QA Pass 1 verdict block. Part 6 requires a fenced qa-pass-1 block whose every line is <criterion>: PASS|PARTIAL|FAIL, the criterion a bare identifier with no spaces. The block must sit inside the Closing report section at fence depth zero: one nested inside a pasted-report fence is content, not a verdict, and a fenced example elsewhere neither satisfies nor poisons this check. A line inside that is not a verdict line is refused, not skipped, because skipping is how a sentence gets in. An HTML comment opened with <!-- and never closed refuses too, because the reader cannot see past it. Write the block at the left margin (three spaces of indent at most): the reader reads the document FLAT, and a block indented four or more spaces, including inside a numbered list item, is indented code."
    fi

    local diag answer
    # HISTORY: ruling LIB-74 (2026-08-29), in the framework source's private hook-rulings record: A FIELD, NOT A SUBSTRING (1.1.0 adversarial review, F8).
    diag="$(printf '%s\n' "$text" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | head -n1)"
    if [ -z "$diag" ]; then
      slh_refuse "SLH-NO-DIAGRAM-FIELD" "spec $num is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    else
      answer="${diag#*Architecture diagram:}"
      # HISTORY: ruling LIB-75 (undated), in the framework source's private hook-rulings record: PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11).
      answer="$(printf '%s' "$answer" | sed 's/<[^>]*>//g')"
      if ! printf '%s' "$answer" | sed 's/^[[:space:]]*//' | grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)'; then
        slh_refuse "SLH-DIAGRAM-UNANSWERED" "spec $num's architecture-diagram field is unanswered; answer it 'updated in this commit' or 'no impact'."
      fi
    fi
  done

  # HISTORY: ruling LIB-76 (undated), in the framework source's private hook-rulings record: THE PER-FILE OWNERSHIP QUESTION AT THE SINGLE-PARENT LANDING (design 8.2).
  if [ "$structured" = "1" ] && [ "$SLH_CLOSE_SINGLE_PARENT" = "1" ] && \
     [ "$__owns_blockless" = "0" ] && [ "$__owns_shape_bad" = "0" ] && \
     { [ "$__owns_declaring" = "1" ] || [ -n "$closing_chores" ]; }; then
    local __ch __cf __sf __owns_staged
    # HISTORY: ruling LIB-77 (plugin 2.4.0), in the framework source's private hook-rulings record: The arm asks what ARRIVES on the trunk, so deletions are out of scope.
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
      local __is_role=0 __rp2
      for __rp2 in $role_paths; do
        while [ "${__rp2#./}" != "$__rp2" ]; do __rp2="${__rp2#./}"; done
        __rp2="$(printf '%s' "$__rp2" | tr -s '/')"
        __rp2="${__rp2#/}"; __rp2="${__rp2%/}"
        [ -n "$__rp2" ] && [ "$__rp2" != "." ] || continue
        if printf '%s\n' "$__sf" | grep -qE "^${__rp2}(/|$)"; then __is_role=1; break; fi
      done
      [ "$__is_role" = "1" ] || continue
      if ! printf '%s\n' "$__owns_list" | grep -qxF -- "$__sf"; then
        slh_refuse "SLH-OWNS-UNDECLARED" "$__sf is a role-path file this close does not declare. A declaring close is audited file by file against its declared set, so a whole commit can no longer be exempted by one record flip. Two honest exits: declare the file through /setlist:checkpoint (under attestation custody that means re-approval, correctly), or take the --no-ff merge route, whose arm asks the provenance question instead."
      fi
    done <<EOF
$__owns_staged
EOF
  fi

  # HISTORY: ruling LIB-78 (undated), in the framework source's private hook-rulings record: T1 at THIS layer, at BOTH landings (a true merge and a single-parent.
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

# HISTORY: ruling LIB-79 (undated), in the framework source's private hook-rulings record: The project's own gate command.
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
          else "ok " + ($g[$t] // "") end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
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
  # HISTORY: ruling LIB-80 (plugin v1.7), in the framework source's private hook-rulings record: AN EMPTY gate_command IS THE STAMPED DEFAULT, SO SKIPPING IT SILENTLY WAS A.
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
    scaffolded="$(jq -r '.scaffolded // false' "$proj/.claude/sdd.json" 2>/dev/null || printf 'true')" # fail-open-ok: an unreadable file yields "true", which refuses rather than skips, and that is the safe direction here
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
  # HISTORY: ruling LIB-81 (undated), in the framework source's private hook-rulings record: 127 is "a command in the gate was not found", which is a DIFFERENT fact from.
  if [ "$rc" = "127" ]; then
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($cmd) could not RUN here (exit 127, a command was not found), so it proves nothing about this work. Hooks run it in a bare shell: if your toolchain lives in a virtualenv or a version-manager shim, put the activation inside gate_command itself. Last output: $last"
  else
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($cmd) does not pass (exit $rc), so this work is not ready to reach the trunk. Last output: $last"
  fi
  return 1
}
