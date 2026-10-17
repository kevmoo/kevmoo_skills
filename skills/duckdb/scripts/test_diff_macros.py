#!/usr/bin/env python3
"""Unit tests for skills/duckdb/scripts/diff_macros.sql."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parent
MACROS_SQL = SCRIPTS_DIR / "diff_macros.sql"


def _find_duckdb() -> str | None:
    """Finds the duckdb CLI executable on PATH or in ~/.local/bin."""
    found = shutil.which("duckdb")
    if found:
        return found
    candidate = Path.home() / ".local/bin/duckdb"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    """Writes a list of dicts to a newline-delimited JSON file."""
    path.write_text(
        "".join(json.dumps(row) + "\n" for row in rows),
        encoding="utf-8",
    )


DUCKDB_BIN = _find_duckdb()


@unittest.skipUnless(DUCKDB_BIN, "duckdb CLI binary not found")
class TestDiffMacros(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir)

    def _query(self, sql: str) -> list[dict[str, Any]]:
        """Executes a SQL query with diff_macros.sql initialized and returns JSON rows."""
        res = subprocess.run(
            [
                str(DUCKDB_BIN),
                "-batch",
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

    def test_raw_and_staged_diff_parity(self) -> None:
        diff_content = (
            "diff --git a/src/service.py b/src/service.py\n"
            "index 1111111..2222222 100644\n"
            "--- a/src/service.py\n"
            "+++ b/src/service.py\n"
            "@@ -10,3 +10,4 @@ def process():\n"
            " keep_before\n"
            "-old_call()\n"
            "+new_call()\n"
            "+extra_call()\n"
            " keep_after\n"
            "diff --git a/tests/test_service.py b/tests/test_service.py\n"
            "--- a/tests/test_service.py\n"
            "+++ b/tests/test_service.py\n"
            "@@ -1 +1,2 @@\n"
            " assert True\n"
            "+new_call()\n"
        )
        raw_diff_path = Path(self.test_dir) / "sample.diff"
        raw_diff_path.write_text(diff_content, encoding="utf-8")

        stage_dir = Path(self.test_dir) / "staged"
        stage_dir.mkdir(parents=True)
        _write_jsonl(
            stage_dir / "diff_lines.jsonl",
            [
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": " ",
                    "old_line": 10,
                    "new_line": 10,
                    "content": "keep_before",
                },
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "-",
                    "old_line": 11,
                    "new_line": None,
                    "content": "old_call()",
                },
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "+",
                    "old_line": None,
                    "new_line": 11,
                    "content": "new_call()",
                },
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "+",
                    "old_line": None,
                    "new_line": 12,
                    "content": "extra_call()",
                },
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": " ",
                    "old_line": 12,
                    "new_line": 13,
                    "content": "keep_after",
                },
                {
                    "file_path": "tests/test_service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 2,
                    "func_context": "",
                    "op": " ",
                    "old_line": 1,
                    "new_line": 1,
                    "content": "assert True",
                },
                {
                    "file_path": "tests/test_service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 2,
                    "func_context": "",
                    "op": "+",
                    "old_line": None,
                    "new_line": 2,
                    "content": "new_call()",
                },
            ],
        )
        _write_jsonl(
            stage_dir / "diff_hunks.jsonl",
            [
                {
                    "file_path": "src/service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "old_start": 10,
                    "old_count": 3,
                    "new_start": 10,
                    "new_count": 4,
                    "func_context": "def process():",
                    "added_lines": 2,
                    "deleted_lines": 1,
                },
                {
                    "file_path": "tests/test_service.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 2,
                    "old_start": 1,
                    "old_count": 1,
                    "new_start": 1,
                    "new_count": 2,
                    "func_context": "",
                    "added_lines": 1,
                    "deleted_lines": 0,
                },
            ],
        )
        _write_jsonl(stage_dir / "diff_entities.jsonl", [])

        raw_lines = self._query(
            f"SELECT file_path, hunk_id, func_context, op, old_line, new_line, content "
            f"FROM read_diff_lines('{raw_diff_path}');"
        )
        staged_lines = self._query(
            f"SELECT file_path, hunk_id, func_context, op, old_line, new_line, content "
            f"FROM staged_diff_lines('{stage_dir}');"
        )
        self.assertEqual(raw_lines, staged_lines)

        raw_hunks = self._query(
            f"SELECT file_path, hunk_id, old_start, old_count, new_start, new_count, "
            f"func_context, added_lines, deleted_lines "
            f"FROM read_diff_hunks('{raw_diff_path}');"
        )
        staged_hunks = self._query(
            f"SELECT file_path, hunk_id, old_start, old_count, new_start, new_count, "
            f"func_context, added_lines, deleted_lines "
            f"FROM staged_diff_hunks('{stage_dir}');"
        )
        self.assertEqual(raw_hunks, staged_hunks)

    def test_entity_churn_signature_drift_and_untested_functions(self) -> None:
        stage_dir = Path(self.test_dir) / "staged_entities"
        stage_dir.mkdir(parents=True)
        _write_jsonl(
            stage_dir / "diff_lines.jsonl",
            [
                {
                    "file_path": "src/worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "class Worker:",
                    "op": "+",
                    "old_line": None,
                    "new_line": 2,
                    "content": (
                        "    def tested_method(self, count: int, strict: bool=False) -> bool:"
                    ),
                },
                {
                    "file_path": "src/worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "class Worker:",
                    "op": "+",
                    "old_line": None,
                    "new_line": 3,
                    "content": "        x = count + 1",
                },
                {
                    "file_path": "src/worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "class Worker:",
                    "op": "+",
                    "old_line": None,
                    "new_line": 4,
                    "content": "        return x > 0",
                },
                {
                    "file_path": "src/worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "class Worker:",
                    "op": "+",
                    "old_line": None,
                    "new_line": 7,
                    "content": "        cleaned = label.strip()",
                },
                {
                    "file_path": "src/worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 1,
                    "func_context": "class Worker:",
                    "op": "+",
                    "old_line": None,
                    "new_line": 8,
                    "content": "        return cleaned.upper()",
                },
                {
                    "file_path": "tests/test_worker.py",
                    "chunk_name": "diff_chunk_01.diff",
                    "hunk_id": 2,
                    "func_context": "def test_worker():",
                    "op": "+",
                    "old_line": None,
                    "new_line": 2,
                    "content": "    assert tested_method(1, strict=True)",
                },
            ],
        )
        _write_jsonl(stage_dir / "diff_hunks.jsonl", [])
        _write_jsonl(
            stage_dir / "diff_entities.jsonl",
            [
                {
                    "file_path": "src/worker.py",
                    "side": "NEW",
                    "kind": "class",
                    "name": "Worker",
                    "signature": "class Worker",
                    "line_start": 1,
                    "line_end": 8,
                },
                {
                    "file_path": "src/worker.py",
                    "side": "NEW",
                    "kind": "method",
                    "name": "tested_method",
                    "signature": "def tested_method(self, count: int, strict: bool=False) -> bool",
                    "line_start": 2,
                    "line_end": 4,
                },
                {
                    "file_path": "src/worker.py",
                    "side": "NEW",
                    "kind": "method",
                    "name": "untested_method",
                    "signature": "def untested_method(self, label: str) -> str",
                    "line_start": 6,
                    "line_end": 8,
                },
                {
                    "file_path": "src/worker.py",
                    "side": "OLD",
                    "kind": "method",
                    "name": "tested_method",
                    "signature": "def tested_method(self, count: int) -> bool",
                    "line_start": 2,
                    "line_end": 3,
                },
                {
                    "file_path": "src/worker.py",
                    "side": "OLD",
                    "kind": "method",
                    "name": "untested_method",
                    "signature": "def untested_method(self, label: str) -> str",
                    "line_start": 5,
                    "line_end": 6,
                },
            ],
        )

        churn = self._query(f"SELECT * FROM diff_entity_churn('{stage_dir}');")
        churn_by_name = {r["name"]: r for r in churn}
        self.assertIn("tested_method", churn_by_name)
        self.assertIn("untested_method", churn_by_name)
        self.assertNotIn("Worker", churn_by_name)
        self.assertEqual(churn_by_name["tested_method"]["lines_added"], 3)
        self.assertEqual(churn_by_name["untested_method"]["lines_added"], 2)

        drift = self._query(f"SELECT * FROM diff_signature_drift('{stage_dir}');")
        self.assertEqual(len(drift), 1)
        self.assertEqual(drift[0]["name"], "tested_method")
        self.assertIn("strict: bool=False", drift[0]["new_signature"])

        untested = self._query(f"SELECT * FROM diff_untested_functions('{stage_dir}');")
        self.assertEqual([r["name"] for r in untested], ["untested_method"])

    def test_empty_entities_jsonl_returns_zero_rows_cleanly(self) -> None:
        stage_dir = Path(self.test_dir) / "staged_no_entities"
        stage_dir.mkdir(parents=True)
        _write_jsonl(stage_dir / "diff_lines.jsonl", [])
        _write_jsonl(stage_dir / "diff_hunks.jsonl", [])
        _write_jsonl(stage_dir / "diff_entities.jsonl", [])

        self.assertEqual(self._query(f"SELECT * FROM staged_diff_entities('{stage_dir}');"), [])
        self.assertEqual(self._query(f"SELECT * FROM diff_entity_churn('{stage_dir}');"), [])
        self.assertEqual(self._query(f"SELECT * FROM diff_signature_drift('{stage_dir}');"), [])
        self.assertEqual(self._query(f"SELECT * FROM diff_untested_functions('{stage_dir}');"), [])


if __name__ == "__main__":
    unittest.main()
