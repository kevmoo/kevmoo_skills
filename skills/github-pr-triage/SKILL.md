---
name: github-pr-triage
description: |-
  Triage open PR comments/reviews and associated CI/CD workflow failures using
  the `triage.dart` helper script and formulate an actionable plan.
---

## When to use this skill

- Use this skill when asked to address review comments, pull request
  feedback, or debug failing CI/CD runs on a GitHub pull request in an
  interactive, single-pass manner.
- This skill MUST be activated when the user asks you to "look at comments on
  my PR", "address comments/reviews", "fix the build/checks", or provides a PR
  URL/branch and asks you to fix it.
- *Note*: For continuous autonomous iteration loops with AI code review bots
  (such as Gemini Code Assist), use the `pr-loop` skill instead, which uses this
  skill's `triage.dart` script as its underlying triage engine.

## 🧠 Critical Mindset: Reviewer Feedback is NOT Gospel

- **Reviewers make mistakes**: Do NOT assume any reviewer — whether an automated
  AI bot like Gemini Code Assist or a human engineer — is infallible. AI review
  bots frequently hallucinate syntax limitations, suggest outdated patterns, or
  misunderstand broader repository architecture.
- **You have the execution advantage**: External reviewers inspect static code,
  whereas you can execute live compilers, static analyzers (`dart analyze`),
  and test suites (`dart test`). Always empirically test claims before accepting
  them.
- **You are free to disagree**: If a reviewer's claim is technically wrong, if
  their suggestion introduces compiler warnings or regressions, or if the
  existing code is already optimal, mark it as `👎 Disagree`. Explain your
  technical rationale in the triage report and propose NO code changes for that
  item.

## How to use this skill (The Workflow)

1. **Run the Triage Script**:
   Execute the `triage.dart` helper script using the `run_command` tool.
   Use the `--dir` (or `-C`) option to specify the path to the target
   repository directory (the project you want to triage). This ensures that the
   underlying `git` and `gh` commands resolve to the correct repository and
   branch:
   ```bash
   dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir <path-to-target-repository>
   ```
   *Note*: If you need to target a specific PR or URL, you can also pass `--pr`:
   ```bash
   dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir <path-to-target-repository> --pr <pr-number-or-url>
   ```
   **Save the raw stdout of this script** as a new markdown artifact named
   `raw_triage_output.md` in the artifacts directory (using the `write_to_file`
   tool).

2. **Verify Workspace State**:
   - The script output will show the PR URL, title, branch, and commit SHA.
   - Verify that your current git branch matches the PR source branch
     (`headRefName`).
   - Run `git status` and ensure the working tree matches the PR branch.
   - Verify you are at the correct commit. If not, inform the user or checkout
     the correct branch/commit.

3. **Analyze Open Comments**:
   - The script lists all unresolved comment threads.
   - Read the conversations carefully to understand what reviewers are
     requesting.
   - Focus *only* on unresolved comments. Ignore comments marked as resolved
     unless they provide necessary context.
   - Ignore comments from the PR author themselves unless they clarify a
     reviewer's comment.

4. **Analyze CI Status & Failures**:
   - The script lists status checks (both failed and active/pending).
   - **Active/Pending CI Handling**: If any CI status checks are currently
     running or pending:
     - Inform the user and call `ask_question` to ask their preference:
       * Option 1: `(Recommended) Proceed with triaging open comments now`
       * Option 2: `Wait for active CI status checks to complete first`
     - *(Note: This interactive prompt is bypassed when operating within an
       outer orchestrator skill like `pr-loop`, which handles background timers
       automatically)*.
   - Analyze the stack traces, compile errors, or analyzer failures to
     understand why any failed checks failed.

5. **Generate a Triage Report (Artifact)**:
   - Create a markdown artifact named `pr_triage_report.md` in the artifacts
     directory (using `write_to_file` with `RequestFeedback: true` in
     `ArtifactMetadata` to render an interactive 'Proceed' button). (Note: This
     step is bypassed ONLY IF operating within an outer orchestrator skill like
     `pr-loop` with upfront user consent).
   - **Link to Raw Output**: Include a markdown link to the
     `raw_triage_output.md` artifact at the top of the report.
   - The report MUST group associated comments and CI failures into cohesive
     action items (you may cluster multiple related comments or failures
     together if they address the same problem).
   - For each action item/group, include:
     - **Summary of Feedback/Failure**: A concise summary of the reviewer
       comment(s) or CI failure(s), including direct markdown links back to the
       comments/checks on GitHub. When linking to comments, use a descriptive
       link that includes both the comment number and the GitHub username of the
       reviewer (e.g. `[Comment #1 by @reviewer_username](url)`).
     - **Thread & Comment Identifiers (For Comments)**: Explicitly preserve the
       `Thread ID` (e.g. `PRRT_...`) and `Comment ID` (e.g. `3438780787`) from
       the comment header in `raw_triage_output.md` under each action item so
       the resolution step (`gh api`) has immediate access to both parameters
       without extra API lookups.
     - **Agent Assessment (For Comments)**:
       - **Agreement Level**: A short indicator of your agreement using one of
         these categories:
         * `🔥 Urgent` (Critical fix for a crash, bug, or CI blocker; we should
           fix immediately)
         * `👍 Solid` (Good suggestion; we should implement it)
         * `🤷 Meh` (Optional nit or stylistic preference; we could address
           it, but it's low priority)
         * `👎 Disagree` (Incorrect or counter-productive suggestion; we should
           explain why and propose no action)
       - **Rationale**: Your technical explanation of why you agree,
         disagree, or recommend a specific direction.
     - **Planned Action**:
       - The target file name(s) and specific line ranges.
       - The proposed changes (e.g. explanation, code snippet/diff, or "No
         action needed").
   - Present this triage report to the user.

6. **Wait for Approval**:
   - DO NOT edit files or make changes until the user explicitly approves the
     proposed plan via the interactive 'Proceed' button (or explicit chat
     confirmation). (Note: This step is bypassed ONLY IF operating within an
     outer orchestrator skill like `pr-loop` with upfront user consent).

7. **Surgical Implementation & Verification**:
   - Once approved, address the comments and failures one by one.
   - **Add tests for new behavior**: When a reviewer requests new behavior,
     bug fixes, or edge-case handling, proactively write automated tests
     (typically placed in the `test/` directory with a `_test.dart` suffix) to
     verify the changes and prevent future regressions.
   - Follow standard development workflows: run formatting, analysis, and tests
     locally to verify fixes before finishing.

8. **Verify Git State and Offer Unified Resolution Menu**:
   - **Outer Skill Exception**: Step 8 is bypassed entirely ONLY IF operating
     within an outer orchestrator skill (such as `pr-loop`) that has already
     obtained upfront user consent for autonomous VCS commits and pushes.
   - **Check Git Status first**: Run `git status` to check whether uncommitted
     fixes or unpushed commits exist.
   - **Present Completion Options (`ask_question`)**: Use the `ask_question`
     tool to present a unified completion menu based on the working tree state
     (passing the options as a list parameter). Do NOT output raw text. By
     selecting an option that includes committing or pushing, the user
     explicitly authorizes those VCS operations for this workflow.
     - **If uncommitted changes or unpushed commits exist**, offer:
       1. `(Recommended) Commit fixes, push branch, reply to comments, and resolve threads`
       2. `Commit fixes and push branch only`
       3. `Reply to comments and resolve threads without committing/pushing`
       4. `Do nothing`
     - **If working tree is clean and all commits are pushed**, offer:
       1. `(Recommended) Reply to comments and resolve threads`
       2. `Do nothing`
   - **Execute Selected Actions**:
     - If committing is selected, stage all modified and new files (using
       `git add <files>` or `git add .` if no untracked scratch files exist)
       and create a descriptive commit.
     - If pushing is selected, run `git push`.
     - If replying and resolving is selected, execute the `gh api` commands
       using the patterns listed below.

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
- **CRITICAL**: You MUST NOT modify files or make any code edits to address PR
  comments or CI failures before generating a `pr_triage_report.md` artifact
  and obtaining explicit user approval on the plan. (Note: This constraint is
  bypassed ONLY IF operating within an outer orchestrator skill like `pr-loop`
  with upfront user consent).
- **VCS Authorization**: Selecting an option in `ask_question` that explicitly
  mentions committing or pushing serves as the user's explicit permission to
  perform those operations for the triage fixes. Do NOT ask for permission
  a second time if the user selects one of those options. (Note: This
  constraint is bypassed ONLY IF operating within an outer orchestrator skill
  like `pr-loop` with upfront user consent).
- **Sync Code Before Comments**: Do not post "Done" or "Fixed" comment replies
  or resolve threads on GitHub while the corresponding code fixes remain
  uncommitted or unpushed, unless the user explicitly selects an option
  directing you to do so.
- Do NOT address resolved comments unless requested.
- **NO `commit --amend`**: Modifying commit history via `git commit --amend` is
  strictly prohibited. Always create new, atomic commits.
- **NO Force Pushes**: Force pushing (`git push -f` or `--force-with-lease`) is
  strictly prohibited under any circumstances.
- Always use the `triage.dart` script to fetch PR information instead of manual
  API calls to ensure consistency and minimize context bloat.
