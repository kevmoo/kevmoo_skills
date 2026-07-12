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
| **[encapsulated-method-object](skills/encapsulated-method-object/SKILL.md)** | Apply the "Encapsulated Method Object" refactoring pattern to simplify functions with deeply nested scopes, bloated closures, and heavy shared local state. |  |
| **[gerrit-stacked-cls](skills/gerrit-stacked-cls/SKILL.md)** | Best practices for managing stacked changelists (CLs) in Gerrit using depot_tools, avoiding common pitfalls with Change-Ids. |  |
| **[github-pr-triage](skills/github-pr-triage/SKILL.md)** | Triage open PR comments/reviews and associated CI/CD workflow failures using the `triage.dart` helper script and formulate an actionable plan. |  |
| **[gob-curl](skills/gob-curl/SKILL.md)** | Use gob-curl to inspect the status of a changelist (CL) on Gerrit. |  |
| **[kevmoo-skills](skills/kevmoo-skills/SKILL.md)** | Apply personal coding preferences and customized workflows for Kevmoo's repositories, including standard formatting, common boilerplate, and preferred tooling usage. |  |
| **[pr-loop](skills/pr-loop/SKILL.md)** | Autonomous pull request review loop that pushes code, polls for AI/bot review comments (e.g., Gemini Code Assist), surgically remediates feedback, commits, pushes, comments `/gemini review`, and loops until zero feedback remains. |  |
| **[sem-semantic-diff](skills/sem-semantic-diff/SKILL.md)** | Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes. |  |
| **[sidequest](skills/sidequest/SKILL.md)** | Synthesizes conversation history and active tasks into a visual hierarchy map (`sidequest.md`) to prevent context drift and cognitive overload across long sessions. Supports multiple sequential and concurrent main quests, sub-quests, and side-quests. Use when the user invokes `/sidequest`, asks where we are, what we were doing, or what's on our stack, or when the conversation branches across multiple topics, blockers, or digressions. Don't use for simple one-off questions that don't involve multi-step work or task hierarchy management. |  |
<!-- SKILLS_LIST_END -->

