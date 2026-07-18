---
name: sidequest
description: >-
  Synthesizes conversation history and active tasks into a visual hierarchy map
  (`sidequest.md`) backed by a deterministic JSON state file (`sidequest.json`).
  Supports multiple sequential and concurrent main quests, sub-quests, and
  side-quests with automatic hierarchical numbering and completion sequencing.
  Use when the user invokes `/sidequest`, asks where we are, what we were doing,
  or what's on our stack, or when the conversation branches across multiple
  topics, blockers, or digressions. Don't use for simple one-off questions that
  don't involve multi-step work or task hierarchy management.
key_features:
  - Conversation mapping
  - Task hierarchy & numbering
  - Chronological completion tracking
  - JSON-first CLI automation
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

`/sidequest` maintains a deterministic JSON data model (`sidequest.json`) and an
organic, multi-tiered visual map (`sidequest.md`) in session memory, keeping
both human and agent anchored without adding friction or bloat.

---

## When to use this skill
- When the user explicitly invokes `/sidequest` or `/sidequest rebuild`.
- When the user asks *"where are we right now?"*, *"what's on our stack?"*, or
  *"what were we originally working on?"*.
- When an interruption, unexpected blocker, or new topic causes the conversation
  to branch away from the active task.

---

## 🏗️ Core Architecture & Zero Repo Pollution

### Session-Private Storage (`sidequest.json` & `sidequest.md`)
Whenever `/sidequest` generates or updates the map, it writes **exclusively**
to the session's artifact directory as `sidequest.json` and `sidequest.md` (the
exact session directory is dynamically provided at runtime).

> [!IMPORTANT]
> **Zero Repo Pollution:** These files exist purely inside the agent's session
> memory on disk. They **never** touch user repositories (`//depot/google3/...`,
> `~/github/...`, or `~/.dotfiles`), completely eliminating untracked git/hg/jj
> file warnings, presubmit failures, or accidental check-ins.

Because the state is persisted as structured JSON on disk in the session folder,
if the conversation undergoes **context compaction** (due to large log outputs
or long turns), the agent can instantly re-read or mutate state without losing
history or corrupting markdown formatting.

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

### The 3-Tier Hierarchy & Hierarchical Numbering
- **⚔️/🏆/⏸️ Main Quests:** High-level initiatives or major chapters (e.g.,
  *Main Quest 1: Migrate UserService to v2*, *Main Quest 2: Investigate Thread Leak*).
- **🛡️ Sub-Quests:** The logical milestones and planned phases needed to
  complete a Main Quest. Formatted with fully-qualified dot-separated numbering
  (e.g., `Sub-Quest 1.1`, `Sub-Quest 2.1`).
  - Critical-path unplanned tasks (e.g. build errors, test failures, minor
    blockers) or steps are nested **directly under** the corresponding
    Sub-Quest with dot-separated hierarchical IDs (e.g. `1.1.1`, `1.1.2`):
    - `👾 *Blocker 1.1.1:* <description>`: An active critical-path blocker.
    - `💀 ~~*Blocker 1.1.1:* <description>~~ -> *Resolved*`: A vanquished blocker,
      visually slain with strikethrough and a skull emoji (`💀`).
    - `👣 *Step 1.1.2:* <description>`: A planned step/action item.
    - `👣 ~~*Step 1.1.2:* <description>~~ -> *Done*`: A completed step, formatted
      with strikethrough.
- **🌿 Side Quests:** ONLY completely unrelated or out-of-scope tasks, tangents,
  or context drift. These are the rabbit holes that branch away from the main
  mission. Global side quests use `G1`, `G2`; quest-specific ones use `S1`, `S2`.

### 🔢 Chronological Completion Order & Recent Work Star (`[#N ⭐]`)
Whenever any task, blocker, sub-quest, or side quest is completed:
- It receives a sequential completion order tag: `[#1]`, `[#2]`, `[#3]`.
- The **most recently completed** item across the entire session displays the
  star indicator next to its order tag (`[#N ⭐]`), allowing humans and agents
  to pinpoint the latest milestone at a single glance.

### 📦 Version Control (VCS) State Integration
To prevent divergent state confusion and accidental amends in stacked-commit
workflows (e.g. `jj`, Gerrit, Git branches):
- Track the VCS status of modified files directly in `sidequest.json` alongside
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
   - **Does `sidequest.json` already exist, and either a task progressed OR the
     user invoked `/sidequest` mid-session?** → Execute **Mode A (Deterministic
     CLI Updates)** below.

---

### Mode A: Deterministic CLI Updates (In-Session `O(1)`)
When an existing `sidequest.json` is active and a task progresses, completes,
meanders, or `/sidequest` is explicitly invoked:
1. **Do NOT re-read `transcript.jsonl` or generate multi-line markdown diffs.**
2. Run the lightweight Dart CLI tool via `run_command`:
   ```bash
   dart run skills/sidequest/bin/sidequest.dart <subcommand> --dir="<session_artifact_dir>"
   ```
   *(Or set `JETSKI_ARTIFACT_DIR` environment variable).*

#### Common CLI Subcommands:
- **Initialize**: `dart run skills/sidequest/bin/sidequest.dart init "Quest Title"`
- **Add Main Quest**: `dart run skills/sidequest/bin/sidequest.dart quest add "Title"`
- **Add Sub-Quest**: `dart run skills/sidequest/bin/sidequest.dart subquest add 1 "Title"`
- **Add Step / Blocker**:
  - `dart run skills/sidequest/bin/sidequest.dart step add 1.1 "Run tests"`
  - `dart run skills/sidequest/bin/sidequest.dart blocker add 1.1 "Build failure"`
- **Add Side Quest**: `dart run skills/sidequest/bin/sidequest.dart sidequest add "Fix typo" [--global] [--parked]`
- **Complete Item**: `dart run skills/sidequest/bin/sidequest.dart complete 1.1.1`
  *(Automatically updates `lastCompletionOrder`, tags item `[#N ⭐]`, strips the star
  from the previous completed item, and emits `sidequest.md`).*
- **Update VCS State**:
  `dart run skills/sidequest/bin/sidequest.dart vcs 1 --stage=dirty --branch=fix-leak --files="lib/a.dart"`
- **Batch Updates (Multi-mutation in 1 turn)**:
  `dart run skills/sidequest/bin/sidequest.dart batch '{"complete":["1.1.1"],"vcs":{"quest":"1","stage":"dirty"}}'`

3. **Explicit Command Response:** If the user invoked `/sidequest` directly,
   output a **brief, punchy chat summary** highlighting:
   - Our active `⚔️ Main Quest` and current active `🛡️` sub-quest (marked
     `*(IN PROGRESS)*`).
   - Active VCS/working copy status (dirty files, active commit/branch).
   - Any open or parked `🌿 Side Quests`.
   - Our immediate recommended next step.

---

### Mode B: Subagent Transcript Audit (`/sidequest rebuild`)
To rebuild or initialize the map without burning main-session tokens or pausing
the conversation:
1. **Pass Baseline JSON to Auditor**: Read the existing `sidequest.json` (if present)
   and pass its content as the baseline to a background subagent using `invoke_subagent`.
   - **Setup**: `TypeName: "research"`, `Role: "Sidequest Log Auditor"`.
   - **Subagent Prompt**: Read prompt instructions from
     [auditor_prompt.txt](resources/auditor_prompt.txt).
2. **Delta Transcript Audit**: The subagent inspects `transcript.jsonl` strictly
   for steps beyond the baseline `watermark.stepIndex`, preventing full-history re-parsing.
3. **Universal Read-Only Contract**: The subagent returns its audited JSON payload
   in its `send_message` completion notification.
4. **Parent Merge & Emission**: The parent agent receives the JSON payload, runs
   `dart run skills/sidequest/bin/sidequest.dart merge-audit --input=<payload_file>`,
   and automatically compiles the finalized `sidequest.md`.

---

## 🤝 Multi-Session Handshake (Context-Specific Issue Trackers)

For items marked **`🎒 [Parked / Tracked for Later]`** in `sidequest.json`, the
skill bridges seamlessly into your existing persistence tools:
1. **Inspect Available Trackers:** Check what issue tracking tools, CLIs, or
   skills exist in the user's active environment (e.g. `gh issue create`).
2. **Prompt to Escalate:** When parking a side quest, the agent gently prompts:
   > *"Would you like me to file a quick issue in your project's issue
   > tracker (`gh issue` / local tracker) so this parked item survives across
   > sessions?"*

---

## 📄 Template Reference

For a full reference of the visual hierarchy map, see
[sidequest_template.md](resources/sidequest_template.md).

