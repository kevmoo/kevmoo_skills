#!/usr/bin/env python3
"""Mine agent session transcripts offline for recurring friction.

Subcommands: scan, audit, view, queue, resolve. Standard library only, so the
script runs as copied on any machine with Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

RULE_BYTES_CEILING = 21_500
SKILL_LINES_CEILING = 250
CONTEXT_HOG_CHARS = 10_000
EDIT_SPIRAL_MIN = 4
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
RULE = "=" * 72

WS_RE = re.compile(r"\s+")


def squash(text, head=400, tail=400):
    """Collapses whitespace and elides the middle, keeping both ends visible."""
    clean = WS_RE.sub(" ", text).strip()
    if len(clean) <= head + tail:
        return clean
    omitted = len(clean) - head - tail
    return f"{clean[:head]} ... [{omitted} chars omitted] ... {clean[len(clean) - tail:]}"


# --- Claude Code transcript reader -------------------------------------------
# Everything that knows the on-disk format lives in this section. A reader for
# another agent only has to yield the same Session/Step objects.

SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
COMMAND_NAME_RE = re.compile(r"<command-name>(.*?)</command-name>", re.S)
COMMAND_ARGS_RE = re.compile(r"<command-args>(.*?)</command-args>", re.S)
# Skill invocations lead with <command-message>; built-ins such as /clear lead
# with <command-name> and are not tasks.
HARNESS_PREFIXES = (
    "<command-name>",
    "<task-notification>",
    "<local-command-",
    "<bash-",
    "[Request interrupted",
)
DENIED_RE = re.compile(
    r"The user doesn't want to proceed|Permission (?:for|to use) .{0,80}denied", re.S
)


@dataclass
class Step:
    index: int
    kind: str  # "prompt" | "text" | "tool"
    ts: str
    text: str = ""  # the prompt, the assistant text, or the tool result
    tool: str = ""
    input: dict = field(default_factory=dict)
    cwd: str = ""
    is_error: bool = False
    denied: bool = False

    @property
    def summary(self):
        """The one input worth showing for a tool call."""
        for key in ("command", "file_path", "notebook_path", "skill", "pattern", "description"):
            value = self.input.get(key)
            if isinstance(value, str) and value:
                return value
        return next((v for v in self.input.values() if isinstance(v, str) and v), "")


@dataclass
class Session:
    sid: str
    path: Path
    title: str
    steps: list[Step]

    @property
    def short(self):
        return self.sid[:8]


def projects_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "projects"


def session_files(root, include_subagents=False):
    """Session transcripts under `root`, newest first."""
    files = list(root.glob("*/*.jsonl"))
    if include_subagents:
        files += root.glob("*/*/subagents/*.jsonl")
    return sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)


def session_id(path):
    if path.parent.name == "subagents":
        return f"{path.parent.parent.name}/{path.stem}"
    return path.stem


def clean_prompt(text):
    """What the user typed, or "" for harness-injected user records."""
    text = SYSTEM_REMINDER_RE.sub("", text).strip()
    if text.startswith(HARNESS_PREFIXES):
        return ""
    command = COMMAND_NAME_RE.search(text)
    if command and text.startswith("<command-message>"):
        args = COMMAND_ARGS_RE.search(text)
        return f"{command.group(1)} {args.group(1) if args else ''}".strip()
    return text


def result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict))
    return ""


def read_session(path):
    is_subagent = path.parent.name == "subagents"
    steps, pending = [], {}
    ai_title = custom_title = ""
    with path.open(encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            kind = rec.get("type")
            if kind == "custom-title":
                custom_title = rec.get("customTitle") or custom_title
            elif kind == "ai-title":
                ai_title = rec.get("aiTitle") or ai_title
            if kind not in ("user", "assistant"):
                continue
            if rec.get("isMeta") or rec.get("isCompactSummary") or rec.get("isApiErrorMessage"):
                continue
            if rec.get("isSidechain") and not is_subagent:
                continue
            message = rec.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            blocks = [{"type": "text", "text": content}] if isinstance(content, str) else content
            ts, cwd = rec.get("timestamp", ""), rec.get("cwd", "")
            for block in blocks or []:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")
                if btype == "text":
                    raw = block.get("text", "")
                    text = clean_prompt(raw) if kind == "user" else raw.strip()
                    if text:
                        step_kind = "prompt" if kind == "user" else "text"
                        steps.append(Step(len(steps) + 1, step_kind, ts, text, cwd=cwd))
                elif btype == "tool_use" and kind == "assistant":
                    step = Step(
                        len(steps) + 1,
                        "tool",
                        ts,
                        tool=block.get("name", "?"),
                        input=block.get("input") or {},
                        cwd=cwd,
                    )
                    steps.append(step)
                    pending[block.get("id")] = step
                elif btype == "tool_result" and kind == "user":
                    step = pending.pop(block.get("tool_use_id"), None)
                    if step is None:
                        continue
                    step.text = result_text(block.get("content"))
                    step.is_error = bool(block.get("is_error"))
                    step.denied = bool(rec.get("toolDenialKind")) or (
                        step.is_error and bool(DENIED_RE.match(step.text))
                    )
    return Session(session_id(path), path, custom_title or ai_title, steps)


# --- Ledger written by the sharpen-later skill -------------------------------

BOOKMARK_RE = re.compile(r"^L-[\w-]+-\d+$")


def default_ledger():
    state = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(state) / "sharpen-saw" / "later.jsonl"


def load_ledger(path):
    if not path.exists():
        return []
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def open_entries(path):
    return [e for e in load_ledger(path) if e.get("status") == "OPEN"]


def resolve_entries(path, target):
    """Marks open entries matching an id, a session prefix or "all" as RESOLVED."""
    entries = load_ledger(path)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    resolved = 0
    for entry in entries:
        matches = (
            target == "all"
            or entry.get("id") == target
            or (not BOOKMARK_RE.match(target) and entry.get("session", "").startswith(target))
        )
        if entry.get("status") == "OPEN" and matches:
            entry.update(status="RESOLVED", resolved_at=now)
            resolved += 1
    if resolved:
        tmp = path.with_suffix(".tmp")
        tmp.write_text(
            "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in entries),
            encoding="utf-8",
        )
        tmp.replace(path)
    return resolved


def format_queue(entries):
    if not entries:
        return ""
    out = [RULE, f"📥 /sharpen-later queue: {len(entries)} open item(s)", RULE]
    for e in entries:
        out.append(
            f"• [{e.get('id')}] {e.get('timestamp')} [{e.get('category')}]"
            f" session {e.get('session', '')[:8]} · {e.get('cwd', '')}"
        )
        out.append(f"    Note   : {e.get('human_note', '')}")
        if e.get("agent_note"):
            out.append(f"    Agent  : {e['agent_note']}")
        out.append(f"    Inspect: view {e.get('id')}   Resolve: resolve {e.get('id')}")
    out.append(RULE)
    return "\n".join(out) + "\n"


# --- Error signatures and command keys ---------------------------------------

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
EXIT_HEADER_RE = re.compile(r"^Exit code \d+\s*")
TOOL_ERROR_TAG_RE = re.compile(r"</?tool_use_error>")
ERROR_LINE_RE = re.compile(
    r"\b(?:\w*error|\w*exception|fatal|failed|failure|unrecognized|unknown|invalid|"
    r"denied|blocked|not found|not allowed|no such|cannot|usage|mismatch|missing|"
    r"conflict|rejected)\b|✗|❌",
    re.I,
)
PATH_TOKEN_RE = re.compile(r"""[^ \t\n"'`()]*/[^ \t\n"'`()]*""")
DIGITS_RE = re.compile(r"\d+")
SANDBOX_RE = re.compile(r"Operation not permitted|Read-only file system", re.I)


def _focus_error(raw):
    """(text from the last line naming a failure, whether such a line exists)."""
    text = ANSI_RE.sub("", raw.strip())
    body = TOOL_ERROR_TAG_RE.sub("", EXIT_HEADER_RE.sub("", text)).strip()
    lines = [ln.strip() for ln in (body or text).splitlines() if ln.strip()]
    window = lines[-25:]
    hits = [i for i, ln in enumerate(window) if ERROR_LINE_RE.search(ln)]
    focused = window[hits[-1]:] if hits else window[-3:]
    return WS_RE.sub(" ", " ".join(focused)), bool(hits)


def error_example(raw):
    """Verbatim failure text, short enough to quote."""
    return _focus_error(raw)[0][:200].rstrip()


def error_signature(raw):
    """The failure with paths and numbers masked, so repeats cluster."""
    focused, named = _focus_error(raw)
    exit_header = EXIT_HEADER_RE.match(raw.strip())
    if exit_header and not named:
        # A failed command whose output names no error is mostly stdout;
        # clustering on that text is noise.
        focused = f"{exit_header.group().strip()}, no error line in output"
    masked = DIGITS_RE.sub("N", PATH_TOKEN_RE.sub("PATH", focused[:400]))
    return WS_RE.sub(" ", masked)[:120].rstrip()


LEADING_VAR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
LEADING_ENV_RE = re.compile(
    r"""^(?:export\s+)?(?:[A-Za-z_]\w*=(?:"(?:[^"\\]|\\.)*"|'[^']*'|\([^)]*\)|\S+)\s*)+"""
)
CHAIN_SPLIT_RE = re.compile(r"\s*(?:&&|;|\|\|)\s*")
DURATION_RE = re.compile(r"^\d+[smhd]?$")
SUBCOMMAND_RE = re.compile(r"^[a-zA-Z0-9_:-]+$")
EXECUTABLE_RE = re.compile(r"^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$")
IGNORED_BUILTINS = {
    "set", "cd", "export", "unset", "true", "echo", "printf", "sleep", "mkdir",
    "for", "while", "if", "then", "else", "do", "done", "fi", "shift", "local",
    "return", "exit",
}  # fmt: skip
SHELL_KEYWORDS = {"do", "then", "else", "{", "!", "time"}
WRAPPERS = {"bash", "sh", "zsh", "timeout", "env", "nice", "command"}
# `gh pr view` always nests; git only does under these subcommands.
GIT_GROUPS = {"worktree", "stash", "remote", "submodule", "bisect"}
# Their first argument is an operand, never a subcommand.
NO_SUBCOMMAND = {
    "cat", "ls", "grep", "rg", "sed", "awk", "head", "tail", "find", "wc", "jq",
    "rm", "cp", "mv", "touch", "chmod", "stat", "sort", "cut", "tr", "diff", "curl",
}  # fmt: skip
HEREDOC_RE = re.compile(r"""<<-?\s*['"]?(\w+)""")
# A shared interpreter says nothing about intent, so these get no sibling contrast.
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node", "dart"}


def _segment_key(segment):
    segment = LEADING_ENV_RE.sub("", segment.strip().lstrip("( ")).strip("()\"' \t")
    tokens = segment.split()
    while tokens and tokens[0] in SHELL_KEYWORDS:
        tokens.pop(0)
    if not tokens:
        return None
    at = 0
    exe = tokens[0].rsplit("/", 1)[-1]
    if exe in WRAPPERS and len(tokens) > 1:
        if tokens[1] == "-n":  # `bash -n script` is a syntax check, not a run
            return None
        at = next(
            (
                i
                for i, tok in enumerate(tokens[1:], 1)
                if not tok.startswith("-") and not DURATION_RE.match(tok)
            ),
            0,
        )
        exe = tokens[at].rsplit("/", 1)[-1]
    if exe in IGNORED_BUILTINS or not EXECUTABLE_RE.match(exe):
        return None
    first = tokens[at + 1] if at + 1 < len(tokens) else ""
    if not first or first.startswith("-") or exe in NO_SUBCOMMAND:
        return exe
    base = first.rsplit("/", 1)[-1]
    if exe in ("python", "python3", "dart", "node") and base.endswith((".py", ".dart", ".js")):
        return f"{exe} {base}"
    if not SUBCOMMAND_RE.match(first):
        return exe
    second = tokens[at + 2] if at + 2 < len(tokens) else ""
    nested = exe == "gh" or (exe == "git" and first in GIT_GROUPS)
    if nested and SUBCOMMAND_RE.match(second) and not second.startswith("-"):
        if not DIGITS_RE.search(second):
            return f"{exe} {first} {second}"
    return f"{exe} {first}"


def command_key(command):
    """`cd x && PAGER=cat timeout 30s gh pr view 1` -> `gh pr view`."""
    terminators = set(HEREDOC_RE.findall(command or ""))
    for line in (command or "").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line in terminators:
            continue
        for segment in CHAIN_SPLIT_RE.split(line):
            key = _segment_key(segment)
            if key:
                return key
    return None


# --- Audit -------------------------------------------------------------------


def installed_skills(home):
    names = set()
    for rel in (".claude/skills", ".agents/skills"):
        for skill_md in (home / rel).glob("*/SKILL.md"):
            names.add(skill_md.parent.name)
    return names


def audit(sessions, prompts="first", skills=frozenset()):
    """Aggregates friction signals across `sessions` into a plain dict."""
    tool_counts = Counter()
    runs = defaultdict(lambda: [0, set()])
    commands = {}
    var_prefixed = Counter()
    hogs = []
    edits = defaultdict(Counter)
    activated = Counter()
    denials = Counter()
    clusters = {}
    successes = defaultdict(list)
    user_prompts = {}
    sandbox = errors = 0

    def close_run(key, length, sid):
        if key and length >= 3:
            runs[key][0] += 1
            runs[key][1].add(sid)

    for session in sessions:
        last_key, run_length = None, 0
        for step in session.steps:
            if len(step.text) > CONTEXT_HOG_CHARS:
                label = step.tool or step.kind
                hogs.append((len(step.text), session.short, step.index, label, step.summary))
            if step.kind == "prompt":
                if prompts == "all" or (prompts == "first" and session.sid not in user_prompts):
                    user_prompts.setdefault(session.sid, []).append(step.text)
                name = step.text.split()[0].lstrip("/") if step.text.startswith("/") else ""
                if name in skills:
                    activated[name] += 1
                continue
            if step.kind != "tool":
                continue

            tool_counts[step.tool] += 1
            key = command_key(step.input.get("command")) if step.tool == "Bash" else None
            run_key = f"Bash ({key})" if key else step.tool
            if run_key == last_key:
                run_length += 1
            else:
                close_run(last_key, run_length, session.sid)
                last_key, run_length = run_key, 1

            command = step.input.get("command") if step.tool == "Bash" else None
            if command:
                stat = commands.setdefault(
                    key or "(unparsed)", {"total": 0, "sessions": set(), "cwds": set()}
                )
                stat["total"] += 1
                stat["sessions"].add(session.sid)
                stat["cwds"].add(step.cwd)
                if LEADING_VAR_RE.match(command.lstrip()):
                    var_prefixed[key or "(unparsed)"] += 1
            path = step.input.get("file_path") or step.input.get("notebook_path")
            if step.tool in EDIT_TOOLS and path:
                edits[path][session.sid] += 1
            if step.tool == "Skill" and step.input.get("skill"):
                activated[step.input["skill"]] += 1
            elif step.tool == "Read" and str(path).endswith("/SKILL.md"):
                activated[Path(path).parent.name] += 1

            if step.denied:
                denials[run_key] += 1
            elif step.is_error:
                errors += 1
                if SANDBOX_RE.search(step.text):
                    sandbox += 1
                signature = error_signature(step.text)
                cluster = clusters.setdefault(
                    (step.tool, key, signature),
                    {
                        "tool": step.tool,
                        "signature": signature,
                        "count": 0,
                        "sessions": set(),
                        "example": error_example(step.text),
                        "command": squash(command, 120, 80) if command else None,
                        "key": key,
                    },
                )
                cluster["count"] += 1
                cluster["sessions"].add(session.sid)
            elif key and len(successes[key]) < 4:
                brief = squash(command, 120, 80)
                if brief not in successes[key]:
                    successes[key].append(brief)
        close_run(last_key, run_length, session.sid)

    for cluster in clusters.values():
        key = cluster["key"]
        siblings = [] if key in INTERPRETERS else successes.get(key, [])
        cluster["siblings"] = [c for c in siblings if c != cluster["command"]][:2]
    spirals = {
        path: per_session
        for path, per_session in edits.items()
        if max(per_session.values()) >= EDIT_SPIRAL_MIN
    }
    return {
        "sessions": sessions,
        "tool_counts": tool_counts,
        "runs": runs,
        "commands": commands,
        "var_prefixed": var_prefixed,
        "hogs": sorted(hogs, reverse=True),
        "spirals": spirals,
        "activated": activated,
        "dormant": sorted(skills - {name.split(":")[-1] for name in activated}),
        "denials": denials,
        "sandbox": sandbox,
        "errors": errors,
        "clusters": sorted(
            clusters.values(),
            key=lambda c: (-len(c["sessions"]), -c["count"], c["tool"]),
        ),
        "prompts": user_prompts,
    }


def format_clusters(report):
    out = ["8. Path-Stripped Error Clusters & Sibling Success Contrast (Top 10):"]
    for c in report["clusters"][:10]:
        label = f" ({c['key']})" if c["key"] else ""
        out.append(
            f"  - [{c['count']}x across {len(c['sessions'])} session(s)]"
            f" {c['tool']}{label}: {c['signature']}"
        )
        out.append(f'      Verbatim Example: "{c["example"]}"')
        if c["command"]:
            out.append(f"      Failed Cmd: {c['command']}")
        for sibling in c["siblings"]:
            out.append(f"      Succeeding Sibling: {sibling}")
    if len(out) == 1:
        out.append("  - None detected")
    return "\n".join(out)


def format_audit(report):
    sessions = report["sessions"]
    steps = sum(len(s.steps) for s in sessions)
    out = [f"--- Audit of {len(sessions)} session(s) ---"]
    for s in sessions:
        title = f' "{s.title}"' if s.title else ""
        out.append(f"  - {s.short}{title} ({len(s.steps)} steps)")
    out.append(
        f"Steps: {steps} · Tool calls: {sum(report['tool_counts'].values())}"
        f" · Failed: {report['errors']} · Denied: {sum(report['denials'].values())}"
    )

    out.append("\n1. Tool Usage Frequencies:")
    out += [f"  - {name}: {n}" for name, n in report["tool_counts"].most_common()]

    out.append("\n2. Repeated Tool Sequences (3+ consecutive calls):")
    runs = sorted(report["runs"].items(), key=lambda kv: -kv[1][0])
    out += [f"  - {key}: {n} run(s) across {len(sids)} session(s)" for key, (n, sids) in runs[:15]]

    out.append("\n3. Shell Commands by Subcommand (Top 15):")
    ranked = sorted(report["commands"].items(), key=lambda kv: -kv[1]["total"])
    for key, stat in ranked[:15]:
        out.append(
            f"  - [{stat['total']}x] {key} (across {len(stat['sessions'])} session(s),"
            f" {len(stat['cwds'])} cwd(s))"
        )

    out.append(f"\n4. Largest Context Hogs (> {CONTEXT_HOG_CHARS:,} chars):")
    for length, short, index, label, summary in report["hogs"][:5]:
        out.append(f"  - {length:,} chars: step {index} in {short} ({label}) {squash(summary, 80, 40)}")

    out.append(f"\n5. File Edit Spirals (>= {EDIT_SPIRAL_MIN} edits in one session):")
    spirals = sorted(report["spirals"].items(), key=lambda kv: -max(kv[1].values()))
    for path, per_session in spirals[:10]:
        out.append(
            f"  - {path}: {sum(per_session.values())} edits"
            f" (max {max(per_session.values())} in one session)"
        )
    if not spirals:
        out.append("  - None detected")

    activated = ", ".join(f"{name} ({n}x)" for name, n in report["activated"].most_common())
    dormant = report["dormant"]
    out.append("\n6. Skill Activation & Allowlist Hygiene:")
    out.append(f"  - Activated skills: {activated or 'none'}")
    out.append(f"  - Installed but never activated here: {len(dormant)} {', '.join(dormant[:10])}")
    out.append(f"  - Permission denials: {sum(report['denials'].values())}")
    out += [f"      * [{n}x] {key}" for key, n in report["denials"].most_common(5)]
    out.append(f"  - Sandbox errors (EPERM / read-only): {report['sandbox']}")
    var_prefixed = report["var_prefixed"]
    out.append(
        "  - Variable-prefixed commands (VAR=val cmd; may defeat prefix allowlists):"
        f" {sum(var_prefixed.values())}"
    )
    out += [f"      * [{n}x] {key}" for key, n in var_prefixed.most_common(5)]

    if report["prompts"]:
        out.append("\n7. Tasks Performed (User Prompts):")
        for s in sessions:
            for prompt in report["prompts"].get(s.sid, []):
                out.append(f'  - {s.short}: "{squash(prompt)}"')

    out.append("\n" + format_clusters(report))
    return "\n".join(out)


def budget_section(home):
    """Sizes of always-loaded rule files and of oversized skills."""
    out = ["=== RULE & SKILL BUDGET AUDIT ==="]
    seen, total = set(), 0
    for rule_file in (home / ".claude" / "CLAUDE.md", home / "AGENTS.md"):
        real = rule_file.resolve()
        if not real.is_file() or real in seen:
            continue
        seen.add(real)
        size = real.stat().st_size
        total += size
        out.append(f"  - {rule_file}: {size:,} bytes")
    verdict = "✅ OK" if total <= RULE_BYTES_CEILING else "⚠️ BUDGET OVERFLOW"
    out.append(f"Global rules: {verdict} ({total:,} / {RULE_BYTES_CEILING:,} bytes, soft ceiling)")
    oversized = []
    for rel in (".claude/skills", ".agents/skills"):
        for skill_md in sorted((home / rel).glob("*/SKILL.md")):
            real = skill_md.resolve()
            if real in seen:
                continue
            seen.add(real)
            lines = len(real.read_text(encoding="utf-8", errors="replace").splitlines())
            if lines > SKILL_LINES_CEILING:
                oversized.append((lines, skill_md))
    out.append(f"Skills over {SKILL_LINES_CEILING} lines: {len(oversized)} (largest 10 shown)")
    out += [f"  - {lines} lines: {skill_md}" for lines, skill_md in sorted(oversized, reverse=True)[:10]]
    return "\n".join(out)


# --- CLI ---------------------------------------------------------------------


def find_session(root, token):
    """Resolves a path or a session-id prefix to a transcript file."""
    if token and Path(token).is_file():
        return Path(token)
    files = session_files(root)
    if not token:
        return files[0] if files else None
    # Main sessions first: a subagent's id starts with its parent's.
    files += [p for p in session_files(root, include_subagents=True) if p not in files]
    return next((p for p in files if session_id(p).startswith(token)), None)


def cmd_scan(args):
    try:
        pattern = re.compile(args.query, re.I) if args.query else None
    except re.error as e:
        sys.exit(f"Invalid --query regex: {e}")
    cutoff = time.time() - args.days * 86400
    candidates = []
    for path in session_files(args.projects_dir, args.include_subagents):
        if path.stat().st_mtime < cutoff:
            break
        session = read_session(path)
        matches = sum(
            1 for s in session.steps if pattern and pattern.search(f"{s.summary}\n{s.text}")
        )
        failures = [s for s in session.steps if s.is_error and not s.denied]
        large = sum(1 for s in session.steps if len(s.text) > 15_000)
        score = matches + 3 * len(failures) + large
        if (pattern and not matches) or score < args.min_score:
            continue
        candidates.append((score, matches, failures, large, session))
    candidates.sort(key=lambda c: -c[0])
    candidates = candidates[: args.limit]

    print(format_queue(open_entries(args.later_file)), end="")
    print(f"Found {len(candidates)} candidate session(s) (past {args.days} days):")
    for score, matches, failures, large, session in candidates:
        title = f' "{session.title}"' if session.title else ""
        print(
            f"\n[{session.short}]{title} score {score}"
            f" (matches {matches}, errors {len(failures)}, >15KB steps {large})"
        )
        first = next((s.text for s in session.steps if s.kind == "prompt"), "")
        print(f"  First prompt: {squash(first, 200, 100)}")
        if failures:
            sample = failures[0]
            print(f"  Sample failure: {squash(sample.summary, 80, 40)} -> {error_example(sample.text)}")
    print("\n" + format_clusters(audit([c[4] for c in candidates], prompts="none")))
    print("\n" + budget_section(Path.home()))


def cmd_audit(args):
    ledger = open_entries(args.later_file)
    by_id = {e.get("id"): e.get("session", "") for e in load_ledger(args.later_file)}
    paths = []
    for target in args.sessions:
        path = find_session(args.projects_dir, by_id.get(target, target))
        if path is None:
            sys.exit(f"No session matches {target!r}")
        paths.append(path)
    sessions = {p: read_session(p) for p in dict.fromkeys(paths)}
    if args.last or not paths:
        for entry in ledger:
            path = find_session(args.projects_dir, entry.get("session") or "unknown")
            if path:
                sessions.setdefault(path, read_session(path))
        wanted = len(sessions) + (args.last or 1)
        for path in session_files(args.projects_dir, args.include_subagents):
            if len(sessions) >= wanted:
                break
            if path not in sessions:
                session = read_session(path)
                if session.steps:  # skip sessions that never got past /login or /clear
                    sessions[path] = session
    sessions = list(sessions.values())
    print(format_queue(ledger), end="")
    print(format_audit(audit(sessions, args.prompts, installed_skills(Path.home()))))
    print("\n" + budget_section(Path.home()))


def cmd_view(args):
    target = args.target or os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    anchor_ts = None
    if BOOKMARK_RE.match(target):
        entry = next((e for e in load_ledger(args.later_file) if e.get("id") == target), None)
        if entry is None:
            sys.exit(f"No bookmark {target} in {args.later_file}")
        target, anchor_ts = entry.get("session", ""), entry.get("timestamp", "")
    path = find_session(args.projects_dir, target)
    if path is None:
        sys.exit(f"No transcript for session {target!r} (it may have been cleaned up)")
    steps = read_session(path).steps

    bounds = None
    if args.step:
        low, _, high = args.step.partition("-")
        bounds = (int(low) - args.window, int(high or low) + args.window)
    elif anchor_ts:
        before = [s.index for s in steps if s.ts[:19] <= anchor_ts[:19]]
        anchor = before[-1] if before else 0
        window = args.window or 5
        bounds = (anchor - window, anchor + window)
    if bounds:
        steps = [s for s in steps if bounds[0] <= s.index <= bounds[1]]
    if args.errors:
        steps = [s for s in steps if s.is_error]
    elif not (bounds or args.tools):
        steps = [s for s in steps if s.kind != "tool"]
    if args.tail:
        steps = steps[-args.tail :]

    head = (args.max_len * 2) // 3
    for s in steps:
        flag = " [DENIED]" if s.denied else " [ERROR]" if s.is_error else ""
        label = f"tool {s.tool}" if s.kind == "tool" else s.kind
        print(f"=== [{s.index}] {label}{flag} ({s.ts[:19]}) ===")
        if s.kind == "tool":
            print(f"  $ {squash(s.summary, head, args.max_len - head)}")
        if s.text:
            print(squash(s.text, head, args.max_len - head))
        print()


def cmd_queue(args):
    print(format_queue(open_entries(args.later_file)) or "No open /sharpen-later items.")


def cmd_resolve(args):
    count = resolve_entries(args.later_file, args.target)
    print(f"✅ Resolved {count} /sharpen-later item(s) matching {args.target!r}.")


def main(argv=None):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--projects-dir", type=Path, default=projects_dir())
    common.add_argument("--later-file", type=Path, default=default_ledger())
    common.add_argument("--include-subagents", action="store_true")

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", parents=[common], help="rank recent sessions by friction")
    scan.add_argument("--query", default="", help="case-insensitive regex to focus on a domain")
    scan.add_argument("--days", type=int, default=14)
    scan.add_argument("--limit", type=int, default=5)
    scan.add_argument("--min-score", type=int, default=1)
    scan.set_defaults(run=cmd_scan)

    deep = sub.add_parser("audit", parents=[common], help="8-section report across sessions")
    deep.add_argument("sessions", nargs="*", help="session id prefixes or bookmark ids")
    deep.add_argument("--last", type=int, default=0, help="include the N most recent sessions")
    deep.add_argument("--prompts", choices=("first", "all", "none"), default="first")
    deep.set_defaults(run=cmd_audit)

    view = sub.add_parser("view", parents=[common], help="print steps of one session")
    view.add_argument("target", nargs="?", default="", help="session id prefix, bookmark id or path")
    view.add_argument("--step", help="N or A-B")
    view.add_argument("--window", type=int, default=0, help="steps of context around --step")
    view.add_argument("--tools", action="store_true", help="include tool calls")
    view.add_argument("--errors", action="store_true", help="only failed tool calls")
    view.add_argument("--tail", type=int, default=0)
    view.add_argument("--max-len", type=int, default=600)
    view.set_defaults(run=cmd_view)

    queue = sub.add_parser("queue", parents=[common], help="list open /sharpen-later items")
    queue.set_defaults(run=cmd_queue)

    resolve = sub.add_parser("resolve", parents=[common], help="close /sharpen-later items")
    resolve.add_argument("target", help="bookmark id, session id prefix or 'all'")
    resolve.set_defaults(run=cmd_resolve)

    args = parser.parse_args(argv)
    args.run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
