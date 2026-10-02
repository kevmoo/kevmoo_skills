"""Unit tests for the sharpen-saw and sharpen-later skill scripts.

Run directly (`python3 tool/test/sharpen_test.py`) or through `dart test`,
which shells out to this file from `sharpen_python_test.dart`.
"""

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SKILLS = Path(__file__).resolve().parents[2] / "skills"


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


saw = _load("sharpen_saw", SKILLS / "sharpen-saw" / "scripts" / "sharpen_saw.py")
later = _load("later", SKILLS / "sharpen-later" / "scripts" / "later.py")

SID = "aaaaaaaa-1111-2222-3333-444444444444"


def user(content, ts="2026-10-01T10:00:00.000Z", **extra):
    return {
        "type": "user",
        "timestamp": ts,
        "cwd": "/repo",
        "message": {"content": content},
        **extra,
    }


def tool_use(use_id, name, tool_input, ts="2026-10-01T10:00:01.000Z"):
    block = {"type": "tool_use", "id": use_id, "name": name, "input": tool_input}
    return {"type": "assistant", "timestamp": ts, "cwd": "/repo", "message": {"content": [block]}}


def tool_result(use_id, content, is_error=False, **extra):
    block = {"type": "tool_result", "tool_use_id": use_id, "content": content, "is_error": is_error}
    return user([block], **extra)


def bash(use_id, command, output="ok", is_error=False, ts="2026-10-01T10:00:01.000Z"):
    return [
        tool_use(use_id, "Bash", {"command": command}, ts),
        tool_result(use_id, output, is_error),
    ]


class SharpenTestCase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.projects = self.root / "projects"
        self.ledger = self.root / "state" / "later.jsonl"
        # Keeps the budget and installed-skill lookups off the real home directory.
        config = str(self.root / ".claude")
        home = mock.patch.dict(os.environ, {"HOME": str(self.root), "CLAUDE_CONFIG_DIR": config})
        home.start()
        self.addCleanup(home.stop)

    def write_session(self, records, sid=SID, age=0):
        """Writes a transcript last modified `age` seconds ago."""
        path = self.projects / "-repo" / f"{sid}.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")
        modified = path.stat().st_mtime - age
        os.utime(path, (modified, modified))
        return path

    def run_saw(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            saw.main(
                [*argv, "--projects-dir", str(self.projects), "--later-file", str(self.ledger)]
            )
        return out.getvalue()


class ReaderTest(SharpenTestCase):
    def test_normalizes_prompts_tools_and_titles(self):
        path = self.write_session(
            [
                {"type": "attachment", "isSidechain": False},
                user("<command-name>/clear</command-name>\n<command-args></command-args>"),
                user("<system-reminder>noise</system-reminder>fix the build"),
                user("skill body", isMeta=True),
                user(
                    "<command-message>relay</command-message>\n"
                    "<command-name>/relay</command-name>\n<command-args>check</command-args>"
                ),
                {
                    "type": "assistant",
                    "message": {"content": [{"type": "thinking", "thinking": "hm"}]},
                },
                {"type": "assistant", "message": {"content": [{"type": "text", "text": "On it."}]}},
                *bash("t1", "dart test", "Exit code 1\nError: boom", is_error=True),
                tool_use("t2", "Bash", {"command": "git push"}),
                tool_result(
                    "t2", "The user doesn't want to proceed", True, toolDenialKind="user-rejected"
                ),
                tool_use("t3", "Read", {"file_path": "/repo/a.dart"}),
                tool_result("t3", [{"type": "text", "text": "contents"}]),
                {"type": "ai-title", "aiTitle": "Fix build"},
                {"type": "custom-title", "customTitle": "My title"},
                "not a record",
            ]
        )
        session = saw.read_session(path)

        self.assertEqual(session.sid, SID)
        self.assertEqual(session.title, "My title")
        self.assertEqual(
            [(s.index, s.kind, s.tool) for s in session.steps],
            [
                (1, "prompt", ""),
                (2, "prompt", ""),
                (3, "text", ""),
                (4, "tool", "Bash"),
                (5, "tool", "Bash"),
                (6, "tool", "Read"),
            ],
        )
        self.assertEqual([s.text for s in session.steps[:2]], ["fix the build", "/relay check"])
        failed, denied, read = session.steps[3:]
        self.assertTrue(failed.is_error and not failed.denied)
        self.assertTrue(denied.denied)
        self.assertEqual(
            (read.summary, read.text, read.is_error), ("/repo/a.dart", "contents", False)
        )

    def test_subagent_transcripts_are_opt_in(self):
        self.write_session([user("hi")])
        sub = self.projects / "-repo" / SID / "subagents" / "agent-1.jsonl"
        sub.parent.mkdir(parents=True)
        sub.write_text(json.dumps(user("sub task", isSidechain=True)) + "\n")

        self.assertEqual(len(saw.session_files(self.projects)), 1)
        self.assertEqual(len(saw.session_files(self.projects, include_subagents=True)), 2)
        self.assertEqual(saw.read_session(sub).sid, f"{SID}/agent-1")
        self.assertEqual(saw.find_session(self.projects, SID[:8]).name, f"{SID}.jsonl")
        self.assertEqual(saw.find_session(self.projects, f"{SID}/agent"), sub)
        self.assertEqual(len(saw.read_session(sub).steps), 1)


class CommandKeyTest(unittest.TestCase):
    def test_extracts_subcommand_past_wrappers(self):
        cases = {
            "cd ~/x && PAGER=cat timeout -k 5s 30s gh pr view 12 --json url": "gh pr view",
            "git worktree add -b x ../y origin/main": "git worktree add",
            "git -C /x status": "git status",
            "git --git-dir=/x/.git diff": "git diff",
            "env FOO=1 gh pr view 3": "gh pr view",
            'echo "step 1; git push origin main"': None,
            "git checkout main": "git checkout",
            'echo "---"; command cat foo | head': "cat",
            "~/.local/bin/relay-whoami --check": "relay-whoami",
            "python3 - << 'PY'\nimport json\nPY": "python3",
            "python3 tool/run.py --fast": "python3 run.py",
            "bash << 'EOF'\nF=(a/b.dart c/d.dart)\nfor f in $F; do dart run $f; done\nEOF": (
                "dart run"
            ),
            'F="a b c"; ls $F': "ls",
            "time dart test": "dart test",
            "bash -n script.sh": None,
            "cd /tmp": None,
            "": None,
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(saw.command_key(command), expected)

    def test_lists_every_command_of_a_chain(self):
        cases = {
            "ls lib && echo '=== x; y ===' && grep -rn Foo lib/": ["ls", "grep"],
            "python3 - << 'PY'\nimport json\nx = 'a; b'\nPY\necho done; jq . f": ["python3", "jq"],
            'cat <<< "x" && wc -l f': ["cat", "wc"],
            "git fetch -q; git fetch origin": ["git fetch"],
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(saw.command_keys(command), expected)


class BlameTest(unittest.TestCase):
    def test_names_the_failing_part_of_a_chain(self):
        cases = [
            (["gh pr view"], "anything", "gh pr view"),
            (["relay-gh issue", "gh pr view"], "ok\n(eval):1: === not found", "shell"),
            (["ls"], "(eval):1: no matches found: results/*.md", "shell"),
            (["grep", "sed"], "sed: -e expression #1, char 5: unknown command", "sed"),
            (["git fetch", "ls"], "fatal: 'main' is already used by worktree", "git fetch"),
            (["git fetch", "git checkout"], "fatal: ambiguous", "chain"),
            (["ls", "grep"], "a.dart\nb.dart", "chain"),
            ([], "boom", None),
        ]
        for keys, error, expected in cases:
            with self.subTest(keys=keys, error=error):
                self.assertEqual(saw.blame(keys, error), expected)


class ErrorSignatureTest(unittest.TestCase):
    def test_masks_paths_and_numbers(self):
        raw = "Exit code 1\nrunning...\nopen /tmp/a/b.md: no such file or directory (os error 2)"
        self.assertEqual(
            saw.error_signature(raw), "open PATH no such file or directory (os error N)"
        )
        self.assertEqual(
            saw.error_example(raw), "open /tmp/a/b.md: no such file or directory (os error 2)"
        )

    def test_python_exception_names_count_as_errors(self):
        raw = "Exit code 1\nTraceback (most recent call last):\nIndexError: list index out of range"
        self.assertEqual(saw.error_signature(raw), "IndexError: list index out of range")

    def test_failed_command_with_only_stdout_reports_its_exit_code(self):
        raw = "Exit code 2\nsdk.dart\nterminal.dart"
        self.assertEqual(saw.error_signature(raw), "Exit code 2")
        self.assertEqual(saw.error_example(raw), "Exit code 2")

    def test_shell_errors_count_as_error_lines(self):
        raw = "Exit code 1\nheader\n(eval):1: no matches found: results/*.md"
        self.assertEqual(saw.error_signature(raw), "(eval):N: no matches found: PATH")

    def test_separator_runs_of_any_length_cluster_together(self):
        self.assertEqual(
            saw.error_signature("Exit code 1\n(eval):1: ===== not found"),
            saw.error_signature("Exit code 1\n(eval):1: ==== not found"),
        )

    def test_tool_errors_keep_their_message(self):
        raw = "<tool_use_error>File has not been read yet.</tool_use_error>"
        self.assertEqual(saw.error_signature(raw), "File has not been read yet.")


class AuditTest(SharpenTestCase):
    def test_aggregates_friction_signals(self):
        edits = [
            record
            for i in range(4)
            for record in (
                tool_use(f"e{i}", "Edit", {"file_path": "/repo/lib/a.dart"}),
                tool_result(f"e{i}", "updated"),
            )
        ]
        first = self.write_session(
            [
                user("ship it"),
                *bash(
                    "a1",
                    "gh pr view 1 --json link",
                    'Exit code 1\nUnknown JSON field: "link"',
                    True,
                ),
                *bash("a2", "gh pr view 1 --json url"),
                *bash("a3", "PAGER=cat gh pr view 2"),
                tool_use("s1", "Skill", {"skill": "relay"}),
                tool_result("s1", "x" * 12_000),
                *edits,
                tool_use("d1", "Bash", {"command": "git push"}),
                tool_result("d1", "denied", True, toolDenialKind="permission-rule"),
            ]
        )
        second = self.write_session(
            bash("b1", "gh pr view 9 --json link", 'Exit code 1\nUnknown JSON field: "link"', True),
            sid="bbbbbbbb-1111-2222-3333-444444444444",
        )
        sessions = [saw.read_session(first), saw.read_session(second)]
        report = saw.audit(sessions, skills={"relay", "duckdb"})

        self.assertEqual(report["tool_counts"], {"Bash": 5, "Edit": 4, "Skill": 1})
        self.assertEqual(report["runs"]["Bash (gh pr view)"][0], 1)
        self.assertEqual(report["runs"]["Edit"][0], 1)
        self.assertEqual(report["commands"]["gh pr view"]["total"], 4)
        self.assertEqual(report["commands"]["git push"]["total"], 1)
        self.assertEqual(report["var_prefixed"], {"gh pr view": 1})
        self.assertEqual([hog[2:4] for hog in report["hogs"]], [(5, "Skill")])
        self.assertEqual(report["spirals"], {"/repo/lib/a.dart": {SID: 4}})
        self.assertEqual(report["activated"], {"relay": 1})
        self.assertEqual(report["dormant"], ["duckdb"])
        self.assertEqual(report["denials"], {"Bash (git push)": 1})
        self.assertEqual(report["errors"], 2)
        self.assertEqual(report["prompts"], {SID: ["ship it"]})

        (cluster,) = report["clusters"]
        self.assertEqual((cluster["count"], len(cluster["sessions"])), (2, 2))
        self.assertEqual(cluster["signature"], 'Unknown JSON field: "link"')
        self.assertEqual(cluster["command"], "gh pr view 1 --json link")
        self.assertEqual(cluster["siblings"], ["gh pr view 1 --json url", "PAGER=cat gh pr view 2"])

        text = saw.format_audit(report)
        self.assertIn("Succeeding Sibling: gh pr view 1 --json url", text)
        self.assertIn("[2x across 2 session(s)] Bash (gh pr view)", text)

    def test_reading_an_installed_skill_file_counts_as_activation(self):
        path = self.write_session(
            [
                tool_use("r1", "Read", {"file_path": "/home/u/.agents/skills/duckdb/SKILL.md"}),
                tool_result("r1", "..."),
                tool_use("r2", "Read", {"file_path": "/repo/skills/relay/SKILL.md"}),
                tool_result("r2", "..."),
            ]
        )
        report = saw.audit([saw.read_session(path)], skills={"relay", "duckdb"})
        self.assertEqual(report["activated"], {"duckdb": 1})
        self.assertEqual(report["dormant"], ["relay"])

    def test_interpreter_failures_get_no_sibling_contrast(self):
        path = self.write_session(
            [
                *bash("p1", "python3 - << 'PY'\nboom\nPY", "Exit code 1\nNameError: boom", True),
                *bash("p2", "python3 - << 'PY'\nprint(1)\nPY"),
            ]
        )
        (cluster,) = saw.audit([saw.read_session(path)])["clusters"]
        self.assertEqual(cluster["siblings"], [])

    def test_chain_failures_are_blamed_on_the_command_that_failed(self):
        path = self.write_session(
            [
                *bash(
                    "c1",
                    "grep -n x f && sed -n '1,+3q' f",
                    "Exit code 1\nsed: unknown command",
                    True,
                ),
                *bash("c2", "sed -n 1,3p f"),
                *bash(
                    "c3",
                    "gh pr view 1; echo ====; ls",
                    "Exit code 1\n(eval):1: === not found",
                    True,
                ),
                *bash("c4", "ls lib && grep -c x lib/a", "Exit code 1\n0", True),
            ]
        )
        clusters = {c["key"]: c for c in saw.audit([saw.read_session(path)])["clusters"]}

        self.assertEqual(set(clusters), {"sed", "shell", "chain"})
        self.assertEqual(clusters["sed"]["siblings"], ["sed -n 1,3p f"])
        self.assertEqual(clusters["shell"]["siblings"], [])
        self.assertEqual(clusters["chain"]["signature"], "Exit code 1")


class LedgerAndCliTest(SharpenTestCase):
    def log(self, note, session=SID):
        out = io.StringIO()
        argv = [note, "--cat", "cli-gap", "--session", session, "--later-file", str(self.ledger)]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            later.main(argv)
        return out.getvalue()

    def test_later_appends_and_resolve_closes(self):
        receipt = self.log("gh pr checks hung")
        self.assertEqual(
            receipt, "📌 Logged for /sharpen-saw ([L-aaaaaaaa-1] cli-gap): gh pr checks hung\n"
        )
        self.log("second", session="")

        entries = saw.open_entries(self.ledger)
        self.assertEqual([e["id"] for e in entries], ["L-aaaaaaaa-1", "L-unknown-2"])
        self.assertEqual(saw.resolve_entries(self.ledger, ""), 0)
        with self.assertRaises(SystemExit):
            self.run_saw("resolve", "L-nope-9")
        self.assertIn("2 open item(s)", self.run_saw("queue"))

        self.assertIn("Resolved 1", self.run_saw("resolve", "L-aaaaaaaa-1"))
        self.assertEqual([e["id"] for e in saw.open_entries(self.ledger)], ["L-unknown-2"])
        self.assertEqual(saw.load_ledger(self.ledger)[0]["status"], "RESOLVED")
        self.assertIn("Resolved 1", self.run_saw("resolve", "all"))
        self.assertIn("No open", self.run_saw("queue"))

    def test_resolve_keeps_ledger_lines_it_cannot_parse(self):
        self.log("first")
        with self.ledger.open("a", encoding="utf-8") as out:
            out.write('{"truncated": \n')
        self.log("third")

        self.run_saw("resolve", "L-aaaaaaaa-1")
        lines = self.ledger.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[1], '{"truncated": ')
        self.assertEqual([e["id"] for e in saw.open_entries(self.ledger)], ["L-aaaaaaaa-3"])

    def test_later_normalizes_notes_and_ids(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            later.main(["two\nlines", "--session", "foo.bar/baz", "--later-file", str(self.ledger)])
        (entry,) = saw.open_entries(self.ledger)
        self.assertEqual((entry["id"], entry["human_note"]), ("L-foobarba-1", "two lines"))
        self.assertTrue(saw.BOOKMARK_RE.match(entry["id"]))
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            later.main(["  ", "--later-file", str(self.ledger)])

    def test_view_bookmark_windows_around_its_timestamp(self):
        records = [user("start", ts="2020-01-01T00:00:00.000Z")]
        for i in range(1, 9):
            records += bash(f"c{i}", f"make step{i}", ts=f"2020-01-01T00:00:{i:02d}.000Z")
        records += bash("late", "make after", ts="2999-01-01T00:00:00.000Z")
        self.write_session(records)
        self.log("make is flaky")

        out = self.run_saw("view", "L-aaaaaaaa-1", "--window", "2")
        self.assertTrue(out.startswith("📌 [L-aaaaaaaa-1] cli-gap: make is flaky\n"))
        self.assertNotIn("step5", out)
        self.assertIn("$ make step7", out)
        self.assertLess(out.index("$ make step8"), out.index("bookmarked here"))
        self.assertLess(out.index("bookmarked here"), out.index("$ make after"))

    def test_view_defaults_to_conversation_and_filters_errors(self):
        self.write_session(
            [user("hello"), *bash("x1", "ls"), *bash("x2", "false", "Exit code 1", True)]
        )
        self.assertNotIn("tool Bash", self.run_saw("view", SID[:8]))
        errors = self.run_saw("view", SID[:8], "--errors")
        self.assertIn("=== [3] tool Bash [ERROR]", errors)
        self.assertNotIn("$ ls", errors)
        self.assertIn("$ ls", self.run_saw("view", SID[:8], "--step", "2"))
        with self.assertRaises(SystemExit) as bad_step:
            self.run_saw("view", SID[:8], "--step", "abc")
        self.assertEqual(bad_step.exception.code, "--step takes N or A-B")

    def test_scan_ranks_by_query_and_errors(self):
        failed = bash("g1", "git rebase main", "Exit code 1\nfatal: conflict", True)
        self.write_session([user("rebase please"), *failed])
        self.write_session([user("unrelated")], sid="cccccccc-1111-2222-3333-444444444444")

        out = self.run_saw("scan", "--query", "rebase")
        self.assertIn("Found 1 candidate session(s)", out)
        self.assertIn("[aaaaaaaa] score 3 (errors 1, >15KB steps 0, query matches 2)", out)
        self.assertIn("Bash (git rebase): fatal: conflict", out)

    def test_audit_includes_sessions_with_open_bookmarks(self):
        self.write_session([user("old work"), *bash("o1", "ls")], age=60)
        self.write_session([user("new work")], sid="dddddddd-1111-2222-3333-444444444444")
        self.log("revisit")

        out = self.run_saw("audit", "--last", "1")
        self.assertIn("Audit of 2 session(s)", out)
        self.assertIn("/sharpen-later queue: 1 open", out)

    def test_audit_last_counts_a_recent_bookmarked_session_once(self):
        self.write_session([user("bookmarked and newest")])
        self.write_session([user("older")], sid="dddddddd-1111-2222-3333-444444444444", age=60)
        self.write_session([user("oldest")], sid="eeeeeeee-1111-2222-3333-444444444444", age=120)
        self.log("revisit")

        self.assertIn("Audit of 1 session(s)", self.run_saw("audit", "--last", "1"))
        out = self.run_saw("audit", "--last", "2")
        self.assertIn("Audit of 2 session(s)", out)
        self.assertNotIn("eeeeeeee", out)


if __name__ == "__main__":
    unittest.main()
