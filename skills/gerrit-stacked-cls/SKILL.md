---
name: gerrit-stacked-cls
description: |-
  Best practices for managing stacked changelists (CLs) in Gerrit using depot_tools, avoiding common pitfalls with Change-Ids.
---

## 1. When to use this skill
Use this skill when you need to create, update, or manage a chain of dependent changelists (CLs) in Gerrit (stacked CLs) for the Dart SDK or similar repositories using Chromium's `depot_tools`.

## 2. Core Concepts
*   **Relation Chain**: Gerrit links commits together based on their parent-child relationship in the pushed git history.
*   **Change-Id**: Gerrit identifies a CL by the Change-Id: line in the commit message.
*   **Commit Hash**: Gerrit identifies a *Patchset* within a CL by the git commit hash.

## 3. Procedural Workflows

### Creating Stacked CLs
1.  **Start with the base CL**:
    ```bash
    git new-branch branch1
    # Make changes
    git commit -m "First change"
    git cl upload
    ```
2.  **Create the dependent CL**:
    Create a new branch on top of `branch1`.
    ```bash
    git checkout branch1
    git new-branch branch2
    # Make dependent changes
    git commit -m "Second change"
    git cl upload
    ```
    Gerrit will automatically create a relation chain.

### Updating a Specific CL in a Stack
To update a specific CL without confusing Gerrit, you must ensure that the commit you push has the **correct Change-Id** and that it is the **last** Change-Id in the commit message if multiple are present (though ideally, keep only one).

#### Method A: Amending (If allowed by user rules)
If allowed to amend, this is the cleanest way:
1.  Checkout the branch for the CL you want to update.
2.  Make changes.
3.  Run `git commit --amend`. Keep the original `Change-Id` line intact!
4.  Run `git cl upload`.

#### Method B: New Commit + Squash (Following strict no-amend rules)
If forbidden from amending active PRs:
1.  Make changes on the branch.
2.  Commit as a new commit (generating a new Change-Id).
3.  To update the existing CL on Gerrit without creating a new one:
    *   Squash the new commit into the previous one using git reset --soft HEAD~2 (assuming one fixup commit) and then committing again.
    *   **CRITICAL**: Ensure the final commit message contains **only** the `Change-Id` of the CL you want to update. If multiple `Change-Id:` lines are present, Gerrit will typically use the **last** one!

### Resolving Conflicts in Stacked CLs
When rebasing a dependent branch (e.g., `branch2`) on top of an updated base branch (`branch1`), conflicts may arise in generated files (like `.wat` files).
1.  Accept OURS (the upstream/base version) during conflict resolution to get past the rebase conflict quickly.
2.  Complete the rebase (`git rebase --continue`).
3.  **Re-generate** the expectations or generated files using the appropriate tool (e.g., `ir_test.dart -w`).
4.  Commit the newly generated files to keep the expectation history clean and accurate.

## 4. Critical Pitfalls
*   **Multiple Change-Ids in a Commit Message**: If you squash commits or copy-paste messages, you might end up with multiple `Change-Id:` lines. Gerrit reads them and usually routes the update to the CL corresponding to the **last** `Change-Id` in the message. Always clean up commit messages to have exactly one target `Change-Id`.
*   **No New Changes**: If you try to push a commit that is identical in content to an existing patchset, Gerrit will reject it. To force a new patchset (e.g., to restore an older state), use `git commit --amend --no-edit` to update the committer timestamp and generate a new commit hash.
