# BUILT and PARKED transitions (Part 5)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

Two inventory states for work that is finished on its branch and not on the
trunk. Both are recorded in STATUS.md in the same commit as the state change,
like every other transition.

- **BUILT**: complete on its branch, close pending.
- **PARKED**: deliberately paused, unmerged. **A PARKED row states its reason
  AND its revisit trigger.** A parked row with neither is not a decision, it is
  an abandoned branch wearing a label; refuse to write one without both.

Resuming a PARKED spec re-validates the branch against the trunk as it exists
NOW, before it may continue toward close. Rebase it, or re-run the gate
command against it and say so. The trunk moved while the branch slept, and the
close checklist in SKILL.md is about to assert a green full suite that was last true
against a different trunk.

When closing anything, remember that a PARKED spec's work is NOT on the trunk.
Do not describe it as done in STATUS.md's current state, and name it in the
exclusions of any release cut.
