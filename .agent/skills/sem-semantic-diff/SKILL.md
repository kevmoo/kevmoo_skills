---
name: sem-semantic-diff
description: Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes.
---

# `sem` Semantic Diff Skill

This skill provides instructions on how to use `sem`, a semantic version control tool that tracks functions, classes, and types rather than just lines of text.

## When to use `sem`

Use `sem` instead of standard `git` commands (like `git diff`, `git log`, `git blame`) when:
- You need to understand structural or logic changes without being distracted by formatting, whitespace, or comments (cosmetic changes).
- You want to identify if an entity (function/class) was moved or renamed, rather than deleted and re-added.
- You need to understand the "blast radius" or transitive impact of modifying a specific entity.
- You want a structural dependency graph of what a function calls or what calls it.

## Finding Entities (`<entity_name>`)

Many `sem` commands require an `<entity_name>`. You can discover the exact names or IDs of entities in the codebase using the following methods:

1. **List entities in a file or directory:**
   Use `sem entities <path>` to see all parsed functions, classes, and types in a specific file or directory. Add `--json` for programmatic parsing.
   ```bash
   sem entities src/utils.ts
   
   # For agentic/programmatic parsing:
   sem entities src/utils.ts --json
   ```

2. **From semantic diffs:**
   When you run `sem diff`, the output will list the names of the entities that have been added, modified, or deleted.

3. **Entity IDs:**
   If a name is ambiguous (e.g., multiple files have a `setup()` function), you can use the fully qualified `entity_id` provided in the JSON output of `sem diff` or `sem entities` (e.g., `--entity-id "src/utils.ts::function::setup"`).

## Core Commands

### 1. Semantic Diff
Show added, modified, deleted, or renamed entities in the working tree or between commits.

```bash
# View semantic changes in the working directory
sem diff

# View only staged changes
sem diff --staged

# View diff between two commits
sem diff --from HEAD~1 --to HEAD

# Get verbose inline content diffs for modified entities
sem diff -v
```

### 2. Impact Analysis
Analyze the transitive impact of changing an entity (BFS traversal).

```bash
# See what else is affected if you change an entity
sem impact <entity_name>

# Show only affected tests
sem impact <entity_name> --tests

# Show direct dependencies only
sem impact <entity_name> --deps
```

### 3. Dependency Graph
View the full entity dependency graph for the codebase.

```bash
sem graph
```

### 4. Semantic Blame
Identify who last modified a specific function or class (not just a line).

```bash
sem blame <entity_name>
```

### 5. Semantic Log
Show the evolution of an entity through git history.

```bash
sem log <entity_name>
```

### 6. Entity Context
Show token-budgeted context for an entity, useful for feeding specific relevant code to context.

```bash
sem context <entity_name> --budget 8000
```

## Best Practices
- **JSON Output for Processing**: Use `--format json` (or `--json`) when you need to parse the output programmatically.
- **File Extensions**: Use `--file-exts .ts .js` to filter large codebases.
- **Handling Ambiguity**: If multiple entities have the same name, use `--file <FILE>` or `--entity-id <ENTITY_ID>` to disambiguate.
