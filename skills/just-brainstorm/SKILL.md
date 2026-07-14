---
name: just-brainstorm
description: |-
  Ponder architectural designs, explore potential solutions, weigh tradeoffs,
  or analyze the impact of proposed codebase changes without making code changes.
  Always outputs the analysis to a Markdown artifact.
key_features:
  - Architectural design
  - Trade-off evaluation
  - Impact & "what-if" analysis
  - Codebase metric gathering
---

## When to use this skill

Activate this skill when you need to think through a design, explore options,
or evaluate the impact of a potential change before writing code.

Examples of trigger phrases:
- "Let me brainstorm..."
- "Just brainstorming here..."
- "What if we [do specific change]..."
- "What would break if we..."
- "How hard would it be to migrate..."
- "Help me design..."

## Critical Rule: Zero Codebase Changes

- **NO CODEBASE FILE EDITS OR CREATION**: Do not edit existing project files,
  write new implementation code, or modify repository state.
- **MANDATORY ARTIFACT GENERATION**: The only permitted file creation is the
  design/analysis artifact (`.md` file in the conversation artifacts directory).

## Procedural Workflow

### 1. Gather Context & Empirical Data (Read-Only)
- Inspect the codebase using read-only tools (`grep_search`, `view_file`, `list_dir`)
  to ground your brainstorming or analysis in reality.
- **For Impact Analysis ("What-if")**: Gather real statistics. Calculate usage
  counts, identify affected call sites, and map out dependencies. Do not guess.

### 2. Interactive Alignment (`ask_question`)
- Use `ask_question` early if the goals, constraints, or the scope of the
  "what-if" scenario are unclear.

### 3. Generate the Artifact
- Write the output to a `.md` file in the conversation artifacts directory.
- Use `RequestFeedback: false` in the artifact metadata (do not block with "Proceed" gates).
- **Structure for Design Brainstorming**:
  - Present 2–4 distinct options.
  - Highlight tradeoffs (pros/cons) and relative complexity.
- **Structure for Impact Analysis ("What-if")**:
  - Detail the step-by-step impact if the change were executed.
  - List breaking changes, migration friction, and affected modules with metrics.
  - Provide a summary risk/feasibility verdict.

### 4. Conclude with Next Steps
- Suggest 1–3 actionable next steps (e.g., create an implementation plan,
  explore a specific option deeper, or start implementation).
