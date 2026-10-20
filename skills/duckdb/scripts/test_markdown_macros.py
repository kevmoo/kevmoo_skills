#!/usr/bin/env python3
"""Unit tests for skills/duckdb/scripts/markdown_macros.sql."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

SCRIPTS_DIR = Path(__file__).resolve().parent
MACROS_SQL = SCRIPTS_DIR / "markdown_macros.sql"


def _find_duckdb() -> str | None:
    """Finds the duckdb CLI executable on PATH or in ~/.local/bin."""
    found = shutil.which("duckdb")
    if found:
        return found
    candidate = Path.home() / ".local/bin/duckdb"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


DUCKDB_BIN = _find_duckdb()


@unittest.skipUnless(DUCKDB_BIN, "duckdb CLI binary not found")
class TestMarkdownMacros(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir)

    def _query(self, sql: str) -> list[dict[str, Any]]:
        """Executes a SQL query with markdown_macros.sql initialized and returns JSON rows."""
        res = subprocess.run(
            [
                str(DUCKDB_BIN),
                "-batch",
                "-no-stdin",
                "-dark-mode",
                "-json",
                "-init",
                str(MACROS_SQL),
                "-c",
                sql,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        out = res.stdout.strip()
        return json.loads(out) if out else []

    def test_section_hierarchy_breadcrumbs_and_subtree_spans(self) -> None:
        md_content = (
            "---\n"
            "name: sample-doc\n"
            "# frontmatter comment that must not become a heading\n"
            "---\n"
            "Preamble intro line.\n"
            "# Title H1\n"
            "Intro under H1.\n"
            "## First H2\n"
            "Body under first H2.\n"
            "### Nested H3 ###\n"
            "Deep body line 1.\n"
            "Deep body line 2.\n"
            "## Second H2\n"
            "Body under second H2 (H3 must reset in breadcrumb).\n"
        )
        doc_path = Path(self.test_dir) / "doc.md"
        doc_path.write_text(md_content, encoding="utf-8")

        sections = self._query(
            f"SELECT section_id, level, heading, breadcrumb, line_start, line_end, "
            f"subtree_line_end, own_lines, subtree_lines, own_code_blocks "
            f"FROM read_md_sections('{doc_path}');"
        )
        self.assertEqual(
            sections,
            [
                {
                    "section_id": 0,
                    "level": 0,
                    "heading": "(preamble)",
                    "breadcrumb": "(preamble)",
                    "line_start": 5,
                    "line_end": 5,
                    "subtree_line_end": 5,
                    "own_lines": 1,
                    "subtree_lines": 1,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 1,
                    "level": 1,
                    "heading": "Title H1",
                    "breadcrumb": "Title H1",
                    "line_start": 6,
                    "line_end": 7,
                    "subtree_line_end": 14,
                    "own_lines": 2,
                    "subtree_lines": 9,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 2,
                    "level": 2,
                    "heading": "First H2",
                    "breadcrumb": "Title H1 > First H2",
                    "line_start": 8,
                    "line_end": 9,
                    "subtree_line_end": 12,
                    "own_lines": 2,
                    "subtree_lines": 5,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 3,
                    "level": 3,
                    "heading": "Nested H3",
                    "breadcrumb": "Title H1 > First H2 > Nested H3",
                    "line_start": 10,
                    "line_end": 12,
                    "subtree_line_end": 12,
                    "own_lines": 3,
                    "subtree_lines": 3,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 4,
                    "level": 2,
                    "heading": "Second H2",
                    "breadcrumb": "Title H1 > Second H2",
                    "line_start": 13,
                    "line_end": 14,
                    "subtree_line_end": 14,
                    "own_lines": 2,
                    "subtree_lines": 2,
                    "own_code_blocks": 0,
                },
            ],
        )

    def test_nested_fences_and_code_block_extraction(self) -> None:
        md_content = (
            "# Guide\n"
            "```bash\n"
            "# shell comment inside 3-backtick block\n"
            "echo hello\n"
            "```\n"
            "## Templates\n"
            "````markdown\n"
            "# Fake Heading Inside 4-Backtick Block\n"
            "```python\n"
            "# nested python comment\n"
            "```\n"
            "````\n"
            "~~~sql\n"
            "# sql hash comment inside tilde block\n"
            "SELECT 1;\n"
            "~~~\n"
            "- List item with 4-space indented fence:\n"
            "    ```bash\n"
            "    # indented shell comment\n"
            "    echo list\n"
            "    ```\n"
            "`````markdown\n"
            "# Fake Heading Inside 5-Backtick Block\n"
            "````markdown\n"
            "# Nested 4-Backtick Heading\n"
            "````\n"
            "`````\n"
        )
        doc_path = Path(self.test_dir) / "fences.md"
        doc_path.write_text(md_content, encoding="utf-8")

        sections = self._query(
            f"SELECT section_id, level, heading, own_code_blocks "
            f"FROM read_md_sections('{doc_path}');"
        )
        self.assertEqual(
            sections,
            [
                {
                    "section_id": 1,
                    "level": 1,
                    "heading": "Guide",
                    "own_code_blocks": 1,
                },
                {
                    "section_id": 2,
                    "level": 2,
                    "heading": "Templates",
                    "own_code_blocks": 4,
                },
            ],
        )

        blocks = self._query(
            f"SELECT block_id, section_id, section_heading, lang, "
            f"line_start, line_end, code_lines, code "
            f"FROM read_md_code_blocks('{doc_path}');"
        )
        self.assertEqual(
            blocks,
            [
                {
                    "block_id": 1,
                    "section_id": 1,
                    "section_heading": "Guide",
                    "lang": "bash",
                    "line_start": 2,
                    "line_end": 5,
                    "code_lines": 2,
                    "code": "# shell comment inside 3-backtick block\necho hello",
                },
                {
                    "block_id": 2,
                    "section_id": 2,
                    "section_heading": "Templates",
                    "lang": "markdown",
                    "line_start": 7,
                    "line_end": 12,
                    "code_lines": 4,
                    "code": (
                        "# Fake Heading Inside 4-Backtick Block\n"
                        "```python\n"
                        "# nested python comment\n"
                        "```"
                    ),
                },
                {
                    "block_id": 3,
                    "section_id": 2,
                    "section_heading": "Templates",
                    "lang": "sql",
                    "line_start": 13,
                    "line_end": 16,
                    "code_lines": 2,
                    "code": "# sql hash comment inside tilde block\nSELECT 1;",
                },
                {
                    "block_id": 4,
                    "section_id": 2,
                    "section_heading": "Templates",
                    "lang": "bash",
                    "line_start": 18,
                    "line_end": 21,
                    "code_lines": 2,
                    "code": "    # indented shell comment\n    echo list",
                },
                {
                    "block_id": 5,
                    "section_id": 2,
                    "section_heading": "Templates",
                    "lang": "markdown",
                    "line_start": 22,
                    "line_end": 27,
                    "code_lines": 4,
                    "code": (
                        "# Fake Heading Inside 5-Backtick Block\n"
                        "````markdown\n"
                        "# Nested 4-Backtick Heading\n"
                        "````"
                    ),
                },
            ],
        )

    def test_tilde_inside_backtick_and_closing_fence_with_trailing_text(
        self,
    ) -> None:
        doc = Path(self.test_dir) / "edge_fences.md"
        doc.write_text(
            "\ufeff# Section 1\n"
            "```\n"
            "```nested_info_inside_bare_fence\n"
            "# comment inside initial bare fence\n"
            "```\n"
            "```rst\n"
            "Title\n"
            "~~~\n"
            "```\n"
            "# Section 2\n"
            "```python\n"
            "print(1)\n"
            "```trailing_text\n"
            "# comment inside fence\n"
            "```\n"
            "# Section 3\n",
            encoding="utf-8",
        )
        sections = self._query(
            f"SELECT section_id, heading, own_code_blocks FROM read_md_sections('{doc}');"
        )
        self.assertEqual(
            sections,
            [
                {"section_id": 1, "heading": "Section 1", "own_code_blocks": 2},
                {"section_id": 2, "heading": "Section 2", "own_code_blocks": 1},
                {"section_id": 3, "heading": "Section 3", "own_code_blocks": 0},
            ],
        )

        blocks = self._query(
            f"SELECT block_id, section_id, lang, line_start, line_end, code "
            f"FROM read_md_code_blocks('{doc}');"
        )
        self.assertEqual(
            blocks,
            [
                {
                    "block_id": 1,
                    "section_id": 1,
                    "lang": "",
                    "line_start": 2,
                    "line_end": 5,
                    "code": (
                        "```nested_info_inside_bare_fence\n# comment inside initial bare fence"
                    ),
                },
                {
                    "block_id": 2,
                    "section_id": 1,
                    "lang": "rst",
                    "line_start": 6,
                    "line_end": 9,
                    "code": "Title\n~~~",
                },
                {
                    "block_id": 3,
                    "section_id": 2,
                    "lang": "python",
                    "line_start": 11,
                    "line_end": 15,
                    "code": "print(1)\n```trailing_text\n# comment inside fence",
                },
            ],
        )

    def test_tilde_block_wrapping_backtick_fences_and_trailing_text_in_t3_f4(
        self,
    ) -> None:
        # H1: 3-backtick fence closed by 4-backtick fence, and 4-tilde RST underline inside
        doc_h1_rst = Path(self.test_dir) / "h1_rst_f4_close.md"
        doc_h1_rst.write_text(
            "# Section 1\n```rst\nTest\n~~~~\n````\n# Section 2\n",
            encoding="utf-8",
        )
        self.assertEqual(
            [
                s["heading"]
                for s in self._query(f"SELECT heading FROM read_md_sections('{doc_h1_rst}');")
            ],
            ["Section 1", "Section 2"],
        )
        self.assertEqual(
            self._query(
                f"SELECT block_id, lang, line_start, line_end, code "
                f"FROM read_md_code_blocks('{doc_h1_rst}');"
            ),
            [
                {
                    "block_id": 1,
                    "lang": "rst",
                    "line_start": 2,
                    "line_end": 5,
                    "code": "Test\n~~~~",
                }
            ],
        )

        # H3: Tilde fence wrapping an unpaired ``` line and a paired ```python ... ``` block
        doc_unclosed = Path(self.test_dir) / "h3_unclosed.md"
        doc_unclosed.write_text(
            "# Before\n~~~text\n```\n~~~\n# After\n## Later\n",
            encoding="utf-8",
        )
        sections = self._query(f"SELECT heading FROM read_md_sections('{doc_unclosed}');")
        self.assertEqual([s["heading"] for s in sections], ["Before", "After", "Later"])

        doc_closed = Path(self.test_dir) / "h3_closed.md"
        doc_closed.write_text(
            "# Before\n~~~markdown\n```python\n# comment\n```\n~~~\n# After\n",
            encoding="utf-8",
        )
        blocks = self._query(
            f"SELECT block_id, lang, line_start, line_end, code "
            f"FROM read_md_code_blocks('{doc_closed}');"
        )
        self.assertEqual(
            blocks,
            [
                {
                    "block_id": 1,
                    "lang": "markdown",
                    "line_start": 2,
                    "line_end": 6,
                    "code": "```python\n# comment\n```",
                }
            ],
        )

        # H2: Tilde, 4-backtick, and 5-backtick fences with trailing text on inner lines
        doc_h2 = Path(self.test_dir) / "h2_fences.md"
        doc_h2.write_text(
            "# Section 1\n"
            "~~~markdown\n~~~sql\n# Fake Heading\n~~~\n"
            "# Section 2\n"
            "````markdown\n````python\n# comment in f4\n````\n"
            "# Section 3\n"
            "`````markdown\n`````python\n# comment in f5\n`````\n"
            "# Section 4\n",
            encoding="utf-8",
        )
        sections_h2 = self._query(f"SELECT heading FROM read_md_sections('{doc_h2}');")
        self.assertEqual(
            [s["heading"] for s in sections_h2],
            ["Section 1", "Section 2", "Section 3", "Section 4"],
        )
        blocks_h2 = self._query(
            f"SELECT block_id, lang, line_start, line_end, code "
            f"FROM read_md_code_blocks('{doc_h2}');"
        )
        self.assertEqual(
            blocks_h2,
            [
                {
                    "block_id": 1,
                    "lang": "markdown",
                    "line_start": 2,
                    "line_end": 5,
                    "code": "~~~sql\n# Fake Heading",
                },
                {
                    "block_id": 2,
                    "lang": "markdown",
                    "line_start": 7,
                    "line_end": 10,
                    "code": "````python\n# comment in f4",
                },
                {
                    "block_id": 3,
                    "lang": "markdown",
                    "line_start": 12,
                    "line_end": 15,
                    "code": "`````python\n# comment in f5",
                },
            ],
        )

        # L1: BOM-only file and lone-\r line endings
        bom_doc = Path(self.test_dir) / "bom_only.md"
        bom_doc.write_text("\ufeff", encoding="utf-8")
        self.assertEqual(self._query(f"SELECT * FROM read_md_sections('{bom_doc}');"), [])

        cr_doc = Path(self.test_dir) / "cr_only.md"
        cr_doc.write_bytes(b"---\rtitle: cr\r---\r# CR Heading\rBody\r")
        self.assertEqual(
            self._query(f"SELECT heading, line_start, line_end FROM read_md_sections('{cr_doc}');"),
            [{"heading": "CR Heading", "line_start": 4, "line_end": 5}],
        )

    def test_multi_file_glob_and_preamble_only_file(self) -> None:
        file_a = Path(self.test_dir) / "a.md"
        file_b = Path(self.test_dir) / "b.md"
        file_c = Path(self.test_dir) / "c_large.md"
        file_a.write_text("Just plain notes without any headings.\nLine two.\n", encoding="utf-8")
        file_b.write_bytes(b"# Doc B\r\nSome CRLF content.\r\n")
        large_lines = [
            "---",
            "title: large-doc",
            "---",
            "# Large Doc",
        ]
        for idx in range(1, 25):
            large_lines.append(f"Intro line {idx}")
        large_lines.append("## Subheading At Line 29")
        for idx in range(1, 25):
            large_lines.append(f"Subheading line {idx}")
        file_c.write_text("\n".join(large_lines) + "\n", encoding="utf-8")

        glob_pat = str(Path(self.test_dir) / "*.md")
        sections = self._query(
            f"SELECT regexp_extract(file_path, '[^/]+$') AS name, "
            f"section_id, level, heading, line_start, line_end, subtree_line_end "
            f"FROM read_md_sections('{glob_pat}') "
            f"ORDER BY name, section_id;"
        )
        self.assertEqual(
            sections,
            [
                {
                    "name": "a.md",
                    "section_id": 0,
                    "level": 0,
                    "heading": "(preamble)",
                    "line_start": 1,
                    "line_end": 2,
                    "subtree_line_end": 2,
                },
                {
                    "name": "b.md",
                    "section_id": 1,
                    "level": 1,
                    "heading": "Doc B",
                    "line_start": 1,
                    "line_end": 2,
                    "subtree_line_end": 2,
                },
                {
                    "name": "c_large.md",
                    "section_id": 1,
                    "level": 1,
                    "heading": "Large Doc",
                    "line_start": 4,
                    "line_end": 28,
                    "subtree_line_end": 53,
                },
                {
                    "name": "c_large.md",
                    "section_id": 2,
                    "level": 2,
                    "heading": "Subheading At Line 29",
                    "line_start": 29,
                    "line_end": 53,
                    "subtree_line_end": 53,
                },
            ],
        )

    def test_deep_heading_levels_dots_frontmatter_and_preamble_code_blocks(
        self,
    ) -> None:
        doc = Path(self.test_dir) / "deep.md"
        doc.write_text(
            "---\n"
            "title: dots-frontmatter\n"
            "...\n"
            "```text\n"
            "preamble block\n"
            "```\n"
            "# L1\n"
            "## L2\n"
            "### L3\n"
            "#### L4a\n"
            "##### L5a\n"
            "###### L6a\n"
            "```\n"
            "```\n"
            "###### L6b\n"
            "##### L5b\n"
            "#### L4b\n",
            encoding="utf-8",
        )
        sections = self._query(
            f"SELECT section_id, level, heading, breadcrumb, line_start, line_end, "
            f"subtree_line_end, own_code_blocks "
            f"FROM read_md_sections('{doc}');"
        )
        self.assertEqual(
            sections,
            [
                {
                    "section_id": 0,
                    "level": 0,
                    "heading": "(preamble)",
                    "breadcrumb": "(preamble)",
                    "line_start": 4,
                    "line_end": 6,
                    "subtree_line_end": 6,
                    "own_code_blocks": 1,
                },
                {
                    "section_id": 1,
                    "level": 1,
                    "heading": "L1",
                    "breadcrumb": "L1",
                    "line_start": 7,
                    "line_end": 7,
                    "subtree_line_end": 17,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 2,
                    "level": 2,
                    "heading": "L2",
                    "breadcrumb": "L1 > L2",
                    "line_start": 8,
                    "line_end": 8,
                    "subtree_line_end": 17,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 3,
                    "level": 3,
                    "heading": "L3",
                    "breadcrumb": "L1 > L2 > L3",
                    "line_start": 9,
                    "line_end": 9,
                    "subtree_line_end": 17,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 4,
                    "level": 4,
                    "heading": "L4a",
                    "breadcrumb": "L1 > L2 > L3 > L4a",
                    "line_start": 10,
                    "line_end": 10,
                    "subtree_line_end": 16,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 5,
                    "level": 5,
                    "heading": "L5a",
                    "breadcrumb": "L1 > L2 > L3 > L4a > L5a",
                    "line_start": 11,
                    "line_end": 11,
                    "subtree_line_end": 15,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 6,
                    "level": 6,
                    "heading": "L6a",
                    "breadcrumb": "L1 > L2 > L3 > L4a > L5a > L6a",
                    "line_start": 12,
                    "line_end": 14,
                    "subtree_line_end": 14,
                    "own_code_blocks": 1,
                },
                {
                    "section_id": 7,
                    "level": 6,
                    "heading": "L6b",
                    "breadcrumb": "L1 > L2 > L3 > L4a > L5a > L6b",
                    "line_start": 15,
                    "line_end": 15,
                    "subtree_line_end": 15,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 8,
                    "level": 5,
                    "heading": "L5b",
                    "breadcrumb": "L1 > L2 > L3 > L4a > L5b",
                    "line_start": 16,
                    "line_end": 16,
                    "subtree_line_end": 16,
                    "own_code_blocks": 0,
                },
                {
                    "section_id": 9,
                    "level": 4,
                    "heading": "L4b",
                    "breadcrumb": "L1 > L2 > L3 > L4b",
                    "line_start": 17,
                    "line_end": 17,
                    "subtree_line_end": 17,
                    "own_code_blocks": 0,
                },
            ],
        )

        blocks = self._query(
            f"SELECT block_id, section_id, section_heading, lang, code_lines, code "
            f"FROM read_md_code_blocks('{doc}');"
        )
        self.assertEqual(
            blocks,
            [
                {
                    "block_id": 1,
                    "section_id": 0,
                    "section_heading": "(preamble)",
                    "lang": "text",
                    "code_lines": 1,
                    "code": "preamble block",
                },
                {
                    "block_id": 2,
                    "section_id": 6,
                    "section_heading": "L6a",
                    "lang": "",
                    "code_lines": 0,
                    "code": "",
                },
            ],
        )

    def test_find_duckdb_fallback_branches(self) -> None:
        fake_home = Path(self.test_dir)
        local_bin = fake_home / ".local/bin"
        local_bin.mkdir(parents=True)
        fake_duckdb = local_bin / "duckdb"

        with (
            patch("shutil.which", return_value=None),
            patch("pathlib.Path.home", return_value=fake_home),
        ):
            self.assertIsNone(_find_duckdb())
            fake_duckdb.write_text("#!/bin/sh\n", encoding="utf-8")
            fake_duckdb.chmod(0o755)
            self.assertEqual(_find_duckdb(), str(fake_duckdb))


if __name__ == "__main__":
    unittest.main()
