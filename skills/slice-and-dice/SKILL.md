---
name: slice-and-dice
description: >-
  Walks through multi-part documents, proposals, technical audits, issue
  backlogs, or code refactors in bite-sized (~60-second) slices ([SND 1/N] ..
  [SND N/N]) with topology-aware ordering, a persistent progress tracker,
  auditable Source anchors, and dynamic plan updates. Use when reviewing,
  co-editing, or triaging a dense document, RFC, plan, or audit slice-by-slice
  without cognitive overload, or when invoked via /slice-and-dice,
  /slice-n-dice, /snd, "slice and dice", or "slice-n-dice". Don't use for
  single-turn answers (use quick-question), learning a domain or verifying deep
  mental models (use teach-me), pre-drafting Socratic quizzes (use
  distilling-strategies-interactively), or one-shot automated PR diff reports
  (use pr-review).
key_features:
  - Topology-aware ~60-second slices ([SND 1/N]) with auditable Source anchors
  - Pre-flight scope gate when natural slicing exceeds 10 slices
  - Zero blocking choice modals during active slice review
  - Before/After + What Changed edit deltas and split-anchor review comments
  - Dynamic plan evolution with explicit upfront realization callouts
---

# Slice-and-Dice (`SND`)

Walk through dense documents, multi-part proposals, technical audits, or triage
lists one `~60-second` slice at a time (`[SND 1/N]` .. `[SND N/N]`), ordered by
the content's natural topology and locked interactively before advancing.

---

## Workflow Overview

- [ ] **Phase 1: Ground, Order by Topology, & Scope Gate (if `N > 10`)** →
      Partition into `~60-second` slices (`[SND 1/N]` .. `[SND N/N]`) with
      `Source` anchors. Halt at the Scope Gate if `N > 10`; otherwise stage the
      working artifact and present **only `[SND 1/N]`**.
- [ ] **Phase 2: Single-Slice Review Loop** → Present `[SND K/N]` with
      deep-links, source checks, and formatted deltas/comments (see
      [references/slice_templates.md](references/slice_templates.md)); yield in
      plain chat.
- [ ] **Phase 3: Dynamic Plan Evolution** → Update the tracker as the user
      steers or source checks surface new facts (state realizations
      **upfront**).
- [ ] **Phase 4: Lock, Defer (`"skip"`), & Wrap-Up** → Mark slices `☑️`
      (**Locked**), `⏭️` (**Skipped**), or `🗑️` (**Dropped**); cycle back
      through `⏭️` items after `[SND N/N]`.

---

## Shared 2×3 Goal-vs-Topology Matrix & `SND` Modes

Human conversation is linear (1 active item per turn), so `/slice-and-dice` and
`/teach-me` share the same 3 content topologies and state-tracking mechanics,
differing on **User Goal**:

| Content Topology                                   | `/slice-and-dice` (`SND` — Review / Co-Edit / Decide, Zero Quizzing)                                          | `/teach-me` (Learn / Verify First-Principles Mastery)                                                  |
| :------------------------------------------------- | :------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------- |
| **1. Document Order (Top-to-Bottom, `A → B → C`)** | Walks top-to-bottom through a narrative RFC or prose document (`[SND 1/N]` .. `[SND N/N]`).                   | Walks step-by-step through a linear mastery checklist (`[1/N]`) when `0` convergence nodes exist.      |
| **2. Thematic Clusters (`{A, B}, {C, D}`)**        | Groups scattered audit findings, issue backlogs, or multi-file refactors by theme or blast radius.            | Groups related concepts by subsystem (or scopes `> 12` concepts to one foundational cluster first).    |
| **3. Dependency / Gate Order (`A & B → C` DAG)**   | Orders foundational slices (`A`, `B`) before convergent slice `C` (with optional Mermaid dependency diagram). | Renders a live color-coded Mermaid prerequisite graph (`✅`, `🎯`, `🔒`) where `A` and `B` unlock `C`. |

Adapt each `[SND K/N]` slice payload to the review mode:

| Mode                                    | Typical User Prompt                                      | What Each `[SND K/N]` Slice Contains                                                                       |
| :-------------------------------------- | :------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| **1. Document / Proposal Review**       | _"Walk me through this RFC / API doc with SND"_          | Exact anchor quote + primary-source check + copy-pasteable `text` comment(s) (or **"No comment needed"**). |
| **2. Co-Authoring & Iterative Editing** | _"Break these edits / proposals into an SND"_            | Target `Source` link + **`Before` → `After` + `What Changed`** (`Added` / `Changed` / `Removed`) delta.    |
| **3. Multi-Item Audit / Issue Triage**  | _"Do a slice-n-dice over these audit findings / issues"_ | Thematic or dependency-ordered item + primary `Source` proof + concrete action/decision to lock.           |

---

## Core Protocol & Invariants

### 1. Completeness-Driven `~60-Second` Slices, Topology Ordering & The `N > 10` Scope Gate

- **Size (`~60s`) & Order by Topology**:
  - Partition the target so each slice (`[SND 1/N]` .. `[SND N/N]`) covers **one
    coherent topic or decision** sized to ~60 seconds of reading and reaction,
    optimizing for **reasonable completeness**. Never over-stuff orthogonal
    debates into one bloated slice or silently drop sections to keep `N` small;
    fold trivial 1-line fixes sharing a theme together.
  - Order slices by **1. Document Order (Top-to-Bottom)**, **2. Thematic
    Clusters**, or **3. Dependency / Gate Order** (ordering `>= 2` foundational
    upstream slices before a convergent downstream slice, with an optional
    Mermaid dependency diagram at the top of the working artifact).
- **Pre-Flight Scope Gate When `N > 10` (Unless Waived by User)**:
  - If natural `~60-second` slicing yields **`N <= 10`** (or the user waives the
    limit), stage the working artifact and present `[SND 1/N]` immediately.
  - If **`N > 10`**, **halt before starting `[SND 1/N]`**, show the grouped
    slice outline in chat, and prompt the user (via `ask_question` /
    `AskUserQuestion` if available, or a numbered list) with three options:
    1. `(Recommended) Focus on {sub_area} first ({k} slices)` — full fidelity on
       the highest-leverage area now; leave remaining areas for follow-up runs.
    2. `Run a high-level Macro-SND across the whole target (~6-8 architectural slices)`
       — one slice per major section or theme.
    3. `Proceed with all {n} slices in one pass` — explicit escape hatch.

### 2. Persistent Working Artifact & Auditable `Source` Anchors

- Pin the canonical **Slice-and-Dice (`SND`) Progress Tracker** (with each
  slice's **auditable `Source` anchor**—such as `path/to/file.ext#L18-L45` or
  `Doc §2.1`—plus locked states, ripple reminders, and open questions) at the
  top of a persistent working Markdown artifact (in the session artifact
  directory or `/tmp/snd_plan_<slug>.md` in standalone CLI sessions—never create
  untracked files in the repo worktree or inject tracker lines into tracked
  files).
- **Lazy Slice Drafting (Keep Turn 1 Fast)**: Record only the Progress Tracker
  (with `Source` anchors) and 1-line slice notes on Turn 1; draft each slice's
  full `Before`/`After` delta or review comments lazily when `[SND K/N]` is
  active.
- Update the working artifact's Progress Tracker before each response and echo
  it at the top of every chat turn:
  - `☑️ [SND 1/N] {title} (Source: {src})` — **Locked**
  - `⏭️ [SND 2/N] {title} (Source: {src})` — **Skipped (Deferred — revisit
    later)**
  - `🗑️ [SND 3/N] {title} (Source: {src})` — **Dropped (Discarded)**
  - **`[-] [SND 4/N] {title} (Source: {src})`** 👈 _Reviewing now_
  - `[ ] [SND 5/N] {title} (Source: {src})`

### 3. Single-Slice Focus, Deep-Link Anchors, & Zero Active-Loop Modals

- **One Active Slice per Turn**: Present **only `[-] [SND K/N]`** in chat; never
  dump the full content of upcoming slices (`[SND K+1..N]`).
- **Clickable Deep-Links**: Anchor local/repo slices with exact line ranges
  (`path/to/file.md#L18-L32`) and external web docs/RFCs with section heading
  URLs (`#heading=...`) plus a verbatim **📌 Exact Text to Anchor On** quote.
- **Zero Blocking Modals During Active Review**: Once `[SND 1/N]` begins,
  **never** call `ask_question` / `AskUserQuestion`—modals block inline quotes,
  "why" questions, and freeform shorthands. Always yield in plain chat (e.g.,
  _`How does [SND 2/5] look? Reply with tweaks, "skip" to defer, "drop" to discard, or "next".`_).

### 4. Primary-Source Grounding & Explicit `"No Comment Needed"` Slices

- Verify every technical claim directly against primary source code before
  presenting a slice's critique, proposed edit, or explanation. When the target
  document is self-contained (such as a standalone rollout plan or prose draft
  making no claims about external codebase files), read the named document
  directly via file-reading tools without running speculative `ls` or `git log`
  probes.
- If primary-source inspection confirms the target document's claim holds up (or
  overturns an earlier draft concern), **do not invent nitpicks**—mark the slice
  **`✅ Verdict: No comment needed (holds up in source)`** and cite the
  verifying code.

### 5. Formatting Candidate Edits & Review Comments

See [references/slice_templates.md](references/slice_templates.md) for complete
copy-pasteable Turn Templates for Mode 1 and Mode 2:

- **Candidate Text Replacements (`Before` → `After` + `What Changed`)**: Always
  present three parts—(1) **Current Text (`Before`)**, (2) **Proposed Text
  (`After`)**, and (3) **What Changed (`Added` / `Changed` / `Removed`)**—never
  `After` in isolation.
- **Candidate Review Comments (`text` Fence & Split Anchors)**: Format comments
  inside a copy-pasteable `text` code fence with blank lines between paragraphs.
  When a slice surfaces two distinct points on different sentences, split them
  into `Comment KA` and `Comment KB` with separate verbatim anchor quotes.

---

## Dynamic Plan Evolution & Lock / Defer / Wrap-Up

- **User-Driven Steering Mid-Walkthrough**:
  1. **Zooming In ("Stay in `[SND K/N]`")**: Keep `[SND K/N]` marked `[-]` while
     unpacking follow-up questions or code examples until the user says `"next"`
     or `"done"`.
  2. **Splitting or Merging (Keeping `1..N` Stable)**: Keep base slice numbers
     `1..N` stable once `[SND 1/N]` begins; use letter suffixes (`[SND 2A/5]`,
     `[SND 2B/5]`) if a slice splits, or mark moot later slices inline as
     `*(Merged into [SND K/N])*`.
  3. **Cross-Slice Ripple Notes & Open Questions**: Append inline reminders
     (`*(Reminder: align with Section 1)*`) or `*(1 Open Question)*` tags (with
     a `> [!WARNING]` callout in the working artifact) onto the tracker.
- **Agent-Driven Realizations (State Explicitly Upfront)**:
  - Whenever primary-source verification overturns an earlier draft point or
    reshapes remaining slices (`[SND K..N]`), place an explicit **Realization /
    Plan Update** callout right under the Progress Tracker stating: (1) what you
    realized (citing source code), (2) which slice was updated, and (3) asking
    before reopening any already-locked (`☑️`) slice.
- **Lock, Defer (`"skip"`), & Wrap-Up**:
  - **Confirm (`"next"`, `"apply"`, `"looks good"`)**: In Mode 2, write the
    approved `After` text to the target document (or apply in a verified batch
    at the end), flip `[SND K/N]` to `☑️` (**Locked**), and advance to
    `[SND K+1/N]`.
  - **Skip (`"skip"`) vs. Drop (`"drop"` / `"discard"`)**: On `"skip"`, mark the
    slice `⏭️ [SND K/N] {slice_title}` — **Skipped (Deferred — revisit later)**
    and advance to `[SND K+1/N]` (never deleting the topic). On `"drop"`, mark
    it `🗑️ [SND K/N] {slice_title}` — **Dropped (Discarded)** (keeping `1..N`
    numbering stable) and advance.
  - **Closing `[SND N/N]`**: After `[SND N/N]` locks, cycle back through any
    `⏭️` deferred slices and `*(1 Open Question)*` callouts, and remove any
    temporary `/tmp/snd_plan_<slug>.md` scratch file.
