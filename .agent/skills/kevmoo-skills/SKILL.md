---
name: kevmoo-skills
description: |-
  Apply personal coding preferences and customized workflows for Kevmoo's
  repositories, including standard formatting, common boilerplate, and preferred
  tooling usage.
license: Apache-2.0
---

## 2. When to use this skill
- ALWAYS use these rules. If this rule is active, it's because the author
  (kevmoo) wants them applied.

## 3. How to use this skill
1.  **Analysis**: Review the codebase to understand the current context and
    identify areas where preferences can be applied.
2.  **Tooling/Dependencies**: Ensure any required personal tools or standard
    dependencies are present (or will be added gracefully).
3.  **Discovery/Grep**: Look for common anti-patterns or stylistic choices that
    diverge from the established preferences.
4.  **Implementation/Replacement**: Apply the specific formatting or code
    generation preferences detailed below.
5.  **Verification**: Ensure the code formatting is correct and tests (if any)
    are operational.

## 4. When editing or creating markdown files
- Try to make new files (and newly added lines) wrap to 80 columns.

## 5. Constraints
- **NEVER** use destructive or state changing `git` commands (`push` and
  `commit` are examples) without explicit approval.
- **NEVER** make sweeping architectural changes without explicit approval.
- **NEVER** run the `gh` command without explicit approval.

## 6. Before declaring yourself DONE with any Dart task
- Ensure all modified Dart files cleanly pass `dart format`.
- Ensure all modified Dart files pass `dart analyze`.
- Ensure all modified Dart files pass `dart test`.

## 7. Strategies for Discovery
- Identify test files: `find_by_name test "*_test.dart"`
