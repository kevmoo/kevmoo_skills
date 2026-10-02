---
name: pr-review
description: >-
  Reviews GitHub Pull Requests or local Git branch diffs using an adversarial 13-angle review rubric and the Inquisitor Presumption of Theater doctrine to eliminate LLM noise. Evaluates code correctness, removed behavior, error handling, testing, and simplification, generates a ranked Markdown report with clickable line permalinks, and presents an interactive action gate (keep findings, apply local fixes, or post inline to GitHub). Use when reviewing a PR (#N or URL), auditing a local feature branch, or invoked via /pr-review. Don't use for Google3 Piper changelists (use /cl-finalize or review) or general formatting.
key_features:
  - Explicit 3D Paranoia Tiering (Ring, Confidence, One-Way/Two-Way Door) with --deep escalation
  - Two-Axis Evaluation (Linked Issue Spec Traceability + CODING_STANDARDS.md)
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
   traceability (`gh issue view <N>`) alongside `~/.agents/CODING_STANDARDS.md`
   and the 13-angle defect rubric in [`RUBRIC.md`](RUBRIC.md).
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

2. **Linked Issue & Spec Extraction (`FU1`)**:
   - When a PR links an issue (`Fixes #N`, `Closes #N`, or prompt issue URL),
     fetch the specification contract:
     ```bash
     gh issue view <N> --json title,body
     ```

3. **3D Paranoia Header & Review Mode Selection (`OQ3`)**:
   - Always compute and render at the top of `pr_review_<PR>.md` and in visible
     chat:
     `🛡️ Paranoia Tier: Ring <0..4B> (<Label>) · Confidence: <High|Low> · Door: <🚪 One-Way | 🔄 Two-Way> -> Review Mode: <Standard | Deep>`
   - **Ring Defaults**:
     - **`Ring 0-2` (`kevmoo/*` personal dotfiles, skills, scripts)**: Default
       to `Review Mode: Standard` (single-pass review across the 13 angles)
       unless `--deep` / `--paranoid` is passed or `Door: 🚪 One-Way`.
     - **`Ring 3-4` (`kevmoo/*` published `pub.dev` packages, `dart-lang/*`,
       `flutter/*`, `google/*`, or low-confidence C++/VM/Wasm/Skwasm/WIMP
       domains) or `Door: 🚪 One-Way` (public API/wire/schema changes)**:
       Default to `Review Mode: Deep` (multi-subagent parallel angle audit +
       adversarial verification).
   - Support `--deep` (`--paranoid`) as an upfront flag to force
     `Review Mode: Deep` on any ring.

---

### Step 2: Two-Axis Grounding (`Spec` + `CODING_STANDARDS.md`)

Never review diff hunks in isolation. Inspect complete modified files
(`view_file`) and verify callers and SDK/package dependencies.

1. **Axis A — Spec & Issue Contract Traceability (`FU1`)**:
   - Cross-check every requirement in the linked issue (`gh issue view <N>`)
     against the implementation and test suite (`Met ✅`, `Partial ⚠️`,
     `Unmet ❌`, `Out-of-Scope ➖`). Flag unwired CLI flags or missing
     acceptance criteria.
2. **Axis B — Dart & Package Standards (`~/.agents/CODING_STANDARDS.md`)**:
   - Audit Dart diffs against `~/.agents/CODING_STANDARDS.md`:
     - **Deep Externally, Pure Internally**: Keep `lib/<pkg>.dart` and `api.txt`
       minimal. Forbid stateful single-use `_Populator` / `_Runner` helper
       classes that mutate caller collections in-place; require pure private
       functions (`_computeX(input) -> output`).
     - **Load-Bearing Library Boundary Rule**: Extract a standalone `lib/src/`
       library (`Tier 1`) only when zero `_private` visibility widening is
       needed; use `part` / `part of` (`Tier 2`) when crossing `sealed`,
       `final`, `interface`, `base`, `._()`, or `_private` class members (never
       widen `_private` to `@internal`).
     - **Public API Surface Verification**: When refactors extract helpers
       across files, verify public API stability with
       `dart run api_summary@^1.1.0` (`--check` if `api.txt` exists, or
       before/after diff).

---

### Step 3: Adversarial Evaluation (`RUBRIC.md`)

1. **Sweep the 13 Angles in [`RUBRIC.md`](RUBRIC.md)**:
   - _1. Line Scan_ · _2. Removed Behavior_ · _3. Cross-File Tracer_ · _4.
     Language Pitfalls_ · _5. Invariants & Wrappers_ · _6. Error Handling_ · _7.
     Testing (Anti-Tautology & Public-Entrypoint Seams)_ · _8. Reuse_ · _9.
     Simplification_ · _10. Efficiency_ · _11. Altitude_ · _12. Readability &
     Conventions_ · _13. Cyclomatic Complexity_.
   - In `Review Mode: Deep`, dispatch parallel subagents across angle clusters
     before running the Inquisitor pass. Subagents must return their markdown
     findings in their response message (never call `write_to_file` on a parent
     conversation's `<appDataDir>/brain/<parent_cid>/` path, which is blocked by
     the subagent artifact sandbox).
2. **Execute Inquisitor Filters ("Presumption of Theater")**: Discard any
   finding matching `[DISMISSED: INVENTED_ARCHITECTURE]`,
   `[DISMISSED: PARANOIA]`, `[DISMISSED: PEDANTIC_ESCALATION]`,
   `[DISMISSED: HARMLESS]`, or `[DISMISSED: HALLUCINATED_API]`.
3. **Assign Severity**: 🚨 `[BLOCKING]`, 💡 `[SUGGESTION]`, or 🧹
   `[HYGIENE_NIT]` (suppress nits if zero blocking/suggestions exist).

---

### Step 4: Two-Layer Report Formatting (`Internal Proof` vs. `Outbound Comment`)

Save the report to `<appDataDir>/brain/<conversation_id>/pr_review_<PR>.md`
using the active conversation's own `<conversation_id>` (if running inside a
delegated subagent, return the markdown directly in your response for the parent
agent to write `pr_review_<PR>.md`, and echo the Paranoia Header in visible
chat).

> [!IMPORTANT]
>
> **Never Leak Internal Inquisitor Proof into Outbound GitHub Comments**: To
> pass [`RUBRIC.md`](RUBRIC.md)'s Inquisitor filters, you must gather mechanical
> proof. Keep that forensic trace in **`Internal Proof (Do Not Post)`** for the
> reviewer gate, and write a separate **`Outbound Inline Comment`** capped at
> **`<= 50 words` (2–3 sentences)** that states only **(1) what
> breaks/regresses** and **(2) the concrete fix**—with **zero call-stack
> narration** of code the PR author just wrote.

```markdown
# Code Review: <Repo> PR #<Number> — <PR Title>

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

### 🚨 Blocking Issues
- [ ] [**path/to/file.dart#L42-L48**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L42-L48)
  - **Internal Proof (Do Not Post)**: <Call-site trace, invariant check, and why alternatives fail Inquisitor filters.>
  - **Outbound Inline Comment (`<= 50 words`)**:
    > <1 sentence stating what breaks/throws + 1 sentence or `suggestion` block with the fix. Zero call-stack narration.>

### 💡 Suggestions
- [ ] [**path/to/file.dart#L105**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L105)
  - **Internal Proof (Do Not Post)**: <Verification of caller fan-in, complexity delta, or test seam.>
  - **Outbound Inline Comment (`<= 50 words`)**:
    > <1-2 sentences stating the simplification or edge case + concrete fix.>

### 🧹 Hygiene Nits
- [ ] [**path/to/file.dart#L12**](https://github.com/<owner>/<repo>/blob/<sha>/path/to/file.dart#L12)
  - **Outbound Inline Comment (`<= 25 words`)**:
    > <Direct 1-line nit.>
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

- Post **strictly** the `Outbound Inline Comment` text (`<= 50 words` of prose);
  never include the `Internal Proof` trace or severity emoji headers (`🚨`,
  `💡`).
- Leave the top-level GitHub review `body` empty (`""`) when inline comments are
  self-contained, unless the user explicitly provides a 1–2 sentence human lead.
