---
name: github-pr-triage
description: |-
  Triage open PR comments/reviews and associated CI/CD workflow failures using the `triage.dart` helper script and formulate an actionable plan.
---

## When to use this skill

- Use this skill when asked to address review comments, pull request feedback, or debug failing CI/CD runs on a GitHub pull request.
- This skill MUST be activated when the user asks you to "look at comments on my PR", "address comments/reviews", "fix the build/checks", or provides a PR URL/branch and asks you to fix it.

## How to use this skill (The Workflow)

1. **Run the Triage Script**:
   Execute the `triage.dart` helper script using the `run_command` tool.
   Use the `--dir` (or `-C`) option to specify the path to the target repository directory (the project you want to triage). This ensures that the underlying `git` and `gh` commands resolve to the correct repository and branch:
   ```bash
   dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir <path-to-target-repository>
   ```
   *Note*: If you need to target a specific PR or URL, you can also pass `--pr`:
   ```bash
   dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir <path-to-target-repository> --pr <pr-number-or-url>
   ```
   **Save the raw stdout of this script** as a new markdown artifact named `raw_triage_output.md` in the artifacts directory (using the `write_to_file` tool).

2. **Verify Workspace State**:
   - The script output will show the PR URL, title, branch, and commit SHA.
   - Verify that your current git branch matches the PR source branch (`headRefName`).
   - Run `git status` and ensure the working tree matches the PR branch.
   - Verify you are at the correct commit. If not, inform the user or checkout the correct branch/commit.

3. **Analyze Open Comments**:
   - The script lists all unresolved comment threads.
   - Read the conversations carefully to understand what reviewers are requesting.
   - Focus *only* on unresolved comments. Ignore comments marked as resolved unless they provide necessary context.
   - Ignore comments from the PR author themselves unless they clarify a reviewer's comment.

4. **Analyze CI Failures**:
   - The script lists failed status checks and displays the logs of their failed steps.
   - Analyze the stack traces, compile errors, or analyzer failures to understand why they failed.

5. **Generate a Triage Report (Artifact)**:
   - Create a markdown artifact named `pr_triage_report.md` in the artifacts directory (using `write_to_file` with `RequestFeedback: true` in `ArtifactMetadata` to render an interactive 'Proceed' button).
   - **Link to Raw Output**: Include a markdown link to the `raw_triage_output.md` artifact at the top of the report.
   - The report MUST group associated comments and CI failures into cohesive action items (you may cluster multiple related comments or failures together if they address the same problem).
   - For each action item/group, include:
     - **Summary of Feedback/Failure**: A concise summary of the reviewer comment(s) or CI failure(s), including direct markdown links back to the comments/checks on GitHub. When linking to comments, use a descriptive link that includes both the comment number and the GitHub username of the reviewer (e.g. `[Comment #1 by @reviewer_username](url)`).
     - **Thread & Comment Identifiers (For Comments)**: Explicitly preserve the `Thread ID` (e.g. `PRRT_...`) and `Comment ID` (e.g. `3438780787`) from the comment header in `raw_triage_output.md` under each action item so Step 8 (`gh api`) has immediate access to both parameters without extra API lookups.
     - **Agent Assessment (For Comments)**:
       - **Agreement Level**: A short indicator of your agreement using one of these categories:
         * `🔥 Urgent` (Critical fix for a crash, bug, or CI blocker; we should fix immediately)
         * `👍 Solid` (Good suggestion; we should implement it)
         * `🤷 Meh` (Optional nit or stylistic preference; we could address it but it's low priority)
         * `👎 Disagree` (Incorrect or counter-productive suggestion; we should explain why and propose no action)
       - **Rationale**: Your technical explanation of why you agree, disagree, or recommend a specific direction.
     - **Planned Action**:
       - The target file name(s) and specific line ranges.
       - The proposed changes (e.g. explanation, code snippet/diff, or "No action needed").
   - Present this triage report to the user.

6. **Wait for Approval**:
   - DO NOT edit files or make changes until the user explicitly approves the proposed plan via the interactive 'Proceed' button (or explicit chat confirmation).

7. **Surgical Implementation & Verification**:
   - Once approved, address the comments and failures one by one.
   - Follow standard development workflows: run formatting, analysis, and tests locally to verify fixes before finishing.

8. **Verify Git State and Offer Resolution**:
   - **Check Git Status first**: Before offering to reply or resolve threads, run `git status` to verify if the fixes are committed and pushed.
     - **If uncommitted changes exist**: Warn the user (e.g., *"I see there are uncommitted changes. If I reply now, the code on GitHub won't match my replies."*).
     - **If unpushed commits exist**: Warn the user (e.g., *"I see there are unpushed commits. If I reply now, the code changes won't be visible on GitHub yet."*).
   - **Adhere to VCS Rules**: Do not guess whether you should commit or push. Follow the user's repository-specific version control rules (e.g., if there is a commit/push prohibition without permission, you must wait for a direct instruction to commit/push before executing those actions).
   - **Offer to Reply & Resolve**: Use the `ask_question` tool to ask the user if they would like you to reply to the review comments and resolve the threads (passing the options as a list parameter, e.g., ["Yes, reply and resolve threads", "No, do not reply or resolve"]). Do NOT output raw text like "YES / NO".
   - If the user selects the option to reply and resolve, execute the replies and resolutions using the patterns listed below.

## Replying and Resolving Comments

Use these API patterns to reply to review comments and resolve threads:

- **Reply to comment**:
  ```bash
  gh api repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_database_id>/replies -f body="<your reply>"
  ```
- **Resolve thread**:
  ```bash
  gh api graphql -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread {
          isResolved
        }
      }
    }
  ' -F threadId='<thread_graphql_id>'
  ```

## Constraints
- **CRITICAL**: You MUST NOT modify files or make any code edits to address PR comments or CI failures before generating a `pr_triage_report.md` artifact and obtaining explicit user approval on the plan.
- **No Git State Guessing**: Never assume you are allowed to commit or push code. Always request explicit permission if VCS operations are restricted, or follow the repository's or user's established commit protocols.
- **Sync Code Before Comments**: Do not post "Done" or "Fixed" comment replies or resolve threads on GitHub while the corresponding code fixes remain uncommitted or unpushed, unless the user explicitly directs you to do so anyway.
- Do NOT address resolved comments unless requested.
- Do NOT perform state-changing Git actions (commit, push) without explicit user permission.
- Always use the `triage.dart` script to fetch PR information instead of manual API calls to ensure consistency and minimize context bloat.
