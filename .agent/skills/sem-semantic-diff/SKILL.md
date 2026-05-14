---
name: sem-semantic-diff
description: Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes.
---

# `sem` Semantic Diff Skill

This skill provides instructions on how to use `sem`, a semantic version control tool that tracks functions, classes, and types rather than just lines of text.

## Capabilities & Limitations (What `sem` Does Well and Does Not Do)

### What `sem` Does Well
- **Local Codebase Navigation:** Builds a precise semantic dependency graph of all classes, functions, methods, and properties defined within the local repository.
- **Structural Diffs & History:** Shows added, modified, renamed, or deleted entities across commits without formatting or whitespace noise.
- **Internal Impact Analysis:** Tracing the transitive impact (`sem impact`) or callers/callees (`sem graph`) of local entities across the workspace.

### What `sem` Does Not Do (Important Limitations)
- **External Dependencies:** `sem` only indexes entities defined within the local repository's source files. It **does not** parse or track external packages or transitive library dependencies (e.g., from `pubspec.yaml`, `node_modules`, `Cargo.toml`, etc.).
- **External Impact Analysis:** Running `sem impact` on an external type or class (e.g., `DartType` or `ClassElement` from an external package) will fail with `error: Entity '...' not found`.
- **Workflow for External Packages:** If tasked with evaluating how an external package is used across a codebase, **do not start with `sem`**. Use standard `grep` or `ripgrep` to find `import` statements and locate local wrapper classes or helper functions. Once local wrapper entities are identified, use `sem impact` on those local entities to trace their usage across the codebase.

## Finding Entities (`<entity_name>`)

Many `sem` commands require an `<entity_name>`. You can discover the exact names or IDs of entities in the codebase using the following methods:

1. **List entities in a file or directory:**
   Use `sem entities [PATH]` to see all parsed functions, classes, and types in a specific file or directory.
   ```bash
   sem entities src/utils.ts
   
   # For agentic/programmatic parsing:
   sem entities src/utils.ts --format json
   ```

2. **From semantic diffs:**
   When you run `sem diff`, the output will list the names of the entities that have been added, modified, or deleted.

3. **Entity IDs:**
   If a name is ambiguous (e.g., multiple files have a `setup()` function), you can use the fully qualified `entity_id` provided in the JSON output of `sem diff` or `sem entities` (e.g., `--entity-id "src/utils.ts::function::setup"`).

## Core Commands & Full Options Reference (No Need to Run `--help`)

To avoid running `--help`, use this comprehensive reference of available commands and their flags. Always use `--format json` when parsing programmatically to guarantee consistency across all subcommands.

### 1. Semantic Diff (`sem diff`)
Show added, modified, deleted, or renamed entities in the working tree or between commits.

```bash
# View semantic changes in the working directory
sem diff

# View only staged changes
sem diff --staged

# Show changes from a specific commit
sem diff --commit <COMMIT>

# View diff between two commits
sem diff --from <COMMIT_1> --to <COMMIT_2>

# Get verbose inline content diffs for modified entities
sem diff -v

# Output in JSON format
sem diff --format json
```
*Additional options:* `-C, --cwd <DIR>` (Run as if started in directory), `--file-exts <EXTS>...` (Filter by extensions).

### 2. Impact Analysis (`sem impact`)
Analyze the transitive impact of changing an entity (BFS traversal).

```bash
# See what else is affected if you change an entity
sem impact <entity_name>

# Look up entity by fully qualified ID
sem impact --entity-id "src/utils.ts::function::setup"

# Disambiguate by specifying the file containing the entity
sem impact setup --file src/test_utils.ts

# Output as JSON
sem impact <entity_name> --format json

# Show direct dependencies only
sem impact <entity_name> --deps

# Show direct dependents only
sem impact <entity_name> --dependents

# Show only affected tests
sem impact <entity_name> --tests
```
*Additional options:* `--depth <DEPTH>` (Max traversal depth, default 2, 0 = unlimited), `--file-exts <EXTS>...`, `--no-cache`.

### 3. Dependency Graph (`sem graph`)
View the full entity dependency graph for the codebase.

```bash
# View graph for current directory
sem graph

# View graph for specific path in JSON format
sem graph src/ --format json
```
*Additional options:* `--format <FORMAT>` (terminal, json), `--file-exts <EXTS>...`, `--no-cache`.

### 4. Semantic Blame (`sem blame`)
Identify who last modified each function or class within a file.

```bash
sem blame <file_path>
```

### 5. Semantic Log (`sem log`)
Show the evolution of an entity through git history.

```bash
sem log <entity_name>
```

### 6. Entity Context (`sem context`)
Show token-budgeted context for an entity. This is intended for providing code snippets directly to an LLM's context window.

```bash
# Show context with token budget (default 8000)
sem context <entity_name> --budget 8000

# Output in JSON
sem context <entity_name> --format json
```
*Additional options:* `--entity-id <ID>`, `--file <FILE>`, `--file-exts <EXTS>...`, `--no-cache`.

### 7. List Entities (`sem entities`)
List entities under a file or directory path.

```bash
# List entities in current directory or specific path
sem entities src/

# Output in JSON format
sem entities src/ --format json
```

## Best Practices
- **JSON Output for Processing**: Always use `--format json` when you need to parse the output programmatically. This ensures 100% consistency across all `sem` commands (as `sem diff` requires `--format json` and does not support a `--json` shorthand).
- **File Extensions**: Use `--file-exts .ts .js` to filter large codebases.
- **Handling Ambiguity**: If multiple entities have the same name (e.g., a `setup` function in multiple test files), use `--file <FILE>` or `--entity-id <ENTITY_ID>` to disambiguate:
  ```bash
  sem impact setup --file src/test_utils.ts
  # OR
  sem impact --entity-id "src/test_utils.ts::function::setup"
  ```
