---
name: slice-and-dice
description: >-
  Walks through multi-part documents, proposals, technical audits, or code
  architectures sequentially in bite-sized (~60-second) slices ([SND 1/N] ..
  [SND N/N]) with a persistent progress tracker, primary-source verification,
  and dynamic plan updates. Use when reviewing, co-editing, or learning from a
  dense document, RFC, plan, or audit section-by-section without cognitive
  overload, or when invoked via /slice-and-dice, /slice-n-dice, /snd, "slice
  and dice", "slice-n-dice", or "snd". Don't use for single-turn answers (use
  quick-question), prerequisite-graph domain mastery from first principles (use
  graph-learn), pre-drafting Socratic quizzes (use
  distilling-strategies-interactively), or one-shot automated PR diff reports
  (use pr-review).
key_features:
  - Sequential ~60-second slices ([SND 1/N]) with persistent artifact state tracking
  - Pre-flight scope gate when natural slicing exceeds 10 slices
  - Zero blocking choice modals during active slice review
  - Before/After + What Changed edit deltas and split-anchor review comments
  - Dynamic plan evolution with explicit upfront realization callouts
---

# Slice-and-Dice (`SND`)

Walk through dense documents, multi-part proposals, technical audits, or complex
codebases one bite-sized slice at a time (`[SND 1/N]` .. `[SND N/N]`).

Instead of dumping an entire 10-section critique, rewrite, or architectural tour
into a single wall of text—which causes cognitive overload and stalls completion
—partition the work into **sequential `~60-second` slices optimized for
reasonable completeness** and lock each slice interactively before advancing.

---

## Why This Workflow Works

- **Eliminates Wall-of-Text Paralysis**: Reading and reacting to one focused
  `~60-second` slice at a time turns a daunting review or co-authoring task into
  a fast, high-momentum loop.
- **Preserves Conversational Nuance**: Yielding in plain chat during the active
  slice loop (with zero blocking multiple-choice modals) lets the user ask
  follow-up questions, quote specific lines, request partial edits, or steer
  with a single word (`"next"`, `"done"`, `"skip"`).
- **Improves Accuracy Over Time**: Grounding each slice in primary source code
  as you go—and explicitly updating the plan when you discover something new—
  catches false assumptions before they propagate into later sections.

---

## Workflow Overview

Copy this checklist to track the lifecycle of an `SND` walkthrough:

- [ ] **Phase 1: Partition, Scope Gate (if `N > 10`), & Stage** → Partition the
      target into coherent `~60-second` slices (`[SND 1/N]` .. `[SND N/N]`) for
      reasonable completeness. If `N > 10`, halt at the Pre-Flight Scope Gate to
      calibrate scope; otherwise stage the persistent working artifact and
      present **only `[SND 1/N]`**.
- [ ] **Phase 2: Single-Slice Review Loop** → Present the active slice with
      exact deep-links, primary-source verification, and properly formatted
      deltas or comments; yield in plain chat.
- [ ] **Phase 3: Dynamic Plan Evolution** → Adapt slices on the fly in the
      working artifact's Progress Tracker as the user steers or as you
      independently discover new facts (stating any independent realizations or
      plan updates **explicitly upfront**).
- [ ] **Phase 4: Lock & Wrap-Up** → Flip each confirmed slice to `☑️`
      (**Locked**), advance to `[SND K+1/N]`, and reconcile any deferred open
      questions when `[SND N/N]` locks.

---

## Choosing the Right `SND` Mode

Adapt the slice payload to what the user is trying to accomplish:

| Mode                                      | Typical User Prompt                                          | What Each `[SND K/N]` Slice Contains                                                                       |
| :---------------------------------------- | :----------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------- |
| **1. Document / Proposal Review**         | _"Walk me through this RFC / API doc with SND"_              | Exact anchor quote + primary-source check + copy-pasteable `text` comment(s) (or **"No comment needed"**). |
| **2. Co-Authoring & Iterative Editing**   | _"Break these edits / proposals into an SND"_                | Target section link + **`Before` → `After` + `What Changed`** (`Added` / `Changed` / `Removed`) delta.     |
| **3. Technical Walkthrough ("Teach Me")** | _"Do a slice-n-dice over these issues teaching me as we go"_ | Focused explanation + primary-source code snippets + space for deep-dive Q&A before locking.               |

---

## Core Protocol & Invariants

### 1. Completeness-Driven `~60-Second` Slices & The `N > 10` Scope Gate

- **Size by Cognitive Unit, Not Arbitrary Quota**:
  - Partition the target top-to-bottom so each slice (`[SND 1/N]` ..
    `[SND N/N]`) covers **one coherent topic or decision** sized to roughly **60
    seconds** of reading and reaction, optimizing for **reasonable
    completeness** across the requested scope.
  - Never force a large document into an arbitrary fixed slice count: neither
    over-stuff 3–4 orthogonal debates into a single bloated slice nor silently
    drop sections just to keep `N` small. Conversely, fold trivial 1-line fixes
    that share a single theme into one `~60-second` slice rather than inflating
    `N`.
- **Mandatory Pre-Flight Scope Gate When `N > 10`**:
  - Linear walkthroughs beyond ~10 turns hit human review fatigue and context
    degradation.
  - If natural `~60-second` slicing yields **`N <= 10`**, stage the working
    artifact and present `[SND 1/N]` immediately.
  - If natural `~60-second` slicing yields **`N > 10`**, **halt before starting
    `[SND 1/N]`**. Present the grouped slice outline in chat so the user can see
    the full landscape, and prompt the user (using an interactive choice modal
    such as `ask_question` / `AskUserQuestion` if available, or a numbered list
    in chat) with three options:
    1. `(Recommended) Focus on {sub_area} first ({k} slices)` — slices the
       highest-leverage part at full fidelity now, leaving remaining chapters as
       clean follow-up `SND` passes.
    2. `Run a high-level Macro-SND across the whole target (~6–8 architectural slices)`
       — one slice per major section or theme, zooming into fine-grained slicing
       only where needed.
    3. `Proceed with all {n} slices in one pass` — explicit escape hatch when
       exhaustive linear coverage is genuinely wanted.

### 2. Persistent Working Artifact as State of Truth

- Pin the canonical **Slice-and-Dice (`SND`) Progress Tracker** (including
  locked states, cross-slice ripple reminders, and deferred open questions) at
  the top of a persistent working Markdown artifact (in the session artifact
  directory if available, or `/tmp/snd_plan_<slug>.md` in standalone CLI
  sessions—never create untracked files in the repository worktree or inject the
  tracker into a tracked repository file).
- **Why**: Chat-only trackers drift over multi-turn sessions or across context
  compaction, whereas a CLI/JSON state wrapper adds per-turn subprocess latency
  and rigid schema friction during dynamic re-slicing. Updating the top ~15
  lines of the working `.md` artifact via standard file-edit tools gives
  compaction-proof state with zero CLI overhead.
- **Lazy Slice Drafting (Keep Turn 1 Fast)**: Keep the working artifact
  lightweight on Turn 1—record only the Progress Tracker and 1-line slice
  titles/notes. Draft each slice's full `Before`/`After` delta or review
  comments lazily when `[SND K/N]` becomes active so Turn 1 stays fast and
  earlier pivots never waste pre-drafted work.
- Update the working artifact's Progress Tracker before each response and echo
  the current tracker block at the top of every chat turn:
  - `☑️ [SND 1/N] {slice_title}` — **Locked**
  - **`[-] [SND 2/N] {slice_title}`** 👈 _Reviewing now_
  - `[ ] [SND 3/N] {slice_title}`

### 3. Zero Blocking Choice Modals During the Active Slice Loop

- Once `[SND 1/N]` begins (after any `N > 10` pre-flight scope gate), **never**
  block an active `SND` turn with an interactive multiple-choice modal tool
  (`ask_question`, `AskUserQuestion`).
- **Why**: Blocking modals force rigid radio-button selection and prevent the
  user from quoting inline lines, asking "why" questions, proposing hybrid
  wording, or replying with quick freeform shorthands (`"next"`, `"done"`,
  `"skip"`, `"remove A, keep B"`).
- Always end active slice turns in plain chat with a lightweight one-line prompt
  (e.g.,
  _`How does [SND 2/5] look? Reply with tweaks, questions, "skip", or "next".`_).

### 4. Single-Slice Focus & Deep-Link Anchoring

- Present **only the active `[-] [SND K/N]` slice** in chat per turn. Never dump
  the full content of upcoming slices (`[SND K+1..N]`) into the chat message.
- Anchor every active slice with clickable deep-links so the user can jump
  straight to the context:
  - **Local / Repo File or Working Artifact**: Include exact line-range links
    (e.g., `path/to/file.md#L18-L32`).
  - **External Document (Web Doc / RFC / Issue)**: Include the exact section
    heading URL (`#heading=...`) plus a verbatim **📌 Exact Text to Anchor On**
    quote so comments can be anchored or located without searching.

### 5. Primary-Source Grounding & Explicit `"No Comment Needed"` Slices

- Before presenting a slice's critique, proposed edit, or technical explanation,
  verify every technical claim directly against the primary source code—never
  guess or extrapolate from earlier summary notes.
- If primary-source inspection confirms the target document's claim holds up (or
  overturns an earlier draft concern), **do not invent nitpicks**. Explicitly
  mark the slice **`✅ Verdict: No comment needed (holds up in source)`**,
  briefly cite the verifying code, and let the user lock and advance cleanly.

### 6. Formatting Candidate Edits & Review Comments

- **Candidate Text Replacements (`Before` → `After` + `What Changed`)**:
  - Whenever an `SND` slice proposes editing or replacing existing text in a
    document or artifact, **never** show the proposed replacement (`After`) in
    isolation. Always present three parts:
    1. **Current Text (`Before`)**
    2. **Proposed Text (`After`)**
    3. **What Changed (`Added` / `Changed` / `Removed`)** — a concise bullet
       breakdown of the exact delta so the user can evaluate the change in
       seconds without mentally diffing two paragraphs.
- **Candidate Review Comments (`text` Fence & Split Anchors)**:
  - Format candidate review comments inside a copy-pasteable `text` code fence
    with **blank lines between paragraphs or numbered points** for easy reading
    and scanning (never cram multi-point feedback into a single dense blockquote
    paragraph).
  - **Split Distinct Points into Separate Comments (`Comment KA`,
    `Comment KB`)**: When a slice surfaces two distinct points that map to
    different sentences or bullets in the target document, split them into
    `Comment KA` and `Comment KB` with separate verbatim anchor phrases so each
    comment thread can be replied to and resolved independently by the document
    author.

---

## Dynamic Plan Evolution (User-Driven & Agent-Driven)

An `SND` plan is a living map in the working `.md` artifact, not a rigid
railroad track. Both the user and the agent can—and should—adapt the plan
mid-walkthrough as understanding deepens.

### User-Driven Steering Mid-Walkthrough

1. **Zooming In ("Staying in `[SND K/N]`")**:
   - If the user asks a conceptual question, requests concrete code examples, or
     wants to debate a sub-point before locking
     (`"let's stay in SND 1/6 — go deeper into #1"`), keep `[SND K/N]` marked as
     `[-] Reviewing now`, unpack the requested detail or source code, and wait
     to advance until the user signals `"next"` or `"done"`.
2. **Splitting, Merging, or Re-Slicing (Keeping `1..N` Stable)**:
   - Keep base slice numbers `1..N` stable once `[SND 1/N]` begins so
     cross-slice ripple reminders (`[ ] [SND 4/5] ...`) never point to shifted
     indices.
   - If a slice turns out to contain two orthogonal debates, split it using
     letter suffixes (`[SND 2A/5]` and `[SND 2B/5]`) rather than incrementing
     `N`.
   - If a decision in `[SND K/N]` renders a later queued slice moot, mark that
     later slice inline as `*(Merged into [SND K/N])*` in the tracker so you
     don't waste a turn on it later.
3. **Cross-Slice Ripple Notes & Loud Open Questions**:
   - **Ripple Reminders**: When an edit in `[SND K/N]` requires a follow-up
     adjustment in a later section (`"remind me to update Section 4 for this"`),
     append an inline reminder tag onto that queued slice in the Progress
     Tracker (`[ ] [SND 4/5] ... *(Reminder: align with Section 1 rename)*`) and
     surface it when `[SND 4/5]` becomes active.
   - **Deferred Open Questions**: When the user flags an unresolved strategic
     question they want to revisit later, insert a prominent callout block
     (`> [!WARNING]` / `Open Question`) directly into the working artifact and
     note `*(1 Open Question)*` next to the locked slice in the Progress
     Tracker. This keeps walkthrough momentum moving without losing the thread.

### Agent-Driven Realizations & Proactive Plan Updates

As you verify source code, synthesize arguments, or incorporate user feedback
while moving from slice to slice, **actively sanity-check your own earlier plan
and draft conclusions**.

It is a **strong positive signal** when you figure something out mid-walkthrough
—such as realizing an earlier critique was wrong, discovering a cross-file
constraint that changes a recommendation, or noticing that remaining slices
`[SND K+1..N]` need to be re-ordered, split, or expanded.

> [!IMPORTANT]
>
> **State Independent Realizations & Plan Updates Explicitly Upfront**: Never
> silently mutate the slice plan or quietly swap out a recommendation. Whenever
> you change your mind, overturn an earlier draft point, or update the remaining
> slices (`[SND K..N]`), place an explicit **Realization / Plan Update** callout
> at the top of your turn (right under the Progress Tracker) stating:
>
> 1. **What you realized / where you changed your mind** (citing the exact
>    primary-source code or locked decision that triggered the realization).
> 2. **How you updated the plan or recommendation** (which queued slice was
>    revised, split, merged, added, or dropped).
> 3. **Confirm Before Reopening Locked Slices (`☑️`)**: If a new finding
>    contradicts an earlier slice that is already **Locked** (`☑️`), flag the
>    contradiction in the callout and ask the user whether to reopen that slice
>    —never overwrite a locked decision silently.

---

## Lock & Wrap-Up

- **Applying Confirmed Edits (Mode 2)**: As soon as the user confirms
  `[SND K/N]` (e.g., `"next"`, `"apply"`, or `"looks good"`), write the approved
  `After` text to the target document or draft artifact before flipping
  `[SND K/N]` to `☑️` (**Locked**) and presenting `[SND K+1/N]`.
- **Closing `[SND N/N]`**: When the final slice locks, reconcile any remaining
  `*(1 Open Question)*` callouts with the user and remove any temporary scratch
  tracker file (such as `/tmp/snd_plan.md`) so the repository stays clean.

---

## Turn Templates

### Template A: Co-Authoring / Edit Slice (`Before` → `After` + `What Changed`)

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

- `☑️ [SND 1/5] Executive Summary & Goals` — **Locked**
- **`[-] [SND 2/5] Rollout Criteria & Confidence Gates`** 👈 *Reviewing now*
- `[ ] [SND 3/5] Cross-Package API Boundaries`
- `[ ] [SND 4/5] Testing & Corpus Verification Strategy`
- `[ ] [SND 5/5] 2027 Horizon & Non-Goals`

---

### `[-] [SND 2/5]` Rollout Criteria & Confidence Gates

- **Target Section**: `docs/rollout_plan.md#L42-L50`

#### 1. Current Text (`Before`)

```text
Now that the opt-in flag and browser CI are merged, burn down any remaining
rendering or stability blockers before flipping the default on main.
```

#### 2. Proposed Text (`After`)

```text
With the opt-in flag and browser CI merged:
1. **Publish Opt-In Guidance**: Document the opt-in configuration and automatic
   fallback behavior for early adopters.
2. **Execute Default-On Checklist**: Define and burn down the concrete
   benchmark and stability gates required before flipping the default on main.
```

#### 3. What Changed (`Added` / `Changed` / `Removed`)

- **Added**:
  1. Explicit developer documentation deliverable for the opt-in flag.
  2. Explicit Default-On Checklist step separating early-adopter opt-in from
     default-on flip criteria.
- **Changed**:
  - Replaced the generic *"burn down any remaining blockers"* phrasing with the
    two concrete milestones above.
- **Removed**:
  - Nothing substantive removed.

How does **`[SND 2/5]`** look? (Reply with tweaks, `"skip"` to keep `Before`,
or `"next"` to apply `After` and advance to `[SND 3/5]`.)
````

### Template B: Document Review Slice with Explicit Agent Realization & Split Anchors

````markdown
### Slice-and-Dice (`SND`) Progress Tracker

- `☑️ [SND 1/5] Summary & Phases Overview` — **Locked**
- **`[-] [SND 2/5] Client Constructors & Credential Wiring`** 👈 *Reviewing now*
- `[ ] [SND 3/5] Shared Type Inventory` *(Updated: verified Row 4 in source)*
- `[ ] [SND 4/5] Cross-Platform Implications`
- `[ ] [SND 5/5] Release & Versioning`

> [!NOTE]
>
> **Where I Changed My Mind & Updated the Plan**: While checking
> `lib/src/client.dart#L140-L152` for `[SND 2/5]`, I realized my initial draft
> critique against the 3-parameter constructor was wrong: passing `client:`
> disables internal lifecycle closure, whereas `clientFactory:` grants ownership
> so `.close()` tears down the underlying client cleanly. I dropped that draft
> critique below and narrowed `[SND 2/5]` to the two remaining constructor edge
> cases.

---

### `[-] [SND 2/5]` Client Constructors & Credential Wiring

- **Doc Section**: `Proposal → Credentials & Client Construction`

#### 💬 Comment 2A (Optional `registrar` Parameter)

- **📌 Exact Text to Anchor On**:
  > `CoreWeb.registerWith(null); // registrar is dynamic`

```text
Could we make the parameter optional (`static void registerWith([Object? registrar])`) so pure-Dart callers don't have to pass `null` explicitly?

In `lib/src/core_web.dart:71`, `registerWith` never reads the `registrar` argument—it only sets the default platform instance.
```

#### 💬 Comment 2B (Default Instance Initialization)

- **📌 Exact Text to Anchor On**:
  > `Pure-Dart consumers import the contracts from common directly.`

```text
In `platform_interface.dart:30`, `_instance` currently defaults to `MethodChannelImpl()`.

Once the base platform class moves to the pure-Dart package while `MethodChannelImpl` stays in the framework package, how will `_instance` be defaulted on mobile when no explicit registration call runs?
```

How do **Comment 2A** and **Comment 2B** look? (Reply with edits, `"skip"`, or
`"next"` to lock `[SND 2/5]` and move to `[SND 3/5]`.)
````
