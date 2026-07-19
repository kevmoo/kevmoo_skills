---
name: sidequest
description: >-
  Synthesizes conversation history and active tasks into a visual hierarchy map
  (`sidequest.md`) backed by a deterministic JSON state file (`sidequest.json`).
  Supports multiple sequential and concurrent main quests, sub-quests, and
  side-quests with automatic hierarchical numbering and completion sequencing.
  Use when the user invokes `/sidequest`, asks where we are, what we were doing,
  or what's on our stack, or when the conversation branches across multiple
  topics, blockers, or digressions. Don't use for simple one-off questions.
key_features:
  - Conversation mapping
  - Task hierarchy & numbering
  - VCS state tracking
  - Subagent history audits
---

# 🧭 Sidequest (`/sidequest`)

Synthesizes task hierarchies and context drift into a visual session map.

## ⚠️ Mandatory Execution Contract (5 Core Rules)

1. **Tool-Driven State Updates:** Always update state via the CLI tool (`sidequest.dart`). Never edit `sidequest.json` manually.
2. **Tool-Driven Map Compilation:** Always generate/compile `sidequest.md` via `sidequest.dart`. Never format the markdown map by hand.
3. **Strict Internal Privacy:** **NEVER** mention or reference `sidequest.json` in user-facing conversation. Treat JSON state as a private implementation detail.
4. **Markdown User Interface:** Always reference `sidequest.md` or provide concise inline markdown summaries when communicating progress to the human.
5. **Subagent History Ingestion:** Never read `transcript.jsonl` directly in the main conversation; always delegate history parsing to an auditor subagent.

---

## 🏗️ Storage & Architecture

- **Session-Private Artifacts:** All state files (`sidequest.json`, `sidequest.md`) reside strictly in the session artifact directory. Never write to user repositories or dotfiles.
- **Compaction Resilient:** `sidequest.json` maintains the deterministic state model (quests, completion orders, VCS state, step watermark) across context truncations.

---

## 🧭 Hierarchy & Syntax Specification

| Level | Syntax / Prefix | Description | Status Indicators |
| :--- | :--- | :--- | :--- |
| **Main Quest** | `Main Quest N:` | High-level initiatives / chapters | `⚔️ [ACTIVE]`, `🏆 [COMPLETED]`, `⏸️ [PAUSED]` |
| **Sub-Quest** | `Sub-Quest N.M:` | Planned milestones | `🛡️` |
| **Blocker** | `Blocker N.M.K:` | Critical-path unplanned blocker | `👾 Active`, `💀 ~~Resolved~~` |
| **Step** | `Step N.M.K:` | Planned action item | `👣 Active`, `👣 ~~Done~~` |
| **Side Quest** | `[Active]` / `🎒 [Parked]` | Tangents / rabbit holes (`G1`, `S1`) | `🌿` |

- **Completion Order (`[#N ⭐]`):** Completed items receive sequential tags (`[#1]`, `[#2]`). The most recently completed item receives the star (`[#N ⭐]`).
- **VCS Lifecycle:** Track working copy state per quest: `📝 Dirty` -> `📦 Local Commit` -> `🚀 Uploaded` -> `🎉 Merged` -> `🧹 Clean`.

---

## 🚀 Execution Workflow

When `/sidequest` triggers (via `/sidequest`, "where are we?", or context drift):

### Mode A: In-Session CLI Mutation (Default `O(1)`)
Run the Dart CLI tool via `run_command` (`dart run skills/sidequest/bin/sidequest.dart <cmd> --dir="<session_artifact_dir>"`):
- `init "Quest Title"`: Initialize session map.
- `quest add "Title"`: Add a new main quest.
- `subquest add <quest_id> "Title"`: Add sub-quest (e.g. `subquest add 1 "UI"`).
- `step add <subquest_id> "Desc"` / `blocker add <subquest_id> "Desc"`: Add step/blocker.
- `sidequest add "Desc" [--global] [--parked]`: Add tangent/side quest.
- `complete <id>`: Mark item done (auto-updates `lastCompletionOrder`, sets `[#N ⭐]`, emits `sidequest.md`).
- `vcs <quest_id> --stage=dirty|local_commit|uploaded|merged|clean [--branch=B] [--files=F]`: Update VCS state.
- `batch '<json_payload>'`: Perform multiple mutations in 1 turn.

**User Output:** Output a brief, punchy chat summary covering active `⚔️ Main Quest`, current `🛡️ Sub-Quest`, VCS status, and recommended next step.

### Mode B: Subagent Transcript Audit (`/sidequest rebuild`)
Use when initializing from long history or explicitly requested via `/sidequest rebuild`:
1. **Spawn Auditor Subagent:** `TypeName: "research"`, `Role: "Sidequest Log Auditor"`, passing baseline `sidequest.json` and [auditor_prompt.txt](resources/auditor_prompt.txt).
2. **Delta Audit:** Subagent inspects `transcript.jsonl` from `watermark.stepIndex` onwards and returns audited JSON payload in `send_message`.
3. **Merge & Emit:** Parent runs `dart run skills/sidequest/bin/sidequest.dart merge-audit --input=<payload_file>` to update JSON and compile `sidequest.md`.

---

## 🤝 Parked Item Escalation

When parking side quests (`🎒 [Parked / Tracked for Later]`), check available issue trackers and offer:
> *"Would you like me to file an issue in your project tracker (`gh issue create` / local tracker) so this parked item survives across sessions?"*
