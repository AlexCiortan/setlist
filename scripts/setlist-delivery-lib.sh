#!/usr/bin/env bash
# setlist-delivery-lib.sh - the ONE definition of hook-layer ownership, sourced
# by every delivery script that can touch core.hooksPath.
#
# WHY THIS FILE EXISTS AS A FILE. The displacement guard was written into
# refresh-instance.sh on 2026-08-07, corrected there on 2026-08-11 (F6: it
# decided by the directory's NAME), and stamp.sh never had it at all, which the
# B1 fixture matrix then measured: a retrofit onto a husky project moved
# core.hooksPath with no warning and no refusal, switching that project's own
# hook layer off, secret scanning included (B2 inbox item 1). A rule with more
# than one reader that is written more than once is how `slh_role_paths`
# drifted, so the rule moves HERE and both readers source it. One definition,
# and the behavioural corpus that proves both readers agree is the delivery
# matrix (cells 1.6/2.6) beside the suite's refresh block (F6a/F6b): the same
# fixture shapes driven through both delivery paths.
#
# CONTRACT. The caller defines GITHOOKS_SRC (the directory holding the shipped
# git-hook files) before calling hooks_layer_is_ours. Sourcing this file from a
# tree where it is missing must be a HARD failure in the caller: a guard that
# silently fails to load is a guard that silently stops guarding.

# DECIDED BY WHAT IS THERE, NOT BY WHAT IT IS CALLED (leg F6, 2026-08-11), AND
# "THERE" MEANS WHAT EXECUTES (2.0.0 leg, F6 again).
#
# The corrected-away version read `case ... in ""|".githooks")`, which treats
# the NAME .githooks as proof the layer is Setlist's. Its replacement then
# repeated the same defect one level down: `grep -q 'setlist-hook-lib.sh'`
# treats the MENTION of our library's name anywhere in a file as proof the file
# is ours, and the 2.0.0 leg defeated it with an ordinary shellcheck-exclusion
# line (`grep -v setlist-hook-lib.sh`) in a repo that vendors its hooks. The
# project's own gitleaks-style pre-commit was claimed as ours and overwritten,
# surviving only as a .setlist-backup.
#
# So the question is now POSITIONAL: a file is ours when it is byte-identical
# to a shipped hook, or when a SETLIST ARTIFACT (setlist-hook-lib.sh or
# trunk-audit.sh, the two things a stamped hook exists to run) appears where
# the shell would LOAD or EXECUTE it. The second 2.0.0 leg's F6 priced the
# first cut of this rule: it knew a source target and a standalone path word,
# and pre-push resolves the library with BOTH candidates on one
# `for cand in "A" "B"; do` line, so the release read its OWN pre-push as
# foreign and every upgrade of an armed instance dead-ended. The loading
# shapes, drawn from every shipped version of the hooks rather than from the
# current one:
#   - a source target:      . path/setlist-hook-lib.sh   source ...
#   - a standalone word:    "$X/trunk-audit.sh" \        (multi-line resolvers)
#   - a one-line resolver:  for cand in "..A" "..B"; do  (quoted candidates)
#   - an exec position:     bash "$AUDIT" / exec ...     (matched via resolver)
# A name appearing as DATA in another command's argument list (grep -v, echo,
# an ls-files pipeline) is still nobody's, and comment lines are stripped
# before the question is asked at all.
# OWNERSHIP IS A SET OF BYTES, NOT A GRAMMAR (fix round 3, adversary rounds 1
# and 2). Two cold reviews broke every text-based reading of "does this file
# load our artifact": each widening admitted argument data (bash lint.sh
# --skip trunk-audit.sh; a usage string; diff arguments; a project script that
# happens to be NAMED trunk-audit.sh), and each tightening refused our own
# hooks (a one-line resolver; a variable load; a trailing comment). That is
# the session-gate parser history replayed inside the guard, and this
# repository froze those parsers for exactly this reason. So the question is
# no longer textual. A hook file is OURS when its content hash is in the set
# of bytes this project has ever shipped for templates/git-hooks/ (every
# historical blob, listed below), or when it is byte-identical to the current
# shipped file. Nothing else is ours: an operator-ADJUSTED copy refuses with
# the file named, a backup discipline, and SETLIST_ADOPT_HOOKSPATH=1 as the
# one-step deliberate escape, because a refusal with an escape is a decision
# point while a text guess in either direction is a displaced secret scanner
# or a dead-ended upgrade. The suite asserts this list SUPERSET-MATCHES the
# repository history whenever it runs where history is visible, so a hook
# edit that forgets the list goes red in the same commit.
#
# Regenerate with:
#   git rev-list --all -- templates/git-hooks/ | while read c; do
#     git ls-tree "$c" -- templates/git-hooks/ | awk '{print $3}'; done | sort -u
KNOWN_SETLIST_HOOK_BLOBS="
  0326524f01f9623f18697f70786caa7a1c6ef72a
  06fd04c5d37ad3090db54f0f70b42606eab403f6
  08984561d53358607871714a18929b9899d1d2c2
  08d608fb8f98fb55dc5dd14fc4c817c3dfeb7865
  0bf5eb5046e001fa172a6518f26aebada88f3142
  0d9d144c5e35cfab30da797553c9f62d134f3569
  10651bbabacc4f869df2bf33c6bf88c5be491678
  15579621fbdb1f087dccb9829e511c96c52310b2
  1578dd280f57509d9725b8e6e08622cc95f3d312
  1f3bdb65e7bc5631149becc4fb3275b0baa12205
  21854101f1f3b45dbee79a63ca056f3b646a5382
  218c69bab893c2cc0ddbff50b024a6d84b01f15f
  232238199c974f0934baa2a75fb5354c9c126400
  24e971f9a02e09cecf953e058261433005b5c48f
  273d972c024696cda2bb8b9e4d09e4c7cbbd093e
  2fa342875311a7c729c29c97391d7b088500e29d
  2fecc00b5aab7389b166297d2f2bad021f0e9b44
  38cb4ab923026d28cec8a6fd255130d79b2798df
  3ae334d46d650e475321ca45c238e4d0ccfb9ce2
  3b1b9f3cc6b28c8c489e5ef5638c4d2d1c192c2e
  3c28085106a28d0f702f38e1085ea2171e75ac2e
  3d93c09e2ef84b402bd12b0db41d11edee33fcec
  3e8b104037d5041f9c5f2a0b6eb7251fed9180bf
  40404ed202ece2281ff503e7a97752b7c5a43361
  443f190847f3e906100ada460377abf9279e8dfa
  511bedb9c0b76a263906e87d1df30b08e597756e
  52894d17c6b98c0090361eb1a088c48b13b2250d
  58c265ee69e75527019f54ab1100bf0f005af29a
  5c3fb0c539909ce0957b1022ce72c08cadc20dfa
  63d48b8ef0e5b8f83ba4714f4c55e66e9971d6c0
  666703b0e9620d97576b6fd89ef5f0fe494a4516
  686a664c39aead88732229faae7ed4b94965a6ec
  6dfa99b6db2ebc84e90cfce2afd7a258b35ad365
  72400713d8b2d983dca18cd429584d264feedaf1
  72c493c4efc0fff1ada3e08994ba66045586bed6
  74e89b10b1267a9121259efc74a8bb8cae68a49b
  78fa9bfb0c6993bfe099c79f59695a906e5088bd
  8033cecd2c5ef2d71d93c91290355a01b98baf40
  8143b3e141e2fea8fc05e670fe390ff489739afd
  863b17e62981998e133aefd56c6a502b2cf22893
  8724f49175ab23a5c4564ec8805f5b368c49c812
  87e0c147ab413a6448675703d4a16b9e7fc7436a
  88a0bee7cd7b87e16919b757f9459d66e1d77801
  9478cd01ac826ca76eba7cc5d70d5d757e2b90eb
  9688b068204336deb362544f1ada4ccd97295797
  9874a864da96911453f6a93bd6b68c96d7759904
  9a036eb59bafbb3419ae203a65747d5e75687f3f
  9af7847c3fab1034a8448bf02f803dc40ea715ad
  9b92bb74a1e712a3fcc84ecde53f808ce93e9d3e
  9c4fe54859c172a3f9c22e0052187313681e2514
  a1fdc709d53f51bc549aebfa20c435bf89a992ae
  a2e27865122d2e95c1c234eeb18db5f906a0f341
  a685d66fa27bdc811a1a9a399b1a24bcb1fd75cc
  a7f29237e44d8ac94c5d50ecedd4b437fb6b07b4
  ae7005fcb67218805f0b3204021262338a2f5e1c
  b22af64dbce051cc9fa11e216fd42a0c3458be35
  b3e4d0098bbd1a7c05d336ca0740fbfd460d5e84
  b69e19d89648cce6e40050630fcb74b8ae5dfe73
  b9356dbdb37071944f58d32509e049cc840d2539
  bd61d21baed1260515f98e3b00af4a2aa26fa107
  c2b8593fc2548511903ba64d6f8ce0ba79aaaf84
  c633f8baa92c3f7fc8fcc3cb6f566e35e7e78696
  c7093ce9e66780cb69f8c44ac229a92c7f4b7235
  c980712cb1ab00df02c36736bd68c9f191dc8436
  ce7a2f074dc8b06ee77d7e2607d3595af6f06062
  d0357a24dc6281d9150c904ff788cee0858997cb
  d0539d590e452562410b26c14c6d3cc619183b94
  de7d0187ab42e1ab8125b071557f777e62a37aeb
  e5869e22fcc64af7364ab2364956554578f010a1
  e7a86d35fca1b4fddf4e2e192ef49103d2b98672
  eac8743342281e4edfe17be7052e713f28f405c2
  efa609a541ca0889abe8d5cadd995fffe6308f82
  f0952180586961a397d6d462f3a54f69444572ee
  f101f2b99cb562255d6c5d0d5a8f663298af55a4
  f3efaa77bbfae2f5c36e89d127bd98520f0c40bf
  f458bc15090e880a4795ec8502077cecd84f151b
  f87c78c62f2a925a3ac52adabf740d5d061aba60
  fb240463618c7b16025c217e75b833437f6c8512
  ff54ee3f1de169584ad16713ba79cf561c5d8d66
"

# THE HASH IS COMPUTED, NEVER ASKED OF GIT (adversary round 3, findings 1-2).
# `git hash-object` inherits the CALLER'S repository context: inside a
# --object-format=sha256 repo it returns 64-hex values that can never match a
# SHA-1 list, and a repo with clean filters (git-crypt, lfs) hashes the
# FILTERED bytes, so the same file got opposite verdicts depending on the
# operator's cwd. A git blob id is just sha1("blob <len>\0" + bytes), so it
# is computed here from the file's real bytes with no git, no repo discovery,
# no filters and no locale: same file, same answer, from any directory.
setlist_hook_blob_is_known() { # setlist_hook_blob_is_known <file> -> 0 when the content hash is a shipped Setlist hook
  local f="$1" size b
  [[ -f "$f" && -r "$f" ]] || return 1
  size="$(wc -c < "$f" 2>/dev/null)" || return 1
  size="${size//[[:space:]]/}"
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  if command -v shasum >/dev/null 2>&1; then
    b="$({ printf 'blob %s\0' "$size"; cat "$f"; } | shasum -a 1 2>/dev/null | awk '{print $1}')"
  elif command -v sha1sum >/dev/null 2>&1; then
    b="$({ printf 'blob %s\0' "$size"; cat "$f"; } | sha1sum 2>/dev/null | awk '{print $1}')"
  else
    return 1
  fi
  [[ "$b" =~ ^[0-9a-f]{40}$ ]] || return 1
  case "$KNOWN_SETLIST_HOOK_BLOBS" in *"$b"*) return 0 ;; esac
  # A CRLF working copy of our own bytes is still our own bytes (round 6,
  # finding 2): git's eol=crlf / core.autocrlf rewrites the checkout, so the
  # raw hash misses. Retry against the content with CRLF folded to LF. Round
  # 10, finding 3 tightened this: the fold strips a CR only at END OF LINE,
  # never a lone mid-line CR, because a lone CR is an ordinary shell word
  # character (`--cached\r` is a different, broken argument) and `tr -d` would
  # have squashed it, letting a behaviourally-different hook whose secret scan
  # is dead hash as ours. Line-ending-only normalization cannot change what a
  # hook does.
  if LC_ALL=C grep -q $'\r' "$f" 2>/dev/null; then
    local nsize nb
    nsize="$(awk '{ sub(/\r$/, ""); print }' "$f" | wc -c)"; nsize="${nsize//[[:space:]]/}"
    if command -v shasum >/dev/null 2>&1; then
      nb="$({ printf 'blob %s\0' "$nsize"; awk '{ sub(/\r$/, ""); print }' "$f"; } | shasum -a 1 2>/dev/null | awk '{print $1}')"
    else
      nb="$({ printf 'blob %s\0' "$nsize"; awk '{ sub(/\r$/, ""); print }' "$f"; } | sha1sum 2>/dev/null | awk '{print $1}')"
    fi
    case "$KNOWN_SETLIST_HOOK_BLOBS" in *"$nb"*) return 0 ;; esac
  fi
  return 1
}

hooks_layer_is_ours() { # hooks_layer_is_ours <dir> -> 0 when nothing foreign runs there
  local d="$1" f base
  [[ -d "$d" ]] || return 0
  # A directory the guard CANNOT LIST is not a directory it may vouch for
  # (adversary round 3, finding 4): chmod 000 on a site-owned hooks dir made
  # the glob fail, the loop never ran, and a LIVE foreign layer read as ours.
  # The unresolvable-spelling rule, one level down: cannot see means refuse.
  [[ -r "$d" && -x "$d" ]] || return 1
  for f in "$d"/*; do
    # Only what git would actually RUN can be a control that gets displaced.
    # Git looks hooks up by EXACT, dot-free names (githooks(5): pre-commit,
    # pre-push, commit-msg, ...), so a basename containing a dot is never a
    # hook: that one fact of git's own contract excludes the .sample files a
    # fresh `git init` leaves behind (executable on most platforms), our own
    # .setlist-backup leavings from a previous refresh, and the library file
    # itself (setlist-hook-lib.sh), which is sourced by hooks and run by
    # nothing. Without the exclusion an upgraded instance carrying an older
    # library would read as foreign and every upgrade would dead-end. A
    # non-executable file is likewise not a layer: git skips it in silence.
    [[ -f "$f" && -x "$f" ]] || continue
    base="${f##*/}"
    case "$base" in *.*) continue ;; esac
    # Ours if byte-identical to the current shipped file, or if its content
    # hash is a blob this project ever shipped (any version's unmodified
    # stamp). An adjusted copy is deliberately NOT ours: it refuses with the
    # file named and the SETLIST_ADOPT_HOOKSPATH=1 escape.
    [[ -f "$GITHOOKS_SRC/$base" ]] && cmp -s "$GITHOOKS_SRC/$base" "$f" && continue
    setlist_hook_blob_is_known "$f" && continue
    return 1
  done
  return 0
}

# foreign_hookspath <repo-dir> -> prints the location a foreign hook layer runs
# from, or nothing when there is nothing to displace. Two cases, because git
# runs hooks from two places and arming Setlist silences both:
#
#   - core.hooksPath SET: git runs that directory; setting it to .githooks
#     replaces it. Resolution is git's own rule (relative against the top of
#     the working tree, absolute as given) and the configured VALUE is printed.
#   - core.hooksPath UNSET: git runs $GIT_DIR/hooks, which is where
#     `pre-commit install` and `lefthook install` wire themselves (both leave
#     hooksPath unset; pre-commit refuses to install when it is set). Setting
#     hooksPath makes git ignore that directory ENTIRELY, so unset-but-occupied
#     is the displacement case the 2.0.0 leg proved (F2): the guard's early
#     return on unset was exactly the two most common tools' wiring. The
#     default directory's path is printed.
# THE VALUE IS RESOLVED THE WAY GIT RESOLVES IT (second 2.0.0 leg, F7). git
# expands a tilde in core.hooksPath and runs the layer there; the first cut of
# this guard treated the value as repo-relative, built <repo>/~/.githooks,
# found nothing, and silently displaced the layer README promises to refuse,
# with report mode calling the setting unset. Raw on one side and normalized
# on the other is the slh_trunk lesson recurred in a path, so the guard now
# asks GIT for the resolved value (`--type=path` performs git's own tilde
# expansion), falls back to expanding `~` itself where an older git lacks the
# flag, and strips trailing slashes before comparing. What is PRINTED stays
# the configured spelling, because messages should name what the operator can
# see in `git config`.
# The adversary's second pass priced two more resolution gaps. A RELATIVE
# value is resolved by git against the TOP OF THE WORKING TREE, not against
# whatever directory the instance argument names, so an instance in a
# subdirectory read <instance>/<value>, found nothing, and displaced the
# repository's real layer silently. And the manual fallback expanded `~/` but
# not `~user/`, which git also honours; a value this function cannot resolve
# is now printed as EMPTY, and the caller treats unresolvable as FOREIGN,
# because a guard that cannot see a layer must refuse rather than assume it
# is not there.
setlist_resolve_hookspath() { # setlist_resolve_hookspath <repo> <raw-value> -> the directory git would use, or empty for UNRESOLVABLE
  local repo="$1" hp="$2" dir top
  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: outside a work tree the instance path itself is the only anchor and is used below
  [[ -n "$top" ]] || top="$repo"
  dir="$(git -C "$repo" config --type=path --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: an older git without --type=path yields empty and the manual expansion below covers the tilde
  if [[ -z "$dir" ]]; then
    dir="$hp"
    # shellcheck disable=SC2088  # the quoted tilde is DELIBERATE: this branch matches the literal spelling git stores in config and expands it by hand, precisely because nothing here should rely on shell tilde expansion
    case "$dir" in
      "~") dir="$HOME" ;;
      "~/"*) dir="$HOME/${dir#"~/"}" ;;
      "~"*) printf ''; return 0 ;;
    esac
  fi
  case "$dir" in /*) ;; *) dir="$top/$dir" ;; esac
  while [[ "$dir" == *"//"* ]]; do dir="${dir//\/\///}"; done
  while [[ "$dir" == *"/./"* ]]; do dir="${dir//\/.\///}"; done
  [[ "$dir" == */. ]] && dir="${dir%/.}"
  while [[ "$dir" == */ && "$dir" != "/" ]]; do dir="${dir%/}"; done
  printf '%s' "$dir"
}

# hooks_layer_foreign_entries <dir> -> the basenames the ownership test would
# refuse on, one per line, so a refusal can NAME what it is protecting instead
# of gesturing at a directory (adversary round 3, finding 3's message half).
hooks_layer_foreign_entries() { # hooks_layer_foreign_entries <dir>
  local d="$1" f base
  [[ -d "$d" ]] || return 0
  if [[ ! -r "$d" || ! -x "$d" ]]; then printf '%s\n' "(directory unreadable)"; return 0; fi
  for f in "$d"/*; do
    [[ -f "$f" && -x "$f" ]] || continue
    base="${f##*/}"
    case "$base" in *.*) continue ;; esac
    [[ -f "$GITHOOKS_SRC/$base" ]] && cmp -s "$GITHOOKS_SRC/$base" "$f" && continue
    setlist_hook_blob_is_known "$f" && continue
    printf '%s\n' "$base"
  done
  return 0
}

# setlist_active_hooks_dir <repo> -> the directory git actually runs hooks
# from, resolved (set value via git's own resolution; unset means the default
# $GIT_DIR/hooks). Callers that need to NAME what a refusal protects resolve
# through this instead of re-deriving (round 5, finding 1: the entries call
# re-anchored an instance-relative default at the worktree top and named
# "unresolvable").
setlist_active_hooks_dir() { # setlist_active_hooks_dir <repo-dir>
  local repo="$1" hp dir
  hp="$(git -C "$repo" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: empty falls to the default branch below
  if [[ -n "$hp" ]]; then
    setlist_resolve_hookspath "$repo" "$hp"
    return 0
  fi
  dir="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null || true)" # fail-open-ok: no repo means no hooks run anywhere
  [[ -n "$dir" ]] || return 0
  case "$dir" in /*) ;; *) dir="$repo/$dir" ;; esac
  printf '%s' "$dir"
}

# setlist_refusal_dir <repo> <printed-value> -> the directory a refusal about
# <printed-value> is protecting. The printed value serves two masters: the
# operator (who sees what git config shows) and the caller's entries listing
# (which needs a real directory). Round 8, finding 2: both callers resolved
# the printed value through the ACTIVE layer, so a refusal about the arming
# TARGET listed the entries of a directory that was ours and printed
# 'unresolvable' over files that were present and readable.
setlist_refusal_dir() { # setlist_refusal_dir <repo> <printed-value>
  local repo="$1" printed="$2" top
  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: empty falls through to the generic resolution
  if [[ "$printed" == ".githooks" && -n "$top" && -d "$top/.githooks" ]]; then
    printf '%s' "$top/.githooks"
    return 0
  fi
  case "$printed" in
    /*) printf '%s' "$printed" ;;
    *)  setlist_resolve_hookspath "$repo" "$printed" ;;
  esac
}

foreign_hookspath() { # foreign_hookspath <repo-dir>
  local repo="$1" hp dir top __hooks_exempt_ok=yes
  hp="$(git -C "$repo" config --get core.hooksPath 2>/dev/null || true)" # fail-open-ok: unreadable yields empty and the DEFAULT directory is then asked instead, so nothing is skipped
  if [[ -n "$hp" ]]; then
    dir="$(setlist_resolve_hookspath "$repo" "$hp")"
    # THE ALREADY-ARMED EXEMPTION (adversary round 3, finding 3). When the
    # resolved directory IS the arming target (<worktree-top>/.githooks),
    # setting core.hooksPath to .githooks changes nothing about what git
    # runs: a foreign commit-msg sitting beside our hooks there KEEPS
    # running, our-named files are replaced WITH BACKUPS and named in the
    # report, and nothing is switched off. Refusing here told the operator to
    # move their checks into the directory they were already in, and
    # dead-ended every refresh of an armed instance that had gained one extra
    # hook (git-lfs install does exactly this). Displacement requires the
    # arm to CHANGE where git looks.
    if [[ -n "$dir" ]]; then
      top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: no work tree means no arming either
      if [[ -n "$top" && "$dir" == "$top/.githooks" ]]; then
        # ...but only for hooks under names the delivery does NOT touch. A
        # foreign file at pre-commit / pre-merge-commit / pre-push WOULD be
        # replaced by the copy loop, and a control that stops running because
        # we overwrote it is displaced however the config reads (the suite's
        # F6a fixture is exactly this). Extra names (commit-msg, lfs's
        # post-checkout family) keep running untouched, so they are exempt.
        # ...and only over a directory the guard can actually LIST: a
        # mode-300 .githooks made the entries helper print its unreadable
        # placeholder, which matches no delivered name, and the exemption
        # waved through a layer the ownership test would have refused
        # (round 4, finding 2). Blindness voids the exemption the same way
        # it voids ownership.
        [[ -r "$dir" && -x "$dir" ]] || __hooks_exempt_ok=no
        local __e __foreign_delivered=""
        while IFS= read -r __e; do
          case "$__e" in pre-commit|pre-merge-commit|pre-push) __foreign_delivered="$__foreign_delivered $__e" ;; esac
        done <<< "$(hooks_layer_foreign_entries "$dir")"
        [[ -n "$__foreign_delivered" || "${__hooks_exempt_ok:-yes}" == "no" ]] || return 0
      fi
    fi
    if [[ -z "$dir" ]]; then
      # Unresolvable spelling: the guard cannot look at what git would run, so
      # it cannot claim the layer is ours. Fail CLOSED and name the spelling.
      printf '%s' "$hp"
      return 0
    fi
    # A CONFIGURED directory that is ABSENT is the same blindness one step
    # over (round 5, finding 5): an unmounted volume or a bootstrap-created
    # dir means the guard cannot see what will run when it returns, and the
    # first cut vouched for it, repointed the config, and destroyed the
    # operator's value silently. Absent-when-configured fails CLOSED, with
    # ONE exception (round 6, finding 1): when the absent directory IS the
    # arming target (<top>/.githooks), it is ours to create, nothing can run
    # from a directory that does not exist, and refusing blocked the exact
    # mkdir that repairs an armed instance whose .githooks was cleaned away.
    # Only the DEFAULT directory may be absent without meaning anything.
    if [[ ! -d "$dir" ]]; then
      top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: no top means the exception cannot apply and the refusal below stands
      if [[ -n "$top" && "$dir" == "$top/.githooks" ]]; then
        return 0
      fi
      printf '%s' "$hp"
      return 0
    fi
    if ! hooks_layer_is_ours "$dir"; then
      printf '%s' "$hp"
      return 0
    fi
    # The active layer is ours but lives elsewhere: arming still repoints to
    # the target, so the target must be inspected too (round 7, finding 1).
    top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: no top, no arming
    if [[ -n "$top" && "$dir" != "$top/.githooks" ]]; then
      setlist_arming_target_foreign "$repo"
    fi
    return 0
  fi
  dir="$(git -C "$repo" rev-parse --git-path hooks 2>/dev/null || true)" # fail-open-ok: no git or no repo means nothing runs hooks at all, so there is nothing to displace
  [[ -n "$dir" ]] || return 0
  case "$dir" in /*) ;; *) dir="$repo/$dir" ;; esac
  if ! hooks_layer_is_ours "$dir"; then
    printf '%s' "${dir#"$repo"/}"
    return 0
  fi
  setlist_arming_target_foreign "$repo"
  return 0
}

# THE ARMING TARGET IS INSPECTED BEFORE IT IS ARMED (round 7, finding 1). The
# guard asked only what RUNS TODAY (the configured layer, or the default
# directory), never what arming would SWITCH ON: a fresh clone of a project
# that ships a tracked .githooks/ has core.hooksPath unset (config never
# clones), the retrofit kept the project's own pre-commit by collision rule,
# and the run printed ARMED with a foreign hook live as the boundary and any
# dormant extra-name hook (commit-msg) silently activated. Whenever the
# active layer is NOT the target, a populated target containing ANY file that
# is not ours refuses: for delivered names because we would be presenting a
# foreign gate as our boundary, and for extra names because arming would
# switch on hooks that do not run today. This is deliberately stricter than
# the already-armed exemption one function up, where extra-name hooks are
# ALREADY running and arming changes nothing.
# setlist_boundary_dir_unsafe <repo> -> prints a reason when <top>/.githooks
# cannot safely RECEIVE the delivered boundary, or nothing when it can (round
# 11, findings 1 and 5). git resolves core.hooksPath through a symlink, so a
# .githooks that is a symlink to a shared directory would have Setlist write
# its four hook files, a backup and a chmod THROUGH the link, outside the
# repository, replacing same-named files there, while reporting ARMED. A
# dangling symlink is the same class one step over. The boundary must be a
# real directory tracked IN the repository; a symlink of any kind refuses.
setlist_boundary_dir_unsafe() { # setlist_boundary_dir_unsafe <repo>
  local repo="$1" top target
  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: no work tree means no delivery either
  [[ -n "$top" ]] || return 0
  target="$top/.githooks"
  if [[ -L "$target" ]]; then
    printf 'the boundary directory %s/.githooks is a SYMLINK (to %s); git would resolve it and Setlist would write the boundary through it, outside the repository. The boundary must be a real directory tracked in the repository. Remove the symlink, or point core.hooksPath at a real .githooks.' "${target#"$repo"/}" "$(readlink "$target" 2>/dev/null || echo 'a missing target')"
  fi
  return 0
}

# setlist_hook_dest_unsafe <path> -> prints a reason when a per-hook
# destination cannot receive our file, or nothing (round 11, finding 2). A
# hook name that is a DIRECTORY makes cp write INTO it (.githooks/pre-commit/
# pre-commit), the -x executability guard passes the directory, and git then
# fatals on every commit while the run reports the hook delivered.
setlist_hook_dest_unsafe() { # setlist_hook_dest_unsafe <dest-path>
  if [[ -d "$1" && ! -L "$1" ]]; then
    printf '%s exists and is a DIRECTORY, so the hook body cannot be written there; git would fail every commit. Remove it, then re-run.' "$1"
  fi
  return 0
}

# THE ONE WRITE RULE (2026-08 consolidation, leg F1's class closed as a class).
# Every file Setlist writes into an instance outside .githooks/ goes through
# these two functions. The .githooks/ loops keep their own leg-pinned inline
# discipline (rounds 8, 9 and 11: dangling links removed with a note, live
# links converted to regular files with a backup), because the boundary's job
# is to DELIVER and a refusal there would leave the guarantee layer stale.
# The advisory copies and the stamped tree have no such duty, so for them a
# symlink of ANY kind at, or on the way to, a destination REFUSES: cp and >
# both resolve links, so writing through one lands our bytes at whatever path
# the link chooses, possibly outside the instance entirely, destroying a
# foreign file under a success message. Measured on the shipped bytes
# (2026-08-19 leg, F1): a 63-byte file outside the instance became the
# 107,776-byte close gate through a symlink at .claude/hooks/close-gate.sh.
#
# setlist_deliver_dest_unsafe <root> <rel-dest> -> prints a reason when the
# destination cannot safely receive a write, or nothing when it can. Checks
# every path component below <root>, not only the final name: a symlinked
# .claude/ or .claude/hooks/ directory redirects the write exactly like a
# symlinked file one level down (the setlist_boundary_dir_unsafe class,
# generalised).
setlist_deliver_dest_unsafe() { # setlist_deliver_dest_unsafe <root> <rel-dest>
  local root="$1" rel="$2" p="$1" rest="$2" comp
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$comp" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
    [[ -n "$comp" ]] || continue
    p="$p/$comp"
    if [[ -L "$p" ]]; then
      printf '%s is a SYMLINK (to %s); writing through it would land the file at a path this instance does not control, replacing whatever lives there. Nothing was written through it. Remove the link (the linked file is untouched), then re-run.' \
        "${p#"$root"/}" "$(readlink "$p" 2>/dev/null || echo 'a missing target')"
      return 0
    fi
  done
  if [[ -d "$p" ]]; then
    printf '%s exists and is a DIRECTORY, so the file cannot be written there. Remove it, then re-run.' "${p#"$root"/}"
  fi
  return 0
}

# setlist_deliver_file <src> <root> <rel-dest> -> 0 delivered (any note on
# stdout), 1 refused or failed (the reason on stdout, nothing written through
# a link). A differing existing file is backed up first and the backup is
# NAMED, the .githooks/ rule: a backup nobody is told about is the same data
# loss one directory over.
setlist_deliver_file() { # setlist_deliver_file <src> <root> <rel-dest>
  local src="$1" root="$2" rel="$3" reason dest
  dest="$root/$rel"
  reason="$(setlist_deliver_dest_unsafe "$root" "$rel")"
  if [[ -n "$reason" ]]; then printf '%s' "$reason"; return 1; fi
  if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest"; then
    # THE BACKUP PATH IS A DESTINATION TOO (2026-08 consolidation, second
    # adversary round). The dest guard above cleared "$rel"; it said nothing
    # about "$rel.setlist-backup", and `cp "$dest" "$dest.setlist-backup"`
    # RESOLVES a symlink pre-placed there, writing the old file over whatever
    # the link points at (a foreign file outside the instance) and then
    # printing "the previous file is kept at ...setlist-backup", which is
    # false. A symlink at the backup path refuses exactly like one at the
    # destination: the same rule, asked of the sibling it was not asked of.
    local backup_reason
    backup_reason="$(setlist_deliver_dest_unsafe "$root" "$rel.setlist-backup")"
    if [[ -n "$backup_reason" ]]; then printf '%s' "$backup_reason"; return 1; fi
    if ! cp "$dest" "$dest.setlist-backup"; then
      printf 'could not back up %s before replacing it; the previous file is still in place and was NOT replaced.' "$rel"
      return 1
    fi
    printf '%s differed and was replaced; the previous file is kept at %s.setlist-backup\n' "$rel" "$rel"
  fi
  if ! cp "$src" "$dest"; then
    printf 'could not write %s; whatever was there before is still in place.' "$rel"
    return 1
  fi
  return 0
}

setlist_arming_target_foreign() { # setlist_arming_target_foreign <repo> -> prints .githooks when the target holds foreign files
  local repo="$1" top target
  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)" # fail-open-ok: no work tree means no arming either
  [[ -n "$top" ]] || return 0
  target="$top/.githooks"
  [[ -d "$target" ]] || return 0
  if ! hooks_layer_is_ours "$target"; then
    printf '%s' ".githooks"
  fi
  return 0
}
