# The long checks of /setlist:validate: 18, 21, 22 and 24

Read on demand: the list in SKILL.md names each check and points here for its full text. Numbers match SKILL.md's. The edition wins on any conflict: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 9`.

18. **The git-hook boundary is LIVE** (Part 6). The guarantee is the push-time
    trunk audit, the per-merge hooks are its early warning, and all three parts
    below have to hold for either to run at all:
    - `.githooks/` exists and carries `pre-commit`, `pre-merge-commit`,
      `pre-push` and `setlist-hook-lib.sh`, and the three hooks are
      EXECUTABLE. Git skips a non-executable hook silently, so a mode bit is
      the difference between a boundary and a decoration.
    - `git config core.hooksPath` is `.githooks`. Without it git runs
      `.git/hooks` and every file above is inert.
    - `git config merge.ff` is `false`. Without it a fast-forward merge fires
      NO hook at all and walks unreviewed work onto the trunk.
    Any of the three missing is a FINDING, not information. Unlike the release
    block or the identity key, this is not opt-in, and an instance that has lost
    it is running with the advisory layer only while the edition says otherwise.
    Both config settings live in `.git/config`, which is not cloned, so a fresh
    clone legitimately lacks them and the fix is to re-run the refresh.
    Report what is missing and the exact command that restores it.
    - **The trunk audit's declared baseline** (`audit.baseline` in
      `.claude/sdd.json`, edition v1.18). The audit walks from the commit that
      introduced `.claude/sdd.json` unless this key declares another, and for an
      instance whose hooks arrived LATER than its stamp the default is not
      merely imprecise: every merge in between was made when no
      `pre-merge-commit` existed to record a completion, so the audit refuses
      every push and calls those commits "made after this instance adopted the
      rules". Two directions, both REPORT-ONLY. **Ask the audit's own
      question, never re-derive it:** run
      `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-instance.sh" .` in REPORT
      mode (no `--apply`; it writes nothing) and quote its
      `.claude/sdd.json audit.baseline` line, which is computed by
      `slh_baseline_frame`, the same function the trunk audit runs (edition
      v1.19, spec 0167).
      - **Present**: the key is usable when it resolves to a commit here and is
        an ancestor of the recorded trunk; the audit walks from the oldest
        commit on the trunk's own first-parent line that contains it (the
        declared commit itself, or the merge that brought it in), and the line
        names that frame. It should equal what the refresh writes: the commit
        that added `.githooks/pre-push`, or, when the refresh is delivering the
        boundary now and no such commit exists yet, the trunk's tip at that
        moment. Any other usable value is a DECLARATION that differs from what
        the refresh would write: say so, name both commits and how many merges
        lie between them, and leave it alone. A value the audit cannot use at
        all (not a full 40-character lowercase-hex id, a present value that is
        not a string, unresolvable, or not an ancestor of the trunk) is the same
        report with the refusal the line names, because that instance is
        refused at every push until it is corrected.
      - **Absent** while `.githooks/pre-push` was added in a LATER commit than
        `.claude/sdd.json` (compare the two with
        `git log --root --diff-filter=A --format=%H -- <path> | tail -n1`):
        that is a FINDING. Name the refresh as the fix and the value it would
        write, because this is the instance that is refused at every push.
        Absent with the two arriving together is correct and not a finding: the
        default is the same commit.

21. **The two wiring files the refresh never replaces** (2.6.0, spec 0132, the
    owner's ruling 2 of 2026-09-07). `.github/workflows/setlist-forge-check.yml`
    and `.github/CODEOWNERS` are delivered by `/setlist:upgrade`'s refresh when
    ABSENT and LEFT AS IS when they differ from the plugin's templates, because
    both are the team's wiring (a runner label, a matrix; the `@OWNER` slot and
    the paths the team adds). A silent leave is refused the same way a silent
    replace is: report, BY FILE, which of the two differs from its template
    (`cmp -s` against `${CLAUDE_PLUGIN_ROOT}/templates/root/.github/workflows/
    setlist-forge-check.yml` and `${CLAUDE_PLUGIN_ROOT}/templates/root/github/
    CODEOWNERS.tmpl`). The ownership file differing is INFORMATION once its slot
    is filled (a standing `@OWNER` slot is check 8's finding), with one clause
    the refresh's report carries too: a file that does not name the
    fourth protected path `/.github/` (ratification amendment 5, 2026-09-07:
    the check's own workflow, the ownership file and the issue form) leaves
    the check's wiring an unreviewed change, so say so by path and recommend
    the line under the team's own owner; the refresh never adds it. The workflow
    differing is INFORMATION naming the file, and a FINDING only when its edited
    form no longer runs the stamped check (`.claude/hooks/forge-check.sh` absent
    from its command line), because then the required check named `setlist
    forge check` verifies nothing. Either file ABSENT is a finding recommending
    `/setlist:upgrade`, which delivers it. Replace neither yourself.

22. **The diagram reports** (projects with `docs/diagrams/`). Where the
    directory does not exist, report nothing: the project has not opted in, and
    check 6 above is the whole diagram check for it. Where it does exist, these
    are REPORTS and never findings that block anything, because each has a
    truthful answer that is "not yet" and the close is where refusal belongs:
    - **Over twelve nodes.** Any diagram file whose Mermaid block draws more
      than twelve primary nodes. Name the file and the count, and recommend the
      split (`docs/diagrams/components/<parent>/<child>.md`). Twelve is a
      drawing bound, never a refusal. For a diagram drawn INLINE in a document
      that is not a diagram file there is no child to split into, so recommend
      cutting a node instead of recommending a split that cannot be made.
    - **Undiagrammed ownership.** Role paths appearing in closed specs' `Owns:`
      lines that no L3 diagram names as a node. Name the paths; they are the
      parts of the system no picture claims anything about.
    - **Stale nodes from earlier specs.** Node names that are path-shaped and do
      not resolve in the tree, whose `%% spec NNNN` is not the current work.
      Name the node, the file, and the spec that introduced it, with the two
      legitimate exits: redraw it in a close that names the file in the diagram
      field, or retire it with a note. The close refuses only the CLOSING
      spec's own stale nodes, so these are the ones that accumulate unnoticed.
    - **Generated edges no hand diagram draws**, where `diagram_command` is
      declared: edges present in `docs/diagrams/generated/` that appear in no
      hand-drawn file. Each is either a real dependency nobody drew or a
      generated artifact worth ignoring, and saying which is the reader's call.
    Report each as a list with its subject, the measured evidence, and the
    one-edit fix, which is the message shape the whole diagram half uses.
24. **The model binding answers now** (Part 2's third fact under the bindings
    table; plugin 2.11.0). Where `.claude/settings.json` sets `"model":
    "opusplan"`, say first, before anything runs, that this check spends two
    short headless sessions of the user's quota (measured at about 0.21 USD for
    the pair on 2026-09-29), then run
    `bash "${CLAUDE_PLUGIN_ROOT}/scripts/model-probe.sh"` and quote its lines.
    It probes the plan phase and the execution phase of `opusplan` and prints
    the model each served, and a `served <phase> <id>` line per phase. Where
    `.claude/sdd.json` records `models` (the ids the bootstrap probe read,
    plugin 2.12.0 and later), compare each live id with the recorded one and
    name a change ("planning: recorded <id>, served now <id>"): a report, not
    a finding, unless the family left its tier (rc 1 below). Where nothing is
    recorded (an instance stamped before 2.12.0, whose answer was a yes or a
    no), say so and print the live ids; never read an old answer in place of
    this check. rc 1
    (`[MP-PLAN-OFF-TIER]` or `[MP-EXEC-OFF-TIER]`) is a finding: a phase was
    served by a model outside its tier's family, which a managed allowlist
    changed after the stamp (exact version matching, or a denied model) or a
    provider that does not serve the family can cause, since the harness
    substitutes a blocked model rather than refusing it; report the phase, the
    model and the script's sentence, and fix nothing. rc 2
    (`[MP-PROBE-UNAVAILABLE]`, `[MP-FAMILY-UNREADABLE]`) is a report with its
    reason, never a pass. A served version older than the one Part 2's table
    names, in the right family, is a line, not a finding: the table names the
    alias. Where the model line is absent or names something else, say the
    check did not run and why. Then read the model this check's own delegated
    run was served (the delegation journal line above): where it is not a
    Haiku 5 model, say which Haiku generation served it, as a line and never
    a finding, because `haiku` resolves to an earlier generation on some
    providers (Part 2's Delegated work row).
