---
name: pr-loop
description: >-
  Autonomous pull request review loop that pushes code, polls for AI/bot review
  comments (e.g., Gemini Code Assist), surgically remediates feedback, commits,
  pushes, comments `/gemini review`, and loops until zero feedback remains.
  Requires the `github-pr-triage` skill.
key_features:
  - PR review loop
  - autonomous iteration
  - Review comment and CI polling
  - Automated feedback remediation
  - Dynamic/adaptive CI polling
---

# Autonomous PR Review Loop (`pr-loop`)

This skill defines the autonomous loop pattern for pair programming with an
automated AI code review bot (such as `gemini-code-assist`,
`gemini-code-review`, or similar PR review agents).

## 📦 Prerequisites & Skill Dependencies
- **REQUIRED SKILL**: `github-pr-triage` MUST be installed alongside `pr-loop`.
- `pr-loop` directly depends on binaries, scripts, and rule definitions provided
  by `github-pr-triage` (including `triage.dart` and `github_cli.dart`).

## When to use this skill
- Use this skill when asked to get into a review loop with an AI review agent on
  a pull request.
- Trigger when the user asks to "loop with gemini", "run the PR loop", "iterate
  on review comments until clean", or executes `/goal pr-loop`.

## 🔓 Upfront VCS Authorization & Safeguards

- **NEVER GUESS Target PR or Branch**: Agents MUST NEVER guess the target branch
  or pull request. If the active local branch or PR is ambiguous, unclear, or
  not explicitly confirmed by the user, the agent MUST pause and explicitly ask
  the user for clarification using the `ask_question` tool before initiating
  the loop or executing any git pushes or gh commands.
- **Request Blanket Upfront Consent**: When initiating `pr-loop`, the agent MUST
  first confirm the target feature branch and remote with the user using the
  `ask_question` tool, requesting blanket consent for autonomous commits and
  pushes for the duration of the loop.
- **Autonomous Execution Scope**: Once upfront consent is established, the agent
  is authorized to execute `git commit` and `git push` autonomously on every
  loop iteration on that specific feature branch (`headRefName`) to `origin`.
- **Trunk Branch Prohibition**: Committing or pushing directly to `main`,
  `master`, or protected trunk branches remains strictly prohibited.
- **NO `commit --amend`**: Modifying commit history via `git commit --amend` is
  strictly prohibited. Always create new, atomic commits for each review pass.
- **NO Force Pushes**: Force pushing (`git push -f` or `--force-with-lease`) is
  strictly prohibited under any circumstances.

## 🛑 Early Termination & Task Cleanup

If the user halts the execution of `pr-loop` early, or if you decide to pivot to another task, you MUST clean up any active background timers or scheduled tasks to prevent orphaned wakeups:
- **Antigravity Task Management**: Run `manage_task(Action="list")` to locate any active `schedule` timers created by this skill, and cancel them using `manage_task(Action="kill", TaskId="...")`.
- **Harness-Agnostic Fallback**: If the harness does not support a graphical task manager, locate the system process PID (if using POSIX background tasks) by inspecting prior tool calls or using standard process commands (e.g., `ps` or `pgrep`), and ensure you kill those background jobs using standard shell signals (e.g., `kill <PID>`) upon termination. Avoid writing temporary state files to the workspace to prevent repository pollution.

## 🏗️ Architectural Relationship & Rule Inheritance
This skill functions as an autonomous, multi-pass loop wrapper around the core
triage capabilities defined in the `github-pr-triage` skill.

**MANDATORY RULE DELEGATION**: `pr-loop` strictly inherits and follows ALL
rules, mindsets, and protocols defined in `github-pr-triage` to the letter
(excluding manual triage report generation and interactive approval steps,
which are bypassed in favor of autonomous execution):
1. **Critical Mindset**: Follow `github-pr-triage`'s mandate that reviewer
   feedback is NOT gospel. Empirically verify claims with compilers/analyzers
   and freely disagree (`👎 Disagree`).
2. **Assessment & Test Directives**: Categorize items using `github-pr-triage`'s
   Agreement Matrix and proactively write automated tests when reviewers
   request new behavior.
3. **Resolution APIs**: Use `github-pr-triage`'s exact API endpoints for comment
   replies and GraphQL thread resolutions.

---

## 🔄 The Autonomous Loop Workflow

### 1. Upfront Consent, Initial Push & PR Creation
* **Request Upfront Consent**: Use the `ask_question` tool to request blanket
  approval for autonomous commits and pushes during this review loop session,
  stating the active feature branch and remote. **Wait for the user's explicit
  response before proceeding to any git push or PR creation.**
* Verify local working tree state (`git status`); commit any uncommitted work.
* Push feature branch to origin: `git push -u origin <head_branch>`.
* Create the PR via GitHub CLI if not already opened:
  ```bash
  gh pr create --title "<type>(<scope>): <summary>" \
    --body "<walkthrough_summary>" --base main --head <head_branch>
  ```

### 2. [START] Immediate Status Check & Polling Timer
* **Immediate Initial Check**: Before scheduling a background timer, execute an
  immediate check of PR status (`dart <path-to-pr-loop-skill>/bin/pr_status.dart --dir .` or `gh pr view`).
  * If actionable review comments or failed CI checks already exist, **bypass the initial timer** and proceed directly to Step 3/4.
  * If review feedback or CI checks are still in progress, proceed to schedule the background wakeup timer.
* **Transition to Wait State**:
  * **If CI checks are running/pending**:
    1. Retrieve all active GHA run IDs for the current commit SHA:
       `gh run list --commit <commit_sha> --json databaseId,status`
       and filter for runs where status is not `completed`.
       (If the returned list is empty, GHA has not registered the runs yet.
       Retry up to 3 times with a 5-second delay; if still empty, proceed
       to Step 3/4).
    2. Watch the runs:
       * **Antigravity**: Dynamically construct and execute the watch command
         using the `run_command` tool:
         * If there is only one active run ID, run `gh run watch <run_id>`.
         * If there are multiple active run IDs, run them in parallel (e.g.,
           `gh run watch <run_id_1> & gh run watch <run_id_2> & wait`).
         * If there are no active GHA run IDs (e.g., due to external non-GHA
           checks), fall back to scheduling a polling timer (e.g., `schedule`
           with `DurationSeconds=300`).
         Before going idle, verify that all addressed review threads report
         `isResolved: true` (resolve them if not). Then, **STOP calling tools**
         and go idle; you will be reactively woken up when all runs complete.
       * **Other Agents / Harnesses**: If your harness supports long-running
         commands and active GHA run IDs exist, run `gh run watch <run_id>` for
         each run synchronously. If not, or if there are no active GHA run IDs (e.g.,
         due to external non-GHA checks), verify that all addressed review
         threads report `isResolved: true` (resolve them if not) before
         scheduling a long-interval timer (e.g., 5-10 minutes) or going idle.
  * **If ONLY bot review is pending (no CI running)**:
    1. Call the `schedule` tool with `DurationSeconds=120` to poll for comments (or use harness-specific polling/timer).
    2. **STOP calling tools** and go idle.

### 3. Wakeup & Feedback Ingestion (Comments & CI/CD)
* When reactive wakeup resumes your execution from the timer, inspect both
  reviewer comments and failing CI/CD status checks.
* **Deterministic Status Verification Engine**:
  Run the `pr_status.dart` helper script to evaluate whether the PR is ready for
  termination or requires further triage:
  ```bash
  dart <path-to-pr-loop-skill>/bin/pr_status.dart --dir .
  ```
* **Strict Termination Rules ([STOP])**:
  A PR is ONLY clean and ready for loop termination when `pr_status.dart`
  returns `"can_terminate": true`. Specifically, termination requires:
  1. Every check run in `gh pr checks` has completed cleanly (`SUCCESS`).
  2. `reviewThreads` has 0 unresolved threads.
  3. No review pass is currently in progress (i.e., no new review request has
     been submitted since the last bot review).
  4. The local git branch commit SHA is fully in sync with the remote PR head commit (`is_synced: true`).

  > [!IMPORTANT]
  > **NO LOCAL OVERRIDES / RATIONALIZATIONS**:
  > Passing local tests (`dart analyze`, `dart test`) are NEVER a substitute for remote CI status.
  > If `pr_status.dart` returns `"can_terminate": false`, the agent MUST NOT exit the loop
  > or declare victory early under any circumstances, regardless of local test results.
* **Action on In-Progress Activity (Waiting for CI/Review)**:
  If `pr_status.dart` returns `"can_terminate": false` because CI checks or a
  review pass are still in progress, go idle to wait for them. DO NOT start
  triaging or editing code until BOTH review comments and CI runs have fully
  completed!
  * **Waiting for CI**:
    * **Antigravity**: Retrieve all active GHA run IDs. Dynamically
      construct and execute the watch command using the `run_command` tool:
      * If there is only one active run ID, run `gh run watch <run_id>`.
      * If there are multiple active run IDs, run them in parallel (e.g.,
        `gh run watch <run_id_1> & gh run watch <run_id_2> & wait`).
      * If there are no active GHA run IDs (e.g., due to external non-GHA
        checks), fall back to scheduling a polling timer (e.g., `schedule`
        with `DurationSeconds=300`).
      Before going idle, verify that all addressed review threads report
      `isResolved: true` (resolve them if not). Then, **STOP calling tools**,
      and go idle. The platform will wake you up reactively when all runs
      complete.
    * **Other Agents / Harnesses**: Run `gh run watch <run_id>` synchronously
      for each active run if your harness allows long-running commands and
      active GHA run IDs exist. Otherwise, or if there are no active GHA run
      IDs (e.g., due to external non-GHA checks), verify that all addressed
      review threads report `isResolved: true` (resolve them if not) before
      scheduling a timer or falling back to checking CI status at larger
      intervals (e.g., 5-10 minutes) using standard timers or sleep commands,
      or going idle.
  * **Waiting for Bot Review only**: If CI is complete but the bot review pass
    is still in progress, call `schedule` with a short interval (e.g., 60-120
    seconds) to poll for comments (or use harness-specific polling/timer).
* **Unified Triage Engine**: If `pr_status.dart` indicates unresolved threads or
  failed CI runs exist (`"can_terminate": false`), run `triage.dart` as defined
  in `github-pr-triage`:
  ```bash
  dart <path-to-github-pr-triage-skill>/bin/triage.dart --dir .
  ```

### 4. Critical Assessment, Empirical Verification & Loop Convergence
* **Follow `github-pr-triage` Rules to the Letter**:
  * Apply the **Agreement Matrix** (`🔥 Urgent`, `👍 Solid`, `🤷 Meh`,
    `👎 Disagree`).
  * Exercise **Empirical Skepticism** using `dart analyze` and `dart test`.
  * **Proactively write automated tests** for reviewer-requested behavior.
* **Pragmatic Complexity & Anti-Overengineering Guardrail**:
  Before implementing structural refactorings suggested by automated bots (e.g.
  creating new classes/structs, adding caching maps, or rearranging working
  data flows), evaluate the file's scope and scale. If a suggestion adds
  boilerplate ceremony or premature optimization for small-scale scripts or
  internal build utilities, classify it as `🤷 Meh` / overengineering. Reject
  it using `👎 Disagree` with technical rationale: `"Deferring structural refactoring; existing implementation is pragmatically optimal."`
* **Loop Convergence Protocol (Progressive Criticality Ramp)**:
  To prevent infinite spinning where new diffs generate endless feedback,
  the agent MUST track its iteration count (e.g. by counting `fix(review):`
  commits in `git log origin/main..HEAD`) and apply its OWN evaluation:
  * **Pass 1 (Full Ingestion)**: Address `🔥 Urgent` bugs and `👍 Solid`
    functional improvements.
  * **Passes 2–5 (Strict Relevance Filter)**: Reject optional `🤷 Meh`
    nitpicks, micro-optimizations, or syntactic alternative cascades (such as
    switching `!= null` checks to `isNotEmpty` or minor variable renamings)
    using `👎 Disagree`. Only implement clear, essential bug fixes or safety
    improvements.
  * **Passes 6+ (Blockers Only / Force Convergence)**:
    Address ONLY `🔥 Urgent` blockers (bugs, compiler errors, analyzer
    warnings, security risks). For any optional refactorings or stylistic
    suggestions, reject them using `👎 Disagree` with rationale:
    `"Deferring optional suggestion to maintain loop convergence; code verified."`
  * **Max Loop Circuit-Breaker**: Cap execution at 10 iterations max.
* Surgically apply verified fixes (including newly created test files) and
  verify clean local quality gates.

### 5. Commit, Push & Resolve Threads
* **Commit & Push Fixes (If changes were made)**: Check `git status`. If code
  edits or new test files were created, stage, commit, and push them to origin
  (using `git add <files>` or `git add .` if no untracked scratch files exist):
  ```bash
  git add <files>
  git commit -m "fix(review): <concise summary of remediations>"
  git push origin HEAD
  ```
  *(Note: If no code changes were made, e.g. all comments were disagreed with,
  skip committing and pushing).*
* **Reply & Resolve Protocol (MANDATORY)**:
  For every addressed review thread, you MUST execute thread resolution (thread resolution is explicit, mandatory, and un-skippable).
  Use the `resolve` subcommand in `triage.dart`:
  ```bash
  dart <path-to-github-pr-triage-skill>/bin/triage.dart resolve <thread_id> <comment_id> "<your concise explanation>"
  ```

* **Pre-Timer Verification Gate (MANDATORY)**:
  Before calling `schedule` or going idle, query GraphQL (or run `pr_status.dart`)
  to verify that all addressed review threads report `isResolved: true`. If any
  addressed thread reports `isResolved: false`, immediately execute the
  `resolveReviewThread` mutation for that thread BEFORE setting the background
  wakeup timer.

### 6. Trigger Subsequent Review Pass (Or Terminate Zero-Change Loop)
* **Zero-Code-Change Loop Termination Rule**:
  If **0 code changes** were made in an iteration because all review comments were evaluated via the empirical verification gate (`dart analyze` returned 0 issues) and classified as `👎 Disagree`:
  * **DO NOT** comment `/gemini review` on the PR. Re-triggering the review bot on the exact same commit causes an infinite review loop.
  * **DO** post empirical disagreement replies on all review threads, resolve all threads via GraphQL (`triage.dart resolve`), and **terminate the loop immediately** with a final status summary.
* **Subsequent Push Review Trigger**:
  If code changes or new test files **were** committed and pushed to `origin`, you MUST explicitly prompt the bot again by posting a comment on the main PR thread:
  ```bash
  gh pr comment <pr_number> --body "/gemini review"
  ```
* Once `/gemini review` is posted and all threads are verified as resolved, loop
  back immediately to **Step 2 [START]** to schedule your background timer
  (e.g., 120s for review bot ingestion, or adaptive duration for CI) and go
  idle!

---

## 🏁 Loop Termination & Handoff
1. When the loop stops, report the total number of review iterations executed
   and link to the final merged/approved PR.
2. If operating in Wynette Hybrid Production mode
   (`.dart_tool/wynette/dolt_replica` exists), present the mandatory Babysitter
   triage prompt (`hybrid_boot.dart --push/--stop`) before terminating the
   conversation.
