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

### Agent Workflow and Communication
*   **Verify State Before Action**: Always run `git status` to check the
    current local branch and whether the working tree is clean or dirty. Also
    run `gh pr status` or `gh pr list --head <branch>` to identify the active
    PR for the branch. Never assume you are on the correct branch or that the
    PR number hasn't changed between interactions.
    *   **Resolving Ambiguity**: If multiple repositories are active and the
        target PR is not specified, check the active local branch in each. If a
        branch name matches the source branch (`headRefName`) of an open PR,
        assume that is the target.
*   **Default to Summary and Plan**: When asked to review changes or give
    thoughts, always default to providing a SUMMARY of the feedback and your
    recommendations. DO NOT proceed with making file edits unless the user
    explicitly instructs you with phrases like "go fix it" or "address the
    issues". If the scope of work is large, always prefer asking for
    confirmation first.

### Useful Commands

#### Pull Requests

**1. Sync & Context Verification (AI Preferred)**
To check branch name, commit SHA (`headRefOid`), review status, and
mergeability:
```bash
gh pr view --json number,title,state,reviewDecision,mergeable,headRefName,headRefOid
```

**2. Full Review & CI Snapshot (AI Preferred)**
To get conversation, review feedback, and CI check results in structured JSON:
```bash
gh pr view --json comments,reviews,statusCheckRollup
```

**3. Find PR by Branch**
To find the PR number for a specific branch:
```bash
gh pr list --head <branch-name>
```

**4. View PR Diff**
To see the diff of a PR:
```bash
gh pr diff <pr-number>
```

**5. Checkout a PR**
To checkout a PR locally:
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



### Guidelines for PR Reviews

When asked to review a PR or address comments:

1.  **Focus on Open Comments**: You should ONLY look at and address **open
    (unresolved)** comments. Do not spend time addressing comments that have
    already been resolved unless the user explicitly asks you to review them.
    *   *Note*: Users often use "comments" and "reviews" interchangeably. Be
        clear when reporting that you found X comments (at the end of the PR)
        vs Y reviews (inline feedback).
    *   **Pro-Tip**: Since `gh` doesn't have a built-in flag for open comments,
        you can use `gh api graphql` to find unresolved review threads. Here
        is a query to list the body of unresolved comments:
        ```bash
        gh api graphql -F owner=':owner' -F repo=':repo' -F pr=:number -f query='
          query($owner: String!, $repo: String!, $pr: Int!) {
            repository(owner: $owner, name: $repo) {
              pullRequest(number: $pr) {
                reviewThreads(first: 100) {
                  nodes {
                    isResolved
                    comments(first: 1) {
                      nodes { body }
                    }
                  }
                }
              }
            }
          }
        ' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .comments.nodes[0].body'
        ```
2.  **Verify Branch and Commit**: Before making any changes or running tests to address PR feedback, you MUST verify that the branch associated with the PR maps to your current workspace git repository and branch/commit.
    *   Run `gh pr view <pr-number> --json headRefName,headRepositoryOwner,headSha` to check the source branch and commit.
    *   Ensure you are on the correct branch and at the correct commit before proceeding.
3.  **Ignore PR Author Comments**: Comments from the PR author can usually be
    ignored when identifying tasks to address, unless they offer context to a
    comment from another user (e.g., a reviewer). Prioritize addressing
    feedback from reviewers.

### Constraints and Best Practices
*   Always verify the repository context before running commands if unsure.
*   Prefer read-only commands (`view`, `status`, `list`) unless instructed otherwise.
*   Use `--json` flag when you need to parse specific fields programmatically (e.g., `gh pr view --json title,body`).
