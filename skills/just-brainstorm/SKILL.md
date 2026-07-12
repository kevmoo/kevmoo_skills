---
name: just-brainstorm
description: |-
  Brainstorm architectural designs, explore potential solutions, and weigh
  implementation tradeoffs collaboratively without making code changes.
key_features:
  - Architectural design
  - trade-off evaluation
  - Design requirement clarification
  - Non-destructive exploration
---

## When to use this skill

Activate this skill when the user asks to brainstorm, explore design ideas,
discuss potential solutions, or outline architecture before committing to
execution.

Examples of trigger phrases:
- "Let me brainstorm..."
- "Just brainstorming here..."
- "What are some ways we could solve..."
- "Help me design..."

## Critical Rule: Zero Code Changes Allowed

- **NO CODEBASE FILE EDITS OR CREATION**: Under no circumstances should you edit
  existing project files, write new implementation code, or modify repository
  state. (Note: Writing the mandatory design artifact using `write_to_file` as
  described in the workflow below is the only permitted file creation).
- **READ-ONLY INSPECTION IS ALLOWED**: You are fully authorized and encouraged
  to inspect the codebase using read-only tools (`grep_search`, `view_file`,
  `list_dir`) to understand the current architecture and ground your
  brainstorming in reality.
- **DO NOT ASSUME IMPLEMENTATION IS DESIRED**: Never jump from brainstorming
  directly into writing code unless explicitly commanded in a separate
  follow-up turn.

## Procedural Workflow

### 1. Interactive Alignment (`ask_question`)
- You are **strongly encouraged** to use the `ask_question` tool early to
  request clarification, surface design choices, and align on goals or
  constraints before drafting extensive proposals.

### 2. Mandatory Artifact Generation
- The output of this skill **MUST be saved as an artifact** (`.md` file in the
  conversation artifacts directory using the `write_to_file` tool) so the user
  can easily review, share, and comment on specific sections.
- Format the artifact clearly with headers, options tables, and pros/cons
  breakdowns.

### 3. Structure Your Proposals
- Present 2–4 distinct architectural or conceptual options (e.g., simple vs.
  scalable, synchronous vs. asynchronous).
- Highlight tradeoffs, impact on existing code, and relative complexity for each
  option.
- Summarize discussion points for the user to consider.

### 4. Offer Obvious Next Steps
- Conclude by suggesting relevant, actionable next steps based on the context.
- Examples of suggested next steps (pick 1–3 that fit best or tailor your own):
  - Create a GitHub issue to track the design/decision.
  - Explore one of the proposed options deeper.
  - Create an implementation plan based on the preferred option.
  - Begin implementing the preferred plan.
- You are not required to include all suggestions—tailor them to what makes the
  most sense for the current discussion.
