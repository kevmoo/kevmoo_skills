---
name: clarify-confirm-continue
description: |-
  Intake multi-step tasks by clarifying ambiguities, summarizing understanding,
  and confirming readiness via ask_question before executing code changes.
key_features:
  - Task intake and scope verification
  - Shorthand ccc and pre-flight triggers
  - Compositional grilling for ambiguity resolution
  - Fast-tracking for VERY obvious assumptions
  - Structured understanding summary
  - On-demand artifact generation for complex iteration
  - Single-click readiness confirmation gate
---

# Clarify-Confirm-Continue (`ccc` / Pre-Flight)

This skill defines a disciplined task intake and pre-flight check workflow for multi-step or complex user requests. It ensures the agent and user are fully aligned before any codebase modification or extensive execution begins.

## 📦 Prerequisites & Skill Dependencies
- **REQUIRED SKILL**: `grilling` MUST be installed alongside `clarify-confirm-continue` for Tier 2 ambiguity resolution.

## When to use this skill
Activate when the user assigns a task and requests a pre-flight check, or uses trigger phrases like:
- `"ccc"` / `"clarify-confirm-continue"`
- `"pre-flight"` / `"check with me first"` / `"before you start"`
- `"make sure you understand"` / `"confirm before proceeding"`

## Procedural Workflow

### Phase 1: Clarification & Fact-Finding
1. **Investigate Facts First**: Use read-only tools (`grep_search`, `view_file`, `list_dir`) to check existing code patterns, architecture, or definitions. Never ask the user for verifiable facts that the codebase can answer directly.
2. **Assess Ambiguity (Two-Tier Check)**:
   - **Tier 1 (VERY Obvious)**: If the task is straightforward and any assumptions or inferences are **VERY obvious** (things that do not require interactive debate, but are simply worth mentioning for transparency), proceed directly to Phase 2.
   - **Tier 2 (Ambiguous / Decisions Needed)**: If major architectural decisions, multiple interpretations, or non-obvious trade-offs exist, apply the Q&A pattern from `grilling`:
     - Ask clarifying questions **one at a time**.
     - Provide your recommended answer for each question.
     - Wait for user feedback on each question before continuing.
     *(Do not present the final summary or readiness confirmation until all questions are answered).*

### Phase 2: Structured Summary
Once all ambiguities are resolved (or immediately if Tier 1 applies), output a structured summary in your chat response:
- **🎯 Goals**: What will be accomplished.
- **🛡️ Non-Goals / Scope Boundaries**: What will explicitly be left untouched.
- **📌 Assumptions**: Verifiable facts or VERY obvious inferences worth mentioning.
- **🛠️ Execution Plan**: High-level steps to be performed once approved.

### Phase 3: Readiness Gate (`ask_question`)
Immediately following the summary in the same turn, invoke the `ask_question` tool with a single, mandatory confirmation check:
- **Question**: *"I have summarized my understanding above. How would you like to proceed?"*
- **Options**:
  - `"(Recommended) Yes, proceed as summarized."`
  - `"Open this proposal in a markdown artifact so we can iterate on specific sections."`
  - `"No, let's adjust the scope or clarify further in chat."`

### Phase 4: Handling Gate Selection
- **If "Yes, proceed"**: Transition immediately to task execution.
- **If "Open in artifact"**: Use `write_to_file` to save the structured summary and execution plan as a markdown artifact (`.md` file) in the session's artifact directory. Stop calling tools and wait for the user's line-by-line review and comments.
- **If "No, adjust in chat"**: Ask what needs adjustment or loop back to Phase 1.

## Critical Rule: Zero Execution Before Approval & Global Rules
- **NO CODE MODIFICATIONS**: Do not edit project files, create branches, or run mutating commands during Phase 1, 2, or 3.
- **STRICT GATING**: You must receive explicit approval via `ask_question` (or clear write-in approval) before transitioning to task execution.
- **GLOBAL RULES UNCHANGED**: Approval at the Phase 3 gate simply confirms that you understand the task and authorizes you to begin researching or drafting code. **Nothing changes about global Git/GitHub write restrictions or commit rules in `AGENTS.md`**—all standard outward-facing write approvals remain strictly and independently enforced during execution.
