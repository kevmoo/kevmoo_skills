# `sem` Core Commands & Flag Reference (`sem v0.24+`)

Complete flag and example reference for
[`skills/sem-cli/SKILL.md`](../SKILL.md).

> **Important Flag Distinction (`--format` vs. `--json`):**
>
> - Only `sem diff` uses `--format <json|markdown|plain>`.
> - **All other subcommands** (`sem impact`, `sem blame`, `sem log`,
>   `sem entities`, `sem context`, `sem find`, `sem callers`, `sem refs`,
>   `sem grep`, `sem graph`) use `--json` directly. Do **not** pass
>   `--format json` to `sem impact` or `sem log`.

## 1. Semantic Diff (`sem diff`)

Show added, modified, deleted, renamed, or moved entities in the working tree,
between commits, between any two files, or piped from unified diffs.

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

# Pipe any unified diff via stdin (works in Jujutsu workspaces without .git)
jj diff --git | sem diff --patch --no-cosmetics --format json

# Compare any two files directly (no git repo required)
sem diff file1.dart file2.dart
```

_Additional options:_ `--file-exts <EXTS>...` (Filter by extensions, e.g.,
`--file-exts .dart`).

## 2. Impact Analysis (`sem impact`)

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

## 3. Repository Hotspots & Entity History (`sem log`)

Show the evolution of an entity through git history, or analyze repository-wide
churn and co-change pairs.

```bash
# Repository hotspots (most-modified entities + author counts) & co-change pairs
sem log --limit 200 --json

# Scoped hotspots & co-change pairs for a specific directory/file
sem log --file src/auth.ts --json

# Track a specific entity's evolution through git history
sem log <entity_name> --json
sem log <entity_name> -v
```

## 4. Instant Index Lookups (`sem find`, `sem callers`, `sem refs`, `sem grep`)

Fast cold/warm lookups backed by `index.sem` (`v0.30+` consolidates these under
`sem find`, while legacy verb names remain aliases):

```bash
# File outline before multi-chunk reads of >300-line files (~25ms)
sem find --in <file_path>

# Locate entity definition (scope huge monorepos with --in <subdir>)
sem find <entity_name> --json

# Direct callers of an entity (check INCOMPLETE / possible callers too)
sem find <entity_name> --callers --json
sem callers <entity_name> --json

# Direct callees referenced by an entity
sem find <entity_name> --refs --json
sem refs <entity_name> --json

# Trigram text search (optionally scoped to a path)
sem grep "TODO"
sem grep "TODO" src/
```

## 5. Token-Budgeted Context (`sem context`)

Fit an entity, its dependencies, and its dependents into a strict token budget
for LLM consumption:

```bash
# Standard full-body context packing
sem context <entity_name> --budget 8000 --json

# Signature-only packing (signature + first doc-comment line; ~5-10x wider map)
sem context <entity_name> --headers --budget 4000 --json

# Pack multiple entities into a single shared budget, bounded by graph hops
sem context --entity <entity_A> --entity <entity_B> --hops 2 --headers --budget 6000 --json
```

## 6. Dependency Graph (`sem graph`) & Entity Blame (`sem blame`)

```bash
# Full entity dependency graph edge list
sem graph --json

# Entity-level git blame for a file
sem blame <file_path> --json
```
