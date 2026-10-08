---
name: slice-and-dice
description: >-
  Walks through multi-part documents, proposals, technical audits, or code
  architectures sequentially in bite-sized (~60-second) slices ([SND 1/N] ..
  [SND N/N]) with a persistent progress tracker, primary-source verification,
  and dynamic plan updates. Use when reviewing, co-editing, or learning from a
  dense document, RFC, plan, or audit section-by-section without cognitive
  overload, or when invoked via /slice-and-dice, /slice-n-dice, /snd, "slice
  and dice", or "slice-n-dice". Don't use for single-turn answers (use
  quick-question), prerequisite-graph domain mastery from first principles (use
  graph-learn), pre-drafting Socratic quizzes (use
  distilling-strategies-interactively), or one-shot automated PR diff reports
  (use pr-review).
key_features:
  - Sequential ~60-second slices ([SND 1/N]) with persistent artifact state tracking
  - Pre-flight scope gate when natural slicing exceeds 10 slices
  - Zero blocking choice modals during active slice review ("skip" = defer, never delete)
  - Before/After + What Changed edit deltas and split-anchor review comments
  - Dynamic plan evolution with explicit upfront realization callouts
---

# Slice-and-Dice (`SND`)

Walk through dense documents, multi-part proposals, technical audits, or complex
codebases one bite-sized slice at a time (`[SND 1/N]` .. `[SND N/N]`). Partition
the work into **sequential `~60-second` slices optimized for reasonable
completeness** (1 coherent topic per slice) and lock each slice interactively
before advancing.

> [!IMPORTANT]
>
> **Turn Templates**: Read
> [`references/slice_templates.md`](references/slice_templates.md) for the exact
> Mode 2 (`Before` → `After` + `What Changed`) and Mode 1 (Document Review with
> Upfront Realization & Split Anchors) turn skeletons.

---

## Workflow Overview

- [ ] **Phase 1: Partition, Scope Gate (if `N > 10`), & Stage** → Partition the
      target into coherent `~60-second` single-topic slices (`[SND 1/N]` ..
      `[SND N/N]`). If `N > 10` (unless the user waives the limit), halt at the
      Pre-Flight Scope Gate; otherwise stage the persistent working artifact and
      present **only `[SND 1/N]`**.
- [ ] **Phase 2: Single-Slice Review Loop** → Present the active slice with
      exact deep-links, primary-source verification, and properly formatted
      deltas or comments; yield in plain chat.
- [ ] **Phase 3: Dynamic Plan Evolution** → Adapt slices on the fly in the
      working artifact's Progress Tracker as the user steers or as you
      independently discover new facts (stating any independent realizations or
      plan updates **explicitly upfront**).
- [ ] **Phase 4: Lock, Defer (`"skip"`), & Wrap-Up** → Flip confirmed slices to
      `☑️` (**Locked**), mark `"skip"` slices `⏭️` (**Deferred — revisit
      later**), advance to `[SND K+1/N]`, and cycle back through any `⏭️`
      deferred slices or open questions when `[SND N/N]` locks.

---

## Choosing the Right `SND` Mode

| Mode                                      | Typical User Prompt                                          | What Each `[SND K/N]` Slice Contains                                                                       |
| :---------------------------------------- | :----------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| **1. Document / Proposal Review**         | _"Walk me through this RFC / API doc with SND"_              | Exact anchor quote + primary-source check + copy-pasteable `text` comment(s) (or **"No comment needed"**). |
| **2. Co-Authoring & Iterative Editing**   | _"Break these edits / proposals into an SND"_                | Target section link + **`Before` → `After` + `What Changed`** (`Added` / `Changed` / `Removed`) delta.     |
| **3. Technical Walkthrough ("Teach Me")** | _"Do a slice-n-dice over these issues teaching me as we go"_ | Focused explanation + primary-source code snippets + space for deep-dive Q&A before locking.               |

---

## Core Protocol & Invariants

### 1. Completeness-Driven `~60-Second` Slices (`1 Topic per Slice`) & The `N > 10` Scope Gate

- **Size by Cognitive Unit (`1 Topic per Slice`), Not Arbitrary Quota**:
  - Partition the target top-to-bottom so each slice (`[SND 1/N]` ..
    `[SND N/N]`) covers **one coherent topic or decision** sized to roughly **60
    seconds** of reading and reaction.
  - Never force a large document into an arbitrary fixed slice count by bundling
    orthogonal topics into `A`/`B`/`C` sub-slices or dropping sections.
- **Pre-Flight Scope Gate When `N > 10` (Unless Waived by User)**:
  - If natural `~60-second` slicing yields **`N <= 10`** (or the user explicitly
    asks to ignore the limit), stage the working artifact and present
    `[SND 1/N]` immediately.
  - If **`N > 10`**, **halt before starting `[SND 1/N]`**, show the grouped
    slice outline, and prompt with three options:
    1. `(Recommended) Focus on {sub_area} first ({k} slices)` — full fidelity on
       the highest-leverage area first.
    2. `Run a high-level Macro-SND across the whole target (~6–8 architectural slices)`.
    3. `Proceed with all {n} slices in one pass` — explicit escape hatch.

### 2. Persistent Working Artifact as State of Truth

- Pin the canonical **Slice-and-Dice (`SND`) Progress Tracker** at the top of a
  persistent working Markdown artifact (in the session artifact directory or
  `/tmp/snd_plan_<slug>.md` in standalone CLI sessions—never create untracked
  files in the repository worktree).
- **Lazy Slice Drafting**: Record only the Progress Tracker and 1-line slice
  titles on Turn 1. Draft each slice's full `Before`/`After` delta or review
  comments lazily when `[SND K/N]` becomes active.
- Update the working artifact's Progress Tracker before each response and echo
  it at the top of every chat turn:
  - `☑️ [SND 1/N] {slice_title}` — **Locked**
  - `⏭️ [SND 2/N] {slice_title}` — **Skipped (Deferred — revisit later)**
  - **`[-] [SND 3/N] {slice_title}`** 👈 _Reviewing now_
  - `[ ] [SND 4/N] {slice_title}`

### 3. Zero Blocking Choice Modals During the Active Slice Loop

- Once `[SND 1/N]` begins, **never** block an active `SND` turn with an
  interactive multiple-choice modal tool (`ask_question`, `AskUserQuestion`).
- Blocking modals prevent the user from quoting inline lines, asking "why"
  questions, or replying with quick shorthands (`"next"`, `"skip"`, `"drop"`).
- Always end active slice turns in plain chat with a one-line prompt (e.g.,
  _`How does [SND 2/5] look? Reply with tweaks, "skip" to defer for later, "drop" to discard, or "next".`_).

### 4. Single-Slice Focus & Deep-Link Anchoring

- Present **only the active `[-] [SND K/N]` slice** in chat per turn.
- Anchor every active slice with clickable deep-links:
  - **Local / Repo File or Working Artifact**: Exact line-range links
    (`path/to/file.md#L18-L32`).
  - **External Document (Web Doc / RFC / Issue)**: Exact section heading URL
    (`#heading=...`) plus a verbatim **📌 Exact Text to Anchor On** quote.

### 5. Primary-Source Grounding & Explicit `"No Comment Needed"` Slices

- Verify every technical claim directly against primary source code before
  presenting a slice's critique, proposed edit, or explanation.
- If primary-source inspection confirms the target document's claim holds up (or
  shows a proposed change is already present), mark the slice
  **`✅ Verdict: No comment needed (holds up in source)`** and cite the
  verifying code.

### 6. Formatting Candidate Edits & Review Comments

- **Candidate Text Replacements (`Before` → `After` + `What Changed`)**:
  - Never show `After` in isolation. Always present: (1) **Current Text
    (`Before`)**, (2) **Proposed Text (`After`)**, and (3) **What Changed
    (`Added` / `Changed` / `Removed`)**.
- **Candidate Review Comments (`text` Fence & Split Anchors)**:
  - Format candidate review comments inside a copy-pasteable `text` code fence
    with **blank lines between paragraphs or numbered points**.
  - When a slice surfaces two distinct points that map to different sentences in
    the target document, split them into `Comment KA` and `Comment KB` with
    separate verbatim anchor phrases.

---

## Dynamic Plan Evolution (User-Driven & Agent-Driven)

### User-Driven Steering Mid-Walkthrough

1. **Zooming In ("Staying in `[SND K/N]`")**: Keep `[SND K/N]` marked `[-]`
   while unpacking follow-up questions or code details until the user signals
   `"next"`.
2. **Splitting, Merging, or Re-Slicing (Keeping `1..N` Stable)**: Keep base
   slice numbers `1..N` stable once `[SND 1/N]` begins; use letter suffixes
   (`2A`, `2B`) only if a single slice splits mid-discussion, or mark moot later
   slices inline as `*(Merged into [SND K/N])*`.
3. **Cross-Slice Ripple Notes & Deferred Open Questions**: Append inline
   reminders (`*(Reminder: align with Section 1)*`) or `*(1 Open Question)*`
   tags directly onto the Progress Tracker.

### Agent-Driven Realizations & Proactive Plan Updates

> [!IMPORTANT]
>
> **State Independent Realizations & Plan Updates Explicitly Upfront**: Whenever
> you overturn an earlier draft point or update remaining slices (`[SND K..N]`)
> based on primary-source verification, place an explicit **Realization / Plan
> Update** callout right under the Progress Tracker stating: (1) what you
> realized (with source citation), (2) which slice was updated, and (3) asking
> before reopening any already-locked (`☑️`) slice.

---

## Lock, Defer (`"skip"`), & Wrap-Up

- **Applying Confirmed Edits (Mode 2)**: When the user confirms `[SND K/N]`
  (`"next"`, `"apply"`, `"looks good"`), flip `[SND K/N]` to `☑️` (**Locked**)
  and advance to `[SND K+1/N]` (writing approved edits per slice or in a single
  verified batch at the end of the walkthrough).
- **Skipping = Defer to Revisit Later (Never Delete)**: When the user replies
  `"skip"` on `[SND K/N]`, mark it
  `⏭️ [SND K/N] {slice_title} — **Skipped (Deferred — revisit later)**` in the
  Progress Tracker and advance immediately to `[SND K+1/N]`. Skipping never
  deletes or discards a topic—only an explicit `"drop"` / `"discard"` drops a
  proposed change.
- **Closing `[SND N/N]`**: After `[SND N/N]` locks, cycle back through any `⏭️`
  deferred slices and `*(1 Open Question)*` callouts, and remove any temporary
  `/tmp/snd_plan_<slug>.md` scratch file.
