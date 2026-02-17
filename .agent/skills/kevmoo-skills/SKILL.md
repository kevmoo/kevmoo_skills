---
name: kevmoo-skills
description: |-
  Apply personal coding preferences and customized workflows for Kevmoo's repositories, including standard formatting, common boilerplate, and preferred tooling usage.
license: Apache-2.0
---

# kevmoo-skills

## When to use this skill
- When working within any repository owned by `kevmoo`.
- When the user specifically requests to apply "my preferences" or "standard setup".

## How to use this skill
1.  **Analysis**: Review the codebase to understand the current context and identify areas where preferences can be applied.
2.  **Tooling/Dependencies**: Ensure any required personal tools or standard dependencies are present (or will be added gracefully).
3.  **Discovery/Grep**: Look for common anti-patterns or stylistic choices that diverge from the established preferences.
4.  **Implementation/Replacement**: Apply the specific formatting or code generation preferences detailed below.
5.  **Verification**: Ensure the code formatting is correct and tests (if any) are operational.

## Common Patterns

### Prefer/Over

| Prefer | Over |
|---|---|
| Use `package:checks` for new tests | Using `package:matcher` |

## Constraints
- "NEVER make sweeping architectural changes without explicit approval."
- "Ensure all modified files cleanly pass `dart format`."

## Strategies for Discovery
- Identify test files: `find_by_name test "*_test.dart"`
