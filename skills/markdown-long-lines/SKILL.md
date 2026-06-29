---
name: markdown-long-lines
description: |-
  Ensure markdown prose lines wrap within 80 columns, excluding code blocks,
  URLs, and tables.
license: Apache-2.0
key_features:
  - Markdown formatting
  - 80-column line wrapping
  - Formatting exclusions
---

## 1. When to use this skill
Use this skill whenever editing or creating Markdown (`.md`) files in the
repository.

## 2. Line Wrapping Guidelines
- **Target Width**: Wrap prose text cleanly within 80 columns for new
  files and newly added lines.
- **Exceptions ("Within Reason")**: Do NOT wrap lines where breaking them would
  corrupt syntax or structure:
  - YAML frontmatter / metadata blocks
  - Fenced code blocks (`` ``` ``)
  - Long URLs or Markdown link destinations
  - Markdown tables

## 3. Clarifying Execution Scope
If the context or scope of how this skill should be run is vague, use the
`ask_question` tool to clarify the user's intent.

For example, ask whether formatting should apply to:
1. Just the currently active or specified file.
2. All new or modified Markdown files in the current session.
3. All Markdown files across the entire repository.
