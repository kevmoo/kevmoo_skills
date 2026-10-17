-- Relational Code Diff Macros for DuckDB
-- Load with: duckdb -batch -dark-mode -init agents/skills/duckdb/scripts/diff_macros.sql

-- 1. Layer 1: Parse raw unified diff lines directly from a .diff file or '/dev/stdin'
CREATE OR REPLACE MACRO read_diff_lines(diff_path) AS TABLE
WITH raw_lines AS (
  SELECT
    row_number() OVER () AS row_id,
    rtrim(line, chr(13)) AS line
  FROM read_csv(
    diff_path,
    header=false,
    columns={'line': 'VARCHAR'},
    quote='',
    delim=chr(0),
    null_padding=true
  )
),
classified AS (
  SELECT
    row_id,
    line,
    COALESCE(
      NULLIF(regexp_extract(line, '^\+\+\+ "b/((?:[^"\\]|\\.)+)"', 1), ''),
      NULLIF(regexp_extract(line, '^\+\+\+ b/([^\t\r\n]+)', 1), ''),
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) "b/((?:[^"\\]|\\.)+)"$', 1), ''),
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) b/(\S+)$', 1), ''),
      NULLIF(regexp_extract(line, '^--- "a/((?:[^"\\]|\\.)+)"', 1), ''),
      NULLIF(regexp_extract(line, '^--- a/([^\t\r\n]+)', 1), '')
    ) AS extracted_file,
    starts_with(line, '@@ ') AS is_hunk,
    (
      starts_with(line, 'diff --git ')
      OR starts_with(line, 'index ')
      OR starts_with(line, '--- ')
      OR starts_with(line, '+++ ')
      OR starts_with(line, 'new file ')
      OR starts_with(line, 'deleted file ')
      OR starts_with(line, 'similarity index ')
      OR starts_with(line, 'rename from ')
      OR starts_with(line, 'rename to ')
      OR starts_with(line, 'old mode ')
      OR starts_with(line, 'new mode ')
      OR starts_with(line, 'Binary files ')
      OR starts_with(line, '\ No newline')
    ) AS is_meta
  FROM raw_lines
),
with_hunks AS (
  SELECT
    row_id,
    line,
    is_hunk,
    is_meta,
    LAST_VALUE(extracted_file IGNORE NULLS) OVER (
      ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS file_path,
    COUNT(*) FILTER (WHERE is_hunk) OVER (
      ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS hunk_id
  FROM classified
),
hunk_context AS (
  SELECT
    row_id,
    line,
    is_hunk,
    is_meta,
    file_path,
    hunk_id,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN TRY_CAST(regexp_extract(line, '^@@ -(\d+)', 1) AS INTEGER)
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS old_start,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN TRY_CAST(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+(\d+)', 1) AS INTEGER)
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS new_start,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN trim(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(.*)$', 1))
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS func_context,
    left(line, 1) AS op,
    (hunk_id > 0 AND NOT is_hunk AND NOT is_meta AND left(line, 1) IN ('+', '-', ' ')) AS is_body
  FROM with_hunks
)
SELECT
  file_path,
  hunk_id,
  func_context,
  op,
  CASE
    WHEN op IN ('-', ' ') THEN old_start + COUNT(*) FILTER (WHERE is_body AND op IN ('-', ' ')) OVER (
      PARTITION BY hunk_id ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    )
    ELSE NULL
  END AS old_line,
  CASE
    WHEN op IN ('+', ' ') THEN new_start + COUNT(*) FILTER (WHERE is_body AND op IN ('+', ' ')) OVER (
      PARTITION BY hunk_id ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    )
    ELSE NULL
  END AS new_line,
  substr(line, 2) AS content
FROM hunk_context
WHERE is_body
ORDER BY row_id;

-- 2. Layer 1: Summarize hunks directly from a raw unified diff file or '/dev/stdin'
CREATE OR REPLACE MACRO read_diff_hunks(diff_path) AS TABLE
WITH raw_lines AS (
  SELECT
    row_number() OVER () AS row_id,
    rtrim(line, chr(13)) AS line
  FROM read_csv(
    diff_path,
    header=false,
    columns={'line': 'VARCHAR'},
    quote='',
    delim=chr(0),
    null_padding=true
  )
),
classified AS (
  SELECT
    row_id,
    line,
    COALESCE(
      NULLIF(regexp_extract(line, '^\+\+\+ "b/((?:[^"\\]|\\.)+)"', 1), ''),
      NULLIF(regexp_extract(line, '^\+\+\+ b/([^\t\r\n]+)', 1), ''),
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) "b/((?:[^"\\]|\\.)+)"$', 1), ''),
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) b/(\S+)$', 1), ''),
      NULLIF(regexp_extract(line, '^--- "a/((?:[^"\\]|\\.)+)"', 1), ''),
      NULLIF(regexp_extract(line, '^--- a/([^\t\r\n]+)', 1), '')
    ) AS extracted_file,
    starts_with(line, '@@ ') AS is_hunk,
    (
      starts_with(line, 'diff --git ')
      OR starts_with(line, 'index ')
      OR starts_with(line, '--- ')
      OR starts_with(line, '+++ ')
      OR starts_with(line, 'new file ')
      OR starts_with(line, 'deleted file ')
      OR starts_with(line, 'similarity index ')
      OR starts_with(line, 'rename from ')
      OR starts_with(line, 'rename to ')
      OR starts_with(line, 'old mode ')
      OR starts_with(line, 'new mode ')
      OR starts_with(line, 'Binary files ')
      OR starts_with(line, '\ No newline')
    ) AS is_meta
  FROM raw_lines
),
with_hunks AS (
  SELECT
    row_id,
    line,
    is_hunk,
    is_meta,
    LAST_VALUE(extracted_file IGNORE NULLS) OVER (
      ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS file_path,
    COUNT(*) FILTER (WHERE is_hunk) OVER (
      ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS hunk_id
  FROM classified
)
SELECT
  FIRST(file_path ORDER BY row_id) AS file_path,
  hunk_id,
  FIRST(TRY_CAST(regexp_extract(line, '^@@ -(\d+)', 1) AS INTEGER) ORDER BY row_id) AS old_start,
  FIRST(
    COALESCE(
      TRY_CAST(NULLIF(regexp_extract(line, '^@@ -\d+,(\d+)', 1), '') AS INTEGER),
      1
    ) ORDER BY row_id
  ) AS old_count,
  FIRST(TRY_CAST(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+(\d+)', 1) AS INTEGER) ORDER BY row_id) AS new_start,
  FIRST(
    COALESCE(
      TRY_CAST(NULLIF(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+,(\d+)', 1), '') AS INTEGER),
      1
    ) ORDER BY row_id
  ) AS new_count,
  FIRST(trim(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(.*)$', 1)) ORDER BY row_id) AS func_context,
  COUNT(*) FILTER (WHERE NOT is_hunk AND NOT is_meta AND left(line, 1) = '+') AS added_lines,
  COUNT(*) FILTER (WHERE NOT is_hunk AND NOT is_meta AND left(line, 1) = '-') AS deleted_lines
FROM with_hunks
WHERE hunk_id > 0
GROUP BY hunk_id
ORDER BY hunk_id;

-- 3. Layer 2: Read staged diff_lines.jsonl emitted by split_diff.py --grouped
CREATE OR REPLACE MACRO staged_diff_lines(diff_dir) AS TABLE
SELECT *
FROM read_json(
  diff_dir || '/diff_lines.jsonl',
  columns={
    'file_path': 'VARCHAR',
    'chunk_name': 'VARCHAR',
    'hunk_id': 'INTEGER',
    'func_context': 'VARCHAR',
    'op': 'VARCHAR',
    'old_line': 'INTEGER',
    'new_line': 'INTEGER',
    'content': 'VARCHAR'
  },
  format='newline_delimited',
  ignore_errors=true
);

-- 4. Layer 2: Read staged diff_hunks.jsonl emitted by split_diff.py --grouped
CREATE OR REPLACE MACRO staged_diff_hunks(diff_dir) AS TABLE
SELECT *
FROM read_json(
  diff_dir || '/diff_hunks.jsonl',
  columns={
    'file_path': 'VARCHAR',
    'chunk_name': 'VARCHAR',
    'hunk_id': 'INTEGER',
    'old_start': 'INTEGER',
    'old_count': 'INTEGER',
    'new_start': 'INTEGER',
    'new_count': 'INTEGER',
    'func_context': 'VARCHAR',
    'added_lines': 'INTEGER',
    'deleted_lines': 'INTEGER'
  },
  format='newline_delimited',
  ignore_errors=true
);

-- 5. Layer 3: Read staged diff_entities.jsonl emitted by split_diff.py --grouped --with-entities
CREATE OR REPLACE MACRO staged_diff_entities(diff_dir) AS TABLE
SELECT *
FROM read_json(
  diff_dir || '/diff_entities.jsonl',
  columns={
    'file_path': 'VARCHAR',
    'side': 'VARCHAR',
    'kind': 'VARCHAR',
    'name': 'VARCHAR',
    'signature': 'VARCHAR',
    'line_start': 'INTEGER',
    'line_end': 'INTEGER'
  },
  format='newline_delimited',
  ignore_errors=true
);

-- 6. Layer 3: Range-join added diff lines to innermost enclosing AST symbols
CREATE OR REPLACE MACRO diff_entity_churn(diff_dir) AS TABLE
WITH innermost_matches AS (
  SELECT
    e.file_path,
    e.kind,
    e.name,
    e.signature,
    e.line_start,
    e.line_end,
    l.chunk_name,
    l.new_line
  FROM staged_diff_entities(diff_dir) e
  JOIN staged_diff_lines(diff_dir) l
    ON e.file_path = l.file_path
   AND l.new_line BETWEEN e.line_start AND e.line_end
  WHERE e.side = 'NEW'
    AND l.op = '+'
  QUALIFY row_number() OVER (
    PARTITION BY l.file_path, l.new_line
    ORDER BY (e.line_end - e.line_start) ASC, e.line_start DESC
  ) = 1
)
SELECT
  file_path,
  kind,
  name,
  signature,
  line_start,
  line_end,
  FIRST(chunk_name) AS chunk_name,
  COUNT(*) AS lines_added,
  (line_end - line_start + 1) AS total_entity_lines,
  ROUND(
    COUNT(*) * 100.0 / NULLIF(line_end - line_start + 1, 0),
    1
  ) AS pct_rewritten
FROM innermost_matches
GROUP BY file_path, kind, name, signature, line_start, line_end
ORDER BY lines_added DESC, file_path, line_start;

-- 7. Layer 3: Detect OLD -> NEW signature drift on modified symbols
CREATE OR REPLACE MACRO diff_signature_drift(diff_dir) AS TABLE
SELECT
  n.file_path,
  n.kind,
  n.name,
  o.signature AS old_signature,
  n.signature AS new_signature,
  o.line_start AS old_line_start,
  n.line_start AS new_line_start,
  n.line_end AS new_line_end
FROM staged_diff_entities(diff_dir) o
JOIN staged_diff_entities(diff_dir) n
  ON o.file_path = n.file_path
 AND o.kind = n.kind
 AND o.name = n.name
WHERE o.side = 'OLD'
  AND n.side = 'NEW'
  AND o.signature != n.signature
ORDER BY n.file_path, n.line_start;

-- 8. Layer 3: Find modified production functions/methods not referenced in test diffs
CREATE OR REPLACE MACRO diff_untested_functions(diff_dir) AS TABLE
WITH prod_mods AS (
  SELECT
    file_path,
    kind,
    name,
    signature,
    chunk_name,
    lines_added,
    pct_rewritten
  FROM diff_entity_churn(diff_dir)
  WHERE kind IN ('function', 'method')
    AND NOT regexp_matches(file_path, '(^|/)(test_|.*_test\.|.*\.test\.|.*\.spec\.|tests?/)')
    AND NOT starts_with(name, '_')
),
test_mentions AS (
  SELECT DISTINCT content
  FROM staged_diff_lines(diff_dir)
  WHERE op IN ('+', ' ')
    AND regexp_matches(file_path, '(^|/)(test_|.*_test\.|.*\.test\.|.*\.spec\.|tests?/)')
)
SELECT
  p.file_path,
  p.kind,
  p.name,
  p.signature,
  p.chunk_name,
  p.lines_added,
  p.pct_rewritten
FROM prod_mods p
WHERE NOT EXISTS (
  SELECT 1
  FROM test_mentions t
  WHERE contains(t.content, p.name)
)
ORDER BY p.lines_added DESC, p.file_path;
