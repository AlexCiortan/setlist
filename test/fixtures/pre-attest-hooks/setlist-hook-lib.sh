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
# SCOPED (2.0.0 leg, F8/F3): the block that decides is the LAST qa-pass-1 fence
# at fence depth ZERO inside a Closing report section. Third fence-vs-QA-block
# collision, so the scoping is structural rather than another special case: the
# reader tracks fences the way the template stripper does (open on three or
# more backticks or tildes, close on a bare fence of the same character and at
# least the same length), and an opener seen inside another fence is CONTENT.
# That closes both directions at once: a block nested inside a pasted verifier
# report cannot satisfy the check (F8, which reached the trunk and the audit
# called it clean), and an illustrative shape-quote outside the Closing report
# cannot poison a real verdict (F3, refused at all three layers with a reason
# naming the wrong block). "Last wins" is the diagram field's revision
# convention, kept deliberately so a revised close still closes. Headings are
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
SLH_QA_PASS1_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; qa_seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } } else { if (__r == "qa-pass-1" && inclose) { inb = 1; qch = __c; qlen = __m; n = 0; bad = 0; next } fence = 1; fch = __c; flen = __m; next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "") next; if (l ~ /^[A-Za-z0-9._-]+[[:space:]]*:[[:space:]]*(PASS|PARTIAL|FAIL)$/) n++; else bad = 1; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) inclose = 0 } } END { if (incmt) print "unclosed-comment"; else if (inb) print "unclosed"; else if (!qa_seen) print "none"; else if (bad) print "malformed"; else if (n == 0) print "empty"; else print "ok" }'

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

# THE LIFECYCLE DETECTOR, MADE A SIBLING OF THE THREE READERS IT DISAGREED WITH
# (v1.9 leg, V19-F2: a CONFIRMED FALSE DENIAL, disclosed at 2.1.0 under a dated
# owner ruling and promised to this cycle by that release's notes).
#
# pre-commit asked "does this commit move a spec lifecycle state" by grepping
# the RAW staged diff for `^\+Status:...|^\+#+[[:space:]]*Closing report`. Two
# defects, one cause, measured in both directions on a stamped fixture:
#
#   - A spec that QUOTES the closing-report template inside a ```markdown fence,
#     changing no lifecycle state of its own, was refused SLH-STATUS-MISSING.
#     The quotation is ordinary authoring: the template ships fenced in the
#     edition, is stamped to specs/TEMPLATE.md, and the authoring skill tells
#     authors to copy it.
#   - The mirror: `  ## Closing report` with two spaces of indent was not matched
#     AT ALL, while the three other readers in the same release accept
#     `^ {0,3}#{1,6}[ \t]+Closing report`. Three readers, one release, three
#     different opinions about what a Closing report heading is. That is the
#     class this repository's leg 2 through 4 blockers came from.
#
# THE FIX IS THE SIBLING RULE, NOT A FOURTH SPELLING (A9). The detector reads
# the spec FROM THE INDEX, strips template quotes with the same
# SLH_TEMPLATE_FENCE_AWK the close verification uses, and matches the same
# heading form. Reading the index rather than the diff text is deliberate and is
# the half a diff-only repair gets wrong: `--unified=0` yields no context, so a
# fence opened by an earlier commit is invisible and the stripper cannot know it
# is inside one. The DIFF still decides WHICH lines are new, so an untouched
# Status line in a file edited for other reasons does not fire the check; the
# INDEX decides whether that line is live text or a quotation. Both questions
# get asked of the surface that can answer them.
slh_lifecycle_added() { # slh_lifecycle_added <proj> <states-re> <spec-path...> -> 0 when this change ADDS a live lifecycle line
  local proj="$1" states_re="$2"; shift 2
  local f live added
  for f in "$@"; do
    [ -n "$f" ] || continue
    # A path with no index version (a deletion) has no live text, and a removed
    # Status line was never an added one. The old detector read added lines only
    # for the same reason.
    # fail-open-ok: no live lifecycle line in this spec is nothing to pair with an inventory row.
    live="$(slh_index_show "$proj" "$f" | awk "$SLH_TEMPLATE_FENCE_AWK" | grep -E "^Status:[[:space:]]*(${states_re})|${SLH_CLOSING_REPORT_RE}" || true)"
    [ -n "$live" ] || continue
    # fail-open-ok: a file whose staged diff adds nothing adds no lifecycle line.
    added="$(git -C "$proj" diff --cached --unified=0 -- "$f" 2>/dev/null \
             | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^+//' || true)"
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

# ===========================================================================
# CONTENT SCANNING, BOUND TO CONTENT RATHER THAN TO AN OPERATION (F1, 2026-08-05).
#
# The em-dash and secret scans lived in pre-commit and nowhere else, so every
# route that creates a commit WITHOUT firing pre-commit carried unscanned bytes
# to the trunk. Measured, each landing a live-shaped key at rc=0 with the audit
# also reporting clean: cherry-pick, rebase, am, merge --no-ff, merge --ff. The
# same bytes through `git commit` were refused SLH-SECRET. The siblings that
# route through the index instead (git apply then commit, checkout -- then
# commit, stash then commit) all refused correctly, which is what makes this a
# hook-FIRING gap rather than a weak scanner.
#
# The fix is deliberately not an enumeration of operations. Enumerating is the
# class C lesson from this same leg: the list is always one entry short of the
# next attack, and git offers no pre-cherry-pick, pre-rebase-commit or pre-am
# hook to enumerate anyway. So the rule is stated once here and every layer that
# can see content calls it:
#
#   pre-commit         the staged diff        (the ordinary path)
#   pre-merge-commit   the merge's own diff   (the framework's close path)
#   pre-push           the pushed range       (the backstop for everything else)
#
# WHAT THE COMMIT-TIME LAYERS CANNOT COVER, stated rather than implied: git
# fires no hook for cherry-pick, for rebase's intermediate commits, or for the
# apply step of `git am`. Those routes reach the trunk unscanned at commit time
# BY CONSTRUCTION, and the pre-push range scan is what catches them, which means
# they are caught before the content is shared rather than before it is
# committed. What this does NOT establish, and claimed to until the v1.7 claims
# audit measured it: that a pushed history cannot carry an unscanned secret. It
# can, by at least four routes the README now names at their real strength, the
# plainest being that the push-time read is an ENDPOINT DIFF rather than a walk
# of the commits, so content added and removed inside the pushed range is never
# rendered while every object still reaches the remote. Treat a secret that
# reached a commit as compromised regardless of what any layer here reported.
SLH_EMDASH="$(printf '\342\200\224')"
SLH_SECRET_RE='(api[_-]?key|secret|passw(or)?d|token)["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+.-]{16,}|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^@[:space:]]+@'

# ===========================================================================
# PATH-SCOPED SCANS: THE DECLARED EXCLUSION SET, NAMED OUT LOUD (KL4, spec 0122).
#
# The two scans above read every added line, which is right for the author's own
# writing and wrong for a vendored tree, a fixture carrying a dummy credential,
# or quoted external text. Splitting the commit does not help (measured): the
# scan follows the content, so isolating the foreign file isolates it WITH the
# scanner. So the projects that carry such content declare an exclusion set:
#
#   .claude/sdd.json  ->  "scan_exclusions": ["vendor/**", "test/fixtures/**"]
#
# FOUR PROPERTIES, each of which is the reason a different failure cannot happen
# here, and each asserted by the suite rather than promised by this comment.
#
# 1. EVERY SKIP IS ANNOUNCED, EVERY TIME. A scan that silently declines to read
#    a path is the vacuous green this whole layer exists to remove, wearing a
#    feature's name. The notice carries the path AND the glob that matched it,
#    at whichever layer did the skipping, so "why did this pass" is answerable
#    from the output rather than from the config. The honest price: a push that
#    walks two hundred commits over an excluded tree prints the notice two
#    hundred times, once per commit, because each is a distinct true statement
#    about a distinct commit and deduplicating them would be this file deciding
#    which truths the operator needs.
#
# 2. ABSENCE IS BYTE-IDENTICAL TO THE PRE-FEATURE BEHAVIOUR, BY CONSTRUCTION.
#    With nothing declared, slh_scan_added takes the SAME two greps over the
#    SAME input it has always taken; the scoped path is not entered at all. That
#    is deliberate: reproducing the old behaviour carefully inside the new code
#    path is how a rewrite ships a difference nobody meant, and the suite's
#    differential against the pinned pre-feature blobs would only tell us
#    afterwards.
#
# 3. IT SCOPES THE CONTENT SCANS AND NOTHING ELSE. The set lives inside this one
#    function, so role-path judgment, the trunk audit, lifecycle detection and
#    every close check are out of its reach structurally rather than by
#    agreement. A glob covering specs/ or .claude/ changes no verdict anywhere
#    but here. That is what keeps this a seatbelt rather than a general ignore
#    file: an exclusion set that can hide anything is not one.
#
# 4. ATTRIBUTION COMES FROM DIFF STRUCTURE, NOT FROM LINE TEXT. A path is read
#    only from a `+++` header seen OUTSIDE a hunk, and hunk state is tracked from
#    `diff --git` / `diff --cc` and `@@`. Every line inside a hunk carries a
#    prefix column, so none of those three can be forged by content: a
#    diff-of-a-diff carrying the line `+++ b/vendor/x` cannot point the scanner
#    at an excluded path and walk a secret through under its name. Without this
#    rule any excluded glob is a universal exemption for anyone who can write
#    one line, which is the shape of the hole this feature would otherwise open
#    while looking like it closed one.
#
# WHERE THE MATCH FAILS, THE SCAN RUNS. Every unreadable, unmatched or ambiguous
# case degrades to scanning, never to skipping: a path git had to quote (non
# ASCII, control characters) is scanned and said so, a case-variant spelling on
# a case-insensitive filesystem does not match and is scanned, a glob naming
# nothing changes nothing. Failing to exclude costs a false refusal the operator
# can see; failing to scan costs a published secret.

# The glob charset. A pattern is interpolated into a `case` pattern, which is
# what makes shell globbing available at all, and an unrestricted string there
# would be config-driven code: a value containing `)` or `;` ends the pattern and
# starts a command, and an unbalanced `[` is a syntax error inside the hook. So
# the charset is closed to what a repo-relative path glob actually needs, and
# anything else is REFUSED rather than sanitised. The cost is that a path with a
# space or a quote in it cannot be excluded; the direction of that cost is the
# safe one (it gets scanned), and it is named in the refusal.
SLH_SCAN_GLOB_BAD='[!A-Za-z0-9._/*?-]'

# The diff reader. ONE program, two modes, because the path census and the line
# filter must agree about what a header is: two readers of one structure is the
# defect this file has paid for repeatedly.
# THE EXCLUDED SET ARRIVES THROUGH THE ENVIRONMENT, NOT THROUGH -v, and this is
# a measured correction rather than a preference. `awk -v x="a\nb"` is an ERROR
# on BWK awk ("newline in string"), which is the awk macOS ships and therefore
# the awk most operators run. The failure was silent in the worst possible
# direction: awk exited non-zero having printed nothing, the caller read the
# empty output as "no added lines to judge", and a commit carrying a secret on a
# SCANNED path was allowed as soon as any OTHER path in the same change was
# excluded. That is the 1.0.8 fail-open shape (an empty string reading as
# "nothing to govern") reintroduced by a new feature, and the mixed-change
# fixture is what caught it. ENVIRON carries newlines on every awk this project
# supports, and the status of every awk stage is now checked by its caller.
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

# THE ONE READER (A9). Both layers, both scans, one implementation.
#
# It sets globals rather than printing its result, and that is not a style
# choice: `x="$(f)"` runs f in a SUBSHELL, so a refusal recorded by slh_refuse
# inside it sets SLH_REFUSED in a process that then exits, which is the exact
# defect slh_verify_close carries a comment about. Setting globals also lets the
# read happen ONCE per hook run rather than once per commit in the push walk,
# so an unreadable config refuses with one message instead of two hundred.
SLH_SCAN_EXCLUSIONS=""
SLH_SCAN_EXCLUSIONS_STATE=""
slh_scan_exclusions_load() { # slh_scan_exclusions_load <proj> -> 0 with SLH_SCAN_EXCLUSIONS set, 1 after refusing
  # THE ENTRIES ARE PREFIXED AND COUNTED, and that is a measured correction
  # rather than defensiveness. The first cut passed them as bare lines after an
  # "ok" verdict, and `x="$(jq ...)"` STRIPS TRAILING NEWLINES: an empty array
  # and an array holding one empty string both arrived as the single line "ok",
  # so a project that declared nothing was refused SLH-SCAN-EXCLUSION-INVALID
  # for an entry it never wrote. That reached the shipped sdd.json template,
  # where "scan_exclusions": [] made every commit in a freshly stamped instance
  # refuse. It was NOT caught by this feature's own empty-array assertion, which
  # only checked that the commit was refused and got a refusal for the wrong
  # reason: a green labelled with the verdict instead of with the evidence, the
  # exact shape A8 exists for, committed by the test for the class.
  #
  # So each entry now arrives as ">" plus its text, which survives the strip
  # because it is never empty, and the verdict carries the DECLARED COUNT so the
  # reader can assert it read as many as jq wrote rather than assuming.
  local proj="$1" raw verdict pat lit out="" declared="" seen=0
  if [ -n "$SLH_SCAN_EXCLUSIONS_STATE" ]; then
    [ "$SLH_SCAN_EXCLUSIONS_STATE" = "ok" ] && return 0
    return 1
  fi
  # jq's STATUS is carried, not discarded, for the same reason slh_trunk carries
  # it: a jq that exists and fails yields an empty string indistinguishable from
  # a legitimate absent key, and here that empty string would read as "nothing
  # excluded" while the truth is "the configuration was not read".
  if ! raw="$(jq -r '
        if (.scan_exclusions == null) then "absent"
        elif ((.scan_exclusions | type) != "array") then "shape"
        elif ([.scan_exclusions[] | select(type != "string")] | length) > 0 then "shape"
        elif ([.scan_exclusions[] | select(contains("\n") or contains("\r"))] | length) > 0 then "shape"
        else ((["ok " + (.scan_exclusions | length | tostring)]) + [.scan_exclusions[] | ">" + .] | join("\n")) end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
    SLH_SCAN_EXCLUSIONS_STATE="bad"
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading the scan exclusion set from .claude/sdd.json, so which paths this scan may skip could not be determined. THE LIKELIER CAUSE IS THE TOOLCHAIN, NOT THE FILE: the trunk was read from this same file moments ago. Check 'jq --version' and 'jq . .claude/sdd.json' in that order. Refusing rather than scanning against a configuration nobody read."
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
    # NORMALISED, NOT USED RAW, and normalised the way role paths already are in
    # this file. A set recorded as "./vendor", "/vendor" or "vendor/" names the
    # same directory a human means, and four spellings of one value is how the
    # guarantee layer went blind on "./src" once already.
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
    # A PATTERN MUST NAME SOMETHING. Strip the wildcards and the separators; if
    # nothing is left, the pattern matches every path in the repository, and an
    # exclusion set that can hide anything is not a seatbelt. Decided by what the
    # pattern IS rather than by a list of spellings: "*", "**", "*/*" and "?" all
    # fail this one test, and any pattern carrying a single literal character
    # passes it.
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
  # THE COUNT IS ASSERTED BEFORE THE SET IS USED. A reader that silently saw
  # fewer entries than the file declares would scan paths the project believes
  # are excluded, which is the safe direction, and would ALSO mean the reader is
  # wrong about a file it just parsed. The second fact is the one that matters:
  # this is the same "assert the fixture count before comparing" rule the suite
  # runs on itself, applied to the reader.
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

# The scoped filter. Announcements go to STDERR from inside here on purpose:
# they are notices rather than refusals, so nothing has to survive the command
# substitution this function is called through, and the operator sees them
# interleaved with the refusals they explain.
slh_scan_scoped_added() { # slh_scan_scoped_added <diff-text> <globs> <what-it-is>
  local diff_text="$1" globs="$2" where="$3" paths p g ex=""
  # EVERY AWK STAGE CARRIES ITS OWN STATUS. An awk that exits non-zero prints
  # nothing, and nothing is indistinguishable from a clean diff to the caller's
  # `[ -n "$added" ]` test. The caller turns a non-zero return here into a
  # refusal with a named code; it must never turn it into a pass.
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

# slh_scan_added <proj> <diff-text> <what-it-is>
# Reads a unified diff and refuses on added lines only, so pre-existing content
# is never re-judged by a later layer. <proj> is the first argument because the
# scan now has a configuration to read; every layer that sees content passes its
# own project root, and there is no path through this function that reaches the
# greps without the exclusion set having been read or refused.
# slh_rows_newly_closed <status-new> <status-old> -> spec numbers whose row
# flipped to CLOSED in this change, whether or not the spec FILE was touched.
# This is the set the documentation has always described (v1.7 claims audit,
# R3-2); the implementation used to intersect it with the staged file list.
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
  # EXACT NUMBER, THEN A HYPHEN (leg F6 and its second half). The second glob
  # here was `specs/${num}[a-z]-*.md`, which for num=0002 also matched
  # specs/0002b-parked.md. Part 4's split convention makes 0002b a DISTINCT
  # spec carrying its own STATUS.md row, so that file is somebody else's spec
  # and was never a candidate for this one.
  hits="$(git -C "$proj" ls-files "specs/${num}-*.md" 2>/dev/null)"
  [ -n "$hits" ] || return 0
  n="$(printf '%s\n' "$hits" | grep -c .)"
  # A pick among several is a guess. Report nothing and let the caller refuse,
  # rather than return the alphabetically first and call it the spec.
  [ "$n" -eq 1 ] || return 0
  printf '%s\n' "$hits"
}

# THE HEADER STRIP IS ANCHORED TO THE HEADER (SC sub-hole 6).
#
# It was `grep -vE '^\+\+\+'`, which drops the diff's own `+++ b/path` line and
# also drops any ADDED LINE whose content begins with `++`. That is not a
# contrived shape: `+++` opens a conflict marker, and diff-of-a-diff content and
# some generated files carry it too. A secret on such a line was removed from the
# scan's input by the scan itself.
#
# The exact forms git emits are `+++ b/<path>` and `+++ /dev/null`, and the
# prefix is pinned at the call sites (`--src-prefix=a/ --dst-prefix=b/`) so a
# repository configuring `diff.noprefix` or a custom prefix cannot change the
# header out from under this anchor. Both ends are set together on purpose: an
# anchor without a pinned prefix eats content on some repositories, and a pinned
# prefix without an anchor eats content on all of them.
SLH_DIFF_HEADER_RE='^\+\+\+ (b/|/dev/null)'

slh_scan_added() {
  local proj="$1" diff_text="$2" where="$3" added
  # The exclusion set is read ONCE per hook run and refuses for the whole run if
  # it cannot be read. Called from here rather than from each hook so no layer
  # can scan without having asked (A9), and called OUTSIDE a command
  # substitution so its refusal survives.
  if ! slh_scan_exclusions_load "$proj"; then
    SLH_REFUSED=1
    return 1
  fi
  if [ -z "$SLH_SCAN_EXCLUSIONS" ]; then
    # NOTHING DECLARED: the pre-feature path, entered verbatim rather than
    # reproduced. This line is the whole of "the feature is invisible until
    # asked for", and the suite proves it by differential against the pinned
    # pre-feature hook blobs rather than by reading it.
    added="$(printf '%s\n' "$diff_text" | grep -E '^\+' | grep -vE "$SLH_DIFF_HEADER_RE" || true)" # fail-open-ok: no added lines makes both greps below find nothing, which is the correct answer for a diff that adds nothing
  else
    # NOT fail-open-ok, and deliberately the only branch here that is not: the
    # scoped filter can FAIL, and a failed filter prints nothing, which the
    # emptiness test below would read as a clean diff. A scan that could not run
    # has not passed.
    if ! added="$(slh_scan_scoped_added "$diff_text" "$SLH_SCAN_EXCLUSIONS" "$where")"; then
      slh_refuse "SLH-SCAN-FILTER-FAILED" "the path-scoped scan of $where could not read the change, so it read nothing and has judged nothing. A scan that could not run has not passed. This points at the toolchain rather than at the content: check 'awk --version'. Remove \"scan_exclusions\" from .claude/sdd.json to fall back to scanning every path, or push with SETLIST_SKIP_HOOKS=1 if this is an exception you are willing to own."
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

# LIVE TEXT ONLY (2026-08 consolidation, blocker F2). STATUS.md is read for chore
# archive lines by a bare grep with no notion of a fenced example or an HTML
# comment, while the frozen QA reader sixty lines of this same file over tracks
# both. Measured: a CHORE-NNN archive line written inside <!-- --> (invisible in
# the rendered file) or inside a ```fence (the very format the how-to-archive
# guidance shows) satisfied the grep and let feature code reach the trunk with no
# spec closed and no real chore. A line indented four or more spaces (an indented
# code block, same threshold the QA reader uses for headings and fences) is the
# same class: an illustration, not a record.
#
# THE READER TOLERATES A BLOCK PREFIX, SO THE STRIP MUST TOO (adversary rounds
# 1-4 of this round). The chore grep and the row reader both accept a leading
# [-*+>[:space:]]* prefix, so a chore or CLOSED row written inside a code fence
# that is itself inside a blockquote (> ```), a list item (- ```) or an ordered
# step (1. ```) renders as a quoted example yet was counted as a record: the
# fence marker sat past the 0-3-space window the anchor allowed. The fence OPEN
# is detected on the line with its blockquote markers and ONE list bullet
# (bulleted -*+ OR ordered 1. / 1)) stripped, so a fence is seen through the
# same container prefix the readers see the record through, and the blockquote
# DEPTH at the open is remembered (fbq). A close is honoured only at that same
# depth and never strips a list bullet, because a closing fence in CommonMark
# carries no marker and sits at its container's depth: a `- ```` or a `> ````
# line at a DIFFERENT depth than the open is literal code, not a close, and
# treating it as one forged an early close that leaked the rest of the block
# (round 4, the bullet; round 5, the blockquote marker on a top-level fence).
# The mismatched-depth case fails closed: the fence stays open and the rest is
# stripped, an honest close refused rather than an illustration kept. Indented
# code is recognised RELATIVE TO ITS CONTAINER (rounds 6-7): the blockquote peel
# consumes `>` and its one following space per level but NOT the content's own
# indentation, tracking depth; then a SEPARATE peel for the indented-code test
# strips any leading run of blockquote markers AND list bullets (-*+, 1., 1))
# and asks whether four or more spaces remain, so a `>     CHORE` (code in a
# quote) and a `-     CHORE` (code in a list item, where CommonMark treats a
# marker followed by 5+ spaces as an indented code block) both read as code, not
# a record. That container-marker peel is used ONLY for the indent test and the
# fence OPEN, NEVER for the fence CLOSE (a closing fence carries no marker; see
# the depth rule above). The HTML-comment scan looks for `-->` starting two
# characters after `<!--`, so an abrupt empty comment (`<!-->`, `<!--->`) closes
# on its own line as a renderer closes it, rather than being read as an unclosed
# comment that hides every following line to EOF. HTML BLOCKS (round 8, extended
# round 11-12): a `<script>`, `<style>`, `<textarea>` or `<pre>` block (CommonMark
# type 1) encloses content GitHub either deletes (script/style/textarea) or draws
# as a literal code block indistinguishable from a ``` fence (pre); a human reads
# none of it as a live record, so those enter an html-block state that strips to
# the matching close tag or EOF. `<details>`, `<div>` and `<table>` are NOT in the
# set: `<details>` is a type-6 block whose content renders as a LIVE (collapsible,
# and in a diff fully visible) table, and stripping it to `</details>` over-
# swallowed and dropped a live CLOSED row, escaping the union check; those tags'
# content is kept, matching what a reviewer sees. INDENTED CODE CANNOT INTERRUPT A
# PARAGRAPH (round 8, direction ii): a four-space-indented line at top level is
# code only when it follows a blank line or the start of file (or continues an
# open code block); a four-space line directly under a paragraph is a lazy
# continuation a renderer SHOWS, so it is kept. Dropping it was NOT the safe
# cooperative over-strip the old comment claimed: a dropped CLOSED inventory row
# escapes the row-flip union check and launders a spec onto the trunk. Code
# indented inside a list item or a blockquote stays always-code (a container
# resets the paragraph), and only a genuine PARAGRAPH sets the continuation flag:
# a heading, a setext underline (===/---) or a thematic break is not paragraph
# text, so a following indented line is code, not a continuation (round 9; a
# STATUS.md heading directly above an indented row otherwise laundered it). A
# GFM TABLE is not a paragraph either (round 10): a delimiter row (`|---|`) and
# the table rows that follow it do not set the flag, so an indented line right
# after the inventory table reads as code, while a LONE pipe row with no
# delimiter is still a paragraph and keeps its lazy continuation. All leading-whitespace handling is [[:space:]]* or a
# bounded ` ? ? ?`, identical on BWK and GNU awk (verified), and the
# indented-code test runs BEFORE the fence open so an indented ``` reads as code,
# not a fence. A comment opened mid-line, or spanning lines, is deleted as a
# span; an unclosed <!-- hides to end of file, as a renderer does. Where a line
# reader genuinely cannot decide it deletes rather than keeps: an over-stripped
# live line refuses an honest close (cooperative), a kept illustration is a
# bypass.
#
# LOCKSTEP: byte-identical to trunk-audit.sh and close-gate.sh. NEW function, not an edit
# to the frozen QA_PASS1_AWK/TEMPLATE_FENCE_AWK (dogfood/QA-READER-FREEZE.md):
# those exist to find a specific block and must keep real content they are not
# stripping FOR; this one exists to delete anything that is not live prose before
# a plain grep runs over what remains, and needs none of that block-finding state.
SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } if ((__d>0 || __peeled) && __ic ~ /^[[:space:]]*[|]/) next; print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

SLH_REFUSED=0

slh_refuse() { # slh_refuse <code> <message...>
  local code="$1"; shift
  printf 'setlist [%s]: %s\n' "$code" "$*" >&2
  SLH_REFUSED=1
}

# Is this repository a framework instance at all? A repo with no sdd.json is
# somebody else's repo and none of our business.
slh_is_instance() { [ -f "$1/.claude/sdd.json" ]; }

# THE TOOLS THIS FILE RUNS ON MUST ACTUALLY WORK (v1.7 gate, adversarial review F2).
#
# The banner above promises EVERYTHING HERE FAILS CLOSED, and jq was the only
# dependency anyone checked. Measured: with grep broken, a merge of an unclosed
# spec landed at rc=0 in silence, because the close verification's greps returned
# nothing and "no evidence of a violation" read as "no violation". Broken awk,
# sed and tr happened to still refuse, which is luck rather than design: each is
# one refactor away from the same fail-open.
#
# Every probe RUNS its tool and checks the OUTPUT as well as the status, because
# a tool that exits 0 and prints nothing disables these checks just as
# thoroughly. The comparisons are shell builtins, so a probe never depends on the
# thing it is probing.
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
  return 0
}

# The trunk name. Mirrors close-gate.sh, including the refusal on a
# present-but-invalid value: guessing "main" over a stated intention would
# govern a branch nobody named.
#
# THIS COMMENT USED TO SAY "Mirrors close-gate.sh exactly" AND IT WAS FALSE, which
# is how the v1.7 dogfood gate's BLOCKER shipped. close-gate.sh does two things
# here and this function did only the first: it checks the value is a non-empty
# string, AND it REDUCES the value to a local branch name, refusing if it cannot.
# Without the second half, slh_on_trunk() compares "refs/remotes/origin/main"
# against the "main" that `symbolic-ref --short HEAD` returns, the two can never
# be equal, both hooks conclude they are not on the trunk, and every governed
# operation is allowed in total silence. Five spellings reproduced it, and the
# route is the SHIPPED UPGRADE PATH: `git symbolic-ref refs/remotes/origin/HEAD`
# is what the upgrade skill tells the agent to use, and it returns a ref path.
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
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading .claude/sdd.json, so the trunk could not be determined. THE LIKELIER CAUSE IS THE TOOLCHAIN, NOT THE FILE: jq exists here (it was probed above), so a jq that then fails is usually a broken link, the wrong architecture, or an OOM kill, and the config is usually fine. Check 'jq --version' and 'jq . .claude/sdd.json' in that order. Refusing rather than defaulting."
    return 1
  fi
  if [ -z "$v" ]; then
    slh_refuse "SLH-TRUNK-INVALID" ".claude/sdd.json declares a \"trunk\" that is not a non-empty string, so the trunk this project protects cannot be determined and every trunk check would silently pass. Set \"trunk\" to your trunk branch name (for example \"main\" or \"master\"), or remove the key to accept the default."
    return 1
  fi

  # THE VALUE MUST NAME A LOCAL BRANCH. Ported from close-gate.sh, and the
  # REDUCTION IS DONE BY ASKING GIT rather than by stripping prefixes textually,
  # which is the mistake the ref rewrite already made once: a spelling that
  # resolves to a local branch becomes that branch, a remote-tracking spelling
  # becomes the local branch it TRACKS if one exists, and anything still naming no
  # local branch is REFUSED. Guessing "main" here would silently govern a branch
  # the project never named, which is the same failure as not checking at all.
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

  # AND THE CASE-VARIANT SPELLING, which is the same class one more time. On a
  # case-insensitive filesystem refs/heads/main is ONE file, so a recorded trunk
  # of "MAIN" resolves and every byte comparison against "main" fails. This is
  # the reducer, so it reduces that too rather than leaving a fourth caller to
  # remember: slh_canonical_branch returns git's STORED spelling.
  v="$(slh_canonical_branch "$proj" "$v")"

  printf '%s' "$v"
}

# The role paths (src, tests, ...) this project declares. Feature code lives
# under these; docs, specs and journals do not.
slh_role_paths() { # slh_role_paths <proj>
  local proj="$1"
  # THE SHAPE, WHICH THIS READER ALONE DID NOT CHECK (1.1.0 final leg, F13).
  #
  # scope-hook.sh and trunk-audit.sh refuse a "roles" that is present and not an
  # object; the GUARANTEE layer did not, so `{"roles": 123}`, `true` or a string
  # made the extraction print nothing, carries_code stayed 0, and an unclosed
  # spec branch merged onto the trunk in silence. The existing suite assertion
  # compared only the jq EXTRACTION output, which is why this looked closed.
  #
  # jq's status is CARRIED rather than discarded here, for the same reason
  # slh_trunk carries it: a jq that exists and fails yields an empty string
  # indistinguishable from a legitimate absent key.
  local shape
  if ! shape="$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$proj/.claude/sdd.json" 2>/dev/null)"; then
    slh_refuse "SLH-UNREADABLE-CONFIG" "jq ran and failed while reading the role paths from .claude/sdd.json. THE LIKELIER CAUSE IS THE TOOLCHAIN, NOT THE FILE: the trunk was read from this same file moments ago, so a failure here points at jq (a broken link, the wrong architecture, an OOM kill) rather than at the config. Check 'jq --version' and 'jq . .claude/sdd.json' in that order. Refusing rather than treating an unreadable config as a project with no feature code."
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

# A BRANCH NAME IS NOT A STRING, IT IS A REF (1.1.0 adversarial review, second run).
#
# On a case-insensitive filesystem (APFS by default, and NTFS) `refs/heads/main`
# is one loose file, so `git checkout MAIN` succeeds, attaches HEAD to that same
# ref, and `symbolic-ref --short HEAD` then answers "MAIN". Every layer here
# compared that answer to the configured "main" as BYTES, concluded it was not
# on the trunk, and allowed an unreviewed merge that really landed: measured, the
# trunk moved, pre-merge-commit stayed silent where the canonical spelling gets
# SLH-CLOSES-NO-SPEC, and the audit filed it under "chore merges (unverifiable)"
# at exit 0 so pre-push passed it too. Four layers, none of them refused.
#
# This is the v1.7 gate's BLOCKER one spelling further out. That fix REDUCED the
# configured side (refs/remotes/origin/main -> main) and left the OBSERVED side
# raw, so the same comparison stayed wrong from the other end.
#
# The fix asks git what the branch is CALLED rather than trusting how it was
# spelled. An exact hit in for-each-ref means the name is already canonical. No
# exact hit plus a case-insensitive hit means this is a case variant of a stored
# branch, which is the alias, so the stored spelling is used. On a genuinely
# case-sensitive filesystem `MAIN` and `main` are two real branches, both appear
# in the list, the exact hit fires, and nothing is rewritten: the repair cannot
# turn a real feature branch into the trunk.
#
# Deliberately NOT done by comparing OIDs: a branch cut from the trunk points at
# the same commit, so that test would call every fresh feature branch the trunk
# and deny all work on it.
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
  # THE UPSTREAM DISCRIMINATOR IS REMOVED (2026-08-07).
  #
  # It was added on 2026-08-05 so a git-flow instance, working on `trunk` while
  # a local `main` also exists, would still be governed when sdd.json recorded
  # "main". It did that by treating any branch whose upstream basename equalled
  # the recorded trunk as the trunk itself, and that is not a question this hook
  # can answer: "this branch IS the trunk under another local name" and "this
  # branch merely tracks origin/main" look identical from here.
  #
  # Measured by the 2026-08-07 leg: an ordinary spec branch whose upstream was
  # origin/main got refused SLH-CLOSES-NO-SPEC for a merge the identical branch
  # WITHOUT an upstream accepted, and a purely local `--set-upstream-to=main`
  # made any branch the trunk to this hook. Those are false denials on ordinary
  # work, which this project treats as costing more than the hole they close.
  #
  # So the rule is the recorded name again, and the git-flow shape is a
  # documented limitation instead: record the branch you actually merge onto.
  # The upgrade skill prescribes exactly that, and gets it right.
  [ "$(slh_canonical_branch "$1" "$head")" = "$(slh_canonical_branch "$1" "$2")" ]
}

# Files staged for this commit, relative to HEAD. On an unborn branch there is
# no HEAD, so fall back to the whole index.
slh_staged_files() { # slh_staged_files <proj>
  local proj="$1"
  if git -C "$proj" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    git -C "$proj" diff --cached --name-only HEAD 2>/dev/null
  else
    git -C "$proj" diff --cached --name-only 2>/dev/null
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
  # GFM ESCAPED PIPE (round 11): a \| inside a Title cell renders as a literal
  # pipe, but awk -F'|' splits on it, shifting CLOSED out of field 4 so a real
  # close-flip reads as not closed and escapes the union check. It never appears
  # in the number or status cell, so replacing it with a space before the split
  # keeps the field count right without touching the fields this reads.
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' -v num="$2" '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 4 && trim($2) == num {
      s = toupper(trim($4))
      if (s == "CLOSED") { found = 1 }
    }
    END { exit(found ? 0 : 1) }
  '
}

# Which chores does this change RECORD as completed? A CHORE-NNN whose archive
# line is in the new STATUS.md and was not in the old one. The before-and-after is
# the same shape the spec rule uses and it exists for the same reason: a chore that
# was already archived closes nothing now, so re-merging beside a months-old
# archive line is not a route onto the trunk. That is the laundering B6 closed for
# specs, refused here before it can be found for chores.
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

# THE CLOSE VERIFICATION, over the index.
#
# It identifies what is being closed by CONTENT rather than by ref name, and
# that is not a convenience. Measured on git 2.x: during pre-merge-commit of a
# clean automatic merge, MERGE_HEAD does not exist (only AUTO_MERGE and
# ORIG_HEAD), so there is no merged ref name to read. Asking "which specs does
# this change close" is answerable from the index alone, and it is the same
# question scripts/trunk-audit.sh asks of history.
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
  # THE STATUS IS CARRIED ACROSS THE SUBSHELL, and it was not.
  #
  # `x="$(f)"` runs f in a SUBSHELL, so a refusal recorded by slh_refuse inside
  # it sets SLH_REFUSED in a process that then exits. The reason reached stderr
  # and the decision reached nobody: a bad "roles" shape printed SLH-ROLES-SHAPE
  # and the merge landed anyway. Found while asserting the role class by outcome
  # rather than by message, which is the whole argument for outcome assertions.
  if ! role_paths="$(slh_role_paths "$proj")"; then
    SLH_REFUSED=1
    return 1
  fi

  # LIVE TEXT AT THE SOURCE (2026-08 consolidation, the F2 class made a rule).
  # Every reader below this point, the row readers included, judges STATUS.md
  # by what a human sees in the rendered file: a fenced example row, a
  # commented-out row or an indented illustration is not an inventory row. The
  # strip happens ONCE, here, so a reader added later cannot be blind by
  # default the way slh_chores_completed was. Both directions matter: a hidden
  # row in the NEW text could excuse a close the visible file never recorded,
  # and a fenced example in the OLD text made an honest close read as not new
  # (measured: SLH-CLOSES-NO-SPEC refused a fully compliant close because a
  # how-to illustration mentioned its row).
  status_new="$(slh_index_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"
  status_old="$(slh_head_show "$proj" specs/STATUS.md | awk "$SLH_LIVE_TEXT_AWK")"

  # Which specs does this change CLOSE? A spec whose row reads CLOSED now and
  # did not before. A spec that was already CLOSED closes nothing, which is the
  # laundering route B6 closed in the audit and which this mirrors.
  # THE UNION, NOT THE INTERSECTION (v1.7 claims audit, R3-2).
  #
  # This loop used to iterate over $spec_files, the STAGED spec files, so the
  # closing set was the intersection of "row flipped to CLOSED" and "spec file
  # touched by this change". A row flipped to CLOSED in specs/STATUS.md WITHOUT
  # editing the spec file was therefore never examined: it satisfied nothing and
  # was checked by nothing. Measured before this fix: a branch that properly
  # closes one spec and flips a second spec's row to CLOSED in the same
  # STATUS.md merged at rc=0, and the trunk carried that second spec as CLOSED
  # with no Closing report, no QA verdict and no diagram field, while the audit
  # reported the merge clean.
  #
  # The documentation said "the specs whose inventory row flips to CLOSED in
  # this same change", which is the right rule and was not the implemented one.
  # The rule is the row flip. Where the spec FILE lives is a separate question,
  # answered per spec below.
  closing_specs=""
  for num in $(slh_rows_newly_closed "$status_new" "$status_old"); do
    # SORT ORDER IS NOT A CHOICE OF SPEC (leg F6). This read
    # `grep -E "^specs/${num}[a-z]*-" | head -n1`, and both git commands that
    # feed it emit SORTED paths, so specs/0002-other-design.md beat
    # specs/0002-other.md ('-' is 0x2d, '.' is 0x2e) and a companion document
    # decided the close. Measured both ways: a non-compliant spec merged clean
    # once a companion existed, and a fully compliant close was refused with a
    # message that was false about the file it named. The advisory gate has
    # counted the matches and refused CG-SPEC-DUPLICATE since 1.0.x; the layer
    # carrying the guarantee never got it.
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

  # Is feature code arriving? Any staged path under a declared role.
  # NORMALISED, not used raw. A role recorded as "./src" or "/src" makes this
  # anchor `^./src/` or `^//src/`, which matches no staged path, so carries_code
  # stays 0 and the closes-no-spec refusal cannot fire: the guarantee layer goes
  # blind on a value nothing rejects (1.1.0 adversarial review, second run). The same
  # normalisation is applied in scope-hook.sh and trunk-audit.sh, which is the
  # point: a role path has to mean the same thing in all three or the layers
  # stop covering each other.
  local carries_code=0 rp
  if [ -n "$role_paths" ]; then
    for rp in $role_paths; do
      while [ "${rp#./}" != "$rp" ]; do rp="${rp#./}"; done
      rp="$(printf '%s' "$rp" | tr -s '/')"
      rp="${rp#/}"
      rp="${rp%/}"
      [ -n "$rp" ] && [ "$rp" != "." ] || continue
      # A ROLE MAY NAME A FILE, not only a directory (1.1.0 final leg, F5). This
      # required a trailing slash, so a flat-root instance whose role is
      # "app.js" could never set carries_code and SLH-CLOSES-NO-SPEC never
      # fired: unreviewed code merged onto the trunk and pushed. Both siblings
      # already matched `<role>` OR `<role>/`; the guarantee layer alone did not.
      if printf '%s\n' "$staged" | grep -qE "^${rp}(/|$)"; then carries_code=1; break; fi
    done
  fi

  # THE CHORE ROUTE (v1.7 gate, F30). Part 5b has always prescribed a
  # `chore/<slug>` branch merged --no-ff for maintenance that touches role paths,
  # and this check refused exactly that, then advised the operator to "route it as
  # a chore branch" while they were standing on one. The route was real and the
  # enforcement had nothing to read, because the edition described the archive line
  # without ever saying what one looked like. Part 5b now defines the form and this
  # reads it.
  #
  # Identity is by CONTENT, like everything else here, and that is forced rather
  # than chosen: MERGE_HEAD, MERGE_MSG and SQUASH_MSG are all absent at
  # pre-merge-commit time (measured 2026-08-02), so the branch NAME is genuinely
  # unavailable and a rule keyed on `chore/` could not be written even if it were
  # wanted. A chore is recognised by the completion it RECORDS, which is also why
  # a branch that records nothing is refused exactly like an unspecced feature: it
  # is indistinguishable from one, and the edition now says so.
  local closing_chores
  closing_chores="$(slh_chores_completed "$status_new" "$status_old")"

  if [ "$carries_code" = "1" ] && [ -z "$closing_specs" ] && [ -z "$closing_chores" ]; then
    slh_refuse "SLH-CLOSES-NO-SPEC" "$what brings feature code to $trunk without closing any spec that was not already CLOSED, and without recording a completed chore. Work reaches the trunk through a closed spec or a recorded chore. If this is deliberate maintenance, add its archive line to specs/STATUS.md in this same commit, in the form: - CHORE-007: DONE $(date +%F). <what changed>"
  fi

  # Every spec this change closes must satisfy the close conditions, read from
  # the index rather than from a branch tip.
  local entry
  for entry in $closing_specs; do
    num="${entry%%:*}"; f="${entry#*:}"
    text="$(slh_index_show "$proj" "$f")"

    # A FENCED EXAMPLE IS NOT A CLOSING REPORT. Ported from close-gate.sh, which
    # learned it as leg 5's F7; this layer never got it, so a spec whose entire
    # Closing report was a quoted ```markdown example satisfied all four checks
    # below at once and really merged (v1.7 gate, adversarial review F9).
    #
    # Not a contrived input: the template ships in setlist.md as a fenced block
    # carrying exactly these markers, it is stamped to specs/TEMPLATE.md, and the
    # spec-authoring skill tells authors to copy it. A spec that quotes its own
    # template is ordinary authoring.
    #
    # Stripped ONCE here rather than inside each check, so the four cannot drift
    # apart the way the report checker's readers did.
    #
    # NARROWED for the 1.1.0 adversarial review F6: dropping EVERY fenced span also
    # dropped a QA Pass 1 report pasted inside a fence, which is what Appendix
    # C's "(pasted verbatim)" means for tool output. This layer is the guarantee
    # rather than the advisory one, so it was the layer refusing compliant work
    # with SLH-NO-QA-VERDICT. A block is a TEMPLATE QUOTE exactly when its own
    # body carries a Closing-report heading; anything else in a fence is content.
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
    # A FIELD, NOT A SUBSTRING (1.1.0 adversarial review, F8). Anchored past any list
    # bullet so ordinary prose repeating the label cannot decide the check, which
    # it did in both directions. `tail -n1` is kept so a revised spec's later
    # report still wins. Same change as close-gate.sh, which carries the reasoning.
    diag="$(printf '%s\n' "$text" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | tail -n1)"
    if [ -z "$diag" ]; then
      slh_refuse "SLH-NO-DIAGRAM-FIELD" "spec $num is missing the mandatory field 'Architecture diagram: updated in this commit | no impact'."
    else
      answer="${diag#*Architecture diagram:}"
      # PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11). This blanked the answer
      # on any '<', which was written for the template's own
      # `<updated in this commit | no impact>` and fired on ordinary prose: a
      # comparison, a generic, an HTML comment. Measured:
      # `updated in this commit (added <auth> box)` was refused.
      # Stripping <...> spans and THEN requiring the answer settles both directions,
      # because the genuine unfilled template strips to nothing and stays refused.
      # Asserted across the value space rather than at a spelling: this field has
      # been corrected three times, twice by repairing only the case reported.
      answer="$(printf '%s' "$answer" | sed 's/<[^>]*>//g')"
      if ! printf '%s' "$answer" | grep -qE 'updated in this commit|no impact'; then
        slh_refuse "SLH-DIAGRAM-UNANSWERED" "spec $num's architecture-diagram field is unanswered; answer it 'updated in this commit' or 'no impact'."
      fi
    fi
  done

  [ "$SLH_REFUSED" = "0" ]
}

# The project's own gate command. This is THE expensive check, and the reason
# the close verification belongs at merge time rather than on every commit: it
# can be the full project suite. A gate_command that is absent means the project
# declared none; a gate_command that FAILS refuses the merge.
slh_run_gate_command() { # slh_run_gate_command <proj>
  local proj="$1" cmd out rc last
  # AN EMPTY gate_command IS THE STAMPED DEFAULT, SO SKIPPING IT SILENTLY WAS A
  # FAIL-OPEN IN THE DEFAULT STATE (v1.7 claims round 6, finding 3).
  #
  # This used to read "an absent gate_command means the project declared none,
  # and skipping it is then correct". That is true before /scaffold and false
  # after it: templates/claude/sdd.json.tmpl ships gate_command empty, /scaffold
  # is what records it, and `scaffolded: true` is the flag that says the project
  # has been through that step. A scaffolded instance with no gate_command is
  # therefore not a project that declared none, it is a project whose suite
  # nobody wired, and every close merged with no suite run, no code and nothing
  # on stderr. Measured: identical merge refused SLH-GATE-COMMAND-FAILED with
  # gate_command "false", accepted silently with gate_command "".
  #
  # Permissive on MISSING EVIDENCE was the one such path left in this file, and
  # it is the class the banner above says was removed. Before scaffolding the
  # skip is still right, so the flag decides.
  # fail-open-ok: a jq that cannot read the file yields empty, which the
  # scaffolded test below turns into a refusal rather than a skip.
  cmd="$(jq -r '.gate_command // empty' "$proj/.claude/sdd.json" 2>/dev/null || true)"
  if [ -z "$cmd" ]; then
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
  # 127 is "a command in the gate was not found", which is a DIFFERENT fact from
  # "the suite failed": it means the gate did not run and so proves nothing
  # either way. Hooks run in a bare shell, so a gate command that relies on an
  # activated virtualenv or a version-manager shim hits this while the operator's
  # own shell runs it green.
  if [ "$rc" = "127" ]; then
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($cmd) could not RUN here (exit 127, a command was not found), so it proves nothing about this work. Hooks run it in a bare shell: if your toolchain lives in a virtualenv or a version-manager shim, put the activation inside gate_command itself. Last output: $last"
  else
    slh_refuse "SLH-GATE-COMMAND-FAILED" "the project gate command ($cmd) does not pass (exit $rc), so this work is not ready to reach the trunk. Last output: $last"
  fi
  return 1
}
