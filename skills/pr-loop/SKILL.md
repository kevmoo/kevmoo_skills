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
  - Review comment polling
  - Automated feedback remediation
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

### 2. [START] Schedule Polling Timer
* Call the `schedule` tool to set a background wakeup timer:
  * **Initial Push**: Set `DurationSeconds=180` (3 minutes) to allow initial bot
    ingestion.
  * **Subsequent Pushes**: Set `DurationSeconds=120` (2 minutes).
  * **Prompt**: `"Poll PR #<number> via gh pr view <number> --json comments. Check if gemini-code-assist posted review feedback on commit <sha>."`
* **CRITICAL IDLE PROTOCOL**: Immediately after calling `schedule`, output a
  concise visible status update to the user and **STOP calling tools**. You must
  go idle to allow the background timer task to tick.

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
* **Action on In-Progress Activity**: If `pr_status.dart` returns
  `"can_terminate": false` because CI checks are in-progress or a review pass is
  currently in progress, **schedule another 90s timer** and **go idle**. DO
  NOT start triaging or editing code until BOTH review comments and CI runs have
  fully completed!
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
* **Two-Step Reply & Resolve Protocol (MANDATORY)**:
  For every addressed review thread, you MUST execute both steps in order:
  1. **Post Reply Comment**: Call the REST API reply endpoint using the numeric
     comment `databaseId`:
     ```bash
     gh api repos/<owner>/<repo>/pulls/<pr_number>/comments/<comment_id>/replies -f body="<your concise explanation>"
     ```
  2. **Resolve Thread**: Call the GraphQL mutation using the thread `id`
     (`PRRT_...`):
     ```bash
     gh api graphql -f query='
       mutation {
         resolveReviewThread(input: {threadId: "<thread_id>"}) {
           thread { isResolved }
         }
       }
     '
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
2. If operating in Wynette Hybrid Production mode
   (`.dart_tool/wynette/dolt_replica` exists), present the mandatory Babysitter
   triage prompt (`hybrid_boot.dart --push/--stop`) before terminating the
   conversation.
