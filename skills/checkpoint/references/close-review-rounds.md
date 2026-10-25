# The close review after a failing round 1 (plugin 2.11.0, Part 5)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

4. **Round 1 reads FAIL, or carries findings at MAJOR or above:** append those
   findings to the spec under `## Close review, round 1`, above the Closing
   report heading, one line each as the block writes them; fix them in
   commits; re-run the gate command; run the agent again as round 2 on the new
   diff; add its round to the SAME block beneath round 1, and its MAJOR-and-up
   findings under `## Close review, round 2`.
5. **Round 2 still reads FAIL: stop, and put the findings in front of the
   human.** There is no third round under any label. The human decides: merge
   past them, recorded as the block's last line
   `verdict: ACCEPTED-BY-HUMAN F2 F3` (every round-2 finding at MAJOR or
   above named, nothing round 2 does not carry), or revise the spec, or park
   it. Write that line only on the human's word, never on your own.
