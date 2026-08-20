#!/usr/bin/env bash
# Trunk audit: does the trunk's HISTORY show every piece of feature code
# arriving through a closed spec?
#
# Usage:
#   trunk-audit.sh [<instance-dir>] [--since <ref>]
#
# ADVISORY as of plugin 1.0.5. Nothing calls this automatically: it is not
# wired as a hook, it does not gate a commit, and a finding does not block
# anything. Run it by hand or from /setlist:validate. That is deliberate for
# a first release, because it reads real project history and real history is
# the only honest test of it.
#
# Why this exists, and why it is different in kind from the hooks. The three
# PreToolUse gates decide by parsing a shell command before it runs, and a
# shell command can compute its own arguments: no parser can be correct about
# what a command will do. Four releases of this plugin were spent improving
# that parser, and each improvement was itself the next release's defect. This
# asks a question that needs no parsing at all, and is decidable:
#
#   Every commit on the trunk that touches a role path is either part of a
#   merge from a branch whose spec carries a Closing report and a CLOSED
#   inventory row, or it is a violation.
#
# That catches what the parser misses BY CONSTRUCTION: chained merges, a
# branch renamed to hide it, a cherry-pick, a tag, a squash, the forge's merge
# button, and the ways nobody has thought of yet. All of them leave history,
# and history is what this reads.
#
# What it cannot do, stated so it is not oversold:
#   - A squash merge has no second parent, so the branch it came from is not
#     recoverable from history. Squashed work is reported as a direct commit.
#   - Rewritten or force-pushed history defeats it, as it defeats any audit.
#   - It says nothing about whether the QA behind a Closing report was honest.
#     It checks that the artifacts exist, not that they were earned.

set -u

INSTANCE="."
SINCE=""
# --until <ref>: audit the history ending at THIS commit rather than at the
# trunk's current tip. Added 2026-08-04 for pre-push, which receives the OID
# actually being pushed and must audit that rather than whatever the local trunk
# happens to point at (1.1.0 leg, F17). Defaults to the trunk, which is every
# other caller and the behaviour this script has always had.
UNTIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --until) UNTIL="${2:-}"; shift 2 ;;
    *) INSTANCE="$1"; shift ;;
  esac
done

die() { printf 'trunk-audit.sh: %s\n' "$1" >&2; exit 2; }

[[ -d "$INSTANCE" ]] || die "not a directory: $INSTANCE"
command -v jq >/dev/null 2>&1 || die "jq is required to read .claude/sdd.json"

# THE TOOLCHAIN PROBE (2026-08-07 leg, F2).
#
# setlist-hook-lib.sh has carried slh_require_toolchain since the run that
# measured a broken grep letting an unclosed spec merge at rc=0 in silence. It
# was wired into the three git hooks and NOT into this file, which is the
# standalone invocation the README documents and the one a CI job would call.
#
# Here the failure was worse than a missed detection: it FLIPPED the verdict.
# The parent count below used to read `wc -w | tr -d ' '`; a broken tr yields
# the empty string, `[[ "" -lt 2 ]]` is true in bash arithmetic, so every merge
# commit was classified as a non-merge, skipped the entire merged-parent loop,
# and landed in the "clean" bucket at exit 0. This script has an "unverifiable"
# bucket for the cases history cannot decide, and that path did not route there
# either: it reported a violating trunk as clean, silently.
#
# The probe is INLINE rather than sourced from the library. This file is copied
# into instances on its own and the library is not always beside it, so a
# discovery failure would be one more way to end up unprobed. That buys a
# lockstep obligation instead, which the suite asserts: both probes must cover
# the same four tools, and this one must die rather than warn. The tr on the
# parent count is also gone, because `wc -w` compares correctly under bash
# arithmetic without stripping, and a check that needs no tool cannot be broken
# by one.
probe_tool() { # probe_tool <name> <expected> <command...>
  local name="$1" want="$2" got; shift 2
  got="$(printf 'x\n' | "$@" 2>/dev/null)" || got="" # fail-open-ok: a failure leaves got empty, which is not the expected value, so the guard below fires
  # `wc -l` pads with leading spaces on macOS, and the first cut of this probe
  # compared the padded output to "1" and would have refused on a HEALTHY
  # system. Normalised with a builtin rather than a tool, because normalising
  # the toolchain probe with a member of the toolchain is circular.
  got="${got//[[:space:]]/}"
  [ "$got" = "$want" ] && return 0
  printf 'trunk-audit.sh [SLH-NO-TOOLCHAIN]: %s is installed but does not work here, so this audit cannot read the trunk and would otherwise report it clean. Run '"'"'%s --version'"'"' to see the failure. The audit stops rather than passing.\n' "$name" "$name" >&2
  exit 2
}
probe_tool awk  x awk '{ print }'
probe_tool sed  y sed 's/x/y/'
probe_tool tr   y tr 'x' 'y'
probe_tool grep x grep -E '^x$'
# The tools above are the library's set. These are the ones THIS file also
# decides with, and leaving them unprobed is what let the cut fail-open ship.
probe_tool cut  x cut -c1
probe_tool wc   1 wc -l
probe_tool head x head -n1
probe_tool tail x tail -n1
probe_tool sort x sort
SDD="$INSTANCE/.claude/sdd.json"
[[ -f "$SDD" ]] || die "no .claude/sdd.json at $INSTANCE; this is not a framework instance"
jq -e . "$SDD" >/dev/null 2>&1 || die "$SDD does not parse"

TRUNK="$(jq -r '.trunk // "main"' "$SDD")"
# ONE EXPRESSION, THREE READERS (1.1.0 leg, fourth run, F8).
#
# These three read .roles and they DISAGREED in two ways at once. This file used
# `to_entries[] | .value`, which does not flatten, so a LIST-valued role path
# printed raw JSON: the role list came back as the lines '[', '  "packages/app",',
# '  "packages/lib",', ']', none of which is a path, carries_code stayed 0, and an
# unclosed spec branch merged past the GUARANTEE layer in silence. Measured with a
# control: the same fixture with roles.src as a string is refused
# SLH-CLOSES-NO-SPEC. A list is not exotic; the edition's own Part 3 names
# `packages/*` when it says paths are roles.
#
# The second disagreement was quieter: this file counted EVERY declared role key
# while the other two read only src and tests, so a project declaring a third role
# was governed differently by the gate and by its backstop.
#
# The unified rule: every declared role value, flattened, strings only, falling
# back to src and tests when .roles is absent or empty so a project that declares
# nothing still gets the documented defaults. The suite asserts all three copies
# produce identical output over a corpus of role shapes, because byte-identity of
# the expression is not the same claim as agreement on behaviour, and F8 drifted
# in a file that had neither.
mapfile_roles() { jq -r 'if ((.roles // {}) | length) == 0 then ["src","tests"] else [(.roles // {}) | .[]] end | flatten | .[] | select(type == "string")' "$SDD"; }
# THE SHAPE, in lockstep with the other two readers (1.1.0 final leg, F13).
if [[ "$(jq -r 'if (.roles == null) then "absent" elif ((.roles | type) == "object") then "ok" else "bad" end' "$SDD" 2>/dev/null)" == "bad" ]]; then
  die ".claude/sdd.json has a \"roles\" value that is not an object, so the role paths this audit reads cannot be established and it would report a trunk carrying unreviewed feature code as clean. Set \"roles\" to an object, or remove the key to accept the defaults."
fi
ROLES="$(mapfile_roles)"
[[ -n "$ROLES" ]] || die "no role paths recorded in $SDD"

git -C "$INSTANCE" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 \
  || die "the recorded trunk '$TRUNK' does not resolve in this repository"

# THE TRUNK VALUE MUST NAME A LOCAL BRANCH, and "it resolves" is not that check.
# A remote-tracking spelling resolves perfectly well, which is why the rev-parse
# above passed it straight through: this script then audited refs/remotes/origin/
# main, the violating merge on LOCAL main was simply not in the range, and it
# reported "1 clean, 0 violations" at exit 0 while pre-push allowed the push
# (v1.7 dogfood gate, hostile leg F10). Same root cause as slh_trunk's, different
# file, so fixing the library does not fix this.
#
# Reduced by ASKING GIT, the same way close-gate.sh and setlist-hook-lib.sh do.
# The three are deliberately identical here; the suite asserts the outcome of all
# three rather than the text, because this is the third place the rule lives.
if ! git -C "$INSTANCE" show-ref --verify --quiet "refs/heads/$TRUNK" 2>/dev/null; then
  TRUNK_FULL="$(git -C "$INSTANCE" rev-parse --symbolic-full-name "$TRUNK" 2>/dev/null || true)" # fail-open-ok: an unresolvable spelling leaves TRUNK unchanged and is refused by the show-ref check below, never audited
  case "$TRUNK_FULL" in
    refs/heads/*)
      TRUNK="${TRUNK_FULL#refs/heads/}"
      ;;
    refs/remotes/*)
      TRUNK_CAND="${TRUNK_FULL#refs/remotes/}"
      TRUNK_CAND="${TRUNK_CAND#*/}"
      if git -C "$INSTANCE" show-ref --verify --quiet "refs/heads/$TRUNK_CAND" 2>/dev/null; then
        TRUNK="$TRUNK_CAND"
      fi
      ;;
  esac
  git -C "$INSTANCE" show-ref --verify --quiet "refs/heads/$TRUNK" 2>/dev/null \
    || die "the recorded trunk '$TRUNK' is not a local branch in this repository, so this audit would read a ref that is not the trunk being pushed and could report it clean. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main."
fi

# The tip to audit. --until names it explicitly; otherwise it is the trunk.
# Refused rather than defaulted if it does not resolve, because an unresolvable
# tip would walk no commits and report a clean trunk, turning a typo into an
# attestation.
AUDIT_TIP="$TRUNK"
if [[ -n "$UNTIL" ]]; then
  git -C "$INSTANCE" rev-parse --verify --quiet "${UNTIL}^{commit}" >/dev/null 2>&1 \
    || die "the --until value '$UNTIL' does not resolve to a commit in this repository, so there is nothing to audit and a clean report would be a false attestation."
  AUDIT_TIP="$UNTIL"
fi

# Baseline. Everything before the instance was stamped is pre-framework and
# not this audit's business; auditing it would produce noise that trains the
# reader to ignore the report.
if [[ -z "$SINCE" ]]; then
  SINCE="$(git -C "$INSTANCE" log --format=%H --diff-filter=A -- .claude/sdd.json | tail -n1)"
  [[ -n "$SINCE" ]] || die "cannot find the commit that introduced .claude/sdd.json; pass --since <ref>"
fi

# The baseline must RESOLVE. Since an empty range now reports clean, a --since
# that names nothing would otherwise walk no commits and report a clean trunk,
# turning a typo into an attestation. Checked explicitly rather than inferred
# from the walk being empty, because those are different facts.
git -C "$INSTANCE" rev-parse --verify --quiet "${SINCE}^{commit}" >/dev/null 2>&1 \
  || die "the baseline '$SINCE' does not resolve to a commit in this repository, so the audit cannot establish what to walk. Pass a --since that names a commit on the trunk."

printf 'trunk audit: %s\n' "$(cd "$INSTANCE" && pwd)"
printf '  trunk: %s   roles: %s\n' "$TRUNK" "$(printf '%s' "$ROLES" | tr '\n' ' ')"
printf '  since: %s (%s)\n\n' "$(git -C "$INSTANCE" rev-parse --short "$SINCE")" \
  "$(git -C "$INSTANCE" log -1 --format=%s "$SINCE" | cut -c1-60)"

row_is_closed() { # row_is_closed <status-md-text> <spec-num>
  # The status is a CELL, not a word anywhere in the row (leg 5, F8). Factored
  # out in the B6 fix because the audit now asks this question twice: once of
  # the merged branch (did it close the spec?) and once of the trunk BEFORE the
  # merge (was it already closed, so this merge closed nothing?).
  # GFM escaped pipe is literal, not a field separator (round 11); it never
  # appears in the number or status cell, so a space keeps the field count right.
  printf '%s\n' "$1" | sed 's/\\|/ /g' | awk -F'|' -v num="$2" '
    function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
    NF >= 5 && trim($2) == num && trim($4) == "CLOSED" { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

# IS THIS FILESYSTEM CASE-INSENSITIVE? (F8 of the 2026-08-05 leg.)
#
# The README claimed the case-variant hole was MINOR because "the trunk audit
# catches it: git stores the path under its on-disk spelling, so the commit is
# reported as feature code on the trunk". Measured, that reasoning silently
# assumed the role directory ALREADY EXISTS in its canonical spelling, so a
# case-insensitive filesystem folds the variant back before git sees it. When
# the directory does not exist, git records the literal `TESTS/foo.js`, the
# audit's role matching is case-sensitive too, and BOTH layers miss it: the
# advisory gate and the guarantee layer, with the push succeeding.
#
# So the audit matches role paths case-insensitively exactly when the
# filesystem is case-insensitive, which is when `TESTS/` and `tests/` are the
# same directory and treating them as different is the mistake. On a
# case-sensitive filesystem they really are different directories and matching
# them together would cry wolf about a path that is genuinely not a role path.
# The probe is done once rather than per file.
ROLE_FOLD=0
_rfprobe="$(mktemp -d "${TMPDIR:-/tmp}/setlist-case.XXXXXX")"
: > "$_rfprobe/aa"
[[ -e "$_rfprobe/AA" ]] && ROLE_FOLD=1
rm -rf "$_rfprobe"

touches_role_file() { # touches_role_file <path> -> 0 if the path is under a role
  local f="$1" r
  if [[ "$ROLE_FOLD" -eq 1 ]]; then f="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')"; fi
  while IFS= read -r r; do
    [[ -n "$r" && "$r" != "." ]] || continue
    while [[ "$r" == ./* ]]; do r="${r#./}"; done
    r="$(printf '%s' "$r" | tr -s '/')"
    r="${r#/}"; r="${r%/}"
    [[ -n "$r" && "$r" != "." ]] || continue
    if [[ "$ROLE_FOLD" -eq 1 ]]; then r="$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')"; fi
    case "$f" in "$r"/*|"$r") return 0 ;; esac
  done <<EOF
$ROLES
EOF
  return 1
}

touches_role() { # touches_role <from> <to>
  # ONE ROLE RULE, not two. This used to carry its own copy of the
  # normalise-and-match logic that touches_role_file also carries, and the two
  # drifted the moment one was fixed: the case-folding repair for F8 of the
  # 2026-08-05 leg landed in touches_role_file, while THIS function decides the
  # direct-commit case, so the variant stayed invisible and the fix read as
  # ineffective. Two copies of a rule is the shape of leg 5's F8 and of item 35;
  # it is also what this file's own comments warn about. So the per-file
  # decision is made in exactly one place and this walks the diff.
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    touches_role_file "$f" && return 0
  done < <(git -C "$INSTANCE" diff --name-only "$1" "$2" 2>/dev/null)
  return 1
}

touches_role_tree() { # touches_role_tree <commit>
  # The same question as touches_role, asked of a commit that has NO parent to
  # diff against: does its own tree carry role-path code? Routed through
  # touches_role_file for the reason the comment above gives, so the normalise
  # and match rule still exists in exactly one place.
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    touches_role_file "$f" && return 0
  done < <(git -C "$INSTANCE" ls-tree -r --name-only "$1" 2>/dev/null)
  return 1
}

# ===========================================================================
# WHEN DID THE RULES START? (F2 and F7 of the 2026-08-05 leg.)
#
# A chore-shaped merge with no recorded completion was reported "unverifiable"
# and tallied as a CHORE, leaving VIOLATIONS at 0 and the exit code at 0, which
# is the only thing pre-push reads. So a merge that reached the trunk WITHOUT
# firing pre-merge-commit (detached HEAD, --no-verify, core.hooksPath=/dev/null,
# SETLIST_SKIP_HOOKS, and by commit shape the forge merge button) was excused by
# the backstop and pushed clean, while README:182 names those routes and claims
# "Every one of them is caught by the trunk audit below".
#
# THE DERIVATION, because the previous repair here patched a case rather than a
# class: this block's own comment justifies the excuse by ANTIQUITY, "predates
# the archive-line rule". But the code decided by SHAPE. Shape is a proxy for
# age and it is a bad one, because a merge made today that skipped the hook has
# exactly the same shape as one made before the rule existed. The last repair
# added NPAR>2 to the enumeration and left the ordinary two-parent case, which
# is the common one, still excused.
#
# So the question is answered directly instead: when did this instance adopt the
# rules? The stamp writes .claude/sdd.json, so the commit that ADDED it is the
# baseline. A merge that descends from that commit is not pre-rule history and
# gets no exemption. A merge that does not is genuinely older and keeps it,
# which is the restraint that stops the backstop crying wolf about the past.
#
# IF NO BASELINE CAN BE ESTABLISHED the exemption is refused rather than
# granted. The exemption is a claim about being older than the rules; an audit
# that cannot say when the rules started cannot grant it. This is the fail-CLOSED
# direction, chosen deliberately: the fail-open one is the finding.
RULE_BASELINE="$(git -C "$INSTANCE" log --diff-filter=A --format=%H -- .claude/sdd.json 2>/dev/null | tail -n1)" # fail-open-ok: an empty baseline is handled explicitly below and refuses the exemption rather than granting it
if [[ -z "$RULE_BASELINE" ]]; then
  RULE_BASELINE="$(git -C "$INSTANCE" log --diff-filter=A --format=%H -- .githooks/setlist-hook-lib.sh 2>/dev/null | tail -n1)" # fail-open-ok: as above; both absent means no exemption is available at all
fi

# post_baseline <commit> -> 0 when the commit is at or after the instance
# adopted the rules, so the pre-rule exemption does not apply to it.
post_baseline() {
  [[ -n "$RULE_BASELINE" ]] || return 0
  git -C "$INSTANCE" merge-base --is-ancestor "$RULE_BASELINE" "$1" 2>/dev/null
}

# in_established_history <commit> -> 0 when the commit belongs to the history
# the stamp sits in, which is what makes a PARENTLESS commit this repository's
# own root rather than one injected over the trunk.
#
# Note the direction: post_baseline asks whether the BASELINE is an ancestor of
# the commit (is this newer than the rules), and this asks the reverse (is this
# older than, or is, the stamp). An injected orphan answers no to BOTH, because
# it shares no history with the baseline in either direction, and that is
# precisely what distinguishes it from the root.
#
# No baseline means no exemption, the same fail-CLOSED choice post_baseline
# documents: the fail-open direction is the finding.
in_established_history() {
  [[ -n "$RULE_BASELINE" ]] || return 1
  git -C "$INSTANCE" merge-base --is-ancestor "$1" "$RULE_BASELINE" 2>/dev/null
}

VIOLATIONS=0
AUDITED=0
CLEAN=0
CHORES=0

# HOISTED so the linear close check above the merged-parent loop can use it.
# LOCKSTEP: close-gate.sh and setlist-hook-lib.sh carry this same program byte
# for byte and the suite asserts all three are identical, and since the 2.0.0
# leg (F8) also that they AGREE BY OUTCOME over a corpus, because this audit
# was blind in lockstep with the hooks it backstops. The reader is scoped: the
# deciding block is the last qa-pass-1 fence at fence depth zero inside a
# Closing report section; close-gate.sh carries the full reasoning.
QA_PASS1_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; qa_seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } } else { if (__r == "qa-pass-1" && inclose) { inb = 1; qch = __c; qlen = __m; n = 0; bad = 0; next } fence = 1; fch = __c; flen = __m; next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "") next; if (l ~ /^[A-Za-z0-9._-]+[[:space:]]*:[[:space:]]*(PASS|PARTIAL|FAIL)$/) n++; else bad = 1; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) inclose = 0 } } END { if (incmt) print "unclosed-comment"; else if (inb) print "unclosed"; else if (!qa_seen) print "none"; else if (bad) print "malformed"; else if (n == 0) print "empty"; else print "ok" }'

# HOISTED, same reason as QA_PASS1_AWK above: the linear close check needs it
# too. LOCKSTEP: byte-identical to close-gate.sh and setlist-hook-lib.sh. Strips
# a fenced block that itself carries a "Closing report" heading (a quoted
# template example) and deletes HTML comment spans; kept narrow on purpose so a
# real pasted qa-pass-1 fence survives for QA_PASS1_AWK to find.
TEMPLATE_FENCE_AWK='function __f(k,  i){ if(k) for(i=1;i<=n;i++) print b[i]; n=0 } { __l=$0; sub(/\r$/,"",__l); sub(/^[[:space:]]*/,"",__l); if (incmt) { __cb[++__cn]=$0; if (index(__l, "-->")) { incmt = 0; __cn=0 } next } if (!fence && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; __cn=0; __cb[++__cn]=$0; next } __c=substr(__l,1,1); if ((__c=="`" || __c=="~") && $0 ~ /^ ? ? ?[`~]/) { __m=0; while(substr(__l,__m+1,1)==__c) __m++; __raw=substr(__l,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { if (!fence) { fence=1; fch=__c; flen=__m; n=0; t=0; b[++n]=$0; next } else if (__c==fch && __m>=flen && __r=="") { fence=0; b[++n]=$0; __f(!t); next } } } if (fence) { b[++n]=$0; if($0 ~ /^ ? ? ?#+[ \t]+Closing report/) t=1; next } print } END { if(fence) __f(!t); if(incmt) for(__ci=1;__ci<=__cn;__ci++) print __cb[__ci] }'

# LIVE TEXT ONLY (2026-08 consolidation, blocker F2). LOCKSTEP: byte-identical to
# setlist-hook-lib.sh, which carries the full reasoning. Strips fenced blocks,
# HTML comment spans and indented-code lines before a plain grep looks for a
# chore archive line, so an illustration cannot be counted as a record.
SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

while IFS= read -r C; do
  [[ -n "$C" ]] || continue
  AUDITED=$((AUDITED + 1))
  # NO EXTERNAL TOOL DECIDES THE PARENT STRUCTURE (2026-08-08 pre-stress).
  #
  # These three lines read `| cut -d' ' -f2-`, `| wc -w` and `| cut -d' ' -f1`.
  # A broken cut yields the empty string, NPAR became 0, `[[ 0 -lt 2 ]]` is true,
  # so every merge was classified a non-merge, skipped the merged-parent loop
  # below, and a violating trunk was reported CLEAN at exit 0 with no reason
  # printed. That is the same fail-open the tr bug had, one tool over, sitting
  # inside the fix written for the tr bug.
  #
  # The probe below now covers cut and wc, but a probe is the second line of
  # defence. Word-splitting a space-separated list is something the shell does
  # natively, so this asks no tool anything and cannot be broken by one.
  PARENT_LIST="$(git -C "$INSTANCE" rev-list --parents -n1 "$C")"
  # shellcheck disable=SC2206 # deliberate word-splitting: git prints one line of hashes
  PARENT_ARR=( $PARENT_LIST )
  P1="${PARENT_ARR[1]:-}"
  PARENTS="${PARENT_ARR[*]:1}"
  NPAR=$(( ${#PARENT_ARR[@]} - 1 ))
  SUBJ="$(git -C "$INSTANCE" log -1 --format=%s "$C" | cut -c1-58)"
  SHORT="$(git -C "$INSTANCE" rev-parse --short "$C")"

  if [[ "$NPAR" -lt 2 ]]; then
    # CLOSE VERIFICATION BINDS TO THE EVENT, NOT TO THE MERGE SHAPE (v1.7 claims
    # confirmation). Every close condition used to live inside the merged-parent
    # loop below, reachable only past this NPAR>=2 guard, so a close that
    # produced no merge commit was never checked at all. Two ordinary honest
    # routes hit that: a `git merge --ff` of a linear spec branch, and a
    # docs-only commit that flips a STATUS row to CLOSED, which this framework
    # explicitly permits on the trunk.
    #
    # This is R3-2 one level up. There, the close set was the intersection of
    # row-flipped and file-touched instead of the row-flip itself; here, the
    # check was bound to the shape that usually carries the event instead of to
    # the event. The rule is the ROW FLIP, and it is asked of every commit.
    if [[ -n "$P1" ]]; then
      # LIVE TEXT AT THE SOURCE (2026-08 consolidation): the row readers judge
      # STATUS.md by what the rendered file shows, so a fenced example row or a
      # commented-out row is not an inventory row here either. Stripped once at
      # extraction, in lockstep with the library's guard_close.
      LIN_NEW="$(git -C "$INSTANCE" show "$C:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"   # fail-open-ok: no STATUS.md at this commit yields empty, so no row can be read as newly closed, which is correct for a repository that has none
      LIN_OLD="$(git -C "$INSTANCE" show "$P1:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"  # fail-open-ok: as above, an absent parent copy means every present row reads as new, which accuses rather than excuses
      for LIN_NUM in $(printf '%s\n' "$LIN_NEW" | sed 's/\\|/ /g' | awk -F'|' 'NF >= 5 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^[0-9]+[a-z]*$/) print $2 }'); do  # sed: GFM escaped pipe (round 11)
        row_is_closed "$LIN_NEW" "$LIN_NUM" || continue
        row_is_closed "$LIN_OLD" "$LIN_NUM" && continue
        # Same narrowing as the library (leg F6): the exact number then a
        # hyphen, and a count rather than head -n1, because 0002b is a
        # different spec and a pick among several is a guess.
        LIN_HITS="$(git -C "$INSTANCE" ls-tree -r --name-only "$C" 2>/dev/null | grep -E "^specs/${LIN_NUM}-[^/]*\.md$" || true)" # fail-open-ok: no file yields empty, handled as its own violation below
        if [ -n "$LIN_HITS" ] && [ "$(printf '%s\n' "$LIN_HITS" | grep -c .)" -ne 1 ]; then
          printf 'VIOLATION %s  spec %s has several files matching specs/%s-*.md, so its close cannot be verified: %s\n' \
            "$SHORT" "$LIN_NUM" "$LIN_NUM" "$(printf '%s' "$LIN_HITS" | tr '\n' ' ')"
          VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
          continue
        fi
        LIN_FILE="$LIN_HITS"
        if [[ -z "$LIN_FILE" ]]; then
          printf 'VIOLATION %s  spec %s marked CLOSED with no specs/%s-*.md to verify\n' "$SHORT" "$LIN_NUM" "$LIN_NUM"
          VIOLATIONS=$((VIOLATIONS + 1)); continue
        fi
        LIN_TEXT="$(git -C "$INSTANCE" show "$C:$LIN_FILE" 2>/dev/null || true)" # fail-open-ok: unreadable yields empty, which fails every condition below rather than passing them
        # A FENCED EXAMPLE IS NOT A CLOSING REPORT, here too (2026-08 consolidation).
        # This arm read LIN_TEXT raw while the merge arm below stripped SPEC_TEXT
        # through TEMPLATE_FENCE_AWK first: a spec whose Closing report existed
        # only inside a quoted ```markdown example satisfied the heading grep in
        # THIS arm alone. Stripped once, exactly as the merge arm does, so a
        # docs-only or fast-forward close is judged by the same reading as a
        # merge close.
        LIN_TEXT="$(printf '%s\n' "$LIN_TEXT" | awk "$TEMPLATE_FENCE_AWK")"
        LIN_MISS=""
        printf '%s\n' "$LIN_TEXT" | grep -qE $'^ {0,3}#{1,6}[ \t]+Closing report' || LIN_MISS="$LIN_MISS no-closing-report"
        [[ "$(printf '%s\n' "$LIN_TEXT" | awk "$QA_PASS1_AWK")" == "ok" ]] || LIN_MISS="$LIN_MISS no-qa-verdict"
        LIN_DIAG="$(printf '%s\n' "$LIN_TEXT" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | tail -n1)" # fail-open-ok: empty is the missing field, tested next
        LIN_ANS="$(printf '%s' "$LIN_DIAG" | sed -e 's/^[-*+>[:space:]]*Architecture diagram:[[:space:]]*//')"
        # PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11, here too). This arm
        # kept the pre-F11 predicate after the merge arm below was corrected, so
        # `updated in this commit (added <auth> box)` refused in this arm alone.
        # Same fix, same direction, same reasoning as the merge arm's DIAG_ANSWER.
        LIN_ANS="$(printf '%s' "$LIN_ANS" | sed 's/<[^>]*>//g')"
        if [[ -z "$LIN_DIAG" ]]; then LIN_MISS="$LIN_MISS no-diagram-field"
        elif ! printf '%s' "$LIN_ANS" | grep -qE 'updated in this commit|no impact'; then LIN_MISS="$LIN_MISS diagram-unanswered"; fi
        if [[ -n "$LIN_MISS" ]]; then
          printf 'VIOLATION %s  spec %s was marked CLOSED without:%s\n' "$SHORT" "$LIN_NUM" "$LIN_MISS"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      done
    fi
    # A PARENTLESS commit (F2 of the 2026-08-11 leg). This arm used to read
    # `[[ -n "$P1" ]] && touches_role "$P1" "$C"`, so a commit with no first
    # parent failed the guard, fell through to CLEAN, and was tallied as
    # audited having had its content examined by NOTHING. Measured: an orphan
    # commit force-pushed over the trunk was reported "1 clean, 0 violations"
    # at exit 0, and the whole trunk became one unreviewed file. That is the
    # fail-open class this script exists to refuse, sitting in the one branch
    # where the parent-diff predicate cannot be evaluated at all.
    #
    # THE TRAP, and why this is not simply "refuse parentless commits": every
    # repository's ROOT commit is parentless too, and it is entirely ordinary
    # for it to carry feature code. Shape cannot tell the two apart, because
    # the attack has exactly the root's shape. IDENTITY can: the real root is
    # an ancestor of the commit that stamped this instance, and an injected
    # orphan shares no history with the stamp whatsoever. That is the same
    # "answer the question directly rather than by proxy" move this file's
    # RULE_BASELINE comment already makes about the chore exemption.
    #
    # With no baseline the exemption is REFUSED rather than granted, matching
    # post_baseline: an audit that cannot say where its own history starts
    # cannot certify that a parentless commit belongs to it.
    if [[ -z "$P1" ]]; then
      if in_established_history "$C"; then
        CLEAN=$((CLEAN + 1))
      elif touches_role_tree "$C"; then
        printf 'VIOLATION %s  parentless commit carrying feature code offered as %s\n' "$SHORT" "$TRUNK"
        printf '          %s\n' "$SUBJ"
        printf '          It has no parent to diff against, so it was judged on its own tree.\n'
        printf '          It shares no history with the commit that stamped this instance, so\n'
        printf '          it cannot have closed a spec and is not this trunk being advanced.\n'
        VIOLATIONS=$((VIOLATIONS + 1))
      else
        CLEAN=$((CLEAN + 1))
      fi
      continue
    fi
    # A direct commit on the trunk. Docs-only is the allowed case the whole
    # loop exists to distinguish.
    if touches_role "$P1" "$C"; then
      printf 'VIOLATION %s  feature code committed directly to %s\n' "$SHORT" "$TRUNK"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
    else
      CLEAN=$((CLEAN + 1))
    fi
    continue
  fi

  if ! touches_role "$P1" "$C"; then
    CLEAN=$((CLEAN + 1))
    continue
  fi

  # EVERY merged parent, not just the second (1.0.5, found by attacking this
  # script). An octopus merge has three or more parents, and reading only
  # parent 2 validated the compliant spec branch while ignoring everything
  # else merged in the same commit: `git merge spec/0001-ok sneaky` put
  # unspecced feature code on the trunk and this reported "1 clean, 0
  # violations". That is the close gate's own defect class, examining one
  # thing when there are several, reproduced in the backstop written to catch
  # what the close gate misses.
  MERGED_PARENTS="${PARENT_ARR[*]:2}"
  SEEN_BAD=0
  SEEN_CHORE=0
  for P2 in $MERGED_PARENTS; do

    # Which spec did the merged branch carry? Read it from the branch side, so a
    # renamed branch or a lost branch name changes nothing.
    # Unrelated histories have no merge-base, leaving BASE empty so the diff
    # reads the whole branch. That over-reports spec files rather than under-
    # reporting them, and erring toward FINDING a spec errs toward CHECKING it.
    # fail-open-ok: an empty BASE widens the search, it does not skip it.
    BASE="$(git -C "$INSTANCE" merge-base "$P1" "$P2" 2>/dev/null || true)"
    # Spec numbers carry an optional letter suffix in the field: 0005b and
    # 0008c are ordinary parallel-track specs, and the first cut of this regex
    # required digits-then-dash, so it read every one of them as "no spec file"
    # and reported a compliant merge as a violation. Found by running against
    # real history, which is the only reason this leg was gated on doing so.
    # EVERY spec file the branch touched, not just the first (B6, leg 5 F29).
    # This carried `| head -n1`, and `git diff --name-only` emits path order, so
    # a branch touching an older ALREADY-CLOSED spec and a new non-compliant one
    # got the older, compliant spec validated and the real work never looked at.
    # A one-line amendment to a closed spec laundered an unspecified change onto
    # the trunk, and the audit reported it clean.
    SPECS_TOUCHED="$(git -C "$INSTANCE" diff --name-only "$BASE" "$P2" 2>/dev/null \
      | grep -E '^specs/[0-9]+[a-z]*-[^/]*\.md$' || true)"   # fail-open-ok: no match means no spec on the branch, handled as a chore below

    # fail-open-ok: same, an unreadable STATUS.md fails the row test below.
    # LIVE TEXT AT THE SOURCE (2026-08 consolidation): stripped ONCE at
    # extraction, so every consumer below, the chore greps AND the row readers,
    # judges the same text a human sees in the rendered file. A fenced example
    # row was reaching row_is_closed here while the chore grep was already
    # protected, which is the one-loop-over drift this round exists to end.
    STATUS_TEXT="$(git -C "$INSTANCE" show "$P2:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)" # fail-open-ok: an unreadable STATUS.md yields empty, which fails the row test and cannot excuse a merge
    # The trunk's STATUS as it stood BEFORE this merge. Used only to ask whether
    # a spec was ALREADY closed, so this merge cannot be what closed it. An
    # unreadable prior STATUS yields empty and row_is_closed then returns false,
    # which is the PERMISSIVE answer here: it can only ever suppress the
    # closes-no-spec finding below, never manufacture one. That direction is
    # deliberate, because a fabricated violation trains the reader to ignore
    # real ones, and this is a report rather than a gate.
    # fail-open-ok: empty prior STATUS suppresses a finding, it cannot invent one.
    PRIOR_STATUS="$(git -C "$INSTANCE" show "$P1:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"

    # THE CHORE ROUTE, IN LOCKSTEP WITH THE HOOKS (v1.7 gate, F30). Same rule,
    # same spelling, read from history instead of from the index: a merge that
    # RECORDS a chore completion in Part 5b's archive-line form, and did not
    # already have it, arrives legitimately.
    #
    # This block replaces a comment that asserted an agreement which did not
    # exist. It read "the close gate has the same limit and checks only the gate
    # command for chores", and the git-hook layer refused the chore merge
    # outright, so the backstop was documented as agreeing with a gate it
    # contradicted. That is this repository's signature defect, sitting in the
    # file written to be the guarantee's backstop.
    CHORE_DONE_RE='^[-*+>[:space:]]*(CHORE-[0-9]+)[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)'
    # LIVE TEXT ONLY (blocker F2): a fenced example, an HTML comment or an
    # indented illustration in STATUS.md must not count as an archive line here
    # either, or the backstop shares the hook's own blindness. The strip now
    # happens once at extraction above, so these greps read STATUS_TEXT and
    # PRIOR_STATUS directly and cannot diverge from the row readers beside them.
    CHORES_NOW="$(printf '%s\n' "$STATUS_TEXT" | grep -oE "$CHORE_DONE_RE" 2>/dev/null | grep -oE 'CHORE-[0-9]+' || true)"  # fail-open-ok: no archive line leaves this EMPTY, which cannot excuse a merge, only fail to excuse it
    RECORDED_CHORE=""
    while IFS= read -r CN; do
      [[ -n "$CN" ]] || continue
      if ! printf '%s\n' "$PRIOR_STATUS" | grep -qE "^[-*+>[:space:]]*${CN}[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)"; then
        RECORDED_CHORE="$CN"; break
      fi
    done <<< "$CHORES_NOW"

    if [[ -z "$SPECS_TOUCHED" ]]; then
      if [[ -n "$RECORDED_CHORE" ]]; then
        # Verifiable now, where it used to be unverifiable by construction. This
        # is the whole gain from giving the archive line a form: history can
        # answer the question rather than shrug at it.
        CLEAN=$((CLEAN + 1))
        continue
      fi
      # No spec and no recorded chore. Still UNVERIFIABLE rather than a
      # violation, and that restraint is deliberate: this audit runs over
      # history that predates the archive-line rule, and promoting the old
      # shape to a violation would refuse pushes on every instance's existing
      # trunk. A backstop that cries wolf about the past gets switched off, and
      # then it guards nothing. Going forward the hooks refuse this shape at
      # merge time, which is where it can still be fixed.
      # THE ARITY ARM IS GONE (B2 restatement, 2026-08-13). This branch used to
      # carry a special case ahead of the ancestry question: `NPAR > 2` was a
      # VIOLATION outright, justified as "an octopus merge is not pre-rule
      # history: nothing shipped before the rule merged three branches at once".
      # That sentence infers AGE from SHAPE, which is the exact proxy the
      # RULE_BASELINE comment above exists to refuse: a merge's parent count is
      # a spelling, and this cycle measured six ways a spelling-keyed check
      # decays. The question that actually decides the exemption is WHEN: did
      # this commit happen after the instance adopted the rules? Ancestry
      # answers that for every arity at once, `post_baseline` already asks it,
      # and it needs no enumeration because there is no list of shapes to keep
      # current, only one merge-base query.
      #
      # What the arm used to catch is still caught, one line below: a
      # post-adoption octopus with an unjustified role-carrying parent descends
      # from the baseline, so the ancestry question condemns it (asserted as
      # "audit age c"). What changes is genuinely PRE-adoption history, where an
      # octopus now keeps the same exemption every other pre-rule merge keeps
      # ("audit age d"): the restraint doctrine is that an audit cannot condemn
      # history made before the rules it is auditing against, and that doctrine
      # does not have an arity clause.
      if post_baseline "$C"; then
        printf 'VIOLATION %s  chore-shaped merge with no recorded completion, made after this instance adopted the rules; it reached the trunk without firing pre-merge-commit\n' "$SHORT"
        printf '          %s\n' "$SUBJ"
        VIOLATIONS=$((VIOLATIONS + 1))
        SEEN_BAD=1
        continue
      fi
      printf 'unverifiable %s  chore-shaped merge with no recorded completion; predates this instance adopting the archive-line rule\n' "$SHORT"
      CHORES=$((CHORES + 1))
      SEEN_CHORE=1
      continue
    fi

    CLOSED_SOMETHING=0
    while IFS= read -r SPEC_FILE; do
      [[ -n "$SPEC_FILE" ]] || continue
      SPEC_NUM="$(printf '%s' "$SPEC_FILE" | sed -e 's#^specs/##' -e 's#-.*##')"
      # fail-open-ok: an unreadable spec yields empty text, and every check
      # below is a grep that FAILS on empty, so the merge is reported as a
      # violation. Unreadable evidence counts against the merge, never for it.
      SPEC_TEXT="$(git -C "$INSTANCE" show "$P2:$SPEC_FILE" 2>/dev/null || true)"

      # A FENCED EXAMPLE IS NOT A CLOSING REPORT, in the backstop too. The close
      # gate has stripped fenced spans since leg 5's F7; this script never did,
      # so a spec quoting the shipped template satisfied every check below and
      # the audit reported it clean (v1.7 gate, hostile leg F9). Stripped once,
      # before all of them, exactly as close-gate.sh and setlist-hook-lib.sh do.
      #
      # NARROWED for the 1.1.0 hostile leg's F6, and this copy is the one that
      # made the defect RETROACTIVE. The stripper is new here in 1.1.0, so an
      # instance upgrading from 1.0.9 found the audit condemning trunk history
      # that had merged legitimately, at which point pre-push refused the push
      # and the only documented escape switched off every other check too. A
      # block is a TEMPLATE QUOTE exactly when its own body carries a
      # Closing-report heading; a pasted verifier report never does.
      #
      # LOCKSTEP: byte-identical to close-gate.sh and setlist-hook-lib.sh, and
      # (2026-08 consolidation) hoisted to file scope with QA_PASS1_AWK above so
      # the linear close check can share the one definition instead of drifting
      # a second copy of it.
      SPEC_TEXT="$(printf '%s\n' "$SPEC_TEXT" | awk "$TEMPLATE_FENCE_AWK")"

      MISSING=""
      printf '%s\n' "$SPEC_TEXT" | grep -qE $'^ {0,3}#{1,6}[ \t]+Closing report' || MISSING="$MISSING no-closing-report"

      # THE VERDICT IS A PASTED BLOCK, NOT A WORD IN PROSE (B6, leg 5 F15).
      # This was `grep PASS|PARTIAL|FAIL` over the WHOLE spec, so "the browser
      # tests PASS on my machine but mobile was never run" satisfied it. The
      # close gate rejects exactly that text and has since 1.0.2; its backstop
      # accepted it, so the audit reported clean on input the gate refuses,
      # which is the worst possible disagreement between two layers that are
      # supposed to cover each other. Both halves of the close gate's rule are
      # mirrored here rather than reinvented: extract the QA Pass 1 block
      # DISPLACED, NOT LEFT BESIDE. The field-marker extraction that used to
      # live here fed a regex over the prose between the "QA Pass 1 report" and
      # "QA Pass 2" markers. The verdict is a structure now, read straight out
      # of the spec text, so that extraction has no reader and is deleted rather
      # than kept warm. shellcheck is what noticed it was dead, which is the
      # argument for the lint gate being a gate.
      # LOCKSTEP WITH templates/hooks/close-gate.sh (backlog item 35). That file
      # carries this same assignment, byte for byte, and the suite asserts the
      # two are identical, so a widening applied to one and not the other goes
      # red here rather than in the field.
      #
      # B6 made this backstop agree with the gate. What they agreed ON was still
      # wrong: both required a verdict to END its line, justified by a claim
      # about Appendix C that Appendix C does not make, and measured against
      # real history it rejected 15 of terminal-setup's 18 specs. The rule now
      # asks whether the verdict is a FIELD (a table cell, a bracketed verdict,
      # a labelled value, a verdict-as-label, or the first or last thing on its
      # line) rather than where on the line it happens to sit. Prose is still
      # refused, which is the half B6 exists for; see close-gate.sh for the full
      # reasoning and for the tally boundary this deliberately does not cross.
      [[ "$(printf '%s\n' "$SPEC_TEXT" | awk "$QA_PASS1_AWK")" == "ok" ]] \
        || MISSING="$MISSING no-qa-verdict"

      row_is_closed "$STATUS_TEXT" "$SPEC_NUM" || MISSING="$MISSING no-CLOSED-row"

      # THE DIAGRAM FIELD, WHICH THIS AUDIT DID NOT READ (v1.7 claims round 6).
      #
      # The audit's close-condition set was a strict SUBSET of the merge hook's:
      # closing report, QA verdict, CLOSED row. The diagram field lived only in
      # pre-merge-commit, which a fast-forward skips entirely. So a merge built
      # off-trunk and fast-forwarded on, which is byte-for-byte what a forge
      # merge button produces, carried an unanswered diagram field to the remote
      # while this audit reported it clean. That is the ordinary pull-request
      # flow rather than a crafted evasion, so it is fixed here rather than
      # documented.
      #
      # LOCKSTEP with setlist-hook-lib.sh's reader: field-shaped, anchored past a
      # list bullet, last match wins, and the template placeholder does not count
      # as an answer.
      DIAG_LINE="$(printf '%s\n' "$SPEC_TEXT" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | tail -n1)" # fail-open-ok: no line yields empty, which the test below reads as the missing field it is
      # LOCKSTEP MEANS THE SAME TEST, NOT THE SAME LINE (v1.7 final claims pass).
      #
      # The first cut of this check found the same line as the hook and then
      # applied a WEAKER test: it refused an empty field and a `<` placeholder
      # and passed everything else. So `TBD`, `n/a` and `see structure.md` were
      # refused SLH-DIAGRAM-UNANSWERED at merge time and reported clean by the
      # audit, which is the one thing the field exists to establish. The comment
      # above claimed lockstep with setlist-hook-lib.sh while the code did not
      # have it. The hook's test is a POSITIVE match on the two answers Appendix
      # C offers, and it is reproduced here rather than approximated.
      DIAG_ANSWER="$(printf '%s' "$DIAG_LINE" | sed -e 's/^[-*+>[:space:]]*Architecture diagram:[[:space:]]*//')"
      if [ -z "$DIAG_LINE" ]; then
        MISSING="$MISSING no-diagram-field"
      # PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11). This blanked the answer
      # on any '<', which was written for the template's own
      # `<updated in this commit | no impact>` and fired on ordinary prose: a
      # comparison, a generic, an HTML comment. Measured:
      # `updated in this commit (added <auth> box)` was refused.
      # Stripping <...> spans and THEN requiring the answer settles both directions,
      # because the genuine unfilled template strips to nothing and stays refused.
      # Asserted across the value space rather than at a spelling: this field has
      # been corrected three times, twice by repairing only the case reported.
      elif ! printf '%s' "$DIAG_ANSWER" | sed 's/<[^>]*>//g' | grep -qE 'updated in this commit|no impact'; then
        MISSING="$MISSING diagram-unanswered"
      fi

      if [[ -n "$MISSING" ]]; then
        printf 'VIOLATION %s  spec %s reached %s without:%s\n' "$SHORT" "$SPEC_NUM" "$TRUNK" "$MISSING"
        printf '          %s\n' "$SUBJ"
        VIOLATIONS=$((VIOLATIONS + 1))
        SEEN_BAD=1
      elif ! row_is_closed "$PRIOR_STATUS" "$SPEC_NUM"; then
        # Compliant AND not already closed on the trunk: this merge is what
        # closed it, so it can authorise the code riding with it.
        CLOSED_SOMETHING=1
      fi
    done <<EOF
$SPECS_TOUCHED
EOF

    # A MERGE CARRYING CODE MUST CLOSE SOMETHING (B6, and section 11's second
    # half). Dispositioning every spec is not sufficient on its own: a branch
    # can touch exactly one spec, have that spec be entirely compliant, and
    # still be laundering, because the spec was closed by an EARLIER merge and
    # this one only amended a line of it. Every spec checked out fine and the
    # audit said clean while unspecified code reached the trunk.
    #
    # Scoped to parents that actually carry role-path changes, so a docs-only
    # parent of an octopus merge cannot raise this.
    # THE CHAINED-MERGE AND OCTOPUS-PARENT DEFENCES ARE REMOVED (2026-08-07).
    #
    # They were added in claims rounds 4 and 5 to refuse merge TOPOLOGY crafted
    # to evade this audit: unspecced code merged into a spec branch, then that
    # branch merged with a compliant close, and the octopus spelling of the same
    # trick. Both worked against the attack. Both also refused ORDINARY WORK.
    #
    # Measured by the 2026-08-07 leg and reproduced here: two clones of one
    # instance, the second doing a fully compliant close and pushing it, the
    # first making one docs commit and running the sync git itself instructs.
    # The resulting merge was refused with "a chained merge below main brought
    # role-path code that closed no spec", naming as the offender the very close
    # merge this audit had passed clean minutes earlier. That breaks every team
    # sharing a trunk, and a false denial on the commonest workflow there is
    # costs more than the bypass it prevents: this project's own doctrine says a
    # gate everybody routes around is not a guarantee.
    #
    # The route is not left silent. The edition and the public README name it,
    # under a heading that says the list of known evasion routes is maintained
    # rather than complete, and the release states plainly that the git hooks are
    # a discipline control for cooperating use rather than a boundary against a
    # committer crafting merges. Documenting a route this audit cannot decide
    # without refusing honest work is the honest position; defending it with a
    # check that cannot tell the two apart was not.
    if [[ "$SEEN_BAD" -eq 0 && "$CLOSED_SOMETHING" -eq 0 ]] && touches_role "$BASE" "$P2"; then
      printf 'VIOLATION %s  role-path code reached %s under specs that were already CLOSED before it: closes-no-spec\n' "$SHORT" "$TRUNK"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
      SEEN_BAD=1
    fi
  done
  # A commit is counted once, in exactly one bucket: a violation if any merged
  # parent failed, otherwise unverifiable if any parent was a chore, otherwise
  # clean. Counting it clean AND chore inflated the clean figure, which is the
  # kind of reporting error that makes a report reassuring rather than true.
  # CONTENT NO PARENT SUPPLIED, which is derived from git rather than enumerated
  # (1.1.0 final leg, F9). `git commit --amend` on a completed merge adds files
  # to the trunk that came from nowhere: pre-commit skips its close verification
  # because MERGE_HEAD is already gone, and this audit found the merge justified
  # by its parents and never asked what the commit's own tree contained. The
  # same hole is an "evil merge" under another name.
  #
  # Asking git which role-path files exist in the commit and in NONE of its
  # parents needs no list of shapes: amend, evil merge, and any future spelling
  # that injects a file into a merge all answer the same question.
  #
  # LIMIT, stated rather than papered over: this catches an ADDED file, not an
  # edit to a file a parent already had. A merge that edits an existing file is
  # indistinguishable by content from an ordinary conflict resolution, and
  # flagging those would refuse every real merge, which is the false-denial
  # direction this repository treats as the more dangerous one. That residue is
  # named in Known limitations.
  if [[ "$NPAR" -ge 2 ]]; then
    INJECTED=""
    while IFS= read -r nf; do
      [[ -n "$nf" ]] || continue
      touches_role_file "$nf" || continue
      IN_A_PARENT=0
      for PP in $PARENTS; do
        git -C "$INSTANCE" cat-file -e "$PP:$nf" 2>/dev/null && { IN_A_PARENT=1; break; }
      done
      [[ "$IN_A_PARENT" -eq 0 ]] && INJECTED="$INJECTED $nf"
    done < <(git -C "$INSTANCE" diff --name-only --diff-filter=A "$P1" "$C" 2>/dev/null)
    if [[ -n "$INJECTED" ]]; then
      printf 'VIOLATION %s  the merge commit itself introduced role-path files that no parent carries:%s\n' "$SHORT" "$INJECTED"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
      SEEN_BAD=1
    fi
  fi

  if [[ "$SEEN_BAD" -eq 0 && "$SEEN_CHORE" -eq 0 ]]; then
    CLEAN=$((CLEAN + 1))
  fi
done < <(git -C "$INSTANCE" rev-list --first-parent "$SINCE".."$AUDIT_TIP" 2>/dev/null)

printf '\n-----------------------------------------------\n'
printf 'audited %d commits on %s: %d clean, %d chore merges (unverifiable), %d violations\n' \
  "$AUDITED" "$TRUNK" "$CLEAN" "$CHORES" "$VIOLATIONS"
if [[ "$AUDITED" -eq 0 ]]; then
  # NOTHING TO AUDIT IS A CLEAN ANSWER, not an error (v1.7 gate session 4, leg F2).
  #
  # This exited 2, pre-push reported that as "the audit could not run", and a
  # freshly stamped instance was therefore configured to REFUSE EVERY PUSH before
  # its owner had written a line. An empty range here means the trunk carries no
  # commits after the baseline, which is exactly what a new project looks like.
  #
  # The misconfigurations this exit was guarding against are caught earlier and
  # explicitly now: a trunk that is not a local branch dies above, and an
  # unresolvable baseline dies at the --since check. Neither can reach this line,
  # so treating an empty range as clean cannot launder a typo into a pass.
  printf 'nothing to audit yet: %s carries no commits after the baseline.\n' "$TRUNK"
fi
[[ "$VIOLATIONS" -eq 0 ]] || exit 1
