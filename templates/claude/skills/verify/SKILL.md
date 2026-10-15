---
name: verify
description: Runs this project's full gate command from .claude/sdd.json and reports what it printed and its exit status. Claude Code asks for a skill of this name before a commit. It reports; the git hooks are what refuse.
---

Run this project's gate command once and report what it printed. This skill
changes nothing: it never edits a file, never stages, never commits, and
never runs the command a second time to get a different answer.

The gate is the one the git hooks run at a close: the `close` tier of the
`gates` block when `.claude/sdd.json` declares one, and `gate_command`
otherwise.

The run is delegated work (Part 2 of the committed edition, the delegated
tier): where the Agent tool is available, hand this block to a subagent with
`model: haiku`, which runs it once and returns its output verbatim; what the
result means for the commit stays with you. Where no subagent can be started,
run it yourself. Either way it is run once.

Run this block from the repository root, as written:

```bash
command -v jq >/dev/null 2>&1 || { echo "verify: jq is not on PATH, so the gate command could not be read. Install jq."; exit 2; }
g="$(jq -r 'if (.gates // null) == null then (.gate_command // "") elif ((.gates | type) == "object" and ((.gates.close // "") | type) == "string") then (.gates.close // "") else "!gates" end' .claude/sdd.json 2>/dev/null)"
[ "$g" != "!gates" ] || { echo "verify: the gates block in .claude/sdd.json is not an object of string tiers, so the gate could not be read. /setlist:validate names the fix."; exit 2; }
[ -n "$g" ] || { echo "verify: no gate command is recorded in .claude/sdd.json. /setlist:validate names the fix."; exit 2; }
out="$(mktemp)"
bash -c "$g" > "$out" 2>&1
rc=$?
tail -n 40 "$out"
rm -f "$out"
echo "verify: the gate command exited $rc"
exit "$rc"
```

Then report, in this order:

1. The last line, `verify: the gate command exited N`, quoted as printed.
2. The lines above it that explain a failure, quoted, never summarised into
   a verdict they do not state.
3. When N is not 0: say the gate is red now and that the commit should wait
   for a fix. Do not commit around it.

A `verify:` line that names jq or an empty gate command means the gate did
not run. Say so; it is not a pass.

This is the harness's own step before a commit, and it persuades. It is not
the boundary: the stamped `pre-commit` hook runs the commit gate on every
commit and the trunk audit reads history at every push, whether or not this
skill ran.

## Gotchas (field-observed)

None observed yet: this skill is new in plugin 2.12.0.
