<p align="center">
  <img src="https://raw.githubusercontent.com/dart-lang/site-shared/master/src/_assets/image/flutter/icon/64.png" alt="Banner" width="100">
  <br>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Language-Dart-0175C2.svg" alt="Dart"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Framework-Flutter-02569B.svg" alt="Flutter"></a>
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/Compliance-Standard%20Agent%20Skills-brightgreen.svg" alt="Standard Agent Skills"></a>
</p>

# kevmoo_skills

This is my personal repository for specialized **Agent Skills**. These skills provide
procedural, actionable instructions to AI assistants for specific domains or tasks.

## Skills Inventory

| Skill | Description | Key Features |
|-------|-------------|--------------|
| **[kevmoo-skills](.agent/skills/kevmoo-skills/SKILL.md)** | Personal preferences and common workflows. | Workflow automation, personal preferences |

## The Agent Usage Lifecycle

AI assistants interact with this repository using the following lifecycle:

1.  **Ingest**: The agent reads the `.agent/skills` directory to discover available capabilities.
2.  **Activate**: The agent checks the `When to use this skill` section of a `SKILL.md` file to determine if it applies to the current context or user request.
3.  **Execute**: The agent carefully follows the structured workflows, specific constraints, and code patterns defined within the activated skill file.
