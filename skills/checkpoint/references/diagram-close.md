# The diagram half at the close (projects with docs/diagrams/)

Read on demand from `/setlist:checkpoint` (its SKILL.md names when). The edition wins on any conflict.

Drafting the diagram field's file list at the close: the field is never pre-filled,
and what you MAY draft is the file list the answer will need. Read the branch's diff
for files under `docs/diagrams/` and for changed Mermaid blocks in
`steering/structure.md`, and offer them as the parenthesised list for a person to
accept or correct. The answer stays theirs; the list is evidence you gathered, and
naming it saves them a refusal at the merge.

None of this runs where `docs/diagrams/` does not exist; there the close behaves
exactly as it did before, and the presence of the directory is what arms it.
Where it does exist, before you merge:

- **Draft the sync edit, do not perform it silently.** Read the spec's
  `## Design sketch` if it has one, name the living diagrams it touches
  (`docs/diagrams/context.md`, the L2 block in its home, usually
  `steering/structure.md`, the L3
  file for each role path in the spec's `Owns:` list), draft the edit for each,
  and let the human approve. The edit rides THIS closing commit; a diagram
  synced in a separate commit on the trunk both breaks the Git rules and opens a
  window where the trunk lies about itself.
- **Promote a flow worth keeping** to `docs/diagrams/flows/<NNNN>-<slug>.md`
  with `Synced by:` set to the closing spec. A sketch that was only the change's
  scaffolding stays in the closed spec and is promoted nowhere.
- **Update `Synced by:`** in every diagram file the close changes. It is the one
  header line the checks read.

The three refusals the close can now draw, at the merge hook, the trunk audit
and the forge check alike. Name the one that will fire BEFORE the merge, because
saying so here is cheaper than a refused merge:

- `SLH-DIAGRAM-CLAIM`: the field claims `updated` and names a file this commit
  does not touch, or names nothing at all.
- `SLH-DIAGRAM-UNDECLARED`: the field says `no impact` while the commit touched
  a file under `docs/diagrams/` or the Mermaid blocks in
  `steering/structure.md`.
- `SLH-DIAGRAM-STALE-NODE`: a node whose drawn path does not exist in the tree
  under review AND whose `%% spec NNNN` names a spec this commit closes. The
  same node from an EARLIER spec is reported, not refused, with two legitimate
  exits: redraw it in this close and name the file in the field, or retire it
  with a note. Node names that are not path-shaped (no slash, or containing
  whitespace) are printed as unverified rather than skipped in silence
  (`SLH-DIAGRAM-NODE-SKIPPED`); read that list, because a path you meant and
  spelled as prose appears in it.

Where the project declares `diagram_command` in `.claude/sdd.json`, the close
also runs it and requires the single committed file under
`docs/diagrams/generated/` to equal what it prints (`SLH-DIAGRAM-DRIFT`), and
refuses `SLH-DIAGRAM-SHAPE` when the command fails, prints no Mermaid block, or
the project commits none or more than one generated view. Re-run the command and
commit its output as part of the closing commit.

The record does not change for any of this: `.claude/status.json` keeps
`"diagram": "updated"` or `"no-impact"` and gains no key. The file list lives in
the Closing report's field text, which is where the hooks read it.
