# DuckDB Advanced Recipes

Advanced recipes and patterns for local data analysis and file transformations
on Linux and macOS.

---

## 1. Querying Agent Conversation History

Local Gemini CLI / agent session transcripts are stored in JSON Lines format
under: `~/.gemini/*/brain/<convo_id>/.system_generated/logs/transcript.jsonl`

DuckDB can scan millions of historical execution steps in 0.1–0.4 seconds when
explicit schema projection is used.

### Tool Selection Boundary: `transcript-view` vs. `duckdb`

- **Single Conversation Inspection (`transcript-view`)**: When reading or
  inspecting steps within a **single known conversation UUID**, use the
  dedicated CLI helper (if installed):
  `~/.local/bin/transcript-view <cid> [--tools] [--step N] [--tail N]`
- **Cross-Conversation Search & Analytics (`duckdb`)**: Use DuckDB SQL when
  searching across multiple conversations, aggregating tool usage, auditing
  error rates, or filtering prompts by keyword/time window.

### Invariants & Fast-Path Projection (`0.39s` vs. `1.10s`)

- **Explicit `columns={...}` Map (3x Speedup)**: Without `columns={...}`, DuckDB
  samples schemas across ~4,900 files (~1.1s latency). Passing an explicit
  `columns` map skips schema inference and drops scan latency to **~0.39s**
  across >1M rows.
- **Always Type `tool_calls` as `STRUCT(name VARCHAR, args JSON)[]`**: If
  `tool_calls` is typed as `'JSON[]'`, `tc.name` returns a JSON-encoded string
  (`"\"run_command\""`) and `WHERE tc.name = 'run_command'` fails with
  `Malformed JSON at byte 0 of input`. Typing it as
  `STRUCT(name VARCHAR, args JSON)[]` exposes native `VARCHAR` fields.
- **`ignore_errors = true`**: Essential because killed or interrupted sessions
  may leave malformed trailing lines in `transcript.jsonl`.
- **`filename = true`**: Exposes the file path column to extract conversation
  UUIDs (`regexp_extract(filename, 'brain/([^/]+)/', 1)`).
- **Sub-100ms Scans with `fd` / `fdfind` Pre-Filtering**: Scoping DuckDB to
  files modified in the last 7 days drops scan latency to **~0.10s** (use
  `SET VARIABLE` + `getvariable()` because DuckDB table functions reject inline
  subqueries with `Binder Error: Table function cannot contain subqueries`):

  ```bash
  fd -H -I -t f --changed-within 7d 'transcript\.jsonl$' ~/.gemini/ > recent_transcripts.txt
  duckdb -batch -dark-mode -box -c "
  SET VARIABLE recent_files = (SELECT list(column0) FROM read_csv('recent_transcripts.txt', header=false));
  SELECT count(*) FROM read_json(
    getvariable('recent_files'),
    columns={'step_index': 'BIGINT', 'type': 'VARCHAR'},
    ignore_errors=true
  );
  "
  ```

### Claude Code Transcripts: Use `**`, and Verify the File Count

Claude Code stores transcripts under `~/.claude/projects/<project-slug>/`, but
**subagent transcripts nest one level deeper**
(`<project-slug>/<session-uuid>/subagents/agent-*.jsonl`). A natural-looking
`*/*.jsonl` therefore matches only the top-level session files and silently
skips the rest — on one machine, 31 of 102 files. Because those 31 top-level
files satisfy the glob, DuckDB does not error; it just returns a smaller,
confident-looking answer.

Always use `**/*.jsonl`, and sanity-check `count(DISTINCT filename)` against
`find`:

```bash
find ~/.claude/projects -name '*.jsonl' | wc -l   # ground truth

duckdb -batch -dark-mode -c "
SELECT count(DISTINCT filename) AS files, count(*) AS rows
FROM read_json_auto('$HOME/.claude/projects/**/*.jsonl',
                    format='newline_delimited', ignore_errors=true,
                    union_by_name=true, filename=true,
                    maximum_object_size=100000000);
"
```

- **`ignore_errors=true` is what tolerates truncated lines**: a session still
  being appended to leaves a partial trailing line, and without this flag a
  single bad line aborts the whole scan
  (`Invalid Input Error: Malformed JSON ... unexpected control character`). It
  does **not** require `format` to be set (verified on DuckDB `v1.5.5`).
- **`format='newline_delimited'` is an optional speed/robustness pin**: it skips
  format auto-detection, which is safe for `.jsonl`. Do not apply it blindly to
  other inputs — forcing it on a file that is really a JSON array silently
  returns 1 row instead of the array's elements.
- **`union_by_name=true` is required**: row shapes differ across record types
  (`user`, `assistant`, `attachment`, `system`, …).
- **Raise `maximum_object_size`**: large tool-result rows exceed the default and
  abort the scan.
- **Project slug**: `regexp_extract(filename, 'projects/([^/]+)/', 1)` (the
  analogue of the Gemini `brain/([^/]+)/` extraction above).

Example — busiest projects by user turn:

```bash
duckdb -batch -dark-mode -c "
SELECT regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
       count(*) AS user_msgs
FROM read_json_auto('$HOME/.claude/projects/**/*.jsonl',
                    format='newline_delimited', ignore_errors=true,
                    union_by_name=true, filename=true,
                    maximum_object_size=100000000)
WHERE type = 'user'
GROUP BY 1 ORDER BY user_msgs DESC LIMIT 10;
"
```

### Recipe 1.1: Aggregating Across All Conversations

```bash
duckdb -batch -dark-mode -box -c "
SELECT
  count(*) AS total_steps,
  count(distinct filename) AS num_conversations,
  min(created_at) AS earliest_log,
  max(created_at) AS latest_log
FROM read_json(
  '~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl',
  columns={'step_index': 'BIGINT', 'created_at': 'VARCHAR'},
  ignore_errors=true,
  filename=true
);
"
```

### Recipe 1.2: Top 15 Tools Used Across History

```bash
duckdb -batch -dark-mode -box -c "
WITH tool_usage AS (
  SELECT
    tc.name AS tool_name,
    count(*) AS invocation_count
  FROM read_json(
    '~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl',
    columns={'tool_calls': 'STRUCT(name VARCHAR, args JSON)[]'},
    ignore_errors=true
  ) t,
  unnest(t.tool_calls) AS u(tc)
  GROUP BY tool_name
)
SELECT
  tool_name,
  invocation_count,
  round(invocation_count * 100.0 / sum(invocation_count) OVER (), 2) AS pct_of_total
FROM tool_usage
ORDER BY invocation_count DESC
LIMIT 15;
"
```

### Recipe 1.3: Search Past User Prompts

Find conversations where specific keywords or workflows were discussed:

```bash
duckdb -batch -dark-mode -box -c "
SELECT
  regexp_extract(filename, 'brain/([^/]+)/', 1) AS convo_id,
  created_at,
  substring(content, 1, 100) AS prompt_snippet
FROM read_json(
  '~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl',
  columns={'type': 'VARCHAR', 'created_at': 'VARCHAR', 'content': 'VARCHAR'},
  ignore_errors=true,
  filename=true
)
WHERE type = 'USER_INPUT' AND content ILIKE '%duckdb%'
ORDER BY created_at DESC
LIMIT 10;
"
```

### Recipe 1.4: Tool Error Rate Audit

Identify which tools fail most often across sessions (correlating the planner
step with the subsequent tool failure status):

```bash
duckdb -batch -dark-mode -box -c "
WITH steps AS (
  SELECT
    filename,
    step_index,
    status,
    tool_calls,
    lead(status) OVER (PARTITION BY filename ORDER BY step_index) AS next_status
  FROM read_json(
    '~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl',
    columns={'step_index': 'BIGINT', 'status': 'VARCHAR', 'tool_calls': 'STRUCT(name VARCHAR, args JSON)[]'},
    ignore_errors=true,
    filename=true
  )
)
SELECT
  tc.name AS tool_name,
  count(*) AS error_count
FROM steps t,
     unnest(t.tool_calls) AS u(tc)
WHERE t.next_status = 'ERROR'
GROUP BY tool_name
ORDER BY error_count DESC
LIMIT 10;
"
```

### Recipe 1.5: `tool_calls` File Edits, `EPHEMERAL_MESSAGE` Memory Filtering & CLI Exit-Code Errors

- **`tool_calls` vs. `content` Invariant**: Tool invocations (`write_to_file`,
  `replace_file_content`, `run_command`) are stored in
  `tool_calls: STRUCT(name VARCHAR, args JSON)[]`, never in
  `PLANNER_RESPONSE.content`. Always cast `CAST(tool_calls AS VARCHAR)` when
  checking which files a session modified or whether it wrote to
  `~/memory/default/topics/*.md`.
- **Stripping Ambient `<memory>` Echoes (`EPHEMERAL_MESSAGE` + `GENERIC`)**: In
  `transcript.jsonl`, ambient `<memory>...</memory>` system blocks live in
  `type = 'EPHEMERAL_MESSAGE'` (`~197k` rows across the archive) and as trailing
  attachments on `type = 'GENERIC'` tool outputs (`~2.2k` rows), while
  `USER_INPUT` is wrapped in `<USER_REQUEST>...</USER_REQUEST>` and
  `<ADDITIONAL_METADATA>...</ADDITIONAL_METADATA>`. Always filter
  `WHERE coalesce(type, '') != 'EPHEMERAL_MESSAGE'` and strip wrapper tags via
  `regexp_replace(coalesce(content, ''), '(?s)(<memory>.*?</memory>|<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>|</?USER_REQUEST>)', '', 'g')`.
- **CLI Command Failures Live in `GENERIC` (`status = 'DONE'`), Not
  `status = 'ERROR'`**: `status = 'ERROR'` only records internal tool-harness
  errors (`~680` rows). When a shell command (`run_command`) exits non-zero, the
  harness records `type = 'GENERIC'` with `status = 'DONE'` and
  `The command exited with code [1-9]` (`~11,600` rows).
- **Code-Host URL Extraction**: Always match both GitHub
  (`github\.com/.+/(?:issues|pull)/[0-9]+`) and Gerrit
  (`dart-review\.googlesource\.com/c/sdk/\+/[0-9]+`) URLs.

```bash
duckdb -batch -dark-mode -box -c "
WITH raw AS (
  SELECT
    regexp_extract(filename, 'brain/([^/]+)/', 1) AS convo_id,
    regexp_replace(coalesce(content, ''), '(?s)(<memory>.*?</memory>|<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>|</?USER_REQUEST>)', '', 'g') AS clean_content,
    CAST(tool_calls AS VARCHAR) AS tc_str
  FROM read_json(
    '~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl',
    columns={
      'type': 'VARCHAR',
      'content': 'VARCHAR',
      'tool_calls': 'STRUCT(name VARCHAR, args JSON)[]'
    },
    ignore_errors=true,
    filename=true
  )
  WHERE coalesce(type, '') != 'EPHEMERAL_MESSAGE'
),
memory_convos AS (
  SELECT DISTINCT convo_id
  FROM raw
  WHERE (tc_str ILIKE '%write_to_file%' OR tc_str ILIKE '%replace_file_content%')
    AND tc_str ILIKE '%memory/default/topics/%'
)
SELECT
  convo_id,
  count(*) FILTER (
    WHERE (tc_str ILIKE '%write_to_file%' OR tc_str ILIKE '%replace_file_content%')
      AND (tc_str ILIKE '%/github/flutter%' OR tc_str ILIKE '%/github/dart-sdk%')
  ) AS code_edits,
  list_distinct(flatten(list(regexp_extract_all(
    clean_content || ' ' || coalesce(tc_str, ''),
    'dart-review\.googlesource\.com/c/sdk/\+/[0-9]+|github\.com/(?:flutter/flutter|dart-lang/[a-z0-9_-]+)/(?:issues|pull)/[0-9]+'
  )))) AS upstream_urls
FROM raw
WHERE convo_id NOT IN (SELECT convo_id FROM memory_convos)
GROUP BY convo_id
HAVING code_edits >= 10 AND len(upstream_urls) > 0
ORDER BY code_edits DESC
LIMIT 15;
"
```

### Recipe 1.6: Searching & Joining JSONL Log Globs with a SQLite Index

When a directory of JSONL files (such as session transcripts, event logs, or
trace shards) is paired with a local SQLite metadata or index database, attach
the SQLite file with `ATTACH '...' AS db (TYPE SQLITE, READ_ONLY)` and join it
against `read_json(..., filename=true)` via a path-extracted key in a single
query.

For example, to search agent transcripts (`transcript.jsonl`) for any topic,
error, command, symbol, file, CL, or PR and join the hits with
`~/.gemini/jetski/conversation_summaries.db` (~3.5 seconds):

- Extract the join key from each file path with
  `regexp_extract(filename, 'brain/([^/]+)/', 1)`.
- Search both `content` (prompts, responses, and tool outputs) and
  `CAST(tool_calls AS VARCHAR)` (commands, file paths, and tool arguments) using
  `ILIKE`, `LIKE`, or `regexp_matches(...)`.
- Exclude `EPHEMERAL_MESSAGE` rows so ambient `<memory>` injections do not
  produce false matches.
- Count `matching_steps` to separate primary sessions from 1-step incidental
  mentions, and filter out subagent rows via `parent_conversation_id` and
  `nesting_depth`.
- Columns with SQLite `TIMESTAMP` affinity (such as `last_modified_time`) must
  be formatted with `strftime(col, '%Y-%m-%d %H:%M:%S')` rather than
  `substr(col, ...)`.
- Unlike `read_json('~/...')`, DuckDB's SQLite extension passes the `ATTACH`
  path directly to `sqlite3_open_v2` without `~` expansion. Use `$HOME` inside
  the double-quoted `-c "..."` string.
- The query sits inside a double-quoted shell string. In `<search_term>`, escape
  `\`, `$`, `` ` ``, and `"` with a backslash, and double any `'`.
- `CAST(tool_calls AS VARCHAR)` is serialized JSON that escapes `"` and `\` as
  `\"` and `\\`, so terms containing either match `content` only. `ILIKE` also
  treats `%` and `_` as wildcards.

```bash
duckdb -batch -dark-mode -box -c "
ATTACH '$HOME/.gemini/jetski/conversation_summaries.db' AS db (TYPE SQLITE, READ_ONLY);
WITH hits AS (
  SELECT
    regexp_extract(filename, 'brain/([^/]+)/', 1) AS conversation_id,
    count(*) AS matching_steps
  FROM read_json(
    '~/.gemini/jetski/brain/*/.system_generated/logs/transcript.jsonl',
    columns={'type': 'VARCHAR', 'content': 'VARCHAR', 'tool_calls': 'JSON'},
    ignore_errors=true,
    filename=true
  )
  WHERE coalesce(type, '') != 'EPHEMERAL_MESSAGE'
    AND (content ILIKE '%<search_term>%' OR CAST(tool_calls AS VARCHAR) ILIKE '%<search_term>%')
  GROUP BY 1
)
SELECT
  s.conversation_id,
  s.title,
  s.step_count,
  h.matching_steps,
  strftime(s.last_modified_time, '%Y-%m-%d %H:%M:%S') AS modified
FROM hits h
JOIN db.conversation_summaries s USING (conversation_id)
WHERE coalesce(s.parent_conversation_id, '') = ''
  AND coalesce(s.nesting_depth, 0) = 0
ORDER BY s.last_modified_time DESC
LIMIT 15;
"
```

---

## 2. Cross-Format Joins

DuckDB allows joins across heterogeneous file formats (JSONL, CSV, Parquet, and
attached SQLite databases; see also Recipe 1.6) in a single SQL statement:

```bash
duckdb -batch -dark-mode -box -c "
SELECT
  u.id,
  u.meta.owner AS owner,
  o.order_id,
  o.amount,
  p.sku_description
FROM read_json('users.jsonl', union_by_name=true) u
JOIN read_csv('orders.csv', header=true) o ON u.id = o.user_id
JOIN read_parquet('products.parquet') p ON o.product_id = p.id
WHERE o.amount > 500
ORDER BY o.amount DESC
LIMIT 20;
"
```

---

## 3. Hive Partitioning & Globbing

DuckDB automatically parses directory partitions (e.g. `year=2026/month=08/`):

```bash
# Read multi-level partitioned dataset
duckdb -batch -dark-mode -box -c "
SELECT year, month, count(*) AS event_count
FROM read_parquet('events/*/*/*.parquet', hive_partitioning=true)
GROUP BY year, month
ORDER BY year DESC, month DESC;
"
```

---

## 4. Partitioned Materialization

Export query results into Hive-partitioned Parquet files:

```bash
duckdb -batch -dark-mode -c "
COPY (
  SELECT
    id,
    created_at::DATE AS log_date,
    status,
    payload
  FROM read_json('raw/*.jsonl', union_by_name=true, ignore_errors=true)
) TO 'partitioned_output' (
  FORMAT PARQUET,
  PARTITION_BY (log_date, status),
  OVERWRITE_OR_IGNORE 1
);
"
```

---

## 5. In-Memory vs. Persistent Database

By default, DuckDB runs in-memory (`:memory:`) and discards state after the
command completes.

To persist tables across multiple shell invocations:

```bash
# Create or open a local DuckDB database file
duckdb -batch -dark-mode analytics.duckdb -c "
CREATE TABLE users AS SELECT * FROM 'users.jsonl';
"

# Query the persistent table later
duckdb -batch -dark-mode analytics.duckdb -box -c "
SELECT count(*) FROM users;
"
```

---

## 6. Benchmark JSON Artifacts, Embedded Log Blocks & Multi-Target Pivots

When benchmark or test runners embed JSON payloads inside standard output logs
(e.g. `<<<BENCH_PRESS_JSON_START>>>` ... `<<<BENCH_PRESS_JSON_END>>>`), extract
and pipe directly into `read_json('/dev/stdin')`:

```bash
sed -n '/<<<BENCH_PRESS_JSON_START>>>/,/<<<BENCH_PRESS_JSON_END>>>/{//!p;}' test.log | \
duckdb -batch -dark-mode -box -c "
SELECT * FROM read_json('/dev/stdin');
"
```

When analyzing benchmark JSON reports (e.g. `bench_press` or `codable`
multi-tier benchmarks across AOT, JIT, and Wasm targets), unnest target arrays
and compute isolated before/after speedups directly in SQL:

```bash
duckdb -batch -dark-mode -markdown -c "
WITH benchmarks AS (
  SELECT
    target,
    b.name AS benchmark_name,
    b.latency_us
  FROM read_json('benchmark_results.json') r,
       unnest(r.results) AS u(b)
)
SELECT
  benchmark_name,
  round(min(latency_us) FILTER (WHERE target = 'aot'), 2) AS aot_us,
  round(min(latency_us) FILTER (WHERE target = 'jit'), 2) AS jit_us,
  round(min(latency_us) FILTER (WHERE target = 'wasm'), 2) AS wasm_us
FROM benchmarks
GROUP BY benchmark_name
ORDER BY benchmark_name;
"
```

---

## 7. Format Conversion & Large Dataset Tuning

Convert bloated JSONL or CSV datasets into compressed Parquet for 10x–50x faster
future scans and 80%+ disk space savings, or export query results to CSV:

```bash
# Convert JSONL to ZSTD-compressed Parquet
duckdb -batch -dark-mode -c "
COPY (
  SELECT * FROM read_json('raw_logs/*.jsonl', union_by_name=true, ignore_errors=true)
) TO 'compacted_logs.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);
"

# Export query results directly to CSV
duckdb -batch -dark-mode -c "
COPY (SELECT id, user.email FROM 'users.jsonl') TO 'users_summary.csv' (HEADER, DELIMITER ',');
"
```

For large datasets (`>10GB`), bound memory and thread usage explicitly:

```bash
duckdb -batch -dark-mode -c "
SET max_memory = '16GB';
SET threads = 8;
SET preserve_insertion_order = false;
SELECT count(*) FROM 'massive_dataset/*.parquet';
"
```

---

## 8. Querying Large Code Diffs

Use [`../scripts/diff_macros.sql`](../scripts/diff_macros.sql) to query unified
diffs with SQL. Use `rg` for single-pattern text searches in a working tree, and
use DuckDB for multi-condition filters and aggregations across diff lines and
hunks.

### Recipe 8.1: Query Raw Unified Diffs via Standard Input

Pipe `git diff` or `gh pr diff` directly into `read_diff_lines('/dev/stdin')` or
`read_diff_hunks('/dev/stdin')`:

```bash
git diff main...HEAD | duckdb -batch -dark-mode -box \
  -init skills/duckdb/scripts/diff_macros.sql -c "
SELECT file_path, new_line, content
FROM read_diff_lines('/dev/stdin')
WHERE op = '+'
  AND regexp_matches(content, 'TODO|FIXME|console\.log')
  AND file_path NOT LIKE '%test%';
"
```

### Recipe 8.2: Summarize Hunk Churn Across Files (`read_diff_hunks`)

Aggregate hunk counts, added lines, and deleted lines per file or function
context header across a branch diff:

```bash
git diff main...HEAD | duckdb -batch -dark-mode -box \
  -init skills/duckdb/scripts/diff_macros.sql -c "
SELECT
  file_path,
  count(*) AS hunks,
  sum(added_lines) AS lines_added,
  sum(deleted_lines) AS lines_deleted
FROM read_diff_hunks('/dev/stdin')
GROUP BY file_path
ORDER BY (sum(added_lines) + sum(deleted_lines)) DESC
LIMIT 15;
"
```

---

## 9. Querying Large Markdown Files & Documentation Corpora

Use [`../scripts/markdown_macros.sql`](../scripts/markdown_macros.sql) to index
Markdown sections and fenced code blocks with SQL.

### Tool Selection Thresholds

- Below 350 lines (`< 15 KB`): Read the file directly with `read_file`. One call
  loads the entire file in 1,500 to 3,500 tokens.
- Single-line pattern search: Use `rg -n` when heading hierarchy and code-fence
  state do not matter.
- Single file of 350+ lines (`15+ KB`) or above the 800-line `read_file` cap:
  Query `read_md_sections` (`~70 ms`) to get the section outline and
  `line_start..subtree_line_end` span, then pass those bounds to `read_file`.
- Multi-file corpus (`10+` files): Query `read_md_sections('**/*.md')` or
  `read_md_code_blocks('**/*.md')`. The macro indexes ATX (`#`) headings only
  and tracks fenced code blocks per CommonMark (closing a fence only on a bare
  line of the same backtick or tilde character with at least the opener's
  length), so `#` comments and nested fences inside code blocks stay out of the
  outline.
- Encoding: The macros read files with `read_text`, which accepts only UTF-8.
  One non-UTF-8 file aborts the whole query and names the file in the error;
  re-encode it, or pass a narrower glob or a list of paths such as
  `read_md_sections(['docs/a.md', 'docs/b.md'])`.

### Recipe 9.1: Section Outline and Subtree Line Spans (`read_md_sections`)

List top-level sections with both their own intro line range
(`line_start..line_end`) and full subtree line range
(`line_start..subtree_line_end`) before calling `read_file`:

```bash
duckdb -batch -dark-mode -box \
  -init skills/duckdb/scripts/markdown_macros.sql -c "
SELECT
  section_id,
  level,
  heading,
  line_start,
  line_end,
  subtree_line_end,
  own_lines,
  subtree_lines
FROM read_md_sections('skills/duckdb/references/recipes.md')
WHERE level <= 2;
"
```

### Recipe 9.2: Audit Fenced Code Blocks Across a Glob (`read_md_code_blocks`)

Extract fenced code blocks by language tag or enclosing section across an entire
repository. A non-matching glob returns zero rows with exit code 0, and any
non-UTF-8 file aborts the scan, so verify `read_md_sections` is non-empty first:

```bash
duckdb -batch -dark-mode -box \
  -init skills/duckdb/scripts/markdown_macros.sql -c "
SELECT
  regexp_extract(file_path, '[^/]+/[^/]+$') AS skill_file,
  block_id,
  section_heading,
  lang,
  line_start,
  line_end
FROM read_md_code_blocks('skills/**/*.md')
WHERE lang IN ('bash', 'sh')
  AND contains(code, 'duckdb')
  AND NOT contains(code, '-dark-mode');
"
```
