---
name: github-cli
description: |-
  Use the `gh` command to interact with GitHub repositories, pull requests, issues, and actions.
---

## When to use this skill

**You MUST strongly consider using this skill any time the user asks you to look at, inspect, or review any `github.com` URL** (e.g., a pull request, issue, or repository link).

Also use this skill when you need to interact with GitHub features from the command line, such as:
*   Checking the status of Pull Requests (PRs).
*   Viewing PR review comments or discussion.
*   Checking CI results for a PR.
*   Listing or viewing issues.
*   Interacting with GitHub Actions workflow runs.

## How to use this skill

Use the `run_command` tool to execute `gh` commands.

### General Tips
*   **Non-interactive mode**: Many `gh` commands will attempt to be interactive if they suspect a terminal. To avoid hangs or blocking, use flags that provide all necessary information or output machine-readable formats (like `--json`).
*   **Authentication**: If a command fails with an authentication error, inform the user.

### Useful Commands

#### Pull Requests

**1. View PR Status**
To see the status of PRs relevant to the current branch or repository:
```bash
gh pr status
```

**2. List Pull Requests**
```bash
gh pr list
```

**3. View a Specific PR**
To view the description and basic details:
```bash
gh pr view <pr-number>
```
To view comments as well:
```bash
gh pr view <pr-number> --comments
```

**4. Check CI Status**
To see the status of checks (CI) for a specific PR:
```bash
gh pr checks <pr-number>
```
This is very useful for diagnosing CI failures.

**5. View PR Diff**
To see the diff of a PR:
```bash
gh pr diff <pr-number>
```

**6. Checkout a PR**
To checkout a PR locally to run tests or inspect code:
```bash
gh pr checkout <pr-number>
```

#### Issues

**1. List Issues**
```bash
gh issue list
```

**2. View an Issue**
```bash
gh issue view <issue-number>
```

#### GitHub Actions

**1. List Workflow Runs**
```bash
gh run list
```

**2. View a Specific Run**
```bash
gh run view <run-id>
```
To see logs for a specific run:
```bash
gh run view <run-id> --log
```

### State-Changing Operations (Caution)

For operations like `gh pr create`, `gh pr merge`, `gh pr comment`, etc.:
*   **Ask for confirmation** unless the user explicitly told you to perform the action (as per the general rules for state-changing operations).
*   Ensure you provide all required flags to avoid interactive prompts.

Example of adding a comment:
```bash
gh pr comment <pr-number> --body "Your comment here"
```

### Guidelines for PR Reviews

When asked to review a PR or address comments:

1.  **Focus on Open Comments**: You should ONLY look at and address **open (unresolved)** comments. Do not spend time addressing comments that have already been resolved unless the user explicitly asks you to review them.
    *   *Note*: If `gh pr view --comments` returns all comments, you must filter them to identify which ones still need attention.
2.  **Verify Branch and Commit**: Before making any changes or running tests to address PR feedback, you MUST verify that the branch associated with the PR maps to your current workspace git repository and branch/commit.
    *   Run `gh pr view <pr-number> --json headRefName,headRepositoryOwner,headSha` to check the source branch and commit.
    *   Ensure you are on the correct branch and at the correct commit before proceeding.

### Constraints and Best Practices
*   Always verify the repository context before running commands if unsure.
*   Prefer read-only commands (`view`, `status`, `list`) unless instructed otherwise.
*   Use `--json` flag when you need to parse specific fields programmatically (e.g., `gh pr view --json title,body`).
