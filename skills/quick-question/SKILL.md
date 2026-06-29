---
name: quick-question
description: |-
  Provide ultra-concise, direct technical answers and rapid clarifications
  without heavy overhead, deep research loops, or artifact generation. (Triggers
  on "quick question" or "qq")
key_features:
  - Concise Q&A
  - rapid clarification
  - Inline answers (no artifacts)
  - Read-only guidance
---

## When to use this skill

Activate this skill when the user asks a straightforward technical question,
requests a quick clarification, asks for a TL;DR explanation, or uses the short
prefix `qq`.

Examples of trigger phrases:
- "qq..." / "qq: ..."
- "Quick question..."
- "TL;DR on..."
- "Just real quick..."

## Critical Rule: Accuracy Over Speculation & Zero Code Changes

- **ACCURACY IS THE TOP PRIORITY**: The most important goal when using this
  skill is offering ACCURATE guidance. Guessing or making wild assumptions
  makes the agent less likely to be accurate.
- **NO FILE EDITS OR CREATION**: Zero file changes are expected or allowed. Do
  not edit files or alter repository state.
- **DO NOT ASSUME ACTION IS DESIRED**: Answer the question directly. Never
  assume the user wants to implement or execute code changes based on your
  answer.

## Procedural & Formatting Rules

### 1. Handling Unclear Requests (Be Up-Front)
- If the user's question is vague or unclear, be completely up-front about it
  inline in your response rather than making blind guesses.
- Feel free to use phrasing such as:
  - *"I'm not completely sure, but I think you're asking about XYZ..."*
  - *"I don't really understand what you mean. Can you offer a bit more
    context?"*

### 2. Direct Chat Output (NO Artifacts)
- **Direct Chat Response**: Do NOT create artifacts (`.md` files in the
  conversation artifacts directory) for quick questions. Deliver the response
  inline directly to the user.

### 3. Conciseness & Structure
- **Brief TL;DR**: Always lead with a very brief TL;DR or direct answer.
- **Bullets Over Tables**: Use bullet points instead of complex markdown tables
  to convey information cleanly and rapidly.
- **No Heavy Overhead**: Avoid multi-paragraph background explanations,
  unsolicited refactoring advice, or heavy automated search loops unless
  necessary for basic correctness.

### 4. Tool Avoidance (`ask_question`)
- **AVOID `ask_question` tool calls**: Do not invoke the interactive modal tool.
  Instead, address any ambiguity directly inline within your chat response.

### 5. Optional Next Steps
- Feel free to suggest **0 to 3 obvious next steps** at the end of your response
  if they are genuinely useful, but keep them brief and non-intrusive.
