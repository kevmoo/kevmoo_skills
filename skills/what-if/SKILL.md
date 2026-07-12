---
name: what-if
description: |-
  Perform "what-if" scenario analysis and impact evaluations for proposed
  codebase changes, migrations, or architectural shifts.
key_features:
  - What-if analysis
  - Codebase metric gathering
  - impact evaluation
  - risk assessment
---

## When to use this skill

Activate this skill when the user asks a what-if question or requests a thought
experiment about potential codebase modifications, deprecations, dependency
upgrades, or migrations.

Examples of trigger phrases:
- "What if..." / "What-if..."
- "What would break if we..."
- "How hard would it be to migrate to..."
- "What happens if we deprecate..."

## Critical Rule: Zero Code Changes Allowed

- **NO FILE EDITS OR CREATION**: You are explicitly forbidden from modifying
  project files, committing changes, or altering repository state.
- **DO NOT ASSUME CHANGE IS WANTED**: Treat the scenario strictly as an
  analytical evaluation. Never start making changes under the assumption that
  the user wants to implement the what-if scenario.

## Empirical Data Gathering (Read-Only)

- **Back Up Answers with Real Project Statistics**: You are strongly encouraged
  to actively inspect the codebase using read-only tools (`grep_search`,
  `view_file`, `list_dir`) to provide empirical metrics.
- Calculate exact counts and scope where possible (e.g., *"This package is
  imported across 34 files and 12 separate modules"* or *"Updating this method
  signature impacts 8 call sites in 3 packages"*).

## Procedural Workflow & Interaction Rules

### 1. `ask_question` Tool Guidelines
- **Conditional Usage Only**: Use the `ask_question` tool **ONLY if the user's
  intent or scope is unclear or vague**.
- **DO NOT USE if Clear**: If the user's what-if question is clear and
  well-defined, proceed directly to analysis without prompting the user.

### 2. Scenario Walking & Analysis
- **Direct Chat Output**: Deliver the analysis inline directly to the user in
  your chat response. Do NOT create artifacts unless the analysis is
  exceptionally long or explicitly requested.
- **Do Not Request Interactive Approval Gates**: If you generate an artifact for a long what-if analysis, ensure you do not request interactive approval/feedback (e.g., set `RequestFeedback: false` if using Antigravity's `ArtifactMetadata`). This analysis is purely informational/analytical and should not block execution with a "Proceed" gate.
- Outline the step-by-step impact if the change were actually executed.
- Identify potential breaking changes, migration friction, and ripple effects
  across dependent packages or modules.
- Provide a summary verdict estimating overall complexity, risks, and
  feasibility based on your read-only inspection.
