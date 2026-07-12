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
---

# Sidequest (`/sidequest`)

An intelligent conversational synthesizer and visual grounding point for task hierarchies and digressions.

## Why this skill exists
In complex pair-programming sessions, work rarely follows a straight line. Engineers encounter broken builds, missing dependencies, linter errors, code review digressions, and parallel CI waits. Without explicit tracking, agents and humans suffer from **context drift** and **cognitive overload** ("AI brain fry"):
- Subtasks get abandoned or forgotten when jumping into a rabbit hole.
- Long-running sessions lose track of earlier completed goals when moving to the next initiative.
- Deep debugging loops cause context window compaction, wiping out memory of original objectives.

`/sidequest` solves this by maintaining an organic, multi-tiered visual map (`sidequest.md`) in session memory, keeping both human and agent anchored without adding friction or bloat.

---

## When to use this skill
- When the user explicitly invokes `/sidequest` or `/sidequest rebuild`.
- When the user asks *"where are we right now?"*, *"what's on our stack?"*, or *"what were we originally working on?"*.
- When an interruption, unexpected blocker, or new topic causes the conversation to branch away from the active task.

---

## 🏗️ Core Architecture & Zero Repo Pollution

### Session-Private Storage (`sidequest.md`)
Whenever `/sidequest` generates or updates the map, it writes **exclusively** to the session's artifact directory as `sidequest.md` (the exact session directory is dynamically provided at runtime).

> [!IMPORTANT]
> **Zero Repo Pollution:** This file exists purely inside the agent's session memory on disk. It **never** touches user repositories (`//depot/google3/...`, `~/github/...`, or `~/.dotfiles`), completely eliminating untracked git/hg/jj file warnings, presubmit failures, or accidental check-ins.

Because the file is persisted to disk in the session folder, if the conversation undergoes **context compaction** (due to large log outputs or long turns), the agent can instantly re-read `sidequest.md` to recover exact task hierarchy without losing state.

---

## 🎯 Multi-Quest Hierarchy (`Main -> Sub -> Side`)

Rather than restricting the map to a single rigid goal, `/sidequest` supports **Multiple Main Quests** across two natural patterns:

1. **Sequential Quests (Chapter Progression):** When Main Quest 1 finishes completely (committed/pushed/merged), the agent marks it `✅ [COMPLETED]` and opens **Main Quest 2** as the new active chapter. This builds a clean chronological ledger of everything achieved across the session.
2. **Concurrent Quests (Parallel Tracks):** While waiting on a 30-minute CI/presubmit run for Main Quest 1 (`⏸️ [PAUSED / WAITING ON CI]`), the user can pivot to start an independent major initiative (Main Quest 2 `🎯 [ACTIVE HEAD]`). Both coexist cleanly without subordinating parallel work.

### The 3-Tier Hierarchy
- **🎯 Main Quests:** High-level initiatives or major chapters (e.g., *Migrate UserService to v2*, *Investigate Bazel Thread Leak*).
- **📂 Sub-Quests:** The logical milestones and planned phases needed to complete a Main Quest.
- **🐇 Side Quests:** Interstitial blockers (presubmit failures, missing dependencies) or ideas/questions meandered into along the way.

---

## 🚀 Execution Workflow & Procedures

When `/sidequest` triggers (either via explicit command, user question, or conversational branching), follow this exact decision workflow:

1. **Determine Execution Mode:**
   - **Is this the very first `/sidequest` check, or did the user explicitly request `/sidequest rebuild`?** → Execute **Mode B (Subagent Rebuild)** below.
   - **Does `sidequest.md` already exist, and either a task progressed OR the user invoked `/sidequest` mid-session?** → Execute **Mode A (In-Session Delta Update & Summary)** below.

---

### Mode A: Rolling Ledger Delta Updates (In-Session `O(1)`)
When an existing `sidequest.md` is active and a task progresses, completes, meanders, or `/sidequest` is explicitly invoked:
1. **Do NOT re-read `transcript.jsonl` or conversation history.**
2. Use `replace_file_content` (or standard file edit tools) directly on `sidequest.md` in the session's artifact directory to perform surgical updates:
   - **Progress:** Mark sub-quests or side quests from `[ ]` to `[x] **Sub-Quest N:** ... -> *Done/PR link*`.
   - **New Side Quest:** Append new blockers or digressions under `### 🐇 Active & Parked Side Quests`.
   - **Chapter Completion:** When a Main Quest is merged/committed, update its header from `🎯 [ACTIVE HEAD]` to `✅ [COMPLETED]`, and open the next `🎯 [ACTIVE HEAD] Main Quest` below it.
3. **Explicit Command Response:** If the user invoked `/sidequest` directly, after performing any pending updates on `sidequest.md`, output a **brief, punchy chat summary** highlighting:
   - Our active `🎯 Main Quest` and current `[ACTIVE HEAD]` sub-quest.
   - Any open or parked `🐇 Side Quests`.
   - Our immediate recommended next step.

---

### Mode B: Subagent Transcript Audit (`/sidequest rebuild`)
To rebuild or initialize the map without burning main-session tokens or pausing the conversation:
1. **Spawn a Background Auditor**: Spawn a background subagent using `invoke_subagent` (or equivalent platform-native multi-agent creation tool).
   - **Antigravity Setup**: Use `TypeName: "self"`, `Role: "Sidequest Log Auditor"`, and provide the prompt below.
   - **Fallback (Harnesses without Multi-Agent APIs)**: If the harness does not support spawning background subagents (like Claude Code), the agent should run the audit synchronously or perform a direct view/write of the transcript files in the session directory.
2. **Subagent Prompt Configuration**:
   Use this self-contained prompt:
   ```
   You are a background Sidequest Log Auditor. Your sole job is to inspect the full conversation transcript in the session's log directory and build/rebuild the visual hierarchy map.

   1. Inspect `transcript.jsonl` using `view_file` (or search tools) to extract all major initiatives (Main Quests), sub-tasks (Sub-Quests), and digressions/blockers (Side Quests).
   2. Format the findings strictly using the 3-Tier Hierarchy (`🎯 Main Quests`, `📂 Sub-Quests`, `🐇 Side Quests`) and status tags (`✅ [COMPLETED]`, `🎯 [ACTIVE HEAD]`, `⏸️ [PAUSED]`, `[Active]`, `[Parked / Tracked for Later]`).
   3. Write the finalized markdown hierarchy map using `write_to_file` (with `Overwrite: true`) to `sidequest.md` in the session's artifact directory.
   4. When done, notify your parent agent. (In Antigravity, call the `send_message` tool targeting the parent's conversation ID, confirming completion and providing the exact absolute path where `sidequest.md` was written. In harnesses without messaging, print the path to stdout or write it to a `.handshake` file in the session's artifact directory).
   ```
3. **Continue Main Session**: Keep your primary context clean and continue pair programming with the user immediately while the subagent runs asynchronously (if supported).
4. **Parent Handshake & UI Availability**: When the subagent sends its completion notification (or the background process completes):
   - In Antigravity, after receiving the `send_message` notification confirming the absolute path, the parent agent MUST immediately read the file's content and write it into the conversation artifacts directory as `sidequest.md` using `write_to_file` (or copy it directly).
   - If running synchronously, copy the compiled file to the conversation's active artifact path so it's immediately available to the user.

---

## 🤝 Multi-Session Handshake (Context-Specific Issue Trackers)

While `sidequest.md` handles in-session digressions cleanly, some side quests cannot be resolved in one sitting (e.g., waiting on external team reviews, security approvals, or multi-day refactors).

For items marked **`[Parked / Tracked for Later]`** in `sidequest.md`, the skill bridges seamlessly into your existing persistence tools:
1. **Inspect Available Trackers:** The agent checks what issue tracking tools, CLIs, or skills exist in the user's active environment (e.g., `gh issue create` for GitHub repositories, local issue tracking skills, or project management frameworks).
2. **Prompt to Escalate:** When parking a side quest, the agent gently prompts:
   > *"Would you like me to file a quick issue in your project's issue tracker (`gh issue` / local tracker) so this parked item survives across sessions?"*

---

## 💬 Ongoing Conversational Behavior

Once `sidequest.md` exists, the agent adopts a helpful, low-friction discipline:
- **No Heavy Pushback:** When the user pivots across files or topics, acknowledge it smoothly: *"Oh, we're going off on a sidequest, that's completely fine."*
- **Gentle Triage Prompts:** When a new unexpected blocker or rabbit hole emerges (e.g., a broken build or linter warning), ask:
  > *"We're diving into a sidequest to fix this dependency—that's totally fine. Should we tackle it right now, or track it in our artifact?"*
  > *"Should we fix this right now, or would you like me to file an issue in your tracker (`gh issue`) for later?"*
- **Chapter-Break Awareness:** When a major PR is pushed or a task completes and the user introduces a new topic, recognize the chapter break:
  > *"Looks like we finished Main Quest 1! Should we open a new Main Quest in our map for this new topic, or is this just a quick sidequest?"*

---

## 📄 Template: `sidequest.md`

```markdown
# 🗺️ Conversation Map & Sidequests

## ✅ [COMPLETED] Main Quest 1: Migrate `UserService` to `v2` API
* [x] **Sub-Quest 1:** Identify callers across repository -> *Done*
* [x] **Sub-Quest 2:** Update client stub bindings -> *Merged in PR #142*
* [x] **Side Quest:** Fix build missing `proto/public` dep -> *Resolved*

---

## 🎯 [ACTIVE HEAD] Main Quest 2: Investigate Thread Leak Issue
* [x] **Sub-Quest 1:** Check configuration and reproduce reproduction test case
* [ ] **Sub-Quest 2:** Profile thread spawning across workers *(IN PROGRESS)*

### 🐇 Active & Parked Side Quests (For Main Quest 2)
* [ ] **[Active]** Check why debug flag behaves differently on local vs remote machine.
* [ ] **[Parked / Tracked for Later]** Refactor `LegacyThreadMonitor` -> *Filed Issue #215 in project tracker*

---

## ⏸️ [PAUSED] Main Quest 3: Code Review for PR #27
* [ ] **Status:** Waiting on author reply to our comment on line 142.
```
