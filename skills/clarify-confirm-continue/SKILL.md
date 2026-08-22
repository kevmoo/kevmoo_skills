---
name: clarify-confirm-continue
description: >-
  Orchestrates a disciplined task intake workflow across code, docs, and project
  files by autonomously fact-checking the workspace, resolving genuine decision
  forks, and confirming execution readiness via ask_question before making
  modifications. Use when starting multi-step tasks, refactorings, ambiguous
  feature requests, broad documentation updates, or when invoked via
  /clarify-confirm-continue or "ccc". Don't use for trivial single-turn lookups,
  straightforward single-line edits where intent is unambiguous, or emergency
  rollbacks.
---

# Clarify-Confirm-Continue (`ccc`)

Disciplined task intake workflow for multi-step or complex user requests across
codebases, document trees, and project workspaces. Ensures the agent and user
are fully aligned before any modification or extensive execution begins.

## Composability

- **Design Interviews**: Works seamlessly alongside the `grilling` skill when an
  extended multi-turn architectural interrogation is warranted before drafting
  the plan.

## Procedural Workflow

### Phase 1: Fact-Checking & Fork-Hunting

#### 1. Fact-Check the Workspace First (Zero-User-Burden)
Before asking any questions, inspect the environment autonomously using
read-only tools (`grep_search`, `view_file`, `list_dir`, `code_search`,
`moma_search`):
- **Codebases**: Check function signatures, type definitions, conventions, and
  existing test suites.
- **Documents & Project Files**: Read relevant Markdown files (`*.md`), design
  docs (`g3doc/`, `docs/`), notes, specifications, references, and schemas.
- **Rule**: Never ask the user for verifiable facts that already exist in the
  workspace files or documentation.

#### 2. Fork-Hunting (Genuine Decisions vs. Fake Dilemmas)
Evaluate the task for unresolved decisions by categorizing them:

<!-- mdformat off(prevent table wrapping) -->
| Category | Definition | Action |
| :--- | :--- | :--- |
| **Workspace Facts** | Verifiable via inspection tools. | **Never ask**; inspect autonomously. |
| **Fake Dilemmas** | Obvious right choice vs obviously broken choices; asking permission for standard best practices. | **Never ask**; execute the obvious right choice. |
| **Genuine Decision Forks** | 2+ viable, defensible paths with real trade-offs (API design, document framing, breaking changes). | **Clarify** before summarizing. |
<!-- mdformat on -->

* **Examples of Fake Dilemmas (Do not ask—execute standard best practices)**:
  - *"Should I write tests for the new feature?"* (Always write tests).
  - *"Should I fix the syntax error or leave it broken?"* (Obvious brownie vs.
    kick-in-the-face).
  - *"Should I format the code to comply with style rules?"* (Standard hygiene).

* **Examples of Genuine Decision Forks (Clarification required)**:
  - **API & Architecture**: Breaking change vs. deprecation shim; synchronous
    vs. streaming response; choosing between two existing architectural patterns.
  - **Documentation & Non-Code**: High-level executive summary vs. deep technical
    breakdown; standalone doc vs. appending to an existing guide; choosing between
    competing taxonomies.
  - **Scope Boundaries**: Inclusions vs. exclusions when both are reasonable and
    defensible.

#### 3. Interrogate Unsettled Forks
If one or more **Genuine Decision Forks** exist:
- Present independent decision forks in a single focused `ask_question` call; ask
  dependent/sequential forks one at a time.
- State the trade-offs clearly.
- **Always provide your recommended choice** with rationale.
- Wait for user feedback before drafting the final execution summary.
- **Anti-Smuggling Rule**: Never convert unresolved decision forks into
  unverified "assumptions" to skip this interrogation step.

---

### Phase 2: In-Modal Structured Summary & Readiness Gate (`ask_question`)

Once all genuine decision forks are settled (or immediately if zero genuine
forks exist), invoke the `ask_question` tool with a single readiness gate.

> [!IMPORTANT]
> **Preventing UI Collapse:** In many agentic harnesses (e.g., Jetski,
> Antigravity), pre-tool chat text emitted in the same turn as a tool call is
> automatically collapsed into a progress/thought accordion. To ensure the
> structured summary is immediately visible and prominent, embed the full
> markdown summary **directly inside the `question` argument** of
> `ask_question`.

Structure the `question` argument in `ask_question` using markdown:
- **🎯 Goals**: What will be accomplished.
- **🛡️ Non-Goals / Scope Boundaries**: What will explicitly be left untouched.
- **📌 Settled Decisions & Invariants**: Agreed choices from Phase 1 and verified
  workspace facts (no unresolved questions or speculative assumptions).
- **🛠️ Execution Plan**: High-level steps to be performed once approved.
- Conclude with: `*How would you like to proceed?*`

Configure the `options` array with:
- `"(Recommended) Yes, proceed"`
- `"Open in artifact"`
- `"No, adjust in chat"`

---

### Phase 3: Handling Gate Selection

- **If "(Recommended) Yes, proceed"**: Transition immediately to task execution.
- **If "Open in artifact"**: Use `write_to_file` to save the structured summary
  and execution plan as a markdown artifact (`.md` file) in the session's
  artifact directory. Configure the file to request interactive
  approval/feedback (e.g., set `RequestFeedback: true` in Antigravity's
  `ArtifactMetadata` to render a 'Proceed' button). If the harness does not
  support interactive gates, instruct the user in chat to review the file and
  reply 'Proceed' when they are ready. Stop calling tools and go idle to await
  reactive wakeup.
- **If "No, adjust in chat" or Custom Write-In**: Apply user feedback, adjust
  the scope or plan accordingly, and re-confirm if substantial changes were
  made.

---

## Execution Safety Invariants

- **No Pre-Approval Modifications**: Do not edit workspace files, create branches,
  or run mutating commands during Phase 1 or Phase 2.
- **Explicit Approval Gate**: You must receive confirmation via `ask_question`
  (or write-in approval) before transitioning to execution.
- **Global Guardrails Preserved**: Approval at the confirmation gate authorizes
  that you understand the task and authorizes you to begin drafting changes. All
  standard version control, push, PR, and landing approval gates in `AGENTS.md`
  remain independently and strictly enforced during execution.
