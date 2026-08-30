#!/usr/bin/env bash
# spec-attest.sh - write and sign a spec's approval attestation (KL3).
#
# WHAT THIS IS FOR, and the sentence is load-bearing rather than decorative:
# a signature proves a KEY WAS USED, it does not prove a PERSON DECIDED. This
# script exists to be run in an INTERACTIVE session where a human is present,
# because that is the only moment at which the two coincide. A headless run
# that can reach the key can produce everything below and prove nothing about
# approval; the framework cannot stop that, so it makes the instance DECLARE
# where its key lives and prints that declaration at every verification.
#
# WHAT IT WRITES:
#   specs/attest/NNNN.json   the document, fixed schema, verdict APPROVED
#   specs/attest/NNNN.sig    a detached ssh signature over those exact bytes
#
# WHY NOT INSIDE THE SPEC FILE. The signature would live inside the bytes it
# signs, and making that work needs a second exclusion in the hashed range
# beside the `Spec-hash:` one. The existing exclusion needed a paragraph of
# justification in spec-hash.sh for exactly this reason, and two interacting
# exclusions in a hashed range is a place defects live.
#
# WHY NOT specs/NNNN-<slug>.<ext>. That namespace has produced two identity
# defects already (the leg's F6 sort-order find, and the SLH-SPEC-DUPLICATE
# family). Introducing a third file family into it is asking for the third.
#
# THE HASH IS scripts/spec-hash.sh's, called rather than reimplemented. The
# recipe has three implementations in deliberate lockstep and the suite pins
# that count; a fourth here would be a fourth thing that can drift, for no gain
# in a script that can always reach the plugin tree.
#
# Usage: spec-attest.sh <spec-file> [--key <path>] [--approver <identity>]
# Exit:  0 written and signed; 1 on a usage or input error; 3 when a required
#        tool is absent (reported, never silently skipped, per BL-001).

set -u

SPEC=""; KEY=""; APPROVER=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)      KEY="${2:-}"; shift 2 || exit 1 ;;
    --approver) APPROVER="${2:-}"; shift 2 || exit 1 ;;
    -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
    -*)         printf 'spec-attest.sh: unknown option %s\n' "$1" >&2; exit 1 ;;
    *)          SPEC="$1"; shift ;;
  esac
done

if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
  printf 'spec-attest.sh: no such spec file: %s\n' "${SPEC:-<none>}" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# THE NUMBER COMES FROM THE FILENAME, and it is checked rather than assumed:
# a spec file that does not carry a number in the shape the hooks look for
# would produce an attestation the verifier can never find, which is a silent
# no-op wearing a success message.
BASE="${SPEC##*/}"
NUM="${BASE%%-*}"
case "$NUM" in
  [0-9][0-9][0-9][0-9]*) ;;
  *) printf 'spec-attest.sh: %s does not begin with a spec number, so no attestation path can be derived\n' "$BASE" >&2; exit 1 ;;
esac

# The custody declaration is READ rather than assumed, and a project that has
# not declared one is told so instead of getting a document nothing will accept.
CUSTODY=""
if [ -f "$PROJ/.claude/sdd.json" ] && command -v jq >/dev/null 2>&1; then
  CUSTODY="$(jq -r '.attestation.custody // ""' "$PROJ/.claude/sdd.json" 2>/dev/null || printf '')"
fi
if [ -z "$CUSTODY" ]; then
  printf 'spec-attest.sh: .claude/sdd.json declares no attestation custody.\n' >&2
  printf '  Refusing rather than writing a document nothing will accept. Declare it:\n' >&2
  printf '    "attestation": {"required": true, "custody": "signer", "verify_with": ".claude/approvers.pub"}\n' >&2
  exit 1
fi
if [ "$CUSTODY" = "forge" ]; then
  printf 'spec-attest.sh: forge custody is DESIGNED AND NOT BUILT.\n' >&2
  printf '  Its verification is a query the forge answers and it lands with the\n' >&2
  printf '  forge-side required check, which is filed rather than promised. Nothing\n' >&2
  printf '  signed here would be accepted, so nothing is written. Use "signer" for a\n' >&2
  printf '  mechanism that works today.\n' >&2
  exit 1
fi

HASH="$(bash "$ROOT/scripts/spec-hash.sh" "$SPEC")" || HASH=""
if [ -z "$HASH" ]; then
  printf 'spec-attest.sh: could not compute the spec hash, so there is nothing to bind an approval to.\n' >&2
  printf '  A missing sha256 tool reports here rather than producing an attestation over an empty digest.\n' >&2
  exit 3
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  printf 'spec-attest.sh: ssh-keygen is required to sign and is not installed.\n' >&2
  exit 3
fi

# The identity written into the document is the identity the verifier looks up
# in the allowed-signers file, so it defaults to the committer's email: the two
# are the same person and a mismatch is the commonest first-run failure.
[ -n "$APPROVER" ] || APPROVER="$(git config --get user.email 2>/dev/null || printf '')"
if [ -z "$APPROVER" ]; then
  printf 'spec-attest.sh: no approver identity. Pass --approver, or set git user.email.\n' >&2
  exit 1
fi

PLUGIN_VERSION="$(jq -r '.version // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || printf '')"

mkdir -p "$PROJ/specs/attest"
DOC="$PROJ/specs/attest/${NUM}.json"
SIG="$PROJ/specs/attest/${NUM}.sig"

# The `spec` field is repo-relative, because that is what the verifier compares
# it against. An absolute path here would be a SUBJECT-MISMATCH on every
# machine but this one.
REL="${SPEC#"$PROJ"/}"
REL="${REL#./}"

cat > "$DOC" <<JSONEOF
{
  "setlist_attestation": 1,
  "spec": "$REL",
  "spec_number": "$NUM",
  "spec_hash": "$HASH",
  "verdict": "APPROVED",
  "approver": "$APPROVER",
  "custody": "$CUSTODY",
  "tool": "setlist/checkpoint",
  "tool_version": "$PLUGIN_VERSION",
  "at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "notes": ""
}
JSONEOF

# THE SIGNATURE IS NAMESPACED. A signature made with the same key for some
# other purpose must not verify as an approval, and the namespace is what makes
# that true rather than hoped.
if [ -n "$KEY" ]; then
  set -- -f "$KEY"
else
  set --
fi
if ! ssh-keygen -Y sign "$@" -n setlist-attestation "$DOC" >/dev/null 2>&1; then
  rm -f "$DOC"
  printf 'spec-attest.sh: ssh-keygen -Y sign failed, so no attestation was written.\n' >&2
  printf '  Pass --key <path-to-private-key>, or load the key into your agent first.\n' >&2
  printf '  Nothing partial is left behind: an unsigned document reads as an absent one\n' >&2
  printf '  to the verifier, which would be a refusal nobody could explain.\n' >&2
  exit 1
fi
mv "$DOC.sig" "$SIG"

printf 'spec-attest.sh: wrote %s and %s\n' "specs/attest/${NUM}.json" "specs/attest/${NUM}.sig"
printf '  spec:     %s\n' "$REL"
printf '  hash:     %s\n' "$HASH"
printf '  approver: %s\n' "$APPROVER"
printf '  custody:  %s\n' "$CUSTODY"
if [ "$CUSTODY" = "ci-secret" ]; then
  printf '  NOTE: ci-secret custody means a key the build process can reach. This\n' >&2
  printf '  establishes that a run had the key, NOT that a person approved. The\n' >&2
  printf '  verifier says so on every verification, including the ones that pass.\n' >&2
fi
printf '  Stage both files in the SAME commit as the ACTIVE flip and the Spec-hash.\n'
exit 0
