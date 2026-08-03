---
name: new-worktree
description: |-
  Creates and initializes a new Git worktree using specialized sibling location
  and naming rules. (Triggers on "/new-worktree")
key_features:
  - Git worktree setup
  - Sibling directory placement
  - Hard boundary checks for non-Git, outside ~/github, and Dart SDK
  - Automated branch and folder naming
---

## When to use this skill

Activate this skill when the user invokes `/new-worktree` or requests creating a
new Git worktree for parallel development, bug fixes, or new features.

## Pre-Flight & Hard Boundaries

Before creating any branch or worktree, verify the current working repository
against the following boundaries:

1. **Git Exclusivity**:
   - Must be a Git repository (`git rev-parse --is-inside-work-tree`).
   - If not using Git, stop immediately and alert the user.
2. **Repository Location (Must be under `~/github`)**:
   - Check the absolute file path of the repository root.
   - Repositories must reside under `~/github` (arbitrarily deep, such as
     `~/github/kevmoo/kevmoo_skills` or `~/github/repo`).
   - **Hard Block**: If the repository is located anywhere else, stop and issue
     a warning asking for explicit human confirmation before proceeding.
3. **Dart SDK Exception**:
   - Check if the repository maps to the Dart SDK
     (`https://github.com/dart-lang/sdk`, e.g., located at `~/github/dart-sdk`).
   - **Hard Block**: If operating in the Dart SDK repository, stop immediately
     and ask if the user wants to use their specialized Dart SDK flow instead
     (e.g., `dart-sdk-bootstrap`). Do not proceed without clarification.

## Location & Naming Conventions

When creating a worktree, observe strict placement and naming rules:

* **Location**: Place the new worktree directory right next to the source
  repository directory (as a direct sibling in the parent folder).
* **Worktree Naming**: Format the folder name as
  `_[original repo folder name]-[branch-name]`.
* **Branch Naming**: Derive a clean, hyphen-separated branch name from the user
  request (e.g., `issue-12345` or `fix-auth-crash`).

### Examples

- In `~/github/flutter`, invoking `/new-worktree to fix flutter issue #12345`:
  - Creates branch: `issue-12345` (or similar clean identifier based on request)
  - Creates worktree at: `~/github/_flutter-issue-12345`
- In `~/github/kevmoo/kevmoo_skills`, invoking `/new-worktree add lint check`:
  - Creates branch: `add-lint-check`
  - Creates worktree at: `~/github/kevmoo/_kevmoo_skills-add-lint-check`

## Execution Steps

1. Verify pre-flight boundaries and git cleanliness.
2. Formulate the recommended target branch name and sibling directory path.
3. Execute the worktree creation command:
   ```bash
   git worktree add -b <branch-name> <sibling-worktree-path>
   ```
4. Output a clickable link to the newly initialized worktree directory in chat.
