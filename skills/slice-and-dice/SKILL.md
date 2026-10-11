---
name: slice-and-dice
description: >-
  Walks through multi-part documents, proposals, technical audits, issue
  backlogs, or codebases in bite-sized (~60-second) slices ([SND 1/N] ..
  [SND N/N]) with a persistent progress tracker, auditable Source anchors,
  two-tier transition footers, and dynamic plan updates. Use when learning or
  understanding material without being quizzed, reviewing, co-editing, or
  triaging a dense document, RFC, plan, or audit slice-by-slice without
  cognitive overload, or when invoked via /slice-and-dice, /slice-n-dice, /snd,
  "slice and dice", or "slice-n-dice". Don't use for single-turn answers (use
  quick-question), active mastery quizzing with hard comprehension gates (use
  quiz-me), branching design decision trees (use grilling or
  clarify-confirm-continue), or one-shot automated PR diff reports (use
  pr-review).
key_features:
  - Bite-sized ~60-second slices ([SND 1/N]) for unquizzed learning, review, and co-editing
  - Pre-flight scope gate (N > 10) and hard boundary against branching decision trees
  - Two-tier action footers preventing the "next, next, next" suggestion-skipping trap
  - 4 clean tracker states ([ ], [-], ⏳ Deferred, ☑️ Done) with zero "skip"/"drop" ambiguity
  - Dynamic plan evolution with explicit upfront realization callouts
---

# Slice-and-Dice (`SND`)

Walk through dense documents, multi-part proposals, technical audits, or
codebase subsystems one `~60-second` slice at a time (`[SND 1/N]` ..
`[SND N/N]`)—whether the user wants an unquizzed learning tour, a sharp review,
or live inline edits along the way.

---

## Workflow Overview

- [ ] **Phase 1: Ground, Check Topology & Scope Gate (`N > 10`)** → Partition
      into `~60-second` linear or thematic slices (`[SND 1/N]` .. `[SND N/N]`)
      with `Source` anchors. Halt if the task is a branching decision tree or if
      `N > 10`; otherwise stage the working artifact and present **only
      `[SND 1/N]`**.
- [ ] **Phase 2: Single-Slice Review Loop** → Present `[SND K/N]` with
      deep-links, source checks, formatted deltas/comments (see
      [references/slice_templates.md](references/slice_templates.md)), and the
      **Two-Tier Action Footer**; yield in plain chat.
- [ ] **Phase 3: Dynamic Plan Evolution** → Stay on `[-] [SND K/N]` whenever the
      user asks questions or brainstorms; state source realizations **upfront**.
- [ ] **Phase 4: Lock (`☑️`), Defer (`⏳`), & Wrap-Up** → Record each slice's
      outcome (`☑️ Applied edit`, `☑️ Kept as-is`, `☑️ Added note`) or defer it
      (`⏳`); cycle back through all `⏳` deferred slices after `[SND N/N]`.

---

## Relationship to `/quiz-me` & `SND` Modes

Human conversation is linear (1 active item per turn). `/slice-and-dice` and
`/quiz-me` share the same 1-item-per-turn pacing and persistent Markdown
tracker, differing on **Hard Comprehension Gates**:

| Dimension                       | `/slice-and-dice` (`SND` — Unquizzed Walkthrough, Review, & Co-Edit)                                          | `/quiz-me` (`SND` + Hard Comprehension Gates)                                                             |
| :------------------------------ | :------------------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------- |
| **User Goal**                   | Understand/learn without being quizzed, review/critique, or co-edit and lock concrete changes as you go.      | Verify you truly know and have internalized the causal mechanics via active scenario and transfer checks. |
| **1. Sequential (`A → B`)**     | Walks top-to-bottom through a narrative RFC, slide deck, or document (`[SND 1/N]` .. `[SND N/N]`).            | Walks step-by-step through a linear mastery checklist (`[1/N]`) when `0` convergence nodes exist.         |
| **2. Thematic (`{A,B},{C,D}`)** | Groups scattered audit findings, issue backlogs, or multi-file changes by theme or blast radius.              | Groups related concepts by subsystem (or scopes `> 12` concepts to one foundational cluster first).       |
| **3. Convergent Graph / Tree**  | **Out of scope** if decisions branch (route branching decision trees to `grilling`); use `/quiz-me` for DAGs. | Renders a live color-coded Mermaid prerequisite DAG (`✅`, `🎯`, `🔒`) where `A` and `B` unlock `C`.      |

Adapt each `[SND K/N]` slice payload to the user's goal (which can blend
mid-session as learning sparks edits):

| Mode                                    | Typical User Prompt                                      | What Each `[SND K/N]` Slice Contains                                                                                   |
| :-------------------------------------- | :------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------- |
| **1. Unquizzed Learning & Review**      | _"Walk me through this RFC / subsystem with SND"_        | Concise explanation + exact anchor quote + primary-source check + candidate `text` comment (or **No comment needed**). |
| **2. Co-Authoring & Iterative Editing** | _"Break these edits / slides into an SND"_               | Target `Source` link + **`Before` → `After` + `What Changed`** (`Added` / `Changed` / `Removed`) delta.                |
| **3. Multi-Item Audit / Issue Triage**  | _"Do a slice-n-dice over these audit findings / issues"_ | Thematic item + primary `Source` proof + concrete recommendation (`accept` vs. `keep as-is` vs. `defer`).              |

---

## Core Protocol & Invariants

### 1. `~60-Second` Slices, Decision-Tree Boundary, & The `N > 10` Scope Gate

- **Size (`~60s`) & Order Linearly or Thematically**:
  - Partition the target so each slice (`[SND 1/N]` .. `[SND N/N]`) covers **one
    coherent topic or section** sized to ~60 seconds of reading and reaction,
    optimizing for **reasonable completeness**. Never over-stuff orthogonal
    debates into one bloated slice or silently drop sections to keep `N` small;
    fold trivial 1-line fixes sharing a theme together.
  - **Hard Boundary Against Branching Decision Trees**: `slice-and-dice` walks
    through a known collection of sections, slides, files, or items (`1..N`). If
    the task is actually an open-ended **branching decision tree** where
    choosing Option A vs. Option B creates different downstream branches, halt
    up front and recommend a decision-tree workflow (`grilling` /
    `clarify-confirm-continue`).
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

### 2. Persistent Working Artifact, 4 Tracker States, & Auditable `Source` Anchors

- Pin the canonical **Slice-and-Dice (`SND`) Progress Tracker** (with each
  slice's **auditable `Source` anchor**—such as `path/to/file.ext#L18-L45` or
  `Doc §2.1`) at the top of a persistent working Markdown artifact (in the
  session artifact directory or `/tmp/snd_plan_<slug>.md` in standalone CLI
  sessions—never create untracked files in the repo worktree or inject tracker
  lines into tracked files).
- **Lazy Slice Drafting (Keep Turn 1 Fast)**: Record only the Progress Tracker
  (with `Source` anchors) and 1-line slice notes on Turn 1; draft each slice's
  full `Before`/`After` delta or review comments lazily when `[SND K/N]` is
  active.
- Every slice in the tracker uses one of **4 states** (never use ambiguous
  `"skip"` or delete slices with `"drop"`):
  - `☑️ [SND 1/N] {title} (Source: {src})` — **Done (Applied edit)**
  - `☑️ [SND 2/N] {title} (Source: {src})` — **Done (Kept as-is)**
  - `⏳ [SND 3/N] {title} (Source: {src})` — **Deferred (Revisit after
    `[SND N/N]`)**
  - **`[-] [SND 4/N] {title} (Source: {src})`** 👈 _Active now_
  - `[ ] [SND 5/N] {title} (Source: {src})`

### 3. Single-Slice Focus, Primary-Source Grounding, & Formatting

- **One Active Slice per Turn & Zero Active-Loop Modals**: Present **only
  `[-] [SND K/N]`** in chat with clickable line-range
  (`path/to/file.md#L18-L32`) or `#heading=...` deep-links. Once `[SND 1/N]`
  begins, **never** call `ask_question` / `AskUserQuestion`—always yield in
  plain chat.
- **Direct Primary-Source Verification**: Verify every technical claim against
  primary source code before presenting a slice. When the target document is
  self-contained (such as a standalone rollout plan making no external code
  claims), read it directly without speculative `ls` or `git log` probes. If
  source inspection confirms the document holds up, do not invent nitpicks—mark
  it **`✅ Verdict: No comment needed (holds up in source)`**.
- **Formatting Candidate Edits & Comments** (see
  [references/slice_templates.md](references/slice_templates.md)):
  - **Candidate Edits (`Before` → `After` + `What Changed`)**: Always show
    **Current Text (`Before`)**, **Proposed Text (`After`)**, and **What Changed
    (`Added` / `Changed` / `Removed`)**.
  - **Candidate Review Comments (`text` Fence & Split Anchors)**: Use a
    copy-pasteable `text` code fence with blank lines between paragraphs; split
    distinct points on different sentences into `Comment KA` and `Comment KB`.

---

## 4. The 4 Natural Transitions, Two-Tier Action Footers, & Dynamic Evolution

Never offer `"skip"` (which confuses ignoring a suggestion with deferring) or
`"drop"` (slices `1..N` are never deleted from the tracker—even if the user says
_"delete Slide 7 and move on"_, that completes `[SND 7/12]` as
`☑️ Done (Deleted slide)`). Every active slice ends with a **Two-Tier Action
Footer** so the user never accidentally rubber-stamps or ignores a suggestion by
typing `"next"`:

1. **Case A Footer — Read-Only / No Suggestions or Questions Offered** (pure
   learning walkthrough or `No comment needed`):
   - End with:
     `👉 Next: Say "ok" / "next" to advance, "defer" to revisit at the end, or reply to zoom in.`
2. **Case B Footer — Agent Offers Suggestions, Edits, Comments, or Questions**:
   - End with an explicit choice between accepting vs. keeping the status quo:
     `👉 Decision needed: Say "accept" (or "accept with <tweak>"), "keep as-is" (ignore suggestion & advance), "defer" (revisit at end), or reply to zoom in.`
   - **Ambiguous `"next"` / `"ok"` Guardrail**: If a slice contains proposed
     edits or open questions (Case B) and the user replies with a bare `"next"`
     or `"ok"`, **do not guess**—ask a 1-line check (_"Before moving to
     `[SND K+1/N]`, should I apply that suggestion or keep the status quo?"_).
3. **The 4 User Transitions on Any Slice**:
   - **Move On (`"ok"` in Case A; `"accept"` or `"keep as-is"` in Case B)** →
     Mark `☑️ [SND K/N]` (**Done — Applied edit** or **Done — Kept as-is**) and
     present `[SND K+1/N]`.
   - **Move On With Notes / Edits (`"ok, but note XYZ"`,
     `"delete this slide and move on"`)** → Apply the note/edit/deletion to the
     target artifact, mark `☑️ [SND K/N]` (**Done — `<action recorded>`**), and
     present `[SND K+1/N]`.
   - **Defer Until End (`"defer"`, `"come back to this"`)** → Mark
     `⏳ [SND K/N]` (**Deferred — revisit after `[SND N/N]`**) and advance to
     `[SND K+1/N]`. Automatically cycle back through all `⏳` slices after
     `[SND N/N]`.
   - **Zoom In / Discuss (Default for any question, pushback, or brainstorm)** →
     Keep `[SND K/N]` marked `[-]` while unpacking, debating, or editing in
     place until the user signals moving on or deferring.
4. **Dynamic Plan Evolution & Upfront Realizations**:
   - Keep base slice numbers `1..N` stable (`[SND 2A/5]`, `[SND 2B/5]` on
     splits; `*(Merged into [SND K/N])*` on merges) and record cross-slice
     ripple notes inline on the tracker.
   - Whenever primary-source checks overturn an earlier draft point or reshape
     remaining slices, place an explicit **Realization / Plan Update** callout
     right below the Progress Tracker citing the source proof, and **ask before
     reopening** any already-completed (`☑️`) slice.
