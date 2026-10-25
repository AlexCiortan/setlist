#!/usr/bin/env bash
# spec-hash.sh - compute the BL-005 integrity hash of a spec file.
#
# WHAT IT HASHES, and every exclusion is load-bearing:
#
#   from the file's FIRST LINE through the line immediately preceding the
#   "## Closing report" heading, with the `Spec-hash:` field line itself
#   removed, sha256 over those bytes exactly as they sit on disk.
#
# The Closing report is excluded because it is APPENDED during the build by
# design; including it would make every honest build read as drift, which is the
# fastest way to teach somebody to ignore a warning. The "## Changelog" section
# sits below Closing report in the template, so it is excluded with it.
#
# THE Spec-hash FIELD ITSELF IS EXCLUDED, and the intake spec did not say so
# because the problem only appears once you try to write the value: the field
# lives in the spec header, which is inside the hashed range, so hashing it would
# change the thing being hashed. Excluding the line makes writing the value
# idempotent, which is what lets the writer and the checker agree at all.
#
# LOCKSTEP: templates/hooks/regrounding-hook.sh implements this same recipe
# INLINE, because a stamped hook runs inside an instance and cannot depend on the
# plugin tree being reachable. Two implementations is a risk this repo has been
# bitten by, so the test suite drives BOTH over a corpus of fixtures and asserts
# they produce identical digests. That is a behavioural lockstep rather than a
# string comparison, which is the right kind here: the two are deliberately
# written differently and must agree on OUTPUT.
#
# Usage: spec-hash.sh <spec-file>
#        spec-hash.sh --refresh-owns <spec-file>
# Exit:  0 and the digest on stdout; 1 on a missing file; 3 when no sha256 tool
#        exists (the caller decides what that means, per BL-001's rule that a
#        dependency which cannot run is reported, never silently skipped).
#        --refresh-owns: 0 after writing and reporting; 1 after refusing, nothing written.
#
# --refresh-owns (spec 0203, M-4 of the 2.13.0 cycle). With attestation off, checkpoint's `Owns:`
# appends drift the spec's own hash, because they sit inside the hashed range by design, and a
# refresh by hand left no trace (the 2.13.0 cold run refreshed it twice). This mode compares the
# working spec's hashed range with the one committed at HEAD, both without the Spec-hash line. It
# writes the new digest only when the committed spec was in step with its recorded hash and every
# difference is an APPENDED `Owns:` line, and it prints each appended file and both digests, so the
# drift is reported where the engineer reads it. Any other difference is the drift the field exists
# to show: refused, nothing written, the REVISED route named.

set -u

# BYTES, NOT CHARACTERS (spec 0169). This is the WRITE side of the hash the
# git-hook library verifies, and that verifier reads bytes since 0169: under a
# UTF-8 locale macOS awk aborted on a byte that is not valid UTF-8 and this
# hashed a truncated text, which the verifier would then call stale.
LC_ALL=C; export LC_ALL

REFRESH=0
if [[ "${1:-}" == "--refresh-owns" ]]; then REFRESH=1; shift; fi
SPEC="${1:-}"
if [[ -z "$SPEC" || ! -f "$SPEC" ]]; then
  printf 'spec-hash.sh: no such spec file: %s\n' "${SPEC:-<none>}" >&2
  exit 1
fi

# macOS ships shasum, Linux ships sha256sum, and a container may have neither.
if command -v sha256sum >/dev/null 2>&1; then
  HASHER() { sha256sum; }
elif command -v shasum >/dev/null 2>&1; then
  HASHER() { shasum -a 256; }
else
  printf 'spec-hash.sh: neither sha256sum nor shasum is available\n' >&2
  exit 3
fi

hashed_range() { # the bytes the digest covers, from stdin
  awk 'BEGIN { keep = 1 }
       /^##[[:space:]]*Closing report/ { keep = 0 }
       keep' \
    | grep -v '^[-*+[:space:]]*Spec-hash:'
}

if [[ "$REFRESH" -eq 0 ]]; then
  hashed_range < "$SPEC" | HASHER | cut -d' ' -f1
  exit 0
fi

refuse() { printf 'spec-hash.sh: NOT REFRESHED: %s Nothing was written.\n' "$1" >&2; exit 1; }
DIR="$(cd "$(dirname "$SPEC")" && pwd)" || refuse "cannot enter the spec's directory."
TOP="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)" || refuse "$SPEC is not inside a git repository, so there is no committed spec to compare with."
REL="$(git -C "$DIR" ls-files --full-name -- "$(basename "$SPEC")" 2>/dev/null)"
[[ -n "$REL" ]] || refuse "$SPEC is not tracked, so there is no committed spec to compare with."
W="$(mktemp -d "${TMPDIR:-/tmp}/spec-hash.XXXXXX")" || refuse "no scratch directory."
trap 'rm -rf "$W"' EXIT
git -C "$TOP" show "HEAD:$REL" > "$W/committed" 2>/dev/null || refuse "HEAD carries no $REL to compare with."
OLD="$(grep -m1 '^[-*+[:space:]]*Spec-hash:' "$SPEC" | sed -E 's/^[-*+[:space:]]*Spec-hash:[[:space:]]*//; s/[[:space:]]+$//')"
[[ -n "$OLD" ]] || refuse "$SPEC carries no Spec-hash: field; checkpoint writes it at the ACTIVE flip."
COMMITTED_HASH="$(hashed_range < "$W/committed" | HASHER | cut -d' ' -f1)"
[[ "$COMMITTED_HASH" == "$OLD" ]] || refuse "the committed spec already reads drifted from its recorded Spec-hash ($OLD against $COMMITTED_HASH), so this is not a refresh after Owns: appends. The route is REVISED with Planner sign-off."
hashed_range < "$W/committed" > "$W/before"
hashed_range < "$SPEC" > "$W/after"
diff "$W/before" "$W/after" > "$W/diff" 2>/dev/null
grep -E '^[<>]' "$W/diff" > "$W/changed" || true # fail-open-ok: no changed line is grep's exit 1, the "nothing appended" answer read below, never a pass
grep -q '^<' "$W/changed" && refuse "the spec changed beyond appended Owns: lines since its last commit (a line was removed or edited: $(grep -m1 '^<' "$W/changed" | cut -c3-100)). That is the drift the field exists to show; the route is REVISED with Planner sign-off."
OTHER="$(grep '^>' "$W/changed" | grep -v '^> Owns: ' | head -n1 | cut -c3-100)"
[[ -z "$OTHER" ]] || refuse "the spec changed beyond appended Owns: lines since its last commit (added: $OTHER). That is the drift the field exists to show; the route is REVISED with Planner sign-off."
if ! grep -q '^>' "$W/changed"; then
  printf 'spec-hash.sh: nothing to refresh: no Owns: line was appended since the last commit, and the recorded Spec-hash %s is current.\n' "$OLD"
  exit 0
fi
NEW="$(HASHER < "$W/after" | cut -d' ' -f1)"
awk -v old="$OLD" -v new="$NEW" '!done && /^[-*+[:space:]]*Spec-hash:/ { sub(old, new); done = 1 } { print }' "$SPEC" > "$W/spec" \
  && cat "$W/spec" > "$SPEC" || refuse "the new digest could not be written into $SPEC."
printf 'spec-hash.sh: Spec-hash REFRESHED after Owns: appends (attestation off), reported so the drift is seen:\n'
grep '^> Owns: ' "$W/changed" | sed 's/^> /  appended: /'
printf '  Spec-hash: %s -> %s\n' "$OLD" "$NEW"
