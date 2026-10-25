# two-clones: provenance

Written for spec 0201 (item 9, the board's two-clone fixture), 2026-10-24, by hand.

Two spec files, `0002-alpha.md` and `0002-beta.md`: the same number cut under two slugs by two
clones of one instance, each carrying the `Driver:` line its clone's flip writes. The `Owns:`
line each clone appends on its branch (`src/shared.js`) is added by the suite, as the checkpoint
adds it during a build, so these files carry none.

Everything else is built by `test/suite/23-board-0201.sh`, region `two-clones-0201`, from the
real stamp: the instance, a bare remote on disk (no network), and the two clones. Clone A flips
0002-alpha on the trunk and pushes the trunk and its empty branch in one atomic push; clone B,
which never fetched, flips 0002-beta on its own trunk, has its push refused, and pushes its
branch alone. The board read from either clone names the number collision and the overlap with
both drivers.
