---
name: new-worktree
description: >-
  Creates and initializes a new Git worktree as a sibling directory with automated
  branching and naming rules based on the latest remote default branch. Use when
  invoking /new-worktree or requesting a new Git worktree for parallel development,
  feature work, or bug fixes in external repositories under ~/github. Don't use for
  the Dart SDK (~/github/dart-sdk), non-Git repositories, or repositories outside
  ~/github.
key_features:
  - Git worktree setup off latest origin/main or origin/master
  - Sibling directory placement
  - Hard boundary checks for non-Git, outside ~/github, and Dart SDK
  - Automated branch and folder naming
---

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
     a warning asking for explicit human confirmation before proceeding. This
     prevents mutating internal corporate repositories or bare-repo dotfiles.
3. **Dart SDK Exception**:
   - Check if the repository maps to the Dart SDK
     (`https://github.com/dart-lang/sdk`, e.g., located at `~/github/dart-sdk`).
   - **Hard Block**: If operating in the Dart SDK repository, stop immediately
     and ask if the user wants to use their specialized Dart SDK flow instead
     (e.g., `dart-sdk-bootstrap`). Do not proceed without clarification. The Dart
     SDK relies on specialized toolchains, `gclient` checkouts, and dedicated
     bootstrap workflows that standard Git worktree operations break.

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
  - Creates branch: `issue-12345`
  - Creates worktree at: `~/github/_flutter-issue-12345`
- In `~/github/kevmoo/kevmoo_skills`, invoking `/new-worktree add lint check`:
  - Creates branch: `add-lint-check`
  - Creates worktree at: `~/github/kevmoo/_kevmoo_skills-add-lint-check`

## Execution Steps

1. **Verify Pre-Flight Boundaries**: Confirm location under `~/github`, confirm
   Git repository status, and ensure the repo is not the Dart SDK. Do not require
   a clean working directory; worktrees allow branching safely from a dirty tree.
2. **Fetch Latest Remote State**: Run `git fetch origin` to ensure local tracking
   branches are up to date. Always base new branches on the latest public default
   branch (`origin/main`, `origin/master`, or `origin/HEAD`).
3. **Formulate Target Names**: Determine `{branch_name}` and sibling directory
   path `{sibling_worktree_path}` based on naming rules.
4. **Execute Worktree Creation**:
   ```bash
   git worktree add -b {branch_name} {sibling_worktree_path} origin/main
   ```
   *(Substitute `origin/master` or `origin/HEAD` if appropriate for the repo).*
5. **Output Clickable Link**: Provide the user with a clickable link to the new
   worktree using the precise scheme `[link text](file:///absolute/path/to/worktree)`.
   Never wrap link text or syntax in backticks.
