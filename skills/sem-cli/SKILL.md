---
name: sem-cli
description: Use the `sem` CLI (`sem-cli`) commands for fast local code exploration, instant call-graph navigation (`callers`/`refs`), signature-only context packing (`--headers`), hotspot and co-change discovery (`sem log`), transitive impact analysis (`sem impact`), and entity-level semantic diffs (`sem diff`).
key_features:
  - Instant call-graph navigation
  - signature-only context packing
  - entity-addressed substring search
  - hotspot and co-change analysis
  - transitive impact analysis
  - semantic diffs
---

# `sem-cli` Skill (`sem v0.30+`)

This skill provides instructions on how to use `sem` (`sem-cli`), an AST entity
indexer, call-graph navigator, and semantic version control tool that tracks
functions, classes, methods, and types across 39 languages and data formats.

> **Anti-Scroll Habit & `v0.30+` Verbs:** Before multi-chunk reads of
> `>300`-line files, run `sem find --in <file>` (alias `sem entities <file>`) to
> get class, method, and constructor line bounds in ~25ms. In `v0.30+`,
> `sem find` unifies `--in` (`entities`), `--callers` (`callers`), `--refs`
> (`refs`), and `--context` (`context`), while all legacy verb names remain
> supported aliases.

## Capabilities & Limitations (What `sem` Does Well and Does Not Do)

### What `sem` Does Well

- **Instant Cold-Start Code Exploration:** Builds an on-disk mmap query index
  (`index.sem`) that answers file outlines (`sem find --in <file>`), definition
  lookups (`sem find`), direct callers (`sem find --callers` / `sem callers`),
  direct callees (`sem find --refs` / `sem refs`), and trigram regex searches
  (`sem grep <pattern> <path>`) in **~20ms** on small–medium repos without
  running an LSP daemon.
- **Signature-Only Context Packing:** Fits **5–10x wider call-graph maps** into
  LLM context windows using `sem find --context --headers`
  (`sem context --headers`).
- **Entity-Addressed Substring Search:** Searches entity bodies
  (`sem find --in src/ --text "..."` / `sem entities --text`) and returns the
  **enclosing AST entity ID** (`file::kind::name`) rather than raw `grep` line
  numbers.
- **Hotspot & Co-Change Discovery:** Identifies most-modified entities and
  co-change pairs ("if you touch X, don't forget Y") via `sem log`.
- **Structural Diffs & History:** Shows added, modified, renamed, or deleted
  entities across commits without formatting or whitespace noise
  (`structuralChange: false` or `--no-cosmetics`).

### What `sem` Does Not Do (Important Limitations)

- **Massive Monorepos Without Scoping:** Never run un-scoped repo-wide
  `sem find <name>` or `sem grep <pattern>` on huge monorepos (for example,
  `dart-sdk` or large multi-package trees); cold index builds exceed `20s`
  timeouts. Always scope to `--in <file_or_subdir>`, pass a subdirectory to
  `sem grep`, or use `rg` / indexed code search.
- **Incomplete Static Callers:** `sem find --callers` and `sem impact` may
  report an `INCOMPLETE` / `possibleCallers` block for unresolved bare-name or
  dynamic calls—inspect those sites instead of treating resolved callers as
  exhaustive. Older builds (`< v0.30.1`) had silent false negatives on Dart
  callers/refs and rejected paths on `sem grep`; keep `sem >= v0.30.1`.
- **External Dependencies:** `sem` only indexes entities defined within the
  local repository's source files. It **does not** parse or track external
  packages or transitive library dependencies (e.g., from `pubspec.yaml`,
  `node_modules`, `Cargo.toml`, etc.).
- **External Impact Analysis:** Running `sem impact` on an external type or
  class (e.g., `DartType` or `ClassElement` from an external package) will fail
  with `error: Entity '...' not found`.
- **Workflow for External Packages:** If tasked with evaluating how an external
  package is used across a codebase, **do not start with `sem`**. Use standard
  `grep` or `ripgrep` (`sem grep` or `rg`) to find `import` statements and
  locate local wrapper classes or helper functions. Once local wrapper entities
  are identified, use `sem impact` on those local entities to trace their usage
  across the codebase.

## Finding Entities (`<entity_name>`)

Many `sem` commands require an `<entity_name>`. Discover exact names or IDs
using:

1. **Instant Cold-Start Lookups (`sem find` / `sem callers` / `sem refs`):**
   Backed by an on-disk mmap-able query index (`index.sem`), warm lookups take
   ~7ms without a daemon:

   ```bash
   # Find where an entity is defined
   sem find "function diff_command" --json

   # Who calls it directly
   sem callers diff_command --json

   # What it calls directly
   sem refs diff_command --json
   ```

2. **Entity-Addressed Substring Search (`sem entities --text`):** Search entity
   bodies for an exact substring and get back the **enclosing AST entity ID**
   (`file::kind::name`), avoiding manual line-to-function mapping:

   ```bash
   # Search for a string inside entity bodies and return enclosing entity IDs
   sem entities src/ --text "PERMISSION_DENIED" --json

   # Filter by AST entity kind (--only / --except)
   sem entities src/ --only function --only class --json
   ```

3. **Entity IDs for Disambiguation:** If a name is ambiguous (e.g., multiple
   files define a `setup()` function), pass `--file <path>` or use the fully
   qualified `entity_id` returned by `--json` output (e.g.,
   `--entity-id "src/utils.ts::function::setup"`).

## Core Commands Overview (`sem v0.24+`)

> **Important Flag Distinction (`--format` vs. `--json`):**
>
> - Only `sem diff` uses `--format <json|markdown|plain>`.
> - **All other subcommands** (`sem impact`, `sem blame`, `sem log`,
>   `sem entities`, `sem context`, `sem find`, `sem callers`, `sem refs`,
>   `sem grep`, `sem graph`) use `--json` directly. Do **not** pass
>   `--format json` to `sem impact` or `sem log`.

See [`references/commands.md`](references/commands.md) for full flag recipes and
stdin/non-Git invocations across all subcommands:

| Subcommand                                 | Primary Invocation                                                                           | Purpose                                                                            |
| :----------------------------------------- | :------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------- |
| `sem find` (`entities`, `callers`, `refs`) | `sem find --in <file>` · `sem find <name> [--callers\|--refs] --json`                        | File outlines (`~25ms`), definitions, direct callers, and direct callees           |
| `sem grep`                                 | `sem grep "<pattern>" [<subdir>]`                                                            | Indexed trigram text/regex search scoped to a directory                            |
| `sem diff`                                 | `sem diff [--staged] [--no-cosmetics] [--format json]` · `jj diff --git \| sem diff --patch` | Entity-level semantic diffs across working trees, commits, files, or piped patches |
| `sem impact`                               | `sem impact <name> [--deps\|--dependents\|--tests] [--file <p>] --json`                      | Transitive BFS call-graph impact and affected test discovery                       |
| `sem context`                              | `sem context <name> [--headers] --budget <tokens> --json`                                    | Token-budgeted context packing (`--headers` packs `5-10x` wider graphs)            |
| `sem log`                                  | `sem log [--limit 200 \| --file <p> \| <name>] --json`                                       | Repository hotspots, co-change pairs, and per-entity evolution                     |
| `sem graph` / `sem blame`                  | `sem graph --json` · `sem blame <file> --json`                                               | Full dependency edge list and entity-level Git blame                               |

## Troubleshooting & Environment Gotchas

- **GNU Parallel Binary Collision (`/usr/bin/sem`):** GNU Parallel installs
  `/usr/bin/sem` as a symlink to `parallel`. If `sem` hangs or rejects
  subcommands, verify the binary with `sem --version` or `which sem`. Ensure
  Homebrew (`$(brew --prefix)/bin/sem`) or Cargo (`~/.cargo/bin/sem`) precedes
  `/usr/bin` in `PATH`.
- **`--only <kind>` Strictness & Empty Diffs:** Omit `--only` unless filtering
  intentionally (`--only function` errors on files with zero top-level
  functions). In non-Git workspaces (such as Jujutsu), bare `sem diff` fails
  (`not a git repository`) and `jj diff --git | sem diff --patch` errors when
  the working copy diff is empty.
- **Cross-Filesystem `sem update` (`os error 18`):** If `sem update` fails with
  `Invalid cross-device link`, set `TMPDIR` on the same filesystem as
  `~/.local/bin` (for example,
  `mkdir -p ~/.local/tmp && TMPDIR="$HOME/.local/tmp" sem update`).
- **Asynchronous Execution for Large Graphs:** On very large repositories, the
  initial index/graph build can exceed `20s`. Scope with `--in <subdir>` or
  `sem grep <pattern> <subdir>`, or run `sem impact`/`sem graph` in the
  background (`WaitMsBeforeAsync` / `run_in_background`).
