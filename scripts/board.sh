#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# board.sh - the board: every spec of an instance by state, read from the trunk
# and the remote, with its driver, its Owns: set, its branch and its age, and the
# collisions a read can see (edition v1.22, Part 6, spec 0201).
#
# Usage: board.sh [--offline] [--dir <instance>]          the board
#        board.sh [--offline] [--dir <instance>] --next   the next spec number
#        board.sh [--offline] [--dir <instance>] --owns <file> --spec <NNNN>
#                                     who else declares <file> (the append report)
#
# IT REFUSES NOTHING. It is a report the agent and the engineer read: exit 0 with
# the report, whatever the report says; exit 2 only when it could not read (not a
# git repository, no .claude/sdd.json, no usable jq, a git read that failed), with
# the reason named. No hook calls it, and no gate reads its output; the guarantee
# on two specs that declare one file stays the close-time refusal (SLH-OWNS-OVERLAP).
#
# WHAT IT READS. The remote is the trunk's upstream (branch.<trunk>.remote), else
# origin, else none. Live, `git ls-remote --heads` lists the remote's trunk tip and
# its spec/ branches, and each listed tip not present locally is fetched into its
# remote-tracking ref (a fetch writes no working tree and no local branch).
# --offline reads the last fetch's remote-tracking refs alone and names their age
# from FETCH_HEAD. With no remote it reads the local trunk and says so. On the
# trunk it reads .claude/status.json (the state) and each specs/NNNN-<slug>.md
# header (Status, Driver, Owns); on each spec branch, that branch's own spec file,
# because Owns: lines are appended on the branch. A spec's Owns: set on the board
# is the union of the trunk's header and its branch's.
#
# It needs no server and works from any clone: what it cannot see is a claim
# nobody pushed.

set -u
LC_ALL=C; export LC_ALL

MODE=board; OFFLINE=0; DIR=""; OWNS_FILE=""; OWNS_SPEC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline) OFFLINE=1; shift ;;
    --next) MODE=next; shift ;;
    --owns) MODE=owns; OWNS_FILE="${2:-}"; shift 2 || { echo "board: --owns wants a file" >&2; exit 2; } ;;
    --spec) OWNS_SPEC="${2:-}"; shift 2 || { echo "board: --spec wants a number" >&2; exit 2; } ;;
    --dir) DIR="${2:-}"; shift 2 || { echo "board: --dir wants a path" >&2; exit 2; } ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "board: unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done
if [[ "$MODE" == owns ]] && [[ -z "$OWNS_FILE" || -z "$OWNS_SPEC" ]]; then
  echo "board: --owns <file> needs --spec <NNNN>, the spec making the append" >&2; exit 2
fi

cant() { echo "board: could not read: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 && [[ "$(printf '{"p":"x"}' | jq -r .p 2>/dev/null)" == x ]] \
  || cant "jq is missing or does not run (the board reads .claude/sdd.json and the status record with it)"
ROOT="$(git -C "${DIR:-.}" rev-parse --show-toplevel 2>/dev/null)" || cant "${DIR:-.} is not inside a git repository"
[[ -f "$ROOT/.claude/sdd.json" ]] || cant "$ROOT has no .claude/sdd.json, so it is not a Setlist instance"
jq -e . "$ROOT/.claude/sdd.json" >/dev/null 2>&1 || cant ".claude/sdd.json does not parse"
# Paths are read as git stores them (spec 0205, the 2.14.0 leg's F6): git quotes a path with a
# non-ASCII byte by default, and a quoted spec file name matched no spec pattern, so its number was
# offered again and no collision named it.
G() { git -C "$ROOT" -c core.quotePath=false "$@"; }

# Text from the repository is shown through the path set every Setlist message
# uses: any other byte becomes ?, so a branch or a handle cannot carry markup.
safe() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._/ :;+=@,()-' '?'; }

TRUNK="$(jq -r '.trunk // "main" | if . == "" then "main" else . end' "$ROOT/.claude/sdd.json")"
STALE_NOTE=""
STALE_DAYS="$(jq -r '.stale_days // empty' "$ROOT/.claude/sdd.json")"
# A value of zeros alone ("0", "00") is no positive number (spec 0205, the 2.14.0 leg's F9): "00" read
# as stale after 00 days and made every claim stale.
case "$STALE_DAYS" in
  '') STALE_DAYS=7; STALE_NOTE="stale_days not set: the default" ;;
  *[!0-9]*) STALE_NOTE="stale_days reads \"$(safe "$STALE_DAYS")\", not a positive whole number of days, so 7"; STALE_DAYS=7 ;;
  *) if [[ "$STALE_DAYS" =~ ^0+$ ]]; then
       STALE_NOTE="stale_days reads \"$(safe "$STALE_DAYS")\", not a positive whole number of days, so 7"; STALE_DAYS=7
     else
       STALE_DAYS="$((10#$STALE_DAYS))"; STALE_NOTE="stale_days in .claude/sdd.json"
     fi ;;
esac

REMOTE="$(G config --get "branch.$TRUNK.remote" 2>/dev/null)"
[[ "$REMOTE" == "." ]] && REMOTE=""
if [[ -z "$REMOTE" ]] && G remote 2>/dev/null | grep -qx origin; then REMOTE=origin; fi

W="$(mktemp -d "${TMPDIR:-/tmp}/setlist-board.XXXXXX")" || cant "no temporary directory"
trap 'rm -rf "$W"' EXIT
NOW="$(date +%s)"

fetch_age() {
  local fh
  fh="$(G rev-parse --git-path FETCH_HEAD 2>/dev/null)"
  [[ -n "$fh" && "$fh" != /* ]] && fh="$ROOT/$fh"
  if [[ -n "$fh" && -f "$fh" ]]; then
    local m; m="$(date -r "$fh" +%s 2>/dev/null)" || { echo "of unknown age"; return; }
    age_words $((NOW - m)) " old"
  else
    echo "never fetched"
  fi
}
age_words() { # seconds -> "3 days", "5 hours", "under an hour", with a suffix
  local s="$1" suf="${2:-}"
  if [[ "$s" -ge 86400 ]]; then echo "$((s / 86400)) days$suf"
  elif [[ "$s" -ge 3600 ]]; then echo "$((s / 3600)) hours$suf"
  else echo "under an hour$suf"; fi
}

# 1. The refs: the trunk revision the board reads, and the spec branches (name, tip).
: > "$W/branches"
TRUNK_REV=""; SOURCE_LINE=""
if [[ -z "$REMOTE" ]]; then
  TRUNK_REV="$(G rev-parse --verify -q "refs/heads/$TRUNK^{commit}")" || cant "the trunk $(safe "$TRUNK") does not resolve, and no remote is configured"
  SOURCE_LINE="remote: none configured; the board reads this clone's trunk, and no other clone can see what it shows"
else
  LIVE=0
  if [[ "$OFFLINE" -eq 0 ]]; then
    if G ls-remote --heads "$REMOTE" > "$W/ls" 2>"$W/ls.err"; then LIVE=1; else
      SOURCE_LINE="remote: $(safe "$REMOTE") could not be listed ($(safe "$(head -n1 "$W/ls.err")")); reading the last fetch, $(fetch_age)"
    fi
  fi
  if [[ "$LIVE" -eq 1 ]]; then
    SOURCE_LINE="remote: $(safe "$REMOTE"), read live (git ls-remote)"
    while IFS="$(printf '\t')" read -r sha ref; do
      name="${ref#refs/heads/}"
      if [[ "$name" == "$TRUNK" || "$name" == spec/* ]]; then
        if ! G cat-file -e "$sha^{commit}" 2>/dev/null; then
          G fetch -q "$REMOTE" "+refs/heads/$name:refs/remotes/$REMOTE/$name" 2>"$W/f.err" \
            || cant "git fetch of $(safe "$name") from $(safe "$REMOTE") failed: $(safe "$(head -n1 "$W/f.err")")"
        fi
        if [[ "$name" == "$TRUNK" ]]; then TRUNK_REV="$sha"; else printf '%s\t%s\n' "$name" "$sha" >> "$W/branches"; fi
      fi
    done < "$W/ls"
  else
    [[ -n "$SOURCE_LINE" ]] || SOURCE_LINE="remote: $(safe "$REMOTE"), read from the last fetch, $(fetch_age) (--offline)"
    TRUNK_REV="$(G rev-parse --verify -q "refs/remotes/$REMOTE/$TRUNK^{commit}" 2>/dev/null)"
    G for-each-ref --format='%(refname)%09%(objectname)' "refs/remotes/$REMOTE/spec/" > "$W/rt" 2>/dev/null \
      || cant "git for-each-ref over refs/remotes/$(safe "$REMOTE")/spec/ failed"
    while IFS="$(printf '\t')" read -r ref sha; do
      printf '%s\t%s\n' "${ref#refs/remotes/$REMOTE/}" "$sha" >> "$W/branches"
    done < "$W/rt"
  fi
  if [[ -z "$TRUNK_REV" ]]; then
    TRUNK_REV="$(G rev-parse --verify -q "refs/heads/$TRUNK^{commit}")" || cant "the trunk $(safe "$TRUNK") resolves neither on $(safe "$REMOTE") nor here"
    SOURCE_LINE="$SOURCE_LINE; the remote carries no $(safe "$TRUNK") yet, so the trunk read is this clone's"
  fi
fi
LOCAL_TRUNK="$(G rev-parse --verify -q "refs/heads/$TRUNK^{commit}" 2>/dev/null)"

# 2. A spec file's header, as the board needs it: one TSV row and its Owns lines.
#    The header ends at the first "## " heading; a placeholder value reads as unset.
read_header() { # <rev> <path> <source> <ref> <ct>  appends to rows and owns
  local rev="$1" path="$2" src="$3" ref="$4" ct="$5" base num slug
  base="${path#specs/}"; base="${base%.md}"
  num="${base%%-*}"; slug="${base#*-}"
  G show "$rev:$path" > "$W/spec" 2>/dev/null || cant "git show $rev:$(safe "$path") failed"
  awk -v src="$src" -v num="$num" -v slug="$slug" -v ref="$ref" -v ct="$ct" -v owns="$W/owns" '
    /^## / { exit }
    st == "" && /^Status:/ { v = $0; sub(/^Status:[[:space:]]*/, "", v); split(v, w, /[^A-Za-z]/); st = tolower(w[1]) }
    dr == "" && /^Driver:/ { v = $0; sub(/^Driver:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); if (v !~ /^</) dr = v }
    /^Owns: / { f = substr($0, 7); sub(/[[:space:]]+$/, "", f); if (f != "") print src "\t" num "\t" slug "\t" f >> owns }
    END { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", src, num, slug, st, dr, ref, ct }
  ' "$W/spec" >> "$W/rows"
}
: > "$W/rows"; : > "$W/owns"; : > "$W/record"

G ls-tree --name-only "$TRUNK_REV" specs/ > "$W/trunk-files" 2>/dev/null || cant "git ls-tree of the trunk's specs/ failed"
while IFS= read -r p; do
  [[ "$p" =~ ^specs/[0-9]+[a-z]*-.+\.md$ ]] || continue
  ct="$(G log -1 --format=%ct "$TRUNK_REV" -- "$p" 2>/dev/null)"
  read_header "$TRUNK_REV" "$p" trunk "$TRUNK" "${ct:-0}"
done < "$W/trunk-files"

RECORD_NOTE=""
if G cat-file -e "$TRUNK_REV:.claude/status.json" 2>/dev/null; then
  if G show "$TRUNK_REV:.claude/status.json" 2>/dev/null | jq -r '.specs // {} | to_entries[] | [.key, (.value.status // "")] | @tsv' > "$W/record" 2>/dev/null; then
    RECORD_NOTE="states from the trunk's status record"
  else
    : > "$W/record"; RECORD_NOTE="the trunk's status record does not parse, so states are read from the spec headers"
  fi
else
  RECORD_NOTE="no status record on the trunk, so states are read from the spec headers"
fi

while IFS="$(printf '\t')" read -r name sha; do
  [[ -n "$name" ]] || continue
  ct="$(G log -1 --format=%ct "$sha" 2>/dev/null)" || cant "git log of $(safe "$name") failed"
  bnum=""; [[ "$name" =~ ^spec/([0-9]+[a-z]*)- ]] && bnum="${BASH_REMATCH[1]}"
  found=0
  if [[ -n "$bnum" ]]; then
    # The branch's own spec file is the one its name carries. A branch cut from a
    # trunk that already holds another spec of its number carries that file too,
    # and it is the trunk's, not this branch's; so the named file is read, and
    # only when the branch holds none is every file of its number read.
    G ls-tree --name-only "$sha" specs/ > "$W/bfiles" 2>/dev/null || cant "git ls-tree of $(safe "$name") failed"
    own_file="specs/${name#spec/}.md"
    if grep -qxF "$own_file" "$W/bfiles"; then
      read_header "$sha" "$own_file" branch "$name" "$ct"; found=1
    else
      while IFS= read -r p; do
        [[ "$p" =~ ^specs/${bnum}-.+\.md$ ]] || continue
        read_header "$sha" "$p" branch "$name" "$ct"; found=1
      done < "$W/bfiles"
    fi
  fi
  bslug="${name#spec/}"; [[ -n "$bnum" ]] && bslug="${bslug#"$bnum"-}"
  [[ "$found" -eq 1 ]] || printf 'branch\t%s\t%s\t\t\t%s\t%s\n' "${bnum:--}" "$bslug" "$name" "$ct" >> "$W/rows"
done < "$W/branches"

# 3. The local trunk's numbers count toward the next number (a cut not yet pushed).
: > "$W/local-nums"
if [[ -n "$LOCAL_TRUNK" ]]; then
  G ls-tree --name-only "$LOCAL_TRUNK" specs/ 2>/dev/null | sed -nE 's#^specs/([0-9]+)[a-z]*-.*\.md$#\1#p' > "$W/local-nums"
fi

NEXT="$(cat "$W/local-nums" <(cut -f2 "$W/rows") <(cut -f1 "$W/record") | sed -nE 's/^([0-9]+).*/\1/p' \
  | awk 'BEGIN { m = 0 } { n = $1 + 0; if (n > m) m = n } END { printf "%04d\n", m + 1 }')"

if [[ "$MODE" == next ]]; then echo "$NEXT"; exit 0; fi

# 4. The units: one per (number, slug), the trunk's row first, its branch beside it.
UNITS="$(awk -F'\t' -v now="$NOW" -v stale="$STALE_DAYS" -v recf="$W/record" -v ownf="$W/owns" '
  function norm(n,   d, s) { d = n; sub(/[a-z]+$/, "", d); s = substr(n, length(d) + 1); return (d + 0) s }
  BEGIN {
    while ((getline l < recf) > 0) { split(l, r, "\t"); rec[norm(r[1])] = r[2] }
    while ((getline l < ownf) > 0) { split(l, o, "\t"); k = norm(o[2]) "\t" o[3]; if (!((k, o[4]) in seenown)) { seenown[k, o[4]] = 1; own[k] = (own[k] == "" ? o[4] : own[k] "\034" o[4]) } }
  }
  {
    k = norm($2) "\t" $3
    if (!(k in num)) { order[++n] = k; num[k] = $2 }
    if ($1 == "trunk") { ontrunk[k] = 1; hst[k] = $4; if ($5 != "") drv[k] = $5; tct[k] = $7 }
    else { br[k] = (br[k] == "" ? $6 : br[k] " " $6); if (bct[k] == "" || $7 > bct[k]) bct[k] = $7; if (bst[k] == "") bst[k] = $4; if (drv[k] == "" && $5 != "") bdrv[k] = $5 }
  }
  END {
    for (i = 1; i <= n; i++) {
      k = order[i]; split(k, kk, "\t"); nn = kk[1]
      if (ontrunk[k]) st = ((nn in rec) && rec[nn] != "" ? rec[nn] : hst[k]); else st = bst[k]
      if (st == "") st = "unknown"
      d = (drv[k] != "" ? drv[k] : bdrv[k])
      ct = (bct[k] != "" ? bct[k] : tct[k]); if (ct == "") ct = 0
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", num[k], kk[2], st, d, (ontrunk[k] ? "yes" : "no"), br[k], ct, own[k]
    }
  }' "$W/rows")"

if [[ "$MODE" == owns ]]; then
  want="$OWNS_SPEC"; [[ "$want" =~ ^[0-9]+[a-z]*$ ]] || cant "--spec wants a spec number, got $(safe "$want")"
  myslug="$(ls "$ROOT/specs/" 2>/dev/null | sed -nE "s/^0*${want#"${want%%[!0]*}"}-(.*)\.md$/\1/p" | head -n1)"
  hits="$(printf '%s\n' "$UNITS" | awk -F'\t' -v want="$want" -v mine="$myslug" -v f="$OWNS_FILE" '
    function norm(n,   d, s) { d = n; sub(/[a-z]+$/, "", d); s = substr(n, length(d) + 1); return (d + 0) s }
    NF == 0 { next }
    norm($1) == norm(want) && (mine == "" || $2 == mine) { next }
    !($3 == "active" || $6 != "") { next }
    { m = split($8, o, "\034"); for (i = 1; i <= m; i++) if (o[i] == f) { print; break } }')"
  if [[ -z "$hits" ]]; then
    echo "owns: no other spec on the trunk at ACTIVE, and no spec on a $( [[ -n "$REMOTE" ]] && safe "$REMOTE" || echo local) spec branch, declares $(safe "$OWNS_FILE") ($SOURCE_LINE)."
  else
    echo "owns: $(safe "$OWNS_FILE") is also declared by:"
    while IFS="$(printf '\t')" read -r n s st d _ b _ _; do
      echo "  - spec $(safe "$n")-$(safe "$s") ($st), driver $( [[ -n "$d" ]] && safe "$d" || echo unknown), $( [[ -n "$b" ]] && echo "branch $(safe "$b")" || echo "no branch on the remote")"
    done <<< "$hits"
    echo "  Both may proceed; the close refuses the second of two overlapping closes (SLH-OWNS-OVERLAP) until its branch carries the first close's change. The remedy then: merge the trunk into the second spec's branch, re-run the close and merge again. If the file changed hands, say so in both specs. This report refuses nothing. ($SOURCE_LINE)"
  fi
  exit 0
fi

# 5. The board.
echo "Setlist board (a read of the trunk and the remote; it refuses nothing)"
echo "$SOURCE_LINE"
tl="trunk: $(safe "$TRUNK") at $(G rev-parse --short "$TRUNK_REV" 2>/dev/null)"
if [[ -n "$LOCAL_TRUNK" && "$LOCAL_TRUNK" != "$TRUNK_REV" ]]; then
  ab="$(G rev-list --left-right --count "$LOCAL_TRUNK...$TRUNK_REV" 2>/dev/null)"
  [[ -n "$ab" ]] && tl="$tl; this clone's $(safe "$TRUNK") is ${ab%%[[:space:]]*} ahead and ${ab##*[[:space:]]} behind it"
fi
echo "$tl"
echo "$RECORD_NOTE; stale after $STALE_DAYS days ($STALE_NOTE)"
echo
printf '%s\n' "$UNITS" | awk -F'\t' -v now="$NOW" '
  NF == 0 { next }
  function age(ct,   s) { if (ct == 0) return "age unknown"; s = now - ct; if (s >= 86400) return int(s / 86400) " days"; if (s >= 3600) return int(s / 3600) " hours"; return "under an hour" }
  { st = toupper($3); line = "  " $1 "-" $2 "  driver " ($4 != "" ? $4 : "unknown") "  " ($6 != "" ? "branch " $6 : "no branch on the remote") ", last commit " age($7) " ago"
    if ($5 == "no") line = line "  (not on the trunk)"
    if ($8 != "") { o = $8; gsub("\034", " ", o); line = line "\n      owns: " o }
    out[st] = out[st] line "\n"; if (!(st in seen)) { seen[st] = 1; ord[++n] = st } }
  END {
    split("ACTIVE REVISED BUILT PARKED QUEUED DRAFT CLOSED", want, " ")
    for (i = 1; i <= 7; i++) if (want[i] in out) { print want[i]; printf "%s", out[want[i]]; done[want[i]] = 1 }
    for (i = 1; i <= n; i++) if (!(ord[i] in done)) { print ord[i]; printf "%s", out[ord[i]] }
  }' | while IFS= read -r l; do safe "$l"; echo; done

echo
echo "collisions it can see:"
COLL="$(printf '%s\n' "$UNITS" | awk -F'\t' -v now="$NOW" -v stale="$STALE_DAYS" '
  function norm(n,   d, s) { d = n; sub(/[a-z]+$/, "", d); s = substr(n, length(d) + 1); return (d + 0) s }
  function who(i) { return "spec " N[i] "-" S[i] " (driver " (D[i] != "" ? D[i] : "unknown") (B[i] != "" ? ", branch " B[i] : "") ")" }
  NF == 0 { next }
  { c++; N[c] = $1; S[c] = $2; ST[c] = $3; D[c] = $4; T[c] = $5; B[c] = $6; CT[c] = $7; O[c] = $8 }
  END {
    for (i = 1; i <= c; i++) for (j = i + 1; j <= c; j++)
      if (N[i] != "-" && norm(N[i]) == norm(N[j])) print "  - number: " N[i] " is claimed twice, by " who(i) " and " who(j) ". The first trunk landing owns the number; the other renumbers before it merges."
    for (i = 1; i <= c; i++) {
      if (ST[i] != "active") continue
      m = split(O[i], oi, "\034")
      for (j = i + 1; j <= c; j++) {
        if (ST[j] != "active") continue
        n2 = split(O[j], oj, "\034"); both = ""
        for (a = 1; a <= m; a++) for (b = 1; b <= n2; b++) if (oi[a] != "" && oi[a] == oj[b]) both = both " " oi[a]
        if (both != "") print "  - overlap: " who(i) " and " who(j) " both declare" both ". The close refuses the second of them until its branch carries the first close."
      }
    }
    for (i = 1; i <= c; i++) {
      if (T[i] == "no") print "  - not on the trunk: " who(i) " has a branch on the remote and no spec file on the trunk; its claim is visible only to a clone that reads the branch."
      if (ST[i] == "active" && B[i] == "") print "  - no branch: " who(i) " is ACTIVE on the trunk with no spec branch on the remote."
      if (ST[i] == "built") print "  - waiting to merge: " who(i) " is BUILT, complete on its branch, and its close is pending."
      if (ST[i] == "active" && CT[i] > 0 && now - CT[i] > stale * 86400) print "  - stale: " who(i) " has had no commit for " int((now - CT[i]) / 86400) " days (more than " stale "); the team round said what a stale claim becomes, and a released claim parks with a reason and a trigger."
    }
  }')"
if [[ -n "$COLL" ]]; then printf '%s\n' "$COLL" | while IFS= read -r l; do safe "$l"; echo; done; else echo "  (none)"; fi

echo
echo "ACTIVE per driver (a count, never a limit):"
PER="$(printf '%s\n' "$UNITS" | awk -F'\t' 'NF && $3 == "active" { d = ($4 != "" ? $4 : "unknown"); n[d]++ } END { for (d in n) print "  " d ": " n[d] }' | sort)"
if [[ -n "$PER" ]]; then printf '%s\n' "$PER" | while IFS= read -r l; do safe "$l"; echo; done; else echo "  (no ACTIVE spec)"; fi
echo
echo "next number: $NEXT (the highest on the trunk, this clone's trunk and the remote's spec branches, plus one)"
exit 0
