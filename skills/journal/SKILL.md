---
name: journal
description: Write the numbered journal entry for a substantive session per Part 4 (raw notes, what surprised you, no narrative smoothing)
argument-hint: "[session subject, e.g. spec 0042 build]"
---

Write the journal entry for this session per Part 4 of the committed edition
(the `journal/` section). This command is a thin binding: on any conflict
between this file and the edition, the edition wins. When in doubt, load the
Part: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 4`

## When an entry is owed

One numbered file per substantive session: a multi-hour build, a non-trivial
planning decision, a QA pass that found real issues, a migration or gate
transition. Not a five-minute chore. Substantive work done on another surface
(the design project, Part 5c) lands as a companion entry, numbered in the same
sequence, written from that surface's own record. Any deliberate deviation
from the declared working mode (a model experiment, a process trial) gets one
line stating the intent: the repo cannot tell drift from experiment; that
line can.

## The entry

- Next sequential number in `journal/` (`NNNN-<slug>.md`), same namespace as
  the existing entries; a bare number is never a valid reference, so cite as
  `journal/NNNN` elsewhere.
- Role split, kept strict: STATUS.md is canonical current state; the journal
  is the diary. What happened, what surprised you, what dead ends you tried,
  what you would change about the spec with hindsight. Nothing in the entry
  substitutes for the STATUS.md, Closing-report, or ADR updates the session
  already owes.
- Style: raw notes, no narrative smoothing, no em-dashes (as everywhere).
  Sections like "the actual session," "what surprised me," "what the spec got
  right / was silent on," "what I'd change in the spec now." Honest about
  what did not work. Audience: future-you and future sessions, not external
  readers.
- Historical text relocated into an entry moves verbatim under a dated
  provenance banner (Part 4, Historical text); never edit the moved text.
- Update the STATUS.md pointer to the latest journal entry in the same
  commit.

## Gotchas (field-observed)

- Session narratives are not evidence. Agent accounts of hook and gate
  interactions have confabulated (a whole-command deny narrated as a partial
  success). When an entry records an enforcement event, write what the repo
  shows (branch, status, checksums), not what the session said happened.
- Name the scanner honestly when an entry records one. A scan that matches
  token-shaped strings is a token-shape scan, not a secret scan; writing the
  stronger name into the record is how a later reader inherits a guarantee
  nobody made. The same goes for "the suite passed" when what ran was a subset.
- Quoted history keeps its punctuation. Pasted verifier output, upstream text
  and relocated documents are evidence of what was written then; the em-dash
  rule is forward-only and governs what this project writes now. Do not
  "correct" quoted material into compliance, and if a path must hold such
  content verbatim, scope the scan by path rather than weakening it.
