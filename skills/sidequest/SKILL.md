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

## ⚠️ Mandatory Execution Contract (6 Core Rules)

1. **Tool-Driven State Updates:** Always update state via the CLI tool
   (`sidequest`). Never edit `sidequest.json` manually.
2. **Tool-Driven Map Compilation:** Always generate/compile `sidequest.md` via
   `sidequest`. Never format the markdown map by hand.
3. **Strict Internal Privacy:** **NEVER** mention or reference `sidequest.json`
   in user-facing conversation. Treat JSON state as a private implementation
   detail.
4. **Markdown User Interface:** Always reference `sidequest.md` or provide
   concise inline markdown summaries when communicating progress to the human.
5. **Subagent History Ingestion:** Never read `transcript.jsonl` directly in the
   main conversation; delegate deep history rebuilds exclusively via
   `/sidequest rebuild`.
6. **Ground-Truth Scope Invariant (Discussed Work Only; Zero Speculation):**
   `sidequest.md` must capture **all** active, completed, and pending/upcoming
   work that has been **explicitly discussed, proposed, or referenced in the
   chat or session artifacts**. Never invent, extrapolate, or add un-discussed
   speculative tasks into `sidequest.json` / `sidequest.md`. Offer new,
   un-discussed suggestions exclusively in the **chat window**, never in the
   sidequest map.

---

## 🎯 Scope & Epistemic Boundaries (Ground-Truth Mandate)

When `/sidequest` is invoked, maintain a strict boundary between **recorded
session state** (`sidequest.md`) and **new agent suggestions** (chat reply):

### ✅ What MUST Be Included in `sidequest.md`

1. **Completed & In-Flight Work:** Every Main Quest, Sub-Quest, Step, Blocker,
   and Side Quest executed or actively in progress during the session.
2. **Discussed Pending & Remaining Work:** Every upcoming task, deferred
   follow-up, open action item, or parked side quest that has **already been
   discussed with the human operator, proposed by the agent in prior turns, or
   documented in session artifacts** (e.g., plans, triage reports, design docs).
   Before updating the map, check prior chat turns and session artifacts so
   discussed pending items are never left out.

### 🚫 What MUST Be Excluded from `sidequest.md` (Chat-Only Boundary)

1. **Zero Artifact Speculation:** Invoking `/sidequest` must **never** inspire
   the agent to brainstorm or invent new steps, sub-quests, or follow-ups inside
   `sidequest.md` that have not yet been discussed or proposed in the session.
2. **New Suggestions Belong in Chat:** If you identify additional work or
   optional follow-ups worth proposing, state them clearly in the **chat
   window** (e.g., _"Separate from our mapped tasks, we could also
   consider..."_). Only add them to `sidequest.md` after they have been
   discussed in chat.

---

## 🏗️ Storage & Architecture

- **Session-Private Artifacts:** All state files (`sidequest.json`,
  `sidequest.md`) reside strictly in the session artifact directory
  (auto-discovered via `ANTIGRAVITY_CONVERSATION_ID`, `CLAUDE_ARTIFACT_DIR`,
  `GEMINI_ARTIFACT_DIR`, or `--dir`). Never write to user repositories or
  dotfiles.
- **Compaction Resilient:** `sidequest.json` maintains the deterministic state
  model (quests, completion orders, VCS state, step watermark) across context
  truncations.

---

## 🧭 Hierarchy & Syntax Specification

| Level          | Syntax / Prefix            | Description                          | Status Indicators                                                      |
| :------------- | :------------------------- | :----------------------------------- | :--------------------------------------------------------------------- |
| **Main Quest** | `Main Quest N:`            | High-level initiatives / chapters    | `⚔️ [ACTIVE HEAD]`, `🏆 [COMPLETED]`, `⏸️ [PAUSED]`                    |
| **Sub-Quest**  | `Sub-Quest N.M:`           | Planned milestones                   | `[ ] 🛡️` (Pending), `[-] 🛡️ *(IN PROGRESS)*`, `[x] 🛡️ -> *Done*`      |
| **Blocker**    | `Blocker N.M.K:`           | Critical-path unplanned blocker      | `[-] ⚡ 👾 *(IN PROGRESS)*`, `[ ] 👾` (Pending), `[x] 💀 ~~Resolved~~` |
| **Step**       | `Step N.M.K:`              | Planned action item                  | `[ ] 👣` (Pending), `[-] ⚡ 👣 *(IN PROGRESS)*`, `[x] 👣 ~~Done~~`     |
| **Side Quest** | `[Active]` / `🎒 [Parked]` | Tangents / rabbit holes (`G1`, `S1`) | `🌿`                                                                   |

- **Pending (`[ ]`) vs. In-Progress (`[-]`)**:
  - Newly added `Sub-Quest` and `Step` items default to `pending` (`[ ]`) so mapped-out roadmaps represent upcoming work without false "in-progress" noise.
  - Only mark the actively executing `Sub-Quest` and `Step` as `in_progress` (`[-]`) using `sidequest start <id...>` (or `--start` on `add`). Starting a child `Step` automatically promotes its parent `Sub-Quest` from `pending` to `in_progress`.
- **Completion Order (`[#N ⭐]`):** Completed items receive sequential tags
  (`[#1]`, `[#2]`). The most recently completed item receives the star
  (`[#N ⭐]`).
- **VCS Lifecycle:** Track working copy state per quest: `📝 Dirty` ->
  `📦 Local Commit` -> `🚀 Uploaded` -> `🎉 Merged` -> `🧹 Clean`.

---

## 🚀 Execution Workflow

When `/sidequest` triggers (via `/sidequest`, "where are we?", or context
drift):

### Mode A: In-Session CLI Mutation (Default `O(1)`)

Execute `sidequest` (or `dart run <path-to-skill>/bin/sidequest.dart`):

```bash
# 1. Inspect Current State (Outputs compact overview to stdout)
sidequest status

# 2. Initialize or Add Quests, Sub-Quests, Steps, Blockers
#    (Sub-Quests & Steps default to `pending`; pass `--start` if executing immediately)
sidequest init "Title"
sidequest subquest add 1 "UI Implementation" [--start]
sidequest step add 1.1 "Draft UI widget" [--start]
sidequest blocker add 1.1 "Broken build dependency"
sidequest sidequest add "Tangent item" [--global] [--parked] [--note="..."]

# 3. Start Pending Items When Active Execution Begins
sidequest start 1.1 1.1.1

# 4. Batch Operations (Atomic multi-item execution in a single call)
sidequest batch '[{"type":"subquest_add","quest":"1","title":"Backend"},{"type":"step_add","subquest":"1.2","title":"API client","status":"pending"},{"type":"start","ids":["1.1.1"]}]'

# 5. Complete One or Multiple Items (Atomic disk write & star update)
sidequest complete 1.1.1 1.1.2 1.1

# 6. Update VCS Lifecycle
sidequest vcs 1 --stage=dirty|local_commit|uploaded|merged|clean [--branch=B] [--files=F]

# 7. Reopen (reverts to `pending`) or Remove
sidequest reopen 1.1
sidequest remove 1.1.2
```

**User Output:** Output a brief, punchy chat summary covering active
`⚔️ Main Quest`, current `🛡️ Sub-Quest`, VCS status, and next discussed step. If
proposing any new, un-discussed ideas, present them strictly in chat (never
inside `sidequest.md`). Always place the clickable link to the generated
artifact at the very **BOTTOM** of the chat reply with an emoji anchor so it is
easy to find and click:

> `🗺️ Full Session Map: [sidequest.md](file:///path/to/sidequest.md)`

### Mode B: Subagent Transcript Rebuild (`/sidequest rebuild`)

Use **only** when initializing from long unmapped history or explicitly
requested via `/sidequest rebuild`:

1. **Spawn Auditor Subagent:** `TypeName: "research"`,
   `Role: "Sidequest Log Auditor"`, passing baseline `sidequest.json` and
   [auditor_prompt.txt](resources/auditor_prompt.txt).
2. **Delta Audit:** Subagent inspects `transcript.jsonl` from
   `watermark.stepIndex` onwards and returns audited JSON payload in
   `send_message`.
3. **Merge & Emit:** Parent runs `sidequest merge-audit --input=<payload_file>`
   to update JSON and compile `sidequest.md`.

---

## 🤝 Parked Item Escalation

When parking side quests (`🎒 [Parked / Tracked for Later]`), check available
issue trackers and offer:

> _"Would you like me to file an issue in your project tracker
> (`gh issue create` / local tracker) so this parked item survives across
> sessions?"_
