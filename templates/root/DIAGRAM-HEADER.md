# <the view's name: what this file draws, in two or three words>

Shows: <one sentence: the mechanism a reader sees here that prose would make them assemble>
Altitude: <L1 context | L2 containers | L3 components>
Synced by: <the spec number that last changed this file; for the first seed, "bootstrap" on a new project, "retrofit" on a retrofitted one, or "chore diagram-baseline" on an upgrade>
Encodes: <the constraints this picture asserts, for example "nothing writes to the store except src/etl">

```mermaid
<one Mermaid block, in the type the diagrams skill's routing test picks>
```

<!-- The four lines above are the header, and they are not decoration.

     All four are read by people. The `Synced by:` line also does one job for
     the checks: a file under `docs/diagrams/` that carries it is what arms the
     diagram checks at the close. Its value is never read by a check; what the
     close reads is the Closing report's `Architecture diagram:` field. Keep the
     header when you edit the block: a diagram whose header names a spec from
     three closes ago is telling you it was edited without being re-thought.

     Node names are the path each node draws, inside the brackets, quoted
     (`auth["src/auth"]`). The close resolves that text against the tree, so a
     name with a slash and no whitespace is CHECKED and anything else is
     printed as unverified. A node a spec introduces carries `%% spec NNNN` on
     a line of its own directly above the node (Mermaid reads a `%%` comment
     only on a line of its own), which is what decides whose node a stale one is.

     One figure, one claim; one main path; at most twelve primary nodes. Over
     twelve, split into `components/<parent>/<child>.md` rather than growing.

     Delete this comment when you fill the file in. -->
