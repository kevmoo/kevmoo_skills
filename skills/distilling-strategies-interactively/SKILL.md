---
name: distilling-strategies-interactively
description: |-
  Analyzes unstructured artifacts (proposals, design docs, issues, notes) to
  identify gaps, contradictions, and implicit assumptions, and interviews the
  user via a structured quiz to distill a definitive strategy and trade-off
  matrix. Use when resolving competing architectural proposals, clarifying
  ambiguous project goals, identifying blind spots in early design documents,
  or synthesizing consensus from fragmented team notes. Don't use for simple
  text summarization without strategic synthesis, writing code solutions
  directly, or managing task lists without strategic decision-making.
key_features:
  - Artifact mapping & contradiction triage
  - Socratic interviewing & interactive quiz
  - Scenario modeling & trade-off matrix
  - Strategy synthesis & action plan
---

# Distilling Strategies Interactively

Use this skill to shift from a pure execution agent to a Socratic engineering
partner. Instead of unilaterally choosing a path or trying to implement a
solution based on fragmented, contradictory, or incomplete documents, map the
landscape, expose hidden assumptions, interview the user to resolve ambiguities,
and synthesize a definitive decision matrix and action plan.

## Why This Approach Matters

- **Avoids Premature Optimization:** Writing code before resolving
  architectural contradictions leads to wasted effort and refactoring loops.
- **Extracts Tacit Knowledge:** The most critical constraints (deadlines,
  organizational risk tolerance, legacy systems) are rarely written down in
  the primary technical proposals; they exist in the user's head.
- **Builds Consensus:** Presenting structured, modeled scenarios allows the
  user to see the direct consequences of their choices.

---

## The Workflow at a Glance

Follow this sequence to guide the user from chaos to a clear action plan. Copy
this checklist to track progress:

- [ ] **Phase 1: Artifact Mapping & Contradiction Triage** → Output: Strategic
  Landscape Analysis
- [ ] **Phase 2: The Socratic Interview** → Output: Structured 4-6 Question
  Quiz (Execution Halted)
- [ ] **Phase 3: Scenario Modeling & Trade-Off Matrix** → Output: Clean
  Markdown comparison table (Triggered by Quiz answers)
- [ ] **Phase 4: Final Synthesis & Action Plan** → Output:
  `DISTILLED_STRATEGY.md`

---

## Detailed Execution Phases

### Phase 1: Artifact Mapping & Contradiction Triage

Scan the target directory `{document_directory}` containing the unstructured
files. Do not write any implementation code yet. Construct and document a map of
the strategic landscape, focusing on:

1. **Competing Paths:** Identify where different documents or proposals suggest
   fundamentally different solutions to the same problem.
2. **Blind Spots:** Locate critical dimensions that are unaddressed (e.g.,
   operational costs, migration path, legacy compatibility, long-term
   maintenance).
3. **Implicit Assumptions:** Highlight what the documents take for granted
   (e.g., "assuming the API is stable," "assuming infinite scalability").

#### Phase 1 Output Example

Present this analysis to the user to demonstrate understanding:

```markdown
### Strategic Landscape Analysis

#### Competing Paths
*   Path A (Proposal 1): Suggests a complete rewrite using Framework X for
    maximum performance.
*   Path B (Proposal 2): Suggests an incremental refactor of the existing
    legacy system to minimize short-term risk.

#### Blind Spots
*   Neither proposal addresses the data migration strategy for the 10M existing
    users.
*   No timeline estimates are provided for the training required for the team to
    adopt Framework X.

#### Implicit Assumptions
*   Proposal 1 assumes we can freeze feature development for 3 months during the
    rewrite.
```

---

### Phase 2: The Socratic Interview (The Quiz)

Based on the contradictions and blind spots identified in Phase 1, generate a
highly targeted, interactive quiz to extract the user's latent constraints.

**Rules for the Quiz:**

- Limit the quiz to **4 to 6 questions** total to avoid fatigue.
- Avoid vague questions (e.g., "What do you want?"). Use forced-choice or
  comparative questions.
- **Interactive Option Selection**:
  - If the hosting platform supports interactive choice modals (e.g., Antigravity's `ask_question` tool), you are strongly encouraged to present predictable or multiple-choice questions using that tool (configured with `is_multi_select: true` or single-select) to reduce user typing overhead.
  - For open-ended questions, or if the harness does not support interactive question modals, fall back to outputting the quiz as a numbered Markdown list directly in chat.
- Structure the quiz into exactly three categories:

1. **Hard Constraints & Guardrails:** Focus on unyielding boundaries (e.g.,
   deadlines, budget, legacy systems).
2. **Appetite & Risk Tolerance:** Gauge preference for incremental safety vs.
   high-conviction leaps.
3. **Tie-Breakers for Foundational Forks:** Force a choice on the key conflicts
   identified in Phase 1.

#### Phase 2 Output Example

```markdown
### Strategic Alignment Quiz

Please answer the following questions to help narrow down the path forward:

#### Category 1: Hard Constraints & Guardrails
1. Do we have a hard deadline for the first release that would make a complete
   rewrite (Path A) highly risky?
2. Are there specific legacy APIs we must maintain backward compatibility with?

#### Category 2: Appetite & Risk Tolerance
3. Is our primary goal a conservative, stable evolution (lower risk, higher
   technical debt), or a bold architectural reset (higher risk, clean slate)?

#### Category 3: Foundational Tie-Breakers
4. Proposal A prioritizes developer ergonomics but increases cloud spend by
   ~30%. Proposal B keeps costs flat but requires manual boilerplates. Which
   trade-off do you prefer?

---
[AWAITING_USER_INPUT: Provide your answers to the questions above to proceed with synthesis.]
```

> [!IMPORTANT] **STRICT GATE:** After outputting the quiz, you MUST halt all
> autonomous generation. Do not attempt to guess the answers or proceed to Phase
> 3 until the user has explicitly responded.

---

### Phase 3: Scenario Modeling & Trade-Off Matrix

*(This phase activates ONLY after the user provides their answers to the Phase 2
quiz.)*

Evaluate the competing paths through the lens of the user's quiz responses.
Synthesize these into a clean Markdown table comparing the top 2 viable
options.

Use this exact schema:

Dimension                                                              | Option A: {Name}                                       | Option B: {Name}
:--------------------------------------------------------------------- | :----------------------------------------------------- | :--------
**Core Concept**                                                       | *Brief description of this path.*                      | *Brief description of this path.*
**Alignment with Your Goals**                                          | *Explain how this path satisfies or violates the specific preferences expressed in the quiz.*                       | *Explain how this path satisfies or violates the specific preferences expressed in the quiz.*
**The Catch / Tax**                                                    | *What you explicitly sacrifice if you choose this path (e.g., developer speed, infrastructure cost, migration time).*         | *What you explicitly sacrifice if you choose this path.*
**Execution Friction**                                                 | *Low / Medium / High, with a 1-sentence justification based on the artifacts.*                                 | *Low / Medium / High, with a 1-sentence justification based on the artifacts.*

---

### Phase 4: Final Synthesis & Action Plan

Create a definitive document named `DISTILLED_STRATEGY.md` in the conversation
artifacts directory (`<appDataDir>/brain/<conversation-id>`) using the
`write_to_file` tool. Save this document without requesting interactive
approval/feedback (e.g., set `RequestFeedback: false` if using Antigravity's
`ArtifactMetadata`), as it serves as a strategic record rather than an
interactive gateway to immediate execution. This document serves as the source of truth for execution.

Structure the document as follows:

1. **The Recommended Path:** A clear, singular recommendation. Justify *why*
   this path is the optimal choice based on the intersection of the technical
   artifacts and the user's quiz inputs.
2. **Immediate Next Steps (3-5 Actions):** Actionable, concrete steps to
   kickstart the chosen path immediately. Avoid vague steps.
3. **Deferred Decisions (Fast-Follows):** List secondary decisions that can be
   safely put off to keep momentum high now, preventing analysis paralysis.

#### Phase 4 Output Example (`DISTILLED_STRATEGY.md`)

```markdown
# Distilled Strategy: Incremental Modernization

## 1. The Recommended Path
Based on the provided proposals and your quiz responses, we recommend
**Option B (Incremental Modernization)**. While a complete rewrite (Option A)
offers a cleaner codebase, your hard deadline of Q3 and low risk tolerance make
it non-viable. Option B allows us to deliver value incrementally while
systematically paying down technical debt.

## 2. Immediate Next Steps
*   **Action 1:** Define the boundary interfaces for the legacy module to
    prepare for extraction.
*   **Action 2:** Set up a shadow deployment pipeline to compare the performance
    of the refactored module under production-like load.
*   **Action 3:** Archive Proposal A (Complete Rewrite) to align team focus.

## 3. Deferred Decisions (Fast-Follows)
*   **Deferred:** Selection of the state management library for the front-end
    (can be deferred until Sprint 3).
*   **Deferred:** Migration of historical analytics data (can be deferred until
    post-launch Phase 1.5).
```
