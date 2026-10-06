#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Trunk audit: does the trunk's HISTORY show every piece of feature code
# arriving through a closed spec?
#
# Usage:
#   trunk-audit.sh [<instance-dir>] [--since <ref>] [--until <ref>] [--config-from <commit>]
#
# THIS FILE IS A GATE (SP2-F5, corrected 2026-08-27). For four editions this
# header called the script advisory, said nothing ran it automatically, and said
# a finding here blocked nothing. Every one of those claims was true when it was
# written for plugin 1.0.5, and none has been true since edition v1.7, when
# pre-push was stamped and made live: `templates/git-hooks/pre-push` RUNS this
# script on every push and REFUSES the push on its verdict. A shipped file
# describing itself as harmless while a caller uses it as a boundary is this
# repository's signature defect, filed against this very file by the scan-scope
# proving run.
#
# The retired sentences are PARAPHRASED above rather than quoted, deliberately.
# A verbatim stale claim sitting in a shipped file reads as a claim to anything
# that greps or skims, which is the same "a quotation is not the thing" class the
# live-text reader exists for, and this project's claims sweep deliberately holds
# zero pinned stale copies so that any new one fails outright. The exact former
# wording is in this file's git history, which is where a retired claim belongs.
#
# What is true now, stated at the strength the bytes support:
#   - Run from pre-push on every push, and its exit status decides the push.
#   - Also runnable by hand and from /setlist:validate, which is where it
#     started and still the best way to read a whole history at once.
#   - It reads real project HISTORY rather than parsing commands, which is why
#     it catches what the session gates miss by construction.
# The escape is named where it is honoured: SETLIST_SKIP_TRUNK_AUDIT=1 skips
# this audit at push time and leaves the content scan running.
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

# EVERY READER IN THIS PROCESS READS BYTES (spec 0169; L2 F2 and F11). This
# file ships alone and is run by hand as well as from pre-push, so it sets its
# own rather than trusting a caller: under a UTF-8 locale one byte that is not
# valid UTF-8 in specs/STATUS.md or a spec aborted macOS awk and sed mid-read,
# and the partial read reported a compliant trunk as a violation. The library
# carries the same line and the same reasoning.
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
# BYTE-IDENTICAL to the copy in templates/git-hooks/setlist-hook-lib.sh; this
# file ships alone, and the suite asserts the two match.
# The CODEOWNERS reader's own description of a line it does not evaluate is
# fixed text, except the one that quotes the offending owner token: only that
# token is the repository's, so only it is bounded (spec 0169, sweep A.3.4).
# BYTE-IDENTICAL to the copy in templates/git-hooks/setlist-hook-lib.sh.
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

INSTANCE="."
SINCE=""
# WHERE THE WALK START CAME FROM, not merely what it is (spec 0157). The
# instance may DECLARE its baseline in .claude/sdd.json, and a declared value is
# read only when the command line named none: scripts/forge-check.sh passes the
# pull request's own base with --since, and a key read there would let a pull
# request move the forge's pre-rule exemption by editing a file in its own
# checkout. So this flag, and not the emptiness of SINCE, decides.
SINCE_GIVEN=0
# --until <ref>: audit the history ending at THIS commit rather than at the
# trunk's current tip. Added 2026-08-04 for pre-push, which receives the OID
# actually being pushed and must audit that rather than whatever the local trunk
# happens to point at (1.1.0 leg, F17). Defaults to the trunk, which is every
# other caller and the behaviour this script has always had.
UNTIL=""
# --config-from <commit>: read .claude/sdd.json from THIS commit when the instance's
# working tree carries none (spec 0173, item 1). pre-push passes the tip it is
# pushing when the checked-out branch has no configuration and the pushed commit
# does, so a push of governed history is audited under the history's own
# configuration whatever is checked out. The working tree's file, when present, is
# still the one read: every other caller, and every existing verdict, unchanged.
CONFIG_FROM=""
# A VALUE-LESS --since OR --until IS REFUSED, NOT ABSORBED (F12).
#
# These read `SINCE="${2:-}"; shift 2`, and `shift 2` with only one argument
# left is an ERROR in bash that leaves $# UNCHANGED, so `trunk-audit.sh --since`
# looped forever on the same argument. Not reachable from pre-push, which always
# passes a value, but a human or a CI job running the CLI hangs.
#
# The `=` spelling is accepted here rather than left to fail as an instance path.
# `--since=HEAD~5` is the form every other git-adjacent tool takes, and the old
# loop silently treated it as the INSTANCE directory, which then failed with
# "not a directory: --since=HEAD~5": a confusing error for a correct command.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*) SINCE="${1#--since=}"; SINCE_GIVEN=1; shift ;;
    --until=*) UNTIL="${1#--until=}"; shift ;;
    --config-from=*) CONFIG_FROM="${1#--config-from=}"; shift ;;
    --since|--until|--config-from)
      if [[ $# -lt 2 ]]; then
        printf 'trunk-audit.sh: %s needs a <ref> value. A missing value used to loop forever rather than say so.\n' "$1" >&2
        exit 2
      fi
      case "$1" in --since) SINCE="$2"; SINCE_GIVEN=1 ;; --until) UNTIL="$2" ;; *) CONFIG_FROM="$2" ;; esac
      shift 2
      ;;
    *) INSTANCE="$1"; shift ;;
  esac
done

die() { printf 'trunk-audit.sh: %s\n' "$1" >&2; exit 2; }

[[ -d "$INSTANCE" ]] || die "not a directory: $INSTANCE"
# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
command -v jq >/dev/null 2>&1 || die "jq is required to read .claude/sdd.json"
# jq is RUN and its OUTPUT compared before it reads anything (spec 0130, the
# same probe the hook library runs in slh_require_toolchain): a jq that exits 0
# printing nothing made `jq -e .` below pass and the trunk read as empty, so
# the audit died with "no role paths recorded", a true refusal with a false
# reason pointing at a file that was fine.
if [[ "$(printf '{"probe":"x"}\n' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  printf 'trunk-audit.sh [SLH-JQ-BROKEN]: jq is installed but does not work here: run on a one-key document it did not print the value back (it exited nonzero, or exited 0 and printed nothing), so this audit cannot read .claude/sdd.json and would otherwise report a trunk it never read. Run '"'"'jq --version'"'"' to see the failure; a broken dynamic library, a wrong-architecture binary and an out-of-memory kill all look like this. Your .claude/sdd.json is not the problem.\n' >&2
  exit 2
fi

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
# Emptied first (spec 0180, F11): the exit traps remove CFG_TMPD, so it holds only what mktemp gave this process.
CFG_TMPD=""
if [[ ! -f "$SDD" && -n "$CONFIG_FROM" ]]; then
  # The configuration of the commit being pushed, materialised once; a copy that
  # cannot be made refuses (exit 2), never audits under no configuration.
  CFG_TMPD="$(mktemp -d 2>/dev/null)" || CFG_TMPD=""
  [[ -n "$CFG_TMPD" ]] || die "--config-from $(slh_bound name "$CONFIG_FROM"): no private workspace for the pushed commit's .claude/sdd.json; check TMPDIR"
  trap 'rm -rf "$CFG_TMPD"' EXIT
  git -C "$INSTANCE" show "$CONFIG_FROM:.claude/sdd.json" > "$CFG_TMPD/sdd.json" 2>/dev/null \
    || die "--config-from $(slh_bound name "$CONFIG_FROM"): that commit carries no readable .claude/sdd.json"
  SDD="$CFG_TMPD/sdd.json"
fi
# What a message calls the file: its path, or, when read from a pushed commit, that commit's copy.
CFG_SHOWN="$SDD"
[[ -z "${CFG_TMPD:-}" ]] || CFG_SHOWN=".claude/sdd.json at $(slh_bound name "$CONFIG_FROM")"
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
# A SHALLOW CLONE CANNOT BE AUDITED (spec 0164, fix round 2, F7 of the 2.10.0
# leg). `git clone --depth 1` keeps the tip and grafts away the history this
# walk reads, so the audit found no commits after the baseline and printed
# "nothing to audit yet" at exit 0 over a history it could not see: a violating
# trunk reported clean. scripts/forge-check.sh has refused this since 2.6.0
# ([FC-SHALLOW-CHECKOUT]); the layer that runs at every push had no such guard.
# Its own work is still refused in such a clone, so this is the retrospective
# sweep failing open, which is the half nobody notices.
if [[ "$(git -C "$INSTANCE" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  die "[SLH-SHALLOW-CLONE] $INSTANCE is a shallow clone, so the history this audit walks is not here and a clean report would say nothing about what the trunk actually carries. A check that could not read has not passed. Fetch the full history (git fetch --unshallow), or audit a clone that has it."
fi

ROLES="$(mapfile_roles)"
[[ -n "$ROLES" ]] || die "no role paths recorded in $SDD"

# A GLOB IN A ROLE VALUE IS REFUSED HERE TOO (spec 0164, fix round 2, F3 of the
# 2.10.0 leg), by the same question the hook library asks: this reader matched
# `packages/*` literally while the close verification expanded it against the
# working directory, so one declared spelling meant two different sets and a
# merge that the hooks refused audited clean at push. A9's rule, one question,
# one answer.
while IFS= read -r _role; do
  [[ -n "$_role" ]] || continue
  case "$_role" in
    *'*'*|*'?'*|*'['*)
      die "[SLH-ROLES-SHAPE] $CFG_SHOWN declares the role path $(slh_bound name "$_role"), which carries a glob character (* ? [). This audit matches role paths literally and the commit-time hooks would expand it against the working directory, so one spelling would mean two different sets and this report could not be trusted either way. Name the directory itself, one role per path." ;;
  esac
  # A `..` SEGMENT, refused by the same question the hook library asks (spec
  # 0169, L2 F10): such a role matched no path, so this audit reported a trunk
  # carrying direct feature code as clean at rc 0.
  case "/$_role/" in
    */../*)
      die "[SLH-ROLES-SHAPE] $CFG_SHOWN declares the role path $(slh_bound name "$_role"), which has a .. segment. Git records no path with one, so this audit would match nothing under it and report the trunk clean whatever it carries. Name the directory itself by its path from the repository root." ;;
  esac
  # And a `.` segment after any leading ./ (spec 0180, F8; the hook library says why).
  _rt="$_role"; while [[ "${_rt#./}" != "$_rt" ]]; do _rt="${_rt#./}"; done
  case "/$_rt/" in
    */./*)
      die "[SLH-ROLES-SHAPE] $CFG_SHOWN declares the role path $(slh_bound name "$_role"), which has a . segment after its start. Git records no path with one, so this audit would match nothing under it and report the trunk clean whatever it carries. Name the directory itself by its path from the repository root." ;;
  esac
done <<EOF
$ROLES
EOF

# A TRUNK THAT NAMES "WHEREVER HEAD IS" NAMES NO TRUNK (V19-F8).
#
# `HEAD`, `@` and `@{-1}` all RESOLVE, and the reducer below then turns them into
# whatever branch is checked out at audit time: the audited ref becomes a
# property of the working tree rather than of the recorded configuration, so the
# same repository audits a different branch depending on where somebody happened
# to leave HEAD, and a spec branch can be audited as though it were the trunk.
# `@{-1}` is worse still, naming the PREVIOUSLY checked-out branch.
#
# This EXTENDS a guard that already fires rather than teaching the audit to tell
# a crafted shape from an ordinary one, which is why it is a fix and not the
# coverage chase A3 warns against: the reducer below already refuses a spelling
# that names no local branch, and these three slip past only because they name a
# real one indirectly. Reaching this needs one of the three written into
# sdd.json's "trunk", which is not ordinary work; the refusal is cheap and the
# silent misdirection is not.
#
# The reflog forms are refused as a FAMILY (`@{...}` anywhere) rather than
# enumerated, because @{0}, @{1}, @{upstream} and @{-1} are one syntax and an
# enumeration is always one spelling short of the next one.
case "$TRUNK" in
  HEAD|@|*@\{*\}*)
    die "the recorded trunk $(slh_bound name "$TRUNK") names a POSITION rather than a branch, so which ref this audit reads would depend on where HEAD happens to point rather than on what this project protects. Record the plain branch NAME (for example \"main\") in .claude/sdd.json."
    ;;
esac

git -C "$INSTANCE" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 \
  || die "the recorded trunk $(slh_bound name "$TRUNK") does not resolve in this repository"

# THE TRUNK VALUE MUST NAME A LOCAL BRANCH, and "it resolves" is not that check.
# A remote-tracking spelling resolves perfectly well, which is why the rev-parse
# above passed it straight through: this script then audited refs/remotes/origin/
# main, the violating merge on LOCAL main was simply not in the range, and it
# reported "1 clean, 0 violations" at exit 0 while pre-push allowed the push
# (v1.7 dogfood gate, adversarial review F10). Same root cause as slh_trunk's, different
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
    || die "the recorded trunk $(slh_bound name "$TRUNK") is not a local branch in this repository, so this audit would read a ref that is not the trunk being pushed and could report it clean. Record the plain branch NAME (for example \"main\"), not a ref path such as refs/remotes/origin/main."
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

# THE DECLARED BASELINE (spec 0157, the 2.10.0 intake section 1).
#
# The default below is the commit that introduced .claude/sdd.json, and it is
# right for every instance whose stamp and hooks arrived together. For the
# instances where it is wrong it is wrong in the worst direction: an instance
# stamped before the git hooks existed has merges that no pre-merge-commit could
# have witnessed, and this audit refuses every push from then on while printing
# "made after this instance adopted the rules" about commits made before any
# rule existed. Measured on a real instance: 33 violations at the default
# baseline, 0 at the commit that delivered .githooks/.
#
# So the frame is DECLARABLE: one key, .audit.baseline, a full commit id in the
# file this audit already takes its trunk, its roles and its exclusions from.
# A commit id and never a ref, for the reason the trunk key refuses a POSITION
# a hundred lines above: this audit decides by identity and a ref moves.
#
# READ ONLY WHEN --since IS ABSENT, and then by BOTH baseline readers, the walk
# start here and the pre-rule exemption's RULE_BASELINE below. Under --since the
# command line wins outright and neither reader touches the key, which is what
# keeps scripts/forge-check.sh (whose only call passes --since) byte-for-byte
# unaffected and stops a pull request moving the forge's exemption by editing
# sdd.json in its own checkout.
#
# A key that cannot be USED is a refusal, never a fallback to the default: the
# instance declared a frame and an audit that quietly walked a different one
# would attest to something nobody asked for. Same reason the --until and
# --since resolutions refuse rather than default.
# --- THE BASELINE FRAME (spec 0167) -------------------------------------------
# LOCKSTEP: everything from this banner to the one that closes it is
# BYTE-IDENTICAL in scripts/trunk-audit.sh and scripts/refresh-instance.sh, and
# the suite asserts it (the audit ships alone into .claude/hooks/ and sources
# nothing from the plugin, so one text in two files is how it is shared).
#
# ONE READER FOR THREE CALLERS: the trunk audit, the refresh's usability probe,
# and /setlist:validate step 18, which reaches it through the refresh's report
# mode. The 2.10.0 second leg's F1, F3, F4, F5 and F9 were these callers asking
# three different questions of one key: the audit required the key on the
# trunk's first-parent line, the refresh wrote the commit that ADDED
# .githooks/pre-push, which sits on a side branch whenever the hooks arrived
# through a merge (the upgrade's chore branch under merge.ff=false makes that
# the ordinary shape), and the refresh's probe asked plain ancestry. Every push
# after such an upgrade was refused by name while the refresh called the key
# healthy. Measured on the owner's instance: refused at once.
#
# So the frame is COMPUTED, not required. Any ancestor of the tip is a valid
# declaration, and the walk starts at the OLDEST commit on the tip's
# first-parent line that contains it: the declared commit itself when it is on
# that line, otherwise the merge that brought it in. Containment is monotone
# along the line (a commit that contains it has descendants that do too), so
# walking from the tip and stopping at the first commit that does NOT contain
# it finds that frame. Never the tip for an older declaration: that would walk
# nothing and attest every trunk clean (spec 0167, ruling E-a).
#
# One line out, compared by bytes across the callers by the suite's key corpus:
#   absent                                  no key
#   frame <frame-id> <declared-id>          walk from <frame-id>
#   refuse SLH-BASELINE-<CODE> <reason>     the audit refuses it at exit 2
# A git failure while computing the frame refuses: a later frame walks less, so
# a guessed one is the fail-open direction. Every git call is tested with
# if/else rather than `$?` so the function behaves the same under `set -e`.
slh_baseline_frame() { # slh_baseline_frame <repo> <sdd.json> <tip>
  local repo="$1" sdd="$2" tip="$3" v c prev="" rc fp
  # The shape guard both scripts carried since 0157: a present "audit" that is
  # not an object, or a present baseline that is not a string (JSON false and
  # null included, spec 0164 F21), is MALFORMED, never read as "no key".
  if ! v="$(jq -r 'if has("audit") and ((.audit | type) != "object") then error("audit-not-object")
        elif ((.audit // {}) | has("baseline")) and ((.audit.baseline | type) != "string") then error("baseline-not-string")
        else (.audit.baseline // empty) end' "$sdd" 2>/dev/null)"; then
    printf 'refuse SLH-BASELINE-MALFORMED type\n'; return 0
  fi
  if [[ -z "$v" ]]; then printf 'absent\n'; return 0; fi
  # LC_ALL=C: a shell bracket range collates by the LOCALE, so under a UTF-8
  # locale `[!0-9a-f]` does not match `A` (spec 0157, the suite's case b3).
  if ! LC_ALL=C grep -qE '^[0-9a-f]{40}$' <<< "$v"; then
    printf 'refuse SLH-BASELINE-MALFORMED shape\n'; return 0
  fi
  if ! git -C "$repo" rev-parse --verify --quiet "${v}^{commit}" >/dev/null 2>&1; then
    printf 'refuse SLH-BASELINE-UNRESOLVED commit\n'; return 0
  fi
  if git -C "$repo" merge-base --is-ancestor "$v" "$tip" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  case "$rc" in
    0) ;;
    1) printf 'refuse SLH-BASELINE-NOT-ANCESTOR ancestry\n'; return 0 ;;
    *) printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0 ;;
  esac
  if ! fp="$(git -C "$repo" rev-list --first-parent "$tip" 2>/dev/null)"; then
    printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0
  fi
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    if git -C "$repo" merge-base --is-ancestor "$v" "$c" >/dev/null 2>&1; then rc=0; else rc=$?; fi
    case "$rc" in
      0) prev="$c" ;;
      1) break ;;
      *) printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0 ;;
    esac
  done <<SLH_FRAME_EOF
$fp
SLH_FRAME_EOF
  if [[ -z "$prev" ]]; then printf 'refuse SLH-BASELINE-UNRESOLVED git\n'; return 0; fi
  printf 'frame %s %s\n' "$prev" "$v"
}
# --- END THE BASELINE FRAME ---------------------------------------------------
DECLARED_BASELINE=""
BASELINE_FRAME=""
if [[ "$SINCE_GIVEN" -eq 0 ]]; then
  BL_VERDICT="$(slh_baseline_frame "$INSTANCE" "$SDD" "$AUDIT_TIP")"
  # DISPLAY ONLY: the value as written, quoted back in a refusal. It decides
  # nothing; the verdict above is the one reader's.
  BL_SHOWN="$(jq -r '(.audit.baseline? // empty) | tostring' "$SDD" 2>/dev/null || true)" # fail-open-ok: display only, the verdict above decides
  case "$BL_VERDICT" in
    absent) : ;;
    "frame "*)
      read -r _ BASELINE_FRAME DECLARED_BASELINE <<< "$BL_VERDICT"
      SINCE="$BASELINE_FRAME"
      ;;
    "refuse SLH-BASELINE-MALFORMED type")
      die "[SLH-BASELINE-MALFORMED] $CFG_SHOWN has an \"audit\" value that is not an object, or an \"audit.baseline\" that is present and is not a string (JSON false and null are values, not an absent key), so the declared baseline cannot be read and this audit would silently walk from the default instead of the frame this instance declares. Set \"audit\" to an object: {\"baseline\": \"<full 40-character commit id>\"}, or remove the key." ;;
    "refuse SLH-BASELINE-MALFORMED shape")
      die "[SLH-BASELINE-MALFORMED] $CFG_SHOWN records audit.baseline $(slh_bound name "$BL_SHOWN"), which is not a full 40-character commit id in lowercase hex: it names a ref, an abbreviation or a position rather than a commit, and this audit decides by identity because a ref moves and an abbreviation can stop being unique. Record the full id ('git rev-parse <ref>'), or remove the key to audit from the commit that introduced .claude/sdd.json." ;;
    "refuse SLH-BASELINE-UNRESOLVED commit")
      die "[SLH-BASELINE-UNRESOLVED] $CFG_SHOWN records audit.baseline $(slh_bound name "$BL_SHOWN"), which does not resolve to a commit in this repository, so the audit cannot establish what to walk and a clean report would be a false attestation. Record a commit this repository carries, or remove the key to audit from the commit that introduced .claude/sdd.json." ;;
    "refuse SLH-BASELINE-NOT-ANCESTOR "*)
      # ONE MEANING (spec 0167): not an ancestor of the tip at all. A commit a
      # merge brought in from a side branch IS an ancestor and is framed at
      # that merge; this refusal is only for a commit no part of the audited
      # history contains, where no frame exists to declare.
      die "[SLH-BASELINE-NOT-ANCESTOR] $CFG_SHOWN records audit.baseline $(slh_bound name "$BL_SHOWN"), which is not an ancestor of the history being audited ($AUDIT_TIP): no commit of that history contains it, so it declares no frame this audit could walk from, and a clean report would be a false attestation. Record a commit this trunk's history contains, or remove the key to audit from the commit that introduced .claude/sdd.json." ;;
    *)
      die "[SLH-BASELINE-UNRESOLVED] $CFG_SHOWN records audit.baseline $(slh_bound name "$BL_SHOWN"), and git could not answer which commit of the history being audited ($AUDIT_TIP) first contains it, so the frame cannot be computed; a guessed frame would walk less than the declaration says. Check the repository with 'git fsck', or remove the key to audit from the commit that introduced .claude/sdd.json." ;;
  esac
fi

# Baseline. Everything before the instance was stamped is pre-framework and
# not this audit's business; auditing it would produce noise that trains the
# reader to ignore the report.
if [[ -z "$SINCE" ]]; then
  # --root at every `log --diff-filter=A` here (RC2-2026, spec 0129): under
  # `log.showRoot=false` git renders a ROOT commit as adding nothing, so an
  # instance whose first commit adopted the rules had no findable baseline and
  # every push was refused by accident. Measured: 0 commits without it, 1 with.
  # Under --config-from the walk starts at the pushed commit rather than HEAD (spec 0173,
  # item 1): with no configuration checked out, HEAD is the branch that lacks it, and
  # its history has no adding commit to find. Without the flag, HEAD, as always.
  SINCE="$(git -C "$INSTANCE" log --root --format=%H --diff-filter=A ${CONFIG_FROM:+"$CONFIG_FROM"} -- .claude/sdd.json | tail -n1)"
  [[ -n "$SINCE" ]] || die "cannot find the commit that introduced .claude/sdd.json; pass --since <ref>"
fi

# The baseline must RESOLVE. Since an empty range now reports clean, a --since
# that names nothing would otherwise walk no commits and report a clean trunk,
# turning a typo into an attestation. Checked explicitly rather than inferred
# from the walk being empty, because those are different facts.
git -C "$INSTANCE" rev-parse --verify --quiet "${SINCE}^{commit}" >/dev/null 2>&1 \
  || die "the baseline '$SINCE' does not resolve to a commit in this repository, so the audit cannot establish what to walk. Pass a --since that names a commit on the trunk."

printf 'trunk audit: %s\n' "$(cd "$INSTANCE" && pwd)"
# THE ROLE LIST AS DECLARED, BOUNDED ONLY WHEN IT NEEDS TO BE (spec 0169, sweep
# A.3.4): a list whose every role is inside the set a path needs prints exactly
# as it always has, so the report of an ordinary instance stays byte-identical
# to earlier generations (the differentials in shards 14 and 17 compare it);
# a role outside that set switches the whole list to the bounded form, the
# edit said.
_roles_shown="$(printf '%s' "$ROLES" | tr '\n' ' ')"
case "$_roles_shown" in *[!A-Za-z0-9._/\ :+=@-]*) _roles_shown="$(slh_bound names "$ROLES")" ;; esac
printf '  trunk: %s   roles: %s\n' "$TRUNK" "$_roles_shown"
# WHICH FRAME PRODUCED THIS REPORT, said in the report (spec 0157). Under
# --since the line keeps today's bytes exactly: the caller named the range, the
# word would describe nothing the caller does not already know, and the forge
# check's stderr stays byte-identical (0157 ruling E-b).
BASELINE_NOTE=""
if [[ "$SINCE_GIVEN" -eq 0 ]]; then
  # When the frame is not the declared commit itself (it came in on a merged
  # branch), both are named, so the report says what was declared and where
  # the walk actually starts (spec 0167). When they are the same commit the
  # line keeps its 2.10.0 bytes.
  if [[ -z "$DECLARED_BASELINE" ]]; then BASELINE_NOTE=" (default)"
  elif [[ "$BASELINE_FRAME" == "$DECLARED_BASELINE" ]]; then BASELINE_NOTE=" (declared)"
  else BASELINE_NOTE=" (declared $(git -C "$INSTANCE" rev-parse --short "$DECLARED_BASELINE"), framed at the first trunk commit that contains it)"; fi
fi
printf '  since: %s (%s)%s\n\n' "$(git -C "$INSTANCE" rev-parse --short "$SINCE")" \
  "$(slh_bound text "$(git -C "$INSTANCE" log -1 --format=%s "$SINCE" | cut -c1-60)")" "$BASELINE_NOTE"

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
#
# IT PROBES THE REPOSITORY, NOT THE TEMPORARY DIRECTORY (spec 0164, fix round 2,
# F1 and F4 of the 2.10.0 leg). It used to probe under TMPDIR, which answers a
# question about a DIFFERENT filesystem: measured on this project, one
# repository on a case-insensitive disk read 1 violation with the ordinary
# TMPDIR and 0 with TMPDIR on a case-sensitive volume, and the reverse arm
# refused legitimate work on a case-sensitive repository whose TMPDIR folds
# case. The scope hook asks the same question under the project root
# (templates/hooks/scope-hook.sh, sh_folds_case); this asks it under the
# instance, so the two layers answer about one filesystem.
#
# AND A PROBE THAT CANNOT RUN REFUSES, rather than leaving ROLE_FOLD at its
# unset default: with an unwritable or absent TMPDIR the old line printed
# mktemp's error, read no status, and reported a violating trunk clean at exit
# 0. A check that could not run has not passed.
# AND SINCE 0169 IT PROBES BESIDE EACH ROLE DIRECTORY (L2 F16): a repository
# can span volumes, and a role directory mounted from a volume whose case
# behaviour differs from the instance root's was judged by the root's, a false
# VIOLATION one way and a silent pass the other. Each role is probed in the
# deepest directory of its path that exists, inside the instance, once per
# directory, and it folds only where its own probe folded. The scope hook asks
# the same question the same way (templates/hooks/scope-hook.sh, sh_folds_case).
ROLE_FOLDS=""   # one line per role: "<0|1><TAB><role as declared>"
_rf_seen=""
while IFS= read -r _rrole; do
  [[ -n "$_rrole" ]] || continue
  _rfdir="$INSTANCE/$_rrole"
  while [[ ! -d "$_rfdir" && "$_rfdir" == "$INSTANCE"/* ]]; do _rfdir="$(dirname "$_rfdir")"; done
  [[ -d "$_rfdir" ]] || _rfdir="$INSTANCE"
  case "$_rf_seen" in
    *"|$_rfdir=1|"*) _rf=1 ;;
    *"|$_rfdir=0|"*) _rf=0 ;;
    *)
      _rf=0
      _rfname=".setlist-case-probe.$$.${RANDOM:-0}"
      _rfupper="$(printf '%s' "$_rfname" | tr '[:lower:]' '[:upper:]')"
      if ( : > "$_rfdir/$_rfname" ) 2>/dev/null; then
        [[ -e "$_rfdir/$_rfupper" ]] && _rf=1
        rm -f "$_rfdir/$_rfname" 2>/dev/null
      else
        die "[SLH-CASE-PROBE-FAILED]: the case-folding probe could not write under $_rfdir, so whether the filesystem a role directory lives on folds case is unknown and role paths cannot be matched either way. A check that could not run has not passed. Make the instance writable, or run the audit where it is."
      fi
      _rf_seen="$_rf_seen|$_rfdir=$_rf|" ;;
  esac
  ROLE_FOLDS="$ROLE_FOLDS$_rf	$_rrole
"
done <<ROLESEOF
$ROLES
ROLESEOF

touches_role_file() { # touches_role_file <path> -> 0 if the path is under a role
  local f="$1" fl="" r rf
  while IFS='	' read -r rf r; do
    [[ -n "$r" && "$r" != "." ]] || continue
    while [[ "$r" == ./* ]]; do r="${r#./}"; done
    r="$(printf '%s' "$r" | tr -s '/')"
    r="${r#/}"; r="${r%/}"
    [[ -n "$r" && "$r" != "." ]] || continue
    if [[ "$rf" == "1" ]]; then
      [[ -n "$fl" ]] || fl="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')"
      r="$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')"
      case "$fl" in "$r"/*|"$r") return 0 ;; esac
    else
      case "$f" in "$r"/*|"$r") return 0 ;; esac
    fi
  done <<FOLDSEOF
$ROLE_FOLDS
FOLDSEOF
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
  # NUL-DELIMITED, BECAUSE git QUOTES PATHS (F1 of the 2.2.0 leg, a BLOCKER).
  # Without -z, `--name-only` emits a path carrying a non-ASCII byte, a double
  # quote, a backslash or a control character as a QUOTED C string, escapes and
  # surrounding quotes included, and touches_role_file's prefix match cannot see
  # `src/` through them. A role-path file was then invisible to the role test and
  # unreviewed feature code reached the trunk at exit 0.
  #
  # -z RATHER THAN core.quotePath=false, and this was measured before it was
  # written: the config flag rescues the NON-ASCII case ONLY. A quote, a
  # backslash and a control character are quoted unconditionally at every
  # setting. -z emits the raw bytes with a NUL terminator and no quoting at all,
  # which is the only spelling that covers all four classes. The suite runs each
  # class with the flag BOTH ways for exactly this reason.
  local f
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    touches_role_file "$f" && return 0
  done < <(git -C "$INSTANCE" diff -z --name-only "$1" "$2" 2>/dev/null)
  return 1
}

touches_role_tree() { # touches_role_tree <commit>
  # The same question as touches_role, asked of a commit that has NO parent to
  # diff against: does its own tree carry role-path code? Routed through
  # touches_role_file for the reason the comment above gives, so the normalise
  # and match rule still exists in exactly one place.
  # NUL-delimited for the reason touches_role gives one screen up: ls-tree quotes
  # the same four path classes that diff does, and the root-commit arm must not
  # be the one place the role test stays blind.
  local f
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    touches_role_file "$f" && return 0
  done < <(git -C "$INSTANCE" ls-tree -r -z --name-only "$1" 2>/dev/null)
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
# ONE VALUE FOR BOTH READERS (spec 0157). When the instance declares its
# baseline the walk start above and this exemption come from the SAME commit, so
# a merge the walk reaches never gets the pre-rule excuse and a merge older than
# the declaration is not walked at all. Under --since neither reads the key and
# this is computed exactly as it always was.
# The COMPUTED frame (spec 0167), not the declared commit: for every commit the
# walk reaches, post_baseline answers the same for either, and one value keeps
# the walk start and the exemption on the same commit by construction.
RULE_BASELINE="$BASELINE_FRAME"
[[ -n "$RULE_BASELINE" ]] \
  || RULE_BASELINE="$(git -C "$INSTANCE" log --root --diff-filter=A --format=%H ${CONFIG_FROM:+"$CONFIG_FROM"} -- .claude/sdd.json 2>/dev/null | tail -n1)" # fail-open-ok: an empty baseline is handled explicitly below and refuses the exemption rather than granting it
if [[ -z "$RULE_BASELINE" ]]; then
  RULE_BASELINE="$(git -C "$INSTANCE" log --root --diff-filter=A --format=%H ${CONFIG_FROM:+"$CONFIG_FROM"} -- .githooks/setlist-hook-lib.sh 2>/dev/null | tail -n1)" # fail-open-ok: as above; both absent means no exemption is available at all
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
# LOCKSTEP: setlist-hook-lib.sh carries this same program byte for byte and
# the suite asserts the two are identical (close-gate.sh, the third copy, left
# in 2.8.0, spec 0144), and since the 2.0.0
# leg (F8) also that they AGREE BY OUTCOME over a corpus, because this audit
# was blind in lockstep with the hooks it backstops. The reader is scoped: the
# deciding block is the FIRST qa-pass-1 fence at fence depth zero inside a
# Closing report section (F7-2026, ruled 2026-08-29; it was the LAST until
# then, which let a later illustrative block replace a real verdict);
# setlist-hook-lib.sh carries the full reasoning.
QA_PASS1_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; qa_seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } } else { if (__r == "qa-pass-1" && inclose && !qa_seen) { inb = 1; qch = __c; qlen = __m; n = 0; bad = 0; next } fence = 1; fch = __c; flen = __m; next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "") next; if (l ~ /^[A-Za-z0-9._-]+[[:space:]]*:[[:space:]]*(PASS|PARTIAL|FAIL)$/) n++; else bad = 1; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) inclose = 0 } } END { if (incmt) print "unclosed-comment"; else if (inb) print "unclosed"; else if (!qa_seen) print "none"; else if (bad) print "malformed"; else if (n == 0) print "empty"; else print "ok" }'

# THE CLOSE REVIEW BLOCK and THE VERSION COMPARISON (spec 0175). LOCKSTEP: byte-identical to
# setlist-hook-lib.sh, asserted; the library carries the full reasoning. The first reads a
# close-review block's last round (one line out, its first word the token); the second is the
# comparison rule_in_force below made first, shared so the gate dates a rule as this audit does.
SLH_CLOSE_REVIEW_AWK='{ __l = $0; sub(/\r$/, "", __l); sub(/^[[:space:]]*/, "", __l); if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (!fence && !inb && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; next } __c = substr(__l, 1, 1); if ((__c == "`" || __c == "~") && $0 ~ /^ ? ? ?[`~]/) { __m = 0; while (substr(__l, __m + 1, 1) == __c) __m++; __raw = substr(__l, __m + 1); __r = __raw; gsub(/[[:space:]]/, "", __r); __ti = __raw; sub(/^[ \t]+/, "", __ti); sub(/[ \t]+$/, "", __ti); if (__m >= 3 && !(__c == "`" && index(__raw, "`"))) { if (inb) { if (__c == qch && __m >= qlen && __r == "") { inb = 0; seen = 1; next } } else if (fence) { if (__c == fch && __m >= flen && __r == "") { fence = 0; next } if (__ti == "close-review" && inclose && !seen && !nin) { nin = NR; ninl = fline; nint = ftext } } else { if (__ti == "close-review" && inclose && !seen) { inb = 1; qch = __c; qlen = __m; next } if (__ti == "close-review" && !inclose && endl && !seen && !late) late = NR; fence = 1; fch = __c; flen = __m; fline = NR; ftext = substr(__l, 1, 40); next } } } if (fence) next; if (inb) { l = $0; sub(/^[[:space:]]+/, "", l); sub(/[[:space:]]+$/, "", l); if (l == "" || bad != "") next; if (acc) { bad = "a line after the ACCEPTED-BY-HUMAN verdict"; next } if (l ~ /^round[ \t]+[0-9]+[ \t]*:[ \t]*(PASS|FAIL|SKIP-DOCS-ONLY)$/) { __n = l; sub(/^round[ \t]+/, "", __n); sub(/[ \t]*:.*$/, "", __n); __n = __n + 0; __t = l; sub(/^[^:]*:[ \t]*/, "", __t); if (__n > 2) bad = "a third round"; else if (__n != nr + 1) bad = "round " __n " out of order"; else if (nr >= 1 && (tok[1] == "SKIP-DOCS-ONLY" || __t == "SKIP-DOCS-ONLY")) bad = "SKIP-DOCS-ONLY beside another round"; else { nr = __n; tok[nr] = __t } next } if (l ~ /^verdict[ \t]*:/) { if (l !~ /^verdict[ \t]*:[ \t]*ACCEPTED-BY-HUMAN([ \t]|$)/) { bad = "a verdict line other than ACCEPTED-BY-HUMAN"; next } if (nr != 2) { bad = "ACCEPTED-BY-HUMAN outside round 2"; next } if (tok[2] != "FAIL") { bad = "ACCEPTED-BY-HUMAN beside round 2 reading " tok[2]; next } __ids = l; sub(/^verdict[ \t]*:[ \t]*ACCEPTED-BY-HUMAN[ \t]*/, "", __ids); __k = split(__ids, __a, /[ \t]+/); if (__k == 0) { bad = "ACCEPTED-BY-HUMAN names no finding"; next } for (__i = 1; __i <= __k; __i++) { if (__a[__i] !~ /^[A-Za-z0-9._-]+$/) { bad = "ACCEPTED-BY-HUMAN names something that is not a finding id"; next } acc_id[__a[__i]] = 1; acc_list = acc_list " " __a[__i] } acc = 1; next } if (nr == 0) { bad = "a line before the first round header"; next } if (tok[nr] == "SKIP-DOCS-ONLY") { bad = "a SKIP-DOCS-ONLY round that carries lines"; next } if (l ~ /^[A-Za-z0-9._-]+[ \t]*:[ \t]*(PASS|PARTIAL|FAIL)$/) { cn[nr]++; if (l ~ /FAIL$/ && cf[nr] == "") { __cn = l; sub(/[ \t]*:.*$/, "", __cn); cf[nr] = __cn } next } if (index(l, "|")) { __k = split(l, __f, "|"); if (__k < 6) { bad = "a finding line with fewer than six fields"; next } for (__i = 1; __i <= 5; __i++) { sub(/^[ \t]+/, "", __f[__i]); sub(/[ \t]+$/, "", __f[__i]) } __fx = __f[6]; for (__i = 7; __i <= __k; __i++) __fx = __fx "|" __f[__i]; sub(/^[ \t]+/, "", __fx); sub(/[ \t]+$/, "", __fx); if (__f[1] !~ /^[A-Za-z0-9._-]+$/) { bad = "a finding whose id is not a bare identifier"; next } if (__f[2] !~ /^([A-Za-z0-9._-]+|-)$/) { bad = "finding " __f[1] " names no criterion"; next } if (__f[3] !~ /^(BLOCKER|MAJOR|MINOR)$/) { bad = "finding " __f[1] " has no severity"; next } if (__f[4] !~ /^[^ \t|]+:[0-9]+$/) { bad = "finding " __f[1] " has no file and line"; next } if (__f[5] == "" || __fx == "") { bad = "finding " __f[1] " says no what or no fix"; next } __key = nr SUBSEP __f[1]; if (__key in fid) { bad = "finding " __f[1] " appears twice in round " nr; next } fid[__key] = __f[3]; if (__f[3] != "MINOR") { if (mj[nr] == "") mj[nr] = __f[1] " " __f[3]; if (nr == 2) mj2[__f[1]] = __f[3] } next } bad = "a line that is not a round header, a criterion verdict, a finding or the human verdict"; next } if (__c == "#" && $0 ~ /^ ? ? ?#/) { __lev = 0; while (substr(__l, __lev + 1, 1) == "#") __lev++; __hn = substr(__l, __lev + 1, 1); if (__lev <= 6 && (__hn == " " || __hn == "\t") && __l ~ /^#+[ \t]+Closing report([ \t]+\(.*\))?[ \t]*(#+[ \t]*)?$/) { inclose = 1; clevel = __lev } else if (__lev <= 6 && (__hn == "" || __hn == " " || __hn == "\t") && inclose && __lev <= clevel) { inclose = 0; endl = NR; endh = substr(__l, 1, 60) } } } END { if (incmt) { print "unclosed-comment"; exit } if (inb) { print "unclosed"; exit } if (!seen && nin) { print "malformed the close-review fence at line " nin " opens inside a fence opened at line " ninl " (" nint ") that is not closed before it, so it is read as content of that fence"; exit } if (!seen && late) { print "malformed the close-review fence at line " late " sits after the heading \"" endh "\" at line " endl ", which ends the Closing report section; a report pasted into the Closing report goes inside a fence, where its headings are content"; exit } if (fence && !seen) { print "malformed an unclosed fence opened at line " fline " (" ftext ") runs to the end of the spec, so no block after it is read"; exit } if (!seen) { print "none"; exit } if (bad != "") { print "malformed " bad; exit } if (nr == 0) { print "empty"; exit } for (__i = 1; __i <= nr; __i++) { if (tok[__i] == "SKIP-DOCS-ONLY") continue; if (cn[__i] == 0) { print "malformed round " __i " carries no criterion verdict"; exit } if (tok[__i] == "PASS" && mj[__i] != "") { print "malformed round " __i " reads PASS beside " mj[__i]; exit } if (tok[__i] == "PASS" && cf[__i] != "") { print "malformed round " __i " reads PASS beside criterion " cf[__i] " FAIL"; exit } } if (acc) { __k = split(acc_list, __a, " "); for (__i = 1; __i <= __k; __i++) { __key = 2 SUBSEP __a[__i]; if (!(__key in fid)) { print "malformed ACCEPTED-BY-HUMAN names " __a[__i] ", which round 2 does not carry"; exit } } for (__x in mj2) if (!(__x in acc_id)) { print "malformed ACCEPTED-BY-HUMAN leaves round 2 finding " __x " " mj2[__x] " unaccepted"; exit } print "accepted"; exit } if (tok[nr] == "PASS") print "pass"; else if (tok[nr] == "FAIL") print "fail"; else print "skip" }'
SLH_VERSION_AT_LEAST_AWK='BEGIN { if (v !~ /^[0-9]+\.[0-9]+(\.|$)/) exit 1; split(v, a, /[.]/); split(want, w, /[.]/); if (a[1] + 0 > w[1] + 0) exit 0; if (a[1] + 0 == w[1] + 0 && a[2] + 0 >= w[2] + 0) exit 0; exit 1 }'

# HOISTED, same reason as QA_PASS1_AWK above: the linear close check needs it
# too. LOCKSTEP: byte-identical to setlist-hook-lib.sh. Strips
# a fenced block that itself carries a "Closing report" heading (a quoted
# template example) and deletes HTML comment spans; kept narrow on purpose so a
# real pasted qa-pass-1 fence survives for QA_PASS1_AWK to find.
TEMPLATE_FENCE_AWK='function __f(k,  i){ if(k) for(i=1;i<=n;i++) print b[i]; n=0 } { __l=$0; sub(/\r$/,"",__l); sub(/^[[:space:]]*/,"",__l); if (incmt) { __cb[++__cn]=$0; if (index(__l, "-->")) { incmt = 0; __cn=0 } next } if (!fence && $0 ~ /^ ? ? ?<!--/ && !index(__l, "-->")) { incmt = 1; __cn=0; __cb[++__cn]=$0; next } __c=substr(__l,1,1); if ((__c=="`" || __c=="~") && $0 ~ /^ ? ? ?[`~]/) { __m=0; while(substr(__l,__m+1,1)==__c) __m++; __raw=substr(__l,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { if (!fence) { fence=1; fch=__c; flen=__m; n=0; t=0; b[++n]=$0; next } else if (__c==fch && __m>=flen && __r=="") { fence=0; b[++n]=$0; __f(!t); next } } } if (fence) { b[++n]=$0; if($0 ~ /^ ? ? ?#+[ \t]+Closing report/) t=1; next } print } END { if(fence) __f(!t); if(incmt) for(__ci=1;__ci<=__cn;__ci++) print __cb[__ci] }'

# LIVE TEXT ONLY (2026-08 consolidation, blocker F2). LOCKSTEP: byte-identical to
# setlist-hook-lib.sh, which carries the full reasoning. Strips fenced blocks,
# HTML comment spans and indented-code lines before a plain grep looks for a
# chore archive line, so an illustration cannot be counted as a record.
SLH_LIVE_TEXT_AWK='{ __l=$0; sub(/\r$/,"",__l); __para=PARA; PARA=0; if (incmt) { if (index(__l, "-->")) incmt = 0; next } if (inhtml) { if (index(tolower(__l), htag)) inhtml = 0; next } if (!fence) { while ((__ci=index(__l, "<!--")) > 0) { __after=substr(__l, __ci+2); __cj=index(__after, "-->"); if (__cj > 0) { __l = substr(__l, 1, __ci-1) substr(__after, __cj+3) } else { __l = substr(__l, 1, __ci-1); incmt = 1; break } } } __t=__l; __d=0; while (1) { __save=__t; sub(/^ ? ? ?/,"",__t); if (__t ~ /^>/) { sub(/^> ?/,"",__t); __d++ } else { __t=__save; break } } if (fence) { if (__d==fbq && !(__t ~ /^(    |\t)/)) { __x=__t; sub(/^[[:space:]]*/,"",__x); __c=substr(__x,1,1); if (__c==fch) { __m=0; while(substr(__x,__m+1,1)==__c) __m++; __raw=substr(__x,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=flen && __r=="") fence=0 } } next } __hx=tolower(__t); sub(/^[[:space:]]*/,"",__hx); if (__hx ~ /^<(script|style|textarea|pre)([ \t>]|$)/) { if (__hx ~ /^<script/) htag="</script>"; else if (__hx ~ /^<style/) htag="</style>"; else if (__hx ~ /^<textarea/) htag="</textarea>"; else htag="</pre>"; if (index(__hx, htag)) { next } inhtml=1; next } __ic=__t; __peeled=0; while (1) { __s2=__ic; sub(/^ ? ? ?/,"",__ic); if (__ic ~ /^([-*+]|[0-9]+[.)])[ \t]/) { sub(/^([-*+]|[0-9]+[.)]) ?/,"",__ic); __peeled=1 } else if (__ic ~ /^>/) { sub(/^> ?/,"",__ic); __peeled=1 } else { __ic=__s2; break } } if (__peeled && __ic ~ /^(    |\t)/) { next } if (__d>0 && __t ~ /^(    |\t)/) { next } if (__d==0 && __t ~ /^(    |\t)/) { if (!__para) next } __o=__t; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/,"",__o); sub(/^[[:space:]]*/,"",__o); __c=substr(__o,1,1); if (__c=="`" || __c=="~") { __m=0; while(substr(__o,__m+1,1)==__c) __m++; __raw=substr(__o,__m+1); __r=__raw; gsub(/[[:space:]]/,"",__r); if (__m>=3 && !(__c=="`" && index(__raw,"`"))) { fence=1; fch=__c; flen=__m; fbq=__d; next } } if ((__d>0 || __peeled) && __ic ~ /^[[:space:]]*[|]/) next; print __l; if (__l ~ /^[[:space:]]*$/) { intable=0 } else if (__d==0) { __ps=__t; sub(/^[[:space:]]*/,"",__ps); if (__ps ~ /^\|?[ \t|:-]*-[ \t|:-]*$/ && index(__ps,"|")) { intable=1 } else if (index(__ps,"|") && intable) { } else { intable=0; if (!(__ps ~ /^#+([ \t]|$)/) && !(__ps ~ /^[-=]+[ \t]*$/) && !(__ps ~ /^[*_]+[ \t]*$/)) PARA=1 } } }'

# THE STRUCTURED STATUS RECORD (RP1, edition v1.12). Where a tree carries
# .claude/status.json, inventory, chore and close facts are read from the
# record and the three frozen readers above DO NOT RUN for it; where it is
# absent, the page path below is byte-identical to what shipped before the
# record existed (the pre-record differential in the suite proves that rather
# than asserting it). PRESENT AND MALFORMED IS A VIOLATION, never a pass and
# never a fallback to the page readers: a fallback would let one deliberate
# syntax error buy back the frozen readers' documented residual class. The
# audit refuses per COMMIT, so a range whose early commits predate the record
# is judged page-wise there and record-wise from the adoption commit on.
#
# LOCKSTEP: the seven SLH_RECORD_*_JQ assignments are byte-identical to
# templates/git-hooks/setlist-hook-lib.sh,
# asserted by the suite exactly as the three frozen awk readers are. The full
# grammar reasoning lives with the library's copy.
SLH_RECORD_CHECK_JQ='if (type != "object") or (.setlist_status != 1) or (((keys - ["setlist_status","specs","chores"]) | length) > 0) or (((.specs // {}) | type) != "object") or (((.chores // {}) | type) != "object") then "malformed" elif (((.specs // {}) | to_entries | all((.key | test("^[0-9]+[a-z]*$")) and (.value | if type != "object" then false else (((keys - ["status","qa_pass_1","diagram"]) | length) == 0) and (.status as $s | (["draft","queued","active","revised","built","parked","closed"] | index($s)) != null) and ((.qa_pass_1 == null) or (.qa_pass_1 == "ok")) and ((.diagram == null) or (.diagram == "updated") or (.diagram == "no-impact")) end))) | not) then "malformed" elif (((.chores // {}) | to_entries | all((.key | test("^CHORE-[0-9]+$")) and (.value | if type != "object" then false else (((keys - ["status","files"]) | length) == 0) and ((.status == "open") or (.status == "done")) and ((.files == null) or (((.files | type) == "array") and (.files | all(type == "string")))) end))) | not) then "malformed" else "ok" end'

# --- THE DIAGRAM HALF'S READERS (edition v1.15, spec 0136) --------------------
#
# LOCKSTEP: every definition between this banner and the one that closes it is
# BYTE-IDENTICAL to templates/git-hooks/setlist-hook-lib.sh, and the suite
# asserts it, exactly as it asserts the record readers and the three frozen awk
# readers above. The audit is the merge hook's backstop and a backstop that
# reads a field differently from the gate is the shape of leg 5's F8: two
# layers going blind the same way at the same time, which is what one shared
# text prevents.
#
# The ARMS that consume these readers are NOT shared: the hook refuses through
# slh_refuse, the audit accumulates a MISSING token and prints a VIOLATION line,
# and those are two different outputs of the same question by design.
#
# The library spells the fence reader SLH_TEMPLATE_FENCE_AWK and this file has
# always spelled it TEMPLATE_FENCE_AWK. One alias here lets the readers below be
# byte-identical rather than nearly so; the value is the same string, asserted.
SLH_TEMPLATE_FENCE_AWK="$TEMPLATE_FENCE_AWK"
# A READER THAT COULD NOT RUN HAS NOT READ, and an empty awk program reads every
# document as empty, which would make every diagram claim below pass in silence.
# Measured 2026-09-10 during this spec's own build: the alias landed empty and
# the audit reported three clean commits over a close it should have refused.
# The guard costs one test and removes the whole class.
if [[ -z "$SLH_TEMPLATE_FENCE_AWK" ]]; then
  printf 'trunk-audit: the template-fence reader is empty, so no Closing report can be read and no diagram claim can be checked. Refusing rather than reporting clean.\n' >&2
  exit 2
fi

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

# --- end of the byte-identical diagram readers -------------------------------

# THE AUDIT'S OWN ARMS over the shared readers above. One function, called from
# both routes, because the single-parent route and the merge route ask the same
# question of different commits and the v1.7 claims round found the audit's
# close-condition set a strict SUBSET of the hook's on exactly this field.
#
# THE SWITCH IS THE FIRST PARENT'S TREE (ruling S2, 2026-09-10), which is what
# makes this readable backwards at all: history from before docs/diagrams/
# existed has an unarmed first parent and is never judged, and the adoption
# commit itself is judged by the tree it started from rather than the one it
# created. An audit that armed on the commit's own tree would condemn the
# baseline chore the moment it walked past it, which is the retroactive shape
# the 1.1.0 review already made this file pay for once.
audit_diagram_tokens() { # audit_diagram_tokens <base> <commit> <spec-text> -> prints MISSING tokens
  local base="$1" rev="$2" text="$3" line answer named touched changed f
  slh_diagram_switch_on "$INSTANCE" "$base" || return 0
  line="$(slh_diagram_field_line "$text")"
  [ -n "$line" ] || return 0
  answer="$(slh_diagram_field_answer "$line")"
  changed="$(git -C "$INSTANCE" diff --name-only "$base" "$rev" 2>/dev/null || true)" # fail-open-ok: an unreadable diff yields an empty change set, under which "updated" naming any file reads as a claim the diff does not back and REFUSES; the accusing direction
  touched="$(slh_diagram_touched "$INSTANCE" "$base" "$rev" "$changed")"
  case "$answer" in
    updated)
      named="$(slh_diagram_field_files "$line")"
      if [ -z "$named" ]; then printf ' diagram-claim-names-nothing'; return 0; fi
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -qxF "$f" <<< "$changed" || { printf ' diagram-claim-unbacked(%s)' "$(slh_bound name "$f")"; return 0; }
      done <<EOF
$named
EOF
      ;;
    no-impact)
      [ -z "$touched" ] || printf ' diagram-undeclared(%s)' "$(slh_bound names "$touched")" ;;
  esac
  return 0
}

# The node evidence, per commit rather than per spec, for the reason the library
# gives at its own call site: both readers read the whole diagram surface.
audit_diagram_nodes() { # audit_diagram_nodes <base> <commit> <closing-nums> -> STDOUT is tokens ONLY; every report goes to stderr, because the caller captures stdout
  local base="$1" rev="$2" closing="$3" files f blob sp kind label skipped=0 out=""
  slh_diagram_switch_on "$INSTANCE" "$base" || return 0
  files="$(git -C "$INSTANCE" ls-tree -r --name-only "$rev" -- docs/diagrams/ steering/structure.md 2>/dev/null | grep -E '\.md$' || true)" # fail-open-ok: no readable diagram files yields no node claims to check, and the field arm above still compared the claim to the diff
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in docs/diagrams/generated/*) continue ;; esac
    blob="$(git -C "$INSTANCE" show "$rev:$f" 2>/dev/null || true)" # fail-open-ok: as above
    [ -n "$blob" ] || continue
    while IFS="$(printf '\t')" read -r sp kind label; do
      [ -n "$label" ] || continue
      case "$label" in
        */*) case "$label" in *[[:space:]]*) skipped=$((skipped+1)); continue ;; esac ;;
        *) skipped=$((skipped+1)); continue ;;
      esac
      slh_diagram_path_exists "$INSTANCE" "$rev" "$label" && continue
      if [ "$sp" != "-" ] && grep -qw "$sp" <<< "$closing"; then
        out="$out diagram-stale-node($(slh_bound name "$f:$label"))"
      else
        printf 'REPORT   %s  [SLH-DIAGRAM-STALE-NODE] %s draws a %s %s whose path does not exist at this commit; an EARLIER spec drew it, so it is reported and not counted. Redraw it in a close that names the file, or retire it with a note.\n' "$SHORT" "$(slh_bound name "$f")" "$kind" "$(slh_bound name "$label")" >&2
      fi
    done <<EOF
$(printf '%s\n' "$blob" | awk "$SLH_DIAGRAM_NODE_AWK")
EOF
  done <<EOF
$files
EOF
  # S4: a skip is PRINTED. The count alone here rather than the ids, because the
  # audit walks many commits and the hook already names them one close at a time.
  [ "$skipped" -eq 0 ] || printf 'REPORT   %s  [SLH-DIAGRAM-NODE-SKIPPED] %s drawn name(s) at this commit (nodes, subgraph ids, subgraph titles) are not path-shaped, so their existence was NOT verified.\n' "$SHORT" "$skipped" >&2
  printf '%s' "$out"
  return 0
}



SLH_RECORD_CLOSED_JQ='((.specs // {}) | to_entries[] | select(.value.status == "closed") | .key)'
# shellcheck disable=SC2034  # defined in every carrier so the suite pins the FULL reader set byte-identical; this carrier consumes a subset and the siblings consume the rest
SLH_RECORD_ACTIVE_JQ='((.specs // {}) | to_entries[] | select(.value.status == "active") | .key)'
SLH_RECORD_DONE_JQ='((.chores // {}) | to_entries[] | select(.value.status == "done") | .key)'
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
# (out of range, wrong shape), and the consumer REFUSES on any "!" token:
# SLH-OWNS-MALFORMED at the arm that would have consumed it.
# LOCKSTEP: byte-identical to templates/git-hooks/setlist-hook-lib.sh, which
# asks the same question of the STAGED close at the squash landing.
SLH_OWNS_AWK='{ l=$0; sub(/\r$/,"",l) } l ~ /^##[[:space:]]*Closing report/{r=1} r!=1 && l=="Tier: lite"{t=1} l ~ /^Owns:/{ if(r==1){print "!range";next} if(substr(l,1,6) != "Owns: "){print "!shape";next} p=substr(l,7); if(p=="" || p ~ /^[ \t]/ || p ~ /[ \t]$/ || index(p,"*") || index(p,"?") || index(p,"[") || index(p,"]") || index(p,"\\") || index(p,"\"") || index(p,"\047") || substr(p,1,1)=="/" || substr(p,1,2)=="./" || substr(p,length(p),1)=="/" || p ~ /(^|\/)\.\.(\/|$)/){print "!shape";next} n++; print p } END{ if(t && n>5) print "!lite-oversized" }'


# T1: THE CODEOWNERS BRIDGE AT THE AUDIT (spec 0132, design section 7; the
# 2.6.0 strategy's ruling 4). For a declaring close landing on the trunk, each
# declared file's owners (the LAST matching pattern of the repository's own
# CODEOWNERS, read at the commit under audit) must include the closer, and the
# closer at THIS layer is the closing commit's author EMAIL, the one identity a
# local audit can read. So: an email owner that does not match REFUSES
# (SLH-OWNS-CODEOWNERS); owners that are handles or teams cannot be resolved
# here and are REPORTED (SLH-OWNS-CODEOWNERS-UNRESOLVED), never refused, because
# refusing on an identity this layer cannot read is a false denial by
# construction (ratification decision 5); the forge check resolves them against
# the forge. A file this reader cannot parse refuses by name
# (SLH-CODEOWNERS-UNREADABLE) when a declaring close is being judged, and is
# never consulted otherwise. LOCKSTEP: the grammar string below is
# byte-identical to setlist-hook-lib.sh's (this file ships alone and sources
# nothing), asserted by the suite.
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

codeowners_arm() { # codeowners_arm <rev-with-the-file> <closing-commit> <declared-files, newline-separated> -> adds VIOLATIONS; 0 when nothing refused
  local rev="$1" c="$2" list="$3" cand text="" path="" bad f owners o ident lc_ident lc_o matched unresolved before
  before="$VIOLATIONS"
  for cand in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    git -C "$INSTANCE" cat-file -e "$rev:$cand" 2>/dev/null || continue
    text="$(git -C "$INSTANCE" show "$rev:$cand" 2>/dev/null)" || continue
    path="$cand"; break
  done
  [[ -n "$path" ]] || return 0
  bad="$(printf '%s\n' "$text" | awk -v mode=parse "$SLH_CODEOWNERS_AWK" | grep '^!unreadable' || true)" # fail-open-ok: an empty result means the file parsed; a parse that printed nothing at all yields no owners below, which is "no owner", the design's own reading of an owner-less pattern
  if [[ -n "$bad" ]]; then
    printf 'VIOLATION %s  [SLH-CODEOWNERS-UNREADABLE] line %s of %s uses %s, which this reader does not evaluate; a close that declares files under an unreadable ownership file cannot be checked against it. The reader accepts the core grammar the forges share (a path pattern with /, * and **, then owners as @login, @org/team or an email; last match wins).\n' \
      "$SHORT" "$(printf '%s' "$bad" | cut -f2)" "$path" "$(slh_codeowners_what "$(printf '%s' "$bad" | cut -f3)")"
    VIOLATIONS=$((VIOLATIONS + 1))
    return 1
  fi
  ident="$(git -C "$INSTANCE" log -1 --format=%ae "$c" 2>/dev/null)" # fail-open-ok: an unreadable author is empty and matches no owner, so every owned file refuses rather than passes
  lc_ident="$(printf '%s' "$ident" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r f; do
    [[ -n "$f" && "$f" != !* ]] || continue
    owners="$(printf '%s\n' "$text" | awk -v mode=owners -v file="$f" "$SLH_CODEOWNERS_AWK")"
    [[ -n "$owners" ]] || continue
    matched=0; unresolved=""
    for o in $owners; do
      case "$o" in
        @*) unresolved="$unresolved $o" ;;
        *)  lc_o="$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')"; [[ "$lc_o" == "$lc_ident" ]] && matched=1 ;;
      esac
      [[ "$matched" == "1" ]] && break
    done
    [[ "$matched" == "1" ]] && continue
    if [[ -n "$unresolved" ]]; then
      printf 'report    %s  [SLH-OWNS-CODEOWNERS-UNRESOLVED] %s is declared by this close and %s assigns it to %s, which this audit cannot resolve against %s (an email); the forge check resolves handles and teams against the forge. Reported, not refused.\n' \
        "$SHORT" "$(slh_bound name "$f")" "$path" "$(slh_bound name "${unresolved# }")" "$(slh_bound name "${ident:-an unreadable author}")"
      continue
    fi
    printf 'VIOLATION %s  [SLH-OWNS-CODEOWNERS] %s is declared by this close and %s assigns it to %s, which does not include %s. A close may declare only files its closer owns under the repository'"'"'s own ownership file; ask an owner to close it, or change the ownership file through its own review.\n' \
      "$SHORT" "$(slh_bound name "$f")" "$path" "$(slh_bound name "$owners")" "$(slh_bound name "${ident:-an unreadable author}")"
    VIOLATIONS=$((VIOLATIONS + 1))
  done <<EOF
$list
EOF
  [[ "$VIOLATIONS" -eq "$before" ]]
}

# A RULE IS DATED BY THE RELEASE THAT INTRODUCED IT (spec 0174, decision 3; ruling E-c).
# The audit re-walks the whole post-baseline history at every push, so a question added in
# 2.11.0 and asked of history made under 2.6.0 to 2.10.0 would condemn (or report on, at
# every push, with no remedy) work that was compliant when it was made; post_baseline dates
# a rule by the instance's ADOPTION, which is the wrong date for a rule added later. So an
# arm introduced in 2.11.0 is in force for a merge only when the merge's OWN tree stamps
# `plugin.version` 2.11.0 or later in .claude/sdd.json (the upgrade's refresh moves the
# key, so the first close after an upgrade carries it). Older, absent or unreadable: not in
# force, the pre-rule exemption's direction, stated rather than hidden.
RIF_KEY=""; RIF_RC=1  # the last answer: both arms ask it of the same merge in turn
rule_in_force() { # rule_in_force <commit> <major.minor> -> 0 when the commit's own sdd.json stamps that version or later
  local v
  [[ "$RIF_KEY" != "$1 $2" ]] || return "$RIF_RC"
  RIF_KEY="$1 $2"; RIF_RC=1
  v="$(git -C "$INSTANCE" show "$1:.claude/sdd.json" 2>/dev/null | jq -r '(.plugin.version // "") | strings' 2>/dev/null || true)" # fail-open-ok: an unreadable stamp is the pre-rule exemption this function exists to state
  awk -v v="$v" -v want="$2" "$SLH_VERSION_AT_LEAST_AWK" && RIF_RC=0
  return "$RIF_RC"
}

# THE CLOSE REVIEW (spec 0175): the close-review block read with the library's one reader
# (SLH_CLOSE_REVIEW_AWK above), at the four places this audit judges a close: the linear arm's
# record and page paths, and the merge arm's two landings beside codeowners_arm and
# audit_owns_overlap. A fast-forward or a forge-button close fires no merge hook, so the linear
# arm is the only reader it meets, which is why the linear arm reads the block too (the F4
# class). Each read is dated by rule_in_force on the close's own plugin.version, so an upgrade
# never condemns a close made before the review existed; each refusal carries the gate's code.
# A SKIP-DOCS-ONLY block is accepted only where the close brings no role-path change: the role
# paths decide the skip, never the reviewer.
# THE TREE THE GATE READ (spec 0180, fix round 2, the 2.11.0 leg's F9). The close gate reads
# the block from the index, and at a merge the index IS the merge commit; the merge arms read it
# from the merged parent's copy, so one close was judged two ways: a block written in the merge
# resolution passed the gate and was refused at push, and a FAIL written over the branch's PASS
# reached the trunk reading clean. At a merge the block is read from the merge commit's own tree,
# the question pre-commit asked, as merge_completion_may_read_commit does for the record; the
# linear arm already read the commit's own tree. The other readers of the merge arms keep the
# merged parent: this moves the close review alone.
# fail-open-ok: an unreadable tree yields empty text, which the reader answers "none", a refusal.
close_review_text_at() { git -C "$INSTANCE" show "$1:$2" 2>/dev/null | awk "$TEMPLATE_FENCE_AWK" || true; }
audit_close_review() { # audit_close_review <commit> <spec-text, template-stripped> <spec-num> <first-parent> -> adds VIOLATIONS; 0 when nothing refused
  local c="$1" out tok
  rule_in_force "$c" 2.11 || return 0
  out="$(printf '%s\n' "$2" | awk "$SLH_CLOSE_REVIEW_AWK")"
  tok="${out%% *}"
  case "$tok" in
    pass|accepted) return 0 ;;
    skip)
      touches_role "$4" "$c" || return 0
      printf 'VIOLATION %s  [SLH-CLOSE-REVIEW-SKIP-REFUSED] spec %s reads SKIP-DOCS-ONLY in its close review, but its close brings a file under a declared role path. The skip is decided by the role paths, never by the reviewer: it covers a close that touches no role path.\n' "$SHORT" "$3" ;;
    fail)
      printf 'VIOLATION %s  [SLH-CLOSE-REVIEW-FAIL] spec %s reached %s with a close review whose last round reads FAIL. The review runs again on the fixed diff (two rounds at most), and after round 2 the decision is the human'"'"'s, written as verdict: ACCEPTED-BY-HUMAN with the ids it accepts.\n' "$SHORT" "$3" "$TRUNK" ;;
    *)
      printf 'VIOLATION %s  [SLH-NO-CLOSE-REVIEW] spec %s reached %s without a usable close-review block in its Closing report (the reader said: %s). Since plugin 2.11.0 /setlist:checkpoint writes it from the close-reviewer agent, or as round 1: SKIP-DOCS-ONLY for a close that touches no role path.\n' "$SHORT" "$3" "$TRUNK" "${out:-nothing}" ;;
  esac
  VIOLATIONS=$((VIOLATIONS + 1))
  return 1
}

# TWO SPECS IN FLIGHT THAT DECLARE ONE FILE (spec 0174, item 3; TE1, the intake's O-10 as
# ruled). Disjoint `Owns:` sets let two specs proceed on two branches and close in turn. When
# the sets overlap, the SECOND close is the one whose branch never saw the first close's change:
# its branch left the trunk before the first close landed. That is decidable from the history
# this audit already walks, with no other branch read: the close under audit is a two-parent
# merge C with the trunk side P1 and the branch P2, BASE is their merge base (computed by the
# merge arm), and the window is the trunk's own first-parent commits after BASE up to P1. Each
# window commit E closed the specs whose status is closed at E and not at E^1 (the record's
# closed set where E carries .claude/status.json, the page's CLOSED cell otherwise); each such
# spec's `Owns:` set is read from its file AT E with the one ownership reader. A file in both
# sets refuses C by name, with the exact remedy: a catch-up merge of the trunk into the branch
# moves BASE past E, so the window no longer holds it and the same close is accepted. The first
# close is never refused (its window cannot hold the later one), nor is sequential work (a spec
# cut after E has BASE at or after E). NOT SEEN, and stated in the public text: a second close
# that is not a two-parent merge (squash, fast-forward: no branch point), and the `git pull`
# sync shape, which puts the earlier close on the pull merge's SECOND parent, off the
# first-parent line. REFUSED ALTHOUGH HONEST, and stated too (the validator's ruling E-b): a
# branch that took the earlier spec by merging its BRANCH rather than the trunk keeps BASE
# before E; the remedy the message names still works. Dated by rule_in_force (E-c).
OV_DONE=$'\n'  # the window commits already read, one per line
OV_DECL=""      # "<commit><TAB><spec><TAB><file>": each file a spec declares, keyed by the commit that closed it
audit_owns_overlap() { # audit_owns_overlap <merge> <p1> <base> <spec-num> <declared, newline-separated> -> adds VIOLATIONS; 0 when nothing refused
  local c="$1" p1="$2" base="$3" num="$4" list="$5" before="$VIOLATIONS" e e1 closed0 closed1 pg0 pg1 n sf f hit reported=$'\n'
  [[ -n "$list" ]] || return 0
  rule_in_force "$c" 2.11 || return 0
  [[ "$(git -C "$INSTANCE" cat-file -t "$base" 2>/dev/null)" == "commit" ]] || return 0 # unrelated histories: the branch never left this trunk, so there is no window
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    # What E closed and declared is a fact about E alone, read once per audit: windows of
    # branches in flight together overlap, and each would read the same commits again.
    case "$OV_DONE" in *$'\n'"$e"$'\n'*) ;; *)
      OV_DONE="$OV_DONE$e"$'\n'
      e1="$(git -C "$INSTANCE" rev-parse -q --verify "$e^1" 2>/dev/null)" || continue # a root has nothing before it to have closed since
      if record_present_at "$e"; then
        closed1="$(record_at "$e" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || true)" # fail-open-ok: an unreadable record at E closes nothing here; the merge arm refuses a malformed record on its own
        closed0="$(record_at "$e1" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || true)" # fail-open-ok: as above; an absent record before E reads as nothing closed, so E's whole closed set is new
      else
        # The page: a close flips its row, so the candidates are the rows E changed, each
        # confirmed CLOSED at E and not at E^1 by the page's one cell reader.
        # Each copy read through the live-text rule, as every page read here is: a row quoted
        # in a fence or a comment is not a close.
        closed1=""; closed0=""; pg1=""; pg0=""
        pg1="$(git -C "$INSTANCE" show "$e:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)" # fail-open-ok: an unreadable page at E closes nothing here
        pg0="$(git -C "$INSTANCE" show "$e1:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)" # fail-open-ok: an absent page before E reads as nothing closed
        while IFS= read -r n; do
          [[ -n "$n" ]] || continue
          row_is_closed "$pg1" "$n" || continue
          row_is_closed "$pg0" "$n" && continue
          closed1="$closed1$n"$'\n'
        done < <(git -C "$INSTANCE" diff "$e1" "$e" -- specs/STATUS.md 2>/dev/null | sed -n 's/^+[[:space:]]*|[[:space:]]*\([0-9][0-9]*[a-z]*\)[[:space:]]*|.*/\1/p')
      fi
      while IFS= read -r n; do
        [[ -n "$n" ]] || continue
        grep -qxF -- "$n" <<< "$closed0" && continue
        sf="$(git -C "$INSTANCE" ls-tree --name-only "$e" specs/ 2>/dev/null | grep -E "^specs/$n-[^/]*\.md$" | head -n1 || true)" # fail-open-ok: a closed spec whose file is gone declares nothing to compare
        [[ -n "$sf" ]] || continue
        while IFS= read -r f; do
          [[ -n "$f" ]] && OV_DECL="$OV_DECL$e"$'\t'"$n"$'\t'"$f"$'\n'
        done < <(git -C "$INSTANCE" show "$e:$sf" 2>/dev/null | awk "$SLH_OWNS_AWK" | grep -v '^!' || true) # fail-open-ok: no declarations is the blockless close, never compared
      done <<< "$closed1"
    ;; esac
    while IFS=$'\t' read -r _ n f; do
      [[ -n "$n" && "$n" != "$num" ]] || continue
      case "$reported" in *$'\n'"$e $n"$'\n'*) continue ;; esac
      grep -qxF -- "$f" <<< "$list" || continue
      hit="$f"; reported="$reported$e $n"$'\n'
      printf 'VIOLATION %s  [SLH-OWNS-OVERLAP] spec %s declares %s, which spec %s also declares and closed at %s after this branch left %s; the branch never carried that change. Merge %s into the spec branch so it carries that close, re-run the close, and merge again.\n' \
        "$SHORT" "$num" "$(slh_bound name "$hit")" "$n" "$(git -C "$INSTANCE" rev-parse --short "$e")" "$(slh_bound name "$TRUNK")" "$(slh_bound name "$TRUNK")"
      VIOLATIONS=$((VIOLATIONS + 1))
    done < <(grep -F -- "$e"$'\t' <<< "$OV_DECL" || true) # fail-open-ok: no line is E declaring nothing
  # Only the window commits that changed the record or the page can have closed anything, and
  # git names them in ONE read, each commit diffed against its FIRST parent (`-m` with
  # --first-parent): measured, a branch that lived through 200 trunk commits paid 20 s at every
  # push reading every one (spec 0174, E-d). NOT a pathspec: git's path-limited walk drops a
  # merge that is TREESAME to its second parent, which is exactly a --no-ff close of a branch
  # the trunk had not moved past (measured, control h read accepted under it).
  done < <(git -C "$INSTANCE" log --first-parent -m --name-only --format='@%H' "$p1" "^$base" 2>/dev/null \
    | awk '/^@/ { c = substr($0, 2); next } ($0 == ".claude/status.json" || $0 == "specs/STATUS.md") && !(c in seen) { seen[c] = 1; print c }')
  [[ "$VIOLATIONS" -eq "$before" ]]
}

# THE EVIL-EDIT ARM, REPORT-ONLY (spec 0174, item 1; the intake's O-3). The injected-file
# check below reads a merge's own ADDED files; an EDIT to a file both parents carry answered
# no to it by construction. git 2.38 and later can compute the clean merge of two parents
# without a worktree (`git merge-tree --write-tree`), and a merge commit's tree differs from
# that clean merge in exactly two ways: inside the files that CONFLICTED (a hand resolution,
# which is every real merge's business) and outside them (an edit the merge made that no
# parent asked for). This names every file of the second kind, every file and not role paths
# only, as a `report` line under [SLH-MERGE-EDIT-OUTSIDE-CONFLICT]; it adds no violation and
# never moves the exit status: a refusing arm needs a release of measurement first. Below git
# 2.38 it is skipped BY NAME, once per audit. A merge it cannot compute is reported by name
# and the audit goes on. merge-tree WRITES the clean tree's objects; they go to a private
# object directory with the instance's own as an alternate, removed at exit, so the audit
# writes nothing into the repository it reads (decision 4).
MT_STATE=""     # "", ok, old
MT_OBJDIR=""
MT_REALOBJ=""
audit_merge_tree() { # audit_merge_tree <merge> <p1> <p2> <short>: prints report lines only
  local c="$1" p1="$2" p2="$3" short="$4" gv maj=0 min=0 out tree f conflicted=$'\n' shown="" n=0
  if [[ -z "$MT_STATE" ]]; then
    gv="$(git version 2>/dev/null || true)" # fail-open-ok: an unreadable version is read as below 2.38 and the arm is skipped by name, never run blind
    if [[ "$gv" =~ ([0-9]+)\.([0-9]+) ]]; then maj="${BASH_REMATCH[1]}"; min="${BASH_REMATCH[2]}"; fi
    if [[ "$maj" -gt 2 ]] || [[ "$maj" -eq 2 && "$min" -ge 38 ]]; then
      MT_STATE=ok
    else
      MT_STATE=old
      printf 'report    [SLH-MERGE-EDIT-OUTSIDE-CONFLICT] skipped: %s is older than 2.38, which has no `git merge-tree --write-tree`, so no merge on %s was compared with the clean merge of its parents. Reported, not refused.\n' \
        "$(slh_bound text "${gv:-an unreadable git version}")" "$(slh_bound name "$TRUNK")"
    fi
  fi
  [[ "$MT_STATE" == "ok" ]] || return 0
  if [[ -z "$MT_OBJDIR" ]]; then
    MT_REALOBJ="$(git -C "$INSTANCE" rev-parse --path-format=absolute --git-path objects 2>/dev/null || true)" # fail-open-ok: an empty answer is caught on the next line and reported
    MT_OBJDIR="$(mktemp -d 2>/dev/null || true)" # fail-open-ok: as above
    trap 'rm -rf "${CFG_TMPD:-}" "${MT_OBJDIR:-}"' EXIT
    if [[ -z "$MT_REALOBJ" || -z "$MT_OBJDIR" ]]; then
      MT_STATE=nowhere
      printf 'report    [SLH-MERGE-EDIT-OUTSIDE-CONFLICT] skipped: no private object directory for the clean merges (check TMPDIR), so no merge on %s was compared. Reported, not refused.\n' "$(slh_bound name "$TRUNK")"
      return 0
    fi
  fi
  out="$(GIT_OBJECT_DIRECTORY="$MT_OBJDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$MT_REALOBJ${GIT_ALTERNATE_OBJECT_DIRECTORIES:+:$GIT_ALTERNATE_OBJECT_DIRECTORIES}" \
    git -C "$INSTANCE" merge-tree --write-tree -z --name-only --no-messages "$p1" "$p2" 2>/dev/null | tr '\0' '\n')"
  tree="$(head -n1 <<< "$out")"
  if [[ ! "$tree" =~ ^[0-9a-f]{40,64}$ ]]; then
    printf 'report    %s  [SLH-MERGE-EDIT-OUTSIDE-CONFLICT] git could not compute the clean merge of this merge'"'"'s parents, so its tree was not compared. Reported, not refused.\n' "$short"
    return 0
  fi
  conflicted="$conflicted$(tail -n +2 <<< "$out")"$'\n'
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    case "$conflicted" in *$'\n'"$f"$'\n'*) continue ;; esac
    n=$((n + 1))
    [[ "$n" -le 20 ]] && shown="$shown${shown:+, }$(slh_bound name "$f")"
  done < <(GIT_OBJECT_DIRECTORY="$MT_OBJDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$MT_REALOBJ${GIT_ALTERNATE_OBJECT_DIRECTORIES:+:$GIT_ALTERNATE_OBJECT_DIRECTORIES}" \
    git -C "$INSTANCE" diff -z --name-only --no-renames "$tree" "$c" 2>/dev/null)
  [[ "$n" -gt 20 ]] && shown="$shown and $((n - 20)) more"
  [[ "$n" -eq 0 ]] && return 0
  printf 'report    %s  [SLH-MERGE-EDIT-OUTSIDE-CONFLICT] this merge differs from the clean merge of its parents in %d file(s) outside the files that conflicted: %s. A conflict resolution changes only conflicted files, so each of these is an edit the merge itself made; review it at the forge. Reported, not refused.\n' \
    "$short" "$n" "$shown"
}

record_present_at() { git -C "$INSTANCE" cat-file -e "$1:.claude/status.json" 2>/dev/null; }
# fail-open-ok: unreadable-but-present yields empty text, which is not "ok" to
# record_verdict, so every consumer treats it as the malformed record it is.
record_at() { git -C "$INSTANCE" show "$1:.claude/status.json" 2>/dev/null || true; }

# THE MERGE COMMIT'S OWN COMPLETION (spec 0157, F10-2026 closed).
#
# pre-merge-commit refuses a merge that records no completion and its message
# says to add the line "in this same commit"; git then says to complete the
# merge with `git commit`, which fires pre-commit, whose merge-completion
# verification reads the INDEX and accepts. That index becomes the MERGE COMMIT.
# This arm read only the merged PARENT, so the identical commit was accepted at
# commit time and refused at push, on the route the refusal text itself
# prescribes. Measured by the 2.4.1 adversarial review, identical on the shipped
# 2.4.0 bytes, and disclosed as an open limitation until now.
#
# So when the merged parent answers the completion question with nothing, the
# question is asked of the merge commit against the trunk side, which is exactly
# what pre-commit asked of the index. TWO PARENTS ONLY: crediting one record
# written on a merge commit to SEVERAL merged parents would re-open the
# laundering route the B6 fix closed (`git merge spec/0001-ok sneaky`), and the
# refused-then-completed case is the ordinary two-parent one.
#
# It widens WHERE a completion may be written and nothing else: a merge with the
# completion on neither side is refused exactly as before, and the suite pins
# both controls beside the flipped case.
merge_completion_may_read_commit() { # merge_completion_may_read_commit -> 0 for a two-parent merge
  [[ "$NPAR" -eq 2 ]]
}
# ONE TOKEN OUT, the attestation verifier's calling convention: the caller
# refuses anything that is not exactly "ok", so an empty result, a crashed jq
# or a truncated read refuses BY CONSTRUCTION. jq's exit status is carried.
record_verdict() { printf '%s' "$1" | jq -r "$SLH_RECORD_CHECK_JQ" 2>/dev/null || printf 'malformed'; }

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
  SUBJ="$(slh_bound text "$(git -C "$INSTANCE" log -1 --format=%s "$C" | cut -c1-58)")"
  SHORT="$(git -C "$INSTANCE" rev-parse --short "$C")"

  # THE OCTOPUS ONTO THE TRUNK (spec 0173, item 4; the intake's ratified row, 0166 row 28).
  # A close merges ONE spec branch, so a commit on the trunk with more than two parents is
  # never a compliant close, whatever its parents carry: it is refused BY NAME, ahead of and
  # instead of the per-parent reading, which judged it as a chore-shaped merge with no
  # recorded completion (measured) or passed it when every parent was a compliant close.
  # Post-adoption only: the B2 restatement below keeps the doctrine that an audit does not
  # condemn history made before its rules, and a pre-adoption octopus keeps that exemption
  # ("audit age d"). The CHAINED route, an octopus merged INTO a spec branch and closed with
  # two parents, is untouched: it is the `git pull` shape (Known limitations, crafted merges).
  # DATED BY THE RELEASE THAT INTRODUCED IT (spec 0180, 0174's E-e as ruled): this is a 2.11.0
  # rule, so it is in force only for a merge whose OWN tree stamps plugin.version 2.11.0 or later
  # (rule_in_force, as 0174's arms and 0175's reader are dated; the reason is at rule_in_force's
  # comment above). An octopus a 2.9.0 or 2.10.0 instance made and pushed after adoption was
  # accepted then, and refusing it now would refuse every later push with a remedy that cannot
  # apply to pushed history ("audit age e"). Such a merge still takes the per-parent reading
  # below, so an unjustified parent is still a violation ("audit age c").
  if [[ "$NPAR" -gt 2 ]] && post_baseline "$C" && rule_in_force "$C" 2.11; then
    printf 'VIOLATION %s  [SLH-OCTOPUS-MERGE] a merge of %d branches reached %s at once, made after this instance adopted the rules; a close merges ONE spec branch, so merge each branch on its own\n' "$SHORT" "$((NPAR - 1))" "$TRUNK"
    printf '          %s\n' "$SUBJ"
    VIOLATIONS=$((VIOLATIONS + 1))
    continue
  fi

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
    # Did this commit COMPLIANTLY close a spec? Set by the loop below and read
    # by the touches-role decision at the end of this arm (F4).
    LIN_CLOSED_OK=0
    LIN_STRUCTURED=0
    LIN_NEWLY=""
    LIN_CHORE_NEW=""
    LIN_DECLARING=0
    LIN_BLOCKLESS=0
    LIN_CHORE_FLIP=0
    LIN_OWNS_SHAPE_BAD=0
    LIN_OWNS_LIST=""
    if [[ -n "$P1" ]] && record_present_at "$C"; then
      # THE RECORD DECIDES (RP1). The commit's own tree carries the status
      # record, so which specs this commit newly closes is a diff of two jq
      # queries, and the close facts are the tokens checkpoint wrote, not a
      # parse of the spec's rendered markdown.
      LIN_STRUCTURED=1
      LIN_REC_C="$(record_at "$C")"
      if [[ "$(record_verdict "$LIN_REC_C")" != "ok" ]]; then
        printf 'VIOLATION %s  [SLH-RECORD-MALFORMED] .claude/status.json at this commit is not a well-formed status record, so no close or chore fact can be read from it. Nothing falls back to the page readers. Only /setlist:checkpoint writes this file; fix the record.\n' "$SHORT"
        printf '          %s\n' "$SUBJ"
        VIOLATIONS=$((VIOLATIONS + 1))
      elif record_present_at "$P1"; then
        LIN_REC_P1="$(record_at "$P1")"
        if [[ "$(record_verdict "$LIN_REC_P1")" != "ok" ]]; then
          printf 'VIOLATION %s  [SLH-RECORD-MALFORMED] .claude/status.json at the parent is not a well-formed status record, so which specs this commit NEWLY closes cannot be computed against it.\n' "$SHORT"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
        else
          LIN_C_CLOSED="$(printf '%s' "$LIN_REC_C" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || printf '\n!jq-failed')"
          LIN_P1_CLOSED="$(printf '%s' "$LIN_REC_P1" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || printf '\n!jq-failed')"
          if grep -q '^!jq-failed$' <<< "$LIN_C_CLOSED$LIN_P1_CLOSED"; then
            printf 'VIOLATION %s  [SLH-RECORD-MALFORMED] jq failed while reading the status record, so the closing set cannot be established; a reader that could not run has not read.\n' "$SHORT"
            VIOLATIONS=$((VIOLATIONS + 1))
          else
            for LIN_NUM in $LIN_C_CLOSED; do
              grep -qxF -- "$LIN_NUM" <<< "$LIN_P1_CLOSED" && continue
              LIN_NEWLY="$LIN_NEWLY $LIN_NUM"
            done
            # Chores newly done in this commit's record (F5-2026's half): the
            # same before-and-after rule as the specs, and the declared set is
            # chores.<id>.files, gathered below into the same per-file
            # question. The widening the 2.3.0 leg warned about came from
            # exempting the COMMIT on the archive line's presence; per-file
            # coverage against the chore's declared files cannot reproduce it.
            LIN_C_DONE="$(printf '%s' "$LIN_REC_C" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)"   # fail-open-ok: an empty done set flips no chore and grants nothing
            LIN_P1_DONE="$(printf '%s' "$LIN_REC_P1" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: as above, empty grants nothing
            for LIN_CN in $LIN_C_DONE; do
              grep -qxF -- "$LIN_CN" <<< "$LIN_P1_DONE" && continue
              LIN_CHORE_NEW="$LIN_CHORE_NEW $LIN_CN"
            done
          fi
        fi
      fi
      # THE ADOPTION COMMIT CLOSES NOTHING: a record present here and absent at
      # the parent is the instance opting in, and entries arriving already
      # closed are transcription. Demanding close facts of them would refuse
      # every opt-in whose history predates the record; granting the exemption
      # would let an adoption commit buy what a close must earn. LIN_NEWLY
      # stays empty: nothing demanded, nothing granted.
    fi
    if [[ "$LIN_STRUCTURED" == "1" ]]; then
      for LIN_NUM in $LIN_NEWLY; do
        # Same narrowing as the library (leg F6): the exact number then a
        # hyphen, and a count rather than head -n1, because 0002b is a
        # different spec and a pick among several is a guess.
        # -z and a NUL-aware grep (F1's class, on the spec side): a spec file whose
        # name carries a non-ASCII byte, a quote, a backslash or a control character
        # is emitted QUOTED by --name-only and would miss this pattern, so the audit
        # would report "no spec file" about a spec that is present. Same defect as
        # the role reader, opposite consequence: there it under-refuses, here it
        # over-refuses.
        LIN_HITS="$(git -C "$INSTANCE" ls-tree -r -z --name-only "$C" 2>/dev/null | grep -zE "^specs/${LIN_NUM}-[^/]*\.md$" | tr '\0' '\n' || true)" # fail-open-ok: no file yields empty, handled as its own violation below
        if [ -n "$LIN_HITS" ] && [ "$(printf '%s\n' "$LIN_HITS" | grep -c .)" -ne 1 ]; then
          printf 'VIOLATION %s  spec %s has several files matching specs/%s-*.md, so its close cannot be verified: %s\n' \
            "$SHORT" "$LIN_NUM" "$LIN_NUM" "$(slh_bound names "$LIN_HITS")"
          VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
          continue
        fi
        LIN_FILE="$LIN_HITS"
        if [[ -z "$LIN_FILE" ]]; then
          printf 'VIOLATION %s  spec %s marked CLOSED with no specs/%s-*.md to verify\n' "$SHORT" "$LIN_NUM" "$LIN_NUM"
          VIOLATIONS=$((VIOLATIONS + 1)); continue
        fi
        # THE CLOSE FACTS ARE THE RECORD'S TOKENS (RP1): qa_pass_1 and diagram,
        # written by checkpoint at the close. The spec's prose Closing report
        # stays a human artifact this arm no longer parses; running the page
        # checks here too would be two readers per fact, the A9 violation the
        # record exists to end.
        LIN_FACTS="$(printf '%s' "$LIN_REC_C" | jq -r --arg num "$LIN_NUM" "$SLH_RECORD_FACTS_JQ" 2>/dev/null || printf 'jq-failed')"
        if [[ "$LIN_FACTS" != "ok" ]]; then
          printf 'VIOLATION %s  [SLH-RECORD-NO-CLOSE] spec %s is newly closed in .claude/status.json without its close facts (status closed, qa_pass_1 ok, diagram updated or no-impact; the reader said: %s). /setlist:checkpoint writes these at the close; run the close through checkpoint rather than editing the record by hand.\n' "$SHORT" "$LIN_NUM" "${LIN_FACTS:-nothing at all}"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          continue
        fi
        # THE DIAGRAM ARMS RUN HERE TOO (F1 of the 2.7.0 leg, fix round 1).
        #
        # They used to live only on the absence path below, so on any instance
        # that closes through /setlist:checkpoint, which has written
        # .claude/status.json since v1.12, NEITHER route ever ran them: the
        # field was never compared to the diff and no drawn node was ever
        # resolved. Every close route that fires no merge hook (a fast-forward,
        # a --squash, a cherry-pick, the forge merge button) therefore carried
        # an unbacked diagram claim to the remote while this audit printed
        # clean. Measured on a real stamped instance before the fix.
        #
        # THIS IS NOT THE SECOND READER THE RECORD EXISTS TO END (A9). The
        # record carries the diagram ANSWER token and deliberately not the file
        # list, because a new key would make every 2.6.1 clone in the same
        # repository refuse ordinary commits. So the claim-versus-diff question
        # has no reader on the structured path at all, and these two arms are
        # its only one rather than a duplicate of the record's.
        LIN_DIAG_TEXT="$(git -C "$INSTANCE" show "$C:$LIN_FILE" 2>/dev/null | awk "$TEMPLATE_FENCE_AWK" || true)" # fail-open-ok: unreadable yields empty, under which a field naming files reads as a claim the diff does not back and REFUSES, the accusing direction
        LIN_DMISS="$(audit_diagram_tokens "$P1" "$C" "$LIN_DIAG_TEXT")$(audit_diagram_nodes "$P1" "$C" "$LIN_NUM")"
        if [[ -n "$LIN_DMISS" ]]; then
          printf 'VIOLATION %s  spec %s was marked CLOSED without:%s\n' "$SHORT" "$LIN_NUM" "$LIN_DMISS"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
          continue
        fi
        # THE CLOSE REVIEW (spec 0175) on the linear route's record path: the block lives in
        # the Closing report on both paths, as the diagram field does.
        if ! audit_close_review "$C" "$LIN_DIAG_TEXT" "$LIN_NUM" "$P1"; then
          printf '          %s\n' "$SUBJ"
          SEEN_BAD=1
          continue
        fi
        # A COMPLIANT CLOSE, ON A COMMIT WITH FEWER THAN TWO PARENTS (F4),
        # established by the record. WHAT IT EXEMPTS is the ownership
        # question (design section 8.2): a spec that DECLARES its files gets
        # per-file coverage instead of the whole-commit exemption; a spec
        # declaring NOTHING keeps today's behaviour exactly (the Spec-hash
        # absence precedent, and the only answer that does not re-refuse the
        # compliant legacy squash close F4's fix exists to permit). A
        # declaration outside the grammar refuses at this arm, because a
        # declared set you cannot enumerate is an exemption wearing a
        # declaration.
        LIN_OWNS_OUT="$(git -C "$INSTANCE" show "$C:$LIN_FILE" 2>/dev/null | awk "$SLH_OWNS_AWK" || true)" # fail-open-ok: an unreadable spec declares nothing, and nothing is the narrow direction here: it forfeits per-file coverage rather than widening it
        # THE LITE TIER'S CAP (edition v1.14, P1): the reader appends the token
        # when a `Tier: lite` spec declares more than five files; refused here
        # as at the hooks, then stripped so the declared set is still judged.
        if grep -q '^!lite-oversized$' <<< "$LIN_OWNS_OUT"; then
          printf 'VIOLATION %s  [SLH-LITE-OVERSIZED] spec %s is declared Tier: lite and declares more than five files under Owns:. A lite spec is at most five files (Part 3 of the edition); the two honest exits are to drop the tier line (a full spec, judged exactly as before) or to split the work, both through /setlist:checkpoint. The tier is a claim about size, and a claim the close cannot honour is refused rather than reread.\n' "$SHORT" "$LIN_NUM"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          LIN_OWNS_OUT="$(printf '%s\n' "$LIN_OWNS_OUT" | grep -v '^!lite-oversized$')"
        fi
        if grep -q '^!' <<< "$LIN_OWNS_OUT"; then
          printf 'VIOLATION %s  [SLH-OWNS-MALFORMED] spec %s declares ownership outside the grammar (a glob, a directory, a quoted or empty path, or an Owns: line below the Closing report heading). One verbatim repo-relative file per "Owns: " line, at column 0, inside the hashed range. The range ends at the FIRST line reading "## Closing report", fences included, because that byte-same cut is what attestation signs: a fenced or quoted copy of the Closing-report template ABOVE your declaration ends the range early, and the fix is one edit (move the declaration above the quote, or drop the quoted heading line). A declared set that cannot be enumerated is an exemption wearing a declaration, so this close exempts nothing until the declaration is fixed through /setlist:checkpoint.\n' "$SHORT" "$LIN_NUM"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          LIN_OWNS_SHAPE_BAD=1
        elif [[ -z "$LIN_OWNS_OUT" ]]; then
          LIN_BLOCKLESS=1
          LIN_CLOSED_OK=1
        else
          LIN_DECLARING=1
          LIN_OWNS_LIST="$LIN_OWNS_LIST
$LIN_OWNS_OUT"
        fi
      done
      # The chore half of the declared set: files come from the record, and a
      # chore that declares no files covers nothing, which is the false-deny
      # direction with the exits named below.
      for LIN_CN in $LIN_CHORE_NEW; do
        LIN_CHORE_FLIP=1
        LIN_CF="$(printf '%s' "$LIN_REC_C" | jq -r --arg id "$LIN_CN" "$SLH_RECORD_CHORE_FILES_JQ" 2>/dev/null || true)" # fail-open-ok: no files declared covers nothing, it cannot widen
        [[ -n "$LIN_CF" ]] && LIN_OWNS_LIST="$LIN_OWNS_LIST
$LIN_CF"
      done
    elif [[ -n "$P1" ]]; then
      # LIVE TEXT AT THE SOURCE (2026-08 consolidation): the row readers judge
      # STATUS.md by what the rendered file shows, so a fenced example row or a
      # commented-out row is not an inventory row here either. Stripped once at
      # extraction, in lockstep with the library's guard_close.
      # THIS IS THE ABSENCE PATH (RP1): no record at this commit, so the page
      # and the frozen readers decide, byte-identical to what shipped before.
      LIN_NEW="$(git -C "$INSTANCE" show "$C:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"   # fail-open-ok: no STATUS.md at this commit yields empty, so no row can be read as newly closed, which is correct for a repository that has none
      LIN_OLD="$(git -C "$INSTANCE" show "$P1:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)"  # fail-open-ok: as above, an absent parent copy means every present row reads as new, which accuses rather than excuses
      for LIN_NUM in $(printf '%s\n' "$LIN_NEW" | sed 's/\\|/ /g' | awk -F'|' 'NF >= 5 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 ~ /^[0-9]+[a-z]*$/) print $2 }'); do  # sed: GFM escaped pipe (round 11)
        row_is_closed "$LIN_NEW" "$LIN_NUM" || continue
        row_is_closed "$LIN_OLD" "$LIN_NUM" && continue
        # Same narrowing as the library (leg F6): the exact number then a
        # hyphen, and a count rather than head -n1, because 0002b is a
        # different spec and a pick among several is a guess.
        # -z and a NUL-aware grep (F1's class, on the spec side): a spec file whose
        # name carries a non-ASCII byte, a quote, a backslash or a control character
        # is emitted QUOTED by --name-only and would miss this pattern, so the audit
        # would report "no spec file" about a spec that is present. Same defect as
        # the role reader, opposite consequence: there it under-refuses, here it
        # over-refuses.
        LIN_HITS="$(git -C "$INSTANCE" ls-tree -r -z --name-only "$C" 2>/dev/null | grep -zE "^specs/${LIN_NUM}-[^/]*\.md$" | tr '\0' '\n' || true)" # fail-open-ok: no file yields empty, handled as its own violation below
        if [ -n "$LIN_HITS" ] && [ "$(printf '%s\n' "$LIN_HITS" | grep -c .)" -ne 1 ]; then
          printf 'VIOLATION %s  spec %s has several files matching specs/%s-*.md, so its close cannot be verified: %s\n' \
            "$SHORT" "$LIN_NUM" "$LIN_NUM" "$(slh_bound names "$LIN_HITS")"
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
        grep -qE $'^ {0,3}#{1,6}[ \t]+Closing report' <<< "$LIN_TEXT" || LIN_MISS="$LIN_MISS no-closing-report"
        [[ "$(printf '%s\n' "$LIN_TEXT" | awk "$QA_PASS1_AWK")" == "ok" ]] || LIN_MISS="$LIN_MISS no-qa-verdict"
        LIN_DIAG="$(printf '%s\n' "$LIN_TEXT" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | awk 'NR == 1')" # fail-open-ok: empty is the missing field, tested next
        LIN_ANS="$(printf '%s' "$LIN_DIAG" | sed -e 's/^[-*+>[:space:]]*Architecture diagram:[[:space:]]*//')"
        # PLACEHOLDER SHAPE, NOT THE CHARACTER '<' (leg F11, here too). This arm
        # kept the pre-F11 predicate after the merge arm below was corrected, so
        # `updated in this commit (added <auth> box)` refused in this arm alone.
        # Same fix, same direction, same reasoning as the merge arm's DIAG_ANSWER.
        LIN_ANS="$(printf '%s' "$LIN_ANS" | sed 's/<[^>]*>//g')"
        # THE ARMED FORM IS AN ANSWER TOO (edition v1.15), and only when armed,
        # for the reason the library states at its own copy: widening the reader
        # on an unarmed instance would change what v1.14 accepts, which the
        # absence differential forbids.
        LIN_ARMED=0; slh_diagram_switch_on "$INSTANCE" "$P1" && LIN_ARMED=1
        if [[ -z "$LIN_DIAG" ]]; then LIN_MISS="$LIN_MISS no-diagram-field"
        elif ! grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)' <<< "$(printf '%s' "$LIN_ANS" | sed 's/^[[:space:]]*//')" \
             && ! { [[ "$LIN_ARMED" == "1" ]] && grep -qE '^updated[[:space:]]*\(' <<< "$(printf '%s' "$LIN_ANS" | sed 's/^[[:space:]]*//')"; }; then LIN_MISS="$LIN_MISS diagram-unanswered"; fi
        # THE FIELD AGAINST THE DIFF, AND THE NODES AGAINST THE TREE (v1.15).
        LIN_MISS="$LIN_MISS$(audit_diagram_tokens "$P1" "$C" "$LIN_TEXT")"
        LIN_MISS="$LIN_MISS$(audit_diagram_nodes "$P1" "$C" "$LIN_NUM")"
        # THE CLOSE REVIEW (spec 0175) on the linear route's page path: its own line, with
        # the gate's code; a close that fails it is not the compliant close below.
        LIN_CR_OK=1
        if ! audit_close_review "$C" "$LIN_TEXT" "$LIN_NUM" "$P1"; then
          printf '          %s\n' "$SUBJ"
          LIN_CR_OK=0
        fi
        if [[ -n "$LIN_MISS" ]]; then
          printf 'VIOLATION %s  spec %s was marked CLOSED without:%s\n' "$SHORT" "$LIN_NUM" "$LIN_MISS"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
        elif [[ "$LIN_CR_OK" == "1" ]]; then
          # A COMPLIANT CLOSE, ON A COMMIT WITH FEWER THAN TWO PARENTS (F4).
          LIN_CLOSED_OK=1
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
    #
    # A COMPLIANT FAST-FORWARD OR SQUASH CLOSE IS NOT "CODE COMMITTED DIRECTLY"
    # (F4, and the two spellings are one shape). A `git merge --ff` of a linear
    # spec branch creates no merge commit; a `git merge --squash` creates a
    # commit with no second parent. Both therefore land role-path work on the
    # trunk in a commit with fewer than two parents, pre-commit allows them, and
    # this arm then called them violations FOREVER: the push was refused every
    # time, with no way forward but rewriting history, for work that satisfied
    # every close condition the framework asks for.
    #
    # KEYED ON THE PARENT COUNT, which is why one fix covers both. This arm is
    # already the "fewer than two parents" arm, and the close verification above
    # has already asked the real question of this exact commit: did a row flip to
    # CLOSED, and does the spec carry its Closing report, its QA verdict and its
    # diagram field. A commit that passed that is a close, whatever flag produced
    # it. A fix keyed on the flag NAME would have covered neither honestly, since
    # neither flag is visible in the history this script reads.
    #
    # The direction is narrow on purpose: LIN_CLOSED_OK is set only where the
    # close verification found a flip AND found nothing missing. A commit that
    # flips a row and fails a condition is still a violation, reported by that
    # loop with the condition named; a commit that carries code and closes
    # nothing is still "feature code committed directly".
    # THE PER-FILE ARM (design 8.2), replacing the whole-commit exemption for
    # a close that DECLARES and for a chore flip: for each role-path file in
    # this commit, is it in the declared set read from the bytes IN THIS
    # COMMIT? Every file covered: clean. Any file not covered: refused, the
    # false-deny direction, with the two honest exits named. The attack now
    # fails on SHAPE: still-active spec 0004's src/wip.txt is not in closing
    # spec 0005's declared set, so the byte-identical commit that used to
    # audit "1 clean, 0 violations" refuses. The honest squash close passes
    # on shape, its files declared at checkpoint commits during the build.
    # A blockless close never reaches this arm (LIN_BLOCKLESS above), and a
    # malformed declaration already refused and exempts nothing.
    if [[ "$LIN_STRUCTURED" == "1" && "$LIN_BLOCKLESS" == "0" && "$LIN_OWNS_SHAPE_BAD" == "0" && ( "$LIN_DECLARING" == "1" || "$LIN_CHORE_FLIP" == "1" ) ]]; then
      LIN_OWNS_VIOL=0
      while IFS= read -r -d '' LIN_RF; do
        [[ -n "$LIN_RF" ]] || continue
        touches_role_file "$LIN_RF" || continue
        # Declared paths match by EXACT bytes, never by fold or glob: a
        # case-variant of a declared path is a different string, reads as
        # undeclared, and refuses, which is the safe direction (PD9's class).
        if ! grep -qxF -- "$LIN_RF" <<< "$LIN_OWNS_LIST"; then
          printf 'VIOLATION %s  [SLH-OWNS-UNDECLARED] %s is a role-path file this close does not declare. A declaring close is audited file by file against its declared set, so a whole commit can no longer be exempted by one row flip. Two honest exits: declare the file through /setlist:checkpoint (under attestation custody that means re-approval, correctly), or take the --no-ff merge route, whose arm asks the provenance question instead.\n' "$SHORT" "$(slh_bound name "$LIN_RF")"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          LIN_OWNS_VIOL=1
        fi
      done < <(git -C "$INSTANCE" diff -z --name-only --diff-filter=d "$P1" "$C" 2>/dev/null)
      # --diff-filter=d (2.4.0 leg F7): the arm asks what ARRIVES on the trunk,
      # and a deleted path arrives nowhere; before the filter the same
      # retirement passed spelled `git mv` and refused spelled `git rm`. The
      # merge arm's provenance sibling already filters (--diff-filter=A below).
      # T1: the declared set against the repository's ownership file, on the
      # closing commit's author email (the arm above has already read the set).
      if [[ "$LIN_OWNS_VIOL" == "0" ]] && ! codeowners_arm "$C" "$C" "$LIN_OWNS_LIST"; then
        printf '          %s\n' "$SUBJ"
        LIN_OWNS_VIOL=1
      fi
      if [[ "$LIN_OWNS_VIOL" == "0" ]]; then
        CLEAN=$((CLEAN + 1))
      fi
      continue
    fi
    if [[ "$LIN_CLOSED_OK" -eq 1 ]]; then
      CLEAN=$((CLEAN + 1))
    elif touches_role "$P1" "$C"; then
      printf 'VIOLATION %s  feature code committed directly to %s\n' "$SHORT" "$TRUNK"
      printf '          %s\n' "$SUBJ"
      VIOLATIONS=$((VIOLATIONS + 1))
    else
      CLEAN=$((CLEAN + 1))
    fi
    continue
  fi

  # AN EDIT NO PARENT ASKED FOR (spec 0174): the evil-edit arm (audit_merge_tree),
  # report-only, for every two-parent merge made under the release that introduced it,
  # asked HERE, before the role-path shortcut below: a merge that brings no role-path
  # change (a docs branch, a `-s ours` merge that drops one side) can still edit a file.
  if [[ "$NPAR" -eq 2 ]] && rule_in_force "$C" 2.11; then
    audit_merge_tree "$C" "$P1" "${PARENT_ARR[2]}" "$SHORT"
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
    # Unrelated histories have no merge-base, and the comment here used to say
    # an empty BASE widened the search. It did not (spec 0164, fix round 2, F5
    # of the 2.10.0 leg): `git diff --name-only "" <p2>` is a fatal argument
    # error, the search read NOTHING, and a merge that imported a whole
    # subproject with --allow-unrelated-histories audited clean while its spec
    # and its role-path files sat on the trunk. The widening is written down
    # now: with no merge-base the branch is diffed against the EMPTY TREE, which
    # really is its whole content.
    BASE="$(git -C "$INSTANCE" merge-base "$P1" "$P2" 2>/dev/null || true)" # fail-open-ok: no merge-base is the unrelated-histories case, and the empty tree below reads the whole branch rather than nothing
    if [[ -z "$BASE" ]]; then
      # fail-open-ok: an empty answer here cannot be swallowed, the die below refuses the audit
      BASE="$(git -C "$INSTANCE" hash-object -t tree /dev/null 2>/dev/null || true)"
      [[ -n "$BASE" ]] || die "[SLH-RECORD-MALFORMED] git could not name the empty tree in $INSTANCE, so a merge of unrelated histories cannot be read at all and a clean report would be a false attestation."
    fi
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
    SPECS_TOUCHED="$(git -C "$INSTANCE" diff -z --name-only "$BASE" "$P2" 2>/dev/null | tr '\0' '\n' \
      | grep -E '^specs/[0-9]+[a-z]*-[^/]*\.md$' || true)"   # fail-open-ok: no match means no spec on the branch, handled as a chore below

    # THE RECORD, OR THE PAGE (RP1): the branch side carrying .claude/status.json
    # answers the chore and close questions from the record; a branch without
    # one takes the page path below, byte-identical to what shipped before.
    # Malformed is a violation for THIS parent, never a fallback.
    MRG_STRUCTURED=0
    MRG_REC_P2=""
    MRG_REC_P1=""
    # The merge commit's own page, read once for the two completion questions
    # spec 0157 asks of it (the archive line and the CLOSED row). Empty when the
    # merge is not a two-parent one, so nothing reads it there.
    STATUS_TEXT_C=""
    if merge_completion_may_read_commit; then
      STATUS_TEXT_C="$(git -C "$INSTANCE" show "$C:specs/STATUS.md" 2>/dev/null | awk "$SLH_LIVE_TEXT_AWK" || true)" # fail-open-ok: an unreadable STATUS.md yields empty, which fails every test below and cannot excuse a merge
    fi
    # WHICH RULEBOOK: THE MERGE COMMIT'S OWN READING (spec 0167, decision 3;
    # L2 F6 of the 2.10.0 second leg). pre-commit chooses record or page from
    # the INDEX of the commit completing a merge, and that index becomes C. This
    # arm chose from the merged parent P2 alone, so a branch cut before the
    # instance adopted .claude/status.json, its refused merge completed on the
    # trunk side as the message prescribes, passed by the record at commit and
    # was refused by the page at push, with no amend able to fix it. So for a
    # TWO-PARENT merge whose branch carries no record, C's own record decides
    # when it COMPLETES this merge against the trunk side: it newly closes a
    # spec the branch touched, or, for a branch touching no spec, newly marks a
    # chore done. A C record that completes nothing leaves the page path on P2
    # exactly as it was, so no pre-record history is newly refused. An octopus
    # is not credited (merge_completion_may_read_commit), for the reason 0157
    # gives. Inline rather than a helper: the question is asked once, here.
    MRG_REC_FROM_C=0
    if ! record_present_at "$P2" && merge_completion_may_read_commit && record_present_at "$C"; then
      MRG_REC_C0="$(record_at "$C")"
      if [[ "$(record_verdict "$MRG_REC_C0")" == "ok" ]]; then
        MRG_REC_P10=""
        record_present_at "$P1" && MRG_REC_P10="$(record_at "$P1")"
        if [[ -n "$SPECS_TOUCHED" ]]; then
          MRG_NEW_C="$(printf '%s' "$MRG_REC_C0" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || true)" # fail-open-ok: an empty closed set completes nothing and leaves the page path in charge
          MRG_OLD_P1="$(printf '%s' "$MRG_REC_P10" | jq -r "$SLH_RECORD_CLOSED_JQ" 2>/dev/null || true)" # fail-open-ok: an unreadable trunk-side record reads as nothing closed before, the permissive direction the record path already takes
          while IFS= read -r MRG_SF; do
            [[ -n "$MRG_SF" ]] || continue
            MRG_SN="$(printf '%s' "$MRG_SF" | sed -e 's#^specs/##' -e 's#-.*##')"
            if grep -qxF -- "$MRG_SN" <<< "$MRG_NEW_C" && ! grep -qxF -- "$MRG_SN" <<< "$MRG_OLD_P1"; then
              MRG_REC_FROM_C=1; break
            fi
          done <<< "$SPECS_TOUCHED"
        else
          MRG_NEW_C="$(printf '%s' "$MRG_REC_C0" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: an empty done set completes nothing and leaves the page path in charge
          MRG_OLD_P1="$(printf '%s' "$MRG_REC_P10" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: as above
          while IFS= read -r MRG_SN; do
            [[ -n "$MRG_SN" ]] || continue
            if ! grep -qxF -- "$MRG_SN" <<< "$MRG_OLD_P1"; then MRG_REC_FROM_C=1; break; fi
          done <<< "$MRG_NEW_C"
        fi
      fi
    fi
    if record_present_at "$P2" || [[ "$MRG_REC_FROM_C" == "1" ]]; then
      MRG_STRUCTURED=1
      # The branch's record, or, on the mixed shape above, the merge commit's:
      # the record pre-commit read in the index.
      if [[ "$MRG_REC_FROM_C" == "1" ]]; then MRG_REC_P2="$MRG_REC_C0"; else MRG_REC_P2="$(record_at "$P2")"; fi
      if [[ "$(record_verdict "$MRG_REC_P2")" != "ok" ]]; then
        printf 'VIOLATION %s  [SLH-RECORD-MALFORMED] .claude/status.json on the merged branch is not a well-formed status record, so what this merge closes or records cannot be read from it. Nothing falls back to the page readers; only /setlist:checkpoint writes this file.\n' "$SHORT"
        printf '          %s\n' "$SUBJ"
        VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
        continue
      fi
      if record_present_at "$P1"; then
        MRG_REC_P1="$(record_at "$P1")"
        if [[ "$(record_verdict "$MRG_REC_P1")" != "ok" ]]; then
          printf 'VIOLATION %s  [SLH-RECORD-MALFORMED] .claude/status.json on the trunk side of this merge is not a well-formed status record, so what was ALREADY closed or done cannot be established.\n' "$SHORT"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
          continue
        fi
      fi
      # The chore route from the record: a chore whose entry reads done on the
      # branch and did not on the trunk side. The trunk side having no record
      # yet reads as nothing-done-before, the same permissive direction the
      # page path takes with an unreadable prior STATUS, and for the same
      # reason: this is a report, and a fabricated violation trains the reader
      # to ignore real ones.
      RECORDED_CHORE=""
      MRG_DONE_P2="$(printf '%s' "$MRG_REC_P2" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: an empty done set cannot excuse a merge, only fail to excuse it
      MRG_DONE_P1=""
      [[ -n "$MRG_REC_P1" ]] && MRG_DONE_P1="$(printf '%s' "$MRG_REC_P1" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: as above, the empty direction suppresses the excuse
      while IFS= read -r CN; do
        [[ -n "$CN" ]] || continue
        if ! grep -qxF -- "$CN" <<< "$MRG_DONE_P1"; then
          RECORDED_CHORE="$CN"; break
        fi
      done <<< "$MRG_DONE_P2"
      # ...and, when the branch records none, the merge commit's own record
      # (spec 0157): the completion written while completing a refused merge
      # lands there, which is where pre-commit read it.
      if [[ -z "$RECORDED_CHORE" ]] && merge_completion_may_read_commit && record_present_at "$C"; then
        MRG_REC_C="$(record_at "$C")"
        if [[ "$(record_verdict "$MRG_REC_C")" == "ok" ]]; then
          MRG_DONE_C="$(printf '%s' "$MRG_REC_C" | jq -r "$SLH_RECORD_DONE_JQ" 2>/dev/null || true)" # fail-open-ok: an empty done set cannot excuse a merge, only fail to excuse it
          while IFS= read -r CN; do
            [[ -n "$CN" ]] || continue
            if ! grep -qxF -- "$CN" <<< "$MRG_DONE_P1"; then
              RECORDED_CHORE="$CN"; break
            fi
          done <<< "$MRG_DONE_C"
        fi
      fi
    else
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
      if ! grep -qE "^[-*+>[:space:]]*${CN}[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)" <<< "$PRIOR_STATUS"; then
        RECORDED_CHORE="$CN"; break
      fi
    done <<< "$CHORES_NOW"
    # The page path's half of spec 0157: the archive line added while completing
    # a refused merge is on the MERGE COMMIT, which is the text pre-commit read
    # in the index. Same two-parent bound, same trunk-side comparison.
    if [[ -z "$RECORDED_CHORE" ]] && merge_completion_may_read_commit; then
      CHORES_AT_C="$(printf '%s\n' "$STATUS_TEXT_C" | grep -oE "$CHORE_DONE_RE" 2>/dev/null | grep -oE 'CHORE-[0-9]+' || true)" # fail-open-ok: no archive line leaves this EMPTY, which cannot excuse a merge, only fail to excuse it
      while IFS= read -r CN; do
        [[ -n "$CN" ]] || continue
        if ! grep -qE "^[-*+>[:space:]]*${CN}[[:space:]]*:[[:space:]]*DONE([^A-Za-z]|$)" <<< "$PRIOR_STATUS"; then
          RECORDED_CHORE="$CN"; break
        fi
      done <<< "$CHORES_AT_C"
    fi
    fi

    if [[ -z "$SPECS_TOUCHED" ]]; then
      if [[ -n "$RECORDED_CHORE" ]]; then
        # Verifiable now, where it used to be unverifiable by construction. This
        # is the whole gain from giving the archive line a form: history can
        # answer the question rather than shrug at it.
        #
        # COUNTED ONCE, BY THE ONE PLACE THAT COUNTS (V19-F9). This arm used to
        # do `CLEAN=$((CLEAN + 1))` here, and this is the PER-PARENT loop: a
        # merge whose parents each record a chore incremented CLEAN once per
        # parent, and then the per-commit bucket at the bottom of the loop
        # incremented it again, so `clean` could exceed `audited` and the report
        # printed an impossible pair. No violation was ever missed, the decision
        # was right and the tally was wrong, but a shipped counter that can print
        # an impossible pair is a claim users read. The bucket below is the ONE
        # site that counts a commit, and it counts it once.
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

      # THE RECORD DECIDES (RP1). A spec file this branch touched must have an
      # entry in the branch's record: no entry is the pre-upgrade spec whose
      # close was attempted without checkpoint, and the way out is the one-line
      # fix the message names. The close facts are the record's tokens; the
      # prose Closing report is a human artifact this arm no longer parses on
      # the structured path.
      if [[ "$MRG_STRUCTURED" == "1" ]]; then
        # The record that answers for this spec: the branch's, or, when the
        # branch's says nothing and this is a two-parent merge, the merge
        # commit's own (spec 0157). The close facts written while completing a
        # refused merge are there, and that is the record pre-commit read.
        MRG_REC_EFF="$MRG_REC_P2"
        MRG_ST="$(printf '%s' "$MRG_REC_EFF" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_STATUS_JQ" 2>/dev/null || printf 'jq-failed')"
        MRG_FACTS_EFF="$(printf '%s' "$MRG_REC_EFF" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_FACTS_JQ" 2>/dev/null || printf 'jq-failed')"
        if [[ "$MRG_FACTS_EFF" != "ok" ]] && merge_completion_may_read_commit && record_present_at "$C"; then
          MRG_REC_C_SPEC="$(record_at "$C")"
          if [[ "$(record_verdict "$MRG_REC_C_SPEC")" == "ok" ]] \
             && [[ "$(printf '%s' "$MRG_REC_C_SPEC" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_FACTS_JQ" 2>/dev/null || printf 'jq-failed')" == "ok" ]]; then
            MRG_REC_EFF="$MRG_REC_C_SPEC"
            MRG_ST="$(printf '%s' "$MRG_REC_EFF" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_STATUS_JQ" 2>/dev/null || printf 'jq-failed')"
          fi
        fi
        if [[ "$MRG_ST" == "absent" || "$MRG_ST" == "jq-failed" || -z "$MRG_ST" ]]; then
          printf 'VIOLATION %s  [SLH-RECORD-NO-SPEC] spec %s reached %s with no entry in .claude/status.json. Run /setlist:checkpoint to record the spec, then close it through checkpoint; a spec cut before the record existed gets its entry backfilled at its next checkpoint touch.\n' "$SHORT" "$SPEC_NUM" "$TRUNK"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          SEEN_BAD=1
          continue
        fi
        MRG_FACTS="$(printf '%s' "$MRG_REC_EFF" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_FACTS_JQ" 2>/dev/null || printf 'jq-failed')"
        if [[ "$MRG_FACTS" != "ok" ]]; then
          printf 'VIOLATION %s  [SLH-RECORD-NO-CLOSE] spec %s reached %s without its close facts in .claude/status.json (status closed, qa_pass_1 ok, diagram updated or no-impact; the reader said: %s). /setlist:checkpoint writes these at the close.\n' "$SHORT" "$SPEC_NUM" "$TRUNK" "${MRG_FACTS:-nothing at all}"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          SEEN_BAD=1
          continue
        fi
        # THE DIAGRAM ARMS RUN HERE TOO (F1 of the 2.7.0 leg, fix round 1); the
        # linear arm above carries the full reasoning. The merge route reads the
        # merge commit C against its FIRST parent P1, the trunk side, because
        # that diff is what the merge BRINGS to the trunk.
        MRG_DIAG_TEXT="$(git -C "$INSTANCE" show "$P2:$SPEC_FILE" 2>/dev/null | awk "$TEMPLATE_FENCE_AWK" || true)" # fail-open-ok: as the linear arm
        MRG_DMISS="$(audit_diagram_tokens "$P1" "$C" "$MRG_DIAG_TEXT")$(audit_diagram_nodes "$P1" "$C" "$SPEC_NUM")"
        if [[ -n "$MRG_DMISS" ]]; then
          printf 'VIOLATION %s  spec %s reached %s without:%s\n' "$SHORT" "$SPEC_NUM" "$TRUNK" "$MRG_DMISS"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1)); SEEN_BAD=1
          continue
        fi
        # Compliant. Was it ALREADY closed on the trunk side? Then this merge
        # is not what closed it and it cannot authorise the code riding along
        # (the B6 laundering rule, read from the record).
        MRG_PRIOR_ST="absent"
        if [[ -n "$MRG_REC_P1" ]]; then
          MRG_PRIOR_ST="$(printf '%s' "$MRG_REC_P1" | jq -r --arg num "$SPEC_NUM" "$SLH_RECORD_STATUS_JQ" 2>/dev/null || printf 'absent')" # fail-open-ok: an unreadable prior record suppresses the already-closed excuse's suppression, i.e. it lets this merge count as the closer, the same permissive direction the page path takes
        fi
        if [[ "$MRG_PRIOR_ST" != "closed" ]]; then
          CLOSED_SOMETHING=1
          # T1 on the structured path: the branch's declared set against the
          # ownership file, on the branch tip's author email (see the page
          # path's note below; the same ADDED read, not the completion question).
          # The lite tier's cap on the structured merge route (edition v1.14,
          # P1): the tier is a claim about the spec, not about how it landed.
          if grep -q '^!lite-oversized$' <<< "$(git -C "$INSTANCE" show "$P2:$SPEC_FILE" 2>/dev/null | awk "$SLH_OWNS_AWK")"; then
            printf 'VIOLATION %s  [SLH-LITE-OVERSIZED] spec %s is declared Tier: lite and declares more than five files under Owns:. A lite spec is at most five files (Part 3 of the edition); the two honest exits are to drop the tier line (a full spec, judged exactly as before) or to split the work, both through /setlist:checkpoint. The tier is a claim about size, and a claim the close cannot honour is refused rather than reread.\n' "$SHORT" "$SPEC_NUM"
            printf '          %s\n' "$SUBJ"
            VIOLATIONS=$((VIOLATIONS + 1))
            SEEN_BAD=1
          fi
          MRG_OWNS="$(git -C "$INSTANCE" show "$P2:$SPEC_FILE" 2>/dev/null | awk "$SLH_OWNS_AWK" | grep -v '^!' || true)" # fail-open-ok: no declarations is the blockless close, never judged by file
          if [[ -n "$MRG_OWNS" ]] && ! codeowners_arm "$C" "$P2" "$MRG_OWNS"; then
            printf '          %s\n' "$SUBJ"
            SEEN_BAD=1
          fi
          if [[ -n "$MRG_OWNS" ]] && ! audit_owns_overlap "$C" "$P1" "$BASE" "$SPEC_NUM" "$MRG_OWNS"; then
            printf '          %s\n' "$SUBJ"
            SEEN_BAD=1
          fi
          # THE CLOSE REVIEW (spec 0175), at the merge that closes the spec, read from the
          # merge commit's own tree (audit_close_review's header says why).
          if ! audit_close_review "$C" "$(close_review_text_at "$C" "$SPEC_FILE")" "$SPEC_NUM" "$P1"; then
            printf '          %s\n' "$SUBJ"
            SEEN_BAD=1
          fi
        fi
        continue
      fi

      # fail-open-ok: an unreadable spec yields empty text, and every check
      # below is a grep that FAILS on empty, so the merge is reported as a
      # violation. Unreadable evidence counts against the merge, never for it.
      SPEC_TEXT="$(git -C "$INSTANCE" show "$P2:$SPEC_FILE" 2>/dev/null || true)"

      # A FENCED EXAMPLE IS NOT A CLOSING REPORT, in the backstop too. The close
      # gate has stripped fenced spans since leg 5's F7; this script never did,
      # so a spec quoting the shipped template satisfied every check below and
      # the audit reported it clean (v1.7 gate, adversarial review F9). Stripped once,
      # before all of them, exactly as setlist-hook-lib.sh does.
      #
      # NARROWED for the 1.1.0 adversarial review F6, and this copy is the one that
      # made the defect RETROACTIVE. The stripper is new here in 1.1.0, so an
      # instance upgrading from 1.0.9 found the audit condemning trunk history
      # that had merged legitimately, at which point pre-push refused the push
      # and the only documented escape switched off every other check too. A
      # block is a TEMPLATE QUOTE exactly when its own body carries a
      # Closing-report heading; a pasted verifier report never does.
      #
      # LOCKSTEP: byte-identical to setlist-hook-lib.sh, and
      # (2026-08 consolidation) hoisted to file scope with QA_PASS1_AWK above so
      # the linear close check can share the one definition instead of drifting
      # a second copy of it.
      SPEC_TEXT="$(printf '%s\n' "$SPEC_TEXT" | awk "$TEMPLATE_FENCE_AWK")"

      MISSING=""
      grep -qE $'^ {0,3}#{1,6}[ \t]+Closing report' <<< "$SPEC_TEXT" || MISSING="$MISSING no-closing-report"

      # THE VERDICT IS A PASTED BLOCK, NOT A WORD IN PROSE (B6, leg 5 F15).
      # This was `grep PASS|PARTIAL|FAIL` over the WHOLE spec, so "the browser
      # tests PASS on my machine but mobile was never run" satisfied it. The
      # close gate rejected exactly that text from 1.0.2; its backstop
      # accepted it, so the audit reported clean on input the gate refused,
      # which is the worst possible disagreement between two layers that are
      # supposed to cover each other. Both halves of that rule, the library's now, are
      # mirrored here rather than reinvented: extract the QA Pass 1 block
      # DISPLACED, NOT LEFT BESIDE. The field-marker extraction that used to
      # live here fed a regex over the prose between the "QA Pass 1 report" and
      # "QA Pass 2" markers. The verdict is a structure now, read straight out
      # of the spec text, so that extraction has no reader and is deleted rather
      # than kept warm. shellcheck is what noticed it was dead, which is the
      # argument for the lint gate being a gate.
      # LOCKSTEP WITH templates/git-hooks/setlist-hook-lib.sh (backlog item 35). That file
      # carries this same program, byte for byte, and the suite asserts the
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
      # refused, which is the half B6 exists for; and a tally (a count of passes)
      # is deliberately never read as a verdict, because a pattern wide enough to
      # admit one is wide enough to admit a sentence containing one.
      [[ "$(printf '%s\n' "$SPEC_TEXT" | awk "$QA_PASS1_AWK")" == "ok" ]] \
        || MISSING="$MISSING no-qa-verdict"

      # The row, on the branch or on the merge commit itself (spec 0157): a close
      # completed on the trunk side after pre-merge-commit refused it flips the
      # row in the commit pre-commit accepted, and both layers now read it there.
      if ! row_is_closed "$STATUS_TEXT" "$SPEC_NUM" \
         && ! { merge_completion_may_read_commit && row_is_closed "$STATUS_TEXT_C" "$SPEC_NUM"; }; then
        MISSING="$MISSING no-CLOSED-row"
      fi

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
      # list bullet, FIRST match wins (KL1, ruled 2026-08-29), the ANSWER
      # anchored to the start of the value (F6-2026), and the template
      # placeholder does not count as an answer.
      DIAG_LINE="$(printf '%s\n' "$SPEC_TEXT" | awk "$SLH_LIVE_TEXT_AWK" | grep -E '^[-*+>[:space:]]*Architecture diagram:' | awk 'NR == 1')" # fail-open-ok: no line yields empty, which the test below reads as the missing field it is
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
      elif ! grep -qE '^(updated in this commit|no impact)([^A-Za-z]|$)' <<< "$(printf '%s' "$DIAG_ANSWER" | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//')" \
           && ! { MRG_ARMED=0; slh_diagram_switch_on "$INSTANCE" "$P1" && MRG_ARMED=1; [[ "$MRG_ARMED" == "1" ]] && grep -qE '^updated[[:space:]]*\(' <<< "$(printf '%s' "$DIAG_ANSWER" | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//')"; }; then
        MISSING="$MISSING diagram-unanswered"
      fi
      # THE FIELD AGAINST THE DIFF, AND THE NODES AGAINST THE TREE (v1.15). The
      # merge route reads the merge commit C against its FIRST parent P1, which
      # is the trunk side: the diff is what the merge BRINGS to the trunk.
      MISSING="$MISSING$(audit_diagram_tokens "$P1" "$C" "$SPEC_TEXT")"
      MISSING="$MISSING$(audit_diagram_nodes "$P1" "$C" "$SPEC_NUM")"

      if [[ -n "$MISSING" ]]; then
        printf 'VIOLATION %s  spec %s reached %s without:%s\n' "$SHORT" "$SPEC_NUM" "$TRUNK" "$MISSING"
        printf '          %s\n' "$SUBJ"
        VIOLATIONS=$((VIOLATIONS + 1))
        SEEN_BAD=1
      elif ! row_is_closed "$PRIOR_STATUS" "$SPEC_NUM"; then
        # Compliant AND not already closed on the trunk: this merge is what
        # closed it, so it can authorise the code riding with it.
        CLOSED_SOMETHING=1
        # T1: a declaring close landing by merge is judged against the
        # ownership file too, on the branch tip's author email; the declared
        # set is the spec's Owns: lines as the branch carries them (a
        # malformed declaration was already refused at the merge hook and
        # declares nothing here). An ADDED read of the merge arm, not a change
        # to the completion question F10-2026 names.
        # The lite tier's cap on the merge route too (edition v1.14, P1): the
        # tier is a claim about the spec, not about how it landed.
        if grep -q '^!lite-oversized$' <<< "$(printf '%s\n' "$SPEC_TEXT" | awk "$SLH_OWNS_AWK")"; then
          printf 'VIOLATION %s  [SLH-LITE-OVERSIZED] spec %s is declared Tier: lite and declares more than five files under Owns:. A lite spec is at most five files (Part 3 of the edition); the two honest exits are to drop the tier line (a full spec, judged exactly as before) or to split the work, both through /setlist:checkpoint. The tier is a claim about size, and a claim the close cannot honour is refused rather than reread.\n' "$SHORT" "$SPEC_NUM"
          printf '          %s\n' "$SUBJ"
          VIOLATIONS=$((VIOLATIONS + 1))
          SEEN_BAD=1
        fi
        MRG_OWNS="$(printf '%s\n' "$SPEC_TEXT" | awk "$SLH_OWNS_AWK" | grep -v '^!' || true)" # fail-open-ok: no declarations is the blockless close, which this arm never judged by file
        if [[ -n "$MRG_OWNS" ]] && ! codeowners_arm "$C" "$P2" "$MRG_OWNS"; then
          printf '          %s\n' "$SUBJ"
          SEEN_BAD=1
        fi
        if [[ -n "$MRG_OWNS" ]] && ! audit_owns_overlap "$C" "$P1" "$BASE" "$SPEC_NUM" "$MRG_OWNS"; then
          printf '          %s\n' "$SUBJ"
          SEEN_BAD=1
        fi
        # THE CLOSE REVIEW (spec 0175), at the merge that closes the spec, read from the
        # merge commit's own tree (audit_close_review's header says why).
        if ! audit_close_review "$C" "$(close_review_text_at "$C" "$SPEC_FILE")" "$SPEC_NUM" "$P1"; then
          printf '          %s\n' "$SUBJ"
          SEEN_BAD=1
        fi
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
    # EACH NAME WHOLE (spec 0169, fix round 1, E-k): git's -z output was turned
    # back into newlines before it was read, so a file name holding a newline
    # was judged and printed as fragments. NUL-delimited, as touches_role reads.
    while IFS= read -r -d '' nf; do
      [[ -n "$nf" ]] || continue
      touches_role_file "$nf" || continue
      IN_A_PARENT=0
      for PP in $PARENTS; do
        git -C "$INSTANCE" cat-file -e "$PP:$nf" 2>/dev/null && { IN_A_PARENT=1; break; }
      done
      [[ "$IN_A_PARENT" -eq 0 ]] && INJECTED="$INJECTED $(slh_bound name "$nf")"
    done < <(git -C "$INSTANCE" diff -z --name-only --diff-filter=A "$P1" "$C" 2>/dev/null)
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
