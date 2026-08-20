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
# Exit:  0 and the digest on stdout; 1 on a missing file; 3 when no sha256 tool
#        exists (the caller decides what that means, per BL-001's rule that a
#        dependency which cannot run is reported, never silently skipped).

set -u

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

awk 'BEGIN { keep = 1 }
     /^##[[:space:]]*Closing report/ { keep = 0 }
     keep' "$SPEC" \
  | grep -v '^[-*+[:space:]]*Spec-hash:' \
  | HASHER \
  | cut -d' ' -f1
