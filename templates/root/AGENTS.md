# AGENTS.md

This project runs Setlist, spec-driven development enforced by git. This file is a
pointer for any coding agent that reads `AGENTS.md`. It holds no rules of its own,
so it cannot disagree with the files it names.

- Read `CLAUDE.md` first. It is this project's instructions for every agent, not
  only for Claude Code, and its golden rules bind you.
- The protocol is `setlist.md` at the repository root; `CLAUDE.md` says what to
  load and when.
- The current state and the next action are in `specs/STATUS.md`.

The git hooks in `.githooks/` enforce the same process whichever agent makes the
commit, or none: a commit, merge or push that skipped a spec is refused by git,
not by this file.
