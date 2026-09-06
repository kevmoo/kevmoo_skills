---
name: sem-semantic-diff
description: Use the `sem` CLI to view semantic codebase diffs, evaluate dependency graphs, perform impact analysis, discover repository hotspots and co-change pairs, and investigate code history without formatting noise. Use instead of standard git diff/log when analyzing structural code changes.
key_features:
  - Semantic diffs
  - impact analysis
  - dependency graphs
  - cold-start caller/callee lookups
  - hotspot and co-change analysis
  - signature-only context packing
  - entity-addressed substring search
---

# `sem` Semantic Diff Skill (`sem-cli v0.24+`)

This skill provides instructions on how to use `sem`, a semantic version control tool that tracks functions, classes, methods, and types rather than lines of text.

## Capabilities & Limitations (What `sem` Does Well and Does Not Do)

### What `sem` Does Well
- **Local Codebase Navigation:** Builds a precise semantic dependency graph of all classes, functions, methods, and properties defined within the local repository across 39 programming and data formats (including first-class `.dart` support).
- **Structural Diffs & History:** Shows added, modified, renamed, or deleted entities across commits without formatting or whitespace noise (`structuralChange: false` or `--no-cosmetics`).
- **Internal Impact Analysis:** Tracing the transitive impact (`sem impact`) or direct callers/callees (`sem callers`, `sem refs`, `sem graph`) of local entities across the workspace.
- **Hotspot & Co-Change Discovery:** Identifies most-modified entities and co-change pairs ("if you touch X, don't forget Y") via `sem log`.
- **Signature-Only Context Packing:** Fits 5–10x wider call-graph maps into LLM context windows using `--headers`.

### What `sem` Does Not Do (Important Limitations)
- **External Dependencies:** `sem` only indexes entities defined within the local repository's source files. It **does not** parse or track external packages or transitive library dependencies (e.g., from `pubspec.yaml`, `node_modules`, `Cargo.toml`, etc.).
- **External Impact Analysis:** Running `sem impact` on an external type or class (e.g., `DartType` or `ClassElement` from an external package) will fail with `error: Entity '...' not found`.
- **Workflow for External Packages:** If tasked with evaluating how an external package is used across a codebase, **do not start with `sem`**. Use standard `grep` or `ripgrep` (`sem grep` or `rg`) to find `import` statements and locate local wrapper classes or helper functions. Once local wrapper entities are identified, use `sem impact` on those local entities to trace their usage across the codebase.

## Finding Entities (`<entity_name>`)

Many `sem` commands require an `<entity_name>`. Discover exact names or IDs using:

1. **Instant Cold-Start Lookups (`sem find` / `sem callers` / `sem refs`):**
   Backed by an on-disk mmap-able query index (`index.sem`), warm lookups take ~7ms without a daemon:
   ```bash
   # Find where an entity is defined
   sem find "function diff_command" --json

   # Who calls it directly
   sem callers diff_command --json

   # What it calls directly
   sem refs diff_command --json
   ```

2. **Entity-Addressed Substring Search (`sem entities --text`):**
   Search entity bodies for an exact substring and get back the **enclosing AST entity ID** (`file::kind::name`), avoiding manual line-to-function mapping:
   ```bash
   # Search for a string inside entity bodies and return enclosing entity IDs
   sem entities src/ --text "PERMISSION_DENIED" --json

   # Filter by AST entity kind (--only / --except)
   sem entities src/ --only function --only class --json
   ```

3. **Entity IDs for Disambiguation:**
   If a name is ambiguous (e.g., multiple files define a `setup()` function), pass `--file <path>` or use the fully qualified `entity_id` returned by `--json` output (e.g., `--entity-id "src/utils.ts::function::setup"`).

## Core Commands & Flag Reference (`sem v0.24+`)

> **Important Flag Distinction (`--format` vs. `--json`):**
> - Only `sem diff` uses `--format <json|markdown|plain>`.
> - **All other subcommands** (`sem impact`, `sem blame`, `sem log`, `sem entities`, `sem context`, `sem find`, `sem callers`, `sem refs`, `sem grep`, `sem graph`) use `--json` directly. Do **not** pass `--format json` to `sem impact` or `sem log`.

### 1. Semantic Diff (`sem diff`)
Show added, modified, deleted, renamed, or moved entities in the working tree, between commits, between any two files, or piped from unified diffs.

```bash
# View semantic changes in working directory
sem diff

# View only staged changes
sem diff --staged

# Strip formatting, whitespace, and comment-only changes
sem diff --no-cosmetics

# Show changes from a specific commit or range
sem diff --commit <COMMIT>
sem diff --from <COMMIT_1> --to <COMMIT_2>

# Verbose inline word-level diffs for modified entities
sem diff -v

# Output formats: json, markdown, or plain
sem diff --format json
sem diff --format markdown

# Pipe any unified diff via stdin (works in Jujutsu / CitC workspaces without .git)
jj diff --git | sem diff --patch --no-cosmetics --format json

# Compare any two files directly (no git repo required)
sem diff file1.dart file2.dart
```
*Additional options:* `--file-exts <EXTS>...` (Filter by extensions, e.g., `--file-exts .dart`).

### 2. Impact Analysis (`sem impact`)
Analyze the transitive impact of changing an entity (BFS traversal).

```bash
# Full transitive impact analysis in JSON
sem impact <entity_name> --json

# Disambiguate by file or fully qualified ID
sem impact setup --file src/test_utils.ts --json
sem impact --entity-id "src/utils.ts::function::setup" --json

# Direct dependencies or dependents only
sem impact <entity_name> --deps --json
sem impact <entity_name> --dependents --json

# Show only affected tests (uses call graph + lexical/IDF fallback)
sem impact <entity_name> --tests --json

# Include generated, fixture, vendor, benchmark, and build trees
sem impact <entity_name> --no-default-excludes --json
```

### 3. Repository Hotspots & Entity History (`sem log`)
Show the evolution of an entity through git history, or analyze repository-wide churn and co-change pairs.

```bash
# Repository hotspots (most-modified entities + author counts) & co-change pairs
sem log --limit 200 --json

# Scoped hotspots & co-change pairs for a specific directory/file
sem log --file src/auth.ts --json

# Track a specific entity's evolution through git history
sem log <entity_name> --json
sem log <entity_name> -v
```

### 4. Instant Index Lookups (`sem find`, `sem callers`, `sem refs`, `sem grep`)
Fast cold/warm lookups backed by `index.sem`:

```bash
# Locate entity definition
sem find <entity_name> --json

# Direct callers of an entity
sem callers <entity_name> --json

# Direct callees referenced by an entity
sem refs <entity_name> --json

# Trigram text search across indexed source files
sem grep "TODO"
```

### 5. Token-Budgeted Context (`sem context`)
Fit an entity, its dependencies, and its dependents into a strict token budget for LLM consumption:

```bash
# Standard full-body context packing
sem context <entity_name> --budget 8000 --json

# Signature-only packing (signature + first doc-comment line; ~5-10x wider map)
sem context <entity_name> --headers --budget 4000 --json

# Pack multiple entities into a single shared budget, bounded by graph hops
sem context --entity <entity_A> --entity <entity_B> --hops 2 --headers --budget 6000 --json
```

### 6. Dependency Graph (`sem graph`) & Entity Blame (`sem blame`)

```bash
# Full entity dependency graph edge list
sem graph --json

# Entity-level git blame for a file
sem blame <file_path> --json
```

## Troubleshooting & Environment Gotchas

- **GNU Parallel Binary Collision (`/usr/bin/sem`):**
  GNU Parallel installs `/usr/bin/sem` as a symlink to `parallel`. If `sem` hangs or rejects subcommands, verify the binary with `sem --version` or `which sem`. Ensure Homebrew (`$(brew --prefix)/bin/sem`) or Cargo (`~/.cargo/bin/sem`) precedes `/usr/bin` in `PATH`.
- **Asynchronous Execution for Large Graphs:**
  On very large repositories, the initial index/graph build can take several seconds. Run `sem impact` or `sem graph` with a background timeout (`WaitMsBeforeAsync`) if cold-starting on a massive monorepo.
