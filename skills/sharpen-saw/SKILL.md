---
name: sharpen-saw
description: >-
  Audits past Claude Code session transcripts offline to find recurring agent
  friction (failing commands, edit spirals, permission denials, context hogs,
  dormant skills) and turns the findings into durable fixes across rules, hooks,
  CLI shims and skills. Use when the user asks to "sharpen the saw", audit past
  sessions for friction, fix repetitive agent mistakes, drain the /sharpen-later
  queue, or runs /sharpen-saw. Don't use for debugging the feature currently
  being built, or for logging a papercut mid-task (use sharpen-later).
key_features:
  - Single-pass offline transcript scan
  - Error clusters with succeeding-sibling contrast
  - Rule and skill budget audit
  - Multi-tier fixes (rules, hooks, shims, skills)
  - Drains the /sharpen-later queue
---

# Sharpening the Saw (`/sharpen-saw`)

Audit past sessions, diagnose the friction that keeps recurring, and harden the
tools, rules and skills that caused it.

## The 3 Laws

1. **Dedicated sessions.** Tool and rule refactoring happens here, in its own
   session. Mid-feature friction gets a `/sharpen-later` bookmark and is picked
   up from the queue.
2. **Deterministic tools over soft prompts.** A failure that recurs or is
   safety-critical gets a hook, a permission rule or a CLI wrapper. Prose rules
   are for routing.
3. **Affirmative framing.** Write "always run Y with flag Z". A rule phrased as
   "do NOT run X" puts X in front of the model on every turn.

## Workflow

`scripts/sharpen_saw.py` sits in this skill's directory; call it by its full
path. It needs Python 3.9+ and nothing else, and reads
`~/.claude/projects/**/*.jsonl` without loading transcripts into context.

### 1. Intake

Settle the target domain with the user (git and GitHub flow, a specific CLI,
allowlist friction, or a general audit) and the lookback window (default 14
days).

### 2. One Offline Scan

Run **one** of these. Each prints the open `/sharpen-later` queue first and the
rule and skill budget last.

```bash
# Domain scan: rank recent sessions by friction around a regex.
python3 scripts/sharpen_saw.py scan --query "git|gh|rebase" --days 14 --limit 5

# Deep audit: the 8-section report over the last N sessions, plus every
# session that has an open bookmark.
python3 scripts/sharpen_saw.py audit --last 5 --prompts first

# Surgical look around one bookmark, or at one session's failures.
python3 scripts/sharpen_saw.py view <L-id> --window 5
python3 scripts/sharpen_saw.py view <session-prefix> --errors
```

Work from the scanner's summary. Reach for `view` on a specific step when a
finding needs its surrounding context; leave the raw `.jsonl` files unread.

Reading the audit:

- **Section 8 (error clusters) comes first.** Prioritize clusters that span two
  or more sessions. `Failed Cmd` beside `Succeeding Sibling` shows the working
  invocation of the same subcommand; confirm the sibling shares the intent
  before copying its flags.
- **Section 2 (repeated sequences)** and **Section 5 (edit spirals)** mark
  iterative struggle: one session means a missing error hint, many sessions
  means a missing tool.
- **Section 6** lists permission denials (allowlist gaps or unwanted actions),
  installed skills that never fired, and `VAR=val cmd` prefixes that can defeat
  prefix allowlists.
- **Budget audit**: when global rules exceed the soft byte ceiling, compact them
  before adding more. A `SKILL.md` over 250 lines should move tables and
  examples into `references/`.

### 3. Write the Report First

Before touching any rule, hook, script or skill, write
`tool_optimization_report.md` to a scratch location. Classify each finding:

| Root cause                | Signature                                              | Typical fix                                    |
| :------------------------ | :----------------------------------------------------- | :--------------------------------------------- |
| **Cognitive / attention** | Negation priming; a rule buried mid-file and forgotten | Rewrite affirmatively, or move it to a hook.   |
| **Tool / harness gap**    | Pagers, editors, watchers that hang; missing flags     | Wrapper or hook that supplies the flag.        |
| **Policy ambiguity**      | Unclear line between autonomous and gated actions      | State the boundary; encode it as a permission. |
| **Iterative struggle**    | 3+ consecutive calls to the same command               | One session: error hint. Many: a real tool.    |

When an existing skill or rule was involved, also say which way it failed:

1. **Discovery miss**: the skill existed and never loaded. Fix its
   `description:` trigger words, leaving the body alone.
2. **Adherence miss**: it loaded and was not followed. Move the constraint into
   a hook or wrapper, or restate it affirmatively at the top of its section.
3. **Coverage gap**: nothing addressed the case. Add one surgical rule or flag.

### 4. Propose Fixes by Tier

| Tier                   | Surface                                                                                     | Use for                                                   |
| :--------------------- | :------------------------------------------------------------------------------------------ | :-------------------------------------------------------- |
| **1. Global rules**    | `~/.claude/CLAUDE.md`                                                                       | One or two affirmative lines that route. Mind the budget. |
| **2. Hooks and shims** | `PreToolUse` hooks and permissions in `~/.claude/settings.json`; wrappers in `~/.local/bin` | Blocking bad flags, adding `--yes` or a timeout, hints.   |
| **3. Skills**          | `~/.claude/skills/<name>/SKILL.md`                                                          | Multi-step workflows loaded on demand, 250 lines at most. |
| **4. Project docs**    | The repository's `CLAUDE.md` or memory                                                      | Build commands and gotchas specific to one repository.    |

Grow an edited `SKILL.md` by at most 20%; past that, split into `references/`.

### 5. Confirm, Apply, Close Out

1. Summarize the findings and proposed fixes for the user, then wait for their
   go-ahead before changing anything on disk.
2. Apply the approved fixes.
3. Close the bookmarks each fix addresses:

   ```bash
   python3 scripts/sharpen_saw.py resolve <L-id|session-prefix|all>
   ```

4. Record, for each landed fix, the regex of its old symptom. After a week of
   sessions, `scan --query "<symptom regex>"` shows whether it came back; a
   recurrence means escalating that fix from a rule to a hook or wrapper.
