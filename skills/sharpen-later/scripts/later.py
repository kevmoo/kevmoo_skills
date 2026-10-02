#!/usr/bin/env python3
"""Append one friction bookmark to the sharpen-saw ledger.

Deliberately knows nothing about transcript formats: it records the session
id and a timestamp, and `sharpen_saw.py view <id>` uses those to find the
surrounding steps later. The ledger line format is the only contract shared
with the sharpen-saw skill.
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

CATEGORIES = (
    "cli-gap",
    "rule-violation",
    "skill-gap",
    "hook-gap",
    "tool-bug",
    "ui-glitch",
    "perf",
    "review-escape",
    "other",
)


def default_ledger():
    state = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(state) / "sharpen-saw" / "later.jsonl"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("note", help="what went wrong, in the user's words")
    parser.add_argument("--agent-note", default="", help="failing command, tool or rule")
    parser.add_argument("--cat", default="other", choices=CATEGORIES)
    parser.add_argument(
        "--session",
        default=os.environ.get("CLAUDE_CODE_SESSION_ID", ""),
        help="session id (default: $CLAUDE_CODE_SESSION_ID)",
    )
    parser.add_argument("--later-file", type=Path, default=default_ledger())
    args = parser.parse_args(argv)
    note = " ".join(args.note.split())
    if not note:
        parser.error("the note is empty")
    # A terminal that cannot encode the receipt must not fail a write that succeeded.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    ledger = args.later_file
    ledger.parent.mkdir(parents=True, exist_ok=True)
    count = len(ledger.read_text(encoding="utf-8").splitlines()) if ledger.exists() else 0
    session = args.session.strip() or "unknown"
    if session == "unknown":
        print("No session id: pass --session so the bookmark can be traced.", file=sys.stderr)
    entry = {
        "id": f"L-{re.sub(r'[^A-Za-z0-9]', '', session)[:8]}-{count + 1}",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "session": session,
        "cwd": os.getcwd(),
        "category": args.cat,
        "human_note": note,
        "agent_note": " ".join(args.agent_note.split()),
        "status": "OPEN",
    }
    # A single O_APPEND write, so concurrent bookmarks never overwrite each other.
    with ledger.open("a", encoding="utf-8") as out:
        out.write(json.dumps(entry, ensure_ascii=False) + "\n")

    print(
        f"📌 Logged for /sharpen-saw ([{entry['id']}] {entry['category']}): {entry['human_note']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
