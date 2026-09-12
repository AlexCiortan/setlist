---
name: diagrams
description: "Diagrams as close-gated source: the routing test that picks a type, the drawing and truthfulness rules, altitude and layout, node evidence, the Design sketch at creation and the sync at close"
---

Condensed binding of Part 4's architecture-diagram section and the diagram
halves of Parts 3, 5, 6 and 8b. On any conflict the edition wins; load it with
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 4`. Type references load on
demand, only when you are drawing that type:
`${CLAUDE_PLUGIN_ROOT}/skills/diagrams/references/flowchart.md`,
`${CLAUDE_PLUGIN_ROOT}/skills/diagrams/references/sequence.md`,
`${CLAUDE_PLUGIN_ROOT}/skills/diagrams/references/state.md`,
`${CLAUDE_PLUGIN_ROOT}/skills/diagrams/references/er-and-class.md`,
`${CLAUDE_PLUGIN_ROOT}/skills/diagrams/references/comparison.md`.

**The switch, first, because everything mechanical below depends on it.** A
project is opted in when `docs/diagrams/` exists in the tree; then the close
checks in "At close" run. Absent, they do not run at all and the project
behaves exactly as it did before the diagram half existed. Opting in is a chore
of its own, never a side effect of an upgrade.

- **When to draw.** A diagram earns its place when a cold reader sees a
  mechanism they would otherwise assemble from prose. If a sentence says it
  faster, write the sentence.
- **What to draw.** The MECHANISM, not its name: the path a request takes, the
  boundary crossed, the hop added, the data that moves. As much as the decision
  turns on and no more. Comparing options: draw the DIFFERENCE, side by side,
  never two labeled boxes. One figure, one claim; a second claim is a second
  figure.
- **What a diagram may not do.** A diagram is a set of claims about the tree on
  the trunk, held to the standard a Closing report is held to. Never invent
  topology: no box for a component that does not exist, no arrow for a call
  that is not made, no boundary the code does not draw. Keep exact names: a
  node is named by the path or module it draws, an arrow by the protocol,
  command, API path or event it carries, exactly as the code spells it, never a
  paraphrase. Label every arrow, and drop a label only when both endpoints
  already state everything the label would (the protocol, the action, the
  direction, whether the call is synchronous, and any boundary crossed). **One
  sense per ARROW, named in its label**, not one sense per figure: any honest
  container view mixes an invocation with a read, and what is forbidden is an
  arrow whose sense the reader has to guess. Line
  ranges are not evidence: they are true at one commit and false at the next. A
  rendered image is never source. After the baseline, no wholesale re-scan
  replaces a diagram: diagrams are edited in closing commits.
- **Artifact first, twelve nodes.** Draw the candidate before reading any
  rendering detail: one main path, at most twelve primary nodes. Over twelve,
  split into a child under a directory named for the parent node. Twelve is
  reported at validate, never refused. **Where there is no child to split into,
  the bound is HARD**: a diagram inline in a README or an ADR has no
  `components/` directory beneath it, so the only way down to twelve is to cut a
  node, and cutting is the work. Cut the node whose absence costs the reader
  least, and say in the prose that it is not drawn.

## The routing test

| The question the reader has | The type | Where it lives |
|---|---|---|
| What are the pieces and which talk to which, including approval chains, CI and runbooks (the workflow question) and pipelines and lineage (the data-flow question, with `Encodes:` naming the rule the arrows assert) | `flowchart` | L2 in the document a reader opens (usually `steering/structure.md`), L3 under `docs/diagrams/components/` |
| What happens, in order, when X | `sequenceDiagram` | `docs/diagrams/flows/`, born in the spec's Design sketch |
| What states can this thing be in, with its retries and terminal outcomes (the lifecycle question) | `stateDiagram-v2` | beside the component it belongs to |
| What is the shape of the data | `erDiagram` or `classDiagram` | `structure.md`'s core-model section |
| What changes between two options | two small diagrams showing the DIFFERENCE | the spec's Design sketch, or an ADR |

Every row is subject to the first rule: if a sentence says it faster, write the
sentence.

## Altitudes and layout

L1 context (`docs/diagrams/context.md`), L2 containers (below), L3 components
(`docs/diagrams/components/<role-path>.md`, one file per role path or module,
named by the path it draws), L4 never hand-drawn
(`docs/diagrams/generated/`, from `diagram_command` where declared). Flows
promoted from specs live at `docs/diagrams/flows/<NNNN>-<slug>.md`. Diagrams are
Mermaid blocks inline in Markdown, one file per view, so each renders and diffs
on its own. **Every file under `docs/diagrams/` opens with the four-line
header** in `${CLAUDE_PLUGIN_ROOT}/templates/root/DIAGRAM-HEADER.md`:
`Shows:` one sentence, `Altitude:` L1, L2 or L3, `Synced by:` the spec that last
changed it, `Encodes:` the constraints the picture asserts.

**L2's home is the document a reader of this system actually opens.** For an
ordinary application that is the bottom of `steering/structure.md`, with the
core-model diagram beside its prose. For a project whose readers are not its
maintainers, a library or a tool whose own README is the front door, L2 belongs
in that README instead, and every rule here is unchanged by the move. One
container view exists, in one place; every other document links to it.

**A diagram inline in a document that is not a diagram file has no place to put
four header lines, so it folds them into the prose around the block.** The
sentences before the block say what it shows and at what altitude; the sentences
after say what it encodes, which is the line that separates a claim from
decoration; `Synced by:` is carried by the Closing report's diagram field, which
names the file the close touched. Folding the header is allowed. Dropping it is
not: a diagram with no `Encodes:` anywhere near it is asserting nothing.

## Node evidence

A node's drawn name is the path or module it draws (`auth["src/auth"]`), and the
close resolves it against the tree. **What is resolved is a DECLARATION's own
label**: the bracket or parenthesis pair attached directly to a node id, quotes
and shape punctuation stripped, which is how Mermaid spells the drawn name in
every type this test routes to; write the path there, not only in the node id.
Three drawn names exist and each is named as what it is in every message: a
`node`, a `subgraph id`, a `subgraph title`. **Nothing else on the line is a
drawn name**, and two cases are worth knowing because the check used to get them
wrong: text between the pipes of an edge label is never a node however it is
spelled, so `-->|"reads (src/gone.json), sync"| b` draws no node called
`src/gone.json`; and text after `%%` is a comment, so it draws nothing either.

**When a project draws the software it STAMPS rather than the software it runs**,
the nodes are the paths of a stamped instance, and the evidence behind them is
the stamp contract, never `git ls-tree` of the tree that carries the drawing. A
plugin, a generator or a scaffolding tool draws what its output looks like; the
drawing is true when the stamp really writes those paths, and whatever check
holds the stamp to its file list is what checks it. Such a project usually has no
`docs/diagrams/` of its own and is not opted in at all, which is exactly why the
rule is written down: nothing mechanical will catch a wrong node there.

A name counts as a path when it contains a slash and no whitespace: anything else
is not resolved, and every unresolved name is PRINTED rather than silently
skipped (`SLH-DIAGRAM-NODE-SKIPPED`, up to ten listed with a count beyond that),
so a label you meant as a path and spelled as prose comes back to you. A node a
spec introduces carries `%% spec NNNN` on its line, which is what decides whose
node a stale one is. Files under `docs/diagrams/generated/` are not scanned for
nodes: they are the command's output, not a drawing anyone signed.

Three spellings are NOT read, and they are stated here so you do not discover
them by being believed when you should not have been: the rhombus and hexagon
(`{...}`), the asymmetric (`>...]`), and a label separated from its id by a space
(`a ["src/a"]`). Use the shapes the type references show, with the bracket
against the id.

**Label your edges with the pipe form**, `-->|"text"|`, which every type reference
here teaches. Mermaid's other spelling, `a -- text --> b`, puts the text where
the reader cannot tell it from a declaration, so a path written inside it
(`a -- reads(src/gone.json) --> b`) is still read as a node and can refuse your
close for a node you never drew. The pipe form has no such hazard.

## At creation

The spec's optional `## Design sketch` section holds the intended change in the
routed type, under every rule above. It is what the owner approves and what the
Builder builds to; a build that departs from it is a scope deviation and is
recorded as one. An ADR gets the same block for the difference between two
options.

## At close

`/setlist:checkpoint` drafts the sync edit for the living diagrams the sketch
touches and writes the diagram field with the files NAMED; the sync edit rides
the closing commit, never a separate commit on the trunk. On an opted-in
project the close then refuses, at the merge hook, the trunk audit and the forge
check alike:

- `SLH-DIAGRAM-CLAIM`: the field claims `updated` and names a file the closing
  commit does not touch, or names nothing at all. A claim that names nothing
  cannot be checked.
- `SLH-DIAGRAM-UNDECLARED`: the field says `no impact` while the commit touched
  a file under `docs/diagrams/` or the Mermaid blocks in
  `steering/structure.md`.
- `SLH-DIAGRAM-STALE-NODE`: a node whose path does not exist in the tree under
  review. It REFUSES when `%% spec NNNN` names a spec this commit closes, and
  REPORTS otherwise, with the two honest exits for an older node: redraw it in
  this close and name the file in the field, or retire it with a note.
- With a `diagram_command` declared in `.claude/sdd.json`, `SLH-DIAGRAM-DRIFT`
  when the committed file under `docs/diagrams/generated/` differs from what the
  command prints, and `SLH-DIAGRAM-SHAPE` when the command fails, prints no
  Mermaid block, or the project commits none or more than one generated view.
- At the forge, `FC-DIAGRAM-RENDER` when a block does not parse under the pinned
  Mermaid version. Local hooks never render.

A flow worth keeping is promoted to `docs/diagrams/flows/` with `Synced by:` set;
a sketch that was only the change's scaffolding stays in the closed spec as the
record of what was intended.

## At validate

Three reports, never refusals: diagrams over twelve nodes; undiagrammed
ownership (role paths in closed specs' `Owns:` sets that no L3 diagram names);
stale nodes from earlier specs; and, where a `diagram_command` is declared,
generated edges no hand diagram draws.

## Every report and refusal names three things

The subject (the node, file or field), the measured evidence (what the tree or
the diff says), and the one-edit fix. A message that names a rule without naming
the evidence sends the reader back to the code to find out what happened.

## Gotchas (field-observed)

None recorded yet for this surface. Entries come from dogfood runs and instance
journals; nothing lands here without a real observed occurrence.
