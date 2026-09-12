---
name: review-pr
description: >-
  Reviews GitHub Pull Requests or local Git branch diffs using an adversarial 13-angle review rubric and the Inquisitor Presumption of Theater doctrine to eliminate LLM noise. Evaluates code correctness, removed behavior, error handling, testing, and simplification, generates a ranked Markdown report with clickable line permalinks, and presents an interactive action gate (keep findings, apply local fixes, or post inline to GitHub). Use when reviewing a PR (#N or URL), auditing a local feature branch, or invoked via /review-pr. Don't use for Google3 Piper changelists (use /cl-finalize or review) or general formatting.
key_features:
  - 13 analytical review angles (correctness, removed behavior, simplification, testing)
  - Inquisitor Presumption of Theater doctrine (zero AI fluff or pedantry)
  - Clickable GitHub permalinks to source lines
  - Interactive 3-way action gate (chat only, apply local fixes, post to GitHub)
---

# GitHub PR Reviewer (`/review-pr`)

A disciplined, senior-grade code reviewer for GitHub Pull Requests and local Git branches. Powered by the 13-angle evaluation rubric and the adversarial **Inquisitor Doctrine ("Presumption of Theater")** in [`RUBRIC.md`](RUBRIC.md) to purge hallucinatory AI fluff, pedantic theater, and unverified assumptions.

---

## 🎯 Primary Capabilities

1. **Native Git & GitHub Scope Detection**: Audits open GitHub PRs (`gh pr diff <PR>`) or local branch diffs (`git diff $(git merge-base origin/main HEAD)..HEAD`) with zero Google3 / Critique dependencies.
2. **Adversarial Inquisitor Gating**: Every candidate finding must survive the Five Inquisitorial Filters in [`RUBRIC.md`](RUBRIC.md) (Imaginary Architecture, Synchronous Paranoia, Pedantic Escalation, Harmless Idempotence, and Hallucinated APIs) before reaching the report.
3. **Clickable GitHub Permalinks**: Formats all findings with direct permalinks to source files and line ranges on GitHub (`https://github.com/<owner>/<repo>/blob/<sha>/<file>#L<start>-L<end>`).
4. **Interactive Action Gate (`ask_question`)**: Concludes with a 3-way decision gate allowing the user to keep findings in chat, auto-remediate nits locally in the worktree, or post comments to GitHub.

---

## 🛠️ Execution Protocol

### Step 1: Pre-Flight Scope & Diff Detection

1. **Explicit PR Target (URL or Number)**:
   If a PR URL or issue number is provided (e.g. `/review-pr https://github.com/foo/bar/pull/42` or `/review-pr #42`):
   ```bash
   # Extract PR metadata, base/head SHAs, and repo details
   gh pr view <PR> --json headRepositoryOwner,headRepository,headRefName,baseRefName,headRefOid,number,title,body,url

   # Extract full patch diff
   gh pr diff <PR>
   ```

2. **Active Worktree / Branch Detection**:
   If invoked inside a Git repository without arguments:
   ```bash
   # Determine target base commit
   TARGET_BASE=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base origin/master HEAD 2>/dev/null || git merge-base main HEAD)

   # Extract local working diff
   git diff ${TARGET_BASE}..HEAD

   # Detect if current branch has an associated open PR
   gh pr view --json number,title,url,headRefOid 2>/dev/null
   ```

3. **PR Intent & Linked Issues**:
   * Inspect the PR title and description body.
   * If the PR description references a tracking issue (e.g. `Fixes #123`, `Closes #456`), fetch the issue context:
     ```bash
     gh issue view <issue_number> --json title,body
     ```

---

### Step 2: Grounding & Local Code Inspection

Never review diff hunks in isolation. A finding without surrounding context is a guess.

1. **Caller & Interface Tracing**:
   * Inspect the complete modified files in the local worktree (`view_file` or `grep_search`).
   * When public methods, parameters, or types are modified, search for call sites across the repository to verify that all consumers are updated.
2. **Dependency & SDK Verification**:
   * If a finding contemplates suggesting an alternative function or class, verify that the symbol exists in the language SDK or `pubspec.yaml` / `go.mod` / `requirements.txt` / `package.json`.

---

### Step 3: Adversarial Evaluation (`RUBRIC.md`)

Evaluate the diff against [`RUBRIC.md`](RUBRIC.md):

1. **Sweep the 13 Angles**:
   * *1. Line Scan* (null safety, off-by-one, type casts, boolean logic).
   * *2. Removed Behavior* (broken silent contracts, deleted invariants).
   * *3. Cross-File Tracer* (interface drift, mock parity, export lists).
   * *4. Language Pitfalls* (unawaited futures, mutable defaults, goroutine leaks).
   * *5. Invariants & Wrappers* (leaky abstractions, unvalidated constructors).
   * *6. Testing Skeptic* (assertion-free tests, happy-path bias, missing regression tests).
   * *7. Error Handling* (swallowed exceptions, missing rethrows, silent nulls).
   * *8. Reuse* (reinventing existing standard library or dependency helpers).
   * *9. Simplification* (premature abstractions, speculative knobs, YAGNI).
   * *10. Efficiency* (allocations in loops, unindexed lookups, N+1 queries).
   * *11. Altitude* (high-level architectural coherence and layering).
   * *12. Readability & Conventions* (docstrings on public symbols, formatting).
   * *13. Cyclomatic Complexity* (arrow anti-patterns, deeply nested branches).

2. **Execute Inquisitor Filters ("Presumption of Theater")**:
   Cross-examine every candidate finding. Summarily discard any finding that falls into:
   * `[DISMISSED: INVENTED_ARCHITECTURE]` — Imaginary contracts not in code.
   * `[DISMISSED: PARANOIA]` — Concurrency/lifetime warnings in synchronous paths.
   * `[DISMISSED: PEDANTIC_ESCALATION]` — Elevating minor preferences to architectural flaws.
   * `[DISMISSED: HARMLESS]` — Defensive null-checks or harmless cleanup.
   * `[DISMISSED: HALLUCINATED_API]` — Recommending non-existent symbols/packages.

3. **Assign Severity**:
   * 🚨 **`[BLOCKING]`**: Runtime defects, data loss, race conditions, broken tests, security issues, public API breaks.
   * 💡 **`[SUGGESTION]`**: Measurable performance wins, significant simplification, eliminating wheel reinvention.
   * 🧹 **`[HYGIENE_NIT]`**: Typos, dead imports, docstring drift. (Suppress if zero blocking/suggestions exist to prevent comment noise on clean PRs).

---

### Step 4: Report Formatting & Artifact Persistence

1. **Write Review Report Artifact**:
   Save the full review report to:
   `<appDataDir>/brain/<conversation_id>/pr_review_<owner>_<repo>_<PR_NUMBER>.md`

2. **Format Structure**:
   ```markdown
   # Code Review: <Repo> PR #<Number> — <PR Title>

   **PR**: [<owner>/<repo>#<number>](https://github.com/<owner>/<repo>/pull/<number>) | **Base**: `<baseRef>` | **Head**: `<headRef>` (`<headSHA>`)
   **Verdict**: `✅ Approved` | `⚠️ Approved with suggestions` | `❌ Changes requested`

   ---

   ## Executive Summary
   - <1-2 bullet summary of the change intent and review outcome>
   - <Filter count: N findings reviewed, M dismissed by Inquisitor filter>

   ---

   ## Findings

   ### 🚨 Blocking Issues
   - [ ] [**path/to/file.dart#L42-L48**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L42-L48)
     **Defect**: <Concise explanation of the concrete runtime or architectural failure.>
     **Suggested Fix**:
     ```dart
     // Exact replacement code
     ```

   ### 💡 Suggestions
   - [ ] [**path/to/file.dart#L105**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L105)
     **Improvement**: <Concrete simplification or reuse opportunity.>

   ### 🧹 Hygiene Nits
   - [ ] [**path/to/file.dart#L12**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L12)
     **Nit**: <Dead import or typo.>
   ```

---

### Step 5: Interactive Action Gate (`ask_question`)

Immediately after presenting the review summary in chat and linking the report artifact, invoke `ask_question` to present a 3-way decision gate:

```text
Question: "PR #<number> review complete (<N> blocking, <M> suggestions, <K> nits). What action would you like to take?"
Options:
  1. "(Recommended) Keep findings in chat & artifact only (do not mutate working copy or GitHub)"
  2. "Apply fixes locally (auto-remediate high-confidence nits & format in worktree)"
  3. "Post findings inline to GitHub PR (stage comments via GitHub API/gh pr review)"
```

#### Action Execution Details:
* **Option 1 (Report Only)**: Yield cleanly. No files or remote state touched.
* **Option 2 (Local Fixes)**: Apply the verified fixes directly to the local worktree files, run formatters (`dart format`, `black`, `gofmt`), run project tests (`dart test`, `go test`), and prompt to commit/push.
* **Option 3 (Post to GitHub)**: Format findings as inline review comments and post to GitHub using `gh api` or `gh pr review --comment --body "<summary>"`.
