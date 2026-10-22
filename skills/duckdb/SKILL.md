---
name: duckdb
description: >-
  Queries, inspects, transforms, and converts local structured and
  semi-structured data files (JSON, JSONL, NDJSON, CSV, TSV, Parquet, SQLite),
  unified code diffs, and Markdown documents on Linux and macOS with DuckDB SQL.
  Use when querying local JSON, CSV, or SQLite files, benchmark artifacts, large
  code diffs, or Markdown corpora, inspecting schemas and row counts, searching
  and joining JSONL log globs with SQLite index databases (such as
  transcript.jsonl and conversation_summaries.db), joining files across formats,
  converting datasets to Parquet, or filtering stdin pipelines. Prefer it over
  ad hoc Python or jq for filtering, grouping, and joining local data. Don't use
  for remote cloud data warehouses (BigQuery, Snowflake, Spanner) or PLx
  dashboards.
key_features:
  - Non-interactive subshell flag safety (-batch -dark-mode) & v2.0+ Agent Mode (-agent)
  - Fast JSONL, CSV, Parquet, and SQLite querying
  - Explicit schema projection & multi-file globbing
  - Cross-format SQL joins & Parquet materialization
  - Relational code diff querying (scripts/diff_macros.sql)
  - Relational Markdown indexing (scripts/markdown_macros.sql)
  - Offline SQL function manual (-manual) & SQL formatter (-format)
---

# DuckDB CLI Analytics

Fast analytical SQL engine for querying, analyzing, and converting local data
files (JSON, JSONL, CSV, TSV, Parquet, SQLite), unified code diffs, and Markdown
documents directly from the shell without database servers or external imports.

## Quick Start & Execution Setup

DuckDB runs as a standalone CLI binary. Always pass **`-dark-mode`** on every
invocation (including `duckdb -dark-mode --version` and `--help`), and pass
**`-batch -dark-mode`** on all queries and `-manual` lookups.

### Installation & Subshell PATH Setup (Linux & macOS)

To prevent `exit code 127: duckdb: command not found` in non-interactive agent
subshells (where `mise` or `asdf` shims are not sourced):

- **`mise` shims on `PATH` (Recommended)**: Pin `"github:duckdb/duckdb" = "2"`
  in `~/.config/mise/config.toml` to track stable `2.x` releases with SLSA
  provenance verification, and put `~/.local/share/mise/shims` on `PATH` in the
  files non-interactive shells actually read (`~/.zshenv` / `BASH_ENV`, and
  `~/.config/environment.d/*.conf` for `systemd` user units) rather than
  symlinking each tool. The shims are symlinks to the `mise` binary itself, so
  they resolve even when `mise` is not on `PATH`, and one entry covers every
  managed tool. Keep `~/.local/bin` _before_ the shims dir so custom wrappers
  still win.

- **Direct Binary / Symlink (fallback)**: Where shims are unavailable, make the
  binary directly accessible at `~/.local/bin/duckdb` (or
  `/opt/homebrew/bin/duckdb` on Apple Silicon macOS). Note that a per-tool
  symlink collides with any dotfiles repo that tracks the same path:

  ```bash
  # Option A: If installed via mise ("github:duckdb/duckdb" = "2"), symlink into ~/.local/bin/
  ln -sf ~/.local/share/mise/installs/github-duckdb-duckdb/2/duckdb ~/.local/bin/duckdb

  # Option B: macOS Homebrew
  brew install duckdb

  # Option C: Direct download from GitHub Releases (v2.0+ uses .tar.gz archives;
  # replace linux-amd64 with linux-arm64 or osx-arm64 as needed)
  curl -fsSL https://github.com/duckdb/duckdb/releases/latest/download/duckdb-cli-linux-amd64.tar.gz \
    | tar -xzf - -C ~/.local/bin/ duckdb
  ```

### Critical Flags & DuckDB `v2.0+` Agent Mode

- `-batch -dark-mode` _(MANDATORY together in subshells)_:
  - `-dark-mode`: DuckDB probes terminal background color via OSC sequences
    whenever `stdout` is a TTY — **even before handling `--version`, `--help`,
    `-manual`, or `-format`**. In PTY-allocated agent subshells this times out
    after **5 seconds**
    (`Timeout trying to read terminal background color (> 5s elapsed)`), and
    **neither `-batch`, `-agent`, nor `DUCKDB_AGENT_MODE=1` disables it** — pass
    `-dark-mode` (or `-light-mode`) on every invocation.
  - `-batch`: Disables interactive prompts, progress bars, and `less` paging
    (also mandatory with `v2.0+` `-manual <fn>`, which otherwise retains
    interactive detection and triggers both the 5-second color probe and pager).
  - `-no-stdin`: Exits after processing CLI options instead of reading `stdin`
    when spawned from child-process runners whose `stdin` pipe stays open (omit
    when streaming data from `/dev/stdin`).
- **Agent Mode (`v2.0+`: `-agent`, `-no-agent`, `AI_AGENT=1`,
  `DUCKDB_AGENT_MODE=1`)**:
  - Renders compact unpadded Markdown tables with inline column types
    (`| col:TYPE |`), loud head+tail caps (`1,000` rows, `10,000` bytes,
    `500`-char cells; `.maxrows` / `.maxbytes` — **enforced even under `-batch`
    and `> file` redirection**, so use `-csv` or `-json` for untruncated
    exports) with a row-count + order-independent hash footer, JSON errors +
    `>1M`-row progress on `stderr`, and 1-line-per-operator `EXPLAIN` plans.
  - **Omit `-box` on exploratory queries**: `duckdb -batch -dark-mode` defaults
    to `box` on `v1.x`, whereas on `v2.0+` built-in Agent Mode auto-detection
    (`CLAUDECODE`, `GEMINI_CLI`, `CURSOR_AGENT`, `CODEX_*`, `COPILOT_*`,
    `AI_AGENT`, `AGENT`) activates only when `stdout` is NOT a TTY and no
    output-mode flag is passed. Passing `-box` disables auto-detection and
    overrides `-agent` (`3x-5x` whitespace padding tax and silent `>40`-row
    truncation). Pass `-agent` explicitly in PTY subshells (`stdout` is a TTY);
    in `PATH` wrappers, pair `export AI_AGENT=1; unset DUCKDB_AGENT_MODE`
    because `DUCKDB_AGENT_MODE=1` keeps `agent_mode_active = true` on `stderr`
    even with `-json`, `-csv`, or `-markdown` (and inspect `"$@"` before
    prepending `-dark-mode` / `-batch` so `-light-mode` / `-interactive` win).
- **Explicit output & utility flags**:
  - `-json` / `-jsonlines`: Structured JSON array or NDJSON rows (`0` `stderr`).
  - `-csv`: Uncapped comma-separated rows with headers (required over `-agent`
    for full-table exports or large `read_md_sections` scans).
  - `-markdown`: Column-padded GFM pipe tables without `:TYPE` or hash footers.
  - `-box` / `-no-agent`: Human-oriented padded Unicode boxed tables.
  - `-manual <function>` (`v2.0+`): Prints offline signature, description, and
    examples (`duckdb -batch -dark-mode -manual regexp_extract`).
  - `-format` / `-format-file <path.sql>` (`v2.0+`): Formats SQL to `stdout`
    (emits ANSI color codes on a TTY; pass `-dark-mode` and pipe `| cat` or
    redirect `> out.sql` for plain SQL text).
  - `-bail`: Stop execution immediately on first error.

```bash
# Exploratory agent query (v2.0+ compact typed Markdown + hash; omit -box)
duckdb -batch -dark-mode -agent -c "SELECT 42 AS answer;"

# Version-neutral exploratory query (box on v1.x; Agent Mode when piped or wrapped on v2.0+)
duckdb -batch -dark-mode -c "SELECT 42 AS answer;"

# Programmatic JSON output (add -no-stdin when spawned from a child-process runner)
duckdb -batch -no-stdin -dark-mode -json -c "SELECT 42 AS answer;"

# Offline SQL function manual lookup & plain-text SQL formatting (v2.0+)
duckdb -batch -dark-mode -manual regexp_extract
printf "select a, b from tbl where a = 1;\n" | duckdb -dark-mode -format | cat
```

---

## Core Gotchas & Invariants

1.  **5-Second Hang on Subshells (`-batch -dark-mode` Required)**: Passing
    `-batch`, `-agent`, `DUCKDB_AGENT_MODE=1`, `--version`, `--help`, `-manual`,
    or `-format` without `-dark-mode` does **not** disable DuckDB's 5-second OSC
    terminal background color probe on a TTY (and `-manual` without `-batch`
    retains interactive paging). Always pass `-batch -dark-mode`.
2.  **1-Based Array Indexing**: DuckDB follows ANSI SQL standards: `arr[1]` is
    the first element. `arr[0]` produces an out-of-bounds error.
3.  **Heterogeneous JSON Schemas**: When reading JSONL with varying keys across
    rows, DuckDB defaults to a common schema and may drop disparate keys. Pass
    `union_by_name = true` inside `read_json` or `read_json_auto`.
4.  **Interrupted / Malformed JSON Lines**: In log files or interrupted
    processes, malformed lines will abort the query. Pass
    `ignore_errors = true`.
5.  **Transparent Compression**: Files ending in `.gz` or `.zst` are read
    automatically without manual decompression.
6.  **Explicit `columns={...}` Projection & `STRUCT` vs. `JSON` Scalar Gotcha**:
    When scanning thousands of JSONL files (e.g. `transcript.jsonl`), passing an
    explicit `columns={...}` map skips multi-file schema inference and speeds up
    scans by **3x** (~1.1s -> ~0.39s). However, if you type a nested
    object/array column as `'JSON'` or `'JSON[]'`, DuckDB returns raw
    JSON-encoded scalars (with quotes inside the string, e.g.,
    `"\"run_command\""`), and comparing `tc.name = 'run_command'` fails with
    `Malformed JSON at byte 0 of input: unexpected character. Input: "run_command"`.
    - **Fix**: Always type nested objects explicitly as `STRUCT(...)[]` (e.g.
      `columns={'tool_calls': 'STRUCT(name VARCHAR, args JSON)[]'}`) OR extract
      strings using the `->>` operator (`tc->>'name' = 'run_command'`).
7.  **`.db` File Extension Disambiguation (DuckDB vs. SQLite)**: Both native
    DuckDB databases and SQLite databases frequently use `.db` extensions.
    Attempting `ATTACH 'path/to/file.db' AS db (TYPE SQLITE)` on a native DuckDB
    database fails with `file is not a database`. Run `file path/to/file.db`
    first when the format is unknown.
8.  **Persistent `.duckdb` Storage Format Across `v1.x` and `v2.0+`**: DuckDB
    `v2.0+` writes storage version `69` (`v2.0.0+`) on new `.duckdb` files,
    which `v1.5.x` and earlier cannot open (while `v2.0+` reads existing `v1.x`
    files transparently). Pass `-storage-version v1.5.0` for `v1.5.x` readers
    (or `v1.2.0` for `v1.2+`; verify via
    `SELECT tags['storage_version'] FROM duckdb_databases()`).

---

## Quick Format & Streaming Patterns

### 1. JSON / JSONL & Nested Unnesting

```bash
# Preview JSONL with irregular schema / interrupted lines tolerance
duckdb -batch -dark-mode -c "SELECT * FROM read_json('logs/*.jsonl', union_by_name=true, ignore_errors=true) LIMIT 10;"

# Dot access, 1-based array indexing, and unnest()
duckdb -batch -dark-mode -c "SELECT id, user.email, tags[1] AS primary_tag, unnest(tags) AS tag FROM 'users.jsonl';"
```

### 2. CSV, TSV & Parquet

```bash
# Auto-detect CSV/TSV or read compressed .csv.gz directly
duckdb -batch -dark-mode -c "SELECT * FROM 'export.csv.gz' LIMIT 10;"

# Read Parquet globs and inspect schema without scanning rows
duckdb -batch -dark-mode -c "SELECT * FROM 'metrics/*.parquet' WHERE value > 100 LIMIT 10; SELECT * FROM parquet_schema('metrics/part-00.parquet');"
```

### 3. Standard Input Streaming (`/dev/stdin`)

```bash
curl -s "https://api.example.com/items" | \
  duckdb -batch -dark-mode -c "SELECT * FROM read_json('/dev/stdin') LIMIT 10;"
```

### 4. Local Databases (`.db`, `.duckdb`, `.sqlite`)

Always check `file path/to/database.db` first:

```bash
# Native DuckDB database file
duckdb -batch -dark-mode path/to/database.db -c "SHOW TABLES;"

# SQLite 3.x database file
duckdb -batch -dark-mode -c "
ATTACH 'path/to/database.db' AS db (TYPE SQLITE, READ_ONLY);
SELECT * FROM db.my_table LIMIT 10;
"
```

---

## SQL Cookbook & Advanced Recipes

Read [`references/recipes.md`](references/recipes.md),
[`scripts/diff_macros.sql`](scripts/diff_macros.sql), and
[`scripts/markdown_macros.sql`](scripts/markdown_macros.sql) for detailed SQL
cookbook patterns:

- **Agent Conversation Transcript Mining & SQLite Index Joins**: Fast-path
  `columns={...}` projection across
  `~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl` and
  `~/.claude/projects/**/*.jsonl`, searching and joining JSONL log globs with
  SQLite index databases (`ATTACH ... (TYPE SQLITE, READ_ONLY)`, such as joining
  `transcript.jsonl` with `conversation_summaries.db`), tool usage/error audits,
  and stripping `EPHEMERAL_MESSAGE` `<memory>` echoes.
- **Format Conversions & Parquet Materialization**: Converting JSONL/CSV logs to
  ZSTD Parquet (`COPY ... TO`), Hive-partitioned reads/writes, and cross-format
  SQL joins (JSON + CSV + Parquet + SQLite).
- **Benchmark JSON & Log Extraction**: Piping `<<<BENCH_PRESS_JSON_START>>>` log
  blocks into DuckDB, pivoting multi-target (`aot` / `jit` / `wasm`) benchmark
  JSON artifacts, and tuning memory/thread limits for `>10GB` datasets.
- **Relational Code Diff Querying**: Querying unified code diffs
  (`read_diff_lines`, `read_diff_hunks`) with
  [`scripts/diff_macros.sql`](scripts/diff_macros.sql).
- **Relational Markdown Indexing**: Indexing Markdown section hierarchies and
  fenced code blocks (`read_md_sections`, `read_md_code_blocks`) across large
  documents (`>= 350` lines) and multi-file corpora (`10+` files) with
  [`scripts/markdown_macros.sql`](scripts/markdown_macros.sql).
