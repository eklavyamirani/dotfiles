---
description: Explain pasted code as quote-then-explain sections anchored to line numbers
argument-hint: "<pasted @path snippet>"
---
<!-- Body kept in sync across packages/common/.claude/skills/explain/SKILL.md,
     packages/common/.copilot/skills/explain/SKILL.md and packages/common/.pi/agent/prompts/explain.md;
     edit all three. -->
Explain the code in the input. The input starts with a `@path:START-END` header
and a fenced block whose lines are prefixed with their real line numbers in the
file. Those numbers are authoritative: reuse them, never renumber.

Format rules:

- Begin with a `## Purpose` section: what the code is for and why it exists.
  No line references here.
- Then one section per logical chunk, in file order. Heading form:
  `## @START-END short title`. Keep every chunk at 25 lines or fewer.
- Under each heading, first quote exactly those lines in a fenced block,
  keeping the line-number prefixes from the input. Then explain only those
  lines, referring to lines by number.
- Every input line must fall inside exactly one chunk. Blank lines may be
  absorbed into the neighbouring chunk.
- End with a `## Notes` section for anything that spans chunks: pitfalls,
  edge cases, how the pieces interact, and questions the code leaves open.
- Do not edit files or run commands. Reading the referenced file for
  surrounding context is fine.

Input:

$@
