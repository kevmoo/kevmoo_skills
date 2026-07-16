---
name: sidequest
description: >-
  Synthesizes conversation history and active tasks into a visual hierarchy map
  (`sidequest.md`) to prevent context drift and cognitive overload across
  long sessions. Supports multiple sequential and concurrent main quests,
  sub-quests, and side-quests. Use when the user invokes `/sidequest`, asks
  where we are, what we were doing, or what's on our stack, or when the
  conversation branches across multiple topics, blockers, or digressions. Don't
  use for simple one-off questions that don't involve multi-step work or task
  hierarchy management.
key_features:
  - Conversation mapping
  - Task hierarchy
  - Context drift prevention
  - Subagent rebuilds
  - VCS state tracking
  - Vanquished blocker styling
---

# 🧭 Sidequest (`/sidequest`)

An intelligent conversational synthesizer and visual grounding point for task
hierarchies and digressions.

## Why this skill exists
In complex pair-programming sessions, work rarely follows a straight line.
Engineers encounter broken builds, missing dependencies, linter errors, code
review digressions, and parallel CI waits. Without explicit tracking, agents and
humans suffer from **context drift** and **cognitive overload** ("AI brain
fry"):
- Subtasks get abandoned or forgotten when jumping into a rabbit hole.
- Long-running sessions lose track of earlier completed goals when moving to the
  next initiative.
- Deep debugging loops cause context window compaction, wiping out memory of
  original objectives.
- Detours leave uncommitted files dirty across branches/commits, risking
  accidental amends in stacked workflows (e.g. `jj`, Gerrit) or forgotten code
  changes.

`/sidequest` maintains an organic, multi-tiered visual map (`sidequest.md`) in
session memory, keeping both human and agent anchored without adding friction or
bloat.

---

## When to use this skill
- When the user explicitly invokes `/sidequest` or `/sidequest rebuild`.
- When the user asks *"where are we right now?"*, *"what's on our stack?"*, or
  *"what were we originally working on?"*.
- When an interruption, unexpected blocker, or new topic causes the conversation
  to branch away from the active task.

---

## 🏗️ Core Architecture & Zero Repo Pollution

### Session-Private Storage (`sidequest.md`)
Whenever `/sidequest` generates or updates the map, it writes **exclusively**
to the session's artifact directory as `sidequest.md` (the exact session
directory is dynamically provided at runtime).

> [!IMPORTANT]
> **Zero Repo Pollution:** This file exists purely inside the agent's session
> memory on disk. It **never** touches user repositories (`//depot/google3/...`,
> `~/github/...`, or `~/.dotfiles`), completely eliminating untracked git/hg/jj
> file warnings, presubmit failures, or accidental check-ins.

Because the file is persisted to disk in the session folder, if the conversation
undergoes **context compaction** (due to large log outputs or long turns), the
agent can instantly re-read `sidequest.md` to recover exact task hierarchy
without losing state.

---

## 🧭 Multi-Quest Hierarchy (`Main -> Sub -> Side`)

Rather than restricting the map to a single rigid goal, `/sidequest` supports
**Multiple Main Quests** across two natural patterns:

1. **Sequential Quests (Chapter Progression):** When Main Quest 1 finishes
   completely (committed/pushed/merged), the agent marks it `🏆 [COMPLETED]`
   and opens **Main Quest 2** as the new active chapter. This builds a clean
   chronological ledger of everything achieved across the session.
2. **Concurrent Quests (Parallel Tracks):** While waiting on a 30-minute
   CI/presubmit run for Main Quest 1 (`⏸️ [PAUSED / WAITING ON CI]`), the user
   can pivot to start an independent major initiative (Main Quest 2
   `⚔️ [ACTIVE HEAD]`). Both coexist cleanly without subordinating parallel
   work.

### The 3-Tier Hierarchy
- **⚔️/🏆/⏸️ Main Quests:** High-level initiatives or major chapters (e.g.,
  *Migrate UserService to v2*, *Investigate Bazel Thread Leak*).
- **🛡️ Sub-Quests:** The logical milestones and planned phases needed to
  complete a Main Quest.
  - Critical-path unplanned tasks (e.g. build errors, test failures, minor
    blockers) or steps should be nested **directly under** the corresponding
    Sub-Quest using indentation and helper tags:
    - `👾 *Blocker:* <description>`: An active critical-path blocker that must
      be resolved.
    - `💀 ~~*Blocker:* <description>~~ -> *Resolved*`: A vanquished blocker,
      visually slain with strikethrough and a skull emoji (`💀`).
    - `👣 *Step:* <description>`: A planned step/action item.
    - `👣 ~~*Step:* <description>~~ -> *Done*`: A completed step, formatted
      with strikethrough.
- **🌿 Side Quests:** ONLY completely unrelated or out-of-scope tasks, tangents,
  or context drift. These are the rabbit holes that branch away from the main
  mission.

### 📦 Version Control (VCS) State Integration
To prevent divergent state confusion and accidental amends in stacked-commit
workflows (e.g. `jj`, Gerrit, Git branches):
- Track the VCS status of modified files directly in `sidequest.md` alongside
  each active Quest or detour using the 5-stage lifecycle:
  - `📝 Dirty`: Lists modified/untracked files in the working copy.
  - `📦 Local Commit`: Lists committed changes / revision IDs awaiting push.
  - `🚀 Uploaded`: Lists published PRs, Gerrit CLs, or remote branches in
    review.
  - `🎉 Merged / Submitted`: Remote change is landed upstream; local rebase or
    sync is pending.
  - `🧹 Clean`: Local workspace is synced to latest main with branches pruned.
- Never mark a code detour or blocker as done without recording whether its
  changes remain dirty or have been committed/uploaded.

---

## 🚀 Execution Workflow & Procedures

When `/sidequest` triggers (either via explicit command, user question, or
conversational branching), follow this exact decision workflow:

1. **Determine Execution Mode:**
   - **Is this the very first `/sidequest` check, or did the user explicitly
     request `/sidequest rebuild`?** → Execute **Mode B (Subagent Rebuild)**
     below.
   - **Does `sidequest.md` already exist, and either a task progressed OR the
     user invoked `/sidequest` mid-session?** → Execute **Mode A (In-Session
     Delta Update & Summary)** below.

---

### Mode A: Rolling Ledger Delta Updates (In-Session `O(1)`)
When an existing `sidequest.md` is active and a task progresses, completes,
meanders, or `/sidequest` is explicitly invoked:
1. **Do NOT re-read `transcript.jsonl` or conversation history.**
2. Use `replace_file_content` (or standard file edit tools) directly on
   `sidequest.md` in the session's artifact directory to perform surgical
   updates:
   - **Progress & Completion:** Mark sub-quests, steps, or side quests from
     `[ ]` to `[x]`. For completed steps (`👣`), wrap the step text in
     strikethrough (`~~...~~`) and append the resolution (e.g.,
     `* [x] 👣 ~~*Step:* Merge in PR #142~~ -> *Done*`).
   - **Vanquished Blockers:** When a blocker (`👾`) is resolved, replace `👾`
     with `💀`, wrap the blocker text in strikethrough (`~~...~~`), and note
     the resolution (e.g., `* [x] 💀 ~~*Blocker:* Fix build~~ -> *Resolved*`).
   - **VCS State Updates:** Update the active VCS state annotation for any
     modified files, local commits, uploaded PRs/CLs, or merged status.
   - **Blockers & Steps:** Nest new critical-path blockers (`👾`) or steps
     (`👣`) under their active `🛡️ Sub-Quest`.
   - **New Side Quest:** Append new unrelated tangents under
     `### 🌿 Active & Parked Side Quests`.
   - **Chapter Completion:** When a Main Quest is merged/committed, update its
     header from `⚔️ [ACTIVE HEAD]` to `🏆 [COMPLETED]`, and open the next
     `⚔️ [ACTIVE HEAD] Main Quest` below it.
3. **Explicit Command Response:** If the user invoked `/sidequest` directly,
   after performing any pending updates on `sidequest.md`, output a **brief,
   punchy chat summary** highlighting:
   - Our active `⚔️ Main Quest` and current active `🛡️` sub-quest (marked
     `*(IN PROGRESS)*`).
   - Active VCS/working copy status (dirty files, active commit/branch).
   - Any open or parked `🌿 Side Quests`.
   - Our immediate recommended next step.

---

### Mode B: Subagent Transcript Audit (`/sidequest rebuild`)
To rebuild or initialize the map without burning main-session tokens or pausing
the conversation:
1. **Spawn a Background Auditor**: Spawn a background subagent using
   `invoke_subagent` (or equivalent platform-native multi-agent creation tool).
   - **Antigravity Setup**: Use `TypeName: "self"`,
     `Role: "Sidequest Log Auditor"`, and provide the prompt contents read
     from `skills/sidequest/resources/auditor_prompt.txt` (relative to the
     repository root).
   - **Fallback (Harnesses without Multi-Agent APIs)**: If the harness does
     not support spawning background subagents (like Claude Code), the agent
     should run the audit synchronously or perform a direct view/write of the
     transcript files in the session directory.
2. **Subagent Prompt Configuration**:
   Read `skills/sidequest/resources/auditor_prompt.txt` (relative to the
   repository root) for the complete auditor prompt. It instructs the subagent
   to parse `transcript.jsonl`, format items according to the 3-Tier Hierarchy,
   track the 5-stage VCS lifecycle, and write the result to `sidequest.md` in
   the session's artifact directory.
3. **Continue Main Session**: Keep your primary context clean and continue pair
   programming with the user immediately while the subagent runs asynchronously
   (if supported).
4. **Parent Handshake & UI Availability**: When the subagent sends its
   completion notification (or the background process completes):
   - In Antigravity, after receiving the `send_message` notification confirming
     the absolute path, the parent agent MUST immediately read the file's
     content and write it into the conversation artifacts directory as
     `sidequest.md` using `write_to_file` (or copy it directly).
   - If running synchronously, copy the compiled file to the conversation's
     active artifact path so it's immediately available to the user.

---

## 🤝 Multi-Session Handshake (Context-Specific Issue Trackers)

While `sidequest.md` handles in-session digressions cleanly, some side quests
cannot be resolved in one sitting (e.g., waiting on external team reviews,
security approvals, or multi-day refactors).

For items marked **`🎒 [Parked / Tracked for Later]`** in `sidequest.md`, the
skill bridges seamlessly into your existing persistence tools:
1. **Inspect Available Trackers:** The agent checks what issue tracking tools,
   CLIs, or skills exist in the user's active environment (e.g.,
   `gh issue create` for GitHub repositories, local issue tracking skills,
   or project management frameworks).
2. **Prompt to Escalate:** When parking a side quest, the agent gently prompts:
   > *"Would you like me to file a quick issue in your project's issue
   > tracker (`gh issue` / local tracker) so this parked item survives across
   > sessions?"*

---

## 💬 Ongoing Conversational Behavior

Once `sidequest.md` exists, the agent adopts a helpful, low-friction discipline:
- **No Heavy Pushback:** When the user pivots across files or topics,
  acknowledge it smoothly: *"Oh, we're going off on a sidequest, that's
  completely fine."*
- **VCS & Detour Awareness:** When completing a code detour or blocker, prompt
  before returning to the main track so uncommitted edits aren't forgotten:
  > *"Detour resolved! Changes in `lib/foo.dart` are currently uncommitted.
  > Should we commit/upload before resuming Main Quest 1?"*
- **Sync & Rebase Prompts:** When a remote PR or CL lands upstream, prompt
  to sync:
  > *"PR #142 has merged upstream! Should we pull main and sync local
  > branches to get back to 🧹 Clean?"*
- **Gentle Triage Prompts:** When a new unexpected blocker or rabbit hole
  emerges (e.g., a broken build or linter warning), ask:
  > *"We're taking a detour to resolve this blocker—that's completely fine.
  > Should we tackle it right now, or track it in our map?"*
  > *"Should we fix this right now, or would you like me to file an issue
  > in your tracker (`gh issue`) for later?"*
- **Chapter-Break Awareness:** When a major PR is pushed or a task completes and
  the user introduces a new topic, recognize the chapter break:
  > *"Looks like we finished ⚔️ Main Quest 1! Should we open a new Main
  > Quest in our map for this new topic, or is this just a quick sidequest?"*

---

## 📄 Template Reference

For a full reference of the visual hierarchy map, see
`skills/sidequest/resources/sidequest_template.md` (relative to the
repository root).
