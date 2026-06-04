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
   Execute the `triage.dart` helper script using the `run_command` tool:
   ```bash
   dart .agent/skills/github-pr-triage/bin/triage.dart
   ```
   *Note*: If you need to target a specific PR or a URL, you can pass it as an argument:
   ```bash
   dart .agent/skills/github-pr-triage/bin/triage.dart --pr <pr-number-or-url>
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
   - Create a markdown artifact named `pr_triage_report.md` in the artifacts directory.
   - **Link to Raw Output**: Include a markdown link to the `raw_triage_output.md` artifact at the top of the report.
   - The report MUST group associated comments and CI failures into cohesive action items (you may cluster multiple related comments or failures together if they address the same problem).
   - For each action item/group, include:
     - **Summary of Feedback/Failure**: A concise summary of the reviewer comment(s) or CI failure(s), including direct markdown links back to the comments/checks on GitHub. When linking to comments, use a descriptive link that includes both the comment number and the GitHub username of the reviewer (e.g. `[Comment #1 by @reviewer_username](url)`).
     - **Agent Assessment (For Comments)**:
       - **Agreement Level**: A short indicator of your agreement (e.g., `🔴 High`, `🟡 Medium`, `🟢 Low` or `⚪ None/Disagree`).
       - **Rationale**: Your technical explanation of why you agree, disagree, or recommend a specific direction.
     - **Planned Action**:
       - The target file name(s) and specific line ranges.
       - The proposed changes (e.g. explanation, code snippet/diff, or "No action needed").
   - Present this triage report to the user.

6. **Wait for Approval**:
   - DO NOT edit files or make changes until the user explicitly approves the proposed plan (e.g. "go fix it", "address the issues", "proceed").

7. **Surgical Implementation & Verification**:
   - Once approved, address the comments and failures one by one.
   - Follow standard development workflows: run formatting, analysis, and tests locally to verify fixes before finishing.

## Constraints
- **CRITICAL**: You MUST NOT modify files or make any code edits to address PR comments or CI failures before generating a `pr_triage_report.md` artifact and obtaining explicit user approval on the plan.
- Do NOT address resolved comments unless requested.
- Do NOT perform state-changing Git actions (commit, push) without explicit user permission.
- Always use the `triage.dart` script to fetch PR information instead of manual API calls to ensure consistency and minimize context bloat.
