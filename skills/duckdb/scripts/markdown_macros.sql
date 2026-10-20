-- Relational Markdown Indexing Macros for DuckDB
-- Load with: duckdb -batch -dark-mode -init skills/duckdb/scripts/markdown_macros.sql

-- Internal helper: Parse raw Markdown lines, strip YAML frontmatter, track
-- CommonMark backtick and tilde code fences, and classify ATX headings.
CREATE OR REPLACE MACRO _parse_markdown(md_glob) AS TABLE
WITH RECURSIVE raw_files AS (
  SELECT
    filename AS file_path,
    regexp_split_to_array(
      regexp_replace(ltrim(content, chr(65279)), '(\r\n|\r|\n)$', ''),
      '\r\n|\r|\n'
    ) AS lines
  FROM read_text(md_glob)
  WHERE ltrim(content, chr(65279)) <> ''
),
raw_lines AS (
  SELECT
    file_path,
    unnest(range(1, len(lines) + 1)) AS line_num,
    unnest(lines) AS line
  FROM raw_files
),
frontmatter_state AS (
  SELECT
    file_path,
    line_num,
    line,
    FIRST_VALUE(line_num = 1 AND line = '---') OVER (
      PARTITION BY file_path ORDER BY line_num
    ) AS has_frontmatter,
    COUNT(*) FILTER (
      WHERE (line_num = 1 AND line = '---')
         OR (line_num > 1 AND line IN ('---', '...'))
    ) OVER (
      PARTITION BY file_path
      ORDER BY line_num
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS fm_delim_count
  FROM raw_lines
),
fm_filtered AS (
  SELECT
    file_path,
    line_num,
    line,
    (
      has_frontmatter
      AND (
        fm_delim_count = 1
        OR (fm_delim_count = 2 AND line IN ('---', '...'))
      )
    ) AS is_frontmatter
  FROM frontmatter_state
),
fence_candidates AS (
  SELECT
    file_path,
    line_num,
    row_number() OVER (PARTITION BY file_path ORDER BY line_num) AS cand_seq,
    left(regexp_extract(line, '^[ \t]*(`{3,}|~{3,})', 1), 1) AS marker_char,
    strlen(regexp_extract(line, '^[ \t]*(`{3,}|~{3,})', 1)) AS marker_len,
    regexp_matches(line, '^[ \t]*(`{3,}|~{3,})[ \t]*$') AS is_bare,
    trim(regexp_extract(line, '^[ \t]*(?:`{3,}|~{3,})[ \t]*([^`~\s]*)', 1)) AS info_lang
  FROM fm_filtered
  WHERE NOT is_frontmatter
    AND regexp_matches(line, '^[ \t]*(`{3,}[^`]*|~{3,}.*)$')
),
fence_walk AS (
  SELECT
    file_path,
    line_num,
    cand_seq,
    true AS is_fence_delim,
    marker_char AS open_char,
    marker_len AS open_len,
    info_lang AS fence_lang
  FROM fence_candidates
  WHERE cand_seq = 1
  UNION ALL
  SELECT
    c.file_path,
    c.line_num,
    c.cand_seq,
    CASE
      WHEN w.open_char IS NULL THEN true
      WHEN c.is_bare AND c.marker_char = w.open_char AND c.marker_len >= w.open_len THEN true
      ELSE false
    END AS is_fence_delim,
    CASE
      WHEN w.open_char IS NULL THEN c.marker_char
      WHEN c.is_bare AND c.marker_char = w.open_char AND c.marker_len >= w.open_len THEN NULL
      ELSE w.open_char
    END AS open_char,
    CASE
      WHEN w.open_char IS NULL THEN c.marker_len
      WHEN c.is_bare AND c.marker_char = w.open_char AND c.marker_len >= w.open_len THEN 0
      ELSE w.open_len
    END AS open_len,
    CASE
      WHEN w.open_char IS NULL THEN c.info_lang
      ELSE NULL
    END AS fence_lang
  FROM fence_walk w
  JOIN fence_candidates c
    ON c.file_path = w.file_path
   AND c.cand_seq = w.cand_seq + 1
),
fence_state AS (
  SELECT
    f.file_path,
    f.line_num,
    f.line,
    f.is_frontmatter,
    COALESCE(w.is_fence_delim, false) AS is_fence_delim,
    w.fence_lang,
    (
      COALESCE(w.is_fence_delim, false)
      OR (
        COUNT(*) FILTER (WHERE COALESCE(w.is_fence_delim, false)) OVER (
          PARTITION BY f.file_path
          ORDER BY f.line_num
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) % 2 = 1
      )
    ) AS in_code_block,
    COUNT(*) FILTER (WHERE COALESCE(w.is_fence_delim, false)) OVER (
      PARTITION BY f.file_path
      ORDER BY f.line_num
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS fence_delim_count
  FROM fm_filtered f
  LEFT JOIN fence_walk w
    ON f.file_path = w.file_path
   AND f.line_num = w.line_num
   AND w.is_fence_delim
),
classified AS (
  SELECT
    file_path,
    line_num,
    line,
    is_frontmatter,
    is_fence_delim,
    in_code_block,
    CASE
      WHEN in_code_block THEN (fence_delim_count + 1) // 2
      ELSE NULL
    END AS code_block_id,
    fence_lang,
    (
      NOT is_frontmatter
      AND NOT in_code_block
      AND regexp_matches(line, '^#{1,6}[ \t]+\S')
    ) AS is_heading,
    CASE
      WHEN NOT is_frontmatter AND NOT in_code_block AND regexp_matches(line, '^#{1,6}[ \t]+\S')
      THEN strlen(regexp_extract(line, '^(#{1,6})[ \t]+', 1))
      ELSE NULL
    END AS heading_level,
    CASE
      WHEN NOT is_frontmatter AND NOT in_code_block AND regexp_matches(line, '^#{1,6}[ \t]+\S')
      THEN trim(regexp_replace(regexp_extract(line, '^#{1,6}[ \t]+(.*)$', 1), '[ \t]+#+[ \t]*$', ''))
      ELSE NULL
    END AS heading_text
  FROM fence_state
)
SELECT
  file_path,
  line_num,
  line,
  is_frontmatter,
  is_fence_delim,
  in_code_block,
  code_block_id,
  fence_lang,
  is_heading,
  heading_level,
  heading_text,
  COUNT(*) FILTER (WHERE is_heading) OVER (
    PARTITION BY file_path
    ORDER BY line_num
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS section_id
FROM classified;

-- 1. Index Markdown sections with hierarchical breadcrumbs and subtree line spans
CREATE OR REPLACE MACRO read_md_sections(md_glob) AS TABLE
WITH parsed AS (
  SELECT * FROM _parse_markdown(md_glob)
),
section_agg AS (
  SELECT
    file_path,
    section_id,
    COALESCE(MAX(heading_level), 0) AS level,
    COALESCE(MAX(heading_text), '(preamble)') AS heading,
    MIN(line_num) AS line_start,
    MAX(line_num) AS line_end,
    (MAX(line_num) - MIN(line_num) + 1) AS own_lines,
    COUNT(DISTINCT code_block_id) AS own_code_blocks,
    string_agg(line, chr(10) ORDER BY line_num) AS content
  FROM parsed
  WHERE NOT is_frontmatter
  GROUP BY file_path, section_id
),
hierarchy AS (
  SELECT
    s.file_path,
    s.section_id,
    s.level,
    s.heading,
    s.line_start,
    s.line_end,
    s.own_lines,
    s.own_code_blocks,
    s.content,
    NULLIF(LAST_VALUE(CASE WHEN s.level = 1 THEN s.heading END IGNORE NULLS) OVER w_upto, '') AS h1,
    NULLIF(LAST_VALUE(CASE WHEN s.level BETWEEN 1 AND 2 THEN CASE WHEN s.level = 2 THEN s.heading ELSE '' END END IGNORE NULLS) OVER w_upto, '') AS h2,
    NULLIF(LAST_VALUE(CASE WHEN s.level BETWEEN 1 AND 3 THEN CASE WHEN s.level = 3 THEN s.heading ELSE '' END END IGNORE NULLS) OVER w_upto, '') AS h3,
    NULLIF(LAST_VALUE(CASE WHEN s.level BETWEEN 1 AND 4 THEN CASE WHEN s.level = 4 THEN s.heading ELSE '' END END IGNORE NULLS) OVER w_upto, '') AS h4,
    NULLIF(LAST_VALUE(CASE WHEN s.level BETWEEN 1 AND 5 THEN CASE WHEN s.level = 5 THEN s.heading ELSE '' END END IGNORE NULLS) OVER w_upto, '') AS h5,
    NULLIF(LAST_VALUE(CASE WHEN s.level BETWEEN 1 AND 6 THEN CASE WHEN s.level = 6 THEN s.heading ELSE '' END END IGNORE NULLS) OVER w_upto, '') AS h6,
    COALESCE(
      CASE s.level
        WHEN 0 THEN s.line_end
        WHEN 1 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 1 THEN s.line_start END) OVER w_after - 1
        WHEN 2 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 2 THEN s.line_start END) OVER w_after - 1
        WHEN 3 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 3 THEN s.line_start END) OVER w_after - 1
        WHEN 4 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 4 THEN s.line_start END) OVER w_after - 1
        WHEN 5 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 5 THEN s.line_start END) OVER w_after - 1
        WHEN 6 THEN MIN(CASE WHEN s.level BETWEEN 1 AND 6 THEN s.line_start END) OVER w_after - 1
      END,
      MAX(s.line_end) OVER (PARTITION BY s.file_path)
    ) AS subtree_line_end
  FROM section_agg s
  WINDOW
    w_upto AS (PARTITION BY s.file_path ORDER BY s.section_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
    w_after AS (PARTITION BY s.file_path ORDER BY s.section_id ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING)
)
SELECT
  file_path,
  section_id,
  level,
  heading,
  CASE
    WHEN level = 0 THEN '(preamble)'
    ELSE concat_ws(' > ', h1, h2, h3, h4, h5, h6)
  END AS breadcrumb,
  line_start,
  line_end,
  subtree_line_end,
  own_lines,
  (subtree_line_end - line_start + 1) AS subtree_lines,
  own_code_blocks,
  content
FROM hierarchy
ORDER BY file_path, section_id;

-- 2. Extract fenced code blocks with language tags, line ranges, and section context
CREATE OR REPLACE MACRO read_md_code_blocks(md_glob) AS TABLE
WITH parsed AS (
  SELECT * FROM _parse_markdown(md_glob)
),
headings AS (
  SELECT
    file_path,
    section_id,
    heading_text AS section_heading
  FROM parsed
  WHERE is_heading
),
blocks AS (
  SELECT
    p.file_path,
    p.code_block_id AS block_id,
    MIN(p.section_id) AS section_id,
    COALESCE(MAX(p.fence_lang), '') AS lang,
    MIN(p.line_num) AS line_start,
    MAX(p.line_num) AS line_end,
    COUNT(*) FILTER (WHERE NOT p.is_fence_delim) AS code_lines,
    COALESCE(
      string_agg(p.line, chr(10) ORDER BY p.line_num) FILTER (WHERE NOT p.is_fence_delim),
      ''
    ) AS code
  FROM parsed p
  WHERE p.in_code_block
  GROUP BY p.file_path, p.code_block_id
)
SELECT
  b.file_path,
  b.block_id,
  b.section_id,
  COALESCE(h.section_heading, '(preamble)') AS section_heading,
  b.lang,
  b.line_start,
  b.line_end,
  b.code_lines,
  b.code
FROM blocks b
LEFT JOIN headings h
  ON b.file_path = h.file_path
 AND b.section_id = h.section_id
ORDER BY b.file_path, b.block_id;
