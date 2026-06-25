---
name: pr-loop
description: >-
  Autonomous pull request review loop that pushes code, polls for AI/bot review
  comments (e.g., Gemini Code Assist), surgically remediates feedback, commits,
  pushes, comments `/gemini review`, and loops until zero feedback remains.
---

# Autonomous PR Review Loop (`pr-loop`)

This skill defines the autonomous loop pattern for pair programming with an
automated AI code review bot (such as `gemini-code-assist`,
`gemini-code-review`, or similar PR review agents).

## When to use this skill
- Use this skill when asked to get into a review loop with an AI review agent on
  a pull request.
- Trigger when the user asks to "loop with gemini", "run the PR loop", "iterate
  on review comments until clean", or executes `/goal pr-loop`.

## 🔒 Prerequisites & Safeguards
1. **Branch Scoping**: This loop MUST ONLY execute on an isolated feature or
   bugfix branch. **NEVER** run this loop directly on `main`, `master`, or
   protected trunk branches.
2. **Push Exemption (Branch Scope)**: When initiating this flow on a feature
   branch, the agent commits and pushes autonomously without prompting for user
   permission on each loop iteration.

---

## 🔄 The Autonomous Loop Workflow

### 1. Initial Push & PR Creation
* Ensure local working tree changes are committed (`git status`).
* Push feature branch to origin: `git push -u origin <head_branch>`.
* Create the PR via GitHub CLI if not already opened:
  ```bash
  gh pr create --title "<type>(<scope>): <summary>" --body "<walkthrough_summary>" --base main --head <head_branch>
  ```

### 2. [START] Schedule Polling Timer
* Call the `schedule` tool to set a background wakeup timer:
  * **Initial Push**: Set `DurationSeconds=180` (3 minutes) to allow initial bot
    ingestion.
  * **Subsequent Pushes**: Set `DurationSeconds=120` (2 minutes).
  * **Prompt**: `"Poll PR #<number> via gh pr view <number> --json comments,reviews. Check if gemini-code-assist posted review feedback on commit <sha>. If feedback exists, triage and fix. If empty, check reactions or stop."`
* **CRITICAL IDLE PROTOCOL**: Immediately after calling `schedule`, output a
  concise visible status update to the user and **STOP calling tools**. You must
  go idle to allow the background timer task to tick.

### 3. Wakeup & Feedback Ingestion (Comments & CI/CD)
* When reactive wakeup resumes your execution from the timer, inspect both
  reviewer comments and failing CI/CD status checks.
* **Recommended Method (Unified Triage)**:
  Execute the `triage.dart` script from the `github-pr-triage` skill. It runs a
  high-precision GraphQL query for unresolved review comments AND captures
  failing CI workflow step logs (`gh pr checks` / `gh run view --log-failed`):
  ```bash
  dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir . --pr <pr_number>
  ```
* **Manual CLI Queries (If executing directly via gh)**:
  * **Unresolved Review Threads**:
    ```bash
    gh api graphql -F owner=<owner> -F repo=<repo> -F pr=<pr_number> -f query='query($owner: String!, $repo: String!, $pr: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $pr) { comments(last: 10) { nodes { body author { login } reactionGroups { content users { totalCount } } } } reviewThreads(first: 100) { nodes { isResolved comments(first: 100) { nodes { databaseId author { login } body path line } } } } } } }'
    ```
  * **CI/CD Checks & Workflow Logs**:
    ```bash
    gh pr checks <pr_number> --json name,state,bucket,link,workflow
    gh run view <run_id> --log-failed
    ```
* **Check Eyeball Reactions**: Inspect `reactionGroups` on your latest comment
  or push. If `gemini-code-assist` attached an 👀 (`EYES`) reaction, she is
  actively analyzing the push right now! Schedule another 90s timer and go idle.
* **Empty Check ([STOP])**: If there are zero unresolved review comments AND all
  CI checks are green/passing, **[STOP]**! The PR is 100% clean. Exit the loop
  and report victory.

### 4. Critical Assessment & Empirical Verification
* **Empirical Skepticism**: Do not assume any reviewer — whether an automated AI
  bot like `gemini-code-assist` or a human engineer — is infallible or always
  smarter than you. Reviewers frequently make mistakes, hallucinate language
  limitations, or suggest outdated patterns.
* **Leverage Your Execution Advantage**: You have the unique superpower to run
  live compilers, test suites, and static analyzers (`dart analyze`, `dart
  test`) that external reviewers cannot execute on demand. **Always empirically
  test a reviewer's claims against real compiler/analyzer feedback** before
  blindly accepting them.
* **Reject Unverified Claims**: If running local quality gates proves that your
  existing code works or that a reviewer's suggestion causes compilation,
  analyzer, or test failures, reject the suggestion.
* Exercise engineering judgment: eagerly accept solid/urgent defensive
  programming suggestions, but feel free to push back on stylistic noise or
  regressions.
* Surgically modify target files (`replace_file_content`) to implement
  empirically verified fixes.
* Run local quality gates (`dart analyze`, `dart test`, linters) to guarantee
  100% clean builds before committing.

### 5. Commit, Push & Resolve Threads
* Commit review fixes atomically:
  ```bash
  git commit -am "fix(review): <concise summary of remediations>"
  ```
* Push directly to the remote feature branch:
  ```bash
  git push origin <head_branch>
  ```
* **Resolve Addressed Review Threads**: For each inline review thread that was
  remediated, mark the conversation thread as resolved via GitHub GraphQL API:
  ```bash
  gh api graphql -F id="<thread_node_id>" -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }'
  ```

### 6. Trigger Subsequent Review Pass
* **CRITICAL OPERATIONAL REMINDER**: `gemini-code-assist` automatically ingests
  the *first* PR push. However, for **every subsequent push**, you MUST
  explicitly prompt the bot again by posting a comment on the main PR thread:
  ```bash
  gh pr comment <pr_number> --body "/gemini review"
  ```
* Once `/gemini review` is posted, loop back immediately to **Step 2 [START]**
  to schedule your 120s timer and go idle!

---

## 🏁 Loop Termination & Handoff
1. When the loop stops, report the total number of review iterations executed
   and link to the final merged/approved PR.
2. If operating in Wynette Hybrid Production mode (`.dart_tool/wynette/dolt_replica`
   exists), present the mandatory Babysitter triage prompt
   (`hybrid_boot.dart --push/--stop`) before terminating the conversation.
