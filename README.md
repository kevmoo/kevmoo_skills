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
| **[distilling-strategies-interactively](skills/distilling-strategies-interactively/SKILL.md)** | Analyzes unstructured artifacts (proposals, design docs, issues, notes) to identify gaps, contradictions, and implicit assumptions, and interviews the user via a structured quiz to distill a definitive strategy and trade-off matrix. Use when resolving competing architectural proposals, clarifying ambiguous project goals, identifying blind spots in early design documents, or synthesizing consensus from fragmented team notes. Don't use for simple text summarization without strategic synthesis, writing code solutions directly, or managing task lists without strategic decision-making. | Artifact mapping & contradiction triage, Socratic interviewing & interactive quiz, Scenario modeling & trade-off matrix, Strategy synthesis & action plan |
| **[encapsulated-method-object](skills/encapsulated-method-object/SKILL.md)** | Apply the "Encapsulated Method Object" refactoring pattern to simplify functions with deeply nested scopes, bloated closures, and heavy shared local state. | Method Object extraction, class-based encapsulation, Closure refactoring |
| **[gerrit-stacked-cls](skills/gerrit-stacked-cls/SKILL.md)** | Best practices for managing stacked changelists (CLs) in Gerrit using depot_tools, avoiding common pitfalls with Change-Ids. | Stacked CLs, Gerrit, depot_tools, Change-Ids |
| **[github-pr-triage](skills/github-pr-triage/SKILL.md)** | Triage open PR comments/reviews and associated CI/CD workflow failures using the `triage.dart` helper script and formulate an actionable plan. | Review feedback triaging, CI log extraction, Action plan generation |
| **[gob-curl](skills/gob-curl/SKILL.md)** | Use gob-curl and Buildbucket tools to inspect the status, tryjobs, and CI results of a Gerrit CL. | Gerrit CL inspection, Buildbucket tryjob inspection |
| **[just-brainstorm](skills/just-brainstorm/SKILL.md)** | Brainstorm architectural designs, explore potential solutions, and weigh implementation tradeoffs collaboratively without making code changes. | Architectural design, trade-off evaluation, Design requirement clarification, Non-destructive exploration |
| **[markdown-long-lines](skills/markdown-long-lines/SKILL.md)** | Ensure markdown prose lines wrap within 80 columns, excluding code blocks, URLs, and tables. | Markdown formatting, 80-column line wrapping, Formatting exclusions |
| **[pr-loop](skills/pr-loop/SKILL.md)** | Autonomous pull request review loop that pushes code, polls for AI/bot review comments (e.g., Gemini Code Assist), surgically remediates feedback, commits, pushes, comments `/gemini review`, and loops until zero feedback remains. Requires the `github-pr-triage` skill. | PR review loop, autonomous iteration, Review comment polling, Automated feedback remediation |
| **[quick-question](skills/quick-question/SKILL.md)** | Provide ultra-concise, direct technical answers and rapid clarifications without heavy overhead, deep research loops, or artifact generation. (Triggers on "quick question" or "qq") | Concise Q&A, rapid clarification, Inline answers (no artifacts), Read-only guidance |
| **[sem-semantic-diff](skills/sem-semantic-diff/SKILL.md)** | Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes. | Semantic diffs, impact analysis, dependency graphs |
| **[what-if](skills/what-if/SKILL.md)** | Perform "what-if" scenario analysis and impact evaluations for proposed codebase changes, migrations, or architectural shifts. | What-if analysis, Codebase metric gathering, impact evaluation, risk assessment |
<!-- SKILLS_LIST_END -->

