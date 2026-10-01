---
name: sharpen-later
description: >-
  Bookmarks agent workflow friction (a failing CLI, an ignored rule, a missing
  skill or hook) in one command, then resumes the active task in the same turn.
  Use when the user invokes /sharpen-later, says "log this for sharpen-saw", or
  wants to note a papercut without derailing current work. Don't use for
  root-cause analysis or for fixing tools and rules now (use sharpen-saw).
key_features:
  - One-command friction bookmark
  - Same-turn task resumption
  - Automatic session and timestamp capture
  - Ledger shared with sharpen-saw
---

# Sharpen-Later (`/sharpen-later`)

Capture a friction bookmark in **one tool call** and return to the user's task
in the **same turn**. A dedicated `/sharpen-saw` session investigates it later.

## The Same-Turn Contract

1. **Log it with one command.** `scripts/later.py` sits in this skill's
   directory; call it by its full path.

   ```bash
   python3 scripts/later.py "<what the user said went wrong>" \
     --agent-note "<the failing command, tool or rule, in one line>" \
     --cat <category>
   ```

   | `--cat`          | Use for                                                  |
   | :--------------- | :------------------------------------------------------- |
   | `cli-gap`        | A CLI that hung, prompted, or needed a flag you guessed. |
   | `rule-violation` | An instruction that existed and was not followed.        |
   | `skill-gap`      | A skill that was missing, or present and never loaded.   |
   | `hook-gap`       | Something a hook or permission rule should have caught.  |
   | `tool-bug`       | A harness tool that misbehaved.                          |
   | `ui-glitch`      | Output that rendered wrong for the user.                 |
   | `perf`           | Work that was needlessly slow or token-heavy.            |
   | `review-escape`  | A real defect a human reviewer caught after local review |
   | `other`          | Anything else.                                           |

2. **Echo the receipt.** Put the printed `📌 Logged for /sharpen-saw (...)` line
   first in your reply.
3. **Resume.** Continue the interrupted task in the same turn.

## Guardrails

- Infer `--cat` and `--agent-note` from the conversation and proceed; the user
  already said everything they wanted to say.
- Keep the detour to that single command. Root causes, transcript reading, and
  edits to rules, skills or CLIs all belong to the later `/sharpen-saw` session,
  which finds the surrounding steps from the bookmark's session and timestamp.

## Details

- Bookmarks append to
  `${XDG_STATE_HOME:-~/.local/state}/sharpen-saw/later.jsonl` (`--later-file`
  overrides).
- The session id comes from `$CLAUDE_CODE_SESSION_ID`; under another agent, pass
  `--session <id>`.
- Needs Python 3.9+ and nothing else.
