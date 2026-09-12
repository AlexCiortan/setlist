#!/usr/bin/env bash
# forge-check.sh - the forge check (KL5, spec 0132, from the ratified design
# design-forge-check-kl5-2026-09-06.md). Stamped to .claude/hooks/forge-check.sh
# beside the trunk audit; run by a pull request's CI as a REQUIRED status check.
#
# Usage:
#   forge-check.sh --base <ref-or-sha> --head <sha> [--instance <dir>]
#                  [--forge github|none] [--repo <owner/name>] [--author <login>]
#                  [--api <url>] [--forge-query <command>]
# stdout: exactly ONE token, the last line
# stderr: every refusal in the hooks' register, codes bracketed
# exit:   0 on PASS, 1 on any refusal, 2 when the check could not run at all
#
# THE FACT THAT DECIDES EVERYTHING (design section 2): a pull request has no
# trunk history. It has a base, a head, and a merge the forge has not made. The
# trunk audit reads history and the close verification reads an index, so this
# check MAKES the merge it audits, in a scratch clone of the checkout, and asks
# the same questions the git hooks ask of it, in this order, cheapest first:
#
#   1. toolchain and checkout (a shallow clone has no history to read)
#   2. the instance (.claude/sdd.json at the head; the base is the trunk)
#   3. the scratch merge (--no-ff --no-commit, under a fixed identity)
#   4. the close verification over the merge index (pre-merge-commit's predicate)
#   5. the attestation walk over the range (pre-push's predicate), with custody
#      C's arm answered HERE rather than deferred
#   6. the content scan over the range (pre-push's predicate)
#   7. the third gate tier (`push`) in the merged worktree
#   8. the merge committed, and the trunk audit over it (pre-push's predicate)
#   9. the forge questions (the trunk's protection read from BOTH endpoints,
#      rulesets and classic protection, as the union the forge enforces;
#      the merge method from the repository's flag AND the ruleset's
#      allowed_merge_methods; and the CODEOWNERS bridge), asked with the
#      job's own identity (ratification amendments 3 and 4, 2026-09-07)
#  10. PASS, once, on stdout, naming the declared custody
#
# IT READS THE CHECKOUT'S OWN STAMPED BYTES, measured against how pre-push
# resolves the audit today (templates/git-hooks/pre-push, the AUDIT and LIB
# loops): $CLAUDE_PLUGIN_ROOT/scripts/trunk-audit.sh, else the stamped
# .claude/hooks/trunk-audit.sh; the library beside the hooks in .githooks/. On a
# runner without the plugin, which is what CI is, that is exactly what pre-push
# runs, so this check verifies what pre-push verifies and nothing more. Nothing
# is fetched: a second copy of the mechanism is the A9 shape, and a network
# fetch is a thing a required check fails on. The suite pins this file's
# resolution to pre-push's over the same tree.
#
# THERE IS NO ESCAPE. SETLIST_SKIP_HOOKS and SETLIST_SKIP_TRUNK_AUDIT are not
# read. A workflow that wants to skip the check edits the workflow, which the
# stamped CODEOWNERS makes a reviewed change. Nothing on stderr names an escape.
#
# NEVER A PASS ON ABSENCE (design section 6). A forge that does not answer
# refuses under custody C; a check that died prints nothing, which the workflow
# refuses by construction; the one "pass on nothing" is a pull request whose
# base is not the recorded trunk, and that is a statement that the predicate has
# no subject, said out loud.
#
# --forge-query <command> is the SUITE's seam and nothing else's: it replaces
# the curl the check would run with a command that is handed the API path and
# prints the HTTP status on its first line and the body after it. The stamped
# workflow never passes it; a workflow that does is a reviewed edit under the
# same CODEOWNERS that governs skipping the check outright, so it is not a
# second escape, it is the same one, and it is named here rather than hidden.

set -u

FC_BASE=""; FC_HEAD=""; FC_INSTANCE=""; FC_FORGE="none"; FC_REPO=""; FC_AUTHOR=""
FC_API="https://api.github.com"; FC_QUERY_CMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)        FC_BASE="${2:-}"; shift 2 || { printf 'forge-check.sh: --base needs a value\n' >&2; exit 2; } ;;
    --head)        FC_HEAD="${2:-}"; shift 2 || { printf 'forge-check.sh: --head needs a value\n' >&2; exit 2; } ;;
    --instance)    FC_INSTANCE="${2:-}"; shift 2 || { printf 'forge-check.sh: --instance needs a value\n' >&2; exit 2; } ;;
    --forge)       FC_FORGE="${2:-}"; shift 2 || { printf 'forge-check.sh: --forge needs a value\n' >&2; exit 2; } ;;
    --repo)        FC_REPO="${2:-}"; shift 2 || { printf 'forge-check.sh: --repo needs a value\n' >&2; exit 2; } ;;
    --author)      FC_AUTHOR="${2:-}"; shift 2 || { printf 'forge-check.sh: --author needs a value\n' >&2; exit 2; } ;;
    --api)         FC_API="${2:-}"; shift 2 || { printf 'forge-check.sh: --api needs a value\n' >&2; exit 2; } ;;
    --forge-query) FC_QUERY_CMD="${2:-}"; shift 2 || { printf 'forge-check.sh: --forge-query needs a value\n' >&2; exit 2; } ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *) printf 'forge-check.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n "$FC_BASE" && -n "$FC_HEAD" ]] || { printf 'forge-check.sh: --base and --head are required\n' >&2; exit 2; }
case "$FC_FORGE" in github|none) ;; *) printf 'forge-check.sh: --forge must be github or none\n' >&2; exit 2 ;; esac

# --- the two exits that are not verdicts ------------------------------------
#
# could_not_run: exit 2, NOTHING on stdout. A caller that reads one token reads
# none and refuses; the reason is on stderr. This is the toolchain's and the
# checkout's exit, never a verdict about the pull request.
could_not_run() { printf 'setlist forge check: could not run: %s\n' "$1" >&2; fc_cleanup; exit 2; }

FC_TMP=""
fc_cleanup() { [[ -n "$FC_TMP" ]] && rm -rf "$FC_TMP"; FC_TMP=""; return 0; }

# refuse: one token on stdout, exit 1, after every reason has been printed.
# The custody verifier runs inside the library's command substitution (a
# subshell), so the token it chooses travels through a FILE in the scratch
# directory rather than a variable: fc_set_token writes it, fc_token reads it.
fc_set_token() { [[ -n "$FC_TMP" ]] && printf '%s' "$1" > "$FC_TMP/token"; return 0; }
fc_token() { cat "$FC_TMP/token" 2>/dev/null; return 0; } # fail-open-ok: no token file means the caller's default token, which is the step's own refusal
fc_clear_token() { rm -f "$FC_TMP/token" 2>/dev/null; return 0; }
refuse() { # refuse <token>
  printf '%s\n' "$1"
  fc_cleanup
  exit 1
}
# The code is passed BRACKETED, as it prints, so the leg trigger's identifier
# extraction (bracketed codes in the mechanism files) sees every code this check
# can emit where it is emitted.
fc_say() { printf 'setlist forge check %s: %s\n' "$1" "$2" >&2; }
fc_report() { printf 'setlist forge check report %s: %s\n' "$1" "$2" >&2; }

REPO="${FC_INSTANCE:-$(git rev-parse --show-toplevel 2>/dev/null || printf '.')}" # fail-open-ok: outside a repository this yields ".", which the git-dir probe below turns into "could not run" (exit 2), never a verdict
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || could_not_run "the instance directory does not exist: ${FC_INSTANCE:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- resolution, the same two candidates pre-push tries, in the same order ---
AUDIT=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/scripts/trunk-audit.sh" \
  "$REPO/.claude/hooks/trunk-audit.sh" \
  "$HERE/trunk-audit.sh" ; do
  [[ -n "$cand" && -f "$cand" ]] && { AUDIT="$cand"; break; }
done
[[ -n "$AUDIT" ]] || could_not_run "cannot find trunk-audit.sh (looked in CLAUDE_PLUGIN_ROOT/scripts/, $REPO/.claude/hooks/ and beside this script). A check that cannot find its own tool has not run."
LIB=""
for cand in \
  "$REPO/.githooks/setlist-hook-lib.sh" \
  "${CLAUDE_PLUGIN_ROOT:-}/templates/git-hooks/setlist-hook-lib.sh" \
  "$HERE/../templates/git-hooks/setlist-hook-lib.sh" ; do
  [[ -n "$cand" && -f "$cand" ]] && { LIB="$cand"; break; }
done
[[ -n "$LIB" ]] || could_not_run "cannot find setlist-hook-lib.sh (looked in $REPO/.githooks/ and the plugin tree). Refusing rather than reading the predicates a second way."
# shellcheck source=/dev/null
. "$LIB"

# --- 1. toolchain and checkout ----------------------------------------------
slh_require_toolchain || could_not_run "the toolchain probe refused (see above); every predicate below needs it"
# An ABSENT jq is named here, before the first read of .claude/sdd.json below.
# The library's probe covers a jq that is present and broken; its readers name an
# absent one (SLH-NO-JQ) only when they are reached, and this check reads the
# config with jq directly first, so without this line a runner with no jq
# refused under the config's code and blamed a healthy file (the 2.6.0 leg's F15).
command -v jq >/dev/null 2>&1 || could_not_run "jq is not installed on this runner, and every read of .claude/sdd.json needs it (the hooks refuse the same absence as SLH-NO-JQ); install jq on the runner. A check that cannot read its configuration has not run."
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || could_not_run "$REPO is not a git repository"
if [[ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  fc_say "[FC-SHALLOW-CHECKOUT]" "the checkout has no history (a shallow clone), so the audit would read nothing; set fetch-depth: 0 on the checkout step. A check that read nothing has not passed."
  refuse SHALLOW-CHECKOUT
fi

# The head must be a commit the checkout can see.
HEAD_SHA="$(git -C "$REPO" rev-parse --verify --quiet "${FC_HEAD}^{commit}" 2>/dev/null)" \
  || could_not_run "the head $FC_HEAD does not resolve to a commit in $REPO"
# --- 2. the instance --------------------------------------------------------
#
# WHOSE CONFIG, AND HOW THE TRUNK IS COMPARED (design amendment 6, 2026-09-08,
# the 2.6.0 leg's F1). The first cut read the recorded trunk from the HEAD's
# config, reduced it with two textual strips and string-compared it with the
# base name; a mismatch was the file's one pass-on-nothing branch. So a trunk
# recorded as origin/main (a spelling the git hooks accept and enforce), a case
# or whitespace variant, and a head that rewrote the trunk value in its own
# commit all printed PASS having evaluated nothing. Three rules now, none of
# them a new identifier:
#   (a) the trunk is read from the BASE's config, the trunk's own tip, and from
#       the head's only when the base carries none; a pull request cannot
#       redirect the check by editing the file it is judged under;
#   (b) the recorded trunk and the base are both resolved THROUGH GIT, in the
#       order pre-push's checkout carries them (the remote's branch, then a
#       local branch, then the name as given), and compared as the refs git
#       returns; a recorded trunk git cannot resolve, or one that differs from
#       the base only in case, REFUSES under the library's own
#       SLH-TRUNK-NOT-A-BRANCH and never passes: an unresolvable trunk is
#       absence, and this file's rule is never a pass on absence;
#   (c) a head whose recorded trunk differs from the base's is refused under
#       FC-NOT-AN-INSTANCE, the row that already refuses a head with no config.
# The pass-on-nothing branch survives for exactly one case: a base both configs
# agree is not the trunk (a pull request into some other branch).
BASE_NAME=""; BASE_SHA=""
case "$FC_BASE" in
  *[!0-9a-f]*|"") BASE_NAME="${FC_BASE#refs/heads/}"; BASE_NAME="${BASE_NAME#refs/remotes/origin/}"; BASE_NAME="${BASE_NAME#origin/}" ;;
esac
if ! git -C "$REPO" cat-file -e "$HEAD_SHA:.claude/sdd.json" 2>/dev/null; then
  fc_say "[FC-NOT-AN-INSTANCE]" "the head carries no .claude/sdd.json, so this is not a Setlist instance at this commit and the check has nothing it can read; a pull request that REMOVES or REDIRECTS the instance's config is refused rather than waved through."
  refuse NOT-AN-INSTANCE
fi

# The base, resolved FIRST: its config is the one the trunk is read from. A
# name is looked up as the remote's branch first, because a CI checkout carries
# the trunk as origin/<name> and rarely as a local branch. A base the checkout
# cannot see is "could not run": there is no config to read the trunk from and
# no commit to merge onto.
case "$FC_BASE" in
  *[!0-9a-f]*|"")
    for cand in "refs/remotes/origin/$BASE_NAME" "refs/heads/$BASE_NAME" "$FC_BASE"; do
      BASE_SHA="$(git -C "$REPO" rev-parse --verify --quiet "${cand}^{commit}" 2>/dev/null)" && break
      BASE_SHA=""
    done
    ;;
  *)
    BASE_SHA="$(git -C "$REPO" rev-parse --verify --quiet "${FC_BASE}^{commit}" 2>/dev/null)" || BASE_SHA=""
    ;;
esac
[[ -n "$BASE_SHA" ]] || could_not_run "the base $FC_BASE does not resolve to a commit in $REPO (tried the remote's branch, a local branch, and the value itself)"

# Two helpers (the leg trigger reads them as entry points; the fix round that
# added them re-attested under RP22 rather than flatten them).
fc_recorded_trunk() { # fc_recorded_trunk <sha> -> the trunk string that commit's config records ("main" when the key is absent; "" when the file or the value is unusable)
  git -C "$REPO" show "$1:.claude/sdd.json" 2>/dev/null | jq -r 'if (.trunk == null) then "main" elif ((.trunk | type) == "string") then .trunk else "" end' 2>/dev/null
}
fc_resolve_ref() { # fc_resolve_ref <name> -> the full ref git resolves it to, in pre-push's order; "" when it resolves to nothing
  local v="$1" short cand full
  [[ -n "$v" ]] || return 0
  short="${v#refs/heads/}"; short="${short#refs/remotes/origin/}"; short="${short#origin/}"
  for cand in "refs/remotes/origin/$short" "refs/heads/$short" "$v"; do
    full="$(git -C "$REPO" rev-parse --symbolic-full-name --verify --quiet "$cand" 2>/dev/null)" || full=""
    [[ -n "$full" ]] && { printf '%s' "$full"; return 0; }
  done
  return 0
}
HEAD_TRUNK_RAW="$(fc_recorded_trunk "$HEAD_SHA")" || HEAD_TRUNK_RAW=""
if git -C "$REPO" cat-file -e "$BASE_SHA:.claude/sdd.json" 2>/dev/null; then
  TRUNK_RAW="$(fc_recorded_trunk "$BASE_SHA")" || TRUNK_RAW=""
  if [[ "$HEAD_TRUNK_RAW" != "$TRUNK_RAW" ]]; then
    fc_say "[FC-NOT-AN-INSTANCE]" "the head records trunk \"$HEAD_TRUNK_RAW\" where the base records \"$TRUNK_RAW\": a pull request that REDIRECTS the instance's trunk is refused rather than judged under the config it rewrote. The trunk's own tip says which branch is protected; change it there, through a person, not through a pull request the change would exempt."
    refuse NOT-AN-INSTANCE
  fi
else
  TRUNK_RAW="$HEAD_TRUNK_RAW"
fi
TRUNK_FULL="$(fc_resolve_ref "$TRUNK_RAW")"
if [[ -z "$TRUNK_FULL" ]]; then
  fc_say "[SLH-TRUNK-NOT-A-BRANCH]" ".claude/sdd.json records trunk \"$TRUNK_RAW\", which does not resolve to a branch in this checkout, so the trunk this project protects cannot be established and this check would otherwise pass on nothing. Record the plain branch NAME (for example \"main\"); a ref path such as refs/remotes/origin/main, a case variant or stray whitespace is not a branch here."
  refuse NOT-AN-INSTANCE
fi
case "$TRUNK_FULL" in
  refs/heads/*) TRUNK_NAME="${TRUNK_FULL#refs/heads/}" ;;
  refs/remotes/*) TRUNK_NAME="${TRUNK_FULL#refs/remotes/}"; TRUNK_NAME="${TRUNK_NAME#*/}" ;;
  *) TRUNK_NAME="$TRUNK_RAW" ;;
esac
if [[ -n "$BASE_NAME" ]]; then
  BASE_FULL="$(fc_resolve_ref "$BASE_NAME")"
  if [[ "$BASE_FULL" != "$TRUNK_FULL" ]]; then
    if [[ "$(printf '%s' "$BASE_FULL" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$TRUNK_FULL" | tr '[:upper:]' '[:lower:]')" ]]; then
      fc_say "[SLH-TRUNK-NOT-A-BRANCH]" ".claude/sdd.json records trunk \"$TRUNK_RAW\" and the pull request's base is $BASE_NAME: the two differ only in case, and this check does not guess which spelling the forge protects. Record the trunk exactly as the branch is named."
      refuse NOT-AN-INSTANCE
    fi
    # THE ONE PASS-ON-NOTHING, and it is not a pass on absence: the predicate has
    # no subject. Said out loud so a reader of the log knows why it was quick.
    printf 'setlist forge check: not a trunk pull request (base %s, recorded trunk %s); nothing to verify\n' "$BASE_NAME" "$TRUNK_NAME" >&2
    printf 'PASS (not a trunk pull request; nothing to verify)\n'
    exit 0
  fi
fi

# --- 3. the scratch merge ---------------------------------------------------
#
# A shared clone rather than a worktree: the trunk branch must exist as a
# LOCAL branch for the library's reducer and for the audit, and a worktree
# cannot check out a branch the main checkout already has. The clone copies no
# config, so the instance's own hooks do not run inside it, and the identity is
# FIXED so nothing about the runner reaches the history the audit reads.
FC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/setlist-forge-check.XXXXXX" 2>/dev/null)" || could_not_run "could not create a scratch directory"
FC_CLONE="$FC_TMP/merge"
git clone -q --shared --no-checkout "$REPO" "$FC_CLONE" >/dev/null 2>&1 || could_not_run "could not clone the checkout into a scratch directory"
git -C "$FC_CLONE" config user.email "forge-check@setlist.invalid"
git -C "$FC_CLONE" config user.name "setlist-forge-check"
git -C "$FC_CLONE" config commit.gpgsign false
git -C "$FC_CLONE" config core.hooksPath /dev/null
git -C "$FC_CLONE" config merge.ff false
export GIT_AUTHOR_NAME="setlist-forge-check" GIT_AUTHOR_EMAIL="forge-check@setlist.invalid"
export GIT_COMMITTER_NAME="setlist-forge-check" GIT_COMMITTER_EMAIL="forge-check@setlist.invalid"
git -C "$FC_CLONE" checkout -q -B "$TRUNK_NAME" "$BASE_SHA" >/dev/null 2>&1 || could_not_run "could not check out the base $BASE_SHA as $TRUNK_NAME in the scratch clone"
if ! git -C "$FC_CLONE" merge --no-ff --no-commit "$HEAD_SHA" >/dev/null 2>&1; then
  git -C "$FC_CLONE" merge --abort >/dev/null 2>&1 || true # fail-open-ok: the refusal is decided on the next line regardless; the abort only tidies the scratch clone that is about to be removed
  fc_say "[FC-NOT-MERGEABLE]" "the head does not merge onto $TRUNK_NAME without conflicts, so there is no merge to verify; resolve the conflicts on the branch."
  refuse NOT-MERGEABLE
fi
# From here every library question is asked of the SCRATCH CLONE, where the
# trunk is a local branch at the base and the index holds the merge.
SLH_REFUSED=0

# --- 5's arm, registered before 4 runs: custody C answered here ---------------
#
# The library's DEFERRED-TO-FORGE arm calls this when it is registered (it is
# registered by this check and by nothing else; the git hooks never set it),
# and refuses on anything but VERIFIED. The forge is asked ONCE and the answer
# is cached for step 9's reports.
FC_RULES_STATE=""     # "", ok, unreachable, forbidden, plan-limited, rate-limited, no-forge
FC_RULES_DETAIL=""
FC_PROTECTED=0; FC_REVIEWS=0; FC_CHECK_REQUIRED=0; FC_REBASE=""; FC_RULESET_REBASE=""; FC_STRICT=0
FC_HTTP=""; FC_BODY=""

fc_forge_get() { # fc_forge_get <api-path> -> FC_HTTP and FC_BODY set; 1 when the forge did not answer at all
  local out
  FC_HTTP=""; FC_BODY=""
  if [[ -n "$FC_QUERY_CMD" ]]; then
    out="$($FC_QUERY_CMD "$1" 2>/dev/null)" || return 1
  else
    command -v curl >/dev/null 2>&1 || return 1
    out="$(curl -sS --max-time 20 -w '\n%{http_code}' \
            -H "Accept: application/vnd.github+json" \
            ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            "$FC_API/$1" 2>/dev/null)" || return 1
    # curl prints the body then the status; the seam prints the status then the
    # body. Normalise to status-first.
    out="$(printf '%s\n' "$out" | tail -n1)
$(printf '%s\n' "$out" | sed '$d')"
  fi
  FC_HTTP="$(printf '%s\n' "$out" | head -n1 | tr -d '[:space:]')"
  FC_BODY="$(printf '%s\n' "$out" | sed '1d')"
  [[ -n "$FC_HTTP" ]] || return 1
  return 0
}

# A 403 HAS THREE CAUSES, AND TWO CODES (ratification amendment 1, 2026-09-07).
# The design's row 2 named two (a token that may not read the rules; a private
# repository) and prescribed contents: read. The build measured a third on the
# owner's private repository: a forge that does not OFFER protection on the
# repository's plan answers 403 with a plan message, at the rules endpoint and
# at the classic one alike, and that operator has no permission to grant. The
# measured body routes to FC-FORGE-PLAN-LIMITED; every other 401/403/404 stays
# FC-FORGE-FORBIDDEN with the row's two readings. The two are pinned beside
# each other so a later edit cannot fold one into the other.
fc_forbidden_or_plan() { # fc_forbidden_or_plan <which query> -> sets FC_RULES_STATE to forbidden or plan-limited
  local msg
  msg="$(printf '%s' "$FC_BODY" | jq -r '.message // ""' 2>/dev/null | head -c 160)" # fail-open-ok: an unreadable body yields an empty message, which routes to FORBIDDEN, the refusing state
  case "$FC_HTTP:$msg" in
    403:"Upgrade to GitHub"*) FC_RULES_STATE="plan-limited"; FC_RULES_DETAIL="$1 answered 403: $msg" ;;
    *) FC_RULES_STATE="forbidden"; FC_RULES_DETAIL="$1 answered $FC_HTTP: $msg" ;;
  esac
}

fc_query_rules() { # fills FC_RULES_STATE and the five facts; idempotent
  [[ -z "$FC_RULES_STATE" ]] || return 0
  if [[ "$FC_FORGE" != "github" ]]; then FC_RULES_STATE="no-forge"; return 0; fi
  [[ -n "$FC_REPO" ]] || { FC_RULES_STATE="no-forge"; FC_RULES_DETAIL="no --repo given"; return 0; }
  # The repository's merge methods first: one query, and it also proves the
  # forge answers at all.
  if ! fc_forge_get "repos/$FC_REPO"; then FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="no answer"; return 0; fi
  case "$FC_HTTP" in
    200) FC_REBASE="$(printf '%s' "$FC_BODY" | jq -r 'if .allow_rebase_merge == true then "1" elif .allow_rebase_merge == false then "0" else "" end' 2>/dev/null || true)" ;; # fail-open-ok: an unreadable answer leaves the rebase fact unknown, and unknown prints no report line; the rebase line is a REPORT under every custody (decision 3), never a verdict
    429) FC_RULES_STATE="rate-limited"; return 0 ;;
    401|403|404) FC_RULES_STATE="forbidden"; FC_RULES_DETAIL="the repository query answered $FC_HTTP"; return 0 ;;
    5*|"") FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="the repository query answered ${FC_HTTP:-nothing}"; return 0 ;;
    *) FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="the repository query answered $FC_HTTP"; return 0 ;;
  esac
  # THE TRUNK'S PROTECTION IS READ FROM BOTH ENDPOINTS AND TAKEN AS A UNION
  # (ratification amendment 4, 2026-09-07). The forge enforces rulesets and
  # classic branch protection together: a repository may require the review
  # in one and the check in the other, and the design's order (rulesets, then
  # the classic endpoint only on an empty list) refused that repository on the
  # ruleset alone (measured 2026-09-07 on the owner's public repository, where
  # the rules answer never carries classic protection). So: the rules that
  # apply to the trunk (rulesets, readable with contents: read), then the
  # classic endpoint ALWAYS; the trunk is protected when either carries a
  # rule, the review requirement is the higher of the two, the check is
  # required when either requires it, and neither present is UNPROTECTED.
  local rules_n rs_prot=0 rs_reviews=0 rs_checks=0 rs_strict=0 cl_prot=0 cl_reviews=0 cl_checks=0 cl_strict=0 rs_enough=0
  if ! fc_forge_get "repos/$FC_REPO/rules/branches/$TRUNK_NAME"; then FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="no answer to the rules query"; return 0; fi
  case "$FC_HTTP" in
    200) ;;
    429) FC_RULES_STATE="rate-limited"; return 0 ;;
    401|403|404) fc_forbidden_or_plan "the rules query"; return 0 ;;
    *) FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="the rules query answered $FC_HTTP"; return 0 ;;
  esac
  rules_n="$(printf '%s' "$FC_BODY" | jq -r 'if type == "array" then length else -1 end' 2>/dev/null || printf -- '-1')" # fail-open-ok: an unreadable answer yields -1, which the next line routes to UNREACHABLE (a refusal under custody C), never to "no rules"
  if [[ "$rules_n" == "-1" ]]; then FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="the rules answer was not a list"; return 0; fi
  if [[ "$rules_n" -gt 0 ]]; then
    # fail-open-ok: both extractions yield 0 when unreadable, and 0 is the REFUSING value for each (no review required, this check not required); an unreadable rule can only refuse here
    rs_reviews="$(printf '%s' "$FC_BODY" | jq -r '[.[] | select(.type == "pull_request") | (.parameters.required_approving_review_count // 0)] | max // 0' 2>/dev/null || printf 0)"
    rs_checks="$(printf '%s' "$FC_BODY" | jq -r '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]? | .context] | index("setlist forge check") | if . == null then "0" else "1" end' 2>/dev/null || printf 0)"
    # THE STRICT SETTING (TE4, ruled D15 2026-09-10): "require branches to be up
    # to date before merging". On a ruleset it is the required_status_checks
    # rule's strict_required_status_checks_policy; on the classic endpoint it is
    # required_status_checks.strict. Read from BOTH and taken as a union, exactly
    # as protection is (amendment 4), and 0 is the refusing value here too, so an
    # unreadable rule can only refuse.
    rs_strict="$(printf '%s' "$FC_BODY" | jq -r '[.[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy] | if length == 0 then "0" elif any(. == true) then "1" else "0" end' 2>/dev/null || printf 0)" # fail-open-ok: 0 is the REFUSING value (not strict), so an unreadable rule refuses under forge custody rather than passing
    rs_prot=1
    # THE RULESET'S OWN MERGE METHODS (ratification amendment 3, 2026-09-07).
    # A pull_request rule may carry allowed_merge_methods, which the forge
    # intersects with the repository's flags: a rebase merge is possible on
    # the trunk only when the repository allows it AND every rule that lists
    # methods lists rebase. "" when no rule states one (the repository flag
    # decides alone), 1 when every stating rule allows rebase, 0 when one
    # forbids it, which SILENCES decision 3's report; report, never refuse.
    FC_RULESET_REBASE="$(printf '%s' "$FC_BODY" | jq -r '[.[] | select(.type == "pull_request") | .parameters.allowed_merge_methods? | select(. != null)] | if length == 0 then "" elif all(index("rebase") != null) then "1" else "0" end' 2>/dev/null || true)" # fail-open-ok: an unreadable rule leaves the ruleset fact unknown, and the repository flag then decides the REPORT line alone, which is the pre-amendment reading and never a verdict
  fi
  rs_enough=0; [[ "$rs_prot" -eq 1 && "${rs_reviews:-0}" -ge 1 && "$rs_checks" == "1" ]] && rs_enough=1
  # The classic branch protection, always. It needs a permission the default
  # token may lack (measured 2026-09-06 on the owner's repositories: a public
  # one answers 404 "Branch not protected" when there is none; a private one
  # on a plan without protection answers 403 "Upgrade to GitHub Pro"), and
  # section 6 treats a permission answer as UNVERIFIABLE rather than as
  # absence. "Branch not protected" IS absence, and is read as such by its
  # documented message. An answer that cannot be read decides the state ONLY
  # where the verdict depends on it: the classic layer can add a requirement
  # and never remove one, so a ruleset that already requires both is not undone
  # by a 403 beside it, while a ruleset that lacks one cannot be read as
  # lacking it when the other layer's answer was refused.
  if ! fc_forge_get "repos/$FC_REPO/branches/$TRUNK_NAME/protection"; then
    if [[ "$rs_enough" -eq 1 ]]; then FC_RULES_DETAIL="no answer to the protection query; the ruleset already requires both, so nothing depends on it"
    else FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="no answer to the protection query"; return 0; fi
  else
    case "$FC_HTTP" in
      200)
        # fail-open-ok: as above, 0 is the refusing value for both facts
        cl_reviews="$(printf '%s' "$FC_BODY" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0' 2>/dev/null || printf 0)"
        cl_checks="$(printf '%s' "$FC_BODY" | jq -r '((.required_status_checks.contexts // []) + [(.required_status_checks.checks // [])[] | .context]) | index("setlist forge check") | if . == null then "0" else "1" end' 2>/dev/null || printf 0)"
        cl_strict="$(printf '%s' "$FC_BODY" | jq -r 'if .required_status_checks.strict == true then "1" else "0" end' 2>/dev/null || printf 0)" # fail-open-ok: as above, 0 is the refusing value
        cl_prot=1 ;;
      404)
        if ! printf '%s' "$FC_BODY" | jq -e '.message == "Branch not protected"' >/dev/null 2>&1; then
          if [[ "$rs_enough" -eq 1 ]]; then FC_RULES_DETAIL="the protection query answered 404 without the documented absence message; the ruleset already requires both, so nothing depends on it"
          else FC_RULES_STATE="forbidden"; FC_RULES_DETAIL="the protection query answered 404: $(printf '%s' "$FC_BODY" | jq -r '.message // ""' 2>/dev/null | head -c 160)"; return 0; fi
        fi ;;
      429)
        if [[ "$rs_enough" -eq 1 ]]; then FC_RULES_DETAIL="the protection query was rate limited; the ruleset already requires both, so nothing depends on it"
        else FC_RULES_STATE="rate-limited"; return 0; fi ;;
      401|403)
        if [[ "$rs_enough" -eq 1 ]]; then FC_RULES_DETAIL="the protection query answered $FC_HTTP; the ruleset already requires both, so nothing depends on it"
        else fc_forbidden_or_plan "the protection query"; return 0; fi ;;
      *)
        if [[ "$rs_enough" -eq 1 ]]; then FC_RULES_DETAIL="the protection query answered $FC_HTTP; the ruleset already requires both, so nothing depends on it"
        else FC_RULES_STATE="unreachable"; FC_RULES_DETAIL="the protection query answered $FC_HTTP"; return 0; fi ;;
    esac
  fi
  # The union.
  if [[ "$rs_prot" -eq 1 || "$cl_prot" -eq 1 ]]; then
    FC_PROTECTED=1
    FC_REVIEWS="${rs_reviews:-0}"; [[ "${cl_reviews:-0}" -gt "$FC_REVIEWS" ]] && FC_REVIEWS="$cl_reviews"
    FC_CHECK_REQUIRED=0; [[ "$rs_checks" == "1" || "$cl_checks" == "1" ]] && FC_CHECK_REQUIRED=1
    FC_STRICT=0; [[ "$rs_strict" == "1" || "$cl_strict" == "1" ]] && FC_STRICT=1
  else
    FC_PROTECTED=0
  fi
  FC_RULES_STATE="ok"; return 0
}

# The sentences of design section 6, one per forge state, printed by the arm
# that refuses on them under custody C and by step 9 as reports otherwise.
fc_forge_state_sentence() { # fc_forge_state_sentence -> prints "<code>|<sentence>" for a non-ok state, or "" when ok
  case "$FC_RULES_STATE" in
    unreachable)  printf '[FC-FORGE-UNREACHABLE]|the forge did not answer whether %s is protected (%s), so this check cannot establish that the approval reached the trunk through a review. A check that could not run has not passed. Re-run the check when the forge answers; nothing about this pull request is wrong.' "$TRUNK_NAME" "${FC_RULES_DETAIL:-no answer}" ;;
    forbidden)    printf '[FC-FORGE-FORBIDDEN]|the job'"'"'s identity may not read %s'"'"'s protection rules (%s), so the approval cannot be verified here. Grant the workflow contents: read (the template'"'"'s permissions block), or run the check from a job that can read them.' "$TRUNK_NAME" "${FC_RULES_DETAIL:-the forge answered forbidden}" ;;
    plan-limited) printf '[FC-FORGE-PLAN-LIMITED]|the forge does not offer protection rules for %s on this repository'"'"'s plan (%s), so no review and no check can be required to land on it, and under forge custody there is no notary. Move the repository to a plan that offers branch protection, or make the repository public, or declare a custody this layer can verify without a forge.' "$TRUNK_NAME" "${FC_RULES_DETAIL:-the forge answered with a plan limit}" ;;
    rate-limited) printf '[FC-FORGE-RATE-LIMITED]|the forge refused the query for rate limiting; re-run after the window named in its answer. Never retried inside the check: a retry loop inside a required check is a hang with a timer.' ;;
    no-forge)     printf '[FC-NO-FORGE]|this instance declares forge custody and the check was run with no forge to ask (%s); a forge the check cannot query cannot be the notary.' "${FC_RULES_DETAIL:-run with --forge none}" ;;
    *) printf '' ;;
  esac
}

fc_verify_custody_forge() { # fc_verify_custody_forge <proj> <spec-path> <num> <rev> -> prints ONE token
  local proj="$1" num="$3" rev="$4" flip line code sentence
  # $2 is the spec path the library hands every verifier; this one keys on the number.
  # 1. The flip is on the trunk: the commit that ADDED the document is an
  #    ancestor of the base. A git question; needs no forge. An empty rev is
  #    the merge INDEX (step 4), whose history is the base's: a document that
  #    exists only in the index was introduced by this merge and has no flip
  #    commit at all, which is the same refusal.
  flip="$(git -C "$proj" log --root --format=%H --diff-filter=A "${rev:-HEAD}" -- "specs/attest/$num.json" 2>/dev/null | tail -n1)"
  if [[ -z "$flip" ]] || ! git -C "$proj" merge-base --is-ancestor "$flip" "$BASE_SHA" 2>/dev/null; then
    fc_say "[FC-FLIP-NOT-ON-TRUNK]" "specs/attest/$num.json was added in this pull request's own history and is not on $TRUNK_NAME; under forge custody an approval is a flip the trunk has already accepted through review. Land the planning change first."
    fc_set_token ATTEST-REFUSED
    printf 'FLIP-NOT-ON-TRUNK'; return 0
  fi
  # 2. The trunk is protected such that a review and this check are required.
  fc_query_rules
  if [[ "$FC_RULES_STATE" != "ok" ]]; then
    line="$(fc_forge_state_sentence)"; code="${line%%|*}"; sentence="${line#*|}"
    fc_say "$code" "$sentence"
    fc_set_token FORGE-UNREACHABLE
    printf 'FORGE-UNREACHABLE'; return 0
  fi
  if [[ "$FC_PROTECTED" != "1" ]]; then
    fc_say "[FC-FORGE-UNPROTECTED]" "$TRUNK_NAME is not protected on this forge: nothing requires a review or this check to land on it, so under forge custody there is no notary and no approval can be verified. Protect the trunk (require a pull request with one approving review, and require the check named \"setlist forge check\"), or declare a custody this layer can verify without a forge."
    fc_set_token FORGE-UNPROTECTED
    printf 'FORGE-UNPROTECTED'; return 0
  fi
  if [[ "${FC_REVIEWS:-0}" -lt 1 ]]; then
    fc_say "[FC-NO-REVIEW-REQUIRED]" "$TRUNK_NAME requires no approving review, so a flip can land with no second person, which is not the custody this instance declares."
    fc_set_token FORGE-UNPROTECTED
    printf 'FORGE-UNPROTECTED'; return 0
  fi
  if [[ "$FC_CHECK_REQUIRED" != "1" ]]; then
    fc_say "[FC-CHECK-NOT-REQUIRED]" "$TRUNK_NAME is protected but does not require the check named \"setlist forge check\", so the merge button does not enforce what this check verifies. Add it to the required status checks; a required check that is not required is a report."
    fc_set_token CHECK-NOT-REQUIRED
    printf 'CHECK-NOT-REQUIRED'; return 0
  fi
  # TE4, ruled D15 (2026-09-10): THE TRUNK MUST REQUIRE BRANCHES TO BE UP TO DATE.
  #
  # ONE REFUSAL PER ROOT CAUSE (the owner's ruling S3): this arm sits BELOW the
  # check-required refusal deliberately and is unreachable while that one fires,
  # because a trunk that does not require this check has nothing to be strict
  # ABOUT, and two codes for one cause is two things for an operator to fix when
  # there is one.
  #
  # Why it refuses rather than reports under custody C: this check is the notary,
  # and without the strict setting two pull requests can each be green against a
  # base neither of them merged into. The second one lands on a trunk its check
  # never read. That is precisely the guarantee "forge" custody claims.
  if [[ "$FC_STRICT" != "1" ]]; then
    fc_say "[FC-STRICT-NOT-REQUIRED]" "$TRUNK_NAME requires this check but does not require branches to be up to date before merging (the setting is \"Require branches to be up to date before merging\", beside the required status checks; on a ruleset it is the required_status_checks rule's strict policy). Without it two pull requests can both be green against a stale base and the second lands on a trunk this check never read, so under forge custody the notary is not one. Turn the setting on."
    fc_set_token STRICT-NOT-REQUIRED
    printf 'STRICT-NOT-REQUIRED'; return 0
  fi
  # THE SENTENCE, VERBATIM FROM THE RATIFIED DESIGN (section 5, decision 4).
  printf 'setlist forge check [FC-CUSTODY-VERIFIED] spec %s is covered by an approval under "forge" custody: the trunk %s is protected on this forge (a pull request with at least one approving review and the required check "setlist forge check" are required to land on it), the ACTIVE flip that wrote specs/attest/%s.json is an ancestor of that trunk, and the attestation'"'"'s hash covers the spec'"'"'s bytes in this merge. This establishes that the approval reached the trunk through the forge'"'"'s review, not that any particular person decided; the forge'"'"'s account security is the custody.\n' "$num" "$TRUNK_NAME" "$num" >&2
  printf 'VERIFIED'
}
# shellcheck disable=SC2034  # read by the sourced library's DEFERRED-TO-FORGE arm
SLH_ATTEST_FORGE_VERIFIER="fc_verify_custody_forge"

# --- 4. the close verification over the merge index ---------------------------
# shellcheck disable=SC2034  # read by the sourced library's close verification (a merge, not a single-parent completion)
SLH_CLOSE_SINGLE_PARENT=0
# The close verification's own CODEOWNERS pass is the hooks' ADVISORY one on the
# merging clone's identity; this check runs the arm itself at step 9 with the
# forge's identity and REFUSES (ruling 4), so the advisory pass is switched off.
# shellcheck disable=SC2034  # read by the sourced library's close verification
SLH_CODEOWNERS_MODE=""
fc_clear_token
# The close verification re-verifies the closing spec's approval over its FINAL
# bytes, so under custody C the forge is asked here first; a forge refusal
# inside it carries its own token (FORGE-UNREACHABLE, FORGE-UNPROTECTED,
# CHECK-NOT-REQUIRED, ATTEST-REFUSED) rather than the close's.
slh_verify_close "$FC_CLONE" "$TRUNK_NAME" "the forge check" || true # fail-open-ok: the refusal is recorded in SLH_REFUSED and decided on the next line, so every reason prints before the one token
FC_T="$(fc_token)"; [[ "$SLH_REFUSED" -eq 0 ]] || refuse "${FC_T:-CLOSE-REFUSED}"

# --- 5. the attestation walk over the range -----------------------------------
fc_clear_token
slh_attest_walk "$FC_CLONE" "the history this pull request adds to $TRUNK_NAME" "$HEAD_SHA" "$BASE_SHA..$HEAD_SHA" || true # fail-open-ok: recorded in SLH_REFUSED and decided on the next line
FC_T="$(fc_token)"; [[ "$SLH_REFUSED" -eq 0 ]] || refuse "${FC_T:-ATTEST-REFUSED}"

# --- 6. the content scan over the range ---------------------------------------
slh_scan_walk "$FC_CLONE" "the history this pull request adds to $TRUNK_NAME" "$BASE_SHA..$HEAD_SHA" || true # fail-open-ok: recorded in SLH_REFUSED and decided on the next line
[[ "$SLH_REFUSED" -eq 0 ]] || refuse SCAN-REFUSED

# --- 7. the third gate tier, in the merged worktree ---------------------------
if ! slh_run_gate_command "$FC_CLONE" push; then
  refuse GATE-RED
fi
[[ "$SLH_REFUSED" -eq 0 ]] || refuse GATE-RED

# --- 8. the merge committed, and the trunk audit over it ----------------------
if ! git -C "$FC_CLONE" diff --cached --quiet 2>/dev/null; then
  git -C "$FC_CLONE" commit -q --no-verify -m "setlist forge check: scratch merge of $HEAD_SHA onto $TRUNK_NAME" >/dev/null 2>&1 \
    || could_not_run "could not commit the scratch merge"
fi
MERGE_SHA="$(git -C "$FC_CLONE" rev-parse HEAD 2>/dev/null)" # fail-open-ok: an unreadable HEAD is empty, differs from the base, and the audit then dies on an unresolvable --until (exit 2), never clean
if [[ "$MERGE_SHA" != "$BASE_SHA" ]]; then
  AUDIT_RC=0
  bash "$AUDIT" "$FC_CLONE" --since "$BASE_SHA" --until "$MERGE_SHA" >&2 || AUDIT_RC=$?
  if [[ "$AUDIT_RC" -eq 2 ]]; then could_not_run "the trunk audit could not run (see above); exit 2 is never clean"; fi
  [[ "$AUDIT_RC" -eq 0 ]] || refuse AUDIT-VIOLATION
fi

# --- 8b. RENDER VALIDATION (edition v1.15, contract item 4, D14) --------------
#
# The claim this step makes is "every diagram block PARSES under the pinned
# Mermaid version", not "a PNG was produced". D14b required that distinction to
# be MEASURED rather than assumed, and it was, on 2026-09-10 against
# mermaid 11.14.0: mermaid.parse() resolves a valid block and throws a real
# parse error on a broken one, headless, with a DOM shim and NO browser. Its
# verdict agreed with the full renderer (mermaid-cli 11.17.0 + puppeteer) on
# every case of a twelve-case corpus covering flowchart, sequence, state, class,
# er and C4, both directions. So the step parses, the browser download goes, and
# the boundary bullet states the price this step actually pays.
#
# THE RENDERER IS AN EXTERNAL COMMAND ON PATH, and there are exactly two shapes
# this step knows how to call. `setlist-mermaid-parse <file>` is what the stamped
# workflow installs; `mmdc -i <file> -o <out>` is mermaid-cli, accepted so a
# forge that already has it needs nothing new. Anything else is "no renderer".
#
# ABSENCE IS A REPORT HERE AND A FAILED JOB IN THE WORKFLOW (condition (a)).
# Inside .github/workflows/setlist-forge-check.yml the install step succeeds or
# fails the job, so this report is reachable only when the stamped script runs
# somewhere else, which is a forge without node rather than a forge that skipped
# the check. "Never a pass on absence" stays true exactly where the check is
# required, and the public bullet says so in those words.
FC_RENDERER=""
if command -v setlist-mermaid-parse >/dev/null 2>&1; then FC_RENDERER="parse"
elif command -v mmdc >/dev/null 2>&1; then FC_RENDERER="mmdc"; fi

if [[ -z "$FC_RENDERER" ]]; then
  fc_report "[FC-DIAGRAM-NO-RENDERER]" "no Mermaid renderer is on PATH (neither setlist-mermaid-parse nor mmdc), so no diagram block was parsed. Inside the stamped workflow the renderer step fails the job rather than reaching this line, so this report means the check is running somewhere that has no node. Put a renderer on the runner's PATH to turn the diagram blocks into a checked claim."
else
  FC_DIAG_FILES="$(git -C "$FC_CLONE" ls-files --cached -- 'docs/diagrams/*.md' 'steering/structure.md' 2>/dev/null || true)" # fail-open-ok: no listed files means no blocks to parse, and the field and node checks in step 4 already ran over the same merge; this step adds a claim, it is not the only reader
  FC_DIAG_BAD=0
  while IFS= read -r fcd; do
    [[ -n "$fcd" ]] || continue
    fcblob="$(git -C "$FC_CLONE" show ":$fcd" 2>/dev/null || true)" # fail-open-ok: an unreadable file yields no blocks; the close verification already refused an unreadable spec surface
    [[ -n "$fcblob" ]] || continue
    # One block at a time, because the refusal has to NAME the block that failed
    # and a whole-file parse can only say the file is bad.
    fccount="$(printf '%s\n' "$fcblob" | awk -v want=0 "$SLH_DIAGRAM_MERMAID_BLOCK_AWK")" # fail-open-ok: an unreadable count yields empty, the loop below runs zero times, and this step adds a claim rather than being the only reader of this merge
    fcn=1
    while [[ "$fcn" -le "${fccount:-0}" ]]; do
      fctmp="$FC_TMP/diagram-$fcn.mmd"
      printf '%s\n' "$fcblob" | awk -v want="$fcn" "$SLH_DIAGRAM_MERMAID_BLOCK_AWK" > "$fctmp"
      if [[ ! -s "$fctmp" ]]; then fcn=$((fcn + 1)); continue; fi
      fcok=0
      if [[ "$FC_RENDERER" == "parse" ]]; then
        fcout="$(setlist-mermaid-parse "$fctmp" 2>&1)" && fcok=1
      else
        fcout="$(mmdc -i "$fctmp" -o "$fctmp.svg" 2>&1)" && fcok=1
      fi
      if [[ "$fcok" -ne 1 ]]; then
        fc_say "[FC-DIAGRAM-RENDER]" "$fcd: Mermaid block $fcn does not parse under the pinned version, so the diagram this repository claims to draw cannot be drawn. The renderer said: $(printf '%s' "$fcout" | tr '\n' ' ' | head -c 300)"
        FC_DIAG_BAD=1
      fi
      fcn=$((fcn + 1))
    done
  done <<EOF
$FC_DIAG_FILES
EOF
  [[ "$FC_DIAG_BAD" -eq 0 ]] || refuse DIAGRAM-RENDER
fi

# --- 9a. the CODEOWNERS bridge (T1) with the forge's identity ------------------
#
# The identity is the pull request's AUTHOR as the forge reports it (--author,
# the workflow passes the event's login); a plain runner with no author falls
# back to the head commit's author email, which is what the audit reads. Handles
# match the login; teams and emails are resolved at the forge with the job's
# token, and a query the forge does not answer is UNVERIFIABLE (section 6's
# rows), never "not a member".
fc_resolve_owner() { # fc_resolve_owner <owner> <login> -> yes | no | unknown; an unanswered query is recorded for the caller
  local owner="$1" login="$2" org team email
  [[ "$FC_FORGE" == "github" && -n "$FC_REPO" ]] || return 0
  case "$owner" in
    @*/*)
      org="${owner#@}"; team="${org#*/}"; org="${org%%/*}"
      if ! fc_forge_get "orgs/$org/teams/$team/memberships/$login"; then printf 'unreachable' > "$FC_TMP/resolve-fail"; printf 'unknown'; return 0; fi
      case "$FC_HTTP" in
        200) if printf '%s' "$FC_BODY" | jq -e '.state == "active"' >/dev/null 2>&1; then printf 'yes'; else printf 'no'; fi ;;
        404) printf 'no' ;;
        429) printf 'rate-limited' > "$FC_TMP/resolve-fail"; printf 'unknown' ;;
        *)   printf 'forbidden:%s' "$FC_HTTP" > "$FC_TMP/resolve-fail"; printf 'unknown' ;;
      esac ;;
    @*) printf 'unknown' ;;
    *)
      if ! fc_forge_get "users/$login"; then printf 'unreachable' > "$FC_TMP/resolve-fail"; printf 'unknown'; return 0; fi
      case "$FC_HTTP" in
        200) email="$(printf '%s' "$FC_BODY" | jq -r '.email // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')" # fail-open-ok: an unreadable or private email is empty and matches no owner, which reads as "no" below, and "no" REFUSES
             if [[ -n "$email" && "$email" == "$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')" ]]; then printf 'yes'; else printf 'no'; fi ;;
        429) printf 'rate-limited' > "$FC_TMP/resolve-fail"; printf 'unknown' ;;
        *)   printf 'forbidden:%s' "$FC_HTTP" > "$FC_TMP/resolve-fail"; printf 'unknown' ;;
      esac ;;
  esac
  return 0
}
if [[ -n "$SLH_OWNS_DECLARED" ]]; then
  SLH_REFUSED=0
  rm -f "$FC_TMP/resolve-fail"
  if ! slh_codeowners_load "$FC_CLONE"; then
    refuse CODEOWNERS-UNREADABLE
  fi
  if [[ "$SLH_CODEOWNERS_STATE" == "ok" ]]; then
    if [[ -n "$FC_AUTHOR" ]]; then
      # shellcheck disable=SC2034  # read by the sourced library's ownership check
      SLH_CODEOWNERS_RESOLVER="fc_resolve_owner"
      # shellcheck disable=SC2086  # the declared set is space-separated by construction (Owns: forbids spaces)
      slh_owns_codeowners_check "the forge check" refuse login "$FC_AUTHOR" $SLH_OWNS_DECLARED
    else
      # shellcheck disable=SC2086
      slh_owns_codeowners_check "the forge check" refuse email "$(git -C "$FC_CLONE" log -1 --format=%ae "$HEAD_SHA" 2>/dev/null)" $SLH_OWNS_DECLARED
    fi
    if [[ -f "$FC_TMP/resolve-fail" ]]; then
      case "$(cat "$FC_TMP/resolve-fail")" in
        rate-limited) fc_say "[FC-FORGE-RATE-LIMITED]" "the forge refused an ownership query for rate limiting; re-run after the window named in its answer. An owner this check could not resolve is not a match and not a mismatch: the check could not run." ;;
        forbidden:*)  fc_say "[FC-FORGE-FORBIDDEN]" "the job's identity may not read a team membership or a user record the ownership file names ($(cat "$FC_TMP/resolve-fail")), so the declared files cannot be checked against their owners here. Grant the workflow the read it needs, or name the owners as logins." ;;
        *)            fc_say "[FC-FORGE-UNREACHABLE]" "the forge did not answer an ownership query, so the declared files cannot be checked against their owners here. A check that could not run has not passed; re-run when the forge answers." ;;
      esac
      refuse FORGE-UNREACHABLE
    fi
    [[ "$SLH_REFUSED" -eq 0 ]] || refuse CODEOWNERS-MISMATCH
  fi
fi

# --- 9. the forge questions that are reports under a custody that is not C ----
FC_CUSTODY="none declared"
slh_attest_load "$FC_CLONE" >/dev/null 2>&1 || true # fail-open-ok: only the custody NAME for the pass line is read here; the load's own refusals already decided steps 4 and 5
[[ "$SLH_ATTEST_STATE" == "on" ]] && FC_CUSTODY="$SLH_ATTEST_CUSTODY"
if [[ "$FC_FORGE" == "github" ]]; then
  fc_query_rules
  if [[ "$FC_RULES_STATE" == "ok" ]]; then
    if [[ "$FC_CUSTODY" != "forge" ]]; then
      # REPORT cells, never passes on absence: under a custody that is not C the
      # trunk's protection is not part of any claim this instance makes, so the
      # fact is reported and the verdict rests on the predicates above.
      if [[ "$FC_PROTECTED" != "1" ]]; then
        fc_report "[FC-FORGE-UNPROTECTED]" "$TRUNK_NAME is not protected on this forge: nothing requires a review or this check to land on it. Under custody \"$FC_CUSTODY\" the verdict above stands; the merge button enforces it only where this check is required."
      else
        [[ "${FC_REVIEWS:-0}" -ge 1 ]] || fc_report "[FC-NO-REVIEW-REQUIRED]" "$TRUNK_NAME requires no approving review. Under custody \"$FC_CUSTODY\" the verdict above stands."
        [[ "$FC_CHECK_REQUIRED" == "1" ]] || fc_report "[FC-CHECK-NOT-REQUIRED]" "$TRUNK_NAME is protected but does not require the check named \"setlist forge check\", so the merge button does not enforce what this check verifies. Add it to the required status checks; a required check that is not required is a report."
        # TE4's report half (D15), beside the review count. Same root-cause rule as
        # the refusing arm (S3): silent while the check is not required at all.
        [[ "$FC_CHECK_REQUIRED" != "1" || "$FC_STRICT" == "1" ]] || fc_report "[FC-STRICT-NOT-REQUIRED]" "$TRUNK_NAME requires this check but does not require branches to be up to date before merging, so two pull requests can both be green against a stale base. Under custody \"$FC_CUSTODY\" the verdict above stands; turn the setting on where this check is the notary."
      fi
    fi
    # Amendment 3: the report fires only where a rebase merge is POSSIBLE on
    # the trunk, the repository's flag AND the ruleset's allowed_merge_methods.
    if [[ "$FC_REBASE" == "1" && "$FC_RULESET_REBASE" != "0" ]]; then
      fc_report "[FC-REBASE-MERGE-ENABLED]" "this repository allows rebase merges; a rebase merge lands every commit of this branch on $TRUNK_NAME as direct feature code and the next check will refuse the trunk. Disable rebase merging, or merge with a merge commit."
    fi
  elif [[ "$FC_CUSTODY" != "forge" ]]; then
    printf 'setlist forge check report: the forge did not answer the protection query (%s); under custody "%s" nothing above depends on it.\n' "${FC_RULES_DETAIL:-$FC_RULES_STATE}" "$FC_CUSTODY" >&2
  fi
fi

# --- 10. PASS ---------------------------------------------------------------
fc_cleanup
case "$FC_CUSTODY" in
  forge) printf 'PASS (custody: forge, verified at the forge)\n' ;;
  "none declared") printf 'PASS (custody: none declared)\n' ;;
  *) printf 'PASS (custody: %s)\n' "$FC_CUSTODY" ;;
esac
exit 0
