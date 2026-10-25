# Instance skill flags (any instance stamped before plugin 1.6)

Read on demand from `/setlist:upgrade` (its SKILL.md names when). The edition wins on any conflict: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/part.sh" 8c`.

The generated skills (`.claude/skills/scaffold`, and `browser-qa` where
present) are instance-owned; the upgrade never rewrites their bodies.
Their frontmatter must still carry the manual-invocation flag Part 6 demands
("Mark them manual-invocation"): ensure each SKILL.md has
`disable-model-invocation: true`, adding the line when missing, and record the
touch-up in the umbrella ADR with the rest.
