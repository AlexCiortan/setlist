#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Setlist Stop hook: refuses to END A TURN that leaves a spec or specs/STATUS.md
# changed and unstaged in the working tree (2.6.0, spec 0132 cluster H; the
# owner's ruling 5 on the 2.6.0 strategy; external review minor 2). Stamped
# into the instance beside the two PreToolUse hooks and the SessionStart
# re-grounding hook; wired on the Stop event, which takes no matcher.
#
# WHY A STOP HOOK, AND WHY THIS RULE. The record (a spec's Status line, its
# Closing report, the inventory row in specs/STATUS.md) and the page that reads
# it are kept in agreement by ONE writer at a time (Part 3, RP1). A turn that
# ends with that record edited and not staged is the state in which the two
# disagree and nobody is holding the pen: the next session re-grounds on a
# STATUS.md the working tree contradicts. The Bash gates cannot see this (they
# read commands, not the tree between them), and the git hooks cannot either
# (nothing was committed). The end of a turn is the one moment the harness
# asks, and the reason it renders here is READ by the model. Measured live on
# 2026-09-07, Claude Code 2.1.259, in a scratch instance with specs/STATUS.md
# edited and unstaged: the first Stop payload (stop_hook_active false) drew
# this hook's block, the session read the reason, ran `git add
# specs/STATUS.md` and answered; the second Stop payload (stop_hook_active
# true) drew this hook's allow and the turn ended, three turns in all. That
# is more than the PreToolUse gates can say for an allow with a reason (RP5).
#
# WHAT IT DOES NOT DO. It does not commit, stage or restore anything. It does
# not read the spec's content. It refuses ONCE per end of turn: the harness
# marks the continuation it grants on this hook's word (`stop_hook_active`),
# and on that continuation this hook allows, so a change the session cannot
# stage (a permission it lacks, a file it did not write) is a nudge that is
# seen, never a lock. A session killed from outside fires no Stop at all, which
# the public list names as this hook's boundary.
#
# FAIL-CLOSED WHERE IT CAN ASK, OPEN WHERE IT CANNOT. A tree git cannot read
# is refused by name (SP-NO-GIT): a check that could not run has not passed,
# and the reason says so. jq is NOT load-bearing here: the payload's one field
# is read by a substring test and the verdict is written by a literal printf,
# so a broken jq changes nothing about the decision; it is REPORTED beside a
# refusal (SP-JQ-BROKEN) so the operator learns it from the layer that can
# still speak. A repository with no .claude/sdd.json is not an instance and
# is none of this hook's business.
#
# THE CONTRACT (the Stop event's, measured):
#   stdout  {"decision":"block","reason":<text>,"setlistAdvisory":{...}}  to refuse
#           nothing                                                        to allow
#   exit    0 either way (a nonzero exit is an error the harness reports, not a verdict)
#   setlistAdvisory  {gate: "stop", verdict: "block", code, reason}, the same
#                    field the PreToolUse hooks emit, so one reader reads them all
set -u

# THE CODE IS EXTRACTED BY THE SHELL (KL11's rule, from birth): the last
# well-formed bracketed token of the reason.

# json_str <text> -> a JSON string literal, by the shell (no jq on this path).
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

refuse() { # refuse <code> <reason>  -> the block, on stdout, exit 0
  # The toolchain report rides AHEAD of the refusal so the refusal's own code
  # is the last bracket a reader sees; the MACHINE-READABLE code is passed in
  # by the caller (spec 0164, fix round 2, F19 of the 2.10.0 leg), because
  # scanning it back out of the rendered text read a bracketed token in a spec
  # FILENAME as the code: a spec whose name carried a bracketed token published
  # that token as the advisory code beside the refusal, for a benign name as
  # readily as a crafted one. The refusal itself was always right; only its
  # label was the filename. (No example is spelled here with its brackets: the
  # suite reads this file for the code family, and an example would read as a
  # fifth code.)
  local code="$1" reason="${JQ_NOTE}$2"
  ADV_CODE="$code"
  printf '{"decision":"block","reason":%s,"setlistAdvisory":{"gate":"stop","verdict":"block","code":%s,"reason":%s}}\n' \
    "$(json_str "setlist stop hook: $reason")" "$(json_str "$ADV_CODE")" "$(json_str "$reason")"
  # fail-open-ok: this exit 0 delivers a BLOCK, not an allow: the harness reads
  # the JSON's decision, and a nonzero exit would be an error it reports rather
  # than a verdict it renders.
  exit 0
}

IFS= read -r -d '' INPUT || true

# THE CONTINUATION THIS HOOK ASKED FOR IS ALLOWED. The harness sets
# stop_hook_active when the turn is continuing because a Stop hook blocked; a
# second block on the same grounds would loop until the harness's own cap.
# Read by substring on the raw payload, so jq is not on this path.
case "$INPUT" in
  # Annotated at F6 of the 2.7.0 leg, which found this file absent from the
  # disposition audit entirely and these exits therefore never read.
  # fail-open-ok: the harness has already marked this turn a continuation of a
  # stop this hook blocked, so blocking again is the loop rather than the gate.
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# JQ'S LINE ENDING (spec 0179). A native jq on Windows ends every line in CRLF,
# and Git Bash drops a CR only at the very end of a command substitution, so
# every line of a jq list but the last kept one ("src\r") and each verdict read
# from a list failed open. jq -b (jq 1.7 and later) writes LF there. The probe
# reads a two-line list, so a jq that ends lines in CR is found on any platform;
# one that also refuses -b fails this file's output probe and is refused by name.
case "$(printf '["x","y"]' | command jq -r '.[]' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; } ;; esac
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJ" ]]; then
  # The payload's cwd, read by jq when jq works and by a substring when it does
  # not; an unreadable cwd falls back to the working directory this hook runs in.
  PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [[ -n "$PROJ" ]] || PROJ="$PWD"
fi
# Not an instance: nothing here is this hook's business. The same guard every
# stamped hook opens with, and the boundary it draws is its own documented
# limitation. Annotated at F6 of the 2.7.0 leg.
# fail-open-ok: no sdd.json on the checked-out branch means this is not a Setlist
# instance, and a core.hooksPath set in one repository must not govern unrelated
# work.
[[ -f "$PROJ/.claude/sdd.json" ]] || exit 0

# NO REPOSITORY YET IS NOT A BROKEN ONE (DE11, spec 0150). An ENTRY of any type
# counts: a .git file (a linked worktree) and a dangling .git symlink reach the
# read below and are judged or refused as before. Only a root with no .git at
# all is silent, and that includes an instance stamped below an enclosing
# repository's top (the stamp's skip-subdir, reported NOT ARMED by the stamp
# itself; the owner's ruling E-1 of 2026-09-17).
# fail-open-ok: no .git at the root is the state /setlist:new leaves by design
# (the stamp's skip-norepo) until /scaffold creates the repository, so there is
# no committed record yet for a turn to leave disagreeing.
[[ -e "$PROJ/.git" || -L "$PROJ/.git" ]] || exit 0

JQ_NOTE=""
if [[ "$(printf '{"probe":"x"}' | jq -r '.probe' 2>/dev/null)" != "x" ]]; then
  JQ_NOTE="[SP-JQ-BROKEN]: jq is broken here; run jq --version. "
fi

# EVERY NAME AND PATH IS BOUNDED, SO THE 480-CHARACTER BOUND HOLDS MECHANICALLY
# (spec 0164, fix round 2, F18 and F24 of the 2.10.0 leg; spec 0171, L2 F21 and
# sweep I16 of 0169). The bound is a claim the changelog makes about EVERY
# rendered refusal, the note on a machine without a working jq included. A file
# name and a root path are the repository's and the machine's text, and this
# reason is read by the model, so each is printed through the path set every
# Setlist message uses (A-Z a-z 0-9 . _ / space : + = @ -, every other byte a ?,
# the edit said once per reason), quoted, its middle elided past 36 characters,
# and a list is one name plus a count, never re-split (L2 F18: a name carrying a
# comma-space read as two files). 36 is the budget's own arithmetic: the worst
# reason (STATUS.md, a spec and an untracked spec, jq broken) is 249 fixed
# characters of text plus the 19 of the prefix, the 52 of the jq note and the 48
# of the edit note, and two names of at most 38 quoted characters each with a
# count of at most 14 ("and 999+ more"), 472 in all, which the suite renders.
bound_paths() { # bound_paths <count> <name> -> the name bounded, quoted, plus how many more
  local n="$1" v="$2" s LC_ALL=C
  s="${v//[^A-Za-z0-9._\/ :+=@-]/?}"
  if [[ "${#s}" -gt 36 ]]; then s="${s:0:16}...${s: -17}"; fi
  printf '"%s"' "$s"
  if [[ "$n" -gt 1000 ]]; then printf ' and 999+ more'
  elif [[ "$n" -gt 1 ]]; then printf ' and %d more' "$((n - 1))"; fi
}
# The one clause that says a value was edited, appended once per reason when
# any bounded value carries a ? (inline at each reason: no second function).
EDITED=' (characters outside a path set replaced with ?)'

# THE READ. git is asked directly for the working tree's state under specs/;
# a git that cannot answer is a refusal by name, never a pass on silence.
if ! git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # THE REMEDY NAMES NO PATH (spec 0171, L2 F21): the path is bounded, and an
  # elided path in a remedy is a command that cannot run, so the fix leads whole
  # and the path follows it.
  PROJ_R="$(bound_paths 1 "$PROJ")"; E=""; case "$PROJ_R" in *'?'*) E="$EDITED" ;; esac
  refuse SP-NO-GIT "[SP-NO-GIT]: run git status in the project root to see the failure, repair it, then end the turn. git could not read $PROJ_R as a work tree (git missing from PATH, a corrupt .git, or not the instance root), so the spec record cannot be checked.$E"
fi
# THE REPOSITORY GIT READ MUST BE THIS ONE (DE19, spec 0159; F6 of the 2.9.0
# leg). Below a corrupt or empty .git, git walks past it and answers for an
# ENCLOSING repository, whose specs/ may ignore the instance entirely, so the
# turn ended in silence or was refused over the parent's paths. The top git
# reports is compared with the root as a DIRECTORY (the same device and inode,
# the shell's -ef), never as a string: git answers with the stored, physical
# spelling, so a project reached through a symlink, or typed in another case on
# a filesystem that folds case, is the same directory and must still be judged
# (the second measured by this spec's cold review, round 3). A .git entry exists
# here (the DE11 guard above), so a different directory is a broken repository.
GIT_TOP="$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null)" || GIT_TOP=""
if [[ -z "$GIT_TOP" ]] || ! [[ "$GIT_TOP" -ef "$PROJ" ]]; then
  PROJ_R="$(bound_paths 1 "$PROJ")"; TOP_R="no repository"; [[ -z "$GIT_TOP" ]] || TOP_R="$(bound_paths 1 "$GIT_TOP")"
  E=""; case "$PROJ_R$TOP_R" in *'?'*) E="$EDITED" ;; esac
  refuse SP-NO-GIT "[SP-NO-GIT]: run git status in the project root, repair its .git, then end the turn. git read $TOP_R in place of $PROJ_R, so the spec record cannot be checked.$E"
fi
# THE PORCELAIN IS READ WITH -z (spec 0171, L2 F14 of the 2.10.0 second leg):
# NUL-terminated records that git never quotes, so no delimiter is parsed out
# of a name. The line form quoted a path carrying a space and wrote a rename as
# "old -> new", and this loop took the text after " -> " BEFORE stripping the
# quotes, so an untracked spec whose name carried " -> " read as a path ending
# in a quote, failed the Markdown test and ended the turn in silence. A rename or
# a copy is followed by one more record, its old path, which is consumed here.
# (The -z form is also what spec 0164's F17 wanted of core.quotePath=false: a
# name is read as the bytes it is.) git's exit status rides a last record of
# this hook's own, which no porcelain record can spell (an XY code never starts
# with #), because a NUL cannot be kept in a variable to be read after the fact.
#
# UNSTAGED means the working tree differs from the index: porcelain's second
# column is not a space (modified, deleted, type-changed), or the entry is
# untracked (??). A change that is STAGED is the session's deliberate act and
# is allowed to stand at the end of a turn; the record it will become is in the
# index, and the commit is the next thing the protocol asks for.
#
# AN UNTRACKED FILE COUNTS ONLY WHEN IT IS MARKDOWN (2.9.0; F8 of that release's
# leg, spec 0154). A new spec is untracked until it is staged, so an untracked
# .md file is the spec record; a .DS_Store, an editor swap file or a merge's .orig
# is not, and refusing every turn on one offered two remedies that fail on a file
# git has never tracked. Such a file gets its own remedy line below.
UNSTAGED_STATUS=""; N_SPECS=0; FIRST_SPEC=""; N_UNTRACKED=0; FIRST_UNTRACKED=""; STATUS_RC=""
while IFS= read -r -d '' rec; do
  case "$rec" in '#rc='*) STATUS_RC="${rec#\#rc=}"; continue ;; esac
  [[ -n "$rec" ]] || continue
  x="${rec:0:1}"; y="${rec:1:1}"; path="${rec:3}"
  case "$x" in R|C) IFS= read -r -d '' _ || true ;; esac
  if [[ "$x$y" == "??" ]]; then
    case "$path" in *.md) N_UNTRACKED=$((N_UNTRACKED + 1)); [[ -n "$FIRST_UNTRACKED" ]] || FIRST_UNTRACKED="$path" ;; *) continue ;; esac
  fi
  if [[ "$x$y" == "??" || "$y" != " " ]]; then
    case "$path" in
      specs/STATUS.md) UNSTAGED_STATUS="$path" ;;
      *) N_SPECS=$((N_SPECS + 1)); [[ -n "$FIRST_SPEC" ]] || FIRST_SPEC="$path" ;;
    esac
  fi
done < <(git -C "$PROJ" status --porcelain=v1 -z --untracked-files=all -- specs/ 2>/dev/null; printf '#rc=%s\0' "$?")
if [[ "$STATUS_RC" != "0" ]]; then
  PROJ_R="$(bound_paths 1 "$PROJ")"; E=""; case "$PROJ_R" in *'?'*) E="$EDITED" ;; esac
  refuse SP-NO-GIT "[SP-NO-GIT]: run git status -- specs/ in the project root to see the failure, repair it, then end the turn. It failed in $PROJ_R, so the spec record cannot be checked.$E"
fi

SPECS_R=""; [[ "$N_SPECS" -eq 0 ]] || SPECS_R="$(bound_paths "$N_SPECS" "$FIRST_SPEC")"
UNTRACKED_NOTE=""; UNTRACKED_R=""
if [[ "$N_UNTRACKED" -gt 0 ]]; then
  # The path is named ONCE; the remedy takes the directory, which git always
  # accepts and which no filename can make unrunnable.
  UNTRACKED_R="$(bound_paths "$N_UNTRACKED" "$FIRST_UNTRACKED")"
  UNTRACKED_NOTE=" Untracked: $UNTRACKED_R; git add specs/ or remove it."
fi
EDIT_NOTE=""; case "$SPECS_R$UNTRACKED_R" in *'?'*) EDIT_NOTE="$EDITED" ;; esac
if [[ -n "$UNSTAGED_STATUS" && "$N_SPECS" -gt 0 ]]; then
  refuse SP-UNSTAGED-STATUS "[SP-UNSTAGED-STATUS]: stage specs/ (git add specs/) and commit it, or git restore what was not meant, then end the turn. STATUS.md and $SPECS_R are unstaged; the next session reads the committed page.$UNTRACKED_NOTE$EDIT_NOTE Refuses once."
elif [[ -n "$UNSTAGED_STATUS" ]]; then
  refuse SP-UNSTAGED-STATUS "[SP-UNSTAGED-STATUS]: stage specs/STATUS.md (git add specs/STATUS.md) and commit it with its work, or git restore it if not meant, then end the turn. It is unstaged, and the next session re-grounds on the committed page. Refuses once."
elif [[ "$N_SPECS" -gt 0 ]]; then
  refuse SP-UNSTAGED-SPEC "[SP-UNSTAGED-SPEC]: stage specs/ (git add specs/) and commit it, or git restore what was not meant, then end the turn. The spec record ($SPECS_R) is unstaged; the next session reads the committed page.$UNTRACKED_NOTE$EDIT_NOTE Refuses once."
fi

# fail-open-ok: every file under specs/ is committed or staged, which is the
# state this hook exists to reach; silence is the allow.
exit 0
