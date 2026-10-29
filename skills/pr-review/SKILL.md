---
name: pr-review
description: >-
  Reviews GitHub Pull Requests or local Git branch diffs for defects, removed behavior, and specification drift using a 13-angle rubric and adversarial noise filtering. Use when reviewing a GitHub PR (#N or URL), auditing a local feature branch before opening a PR, or invoked via /pr-review. Don't use for triaging existing PR review comments or CI failures (use pr-triage), multi-repo branch cleanup sweeps (use pr-cleanup), or non-GitHub code review systems.
key_features:
  - Explicit 3D Paranoia Tiering (Ring, Confidence, One-Way/Two-Way Door) with --deep escalation
  - Two-Axis Evaluation (Linked Issue Spec Traceability + RUBRIC.md Standards)
  - 13 analytical review angles + Inquisitor Presumption of Theater doctrine
  - 2-Tier ownership action gate (own repo auto-fix vs. external read-only)
---

# GitHub PR Reviewer (`/pr-review`)

A disciplined, senior-grade code reviewer for GitHub Pull Requests and local Git
branches. Powered by the 13-angle evaluation rubric and the adversarial
**Inquisitor Doctrine ("Presumption of Theater")** in [`RUBRIC.md`](RUBRIC.md)
to purge hallucinatory AI fluff, pedantic theater, and unverified assumptions.

---

## 🎯 Primary Capabilities

1. **Explicit 3D Paranoia Tiering (`OQ3`)**: Computes Audience Ring
   (`Ring 0..4B`), Author Domain Confidence (`High|Low`), and Reversibility
   (`🚪 One-Way` vs. `🔄 Two-Way` Door) to select `Standard` (single-pass) or
   `Deep` (multi-subagent parallel) review mode.
2. **Two-Axis Evaluation (`Spec` vs. `Standards`)**: Verifies issue requirement
   traceability (`gh issue view <N>`) alongside the Dart, package, and 13-angle
   defect standards in [`RUBRIC.md`](RUBRIC.md).
3. **Adversarial Inquisitor Gating & Clickable Permalinks**: Filters every
   candidate finding through the Five Inquisitorial Filters in
   [`RUBRIC.md`](RUBRIC.md) and links directly to GitHub source lines
   (`https://github.com/<owner>/<repo>/blob/<sha>/<file>#L<start>-L<end>`).
4. **2-Tier Ownership Action Gate (`OQ1`)**: Adapts `ask_question` defaults
   between owned `kevmoo/*` branches (auto-fix + `kscripts pr-check`) and
   external/peer PRs (strictly read-only local checkout).

---

## 🛠️ Execution Protocol

### Step 1: Pre-Flight Scope, Ownership & 3D Paranoia Classification

1. **Target & Ownership Detection (`OQ1`)**:
   - **Explicit PR (`#N` or URL)**:
     ```bash
     gh pr view <PR> --json author,headRepositoryOwner,headRepository,headRefName,baseRefName,headRefOid,number,title,body,url
     gh pr diff <PR>
     ```
   - **Local Branch / Worktree (no arguments)**:
     ```bash
     TARGET_BASE=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base origin/master HEAD 2>/dev/null || git merge-base main HEAD)
     git diff ${TARGET_BASE}..HEAD
     gh pr view --json author,headRepositoryOwner,headRefName,number,title,url,headRefOid 2>/dev/null
     ```
   - Classify ownership into two tiers:
     - **Tier 1 (Own Repo `kevmoo/*` + Author `kevmoo` /
       `$(gh api user --jq .login)` with `headRefName` checked out locally, or
       local feature branch)**: Local remediation and test execution
       (`kscripts pr-check`) enabled.
     - **Tier 2 (External/Peer PR, non-`kevmoo` author, or PR branch not checked
       out locally)**: Strictly read-only local checkout.

2. **Linked Issue, Spec & Prior Review Thread Extraction (`FU1`)**:
   - When a PR links an issue (`Fixes #N`, `Closes #N`, or prompt issue URL),
     fetch the specification contract:
     ```bash
     gh issue view <N> --json title,body
     ```
   - On explicit PRs with prior review rounds, fetch existing review threads
     (resolved and unresolved) to respect settled design decisions and skip
     previously addressed feedback:
     ```bash
     gh api graphql -F owner='{owner}' -F name='{repo}' -F pr={pr_number} -f query='query($owner:String!, $name:String!, $pr:Int!) { repository(owner:$owner, name:$name) { pullRequest(number:$pr) { reviewThreads(first:100) { nodes { isResolved path line comments(first:10) { nodes { author { login } body } } } } } } }'
     ```

3. **3D Paranoia Header & Review Mode Selection (`OQ3`)**:

   <!-- BEGIN SPOT: workflow-3d-paranoia-tiers -->
   - **Banner Format**: Render at the top of review and PR draft preview
     artifacts (and in chat):
     `🛡️ Paranoia Tier: Ring <0..4B> (<Label>) · Confidence: <High|Low> · Door: <🚪 One-Way | 🔄 Two-Way>`
   - **Reuse Ring (`Ring 0..4B`)**: `Ring 0` (personal dotfiles & private
     configs) · `Ring 1-2` (public skills, utilities & internal scripts) ·
     `Ring 3` (published `pub.dev` packages) · `Ring 4A` (upstream Dart/Flutter
     framework & packages) · `Ring 4B` (upstream C++, Dart VM internals, WIMP,
     Skwasm engine). Default to `Review Mode: Standard` on `Ring 0-2` and
     `Review Mode: Deep` on `Ring 3-4` or when `--deep` (`--paranoid`) is
     passed.
   - **Confidence (`High | Low`)**: `High` for familiar pure Dart, CLI, package
     & framework code; `Low` (forcing `Review Mode: Deep`) for unfamiliar C++,
     VM internals, or WIMP/Skwasm/engine plumbing.
   - **Door Type (`🚪 One-Way | 🔄 Two-Way`)**: `🚪 One-Way` (forcing
     `Review Mode: Deep`) for public `api.txt` / CLI flag / JSON schema deltas,
     SemVer `-wip` bumps, DB migrations, or CI release workflows; `🔄 Two-Way`
     for internal `lib/src/` refactors, isolated tests, and docs.

   <!-- END SPOT: workflow-3d-paranoia-tiers -->

---

### Step 2: Two-Axis Grounding (`Spec` + [`RUBRIC.md`](RUBRIC.md))

Inspect complete modified files (`view_file`) along with callers and SDK/package
dependencies rather than diff hunks in isolation.

1. **Axis A — Spec & Issue Contract Traceability (`FU1`)**:
   - Cross-check every requirement in the linked issue (`gh issue view <N>`)
     against the implementation and test suite (`Met ✅`, `Partial ⚠️`,
     `Unmet ❌`, `Out-of-Scope ➖`). Flag unwired CLI flags or missing
     acceptance criteria.
2. **Axis B — Dart, Architecture & Testing Standards
   ([`RUBRIC.md`](RUBRIC.md))**:
   - Audit Dart and package diffs against the canonical standards embedded in
     [`RUBRIC.md`](RUBRIC.md) Angles `#3` (Public API Surface Verification),
     `#5` (Load-Bearing Library Boundary Rule), `#7` (Test Seam Discipline,
     Hermeticity & No Change-Detector Tests — newly added or literal-updated
     change-detector assertions in the diff are `[BLOCKING]`), `#9` & `#13`
     (Deep Externally / Pure Internally & Cognitive Complexity Target Zone
     `8–15`), and Part 2 (`Dart Inquisitorial Review Dismissal Filters`).

---

### Step 3: Adversarial Evaluation (`RUBRIC.md`)

1. **Sweep the 13 Angles in [`RUBRIC.md`](RUBRIC.md)**:
   - _1. Line Scan_ · _2. Removed Behavior_ · _3. Cross-File Tracer_ · _4.
     Language Pitfalls_ · _5. Invariants & Wrappers_ · _6. Error Handling_ · _7.
     Testing (Seam Discipline, No Change-Detector Tests & Real Doubles)_ · _8.
     Reuse_ · _9. Simplification_ · _10. Efficiency_ · _11. Altitude_ · _12.
     Readability & Conventions_ · _13. Cyclomatic Complexity_.
   - In `Review Mode: Deep`, run deterministic CLI verification (`dart format`,
     `dart analyze --fatal-infos`, `cognitive_complexity`, `dart test`) once in
     the parent agent, then dispatch strictly read-only subagents
     (`Model: "flash"`, `EnableWriteTools: false` or a read-only `Explore` /
     `research` agent type with no shell execution; never an unrestricted
     general subagent) across bounded file slices (`<= 10` files per subagent)
     and angle clusters before running the Inquisitor pass. Forbid subagents
     from running `dart test`, `dart analyze`, or task polling, and have each
     return its markdown findings directly in its reply so the parent agent
     synthesizes `pr_review_<PR>.md`.
2. **Empirical Verification & Anti-Slop Gate**:
   - Before keeping a candidate finding or offering
     `"Select findings to post inline to GitHub"`, empirically verify it via
     local test execution (`dart analyze --fatal-infos`, `dart test` on Tier 1)
     or live CI check inspection (`gh pr checks <PR>` and
     `gh run view <id> --log-failed` on Tier 2). Discard any theoretical claim
     contradicted by passing tests or CI checks, and apply the Inquisitor
     Filters (`[DISMISSED: INVENTED_ARCHITECTURE]`, `[DISMISSED: PARANOIA]`,
     `[DISMISSED: PEDANTIC_ESCALATION]`, `[DISMISSED: HARMLESS]`,
     `[DISMISSED: HALLUCINATED_API]`).
3. **Assign Severity**: 🚨 `[BLOCKING]`, 💡 `[SUGGESTION]`, or 🧹
   `[HYGIENE_NIT]` (suppress nits if zero blocking/suggestions exist).

---

### Step 4: Two-Layer Report Formatting (`Internal Proof` vs. `Outbound Comment`)

Save the report to `<appDataDir>/brain/<conversation_id>/pr_review_<PR>.md` (if
running in a delegated subagent, return markdown in your reply for the parent
agent to write `pr_review_<PR>.md`, and echo the Paranoia Header in chat). Keep
call-site traces in **`Internal Proof (Do Not Post)`** and cap
**`Outbound Inline Comment`** at **`<= 50 words` (2-3 sentences)** stating **(1)
what breaks or regresses** and **(2) the concrete fix**:

```markdown
# Code Review: <Repo> PR #<Number> - <PR Title>
🛡️ Paranoia Tier: Ring <0..4B> (<Label>) · Confidence: <High|Low> · Door: <🚪 One-Way | 🔄 Two-Way> -> Review Mode: <Standard | Deep>
**PR**: [<owner>/<repo>#<number>](https://github.com/<owner>/<repo>/pull/<number>) | **Author**: `<author>` | **Head**: `<headRef>` (`<headSHA>`)
**Verdict**: `✅ Approved` | `⚠️ Approved with suggestions` | `❌ Changes requested`

## Executive Summary
- <1-2 bullet summary of change intent, review outcome, and Inquisitor filter count>

### Spec & Issue Contract Traceability
| Requirement | Status [Met ✅ / Partial ⚠️ / Unmet ❌ / Out-of-Scope ➖] | Evidence (file:line & test) |
| :--- | :--- | :--- |
| <Requirement from issue #N> | Met ✅ | `lib/foo.dart:42`, `test/foo_test.dart:18` |

## Findings
### 🚨 Blocking Issues / 💡 Suggestions / 🧹 Hygiene Nits
- [ ] [**path/to/file.dart#L42-L48**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L42-L48)
  - **Internal Proof (Do Not Post)**: <Call-site trace, caller fan-in, invariant check, and Inquisitor filter proof.>
  - **Outbound Inline Comment (`<= 50 words`)**:
    > <1 sentence stating what breaks/throws + 1 sentence or `suggestion` block with the concrete fix.>
```

---

### Step 5: 2-Tier Interactive Action Gate (`ask_question`) & Posting Hygiene

Present the `ask_question` gate tailored to the Ownership Tier (`OQ1`) and
`Review Mode` (`OQ3`):

- **Tier 1 (Own Repo `kevmoo/*` + Author `kevmoo` or local feature branch)**:
  1. `"(Recommended) Auto-fix valid findings locally, run tests (kscripts pr-check), and stage/push"`
  2. `"Keep findings in local report artifact"`
  3. `"Select findings to post inline to GitHub"`
  4. _(Include whenever `Review Mode: Standard` was used)_
     `"Escalate to Deep / Paranoid Review (--deep multi-agent pass)"`
- **Tier 2 (External/Peer PR or non-`kevmoo` author — Strictly Read-Only Local
  Checkout)**:
  1. `"(Recommended) Keep findings in local report artifact"`
  2. `"Select findings to post inline to GitHub"`
  3. _(Include whenever `Review Mode: Standard` was used)_
     `"Escalate to Deep / Paranoid Review (--deep multi-agent pass)"`

**Outbound Posting Guardrails (When Option
`"Select findings to post inline to GitHub"` Is Chosen)**:

- **Empirical Pre-Post Gate**: Never offer or post inline review comments to
  GitHub until local tests (`dart test` / `kscripts pr-check` on Tier 1) or live
  CI check runs (`gh pr checks <PR>` on Tier 2) have been inspected and confirm
  the finding is not a false positive.
- **Mandatory Diff-Hunk `line` & `start_line` Check (`HTTP 422` Prevention)**:
  Because Step 2 inspects complete files (`view_file`), a finding may target
  lines outside a modified `@@ -a,b +c,d @@` hunk. GitHub's REST API resolves
  inline `comments[].line` **and `comments[].start_line`** anchors strictly
  within modified diff hunks (returning `HTTP 422: Line could not be resolved`
  if either `line` or `start_line` falls outside the hunk or spans across an
  unmodified gap). Before posting, verify every inline comment's `line` (and
  `start_line` when multi-line, ensuring `start_line <= line`) against
  `git diff` / `gh pr diff <PR>` on `side: "RIGHT"`:
  - **In-hunk (`line` and `start_line` inside the same diff hunk)**: Anchor
    inline via `comments[].line` (and optional `start_line`, `side: "RIGHT"`).
  - **Out-of-hunk / pre-existing lines**: Clamp `start_line`/`line` to the
    modified hunk range if applicable, or label as
    `(Pre-existing, outside diff hunk)` and place in the top-level review `body`
    with a blob permalink
    (`https://github.com/<owner>/<repo>/blob/<sha>/<path>#L<line>`).
- **Post Only the Outbound Comment Text**: In GitHub review comments, include
  only the `Outbound Inline Comment` prose (`<= 50 words`) and any `suggestion`
  block, keeping `Internal Proof` traces and severity badges (`🚨`, `💡`) in the
  local report artifact.
- **Keep Top-Level Review Body Minimal**: Set the top-level GitHub review `body`
  to `""` when all posted comments are in-hunk inline comments, populating
  `body` only when routing an out-of-hunk note or a user-requested summary lead.
