<a href="https://agentskills.io"><img src="https://img.shields.io/badge/Compliance-Standard%20Agent%20Skills-brightgreen.svg" alt="Standard Agent Skills"></a>


This is my personal repository for specialized **Agent Skills**. These skills provide
procedural, actionable instructions to AI assistants for specific domains or tasks.

## Skills Inventory

<!-- SKILLS_LIST_START -->
To install any skill individually:
```bash
npx skills add kevmoo/kevmoo_skills --skill <skill-name>
```

| Skill | Description | Key Features |
|-------|-------------|--------------|
| **[clarify-confirm-continue](skills/clarify-confirm-continue/SKILL.md)** | Intake multi-step tasks by clarifying ambiguities, summarizing understanding, and confirming readiness via ask_question before executing code changes. | Task intake and scope verification, Shorthand ccc and pre-flight triggers, Compositional grilling for ambiguity resolution, Fast-tracking for VERY obvious assumptions, In-modal structured understanding summary, On-demand artifact generation for complex iteration, Single-click readiness confirmation gate |
| **[distilling-strategies-interactively](skills/distilling-strategies-interactively/SKILL.md)** | Analyzes unstructured artifacts (proposals, design docs, issues, notes) to identify gaps, contradictions, and implicit assumptions, and interviews the user via a structured quiz to distill a definitive strategy and trade-off matrix. Use when resolving competing architectural proposals, clarifying ambiguous project goals, identifying blind spots in early design documents, or synthesizing consensus from fragmented team notes. Don't use for simple text summarization without strategic synthesis, writing code solutions directly, or managing task lists without strategic decision-making. | Artifact mapping & contradiction triage, Socratic interviewing & interactive quiz, Scenario modeling & trade-off matrix, Strategy synthesis & action plan |
| **[encapsulated-method-object](skills/encapsulated-method-object/SKILL.md)** | Apply the "Encapsulated Method Object" refactoring pattern to simplify functions with deeply nested scopes, bloated closures, and heavy shared local state. | Method Object extraction, class-based encapsulation, Closure refactoring |
| **[gerrit-stacked-cls](skills/gerrit-stacked-cls/SKILL.md)** | Best practices for managing stacked changelists (CLs) in Gerrit using depot_tools, avoiding common pitfalls with Change-Ids. | Stacked CLs, Gerrit, depot_tools, Change-Ids |
| **[github-pr-triage](skills/github-pr-triage/SKILL.md)** | Triage open PR comments/reviews and associated CI/CD workflow failures using the `triage.dart` helper script and formulate an actionable plan. | Review feedback triaging, CI log extraction, Action plan generation |
| **[gob-curl](skills/gob-curl/SKILL.md)** | Use gob-curl and Buildbucket tools to inspect the status, tryjobs, and CI results of a Gerrit CL. | Gerrit CL inspection, Buildbucket tryjob inspection |
| **[just-brainstorm](skills/just-brainstorm/SKILL.md)** | Ponder architectural designs, explore potential solutions, weigh tradeoffs, or analyze the impact of proposed codebase changes without making code changes. Always outputs the analysis to a Markdown artifact. | Architectural design, Trade-off evaluation, Impact & "what-if" analysis, Codebase metric gathering |
| **[markdown-long-lines](skills/markdown-long-lines/SKILL.md)** | Ensure markdown prose lines wrap within 80 columns, excluding code blocks, URLs, and tables. | Markdown formatting, 80-column line wrapping, Formatting exclusions |
| **[pr-loop](skills/pr-loop/SKILL.md)** | Autonomous pull request review loop that pushes code, polls for AI/bot review comments (e.g., Gemini Code Assist), surgically remediates feedback, commits, pushes, comments `/gemini review`, and loops until zero feedback remains. Requires the `github-pr-triage` skill. | PR review loop, autonomous iteration, Review comment and CI polling, Automated feedback remediation, Dynamic/adaptive CI polling |
| **[quick-question](skills/quick-question/SKILL.md)** | Provide ultra-concise, direct technical answers and rapid clarifications without heavy overhead, deep research loops, or artifact generation. (Triggers on "quick question" or "qq") | Concise Q&A, rapid clarification, Inline answers (no artifacts), Read-only guidance |
| **[sem-semantic-diff](skills/sem-semantic-diff/SKILL.md)** | Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes. | Semantic diffs, impact analysis, dependency graphs |
| **[sidequest](skills/sidequest/SKILL.md)** | Synthesizes conversation history and active tasks into a visual hierarchy map (`sidequest.md`) backed by a deterministic JSON state file (`sidequest.json`). Supports multiple sequential and concurrent main quests, sub-quests, and side-quests with automatic hierarchical numbering and completion sequencing. Use when the user invokes `/sidequest`, asks where we are, what we were doing, or what's on our stack, or when the conversation branches across multiple topics, blockers, or digressions. Don't use for simple one-off questions. |  |
<!-- SKILLS_LIST_END -->

