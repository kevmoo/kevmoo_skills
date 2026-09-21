---
name: duckdb
description: >-
  Queries, inspects, transforms, and converts local structured and
  semi-structured data files (JSON, JSONL, NDJSON, CSV, TSV, Parquet, SQLite) on
  Linux and macOS using DuckDB SQL. Use when querying local JSON/CSV dumps,
  benchmark JSON artifacts (e.g. bench_press), inspecting schemas and row
  counts, mining agent conversation transcripts (transcript.jsonl), joining
  local files across formats, converting large JSON/CSV datasets to Parquet,
  querying local SQLite (.db) files, or streaming shell pipelines via stdin.
  Prefer over ad-hoc Python scripts (json/csv) or jq for filtering, grouping,
  aggregating, and joining local datasets. Don't use for remote cloud data
  warehouses (e.g. BigQuery, Snowflake, Spanner).
key_features:
  - Non-interactive subshell flag safety (-batch -dark-mode)
  - Fast JSONL, CSV, Parquet, and SQLite querying
  - Explicit schema projection & multi-file globbing
  - Cross-format SQL joins & Parquet materialization
---

# DuckDB CLI Analytics

Fast analytical SQL engine for querying, analyzing, and converting local data
files (JSON, JSONL, CSV, TSV, Parquet, SQLite) directly from the shell without
database servers or external imports.

## Quick Start & Execution Setup

DuckDB runs as a standalone CLI binary. Always invoke `~/.local/bin/duckdb` (or
`duckdb` when `~/.local/bin` is in `$PATH`) with **`-batch -dark-mode`**.

### Installation & Subshell PATH Setup (Linux & macOS)

To prevent `exit code 127: duckdb: command not found` in non-interactive agent
subshells (where `mise` or `asdf` shims are not sourced):

- **`mise` shims on `PATH` (Recommended)**: If `mise` manages `duckdb`, put
  `~/.local/share/mise/shims` on `PATH` in the files non-interactive shells
  actually read (`~/.zshenv` / `BASH_ENV`, and
  `~/.config/environment.d/*.conf` for `systemd` user units) rather than
  symlinking each tool. The shims are symlinks to the `mise` binary itself, so
  they resolve even when `mise` is not on `PATH`, and one entry covers every
  managed tool. Keep `~/.local/bin` *before* the shims dir so custom wrappers
  still win.

- **Direct Binary / Symlink (fallback)**: Where shims are unavailable, make the
  binary directly accessible at `~/.local/bin/duckdb` (or
  `/opt/homebrew/bin/duckdb` on Apple Silicon macOS). Note that a per-tool
  symlink collides with any dotfiles repo that tracks the same path:

  ```bash
  # Option A: If installed via mise, symlink into ~/.local/bin/
  ln -sf ~/.local/share/mise/installs/duckdb/latest/duckdb ~/.local/bin/duckdb

  # Option B: macOS Homebrew
  brew install duckdb

  # Option C: Direct download from GitHub Releases (Linux amd64)
  curl -LO https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
  unzip -o duckdb_cli-linux-amd64.zip -d ~/.local/bin/
  ```

### Critical Flags

- `-batch -dark-mode` _(MANDATORY together in subshells)_:
  - `-dark-mode`: DuckDB attempts to detect terminal background color via OSC
    query sequences on startup. In non-interactive agent subshells, this probe
    times out after **5 seconds**
    (`Timeout trying to read terminal background color (> 5s elapsed)`).
    **`-batch` alone does NOT disable this probe** — `-dark-mode` (or
    `-light-mode`) is strictly required.
  - `-batch`: Disables interactive progress bars and prompt formatting.
- Output formatting:
  - `-box` _(Default)_: Clean Unicode boxed tables, ideal for terminal viewing.
  - `-json`: Output rows as JSON array of objects (ideal for piping to scripts).
  - `-csv`: Output standard comma-separated values with headers.
  - `-markdown`: Output standard markdown pipe tables.
  - `-bail`: Stop execution immediately on first error.

```bash
# Human-readable boxed table (non-interactive safe, zero 5s hang)
~/.local/bin/duckdb -batch -dark-mode -box -c "SELECT 42 AS answer;"

# Programmatic JSON output
~/.local/bin/duckdb -batch -dark-mode -json -c "SELECT 42 AS answer;"
```

---

## Core Gotchas & Invariants

1.  **5-Second Hang on Subshells (`-batch -dark-mode` Required)**: Passing
    `-batch` alone does **not** disable DuckDB's 5-second OSC terminal
    background color probe timeout. Always pass `-batch -dark-mode` together.
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

---

## Format Recipes

### 1. JSON and JSON Lines (JSONL / NDJSON)

DuckDB automatically discovers schemas and flattens top-level keys into columns.

```bash
# Auto-detect schema and preview first 10 rows
duckdb -dark-mode -box -c "
SELECT * FROM 'data.jsonl' LIMIT 10;
"

# Handle irregular schemas and malformed lines
duckdb -dark-mode -box -c "
SELECT * FROM read_json('logs/*.jsonl', union_by_name=true, ignore_errors=true)
LIMIT 10;
"

# Inspect inferred column names and types
duckdb -dark-mode -box -c "
DESCRIBE SELECT * FROM 'data.jsonl';
"
```

#### Nested Fields and Arrays

- **Struct / Object**: Dot notation `col.nested_field` or bracket
  `col['nested_field']`.
- **List Index**: 1-based indexing `tags[1]`.
- **Array Unnest**: `unnest(tags)` explodes array elements into multiple rows.

```bash
duckdb -dark-mode -box -c "
SELECT
  id,
  user.email,
  tags[1] AS primary_tag,
  unnest(tags) AS individual_tag
FROM 'users.jsonl';
"
```

### 2. CSV & TSV

DuckDB auto-detects delimiters (comma, tab, pipe), quoting, and header rows.

```bash
# Auto-detect headers and delimiter
duckdb -dark-mode -box -c "
SELECT * FROM 'export.csv' LIMIT 10;
"

# Explicit delimiter and column types
duckdb -dark-mode -box -c "
SELECT * FROM read_csv('dump.tsv', delim='\t', header=true, all_varchar=true)
LIMIT 10;
"

# Read gzipped CSV directly
duckdb -dark-mode -box -c "
SELECT count(*) FROM 'large_data.csv.gz';
"
```

### 3. Parquet

Parquet is the most performant format for analytical scans.

```bash
# Read Parquet files (supports globbing)
duckdb -dark-mode -box -c "
SELECT * FROM 'metrics/*.parquet' WHERE value > 100 LIMIT 10;
"

# Inspect Parquet schema without scanning data
duckdb -dark-mode -box -c "
SELECT * FROM parquet_schema('metrics/part-00.parquet');
"

# Inspect Parquet row groups and metadata
duckdb -dark-mode -box -c "
SELECT num_rows, num_row_groups, format_version
FROM parquet_file_metadata('metrics/part-00.parquet');
"
```

### 4. Format Conversion & Materialization

Convert bloated JSONL or CSV datasets into compressed Parquet for 10x-50x faster
future scans and 80%+ disk space savings.

```bash
# Convert JSONL to Parquet (Snappy compression by default, zstd optional)
duckdb -dark-mode -c "
COPY (
  SELECT * FROM read_json('raw_logs/*.jsonl', union_by_name=true, ignore_errors=true)
) TO 'compacted_logs.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);
"

# Export query results directly to CSV
duckdb -dark-mode -c "
COPY (SELECT id, user.email FROM 'users.jsonl') TO 'users_summary.csv' (HEADER, DELIMITER ',');
"
```

### 5. Standard Input Streaming

Query data directly from shell pipelines without intermediate files:

```bash
# Stream JSON from a curl command or shell pipeline
curl -s "https://api.example.com/items" | \
duckdb -dark-mode -box -c "
SELECT * FROM read_json('/dev/stdin') LIMIT 10;
"

# Stream CSV pipeline
cat input.csv | \
~/.local/bin/duckdb -batch -dark-mode -box -c "
SELECT col1, sum(col2) FROM read_csv('/dev/stdin', header=true) GROUP BY col1;
"
```

### 6. Local Databases (`.db`, `.duckdb`, `.sqlite`)

Since `.db` files can be either native DuckDB or SQLite databases, check with
`file <path>` first:

```bash
# 1. Inspect database file format
file path/to/database.db

# 2a. If "DuckDB database file": pass file path directly
~/.local/bin/duckdb -batch -dark-mode -box path/to/database.db -c "
SHOW TABLES;
SELECT * FROM my_table LIMIT 10;
"

# 2b. If "SQLite 3.x database": attach with TYPE SQLITE
~/.local/bin/duckdb -batch -dark-mode -box -c "
ATTACH 'path/to/database.db' AS db (TYPE SQLITE, READ_ONLY);
SHOW ALL TABLES;
SELECT * FROM db.my_table LIMIT 10;
"
```

### 7. Embedded JSON Blocks in Log Files

When benchmark or test runners embed JSON payloads inside standard output logs
(e.g. `<<<BENCH_PRESS_JSON_START>>>` ... `<<<BENCH_PRESS_JSON_END>>>`), extract
and pipe directly into `read_json('/dev/stdin')`:

```bash
sed -n '/<<<BENCH_PRESS_JSON_START>>>/,/<<<BENCH_PRESS_JSON_END>>>/{//!p;}' test.log | \
~/.local/bin/duckdb -batch -dark-mode -box -c "
SELECT * FROM read_json('/dev/stdin');
"
```

---

## Memory & Resource Management

For large datasets (>10GB):

```bash
duckdb -dark-mode -c "
SET max_memory = '16GB';
SET threads = 8;
SET preserve_insertion_order = false;
SELECT count(*) FROM 'massive_dataset/*.parquet';
"
```

---

## Advanced Recipes

For specialized workflows, see:

- [references/recipes.md](references/recipes.md): Analyzing agent conversation
  history (`~/.gemini/*/brain/...`), cross-format joins (JSON + CSV + Parquet),
  and partitioned exports.
